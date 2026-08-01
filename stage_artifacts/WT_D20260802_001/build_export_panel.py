#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_export_panel.py — WT-D20260802_001 / FQ-073
관세청 HS 월별 수출(USD) x DART 사업부문-파생 firm-HS 크로스워크
  -> firm-month 수출노출 패널 (AST v1.1 STORED_SCORE 리프 소비용)

★이 스크립트는 '원시 노출값'만 만든다. YoY/서프라이즈/횡단면 표준화는 전부
  AST(02_Infrastructure/ast/ast_compile.R)가 계산한다 — 컴파일러-소유 AS_OF 조인
  (SOT §4-2, 수기 merge 금지). 여기서 신호를 만들면 AST 계층을 우회하는 것.

PIT (PIT_plan_fq073.md §3):
  data_ym = M         수출 발생월
  avail_ts = M+1/15   1차 현행화(확정 lane) 완료일 -> 이 시각부터 소비 가능
  score_date          = M+1 거래 월말  (avail_ts <= score_date, 버퍼 14~17일)
  holding month       = M+2            (compiler final AS_OF가 강제)

vintage 정직 라벨 (PIT_plan_fq073.md §2):
  customs 값 = revised_asof_pull (API에 vintage 파라미터 없음 -> first-release 소급복원 불가)
  crosswalk  = static_current     (2024-2025 사업보고서 1 vintage를 전 역사에 귀속 = C1/C3 노출)
  -> 두 라벨 모두 패널 메타에 기록되고 alpha_package challenge_flags로 승계된다.
