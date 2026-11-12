"""12_score_p3.py — P3 재현 예측(fc_P3_replica.parquet) → 일별 점수 파일 sc_P3.parquet.

ES 는 결정론 중점 적분(운영 601 은 400점 무작위 MC — 같은 날 재실행 때 값이 흔들린다 · 진단에 기록).
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402


def main():
    fc = pd.read_parquet(C.OUT / "fc_P3_replica.parquet")
    sc = S.score_hansen(fc[["Date", "y", "mu", "sigma", "nu", "lam"]].copy())
    for c in ("nnz_q05", "nnz_q50", "train_n"):
        sc[c] = fc[c].values
    for tau in C.P_TAUS:
        k = f"q_{int(round(tau * 1000)):03d}"
        sc[k] = fc[k].values
    sc.to_parquet(C.OUT / "sc_P3.parquet")
    # 운영 ES(MC 400점) 잡음 크기 — 같은 모수로 200회 재추정한 표준편차(최근 20일 표본)
    hsk3 = C.load_p3_modules()[2]
    tail = fc.tail(20)
    sd = []
    for _, r in tail.iterrows():
        v = [float(hsk3.hansen_quantile(np.random.uniform(1e-6, 0.05, 400), r.mu, r.sigma, r.nu, r.lam).mean()) for _ in range(200)]
        sd.append(np.std(v) / abs(np.mean(v)))
    C.write_json(C.OUT / "sc_P3.meta.json", {"n": int(len(sc)), "es_mc_noise_rel_sd_median_last20": float(np.median(sd)),
                                              "data_vintage": C.data_vintage()})
    print(f"[score_p3] n={len(sc)} · 운영 ES MC 상대 표준편차(중앙) = {np.median(sd):.3%}")


if __name__ == "__main__":
    main()
