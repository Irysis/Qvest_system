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
  # ★로그는 당일 append-only 라 과거 실행의 실패 문구가 그대로 남는다.
  #   구현이 tail 전체를 우선순위로만 훑어, **이미 해소된 과거 오류가 현재 실패를 가린다**.
  #   실사고(2026-07-26 18:17): 현재 원인은 spend limit 인데 15:38 의 401 이 먼저 매칭돼
  #   auth_expired 로 오분류 → "재인증하십시오"라는 정반대 조치를 안내했다.
  #   ∴ 마지막 실행 구간(가장 최근 시작 마커 이후)만 본다. 마커가 없으면 짧은 꼬리로 제한.
  local tail_txt=""
  if [ -n "$log" ] && [ -f "$log" ]; then
    tail_txt=$(awk '/\[(alpha_queue|router|recheck)\] (start|trigger)/{buf=""} {buf=buf $0 ORS} END{printf "%s", buf}' "$log" 2>/dev/null)
    [ -z "$tail_txt" ] && tail_txt=$(tail -n 15 "$log" 2>/dev/null)
  fi

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
  # ④ 시간초과 강제종료 (`timeout N claude -p` 가 벽시계로 SIGTERM) — 종료코드 124.
  #   ★위 ①~③ 은 이 경우 **원리적으로 발화할 수 없다**: `claude -p` 는 기본 출력형식에서
  #     최종 메시지를 런 끝에 1회만 flush 하는데, 그 전에 죽으므로 로그에 claude 출력이
  #     한 줄도 남지 않는다(실측: 08-09 런 50분간 로그 증가분 0바이트).
  #     그래서 구판은 전부 generic `exit_124` → 안내가 "원인 미분류 — 로그 확인 필요" 였고,
  #     **가리키는 그 로그가 구조적으로 비어 있다**. 사람이 확인해도 얻을 게 없는 안내 =
  #     침묵 실패 계통("존재하는 진단 경로가 사실은 죽어 있다").
  #   ∴ 로그를 뒤지지 말고 종료코드로 판정한다. 원인은 코드 자체가 말하고 있다.
  #   ⚠ 순서 주의: 한도/인증이 먼저 걸려 hang 한 뒤 timeout 난 경우는 ①~③ 이 이미 잡는다
  #     (그 문구는 kill 이전에 이미 로그에 있다). 여기는 그 뒤의 폴백이다.
  if [ "${rc:-0}" -eq 124 ]; then
    echo "timeout_kill"; return 0
  fi
  echo "exit_${rc}"
}

# ── 자동복구 여부 (경보 톤을 가르는 축)
sched_failure_autorecovers() {
  case "${1:-}" in
    spend_limit|rate_limit) echo "yes" ;;
    auth_expired)           echo "no"  ;;
    # ★partial: 큐 pending 은 보존돼 차기 런이 재시도하지만, kill 시점에 **이미 끝난 항목의
    #   원장 append·텔레그램은 유실**된다(실행됐는데 pending 으로 남는 상태). 완전 자동복구가
    #   아니므로 yes 로 뭉개지 않는다 — yes 로 적으면 학습된 무시를 만든다.
    timeout_kill)           echo "partial" ;;
    ok)                     echo "n/a" ;;
    *)                      echo "unknown" ;;
  esac
}

# ── 사람이 읽을 조치 안내 1줄
sched_failure_guidance() {
  case "${1:-}" in
    auth_expired) echo "★사람 조치 필요 — 헤드리스 실행용 자격증명이 만료됐고 자동 갱신되지 않습니다. 터미널에서 claude 재로그인 후 차기 런부터 정상화됩니다. 방치하면 무기한 정지." ;;
    spend_limit)  echo "사용률 한도 소진으로 정지했습니다. 큐 pending 은 보존됩니다 — 재충전 후 도훈이 재개시키면 그대로 소비됩니다. (2026-07-26 도훈 지시: 한도 기반 자동 재시도·감축·보류는 두지 않음)" ;;
    rate_limit)   echo "레이트 리밋으로 정지했습니다. 큐는 보존되며, 재개는 수동입니다." ;;
    timeout_kill) echo "벽시계 시간초과(timeout 3000s)로 강제 종료됐습니다 — 한도·인증 문제가 아닙니다. 런은 살아서 일하던 중이었고, 끝낸 항목이 있어도 **원장 append·텔레그램이 유실**됩니다. 확인 순서: ①stage_artifacts/paper_recharge/auto_verify_*_<TODAY>.json 중 done 원장에 없는 건(=실행됐는데 pending) ②그 건을 원장에 소급 기록 ③반복되면 MAX_ALPHA 하향 또는 timeout 상향(도훈 결정 — 리서치 처리량 정책)." ;;
    ok)           echo "정상." ;;
    *)            echo "원인 미분류 — 로그 확인 필요. 자동복구 여부 미상이므로 반복 시 수동 점검." ;;
  esac
}

