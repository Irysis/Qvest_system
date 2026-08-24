#!/bin/bash
# test_auto_alpha_gate_tiers.sh — 무인 판정 게이트의 **계층·계약·권위** (2026-08-22 신설)
#
# 왜 있나 (논문 라우터 전수 감사 후속, 실측 3결함):
#  ① 선언과 실제가 갈렸다 — 구판 gate_rule 은 4층만 말하는데 원장엔 `L5_hard_fail_grade_F`
#     로 떨어진 건이 있었다. auto_verify_FQ110B_20260808.json 을 구판으로 **재실행하면 ADOPT**
#     가 나오는데 파일 기록은 QUARANTINE. 게이트가 hard_fail 을 안 읽어 재실행이 판정을 뒤집었다.
#  ② 계층 분리 소실 — measurement-graduation.md §3 의 screen_route 를 구판은 **한 번도**
#     발급하지 않았다(키워드 전수 0). FQ110B 는 oos_retention 1.267 · IC +0.0278 · PIT 15/0 인데
#     MDD 62.7% 하나로 폐기됐다 — §3 이 지목한 그 구조 모순 그대로.
#  ③ 입력 계약 2갈래 중 1갈래만 읽음 — 비-flat 10/21 이 `NULL→FALSE→QUARANTINE` 으로 흡수됐다.
#     (실현 손실은 0 이었다 — 잠복 결함이지 수율 0 의 원인은 아니다. 그래도 닫는다.)
#
# ★1급 축은 "판정이 맞는가" 가 아니라 **"판정과 미판정이 구분되는가"** 다.
#   못 읽은 것을 QUARANTINE 으로 흡수하면 '재료가 약하다' 와 '읽지 못했다' 가 같은 라벨이 되고,
#   그 순간 수율 진단이 통째로 무의미해진다.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$(cd "$SELF_DIR/../.." && pwd)"
GATE="$ROOT/02_Infrastructure/ops/auto_alpha_gate.R"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
ng(){ FAIL=$((FAIL+1)); echo "  FAIL  $1 :: $2"; }

if [ ! -f "$GATE" ]; then echo "  SKIP  게이트 부재"; echo "== t_summary: PASS=0 FAIL=0 =="; printf '{"test":"auto_alpha_gate_tiers","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"게이트 부재","missing":"%s"}]}\n' "$GATE"; exit 0; fi
command -v Rscript >/dev/null 2>&1 || { echo "  SKIP  Rscript 없음"; echo "== t_summary: PASS=0 FAIL=0 =="; printf '{"test":"auto_alpha_gate_tiers","pass":0,"fail":0,"total":0,"skipped":1,"skips":[{"axis":"ALL","reason":"Rscript 없음","missing":"%s"}]}\n' "Rscript (command -v 실패)"; exit 0; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run(){ # run <json문자열> → "exit|stdout마지막줄"
  printf '%s' "$1" > "$T/v.json"
  local out rc
  out=$(Rscript --no-save "$GATE" "$T/v.json" 2>&1); rc=$?
  printf '%s|%s' "$rc" "$(printf '%s' "$out" | tail -1)"
}
field(){ "${QVEST_PY:-python}" -c "
import json,io,sys
print(json.load(io.open(sys.argv[1],encoding='utf-8')).get(sys.argv[2],''))" "$T/v.json" "$1" 2>/dev/null; }

echo "== 양성 대조: 4층 PASS ∧ hard_fail 없음 → ADOPT(exit 0) =="
R=$(run '{"paper_id":"X","pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true}')
[ "${R%%|*}" = "0" ] && [ "${R#*|}" = "ADOPT" ] && ok "ADOPT · exit 0" || ng "ADOPT 경로" "got=$R"

echo "== 위반 주입 1: 4층 PASS 인데 구조 hard_fail → SCREEN_TIER(실사고 FQ110B 재현) =="
R=$(run '{"paper_id":"FQ110B","pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true,"hard_fail":true,"hard_fail_reason":"Structural drawdown (45%+ episodes>=15): MDD 62.7%"}')
case "${R#*|}" in
  SCREEN_TIER*) ok "구조 탈락 + 신호 생존 → SCREEN_TIER" ;;
  ADOPT*)       ng "hard_fail 무시" "MDD 62.7% 인데 채택 — 재실행이 판정을 뒤집는 구판 그대로" ;;
  *)            ng "SCREEN_TIER 미발급" "신호가 실재하는데 통째로 버린다: $R" ;;
esac
[ "${R%%|*}" = "1" ] && ok "SCREEN_TIER 는 exit 1 (L-code 적립 금지 유지)" \
  || ng "exit 코드" "screening 라벨이 자본 경로를 열면 §3 위반: exit=${R%%|*}"
[ "$(field screen_route)" = "OVERLAY_CANDIDATE" ] && ok "screen_route=OVERLAY_CANDIDATE 기록" \
  || ng "라우팅 라벨" "got=$(field screen_route)"

echo "== 경계: turnover 사유는 TURNOVER_REVIEW 로 갈리는가 =="
R=$(run '{"pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true,"hard_fail":true,"hard_fail_reason":"turnover 320% 연 — 비용 초과"}')
[ "$(field screen_route)" = "TURNOVER_REVIEW" ] && ok "turnover → TURNOVER_REVIEW" \
  || ng "사유별 라우팅" "got=$(field screen_route)"

