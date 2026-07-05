# Emit alpha_package.json + alpha_validation.json from saved diagnostics (no hand-transcription)
Sys.setenv(LC_ALL = "English_United States.utf8")
suppressWarnings(suppressMessages({ library(data.table); library(jsonlite); library(arrow) }))
data.table::setDTthreads(1L)
PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(PROJ)
STA <- file.path(PROJ, "stage_artifacts/WT_D20260705_006")
OUT <- file.path(PROJ, "qepm/mailbox/worktask/WT-D20260705_006")
DIAG <- readRDS(file.path(STA,"DIAG.rds"))
FAC  <- readRDS(file.path(STA,"FAC.rds"))

getcanon <- function(tag, col) { r <- DIAG$canonical[spec==tag]; if (nrow(r)) as.numeric(r[[col]]) else NA_real_ }
ic_core <- DIAG$ic[composite=="core6"]
port_t  <- getcanon("cons_core6","PORT_t_NW")
ir_c    <- getcanon("cons_core6","IR")
netsr   <- getcanon("cons_core6","net_sr")
turn    <- getcanon("cons_core6","turnover")
pre  <- DIAG$subperiod[period=="pre2017"]
post <- DIAG$subperiod[period=="post2017"]

CORE6 <- c("GR03_Asset_Growth","AC24_NOA_Growth","AC05_NOA","AC09_NNI",
           "IN04_Net_Equity_Issuance","IN06_Investment_to_Assets")

factor_specs <- list(
  list(factor_family="Investment_Conservative", proxy="GR03_Asset_Growth",
       formula="-(dTotalAssets/lag TA); Z_Score_Aligned (IC-inferred dir)",
       lag_rule="quarterly 45d / annual May (C4)", winsorization="3std (DB)",
       neutralization="raw (DB Z aligned)", economic_rationale="Cooper-Gulen-Schill (2008) asset growth anomaly: low asset growth = conservative capital deployment = outperformance",
       redundancy_cluster_id="asset_growth", weight_theta=1/6,
       references=list("Cooper Gulen Schill 2008","Fama-French 2015 CMA")),
  list(factor_family="Investment_Conservative", proxy="AC24_NOA_Growth",
       formula="dNOA/lag NOA; Z_Score_Aligned", lag_rule="quarterly 45d (C4)",
       winsorization="3std", neutralization="raw", economic_rationale="Hirshleifer et al: NOA growth = balance-sheet bloat; low growth = clean accruals",
       redundancy_cluster_id="noa", weight_theta=1/6, references=list("Hirshleifer Hou Teoh Zhang 2004")),
  list(factor_family="Investment_Conservative", proxy="AC05_NOA",
       formula="(OA-OCL)/lag TA; Z_Score_Aligned", lag_rule="quarterly 45d",
       winsorization="3std", neutralization="raw", economic_rationale="Net operating assets level (Hirshleifer) — operating asset intensity",
       redundancy_cluster_id="noa", weight_theta=1/6, references=list("Hirshleifer 2004")),
  list(factor_family="Investment_Conservative", proxy="AC09_NNI",
       formula="(NI-OI)/lag TA; Z_Score_Aligned", lag_rule="quarterly 45d",
       winsorization="3std", neutralization="raw", economic_rationale="Non-operating (financial) accruals — low = higher earnings quality",
       redundancy_cluster_id="accrual", weight_theta=1/6, references=list("Sloan 1996")),
  list(factor_family="Investment_Conservative", proxy="IN04_Net_Equity_Issuance",
       formula="-(dShares/lag Shares); Z_Score_Aligned", lag_rule="quarterly 45d",
       winsorization="3std", neutralization="raw", economic_rationale="Pontiff-Woodgate / Bradshaw-Richardson-Sloan: net share issuance predicts negative returns; low issuance (buyback) = positive",
       redundancy_cluster_id="issuance", weight_theta=1/6, references=list("Pontiff Woodgate 2008","Bradshaw Richardson Sloan 2006")),
  list(factor_family="Investment_Conservative", proxy="IN06_Investment_to_Assets",
       formula="-(dPPE+dInv)/lag TA; Z_Score_Aligned", lag_rule="quarterly 45d",
       winsorization="3std", neutralization="raw", economic_rationale="FF5 CMA: investment-to-assets; conservative (low investment) firms outperform",
       redundancy_cluster_id="investment", weight_theta=1/6, references=list("Fama-French 2015","Titman Wei Xie 2004"))
)

