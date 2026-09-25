#!/usr/bin/env python
"""ae_pit_features.py — AE(D3 게이트) 특성 패널의 가용시점 결합 (PIT C11 수리 1단계 · S5).

★무엇을 고치나 (판정서 V-03 · V-02 — 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md)
  동결 원본(stage_artifacts/WT_D20260718_007/ae_regime_extend.py:34-48)과 백필기(ae_regime_backfill.py:69-83)는
  해외 특성을 `pd.merge_asof(spine, fred, on="Date", direction="backward")` 로 붙였다. FRED 의 Date 는 **미국
  관측일(주간·월간은 라벨일)** 이라 한국 d 행에
    · 미국 d 종가(VIX·금리 — 한국 d 종가 뒤 미국 세션)와
    · 공표 전 주간값(StL_Fin_Stress=STLFSI4 라벨 +7일 · Chi_Fin_Cond=NFCI 라벨 +6일)
  이 들어갔다. 실측: 보유 시작 시점 미공표 STLFSI4 171/223 · NFCI 140/223 결정(V3 s8_aeleak.R), L1 신호일 종가
  체결로는 같은 날짜 미국 월말 종가 218/223개월(V3 s12_arm.R).

★원칙 (판정서 ② · 형태 (a)): 관측마다 가용일을 붙이고 **가용일로** 결합한다.
  한국 행 t 의 해외 특성 = 한국 t 일 15:30 결정에 쓸 수 있었던 최신 관측(fred_asof_join mode="decision_close").
  행마다 자기 날짜의 정보집합만 담으므로, 결정일 d 의 창(행 < d)은 어떤 집행 규약(신호일 종가·익일 종가·월초 집행)
  에서도 결정 시점 이전 정보만 쓴다. 오프셋·규칙 수치는 이 파일에 없다 — 전부 기반(S0) 규칙 파일
  06_Registry/fred_availability_rules.json 이 정본이고 결합은 02_Infrastructure/data/fred_availability.py 만 경유한다.

★원/달러 (결정 PIT-C11-CONVENTIONS ①): FRED DEXKOUS(와이드 열 'KRW_USD')는 규칙 파일에서 prohibited 다.
  모델 입력 열 이름 'KRW_USD' 는 그대로 두고 원천만 ECOS 731Y001(.cache/ecos_krw_usd.parquet · 계열 id
  ECOS_KRW_USD · 판정서 ② '한국 적용일, 값은 전 거래일 세션 → lag 0 적합(검증됨)')으로 바꾼다.

★한국 거래일 달력 = 핀된 벤치마크의 날짜 집합(핀 재현성 — 라이브 달력을 섞지 않는다). 벤치마크에 빠진 날이
  있으면 가용일이 그만큼 **늦어질 뿐**(보수 방향)이고, 달력 끝 이후로 떨어지는 가용일은 NA = 아직 불가다.

★산출 표식(소비자 검증용 계약 — pg2_risk_overlay.R · 배포 생성기 promote 패치가 읽는다)
    c11_feat_join      = FEAT_JOIN (이 빌더를 거쳤다는 표지)
    c11_regime_key     = fred_avail_rules_meta()['regime_key'] (규칙 epoch)
    c11_fred_avail_max = 결정 창(행 ≤ last_feat_date)에 실린 해외 관측 가용일의 최댓값
    c11_info_cutoff    = max(last_feat_date, c11_fred_avail_max) — 이 결정이 쓴 정보가 전부 가용해진 한국 날짜
                         (그 날 15:30 결정 기준). 소비자는 이 값 ≤ 자기 결정일 을 확인한다.

★빈티지: 값은 최신 빈티지다(안 C 전까지 C1·C11 미해소 — 판정서 ② '빈티지'). 개정 계열(NFCI·STLFSI4)은
  fred_asof_join 이 vintage_resolved=False 를 단다. 이 층은 공표 시점만 고친다.
  ★r1(V5 BLOCKING · 판정서 ② '최신 빈티지 라벨을 달고 C1·C11 미해소로 둔다' · 안 B '라벨로 명시'): 그 라벨을 버리지 않고
  산출 행에 싣는다 — c11_vintage = 'latest' · c11_vintage_resolved(모든 해외 입력이 개정 없는 계열일 때만 True) ·
  c11_vintage_unresolved = 미해소 계열 id(쉼표). 표식 열(PROVENANCE_COLS)에 포함 — 빠진 산출은 is_c11_stamped=False.
"""
from __future__ import annotations

