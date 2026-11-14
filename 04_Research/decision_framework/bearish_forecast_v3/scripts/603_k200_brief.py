"""603_k200_brief.py — K200 일간 위험 브리핑: 발송 원천 결정(H1 | P3 대체 | 보류) + 본문 · 차트 (아침 체인 [6b]).

도훈 결정 K200-RISK-H1-REPLACE-P3-20261114: H1 본 모형 · 이상 입력 점검 · P3 는 비교용 산출 · 기록만.
  H1   = H1_guard_latest.json 이 기준일 · 차단 아님 + H1_latest.json 기준일 일치 → H1 본문 · 차트
  P3   = H1 이 차단 · 산출 없음 · 기준일 불일치이고, 벤치 자료 점검 통과 + P3 기준일 일치 + P3 물리 한계 통과
         → 운영 P3 브리핑(600_morning_brief.make_brief) + 맨 위 대체 안내 줄
  보류 = 둘 다 안 되면 수치 없이 사유만
산출(--out-root/<기준일>/): brief.md · dist.png · trend.png · brief_meta.json(발송기가 사진 · 설명을 여기서 읽는다)
기록: --pred-dir/k200_brief_log.jsonl (한 줄 = 한 실행 · H1 · P3 나란히)
사용: python scripts/603_k200_brief.py --asof 2026-11-13 [--pred-dir DIR] [--out-root DIR]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates  # noqa: E402
import matplotlib.font_manager as fm  # noqa: E402
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

for _f in ["Malgun Gothic", "NanumGothic", "AppleGothic", "NanumBarunGothic", "DejaVu Sans"]:
    if any(font.name == _f for font in fm.fontManager.ttflist):
        plt.rcParams["font.family"] = _f
        break
plt.rcParams["axes.unicode_minus"] = False

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent.parent.parent
SEP = "───────────────"
TREND_DAYS = 60


def _load(name, p):
    spec = importlib.util.spec_from_file_location(name, str(p))
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m


H = _load("h1_dr_newsvk", ROOT / "03_models" / "h1_dr_newsvk.py")
G = _load("h1_guard", ROOT / "03_models" / "h1_guard.py")


def _read_json(p: Path):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None


def _write_json(p: Path, obj):
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2, default=str), encoding="utf-8")
    os.replace(tmp, p)


def _fmt_date(d):
    return pd.Timestamp(d).strftime("%Y-%m-%d (%a)")


# ─── 발송 원천 결정 ────────────────────────────────────────────────────────────────────────────────────
def decide(asof, pred_dir: Path, cfg: dict):
    a = str(pd.Timestamp(asof).date())
    g = _read_json(pred_dir / "H1_guard_latest.json")
    h1 = _read_json(pred_dir / "H1_latest.json")
    p3 = _read_json(pred_dir / "P3_latest.json")
    bm = pd.read_parquet(PROJECT_ROOT / ".cache" / "benchmark.parquet")
    b = G.bench_frame(bm, cfg["ewma_lambda"])
    bblk, _, binfo = G.check_bench(b, asof, cfg, live=True)
    reasons = []
    h1_ok = bool(g and g.get("asof") == a and g.get("status") != "BLOCK" and h1 and h1.get("asof_date") == a
                 and not h1.get("blocked") and h1.get("sigma") is not None)
    if not h1_ok:
        if not g or g.get("asof") != a:
            reasons.append(f"H1 점검 결과 없음 · 기준일 불일치(점검 {g.get('asof') if g else '없음'})")
        elif g.get("status") == "BLOCK":
            reasons += [f"H1 차단 {x['code']}: {x['msg']}" for x in g.get("block", [])]
        else:
            reasons.append(f"H1 예측 파일 기준일 불일치({h1.get('asof_date') if h1 else '없음'})")
    p3_ok, p3_blk, p3_wrn = G.p3_fallback_check(p3, asof, binfo.get("ewma_t", float("nan")), cfg)
    if h1_ok:
        src = "H1"
    elif not bblk and p3_ok:
        src = "P3"
    else:
        src = "HOLD"
        reasons += [f"자료 {x['code']}: {x['msg']}" for x in bblk]
        reasons += [f"P3 {x['code']}: {x['msg']}" for x in p3_blk]
    return {"asof": a, "source": src, "reasons": reasons, "h1_guard": g, "h1": h1, "p3": p3,
            "p3_ok": p3_ok, "p3_warn": p3_wrn, "bench_block": bblk, "bench_info": binfo}


# ─── H1 본문 ──────────────────────────────────────────────────────────────────────────────────────────
def _sigma_state(s):
    return "낮음 (안정)" if s < 1.0 else ("정상" if s < 1.8 else ("높음" if s < 2.8 else "매우 높음 ⚠️"))


def _lam_state(l):
    return "강한 bear 편향 ⚠️" if l < -0.3 else ("bear 편향" if l < -0.1 else ("중립" if l < 0.1 else "bull 편향"))


def _nu_state(n):
    return "fat-tail (극단치 잦음) ⚠️" if n < 8 else ("보통" if n < 50 else "Normal-like (얇음)")


def _shown_warnings(g: dict) -> list:
    out = []
    for w in (g or {}).get("warn", []):
        if w["code"] == "W3" and not w.get("material", False):
            continue
        out.append(w)
    return out


def h1_brief_text(asof, dec: dict, hist: pd.DataFrame) -> str:
    t = pd.Timestamp(asof)
    today = hist[hist["Date"] == t].iloc[0]
    idx = hist.index[hist["Date"] == t][0]
    recent = hist.loc[max(0, idx - 21): idx]
    g = dec["h1_guard"]
    shown = _shown_warnings(g)
    sigma, lam, nu, mu = float(today.sigma), float(today.lam), float(today.nu), float(today.mu)
    vk = float(today.vkospi)
    md = ["📊 KOSPI 200 일간 위험 브리핑", "",
          f"데이터 기준일 : {_fmt_date(t)} 종가 (직전 영업일)",
          "적용 대상     : 다음 1 거래일",
          "모델          : H1 분포 회귀 + V-KOSPI200 (Hansen 비대칭 t · 21거래일 재추정)",
          f"입력 점검     : {'✅ 통과' if not shown else f'⚠️ 경고 {len(shown)}건 (알림 참조)'}",
          SEP, "🌡️ 오늘의 시장 진단", "",
          "| 지표 | 값 | 상태 |",
          f"| 변동성 (σ) | {sigma:.2f}% | {_sigma_state(sigma)} |",
          f"| V-KOSPI200 (입력) | {vk:.2f} | 내재 일변동 {vk / math.sqrt(252):.2f}% |",
          f"| 비대칭성 (λ) | {lam:+.3f} | {_lam_state(lam)} · 창 상수 |",
          f"| 꼬리 두께 (ν) | {nu:.1f} | {_nu_state(nu)} · 창 상수 |",
          f"| 평균 예측 (μ) | {mu:+.3f}% | — |", "",
          f"한 줄 진단: 변동성 {_sigma_state(sigma)} · V-KOSPI200 {vk:.2f} · 분포 모양(λ · ν)은 {today.refit_anchor} 재추정 창 값",
          SEP, "🚨 오늘의 위험 한도", "",
          "| 한도 | 값 | 의미 |",
          f"| VaR 5% | {today.var_05:+.2f}% | 이보다 더 떨어질 확률 5% |",
          f"| VaR 1% | {today.var_01:+.2f}% | 이보다 더 떨어질 확률 1% |",
          f"| VaR 0.5% | {today.var_005:+.2f}% | 0.5% 극단 영역 |",
          f"| ES 5% | {today.es_05:+.2f}% | 5% 영역 발생 시 평균 손실 |", "",
          "💥 폭락 확률", "",
          "| 폭락 | 확률 | 빈도 환산 |"]
    for col, lab, dg in (("p_minus_5pct", "P(-5% 이상)", 2), ("p_minus_7pct", "P(-7% 이상)", 2), ("p_minus_10pct", "P(-10% 이상)", 3)):
        p = float(today[col]); f = (1 / p) if p > 0 else 9999
        md.append(f"| {lab} | {p * 100:.{dg}f}% | {f:.0f}일에 1번 |")
    md.append(SEP)
    # 직전 예측 검증 — 실현값이 있는 가장 최근 행
    prev = hist.loc[: idx - 1]
    prev = prev[prev["y_actual"].notna() & (prev["y_actual"].abs() > 1e-8)]
    if len(prev):
        pr = prev.iloc[-1]
        nxt = hist.loc[hist.index[hist["Date"] == pr["Date"]][0] + 1, "Date"] if (hist["Date"] > pr["Date"]).any() else None
        breach = pr["y_actual"] < pr["var_05"]
        pit = pr.get("pit", float("nan"))
        md += ["📈 직전 forecast 검증",
               f"Forecast 날짜: {_fmt_date(pr['Date'])} 종가 → 실현 날짜: {_fmt_date(nxt) if nxt is not None else '다음 거래일'}", "",
               "| 항목 | 값 |",
               f"| 실제 등락률 | {pr['y_actual']:+.2f}% |",
               f"| 예측 VaR 5% | {pr['var_05']:+.2f}% |",
               f"| VaR 5% breach | {'⚠️ YES (큰 손실)' if breach else '✅ NO (한도 내)'} |"]
        if pd.notna(pit):
            st = "꼬리 (extreme)" if pit < 0.05 or pit > 0.95 else ("우측" if pit > 0.7 else ("좌측" if pit < 0.3 else "중심"))
            md.append(f"| PIT 위치 | {pit:.3f} ({st}) |")
        md.append(SEP)
    # 22일 추세
    rw = recent[recent["y_actual"].notna()]
    nb = int((rw["y_actual"] < rw["var_05"]).sum()); nv = len(rw)
    s22 = float(recent["sigma"].mean()); v22 = float(recent["vkospi"].mean())
    s_tr = "상승" if sigma > s22 * 1.1 else ("하락" if sigma < s22 * 0.9 else "안정")
    v_tr = "상승" if vk > v22 * 1.1 else ("하락" if vk < v22 * 0.9 else "안정")
    md += ["📉 최근 22 거래일 (1개월) 추세", "",
           "| 지표 | 22일 평균 | 오늘 | 추세 |",
           f"| σ 변동성 | {s22:.2f}% | {sigma:.2f}% | {s_tr} |",
           f"| V-KOSPI200 | {v22:.2f} | {vk:.2f} | {v_tr} |"]
    if nv > 0:
        bp = nb / nv * 100
        md.append(f"| VaR 5% breach | {nb}/{nv}일 = {bp:.0f}% | — | {'정상' if bp <= 10 else 'OVER ⚠️'} |")
    md.append(SEP)
    # 알림 — P3 브리핑과 같은 규칙 + 입력 점검 경고
    al = []
    if sigma > 2.8:
        al.append(f"🔴 변동성 매우 높음 (σ={sigma:.2f}%, 평소 1.3% 대비 {sigma / 1.3:.1f}x) — position size 검토")
    if lam < -0.3:
        al.append(f"🟡 강한 bear 편향 (λ={lam:.3f}) — hedge 검토")
    if today.p_minus_10pct * 100 > 1.0:
        al.append(f"🔴 P(-10%) 비정상 활성 ({today.p_minus_10pct * 100:.2f}%) — tail risk 큼")
    if today.p_minus_5pct * 100 > 5.0:
        al.append(f"🟡 P(-5%) 높음 ({today.p_minus_5pct * 100:.2f}%) — 일반적 1% 이하")
    if nv > 0 and nb / max(nv, 1) > 0.18:
        al.append(f"🟡 breach 빈도 OVER ({nv}일 중 {nb}회 vs 정상 1-2회)")
    for w in shown:
        al.append(f"🟠 입력 점검 {w['code']}: {w['msg']}")
    if not al:
        al.append("🟢 특이사항 없음 — 정상 상태")
    md += ["🔔 알림", ""] + [f"  · {x}" for x in al] + [SEP]
    rl = "🟢 정상"
    if sigma > 2.0 or lam < -0.2 or today.p_minus_10pct * 100 > 0.5:
        rl = "🟡 주의"
    if sigma > 2.8 or lam < -0.3 or today.p_minus_10pct * 100 > 1.0:
        rl = "🔴 경계"
    md += [f"🎯 종합 risk level: {rl}", "",
           "본 모형 H1 · P3 는 비교 기록만 (2026-11-14 교체 · 사전등록 검증 OOS 로그 점수 +0.066/일)",
           f"시각자료: dist.png (오늘 분포 + 위험선) / trend.png (최근 {TREND_DAYS}거래일 σ · V-KOSPI200 · VaR 대비 실현)"]
    return "\n".join(md)


def h1_charts(asof, hist: pd.DataFrame, out_dir: Path):
    t = pd.Timestamp(asof)
    today = hist[hist["Date"] == t].iloc[0]
    mu, sg, nu, lam = float(today.mu), float(today.sigma), float(today.nu), float(today.lam)
    lo = min(-12.0, float(today.var_001) - 1.0)
    hi = max(8.0, float(H.hansen_ppf(np.array([0.999]), np.array([mu]), np.array([sg]), np.array([nu]), np.array([lam]))[0, 0]) + 1.0)
    x = np.linspace(lo, hi, 1200)
    pdf = np.exp(H.hansen_logpdf(x, mu, sg, nu, lam))
    fig, ax = plt.subplots(figsize=(11, 5.5))
    ax.plot(x, pdf, color="#2c3e50", lw=2.2, label="오늘 분포 예측 (H1)")
    ax.fill_between(x, 0, pdf, where=(x < today.var_05), color="#e74c3c", alpha=0.30, label=f"VaR 5% 영역 (< {today.var_05:+.2f}%)")
    ax.fill_between(x, 0, pdf, where=(x < today.var_01), color="#c0392b", alpha=0.55, label=f"VaR 1% 영역 (< {today.var_01:+.2f}%)")
    ax.axvline(today.var_05, color="#e74c3c", ls="--", lw=1.2)
    ax.axvline(today.var_01, color="#c0392b", ls="--", lw=1.5)
    ax.axvline(mu, color="#27ae60", ls=":", lw=1.0, label=f"평균 μ {mu:+.3f}%")
    prev = hist[(hist["Date"] < t) & hist["y_actual"].notna()]
    if len(prev):
        pr = prev.iloc[-1]
        ax.axvline(pr["y_actual"], color="#3498db", lw=1.8, label=f"직전 실현 ({pr['y_actual']:+.2f}%)")
    ax.set_xlabel("다음 1일 KOSPI200 로그 등락률 (%)"); ax.set_ylabel("확률 밀도")
    ax.set_title(f"H1 분포 예측 (기준 {t.date()} 종가)  σ={sg:.2f}%  ν={nu:.1f}  λ={lam:+.3f}  V-KOSPI200={today.vkospi:.2f}", fontsize=11)
    ax.legend(loc="upper left", fontsize=8); ax.set_xlim(lo, hi); ax.grid(alpha=0.25)
    fig.tight_layout(); fig.savefig(out_dir / "dist.png", dpi=110); plt.close(fig)

    r = hist[hist["Date"] <= t].tail(TREND_DAYS).copy()
    d = r["Date"].values
    fig, axes = plt.subplots(3, 1, figsize=(11, 9), sharex=True)
    a0 = axes[0]
    a0.plot(d, r["sigma"], color="#2c3e50", lw=1.8, marker="o", ms=3, label="H1 σ 예측")
    a0.plot(d, r["vkospi"] / math.sqrt(252), color="#8e44ad", lw=1.3, ls="--", label="V-KOSPI200 내재 일변동 (VK/√252)")
    a0.scatter(d, r["y_actual"].abs(), color="#e67e22", s=14, zorder=3, label="실현 |등락률| (다음 날)")
    a0.set_ylabel("일 변동 (%)"); a0.set_title(f"최근 {TREND_DAYS}거래일 — H1 예측 vs 실현", fontsize=11)
    a0.legend(fontsize=8, loc="upper left"); a0.grid(alpha=0.25)
    a1 = axes[1]
    y = r["y_actual"]
    br = y < r["var_05"]
    a1.bar(d, y, color=np.where(br, "#c0392b", "#95a5a6"), width=0.8, label="실현 등락률 (빨강 = VaR 5% 이탈)")
    a1.plot(d, r["var_05"], color="#e74c3c", lw=1.4, label="VaR 5%")
    a1.plot(d, r["var_01"], color="#8b0000", lw=1.2, ls="--", label="VaR 1%")
    a1.axhline(0, color="gray", lw=0.6)
    nb = int(br.sum()); nv = int(y.notna().sum())
    a1.set_ylabel("등락률 (%)"); a1.set_title(f"VaR 대비 실현 — 이탈 {nb}/{nv}일", fontsize=10)
    a1.legend(fontsize=8, loc="lower left"); a1.grid(alpha=0.25)
    a2 = axes[2]
    a2.plot(d, r["p_minus_5pct"] * 100, color="#e74c3c", marker="o", ms=3, lw=1.4, label="P(-5%)")
    a2.plot(d, r["p_minus_10pct"] * 100, color="#8b0000", marker="s", ms=3, lw=1.4, label="P(-10%)")
    a2.set_ylabel("폭락 확률 (%)"); a2.legend(fontsize=8, loc="upper left"); a2.grid(alpha=0.25)
    if len(r) > 22:
        for ax in axes:
            ax.axvline(r["Date"].iloc[-22], color="gray", ls=":", lw=1.0)
    a2.xaxis.set_major_formatter(mdates.DateFormatter("%m-%d"))
    fig.autofmt_xdate(); fig.tight_layout(); fig.savefig(out_dir / "trend.png", dpi=110); plt.close(fig)


# ─── P3 대체 · 보류 ─────────────────────────────────────────────────────────────────────────────────
def p3_fallback(asof, dec, pred_dir: Path, out_root: Path):
    P600 = _load("p600", ROOT / "scripts" / "600_morning_brief.py")
    out_dir, md = P600.make_brief(pred_dir / "P3_daily.parquet", str(pd.Timestamp(asof).date()), out_root)
    banner = ["⚠️ 오늘은 P3 대체 발송 — 본 모형 H1 이 입력 점검을 통과하지 못했습니다"]
    banner += [f"  · {x}" for x in dec["reasons"][:3]]
    banner += [f"  · P3 점검 경고 {w['code']}: {w['msg']}" for w in dec["p3_warn"][:2]]
    body = "\n".join(banner) + "\n" + SEP + "\n" + md
    (Path(out_dir) / "brief.md").write_text(body + "\n", encoding="utf-8")
    return Path(out_dir), body


def hold_text(asof, dec):
    md = ["📊 KOSPI 200 일간 위험 브리핑", "",
          f"데이터 기준일 : {_fmt_date(asof)} 종가 (직전 영업일)",
          "⛔ 입력 점검 실패 — 오늘 수치를 보류합니다 (H1 · P3 모두 발송 조건 미충족)", SEP, "사유"]
    md += [f"  · {x}" for x in (dec["reasons"] or ["사유 기록 없음"])][:8]
    md += [SEP, "조치: 자료 갱신(벤치 종가 · V-KOSPI200) 확인 뒤 [6/6] 단계 재실행"]
    return "\n".join(md)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--asof", required=True)
    ap.add_argument("--pred-dir", default=str(ROOT / "03_models" / "daily_predictions"))
    ap.add_argument("--out-root", default=str(ROOT / "03_models" / "morning_brief"))
    a = ap.parse_args()
    pred_dir, out_root = Path(a.pred_dir), Path(a.out_root)
    cfg = G.load_config()
    asof = pd.Timestamp(a.asof)
    out_dir = out_root / str(asof.date())
    out_dir.mkdir(parents=True, exist_ok=True)
    meta_p = out_dir / "brief_meta.json"
    if meta_p.exists():
        meta_p.unlink()   # 이번 실행이 끝까지 가야만 새 메타가 생긴다(중간 실패 = 메타 없음 → 발송기 구 방식)
    dec = decide(asof, pred_dir, cfg)
    src = dec["source"]
    if src == "H1":
        hist = pd.read_parquet(pred_dir / "H1_daily.parquet"); hist["Date"] = pd.to_datetime(hist["Date"])
        hist = hist.sort_values("Date").reset_index(drop=True)
        body = h1_brief_text(asof, dec, hist)
        (out_dir / "brief.md").write_text(body + "\n", encoding="utf-8")
        h1_charts(asof, hist, out_dir)
        photos = [{"file": "dist.png", "caption": f"H1 · 오늘 분포 예측 (기준 {asof.date()} 종가)"},
                  {"file": "trend.png", "caption": f"H1 · 최근 {TREND_DAYS}거래일 σ · V-KOSPI200 · VaR 대비 실현"}]
    elif src == "P3":
        out_dir, body = p3_fallback(asof, dec, pred_dir, out_root)
        photos = [{"file": "dist.png", "caption": "P3(대체) · 오늘 분포 forecast"},
                  {"file": "trend.png", "caption": "P3(대체) · 22일 추세"},
                  {"file": "p3_9quad_riskpro.png", "caption": "P3(대체) Risk Manager Pro Dashboard"}]
    else:
        body = hold_text(asof, dec)
        (out_dir / "brief.md").write_text(body + "\n", encoding="utf-8")
        photos = []
    h1 = dec["h1"] or {}; p3 = dec["p3"] or {}; g = dec["h1_guard"] or {}
    meta = {"asof": dec["asof"], "source": src, "photos": photos, "reasons": dec["reasons"],
            "made_at": datetime.now().isoformat(timespec="seconds"), "decision": cfg.get("decision"),
            "h1": {"status": g.get("status"), "codes": [x["code"] for x in g.get("block", []) + g.get("warn", [])],
                   "sigma": h1.get("sigma") if h1.get("asof_date") == dec["asof"] else None},
            "p3": {"ok": dec["p3_ok"], "sigma": p3.get("sigma") if p3.get("asof_date") == dec["asof"] else None}}
    _write_json(meta_p if src != "P3" else Path(out_dir) / "brief_meta.json", meta)
    log = {"asof": dec["asof"], "made_at": meta["made_at"], "source": src, "reasons": dec["reasons"][:5],
           "h1_status": g.get("status") if g.get("asof") == dec["asof"] else "stale",
           "h1_sigma": meta["h1"]["sigma"], "h1_var_05": h1.get("var_05") if h1.get("asof_date") == dec["asof"] else None,
           "p3_sigma": meta["p3"]["sigma"], "p3_var_05": p3.get("var_05") if p3.get("asof_date") == dec["asof"] else None,
           "p3_ok": dec["p3_ok"]}
    with open(pred_dir / "k200_brief_log.jsonl", "a", encoding="utf-8") as fh:
        fh.write(json.dumps(log, ensure_ascii=False, default=str) + "\n")
    print(f"[brief] source={src} → {out_dir}")
    for x in dec["reasons"][:5]:
        print(f"[brief]   reason: {x}")
    print(f"[brief] H1 σ={log['h1_sigma']} · P3 σ={log['p3_sigma']} (P3 = 비교 기록)")
    print("=" * 70 + "\n" + body + "\n" + "=" * 70)


if __name__ == "__main__":
    main()
