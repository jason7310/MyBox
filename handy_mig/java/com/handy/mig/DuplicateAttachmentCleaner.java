package com.handy.mig;

import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * [통합 MIG] 수신문서 중복 첨부파일(DOCUMENTTYPE=100) 검출 및 물리 파일 삭제 도구 (Java 17 호환)
 * 
 * - 기능:
 *   1. 원기안문서 첨부를 바라보지 않고 중복 생성된 수신문서 첨부파일(DOCUMENTTYPE=100)을 DB에서 정밀 탐색합니다.
 *   2. [검사 모드 : check]
 *      - 실제 디스크 파일 존재 여부 및 중복 용량(MB/GB) 정밀 산출
 *      - 삭제 대상 전체 경로 목록을 'report/duplicate_files_to_delete.txt' 파일로 안전하게 추출
 *   3. [삭제 모드 : delete]
 *      - 삭제 작업 전/후 디스크 실제 가용 용량(Free/Usable Space) 측정 및 변화량 리포팅
 *      - 디스크 상의 중복 파일을 실제로 삭제하여 스토리지 공간을 즉시 회수
 *      - 옵션(--fix-db)에 따라 DB DOCMBR/DOCUMENT 매핑 정상화(원기안 재연결) 수행
 */
public class DuplicateAttachmentCleaner {

    private static final SimpleDateFormat SDF = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");

    static class DupFileItem {
        String enfApprId;
        String orgApprId;
        String enfObjectId;
        String orgObjectId;
        String fileName;
        long fileSize;
        String filePath; // 실제 디스크 상의 파일 경로
    }

    static class DiskSpaceInfo {
        String path;
        long totalBytes;
        long usableBytes;
        long usedBytes;

        DiskSpaceInfo(String path, long total, long usable) {
            this.path = path;
            this.totalBytes = total;
            this.usableBytes = usable;
            this.usedBytes = Math.max(0, total - usable);
        }

        double toGb(long bytes) {
            return bytes / (1024.0 * 1024.0 * 1024.0);
        }

        double toMb(long bytes) {
            return bytes / (1024.0 * 1024.0);
        }

        double usedPercent() {
            return totalBytes > 0 ? (usedBytes * 100.0 / totalBytes) : 0.0;
        }
    }

