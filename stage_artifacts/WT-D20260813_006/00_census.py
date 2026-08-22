# -*- coding: utf-8 -*-
"""
WT-D20260813_006 / FQ-234 Lane B — 착수 0항 ② 커버리지 census (실측)
원천: .cache/investor_stock/investor_wide.parquet (일별 순매수대금 KRW)
      .cache/RAWDATA.parquet (일별 OHLCVS + K200/KQ150 플래그)
판정 없음 — 개수/gap 실측만.
"""
import sys, json
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

sys.stdout.reconfigure(encoding="utf-8")
ROOT = r"C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT = {}

# ---------- 1) investor_wide census ----------
iw = pq.ParquetFile(f"{ROOT}/.cache/investor_stock/investor_wide.parquet")
OUT["investor_wide_rows"] = int(iw.metadata.num_rows)
inv = pd.read_parquet(f"{ROOT}/.cache/investor_stock/investor_wide.parquet",
                      columns=["Date", "Ticker", "Foreign", "Individual", "Institutional"])
inv["Date"] = pd.to_datetime(inv["Date"])
OUT["investor_wide_date_min"] = str(inv["Date"].min().date())
OUT["investor_wide_date_max"] = str(inv["Date"].max().date())
inv_ym = inv["Date"].dt.to_period("M")
u_ym = np.sort(inv_ym.unique())
OUT["investor_wide_n_months_observed"] = int(len(u_ym))
theo = (u_ym[-1] - u_ym[0]).n + 1
OUT["investor_wide_n_months_theoretical"] = int(theo)
OUT["investor_wide_month_gap"] = int(theo - len(u_ym))
inv_days = np.sort(inv["Date"].unique())
OUT["investor_wide_n_tradingdays"] = int(len(inv_days))
OUT["investor_wide_n_tickers"] = int(inv["Ticker"].nunique())
# 결측률
for c in ["Foreign", "Individual", "Institutional"]:
    OUT[f"investor_wide_na_frac_{c}"] = float(inv[c].isna().mean())
    OUT[f"investor_wide_zero_frac_{c}"] = float((inv[c].fillna(0) == 0).mean())

# ---------- 2) RAWDATA census ----------
raw = pd.read_parquet(f"{ROOT}/.cache/RAWDATA.parquet",
                      columns=["Date", "Ticker", "K200", "KQ150", "Close", "Vol", "Size", "Ret"])
raw["Date"] = pd.to_datetime(raw["Date"])
OUT["rawdata_rows"] = int(len(raw))
OUT["rawdata_date_min"] = str(raw["Date"].min().date())
OUT["rawdata_date_max"] = str(raw["Date"].max().date())
raw_days = np.sort(raw["Date"].unique())
OUT["rawdata_n_tradingdays"] = int(len(raw_days))
r_ym = raw["Date"].dt.to_period("M")
ru = np.sort(r_ym.unique())
OUT["rawdata_n_months_observed"] = int(len(ru))
OUT["rawdata_n_months_theoretical"] = int((ru[-1] - ru[0]).n + 1)

# ---------- 3) 거래일 축 정합 (flow days ⊂ rawdata days?) ----------
rd = set(pd.DatetimeIndex(raw_days))
idset = set(pd.DatetimeIndex(inv_days))
OUT["flowdays_not_in_rawdays"] = int(len(idset - rd))
common_lo = max(inv["Date"].min(), raw["Date"].min())
common_hi = min(inv["Date"].max(), raw["Date"].max())
OUT["common_window"] = [str(common_lo.date()), str(common_hi.date())]
rd_in = set(d for d in rd if common_lo <= d <= common_hi)
OUT["rawdays_in_common_not_in_flow"] = int(len(rd_in - idset))
OUT["n_rawdays_in_common"] = int(len(rd_in))

# ---------- 4) 유니버스 커버리지: 유니버스 종목 중 flow 존재 비율 (연도별) ----------
raw["univ"] = (raw["K200"].fillna(0) > 0) | (raw["KQ150"].fillna(0) > 0)
u = raw.loc[raw["univ"], ["Date", "Ticker"]]
u = u[(u["Date"] >= common_lo) & (u["Date"] <= common_hi)]
inv_key = inv[["Date", "Ticker"]].copy()
inv_key["has_flow"] = 1
m = u.merge(inv_key, on=["Date", "Ticker"], how="left")
m["yr"] = m["Date"].dt.year
cov = m.groupby("yr")["has_flow"].agg(["mean", "size"])
OUT["universe_flow_coverage_by_year"] = {int(k): [round(float(v[0]), 4), int(v[1])]
                                         for k, v in cov.iterrows()}

# ---------- 5) 유니버스 크기 / KQ150 소급투영 확인(FQ-241 승계) ----------
raw["ym"] = raw["Date"].dt.to_period("M").astype(str)
mend = raw.groupby("ym")["Date"].max().rename("mdate")
last = raw.merge(mend, left_on="ym", right_index=True)
last = last[last["Date"] == last["mdate"]]
sz = last.groupby("ym").agg(n_k200=("K200", lambda s: int((s.fillna(0) > 0).sum())),
                            n_kq150=("KQ150", lambda s: int((s.fillna(0) > 0).sum())))
OUT["universe_size_sample"] = {k: [int(a), int(b)] for k, (a, b) in
                               sz.loc[["2005-01", "2010-01", "2011-06", "2015-06", "2015-07",
                                       "2020-01", "2026-06"]].iterrows()}

print(json.dumps(OUT, ensure_ascii=False, indent=1))
with open(f"{ROOT}/stage_artifacts/WT-D20260813_006/00_census.json", "w", encoding="utf-8") as f:
    json.dump(OUT, f, ensure_ascii=False, indent=1)
