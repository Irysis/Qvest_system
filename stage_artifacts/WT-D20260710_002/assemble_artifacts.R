# assemble_artifacts.R — WT-D20260710_002
# Assembles alpha_validation.json (8-factor dual-basis classification) + alpha_package.json
# from measured artifacts. write order: alpha_package.json -> record_package_lineage (L-194).

suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT-D20260710_002")
MB   <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260710_002")

db  <- fromJSON(file.path(OUT,"dual_basis_raw.json"), simplifyVector = FALSE)
adv <- fromJSON(file.path(OUT,"advisory_rankic.json"), simplifyVector = FALSE)
scores <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))

# EW-survivor rule: cap-w PORT_t < 2.95 AND EW PORT_t significant (t >= 2.5)
classify <- function(x) {
  capw <- x$capw_port_t_nw_lag3; ew <- x$ew_port_t_nw_lag3
  capw_pass <- is.finite(capw) && capw >= 2.95
  ew_sig    <- is.finite(ew) && ew >= 2.5
  if (capw_pass) return("capw_pass_not_rejected")           # was not actually cap-w-rejected
  if (ew_sig)    return("EW_SURVIVOR")                       # cap-w FAIL but EW significant
  if (is.finite(ew) && ew <= -2.0) return("true_dead_negative")
  if (is.finite(ew) && ew > 0)     return("true_dead_weak_positive")
  "true_dead"
}

facs <- names(db)
tab <- rbindlist(lapply(facs, function(f){
  x <- db[[f]]; a <- adv[[f]]
  data.table(
    factor=f,
    capw_port_t=round(x$capw_port_t_nw_lag3,3), capw_post2017_t=round(x$capw_post2017_t,3),
    capw_IR=round(x$capw_IR,3), capw_turnover=round(x$capw_turnover_annual,2),
    ew_port_t=round(x$ew_port_t_nw_lag3,3), ew_post2017_t=round(x$ew_post2017_t,3),
    ew_IR=round(x$ew_IR,3), ew_oos_approx=round(x$ew_oos_retention_approx %||% NA_real_,3),
    tier_MEGA=round(x$tier_wshare_MEGA,3), tier_MID=round(x$tier_wshare_MID,3), tier_OTHER=round(x$tier_wshare_OTHER,3),
    rank_ic=round(a$rank_ic,4), icir=round(a$icir,3), ic_t_nw=round(a$ic_t_nw_lag3,2),
    verdict=classify(x)
  )
}))
setorder(tab, -ew_port_t)
fwrite(tab, file.path(OUT,"ew_survivor_table.csv"))
print(tab[, .(factor, capw_port_t, ew_port_t, ew_post2017_t, tier_OTHER, rank_ic, verdict)])

survivors <- tab[verdict=="EW_SURVIVOR", factor]
cat("\nEW-survivors:", if(length(survivors)) paste(survivors,collapse=", ") else "NONE", "\n")