    public static void main(String[] args) {
        String mode = "check"; // 기본값은 안전한 검사(check) 모드
        boolean fixDb = false;
        String customConfig = null;

        for (int i = 0; i < args.length; i++) {
            if ("delete".equalsIgnoreCase(args[i]) || "--delete".equalsIgnoreCase(args[i])) {
                mode = "delete";
            } else if ("check".equalsIgnoreCase(args[i]) || "--check".equalsIgnoreCase(args[i])) {
                mode = "check";
            } else if ("--fix-db".equalsIgnoreCase(args[i])) {
                fixDb = true;
            } else if (args[i].endsWith(".properties")) {
                customConfig = args[i];
            }
        }

        MigLogger.init("dup_cleaner");
        log("=========================================================================");
        log(" [Handy MIG] 수신문서 중복 첨부파일(DOCUMENTTYPE=100) 검출 및 디스크 정리 도구");
        log(" 실행 모드: [" + mode.toUpperCase() + "] " + (fixDb ? "(DB 매핑 보정 포함)" : ""));
        log("=========================================================================");

        if (customConfig != null) {
            try {
                DbConfig.load(customConfig);
            } catch (IOException e) {
                MigLogger.warn("지정된 설정 파일 로드 실패: " + customConfig);
            }
        }

        // 스토리지 베이스 경로 확인
        String storageBasePath = DbConfig.getProperty("storage.base.path", "/data");
        File storageBaseDir = new File(storageBasePath);
        if (!storageBaseDir.exists()) {
            storageBaseDir = new File(".");
        }

        // 1. [작업 전] 디스크 용량 측정
        DiskSpaceInfo diskBefore = getDiskSpace(storageBaseDir);

        try (Connection conn = DbConfig.getConnection()) {
            log("데이터베이스 접속 성공 (" + DbConfig.getUrl() + ")");

            // 2. 중복 첨부파일(DOCUMENTTYPE=100) 목록 조회
            List<DupFileItem> dupList = findDuplicateAttachments(conn);
            log(String.format("중복 수신 첨부파일(DOCUMENTTYPE=100) DB 검출: %,d 건", dupList.size()));

            if (dupList.isEmpty()) {
                log("[결과] 중복 생성된 수신문서 첨부파일이 없습니다. (정상 상태)");
                MigLogger.complete();
                return;
            }

            // 3. 디스크 상의 물리 파일 존재 여부 및 대상 파일 목록 파일 작성
            File reportDir = new File("report");
            if (!reportDir.exists()) reportDir.mkdirs();
            File reportFile = new File(reportDir, "duplicate_files_to_delete.txt");

            long existCount = 0;
            long totalBytes = 0;
            long deletedCount = 0;
            long deleteFailedCount = 0;

            try (BufferedWriter bw = new BufferedWriter(new FileWriter(reportFile))) {
                bw.write("# 수신문서 중복 첨부파일(DOCUMENTTYPE=100) 삭제 대상 목록 - 생성일시: " + SDF.format(new Date()) + "\n");
                bw.write("# 수신결재ID | 원기안결재ID | 수신OBJECTID | 원기안OBJECTID | 파일크기(Byte) | 물리파일경로\n");

                for (DupFileItem item : dupList) {
                    File file = resolvePhysicalFile(item.filePath);
                    boolean exists = (file != null && file.exists() && file.isFile());

                    if (exists) {
                        existCount++;
                        totalBytes += file.length();
                    }

                    bw.write(String.format("%s | %s | %s | %s | %d | %s\n",
                            item.enfApprId, item.orgApprId, item.enfObjectId, item.orgObjectId,
                            item.fileSize, (file != null ? file.getAbsolutePath() : item.filePath)));

                    // 4. 실제 삭제 모드 처리
                    if ("delete".equals(mode) && exists) {
                        if (file.delete()) {
                            deletedCount++;
                        } else {
                            deleteFailedCount++;
                        }
                    }
                }
            }

            double totalMb = totalBytes / (1024.0 * 1024.0);
            double totalGb = totalMb / 1024.0;

            log("-------------------------------------------------------------------------");
            log(String.format(" [검사 결과 통계 (첨부파일 DOCUMENTTYPE=100 대상)]"));
            log(String.format("  - DB 등록 중복 건수     : %,d 건", dupList.size()));
            log(String.format("  - 실제 디스크 존재 파일 : %,d 건", existCount));
            log(String.format("  - 중복 파일 점유 용량   : %,.2f MB (약 %,.2f GB)", totalMb, totalGb));
            log("  - 상세 대상 파일 목록   : " + reportFile.getAbsolutePath());
            log("-------------------------------------------------------------------------");

            if ("delete".equals(mode)) {
                log(String.format(" [삭제 결과] 정상 삭제: %,d 건 | 삭제 실패: %,d 건", deletedCount, deleteFailedCount));

                // 5. [작업 후] 디스크 용량 측정 및 이전/이후 비교
                DiskSpaceInfo diskAfter = getDiskSpace(storageBaseDir);
                printDiskComparison(diskBefore, diskAfter, totalBytes);

                // DB 보정 실행
                if (fixDb) {
                    fixDbMapping(conn);
                } else {
                    log("[안내] DB 매핑(DOCMBR/DOCUMENT) 보정은 sql/07.DUPLICATE_ATTACHMENT_CHECK_AND_FIX.sql 을 실행하십시오.");
                }
            } else {
                log(String.format(" [현재 디스크 현황] 여유공간: %,.2f GB / 전체: %,.2f GB (사용률: %.1f%%)",
                        diskBefore.toGb(diskBefore.usableBytes), diskBefore.toGb(diskBefore.totalBytes), diskBefore.usedPercent()));
                log("[안내] 현재는 검사(check) 모드이므로 실제 파일이 삭제되지 않았습니다.");
                log("       실제 파일을 삭제하여 디스크를 확보하려면 아래 명령을 실행하십시오:");
                log("       -> ./build_and_run.sh clean-dup");
            }

            MigLogger.complete();

        } catch (Exception e) {
            MigLogger.error("작업 중 오류 발생: " + e.getMessage(), e);
        }
    }

