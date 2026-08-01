#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_materiality_panel.py — WT-D20260802_001 R2 / FQ-073 next_probe P1

R1 결함: HS4 산업 수출을 그 버킷에 속한 모든 기업에 **균등 배분**했다.
        수출 의존도 5%인 기업과 80%인 기업이 같은 신호를 받았고, 결과적으로 신호
        강도가 기업의 경제적 노출이 아니라 **버킷의 변동성**에 지배됐다.

본 스크립트는 그 균등 배분을 **경제적 크기로 재척도**하는 materiality 패널을 만든다.

── 정규화 선택과 기전 근거 ────────────────────────────────────────────────
기전(1차 pass-through): 기업 i 가 버킷 h 의 수출 흐름에서 얻는 수출매출은
      ExpRev_ih = Flow_h x share_ih ,  share_ih = (Rev_i w_ih) / Σ_j (Rev_j w_jh)
   (= 노출매출 비례배분. 버킷 안에서 누가 얼마나 그 흐름의 주인인지)
따라서 기업의 **수출 의존도**(= 매출 중 수출 노출분의 비중)는

      M_i = Σ_h ExpRev_ih / Rev_i = Σ_h w_ih x [ Flow_h x FX / Σ_j (Rev_j w_jh) ]
                                    └────────── R_h : 버킷 relevance ──────────┘

★핵심 성질 — Rev_i 가 소거된다. 즉 M 은 **scale-free 분수**이며 시총/매출에
  기계적으로 단조가 아니다. (만약 "버킷 안 매출점유율"을 그대로 가중치로 썼다면
  대형주로의 이동은 구성상 자명해져 cap-tier 판별이 순환논증이 됐을 것이다.
  그 arm 은 의도적으로 채택하지 않았다 — challenge_note R2 참조.)

M 의 경제적 독해:
  · R_h 高 = 그 버킷의 한국 수출액이, 그 버킷에 매핑된 상장사들의 매출 대비 크다
            = 그 상장사들이 실제로 그 수출의 주인이고 수출이 사업의 큰 몫이다.
  · R_h 低 = 흐름이 그 기업들 사업에 비해 사소하다 = **immaterial**. R1 이 균등
            배분으로 같은 신호를 주던 바로 그 5%-노출 케이스.
  · M > 1 = 매핑된 상장사 매출로 그 흐름을 설명할 수 없다(비상장·해외·오매핑).
            수출의존도는 정의상 <=1 이므로 AST 에서 CLIP(0,1) 로 경제적 상한 부과.

── PIT ────────────────────────────────────────────────────────────────────
  Flow_h    : data_ym M 까지의 TTM 수출합 (12M). avail = M+1 월 15일 (R1 패널 동일)
  Rev_j     : fundamental_dart.Factor_Date <= (데이터월 M 말) 인 최신 연간 매출
              (Factor_Date = 익년 3/31 = C4 준수). 데이터월 말 기준이므로
              avail_ts(M+1/15) 보다 항상 이르다 = 보수적.
  FX        : 데이터월 M 까지 TTM 월평균 KRW/USD (횡단면 공통 스칼라 — 랭킹 무영향,
              단위·CLIP 경계에만 관여)
  avail_ts  : M+1/15  (R1 export 패널과 동일 규약 — 두 STORED_SCORE 리프 정합)

vintage 정직 라벨: crosswalk = static_current (R1 과 동일한 C1/C3 노출. R2 는 이
  노출을 해소하지 않는다 — P3 는 본 라운드 범위 밖. gate_eligible=False 승계).
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
FUND = os.path.join(ROOT, ".cache/fundamental_dart.parquet")
FXP = os.path.join(ROOT, ".cache/ecos_krw_usd.parquet")

TTM = 12


def sha1_file(p):
    h = hashlib.sha1()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def month_end(ym):
    y, m = int(ym[:4]), int(ym[5:7])
    nxt = dt.date(y + 1, 1, 1) if m == 12 else dt.date(y, m + 1, 1)
    return nxt - dt.timedelta(days=1)


def avail_ts_of(ym):
    y, m = int(ym[:4]), int(ym[5:7])
    return dt.date(y + 1, 1, 15) if m == 12 else dt.date(y, m + 1, 15)


