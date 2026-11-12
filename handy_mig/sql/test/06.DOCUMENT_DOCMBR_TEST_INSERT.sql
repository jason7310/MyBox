-- ====================================================================================================
-- [테스트 환경] 06. INTRAWARE.DOCUMENT_TEST & DOCMBR_TEST 적재
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 운영 DOCUMENT, DOCMBR 대신 DOCUMENT_TEST, DOCMBR_TEST 테이블로 첨부 및 매핑을 검증 적재합니다.
--        (내부 수신문서 첨부 중복 제외 및 원본 참조 로직 동일 적용)
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ====================================================================================================
-- STEP 1. 테스트용 임시 파일 키 매핑 테이블
-- ====================================================================================================
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE INTRAWARE.MAPPING_FILE_KEY_TEST CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE INTRAWARE.MAPPING_FILE_KEY_TEST (
    DOC_ID          VARCHAR2(40)    NOT NULL,
    ORD             NUMBER(5)       NOT NULL,
    FILE_ID         VARCHAR2(40)    NOT NULL,
    OBJECTID        VARCHAR2(20)    NOT NULL,
    DOCUMENTTYPE    VARCHAR2(10),
    FILENAME        VARCHAR2(520),
    FILESIZE        NUMBER(10),
    IS_INTERNAL_ENF CHAR(1)         DEFAULT 'N',
    ORIGIN_DOC_ID   VARCHAR2(40)
)
NOLOGGING
TABLESPACE TSIGWS;

INSERT /*+ APPEND PARALLEL(FK, 16) */ INTO INTRAWARE.MAPPING_FILE_KEY_TEST FK (
    DOC_ID,
    ORD,
    FILE_ID,
    OBJECTID,
    DOCUMENTTYPE,
    FILENAME,
    FILESIZE,
    IS_INTERNAL_ENF,
    ORIGIN_DOC_ID
)
SELECT /*+ PARALLEL(MD, 16) PARALLEL(K, 16) */
    MD.DOC_ID,
    MD.ORD,
    MD.FILE_ID,
    SUBSTR(K.APPRID, 1, 17) || LPAD(MD.ORD, 3, '0')                         AS OBJECTID,
    MD.DOCUMENTTYPE,
    MD.FILENAME,
    MD.FILESIZE,
    CASE WHEN K.DOC_TYPE = 'E' AND K.ORIGIN_DOC_ID IS NOT NULL AND K_ORG.APPRID IS NOT NULL 
         THEN 'Y' ELSE 'N' END                                              AS IS_INTERNAL_ENF,
    K.ORIGIN_DOC_ID
FROM MIG1_USER.MG_DOCUMENT MD
JOIN INTRAWARE.MAPPING_APPR_KEY K 
  ON MD.DOC_ID = K.DOC_ID
LEFT JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG
  ON K.ORIGIN_DOC_ID = K_ORG.DOC_ID
;

COMMIT;

CREATE UNIQUE INDEX INTRAWARE.PK_MAP_FILE_KEY_TEST ON INTRAWARE.MAPPING_FILE_KEY_TEST (DOC_ID, ORD)
NOLOGGING TABLESPACE TSIGWS;

CREATE INDEX INTRAWARE.IX_MAP_FILE_ORG_TEST ON INTRAWARE.MAPPING_FILE_KEY_TEST (ORIGIN_DOC_ID, FILE_ID)
NOLOGGING TABLESPACE TSIGWS;


