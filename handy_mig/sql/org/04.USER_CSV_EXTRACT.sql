-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 04. 사용자 정보 추출 (MIG1_USER -> CSV)
-- 
-- * 관리자 화면 메뉴: 조직도 관리 > 사용자 관리 > 일괄등록(CSV)
-- * 추출 순서: 4순위 (부서, 직위, 직급이 반드시 먼저 등록 완료되어 있어야 함)
-- * 원본 테이블: MIG1_USER.MG_USER (이미지 IMG_9459, IMG_9461 기준)
--   - NAME, EMPCODE, DEPTCODE, POSNAME, RANKNAME, DUTYNAME, PASSWORD
--   - SECURITY, SANCLEVEL, ISUSE(결재사용: 1 정상사용자, 0 탈퇴/미사용)
--   - MODIFYDATE, ALIAS, SEX, PHONE, FAX, EMAIL, HOMEPAGE, SSN, WEDDAY
--   - BIRTHDAY, HOMEADDR, HOMEZIP, HOMEPHONE, HOMEFAX, BEEPER, MOBILEPHONE
--   - BUSINESS, WHETHERBUSINESSMAN, USER_ID, USER_UID
-- ============================================================================

-- [심사숙고: 삭제/퇴직 사용자 처리 방안]
-- 1) 정상 재직자와 퇴직/삭제자는 반드시 별개의 CSV 파일로 분리하여 진행합니다.
-- 2) 전자결재 과거 문서 정합성:
--    과거 문서의 기안자, 결재선(PARTICIPANT) 등에 존재하는 사용자가 핸디 조직도에 전혀 없으면
--    문서 조회 시 이름/부서가 공란 처리되거나 오류가 발생할 수 있습니다.
--    따라서:
--    - [파일 1] 정상 재직자 (ISUSE = '1') -> user_normal.csv (ADD 등록)
--    - [파일 2] 삭제/퇴직자 - 결재이관 보존용 ADD -> user_deleted_add.csv 
--               (관리자 화면에 '퇴직자' 부서 생성 후 해당 부서로 ADD 등록)
--    - [파일 3] 삭제/퇴직자 - DEL 처리용 -> user_deleted_del.csv (DEL 플래그)
-- ============================================================================

-- 재직자 
-- * EMPCODE 6자리 이상인것 
-- 감사01~감사10  : 이관해야함(감사시 
-- 외부사용자도 있네, 그냥 삭제자 아니면 이관 함. 


-- ============================================================================
-- [1] 정상 (재직or휴직)and원직자 사용자 추출 -> user_normal.csv
-- DELETED                  -> 재직 : 0 , 휴직 : 1, 퇴직 : 2
-- ANOTHERBUSINESSYN -> N: 원직자 , Y:겸직자
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, '무명인'), ',', ' '), '"', '""')                 -- 2. name (이름)
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))                                         -- 3. empcode (사번), 겸직자는 뒤에 _u1 붙음
    || ',' || TRIM(U.DEPTCODE)                                                        -- 4. deptcode (부서코드)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (직위명)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (직급명)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (직책명)
    || ',' || '1'                                                                    -- 9. password : 기본값 1로 셋팅
    || ',' || NVL(TO_CHAR(U.SECURITY), '1')                                         -- 10. security (기본 100)
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '1')                                        -- 11. sanclevel (기본 100)
    || ',' || '3'                                                                     -- 12. signtype (1:도장, 2:사인, 3:일반텍스트(문자서명))
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYYMMDD')                        -- 13. modifydate
    || ',' || ''								                                     -- 14. alias
    || ',' || NVL(U.SEX, '')                                                         -- 15. sex (0:남, 1:여)
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone : 회사
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax : 회사
    --|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email : 사번@
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))||'@kvhs.or.kr'  							-- 18. email : 사번@kvhs.OR.kr
    || ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ')                                  -- 19. homepage
    || ',' || REPLACE(NVL(U.SSN, ''), ',', ' ')                                       -- 20. ssn
    || ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ')                                    -- 21. wedday
    || ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ')                                  -- 22. birthday
    || ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '"', '""')              -- 23. homeaddr
    || ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ')                                   -- 24. homezip
    || ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ')                                 -- 25. homephone
    || ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ')                                   -- 26. homefax
    || ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ')                                    -- 27. beeper
    || ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ')                               -- 28. mobilephone
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business (개행/콤마 제거)
    || ',' || ''                                                                      -- 30. mngrtype
    || ',' ||  REPLACE(NVL(U.EMAIL, ''), ',', ' ')									  -- user_column1 : ELTR_MLAD 외부메일
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') 									  -- user_column2 : COMP_TENR 회사전화번호
    || ',' || '0'																	  -- user_column3 :	파견여부(0/1/2 사용안함/유예/사용중)
    || ',' || ''																	  -- user_column4 :	파견부서
    || ',' || CASE 																	
    			WHEN U.DELETED = '0'	THEN '0' 
    			WHEN U.DELETED = '1'	THEN '1' 
    			WHEN U.DELETED = '2'	THEN '2'															 
    			ELSE '0' 
    		  END 																	 -- user_column5 :	근무상태코드 0/1/2(재직/휴직/퇴직)  
    || ',' || CASE 													    
    			WHEN U.DELETED = '1'	THEN '003'
    			WHEN U.DELETED = '2'	THEN '002'
    			ELSE '0'
    		  END																		-- user_column6 :	 WOCO_CODE 원근무상태코드 : 001/002/003(재직/퇴직/휴직)
    || ',' || ''																	  -- user_column7 :	 APNT_TYPE 겸직여부      N (null) : 원직자 , Y:겸직자     
    || ',' || ''																	  -- user_column8 :	겸직사용자의 원 사번																	
    ||',,,,,,,,,,,,'                                                                  -- etc9 ~ etc20 (12개 공란)
    AS csv_row
  FROM MIG1_USER.MG_USER U
 WHERE 1=1
 AND DELETED IN ('0', '1') -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
 AND ANOTHERBUSINESSYN = 'N' -- N: 원직자 , Y:겸직자