def main():
    # ── 1. HS4 TTM 수출흐름 ───────────────────────────────────────────────
    cust = pd.read_parquet(CUSTOMS, columns=["hs", "ym", "exp_usd"])
    cust = cust[cust.hs.astype(str).str.len() >= 6].copy()
    cust["hs4"] = cust.hs.astype(str).str[:4]
    cust["exp_usd"] = pd.to_numeric(cust.exp_usd, errors="coerce").fillna(0.0)
    hs4 = cust.groupby(["hs4", "ym"], as_index=False)["exp_usd"].sum()
    hs4 = hs4.sort_values(["hs4", "ym"])
    hs4["flow_ttm"] = (hs4.groupby("hs4")["exp_usd"]
                          .transform(lambda s: s.rolling(TTM, min_periods=TTM).sum()))
    hs4 = hs4.dropna(subset=["flow_ttm"])
    print(f"[mat] HS4 TTM: {len(hs4)}행 · hs4 {hs4.hs4.nunique()} · {hs4.ym.min()}~{hs4.ym.max()}")

    # ── 2. firm -> hs4 정규화 weight (R1 build_export_panel.py 와 동일 구성) ─
    xw = pd.read_parquet(XWALK)
    f = xw[xw["consume_ok_chapter"].astype(bool) & xw.hs_code.notna()].copy()
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
    fmap["weight"] = fmap.weight / fmap.groupby("Ticker")["weight"].transform("sum")
    print(f"[mat] firm-hs4 pairs {len(fmap)} · firms {fmap.Ticker.nunique()} · hs4 {fmap.hs4.nunique()}")

    # ── 3. PIT 연간매출 (Factor_Date = 익년 3/31) ────────────────────────
    fu = pd.read_parquet(FUND, columns=["Ticker", "bsns_year", "Factor_Date", "Revenue"])
    fu = fu[fu.Revenue.notna() & (fu.Revenue > 0)].copy()
    fu["Factor_Date"] = pd.to_datetime(fu.Factor_Date)
    fu = fu.sort_values(["Ticker", "Factor_Date"])

    # ── 4. FX TTM 월평균 ─────────────────────────────────────────────────
    fx = pd.read_parquet(FXP)
    fx["Date"] = pd.to_datetime(fx.Date)
    fx["ym"] = fx.Date.dt.strftime("%Y-%m")
    fxm = fx.groupby("ym", as_index=False)["KRW_USD"].mean().sort_values("ym")
    fxm["fx_ttm"] = fxm.KRW_USD.rolling(TTM, min_periods=TTM).mean()
    fxm = fxm.dropna(subset=["fx_ttm"])[["ym", "fx_ttm"]]

    # ── 5. 월별 materiality ──────────────────────────────────────────────
    yms = sorted(set(hs4.ym) & set(fxm.ym))
    yms = [y for y in yms if y >= "2015-12"]
    fx_map = dict(zip(fxm.ym, fxm.fx_ttm))
    flow_by_ym = {y: g.set_index("hs4")["flow_ttm"] for y, g in hs4.groupby("ym")}

    out, diag_rows = [], []
    for ym in yms:
        asof = pd.Timestamp(month_end(ym))
        rev = (fu[fu.Factor_Date <= asof].groupby("Ticker", as_index=False)
                 .tail(1)[["Ticker", "Revenue", "bsns_year"]])
        if not len(rev):
            continue
        m = fmap.merge(rev, on="Ticker", how="left")
        m["rev_w"] = m.Revenue.fillna(0.0) * m.weight            # 노출매출 (KRW)
        denom = m.groupby("hs4", as_index=False)["rev_w"].sum().rename(
            columns={"rev_w": "denom_krw"})
        fl = flow_by_ym.get(ym)
        if fl is None:
            continue
        denom["flow_ttm_usd"] = denom.hs4.map(fl)
        denom = denom[denom.flow_ttm_usd.notna()]
        denom["R_h"] = np.where(denom.denom_krw > 0,
                                denom.flow_ttm_usd * fx_map[ym] / denom.denom_krw, np.nan)
        mm = m.merge(denom[["hs4", "R_h", "denom_krw", "flow_ttm_usd"]], on="hs4", how="inner")
        mm = mm[mm.R_h.notna()]
        # credibility 보정: R_h > 1 = 매핑 상장사 매출로 흐름을 설명 못함(비상장·해외·오매핑)
        #   → 그 버킷 신호의 firm 귀속 신뢰도가 낮다. min(R, 1/R) 은 R=1(흐름과 노출매출이
        #   동급 = 매핑이 흐름을 설명)에서 최대, 양방향(사소함 / 설명불가)으로 감쇠.
        mm["R_cred"] = np.minimum(mm.R_h, np.where(mm.R_h > 0, 1.0 / mm.R_h, 0.0))
        agg = mm.groupby("Ticker", as_index=False).apply(
            lambda g: pd.Series({
                "value": float((g.weight * g.R_h).sum()),
                "value_cred": float((g.weight * g.R_cred).sum()),
                "wcov": float(g.weight.sum()),          # relevance 산출된 버킷 weight 커버리지
                "n_hs": int(len(g)),
            }), include_groups=False)
        agg = agg[agg.wcov > 0]
        agg["Date"] = asof
        agg["avail_ts"] = pd.Timestamp(avail_ts_of(ym))
        out.append(agg[["Date", "Ticker", "value", "value_cred", "wcov", "n_hs"]].assign(
            avail_ts=pd.Timestamp(avail_ts_of(ym))))
        diag_rows.append({"ym": ym, "n_firms": int(len(agg)),
                          "n_rev_firms": int(rev.Ticker.isin(fmap.Ticker).sum()),
                          "M_med": float(agg.value.median()),
                          "M_p90": float(agg.value.quantile(0.90)),
                          "share_gt1": float((agg.value > 1).mean())})

    panel = pd.concat(out, ignore_index=True)
    panel = panel[["Date", "Ticker", "value", "value_cred", "avail_ts", "wcov", "n_hs"]].sort_values(
        ["Ticker", "Date"]).reset_index(drop=True)
    bad = (panel.avail_ts < panel.Date).sum()
    if bad:
        sys.exit(f"[mat] avail_ts < Date {bad}행 — AST panel_contract 위반")

    out_p = os.path.join(OUT, "fq073_export_materiality.parquet")
    panel.to_parquet(out_p, index=False)

    dg = pd.DataFrame(diag_rows)
    meta = {
        "panel": os.path.basename(out_p),
        "generated_at": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generator_code_path": "stage_artifacts/WT_D20260802_001/build_materiality_panel.py",
        "rows": int(len(panel)), "n_firms": int(panel.Ticker.nunique()),
        "n_months": int(panel.Date.nunique()),
        "date_min": str(panel.Date.min().date()), "date_max": str(panel.Date.max().date()),
        "value_semantics": "M_i = Σ_h w_ih x [Flow_h(TTM,USD) x FX / Σ_j (Rev_j x w_jh)] "
                           "= 추정 수출 의존도(매출 대비 수출노출 비중). scale-free 분수 — "
                           "Rev_i 소거로 시총 단조 아님. 상한 1 부과는 AST CLIP 담당.",
        "avail_rule": "avail_ts = data_ym(M) + 1개월의 15일 (R1 export 패널과 동일)",
        "revenue_pit": "fundamental_dart.Revenue, Factor_Date <= 데이터월 말 (Factor_Date=익년 3/31, C4)",
        "distribution": {
            "M_median_overall": float(panel.value.median()),
            "M_p10": float(panel.value.quantile(0.10)),
            "M_p90": float(panel.value.quantile(0.90)),
            "share_gt_1": float((panel.value > 1).mean()),
            "share_lt_0p05": float((panel.value < 0.05).mean()),
        },
        "monthly_diag_head": dg.head(3).to_dict("records"),
        "monthly_diag_tail": dg.tail(3).to_dict("records"),
        "sources": {
            "customs_hs_monthly.parquet": {"sha1": sha1_file(CUSTOMS),
                                           "vintage_basis": "revised_asof_pull"},
            "firm_hs_crosswalk.parquet": {"sha1": sha1_file(XWALK),
                                          "map_vintage_mode": "static_current"},
            "fundamental_dart.parquet": {"sha1": sha1_file(FUND),
                                         "pit": "Factor_Date=익년 3/31"},
            "ecos_krw_usd.parquet": {"sha1": sha1_file(FXP)},
        },
        "known_pit_exposures": ["C1_C3_static_business_mix", "C6_survivorship_current_listed_pool",
                                "customs_revised_vintage"],
    }
    meta["store_build_hash"] = hashlib.sha1(
        json.dumps({k: meta[k] for k in ("rows", "n_firms", "n_months", "date_min",
                                         "date_max", "sources")},
                   sort_keys=True, default=str).encode()).hexdigest()
    with open(os.path.join(OUT, "fq073_export_materiality_meta.json"), "w",
              encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=2)

    print(f"[mat] -> {out_p}")
    print(f"[mat] {len(panel)}행 · firms {panel.Ticker.nunique()} · months {panel.Date.nunique()} · "
          f"{meta['date_min']}~{meta['date_max']}")
    print(f"[mat] M 분포: p10={meta['distribution']['M_p10']:.4f} "
          f"med={meta['distribution']['M_median_overall']:.4f} "
          f"p90={meta['distribution']['M_p90']:.4f} · >1 비중={meta['distribution']['share_gt_1']:.3f} "
          f"· <0.05 비중={meta['distribution']['share_lt_0p05']:.3f}")
    print(f"[mat] store_build_hash={meta['store_build_hash'][:12]}")


if __name__ == "__main__":
    main()
