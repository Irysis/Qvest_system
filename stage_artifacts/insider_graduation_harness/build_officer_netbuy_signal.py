#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""build_officer_netbuy_signal.py — DART 임원(officer) 장내 순매수 신호 패널 (재배선판).

★ 재배선 배경 (도훈 mandate 2026-07-06):
  기존 04_Research/insider/build_insider_signal.py 는 옛 elestock CSV 경로
  (.cache/dart/insider_backfill/*.csv, capped/빈값)를 읽는 버그. 여기서는
  **새 원문파서 출력(stage_artifacts/dart_parser_build/cache/monthly/*.parquet)**을 소비.

이 스크립트는 **신호 패널만** 산출 (자체합성 백테 없음 — canonical_screen_bt(R)가 소비).
idempotent: 매 실행 시 현 커버리지의 monthly 체크포인트를 전량 재소비.
backfill(다른 세션 소유)이 월을 추가하면 재실행 시 자동으로 최신 커버리지 반영.

────────────────────────────────────────────────────────────────────────────
신호 구성 (net officer OPEN-MARKET buying, KRW flow)
────────────────────────────────────────────────────────────────────────────
1) officer-only:  reporter_type == "officer"  (등기+비등기 임원. 주요주주/지배주주/기타 제외)
     — 주요주주(10%주주·연기금)의 블록딜/지수리밸 기계적 매매 노이즈 격리.
     — 주의: pre-2009 파일은 reporter_type 필드 sparse(README §한계) → officer=0.
       이 경우 그 월은 officer 신호 부재로 자연 제외(과대주장 안 함).

2) mechanical 제외:  n_mechanical == 0 인 report만 채택.
     — 원문파서가 report별 n_discretionary/n_offmarket/n_mechanical 카운트.
       n_mechanical>0 = 주식분할·유상신주취득·임원선임상여·전환 등 섞인 report
       → net_change_qty 가 mechanical 로 오염(예: 주식분할 +47.5M) → 통째 배제.
     — disc_change_qty(장내매매 순증감)는 파서에서 CPT_CNT 추출 실패로 전량 NULL
       (검증됨) → 사용 불가. 따라서 report-level n_mechanical==0 필터가 유일한
       clean 경로. 남는 report의 net_change_qty 는 장내/장외 매매만 → 신호로 채택.
     — 추가 보수: n_discretionary>0 (장내매매 1건 이상 포함) report만 (순수 장외/무거래 배제).

3) common-stock market trades:  파서 net_change_qty(MDF_STK_SUM)는 '특정증권등' 합계.
     보통주 한정 별도 필드 부재 → n_mechanical==0 & n_discretionary>0 로 근사(장내매매=보통주 대다수).
     한계로 라벨.

4) KRW flow:  firm-month net officer flow = Σ(net_change_qty × price_at_month_end).
     price = 해당 종목 rcept 월말 Close (RAWDATA). qty×price = 명목 순매수 KRW.
     — 규모/유동성 정규화: firm-month flow 를 종목 월말 시가총액(Size)으로 나눈
       normalized flow(nflow = KRW / mktcap) 도 산출(대형주 규모편향 완화).
     — 두 변형 모두 저장: raw KRW flow(krw) + normalized(nflow).

────────────────────────────────────────────────────────────────────────────
★★ PIT (오늘 세션 최대 교훈 — anti-look-ahead 배선)
────────────────────────────────────────────────────────────────────────────
signal month M (= rcept_dt 의 월)의 필링은 **M+1 수익에만** 적용.
  usable_month = sig_month + 1  (일관: consolidate_netbuy 규약과 동일)
  canonical screen 에 넘길 때 Date = usable_month 의 월초(first-day-of usable month).
  → returns_dt 의 Ret_1m 은 그 Date 로부터의 forward 1M(즉 usable_month 실현수익).
  즉 rcept_dt(M) < first-day-of(usable_month=M+1) 항상 성립 → 홀딩월 시작 전 정보만.

  ⚠ 절대 금지: 'Date < anchor_date' 류 (오늘 BearProb faith 버그 = 동월 look-ahead).
     여기선 sig(M) → return(M+1) 로 월 경계를 명시 분리. 동월 사용 없음.

  lag1 스트레스: PIT_LAG 환경변수(default 1)로 usable_month = sig_month + PIT_LAG.
     PIT_LAG=2 로 재실행 시 신호 1개월 추가 지연 → graceful degrade(누출 없음) 확인용.

산출: data/officer_netbuy_panel.parquet  (Date=usable month-begin, Ticker, krw, nflow, n_reports, sig_month)
      reports/signal_build_meta.json
"""
import os, sys, glob, json
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

R = os.environ.get("QM_ROOT", r"C:\Users\99922\OneDrive\Quant_Module_Moltbot")
BUILD = os.path.join(R, "stage_artifacts", "dart_parser_build")
CKDIR = os.path.join(BUILD, "cache", "monthly")
HARN = os.path.join(R, "stage_artifacts", "insider_graduation_harness")
os.makedirs(os.path.join(HARN, "data"), exist_ok=True)
os.makedirs(os.path.join(HARN, "reports"), exist_ok=True)

PIT_LAG = int(os.environ.get("PIT_LAG", "1"))   # months from sig_month to usable_month (>=1 => no same-month)
assert PIT_LAG >= 1, "PIT_LAG must be >=1 (same-month use is look-ahead)"

OFFICER_ONLY = os.environ.get("OFFICER_ONLY", "1") == "1"


def load_monthly_trades():
    files = sorted(glob.glob(os.path.join(CKDIR, "*.parquet")))
    frames = []
    for f in files:
        d = pd.read_parquet(f)
        if "ok" not in d.columns:
            continue
        d = d[d["ok"] == True].copy()
        if len(d):
            frames.append(d)
    if not frames:
        raise SystemExit("no ok records in monthly checkpoints")
    d = pd.concat(frames, ignore_index=True)
    return d


def main():
    d = load_monthly_trades()
    n_all = len(d)

    d["net"] = pd.to_numeric(d["net_change_qty"], errors="coerce")
    d["nmech"] = pd.to_numeric(d.get("n_mechanical"), errors="coerce").fillna(0)
    d["ndisc"] = pd.to_numeric(d.get("n_discretionary"), errors="coerce").fillna(0)
    d["stock_code"] = d["stock_code"].astype(str).str.zfill(6)
    d = d[d["net"].notna() & (d["stock_code"].str.len() == 6)]

    # sig month from rcept_dt (YYYYMMDD)
    d["sig_month"] = pd.to_datetime(d["rcept_dt"].astype(str).str[:6], format="%Y%m").dt.strftime("%Y-%m")

    # --- filters ---
    n_before_filter = len(d)
    # (1) officer-only
    if OFFICER_ONLY:
        d = d[d["reporter_type"] == "officer"]
    n_officer = len(d)
    # (2) mechanical exclusion: keep reports w/ zero mechanical txns AND >=1 discretionary(장내) txn
    d = d[(d["nmech"] == 0) & (d["ndisc"] > 0)]
    n_clean = len(d)

    d["Ticker"] = "A" + d["stock_code"]

    # ── price + mktcap join (month-end Close, Size) from RAWDATA ──────────────
    rd = pq.read_table(os.path.join(R, ".cache", "RAWDATA.parquet"),
                       columns=["Date", "Ticker", "Close", "Size"]).to_pandas()
    rd["Date"] = pd.to_datetime(rd["Date"])
    rd["ym"] = rd["Date"].dt.to_period("M").astype(str)
    # month-end (last available trading day of month) Close & Size per ticker-month
    rd = rd.sort_values(["Ticker", "ym", "Date"])
    me = rd.groupby(["Ticker", "ym"]).agg(Close=("Close", "last"), Size=("Size", "last")).reset_index()
    me = me.rename(columns={"ym": "sig_month"})

    d = d.merge(me, on=["Ticker", "sig_month"], how="left")
    n_priced = d["Close"].notna().sum()
    d = d[d["Close"].notna() & (d["Close"] > 0)]

    # per-report KRW flow (signed qty × month-end price)
    d["krw_flow"] = d["net"] * d["Close"]

    # firm-month aggregation
    grp = d.groupby(["Ticker", "sig_month"]).agg(
        krw=("krw_flow", "sum"),
        net_qty=("net", "sum"),
        n_reports=("net", "size"),
        Size=("Size", "last"),
    ).reset_index()
    # keep only nonzero net events (직관: 임원 순매수/순매도 방향 신호. 0=무이벤트)
    grp = grp[grp["krw"] != 0].copy()
    grp["nflow"] = grp["krw"] / grp["Size"].replace(0, np.nan)

    # ── PIT: usable month = sig_month + PIT_LAG (month begin) ─────────────────
    sm = pd.to_datetime(grp["sig_month"], format="%Y-%m")
    um = sm + pd.offsets.MonthBegin(PIT_LAG)
    grp["usable_month"] = um.dt.strftime("%Y-%m")
    # Date passed to canonical screen = first day of usable month (holding-month begin)
    grp["Date"] = um.dt.strftime("%Y-%m-%d")  # already month-begin from MonthBegin

    out = grp[["Date", "Ticker", "krw", "nflow", "net_qty", "n_reports", "sig_month", "usable_month"]].copy()
    out = out.sort_values(["Date", "Ticker"]).reset_index(drop=True)

    outp = os.path.join(HARN, "data", "officer_netbuy_panel.parquet")
    out.to_parquet(outp, index=False)

    months = sorted(out["sig_month"].unique().tolist())
    # contiguity check
    mp = pd.PeriodIndex(months, freq="M")
    full = pd.period_range(mp.min(), mp.max(), freq="M")
    gaps = [str(p) for p in full if p not in set(mp)]
    # largest contiguous run
    present = sorted(set(mp))
    best_run = cur_run = 1
    run_start = best_start = present[0]
    for i in range(1, len(present)):
        if present[i] == present[i-1] + 1:
            cur_run += 1
            if cur_run > best_run:
                best_run, best_start = cur_run, run_start
        else:
            cur_run = 1
            run_start = present[i]
    best_end = best_start + (best_run - 1)

    meta = {
        "generated_utc": pd.Timestamp.utcnow().isoformat(),
        "source": "stage_artifacts/dart_parser_build/cache/monthly/*.parquet (원문파서 출력)",
        "pit_lag_months": PIT_LAG,
        "officer_only": OFFICER_ONLY,
        "filters": {
            "reporter_type": "officer" if OFFICER_ONLY else "ALL",
            "mechanical": "n_mechanical==0 (report-level exclusion of split/grant/rights/conversion)",
            "market": "n_discretionary>0 (>=1 장내매매 txn; 보통주 시장거래 근사)",
        },
        "counts": {
            "raw_trade_reports_ok": int(n_all),
            "after_price_notna": int(n_priced),
            "officer_reports": int(n_officer),
            "clean_reports(no_mech & disc>0)": int(n_clean),
            "firm_month_events(nonzero)": int(len(out)),
        },
        "coverage": {
            "n_signal_months": len(months),
            "sig_month_range": [months[0], months[-1]] if months else [],
            "gaps_within_range": gaps,
            "largest_contiguous_run_months": int(best_run),
            "largest_contiguous_run_range": [str(best_start), str(best_end)],
        },
        "signal_columns": {
            "krw": "Σ(net_change_qty × month-end Close) = net officer open-market KRW flow",
            "nflow": "krw / month-end mktcap (Size) — 규모정규화",
            "Date": "first-day-of usable_month (holding-month begin). sig(M) applied to M+PIT_LAG return.",
        },
        "pit_note": "rcept_dt(M) < first-day-of(usable_month=M+PIT_LAG) ALWAYS. no same-month. 'Date<anchor' NOT used.",
    }
    json.dump(meta, open(os.path.join(HARN, "reports", "signal_build_meta.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)

    print(f"[build] raw ok reports={n_all} -> officer={n_officer} -> clean(no-mech,disc)={n_clean} "
          f"-> firm-month events={len(out)}")
    print(f"[build] signal months={len(months)} range={meta['coverage']['sig_month_range']} "
          f"largest_contiguous_run={best_run}m {meta['coverage']['largest_contiguous_run_range']}")
    print(f"[build] gaps within range: {len(gaps)} months")
    print(f"[build] wrote {outp}")


if __name__ == "__main__":
    main()
