#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""KR 자본시장 스트레스 일보 — 같은 형태 · 내용만 바뀌는 PDF 보고서(A4 세로) + 원자료 엑셀 대시보드(도훈 2026-11-06 요청).

입력 = build_kr_stress_index_v1.py 의 output/v1/ (+ 캐시 benchmark.parquet 의 KOSPI200).
출력 = daily/<데이터 기준일>/  kr_stress_daily_<일자>.md · .pdf · kr_stress_dashboard_<일자>.xlsx · 차트 d1~d7.png
       daily/latest/           같은 파일의 '_latest' 사본(고정 경로) + latest.json
PDF = 프로젝트 단일 경로 00_Lawbook/tools/md_to_print_pdf.R(현대하모니 L/M/B · Edge 인쇄 · pdf_check) — 서식 규칙 docs/rules/pdf-output-style.md.
차트 = daily_charts.py(본문 폭 188mm 에 1:1 · 글자 9pt 안팎 — 축소로 글자가 뭉개지지 않게 쪽 크기로 그린다).
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

import numpy as np
import pandas as pd
from openpyxl import Workbook
from openpyxl.chart import BarChart, LineChart, Reference
from openpyxl.formatting.rule import ColorScaleRule, DataBarRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

HERE = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..")).replace("\\", "/")
sys.path.insert(0, HERE)
import daily_charts  # noqa: E402
import daily_text  # noqa: E402  (임원 보고용 본문 — 높임말 · 쉬운 말 · 꾸민 HTML 표)

OUT = HERE + "/output/v1"
DAILY = HERE + "/daily"
RSCRIPT = os.environ.get("QVEST_RSCRIPT", "C:/Program Files/R/R-4.5.2/bin/Rscript.exe")
PDF_TOOL = ROOT + "/00_Lawbook/tools/md_to_print_pdf.R"
TIER_COLOR = {"정상": "C6EFCE", "주의": "FFEB9C", "위험": "FFC7CE"}
CHART_FILES = ["d1_gauge.png", "d2_axis_contrib.png", "d3_heatmap_65d.png", "d4_radar_hist.png", "d5_indicators.png", "d6_recent_18m.png", "d7_history.png"]


def log(*a):
    print("[daily]", *a, flush=True)


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
    bm = pd.read_parquet(ROOT + "/.cache/benchmark.parquet")
    bm["Date"] = pd.to_datetime(bm["Date"])
    bm = bm.sort_values("Date").drop_duplicates("Date", keep="last").set_index("Date")["BM_Close"].astype(float)
    derive_level(meta, d, st, nsr.get("v1", {}))
    return meta, d, st, eps, cv, nsr, rob, bm


