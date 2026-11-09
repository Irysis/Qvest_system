"""lift_stale_aliases.py — 창 결함으로 생긴 별칭 선언 2건(C10 · C13) 해제 (2026-11-10 · 일회성 writer).

왜: 등록부 dedup 블록이 스스로 적어 둔 규칙(defect.revisit_on) —
    ".cons_history() 가 분기 관측으로 축약되도록 수리되면 이 alias 선언은 무효다 — 재측정 후 재선언할 것".
    창 수리(08-10)가 11-09~10 전 기간 재계산으로 처음 전 기간에 반영됐다. 같은 표본 6개월 재측정
    (alias_remeasure_20261110.json · 순위 상관 = emission_guard 축 I 기준):
      C10_SUE_Persistence ~ C01_SUE           rho 0.497 ~ 0.618 (중앙 n 292)
      C13_Revision_Breadth_3m ~ C04_ESBR      rho 0.555 ~ 0.662 (중앙 n 420)
      나머지 별칭 9쌍                           rho >= 0.999984 (선언 유효 · 건드리지 않는다)
    alias = '구성상 같은 양'(apply_factor_dedup.R) 인데 두 쌍은 더 이상 같은 양이 아니다. 선언이 남아 있으면
    dedup=TRUE 소비자(결합용 뷰 기본값 · drop_alias_factors · collapse_alias_rows)가 두 팩터를 버린다.

무엇을 하나(두 사본 같은 내용 · 동시 변경 검사):
  C10 · C13 : dedup 블록을 retired_dedup 로 옮긴다(소비자는 dedup 만 읽는다 — 이력은 그대로 남는다) + 해제 기록
  C01_SUE   : dedup.aliases 에서 C10 제거 + lifted_aliases 기록(C09 별칭 · C05 상대 · 군집 DUPC-005 는 유지)
  C04_ESBR  : 군집 DUPC-045 의 유일한 짝(C13)이 빠져 정본 역할이 비므로 dedup → retired_dedup + 해제 기록
  재선언: 두 팩터는 이제 각자 독립 팩터다(redundant 문턱에도 못 미침 — 최대 0.662). 새 선언 없음.
  ★이력 키 이름 = retired_dedup('dedup' 으로 시작하면 안 된다): R 의 `$` 는 목록에서 부분 일치를 하므로
    `reg[[k]]$dedup` 이 dedup_history 같은 키를 그대로 집는다. 커넥터는 fromJSON(simplifyVector = TRUE) 로 읽어
    그 이력이 표가 되고 $role = "alias" 가 읽혀 해제한 별칭이 계속 접혔다(첫 실행 11-10 04:1x 실측 → 키 이름 교체).

실행: <venv python> -X utf8 04_Research/01_reports/factor_alias_remeasure_20261110/lift_stale_aliases.py [--dry-run]
"""
import copy
import hashlib
import json
import os
import sys

ROOT = os.environ.get("QM_ROOT", "").replace("\\", "/") or "G:/OneDrive/Quant_Module_Moltbot"
REGS = [os.path.join(ROOT, "02_Infrastructure", "factor_db", "factor_registry.json"),
        os.path.join(ROOT, ".cache", "factor_db", "factor_registry.json")]
EVID = "04_Research/01_reports/factor_alias_remeasure_20261110/alias_remeasure_20261110.json"
TODAY = "2026-11-10"
DRY = "--dry-run" in sys.argv


