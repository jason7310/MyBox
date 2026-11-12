-- ==============================================================================
-- [통합 MIG 보고서 4-2] 미편철 사유별 세부 분석
-- ==============================================================================
SELECT 
    CASE 
        WHEN SAVEDEPTID IS NULL OR SAVEDEPTID = '000000000' THEN '보존부서(SAVEDEPTID) 누락'
        WHEN SPECIALLIST1 IS NULL OR TRIM(SPECIALLIST1) IS NULL THEN '원천 바인드ID(SPECIALLIST1) 누락'
        ELSE '원천 바인드ID에 대응하는 편철함 미존재 또는 년도 불일치'
    END AS REASON,
    COUNT(*) AS CNT
FROM INTRAWARE.APPROVAL
WHERE FOLDERID IS NULL OR FOLDERID = '00000000000000000000'
GROUP BY 
    CASE 
        WHEN SAVEDEPTID IS NULL OR SAVEDEPTID = '000000000' THEN '보존부서(SAVEDEPTID) 누락'
        WHEN SPECIALLIST1 IS NULL OR TRIM(SPECIALLIST1) IS NULL THEN '원천 바인드ID(SPECIALLIST1) 누락'
        ELSE '원천 바인드ID에 대응하는 편철함 미존재 또는 년도 불일치'
    END
ORDER BY CNT DESC
