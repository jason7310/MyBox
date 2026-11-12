-- ==============================================================================
-- [통합 MIG 보고서 3] 한국보훈복지의료공단 소속 기관(지사)별 결재문서 집계 쿼리
-- 
-- * 설명:
--   - DRAFTDEPTNAME(기안부서명) 패턴 매칭을 통해 공단 본부, 중앙보훈병원, 5개 지역보훈병원,
--     보훈요양원(전체), 보훈휴양원, 보훈재활체육센터, 보훈의학연구소 등으로 분류 집계합니다.
--   - 기관명 추가/수정이 필요할 경우 이 SQL 파일만 직접 수정하면 즉시 반영됩니다.
--
-- * 파라미터:
--   - ${START_YEAR}    : 시작 연도 (예: 2016)
--   - ${NEXT_END_YEAR} : 종료 연도 + 1 (예: 2027)
-- ==============================================================================
SELECT 
    CASE 
        WHEN DRAFTDEPTNAME LIKE '%중앙보훈병원%' OR DRAFTDEPTNAME LIKE '%중앙병원%' THEN '중앙보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%부산보훈병원%' OR DRAFTDEPTNAME LIKE '%부산병원%' THEN '부산보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%광주보훈병원%' OR DRAFTDEPTNAME LIKE '%광주병원%' THEN '광주보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%대구보훈병원%' OR DRAFTDEPTNAME LIKE '%대구병원%' THEN '대구보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%대전보훈병원%' OR DRAFTDEPTNAME LIKE '%대전병원%' THEN '대전보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%인천보훈병원%' OR DRAFTDEPTNAME LIKE '%인천병원%' THEN '인천보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%요양원%' THEN '보훈요양원(전체)'
        WHEN DRAFTDEPTNAME LIKE '%휴양원%' THEN '보훈휴양원'
        WHEN DRAFTDEPTNAME LIKE '%재활%' THEN '보훈재활체육센터'
        WHEN DRAFTDEPTNAME LIKE '%연구소%' THEN '보훈의학연구소'
        WHEN DRAFTDEPTNAME LIKE '%본부%' OR DRAFTDEPTNAME LIKE '%이사회%' OR DRAFTDEPTNAME LIKE '%감사실%' THEN '공단 본부'
        ELSE '본부 및 기타 소속'
    END AS ORG_NAME,
    COUNT(1) AS CNT
FROM INTRAWARE.APPROVAL
WHERE NVL(APPROVALDATE, DRAFTDATE) >= TO_DATE('${START_YEAR}0101', 'YYYYMMDD')
  AND NVL(APPROVALDATE, DRAFTDATE) <  TO_DATE('${NEXT_END_YEAR}0101', 'YYYYMMDD')
GROUP BY 
    CASE 
        WHEN DRAFTDEPTNAME LIKE '%중앙보훈병원%' OR DRAFTDEPTNAME LIKE '%중앙병원%' THEN '중앙보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%부산보훈병원%' OR DRAFTDEPTNAME LIKE '%부산병원%' THEN '부산보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%광주보훈병원%' OR DRAFTDEPTNAME LIKE '%광주병원%' THEN '광주보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%대구보훈병원%' OR DRAFTDEPTNAME LIKE '%대구병원%' THEN '대구보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%대전보훈병원%' OR DRAFTDEPTNAME LIKE '%대전병원%' THEN '대전보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%인천보훈병원%' OR DRAFTDEPTNAME LIKE '%인천병원%' THEN '인천보훈병원'
        WHEN DRAFTDEPTNAME LIKE '%요양원%' THEN '보훈요양원(전체)'
        WHEN DRAFTDEPTNAME LIKE '%휴양원%' THEN '보훈휴양원'
        WHEN DRAFTDEPTNAME LIKE '%재활%' THEN '보훈재활체육센터'
        WHEN DRAFTDEPTNAME LIKE '%연구소%' THEN '보훈의학연구소'
        WHEN DRAFTDEPTNAME LIKE '%본부%' OR DRAFTDEPTNAME LIKE '%이사회%' OR DRAFTDEPTNAME LIKE '%감사실%' THEN '공단 본부'
        ELSE '본부 및 기타 소속'
    END
ORDER BY CNT DESC
