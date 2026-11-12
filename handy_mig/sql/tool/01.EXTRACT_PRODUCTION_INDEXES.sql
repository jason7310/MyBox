-- ====================================================================================================
-- [DBA 유틸리티] 운영서버 실제 적용 인덱스 전수 추출 및 DDL 자동 생성 쿼리
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 운영 데이터베이스(INTRAWARE)에 실제로 생성되어 운영 중인 결재 관련 테이블의 모든 인덱스를
--        컬럼 구성 순서와 함께 전수 추출하고, 테스트용 DDL 및 리빌드 쿼리를 자동 생성합니다.
-- ====================================================================================================

-- ----------------------------------------------------------------------------------------------------
-- 1. 운영 결재 테이블 인덱스 현황 전수 상세 조회 (테이블명, 인덱스명, 유형, 컬럼목록, 상태)
-- ----------------------------------------------------------------------------------------------------
SELECT 
    I.TABLE_NAME,
    I.INDEX_NAME,
    I.UNIQUENESS,
    I.STATUS,
    I.TABLESPACE_NAME,
    LISTAGG(C.COLUMN_NAME || ' ' || C.DESCEND, ', ') WITHIN GROUP (ORDER BY C.COLUMN_POSITION) AS INDEX_COLUMNS
FROM USER_INDEXES I
JOIN USER_IND_COLUMNS C 
  ON I.INDEX_NAME = C.INDEX_NAME AND I.TABLE_NAME = C.TABLE_NAME
WHERE I.TABLE_NAME IN ('APPROVAL', 'SEND', 'PARTICIPANT', 'FLOW', 'DOCUMENT', 'DOCMBR')
GROUP BY 
    I.TABLE_NAME,
    I.INDEX_NAME,
    I.UNIQUENESS,
    I.STATUS,
    I.TABLESPACE_NAME
ORDER BY 
    I.TABLE_NAME, 
    I.UNIQUENESS DESC, 
    I.INDEX_NAME;


-- ----------------------------------------------------------------------------------------------------
-- 2. 운영 테이블 인덱스 일괄 REBUILD 쿼리 자동 생성 (복사하여 sql/08.REBUILD_OPERATIONAL_INDEXES.sql에 반영 가능)
-- ----------------------------------------------------------------------------------------------------
SELECT 
    'ALTER INDEX ' || I.INDEX_NAME || ' REBUILD PARALLEL 16 NOLOGGING;' AS REBUILD_DDL,
    'ALTER INDEX ' || I.INDEX_NAME || ' NOPARALLEL LOGGING;'            AS RESTORE_DDL
FROM USER_INDEXES I
WHERE I.TABLE_NAME IN ('APPROVAL', 'SEND', 'PARTICIPANT', 'FLOW', 'DOCUMENT', 'DOCMBR')
ORDER BY I.TABLE_NAME, I.INDEX_NAME;


-- ----------------------------------------------------------------------------------------------------
-- 3. 운영 인덱스 기반 _TEST 테이블용 CREATE INDEX DDL 자동 생성 (완벽한 1:1 복제)
-- ----------------------------------------------------------------------------------------------------
SELECT 
    'CREATE ' || DECODE(I.UNIQUENESS, 'UNIQUE', 'UNIQUE ', '') || 'INDEX ' || 
    I.INDEX_NAME || '_TEST ON ' || I.TABLE_NAME || '_TEST (' ||
    LISTAGG(C.COLUMN_NAME || ' ' || C.DESCEND, ', ') WITHIN GROUP (ORDER BY C.COLUMN_POSITION) || 
    ') PARALLEL 16 NOLOGGING;' AS TEST_CREATE_INDEX_DDL
FROM USER_INDEXES I
JOIN USER_IND_COLUMNS C 
  ON I.INDEX_NAME = C.INDEX_NAME AND I.TABLE_NAME = C.TABLE_NAME
WHERE I.TABLE_NAME IN ('APPROVAL', 'SEND', 'PARTICIPANT', 'FLOW', 'DOCUMENT', 'DOCMBR')
GROUP BY 
    I.TABLE_NAME,
    I.INDEX_NAME,
    I.UNIQUENESS
ORDER BY 
    I.TABLE_NAME, 
    I.INDEX_NAME;
