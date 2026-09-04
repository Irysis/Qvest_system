#!/usr/bin/env bash
#==============================================================================
# rf_axiom_brief.sh — 무인 LLM 레인에 **공리를 주입**하는 단일 지점 (도훈 지시 2026-09-04)
#
# 왜: 공리 주입 경로가 둘 있었는데 둘 다 LLM 판단 지점에 안 닿았다.
#   ① axiom_context_inject.sh = PreToolUse[Agent] 훅 — 무인 레인은 Agent 를 **0개** 스폰하고
#      `claude -p` 를 직접 부르므로 발화하지 않는다.
#   ② rf_preflight.R = 셀 스펙에 공리를 실어 준다 — 그런데 rf_cell_engine 은 preflight 를
#      **한 번도 참조하지 않는다**(grep 0건). 기록으로만 남는다.
#   ⇒ 결과: 규칙이 도는 자리에만 공리가 실리고, 정작 **판단이 일어나는 네 지점**
#     (구현 설계 · 충실도 감사 · B1 설계 · 블록 기전)은 비어 있었다.
#
# 정본은 하나다: qepm/memory/axioms/active/AX-*.json — rf_preflight 와 같은 디렉터리를 읽는다.
#   ★절단하지 않는다. 110자 절단은 원장 기록용이고, 판단에 쓰려면 문장이 온전해야 한다.
#
# 공리는 **전제**이지 지시가 아니다. 특히 AX-000 은 "소수 실패를 구조적 한계로 단정하지 말라"
#   이므로, 이걸 주지 않으면 기전 에이전트가 세 칸 보고 "이 축은 죽었다" 로 닫아 버린다.
#
# 사용: . rf_axiom_brief.sh ;  AXB="$(rf_axiom_brief)"  →  PROMPT 에 삽입
#==============================================================================
rf_axiom_brief() {
  local root="${ROOT:-${QVEST_RF_ROOT:-${QM_ROOT:-C:/Users/99922/OneDrive/Quant_Module_Moltbot}}}"
  local py="${QVEST_PY:-${root}/.venv_qvest_ml/Scripts/python.exe}"
  "$py" - "$root" <<'PYAXB'
import glob, io, json, os, sys
root = sys.argv[1]
d = os.path.join(root, "qepm", "memory", "axioms", "active")
fs = sorted(glob.glob(os.path.join(d, "AX-*.json")))
out = []
for f in fs:
    try:
        a = json.loads(io.open(f, "rb").read().decode("utf-8"))
    except Exception:
        continue
    aid = a.get("axiom_id") or a.get("id") or os.path.basename(f).replace(".json", "")
    name = (a.get("name") or "").strip()
    txt = (a.get("statement") or a.get("text") or "").strip()
    if not txt:
        continue
    out.append("- **%s%s** — %s" % (aid, (" · " + name) if name else "", " ".join(txt.split())))
if not out:
    raise SystemExit(0)
print("## 공리 (전제 — 지시가 아니다)")
print("아래는 이 저장소가 실측으로 세운 전제다. 네 판단은 이 위에서 이뤄진다.")
print("어긋나는 결론을 낼 수는 있지만, 그때는 **무엇이 이 전제를 뒤집는 증거인지** 적어라.")
print()
print("\n".join(out))
print()
PYAXB
}
