-- ============================================================================
-- [핸디 그룹웨어 10.x 조직도 마이그레이션]
-- 11. 오픈 당일 사용자 증가분(Delta) 추출 (ADD / MODIFY 전용, DEL 완전 배제)
-- 
-- * 목적: 오픈 당일(D-Day) 사전 이관 이후 발생한 '신규 입사자(ADD)' 및 '정보 변경자(MOD: 부서이동, 승진 등)'만 추출
-- * 원칙:
--   1) ⭐ DEL(삭제/퇴직)은 오픈 당일 결재선 장애 방지를 위해 100% 완전 제외 (사후 수작업 처리)
--   2) 정상 재직자(DELETED = 0) 대상만 선별
--   3) 타겟 운영 DB(INTRAWARE.USR_GLOBAL)와 원천(MIG1_USER.MG_USER)을 1:1 비교(Diff)
-- * 추출 대상 파일: user_delta.csv
-- ============================================================================

-- CSV 헤더 (1~2행)
SELECT 'HANDY*GROUPWARE E/F CSV COMMUNITY_ID=001000000 USER INFO VERSION 1.0' AS csv_row
  FROM DUAL

UNION ALL

SELECT '*operation,name,empcode,deptcode,site,posname,rankname,dutyname,password,security,sanclevel,signtype,modifydate,alias,sex,phone,fax,email,homepage,ssn,wedday,birthday,homeaddr,homezip,homephone,homefax,beeper,mobilephone,business,mngrtype,etc1,etc2,etc3,etc4,etc5,etc6,etc7,etc8,etc9,etc10,etc11,etc12,etc13,etc14,etc15,etc16,etc17,etc18,etc19,etc20' AS csv_row
  FROM DUAL

UNION ALL

-- ============================================================================
-- 1. [ADD] 신규 입사자 (핸디에 미존재하는 사번)
-- ============================================================================
SELECT 
    'ADD'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '"', '""')                 -- 2. name
    || ',' || TRIM(NVL(U.EMPCODE, U.USER_ID))                                         -- 3. empcode
    || ',' || TRIM(U.DEPTCODE)                                                        -- 4. deptcode
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname
    || ',' || NVL(U.PASSWORD, '')                                                     -- 9. password
    || ',' || NVL(TO_CHAR(U.SECURITY), '100')                                         -- 10. security
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '100')                                        -- 11. sanclevel
    || ',' || '1'                                                                     -- 12. signtype
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS')            -- 13. modifydate
    || ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ')                                     -- 14. alias
    || ',' || NVL(U.SEX, '0')                                                         -- 15. sex
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax
    || ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email
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
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business
    || ',' || ''                                                                      -- 30. mngrtype
    || ',,,,,,,,,,,,,,,,,,,,'                                                         -- etc1 ~ etc20
    AS csv_row
  FROM MIG1_USER.MG_USER U
 WHERE NVL(U.DELETED, 0) = 0
   AND NOT EXISTS (
       SELECT 1 
         FROM INTRAWARE.USR_GLOBAL UG 
        WHERE UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))
   )

UNION ALL

-- ============================================================================
-- 2. [MODIFY] 정보 변경 사용자 (부서 이동, 직위/직급 승진, 직책 변동 등)
-- ============================================================================
SELECT 
    'MODIFY'                                                                             -- 1. operation
    || ',' || REPLACE(REPLACE(NVL(U.NAME, ' '), ',', ' '), '"', '""')                 -- 2. name
    || ',' || TRIM(NVL(U.EMPCODE, U.USER_ID))                                         -- 3. empcode
    || ',' || TRIM(U.DEPTCODE)                                                        -- 4. deptcode (새 부서코드 반영!)
    || ',' || 'site'                                                                  -- 5. site
    || ',' || REPLACE(NVL(U.POSNAME, '미지정'), ',', ' ')                             -- 6. posname (새 직위)
    || ',' || REPLACE(NVL(U.RANKNAME, ''), ',', ' ')                                  -- 7. rankname (새 직급)
    || ',' || REPLACE(NVL(U.DUTYNAME, ''), ',', ' ')                                  -- 8. dutyname (새 직책)
    || ',' || NVL(U.PASSWORD, '')                                                     -- 9. password
    || ',' || NVL(TO_CHAR(U.SECURITY), '100')                                         -- 10. security
    || ',' || NVL(TO_CHAR(U.SANCLEVEL), '100')                                        -- 11. sanclevel
    || ',' || '1'                                                                     -- 12. signtype
    || ',' || TO_CHAR(NVL(U.MODIFYDATE, SYSDATE), 'YYYY-MM-DD HH24:MI:SS')            -- 13. modifydate
    || ',' || REPLACE(NVL(U.ALIAS, ''), ',', ' ')                                     -- 14. alias
    || ',' || NVL(U.SEX, '0')                                                         -- 15. sex
    || ',' || REPLACE(NVL(U.PHONE, ''), ',', ' ')                                     -- 16. phone
    || ',' || REPLACE(NVL(U.FAX, ''), ',', ' ')                                       -- 17. fax
    || ',' || REPLACE(NVL(U.EMAIL, ''), ',', ' ')                                     -- 18. email
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
    || ',' || REPLACE(REPLACE(REPLACE(NVL(U.BUSINESS, ''), ',', ' '), CHR(13), ''), CHR(10), '') -- 29. business
    || ',' || ''                                                                      -- 30. mngrtype
    || ',,,,,,,,,,,,,,,,,,,,'                                                         -- etc1 ~ etc20
    AS csv_row
  FROM MIG1_USER.MG_USER U
  JOIN INTRAWARE.USR_GLOBAL UG
    ON UG.EMP_CODE = TRIM(NVL(U.EMPCODE, U.USER_ID))
  LEFT JOIN INTRAWARE.DEPT_GLOBAL DG
    ON UG.DEPT_ID = DG.DEPT_ID
 WHERE NVL(U.DELETED, 0) = 0
   AND (
       -- 소속 부서코드 변경 (부서이동/전출입)
       NVL(TRIM(DG.DEPT_CODE), ' ') <> TRIM(U.DEPTCODE)
       -- 직위 변경
       OR NVL(TRIM(UG.POS_NAME), ' ') <> NVL(TRIM(U.POSNAME), ' ')
       -- 직급 변경
       OR NVL(TRIM(UG.RANK_NAME), ' ') <> NVL(TRIM(U.RANKNAME), ' ')
       -- 직책 변경
       OR NVL(TRIM(UG.DUTY_NAME), ' ') <> NVL(TRIM(U.DUTYNAME), ' ')
       -- 성명 변경
       OR TRIM(UG.NAME) <> TRIM(U.NAME)
       -- 연락처 변경 (핸드폰, 이메일, 전화)
       OR NVL(TRIM(UG.MOBILE_PHONE), ' ') <> NVL(TRIM(U.MOBILEPHONE), ' ')
       OR NVL(TRIM(UG.E_MAIL), ' ') <> NVL(TRIM(U.EMAIL), ' ')
       OR NVL(TRIM(UG.PHONE), ' ') <> NVL(TRIM(U.PHONE), ' ')
   );
