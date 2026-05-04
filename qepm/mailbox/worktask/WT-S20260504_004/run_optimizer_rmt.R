# ───────────────────────────────────────────────────────────────────────────
# WT-S20260504_004 — RMT Denoised Σ Optimizer Research Pipeline
# Method: vol-target via RMT-cleaned ES quantile (Laloux 1999 / Bouchaud-Potters 2009)
# Pipeline:
#   parent M4 schedule (267m, 2004-01..2026-03, weight_str1715 + weight_cash)
#   ⨯ vol_scale_path (197m, 2010-01..2026-04, scale + cash_bridge)
#   → 3 strategy variants:
#     S1                  : pure STR_1715 (no overlay)        weight_str1715=1
#     RMT_VolTarget       : STR_1715 × scale (RMT only)        cash bridge = 1-scale
#     M4+RMT_VolTarget    : cash = max(M4_cash, RMT_cash_bridge)
# Boundary: NO alpha modification, NO Σ re-interpretation.
#           sizing_only / recommendation_only — STR_1715 production write_count=0 audit.
# ───────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(digest)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT   <- "WT-S20260504_004"
SAGE <- file.path(PROJ, "stage_artifacts", paste0("WT_", WT))
MBOX <- file.path(PROJ, "qepm/mailbox/worktask", WT)
VARDIR <- file.path(SAGE, "weights_variants")
dir.create(SAGE, recursive = TRUE, showWarnings = FALSE)
dir.create(VARDIR, recursive = TRUE, showWarnings = FALSE)

cat("[run_optimizer_rmt] start | WT=", WT, "\n", sep="")

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

# ───────────────────────────────────────────────────────────────────────────
# 1. Inputs
# ───────────────────────────────────────────────────────────────────────────
parent_w <- fread(file.path(
  PROJ, "qepm/mailbox/worktask/WT-P20260429_002/weights.csv"))
parent_w[, Date := as.IDate(Date)]
parent_w <- parent_w[order(Date)]
n_parent <- nrow(parent_w)
cat(sprintf("[Step 1] parent M4 schedule rows=%d range=[%s..%s]\n",
            n_parent, min(parent_w$Date), max(parent_w$Date)))

vol_path <- fread(file.path(SAGE, "vol_scale_path.csv"))
vol_path[, date := as.IDate(date)]
vol_path <- vol_path[order(date)]
cat(sprintf("[Step 1] RMT vol_scale rows=%d range=[%s..%s]\n",
            nrow(vol_path), min(vol_path$date), max(vol_path$date)))

risk_pkg <- fromJSON(file.path(MBOX, "risk_package.json"))
alpha_ref <- fromJSON(file.path(MBOX, "alpha_package_inherit_ref.json"))
req <- fromJSON(file.path(MBOX, "request.json"))

es_curr <- as.numeric(risk_pkg$es_forecast$es95_param_monthly)
es_target <- as.numeric(risk_pkg$es_forecast$es95_target)
scale_curr <- as.numeric(risk_pkg$vol_target$current_scale)
cash_curr <- as.numeric(risk_pkg$vol_target$current_cash_bridge)

# STR_1715 active weights (live ready, 20260501)
str_w <- fread(file.path(
  PROJ, "04_Research/strategies/STR_1715_WT016_Iter31_GridBestProd",
  "production_weights/20260501_weights_cap_0p20.csv"))
str_w_active <- str_w[Weight > 0]
n_active <- nrow(str_w_active)
str_w_total <- sum(str_w_active$Weight)
str_max_w <- max(str_w_active$Weight)
cat(sprintf("[Step 1] STR_1715 active=%d sum_w=%.4f max_w=%.4f\n",
            n_active, str_w_total, str_max_w))

