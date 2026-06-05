## Scout: 12 S0 Hypotheses Allocation (manual, no sg_init dependency)
cat("=== Scout: 12 S0 Hypotheses Allocation ===\n")

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
source(file.path(PROJECT_ROOT, "02_Infrastructure/config.R"))
library(jsonlite)

SG_CACHE <- file.path(PROJECT_ROOT, ".cache", "stage_gate")
dir.create(SG_CACHE, recursive = TRUE, showWarnings = FALSE)

manual_sg_init <- function(factor_id, strategy_id) {
  tracker <- list(
    factor_id = factor_id,
    strategy_id = strategy_id,
    current_stage = "S0_pending",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    stage_log = list(
      S0 = list(status = "pending", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S1 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S2 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S3 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S4 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S5 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL),
      S6 = list(status = "blocked", artifact = NULL, completed_at = NULL, completed_by = NULL)
    )
  )
  tracker_path <- file.path(SG_CACHE, paste0(factor_id, "_tracker.json"))
  write_json(tracker, tracker_path, auto_unbox = TRUE, pretty = TRUE)
  cat(sprintf("  [sg_init] %s -> %s\n", factor_id, strategy_id))
}

hypotheses <- list(
  list(slug="kurtosis_defense", fid="D44_Kurtosis", icir=0.910, pct=0.86,
       hyp="Return kurtosis low stocks outperform. Tail risk undercompensation.",
       rat="Behavioral: investors underweight kurtosis risk (Kahneman-Tversky). Dittmar(2002) nonlinear pricing kernel.",
       src="Dittmar 2002; Conrad et al. 2013", pa="Novel",
       eo="D01_IdioVol partial corr expected. ICIR 0.910 strongest in Defense."),
  list(slug="beta_persistence", fid="D33_Beta_Persistence", icir=0.645, pct=0.78,
       hyp="Stable beta stocks outperform. Predictable risk attracts institutional demand.",
       rat="Structural: institutions use beta in VaR. Unstable beta = model uncertainty = avoidance.",
       src="Adrian & Brunnermeier 2016; Bollerslev et al. 2018", pa="Novel",
       eo="D27_Beta_Stability high corr. Orthogonal to D02_Beta (level vs stability)."),
  list(slug="rogers_satchell_vol", fid="D39_RogersSatchell_Vol", icir=0.657, pct=0.69,
       hyp="OHLC RS vol low stocks outperform. More efficient vol estimator for low-vol anomaly.",
       rat="Risk premium + measurement: RS uses OHLC range, drift-adjusted. Rogers-Satchell(1991).",
       src="Rogers & Satchell 1991; Ang et al. 2006", pa="Variant",
       eo="D01_IdioVol high corr expected (0.6+). OHLC differentiates."),
  list(slug="ulcer_index", fid="D51_Ulcer_Index", icir=0.602, pct=0.67,
       hyp="Low Ulcer Index stocks outperform. Captures DD duration+depth.",
       rat="Behavioral: loss aversion intensified by DD duration. Martin(1987).",
       src="Martin 1987; Eling & Schuhmacher 2007", pa="Novel",
       eo="D50_MaxDrawdown partial corr. UI adds duration."),
  list(slug="vol_ret_asymmetry", fid="L44_Vol_Ret_Asymmetry", icir=-1.082, pct=0.17,
       hyp="Low vol-ret asymmetry outperform. Less leverage effect = lower info asymmetry. ICIR -1.082 strongest overall.",
       rat="Info asymmetry: high down-vol surge = informed selling. Chordia(2001).",
       src="Chordia et al. 2001; Gervais et al. 2001", pa="Novel",
       eo="L32_Ret_Vol_Corr similar concept. L44=directional, L32=symmetric."),
  list(slug="vol_variance_ratio", fid="L13_Vol_Variance_Ratio", icir=0.915, pct=0.78,
       hyp="High volume VR outperform. Mean-reverting volume = stable liquidity.",
       rat="Liquidity premium: VR>1 = structural liquidity. Lo-MacKinlay(1988) applied to volume.",
       src="Lo & MacKinlay 1988; Hasbrouck 2009", pa="Novel",
       eo="L02_Turnover, L05_DolVol partial corr. VR=structure not level."),
  list(slug="turnover_vol", fid="L16_Turnover_Vol", icir=0.729, pct=0.72,
       hyp="Low turnover vol outperform. Stable trading interest vs speculation.",
       rat="Adverse selection: erratic turnover = speculation. Scheinkman-Xiong(2003).",
       src="Scheinkman & Xiong 2003; Barber & Odean 2008", pa="Novel",
       eo="L02_Turnover(level) weak corr. L16=variance = orthogonal."),
  list(slug="vol_spike_ratio", fid="L34_Vol_Spike_Ratio", icir=0.704, pct=0.69,
       hyp="Low vol spike ratio outperform. Fewer info events = less adverse selection.",
       rat="Adverse selection: spikes = informed trading. Kyle(1985). Easley-OHara(2004).",
       src="Kyle 1985; Easley & OHara 2004", pa="Novel",
       eo="L31_Vol_Concentration similar. L34=frequency, L31=concentration."),
  list(slug="ncskew_crash", fid="R13_NCSKEW", icir=-1.005, pct=0.14,
       hyp="Low NCSKEW outperform. Less crash risk buildup. ICIR -1.005 (86% consistent).",
       rat="Chen-Hong-Stein(2001): mgmt hoards bad news -> positive skew -> crash.",
       src="Chen Hong & Stein 2001; Harvey & Siddique 2000", pa="Novel",
       eo="D43_Skewness related. NCSKEW is crash-specific."),
  list(slug="idio_risk_premium", fid="R12_Idiosyncratic_Risk", icir=0.582, pct=0.75,
       hyp="High idio risk outperform in Korea. Positive premium from under-diversified retail.",
       rat="Market imperfection: Korean high retail. Fu(2009) conditional idio vol.",
       src="Fu 2009; Malkiel & Xu 2002", pa="Variant",
       eo="D01_IdioVol high corr. R12=regression decomposition differentiates."),
  list(slug="cvar99_tail", fid="R04_CVaR_99", icir=-0.500, pct=0.31,
       hyp="Low CVaR(99%) outperform. Coherent risk measure captures full tail.",
       rat="Artzner(1999) coherent measure. CVaR=expected shortfall. Low tail = crisis safe.",
       src="Artzner et al. 1999; Agarwal & Naik 2004", pa="Novel",
       eo="D47_CVaR_5pct related. 99% threshold = extreme tail focus."),
  list(slug="coskewness_risk", fid="R09_Coskewness", icir=-0.440, pct=0.31,
       hyp="Low coskewness outperform. Less portfolio negative skew contribution = hedge value.",
       rat="Harvey-Siddique(2000) 3-moment CAPM. Coskewness = non-diversifiable.",
       src="Harvey & Siddique 2000; Kraus & Litzenberger 1976", pa="Variant",
       eo="R10_Cokurtosis(used) analog. 3rd vs 4th co-moment.")
)

