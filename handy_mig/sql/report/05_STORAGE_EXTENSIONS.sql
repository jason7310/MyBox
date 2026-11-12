-- ==============================================================================
-- [통합 MIG 보고서 5-2] 파일 확장자(Extension) 상위 집계
-- * 파라미터:
--   - ${TARGET_TABLE} : 파일 메타 테이블 (INTRAWARE.DOCUMENT 또는 MIG1_USER.MG_DOCUMENT)
-- ==============================================================================
SELECT 
    UPPER(SUBSTR(FILENAME, INSTR(FILENAME, '.', -1) + 1)) AS EXT,
    COUNT(1) AS CNT
FROM ${TARGET_TABLE}
WHERE FILENAME LIKE '%.%'
GROUP BY UPPER(SUBSTR(FILENAME, INSTR(FILENAME, '.', -1) + 1))
ORDER BY CNT DESC
