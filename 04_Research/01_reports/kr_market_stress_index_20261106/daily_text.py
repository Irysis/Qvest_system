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
# 상태 라벨 = 미세먼지 예보처럼 '높을수록 나쁨' 이 바로 읽히는 말(도훈 11-06) — 심각도 ≥90 매우 나쁨 · ≥80 나쁨 · ≥60 다소 나쁨 · 그 외 보통
STATUS = [(0.90, "매우 나쁨", "#c62828", "#ffcdd2"), (0.80, "나쁨", "#ef6c00", "#ffe0b2"), (0.60, "다소 나쁨", "#f9a825", "#fff3c4"), (-1, "보통", "#2e7d32", "#c8e6c9")]
SEV = "심각도"            # = 2006년 이후 거래일 중 오늘보다 평온했던 날의 비율(%) · 0 = 역대 가장 평온 · 100 = 역대 최악 (분야 · 세부 지표에 쓴다)
SEV_NOTE = "심각도(%) · 높을수록 나쁨"
RANK = "역대 순위"        # 종합 점수의 2006년 이후 백분위 — 카드에서는 '나쁜 순 상위 n%' 로 읽는다
TIER_FILL = {"정상": "#c8e6c9", "주의": "#fff3c4", "위험": "#ffcdd2"}

# ★점수 눈금(도훈 11-06 "점수를 좀 더 직관적으로") — 보고서의 '스트레스 점수' = 10·√(CISS 원값).
#   CISS 원값은 '분야들이 같이 움직일수록 커지는 합'(포트폴리오 분산과 같은 꼴)이라 0~100 눈금의 아래쪽에 몰린다(2006년 이후 중앙값 2 · 2008년 정점 67).
#   분산을 변동성(제곱근)으로 읽듯 제곱근을 취하면 평상시 14 · 2011년 46 · 2020년 61 · 2008년 82 로 눈금이 고르게 펴진다.
#   단조 변환이므로 백분위 · 경보 단계 · 위기 검증은 전혀 바뀌지 않는다. 분야별 기여도는 같은 비율로 나눈다(제곱근의 오일러 배분 — 합 = 점수). 보고서 어휘 = '기여도'(도훈 11-06 — '몫' 금지).
def level_of(score):
    """CISS 원값(0~100) → 스트레스 점수(0~100 · 제곱근 눈금)."""
    return 10.0 * (max(float(score), 0.0) ** 0.5)


# 점수 눈금의 기준점이 되는 잘 알려진 위기(표시용 라벨 — 창 안의 최고 점수를 쓴다 · 수치 튜닝 아님)
REF_EVENTS = [("2008년 금융위기", "2008-01-01", "2009-06-30"), ("2011년 유럽 재정위기", "2011-07-01", "2011-12-31"),
              ("2020년 코로나 급락", "2020-02-01", "2020-06-30"), ("2022년 금리 급등", "2022-01-01", "2022-12-31")]


def ref_marks(d):
    """점수 눈금 기준점 = 평상시(중앙값) + 잘 알려진 위기들의 정점 점수(낮은 순)."""
    out = [{"label": "평상시(중앙값)", "short": "평상시", "level": float(d["level"].median()), "date": None, "kind": "median"}]
    for lab, a, b in REF_EVENTS:
        w = d.loc[a:b, "level"].dropna()
        if len(w):
            out.append({"label": lab, "short": lab.replace("년 ", " "), "level": float(w.max()), "date": str(w.idxmax().date()), "kind": "crisis"})
    return sorted(out, key=lambda r: r["level"])


def scale_phrase(meta):
    return " · ".join(f"{r['label']} {r['level']:.0f}" for r in meta["ref_marks"])


def status(p):
    p = round(100 * p) / 100.0   # 표시 숫자(정수 %)와 같은 기준으로 판정 — 89.6 은 '90' 으로 보이므로 '매우 높음'
    for th, lab, fg, bg in STATUS:
        if p >= th:
            return lab, fg, bg
    return STATUS[-1][1:]


def pct(x):
    return "—" if x is None or (isinstance(x, float) and x != x) else f"{100 * x:.0f}"


def rank_phrase(p):
    """심각도 → '나쁜 순으로 상위 n%' 말(높을수록 나쁨이 바로 읽히게)."""
    return f"나쁜 순으로 상위 {max(1, round(100 - 100 * p)):.0f}%"


def tier_of(p, ns):
    if ns.get("threshold_risk") is not None and p >= ns["threshold_risk"]:
        return "위험"
    if ns.get("threshold_warn") is not None and p >= ns["threshold_warn"]:
        return "주의"
    return "정상"


