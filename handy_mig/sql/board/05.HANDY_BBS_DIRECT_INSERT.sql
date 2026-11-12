-- ====================================================================================================
-- 스크립트명 : 05.HANDY_BBS_DIRECT_INSERT.sql
-- 작성목적   : 게시판 스테이징(MIG1_USER.MG_BOARD / MG_POST / MG_POST_COMMENT / MG_POST_ATTACH) 데이터를
--              핸디 10.x 운영 스키마(INTRAWARE) 게시판 테이블에 Direct Path로 일괄 고속 적재
-- 대상스키마 : 스테이징(MIG1_USER) -> 타겟(INTRAWARE)
-- 적재테이블 :
--   1. INTRAWARE.BBOARD         (게시판 마스터)
--   2. INTRAWARE.BBS_BOARD_TREE (게시판 상하위 트리)
--   3. INTRAWARE.BHEADER        (게시물 헤더/메타)
--   4. INTRAWARE.BBS_COMMENT    (게시물 사용자의견/덧글)
--   5. INTRAWARE.BBS_ATTACH     (게시물 첨부파일)
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ====================================================================================================
-- 1. 게시판 마스터 적재 (INTRAWARE.BBOARD)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(B, 4) */ INTO INTRAWARE.BBOARD B (
    BRD_ID,
    PAR_ID,
    SEQ,
    RESPONSE_TYPE,
    RESPONSE_VIEW,
    BRD_TYPE,
    LIST_TYPE,
    SECURITY_F,
    NOTIFY_F,
    FORCED_EXPR_NOTIFY_F,
    CORP_EX_F,
    FORM_ID,
    WRITE_AUTH,
    READ_AUTH,
    REPLY_AUTH,
    COMMENT_AUTH,
    POST_PERIOD,
    MODIFY_DATE,
    COMMUNITY_ID,
    CREATE_DATE,
    WASTE_DATE,
    ANONYM_F,
    NAME,
    REPLY_MAIL_F,
    MOD_ENDDATE_F,
    REPLICATION_F,
    NICKNAME_F,
    ALIAS_F,
    BUSINESS_F,
    PREFACE_F,
    EMPCODE_F,
    POSTER_VIEW_F,
    VIEWS_F,
    FOLDER_MERGED_F,
    PRINT_BODY_F,
    SAVE_BODY_F,
    POSTER_TYPE,
    ATTACH_MAX_SIZE,
    COMMENT_MAIL_F,
    FORWORD_MAIL_F,
    HIDE_F,
    CUSTOM_FIELD_F,
    MATERIAL_OPEN_F,
    TASK_VERSION,
    DISPLAY_FOLDER_ICON_F,
    FONT_COLOR,
    FONT_UNDERLINE_F,
    FONT_BOLD_F,
    USER_COLUMN1
)
SELECT
    MB.HANDY_BOARD_ID                                           AS BRD_ID,
    NVL(MB.HANDY_PAR_ID, '^^^^^^^^^')                           AS PAR_ID,
    MOD(ROWNUM - 1, 999) + 1                                    AS SEQ,
    CASE WHEN MB.USE_COMMENT IN ('1', 'Y') THEN '1' ELSE '0' END AS RESPONSE_TYPE,
    '4'                                                         AS RESPONSE_VIEW,
    '1'                                                         AS BRD_TYPE,
    CASE WHEN MB.BOARD_TYPE IN ('I', 'G') THEN '2'
         WHEN MB.BOARD_TYPE = 'B' THEN '1'
         ELSE '0' END                                           AS LIST_TYPE,
    '0'                                                         AS SECURITY_F,
    '1'                                                         AS NOTIFY_F,
    '0'                                                         AS FORCED_EXPR_NOTIFY_F,
    '0'                                                         AS CORP_EX_F,
    '^^^^^^^^^'                                                 AS FORM_ID,
    '1'                                                         AS WRITE_AUTH,
    '0'                                                         AS READ_AUTH,
    CASE WHEN MB.USE_REPLY IN ('1', 'Y') THEN '1' ELSE '0' END  AS REPLY_AUTH,
    CASE WHEN MB.USE_COMMENT IN ('1', 'Y') THEN '1' ELSE '0' END AS COMMENT_AUTH,
    '-1'                                                        AS POST_PERIOD,
    NVL(MB.MOD_DATE, SYSDATE)                                   AS MODIFY_DATE,
    '001000000'                                                 AS COMMUNITY_ID,
    NVL(MB.REG_DATE, SYSDATE)                                   AS CREATE_DATE,
    TO_DATE('3000/01/01', 'YYYY/MM/DD')                         AS WASTE_DATE,
    CASE WHEN MB.USE_ANONYMOUS IN ('N', 'H', 'P') THEN '1' ELSE '0' END AS ANONYM_F,
    SUBSTRB(TRIM(MB.BOARD_NAME), 1, 120)                        AS NAME,
    '0'                                                         AS REPLY_MAIL_F,
    '1'                                                         AS MOD_ENDDATE_F,
    '1'                                                         AS REPLICATION_F,
    '0'                                                         AS NICKNAME_F,
    '0'                                                         AS ALIAS_F,
    '0'                                                         AS BUSINESS_F,
    '0'                                                         AS PREFACE_F,
    '0'                                                         AS EMPCODE_F,
    '1'                                                         AS POSTER_VIEW_F,
    '1'                                                         AS VIEWS_F,
    '0'                                                         AS FOLDER_MERGED_F,
    '1'                                                         AS PRINT_BODY_F,
    '1'                                                         AS SAVE_BODY_F,
    '0'                                                         AS POSTER_TYPE,
    0                                                           AS ATTACH_MAX_SIZE,
    '0'                                                         AS COMMENT_MAIL_F,
    '1'                                                         AS FORWORD_MAIL_F,
    CASE WHEN MB.IS_ACTIVE = 'Y' THEN '0' ELSE '1' END          AS HIDE_F,
    '0'                                                         AS CUSTOM_FIELD_F,
    '0'                                                         AS MATERIAL_OPEN_F,
    0                                                           AS TASK_VERSION,
    '1'                                                         AS DISPLAY_FOLDER_ICON_F,
    '0'                                                         AS FONT_COLOR,
    '0'                                                         AS FONT_UNDERLINE_F,
    '0'                                                         AS FONT_BOLD_F,
    SUBSTRB(MB.BOARD_ID, 1, 512)                                AS USER_COLUMN1 -- 원천 BOARD_ID 추적용 보관
