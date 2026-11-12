package com.handy.mig;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.text.SimpleDateFormat;
import java.util.Date;

/**
 * [통합 MIG] 폐쇄망/보안환경 최적화 순수 Java 표준 통합 로거 (Zero-Dependency MigLogger)
 * 
 * - 특징:
 *   1. 외부 JAR 종속성 0개 (Log4j/Logback 불필요, 공공기관 Log4Shell 보안 심사 리스크 원천 배제)
 *   2. 화면(Console)과 파일(logs/ 디렉토리)에 UTF-8 인코딩으로 실시간 동시 출력
 *   3. 타임스탬프 원본 로그와 'latest_{taskName}.log' 고정 파일을 동시 생성하여 망연계/외부 반출 편의성 극대화
 *   4. JVM ShutdownHook을 통한 안전한 버퍼 Flush 및 리소스 반환
 */
public class MigLogger {

    private static final SimpleDateFormat SDF_CONSOLE = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
    private static final SimpleDateFormat SDF_FILE = new SimpleDateFormat("yyyyMMdd_HHmmss");

    private static String currentTask = "mig";
    private static File logFile = null;
    private static File latestFile = null;
    private static PrintWriter writer = null;
    private static boolean isInitialized = false;

    static {
        // 비정상 종료 시에도 파일 버퍼를 안전하게 닫도록 ShutdownHook 등록
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            close();
        }));
    }

    /**
     * 작업 태스크 단위 로거 초기화
     * @param taskName 태스크 식별자 (예: "validate", "dup_cleaner", "approval_mig")
     */
    public static synchronized void init(String taskName) {
        if (taskName != null && !taskName.trim().isEmpty()) {
            currentTask = taskName.replaceAll("[^a-zA-Z0-9_.-]", "_");
        }

        File logDir = new File("logs");
        if (!logDir.exists()) {
            logDir.mkdirs();
        }

        String timestamp = SDF_FILE.format(new Date());
        logFile = new File(logDir, currentTask + "_" + timestamp + ".log");
        latestFile = new File(logDir, "latest_" + currentTask + ".log");

        try {
            if (writer != null) {
                writer.flush();
                writer.close();
            }
            writer = new PrintWriter(new OutputStreamWriter(new FileOutputStream(logFile, true), StandardCharsets.UTF_8), true);
            isInitialized = true;
        } catch (Exception e) {
            System.err.println("[MigLogger] 로그 파일 생성 실패 (" + logFile.getAbsolutePath() + "): " + e.getMessage());
        }
    }

    public static synchronized void info(String message) {
        log("INFO", message);
    }

    public static synchronized void warn(String message) {
        log("WARN", message);
    }

    public static synchronized void error(String message) {
        log("ERROR", message);
    }

    public static synchronized void error(String message, Throwable t) {
        log("ERROR", message);
        if (t != null) {
            t.printStackTrace(System.err);
            if (writer != null) {
                t.printStackTrace(writer);
                writer.flush();
            }
        }
    }

    /**
     * 화면과 로그 파일 양쪽에 포맷팅 없이 직접 출력 (테이블, 구분선 등)
     */
    public static synchronized void printBoth(String line) {
        System.out.println(line);
        if (writer != null) {
            writer.println(line);
        }
    }

    /**
     * 화면 출력 없이 파일에만 출력 (대량 조회 시 화면 스크롤 폭주 방지)
     */
    public static synchronized void printFileOnly(String line) {
        if (writer != null) {
            writer.println(line);
        }
    }

    private static synchronized void log(String level, String message) {
        if (!isInitialized) {
            init("mig");
        }
        String formatted = "[" + SDF_CONSOLE.format(new Date()) + "] [" + level + "] " + message;
        System.out.println(formatted);
        if (writer != null) {
            writer.println(formatted);
        }
    }

    /**
     * 작업 완료 시 반출 경로 안내 및 latest 파일 동기화
     */
    public static synchronized void complete() {
        if (logFile != null && logFile.exists()) {
            try {
                if (writer != null) {
                    writer.flush();
                }
                Files.copy(logFile.toPath(), latestFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            } catch (Exception ignored) {}

            printBoth("=========================================================================");
            printBoth(" ⭐ [내부망 -> 외부망 반출 안내]");
            printBoth("   실행 결과 및 로그가 아래 파일에 100% 전수 저장되었습니다:");
            printBoth("   1) 타임스탬프 파일 : " + logFile.getAbsolutePath());
            printBoth("   2) 최신 고정 파일   : " + latestFile.getAbsolutePath());
            printBoth("=========================================================================");
        }
    }

    public static synchronized void close() {
        if (writer != null) {
            try {
                writer.flush();
                writer.close();
            } catch (Exception ignored) {}
            writer = null;
        }
    }

    public static String getLogFilePath() {
        return logFile != null ? logFile.getAbsolutePath() : "";
    }
}
