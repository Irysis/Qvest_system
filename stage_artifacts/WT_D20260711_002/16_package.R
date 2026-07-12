#==============================================================================
# WT-D20260711_002 Phase A — Step 16: assemble alpha_package + alpha_validation
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002")
MBX  <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260711_002")
ar   <- readRDS(file.path(OUT,"analysis_results.rds"))
tab  <- readRDS(file.path(OUT,"single_metric_canon.rds"))
adv  <- readRDS(file.path(OUT,"adversarial_results.rds"))
P    <- readRDS(file.path(OUT,"signal_panel.rds"))
famt <- ar$famtab

cf <- ar$canon_full; ci <- ar$canon_is; co <- ar$canon_oos
m1 <- tab[metric=="m1"]
getf <- function(x) if(is.null(x)||length(x)==0) NA else as.numeric(x)

# alpha_vector: latest-month clarity score (pre-registered primary = composite; higher=clearer=long)
last_ym <- max(P$ym)
Plast <- P[ym==last_ym]
alpha_vec <- as.list(setNames(round(Plast$score,4), Plast$Ticker))
conf_vec  <- as.list(setNames(round(pmin(1, pmax(0.2, 0.5 + 0.3*scale(Plast$age)[,1]*-1)),3), Plast$Ticker))

diagnostics <- list(
  canonical_port_t_nw_lag3 = round(getf(cf$portfolio_alpha_t_nw_lag3),3),   # PRIMARY composite (cap-w)
  canonical_port_t_pvalue  = round(getf(cf$portfolio_alpha_t_pvalue),4),
  canonical_n_months = getf(cf$n_months),
  canonical_ir = round(getf(cf$information_ratio),3),
  canonical_net_sr = round(getf(cf$net_sr),3),
  canonical_turnover_annual = round(getf(cf$turnover_annual),3),
  canonical_port_t_IS = round(getf(ci$portfolio_alpha_t_nw_lag3),3),
  canonical_port_t_OOS = round(getf(co$portfolio_alpha_t_nw_lag3),3),
  ew_universe_port_t = round(getf(cf$diag_ew_universe$portfolio_alpha_t_nw_lag3),3),
  ew_universe_post2017_t = round(getf(cf$diag_ew_universe$post2017_t_nw_lag3),3),
  captier_mega_wshare = round(getf(cf$diag_cap_tier$weight_share_avg$MEGA),4),
  captier_mid_wshare = round(getf(cf$diag_cap_tier$weight_share_avg$MID),4),
  captier_other_wshare = round(getf(cf$diag_cap_tier$weight_share_avg$OTHER),4),
  rank_ic_composite = round(famt[metric=="obfuscation_composite"]$mean_ic,5),
  icir_composite = round(famt[metric=="obfuscation_composite"]$icir,4),
  harvey_t_rankic_composite = round(famt[metric=="obfuscation_composite"]$harvey_t,3),
  # best single metric (m1 avg sentence length)
  best_single_metric = "m1_avg_sentence_len_chars",
  m1_canonical_port_t_capw = round(m1$port_t_full,3),
  m1_canonical_port_t_IS = round(m1$port_t_IS,3),
  m1_canonical_port_t_OOS = round(m1$port_t_OOS,3),
  m1_ew_universe_port_t = round(m1$ew_t_full,3),
  m1_ew_post2017_t = round(m1$ew_post2017,3),
  m1_rank_ic = round(famt[metric=="m1"]$mean_ic,5),
  m1_icir = round(famt[metric=="m1"]$icir,4),
  m1_harvey_t_rankic = round(famt[metric=="m1"]$harvey_t,3),
  m1_net_sr = round(m1$sr_full,3),
  m1_turnover_annual = round(m1$turn_full,3),
  m1_placebo_p = adv$m1$placebo_p,
  m1_size_partial_ic = round(adv$m1$size_partial,5),
  m1_size_cor_logsize = round(adv$m1$size_cor,3),
  m1_size_partial_harvey_t = round(adv$m1$size_t_part,3),
  m1_annual_lag12_harvey_t = round(adv$m1$lag12_t,3),
  composite_placebo_p = adv$composite$placebo_p,
  null_max_harvey_t = round(ar$null_max_t,3),
  convergence_composite_vs_llm = getf(ar$conv$composite_vs_llm_complexity),
  n_trials_family = 7L,
  selection_type = "chain"
)

