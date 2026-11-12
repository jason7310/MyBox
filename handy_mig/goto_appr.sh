#!/bin/bash
# ==============================================================================
# [Handy 10.x] 결재 문서 ID(APPROVALID) 기반 스토리지 디렉토리 자동 이동 유틸리티
# 
# * 목적: APPROVALID 또는 OBJECTID를 입력받아 핸디 표준 sancbox 공식 경로를 
#         자동 계산하고 해당 물리 디렉토리로 즉시 이동(cd)합니다.
#
# * 핸디 표준 sancbox 경로 공식:
#   - YYYY = 2000 + SUBSTR(id, 6, 2)
#   - DDD  = SUBSTR(id, 8, 3) (줄리안 데이 / 연중 일차)
#   - MM, DD = DDD를 윤년 산출식으로 변환 (1~12, 1~31)
#   - NUM  = TO_NUMBER(SUBSTR(id, 15, 3))
#   - 공식 디렉토리: {basePath}/hoffice/sancbox/{YYYY}/{MM}/{DD}/{NUM}
#
# * 사용 방법:
#   1) 현재 쉘에서 바로 이동 (가장 권장):
#      source ./goto_appr.sh <APPROVALID>
#      . ./goto_appr.sh <APPROVALID>
#
#   2) cd 명령어로 이동:
#      cd $(./goto_appr.sh -p <APPROVALID>)
#
#   3) ~/.bashrc 등록 후 전역 명령어(cdappr)로 사용:
#      source ./goto_appr.sh --install
#      cdappr <APPROVALID>
# ==============================================================================

# 스크립트가 source 로 실행되었는지 여부 확인
is_sourced() {
    if [ -n "$ZSH_VERSION" ]; then
        case "$ZSH_EVAL_CONTEXT" in *:file) return 0;; esac
    else
        case "${0##*/}" in bash|sh|zsh) return 0;; esac
        [ "$0" != "$BASH_SOURCE" ] && return 0
    fi
    return 1
}

