"""남은 목록 9행(+ 대조 A012470) 판정 재현 — 단절 전후 시총(Size)의 최대공약수 비교(쓰기 없음 · 11-15).

원리: Size = 원주가 × 상장 주식 수(정수 원)라면 주식 수가 그대로인 구간의 gcd(Size) = 주식 수 × gcd(원주가).
     단절 앞 구간 gcd 와 뒤 구간 gcd 가 같거나 한쪽이 다른 쪽의 배수면 주식 수가 그대로였을 개연성이 크다(필요조건은 아니다 —
     공시로 증자 · 감자가 없는지 함께 본다). 이때 보유자 수익 = 시총 기준. 주식 수의 절대 수준은 원주가 gcd(호가 단위)와 섞여 정하지 않는다.
     거래정지 구간처럼 Size 가 일정하면 gcd = 그 값 자체라 아무것도 말하지 않는다(표시: 정지).
사용: python list9_check.py <SP 출력 폴더> [RAWDATA.parquet] [창 길이=20]
출력: SP/list9_rows.csv · 화면
"""
import csv, math, sys
from functools import reduce
import pandas as pd
import pyarrow.parquet as pq

SP = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else ".cache/RAWDATA.parquet"
WIN = int(sys.argv[3]) if len(sys.argv) > 3 else 20
ROWS = [("1998-07-13", "A012470"),  # 양성 대조(11-15 판정 — 주식 수 불변 · 퀀티 수정 계수 152.78)
        ("1991-01-03", "A003580"), ("1992-01-03", "A013520"), ("1996-11-19", "A016560"), ("1997-08-27", "A014440"),
        ("1997-10-28", "A024890"), ("1997-11-25", "A027840"), ("1999-11-26", "A007120"),
        ("2012-01-12", "A008080"), ("2012-11-30", "A008080")]
# A008080 2012-01-12 는 2011-10-27 ~ 2012-01-11 거래정지 — 앞 구간은 정지 전 거래일, 뒤 구간은 01-25 주식 수 변화 전까지
PRE_OVERRIDE = {("2012-01-12", "A008080"): ("2011-10-04", "2011-10-26")}
POST_OVERRIDE = {("2012-01-12", "A008080"): ("2012-01-12", "2012-01-20")}

tk = sorted({c for _, c in ROWS})
t = pq.read_table(RAW, columns=["Date", "Ticker", "Close", "Vol", "Size", "Ret"], filters=[("Ticker", "in", tk)]).to_pandas()
t["Date"] = pd.to_datetime(t["Date"])
t = t.sort_values(["Ticker", "Date"]).reset_index(drop=True)


def gcd_of(sizes):
    v = [float(a) for a in sizes if pd.notna(a)]
    if not v or any(abs(a - round(a)) > 1e-6 or a <= 0 for a in v):
        return None, "정수 아님"
    v = [int(round(a)) for a in v]
    return reduce(math.gcd, v), ("정지(값 일정)" if len(set(v)) == 1 else f"{len(set(v))}값")


out = []
for d, c in ROWS:
    s = t[t.Ticker == c].reset_index(drop=True)
    i = int(s.index[s.Date == pd.Timestamp(d)][0])
    assert i > 0, f"{c} {d} 첫 행"
    if (d, c) in PRE_OVERRIDE:
        lo, hi = PRE_OVERRIDE[(d, c)]
        pre = s[(s.Date >= lo) & (s.Date <= hi)]
    else:
        pre = s.iloc[max(0, i - WIN):i]
    if (d, c) in POST_OVERRIDE:
        lo, hi = POST_OVERRIDE[(d, c)]
        post = s[(s.Date >= lo) & (s.Date <= hi)]
    else:
        post = s.iloc[i:i + WIN]
    gb, kb = gcd_of(pre.Size)
    ga, ka = gcd_of(post.Size)
    rel = None
    if gb and ga and "정지" not in kb:
        rel = "같음" if ga == gb else (f"뒤 = 앞 × {ga // gb}" if ga % gb == 0 else (f"앞 = 뒤 × {gb // ga}" if gb % ga == 0 else "배수 아님"))
    p, q = s.iloc[i - 1], s.iloc[i]
    row = dict(date=d, code=c, prev=p.Date.date().isoformat(), ret_stored=round(q.Ret, 6), mcap_ret=round(q.Size / p.Size - 1, 6),
               size_close_ratio=round((q.Size / q.Close) / (p.Size / p.Close), 6), gcd_pre=gb, pre_kind=kb, gcd_post=ga, post_kind=ka,
               gcd_relation=rel, vol0_prev60=int((s.iloc[max(0, i - 60):i].Vol == 0).sum()), vol_day=q.Vol, last_row=s.Date.max().date().isoformat())
    out.append(row)
    print(f"{c} {d} · 저장 {row['ret_stored']:+.4f} · 시총 {row['mcap_ret']:+.6f} · Size/Close 비 {row['size_close_ratio']} · "
          f"gcd 앞 {gb}({kb}) 뒤 {ga}({ka}) → {rel} · 앞 60행 거래량 0 = {row['vol0_prev60']} · 당일 거래량 {q.Vol:,.0f} · 마지막 행 {row['last_row']}")

with open(f"{SP}/list9_rows.csv", "w", newline="", encoding="utf-8") as f:
    wr = csv.DictWriter(f, fieldnames=list(out[0].keys()))
    wr.writeheader(); wr.writerows(out)
s = t[t.Ticker == "A008080"].reset_index(drop=True)   # A008080 2012-11-30 시총 비 — 제한폭 비교가 부동소수점 경계에서 떨어지는지
k = int(s.index[s.Date == pd.Timestamp("2012-11-30")][0])
mc = float(s.Size.iloc[k]) / float(s.Size.iloc[k - 1]) - 1
print(f"\nA008080 2012-11-30 시총 기준 = {mc!r} · abs(mc) <= 0.15 → {abs(mc) <= 0.15} (경계 −15% 정확히 · 1e-9 허용이면 {abs(mc) <= 0.15 + 1e-9})")