cat(sprintf("[Scout] %d hypotheses. Allocating...\n\n", length(hypotheses)))

results <- list()
for (h in hypotheses) {
  strat_id <- allocate_str(h$slug)
  art_dir <- file.path(PROJECT_ROOT, "04_Research/strategies", strat_id, "stage_artifacts")
  dir.create(art_dir, recursive = TRUE, showWarnings = FALSE)
  manual_sg_init(h$fid, strat_id)

  s0 <- list(
    factor_id = h$fid, strategy_id = strat_id,
    hypothesis = h$hyp, economic_rationale = h$rat,
    prior_art = h$pa, source_reference = h$src,
    expected_orthogonality = h$eo,
    overlay = "none",
    overlay_note = "S0/S1 pure factor only. DD/VT/Regime at S5.",
    icir_3y = h$icir, pct_positive_3y = h$pct,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    created_by = "scout_v5.0"
  )
  s0_path <- file.path(art_dir, sprintf("s0_record_%s.json", h$fid))
  write_json(s0, s0_path, auto_unbox = TRUE, pretty = TRUE)
  results[[length(results)+1]] <- list(sid=strat_id, fid=h$fid, icir=h$icir)
  cat(sprintf("  [OK] %s | %s | ICIR %.3f\n", strat_id, h$fid, h$icir))
}

cat(sprintf("\n[Scout] === %d S0 records created ===\n", length(results)))
