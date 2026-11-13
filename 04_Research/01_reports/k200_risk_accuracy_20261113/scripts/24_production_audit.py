"""24_production_audit.py — 운영 기록(P3_daily.parquet) vs 현재 자료 재현 대조 · P3 분포 층 경계 적합 집계 · 이득 강건성.

산출: output/production_audit.json
  parity_by_month      운영 행 vs 재현의 σ 차이 중앙값 · 실현 수익 기록 차이 최대(벤치 개정 흔적)
  incident_rows        운영 σ 가 재현의 2배를 넘는 행(발송 브리핑의 이상치)
  shape_bounds         P3 의 ν · λ 가 경계에 붙은 날 수(전 기간)
  robustness[model]    IS · OOS 하루 ΔLS 의 평균 · 상하위 1% 절사 평균 · 중앙값 · 이긴 날 비율 · 연도별 양수 개수
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402

TAU = pd.Timestamp("2022-12-31")


def main():
    reg = json.loads((C.STUDY / "prereg" / "prereg_v1.json").read_text(encoding="utf-8"))
    rep = pd.read_parquet(C.OUT / "fc_P3_replica.parquet")
    prod = pd.read_parquet(C.P3_DIR / "03_models" / "daily_predictions" / "P3_daily.parquet")
    prod["Date"] = pd.to_datetime(prod["Date"])
    m = rep.merge(prod[["Date", "mu", "sigma", "nu", "lam", "y_actual", "inference_at"]], on="Date", suffixes=("_r", "_p"))
    m["dsig"] = (m["sigma_r"] - m["sigma_p"]).abs(); m["dy"] = (m["y"] - m["y_actual"]).abs()
    m["month"] = m["Date"].dt.strftime("%Y-%m")
    out = {"n_prod_rows_matched": int(len(m)),
           "parity_exact_rows": int((m["dsig"] < 1e-6).sum()),
           "parity_exact_from": str(m.loc[m["dsig"] < 1e-6, "Date"].min().date()) if (m["dsig"] < 1e-6).any() else None,
           "parity_by_month": m.groupby("month").agg(n=("dsig", "size"), dsig_median=("dsig", "median"),
                                                      dy_max=("dy", "max")).reset_index().to_dict(orient="records")}
    inc = m[m["sigma_p"] > 2 * m["sigma_r"]]
    out["incident_rows"] = [{"date": str(r.Date.date()), "sigma_prod": float(r.sigma_p), "sigma_replica": float(r.sigma_r),
                             "mu_prod": float(r.mu_p), "mu_replica": float(r.mu_r), "inference_at": str(r.inference_at)}
                            for r in inc.itertuples()]
    p3 = pd.read_parquet(C.OUT / "sc_P3.parquet")
    out["shape_bounds"] = {"n": int(len(p3)), "nu_lower_2p5": int((p3["nu"] < 2.51).sum()), "nu_upper_50": int((p3["nu"] > 49.9).sum()),
                           "lam_bound_0p98": int((p3["lam"].abs() > 0.97).sum()),
                           "lam_bound_dates": [str(d.date()) for d in p3.loc[p3["lam"].abs() > 0.97, "Date"]]}
    w = p3.nsmallest(3, "ls")
    out["p3_worst_ls_days"] = [{"date": str(r.Date.date()), "y": float(r.y), "ls": float(r.ls), "sigma": float(r.sigma),
                                "nu": float(r.nu), "lam": float(r.lam)} for r in w.itertuples()]
    # 도전 모형 중 매일 Hansen 재적합(분위 11점 → 분포)을 쓰는 것의 경계 적합 · 최악일 집중도
    out["challenger_shape_bounds"] = {}
    for c in reg["challengers"]:
        f = C.OUT / f"sc_{c['name']}.parquet"
        if not f.exists():
            continue
        s = pd.read_parquet(f)
        if s["nu"].nunique() < 200:  # 창 단위 상수 모양(분포 회귀)은 제외
            continue
        assert s["Date"].tolist() == p3["Date"].tolist()
        dq = s["ls"].values - p3["ls"].values
        _dd = pd.to_datetime(pd.read_parquet(C.BM_PATH, columns=["Date"])["Date"]).sort_values().reset_index(drop=True)
        _nxt = pd.Series(_dd.shift(-1).values, index=_dd.values)
        is_mask = (pd.to_datetime(p3["Date"].map(_nxt)) <= TAU).values  # 결과일 기준 IS
        worst = np.argsort(dq)[:6]
        wis = [i for i in worst if is_mask[i]]
        out["challenger_shape_bounds"][c["name"]] = {
            "nu_lower_2p5": int((s["nu"] < 2.51).sum()), "nu_upper_50": int((s["nu"] > 49.9).sum()),
            "lam_bound_0p98": int((s["lam"].abs() > 0.97).sum()),
            "worst6_share_of_IS_sum": float(dq[wis].sum() / dq[is_mask].sum()) if dq[is_mask].sum() != 0 else None,
            "worst6": [{"date": str(pd.Timestamp(s["Date"].iloc[i]).date()), "dls": float(dq[i]), "sigma": float(s["sigma"].iloc[i]),
                        "nu": float(s["nu"].iloc[i]), "lam": float(s["lam"].iloc[i])} for i in worst]}
    bm = pd.read_parquet(C.BM_PATH, columns=["Date"]); dd = pd.to_datetime(bm["Date"]).sort_values().reset_index(drop=True)
    nxt = pd.Series(dd.shift(-1).values, index=dd.values)
    yd = pd.to_datetime(p3["Date"].map(nxt))
    rob = {}
    for c in reg["challengers"]:
        f = C.OUT / f"sc_{c['name']}.parquet"
        if not f.exists():
            continue
        s = pd.read_parquet(f)
        assert s["Date"].tolist() == p3["Date"].tolist()
        d = s["ls"].values - p3["ls"].values
        r = {}
        for seg, mk in (("IS", (yd <= TAU).values), ("OOS", (yd > TAU).values)):
            x = d[mk]; q = np.quantile(x, [0.01, 0.99]); xt = x[(x >= q[0]) & (x <= q[1])]
            yrs = pd.Series(x, index=yd[mk].dt.year.values).groupby(level=0).mean()
            r[seg] = {"mean": float(x.mean()), "trim1_mean": float(xt.mean()), "median": float(np.median(x)),
                      "frac_better": float((x > 0).mean()), "years_positive": int((yrs > 0).sum()), "years": int(len(yrs)),
                      "top5_share": float(np.sort(x)[-5:].sum() / x.sum()) if x.sum() != 0 else None}
        rob[c["name"]] = r
    out["robustness"] = rob
    C.write_json(C.OUT / "production_audit.json", out)
    print(json.dumps({k: out[k] for k in ("n_prod_rows_matched", "parity_exact_rows", "parity_exact_from", "shape_bounds")}, ensure_ascii=False))
    print("incidents:", [(r["date"], round(r["sigma_prod"], 1), round(r["sigma_replica"], 1)) for r in out["incident_rows"]])
    for k, v in rob.items():
        print(k, {s: {kk: round(vv, 4) if isinstance(vv, float) else vv for kk, vv in x.items()} for s, x in v.items()})


if __name__ == "__main__":
    main()
