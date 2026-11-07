#!/usr/bin/env bash
#==============================================================================
# claude_cli_update.sh — 무인 레인이 쓰는 npm 전역 Claude Code CLI 를 채널 최신 버전으로 올린다 (2026-11-07)
#   도훈 지시 "무인레인이 쓰는 npm cli는 최신버전 나올때마다 자동 업데이트 되게" → 방식 2(예약 작업) 채택.
#
# 왜 CLI 내장 자동 업데이트가 아닌가:
#   npm 패키지 2.1.x 는 네이티브 bin/claude.exe 다(2.1.261 실측 · 218 MB). 공식 문서(code.claude.com/docs/en/setup):
#   실행 중인 세션은 실행 파일을 계속 디스크에서 읽고("reads parts of the Claude Code executable from disk as it works"),
#   npm install -g 제자리 업그레이드는 이전 바이너리를 지운다. Windows 는 실행 중인 exe 를 잠근다. 레인 여럿이 동시에
#   claude 를 돌리는데 내장 업데이터는 교체 시점을 고르지 못한다 → 실행 중인 레인이 죽거나 설치가 반쯤 깨진다.
#   그래서 교체는 이 스크립트 하나만 하고, 레인 쪽 내장 업데이터는 끈다(rf_llm_env.sh::rf_llm_agent_run 이
#   DISABLE_AUTOUPDATER=1 · DISABLE_UPDATES=1 을 claude 프로세스에 싣는다).
#
# 흐름(예약 작업 Qvest_ClaudeCliUpdate · 매일 06:00 · 기계마다 따로 = machines.conf period local):
#   ① 버전 비교 — 설치 버전(<npm prefix>/node_modules/@anthropic-ai/claude-code/package.json) vs 채널 버전
#      (npm dist-tags.<채널>). 같으면 SUMMARY 1줄만 남기고 끝. 채널 = --channel > QVEST_CLI_CHANNEL > latest.
#      채널 버전이 설치 버전보다 낮으면(배포 쪽이 릴리스를 거둬 태그를 되돌린 경우) 그 버전으로 내린다 — 채널을 따른다.
#   ② 유휴 구간 대기 — npm 전역 claude 프로세스(claude_cli_procs.ps1)가 0개일 때까지 폴링(기본 2분 간격 · 최대 180분).
#      목록 조회가 실패하면 '사용 중'으로 본다(빈 출력을 0개로 읽지 않는다 — '#OK' 줄 필수). 끝내 없으면 오늘은 보류.
#   ③ 교체 잠금 — .cache/machine/claude_cli_update_<HOST>.lock/ 을 mkdir 로 잡고(원자적 · 업데이터끼리 상호 배제)
#      잠깐 뒤 프로세스를 다시 확인한다. 그 사이 레인이 떴으면 잠금을 풀고 ②로. 잠금이 있는 동안
#      rf_llm_agent_run 은 새 claude 를 띄우지 않고 기다린다(STALE 1800s 넘은 잠금 = 업데이터 사망 → 무시).
#   ④ 설치 — npm install -g @anthropic-ai/claude-code@<확인한 정확한 버전>(그 사이 태그가 움직여도 확인한 버전을 설치).
#      npm 잔여 폴더(retire 경로 node_modules/@anthropic-ai/.claude-code-*)가 있으면 먼저 지운다(ENOTEMPTY 원인).
#      설치에는 timeout 을 걸지 않는다 — MSYS timeout 이 npm 셸 래퍼만 끊으면 node 가 고아로 남아 롤백 설치와 겹친다
#      (npm 자체 fetch 타임아웃 · 예약 작업 ExecutionTimeLimit 4h 가 상한).
#   ⑤ 확인 — package.json 버전 = 목표 ∧ bin/claude.exe --version 첫 줄 = 목표. 실패면 최종 상태로 판정한다:
#      npm 이 스스로 롤백해 이전 버전이 온전하면 재설치하지 않고, 아니면 이전 버전을 재설치한 뒤 같은 확인.
#   ⑥ 기록 — 이력 .cache/machine/claude_cli_history_<HOST>.jsonl(설치 시도마다 1줄: before · target · after · result).
#      교체는 레인 claude 가 0개일 때만 하므로 한 레인 실행이 두 버전에 걸치지 않는다 → 레인 로그 시각과 이력을
#      맞추면 그 실행의 CLI 버전이 정확히 나온다. 상태 .cache/machine/claude_cli_<HOST>.json · 로그
#      .cache/scheduler_logs/claude_cli_update_<HOST>.log(실행마다 SUMMARY 1줄 — 무인 로그가 비면 침묵 실패와 구분이 안 된다).
#   ⑦ 텔레그램(tg_agent_brief · 무인 선언 QVEST_UNATTENDED=1 일 때만 — _sched_failure_classify.sh 규약) —
#      버전 변경 · 설치 실패 · 연속 보류 3 · 7 · 14 … 회째. 최신이면 무음.
#
# 사용: bash claude_cli_update.sh [--channel latest|stable] [--check] [--dry-run] [--no-telegram] [--quiet]
#                                 [--max-wait-min N] [--poll-sec N]
#   --check    버전만 비교한다(설치 · 잠금 · 이력 없음)      --dry-run  유휴 구간 판정까지 하고 설치 직전에 멈춘다
#   rc 0 = 최신 · 업데이트 · 오늘 보류(사용 중 · 조회 실패 — 연속 횟수로 경보) · 2 = 설치 실패 → 이전 버전 복구 ·
#      3 = 설치 실패 · 복구도 실패(사람 조치) · 64 = 인자 오류
#   (rc≠0 은 scheduler_task_health.sh 가 LastTaskResult 로 잡는다 — 일시적 네트워크 실패로 그 경보가 울리지 않게 0 으로 둔다)
#   테스트 주입: QVEST_CLI_NPM · QVEST_CLI_PREFIX · QVEST_CLI_PROCS_CMD · QVEST_CLI_STATE_DIR · QVEST_CLI_LOG ·
#               QVEST_CLI_UPDATE_LOCK · QVEST_HOST · QVEST_CLI_GRACE_SEC · QVEST_CLI_LOCK_STALE_SEC
#   테스트 = 08_Tests/ops/test_claude_cli_update.sh
#==============================================================================
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${QM_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$SELF_DIR/../.." && pwd)}}"; ROOT="${ROOT//\\//}"
HOSTU="$(printf '%s' "${QVEST_HOST:-${COMPUTERNAME:-$(hostname 2>/dev/null || echo unknown)}}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9_.-' '_')"
PKG_NAME="@anthropic-ai/claude-code"

CHANNEL="${QVEST_CLI_CHANNEL:-latest}"; MODE=update; DO_TG=1; QUIET=0
MAX_WAIT_MIN="${QVEST_CLI_MAX_WAIT_MIN:-180}"; POLL_SEC="${QVEST_CLI_POLL_SEC:-120}"
GRACE_SEC="${QVEST_CLI_GRACE_SEC:-5}"; STALE_SEC="${QVEST_CLI_LOCK_STALE_SEC:-1800}"
while [ $# -gt 0 ]; do
  case "$1" in
    --channel)       CHANNEL="${2:-}"; shift ;;
    --channel=*)     CHANNEL="${1#*=}" ;;
    --check)         MODE=check ;;
    --dry-run)       MODE=dry ;;
    --no-telegram)   DO_TG=0 ;;
    --quiet)         QUIET=1 ;;
    --max-wait-min)  MAX_WAIT_MIN="${2:-}"; shift ;;
    --poll-sec)      POLL_SEC="${2:-}"; shift ;;
    -h|--help)       sed -n '2,/^#=====/p' "$0"; exit 0 ;;
    *)               echo "claude_cli_update: 알 수 없는 인자 $1" >&2; exit 64 ;;
  esac
  shift
