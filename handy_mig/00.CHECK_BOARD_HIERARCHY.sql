-- ====================================================================================================
-- 스크립트명 : 00.CHECK_BOARD_HIERARCHY.sql
-- 작성목적   : ACUBE 6.0 + LUXOR 포털 환경에서 게시판의 상위-하위 계층(Tree) 구조를 추출하는 쿼리 모음
-- 분석근거   :
--   [구조 1] LUXOR 포털 메뉴 계층 :
--     LUXOR.TLXR_MENU (PARENT_ID -> MENU_ID 계층)
--       -> LUXOR.TLXR_PAGE_ZONE (PAGE_ID = MENU_ID, CONTENT_ID 연결)
--       -> LUXOR.TLXR_CONTENT (CONTENT_ID -> BOARD_ID, CONTENT_NAME_ID 연결)
--       -> LUXOR.TLXR_MESSAGE (MESSAGE_ID = MENU_ID 또는 CONTENT_NAME_ID, LANG_TYPE = 'ko')
--   [구조 2] BBS_USER 게시판 폴더/메뉴 계층 :
--     BBS_USER.TBBS_BOARD_FOLDER (PARENT_FOLDER_ID -> FOLDER_ID)
--       -> BBS_USER.TBBS_BOARD_MENU (FOLDER_ID, PARENT_MENU_ID -> MENU_ID -> BOARD_ID)
-- ====================================================================================================


-- ====================================================================================================
-- [쿼리 1] (추천 1순위) LUXOR 포털 메뉴(TLXR_MENU) ~ 게시판(TLXR_CONTENT) 전체 계층 트리 조회
--   - 포털 상단/좌측 메뉴(ROOT -> 대분류 -> 중분류 -> 소분류)부터 실제 연결된 게시판(BOARD_ID) 및
--     원천 게시물 건수(POST_CNT)까지 전체 경로(FULL_PATH)로 한눈에 출력합니다.
-- ====================================================================================================
WITH MSG_KO AS (
    -- 다국어 메시지 테이블에서 한글('ko') 명칭만 중복 없이 추출
    SELECT
        MESSAGE_ID,
        MAX(TRIM(MESSAGE_NAME)) AS KO_NAME
    FROM LUXOR.TLXR_MESSAGE
    WHERE LANG_TYPE = 'ko'
    GROUP BY MESSAGE_ID
),
MENU_TREE AS (
    -- LUXOR 포털 메뉴(TLXR_MENU) 계층 전개
    SELECT
        M.PORTAL_ID,
        M.MENU_ID,
        M.PARENT_ID,
        NVL(MSG1.KO_NAME, NVL(MSG2.KO_NAME, M.MENU_ID)) AS MENU_NAME,
        LEVEL AS MENU_LEVEL,
        M.DEPTH,
        M.SEQ,
        M.HAS_CHILD,
        NVL(M.IS_ACTIVE, 'Y') AS MENU_ACTIVE,
        SUBSTR(SYS_CONNECT_BY_PATH(NVL(MSG1.KO_NAME, NVL(MSG2.KO_NAME, M.MENU_ID)), ' > '), 4) AS MENU_FULL_PATH,
        ROWNUM AS TREE_SORT_ORDER,
        -- SCRIPT 컬럼 내에 pageId= 또는 boardId= 파라미터가 직접 박혀있는 경우 추출
        REGEXP_SUBSTR(DBMS_LOB.SUBSTR(M.SCRIPT, 1000, 1), 'N[0-9]{15,25}') AS SCRIPT_PAGE_ID
    FROM LUXOR.TLXR_MENU M
    LEFT JOIN MSG_KO MSG1
      ON M.MENU_ID = MSG1.MESSAGE_ID
    LEFT JOIN MSG_KO MSG2
      ON M.DISPLAY_NAME_ID = MSG2.MESSAGE_ID
    WHERE NVL(M.IS_ACTIVE, 'Y') = 'Y'
    START WITH M.PARENT_ID = 'ROOT'
            OR M.PARENT_ID IS NULL
    CONNECT BY NOCYCLE PRIOR M.MENU_ID = M.PARENT_ID
           AND PRIOR M.PORTAL_ID = M.PORTAL_ID
    ORDER SIBLINGS BY M.SEQ ASC NULLS LAST, M.MENU_ID ASC
),
PAGE_BOARD_MAP AS (
    -- 페이지 영역(TLXR_PAGE_ZONE)에 배치된 게시판 컨텐츠(TLXR_CONTENT) 매핑
    SELECT DISTINCT
        PZ.PORTAL_ID,
        PZ.PAGE_ID,
        C.CONTENT_ID,
        C.BOARD_ID,
        MSG_C.KO_NAME AS BOARD_NAME,
        C.PORTLET_ID,
        NVL(C.IS_ACTIVE, 'Y') AS BOARD_ACTIVE,
        PZ.SEQ AS ZONE_SEQ
    FROM LUXOR.TLXR_PAGE_ZONE PZ
    JOIN LUXOR.TLXR_CONTENT C
      ON PZ.CONTENT_ID = C.CONTENT_ID
     AND PZ.PORTAL_ID  = C.PORTAL_ID
    LEFT JOIN MSG_KO MSG_C
      ON C.CONTENT_NAME_ID = MSG_C.MESSAGE_ID
    WHERE NVL(PZ.IS_DELETED, 'N') <> 'Y'
      AND C.BOARD_ID IS NOT NULL
),
POST_STAT AS (
    -- 게시판별 실제 게시물 건수 (삭제 'D' 제외)
    SELECT
        BOARD_ID,
        COUNT(*) AS POST_CNT
    FROM BBS_USER.TBBS_POST_COMMON
    WHERE NVL(POST_TYPE, 'N') <> 'D'
    GROUP BY BOARD_ID
)
SELECT
    MT.PORTAL_ID,
    MT.MENU_LEVEL                                                       AS LVL,
    LPAD(' ', (MT.MENU_LEVEL - 1) * 4, ' ') || MT.MENU_NAME             AS HIERARCHY_TREE,
    MT.MENU_FULL_PATH                                                   AS FULL_MENU_PATH,
    MT.MENU_ID,
    MT.PARENT_ID,
    MT.SEQ                                                              AS MENU_SEQ,
    PBM.BOARD_ID,
    NVL(PBM.BOARD_NAME, MT.MENU_NAME)                                   AS BOARD_NAME,
    NVL(PS.POST_CNT, 0)                                                 AS POST_CNT,
    PBM.CONTENT_ID,
    PBM.PORTLET_ID
