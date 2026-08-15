"""WT-D20260813_005 · S5 — ast_spec_gate 검사 ① 로직 재현 + **위반 주입으로 판별력 확인**

왜: "게이트를 통과했다"는 그 게이트가 위반을 잡을 때만 근거가 된다.
    (WT-004 에서 PIT 검사기가 판별력 0 이었던 전례 — clean 도 PASS, 위반 주입도 PASS.)
    여기서는 clean 패키지 PASS 와 **위반 주입 5종 전부 BLOCK** 을 같이 확인한다.
    검사 로직은 02_Infrastructure/hooks/ast_spec_gate.sh 의 ① 블록을 그대로 옮긴 것.

실행: cd <ROOT> && "$QVEST_PY" stage_artifacts/WT-D20260813_005/s5_gate_selfcheck.py
"""
import json, os, copy, sys

ROOT = os.environ.get("QM_ROOT") or os.getcwd()
PKG = os.path.join(ROOT, "qepm/mailbox/worktask/WT-D20260813_005/alpha_package.json")


def load_field_dictionary():
    names = set()
    with open(os.path.join(ROOT, "02_Infrastructure/factor_db/factor_registry.json"), encoding="utf-8") as f:
        names |= set(json.load(f).keys())
    with open(os.path.join(ROOT, "06_Registry/ast_field_map_v0.json"), encoding="utf-8") as f:
        fmap = json.load(f)
    for dom in fmap.get("domains", {}).values():
        for g in dom.get("leaf_groups", []):
            names.add(g.get("group_id"))
    names.discard(None)
    return names


FIELD_DICT = load_field_dictionary()


def fals_fields(entry):
    if isinstance(entry, str):
        return [entry]
    if isinstance(entry, dict):
        out = []
        for k in ("field", "fields", "field_ref", "leaf", "group_id", "factor"):
            v = entry.get(k)
            if isinstance(v, str):
                out.append(v)
            elif isinstance(v, list):
                out += [x for x in v if isinstance(x, str)]
        return out
    return []


def gate(pkg):
    """게이트 ① 재현. 반환 = block 사유 리스트(빈 리스트 = PASS)."""
    issues = []
    hyp = pkg.get("hypothesis") or {}
    mech = hyp.get("mechanism") or {}
    missing = [k for k in ("agent", "friction", "path")
               if not (isinstance(mech.get(k), str) and mech.get(k).strip())]
    if missing:
        issues.append("mechanism 필드 누락/공백: {%s}" % ", ".join(missing))
    fals = hyp.get("falsification")
    if not isinstance(fals, list) or not fals:
        issues.append("falsification 사전 부재/빈 배열")
    else:
        bad = []
        for i, e in enumerate(fals):
            refs = fals_fields(e)
            if not refs:
                bad.append("[%d] 필드 참조 없음" % i)
            else:
                unk = [r for r in refs if r not in FIELD_DICT]
                if unk:
                    bad.append("[%d] field_dictionary 밖: %s" % (i, ", ".join(unk[:5])))
        if bad:
            issues.append("falsification 검증 실패 — " + " | ".join(bad[:6]))
    rs = hyp.get("regime_scope")
    wor = rs.get("weakens_or_reverses_in") if isinstance(rs, dict) else None
    if not isinstance(wor, list) or not wor:
        issues.append("regime_scope.weakens_or_reverses_in 부재/빈 배열")
    pit = pkg.get("pit")
    if not (isinstance(pit, dict) and pit.get("sig_date")):
        issues.append("pit.sig_date 부재 (schema v1.1 required)")
    return issues


with open(PKG, encoding="utf-8") as f:
    clean = json.load(f)

print("=== clean 패키지 ===")
iss = gate(clean)
print("  PASS" if not iss else "  ★BLOCK: " + " | ".join(iss))
clean_pass = not iss

# ── 위반 주입 5종 — 전부 BLOCK 되어야 검사에 판별력이 있다 ──────────────────
def inj_mech(p):
    p["hypothesis"]["mechanism"]["friction"] = "   "        # 공백 = 마찰 무명명
    return p

def inj_fals_outside(p):
    p["hypothesis"]["falsification"][0]["fields"] = ["NOT_A_REAL_FIELD_xyz"]
    return p

def inj_fals_norefs(p):
    p["hypothesis"]["falsification"] = [{"expectation": "성과가 나쁘면 기각"}]  # 필드 지목 없음
    return p

def inj_regime(p):
    p["hypothesis"]["regime_scope"]["weakens_or_reverses_in"] = []   # 보편타당 주장
    return p

def inj_pit(p):
    p.pop("pit", None)
    return p

INJ = [("mechanism friction 공백", inj_mech),
       ("falsification 사전 밖 필드", inj_fals_outside),
       ("falsification 필드 지목 없음", inj_fals_norefs),
       ("regime_scope 빈 배열(보편타당)", inj_regime),
       ("pit.sig_date 제거", inj_pit)]

print("\n=== 위반 주입 %d종 (전부 BLOCK 되어야 판별력 있음) ===" % len(INJ))
caught = 0
for name, fn in INJ:
    iss = gate(fn(copy.deepcopy(clean)))
    ok = bool(iss)
    caught += ok
    print("  %-32s %s  %s" % (name, "BLOCK(검출)" if ok else "★PASS(검출 실패)",
                              (" — " + iss[0][:70]) if iss else ""))

print("\n=== 판정 ===")
print("  clean PASS: %s · 위반 주입 검출 %d/%d" % (clean_pass, caught, len(INJ)))
verdict = clean_pass and caught == len(INJ)
print("  ⇒ %s" % ("검사 판별력 확인 — 'PASS' 를 근거로 쓸 수 있음"
                  if verdict else "★검사 판별력 미확인 — 'PASS' 를 근거로 쓰지 말 것"))
sys.exit(0 if verdict else 1)
