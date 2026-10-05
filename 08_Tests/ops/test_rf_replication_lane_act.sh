#!/usr/bin/env bash
#==============================================================================
# test_rf_replication_lane_act.sh — 충실구현 레인(rf_replication_auto.sh) ACT 계수 = **차단 active 만** (P1-08 · D-G 레인 순서 · 감사 D8-02 · 2026-09-25)
# 방식: 레인 파일에서 ACT 계수 절(ACT_ALL=… ~ 'if [ "${ACT:-0}" != "0" ]' 직전)을 추출해 격리 루트에서 실행(LLM·원장 쓰기 0).
#   술어는 실제 rf_lane_rules.R::rf_blocking_active(파이썬 사본 없음) — 격리 루트에 코드 사본.
# 판정: C1 반사실(idle_only)만 active → 0 · 비차단 로그   C2 신규 논문(normal) active → 1   C3 실험 entry 만 active → 0
#       C4 lanes 설정 없음 → 구판(반사실도 1)   C5 R 판정 불능(술어 파일 부재) → 구판 계수 폴백 + lane_blocking_fallback 로그
#       M1 술어를 active 전부로 바꾼 사본 → C1 에서 1(red)
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY="$(command -v python || command -v python3)"
LANE="$ROOT/02_Infrastructure/ops/rf_replication_auto.sh"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
W=$(mktemp -d "${TMPDIR:-/tmp}/actlane.XXXXXX"); trap 'rm -rf "$W"' EXIT
command -v cygpath >/dev/null 2>&1 && W=$(cygpath -m "$W")
case "$W" in "$ROOT"/*) echo "격리 루트가 ROOT 안이다 — 중단"; exit 1 ;; esac
# ★자식 Rscript 는 R_ENVIRON_USER=<빈 파일> — ~/.Renviron 의 QM_ROOT 가 격리 루트를 운영 루트로 덮는다(09-24~25 운영 오염 3건 · 
#   test_refresh_barrier.sh 선례). 덮이면 방출 원장 기록이 운영 overlay_arm_ledger.jsonl 로 간다.
: > "$W/empty.Renviron"; export R_ENVIRON_USER="$W/empty.Renviron"
BLOCK="$W/act_block.sh"
awk '/^  ACT_ALL=\$\("\$PY" -c "$/{on=1} on && /^  if \[ "\$\{ACT:-0\}" != "0" \]; then$/{exit} on{print}' "$LANE" > "$BLOCK"
grep -q 'rf_blocking_active(d$entries, L)' "$BLOCK" && ok "E0 ACT 절 추출 · 정본 술어 rf_blocking_active 호출" || { ng "E0 ACT 절/술어 없음"; echo "{\"test\":\"rf_replication_lane_act\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"; exit 1; }

mkroot(){   # $1 루트 · $2 lanes(on|off) · $3 active 목록(json 배열) · $4 코드(on|off)
  local R="$1"; mkdir -p "$R/02_Infrastructure/reinforcement" "$R/06_Registry"
  if [ "$4" = on ]; then for f in rf_lane_rules.R rf_spec_sig.R; do cp "$ROOT/02_Infrastructure/reinforcement/$f" "$R/02_Infrastructure/reinforcement/"; done; fi
  printf '{"schema_version":"reinforce_ledger_v2","layer":1,"entries":%s}' "$3" > "$R/06_Registry/reinforce_ledger_l1.json"
  if [ "$2" = on ]; then
    "$PY" -c "
import json,sys
c=json.load(open(sys.argv[1],encoding='utf-8'))
json.dump({'enabled':True,'lanes':c['lanes']},open(sys.argv[2],'w',encoding='utf-8'),ensure_ascii=False)" "$ROOT/06_Registry/reinforce_auto_config.json" "$R/06_Registry/reinforce_auto_config.json"
  else printf '{"enabled": true}' > "$R/06_Registry/reinforce_auto_config.json"; fi
}
run(){   # $1 루트 · $2 블록 → "ACT=<n> EV=<이벤트들>"
  local R="$1" B="${2:-$BLOCK}"; : > "$R/jl.txt"
  cat > "$W/h.sh" <<EOF
set -uo pipefail
ROOT="$R"; PY="$PY"; CFG="$R/06_Registry/reinforce_auto_config.json"
jl(){ printf '%s\n' "\$1" >> "$R/jl.txt"; }
. "$B"
echo "ACT=\$ACT"
EOF
  local a; a=$(bash "$W/h.sh" 2>/dev/null | tr -d '\r' | sed -n 's/^ACT=//p' | tail -1)
  echo "ACT=$a EV=$(tr '\n' ',' < "$R/jl.txt")"
}
CF='{"base_id":"CF","status":"active","priority":"idle_only"}'
NEW='{"base_id":"NEW","status":"active"}'
EXP='{"base_id":"ARM","status":"active","priority":"prereg","experiment":{"prereg_id":"P"}}'
DONE='{"base_id":"OLD","status":"exhausted"}'
R1="$W/r1"; mkroot "$R1" on "[$CF,$DONE]" on; o=$(run "$R1")
case "$o" in "ACT=0 EV=reinforce_active_nonblocking,") ok "C1 반사실만 active → 0 · 비차단 로그";; *) ng "C1" "$o";; esac
R2="$W/r2"; mkroot "$R2" on "[$CF,$NEW]" on; o=$(run "$R2")
case "$o" in "ACT=1 EV=reinforce_active_nonblocking,") ok "C2 신규 논문 active → 1(막는다)";; *) ng "C2" "$o";; esac
R3="$W/r3"; mkroot "$R3" on "[$EXP]" on; o=$(run "$R3")
case "$o" in "ACT=0 EV=reinforce_active_nonblocking,") ok "C3 실험 entry 만 active → 0";; *) ng "C3" "$o";; esac
R4="$W/r4"; mkroot "$R4" off "[$CF]" on; o=$(run "$R4")
case "$o" in "ACT=1 EV=") ok "C4 lanes 설정 없음 → 구판 거동(반사실도 막는다)";; *) ng "C4" "$o";; esac
R5="$W/r5"; mkroot "$R5" on "[$CF]" off; o=$(run "$R5")
case "$o" in "ACT=1 EV=lane_blocking_fallback,") ok "C5 술어 판정 불능 → 구판 계수 폴백(막는 쪽) + 로그";; *) ng "C5" "$o";; esac
MB="$W/mut.sh"; sed 's/length(rf_blocking_active(d\$entries, L))/length(Filter(function(e) identical(e$status, "active"), d$entries))/' "$BLOCK" > "$MB"
if cmp -s "$MB" "$BLOCK"; then ng "M1 돌연변이 앵커 불일치"; else
  R6="$W/r6"; mkroot "$R6" on "[$CF]" on; o=$(run "$R6" "$MB")
  case "$o" in ACT=1*) ok "M1 술어를 active 전부로 바꾼 사본 → C1 에서 1(검사가 잡는다 — red)";; *) ng "M1 돌연변이 생존" "$o";; esac; fi
echo
echo "합계: 통과 $PASS · 실패 $FAIL"
echo "{\"test\":\"rf_replication_lane_act\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ]
