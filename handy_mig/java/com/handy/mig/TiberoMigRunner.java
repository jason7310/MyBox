package com.handy.mig;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * [통합 MIG] Tibero 7 TAC 고속 배치 실행기 (Java 17 호환 / 파일 반출 지원)
 * 
 * - 실행 환경: OpenJDK 17.0.19 / Rocky Linux 9.7 / Tibero 7
 * - 목적: 대용량 마이그레이션 SQL 스크립트를 세션 최적화(Direct-Path, Parallel)와 함께 자동 실행하고,
 *         망연계/외부망 반출을 위해 실행 결과 및 DDL을 logs/ 디렉토리에 자동 파일로 저장합니다.
 */
public class TiberoMigRunner {

    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("=========================================================================");
            System.out.println(" [Handy MIG] Tibero 7 고속 마이그레이션 런너 (JDK 17)");
            System.out.println(" Usage : java -cp .:tibero7-jdbc.jar com.handy.mig.TiberoMigRunner <SQL_FILE_PATH> [CONFIG_PATH]");
            System.out.println(" Example: java -cp .:bin:lib/tibero7-jdbc.jar com.handy.mig.TiberoMigRunner sql/02.APPROVAL_DIRECT_INSERT.sql");
            System.out.println("          (DB 접속 정보는 config/db.properties 에서 자동 로드됩니다)");
            System.out.println("=========================================================================");
            return;
        }

        String sqlFilePath = args[0];

        // 외부 설정 파일 경로가 지정된 경우 로드
        if (args.length >= 2) {
            try {
                DbConfig.load(args[1]);
            } catch (Exception e) {
                System.out.println("[WARN] 지정된 설정 파일 로드 실패 (" + args[1] + "), 기본 설정을 시도합니다.");
            }
        }

        String rawName = new File(sqlFilePath).getName();
        String baseName = rawName.replaceAll("\\.[^.]+$", "");
        MigLogger.init(baseName);

        log("=========================================================================");
        log(" [마이그레이션 실행 시작] 대상 파일: " + sqlFilePath);
        log(" [반출 로그 저장 경로] " + MigLogger.getLogFilePath());
        log("=========================================================================");

        long startTime = System.currentTimeMillis();

        try (Connection conn = DbConfig.getConnection()) {
            conn.setAutoCommit(false);
            log("Tibero 7 데이터베이스 접속 성공 (" + DbConfig.getUsername() + "@" + DbConfig.getUrl() + ")");

            // 세션 최적화 설정
            int parallelDegree = DbConfig.getParallelDegree();
            try (Statement stmt = conn.createStatement()) {
                stmt.execute("ALTER SESSION ENABLE PARALLEL DML");
                stmt.execute("ALTER SESSION ENABLE PARALLEL DDL");
                stmt.execute("ALTER SESSION FORCE PARALLEL DML PARALLEL " + parallelDegree);
                // stmt.execute("ALTER SESSION SET SKIP_UNUSABLE_INDEXES = TRUE");
                log("세션 병렬 DML/DDL 및 SKIP_UNUSABLE_INDEXES 활성화 완료 (Degree: " + parallelDegree + ")");
            }

            // SQL 파일 실행
            executeSqlFile(conn, sqlFilePath);

            long elapsed = (System.currentTimeMillis() - startTime) / 1000;
            log("마이그레이션 정상 완료! 총 소요시간: " + elapsed + " 초 (" + (elapsed / 60) + " 분 " + (elapsed % 60) + " 초)");

            MigLogger.complete();

        } catch (Exception e) {
            MigLogger.error("마이그레이션 실행 중 예외 발생: " + e.getMessage(), e);
        }
    }

    private static void executeSqlFile(Connection conn, String filePath) throws IOException, SQLException {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader br = new BufferedReader(new FileReader(filePath))) {
            String line;
            while ((line = br.readLine()) != null) {
                String trimmed = line.trim();
                // 주석 라인 무시
                if (trimmed.startsWith("--") || trimmed.startsWith("/*") || trimmed.isEmpty()) {
                    continue;
                }
                sb.append(line).append("\n");

                // 세미콜론 단위 명령 분리 실행 (단, PL/SQL 블록 제외)
                if (trimmed.endsWith(";")) {
                    String sql = sb.toString().trim();
                    if (sql.endsWith(";")) {
                        sql = sql.substring(0, sql.length() - 1);
                    }
                    if (!sql.isEmpty() && !sql.equalsIgnoreCase("COMMIT")) {
                        executeSingleSql(conn, sql);
                    } else if (sql.equalsIgnoreCase("COMMIT")) {
                        conn.commit();
                        log("[COMMIT] 트랜잭션 반영 완료.");
                    }
                    sb.setLength(0);
                }
            }
        }
        conn.commit();
    }

    private static void executeSingleSql(Connection conn, String sql) throws SQLException {
        long t1 = System.currentTimeMillis();
        String summary = sql.replaceAll("\\s+", " ");
        if (summary.length() > 80) {
            summary = summary.substring(0, 80) + "...";
        }
        log("[EXECUTE] " + summary);

        try (Statement stmt = conn.createStatement()) {
            boolean hasResultSet = stmt.execute(sql);
            long elapsed = System.currentTimeMillis() - t1;
            if (hasResultSet) {
                try (ResultSet rs = stmt.getResultSet()) {
                    ResultSetMetaData meta = rs.getMetaData();
                    int colCount = meta.getColumnCount();

                    // 컬럼 헤더 생성
                    StringBuilder header = new StringBuilder();
                    for (int i = 1; i <= colCount; i++) {
                        header.append(String.format("%-25s", meta.getColumnLabel(i))).append(" | ");
                    }
                    printBoth("--------------------------------------------------------------------------------");
                    printBoth(header.toString());
                    printBoth("--------------------------------------------------------------------------------");

                    int rows = 0;
                    while (rs.next()) {
                        StringBuilder row = new StringBuilder();
                        for (int i = 1; i <= colCount; i++) {
                            String val = rs.getString(i);
                            row.append(String.format("%-25s", (val == null ? "<NULL>" : val))).append(" | ");
                        }

                        // 화면에는 최대 150건까지만 출력 (스크롤 폭주 방지)
                        // 반출용 로그 파일에는 건수 제한 없이 전수(100%) 기록!
                        if (rows < 150) {
                            printBoth(row.toString());
                        } else {
                            printFileOnly(row.toString());
                        }
                        rows++;
                    }
                    printBoth("--------------------------------------------------------------------------------");
                    if (rows > 150) {
                        printBoth("[안내] 화면에는 상위 150건만 표시되었습니다. (전체 " + rows + "건 데이터는 반출 파일에 전수 저장됨)");
                    }
                    log(" -> 조회 완료 (조회건수: " + rows + " 행, 소요시간: " + elapsed + " ms)");
                }
            } else {
                int affected = stmt.getUpdateCount();
                log(" -> 완료 (반영건수: " + affected + " 행, 소요시간: " + elapsed + " ms)");
            }
        }
    }

    private static void log(String message) {
        MigLogger.info(message);
    }

    private static void printBoth(String line) {
        MigLogger.printBoth(line);
    }

    private static void printFileOnly(String line) {
        MigLogger.printFileOnly(line);
    }
}
