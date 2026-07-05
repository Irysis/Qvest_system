#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Cohen-Malloy-Pomorski (2012) "Decoding Inside Information" — KR 충실 복제 신호 빌더
==============================================================================
alpha-search 제1원칙(충실 복제) 하에서 CMP(2012)의 routine vs opportunistic 임원 분리를
KR(K200∪KQ150) 임원 순매수에 이식한다. **신호 패널만 산출** — 백테스트 자체합성 없음
(canonical_screen_bt / build_bt_result R 브릿지가 측정. python-policy §4 준수).

입력: stage_artifacts/dart_parser_build/cache/monthly/YYYYMM.parquet (document.xml 파서 산출,
      net_change_qty 100% elestock parity 검증됨). reporter_name·reporter_type·officer_registered
      per-report 레코드.

CMP 분류 (원전 충실):
  - insider 신원 = (stock_code, normalized reporter_name). 공백/포맷 정규화(파서 parity note:
    '장 세 환' vs '장세환' 동일인).
  - 임원(officer) 필터: reporter_type=='officer' (10%주주·지배주주 = 연기금 등 기계적 매매 격리,
    consolidate 및 memory project-dart-insider 근거 — 임원 정보매수가 ICIR 1.31 lead).
  - ROUTINE: 어떤 임원-종목이 **직전 3개 연속 연도 모두 동일 달(calendar month)에 거래**했으면
    그 거래는 routine (예측가능 = 유동성/분산 목적, 무정보). 원전 정의.
  - OPPORTUNISTIC: 3년 이력이 있으나 routine 패턴 아님 = 정보성 후보 (CMP 알파 원천).
  - 이력 3년 미만 = unclassified (test 제외 — 원전도 3yr 이력 요구).

신호 (firm-month, sig_month = rcept_dt 월):
  opp_netbuy   = Σ opportunistic-officer net_change_qty (원전 알파 신호)
  all_netbuy   = Σ officer net_change_qty (분류 무관 — 기존 count-fail 대비 amount 버전)
  rout_netbuy  = Σ routine-officer net_change_qty (플라시보 대조군 — 무신호여야)
  n_opp_buyers = opportunistic 순매수 임원 수(방향 카운트 대안)

PIT: usable_month = sig_month + 1 (t-1 lag). 리밸 결정은 usable_month 시점 정보만 사용.

Usage:
  python cmp_signal.py            # 전체 월 → panel parquet
  python cmp_signal.py --selftest # routine/opportunistic 분류 로직 synthetic 단위검증

