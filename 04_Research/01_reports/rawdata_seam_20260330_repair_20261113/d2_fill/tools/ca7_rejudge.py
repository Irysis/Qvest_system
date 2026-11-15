"""남은 7행 재판정(11-15 · 도훈 결정 RAWDATA-7ROWS-CORPACTION-REQUERY-20261115 '판정해') — 쓰기 없음(RAWDATA · 입력 csv 읽기만).

입력 = 리프레시 세션의 퀀티 재조회 원본 사본(SP 폴더): seam_ca7_daily_20261115.csv(단절 ±10 거래일 · 일별 항목) · seam_ca7_summary_20261115.csv(행별 요약).
퀀티에는 증자 · 감자 이력 항목이 없어 사건을 일별 항목(시장구분 · 발행주식수 · 상장주식수 · 기준가)에서 읽는다.

판정:
 (가) 단절일에 시장구분이 바뀐다(코스닥 · 외감 → 유가증권 상장 첫날) ∧ 발행주식수가 단절 전에 늘고 그날 상장주식수가 발행주식수로 는다(공모 신주)
      ∧ 창 안 구시장 기준가 = 전일 종가(권리락 없음 = 기존 주주 배정 · 무상이 아님) → 사건 = 이전상장 · 공모.
      등록부 규칙 '이전상장 · 일반공모 = 생비율'(주식은 1:1 로 옮겨가고 신주가 시총을 부풀린다 · 06_Registry/ret_fill_registry.json _purpose).
      수정 계수(종가 ÷ 수정주가)가 단절 앞뒤 같으면 저장값(수정주가 비율) = 원주가 비율이다.
      보조: 그날 종가 ÷ 새 기준가가 뒤 4세션 연속 제한가 폭 안이다(그날도 제한가) — 아니면 제한가로 거꾸로 셈한 기준가를 보인다.
 (나) 시장구분 그대로 ∧ 발행주식수가 첫 관측 전부터 그대로(상장주식수만 발행주식수로 늘어남 = 이미 발행된 주식의 상장 · 새 돈 · 새 주식 없음)
      → 빠진 조정 없음(배당락은 수정주가에 들어 있다). 단 RAWDATA 첫 행 ~ 전날 체결이 0 이면 단절 전 값이 호가라 체결 기준으로는 확인할 수 없다 → 현행 유지.
사용: python ca7_rejudge.py <SP> [RAWDATA.parquet]
출력: SP/ca7_rejudge_rows.csv · 화면
"""
import csv, sys
import pandas as pd
import pyarrow.parquet as pq

SP = sys.argv[1]
RAW = sys.argv[2] if len(sys.argv) > 2 else ".cache/RAWDATA.parquet"
TICK_TOL = 0.003    # 제한가 비교의 호가 반올림 허용(진단 · 0.3%p) — 뒤 세션 제한가 폭 자체가 반올림으로 제한폭보다 조금 작게 보인다(A027840 7.83 · 7.93%)
FAC_TOL = 1e-3      # 수정 계수 단절 앞뒤 상대 차 허용 — 수정주가가 정수라 생기는 반올림
STORED_TOL = 1e-4   # 저장 Ret 과 퀀티 수정주가 비율의 차 허용 — 정수 반올림 · RAWDATA 수출 판 배율(A024890 = 1/5)

daily = pd.read_csv(f"{SP}/seam_ca7_daily_20261115.csv", encoding="utf-8-sig", dtype={"halt_reason": str, "div_type": str})
summ = pd.read_csv(f"{SP}/seam_ca7_summary_20261115.csv", encoding="utf-8-sig", dtype=str)
assert len(summ) == 7, f"요약 행 수 {len(summ)} ≠ 7"


def last_change_before(spec, before):
    """'YYYY-MM-DD a->b; …' 에서 before 이전 마지막 변화(날짜 · 전 · 후). 없으면 None."""
    best = None
    for part in str(spec).split(";"):
        part = part.strip()
        if not part or part == "없음":
            continue
        dt, ab = part.split(" ", 1)
        a, b = (int(x) for x in ab.split("->"))
        if pd.Timestamp(dt) < before and (best is None or pd.Timestamp(dt) > best[0]):
            best = (pd.Timestamp(dt), a, b)
    return best


tk = sorted(summ.code)
t = pq.read_table(RAW, columns=["Date", "Ticker", "Close", "Vol", "Ret"], filters=[("Ticker", "in", tk)]).to_pandas()
t["Date"] = pd.to_datetime(t["Date"])
t = t.sort_values(["Ticker", "Date"]).reset_index(drop=True)

