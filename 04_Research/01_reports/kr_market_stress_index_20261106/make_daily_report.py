#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""KR 자본시장 스트레스 일보 — 같은 형태 · 내용만 바뀌는 PDF 보고서 + 원자료 엑셀 대시보드(도훈 2026-11-06 요청).

입력 = build_kr_stress_index_v1.py 의 output/v1/ (+ make_charts.py v1 의 charts/v1_*.png).
출력 = daily/<데이터 기준일>/  kr_stress_daily_<일자>.md · .pdf · kr_stress_dashboard_<일자>.xlsx · 차트 사본
       daily/latest/           같은 파일의 '_latest' 사본(고정 경로 — 대시보드 · 링크용)
PDF = 프로젝트 단일 경로 00_Lawbook/tools/md_to_print_pdf.R(현대하모니 L/M/B · Edge 인쇄 · pdf_check) — 서식 규칙 docs/rules/pdf-output-style.md.
엑셀 = openpyxl(네이티브 차트 · 조건부 서식) — 시트: Dashboard · Index_Daily · Axes_Latest · Indicators_Latest · Raw_Daily · PIT_Daily ·
       AxisContrib_Daily · Crises · Thresholds · Meta.
실행: <repo>/.venv_qvest_ml/Scripts/python.exe make_daily_report.py [--no-pdf]
"""
from __future__ import annotations

import datetime as dt
import json
import os
import shutil
import subprocess
import sys

import pandas as pd
from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.formatting.rule import ColorScaleRule, DataBarRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
OUT = HERE + "/output/v1"
CH = HERE + "/charts"
DAILY = HERE + "/daily"
RSCRIPT = os.environ.get("QVEST_RSCRIPT", "C:/Program Files/R/R-4.5.2/bin/Rscript.exe")
PDF_TOOL = ROOT + "/00_Lawbook/tools/md_to_print_pdf.R"
TIER_COLOR = {"정상": "C6EFCE", "주의": "FFEB9C", "위험": "FFC7CE"}


def log(*a):
    print("[daily]", *a, flush=True)


def f1(x, nd=1):
    return "—" if x is None or (isinstance(x, float) and x != x) else f"{x:.{nd}f}"


def pct(x):
    return "—" if x is None or (isinstance(x, float) and x != x) else f"{100 * x:.0f}"


# ─────────────────────────────────────────────────────────────────────────────
def load():
    meta = json.load(open(OUT + "/run_meta.json", encoding="utf-8"))
    d = pd.read_parquet(OUT + "/kr_stress_v1_daily.parquet")
    d.index = pd.to_datetime(d.index)
    st = pd.read_csv(OUT + "/indicator_status_latest.csv")
    eps = pd.read_csv(OUT + "/crisis_episodes_lt2020_kospi200.csv")
    cv = pd.read_csv(OUT + "/crisis_validation.csv")
    nsr = json.load(open(OUT + "/nsr_selected.json", encoding="utf-8"))
    rob = pd.read_csv(OUT + "/robustness.csv")
    return meta, d, st, eps, cv, nsr, rob


def tier_of(p, ns):
    if ns.get("threshold_risk") is not None and p >= ns["threshold_risk"]:
        return "위험"
    if ns.get("threshold_warn") is not None and p >= ns["threshold_warn"]:
        return "주의"
    return "정상"


def headline_sentence(meta, d, ns):
    lt = meta["latest"]
    ko = meta["axis_ko"]
    on = [ko[a] for a, p in sorted(lt["axis_pct"].items(), key=lambda kv: -kv[1]) if p >= 0.90]
    calm = [ko[a] for a, p in sorted(lt["axis_pct"].items(), key=lambda kv: kv[1]) if p <= 0.40]
    chg = lt["score"] - lt["score_20td_ago"]
    dir_ = "올랐다" if chg > 0.5 else "내렸다" if chg < -0.5 else "비슷하다"
    s = (f"지수 {lt['score']:.1f}(역사 백분위 {100 * lt['score_pct']:.0f}) · 단계 **{tier_of(lt['score_pct'], ns)}** · "
         f"20거래일 전({lt['date_20td_ago']}) {lt['score_20td_ago']:.1f}보다 {dir_}. ")
    s += f"90백분위 이상인 축 = {' · '.join(on) if on else '없음'}; 평온한 축(40 이하) = {' · '.join(calm) if calm else '없음'}. "
    s += f"V-KOSPI200 {lt['vkospi']:.1f}(백분위 {100 * lt['vkospi_pct']:.0f}). 축 평균 상관 {lt['avg_corr']:.2f}"
    s += "(높을수록 분절 간 동행 = 체계적)." if lt["avg_corr"] >= 0.3 else "(낮음 — 분절이 함께 움직이진 않는다)."
    return s


# ─────────────────────────────────────────────────────────────────────────────
def write_markdown(meta, d, st, eps, nsr, rob, folder, day):
    lt = meta["latest"]
    ko = meta["axis_ko"]
    axes = meta["axes"]
    ns = nsr.get("v1", {})
    prev = d.iloc[-2] if len(d) > 1 else d.iloc[-1]
    q = d["score"].quantile([.5, .8, .9, .95, .99])
    lines = []
    L = lines.append
    L(f"# KR 자본시장 스트레스 일보 — {day}")
    L("")
    L(f"산출 {meta['run_at'][:16]} · 지수 = KR-CISS v1(12축 34지표 · 재귀 PIT · 지표 수준 EWMA 순위상관 집계 · 0~100) · 설계 · 근거 = `DESIGN_v1_capital_market.md` · 아이디어 연구(등급 · BOOK 무관)")
    L("")
    L("## 1. 오늘의 레벨")
    L("")
    L("| 지수 | 역사 백분위 | 단계 | 전일 | 20거래일 전 | 60거래일 전 | 선형 평균 | V-KOSPI200 | 축 평균 상관 |")
    L("|---|---|---|---|---|---|---|---|---|")
    L(f"| **{lt['score']:.1f}** | **{pct(lt['score_pct'])}** | **{tier_of(lt['score_pct'], ns)}** | {prev['score']:.1f}({str(prev.name.date())}) | "
      f"{lt['score_20td_ago']:.1f}({lt['date_20td_ago']}) | {lt['score_60td_ago']:.1f}({lt['date_60td_ago']}) | {lt['score_linear']:.1f} | "
      f"{lt['vkospi']:.1f}(백분위 {pct(lt['vkospi_pct'])}) | {lt['avg_corr']:.2f} |")
    L("")
    L(headline_sentence(meta, d, ns))
    L("")
    L(f"단계 규칙 = 잡음/신호 비율(KLR 1998 · 한은 FSI 2023 방식)로 τ_D(2022-12-31) 이전 표본에서 고른 백분위 문턱 — 주의 ≥ {pct(ns.get('threshold_warn'))} · 위험 ≥ {pct(ns.get('threshold_risk'))}. "
      f"전 기간 분위: 중앙값 {q[.5]:.1f} · 80% {q[.8]:.1f} · 90% {q[.9]:.1f} · 95% {q[.95]:.1f} · 99% {q[.99]:.1f} · 최고 {lt['max_score_since_t0']:.1f}({lt['max_score_date']}).")
    L("")
    L('<img src="v1_02_axis_contribution_latest.png" alt="축별 기여" style="max-height:88mm">')
    L("")
    L("## 2. 축별 분해 — 어디서 온 스트레스인가")
    L("")
    L("| 축 | 기여(점) | 하위지수 | 축 백분위 | 20거래일 전 기여 | 변화 | 80백분위 이상 지표 | 입력 신선도 |")
    L("|---|---|---|---|---|---|---|---|")
    order = sorted(axes, key=lambda a: -lt["contrib"][a])
    for a in order:
        rows = st[st.axis == a]
        hot = " · ".join(f"{r.name}({100 * r.ecdf_pct:.0f})" for r in rows.itertuples() if r.ecdf_pct >= 0.8) or "—"
        fresh = max(int(x) for x in rows.stale_trading_days.fillna(0))
        fr = "당일" if fresh == 0 else f"{fresh}거래일 전"
        L(f"| {ko[a]} | {lt['contrib'][a]:.1f} | {lt['subindex'][a]:.2f} | {pct(lt['axis_pct'][a])} | {lt['contrib_20td_ago'][a]:.1f} | "
          f"{lt['contrib'][a] - lt['contrib_20td_ago'][a]:+.1f} | {hot} | {fr} |")
    L("")
    L("기여 = w·z_i × Σ_j ρ_ij w·z_j × 100 (합 = 지수). 음수 = 그 축이 다른 축과 역상관으로 움직여 체계성을 깎는다. 하위지수 = 축 안 지표 PIT 평균(0~1). 축 백분위 = 그 하위지수의 재귀 백분위. 아래 = 최근 18개월의 지수와 축별 기여(회색 = KOSPI200 LT 위기).")
    L("")
    L('<img src="v1_05_recent_18m_zoom.png" alt="최근 18개월" style="max-height:84mm">')
    L("")
    L("## 3. 지표 전체(34) — 값 · 역사 백분위 · 변화")
    L("")
    half = len(axes) // 2
    for k, grp in enumerate((axes[:half], axes[half:]), start=1):
        L(f"#### 3.{k} {' · '.join(ko[a] for a in grp)}")
        L("")
        L("| id | 축 | 지표 | 값 | 백분위 | 20거래일 전 백분위 | 기여 | 관측일 | 묵음(td) |")
        L("|---|---|---|---|---|---|---|---|---|")
        for r in st[st.axis.isin(grp)].itertuples():
            v = r.value
            vs = f"{v:.4g}" if abs(v) < 1 else f"{v:.3f}" if abs(v) < 100 else f"{v:.1f}"
            L(f"| {r.id} | {ko[r.axis]} | {r.name} | {vs} | {100 * r.ecdf_pct:.0f} | {100 * r.ecdf_pct_20td_ago:.0f} | {r.contrib:+.2f} | {r.last_obs_date} | {int(r.stale_trading_days)} |")
        L("")
    L("## 4. 역사 속 위치")
    L("")
    L('<img src="v1_01_index_timeseries_crises.png" alt="전 기간" style="max-height:92mm">')
    L("")
    s = d["score"].copy()
    peaks = []
    while len(peaks) < 8 and s.notna().any():
        i = s.idxmax()
        peaks.append((i.date(), float(s.loc[i])))
        s[(s.index >= i - pd.Timedelta(days=90)) & (s.index <= i + pd.Timedelta(days=90))] = float("nan")
    L("| 봉우리(90일 간격) | " + " | ".join(str(p[0]) for p in peaks) + " | **오늘** |")
    L("|---|" + "---|" * (len(peaks) + 1))
    L("| 지수 | " + " | ".join(f"{p[1]:.1f}" for p in peaks) + f" | **{lt['score']:.1f}** |")
    L("")
    e = eps[pd.to_datetime(eps["peak"]) >= pd.Timestamp(meta["composite_start_t0"])].tail(4)
    L("최근 KOSPI200 Lunde-Timmermann 20/20 위기: " + " · ".join(
        f"{r.peak}→{r.trough}({100 * r.depth:.0f}%{' · 진행 중' if r.ongoing else ''})" for r in e.itertuples()) + ".")
    L("")
    L("## 5. 읽는 법 · 주의")
    L("")
    L("- **동행 지표**다 — 고점을 앞서지 않고, 위기 확정(−20%)보다는 앞선다. 방향이 아니라 **꼬리 폭**(≥95백분위 구간의 60일 선행 5% 분위 −33% vs 평시 −11%)을 읽는다.")
    rl = {r.variant: r for r in rob.itertuples()}
    v = [rl[k] for k in ("corr_lambda_0.9856", "score_linear", "score_axis_level") if k in rl]
    if v:
        L("- **수준이 아니라 백분위로 읽는다** — 상관 기억 · 집계 방식을 바꾸면 수준은 " + " · ".join(f"{x.latest_variant:.1f}" for x in v) +
          f" 로 흔들리지만 백분위는 " + " · ".join(pct(x.latest_variant_pct) for x in v) + f"(본 지수 {pct(lt['score_pct'])}).")
    L("- 입력 신선도: 국내 시장 자료(RAWDATA · 수급)는 퀀티 최신화 뒤 · 금리 · 환율 · 해외는 ECOS/FRED 직접 수급(가용일 규칙 C11). 묵은 지표는 §3 '묵음' 열.")
    L("- PIT: 표준화 · 상관 · 백분위 전부 확장 창(미래 관측 없음). 지수 t 는 t 마감 자료 — 신호로 쓰려면 t+1 부터.")
    L("- 등급 · BOOK · 등록부와 무관한 아이디어 연구 산출물. 수치 결정의 출처 = `output/v1/run_meta.json::params`.")
    L("")
    md = "\n".join(lines) + "\n"
    path = f"{folder}/kr_stress_daily_{day}.md"
    open(path, "w", encoding="utf-8", newline="\n").write(md)
    return path


def render_pdf(md_path):
    pdf = md_path[:-3] + ".pdf"
    cmd = [RSCRIPT, "--no-save", PDF_TOOL, md_path, pdf, "landscape"]
    env = dict(os.environ)
    env.setdefault("PYTHONUTF8", "1")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, cwd=ROOT)
    tail = (r.stdout + r.stderr).strip().splitlines()[-6:]
    for t in tail:
        log("  pdf:", t[:200])
    if r.returncode != 0 or not os.path.exists(pdf):
        raise RuntimeError(f"PDF 생성 실패 rc={r.returncode}")
    return pdf


# ─────────────────────────────────────────────────────────────────────────────
HDR = PatternFill("solid", fgColor="1F4E79")
HFONT = Font(bold=True, color="FFFFFF")
THIN = Side(style="thin", color="BFBFBF")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)


def _hdr(ws, row, cols):
    for j, c in enumerate(cols, start=1):
        cell = ws.cell(row=row, column=j, value=c)
        cell.fill = HDR
        cell.font = HFONT
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        cell.border = BORDER


def _df_to_sheet(ws, df, start_row=1, index=True, date_fmt="yyyy-mm-dd", num_fmt="0.000", widths=None, freeze=True):
    cols = ([df.index.name or "Date"] if index else []) + [str(c) for c in df.columns]
    _hdr(ws, start_row, cols)
    for i, (idx, row) in enumerate(df.iterrows(), start=start_row + 1):
        j = 1
        if index:
            v = idx.to_pydatetime() if hasattr(idx, "to_pydatetime") else idx
            c = ws.cell(row=i, column=j, value=v)
            c.number_format = date_fmt
            j += 1
        for v in row.values:
            if isinstance(v, float) and v != v:
                v = None
            elif hasattr(v, "item"):
                v = v.item()
            c = ws.cell(row=i, column=j, value=v)
            if isinstance(v, float):
                c.number_format = num_fmt
            j += 1
    ws.auto_filter.ref = f"A{start_row}:{get_column_letter(len(cols))}{start_row + len(df)}"
    if freeze:
        ws.freeze_panes = ws.cell(row=start_row + 1, column=2 if index else 1)
    for j, c in enumerate(cols, start=1):
        ws.column_dimensions[get_column_letter(j)].width = (widths or {}).get(c, max(10, min(28, len(str(c)) + 4)))


def write_excel(meta, d, st, eps, cv, nsr, rob, folder, day):
    lt = meta["latest"]
    ko = meta["axis_ko"]
    axes = meta["axes"]
    ns = nsr.get("v1", {})
    ids = [i["id"] for i in meta["indicators"]]
    wb = Workbook()

    # ── Dashboard ──
    ws = wb.active
    ws.title = "Dashboard"
    ws["A1"] = f"KR 자본시장 스트레스 대시보드 — 데이터 기준 {day} (산출 {meta['run_at'][:16]})"
    ws["A1"].font = Font(bold=True, size=14)
    ws["A2"] = "KR-CISS v1 · 12축 34지표 · 재귀 PIT · 지표 수준 EWMA 순위상관 집계 · 0~100 · 아이디어 연구(등급 · BOOK 무관) · 설계 = DESIGN_v1_capital_market.md"
    ws["A2"].font = Font(italic=True, color="595959")
    kv = [("지수", lt["score"], "0.0"), ("역사 백분위(%)", 100 * lt["score_pct"], "0"), ("단계", tier_of(lt["score_pct"], ns), None),
          ("전일 지수", float(d["score"].iloc[-2]) if len(d) > 1 else None, "0.0"),
          (f"20거래일 전({lt['date_20td_ago']})", lt["score_20td_ago"], "0.0"), (f"60거래일 전({lt['date_60td_ago']})", lt["score_60td_ago"], "0.0"),
          ("선형 평균(상관 미반영)", lt["score_linear"], "0.0"), ("축 평균 상관", lt["avg_corr"], "0.00"),
          ("V-KOSPI200", lt["vkospi"], "0.0"), ("V-KOSPI 백분위(%)", 100 * lt["vkospi_pct"], "0"),
          ("주의 문턱(백분위 %)", 100 * ns.get("threshold_warn", float("nan")), "0"), ("위험 문턱(백분위 %)", 100 * ns.get("threshold_risk", float("nan")), "0"),
          ("전 기간 최고", f"{lt['max_score_since_t0']:.1f} ({lt['max_score_date']})", None)]
    _hdr(ws, 4, ["항목", "값"])
    for i, (k, v, fmt) in enumerate(kv, start=5):
        ws.cell(row=i, column=1, value=k).border = BORDER
        c = ws.cell(row=i, column=2, value=v)
        c.border = BORDER
        if fmt:
            c.number_format = fmt
        if k == "단계":
            c.fill = PatternFill("solid", fgColor=TIER_COLOR.get(str(v), "FFFFFF"))
            c.font = Font(bold=True)
    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 22
    ws["A19"] = headline_sentence(meta, d, ns).replace("**", "")
    ws["A19"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells("A19:F22")
    r0 = 24
    _hdr(ws, r0, ["축", "기여(점)", "하위지수", "축 백분위(%)", "20거래일 전 기여", "변화", "80백분위 이상 지표"])
    order = sorted(axes, key=lambda a: -lt["contrib"][a])
    for i, a in enumerate(order, start=r0 + 1):
        rows = st[st.axis == a]
        hot = " · ".join(f"{r.name}({100 * r.ecdf_pct:.0f})" for r in rows.itertuples() if r.ecdf_pct >= 0.8) or "—"
        vals = [ko[a], lt["contrib"][a], lt["subindex"][a], 100 * lt["axis_pct"][a], lt["contrib_20td_ago"][a], lt["contrib"][a] - lt["contrib_20td_ago"][a], hot]
        for j, v in enumerate(vals, start=1):
            c = ws.cell(row=i, column=j, value=v)
            c.border = BORDER
            c.number_format = {2: "0.00", 3: "0.00", 4: "0", 5: "0.00", 6: "+0.00;-0.00;0.00"}.get(j, "General")
    r1 = r0 + len(order)
    ws.conditional_formatting.add(f"B{r0 + 1}:B{r1}", DataBarRule(start_type="num", start_value=0, end_type="max", color="1F4E79"))
    ws.conditional_formatting.add(f"D{r0 + 1}:D{r1}", ColorScaleRule(start_type="num", start_value=0, start_color="C6EFCE", mid_type="num", mid_value=80, mid_color="FFEB9C", end_type="num", end_value=100, end_color="FFC7CE"))
    for col, w in zip("CDEFG", (12, 14, 16, 10, 70)):
        ws.column_dimensions[col].width = w
    bar = BarChart()
    bar.type = "bar"
    bar.title = f"축별 기여 — {day}"
    bar.add_data(Reference(ws, min_col=2, min_row=r0, max_row=r1), titles_from_data=True)
    bar.set_categories(Reference(ws, min_col=1, min_row=r0 + 1, max_row=r1))
    bar.height, bar.width = 9, 16
    bar.legend = None
    ws.add_chart(bar, "I4")
    # 상위 지표
    r2 = r1 + 2
    _hdr(ws, r2, ["id", "축", "지표", "값", "백분위(%)", "기여", "관측일", "묵음(td)"])
    top = st.sort_values("contrib", ascending=False).head(12)
    for i, r in enumerate(top.itertuples(), start=r2 + 1):
        for j, v in enumerate([r.id, ko[r.axis], r.name, float(r.value), 100 * float(r.ecdf_pct), float(r.contrib), str(r.last_obs_date), int(r.stale_trading_days)], start=1):
            c = ws.cell(row=i, column=j, value=v)
            c.border = BORDER
            c.number_format = {4: "0.0000", 5: "0", 6: "0.00"}.get(j, "General")

    # ── Index_Daily (+ 꺾은선 차트) ──
    w2 = wb.create_sheet("Index_Daily")
    cols = ["score", "score_pct", "score_linear", "score_axis_level", "avg_corr", "vkospi", "vkospi_pct"] + [f"c_{a}" for a in axes] + [f"s_{a}" for a in axes] + [f"pct_{a}" for a in axes]
    dd = d[cols].copy()
    dd["tier"] = [tier_of(p, ns) if p == p else None for p in dd["score_pct"]]
    dd.index.name = "Date"
    _df_to_sheet(w2, dd, num_fmt="0.0000")
    n = len(dd) + 1
    lc = LineChart()
    lc.title = "KR-CISS v1 (전 기간)"
    lc.add_data(Reference(w2, min_col=2, min_row=1, max_row=n), titles_from_data=True)
    lc.set_categories(Reference(w2, min_col=1, min_row=2, max_row=n))
    lc.height, lc.width = 9, 24
    lc.legend = None
    ws.add_chart(lc, "I24")

    # ── Axes_Latest · Indicators_Latest ──
    w3 = wb.create_sheet("Axes_Latest")
    ax = pd.DataFrame([{"axis": a, "axis_ko": ko[a], "contrib": lt["contrib"][a], "subindex": lt["subindex"][a], "axis_pct": lt["axis_pct"][a],
                        "contrib_20td_ago": lt["contrib_20td_ago"][a], "n_indicators": int((st.axis == a).sum())} for a in axes]).set_index("axis")
    _df_to_sheet(w3, ax, date_fmt="@")
    w4 = wb.create_sheet("Indicators_Latest")
    si = st.set_index("id")
    _df_to_sheet(w4, si, date_fmt="@", num_fmt="0.0000", widths={"name": 30, "definition": 46, "source": 40, "availability_rule": 18})

    # ── Raw_Daily · PIT_Daily · AxisContrib_Daily ──
    w5 = wb.create_sheet("Raw_Daily")
    raw = d[[f"x_{i}" for i in ids]].copy()
    raw.columns = ids
    raw.index.name = "Date"
    _df_to_sheet(w5, raw, num_fmt="0.000000")
    w6 = wb.create_sheet("PIT_Daily")
    z = d[[f"z_{i}" for i in ids]].copy()
    z.columns = ids
    z.index.name = "Date"
    _df_to_sheet(w6, z, num_fmt="0.000")
    w7 = wb.create_sheet("AxisContrib_Daily")
    cc = d[[f"c_{a}" for a in axes]].copy()
    cc.columns = [ko[a] for a in axes]
    cc.index.name = "Date"
    _df_to_sheet(w7, cc, num_fmt="0.000")

    # ── Crises · Thresholds · Meta ──
    w8 = wb.create_sheet("Crises")
    e = eps.copy()
    e.index = range(1, len(e) + 1)
    e.index.name = "no"
    _df_to_sheet(w8, e, date_fmt="@", num_fmt="0.000")
    r = len(e) + 3
    w8.cell(row=r, column=1, value="경보 시점(80 · 90 백분위) · 신호별").font = Font(bold=True)
    keep = [c for c in cv.columns if c in ("peak", "confirm_minus20", "trough", "depth", "score_at_peak", "score_max", "score_max_date") or "alarm_lag_from_peak_td" in c or "alarm_lead_vs_confirm_td" in c]
    cv2 = cv[keep].copy()
    cv2.index = range(1, len(cv2) + 1)
    cv2.index.name = "no"
    _df_to_sheet(w8, cv2, start_row=r + 1, date_fmt="@", num_fmt="0.000", freeze=False)
    w9 = wb.create_sheet("Thresholds")
    _hdr(w9, 1, ["signal", "key", "value"])
    i = 2
    for sig, dct in nsr.items():
        for k, v in dct.items():
            w9.cell(row=i, column=1, value=sig)
            w9.cell(row=i, column=2, value=k)
            w9.cell(row=i, column=3, value=None if v is None or (isinstance(v, float) and v != v) else v)
            i += 1
    w9.column_dimensions["A"].width, w9.column_dimensions["B"].width, w9.column_dimensions["C"].width = 16, 28, 16
    rr = rob.copy()
    rr.index = range(1, len(rr) + 1)
    rr.index.name = "no"
    _df_to_sheet(w9, rr, start_row=i + 2, date_fmt="@", num_fmt="0.000", freeze=False)
    w10 = wb.create_sheet("Meta")
    _hdr(w10, 1, ["key", "value", "source"])
    rows = [("run_at", meta["run_at"], ""), ("data_last_date", meta["last_date"], ""), ("composite_start", meta["composite_start_t0"], ""),
            ("fred_availability_rules", json.dumps(meta["fred_availability_rules"], ensure_ascii=False), "06_Registry/fred_availability_rules.json 사본(연구용)")]
    rows += [(f"data_file:{k}", v["mtime"], "") for k, v in meta["data_files"].items()]
    rows += [(f"param:{k}", json.dumps(v["value"], ensure_ascii=False), v["source"]) for k, v in meta["params"].items()]
    rows += [(f"indicator:{x['id']}", f"{x['name']} — {x['definition']}", f"{x['source']} · 가용 규칙 {x['availability_rule'] or '당일 마감'}") for x in meta["indicators"]]
    for i, (k, v, s) in enumerate(rows, start=2):
        w10.cell(row=i, column=1, value=k)
        w10.cell(row=i, column=2, value=str(v)[:32000])
        w10.cell(row=i, column=3, value=str(s)[:32000])
    w10.column_dimensions["A"].width, w10.column_dimensions["B"].width, w10.column_dimensions["C"].width = 34, 80, 90
    path = f"{folder}/kr_stress_dashboard_{day}.xlsx"
    wb.save(path)
    return path


# ─────────────────────────────────────────────────────────────────────────────
def main():
    no_pdf = "--no-pdf" in sys.argv
    meta, d, st, eps, cv, nsr, rob = load()
    day = meta["last_date"]
    folder = f"{DAILY}/{day}"
    latest = f"{DAILY}/latest"
    os.makedirs(folder, exist_ok=True)
    os.makedirs(latest, exist_ok=True)
    for f in ("v1_01_index_timeseries_crises.png", "v1_02_axis_contribution_latest.png", "v1_05_recent_18m_zoom.png"):
        shutil.copy2(f"{CH}/{f}", f"{folder}/{f}")
    md = write_markdown(meta, d, st, eps, nsr, rob, folder, day)
    log("markdown", md)
    xlsx = write_excel(meta, d, st, eps, cv, nsr, rob, folder, day)
    log("excel", xlsx, f"{os.path.getsize(xlsx) / 1e6:.1f} MB")
    pdf = None
    if not no_pdf:
        pdf = render_pdf(md)
        log("pdf", pdf)
    for src, dst in ((md, "kr_stress_daily_latest.md"), (xlsx, "kr_stress_dashboard_latest.xlsx"), (pdf, "kr_stress_daily_latest.pdf")):
        if src and os.path.exists(src):
            shutil.copy2(src, f"{latest}/{dst}")
    for f in ("v1_01_index_timeseries_crises.png", "v1_02_axis_contribution_latest.png", "v1_05_recent_18m_zoom.png"):
        shutil.copy2(f"{CH}/{f}", f"{latest}/{f}")
    json.dump({"day": day, "run_at": dt.datetime.now().isoformat(timespec="seconds"), "score": meta["latest"]["score"],
               "score_pct": meta["latest"]["score_pct"], "tier": tier_of(meta["latest"]["score_pct"], nsr.get("v1", {})),
               "pdf": pdf, "xlsx": xlsx, "md": md}, open(f"{latest}/latest.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    log("done", day)


if __name__ == "__main__":
    main()
