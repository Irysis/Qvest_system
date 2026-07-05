import pandas as pd, numpy as np, json, os
OUT = "stage_artifacts/WT-D20260705_004"
fc = pd.read_parquet(OUT + "/alpha_scores.parquet")
res = json.load(open(OUT + "/variant_results.json"))
meta = res["_meta"]

asof_ym = sorted(fc.ym.unique())[-1]
last = fc[fc.ym == asof_ym].copy()
last["sig_norm"] = (last.sigma_hat - last.sigma_hat.min()) / (last.sigma_hat.max() - last.sigma_hat.min() + 1e-12)
last["conf"] = (1 - last["sig_norm"]).clip(0, 1)
top = last.sort_values("mu_hat", ascending=False).head(40)
alpha_vector = {r.Ticker: round(float(r.mu_hat), 6) for r in top.itertuples()}
conf_vector = {r.Ticker: round(float(r.conf), 4) for r in top.itertuples()}

def g(v, seg, k):
    x = res[v].get(seg)
    return None if x is None else x.get(k)

variant_table = []
for v, label in [("A_baseline", "A: point mu_hat top-25 (baseline)"),
                 ("B_risk_adj", "B: mu_hat/sigma_hat top-25 (risk-adjusted)"),
                 ("C_confband", "C: conformal-lb>0 then top-25 (confidence-band)"),
                 ("D_shrunk", "D: mu_hat*(1-lambda*sigma_norm) top-25 (uncertainty-shrunk)")]:
    variant_table.append({
        "variant": v, "label": label, "metric_type": "canonical_screen",
        "full_port_t_nw3": g(v, "full", "portfolio_alpha_t_nw_lag3"),
        "full_IR": g(v, "full", "information_ratio"),
        "full_net_sr": g(v, "full", "net_sr"),
        "full_turnover_annual": g(v, "full", "turnover_annual"),
        "full_n_months": g(v, "full", "n_months"),
        "recent2017_port_t_nw3": g(v, "recent2017", "portfolio_alpha_t_nw_lag3"),
        "recent2017_n_months": g(v, "recent2017", "n_months"),
        "rank_ic_full": res[v]["rank_ic_full"]["ic"]})

A = res["A_baseline"]["full"]["portfolio_alpha_t_nw_lag3"]
BD = [res["B_risk_adj"]["full"]["portfolio_alpha_t_nw_lag3"], res["D_shrunk"]["full"]["portfolio_alpha_t_nw_lag3"]]
delta_full = round(max(BD) - A, 4)
Ar = res["A_baseline"]["recent2017"]["portfolio_alpha_t_nw_lag3"]
BDr = [res["B_risk_adj"]["recent2017"]["portfolio_alpha_t_nw_lag3"], res["D_shrunk"]["recent2017"]["portfolio_alpha_t_nw_lag3"]]
delta_recent = round(max(BDr) - Ar, 4)

