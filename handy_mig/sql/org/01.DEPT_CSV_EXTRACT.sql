-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 01. 부서 정보 추출 (MG_DEPT -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 부서 관리 > 일괄등록(CSV)
-- * 추출 순서: 1순위 (직위, 직급, 사용자 등록 전에 반드시 부서가 먼저 등록되어야 함)
-- * 원본 테이블: MIG1_USER.MG_DEPT (이미지 IMG_9458 기준)
--   - DEPTNAME     : VARCHAR2(200) 부서명
--   - DEPTCODE     : VARCHAR2(32)  부서코드
--   - PARCODE      : VARCHAR2(32)  상위부서코드
--   - SEQ          : NUMBER        정렬순서
--   - ABBREVIATION : VARCHAR2(200) 부서 약어(문서번호 등)
--   - DELETED        : CHAR(1)       부서삭제 (운영 : 0 , 폐지 : 1)
--   - RCVF         : CHAR(1)       문서접수유무(0:미접수, 1:접수)
--   - MODIFYDATE   : DATE          수정일자
--   - DEPTNAME2    : VARCHAR2(200) 영문부서명
-- ============================================================================

-- [심사숙고: 삭제 부서 처리 가이드]
-- 1) 실제 정상 부서와 삭제 부서는 반드시 별개의 CSV 파일로 분리하여 진행해야 합니다.
-- 2) 부서 등록 시 상위부서(PARCODE)가 먼저 시스템에 등록되어 있지 않으면 
--    관리자 화면 업로드 시 '상위부서 미존재' 오류가 발생하므로 계층 순(CONNECT BY)으로 추출합니다.
-- 3) 삭제 부서(DELETED = '1')는:
--    - 방안 A: 정상 부서 업로드 후, DEL 오퍼레이션으로 일괄 업로드하여 삭제 처리
--    - 방안 B: 과거 전자결재 이관 데이터 정합성을 위해 임시 '폐지부서' 하위에 ADD로 등록 유지
-- ============================================================================


-- ============================================================================
-- [1] 정상 부서 추출 (DELETED = '0') -> dept_normal.csv
--     * 관리자 화면에서 최우선으로 등록할 실제 사용 부서 목록
-- ============================================================================
-- CSV 헤더 (1행)
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 DEPT INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '**OPERATION,DEPTNAME,DEPTNAME_ENG,DEPTLOCALE,DEPTCODE,PARCODE,SEQ,SITE,ABBREVIATION,BOXF,RECVF,MODIFYDATE,DEPTNAME2,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10' AS csv_row
  FROM DUAL
UNION ALL
-- 부서 데이터 (계층 순 정렬)
SELECT 
    'ADD'                                                                 -- *operation
    || ',' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')   -- deptname (콤마/따옴표 제거)
    --|| ',' || CASE 
    --			WHEN ORG_LEVEL <= 2 THEN REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')
    --			ELSE REGEXP_SUBSTR(FULL_PATH,'[^>]+',1,2)||'_'||REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""') -- deptname : 삭제부서는 2레벨명과 자신의 부서명을 조합한다.
    --		  END
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')     		    -- DEPTNAME_ENG 
    || ',' || 'ko_KR'													  -- DEPTLOCALE 
    || ',' || TRIM(DEPTCODE)                                              -- deptcode
    || ',' || TRIM(PARCODE)                          				 -- parcode : 2026
    || ',' || NVL(TO_CHAR(SEQ), '1')                                      -- seq
    || ',' || 'site'                                                      -- site
    || ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ')                    -- abbreviation
    || ',' || NVL(BOXF, '1')                                              -- boxf (문서함보유 1:있음, 0:없음)
    || ',' || NVL(RECVF, '1')                                             -- recvf (문서접수유무 1:접수, 0:미접수)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- modifydate
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')                       -- deptname2 (영문명)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column1 : 등록날짜
	|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column2 : 폐지날짜   
	|| ',' || '0'   										 -- dept_column3 : (운영 : 0 , 폐지 : 1)
	|| ',' || ORG_LEVEL										 -- dept_column4 : 부서레벨
	|| ',' || REPLACE(SUBSTR(FULL_PATH,2),'>','_')			 -- dept_column5 : 부서 전체 경로
    || ',,,,,'                                               -- etc6 ~ etc10 (공란)
    AS csv_row
  FROM (
      SELECT 
         REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME, -- 알파벳,숫자,한글,공백 제외하고 모든 특수문자는 ' '(공백으로)
         REGEXP_REPLACE(D.DEPTNAME2,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME2, -- 알파벳,숫자,한글,공백 제외하고 모든 특수문자는 ' '(공백으로)
         D.DEPTCODE,
         D.PARCODE,
         D.SEQ,
         D.ABBREVIATION,
         D.BOXF,
         D.RECVF,
         D.MODIFYDATE,
         D.DELETED,
         D.ORG_LEVEL,
         --SYS_CONNECT_BY_PATH(D.DEPTNAME, '>') AS FULL_PATH,
         SYS_CONNECT_BY_PATH(REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' '), '>') AS FULL_PATH -- 알파벳,숫자,한글,공백 제외하고 모든 특수문자는 ' '(공백으로)
        FROM MIG1_USER.MG_DEPT D
       WHERE 1=1
     AND NVL(D.DELETED, '0') = '0' -- (운영 : 0 , 폐지 : 1)
        AND NOT EXISTS (
       SELECT 1 
         FROM INTRAWARE.DEPT_GLOBAL DG 
        WHERE DG.DEPT_CODE = TRIM(D.DEPTCODE)
   )
      START WITH D.PARCODE IS NULL OR D.PARCODE = '1000000' OR D.PARCODE = '000000000' OR D.PARCODE = D.DEPTCODE
     CONNECT BY PRIOR D.DEPTCODE = D.PARCODE
       ORDER SIBLINGS BY D.SEQ,
D.DEPTCODE
  );

  


 -- ============================================================================
