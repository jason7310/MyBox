-- ====================================================================================================
-- [운영 환경] 08. 운영 결재 테이블 인덱스 일괄 병렬 고속 리빌드 (Rebuild Operational Indexes)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 데이터 적재가 완료된 후, UNUSABLE 상태인 모든 인덱스를 16개 병렬 프로세스로
--        메모리 일괄 정렬하여 고속 재구축하고 최종 운영 상태(LOGGING, NOPARALLEL)로 복원합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DDL;

BEGIN
    FOR cur IN (
        SELECT index_name, table_name 
        FROM user_indexes 
        WHERE table_name IN ('APPROVAL', 'SEND', 'PARTICIPANT', 'FLOW', 'DOCUMENT', 'DOCMBR')
    ) LOOP
        BEGIN
            -- 1단계: 병렬 16 + NOLOGGING으로 초고속 일괄 재구축
            EXECUTE IMMEDIATE 'ALTER INDEX ' || cur.index_name || ' REBUILD PARALLEL 16 NOLOGGING';
            -- 2단계: 운영 모드로 원복
            EXECUTE IMMEDIATE 'ALTER INDEX ' || cur.index_name || ' NOPARALLEL LOGGING';
        EXCEPTION 
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

COMMIT;
