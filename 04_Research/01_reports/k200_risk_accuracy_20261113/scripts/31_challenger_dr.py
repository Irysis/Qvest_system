"""31_challenger_dr.py — 분포 회귀(위치-척도 · 직접 최대우도) 도전 모형 워크포워드.

모형:  y_{t+1} = μ + σ_t ε_{t+1},  ε ~ Hansen(ν, λ) 표준화(평균 0 · 분산 1)
       log σ_t = a0 + a' z_t      (z_t = 학습 창 평균 · 표준편차로 표준화한 특징)
       μ · a0 · a · ν · λ 를 학습 창의 로그우도로 한 번에 추정(분포 표적 직접 학습 — GAMLSS 형, Rigby & Stasinopoulos 2005)
       척도 입력 = HAR 형 실현 변동성(Corsi 2009) 로그 + 최근 수익 충격(Engle & Ng 1993 뉴스 충격 곡선) [+ V-KOSPI200]
학습 창: P3 와 같은 규칙 [t_k − 21일 − 12년, t_k − 21일] · 21거래일마다 재추정(t_k) · σ_t 는 매일 t 종가 특징으로 갱신.
특징 어휘(전부 t 종가까지):
  lrv5 lrv22 lrv60  log 실현 변동성(5 · 22 · 60일 표준편차 %, P3 의 rv_*)
  r0 absr0 negr0    r_t · |r_t| · min(r_t, 0)
  ddz               P3 의 drawdown_z(확장 창 z)
  lvk dlvk          log V-KOSPI200_t · 그 하루 변화
--until : 예측일 상한(설계 단계 IS 전용)
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import optimize as sp_opt

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

VOCAB = ("lrv5", "lrv22", "lrv60", "r0", "absr0", "negr0", "ddz", "lvk", "dlvk")
REFIT_EVERY = 21


def build_frame(feats):
    p472 = C.load_p3_modules()[1]
    df, _ = C.build_feature_frame(p472)
    bm = pd.read_parquet(C.BM_PATH); bm["Date"] = pd.to_datetime(bm["Date"]); bm = bm.sort_values("Date")
    bm["r0"] = np.log(bm["BM_Close"]).diff() * 100.0
    df = df.merge(bm[["Date", "r0"]], on="Date", how="left")
    df["absr0"] = df["r0"].abs(); df["negr0"] = np.minimum(df["r0"], 0.0)
    df["lrv5"] = np.log(np.maximum(df["rv_5d"], 1e-3)); df["lrv22"] = np.log(np.maximum(df["rv_22d"], 1e-3))
    df["lrv60"] = np.log(np.maximum(df["rv_60d"], 1e-3)); df["ddz"] = df["drawdown_z"]
    if "lvk" in feats or "dlvk" in feats:
        ix = pd.read_parquet(C.PROJECT_ROOT / ".cache" / "indices.parquet", columns=["Date", "kospi200_vol"])
        ix["Date"] = pd.to_datetime(ix["Date"]); ix = ix.sort_values("Date")
        ix["lvk"] = np.log(ix["kospi200_vol"]); ix["dlvk"] = ix["lvk"].diff()
        df = df.merge(ix[["Date", "lvk", "dlvk"]], on="Date", how="left")
    return df


def unpack(th, k):
    mu = th[0]; a0 = th[1]; a = th[2:2 + k]
    nu = 2.05 + np.exp(th[2 + k]); lam = 0.95 * np.tanh(th[3 + k])
    return mu, a0, a, nu, lam


def nll(th, Z, y, k):
    mu, a0, a, nu, lam = unpack(th, k)
    if nu > 200:
        return 1e10
    ls = a0 + Z @ a
    if np.any(ls > 4) or np.any(ls < -6):
        return 1e10
    v = -float(np.sum(C.hansen_logpdf(y, mu, np.exp(ls), nu, lam)))
    return v if np.isfinite(v) else 1e10


def fit(Z, y, th0):
    k = Z.shape[1]
    if th0 is None:
        th0 = np.zeros(4 + k); th0[1] = np.log(np.std(y)); th0[2 + k] = np.log(6.0); th0[3 + k] = -0.05
    res = sp_opt.minimize(nll, th0, args=(Z, y, k), method="BFGS", options={"maxiter": 2000, "gtol": 1e-5})
    if not res.success:
        res2 = sp_opt.minimize(nll, res.x, args=(Z, y, k), method="Nelder-Mead",
                               options={"maxiter": 20000, "xatol": 1e-6, "fatol": 1e-6})
        if res2.fun <= res.fun:
            return res2.x, res2, False
    return res.x, res, bool(res.success)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--feats", type=str, required=True)
    ap.add_argument("--until", type=str, default="2099-12-31")
    args = ap.parse_args()
    feats = [f for f in args.feats.split(",") if f]
    bad = [f for f in feats if f not in VOCAB]
    if bad:
        raise SystemExit(f"unknown feats {bad}")
    t0 = time.time()
    df = build_frame(feats)
    dates = C.forecast_dates(args.until)
    dix = df.set_index("Date")
    rows = []; th = None; log = []
    for k0 in range(0, len(dates), REFIT_EVERY):
        blk = dates[k0:k0 + REFIT_EVERY]
        tk = blk[0]
        te = tk - pd.Timedelta(days=C.P3_EMBARGO_CAL_DAYS); ts = te - pd.DateOffset(years=C.P3_LOOKBACK_YEARS)
        tr = df[(df["Date"] >= ts) & (df["Date"] <= te)].dropna(subset=feats + ["ret_fwd"])
        X = tr[feats].values.astype(float); m_ = X.mean(0); s_ = X.std(0); s_[s_ == 0] = 1
        Z = (X - m_) / s_
        th, res, ok = fit(Z, tr["ret_fwd"].values.astype(float), th)
        mu, a0, a, nu, lam = unpack(th, len(feats))
        log.append({"refit": str(tk.date()), "n": int(len(tr)), "ok": ok, "nll": float(res.fun), "nu": float(nu),
                    "lam": float(lam), "mu": float(mu), "a0": float(a0), **{f"a_{f}": float(v) for f, v in zip(feats, a)}})
        for t in blk:
            x = dix.loc[t, feats].values.astype(float)
            sg = float(np.exp(a0 + ((x - m_) / s_) @ a))
            rows.append({"Date": t, "y": float(dix.loc[t, "ret_fwd"]), "mu": float(mu), "sigma": sg,
                         "nu": float(nu), "lam": float(lam)})
    fc = pd.DataFrame(rows)
    fc.to_parquet(C.OUT / f"fc_{args.name}.parquet")
    S.score_hansen(fc).to_parquet(C.OUT / f"sc_{args.name}.parquet")
    C.write_json(C.OUT / f"fc_{args.name}.meta.json", {"name": args.name, "feats": feats, "n": int(len(fc)),
                 "until": args.until, "refit_every": REFIT_EVERY, "fits": log, "data_vintage": C.data_vintage(),
                 "elapsed_s": round(time.time() - t0, 1)})
    print(f"[{args.name}] n={len(fc)} refits={len(log)} ok={np.mean([l['ok'] for l in log]):.2f} {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