-- [2] 삭제/폐지 부서 추출 (DELETED = '1') -> dept_deleted.csv
--     * 방안 A: DEL 작업용 (이미 시스템에 부서가 존재하거나 등록 후 삭제 처리할 때)
-- 부서명, 부서코드 중복 허용 하지 않음
-- 부서명에 금칙문자는 모두 제거 한다. ' '(공백으로 처리)
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 DEPT INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '**OPERATION,DEPTNAME,DEPTNAME_ENG,DEPTLOCALE,DEPTCODE,PARCODE,SEQ,SITE,ABBREVIATION,BOXF,RECVF,MODIFYDATE,DEPTNAME2,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10' AS csv_row
  FROM DUAL
UNION ALL
-- 부서 데이터 (계층 순 정렬)
SELECT 
    'ADD'                                                                 -- *operation
    --|| ',' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')   -- deptname (콤마/따옴표 제거)
    || ',' || CASE 
    			WHEN ORG_LEVEL <= 2 THEN REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')
    			ELSE REGEXP_SUBSTR(FULL_PATH,'[^>]+',1,2)||'_'||REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""') -- deptname : 삭제부서는 2레벨명과 자신의 부서명을 조합한다.
    		  END
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')     		    -- DEPTNAME_ENG 
    || ',' || 'ko_KR'													  -- DEPTLOCALE 
    || ',' || TRIM(DEPTCODE)                                              -- deptcode
    || ',' || 'DEL2026'                          						  -- parcode : 2026
    || ',' || NVL(TO_CHAR(SEQ), '1')                                      -- seq
    || ',' || 'site'                                                      -- site
    || ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ')                    -- abbreviation
    || ',' || NVL(BOXF, '1')                                              -- boxf (문서함보유 1:있음, 0:없음)
    || ',' || NVL(RECVF, '1')                                             -- recvf (문서접수유무 1:접수, 0:미접수)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- modifydate
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')                       -- deptname2 (영문명)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column1 : 등록날짜
	|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column2 : 폐지날짜   
	|| ',' || '1'   										 -- dept_column3 : (운영 : 0 , 폐지 : 1)
	|| ',' || ORG_LEVEL										 -- dept_column4 : 부서레벨
	|| ',' || REPLACE(SUBSTR(FULL_PATH,2),'>','_')			 -- dept_column5 : 부서 전체 경로
    || ',,,,,'                                               -- etc6 ~ etc10 (공란)
    AS csv_row
  FROM (
      SELECT 
         REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME,
         REGEXP_REPLACE(D.DEPTNAME2,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME2,
         D.DEPTCODE,
         D.PARCODE,
         D.SEQ,
         D.ABBREVIATION,
         D.BOXF,
         D.RECVF,
         D.MODIFYDATE,
         D.DELETED,
         D.ORG_LEVEL,
         --SYS_CONNECT_BY_PATH(D.DEPTNAME, '>') AS FULL_PATH,
         SYS_CONNECT_BY_PATH(REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' '), '>') AS FULL_PATH -- 알파벳,숫자,한글,공백 제외하고 모든 특수문자는 ' '(공백으로)
        FROM MIG1_USER.MG_DEPT D
       WHERE NVL(D.DELETED, '1') = '1' -- (운영 : 0 , 폐지 : 1)
       START WITH D.PARCODE IS NULL OR D.PARCODE = '1000000' OR D.PARCODE = '000000000' OR D.PARCODE = D.DEPTCODE
     CONNECT BY PRIOR D.DEPTCODE = D.PARCODE
       ORDER SIBLINGS BY D.SEQ, D.DEPTCODE
  );

