# -*- coding: utf-8 -*-
"""
FQ-236 Lane D — 조건변수 S 후보 월간 정렬 패널 생성 (C5 홀딩월-시작-전 + C11 계열별 발표시차 주입)

★계열별 lag 테이블을 **어댑터가 직접 주입**한다 (ctx_providers 는 계열별 시차를 대행하지 않음 — C11).
★본 스크립트는 후보를 전부 정렬해두기만 한다. **어느 계열을 PRIMARY 로 쓸지는 alpha-hypothesis 재설계
  산출(alpha_hypothesis_rev2.json)이 지정**하며, 여기서 결과를 보고 고르지 않는다(sweep 금지).
"""
import os, json
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts", "WT-D20260822_001")

# ── 계열별 발표시차 테이블 (calendar days). 근거를 값 옆에 같이 둔다. ──────────────
LAG_TABLE = {
    "KR_CredSpread_BBB": (3, "rev2 지정: ECOS 일별 금리 익영업일 공표, 최악 경로(금 관측→월 게시)=달력 3일"),
    "KR_CredSpread_AA":  (3, "동일 (회사채AA-·국고3년)"),
    "KR_TermSpread":     (3, "ECOS 국고10년-3년"),
    "KR_Call_CD_Spread": (3, "ECOS CD91-콜1D (단기 자금시장 경색). CD91 은 2005-08~"),
    "StL_Fin_Stress":    (7, "FRED STLFSI4 주간 — 목요일 공표, 직전 금요일 종료 주 기준 ⇒ 최대 7일"),
    "Chi_Fin_Cond":      (7, "FRED NFCI 주간 — 수요일 공표, 직전 금요일 종료 주 기준 ⇒ 최대 7일"),
    "VIX":               (1, "일별 종가, 익일 가용"),
    "US_TermSpread":     (1, "FRED T10Y2Y 일별"),
    "breadth_bear_prob": (0, "smv 패널이 effective_date(T+2) 를 자체 보유 — 컷오프는 effective_date 로 적용(추가 lag 주입 없음)"),
}

# ── 결정일: 홀딩월 첫 거래일 ─────────────────────────────────────────────────
cen = pd.read_csv(os.path.join(OUT, "universe_membership_census.csv"))
cen['ym_d'] = pd.to_datetime(cen['ym'] + "-01")
cen['d0'] = pd.to_datetime(cen['d0'])
# 홀딩월 첫 거래일 = d0 의 다음 거래일. 거래일 달력에서 복원
cal = pq.read_table(os.path.join(ROOT, ".cache/RAWDATA.parquet"), columns=['Date'],
                    filters=[('Date', '>=', pd.Timestamp('1998-01-01').date())]).to_pandas()
tdays = np.sort(pd.to_datetime(cal['Date'].unique()))
pos = {d: i for i, d in enumerate(tdays)}
cen['first_td'] = [tdays[pos[d] + 1] for d in cen['d0']]

# ── 원천 로드 ────────────────────────────────────────────────────────────────
ec = pq.read_table(os.path.join(ROOT, ".cache/ecos_bond_rates.parquet")).to_pandas()
ec['Date'] = pd.to_datetime(ec['Date'])
ecw = ec.pivot_table(index='Date', columns='Series', values='Value')

fr = pq.read_table(os.path.join(ROOT, ".cache/fred_macro_wide.parquet")).to_pandas()
fr['Date'] = pd.to_datetime(fr['Date'])
fr = fr.set_index('Date')

smv = pq.read_table(os.path.join(ROOT, "outputs/ramp/smv_factor_regime_daily.parquet")).to_pandas()
smv['effective_date'] = pd.to_datetime(smv['effective_date'])
br = smv.groupby('effective_date')['bear_prob'].mean().sort_index()   # 6 factor 평균

series = {
    "KR_CredSpread_BBB": (ecw['KR_CorpBBB'] - ecw['KR_Gov3Y']).dropna(),
    "KR_CredSpread_AA":  (ecw['KR_CorpAA'] - ecw['KR_Gov3Y']).dropna(),
    "KR_TermSpread":     (ecw['KR_Gov10Y'] - ecw['KR_Gov3Y']).dropna(),
    "KR_Call_CD_Spread": (ecw['KR_CD91'] - ecw['KR_Call1D']).dropna(),
    "StL_Fin_Stress":    fr['StL_Fin_Stress'].dropna(),
    "Chi_Fin_Cond":      fr['Chi_Fin_Cond'].dropna(),
    "VIX":               fr['VIX'].dropna(),
    "US_TermSpread":     fr['Term_Spread'].dropna(),
    "breadth_bear_prob": br,
}

rows = []
for name, s in series.items():
    L, why = LAG_TABLE[name]
    s = s.sort_index()
    for _, r in cen.iterrows():
        # cutoff = min(홀딩월 첫 거래일 - L, 홀딩월 캘린더 첫날).
        #   rev2 지정 규칙(first_td - L) 을 따르되 assert_overlay_pit HARD(캘린더 월초 이전) 를
        #   동시 만족하도록 **더 보수적인 쪽**을 취한다(느슨화 아님 — 문서화된 강화).
        cut = min(r['first_td'] - pd.Timedelta(days=L), r['ym_d'])
        if name == "breadth_bear_prob":
            cut = r['ym_d'] - pd.Timedelta(days=1)   # effective_date(T+2) 자체 보유
        sub = s.loc[:cut]
        if len(sub) == 0:
            continue
        obs_d = sub.index[-1]
        stale = (r['ym_d'] - obs_d).days
        rows.append(dict(ym=r['ym'], series=name, S=float(sub.iloc[-1]),
                         obs_date=str(obs_d.date()), first_td=str(r['first_td'].date()),
                         cutoff=str(pd.Timestamp(cut).date()),
                         holding_month_start=str(r['ym_d'].date()),
                         lag_days=L, staleness_days=int(stale)))
S = pd.DataFrame(rows)
S.to_csv(os.path.join(OUT, "S_panel_monthly.csv"), index=False)

print("[S panel] rows", len(S))
g = S.groupby('series').agg(n=('S', 'size'), first=('ym', 'min'), last=('ym', 'max'),
                            mean=('S', 'mean'), sd=('S', 'std'),
                            stale_med=('staleness_days', 'median'),
                            stale_max=('staleness_days', 'max'))
print(g.round(4).to_string())
print("\n[LAG_TABLE]")
for k, (L, why) in LAG_TABLE.items():
    print(f"  {k:20s} L={L:2d}d  {why}")
