-- ====================================================================================================
-- [테스트 환경] 03. INTRAWARE.SEND_TEST 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 운영 SEND 테이블 대신 SEND_TEST 테이블로 시행/발송 데이터를 검증 적재합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(S, 16) */ INTO INTRAWARE.SEND_TEST S (
    SENDID,
    APPRID,
    DOCNO,
    SENDDEPTNAME,
    TITLE,
    RECEIVERTYPE,
    RECEIVERNAME,
    SENDFLAG,
    SENDDATE,
    SENDSTATUS,
    SENDERNAME,
    SENDERID,
    SENDERDEPTNAME,
    SENDERDEPTID,
    CHARGECONFIRMFLAG,
    SUBSEQ,
    PARSENDID,
    PARRECEIVERSEQ,
    RECEIVERSEQ,
    RECEIVERID,
    RECEIVERSTATUS,
    RECEIVERDEPTID,
    OPENDATE,
    OPENSTATUS,
    REJECTREASON,
    REJECTDATE,
    REJECTERID,
    CHARGECONFIRMSTATUS,
    CHARGEID,
    ACTIONID,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    RETRYCOUNT,
    SIGNERTYPE,
    ORGANID,
    PERMITTERPARTICIPANTID,
    SENDMETHODTYPE,
    MANUALFLAG,
    RECEIVERPOSTSTATUS,
    FAILUREREASON
)
SELECT /*+ PARALLEL(MS, 16) PARALLEL(K, 16) */
    -- 1) 발송ID 및 결재ID (인라인 채번: 결재ID 17자리 + 순번 3자리)
    SUBSTR(K.APPRID, 1, 17) || LPAD(ROW_NUMBER() OVER (
        PARTITION BY MS.DOC_ID 
        ORDER BY MS.SEND_SEQ, MS.RECEIVER_SEQ
    ), 3, '0')                                                              AS SENDID,
    K.APPRID                                                                AS APPRID,
    TRIM(REPLACE(REPLACE(MS.DOC_NUM, CHR(13), ''), CHR(10), ''))           AS DOCNO,
    NVL(MS.SENDER_DEPT_NAME, '미지정부서')                                  AS SENDDEPTNAME,
    NVL(TRIM(REPLACE(REPLACE(MS.TITLE, CHR(13), ''), CHR(10), '')), '제목 없음') AS TITLE,
    NVL(MS.RECEIVER_TYPE, '1')                                              AS RECEIVERTYPE,
    TRIM(REPLACE(REPLACE(MS.RECEIVE_NAME, CHR(13), ''), CHR(10), ''))       AS RECEIVERNAME,
    NVL(MS.SEND_TYPE, '0')                                                  AS SENDFLAG,
    NVL(MS.SEND_DATE, SYSDATE)                                              AS SENDDATE,
    NVL(MS.SEND_STATUS, '2')                                                AS SENDSTATUS,
    MS.SENDER_NAME                                                          AS SENDERNAME,

    -- 2) 발송자/수신자 ID 매핑 (퇴직자 포함 매핑 보장, 결측 시 '000000000' 방어)
    NVL(UG_SENDER.USER_ID, '000000000')                                     AS SENDERID,
    MS.SENDER_DEPT_NAME                                                     AS SENDERDEPTNAME,
    NVL(DG_SENDER.DEPT_ID, '000000000')                                     AS SENDERDEPTID,
    '0'                                                                     AS CHARGECONFIRMFLAG,
    1                                                                       AS SUBSEQ,

    -- 3) 상위 발송ID (최초 발송은 자신의 SENDID 참조)
    SUBSTR(K.APPRID, 1, 17) || LPAD(ROW_NUMBER() OVER (
        PARTITION BY MS.DOC_ID 
        ORDER BY MS.SEND_SEQ, MS.RECEIVER_SEQ
    ), 3, '0')                                                              AS PARSENDID,
    0                                                                       AS PARRECEIVERSEQ,
    NVL(MS.RECEIVER_SEQ, 1)                                                 AS RECEIVERSEQ,
    NVL(UG_RECV.USER_ID, '000000000')                                       AS RECEIVERID,
    NVL(MS.RECEIVE_STATUS, '2')                                             AS RECEIVERSTATUS,
    NVL(DG_RECV.DEPT_ID, '000000000')                                       AS RECEIVERDEPTID,
    MS.OPEN_DATE                                                            AS OPENDATE,
    NVL(MS.OPEN_STATUS, '0')                                                AS OPENSTATUS,
    NULL                                                                    AS REJECTREASON,
    NULL                                                                    AS REJECTDATE,

    -- 4) 누락 방어된 7개 핸디 10.x 필수 컬럼
    '000000000'                                                             AS REJECTERID,
    '0'                                                                     AS CHARGECONFIRMSTATUS,
    '000000000'                                                             AS CHARGEID,
    '000000000'                                                             AS ACTIONID,
    NVL(MS.SEND_DATE, SYSDATE)                                              AS REGISTDATE,
    NVL(UG_SENDER.USER_ID, '000000000')                                     AS REGISTERID,
    NVL(MS.SEND_DATE, SYSDATE)                                              AS UPDATEDATE,
    NVL(UG_SENDER.USER_ID, '000000000')                                     AS UPDATERID,
    0                                                                       AS RETRYCOUNT,

    -- 5) 수신/발송 메타
    '0'                                                                     AS SIGNERTYPE,
    NULL                                                                    AS ORGANID,
    '00000000000000000000'                                                 AS PERMITTERPARTICIPANTID,
    '0'                                                                     AS SENDMETHODTYPE,
    '0'                                                                     AS MANUALFLAG,
    '0'                                                                     AS RECEIVERPOSTSTATUS,
    NULL                                                                    AS FAILUREREASON

FROM MIG1_USER.MG_SEND MS

-- 1) 고속 조인: 채번 키 획득
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON MS.DOC_ID = K.DOC_ID

-- 2) 발송자 조직도 매핑 (퇴직자 포함 매핑 보장)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_SENDER
  ON UG_SENDER.EMP_CODE = SUBSTR(MS.SENDER_ID, 3, 6)

-- 3) 발송부서 조직도 매핑 (폐지부서 포함 매핑 보장)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_SENDER
  ON DG_SENDER.DEPT_CODE = MS.SENDER_DEPT_ID

-- 4) 수신자 조직도 매핑 (퇴직자 포함 매핑 보장)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_RECV
  ON UG_RECV.EMP_CODE = SUBSTR(MS.RECEIVER_ID, 3, 6)

-- 5) 수신부서 조직도 매핑 (폐지부서 포함 매핑 보장)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_RECV
  ON DG_RECV.DEPT_CODE = MS.RECEIVE_DEPT_ID
;

COMMIT;
