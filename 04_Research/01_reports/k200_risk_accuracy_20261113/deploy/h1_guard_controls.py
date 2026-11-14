"""h1_guard_controls.py — H1 입력 · 출력 점검기의 양성 · 음성 대조(배포 전 1회 · 결과 = deploy/h1_guard_controls.json).

검사기는 양방향으로 잰다: 막아야 할 것(실제 사고 값 · 실제 자료 오류 · 주입 오류)은 막고, 막지 말아야 할 것(실제 급락 · 평상일)은 통과시킨다.
운영 산출물은 건드리지 않는다 — 모든 실행은 write=False 또는 임시 폴더.
"""
from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parents[4]
BF = PROJECT_ROOT / "04_Research" / "decision_framework" / "bearish_forecast_v3"
STUDY_OUT = PROJECT_ROOT / "04_Research" / "01_reports" / "k200_risk_accuracy_20261113" / "output"
SEED = STUDY_OUT / "fc_DR_newsvk.meta.json"


def _load(name, p):
    s = importlib.util.spec_from_file_location(name, str(p)); m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m


R602 = _load("r602", BF / "scripts" / "602_h1_daily_inference.py")
G = R602.G
cfg = G.load_config()
BM = pd.read_parquet(PROJECT_ROOT / ".cache" / "benchmark.parquet"); BM["Date"] = pd.to_datetime(BM["Date"])
IX = pd.read_parquet(PROJECT_ROOT / ".cache" / "indices.parquet", columns=["Date", "kospi200_vol"]); IX["Date"] = pd.to_datetime(IX["Date"])
ASOF = BM["Date"].max()
results = []


def codes(g):
    return {"block": sorted({x["code"] for x in g["block"]}), "warn": sorted({x["code"] for x in g["warn"]})}


def run_case(name, expect_block, asof=ASOF, bm=None, ix=None, live=True, backfill_from=None, pick=None):
    with tempfile.TemporaryDirectory() as td:
        r = R602.run(asof, Path(td), live, backfill_from=backfill_from, seed_meta=SEED,
                     bm=(bm if bm is not None else BM.copy()), ix=(ix if ix is not None else IX.copy()), cfg=cfg, write=False)
    gs = r["guards"] if pick is None else [g for g in r["guards"] if g["asof"] in pick]
    for g in gs:
        c = codes(g)
        blocked = bool(c["block"])
        exp = expect_block(g["asof"]) if callable(expect_block) else expect_block
        ok = (blocked == exp)
        results.append({"case": name, "asof": g["asof"], "expect_block": exp, "blocked": blocked, "ok": ok, **c,
                        "sigma": g["info"].get("sigma"), "var_01": g["info"].get("var_01"), "vk": g["info"].get("vk"),
                        "msgs": [x["msg"] for x in g["block"]][:2]})
        print(f"{'OK ' if ok else 'BAD'} {name:28s} {g['asof']} block={c['block']} warn={c['warn']} σ={g['info'].get('sigma')}")


# C0 평상(오늘 기준일) — 막지 않는다
run_case("C0 normal live", False)
# C2 실제 자료 오류 재생 — 2019-04-10 V-KOSPI 30.40(전후 12.7 · 12.3) · 다음 날 되돌림
run_case("C2 vk spike 2019-04-10", lambda d: d in ("2019-04-10", "2019-04-11"), asof=pd.Timestamp("2019-04-12"),
         live=False, backfill_from="2019-04-08")
