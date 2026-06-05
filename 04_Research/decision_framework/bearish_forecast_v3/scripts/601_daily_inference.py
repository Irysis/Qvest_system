"""
601_daily_inference.py — P2/P3 daily forecast pipeline

도훈 mandate 2026-05-26: 매일 cron에서 호출 → 최신 데이터로 1일 forecast 생성.

Pipeline:
1. .cache/benchmark.parquet에서 latest KOSPI 200 시계열 load
2. 12 features 계산 (P2/P3와 동일 schema)
3. LASSO Quantile (최근 N년 train) fit + 오늘 features inference → 11 quantile
4. Hansen Skewed-t fit → 4 params
5. VaR / ES / P(폭락) closed-form derive
6. predictions.parquet에 1행 append (덮어쓰기 아닌 update)

CLI:
  python scripts/601_daily_inference.py [--model P2|P3] [--asof YYYY-MM-DD]
"""
from __future__ import annotations
import argparse
import importlib.util
import json
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
sys.path.insert(0, str(ROOT))


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, p)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LQM = _load("a1_lasso_quantile", str(ROOT / "03_models" / "a1_lasso_quantile.py"))
P472 = _load("p1_patch_v2", str(ROOT / "scripts" / "472_p1_patch_v2.py"))


P_TAUS = (0.01, 0.025, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.975, 0.99)


def load_model(model_name):
    if model_name == 'P2':
        return _load("hsk_p2", str(ROOT / "03_models" / "p1_hansen_skewt.py"))
    elif model_name == 'P3':
        return _load("hsk_p3", str(ROOT / "03_models" / "p3_hansen_skewt_bounded.py"))
    raise ValueError(f"Unknown model: {model_name}")


