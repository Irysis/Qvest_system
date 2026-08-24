# -*- coding: utf-8 -*-
"""test_factor_evidence_backfill.py — 팩터 근거 환류 양방향 검사 (2026-08-21 신설).

★양방향으로 잰다: 잡아야 할 것을 잡는지(양성 대조) + 잡지 말아야 할 것을 안 잡는지(위반 주입).
  "생성 성공" 만으로는 아무것도 증명되지 않는다 — 등급이 전부 S1 이어도 성공처럼 보인다.
"""
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILDER = os.path.join(ROOT, "02_Infrastructure", "factor_db", "build_factor_evidence.py")
PY = os.environ.get("QVEST_PY") or sys.executable

P = F = 0


def ok(m):
    global P
    P += 1
    print("  PASS  %s" % m)


def ng(m, d):
    global F
    F += 1
    print("  FAIL  %s :: %s" % (m, d))


def make_fixture(tmp, reg, ic_rows):
    os.makedirs(os.path.join(tmp, "02_Infrastructure", "factor_db"), exist_ok=True)
    os.makedirs(os.path.join(tmp, "02_Infrastructure", "hooks"), exist_ok=True)
    os.makedirs(os.path.join(tmp, ".cache"), exist_ok=True)
    os.makedirs(os.path.join(tmp, "06_Registry"), exist_ok=True)
    io.open(os.path.join(tmp, "02_Infrastructure", "hooks", "qvest_hook_router.py"),
            "w").write("")
    with io.open(os.path.join(tmp, "02_Infrastructure", "factor_db",
                              "factor_registry.json"), "w", encoding="utf-8") as fh:
        json.dump(reg, fh, ensure_ascii=False, indent=2)
    cols = ["Factor_Name", "ic_all", "ic_bad", "ic_good", "conditional_value",
            "recent_3y_icir", "n_months", "used", "category"]
    with io.open(os.path.join(tmp, ".cache", "conditional_ic_matrix.csv"),
                 "w", encoding="utf-8", newline="") as fh:
        fh.write(",".join(cols) + "\n")
        for r in ic_rows:
            fh.write(",".join(str(r.get(c, "")) for c in cols) + "\n")
    shutil.copy(BUILDER, os.path.join(tmp, "02_Infrastructure", "factor_db",
                                      "build_factor_evidence.py"))


def run(tmp):
    env = dict(os.environ, QM_ROOT=tmp)
    rc = subprocess.run([PY, os.path.join(tmp, "02_Infrastructure", "factor_db",
                                          "build_factor_evidence.py")],
                        env=env, capture_output=True, text=True)
    out = os.path.join(tmp, "06_Registry", "factor_evidence.json")
    if not os.path.exists(out):
        return None, rc
    return json.load(io.open(out, encoding="utf-8")), rc


def mk_reg(*ids):
    return {i: {"category": "momentum", "direction": "positive",
                "lifecycle": {"status": "active"}} for i in ids}


