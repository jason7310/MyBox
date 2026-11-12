-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 07. 권한 정보 추출 (MG_AUTH -> CSV) [방안 1 적용]
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 권한 관리 > 일괄등록(CSV) (또는 DB 직접 INSERT)
-- * 추출 순서: 7순위 (부서, 직위, 직급, 사용자 등록 완료 후 최종 진행)
-- * 원본 테이블: MIG1_USER.MG_AUTH
--   - 방안 1 적용: MIG1_USER.MG_AUTH 원본의 숫자 코드(7105, 2001 등)를 변경하지 않고
--                 추출 쿼리에서 인라인 CASE 문으로 핸디 표준 코드(S1, D1, Da, D4, D5)로 변환!
--
-- [인라인 매핑 변환 정의]
--   * 7105 -> S1 : 부서장 (21)
--   * 2001 -> D1 : 접수담당자 / 기관문서관리책임자 (11)
--   * 2002 -> D4 : 문서관리자 / 부서문서관리책임자 (14)
--   * 2004 -> Da : 발송담당자 / 부서날인관리자 (51)
--   * 8002 -> D5 : 열람제외문서함 관리자 / 부서관리자 (15)
--   * 1009 -> D1 : 전자결재 관리자 (11)
--   * U1   -> U1 : 겸직사용자 (1)
-- ============================================================================

-- [핸디 그룹웨어 권한 CSV 헤더 규격]
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 AUTH INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*OPERATION,EMPCODE,AUTHCODE,RELCODE' AS csv_row
  FROM DUAL
UNION ALL
-- 권한 데이터 추출 (방안 1: 인라인 매핑 변환)
SELECT 
    'ADD'                                                                 -- 1. OPERATION
    || ',' || TRIM(A.EMPCODE)                                             -- 2. EMPCODE (사용자 사번)
    || ',' || CASE TRIM(A.AUTHCODE)                                       -- 3. AUTHCODE (핸디 표준 코드로 인라인 변환)
                  WHEN '7105' THEN 'S1'  -- 부서장
                  WHEN '2001' THEN 'D1'  -- 접수담당자 (기관문서관리책임자)
                  WHEN '2002' THEN 'D4'  -- 문서관리자 (부서문서관리책임자)
                  WHEN '2004' THEN 'Da'  -- 발송담당자 (부서날인관리자)
                  WHEN '8002' THEN 'D5'  -- 열람제외문서함 관리자 / 부서관리자
                  WHEN '1009' THEN 'D1'  -- 전자결재 관리자
                  ELSE TRIM(A.AUTHCODE)  -- 이미 영문 코드로 된 경우 유지
              END
    || ',' || TRIM(NVL(A.DEPTCODE, NVL(A.EMPCODE2, '000000000')))        -- 4. RELCODE (대상 부서코드 또는 대상 사용자코드)
    AS csv_row
  FROM (
      SELECT DISTINCT 
             EMPCODE,
             AUTHCODE,
             DEPTCODE,
             EMPCODE2
        FROM MIG1_USER.MG_AUTH
       WHERE EMPCODE IS NOT NULL 
         AND AUTHCODE IS NOT NULL
       ORDER BY AUTHCODE ASC, EMPCODE ASC
  );
