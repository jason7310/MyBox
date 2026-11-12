package com.handy.mig;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * [통합 MIG] 조직도 관리자 화면 업로드용 CSV 일괄 추출기 (Java 17 호환 / UTF-8)
 * 
 * - 대상 DBMS : Tibero 7
 * - 소스 스키마: MIG1_USER (MIG_DEPT, MIG_POS, MIG_RANK, MIG_USER, MIG_GROUP, MIG_GROUP_MEMBER)
 * - 인코딩   : UTF-8 (기본 표준 인코딩)
 * - 출력 경로 : output/csv/
 * 
 * - 추출 목록:
 *   1) dept_normal.csv   : 정상 부서 (ISUSE = '1', 계층 순 정렬, ADD)
 *   2) dept_deleted.csv  : 삭제/폐지 부서 (ISUSE = '0', DEL)
 *   3) pos.csv           : 직위 정보 (ADD)
 *   4) rank.csv          : 직급 정보 (ADD)
 *   5) user_normal.csv   : 정상 재직 사용자 (ISUSE = '1', ADD)
 *   6) user_deleted.csv  : 삭제/퇴직 사용자 (ISUSE = '0', DEL)
 *   7) group.csv         : 사용자 그룹 (ADD)
 *   8) group_member.csv  : 그룹 구성원 (ADD)
 *   9) auth.csv          : 사용자 권한 정보 (부서장, 접수/발송담당 등, ADD)
 */
public class OrgCsvExporter {

    private static final String DEFAULT_OUTPUT_DIR = "output/csv";

    // 태스크 정의 (출력파일명 -> 쿼리)
    private static final Map<String, TaskInfo> TASKS = new LinkedHashMap<>();

