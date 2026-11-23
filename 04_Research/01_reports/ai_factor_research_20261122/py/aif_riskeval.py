"""aif_riskeval.py — 위험 평가 모형 3부(첫 조각): 2부의 예측을 편향 통계로 검증한다 — 팩터 · 고유팩터 · 최적화한 팩터 포트폴리오 · 종목 고유수익.

편향 통계(USE4 방법론 노트 부록 A): b_t = 그 달의 실현 수익 ÷ 달 초의 예측 변동성 → 그 표준편차가 1 이면 예측이 맞다(1 보다 크면 위험을 낮게 예측).
  12개월 이동 편향 통계와 MRAD(|편향 − 1| 의 평균 · 완벽한 예측이어도 0.17 · 꼬리가 두꺼우면 0.19)를 낸다.
시험 넷(종목 포트폴리오 유형 — 무작위 액티브 · 팩터 기울기 · 최적화 스타일 — 과 비교 기준 둘 · 위험 평가 보고서는 다음 조각):
  factor  순수 팩터(시장 · 업종 · 스타일) — 예측 = 팩터 공분산의 대각
  eigen   고유팩터(조정 전 공분산의 고유벡터 포트폴리오 · 변동성이 작은 것부터) — 고유팩터 위험 조정이 고치려는 대상(USE4 그림 4.1 · 4.4)
  optim   무작위 알파 100개의 최소위험 팩터 포트폴리오(알파 노출 1) — 최적화한 포트폴리오의 위험 과소예측(USE4 그림 4.2 · 4.5)
  spec    종목 고유수익(추정 유니버스) — 시계열 → 혼합 → 축소 → 국면 조정의 단계마다 · 고유 변동성 10분위별(USE4 그림 5.1 · 5.2)
조정을 하나씩 켠 판을 나란히 낸다: 조정 전(F0) → 고유팩터 조정(Feig) → 국면 조정(λ_F² × Feig).
달의 실현 값 = 보유월 안 일별 팩터 수익 · 고유수익의 합(회귀의 산출물이고 포트폴리오 성과가 아니다) · 예측 = 하루 분산 × 그 달의 거래일 수.
표본 안만 낸다(보유월이 설정 measure.is_end 안에서 끝난 달 · 스타일이 모두 공분산에 든 뒤) — 설정을 고르는 데 쓰는 표이기 때문이다.
산출: results/followup/risk/bias_is.json · bias_factor_is.csv · bias_spec_decile_is.csv + stage_summary_nl_risk.json(텔레그램 결과 통)
실행: python py/aif_riskeval.py     (감시 셸: ops/aif_run.py --track followup --job nl_risk --stage nl_risk)
"""
import csv
import os
import sys
import warnings

import numpy as np

import aif_common as ac
import aif_riskcov as rc
import aif_riskmodel as rm

STAGE, PART_FROM, PART_TO = "nl_risk", 0.75, 0.85
WIN = 12                                    # 이동 편향 통계의 창(달 — USE4 부록 A)
MIN_T = 60                                  # 전 기간 편향 통계를 내는 데 필요한 달 수
N_ALPHA = 100                               # 무작위 알파의 수(USE4 4.2절의 실험)
SEED = 20261123
LEVELS = ("raw", "eig", "eig_vra")          # 조정 전 · 고유팩터 조정 · + 국면 조정
SPEC_LEVELS = ("ts", "blend", "sh", "sh_vra", "sh_vra_sqrt")
SPEC_KO = {"ts": "시계열", "blend": "구조 모형 혼합", "sh": "베이즈 축소", "sh_vra": "축소 + 국면 조정(시총 가중)", "sh_vra_sqrt": "축소 + 국면 조정(√시총 가중)"}


def rolling_bias(b):
    """b [달 × 대상](표준화 수익 · 결측 NaN) → 12개월 이동 편향 통계 [달 − 11 × 대상](창 안 값이 모두 있을 때만)."""
    T, P = b.shape
    out = np.full((max(T - WIN + 1, 0), P), np.nan)
    for t in range(T - WIN + 1):
        w = b[t:t + WIN]
        ok = np.isfinite(w).all(0)
        out[t, ok] = w[:, ok].std(axis=0, ddof=1)
    return out