# ── (2026-07-26 도훈 지시로 제거) 사용률 창 사전 점검·예측·보류/감축
#    "한도소비 관련한 제약사항들, 방어형 조건들 모두 없애. 한도 소비하면 재충전 후 내가 재개"
#    ★기존 mandate 재확인: [[feedback-spend-limit-external-not-gate]] — 지출한도는 구독 외생
#      변수이지 아키텍처 게이트가 아니다. 한도를 관리 변수로 재취급 금지.
#      오늘(07-26) 내가 그 mandate 를 어기고 보류·감축 게이트를 만들었다가 되돌린다.
#    유지되는 것: 실패 사유 분류(진단) + 경보 발행(도훈이 재개 시점을 알기 위해).

# ── 사유별 당일 재시도 상한
#    (2026-07-26 도훈 지시) 한도 관련 특별취급 제거 — spend_limit/rate_limit 을
#    다른 실패와 구분해 상한·대기를 두던 로직을 없앤다. 한도 소진 시 그냥 멈추고,
#    재충전 후 도훈이 재개시킨다. 재시도는 크래시 등 일반 실패에만 남긴다.
sched_retry_cap() {
  case "${1:-}" in
    spend_limit|spend_limit_fallback_*|rate_limit) echo 0 ;;   # 한도 = 재시도 안 함(수동 재개)
    auth_expired|credentials_*)                    echo 1 ;;   # 사람 조치 후 1회
    count_measurement_failed)                      echo 1 ;;
    *)                                             echo 3 ;;   # 크래시·미분류
  esac
}

# 재시도 대기 간격 — 한도 특별취급 제거로 전 사유 0(대기 없음).
sched_retry_backoff_sec() { echo 0; }

# ── 연속 실패 카운트 (같은 사유 N회 연속 = 학습된 무시 방지용 에스컬레이션)
#    경보 마커 파일명 규칙 {comp}_{reason}_{YYYYMMDD}.alert 를 세어 추정.
#    ★전기간 개수가 아니라 **오늘부터 거꾸로 이어지는 연속 일수**를 센다.
#      전기간 합계로 세면 이미 해소된 과거 실패(예: 07-19~24 401, 07-26 해소)가 영구히
#      남아 가짜 격상 경보를 만든다 — "해소됐는데 3일째 실패" 같은 거짓말.
#      연속이 끊기면(하루라도 마커 없음) 자동으로 0 이 되므로 별도 만료 처리가 불필요하다.
sched_failure_streak() {
  local comp="${1:-}" reason="${2:-}" adir="${3:-}"
  { [ -z "$adir" ] || [ ! -d "$adir" ]; } && { echo 0; return 0; }
  # ★별칭 인지 (2026-08-09): 사유 개명 직후 streak 이 0 으로 떨어지는 것을 막는다.
  #   실측 결함: recent_count 에만 별칭을 넣었더니 같은 날 경보가 "연속=0 | 최근14일=6회" 로
  #   서로 다른 것을 말했다 — 두 축이 다른 규약 위에 서 있으면 읽는 사람이 어느 쪽도 못 믿는다.
  #   ⚠ 공유하는 건 **철자**뿐이다. streak 은 _resolved/ 를 보지 않는다 — 성공이 해소를
  #     뜻한다는 streak 고유 의미는 그대로 둔다(그래서 recent_count 와 값이 갈리는 게 정상).
  local aliases; aliases=$(sched_reason_aliases "$reason")
  local n=0 i=0 d r hit
  while [ "$i" -lt 60 ]; do            # 최대 60일 역추적 (무한루프 방지)
    d=$(date -d "-${i} day" +%Y%m%d 2>/dev/null) || break
    hit=0
    for r in $aliases; do
      [ -f "$adir/${comp}_${r}_${d}.alert" ] && { hit=1; break; }
    done
    if [ "$hit" -eq 1 ]; then
      n=$((n + 1))
    elif [ "$i" -gt 0 ]; then
      break                            # 오늘 마커는 아직 없을 수 있으니 i=0 만 관대하게
    fi
    i=$((i + 1))
  done
  echo "$n"
}