echo "== ★라우팅 축 독립(v9.1 S2a): hard_fail=false 인데 screen_route_hint 만으로 SCREEN_TIER =="
# 왜 이 케이스가 필요한가: 위 3건은 전부 hard_fail=true 인 합성 입력이라 구 게이트로도 통과한다.
#   리서치 층에서 MDD 의 탈락 권한이 사라지면(E-2) **hard_fail=false 인데 결합 층으로 가야 하는**
#   상태가 새로 생긴다 — 구판은 `structural = hard_fail && grepl(...)` 라 그 순간 발급이 0 이 된다.
#   등급 C 로 ADOPT 를 닫아 두고(등급 바닥은 불변), 라우팅만 hint 로 살아나는지 잰다.
R=$(run '{"paper_id":"S2A","pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true,"hard_fail":false,"grade":"C","screen_route_hint":"OVERLAY_CANDIDATE"}')
case "${R#*|}" in
  SCREEN_TIER*) ok "hard_fail 없이도 route_hint 로 SCREEN_TIER (라우팅이 hard_fail 에서 분리됨)" ;;
  *)            ng "라우팅 축 미분리" "MDD 가 탈락 권한을 잃으면 이 입력이 표준이 된다 — 결합 층 재료가 통째로 사라진다: $R" ;;
esac
[ "$(field screen_route)" = "OVERLAY_CANDIDATE" ] && ok "route_hint 라벨 보존" \
  || ng "라벨 소실" "got=$(field screen_route)"

echo "== 위반 주입 2: 신호가 죽었으면 구조 사유여도 SCREEN_TIER 아님 =="
# robustness FAIL = 신호 자체가 OOS 를 못 견딤. 소비면으로 보낼 재료가 아니다.
R=$(run '{"pit_pass":true,"contract_pass":true,"robustness_pass":false,"fidelity_pass":true,"hard_fail":true,"hard_fail_reason":"Structural drawdown MDD 70%"}')
case "${R#*|}" in
  QUARANTINE*) ok "robustness FAIL → QUARANTINE (screening 남발 방지)" ;;
  *)           ng "screening 남발" "신호가 죽었는데 소비면으로 보낸다: $R" ;;
esac

echo "== 위반 주입 3: PIT FAIL 은 무엇과도 무관하게 탈락 =="
R=$(run '{"pit_pass":false,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true,"hard_fail":true,"hard_fail_reason":"Structural drawdown MDD 60%"}')
case "${R#*|}" in
  QUARANTINE*) ok "PIT FAIL → QUARANTINE (계층 무관 절대 기각)" ;;
  *)           ng "PIT 우회" "PIT 위반이 screening 라벨로 살아난다: $R" ;;
esac

echo "== 계약 축: L계층 스키마를 읽는가 (구판은 못 읽어 NULL→FALSE) =="
R=$(run '{"paper_id":"Y","L1_pit_pass":"PASS","L2_contract_pass":"PASS","L3_robustness_pass":"PASS","L4_fidelity_pass":"PASS"}')
[ "${R#*|}" = "ADOPT" ] && ok "L계층 4층 PASS → ADOPT (구판은 원리적으로 불가)" \
  || ng "L계층 미독해" "비-flat 입력에서 ADOPT 를 낼 수 없다: $R"

echo "== ★미판정 축: 어느 층도 못 읽으면 판정이 아니라 오류(exit 2) =="
R=$(run '{"paper_id":"Z","factor_id":"f","created_at":"20260802","impl_spec":{}}')
[ "${R%%|*}" = "2" ] && ok "계약 불일치 → exit 2 (판정 아님)" \
  || ng "결손을 정상값으로" "읽지 못한 것을 QUARANTINE 으로 흡수 — 수율 진단이 무의미해진다: $R"
[ "$(field gate_decision)" = "ERROR_UNREADABLE" ] && ok "gate_decision=ERROR_UNREADABLE 로 식별" \
  || ng "오류 라벨" "got=$(field gate_decision)"

echo "== SKIP 값을 FALSE 로 접지 않는가 (3값 판정) =="
R=$(run '{"L1_pit_pass":"SKIP_NOT_EXECUTED","L2_contract_pass":"SKIP_NOT_EXECUTED","L3_robustness_pass":"SKIP_NOT_EXECUTED","L4_fidelity_pass":"FAIL"}')
# 하나라도 읽혔으므로(FAIL) 오류가 아니라 판정이다 — 단 SKIP 을 PASS 로 읽어서도 안 된다
[ "${R%%|*}" = "1" ] && ok "일부만 읽히면 판정 진행 (전부 NA 일 때만 오류)" || ng "3값 처리" "got=$R"

echo "== 권위 축: 결정적 게이트의 서명이 남는가 (에이전트 판정과 구분) =="
run '{"pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true}' >/dev/null
[ "$(field gate_authority)" = "auto_alpha_gate.R" ] && ok "gate_authority 서명 기록" \
  || ng "권위 미표기" "에이전트가 쓴 gate_decision 과 구분 불가 — 실사고 FQ110B 가 그 상태였다"

echo "== 선언 축: gate_rule 이 실제 판정 축을 전부 말하는가 =="
run '{"pit_pass":true,"contract_pass":true,"robustness_pass":true,"fidelity_pass":true}' >/dev/null
RULE="$(field gate_rule)"
echo "$RULE" | grep -q "hard_fail" && ok "규칙이 hard_fail 을 명시" \
  || ng "선언≠실제" "구판처럼 4층만 말하면 재실행이 판정을 뒤집는다"
echo "$RULE" | grep -q "면제" && ok "규칙이 '자본 tier 면제 없음' 을 명시" \
  || ng "면제 경계" "screening 라벨이 자본 경로로 오해될 수 있다"

echo "== t_summary: PASS=$PASS FAIL=$FAIL =="
printf '{"test":"auto_alpha_gate_tiers","pass":%d,"fail":%d,"total":%d,"skipped":0}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ] || exit 1
