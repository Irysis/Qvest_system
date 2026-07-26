#!/usr/bin/env bash
# _sched_failure_classify.sh — 무인 스케줄러 실패 사유 분류 + 조치 안내 (공통 헬퍼)
#
# 왜 공통인가: alpha_search_queue_run / factor_deep_recheck_run / paper_router_run 이
#   동일한 `grep -qi "spend limit"` 판정을 각자 복사 보유했고, 셋 다 그 하나만 특별취급하고
#   나머지를 exit_N 으로 뭉갰다. 그 결과 **자동복구되는 실패(월 리셋)와 사람이 재인증해야만
#   풀리는 실패(OAuth)가 한 라벨로 묶여**, 경보 문구가 "차기 런에서 재소비됩니다"라고
#   안내하는 동안 무인 alpha-search 가 8일간(07-19~26) 정지했다. 증상은 같고 조치는 정반대다.
#
# 사용:
#   source "$(dirname "${BASH_SOURCE[0]}")/_sched_failure_classify.sh"
#   reason=$(sched_classify_failure "$rc" "$LOG")     # → spend_limit / auth_expired / rate_limit / exit_N
#   guide=$(sched_failure_guidance "$reason")         # → 사람이 읽을 조치 1줄
#   auto=$(sched_failure_autorecovers "$reason")      # → yes / no / unknown
#
# 설계 원칙: **자동복구 여부를 1급 축으로 노출**한다. 이 축이 빠지면 경보가 학습된 무시를 만든다.
# 2026-07-25 신규 (도훈 지시 "모두 다 해결")

# ── 실패 사유 판정 (로그 tail 기반). 우선순위: auth > spend > rate > generic
sched_classify_failure() {
  local rc="${1:-0}" log="${2:-}"
  [ "${rc:-0}" -eq 0 ] && { echo "ok"; return 0; }
  local tail_txt=""
  [ -n "$log" ] && [ -f "$log" ] && tail_txt=$(tail -n 40 "$log" 2>/dev/null)

  # ① 인증 만료 — 사람 개입 없이는 영구 실패. 최우선 판정.
  if printf '%s' "$tail_txt" | grep -qiE "OAuth access token has expired|Re-authenticate to continue|API Error: 401|invalid[_ ]token|unauthorized"; then
    echo "auth_expired"; return 0
  fi
  # ② 구독 한도 — 월 리셋으로 자동 해소 (외생 변수, 아키텍처 게이트 아님)
  if printf '%s' "$tail_txt" | grep -qiE "spend limit|usage limit|credit balance"; then
    echo "spend_limit"; return 0
  fi
  # ③ 레이트 리밋 — 차기 런에서 자동 해소
  if printf '%s' "$tail_txt" | grep -qiE "rate limit|429|too many requests"; then
    echo "rate_limit"; return 0
  fi
  echo "exit_${rc}"
}

# ── 자동복구 여부 (경보 톤을 가르는 축)
sched_failure_autorecovers() {
  case "${1:-}" in
    spend_limit|rate_limit) echo "yes" ;;
    auth_expired)           echo "no"  ;;
    ok)                     echo "n/a" ;;
    *)                      echo "unknown" ;;
  esac
}

# ── 사람이 읽을 조치 안내 1줄
sched_failure_guidance() {
  case "${1:-}" in
    auth_expired) echo "★사람 조치 필요 — 헤드리스 실행용 자격증명이 만료됐고 자동 갱신되지 않습니다. 터미널에서 claude 재로그인 후 차기 런부터 정상화됩니다. 방치하면 무기한 정지." ;;
    spend_limit)  echo "구독 한도 소진 — 월 리셋 시 자동 해소됩니다. 큐 pending 은 보존되어 차기 성공 런에서 재소비됩니다." ;;
    rate_limit)   echo "레이트 리밋 — 차기 런에서 자동 재시도됩니다. 조치 불필요." ;;
    ok)           echo "정상." ;;
    *)            echo "원인 미분류 — 로그 확인 필요. 자동복구 여부 미상이므로 반복 시 수동 점검." ;;
  esac
}

# ── 연속 실패 카운트 (같은 사유 N회 연속 = 학습된 무시 방지용 에스컬레이션)
#    경보 마커 파일명 규칙 {comp}_{reason}_{YYYYMMDD}.alert 를 세어 추정.
sched_failure_streak() {
  local comp="${1:-}" reason="${2:-}" adir="${3:-}"
  [ -z "$adir" ] || [ ! -d "$adir" ] && { echo 0; return 0; }
  ls -1 "$adir"/${comp}_${reason}_*.alert 2>/dev/null | wc -l | tr -d ' '
}