import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

_HERE = os.path.dirname(os.path.abspath(__file__))
_DATA_DIR = os.path.join(os.path.dirname(_HERE), "data")
if _DATA_DIR not in sys.path:
    sys.path.insert(0, _DATA_DIR)
import fred_availability as fa  # noqa: E402  (S0 기반 도우미 — 규칙 수치 없음)

FEAT_JOIN = "c11_avail_decision_close"
KR_FEATS = ["klog", "kvol20", "kcum20", "kcum60"]
ECOS_KRW_FILE = "ecos_krw_usd.parquet"
# 모델 입력 열 → 원천 교체(결정 PIT-C11-CONVENTIONS ①). 나머지 해외 열은 와이드 파일의 같은 이름 열을 쓰고,
# 계열 id 는 열 이름 그대로 넘긴다 — 규칙 파일의 aliases(VIX→VIXCLS 등)가 해석하고, 규칙 없는 열은 거부된다.
SOURCE_OVERRIDES = {
    "KRW_USD": {"file": ECOS_KRW_FILE, "series_id": "ECOS_KRW_USD", "value_col": "KRW_USD"},
}
VINTAGE_COLS = ["c11_vintage", "c11_vintage_resolved", "c11_vintage_unresolved"]
PROVENANCE_COLS = ["c11_feat_join", "c11_regime_key", "c11_fred_avail_max", "c11_info_cutoff"] + VINTAGE_COLS


class AEPitError(RuntimeError):
    """C11 가용시점 결합의 fail-closed 거부(입력 부재·자기 검사 위반)."""


def build_kr_spine(bench_path: str) -> pd.DataFrame:
    """한국 측 특성 — 동결 원본 ae_regime_extend.py:36-43 과 같은 식(국내 종가, C11 무관)."""
    bm = pq.read_table(bench_path).to_pandas()
    bm["Date"] = pd.to_datetime(bm["Date"])
    bm = bm.sort_values("Date").reset_index(drop=True)
    c = bm["BM_Close"].astype(float).values
    bm["kret"] = bm["BM_Ret"].astype(float)
    bm["klog"] = np.log(c / np.roll(c, 1))
    bm.loc[0, "klog"] = np.nan
    bm["kvol20"] = bm["kret"].rolling(20, min_periods=10).std()
    bm["kcum20"] = c / np.concatenate([np.full(20, np.nan), c[:-20]]) - 1.0
    bm["kcum60"] = c / np.concatenate([np.full(60, np.nan), c[:-60]]) - 1.0
    return bm[["Date", "kret", "klog", "kvol20", "kcum20", "kcum60"]].copy()


def _series_frame(feat: str, fred: pd.DataFrame | None, ecos_path: str | None):
    """feat 의 (Date, Value) 시계열과 계열 id. 결측 값 행은 버린다(결합 모호성 방지)."""
    src = SOURCE_OVERRIDES.get(feat)
    if src is not None:
        if not ecos_path or not os.path.exists(ecos_path):
            raise AEPitError(
                f"[ae_pit] '{feat}' 원천 {src['file']} 부재({ecos_path}) — DEXKOUS 는 prohibited(PIT-C11-CONVENTIONS ①). "
                f"핀에 ECOS 원/달러가 없으면 수리 전 핀이다: --advance-pin 으로 새 핀을 떠라")
        e = pq.read_table(ecos_path).to_pandas()
        if src["value_col"] not in e.columns or "Date" not in e.columns:
            raise AEPitError(f"[ae_pit] {ecos_path} 에 Date/{src['value_col']} 열 없음")
        df = pd.DataFrame({"Date": pd.to_datetime(e["Date"]), "Value": e[src["value_col"]].astype(float)})
        sid = src["series_id"]
    else:
        if fred is None or feat not in fred.columns:
            raise AEPitError(f"[ae_pit] 해외 특성 열 '{feat}' 이 FRED 와이드 파일에 없음")
        df = pd.DataFrame({"Date": pd.to_datetime(fred["Date"]), "Value": fred[feat].astype(float)})
        sid = feat
    df = df[np.isfinite(df["Value"].values)].sort_values("Date").reset_index(drop=True)
    return df, sid


