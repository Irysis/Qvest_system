"""41_report_message.py — 보고 1통 본문(report_message.json)을 산출 파일의 수치로만 만든다(손 수치 없음).

입력: prereg/prereg_v1.json · output/verdict_v1.json · output/eval_final.json · output/crisis_events_final.json · output/design_IS_diag.json
문체(도훈 11-13): 퀀트 전문 용어 · 표본 = IS / OOS · 가설 · 설계 · 판정 기준 먼저, 운영 상태는 뒤.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common as C  # noqa: E402


def J(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))


def pct(x, d=1):
    return f"{x * 100:.{d}f}%"


def main():
    reg = J(C.STUDY / "prereg" / "prereg_v1.json")
    ver = J(C.OUT / "verdict_v1.json")
    ev = J(C.OUT / "eval_final.json")
    ce = J(C.OUT / "crisis_events_final.json")
    dg = J(C.OUT / "design_IS_diag.json")
    lab = {c["name"]: c["label"] for c in reg["challengers"]}
    hyp = {c["name"]: c["hypothesis"] for c in reg["challengers"]}
    S_IS, S_OOS = ev["segments"]["IS"], ev["segments"]["OOS"]
    rec = ver["recommend"]
    P = S_OOS["P3"]; PI = S_IS["P3"]

    # ── 결론 1줄
    if rec:
        r = ver["challengers"][rec]["OOS"]
        head = (f"OOS 로그 점수 P3 {P['ls']:.4f} → {lab[rec]} {S_OOS[rec]['ls']:.4f} (하루 {r['ls']['mean']:+.4f} · DM t {r['ls']['t']:.2f}) — "
                f"사전등록 관문 통과 · 채택 권고 · 운영 반영은 도훈 확인 뒤")
    else:
        head = "등록 3건 모두 사전등록 기준 미달 — 운영 P3 유지"

    # ── 가설
    hyps = []
    for c in reg["challengers"]:
        hyps.append(f"{c['hypothesis']} {c['label']}: {c['mechanism_short']}")

    # ── 설계 · 판정 기준
    design = [
        "예측 대상: KOSPI200 다음 거래일 로그수익의 예측 분포 전체 · 정보 집합 = t 종가(15:30)까지 — 07:10 발송 시점의 미국 장 결과는 쓰지 않음",
        f"표본: IS {S_IS['P3']['first']}~2022-12(설계) · OOS 2023-01~{S_OOS['P3']['last'][:7]}(판정) · 모든 모형 같은 {ver['n_common']:,}거래일 · 워크포워드(그날까지 자료만)",
        f"주 지표: 로그 점수(엄격 적정 점수) 차이 · Diebold-Mariano HAC 단측 · Holm 보정(k = {ver['k']})",
        "관문: FZ0(VaR · ES 결합 점수 · Patton-Ziegel-Chen 2019) 비악화 · VaR 1% · 5% 적중률 비악화 · IS 같은 방향",
        "기준 = P3 재현(운영 코드 · 사양 그대로 · 운영 기록과 소수 6자리 일치) · 등록 전 OOS 집계 비공개",
    ]

    # ── 기준선
    def line(seg, s):
        vb = s["var_backtest"]
        return (f"{seg}: 로그 점수 {s['ls']:.4f} · CRPS {s['crps']:.4f} · VaR 5% 위반 {pct(vb['0.05']['kupiec']['rate'])} "
                f"(Kupiec p {vb['0.05']['kupiec']['p']:.3f}) · 1% 위반 {pct(vb['0.01']['kupiec']['rate'], 2)} "
                f"(p {vb['0.01']['kupiec']['p']:.3f}) · PIT χ² p {s['pit_chi2_20']['p']:.3f}")
    base = [line("IS", PI), line("OOS", P)]
    refs = []
    for seg, SS in (("IS", S_IS), ("OOS", S_OOS)):
        order = sorted(["P3", "GJR", "EWMA"], key=lambda m: -SS[m]["ls"])
        refs.append(f"{seg} 로그 점수 순위: " + " > ".join(f"{m} {SS[m]['ls']:.4f}" for m in order))
    base += refs
    base.append(f"진단(IS): Hansen 꼬리 ν 가 하한 2.5 에 붙은 날 {pct(dg['nu_at_lower_bound_frac'])} · 상한 50 {pct(dg['nu_at_upper_bound_frac'])} — "
                f"그날의 분위 11점에 분포를 다시 맞추는 2단 구조라 꼬리 모양이 날마다 흔들림")
    base.append("진단: P3 특징의 '1일 전 수익'은 실제로 r(t−1) — 당일 수익 r(t)가 직접 들어가지 않음(뉴스 충격 첫 항 누락)")

    # ── 판정
    verdict = []
    for m, r in ver["challengers"].items():
        o = r["OOS"]; g = r["gates"]; h = r["holm"]
        gate_txt = " · ".join(f"{k.split('_')[0]} {'○' if v else '×'}" for k, v in g.items())
        verdict.append(f"{lab[m]}: OOS 로그 점수 하루 {o['ls']['mean']:+.4f}(t {o['ls']['t']:.2f} · Holm 문턱 {h['threshold']:.4f} · p {h['p']:.2g}) · "
                       f"FZ0 {o['fz0_gain']['mean']:+.4f} · 관문 {gate_txt} → {'통과' if r['pass'] else '미달'}")

    # ── 위기 · 사건
    cr = []
    for c in ce["crises"]:
        if c["peak"] < "2019-01-01":
            continue
        mm = c["models"]
        if "P3" not in mm or (rec and rec not in mm):
            continue
        b = mm["P3"]
        txt = f"{c['peak']}→{c['trough']}(−{c['depth']*100:.0f}%): 초입 20일 VaR 5% 위반 P3 {b['onset_hits5']}회"
        if rec:
            txt += f" vs {lab[rec]} {mm[rec]['onset_hits5']}회 · 구간 로그 점수 {b['ls']:.3f} vs {mm[rec]['ls']:.3f}"
        cr.append(txt)
    al = ce["alerts"].get("-3", {})
    if al:
        red = al["red"]; yp = al["yellow_plus"]
        cr.append(f"운영 경보(다음날 ≤ −3%): 빨강 경보 {red['alerts']}일 적중률 {red['hit_rate']:.2f} · 정밀도 {red['precision']:.2f} / "
                  f"주의 이상 {yp['alerts']}일 적중률 {yp['hit_rate']:.2f} · 정밀도 {yp['precision']:.2f} · λ 판별력 AUC {al['lambda_auc']:.2f}")
    e3P = S_OOS["P3"]["events"]["-3"]
    ev_line = f"OOS 다음날 ≤ −3% 사건 {e3P['events']}회: P3 AUC {e3P['auc']:.3f} · Brier 기후값 대비 {e3P['bss']:+.3f}"
    if rec:
        e3C = S_OOS[rec]["events"]["-3"]
        ev_line += f" vs {lab[rec]} AUC {e3C['auc']:.3f} · {e3C['bss']:+.3f}"
    cr.append(ev_line)

    # ── 운영 · 다음
    ops = ["운영 브리핑(모닝 체인 [6/6] · P3)은 이번 연구 중 바꾸지 않았다"]
    if rec:
        ops.append(f"채택 시 배포: {lab[rec]} 를 스크래치 사본으로 운영 경로에 붙여 며칠 그림자 운용(P3 와 나란히 산출) → 시험 → 원자 교체")
    ops += ["다음 연구 후보: ① 발송 시점 정보(미국 t 일 장) 반영 — 정보 집합 확장이라 별도 등록 ② PIT 재보정(베타 변환) ③ 1일 외 5 · 20일 지평 분리"]

    sections = [
        {"type": "summary", "emoji": "\U0001F4CC", "body": head},
        {"type": "bullet", "heading": "가설 — 사전등록 3건(측정 전 고정)", "emoji": "\U0001F9EA", "items": hyps},
        {"type": "bullet", "heading": "설계 · 판정 기준", "emoji": "\U0001F4D0", "items": design},
        {"type": "bullet", "heading": "기준선 — 운영 P3 의 예측 성능", "emoji": "\U0001F4CF", "items": base},
        {"type": "bullet", "heading": "판정 — OOS(2023-01 ~)", "emoji": "\U0001F3AF", "items": verdict},
        {"type": "bullet", "heading": "위기 구간 · 하락 사건", "emoji": "\U0001F32A️", "items": cr},
        {"type": "bullet", "heading": "운영 상태 · 다음", "emoji": "➡️", "items": ops},
    ]
    charts = {
        "① 예측 분포 보정 — PIT 히스토그램 · 왼꼬리 분위 적중(IS · OOS)": "charts/fig1_pit_coverage.png",
        "② 점수 개선 — 도전 vs P3(HAC 95% 구간) · 누적 로그 점수 차이": "charts/fig2_score_gain.png",
        "③ 예측 vs 실현 — OOS 일별 수익과 VaR 1% · 5% 위반": "charts/fig3_oos_var.png",
        "④ 위기 구간 확대 — 예측 표준편차 vs 실현": "charts/fig4_crisis_zoom.png",
        "⑤ 하락 사건 예측 — 다음날 ≤ −3% · ≤ −5% 보정 · ROC(OOS)": "charts/fig5_events.png",
    }
    msg = {"title": "[위험 예측 연구] K200 일간 위험 브리핑 — 정확도 개선 1차: 기준선 · 가설 3건 · OOS 판정",
           "sections": sections, "charts": charts,
           "footer": "산출물: 04_Research/01_reports/k200_risk_accuracy_20261113 (README · prereg · output · charts)",
           "push": True}
    C.write_json(C.OUT / "report_message.json", msg)
    print(json.dumps(msg, ensure_ascii=False, indent=1)[:6000])


if __name__ == "__main__":
    main()
