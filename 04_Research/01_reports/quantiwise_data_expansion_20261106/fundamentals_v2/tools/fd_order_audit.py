"""fd_order_audit.py — 재무 표의 날짜 순서 계약 검사(읽기 전용).

소비자(팩터 모듈 · 전략 엔진)는 (Ticker, Item) 안에서 Factor_Date 순위로 '최신 · 직전 기간'을 고르고, 그 순서가
기간(Period_Date) 순서와 같다고 가정한다. 이 검사는 그 가정이 깨지는 곳을 센다.
  겹침(tie) = 이웃한 두 기간의 Factor_Date 가 같다 · 역전(inversion) = 새 기간이 옛 기간보다 먼저 쓰일 수 있다
사용: python -I fd_order_audit.py <파일명(.cache 안)> [<파일명> ...]   (11-09 실측: 지금 병합 표 0 · 0)
"""
import os
import sys

import numpy as np
import pandas as pd
import pyarrow.parquet as pq

root = os.path.join(os.environ.get("QM_ROOT", r"G:/OneDrive/Quant_Module_Moltbot"), ".cache")
bad_any = False
for f in sys.argv[1:]:
    p = os.path.join(root, f)
    names = pq.read_schema(p).names
    cols = [c for c in ["Ticker", "Item", "Period", "Period_Date", "Factor_Date", "Source", "Origin"] if c in names]
    x = pd.read_parquet(p, columns=cols)
    x["Factor_Date"] = pd.to_datetime(x["Factor_Date"]); x["Period_Date"] = pd.to_datetime(x["Period_Date"])
    x = x.sort_values(["Ticker", "Item", "Period_Date"]).reset_index(drop=True)
    same = (x.Ticker.values[1:] == x.Ticker.values[:-1]) & (x.Item.values[1:] == x.Item.values[:-1])
    fd = x.Factor_Date.values
    tie = np.zeros(len(x), bool); inv = np.zeros(len(x), bool)
    tie[1:] = same & (fd[1:] == fd[:-1]); inv[1:] = same & (fd[1:] < fd[:-1])
    print(f"== {f}: 행 {len(x):,} · 계열 {x.groupby(['Ticker', 'Item']).ngroups:,} · 겹침 {int(tie.sum()):,} · 역전 {int(inv.sum()):,}")
    if tie.any() or inv.any():
        bad_any = True
        src = "Origin" if "Origin" in x.columns else ("Source" if "Source" in x.columns else None)
        if src:
            print("   출처별:", x.loc[tie | inv, src].value_counts().head(8).to_dict())
        print("   기간 연도별:", pd.Series(x.loc[tie | inv, "Period_Date"].dt.year).value_counts().sort_index().to_dict())
sys.exit(1 if bad_any else 0)