def summarize(b, weights=None):
    """편향 통계 요약 — 이동 편향의 평균 · MRAD · 5% / 95% 와 전 기간 편향의 평균. weights [달 × 대상] 을 주면 이동 편향을 창 첫 달의 가중으로 평균한 값도 낸다."""
    with warnings.catch_warnings(), np.errstate(all="ignore"):
        warnings.simplefilter("ignore", RuntimeWarning)
        rb = rolling_bias(b)
        n = np.isfinite(b).sum(0)
        full = np.where(n >= MIN_T, np.nanstd(b, axis=0, ddof=1), np.nan)
        o = {"n_targets": int(np.isfinite(rb).any(0).sum()), "windows": int(len(rb)), "roll_mean": float(np.nanmean(rb)), "mrad": float(np.nanmean(np.abs(rb - 1.0))),
             "roll_p05": float(np.nanpercentile(rb, 5)), "roll_p95": float(np.nanpercentile(rb, 95)), "full_mean": float(np.nanmean(full)),
             "full_p05": float(np.nanpercentile(full, 5)) if np.isfinite(full).any() else np.nan, "full_p95": float(np.nanpercentile(full, 95)) if np.isfinite(full).any() else np.nan}
        if weights is not None:
            w = np.where(np.isfinite(rb), weights[: len(rb)], 0.0)
            o["roll_mean_weighted"] = float(np.nansum(w * np.nan_to_num(rb)) / w.sum())
    return o


def month_sum(A, a, b):
    """일별 값 [날 × 대상]의 보유월(a ~ b) 합 — 그 달에 하루라도 없으면 결측."""
    w = np.asarray(A[a:b + 1], dtype=np.float64)
    return np.where(np.isfinite(w).all(0), w.sum(0), np.nan)


def evaluate(f, model, variant, is_end, prog=None):
    I = rc.Inputs(f, model)
    with np.load(rc.RK("cov_%s_%s.npz" % (model, variant)), allow_pickle=True) as z:
        C = {k: z[k] for k in z.files}
    n_sec, P, N = I.n_sec, I.FD.shape[1], I.U.shape[1]
    ok = np.array([bool(f.hold_ok[i]) and f.hold_b[i] < f.nd and f.dates[min(f.hold_b[i], f.nd - 1)] <= is_end and bool(C["present"][i][0]) and bool(C["present"][i][1 + n_sec:].all())
                   for i in range(I.S)])
    months = np.nonzero(ok)[0]
    if len(months) and not np.array_equal(months, np.arange(months[0], months[-1] + 1)):      # 이동 창은 이어진 달이어야 한다 — 가운데가 빈 달은 그 뒤부터 쓴다
        gap = np.nonzero(np.diff(months) > 1)[0][-1]
        months = months[gap + 1:]
    T = len(months)
    rng = np.random.default_rng(SEED)
    alphas = rng.standard_normal((N_ALPHA, P))                                               # 팩터 단위 무작위 알파(시간 불변)
    bF = {lv: np.full((T, P), np.nan) for lv in LEVELS}
    bE = {lv: np.full((T, P), np.nan) for lv in LEVELS}
    bO = {lv: np.full((T, N_ALPHA), np.nan) for lv in LEVELS}
    bS = {lv: np.full((T, N), np.nan, np.float32) for lv in SPEC_LEVELS}
    capw = np.zeros((T, N))
    dec = np.full((T, N), -1, np.int8)
    for t, i in enumerate(months):
        a, b = int(f.hold_a[i]), int(f.hold_b[i])
        nd = b - a + 1
        pres = C["present"][i]
        rf = month_sum(I.FD, a, b)
        lam = float(C["lamF"][i])
        F = {"raw": C["F0"][i][np.ix_(pres, pres)].astype(np.float64), "eig": C["Feig"][i][np.ix_(pres, pres)].astype(np.float64)}
        scale = {"raw": 1.0, "eig": 1.0, "eig_vra": lam * lam}
        r = rf[pres]
        d0, U0 = np.linalg.eigh(F["raw"])
        K = int(pres.sum())
        v = C["v_eig"][i][:K].astype(np.float64)
        re = r @ U0                                                                           # 고유팩터 포트폴리오의 그 달 수익
        for lv in LEVELS:
            Fx = F["raw"] if lv == "raw" else F["eig"]
            with np.errstate(all="ignore"):
                bF[lv][t, pres] = r / np.sqrt(np.diag(Fx) * scale[lv] * nd)
                bE[lv][t, :K] = re / np.sqrt(d0 * (1.0 if lv == "raw" else v * v) * scale[lv] * nd)
                if np.isfinite(r).all():
                    Fi = np.linalg.inv(Fx)
                    al = alphas[:, pres]
                    q = np.einsum("ji,ik,jk->j", al, Fi, al)                                  # α′F⁻¹α — 최소위험 포트폴리오의 예측 분산 = 1 ÷ 이 값
                    bO[lv][t] = ((al @ Fi) @ r / q) / np.sqrt(scale[lv] * nd / q)
        us = month_sum(I.U, a, b)
        est = I.EST[i]
        sq = np.sqrt(nd)
        with np.errstate(all="ignore"):
            for lv, sig in (("ts", C["sp_ts"][i]), ("blend", C["sp_blend"][i]), ("sh", C["sp_sh"][i]), ("sh_vra", C["sp_sh"][i] * C["lamS"][i]), ("sh_vra_sqrt", C["sp_sh"][i] * C["lamS_sqrt"][i])):
                bS[lv][t] = np.where(est & (sig > 0), us / (sig.astype(np.float64) * sq), np.nan)
        capw[t] = np.where(est, I.CAP[i], 0.0)
        s0 = C["sp_blend"][i].astype(np.float64)
        k = est & np.isfinite(s0)
        if k.sum() >= 50:                                                                     # 고유 변동성 10분위(혼합 뒤 예측 — 축소 전 · 뒤를 같은 분위에서 견준다)
            dec[t, k] = np.searchsorted(np.quantile(s0[k], np.arange(1, 10) / 10), s0[k], side="right")
        if prog and ((t + 1) % 40 == 0 or t + 1 == T):
            prog(t + 1, T)
    grp ={"market": np.arange(P) == 0, "industry": (np.arange(P) >= 1) & (np.arange(P) <= n_sec), "style": np.arange(P) > n_sec}
    res = {"months": T, "first": str(f.sig_dates[months[0]]) if T else None, "last": str(f.sig_dates[months[-1]]) if T else None, "factor": {}, "eigen": {}, "optim": {}, "spec": {}, "spec_decile": {}}
    for lv in LEVELS:
        res["factor"][lv] = {g: summarize(bF[lv][:, m]) for g, m in grp.items()}
        res["factor"][lv]["all"] = summarize(bF[lv])
        Kmax = int(np.isfinite(bE[lv]).any(0).sum())
        third = max(Kmax // 3, 1)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", RuntimeWarning)
            full = np.nanstd(bE[lv][:, :Kmax], axis=0, ddof=1)
        res["eigen"][lv] = {"n": Kmax, "full_smallest_third": float(np.mean(full[:third])), "full_middle_third": float(np.mean(full[third:Kmax - third])),
                            "full_largest_third": float(np.mean(full[Kmax - third:])), "full_smallest": float(full[0]), "full_all": [float(x) for x in full]}
        res["optim"][lv] = summarize(bO[lv])
    for lv in SPEC_LEVELS:
        res["spec"][lv] = summarize(bS[lv].astype(np.float64), weights=capw)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)
        for lv in ("blend", "sh"):
            res["spec_decile"][lv] = [float(np.nanstd(bS[lv][dec == d_].astype(np.float64), ddof=1)) for d_ in range(10)]
    fac_full = {lv: np.where(np.isfinite(bF[lv]).sum(0) >= MIN_T, np.nanstd(bF[lv], axis=0, ddof=1), np.nan) for lv in LEVELS}
    return res, I.factors, fac_full


