"""h1_guard.py — K200 일간 위험 브리핑 입력 · 출력 점검(H1 본 모형 · P3 대체 판단).

도훈 결정 K200-RISK-H1-REPLACE-P3-20261114 조건 ① "이상 입력 점검(σ 급등 등 7/31~8/7 같은 값 차단)".
사고: 2026-07-31~08-07 운영 P3 브리핑 5회가 σ 20.9~44.5% · VaR 1% −68~−113% 를 그대로 발송했다(현재 자료 재현 4.8~7.0%).
      점검 장치가 없었다(연구 04_Research/01_reports/k200_risk_accuracy_20261113 · production_audit.json).

두 층:
  차단(BLOCK) — 그 모형 수치를 발송하지 않는다. H1 차단이면 P3 대체(자료 점검 통과 + P3 물리 한계 통과일 때만), 둘 다 안 되면 보류.
    B1 기준일   벤치 종가 최신일 = 예측 기준일(asof) — 운영 실행만
    B2 벤치 값   종가 유한 · 양수 · 날짜 중복 없음 · 당일 로그수익이 가격제한폭 물리 한계 안
    B3 V-KOSPI  기준일 값 존재 · 유한 · 양수 · 역대 범위(이전 자료)의 [하한 배수 × 최저, 상한 배수 × 최고] 안 — 단위 · 열 착오
    B4 특징     7개 특징 유한
    B5 적합     모수 유한 · 학습 행 ≥ 1008 · ν ∈ (2.05, 200)
    B6 물리 한계 σ 유한 · 양수 · VaR 1% ≥ 가격제한폭 하한(지수 일간 로그수익은 100·ln(0.7) 밑으로 갈 수 없다)
    B7 V-KOSPI 급변 · 지수 정지 — |Δlog VK| > 역대 99.9% 분위 이면서 |r_t| < k × EWMA σ(t−1): 하루 튄 자료 오류 형태(2019-04-10 실례)
  경고(WARN) — 발송하되 브리핑에 표시한다.
    W1 σ/EWMA 비가 그 모형 워크포워드 역사 범위 밖 · W2 σ 전일 대비 비가 역사 범위 밖 · W3 특징이 학습 창 범위 밖(외삽)
    W4 V-KOSPI 전일과 같은 값(갱신 누락 의심) · W6 과거 실현 수익 개정(저장 기록과 현재 자료 차이)
문턱 수치는 h1_guard_config.json(604_h1_guard_calibrate.py 가 자료에서 계산 · 근거 문서화)에서만 읽는다.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pandas as pd

CONFIG_PATH = Path(__file__).resolve().parent / "h1_guard_config.json"


def load_config(path: Path | None = None) -> dict:
    return json.loads(Path(path or CONFIG_PATH).read_text(encoding="utf-8"))


def ewma_sigma(r_pct: np.ndarray, lam: float) -> np.ndarray:
    """RiskMetrics EWMA — σ²_t = λσ²_{t−1} + (1−λ) r_t² (t 의 값 = t+1 예측). 초깃값 = 처음 60개 수익 분산."""
    r = np.asarray(r_pct, float)
    r0 = np.nan_to_num(r, nan=0.0)
    s2 = np.empty(len(r))
    s2[0] = np.nanvar(r[1:61])
    for i in range(1, len(r)):
        s2[i] = lam * s2[i - 1] + (1.0 - lam) * r0[i] ** 2
    return np.sqrt(s2)


def bench_frame(bm: pd.DataFrame, lam: float) -> pd.DataFrame:
    b = bm[["Date", "BM_Close"]].copy()
    b["Date"] = pd.to_datetime(b["Date"]); b = b.sort_values("Date").reset_index(drop=True)
    b["r"] = np.log(b["BM_Close"]).diff() * 100.0
    b["ewma"] = ewma_sigma(b["r"].values, lam)
    b["ewma_prev"] = b["ewma"].shift(1)
    return b


def _item(code, msg, **kv):
    d = {"code": code, "msg": msg}
    d.update({k: (None if (isinstance(v, float) and not math.isfinite(v)) else v) for k, v in kv.items()})
    return d


def check_bench(b: pd.DataFrame, asof, cfg: dict, live: bool) -> tuple[list, list, dict]:
    """자료(벤치마크) 점검 — 모든 모형 공통. 반환 (block, warn, info)."""
    block, warn = [], []
    asof = pd.Timestamp(asof)
    pl = cfg["price_limit"]
    info = {"bm_max": str(b["Date"].max().date()) if len(b) else None}
    if asof not in set(b["Date"]):
        block.append(_item("B1", f"벤치 종가에 기준일 {asof.date()} 행이 없다"))
        return block, warn, info
    if live and b["Date"].max() != asof:
        block.append(_item("B1", f"벤치 최신일 {b['Date'].max().date()} ≠ 기준일 {asof.date()}"))
    tail = b[b["Date"] <= asof].tail(300)
    if tail["Date"].duplicated().any():
        block.append(_item("B2", "벤치 최근 300행에 날짜 중복"))
    if not (np.isfinite(tail["BM_Close"]).all() and (tail["BM_Close"] > 0).all()):
        block.append(_item("B2", "벤치 최근 300행 종가가 유한 · 양수가 아니다"))
    row = b[b["Date"] == asof].iloc[-1]
    r_t = float(row["r"])
    info.update({"r_t": r_t, "ewma_t": float(row["ewma"]), "ewma_prev": float(row["ewma_prev"])})
    if not math.isfinite(r_t):
        block.append(_item("B2", "당일 로그수익이 유한하지 않다"))
    elif r_t < pl["down_log_pct"] or r_t > pl["up_log_pct"]:
        block.append(_item("B2", f"당일 로그수익 {r_t:+.2f}% 가 가격제한폭 물리 한계 밖", r_t=r_t))
    return block, warn, info


def check_vk(ix: pd.DataFrame, asof, info_bm: dict, cfg: dict) -> tuple[list, list, dict]:
    """V-KOSPI200 점검 — H1 전용 입력."""
    block, warn = [], []
    asof = pd.Timestamp(asof)
    v = ix[["Date", "kospi200_vol"]].copy(); v["Date"] = pd.to_datetime(v["Date"])
    v = v.dropna(subset=["kospi200_vol"]).sort_values("Date")
    cur = v[v["Date"] == asof]
    info = {"vk_max_date": str(v["Date"].max().date()) if len(v) else None}
    if len(cur) == 0:
        block.append(_item("B3", f"V-KOSPI200 에 기준일 {asof.date()} 값이 없다(최신 {info['vk_max_date']})"))
        return block, warn, info
    vk = float(cur["kospi200_vol"].iloc[-1])
    hist = v[v["Date"] < asof]["kospi200_vol"]
    info["vk"] = vk
    c3 = cfg["b3_vk_range"]
    if not (math.isfinite(vk) and vk > 0):
        block.append(_item("B3", f"V-KOSPI200 값 {vk} 이 유한 · 양수가 아니다"))
        return block, warn, info
    if len(hist):
        lo, hi = c3["lo_factor"] * float(hist.min()), c3["hi_factor"] * float(hist.max())
        info.update({"vk_hist_min": float(hist.min()), "vk_hist_max": float(hist.max())})
        if vk < lo or vk > hi:
            block.append(_item("B3", f"V-KOSPI200 {vk:.2f} 가 역대 범위 밖(허용 {lo:.2f}~{hi:.2f})", vk=vk))
        prev = float(hist.iloc[-1])
        dl = math.log(vk / prev)
        info.update({"vk_prev": prev, "vk_dlog": dl})
        c7 = cfg["b7_vk_jump"]
        r_t, ew_prev = info_bm.get("r_t", float("nan")), info_bm.get("ewma_prev", float("nan"))
        if abs(dl) > c7["abs_dlog"] and math.isfinite(r_t) and math.isfinite(ew_prev) and abs(r_t) < c7["index_move_k"] * ew_prev:
            block.append(_item("B7", f"V-KOSPI200 {prev:.2f}→{vk:.2f}(log {dl:+.2f}) 급변인데 지수는 {r_t:+.2f}%(EWMA σ {ew_prev:.2f}% 미만) — 자료 오류 형태",
                               vk=vk, vk_prev=prev))
        if vk == prev:
            warn.append(_item("W4", f"V-KOSPI200 이 전일과 같은 값({vk:.2f}) — 갱신 누락 의심"))
    return block, warn, info


def check_fit(fr: dict, feats_x: np.ndarray, train_min_rows: int) -> tuple[list, list]:
    block, warn = [], []
    th = np.asarray(fr["theta"], float)
    if not np.isfinite(th).all() or not math.isfinite(fr["nll"]):
        block.append(_item("B5", "적합 모수 · 우도가 유한하지 않다"))
    if fr["n"] < train_min_rows:
        block.append(_item("B5", f"학습 행 {fr['n']} < {train_min_rows}"))
    if not np.isfinite(np.asarray(feats_x, float)).all():
        block.append(_item("B4", "기준일 특징에 결측 · 무한"))
    return block, warn


def check_output(o: dict, met: dict, ewma_t: float, sigma_prev: float | None, z: np.ndarray | None,
                 fr: dict | None, feats: tuple, cfg: dict, band_key: str = "w1_ratio_ewma") -> tuple[list, list, dict]:
    """출력 점검 — B6 물리 한계(차단) · W1 · W2 · W3(경고)."""
    block, warn = [], []
    pl = cfg["price_limit"]
    sg = float(o["sigma"])
    info = {"sigma": sg, "var_01": float(met["var_01"]), "ewma_t": ewma_t}
    if not (math.isfinite(sg) and sg > 0):
        block.append(_item("B6", f"σ {sg} 가 유한 · 양수가 아니다"))
        return block, warn, info
    if not math.isfinite(met["var_01"]) or met["var_01"] < pl["down_log_pct"]:
        block.append(_item("B6", f"VaR 1% {met['var_01']:+.2f}% 가 가격제한폭 하한 {pl['down_log_pct']:.2f}% 밑(σ {sg:.2f}%)",
                           sigma=sg, var_01=float(met["var_01"])))
    nu = o.get("nu")
    if nu is not None and not (2.05 < float(nu) < 200):
        block.append(_item("B5", f"ν {nu} 범위 밖"))
    band = cfg.get(band_key)
    if band and math.isfinite(ewma_t) and ewma_t > 0:
        ratio = sg / ewma_t
        info["ratio_ewma"] = ratio
        if ratio < band["lo"] or ratio > band["hi"]:
            warn.append(_item("W1", f"σ/EWMA {ratio:.2f}배 — 워크포워드 역사 범위({band['lo']:.2f}~{band['hi']:.2f}) 밖", ratio=ratio))
    c2 = cfg.get("w2_day_over_day")
    if c2 and sigma_prev is not None and math.isfinite(sigma_prev) and sigma_prev > 0 and band_key == "w1_ratio_ewma":
        dod = sg / sigma_prev
        info["dod"] = dod
        if dod < c2["lo"] or dod > c2["hi"]:
            warn.append(_item("W2", f"σ 전일 대비 {dod:.2f}배({sigma_prev:.2f}%→{sg:.2f}%) — 역사 범위({c2['lo']:.2f}~{c2['hi']:.2f}) 밖", dod=dod))
    if z is not None and fr is not None and fr.get("z_min") is not None:
        zc = np.clip(z, fr["z_min"], fr["z_max"])
        out = [f for f, zz, cc in zip(feats, z, zc) if zz != cc]
        if out:
            a = np.asarray(fr["theta"], float)[2:2 + len(feats)]
            eff = float(np.exp(np.sum(a * (np.asarray(z) - zc))) - 1.0)   # 범위 밖 부분이 σ 를 바꾼 비율
            c3 = cfg.get("w3_extrapolation", {})
            info.update({"extrap_feats": out, "extrap_sigma_effect": eff})
            warn.append(_item("W3", f"학습 창 범위 밖 입력(외삽): {', '.join(out)} — 범위 밖 부분의 σ 영향 {eff:+.1%}",
                              sigma_effect=eff, material=bool(abs(eff) >= c3.get("show_if_abs_effect_ge", 0.0))))
    return block, warn, info


def p3_fallback_check(p3: dict | None, asof, ewma_t: float, cfg: dict) -> tuple[bool, list, list]:
    """P3 대체 가능 여부 — 기준일 일치 · B6 물리 한계. W1 은 P3 자기 범위."""
    if p3 is None:
        return False, [_item("P3", "P3_latest.json 없음")], []
    if str(p3.get("asof_date")) != str(pd.Timestamp(asof).date()):
        return False, [_item("P3", f"P3 기준일 {p3.get('asof_date')} ≠ {pd.Timestamp(asof).date()}")], []
    o = {"sigma": p3.get("sigma"), "nu": None}
    met = {"var_01": p3.get("var_01")}
    try:
        b, w, _ = check_output(o, met, ewma_t, None, None, None, (), cfg, band_key="p3_w1_ratio_ewma")
    except Exception as e:  # noqa: BLE001
        return False, [_item("P3", f"P3 점검 실패: {e}")], []
    return (len(b) == 0), b, w


def status_of(block: list, warn: list) -> str:
    return "BLOCK" if block else ("WARN" if warn else "PASS")