tmp = tempfile.mkdtemp()
try:
    print("== 양성 대조: 강한 IC + 부호일치 + 장기간 → S1 ==")
    make_fixture(tmp, mk_reg("F_STRONG"),
                 [{"Factor_Name": "F_STRONG", "ic_all": 0.06, "recent_3y_icir": 0.5,
                   "n_months": 300, "ic_bad": 0.08, "ic_good": 0.04,
                   "conditional_value": 0.04}])
    o, rc = run(tmp)
    if o and o["factors"]["F_STRONG"]["ic_screen_tier"] == "S1":
        ok("|ic|0.06 · 부호일치 · 300개월 → S1")
    else:
        ng("S1 판정", (o or {}).get("factors", {}).get("F_STRONG") or rc.stderr[:160])

    print("== 위반 주입 1: 부호 불일치면 S1 을 주지 않는가 ==")
    make_fixture(tmp, mk_reg("F_FLIP"),
                 [{"Factor_Name": "F_FLIP", "ic_all": 0.06, "recent_3y_icir": -0.5,
                   "n_months": 300}])
    o, rc = run(tmp)
    t = (o or {}).get("factors", {}).get("F_FLIP", {}).get("ic_screen_tier")
    ok("부호 불일치 → %s (S1 아님)" % t) if t == "S2" else ng("부호 불일치 강등", t)

    print("== 위반 주입 2: 기간 미달이면 S1 을 주지 않는가 ==")
    make_fixture(tmp, mk_reg("F_SHORT"),
                 [{"Factor_Name": "F_SHORT", "ic_all": 0.09, "recent_3y_icir": 0.4,
                   "n_months": 60}])
    o, rc = run(tmp)
    t = (o or {}).get("factors", {}).get("F_SHORT", {}).get("ic_screen_tier")
    ok("60개월 → %s (S1 아님)" % t) if t == "S2" else ng("기간 미달 강등", t)

    print("== 위반 주입 3: 미측정 팩터를 목록에서 지우지 않는가 ==")
    make_fixture(tmp, mk_reg("F_HAS", "F_NONE"),
                 [{"Factor_Name": "F_HAS", "ic_all": 0.05, "recent_3y_icir": 0.3,
                   "n_months": 300}])
    o, rc = run(tmp)
    fs = (o or {}).get("factors", {})
    if "F_NONE" in fs and fs["F_NONE"]["ic_screen_tier"] == "unmeasured":
        ok("IC 부재 팩터가 unmeasured 로 **수록**됨 (누락 아님)")
    else:
        ng("미측정 수록", "F_NONE=%s — 지워지면 소비자가 '전부 측정됨'으로 오독" % fs.get("F_NONE"))

    print("== 위반 주입 4: 원장에 없는 IC 를 조용히 버리지 않는가 ==")
    make_fixture(tmp, mk_reg("F_HAS"),
                 [{"Factor_Name": "F_HAS", "ic_all": 0.05, "recent_3y_icir": 0.3,
                   "n_months": 300},
                  {"Factor_Name": "F_GHOST", "ic_all": 0.07, "recent_3y_icir": 0.3,
                   "n_months": 300}])
    o, rc = run(tmp)
    if o and "F_GHOST" in o.get("orphans_ic_without_registry", []):
        ok("원장 부재 IC 가 orphans 로 표면화 (원장/IC 낙후 지문)")
    else:
        ng("orphan 표면화", (o or {}).get("orphans_ic_without_registry"))

    print("== 계약 검사: 자본 주장 원천 차단 ==")
    make_fixture(tmp, mk_reg("F_A", "F_B"),
                 [{"Factor_Name": "F_A", "ic_all": 0.09, "recent_3y_icir": 0.5,
                   "n_months": 300}])
    o, rc = run(tmp)
    fs = (o or {}).get("factors", {})
    bad = [k for k, v in fs.items()
           if v.get("capital_claim") is not False
           or v.get("metric_type") != "screen_diagnostic"]
    ok("전 레코드 capital_claim=false · metric_type=screen_diagnostic") if not bad \
        else ng("자본주장 차단", bad)

    print("== 비파괴 검사: factor_registry 를 건드리지 않는가 ==")
    regp = os.path.join(tmp, "02_Infrastructure", "factor_db", "factor_registry.json")
    before = hashlib.sha256(io.open(regp, "rb").read()).hexdigest()
    run(tmp)
    after = hashlib.sha256(io.open(regp, "rb").read()).hexdigest()
    ok("원장 바이트 불변 (13,100줄 reformat 위험 회피)") if before == after \
        else ng("원장 비파괴", "sha 변경 %s -> %s" % (before[:12], after[:12]))

    print("== 계약 검사: evidence_tier(A/B/C) 축을 침범하지 않는가 ==")
    o, rc = run(tmp)
    invaded = [k for k, v in (o or {}).get("factors", {}).items() if "evidence_tier" in v]
    ok("evidence_tier 필드 미발급 (학술·재현 축 보존)") if not invaded \
        else ng("축 침범", invaded)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print("== t_summary: PASS=%d FAIL=%d ==" % (P, F))
print('{"test":"factor_evidence_backfill","pass":%d,"fail":%d,"total":%d,"skipped":0}' % (P, F, (P)+(F)))
sys.exit(1 if F else 0)
