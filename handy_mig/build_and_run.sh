#!/bin/bash
# ====================================================================
# [통합 MIG] 컴파일 및 실행 스크립트 (Rocky Linux 9.7 / JDK 17)
# ====================================================================

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="${BASE_DIR}/bin"
SRC_DIR="${BASE_DIR}/java"
CONFIG_FILE="${BASE_DIR}/config/db.properties"
TARGET_CLASS="${BIN_DIR}/com/handy/mig/TiberoMigRunner.class"

# --------------------------------------------------------------------
# 1. 도움말 출력 함수 (Help Guide)
# --------------------------------------------------------------------
show_help() {
    cat << 'EOF'
================================================================================
 [통합 MIG 도구] 사용법 및 시스템 환경 안내 (Help Guide)
================================================================================

1. 시스템 권장 환경 (System Requirements)
   - 운영체제 (OS) : Rocky Linux 9.7 (또는 RHEL 9 계열)
   - 자바 런타임   : OpenJDK 17.0.19 이상 (Java 17 LTS)
   - 데이터베이스  : Tibero 7 (TAC 2-node 호환)

2. 필수 라이브러리 (Required Libraries)
   * 본 도구는 순수 표준 Java SE JDBC 기술로 작성되어 외부 프레임워크 의존성이 없습니다.
   * 유일한 필수 라이브러리는 Tibero 7 공식 JDBC 드라이버입니다:
     - 파일명: tibero7-jdbc.jar (JDK 11/17 호환 버전 권장)
     - 권장 배치 경로:
       1) ./lib/tibero7-jdbc.jar (권장: handy_mig/lib/ 디렉토리에 복사)
       2) ./tibero7-jdbc.jar
       3) /app/tibero/client/lib/tibero7-jdbc.jar (서버 기본 설치 경로)
       4) /app/tibero7/client/lib/tibero7-jdbc.jar

3. 설정 파일 (Configuration)
   - 경로: config/db.properties
   - 설정 항목: DB URL, 계정/비밀번호, 병렬도, 스토리지 베이스 경로(storage.base.path)

