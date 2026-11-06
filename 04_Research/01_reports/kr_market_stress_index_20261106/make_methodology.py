#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""스트레스 점수 산출 방법론 문서 — 쉬운 말 버전(1부) + 전문 버전(2부)을 한 파일로(도훈 11-06 "방법론도 전문/쉬운말 2가지로").

숫자(모수 · 문턱 · 기준점 · 검증 수치)는 전부 output/v1 · daily/latest 에서 읽어 넣는다 — 손으로 적은 수치 없음.
출력: METHODOLOGY_score.md (+ --pdf 면 00_Lawbook/tools/md_to_print_pdf.R 로 METHODOLOGY_score.pdf · 사본 daily/latest/kr_stress_methodology.pdf).
실행: <repo>/.venv_qvest_ml/Scripts/python.exe make_methodology.py [--pdf]
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
sys.path.insert(0, HERE)
import daily_text  # noqa: E402

OUT = HERE + "/output/v1"
RSCRIPT = os.environ.get("QVEST_RSCRIPT", "C:/Program Files/R/R-4.5.2/bin/Rscript.exe")
PDF_TOOL = ROOT + "/00_Lawbook/tools/md_to_print_pdf.R"


def f0(x):
    return "—" if x is None or x != x else f"{x:.0f}"


def f1(x):
    return "—" if x is None or x != x else f"{x:.1f}"


def pc(x):
    return "—" if x is None or x != x else f"{100 * x:.0f}%"


def load():
    meta = json.load(open(OUT + "/run_meta.json", encoding="utf-8"))
    nsr = json.load(open(OUT + "/nsr_selected.json", encoding="utf-8"))["v1"]
    latest = json.load(open(HERE + "/daily/latest/latest.json", encoding="utf-8"))
    d = pd.read_parquet(OUT + "/kr_stress_v1_daily.parquet")
    d.index = pd.to_datetime(d.index)
    d["level"] = 10 * np.sqrt(d["score"].clip(lower=0))
    cv = pd.read_csv(OUT + "/crisis_validation.csv")
    fb = pd.read_csv(OUT + "/forward_by_percentile_bucket.csv").set_index("bucket")
    qr = pd.read_csv(OUT + "/quantile_regression.csv")
    qo = pd.read_csv(OUT + "/quantile_regression_oos.csv")
    rob = pd.read_csv(OUT + "/robustness.csv").set_index("variant")
    return meta, nsr, latest, d, cv, fb, qr, qo, rob


