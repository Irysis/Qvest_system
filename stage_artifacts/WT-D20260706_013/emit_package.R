# emit_package.R — WT-D20260706_013 Alpha Research
# Emits alpha_scores.parquet, alpha_validation.json, alpha_package.json (+ lineage).
# CLEAN_NEGATIVE: intangible-adjusted value does not escape the KR large-cap wall (post-2017 cap-w death).

suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
WT  <- "WT-D20260706_013"
MB  <- file.path(ROOT, "qepm/mailbox/worktask", WT)
STG <- file.path(ROOT, "stage_artifacts", WT)
PAN <- file.path(STG, "panel")
AS_OF <- as.Date("2026-07-06")

sc  <- as.data.table(read_parquet(file.path(PAN, "intan_scores_monthly.parquet")))
res <- readRDS(file.path(STG, "screen_results.rds"))

# ---- alpha_vector: cross-sectional z of iBM_orgc at latest signal month (headline signal) ----
sig_month <- max(sc$Date[sc$Date <= AS_OF])
snap <- sc[Date == sig_month & is.finite(iBM_orgc)]
zsc <- function(x){ x<-as.numeric(x); w<-pmin(pmax(x,quantile(x,.01,na.rm=TRUE)),quantile(x,.99,na.rm=TRUE)); (w-mean(w,na.rm=TRUE))/sd(w,na.rm=TRUE) }
snap[, z_iBM_orgc := zsc(iBM_orgc)]
snap[, z_iBM_full := zsc(iBM_full)]
snap[, z_stdBM    := zsc(stdBM)]
# confidence: data quality (has_rd + finite eq/ni) + cross-sectional coverage
snap[, conf := 0.5 + 0.2*as.integer(has_rd) + 0.15*as.integer(is.finite(eq)) + 0.15*as.integer(is.finite(ni))]
snap[, conf := pmin(pmax(conf,0),1)]
# expected active return proxy (screening-tier only; NOT authoritative): scale z by realized ann alpha/sd
alpha_scale <- 0.01
snap[, alpha_hat := alpha_scale * z_iBM_orgc]

alpha_scores <- snap[, .(Date = sig_month, Ticker,
                         z_iBM_orgc, z_iBM_full, z_stdBM,
                         iBM_orgc, iBM_full, stdBM, stdEP, iEP_orgc,
                         size_rank, size_pctile, has_rd, intan_intensity,
                         alpha_hat, confidence = conf)]
write_parquet(alpha_scores, file.path(STG, "alpha_scores.parquet"))
cat(sprintf("[emit] alpha_scores: %d names @ %s\n", nrow(alpha_scores), as.character(sig_month)))

# ---- pull key screening numbers ----
gv <- function(dt, lab, col) { v <- dt[label==lab][[col]]; if(length(v)) v[1] else NA }
std_cw <- res$res_std$cw; orgc_cw <- res$res_orgc$cw; full_cw <- res$res_full$cw
orgc_ew <- res$res_orgc$ew
ic <- res$ic_tbl

