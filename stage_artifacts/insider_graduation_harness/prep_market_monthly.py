#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""prep_market_monthly.py — RAWDATA(daily) → 슬림 월별 시장 입력 (canonical screen용).

R 쪽 arrow read_parquet 이 OneDrive 대용량 RAWDATA 에서 halt(Windows arrow mmap 1224)하는
이슈 회피: 무거운 daily→monthly 집계를 Python 에서 수행하고, R 은 슬림 parquet 3개만 소비.

산출(모두 data/):
  market_returns_monthly.parquet  : Date(month-begin), Ticker, Ret_1m(월 실현수익), univ(K200∪KQ150)
  bench_monthly.parquet           : Date(month-begin), BM_Ret(월누적 index return)
  liq_monthly.parquet             : Date(month-begin=홀딩월), Ticker, adv(직전월말 trailing-20d ADV, t-1 PIT)

PIT: Ret_1m 은 그 월(Date의 월)의 실현수익. 신호 Date(=usable month begin)와 join → 홀딩월 정렬.
     adv 는 홀딩월 직전월말 값(t-1). 자체합성 백테 없음(수익 시계열 raw만).
"""
import os
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

R = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
HARN = os.path.join(R, "stage_artifacts", "insider_graduation_harness")
os.makedirs(os.path.join(HARN, "data"), exist_ok=True)


def main():
    rd = pq.read_table(os.path.join(R, ".cache", "RAWDATA.parquet"),
                       columns=["Date", "Ticker", "Ret", "BM_Ret", "Close", "Vol", "K200", "KQ150"]).to_pandas()
    rd["Date"] = pd.to_datetime(rd["Date"])
    rd["ym"] = rd["Date"].dt.to_period("M")
    rd = rd.sort_values(["Ticker", "Date"])
    rd["lr"] = np.log1p(rd["Ret"].clip(lower=-0.99))

    # monthly ticker return + universe flag
    g = rd.groupby(["Ticker", "ym"])
    m = g.agg(lr=("lr", "sum"),
              K200=("K200", lambda s: int((s > 0).any())),
              KQ150=("KQ150", lambda s: int((s > 0).any()))).reset_index()
    m["Ret_1m"] = np.expm1(m["lr"])
    m["univ"] = (m["K200"] == 1) | (m["KQ150"] == 1)
    m["Date"] = m["ym"].dt.to_timestamp(how="start")
    mret = m[m["univ"]][["Date", "Ticker", "Ret_1m"]].copy()
    mret["univ"] = True
    mret.to_parquet(os.path.join(HARN, "data", "market_returns_monthly.parquet"), index=False)

    # benchmark monthly (index return, same across tickers per day)
    bd = rd[["Date", "ym", "BM_Ret"]].drop_duplicates(subset=["Date"])
    bd["blr"] = np.log1p(bd["BM_Ret"].clip(lower=-0.99))
    bm = bd.groupby("ym").agg(BM_Ret=("blr", lambda s: np.expm1(s.sum()))).reset_index()
    bm["Date"] = bm["ym"].dt.to_timestamp(how="start")
    bm[["Date", "BM_Ret"]].to_parquet(os.path.join(HARN, "data", "bench_monthly.parquet"), index=False)

    # liquidity: trailing-20d ADV (Close*Vol), month-end value → usable next month (t-1 PIT)
    rd["adv_daily"] = rd["Close"] * rd["Vol"]
    rd["adv20"] = rd.groupby("Ticker")["adv_daily"].transform(
        lambda s: s.rolling(20, min_periods=20).mean())
    me = rd.groupby(["Ticker", "ym"]).agg(adv20_me=("adv20", "last")).reset_index()
    # ADV of month M usable in holding month M+1
    me["hold_ym"] = me["ym"] + 1
    me["Date"] = me["hold_ym"].dt.to_timestamp(how="start")
    liq = me[me["adv20_me"].notna()][["Date", "Ticker", "adv20_me"]].rename(columns={"adv20_me": "adv"})
    liq.to_parquet(os.path.join(HARN, "data", "liq_monthly.parquet"), index=False)

    print(f"[prep] market_returns rows={len(mret)} ({mret.Date.min().date()}..{mret.Date.max().date()})")
    print(f"[prep] bench rows={len(bm)} | liq rows={len(liq)}")
    print("[prep] wrote market_returns_monthly / bench_monthly / liq_monthly")


if __name__ == "__main__":
    main()