def main():
    if ac.track() != "followup":
        raise RuntimeError("[aif] 2단계 줄로만 띄운다 — ops/aif_run.py --track followup 또는 AIF_TRACK=followup")
    ac.low_priority()
    f = ac.Frame()
    is_end = np.datetime64(ac.cfg()["measure"]["is_end"], "D")
    ac.stage_begin(STAGE, 100, "진행(%)", PART_FROM, PART_TO)
    out, rows = {}, []
    jobs = [(m, v) for m in rm.MODELS for v in rc.VARIANTS]
    for j, (m, v) in enumerate(jobs):
        res, factors, fac_full = evaluate(f, m, v, is_end, lambda d_, t_, j=j, m=m, v=v: ac.stage_unit(
            int(round(100 * (j + d_ / max(t_, 1)) / len(jobs))), "%s(%s) 달 %d / %d" % (rm.MODEL_KO[m], rc.VARIANT_KO[v], d_, t_)))
        out["%s:%s" % (m, v)] = res
        for p, nm in enumerate(factors):
            rows.append({"model": m, "variant": v, "factor": nm, **{"bias_" + lv: ("" if not np.isfinite(fac_full[lv][p]) else round(float(fac_full[lv][p]), 4)) for lv in LEVELS}})
        ac.log("%s:%s — 달 %d(%s~%s) · 팩터 편향(이동 평균 · MRAD) 조정 전 %.2f · %.2f → 최종 %.2f · %.2f · 최적화 포트폴리오 %.2f → %.2f · 고유 %.2f → %.2f", m, v, res["months"],
               (res["first"] or "")[:7], (res["last"] or "")[:7], res["factor"]["raw"]["all"]["roll_mean"], res["factor"]["raw"]["all"]["mrad"],
               res["factor"]["eig_vra"]["all"]["roll_mean"], res["factor"]["eig_vra"]["all"]["mrad"], res["optim"]["raw"]["full_mean"], res["optim"]["eig_vra"]["full_mean"],
               res["spec"]["ts"]["roll_mean"], res["spec"]["sh_vra"]["roll_mean"])
    rdir = ac.results("followup", "risk")
    os.makedirs(rdir, exist_ok=True)
    ac.write_json({"at": ac._now(), "is_end": str(is_end), "note": "표본 안 · 12개월 이동 편향 통계(roll_*) · 전 기간 편향 통계(full_*) · MRAD = |이동 편향 − 1| 의 평균", "results": out}, rdir + "/bias_is.json")

    def wcsv(path, rr):
        def w_(p):
            with open(p, "w", newline="", encoding="utf-8-sig") as fh:
                w = csv.DictWriter(fh, fieldnames=list(rr[0]))
                w.writeheader()
                w.writerows(rr)
        ac.write_atomic(path, w_)
    wcsv(rdir + "/bias_factor_is.csv", rows)
    wcsv(rdir + "/bias_spec_decile_is.csv", [{"model": k.split(":")[0], "variant": k.split(":")[1], "level": lv, **{"d%d" % (d_ + 1): round(x, 4) for d_, x in enumerate(r["spec_decile"][lv])}}
                                              for k, r in out.items() for lv in ("blend", "sh")])
    L, S_, cL = out["main:L"], out["main:S"], out.get("nlbeta:L")
    fm = lambda r, lv, g="all": "%.2f(MRAD %.2f)" % (r["factor"][lv][g]["roll_mean"], r["factor"][lv][g]["mrad"])     # noqa: E731
    lines = ["2부의 위험 예측을 편향 통계로 검증했습니다(표본 안 %s~%s · %d달 · 1 이면 예측이 맞고 1 보다 크면 위험을 낮게 본 것 · 완벽한 예측의 MRAD 는 0.17~0.19)" % (L["first"][:7], L["last"][:7], L["months"]),
             "순수 팩터(본 모형 · 안정형) — 12개월 이동 편향 평균: 조정 전 %s → 고유팩터 조정 %s → 국면 조정까지 %s" % (fm(L, "raw"), fm(L, "eig"), fm(L, "eig_vra")),
             "순수 팩터(본 모형 · 반응형) — 조정 전 %s → 국면 조정까지 %s" % (fm(S_, "raw"), fm(S_, "eig_vra")),
             "최적화한 팩터 포트폴리오(무작위 알파 %d개 · 안정형) — 편향: 조정 전 %.2f → 고유팩터 조정 %.2f → 국면 조정까지 %.2f" % (N_ALPHA, L["optim"]["raw"]["full_mean"], L["optim"]["eig"]["full_mean"], L["optim"]["eig_vra"]["full_mean"]),
             "고유팩터(안정형) — 변동성이 작은 3분의 1 의 편향: 조정 전 %.2f → 조정 뒤 %.2f · 큰 3분의 1: %.2f → %.2f" % (
                 L["eigen"]["raw"]["full_smallest_third"], L["eigen"]["eig"]["full_smallest_third"], L["eigen"]["raw"]["full_largest_third"], L["eigen"]["eig"]["full_largest_third"]),
             "종목 고유수익(추정 유니버스 · 안정형) — 이동 편향 평균(MRAD): " + " → ".join("%s %.2f(%.2f)" % (SPEC_KO[lv].split("(")[0].strip() if lv != "sh_vra_sqrt" else "√시총 가중 국면 조정", L["spec"][lv]["roll_mean"], L["spec"][lv]["mrad"]) for lv in SPEC_LEVELS),
             "고유 변동성 10분위별 편향(안정형 · 낮은 분위 → 높은 분위) — 축소 전 %.2f ~ %.2f · 축소 뒤 %.2f ~ %.2f" % (L["spec_decile"]["blend"][0], L["spec_decile"]["blend"][9], L["spec_decile"]["sh"][0], L["spec_decile"]["sh"][9])]
    if cL:
        lines.append("대조 판(비선형 베타 포함 · 안정형) — 순수 팩터 %s · 최적화 포트폴리오 %.2f · 스타일만 보면 본 모형 %s 대 대조 판 %s" % (
            fm(cL, "eig_vra"), cL["optim"]["eig_vra"]["full_mean"], fm(L, "eig_vra", "style"), fm(cL, "eig_vra", "style")))
    ac.write_json({"at": ac._now(), "title": "위험 평가 모형 3부(첫 조각) — 팩터 · 고유수익 단위의 편향 통계", "lines": lines, "charts": [], "chart_names": []}, ac.out("followup", "stage_summary_nl_risk.json"))
    for ln in lines:
        ac.log("%s", ln)
    ac.stage_unit(100, "3부 첫 조각 끝")
    ac.status_set(stage_state="done", detail="3부 첫 조각 끝 — 다음 작업 대기")
    return 0


if __name__ == "__main__":
    sys.exit(main())