# ── 자격증명 사전 점검 (실행 前 감지 — 실패하고 나서 알리지 말고 미리 알린다)
#    ★토큰 값은 절대 출력하지 않는다. 존재/빈값/만료시각만 판정.
#    반환: ok / no_refresh_token / expired / missing / unknown
sched_check_credentials() {
  local cred="${CLAUDE_CREDENTIALS_PATH:-$HOME/.claude/.credentials.json}"
  local acct="$HOME/.claude.json"
  [ -f "$cred" ] || { echo "missing"; return 0; }
  # ★저장소 분리 감지 (2026-07-26 실사고): 데스크톱 앱은 웹 세션(%APPDATA%/Claude 의 Cookies·
  #   IndexedDB·LocalStorage)에, npm CLI 는 ~/.claude/.credentials.json 에 각각 저장한다.
  #   앱에서 재로그인해도 CLI 토큰은 그대로다 — "재로그인했는데 왜 여전히 401?" 의 정체.
  #   계정 파일(~/.claude.json)만 최신이고 토큰 파일이 낡았으면 이 상태로 단정한다.
  if [ -f "$acct" ] && [ "$acct" -nt "$cred" ]; then
    if grep -qE '"refreshToken"[[:space:]]*:[[:space:]]*""' "$cred" 2>/dev/null; then
      echo "app_login_only"; return 0
    fi
  fi
  # refreshToken 이 빈 문자열이면 자동 갱신 불가 = 만료 즉시 영구 실패 (2026-07 실사고 기전)
  if grep -qE '"refreshToken"[[:space:]]*:[[:space:]]*""' "$cred" 2>/dev/null; then
    echo "no_refresh_token"; return 0
  fi
  local exp_ms exp_s now_s
  exp_ms=$(grep -oE '"expiresAt"[[:space:]]*:[[:space:]]*[0-9]+' "$cred" 2>/dev/null | grep -oE '[0-9]+$' | head -1)
  if [ -n "$exp_ms" ]; then
    exp_s=$(( exp_ms / 1000 )); now_s=$(date +%s)
    [ "$exp_s" -lt "$now_s" ] && { echo "expired"; return 0; }
    echo "ok"; return 0
  fi
  echo "unknown"
}

# ── 경보 본문 주석 조립 (자동복구 축 + 연속실패 에스컬레이션 + 조치 안내) — 3 호출부 공통.
#    ★에스컬레이션이 있어야 "같은 톤 반복 → 학습된 무시"가 끊긴다.
#      실사고: alpha_queue 가 5회 연속 동일 401 경보를 같은 문구로 보내는 동안 8일 방치(07-19~26).
#    streak 은 마커 파일({comp}_{reason}_YYYYMMDD.alert) 일자별 누적 개수로 센다.
SCHED_ESCALATE_AT="${SCHED_ESCALATE_AT:-3}"
sched_failure_annotate() {
  local comp="${1:-}" reason="${2:-}" adir="${3:-}"
  local streak guide auto esc=""
  streak=$(sched_failure_streak "$comp" "$reason" "$adir")
  guide=$(sched_failure_guidance "$reason")
  auto=$(sched_failure_autorecovers "$reason")
  if [ "${streak:-0}" -ge "$SCHED_ESCALATE_AT" ] 2>/dev/null; then
    esc="★${streak}일째 동일 실패 — 자동 해소 기대를 중단하고 수동 개입하십시오. "
  fi
  printf '자동복구=%s | 연속=%s | %s%s' "$auto" "${streak:-0}" "$esc" "$guide"
}

# ── 경보 발행 (마커 + 텔레그램). alpha/paper 의 검증된 scheduler_alert 와 동일 계약.
#    ★기존 2곳의 자체 정의는 건드리지 않는다(작동 중) — 미보유 스크립트만 이 경로를 쓴다.
#    caller 는 BASE / LOG / TODAY 를 정의해 두어야 한다.
sched_alert_emit() {
  local comp="$1" reason="$2" detail="$3"
  local base="${BASE:-${PROJECT:-$PWD}}" today="${TODAY:-$(date +%Y%m%d)}"
  local adir="$base/.cache/scheduler_alerts"; mkdir -p "$adir" 2>/dev/null
  local marker="$adir/${comp}_${reason}_${today}.alert"
  [ -f "$marker" ] && return 0          # 같은 (comp,reason) 1일 1회 스로틀
  {
    echo "ts=$(date -Iseconds)"; echo "component=$comp"; echo "reason=$reason"
    echo "detail=$detail";      echo "log=${LOG:-}"
  } > "$marker"
  local rs; rs="$(command -v Rscript || true)"
  [ -x "$rs" ] || return 0              # Rscript 없으면 마커만 보존(fail-soft)
  local rfile="$adir/_tg_alert_${comp}_${today}.R"
  cat > "$rfile" <<RS
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))
invisible(tryCatch(tg_agent_brief(
  agent = "Q-Lead", title = "무인 스케줄러 경보 — ${comp}",
  relaxed = TRUE, force = TRUE, lock_scope = "sched_${comp}_${reason}_${today}",
  sections = list(
    list(type = "summary", emoji = "\U0001F6A8",
         body = "무인 파이프라인 ${comp} 가 ${reason} 사유로 정지했습니다."),
    list(type = "kv", emoji = "\U0001F4CB", heading = "상세",
         kv = list("구성요소" = "${comp}", "사유" = "${reason}", "내용" = "${detail}"))
  )
), error = function(e) NULL))
RS
  "$rs" "$rfile" >/dev/null 2>&1 || true
}

sched_credentials_guidance() {
  case "${1:-}" in
    app_login_only)   echo "★데스크톱 앱에서만 로그인됨 — 앱(웹 세션)과 npm CLI(~/.claude/.credentials.json)는 저장소가 분리돼 있어 앱 재로그인이 CLI 에 도달하지 않습니다. 반드시 '일반 터미널'에서 CLI 로 로그인하십시오: claude setup-token (완료 확인은 claude -p 왕복으로만 — auth status 는 존재만 검사)." ;;
    no_refresh_token) echo "리프레시 토큰이 비어 있어 자동 갱신 경로가 없습니다 — 액세스 토큰 만료 시 헤드리스 실행이 영구 실패합니다. 일반 터미널에서 claude setup-token 실행 필요." ;;
    expired)          echo "액세스 토큰이 만료됐습니다. claude 재로그인 필요." ;;
    missing)          echo "자격증명 파일이 없습니다. claude 로그인 필요." ;;
    ok)               echo "정상." ;;
    *)                echo "자격증명 상태 판별 불가 — 형식 변경 가능성." ;;
  esac
}