def kdate(x):
    t = pd.Timestamp(x)
    return f"{t.year}년 {t.month}월 {t.day}일"


# 인쇄(PDF)에서는 크로미움이 배경색을 기본으로 버린다 — 색이 있는 요소마다 print-color-adjust 를 박아야 칩 · 막대 · 머리 행 색이 PDF 에 남는다.
PC = "-webkit-print-color-adjust:exact;print-color-adjust:exact;"


def chip(color):
    return f'<span style="display:inline-block;width:9px;height:9px;border-radius:5px;background:{color};margin-right:5px;vertical-align:middle;{PC}"></span>'


def bar(p, color, width_px=70):
    w = max(2, int(round(width_px * max(0.0, min(1.0, p)))))
    return (f'<span style="display:inline-block;width:{width_px}px;height:9px;background:#e6e6e6;vertical-align:middle;border-radius:2px;{PC}">'
            f'<span style="display:inline-block;width:{w}px;height:9px;background:{color};border-radius:2px;{PC}"></span></span>')


def badge(text, fg, bg, size="8.4pt"):
    return f'<span style="display:inline-block;padding:2px 7px;border-radius:3px;background:{bg};color:{fg};font-weight:700;white-space:nowrap;font-size:{size};{PC}">{text}</span>'


def sparkline(values, color, w=84, h=18, bands=True):
    """최근 n일 심각도(0~1) 추이 — 인라인 SVG(크로미움 인쇄 통과). 띠 = 보통/다소 나쁨/나쁨/매우 나쁨(60 · 80 · 90)."""
    v = [x for x in values if x == x]
    if len(v) < 2:
        return ""
    n = len(v)
    xs = [i * (w - 2) / (n - 1) + 1 for i in range(n)]
    ys = [h - 1 - max(0.0, min(1.0, x)) * (h - 2) for x in v]
    pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in zip(xs, ys))
    rects = ""
    if bands:
        for lo, hi, col in ((0.0, 0.6, "#e8f5e9"), (0.6, 0.8, "#fff8e1"), (0.8, 0.9, "#ffe9d6"), (0.9, 1.0, "#ffe0e0")):
            y0 = h - 1 - hi * (h - 2)
            rects += f'<rect x="0" y="{y0:.1f}" width="{w}" height="{(hi - lo) * (h - 2):.1f}" fill="{col}"/>'
    return (f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}" style="vertical-align:middle;{PC}">{rects}'
            f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="1.4"/>'
            f'<circle cx="{xs[-1]:.1f}" cy="{ys[-1]:.1f}" r="2.2" fill="{color}"/></svg>')


def html_table(headers, rows, aligns=None, widths=None, small=False, row_bg=None):
    fs = "font-size:8.2pt;" if small else ""
    th = "".join(f'<th style="background:#1f4e79;color:#ffffff;padding:4px 5px;text-align:center;border:1px solid #16395a;{fs}{PC}' +
                 (f'width:{widths[i]}' if widths and widths[i] else "") + f'">{h}</th>' for i, h in enumerate(headers))
    body = []
    for k, r in enumerate(rows):
        bg = (row_bg[k] if row_bg and row_bg[k] else ("#f7f7f7" if k % 2 else "#ffffff"))
        tds = []
        for i, c in enumerate(r):
            al = (aligns[i] if aligns else "left")
            # white-space:normal 은 PDF 도구 CSS 의 `td:first-child { white-space: nowrap }` 를 이긴다(인라인 우선) — 첫 칸에 긴 글이 오면
            # 첫 열이 쪽 폭을 다 먹고 나머지 열이 세로 글자로 무너지던 사고(11-06 1쪽 카드 표) 방지
            tds.append(f'<td style="padding:3px 5px;border:1px solid #dcdcdc;text-align:{al};vertical-align:middle;background:{bg};white-space:normal;{fs}{PC}">{c}</td>')
        body.append("<tr>" + "".join(tds) + "</tr>")
    return (f'<table style="width:100%;border-collapse:collapse;margin:4px 0 6px 0"><thead><tr>{th}</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table>')