;

-- ============================================================================
-- [2] 정상 (재직or휴직)and겸직자 사용자 추출 -> user_normal_other.csv
-- 겸직자의 사번 : 원직자사번_U1 ~ Un 시퀀스 하게 붙음
-- DELETED                  -> 재직 : 0 , 휴직 : 1, 퇴직 : 2
-- ANOTHERBUSINESSYN -> N: 원직자 , Y:겸직자
-- ============================================================================
-- 재직 겸직자
-- as-IS에 재직자 겸직이 586 
-- 이관 안된게 : 1건 (부서존재하지않음)
-- ADD,정인채,,ko_KR,101920_U1,1400084,site,팀장,1급,,6,1,3,20261109,,,,,101920@kvhs.or.kr,,,,,,,,,,,,,101920@bohun.or.kr,,0,,0,0,,,,,,,,,,,,,,
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*OPERATION,NAME,NAME_ENG,LOCALE,EMPCODE,DEPTCODE,SITE,POSNAME,RANKNAME,DUTYNAME,SECLEVEL,SANCLEVEL,SIGNTYPE,MODIFYDATE,ALIAS,SEX,PHONE,FAX,EMAIL,HOMEPAGE,SSN,WEDDAY,BIRTHDAY,HOMEADDR,HOMEZIP,HOMEPHONE,HOMEFAX,BEEPER,MOBILEPHONE,BUSINESS,MNGRTYPE,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10,ETC11,ETC12,ETC13,ETC14,ETC15,ETC16,ETC17,ETC18,ETC19,ETC20' AS csv_row
   FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, '무명인'), ',', ' '), '"', '""')                 -- 2. name (이름)
    || ',' || ''														                 -- 2. NAME_ENG (영어 이름)
    || ',' || 'ko_KR'	
	|| ',' || TRIM(NVL(U.EMPCODE, '000000'))||'_U'||ROW_NUMBER() OVER(PARTITION BY U.USER_RID ORDER BY U.USER_UID )    -- 3. empcode (사번), 겸직자는 뒤에 _u1 붙음
    || ',' || TRIM(U.DEPTCODE)                                                        -- 4. deptcode (부서코드)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (직위명)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (직급명)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (직책명)
   -- || ',' || '1'                                                                    -- 9. password : 기본값 1로 셋팅
    || ',' || NVL(TO_CHAR(U.SECURITY), '1')                                         -- 10. security (기본 100)
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '1')                                        -- 11. sanclevel (기본 100)
    || ',' || '3'                                                                     -- 12. signtype (1:도장, 2:사인, 3:일반텍스트(문자서명))
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYYMMDD')                        -- 13. modifydate
    || ',' || ''								                                     -- 14. alias
    || ',' || NVL(U.SEX, '')                                                         -- 15. sex (0:남, 1:여)
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone : 회사
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax : 회사
    --|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email : 사번@
    || ',' || TRIM(NVL(U.EMPCODE
    , '000000'))||'@kvhs.or.kr'  							-- 18. email : 사번@kvhs.OR.kr
    || ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ')                                  -- 19. homepage
    || ',' || REPLACE(NVL(U.SSN, ''), ',', ' ')                                       -- 20. ssn
    || ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ')                                    -- 21. wedday
    || ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ')                                  -- 22. birthday
    || ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '"', '""')              -- 23. homeaddr
    || ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ')                                   -- 24. homezip
    || ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ')                                 -- 25. homephone
    || ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ')                                   -- 26. homefax
    || ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ')                                    -- 27. beeper
    || ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ')                               -- 28. mobilephone
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business (개행/콤마 제거)
    || ',' || ''                                                                      -- 30. mngrtype
    || ',' ||  REPLACE(NVL(U.EMAIL, ''), ',', ' ')									  -- user_column1 : ELTR_MLAD 외부메일
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') 									  -- user_column2 : COMP_TENR 회사전화번호
    || ',' || '0'																	  -- user_column3 :	파견여부(0/1/2 사용안함/유예/사용중)
    || ',' || ''																	  -- user_column4 :	파견부서
    || ',' || CASE 																	
    			WHEN U.DELETED = '0'	THEN '0' 
    			WHEN U.DELETED = '1'	THEN '1' 
    			WHEN U.DELETED = '2'	THEN '2'															 
    			ELSE '0' 
    		  END 																	 -- user_column5 :	근무상태코드 0/1/2(재직/휴직/퇴직)  
    || ',' || CASE 													    
    			WHEN U.DELETED = '1'	THEN '003'
    			WHEN U.DELETED = '2'	THEN '002'
    			ELSE '0'
    		  END																		-- user_column6 :	 WOCO_CODE 원근무상태코드 : 001/002/003(재직/퇴직/휴직)
    || ',' || ''																	  -- user_column7 :	 APNT_TYPE 겸직여부      N (null) : 원직자 , Y:겸직자     
    || ',' || ''																	  -- user_column8 :	겸직사용자의 원 사번																	
    ||',,,,,,,,,,,,'                                                                  -- etc9 ~ etc20 (12개 공란)
    AS csv_row 