-- ============================================================================
-- [3] 삭제/폐지 부서 - 전자결재 이관용 폐지부서 하위 ADD 추출 (방안 B 권장)
--     * 과거 결재문서 조회 시 부서코드가 누락되면 문서 조회가 불가능하므로,
--       관리자 화면에서 '폐지부서(구부서)'를 만든 후 그 하위로 부서를 살려두는 경우 사용
--     * 예: 상위부서코드를 지정된 폐지부서코드('DEL_DEPT')로 치환하여 ADD 등록
-- ============================================================================
/*
SELECT '*operation,deptname,deptcode,parcode,seq,site,abbreviation,boxf,recvf,modifydate,deptname2,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'ADD'
    || ',[폐지]' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')
    || ',' || TRIM(DEPTCODE)
    || ',' || 'DEL_DEPT'                                                  -- 임시 폐지부서 루트 코드
    || ',' || NVL(TO_CHAR(SEQ), '1')
    || ',' || 'site'
    || ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ')
    || ',' || '0'                                                         -- 문서접수 불가
    || ',' || '0'
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS')
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')
    || ',,,,,,,,,,'
    AS csv_row
  FROM MIG1_USER.MG_DEPT
 WHERE NVL(DELETED, '1') = '0'
 ORDER BY SEQ, DEPTCODE;
*/


-- ============================================================================
-- [4] ⭐ 삭제여부 불문 전체 부서 일괄 등록 (ALL-ADD) -> dept_all_add.csv
--     * 전략: 전자결재 이관 중 부서 ID 결손 방지를 위해 정상/폐지 불문 전체를 ADD로 선등록
--     * 결재문서 이관 완료 후 '08.ORG_POST_DELETE_UPDATE.sql'을 통해 삭제 대상만 STATUS=4로 후처리
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 DEPT INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '**OPERATION,DEPTNAME,DEPTNAME_ENG,DEPTLOCALE,DEPTCODE,PARCODE,SEQ,SITE,ABBREVIATION,BOXF,RECVF,MODIFYDATE,DEPTNAME2,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10' AS csv_row
  FROM DUAL
UNION ALL
-- 부서 데이터 (계층 순 정렬)
SELECT 
    'ADD'                                                                 -- *operation
    || ',' || REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')   -- deptname (콤마/따옴표 제거)
    --|| ',' || CASE 
    --			WHEN ORG_LEVEL <= 2 THEN REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""')
    --			ELSE REGEXP_SUBSTR(FULL_PATH,'[^>]+',1,2)||'_'||REPLACE(REPLACE(NVL(DEPTNAME, ' '), ',', ' '), '"', '""') -- deptname : 삭제부서는 2레벨명과 자신의 부서명을 조합한다.
    --		  END
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')     		    -- DEPTNAME_ENG 
    || ',' || 'ko_KR'													  -- DEPTLOCALE 
    || ',' || TRIM(DEPTCODE)                                              -- deptcode
    || ',' || 'DEL2026'                          						  -- parcode : 2026
    || ',' || NVL(TO_CHAR(SEQ), '1')                                      -- seq
    || ',' || 'site'                                                      -- site
    || ',' || REPLACE(NVL(ABBREVIATION, ''), ',', ' ')                    -- abbreviation
    || ',' || NVL(BOXF, '1')                                              -- boxf (문서함보유 1:있음, 0:없음)
    || ',' || NVL(RECVF, '1')                                             -- recvf (문서접수유무 1:접수, 0:미접수)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- modifydate
    || ',' || REPLACE(NVL(DEPTNAME2, ''), ',', ' ')                       -- deptname2 (영문명)
    || ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column1 : 등록날짜
	|| ',' || TO_CHAR(NVL(MODIFYDATE, SYSDATE), 'YYYYMMDD')  -- dept_column2 : 폐지날짜   
	|| ',' || '1'   										 -- dept_column3 : (운영 : 0 , 폐지 : 1)
	|| ',' || ORG_LEVEL										 -- dept_column4 : 부서레벨
	|| ',' || REPLACE(SUBSTR(FULL_PATH,2),'>','_')			 -- dept_column5 : 부서 전체 경로
    || ',,,,,'                                               -- etc6 ~ etc10 (공란)
    AS csv_row
  FROM (
      SELECT 
         REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME,
         REGEXP_REPLACE(D.DEPTNAME2,'[^[:alnum:]가-힣[:space:]]',' ') AS DEPTNAME2,
         D.DEPTCODE,
         D.PARCODE,
         D.SEQ,
         D.ABBREVIATION,
         D.BOXF,
         D.RECVF,
         D.MODIFYDATE,
         D.DELETED,
         D.ORG_LEVEL,
         --SYS_CONNECT_BY_PATH(D.DEPTNAME, '>') AS FULL_PATH,
         SYS_CONNECT_BY_PATH(REGEXP_REPLACE(D.DEPTNAME,'[^[:alnum:]가-힣[:space:]]',' '), '>') AS FULL_PATH -- 알파벳,숫자,한글,공백 제외하고 모든 특수문자는 ' '(공백으로)
        FROM MIG1_USER.MG_DEPT D
       WHERE 1=1
      -- AND NVL(D.DELETED, '1') = '0' -- (운영 : 0 , 폐지 : 1)
       START WITH D.PARCODE IS NULL OR D.PARCODE = '1000000' OR D.PARCODE = '000000000' OR D.PARCODE = D.DEPTCODE
     CONNECT BY PRIOR D.DEPTCODE = D.PARCODE
       ORDER SIBLINGS BY D.SEQ, D.DEPTCODE
  );
  