FROM MENU_TREE MT
LEFT JOIN PAGE_BOARD_MAP PBM
  ON MT.PORTAL_ID = PBM.PORTAL_ID
 AND (MT.MENU_ID = PBM.PAGE_ID OR MT.SCRIPT_PAGE_ID = PBM.PAGE_ID)
LEFT JOIN POST_STAT PS
  ON PBM.BOARD_ID = PS.BOARD_ID
ORDER BY MT.TREE_SORT_ORDER ASC, PBM.ZONE_SEQ ASC NULLS LAST;


-- ====================================================================================================
-- [쿼리 2] 게시판(BOARD_ID)이 매핑된 메뉴들과 그 상위 부모 폴더만 필터링해서 보는 쿼리
--   - 핸디 10.x INTRAWARE.BBOARD (PAR_ID -> BRD_ID) 트리 이관 설계용
-- ====================================================================================================
WITH MSG_KO AS (
    SELECT MESSAGE_ID, MAX(TRIM(MESSAGE_NAME)) AS KO_NAME
    FROM LUXOR.TLXR_MESSAGE
    WHERE LANG_TYPE = 'ko'
    GROUP BY MESSAGE_ID
),
BOARD_PAGE AS (
    SELECT
        PZ.PORTAL_ID,
        PZ.PAGE_ID,
        C.BOARD_ID,
        MAX(MSG.KO_NAME) AS BOARD_NAME
    FROM LUXOR.TLXR_PAGE_ZONE PZ
    JOIN LUXOR.TLXR_CONTENT C
      ON PZ.CONTENT_ID = C.CONTENT_ID
    LEFT JOIN MSG_KO MSG
      ON C.CONTENT_NAME_ID = MSG.MESSAGE_ID
    WHERE NVL(PZ.IS_DELETED, 'N') <> 'Y'
      AND C.BOARD_ID IS NOT NULL
    GROUP BY PZ.PORTAL_ID, PZ.PAGE_ID, C.BOARD_ID
),
ACTIVE_MENU_IDS AS (
    -- 게시판을 가진 메뉴로부터 최상위(ROOT)까지 역방향(Bottom-Up) 추적하여 관련 메뉴 ID만 수집
    SELECT DISTINCT M.PORTAL_ID, M.MENU_ID
    FROM LUXOR.TLXR_MENU M
    START WITH EXISTS (
        SELECT 1 FROM BOARD_PAGE BP
        WHERE BP.PORTAL_ID = M.PORTAL_ID
          AND BP.PAGE_ID   = M.MENU_ID
    )
    CONNECT BY NOCYCLE PRIOR M.PARENT_ID = M.MENU_ID
           AND PRIOR M.PORTAL_ID = M.PORTAL_ID
)
SELECT
    M.PORTAL_ID,
    LEVEL                                                       AS LVL,
    LPAD(' ', (LEVEL - 1) * 4, ' ') || NVL(MSG.KO_NAME, M.MENU_ID) AS BOARD_TREE_NAME,
    SUBSTR(SYS_CONNECT_BY_PATH(NVL(MSG.KO_NAME, M.MENU_ID), ' > '), 4) AS FULL_PATH,
    M.MENU_ID,
    M.PARENT_ID,
    M.SEQ,
    BP.BOARD_ID,
    BP.BOARD_NAME,
    CASE WHEN BP.BOARD_ID IS NOT NULL THEN 'BOARD(게시판)' ELSE 'FOLDER(분류폴더)' END AS NODE_TYPE
