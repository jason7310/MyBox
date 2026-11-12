-- ====================================================================================================
-- [통합 MIG] 07. 수신문서 중복 첨부파일 검출 및 DB 매핑 보정 SQL
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 원기안문서 첨부를 참조하지 않고 독자적으로 중복 생성된 수신문서 첨부(DOCUMENTTYPE=100)를 식별하고,
--        DOCMBR을 원기안 첨부 OBJECTID로 정상 연결한 뒤 중복 DOCUMENT 레코드를 정리합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DML;

-- ----------------------------------------------------------------------------------------------------
-- [검증 1] 중복 생성된 수신문서 첨부파일(DOCUMENTTYPE=100) 건수 및 용량 현황 조회
-- ----------------------------------------------------------------------------------------------------
SELECT 
    COUNT(*)                                            AS DUP_FILE_COUNT,
    ROUND(SUM(D_ENF.FILESIZE) / 1024 / 1024, 2)         AS TOTAL_DUP_SIZE_MB,
    ROUND(SUM(D_ENF.FILESIZE) / 1024 / 1024 / 1024, 2)  AS TOTAL_DUP_SIZE_GB
FROM INTRAWARE.MAPPING_APPR_KEY K_ENF
-- 1. 원기안문서 매핑
JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG
  ON K_ENF.ORIGIN_DOC_ID = K_ORG.DOC_ID
-- 2. 수신문서의 첨부파일 (DOCUMENTTYPE = 100 명시)
JOIN INTRAWARE.DOCMBR M_ENF
  ON K_ENF.APPRID = M_ENF.APPRID AND M_ENF.DOCUMENTTYPE = 100
JOIN INTRAWARE.DOCUMENT D_ENF
  ON M_ENF.OBJECTID = D_ENF.OBJECTID
-- 3. 원기안문서의 동일 첨부파일 (DOCUMENTTYPE = 100 명시)
JOIN INTRAWARE.DOCMBR M_ORG
  ON K_ORG.APPRID = M_ORG.APPRID AND M_ORG.DOCUMENTTYPE = 100
JOIN INTRAWARE.DOCUMENT D_ORG
  ON M_ORG.OBJECTID = D_ORG.OBJECTID
 AND (D_ENF.FILENAME = D_ORG.FILENAME AND D_ENF.FILESIZE = D_ORG.FILESIZE)
-- 4. 중복 조건 : 수신문서 첨부가 원기안 첨부의 OBJECTID를 가리키지 않고 별도 OBJECTID를 가진 경우!
WHERE K_ENF.DOC_TYPE = 'E'
  AND M_ENF.OBJECTID <> M_ORG.OBJECTID;


-- ----------------------------------------------------------------------------------------------------
-- [보정 1] 수신문서 첨부의 DOCMBR 매핑을 원기안문서의 첨부 OBJECTID로 정상 전환 (재연결)
-- ----------------------------------------------------------------------------------------------------
MERGE /*+ PARALLEL(M_ENF, 16) */ INTO INTRAWARE.DOCMBR M_ENF
USING (
    SELECT 
        K_ENF.APPRID        AS ENF_APPRID,
        M_ENF.OBJECTID      AS OLD_OBJECTID,
        M_ORG.OBJECTID      AS NEW_OBJECTID
    FROM INTRAWARE.MAPPING_APPR_KEY K_ENF
    JOIN INTRAWARE.MAPPING_APPR_KEY K_ORG
      ON K_ENF.ORIGIN_DOC_ID = K_ORG.DOC_ID
    JOIN INTRAWARE.DOCMBR M_ENF
      ON K_ENF.APPRID = M_ENF.APPRID AND M_ENF.DOCUMENTTYPE = 100
    JOIN INTRAWARE.DOCUMENT D_ENF
      ON M_ENF.OBJECTID = D_ENF.OBJECTID
    JOIN INTRAWARE.DOCMBR M_ORG
      ON K_ORG.APPRID = M_ORG.APPRID AND M_ORG.DOCUMENTTYPE = 100
    JOIN INTRAWARE.DOCUMENT D_ORG
      ON M_ORG.OBJECTID = D_ORG.OBJECTID
     AND (D_ENF.FILENAME = D_ORG.FILENAME AND D_ENF.FILESIZE = D_ORG.FILESIZE)
    WHERE K_ENF.DOC_TYPE = 'E'
      AND M_ENF.OBJECTID <> M_ORG.OBJECTID
) SRC
ON (M_ENF.APPRID = SRC.ENF_APPRID AND M_ENF.OBJECTID = SRC.OLD_OBJECTID)
WHEN MATCHED THEN
UPDATE SET 
    M_ENF.OBJECTID = SRC.NEW_OBJECTID;

COMMIT;


-- ----------------------------------------------------------------------------------------------------
-- [보정 2] DOCMBR 연결이 끊어진 중복 첨부 DOCUMENT 레코드 삭제 (물리 파일 삭제와 병행)
-- ----------------------------------------------------------------------------------------------------
DELETE /*+ PARALLEL(D, 16) */ FROM INTRAWARE.DOCUMENT D
WHERE D.DOCUMENTTYPE = 100
  AND D.OBJECTID IN (
      SELECT D_TARGET.OBJECTID
      FROM INTRAWARE.DOCUMENT D_TARGET
      JOIN INTRAWARE.MAPPING_FILE_KEY FK ON D_TARGET.OBJECTID = FK.OBJECTID
      WHERE FK.IS_INTERNAL_ENF = 'Y'
        AND FK.DOCUMENTTYPE = '100'
        AND NOT EXISTS (
            SELECT 1 FROM INTRAWARE.DOCMBR M WHERE M.OBJECTID = D_TARGET.OBJECTID
        )
  );

COMMIT;