# ---- alpha_validation.json ----
validation <- list(
  task_id="WT-D20260710_002", as_of_date="2026-07-10",
  hypothesis="EW-relative survivor screen — dual-basis(cap-w vs EW-universe) re-measurement of cap-w-rejected standard factors. Separate benchmark-artifact rejections from true-dead.",
  universe="KOSPI200 U KOSDAQ150 (in_univ per-month, ~350 names/mo)", n_months=258, period="2005-01..2026-06",
  measurement_engine="canonical_screen_bt (top_n=25, 2e8 liq, 15bps, NW lag-3, diag_dual_basis=TRUE, size_dt)",
  selection_authority="canonical PORT_t (cap-w HARD-basis) — rank-IC advisory only",
  measurement_integrity_fix=list(
    issue="features_monthly = full factor-DB universe (~1772/mo) >> tradable K200uKQ150 (~350). 1st run: canonical top-25 drew out-of-universe micro-caps, forward Ret_1m 0-filled -> uniform spurious cap-w PORT_t ~ -2.5, cap-tier UNRANKED ~0.9.",
    fix="restrict scores to returns_monthly universe (in_univ & has forward return). tier sums ~1.00 after fix; 1st run discarded.",
    evidence="2015-06: 1772 feature names, 348 in tradable universe (11.1%)."
  ),
  ew_survivor_rule="cap-w PORT_t < 2.95 (rejected) AND EW-universe PORT_t >= 2.5 (survives) = benchmark-artifact rejection (re-routing candidate). Both < threshold = true-dead. NON-BINDING diag: EW basis is re-routing label, cap-w HARD is capital authority.",
  dual_basis_table=lapply(seq_len(nrow(tab)), function(i) as.list(tab[i])),
  ew_survivors=survivors,
  n_ew_survivors=length(survivors),
  strongest_ew_survivor=if(length(survivors)) survivors[1] else NULL,
  findings=list(
    "1 EW-survivor separated: V02_EP (cap-w +2.52 FAIL <2.95, EW +4.40 survive). Its top-25 holds 98.6% OTHER tier (rank 31+, benchmark-underweight tail) — mechanistically confirms alpha localizes in bench-low-weight names, cap-w mega-cap benchmark structurally cannot credit it.",
    "Benchmark-artifact is FACTOR-SPECIFIC, not universal: quality Q01_GPA/Q08_Composite_Quality are portfolio-NEGATIVE on BOTH bases (EW post2017_t ~ -2.5) = genuinely dead, NOT artifact (AX-004 upheld). Momentum M08/M09 weak-positive but non-significant either basis.",
    "V02_EP post-2017 EW survival is WEAK (+1.73, <2.5) — full-period +4.40 is pre-2017 value-premium heavy. Benchmark-artifact swing real (cap-w post17 -0.45 -> EW +1.73, ~+2.2t) but recent decay partially real even on EW. ew_oos_approx 0.52 (<0.7) — not graduation-grade even on EW.",
    "rank-IC MISLEADS (advisory confirmed): R12_Idiosyncratic_Risk has HIGHEST rank-IC (+0.051, IC_t +4.65) yet portfolio-NEGATIVE both bases (cap-w -1.16 / EW -1.64). Old rank_ic>=0.04 gate would false-pass R12."
  ),
  reroute_recommendation=list(
    V02_EP=list(
      lane=c("RAMP tiered/EW-weight sleeve (not cap-w top-25)","benchmark-relative construction (do not hedge mega-cap drift)","overlay context / value-timing"),
      caveat=c("capacity/cost of OTHER-tier (rank 31+) names in real deployment","post-2017 EW weak (+1.73) — pre-2017 heavy","NOT capital graduation — cap-w HARD +2.52 FAILS 2.95; re-routing label only")
    )
  ),
  non_graduation_disclaimer="cap-w PORT_t is capital-gate authority (forge build_bt_result). EW-survival is a RE-ROUTING label, not capital admission. No standalone capital editing claimed.",
  challenge_note="qepm/mailbox/worktask/WT-D20260710_002/challenge_note.md"
)
write_json(validation, file.path(MB,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
write_json(validation, file.path(OUT,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, na="null")

# ---- alpha_package.json ----
alpha_vec  <- setNames(as.list(round(scores$expected_active_1m,6)), scores$Ticker)
conf_vec   <- setNames(as.list(round(scores$confidence,4)), scores$Ticker)
v02 <- db[["V02_EP"]]; v10 <- db[["V10_FCF_Yield"]]
a02 <- adv[["V02_EP"]]

pkg <- list(
  task_id="WT-D20260710_002", wt_type="discovery", as_of_date="2026-07-10",
  forecast_horizon="1M",
  role_card_note="discovery survivor-screen: deliverable = benchmark-artifact vs true-dead classification (alpha_validation.json). factor_specs carries characterized strongest EW-survivor only (<=5). This is a diagnostic re-routing WT, not a capital-deployment alpha.",
  alpha_vector=alpha_vec,
  confidence_vector=conf_vec,
  signal_matrix_ref="stage_artifacts/WT-D20260710_002/alpha_scores.parquet",
  factor_specs=list(
    list(factor_family="Value", proxy="V02_EP (earnings yield)",
         formula="cross-sectional Z of E/P, direction-aligned (higher=better) via PIT-safe expanding-IC connector",
         lag_rule="quarterly 45d / annual May", winsorization="builder 3std", neutralization="factor-DB standard (sector/size per builder)",
         economic_rationale="value risk-premium / mispricing. STRONGEST EW-survivor: cap-w PORT_t +2.52 (FAIL <2.95) but EW-universe +4.40 (survive). 98.6% OTHER-tier (bench-underweight) holdings = benchmark-artifact rejection candidate. NOT capital graduation.",
         weight_theta=1.0, references=c("Basu 1977","Fama-French 1992"),
         redundancy_cluster_id="KR_value_EP",
         canonical_capw_port_t=v02$capw_port_t_nw_lag3, canonical_ew_port_t=v02$ew_port_t_nw_lag3,
         verdict="EW_SURVIVOR_reroute_candidate"),
    list(factor_family="Value", proxy="V10_FCF_Yield",
         formula="cross-sectional Z of FCF/price, direction-aligned",
         lag_rule="quarterly 45d / annual May", winsorization="builder 3std", neutralization="factor-DB standard",
         economic_rationale="cash-flow value. NEAR-MISS: cap-w +1.33 (FAIL), EW +2.30 (just below 2.5 threshold). EW post2017 -0.03 (recent dead). Marginal, not a qualifying survivor.",
         weight_theta=0.0, references=c("Fama-French 1992"),
         redundancy_cluster_id="KR_value_FCF",
         canonical_capw_port_t=v10$capw_port_t_nw_lag3, canonical_ew_port_t=v10$ew_port_t_nw_lag3,
         verdict="near_miss_not_qualifying")
  ),
  diagnostics=list(
    canonical_port_t_nw_lag3=v02$capw_port_t_nw_lag3,     # cap-w HARD-basis (authoritative screen) for V02_EP
    canonical_port_t_pvalue=v02$capw_port_t_pvalue,
    canonical_n_months=v02$n_months,
    canonical_ew_universe_port_t=v02$ew_port_t_nw_lag3,   # diag (non-binding)
    canonical_ew_post2017_t=v02$ew_post2017_t,
    canonical_ew_oos_retention_approx=v02$ew_oos_retention_approx,
    cap_tier_wshare=list(MEGA=v02$tier_wshare_MEGA, MID=v02$tier_wshare_MID, OTHER=v02$tier_wshare_OTHER),
    rank_ic=a02$rank_ic, icir=a02$icir, harvey_t_stat=a02$ic_t_nw_lag3,  # advisory (rank-IC based)
    turnover_proxy=v02$capw_turnover_annual,
    note="canonical_port_t_nw_lag3 = cap-w HARD-basis authoritative screen (metric_type=canonical_screen). EW fields = canonical_screen_diag (non-binding re-routing). rank_ic/icir/harvey_t = advisory (rank-IC based, misleads — see R12 in alpha_validation)."
  ),
  selection_objective="canonical_port_t",
  method_shopping_log=list(candidates_tried=length(facs),
    selection_type="diagnostic_survey_not_argmax",
    note="8 cap-w-rejected standard factors dual-basis re-measured (not try-and-cherry-pick). factor_specs carries characterized survivor + near-miss only.",
    method_log=lapply(facs, function(f) list(name=f, capw_port_t=db[[f]]$capw_port_t_nw_lag3,
                                             ew_port_t=db[[f]]$ew_port_t_nw_lag3,
                                             selected=(f=="V02_EP")))),
  challenge_flags=c(
    "EW_survivor_is_reroute_label_NOT_capital_graduation (cap-w HARD +2.52 FAILS 2.95, forge authoritative)",
    "V02_EP post-2017 EW weak (+1.73 <2.5) — full-period strength pre-2017 heavy; ew_oos_approx 0.52 <0.7",
    "capacity_concern_other_tier: V02_EP 98.6% OTHER-tier (rank 31+) holdings — deployment capacity/cost risk",
    "benchmark_artifact_is_factor_specific: quality Q01/Q08 dead-negative BOTH bases (AX-004 upheld), momentum non-significant both",
    "rank-IC advisory: R12 highest rank-IC (0.051) but portfolio-NEGATIVE both bases",
    "measurement_integrity_fix applied: 1st run had universe-mismatch 0-fill drag (see alpha_validation)"
  )
)
# WRITE ORDER: package first, then lineage (L-194)
write_json(pkg, file.path(MB,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, na="null")
cat("\n[assemble] alpha_package.json + alpha_validation.json written.\n")

# lineage (after write)
tryCatch({
  source(file.path(ROOT,"02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260710_002", package_type="alpha_package",
    method_selected="dual-basis survivor screen: V02_EP EW-survivor (cap-w reject)",
    input_file_paths=c(".cache/RAWDATA.parquet",".cache/factor_db/",
                       "stage_artifacts/WT-D20260710_002/panel/features_monthly.parquet"))
  cat("[assemble] lineage recorded.\n")
}, error=function(e) cat("[assemble] lineage skip:", conditionMessage(e),"\n"))
cat("ASSEMBLE_DONE\n")