def build_pit_panel(fred_path: str, bench_path: str, ecos_path: str | None, fred_feats: list[str],
                    rules=None, kr_calendar=None):
    """동결 원본 build_panel() 의 PIT 판 — 같은 반환형 (panel, feat_cols).

    panel 열: Date · kret · KR_FEATS · fred_feats(가용일 결합 값) · c11_row_avail_max · _avail_<feat> · _obs_<feat>.
    동결 원본 main 은 panel['Date'] 와 panel[feat_cols] 만 읽으므로 나머지 열은 소비 경로에 영향이 없다.
    """
    for p in (fred_path, bench_path):
        if not os.path.exists(p):
            raise AEPitError(f"[ae_pit] 입력 부재: {p}")
    fred = pq.read_table(fred_path).to_pandas()
    fred["Date"] = pd.to_datetime(fred["Date"])
    spine = build_kr_spine(bench_path)
    kr_dates = list(spine["Date"])
    cal = kr_calendar if kr_calendar is not None else sorted(set(d.date() for d in spine["Date"]))
    m = spine.copy()
    unresolved = []                     # r1: fred_asof_join 의 vintage_resolved=False 계열(버리지 않는다)
    for f in fred_feats:
        df, sid = _series_frame(f, fred, ecos_path)
        try:
            j = fa.fred_asof_join(kr_dates, df, sid, mode="decision_close", kr_calendar=cal, rules=rules,
                                  extend_calendar=False)
        except fa.FredAvailError as e:
            raise AEPitError(f"[ae_pit] '{f}'(계열 {sid}) 결합 거부: {e}") from e
        # 빈티지 라벨 판독 — 결합 산출에 vintage_resolved 가 없으면(대체 결합기 등) 해소 여부를 모른다 = 미해소(fail-closed)
        vr = j["vintage_resolved"] if "vintage_resolved" in getattr(j, "columns", []) else None
        if vr is None or not bool(pd.Series(vr).astype(bool).all()):
            unresolved.append(str(sid))
        m[f] = pd.to_numeric(j["value"], errors="coerce").astype(float).values
        m[f"_avail_{f}"] = pd.to_datetime(j["avail_date"]).values
        m[f"_obs_{f}"] = pd.to_datetime(j["obs_date"]).values
        # ── 자기 검사(양성 대조가 아니라 독립 경로 재검): 결합된 (행 날짜, 관측일) 쌍을 규칙으로 다시 잰다 ──
        ok = m[f"_obs_{f}"].notna().values
        viol = fa.fred_join_violations([d.date() for d in m.loc[ok, "Date"]],
                                       [d.date() for d in m.loc[ok, f"_obs_{f}"]],
                                       sid, mode="decision_close", kr_calendar=cal, rules=rules)
        if viol:
            v0 = viol[0]
            raise AEPitError(f"[ae_pit] ★C11 자기 검사 위반 '{f}'({sid}) {len(viol)}행 — 예: 한국 {v0['kr_date']} 행에 "
                             f"관측 {v0['obs_date']}(가용 {v0['avail_date']}) · {v0['reason']}")
    feat_cols = KR_FEATS + list(fred_feats)
    # 국내 특성만 동결 원본처럼 ffill. 해외 특성은 결합 자체가 '가용한 최신 관측'(가용일 기준 LOCF)이라 ffill 대상이 아니다.
    m[KR_FEATS] = m[KR_FEATS].ffill()
    m = m.dropna(subset=feat_cols).reset_index(drop=True)
    m["c11_vintage_unresolved"] = ",".join(sorted(set(unresolved)))
    av = m[[f"_avail_{f}" for f in fred_feats]]
    m["c11_row_avail_max"] = av.max(axis=1)
    bad = int((m["c11_row_avail_max"] > m["Date"]).sum())
    if bad:
        raise AEPitError(f"[ae_pit] ★C11 행 불변식 위반 {bad}행 — 해외 관측 가용일 > 한국 행 날짜")
    return m, feat_cols