def build(meta, nsr, latest, d, cv, fb, qr, qo, rob):
    P = {k: v["value"] for k, v in meta["params"].items()}
    S = {k: v["source"] for k, v in meta["params"].items()}
    lt = meta["latest"]
    lv = latest["levels"]
    refs = latest["ref_marks"]
    rmap = {r["label"]: r["level"] for r in refs}
    today_level = latest["level"]
    today_pct = lt["score_pct"]
    top_pct = max(1, round(100 - 100 * today_pct))
    tier = latest["tier"]
    comove = today_level / lt["score_linear"]
    lq = d["level"].quantile([.5, .72, .9, .95, .99])
    rq = d["score"].quantile([.5, .72, .9, .95, .99])
    n_days = int(d["score"].notna().sum())
    y0, y1 = d.index[0].year, d.index[-1].date()
    axes = meta["axes"]
    ind = meta["indicators"]
    by_axis = {a: [x for x in ind if x["axis"] == a] for a in axes}
    hist0 = meta.get("indicator_history_start", {})
    order = sorted(axes, key=lambda a: -lt["contrib"][a])
    fac = 10 / np.sqrt(lt["score"]) if lt["score"] > 0 else 0.0
    q05 = qr[(qr.signal == "v1") & (qr.tau == 0.05)].iloc[0]
    q05o = qo[(qo.signal == "v1") & (qo.tau == 0.05)].iloc[0]
    cvt = cv.copy()
    cvt["lvl"] = 10 * np.sqrt(cvt["score_max"].clip(lower=0))
    lam_alt = [k for k in rob.index if k.startswith("corr_lambda_")]
    drop = rob[[k.startswith("drop_axis_") for k in rob.index]]
    L = []
    A = L.append

    # ───────────────────────── 머리 ─────────────────────────
    A("# 국내 자본시장 스트레스 점수 — 산출 방법론")
    A("")
    A(f"작성 {latest['run_at'][:10]} · 기준 실행 {latest['day']}(자료 {y0}-01 ~ {y1} · {n_days:,} 거래일) · KR-CISS v1(연구 시제품) · "
      f"1부 = 쉬운 말 버전(임원 · 비전문가) · 2부 = 전문 버전(수식 · 모수 · 출처 · 검증). 두 부는 같은 계산을 다른 말로 설명합니다. "
      f"수치는 전부 `output/v1/run_meta.json` · `nsr_selected.json` · `daily/latest/latest.json` 에서 읽어 넣은 것입니다.")
    A("")

    # ───────────────────────── 1부 쉬운 말 ─────────────────────────
    A("## 1부. 쉬운 말 버전 — 이 점수는 무엇을 어떻게 재는가")
    A("")
    A("**한 줄로**: 주식 · 금리 · 신용 · 자금시장 · 환율 · 외국인 · 해외 등 12개 분야에 걸어 둔 **34개의 시장 체온계**를 매일 읽어, "
      "**① 지금이 과거와 비교해 얼마나 나쁜 날인지**, **② 그 나쁨이 한 분야에 머무는지 여러 분야로 번졌는지**를 0~100 점수 하나로 보여 드립니다. 높을수록 나쁩니다.")
    A("")
    A("### 왜 숫자 하나가 필요한가")
    A("")
    A("위기는 늘 같은 자리에서 오지 않습니다. 2008년에는 모든 분야가 동시에 무너졌고, 2011년에는 금융회사 주가가, 2022년에는 회사채와 단기 자금시장이, 올해는 국내 주식과 거래 유동성이 먼저 나빠졌습니다. "
      "주가지수나 변동성지수 하나만 보면 다른 자리에서 시작되는 위기를 놓칩니다. 그래서 여러 시장을 한 번에 읽되, 결과는 숫자 하나와 '어느 분야 때문인가' 라는 분해로 드립니다.")
    A("")
    A("### 무엇을 재는가 — 12개 분야 · 34개 체온계")
    A("")
    A("| 분야 | 무엇을 보는가 | 세부 체온계 |")
    A("|---|---|---|")
    for a in axes:
        name, plain = daily_text.AXIS_PLAIN[a]
        A(f"| **{name}** | {plain} | " + " · ".join(daily_text.IND_PLAIN.get(x["id"], x["name"]) for x in by_axis[a]) + " |")
    A("")
    A("### 어떻게 계산하는가 — 네 단계")
    A("")
    A("1. **체온계마다 '역대 순위'를 매깁니다(심각도 0~100).** 오늘 값이 그 체온계의 과거 기록 가운데 어디쯤인지를 봅니다. 100 이면 역대 최악, 50 이면 딱 중간, 0 이면 역대 가장 평온한 날입니다. "
      "단위가 제각각인 금리 · 환율 · 거래대금을 한 자로 재기 위한 방법이며, 비교 대상은 **그날까지 알려진 과거**뿐입니다(뒤에 나올 자료로 과거를 다시 채점하지 않습니다).")
    A("2. **분야들이 '같이' 움직이는지를 봅니다.** 한 분야만 크게 흔들릴 때보다 여러 분야가 한 방향으로 흔들릴 때가 훨씬 위험합니다 — 합창에서 한 사람이 크게 외치는 것보다 여럿이 같은 방향으로 외칠 때 소리가 커지는 것과 같습니다. "
      f"그래서 체온계 사이의 **최근 동행 정도(상관)** 를 매일 갱신하며(기억의 반감기 약 {np.log(0.5) / np.log(P['ewma_corr_lambda_daily']):.0f}거래일 — 최근 1~2주의 움직임이 주로 반영), 같이 움직이는 분야끼리는 합이 커지고 따로 움직이면 합이 작아지게 합칩니다. 이 방식은 유럽중앙은행의 체계적 스트레스 지수(CISS)와 같습니다.")
    A(f"3. **합친 값에 제곱근을 취해 0~100 점수로 만듭니다.** 2번에서 합친 값은 '분야들이 함께 움직일수록 커지는 합' 이라 평상시에는 아주 작고(중앙값 {f1(rq[.5])}) 위기 때만 커지는, 아래쪽에 몰린 눈금입니다. "
      f"포트폴리오의 위험을 분산이 아니라 변동성(제곱근)으로 읽듯 제곱근을 취하면 눈금이 고르게 펴집니다 — **평상시 {f0(lv['median'])} · 2011년 유럽 재정위기 {f0(rmap.get('2011년 유럽 재정위기'))} · 2022년 금리 급등 {f0(rmap.get('2022년 금리 급등'))} · "
      f"2020년 코로나 급락 {f0(rmap.get('2020년 코로나 급락'))} · 2008년 금융위기 {f0(rmap.get('2008년 금융위기'))}**. 100 은 34개 체온계가 모두 역대 최악이면서 완전히 한 방향으로 움직일 때이고, 실제 최고는 2008년의 {f0(rmap.get('2008년 금융위기'))}점이었습니다.")
    A(f"4. **점수의 '역대 순위'와 경보 단계를 붙입니다.** 점수 자체에도 1번과 같은 역대 순위를 매겨 '나쁜 순으로 상위 몇 %' 로 읽습니다. 경보 단계는 과거 자료에서 '허위 경보 대비 적중' 이 가장 좋았던 순위로 정했습니다 — "
      f"**주의 = 상위 {100 - 100 * nsr['threshold_warn']:.0f}%(점수 약 {f0(lv['warn'])} 이상) · 위험 = 상위 {100 - 100 * nsr['threshold_risk']:.0f}%(점수 약 {f0(lv['risk'])} 이상)**. 위험은 2008년 · 2020년 수준에서만 켜집니다.")
    A("")
    A("### 보고서의 숫자를 읽는 법")
    A("")
    A("| 숫자 | 뜻 | 오늘(" + latest["day"] + ") |")
    A("|---|---|---|")
    A(f"| **스트레스 점수** | 0~100 · 높을수록 나쁨 · 제곱근 눈금 | **{f0(today_level)}** |")
    A(f"| **역대 순위** | {y0}년 이후 모든 거래일 중 나쁜 순 상위 몇 % | 상위 {top_pct}%(백분위 {f0(100 * today_pct)}) |")
    A(f"| **경보 단계** | 주의 {f0(lv['warn'])} 이상 · 위험 {f0(lv['risk'])} 이상 | {tier} |")
    A(f"| **분야별 기여도** | 오늘 점수를 12개 분야로 나눈 것(점 · 모두 더하면 점수) | 1위 {daily_text.AXIS_PLAIN[order[0]][0]} {f1(lt['contrib'][order[0]] * fac)}점 · 2위 {daily_text.AXIS_PLAIN[order[1]][0]} {f1(lt['contrib'][order[1]] * fac)}점 |")
    A(f"| **심각도(분야 · 세부 지표)** | 그 분야 · 지표의 역대 순위(0~100) | 심각도 90 이상 분야 {sum(1 for a in axes if lt['axis_pct'][a] >= 0.9)}개 |")
    A(f"| **평균 심각도 × 동행률** | 점수가 왜 그 값인지 — 34개 체온계가 평균적으로 얼마나 나쁜가 × 분야들이 얼마나 같이 움직이는가 | {f0(lt['score_linear'])} × {pc(comove)} → {f0(today_level)} |")
    A("")
    A(f"오늘의 예를 들면, 34개 체온계는 평균적으로 역대 순위 {f0(lt['score_linear'])} 자리에 있고(평상시 {f0(lv['linear_median'])}), 분야들이 함께 움직이는 정도는 {pc(comove)}(평상시 {pc(lv['comove_median'])} · 2008년 정점 {pc(lv['comove_at_max'])})입니다. "
      f"모든 분야가 완전히 같이 움직였다면 점수는 평균 심각도와 같은 {f0(lt['score_linear'])}점이 됐을 텐데, 동행이 그보다 약해 {f0(today_level)}점에 머물렀습니다. 즉 **점수가 높아지는 길은 두 가지** — 체온계들이 더 나빠지거나, 분야들이 더 같이 움직이거나 — 이고, 보고서는 둘을 따로 보여 드립니다.")
    A("")
    A('<img src="daily/latest/d1_gauge.png" alt="게이지" style="width:100%">')
    A("")
    A("### 미래를 들여다보지 않습니다")
    A("")
    A("모든 계산은 **그날 장 마감 뒤에 알 수 있었던 자료**만 씁니다. 역대 순위는 그날까지의 과거와만 비교하고, 분야 간 동행도 그날까지의 자료로만 갱신하며, 금리 · 환율 · 해외 지표는 실제 발표 시차를 반영해 하루 뒤부터 씁니다. "
      "그래서 과거 어느 날의 점수도 '그날 아침에 계산했다면 나왔을 값' 입니다. 이것이 과거 위기에서의 검증 결과를 믿을 수 있는 이유입니다.")
    A("")
    A("### 어디까지 믿고, 어디서 멈춰야 하는가")
    A("")
    cnt = int(len(cvt))
    A(f"- **되는 것**: {y0}년 이후 코스피200 이 고점 대비 20% 넘게 빠진 급락 {cnt}차례에서 점수는 모두 뚜렷한 봉우리를 만들었고, 크기 순서도 상식과 맞습니다(2008 ≫ 2020 ≈ 2022 > 2011). "
      f"점수가 상위 5% 안에 있을 때 이후 60거래일 코스피200 수익률은 평균 {f1(fb.loc['>=95', 'fwd_logret_60_mean'])}%(평온할 때 +{f1(fb.loc['<50', 'fwd_logret_60_mean'])}%)였고, 나쁜 쪽 5% 시나리오는 {f1(fb.loc['>=95', 'fwd_logret_60_q05'])}%(평온할 때 {f1(fb.loc['<50', 'fwd_logret_60_q05'])}%)까지 내려갔습니다 — "
      "즉 **점수가 높을 때는 크게 더 빠질 위험이 평소보다 훨씬 큽니다.**")
    A("- **안 되는 것**: 이 점수는 **온도계이지 예보가 아닙니다.** 급락과 거의 동시에 오르고, 주가 고점을 미리 알려 주지 못합니다(과거 검증에서 경보 시점은 변동성지수 V-KOSPI 와 비슷했습니다). 방향을 맞히는 도구로 쓰시면 안 되고, '지금 얼마나 흔들리는가 · 어디서 흔들리는가 · 번지고 있는가' 를 공유하는 데 쓰시기 바랍니다.")
    A("- **아직 없는 재료**: 한국 CDS 프리미엄, 통화스와프(CRS−IRS) 베이시스, 여전채 · 전단채 스프레드, 신용융자 잔고, 외국인 채권 수급은 자료가 갖춰지면 넣을 후보입니다. 지금 점수는 이 재료 없이 계산된 값입니다.")
    A("- **성격**: 연구용 시제품입니다. 투자 등급 · 포트폴리오 결정과 연결되어 있지 않습니다.")
    A("")

    # ───────────────────────── 2부 전문 ─────────────────────────
    A("## 2부. 전문 버전 — 정의 · 수식 · 모수 · 검증")
    A("")
    A("### 2.1 설계의 뿌리")
    A("")
    A("- **집계 틀** = 유럽중앙은행 CISS(Holló · Kremer · Lo Duca 2012, ECB WP 1426): 지표를 확률적분변환(PIT)으로 [0,1] 에 맞춘 뒤 시변 상관으로 가중하는 '포트폴리오 위험' 꼴의 합성. "
      "**지표 수준 집계 · 동일 가중 · EWMA 상관** 은 새 CISS(Chavleishvili & Kremer 2023, ECB WP 2842 / Review of Finance 2025)를 따르고, 동일 가중의 근거는 Arrigoni · Bobasu · Venditti(2022)의 비교(가중 방식 차이가 결과를 거의 바꾸지 않음)입니다.")
    A("- **변환 어휘**(변동성 EWMA · CMAX · CMIN · 환율 6개월 CMAX · 이동 창 PIT)는 CLIFS(Duprey · Klaus · Peltonen 2017, J. Financial Stability)에서, "
      "한국형 구성(외국인 수급 · 중소형 · 시장 폭 · 전이 축)은 AMRO 한국 FSI 와 한국은행 금융불안지수(2023)의 지표군을 참고했습니다.")
    A("- **경보 문턱**은 Kaminsky · Lizondo · Reinhart(1998)의 잡음/신호 비율 최소화, **꼬리 위험 검증**은 Adrian · Boyarchenko · Giannone(2019, 'Vulnerable Growth')의 분위회귀 틀을 시장 수익에 적용한 것입니다. 위기 정의는 Lunde & Timmermann(2004) 20/20 규칙입니다.")
    A("")
    A("### 2.2 지표 체계 — 12축 34지표")
    A("")
    # 34행 한 표는 한 쪽을 넘어 pdf-check 의 '갈린 표' 에 걸린다 — 축 3개씩 네 표로 나눈다(소제목 + 표 = 한 블록)
    for k in range(0, len(axes), 3):
        grp = axes[k:k + 3]
        A(f"#### 2.2.{k // 3 + 1} {' · '.join(daily_text.AXIS_PLAIN[a][0] for a in grp)}")
        A("")
        A("| id | 축 | 지표 | 정의 | 원천 | 가용 규칙 | 이력 시작 |")
        A("|---|---|---|---|---|---|---|")
        for a in grp:
            for x in by_axis[a]:
                rule = x.get("availability_rule") or "당일 마감"
                esc = lambda s: str(s).replace("|", "\\|")      # 정의 안의 '|'(절댓값 · Amihud) 가 표 칸을 가르지 않게
                A(f"| {x['id']} | {daily_text.AXIS_PLAIN[a][0]} | {esc(x['name'])} | {esc(x['definition'])} | {esc(x['source'])} | {rule} | {hist0.get(x['id'], '—')} |")
        A("")
    A(f"가용 규칙 열의 계열명은 `06_Registry/fred_availability_rules.json`(연구용 사본 `output/fred_availability_rules_research.json`)의 규칙 키입니다 — 공표 시차를 둔 as-of 결합(PIT C11)으로, 그 날짜에 실제로 알 수 있었던 값만 들어갑니다. "
      f"국내 시세 · 수급(RAWDATA · investor_wide · benchmark · indices)은 전 거래일 마감 자료입니다. 유니버스 위생: 전날 종가 {P['price_floor_krw']:,}원 미만 제외(측정 축 epoch `all_hyg_px1000_2000_v1`) · 시총 순위는 직전일 기준 · 유동성은 t−1.")
    A("")
    A("### 2.3 지표 변환(원값 → 스트레스 방향의 수치)")
    A("")
    A(f"- **변동성**(E1 · S1 · R1 · M3 · X1 · F2): 일별 변화 `r_t`(주가 · 환율은 로그수익, 금리는 %p 변화)의 제곱을 EWMA 로 평활한 뒤 제곱근 — `v_t = sqrt(lambda*v_{{t-1}}^2 + (1-lambda)*r_t^2)`, `lambda = {P['ewma_vol_lambda']}`(새 CISS). 초기값은 첫 {P['ewma_vol_seed_obs']}관측의 분산(새 CISS 의 '첫 2년 분산' 초기화는 워밍업 안 미래참조라 쓰지 않음).")
    A(f"- **CMAX**(E2 · S2 · F1): `1 − P_t / max(P_{{t−{P['cmax_window_days']}d..t}})` — 2년 최고 대비 하락률. **환율 CMAX**(X2)는 {P['fx_cmax_window_days']}일(6개월) 창에 절하 방향. **CMIN**(R2): `y_t − min(y_{{t−{P['cmin_window_days']}d..t}})` — 2년 최저 대비 금리 상승폭(%p).")
    A(f"- **스프레드 · 기울기**(R3 · C1~C3 · M1 · M2): 두 금리의 차(%p). **상대 약세**(S3 · F3): {P['rel_return_window_obs']}일 로그수익 차에 음의 부호(부진할수록 큼). **금융업 고유 변동성**(F2): KOSPI200 에 대한 {P['beta_window_obs']}일 이동 OLS 잔차의 EWMA 변동성.")
    A(f"- **시장 폭**(B1~B3): 직전일 시총 상위 {P['breadth_universe_topn']} 종목 가운데 {P['breadth_high_window_obs']}일 고가 대비 −{100 * P['breadth_drawdown']:.0f}% 이하인 종목 비중(B1 · 고가 창 관측 ≥ {P['breadth_high_min_obs']}) · 상위 {P['corr_topn']} 종목의 {P['corr_window_obs']}일 평균 쌍별 상관(B2 · Pollet & Wilson 2010) · 상위 500 의 60일 수익 중앙값에 음의 부호(B3).")
    A(f"- **비유동성**(L1 · L2): Amihud(2002) `|r|/거래대금` 의 {P['amihud_window_obs']}일 평균을 종목별로 구해 상위 500(L1) · 시총 {P['amihud_small_rank'][0]}~{P['amihud_small_rank'][1]}위(L2)의 중앙값.")
    A(f"- **외국인 수급**(N1~N3): {P['flow_windows_obs'][0]} · {P['flow_windows_obs'][1]}일 누적 순매수를 시총으로 나눈 값에 음의 부호(순매도일수록 큼) · {P['flow_breadth_window_obs']}일 순매도 종목 비중.")
    A(f"- **해외**(G1~G3): VIX · 세인트루이스 연준 FSI(주간 · 가용일 규칙) · 달러지수 프록시의 20일 변화. 달러지수는 ICE DXY 가중(EUR −0.576 · JPY 0.136 · GBP −0.119 · CAD 0.091 · SEK 0.042 · CHF 0.036)을 ECOS 731Y002 교차환율로 재구성한 값입니다.")
    A(f"- **전이**(T1 · T2): 주가 수익과 원/달러 변화의 {P['corr_window_obs']}일 상관에 음의 부호(동반 약세일수록 큼) · 주가 수익과 국고채 3년 변화의 21일 상관이 {P['contagion_long_window_obs']}일(4년) 장기 상관에서 벗어난 절대 크기.")
    A("")
    A("### 2.4 확률적분변환(PIT) — 미래참조 없는 '역대 순위'")
    A("")
    A(f"지표 `i` 의 날짜 `t` 값 `x_{{i,t}}` 를, 그 지표의 **그날까지의 자기 이력**에 대한 경험 분포로 바꿉니다: `s_{{i,t}} = F_{{i,t}}(x_{{i,t}}) = (#{{u ≤ t : x_{{i,u}} ≤ x_{{i,t}}}}) / n_t` (확장 창 · 재귀 ECDF). "
      f"이력이 {P['ecdf_min_history_years']}년 미만이면 미유효(CISS 2012 §3.3 의 사전 구간). 예외로 비유동성 L1 · L2 는 {P['pit_rolling_window_obs']}관측(10년) **이동 창**(최소 {P['pit_rolling_min_obs']}) — Amihud 비유동성은 시장이 깊어지며 구조적으로 내려가므로 확장 창이면 2010년대 이후 영영 켜지지 않습니다(CLIFS §2.2 · §5 의 처방). "
      "전 표본 ECDF 는 **진단용으로만** 계산하며(미래참조) 본 점수에 쓰지 않습니다.")
    A("")
    A("### 2.5 집계 — 시변 상관 가중 합성(CISS 식)")
    A("")
    A(f"- 가중치 `w_i = 1/{meta['n_indicators']}`(동일 가중), `y_t = w * s_t`(원소별 곱).")
    A(f"- 공분산 EWMA: `Sigma_t = lambda*Sigma_{{t-1}} + (1-lambda)*(s_t - 0.5)(s_t - 0.5)'`, `lambda = {P['ewma_corr_lambda_daily']}`(일간 · 새 CISS), 중심 {P['ewma_demean']} = 균등분포의 이론 중앙값(CISS 2012 §3.4). 초기값 = 분산 1/12(균등분포) · 공분산 0(무상관). 상관 `C_t = D_t^{{-1/2}} Sigma_t D_t^{{-1/2}}` — 입력이 PIT 순위이므로 순위 상관입니다.")
    A("- **원값** `CISS_t = y_t' C_t y_t ∈ [0, 1]` (0~100 표기는 ×100). 경계: 34개 지표가 모두 `s = 1` 이고 `C = J`(완전 동행)면 1, 모두 `s = 1` 이어도 `C = I`(무상관)면 `1/34 = 0.029`. "
      f"실측 분포({y0}~ · {n_days:,} 거래일 · 0~100 표기): 중앙값 {f1(rq[.5])} · 72% {f1(rq[.72])} · 90% {f1(rq[.9])} · 95% {f1(rq[.95])} · 99% {f1(rq[.99])} · 최고 {f1(d['score'].max())}({d['score'].idxmax().date()}). 눈금이 아래쪽에 몰려 있습니다.")
    A("")
    A("### 2.6 표시 점수 · 기여도 · 동행률")
    A("")
    A("- **스트레스 점수** `Score_t = 100 * sqrt(CISS_t)`. `CISS` 는 포트폴리오 **분산**과 같은 이차형식이므로 변동성처럼 제곱근으로 읽습니다(ECB 가 CISS 를 '포트폴리오 위험 계산과 같은 방식' 이라 설명하는 바로 그 유비). "
      f"제곱근은 단조 변환이라 **백분위 · 경보 단계 · 순위 기반 검증은 전혀 바뀌지 않고**, 표시 눈금만 펴집니다 — 실측: 중앙값 {f1(lq[.5])} · 72% {f1(lq[.72])} · 90% {f1(lq[.9])} · 95% {f1(lq[.95])} · 99% {f1(lq[.99])} · 최고 {f1(d['level'].max())}.")
    A("- **기여도**(분야 · 지표): `sqrt(y'Cy)` 의 오일러 배분 `RC_i = y_i (C y)_i / sqrt(y'Cy)` — 포트폴리오 변동성의 위험 기여와 같은 식으로, `Σ_i RC_i = Score`(×100 표기). 분야 기여도 = 그 분야 지표들의 합. 음수 기여도 = 다른 지표들과 역상관으로 움직여 체계성을 깎는 지표.")
    A("- **평균 심각도** `L_t = 100 * mean_i(s_{i,t})` = 모든 지표가 완전히 같이 움직일 때의 점수 상한(`C = J` 이면 `Score = L`). **동행률** `= Score_t / L_t = sqrt(y'Cy) / Σy ∈ (0, 1]` — 실측 중앙값 "
      f"{pc(lv['comove_median'])} · 2008년 정점 {pc(lv['comove_at_max'])} · 오늘 {pc(comove)}. 점수는 '얼마나 나쁜가(L)' 와 '얼마나 함께 움직이는가(동행률)' 의 곱으로 읽힙니다.")
    A("- **기준점**(보고서 눈금 표시용 라벨 · 모수 아님): 잘 알려진 위기 창 안의 최고 점수 — " + " · ".join(f"{r['label']} {f0(r['level'])}" + (f"({r['date']})" if r.get("date") else "") for r in refs) + ".")
    A("")
    A("### 2.7 역대 순위(백분위)와 경보 단계")
    A("")
    A(f"- **역대 순위** `p_t` = `CISS_t` 의 재귀 백분위(그날까지의 자기 이력 · 첫 {P['score_pct_min_obs']}관측은 미표시 — 첫 관측 백분위 1 인공물 차단). 보고서는 `1 − p_t` 를 '나쁜 순 상위 n%' 로 적습니다. 분야 · 지표의 '심각도' 는 같은 정의의 축 · 지표별 백분위입니다.")
    A(f"- **경보 단계**(Kaminsky · Lizondo · Reinhart 1998): 사건 = 코스피200 LT 20/20 위기의 '−20% 첫 통과(확정)' 가 앞으로 {P['nsr_event_horizon_obs']}거래일 안에 오는 날. 백분위 문턱 격자 {P['nsr_grid'][0]:.2f}~{P['nsr_grid'][1]:.2f}(간격 {P['nsr_grid'][2]:.2f} · 신호일 {P['nsr_min_signal_days']}일 미만 제외)에서 잡음/신호 비율 `NSR = FPR / TPR` 을 계산하고, "
      f"**주의** = `TPR ≥ {P['nsr_warn_tpr_floor']}` 제약 아래 NSR 최소 → 백분위 **{nsr['threshold_warn']:.2f}**(표본내 TPR {pc(nsr['tpr_warn_in'])} · NSR {nsr['nsr_warn_in']:.2f}), **위험** = 제약 없는 NSR 최소 → 백분위 **{nsr['threshold_risk']:.2f}**(표본내 TPR {pc(nsr['tpr_risk_in'])} · NSR {nsr['nsr_risk_in']:.2f}). 한국은행 FSI 의 2단(주의/위험) 구조를 따릅니다.")
    A(f"- 문턱은 정보 경계 **τ_D = {P['tau_d']}** 이전 자료로만 고르고, 이후({nsr['oos_n']}거래일)는 표본외 검증: 주의 TPR {pc(nsr['oos_warn_tpr'])} · FPR {pc(nsr['oos_warn_fpr'])} · NSR {nsr['oos_warn_nsr']:.2f}, 위험은 표본외 미도달(신호일 {nsr['oos_risk_signal_days']}). "
      f"점수 눈금으로 환산하면 오늘 기준 주의 ≈ {f1(lv['warn'])} · 위험 ≈ {f1(lv['risk'])}(백분위 문턱의 그날 역변환이라 천천히 움직입니다).")
    A("")
    A("### 2.8 검증 요약")
    A("")
    A("| 위기(코스피200 고점) | 저점 | 낙폭 | 점수 최고(날짜) |")
    A("|---|---|---|---|")
    for r in cvt.itertuples():
        A(f"| {r.peak} | {r.trough}{' (진행 중)' if bool(r.ongoing) else ''} | {100 * r.depth:.0f}% | {r.lvl:.0f} ({r.score_max_date}) |")
    A("")
    A(f"- **동시성**: 80 · 90 백분위 경보는 급락과 거의 동시에 켜지고 고점을 앞서지 않습니다(경보 시점 ≈ V-KOSPI). 공식 약세장 확정(−20%)보다는 대개 앞섭니다.")
    A(f"- **꼬리 조건부 정보**: 점수 백분위 ≥95 구간의 60거래일 선행 코스피200 로그수익 평균 {f1(fb.loc['>=95', 'fwd_logret_60_mean'])}% · 5% 분위 {f1(fb.loc['>=95', 'fwd_logret_60_q05'])}%(＜50 구간 +{f1(fb.loc['<50', 'fwd_logret_60_mean'])}% · {f1(fb.loc['<50', 'fwd_logret_60_q05'])}%). "
      f"분위회귀 τ=0.05 기울기 {f1(q05['slope'])}(n {int(q05['n']):,} · 연구 판의 이동 블록 부트스트랩 CI 는 DESIGN §5.4), 표본외(τ_D 이후) 5% 분위 적중 {pc(q05o['coverage_conditional'])}(명목 5% · 핀볼 손실 비율 {q05o['ratio_cond_over_unc']:.2f}).")
    A(f"- **강건성**: 상관 기억 λ 를 {' · '.join(k.replace('corr_lambda_', '') for k in lam_alt)} 로 바꾸면 오늘 원값은 {' · '.join(f1(rob.loc[k, 'latest_variant']) for k in lam_alt)} 로 움직이나 백분위는 {' · '.join(pc(rob.loc[k, 'latest_variant_pct']) for k in lam_alt)}(본 지수 {pc(today_pct)}); "
      f"축 하나씩 뺀 12개 변형의 백분위 범위 {pc(drop['latest_variant_pct'].min())}~{pc(drop['latest_variant_pct'].max())}; 선형 평균(상관 미반영) 백분위 {pc(rob.loc['score_linear', 'latest_variant_pct'])}. → **판단은 수준이 아니라 백분위로** 합니다.")
    A("")
    A("### 2.9 PIT 점검표(C1~C15 중 해당 항목)")
    A("")
    A("- C1 전 표본 통계 금지: ECDF · EWMA 변동성 · EWMA 상관 · 백분위 전부 확장(또는 이동) 창. 전 표본 ECDF 는 진단 열에만.")
    A("- C2/C3 당일 순환 금지: 지수 `t` 는 `t` 마감 자료 — 신호로 쓰려면 `t+1` 부터. 유니버스(시총 순위 · 가격 바닥 · 유동성)는 t−1.")
    A("- C10/C11 가용일: 금리 · 환율 · 해외 계열은 가용 규칙 파일의 공표 시차 as-of 결합(fail-closed — 규칙 없는 계열은 쓰지 않음).")
    A(f"- 정보 경계 τ_D = {P['tau_d']}: 문턱 · 분위회귀 적합은 이전 자료, 이후는 표본외.")
    A("")
    A("### 2.10 구현 · 재현 · 한계")
    A("")
    A("- 코드: `fetch_research_inputs.py`(ECOS · FRED 직접 수급 · 가용 규칙 사본) → `build_kr_stress_index_v1.py`(지표 · PIT · 집계 · 검증 · `output/v1/`) → `make_charts.py v1` → `make_daily_report.py`(점수 눈금 · 기여도 · 일보 PDF · 엑셀). 모수와 출처는 `run_meta.json::params` 에 전부 기록됩니다(하드코딩 없음 · 설계 선택은 '설계 선택' 으로 표시).")
    A("- 한계: ① 동행 지표(선행성 없음) ② 자본시장 전체 지수를 코스피200 낙폭으로 채점하므로 분절 스트레스(2022-10 레고랜드 · 2023-10 금리)가 '거짓 경보' 로 세어진다 — 다중 시장 위기 연대기가 있어야 적중률을 제대로 매길 수 있다 ③ 수준은 λ 에 민감(백분위는 안정) ④ 데이터 공백(CDS · CRS−IRS · 여전채/전단채 · 신용융자 · 외국인 채권 · 선물 베이시스).")
    A("- 위치: 아이디어 연구 산출물 — 등급 · BOOK · 등록부 · 국면 원장과 무관.")
    A("")
    return "\n".join(L) + "\n"


def render_pdf(md_path):
    pdf = md_path[:-3] + ".pdf"
    env = dict(os.environ)
    env.setdefault("PYTHONUTF8", "1")
    r = subprocess.run([RSCRIPT, "--no-save", PDF_TOOL, md_path, pdf, "portrait"], capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, cwd=ROOT)
    for t in (r.stdout + r.stderr).strip().splitlines()[-4:]:
        print("[methodology] pdf:", t[:300])
    if r.returncode != 0 or not os.path.exists(pdf):
        raise RuntimeError(f"PDF 생성 실패 rc={r.returncode}")
    return pdf


def main():
    md = HERE + "/METHODOLOGY_score.md"
    open(md, "w", encoding="utf-8", newline="\n").write(build(*load()))
    print("[methodology] markdown", md)
    if "--pdf" in sys.argv:
        pdf = render_pdf(md)
        os.makedirs(HERE + "/daily/latest", exist_ok=True)
        shutil.copy2(pdf, HERE + "/daily/latest/kr_stress_methodology.pdf")
        print("[methodology] pdf", pdf)


if __name__ == "__main__":
    main()