# ── 간헐 재발 횟수 (연속 streak 이 못 보는 축, 2026-08-09 신설)
#   ★streak 은 **연속 일수**만 센다. 그런데 성공 1회가 sched_mark_resolved 로 과거 마커를
#     _resolved/ 로 옮기므로, 하루걸러 재발하는 간헐 실패는 **영원히 연속=1** 로 보고되고
#     SCHED_ESCALATE_AT 에 절대 도달하지 못한다.
#     실측(2026-08-09): alpha_queue exit_124 가 07-27·08-04·08-06·08-07·08-08·08-09 로
#     14일 중 6회인데 경보는 매번 "연속=1" — 재발이 통계적으로 보이지 않았다.
#   ∴ 후행 N일 창에서 (comp, reason) 마커 **개수**를 센다. _resolved/ 아카이브도 포함해야
#     "성공이 역사를 지우는" 위 기전을 피한다.
#   ★별칭: 사유 이름이 바뀌어도 역사가 끊기지 않도록 구 이름을 함께 센다.
# ★사유 이름 별칭 — **여기가 유일 정의**. 소비자(streak/recent_count)는 이 함수를 부른다.
#   같은 표를 두 곳에 적으면 한쪽만 갱신돼 조용히 갈라진다(이 저장소가 반복해서 물린 계통).
#   목적: 사유를 개명해도 **역사가 끊기지 않는 것**. streak/recent 는 라벨의 철자가 아니라
#   같은 실패를 세야 한다 — 개명일 전후로 카운터가 0 으로 떨어지면 그건 결함 소멸이 아니라
#   계측 단절이다.
sched_reason_aliases() {
  case "${1:-}" in
    timeout_kill) echo "timeout_kill exit_124" ;;   # 2026-08-09 개명
    *)            echo "${1:-}" ;;
  esac
}

SCHED_RECENT_WINDOW_DAYS="${SCHED_RECENT_WINDOW_DAYS:-14}"
sched_failure_recent_count() {
  local comp="${1:-}" reason="${2:-}" adir="${3:-}"
  { [ -z "$adir" ] || [ ! -d "$adir" ]; } && { echo 0; return 0; }
  local aliases; aliases=$(sched_reason_aliases "$reason")
  local n=0 i=0 d r
  while [ "$i" -lt "$SCHED_RECENT_WINDOW_DAYS" ]; do
    d=$(date -d "-${i} day" +%Y%m%d 2>/dev/null) || break
    for r in $aliases; do
      if [ -f "$adir/${comp}_${r}_${d}.alert" ] || [ -f "$adir/_resolved/${comp}_${r}_${d}.alert" ]; then
        n=$((n + 1)); break
      fi
    done
    i=$((i + 1))
  done
  echo "$n"
}