def chg_phrase(delta, unit="점", fmt="+.1f"):
    if delta > 0.05:
        return f'<span style="color:#c62828">▲ {delta:{fmt}}{unit}</span>'
    if delta < -0.05:
        return f'<span style="color:#2e7d32">▼ {delta:{fmt}}{unit}</span>'
    return f'<span style="color:#777777">— {delta:{fmt}}{unit}</span>'


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
    lv = meta["levels"]
    refs = {r["label"]: r["level"] for r in meta["ref_marks"]}
    p = lt["score_pct"]
    tier = tier_of(p, ns)
    B = []
    B.append(f"오늘의 자본시장 스트레스 점수는 **{lt['level']:.0f}점**(0~100 · **높을수록 나쁨**)입니다. 이 눈금에서 평상시는 {lv['median']:.0f}점 안팎이고, "
             f"2020년 코로나 급락 때 {refs.get('2020년 코로나 급락', float('nan')):.0f}점, 2008년 금융위기 정점에 {refs.get('2008년 금융위기', float('nan')):.0f}점까지 올랐습니다. "
             f"2006년 이후 모든 거래일과 비교하면 **{rank_phrase(p)}** 에 해당하며, 경보 단계는 **'{tier}'** 입니다"
             f"(점수 {lv['warn']:.0f} 이상이면 주의 · {lv['risk']:.0f} 이상이면 위험 — 각각 2006년 이후 나쁜 순 상위 {100 - 100 * ns.get('threshold_warn', 0.8):.0f}% · 상위 {100 - 100 * ns.get('threshold_risk', 0.99):.0f}% 선입니다).")
    order = sorted(axes, key=lambda a: -lt["contrib_level"][a])
    top = order[:3]
    share = sum(lt["contrib_level"][a] for a in top) / lt["level"] if lt["level"] else float("nan")
    B.append("스트레스의 " + (f"약 {100 * share:.0f}%" if share == share else "대부분") + "는 " +
             " · ".join(f"**{AXIS_PLAIN[a][0]}**(심각도 {pct(lt['axis_pct'][a])})" for a in top) +
             " 세 분야에서 오고 있습니다. 심각도는 그 분야가 2006년 이후 어느 자리에 있는지(0 = 역대 가장 평온 · 100 = 역대 최악)이며, 90 이상이면 나쁜 순으로 상위 10% 안에 드는 이례적 수준입니다.")
    calm = [a for a in axes if lt["axis_pct"][a] <= 0.45]
    sys_axes = ("credit", "fx", "global")
    if all(lt["axis_pct"][a] <= 0.5 for a in sys_axes):
        B.append("반면 " + " · ".join(f"{AXIS_PLAIN[a][0]}(심각도 {pct(lt['axis_pct'][a])})" for a in sys_axes) +
                 " 은 평온합니다. 회사채 · 환율 · 해외로 번지지 않았다는 뜻이므로, 현재는 **금융시스템 전반의 위기라기보다 주식시장 내부의 조정**에 가까운 모습으로 판단됩니다.")
    elif calm:
        B.append("반면 " + " · ".join(f"{AXIS_PLAIN[a][0]}(심각도 {pct(lt['axis_pct'][a])})" for a in calm) + " 은 평온한 수준입니다.")
    else:
        B.append("모든 분야가 동시에 높은 상태로, 분절을 가리지 않고 번진 체계적 스트레스의 모습입니다.")
    cm, cm_med, cm_max = 100 * lt["comove"], 100 * lv["comove_median"], 100 * lv["comove_at_max"]
    B.append(f"점수가 이렇게 나온 이유를 두 숫자로 나누면, 34개 세부 지표는 평균적으로 심각도 **{lt['score_linear']:.0f}** 자리에 있고(평상시 {lv['linear_median']:.0f}), "
             f"분야들이 함께 움직이는 정도(동행률)는 **{cm:.0f}%** 입니다(평상시 {cm_med:.0f}% · 2008년 정점 {cm_max:.0f}%). 모든 분야가 완전히 같이 움직였다면 점수도 {lt['score_linear']:.0f}점이 됐을 텐데, "
             + ("동행이 평소보다 훨씬 강해 점수가 여기까지 올랐습니다. 다만 2008년처럼 모든 분야가 한 방향으로 무너지는 모습은 아닙니다." if cm >= cm_med + 10 else
                "분야 간 동행이 약해 점수는 그보다 낮은 자리에 머물렀습니다."))
    chg = lt["level"] - lt["level_20td_ago"]
    dcon = sorted(axes, key=lambda a: -(lt["contrib_level"][a] - lt["contrib_level_20td_ago"][a]))[:2]
    dir_ = "크게 높아졌습니다" if chg > 5 else "높아졌습니다" if chg > 1 else "낮아졌습니다" if chg < -1 else "비슷한 수준입니다"
    B.append(f"20거래일 전({kdate(lt['date_20td_ago'])}) {lt['level_20td_ago']:.0f}점에서 {lt['level']:.0f}점으로 {dir_}" +
             (f"({chg:+.0f}점). 그 사이 가장 많이 오른 분야는 {AXIS_PLAIN[dcon[0]][0]}(+{lt['contrib_level'][dcon[0]] - lt['contrib_level_20td_ago'][dcon[0]]:.1f}점)과 "
              f"{AXIS_PLAIN[dcon[1]][0]}(+{lt['contrib_level'][dcon[1]] - lt['contrib_level_20td_ago'][dcon[1]]:.1f}점)입니다." if chg > 1 else "."))
    if peaks:
        pmax_d, pmax = peaks[0]
        B.append(f"과거와 비교하면 역대 최고였던 {kdate(pmax_d)}({_peak_label(pmax_d)} · {pmax:.0f}점)의 {100 * lt['level'] / pmax:.0f}% 수준입니다. "
                 + _nearest_peak_phrase(lt, peaks, d.index[-1]))
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


