"""10_p3_replica_walkforward.py — 운영 P3 를 그대로 재현한 워크포워드 1일 분포 예측(기준선).

운영 사양(601_daily_inference.py · morning_briefing.sh [6/6]):
  특징 12개(472 load_data) · 표적 = 다음 거래일 로그수익(%) · LASSO 분위회귀 11분위(α = 6.68e-4 · 표준화 · highs)
  · 학습 창 = [t − 21일 − 12년, t − 21일](달력일) · **매일 재적합** · 분위 정렬 → Hansen 비대칭 t(ν ∈ (2.5, 50)) 적합(init 없음).
PIT: 예측일 t 의 특징은 t 종가까지 · 학습 표본의 표적(t'→t'+1)은 t' ≤ t − 21일이라 t 이전에 실현.

실행: .venv_qvest_ml/Scripts/python.exe 04_Research/01_reports/k200_risk_accuracy_20261113/scripts/10_p3_replica_walkforward.py --workers 6
산출: output/fc_P3_replica.parquet (+ 조각 output/_chunks_p3/ · 재시작 시 완료 조각 건너뜀)
"""
from __future__ import annotations

import argparse
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

_G = {}


def _init():
    lqm, p472, hsk3 = C.load_p3_modules()
    df, fc = C.build_feature_frame(p472)
    _G.update(lqm=lqm, hsk3=hsk3, df=df, fc=fc)


def _one(t):
    lqm, hsk3, df, fc = _G["lqm"], _G["hsk3"], _G["df"], _G["fc"]
    t = pd.Timestamp(t)
    train_end = t - pd.Timedelta(days=C.P3_EMBARGO_CAL_DAYS)
    train_start = train_end - pd.DateOffset(years=C.P3_LOOKBACK_YEARS)
    tr = df[(df["Date"] >= train_start) & (df["Date"] <= train_end)]
    row = df[df["Date"] == t]
    m = lqm.LassoQuantileGaR(taus=C.P_TAUS, alpha=C.P3_ALPHA, standardize=True)
    m.fit(tr[fc].values.astype(np.float64), tr["ret_fwd"].values.astype(np.float64), feature_names=fc)
    Q = m.predict_all_quantiles(row[fc].values.astype(np.float64), fix_crossing=True)
    mu, sigma, nu, lam = hsk3.fit_hansen_to_quantiles(np.sort(Q[0]), np.array(C.P_TAUS), init=None)
    out = {"Date": t, "y": float(row["ret_fwd"].iloc[0]), "train_start": tr["Date"].min(),
           "train_end": tr["Date"].max(), "train_n": int(len(tr)),
           "mu": float(mu), "sigma": float(sigma), "nu": float(nu), "lam": float(lam)}
    for i, tau in enumerate(C.P_TAUS):
        out[f"q_{int(round(tau * 1000)):03d}"] = float(Q[0, i])
    # 비영(0) 계수 수(진단)
    out["nnz_q05"] = int(m.n_nonzero_features(0.05))
    out["nnz_q50"] = int(m.n_nonzero_features(0.50))
    return out


def _chunk(dates, path):
    rows = [_one(t) for t in dates]
    pd.DataFrame(rows).to_parquet(path)
    return str(path), len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--start", type=str, default="2013-01-24")
    ap.add_argument("--end", type=str, default="2026-12-31")
    ap.add_argument("--chunk", type=int, default=40)
    ap.add_argument("--tag", type=str, default="")
    args = ap.parse_args()

    lqm, p472, hsk3 = C.load_p3_modules()
    df, fc = C.build_feature_frame(p472)
    dates = df.loc[(df["Date"] >= args.start) & (df["Date"] <= args.end), "Date"].tolist()
    # 첫 날은 12년 창이 꽉 차는 날부터(운영 정상 상태)
    first_ok = pd.Timestamp("2001-01-03") + pd.DateOffset(years=C.P3_LOOKBACK_YEARS) + pd.Timedelta(days=C.P3_EMBARGO_CAL_DAYS)
    dates = [d for d in dates if d >= first_ok]
    chunk_dir = C.OUT / f"_chunks_p3{args.tag}"
    chunk_dir.mkdir(parents=True, exist_ok=True)
    jobs = []
    for k in range(0, len(dates), args.chunk):
        p = chunk_dir / f"chunk_{k // args.chunk:04d}.parquet"
        if p.exists():
            continue
        jobs.append((dates[k:k + args.chunk], p))
    print(f"[p3_replica] dates={len(dates)} ({dates[0].date()}~{dates[-1].date()}) chunks_todo={len(jobs)} workers={args.workers}", flush=True)
    t0 = time.time()
    done = 0
    if jobs:
        with ProcessPoolExecutor(max_workers=args.workers, initializer=_init) as ex:
            futs = [ex.submit(_chunk, d, p) for d, p in jobs]
            for f in as_completed(futs):
                path, n = f.result()
                done += n
                el = time.time() - t0
                print(f"  [{done}] {Path(path).name} n={n} elapsed={el/60:.1f}m", flush=True)
    parts = sorted(chunk_dir.glob("chunk_*.parquet"))
    full = pd.concat([pd.read_parquet(p) for p in parts], ignore_index=True).sort_values("Date").reset_index(drop=True)
    full.to_parquet(C.OUT / f"fc_P3_replica{args.tag}.parquet")
    meta = {"script": "10_p3_replica_walkforward.py", "n": int(len(full)),
            "first": str(full["Date"].min().date()), "last": str(full["Date"].max().date()),
            "spec": {"alpha": C.P3_ALPHA, "lookback_years": C.P3_LOOKBACK_YEARS,
                     "embargo_cal_days": C.P3_EMBARGO_CAL_DAYS, "taus": list(C.P_TAUS), "refit": "daily"},
            "data_vintage": C.data_vintage(), "elapsed_min": round((time.time() - t0) / 60, 1)}
    C.write_json(C.OUT / f"fc_P3_replica{args.tag}.meta.json", meta)
    print(f"[p3_replica] saved n={len(full)} → output/fc_P3_replica.parquet", flush=True)


if __name__ == "__main__":
    main()