def derive_level(meta, d, st, ns):
    """표시용 점수 눈금(도훈 11-06 "점수를 좀 더 직관적으로") — 점수 = 10·√(CISS 원값). 원값은 '분야들이 같이 움직일수록 커지는 합'(포트폴리오 분산 꼴)이라
    2006년 이후 중앙값 2 · 2008년 정점 67 로 눈금 아래쪽에 몰린다. 분산을 변동성으로 읽듯 제곱근을 취하면 평상시 14 · 2011년 46 · 2020년 61 · 2008년 82.
    단조 변환이라 백분위 · 단계 · 위기 검증은 그대로다. 분야 · 지표 몫은 오일러 배분(원값 몫 × 10/√원값 — 합 = 점수). 동행률 = 점수 ÷ 34지표 평균 심각도(0~1)."""
    axes = meta["axes"]
    lt = meta["latest"]
    s = d["score"].clip(lower=0)
    d["level"] = 10 * np.sqrt(s)
    f = pd.Series(np.where(s > 0, 10 / np.sqrt(s.where(s > 0)), 0.0), index=d.index)
    for a in axes:
        d[f"cl_{a}"] = d[f"c_{a}"] * f
    d["comove"] = (d["level"] / d["score_linear"]).where(d["score_linear"] > 0)

    def lvl(x):
        return float(10 * np.sqrt(max(float(x), 0.0)))

    def fac(x):
        return float(10 / np.sqrt(x)) if x and x > 0 else 0.0
    lt["level"] = lvl(lt["score"])
    lt["level_20td_ago"] = lvl(lt["score_20td_ago"])
    lt["level_60td_ago"] = lvl(lt["score_60td_ago"])
    lt["max_level"] = lvl(lt["max_score_since_t0"])
    lt["contrib_level"] = {a: v * fac(lt["score"]) for a, v in lt["contrib"].items()}
    lt["contrib_level_20td_ago"] = {a: v * fac(lt["score_20td_ago"]) for a, v in lt["contrib_20td_ago"].items()}
    lt["comove"] = lt["level"] / lt["score_linear"] if lt["score_linear"] else float("nan")
    st["contrib_level"] = st["contrib"] * fac(lt["score"])
    imax = d["score"].idxmax()
    meta["levels"] = {"warn": float(d["level"].quantile(ns.get("threshold_warn") or 0.8)), "risk": float(d["level"].quantile(ns.get("threshold_risk") or 0.99)),
                      "median": float(d["level"].median()), "linear_median": float(d["score_linear"].median()),
                      "comove_median": float(d["comove"].median()), "comove_at_max": float(d.loc[imax, "comove"])}
    meta["ref_marks"] = daily_text.ref_marks(d)


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
    chg = lt["level"] - lt["level_20td_ago"]
    dir_ = "올랐다" if chg > 1 else "내렸다" if chg < -1 else "비슷하다"
    s = (f"스트레스 점수 {lt['level']:.0f}/100(원값 {lt['score']:.1f} · 역대 순위 백분위 {100 * lt['score_pct']:.0f}) · 단계 **{tier_of(lt['score_pct'], ns)}** · "
         f"20거래일 전({lt['date_20td_ago']}) {lt['level_20td_ago']:.0f}보다 {dir_}. ")
    s += f"심각도 90 이상인 분야 = {' · '.join(on) if on else '없음'}; 평온한 분야(40 이하) = {' · '.join(calm) if calm else '없음'}. "
    s += f"34지표 평균 심각도 {lt['score_linear']:.0f} · 동행률 {100 * lt['comove']:.0f}% · V-KOSPI200 {lt['vkospi']:.1f}(백분위 {100 * lt['vkospi_pct']:.0f}). 축 평균 상관 {lt['avg_corr']:.2f}"
    s += "(높음 — 분야들이 함께 움직인다 = 체계적)." if lt["avg_corr"] >= 0.3 else "(낮음 — 분야들이 함께 움직이진 않는다)."
    return s


def peaks_of(d, k=8, gap_days=90):
    """점수(제곱근 눈금) 봉우리 — 단조 변환이라 날짜는 원값 봉우리와 같다."""
    s = d["level"].copy()
    out = []
    while len(out) < k and s.notna().any():
        i = s.idxmax()
        out.append((i, float(s.loc[i])))
        s[(s.index >= i - pd.Timedelta(days=gap_days)) & (s.index <= i + pd.Timedelta(days=gap_days))] = float("nan")
    return out


