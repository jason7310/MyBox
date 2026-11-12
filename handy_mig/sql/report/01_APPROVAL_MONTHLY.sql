-- ==============================================================================
-- [통합 MIG 보고서 1] 연월별 결재문서 생산/이관 매트릭스 피벗 집계 쿼리
-- 
-- * 파라미터:
--   - ${TABLE_NAME}    : 대상 테이블 (INTRAWARE.APPROVAL 또는 MIG1_USER.MG_APPROVAL)
--   - ${START_YEAR}    : 시작 연도 (예: 2016)
--   - ${NEXT_END_YEAR} : 종료 연도 + 1 (예: 2027)
-- ==============================================================================
SELECT 
    TO_NUMBER(TO_CHAR(NVL(APPROVALDATE, DRAFTDATE), 'YYYY')) AS YYYY,
    TO_NUMBER(TO_CHAR(NVL(APPROVALDATE, DRAFTDATE), 'MM')) AS MM,
    COUNT(1) AS CNT
FROM ${TABLE_NAME}
WHERE NVL(APPROVALDATE, DRAFTDATE) >= TO_DATE('${START_YEAR}0101', 'YYYYMMDD')
  AND NVL(APPROVALDATE, DRAFTDATE) <  TO_DATE('${NEXT_END_YEAR}0101', 'YYYYMMDD')
GROUP BY TO_CHAR(NVL(APPROVALDATE, DRAFTDATE), 'YYYY'), TO_CHAR(NVL(APPROVALDATE, DRAFTDATE), 'MM')
ORDER BY YYYY, MM
