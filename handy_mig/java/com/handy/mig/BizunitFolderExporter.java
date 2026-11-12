package com.handy.mig;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.*;

/**
 * [통합 MIG] 단위업무(BIZUNIT) 및 기록물철(FOLDER) 부서별 분할 추출기
 * 
 * 핸디 10.x 기록관리 배치 도구(rtool.sh) 입력 규격에 맞추어
 * 원천 중간 테이블(MIG1_USER.MG_BIZUNIT, MIG1_USER.MG_FOLDER)의 데이터를
 * 부서코드(PROCDEPTCODE)별 파일로 초고속 분할 추출합니다.
 * 
 * [rtool.sh 옵션 규격] (IMG_9474 실물 검증 완료)
 * - 단위업무 로드 : rtool.sh -t lb -p <파일 path>
 * - 기록물철 로드 : rtool.sh -t al -p <파일 path>
 * 
 * [출력 기본 경로]
 * - output/rtool/ (handy_mig 통합 저장소 하위)
 */
public class BizunitFolderExporter {

    private static final String DEFAULT_CONFIG = "config/db.properties";
    private static final String DEFAULT_OUTPUT_BASE = "output/rtool";
    private static final String RTOOL_BIN_PATH = "/app/hso10/jhoms/bin/tools";

    public static void main(String[] args) {
        String modeArg = args.length > 0 ? args[0].toLowerCase() : "all";
        String outputPath = args.length > 1 ? args[1] : DEFAULT_OUTPUT_BASE;
        String configFile = args.length > 2 ? args[2] : DEFAULT_CONFIG;

        // ~ 경로 확장 지원
        if (outputPath.startsWith("~/")) {
            String home = System.getProperty("user.home");
            outputPath = home + outputPath.substring(1);
        }

        boolean isDeltaMode = modeArg.contains("delta");
        String target = modeArg.replace("delta-", "").replace("delta", "").trim();
        if (target.isEmpty()) target = "all";

        MigLogger.init("bizunit_folder_exporter");

        MigLogger.info("================================================================================");
        MigLogger.info(" [통합 MIG] 단위업무 & 기록물철 부서별 분할 추출 시작 (rtool.sh 옵션 연동)");
        MigLogger.info(" - 대상 모드      : " + target + (isDeltaMode ? " [증가분(Delta) 전용]" : " [전체(Full) 추출]"));
        MigLogger.info(" - 출력 기본 경로 : " + outputPath);
        MigLogger.info(" - rtool.sh 경로  : " + RTOOL_BIN_PATH + "/rtool.sh");
        MigLogger.info(" - rtool 옵션     : 단위업무 [-t lb -p <file>], 기록물철 [-t al -p <file>]");
        MigLogger.info("================================================================================");

        File baseDir = new File(outputPath);
        File bizunitDir = new File(baseDir, isDeltaMode ? "bizunit_delta" : "bizunit");
        File folderDir = new File(baseDir, isDeltaMode ? "folder_delta" : "folder");

        if (!bizunitDir.exists()) bizunitDir.mkdirs();
        if (!folderDir.exists()) folderDir.mkdirs();

        Set<String> processedDepts = new TreeSet<>();

        try {
            DbConfig.load(configFile);
        } catch (IOException e) {
            MigLogger.error("설정 파일 로드 실패: " + configFile, e);
            System.exit(1);
        }

        try (Connection conn = DbConfig.getConnection()) {

            // 1. 단위업무(BIZUNIT) 부서별 추출
            if ("all".equals(target) || "bizunit".equals(target) || "bu".equals(target)) {
                MigLogger.info(">>> [1/2] 단위업무(MG_BIZUNIT) 부서별 분할 추출 (" + (isDeltaMode ? "증가분" : "전체") + ")...");
                exportBizunit(conn, bizunitDir, processedDepts, isDeltaMode);
            }

            // 2. 기록물철(FOLDER) 부서별 추출
            if ("all".equals(target) || "folder".equals(target) || "bf".equals(target)) {
                MigLogger.info(">>> [2/2] 기록물철(MG_FOLDER) 부서별 분할 추출 (" + (isDeltaMode ? "증가분" : "전체") + ")...");
                exportFolder(conn, folderDir, processedDepts, isDeltaMode);
            }

            // 3. rtool.sh 부서별 일괄 실행 쉘 스크립트 자동 생성
            generateRtoolRunnerScript(baseDir, bizunitDir, folderDir, isDeltaMode);

            MigLogger.info("================================================================================");
            MigLogger.info(" [완료] 단위업무 & 기록물철 부서별 분할 추출 및 rtool.sh 실행 쉘 생성 완료!");
            MigLogger.info(" - 총 대상 부서 수 : " + processedDepts.size() + " 개 부서");
            MigLogger.info(" - 생성된 실행 쉘 : " + new File(baseDir, isDeltaMode ? "run_rtool_delta.sh" : "run_rtool_all.sh").getAbsolutePath());
            MigLogger.info("================================================================================");

        } catch (Exception e) {
            MigLogger.error("추출 중 치명적 오류 발생: " + e.getMessage(), e);
            System.exit(1);
        }
    }

