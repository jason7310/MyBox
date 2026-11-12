-- ====================================================================================================
-- [Handy MIG] 03. INTRAWARE.SEND 직접 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 규격 : Handy 10.x 공식 스키마 42개 컬럼 100% 일치
-- 목적 : 2차 중간 테이블(MG_SEND) 적재 및 MERGE 단계를 전면 배제하고,
--        키 매핑 인덱스(MAPPING_APPR_KEY)를 조인하여 운영 테이블(INTRAWARE.SEND)로 직접 고속 적재합니다.
--        (퇴사자/폐지부서 3중 방어: ID는 000000000 기본값, 성명/부서명 텍스트는 원본 100% 보존)
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(S, 16) */ INTO INTRAWARE.SEND S (
    SENDID,
    APPRID,
    CONTENTID,
    SENDTYPE,
    PARSENDID,
    RECDOCSTATUS,
    RECEIVERID,
    RECEIVERNAME,
    SENDERTYPE,
    SENDERID,
    SENDERNAME,
    SENDDEPTID,
    SENDDEPTNAME,
    SENDDATE,
    DOCRECVDATE,
    PROCRECVDATE,
    APPROVALDATE,
    RECEIPTAPPRID,
    RECEIVERTYPE,
    ASSIGNUSERID,
    ASSIGNUSERNAME,
    RECEIPTBASEDATE,
    REGNO,
    RESENDREQDATE,
    BROADNO,
    BROADDATE,
    BROADUSERID,
    BROADUSERNAME,
    BROADDEPTID,
    BROADDEPTNAME,
    NUMATTR,
    REJECTDATE,
    REJECTERID,
    REJECTERNAME,
    CHARGECONFIRMSTATUS,
    CHARGEID,
    ACTIONID,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    RETRYCOUNT
)
SELECT /*+ PARALLEL(MS, 16) PARALLEL(K, 16) */
    -- 1) 발송ID 및 결재ID (MAPPING_APPR_KEY에서 즉시 결합)
    CASE 
        WHEN MS.SEND_ID IS NOT NULL AND LENGTH(MS.SEND_ID) = 20 THEN MS.SEND_ID
        ELSE SUBSTR(K.APPRID, 1, 18) || '99'
    END                                                                     AS SENDID,
    K.APPRID                                                                AS APPRID,
    '00000000000000000000'                                                  AS CONTENTID,
    NVL(MS.SENDTYPE, '0')                                                   AS SENDTYPE,
    
    -- 원문서(수신문서)가 존재하는 경우 상위발송ID 인라인 매핑
    CASE 
        WHEN K_RECV.APPRID IS NOT NULL THEN SUBSTR(K_RECV.APPRID, 1, 18) || '99'
        ELSE '00000000000000000000'
    END                                                                     AS PARSENDID,
    NVL(MS.RECDOCSTATUS, '8')                                               AS RECDOCSTATUS,

    -- 2) 수신처 정보 (조직도 매핑 실패 시에도 원본 부서명/수신처명 100% 보존)
    NVL(DG_RECV.DEPT_ID, '000000000')                                       AS RECEIVERID,
    MS.RECEIVERNAME                                                         AS RECEIVERNAME,
    '1'                                                                     AS SENDERTYPE,

    -- 3) 발신자 정보 (퇴사자/폐지부서 방어: 사번 매핑 실패 시 000000000, 성명/부서명 원본 보존)
    NVL(UG_SEND.USER_ID, '000000000')                                       AS SENDERID,
    MS.SENDERNAME                                                           AS SENDERNAME,
    NVL(DG_SEND.DEPT_ID, '000000000')                                       AS SENDDEPTID,
    MS.SENDDEPTNAME                                                         AS SENDDEPTNAME,

    -- 4) 일자 정보
    MS.SENDDATE                                                             AS SENDDATE,
    MS.DOCRECVDATE                                                          AS DOCRECVDATE,
    MS.PROCRECVDATE                                                         AS PROCRECVDATE,
    MS.APPROVALDATE                                                         AS APPROVALDATE,

    -- 5) 수신결재문서 ID 및 담당자 정보
    NVL(K_RECV.APPRID, '00000000000000000000')                              AS RECEIPTAPPRID,
    NVL(MS.RECEIVERTYPE, '0')                                               AS RECEIVERTYPE,
    NVL(UG_ASSIGN.USER_ID, '000000000')                                     AS ASSIGNUSERID,
    MS.ASSIGNUSERNAME                                                       AS ASSIGNUSERNAME,
    MS.RECEIPTBASEDATE                                                      AS RECEIPTBASEDATE,
    MS.REGNO                                                                AS REGNO,
    MS.RESENDREQDATE                                                        AS RESENDREQDATE,
    MS.BROADNO                                                              AS BROADNO,
    MS.BROADDATE                                                            AS BROADDATE,
    NVL(MS.BROADUSERID, '000000000')                                        AS BROADUSERID,
    MS.BROADUSERNAME                                                        AS BROADUSERNAME,
    NVL(MS.BROADDEPTID, '000000000')                                        AS BROADDEPTID,
    MS.BROADDEPTNAME                                                        AS BROADDEPTNAME,
    NVL(MS.NUMATTR, '0')                                                    AS NUMATTR,
    
    -- 6) 반려 정보
    MS.REJECTDATE                                                           AS REJECTDATE,
    NVL(UG_REJ.USER_ID, '000000000')                                        AS REJECTERID,
    MS.REJECTERNAME                                                         AS REJECTERNAME,

    -- 7) 담당 및 상태 정보 (Handy 10.x 신규 필수 컬럼)
    '0'                                                                     AS CHARGECONFIRMSTATUS,
    '00000000000000000000'                                                  AS CHARGEID,
    '00000000000000000000'                                                  AS ACTIONID,

    -- 8) 등록 및 수정자 정보
    NVL(MS.UPDATEDATE, SYSDATE)                                             AS REGISTDATE,
    NVL(UG_UPD.USER_ID, '000000000')                                        AS REGISTERID,
    NVL(MS.UPDATEDATE, SYSDATE)                                             AS UPDATEDATE,
    '000000000'                                                             AS UPDATERID,
    0                                                                       AS RETRYCOUNT

FROM MIG1_USER.MG_SEND MS

-- 1) 결재ID 매핑: 기안문서 기준 APPRID 확보
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON MS.DOC_ID = K.DOC_ID

-- 2) 수신문서 매핑 (수신문서 ORIGIN_DOC_ID 연결)
LEFT JOIN INTRAWARE.MAPPING_APPR_KEY K_RECV
  ON MS.ORIGIN_DOC_ID = K_RECV.DOC_ID

-- 3) 조직도 부서 매핑 (부서코드 기준 매핑)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_RECV
  ON DG_RECV.DEPT_CODE = MS.RECEIVERID

LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_SEND
  ON DG_SEND.DEPT_CODE = MS.SENDDEPTID

-- 4) 조직도 사용자 매핑 (사번 기준 매핑: 재직자뿐만 아니라 이관된 퇴사자까지 포괄)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_SEND
  ON UG_SEND.EMP_CODE = SUBSTR(MS.SENDERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_ASSIGN
  ON UG_ASSIGN.EMP_CODE = SUBSTR(MS.ASSIGNUSERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_REJ
  ON UG_REJ.EMP_CODE = SUBSTR(MS.REJECTERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_UPD
  ON UG_UPD.EMP_CODE = SUBSTR(MS.UPDATERID, 3, 6)
;

COMMIT;