done
case "$CHANNEL" in latest|stable) ;; *) echo "claude_cli_update: --channel 은 latest|stable ($CHANNEL)" >&2; exit 64 ;; esac
for _n in "$MAX_WAIT_MIN" "$POLL_SEC" "$GRACE_SEC" "$STALE_SEC"; do
  case "$_n" in ''|*[!0-9]*) echo "claude_cli_update: 숫자가 아닌 설정값 '$_n'" >&2; exit 64 ;; esac
done

STATE_DIR="${QVEST_CLI_STATE_DIR:-$ROOT/.cache/machine}"
STATE="$STATE_DIR/claude_cli_${HOSTU}.json"
HIST="$STATE_DIR/claude_cli_history_${HOSTU}.jsonl"
LOCK="${QVEST_CLI_UPDATE_LOCK:-$ROOT/.cache/machine/claude_cli_update_${HOSTU}.lock}"   # ★rf_llm_env.sh 와 같은 경로 규칙
LOG="${QVEST_CLI_LOG:-$ROOT/.cache/scheduler_logs/claude_cli_update_${HOSTU}.log}"
mkdir -p "$STATE_DIR" "$(dirname "$LOG")" "$(dirname "$LOCK")" 2>/dev/null

say()   { local l; l="$(date '+%Y-%m-%dT%H:%M:%S') $HOSTU $*"; printf '%s\n' "$l" >> "$LOG" 2>/dev/null || true; [ "$QUIET" = 1 ] || printf '%s\n' "$l"; }
# JSON · R 문자열 리터럴에 넣어도 안전한 한 줄 — 따옴표 · 역슬래시 · 줄바꿈 제거 · 600바이트에서 자른 뒤
#   잘린 UTF-8 꼬리를 iconv -c 로 버린다(cut -b 는 바이트 단위라 한글 중간에서 끊기면 R 이 문자열을 못 읽는다).
if command -v iconv >/dev/null 2>&1; then _utf8fix() { iconv -f UTF-8 -t UTF-8 -c 2>/dev/null; }; else _utf8fix() { cat; }; fi
clean() { printf '%s' "$*" | tr -d '\r"\\' | tr '\n\t' '  ' | cut -b1-600 | _utf8fix; }
ver_lt(){ [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]; }
alert_due(){ [ "$1" -eq 3 ] || { [ "$1" -ge 7 ] && [ $(( $1 % 7 )) -eq 0 ]; }; }   # 연속 보류 경보: 3 · 7 · 14 · 21 … 회째