4. 실행 명령어 (Usage)
   -----------------------------------------------------------------------------
   명령어 형식 : ./build_and_run.sh <COMMAND> [ARGUMENTS]
   -----------------------------------------------------------------------------

   [1] 빌드/컴파일 관리:
       ./build_and_run.sh compile (또는 build)
       -> Java 소스 코드를 컴파일하여 bin/ 디렉토리에 클래스 생성 (최초 1회 또는 코드 수정 시)
       ./build_and_run.sh clean
       -> 기존 컴파일된 bin/ 디렉토리 산출물 삭제

   [2] 전체 파이프라인 일괄 실행 (오픈 당일 권장):
       ./build_and_run.sh all
       -> 컴파일 과정 없이 즉시 1단계부터 6단계까지 순차적 고속 실행

   [3] 원문서(ORGAPPRID) 정합성 사전 진단:
       ./build_and_run.sh validate
       -> 실제 이관 전, 원문서 링크율 및 미매핑(000...) 발생 사유 통계 출력

   [4] ⭐ 수신문서 중복 첨부파일 점검 및 디스크 정리 (신규):
       ./build_and_run.sh check-dup
       -> 원기안 첨부를 참조하지 않는 수신 첨부 중복 검사 및 절감 예상 용량 리포트 출력 (안전 모드, 삭제 안 함)
       ./build_and_run.sh clean-dup
       -> 디스크 상의 중복 수신 첨부파일을 실제로 삭제하여 용량 확보 & DB DOCMBR 매핑 자동 정상화

   [5] 개별 단계별 단독 실행 (초고속 즉시 실행):
       ./build_and_run.sh run <SQL_FILE_PATH>

       * 실행 순서별 SQL 파일:
       - 0단계 (인덱스정지) : ./build_and_run.sh run sql/00.DISABLE_OPERATIONAL_INDEXES.sql
       - 1단계 (키 인덱스)  : ./build_and_run.sh run sql/01.MAPPING_KEY_TABLE_CREATE.sql
       - 2단계 (결재문서)   : ./build_and_run.sh run sql/02.APPROVAL_DIRECT_INSERT.sql
       - 3단계 (시행발송)   : ./build_and_run.sh run sql/03.SEND_DIRECT_INSERT.sql
       - 4단계 (결재선)     : ./build_and_run.sh run sql/04.PARTICIPANT_DIRECT_INSERT.sql
       - 5단계 (참여흐름)   : ./build_and_run.sh run sql/05.FLOW_DIRECT_INSERT.sql
       - 6단계 (파일/매핑)  : ./build_and_run.sh run sql/06.DOCUMENT_DOCMBR_DIRECT_INSERT.sql
         (※ 6단계에서 수신문서 첨부 중복 제거 및 스토리지 50% 절감 로직 자동 적용)
       - 7단계 (중복보정)   : ./build_and_run.sh run sql/07.DUPLICATE_ATTACHMENT_CHECK_AND_FIX.sql
       - 8단계 (인덱스재구축) : ./build_and_run.sh run sql/08.REBUILD_OPERATIONAL_INDEXES.sql

   [6] ⭐ 테스트 테이블(_TEST) 전용 안전 모드 (초고속 노인덱스 적재 지원):
       ./build_and_run.sh test-create
       -> _TEST 테이블(6종) 초고속 생성 (인덱스 부하 없는 순수 테이블 모드)
       ./build_and_run.sh test-clean
       -> _TEST 테이블 초고속 초기화 (TRUNCATE: 0.1초 완료)
       ./build_and_run.sh test-all
       -> 생성 -> 고속적재 -> 8단계 병렬 16 인덱스 일괄구축 -> 정합성 리포트까지 원클릭
       ./build_and_run.sh test-verify
       -> _TEST 테이블에 적재된 데이터 건수 및 정합성 리포트 출력
       ./build_and_run.sh test-drop
       -> 테스트 완료 후 _TEST 테이블 완전 삭제 및 DB 자원 환원

   [7] 🔍 운영서버 실제 인덱스 전수 추출 도구 (신규):
       ./build_and_run.sh extract-indexes
       -> 운영 DB에 실제 생성된 결재 인덱스 목록 및 컬럼 구성, DDL 자동 추출/출력

    [8] 🏢 조직도 일괄 추출 및 직접 적재 (신규):
        ./build_and_run.sh export-org [target] [outputDir]
        -> 조직도 8종(부서, 직위, 직급, 사용자, 그룹 등)을 UTF-8 CSV 파일로 일괄 추출 (기본경로: output/csv/)
           (예: ./build_and_run.sh export-org all)
           (예: ./build_and_run.sh export-org user)
        ./build_and_run.sh org-insert
        -> 중간 테이블(MIG1_USER)에서 운영 테이블(INTRAWARE)로 조직도 직접 적재 (00.ORG_DIRECT_INSERT.sql)
        ./build_and_run.sh org-insert-all
        -> ⭐ [ALL-ADD 모드] 부서/사용자 전원 정상(STATUS=1) 선등록 적재 (00.ORG_DIRECT_INSERT_ALL_ADD.sql)
        ./build_and_run.sh update-auth
        -> MIG_AUTH 권한코드 AS-IS 숫자(7105, 2001 등) -> 핸디 표준코드(S1, D1 등) 일괄 보정 (방안 2)
        ./build_and_run.sh org-post-delete
        -> ⭐ 결재문서 이관 완료 후, 폐지부서 및 퇴직자 STATUS = 4 일괄 후처리 (오픈 직전 실행)
        ./build_and_run.sh org-delta-check
        -> ⭐ [D-Day 증가분 진단] 오픈 당일 증가분(ADD/MOD) 사전 감사 및 대상자 명단 조회 (DEL 완전 배제)

     [9] 📁 전자결재 파일 물리 정합성 전수 점검 (신규):
         ./build_and_run.sh check-file [--intraware|--mig1] [--threads=16] [--limit=1000] [--include-hox]
         -> DB(DOCUMENT/DOCMBR) 대비 디스크(NAS) 물리 파일 누락(404) 및 0바이트 전수 검증
         -> ⭐ HOX 002 결재문서는 열람 시 자동 생성되므로 기본 점검 제외 (안전 처리)
         -> 검증 결과 CSV 및 AS-IS 원천 선별 복구 쉘 스크립트(copy_missing_from_asis_*.sh) 자동 생성
            (예: ./build_and_run.sh check-file)
            (예: ./build_and_run.sh check-file --mig1 --threads=32)

    [10] 📑 단위업무 & 기록물철 rtool.sh 연동 및 편철 매핑 (신규):
        ./build_and_run.sh export-rtool [all|bizunit|folder|delta] [outputPath]
        -> 핸디 rtool.sh 규격에 맞춰 부서별 단위업무/기록물철 분할 추출 (기본경로: output/rtool/)
        -> ⭐ 증가분(Delta) 모드 지원: delta, delta-bizunit, delta-folder (DEL 제외, 미등록 건만 추출)
        -> rtool 실행 쉘 자동 생성 (단위업무: -t lb -p <file>, 기록물철: -t al -p <file>)
        -> (예: ./build_and_run.sh export-rtool all)
        -> (예: ./build_and_run.sh export-rtool delta)
        ./build_and_run.sh post-rtool
        -> rtool.sh 완료 후 사후 처리 (명칭 원본 복구 + 전체문서함 매핑 + 결재문서 FOLDERID MERGE)
        ./build_and_run.sh check-unmapped
        -> 미편철/누락 결재문서 전수 감사 및 편철율 리포트 출력

    [11] 📊 이관결과 보고서용 종합 통계 생성 (신규):
        ./build_and_run.sh report [startYear] [endYear] [both|tobe|asis] [outputDir]
        -> 연도별 x 월별(1~12월) 결재문서 생산/이관 피벗 매트릭스 생성 (기본값: 2016 2026)
        -> AS-IS vs TO-BE 1:1 전수 대조 오차(Diff) 검증서 및 문서유형별 통계 산출
        -> 엑셀 즉시 열람 CSV(BOM) 및 브라우저/인쇄용 프리미엄 HTML 리포트 동시 출력
        -> (예: ./build_and_run.sh report)
        -> (예: ./build_and_run.sh report 2016 2026)
        -> (예: ./build_and_run.sh report 2004 2024 tobe output/report)

    [12] 도움말 보기:
        ./build_and_run.sh help  (또는 -h, --help)