def rules_regime_key(rules_path: str | None = None) -> str:
    return fa.fred_avail_rules_meta(rules_path)["regime_key"]


def decision_provenance(panel: pd.DataFrame, last_feat_dates) -> pd.DataFrame:
    """결정 행마다 c11_fred_avail_max · c11_info_cutoff 를 잰다(창 = 패널 행 ≤ last_feat_date)."""
    if panel is None or "c11_row_avail_max" not in getattr(panel, "columns", []):
        raise AEPitError("[ae_pit] ★C11 패널에 c11_row_avail_max 없음 — build_pit_panel 산출이 아니다(가용시점 결합 미경유)")
    d = pd.to_datetime(panel["Date"]).values
    cm = pd.Series(pd.to_datetime(panel["c11_row_avail_max"]).values).cummax().values
    lf = pd.to_datetime(pd.Series(last_feat_dates)).values
    idx = np.searchsorted(d, lf, side="right") - 1
    fam = np.array([cm[i] if i >= 0 else np.datetime64("NaT") for i in idx], dtype="datetime64[ns]")
    cut = np.where(np.isnat(fam), lf, np.maximum(fam, lf))
    return pd.DataFrame({"c11_fred_avail_max": fam, "c11_info_cutoff": cut})


def stamp(df: pd.DataFrame, panel: pd.DataFrame, regime_key: str) -> pd.DataFrame:
    """AE 산출 행(decision_date · last_feat_date)에 C11 표식 4열을 붙인다. 행 불변식 위반이면 거부."""
    out = df.copy()
    pv = decision_provenance(panel, out["last_feat_date"])
    out["c11_feat_join"] = FEAT_JOIN
    out["c11_regime_key"] = regime_key
    out["c11_fred_avail_max"] = pv["c11_fred_avail_max"].values
    out["c11_info_cutoff"] = pv["c11_info_cutoff"].values
    # r1: 빈티지 라벨 — 패널이 기록한 미해소 계열을 그대로 싣는다(없으면 'unknown' = 미해소로 본다 · fail-closed)
    vu = (str(panel["c11_vintage_unresolved"].iloc[0])
          if "c11_vintage_unresolved" in getattr(panel, "columns", []) and len(panel) else "unknown")
    out["c11_vintage"] = "latest"
    out["c11_vintage_unresolved"] = vu
    out["c11_vintage_resolved"] = (vu == "")
    lfd = pd.to_datetime(out["last_feat_date"])
    if int((pd.to_datetime(out["c11_fred_avail_max"]) > lfd).sum()):
        raise AEPitError("[ae_pit] ★C11 표식 위반 — 창의 해외 가용일 > last_feat_date")
    if int((pd.to_datetime(out["c11_info_cutoff"]) >= pd.to_datetime(out["decision_date"])).sum()):
        raise AEPitError("[ae_pit] ★C11 표식 위반 — c11_info_cutoff >= decision_date")
    return out


def is_c11_stamped(df: pd.DataFrame, regime_key: str | None = None) -> bool:
    """표식 4열이 있고 전 행이 이 빌더 산출인가(regime_key 를 주면 규칙 epoch 까지 대조)."""
    if not all(c in df.columns for c in PROVENANCE_COLS):
        return False
    if not len(df):
        return True
    if not (df["c11_feat_join"].astype(str) == FEAT_JOIN).all():
        return False
    if pd.to_datetime(df["c11_info_cutoff"]).isna().any():
        return False
    if regime_key is not None and not (df["c11_regime_key"].astype(str) == regime_key).all():
        return False
    return True
