#!/usr/bin/env bash
#==============================================================================
# test_rf_overlay_propose_g1.sh — arm 생성 레인(rf_overlay_propose.sh)의 **G1 적대 감사 경유** 양방향 검사 (2026-09-25)
#   결정 D-G "overlay_propose 는 G1 경유 또는 dead 동안 정지" 의 성과 비소비 분기 · 설계 최종판 §1.1 표 · 감사 D5-F2
# 방식: 레인 파일에서 G1 블록(표지 '★G1 적대 감사 경유' ~ 등재 호출 직전 fi)을 **추출**해 격리 루트에서 실행한다 — LLM·등재기 호출 0.
#   probe·방출 원장 기록은 실제 R 코드(overlay_probe.R · rf_overlay_admit.R)를 격리 루트에서 돌린다. 감사기는 가짜(QVEST_OV_AUDIT_SH).
# 판정:
#   T1 감사 pass(rc 0)        → 등재 단계 도달 · 감사 1회 호출 · arm 파일 보존 · jl g1_pass
#   T2 감사 reject(rc 3)      → 등재 단계 미도달 · 방출 원장 admitted=false · rejected_stage=audit · arm 파일 제거
#   T3 감사 unavailable(rc 4) → 같음 · rejected_stage=audit_unavailable
#   T4 probe 실패 arm(리터럴 문턱) → 감사 **미호출** · 등재 단계 도달(등재기가 같은 probe 로 거부·기록 — 구판과 같은 기록)
#   T5 config overlay_propose_g1.enabled=false → 감사 미호출 · 등재 단계 도달 · jl g1_disabled
#   T6 config 에 키 없음 → 감사 호출(기본 켬 — 막는 쪽)
#   M1 감사 호출을 pass 로 바꾼 사본 → T2 에서 등재 단계 도달(red 여야 한다) · M2 probe 관문 제거 사본 → T4 에서 감사 호출(red)
# 쓰기 = mktemp 격리 루트뿐(운영 카탈로그·원장·로그 무접촉).
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"; ROOT="${ROOT//\\//}"
case "$ROOT" in /[A-Za-z]/*) command -v cygpath >/dev/null 2>&1 && ROOT=$(cygpath -m "$ROOT") ;; esac
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"; [ -x "$PY" ] || PY="$(command -v python || command -v python3)"
LANE="$ROOT/02_Infrastructure/ops/rf_overlay_propose.sh"
PASS=0; FAIL=0
ok(){ printf '  OK   %s\n' "$1"; PASS=$((PASS+1)); }
ng(){ printf '  FAIL %s — %s\n' "$1" "${2:-}"; FAIL=$((FAIL+1)); }
W=$(mktemp -d "${TMPDIR:-/tmp}/g1test.XXXXXX"); trap 'rm -rf "$W"' EXIT
command -v cygpath >/dev/null 2>&1 && W=$(cygpath -m "$W")   # ★R·파이썬(네이티브)이 여는 경로 — POSIX 형(/c/…)은 Windows R 이 못 연다
case "$W" in "$ROOT"/*) echo "격리 루트가 ROOT 안이다 — 중단"; exit 1 ;; esac
# ★자식 Rscript 는 R_ENVIRON_USER=<빈 파일> — ~/.Renviron 의 QM_ROOT 가 격리 루트를 운영 루트로 덮는다(09-24~25 운영 오염 3건 · 
#   test_refresh_barrier.sh 선례). 덮이면 방출 원장 기록이 운영 overlay_arm_ledger.jsonl 로 간다.
: > "$W/empty.Renviron"; export R_ENVIRON_USER="$W/empty.Renviron"

extract_block(){   # $1 = 레인 파일 → G1 블록 텍스트(없으면 빈 출력)
  awk '/★G1 적대 감사 경유/{on=1} on{print} on && /^fi$/{exit}' "$1"
}
BLOCK="$W/g1_block.sh"; extract_block "$LANE" > "$BLOCK"
[ -s "$BLOCK" ] && grep -q 'QVEST_OV_AUDIT_SH' "$BLOCK" && ok "E0 레인 파일에서 G1 블록 추출(감사기 경유 배선 실재)" || { ng "E0 G1 블록 없음 — 배선이 없다"; echo "{\"test\":\"rf_overlay_propose_g1\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"; exit 1; }
# 등재 호출이 블록 **뒤**에 있는가(순서 — 감사를 지나야 등재)
L_G1=$(grep -n '★G1 적대 감사 경유' "$LANE" | head -1 | cut -d: -f1); L_AD=$(grep -n 'rf_overlay_admit_cli.R' "$LANE" | tail -1 | cut -d: -f1)
[ -n "$L_G1" ] && [ -n "$L_AD" ] && [ "$L_G1" -lt "$L_AD" ] && ok "E1 G1 블록이 등재 호출보다 앞(감사 → 등재)" || ng "E1 순서" "$L_G1 / $L_AD"

mkroot(){   # $1 = 루트 · $2 = config 모드(on|off|absent)
  local R="$1"; mkdir -p "$R/02_Infrastructure" "$R/06_Registry" "$R/.cache/scheduler_logs"
  cp -r "$ROOT/02_Infrastructure/reinforcement" "$R/02_Infrastructure/"
  [ -d "$ROOT/02_Infrastructure/portfolio" ] && cp -r "$ROOT/02_Infrastructure/portfolio" "$R/02_Infrastructure/"
  for f in overlay_probe_future.json overlay_probe_allowlist.json; do [ -f "$ROOT/06_Registry/$f" ] && cp "$ROOT/06_Registry/$f" "$R/06_Registry/"; done
  : > "$R/06_Registry/overlay_arm_ledger.jsonl"
  case "$2" in
    on)     printf '{"enabled": true, "overlay_propose_g1": {"enabled": true}}' > "$R/06_Registry/reinforce_auto_config.json" ;;
    off)    printf '{"enabled": true, "overlay_propose_g1": {"enabled": false}}' > "$R/06_Registry/reinforce_auto_config.json" ;;
    absent) printf '{"enabled": true}' > "$R/06_Registry/reinforce_auto_config.json" ;;
  esac
  local AD="$R/02_Infrastructure/reinforcement/overlay_arms"
  sed 's/overlay_expo_dbeta_tilt/overlay_expo_zz_g1_ok/' "$ROOT/02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R" > "$AD/zz_g1_ok.R"
  printf '{"id":"zz_g1_ok_v1","family":"cross_sectional","basis":"검사 픽스처 — dbeta_tilt 사본","est_cost_min":1}' > "$AD/zz_g1_ok.arm.json"
  cat > "$AD/zz_g1_lit.R" <<'EOF'
overlay_expo_zz_g1_lit <- function(H, t, ctx) {
  if (H$dd[t] > 0.2) return(0.5)
  1
}
EOF
  printf '{"id":"zz_g1_lit_v1","family":"drawdown","basis":"검사 픽스처 — 리터럴 문턱(probe 거부 대상)","est_cost_min":1}' > "$AD/zz_g1_lit.arm.json"
}
cat > "$W/fake_audit.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "$FAKE_AUDIT_CALLS"
case "${FAKE_AUDIT_RC:-0}" in
  0) echo "audit: $1 | pass | 채택 발견 0"; exit 0 ;;
  3) echo "audit: $1 | reject | leak(검사 픽스처)"; exit 3 ;;
  *) echo "audit: $1 | unavailable | 축 미산출(검사 픽스처)"; exit 4 ;;
esac
EOF
chmod +x "$W/fake_audit.sh"

run_block(){   # $1 루트 · $2 kind · $3 감사 rc · $4 블록 파일 → stdout 에 ADMIT_REACHED 여부
  local R="$1" K="$2" RC="$3" B="${4:-$BLOCK}"
  : > "$W/calls_$K"; : > "$R/jl.jsonl"
  cat > "$W/harness.sh" <<EOF
set -uo pipefail
ROOT="$R"; PY="$PY"; CFG="$R/06_Registry/reinforce_auto_config.json"; LOG="$R/.cache/scheduler_logs/ovp_test.log"
ADIR="$R/02_Infrastructure/reinforcement/overlay_arms"; KIND="$K"; ACT="scalar_exposure"; ST="drawdown"; RP_MODEL="fixture-model"
jl(){ local ev="\$1"; shift; printf '%s %s\n' "\$ev" "\$*" >> "$R/jl.jsonl"; }
. "$B"
echo ADMIT_REACHED
EOF
  QVEST_OV_AUDIT_SH="$W/fake_audit.sh" FAKE_AUDIT_RC="$RC" FAKE_AUDIT_CALLS="$W/calls_$K" bash "$W/harness.sh" 2>&1
}
emis(){ "$PY" -c "
import json,sys
L=[json.loads(l) for l in open(sys.argv[1],encoding='utf-8') if l.strip()]
print(len(L), (L[-1].get('admitted') if L else ''), (L[-1].get('rejected_stage') if L else ''), (L[-1].get('source') if L else ''))" "$1"; }

# T1 pass
R1="$W/r1"; mkroot "$R1" on; o=$(run_block "$R1" zz_g1_ok 0)
[ "$(wc -l < "$W/calls_zz_g1_ok")" -eq 1 ] && printf '%s' "$o" | grep -q ADMIT_REACHED && grep -q '^g1_pass' "$R1/jl.jsonl" && [ -f "$R1/02_Infrastructure/reinforcement/overlay_arms/zz_g1_ok.R" ] \
  && ok "T1 감사 pass → 등재 단계 도달 · 감사 1회 · arm 보존" || ng "T1" "$(printf '%s' "$o" | tail -3)"
# T2 reject
R2="$W/r2"; mkroot "$R2" on; o=$(run_block "$R2" zz_g1_ok 3); e=$(emis "$R2/06_Registry/overlay_arm_ledger.jsonl")
! printf '%s' "$o" | grep -q ADMIT_REACHED && [ "$e" = "1 False audit overlay_propose" ] && [ ! -f "$R2/02_Infrastructure/reinforcement/overlay_arms/zz_g1_ok.R" ] \
  && grep -q '^admit_rejected_g1' "$R2/jl.jsonl" && ok "T2 감사 reject → 등재 미도달 · 방출 원장 admitted=false/audit · arm 제거" || ng "T2" "emis=[$e] $(printf '%s' "$o" | tail -3)"
# T3 unavailable
R3="$W/r3"; mkroot "$R3" on; o=$(run_block "$R3" zz_g1_ok 4); e=$(emis "$R3/06_Registry/overlay_arm_ledger.jsonl")
! printf '%s' "$o" | grep -q ADMIT_REACHED && [ "$e" = "1 False audit_unavailable overlay_propose" ] \
  && ok "T3 감사 unavailable → 등재 미도달 · audit_unavailable 기록(미판정 = 등재 금지)" || ng "T3" "emis=[$e]"
# T4 probe 실패 arm
R4="$W/r4"; mkroot "$R4" on; o=$(run_block "$R4" zz_g1_lit 0)
[ ! -s "$W/calls_zz_g1_lit" ] && printf '%s' "$o" | grep -q ADMIT_REACHED && grep -q '^g1_skipped_probe_fail' "$R4/jl.jsonl" \
  && ok "T4 probe 실패 arm → 감사 미호출(비용 0) · 등재기로(같은 probe 로 거부·기록)" || ng "T4" "calls=$(wc -l < "$W/calls_zz_g1_lit") $(printf '%s' "$o" | tail -3)"
# T5 disabled
R5="$W/r5"; mkroot "$R5" off; o=$(run_block "$R5" zz_g1_ok 3)
[ ! -s "$W/calls_zz_g1_ok" ] && printf '%s' "$o" | grep -q ADMIT_REACHED && grep -q '^g1_disabled' "$R5/jl.jsonl" \
  && ok "T5 enabled=false → 감사 미호출 · 구판 흐름(등재 단계) · g1_disabled 로그" || ng "T5"
# T6 absent key
R6="$W/r6"; mkroot "$R6" absent; o=$(run_block "$R6" zz_g1_ok 3)
[ "$(wc -l < "$W/calls_zz_g1_ok")" -eq 1 ] && ! printf '%s' "$o" | grep -q ADMIT_REACHED \
  && ok "T6 설정 키 없음 → 감사 건다(기본 켬)" || ng "T6"
# M1 감사 결과 무시 돌연변이
MB="$W/mut1.sh"; sed 's/^    A_RC=\$?$/    A_RC=0/' "$BLOCK" > "$MB"
if cmp -s "$MB" "$BLOCK"; then ng "M1 돌연변이 앵커 불일치"; else
  R7="$W/r7"; mkroot "$R7" on; o=$(run_block "$R7" zz_g1_ok 3 "$MB")
  printf '%s' "$o" | grep -q ADMIT_REACHED && ok "M1 감사 판정 무시 사본 → reject 인데 등재 단계 도달(검사가 잡는다 — red)" || ng "M1 돌연변이 생존" ; fi
# M2 probe 관문 제거 돌연변이
MB2="$W/mut2.sh"; sed 's/^  if \[ "\$PR_RC" -eq 0 \]; then$/  if true; then/' "$BLOCK" > "$MB2"
if cmp -s "$MB2" "$BLOCK"; then ng "M2 돌연변이 앵커 불일치"; else
  R8="$W/r8"; mkroot "$R8" on; o=$(run_block "$R8" zz_g1_lit 0 "$MB2")
  [ -s "$W/calls_zz_g1_lit" ] && ok "M2 probe 관문 제거 사본 → probe 실패 arm 에 감사 호출(검사가 잡는다 — red)" || ng "M2 돌연변이 생존"; fi

echo
echo "합계: 통과 $PASS · 실패 $FAIL"
echo "{\"test\":\"rf_overlay_propose_g1\",\"pass\":$PASS,\"fail\":$FAIL,\"total\":$((PASS+FAIL))}"
[ "$FAIL" -eq 0 ]