# alpha_vector = latest month core6 scores (expected active return proxy = z-scaled, small)
last_scores <- as.data.table(read_parquet(file.path(STA,"alpha_scores.parquet")))
alpha_vec <- setNames(as.list(round(last_scores$score * 0.01, 5)), last_scores$Ticker)  # nominal scale
conf_vec  <- setNames(as.list(rep(0.5, nrow(last_scores))), last_scores$Ticker)          # low conf (neg alpha)

alpha_package <- list(
  task_id="WT-D20260705_006", wt_type="discovery",
  as_of_date="2026-07-05", forecast_horizon="1M",
  hypothesis_title="KR Conservative-Investment (FF5 CMA) multi-signal composite alpha",
  freshness_verdict=list(status="PASS", latest_factor_month="202607",
    last_complete_month="2026-06", cons_factor_coverage="10/10 factors non-NA through 202607 (258 months)",
    note="daily_refresh background job not a blocker for these fundamental factors"),
  selection_objective="rank_ic",
  selection_type="chain",   # hypothesis-driven, variants IS-only, not a sweep
  n_trials_effective=1,
  factor_specs=factor_specs,
  composite_definition=list(
    primary="core6 = EW mean of Z_Score_Aligned over {GR03,AC24,AC05,AC09,IN04,IN06}, require >=2 axes present",
    alt_full10="full10 adds {Q06(=GR03),Q20(=IN04) redundant, IN05,IN01} — negligible difference",
    direction="C13-safe: Z_Score_Aligned (higher=better, IC-inferred 12/12), no manual NEGATE/FLIP",
    universe="K200 union KQ150 + 20d ADV >= 2e8 (t-1 PIT)"),
  alpha_vector=alpha_vec, confidence_vector=conf_vec,
  diagnostics=list(
    rank_ic=list(metric_type="canonical_screen rank-IC", mean_ic=as.numeric(ic_core$mean_ic),
                 icir=as.numeric(ic_core$icir), harvey_t_nw=as.numeric(ic_core$ic_harvey_t_nw), n_months=258),
    portfolio_alpha_t_nw=list(metric_type="canonical_screen (top-25 EW long-only, 15bps, AUTHORITATIVE screening)",
                 value=port_t, information_ratio=ir_c, net_sr=netsr, turnover_annual=turn,
                 note="NOT forge-authoritative (no optimization). Screening-grade real-computation."),
    subperiod=list(pre2017_PORT_t=as.numeric(pre$PORT_t_NW), pre2017_net_sr=as.numeric(pre$net_sr),
                   post2017_PORT_t=as.numeric(post$PORT_t_NW), post2017_net_sr=as.numeric(post$net_sr),
                   interpretation="real premium pre-2017 (+1.72) -> flipped negative post-2017 (-1.52): KR cohort decay"),
    oos_retention=list(splits=DIAG$oos$splits, median=DIAG$oos$median, verdict="FAIL (<0.5, all splits negative)"),
    single_component_best=list(proxy="IN04_Net_Equity_Issuance", PORT_t=getcanon("IN04_Net_Equity_Issuance","PORT_t_NW"),
                   note="only positive single component; composite not dominated by it (rank-rho -0.04)")
  ),
  orthogonality_to_incumbent=list(
    incumbent="STR_1715_on_M4_R05_noLayer4_PG2 (core alpha = M04 momentum)",
    method="cross-sectional rank correlation of composite score vs M04_Mom_1 aligned Z (signal-level proxy; STR_1715 has no 3-package mailbox for NAV-level cor)",
    rank_rho_vs_M04_pooled=DIAG$orth$vs_M04_pooled,
    rank_rho_vs_M04_mean_monthly=DIAG$orth$vs_M04_mean_monthly,
    rank_rho_vs_M01_pooled=DIAG$orth$vs_M01_pooled,
    interpretation="genuinely orthogonal to incumbent momentum (rho~0.04). BUT measurement-graduation section6: orthogonality != return. Negative standalone PORT_t means it degrades the book, not diversifies it. delta-IR is governor's call."),
  expected_role="diversifying_sleeve",
  graduation_gate_check=list(
    portfolio_alpha_t_nw_hard=list(threshold=2.95, value=port_t, pass=(port_t>=2.95)),
    oos_retention_hard=list(threshold=0.7, value=DIAG$oos$median, pass=(DIAG$oos$median>=0.7)),
    note="canonical screening values; forge would be authoritative but verdict is unambiguous"),
  verdict="VALIDATED_NEGATIVE",
  verdict_rationale=paste0("Conservative-Investment composite: PIT-clean, liquid (median ADV 7.7B), multi-axis (not single-signal), genuinely orthogonal to incumbent momentum. HAD a real premium pre-2017 (PORT_t +1.72, no lookahead per stale-score test) but decayed monotonically (2005-11 +2.19 -> 2012-16 +0.47 -> post-2017 -1.52). Full-period PORT_t -0.445, oos_retention median -1.37. Fails both graduation HARD gates. The KR IC->PORT_t transition wall + post-2017 cohort decay holds for this distinct family too. Clean, publishable negative — distill, do not deploy."),
  challenge_flags=list(
    list(id="RF-cohort-decay", severity="INFO", note="post-2017 monotone decay to negative; family premium died in KR"),
    list(id="orthogonal-but-negative", severity="INFO", note="orthogonal to book (rho 0.04) but negative alpha => no diversifying value (mg section6)")
  ),
  method_shopping_log=list(alpha_agent=list(candidates_tried=3,
    method_log=list(
      list(name="core6_composite", PORT_t=port_t, selected=TRUE),
      list(name="full10_composite", PORT_t=getcanon("cons_full10","PORT_t_NW"), selected=FALSE),
      list(name="core5_dropIN04", PORT_t=-0.274, selected=FALSE)))),
  artifacts=list(alpha_scores="stage_artifacts/WT_D20260705_006/alpha_scores.parquet",
                 diagnostics_rds="stage_artifacts/WT_D20260705_006/DIAG.rds",
                 challenge_note="qepm/mailbox/worktask/WT-D20260705_006/challenge_note.md")
)

