"""30_challenger_qr.py — P3 골격(LASSO 분위회귀 11분위 → Hansen 적합) 위의 도전 모형 워크포워드.

P3 와 같은 것: 학습 창(12년 · 21일 금지) · α · 11분위 · 매일 재적합 · Hansen 적합(ν ∈ (2.5, 50)).
다른 것: 특징 추가(--extra) 또는 분포 층(--dist) — 사전등록(prereg/*.json)이 정본 사양.

추가 특징 어휘(모두 t 종가까지 자료 · PIT):
  r0     r_t = 100·log(P_t/P_{t−1})  (운영 특징은 r_{t−1}(lag_1)부터라 r_t 가 직접 없다)
  absr0  |r_t|
  negr0  min(r_t, 0)  (GJR 의 음수 충격 — Glosten, Jagannathan & Runkle 1993)
  lvk    log V-KOSPI200_t (.cache/indices.parquet::kospi200_vol · 2003-01-02~ · KRX 산출 종가)
  dlvk   log V-KOSPI200_t − log V-KOSPI200_{t−1}
--until YYYY-MM-DD  : 예측일 상한(설계 단계 IS 전용 실행)
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
EXTRA_VOCAB = ("r0", "absr0", "negr0", "lvk", "dlvk")


def build_frame(p472, extra):
    df, fc = C.build_feature_frame(p472)
    bm = pd.read_parquet(C.BM_PATH); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date")
    bm["r0"] = np.log(bm["BM_Close"]).diff() * 100.0
    df = df.merge(bm[["Date", "r0"]], on="Date", how="left")
    df["absr0"] = df["r0"].abs()
    df["negr0"] = np.minimum(df["r0"], 0.0)
    if "lvk" in extra or "dlvk" in extra:
        ix = pd.read_parquet(C.PROJECT_ROOT / ".cache" / "indices.parquet", columns=["Date", "kospi200_vol"])
        ix["Date"] = pd.to_datetime(ix["Date"]); ix = ix.sort_values("Date")
        ix["lvk"] = np.log(ix["kospi200_vol"])
        ix["dlvk"] = ix["lvk"].diff()
        df = df.merge(ix[["Date", "lvk", "dlvk"]], on="Date", how="left")
    feats = fc + [e for e in extra]
    return df, feats


def _init(extra):
    lqm, p472, hsk3 = C.load_p3_modules()
    df, feats = build_frame(p472, extra)
    _G.update(lqm=lqm, hsk3=hsk3, df=df, feats=feats)


def _one(t):
    lqm, hsk3, df, feats = _G["lqm"], _G["hsk3"], _G["df"], _G["feats"]
    t = pd.Timestamp(t)
    te = t - pd.Timedelta(days=C.P3_EMBARGO_CAL_DAYS)
    ts = te - pd.DateOffset(years=C.P3_LOOKBACK_YEARS)
    tr = df[(df["Date"] >= ts) & (df["Date"] <= te)].dropna(subset=feats + ["ret_fwd"])
    row = df[df["Date"] == t]
    m = lqm.LassoQuantileGaR(taus=C.P_TAUS, alpha=C.P3_ALPHA, standardize=True)
    m.fit(tr[feats].values.astype(np.float64), tr["ret_fwd"].values.astype(np.float64), feature_names=feats)
    Q = m.predict_all_quantiles(row[feats].values.astype(np.float64), fix_crossing=True)
    mu, sigma, nu, lam = hsk3.fit_hansen_to_quantiles(np.sort(Q[0]), np.array(C.P_TAUS), init=None)
    out = {"Date": t, "y": float(row["ret_fwd"].iloc[0]), "train_n": int(len(tr)),
           "train_start": tr["Date"].min(), "mu": float(mu), "sigma": float(sigma), "nu": float(nu), "lam": float(lam)}
    for i, tau in enumerate(C.P_TAUS):
        out[f"q_{int(round(tau * 1000)):03d}"] = float(Q[0, i])
    return out


def _chunk(dates, path):
    pd.DataFrame([_one(t) for t in dates]).to_parquet(path)
    return str(path), len(dates)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--extra", type=str, default="")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--until", type=str, default="2099-12-31")
    ap.add_argument("--chunk", type=int, default=40)
    args = ap.parse_args()
    extra = [e for e in args.extra.split(",") if e]
    bad = [e for e in extra if e not in EXTRA_VOCAB]
    if bad:
        raise SystemExit(f"unknown extra {bad}")
    dates = C.forecast_dates(args.until)
    cdir = C.OUT / f"_chunks_{args.name}"
    cdir.mkdir(parents=True, exist_ok=True)
    jobs = []
    for k in range(0, len(dates), args.chunk):
        p = cdir / f"chunk_{k // args.chunk:04d}.parquet"
        want = dates[k:k + args.chunk]
        if p.exists():
            have = [pd.Timestamp(x) for x in pd.read_parquet(p, columns=["Date"])["Date"]]
            if have == want:
                continue  # 같은 날짜 묶음이면 재사용(IS 실행 뒤 전 기간 실행에서 마지막 조각은 다시 계산)
        jobs.append((want, p))
    print(f"[{args.name}] extra={extra} dates={len(dates)} todo_chunks={len(jobs)}", flush=True)
    t0 = time.time(); n = 0
    if jobs:
        with ProcessPoolExecutor(max_workers=args.workers, initializer=_init, initargs=(extra,)) as ex:
            for f in as_completed([ex.submit(_chunk, d, p) for d, p in jobs]):
                _, k = f.result(); n += k
                print(f"  [{n}] {(time.time()-t0)/60:.1f}m", flush=True)
    parts = sorted(cdir.glob("chunk_*.parquet"))
    full = pd.concat([pd.read_parquet(p) for p in parts], ignore_index=True).sort_values("Date").reset_index(drop=True)
    full = full[full["Date"] <= pd.Timestamp(args.until)]
    full.to_parquet(C.OUT / f"fc_{args.name}.parquet")
    import scoring as S
    sc = S.score_hansen(full[["Date", "y", "mu", "sigma", "nu", "lam"]].copy())
    sc.to_parquet(C.OUT / f"sc_{args.name}.parquet")
    C.write_json(C.OUT / f"fc_{args.name}.meta.json", {"name": args.name, "extra": extra, "n": int(len(full)),
                 "until": args.until, "data_vintage": C.data_vintage(), "elapsed_min": round((time.time()-t0)/60, 1)})
    print(f"[{args.name}] saved n={len(full)}", flush=True)


if __name__ == "__main__":
    main()
