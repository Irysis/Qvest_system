# -*- coding: utf-8 -*-
"""
FQ-236 Lane D — prereg #2(신판) backfill 생존편향 census (C6). PRIMARY 창을 **기계 결정**한다.
규칙(rev2 window_decision.condition_backfill_gate, 착수 전 고정):
  share_backfill = 백필 구간(2010-02~2015-06) KQ150 멤버 중 이후 상장폐지 비율
  share_clean    = 비교 구간(2015-07~2020-12, 동일 길이 65m) KQ150 멤버의 동일 정의 비율
  share_backfill >= 0.5 * share_clean  →  198m PRIMARY 유지 / 미달 → 133m 자동 강등
'상장폐지' 정의 = RAWDATA 가격 계열이 2026-07-01 이전 종결.
"""
import os
import numpy as np
import pandas as pd
import pyarrow.parquet as pq

ROOT = os.environ.get("QM_ROOT", r"C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT = os.path.join(ROOT, "stage_artifacts", "WT-D20260822_001")

df = pq.read_table(os.path.join(ROOT, ".cache/RAWDATA.parquet"),
                   columns=['Date', 'Ticker', 'KQ150'],
                   filters=[('Date', '>=', pd.Timestamp('2009-01-01').date())]).to_pandas()
df['Date'] = pd.to_datetime(df['Date'])
last_seen = df.groupby('Ticker')['Date'].max()
DELIST_CUT = pd.Timestamp('2026-07-01')

def members(a, b):
    m = df[(df['Date'] >= pd.Timestamp(a)) & (df['Date'] <= pd.Timestamp(b)) & (df['KQ150'].fillna(0) > 0)]
    return set(m['Ticker'].unique())

win = {
    'backfill_2010_02__2015_06': ('2010-02-01', '2015-06-30'),
    'clean_2015_07__2020_12':    ('2015-07-01', '2020-12-31'),
    'recent_2021_01__2026_06':   ('2021-01-01', '2026-06-30'),
}
res = {}
for k, (a, b) in win.items():
    tk = members(a, b)
    dl = {t for t in tk if last_seen.get(t, DELIST_CUT) < DELIST_CUT}
    res[k] = dict(n_members=len(tk), n_delisted=len(dl),
                  share=len(dl) / len(tk) if tk else np.nan)
    print(f"{k:30s} members={len(tk):4d} delisted={len(dl):4d} share={res[k]['share']:.4f}")

sb = res['backfill_2010_02__2015_06']['share']
sc = res['clean_2015_07__2020_12']['share']
gate = sb >= 0.5 * sc
print()
print(f"share_backfill = {sb:.4f}")
print(f"share_clean    = {sc:.4f}   (0.5x = {0.5*sc:.4f})")
print(f"GATE: share_backfill >= 0.5*share_clean  ->  {gate}")
print("PRIMARY 창 =", "UNION 198m (2010-02..2026-07) 유지" if gate else "UNION 133m (2015-07..2026-07) 자동 강등")

import json
json.dump(dict(rule="share_backfill >= 0.5 * share_clean",
               delist_definition="RAWDATA 가격 계열 최종일 < 2026-07-01",
               windows=res, share_backfill=sb, share_clean=sc,
               threshold=0.5 * sc, gate_pass=bool(gate),
               primary_window="UNION_198m_2010-02..2026-07" if gate else "UNION_133m_2015-07..2026-07",
               metric_type="measured_direct"),
          open(os.path.join(OUT, "backfill_survivorship_census.json"), "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