FROM MIG1_USER.MG_BOARD MB
WHERE NOT EXISTS (
    SELECT 1 FROM INTRAWARE.BBOARD TB WHERE TB.BRD_ID = MB.HANDY_BOARD_ID
);

COMMIT;


-- ====================================================================================================
-- 2. 게시판 트리 적재 (INTRAWARE.BBS_BOARD_TREE)
-- ====================================================================================================
INSERT /*+ APPEND */ INTO INTRAWARE.BBS_BOARD_TREE (
    PAR_ID,
    BRD_ID
)
SELECT
    NVL(MB.HANDY_PAR_ID, '^^^^^^^^^') AS PAR_ID,
    MB.HANDY_BOARD_ID                 AS BRD_ID
FROM MIG1_USER.MG_BOARD MB
WHERE NOT EXISTS (
    SELECT 1 FROM INTRAWARE.BBS_BOARD_TREE TT
    WHERE TT.PAR_ID = NVL(MB.HANDY_PAR_ID, '^^^^^^^^^')
      AND TT.BRD_ID = MB.HANDY_BOARD_ID
);

COMMIT;


-- ====================================================================================================
-- 3. 게시물 마스터 적재 (INTRAWARE.BHEADER)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(H, 8) */ INTO INTRAWARE.BHEADER H (
    HEADER_ID,
    DEPT_ID,
    BRD_ID,
    POSTER_ID,
    FORM_ID,
    MTRL_NO,
    POST_DATE,
    MODIFY_DATE,
    READ_NUM,
    ORIG_ID,
    EXPR_F,
    SEC_F,
    MODIFIED_F,
    SV_ID,
    END_DATE,
    ATT_CNT,
    SEC_LEVEL,
    POS_ID,
    RESPONSE_TYPE,
    RESPONSE_VIEW,
    APPROVAL_NUM,
    OPPOSITE_NUM,
    COMMENT_NUM,
    DECLARE_NUM,
    STATUS,
    THREAD_ID,
    THREAD_SEQ,
    THREAD_DEPTH,
    SITE_ID,
    TITLE,
    BODY_TEXT,
    BODY_PATH,
    POSTER_NAME,
    COMMUNITY_ID,
    RFC_F,
    ANN_F,
    KM_STTS,
    EDM_STTS,
    NICKNAME_POSTER_TYPE,
    APPRV_F,
    TASK_PROCESS,
    TASK_VERSION,
    ORIG_DEPT_NAME,
    OPEN_F,
    ANN_SEQ,
    PRIVATE_F,
    USER_COLUMN1
)
WITH UNIQ_USR AS (
    SELECT
        LOGIN_ID,
        USER_ID,
        DEPT_ID,
        POS_ID,
        ROW_NUMBER() OVER (PARTITION BY LOGIN_ID ORDER BY STATUS ASC, USER_ID ASC) AS RN
    FROM INTRAWARE.USR_GLOBAL
    WHERE LOGIN_ID IS NOT NULL
)
SELECT
    P.HANDY_HEADER_ID                                   AS HEADER_ID,
    NVL(DG.DEPT_ID, NVL(UG.DEPT_ID, '000000000'))       AS DEPT_ID,
    P.HANDY_BOARD_ID                                    AS BRD_ID,
    NVL(UG.USER_ID, '000000000')                        AS POSTER_ID,
    '^^^^^^^^^'                                         AS FORM_ID,
    P.MTRL_NO                                           AS MTRL_NO,
    P.CREATE_DATE                                       AS POST_DATE,
    P.UPDATE_DATE                                       AS MODIFY_DATE,
    P.VIEW_COUNT                                        AS READ_NUM,
    NVL(P.HANDY_ORIG_ID, '000000000')                   AS ORIG_ID,
    NVL(P.IS_EMERGENCY, '0')                            AS EXPR_F,
    NVL(P.IS_SECURITY, '0')                             AS SEC_F,
    CASE WHEN P.UPDATE_DATE > P.CREATE_DATE THEN '1' ELSE '0' END AS MODIFIED_F,
    1                                                   AS SV_ID,
    P.END_DATE                                          AS END_DATE,
    LEAST(NVL(P.ATT_CNT, 0), 999)                       AS ATT_CNT,
    100                                                 AS SEC_LEVEL,
    UG.POS_ID                                           AS POS_ID,
    '1'                                                 AS RESPONSE_TYPE,
    '2'                                                 AS RESPONSE_VIEW,
    NVL(P.RCMD_COUNT, 0)                                AS APPROVAL_NUM,
    NVL(P.NO_COUNT, 0)                                  AS OPPOSITE_NUM,
    LEAST(NVL(P.COMMENT_COUNT, 0), 9999)                AS COMMENT_NUM,
    0                                                   AS DECLARE_NUM,
    '1'                                                 AS STATUS,
    P.HANDY_THREAD_ID                                   AS THREAD_ID,
    LEAST(NVL(P.HANDY_THREAD_SEQ, 0), 999)              AS THREAD_SEQ,
    LEAST(NVL(P.POST_DEPTH, 0), 99)                     AS THREAD_DEPTH,
    '001000000'                                         AS SITE_ID,
    P.POST_TITLE                                        AS TITLE,
    P.BODY_TEXT                                         AS BODY_TEXT,
    P.HANDY_BODY_PATH                                   AS BODY_PATH,
    P.CREATOR_NAME                                      AS POSTER_NAME,
    '001000000'                                         AS COMMUNITY_ID,
    '0'                                                 AS RFC_F,
    NVL(P.IS_NOTICE, '0')                               AS ANN_F,
    '0'                                                 AS KM_STTS,
    '0'                                                 AS EDM_STTS,
    '1'                                                 AS NICKNAME_POSTER_TYPE,
    '0'                                                 AS APPRV_F,
    0                                                   AS TASK_PROCESS,
    0                                                   AS TASK_VERSION,
    P.CREATOR_DEPT_NAME                                 AS ORIG_DEPT_NAME,
    '0'                                                 AS OPEN_F,
    999                                                 AS ANN_SEQ,
    NVL(P.IS_SECRET_POST, '0')                          AS PRIVATE_F,
    SUBSTRB(P.POST_ID, 1, 512)                          AS USER_COLUMN1 -- 원천 POST_ID 추적용 보관
