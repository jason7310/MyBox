-- ==============================================================================
-- [통합 MIG 보고서 4-1] 결재문서 편철율 조회
-- FOLDERID 정상 편철 여부(NULL 또는 20자리 '0' 제외) 집계
-- ==============================================================================
SELECT 
    COUNT(*) AS TOTAL,
    SUM(CASE WHEN FOLDERID IS NOT NULL AND FOLDERID <> '00000000000000000000' THEN 1 ELSE 0 END) AS MAPPED,
    SUM(CASE WHEN FOLDERID IS NULL OR FOLDERID = '00000000000000000000' THEN 1 ELSE 0 END) AS UNMAPPED
FROM INTRAWARE.APPROVAL