5. 실무 운영 팁 (Performance & Operation Tips)
   - 컴파일은 최초 1회(또는 Java 소스 수정 시)만 './build_and_run.sh compile'을
     수행하고, 평상시나 오픈 당일에는 'all' 또는 'run'으로 재컴파일 없이 즉시 실행하십시오.
   - TAC 2-node 환경에서는 노드 간 블록 전송 경합을 방지하기 위해 config/db.properties의
     접속 IP를 특정 노드 1번(VIP)으로 고정하여 실행하십시오.

6. 상세 문서 및 표준 작업 절차서 (Documentation)
   - doc/00.조직도_CSV추출가이드.md : 조직도 8종 CSV 추출 및 일괄등록 표준 절차서
   - doc/01.파일_정합성_점검가이드.md : 전자결재 본문/첨부 물리 정합성 전수 감사 가이드
   - doc/02.단위업무_기록물철_rtool가이드.md : rtool.sh 연동 및 편철 매핑 가이드
   - doc/03.이관통계보고서_생성가이드.md : 4대 종합 이관결과 보고서 및 피벗 통계 생성 가이드
   - doc/운영수행.txt   : 실 운영 환경 표준 작업 절차서 (운영 오픈 D-Day, 고속 적재, 장애 복구 SOP)
   - doc/테스트수행.txt : 테스트 환경 구축, 정합성 판정 기준, 사전 리허설 및 반출 SOP
   - doc/2026-10-13_작업내역.txt : 10/13 일별 작업 내역서 (기초 분석, 키 매핑, 첨부 중복제거 설계)
   - doc/2026-10-14_작업내역.txt : 10/14 일별 작업 내역서 (Fast-Bulk 인덱스 우회, 로거 통합, 파이프라인 완성)
================================================================================
EOF
}

# --------------------------------------------------------------------
# 2. 도움말 매개변수 검사
# --------------------------------------------------------------------
COMMAND=$1
if [ "$COMMAND" = "help" ] || [ "$COMMAND" = "-h" ] || [ "$COMMAND" = "--help" ] || [ -z "$COMMAND" ]; then
    show_help
    exit 0
fi

