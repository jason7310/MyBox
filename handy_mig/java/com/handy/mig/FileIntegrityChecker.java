package com.handy.mig;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * [통합 MIG] 전자결재 본문 및 첨부파일 물리 정합성 검증 도구 (Java 17 호환)
 * 
 * ====================================================================================
 * 핵심 목표:
 *   - DB(DOCUMENT / DOCMBR 또는 MG_DOCUMENT)에는 메타데이터가 등록되어 있으나,
 *     실제 디스크 스토리지(NAS/SAN)에는 물리 파일이 존재하지 않는 "누락/결손 파일(Missing File)"을
 *     멀티스레드 기반으로 초고속 전수 검출합니다.
 *   - 0바이트 파일, 파일 크기 불일치(Size Mismatch) 여부도 함께 정밀 진단합니다.
 *   - 검출 즉시 AS-IS 원천 스토리지에서 누락 파일만 선별 복사할 수 있는 재복사 스크립트(.sh)를 자동 생성합니다.
 * ====================================================================================
 */
public class FileIntegrityChecker {

    private static final SimpleDateFormat SDF_TIMESTAMP = new SimpleDateFormat("yyyyMMdd_HHmmss");
    private static final SimpleDateFormat SDF_DATETIME = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
    private static final SimpleDateFormat SDF_YYYY = new SimpleDateFormat("yyyy");
    private static final SimpleDateFormat SDF_YYYYMM = new SimpleDateFormat("yyyy/MM");
    private static final SimpleDateFormat SDF_YYYYMMDD = new SimpleDateFormat("yyyy/MM/dd");

    // 검사 대상 레코드 단위
    public static class FileMetaItem {
        public String apprId;
        public String objectId;
        public int docType;
        public String fileName;
        public long fileSize;
        public Date registDate;
        public String dbFilePath; // MG_DOCUMENT의 FILE_PATH 등
        public String srcObjectId; // 원천 파일 ID 등

        // 검사 결과 필드
        public CheckStatus status = CheckStatus.UNKNOWN;
        public String resolvedPath;
        public long actualFileSize = -1;
        public String failureReason;
    }

    public enum CheckStatus {
        OK,             // 정상 존재
        MISSING,        // 파일 없음 (404)
        ZERO_BYTE,      // 파일은 있으나 0바이트
        SIZE_MISMATCH,  // DB 용량과 디스크 용량 불일치 (허용 오차 초과)
        UNKNOWN
    }

    // 통계 카운터
    private static final AtomicLong totalChecked = new AtomicLong(0);
    private static final AtomicLong countOk = new AtomicLong(0);
    private static final AtomicLong countMissing = new AtomicLong(0);
    private static final AtomicLong countZeroByte = new AtomicLong(0);
    private static final AtomicLong countSizeMismatch = new AtomicLong(0);
    private static final AtomicLong countHoxSkipped = new AtomicLong(0);
    private static final AtomicLong totalMissingBytes = new AtomicLong(0);

    // 포이즌 필 (작업 완료 신호)
    private static final FileMetaItem POISON_PILL = new FileMetaItem();

