"""11-15 리프레시 세션 14행 퀀티 재조회(지금 판 · 수정주가 S100300) 판정 재현 — 쓰기 없음(RAWDATA 읽기 · 네이버 모바일 일별 시세 읽기만).

① 14행 — RAWDATA 의 주식 수 비율(Size/Close 당일 ÷ 전일) · 시총 기준 수익 · '주식 수 불변이면' 전일 원주가(전일 Size ÷ 당일 주식 수)
② A012470 1998-07-13 — RAWDATA 에는 토요일 행이 없다(재조회 = 단절이 1998-07-11 토요일).
   전일까지의 '원주가 = Size ÷ 이벤트 뒤 주식 수' 가 호가 단위(5원)에 맞으면 주식 수가 그대로였다는 뜻 → 수정주가 계수만 바뀐 것(보유자 수익 = 시총 기준).
③ A037030 2018-06-07 · 06-08 — 거래소 공식 종가 · 등락률(네이버 모바일)과 상한가 산술(전일 종가 × 1.3 → 호가 단위 내림).

사용: python requery_1115_check.py <SP 출력 폴더> [RAWDATA.parquet]
출력: SP/requery_1115_rows.csv · 화면
"""
import csv, json, math, sys, time, urllib.request
import pandas as pd
import pyarrow.parquet as pq

SP = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else ".cache/RAWDATA.parquet"
ROWS = [("1991-01-03", "A003580"), ("1992-01-03", "A013520"), ("1996-11-19", "A016560"), ("1997-08-27", "A014440"),
        ("1997-10-28", "A024890"), ("1997-11-25", "A027840"), ("1998-07-13", "A012470"), ("1999-11-26", "A007120"),
        ("2012-01-12", "A008080"), ("2012-11-30", "A008080"), ("2015-11-19", "A127160"), ("2015-11-20", "A180400"),
        ("2016-12-09", "A204990"), ("2018-06-07", "A037030")]

tk = sorted({c for _, c in ROWS})
t = pq.read_table(RAW, columns=["Date", "Ticker", "Close", "Vol", "Size", "Ret"], filters=[("Ticker", "in", tk)]).to_pandas()
t["Date"] = pd.to_datetime(t["Date"])
t = t.sort_values(["Ticker", "Date"]).reset_index(drop=True)
dates = pd.Series(pd.to_datetime(pq.read_table(RAW, columns=["Date"]).column("Date").unique().to_pandas()))
print(f"RAWDATA 토요일 날짜 수 = {(dates.dt.day_of_week == 5).sum()} (전 이력)")

# ① 14행
out = []
for d, c in ROWS:
    s = t[t.Ticker == c].reset_index(drop=True)
    i = s.index[s.Date == pd.Timestamp(d)][0]
    assert i > 0, f"{c} {d} = 그 종목 첫 행 — 전일이 없다"   # iloc[-1] 이 마지막 행으로 조용히 감기는 것을 막는다
    p, q = s.iloc[i - 1], s.iloc[i]
    sh_after = q.Size / q.Close
    out.append(dict(date=d, code=c, prev_date=p.Date.date().isoformat(), ret=round(q.Ret, 6),
                    mcap_ret=round(q.Size / p.Size - 1, 6), share_ratio=round(sh_after / (p.Size / p.Close), 4),
                    raw_prev_if_const_shares=round(p.Size / sh_after, 3), close=q.Close, vol_prev=p.Vol, vol=q.Vol))