# --------------------------------------------------------------------
# 3. Tibero JDBC 드라이버 탐색 및 CLASSPATH 설정
# --------------------------------------------------------------------
setup_classpath() {
    TIBERO_JAR=""
    CANDIDATES=(
        "${BASE_DIR}/lib/tibero7-jdbc.jar"
        "${BASE_DIR}/tibero7-jdbc.jar"
        "/app/tibero/client/lib/tibero7-jdbc.jar"
        "/app/tibero7/client/lib/tibero7-jdbc.jar"
    )

    for jar in "${CANDIDATES[@]}"; do
        if [ -f "$jar" ]; then
            TIBERO_JAR="$jar"
            break
        fi
    done

    if [ -z "$TIBERO_JAR" ]; then
        CLASSPATH=".:${BIN_DIR}"
    else
        CLASSPATH=".:${BIN_DIR}:${TIBERO_JAR}"
    fi
}

# --------------------------------------------------------------------
# 4. 컴파일 전담 함수
# --------------------------------------------------------------------
do_compile() {
    setup_classpath
    mkdir -p "${BIN_DIR}"
    echo "[빌드] Java 소스 컴파일 시작 (OpenJDK 17)..."
    javac -encoding UTF-8 -cp "${CLASSPATH}" -d "${BIN_DIR}" ${SRC_DIR}/com/handy/mig/*.java

    if [ $? -ne 0 ]; then
        echo "[오류] 컴파일 실패! Java 소스 코드 또는 JDK(javac) 환경을 확인하세요."
        exit 1
    fi
    echo "[성공] 컴파일 완료 (${BIN_DIR})"
}

# --------------------------------------------------------------------
# 5. 실행 전 클래스 존재 여부 검사 (자동 빌드 안전장치)
# --------------------------------------------------------------------
ensure_compiled() {
    if [ ! -f "${TARGET_CLASS}" ]; then
        echo "[안내] 컴파일된 클래스 파일이 없습니다. 최초 1회 자동 빌드를 진행합니다."
        do_compile
    fi
    setup_classpath
}

# --------------------------------------------------------------------
# 6. 명령어 분기 처리
# --------------------------------------------------------------------
case "$COMMAND" in
    compile|build)
        do_compile
        ;;
    clean)
        echo "[정리] bin/ 디렉토리 산출물 삭제 중..."
        rm -rf "${BIN_DIR}"
        echo "[완료] 정리 완료."
        ;;
    validate)
        ensure_compiled
        echo "[실행] ApprovalKeyMapper (정합성 진단) 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.ApprovalKeyMapper "${CONFIG_FILE}"
        ;;
    check-dup)
        ensure_compiled
        echo "[실행] DuplicateAttachmentCleaner (중복 첨부 검사 모드) 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.DuplicateAttachmentCleaner check "${CONFIG_FILE}"
        ;;
    clean-dup)
        ensure_compiled
        echo "[경고] 실제 디스크 상의 중복 수신 첨부파일 삭제 및 DB 매핑 보정을 시작합니다."
        java -cp "${CLASSPATH}" com.handy.mig.DuplicateAttachmentCleaner delete --fix-db "${CONFIG_FILE}"
        ;;
    run)
        SQL_FILE=$2
        if [ -z "$SQL_FILE" ]; then
            echo "[오류] 실행할 SQL 파일 경로를 지정해 주세요."
            echo "사용법: ./build_and_run.sh run <SQL_FILE_PATH>"
            echo "예시:   ./build_and_run.sh run sql/02.APPROVAL_DIRECT_INSERT.sql"
            exit 1
        fi
        ensure_compiled
        echo "[실행] TiberoMigRunner 즉시 실행 중 (${SQL_FILE})..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "${SQL_FILE}" "${CONFIG_FILE}"
        ;;
    all)
        ensure_compiled
        echo "====================================================================="
        echo " [통합 MIG] 전체 전자결재 파이프라인 일괄 실행 시작 (재컴파일 없이 즉시 구동)"
        echo "====================================================================="
        SQL_LIST=(
            "sql/00.DISABLE_OPERATIONAL_INDEXES.sql"
            "sql/01.MAPPING_KEY_TABLE_CREATE.sql"
            "sql/02.APPROVAL_DIRECT_INSERT.sql"
            "sql/03.SEND_DIRECT_INSERT.sql"
            "sql/04.PARTICIPANT_DIRECT_INSERT.sql"
            "sql/05.FLOW_DIRECT_INSERT.sql"
            "sql/06.DOCUMENT_DOCMBR_DIRECT_INSERT.sql"
            "sql/08.REBUILD_OPERATIONAL_INDEXES.sql"
        )
        for sql in "${SQL_LIST[@]}"; do
            echo ""
            echo ">>> [단계 실행] ${sql}"
            java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "${sql}" "${CONFIG_FILE}"
            if [ $? -ne 0 ]; then
                echo "[오류] ${sql} 실행 중 에러가 발생하여 일괄 작업을 중단합니다."
                exit 1
            fi
        done
        echo ""
        echo "====================================================================="
        echo " [통합 MIG] 전체 파이프라인 정상 완료!"
        echo "====================================================================="
        ;;
    test-create)
        ensure_compiled
        echo "[테스트] _TEST 테이블(6종) 초고속 생성 중 (노인덱스 모드)..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/test/00.CREATE_TEST_TABLES.sql" "${CONFIG_FILE}"
        ;;
    test-clean)
        ensure_compiled
        echo "[테스트] _TEST 테이블 초고속 초기화 중 (TRUNCATE: 인덱스 유지)..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/test/00.TRUNCATE_TEST_TABLES.sql" "${CONFIG_FILE}"
        ;;
    test-all)
        ensure_compiled
        echo "====================================================================="
        echo " [테스트 MIG] _TEST 테이블 대상 전체 테스트 파이프라인 일괄 실행 시작"
        echo "====================================================================="
        TEST_SQL_LIST=(
            "sql/test/00.CREATE_TEST_TABLES.sql"
            "sql/01.MAPPING_KEY_TABLE_CREATE.sql"
            "sql/test/02.APPROVAL_TEST_INSERT.sql"
            "sql/test/03.SEND_TEST_INSERT.sql"
            "sql/test/04.PARTICIPANT_TEST_INSERT.sql"
            "sql/test/05.FLOW_TEST_INSERT.sql"
            "sql/test/06.DOCUMENT_DOCMBR_TEST_INSERT.sql"
            "sql/test/08.CREATE_TEST_INDEXES.sql"
            "sql/test/07.VERIFY_TEST_DATA.sql"
        )
        for sql in "${TEST_SQL_LIST[@]}"; do
            echo ""
            echo ">>> [테스트 단계 실행] ${sql}"
            java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "${sql}" "${CONFIG_FILE}"
            if [ $? -ne 0 ]; then
                echo "[오류] ${sql} 실행 중 에러가 발생하여 테스트를 중단합니다."
                exit 1
            fi
        done
        echo ""
        echo "====================================================================="
        echo " [테스트 MIG] 전체 테스트 파이프라인 및 정합성 검증 완료!"
        echo "====================================================================="
        ;;
    test-verify)
        ensure_compiled
        echo "[테스트] _TEST 테이블 정합성 및 현황 전수 검증 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/test/07.VERIFY_TEST_DATA.sql" "${CONFIG_FILE}"
        ;;
    test-drop)
        ensure_compiled
        echo "[테스트] _TEST 테이블 및 임시 매핑 테이블 완전 삭제 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/test/99.DROP_TEST_TABLES.sql" "${CONFIG_FILE}"
        ;;
    extract-indexes)
        ensure_compiled
        echo "[조회] 운영서버 실제 적용 인덱스 전수 추출 및 DDL 자동 생성 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/tool/01.EXTRACT_PRODUCTION_INDEXES.sql" "${CONFIG_FILE}"
        ;;
    export-org)
        ensure_compiled
        echo "[조직도] E/F CSV 일괄 추출 시작 (UTF-8)..."
        TARGET_SUB="${2:-all}"
        OUTPUT_PATH="${3:-output/csv}"
        java -cp "${CLASSPATH}" com.handy.mig.OrgCsvExporter "${TARGET_SUB}" "${OUTPUT_PATH}"
        ;;
    org-insert)
        ensure_compiled
        echo "[조직도] 운영 테이블(INTRAWARE) 직접 적재 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/00.ORG_DIRECT_INSERT.sql" "${CONFIG_FILE}"
        ;;
    org-insert-all)
        ensure_compiled
        echo "[조직도] 운영 테이블(INTRAWARE) ALL-ADD 직접 적재 실행 중 (전체 정상 '1' 선등록)..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/00.ORG_DIRECT_INSERT_ALL_ADD.sql" "${CONFIG_FILE}"
        ;;
    update-auth)
        ensure_compiled
        echo "[조직도] MIG_AUTH 권한코드 핸디 표준화(S1, D1, Da 등) 보정 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/org/00.MIG_AUTH_CODE_UPDATE.sql" "${CONFIG_FILE}"
        ;;
    check-file)
        ensure_compiled
        TARGET_SCHEMA="${2:---intraware}"
        EXTRA_ARGS="${@:3}"
        echo "[파일점검] 전자결재 본문/첨부 물리 정합성 전수 검증 시작 (${TARGET_SCHEMA})..."
        java -cp "${CLASSPATH}" com.handy.mig.FileIntegrityChecker "${TARGET_SCHEMA}" ${EXTRA_ARGS} "${CONFIG_FILE}"
        ;;
    org-post-delete)
        ensure_compiled
        echo "[조직도 후처리] 결재문서 이관 완료 후 폐지부서 및 퇴직자 STATUS = 4 일괄 처리 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/org/08.ORG_POST_DELETE_UPDATE.sql" "${CONFIG_FILE}"
        ;;
    org-delta-check)
        ensure_compiled
        echo "[조직도 증가분] 오픈 당일 증가분(ADD/MOD) 사전 검증 및 건수 진단 실행 중 (DEL 제외)..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/org/12.DELTA_PRE_CHECK.sql" "${CONFIG_FILE}"
        ;;
    export-rtool)
        ensure_compiled
        echo "[기록물철/단위업무] rtool.sh 부서별 분할 추출 시작..."
        TARGET_SUB="${2:-all}"
        OUTPUT_PATH="${3:-output/rtool}"
        java -cp "${CLASSPATH}" com.handy.mig.BizunitFolderExporter "${TARGET_SUB}" "${OUTPUT_PATH}" "${CONFIG_FILE}"
        ;;
    post-rtool)
        ensure_compiled
        echo "====================================================================="
        echo " [기록물철 후속 처리] 1. 특수문자 및 명칭 원본 복구..."
        echo "====================================================================="
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/folder/01.RESTORE_SPECIAL_CHARS.sql" "${CONFIG_FILE}"
        echo ""
        echo "====================================================================="
        echo " [기록물철 후속 처리] 2. 부서별 전체문서함(8010) 매핑..."
        echo "====================================================================="
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/folder/02.FLDRMBR2_TOTAL_INSERT.sql" "${CONFIG_FILE}"
        echo ""
        echo "====================================================================="
        echo " [기록물철 후속 처리] 3. 결재문서 편철 매핑 및 FOLDERID 업데이트..."
        echo "====================================================================="
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/folder/03.APPROVAL_FOLDER_MERGE.sql" "${CONFIG_FILE}"
        echo ""
        echo "====================================================================="
        echo " [완료] rtool.sh 사후 처리 파이프라인 전체 완료!"
        echo "====================================================================="
        ;;
    check-unmapped)
        ensure_compiled
        echo "[기록물철 감사] 미편철/누락 결재문서 전수 감사 실행 중..."
        java -cp "${CLASSPATH}" com.handy.mig.TiberoMigRunner "sql/folder/04.UNMAPPED_FOLDER_CHECK.sql" "${CONFIG_FILE}"
        ;;
    report)
        ensure_compiled
        START_YEAR="${2:-2016}"
        END_YEAR="${3:-2026}"
        MODE="${4:-both}"
        OUT_DIR="${5:-output/report}"
        echo "[이관통계] 이관결과 보고서 통계 생성 시작 (${START_YEAR}년 ~ ${END_YEAR}년, 모드: ${MODE})..."
        java -cp "${CLASSPATH}" com.handy.mig.MigStatisticsReporter "${START_YEAR}" "${END_YEAR}" "${MODE}" "${OUT_DIR}" "${CONFIG_FILE}"
        ;;
    *)
        echo "[오류] 알 수 없는 명령: ${COMMAND}"
        echo "사용법을 확인하려면 './build_and_run.sh help' 를 실행하세요."
        exit 1
        ;;
esac