# 1. 줄리안 데이(DDD) -> MM, DD 변환 (Pure Bash / 초고속)
calc_month_day() {
    local year=$1
    local ddd=$((10#$2))
    local leap=0

    # 윤년 판별
    if (( (year % 400 == 0) || (year % 4 == 0 && year % 100 != 0) )); then
        leap=1
    fi

    local days_in_month=(31 $((28 + leap)) 31 30 31 30 31 31 30 31 30 31)
    local m=1
    for dim in "${days_in_month[@]}"; do
        if (( ddd <= dim )); then
            echo "$m $ddd"
            return 0
        fi
        (( ddd -= dim ))
        (( m++ ))
    done
    echo "1 1"
    return 1
}

# 2. 메인 이동 함수 정의
goto_appr() {
    local PATH_ONLY=0
    local TARGET_ID=""

    # 옵션 처리
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--path|--print)
                PATH_ONLY=1
                shift
                ;;
            --install)
                local SCRIPT_PATH
                SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/$(basename "${BASH_SOURCE[0]:-$0}")"
                echo "alias cdappr='source \"$SCRIPT_PATH\"'" >> ~/.bashrc
                echo "alias cdappr='source \"$SCRIPT_PATH\"'" >> ~/.zshrc 2>/dev/null || true
                echo "[성공] ~/.bashrc 에 'cdappr' 명령어가 등록되었습니다."
                echo "다음 명령을 실행하거나 터미널을 다시 여십시오:"
                echo "  source ~/.bashrc"
                echo "사용법: cdappr <APPROVALID>"
                return 0 2>/dev/null || exit 0
                ;;
            -h|--help)
                echo "사용법:"
                echo "  source $0 <APPROVALID>       (현재 쉘에서 직접 디렉토리로 이동)"
                echo "  $0 -p <APPROVALID>           (계산된 경로만 출력)"
                echo "  $0 --install                 (~/.bashrc 에 cdappr 명령어로 등록)"
                echo "예시:"
                echo "  source $0 HND01230450001001"
                return 0 2>/dev/null || exit 0
                ;;
            *)
                if [ -z "$TARGET_ID" ]; then
                    TARGET_ID="$1"
                fi
                shift
                ;;
        esac
    done

    # 입력 검증
    if [ -z "$TARGET_ID" ]; then
        if (( PATH_ONLY == 0 )); then
            echo "❌ [오류] APPROVALID(또는 OBJECTID)를 입력하십시오."
            echo "   사용법: source $0 <APPROVALID>"
            echo "   예  시: source $0 HND01230450001001"
        fi
        return 1 2>/dev/null || exit 1
    fi

    # 공백 제거 및 대문자 변환
    TARGET_ID=$(echo "$TARGET_ID" | tr -d ' ' | tr '[:lower:]' '[:upper:]')

    # 최소 길이 점검 (APPROVALID는 통상 17자리 이상)
    if [ ${#TARGET_ID} -lt 17 ]; then
        if (( PATH_ONLY == 0 )); then
            echo "❌ [오류] ID 길이가 너무 짧습니다. (최소 17자리 필요: ${TARGET_ID})"
        fi
        return 1 2>/dev/null || exit 1
    fi

    # 3. 파싱 (핸디 공식)
    # 접두사 5자리 이후 6~7번째: YY
    local yy_str="${TARGET_ID:5:2}"
    # 8~10번째: DDD
    local ddd_str="${TARGET_ID:7:3}"
    # 15~17번째: NUM
    local num_str="${TARGET_ID:14:3}"

    # 숫자 유효성 검사
    if ! [[ "$yy_str" =~ ^[0-9]+$ ]] || ! [[ "$ddd_str" =~ ^[0-9]+$ ]] || ! [[ "$num_str" =~ ^[0-9]+$ ]]; then
        if (( PATH_ONLY == 0 )); then
            echo "❌ [오류] APPROVALID 날짜/순번 영역에 숫자가 아닌 문자가 포함되어 있습니다: ${TARGET_ID}"
        fi
        return 1 2>/dev/null || exit 1
    fi

    local year=$((2000 + 10#$yy_str))
    local sub_num=$((10#$num_str))

    read -r mm dd < <(calc_month_day "$year" "$ddd_str")

    local rel_path="${year}/${mm}/${dd}/${sub_num}"

    # 4. 베이스 경로 결정 (config/db.properties 탐색 -> 기본값 /data)
    local base_path="/data"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
    local cfg_file="${script_dir}/config/db.properties"
    if [ ! -f "$cfg_file" ]; then
        cfg_file="${script_dir}/../config/db.properties"
    fi

    if [ -n "$STORAGE_BASE_PATH" ]; then
        base_path="$STORAGE_BASE_PATH"
    elif [ -f "$cfg_file" ]; then
        local prop_val
        prop_val=$(grep -E '^[[:space:]]*storage\.base\.path[[:space:]]*=' "$cfg_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r' | tr -d ' ')
        if [ -n "$prop_val" ]; then
            base_path="$prop_val"
        fi
    fi

    # 5. 디렉토리 후보군 우선순위 검사
    local candidate_dirs=(
        "${base_path}/hoffice/sancbox/${rel_path}"
        "${base_path}/sancbox/${rel_path}"
        "/data/hoffice/sancbox/${rel_path}"
        "/data/sancbox/${rel_path}"
        "/app/hso10/hoffice/sancbox/${rel_path}"
        "/home/handy/hoffice/sancbox/${rel_path}"
        "${base_path}/${rel_path}"
    )

    local target_dir=""
    for cdir in "${candidate_dirs[@]}"; do
        if [ -d "$cdir" ]; then
            target_dir="$cdir"
            break
        fi
    done

    # 물리 디렉토리가 아직 없으면 표준 1순위 경로로 지정
    if [ -z "$target_dir" ]; then
        target_dir="${candidate_dirs[0]}"
    fi

    # 경로만 출력하는 옵션인 경우
    if (( PATH_ONLY == 1 )); then
        echo "$target_dir"
        return 0 2>/dev/null || exit 0
    fi

    # 6. 상세 안내 및 이동
    echo "=============================================================================="
    echo "📂 [Handy Sancbox] 결재 문서 디렉토리 이동기"
    echo "=============================================================================="
    echo " ▶ APPROVALID  : ${TARGET_ID}"
    echo " ▶ 기준 일자   : ${year}년 ${mm}월 ${dd}일 (연중 ${ddd_str}일차)"
    echo " ▶ 순번(NUM)   : ${sub_num}"
    echo " ▶ 대상 디렉토리: ${target_dir}"
    echo "------------------------------------------------------------------------------"

    if [ ! -d "$target_dir" ]; then
        echo " ⚠️  [알림] 해당 물리 디렉토리가 현재 서버 디스크에 존재하지 않습니다."
        echo "     (아직 파일 이관 전이거나 다른 스토리지 마운트 포인트일 수 있습니다.)"
        echo "     계산된 디렉토리 경로: ${target_dir}"
        echo "------------------------------------------------------------------------------"
    fi

    # source 로 호출된 경우 직접 cd 수행
    if is_sourced; then
        if [ -d "$target_dir" ]; then
            cd "$target_dir" || return 1
            echo " ✅ [이동 완료] 현재 디렉토리: $(pwd)"
            echo ""
            echo " 📄 [해당 문서 관련 파일 목록]"
            local file_matches
            file_matches=$(ls -lh *"${TARGET_ID:0:17}"* 2>/dev/null || true)
            if [ -n "$file_matches" ]; then
                echo "$file_matches"
            else
                echo "   (현재 디렉토리에 ${TARGET_ID:0:17} 관련 파일이 없습니다.)"
                echo "   전체 파일 수: $(ls -1 2>/dev/null | wc -l) 개"
            fi
        else
            echo " ℹ️  디렉토리가 없으므로 위치를 이동하지 않았습니다."
        fi
    else
        # 서브쉘로 실행된 경우
        echo " 💡 [안내] 쉘 스크립트가 직접 실행(./)되어 부모 터미널의 위치는 유지됩니다."
        echo ""
        echo " 👉 현재 터미널에서 바로 이동하려면 아래 명령을 사용하십시오:"
        echo "    source $0 ${TARGET_ID}"
        echo "    또는"
        echo "    cd \"${target_dir}\""
        echo ""
        echo " 👉 영구 등록하여 사용하기:"
        echo "    $0 --install"
        echo "    이후 어디서나: cdappr ${TARGET_ID}"
    fi
    echo "=============================================================================="
}

# 실행
goto_appr "$@"