    static {
        // 1. 부서 - 정상
        TASKS.put("dept_normal.csv", new TaskInfo("정상 부서 추출",
            "SELECT '*operation,deptname,deptcode,parcode,seq,site,abbreviation,boxf,recvf,modifydate,deptname2,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(DEPTCODE) " +
            "|| ',' || TRIM(NVL(PARCODE, '000000000')) " +
            "|| ',' || NVL(TO_CHAR(SEQ), '1') " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ') " +
            "|| ',' || NVL(BOXF, '1') " +
            "|| ',' || NVL(RECVF, '1') " +
            "|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ') " +
            "|| ',,,,,,,,,,' " +
            "FROM ( " +
            "    SELECT D.* FROM MIG1_USER.MG_DEPT D " +
            "    WHERE NVL(D.DELETED, 0) = 0 " +
            "    START WITH D.PARCODE IS NULL OR D.PARCODE = '0' OR D.PARCODE = '000000000' OR D.PARCODE = D.DEPTCODE " +
            "    CONNECT BY PRIOR D.DEPTCODE = D.PARCODE " +
            "    ORDER SIBLINGS BY D.SEQ, D.DEPTCODE " +
            ")"
        ));

        // 2. 부서 - 삭제
        TASKS.put("dept_deleted.csv", new TaskInfo("삭제 부서 추출",
            "SELECT '*operation,deptname,deptcode,parcode,seq,site,abbreviation,boxf,recvf,modifydate,deptname2,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'DEL,' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(DEPTCODE) " +
            "|| ',' || TRIM(NVL(PARCODE, '000000000')) " +
            "|| ',' || NVL(TO_CHAR(SEQ), '1') " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ') " +
            "|| ',' || '0' " +
            "|| ',' || '0' " +
            "|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ') " +
            "|| ',,,,,,,,,,' " +
            "FROM MIG1_USER.MG_DEPT " +
            "WHERE NVL(DELETED, 0) = 1 " +
            "ORDER BY SEQ, DEPTCODE"
        ));

        // 2-2. 부서 - 전체 일괄 (삭제여부 불문 ALL-ADD)
        TASKS.put("dept_all.csv", new TaskInfo("전체 부서 일괄(ALL-ADD) 추출",
            "SELECT '*operation,deptname,deptcode,parcode,seq,site,abbreviation,boxf,recvf,modifydate,deptname2,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(DEPTCODE) " +
            "|| ',' || TRIM(NVL(PARCODE, '000000000')) " +
            "|| ',' || NVL(TO_CHAR(SEQ), '1') " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ') " +
            "|| ',' || NVL(BOXF, '1') " +
            "|| ',' || NVL(RECVF, '1') " +
            "|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ') " +
            "|| ',,,,,,,,,,' " +
            "FROM ( " +
            "    SELECT D.* FROM MIG1_USER.MG_DEPT D " +
            "    WHERE D.DEPTCODE IS NOT NULL " +
            "    START WITH D.PARCODE IS NULL OR D.PARCODE = '0' OR D.PARCODE = '000000000' OR D.PARCODE = D.DEPTCODE " +
            "    CONNECT BY PRIOR D.DEPTCODE = D.PARCODE " +
            "    ORDER SIBLINGS BY D.SEQ, D.DEPTCODE " +
            ")"
        ));

        // 3. 직위
        TASKS.put("pos.csv", new TaskInfo("직위 정보 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 POS INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,posname,poscode,seclevel,sanclevel' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(POSNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(POSCODE) " +
            "|| ',' || NVL(TO_CHAR(POSLEVEL), '100') " +
            "|| ',' || NVL(TO_CHAR(POSLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT POSCODE, POSNAME, NVL(POSLEVEL, 100) AS POSLEVEL, NVL(POSSEQ, 1) AS POSSEQ " +
            "    FROM MIG1_USER.MG_POS " +
            "    WHERE POSNAME IS NOT NULL " +
            "    ORDER BY POSLEVEL ASC, POSSEQ ASC, POSCODE ASC " +
            ")"
        ));

        // 4. 직급
        TASKS.put("rank.csv", new TaskInfo("직급 정보 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 RANK INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,rankname,rankcode,ranklevel' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(RANKNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(RANKCODE) " +
            "|| ',' || NVL(TO_CHAR(RANKLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT RANKCODE, RANKNAME, NVL(RANKLEVEL, 100) AS RANKLEVEL, NVL(RANKDEL, 1) AS RANKDEL " +
            "    FROM MIG1_USER.MG_RANK " +
            "    WHERE RANKNAME IS NOT NULL " +
            "    ORDER BY RANKLEVEL ASC, RANKDEL ASC, RANKCODE ASC " +
            ")"
        ));

        // 5. 사용자 - 정상 재직자
        TASKS.put("user_normal.csv", new TaskInfo("정상 재직 사용자 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "|| ',' || TRIM(U.DEPTCODE) " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ') " +
            "|| ',' || NVL(U.PASSWORD, '') " +
            "|| ',' || NVL(TO_CHAR(U.SECURITY), '100') " +
            "|| ',' || NVL(TO_CHAR(U.SANCLEVEL), '100') " +
            "|| ',' || '1' " +
            "|| ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ') " +
            "|| ',' || NVL(U.SEX, '0') " +
            "|| ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.FAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.SSN, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "|| ',' || '' " +
            "|| ',,,,,,,,,,,,,,,,,,,,' " +
            "FROM MIG1_USER.MG_USER U " +
            "WHERE NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') " +
            "ORDER BY U.DEPTCODE, U.EMPCODE"
        ));

        // 6. 사용자 - 삭제/퇴직자
        TASKS.put("user_deleted.csv", new TaskInfo("삭제/퇴직 사용자 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'DEL,' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "|| ',' || TRIM(U.DEPTCODE) " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ') " +
            "|| ',' || '' " +
            "|| ',' || '0' " +
            "|| ',' || '0' " +
            "|| ',' || '1' " +
            "|| ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || '' " +
            "|| ',' || NVL(U.SEX, '0') " +
            "|| ',,,,,,,,,,,,,' " +
            "|| ',' || '[퇴직자]' " +
            "|| ',' || '' " +
            "|| ',,,,,,,,,,,,,,,,,,,,' " +
            "FROM MIG1_USER.MG_USER U " +
            "WHERE NVL(U.ISUSE, '1') NOT IN ('1', 'Y', 'y') " +
            "ORDER BY U.DEPTCODE, U.EMPCODE"
        ));

        // 6-2. 사용자 - 전체 일괄 (재직/퇴직 불문 ALL-ADD)
        TASKS.put("user_all.csv", new TaskInfo("전체 사용자 일괄(ALL-ADD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "|| ',' || TRIM(U.DEPTCODE) " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ') " +
            "|| ',' || CASE WHEN NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') THEN NVL(U.PASSWORD, '') ELSE '!' END " +
            "|| ',' || CASE WHEN NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') THEN NVL(TO_CHAR(U.SECURITY), '100') ELSE '0' END " +
            "|| ',' || CASE WHEN NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') THEN NVL(TO_CHAR(U.SANCLEVEL), '100') ELSE '0' END " +
            "|| ',' || '1' " +
            "|| ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ') " +
            "|| ',' || NVL(U.SEX, '0') " +
            "|| ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.FAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.SSN, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ') " +
            "|| ',' || CASE WHEN NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') " +
            "               THEN REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "               ELSE '[퇴직자]' END " +
            "|| ',' || '' " +
            "|| ',,,,,,,,,,,,,,,,,,,,' " +
            "FROM MIG1_USER.MG_USER U " +
            "WHERE U.EMPCODE IS NOT NULL OR U.USER_ID IS NOT NULL " +
            "ORDER BY U.DEPTCODE, U.EMPCODE"
        ));

        // 7. 그룹
        TASKS.put("group.csv", new TaskInfo("사용자 그룹 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,group_id,user_id,application,group_name,g_desc' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(NVL(G.HANDY_ID, G.GROUP_ID)) " +
            "|| ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM')) " +
            "|| ',' || NVL(G.APPLICATION, '0') " +
            "|| ',' || REPLACE(REPLACE(NVL(G.GROUP_NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(G.GROUP_DESC, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "FROM MIG1_USER.MG_GROUP G " +
            "WHERE G.GROUP_NAME IS NOT NULL " +
            "ORDER BY G.APPLICATION, G.GROUP_ID"
        ));

        // 8. 그룹멤버
        TASKS.put("group_member.csv", new TaskInfo("그룹 구성원 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP_MEMBER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,group_id,seq,user_id,member_id,type,email' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID)) " +
            "|| ',' || NVL(TO_CHAR(GM.MEMBER_SEQ), '1') " +
            "|| ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM')) " +
            "|| ',' || TRIM(GM.MEMBER_CODE) " +
            "|| ',' || NVL(GM.MEMBER_TYPE, '0') " +
            "|| ',' || '' " +
            "FROM MIG1_USER.MG_GROUP_MEMBER GM " +
            "LEFT JOIN MIG1_USER.MG_GROUP G ON GM.GROUP_ID = G.GROUP_ID " +
            "WHERE GM.MEMBER_CODE IS NOT NULL " +
            "ORDER BY GM.GROUP_ID, GM.MEMBER_SEQ"
        ));

        // 9. 권한 (방안 1: 인라인 매핑 변환 적용)
        TASKS.put("auth.csv", new TaskInfo("사용자 권한 정보 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 AUTH INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*OPERATION,EMPCODE,AUTHCODE,RELCODE' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(A.EMPCODE) " +
            "|| ',' || CASE TRIM(A.AUTHCODE) " +
            "              WHEN '7105' THEN 'S1' " +
            "              WHEN '2001' THEN 'D1' " +
            "              WHEN '2002' THEN 'D4' " +
            "              WHEN '2004' THEN 'Da' " +
            "              WHEN '8002' THEN 'D5' " +
            "              WHEN '1009' THEN 'D1' " +
            "              ELSE TRIM(A.AUTHCODE) " +
            "          END " +
            "|| ',' || TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000'))) " +
            "FROM ( " +
            "    SELECT DISTINCT EMPCODE, AUTHCODE, DEPTCODE, EMPCODE2 " +
            "    FROM MIG1_USER.MG_AUTH " +
            "    WHERE EMPCODE IS NOT NULL AND AUTHCODE IS NOT NULL " +
            "    ORDER BY AUTHCODE ASC, EMPCODE ASC " +
            ")"
        ));

        // 10. 부서 증가분 (ADD / MOD, DEL 배제)
        TASKS.put("dept_delta.csv", new TaskInfo("오픈 당일 부서 증가분(ADD/MOD) 추출",
            "SELECT '*operation,deptname,deptcode,parcode,seq,site,abbreviation,boxf,recvf,modifydate,deptname2,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(D.DEPTNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(D.DEPTCODE) " +
            "|| ',' || TRIM(NVL(D.PARCODE, '000000000')) " +
            "|| ',' || NVL(TO_CHAR(D.SEQ), '1') " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(D.ABBREVIATION, ''), ',', ' ') " +
            "|| ',' || NVL(D.BOXF, '1') " +
            "|| ',' || NVL(D.RECVF, '1') " +
            "|| ',' || TO_CHAR(NVL(D.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(D.DEPTNAME2, ''), ',', ' ') " +
            "|| ',,,,,,,,,,' " +
            "FROM MIG1_USER.MG_DEPT D " +
            "WHERE NVL(D.DELETED, 0) = 0 " +
            "  AND NOT EXISTS (SELECT 1 FROM INTRAWARE.DEPT_GLOBAL DG WHERE DG.DEPT_CODE = TRIM(D.DEPTCODE)) " +
            "UNION ALL " +
            "SELECT 'MOD,' || REPLACE(REPLACE(NVL(D.DEPTNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(D.DEPTCODE) " +
            "|| ',' || TRIM(NVL(D.PARCODE, '000000000')) " +
            "|| ',' || NVL(TO_CHAR(D.SEQ), '1') " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(D.ABBREVIATION, ''), ',', ' ') " +
            "|| ',' || NVL(D.BOXF, '1') " +
            "|| ',' || NVL(D.RECVF, '1') " +
            "|| ',' || TO_CHAR(NVL(D.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(D.DEPTNAME2, ''), ',', ' ') " +
            "|| ',,,,,,,,,,' " +
            "FROM MIG1_USER.MG_DEPT D " +
            "JOIN INTRAWARE.DEPT_GLOBAL DG ON DG.DEPT_CODE = TRIM(D.DEPTCODE) " +
            "WHERE NVL(D.DELETED, 0) = 0 " +
            "  AND (NVL(D.DEPTNAME, ' ') <> NVL(DG.DEPT_NAME, ' ') " +
            "       OR TRIM(NVL(D.PARCODE, '000000000')) <> NVL((SELECT PAR_DEPT_CODE FROM INTRAWARE.DEPT_GLOBAL WHERE DEPT_ID = DG.PAR_DEPT_ID), '000000000'))"
        ));

        // 11. 사용자 증가분 (ADD / MOD, DEL 배제)
        TASKS.put("user_delta.csv", new TaskInfo("오픈 당일 사용자 증가분(ADD/MOD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "|| ',' || TRIM(U.DEPTCODE) " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ') " +
            "|| ',' || NVL(U.PASSWORD, '') " +
            "|| ',' || NVL(TO_CHAR(U.SECURITY), '100') " +
            "|| ',' || NVL(TO_CHAR(U.SANCLEVEL), '100') " +
            "|| ',' || '1' " +
            "|| ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ') " +
            "|| ',' || NVL(U.SEX, '0') " +
            "|| ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.FAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.SSN, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "|| ',' || '' " +
            "|| ',,,,,,,,,,,,,,,,,,,,' " +
            "FROM MIG1_USER.MG_USER U " +
            "WHERE NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') " +
            "  AND NOT EXISTS (SELECT 1 FROM INTRAWARE.USR_GLOBAL UG WHERE UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))) " +
            "UNION ALL " +
            "SELECT 'MOD,' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "|| ',' || TRIM(U.DEPTCODE) " +
            "|| ',' || 'site' " +
            "|| ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ') " +
            "|| ',' || NVL(U.PASSWORD, '') " +
            "|| ',' || NVL(TO_CHAR(U.SECURITY), '100') " +
            "|| ',' || NVL(TO_CHAR(U.SANCLEVEL), '100') " +
            "|| ',' || '1' " +
            "|| ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS') " +
            "|| ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ') " +
            "|| ',' || NVL(U.SEX, '0') " +
            "|| ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.FAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.SSN, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ') " +
            "|| ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "|| ',' || '' " +
            "|| ',,,,,,,,,,,,,,,,,,,,' " +
            "FROM MIG1_USER.MG_USER U " +
            "JOIN INTRAWARE.USR_GLOBAL UG ON UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID)) " +
            "WHERE NVL(U.ISUSE, '1') IN ('1', 'Y', 'y') " +
            "  AND (TRIM(U.DEPTCODE) <> NVL((SELECT DEPT_CODE FROM INTRAWARE.DEPT_GLOBAL WHERE DEPT_ID = UG.DEPT_ID), ' ') " +
            "       OR NVL(U.NAME, ' ') <> NVL(UG.USER_NAME, ' ') " +
            "       OR NVL(U.POSNAME, ' ') <> NVL((SELECT TR_VAL FROM INTRAWARE.TR_DATA WHERE TR_ID = UG.TR_ID AND TR_COL = 'POSITIONNAME' AND ROWNUM = 1), ' '))"
        ));

        // 12. 직위 증가분 (ADD / MOD)
        TASKS.put("pos_delta.csv", new TaskInfo("오픈 당일 직위 증가분(ADD/MOD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 POS INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,posname,poscode,seclevel,sanclevel' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(P.POSNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(P.POSCODE) " +
            "|| ',' || NVL(TO_CHAR(P.POSLEVEL), '100') " +
            "|| ',' || NVL(TO_CHAR(P.POSLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT POSCODE, POSNAME, NVL(POSLEVEL, 100) AS POSLEVEL " +
            "    FROM MIG1_USER.MG_POS " +
            "    WHERE POSNAME IS NOT NULL " +
            ") P " +
            "WHERE NOT EXISTS (SELECT 1 FROM INTRAWARE.POS IP WHERE IP.POS_ID = TRIM(P.POSCODE)) " +
            "UNION ALL " +
            "SELECT 'MOD,' || REPLACE(REPLACE(NVL(P.POSNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(P.POSCODE) " +
            "|| ',' || NVL(TO_CHAR(P.POSLEVEL), '100') " +
            "|| ',' || NVL(TO_CHAR(P.POSLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT POSCODE, POSNAME, NVL(POSLEVEL, 100) AS POSLEVEL " +
            "    FROM MIG1_USER.MG_POS " +
            "    WHERE POSNAME IS NOT NULL " +
            ") P " +
            "JOIN INTRAWARE.POS IP ON IP.POS_ID = TRIM(P.POSCODE) " +
            "WHERE TRIM(IP.POS_NAME) <> TRIM(P.POSNAME) OR NVL(IP.POS_LEVEL, 100) <> NVL(P.POSLEVEL, 100)"
        ));

        // 13. 직급 증가분 (ADD / MOD)
        TASKS.put("rank_delta.csv", new TaskInfo("오픈 당일 직급 증가분(ADD/MOD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 RANK INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,rankname,rankcode,ranklevel' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || REPLACE(REPLACE(NVL(R.RANKNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(R.RANKCODE) " +
            "|| ',' || NVL(TO_CHAR(R.RANKLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT RANKCODE, RANKNAME, NVL(RANKLEVEL, 100) AS RANKLEVEL " +
            "    FROM MIG1_USER.MG_RANK " +
            "    WHERE RANKNAME IS NOT NULL " +
            ") R " +
            "WHERE NOT EXISTS (SELECT 1 FROM INTRAWARE.RANK IR WHERE IR.RANK_ID = TRIM(R.RANKCODE)) " +
            "UNION ALL " +
            "SELECT 'MOD,' || REPLACE(REPLACE(NVL(R.RANKNAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || TRIM(R.RANKCODE) " +
            "|| ',' || NVL(TO_CHAR(R.RANKLEVEL), '100') " +
            "FROM ( " +
            "    SELECT DISTINCT RANKCODE, RANKNAME, NVL(RANKLEVEL, 100) AS RANKLEVEL " +
            "    FROM MIG1_USER.MG_RANK " +
            "    WHERE RANKNAME IS NOT NULL " +
            ") R " +
            "JOIN INTRAWARE.RANK IR ON IR.RANK_ID = TRIM(R.RANKCODE) " +
            "WHERE TRIM(IR.RANK_NAME) <> TRIM(R.RANKNAME) OR NVL(IR.RANK_LEVEL, 100) <> NVL(R.RANKLEVEL, 100)"
        ));

        // 14. 그룹 증가분 (ADD / MOD)
        TASKS.put("group_delta.csv", new TaskInfo("오픈 당일 그룹 증가분(ADD/MOD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,group_id,user_id,application,group_name,g_desc' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(NVL(G.HANDY_ID, G.GROUP_ID)) " +
            "|| ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM')) " +
            "|| ',' || NVL(G.APPLICATION, '0') " +
            "|| ',' || REPLACE(REPLACE(NVL(G.GROUP_NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(G.GROUP_DESC, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "FROM MIG1_USER.MG_GROUP G " +
            "WHERE G.GROUP_NAME IS NOT NULL " +
            "  AND NOT EXISTS (SELECT 1 FROM INTRAWARE.G_LIST IG WHERE IG.GROUP_ID = TRIM(NVL(G.HANDY_ID, G.GROUP_ID))) " +
            "UNION ALL " +
            "SELECT 'MOD,' || TRIM(NVL(G.HANDY_ID, G.GROUP_ID)) " +
            "|| ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM')) " +
            "|| ',' || NVL(G.APPLICATION, '0') " +
            "|| ',' || REPLACE(REPLACE(NVL(G.GROUP_NAME, ' '), ',', ' '), '\"', '\"\"') " +
            "|| ',' || REPLACE(REPLACE(REPLACE(NVL(G.GROUP_DESC, ''), ',', ' '), CHR(13), ''), CHR(10), '') " +
            "FROM MIG1_USER.MG_GROUP G " +
            "JOIN INTRAWARE.G_LIST IG ON IG.GROUP_ID = TRIM(NVL(G.HANDY_ID, G.GROUP_ID)) " +
            "WHERE G.GROUP_NAME IS NOT NULL " +
            "  AND TRIM(IG.NAME) <> TRIM(G.GROUP_NAME)"
        ));

        // 15. 그룹멤버 증가분 (ADD)
        TASKS.put("group_member_delta.csv", new TaskInfo("오픈 당일 그룹멤버 증가분(ADD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP_MEMBER INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*operation,group_id,seq,user_id,member_id,type,email' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID)) " +
            "|| ',' || NVL(TO_CHAR(GM.MEMBER_SEQ), '1') " +
            "|| ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM')) " +
            "|| ',' || TRIM(GM.MEMBER_CODE) " +
            "|| ',' || NVL(GM.MEMBER_TYPE, '0') " +
            "|| ',' || '' " +
            "FROM MIG1_USER.MG_GROUP_MEMBER GM " +
            "LEFT JOIN MIG1_USER.MG_GROUP G ON GM.GROUP_ID = G.GROUP_ID " +
            "WHERE GM.MEMBER_CODE IS NOT NULL " +
            "  AND NOT EXISTS ( " +
            "      SELECT 1 FROM INTRAWARE.G_MEMBER IGM " +
            "      WHERE IGM.GROUP_ID = TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID)) " +
            "        AND IGM.MEMBER_ID = TRIM(GM.MEMBER_CODE) " +
            "  )"
        ));

        // 16. 사용자 권한 증가분 (ADD)
        TASKS.put("auth_delta.csv", new TaskInfo("오픈 당일 신규 권한 증가분(ADD) 추출",
            "SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 AUTH INFO VERSION 1.0' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT '*OPERATION,EMPCODE,AUTHCODE,RELCODE' AS csv_row FROM DUAL " +
            "UNION ALL " +
            "SELECT 'ADD,' || TRIM(MA.EMPCODE) " +
            "|| ',' || MA.HANDY_AUTH " +
            "|| ',' || TRIM(MA.DEPTCODE) " +
            "FROM ( " +
            "    SELECT DISTINCT " +
            "           TRIM(A.EMPCODE) AS EMPCODE, " +
            "           CASE TRIM(A.AUTHCODE) " +
            "               WHEN '7105' THEN 'S1' " +
            "               WHEN '2001' THEN 'D1' " +
            "               WHEN '2002' THEN 'D4' " +
            "               WHEN '2004' THEN 'Da' " +
            "               WHEN '8002' THEN 'D5' " +
            "               WHEN '1009' THEN 'D1' " +
            "               ELSE SUBSTR(TRIM(A.AUTHCODE), 1, 2) " +
            "           END AS HANDY_AUTH, " +
            "           TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000'))) AS DEPTCODE " +
            "    FROM MIG1_USER.MG_AUTH A " +
            "    WHERE A.EMPCODE IS NOT NULL AND A.AUTHCODE IS NOT NULL " +
            ") MA " +
            "WHERE NOT EXISTS ( " +
            "    SELECT 1 FROM INTRAWARE.USR_AUTH UA " +
            "    WHERE UA.USER_ID = MA.EMPCODE " +
            "      AND UA.AUTH = MA.HANDY_AUTH " +
            "      AND UA.REL_ID = MA.DEPTCODE " +
            ")"
        ));
    }

    public static void main(String[] args) {
        String target = (args.length >= 1) ? args[0].toLowerCase() : "all";
        String outputDir = (args.length >= 2) ? args[1] : DEFAULT_OUTPUT_DIR;

        MigLogger.init("org_csv_export");

        log("=========================================================================");
        log(" [Handy MIG] 조직도 E/F CSV 일괄 추출 도구 (UTF-8 인코딩)");
        log(" - 대상 작업 : " + target);
        log(" - 출력 디렉토리: " + outputDir);
        log(" - 로그 파일 : " + MigLogger.getLogFilePath());
        log("=========================================================================");

        File outDir = new File(outputDir);
        if (!outDir.exists()) {
            outDir.mkdirs();
        }

        long totalStartTime = System.currentTimeMillis();
        int successCount = 0;
        int failCount = 0;

        try (Connection conn = DbConfig.getConnection()) {
            log("Tibero 7 데이터베이스 접속 성공 (" + DbConfig.getUsername() + "@" + DbConfig.getUrl() + ")");

            for (Map.Entry<String, TaskInfo> entry : TASKS.entrySet()) {
                String fileName = entry.getKey();
                TaskInfo task = entry.getValue();

                // 대상 작업 필터링
                if ("delta".equals(target)) {
                    // delta 모드: 증가분 전용 파일만 추출 (dept_delta.csv, user_delta.csv)
                    if (!fileName.contains("delta")) {
                        continue;
                    }
                } else if ("all".equals(target)) {
                    // all 모드: 초기 전체 적재용 파일만 추출 (delta 파일 제외)
                    if (fileName.contains("delta")) {
                        continue;
                    }
                } else {
                    // 특정 파일명이나 키워드 검색
                    if (!fileName.contains(target) && !task.title.toLowerCase().contains(target)) {
                        continue;
                    }
                }

                File targetFile = new File(outDir, fileName);
                log("-------------------------------------------------------------------------");
                log("[추출 시작] " + task.title + " -> " + targetFile.getPath());

                long taskStartTime = System.currentTimeMillis();
                try {
                    int lineCount = exportQueryToCsv(conn, task.sql, targetFile);
                    long elapsed = System.currentTimeMillis() - taskStartTime;
                    log(String.format(" -> 완료: %,d 건 추출 (소요시간: %,d ms, 크기: %,d bytes, 인코딩: UTF-8)",
                            lineCount, elapsed, targetFile.length()));
                    successCount++;
                } catch (Exception e) {
                    log("[ERROR] " + task.title + " 추출 실패: " + e.getMessage());
                    e.printStackTrace();
                    failCount++;
                }
            }

        } catch (SQLException e) {
            log("[FATAL ERROR] 데이터베이스 접속 실패: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }

        long totalElapsed = System.currentTimeMillis() - totalStartTime;
        log("=========================================================================");
        log(String.format(" [추출 요약] 성공: %d건 / 실패: %d건 / 총 소요시간: %,d ms", successCount, failCount, totalElapsed));
        log(" [출력 폴더] " + outDir.getAbsolutePath());
        log("=========================================================================");

        if (failCount > 0) {
            System.exit(2);
        }
    }

    /**
     * SQL 쿼리를 실행하여 첫 번째 컬럼을 UTF-8 CSV 파일로 스트리밍 저장
     */
    private static int exportQueryToCsv(Connection conn, String sql, File outputFile) throws SQLException, IOException {
        int count = 0;

        // UTF-8 인코딩으로 OutputStreamWriter 생성 (버퍼 64KB)
        try (Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql);
             FileOutputStream fos = new FileOutputStream(outputFile);
             OutputStreamWriter osw = new OutputStreamWriter(fos, StandardCharsets.UTF_8);
             BufferedWriter writer = new BufferedWriter(osw, 65536)) {

            // fetchSize 튜닝 (네트워크 라운드트립 최소화)
            stmt.setFetchSize(1000);

            while (rs.next()) {
                String line = rs.getString(1);
                if (line != null) {
                    writer.write(line);
                    writer.newLine();
                    count++;
                }
            }
            writer.flush();
        }

        return count;
    }

    private static void log(String msg) {
        MigLogger.info(msg);
    }

    private static class TaskInfo {
        final String title;
        final String sql;

        TaskInfo(String title, String sql) {
            this.title = title;
            this.sql = sql;
        }
    }
}
