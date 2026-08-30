#!/usr/bin/env bash
# design_envelope_gate.sh — 설계 단계 실투 envelope 강제 (v10.1 2026-08-29)
#
# 이벤트: PreToolUse[Write|Edit] · 대상: WT-R(강화) 의 alpha_hypothesis.json / alpha_package.json
#
# ★왜 만들었나 (도훈 지적 2026-08-29 "롱숏을 왜 자꾸 설계하는거야 ... HOOK이 없어서 그런건가?")
#   실측 확인: 등록 훅 12종 중 구성 제약을 보는 것은 worktask_constraint_enforcer 하나이고
#   그건 `*/optimization_package.json` 의 target_weights 만 본다. 즉 **설계 단계는 무검사**였다.
#   설계에서 롱숏이 들어오면 하류 전체가 그 위에 쌓이므로 optimizer 단계 검사는 너무 늦다.
#
# ★왜 키워드 검사가 아닌가 (2026-08-29 실측)
#   설계 산출물 12건에서 '롱숏/공매도/long-short' 는 **정당한 문맥에 도배**돼 있다
#   (논문 판독 인용 · 앵커 실격 사유 · 기전 서술 "KR 공매도 제약이 마찰이다").
#   WT-R20260829_012 한 파일에서만 10건이고 전부 정당했다. 키워드 훅은 상시 오탐이 되고,
#   상시 오탐 훅은 곧 해제되거나 무시된다 — 계기가 죽는 표준 경로다.
#   ⇒ **판정을 지는 구성만** 본다. 그런데 그 구성을 담는 필드가 스키마에 없었다
#   (12건 전수: 구성 관련 리프 경로 중 2회 이상 등장한 것이 단 1개).
#   ⇒ 그래서 이 훅은 **구조를 먼저 요구하고 그 구조를 검사한다**. 없으면 차단하되
#      무엇을 적어야 하는지 알려준다(건설적 차단).
#
# 검사 (envelope_declaration 블록):
#   1. long_only == true
#   2. n_max <= 25
#   3. weight_lower_bound >= 0
#   4. verdict_bearing_construction 이 envelope 밖 구성을 지목하지 않을 것
#   5. out_of_envelope_constructions 의 각 항목은 reference_only_not_verdict_bearing == true
#      (논문 원구성을 **참조**하는 것은 정당하다 — 판정을 지면 안 될 뿐이다)
#
# 미적용: WT-D/WT-P(충실구현·운용) 경로 · 다른 파일명 → 무조건 통과.

if [ -z "${QVEST_PY_BIN:-}" ]; then
  QVEST_PY_BIN="${QVEST_PY:-}"; QVEST_PY_BIN="${QVEST_PY_BIN//\//}"
  { [ -n "$QVEST_PY_BIN" ] && [ -x "$QVEST_PY_BIN" ]; } || QVEST_PY_BIN="/c/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"
  [ -x "$QVEST_PY_BIN" ] || QVEST_PY_BIN="$(command -v python.exe 2>/dev/null || echo python3)"
  export QVEST_PY_BIN
fi

set -euo pipefail
trap 'echo "{}"; exit 0' ERR
export PYTHONUTF8=1

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | "$QVEST_PY_BIN" -c 'import json,sys; sys.stdout.reconfigure(encoding="utf-8",errors="replace"); d=json.loads(sys.stdin.buffer.read().decode("utf-8","replace")); ti=d.get("tool_input",{}); print(ti.get("content","") or ti.get("new_string",""))' 2>/dev/null || echo "")

case "$FILE_PATH" in
  */alpha_hypothesis.json|*/alpha_package.json)
    DEG_CONTENT="$CONTENT" DEG_FP="$FILE_PATH" "$QVEST_PY_BIN" <<'PYEOF'
import json, os, re

content = os.environ.get("DEG_CONTENT", "")
fp = (os.environ.get("DEG_FP", "") or "").replace(chr(92), "/")