FROM
	(SELECT
	 U.*,
   	 TRIM(NVL(U.EMPCODE, '000000'))||'_U'||ROW_NUMBER() OVER(PARTITION BY U.USER_RID ORDER BY U.USER_UID ) AS EMPCODE_U  -- 겸직자 사번 생성 
	FROM MIG1_USER.MG_USER U
	 WHERE 1=1
	  AND DELETED IN ('0', '1') -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
	 -- AND DELETED = '2' -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
	 --AND U.POSNAME NOT IN ('외부사용자','인턴')
	 AND TRIM(U.EMPCODE) IS NOT NULL 
	 AND ANOTHERBUSINESSYN = 'Y' -- N: 원직자 , Y:겸직자
	 ) U
 WHERE 1=1
 	AND NOT EXISTS (
 		SELECT 1
 			FROM INTRAWARE.USR_GLOBAL UG 
 		WHERE 1=1 
 		AND TRIM(UG.EMP_CODE)  = TRIM(NVL(U.EMPCODE_U, U.EMPCODE)) 
 		AND UG.ORG_OTHER_OFFICE_F  = '1' 
 	)
;



-- ============================================================================
-- [3] 원직에 대한 퇴직자 - DEL2026 부서에 등록 -> user_deleted_add.csv
-- 퇴직자중 원직자만 등록한다.
-- 퇴직자의 겸직은 50만건 정도..이관 대상 아님)
-- DELETED                  -> 재직 : 0 , 휴직 : 1, 퇴직 : 2
-- ANOTHERBUSINESSYN -> N: 원직자 , Y:겸직자 
-- 
-- ============================================================================
--// 원직에 대한 퇴직자 : 10991-2
--// 겸직에 대한 퇴직은 이관 하지 않는다.
--// 등록부서는 :DEL2026 
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*OPERATION,NAME,NAME_ENG,LOCALE,EMPCODE,DEPTCODE,SITE,POSNAME,RANKNAME,DUTYNAME,SECLEVEL,SANCLEVEL,SIGNTYPE,MODIFYDATE,ALIAS,SEX,PHONE,FAX,EMAIL,HOMEPAGE,SSN,WEDDAY,BIRTHDAY,HOMEADDR,HOMEZIP,HOMEPHONE,HOMEFAX,BEEPER,MOBILEPHONE,BUSINESS,MNGRTYPE,ETC1,ETC2,ETC3,ETC4,ETC5,ETC6,ETC7,ETC8,ETC9,ETC10,ETC11,ETC12,ETC13,ETC14,ETC15,ETC16,ETC17,ETC18,ETC19,ETC20' 
	AS csv_row
   FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, '무명인'), ',', ' '), '"', '""')                 -- 2. name (이름)
    || ',' || ''														                 -- 2. NAME_ENG (영어 이름)
    || ',' || 'ko_KR'	
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))                                         -- 3. empcode (사번), 겸직자는 뒤에 _u1 붙음
    || ',' || 'DEL2026'                                                              -- 4. deptcode (부서코드)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (직위명)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (직급명)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (직책명)
   -- || ',' || '1'                                                                    -- 9. password : 기본값 1로 셋팅
    || ',' || NVL(TO_CHAR(U.SECURITY), '1')                                         -- 10. security (기본 100)
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '1')                                        -- 11. sanclevel (기본 100)
    || ',' || '3'                                                                     -- 12. signtype (1:도장, 2:사인, 3:일반텍스트(문자서명))
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYYMMDD')                        -- 13. modifydate
    || ',' || ''								                                     -- 14. alias
    || ',' || NVL(U.SEX, '')                                                         -- 15. sex (0:남, 1:여)
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone : 회사
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax : 회사
    --|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email : 사번@
    || ',' || TRIM(NVL(U.EMPCODE
    , '000000'))||'@kvhs.or.kr'  							-- 18. email : 사번@kvhs.OR.kr
    || ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ')                                  -- 19. homepage
    || ',' || REPLACE(NVL(U.SSN, ''), ',', ' ')                                       -- 20. ssn
    || ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ')                                    -- 21. wedday
    || ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ')                                  -- 22. birthday
    || ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '"', '""')              -- 23. homeaddr
    || ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ')                                   -- 24. homezip
    || ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ')                                 -- 25. homephone
    || ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ')                                   -- 26. homefax
    || ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ')                                    -- 27. beeper
    || ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ')                               -- 28. mobilephone
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business (개행/콤마 제거)
    || ',' || ''                                                                      -- 30. mngrtype
    || ',' ||  REPLACE(NVL(U.EMAIL, ''), ',', ' ')									  -- user_column1 : ELTR_MLAD 외부메일
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') 									  -- user_column2 : COMP_TENR 회사전화번호
    || ',' || '0'																	  -- user_column3 :	파견여부(0/1/2 사용안함/유예/사용중)
    || ',' || ''																	  -- user_column4 :	파견부서
    || ',' || CASE 																	
    			WHEN U.DELETED = '0'	THEN '0' 
    			WHEN U.DELETED = '1'	THEN '1' 
    			WHEN U.DELETED = '2'	THEN '2'															 
    			ELSE '0' 
    		  END 																	  -- user_column5 :	근무상태코드 0/1/2(재직/휴직/퇴직)  
    || ',' || CASE 													    
    			WHEN U.DELETED = '1'	THEN '003'
    			WHEN U.DELETED = '2'	THEN '002'
    			ELSE '0'
    		  END																		-- user_column6 :	 WOCO_CODE 원근무상태코드 : 001/002/003(재직/퇴직/휴직)
    || ',' || 'N'																	    -- user_column7 :	 APNT_TYPE 겸직여부      N (null) : 원직자 , Y:겸직자     
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))									      -- user_column8 :	겸직사용자의 원 사번		
    || ',' || TRIM(U.DEPTCODE) 														-- user_column9 : 이관시 퇴직자는 DEL2026에 넣으니까, 원 소속 부서를 저장
    ||',,,,,,,,,,,'                                                                  -- etc9 ~ etc20 (12개 공란)
    AS csv_row
  FROM MIG1_USER.MG_USER U
 WHERE 1=1
 -- AND DELETED IN ('0', '1') -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
 AND DELETED = '2' -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
 AND U.POSNAME NOT IN ('외부사용자','인턴')
 AND TRIM(U.EMPCODE) IS NOT NULL 
 AND ANOTHERBUSINESSYN = 'N' -- N: 원직자 , Y:겸직자
 	AND NOT EXISTS (
 		SELECT 1
 			FROM INTRAWARE.USR_GLOBAL UG 
 		WHERE TRIM(UG.EMP_CODE)  = TRIM(NVL(U.EMPCODE, U.USER_RID)) 
 		AND UG.ORG_OTHER_OFFICE_F  = '0'  -- 0: 원직, 1:겸직
 	)