def dump(o):
    return (json.dumps(o, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def main():
    raw = [open(p, "rb").read() for p in REGS]
    if raw[0] != raw[1]:
        print("[lift] 두 사본이 다르다 — 중단(direction_sync 가 먼저 맞춰야 한다)"); return 3
    if dump(json.loads(raw[0].decode("utf-8"))) != raw[0]:
        print("[lift] 서식 왕복 불일치 — 중단"); return 3
    h0 = hashlib.sha256(raw[0]).hexdigest()
    reg = json.loads(raw[0].decode("utf-8"))
    ev = json.load(open(os.path.join(ROOT, EVID), encoding="utf-8"))
    sm = {r["alias"]: r for r in ev["summary"]}

    def lift_rec(fac, why):
        r = sm[fac]
        return {"lifted_at": TODAY, "rule": "dedup.defect.revisit_on (등록부 자체 규칙 — 창 수리 후 선언 무효 · 재측정 후 재선언)",
                "why": why,
                "remeasure": {"months": ev["months"], "basis": ev["basis"], "min_rho": r["min_rho"], "max_rho": r["max_rho"],
                              "median_n_common": r["med_n_common"], "report": EVID},
                "redeclared": "없음 — 독립 팩터(redundant 문턱에도 못 미침)"}

    plan = []
    for fac, canon in (("C10_SUE_Persistence", "C01_SUE"), ("C13_Revision_Breadth_3m", "C04_ESBR")):
        d = reg[fac].get("dedup")
        if not d or d.get("role") != "alias" or d.get("canonical") != canon:
            print(f"[lift] {fac}: 예상한 별칭 선언이 아니다({d and d.get('role')}) — 중단"); return 3
        r = sm.get(fac)
        if not r or r["canonical"] != canon or r["months"] < 6 or r["max_rho"] >= 0.999:
            print(f"[lift] {fac}: 재측정 근거가 해제를 뒷받침하지 않는다({r}) — 중단"); return 3
        old = copy.deepcopy(d)
        old["lift"] = lift_rec(fac, f"창 수리(08-10) 전 기간 반영 뒤 {canon} 와 순위 상관 {r['min_rho']:.3f}~{r['max_rho']:.3f} — 같은 양이 아니다")
        reg[fac].setdefault("retired_dedup", []).append(old)
        del reg[fac]["dedup"]
        plan.append(f"{fac}: dedup(alias → {canon}) → retired_dedup")
    c01 = reg["C01_SUE"]["dedup"]
    c01["aliases"] = [a for a in c01.get("aliases", []) if a != "C10_SUE_Persistence"]
    c01.setdefault("lifted_aliases", []).append(dict(factor="C10_SUE_Persistence", **lift_rec("C10_SUE_Persistence", "C10 별칭 해제")))
    plan.append(f"C01_SUE: aliases → {c01['aliases']} · lifted_aliases += C10")
    c04 = copy.deepcopy(reg["C04_ESBR"]["dedup"])
    if c04.get("aliases") != ["C13_Revision_Breadth_3m"]:
        print(f"[lift] C04_ESBR: 예상과 다른 aliases {c04.get('aliases')} — 중단"); return 3
    c04["lift"] = dict(lift_rec("C13_Revision_Breadth_3m", "군집 DUPC-045 의 유일한 별칭(C13) 해제 — 정본 역할이 빈다"), factor="C13_Revision_Breadth_3m")
    reg["C04_ESBR"].setdefault("retired_dedup", []).append(c04)
    del reg["C04_ESBR"]["dedup"]
    plan.append("C04_ESBR: dedup(canonical · DUPC-045) → retired_dedup")
    for line in plan:
        print("[lift]", line)
    out = dump(reg)
    if DRY:
        print(f"[lift] --dry-run · 쓰기 없음 · 새 크기 {len(out)} (옛 {len(raw[0])})"); return 0
    for p in REGS:  # 동시 변경 검사 — 읽은 뒤 다른 writer 가 바꿨으면 쓰지 않는다
        if hashlib.sha256(open(p, "rb").read()).hexdigest() != h0:
            print(f"[lift] {p} 가 읽은 뒤 바뀌었다 — 중단(다시 실행)"); return 4
    for p in REGS:
        tmp = p + ".lift_tmp"
        with open(tmp, "wb") as f:
            f.write(out)
        os.replace(tmp, p)
    ok = all(open(p, "rb").read() == out for p in REGS)
    print(f"[lift] 썼다 · 두 사본 같음 {ok} · sha256 {hashlib.sha256(out).hexdigest()[:12]}")
    return 0 if ok else 5


if __name__ == "__main__":
    sys.exit(main())
