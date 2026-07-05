# emit_package.R — WT-D20260706_005 alpha_package.json + alpha_scores.parquet + alpha_validation.json
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(1L)
PR   <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(PR, "stage_artifacts/high52_anchoring_wt005")
MB   <- file.path(PR, "qepm/mailbox/worktask/WT-D20260706_005")
SA   <- file.path(PR, "stage_artifacts/WT_D20260706_005")
dir.create(SA, showWarnings=FALSE, recursive=TRUE)

res <- fromJSON(file.path(OUT, "high52_result.json"))
scores <- as.data.table(read_parquet(file.path(OUT, "high52_scores.parquet")))
scores[, Date := as.Date(Date)]

# alpha_vector = latest cross-section cross-sectional z-score of pr52 (direction: higher pr52 -> higher alpha)
last_d <- max(scores$Date)
xs <- scores[Date == last_d & is.finite(pr52)]
mu <- mean(xs$pr52); sdv <- sd(xs$pr52)
xs[, z := (pr52 - mu)/sdv]
xs[, z := pmax(pmin(z, 3), -3)]  # winsor 3std
alpha_vec <- setNames(as.list(round(xs$z * 0.01, 5)), xs$Ticker)  # scaled to ~active-return units
# confidence: coverage + stability heuristic; uniform-ish, higher for mid-range (non-extreme) names
xs[, conf := round(pmax(0.2, pmin(0.9, 0.6 - 0.1*abs(z))), 3)]
conf_vec <- setNames(as.list(xs$conf), xs$Ticker)

# alpha_scores.parquet (full panel for downstream)
alpha_scores <- scores[, .(Date, Ticker, pr52, mcap_rank, tier)]
write_parquet(alpha_scores, file.path(SA, "alpha_scores.parquet"))

ct <- res$canonical_top25
tt <- res$cap_tier_longshort
alpha_package <- list(
  task_id = "WT-D20260706_005",
  as_of_date = "2026-07-06",
  forecast_horizon = "1M",
  wt_type = "discovery",
  verdict = "VALIDATED_NEGATIVE",
  escapes_cap_tier_trap_in_mega = FALSE,
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260706_005/alpha_scores.parquet",
  selection_objective = "rank_ic",
  factor_specs = list(list(
    factor_family = "Anchoring/Behavioral (price-level)",
    proxy = "52wk-high proximity (George-Hwang 2004)",
    formula = "Close_t / max(High over trailing 252 trading days ending t)",
    lag_rule = "price t-1 close; high over trailing 252d ending t (formation-date PIT); liq t-1 ADV",
    winsorization = "3std",
    neutralization = "none (raw cross-sectional; cap-tier decomposed separately)",
    economic_rationale = "Behavioral anchoring: investors reluctant to bid above the 52wk-high anchor -> underreact to good news -> near-high stocks keep rising (George-Hwang 2004: subsumes JT momentum). DISTINCT from return-continuation (xsec corr vs mom12-1 = 0.427).",
    weight_theta = 1.0,
    references = list("George & Hwang 2004 JF", "Jegadeesh-Titman 1993 (subsumed reference)"),
    redundancy_cluster_id = "price_momentum_family (distinct sub-cluster: level-anchoring, xsec_corr_to_mom121=0.427)",
    source = "new_designed"
  )),
  diagnostics = list(
    metric_type = "canonical_screen",
    n_months = ct$n_months,
    rank_ic = ct$rank_ic,
    icir = ct$icir,
    harvey_t_stat = ct$harvey_t_rankic,
    rank_ic_post2017 = ct$rank_ic_post2017,
    portfolio_alpha_t_nw_full = ct$port_t_nw_full,
    portfolio_alpha_t_nw_pre2017 = ct$port_t_pre2017,
    portfolio_alpha_t_nw_post2017 = ct$port_t_post2017,
    information_ratio = ct$information_ratio,
    net_sr = ct$net_sr,
    turnover_proxy = ct$turnover_annual,
    oos_retention = ct$oos_retention,
    oos_splits = ct$oos_splits
  ),
  cap_tier_escape_test = list(
    note = "Long-short (pr52 hi-half minus lo-half) within cap tier; NW lag-3 t. Escape question: mega post-2017 edge?",
    mega_ls_t_full = tt$mega$ls_t_full,
    mega_ls_t_post2017 = tt$mega$ls_t_post2017,
    mega_ls_t_post2020 = tt$mega$ls_t_post2020,
    mega_top5_longonly_port_t_full = res$mega_top5_longonly$port_t_full,
    mega_top5_longonly_port_t_post2017 = res$mega_top5_longonly$port_t_post2017,
    mid_ls_t_full = tt$mid$ls_t_full, mid_ls_t_post2017 = tt$mid$ls_t_post2017,
    small_ls_t_full = tt$small$ls_t_full, small_ls_t_post2017 = tt$small$ls_t_post2017,
    parallel_session_megatier_momrev_t = 0.59,
    conclusion = "pr52 mega LS t_full 0.68 / post2017 0.45 ~ parallel session's 0.59 (mom/rev/eff) -> DOES NOT ESCAPE. mega top-5 long-only port_t -1.06. Only post2020 (AI-run window) shows modest life, still <t=2 and does not translate to long-only book."
  ),
  closet_index_guard = res$closet_guard,
  pit_lag1_variant = res$pit_lag1_variant,
  vs_momentum121_xsec_corr = res$vs_momentum121_xsec_corr,
  graduation_assessment = list(
    port_t_hard_2p95 = ct$port_t_nw_full, port_t_pass = FALSE,
    oos_retention_hard_0p7 = ct$oos_retention, oos_pass = FALSE,
    rank_ic_advisory_0p04 = ct$rank_ic, rank_ic_pass = FALSE,
    graduation_candidate = FALSE,
    screen_route = "DPL_FEATURE (weak; mostly regime-local post2020)"
  ),
  challenge_flags = list(
    list(id="RF-A3", severity="INFO", note="post2017 canonical PORT_t -1.04 << pre2017 +1.31 = transition-wall decay, not recent-inflation. No RF-A3 recent>overall inflation."),
    list(id="ESCAPE-TEST", severity="HIGH_INFO", note="Does NOT escape cap-tier trap in mega (mega LS t_full 0.68 ~ known-dead 0.59). Confirms trap signal-universal in mega, now extended to distinct anchoring family."),
    list(id="PIT-CLEAN", severity="INFO", note="lag1 variant full 0.391 vs base -0.041 (leak would invert) -> no lookahead. C1/C2/C10 satisfied.")
  ),
  challenge_note_ref = "stage_artifacts/high52_anchoring_wt005/challenge_note.md",
  method_shopping_log = list(candidates_tried = 1, method_log = list(
    list(name="pr52_George_Hwang", rank_ic=ct$rank_ic, selected=TRUE)))
)
write_json(alpha_package, file.path(MB, "alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
write_json(alpha_package, file.path(SA, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat(sprintf("[emit] alpha_package.json -> %s\n", file.path(MB, "alpha_package.json")))
cat(sprintf("[emit] alpha_scores.parquet rows=%d, alpha_validation.json -> %s\n", nrow(alpha_scores), SA))
cat(sprintf("[emit] alpha_vector size=%d (latest xsec %s)\n", length(alpha_vec), as.character(last_d)))
