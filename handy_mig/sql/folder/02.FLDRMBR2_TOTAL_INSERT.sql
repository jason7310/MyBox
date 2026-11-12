-- ============================================================================
-- [통합 MIG] 기록물철 후속 처리 - 02. 부서별 전체문서함(APPLID=8010) 매핑
-- 
-- * 목적: 각 부서의 생산/접수 결재문서를 부서 '전체문서함'에 1:1 Direct-Path 매핑합니다.
-- ============================================================================

ALTER SESSION ENABLE PARALLEL DML;

INSERT /*+ APPEND PARALLEL(FLDRMBR2, 16) */ INTO INTRAWARE.FLDRMBR2 (
    FLDRID,
    FLDRMBRID,
    INDEXDATE,
    REGISTDATE,
    REGISTERID,
    UPDATEDATE,
    UPDATERID
)
SELECT 
    A.FLDRID,
    A.APPRID,
    A.DRAFTDATE,
    A.INDEXDATE,
    A.DRAFTERID,
    NULL AS UPDATEDATE,
    NULL AS UPDATERID
FROM (
    SELECT /*+ PARALLEL(AP, 16) */
        (SELECT F.FLDRID 
           FROM INTRAWARE.FOLDER F 
          WHERE F.OWNERID = AP.SAVEDEPTID 
            AND F.APPLID = 8010 
            AND ROWNUM = 1) AS FLDRID,
        AP.APPRID,
        AP.DRAFTDATE,
        AP.INDEXDATE,
        AP.DRAFTERID
    FROM INTRAWARE.APPROVAL AP
    WHERE AP.SAVEDEPTID IS NOT NULL
) A
WHERE A.FLDRID IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 
        FROM INTRAWARE.FLDRMBR2 M 
       WHERE M.FLDRID = A.FLDRID 
         AND M.FLDRMBRID = A.APPRID
  );

COMMIT;

SELECT '전체문서함(8010) 매핑 완료' AS STATUS, TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS FINISH_TIME FROM DUAL;