;
/*
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'DELETE'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, '무명인'), ',', ' '), '"', '""')                 -- 2. name (이름)
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))                                         -- 3. empcode (사번), 겸직자는 뒤에 _u1 붙음
    || ',' || 'DELDEPT'                                                              -- 4. deptcode (부서코드)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (직위명)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (직급명)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (직책명)
    || ',' || '1'                                                                    -- 9. password : 기본값 1로 셋팅
    || ',' || NVL(TO_CHAR(U.SECURITY), '1')                                         -- 10. security (기본 100)
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '1')                                        -- 11. sanclevel (기본 100)
    || ',' || '3'                                                                     -- 12. signtype (1:도장, 2:사인, 3:일반텍스트(문자서명))
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYYMMDD')                        -- 13. modifydate
    || ',' || ''								                                     -- 14. alias
    || ',' || NVL(U.SEX, '')                                                         -- 15. sex (0:남, 1:여)
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone : 회사
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax : 회사
    --|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email : 사번@
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))||'@kvhs.or.kr'  							-- 18. email : 사번@kvhs.OR.kr
    || ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ')                                  -- 19. homepage
    || ',' || REPLACE(NVL(U.SSN, ''), ',', ' ')                                       -- 20. ssn
    || ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ')                                    -- 21. wedday
    || ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ')                                  -- 22. birthday
    || ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '"', '""')              -- 23. homeaddr
    || ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ')                                   -- 24. homezip
    || ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ')                                 -- 25. homephone
    || ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ')                                   -- 26. homefax
    || ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ')                                    -- 27. beeper
    || ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ')                               -- 28. mobilephone
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business (개행/콤마 제거)
    || ',' || ''                                                                      -- 30. mngrtype
    || ',' ||  REPLACE(NVL(U.EMAIL, ''), ',', ' ')									  -- user_column1 : ELTR_MLAD 외부메일
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') 									  -- user_column2 : COMP_TENR 회사전화번호
    || ',' || '0'																	  -- user_column3 :	파견여부(0/1/2 사용안함/유예/사용중)
    || ',' || ''																	  -- user_column4 :	파견부서
    || ',' || CASE 																	
    			WHEN U.DELETED = '0'	THEN '0' 
    			WHEN U.DELETED = '1'	THEN '1' 
    			WHEN U.DELETED = '2'	THEN '2'															 
    			ELSE '0' 
    		  END 																	 -- user_column5 :	근무상태코드 0/1/2(재직/휴직/퇴직)  
    || ',' || CASE 													    
    			WHEN U.DELETED = '1'	THEN '003'
    			WHEN U.DELETED = '2'	THEN '002'
    			ELSE '0'
    		  END																		-- user_column6 :	 WOCO_CODE 원근무상태코드 : 001/002/003(재직/퇴직/휴직)
    || ',' || ''																	  -- user_column7 :	 APNT_TYPE 겸직여부      N (null) : 원직자 , Y:겸직자     
    || ',' || ''																	  -- user_column8 :	겸직사용자의 원 사번																	
    ||',,,,,,,,,,,,'                                                                  -- etc9 ~ etc20 (12개 공란)
    AS csv_row
  FROM MIG1_USER.MG_USER U
 WHERE 1=1
 AND DELETED = '2' -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
 AND ANOTHERBUSINESSYN = 'N' -- N: 원직자 , Y:겸직자
;
*/
-- ============================================================================
-- [4] ⭐ 재직/퇴직 불문 전체 사용자 일괄 등록 (ALL-ADD) -> user_all_add.csv
--     * 전략: 전자결재 이관 중 작성자/결재자 ID 결손 방지를 위해 재직/퇴직 불문 전체를 ADD 선등록
--     * 원래 소속 부서코드를 그대로 유지하여 매핑 무결성 100% 확보
--     * 퇴직자는 로그인 불가 패스워드('!') 및 보안/결재등급 0으로 안전 처리
--     * 결재문서 이관 완료 후 '08.ORG_POST_DELETE_UPDATE.sql'을 통해 퇴직자만 STATUS=4로 후처리
--    이건 작업 하지 않는다, INSERT 문으로 USR_GLOBAL에만 등록 하도록 한다. 
-- ============================================================================
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL
UNION ALL
SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row
  FROM DUAL