# ── 자격증명 사전 점검 (실행 前 감지 — 실패하고 나서 알리지 말고 미리 알린다)
#    ★토큰 값은 절대 출력하지 않는다. 존재/빈값/만료시각만 판정.
#    반환: ok / no_refresh_token / expired / missing / unknown
# ── env 토큰 사용기간 추적 (2026-07-26 ② — 만료 선제 감지)
#    setup-token 산출 토큰은 파일과 달리 expiresAt 이 없어 **만료를 미리 알 수 없다**.
#    실패해야 알게 되는 구조라 8일 침묵이 재발할 수 있다 → 지문(sha256 앞 12자)으로
#    "언제부터 이 토큰을 쓰고 있나"를 기록해 경과일로 사전 경고한다.
#    ★토큰 값 자체는 저장하지 않는다. 지문만.
SCHED_TOKEN_WARN_DAYS="${SCHED_TOKEN_WARN_DAYS:-75}"
sched_token_age_days() {
  local tok="${CLAUDE_CODE_OAUTH_TOKEN:-}"
  [ -n "$tok" ] || { echo -1; return 0; }
  # ★상태파일 위치가 호출 경로마다 갈리면 매번 "신규 토큰"으로 판정돼 경과일이 영원히 0 이 되고
  #   감시가 조용히 죽는다(2026-07-26 실측: QM_ROOT 있음→프로젝트/.cache, 없음→$HOME/.cache).
  #   resolve_project.sh 가 세우는 BASE/PROJECT 를 중간 폴백으로 넣어 단일 위치로 수렴시킨다.
  local root="${QM_ROOT:-${BASE:-${PROJECT:-${CLAUDE_PROJECT_DIR:-$HOME}}}}"
  local state="$root/.cache/token_state.json"
  local fp; fp=$(printf '%s' "$tok" | sha256sum 2>/dev/null | cut -c1-12)
  [ -n "$fp" ] || { echo -1; return 0; }
  local now; now=$(date +%s)
  local prev_fp prev_ts
  if [ -f "$state" ]; then
    prev_fp=$(grep -oE '"fingerprint"[[:space:]]*:[[:space:]]*"[^"]*"' "$state" 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/')
    prev_ts=$(grep -oE '"first_seen_epoch"[[:space:]]*:[[:space:]]*[0-9]+' "$state" 2>/dev/null | grep -oE '[0-9]+$')
  fi
  if [ "$prev_fp" != "$fp" ] || [ -z "${prev_ts:-}" ]; then
    mkdir -p "$(dirname "$state")" 2>/dev/null
    printf '{\n  "_doc": "env 토큰 사용기간 추적 — 값 미저장, sha256 앞 12자 지문만. 생성 _sched_failure_classify.sh",\n  "fingerprint": "%s",\n  "first_seen_epoch": %s,\n  "first_seen": "%s"\n}\n' \
      "$fp" "$now" "$(date '+%Y-%m-%d %H:%M:%S')" > "$state" 2>/dev/null
    echo 0; return 0
  fi
  echo $(( (now - prev_ts) / 86400 ))
}

# (2026-07-26) 프로세스 env ← User 스코프 브리지.
#   기전: `setx` 는 **User 환경 레지스트리**에 쓴다. 그 시점에 *이미 떠 있던* 프로세스는
#   낡은 환경을 그대로 들고 있고, 그 자식 셸도 마찬가지다. 그래서 같은 머신에서
#     · Task Scheduler 가 새로 띄운 작업 → 토큰 상속됨 → 정상 (21:05 alpha_queue 성공)
#     · 기존 앱에서 파생된 셸        → 토큰 없음   → ~/.claude/.credentials.json 로 폴백
#   으로 갈린다. 그 파일은 refreshToken="" + 17일 전 만료 상태라 즉시 401 이고,
#   메시지는 "Re-authenticate to continue" 라 **이미 재인증한 사용자를 다시 재인증으로 보낸다**.
#   ∴ env 가 비었으면 User 스코프에서 끌어와 이 프로세스에만 export 한다.
#   ★토큰 값은 로그·파일·stdout 어디에도 쓰지 않는다(지문만). 실패해도 조용히 통과 —
#     여기서 막으면 원래 정상인 파일-인증 구성까지 죽는다.
sched_resolve_oauth_token() {
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && return 0
  [ -n "${ANTHROPIC_API_KEY:-}" ] && return 0
  command -v powershell.exe >/dev/null 2>&1 || return 1
  local tok
  tok=$(powershell.exe -NoProfile -NonInteractive -Command \
        '[Environment]::GetEnvironmentVariable("CLAUDE_CODE_OAUTH_TOKEN","User")' 2>/dev/null | tr -d '\r\n')
  case "$tok" in
    sk-ant-*) export CLAUDE_CODE_OAUTH_TOKEN="$tok"; return 0 ;;
    *)        return 1 ;;
  esac
}

# 브리지가 실제로 발동했는지 사람이 볼 수 있는 지문 (값 아님). 로그용.
sched_token_fingerprint() {
  [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] || { printf 'none'; return 1; }
  printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN" | sha256sum 2>/dev/null | cut -c1-12
}

