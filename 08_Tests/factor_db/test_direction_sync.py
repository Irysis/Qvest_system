"""test_direction_sync.py — 등록부 방향 야간 동기화(apply_direction_basis.py --sync · daily_refresh [6f]) 계약 검사.

2026-11-09 · decision_register FACTOR-DIRECTION-TWO-VIEWS-20261109 · 도훈 'C안으로 수정된 정책도 추후 팩터 DB 업데이트에 자동으로 반영되게끔'.
합성 등록부 · 감사 표 · 빌더 코드(임시 폴더)만 쓴다 — 운영 파일을 읽거나 쓰지 않는다.
  S1 새 엔트리(필드 없음 · 위험 계열) → 감사 표 자동 등재 · 필드 채움 · 소비자 direction 그대로 · 방어 판정 대기
  S1b 새 엔트리(코드 없음 · custom) → stored_sign +1 가정
  S1c 새 엔트리(코드는 음수화 · 정의는 음수화를 말하지 않음) → stored_sign −1 · direction 은 그대로(direction_economic 이 반대)
  S2 등록부 direction 손 편집(감사 표와 다름) → 고치지 않고 충돌 · rc 3 · 다른 엔트리는 동기화
  S3 두 사본이 엔트리 하나만 다름 → 합집합으로 둘 다 맞춤
  S4 두 사본의 같은 이름 엔트리 값이 다름 → 쓰지 않음 · rc 3
  S5 읽은 뒤 파일이 바뀜 → 쓰지 않음 · rc 4 · 임시 파일 안 남김
  S6 두 번째 실행 = 쓰기 없음(멱등)
  S7 빌더 부호 드리프트 → 경보 · rc 3
  S8 다른 서식(indent 4) → 같은 뜻으로 정규화
  M1~M3 돌연변이(소스 텍스트 치환 · 치환 성사 단정): 충돌 검사 제거 → S2 · 동시성 검사 제거 → S5 · direction 보존 제거 → S1c
표준 라이브러리만 쓴다.
"""
import copy
import json
import os
import shutil
import sys
import tempfile
import types

ROOT = os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot")
FDIR = os.path.join(ROOT, "02_Infrastructure", "factor_db")
SRC = os.path.join(FDIR, "apply_direction_basis.py")
sys.path.insert(0, FDIR)
PASS = FAIL = 0


