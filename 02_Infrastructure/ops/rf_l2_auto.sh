#!/usr/bin/env bash
#==============================================================================
# rf_l2_auto.sh — 2계층 무인 레인 게이트 (2026-09-21 도훈 승인 플랜 Part 3 · D2)
#   tick(reinforce_auto_tick.sh) 마다 불린다. 조건이 없으면 즉시 종료(다른 레인과 같은 규약):
#     enabled ∧ l2_auto.enabled → l2_unit_request.json pending → R1(selection_type) 결정 기록 → Rscript rf_l2_auto.R
#   실행·claim·원장·텔레그램은 전부 드라이버(rf_l2_auto.R) 몫. 여기는 게이트와 로그만.
#   검사: QVEST_L2_DRY_GATE=1 이면 게이트 통과 후 드라이버를 부르지 않고 gate_pass 만 남긴다.
#==============================================================================
set -uo pipefail
ROOT="${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}"
cd "$ROOT" || exit 1
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY=python
CFG="${QVEST_RF_CONFIG:-$ROOT/06_Registry/reinforce_auto_config.json}"
REQ="${QVEST_L2_REQUEST:-$ROOT/06_Registry/l2_unit_request.json}"
JLOG="${QVEST_RP_JLOG:-$ROOT/.cache/reinforce_auto_log.jsonl}"
LOG="$ROOT/.cache/scheduler_logs/l2_auto_$(date +%Y%m%d).log"
mkdir -p "$(dirname "$LOG")" "$(dirname "$JLOG")"
jl(){ "$PY" -c "
import io,json,sys,time
rec={'ts':time.strftime('%Y-%m-%dT%H:%M:%S%z'),'event':sys.argv[1],'src':'l2_auto'}
for kv in sys.argv[2:]:
    k,_,v=kv.partition('='); rec[k]=v
io.open(r'$JLOG','a',encoding='utf-8').write(json.dumps(rec,ensure_ascii=False)+'\n')
print('[l2_auto] '+sys.argv[1])" "$@" ; }
read -r EN R1 <<<"$("$PY" -c "
import io,json
try:
    c=json.loads(io.open(r'$CFG','rb').read().decode('utf-8')); l=c.get('l2_auto') or {}
    en='1' if c.get('enabled') and l.get('enabled') else '0'
    r1='1' if (l.get('selection_type') in ('chain','sweep') and l.get('decided_by') and l.get('decided_at')) else '0'
    print(en, r1)
except Exception: print('0 0')" 2>/dev/null)"
[ "${EN:-0}" = "1" ] || { jl halt_disabled; exit 0; }
ST=$("$PY" -c "
import io,json
try: print(json.loads(io.open(r'$REQ','rb').read().decode('utf-8')).get('status') or 'none')
except Exception: print('none')" 2>/dev/null)
[ "$ST" = "pending" ] || { jl not_due "status=$ST"; exit 0; }
[ "${R1:-0}" = "1" ] || { jl halt_r1_undecided "note=config l2_auto.selection_type(chain|sweep)+decided_by+decided_at 미기록 — 도훈 결정 전 레인 정지"; exit 0; }
[ "${QVEST_L2_DRY_GATE:-0}" = "1" ] && { jl gate_pass "note=dry gate"; exit 0; }
echo "=== $(date -Iseconds) l2_auto 드라이버 시작 ===" >> "$LOG"
Rscript "$ROOT/02_Infrastructure/ops/rf_l2_auto.R" >> "$LOG" 2>&1; RC=$?
echo "=== $(date -Iseconds) l2_auto 드라이버 종료 rc=$RC ===" >> "$LOG"
exit 0