pkg = {
 "task_id": "WT-D20260705_004", "wt_type": "discovery",
 "as_of_date": "2026-04-30", "as_of_forecast_month": asof_ym, "forecast_horizon": "1M",
 "selection_objective": "rank_ic",
 "alpha_mean_source": "score_eff (established multi-factor composite, rank-IC 0.042 / ICIR 0.34 / 256m)",
 "method": "NGBoost(Normal) probabilistic forecast + MAPIE SplitConformal (expanding-window PIT) over established score_eff mean; 4 selection/sizing variants on identical mu_hat mean",
 "alpha_vector": alpha_vector, "confidence_vector": conf_vector,
 "signal_matrix_ref": "stage_artifacts/WT-D20260705_004/alpha_scores.parquet",
 "forecast_uncertainty_note": "confidence_vector = 1 - cross-sectional-normalized sigma_hat (NGBoost predictive std). forecast_uncertainty is NOT return covariance Sigma (risk agent). weight undecided (optimizer).",
 "factor_specs": [
   {"factor_family": "Composite (established)", "proxy": "score_eff",
    "formula": "pre-registered multi-factor composite (value/quality/momentum/flow/defense)",
    "lag_rule": "monthly sig_date; fundamentals quarterly 45d", "winsorization": "cross-sectional z",
    "neutralization": "cross-sectional demean (active target)",
    "economic_rationale": "established composite with real cross-sectional IC (0.042); reused as alpha_hat MEAN, no new signal per WT mandate (transition-wall probe not signal hunt)",
    "weight_theta": 1.0, "references": ["Harvey-Liu-Zhu 2016", "internal score_eff registry"]},
   {"factor_family": "ForecastUncertainty (new dimension)", "proxy": "sigma_hat (NGBoost Normal.scale)",
    "formula": "NGBoost natural-gradient predictive std, expanding window train months[:t]",
    "lag_rule": "PIT expanding, 60m burn-in, retrain/6m", "winsorization": "n/a", "neutralization": "n/a",
    "economic_rationale": "per-name predictive uncertainty; calibrated (within-month corr(sigma_hat,|realized active|)=+0.207). NOT covariance. research_philosophy #3 first operationalization",
    "weight_theta": 0.0, "references": ["Duan NGBoost 2020", "Angelopoulos-Bates conformal 2023", "Liao-Ma-Neuhierl-Schilling 2025 RFS"]}],
 "diagnostics": {
   "rank_ic": res["A_baseline"]["rank_ic_full"]["ic"], "icir": res["A_baseline"]["rank_ic_full"]["icir"],
   "harvey_t_stat": res["A_baseline"]["rank_ic_full"]["t"],
   "rank_ic_recent2017": res["A_baseline"]["rank_ic_recent2017"]["ic"],
   "portfolio_alpha_t_nw_lag3_baseline": A, "sigma_calibration_corr": 0.2074,
   "sigma_calibration_note": "within-month spearman corr(sigma_hat, |realized active return|); positive = calibrated",
   "lookahead_check": "PASS - PIT mu_hat rank-IC 0.031 <= score_eff mean IC 0.036 (no inflation); train window strictly months[:t]",
   "n_forecast_months": meta["n_forecast_months"],
   "turnover_annual_baseline": res["A_baseline"]["full"]["turnover_annual"]},
 "variant_comparison": variant_table,
 "delta_port_t": {
   "definition": "best like-for-like uncertainty variant (B/D, 196/112 months) minus A. C EXCLUDED (degenerate: 0/196 months had >=25 conformal-eligible names).",
   "delta_full": delta_full, "delta_recent2017": delta_recent, "verdict": "FAIL",
   "verdict_detail": "delta_full=%s (<0), delta_recent=%s; no variant near 2.95 gate. Uncertainty-aware selection/sizing does NOT recover IC->PORT_t transition - neutral-to-harmful like-for-like. Transition wall robust to sizing/selection dimension." % (delta_full, delta_recent)},
 "challenge_flags": [
   {"id": "CF-1", "severity": "HIGH", "resolved": True,
    "flag": "Variant C (confidence-band) degenerate - 0/196 months formed >=25-name portfolio (conformal 1M-active 68% lower bound almost never >0). C positive PORT_t = conditional-sampling survivorship artifact, excluded from verdict."},
   {"id": "CF-2", "severity": "INFO", "resolved": True,
    "flag": "sigma_hat calibrated (+0.207 vs |realized active|) yet selection/sizing on it fails to beat baseline -> failure is transition wall itself, not sigma quality."},
   {"id": "CF-3", "severity": "INFO", "resolved": True,
    "flag": "single probabilistic estimator (NGBoost) + single conformal (MAPIE); low residual EV given calibrated-sigma failure."}],
 "method_shopping_log": {"alpha_agent": {"candidates_tried": 4, "parallel_exec": False, "method_log": [
   {"name": "A_baseline", "port_t_full": A, "selected": False},
   {"name": "B_risk_adj", "port_t_full": BD[0], "selected": False},
   {"name": "C_confband", "port_t_full": res["C_confband"]["full"]["portfolio_alpha_t_nw_lag3"], "selected": False, "note": "degenerate"},
   {"name": "D_shrunk", "port_t_full": BD[1], "selected": False}]}},
 "selection_type": "chain",
 "self_adversarial_challenge": "challenge_note.md - 4 concerns (2 HIGH: C survivorship ACCEPT, look-ahead REBUTTAL; 2 MEDIUM). no escalate trigger."}
json.dump(pkg, open("qepm/mailbox/worktask/WT-D20260705_004/alpha_package.json", "w"), indent=2, default=str)

val = {
 "task_id": "WT-D20260705_004", "as_of_date": "2026-04-30",
 "hypothesis": "uncertainty-aware selection/sizing recovers IC->PORT_t transition that point-ranking destroys",
 "verdict": "FAIL", "delta_port_t_full": delta_full, "delta_port_t_recent2017": delta_recent,
 "gate_2p95": "not approached by any variant (max full PORT_t 0.970 = baseline A)",
 "variant_results": res,
 "pit": {"lookahead": "PASS", "expanding_window": "train months[:t] strict",
         "sigma_calibration_corr": 0.2074, "mu_hat_ic_vs_score_eff_ic": "0.031 <= 0.036 (no inflation)"},
 "universe_comparison": {"note": "KR_top342 deployment envelope (phase0 panel, median 253 names/month). v2 KR_TOP500_FREEFLOAT not run - failure is dimensional (selection on calibrated sigma), not universe-restricted attenuation; v2 would not change verdict since sigma is already calibrated and selection is neutral-to-harmful."},
 "metric_type": "canonical_screen",
 "measurement": "canonical_screen_bt (build_benchmark_compare NW lag-3); no proxy hand-calc"}
json.dump(val, open(OUT + "/alpha_validation.json", "w"), indent=2, default=str)
print("WROTE alpha_package.json + alpha_validation.json")
print("as_of_forecast", asof_ym, "n_alpha", len(alpha_vector))
print("delta_full", delta_full, "delta_recent", delta_recent, "VERDICT FAIL")
