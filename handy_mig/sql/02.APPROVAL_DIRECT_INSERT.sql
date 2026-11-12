-- ====================================================================================================
-- [통합 MIG] 02. INTRAWARE.APPROVAL 직접 적재 (One-Pass Direct Path Insert)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 중간 테이블(MG_APPROVAL) 적재 및 PL/SQL 루프 UPDATE를 전면 배제하고,
--        원천 데이터에서 운영 테이블(INTRAWARE.APPROVAL)로 직접 고속 적재합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- 1. 키 매핑 테이블에 대상 문서 및 APPRID 사전 확정 적재
-- (이미 채번되어 있는 MIG1_USER.MG_APPROVAL 활용 또는 인라인 채번)
TRUNCATE TABLE INTRAWARE.MG_APPR_KEY;

INSERT /*+ APPEND PARALLEL(K, 8) */ INTO INTRAWARE.MG_APPR_KEY K (
    DOC_ID,
    ORIGIN_DOC_ID,
    APPRID,
    DOC_TYPE,
    DRAFTDATE,
    APPROVALDATE,
    COMP_ID
)
SELECT 
    MA.DOC_ID,
    MA.ORIGIN_DOC_ID,
    NVL(MA.HANDY_ID, 
        'ACUBE' || TO_CHAR(MA.DRAFTDATE, 'YY') || TO_CHAR(MA.DRAFTDATE, 'DDD')
        || LPAD(ROW_NUMBER() OVER (PARTITION BY TO_CHAR(MA.DRAFTDATE, 'YYYY') ORDER BY MA.DRAFTDATE, MA.DOC_ID), 7, '0') 
        || '000'
    ) AS APPRID,
    CASE WHEN MA.DOCATTR IN ('4', '5') THEN 'E' ELSE 'A' END AS DOC_TYPE,
    MA.DRAFTDATE,
    MA.APPROVALDATE,
    'B551202' AS COMP_ID
FROM MIG1_USER.MG_APPROVAL MA;

COMMIT;