def _nearest_peak_phrase(lt, peaks, today):
    """오늘과 8점 안에 드는 과거 봉우리(오늘 속한 급락기 = 90일 안쪽은 제외) 중 가장 가까운 것."""
    others = [(dte, v) for dte, v in peaks[1:] if abs(v - lt["level"]) <= 8 and pd.Timestamp(dte) < pd.Timestamp(today) - pd.Timedelta(days=90)]
    if not others:
        return ""
    dte, v = min(others, key=lambda t: abs(t[1] - lt["level"]))
    return f"과거 사례 중에서는 {kdate(dte)}({_peak_label(dte) or '급락기'} · {v:.0f}점) 전후와 비슷한 수준입니다."


def build_markdown(meta, d, st, eps, cv, nsr, rob, day, peaks):
    lt = meta["latest"]
    ko = meta["axis_ko"]
    axes = meta["axes"]
    ns = nsr.get("v1", {})
    tier = tier_of(lt["score_pct"], ns)
    prev = d.iloc[-2] if len(d) > 1 else d.iloc[-1]
    q = d["level"].quantile([.5, .8, .9, .95, .99])
    lv = meta["levels"]
    refs = {r["label"]: r["level"] for r in meta["ref_marks"]}
    L = []
    A = L.append

    A(f"# 국내 자본시장 스트레스 일일 보고 — {kdate(day)} 기준")
    A("")
    A(f"작성 {meta['run_at'][:10]} · 지수 산출 기준일 {day}(마지막 거래일 마감 자료) · 연구 시제품(KR-CISS v1) — 투자 판단의 유일한 근거로 쓰지 마시기 바랍니다.")
    A("")
    # 헤드라인 카드 — 점수(제곱근 눈금 · 기준점 병기) · 역대 순위 · 단계 · 변화 · V-KOSPI
    lab, fg, bg = status(lt["score_pct"])
    top_pct = max(1, round(100 - 100 * lt["score_pct"]))
    # ★카드 칸의 글은 짧게 — 긴 기준점 줄은 표 아래 '점수 눈금 읽기' 한 줄에만(첫 칸이 길면 PDF 표 열 배분이 무너진다 · 11-06 실사고)
    cards = html_table(
        ["오늘의 스트레스 점수<br><span style=\"font-weight:400;font-size:7.6pt\">0~100 · 높을수록 나쁨</span>",
         f"{RANK}<br><span style=\"font-weight:400;font-size:7.6pt\">2006년 이후 {len(d):,} 거래일 · 나쁜 순</span>",
         f"경보 단계<br><span style=\"font-weight:400;font-size:7.6pt\">주의 {lv['warn']:.0f}점 이상 · 위험 {lv['risk']:.0f}점 이상</span>",
         "20거래일 전 → 오늘", "비교: V-KOSPI200<br><span style=\"font-weight:400;font-size:7.6pt\">옵션시장이 보는 변동성</span>"],
        [[f'<span style="font-size:23pt;font-weight:700;color:{fg}">{lt["level"]:.0f}</span><span style="color:#666"> / 100</span>'
          f'<br><span style="color:#444;font-size:7.6pt">평상시 {lv["median"]:.0f} · 2008년 정점 {refs.get("2008년 금융위기", float("nan")):.0f}</span>',
          f'<span style="font-size:19pt;font-weight:700;color:{fg}">상위 {top_pct}%</span><br><span style="color:#444;font-size:7.6pt">백분위 {pct(lt["score_pct"])} — 거래일의 {pct(lt["score_pct"])}% 가 오늘보다 평온</span>',
          f'<span style="display:inline-block;padding:6px 18px;background:{TIER_FILL[tier]};font-size:15pt;font-weight:700;border-radius:4px;{PC}">{tier}</span>',
          f'<span style="font-size:13pt">{lt["level_20td_ago"]:.0f} → {lt["level"]:.0f}</span><br>{chg_phrase(lt["level"] - lt["level_20td_ago"], fmt="+.0f")}',
          f'<span style="font-size:13pt">{lt["vkospi"]:.1f}</span><br><span style="color:#444">{rank_phrase(lt["vkospi_pct"])}</span>']],
        aligns=["center"] * 5, widths=["24%", "24%", "18%", "16%", "18%"])
    A(cards)
    A("")
    A(f'<span style="font-size:7.8pt;color:#444">점수 눈금 읽기 — {scale_phrase(meta)} · 100 = 12개 분야가 모두 역대 최악이면서 한 방향으로 움직일 때. '
      f'점수는 34개 세부 지표의 심각도를 분야들이 **함께** 움직일수록 크게 치도록 합친 값입니다(유럽중앙은행 CISS 방식 · 제곱근 눈금).</span>')
    A("")
    A("## 1. 핵심 요약")
    A("")
    for b in summary_bullets(meta, d, st, eps, cv, ns, peaks):
        A(f"- {b}")
    A("")
    # 오늘의 해설(선택) — make_commentary.py 가 Sonnet 으로 쓰고 숫자 자동 검사를 통과한 경우에만(같은 기준일 · passed). 없거나 불통과면 이 절은 없다.
    cm = _commentary(day)
    if cm:
        A(f"#### 오늘의 해설 — AI 작성({cm['model_label']}) · 숫자 출처 자동 검사 통과")
        A("")
        A(cm["text"])
        A("")
        A('<span style="font-size:7.6pt;color:#666">위 단락은 AI 가 이 보고서의 데이터만 보고 쓴 해설입니다. 본문의 모든 숫자는 데이터의 출처 항목으로 자동 재계산해 일치를 확인했으며, '
          '예측 · 전망 표현은 싣지 않습니다. 해설이 검사를 통과하지 못한 날은 이 단락 없이 발행됩니다.</span>')
        A("")
    # 소제목으로 블록을 나눈다 — PDF 도구는 제목~다음 제목을 한 덩어리(쪽 나눔 금지)로 묶으므로, 요약 글머리와 게이지를 한 덩어리로 두면
    # 1쪽에 못 들어갈 때 요약까지 통째로 2쪽으로 밀린다(1쪽 = 제목 + 카드만 남는 양식 사고)
    A("#### 오늘의 자리 — 0~100 눈금과 최근 1년의 길")
    A("")
    A('<img src="d1_gauge.png" alt="게이지" style="width:100%">')
    A("")
    A(f"위 그림의 윗부분은 오늘의 점수가 0~100 눈금 어디에 있는지를 과거 위기의 정점(눈금 아래 표시)과 나란히 보여 드리고, 아랫부분은 최근 1년 동안 점수가 어떤 길을 밟아 지금에 이르렀는지를 보여 드립니다. "
      f"초록 구간은 평소, 노랑은 주의, 빨강은 2008년 · 2020년 같은 극단적 위기 수준입니다. 전일 {prev['level']:.0f}점({str(prev.name.date())}) · 60거래일 전 {lt['level_60td_ago']:.0f}점({lt['date_60td_ago']}) 이었습니다.")
    A("")

    # ── 2. 축별 분해 ──
    # 그림(짧은 블록) → 소제목 → 표(긴 블록) 순 — PDF 도구가 제목 단위로 쪽 나눔을 막으므로, 그림을 앞에 따로 두면 게이지 쪽의 남는 자리에 들어간다
    A("## 2. 어느 분야에서 온 스트레스인가")
    A("")
    A(f"점수는 12개 분야의 상태를 합친 값입니다. 아래 그림은 오늘 점수 {lt['level']:.0f}점을 분야별 기여도로 나눈 것(진한 막대 · 모두 더하면 {lt['level']:.0f}점)이고, 연한 막대는 20거래일 전의 기여도, 오른쪽 칩은 그 분야의 심각도(0 = 역대 가장 평온 · 100 = 역대 최악)입니다.")
    A("")
    A('<img src="d2_axis_contrib.png" alt="축별 기여" style="width:100%">')
    A("")
    A("#### 분야별 상세 — 상태 · 심각도 · 최근 3개월 · 기여도")
    A("")
    A(f"**'{SEV}'** 는 그 분야가 2006년 이후 모든 날과 비교해 얼마나 나쁜 자리에 있는지(0 = 역대 가장 평온 · 100 = 역대 최악)이고, "
      "**'기여도'** 는 오늘 점수 가운데 그 분야가 차지하는 부분(점 · 12개를 더하면 점수)입니다. 기여도가 음수인 분야는 다른 분야와 반대로 움직여 전체 체계적 위험을 오히려 낮추고 있는 분야입니다. '최근 3개월' 작은 그림은 그 분야 심각도의 65거래일 추이(띠 색 = 보통/다소 나쁨/나쁨/매우 나쁨)입니다.")
    A("")
    rows, rbg = [], []
    sub65 = d.tail(65)
    for a in sorted(axes, key=lambda a: -lt["contrib_level"][a]):
        p = lt["axis_pct"][a]
        lab, fg, bg = status(p)
        sub = st[st.axis == a]
        hot = ", ".join(IND_PLAIN.get(r.id, r.name) for r in sub[sub.ecdf_pct >= 0.8].sort_values("ecdf_pct", ascending=False).itertuples()) or "—"
        fresh = max(int(x) for x in sub.stale_trading_days.fillna(0))
        name, plain = AXIS_PLAIN[a]
        rows.append([
            badge(lab, fg, bg),
            f'<b>{name}</b><br><span style="color:#555;font-size:7.6pt">{plain}</span>',
            f'{bar(p, fg)}&nbsp;<b style="color:{fg};font-size:10pt">{pct(p)}</b>',
            sparkline(list(sub65[f"pct_{a}"].values), fg),
            f'<b style="font-size:9.5pt">{lt["contrib_level"][a]:.1f}</b>',
            chg_phrase(lt["contrib_level"][a] - lt["contrib_level_20td_ago"][a]),
            f'<span style="font-size:7.6pt">{hot}</span>',
            f'<span style="font-size:7.6pt;color:#555">{"당일" if fresh == 0 else f"{fresh}거래일 전"}</span>'])
        rbg.append({"매우 나쁨": "#fff4f4", "나쁨": "#fff7ef", "다소 나쁨": "#fffdf0"}.get(lab, "#ffffff"))
    A(html_table(["상태<br><span style=\"font-weight:400;font-size:7.2pt\">높을수록 나쁨</span>", "분야", f"{SEV}(0~100)", "최근 3개월", "기여도(점)", "20거래일 전 대비",
                  "지금 나쁜 세부 지표(심각도 80 이상)", "자료 시점"],
                 rows, aligns=["center", "left", "left", "center", "right", "center", "left", "center"],
                 widths=["8%", "20%", "14%", "11%", "6%", "10%", "24%", "7%"], row_bg=rbg))
    A("")
    top = sorted(axes, key=lambda a: -lt["contrib_level"][a])[:3]
    cm, cm_med, cm_max = 100 * lt["comove"], 100 * lv["comove_median"], 100 * lv["comove_at_max"]
    A(f"기여도가 가장 큰 분야는 **{AXIS_PLAIN[top[0]][0]}**({lt['contrib_level'][top[0]]:.1f}점)이고, 이어서 {AXIS_PLAIN[top[1]][0]}({lt['contrib_level'][top[1]]:.1f}점) · {AXIS_PLAIN[top[2]][0]}({lt['contrib_level'][top[2]]:.1f}점) 순입니다. "
      f"점수를 '지표가 얼마나 나쁜가' 와 '분야들이 얼마나 같이 움직이는가' 로 나누어 보면, 34개 세부 지표의 평균 심각도는 **{lt['score_linear']:.0f}**(평상시 {lv['linear_median']:.0f})이고 "
      f"분야 간 **동행률**은 **{cm:.0f}%**(평상시 {cm_med:.0f}% · 2008년 정점 {cm_max:.0f}%)입니다. 동행률 100% 는 모든 분야가 한 방향으로 움직여 점수가 평균 심각도와 같아지는 상태이고, "
      + ("지금은 동행이 평소보다 훨씬 강해 점수가 평균 심각도에 가깝게 올라와 있습니다." if cm >= cm_med + 10 else "지금은 분야들이 따로 움직여 점수가 평균 심각도보다 한참 낮은 자리에 있습니다.") +
      f" 분야 평균 상관은 {lt['avg_corr']:.2f} 입니다.")
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
      f" 오른쪽 그림은 2006년 이후 {len(d):,} 거래일의 점수 분포이며 붉은 세로선이 오늘, 점선이 과거 위기의 정점입니다. 전체 거래일의 절반은 {q[.5]:.0f}점 아래, 90%는 {q[.9]:.0f}점 아래, 95%는 {q[.95]:.0f}점 아래였습니다.")
    A("")
    prow = []
    for i, (dte, v) in enumerate(peaks, start=1):
        prow.append([str(i), kdate(dte), f"{v:.0f}", f"{100 * lt['level'] / v:.0f}%", _peak_label(dte)])
    prow.append(["—", f"<b>오늘 {kdate(day)}</b>", f"<b>{lt['level']:.0f}</b>", "100%", f"<b>{tier}</b>"])
    A(f"아래 표는 점수가 가장 높았던 날들(봉우리끼리 90일 이상 간격)입니다. **'오늘 ÷ 당시 정점'** 은 오늘 점수({lt['level']:.0f}점)를 그 위기 정점의 점수로 나눈 값으로, "
      "오늘의 스트레스 강도가 그때의 몇 % 수준인지를 뜻합니다 — 100% 면 그 위기 정점과 같은 강도, 50% 면 절반입니다(점수 눈금이 선형이라 비율로 읽을 수 있습니다).")
    A("")
    A(html_table(["순위", "스트레스가 가장 높았던 시기(90일 간격)", "당시 정점 점수", "오늘 ÷ 당시 정점", "당시 상황"], prow, aligns=["center", "left", "right", "right", "left"]))
    A("")

    # ── 5. 최근 18개월 ──
    A("## 5. 최근 18개월의 흐름")
    A("")
    e = eps[pd.to_datetime(eps["peak"]) >= d.index[-1] - pd.DateOffset(months=18)]
    cvm = {str(r.peak): r for r in cv.itertuples()} if len(cv) else {}
    parts = []
    for r in e.itertuples():
        c = cvm.get(str(r.peak))
        mx = f"점수 최고 {level_of(c.score_max):.0f}점({kdate(c.score_max_date)})" if c is not None and c.score_max == c.score_max else ""
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
    A("지수를 이루는 34개 세부 지표를 분야별로 묶어 심각도(0 = 역대 가장 평온 · 100 = 역대 최악)를 표시했습니다. 검은 점이 오늘, 흰 점이 20거래일 전입니다. 점이 오른쪽 빨간 선(90%)을 넘으면 2006년 이후 상위 10% 안의 이례적 수준입니다.")
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
        A(html_table(["분야", "세부 지표(쉬운 설명)", "오늘 값", "심각도(0~100)", "20거래일 전(%)", "기여도(점)", "자료일"], irows,
                     aligns=["left", "left", "right", "center", "center", "right", "center"], widths=["11%", "40%", "9%", "11%", "10%", "8%", "11%"], small=True))
        A("")

    # ── 7. 전 기간 ──
    A("## 7. 2006년 이후 전체 흐름")
    A("")
    A('<img src="d7_history.png" alt="전 기간" style="width:100%">')
    A("")
    A(f"회색 띠는 코스피200 이 고점 대비 20% 넘게 떨어진 구간(고점에서 저점까지)입니다. 점수는 2008년 금융위기(최고 {peaks[0][1]:.0f}점), 2020년 코로나 급락({refs.get('2020년 코로나 급락', float('nan')):.0f}점), 2022년 금리 급등 · 레고랜드 사태({refs.get('2022년 금리 급등', float('nan')):.0f}점), 그리고 올해의 세 차례 급락에서 모두 뚜렷한 봉우리를 만들었습니다. "
      "아래 그림의 V-KOSPI200(옵션시장이 보는 향후 변동성)과 견주어 보시면, 주식시장만 흔들릴 때는 V-KOSPI 가 더 민감하고, 여러 시장이 함께 흔들릴 때 이 지수가 더 높이 오르는 차이를 보실 수 있습니다.")
    A("")

    # ── 8. 유의사항 ──
    A("## 8. 보고서를 읽으실 때 유의하실 점")
    A("")
    A("- **동시성**: 이 지수는 시장 급락과 거의 동시에 오릅니다. 고점을 미리 알려 주지는 못하지만, '공식적인 약세장 기준(고점 대비 -20%)' 보다는 대개 먼저 경보 수준에 도달했습니다.")
    A(f"- **점수 눈금**: 점수는 '분야들이 함께 움직일수록 커지는 합'(유럽중앙은행 CISS 방식)에 제곱근을 취해 0~100 으로 나타낸 값입니다. 100 은 12개 분야가 모두 역대 최악이면서 한 방향으로 움직일 때이고, 실제 최고는 2008년의 {refs.get('2008년 금융위기', float('nan')):.0f}점이었습니다. "
      "계산 방식(분야 간 상관의 기억 길이 등)에 따라 수준이 조금 달라질 수 있어, 경보 단계 판정은 방식과 무관하게 안정적인 '역대 순위(백분위)' 로 합니다.")
    A("- **자료 시점**: 국내 주식 · 수급 자료는 전 거래일 마감 기준이고, 금리 · 환율 · 해외 자료는 공표 시차를 반영해 실제로 알 수 있었던 날짜의 값만 씁니다(미래 정보 없음). 각 분야의 자료 시점은 2절 표의 마지막 열에 있습니다.")
    A(f"- **경보 단계**: 주의 · 위험 문턱은 2006~2022년 자료에서 '허위 경보 대비 적중' 비율이 가장 좋은 백분위로 정했습니다(주의 = 상위 {100 - 100 * ns.get('threshold_warn', 0.8):.0f}% = 점수 약 {lv['warn']:.0f} · 위험 = 상위 {100 - 100 * ns.get('threshold_risk', 0.99):.0f}% = 점수 약 {lv['risk']:.0f}). 위험 단계는 2008년 · 2020년 수준에서만 켜집니다.")
    A("- **성격**: 연구용 시제품입니다. 투자 등급 · 포트폴리오 결정과 연결되어 있지 않으며, 단독 근거로 쓰기보다 시장 상황을 공유하는 온도계로 활용하시기 바랍니다.")
    A("")
    A("#### 부록 · 용어 풀이")
    A("")
    A(f"- **스트레스 점수(0~100)**: 12개 분야 34개 세부 지표를 각각 '심각도' 로 바꾼 뒤, 분야들이 **함께** 움직일수록 크게 치도록 합친 값(유럽중앙은행 CISS 방식 · 포트폴리오 분산과 같은 꼴)에 제곱근을 취한 것입니다 — 분산을 변동성으로 읽는 것과 같은 이치입니다. "
      f"한 분야만 크게 흔들리면 점수는 완만하게, 여러 분야가 동시에 흔들리면 가파르게 오릅니다. 기준점: {scale_phrase(meta)}. (원값 = 점수²/100 · 오늘 {lt['score']:.1f})")
    A("- **역대 순위 · 심각도(0 = 역대 가장 평온 · 100 = 역대 최악)**: 2006년 이후 전체 거래일 중 오늘보다 평온했던 날의 비율(%)입니다. 93이면 나쁜 순으로 상위 7% 안입니다. 모든 비교는 그 시점까지의 과거만 써서 계산합니다. 종합 점수에는 '역대 순위', 분야 · 세부 지표에는 '심각도' 라는 이름을 씁니다.")
    A("- **동행률(%)**: 점수 ÷ 34개 지표의 평균 심각도. 모든 분야가 한 방향으로 움직이면 100%, 서로 무관하게 움직이면 20% 안팎까지 내려갑니다. 같은 지표 상태라도 동행률이 높을수록 점수가 높습니다.")
    A("- **기여도(점)**: 오늘 점수 가운데 각 분야가 차지하는 부분입니다. 12개 분야의 기여도를 모두 더하면 점수가 됩니다.")
    A("- **분야 설명**: " + " / ".join(f"{AXIS_PLAIN[a][0]} = {AXIS_PLAIN[a][1]}" for a in axes) + ".")
    A("- **자료 출처**: 한국거래소 시세 · 투자자 수급(퀀티와이즈), 한국은행 ECOS(금리 · 환율), 미국 연준 FRED(VIX · 금융스트레스), V-KOSPI200. 산출 방법과 수치 근거는 `DESIGN_v1_capital_market.md` 와 `output/v1/run_meta.json` 에 있습니다.")
    A("")
    return "\n".join(L) + "\n"


def _commentary(day):
    """daily/<기준일>/commentary.json — 같은 기준일 · 검사 통과분만."""
    import json
    import os
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "daily", str(day), "commentary.json")
    try:
        c = json.load(open(p, encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None
    if not c.get("passed") or not c.get("text") or str(c.get("day")) != str(day):
        return None
    labels = {"claude-sonnet-5-5": "Claude Sonnet 5.5", "claude-opus-5-5": "Claude Opus 5.5", "claude-haiku-5-5": "Claude Haiku 5.5"}
    c["model_label"] = labels.get(c.get("model"), c.get("model"))
    return c


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