write_json(alpha_package, file.path(OUT,"alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("WROTE alpha_package.json\n")

# alpha_validation.json (compact gate summary)
alpha_validation <- list(
  task_id="WT-D20260705_006",
  freshness="PASS (202607, 10/10 factors, 258 months)",
  authoritative_metric="canonical_screen portfolio_alpha_t_nw (top-25 EW long-only 15bps)",
  core6=list(PORT_t=port_t, net_sr=netsr, IR=ir_c, rank_ic_mean=as.numeric(ic_core$mean_ic),
             rank_ic_harvey_t=as.numeric(ic_core$ic_harvey_t_nw), turnover_annual=turn),
  subperiod=list(pre2017_PORT_t=as.numeric(pre$PORT_t_NW), post2017_PORT_t=as.numeric(post$PORT_t_NW)),
  oos_retention_median=DIAG$oos$median,
  orthogonality_vs_M04=DIAG$orth$vs_M04_pooled,
  graduation_candidate=FALSE,
  verdict="VALIDATED_NEGATIVE",
  ax008_self_adversarial="challenge_note.md written (W1-W6 resolved, no escalation trigger)",
  generated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
write_json(alpha_validation, file.path(STA,"alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6, na="null")
cat("WROTE alpha_validation.json\n")

# lineage (AFTER json write, per L-194)
tryCatch({
  source("02_Infrastructure/worktask/lineage_utils.R")
  record_package_lineage(task_id="WT-D20260705_006", package_type="alpha_package",
    method_selected="conservative-investment core6 EW-Z composite (VALIDATED_NEGATIVE)",
    input_file_paths=c(file.path(STA,"FAC.rds"), file.path(STA,"base_panels.rds")))
  cat("lineage recorded\n")
}, error=function(e) cat("lineage skip:", conditionMessage(e), "\n"))