# C9 실제 급락 재생 — 2024-08-05(KOSPI200 −9.6% · V-KOSPI +0.75 log) 는 막지 않는다
run_case("C9 real shock 2024-08", False, asof=pd.Timestamp("2024-08-09"), live=False, backfill_from="2024-08-01")
# C10 사고 기간 재생(현재 자료) — H1 은 막지 않는다
run_case("C10 incident window H1", False, asof=pd.Timestamp("2026-08-10"), live=False, backfill_from="2026-07-27")
# C3 V-KOSPI 단위 착오(×100)
ix = IX.copy(); ix.loc[ix["Date"] == ASOF, "kospi200_vol"] *= 100; run_case("C3 vk x100", True, ix=ix)
# C4 V-KOSPI 기준일 결측
ix = IX.copy(); ix = ix[ix["Date"] != ASOF]; run_case("C4 vk missing", True, ix=ix)
# C5 V-KOSPI 전일 값 반복 — 경고만
ix = IX.copy(); prev = ix[ix["Date"] < ASOF]["kospi200_vol"].dropna().iloc[-1]; ix.loc[ix["Date"] == ASOF, "kospi200_vol"] = prev
run_case("C5 vk repeat (warn)", False, ix=ix)
# C6 벤치 당일 +40%(가격제한폭 밖)
bm = BM.copy(); i = bm.index[bm["Date"] == ASOF][0]; bm.loc[i, "BM_Close"] = bm.loc[i - 1, "BM_Close"] * 1.40
run_case("C6 bench +40%", True, bm=bm)
# C7 운영 기준일 ≠ 벤치 최신일
run_case("C7 live asof stale", True, asof=pd.Timestamp(BM["Date"].iloc[-2]))
# C8 실제형 충격(V-KOSPI ×1.9 + 지수 −8%) — B7 아님 · 물리 한계 안이면 막지 않는다
bm = BM.copy(); ix = IX.copy(); i = bm.index[bm["Date"] == ASOF][0]
bm.loc[i, "BM_Close"] = bm.loc[i - 1, "BM_Close"] * np.exp(-0.08); ix.loc[ix["Date"] == ASOF, "kospi200_vol"] *= 1.9
run_case("C8 shock-like inject", lambda d: False, bm=bm, ix=ix)
# C11 V-KOSPI ×1.9 인데 지수 정지(−0.2%) — B7 로 막는다
bm = BM.copy(); ix = IX.copy(); i = bm.index[bm["Date"] == ASOF][0]
bm.loc[i, "BM_Close"] = bm.loc[i - 1, "BM_Close"] * np.exp(-0.002); ix.loc[ix["Date"] == ASOF, "kospi200_vol"] *= 1.9
run_case("C11 vk x1.9 calm index", True, bm=bm, ix=ix)

# C1 실제 사고 값 — 운영 P3 기록(2026-07-31~08-07) 은 대체 발송 점검(B6)에서 막혀야 하고, 앞뒤 평상 행은 통과
p3 = pd.read_parquet(BF / "03_models" / "daily_predictions" / "P3_daily.parquet"); p3["Date"] = pd.to_datetime(p3["Date"])
b = G.bench_frame(BM, cfg["ewma_lambda"]).set_index("Date")
for d in ["2026-07-27", "2026-07-31", "2026-08-03", "2026-08-04", "2026-08-06", "2026-08-07", "2026-08-12"]:
    row = p3[p3["Date"] == pd.Timestamp(d)].iloc[0].to_dict()
    ok_, blk, wrn = G.p3_fallback_check({**row, "asof_date": d}, d, float(b.loc[pd.Timestamp(d), "ewma"]), cfg)
    exp = d not in ("2026-07-27", "2026-08-12")
    blocked = not ok_
    results.append({"case": "C1 P3 incident rows", "asof": d, "expect_block": exp, "blocked": blocked, "ok": blocked == exp,
                    "block": sorted({x['code'] for x in blk}), "warn": sorted({x['code'] for x in wrn}),
                    "sigma": float(row["sigma"]), "var_01": float(row["var_01"])})
    print(f"{'OK ' if blocked == exp else 'BAD'} C1 P3 incident rows        {d} blocked={blocked} σ={row['sigma']:.2f} VaR1={row['var_01']:.1f}")

n_ok = sum(r["ok"] for r in results)
out = {"made_at": pd.Timestamp.now().isoformat(timespec="seconds"), "guard_config_version": cfg["version"],
       "benchmark_max_date": str(ASOF.date()), "n": len(results), "n_ok": n_ok, "results": results}
p = Path(__file__).resolve().parent / "h1_guard_controls.json"
p.write_text(json.dumps(out, ensure_ascii=False, indent=2, default=lambda o: None if isinstance(o, float) and not np.isfinite(o) else str(o)), encoding="utf-8")
print(f"[controls] {n_ok}/{len(results)} ok → {p}")
sys.exit(0 if n_ok == len(results) else 1)