# 무인 선언 규약(발송 여부) — 공용 헬퍼가 정본. 읽지 못하면 같은 규칙의 최소판.
[ -f "$SELF_DIR/_sched_failure_classify.sh" ] && . "$SELF_DIR/_sched_failure_classify.sh" 2>/dev/null
if ! command -v sched_alert_should_send >/dev/null 2>&1; then
  sched_alert_should_send() {
    [ "${QVEST_NO_ALERT:-0}" = 1 ] && return 1
    [ "${QVEST_ALERT_FORCE:-0}" = 1 ] && return 0
    [ "${QVEST_UNATTENDED:-0}" = 1 ]
  }
fi

# ── 상태 · 이력 ───────────────────────────────────────────────────────────────
state_field() { [ -f "$STATE" ] || return 0; grep -oE "\"$1\":(\"[^\"]*\"|[0-9]+)" "$STATE" 2>/dev/null | head -1 | sed -E 's/^"[^"]*":"?//; s/"$//'; }
STREAK_PREV="$(state_field streak)"; case "$STREAK_PREV" in ''|*[!0-9]*) STREAK_PREV=0 ;; esac
write_state() { # $1 result · $2 설치 버전 · $3 목표 버전 · $4 연속 보류 · $5 메모 (임시 파일 → mv = atomic rename)
  local tmp="$STATE.tmp.$$"
  printf '{"host":"%s","channel":"%s","checked_at":"%s","result":"%s","installed":"%s","target":"%s","streak":%s,"note":"%s"}\n' \
    "$HOSTU" "$CHANNEL" "$(date -Iseconds)" "$1" "$2" "$3" "$4" "$(clean "$5")" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE"
}
hist() { # $1 before · $2 target · $3 after · $4 result · $5 메모
  printf '{"at":"%s","host":"%s","channel":"%s","before":"%s","target":"%s","after":"%s","result":"%s","note":"%s"}\n' \
    "$(date -Iseconds)" "$HOSTU" "$CHANNEL" "$1" "$2" "$3" "$4" "$(clean "$5")" >> "$HIST" 2>/dev/null || true
}

