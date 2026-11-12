-- ====================================================================================================
-- [테스트 환경] 02. INTRAWARE.APPROVAL_TEST 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 운영 APPROVAL 테이블 대신 APPROVAL_TEST 테이블로 결재 문서를 검증 적재합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(A, 16) */ INTO INTRAWARE.APPROVAL_TEST A (
    APPRID,
    WORDTYPE,
    FORMTYPE,
    FORMNAME,
    FORMVERSION,
    REGNO,
    REGDATE,
    DOCNO,
    APPRSTATUS,
    SECURITYLEVEL,
    KEEPPERIOD,
    TITLE,
    DEPTNAME,
    DRAFTERID,
    DRAFTERNAME,
    DRAFTDATE,
    LASTSANCDATE,
    DRAFTERDEPTNAME,
    MODRECORDNO,
    MODRECORDCOMMENT,
    REGTYPE,
    SANCDOCATTACHCNT,
    TEMPORARYFLAG,
    ATTACHSECURITYLEVEL,
    ATTACHSEPARATEFLAG,
    DELFLAG,
    SANCSERIALNO,
    PROPOSALCOUNT,
    RESERVEDFLAG,
    BODYPASSFLAG,
    SANCPASSFLAG,
    SANCPASSSIGNERNAME,
    SANCPASSSIGNERID,
    SANCPASSSIGNDATE,
    COMPLYPASSFLAG,
    POSTSTATUS,
    OPINIONFLAG,
    AUTOFLAG,
    SPECIALAUDITFLAG,
    SANCPERSONALINFOCNT,
    ENFORCEMENTATTACHCNT,
    PERSONALINFOCOUNT,
    PREVIEWTYPE,
    DRAFTERSANCLEVEL,
    SPAMFLAG,
    COMPLIANCENO,
    DEPTID,
    DRAFTERDEPTID,
    ORGDRAFTERDEPTID,
    LASTSIGNERDEPTID,
    ENFORCEFLAG,
    SENDERNAME,
    RECIEVENAME,
    SUMMARY,
    EMERGENCYLEVEL,
    AUDITFLAG,
    RECIEVETYPE,
    DOCSTATUS,
    DOCATTR,
    PUBLICATIONTYPE,
    PUBLICATIONSTATUS,
    PUBLICATIONLIMITTERM,
    SENDDEPTNAME,
    PROPOSALNO,
    MODIFYFLAG,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    DOCID,
    ORGAPPRID,
    BODYCOUNT,
    BODYATTACHFLAG,
    CHARGERID,
    SUBSEQ,
    PARENTAPPRID,
    VIEWRESTRICTTYPE,
    EXTRADOCATTR,
    DOCNUMBERSTATUS,
    ENFORCEMENTFLAG,
    PASSFLAG,
    OPENLIMITDATE,
    DRAFTERPOSITIONNAME,
    SENDFLAG,
    SENDDATE,
    POSTFLAG,
    SENDMETHODTYPE,
    VIEWRANGETYPE,
    DRAFTSRCTYPE,
    UNRECEIVERCNT
)
SELECT /*+ PARALLEL(MA, 16) PARALLEL(K, 16) */
    -- 1) 고유 식별자 및 서식
    K.APPRID                                                                AS APPRID,
    5                                                                       AS WORDTYPE,      -- 웹기안기 순수 HWP
    5                                                                       AS FORMTYPE,
    NVL(MA.FORM_NAME, '기본양식')                                           AS FORMNAME,
    NVL(MA.FORM_VER, 1)                                                     AS FORMVERSION,

    -- 2) 등록번호 및 일자
    NVL(LPAD(TO_CHAR(K.REG_SEQ), 6, '0'), '000000')                         AS REGNO,
    NVL(MA.APPROVALDATE, MA.DRAFT_DATE)                                     AS REGDATE,
    TRIM(REPLACE(REPLACE(MA.DOC_NUM, CHR(13), ''), CHR(10), ''))           AS DOCNO,
    MA.DOC_STATUS                                                           AS APPRSTATUS,
    NVL(MA.SECURITY_LEVEL, '0')                                             AS SECURITYLEVEL,
    NVL(MA.KEEP_PERIOD, '03')                                               AS KEEPPERIOD,

    -- 3) 문서 제목 및 기안자 정보
    NVL(TRIM(REPLACE(REPLACE(MA.TITLE, CHR(13), ''), CHR(10), '')), '제목 없음') AS TITLE,
    NVL(MA.DRAFT_DEPT_NAME, '미지정부서')                                    AS DEPTNAME,
    NVL(UG_DRAFTER.USER_ID, '000000000')                                    AS DRAFTERID,
    MA.DRAFTER_NAME                                                         AS DRAFTERNAME,
    MA.DRAFT_DATE                                                           AS DRAFTDATE,
    NVL(MA.APPROVALDATE, MA.DRAFT_DATE)                                     AS LASTSANCDATE,
    MA.DRAFT_DEPT_NAME                                                      AS DRAFTERDEPTNAME,
    0                                                                       AS MODRECORDNO,
    NULL                                                                    AS MODRECORDCOMMENT,

    -- 4) 문서 등록구분 및 첨부 플래그
    CASE 
        WHEN K.DOC_TYPE = 'P' THEN '1'
        WHEN K.DOC_TYPE = 'E' THEN '2'
        ELSE '1' 
    END                                                                     AS REGTYPE,
    NVL(MA.ATTACH_CNT, 0)                                                   AS SANCDOCATTACHCNT,
    '0'                                                                     AS TEMPORARYFLAG,
    '99'                                                                    AS ATTACHSECURITYLEVEL,
    '0'                                                                     AS ATTACHSEPARATEFLAG,
    NVL(MA.IS_DELETED, '0')                                                 AS DELFLAG,
    0                                                                       AS SANCSERIALNO,
    1                                                                       AS PROPOSALCOUNT,
    '0'                                                                     AS RESERVEDFLAG,
    '0'                                                                     AS BODYPASSFLAG,
    '0'                                                                     AS SANCPASSFLAG,
    NULL                                                                    AS SANCPASSSIGNERNAME,
    '000000000'                                                             AS SANCPASSSIGNERID,
    NULL                                                                    AS SANCPASSSIGNDATE,
    '0'                                                                     AS COMPLYPASSFLAG,
    NVL(MA.POST_STATUS, '0')                                                AS POSTSTATUS,
    NVL(MA.IS_OPINION, '0')                                                 AS OPINIONFLAG,
    '0'                                                                     AS AUTOFLAG,
    '0'                                                                     AS SPECIALAUDITFLAG,
    0                                                                       AS SANCPERSONALINFOCNT,
    0                                                                       AS ENFORCEMENTATTACHCNT,
    0                                                                       AS PERSONALINFOCOUNT,
    '0'                                                                     AS PREVIEWTYPE,
    '0'                                                                     AS DRAFTERSANCLEVEL,
    '0'                                                                     AS SPAMFLAG,
    NULL                                                                    AS COMPLIANCENO,

    -- 5) 부서 ID 매핑 (퇴직/폐지부서 고려, 결측 시 '000000000' 방어)
    NVL(DG_DRAFT.DEPT_ID, '000000000')                                      AS DEPTID,
    NVL(DG_DRAFT.DEPT_ID, '000000000')                                      AS DRAFTERDEPTID,
    NVL(DG_DRAFT.DEPT_ID, '000000000')                                      AS ORGDRAFTERDEPTID,
    NVL(DG_LAST.DEPT_ID, NVL(DG_DRAFT.DEPT_ID, '000000000'))                AS LASTSIGNERDEPTID,

    -- 6) 시행/발송/수신 정보
    NVL(MA.ENFORCE_FLAG, '0')                                               AS ENFORCEFLAG,
    TRIM(REPLACE(REPLACE(MA.SENDER_NAME, CHR(13), ''), CHR(10), ''))        AS SENDERNAME,
    TRIM(REPLACE(REPLACE(MA.RECEIVE_NAME, CHR(13), ''), CHR(10), ''))       AS RECIEVENAME,
    NULL                                                                    AS SUMMARY,
    NVL(MA.EMERGENCY_LEVEL, '0')                                            AS EMERGENCYLEVEL,
    '0'                                                                     AS AUDITFLAG,
    '0'                                                                     AS RECIEVETYPE,
    NVL(MA.DOC_STATUS, '0')                                                 AS DOCSTATUS,

    -- 7) 핸디 10.x 표준 80자리 DOCATTR 비트마스크
    RPAD(
        SUBSTR(NVL(MA.ELECTRONIC_SIGN_FLAG, '1'), 1, 1) ||
        SUBSTR(NVL(MA.SEND_TYPE, '0'), 1, 1) ||
        SUBSTR(NVL(MA.ATTACH_CNT, 0), 1, 2) ||
        '0000000000000000000000000000000000000000000000000000000000000000000000000000',
        80,
        '0'
    )                                                                       AS DOCATTR,

    NVL(MA.PUBLIC_LEVEL, '1')                                               AS PUBLICATIONTYPE,
    '0'                                                                     AS PUBLICATIONSTATUS,
    NULL                                                                    AS PUBLICATIONLIMITTERM,
    MA.DRAFT_DEPT_NAME                                                      AS SENDDEPTNAME,
    1                                                                       AS PROPOSALNO,
    '0'                                                                     AS MODIFYFLAG,
    NVL(MA.REG_DATE, MA.DRAFT_DATE)                                         AS REGISTDATE,
    NVL(UG_DRAFTER.USER_ID, '000000000')                                    AS REGISTERID,
    NVL(MA.APPROVALDATE, SYSDATE)                                           AS UPDATEDATE,
    NVL(UG_LAST.USER_ID, '000000000')                                       AS UPDATERID,
    MA.DOC_ID                                                               AS DOCID,

    -- 8) 원문서 링크 매핑 (재배포/접수 문서)
    NVL(K_ORG.APPRID, '00000000000000000000')                               AS ORGAPPRID,

    1                                                                       AS BODYCOUNT,
    '0'                                                                     AS BODYATTACHFLAG,
    '000000000'                                                             AS CHARGERID,
    1                                                                       AS SUBSEQ,
    '00000000000000000000'                                                 AS PARENTAPPRID,
    '0'                                                                     AS VIEWRESTRICTTYPE,
    '00000000000000000000000000000000000000000000000000'                    AS EXTRADOCATTR,
    '0'                                                                     AS DOCNUMBERSTATUS,
    NVL(MA.ENFORCE_FLAG, '0')                                               AS ENFORCEMENTFLAG,
    '0'                                                                     AS PASSFLAG,
    NULL                                                                    AS OPENLIMITDATE,
    MA.DRAFTER_POS                                                          AS DRAFTERPOSITIONNAME,
    NVL(MA.SEND_TYPE, '0')                                                  AS SENDFLAG,
    MA.SEND_DATE                                                            AS SENDDATE,
    NVL(MA.POST_STATUS, '0')                                                AS POSTFLAG,
    '0'                                                                     AS SENDMETHODTYPE,
    '0'                                                                     AS VIEWRANGETYPE,
    '0'                                                                     AS DRAFTSRCTYPE,
    0                                                                       AS UNRECEIVERCNT

FROM MIG1_USER.MG_APPROVAL MA

-- 1) 고속 조인: 채번 키 획득
JOIN INTRAWARE.MAPPING_APPR_KEY K
  ON MA.DOC_ID = K.DOC_ID

-- 2) 원문서 매핑 조인
LEFT JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG
  ON K.ORIGIN_DOC_ID = K_ORG.DOC_ID

-- 3) 기안자 조직도 매핑 (퇴직자 포함 매핑 보장)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_DRAFTER
  ON UG_DRAFTER.EMP_CODE = SUBSTR(MA.DRAFTERID, 3, 6)

-- 4) 최종결재자 조직도 매핑 (퇴직자 포함 매핑 보장)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_LAST
  ON UG_LAST.EMP_CODE = SUBSTR(MA.LASTSIGNERID, 3, 6)

-- 5) 부서 조직도 매핑 (폐지부서 포함 매핑 보장)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_DRAFT
  ON DG_DRAFT.DEPT_CODE = MA.DRAFT_DEPT_ID

LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_LAST
  ON DG_LAST.DEPT_CODE = MA.LAST_SIGN_DEPT_ID
;

COMMIT;
