#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_index_cache.py — QuantiWise Benchmark_price.xlsx → 지수 캐시 (재현 가능)

목적: benchmark.parquet(코스피200=IKS200) + indices.parquet(전 지수) 재빌드.
배경(2026-07-02): 기존 build_cache.R가 QT_to_xts 컬럼선택 버그로 benchmark.parquet에
                 IKS200(코스피200)이 아닌 IKS001(코스피 전체)를 넣고 있었음. 본 스크립트가
                 Code 행을 명시적으로 매칭해 정확한 IKS200을 뽑고, sanity 가드로 재발 방지.

사용: python 02_Infrastructure/data/build_index_cache.py [--update-rawdata] [--allow-grid-change]
  --update-rawdata     : RAWDATA.parquet의 BM_Ret 을 단일 writer(rawdata_bm_ret_sync.R --apply)로 동기화.
  --allow-grid-change  : benchmark.parquet 의 **날짜 격자 전면 교체**를 허용한다.
                         기본은 격자 보존(과거 삽입·기존 삭제 금지 · 전진만 반영) —
                         이 파일이 trading_calendar.R 의 거래일 권위이기 때문이다.
"""
import os, sys, shutil
import numpy as np
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

def _read_indices(xlsx=None):
    # ★인자 기본값 = 정본. 인자를 받으면 **그 파일**을 읽는다 — 수급기가 받아온 후보를
    #   교체 전에 검증하려면 같은 파서로 다른 파일을 읽을 수 있어야 한다
    #   (2026-09-18 실사고: benchmark_axis 가 경로를 넘겨도 여기서 무시돼 후보가 정본으로
    #    읽혔고, 새로 받아온 xlsx 가 "지평선 불변" 으로 기각됐다).
    wb = openpyxl.load_workbook(xlsx or XLSX, read_only=True, data_only=True)
    try:
        rows = list(wb.active.iter_rows(values_only=True))
    finally:
        wb.close()   # ★read_only 는 핸들을 잡는다 — 안 닫으면 후보 파일이 잠겨 교체·정리가 막힌다
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
        # ★2026-09-18: provenance(BM_Src) 같은 문자열 열도 실을 수 있게 — 구판은 전부
        #   float64 로 캐스팅해서 문자열 열이 조용히 사라졌다.
        if df[c].dtype == object:
            arrs[c] = pa.array(df[c].astype(str))
        else:
            arrs[c] = pa.array(df[c].astype("float64"))
    pq.write_table(pa.table(arrs), path)

def main(update_rawdata=False, allow_grid_change=False):
    df, cols = _read_indices()
    print(f"[build_index_cache] {len(df)}행 × {len(cols)}지수 | {df.Date.min()} ~ {df.Date.max()}")

    # sanity 가드: 코스피200 최근값이 코스피(전체, 수천대) 오선택 아닌지
    last200 = df["kospi200"].dropna().iloc[-1]
    if not (100 < last200 < 5000):
        raise RuntimeError(f"IKS200 sanity FAIL: 최근 코스피200={last200:.1f} (코스피 전체 오선택 의심)")

    # 1) indices.parquet (전 지수)
    _write_parquet(df, cols, os.path.join(CACHE, "indices.parquet"))
    print("  indices.parquet 작성")

    # 2) benchmark.parquet (코스피200 = book 벤치)
    #   (2026-07-04) IKS001→IKS200 마이그레이션 완료·검증 → 일회성 폐기-백업 블록 무효화.
    #   백업본은 캐시 정리 시 삭제됨. 재백업이 필요하면 QVEST_IKS_MIGRATION=1로 실행.
    bmk = os.path.join(CACHE, "benchmark.parquet")
    if os.environ.get("QVEST_IKS_MIGRATION") == "1":
        bak = os.path.join(CACHE, "benchmark_IKS001_WRONG_backup_20260702.parquet")
        if os.path.exists(bmk) and not os.path.exists(bak):
            shutil.copy(bmk, bak); print(f"  기존(잘못된 IKS001) 백업: {os.path.basename(bak)}")
    bm = df[["Date", "kospi200"]].dropna(subset=["kospi200"]).copy()
    bm.columns = ["Date", "BM_Close"]
    bm["BM_Ret"] = bm["BM_Close"] / bm["BM_Close"].shift(1) - 1

    # ★2026-09-18 축 정규화 — provenance 열. 이 경로는 **정본 원천**이고 배율이 없다
    #   (BM_Close = IKS200 포인트 그대로). 규약 = .cache/benchmark_axis.json::unit.
    bm["BM_Src"] = "quantiwise_iks200"

    # ★2026-09-18 신설 · 09-18 2차 강화 — **날짜 격자를 조용히 갈아끼우지 않는다**.
    #   benchmark.parquet 은 trading_calendar.R 의 거래일 유일 권위다. 이 재빌드는 xlsx 격자를
    #   그대로 쓰므로, 기존 파일과 행 집합이 다르면 **캘린더가 바뀐다**.
    #   실측(2026-09-18): xlsx 9,472행 vs 캐시 9,031행 — 차이는 행마다 성격이 다르다:
    #     · 1990~98 토요장 438행 = 진짜 세션인데 캐시에만 없다(복원 대상)
    #     · 2024-12-30 = 반대로 유령(QuantiWise RAWDATA·trading_calendar·캐시 셋 다 12-27 이 마지막)
    #   통째로 옳다/그르다 할 수 없으므로 처분은 도훈 판단이다.
    #   ★초판은 경고만 찍고 **그대로 썼다** — 그게 이 밤 내내 고친 바로 그 병(조용한 덮어쓰기)이다.
    #     이제 기본은 **격자 보존**이다: 과거 날짜 삽입·기존 날짜 삭제는 하지 않고, 마지막 날짜
    #     **이후**로 자라는 것만 받는다(그게 일일 갱신이다). 전면 교체는 --allow-grid-change 로만.
    bm_prev = None
    try:
        if os.path.exists(bmk):
            bm_prev = pq.read_table(bmk).to_pandas()
            bm_prev["Date"] = pd.to_datetime(bm_prev["Date"])
    except Exception as e:
        print(f"  (기존 캐시 판독 실패: {e.__class__.__name__} — 격자 보존 불가)")
        bm_prev = None

    if bm_prev is not None and len(bm_prev):
        prev_dates = set(bm_prev["Date"])
        prev_max = max(prev_dates)
        new_dates = set(pd.to_datetime(bm["Date"]))
        hist_inserts = sorted(d for d in (new_dates - prev_dates) if d <= prev_max)
        drops = sorted(prev_dates - new_dates)
        grows = sorted(d for d in (new_dates - prev_dates) if d > prev_max)
        if hist_inserts or drops:
            print(f"  ★[격자 차이] 기존 {len(prev_dates)}행 · xlsx {len(new_dates)}행 — "
                  f"과거삽입 {len(hist_inserts)} · 삭제 {len(drops)} · 전진 {len(grows)}")
            if hist_inserts:
                print(f"     과거삽입 예: {[str(d.date()) for d in hist_inserts[:3]]} … "
                      f"{[str(d.date()) for d in hist_inserts[-3:]]}")
            if drops:
                print(f"     삭제 예: {[str(d.date()) for d in drops[:3]]} … "
                      f"{[str(d.date()) for d in drops[-3:]]}")
        if (hist_inserts or drops) and not allow_grid_change:
            # 격자 보존 — 기존 날짜 ∪ 전진분. 값은 xlsx 우선, 없으면 기존 값 유지.
            keep = sorted(prev_dates | set(grows))
            base = pd.DataFrame({"Date": keep})
            xl = bm.copy(); xl["Date"] = pd.to_datetime(xl["Date"])
            merged = base.merge(xl[["Date", "BM_Close"]], on="Date", how="left")
            merged = merged.merge(bm_prev[["Date", "BM_Close"]].rename(
                columns={"BM_Close": "BM_Close_prev"}), on="Date", how="left")
            merged["BM_Src"] = np.where(merged["BM_Close"].notna(),
                                        "quantiwise_iks200", "legacy_cache_kept")
            merged["BM_Close"] = merged["BM_Close"].fillna(merged["BM_Close_prev"])
            merged = merged.dropna(subset=["BM_Close"]).drop(columns=["BM_Close_prev"])
            merged = merged.sort_values("Date").reset_index(drop=True)
            merged["BM_Ret"] = merged["BM_Close"] / merged["BM_Close"].shift(1) - 1
            merged["Date"] = merged["Date"].dt.date
            bm = merged[["Date", "BM_Close", "BM_Ret", "BM_Src"]]
            n_kept = int((bm["BM_Src"] == "legacy_cache_kept").sum())
            print(f"     ⇒ 격자 보존 모드: {len(bm)}행 (전진 {len(grows)} 반영 · "
                  f"xlsx 미포함 {n_kept}행은 기존 값 유지). 전면 교체는 --allow-grid-change")
            print("     ※토요장 복원·유령 삭제는 캘린더 변경이다 — 도훈 판단으로만 한다.")
        elif hist_inserts or drops:
            print("     ⇒ --allow-grid-change 지정 — **캘린더가 바뀐다**(xlsx 격자 그대로)")

    _write_parquet(bm, ["BM_Close", "BM_Ret", "BM_Src"], bmk)
    print(f"  benchmark.parquet 작성 (코스피200 포인트) — 최근 {bm['BM_Close'].iloc[-1]:,.1f}")

    # 3) (옵션) RAWDATA.parquet BM_Ret 동기화 — ★W-09(2026-09-23): 단일 writer 위임.
    #   구판은 여기서 BM_Ret 열 전체를 벤치로 갈아엎고 **BM_Ret NA 행을 삭제**했다(벤치 지연일의
    #   전 종목 행이 사라진다) · 보호 구간(1990~98 토요장 계열 · 2024-12-30)까지 덮었다 · 비원자 쓰기.
    #   정의·보호·킬스위치·원자 쓰기·사후검증은 rawdata_bm_ret_sync.R 하나가 진다.
    if update_rawdata:
        import subprocess
        rscript = shutil.which("Rscript") or r"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
        sync_r = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rawdata_bm_ret_sync.R")
        env = dict(os.environ, QM_ROOT=os.path.dirname(CACHE))
        rc = subprocess.call([rscript, "--no-save", sync_r, "--apply"], env=env)
        print(f"  RAWDATA BM_Ret 동기화 (단일 writer rawdata_bm_ret_sync.R) rc={rc} "
              f"(0=정합 · 4=벤치 지연 NA 유지 · 3=위반 · 1=오류)")

    # 검증
    d2 = df.copy(); d2["ym"] = pd.to_datetime(d2["Date"]).dt.strftime("%Y-%m")
    me = d2.groupby("ym")["kospi200"].last()
    print("  검증 코스피200 2026 월수익:",
          " ".join(f"{m[-2:]}월{me.pct_change()[m]*100:+.1f}%" for m in
                   ["2026-02","2026-03","2026-04","2026-05","2026-06"]))

if __name__ == "__main__":
    main(update_rawdata=("--update-rawdata" in sys.argv),
         allow_grid_change=("--allow-grid-change" in sys.argv))