    /**
     * 특정 디렉토리의 파일시스템 디스크 용량 측정
     */
    private static DiskSpaceInfo getDiskSpace(File dir) {
        try {
            long total = dir.getTotalSpace();
            long usable = dir.getUsableSpace();
            return new DiskSpaceInfo(dir.getAbsolutePath(), total, usable);
        } catch (Exception e) {
            return new DiskSpaceInfo(dir.getAbsolutePath(), 0, 0);
        }
    }

    /**
     * 디스크 용량 이전/이후 대조 결과 출력
     */
    private static void printDiskComparison(DiskSpaceInfo before, DiskSpaceInfo after, long deletedFileBytes) {
        long freedBytes = Math.max(0, after.usableBytes - before.usableBytes);
        double freedGb = after.toGb(freedBytes);
        double deletedGb = before.toGb(deletedFileBytes);

        log("=========================================================================");
        log(" 💾 [스토리지 디스크 용량 변화 리포트 (Before vs After)]");
        log(" 마운트 경로: " + after.path);
        log("-------------------------------------------------------------------------");
        log(String.format("  [삭제 전] 여유 공간: %,.2f GB (사용 중: %,.2f GB / %.1f%%)",
                before.toGb(before.usableBytes), before.toGb(before.usedBytes), before.usedPercent()));
        log(String.format("  [삭제 후] 여유 공간: %,.2f GB (사용 중: %,.2f GB / %.1f%%)",
                after.toGb(after.usableBytes), after.toGb(after.usedBytes), after.usedPercent()));
        log("-------------------------------------------------------------------------");
        log(String.format("  ✨ 순수 확보된 여유 공간: +%,.2f GB (+%,.2f MB)", freedGb, after.toMb(freedBytes)));
        log(String.format("  ✨ 삭제된 파일 총 크기  : %,.2f GB", deletedGb));
        log("=========================================================================");

        printSystemDf(after.path);
    }

