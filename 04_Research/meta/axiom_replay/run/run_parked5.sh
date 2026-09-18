#!/usr/bin/env bash
# run_parked5.sh — 파킹 entry 를 언파크해 격자 1회(25+칸)를 **수동** 실행한다.
#   도훈 지시 2026-09-18: "파킹 5건 측정 진행해. 루프는 켜지 마"
#   ★실 config(06_Registry/reinforce_auto_config.json) 는 enabled=false 그대로 — 스케줄러 루프 OFF.
#   ★이 스크립트만 격리 사본(QVEST_RF_CONFIG)을 읽어 러너·B1 설계 레인을 순차 호출한다.
#   ★한 entry 를 소진(status != active)시킨 뒤 다음 entry 로 간다 — 동시에 두 entry 를 active 로 두지 않는다.
#   ★승격·결합·다음 논문 개설은 사본 config 로 차단 + next_paper 의 active_exists 가드로 이중 차단.
set -u
ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot"
PILOT="$ROOT/04_Research/meta/axiom_replay"
export QVEST_RF_CONFIG="$PILOT/run/reinforce_config_parked5.json"
export QM_ROOT="$ROOT"
LOG="$PILOT/run/parked5_run.log"
PY="$ROOT/.venv_qvest_ml/Scripts/python.exe"
[ -x "$PY" ] || PY=python
MAX_ITER=${MAX_ITER:-40}          # entry 당 러너 호출 상한(배치 ≈ 6~8회면 소진)
STALL_MAX=${STALL_MAX:-4}         # attempts_used 가 연속 N회 안 늘면 중단

ts() { date +"%Y-%m-%dT%H:%M:%S%z"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

status_of() {  # base_id -> "status attempts_used"
  "$PY" - "$1" <<'PYEOF'
import io,json,sys
led=json.loads(io.open(r"C:/Users/99922/OneDrive/Quant_Module_Moltbot/06_Registry/reinforce_ledger_l1.json","rb").read().decode("utf-8"))
for e in led.get("entries") or []:
    if e.get("base_id")==sys.argv[1]:
        print(e.get("status"), e.get("attempts_used") or 0); break
else:
    print("missing 0")
PYEOF
}

[ "$#" -ge 1 ] || { echo "usage: run_parked5.sh <base_id> [<base_id>...]"; exit 2; }
log "=== 시작 · 대상 $# entry · config=$QVEST_RF_CONFIG ==="
[ -f "$QVEST_RF_CONFIG" ] || { log "config 사본 없음 — 중단"; exit 2; }
"$PY" -c "import json;c=json.load(open(r'$ROOT/06_Registry/reinforce_auto_config.json',encoding='utf-8'));assert c['enabled'] is False,'실 config enabled=true — 루프가 켜져 있다. 수동 측정 중단'" || exit 3

for BID in "$@"; do
  read -r ST USED <<<"$(status_of "$BID")"
  log "--- $BID · status=$ST used=$USED ---"
  if [ "$ST" = "parked" ]; then
    Rscript "$PILOT/run/unpark_entry.R" "$BID" "도훈 지시 2026-09-18 — 기저 관문 반사실 측정(파킹 5건). 루프 OFF 유지·격리 config 수동 실행. parked_reason 보존." >>"$LOG" 2>&1 || { log "언파크 실패 — 건너뜀"; continue; }
  elif [ "$ST" != "active" ]; then
    log "status=$ST — 대상 아님, 건너뜀"; continue
  fi
  # B1 LLM 설계 1회 (post-0904 체제 동등성). 실패하면 러너가 규칙 선정으로 폴백한다.
  log "B1 설계 레인 호출"
  bash "$ROOT/02_Infrastructure/ops/rf_b1_design.sh" >>"$LOG" 2>&1; log "B1 설계 rc=$?"
  it=0; stall=0; prev="$USED"
  while [ "$it" -lt "$MAX_ITER" ]; do
    it=$((it+1))
    Rscript "$ROOT/02_Infrastructure/ops/reinforce_auto_parallel.R" >>"$LOG" 2>&1; rc=$?
    read -r ST USED <<<"$(status_of "$BID")"
    log "iter=$it rc=$rc status=$ST used=$USED"
    [ "$ST" = "active" ] || break
    if [ "$USED" = "$prev" ]; then stall=$((stall+1)); else stall=0; fi
    prev="$USED"
    if [ "$stall" -ge "$STALL_MAX" ]; then log "진전 없음 ${STALL_MAX}회 — 이 entry 중단(수동 점검 필요)"; break; fi
    sleep 20
  done
  log "완료 $BID · status=$ST used=$USED"
done
log "=== 전체 종료 ==="