UNION ALL
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, '무명인'), ',', ' '), '"', '""')                 -- 2. name (이름)
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))                                         -- 3. empcode (사번), 겸직자는 뒤에 _u1 붙음
    || ',' || TRIM(U.DEPTCODE)                                                        -- 4. deptcode (부서코드)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (직위명)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (직급명)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (직책명)
    || ',' || '1'                                                                    -- 9. password : 기본값 1로 셋팅
    || ',' || NVL(TO_CHAR(U.SECURITY), '1')                                         -- 10. security (기본 100)
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '1')                                        -- 11. sanclevel (기본 100)
    || ',' || '3'                                                                     -- 12. signtype (1:도장, 2:사인, 3:일반텍스트(문자서명))
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYYMMDD')                        -- 13. modifydate
    || ',' || ''								                                     -- 14. alias
    || ',' || NVL(U.SEX, '')                                                         -- 15. sex (0:남, 1:여)
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone : 회사
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax : 회사
    --|| ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email : 사번@
    || ',' || TRIM(NVL(U.EMPCODE, '000000'))||'@kvhs.or.kr'  							-- 18. email : 사번@kvhs.OR.kr
    || ',' || REPLACE(NVL(U.HOMEPAGE, ''), ',', ' ')                                  -- 19. homepage
    || ',' || REPLACE(NVL(U.SSN, ''), ',', ' ')                                       -- 20. ssn
    || ',' || REPLACE(NVL(U.WEDDAY, ''), ',', ' ')                                    -- 21. wedday
    || ',' || REPLACE(NVL(U.BIRTHDAY, ''), ',', ' ')                                  -- 22. birthday
    || ',' || REPLACE(REPLACE(NVL(U.HOMEADDR, ''), ',', ' '), '"', '""')              -- 23. homeaddr
    || ',' || REPLACE(NVL(U.HOMEZIP, ''), ',', ' ')                                   -- 24. homezip
    || ',' || REPLACE(NVL(U.HOMEPHONE, ''), ',', ' ')                                 -- 25. homephone
    || ',' || REPLACE(NVL(U.HOMEFAX, ''), ',', ' ')                                   -- 26. homefax
    || ',' || REPLACE(NVL(U.BEEPER, ''), ',', ' ')                                    -- 27. beeper
    || ',' || REPLACE(NVL(U.MOBILEPHONE, ''), ',', ' ')                               -- 28. mobilephone
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business (개행/콤마 제거)
    || ',' || ''                                                                      -- 30. mngrtype
    || ',' ||  REPLACE(NVL(U.EMAIL, ''), ',', ' ')									  -- user_column1 : ELTR_MLAD 외부메일
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ') 									  -- user_column2 : COMP_TENR 회사전화번호
    || ',' || '0'																	  -- user_column3 :	파견여부(0/1/2 사용안함/유예/사용중)
    || ',' || ''																	  -- user_column4 :	파견부서
    || ',' || CASE 																	
    			WHEN U.DELETED = '0'	THEN '0' 
    			WHEN U.DELETED = '1'	THEN '1' 
    			WHEN U.DELETED = '2'	THEN '2'															 
    			ELSE '0' 
    		  END 																	 -- user_column5 :	근무상태코드 0/1/2(재직/휴직/퇴직)  
    || ',' || CASE 													    
    			WHEN U.DELETED = '1'	THEN '003'
    			WHEN U.DELETED = '2'	THEN '002'
    			ELSE '0'
    		  END																		-- user_column6 :	 WOCO_CODE 원근무상태코드 : 001/002/003(재직/퇴직/휴직)
    || ',' || ''																	  -- user_column7 :	 APNT_TYPE 겸직여부      N (null) : 원직자 , Y:겸직자     
    || ',' || ''																	  -- user_column8 :	겸직사용자의 원 사번																	
    ||',,,,,,,,,,,,'                                                                  -- etc9 ~ etc20 (12개 공란)
    AS csv_row
  FROM MIG1_USER.MG_USER U
 WHERE 1=1
 --AND DELETED = '2' -- 재직 : 0 , 휴직 : 1, 퇴직 : 2
 AND ANOTHERBUSINESSYN = 'N' -- N: 원직자 , Y:겸직자
;
