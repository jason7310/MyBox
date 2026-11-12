-- ====================================================================================================
-- [통합 MIG] 00. 조직도 운영 테이블 직접 적재 (Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 중간 매핑 테이블(MIG1_USER)에서 핸디 그룹웨어 운영 스키마(INTRAWARE)로
--        조직도(부서, 직위, 직급, 사용자, 그룹, 그룹멤버)를 원패스로 고속 직접 적재합니다.
--
-- 적재 대상 테이블:
--   1) INTRAWARE.DEPT_GLOBAL (부서 기본 정보)
--   2) INTRAWARE.DEPT_TREE   (부서 상하 트리 관계)
--   3) INTRAWARE.POS         (직위 정보)
--   4) INTRAWARE.RANK        (직급 정보)
--   5) INTRAWARE.USR_GLOBAL  (사용자 정보 - 재직자 및 퇴직자)
--   6) INTRAWARE.USR_GROUP   (사용자 그룹)
--   6) INTRAWARE.G_MEMBER    (그룹 구성원)
--   7) INTRAWARE.USR_AUTH    (사용자 권한 정보 - 부서장, 접수/발송담당 등)
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ====================================================================================================
-- 1. 부서 정보 적재 (INTRAWARE.DEPT_GLOBAL & DEPT_TREE)
-- ====================================================================================================

-- 1-1. 부서 기본 정보 (DEPT_GLOBAL)
INSERT /*+ APPEND PARALLEL(D, 8) */ INTO INTRAWARE.DEPT_GLOBAL (
    COMMUNITY_ID,
    DEPT_ID,
    DEPT_NAME,
    DEPT_NAME2,
    PAR_ID,
    SEQ,
    REP_F,
    RECV_BOX_F,
    BOX_F,
    STATUS,
    ABBREVIATION,
    DEPT_CODE,
    MODIFY_DATE,
    SITE_ID
)
SELECT 
    '001000000'                                AS COMMUNITY_ID,
    TRIM(D.DEPTCODE)                           AS DEPT_ID,
    TRIM(D.DEPTNAME)                           AS DEPT_NAME,
    TRIM(D.DEPTNAME2)                          AS DEPT_NAME2,
    TRIM(NVL(D.PARCODE, '000000000'))          AS PAR_ID,
    NVL(D.SEQ, 1)                              AS SEQ,
    '1'                                        AS REP_F,
    NVL(D.RECVF, '1')                          AS RECV_BOX_F,
    NVL(D.BOXF, '1')                           AS BOX_F,
    DECODE(NVL(D.DELETED, 0), 0, '1', '4')   AS STATUS,        -- 핸디 표준 STATUS (1: 정상, 4: 폐지/삭제)
    TRIM(D.ABBREVIATION)                       AS ABBREVIATION,
    TRIM(D.DEPTCODE)                           AS DEPT_CODE,
    NVL(D.MODIFYDATE, SYSDATE)                 AS MODIFY_DATE,
    '001000000'                                AS SITE_ID
FROM MIG1_USER.MG_DEPT D
WHERE D.DEPTCODE IS NOT NULL;

COMMIT;

-- 1-2. 부서 트리 관계 (DEPT_TREE)
INSERT /*+ APPEND PARALLEL(T, 8) */ INTO INTRAWARE.DEPT_TREE (
    PAR_ID,
    DEPT_ID
)
SELECT 
    TRIM(NVL(D.PARCODE, '000000000'))          AS PAR_ID,
    TRIM(D.DEPTCODE)                           AS DEPT_ID
FROM MIG1_USER.MG_DEPT D
WHERE D.DEPTCODE IS NOT NULL;

COMMIT;


-- ====================================================================================================
-- 2. 직위 정보 적재 (INTRAWARE.POS)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(P, 8) */ INTO INTRAWARE.POS (
    POS_ID,
    POS_LEVEL,
    COMMUNITY_ID,
    POS_NAME,
    POS_CODE
)
SELECT 
    TRIM(P.POSCODE)                            AS POS_ID,
    NVL(P.POSLEVEL, 100)                       AS POS_LEVEL,
    '001000000'                                AS COMMUNITY_ID,
    TRIM(P.POSNAME)                            AS POS_NAME,
    TRIM(P.POSCODE)                            AS POS_CODE
