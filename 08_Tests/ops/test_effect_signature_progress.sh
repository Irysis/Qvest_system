#!/bin/bash
# test_effect_signature_progress.sh — 진척 판정이 자기보고가 아니라 **원장**을 보는가 (2026-08-22)
#
# 왜 있나 (실사고 2026-08-22 16:31):
#   qepm_dossier 첫 런이 WT-D20260822_004 를 SPEC_APPROVED → ALPHA_DONE 으로 전이시키고
#   alpha_package.json · alpha_validation.json · artifact_lineage.json 을 만들었다.
#   **일은 다 했는데** stdout 에 MODEQ_DONE 을 안 내서 zero_progress 가 오경보했다.
#   구판 가드는 에이전트 **자기보고 한 줄**만 봤다 — 오늘 하루 반복 확인된 교훈의 반대다.
#   자기보고 누락은 흔하고, 그때마다 경보가 나면 경보가 '학습된 무시'가 된다.
#
# ★양방향: 효과가 있으면 경보하지 않고(오경보 방지), 없으면 경보한다(검출력 유지).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
SIG="$ROOT/02_Infrastructure/ops/research_effect_signature.py"
PY="${QVEST_PY:-python}"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$SIG" ]; then echo "  SKIP  지문 모듈 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0; fi
if ! "$PY" -c "print(1)" >/dev/null 2>&1; then
  echo "  SKIP  실물 python 없음 (QVEST_PY 미설정)"; echo "== t_summary: PASS=0 FAIL=0 =="; exit 0; fi

FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/06_Registry" "$FIX/qepm/mailbox/worktask"
reg(){ printf '{"modules": %s}' "$1" > "$FIX/06_Registry/module_catalog.json"; }
mreg(){ printf '{"methods": %s}' "$1" > "$FIX/06_Registry/method_registry.json"; }
qua(){ printf '{"modules": %s}' "$1" > "$FIX/06_Registry/module_quarantine.json"; }
wt(){ d="$FIX/qepm/mailbox/worktask/$1"; mkdir -p "$d"; printf '{"current_phase":"%s"}' "$2" > "$d/status.json"; }
sig(){ "$PY" "$SIG" "$FIX"; }
cmp_(){ "$PY" "$SIG" "$FIX" --compare "$1"; }

reg '[]'; mreg '[]'; qua '[]'; wt WT-A ALPHA_DONE
B="$(sig)"

echo "== 양성 대조 1: 아무것도 안 바뀌면 SAME 인가 (검출력 유지) =="
[ "$(cmp_ "$B")" = "SAME" ] && ok "무변화 → SAME (진짜 무진척이면 경보 가능)" \
  || ng "무변화 판정" "got=$(cmp_ "$B")"

echo "== 위반 주입 1: WT phase 전이를 감지하는가 (실사고 재현) =="
# 이게 정확히 16:31 에 일어난 일 — 자기보고는 없고 phase 만 바뀌었다.
wt WT-A RISK_DONE
[ "$(cmp_ "$B")" = "CHANGED" ] && ok "phase 전이 → CHANGED (오경보 방지)" \
  || ng "phase 전이 감지" "자기보고 없는 진척을 무진척으로 읽는다"
wt WT-A ALPHA_DONE

echo "== 위반 주입 2: WT 산출물 증가를 감지하는가 =="
: > "$FIX/qepm/mailbox/worktask/WT-A/alpha_package.json"
[ "$(cmp_ "$B")" = "CHANGED" ] && ok "산출물 추가 → CHANGED" \
  || ng "산출물 감지" "패키지가 생겼는데 무진척으로 읽는다"
rm -f "$FIX/qepm/mailbox/worktask/WT-A/alpha_package.json"

echo "== 위반 주입 3: 신규 WT 를 감지하는가 =="
wt WT-B SPEC_APPROVED
[ "$(cmp_ "$B")" = "CHANGED" ] && ok "WT 신설 → CHANGED" || ng "WT 신설 감지" "승격 산출을 못 본다"
rm -rf "$FIX/qepm/mailbox/worktask/WT-B"

echo "== 위반 주입 4: method 측정 기입만 늘어도 감지하는가 =="
# method_measure 레인은 등재 없이 measurement_status 만 채운다 — 개수로는 안 보인다.
mreg '[{"method_id":"M1"}]'; B2="$(sig)"
mreg '[{"method_id":"M1","measurement_status":"측정 완료"}]'
[ "$(cmp_ "$B2")" = "CHANGED" ] && ok "measured 증가 → CHANGED (개수 불변인데도 감지)" \
  || ng "측정 기입 감지" "등재 수가 같으면 못 본다 — method_measure 레인이 통째로 오경보"

echo "== 위반 주입 5: quarantine 만 늘어도 감지하는가 =="
mreg '[]'; B3="$(sig)"; qua '[{"strategy_id":"S1"}]'
[ "$(cmp_ "$B3")" = "CHANGED" ] && ok "quarantine 증가 → CHANGED (floor 미달도 산출이다)" \
  || ng "quarantine 감지" "grade F 격리를 무진척으로 읽는다"

echo "== 계약 검사: 러너가 이 판정을 실제로 부르는가 =="
R="$ROOT/02_Infrastructure/ops/mode_queue_research_run.sh"
if grep -q '_EFFECT_BEFORE=' "$R" && grep -q 'compare "${_EFFECT_BEFORE' "$R" \
   && grep -q 'CHANGED' "$R"; then
  ok "러너 배선 존재 (만들고 안 부르는 상태 아님)"
else
  ng "러너 배선" "지문 모듈이 소비자 없이 존재 — 오늘 sched_token_fingerprint 와 같은 계통"
fi

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ] || exit 1