FROM MIG1_USER.MG_POST P
LEFT JOIN UNIQ_USR UG
  ON P.CREATOR_UID = UG.LOGIN_ID
 AND UG.RN = 1
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG
  ON P.CREATOR_DEPT_ID = DG.DEPT_ID
WHERE NOT EXISTS (
    SELECT 1 FROM INTRAWARE.BHEADER TH WHERE TH.HEADER_ID = P.HANDY_HEADER_ID
);

COMMIT;


-- ====================================================================================================
-- 4. 게시물 덧글 적재 (INTRAWARE.BBS_COMMENT)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(CM, 8) */ INTO INTRAWARE.BBS_COMMENT CM (
    COMMENT_ID,
    USER_ID,
    HEADER_ID,
    PAR_ID,
    BRD_ID,
    M_COMMENT_DATE,
    USER_COMMENT,
    ORIG_COMMENT_DATE,
    RESPONSE_VIEW,
    ALIAS
)
WITH UNIQ_USR AS (
    SELECT
        LOGIN_ID,
        USER_ID,
        ROW_NUMBER() OVER (PARTITION BY LOGIN_ID ORDER BY STATUS ASC, USER_ID ASC) AS RN
    FROM INTRAWARE.USR_GLOBAL
    WHERE LOGIN_ID IS NOT NULL
)
SELECT
    C.HANDY_COMMENT_ID                  AS COMMENT_ID,
    NVL(UG.USER_ID, '000000000')        AS USER_ID,
    C.HANDY_HEADER_ID                   AS HEADER_ID,
    NVL(C.HANDY_PAR_ID, '000000000')    AS PAR_ID,
    C.HANDY_BOARD_ID                    AS BRD_ID,
    C.CREATE_DATE                       AS M_COMMENT_DATE,
    C.COMMENT_CONTENT                   AS USER_COMMENT,
    C.CREATE_DATE                       AS ORIG_COMMENT_DATE,
    '1'                                 AS RESPONSE_VIEW,
    C.CREATOR_NAME                      AS ALIAS
