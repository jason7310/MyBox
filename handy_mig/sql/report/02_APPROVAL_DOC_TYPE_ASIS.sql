-- ==============================================================================
-- [통합 MIG 보고서 2] 문서구분(생산/기안, 접수/시행, 일괄기안)별 건수 집계 쿼리 (AS-IS)
-- 
-- * 대상 테이블 : MIG1_USER.MG_APPROVAL (ACUBE 원천 이관 중간 테이블)
-- * 분류 기준:
--   - 접수문서(시행) : DOCATTR IN ('4', '5') OR DOCTYPE = '3'
--   - 일괄기안문서   : DOCTYPE = '5'
--   - 생산문서(기안) : 그 외 일반 결재 문서 (DOCTYPE = '1' 등)
-- * 파라미터:
--   - ${TABLE_NAME}    : 대상 테이블 (기본: MIG1_USER.MG_APPROVAL)
--   - ${START_YEAR}    : 시작 연도 (예: 2016)
--   - ${NEXT_END_YEAR} : 종료 연도 + 1 (예: 2027)
-- ==============================================================================
SELECT 
    CASE 
        WHEN DOCTYPE = '3' THEN '접수문서(시행)'
        WHEN DOCTYPE = '5' THEN '일괄기안문서'
        ELSE '생산문서(기안)'
    END AS DOCTYPE_NAME,
    COUNT(1) AS CNT
FROM ${TABLE_NAME}
WHERE NVL(APPROVALDATE, DRAFTDATE) >= TO_DATE('${START_YEAR}0101', 'YYYYMMDD')
  AND NVL(APPROVALDATE, DRAFTDATE) <  TO_DATE('${NEXT_END_YEAR}0101', 'YYYYMMDD')
GROUP BY 
    CASE 
        WHEN DOCTYPE = '3' THEN '접수문서(시행)'
        WHEN DOCTYPE = '5' THEN '일괄기안문서'
        ELSE '생산문서(기안)'
    END
ORDER BY CNT DESC
