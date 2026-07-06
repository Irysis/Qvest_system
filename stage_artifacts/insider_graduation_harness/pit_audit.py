#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""pit_audit.py — 임원 순매수 하네스 PIT(anti-look-ahead) 감사.

★ 오늘 세션 교훈 배선: BearProb faith 버그(동월 look-ahead)가 placebo/OOS 를 통과했음.
   → 신호→수익 월 경계를 프로그램적으로 assert. 위반 시 non-zero exit.

검사 항목:
  A1. usable_month > sig_month (STRICT). 동월/과거월 사용 없음.
  A2. Date(=canonical screen 입력) == first-day-of(usable_month). 홀딩월 시작.
  A3. usable_month - sig_month == PIT_LAG (일관, 최소 1).
  A4. late-filing 점검: rcept_dt 기준이 보수적임을 확인 (변동일 MDF < rcept_dt 존재 = 정상,
      rcept_dt 기준이 정답. rcept_dt 자체는 항상 sig_month 정의에 사용).
  A5. 'Date<anchor_date' 안티패턴이 소스에 없음 (grep). anchor_date 변수 미사용.

산출: reports/pit_audit_report.json  (+ stdout PASS/FAIL). FAIL 시 exit 1.
"""
import os, sys, json, re
import pandas as pd

R = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
HARN = os.path.join(R, "stage_artifacts", "insider_graduation_harness")
PANEL = os.path.join(HARN, "data", "officer_netbuy_panel.parquet")
BUILD_SRC = os.path.join(HARN, "build_officer_netbuy_signal.py")

fails, checks = [], []


def rec(name, ok, detail):
    checks.append({"check": name, "pass": bool(ok), "detail": detail})
    if not ok:
        fails.append(name)


def main():
    meta = json.load(open(os.path.join(HARN, "reports", "signal_build_meta.json"), encoding="utf-8"))
    pit_lag = int(meta["pit_lag_months"])
    df = pd.read_parquet(PANEL)

    sm = pd.PeriodIndex(df["sig_month"], freq="M")
    um = pd.PeriodIndex(df["usable_month"], freq="M")
    dt = pd.to_datetime(df["Date"])
    # month difference as plain integers (ordinal diff)
    lags = (um.astype("int64") - sm.astype("int64"))

    # A1: usable strictly after signal
    a1 = bool((um > sm).all())
    rec("A1_usable_after_signal_strict", a1,
        f"min(usable-sig months)={int(lags.min())} (must be >=1)")

    # A2: Date == first day of usable month
    exp = um.to_timestamp(how="start")
    a2 = bool((dt.values == exp.values).all())
    rec("A2_date_is_usable_month_begin", a2,
        f"mismatches={int((dt.values != exp.values).sum())}")

    # A3: constant lag == PIT_LAG
    a3 = bool((lags == pit_lag).all())
    rec("A3_lag_equals_pit_lag", a3,
        f"pit_lag={pit_lag}; distinct lags={sorted(set(lags.tolist()))}")

    # A4: rcept-based sig_month is the conservative choice (documented). We assert Date >= last day of sig_month.
    sm_end = sm.to_timestamp(how="end")
    a4 = bool((dt.values >= sm_end.values).all())
    rec("A4_holding_begins_after_signal_month_end", a4,
        f"holding-begin Date always >= sig_month end: {a4} (rcept_dt month fully elapsed before holding)")

    # A5: anti-pattern grep in build source — flag ACTUAL code usage, not doc mentions.
    #     Strip comment lines (# ...) and docstring, then search for a live 'Date < anchor'
    #     style comparison or an assignment to an anchor_date variable used in filtering.
    src = open(BUILD_SRC, encoding="utf-8").read()
    # Reduce to executable code only using the tokenizer: drop COMMENT and STRING tokens
    # (docstrings, meta-dict doc strings, and comments all mention the forbidden pattern
    #  intentionally — only a live operator usage in code should trip this check).
    import io, tokenize
    kept = []
    try:
        toks = tokenize.generate_tokens(io.StringIO(src).readline)
        for tok in toks:
            if tok.type in (tokenize.COMMENT, tokenize.STRING):
                continue
            kept.append(tok.string)
        code_only = " ".join(kept)
    except tokenize.TokenError:
        # fallback: strip comments + triple/single quoted blocks heuristically
        code_only = re.sub(r'(""".*?"""|\'.*?\'|".*?")', " ", src, flags=re.S)
        code_only = "\n".join(l.split("#", 1)[0] for l in code_only.splitlines())
    # live antipatterns: assigning anchor_date, or comparing a Date column '< anchor'
    ap1 = re.search(r"anchor_date\s*=", code_only)
    ap2 = re.search(r"Date\W*<\W*anchor", code_only)
    a5 = (ap1 is None) and (ap2 is None)
    rec("A5_no_anchor_date_antipattern", a5,
        "no live 'anchor_date=' assignment nor 'Date<anchor' comparison in executable code "
        "(doc mentions of the forbidden pattern are allowed)" if a5
        else f"FOUND live antipattern: anchor_assign={ap1 is not None} date_lt_anchor={ap2 is not None}")

    verdict = "PASS" if not fails else "FAIL"
    report = {
        "verdict": verdict,
        "pit_lag_months": pit_lag,
        "n_rows_audited": int(len(df)),
        "checks": checks,
        "fails": fails,
        "note": "rcept_dt(sig month M) < first-day(usable M+lag). no same-month use. lag1 stress via PIT_LAG env.",
    }
    json.dump(report, open(os.path.join(HARN, "reports", "pit_audit_report.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"[PIT audit] {verdict}  ({len(checks)-len(fails)}/{len(checks)} checks pass)")
    for c in checks:
        print(f"  [{'OK' if c['pass'] else 'XX'}] {c['check']}: {c['detail']}")
    if fails:
        sys.exit(1)


if __name__ == "__main__":
    main()