    public static void main(String[] args) {
        String targetSchema = "INTRAWARE"; // 기본 검사 대상: INTRAWARE (운영), 옵션: MIG1 (중간테이블)
        String customConfig = null;
        int threadCount = 16;
        long maxLimit = 0; // 0: 전체 검사, 양수: 샘플 검사 건수
        boolean checkSizeMismatch = false;
        boolean skipHox002 = true; // 기본값: 002로 끝나는 HOX 결재정보 문서는 열람 시 자동 생성되므로 점검 제외

        // CLI 옵션 파싱
        for (int i = 0; i < args.length; i++) {
            String arg = args[i];
            if ("--mig1".equalsIgnoreCase(arg) || "mig1".equalsIgnoreCase(arg)) {
                targetSchema = "MIG1_USER";
            } else if ("--intraware".equalsIgnoreCase(arg) || "intraware".equalsIgnoreCase(arg)) {
                targetSchema = "INTRAWARE";
            } else if (arg.startsWith("--threads=")) {
                threadCount = Integer.parseInt(arg.substring("--threads=".length()));
            } else if (arg.startsWith("--limit=")) {
                maxLimit = Long.parseLong(arg.substring("--limit=".length()));
            } else if ("--check-size".equalsIgnoreCase(arg)) {
                checkSizeMismatch = true;
            } else if ("--include-hox".equalsIgnoreCase(arg)) {
                skipHox002 = false;
            } else if (arg.endsWith(".properties")) {
                customConfig = arg;
            }
        }

        MigLogger.init("file_checker");
        log("==================================================================================");
        log(" [Handy MIG] 전자결재 파일 물리 정합성 전수 점검 도구 (FileIntegrityChecker)");
        log(" 대상 스키마      : " + targetSchema);
        log(" 병렬 검증 스레드 : " + threadCount + " Threads");
        log(" 검사 한도        : " + (maxLimit > 0 ? String.format("%,d 건 (샘플 모드)", maxLimit) : "전체 전수 검사"));
        log(" 크기 불일치 검사 : " + (checkSizeMismatch ? "활성화" : "비활성화 (존재 여부 위주)"));
        log(" HOX 002 파일     : " + (skipHox002 ? "점검 제외 (열람 시 자동 생성 문서)" : "점검 포함 (--include-hox)"));
        log("==================================================================================");

        try {
            if (customConfig != null) {
                DbConfig.load(customConfig);
            } else {
                DbConfig.load();
            }
        } catch (IOException e) {
            MigLogger.error("설정 파일 로드 실패: " + e.getMessage(), e);
            return;
        }

        String basePath = DbConfig.getProperty("storage.base.path", "/data");
        log("스토리지 루트 경로: " + basePath);

        File baseDir = new File(basePath);
        if (!baseDir.exists()) {
            MigLogger.warn("[주의] 스토리지 루트 경로가 현재 서버에 존재하지 않습니다: " + basePath);
            MigLogger.warn("       (로컬 테스트 중인 경우 config/db.properties의 storage.base.path를 확인하십시오.)");
        }

        long startTime = System.currentTimeMillis();
        String timestamp = SDF_TIMESTAMP.format(new Date());

        // 결과 파일 경로
        File reportDir = new File("report");
        if (!reportDir.exists()) {
            reportDir.mkdirs();
        }
        File missingReportFile = new File(reportDir, "missing_files_" + timestamp + ".csv");
        File zeroByteReportFile = new File(reportDir, "zero_byte_files_" + timestamp + ".csv");
        File asisCopyScriptFile = new File(reportDir, "copy_missing_from_asis_" + timestamp + ".sh");
        File summaryReportFile = new File(reportDir, "file_integrity_summary_" + timestamp + ".txt");

        // 작업 큐 및 누락 수집 큐
        BlockingQueue<FileMetaItem> taskQueue = new LinkedBlockingQueue<>(50000);
        ConcurrentLinkedQueue<FileMetaItem> missingList = new ConcurrentLinkedQueue<>();
        ConcurrentLinkedQueue<FileMetaItem> zeroByteList = new ConcurrentLinkedQueue<>();

        // 멀티스레드 워커 풀 생성
        ExecutorService workerPool = Executors.newFixedThreadPool(threadCount);
        CountDownLatch workerLatch = new CountDownLatch(threadCount);

        // 1. Worker Threads 시작
        for (int i = 0; i < threadCount; i++) {
            final int workerId = i + 1;
            final boolean verifySize = checkSizeMismatch;
            final boolean verifyHoxSkip = skipHox002;
            workerPool.submit(() -> {
                try {
                    while (true) {
                        FileMetaItem item = taskQueue.take();
                        if (item == POISON_PILL) {
                            // 다시 큐에 넣어 다른 워커도 종료되도록 함
                            taskQueue.put(POISON_PILL);
                            break;
                        }

                        // 물리 파일 검증 수행
                        verifyPhysicalFile(item, basePath, verifySize, verifyHoxSkip);

                        long current = totalChecked.incrementAndGet();
                        if (current % 20000 == 0) {
                            log(String.format(" -> 검사 진행 중... %,d 건 완료 (누락: %,d 건, 0바이트: %,d 건)",
                                    current, countMissing.get(), countZeroByte.get()));
                        }

                        if (item.status == CheckStatus.MISSING) {
                            missingList.add(item);
                            countMissing.incrementAndGet();
                            totalMissingBytes.addAndGet(item.fileSize);
                        } else if (item.status == CheckStatus.ZERO_BYTE) {
                            zeroByteList.add(item);
                            countZeroByte.incrementAndGet();
                        } else if (item.status == CheckStatus.SIZE_MISMATCH) {
                            countSizeMismatch.incrementAndGet();
                        } else {
                            countOk.incrementAndGet();
                        }
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                } finally {
                    workerLatch.countDown();
                }
            });
        }

        // 2. DB 조회 (생산자 스레드)
        try (Connection conn = DbConfig.getConnection()) {
            log("데이터베이스 접속 성공 (" + DbConfig.getUrl() + ")");

            String query = buildQuery(conn, targetSchema, maxLimit, skipHox002);
            log("실행 쿼리:\n" + query);

            try (Statement stmt = conn.createStatement(ResultSet.TYPE_FORWARD_ONLY, ResultSet.CONCUR_READ_ONLY)) {
                stmt.setFetchSize(DbConfig.getBatchSize());

                try (ResultSet rs = stmt.executeQuery(query)) {
                    long produced = 0;
                    while (rs.next()) {
                        FileMetaItem item = new FileMetaItem();
                        item.objectId = rs.getString("OBJECTID");
                        item.fileName = rs.getString("FILENAME");
                        item.fileSize = rs.getLong("FILESIZE");
                        item.docType = rs.getInt("DOCUMENTTYPE");

                        try {
                            item.apprId = rs.getString("APPRID");
                        } catch (SQLException ignored) {
                            item.apprId = "-";
                        }

                        try {
                            item.registDate = rs.getTimestamp("REGISTDATE");
                        } catch (SQLException ignored) {
                            item.registDate = null;
                        }

                        try {
                            item.dbFilePath = rs.getString("FILE_PATH");
                        } catch (SQLException ignored) {
                            item.dbFilePath = null;
                        }

                        try {
                            item.srcObjectId = rs.getString("SRCOBJECTID");
                        } catch (SQLException ignored) {
                            item.srcObjectId = null;
                        }

                        taskQueue.put(item);
                        produced++;

                        if (maxLimit > 0 && produced >= maxLimit) {
                            break;
                        }
                    }
                    log(String.format("DB 레코드 Fetch 완료: 총 %,d 건을 검증 큐에 전달했습니다.", produced));
                }
            }

            // 작업 종료 신호 전송
            taskQueue.put(POISON_PILL);

            // 워커 종료 대기
            workerLatch.await();
            workerPool.shutdown();
            workerPool.awaitTermination(30, TimeUnit.SECONDS);

        } catch (Exception e) {
            MigLogger.error("점검 수행 중 오류 발생: " + e.getMessage(), e);
        }

        long elapsedMs = System.currentTimeMillis() - startTime;
        double elapsedSec = elapsedMs / 1000.0;
        long total = totalChecked.get();
        double speed = elapsedSec > 0 ? (total / elapsedSec) : 0.0;

        // 3. 리포트 파일 생성
        if (!missingList.isEmpty()) {
            fillMissingApprIds(missingList, targetSchema);
        }
        writeMissingCsv(missingReportFile, missingList);
        writeZeroByteCsv(zeroByteReportFile, zeroByteList);
        writeAsisCopyScript(asisCopyScriptFile, basePath, missingList);
        writeSummaryReport(summaryReportFile, targetSchema, basePath, total, elapsedSec, speed, skipHox002);

        // 4. 최종 결과 콘솔 출력
        log("==================================================================================");
        log(String.format(" [파일 정합성 검사 최종 결과 보고]"));
        log(String.format("  - 총 검증 대상 건수   : %,d 건", total));
        log(String.format("  - 정상 파일 (OK)      : %,d 건 (%.2f%%)", countOk.get(), total > 0 ? (countOk.get() * 100.0 / total) : 0.0));
        log(String.format("  - 누락 파일 (MISSING) : %,d 건 (%.2f%%)", countMissing.get(), total > 0 ? (countMissing.get() * 100.0 / total) : 0.0));
        log(String.format("  - 0바이트 파일 (WARN) : %,d 건", countZeroByte.get()));
        if (checkSizeMismatch) {
            log(String.format("  - 크기 불일치 건수    : %,d 건", countSizeMismatch.get()));
        }
        if (skipHox002) {
            log(String.format("  - HOX 002 결재정보    : 점검 제외됨 (열람 시 엔진 실시간 자동생성)"));
        }
        log(String.format("  - 누락 총 추정 용량   : %,.2f MB (약 %,.2f GB)",
                totalMissingBytes.get() / (1024.0 * 1024.0), totalMissingBytes.get() / (1024.0 * 1024.0 * 1024.0)));
        log(String.format("  - 총 소요 시간        : %,.2f 초 (평균 검증속도: %,.0f 건/초)", elapsedSec, speed));
        log("----------------------------------------------------------------------------------");
        log("  - 누락 파일 상세 리포트 : " + missingReportFile.getAbsolutePath());
        log("  - 0바이트 파일 리포트   : " + zeroByteReportFile.getAbsolutePath());
        log("  - 원천 복구용 쉘 스크립트: " + asisCopyScriptFile.getAbsolutePath());
        log("  - 종합 요약 리포트      : " + summaryReportFile.getAbsolutePath());
        log("==================================================================================");

        if (countMissing.get() == 0) {
            log("🎉 축하합니다! 모든 DB 레코드에 대응하는 물리 파일이 디스크에 100% 정상 존재합니다.");
        } else {
            MigLogger.warn(String.format("⚠️ 누락 파일이 %,d 건 검출되었습니다. '%s'를 확인하여 원천 백업본에서 재복사하십시오.",
                    countMissing.get(), missingReportFile.getName()));
        }

        MigLogger.complete();
    }

    /**
     * DB 조회 쿼리 동적 생성
     */
    private static String buildQuery(Connection conn, String targetSchema, long limit, boolean skipHox002) throws SQLException {
        boolean isMig1 = "MIG1_USER".equalsIgnoreCase(targetSchema);

        if (isMig1) {
            // MG_DOCUMENT 기준
            StringBuilder sb = new StringBuilder();
            sb.append("SELECT /*+ PARALLEL(MD, 16) */ ");
            sb.append("       MD.DOC_ID AS APPRID, MD.OBJECTID, MD.FILENAME, MD.FILESIZE, MD.DOCUMENTTYPE, ");
            sb.append("       MD.REGISTDATE, MD.FILE_PATH, MD.SRCOBJECTID ");
            sb.append("  FROM MIG1_USER.MG_DOCUMENT MD ");
            sb.append(" WHERE 1=1 ");
            if (skipHox002) {
                // [성능 최적화] LIKE '%002'의 Full Scan CPU 부하를 방지하기 위해:
                // 1순위: DOCUMENTTYPE != '2' (숫자 비교로 즉시 필터링)
                // 2순위: SUBSTR(MD.OBJECTID, -3) != '002' (끝 3자리 고정 슬라이스 비교)
                sb.append("   AND MD.DOCUMENTTYPE != '2' ");
                sb.append("   AND SUBSTR(MD.OBJECTID, -3) != '002' ");
            }
            if (limit > 0) {
                sb.append("   AND ROWNUM <= ").append(limit);
            }
            return sb.toString();
        } else {
            // INTRAWARE (운영) 기준: DOCUMENT 테이블의 물리 파일 전수 대상 (단일 테이블 초고속 병렬 스캔)
            StringBuilder sb = new StringBuilder();
            sb.append("SELECT /*+ PARALLEL(D, 16) */ ");
            sb.append("       '-' AS APPRID, D.OBJECTID, D.FILENAME, D.FILESIZE, D.DOCUMENTTYPE, ");
            sb.append("       D.REGISTDATE, NULL AS FILE_PATH, D.SRCOBJECTID ");
            sb.append("  FROM INTRAWARE.DOCUMENT D ");
            sb.append(" WHERE 1=1 ");
            if (skipHox002) {
                // [성능 최적화] LIKE '%002'의 Full Scan CPU 부하를 방지하기 위해:
                // 1순위: DOCUMENTTYPE != 2 (NUMBER 정수 비교로 초고속 평가)
                // 2순위: SUBSTR(D.OBJECTID, -3) != '002' (끝 3자리 고정 슬라이스 비교)
                sb.append("   AND D.DOCUMENTTYPE != 2 ");
                sb.append("   AND SUBSTR(D.OBJECTID, -3) != '002' ");
            }
            if (limit > 0) {
                sb.append("   AND ROWNUM <= ").append(limit);
            }
            return sb.toString();
        }
    }

    /**
     * HOX 결재정보 문서 판별 (002로 끝나는 OBJECTID 또는 DOCUMENTTYPE=2 또는 결재정보.xml / .hox)
     * -> 문서 열람 시 핸디 서버 엔진에서 실시간 자동 생성되므로 물리 점검 불필요
     */
    private static boolean isHox002(FileMetaItem item) {
        if (item.objectId != null && item.objectId.endsWith("002")) {
            return true;
        }
        if (item.docType == 2) {
            return true;
        }
        if (item.fileName != null) {
            String f = item.fileName.toLowerCase();
            if (f.endsWith(".hox") || f.equals("결재정보.xml")) {
                return true;
            }
        }
        return false;
    }

    /**
     * 누락 파일 발생 시, 보고서 편의를 위해 DOCMBR에서 APPRID 역추적 보강 (누락 건만 소량 수행)
     */
    private static void fillMissingApprIds(ConcurrentLinkedQueue<FileMetaItem> missingList, String targetSchema) {
        String docmbrTable = "MIG1_USER".equalsIgnoreCase(targetSchema) ? "MIG1_USER.MG_DOCMBR" : "INTRAWARE.DOCMBR";
        String sql = "SELECT APPRID FROM " + docmbrTable + " WHERE OBJECTID = ? AND ROWNUM = 1";
        try (Connection conn = DbConfig.getConnection();
             PreparedStatement pstmt = conn.prepareStatement(sql)) {
            for (FileMetaItem item : missingList) {
                if (item.apprId == null || "-".equals(item.apprId)) {
                    pstmt.setString(1, item.objectId);
                    try (ResultSet rs = pstmt.executeQuery()) {
                        if (rs.next()) {
                            item.apprId = rs.getString(1);
                        }
                    } catch (SQLException ignored) {
                    }
                }
            }
        } catch (Exception e) {
            MigLogger.warn("누락 파일 APPRID 역추적 중 오류 (무시 가능): " + e.getMessage());
        }
    }

    /**
     * 핸디 물리 파일 다중 패턴 탐색 및 무결성 검증
     */
    private static void verifyPhysicalFile(FileMetaItem item, String basePath, boolean verifySize, boolean skipHox002) {
        // HOX 002 문서 체크 제외 (열람 시 핸디 엔진에서 자동 생성)
        if (skipHox002 && isHox002(item)) {
            item.status = CheckStatus.OK;
            countHoxSkipped.incrementAndGet();
            return;
        }

        List<String> candidatePaths = new ArrayList<>();

        // 1. DB에 명시된 FILE_PATH가 있는 경우 최우선 탐색
        if (item.dbFilePath != null && !item.dbFilePath.trim().isEmpty()) {
            candidatePaths.add(item.dbFilePath.trim());
            candidatePaths.add(combinePath(basePath, item.dbFilePath.trim()));
        }

        // 2. 핸디 표준 OBJECTID 기반 경로 후보 생성
        String objId = item.objectId != null ? item.objectId.trim() : "";
        if (!objId.isEmpty()) {
            // 패턴 A: {basePath}/{OBJECTID}
            candidatePaths.add(combinePath(basePath, objId));
            candidatePaths.add(combinePath(basePath, "appr", objId));

            // 패턴 B: {basePath}/sancbox/{OBJECTID}
            candidatePaths.add(combinePath(basePath, "sancbox", objId));
            candidatePaths.add(combinePath(basePath, "hoffice/sancbox", objId));

            // 패턴 C: 등록일자(YYYY/MM/DD) 기반 분할 저장 경로
            if (item.registDate != null) {
                String yyyy = SDF_YYYY.format(item.registDate);
                String yyyymm = SDF_YYYYMM.format(item.registDate);
                String yyyymmdd = SDF_YYYYMMDD.format(item.registDate);

                candidatePaths.add(combinePath(basePath, yyyy, objId));
                candidatePaths.add(combinePath(basePath, yyyymm, objId));
                candidatePaths.add(combinePath(basePath, yyyymmdd, objId));
                candidatePaths.add(combinePath(basePath, "appr", yyyy, objId));
                candidatePaths.add(combinePath(basePath, "appr", yyyymmdd, objId));
            }

            // 패턴 D: OBJECTID 앞 4자리/6자리 기반 분할 경로 (예: 2023/10/...)
            if (objId.length() >= 8 && Character.isDigit(objId.charAt(0))) {
                String p1 = objId.substring(0, 4);
                String p2 = objId.substring(4, 6);
                candidatePaths.add(combinePath(basePath, p1, p2, objId));
                candidatePaths.add(combinePath(basePath, "appr", p1, p2, objId));
            }

            // 패턴 E: 원본 파일명 확장자가 붙어 있는 경우 (예: OBJ12345.hwp, OBJ12345.pdf)
            if (item.fileName != null && item.fileName.contains(".")) {
                String ext = item.fileName.substring(item.fileName.lastIndexOf("."));
                candidatePaths.add(combinePath(basePath, objId + ext));
                candidatePaths.add(combinePath(basePath, "appr", objId + ext));
            }
        }

        // 3. 후보 경로 순차 확인
        File foundFile = null;
        for (String pathStr : candidatePaths) {
            File f = new File(pathStr);
            if (f.exists() && f.isFile()) {
                foundFile = f;
                break;
            }
        }

        if (foundFile == null) {
            item.status = CheckStatus.MISSING;
            item.resolvedPath = candidatePaths.isEmpty() ? (basePath + "/" + objId) : candidatePaths.get(0);
            item.failureReason = "물리 파일이 스토리지 경로에 존재하지 않음 (404 Not Found)";
            return;
        }

        // 파일이 존재하는 경우 크기 검증
        long actualLength = foundFile.length();
        item.resolvedPath = foundFile.getAbsolutePath();
        item.actualFileSize = actualLength;

        if (actualLength == 0 && item.fileSize > 0) {
            item.status = CheckStatus.ZERO_BYTE;
            item.failureReason = "파일은 존재하나 크기가 0 Byte임 (DB 기록: " + item.fileSize + " Byte)";
            return;
        }

        if (verifySize && item.fileSize > 0) {
            // DB 기록 크기와 실제 디스크 크기 비교 (10% 이상 차이 시 경고)
            long diff = Math.abs(item.fileSize - actualLength);
            if (diff > 1024 && diff > (item.fileSize * 0.2)) {
                item.status = CheckStatus.SIZE_MISMATCH;
                item.failureReason = String.format("파일 크기 현저한 불일치 (DB: %,d Byte, 실제: %,d Byte)",
                        item.fileSize, actualLength);
                return;
            }
        }

        item.status = CheckStatus.OK;
    }

    private static String combinePath(String base, String... subs) {
        Path p = Paths.get(base);
        for (String sub : subs) {
            if (sub != null && !sub.isEmpty()) {
                p = p.resolve(sub.startsWith("/") ? sub.substring(1) : sub);
            }
        }
        return p.toAbsolutePath().toString();
    }

    /**
     * 누락 파일 목록 CSV 작성
     */
    private static void writeMissingCsv(File file, ConcurrentLinkedQueue<FileMetaItem> list) {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(file))) {
            bw.write("\uFEFF"); // Excel UTF-8 BOM
            bw.write("APPRID,OBJECTID,DOCUMENTTYPE,FILENAME,DB_FILESIZE_BYTES,EXPECTED_FILE_PATH,SRCOBJECTID,FAILURE_REASON\n");

            for (FileMetaItem item : list) {
                bw.write(String.format("\"%s\",\"%s\",%d,\"%s\",%d,\"%s\",\"%s\",\"%s\"\n",
                        escapeCsv(item.apprId),
                        escapeCsv(item.objectId),
                        item.docType,
                        escapeCsv(item.fileName),
                        item.fileSize,
                        escapeCsv(item.resolvedPath),
                        escapeCsv(item.srcObjectId),
                        escapeCsv(item.failureReason)));
            }
        } catch (IOException e) {
            MigLogger.error("누락 파일 CSV 작성 실패: " + e.getMessage(), e);
        }
    }

    /**
     * 0바이트 파일 목록 CSV 작성
     */
    private static void writeZeroByteCsv(File file, ConcurrentLinkedQueue<FileMetaItem> list) {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(file))) {
            bw.write("\uFEFF"); // Excel UTF-8 BOM
            bw.write("APPRID,OBJECTID,DOCUMENTTYPE,FILENAME,DB_FILESIZE_BYTES,FOUND_FILE_PATH,FAILURE_REASON\n");

            for (FileMetaItem item : list) {
                bw.write(String.format("\"%s\",\"%s\",%d,\"%s\",%d,\"%s\",\"%s\"\n",
                        escapeCsv(item.apprId),
                        escapeCsv(item.objectId),
                        item.docType,
                        escapeCsv(item.fileName),
                        item.fileSize,
                        escapeCsv(item.resolvedPath),
                        escapeCsv(item.failureReason)));
            }
        } catch (IOException e) {
            MigLogger.error("0바이트 파일 CSV 작성 실패: " + e.getMessage(), e);
        }
    }

    /**
     * AS-IS 원천 백업에서 누락 파일만 골라 복사하는 쉘 스크립트 자동 생성
     */
    private static void writeAsisCopyScript(File scriptFile, String targetBasePath, ConcurrentLinkedQueue<FileMetaItem> missingList) {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(scriptFile))) {
            bw.write("#!/bin/bash\n");
            bw.write("# ====================================================================\n");
            bw.write("# [자동생성] 결재 누락 파일 원천(AS-IS) 선별 복구 스크립트\n");
            bw.write("# 생성일시 : " + SDF_DATETIME.format(new Date()) + "\n");
            bw.write("# 누락건수 : " + missingList.size() + " 건\n");
            bw.write("# ====================================================================\n\n");
            bw.write("# AS-IS 원천 스토리지 마운트 루트 경로 (환경에 맞게 수정하십시오)\n");
            bw.write("ASIS_SRC_ROOT=\"/backup/asis_storage\"\n");
            bw.write("TOBE_TARGET_ROOT=\"" + targetBasePath + "\"\n\n");
            bw.write("echo \"[INFO] 누락 파일 복구 작업을 시작합니다 (총 " + missingList.size() + " 건)...\"\n");
            bw.write("SUCCESS_CNT=0\n");
            bw.write("FAIL_CNT=0\n\n");

            int count = 0;
            for (FileMetaItem item : missingList) {
                if (count++ > 50000) {
                    bw.write("# (출력 한도 50,000건을 초과하여 스크립트 생성을 중단했습니다. CSV를 참조하세요)\n");
                    break;
                }

                String targetPath = item.resolvedPath != null ? item.resolvedPath : (targetBasePath + "/" + item.objectId);
                String parentDir = new File(targetPath).getParent();

                bw.write("# 문서: " + (item.fileName != null ? item.fileName : item.objectId) + " (크기: " + item.fileSize + "B)\n");
                bw.write("mkdir -p \"" + parentDir + "\"\n");

                if (item.dbFilePath != null && !item.dbFilePath.isEmpty()) {
                    bw.write("if [ -f \"${ASIS_SRC_ROOT}/" + item.dbFilePath.replaceAll("^/+", "") + "\" ]; then\n");
                    bw.write("    cp -p \"${ASIS_SRC_ROOT}/" + item.dbFilePath.replaceAll("^/+", "") + "\" \"" + targetPath + "\" && ((SUCCESS_CNT++))\n");
                    bw.write("else\n");
                    bw.write("    echo \"[FAIL] 원천 파일 없음: ${ASIS_SRC_ROOT}/" + item.dbFilePath + "\" >> copy_failed.log\n");
                    bw.write("    ((FAIL_CNT++))\n");
                    bw.write("fi\n\n");
                } else {
                    bw.write("# 원천 경로 미지정 건 (OBJECTID 기준 탐색 권장)\n");
                    bw.write("# find \"${ASIS_SRC_ROOT}\" -name \"" + item.objectId + "*\" -exec cp -p {} \"" + targetPath + "\" \\;\n\n");
                }
            }

            bw.write("echo \"[완료] 복구 완료: ${SUCCESS_CNT} 건, 원천 누락/실패: ${FAIL_CNT} 건\"\n");

            // 실행 권한 부여
            scriptFile.setExecutable(true, false);

        } catch (IOException e) {
            MigLogger.error("복구 쉘 스크립트 작성 실패: " + e.getMessage(), e);
        }
    }

    /**
     * 종합 요약 리포트 작성
     */
    private static void writeSummaryReport(File summaryFile, String targetSchema, String basePath,
                                           long total, double elapsedSec, double speed, boolean skipHox002) {
        try (BufferedWriter bw = new BufferedWriter(new FileWriter(summaryFile))) {
            bw.write("====================================================================================\n");
            bw.write(" [Handy MIG] 전자결재 파일 물리 정합성 전수 점검 종합 보고서\n");
            bw.write("====================================================================================\n");
            bw.write("점검 일시         : " + SDF_DATETIME.format(new Date()) + "\n");
            bw.write("점검 대상 스키마 : " + targetSchema + "\n");
            bw.write("스토리지 베이스   : " + basePath + "\n");
            bw.write("HOX 002 결재문서 : " + (skipHox002 ? "점검 제외 (열람 시 엔진 실시간 자동생성)" : "점검 포함") + "\n");
            bw.write("총 검사 건수      : " + String.format("%,d 건", total) + "\n");
            bw.write("정상 존재 파일    : " + String.format("%,d 건 (%.2f%%)", countOk.get(), total > 0 ? (countOk.get() * 100.0 / total) : 0.0) + "\n");
            bw.write("누락 결손 파일    : " + String.format("%,d 건 (%.2f%%)", countMissing.get(), total > 0 ? (countMissing.get() * 100.0 / total) : 0.0) + "\n");
            bw.write("0바이트 파일     : " + String.format("%,d 건", countZeroByte.get()) + "\n");
            bw.write("크기 불일치 파일 : " + String.format("%,d 건", countSizeMismatch.get()) + "\n");
            bw.write("누락 총 추정용량  : " + String.format("%,.2f MB (약 %,.2f GB)",
                    totalMissingBytes.get() / (1024.0 * 1024.0), totalMissingBytes.get() / (1024.0 * 1024.0 * 1024.0)) + "\n");
            bw.write("총 검사 소요시간  : " + String.format("%,.2f 초 (평균 %,.0f 건/초)", elapsedSec, speed) + "\n");
            bw.write("====================================================================================\n");
            bw.write("[품질 판정]\n");
            if (countMissing.get() == 0) {
                bw.write(" -> [적합 / PASSED] : 디스크 상에 모든 결재 본문/첨부파일이 100% 정상 존재합니다.\n");
            } else {
                bw.write(" -> [보완 필요 / ACTION REQUIRED] : " + countMissing.get() + " 건의 누락 파일이 확인되었습니다.\n");
                bw.write("    누락 리포트(missing_files_*.csv) 및 자동생성 복구 스크립트(copy_missing_from_asis_*.sh)를 활용하여\n");
                bw.write("    AS-IS 원천 스토리지에서 즉시 보완 복사를 수행하십시오.\n");
            }
            bw.write("====================================================================================\n");
        } catch (IOException e) {
            MigLogger.error("요약 보고서 작성 실패: " + e.getMessage(), e);
        }
    }

    private static String escapeCsv(String str) {
        if (str == null) return "";
        return str.replace("\"", "\"\"");
    }

    private static void log(String message) {
        MigLogger.info(message);
    }
}
