-- ====================================================================================================
-- [테스트 환경] 05. INTRAWARE.FLOW_TEST 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : PARTICIPANT_TEST 데이터를 기반으로 FLOW_TEST 테이블로 참여흐름을 검증 적재합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(F, 16) */ INTO INTRAWARE.FLOW_TEST F (
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
    FROM INTRAWARE.PARTICIPANT_TEST
) P
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON P.APPRID = K.APPRID
WHERE P.RN = 1
;

COMMIT;
