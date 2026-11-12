-- ====================================================================================================
-- [운영 환경] 00. 운영 결재 테이블 인덱스 일시 무효화 (Make Indexes UNUSABLE)
-- 대상 DBMS : Tibero 7 (TAC 2-node 호환)
-- 목적 : 대량 결재 데이터 이관 적재 전, 인덱스 갱신 부하(Leaf Block Split 및 Random I/O)를 원천 차단하여
--        Direct-Path Insert 적재 속도를 최대 3~10배 가속화합니다.
-- ====================================================================================================

ALTER SESSION ENABLE PARALLEL DDL;

BEGIN
    FOR cur IN (
        SELECT index_name, table_name 
        FROM user_indexes 
        WHERE table_name IN ('APPROVAL', 'SEND', 'PARTICIPANT', 'FLOW', 'DOCUMENT', 'DOCMBR')
          AND status <> 'UNUSABLE'
    ) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER INDEX ' || cur.index_name || ' UNUSABLE';
        EXCEPTION 
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

COMMIT;
