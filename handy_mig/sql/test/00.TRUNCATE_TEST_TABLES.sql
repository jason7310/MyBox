-- ====================================================================================================
-- [테스트 환경] 00. 테스트 테이블 고속 데이터 초기화 (TRUNCATE)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : DROP 없이 0.01초 내에 HWM을 리셋하고 인덱스 구조를 유지하여 반복 테스트를 즉시 수행합니다.
-- ====================================================================================================

TRUNCATE TABLE INTRAWARE.APPROVAL_TEST;
TRUNCATE TABLE INTRAWARE.SEND_TEST;
TRUNCATE TABLE INTRAWARE.PARTICIPANT_TEST;
TRUNCATE TABLE INTRAWARE.FLOW_TEST;
TRUNCATE TABLE INTRAWARE.DOCUMENT_TEST;
TRUNCATE TABLE INTRAWARE.DOCMBR_TEST;

COMMIT;