FROM MIG1_USER.MG_POST_COMMENT C
LEFT JOIN UNIQ_USR UG
  ON C.CREATOR_UID = UG.LOGIN_ID
 AND UG.RN = 1
WHERE NOT EXISTS (
    SELECT 1 FROM INTRAWARE.BBS_COMMENT TC WHERE TC.COMMENT_ID = C.HANDY_COMMENT_ID
);

COMMIT;


-- ====================================================================================================
-- 5. 게시물 첨부파일 적재 (INTRAWARE.BBS_ATTACH)
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(AT, 8) */ INTO INTRAWARE.BBS_ATTACH AT (
    HEADER_ID,
    ORD,
    TYPE,
    ATT_SIZE,
    FILE_NAME,
    ATT_URL
)
SELECT
    A.HANDY_HEADER_ID   AS HEADER_ID,
    A.ORD               AS ORD,
    '1'                 AS TYPE,
    A.FILE_SIZE         AS ATT_SIZE,
    A.FILE_LOCAL_NAME   AS FILE_NAME,
    A.HANDY_ATT_URL     AS ATT_URL
FROM MIG1_USER.MG_POST_ATTACH A
WHERE NOT EXISTS (
    SELECT 1 FROM INTRAWARE.BBS_ATTACH TA
    WHERE TA.HEADER_ID = A.HANDY_HEADER_ID
      AND TA.ORD       = A.ORD
);

COMMIT;


-- ====================================================================================================
-- 6. 최종 적재 건수 1:1 패리티 감사 (Stage vs Target)
-- ====================================================================================================
SELECT '1. 게시판 마스터 (MG_BOARD vs BBOARD)' AS AUDIT_ITEM,
       (SELECT COUNT(*) FROM MIG1_USER.MG_BOARD) AS STAGING_CNT,
       (SELECT COUNT(*) FROM INTRAWARE.BBOARD WHERE BRD_ID LIKE 'B%') AS TARGET_CNT
  FROM DUAL
UNION ALL
SELECT '2. 게시물 본문 (MG_POST vs BHEADER)' AS AUDIT_ITEM,
       (SELECT COUNT(*) FROM MIG1_USER.MG_POST) AS STAGING_CNT,
       (SELECT COUNT(*) FROM INTRAWARE.BHEADER WHERE HEADER_ID LIKE 'H%') AS TARGET_CNT
  FROM DUAL
UNION ALL
SELECT '3. 게시물 덧글 (MG_POST_COMMENT vs BBS_COMMENT)' AS AUDIT_ITEM,
       (SELECT COUNT(*) FROM MIG1_USER.MG_POST_COMMENT) AS STAGING_CNT,
       (SELECT COUNT(*) FROM INTRAWARE.BBS_COMMENT WHERE COMMENT_ID LIKE 'C%') AS TARGET_CNT
  FROM DUAL
UNION ALL
SELECT '4. 게시물 첨부 (MG_POST_ATTACH vs BBS_ATTACH)' AS AUDIT_ITEM,
       (SELECT COUNT(*) FROM MIG1_USER.MG_POST_ATTACH) AS STAGING_CNT,
       (SELECT COUNT(*) FROM INTRAWARE.BBS_ATTACH WHERE HEADER_ID LIKE 'H%') AS TARGET_CNT
  FROM DUAL;