# ── 텔레그램(tg_agent_brief 단일 진입점) ───────────────────────────────────────
tg() { # $1 이벤트 · $2 제목 · $3 요약 · $4 쉬운 설명(항목을 " | " 로 구분) · 나머지 = "키=값"
  #   섹션 3개(요약 · 쉬운 설명 · 상세) = 이모지 5개 — qvest-telegram SKILL 규칙 EMOJI_MIN(메시지당 ≥5).
  local ev="$1" title="$2" body="$3" rest="$4"; shift 4
  [ "$DO_TG" = 1 ] || { say "tg skip(--no-telegram): $ev"; return 0; }
  sched_alert_should_send || { say "tg skip(무인 선언 없음 — 수동 실행): $ev"; return 0; }
  local rs; rs="$(command -v Rscript 2>/dev/null || true)"
  [ -n "$rs" ] || { [ -x "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" ] && rs="/c/Program Files/R/R-4.5.2/bin/Rscript.exe"; }
  [ -n "$rs" ] || { say "tg skip: Rscript 없음 ($ev)"; return 0; }
  local kv="" pair items="" it
  for pair in "$@"; do kv="${kv}${kv:+, }\"$(clean "${pair%%=*}")\" = \"$(clean "${pair#*=}")\""; done
  while [ -n "$rest" ]; do
    it="${rest%% | *}"; items="${items}${items:+, }\"$(clean "$it")\""
    [ "$it" = "$rest" ] && break
    rest="${rest#* | }"
  done
  local rf="$STATE_DIR/_tg_claude_cli_${HOSTU}_$$.R"
  cat > "$rf" <<RS
suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))
res <- tryCatch(tg_agent_brief(
  agent = "Q-Lead",
  title = "$(clean "$title")",
  relaxed = TRUE, force = TRUE,
  lock_scope = "claude_cli_${HOSTU}_${ev}_$(date +%Y%m%d)",
  sections = list(
    list(type = "summary", emoji = "\U0001F527", body = "$(clean "$body")"),
    list(type = "bullet", emoji = "\U0001F4A1", heading = "쉬운 설명", items = c(${items})),
    list(type = "kv", emoji = "\U0001F4CB", heading = "상세", kv = list(${kv}))
  )
), error = function(e) { cat("tg fail:", conditionMessage(e), "\n"); NULL })
if (!(is.list(res) && isTRUE(res\$ok))) quit(status = 1)
RS
  if LC_ALL='English_United States.utf8' "$rs" "$rf" >> "$LOG" 2>&1; then say "tg sent: $ev"; rm -f "$rf"
  else say "tg fail: $ev (생성 스크립트 보존 $rf)"; fi
}

