#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
DART insider net-buy panel -> sleeve score parquet (harness-ready).
==============================================================================
입력: stage_artifacts/dart_parser_build/data/insider_netbuy_monthly.parquet
      (Ticker, stock_code, sig_month, usable_month, net_qty, net_qty_officer, ...)

출력(격리): stage_artifacts/dart_sleeve_test/data/cache_<CODE>.parquet
      columns: Date (month-end Timestamp of sig_month), Ticker, score
      -> eval_lag1.R blend() 이 ym=format(Date,"%Y-%m") 로 읽고 LAG=1 forward-shift.
         => sleeve sig_month=m 가 decision month m+1 로 이동 (usable_month 과 일치, 단일 PIT lag).

sleeve 변형 (officer 우선 — 10%주주 기계매도 격리):
  DINSD_OFF   : net_qty_officer sign(+매수 우위)  -- 임원 순매수 신호(2010+ 신뢰)
  DINSD_OFFB  : n_officer_buy - n_officer_sell (breadth, 규모 무관)
  DINSD_NET   : net_qty (전체, officer 포함 — pre-2010 fallback + full-coverage 비교)
  DINSD_BRD   : n_buy - n_sell (전체 breadth)

score = 그 달의 신호값 (원시). 표준화(cross-sectional z)는 harness blend() 가 수행(zc by Date).
신호 없는 종목-월 = 결측 -> harness 가 sz=0 (중립) 처리. 자체합성 없음.

작성: 2026-07-05 (도훈 mandate DART sleeve). 격리 산출.
"""
import os
import sys
import pandas as pd

ROOT = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
PANEL = os.path.join(ROOT, "stage_artifacts", "dart_parser_build", "data", "insider_netbuy_monthly.parquet")
OUTDIR = os.path.join(ROOT, "stage_artifacts", "dart_sleeve_test", "data")
os.makedirs(OUTDIR, exist_ok=True)

# sleeve def: code -> (column, transform)  transform in {"raw","sign","breadth_off","breadth_all"}
SLEEVES = {
    "DINSD_OFF":  ("net_qty_officer", "raw"),
    "DINSD_OFFB": (None,              "breadth_off"),   # n_officer_buy - n_officer_sell
    "DINSD_NET":  ("net_qty",         "raw"),
    "DINSD_BRD":  (None,              "breadth_all"),    # n_buy - n_sell
}


def month_end(sig_month):
    # sig_month "YYYY-MM" -> month-end Timestamp (aligns to BASE month-end Date convention)
    return (pd.to_datetime(sig_month, format="%Y-%m") + pd.offsets.MonthEnd(0))


def main():
    if not os.path.exists(PANEL):
        print(f"[sleeve] PANEL missing: {PANEL} — run consolidate_netbuy.py first")
        sys.exit(1)
    p = pd.read_parquet(PANEL)
    p["Date"] = month_end(p["sig_month"])
    n_written = {}
    for code, (col, tf) in SLEEVES.items():
        d = p.copy()
        if tf == "raw":
            d["score"] = pd.to_numeric(d[col], errors="coerce")
        elif tf == "breadth_off":
            d["score"] = pd.to_numeric(d["n_officer_buy"], errors="coerce") - pd.to_numeric(d["n_officer_sell"], errors="coerce")
        elif tf == "breadth_all":
            d["score"] = pd.to_numeric(d["n_buy"], errors="coerce") - pd.to_numeric(d["n_sell"], errors="coerce")
        d = d[d["score"].notna()].copy()
        # drop exact-zero signals? keep — zero net can be informative (offsetting), but harness z-scores anyway.
        out = d[["Date", "Ticker", "score"]].drop_duplicates(subset=["Date", "Ticker"])
        outf = os.path.join(OUTDIR, f"cache_{code}.parquet")
        out.to_parquet(outf, index=False)
        n_written[code] = len(out)
        rng = (out["Date"].min(), out["Date"].max())
        print(f"[sleeve] {code:12s} rows={len(out):6d}  Date {rng[0].strftime('%Y-%m') if len(out) else '-'}..{rng[1].strftime('%Y-%m') if len(out) else '-'}  nonzero={(out['score']!=0).sum()}")
    print(f"[sleeve] wrote {len(n_written)} sleeves -> {OUTDIR}")


if __name__ == "__main__":
    main()
