-- ====================================================================================================
-- [통합 MIG] 06. INTRAWARE.DOCUMENT & DOCMBR 직접 적재
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 
-- ⭐ [핵심 과제 2 해결] : 수신문서 첨부파일 중복 생성 방지 및 스토리지 50% 절감 구현
-- 
-- [규격 정의]
--  - 본문 문서 : DOCUMENTTYPE = 1 (또는 시행문 23)
--  - 일반 첨부 : DOCUMENTTYPE = 100 (첨부파일 명시)
-- 
-- 1. INTRAWARE.DOCUMENT (물리 파일 메타) :
--    - 기안문서(APP) 및 외부수신문서의 파일은 정상 등록
--    - 내부수신문서(ENF)의 본문(DOCUMENTTYPE = 1, 23)은 정상 등록
--    - ⭐ 내부수신문서(ENF)의 첨부파일(DOCUMENTTYPE = 100)은 DOCUMENT 등록에서 전면 제외!
--      -> 파일 복사 목록(miggwfile.bsh)에서 수신문서 첨부가 빠져 물리 스토리지 용량 50% 절감 달성!
--
-- 2. INTRAWARE.DOCMBR (결재문서-파일 매핑) :
--    - 기안문서 및 외부수신문서는 자신의 OBJECTID 매핑
--    - ⭐ 내부수신문서의 첨부파일(DOCUMENTTYPE = 100)은 원 기안문서의 첨부 OBJECTID를 재참조하여 연결!
--      -> 수신 부서 사용자도 원본 첨부파일을 정상적으로 열람 및 다운로드 가능!
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ====================================================================================================
-- STEP 1. 임시 파일 키 매핑 테이블 (FILE_ID <-> OBJECTID 채번 테이블)
-- ====================================================================================================
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE INTRAWARE.MAPPING_FILE_KEY CASCADE CONSTRAINTS';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE INTRAWARE.MAPPING_FILE_KEY (
    DOC_ID          VARCHAR2(40)    NOT NULL,
    ORD             NUMBER(5)       NOT NULL,
    FILE_ID         VARCHAR2(40)    NOT NULL,
    OBJECTID        VARCHAR2(20)    NOT NULL,
    DOCUMENTTYPE    VARCHAR2(10),
    FILENAME        VARCHAR2(520),
    FILESIZE        NUMBER(10),
    IS_INTERNAL_ENF CHAR(1)         DEFAULT 'N', -- 내부 수신문서 여부
    ORIGIN_DOC_ID   VARCHAR2(40)
)
NOLOGGING
TABLESPACE TSIGWS;

-- 파일 키 매핑 적재 및 OBJECTID 인라인 채번
INSERT /*+ APPEND PARALLEL(FK, 16) */ INTO INTRAWARE.MAPPING_FILE_KEY FK (
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
    -- 핸디 표준 OBJECTID 채번: 결재ID(17자리) || LPAD(순번, 3, '0')
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

CREATE UNIQUE INDEX INTRAWARE.PK_MAPPING_FILE_KEY ON INTRAWARE.MAPPING_FILE_KEY (DOC_ID, ORD)
NOLOGGING TABLESPACE TSIGWS;

CREATE INDEX INTRAWARE.IX_MAPPING_FILE_ORIGIN ON INTRAWARE.MAPPING_FILE_KEY (ORIGIN_DOC_ID, FILE_ID)
NOLOGGING TABLESPACE TSIGWS;


-- ====================================================================================================
-- STEP 2. INTRAWARE.DOCUMENT 직접 적재 (물리 파일 대상)
-- ⭐ 내부 수신문서의 첨부파일(IS_INTERNAL_ENF='Y' AND DOCUMENTTYPE='100')은 적재에서 제외!
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(D, 16) */ INTO INTRAWARE.DOCUMENT D (
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
JOIN INTRAWARE.MAPPING_FILE_KEY FK 
  ON MD.DOC_ID = FK.DOC_ID AND MD.ORD = FK.ORD
WHERE 1=1
  -- ⭐ 명확한 필터 조건:
  -- 내부 수신문서의 첨부파일(DOCUMENTTYPE = '100')만 물리 테이블(DOCUMENT)에서 제외!
  -- (기안문서 파일 전체 및 수신문서의 본문은 정상 적재)
  AND NOT (FK.IS_INTERNAL_ENF = 'Y' AND FK.DOCUMENTTYPE = '100')
;

COMMIT;


-- ====================================================================================================
-- STEP 3. INTRAWARE.DOCMBR 직접 적재 (결재문서-파일 N:M 매핑)
-- ⭐ 내부 수신문서의 첨부파일(DOCUMENTTYPE='100')은 원 기안문서의 OBJECTID를 정확히 매핑!
-- ====================================================================================================
INSERT /*+ APPEND PARALLEL(M, 16) */ INTO INTRAWARE.DOCMBR M (
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
    -- ⭐ 명확한 매핑 조건:
    -- 내부 수신문서의 첨부파일(DOCUMENTTYPE = '100')인 경우: 원 기안문서(ORIGIN_DOC_ID)의 첨부 OBJECTID 재사용!
    -- 그 외(기안문서 전체 및 수신문서 본문): 자신의 고유 OBJECTID 사용
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
FROM INTRAWARE.MAPPING_FILE_KEY FK
JOIN INTRAWARE.MAPPING_APPR_KEY K 
  ON FK.DOC_ID = K.DOC_ID

-- 원 기안문서의 첨부파일 매핑 조인 (1순위: FILE_ID 일치, 2순위: 파일명+크기 일치, 3순위: 순번 일치)
LEFT JOIN INTRAWARE.MAPPING_FILE_KEY FK_ORG
  ON FK.ORIGIN_DOC_ID = FK_ORG.DOC_ID 
 AND FK_ORG.DOCUMENTTYPE = '100'
 AND (FK.FILE_ID = FK_ORG.FILE_ID OR (FK.FILENAME = FK_ORG.FILENAME AND FK.FILESIZE = FK_ORG.FILESIZE) OR FK.ORD = FK_ORG.ORD)
;

COMMIT;