def daily_inference(model_name='P2', asof=None, train_lookback_years=8, alpha_l1=0.001, percent_scale=True):
    """One-day inference: latest benchmark.parquet → today's forecast row."""
    HSK = load_model(model_name)

    # ─── 1. Load benchmark + build features ───────────────────────────
    bm_path = PROJECT_ROOT / ".cache" / "benchmark.parquet"
    cfg = {
        'data': {
            'bm_path': '.cache/benchmark.parquet',
            'date_start': '2001-01-03',
            'date_end': asof or '2099-12-31',
            'percent_scale': percent_scale,
        }
    }
    df, feature_cols = P472.load_data(cfg)
    df['Date'] = pd.to_datetime(df['Date'])

    # P472.load_data drops last row due to ret_fwd dropna; for prediction we don't need ret_fwd.
    # Re-build features on raw benchmark for asof_dt if missing.
    if asof is not None:
        asof_dt = pd.to_datetime(asof)
        if asof_dt not in df['Date'].values:
            # rebuild features-only from raw benchmark (no ret_fwd requirement)
            raw = pd.read_parquet(bm_path)
            raw['Date'] = pd.to_datetime(raw['Date'])
            raw = raw.rename(columns={'BM_Close': 'Close'}).sort_values('Date').reset_index(drop=True)
            raw['log_ret'] = np.log(raw['Close']).diff()
            for lag in [1, 2, 5, 22]:
                raw[f'log_ret_lag_{lag}'] = raw['log_ret'].shift(lag)
            for w in [5, 22, 60]:
                raw[f'rv_{w}d'] = raw['log_ret'].rolling(w, min_periods=max(3, w // 2)).std()
                raw[f'mean_{w}d'] = raw['log_ret'].rolling(w, min_periods=max(3, w // 2)).mean()
            eps = 1e-8
            cum_max = raw['Close'].cummax()
            raw['drawdown'] = (raw['Close'] - cum_max) / (cum_max + eps)
            def expanding_z(s, min_periods=60):
                mu = s.expanding(min_periods=min_periods).mean()
                sd = s.expanding(min_periods=min_periods).std() + eps
                return (s - mu) / sd
            raw['rv_22d_z'] = expanding_z(raw['rv_22d'])
            raw['drawdown_z'] = expanding_z(raw['drawdown'])
            raw = raw.dropna(subset=feature_cols).reset_index(drop=True)
            if percent_scale:
                for c in ['log_ret'] + [f'log_ret_lag_{l}' for l in [1, 2, 5, 22]] + \
                         [f'rv_{w}d' for w in [5, 22, 60]] + [f'mean_{w}d' for w in [5, 22, 60]] + ['drawdown']:
                    if c in raw.columns:
                        raw[c] = raw[c] * 100.0
            asof_row = raw[raw['Date'] == asof_dt]
            if len(asof_row) == 0:
                raise ValueError(f"No data for asof={asof_dt.date()} (raw too)")
            print(f"[daily_inference] forecast-only mode (ret_fwd N/A)")
        else:
            asof_row = df[df['Date'] == asof_dt]
    else:
        asof_dt = df['Date'].max()
        asof_row = df[df['Date'] == asof_dt]
    if len(asof_row) == 0:
        raise ValueError(f"No data for asof={asof_dt.date()}")

    print(f"[daily_inference] model={model_name} asof={asof_dt.date()}")

    # ─── 3. Train on lookback window (PIT: only past) ─────────────────
    train_end = asof_dt - pd.Timedelta(days=21)  # 21d embargo
    train_start = train_end - pd.DateOffset(years=train_lookback_years)
    train_df = df[(df['Date'] >= train_start) & (df['Date'] <= train_end)].copy()
    print(f"  train: {train_df['Date'].min().date()} ~ {train_df['Date'].max().date()}  n={len(train_df)}")

    if len(train_df) < 1008:
        raise RuntimeError(f"Train set too small (n={len(train_df)}). Need >=1008.")

    X_tr = train_df[feature_cols].values.astype(np.float64)
    y_tr = train_df['ret_fwd'].values.astype(np.float64)
    X_pred = asof_row[feature_cols].values.astype(np.float64)

    # ─── 4. LASSO Quantile fit + predict ──────────────────────────────
    print(f"  LASSO Quantile fit (11 taus, alpha={alpha_l1})...")
    model = LQM.LassoQuantileGaR(taus=P_TAUS, alpha=alpha_l1, standardize=True)
    model.fit(X_tr, y_tr, feature_names=feature_cols)
    Q_pred = model.predict_all_quantiles(X_pred, fix_crossing=True)  # (1, 11)
    print(f"  11 quantile estimates: {np.round(Q_pred[0], 3).tolist()}")

    # ─── 5. Hansen Skewed-t fit ───────────────────────────────────────
    taus_np = np.array(P_TAUS)
    sst = HSK.derive_metrics_per_obs(Q_pred, taus_np)

    # ─── 6. Build output row ──────────────────────────────────────────
    out_row = {
        'Date': asof_dt,  # batch result와 호환되는 schema
        'asof_date': asof_dt.strftime('%Y-%m-%d'),
        'y_actual': float('nan'),  # forecast 시점에는 모름 (사후 fill 가능)
        'crps': float('nan'),
        'pit': float('nan'),
        'model': model_name,
        'inference_at': datetime.now().isoformat(),
        'train_start': train_df['Date'].min().strftime('%Y-%m-%d'),
        'train_end': train_df['Date'].max().strftime('%Y-%m-%d'),
        'train_n': int(len(train_df)),
        # Hansen params
        'mu': float(sst['mu'][0]),
        'sigma': float(sst['sigma'][0]),
        'nu': float(sst['nu'][0]),
        'lam': float(sst['lam'][0]),
        # VaR
        'var_05': float(sst['var_05'][0]),
        'var_01': float(sst['var_01'][0]),
        'var_005': float(sst['var_005'][0]),
        'var_001': float(sst['var_001'][0]),
        'es_05': float(sst['es_05'][0]),
        # Bear probabilities
        'p_minus_5pct': float(sst['p_minus_5'][0]),
        'p_minus_7pct': float(sst['p_minus_7'][0]),
        'p_minus_10pct': float(sst['p_minus_10'][0]),
        # 11 raw quantiles (for audit / debug)
        **{f'q_{int(tau*1000):03d}': float(Q_pred[0, i]) for i, tau in enumerate(P_TAUS)},
    }
    return out_row


def append_to_predictions(out_row, model_name, output_dir=None):
    """Append/replace 1-row in daily_predictions.parquet."""
    if output_dir is None:
        output_dir = ROOT / "03_models" / "daily_predictions"
    output_dir.mkdir(parents=True, exist_ok=True)
    parquet_path = output_dir / f"{model_name}_daily.parquet"
    new_row_df = pd.DataFrame([out_row])
    if parquet_path.exists():
        existing = pd.read_parquet(parquet_path)
        # ensure Date is datetime
        if 'Date' in existing.columns:
            existing['Date'] = pd.to_datetime(existing['Date'])
        # remove existing row with same Date (latest replaces older)
        existing = existing[existing['Date'] != out_row['Date']]
        new_df = pd.concat([existing, new_row_df], ignore_index=True, sort=False)
    else:
        new_df = new_row_df
    new_df['Date'] = pd.to_datetime(new_df['Date'])
    new_df = new_df.sort_values('Date').reset_index(drop=True)
    new_df.to_parquet(parquet_path)

    # also save JSON for human read (drop Date Timestamp, keep asof_date string)
    json_path = output_dir / f"{model_name}_latest.json"
    json_safe = {k: v for k, v in out_row.items() if k != 'Date'}
    json_path.write_text(json.dumps(json_safe, indent=2, ensure_ascii=False, default=str))
    return parquet_path, json_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', type=str, default='P3', choices=['P2', 'P3'])
    parser.add_argument('--asof', type=str, default=None, help='YYYY-MM-DD (default: latest)')
    parser.add_argument('--lookback', type=int, default=None,
                        help='training lookback years (default: P2=8, P3=12)')
    parser.add_argument('--alpha', type=float, default=None,
                        help='LASSO L1 penalty (default: P2=0.001, P3=6.68e-4)')
    parser.add_argument('--output', type=str, default=None)
    args = parser.parse_args()

    # Model-specific defaults
    if args.alpha is None:
        args.alpha = 0.001 if args.model == 'P2' else 6.68e-4
    if args.lookback is None:
        args.lookback = 8 if args.model == 'P2' else 12

    out_row = daily_inference(args.model, args.asof, args.lookback, args.alpha)
    output_dir = Path(args.output) if args.output else None
    parquet_path, json_path = append_to_predictions(out_row, args.model, output_dir)

    print(f"\n=== {args.model} forecast for {out_row['asof_date']} ===")
    print(f"  mu={out_row['mu']:+.4f}%  sigma={out_row['sigma']:.4f}%  nu={out_row['nu']:.2f}  lam={out_row['lam']:+.4f}")
    print(f"  VaR_05={out_row['var_05']:+.2f}%  VaR_01={out_row['var_01']:+.2f}%  ES_05={out_row['es_05']:+.2f}%")
    print(f"  P(-5%)={out_row['p_minus_5pct']*100:.2f}%  P(-7%)={out_row['p_minus_7pct']*100:.2f}%  P(-10%)={out_row['p_minus_10pct']*100:.3f}%")
    print(f"\n[saved] {parquet_path}")
    print(f"[saved] {json_path}")


if __name__ == "__main__":
    main()
