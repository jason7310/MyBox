-- ============================================================================
-- [유틸리티] 데이터베이스 스키마 및 테이블/컬럼 메타데이터 추출 쿼리
-- 
-- * 파일 위치: handy_mig/sql/tool/03.EXTRACT_SCHEMA_METADATA.sql
-- * 목적: 
--   1) 대상 스키마(OWNER)의 테이블 목록 및 테이블 코멘트 일괄 추출
--   2) 각 테이블별 컬럼 정보(타입, 크기, Nullable, Default, PK 여부, 코멘트) 추출
--   3) Markdown 표 / CSV 보고서 생성용 쿼리
-- * 지원 DBMS: Tibero 7, Oracle 11g~19c 호환
-- ============================================================================

-- ============================================================================
-- 1. [테이블 목록 추출] 대상 OWNER별 테이블 및 테이블 코멘트
--    (출력 파일명 권장: 이관대상테이블.csv)
-- ============================================================================
SELECT 
    T.OWNER,
    T.TABLE_NAME,
    TC.COMMENTS AS TABLE_COMMENTS
FROM DBA_TABLES T
LEFT JOIN DBA_TAB_COMMENTS TC 
       ON TC.OWNER = T.OWNER
      AND TC.TABLE_NAME = T.TABLE_NAME
WHERE T.OWNER IN (
    'APP_USER',   -- 전자결재 신규 편철/기록물철
    'BBS_USER',   -- 게시판
    'COM_USER',   -- 동호회/커뮤니티
    'ND_USER',    -- 알림/통지
    'RSC_USER',   -- 자원예약
    'SCH_USER',   -- 일정관리
    'SUR_USER',   -- 설문조사
    'TSP_USER',   -- 메신저/근태
    'MIG1_USER',  -- 마이그레이션 스테이징 스키마
    'INTRAWARE',  -- 핸디 그룹웨어 핵심 운영 스키마
    'COPADMIN'    -- 관리자 스키마
)
ORDER BY T.OWNER, T.TABLE_NAME;


-- ============================================================================
-- 2. [테이블 컬럼 및 PK 상세 추출] CSV 보고서용 풀 쿼리
--    (출력 파일명 권장: 이관대상테이블컬럼.csv)
-- ============================================================================
SELECT
    C.OWNER,
    C.TABLE_NAME,
    TC.COMMENTS                                                            AS TABLE_COMMENT,
    C.COLUMN_ID,
    C.COLUMN_NAME,
    CC.COMMENTS                                                            AS COLUMN_COMMENT,
    C.DATA_TYPE ||
        CASE 
            WHEN C.DATA_TYPE IN ('VARCHAR', 'VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR')
                THEN '(' || C.DATA_LENGTH || ')'
            WHEN C.DATA_TYPE = 'NUMBER' AND C.DATA_PRECISION IS NOT NULL 
                THEN '(' || C.DATA_PRECISION || NVL2(C.DATA_SCALE, ',' || C.DATA_SCALE, '') || ')'
        END                                                                AS DATA_TYPE,
    C.NULLABLE,
    C.DATA_DEFAULT,
    CASE WHEN PK.COLUMN_NAME IS NOT NULL THEN 'Y' END                      AS PK
FROM DBA_TAB_COLUMNS C
JOIN DBA_TABLES T
  ON T.OWNER = C.OWNER 
 AND T.TABLE_NAME = C.TABLE_NAME
LEFT JOIN DBA_TAB_COMMENTS TC 
       ON TC.OWNER = C.OWNER 
      AND TC.TABLE_NAME = C.TABLE_NAME
LEFT JOIN DBA_COL_COMMENTS CC 
       ON CC.OWNER = C.OWNER 
      AND CC.TABLE_NAME = C.TABLE_NAME
      AND CC.COLUMN_NAME = C.COLUMN_NAME
LEFT JOIN (
    SELECT 
        CC.OWNER,
        CC.TABLE_NAME,
        CC.COLUMN_NAME
    FROM DBA_CONSTRAINTS C
    JOIN DBA_CONS_COLUMNS CC 
      ON CC.OWNER = C.OWNER
     AND CC.CONSTRAINT_NAME = C.CONSTRAINT_NAME
    WHERE C.CONSTRAINT_TYPE = 'P'
) PK
  ON PK.OWNER = C.OWNER 
 AND PK.TABLE_NAME = C.TABLE_NAME 
 AND PK.COLUMN_NAME = C.COLUMN_NAME
WHERE C.OWNER IN (
    'APP_USER',
    'LUXOR',
    'BBS_USER',
    'COM_USER',
    'ND_USER',
    'RSC_USER',
    'SCH_USER',
    'SUR_USER',
    'TSP_USER',
    'MIG1_USER',
    'INTRAWARE',
    'COPADMIN'
)
ORDER BY C.OWNER, C.TABLE_NAME, C.COLUMN_ID;


-- ============================================================================
-- 3. [Markdown 테이블 포맷 출력용 쿼리] 문서화 자동 생성용
-- ============================================================================
SELECT 
    '|' || C.OWNER || '|' || C.TABLE_NAME || '|' || NVL(TC.COMMENTS, ' ') || '|' 
    || C.COLUMN_ID || '|' || C.COLUMN_NAME || '|' || NVL(CC.COMMENTS, ' ') || '|' 
    || (C.DATA_TYPE ||
        CASE 
            WHEN C.DATA_TYPE IN ('VARCHAR', 'VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR')
                THEN '(' || C.DATA_LENGTH || ')'
            WHEN C.DATA_TYPE = 'NUMBER' AND C.DATA_PRECISION IS NOT NULL 
                THEN '(' || C.DATA_PRECISION || NVL2(C.DATA_SCALE, ',' || C.DATA_SCALE, '') || ')'
        END) || '|'
    || C.NULLABLE || '|' || NVL(TRIM(REPLACE(C.DATA_DEFAULT, CHR(10), '')), ' ') || '|'
    || NVL(CASE WHEN PK.COLUMN_NAME IS NOT NULL THEN 'Y' END, ' ') || '|' AS md_row
FROM DBA_TAB_COLUMNS C
JOIN DBA_TABLES T
  ON T.OWNER = C.OWNER 
 AND T.TABLE_NAME = C.TABLE_NAME
LEFT JOIN DBA_TAB_COMMENTS TC 
       ON TC.OWNER = C.OWNER 
      AND TC.TABLE_NAME = C.TABLE_NAME
LEFT JOIN DBA_COL_COMMENTS CC 
       ON CC.OWNER = C.OWNER 
      AND CC.TABLE_NAME = C.TABLE_NAME
      AND CC.COLUMN_NAME = C.COLUMN_NAME
LEFT JOIN (
    SELECT 
        CC.OWNER,
        CC.TABLE_NAME,
        CC.COLUMN_NAME
    FROM DBA_CONSTRAINTS C
    JOIN DBA_CONS_COLUMNS CC 
      ON CC.OWNER = C.OWNER
     AND CC.CONSTRAINT_NAME = C.CONSTRAINT_NAME
    WHERE C.CONSTRAINT_TYPE = 'P'
) PK
  ON PK.OWNER = C.OWNER 
 AND PK.TABLE_NAME = C.TABLE_NAME 
 AND PK.COLUMN_NAME = C.COLUMN_NAME
WHERE C.OWNER IN ('MIG1_USER', 'INTRAWARE')
ORDER BY C.OWNER, C.TABLE_NAME, C.COLUMN_ID;