with open(f"{SP}/requery_1115_rows.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=list(out[0].keys()))
    w.writeheader(); w.writerows(out)
print(pd.DataFrame(out).to_string(index=False))

# ② A012470 — 이벤트 전 원주가가 호가 단위에 맞나
s = t[t.Ticker == "A012470"].reset_index(drop=True)
ev = s[s.Date == pd.Timestamp("1998-07-13")].iloc[0]
sh = ev.Size / ev.Close
pre = s[(s.Date >= "1998-01-01") & (s.Date <= "1998-07-10")].copy()
pre["raw"] = pre.Size / sh
pre["tick_ok"] = (pre.raw - (pre.raw / 5).round() * 5).abs() < 1e-6
pre["factor"] = pre.Close / pre.raw
print(f"\nA012470 이벤트 뒤 주식 수 = {sh:,.0f} · 1998-01-01~07-10 {len(pre)}일 중 원주가가 5원 단위 = {int(pre.tick_ok.sum())}"
      f" · 수정 계수(Close/원주가) 범위 {pre.factor.min():.4f}~{pre.factor.max():.4f}")
post = s[(s.Date >= "1998-07-13") & (s.Date <= "1998-12-31")]
print(f"  이벤트 뒤(1998-07-13~12-31) 종가가 5원 단위 = {int(((post.Close % 5).abs() < 1e-9).sum())}/{len(post)} · 최고 수정 종가(이벤트 뒤 전 기간) = {s[s.Date >= '1998-07-13'].Close.max():,.0f}"
      f" · 마지막 행 = {s.Date.max().date()}")
# 토요일 값은 RAWDATA 에 없다 — 리프레시 세션 11-15 10:16 퀀티 재조회(S100300 수정주가 · 단말 지금 판 · 공유 노트 seam_requery_14rows_20261115.csv)
SAT_19980711_ADJ_CLOSE = 55.0
fri_row = pre[pre.Date == pd.Timestamp("1998-07-10")].iloc[0]
fri, sat = float(fri_row.raw), SAT_19980711_ADJ_CLOSE
print(f"  원주가 07-10(금) {fri:.1f} → 07-11(토 · 재조회 {sat:.0f}) → 07-13(월) {ev.Close:.0f}: 토 {sat / fri - 1:+.4%} · 월 {ev.Close / sat - 1:+.4%} · 합 {ev.Close / fri - 1:+.4%}"
      f" (시총 기준 {ev.Size / float(fri_row.Size) - 1:+.4%})")

# ③ A037030 — 거래소 공식 시세
UA = {"User-Agent": "Mozilla/5.0"}


def page(code, p):
    u = f"https://m.stock.naver.com/api/stock/{code}/price?pageSize=60&page={p}"
    for _ in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=20) as r:
                d = json.loads(r.read().decode("utf-8"))
            time.sleep(0.12)
            return d if isinstance(d, list) else []
        except Exception:
            time.sleep(1.0)
    return None


# 06-05 는 장외 거래일이라 거래소 시세에 없다(그 앞 거래소 행 = 옛 상장 2005-08-29) — 찾는 날은 상장 첫날부터.
want = {"2018-06-07", "2018-06-08", "2018-06-11"}
got, p, seen, fetch_failed = {}, 30, set(), False
while 1 <= p < 80 and p not in seen and len(got) < len(want):
    seen.add(p)
    rows = page("037030", p)
    if rows is None:     # 3번 다 실패 = 조회 실패(없음과 구분)
        fetch_failed = True
        break
    if not rows:         # 빈 쪽 = 자료 끝
        break
    for r in rows:
        if r["localTradedAt"] in want:
            got[r["localTradedAt"]] = r
    if rows[-1]["localTradedAt"] > "2018-06-11":
        p += 1          # 이 쪽은 전부 더 늦은 날 — 더 오래된 쪽으로
    elif rows[0]["localTradedAt"] < "2018-06-07":
        p -= 1          # 이 쪽은 전부 더 이른 날 — 더 최근 쪽으로
    else:
        p += 1          # 걸친 쪽 — 다음(더 오래된) 쪽에 나머지가 있을 수 있다(본 쪽은 seen 이 막는다)
for k in sorted(want):
    r = got.get(k)
    print(f"  A037030 {k}: " + ("없음" if r is None else f"종가 {r['closePrice']} · 전일비 {r['compareToPreviousClosePrice']} · 등락률 {r['fluctuationsRatio']}%"))


def tick(px):  # 2018 코스닥 호가 단위
    return 1 if px < 1000 else 5 if px < 5000 else 10 if px < 10000 else 50 if px < 50000 else 100


c0607 = float(t[(t.Ticker == "A037030") & (t.Date == pd.Timestamp("2018-06-07"))].Close.iloc[0])   # RAWDATA 06-07 종가
lim = c0607 * 1.3
up = math.floor(lim / tick(lim)) * tick(lim)
off = got.get("2018-06-08")
print(f"  상한가 산술: {c0607:,.0f} × 1.3 = {lim:,.0f} → 호가 {tick(lim)}원 내림 = {up:,}"
      + ("" if off is None else f" · 거래소 06-08 종가와 같음 = {float(str(off['closePrice']).replace(',', '')) == up}"))
if len(got) < len(want):
    print(f"  ★거래소 시세 미완: {sorted(want - set(got))} — " + ("조회 실패(네트워크)" if fetch_failed else "쪽 탐색으로 못 찾음"))
    sys.exit(2)