    /**
     * 단위업무(MG_BIZUNIT) 부서별 분할 추출 (전체 또는 증가분)
     */
    private static void exportBizunit(Connection conn, File outputDir, Set<String> deptSet, boolean isDeltaMode) throws SQLException, IOException {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT ")
           .append("  NVL(B.BIZOPENDATE, TO_CHAR(SYSDATE,'YYYYMMDDHH24MI')) AS BIZOPENDATE, ")
           .append("  NVL(B.BASETIME, TO_CHAR(SYSDATE,'YYYYMMDD')) AS BASETIME, ")
           .append("  TRIM(B.PROCDEPTCODE) AS PROCDEPTCODE, ")
           .append("  NVL(B.PROCDEPTNAME, '') AS PROCDEPTNAME, ")
           .append("  TRIM(B.BIZUNITCODE) AS BIZUNITCODE, ")
           .append("  NVL(B.LCODE, '') AS LCODE, NVL(B.LNAME, '') AS LNAME, ")
           .append("  NVL(B.MCODE, '') AS MCODE, NVL(B.MNAME, '') AS MNAME, ")
           .append("  NVL(B.SCODE, '') AS SCODE, NVL(B.SNAME, '') AS SNAME, ")
           .append("  TRIM(NVL(B.BIZUNITCODE2, B.BIZUNITCODE)) AS BIZUNITCODE2, ")
           .append("  NVL(B.BIZUNITNAME, '임시업무') AS BIZUNITNAME, ")
           .append("  NVL(B.BIZUNITDESC, '') AS BIZUNITDESC, ")
           .append("  NVL(B.KEEPPERIOD, '40') AS KEEPPERIOD, ")
           .append("  NVL(B.KEEPPERIODCAUSE, '') AS KEEPPERIODCAUSE, ")
           .append("  NVL(B.KEEPMETHOD, '1') AS KEEPMETHOD, ")
           .append("  NVL(B.KEEPPLACE, '1') AS KEEPPLACE, ")
           .append("  NVL(B.PROVISIONFLAG, '1') AS PROVISIONFLAG, ")
           .append("  NVL(B.PROVISIONTRANSTIME, '') AS PROVISIONTRANSTIME, ")
           .append("  NVL(B.EXPECTEDREADFREQ, '3') AS EXPECTEDREADFREQ, ")
           .append("  NVL(B.READPROPOSE, '5') AS READPROPOSE, ")
           .append("  NVL(B.SPECIALLOC, '0') AS SPECIALLOC, ")
           .append("  NVL(B.KEYWORD1, '') AS KEYWORD1, ")
           .append("  NVL(B.KEYWORD2, '') AS KEYWORD2, ")
           .append("  NVL(B.KEYWORD3, '') AS KEYWORD3, ")
           .append("  NVL(B.ABOLITIONFLAG, '1') AS ABOLITIONFLAG ")
           .append("FROM MIG1_USER.MG_BIZUNIT B ")
           .append("WHERE B.PROCDEPTCODE IS NOT NULL ");

        if (isDeltaMode) {
            // 증가분: 핸디 BIZUNIT에 미등록된 단위업무코드만 선별 (DEL 제외)
            sql.append("  AND NOT EXISTS ( ")
               .append("      SELECT 1 FROM INTRAWARE.BIZUNIT IB ")
               .append("       WHERE IB.BIZUNITCD = TRIM(B.BIZUNITCODE) ")
               .append("  ) ");
        }

        sql.append("ORDER BY B.PROCDEPTCODE, B.BIZUNITCODE");

        Map<String, BufferedWriter> writers = new HashMap<>();
        long rowCount = 0;

        try (Statement stmt = conn.createStatement(); ResultSet rs = stmt.executeQuery(sql.toString())) {
            while (rs.next()) {
                String deptCode = rs.getString("PROCDEPTCODE");
                if (deptCode == null || deptCode.trim().isEmpty()) {
                    deptCode = "UNKNOWN";
                }
                deptCode = deptCode.trim();
                deptSet.add(deptCode);

                BufferedWriter bw = writers.get(deptCode);
                if (bw == null) {
                    File deptFile = new File(outputDir, "bizunit_" + deptCode + ".txt");
                    bw = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(deptFile), StandardCharsets.UTF_8));
                    writers.put(deptCode, bw);
                }

                String unitName = cleanText(rs.getString("BIZUNITNAME"));
                String unitDesc = cleanText(rs.getString("BIZUNITDESC"));
                String periodCause = cleanText(rs.getString("KEEPPERIODCAUSE"));

                // rtool.sh -t lb 표준 콤마 구분자 라인
                String line = String.join(",",
                    rs.getString("BIZOPENDATE"),
                    rs.getString("BASETIME"),
                    deptCode,
                    cleanText(rs.getString("PROCDEPTNAME")),
                    "e0000001", // TEMPUNIT
                    rs.getString("LCODE"), rs.getString("LNAME"),
                    rs.getString("MCODE"), rs.getString("MNAME"),
                    rs.getString("SCODE"), rs.getString("SNAME"),
                    rs.getString("BIZUNITCODE"),
                    unitName,
                    unitDesc,
                    rs.getString("KEEPPERIOD"),
                    periodCause,
                    rs.getString("KEEPMETHOD"),
                    rs.getString("KEEPPLACE"),
                    rs.getString("PROVISIONFLAG"),
                    rs.getString("PROVISIONTRANSTIME"),
                    rs.getString("EXPECTEDREADFREQ"),
                    rs.getString("READPROPOSE"),
                    rs.getString("SPECIALLOC"),
                    rs.getString("KEYWORD1"),
                    rs.getString("KEYWORD2"),
                    rs.getString("KEYWORD3"),
                    rs.getString("ABOLITIONFLAG")
                );

                bw.write(line);
                bw.newLine();
                rowCount++;
            }
        } finally {
            for (BufferedWriter bw : writers.values()) {
                try { bw.flush(); bw.close(); } catch (Exception ignored) {}
            }
        }

        MigLogger.info(" - 단위업무 분할 완료: 총 " + String.format("%,d", rowCount) + " 건, " + writers.size() + " 개 부서 파일 생성.");
    }

    /**
     * 기록물철(MG_FOLDER) 부서별 분할 추출 (전체 또는 증가분)
     */
    private static void exportFolder(Connection conn, File outputDir, Set<String> deptSet, boolean isDeltaMode) throws SQLException, IOException {
        StringBuilder sql = new StringBuilder();
        sql.append("SELECT ")
           .append("  TRIM(F.PROCDEPTCODE) AS PROCDEPTCODE, ")
           .append("  NVL(F.OLDDOCORGNAME, '') AS OLDDOCORGNAME, ")
           .append("  NVL(F.PRODYEAR, '2006') AS PRODYEAR, ")
           .append("  TRIM(F.BIZUNITCODE) AS BIZUNITCODE, ")
           .append("  NVL(F.BIZUNITYEARSEQ, '000001') AS BIZUNITYEARSEQ, ")
           .append("  NVL(F.VOLUMESEQ, '001') AS VOLUMESEQ, ")
           .append("  NVL(F.FOLDERNAME, '무제') AS FOLDERNAME, ")
           .append("  NVL(F.RECORDINGTYPE, '1') AS RECORDINGTYPE, ")
           .append("  NVL(F.ENDYEAR, '2026') AS ENDYEAR, ")
           .append("  NVL(F.KEEPINGPERIOD, '40') AS KEEPINGPERIOD, ")
           .append("  NVL(F.KEEPINGMETHOD, '1') AS KEEPINGMETHOD, ")
           .append("  NVL(F.KEEPINGPLACE, '1') AS KEEPINGPLACE, ")
           .append("  F.PROVISIONENDDATE, ")
           .append("  NVL(F.PROVISIONCAUSE, '') AS PROVISIONCAUSE, ")
           .append("  NVL(F.DOCPROCUSERCODE, 'admin') AS DOCPROCUSERCODE, ")
           .append("  NVL(F.DOCPROCUSERNAME, '관리자') AS DOCPROCUSERNAME, ")
           .append("  NVL(F.OLDDOCCLSNO, '') AS OLDDOCCLSNO, ")
           .append("  NVL(F.PUBLICFLAG, '1') AS PUBLICFLAG, ")
           .append("  F.BINDID ")
           .append("FROM MIG1_USER.MG_FOLDER F ")
           .append("WHERE F.PROCDEPTCODE IS NOT NULL ");

        if (isDeltaMode) {
            // 증가분: 핸디 APPRFOLDER에 미등록된 기록물철만 선별 (BINDID 또는 단위업무+년도+순번 기준)
            sql.append("  AND NOT EXISTS ( ")
               .append("      SELECT 1 FROM INTRAWARE.APPRFOLDER AF ")
               .append("       WHERE AF.KEEPINGPERIODCAUSE = F.BINDID ")
               .append("          OR (AF.BIZUNITCD = TRIM(F.BIZUNITCODE) ")
               .append("              AND AF.FLDRINFOYEAR = F.PRODYEAR ")
               .append("              AND AF.BIZUNITYEARSEQ = F.BIZUNITYEARSEQ ")
               .append("              AND AF.VOLUMESEQ = F.VOLUMESEQ) ")
               .append("  ) ");
        }

        sql.append("ORDER BY F.PROCDEPTCODE, F.PRODYEAR, F.BIZUNITCODE, F.BIZUNITYEARSEQ, F.VOLUMESEQ");

        Map<String, BufferedWriter> writers = new HashMap<>();
        long rowCount = 0;

        try (Statement stmt = conn.createStatement(); ResultSet rs = stmt.executeQuery(sql.toString())) {
            while (rs.next()) {
                String deptCode = rs.getString("PROCDEPTCODE");
                if (deptCode == null || deptCode.trim().isEmpty()) {
                    deptCode = "UNKNOWN";
                }
                deptCode = deptCode.trim();
                deptSet.add(deptCode);

                BufferedWriter bw = writers.get(deptCode);
                if (bw == null) {
                    File deptFile = new File(outputDir, "folder_" + deptCode + ".txt");
                    bw = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(deptFile), StandardCharsets.UTF_8));
                    writers.put(deptCode, bw);
                }

                String folderName = cleanText(rs.getString("FOLDERNAME"));
                String provisionCause = cleanText(rs.getString("PROVISIONCAUSE"));
                String userName = cleanText(rs.getString("DOCPROCUSERNAME"));

                // rtool.sh -t al 표준 콤마 구분자 라인
                String line = String.join(",",
                    deptCode,
                    rs.getString("OLDDOCORGNAME"),
                    rs.getString("PRODYEAR"),
                    rs.getString("BIZUNITCODE"),
                    rs.getString("BIZUNITYEARSEQ"),
                    rs.getString("VOLUMESEQ"),
                    folderName,
                    rs.getString("RECORDINGTYPE"),
                    rs.getString("ENDYEAR"),
                    rs.getString("KEEPINGPERIOD"),
                    rs.getString("KEEPINGMETHOD"),
                    rs.getString("KEEPINGPLACE"),
                    "", // 비치종결일자 공란
                    provisionCause,
                    rs.getString("DOCPROCUSERCODE"),
                    userName,
                    rs.getString("OLDDOCCLSNO")
                );

                bw.write(line);
                bw.newLine();
                rowCount++;
            }
        } finally {
            for (BufferedWriter bw : writers.values()) {
                try { bw.flush(); bw.close(); } catch (Exception ignored) {}
            }
        }

        MigLogger.info(" - 기록물철 분할 완료: 총 " + String.format("%,d", rowCount) + " 건, " + writers.size() + " 개 부서 파일 생성.");
    }

    /**
     * rtool.sh 부서별 순차 구동 쉘 스크립트 자동 생성
     */
    private static void generateRtoolRunnerScript(File baseDir, File bizunitDir, File folderDir, boolean isDeltaMode) throws IOException {
        String scriptName = isDeltaMode ? "run_rtool_delta.sh" : "run_rtool_all.sh";
        File runnerScript = new File(baseDir, scriptName);

        try (BufferedWriter bw = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(runnerScript), StandardCharsets.UTF_8))) {
            bw.write("#!/bin/bash"); bw.newLine();
            bw.write("# =============================================================================="); bw.newLine();
            bw.write("# [통합 MIG] 단위업무 & 기록물철 rtool.sh 부서별 일괄 실행 스크립트 (" + (isDeltaMode ? "증가분 모드" : "전체 모드") + ")"); bw.newLine();
            bw.write("# [rtool.sh 옵션 규격] 단위업무: -t lb -p <file>, 기록물철: -t al -p <file>"); bw.newLine();
            bw.write("# 작성일시 : " + new java.util.Date()); bw.newLine();
            bw.write("# =============================================================================="); bw.newLine();
            bw.newLine();
            bw.write("if [ -x \"${HOME}/jhoms/bin/tools/rtool.sh\" ]; then"); bw.newLine();
            bw.write("    RTOOL_BIN=\"${HOME}/jhoms/bin/tools/rtool.sh\""); bw.newLine();
            bw.write("elif [ -x \"/app/hso10/jhoms/bin/tools/rtool.sh\" ]; then"); bw.newLine();
            bw.write("    RTOOL_BIN=\"/app/hso10/jhoms/bin/tools/rtool.sh\""); bw.newLine();
            bw.write("else"); bw.newLine();
            bw.write("    RTOOL_BIN=\"rtool.sh\""); bw.newLine();
            bw.write("fi"); bw.newLine();
            bw.write("BASE_DIR=\"$(cd \"$(dirname \"$0\")\" && pwd)\""); bw.newLine();
            bw.write("BIZUNIT_DIR=\"${BASE_DIR}/" + bizunitDir.getName() + "\""); bw.newLine();
            bw.write("FOLDER_DIR=\"${BASE_DIR}/" + folderDir.getName() + "\""); bw.newLine();
            bw.write("LOG_DIR=\"${BASE_DIR}/logs\""); bw.newLine();
            bw.write("mkdir -p \"${LOG_DIR}\""); bw.newLine();
            bw.newLine();
            bw.write("if ! command -v \"${RTOOL_BIN}\" >/dev/null 2>&1 && [ ! -x \"${RTOOL_BIN}\" ]; then"); bw.newLine();
            bw.write("    echo \"[오류] rtool.sh 실행 파일이 존재하지 않거나 실행 권한이 없습니다: ${RTOOL_BIN}\""); bw.newLine();
            bw.write("    exit 1"); bw.newLine();
            bw.write("fi"); bw.newLine();
            bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
            bw.write("echo \" [1단계] 단위업무(BIZUNIT) 부서별 rtool.sh (-t lb) 등록 시작\""); bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
            bw.write("BU_CNT=0; BU_ERR=0"); bw.newLine();
            bw.write("for f in ${BIZUNIT_DIR}/bizunit_*.txt; do"); bw.newLine();
            bw.write("    [ -e \"$f\" ] || continue"); bw.newLine();
            bw.write("    dept=$(basename \"$f\" .txt | cut -d'_' -f2)"); bw.newLine();
            bw.write("    BU_CNT=$((BU_CNT + 1))"); bw.newLine();
            bw.write("    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] >>> [단위업무 #${BU_CNT}] 부서코드: ${dept} 로드 중...\""); bw.newLine();
            bw.write("    \"${RTOOL_BIN}\" -t lb -p \"$f\" >> \"${LOG_DIR}/rtool_bizunit_${dept}.log\" 2>&1"); bw.newLine();
            bw.write("    if [ $? -ne 0 ]; then"); bw.newLine();
            bw.write("        echo \"  [경고] 부서 ${dept} 단위업무 등록 오류! 확인: ${LOG_DIR}/rtool_bizunit_${dept}.log\""); bw.newLine();
            bw.write("        BU_ERR=$((BU_ERR + 1))"); bw.newLine();
            bw.write("    fi"); bw.newLine();
            bw.write("done"); bw.newLine();
            bw.newLine();
            bw.write("echo \"\""); bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
            bw.write("echo \" [2단계] 기록물철(FOLDER) 부서별 rtool.sh (-t al) 등록 시작\""); bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
            bw.write("FLDR_CNT=0; FLDR_ERR=0"); bw.newLine();
            bw.write("for f in ${FOLDER_DIR}/folder_*.txt; do"); bw.newLine();
            bw.write("    [ -e \"$f\" ] || continue"); bw.newLine();
            bw.write("    dept=$(basename \"$f\" .txt | cut -d'_' -f2)"); bw.newLine();
            bw.write("    FLDR_CNT=$((FLDR_CNT + 1))"); bw.newLine();
            bw.write("    echo \"[$(date +'%Y-%m-%d %H:%M:%S')] >>> [기록물철 #${FLDR_CNT}] 부서코드: ${dept} 로드 중...\""); bw.newLine();
            bw.write("    \"${RTOOL_BIN}\" -t al -p \"$f\" >> \"${LOG_DIR}/rtool_folder_${dept}.log\" 2>&1"); bw.newLine();
            bw.write("    if [ $? -ne 0 ]; then"); bw.newLine();
            bw.write("        echo \"  [경고] 부서 ${dept} 기록물철 등록 오류! 확인: ${LOG_DIR}/rtool_folder_${dept}.log\""); bw.newLine();
            bw.write("        FLDR_ERR=$((FLDR_ERR + 1))"); bw.newLine();
            bw.write("    fi"); bw.newLine();
            bw.write("done"); bw.newLine();
            bw.newLine();
            bw.write("echo \"\""); bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
            bw.write("echo \" [결과 요약] rtool.sh 부서별 일괄 실행 완료\""); bw.newLine();
            bw.write("echo \" - 단위업무 : 총 ${BU_CNT} 개 부서 완료 (오류: ${BU_ERR} 건)\""); bw.newLine();
            bw.write("echo \" - 기록물철 : 총 ${FLDR_CNT} 개 부서 완료 (오류: ${FLDR_ERR} 건)\""); bw.newLine();
            bw.write("echo \" 다음 단계: ./build_and_run.sh post-rtool (명칭 복구 및 결재 편철 MERGE)\""); bw.newLine();
            bw.write("echo \"=====================================================================\""); bw.newLine();
        }

        runnerScript.setExecutable(true);
        MigLogger.info(" - rtool.sh 실행 쉘 스크립트 생성 완료: " + runnerScript.getAbsolutePath());
    }

    private static String cleanText(String str) {
        if (str == null) return "";
        return str.replace(",", "^")
                  .replace("(", "#")
                  .replace(")", "\\")
                  .replace("/", "l")
                  .replace("\r", " ")
                  .replace("\n", " ")
                  .trim();
    }
}