작성: 2026-07-05 (alpha-search 새 아키텍처 — exec-insider frontier, 도훈 confirm Option A).
"""
import os, sys, json, re
import pandas as pd
import numpy as np

ROOT = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
BUILD = os.path.join(ROOT, "stage_artifacts", "dart_parser_build")
CKDIR = os.path.join(BUILD, "cache", "monthly")
OUTP = os.path.join(BUILD, "data", "cmp_opportunistic_signal.parquet")
METAP = os.path.join(BUILD, "reports", "cmp_signal_meta.json")

ROUTINE_YEARS = 3  # CMP: 직전 3개 연속 연도 동일 달 거래 = routine


def norm_name(s):
    """reporter_name 정규화 — 공백 제거(파서가 원문 공백형 보존: '장 세 환'→'장세환')."""
    if s is None or (isinstance(s, float) and np.isnan(s)):
        return None
    return re.sub(r"\s+", "", str(s)).strip()


def load_reports():
    """월별 parquet → officer per-report 레코드 (ok==True, net_change_qty notna)."""
    files = sorted(f for f in os.listdir(CKDIR) if f.endswith(".parquet"))
    frames = []
    for f in files:
        df = pd.read_parquet(os.path.join(CKDIR, f))
        if "ok" not in df.columns:
            continue
        df = df[df["ok"] == True].copy()
        if len(df):
            frames.append(df)
    if not frames:
        return pd.DataFrame()
    d = pd.concat(frames, ignore_index=True)
    d["net"] = pd.to_numeric(d["net_change_qty"], errors="coerce")
    d = d[d["net"].notna()].copy()
    d["stock_code"] = d["stock_code"].astype(str).str.zfill(6)
    d["ins_name"] = d["reporter_name"].map(norm_name)
    d["ym"] = pd.to_datetime(d["rcept_dt"].astype(str).str[:6], format="%Y%m")
    d["year"] = d["ym"].dt.year
    d["cmonth"] = d["ym"].dt.month
    return d


def classify_routine(d):
    """
    각 officer 레코드에 is_routine / classified 부여.
    routine := 이 (insider,stock,calendar_month) 조합이 직전 ROUTINE_YEARS 연속 연도 각각
              해당 달에 최소 1건 거래 존재.
    classified := 이 insider-stock 이력이 현재거래 이전 ROUTINE_YEARS 년 이상 존재.
    """
    off = d[d["reporter_type"] == "officer"].copy()
    if off.empty:
        off["is_routine"] = pd.Series(dtype=bool)
        off["classified"] = pd.Series(dtype=bool)
        return off
    # (insider, stock, month) 별 거래연도 집합
    key = ["ins_name", "stock_code", "cmonth"]
    year_sets = off.groupby(key)["year"].apply(lambda s: set(s.tolist())).to_dict()
    # insider-stock 최초 거래연도(이력 길이 판정용)
    first_year = off.groupby(["ins_name", "stock_code"])["year"].min().to_dict()

    def row_flags(r):
        ins, sc, cm, yr = r["ins_name"], r["stock_code"], r["cmonth"], r["year"]
        if ins is None:
            return pd.Series({"is_routine": False, "classified": False})
        classified = (yr - first_year.get((ins, sc), yr)) >= ROUTINE_YEARS
        ys = year_sets.get((ins, sc, cm), set())
        # 직전 ROUTINE_YEARS 연속 연도 모두 해당 달 거래?
        routine = classified and all((yr - k) in ys for k in range(1, ROUTINE_YEARS + 1))
        return pd.Series({"is_routine": bool(routine), "classified": bool(classified)})

    flags = off.apply(row_flags, axis=1)
    off["is_routine"] = flags["is_routine"]
    off["classified"] = flags["classified"]
    return off


def build_panel(off):
    """officer 레코드(분류됨) → firm-month 신호 패널."""
    off = off.copy()
    off["sig_month"] = off["ym"].dt.strftime("%Y-%m")
    opp = off["classified"] & (~off["is_routine"])
    rout = off["classified"] & off["is_routine"]

    def agg(g):
        gi = g.index
        o = opp.loc[gi]; rt = rout.loc[gi]
        return pd.Series({
            "opp_netbuy": g.loc[o, "net"].sum(),
            "rout_netbuy": g.loc[rt, "net"].sum(),
            "all_netbuy": g["net"].sum(),
            "n_opp_buyers": int(((g["net"] > 0) & o).sum()),
            "n_opp_sellers": int(((g["net"] < 0) & o).sum()),
            "n_officer_reports": int(len(g)),
            "n_classified": int(g.loc[gi, "classified"].sum()) if "classified" in g else int(off.loc[gi, "classified"].sum()),
        })

    panel = off.groupby(["stock_code", "sig_month"]).apply(agg, include_groups=False).reset_index()
    panel["Ticker"] = "A" + panel["stock_code"]
    um = pd.to_datetime(panel["sig_month"], format="%Y-%m") + pd.offsets.MonthBegin(1)
    panel["usable_month"] = um.dt.strftime("%Y-%m")
    return panel[["Ticker", "stock_code", "sig_month", "usable_month",
                  "opp_netbuy", "rout_netbuy", "all_netbuy",
                  "n_opp_buyers", "n_opp_sellers", "n_officer_reports", "n_classified"]]


def main():
    d = load_reports()
    if d.empty:
        print("[cmp] no ok records yet — crawl 진행중"); return
    off = classify_routine(d)
    n_class = int(off["classified"].sum()); n_rout = int(off["is_routine"].sum())
    panel = build_panel(off)
    panel.to_parquet(OUTP, index=False)
    meta = {
        "rows": int(len(panel)),
        "n_officer_reports": int(len(off)),
        "n_classified": n_class,
        "n_routine": n_rout,
        "n_opportunistic": int(n_class - n_rout),
        "date_range": [panel["sig_month"].min(), panel["sig_month"].max()],
        "n_tickers": int(panel["Ticker"].nunique()),
        "routine_years": ROUTINE_YEARS,
        "note": "opp_netbuy = opportunistic-officer net-buy (CMP alpha). classified requires 3yr history.",
    }
    os.makedirs(os.path.dirname(METAP), exist_ok=True)
    json.dump(meta, open(METAP, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"[cmp] {len(panel)} ticker-months -> {OUTP}")
    print(f"  officer_reports={len(off)} classified={n_class} routine={n_rout} opp={n_class-n_rout}")
    print(f"  range {meta['date_range'][0]}..{meta['date_range'][1]} tickers={meta['n_tickers']}")


def selftest():
    """routine/opportunistic 분류 로직 synthetic 단위검증."""
    rows = []
    def rec(name, sc, ym, net):
        rows.append({"reporter_name": name, "reporter_type": "officer", "stock_code": sc,
                     "rcept_dt": ym.replace("-", "") + "15", "net_change_qty": net, "ok": True})
    # A: 매년 3월 거래 (2018,2019,2020,2021 3월) → 2021-03 = routine
    for y in (2018, 2019, 2020, 2021):
        rec("routine_guy", "000001", f"{y}-03", 100)
    # B: 불규칙 (2018-05, 2019-11, 2020-02, 2021-08) → 2021-08 = opportunistic(3yr 이력 有, 패턴 無)
    for ym in ("2018-05", "2019-11", "2020-02", "2021-08"):
        rec("opp_guy", "000002", ym, 200)
    # C: 이력 부족 (2021 첫 등장) → unclassified
    rec("new_guy", "000003", "2021-06", 300)
    d = pd.DataFrame(rows)
    d["net"] = d["net_change_qty"]; d["stock_code"] = d["stock_code"]
    d["ins_name"] = d["reporter_name"].map(norm_name)
    d["ym"] = pd.to_datetime(d["rcept_dt"].str[:6], format="%Y%m")
    d["year"] = d["ym"].dt.year; d["cmonth"] = d["ym"].dt.month
    off = classify_routine(d)
    g = off.set_index(["ins_name", "year", "cmonth"])[["classified", "is_routine"]]
    checks = [
        ("routine_guy 2021-03 = classified+routine", g.loc[("routine_guy", 2021, 3)].tolist() == [True, True]),
        ("opp_guy 2021-08 = classified+NOT routine", g.loc[("opp_guy", 2021, 8)].tolist() == [True, False]),
        ("new_guy 2021-06 = unclassified", g.loc[("new_guy", 2021, 6)].tolist() == [False, False]),
        ("routine_guy 2018-03 = unclassified(이력無)", g.loc[("routine_guy", 2018, 3)].tolist() == [False, False]),
    ]
    ok = all(c[1] for c in checks)
    for name, res in checks:
        print(f"  [{'PASS' if res else 'FAIL'}] {name}")
    print(f"SELFTEST {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(0 if selftest() else 1)
    main()
