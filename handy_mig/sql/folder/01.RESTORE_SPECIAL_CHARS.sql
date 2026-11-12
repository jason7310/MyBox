-- ============================================================================
-- [통합 MIG] 기록물철 후속 처리 - 01. 특수문자 및 명칭 원본 복구
-- 
-- * 배경: 핸디 rtool.sh 등록 시 구문 파싱 오류를 방지하기 위해 치환되었던
--         특수문자(^, #, \, l) 및 40바이트 초과 축약 명칭을 원본으로 일괄 복구합니다.
-- ============================================================================

-- 1. 단위업무(BIZUNIT) 명칭 원본 복구
UPDATE INTRAWARE.BIZUNIT
   SET BIZUNITNAME = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(BIZUNITNAME, 'BIGUNITNAME', '기획(예산,정보시스템,조사,문서,감사)'), '#', '('), '\', ')'), 'l', '/'), '^', ',')
 WHERE REGEXP_LIKE(BIZUNITNAME, '[\^#\\l]')
    OR BIZUNITNAME LIKE '%BIGUNITNAME%';

COMMIT;

-- 2. 기록물철(FOLDER) 명칭 원본 복구 (기록물철 APPLID = 7010 대상)
UPDATE INTRAWARE.FOLDER
   SET FLDRNAME = REPLACE(REPLACE(REPLACE(REPLACE(FLDRNAME, '^', ','), '#', '('), '\', ')'), 'l', '/')
 WHERE APPLID = 7010
   AND REGEXP_LIKE(FLDRNAME, '[\^#\\l]');

COMMIT;

SELECT '특수문자 및 명칭 원본 복구 완료' AS STATUS, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS FINISH_TIME FROM DUAL;