FROM MIG1_USER.MG_POS P
WHERE P.POSCODE IS NOT NULL;

COMMIT;


-- ====================================================================================================
-- 3. 직급 정보 적재 (INTRAWARE.RANK)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(R, 8) */ INTO INTRAWARE.RANK (
    RANK_ID,
    RANK_LEVEL,
    COMMUNITY_ID,
    RANK_NAME,
    RANK_CODE
)
SELECT 
    TRIM(R.RANKCODE)                           AS RANK_ID,
    NVL(R.RANKLEVEL, 100)                      AS RANK_LEVEL,
    '001000000'                                AS COMMUNITY_ID,
    TRIM(R.RANKNAME)                           AS RANK_NAME,
    TRIM(R.RANKCODE)                           AS RANK_CODE
FROM MIG1_USER.MG_RANK R
WHERE R.RANKCODE IS NOT NULL;

COMMIT;


-- ====================================================================================================
-- 4. 사용자 정보 적재 (INTRAWARE.USR_GLOBAL) - 재직자 및 퇴직자 일괄 고속 적재
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(U, 16) */ INTO INTRAWARE.USR_GLOBAL (
    USER_ID,
    EMP_CODE,
    DEPT_ID,
    DEPT_NAME,
    COMMUNITY_ID,
    SV_ID,
    NAME,
    STATUS,
    SEX,
    PHONE,
    FAX,
    E_MAIL,
    MOBILE_PHONE,
    DUTY_NAME,
    POS_NAME,
    RANK_NAME,
    MODIFY_DATE,
    SITE_ID,
    SANC_BOX_F,
    RECV_SEND_F
)
SELECT 
    TRIM(NVL(U.EMPCODE, U.USER_ID))            AS USER_ID,
    TRIM(NVL(U.EMPCODE, U.USER_ID))            AS EMP_CODE,
    TRIM(U.DEPTCODE)                           AS DEPT_ID,
    NVL(D.DEPTNAME, '미지정')                   AS DEPT_NAME,
    '001000000'                                AS COMMUNITY_ID,
    1                                          AS SV_ID,
    TRIM(U.NAME)                               AS NAME,
    CASE 
        WHEN NVL(U.DELETED, 0) IN (0, 1) THEN '1'   -- 1: 정상 재직
        ELSE '4'                                             -- 핸디 표준 STATUS (4: 퇴직/삭제)
    END                                        AS STATUS,
    NVL(U.SEX, '0')                            AS SEX,
    TRIM(U.PHONE)                              AS PHONE,
    TRIM(U.FAX)                                AS FAX,
    TRIM(U.EMAIL)                              AS E_MAIL,
    TRIM(U.MOBILEPHONE)                        AS MOBILE_PHONE,
    TRIM(U.DUTYNAME)                           AS DUTY_NAME,
    TRIM(NVL(U.POSNAME, '미지정'))              AS POS_NAME,
    TRIM(U.RANKNAME)                           AS RANK_NAME,
    NVL(U.MODIFYDATE, SYSDATE)                 AS MODIFY_DATE,
    '001000000'                                AS SITE_ID,
    '1'                                        AS SANC_BOX_F,
    '1'                                        AS RECV_SEND_F
FROM MIG1_USER.MG_USER U
LEFT JOIN MIG1_USER.MG_DEPT D
  ON U.DEPTCODE = D.DEPTCODE
WHERE U.EMPCODE IS NOT NULL OR U.USER_ID IS NOT NULL;

COMMIT;