"""
import os, sys, json, hashlib, datetime as dt
import pandas as pd
import numpy as np

ROOT = os.environ.get("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
FQ = os.path.join(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold/fq073")
OUT = os.path.join(ROOT, "stage_artifacts/WT_D20260802_001")
os.makedirs(OUT, exist_ok=True)

CUSTOMS = os.path.join(FQ, "customs_hs_monthly.parquet")
XWALK = os.path.join(FQ, "firm_hs_crosswalk.parquet")

# 소비 게이트: confidence A/B (consume_ok_chapter). strict arm = consume_ok_hs4
POOL = os.environ.get("FQ073_POOL", "chapter")   # chapter | hs4strict


def sha1_file(p, cap=None):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
            if cap and h.digest_size and f.tell() > cap:
                break
    return h.hexdigest()


def month_end(ym):
    y, m = int(ym[:4]), int(ym[5:7])
    if m == 12:
        nxt = dt.date(y + 1, 1, 1)
    else:
        nxt = dt.date(y, m + 1, 1)
    return nxt - dt.timedelta(days=1)


def avail_ts_of(ym):
    """PIT_plan §1-c: 1차 현행화 = M+1월 15일경 -> 확정 lane 가용시각."""
    y, m = int(ym[:4]), int(ym[5:7])
    if m == 12:
        return dt.date(y + 1, 1, 15)
    return dt.date(y, m + 1, 15)


def main():
    cust = pd.read_parquet(CUSTOMS)
    xw = pd.read_parquet(XWALK)

    # ── 1. HS4 월별 수출 집계 (10자리 -> 앞 4자리) ─────────────────────────
    cust = cust[cust.hs.astype(str).str.len() >= 6].copy()
    cust["hs4"] = cust.hs.astype(str).str[:4]
    cust["exp_usd"] = pd.to_numeric(cust.exp_usd, errors="coerce").fillna(0.0)
    hs4 = cust.groupby(["hs4", "ym"], as_index=False)["exp_usd"].sum()
    print(f"[panel] HS4 x month: {len(hs4)}행 · hs4 {hs4.hs4.nunique()} · "
          f"{hs4.ym.min()}~{hs4.ym.max()} ({hs4.ym.nunique()}월)")

    # ── 2. firm -> hs4 weight (primary + secondary) long map ──────────────
    gate = "consume_ok_hs4" if POOL == "hs4strict" else "consume_ok_chapter"
    f = xw[xw[gate].astype(bool) & xw.hs_code.notna()].copy()
    rows = []
    for _, r in f.iterrows():
        wp = r.weight_heuristic
        wp = 1.0 if (wp is None or not np.isfinite(wp)) else float(wp)
        rows.append((r.Ticker, str(r.hs_code), wp))
        if pd.notna(r.hs4_secondary):
            ws = r.weight_secondary_heuristic
            if ws is not None and np.isfinite(ws) and ws > 0:
                rows.append((r.Ticker, str(r.hs4_secondary), float(ws)))
    fmap = pd.DataFrame(rows, columns=["Ticker", "hs4", "weight"])
    fmap = fmap.groupby(["Ticker", "hs4"], as_index=False)["weight"].sum()
    # 종목별 weight 정규화 (Σw = 1) -> 값 스케일이 매핑 개수에 의존하지 않게
    fmap["weight"] = fmap.weight / fmap.groupby("Ticker")["weight"].transform("sum")
    print(f"[panel] gate={gate}: firms {fmap.Ticker.nunique()} · "
          f"firm-hs4 pairs {len(fmap)} · distinct hs4 {fmap.hs4.nunique()}")

    # ── 3. firm-month 수출노출 = Σ_h w_ih · exp_usd_hm ────────────────────
    j = fmap.merge(hs4, on="hs4", how="inner")
    if not len(j):
        sys.exit("[panel] firm x HS4 x month 조인 0행 — hs4 자릿수 정합 확인")
    j["contrib"] = j.weight * j.exp_usd
    panel = j.groupby(["Ticker", "ym"], as_index=False).agg(
        value=("contrib", "sum"), n_hs=("hs4", "nunique"))

    panel["Date"] = panel.ym.map(month_end)
    panel["avail_ts"] = panel.ym.map(avail_ts_of)
    panel["Date"] = pd.to_datetime(panel.Date)
    panel["avail_ts"] = pd.to_datetime(panel.avail_ts)

    # 불변식: avail_ts >= Date (AST panel_contract)
    bad = (panel.avail_ts < panel.Date).sum()
    if bad:
        sys.exit(f"[panel] avail_ts < Date {bad}행 — AST panel_contract 위반")

    panel = panel[["Date", "Ticker", "value", "avail_ts", "n_hs"]].sort_values(
        ["Ticker", "Date"]).reset_index(drop=True)

    tag = "strict" if POOL == "hs4strict" else "chapter"
    out_p = os.path.join(OUT, f"fq073_export_exposure_{tag}.parquet")
    panel.to_parquet(out_p, index=False)

    meta = {
        "panel": os.path.basename(out_p),
        "generated_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generator_code_path": "stage_artifacts/WT_D20260802_001/build_export_panel.py",
        "rows": int(len(panel)),
        "n_firms": int(panel.Ticker.nunique()),
        "n_months": int(panel.Date.nunique()),
        "date_min": str(panel.Date.min().date()),
        "date_max": str(panel.Date.max().date()),
        "gate": gate,
        "value_semantics": "firm-month 수출노출 USD = Σ_h normalized_weight(i,h) x HS4 월수출액. "
                           "raw level — YoY/서프라이즈/표준화는 AST가 수행.",
        "avail_rule": "avail_ts = data_ym(M) + 1개월의 15일 (PIT_plan_fq073 §1-c 1차 현행화)",
        "sources": {
            "customs_hs_monthly.parquet": {
                "sha1": sha1_file(CUSTOMS),
                "vintage_basis": "revised_asof_pull",
                "caveat": "API에 vintage 파라미터 없음 — first-release 소급 복원 불가. "
                          "개정이 무기한 반복되므로 역사 구간은 개정판 기반(원천 성질)."},
            "firm_hs_crosswalk.parquet": {
                "sha1": sha1_file(XWALK),
                "map_vintage_mode": "static_current",
                "caveat": "2024-04~2025-11 사업보고서 1 vintage를 전 역사에 귀속 = C1/C3 "
                          "사업구성 look-ahead. gate_eligible=False (원 크로스워크 자체 라벨)."},
        },
        "known_pit_exposures": ["C1_C3_static_business_mix", "C6_survivorship_current_listed_pool",
                                "customs_revised_vintage"],
    }
    meta["store_build_hash"] = hashlib.sha1(
        json.dumps({k: meta[k] for k in ("rows", "n_firms", "n_months", "date_min",
                                         "date_max", "gate", "sources")},
                   sort_keys=True, default=str).encode()).hexdigest()
    with open(os.path.join(OUT, f"fq073_export_exposure_{tag}_meta.json"), "w",
              encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)

    print(f"[panel] -> {out_p}")
    print(f"[panel] {len(panel)}행 · firms {panel.Ticker.nunique()} · "
          f"months {panel.Date.nunique()} · {meta['date_min']}~{meta['date_max']}")
    print(f"[panel] store_build_hash={meta['store_build_hash'][:12]}")


if __name__ == "__main__":
    main()
