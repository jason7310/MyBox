-- ====================================================================================================
-- [테스트 환경] 04. INTRAWARE.PARTICIPANT_TEST 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 운영 PARTICIPANT 테이블 대신 PARTICIPANT_TEST 테이블로 결재선 데이터를 검증 적재합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(P, 16) */ INTO INTRAWARE.PARTICIPANT_TEST P (
    PARTICIPANTID,
    APPRID,
    LINETYPE,
    SEQ,
    SIGNERSEQ,
    SIGNERTYPE,
    APPROVALTYPE,
    APPROVALSTATUS,
    POSITIONNAME,
    SIGNERID,
    SIGNERNAME,
    ABSENTFLAG,
    ABSENTEEID,
    ARRIVALDATE,
    SIGNDATE,
    DUEDATE,
    OPENDATE,
    ACTORID,
    VALIDFLAG,
    APPROVALTYPENAME,
    ROLETYPE,
    BFMAJORVERSION,
    BFMINORVERSION,
    PARTATTR,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    SIGNERDEPTID,
    ABSENTEEDEPTID,
    ACTORDEPTID
)
SELECT /*+ PARALLEL(MP, 16) PARALLEL(K, 16) */
    -- 1) 참여자ID 및 결재ID (인라인 채번: 결재ID 17자리 + 순번 3자리)
    SUBSTR(K.APPRID, 1, 17) || LPAD(ROW_NUMBER() OVER (
        PARTITION BY MP.DOC_ID 
        ORDER BY MP.LINETYPE, MP.SEQ, NVL(MP.LINE_SUB_ORDER, 1), MP.SIGNERID
    ), 3, '0')                                                              AS PARTICIPANTID,
    K.APPRID                                                                AS APPRID,
    MP.LINETYPE                                                             AS LINETYPE,
    MP.SEQ                                                                  AS SEQ,
    NVL(MP.LINE_SUB_ORDER, 1)                                               AS SIGNERSEQ,
    MP.SIGNERTYPE                                                           AS SIGNERTYPE,
    MP.APPROVALTYPE                                                         AS APPROVALTYPE,
    MP.APPROVALSTATUS                                                       AS APPROVALSTATUS,
    CASE 
        WHEN MP.POSITIONNAME = '<BR/>' OR MP.POSITIONNAME IS NULL THEN '담당' 
        ELSE MP.POSITIONNAME 
    END                                                                     AS POSITIONNAME,

    -- 2) 결재자 사번 -> 핸디 USER_ID 매핑 (STATUS='1' 제거로 퇴직자 매핑 보장, 결측 시 '000000000' 방어)
    NVL(UG_SIGNER.USER_ID, '000000000')                                     AS SIGNERID,
    MP.SIGNERNAME                                                           AS SIGNERNAME,
    NVL(MP.ABSENTFLAG, '0')                                                 AS ABSENTFLAG,
    NVL(MP.ABSENTEEID, '000000000')                                         AS ABSENTEEID,
    MP.ARRIVALDATE                                                          AS ARRIVALDATE,
    MP.SIGNDATE                                                             AS SIGNDATE,
    MP.DUEDATE                                                              AS DUEDATE,
    MP.OPENDATE                                                             AS OPENDATE,
    '000000000'                                                             AS ACTORID,
    NVL(MP.VALIDFLAG, '0')                                                  AS VALIDFLAG,
    MP.APPROVALTYPENAME                                                     AS APPROVALTYPENAME,
    NVL(MP.ROLETYPE, '0')                                                   AS ROLETYPE,
    NVL(MP.BFMAJORVERSION, 0)                                               AS BFMAJORVERSION,
    NVL(TO_CHAR(MP.BFMINORVERSION), '0')                                    AS BFMINORVERSION,
    NVL(MP.PARTATTR, '00000000000000000')                                   AS PARTATTR,
    NVL(MP.REGISTDATE, NVL(MP.SIGNDATE, MP.ARRIVALDATE))                    AS REGISTDATE,
    NVL(UG_SIGNER.USER_ID, '000000000')                                     AS REGISTERID,
    MP.UPDATEDATE                                                           AS UPDATEDATE,
    NVL(MP.UPDATERID, '000000000')                                          AS UPDATERID,
    NVL(DG_SIGNER.DEPT_ID, '000000000')                                     AS SIGNERDEPTID,
    '000000000'                                                             AS ABSENTEEDEPTID,
    '000000000'                                                             AS ACTORDEPTID

FROM MIG1_USER.MG_PARTICIPANT MP

-- 1) 고속 조인: 결재ID 획득
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON MP.DOC_ID = K.DOC_ID

-- 2) 조직도 사용자 매핑 (사번 기준, 퇴직자 포함)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_SIGNER
  ON UG_SIGNER.EMP_CODE = SUBSTR(MP.SIGNERID, 3, 6)

-- 3) 조직도 부서 매핑 (부서코드 기준, 폐지부서 포함)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_SIGNER
  ON DG_SIGNER.DEPT_CODE = MP.SIGNERDEPTID
;

COMMIT;
