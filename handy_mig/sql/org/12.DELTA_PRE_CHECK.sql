-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 12. 오픈 당일 조직도 증가분(Delta) 사전 검증 및 건수 요약 진단 (Argus 감사용)
-- 
-- * 목적: CSV 추출 및 관리자 업로드 전, 증가분(ADD/MODIFY) 건수 및 상세 명단 사전 전수 감사
-- * 원칙: DEL(삭제/퇴직) 제외, 정상 재직/사용 부서만 집계
-- ============================================================================

-- 1. 부서 증가분 요약 집계
SELECT '부서 증가분 요약' AS CATEGORY,
       SUM(CASE WHEN DG.DEPT_CODE IS NULL THEN 1 ELSE 0 END) AS ADD_COUNT,
       SUM(CASE WHEN DG.DEPT_CODE IS NOT NULL AND (
           TRIM(DG.DEPT_NAME) <> TRIM(D.DEPTNAME)
           OR NVL(TRIM(DG_PAR.DEPT_CODE), '000000000') <> TRIM(NVL(D.PARCODE, '000000000'))
           OR NVL(TRIM(DG.ABBREVIATION), ' ') <> NVL(TRIM(D.ABBREVIATION), ' ')
           OR NVL(DG.SEQ, 1) <> NVL(D.SEQ, 1)
           OR NVL(DG.BOX_F, '1') <> NVL(D.BOXF, '1')
           OR NVL(DG.RECV_BOX_F, '1') <> NVL(D.RECVF, '1')
       ) THEN 1 ELSE 0 END) AS MOD_COUNT,
       COUNT(*) AS TOTAL_CANDIDATE
  FROM MIG1_USER.MG_DEPT D
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG
    ON DG.DEPT_CODE = TRIM(D.DEPTCODE)
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_PAR
    ON DG.PAR_ID = DG_PAR.DEPT_ID
 WHERE NVL(D.DELETED, 0) = 0;


-- 2. 사용자 증가분 요약 집계
SELECT '사용자 증가분 요약' AS CATEGORY,
       SUM(CASE WHEN UG.EMP_CODE IS NULL THEN 1 ELSE 0 END) AS ADD_COUNT,
       SUM(CASE WHEN UG.EMP_CODE IS NOT NULL AND (
           NVL(TRIM(DG.DEPT_CODE), ' ') <> TRIM(U.DEPTCODE)
           OR NVL(TRIM(UG.POS_NAME), ' ') <> NVL(TRIM(U.POSNAME), ' ')
           OR NVL(TRIM(UG.RANK_NAME), ' ') <> NVL(TRIM(U.RANKNAME), ' ')
           OR NVL(TRIM(UG.DUTY_NAME), ' ') <> NVL(TRIM(U.DUTYNAME), ' ')
           OR TRIM(UG.NAME) <> TRIM(U.NAME)
           OR NVL(TRIM(UG.MOBILE_PHONE), ' ') <> NVL(TRIM(U.MOBILEPHONE), ' ')
           OR NVL(TRIM(UG.E_MAIL), ' ') <> NVL(TRIM(U.EMAIL), ' ')
           OR NVL(TRIM(UG.PHONE), ' ') <> NVL(TRIM(U.PHONE), ' ')
       ) THEN 1 ELSE 0 END) AS MOD_COUNT,
       COUNT(*) AS TOTAL_ACTIVE_CANDIDATE
  FROM MIG1_USER.MG_USER U
  LEFT JOIN INTRAWARE.USR_GLOBAL UG
    ON UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG
    ON UG.DEPT_ID = DG.DEPT_ID
 WHERE NVL(U.DELETED, 0) IN (0, 1);


-- 3. [상세 명단] 신규 입사자 명단 (ADD)
SELECT '신규 입사자' AS TYPE,
       TRIM(NVL(U.EMPCODE, U.USER_ID)) AS EMP_CODE,
       TRIM(U.NAME) AS NAME,
       TRIM(U.DEPTCODE) AS DEPT_CODE,
       TRIM(U.POSNAME) AS POS_NAME,
       TRIM(U.RANKNAME) AS RANK_NAME
  FROM MIG1_USER.MG_USER U
 WHERE NVL(U.DELETED, 0) IN (0, 1)
   AND NOT EXISTS (
       SELECT 1 
         FROM INTRAWARE.USR_GLOBAL UG 
        WHERE UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))
   )
 ORDER BY U.DEPTCODE, U.EMPCODE;