    /**
     * 리눅스 df -h 커맨드 정보 보조 출력
     */
    private static void printSystemDf(String path) {
        try {
            Process process = new ProcessBuilder("df", "-h", path).start();
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(process.getInputStream()))) {
                String line;
                log("[시스템 df -h 현황]");
                while ((line = reader.readLine()) != null) {
                    log("  " + line);
                }
            }
        } catch (Exception ignored) {
        }
    }

    /**
     * DB에서 중복된 수신 첨부파일(DOCUMENTTYPE = 100) 목록 조회
     */
    private static List<DupFileItem> findDuplicateAttachments(Connection conn) throws SQLException {
        List<DupFileItem> list = new ArrayList<>();

        // ⭐ DOCUMENTTYPE = 100 명시적 조건 적용
        String sql = "SELECT " +
                     "    K_ENF.APPRID AS ENF_APPRID, " +
                     "    K_ORG.APPRID AS ORG_APPRID, " +
                     "    M_ENF.OBJECTID AS ENF_OBJECTID, " +
                     "    M_ORG.OBJECTID AS ORG_OBJECTID, " +
                     "    D_ENF.FILENAME, " +
                     "    D_ENF.FILESIZE, " +
                     "    NVL(D_ENF.SRCOBJECTID, D_ENF.OBJECTID) AS FILE_PATH " +
                     " FROM INTRAWARE.MAPPING_APPR_KEY K_ENF " +
                     " JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG ON K_ENF.ORIGIN_DOC_ID = K_ORG.DOC_ID " +
                     " JOIN INTRAWARE.DOCMBR M_ENF ON K_ENF.APPRID = M_ENF.APPRID AND M_ENF.DOCUMENTTYPE = 100 " +
                     " JOIN INTRAWARE.DOCUMENT D_ENF ON M_ENF.OBJECTID = D_ENF.OBJECTID " +
                     " JOIN INTRAWARE.DOCMBR M_ORG ON K_ORG.APPRID = M_ORG.APPRID AND M_ORG.DOCUMENTTYPE = 100 " +
                     " JOIN INTRAWARE.DOCUMENT D_ORG ON M_ORG.OBJECTID = D_ORG.OBJECTID " +
                     "  AND (D_ENF.FILENAME = D_ORG.FILENAME AND D_ENF.FILESIZE = D_ORG.FILESIZE) " +
                     " WHERE K_ENF.DOC_TYPE = 'E' " +
                     "   AND M_ENF.OBJECTID <> M_ORG.OBJECTID";

        try (PreparedStatement pstmt = conn.prepareStatement(sql);
             ResultSet rs = pstmt.executeQuery()) {
            while (rs.next()) {
                DupFileItem item = new DupFileItem();
                item.enfApprId = rs.getString("ENF_APPRID");
                item.orgApprId = rs.getString("ORG_APPRID");
                item.enfObjectId = rs.getString("ENF_OBJECTID");
                item.orgObjectId = rs.getString("ORG_OBJECTID");
                item.fileName = rs.getString("FILENAME");
                item.fileSize = rs.getLong("FILESIZE");
                item.filePath = rs.getString("FILE_PATH");
                list.add(item);
            }
        }
        return list;
    }

    /**
     * 물리 디스크 상의 실제 파일 객체 탐색
     */
    private static File resolvePhysicalFile(String pathStr) {
        if (pathStr == null || pathStr.trim().isEmpty()) return null;

        File f = new File(pathStr);
        if (f.exists()) return f;

        String basePath = DbConfig.getProperty("storage.base.path", "/data");
        File baseFile = new File(basePath, pathStr.startsWith("/") ? pathStr.substring(1) : pathStr);
        if (baseFile.exists()) return baseFile;

        File baseFile2 = new File("/data/appr", pathStr.startsWith("/") ? pathStr.substring(1) : pathStr);
        if (baseFile2.exists()) return baseFile2;

        return f;
    }

    /**
     * DB 매핑 보정 (수신문서 DOCMBR의 OBJECTID를 원기안문서 OBJECTID로 전환)
     */
    private static void fixDbMapping(Connection conn) {
        log("[DB 보정] 수신문서 첨부(DOCUMENTTYPE=100)의 DOCMBR 매핑을 원기안 첨부로 전환 중...");
        String mergeSql = "MERGE INTO INTRAWARE.DOCMBR M_ENF " +
                          "USING ( " +
                          "    SELECT K_ENF.APPRID AS ENF_APPRID, M_ENF.OBJECTID AS OLD_OBJ, M_ORG.OBJECTID AS NEW_OBJ " +
                          "      FROM INTRAWARE.MAPPING_APPR_KEY K_ENF " +
                          "      JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG ON K_ENF.ORIGIN_DOC_ID = K_ORG.DOC_ID " +
                          "      JOIN INTRAWARE.DOCMBR M_ENF ON K_ENF.APPRID = M_ENF.APPRID AND M_ENF.DOCUMENTTYPE = 100 " +
                          "      JOIN INTRAWARE.DOCUMENT D_ENF ON M_ENF.OBJECTID = D_ENF.OBJECTID " +
                          "      JOIN INTRAWARE.DOCMBR M_ORG ON K_ORG.APPRID = M_ORG.APPRID AND M_ORG.DOCUMENTTYPE = 100 " +
                          "      JOIN INTRAWARE.DOCUMENT D_ORG ON M_ORG.OBJECTID = D_ORG.OBJECTID " +
                          "       AND (D_ENF.FILENAME = D_ORG.FILENAME AND D_ENF.FILESIZE = D_ORG.FILESIZE) " +
                          "     WHERE K_ENF.DOC_TYPE = 'E' AND M_ENF.OBJECTID <> M_ORG.OBJECTID " +
                          ") SRC ON (M_ENF.APPRID = SRC.ENF_APPRID AND M_ENF.OBJECTID = SRC.OLD_OBJ) " +
                          "WHEN MATCHED THEN UPDATE SET M_ENF.OBJECTID = SRC.NEW_OBJ";

        try (PreparedStatement pstmt = conn.prepareStatement(mergeSql)) {
            int updated = pstmt.executeUpdate();
            conn.commit();
            log("[DB 보정 완료] 수신문서 첨부(DOCUMENTTYPE=100) DOCMBR 매핑 정상화 완료: " + updated + " 건 갱신");
        } catch (SQLException e) {
            log("[ERROR] DB 보정 중 오류: " + e.getMessage());
        }
    }

    private static void log(String message) {
        MigLogger.info(message);
    }
}
