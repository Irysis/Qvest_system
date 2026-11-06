#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""일보 본문 — 임원 보고용(높임말 · 쉬운 말 · 데이터에서 자동으로 쓰는 서술 · 꾸민 HTML 표).

모든 문장은 output/v1 의 숫자에서 만든다(지어내는 서술 없음). 전문용어는 처음 나올 때 쉬운 말로 풀고, 부록에 용어 풀이를 둔다.
표는 commonmark 가 그대로 통과시키는 raw HTML(인라인 스타일)로 그린다 — md_to_print_pdf.R 의 pdf-check 가 세는 <thead> 를 둔다.
"""
from __future__ import annotations

import pandas as pd

# 분야(축)를 쉬운 말로
AXIS_PLAIN = {
    "equity": ("대형주 시장", "코스피200 의 변동폭 · 고점 대비 하락 · 옵션시장이 보는 향후 변동성"),
    "smallcap": ("중소형 · 코스닥", "코스닥의 변동폭 · 하락 · 대형주 대비 부진"),
    "breadth": ("하락의 확산", "하락이 몇몇 종목이 아니라 시장 전체로 번졌는지 · 종목들이 같이 움직이는지"),
    "liquidity": ("거래 유동성", "주식을 팔 때 가격이 얼마나 쉽게 밀리는지(거래 비용)"),
    "rates": ("국채 금리", "국채 금리의 변동폭 · 상승폭 · 장단기 금리 역전"),
    "credit": ("회사채 신용", "회사채가 국채보다 얼마나 높은 금리를 요구받는지(기업 신용 불안)"),
    "funding": ("단기 자금시장", "CD · 기업어음(CP) 같은 3개월 이내 자금시장의 경색"),
    "fx": ("원화 · 환율", "원/달러 환율의 변동폭 · 원화 약세"),
    "financial": ("금융회사 주가", "은행 · 증권 · 보험주의 하락과 고유한 변동"),
    "flow": ("외국인 매도", "외국인이 얼마나 지속적으로 · 폭넓게 팔고 있는지"),
    "global": ("해외 전이", "미국 변동성(VIX) · 미국 금융스트레스 · 달러 강세가 번지는지"),
    "contagion": ("시장 간 전이", "주가 · 원화 · 국채가 함께 무너지는지(평소 관계가 깨졌는지)"),
}
IND_PLAIN = {
    "E1": "코스피200 하루 변동폭", "E2": "코스피200 2년 고점 대비 하락률", "E3": "옵션시장이 보는 향후 변동성(V-KOSPI)",
    "S1": "코스닥 하루 변동폭", "S2": "코스닥 2년 고점 대비 하락률", "S3": "코스닥이 대형주보다 더 못 간 정도(60일)",
    "B1": "1년 고점 대비 20% 이상 빠진 종목 비중", "B2": "대형주들이 같은 방향으로 움직이는 정도", "B3": "상위 500 종목의 60일 수익 중앙값(하락일수록 높음)",
    "L1": "대형주 거래 시 가격이 밀리는 정도", "L2": "중소형주 거래 시 가격이 밀리는 정도",
    "R1": "국고채 10년 금리의 하루 변동폭", "R2": "국고채 3년 금리가 2년 저점에서 오른 폭", "R3": "단기(1년) · 장기(10년) 금리 역전 정도",
    "C1": "우량 회사채(AA-)가 국채보다 더 내는 금리", "C2": "비우량 회사채(BBB-)가 국채보다 더 내는 금리", "C3": "비우량 · 우량 회사채의 금리 차",
    "M1": "CD 금리가 하루짜리 콜금리보다 높은 정도", "M2": "기업어음(CP)이 CD 보다 높은 정도(단기 신용 불안)", "M3": "CD 금리의 하루 변동폭",
    "X1": "원/달러 환율의 하루 변동폭", "X2": "6개월 최고 원화가치 대비 하락률", "X3": "달러 강세로 설명되지 않는 원화 약세(20일)",
    "F1": "은행 · 증권 · 보험주 2년 고점 대비 하락률", "F2": "금융주만의 고유한 변동", "F3": "금융주가 시장보다 더 못 간 정도(60일)",
    "N1": "외국인 20일 순매도(시가총액 대비)", "N2": "외국인 60일 순매도(시가총액 대비)", "N3": "외국인이 순매도한 종목 비중(20일)",
    "G1": "미국 주식시장 공포지수(VIX)", "G2": "미국 금융스트레스지수(세인트루이스 연준)", "G3": "달러 강세 정도(20일)",
    "T1": "주가 하락과 원화 약세가 함께 가는 정도", "T2": "주가와 국채금리의 관계가 평소와 달라진 정도",
}
STATUS = [(0.90, "매우 높음", "#c62828", "#ffcdd2"), (0.80, "높음", "#ef6c00", "#ffe0b2"), (0.60, "다소 높음", "#f9a825", "#fff3c4"), (-1, "낮음 · 보통", "#2e7d32", "#c8e6c9")]
TIER_FILL = {"정상": "#c8e6c9", "주의": "#fff3c4", "위험": "#ffcdd2"}


def status(p):
    p = round(100 * p) / 100.0   # 표시 숫자(정수 %)와 같은 기준으로 판정 — 89.6 은 '90' 으로 보이므로 '매우 높음'
    for th, lab, fg, bg in STATUS:
        if p >= th:
            return lab, fg, bg
    return STATUS[-1][1:]


def pct(x):
    return "—" if x is None or (isinstance(x, float) and x != x) else f"{100 * x:.0f}"


def rank_phrase(p):
    """백분위 → '상위 n%' 말."""
    return f"상위 {max(1, round(100 - 100 * p)):.0f}%"


def tier_of(p, ns):
    if ns.get("threshold_risk") is not None and p >= ns["threshold_risk"]:
        return "위험"
    if ns.get("threshold_warn") is not None and p >= ns["threshold_warn"]:
        return "주의"
    return "정상"


def kdate(x):
    t = pd.Timestamp(x)
    return f"{t.year}년 {t.month}월 {t.day}일"


def chip(color):
    return f'<span style="display:inline-block;width:9px;height:9px;border-radius:5px;background:{color};margin-right:5px;vertical-align:middle"></span>'


def bar(p, color, width_px=70):
    w = max(2, int(round(width_px * max(0.0, min(1.0, p)))))
    return (f'<span style="display:inline-block;width:{width_px}px;height:9px;background:#eeeeee;vertical-align:middle;border-radius:2px">'
            f'<span style="display:inline-block;width:{w}px;height:9px;background:{color};border-radius:2px"></span></span>')


def html_table(headers, rows, aligns=None, widths=None, small=False):
    fs = "font-size:8.2pt;" if small else ""
    th = "".join(f'<th style="background:#1f4e79;color:#ffffff;padding:4px 5px;text-align:center;border:1px solid #d9d9d9;{fs}' +
                 (f'width:{widths[i]}' if widths and widths[i] else "") + f'">{h}</th>' for i, h in enumerate(headers))
    body = []
    for k, r in enumerate(rows):
        bg = "#fafafa" if k % 2 else "#ffffff"
        tds = []
        for i, c in enumerate(r):
            al = (aligns[i] if aligns else "left")
            tds.append(f'<td style="padding:3px 5px;border:1px solid #e3e3e3;text-align:{al};vertical-align:middle;background:{bg};{fs}">{c}</td>')
        body.append("<tr>" + "".join(tds) + "</tr>")
    return (f'<table style="width:100%;border-collapse:collapse;margin:4px 0 6px 0"><thead><tr>{th}</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table>')


def chg_phrase(delta, unit="점"):
    if delta > 0.05:
        return f'<span style="color:#c62828">▲ {delta:+.1f}{unit}</span>'
    if delta < -0.05:
        return f'<span style="color:#2e7d32">▼ {delta:+.1f}{unit}</span>'
    return f'<span style="color:#777777">— {delta:+.1f}{unit}</span>'


# ─────────────────────────────────────────────────────────────────────────────
def _axis_runs(d, axes, n=65, thr=0.8):
    """최근 n거래일 창에서 축별 '현재 높음 상태'가 언제 시작됐나."""
    out = {}
    sub = d.tail(n)
    for a in axes:
        s = sub[f"pct_{a}"]
        if s.iloc[-1] != s.iloc[-1]:
            out[a] = None
            continue
        if s.iloc[-1] < thr:
            out[a] = ("low", None, 0)
            continue
        k = 0
        for v in s.values[::-1]:
            if v >= thr:
                k += 1
            else:
                break
        out[a] = ("all", None, k) if k >= len(s) else ("since", s.index[len(s) - k], k)
    return out


def summary_bullets(meta, d, st, eps, cv, ns, peaks):
    lt = meta["latest"]
    axes = meta["axes"]
    p = lt["score_pct"]
    tier = tier_of(p, ns)
    B = []
    B.append(f"오늘의 자본시장 스트레스 지수는 **{lt['score']:.1f}점**(100점 만점)으로, 2006년 이후 모든 거래일과 비교하면 **{rank_phrase(p)}** 에 해당하는 높은 수준입니다. "
             f"경보 단계는 **'{tier}'** 입니다(과거 대비 위치가 {pct(ns.get('threshold_warn'))}% 를 넘으면 주의, {pct(ns.get('threshold_risk'))}% 를 넘으면 위험으로 봅니다).")
    order = sorted(axes, key=lambda a: -lt["contrib"][a])
    top = order[:3]
    share = sum(lt["contrib"][a] for a in top) / lt["score"] if lt["score"] else float("nan")
    B.append("스트레스의 " + (f"약 {100 * share:.0f}%" if share == share else "대부분") + "는 " +
             " · ".join(f"**{AXIS_PLAIN[a][0]}**({pct(lt['axis_pct'][a])}%)" for a in top) +
             " 세 분야에서 오고 있습니다. 괄호 안 숫자는 과거 대비 위치(백분위)로, 90 이상이면 2006년 이후 상위 10% 안에 드는 이례적 수준입니다.")
    calm = [a for a in axes if lt["axis_pct"][a] <= 0.45]
    sys_axes = ("credit", "fx", "global")
    if all(lt["axis_pct"][a] <= 0.5 for a in sys_axes):
        B.append("반면 " + " · ".join(f"{AXIS_PLAIN[a][0]}({pct(lt['axis_pct'][a])}%)" for a in sys_axes) +
                 " 은 평온합니다. 회사채 · 환율 · 해외로 번지지 않았다는 뜻이므로, 현재는 **금융시스템 전반의 위기라기보다 주식시장 내부의 조정**에 가까운 모습으로 판단됩니다.")
    elif calm:
        B.append("반면 " + " · ".join(f"{AXIS_PLAIN[a][0]}({pct(lt['axis_pct'][a])}%)" for a in calm) + " 은 낮은 수준입니다.")
    else:
        B.append("모든 분야가 동시에 높은 상태로, 분절을 가리지 않고 번진 체계적 스트레스의 모습입니다.")
    chg = lt["score"] - lt["score_20td_ago"]
    dcon = sorted(axes, key=lambda a: -(lt["contrib"][a] - lt["contrib_20td_ago"][a]))[:2]
    dir_ = "크게 높아졌습니다" if chg > 3 else "높아졌습니다" if chg > 0.5 else "낮아졌습니다" if chg < -0.5 else "비슷한 수준입니다"
    B.append(f"20거래일 전({kdate(lt['date_20td_ago'])}) {lt['score_20td_ago']:.1f}점에서 {lt['score']:.1f}점으로 {dir_}" +
             (f". 그 사이 가장 많이 오른 분야는 {AXIS_PLAIN[dcon[0]][0]}(+{lt['contrib'][dcon[0]] - lt['contrib_20td_ago'][dcon[0]]:.1f}점)과 "
              f"{AXIS_PLAIN[dcon[1]][0]}(+{lt['contrib'][dcon[1]] - lt['contrib_20td_ago'][dcon[1]]:.1f}점)입니다." if chg > 0.5 else "."))
    if peaks:
        pmax_d, pmax = peaks[0]
        B.append(f"과거와 비교하면 2008년 금융위기 정점({kdate(pmax_d)} {pmax:.1f}점)의 {100 * lt['score'] / pmax:.0f}% 수준입니다. "
                 + _nearest_peak_phrase(lt, peaks))
    watch = st[(st.ecdf_pct >= 0.8) & (st.ecdf_pct < 0.9)].sort_values("ecdf_pct", ascending=False)
    rising = st[(st.ecdf_pct - st.ecdf_pct_20td_ago >= 0.25) & (st.ecdf_pct >= 0.6)].sort_values("ecdf_pct", ascending=False)
    w = []
    if len(watch):
        w.append("경계선(80~90%) 부근의 지표 = " + " · ".join(f"{IND_PLAIN.get(r.id, r.name)}({100 * r.ecdf_pct:.0f}%)" for r in watch.head(3).itertuples()))
    if len(rising):
        w.append("최근 20거래일 사이 빠르게 오른 지표 = " + " · ".join(f"{IND_PLAIN.get(r.id, r.name)}({100 * r.ecdf_pct_20td_ago:.0f}→{100 * r.ecdf_pct:.0f}%)" for r in rising.head(3).itertuples()))
    if w:
        B.append("앞으로 지켜볼 대목입니다 — " + "; ".join(w) + ". 이 지표들이 90% 를 넘어서면 스트레스가 다른 분야로 번지는 신호로 읽으시면 됩니다.")
    B.append("유의하실 점은, 이 지수는 시장이 **지금 얼마나 흔들리고 있는지를 재는 온도계**이지 앞으로의 방향을 맞히는 예측 지표가 아니라는 것입니다. "
             "과거 검증에서 지수는 급락과 거의 동시에 오르고, 주가 고점을 미리 알려 주지는 못했습니다. 다만 지수가 상위 5% 안에 있을 때는 이후 두 달 동안 큰 폭의 추가 하락이 평소보다 훨씬 자주 나타났습니다.")
    return B


def _nearest_peak_phrase(lt, peaks):
    others = [(dte, v) for dte, v in peaks[1:] if abs(v - lt["score"]) / max(v, 1e-9) < 0.5]
    if not others:
        return ""
    dte, v = min(others, key=lambda t: abs(t[1] - lt["score"]))
    return f"최근 사례 중에서는 {kdate(dte)}({v:.1f}점) 전후와 비슷한 수준입니다."


def build_markdown(meta, d, st, eps, cv, nsr, rob, day, peaks):
    lt = meta["latest"]
    ko = meta["axis_ko"]
    axes = meta["axes"]
    ns = nsr.get("v1", {})
    tier = tier_of(lt["score_pct"], ns)
    prev = d.iloc[-2] if len(d) > 1 else d.iloc[-1]
    q = d["score"].quantile([.5, .8, .9, .95, .99])
    L = []
    A = L.append

    A(f"# 국내 자본시장 스트레스 일일 보고 — {kdate(day)} 기준")
    A("")
    A(f"작성 {meta['run_at'][:10]} · 지수 산출 기준일 {day}(마지막 거래일 마감 자료) · 연구 시제품(KR-CISS v1) — 투자 판단의 유일한 근거로 쓰지 마시기 바랍니다.")
    A("")
    # 헤드라인 카드
    cards = html_table(
        ["오늘의 스트레스 지수", "과거 대비 위치", "경보 단계", "20거래일 전 → 오늘", "비교: V-KOSPI200"],
        [[f'<span style="font-size:20pt;font-weight:700">{lt["score"]:.1f}</span><span style="color:#666"> / 100</span>',
          f'<span style="font-size:20pt;font-weight:700">{rank_phrase(lt["score_pct"])}</span><br><span style="color:#666">백분위 {pct(lt["score_pct"])}</span>',
          f'<span style="display:inline-block;padding:6px 18px;background:{TIER_FILL[tier]};font-size:15pt;font-weight:700;border-radius:4px">{tier}</span>',
          f'<span style="font-size:13pt">{lt["score_20td_ago"]:.1f} → {lt["score"]:.1f}</span><br>{chg_phrase(lt["score"] - lt["score_20td_ago"])}',
          f'<span style="font-size:13pt">{lt["vkospi"]:.1f}</span><br><span style="color:#666">{rank_phrase(lt["vkospi_pct"])}</span>']],
        aligns=["center"] * 5)
    A(cards)
    A("")
    A("## 1. 핵심 요약")
    A("")
    for b in summary_bullets(meta, d, st, eps, cv, ns, peaks):
        A(f"- {b}")
    A("")
    A('<img src="d1_gauge.png" alt="게이지" style="width:100%">')
    A("")
    A(f"위 눈금은 오늘의 지수가 2006년 이후 전체 거래일 가운데 어디쯤인지를 보여 드립니다. 초록 구간은 평소, 노랑은 주의, 빨강은 2008년 · 2020년 같은 극단적 위기 수준입니다. "
      f"전일 {prev['score']:.1f}점({str(prev.name.date())}) · 60거래일 전 {lt['score_60td_ago']:.1f}점({lt['date_60td_ago']}) 이었습니다.")
    A("")

    # ── 2. 축별 분해 ──
    A("## 2. 어느 분야에서 온 스트레스인가")
    A("")
    A("지수는 12개 분야의 상태를 합친 값이며, 아래 표는 그 합계를 분야별로 나눈 것입니다. **'과거 대비 위치'** 는 그 분야가 2006년 이후 모든 날과 비교해 몇 퍼센트 자리에 있는지(백분위)이고, "
      "**'기여'** 는 오늘 지수 가운데 그 분야 몫(점)입니다. 기여가 음수인 분야는 다른 분야와 반대로 움직여 전체 체계적 위험을 오히려 낮추고 있는 분야입니다.")
    A("")
    rows = []
    for a in sorted(axes, key=lambda a: -lt["contrib"][a]):
        p = lt["axis_pct"][a]
        lab, fg, bg = status(p)
        sub = st[st.axis == a]
        hot = ", ".join(IND_PLAIN.get(r.id, r.name) for r in sub[sub.ecdf_pct >= 0.8].sort_values("ecdf_pct", ascending=False).itertuples()) or "—"
        fresh = max(int(x) for x in sub.stale_trading_days.fillna(0))
        name, plain = AXIS_PLAIN[a]
        rows.append([
            f'<span style="display:inline-block;padding:2px 7px;border-radius:3px;background:{bg};color:{fg};font-weight:700;white-space:nowrap">{lab}</span>',
            f'<b>{name}</b><br><span style="color:#555;font-size:7.8pt">{plain}</span>',
            f'{bar(p, fg)} <b>{pct(p)}</b>',
            f'<b>{lt["contrib"][a]:.1f}</b>',
            chg_phrase(lt["contrib"][a] - lt["contrib_20td_ago"][a]),
            f'<span style="font-size:7.8pt">{hot}</span>',
            f'<span style="font-size:7.8pt;color:#555">{"당일" if fresh == 0 else f"{fresh}거래일 전"}</span>'])
    A(html_table(["상태", "분야", "과거 대비 위치(%)", "기여(점)", "20거래일 전 대비", "지금 높은 세부 지표(과거 대비 80% 이상)", "자료 시점"],
                 rows, aligns=["center", "left", "left", "right", "center", "left", "center"], widths=["9%", "22%", "15%", "7%", "11%", "28%", "8%"]))
    A("")
    top = sorted(axes, key=lambda a: -lt["contrib"][a])[:3]
    A(f"가장 큰 몫은 **{AXIS_PLAIN[top[0]][0]}**({lt['contrib'][top[0]]:.1f}점)이고, 이어서 {AXIS_PLAIN[top[1]][0]}({lt['contrib'][top[1]]:.1f}점) · {AXIS_PLAIN[top[2]][0]}({lt['contrib'][top[2]]:.1f}점) 순입니다. "
      f"분야들이 서로 얼마나 같이 움직이는지를 나타내는 평균 상관은 {lt['avg_corr']:.2f}" +
      ("로 높은 편이어서 여러 분야가 한꺼번에 흔들리는 국면입니다." if lt["avg_corr"] >= 0.3 else "로 낮은 편입니다. 일부 분야가 크게 흔들려도 다른 분야가 따라 움직이지 않을 때 지수는 완만하게 오릅니다 — 지금이 그 경우입니다.") +
      f" 비교를 위해 12개 분야 수치를 단순 평균하면 {lt['score_linear']:.1f}점이 되는데, 지수가 그보다 낮은 것은 분야 간 동행이 약하다는 뜻입니다.")
    A("")
    A('<img src="d2_axis_contrib.png" alt="축별 기여" style="width:100%">')
    A("")

    # ── 3. 어떻게 쌓였나 ──
    A("## 3. 최근 석 달, 분야별로 언제 켜졌는가")
    A("")
    runs = _axis_runs(d, axes)
    all_on = [AXIS_PLAIN[a][0] for a in axes if runs.get(a) and runs[a][0] == "all"]
    since = sorted([(runs[a][1], a, runs[a][2]) for a in axes if runs.get(a) and runs[a][0] == "since"], key=lambda t: t[0])
    low = [AXIS_PLAIN[a][0] for a in axes if runs.get(a) and runs[a][0] == "low"]
    s = []
    if all_on:
        s.append("**" + " · ".join(all_on) + "** 은 최근 석 달 내내 높은 상태(과거 대비 80% 이상)를 유지해 왔습니다")
    if since:
        s.append("그 뒤로 " + ", ".join(f"**{AXIS_PLAIN[a][0]}** 은 {kdate(t)}부터({k}거래일째)" for t, a, k in since) + " 높은 상태에 들어왔습니다")
    if low:
        s.append("**" + " · ".join(low) + "** 은 아직 높은 상태가 아닙니다")
    A(". ".join(s) + ".")
    A("")
    A('<img src="d3_heatmap_65d.png" alt="히트맵" style="width:100%">')
    A("")
    A("색이 붉을수록 그 날 그 분야가 과거와 비교해 높은 스트레스 상태였다는 뜻입니다. 맨 윗줄이 종합 지수이고, 맨 오른쪽 열의 숫자가 오늘 값입니다. 위에서부터 아래로 붉은 띠가 넓어지면 스트레스가 다른 분야로 번지고 있는 것입니다.")
    A("")

    # ── 4. 과거 위기와 비교 ──
    A("## 4. 과거 위기와 비교하면")
    A("")
    A('<img src="d4_radar_hist.png" alt="레이더 · 분포" style="width:100%">')
    A("")
    tmax = pd.Timestamp(lt["max_score_date"])
    ref = {a: float(d.loc[tmax, f"pct_{a}"]) for a in axes} if tmax in d.index else {}
    gap = sorted(((ref[a] - lt["axis_pct"][a], a) for a in ref), reverse=True)[:3]
    A(f"왼쪽 그림의 파란 면이 오늘, 점선이 {kdate(tmax)}(2008년 금융위기 정점)입니다. 바깥으로 나갈수록 그 분야의 스트레스가 큽니다. 2008년에는 12개 분야가 거의 모두 바깥쪽에 있었던 반면, 오늘은 "
      + " · ".join(AXIS_PLAIN[a][0] for a in axes if lt["axis_pct"][a] >= 0.9) + " 쪽만 바깥에 있고 "
      + (" · ".join(f"{AXIS_PLAIN[a][0]}" for _, a in gap) + " 은 2008년과 가장 크게 다릅니다(아직 평온)." if gap else "") +
      f" 오른쪽 그림은 2006년 이후 {len(d):,} 거래일의 지수 분포이며 붉은 세로선이 오늘입니다. 전체 거래일의 절반은 {q[.5]:.1f}점 아래, 90%는 {q[.9]:.1f}점 아래, 95%는 {q[.95]:.1f}점 아래였습니다.")
    A("")
    prow = []
    for i, (dte, v) in enumerate(peaks, start=1):
        prow.append([str(i), kdate(dte), f"{v:.1f}", f"{100 * lt['score'] / v:.0f}%", _peak_label(dte)])
    prow.append(["—", f"<b>오늘 {kdate(day)}</b>", f"<b>{lt['score']:.1f}</b>", "100%", f"<b>{tier}</b>"])
    A(html_table(["순위", "스트레스가 가장 높았던 시기(90일 간격)", "지수", "오늘 / 당시", "당시 상황"], prow, aligns=["center", "left", "right", "right", "left"]))
    A("")

    # ── 5. 최근 18개월 ──
    A("## 5. 최근 18개월의 흐름")
    A("")
    e = eps[pd.to_datetime(eps["peak"]) >= d.index[-1] - pd.DateOffset(months=18)]
    cvm = {str(r.peak): r for r in cv.itertuples()} if len(cv) else {}
    parts = []
    for r in e.itertuples():
        c = cvm.get(str(r.peak))
        mx = f"지수 최고 {c.score_max:.1f}점({kdate(c.score_max_date)})" if c is not None and c.score_max == c.score_max else ""
        parts.append(f"{kdate(r.peak)} 고점 이후 {100 * r.depth:.0f}% 하락{'(진행 중)' if r.ongoing else f'(저점 {kdate(r.trough)})'}" + (f" — {mx}" if mx else ""))
    if parts:
        A("코스피200 기준으로 최근 18개월 사이 고점 대비 20% 이상의 급락이 " + f"{len(parts)}차례 있었습니다: " + "; ".join(parts) + ". 지수는 매번 급락과 거의 동시에 올랐고, 급락이 멈추면 몇 주 안에 내려왔습니다.")
    else:
        A("최근 18개월 사이 코스피200 기준 고점 대비 20% 이상의 급락은 없었습니다.")
    A("")
    A('<img src="d6_recent_18m.png" alt="최근 18개월" style="width:100%">')
    A("")

    # ── 6. 세부 지표 ──
    A("## 6. 세부 지표 34개 — 무엇이 극단에 있는가")
    A("")
    A("지수를 이루는 34개 세부 지표를 분야별로 묶어 과거 대비 위치를 표시했습니다. 검은 점이 오늘, 흰 점이 20거래일 전입니다. 점이 오른쪽 빨간 선(90%)을 넘으면 2006년 이후 상위 10% 안의 이례적 수준입니다.")
    A("")
    A('<img src="d5_indicators.png" alt="34지표" style="width:100%">')
    A("")
    half = len(axes) // 2
    for k, grp in enumerate((axes[:half], axes[half:]), start=1):
        A(f"#### 6.{k} {' · '.join(AXIS_PLAIN[a][0] for a in grp)}")
        A("")
        irows = []
        for r in st[st.axis.isin(grp)].itertuples():
            v = r.value
            vs = f"{v:.4g}" if abs(v) < 1 else f"{v:.2f}" if abs(v) < 100 else f"{v:.1f}"
            lab, fg, bg = status(r.ecdf_pct)
            irows.append([f'<span style="color:#555">{AXIS_PLAIN[r.axis][0]}</span>', IND_PLAIN.get(r.id, r.name), vs,
                          f'<span style="display:inline-block;padding:1px 6px;border-radius:3px;background:{bg};color:{fg};font-weight:700">{100 * r.ecdf_pct:.0f}</span>',
                          f"{100 * r.ecdf_pct_20td_ago:.0f}", f"{r.contrib:+.2f}", f'<span style="color:#555">{r.last_obs_date}</span>'])
        A(html_table(["분야", "세부 지표(쉬운 설명)", "오늘 값", "과거 대비 위치(%)", "20거래일 전(%)", "기여(점)", "자료일"], irows,
                     aligns=["left", "left", "right", "center", "center", "right", "center"], widths=["11%", "40%", "9%", "11%", "10%", "8%", "11%"], small=True))
        A("")

    # ── 7. 전 기간 ──
    A("## 7. 2006년 이후 전체 흐름")
    A("")
    A('<img src="d7_history.png" alt="전 기간" style="width:100%">')
    A("")
    A(f"회색 띠는 코스피200 이 고점 대비 20% 넘게 떨어진 구간(고점에서 저점까지)입니다. 지수는 2008년 금융위기(최고 {peaks[0][1]:.1f}점), 2020년 코로나 급락, 2022년 금리 급등 · 레고랜드 사태, 그리고 올해의 세 차례 급락에서 모두 뚜렷한 봉우리를 만들었습니다. "
      "아래 그림의 V-KOSPI200(옵션시장이 보는 향후 변동성)과 견주어 보시면, 주식시장만 흔들릴 때는 V-KOSPI 가 더 민감하고, 여러 시장이 함께 흔들릴 때 이 지수가 더 높이 오르는 차이를 보실 수 있습니다.")
    A("")

    # ── 8. 유의사항 ──
    A("## 8. 보고서를 읽으실 때 유의하실 점")
    A("")
    A("- **동시성**: 이 지수는 시장 급락과 거의 동시에 오릅니다. 고점을 미리 알려 주지는 못하지만, '공식적인 약세장 기준(고점 대비 -20%)' 보다는 대개 먼저 경보 수준에 도달했습니다.")
    A("- **숫자보다 위치**: 지수의 절대값은 계산 방식(분야 간 상관의 기억 길이 등)에 따라 달라질 수 있으나, '과거 대비 위치(백분위)' 는 방식과 무관하게 안정적입니다. 보고서의 판단은 모두 백분위를 기준으로 합니다.")
    A("- **자료 시점**: 국내 주식 · 수급 자료는 전 거래일 마감 기준이고, 금리 · 환율 · 해외 자료는 공표 시차를 반영해 실제로 알 수 있었던 날짜의 값만 씁니다(미래 정보 없음). 각 분야의 자료 시점은 2절 표의 마지막 열에 있습니다.")
    A("- **경보 단계**: 주의 · 위험 문턱은 2006~2022년 자료에서 '허위 경보 대비 적중' 비율이 가장 좋은 지점으로 정했습니다. 위험 단계(상위 1%)는 2008년 · 2020년 수준에서만 켜집니다.")
    A("- **성격**: 연구용 시제품입니다. 투자 등급 · 포트폴리오 결정과 연결되어 있지 않으며, 단독 근거로 쓰기보다 시장 상황을 공유하는 온도계로 활용하시기 바랍니다.")
    A("")
    A("#### 부록 · 용어 풀이")
    A("")
    A("- **스트레스 지수(0~100)**: 12개 분야 34개 세부 지표를 각각 '과거 대비 위치' 로 바꾼 뒤, 분야들이 **함께** 움직일수록 크게 치도록 합친 값입니다(유럽중앙은행 CISS 방식). 한 분야만 크게 흔들리면 지수는 완만하게, 여러 분야가 동시에 흔들리면 가파르게 오릅니다.")
    A("- **과거 대비 위치(백분위)**: 2006년 이후 전체 거래일 중 오늘보다 낮았던 날의 비율(%)입니다. 93이면 상위 7% 안입니다. 모든 비교는 그 시점까지의 과거만 써서 계산합니다.")
    A("- **기여(점)**: 오늘 지수 가운데 각 분야의 몫입니다. 12개 분야의 기여를 모두 더하면 지수가 됩니다.")
    A("- **분야 설명**: " + " / ".join(f"{AXIS_PLAIN[a][0]} = {AXIS_PLAIN[a][1]}" for a in axes) + ".")
    A("- **자료 출처**: 한국거래소 시세 · 투자자 수급(퀀티와이즈), 한국은행 ECOS(금리 · 환율), 미국 연준 FRED(VIX · 금융스트레스), V-KOSPI200. 산출 방법과 수치 근거는 `DESIGN_v1_capital_market.md` 와 `output/v1/run_meta.json` 에 있습니다.")
    A("")
    return "\n".join(L) + "\n"


def _peak_label(dte):
    y, m = pd.Timestamp(dte).year, pd.Timestamp(dte).month
    if y == 2008 or (y == 2009 and m <= 3):
        return "글로벌 금융위기"
    if y == 2020 and m <= 6:
        return "코로나19 급락"
    if y == 2011:
        return "유럽 재정위기 · 미국 신용등급 강등"
    if y == 2022 and m >= 9:
        return "레고랜드 자금시장 경색"
    if y == 2022:
        return "금리 급등 · 약세장"
    if y == 2023:
        return "미국 금리 급등 · 원화 약세"
    if y == 2026:
        return "2026년 급락기"
    return ""