-- 4. [상세 명단] 부서 이동 및 승진자 명단 (MOD)
SELECT '부서이동/승진' AS TYPE,
       UG.EMP_CODE,
       UG.NAME,
       DG.DEPT_CODE AS OLD_DEPT_CODE,
       TRIM(U.DEPTCODE) AS NEW_DEPT_CODE,
       UG.POS_NAME AS OLD_POS,
       TRIM(U.POSNAME) AS NEW_POS,
       UG.RANK_NAME AS OLD_RANK,
       TRIM(U.RANKNAME) AS NEW_RANK
  FROM MIG1_USER.MG_USER U
  JOIN INTRAWARE.USR_GLOBAL UG
    ON UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG
    ON UG.DEPT_ID = DG.DEPT_ID
 WHERE NVL(U.DELETED, 0) IN (0, 1)
   AND (
       NVL(TRIM(DG.DEPT_CODE), ' ') <> TRIM(U.DEPTCODE)
       OR NVL(TRIM(UG.POS_NAME), ' ') <> NVL(TRIM(U.POSNAME), ' ')
       OR NVL(TRIM(UG.RANK_NAME), ' ') <> NVL(TRIM(U.RANKNAME), ' ')
       OR NVL(TRIM(UG.DUTY_NAME), ' ') <> NVL(TRIM(U.DUTYNAME), ' ')
       OR TRIM(UG.NAME) <> TRIM(U.NAME)
   )
 ORDER BY U.DEPTCODE, U.EMPCODE;


-- ============================================================================
-- 5. 직위(POS) 및 직급(RANK) 증가분 요약 및 신규 목록
-- ============================================================================
-- 5-1. 직위 증가분
SELECT '직위(POS) 증가분' AS CATEGORY,
       SUM(CASE WHEN IP.POS_ID IS NULL THEN 1 ELSE 0 END) AS ADD_COUNT,
       SUM(CASE WHEN IP.POS_ID IS NOT NULL AND (
           TRIM(IP.POS_NAME) <> TRIM(P.POSNAME) 
           OR NVL(IP.POS_LEVEL, 100) <> NVL(P.POSLEVEL, 100)
       ) THEN 1 ELSE 0 END) AS MOD_COUNT,
       COUNT(*) AS TOTAL_CANDIDATE
  FROM (
      SELECT DISTINCT POSCODE, POSNAME, NVL(POSLEVEL, 100) AS POSLEVEL 
        FROM MIG1_USER.MG_POS 
       WHERE POSNAME IS NOT NULL
  ) P
  LEFT JOIN INTRAWARE.POS IP
    ON IP.POS_ID = TRIM(P.POSCODE);

-- 5-2. 직급 증가분
SELECT '직급(RANK) 증가분' AS CATEGORY,
       SUM(CASE WHEN IR.RANK_ID IS NULL THEN 1 ELSE 0 END) AS ADD_COUNT,
       SUM(CASE WHEN IR.RANK_ID IS NOT NULL AND (
           TRIM(IR.RANK_NAME) <> TRIM(R.RANKNAME) 
           OR NVL(IR.RANK_LEVEL, 100) <> NVL(R.RANKLEVEL, 100)
       ) THEN 1 ELSE 0 END) AS MOD_COUNT,
       COUNT(*) AS TOTAL_CANDIDATE
  FROM (
      SELECT DISTINCT RANKCODE, RANKNAME, NVL(RANKLEVEL, 100) AS RANKLEVEL 
        FROM MIG1_USER.MG_RANK 
       WHERE RANKNAME IS NOT NULL
  ) R
  LEFT JOIN INTRAWARE.RANK IR
    ON IR.RANK_ID = TRIM(R.RANKCODE);


-- ============================================================================
-- 6. 그룹(GROUP) 및 그룹구성원(MEMBER) 증가분 요약
-- ============================================================================
-- 6-1. 그룹 증가분
SELECT '그룹(GROUP) 증가분' AS CATEGORY,
       SUM(CASE WHEN IG.GROUP_ID IS NULL THEN 1 ELSE 0 END) AS ADD_COUNT,
       SUM(CASE WHEN IG.GROUP_ID IS NOT NULL AND (
           TRIM(IG.NAME) <> TRIM(G.GROUP_NAME)
       ) THEN 1 ELSE 0 END) AS MOD_COUNT,
       COUNT(*) AS TOTAL_CANDIDATE
  FROM MIG1_USER.MG_GROUP G
  LEFT JOIN INTRAWARE.G_LIST IG
    ON IG.GROUP_ID = TRIM(NVL(G.HANDY_ID, G.GROUP_ID))
 WHERE G.GROUP_NAME IS NOT NULL;