# 강화(WT-R) 경로만 대상. 충실구현·운용은 구 동작 유지(무검사).
if not re.search(r"WT-R[0-9]{8}_[0-9]{3}", fp):
    print(json.dumps({})); raise SystemExit(0)

# 부분 Edit(new_string)라 JSON 이 아닐 수 있다 — 파싱 불가는 통과(이 훅의 판정 대상 아님).
try:
    d = json.loads(content)
    if not isinstance(d, dict): raise ValueError
except Exception:
    print(json.dumps({})); raise SystemExit(0)

errs = []
env = d.get("envelope_declaration")

if not isinstance(env, dict):
    errs.append(
      "envelope_declaration 블록 누락. 강화 라운드 설계는 판정을 지는 구성을 명시 선언해야 한다. "
      "필수 형태: {\"long_only\": true, \"n_max\": <=25, \"weight_lower_bound\": >=0, "
      "\"verdict_bearing_construction\": \"<1급/2급 판정을 지는 구성 1줄>\", "
      "\"out_of_envelope_constructions\": [{\"what\": \"...\", \"why_referenced\": \"...\", "
      "\"reference_only_not_verdict_bearing\": true}]}. "
      "논문 원구성(롱숏·데실·>25종) 참조는 정당하다 — 마지막 플래그로 참조임을 밝히면 된다."
    )
else:
    if env.get("long_only") is not True:
        errs.append("envelope_declaration.long_only != true (실투 축: w >= 0)")
    n = env.get("n_max")
    if not isinstance(n, int) or isinstance(n, bool) or n > 25 or n < 1:
        errs.append("envelope_declaration.n_max = %r (1~25 정수여야 함 — 종목수 상한 25)" % (n,))
    wlb = env.get("weight_lower_bound")
    if not isinstance(wlb, (int, float)) or isinstance(wlb, bool) or wlb < 0:
        errs.append("envelope_declaration.weight_lower_bound = %r (0 이상이어야 함)" % (wlb,))

    vbc = env.get("verdict_bearing_construction")
    if not isinstance(vbc, str) or len(vbc.strip()) < 10:
        errs.append("envelope_declaration.verdict_bearing_construction 이 비었다 — 무엇이 판정을 지는지 1줄로 적어라")
    else:
        # 판정을 지는 구성 자체가 envelope 밖을 지목하면 차단.
        # (파일 전체가 아니라 이 한 필드만 본다 — 정당한 롱숏 언급과 구분하는 지점이다)
        bad = re.search(r"long[-_ ]?short|롱숏|숏\s*레그|short\s*leg|공매도\s*(포함|편입|사용)|net\s*zero", vbc, re.I)
        if bad:
            errs.append("verdict_bearing_construction 이 envelope 밖 구성을 지목한다: '%s'" % bad.group(0))
        m = re.search(r"(\d{2,4})\s*종", vbc)
        if m and int(m.group(1)) > 25:
            errs.append("verdict_bearing_construction 의 종목수 %s > 25" % m.group(1))

    ooe = env.get("out_of_envelope_constructions")
    if ooe is not None:
        if not isinstance(ooe, list):
            errs.append("out_of_envelope_constructions 는 리스트여야 한다")
        else:
            for i, it in enumerate(ooe):
                if not isinstance(it, dict) or it.get("reference_only_not_verdict_bearing") is not True:
                    errs.append("out_of_envelope_constructions[%d] 에 reference_only_not_verdict_bearing=true 가 없다 "
                                "— envelope 밖 구성은 참조로만 존재할 수 있다" % i)

if errs:
    print(json.dumps({
      "decision": "block",
      "reason": "design_envelope_gate (WT-R 강화 라운드): " + " | ".join(errs)
    }, ensure_ascii=False))
else:
    print(json.dumps({}))
PYEOF
    ;;
  *)
    echo '{}'
    ;;
esac
