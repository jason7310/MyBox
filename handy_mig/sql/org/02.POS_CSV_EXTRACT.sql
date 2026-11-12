-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 02. 직위 정보 추출 (MG_POS -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 직위/직급 관리 > 직위 관리 > 일괄등록(CSV)
-- * 추출 순서: 2순위 (부서 등록 후, 사용자 등록 전에 등록)
-- * 원본 테이블: MIG1_USER.MG_POS (또는 MIG1_USER.MG_POS)
--   - POSCODE  : VARCHAR2(11)  직위코드
--   - POSNAME  : VARCHAR2(100) 직위명
--   - POSLEVEL : NUMBER        직위등급 (보안/결재레벨 매핑)
--   - POSSEQ   : NUMBER        동일등급간 서열
-- ============================================================================

-- [핸디 그룹웨어 직위 CSV 헤더 규격]
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 POS INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,posname,poscode,seclevel,sanclevel' AS csv_row
  FROM DUAL
UNION ALL
-- 직위 데이터 추출
SELECT 
    'ADD'                                                                 -- *operation
    || ',' || REPLACE(REPLACE(NVL(POSNAME, ' '), ',', ' '), '"', '""')     -- posname (직위명)
    || ',' || TRIM(POSCODE)                                               -- poscode (직위코드)
    || ',' || NVL(TO_CHAR(POSLEVEL), '100')                               -- seclevel (보안레벨: 기본 100)
    || ',' || NVL(TO_CHAR(POSLEVEL), '100')                               -- sanclevel (결재레벨: 기본 100)
    AS csv_row
  FROM (
      SELECT DISTINCT 
             POSCODE,
             POSNAME,
             NVL(POSLEVEL, 100) AS POSLEVEL,
             NVL(POSSEQ, 1)     AS POSSEQ
        FROM MIG1_USER.MG_POS
       WHERE POSNAME IS NOT NULL
       ORDER BY POSLEVEL ASC, POSSEQ ASC, POSCODE ASC
  );