-- 6-2. 그룹 구성원 증가분 (신규 배속 멤버)
SELECT '그룹멤버 증가분' AS CATEGORY,
       COUNT(*) AS ADD_COUNT
  FROM MIG1_USER.MG_GROUP_MEMBER GM
 WHERE GM.MEMBER_CODE IS NOT NULL
   AND NOT EXISTS (
       SELECT 1
         FROM INTRAWARE.G_MEMBER IGM
        WHERE IGM.GROUP_ID = TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID))
          AND IGM.MEMBER_ID = TRIM(GM.MEMBER_CODE)
   );


-- ============================================================================
-- 7. 사용자 권한(AUTH: 부서장, 접수담당자, 문서관리자 등) 신규 증가분
-- ============================================================================
SELECT '사용자 권한(AUTH) 증가분' AS CATEGORY,
       COUNT(*) AS NEW_AUTH_COUNT
  FROM (
      SELECT DISTINCT 
             TRIM(A.EMPCODE) AS EMPCODE,
             CASE TRIM(A.AUTHCODE)
                 WHEN '7105' THEN 'S1'
                 WHEN '2001' THEN 'D1'
                 WHEN '2002' THEN 'D4'
                 WHEN '2004' THEN 'Da'
                 WHEN '8002' THEN 'D5'
                 WHEN '1009' THEN 'D1'
                 ELSE SUBSTR(TRIM(A.AUTHCODE), 1, 2)
             END AS HANDY_AUTH,
             TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000'))) AS DEPTCODE
        FROM MIG1_USER.MG_AUTH A
       WHERE A.EMPCODE IS NOT NULL 
         AND A.AUTHCODE IS NOT NULL
  ) MA
 WHERE NOT EXISTS (
     SELECT 1
       FROM INTRAWARE.USR_AUTH UA
      WHERE UA.USER_ID = MA.EMPCODE
        AND UA.AUTH = MA.HANDY_AUTH
        AND UA.REL_ID = MA.DEPTCODE
 );

-- 7-1. [상세 명단] 신규 부여된 핵심 권한(부서장 S1, 접수 D1, 문서관리 D4) 명단
SELECT '신규 핵심권한' AS TYPE,
       MA.EMPCODE,
       U.NAME,
       MA.DEPTCODE,
       D.DEPTNAME,
       MA.HANDY_AUTH AS AUTH_CODE,
       CASE MA.HANDY_AUTH
           WHEN 'S1' THEN '부서장'
           WHEN 'D1' THEN '접수담당자'
           WHEN 'D4' THEN '문서관리자'
           WHEN 'Da' THEN '발송담당자'
           WHEN 'D5' THEN '부서관리자'
           ELSE '기타권한'
       END AS AUTH_NAME
  FROM (
      SELECT DISTINCT 
             TRIM(A.EMPCODE) AS EMPCODE,
             CASE TRIM(A.AUTHCODE)
                 WHEN '7105' THEN 'S1'
                 WHEN '2001' THEN 'D1'
                 WHEN '2002' THEN 'D4'
                 WHEN '2004' THEN 'Da'
                 WHEN '8002' THEN 'D5'
                 WHEN '1009' THEN 'D1'
                 ELSE SUBSTR(TRIM(A.AUTHCODE), 1, 2)
             END AS HANDY_AUTH,
             TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000'))) AS DEPTCODE
        FROM MIG1_USER.MG_AUTH A
       WHERE A.EMPCODE IS NOT NULL 
         AND A.AUTHCODE IS NOT NULL
  ) MA
  LEFT JOIN MIG1_USER.MG_USER U ON TRIM(NVL(U.EMPCODE, U.USER_ID)) = MA.EMPCODE
  LEFT JOIN MIG1_USER.MG_DEPT D ON TRIM(D.DEPTCODE) = MA.DEPTCODE
 WHERE NOT EXISTS (
     SELECT 1
       FROM INTRAWARE.USR_AUTH UA
      WHERE UA.USER_ID = MA.EMPCODE
        AND UA.AUTH = MA.HANDY_AUTH
        AND UA.REL_ID = MA.DEPTCODE
 )
   AND MA.HANDY_AUTH IN ('S1', 'D1', 'D4', 'Da', 'D5')
 ORDER BY MA.HANDY_AUTH, MA.DEPTCODE, MA.EMPCODE;