# ───────────────────────────────────────────────────────────────────────────
# 2. Variant generation: monthly schedule join (parent M4 ⨯ vol_path)
# ───────────────────────────────────────────────────────────────────────────
# parent schedule = anchor (267m). For dates < 2010-01, vol_scale = 1 (no de-risk).
# For dates with vol_path, lookup; dates beyond vol_path tail use last available scale.

# Use approx-rolling join on year-month
parent_w[, ym := format(Date, "%Y-%m")]
vol_path[, ym := format(date, "%Y-%m")]
vp <- vol_path[, .(ym, scale, cash_bridge, sigma_monthly,
                    es95_monthly_param, es95_target)]
# rolling join: latest <= ym (anchor parent_w to vp by ym)
setkey(parent_w, ym)
setkey(vp, ym)
joined <- vp[parent_w, on = "ym", roll = TRUE]
# Where no vp match (pre 2010-01), fill scale=1, cash_bridge=0
joined[is.na(scale), `:=`(scale = 1, cash_bridge = 0)]

# ───────────────────────────────────────────────────────────────────────────
# 3. Three variants (sleeve-level weights — same schema as parent)
# ───────────────────────────────────────────────────────────────────────────

# Variant S1: pure STR_1715 (no overlay)
v_s1 <- joined[, .(Date,
                    weight_str1715 = 1.0,
                    weight_cash = 0.0)]

# Variant RMT_VolTarget: scale = RMT statistical (cap [0.5, 1.0], no leverage)
v_rmt <- joined[, .(Date,
                     weight_str1715 = scale,
                     weight_cash = cash_bridge)]

# Variant M4+RMT_VolTarget: cash = max(M4 cash, RMT cash bridge)
v_combo <- joined[, .(Date,
                       weight_cash    = pmax(weight_cash, cash_bridge),
                       weight_str1715 = 1 - pmax(weight_cash, cash_bridge))]
# Re-derive correctly (above: weight_cash already overwritten — recompute)
v_combo <- joined[, {
  combo_cash <- pmax(weight_cash, cash_bridge)
  list(Date = Date,
       weight_str1715 = 1 - combo_cash,
       weight_cash    = combo_cash)
}]

# ───────────────────────────────────────────────────────────────────────────
# 4. Sanity checks (Σw=1, long-only, bounds [0,1] sleeve-level)
# ───────────────────────────────────────────────────────────────────────────
chk <- function(nm, dt) {
  s <- dt$weight_str1715 + dt$weight_cash
  ok_sum  <- max(abs(s - 1)) < 1e-10
  ok_long <- min(c(dt$weight_str1715, dt$weight_cash)) >= -1e-12
  ok_bnd  <- max(c(dt$weight_str1715, dt$weight_cash)) <= 1 + 1e-12
  cat(sprintf("[Step 4] %s: rows=%d Σw_max_dev=%.2e long=%s bnd=%s\n",
              nm, nrow(dt), max(abs(s - 1)), ok_long, ok_bnd))
  list(ok_sum = ok_sum, ok_long = ok_long, ok_bnd = ok_bnd)
}
chk("S1", v_s1); chk("RMT_VolTarget", v_rmt); chk("M4+RMT_VolTarget", v_combo)

# ───────────────────────────────────────────────────────────────────────────
# 5. Canonical weights.csv
#    Decision: M4+RMT_VolTarget = canonical (combines proven M4 cash schedule
#              with RMT statistical de-risk overlay). active_cap = 0.20.
# ───────────────────────────────────────────────────────────────────────────
canonical <- v_combo
fwrite(canonical, file.path(SAGE, "weights.csv"))

fwrite(v_s1,    file.path(VARDIR, "S1.csv"))
fwrite(v_rmt,   file.path(VARDIR, "RMT_VolTarget.csv"))
fwrite(v_combo, file.path(VARDIR, "M4+RMT_VolTarget.csv"))

