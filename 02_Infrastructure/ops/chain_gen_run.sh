#!/usr/bin/env bash
#==============================================================================
# chain_gen_run.sh — 강화 사슬 다음 걸음 설계(생성기 LLM) 1회 · 무인 LLM 러너(계약 대상) · v1 2026-11-10
#
# 결정: CHAIN-AUTOMATION-STANDING-BOARD-AND-TICK-20261110(도훈 11-10). 호출자 = 02_Infrastructure/ops/chain_tick.sh 뿐.
# 사용: chain_gen_run.sh <WDIR> [사슬 디렉터리(저장소 상대 — 가드 탐침용)]
#   입력 <WDIR>/prompt.md(chain_tick.R prompt) · <WDIR> 네 파일(round.sh <사슬> p4-workdir 가 τ_D 검사로 만든 것)
#   출력 <WDIR>/out.md(최종 응답) · <WDIR>/gen_result.json {rc · reason · model}
#   종료 0 산출 · 3 한도 · 4 인증 · 5 가드 탐침 실패(LLM 호출 안 함) · 6 시간 초과 · 1 그 밖
# 실행 방식 = rx_lane.sh 와 같다(청정 레인 QVEST_CLEAN_LANE=1 · QVEST_CLEAN_WDIR=<WDIR> · 도구 Read/Glob/Grep 만 · 자동 커밋/푸시 끔 · cwd = 저장소 루트
#   — 세션 훅 arm_gen_read_guard.sh(R5 성과 경로 · R6 허용 목록 밖 = block)가 이 호출에도 그대로 걸린다). 단일 진입 = rf_llm_env.sh::rf_llm_agent_run.
# ★LLM 을 부르기 전에 가드 탐침(양성 대조)을 돈다 — 성과 파일 · 사슬 측정 파일 · 루트 표기 3꼴(G: · C: 접합점 · 역슬래시)이 block, 작업 폴더 파일이 통과여야 한다.
#   하나라도 어긋나면 claude 를 부르지 않는다(경계가 실제로 걸린다는 증거 없이 생성기를 띄우지 않는다).
# 경보는 이 러너가 내지 않는다(정체 잠금만 예외) — 원인 분류를 종료 코드로 돌려주고 틱이 원인 하나 = 하루 한 통으로 낸다.
#==============================================================================
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]:-$0}")/resolve_project.sh"
BASE="${BASE:-${PROJECT:-$PWD}}"; PROJECT="${PROJECT:-$BASE}"
cd "$BASE" || exit 1
WDIR="${1:?usage: chain_gen_run.sh <WDIR> [chain_dir]}"; CHAIN_REL="${2:-}"
WDIR="${WDIR//\\//}"
TODAY=$(date +%Y%m%d)
LOG="$BASE/.cache/scheduler_logs/chain_gen_${TODAY}.log"
mkdir -p "$(dirname "$LOG")"
log(){ echo "$(date -Iseconds) [chain_gen] $*" >> "$LOG"; }
log "start wdir=$WDIR chain=${CHAIN_REL:-?}"
RSCRIPT="${CT_RSCRIPT:-Rscript}"
GEN_TMO=$("$RSCRIPT" --vanilla "$BASE/02_Infrastructure/programs/chain_tick.R" config gen_timeout_sec 2>/dev/null | tr -d '\r' | tail -n 1)
case "$GEN_TMO" in ''|*[!0-9]*) log "설정 판독 불가(gen_timeout_sec='$GEN_TMO') — claude 호출 안 함"; exit 1 ;; esac
# -- 자체 상호배제 + 정체 경보 — 홀더를 죽이지 않는다(보이게만 한다) --------------------
GLOCK="$BASE/.cache/chain_gen_run.lock"
if ! mkdir "$GLOCK" 2>/dev/null; then
  _rp=$(cat "$GLOCK/pid" 2>/dev/null)
  if [ -n "${_rp:-}" ] && kill -0 "$_rp" 2>/dev/null; then
    # 정체 문턱 근거: 살아 있는 홀더가 자기 timeout(gen_timeout_sec)을 넘겨 로그가 멈췄다 = timeout 이 실패한 것 = 매달림(새 숫자 없음)
    _stall_min="${QVEST_STALL_ALERT_MIN:-$(( GEN_TMO / 60 ))}"
    if [ -f "$LOG" ]; then
      _lm=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
      _age_min=$(( ( $(date +%s) - _lm ) / 60 ))
      if [ "$_age_min" -ge "$_stall_min" ]; then
        source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
        command -v sched_alert_emit >/dev/null 2>&1 && sched_alert_emit "chain_gen" "stalled_lock" "홀더 PID=${_rp:-?} 가 살아 있으나 로그가 ${_age_min}분째 정체(문턱 ${_stall_min}분) — 매달림 의심 · 그 PID 를 종료하면 잠금이 풀린다" "chain_gen:stalled_lock" "강화 사슬 생성기 실행이 멈춘 것 같습니다"
        log "★정체 경보: 홀더 PID=${_rp:-?} 로그 ${_age_min}분 무변화 (문턱 ${_stall_min}분)"
      fi
    fi
    log "다른 인스턴스 실행 중(PID=$_rp) — skip"; exit 0
  fi
  log "stale lock 회수 (PID=${_rp:-?} 생존 안 함)"
  rm -rf "$GLOCK"
  mkdir "$GLOCK" 2>/dev/null || { log "락 획득 실패 — skip"; exit 0; }
