"""602_h1_daily_inference.py — K200 일간 위험 브리핑 본 모형 H1 일간 추론 + 입력 · 출력 점검 (아침 체인 [6h]).

도훈 결정 K200-RISK-H1-REPLACE-P3-20261114(2026-11-14): 다음 아침 브리핑부터 H1(분포 회귀 + V-KOSPI200) 본 모형 ·
이상 입력 점검 포함 · P3 는 비교용으로 나란히 산출 · 기록. 모형 = 03_models/h1_dr_newsvk.py · 점검 = 03_models/h1_guard.py.

산출(--out, 기본 03_models/daily_predictions):
  H1_fits.json          재추정 기준일별 적합 모수(연구 워크포워드 적합 기록으로 시작 · 운영이 기준일마다 이어 적합)
  H1_daily.parquet      일별 예측(점검 통과 · 경고 행만) — P3_daily.parquet 과 같은 열 이름 + H1 열
  H1_latest.json        기준일 예측(차단이면 갱신하지 않는다 — 603 이 기준일 불일치로 본다)
  H1_guard_latest.json  기준일 점검 결과(통과 · 경고 · 차단 · 사유 · 값) — 매 실행 갱신
  H1_guard_log.jsonl    운영 실행 점검 기록(한 줄 = 한 실행)
사용:
  운영  : python scripts/602_h1_daily_inference.py --live --asof 2026-11-13
  초기화: python scripts/602_h1_daily_inference.py --asof 2026-11-13 --seed-research <fc_DR_newsvk.meta.json> --backfill-from 2026-01-26
  대조  : ... --parity <fc_DR_newsvk.parquet>   (연구 워크포워드 σ 와 최대 차이 · 허용 1e-4 %p 초과면 rc 2)
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


H = _load("h1_dr_newsvk", ROOT / "03_models" / "h1_dr_newsvk.py")
G = _load("h1_guard", ROOT / "03_models" / "h1_guard.py")

CATCHUP_MAX = 30          # 운영 실행이 메우는 최대 거래일 수(마지막 기록 다음 날 ~ 기준일)
PARITY_TOL = 1e-4         # 대조 허용 σ 차이(%p) — 연구 적합 기록의 ν · λ 반올림 왕복 차(실측 2.4e-6)의 40배 여유
REVISION_TOL = 0.01       # 실현 수익 개정 감지(%p)


def _json_default(o):
    if isinstance(o, (np.bool_,)):
        return bool(o)
    if isinstance(o, np.integer):
        return int(o)
    if isinstance(o, np.floating):
        return None if not np.isfinite(o) else float(o)
    if isinstance(o, np.ndarray):
        return o.tolist()
    if isinstance(o, pd.Timestamp):
        return str(o.date())
    raise TypeError(type(o).__name__)


def write_json(path: Path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2, default=_json_default), encoding="utf-8")
    os.replace(tmp, path)


def write_parquet(path: Path, df: pd.DataFrame):
    tmp = path.with_suffix(path.suffix + ".tmp")
    df.to_parquet(tmp, index=False)
    os.replace(tmp, path)


# ─── 적합 저장소 ────────────────────────────────────────────────────────────────────────────────────────
def load_store(path: Path) -> dict:
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {"model": H.MODEL_ID, "name": H.MODEL_NAME, "feats": list(H.FEATS), "fits": {}}


def seed_store(store: dict, meta_path: Path) -> int:
    meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
    if list(meta["feats"]) != list(H.FEATS):
        raise SystemExit(f"seed feats {meta['feats']} ≠ {list(H.FEATS)}")
    n = 0
    for f in meta["fits"]:
        if f["refit"] in store["fits"]:
            continue
        th = H.pack(f["mu"], f["a0"], [f[f"a_{c}"] for c in H.FEATS], f["nu"], f["lam"])
        store["fits"][f["refit"]] = {"theta": th.tolist(), "n": f["n"], "nll": f["nll"], "ok": f["ok"],
                                     "source": "research_seed", "seeded_from": str(meta_path).replace("\\", "/")}
        n += 1
    store["seed"] = {"from": str(meta_path).replace("\\", "/"), "n": n, "data_vintage": meta.get("data_vintage"),
                     "at": datetime.now().isoformat(timespec="seconds")}
    return n


def ensure_fits(store: dict, tr_all: pd.DataFrame, dates: list, anchors: list) -> dict:
    """요청 기준일들을 오래된 순으로 적합 — 시작점 = 격자상 직전 기준일의 저장 모수(연구 워크포워드와 같은 사슬)."""
    out = {}
    for a in sorted(set(anchors)):
        i = dates.index(a)
        prev = dates[i - H.REFIT_EVERY] if i >= H.REFIT_EVERY else None
        th0 = None
        if prev is not None:
            pk = str(prev.date())
            if pk in store["fits"]:
                th0 = np.asarray(store["fits"][pk]["theta"], float)
        fr = H.fit_anchor(tr_all, a, th0)
        ak = str(a.date())
        old = store["fits"].get(ak)
        dth = float(np.max(np.abs(fr["theta"] - np.asarray(old["theta"], float)))) if old else None
        store["fits"][ak] = {"theta": fr["theta"].tolist(), "n": fr["n"], "nll": fr["nll"], "ok": fr["ok"],
                             "train_start": str(fr["train_start"].date()), "train_end": str(fr["train_end"].date()),
                             "start_from": (str(prev.date()) if th0 is not None else "cold"),
                             "source": "production", "updated_at": datetime.now().isoformat(timespec="seconds"),
                             "max_dtheta_vs_stored": dth}
        out[a] = fr
    return out


# ─── 한 날짜 예측 + 점검 ───────────────────────────────────────────────────────────────────────────────
def predict_day(t, df, dix, b, ix, fr, cfg, sigma_prev, live):
    blk, wrn = [], []
    bb, bw, binfo = G.check_bench(b, t, cfg, live)
    blk += bb; wrn += bw
    vb, vw, vinfo = G.check_vk(ix, t, binfo, cfg)
    blk += vb; wrn += vw
    x_t = dix.loc[t, list(H.FEATS)].values.astype(float)
    fb, fw = G.check_fit(fr, x_t, H.TRAIN_MIN_ROWS)
    blk += fb; wrn += fw
    row = None; oinfo = {}
    if np.isfinite(x_t).all() and np.isfinite(fr["theta"]).all():
        o = H.forecast_from_fit(fr, x_t)
        met = H.metrics(o["mu"], o["sigma"], o["nu"], o["lam"]) if (math.isfinite(o["sigma"]) and o["sigma"] > 0) else \
            {k: float("nan") for k in ("var_05", "var_01", "var_005", "var_001", "es_05", "p_minus_5pct", "p_minus_7pct", "p_minus_10pct")}
        ob, ow, oinfo = G.check_output(o, met, binfo.get("ewma_t", float("nan")), sigma_prev, o["z"], fr, H.FEATS, cfg)
        blk += ob; wrn += ow
        row = {"Date": pd.Timestamp(t), "asof_date": str(pd.Timestamp(t).date()), "y_actual": float("nan"), "crps": float("nan"),
               "pit": float("nan"), "model": H.MODEL_ID, "inference_at": datetime.now().isoformat(),
               "train_start": str(fr["train_start"].date()), "train_end": str(fr["train_end"].date()), "train_n": int(fr["n"]),
               "mu": o["mu"], "sigma": o["sigma"], "nu": o["nu"], "lam": o["lam"], **met,
               "refit_anchor": str(fr["anchor"].date()), "vkospi": vinfo.get("vk", float("nan")),
               "ewma_sigma": binfo.get("ewma_t", float("nan")), "ratio_ewma": oinfo.get("ratio_ewma", float("nan"))}
    status = G.status_of(blk, wrn)
    data_bm_ok = not any(x["code"] in ("B1", "B2") for x in blk)
    if row is not None:
        row["guard_status"] = status
        row["guard_codes"] = ",".join(sorted({x["code"] for x in blk + wrn}))
    guard = {"asof": str(pd.Timestamp(t).date()), "status": status, "data_bm_ok": data_bm_ok,
             "block": blk, "warn": wrn, "info": {**binfo, **vinfo, **oinfo}}
    return row, guard


def refresh_actuals(hist: pd.DataFrame, df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """실현 수익(y_actual) · PIT 를 현재 자료로 다시 채운다 — 저장값과 다르면 개정으로 센다(W6)."""
    if hist.empty:
        return hist, {"n_revised": 0, "max_abs": 0.0}
    fwd = df.set_index("Date")["ret_fwd"]
    new_y = hist["Date"].map(fwd).astype(float)
    old_y = hist["y_actual"].astype(float)
    both = old_y.notna() & new_y.notna()
    diff = (old_y[both] - new_y[both]).abs()
    rev = {"n_revised": int((diff > REVISION_TOL).sum()), "max_abs": float(diff.max()) if len(diff) else 0.0,
           "dates": [str(d.date()) for d in hist.loc[diff[diff > REVISION_TOL].index, "Date"]][:10]}
    hist = hist.copy()
    hist["y_actual"] = new_y
    ok = hist["y_actual"].notna()
    hist.loc[ok, "pit"] = [H.pit(y, m, s, n, l) for y, m, s, n, l in
                           hist.loc[ok, ["y_actual", "mu", "sigma", "nu", "lam"]].itertuples(index=False)]
    return hist, rev


def run(asof, out_dir: Path, live: bool, backfill_from=None, seed_meta=None, bm=None, ix=None, cfg=None,
        parity=None, write=True):
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    cfg = cfg or G.load_config()
    bm = bm if bm is not None else pd.read_parquet(PROJECT_ROOT / ".cache" / "benchmark.parquet")
    ix = ix if ix is not None else pd.read_parquet(PROJECT_ROOT / ".cache" / "indices.parquet", columns=["Date", "kospi200_vol"])
    df = H.build_frame(PROJECT_ROOT, bm=bm, ix=ix)
    dix = df.set_index("Date")
    b = G.bench_frame(bm, cfg["ewma_lambda"])
    asof = pd.Timestamp(asof) if asof else df["Date"].max()
    dates = H.grid_dates(df)
    if asof not in dates:
        raise SystemExit(f"asof {asof.date()} 가 벤치 거래일 격자에 없다")
    tr_all = H.training_rows(df)
    store_p = out_dir / "H1_fits.json"
    store = load_store(store_p)
    if seed_meta:
        print(f"[H1] seed from research: +{seed_store(store, Path(seed_meta))} anchors")
    hist_p = out_dir / "H1_daily.parquet"
    hist = pd.read_parquet(hist_p) if hist_p.exists() else pd.DataFrame()
    if not hist.empty:
        hist["Date"] = pd.to_datetime(hist["Date"])
    # 예측할 날짜
    ia = dates.index(asof)
    if backfill_from:
        todo = [d for d in dates if pd.Timestamp(backfill_from) <= d <= asof]
    else:
        last = hist["Date"].max() if not hist.empty else None
        i0 = (dates.index(last) + 1) if (last is not None and last in dates) else ia
        todo = dates[max(i0, ia - CATCHUP_MAX + 1, 0): ia + 1]
        if asof not in todo:
            todo.append(asof)
    anchors = [H.anchor_for(t, dates) for t in todo]
    fits = ensure_fits(store, tr_all, dates, anchors)
    rows, guards = [], []
    prev_sigma = {}
    if not hist.empty:
        prev_sigma.update(dict(zip(hist["Date"], hist["sigma"])))
    for t in todo:
        it = dates.index(t)
        sp = prev_sigma.get(dates[it - 1]) if it > 0 else None
        row, guard = predict_day(t, df, dix, b, ix, fits[H.anchor_for(t, dates)], cfg, sp, live and t == asof)
        guard["mode"] = "live" if (live and t == asof) else ("backfill" if backfill_from else "catchup")
        guards.append(guard)
        if row is not None:
            row["source"] = guard["mode"]
            prev_sigma[t] = row["sigma"]
            if guard["status"] != "BLOCK":
                rows.append(row)
    # 이력 갱신 — 같은 날짜 행 교체 · 차단 날짜 행 제거
    todo_set = set(todo)
    keep = hist[~hist["Date"].isin(todo_set)] if not hist.empty else hist
    new = pd.DataFrame(rows)
    hist2 = pd.concat([keep, new], ignore_index=True, sort=False) if not new.empty else keep.copy()
    if not hist2.empty:
        hist2["Date"] = pd.to_datetime(hist2["Date"])
        hist2 = hist2.sort_values("Date").reset_index(drop=True)
    hist2, rev = refresh_actuals(hist2, df)
    g_asof = guards[-1]
    if rev["n_revised"] > 0:
        g_asof["warn"].append({"code": "W6", "msg": f"과거 실현 수익 개정 {rev['n_revised']}건(최대 {rev['max_abs']:.2f}%p · {', '.join(rev['dates'][:3])})"})
        if g_asof["status"] == "PASS":
            g_asof["status"] = "WARN"
    g_asof["revisions"] = rev
    g_asof["made_at"] = datetime.now().isoformat(timespec="seconds")
    g_asof["fit_anchor"] = str(H.anchor_for(asof, dates).date())
    g_asof["fit"] = {k: v for k, v in store["fits"][g_asof["fit_anchor"]].items() if k != "theta"}
    par = None
    if parity:
        fc = pd.read_parquet(parity); fc["Date"] = pd.to_datetime(fc["Date"])
        j = fc.merge(hist2[["Date", "sigma"]], on="Date", suffixes=("_r", "_p"))
        par = {"n": int(len(j)), "max_abs_dsigma": float((j["sigma_r"] - j["sigma_p"]).abs().max()) if len(j) else None, "tol": PARITY_TOL}
        g_asof["parity"] = par
    if write:
        write_json(store_p, store)
        if not hist2.empty:
            write_parquet(hist_p, hist2)
        write_json(out_dir / "H1_guard_latest.json", g_asof)
        if g_asof["status"] != "BLOCK":
            lr = hist2[hist2["Date"] == asof]
            if len(lr):
                js = {k: v for k, v in lr.iloc[0].to_dict().items() if k != "Date"}
                js["guard"] = {"status": g_asof["status"], "codes": [x["code"] for x in g_asof["block"] + g_asof["warn"]]}
                write_json(out_dir / "H1_latest.json", js)
        else:
            # 차단 — 수치 없는 표지만 남긴다(같은 기준일의 이전 값이 남아 오인되지 않게 · 막힌 값은 rejected 에 기록)
            write_json(out_dir / "H1_latest.json", {
                "asof_date": g_asof["asof"], "model": H.MODEL_ID, "blocked": True,
                "guard": {"status": "BLOCK", "codes": [x["code"] for x in g_asof["block"] + g_asof["warn"]],
                          "block": [x["msg"] for x in g_asof["block"]]},
                "rejected": {k: g_asof["info"].get(k) for k in ("sigma", "var_01", "vk", "ratio_ewma")},
                "inference_at": g_asof["made_at"]})
        if live:
            with open(out_dir / "H1_guard_log.jsonl", "a", encoding="utf-8") as fh:
                fh.write(json.dumps({k: g_asof[k] for k in ("asof", "status", "block", "warn", "made_at", "fit_anchor")} |
                                    {"sigma": g_asof["info"].get("sigma"), "vk": g_asof["info"].get("vk")},
                                    ensure_ascii=False, default=_json_default) + "\n")
    return {"hist": hist2, "guards": guards, "guard_asof": g_asof, "parity": par, "store": store}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asof", default=None)
    ap.add_argument("--out", default=str(ROOT / "03_models" / "daily_predictions"))
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--backfill-from", default=None)
    ap.add_argument("--seed-research", default=None)
    ap.add_argument("--parity", default=None)
    a = ap.parse_args()
    r = run(a.asof, Path(a.out), a.live, a.backfill_from, a.seed_research, parity=a.parity)
    g = r["guard_asof"]
    lr = r["hist"][r["hist"]["Date"] == pd.Timestamp(g["asof"])] if not r["hist"].empty else pd.DataFrame()
    print(f"[H1] asof {g['asof']} · guard {g['status']} · anchor {g['fit_anchor']} · rows {len(r['hist'])}")
    for x in g["block"]:
        print(f"[H1]   BLOCK {x['code']}: {x['msg']}")
    for x in g["warn"]:
        print(f"[H1]   WARN  {x['code']}: {x['msg']}")
    if len(lr) and g["status"] != "BLOCK":
        o = lr.iloc[0]
        print(f"[H1]   σ={o.sigma:.3f}%  μ={o.mu:+.4f}%  ν={o.nu:.2f}  λ={o.lam:+.4f}  VaR5={o.var_05:+.2f}%  VaR1={o.var_01:+.2f}%  "
              f"ES5={o.es_05:+.2f}%  P(-5%)={o.p_minus_5pct*100:.2f}%  VK={o.vkospi:.2f}")
    if r["parity"] is not None:
        p = r["parity"]
        print(f"[H1] parity vs research: n={p['n']} max|Δσ|={p['max_abs_dsigma']:.3g} (tol {p['tol']})")
        if p["max_abs_dsigma"] is None or p["max_abs_dsigma"] > p["tol"]:
            sys.exit(2)


if __name__ == "__main__":
    main()
