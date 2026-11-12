"""13_p3_is_from_chunks.py — 설계 단계 전용: P3 재현 조각 0..61(IS 예측일)만 모아 sc_P3.parquet(IS)을 만든다.
전 기간 재현이 끝나면 12_score_p3.py 가 sc_P3.parquet 를 전 기간으로 덮어쓴다.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402
import scoring as S  # noqa: E402

LAST_IS_CHUNK = 61  # 40일 조각 · 예측일 2013-01-24 부터 → 조각 61 이 2022-12 를 덮는다


def main():
    parts = [C.OUT / "_chunks_p3" / f"chunk_{i:04d}.parquet" for i in range(LAST_IS_CHUNK + 1)]
    miss = [p.name for p in parts if not p.exists()]
    if miss:
        raise SystemExit(f"missing {miss[:5]}")
    fc = pd.concat([pd.read_parquet(p) for p in parts], ignore_index=True).sort_values("Date").reset_index(drop=True)
    fc = fc[fc["Date"] <= pd.Timestamp("2022-12-31")]
    sc = S.score_hansen(fc[["Date", "y", "mu", "sigma", "nu", "lam"]].copy())
    for tau in C.P_TAUS:
        k = f"q_{int(round(tau * 1000)):03d}"
        sc[k] = fc[k].values
    sc.to_parquet(C.OUT / "sc_P3.parquet")
    print(f"[p3_is] n={len(sc)} {sc['Date'].min().date()} ~ {sc['Date'].max().date()}")


if __name__ == "__main__":
    main()