FROM LUXOR.TLXR_MENU M
JOIN ACTIVE_MENU_IDS A
  ON M.PORTAL_ID = A.PORTAL_ID
 AND M.MENU_ID   = A.MENU_ID
LEFT JOIN MSG_KO MSG
  ON M.MENU_ID = MSG.MESSAGE_ID
LEFT JOIN BOARD_PAGE BP
  ON M.PORTAL_ID = BP.PORTAL_ID
 AND M.MENU_ID   = BP.PAGE_ID
START WITH M.PARENT_ID = 'ROOT' OR M.PARENT_ID IS NULL
CONNECT BY NOCYCLE PRIOR M.MENU_ID = M.PARENT_ID
       AND PRIOR M.PORTAL_ID = M.PORTAL_ID
ORDER SIBLINGS BY M.SEQ ASC NULLS LAST, M.MENU_ID ASC;


-- ====================================================================================================
-- [쿼리 3] BBS_USER 스키마 내부 폴더(TBBS_BOARD_FOLDER) + 메뉴(TBBS_BOARD_MENU) 계층 조회
--   - 포털 메뉴와 별개로 BBS 모듈 자체 메뉴/폴더 테이블에 구성된 계층을 확인할 때 사용합니다.
-- ====================================================================================================
WITH MSG_KO AS (
    SELECT MESSAGE_ID, MAX(TRIM(MESSAGE_NAME)) AS KO_NAME
    FROM LUXOR.TLXR_MESSAGE
    WHERE LANG_TYPE = 'ko'
    GROUP BY MESSAGE_ID
),
BBS_NODES AS (
    -- 1. 상위 폴더 노드 (TBBS_BOARD_FOLDER)
    SELECT
        F.PORTAL_ID,
        'F' AS NODE_DIV,
        F.FOLDER_ID AS NODE_ID,
        CASE WHEN F.PARENT_FOLDER_ID IS NULL OR F.PARENT_FOLDER_ID = 'ROOT' OR F.PARENT_FOLDER_ID = F.FOLDER_ID
             THEN NULL ELSE F.PARENT_FOLDER_ID END AS PARENT_NODE_ID,
        NVL(MSG.KO_NAME, F.FOLDER_NAME) AS NODE_NAME,
        CAST(NULL AS VARCHAR2(32)) AS BOARD_ID,
        F.SORT_ORDER
    FROM BBS_USER.TBBS_BOARD_FOLDER F
    LEFT JOIN MSG_KO MSG
      ON F.FOLDER_NAME = MSG.MESSAGE_ID
      OR F.FOLDER_ID   = MSG.MESSAGE_ID
    UNION ALL
    -- 2. 하위 게시판 메뉴 노드 (TBBS_BOARD_MENU)
    SELECT
        BM.PORTAL_ID,
        'M' AS NODE_DIV,
        BM.MENU_ID AS NODE_ID,
        CASE WHEN BM.PARENT_MENU_ID IS NOT NULL AND BM.PARENT_MENU_ID <> 'ROOT' AND BM.PARENT_MENU_ID <> BM.MENU_ID
             THEN BM.PARENT_MENU_ID
             ELSE BM.FOLDER_ID END AS PARENT_NODE_ID,
        NVL(MSG.KO_NAME, BM.MENU_NAME) AS NODE_NAME,
        BM.BOARD_ID,
        BM.SORT_ORDER
    FROM BBS_USER.TBBS_BOARD_MENU BM
    LEFT JOIN MSG_KO MSG
      ON BM.MENU_NAME = MSG.MESSAGE_ID
      OR BM.MENU_ID   = MSG.MESSAGE_ID
)
SELECT
    PORTAL_ID,
    LEVEL AS LVL,
    NODE_DIV,
    LPAD(' ', (LEVEL - 1) * 4, ' ') || NODE_NAME AS BBS_TREE_NAME,
    SUBSTR(SYS_CONNECT_BY_PATH(NODE_NAME, ' > '), 4) AS FULL_PATH,
    NODE_ID,
    PARENT_NODE_ID,
    BOARD_ID,
    SORT_ORDER
FROM BBS_NODES
START WITH PARENT_NODE_ID IS NULL
CONNECT BY NOCYCLE PRIOR NODE_ID = PARENT_NODE_ID
       AND PRIOR PORTAL_ID = PORTAL_ID
ORDER SIBLINGS BY SORT_ORDER ASC NULLS LAST, NODE_ID ASC;

