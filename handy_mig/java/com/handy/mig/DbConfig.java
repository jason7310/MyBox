package com.handy.mig;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.Properties;

/**
 * [통합 MIG] DB 설정 관리 및 커넥션 공급자 (Java 17 호환)
 * 
 * - 기능: config/db.properties 또는 지정된 외부 설정 파일에서 DB 접속 정보를 읽어 Connection을 생성합니다.
 */
public class DbConfig {

    private static final String DEFAULT_CONFIG_PATH = "config/db.properties";
    private static Properties properties = new Properties();
    private static boolean isLoaded = false;

    /**
     * 기본 설정 파일 경로로부터 로드
     */
    public static synchronized void load() throws IOException {
        load(DEFAULT_CONFIG_PATH);
    }

    /**
     * 지정된 경로로부터 설정 파일 로드
     */
    public static synchronized void load(String customPath) throws IOException {
        File file = new File(customPath);
        if (!file.exists()) {
            // 상위 디렉토리 또는 현재 디렉토리 재탐색
            File altFile = new File("db.properties");
            if (altFile.exists()) {
                file = altFile;
            } else {
                File altFile2 = new File("../config/db.properties");
                if (altFile2.exists()) {
                    file = altFile2;
                }
            }
        }

        if (!file.exists()) {
            throw new IOException("[DbConfig] 설정 파일을 찾을 수 없습니다: " + customPath);
        }

        try (InputStream in = new FileInputStream(file)) {
            properties.load(in);
            isLoaded = true;
            System.out.println("[DbConfig] 설정 파일 로드 성공: " + file.getAbsolutePath());
        }

        // 드라이버 사전 로드
        String driver = getProperty("db.driver", "com.tmax.tibero.jdbc.TbDriver");
        try {
            Class.forName(driver);
        } catch (ClassNotFoundException e) {
            System.err.println("[DbConfig ERROR] JDBC 드라이버 로드 실패: " + driver);
            System.err.println(" -> tibero7-jdbc.jar 파일이 클래스패스(-cp)에 포함되어 있는지 확인하세요.");
        }
    }

    public static String getProperty(String key) {
        if (!isLoaded) {
            try {
                load();
            } catch (IOException e) {
                throw new RuntimeException("[DbConfig ERROR] 설정 파일 로드 실패: " + e.getMessage(), e);
            }
        }
        return properties.getProperty(key);
    }

    public static String getProperty(String key, String defaultValue) {
        String val = getProperty(key);
        return (val != null && !val.trim().isEmpty()) ? val.trim() : defaultValue;
    }

    public static String getUrl() {
        return getProperty("db.url");
    }

    public static String getUsername() {
        return getProperty("db.username");
    }

    public static String getPassword() {
        return getProperty("db.password");
    }

    public static int getParallelDegree() {
        return Integer.parseInt(getProperty("mig.parallel.degree", "16"));
    }

    public static int getBatchSize() {
        return Integer.parseInt(getProperty("mig.batch.size", "10000"));
    }

    /**
     * 설정된 정보로 데이터베이스 연결 생성
     */
    public static Connection getConnection() throws SQLException {
        if (!isLoaded) {
            try {
                load();
            } catch (IOException e) {
                throw new SQLException("설정 파일 로드 실패: " + e.getMessage(), e);
            }
        }
        return DriverManager.getConnection(getUrl(), getUsername(), getPassword());
    }
}
