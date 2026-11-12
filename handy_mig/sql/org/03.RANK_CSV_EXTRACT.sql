-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 03. 직급 정보 추출 (MG_RANK -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 직위/직급 관리 > 직급 관리 > 일괄등록(CSV)
-- * 추출 순서: 3순위 (부서, 직위 등록 후, 사용자 등록 전에 등록)
-- * 원본 테이블: MIG1_USER.MG_RANK (이미지 IMG_9460 기준)
--   - RANKCODE  : VARCHAR2(10) 직급코드(ID)
--   - RANKNAME  : VARCHAR2(50) 직급명
--   - RANKLEVEL : NUMBER       직급순서/등급
--   - RANKDEL   : NUMBER       동일직급간서열 (또는 RANKSEQ)
-- ============================================================================

-- [핸디 그룹웨어 직급 CSV 헤더 규격]
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 RANK INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,rankname,rankcode,ranklevel' AS csv_row
  FROM DUAL
UNION ALL
-- 직급 데이터 추출
SELECT 
    'ADD'                                                                 -- *operation
    || ',' || REPLACE(REPLACE(NVL(RANKNAME, ' '), ',', ' '), '"', '""')   -- rankname (직급명)
    || ',' || TRIM(RANKCODE)                                              -- rankcode (직급코드)
    || ',' || NVL(TO_CHAR(RANKLEVEL), '100')                              -- ranklevel (직급등급/순서)
    AS csv_row
  FROM (
      SELECT DISTINCT 
             RANKCODE,
             RANKNAME,
             NVL(RANKLEVEL, 100) AS RANKLEVEL,
             NVL(RANKDEL, 1)     AS RANKDEL
        FROM MIG1_USER.MG_RANK
       WHERE RANKNAME IS NOT NULL
       ORDER BY RANKLEVEL ASC, RANKDEL ASC, RANKCODE ASC
  );
