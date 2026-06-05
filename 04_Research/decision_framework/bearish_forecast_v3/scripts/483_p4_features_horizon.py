"""
483_p4_features_horizon.py — P4 (22d horizon) Features Panel Builder

도훈 mandate 2026-05-27 (P4 정식 학습 Stage 1):
- 기존 12 features + horizon-aware 6 + FRED 4 + KR macro 4 = 26 features
- PIT C11 강제: 모든 macro lag 1d (.shift(1))
- forward 22d label (ret_h) — Cycle 50 incident 재발 방지 (validate_label_direction 의무)

Features:
  [기존 12, 1d 기준]
    log_ret_lag_{1,2,5,22}, rv_{5,22,60}d, mean_{5,22,60}d, rv_22d_z, drawdown_z
  [horizon-aware 6, 22d horizon 적합]
    rv_120d, rv_252d, mean_120d, mean_252d, momentum_22_60_slope, drawdown_60d
  [FRED macro 4, C11 lag 1d]
    vix_lag1, vix_60d_z, term_spread_lag1 (T10Y2Y), dgs10_lag1, nfci_lag1 (weekly ffill)
  [KR macro 4, C11 lag 1d]
    kr_gov10y_lag1, kr_term_spread_lag1, kr_credit_spread_lag1, krwusd_vol_60d_z

CLI:
    python scripts/483_p4_features_horizon.py \
        --output 04_Research/.../outputs/p4_features_panel.parquet \
        [--horizon 22]
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
from pathlib import Path
from datetime import datetime

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent


# ─── Constants ────────────────────────────────────────────────────────────────
# h=21 (KR trading days monthly convention) — bear_date_audit.R H=21 hardcoded 호환
# + PG2 monthly rebalance frequency match (도훈 mandate 2026-05-27)
HORIZON_DEFAULT = 21
PERCENT_SCALE = True
DATE_START = "2001-01-03"
EPS = 1e-8

FRED_PARQUET = PROJECT_ROOT / ".cache" / "fred_macro.parquet"
BM_PARQUET   = PROJECT_ROOT / ".cache" / "benchmark.parquet"
ECOS_BOND    = PROJECT_ROOT / ".cache" / "ecos_bond_rates.parquet"
ECOS_KRWUSD  = PROJECT_ROOT / ".cache" / "ecos_krw_usd.parquet"

# ─── Helper ───────────────────────────────────────────────────────────────────
def expanding_z(s: pd.Series, min_periods: int = 60) -> pd.Series:
    mu = s.expanding(min_periods=min_periods).mean()
    sd = s.expanding(min_periods=min_periods).std() + EPS
    return (s - mu) / sd


def load_fred_series_wide(series_ids: list[str]) -> pd.DataFrame:
    """FRED long → wide pivot for required Series_IDs. Returns Date + cols."""
    fred = pd.read_parquet(FRED_PARQUET)
    fred['Date'] = pd.to_datetime(fred['Date'])
    sub = fred[fred['Series_ID'].isin(series_ids)][['Date', 'Series_ID', 'Value']]
    wide = sub.pivot(index='Date', columns='Series_ID', values='Value').reset_index()
    wide = wide.sort_values('Date').reset_index(drop=True)
    return wide


def load_kr_macro() -> pd.DataFrame:
    """ECOS bond_rates → wide pivot + krw_usd."""
    br = pd.read_parquet(ECOS_BOND)
    br['Date'] = pd.to_datetime(br['Date'])
    kr_series = ['KR_Gov10Y', 'KR_Gov3Y', 'KR_CorpBBB', 'KR_CorpAA']
    sub = br[br['Series'].isin(kr_series)][['Date', 'Series', 'Value']]
    kr_wide = sub.pivot(index='Date', columns='Series', values='Value').reset_index()
    kr_wide = kr_wide.sort_values('Date').reset_index(drop=True)

    krw = pd.read_parquet(ECOS_KRWUSD)
    krw['Date'] = pd.to_datetime(krw['Date'])
    krw = krw[['Date', 'KRW_USD']].sort_values('Date').reset_index(drop=True)
    return kr_wide.merge(krw, on='Date', how='outer').sort_values('Date').reset_index(drop=True)


# ─── Main feature builder ─────────────────────────────────────────────────────
def build_p4_features(horizon: int = HORIZON_DEFAULT,
                       date_start: str = DATE_START,
                       date_end: str | None = None) -> tuple[pd.DataFrame, list[str]]:
    """Build P4 horizon-aware + macro features panel.

    Returns (df_full, feature_cols).
    df_full schema: Date, BM_Close, ret_h (forward log return), <features...>
    """
    # ── 1. Benchmark + base 12 features (existing 482 logic) ──────────────────
    bm = pd.read_parquet(BM_PARQUET)
    bm['Date'] = pd.to_datetime(bm['Date'])
    bm = bm.rename(columns={'BM_Close': 'Close'}).sort_values('Date').reset_index(drop=True)
    bm['log_ret'] = np.log(bm['Close']).diff()

    for lag in [1, 2, 5, 22]:
        bm[f'log_ret_lag_{lag}'] = bm['log_ret'].shift(lag)

    for w in [5, 22, 60, 120, 252]:
        bm[f'rv_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()
        bm[f'mean_{w}d'] = bm['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()

    # drawdown (cum) and 60d rolling drawdown
    cum_max = bm['Close'].cummax()
    bm['drawdown'] = (bm['Close'] - cum_max) / (cum_max + EPS)
    rolling_max_60 = bm['Close'].rolling(60, min_periods=20).max()
    bm['drawdown_60d'] = (bm['Close'] - rolling_max_60) / (rolling_max_60 + EPS)

    bm['rv_22d_z']   = expanding_z(bm['rv_22d'])
    bm['drawdown_z'] = expanding_z(bm['drawdown'])
    bm['momentum_22_60_slope'] = (bm['mean_22d'] - bm['mean_60d']) / (bm['rv_22d'] + EPS)

    # forward h-day return label (ret_h) — simple return for audit compatibility
    # (bear_date_audit / validate_label_direction use simple return: BM[t+H]/BM[t] - 1)
    bm['ret_h'] = bm['Close'].shift(-horizon) / bm['Close'] - 1.0
    # Also keep log return for P3 baseline comparison
    bm['ret_h_log'] = np.log(bm['Close'].shift(-horizon) / bm['Close'])

    # ── 2. FRED macro features (PIT C11 lag 1d 의무) ──────────────────────────
    fred_w = load_fred_series_wide(['VIXCLS', 'T10Y2Y', 'DGS10', 'NFCI'])
    # NFCI weekly → forward fill within 5 calendar days then merge
    fred_w['NFCI'] = fred_w['NFCI'].ffill(limit=7)
    fred_w['vix_lag1']          = fred_w['VIXCLS'].shift(1)
    fred_w['term_spread_lag1']  = fred_w['T10Y2Y'].shift(1)
    fred_w['dgs10_lag1']        = fred_w['DGS10'].shift(1)
    fred_w['nfci_lag1']         = fred_w['NFCI'].shift(1)
    fred_w['vix_60d_z']         = expanding_z(fred_w['vix_lag1'])
    fred_feats = ['vix_lag1', 'vix_60d_z', 'term_spread_lag1', 'dgs10_lag1', 'nfci_lag1']

    # ── 3. KR macro features ──────────────────────────────────────────────────
    kr = load_kr_macro()
    # ffill BBB/AA spreads (KR bond rates daily-ish)
    for c in ['KR_Gov10Y', 'KR_Gov3Y', 'KR_CorpBBB', 'KR_CorpAA', 'KRW_USD']:
        if c in kr.columns:
            kr[c] = kr[c].ffill(limit=7)
    kr['kr_gov10y_lag1']        = kr['KR_Gov10Y'].shift(1)
    kr['kr_term_spread_lag1']   = (kr['KR_Gov10Y'] - kr['KR_Gov3Y']).shift(1)
    kr['kr_credit_spread_lag1'] = (kr['KR_CorpBBB'] - kr['KR_Gov10Y']).shift(1)
    # KRW_USD daily log return → 60d rolling std → expanding z
    krw_ret = np.log(kr['KRW_USD']).diff()
    krwusd_vol = krw_ret.rolling(60, min_periods=20).std()
    kr['krwusd_vol_60d_z'] = expanding_z(krwusd_vol)
    kr_feats = ['kr_gov10y_lag1', 'kr_term_spread_lag1',
                'kr_credit_spread_lag1', 'krwusd_vol_60d_z']

    # ── 4. Merge (Date alignment) ─────────────────────────────────────────────
    out = bm.merge(fred_w[['Date'] + fred_feats], on='Date', how='left')
    out = out.merge(kr[['Date'] + kr_feats], on='Date', how='left')

    # ── 5. Feature column list ────────────────────────────────────────────────
    feature_cols = (
        [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] +
        [f'rv_{w}d' for w in [5, 22, 60]] +
        [f'mean_{w}d' for w in [5, 22, 60]] +
        ['rv_22d_z', 'drawdown_z'] +
        ['rv_120d', 'rv_252d', 'mean_120d', 'mean_252d',
         'momentum_22_60_slope', 'drawdown_60d'] +
        fred_feats +
        kr_feats
    )
    assert len(feature_cols) == 27, f"feature count mismatch: {len(feature_cols)}"

    # ── 6. Date range filter ──────────────────────────────────────────────────
    date_start_dt = pd.to_datetime(date_start)
    date_end_dt = pd.to_datetime(date_end) if date_end else out['Date'].max()
    out = out[(out['Date'] >= date_start_dt) & (out['Date'] <= date_end_dt)].reset_index(drop=True)

    # ── 7. Drop NaN rows (features + ret_h) ───────────────────────────────────
    before = len(out)
    out = out.dropna(subset=feature_cols + ['ret_h']).reset_index(drop=True)
    after = len(out)
    print(f'[P4 features] dropped {before - after} NaN rows ({before} → {after})')

    # ── 8. Percent scale (for LASSO numerical stability) ──────────────────────
    # Note: ret_h, ret_h_log are kept in raw (no scale) for audit compatibility.
    # Scaled versions ret_h_pct / ret_h_log_pct created for training use.
    if PERCENT_SCALE:
        out['ret_h_pct'] = out['ret_h'] * 100.0
        out['ret_h_log_pct'] = out['ret_h_log'] * 100.0
        pct_cols = ['log_ret'] + [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] + \
                   [f'rv_{w}d' for w in [5, 22, 60, 120, 252]] + \
                   [f'mean_{w}d' for w in [5, 22, 60, 120, 252]] + \
                   ['drawdown', 'drawdown_60d']
        for c in pct_cols:
            if c in out.columns:
                out[c] = out[c] * 100.0

    # ── 9. Rename Close → BM_Close (for validate_label_direction/bear_audit) ──
    out = out.rename(columns={'Close': 'BM_Close'})
    return out, feature_cols


# ─── Main entry ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=str, required=True,
                        help='Output parquet path')
    parser.add_argument('--horizon', type=int, default=HORIZON_DEFAULT)
    parser.add_argument('--date_start', type=str, default=DATE_START)
    parser.add_argument('--date_end', type=str, default=None)
    parser.add_argument('--skip_validation', action='store_true',
                        help='Skip PIT label direction + bear_date_audit (default: run)')
    args = parser.parse_args()

    out_path = Path(args.output)
    if not out_path.is_absolute():
        out_path = PROJECT_ROOT / out_path
    out_path.parent.mkdir(parents=True, exist_ok=True)

    print(f'[P4 features] horizon={args.horizon} date_start={args.date_start} date_end={args.date_end or "latest"}')
    df, feature_cols = build_p4_features(
        horizon=args.horizon,
        date_start=args.date_start,
        date_end=args.date_end,
    )
    print(f'[P4 features] final shape: {df.shape}  features={len(feature_cols)}')
    print(f'[P4 features] Date range: {df["Date"].min().date()} ~ {df["Date"].max().date()}')

    df.to_parquet(out_path)
    print(f'[P4 features] saved → {out_path}')

    meta_path = out_path.with_suffix('.meta.json')
    meta = {
        'horizon': args.horizon,
        'date_start': args.date_start,
        'date_end': str(df['Date'].max().date()),
        'n_rows': len(df),
        'n_features': len(feature_cols),
        'feature_cols': feature_cols,
        'built_at': datetime.now().isoformat(),
    }
    meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False))
    print(f'[P4 features] meta → {meta_path}')

    # ── 10. PIT validation (Cycle 51 의무) ────────────────────────────────────
    if not args.skip_validation:
        print('\n[P4 features] === PIT validate_label_direction (forward h=22) ===')
        # bm_df는 .cache/benchmark.parquet 그대로 사용
        validation_cmd = [
            "Rscript", "--no-save", "-e",
            f"""
            setwd("{PROJECT_ROOT}")
            source("02_Infrastructure/validation/pit_enforcement.R")
            suppressPackageStartupMessages({{
              library(arrow); library(data.table)
            }})
            td <- as.data.table(read_parquet("{out_path}"))
            bd <- as.data.table(read_parquet("{BM_PARQUET}"))
            res <- validate_label_direction(
              target_df = td, target_col = "ret_h",
              bm_df = bd, bm_col = "BM_Close",
              expected_direction = "forward",
              horizon = {args.horizon}L
            )
            cat(sprintf("[validate_label_direction] pass=%s fwd_rate=%.4f bwd_rate=%.4f\\n",
                        res$pass, res$agreement_rate_forward, res$agreement_rate_backward))
            cat(sprintf("[COVID 2020-02-19] fwd_pass=%s fwd_actual=%.4f\\n",
                        res$covid_assertion$fwd_pass, res$covid_assertion$forward_actual))
            if (!res$pass) quit(status = 1)
            """,
        ]
        result = subprocess.run(validation_cmd, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            print(f'[ERROR] validate_label_direction FAILED:\n{result.stderr}')
            sys.exit(1)

        print('\n[P4 features] === bear_date_audit (4 known dates) ===')
        # bear_date_audit requires Date class (not POSIXt). pandas → arrow saves as
        # datetime64[ns] which R reads as POSIXt → comparison fails. Build a
        # Date-only temp panel first.
        bear_cmd = [
            "Rscript", "--no-save", "-e",
            f"""
            setwd("{PROJECT_ROOT}")
            source("02_Infrastructure/sanity_checks/bear_date_audit.R")
            suppressPackageStartupMessages({{
              library(arrow); library(data.table)
            }})
            td <- as.data.table(read_parquet("{out_path}"))
            td[, Date := as.Date(Date)]
            temp_path <- tempfile(fileext = ".parquet")
            write_parquet(td[, .(Date, BM_Close, ret_h)], temp_path)
            bd <- as.data.table(read_parquet("{BM_PARQUET}"))
            bd[, Date := as.Date(Date)]
            temp_bm <- tempfile(fileext = ".parquet")
            write_parquet(bd[, .(Date, BM_Close)], temp_bm)
            res <- audit_bear_dates(temp_path, temp_bm)
            cat(sprintf("[bear_audit] pass=%s n_pass=%d n_fail=%d n_skip=%d\\n",
                        res$pass, res$n_pass, res$n_fail, res$n_skip))
            if (!isTRUE(res$pass)) quit(status = 1)
            """,
        ]
        result = subprocess.run(bear_cmd, capture_output=True, text=True)
        print(result.stdout)
        if result.returncode != 0:
            print(f'[ERROR] bear_date_audit FAILED:\n{result.stderr}')
            sys.exit(1)

        print('\n[P4 features] ✅ All validations PASS')


if __name__ == '__main__':
    main()