sched_check_credentials() {
  # 프로세스 env 가 비었으면 User 스코프에서 먼저 끌어온다 (위 함수 주석 참조).
  sched_resolve_oauth_token >/dev/null 2>&1 || true
  # ★환경변수 인증이 최우선 — 파일 저장소를 통째로 우회한다(claude.exe 가 두 변수 모두 지원, 실측).
  #   이 분기가 없으면 setup-token 을 env 로 쓰는 정상 구성에서 낡은 파일만 보고 오차단한다.
  #   (2026-07-26: 본 함수 자체의 결함이었음 — 검사 대상을 잘못 잡는 계통의 재발)
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
    local age; age=$(sched_token_age_days)
    if [ "${age:-0}" -ge "$SCHED_TOKEN_WARN_DAYS" ] 2>/dev/null; then
      echo "ok_token_aging"; return 0    # 통과시키되 갱신 권고 (차단 아님)
    fi
    echo "ok"; return 0
  fi
  [ -n "${ANTHROPIC_API_KEY:-}" ]       && { echo "ok"; return 0; }
  local cred="${CLAUDE_CREDENTIALS_PATH:-${CLAUDE_CONFIG_DIR:+$CLAUDE_CONFIG_DIR/.credentials.json}}"
  cred="${cred:-$HOME/.claude/.credentials.json}"
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

# ── python 인터프리터 견고 해석 (bare `python3` = Windows Store 스텁 함정)
#    스텁은 "Python " 한 줄 찍고 종료한다 → 명령치환 결과가 빈 문자열 → 호출부의 ${N:-0} 이
#    이를 0 으로 삼켜 "대기 없음" 정상 skip 으로 위장한다. ★총계 0 은 성공이 아니라 계측 사망일 수 있다.
#    존재(command -v)로 판별하지 말 것 — 스텁도 존재한다. 반드시 실행으로 확인.
sched_resolve_python() {
  local c
  for c in "${QVEST_PY:-}" \
           "/c/Users/99922/AppData/Local/Programs/Python/Python312/python.exe" \
           "$(command -v python3 2>/dev/null)" \
           "$(command -v python 2>/dev/null)"; do
    [ -n "$c" ] || continue
    "$c" -c 'import sys' >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ── 카운트 산출물 무결성 검사: 숫자가 아니면 '0' 으로 강등하지 말고 실패로 다룬다.
#    반환 0=정상(숫자) / 1=계측 실패
sched_assert_count() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *)           return 0 ;;
  esac
}

# ── 경보 본문 주석 조립 (자동복구 축 + 연속실패 에스컬레이션 + 조치 안내) — 3 호출부 공통.
#    ★에스컬레이션이 있어야 "같은 톤 반복 → 학습된 무시"가 끊긴다.
#      실사고: alpha_queue 가 5회 연속 동일 401 경보를 같은 문구로 보내는 동안 8일 방치(07-19~26).
#    streak 은 마커 파일({comp}_{reason}_YYYYMMDD.alert) 일자별 누적 개수로 센다.
SCHED_ESCALATE_AT="${SCHED_ESCALATE_AT:-3}"
sched_failure_annotate() {
  local comp="${1:-}" reason="${2:-}" adir="${3:-}"
  local streak guide auto esc=""
  local recent rec_txt=""
  streak=$(sched_failure_streak "$comp" "$reason" "$adir")
  recent=$(sched_failure_recent_count "$comp" "$reason" "$adir")
  guide=$(sched_failure_guidance "$reason")
  auto=$(sched_failure_autorecovers "$reason")
  if [ "${streak:-0}" -ge "$SCHED_ESCALATE_AT" ] 2>/dev/null; then
    esc="★${streak}일째 동일 실패 — 자동 해소 기대를 중단하고 수동 개입하십시오. "
  elif [ "${recent:-0}" -ge "$SCHED_ESCALATE_AT" ] 2>/dev/null; then
    # 연속은 끊겼지만 간헐 재발 — 성공 1회가 마커를 아카이브해 streak 을 리셋한 경우.
    esc="★최근 ${SCHED_RECENT_WINDOW_DAYS}일 ${recent}회 재발(간헐) — 연속이 아니어서 자동 격상에 안 걸립니다. 구조 원인을 보십시오. "
  fi
  printf '자동복구=%s | 연속=%s | 최근%s일=%s회 | %s%s' \
    "$auto" "${streak:-0}" "$SCHED_RECENT_WINDOW_DAYS" "${recent:-0}" "$esc" "$guide"
}

