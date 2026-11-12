-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 05. 그룹 정보 추출 (MG_GROUP -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 그룹 관리 > 일괄등록(CSV) (또는 DB 직접 INSERT)
-- * 추출 순서: 5순위 (사용자 등록 후 진행)
-- * 원본 테이블: MIG1_USER.MG_GROUP (이미지 IMG_9462 기준)
--   - HANDY_ID    : CHAR(32)        TOBE 그룹ID (기채번된 경우 사용)
--   - COMP_ID     : VARCHAR2(32)    회사ID
--   - GROUP_ID    : VARCHAR2(32)    ASIS 그룹ID
--   - USER_CODE   : VARCHAR2(32)    등록자 사번 (user_id)
--   - USER_NAME   : VARCHAR2(128)   등록자 이름
--   - APPLICATION : CHAR(1)         그룹종류 (0:개인, 1:공유, G:공람, R/T:수신처, B:게시판, M:메일)
--   - GROUP_NAME  : VARCHAR2(128)   그룹명
--   - GROUP_DESC  : VARCHAR2(1000)  그룹설명
-- ============================================================================

-- ============================================================================
-- [1] 관리자 화면 업로드용 CSV 추출 (E/F CSV 규격) -> group.csv
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,group_id,user_id,application,group_name,g_desc' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || TRIM(NVL(G.HANDY_ID, G.GROUP_ID))                                       -- 2. group_id
    || ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM'))                                        -- 3. user_id (등록자 사번)
    || ',' || NVL(G.APPLICATION, '0')                                                 -- 4. application (그룹종류)
    || ',' || REPLACE(REPLACE(NVL(G.GROUP_NAME, ' '), ',', ' '), '"', '""')           -- 5. group_name
    || ',' || REPLACE(REPLACE(REPLACE(NVL(G.GROUP_DESC, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 6. g_desc
    AS csv_row
  FROM MIG1_USER.MG_GROUP G
 WHERE G.GROUP_NAME IS NOT NULL
 ORDER BY G.APPLICATION, G.GROUP_ID;


-- ============================================================================
-- [2] (참고용) 핸디 운영 DB (INTRAWARE.USR_GROUP) 직접 INSERT 문 추출
--     * 관리자 화면 CSV 등록 외에 DB 직접 적재 시 활용
-- ============================================================================
/*
INSERT INTO INTRAWARE.USR_GROUP (
    GROUP_ID,
    USER_ID,
    APPLICATION,
    NAME,
    G_DESC
)
SELECT 
    TRIM(NVL(G.HANDY_ID, G.GROUP_ID)) AS GROUP_ID,
    TRIM(NVL(G.USER_CODE, 'SYSTEM'))   AS USER_ID,
    NVL(G.APPLICATION, '0')            AS APPLICATION,
    SUBSTR(TRIM(G.GROUP_NAME), 1, 120) AS NAME,
    SUBSTR(TRIM(G.GROUP_DESC), 1, 100) AS G_DESC
  FROM MIG1_USER.MG_GROUP G
 WHERE G.GROUP_NAME IS NOT NULL;
*/
