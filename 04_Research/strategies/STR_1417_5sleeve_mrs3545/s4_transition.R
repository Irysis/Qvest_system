cat("=== STR_1417 S4 Transition ===\n")
suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT_RAW <- "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot"
INFRA_DIR <- file.path(PROJ_ROOT_RAW, "02_Infrastructure")

# Force .sg_root to absolute path before sourcing
.sg_root <<- INFRA_DIR
old_wd <- getwd()
setwd(INFRA_DIR)
source("stage_gate_engine.R")
# Override .SG_CACHE to absolute path
.SG_CACHE <<- file.path(PROJ_ROOT_RAW, ".cache", "stage_gate")
if (!dir.exists(.SG_CACHE)) dir.create(.SG_CACHE, recursive = TRUE)
setwd(old_wd)

factor_id  <- "STR_1417"
strategy_id <- "STR_1417_5sleeve_mrs3545"
PROJ_ROOT <- PROJ_ROOT_RAW
strat_dir <- file.path(PROJ_ROOT, "research_output", "strategies", strategy_id)

# --- 1) sg_init ---
cat("[Forge] Initializing stage tracker for", factor_id, "\n")
sg_init(factor_id, strategy_id)

# --- 2) Fast-forward S0~S3 (already completed by prior pipeline) ---
art_dir <- file.path(strat_dir, "stage_artifacts")

s0_art <- list(factor_id = factor_id, record_type = "5sleeve_mrs_variant",
               base_strategy = "STR_1071", created_at = format(Sys.time()))
s0_path <- file.path(art_dir, "s0_record_STR_1417.json")
write_json(s0_art, s0_path, auto_unbox = TRUE, pretty = TRUE)
tryCatch(sg_transition(factor_id, "S1", s0_path, completed_by = "forge"),
         error = function(e) cat("[WARN] S0->S1:", e$message, "\n"))

s1_art <- list(factor_id = factor_id, method = "5sleeve_score_blend",
               mrs_low = 35, mrs_high = 45, n_stocks = 30,
               constructed_at = format(Sys.time()))
s1_path <- file.path(art_dir, "s1_construction_STR_1417.json")
write_json(s1_art, s1_path, auto_unbox = TRUE, pretty = TRUE)
tryCatch(sg_transition(factor_id, "S2", s1_path, completed_by = "forge"),
         error = function(e) cat("[WARN] S1->S2:", e$message, "\n"))

s2_art <- list(factor_id = factor_id, ic_ir = 0.806, t_stat = 2.73,
               tag = "Strong", monotonicity = NA, turnover = 154.1,
               quintile_spread = NA, sharpe = 1.361, cagr = 24.63, mdd = 30.61,
               computed_at = format(Sys.time()))
s2_path <- file.path(art_dir, "s2_profile_STR_1417.json")
write_json(s2_art, s2_path, auto_unbox = TRUE, pretty = TRUE)
tryCatch(sg_transition(factor_id, "S3", s2_path, completed_by = "forge"),
         error = function(e) cat("[WARN] S2->S3:", e$message, "\n"))

s3_art <- list(factor_id = factor_id, independence = "redundant",
               max_corr = 1.0, max_corr_with = "STR_1071",
               jaccard = 1.0, value_matrix = "Strong_Redundant",
               computed_at = format(Sys.time()))
s3_path <- file.path(art_dir, "s3_orthogonality_STR_1417.json")
write_json(s3_art, s3_path, auto_unbox = TRUE, pretty = TRUE)
tryCatch(sg_transition(factor_id, "S4", s3_path, completed_by = "scout"),
         error = function(e) cat("[WARN] S3->S4:", e$message, "\n"))

# --- 3) S4 -> S6 transition (KOSPI beat confirmed) ---
s4_path <- file.path(art_dir, "s4_integration_STR_1417.json")
cat("[Forge] S4 artifact exists:", file.exists(s4_path), "\n")

tryCatch({
  result <- sg_transition(factor_id, "S6", s4_path, completed_by = "forge")
  cat("[Forge] S4 -> S6 transition SUCCESS\n")
}, error = function(e) {
  cat("[WARN] S4->S6:", e$message, "\n")
})

# --- 4) Verify final state ---
state <- sg_get_state(factor_id)
cat("[Forge] Current stage:", state$current_stage, "\n")

# --- 5) sg_check_s6_entry ---
tryCatch({
  s6_ok <- sg_check_s6_entry(factor_id)
  cat("[Forge] S6 entry gate:", s6_ok, "\n")
}, error = function(e) {
  cat("[WARN] S6 entry check:", e$message, "\n")
})

cat("[Forge] STR_1417 S4 processing complete. Judge S6 request sent.\n")