-- 2. 운영 테이블(INTRAWARE.APPROVAL) Direct Path Insert
-- Self-Join(원문서 매핑) 및 사번/부서코드 변환을 단 1회의 SQL로 처리
INSERT /*+ APPEND PARALLEL(A, 16) */ INTO INTRAWARE.APPROVAL A (
    APPRID,
    ORGAPPRID,
    REJECTEDAPPRID,
    REGNO,
    DOCREGNO,
    TITLE,
    FORMID,
    FORMNAME,
    FORMTYPE,
    DRAFTDATE,
    DRAFTERID,
    DRAFTERNAME,
    DRAFTDEPTID,
    DRAFTDEPTNAME,
    ORGDRAFTERID,
    ORGDRAFTERNAME,
    ORGDRAFTDEPTID,
    ORGDRAFTDEPTNAME,
    ORGREGNO,
    URGENTFLAG,
    DOCATTR,
    EXTERNALDOCTYPE,
    ELECTRONICDOCFLAG,
    SAVEDEPTID,
    APPROVALDATE,
    APPROVALTYPE,
    WORDTYPE,
    APPROVALSTATUS,
    LASTSIGNERID,
    LASTSIGNERNAME,
    ENFORCEDATE,
    SENDDATE,
    PAGECNT,
    DRAFTSRCTYPE,
    REGTYPE,
    SPECIALDOC,
    PUBLICATIONTYPE,
    PUBLICATIONFLAG,
    VIEWRANGETYPE,
    VIEWRESTRICTTYPE,
    SECURITYEXPIREDATE,
    PASSWORDFLAG,
    ATTACHCNT,
    MODIFYFLAG,
    REJECTFLAG,
    INDEXDATE,
    NUMATTR,
    RECEIVERS,
    SENDID,
    PARAPPRID,
    KMSFLAG,
    INTERNALOPENSTATUS,
    CONTENTNO,
    RELATIONAPPRID,
    RELATIONTYPE,
    EXCHANGEID,
    DRMFLAG,
    POSTSTATUS,
    SENDMETHODTYPE,
    UNRECEIVERCNT,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    DRAFTERDEPTID,
    ORGDRAFTERDEPTID,
    LASTSIGNERDEPTID,
    CHARGERID,
    CHARGERDEPTID,
    KEEPPERIOD,
    SECURITYLEVEL,
    AUDITTYPE,
    EDMSFLAG,
    FOLDERID,
    AUDITSTATUS,
    RETURNDUEDATE,
    DOCTYPE,
    DOCREGSTATUS,
    FILINGDATE,
    DETACHEDDOCNO,
    ORGDEPTFOLDERID,
    ORGUSERFOLDERID,
    PERSONALINFOCOUNT,
    PREVIEWTYPE,
    DRAFTERSANCLEVEL,
    OPENSTARTDATE,
    BPMWORK,
    ATTACHSECURITYLEVEL,
    SPAMFLAG,
    COMPLIANCENO
)
SELECT /*+ PARALLEL(MA, 16) */
    -- 1) 결재ID 및 원문서 결재ID (인라인 조인으로 즉시 확정)
    K.APPRID                                                                AS APPRID,
    NVL(K_ORG.APPRID, '00000000000000000000')                              AS ORGAPPRID,
    '00000000000000000000'                                                  AS REJECTEDAPPRID,

    -- 2) 등록번호 및 문서번호
    NVL(DG_DRAFT.DEPT_CODE, '00000') || LPAD(NVL(MA.REGNO, '0'), 6, '0')    AS REGNO,
    MA.DOCREGNO                                                             AS DOCREGNO,
    SUBSTRB(REPLACE(REPLACE(MA.TITLE, CHR(13), ''), CHR(10), ''), 1, 300)   AS TITLE,

    -- 3) 서식 및 기안정보
    '00000000000000000000'                                                  AS FORMID,
    MA.FORMNAME                                                             AS FORMNAME,
    '5'                                                                     AS FORMTYPE, -- 서식유형 (순수웹한글 기본)
    NVL(MA.DRAFTDATE, SYSDATE)                                              AS DRAFTDATE,
    
    -- 기안자/부서 (사번 매핑 및 부서ID 변환)
    NVL(UG_DRAFT.USER_ID, '000000000')                                      AS DRAFTERID,
    MA.DRAFTERNAME                                                          AS DRAFTERNAME,
    NVL(DG_DRAFT.DEPT_ID, '000000000')                                      AS DRAFTDEPTID,
    MA.DRAFTDEPTNAME                                                        AS DRAFTDEPTNAME,

    -- 원기안자/원기안부서
    NVL(UG_ORGDRAFT.USER_ID, '000000000')                                   AS ORGDRAFTERID,
    MA.ORGDRAFTERNAME                                                       AS ORGDRAFTERNAME,
    NVL(DG_ORGDRAFT.DEPT_ID, '000000000')                                   AS ORGDRAFTDEPTID,
    MA.ORGDRAFTDEPTNAME                                                     AS ORGDRAFTDEPTNAME,
    NULL                                                                    AS ORGREGNO,

    -- 4) 문서 상태 및 속성
    CASE WHEN MA.URGENTFLAG = 'Y' THEN '1' 
         WHEN MA.URGENTFLAG = 'N' THEN '0' 
         ELSE NVL(MA.URGENTFLAG, '0') END                                   AS URGENTFLAG,
    
    -- [DOCATTR] 핸디 80자리 고정 속성 비트마스크 변환
    CASE WHEN MA.DOCATTR = '1' THEN '00000000000000000000000000000000000000000000000000001100000000000000000000000000'
         WHEN MA.DOCATTR = '2' THEN '00000100000000000000000000000000000000000000000000001100000000000000000000000000'
         WHEN MA.DOCATTR = '3' THEN '00000200000000000000000000000000000000000000000000001100000000000000000000000000'
         WHEN MA.DOCATTR = '4' THEN '00000000000000000000000000000000000000000000000000001100000000000000000000000000'
         WHEN MA.DOCATTR = '5' THEN '00000200000000000000000000000000000000000000000000001100000000000000000000000000'
         ELSE '00000000000000000000000000000000000000000000000000001100000000000000000000000000' END AS DOCATTR,

    CASE WHEN MA.EXTERNALDOCTYPE = 'Y' THEN '0'
         WHEN MA.EXTERNALDOCTYPE = 'N' THEN '1'
         ELSE NVL(MA.EXTERNALDOCTYPE, '0') END                              AS EXTERNALDOCTYPE,
    
    CASE WHEN MA.ELECTRONICDOCFLAG = 'Y' THEN '1' 
         WHEN MA.ELECTRONICDOCFLAG = 'N' THEN '0' 
         ELSE NVL(MA.ELECTRONICDOCFLAG, '1') END                            AS ELECTRONICDOCFLAG,
    NVL(DG_SAVE.DEPT_ID, '000000000')                                       AS SAVEDEPTID,
    MA.APPROVALDATE                                                         AS APPROVALDATE,
    NVL(MA.APPROVALTYPE, 0)                                                 AS APPROVALTYPE,
    '5'                                                                     AS WORDTYPE, -- 순수웹한글
    MA.APPROVALSTATUS                                                       AS APPROVALSTATUS,

    -- 최종결재자
    NVL(UG_LAST.USER_ID, '000000000')                                       AS LASTSIGNERID,
    MA.LASTSIGNERNAME                                                       AS LASTSIGNERNAME,
    MA.ENFORCEDATE                                                          AS ENFORCEDATE,
    MA.SENDDATE                                                             AS SENDDATE,
    NVL(MA.PAGECNT, 1)                                                      AS PAGECNT,
    '0'                                                                     AS DRAFTSRCTYPE,
    '0'                                                                     AS REGTYPE,
    MA.SPECIALDOC                                                           AS SPECIALDOC,
    MA.PUBLICATIONTYPE                                                      AS PUBLICATIONTYPE,
    MA.PUBLICATIONFLAG                                                      AS PUBLICATIONFLAG,
    DECODE(MA.VIEWRANGETYPE, '9', '0', NVL(MA.VIEWRANGETYPE, '0'))          AS VIEWRANGETYPE,
    NVL(MA.VIEWRESTRICTTYPE, '0')                                           AS VIEWRESTRICTTYPE,
    MA.SECURITYEXPIREDATE                                                   AS SECURITYEXPIREDATE,
    CASE WHEN MA.PASSWORDFLAG = 'Y' THEN '1' 
         WHEN MA.PASSWORDFLAG = 'N' THEN '0' 
         ELSE NVL(MA.PASSWORDFLAG, '0') END                                 AS PASSWORDFLAG,
    NVL(MA.ATTACHCNT, 0)                                                    AS ATTACHCNT,
    NVL(MA.MODIFYFLAG, '0')                                                 AS MODIFYFLAG,
    NVL(MA.REJECTFLAG, '0')                                                 AS REJECTFLAG,
    MA.INDEXDATE                                                            AS INDEXDATE,
    MA.NUMATTR                                                              AS NUMATTR,

    -- 5) 수신처 (최대 6000자 초과 방지)
    SUBSTR(MA.RECEIVERS, 1, 6000)                                           AS RECEIVERS,
    '00000000000000000000'                                                  AS SENDID,
    '00000000000000000000'                                                  AS PARAPPRID,
    '0'                                                                     AS KMSFLAG,
    '0'                                                                     AS INTERNALOPENSTATUS,
    0                                                                       AS CONTENTNO,
    '00000000000000000000'                                                  AS RELATIONAPPRID,
    '0'                                                                     AS RELATIONTYPE,
    '00000000000000000000'                                                  AS EXCHANGEID,
    '0'                                                                     AS DRMFLAG,
    '0'                                                                     AS POSTSTATUS,
    '1'                                                                     AS SENDMETHODTYPE,
    NVL(MA.UNRECEIVERCNT, 0)                                                AS UNRECEIVERCNT,
    NVL(MA.REGISTDATE, SYSDATE)                                             AS REGISTDATE,
    NVL(UG_REG.USER_ID, '000000000')                                        AS REGISTERID,
    MA.UPDATEDATE                                                           AS UPDATEDATE,
    '000000000'                                                             AS UPDATERID,
    NVL(DG_DRAFT.DEPT_ID, '000000000')                                      AS DRAFTERDEPTID,
    NVL(DG_ORGDRAFT.DEPT_ID, '000000000')                                   AS ORGDRAFTERDEPTID,
    NVL(DG_LAST.DEPT_ID, '000000000')                                       AS LASTSIGNERDEPTID,
    '000000000'                                                             AS CHARGERID,
    '000000000'                                                             AS CHARGERDEPTID,
    MA.KEEPPERIOD                                                           AS KEEPPERIOD,
    MA.SECURITYLEVEL                                                        AS SECURITYLEVEL,
    MA.AUDITTYPE                                                            AS AUDITTYPE,
    '0'                                                                     AS EDMSFLAG,

    -- 6) 편철 및 분류정보
    SUBSTR(MA.FOLDERID, 1, 40)                                              AS FOLDERID,
    '0'                                                                     AS AUDITSTATUS,
    NULL                                                                    AS RETURNDUEDATE,
    NVL(MA.DOCTYPE, '0')                                                    AS DOCTYPE,
    '0'                                                                     AS DOCREGSTATUS,
    CASE WHEN MA.FILINGDATE IS NOT NULL 
         THEN TO_DATE(SUBSTR(MA.FILINGDATE, 1, 4) || '-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS')
         ELSE NULL END                                                      AS FILINGDATE,
    MA.DETACHEDDOCNO                                                        AS DETACHEDDOCNO,
    '00000000000000000000'                                                  AS ORGDEPTFOLDERID,
    '00000000000000000000'                                                  AS ORGUSERFOLDERID,
    0                                                                       AS PERSONALINFOCOUNT,
    '0'                                                                     AS PREVIEWTYPE,
    '99'                                                                    AS DRAFTERSANCLEVEL,
    NULL                                                                    AS OPENSTARTDATE,
    '0'                                                                     AS BPMWORK,
    '99'                                                                    AS ATTACHSECURITYLEVEL,
    '0'                                                                     AS SPAMFLAG,
    '0'                                                                     AS COMPLIANCENO