def chk(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1; print(f"  [ok]   {name}")
    else:
        FAIL += 1; print(f"  [FAIL] {name} {detail}")


def load_mod(text=None):
    src = text if text is not None else open(SRC, encoding="utf-8").read()
    m = types.ModuleType("adb_under_test")
    m.__file__ = SRC
    exec(compile(src, SRC, "exec"), m.__dict__)
    return m


def mutant(old, new):
    src = open(SRC, encoding="utf-8").read()
    n = src.count(old)
    if n != 1:
        return None, f"치환 대상 {n}곳: {old[:60]}"
    return load_mod(src.replace(old, new, 1)), None


def dump(obj):
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


BASE_REG = {
    "D_OLD": {"name": "old", "category": "defense", "definition": "Negate volatility.", "direction": "higher_better",
              "direction_economic": "higher_better", "direction_economic_basis": "registry_original", "stored_sign": 1,
              "direction_basis": "stored_raw_value", "direction_defensive": "higher_better",
              "direction_defensive_definition": "higher_better", "direction_defensive_reason": "위험 낮을수록", "lifecycle": {"added_date": "2026-01-01"}},
    "V_OLD": {"name": "value", "category": "value", "definition": "Book to market.", "direction": "higher_better",
              "direction_economic": "higher_better", "direction_economic_basis": "registry_original", "stored_sign": 1,
              "direction_basis": "stored_raw_value", "lifecycle": {"added_date": "2026-01-01"}},
}
BASE_AUD = {"schema": "factor_direction_audit_v2", "factors": {
    "D_OLD": {"stored_sign": 1, "direction_economic": "higher_better", "direction_stored": "higher_better", "economic_basis": "registry_original",
              "defensive_definition": "higher_better", "defensive_reason": "위험 낮을수록", "code_negated_at_audit": True},
    "V_OLD": {"stored_sign": 1, "direction_economic": "higher_better", "direction_stored": "higher_better", "economic_basis": "registry_original",
              "code_negated_at_audit": False}}, "history": []}
CODE = ('bm <- book / mcap\n'                                              # 변수 대입 — 판독기가 따라가 '음수화 아님'으로 판정
        'out <- list(data.table(Factor_Name = "D_OLD", Raw_Value = -vol), data.table(Factor_Name = "V_OLD", Raw_Value = bm),\n'
        '  data.table(Factor_Name = "L_NEW", Raw_Value = -turn), data.table(Factor_Name = "Q_NEW", Raw_Value = -roe))\n')


def env(reg=None, reg2=None, aud=None, code=CODE):
    td = tempfile.mkdtemp(prefix="dsync_")
    os.makedirs(os.path.join(td, "code"))
    open(os.path.join(td, "code", "compute_test.R"), "w", encoding="utf-8").write(code)
    r1, r2 = os.path.join(td, "reg1.json"), os.path.join(td, "reg2.json")
    open(r1, "wb").write(dump(reg if reg is not None else BASE_REG))
    open(r2, "wb").write(dump(reg2 if reg2 is not None else (reg if reg is not None else BASE_REG)))
    ap = os.path.join(td, "audit.json")
    open(ap, "wb").write(dump(aud if aud is not None else BASE_AUD))
    return td, [r1, r2], ap, os.path.join(td, "code"), os.path.join(td, "pending.json")


def run(m, reg=None, reg2=None, aud=None, code=CODE, **kw):
    td, regs, ap, cd, pend = env(reg, reg2, aud, code)
    rc, rep = m.sync(regs, ap, cd, pend, today="2026-11-09", **kw)
    out = [json.loads(open(p, encoding="utf-8").read()) for p in regs]
    raws = [open(p, "rb").read() for p in regs]
    audit = json.loads(open(ap, encoding="utf-8").read())
    left = [f for f in os.listdir(td) if f.startswith(".reg_")]
    return dict(td=td, regs=regs, ap=ap, cd=cd, pend=pend, rc=rc, rep=rep, out=out, raws=raws, audit=audit, left=left)


def with_new(**entries):
    r = copy.deepcopy(BASE_REG)
    r.update(entries)
    return r


L_NEW = {"name": "new liq", "category": "liquidity", "definition": "Negate turnover.", "direction": "higher_better", "lifecycle": {"added_date": "2026-11-09"}}
C_NEW = {"name": "rp", "category": "custom", "definition": "논문 신호(동결 패널).", "direction": "higher_better", "lifecycle": {"added_date": "2026-11-09"}}
Q_NEW = {"name": "q", "category": "quality", "definition": "Return on equity.", "direction": "lower_better", "lifecycle": {"added_date": "2026-11-09"}}


def s1(m):
    R = run(m, reg=with_new(L_NEW=L_NEW, C_NEW=C_NEW, Q_NEW=Q_NEW))
    e, c, q = R["out"][0]["L_NEW"], R["out"][0]["C_NEW"], R["out"][0]["Q_NEW"]
    a = R["audit"]["factors"]
    return R, dict(
        s1=R["rc"] == 0 and e["direction"] == "higher_better" and e["direction_basis"] == "stored_raw_value" and e["stored_sign"] == 1 and
        e["direction_economic"] == "higher_better" and a["L_NEW"]["auto_added"] == "2026-11-09" and "L_NEW" in R["rep"]["pending_defensive"] and
        "direction_defensive" not in e and R["out"][0] == R["out"][1],
        s1b=c["stored_sign"] == 1 and a["C_NEW"]["stored_sign_basis"] == "assumed_definition_is_stored" and c["direction"] == "higher_better",
        s1c=q["stored_sign"] == -1 and q["direction"] == "lower_better" and q["direction_economic"] == "higher_better")


def s2(m):
    r = copy.deepcopy(BASE_REG)
    r["V_OLD"]["direction"] = "lower_better"                           # 손 편집(감사 표 = higher)
    r["L_NEW"] = L_NEW
    R = run(m, reg=r)
    return R, (R["rc"] == 3 and R["out"][0]["V_OLD"]["direction"] == "lower_better" and
               any(c.get("name") == "V_OLD" for c in R["rep"]["conflicts"]) and R["out"][0]["L_NEW"].get("direction_basis") == "stored_raw_value")


def s5(m):
    td, regs, ap, cd, pend = env(reg=with_new(L_NEW=L_NEW))
    inj = dump({"INJECTED": {"direction": "higher_better"}})
    rc, rep = m.sync(regs, ap, cd, pend, today="2026-11-09", _before_replace=lambda: open(regs[0], "wb").write(inj))
    left = [f for f in os.listdir(td) if f.startswith(".reg_")]
    ok = rc == 4 and open(regs[0], "rb").read() == inj and not left
    shutil.rmtree(td, ignore_errors=True)
    return ok


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    m = load_mod()
    R, s = s1(m)
    chk("S1 새 위험 계열 엔트리 → 감사 표 자동 등재 · 필드 채움 · direction 그대로 · 방어 판정 대기 · 두 사본 같음", s["s1"], json.dumps(R["rep"], ensure_ascii=False)[:300])
    chk("S1b 코드 없는 custom 엔트리 → stored_sign +1 가정(정의 = 저장값)", s["s1b"])
    chk("S1c 코드 음수화 · 정의는 음수화 말 안 함 → stored_sign −1 · 소비자 direction 그대로", s["s1c"])
    R2, ok2 = s2(m)
    chk("S2 등록부 direction 손 편집 → 고치지 않고 충돌 · rc 3 · 다른 엔트리는 동기화", ok2, f"rc={R2['rc']}")
    R3 = run(m, reg=BASE_REG, reg2=with_new(C_NEW=C_NEW))
    chk("S3 두 사본이 엔트리 하나만 다름 → 합집합으로 둘 다 맞춤", R3["rc"] == 0 and all("C_NEW" in o for o in R3["out"]) and R3["raws"][0] == R3["raws"][1] and R3["rep"]["copies"] == "union")
    r4 = copy.deepcopy(BASE_REG); r4["V_OLD"]["definition"] = "다른 값"
    R4 = run(m, reg=BASE_REG, reg2=r4)
    chk("S4 두 사본의 같은 이름 엔트리 값이 다름 → 쓰지 않음 · rc 3", R4["rc"] == 3 and R4["rep"]["copies"] == "conflict" and R4["raws"][0] == dump(BASE_REG) and not R4["rep"]["wrote"])
    chk("S5 읽은 뒤 파일이 바뀜 → 쓰지 않음 · rc 4 · 임시 파일 안 남김", s5(m))
    R6 = run(m, reg=R["out"][0], aud=R["audit"])
    chk("S6 두 번째 실행 = 쓰기 없음(멱등)", R6["rc"] == 0 and not R6["rep"]["wrote"] and not R6["rep"]["added"])
    a7 = copy.deepcopy(BASE_AUD); a7["factors"]["V_OLD"]["code_negated_at_audit"] = True   # 지금 코드 = 음수화 아님
    R7 = run(m, aud=a7)
    chk("S7 빌더 부호 드리프트 → 경보 · rc 3", R7["rc"] == 3 and any(d.get("name") == "V_OLD" for d in R7["rep"]["drift"]))
    td, regs, ap, cd, pend = env()
    open(regs[0], "wb").write((json.dumps(BASE_REG, ensure_ascii=False, indent=4) + "\n").encode("utf-8"))
    open(regs[1], "wb").write((json.dumps(BASE_REG, ensure_ascii=False, indent=4) + "\n").encode("utf-8"))
    rc8, rep8 = m.sync(regs, ap, cd, pend, today="2026-11-09")
    chk("S8 다른 서식 → 같은 뜻으로 정규화해 쓴다", rc8 == 0 and rep8["normalized"] and rep8["wrote"] and open(regs[0], "rb").read() == dump(BASE_REG))
    shutil.rmtree(td, ignore_errors=True)
    for x in (R, R2, R3, R4, R6, R7):
        shutil.rmtree(x["td"], ignore_errors=True)
    # ── 돌연변이 ──
    M1, e1 = mutant('            if e.get("direction") != a.get("direction_stored"):\n', "            if False:\n")
    M2, e2 = mutant('    if any(open(p, "rb").read() != r for p, r in zip(present, raws)):\n', "    if False:\n")
    M3, e3 = mutant("        de = stored_direction(d, s)\n", "        de = d\n")
    chk("M0 돌연변이 3개 모두 치환 성사", M1 is not None and M2 is not None and M3 is not None, f"{e1} {e2} {e3}")
    if M1 is not None:
        Rm, okm = s2(M1)
        chk("M1 충돌 검사 제거 → S2 가 걸린다(손 편집이 덮인다)", not okm)
        shutil.rmtree(Rm["td"], ignore_errors=True)
    if M2 is not None:
        chk("M2 동시성 검사 제거 → S5 가 걸린다", not s5(M2))
    if M3 is not None:
        Rm3, sm3 = s1(M3)
        chk("M3 direction 보존 제거 → S1c 가 걸린다(소비자 방향이 바뀐다)", not sm3["s1c"])
        shutil.rmtree(Rm3["td"], ignore_errors=True)
    print(f"\n[test_direction_sync] {PASS} passed, {FAIL} failed")
    print(json.dumps({"test": "direction_sync", "pass": PASS, "fail": FAIL, "total": PASS + FAIL}))  # 배터리 요약 줄(run_all_hooks.sh)
    sys.exit(1 if FAIL else 0)


if __name__ == "__main__":
    main()
