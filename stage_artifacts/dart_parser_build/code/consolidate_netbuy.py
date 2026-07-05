#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
월별 체크포인트 → 최종 net-buy 신호 parquet 통합 (PIT-safe).
==============================================================================
산출:
  insider_netbuy_monthly.parquet — ticker × sig_month 신호 패널.
    sig_month = rcept_dt(접수일)의 월 → t-1 lag: 신호는 익월(rcept 월+1)의 결정에 사용 가능.
    (PIT: 접수일 D 에 시장 인지 → 그 달 말 리밸런싱은 이미 안 시점. 보수적 t-1 = 익월 사용.)

  컬럼:
    Ticker(A-prefix), stock_code, sig_month(YYYY-MM, 신호 산출 기준월=rcept월),
    usable_month(YYYY-MM, 사용 가능 월 = sig_month+1, PIT lag),
    net_qty(전체 증감 합), net_qty_disc(장내매매만),
    n_buy, n_sell, n_reports, n_buyers,
    net_qty_officer(임원만 증감), n_officer_buy, n_officer_sell  (v3+ 신뢰)
    officer vs 10%주주 분리 — 국민연금 등 기계적 매도 노이즈 격리용.

officer 분리 근거(도훈 mandate): 10%주주(연기금 등)의 지수편입/리밸 기계적 매매는 정보성 낮음.
  → 임원(officer) 매수/매도가 진짜 내부정보 신호. usable에서 별도 컬럼 제공.

주: 절대 자체합성 백테스트 없음 — 순수 신호 패널만. alpha/forge 가 소비.
작성: 2026-07-05 (신규).
"""
import os, json
import pandas as pd

ROOT = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
BUILD = os.path.join(ROOT, "stage_artifacts", "dart_parser_build")
CKDIR = os.path.join(BUILD, "cache", "monthly")
OUTP = os.path.join(BUILD, "data", "insider_netbuy_monthly.parquet")
os.makedirs(os.path.join(BUILD, "data"), exist_ok=True)


def main():
    files = sorted(f for f in os.listdir(CKDIR) if f.endswith(".parquet"))
    frames = []
    for f in files:
        df = pd.read_parquet(os.path.join(CKDIR, f))
        if "ok" not in df.columns:
            continue  # month w/ no universe insider (note-only checkpoint)
        df = df[df["ok"] == True].copy()
        if len(df):
            frames.append(df)
    if not frames:
        print("no ok records yet"); return
    d = pd.concat(frames, ignore_index=True)

    d["net"] = pd.to_numeric(d["net_change_qty"], errors="coerce")
    d["disc"] = pd.to_numeric(d.get("disc_change_qty"), errors="coerce")
    d = d[d["net"].notna()]
    d["stock_code"] = d["stock_code"].astype(str).str.zfill(6)
    d["sig_month"] = d["rcept_dt"].astype(str).str[:6]
    d["sig_month"] = pd.to_datetime(d["sig_month"], format="%Y%m").dt.strftime("%Y-%m")
    d["is_officer"] = (d["reporter_type"] == "officer")

    def agg(g):
        return pd.Series({
            "net_qty": g["net"].sum(),
            "net_qty_disc": g["disc"].dropna().sum() if g["disc"].notna().any() else None,
            "n_buy": int((g["net"] > 0).sum()),
            "n_sell": int((g["net"] < 0).sum()),
            "n_reports": int(len(g)),
            "n_buyers": int(g.loc[g["net"] > 0, "reporter_name"].nunique()),
            "net_qty_officer": g.loc[g["is_officer"], "net"].sum(),
            "n_officer_buy": int(((g["net"] > 0) & g["is_officer"]).sum()),
            "n_officer_sell": int(((g["net"] < 0) & g["is_officer"]).sum()),
        })

    panel = d.groupby(["stock_code", "sig_month"]).apply(agg, include_groups=False).reset_index()
    panel["Ticker"] = "A" + panel["stock_code"]
    # PIT lag: usable one month after signal month
    um = pd.to_datetime(panel["sig_month"], format="%Y-%m") + pd.offsets.MonthBegin(1)
    panel["usable_month"] = um.dt.strftime("%Y-%m")

    panel = panel[["Ticker", "stock_code", "sig_month", "usable_month",
                   "net_qty", "net_qty_disc", "n_buy", "n_sell", "n_reports", "n_buyers",
                   "net_qty_officer", "n_officer_buy", "n_officer_sell"]]
    panel.to_parquet(OUTP, index=False)

    meta = {
        "rows": int(len(panel)),
        "months_covered": sorted(panel["sig_month"].unique().tolist()),
        "n_tickers": int(panel["Ticker"].nunique()),
        "date_range": [panel["sig_month"].min(), panel["sig_month"].max()],
        "pit_note": "sig_month = rcept_dt month; usable_month = sig_month+1 (t-1 lag, PIT-safe)",
        "officer_note": "net_qty_officer reliable v3+ (2010+); pre-2007 reporter-type sparse (v2.8)",
    }
    json.dump(meta, open(os.path.join(BUILD, "reports", "netbuy_panel_meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)
    print(f"[consolidate] wrote {len(panel)} ticker-months -> {OUTP}")
    print(f"  months: {meta['date_range'][0]} .. {meta['date_range'][1]}  tickers: {meta['n_tickers']}")


if __name__ == "__main__":
    main()
