#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_index_cache.py — QuantiWise Benchmark_price.xlsx → 지수 캐시 (재현 가능)

목적: benchmark.parquet(코스피200=IKS200) + indices.parquet(전 지수) 재빌드.
배경(2026-07-02): 기존 build_cache.R가 QT_to_xts 컬럼선택 버그로 benchmark.parquet에
                 IKS200(코스피200)이 아닌 IKS001(코스피 전체)를 넣고 있었음. 본 스크립트가
                 Code 행을 명시적으로 매칭해 정확한 IKS200을 뽑고, sanity 가드로 재발 방지.

사용: python 02_Infrastructure/data/build_index_cache.py [--update-rawdata]
  --update-rawdata : RAWDATA.parquet의 BM_Ret도 코스피200 기준으로 재생성(백업 후).
"""
import os, sys, shutil
import pandas as pd, numpy as np
import openpyxl, pyarrow as pa, pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
XLSX = os.path.join(ROOT, "03_Universe", "Benchmark_price.xlsx")
CACHE = os.path.join(ROOT, ".cache")

# QW 코드 → 가독 컬럼명 (필요 시 확장)
NAMEMAP = {
    "IKS001": "kospi",      "IKS170": "kospi_tr",    "IKS002": "kospi_large",
    "IKS003": "kospi_mid",  "IKS004": "kospi_small", "IKS200": "kospi200",
    "IKS500": "kospi200_ew","IKS270": "kospi200_tr", "IKQ001": "kosdaq",
    "IKQ170": "kosdaq_tr",  "IKQ150": "kosdaq150",   "IKQ270": "kosdaq150_tr",
    "IKQ500": "kosdaq150_ew","IKQ002": "kosdaq_large","IKQ003": "kosdaq_mid",
    "IKQ004": "kosdaq_small","W00": "all_firms",     "IKS221": "kospi200_vol",
}

def _read_indices():
    wb = openpyxl.load_workbook(XLSX, read_only=True, data_only=True)
    rows = list(wb.active.iter_rows(values_only=True))
    codes = list(rows[7])                       # ['Code','IKS001',...] — Code 행
    colidx = {NAMEMAP[c]: i for i, c in enumerate(codes) if c in NAMEMAP}
    if "kospi200" not in colidx:
        raise RuntimeError("IKS200(코스피200) 컬럼을 찾지 못함 — Benchmark_price.xlsx 구조 확인")
    recs = []
    for r in rows[12:]:                          # row12+ = 실제 일별 데이터
        if r[0] is None:
            continue
        d = pd.to_datetime(r[0], errors="coerce")
        if pd.isna(d):
            continue
        row = {"Date": d.date()}
        for nm, i in colidx.items():
            row[nm] = pd.to_numeric(r[i], errors="coerce")
        recs.append(row)
    df = pd.DataFrame(recs).sort_values("Date").reset_index(drop=True)
    return df, [NAMEMAP[c] for c in codes if c in NAMEMAP]

def _write_parquet(df, cols, path):
    arrs = {"Date": pa.array(df["Date"], type=pa.date32())}
    for c in cols:
        arrs[c] = pa.array(df[c].astype("float64"))
    pq.write_table(pa.table(arrs), path)

def main(update_rawdata=False):
    df, cols = _read_indices()
    print(f"[build_index_cache] {len(df)}행 × {len(cols)}지수 | {df.Date.min()} ~ {df.Date.max()}")

    # sanity 가드: 코스피200 최근값이 코스피(전체, 수천대) 오선택 아닌지
    last200 = df["kospi200"].dropna().iloc[-1]
    if not (100 < last200 < 5000):
        raise RuntimeError(f"IKS200 sanity FAIL: 최근 코스피200={last200:.1f} (코스피 전체 오선택 의심)")

    # 1) indices.parquet (전 지수)
    _write_parquet(df, cols, os.path.join(CACHE, "indices.parquet"))
    print("  indices.parquet 작성")

    # 2) benchmark.parquet (코스피200 = book 벤치) — 최초 1회 백업
    bmk = os.path.join(CACHE, "benchmark.parquet")
    bak = os.path.join(CACHE, "benchmark_IKS001_WRONG_backup_20260702.parquet")
    if os.path.exists(bmk) and not os.path.exists(bak):
        shutil.copy(bmk, bak); print(f"  기존(잘못된 IKS001) 백업: {os.path.basename(bak)}")
    bm = df[["Date", "kospi200"]].dropna(subset=["kospi200"]).copy()
    bm.columns = ["Date", "BM_Close"]
    bm["BM_Ret"] = bm["BM_Close"] / bm["BM_Close"].shift(1) - 1
    _write_parquet(bm, ["BM_Close", "BM_Ret"], bmk)
    print(f"  benchmark.parquet 작성 (코스피200) — 최근 {bm['BM_Close'].iloc[-1]:,.1f}")

    # 3) (옵션) RAWDATA.parquet BM_Ret 재생성
    if update_rawdata:
        raw_path = os.path.join(CACHE, "RAWDATA.parquet")
        raw_bak = os.path.join(CACHE, "rawdata_pre_kospi200bench_20260702.parquet")
        if not os.path.exists(raw_bak):
            shutil.copy(raw_path, raw_bak); print(f"  RAWDATA 백업: {os.path.basename(raw_bak)}")
        raw = pq.read_table(raw_path).to_pandas()
        raw["Date"] = pd.to_datetime(raw["Date"]).dt.date
        bmr = bm[["Date", "BM_Ret"]].rename(columns={"BM_Ret": "BM_Ret_new"})
        raw = raw.merge(bmr, on="Date", how="left")
        raw["BM_Ret"] = raw["BM_Ret_new"]; raw = raw.drop(columns=["BM_Ret_new"])
        raw = raw[raw["BM_Ret"].notna() & raw["Ret"].notna()]
        pq.write_table(pa.Table.from_pandas(raw, preserve_index=False), raw_path)
        print(f"  RAWDATA.parquet BM_Ret 재생성 (코스피200 기준) — {len(raw):,}행")

    # 검증
    d2 = df.copy(); d2["ym"] = pd.to_datetime(d2["Date"]).dt.strftime("%Y-%m")
    me = d2.groupby("ym")["kospi200"].last()
    print("  검증 코스피200 2026 월수익:",
          " ".join(f"{m[-2:]}월{me.pct_change()[m]*100:+.1f}%" for m in
                   ["2026-02","2026-03","2026-04","2026-05","2026-06"]))

if __name__ == "__main__":
    main(update_rawdata=("--update-rawdata" in sys.argv))