out = []
for _, s in summ.iterrows():
    bd, c = pd.Timestamp(s.break_date), s.code
    d = daily[(daily.break_date == s.break_date) & (daily.code == c)].sort_values("offset").set_index("offset")
    assert {-1, 0, 1, 2, 3, 4} <= set(d.index), f"{c} {s.break_date} 일별 창 결손"
    p, q = d.loc[-1], d.loc[0]
    raw = q.close / p.close - 1
    adj = q.adj_close / p.adj_close - 1
    vs_base = q.close / q.base_price - 1
    mc_listed = (q.listed_shares * q.close) / (p.listed_shares * p.close) - 1
    mc_issued = (q.issued_shares * q.close) / (p.issued_shares * p.close) - 1
    fac_change = (q.close / q.adj_close) / (p.close / p.adj_close) - 1
    nxt = [d.loc[k].close / d.loc[k - 1].close - 1 for k in range(1, 5)]
    lim_emp = max(abs(x) for x in nxt)
    market_change = bool(p.market != q.market)
    # 제한가 대조는 시장이 바뀐 날(새 시장 기준가)에만 — (나)의 뒤 세션은 제한가가 아닌 평범한 폭이라 역산이 뜻이 없다
    # bool() = numpy bool 은 `is False` 비교에 안 걸린다
    limit_ok = bool(abs(vs_base) <= lim_emp + TICK_TOL) if market_change else None
    dirn = 1.0 if nxt[0] > 0 else -1.0
    base_implied = q.close / (1 + dirn * lim_emp) if limit_ok is False else None
    pre = d[(d.index >= d.index.min() + 1) & (d.index <= -1)]
    base_resets_pre = int(sum(pre.loc[k].base_price != d.loc[k - 1].close for k in pre.index))
    iss = last_change_before(s.issued_changes_m12_p1, bd)
    first_qw = pd.Timestamp(s.first_data_date)
    # RAWDATA — 저장 Ret · 첫 행 ~ 전날 체결 수 · 수출 판 배율(RAWDATA 종가 ÷ 퀀티 수정주가) 앞뒤
    r = t[t.Ticker == c].reset_index(drop=True)
    i = int(r.index[r.Date == bd][0])
    assert i > 0, f"{c} {s.break_date} = 그 종목 첫 행"
    assert r.Date.iloc[i - 1] == pd.Timestamp(p.date), f"{c} RAWDATA 전일 {r.Date.iloc[i - 1].date()} ≠ 퀀티 전일 {p.date}"
    stored = float(r.Ret.iloc[i])
    trades_before = int((r.Vol.iloc[:i] > 0).sum())
    vol_na_before = int(r.Vol.iloc[:i].isna().sum())   # 빈 거래량을 '체결 없음'으로 세지 않는다
    vint_p, vint_q = r.Close.iloc[i - 1] / p.adj_close, r.Close.iloc[i] / q.adj_close
    vint_ok = abs(vint_q / vint_p - 1) <= FAC_TOL
    stored_ok = abs(stored - adj) <= STORED_TOL

    if (market_change and iss is not None and first_qw <= iss[0] < bd and q.listed_shares == q.issued_shares
            and p.listed_shares < q.listed_shares and base_resets_pre == 0 and abs(fac_change) <= FAC_TOL and stored_ok and vint_ok):
        grp, verdict = "가", "확정 — 저장값 = 보유자 수익(이전상장 · 공모 = 생비율)"
    elif (not market_change and p.issued_shares == q.issued_shares and iss is not None and iss[0] < first_qw
          and p.listed_shares < p.issued_shares and q.listed_shares == q.issued_shares and stored_ok and vint_ok):
        grp = "나"
        verdict = ("빠진 조정 없음 · 단절 전 체결 0(호가) → 현행 유지" if trades_before == 0 and vol_na_before == 0
                   else f"빠진 조정 없음 → 저장값 = 보유자 수익(검토 · 단절 전 체결 {trades_before} · 빈 거래량 {vol_na_before})")
    else:
        grp, verdict = "?", "판정 불가 → 현행 유지"

    row = dict(date=s.break_date, code=c, group=grp, market=f"{p.market}→{q.market}",
               issued_change=(f"{iss[0].date()} ×{iss[2] / iss[1]:.4f}" if iss else ""),
               days_issue_to_break=((bd - iss[0]).days if iss else ""),
               new_share_frac=(round(1 - iss[1] / iss[2], 4) if iss and grp == "가" else ""),
               listed_ratio=round(q.listed_shares / p.listed_shares, 4),
               stored=round(stored, 7), raw=round(raw, 7), adj_qw=round(adj, 7), mc_listed=round(mc_listed, 6), mc_issued=round(mc_issued, 6),
               vs_base=round(vs_base, 6), next4="/".join(f"{x:+.4f}" for x in nxt), lim_emp=round(lim_emp, 4),
               limit_ok=("" if limit_ok is None else limit_ok),
               base_implied=(round(base_implied) if base_implied else ""), base_resets_pre=base_resets_pre,
               fac_change=round(fac_change, 6), div=(q.div_type if isinstance(q.div_type, str) else ""),
               vintage_ratio=round(vint_p, 6), trades_before=f"{trades_before}/{i}", verdict=verdict)
    out.append(row)
    print(f"{c} {s.break_date} ({grp}) {row['market']} · 발행 변화 {row['issued_change']}({row['days_issue_to_break']}일 전) · 상장 ×{row['listed_ratio']}\n"
          f"    저장 {stored:+.5f} · 생비율 {raw:+.5f} · 퀀티 수정 {adj:+.5f} · 시총(상장) {mc_listed:+.4f} · 시총(발행) {mc_issued:+.4f} · 종가/기준가 {vs_base:+.4f}"
          f" · 뒤 4세션 {row['next4']}"
          + ("" if limit_ok is None else f" → 제한폭 안 {limit_ok}{'' if limit_ok else f' (제한가로 역산한 기준가 {base_implied:,.0f})'}") + "\n"
          f"    구시장 기준가 ≠ 전일 종가 {base_resets_pre}일 · 수정 계수 변화 {fac_change:+.5f}{(' · 배당 ' + row['div']) if row['div'] else ''}"
          f" · RAWDATA 첫 행~전날 체결 {row['trades_before']} → {verdict}")

with open(f"{SP}/ca7_rejudge_rows.csv", "w", newline="", encoding="utf-8") as f:
    wr = csv.DictWriter(f, fieldnames=list(out[0].keys()))
    wr.writeheader(); wr.writerows(out)
n = pd.Series([o["group"] for o in out]).value_counts().to_dict()
print(f"\n요약: (가) {n.get('가', 0)}행 · (나) {n.get('나', 0)}행 · 판정 불가 {n.get('?', 0)}행 — 이 도구는 새 값을 내지 않는다"
      "((가) 확정 = 저장값 · (나) · 판정 불가 = 현행 유지)")
if n.get("?", 0):
    sys.exit(3)
