#!/usr/bin/env Rscript
# Promote strategy-pool BUILD_THEN_RUN rows that can be measured directly from
# the factor DB into executable AlphaSearch combo-factor commands.

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1L) args[[1]] else {
  file.path("stage_artifacts", "batch_434", paste0(format(Sys.Date(), "%Y%m%d"), "_promoted_combo_direct"))
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
ENGINE <- file.path("02_Infrastructure", "alpha_search", "fe_factor_combo.R")

clean_text <- function(x) {
  x <- gsub("'", "", x, fixed = TRUE)
  x <- gsub("\\\\", "/", x)
  x
}

r_string <- function(x) {
  x <- clean_text(x)
  x <- gsub("\"", "\\\\\"", x, fixed = TRUE)
  x
}

mk_cmd <- function(item_id, title, idea, factors, weights, min_count, n_holdings) {
  factors_str <- paste(factors, collapse = ",")
  weights_str <- paste(format(weights, scientific = FALSE, trim = TRUE), collapse = ",")
  result_path <- file.path(out_dir, paste0(item_id, "_result.rds"))
  expr <- sprintf(
    paste0(
      "source(\"02_Infrastructure/alpha_search/run_alpha_search.R\"); ",
      "res <- run_alpha_search(",
      "strategy_name=\"%s\", ",
      "strategy_idea=\"%s\", ",
      "factor_engine_path=\"%s\", ",
      "n_holdings=%dL, ",
      "weight_method=\"equal\", ",
      "universe=\"ALL\", ",
      "send_telegram=TRUE, ",
      "tg_dry_run=FALSE, ",
      "factor_analysis=TRUE); ",
      "saveRDS(res, \"%s\")"
    ),
    r_string(title),
    r_string(idea),
    r_string(ENGINE),
    as.integer(n_holdings),
    r_string(result_path)
  )
  sprintf(
    "FACTOR_NAMES=%s FACTOR_WEIGHTS=%s FACTOR_MIN_COUNT=%d Rscript -e %s",
    shQuote(factors_str),
    shQuote(weights_str),
    as.integer(min_count),
    shQuote(expr)
  )
}

equal_w <- function(x) rep(1, length(x))

promotions <- list(
  list(
    item_id = "STR_1048_BASE_3F",
    source_item_id = "STR_1048",
    title = "STR_1048 3-factor ensemble base signal",
    idea = "Defense(IdioVol+Beta) + EPS revision + industry momentum base signal. Overlay/NCO wrappers excluded; direct AlphaSearch remeasurement.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "ALPHA_21_BASE_QUALREV",
    source_item_id = "ALPHA_21",
    title = "Quality + short-term reversal base signal",
    idea = "CFOA + Piotroski + ROE growth + short-term reversal. Direct composite signal remeasurement, no result blending.",
    factors = c("Q09_CFOA", "Q04_Piotroski_F", "GR05_ROE_Growth", "M11_ST_Reversal"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "ALPHA_QUALREV_OVERLAY_BASE",
    source_item_id = "ALPHA_QUALREV_OVERLAY",
    title = "Quality + reversal base signal from overlay spec",
    idea = "Same source alpha as the overlay variant; BRK/market overlays excluded so QEPM and factor rotation can consume the raw base signal.",
    factors = c("Q09_CFOA", "Q04_Piotroski_F", "GR05_ROE_Growth", "M11_ST_Reversal"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "PIOTROSKI_OVERLAY_GRADEA_BASE",
    source_item_id = "PIOTROSKI_OVERLAY_GRADEA",
    title = "Piotroski F-score base signal",
    idea = "Piotroski quality signal only. Grade hurdle and overlay admission logic excluded for direct AlphaSearch measurement.",
    factors = c("Q04_Piotroski_F"),
    weights = c(1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_01_COMPOSITE_QUALITY_BASE",
    source_item_id = "SF_01_composite_quality",
    title = "Composite quality base signal",
    idea = "Gross profitability + CFOA + Piotroski + ROE growth + operating accrual quality, directly measured as one cross-sectional score.",
    factors = c("Q01_GPA", "Q09_CFOA", "Q04_Piotroski_F", "GR05_ROE_Growth", "AC07_Operating_Accruals"),
    weights = c(1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_03_DEF_QUALITY_BASE",
    source_item_id = "SF_03_def_quality_gate",
    title = "Defense + quality base signal",
    idea = "Idiosyncratic volatility, beta, Piotroski and gross profitability base signal. Quality gate wrapper excluded.",
    factors = c("D01_IdioVol", "D02_Beta", "Q04_Piotroski_F", "Q01_GPA"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "MF_NNNN1_SIMPLE_BEST_BASE",
    source_item_id = "MF_NNNN1_SIMPLE_BEST",
    title = "Defense + EPS revision simple base signal",
    idea = "Defense sleeve plus EPS revision sleeve; BRK and portfolio wrappers excluded.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m"),
    weights = c(1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SLE_5F_QUALITY_VALUE_BASE",
    source_item_id = "SLE_5F_QUALITY_VALUE",
    title = "Quality-value 5-factor base signal",
    idea = "Quality and value sleeves measured directly from factor DB aligned z-scores.",
    factors = c("Q01_GPA", "Q09_CFOA", "Q04_Piotroski_F", "V03_CFP", "V10_FCF_Yield"),
    weights = c(1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "MF_A2_FIXED_BALANCED_BASE",
    source_item_id = "MF_A2_FIXED_BALANCED",
    title = "Balanced multi-factor base signal",
    idea = "Defense, consensus, industry momentum, quality, value and price momentum measured as one base score.",
    factors = c("D01_IdioVol", "D02_Beta", "C01_SUE", "C02_EPS_Chg_1m", "M07_IndMom", "Q04_Piotroski_F", "V03_CFP", "M01_Mom_12_1"),
    weights = c(1, 1, 1, 1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "MF_A3_DEFENSE_HEAVY_BASE",
    source_item_id = "MF_A3_DEFENSE_HEAVY",
    title = "Defense-heavy multi-factor base signal",
    idea = "Defense-heavy composite with consensus, industry momentum, quality and value sleeves. Direct signal measurement.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom", "Q04_Piotroski_F", "V03_CFP"),
    weights = c(1.5, 1.5, 1, 0.75, 0.75, 0.75),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_15_DEFENSE_ONLY_BASE",
    source_item_id = "SF_15_defense_only_brk",
    title = "Defense-only base signal",
    idea = "Low idiosyncratic volatility and beta defense base signal. BRK overlay excluded.",
    factors = c("D01_IdioVol", "D02_Beta"),
    weights = c(1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_17_4F_CORE_BASE",
    source_item_id = "SF_17_4f_core",
    title = "Core defense-consensus-momentum-quality-value base signal",
    idea = "Core multi-factor base score from defense, EPS revision, industry momentum, quality and cash-flow value.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom", "Q04_Piotroski_F", "V03_CFP"),
    weights = c(1, 1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_09_3F_DEF_CONS_VAL_BASE",
    source_item_id = "SF_09_3f_def_cons_val",
    title = "Defense + consensus + value base signal",
    idea = "Defense, EPS revision and cash-flow yield base score, directly remeasured.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "V03_CFP"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_14_DEF_CONS_TP_BASE",
    source_item_id = "SF_14_def_cons_tp",
    title = "Defense + consensus + target-price base signal",
    idea = "Defense, EPS revision and target-price gap base score. Timing wrappers excluded.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "C06_TP_Gap"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_18_5F_EQ_BASE",
    source_item_id = "SF_18_5f_eq_mrs1225",
    title = "Equal-weight five-sleeve base signal",
    idea = "Defense, consensus, industry momentum, quality and value sleeves. MRS12/25 overlay excluded.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "M07_IndMom", "Q04_Piotroski_F", "V03_CFP"),
    weights = c(1, 1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_24_DCQV_4F_BASE",
    source_item_id = "SF_24_dcqv_4f",
    title = "Defense-consensus-quality-value base signal",
    idea = "Defense, EPS revision, quality and value sleeves directly measured from factor DB.",
    factors = c("D01_IdioVol", "D02_Beta", "C02_EPS_Chg_1m", "Q04_Piotroski_F", "V03_CFP"),
    weights = c(1, 1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_37_DEF_MRS1225_BASE",
    source_item_id = "SF_37_def_mrs1225",
    title = "Defense base signal from MRS spec",
    idea = "Defense base score only. MRS12/25 overlay excluded for direct signal measurement.",
    factors = c("D01_IdioVol", "D02_Beta"),
    weights = c(1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_11_SUE_EPSCHG_BASE",
    source_item_id = "SF_11_sue_epschg",
    title = "SUE + EPS revision base signal",
    idea = "Earnings surprise and one-month EPS revision composite directly measured.",
    factors = c("C01_SUE", "C02_EPS_Chg_1m"),
    weights = c(1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_20_DVQ_GATE_BASE",
    source_item_id = "SF_20_dvq_gate",
    title = "Defense-value-quality base signal",
    idea = "Defense, value and quality base score. Gate rules excluded from AlphaSearch measurement.",
    factors = c("D01_IdioVol", "D02_Beta", "V03_CFP", "Q04_Piotroski_F"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  ),
  list(
    item_id = "SF_05_MOM_DEF_BARBELL_BASE",
    source_item_id = "SF_05_mom_def_barbell",
    title = "Momentum-defense barbell base signal",
    idea = "Price momentum, industry momentum and defense sleeves measured directly as a base score.",
    factors = c("M01_Mom_12_1", "M07_IndMom", "D01_IdioVol", "D02_Beta"),
    weights = c(1, 1, 1, 1),
    n_holdings = 30L
  )
)

rows <- lapply(seq_along(promotions), function(i) {
  p <- promotions[[i]]
  min_count <- length(p$factors)
  data.frame(
    status = "KEEP",
    item_id = p$item_id,
    priority_score = round(0.90 - (i - 1) * 0.005, 3),
    bucket = "promoted_alpha_search",
    prefix = sub("_.*$", "", p$item_id),
    family = "factor_db_combo",
    execution_class = "RUN_ALPHA_COMBO_FACTOR",
    run_dir = ROOT,
    runnable_command = mk_cmd(
      item_id = p$item_id,
      title = p$title,
      idea = p$idea,
      factors = p$factors,
      weights = p$weights,
      min_count = min_count,
      n_holdings = p$n_holdings
    ),
    title = p$title,
    file = paste0(p$source_item_id, ".json"),
    reason = "factor DB aligned-z base signal mapped via fe_factor_combo.R; direct AlphaSearch measurement",
    mapping_quality = "BASE_SIGNAL_DIRECT_MEASURE",
    mapping_notes = paste0(
      "source_item_id=", p$source_item_id,
      "; overlays/gates/grade hurdles excluded; factors=", paste(p$factors, collapse = "+"),
      "; weights=", paste(format(p$weights, scientific = FALSE, trim = TRUE), collapse = "+"),
      "; min_count=", min_count
    ),
    source_item_id = p$source_item_id,
    factor_names = paste(p$factors, collapse = ","),
    factor_weights = paste(format(p$weights, scientific = FALSE, trim = TRUE), collapse = ","),
    factor_min_count = min_count,
    n_holdings = p$n_holdings,
    stringsAsFactors = FALSE
  )
})

queue <- do.call(rbind, rows)
queue_path <- file.path(out_dir, "promoted_combo_commands.csv")
write.csv(queue, queue_path, row.names = FALSE, fileEncoding = "UTF-8")

manifest_path <- file.path(out_dir, "promoted_combo_manifest.csv")
write.csv(
  queue[, c("item_id", "source_item_id", "title", "factor_names", "factor_weights",
            "factor_min_count", "n_holdings", "mapping_quality", "mapping_notes")],
  manifest_path,
  row.names = FALSE,
  fileEncoding = "UTF-8"
)

cat(sprintf("[promote-combo] wrote %d commands\n", nrow(queue)))
cat(sprintf("[promote-combo] queue=%s\n", queue_path))
cat(sprintf("[promote-combo] manifest=%s\n", manifest_path))
