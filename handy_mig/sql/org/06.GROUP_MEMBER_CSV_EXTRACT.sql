-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 06. 그룹멤버 정보 추출 (MG_GROUP_MEMBER -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 그룹 관리 > 그룹멤버 일괄등록(CSV) (또는 DB 직접 INSERT)
-- * 추출 순서: 6순위 (그룹 등록 후 마지막으로 진행)
-- * 원본 테이블: MIG1_USER.MG_GROUP_MEMBER (이미지 IMG_9463 기준)
--   - HANDY_ID       : CHAR(32)        TOBE 그룹ID
--   - GROUP_ID       : VARCHAR2(32)    ASIS 그룹ID
--   - MEMBER_SEQ     : NUMBER(10)      그룹 내 멤버 순번
--   - MEMBER_CODE    : VARCHAR2(32)    사용자(사번) 또는 부서 코드
--   - MEMBER_NAME    : VARCHAR2(512)   사용자 또는 부서명
--   - MEMBER_TYPE    : CHAR(1)         멤버유형 (0:사용자, 1:부서, 5:하위포함부서 등)
--   - RECV_DEPT_ID   : VARCHAR2(512)   LDAP 수신부서ID
--   - RECV_DEPT_NAME : VARCHAR2(512)   LDAP 수신부서명
--   - REF_DEPT_ID    : VARCHAR2(512)   LDAP 참조부서ID
--   - REF_DEPT_NAME  : VARCHAR2(128)   LDAP 참조부서명
-- ============================================================================

-- ============================================================================
-- [1] 관리자 화면 업로드용 CSV 추출 (E/F CSV 규격) -> group_member.csv
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 GROUP_MEMBER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,group_id,seq,user_id,member_id,type,email' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID))                                     -- 2. group_id (TOBE 그룹ID 또는 ASIS 그룹ID)
    || ',' || NVL(TO_CHAR(GM.MEMBER_SEQ), '1')                                        -- 3. seq (멤버 순번)
    || ',' || TRIM(NVL(G.USER_CODE, 'SYSTEM'))                                        -- 4. user_id (그룹 소유자 사번)
    || ',' || TRIM(GM.MEMBER_CODE)                                                    -- 5. member_id (사용자 사번 또는 부서코드)
    || ',' || NVL(GM.MEMBER_TYPE, '0')                                                -- 6. type (0:사용자, 1:부서, 5:하위포함부서)
    || ',' || ''                                                                      -- 7. email (공란)
    AS csv_row
  FROM MIG1_USER.MG_GROUP_MEMBER GM
  LEFT JOIN MIG1_USER.MG_GROUP G
    ON GM.GROUP_ID = G.GROUP_ID
 WHERE GM.MEMBER_CODE IS NOT NULL
 ORDER BY GM.GROUP_ID, GM.MEMBER_SEQ;


-- ============================================================================
-- [2] (참고용) 핸디 운영 DB (INTRAWARE.G_MEMBER) 직접 INSERT 문 추출
--     * 관리자 화면 CSV 등록 외에 DB 직접 적재 시 활용
-- ============================================================================
/*
INSERT INTO INTRAWARE.G_MEMBER (
    GROUP_ID,
    SEQ,
    USER_ID,
    MEMBER_ID,
    TYPE,
    E_MAIL
)
SELECT 
    TRIM(NVL(GM.HANDY_ID, GM.GROUP_ID)) AS GROUP_ID,
    NVL(GM.MEMBER_SEQ, 1)               AS SEQ,
    TRIM(NVL(G.USER_CODE, 'SYSTEM'))   AS USER_ID,
    TRIM(GM.MEMBER_CODE)                AS MEMBER_ID,
    NVL(GM.MEMBER_TYPE, '0')            AS TYPE,
    ''                                  AS E_MAIL
  FROM MIG1_USER.MG_GROUP_MEMBER GM
  LEFT JOIN MIG1_USER.MG_GROUP G
    ON GM.GROUP_ID = G.GROUP_ID
 WHERE GM.MEMBER_CODE IS NOT NULL;
*/