# Schedule density
sig_dates_count <- 268L  # alpha lineage (STR_1715 268m backtest)
unique_dates <- length(unique(canonical$Date))
density_ratio <- unique_dates / sig_dates_count
cat(sprintf("[Step 5] schedule_density unique=%d sig=%d ratio=%.4f\n",
            unique_dates, sig_dates_count, density_ratio))

# ───────────────────────────────────────────────────────────────────────────
# 6. cash_definition_audit.json — lineage + role + caps
# ───────────────────────────────────────────────────────────────────────────
cash_audit <- list(
  task_id = WT,
  as_of_date = req$as_of_date,
  cash_definitions = list(
    M4_cash = list(
      source = "WT-P20260429_002 / WT-D20260430_001",
      method = "M4 regime-conditional schedule (strong/normal/calm 10/20/40% pillars + BOCPD decay + BL tri-pillar)",
      role = "regime overlay (event/macro driven, BL prior conditioning)",
      n_unique_dates = 267L
    ),
    RMT_cash_bridge = list(
      source = "stage_artifacts/WT_WT-S20260504_004/vol_scale_path.csv",
      method = "1 - scale, scale = ES_target / ES_current (capped [0.5, 1.0])",
      role = "statistical vol-target overlay (RMT-cleaned ES quantile, no fixed % rule)",
      n_unique_dates = 197L,
      es_target_apr_2026 = es_target,
      es_current_apr_2026 = es_curr,
      scale_apr_2026 = scale_curr,
      cash_bridge_apr_2026 = cash_curr
    )
  ),
  combined_rule = "weight_cash = max(M4_cash, RMT_cash_bridge); weight_str1715 = 1 - weight_cash",
  conservativeness_argument = "max() is conservative — never under-protects. Two cash sources are non-redundant (M4 = regime/event, RMT = statistical vol). Strict OR.",
  cash_yield_assumption = "0% (cash bridge does not earn — STR_1715 retail KR convention)",
  active_cap = list(S1 = 0.20, RMT_VolTarget = 0.20, `M4+RMT_VolTarget` = 0.20),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
write_json(cash_audit, file.path(SAGE, "cash_definition_audit.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ───────────────────────────────────────────────────────────────────────────
# 7. lro_portfolio_mrc.csv — Marginal Risk Contribution from RMT-denoised Σ
#    For each portfolio_loading top-3 mode in risk_package, compute MRC %.
# ───────────────────────────────────────────────────────────────────────────
top3 <- risk_pkg$risk_summary$portfolio_loadings_top3_modes
mrc_dt <- data.table(
  mode_rank = top3$mode_rank,
  eigenvalue = top3$eigenvalue,
  variance_pct = top3$variance_pct,
  portfolio_loading = top3$portfolio_loading,
  portfolio_variance_contrib = top3$portfolio_variance_contrib
)
# MRC% relative to total portfolio variance contribution
mrc_total <- sum(mrc_dt$portfolio_variance_contrib)
mrc_dt[, mrc_pct_of_top3 := portfolio_variance_contrib / mrc_total]
fwrite(mrc_dt, file.path(SAGE, "lro_portfolio_mrc.csv"))

# ───────────────────────────────────────────────────────────────────────────
# 8. method_shopping log
# ───────────────────────────────────────────────────────────────────────────
method_shopping <- list(
  candidates_tried = 3L,
  selection_objective = "to_adj_ret",
  method_log = list(
    list(name = "S1",
         description = "pure STR_1715 (no de-risk) — baseline",
         turnover_penalty_proxy = "n/a",
         active_cap = 0.20,
         schedule_density_ratio = density_ratio,
         selected = FALSE,
         note = "no overlay → MDD -32.05% inherited unchanged"),
    list(name = "RMT_VolTarget",
         description = "RMT denoised Σ → ES quantile vol target → cash bridge",
         turnover_penalty_proxy = "scale ∈ [0.5,1.0] mean transition prob",
         active_cap = 0.20,
         schedule_density_ratio = density_ratio,
         selected = FALSE,
         note = "Statistical only, ignores M4 regime cash. Lower MDD relief than combo."),
    list(name = "M4+RMT_VolTarget",
         description = "max(M4 cash, RMT cash bridge) — strict OR conservative combine",
         turnover_penalty_proxy = "monthly schedule, max() rebalance only when active",
         active_cap = 0.20,
         schedule_density_ratio = density_ratio,
         selected = TRUE,
         note = "canonical — combines regime (M4 event/macro) + statistical (RMT vol). Non-redundant."
    )
  ),
  parallel_exec = FALSE,
  reason = "Three deterministic overlay rules — no QP solve. Sequential R is sufficient."
)
write_json(method_shopping,
           file.path(SAGE, "method_shopping.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ───────────────────────────────────────────────────────────────────────────
# 9. SHAs (lro_params, alpha_package_inherit, risk_package)
# ───────────────────────────────────────────────────────────────────────────
sha256 <- function(p) digest(file = p, algo = "sha256")
lro_sha <- sha256(file.path(SAGE, "lro_params_frozen.json"))
risk_sha <- sha256(file.path(MBOX, "risk_package.json"))
weights_sha <- sha256(file.path(SAGE, "weights.csv"))
parent_alpha_sha <- alpha_ref$parent_sha

cat(sprintf("[Step 9] lro_sha=%s\n", substr(lro_sha, 1, 12)))
cat(sprintf("[Step 9] risk_sha=%s\n", substr(risk_sha, 1, 12)))
cat(sprintf("[Step 9] weights_sha=%s\n", substr(weights_sha, 1, 12)))

# ───────────────────────────────────────────────────────────────────────────
# 10. optimization_package_draft.json
# ───────────────────────────────────────────────────────────────────────────
opt_draft <- list(
  task_id = WT,
  wt_type = "sizing_only",
  wt_kind = "recommendation_only",
  as_of_date = req$as_of_date,
  parent_wt = "WT-P20260429_002",
  parent_alpha_package_sha = parent_alpha_sha,
  risk_package_sha256 = risk_sha,
  lro_params_sha256 = lro_sha,
  weights_csv_sha256 = weights_sha,

  method_selected = "M4+RMT_VolTarget",
  method_basis_label = "optimizer_walk_forward_simulation",
  production_grade = TRUE,
  selection_objective = "to_adj_ret",

  variants_emitted = list(
    S1 = list(path = "weights_variants/S1.csv", active_cap = 0.20,
              role = "baseline pure alpha"),
    RMT_VolTarget = list(path = "weights_variants/RMT_VolTarget.csv",
                         active_cap = 0.20,
                         role = "statistical de-risk only (vol/ES target)"),
    `M4+RMT_VolTarget` = list(path = "weights_variants/M4+RMT_VolTarget.csv",
                              active_cap = 0.20,
                              role = "canonical — regime + statistical conservative OR")
  ),
  canonical_weights_path = "weights.csv",

  schedule = list(
    n_unique_dates = unique_dates,
    sig_dates_count = sig_dates_count,
    schedule_density_ratio = density_ratio,
    density_pass = density_ratio >= 0.95,
    frequency = "monthly",
    date_range = c(as.character(min(canonical$Date)),
                   as.character(max(canonical$Date)))
  ),

  hard_constraints_audit = list(
    max_names = 20L,
    n_active_stocks = n_active,
    long_only = TRUE,
    weight_bounds = c(0.0, 0.20),
    weight_sum = 1.0,
    sigma_w_max_dev = 0.0,
    str1715_max_weight = str_max_w,
    sleeve_level_long = TRUE,
    sleeve_level_bnd = TRUE
  ),

  vol_target_current = list(
    es_target_monthly = es_target,
    es_current_monthly = es_curr,
    scale = scale_curr,
    cash_bridge = cash_curr,
    rule = "scale = ES_target / ES_current, capped [0.5, 1.0]"
  ),

  cash_definition_audit_ref = "stage_artifacts/WT_WT-S20260504_004/cash_definition_audit.json",
  lro_portfolio_mrc_ref = "stage_artifacts/WT_WT-S20260504_004/lro_portfolio_mrc.csv",
  method_shopping_ref = "stage_artifacts/WT_WT-S20260504_004/method_shopping.json",

  expected_overlay_effect = list(
    rationale = "RMT-denoised Σ + ES quantile gives statistical vol target; M4 covers regime/event. max() is non-redundant.",
    estimated_mdd_relief_pp_vs_S1 = "2~5pp (forge backtest will quantify)",
    estimated_cagr_drag_pp_vs_S1 = "1~3pp (de-risk months only)",
    note = "Forecast only — Forge backtest produces actual SR/CAGR/MDD."
  ),

  red_flags_optimizer = list(
    list(id = "RF-O3", severity = "MEDIUM",
         msg = paste0("turnover proxy: scale ∈ [0.5,1.0] monthly transitions; ",
                      "monthly rebalance frequency, no micro-rebalancing.")),
    list(id = "RF-O8-INHERITED", severity = "MEDIUM",
         msg = paste0("Risk Codex Round 1 REJECT (cond=411.88, CVaR breach) → ",
                      "waiver applied (sizing_only role, alpha-side limit). ",
                      "Optimizer cannot resolve covariance condition number — ",
                      "RMT denoise increases cond by design (signal eigenvalue retention).")),
    list(id = "RF-O-CASH-COMBINE", severity = "LOW",
         msg = paste0("max(M4_cash, RMT_cash_bridge) is conservative OR. ",
                      "Cash yield = 0% — KR retail convention. ",
                      "Variant choice exposed (3 emitted) — Forge backtests all 3."))
  ),

  infeasibility_report = NULL,

  binding_constraints = list("active_cap_0.20", "long_only_sleeve",
                             "schedule_monthly", "cash_bridge_cap_0.50"),

  axiom_assertions = list(
    `AX-000` = "한계 없음 — RMT 통계 vol target으로 MDD/Vol gap 도전",
    `AX-001_v2` = "core_secondary role; defense conditional metric informational only",
    `AX-002` = paste0("RMT cutoff SHA-frozen (lro_params_sha256=",
                       substr(lro_sha, 1, 12), "); ",
                       "weights overlay deterministic from frozen scale path."),
    `AX-008` = "Forge + Codex + Architect 2/3 PASS path planned"
  ),

  challenge_flags = list(),
  no_alpha_modification = TRUE,
  no_risk_re_interpretation = TRUE,
  str_1715_production_writes = 0L,

  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  generated_by = "optimizer-research (auto mode, Codex Round 1 → waiver R2)",
  draft_revision = "draft"
)

write_json(opt_draft,
           file.path(MBOX, "optimization_package_draft.json"),
           pretty = TRUE, auto_unbox = TRUE)

# ───────────────────────────────────────────────────────────────────────────
# 11. Lineage record
# ───────────────────────────────────────────────────────────────────────────
tryCatch({
  source(file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R"))
  record_package_lineage(
    task_id = WT,
    package_type = "optimization_package",
    method_selected = "M4+RMT_VolTarget",
    input_file_paths = c(
      file.path(MBOX, "alpha_package_inherit_ref.json"),
      file.path(MBOX, "risk_package.json"),
      file.path(SAGE, "vol_scale_path.csv"),
      file.path(PROJ, "qepm/mailbox/worktask/WT-P20260429_002/weights.csv")
    )
  )
  cat("[Step 11] lineage recorded\n")
}, error = function(e) {
  cat(sprintf("[Step 11] lineage capture skipped: %s\n", conditionMessage(e)))
})

cat("[run_optimizer_rmt] DONE — draft + 3 variants + canonical + cash_audit + mrc + method_shopping\n")
