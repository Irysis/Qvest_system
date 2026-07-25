# -*- coding: utf-8 -*-
"""
run_fixture_battery.py — ast_verify.py 픽스처 배터리 (SOT §8 Step 3 검증 기준 선행분)

5 픽스처: ① clean PASS ② 재무 당일참조 FAIL_LOOKAHEAD ③ 실사고2(동월 vintage) FAIL
          ④ restatement WARN ⑤ escape 계약 결측 FAIL_CONTRACT
실행: <venv python> run_fixture_battery.py   (bare python3 금지 — Windows Store 스텁)
"""
import io
import json
import os
import sys
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # 02_Infrastructure/ast
import ast_verify  # noqa: E402

CASES = [
    # (fixture, 기대 verdict, 기대 exit, 추가 assert 함수)
    ("fx1_clean_pass.json", "PASS", 0,
     lambda r: not r["violations"] and not r["restatement_leaves"] and not r["contract_failures"]),
    ("fx2_fund_sameday_fail.json", "FAIL_LOOKAHEAD", 1,
     lambda r: any("C-FUND-MERGED" in v["leaf"] and v["path"] for v in r["violations"])
               and len(r["discrepancy_used"]) >= 1),
    ("fx3_samemonth_vintage_fail.json", "FAIL_LOOKAHEAD", 1,
     lambda r: any("동월 vintage" in v["detail"] for v in r["violations"])),
    ("fx4_restatement_warn.json", "WARN_RESTATEMENT", 0,
     lambda r: not r["violations"] and len(r["restatement_leaves"]) >= 1
               and len(r["discrepancy_used"]) >= 1),
    ("fx5_escape_missing_contract.json", "FAIL_CONTRACT", 1,
     lambda r: any("training_window_end" in cf["missing"] for cf in r["contract_failures"])),
]


def run_one(fx):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        code = ast_verify.main([os.path.join(HERE, "fixtures", fx)])
    return code, json.loads(buf.getvalue())


def main():
    n_ok = 0
    rows = []
    for fx, want_verdict, want_exit, extra in CASES:
        code, res = run_one(fx)
        got = res["verdict"]
        ok = (got == want_verdict) and (code == want_exit) and bool(extra(res))
        n_ok += ok
        rows.append((fx, want_verdict, got, code, "OK" if ok else "MISMATCH"))
    w = max(len(r[0]) for r in rows)
    print("%-*s  %-18s %-18s %-4s %s" % (w, "fixture", "expected", "got", "exit", "result"))
    for r in rows:
        print("%-*s  %-18s %-18s %-4d %s" % (w, r[0], r[1], r[2], r[3], r[4]))
    print("battery: %d/%d" % (n_ok, len(CASES)))
    return 0 if n_ok == len(CASES) else 1


if __name__ == "__main__":
    sys.exit(main())