# ── npm · 설치 위치 · 버전 ────────────────────────────────────────────────────
NPM="${QVEST_CLI_NPM:-}"
[ -n "$NPM" ] || NPM="$(command -v npm 2>/dev/null || true)"
[ -n "$NPM" ] || { [ -x "/c/Program Files/nodejs/npm" ] && NPM="/c/Program Files/nodejs/npm"; }
PREFIX="${QVEST_CLI_PREFIX:-}"
if [ -z "$PREFIX" ] && [ -n "$NPM" ]; then PREFIX="$(timeout 60 "$NPM" config get prefix 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1)"; fi
PREFIX_U="$(cygpath -u "$PREFIX" 2>/dev/null || printf '%s' "${PREFIX//\\//}")"
PKG="$PREFIX_U/node_modules/$PKG_NAME"
EXE="$PKG/bin/claude.exe"

INSTALLED=""; EXE_VER=""; REMOTE=""; REMOTE_ERR=""
read_installed() { INSTALLED=""; [ -f "$PKG/package.json" ] || return 1
  INSTALLED="$(grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' "$PKG/package.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  [ -n "$INSTALLED" ]; }
read_exe() { EXE_VER=""; [ -f "$EXE" ] || return 1
  local out; out="$(timeout 60 env -u CLAUDECODE DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 "$EXE" --version 2>&1)" || return 1
  EXE_VER="$(printf '%s\n' "$out" | tr -d '\r' | head -1 | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"
  [ -n "$EXE_VER" ]; }
healthy_at() { [ "$INSTALLED" = "$1" ] && [ "$EXE_VER" = "$1" ]; }   # read_installed · read_exe 직후에만 의미가 있다
read_remote() { REMOTE=""; REMOTE_ERR=""
  [ -n "$NPM" ] || { REMOTE_ERR="npm 없음"; return 1; }
  local ef out rc last
  ef="$STATE_DIR/.npm_view_err_${HOSTU}_$$"
  # stdout 만 버전 후보로 본다 — npm 경고(stderr)가 버전 줄 뒤에 끼면 '마지막 줄 = 버전' 이 깨진다.
  out="$(timeout 120 "$NPM" view "$PKG_NAME" "dist-tags.$CHANNEL" 2>"$ef")"; rc=$?
  last="$(printf '%s\n' "$out" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -1 | tr -d '[:space:]')"
  # 버전 문자열 하나만 나온 경우만 믿는다 — 오류 문구 속 숫자(예: node v24.13.1)를 버전으로 읽지 않는다.
  if [ "$rc" -eq 0 ] && printf '%s' "$last" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then REMOTE="$last"; rm -f "$ef"; return 0; fi
  REMOTE_ERR="npm view rc=$rc · out=$(clean "$(printf '%s' "$out" | tail -2)") · err=$(clean "$(tail -2 "$ef" 2>/dev/null)")"
  rm -f "$ef"; return 1; }

# ── 레인 claude 프로세스(유휴 구간 판정) ──────────────────────────────────────
BUSY_N=-1; BUSY_WHAT=""
busy_check() { # BUSY_N = 개수 · 조회 실패면 -1(= 사용 중으로 다룬다)
  local out rc okl
  if [ -n "${QVEST_CLI_PROCS_CMD:-}" ]; then out="$(bash -c "$QVEST_CLI_PROCS_CMD" 2>&1)"; rc=$?
  else out="$(timeout 120 powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass \
              -File "$(cygpath -w "$SELF_DIR/claude_cli_procs.ps1" 2>/dev/null || echo "$SELF_DIR/claude_cli_procs.ps1")" 2>&1)"; rc=$?; fi
  out="$(printf '%s\n' "$out" | tr -d '\r')"
  okl="$(printf '%s\n' "$out" | grep -E '^#OK [0-9]+$' | tail -1)"
  if [ "$rc" -ne 0 ] || [ -z "$okl" ]; then BUSY_N=-1; BUSY_WHAT="조회 실패 rc=$rc $(clean "$(printf '%s' "$out" | tail -2)")"; return 0; fi
  BUSY_N="${okl#\#OK }"
  BUSY_WHAT="$(printf '%s\n' "$out" | grep -vE '^#' | sed '/^[[:space:]]*$/d' | head -3 | tr '\n' ';')"
}

# ── 교체 잠금(설치 동안 새 레인 claude 시작을 막는다) ─────────────────────────
HAVE_LOCK=0
_lock_mine() { printf 'pid=%s\nstart=%s\nhost=%s\nfrom=%s\nto=%s\n' "$$" "$(date +%s)" "$HOSTU" "$INSTALLED" "$REMOTE" > "$LOCK/info" 2>/dev/null; HAVE_LOCK=1; }
lock_take() {
  if mkdir "$LOCK" 2>/dev/null; then _lock_mine; return 0; fi
  local age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  [ "$age" -ge "$STALE_SEC" ] || return 1
  say "stale 잠금 회수(${age}s — 이전 업데이터가 죽은 것으로 본다): $LOCK"
  rm -rf "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || return 1
  _lock_mine
}
lock_touch()   { [ "$HAVE_LOCK" = 1 ] && touch "$LOCK" 2>/dev/null; return 0; }
lock_release() { [ "$HAVE_LOCK" = 1 ] && rm -rf "$LOCK" 2>/dev/null; HAVE_LOCK=0; return 0; }
trap 'lock_release' EXIT
trap 'lock_release; exit 130' INT TERM

# ── 설치 · 확인 ───────────────────────────────────────────────────────────────
INSTALL_ERR=""
npm_install() { # $1 버전 → 0 = 설치 성공 ∧ 확인 통과. 끝나면 INSTALLED · EXE_VER = 그 시점 실제 상태
  local v="$1" retired="" d out rc
  for d in "$PREFIX_U/node_modules/@anthropic-ai"/.claude-code-*; do
    [ -e "$d" ] || continue
    retired="${retired}${retired:+ }$(basename "$d")"
    rm -rf "$d" 2>/dev/null
  done
  [ -n "$retired" ] && say "npm 잔여 폴더 정리: $retired"
  lock_touch
  out="$("$NPM" install -g "$PKG_NAME@$v" --no-fund --no-audit 2>&1)"; rc=$?
  printf '%s\n' "$out" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -15 | sed 's/^/    npm| /' >> "$LOG" 2>/dev/null
  INSTALL_ERR=""
  [ "$rc" -eq 0 ] || INSTALL_ERR="npm install rc=$rc · $(clean "$(printf '%s' "$out" | grep -iE 'err|ebusy|eperm|enotempty' | tail -2)")"
  read_installed; read_exe
  if [ "$rc" -eq 0 ] && healthy_at "$v"; then return 0; fi
  [ -n "$INSTALL_ERR" ] || INSTALL_ERR="확인 실패 — package.json=${INSTALLED:-없음} · claude.exe --version=${EXE_VER:-실행 실패} · 목표 $v"
  return 1
}

# ══ 본 흐름 ═══════════════════════════════════════════════════════════════════
if [ -z "$NPM" ] || [ -z "$PREFIX_U" ]; then
  say "SUMMARY result=no_npm channel=$CHANNEL npm=${NPM:-없음} prefix=${PREFIX:-없음} — npm 또는 전역 설치 위치를 찾지 못함(PATH · /c/Program Files/nodejs)"
  write_state no_npm "" "" "$STREAK_PREV" "npm=${NPM:-없음} prefix=${PREFIX:-없음}"
  exit 0
fi
read_installed; BEFORE="$INSTALLED"
if [ -z "$BEFORE" ]; then
  say "SUMMARY result=not_installed channel=$CHANNEL pkg=$PKG — npm 전역 CLI 가 없다(레인이 이 기계에서 claude 를 못 쓴다 · 사람이 1회 설치)"
  write_state not_installed "" "" "$STREAK_PREV" "npm 전역 설치 없음: $PKG"
  exit 0
fi

if ! read_remote; then
  STREAK=$((STREAK_PREV + 1))
  say "SUMMARY result=check_failed installed=$BEFORE channel=$CHANNEL streak=$STREAK — $REMOTE_ERR"
  write_state check_failed "$BEFORE" "" "$STREAK" "$REMOTE_ERR"
  if [ "$MODE" = update ] && alert_due "$STREAK"; then
    tg stuck "[무인] Claude CLI 버전 확인 ${STREAK}회 연속 실패 — $HOSTU" \
      "npm 에서 최신 버전을 읽지 못해 CLI 업데이트를 못 하고 있습니다. 레인은 지금 버전으로 계속 돕니다." \
      "레인 실행에는 지장이 없습니다 — 업데이트만 미뤄지고 있습니다 | 네트워크 · npm 레지스트리 접속이 원인일 가능성이 큽니다 | 매일 06:00 에 다시 확인합니다" \
      "기계=$HOSTU" "설치 버전=$BEFORE" "채널=$CHANNEL" "사유=$REMOTE_ERR" "로그=.cache/scheduler_logs/claude_cli_update_${HOSTU}.log"
  fi
  exit 0
fi

if [ "$BEFORE" = "$REMOTE" ]; then
  say "SUMMARY result=up_to_date installed=$BEFORE channel=$CHANNEL"
  write_state up_to_date "$BEFORE" "$REMOTE" 0 ""
  exit 0
fi
if ver_lt "$REMOTE" "$BEFORE"; then DIRWORD="downgrade(채널 태그가 더 낮은 버전으로 되돌아감)"; DIRSENT="내렸습니다(채널 태그가 더 낮은 버전으로 되돌아갔습니다)."
else DIRWORD="upgrade"; DIRSENT="올렸습니다."; fi
if [ "$MODE" = check ]; then
  say "SUMMARY result=update_available installed=$BEFORE target=$REMOTE channel=$CHANNEL ($DIRWORD · --check)"
  write_state update_available "$BEFORE" "$REMOTE" "$STREAK_PREV" "--check"
  exit 0
fi

# ② 유휴 구간 대기 · ③ 교체 잠금
say "start installed=$BEFORE target=$REMOTE channel=$CHANNEL ($DIRWORD) — 레인 claude 0개를 기다린다(최대 ${MAX_WAIT_MIN}분 · ${POLL_SEC}s 간격)"
DEADLINE=$(( $(date +%s) + MAX_WAIT_MIN * 60 )); POLLS=0; GOT=0; LAST_BUSY=""
while :; do
  POLLS=$((POLLS + 1))
  busy_check
  if [ "$BUSY_N" = 0 ]; then
    if lock_take; then
      sleep "$GRACE_SEC"
      busy_check
      if [ "$BUSY_N" = 0 ]; then GOT=1; break; fi
      say "잠금 직후 레인 claude 감지(n=$BUSY_N · $BUSY_WHAT) — 잠금을 풀고 다시 기다린다"
      lock_release
    else
      LAST_BUSY="다른 업데이터가 잠금을 쥐고 있음($LOCK)"
    fi
  else
    LAST_BUSY="n=$BUSY_N · $BUSY_WHAT"
  fi
  [ "$(date +%s)" -lt "$DEADLINE" ] || break
  sleep "$POLL_SEC"
done
if [ "$GOT" != 1 ]; then
  STREAK=$((STREAK_PREV + 1))
  say "SUMMARY result=skip_busy installed=$BEFORE target=$REMOTE channel=$CHANNEL polls=$POLLS streak=$STREAK — ${MAX_WAIT_MIN}분 안에 유휴 구간 없음 · 마지막: $LAST_BUSY"
  write_state skip_busy "$BEFORE" "$REMOTE" "$STREAK" "$LAST_BUSY"
  if alert_due "$STREAK"; then
    tg stuck "[무인] Claude CLI ${STREAK}회 연속 업데이트 보류 — $HOSTU" \
      "레인 claude 가 계속 돌고 있어 교체할 유휴 구간이 없었습니다(매번 최대 ${MAX_WAIT_MIN}분 대기). 레인은 지금 버전으로 계속 돕니다." \
      "실행 중인 레인을 끊지 않으려고 교체를 미루는 중입니다 | 레인 claude 가 모두 끝난 순간이 생기면 그때 자동으로 교체합니다 | 급하면 레인을 잠시 멈추고 수동으로 실행하면 됩니다" \
      "기계=$HOSTU" "설치 버전=$BEFORE" "최신 버전=$REMOTE ($CHANNEL)" "마지막 확인=$LAST_BUSY" \
      "수동=레인을 잠시 멈추고 bash 02_Infrastructure/ops/claude_cli_update.sh"
  fi
  exit 0
fi
if [ "$MODE" = dry ]; then
  say "SUMMARY result=dry_run installed=$BEFORE target=$REMOTE channel=$CHANNEL polls=$POLLS — 유휴 구간 확인 · 설치 직전에 멈춤(--dry-run)"
  write_state dry_run "$BEFORE" "$REMOTE" "$STREAK_PREV" "--dry-run"
  exit 0
fi

# ④ 설치 · ⑤ 확인
T0=$(date +%s)
if npm_install "$REMOTE"; then
  DUR=$(( $(date +%s) - T0 ))
  lock_release
  hist "$BEFORE" "$REMOTE" "$REMOTE" updated "${DUR}s · polls=$POLLS"
  say "SUMMARY result=updated before=$BEFORE after=$REMOTE channel=$CHANNEL polls=$POLLS install=${DUR}s"
  write_state updated "$REMOTE" "$REMOTE" 0 "$BEFORE → $REMOTE"
  tg updated "[무인] Claude CLI 업데이트 — $HOSTU $BEFORE → $REMOTE" \
    "무인 레인이 쓰는 npm CLI 를 $CHANNEL 채널 버전으로 $DIRSENT 레인 claude 가 하나도 돌지 않을 때 교체했고, 실행 확인까지 마쳤습니다." \
    "다음 레인 실행부터 새 버전을 씁니다 | 실행 중이던 레인은 없었으므로 끊긴 작업이 없습니다 | 버전이 바뀐 시각은 이력 파일에 남아 레인 결과와 맞춰 볼 수 있습니다" \
    "기계=$HOSTU" "이전=$BEFORE" "지금=$REMOTE" "채널=$CHANNEL" "설치 시간=${DUR}초"
  exit 0
fi
FAIL1="$INSTALL_ERR"; FAIL2=""
# 실패 뒤 판정은 최종 상태로 한다 — npm 이 스스로 롤백해 이전 버전이 온전하면 다시 설치하지 않는다(불필요한 교체 · 다운로드 회피).
if healthy_at "$BEFORE"; then
  HOW="npm 자체 롤백 — 이전 버전 그대로"
else
  say "설치 실패(목표 $REMOTE): $FAIL1 — 이전 버전 $BEFORE 재설치"
  npm_install "$BEFORE" || FAIL2="$INSTALL_ERR"
  HOW="이전 버전 재설치"
fi
lock_release
if healthy_at "$BEFORE"; then
  hist "$BEFORE" "$REMOTE" "$BEFORE" failed_rolled_back "$FAIL1 · $HOW"
  say "SUMMARY result=failed_rolled_back before=$BEFORE target=$REMOTE after=$BEFORE channel=$CHANNEL — $FAIL1 · $HOW"
  write_state failed_rolled_back "$BEFORE" "$REMOTE" "$((STREAK_PREV + 1))" "$FAIL1 · $HOW"
  tg install_failed "[무인] Claude CLI 업데이트 실패 — $HOSTU (이전 버전 복구)" \
    "$REMOTE 설치가 실패해 $BEFORE 로 되돌렸습니다($HOW). 레인은 $BEFORE 로 계속 돌고, 내일 다시 시도합니다." \
    "레인은 이전 버전으로 정상 동작합니다 | 같은 실패가 며칠 이어지면 사유 줄을 보고 수동으로 설치해 주세요" \
    "기계=$HOSTU" "목표=$REMOTE" "지금=$BEFORE" "사유=$FAIL1"
  exit 2
fi
hist "$BEFORE" "$REMOTE" "${INSTALLED:-?}" failed_broken "$FAIL1 // 복구: ${FAIL2:-확인 실패}"
say "SUMMARY result=failed_broken before=$BEFORE target=$REMOTE now=${INSTALLED:-?} exe=${EXE_VER:-실행 실패} — $FAIL1 // 복구: ${FAIL2:-확인 실패}"
write_state failed_broken "${INSTALLED:-}" "$REMOTE" "$((STREAK_PREV + 1))" "$FAIL1 // 복구: ${FAIL2:-확인 실패}"
tg install_failed "[무인] Claude CLI 설치 손상 — $HOSTU · 사람 조치 필요" \
  "$REMOTE 설치와 $BEFORE 복구가 모두 실패했습니다. 레인의 claude 실행이 실패할 수 있습니다. 보통 PowerShell 에서 npm install -g @anthropic-ai/claude-code@latest 를 실행해 주세요." \
  "설치가 손상돼 레인이 claude 를 못 띄울 수 있습니다 | 수동 설치 뒤에는 다음 06:00 실행이 정상 상태를 다시 확인합니다" \
  "기계=$HOSTU" "목표=$REMOTE" "이전=$BEFORE" "지금 package.json=${INSTALLED:-없음}" "claude.exe=${EXE_VER:-실행 실패}" "사유=$FAIL1 // ${FAIL2:-확인 실패}"
exit 3
