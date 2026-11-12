-- ==============================================================================
-- [통합 MIG 보고서 5] 본문 및 첨부파일 스토리지 물리 통계 쿼리
-- 
-- * 파라미터:
--   - ${TARGET_TABLE} : 파일 메타 테이블 (INTRAWARE.DOCUMENT 또는 MIG1_USER.MG_DOCUMENT)
-- ==============================================================================

-- [쿼리 1] 파일 총수량 및 본문/첨부별 용량/건수 집계
SELECT 
    COUNT(1) AS TOTAL_CNT,
    NVL(SUM(NVL(FILESIZE, 0)), 0) AS TOTAL_SIZE,
    NVL(SUM(CASE WHEN DOCUMENTTYPE = '1' THEN 1 ELSE 0 END), 0) AS BODY_CNT,
    NVL(SUM(CASE WHEN DOCUMENTTYPE = '1' THEN NVL(FILESIZE, 0) ELSE 0 END), 0) AS BODY_SIZE,
    NVL(SUM(CASE WHEN DOCUMENTTYPE <> '1' THEN 1 ELSE 0 END), 0) AS ATTACH_CNT,
    NVL(SUM(CASE WHEN DOCUMENTTYPE <> '1' THEN NVL(FILESIZE, 0) ELSE 0 END), 0) AS ATTACH_SIZE
FROM ${TARGET_TABLE};

-- [쿼리 2] 파일 확장자(Extension) 상위 집계
SELECT 
    UPPER(SUBSTR(FILENAME, INSTR(FILENAME, '.', -1) + 1)) AS EXT,
    COUNT(1) AS CNT
FROM ${TARGET_TABLE}
WHERE FILENAME LIKE '%.%'
GROUP BY UPPER(SUBSTR(FILENAME, INSTR(FILENAME, '.', -1) + 1))
ORDER BY CNT DESC;
