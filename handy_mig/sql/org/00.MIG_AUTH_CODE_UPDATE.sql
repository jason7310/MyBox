-- ====================================================================================================
-- [통합 MIG] MIG1_USER.MG_AUTH 권한코드 표준화 보정 스크립트 (방안 2)
-- 대상 DBMS : Tibero 7
-- 목적 : 중간 테이블(MIG1_USER.MG_AUTH)에 AS-IS 숫자(7105, 2001 등)로 들어가 있는 AUTHCODE를
--        핸디 그룹웨어 10.x 표준 2자리 권한코드(S1, D1, Da, D4, D5)로 일괄 보정합니다.
--
-- [매핑 정의표]
--   1) 7105 -> S1 : 부서장 (Chief/Dept Head)
--   2) 2001 -> D1 : 접수담당자 (기관문서관리책임자)
--   3) 2002 -> D4 : 문서관리자 (부서문서관리책임자)
--   4) 2004 -> Da : 발송담당자 (부서날인관리자 / 기관날인관리자)
--   5) 8002 -> D5 : 열람제외문서함 관리자 / 부서관리자
--   6) 1009 -> D1 : 전자결재 관리자 (전체관리자)
-- ====================================================================================================

-- 1. 보정 전 현재 권한코드 분포 확인
SELECT AUTHCODE, COUNT(*) AS CNT
  FROM MIG1_USER.MG_AUTH
 GROUP BY AUTHCODE
 ORDER BY AUTHCODE;


-- 2. AS-IS 숫자 코드를 핸디 표준 영문 코드로 일괄 UPDATE
UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'S1'
 WHERE AUTHCODE = '7105';

UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'D1'
 WHERE AUTHCODE = '2001';

UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'D4'
 WHERE AUTHCODE = '2002';

UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'Da'
 WHERE AUTHCODE = '2004';

UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'D5'
 WHERE AUTHCODE = '8002';

UPDATE MIG1_USER.MG_AUTH
   SET AUTHCODE = 'D1'
 WHERE AUTHCODE = '1009';

COMMIT;


-- 3. 보정 후 최종 권한코드 분포 검증 (모두 S1, D1, Da, D4, D5 등 영문 2자리여야 함)
SELECT AUTHCODE,
       CASE AUTHCODE
           WHEN 'S1' THEN '부서장'
           WHEN 'D1' THEN '접수담당자 / 전체관리자'
           WHEN 'Da' THEN '발송담당자'
           WHEN 'D4' THEN '문서관리자'
           WHEN 'D5' THEN '열람제외 / 부서관리자'
           WHEN 'U1' THEN '겸직사용자'
           ELSE '미정의 코드 (확인 필요)'
       END AS AUTH_NAME,
       COUNT(*) AS CNT
  FROM MIG1_USER.MG_AUTH
 GROUP BY AUTHCODE
 ORDER BY AUTHCODE;