-- ====================================================================================================
-- 5. 사용자 그룹 적재 (INTRAWARE.USR_GROUP)
-- ====================================================================================================
INSERT /*+ APPEND */ INTO INTRAWARE.USR_GROUP (
    GROUP_ID,
    USER_ID,
    APPLICATION,
    NAME,
    G_DESC
)
SELECT 
    TRIM(NVL(G.HANDY_ID, G.GROUP_ID))          AS GROUP_ID,
    TRIM(NVL(G.USER_CODE, 'SYSTEM'))           AS USER_ID,
    NVL(G.APPLICATION, '0')                    AS APPLICATION,
    SUBSTR(TRIM(G.GROUP_NAME), 1, 120)         AS NAME,
    SUBSTR(TRIM(G.GROUP_DESC), 1, 100)         AS G_DESC
FROM MIG1_USER.MG_GROUP G
WHERE G.GROUP_NAME IS NOT NULL;

COMMIT;


-- ====================================================================================================
-- 6. 그룹 구성원 적재 (INTRAWARE.G_MEMBER)
-- ====================================================================================================
INSERT /*+ APPEND */ INTO INTRAWARE.G_MEMBER (
    GROUP_ID,
    SEQ,
    USER_ID,
    MEMBER_ID,
    TYPE,
    E_MAIL
)
SELECT 
    TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID))         AS GROUP_ID,
    NVL(GM.MEMBER_SEQ, 1)                      AS SEQ,
    TRIM(NVL(G.USER_CODE, 'SYSTEM'))           AS USER_ID,
    TRIM(GM.MEMBER_CODE)                       AS MEMBER_ID,
    NVL(GM.MEMBER_TYPE, '0')                   AS TYPE,
    ''                                         AS E_MAIL
FROM MIG1_USER.MG_GROUP_MEMBER GM
LEFT JOIN MIG1_USER.MG_GROUP G
  ON GM.GROUP_ID = G.GROUP_ID
WHERE GM.MEMBER_CODE IS NOT NULL;

COMMIT;

-- ====================================================================================================
-- 7. 사용자 권한 적재 (INTRAWARE.USR_AUTH) - 부서장, 접수/발송/문서 관리자 권한
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(A, 8) */ INTO INTRAWARE.USR_AUTH (
    USER_ID,
    AUTH,
    AUTH_NUM,
    REL_ID,
    REL_COMMUNITY_ID
)
SELECT DISTINCT
    TRIM(A.EMPCODE)                                            AS USER_ID,
    -- [방안 1] 인라인 권한코드 변환 (MG_AUTH의 원본 숫자 코드를 핸디 2자리 영문으로 변환)
    CASE TRIM(A.AUTHCODE)
        WHEN '7105' THEN 'S1'  -- 부서장
        WHEN '2001' THEN 'D1'  -- 접수담당자 (기관문서관리책임자)
        WHEN '2002' THEN 'D4'  -- 문서관리자 (부서문서관리책임자)
        WHEN '2004' THEN 'Da'  -- 발송담당자 (부서날인관리자)
        WHEN '8002' THEN 'D5'  -- 열람제외문서함 관리자 / 부서관리자
        WHEN '1009' THEN 'D1'  -- 전자결재 관리자
        ELSE SUBSTR(TRIM(A.AUTHCODE), 1, 2)
    END                                                        AS AUTH,
    -- [방안 1] 인라인 권한번호(AUTH_NUM) 매핑
    CASE TRIM(A.AUTHCODE)
        WHEN '7105' THEN 21    -- 부서장
        WHEN 'S1'   THEN 21
        WHEN '2001' THEN 11    -- 접수담당자
        WHEN 'D1'   THEN 11
        WHEN '2002' THEN 14    -- 문서관리자
        WHEN 'D4'   THEN 14
        WHEN '2004' THEN 51    -- 발송담당자
        WHEN 'Da'   THEN 51
        WHEN '8002' THEN 15    -- 열람제외 / 부서관리자
        WHEN 'D5'   THEN 15
        WHEN '1009' THEN 11    -- 전자결재 관리자
        WHEN 'U1'   THEN 1     -- 겸직
        ELSE 0
    END                                                        AS AUTH_NUM,
    TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000')))        AS REL_ID,
    '001000000'                                                AS REL_COMMUNITY_ID
FROM MIG1_USER.MG_AUTH A
WHERE A.EMPCODE IS NOT NULL
  AND A.AUTHCODE IS NOT NULL;

COMMIT;