# ── 성공 시 해당 컴포넌트의 미해소 마커를 아카이브 (2026-07-26)
#    왜 필요한가: streak 은 마커 파일의 날짜 연속성으로 센다. 사유가 해소돼도 마커가 남으면
#    다음 실패가 과거와 이어져 "2일 연속"으로 잘못 세고 가짜 격상을 낸다.
#    ★삭제가 아니라 이동 — 사고 이력은 보존해야 사후 추적이 된다.
#    호출 지점 = 잡이 실제로 성공한 직후(exit 0 경로).
sched_mark_resolved() {
  local comp="${1:-}" adir="${2:-}"
  [ -n "$comp" ] || return 0
  [ -n "$adir" ] && [ -d "$adir" ] || return 0
  local arch="$adir/_resolved"; mkdir -p "$arch" 2>/dev/null || return 0
  local n=0 f
  for f in "$adir/${comp}_"*.alert; do
    [ -f "$f" ] || continue
    mv -f "$f" "$arch/" 2>/dev/null && n=$((n + 1))
  done
  # 아카이브 보관기한 — 무한 누적 방지. 사후 추적 가치가 남는 기간만 유지한다.
  #   ★삭제는 아카이브(_resolved) 안에서만 일어난다. 활성 마커는 절대 지우지 않는다.
  find "$arch" -maxdepth 1 -name '*.alert' -mtime "+${SCHED_RESOLVED_RETAIN_DAYS:-90}" -delete 2>/dev/null || true
  [ "$n" -gt 0 ] && printf '%s\n' "$n"
  return 0
}

# ── 경보 발행 (마커 + 텔레그램). alpha/paper 의 검증된 scheduler_alert 와 동일 계약.
#    ★기존 2곳의 자체 정의는 건드리지 않는다(작동 중) — 미보유 스크립트만 이 경로를 쓴다.
#    caller 는 BASE / LOG / TODAY 를 정의해 두어야 한다.
# ── 무인 실행인가 판별 (수동 디버깅 실행의 텔레그램 오경보 차단)
#    2026-07-26 실사고: 토큰 없는 개발 셸에서 큐를 수동 실행하자 사전점검이 정상 차단하면서
#    도훈 텔레그램에 경보가 갔다. 판정 자체는 옳았으나 **수신자에게는 오경보**다.
#    → 대화형 TTY 에서 돈 실행은 마커만 남기고 발송을 생략한다(진단 정보는 보존).
#    강제: QVEST_ALERT_FORCE=1 (수동인데도 보내고 싶을 때) / QVEST_NO_ALERT=1 (항상 억제)
# ── 발송 자격 판정 (2026-07-26 v2 — **선언 기반**)
#    ★v1(TTY 유무 추론)은 틀렸다: 에이전트 도구·CI·서브셸 실행도 TTY 가 없어 "무인"으로
#      오분류돼, 개발 중 검증 실행이 도훈 텔레그램에 실경보로 나갔다(실사고 16:41 auth_expired).
#      존재/부재 추론으로 정체성을 판별하지 말 것 — 이 저장소가 반복 학습한 계통.
#    ∴ 무인임을 **명시 선언**한 실행만 발송한다(allow-list). 스케줄러 .bat 이 QVEST_UNATTENDED=1
#      을 export 하고, 그 표지가 없으면 마커만 남긴다. 추론이 아니라 계약.
sched_is_unattended() { [ "${QVEST_UNATTENDED:-0}" = "1" ]; }

sched_alert_should_send() {
  [ "${QVEST_NO_ALERT:-0}" = "1" ]  && return 1   # 항상 억제
  [ "${QVEST_ALERT_FORCE:-0}" = "1" ] && return 0  # 항상 발송(디버깅/수동 재발송)
  if sched_is_unattended; then
    return 0                            # 스케줄러가 선언한 무인 실행 → 발송
  fi
  return 1                              # 선언 없음 = 수동/에이전트 → 마커만
}

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
  sched_alert_should_send || return 0    # 수동 실행 = 마커만, 텔레그램 생략
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
    ok_token_aging)   echo "정상이나 env 토큰을 ${SCHED_TOKEN_WARN_DAYS}일 이상 사용 중 — setup-token 토큰은 만료시각을 알 수 없어 만료 시 예고 없이 401 이 됩니다. 일반 터미널에서 claude setup-token 으로 갱신 권장(차단 아님)." ;;
    *)                echo "자격증명 상태 판별 불가 — 형식 변경 가능성." ;;
  esac
}