validation <- list(
  task_id = WT, as_of_date = as.character(AS_OF), signal_month = as.character(sig_month),
  metric_type = "canonical_screen",
  verdict = "CLEAN_NEGATIVE",
  verdict_summary = "Intangible-adjusted value does NOT escape the KR large-cap wall. Standard value death (AX-003) reproduced; intangible adjustment barely re-ranks (cross-rank Spearman 0.987), does not tilt value large-cap (signal~size -0.705), and forcing a large-cap/intangible tilt makes post-2017 cap-w PORT_t strictly worse. KR value death is real, not an intangible-mismeasurement artifact.",
  headline_signal = "iBM_orgc",
  rank_ic_diagnostic = list(
    stdBM = list(rank_ic=ic[signal=="stdBM"]$rank_ic, ic_t=ic[signal=="stdBM"]$ic_t, icir=ic[signal=="stdBM"]$icir),
    iBM_orgc = list(rank_ic=ic[signal=="iBM_orgc"]$rank_ic, ic_t=ic[signal=="iBM_orgc"]$ic_t, icir=ic[signal=="iBM_orgc"]$icir),
    iBM_full = list(rank_ic=ic[signal=="iBM_full"]$rank_ic, ic_t=ic[signal=="iBM_full"]$ic_t, icir=ic[signal=="iBM_full"]$icir),
    iEP_orgc = list(rank_ic=ic[signal=="iEP_orgc"]$rank_ic, ic_t=ic[signal=="iEP_orgc"]$ic_t, icir=ic[signal=="iEP_orgc"]$icir),
    note = "rank-IC t 3.1-5.3 for value variants BUT portfolio-alpha t (authoritative) fails post-2017 (long-only realized alpha != cross-sectional rank power)"
  ),
  portfolio_alpha_t_canonical = list(
    benchmark = "cap-w float universe (K200∪KQ150)",
    CONTROL_stdBM = list(FULL=gv(std_cw,"FULL_capw","port_t"), PRE2017=gv(std_cw,"PRE2017_capw","port_t"), POST2017=gv(std_cw,"POST2017_capw","port_t"), VALUEUP2024=gv(std_cw,"VALUEUP2024_capw","port_t")),
    iBM_orgc = list(FULL=gv(orgc_cw,"FULL_capw","port_t"), PRE2017=gv(orgc_cw,"PRE2017_capw","port_t"), POST2017=gv(orgc_cw,"POST2017_capw","port_t"), VALUEUP2024=gv(orgc_cw,"VALUEUP2024_capw","port_t")),
    iBM_full = list(FULL=gv(full_cw,"FULL_capw","port_t"), PRE2017=gv(full_cw,"PRE2017_capw","port_t"), POST2017=gv(full_cw,"POST2017_capw","port_t"))
  ),
  ew_vs_capw = list(
    note = "EW benchmark 'survival' is the small-cap tilt, not a wall-escape.",
    iBM_orgc_POST2017_capw = gv(orgc_cw,"POST2017_capw","port_t"),
    iBM_orgc_POST2017_ew   = gv(orgc_ew,"POST2017_ew","port_t")
  ),
  large_cap_decomposition = list(
    note = "wall-escape판별: intangible adj must strengthen LARGE-cap value. It does not.",
    stdBM_LARGE_capw = res$lc[signal=="stdBM"&group=="LARGE"&bench=="capw"]$port_t,
    iBM_orgc_LARGE_capw = res$lc[signal=="iBM_orgc"&group=="LARGE"&bench=="capw"]$port_t,
    iBM_full_LARGE_capw = res$lc[signal=="iBM_full"&group=="LARGE"&bench=="capw"]$port_t,
    iBM_orgc_SMALL_capw = res$lc[signal=="iBM_orgc"&group=="SMALL"&bench=="capw"]$port_t,
    verdict = "LARGE-cap intangible value PORT_t ~0.08 (dead); SMALL retains ~1.48. Value stays small-cap."
  ),
  reclassification = list(
    cross_rank_spearman_std_vs_intan = res$xrank_cor_med,
    large_cap_mean_rank_shift = res$lc_shift$mean_shift,
    small_cap_mean_rank_shift = res$sm_shift$mean_shift,
    interpretation = "0.987 cross-rank corr + LARGE-cap rank-shift ≈ -0.001 (NOT positive) => intangible adjustment does NOT reclassify mega-caps cheaper. Wall-escape mechanism absent at its root."
  ),
  monotonicity = res$mono,
  signal_size_correlation = -0.705,
  quality_orthogonality = list(iBM_orgc_ROE=-0.239, stdBM_ROE=-0.243, note="not quality-in-disguise; genuine value"),
  adversarial_tilt_sweep = list(
    note = "forcing large-cap/intangible tilt worsens POST2017 cap-w PORT_t (monotone wrong direction)",
    lam0.5=-0.951, lam1.0=-1.019, lam2.0=-1.158, pure_intan_intensity=-1.415
  ),
  data_caveats = list(
    rd_line_coverage = "RandD separate line collapses post-2016 (has_rd frac post-2017 = 0.17); post-2017 leans on SG&A org-capital + on-balance IntangibleAssets",
    metric_type = "canonical_screen (screening-tier; NOT forge-authoritative, NOT admission-binding)"
  ),
  intangible_params = list(delta_RD=0.15, delta_SGA=0.20, theta_SGA=0.30, g_steady=0.10, source="Peters-Taylor 2017 canonical defaults (no return-tuning)")
)
write_json(validation, file.path(STG, "alpha_validation.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[emit] alpha_validation.json written\n")

# ---- alpha_package.json (schema v1) ----
av <- setNames(as.list(round(alpha_scores$alpha_hat,6)), alpha_scores$Ticker)
cv <- setNames(as.list(round(alpha_scores$confidence,4)), alpha_scores$Ticker)

alpha_package <- list(
  task_id = WT, wt_type = "discovery", as_of_date = as.character(AS_OF),
  forecast_horizon = "1M",
  status = "COMPLETE_CLEAN_NEGATIVE",
  selection_objective = "portfolio_alpha_t_nw",   # authoritative gate (screening); rank_ic diagnostic only
  alpha_vector = av, confidence_vector = cv,
  signal_matrix_ref = "stage_artifacts/WT-D20260706_013/alpha_scores.parquet",
  factor_specs = list(
    list(factor_family="Value", proxy="iBM_orgc (intangible-adjusted book-to-market, org-capital)",
         formula="(TotalEquity + OrgCapital) / MarketCap;  OrgCapital = perpetual-inventory(0.30*SG&A, δ=0.20)",
         lag_rule="fundamental Factor_Date <= t (quarterly ~45d / annual May)", winsorization="1/99 pct",
         neutralization="none (raw cross-sectional; size/quality ortho reported)",
         economic_rationale="Peters-Taylor 2017: expensed intangibles (R&D/SG&A) understate book -> intangible-intensive firms mis-valued. Test whether adjustment reclassifies KR mega-caps cheap and revives dead value.",
         weight_theta=1.0, references=list("Peters-Taylor 2017 JFE","Eisfeldt-Papanikolaou 2013 JF")),
    list(factor_family="Value", proxy="iBM_full (+ R&D knowledge capital)",
         formula="(TotalEquity + KnowledgeCap + OrgCap)/MarketCap; KnowledgeCap = perpetual-inventory(R&D, δ=0.15)",
         lag_rule="same", winsorization="1/99 pct", neutralization="none",
         economic_rationale="full Peters-Taylor knowledge+organizational capital. R&D line sparse post-2016.",
         weight_theta=0.0, references=list("Peters-Taylor 2017 JFE")),
    list(factor_family="Value", proxy="stdBM (CONTROL — standard book-to-market)",
         formula="TotalEquity / MarketCap", lag_rule="same", winsorization="1/99 pct", neutralization="none",
         economic_rationale="AX-003 death reproduction control (must fail post-2017).",
         weight_theta=0.0, references=list("Fama-French 1993"))
  ),
  diagnostics = list(
    rank_ic = ic[signal=="iBM_orgc"]$rank_ic,
    icir = ic[signal=="iBM_orgc"]$icir,
    monotonicity = res$mono,
    subperiod_stability = 0.0,  # dies post-2017; pre/post not stable
    turnover_proxy = orgc_cw[label=="FULL_capw"]$turnover,
    harvey_t_stat = ic[signal=="iBM_orgc"]$ic_t,          # rank-IC t (diagnostic)
    portfolio_alpha_t_nw_full_capw = orgc_cw[label=="FULL_capw"]$port_t,
    portfolio_alpha_t_nw_post2017_capw = orgc_cw[label=="POST2017_capw"]$port_t,  # HEADLINE authoritative-style
    post_neutralization_ic = ic[signal=="iBM_orgc"]$rank_ic
  ),
  challenge_flags = list(
    "CLEAN_NEGATIVE: intangible-adjusted value fails to escape KR large-cap wall (POST2017 cap-w PORT_t = -0.77, ~= stdBM control -0.79).",
    "RECLASSIFICATION FAILURE: cross-rank Spearman(stdBM,iBM_orgc)=0.987; LARGE-cap mean rank-shift ~= -0.001 (not positive). Intangible adj does not reclassify mega-caps cheaper.",
    "STRUCTURALLY SMALL-CAP: signal~size Spearman=-0.705; top-25 median size-pctile 9.1%; forcing large-cap tilt worsens post-2017 alpha (-0.95 to -1.42).",
    "DATA CAVEAT: RandD separate-line coverage collapses post-2016 (has_rd frac post2017=0.17); V-full~=V-orgc post-2017.",
    "RF-A3-like: pre-2017 strong (PORT_t 3.79) but post-2017 dead (-0.77) = regime decay, not stable alpha.",
    "metric_type=canonical_screen (screening-tier, NOT forge-authoritative / admission-binding)."
  ),
  challenge_note_ref = "qepm/mailbox/worktask/WT-D20260706_013/challenge_note.md",
  recommendation = list(
    forge_promotion = FALSE,
    reason = "No cap-w post-2017 survival at any adjustment strength; wall-escape mechanism (mega-cap reclassification) empirically absent. Value-family (standalone long-only) research direction: CLOSE.",
    screen_route = "none (dead post-2017 under deployable cap-w bar)"
  ),
  method_shopping_log = list(
    candidates_tried = 5,
    method_log = list(
      list(name="iBM_orgc", selected=TRUE,  post2017_capw_port_t=orgc_cw[label=="POST2017_capw"]$port_t),
      list(name="iBM_full", selected=FALSE, post2017_capw_port_t=full_cw[label=="POST2017_capw"]$port_t),
      list(name="iEP_orgc", selected=FALSE, post2017_capw_port_t=res$res_iEPo$cw[label=="POST2017_capw"]$port_t),
      list(name="stdBM(CONTROL)", selected=FALSE, post2017_capw_port_t=std_cw[label=="POST2017_capw"]$port_t),
      list(name="stdEP(CONTROL)", selected=FALSE, post2017_capw_port_t=res$res_stdEP$cw[label=="POST2017_capw"]$port_t)
    ),
    parallel_exec = FALSE
  )
)
write_json(alpha_package, file.path(MB, "alpha_package.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
cat("[emit] alpha_package.json written to mailbox\n")

# ---- lineage (AFTER json write) ----
lu <- file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R")
if (file.exists(lu)) {
  source(lu)
  tryCatch(record_package_lineage(task_id=WT, package_type="alpha_package",
    method_selected="intangible-adjusted value (iBM_orgc/full) + stdBM control, canonical top-25 cap-w",
    input_file_paths=c(".cache/RAWDATA.parquet",".cache/fundamental_merged.parquet",
                       file.path(PAN,"intan_scores_monthly.parquet"))),
    error=function(e) cat("[emit] lineage warn:", conditionMessage(e), "\n"))
} else cat("[emit] lineage_utils.R absent — skip\n")
cat("[emit] DONE\n")