FROM MIG1_USER.MG_APPROVAL MA

-- 1) 고속 인라인 조인: APPRID 확정 및 원문서 APPRID 즉시 매핑
JOIN INTRAWARE.MG_APPR_KEY K 
  ON MA.DOC_ID = K.DOC_ID

LEFT JOIN INTRAWARE.MG_APPR_KEY K_ORG 
  ON MA.ORIGIN_DOC_ID = K_ORG.DOC_ID

-- 2) 조직도 사용자 매핑 (사번 기준 매핑: 재직자뿐만 아니라 이관된 퇴사자까지 포괄)
LEFT JOIN INTRAWARE.USR_GLOBAL UG_DRAFT 
  ON UG_DRAFT.EMP_CODE = SUBSTR(MA.DRAFTERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_ORGDRAFT 
  ON UG_ORGDRAFT.EMP_CODE = SUBSTR(MA.ORGDRAFTERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_LAST 
  ON UG_LAST.EMP_CODE = SUBSTR(MA.LASTSIGNERID, 3, 6)

LEFT JOIN INTRAWARE.USR_GLOBAL UG_REG 
  ON UG_REG.EMP_CODE = SUBSTR(MA.REGISTERID, 3, 6)

-- 3) 조직도 부서 매핑 (부서코드 기준 매핑)
LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_DRAFT 
  ON DG_DRAFT.DEPT_CODE = MA.DRAFTDEPTID

LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_ORGDRAFT 
  ON DG_ORGDRAFT.DEPT_CODE = MA.ORGDRAFTDEPTID

LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_SAVE 
  ON DG_SAVE.DEPT_CODE = MA.SAVEDEPTID

LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_LAST 
  ON DG_LAST.DEPT_CODE = MA.LASTSIGNERDEPTID
;

COMMIT;