def render_pdf(md_path):
    pdf = md_path[:-3] + ".pdf"
    cmd = [RSCRIPT, "--no-save", PDF_TOOL, md_path, pdf, "portrait"]
    env = dict(os.environ)
    env.setdefault("PYTHONUTF8", "1")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env, cwd=ROOT)
    for t in (r.stdout + r.stderr).strip().splitlines()[-6:]:
        log("  pdf:", t[:220])
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
    ws["A2"] = "KR-CISS v1 · 12축 34지표 · 재귀 PIT · 지표 수준 EWMA 순위상관 집계 · 점수 = 10·√원값(0~100) · 아이디어 연구(등급 · BOOK 무관) · 설계 = DESIGN_v1_capital_market.md"
    ws["A2"].font = Font(italic=True, color="595959")
    lv = meta["levels"]
    kv = [("스트레스 점수(0~100 · 제곱근 눈금 · 높을수록 나쁨)", lt["level"], "0.0"), ("원값(CISS · 점수²/100)", lt["score"], "0.00"),
          ("역대 순위(백분위 % · 높을수록 나쁨)", 100 * lt["score_pct"], "0"), ("단계", tier_of(lt["score_pct"], ns), None),
          ("전일 점수", float(d["level"].iloc[-2]) if len(d) > 1 else None, "0.0"),
          (f"20거래일 전({lt['date_20td_ago']})", lt["level_20td_ago"], "0.0"), (f"60거래일 전({lt['date_60td_ago']})", lt["level_60td_ago"], "0.0"),
          ("34지표 평균 심각도(완전 동행 시 점수 상한)", lt["score_linear"], "0.0"), ("동행률(점수 ÷ 평균 심각도 · %)", 100 * lt["comove"], "0"), ("축 평균 상관", lt["avg_corr"], "0.00"),
          ("V-KOSPI200", lt["vkospi"], "0.0"), ("V-KOSPI 역대 순위(백분위 %)", 100 * lt["vkospi_pct"], "0"),
          ("주의 문턱(백분위 % / 점수)", f"{100 * ns.get('threshold_warn', float('nan')):.0f} / {lv['warn']:.1f}", None), ("위험 문턱(백분위 % / 점수)", f"{100 * ns.get('threshold_risk', float('nan')):.0f} / {lv['risk']:.1f}", None),
          ("점수 눈금 기준점", " · ".join(f"{r['label']} {r['level']:.0f}" for r in meta["ref_marks"]), None),
          ("전 기간 최고", f"{lt['max_level']:.1f} ({lt['max_score_date']})", None)]
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
    ws.column_dimensions["A"].width = 40
    ws.column_dimensions["B"].width = 22
    ws["A22"] = headline_sentence(meta, d, ns).replace("**", "")
    ws["A22"].alignment = Alignment(wrap_text=True, vertical="top")
    ws.merge_cells("A22:F25")
    r0 = 27
    _hdr(ws, r0, ["분야", "기여도(점 · 합 = 점수)", "하위지수", "심각도(0~100 · 높을수록 나쁨)", "20거래일 전 기여도", "변화", "심각도 80 이상 세부 지표"])
    order = sorted(axes, key=lambda a: -lt["contrib_level"][a])
    for i, a in enumerate(order, start=r0 + 1):
        rows = st[st.axis == a]
        hot = " · ".join(f"{r.name}({100 * r.ecdf_pct:.0f})" for r in rows.itertuples() if r.ecdf_pct >= 0.8) or "—"
        vals = [ko[a], lt["contrib_level"][a], lt["subindex"][a], 100 * lt["axis_pct"][a], lt["contrib_level_20td_ago"][a], lt["contrib_level"][a] - lt["contrib_level_20td_ago"][a], hot]
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
    bar.title = f"분야별 기여도 — {day}"
    bar.add_data(Reference(ws, min_col=2, min_row=r0, max_row=r1), titles_from_data=True)
    bar.set_categories(Reference(ws, min_col=1, min_row=r0 + 1, max_row=r1))
    bar.height, bar.width = 9, 16
    bar.legend = None
    ws.add_chart(bar, "I4")
    r2 = r1 + 2
    _hdr(ws, r2, ["id", "분야", "지표", "값", "심각도(0~100)", "기여도(점)", "관측일", "묵음(td)"])
    top = st.sort_values("contrib_level", ascending=False).head(12)
    for i, r in enumerate(top.itertuples(), start=r2 + 1):
        for j, v in enumerate([r.id, ko[r.axis], r.name, float(r.value), 100 * float(r.ecdf_pct), float(r.contrib_level), str(r.last_obs_date), int(r.stale_trading_days)], start=1):
            c = ws.cell(row=i, column=j, value=v)
            c.border = BORDER
            c.number_format = {4: "0.0000", 5: "0", 6: "0.00"}.get(j, "General")

    # ── Index_Daily (+ 꺾은선 차트) ──
    w2 = wb.create_sheet("Index_Daily")
    cols = ["level", "score", "score_pct", "score_linear", "comove", "score_axis_level", "avg_corr", "vkospi", "vkospi_pct"] + [f"cl_{a}" for a in axes] + [f"c_{a}" for a in axes] + [f"s_{a}" for a in axes] + [f"pct_{a}" for a in axes]
    dd = d[cols].copy()
    dd["tier"] = [tier_of(p, ns) if p == p else None for p in dd["score_pct"]]
    dd.index.name = "Date"
    _df_to_sheet(w2, dd, num_fmt="0.0000")
    n = len(dd) + 1
    lc = LineChart()
    lc.title = "스트레스 점수(0~100 · 제곱근 눈금) — 전 기간"
    lc.add_data(Reference(w2, min_col=2, min_row=1, max_row=n), titles_from_data=True)
    lc.set_categories(Reference(w2, min_col=1, min_row=2, max_row=n))
    lc.height, lc.width = 9, 24
    lc.legend = None
    ws.add_chart(lc, "I27")

    # ── Axes_Latest · Indicators_Latest ──
    w3 = wb.create_sheet("Axes_Latest")
    ax = pd.DataFrame([{"axis": a, "axis_ko": ko[a], "contrib_level": lt["contrib_level"][a], "contrib_raw": lt["contrib"][a], "subindex": lt["subindex"][a], "axis_pct": lt["axis_pct"][a],
                        "contrib_level_20td_ago": lt["contrib_level_20td_ago"][a], "n_indicators": int((st.axis == a).sum())} for a in axes]).set_index("axis")
    _df_to_sheet(w3, ax, date_fmt="@")
    w4 = wb.create_sheet("Indicators_Latest")
    _df_to_sheet(w4, st.set_index("id"), date_fmt="@", num_fmt="0.0000", widths={"name": 30, "definition": 46, "source": 40, "availability_rule": 18})

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
    cc = d[[f"cl_{a}" for a in axes]].copy()          # 점수 눈금의 분야별 몫(합 = 점수) — 원값 몫은 Index_Daily 의 c_<축>
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
    meta, d, st, eps, cv, nsr, rob, bm = load()
    day = meta["last_date"]
    folder = f"{DAILY}/{day}"
    latest = f"{DAILY}/latest"
    os.makedirs(folder, exist_ok=True)
    os.makedirs(latest, exist_ok=True)
    meta["axis_ko"] = {a: daily_text.AXIS_PLAIN[a][0] for a in meta["axes"]}   # 차트 · 표 · 본문의 분야 이름을 쉬운 말로 통일
    charts = daily_charts.make_all(meta, d, st, eps, bm, folder, nsr.get("v1", {}))
    log("charts", len(charts), "→", folder)
    md = f"{folder}/kr_stress_daily_{day}.md"
    open(md, "w", encoding="utf-8", newline="\n").write(daily_text.build_markdown(meta, d, st, eps, cv, nsr, rob, day, peaks_of(d)))
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
    for f in CHART_FILES:
        shutil.copy2(f"{folder}/{f}", f"{latest}/{f}")
    for stale in ("v1_01_index_timeseries_crises.png", "v1_02_axis_contribution_latest.png", "v1_05_recent_18m_zoom.png"):
        for p in (f"{folder}/{stale}", f"{latest}/{stale}"):
            if os.path.exists(p):
                os.remove(p)
    json.dump({"day": day, "run_at": dt.datetime.now().isoformat(timespec="seconds"), "level": round(meta["latest"]["level"], 2), "score": meta["latest"]["score"],
               "score_pct": meta["latest"]["score_pct"], "tier": tier_of(meta["latest"]["score_pct"], nsr.get("v1", {})),
               "levels": {k: round(v, 2) for k, v in meta["levels"].items()}, "ref_marks": meta["ref_marks"],
               "pdf": pdf, "xlsx": xlsx, "md": md, "charts": CHART_FILES}, open(f"{latest}/latest.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    log("done", day)


if __name__ == "__main__":
    main()
