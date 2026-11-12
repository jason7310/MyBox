-- ====================================================================================================
-- [통합 MIG] 05. INTRAWARE.FLOW 직접 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 선행 적재된 INTRAWARE.PARTICIPANT 데이터를 기반으로,
--        참여흐름(FLOW) 운영 테이블로 직접 고속 적재합니다.
--
-- ⭐ [최적화 규격]
--  1. MAPPING_APPR_KEY와의 조인을 통해 현재 이관 배치 대상 문서만 정확히 선별 적재
--  2. (APPRID, LINETYPE, SEQ) 단위 그룹화에서 첫 결재선(SIGNERSEQ 최솟값) 메타를 기준으로 흐름 상태 산출
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(F, 16) */ INTO INTRAWARE.FLOW F (
    APPRID,
    LINETYPE,
    SEQ,
    APPROVALTYPE,
    APPROVALSTATUS,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID
)
SELECT /*+ PARALLEL(P, 16) PARALLEL(K, 16) */
    P.APPRID,
    P.LINETYPE,
    P.SEQ,
    P.APPROVALTYPE,
    P.APPROVALSTATUS,
    NVL(P.REGISTDATE, NVL(P.SIGNDATE, P.ARRIVALDATE))                       AS REGISTDATE,
    NVL(P.REGISTERID, P.SIGNERID)                                           AS REGISTERID,
    NVL(P.UPDATEDATE, NVL(P.SIGNDATE, SYSDATE))                             AS UPDATEDATE,
    NVL(P.UPDATERID, '000000000')                                           AS UPDATERID
FROM (
    SELECT 
        APPRID,
        LINETYPE,
        SEQ,
        APPROVALTYPE,
        APPROVALSTATUS,
        REGISTDATE,
        REGISTERID,
        UPDATEDATE,
        UPDATERID,
        ARRIVALDATE,
        SIGNDATE,
        SIGNERID,
        ROW_NUMBER() OVER (
            PARTITION BY APPRID, LINETYPE, SEQ 
            ORDER BY SIGNERSEQ ASC, PARTICIPANTID ASC
        ) AS RN
    FROM INTRAWARE.PARTICIPANT
) P
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON P.APPRID = K.APPRID
WHERE P.RN = 1
;

COMMIT;
