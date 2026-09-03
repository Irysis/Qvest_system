#!/usr/bin/env bash
#==============================================================================
# test_arm_gen_read_guard.sh — arm 생성 세션 성과 열람 차단 계약 (v10.2 2026-09-03)
#
# ★두 방향을 다 잰다: 생성 세션에서 **막는가**, 평시에 **안 막는가**.
#   상시 오탐 훅은 곧 해제되거나 무시된다 — 계기가 죽는 표준 경로다.
#==============================================================================
set -uo pipefail
ROOT="${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}"
HOOK="$ROOT/02_Infrastructure/hooks/arm_gen_read_guard.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  OK    %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  FAIL  %s — %s\n' "$1" "${2:-}"; }

fire(){ # $1=env(0/1) $2=json
  if [ "$1" = "1" ]; then printf '%s' "$2" | QVEST_ARM_GEN=1 bash "$HOOK" 2>/dev/null
  else printf '%s' "$2" | bash "$HOOK" 2>/dev/null; fi
}
J_LEDGER='{"tool_name":"Read","tool_input":{"file_path":"06_Registry/reinforce_ledger_l1.json"}}'
J_AUTH='{"tool_name":"Read","tool_input":{"file_path":"04_Research/x/stage_artifacts/authoritative_remeasure.json"}}'
J_MAP='{"tool_name":"Read","tool_input":{"file_path":"06_Registry/overlay_mechanism_map.json"}}'
J_ARM='{"tool_name":"Read","tool_input":{"file_path":"02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R"}}'
J_GREP='{"tool_name":"Grep","tool_input":{"pattern":"grade","path":"06_Registry/reinforce_ledger_l1.json"}}'

echo "=== test_arm_gen_read_guard ==="

# ① 음성 대조 — 평시엔 같은 경로도 통과해야 한다(소음 0)
case "$(fire 0 "$J_LEDGER")" in
  '{}') ok "① 평시 무발화 — 측정 경로도 통과" ;;
  *) ng "① 평시에 발화했다 — 상시 오탐은 훅을 죽인다" "$(fire 0 "$J_LEDGER")" ;;
esac

# ②~④ 위반 주입 — 생성 세션에서 성과 경로 3종
for pair in "원장:$J_LEDGER" "권위재측정:$J_AUTH" "기전지도:$J_MAP"; do
  lbl="${pair%%:*}"; js="${pair#*:}"
  out="$(fire 1 "$js")"
  case "$out" in
    *ARM_GEN_READ_BLOCKED*) ok "② 생성 세션 차단 — $lbl" ;;
    *) ng "② 생성 세션에서 $lbl 이 통과했다" "$out" ;;
  esac
done

# ⑤ 과잉 차단 없음 — arm 디렉터리는 읽어야 일을 한다
case "$(fire 1 "$J_ARM")" in
  '{}') ok "⑤ 과잉 차단 없음 — overlay_arms 는 생성 세션에서도 읽힌다" ;;
  *) ng "⑤ arm 디렉터리가 막혔다 — 생성기가 본보기를 못 읽는다" "$(fire 1 "$J_ARM")" ;;
esac

# ⑥ Grep 의 path 키도 본다 — file_path 만 보면 Grep 로 우회된다
case "$(fire 1 "$J_GREP")" in
  *ARM_GEN_READ_BLOCKED*) ok "⑥ Grep path 키도 차단 — file_path 만 보는 우회 없음" ;;
  *) ng "⑥ Grep 로 원장을 읽을 수 있다" "$(fire 1 "$J_GREP")" ;;
esac

# ⑦ 등록 — 훅이 settings.json 에 실제로 걸려 있는가(파일만 있고 안 도는 계기 금지)
PY="${QVEST_PY:-$ROOT/.venv_qvest_ml/Scripts/python.exe}"
REG="$("$PY" -c "
import json,io
d=json.load(io.open(r'$ROOT/.claude/settings.json',encoding='utf-8'))
print(int(any('arm_gen_read_guard.sh' in json.dumps(g) for g in d['hooks'].get('PreToolUse',[]))))
" 2>/dev/null || echo 0)"
[ "$REG" = "1" ] && ok "⑦ settings.json 에 등록됨" || ng "⑦ 미등록 — 존재하지만 발화하지 않는 계기"

echo
printf '합계: 통과 %d · 실패 %d\n' "$PASS" "$FAIL"
printf '{"test":"arm_gen_read_guard","pass":%d,"fail":%d,"total":%d}\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