fi
echo "$$" > "$GLOCK/pid"
trap 'rm -rf "$GLOCK"' EXIT
[ -f "$WDIR/prompt.md" ] || { log "prompt.md 없음: $WDIR"; exit 1; }
for f in design_input.md investment_philosophy_charter.md toolbox.md parent_cell_spec.json; do
  [ -f "$WDIR/$f" ] || { log "작업 폴더 파일 없음: $f"; exit 1; }
done
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo /c/Users/99922/AppData/Roaming/npm/claude)}"
ROOT="${ROOT:-$BASE}"
. "$BASE/02_Infrastructure/ops/rf_llm_env.sh"
rf_llm_resolve chain_generator "${QVEST_CG_MODEL:-}" "${QVEST_CG_EFFORT:-}"
LLM_FALLBACK_MODEL=""                        # 폴백 미탑재(rx_lane.sh 와 같다 — 한도면 물러난다)
[ -x "$CLAUDE_BIN" ] || { log "claude CLI not found ($CLAUDE_BIN)"; exit 1; }
source "$(dirname "${BASH_SOURCE[0]:-$0}")/_sched_failure_classify.sh" 2>/dev/null || true
if command -v sched_check_credentials >/dev/null 2>&1; then
  CRED_ST=$(sched_check_credentials)
  case "$CRED_ST" in ok*|unknown) : ;; *) log "자격증명 사전점검 실패: $CRED_ST — claude 호출 생략"; exit 4 ;; esac
fi
# 자격 토큰을 현재 셸에서 확보한다(명령치환 서브셸 export 미도달 결함 — test_credential_scope_wiring.sh) · 값은 로그로 내지 않는다
command -v sched_resolve_oauth_token >/dev/null 2>&1 && sched_resolve_oauth_token >/dev/null 2>&1 || true
_tokfp="none"
command -v sched_token_fingerprint >/dev/null 2>&1 && _tokfp="$(sched_token_fingerprint 2>/dev/null || echo none)"
log "토큰 지문: ${_tokfp} (값 아님 · sha256 앞12자)"

# -- 가드 탐침(양성 대조) — 무인 호출에서도 생성기 읽기 경계가 실제로 걸리는가 --------------
_guard_fire(){ # $1 = 도구 $2 = 경로 → block | pass | odd
  local js out
  js=$(GP_TOOL="$1" GP_PATH="$2" GP_CWD="$BASE" "${_PYB:-python}" -c "import json,os;t=os.environ['GP_TOOL'];k='file_path' if t=='Read' else 'path';ti={k:os.environ['GP_PATH']};ti.update({'pattern':'*'} if t!='Read' else {});print(json.dumps({'session_id':'chain_gen_probe','hook_event_name':'PreToolUse','cwd':os.environ['GP_CWD'],'tool_name':t,'tool_input':ti}))" 2>/dev/null) || { echo odd; return; }
  out=$(printf '%s' "$js" | QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WDIR" CLAUDE_PROJECT_DIR="$BASE" QM_ROOT="$BASE" \
        QVEST_ARM_GEN_GUARD_LOG="${WDIR%/}.guard_probe.log" "${BASH:-bash}" "$BASE/02_Infrastructure/hooks/arm_gen_read_guard.sh" 2>/dev/null)
  case "$out" in *'"decision":"block"'*|*'"decision": "block"'*) echo block ;; *'"continue":true'*|*'"continue": true'*|'{}'|'') echo pass ;; *) echo odd ;; esac
}
_guard_probe(){
  local w="$1" bad="" rel="${CHAIN_REL:-04_Research/programs/P4_ASSEMBLY/_probe_chain}" p v bs
  _PYB="$(command -v sched_resolve_python >/dev/null 2>&1 && sched_resolve_python 2>/dev/null || echo python)"
  [ -f "$BASE/02_Infrastructure/hooks/arm_gen_read_guard.sh" ] || { log "가드 탐침: 훅 파일 없음"; return 1; }
  grep -q 'arm_gen_read_guard.sh' "$BASE/.claude/settings.json" 2>/dev/null || { log "가드 탐침: settings.json 에 훅 등록 없음(세션 훅이 실리지 않는다)"; return 1; }
  awk '/"matcher"/{m=$0} /arm_gen_read_guard.sh/{print m; exit}' "$BASE/.claude/settings.json" | grep -q 'Read' || { log "가드 탐침: 훅 매처에 Read 없음"; return 1; }
  bs="${BASE//\//\\}"
  for p in "$BASE/06_Registry/round_outcomes.jsonl" "$BASE/$rel/measure/k0.json" "$rel/measure/k0.json" "$BASE/$rel/finalize.json" \
           "G:/OneDrive/Quant_Module_Moltbot/$rel/measure/k0.json" "C:/Users/99922/OneDrive/Quant_Module_Moltbot/$rel/measure/k0.json" \
           "$bs\\${rel//\//\\}\\measure\\k0.json"; do
    v=$(_guard_fire Read "$p"); [ "$v" = "block" ] || bad="$bad Read:$p=$v"
  done
  v=$(_guard_fire Grep "$BASE/$rel"); [ "$v" = "block" ] || bad="$bad Grep:$rel=$v"
  v=$(_guard_fire Read "$w/design_input.md"); [ "$v" = "pass" ] || bad="$bad Read:WDIR/design_input.md=$v(통과여야)"
  if [ -n "$bad" ]; then log "가드 탐침 어긋남:$bad"; return 1; fi
  log "가드 탐침 통과(성과 · 사슬 측정 · 루트 표기 3꼴 block · 작업 폴더 pass)"; return 0
}
_guard_probe "$WDIR" || { log "가드 탐침 실패 — claude 호출 안 함"; printf '{"rc":5,"reason":"guard_probe","model":"none"}\n' > "$WDIR/gen_result.json"; exit 5; }

