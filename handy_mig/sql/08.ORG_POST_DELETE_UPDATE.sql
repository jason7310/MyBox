-- ====================================================================================================
-- [통합 MIG] 08. 조직도 결재이관 후 폐지부서 및 퇴직자 일괄 삭제 처리 (Post-Delete Update)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
--
-- ⭐ [실행 시점] : 
--   1단계(조직도 ALL-ADD 등록) ➔ 2단계(전자결재 전체 이관 완료) ➔ ⭐ [3단계: 오픈 D-Day 직전 본 쿼리 실행]
--
-- 목적 : 
--   1. 전자결재 이관 중 과거 작성자/결재자/부서 ID 결손 방지를 위해 선등록해 두었던 전체 조직도 중,
--      MIG1_USER(원천)에서 삭제/폐지 플래그(DELETED = 1)로 지정된 부서와 퇴직자를 
--      핸디 그룹웨어 표준 삭제 상태인 STATUS = '4' 로 초고속 원터치 일괄 변경합니다.
--   2. 이 처리를 통해 기존 이관된 전자결재 문서의 결재선/부서 정보는 100% 정상 보존되면서,
--      운영 오픈 후 사용자의 신규 결재선 지정 팝업 및 조직도 트리에는 폐지부서/퇴직자가 노출되지 않습니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ====================================================================================================
-- 1. 폐지 부서 STATUS -> '4' 일괄 업데이트 및 접수함/문서함 비활성화
-- ====================================================================================================
PROMPT [조직도 후처리] 1. 폐지 부서 STATUS = '4' 일괄 업데이트 시작...

UPDATE /*+ PARALLEL(D, 8) */ INTRAWARE.DEPT_GLOBAL D
   SET D.STATUS      = '4',
       D.RECV_BOX_F  = '0',
       D.BOX_F       = '0',
       D.MODIFY_DATE = SYSDATE
 WHERE D.DEPT_ID IN (
       SELECT TRIM(MD.DEPTCODE)
         FROM MIG1_USER.MG_DEPT MD
        WHERE NVL(MD.DELETED, 0) = 1
          AND MD.DEPTCODE IS NOT NULL
 )
   AND D.STATUS != '4';

COMMIT;

PROMPT [성공] 폐지 부서 일괄 삭제 처리 완료!


-- ====================================================================================================
-- 2. 퇴직/삭제 사용자 STATUS -> '4' 일괄 업데이트 및 결재/수발신함 비활성화
-- ====================================================================================================
PROMPT [조직도 후처리] 2. 퇴직/삭제 사용자 STATUS = '4' 일괄 업데이트 시작...

UPDATE /*+ PARALLEL(U, 16) */ INTRAWARE.USR_GLOBAL U
   SET U.STATUS      = '4',
       U.SANC_BOX_F  = '0',
       U.RECV_SEND_F = '0',
       U.MODIFY_DATE = SYSDATE
 WHERE U.USER_ID IN (
       SELECT TRIM(NVL(MU.EMPCODE, MU.USER_ID))
         FROM MIG1_USER.MG_USER MU
        WHERE NVL(MU.DELETED, 0) = 2
          AND (MU.EMPCODE IS NOT NULL OR MU.USER_ID IS NOT NULL)
 )
   AND U.STATUS != '4';

COMMIT;

PROMPT [성공] 퇴직/삭제 사용자 일괄 삭제 처리 완료!


-- ====================================================================================================
-- 2-1. 퇴직자 부서장/접수담당 권한(USR_AUTH) 정리 (오픈 후 자동 지정 오류 원천 방지)
-- ====================================================================================================
PROMPT [조직도 후처리] 2-1. 퇴직자 불필요 직무 권한(USR_AUTH) 정리 시작...

DELETE FROM INTRAWARE.USR_AUTH A
 WHERE A.USER_ID IN (
       SELECT TRIM(NVL(MU.EMPCODE, MU.USER_ID))
         FROM MIG1_USER.MG_USER MU
        WHERE NVL(MU.DELETED, 0) = 2
          AND (MU.EMPCODE IS NOT NULL OR MU.USER_ID IS NOT NULL)
 );

COMMIT;

PROMPT [성공] 퇴직자 권한 정보 정리 완료!


-- ====================================================================================================
-- 3. 후처리 결과 최종 정합성 검증 리포트
-- ====================================================================================================
PROMPT 
PROMPT ====================================================================================
PROMPT  [조직도 후처리 최종 상태 검증 리포트]
PROMPT ====================================================================================

-- 3-1. 부서 상태별 통계
SELECT 
    'DEPT_GLOBAL'                               AS TABLE_NAME,
    COUNT(CASE WHEN STATUS = '1' THEN 1 END)    AS NORMAL_COUNT,    -- 정상 부서 (1)
    COUNT(CASE WHEN STATUS = '4' THEN 1 END)    AS DELETED_COUNT,   -- 폐지/삭제 부서 (4)
    COUNT(*)                                    AS TOTAL_COUNT
  FROM INTRAWARE.DEPT_GLOBAL;

-- 3-2. 사용자 상태별 통계
SELECT 
    'USR_GLOBAL'                                AS TABLE_NAME,
    COUNT(CASE WHEN STATUS = '1' THEN 1 END)    AS NORMAL_COUNT,    -- 정상 재직자 (1)
    COUNT(CASE WHEN STATUS = '4' THEN 1 END)    AS DELETED_COUNT,   -- 퇴직/삭제자 (4)
    COUNT(*)                                    AS TOTAL_COUNT
  FROM INTRAWARE.USR_GLOBAL;

PROMPT ====================================================================================
PROMPT [완료] 조직도 삭제 후처리가 성공적으로 완료되었습니다.
PROMPT ====================================================================================