alpha_package <- list(
  task_id = "WT-D20260711_002",
  as_of_date = "2026-07-11",
  forecast_horizon = "1M",
  metric_type = "canonical_screen",
  alpha_vector = alpha_vec,
  confidence_vector = conf_vec,
  signal_matrix_ref = "stage_artifacts/WT_D20260711_002/signal_panel.rds",
  factor_specs = list(list(
    factor_family = "Disclosure_Text_Readability",
    proxy = "obfuscation_composite (EW z of {avg_sentence_len, fog_kr, hanja_latin_density, log_section_len}); primary carrier = m1 avg_sentence_len_chars",
    formula = "score_long = -zscore(obfuscation); higher = clearer MD&A = long",
    lag_rule = "annual, active month AFTER rcept_dt, carry<=12m",
    winsorization = "cross-sectional z per month",
    neutralization = "none (Size-control tested post-hoc: m1 survives partial|logSize)",
    economic_rationale = "Li 2008 readability / obfuscation: managers bury bad news in complex, long prose -> lower subsequent returns. Full-corpus objective replication of pilot subjective-LLM complexity (WT-001 rho -0.316).",
    redundancy_cluster_id = "text_disclosure_readability (virgin material; distinct from disclosure METADATA killed WT-D20260710_005 = size-proxy)",
    weight_theta = 1.0,
    references = c("Li 2008 JAE readability", "Loughran-McDonald 2011 JF", "Brown-Tucker 2011 (YoY change)")
  )),
  diagnostics = diagnostics,
  selection_objective = "canonical_port_t",
  method_shopping_log = list(candidates_tried = 7L, method_log = lapply(1:nrow(famt), function(i)
    list(name=famt$metric[i], rank_ic=round(famt$mean_ic[i],5), harvey_t=round(famt$harvey_t[i],3),
         selected = famt$metric[i]=="obfuscation_composite"))),
  verdict = "FAIL_CANONICAL_HARD_GATE / SCREEN_TIER",
  verdict_basis = paste0(
    "Pre-registered PRIMARY (obfuscation_composite): canonical cap-w PORT_t=", round(getf(cf$portfolio_alpha_t_nw_lag3),2),
    " < 2.95 (HARD FAIL); rank-IC Harvey-t=", round(famt[metric=="obfuscation_composite"]$harvey_t,2),
    " placebo p=", adv$composite$placebo_p, " (NULL). ",
    "Best single m1 (avg sentence length): cap-w PORT_t=", round(m1$port_t_full,2),
    " < 2.95 (HARD FAIL), IS ", round(m1$port_t_IS,2), " -> OOS ", round(m1$port_t_OOS,2),
    " (oos_retention<<0.5 HARD FAIL, post-2017 decay). m1 signal REAL (placebo p=", adv$m1$placebo_p,
    ", survives Size control: partial|logSize IC=", round(adv$m1$size_partial,4), " cor(m1,logSize)=", round(adv$m1$size_cor,3),
    ", persistent: annual-lag12 Harvey-t=", round(adv$m1$lag12_t,2), ") but sub-threshold + small-cap localized (MEGA wshare=",
    round(getf(cf$diag_cap_tier$weight_share_avg$MEGA),3), ")."),
  screen_route = "TEXT_READABILITY_FEATURE (m1 sentence-length) -> OVERLAY_CANDIDATE / feature-preservation; NOT capital-grade standalone",
  challenge_flags = c(
    "RF: pre-registered composite is a NULL signal (placebo p=0.716); only m1 (avg sentence length) carries return signal (leave-one-out: dropping m1 flips composite Harvey-t to +0.64).",
    "IC->PORT_t transition wall: rank-IC Harvey-t (m1 -2.80) does NOT reach capital-grade cap-w PORT_t (2.35<2.95).",
    "Post-2017 / OOS decay: m1 IS PORT_t 2.80 -> OOS 0.18; cohort-wide attenuation.",
    "Cap-w trap: clarity-selected top-25 holds ~96% small-cap (OTHER), MEGA wshare ~0.01 -> long-only cross-section cannot express signal in benchmark tiers.",
    "Convergence divergence: objective metric best matching pilot LLM complexity (m2 fog 0.275 / composite 0.329) carries NO return signal; the return carrier (m1) has weak LLM convergence (0.147).",
    "Horizon caveat: pilot was 12M forward + subjective; Phase A is 1M monthly + objective — non-replication may be partly horizon/scorer, not pure falsification.",
    "Telegram send SUPPRESSED per WT prereg (charts generated as artifacts; Q-Lead attaches at judgment stage)."
  )
)

write_json(alpha_package, file.path(MBX,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("[16] alpha_package.json written\n")

# lineage (AFTER package write)
lu <- file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  source(lu)
  tryCatch(record_package_lineage(task_id="WT-D20260711_002", package_type="alpha_package",
    method_selected="obfuscation_composite (primary) + m1 sentence-length (carrier)",
    input_file_paths=c(file.path(OUT,"signal_panel.rds"), file.path(OUT,"analysis_results.rds"),
                       file.path(OUT,"single_metric_canon.rds"))),
    error=function(e) cat("[16] lineage warn:", conditionMessage(e), "\n"))
}
cat("[16] DONE\n")