# -- 생성기 1회(단일 진입 · 청정 표식 · 읽기 3도구) — 시간제한 = 설정 gen_timeout_sec · 환경 QVEST_RUN_TIMEOUT 이 덮는다 --
_run_claude(){
  QVEST_SKIP_AUTO_COMMIT=1 QVEST_SKIP_AUTO_PUSH=1 \
  QVEST_CLEAN_LANE=1 QVEST_CLEAN_WDIR="$WDIR" RF_CLAUDE_BIN="$CLAUDE_BIN" LLM_MODEL="${1:-$LLM_MODEL}" LLM_FALLBACK_MODEL="" \
    rf_llm_agent_run "$WDIR/prompt.md" "$WDIR/out.md" "${QVEST_RUN_TIMEOUT:-$GEN_TMO}" \
      --permission-mode default \
      --allowed-tools "Read,Glob,Grep" \
      --disallowed-tools "Bash,PowerShell,Monitor,REPL,Workflow,CronCreate,RemoteTrigger,Agent,Skill,Write,Edit,NotebookEdit,WebFetch,WebSearch" \
      --add-dir "$WDIR"
  rc=$?
}
log "claude 호출 시작 model=$LLM_MODEL effort=$LLM_EFFORT"
# 알림 창 기준점 — 이 시각 이후 산출만 이 런의 것으로 본다(완주 알림 블록이 넘긴다)
_NOTIFY_SINCE=$(date +%s)
_run_claude ""
log "claude -p exit=$rc"
reason="ok"
if [ "$rc" -ne 0 ]; then
  reason="exit_$rc"
  command -v sched_classify_failure >/dev/null 2>&1 && reason=$(sched_classify_failure "$rc" "$WDIR/out.md" 2>/dev/null || echo "exit_$rc")
fi
rf_llm_limit_hit "$WDIR/out.md" && reason="usage_limit"            # 주간 · 세션 · 한도 문구 전부(RF_LLM_LIMIT_RE) — rc 0 이어도 산출이 아니다
[ "$rc" -eq 124 ] && reason="timeout_kill"
[ "$reason" != "ok" ] && [ "$rc" -eq 0 ] && rc=1
# --- (2026-08-22 도훈 지시 "완주할 때마다") 완주 알림 — tg_agent_brief() 단일 진입점 경유 · 기본 off(틱이 경보를 맡는다 · 재가동 = QVEST_RUN_NOTIFY=1)
_RS="$BASE/02_Infrastructure/ops/research_run_notify.R"
if [ -f "$_RS" ] && [ "${QVEST_RUN_NOTIFY:-0}" = "1" ]; then
  QM_ROOT="$BASE" Rscript --no-save "$_RS" "chain_gen" 0 0 "SAME" "$rc" "" "${_NOTIFY_SINCE:-}" >> "$LOG" 2>&1 || log "완주 알림 실패(비치명)"
fi
printf '{"rc":%s,"reason":"%s","model":"%s"}\n' "$rc" "$reason" "${LLM_USED_MODEL:-?}" > "$WDIR/gen_result.json"
log "끝 rc=$rc reason=$reason"
case "$reason" in
  ok) exit 0 ;;
  usage_limit|session_limit|spend_limit*|rate_limit*|weekly_limit*) exit 3 ;;
  auth_expired|credentials_*|auth*) exit 4 ;;
  timeout_kill) exit 6 ;;
  *) exit 1 ;;
esac
