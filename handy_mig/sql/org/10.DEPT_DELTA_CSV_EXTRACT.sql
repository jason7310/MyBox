-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 10. 오픈 당일 부서 증가분(Delta) 추출 (ADD / MODIFY 전용, DEL 완전 배제)
-- 
-- * 목적: 오픈 당일(D-Day) 사전 이관 이후 발생한 '신규 부서(ADD)' 및 '정보 변경 부서(MOD)'만 추출
-- * 원칙:
--   1) ⭐ DEL(삭제/폐지)은 오픈 당일 장애 방지를 위해 100% 완전 제외 (사후 수작업 처리)
--   2) 정상 사용 부서(DELETED = 0) 중 신규 및 변경 대상만 선별
--   3) 타겟 운영 DB(INTRAWARE.DEPT_GLOBAL)와 원천(MIG1_USER.MG_DEPT)을 1:1 비교(Diff)
-- * 추출 대상 파일: dept_delta.csv
-- ============================================================================
-- ============================================================================
-- 1. [ADD] 신규 부서 (핸디에 미존재하는 부서코드)
-- 실운영  부서 중 미이관 부서 존재 하는지 체크
-- 이관대상 아님 부서 목록 
-- 개발과,000020601한국보훈복지의료공단_본사_기획이사_기획조정실_정보지원부_개발과,,,,,
-- 일반검사실,1100367한국보훈복지의료공단_중앙보훈병원_원장실_진료부원장_제1진료본부_영상의학과_기사장실_책임방사선사실2_일반검사실,,,,,
-- 통합예약실,1400156,한국보훈복지의료공단_대구보훈병원_운영실_고객통합서비스 THIS 부_통합예약실,,,,,
-- 전화예약실,1400183,한국보훈복지의료공단_대구보훈병원_운영실_고객통합서비스 THIS 부_전화예약실,,,,,
-- 사회복지실,1400125,한국보훈복지의료공단_대구보훈병원_운영실_고객통합서비스 THIS 부_사회복지실,,,,,
-- ============================================================================
-- CSV 헤더 (1행)
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 DEPT INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '**OPERATION,DEPTNAME,DEPTNAME_ENG,DEPTLOCALE,DEPTCODE,PARCODE,SEQ,SITE,ABBREVIATION,BOXF,RECVF,MODIFYDATE,DEPTNAME2,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10' AS csv_row
  FROM DUAL
UNION ALL
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
-- 2. [ADD] 삭제 부서 (핸디에 미존재하는 부서코드)
-- AS-IS 삭제 부서 중 미이관 부서 존재 하는지 체크
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
     AND NVL(D.DELETED, '1') = '1' -- (운영 : 0 , 폐지 : 1)
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
-- 3. [MODIFY] 정보 변경 부서 (부서명, 상위부서, 약어, 순번, 접수/보유 플래그 변경)
-- ============================================================================
SELECT 
    'MODIFY'                                                                 -- operation
    || ',' || REPLACE(REPLACE(NVL(D.DEPTNAME, ' '), ',', ' '), '"', '""')   -- deptname
    || ',' || TRIM(D.DEPTCODE)                                              -- deptcode
    || ',' || TRIM(NVL(D.PARCODE, '000000000'))                             -- parcode
    || ',' || NVL(TO_CHAR(D.SEQ), '1')                                      -- seq
    || ',' || 'site'                                                      -- site
    || ',' || REPLACE(NVL(D.ABBREVIATION, ''), ',', ' ')                    -- abbreviation
    || ',' || NVL(D.BOXF, '1')                                              -- boxf
    || ',' || NVL(D.RECVF, '1')                                             -- recvf
    || ',' || TO_CHAR(NVL(D.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS')  -- modifydate
    || ',' || REPLACE(NVL(D.DEPTNAME2, ''), ',', ' ')                       -- deptname2
    || ',,,,,,,,,,'                                                       -- etc1 ~ etc10
    AS csv_row
  FROM MIG1_USER.MG_DEPT D
  JOIN INTRAWARE.DEPT_GLOBAL DG
    ON DG.DEPT_CODE = TRIM(D.DEPTCODE)
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG_PAR
    ON DG.PAR_ID = DG_PAR.DEPT_ID
 WHERE NVL(D.DELETED, 0) = 0
   AND (
       -- 부서명 변경
       TRIM(DG.DEPT_NAME) <> TRIM(D.DEPTNAME)
       -- 상위부서코드 변경
       OR NVL(TRIM(DG_PAR.DEPT_CODE), '000000000') <> TRIM(NVL(D.PARCODE, '000000000'))
       -- 약어 변경
       OR NVL(TRIM(DG.ABBREVIATION), ' ') <> NVL(TRIM(D.ABBREVIATION), ' ')
       -- 순번 변경
       OR NVL(DG.SEQ, 1) <> NVL(D.SEQ, 1)
       -- 문서함/수신함 플래그 변경
       OR NVL(DG.BOX_F, '1') <> NVL(D.BOXF, '1')
       OR NVL(DG.RECV_BOX_F, '1') <> NVL(D.RECVF, '1')
   );
