#!/bin/bash
# ==============================================================================
# [Handy MIG] 마이그레이션 프로세스 비상 강제 종료 및 Hang 복구 도구
# 대상 환경 : Rocky Linux 9.7 / RHEL 9 / macOS
# 용도     : 마이그레이션 프로그램(Java) 구동 중 무한 대기(Hang) 발생 시 원터치 정리
# ==============================================================================

BASE_DIR=$(cd "$(dirname "$0")" && pwd)
PID_FILE="${BASE_DIR}/.mig.pid"

echo "================================================================================"
echo "  🚨 [Handy MIG] 비상 프로세스 강제 종료 및 상태 점검 도구 (Emergency Kill)"
echo "================================================================================"

# 1. 대상 Java 마이그레이션 메인 클래스 목록
TARGET_PATTERNS=(
    "com.handy.mig.TiberoMigRunner"
    "com.handy.mig.FileIntegrityChecker"
    "com.handy.mig.DuplicateAttachmentCleaner"
    "com.handy.mig.OrgCsvExporter"
    "com.handy.mig.BizunitFolderExporter"
    "com.handy.mig.MigStatisticsReporter"
    "com.handy.mig.ApprovalKeyMapper"
)

# 2. 실행 중인 프로세스 탐색
PIDS=()
for pattern in "${TARGET_PATTERNS[@]}"; do
    FOUND=$(pgrep -f "${pattern}")
    if [ -n "$FOUND" ]; then
        for pid in $FOUND; do
            # 자기 자신이나 부모 스크립트 제외
            if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
                PIDS+=("$pid")
            fi
        done
    fi
done

# PID_FILE 검사 보강
if [ -f "$PID_FILE" ]; then
    SAVED_PID=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$SAVED_PID" ] && kill -0 "$SAVED_PID" 2>/dev/null; then
        PIDS+=("$SAVED_PID")
    fi
fi

# 중복 PID 제거
UNIQUE_PIDS=($(printf "%s\n" "${PIDS[@]}" | sort -u))

if [ ${#UNIQUE_PIDS[@]} -eq 0 ]; then
    echo "  [안내] 현재 실행 중인 마이그레이션 프로세스가 없습니다. (정상 상태)"
    echo "================================================================================"
    rm -f "$PID_FILE" 2>/dev/null
    exit 0
fi

echo "  ⚠️ 다음 마이그레이션 프로세스 (${#UNIQUE_PIDS[@]} 개) 가 감지되었습니다:"
echo "--------------------------------------------------------------------------------"
printf "  %-8s %-12s %-10s %s\n" "PID" "USER" "CPU/MEM" "COMMAND"
echo "--------------------------------------------------------------------------------"

for pid in "${UNIQUE_PIDS[@]}"; do
    ps -p "$pid" -o pid,user,%cpu,%mem,args 2>/dev/null | tail -n +2 | while read -r line; do
        echo "  $line"
    done
done
echo "--------------------------------------------------------------------------------"

# 3. 1단계: SIGTERM (15) 부드러운 종료 시도
echo ""
echo ">>> [1단계] 안전 종료 시도 (kill -15)..."
for pid in "${UNIQUE_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        kill -15 "$pid" 2>/dev/null
        echo "    -> PID $pid 에 종료 신호(SIGTERM) 전송 완료"
    fi
done

# 3초간 종료 대기
echo "    -> 프로세스 자원 정리 대기 중 (3초)..."
sleep 3

# 4. 2단계: 여전히 살아있는 프로세스 SIGKILL (9) 강제 사살
STILL_ALIVE=()
for pid in "${UNIQUE_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        STILL_ALIVE+=("$pid")
    fi
done

if [ ${#STILL_ALIVE[@]} -gt 0 ]; then
    echo ""
    echo ">>> [2단계] 미종료 프로세스 강제 즉시 사살 (kill -9)..."
    for pid in "${STILL_ALIVE[@]}"; do
        kill -9 "$pid" 2>/dev/null
        echo "    -> [강제종료] PID $pid 강제 종료 (SIGKILL) 완료"
    done
    sleep 1
fi

# 5. 최종 확인
ALL_DEAD=true
for pid in "${UNIQUE_PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        ALL_DEAD=false
        echo "    [경고] PID $pid 가 아직 종료되지 않았습니다. 수동 확인이 필요합니다."
    fi
done

rm -f "$PID_FILE" 2>/dev/null

echo ""
echo "================================================================================"
if [ "$ALL_DEAD" = true ]; then
    echo "  ✨ [성공] 모든 마이그레이션 프로세스가 깨끗하게 종료되었습니다."
    echo "  ✨ 이제 재실행하거나 다음 작업을 안전하게 수행하실 수 있습니다."
else
    echo "  ⚠️ 일부 프로세스가 아직 남아있을 수 있습니다. 'ps -ef | grep handy' 로 확인하세요."
fi
echo "================================================================================"

# 6. Tibero DB 세션 락/Hang 점검 안내
echo ""
echo "💡 [DBA 팁] 만약 Tibero DB 세션 락(Lock)으로 인한 Hang인 경우:"
echo "   tbsql sys/tibero 접속 후 아래 쿼리로 마이그레이션 세션을 확인/정리할 수 있습니다:"
echo ""
echo "   SELECT SID, SERIAL#, USERNAME, STATUS, PROGRAM, SQL_ID "
echo "     FROM V\$SESSION "
echo "    WHERE PROGRAM LIKE '%java%' OR USERNAME IN ('INTRAWARE', 'MIG1_USER');"
echo ""
echo "   -- 특정 세션 강제 종료 명령:"
echo "   -- ALTER SYSTEM DISCONNECT SESSION 'SID,SERIAL#' IMMEDIATE;"
echo "================================================================================"