-- ====================================================================================================
-- STEP 2. INTRAWARE.DOCUMENT_TEST 직접 적재 (물리 파일 대상)
-- ⭐ 내부 수신문서 첨부파일(IS_INTERNAL_ENF='Y' AND DOCUMENTTYPE='100')은 제외!
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(D, 16) */ INTO INTRAWARE.DOCUMENT_TEST D (
    OBJECTID,
    OBJECTNAME,
    PAGECNT,
    FILENAME,
    FILESIZE,
    DOCUMENTTYPE,
    HASHCODE,
    OPENFLAG,
    PARTICIPANTID,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    REGISTERDEPTID,
    SRCOBJECTID
)
SELECT /*+ PARALLEL(MD, 16) PARALLEL(FK, 16) */
    FK.OBJECTID                                                             AS OBJECTID,
    NVL(MD.OBJECTNAME, MD.FILENAME)                                         AS OBJECTNAME,
    NVL(MD.PAGECNT, 1)                                                      AS PAGECNT,
    MD.FILENAME                                                             AS FILENAME,
    NVL(MD.FILESIZE, 0)                                                     AS FILESIZE,
    TO_NUMBER(MD.DOCUMENTTYPE)                                              AS DOCUMENTTYPE,
    MD.HASHCODE                                                             AS HASHCODE,
    NVL(MD.OPENFLAG, '1')                                                   AS OPENFLAG,
    NULL                                                                    AS PARTICIPANTID,
    NVL(MD.REGISTDATE, SYSDATE)                                             AS REGISTDATE,
    '000000000'                                                             AS REGISTERID,
    SYSDATE                                                                 AS UPDATEDATE,
    '000000000'                                                             AS UPDATERID,
    NULL                                                                    AS REGISTERDEPTID,
    MD.FILE_ID                                                              AS SRCOBJECTID
FROM MIG1_USER.MG_DOCUMENT MD
JOIN INTRAWARE.MAPPING_FILE_KEY_TEST FK 
  ON MD.DOC_ID = FK.DOC_ID AND MD.ORD = FK.ORD
WHERE 1=1
  AND NOT (FK.IS_INTERNAL_ENF = 'Y' AND FK.DOCUMENTTYPE = '100')
;

COMMIT;


-- ====================================================================================================
-- STEP 3. INTRAWARE.DOCMBR_TEST 직접 적재 (결재문서-파일 매핑)
-- ⭐ 내부 수신문서 첨부(DOCUMENTTYPE='100')는 원 기안문서 첨부 OBJECTID 재사용
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(M, 16) */ INTO INTRAWARE.DOCMBR_TEST M (
    APPRID,
    OBJECTID,
    OBJECTSEQ,
    DOCUMENTTYPE,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID,
    PARTICIPANTID
)
SELECT /*+ PARALLEL(FK, 16) PARALLEL(K, 16) */
    K.APPRID                                                                AS APPRID,
    CASE 
        WHEN FK.IS_INTERNAL_ENF = 'Y' AND FK.DOCUMENTTYPE = '100' AND FK_ORG.OBJECTID IS NOT NULL
        THEN FK_ORG.OBJECTID
        ELSE FK.OBJECTID
    END                                                                     AS OBJECTID,
    FK.ORD                                                                  AS OBJECTSEQ,
    TO_NUMBER(FK.DOCUMENTTYPE)                                              AS DOCUMENTTYPE,
    NVL(K.DRAFTDATE, SYSDATE)                                               AS REGISTDATE,
    '000000000'                                                             AS REGISTERID,
    SYSDATE                                                                 AS UPDATEDATE,
    '000000000'                                                             AS UPDATERID,
    NULL                                                                    AS PARTICIPANTID
FROM INTRAWARE.MAPPING_FILE_KEY_TEST FK
JOIN INTRAWARE.MAPPING_APPR_KEY K 
  ON FK.DOC_ID = K.DOC_ID
LEFT JOIN INTRAWARE.MAPPING_FILE_KEY_TEST FK_ORG
  ON FK.ORIGIN_DOC_ID = FK_ORG.DOC_ID 
 AND FK_ORG.DOCUMENTTYPE = '100'
 AND (FK.FILE_ID = FK_ORG.FILE_ID OR (FK.FILENAME = FK_ORG.FILENAME AND FK.FILESIZE = FK_ORG.FILESIZE) OR FK.ORD = FK_ORG.ORD)
;

COMMIT;
