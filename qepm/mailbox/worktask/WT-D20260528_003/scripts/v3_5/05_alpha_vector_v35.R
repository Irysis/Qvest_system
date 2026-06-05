#==============================================================================
# Step 5 — Alpha Vector Computation v3.5
#
# Formula:
#   α̂(i, t) = Σ_f w_f(regime_state(t-1), t) × F_f(i, t)
#     where F_f(i, t) = Z_aligned of family f for stock i at sig_date t
#
# v3.5 PIT compliance:
#   - regime_state(t-1) via Step 4 weight matrix (already PIT-safe)
#   - F_f(i, t) via Step 2 panel (Z_aligned via load_month_factors PIT-safe expanding IC)
#
# Output:
#   - stage_artifacts/WT_D20260528_003_v3_5/alpha_scores_v35.parquet
#     columns: Date, Ticker, alpha_score, regime_state_used
#==============================================================================

suppressPackageStartupMessages({
  library(arrow)
  library(data.table)
  library(jsonlite)
})

BASE <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT_DIR <- file.path(BASE, "qepm/mailbox/worktask/WT-D20260528_003/outputs/v3_5")
STAGE_DIR <- file.path(BASE, "stage_artifacts/WT_D20260528_003_v3_5")
PANEL_PATH <- file.path(OUT_DIR, "k200_factor_panel_v35.parquet")
WEIGHT_PATH <- file.path(OUT_DIR, "regime_factor_weight_matrix_v35_walkforward.parquet")

SIGNAL_CUTOFF <- as.Date("2023-12-22")
FAMILIES <- c("value","quality","momentum","growth","consensus","low_vol","size","dividend")

cat("[Alpha Vector v3.5] === START ===\n")
t0 <- Sys.time()

# ---- 1. Load panel + weights ----
panel <- as.data.table(read_parquet(PANEL_PATH))
panel[, Date := as.Date(Date)]
cat("[1] panel rows:", nrow(panel), "\n")

w <- as.data.table(read_parquet(WEIGHT_PATH))
w[, sig_date := as.Date(sig_date)]
cat("    weight matrix rows:", nrow(w), " | unique sig_dates:", length(unique(w$sig_date)), "\n")

# Pivot weight matrix to wide (family x sig_date → row=sig_date col=F_family weight)
w_wide <- dcast(w, sig_date + regime_state ~ family, value.var = "weight")
cat("    weight wide shape:", nrow(w_wide), "x", ncol(w_wide), "\n")

# ---- 2. Per sig_date: alpha_score(i,t) = Σ w_f × F_f(i,t) ----
cat("[2] Per-sig_date alpha computation ...\n")
result_list <- list()
sig_dates <- sort(unique(panel$Date))
sig_dates <- sig_dates[sig_dates %in% w_wide$sig_date]
cat("    sig_dates with weight available:", length(sig_dates), "\n")

for (sig_d in sig_dates) {
  sig_d <- as.Date(sig_d)
  pn <- panel[Date == sig_d]
  wd <- w_wide[sig_date == sig_d]
  if (nrow(wd) == 0L) next
  reg_st <- wd$regime_state[1]
  fam_cols <- paste0("F_", FAMILIES)
  fam_panel <- as.matrix(pn[, ..fam_cols])
  fam_panel[is.na(fam_panel)] <- 0  # treat missing factor as 0 (no contribution)
  weight_vec <- as.numeric(wd[, ..FAMILIES])
  if (length(weight_vec) != length(FAMILIES)) next

  alpha_scores <- as.numeric(fam_panel %*% weight_vec)
  result_list[[length(result_list) + 1L]] <- data.table(
    Date = sig_d,
    Ticker = pn$Ticker,
    alpha_score = alpha_scores,
    regime_state_used = reg_st
  )
}

alpha_dt <- rbindlist(result_list, use.names = TRUE)
setorder(alpha_dt, Date, -alpha_score)
cat("    alpha rows:", nrow(alpha_dt), " | sig_dates:", length(unique(alpha_dt$Date)), "\n")

# ---- 3. Sanity diag per sig_date ----
diag_per_d <- alpha_dt[, .(
  n_stocks = .N,
  n_pos = sum(alpha_score > 0, na.rm = TRUE),
  n_neg = sum(alpha_score < 0, na.rm = TRUE),
  alpha_mean = round(mean(alpha_score, na.rm = TRUE), 4),
  alpha_sd = round(sd(alpha_score, na.rm = TRUE), 4),
  alpha_q05 = round(quantile(alpha_score, 0.05, na.rm = TRUE), 4),
  alpha_q95 = round(quantile(alpha_score, 0.95, na.rm = TRUE), 4)
), by = Date]
cat("[3] Per sig_date alpha diag (first 3):\n")
print(head(diag_per_d, 3))

# ---- 4. Output ----
write_parquet(alpha_dt, file.path(STAGE_DIR, "alpha_scores_v35.parquet"))
write_parquet(alpha_dt, file.path(OUT_DIR, "alpha_scores_v35.parquet"))

# Final-date alpha_vector for handoff
last_date <- max(alpha_dt$Date)
last_dt <- alpha_dt[Date == last_date]
setorder(last_dt, -alpha_score)
alpha_vector <- setNames(round(last_dt$alpha_score, 4), last_dt$Ticker)

meta <- list(
  spec = "v3.5 α̂(i,t) = Σ_f w_f(state(t-1)) × F_f(i,t). Long-only weight, normalized sum=1.",
  pit_compliance = list(
    C9_regime_t_minus_1 = TRUE,
    C13_z_aligned_only = TRUE,
    C15_load_month_factors = TRUE
  ),
  n_sig_dates = length(unique(alpha_dt$Date)),
  n_alpha_obs = nrow(alpha_dt),
  date_range = c(as.character(min(alpha_dt$Date)), as.character(max(alpha_dt$Date))),
  families = FAMILIES,
  last_date = as.character(last_date),
  last_date_alpha_vector_head = head(alpha_vector, 20),
  last_date_alpha_vector_tail = tail(alpha_vector, 20),
  per_sig_date_diag_summary = diag_per_d,
  built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
)
writeLines(toJSON(meta, pretty = TRUE, auto_unbox = TRUE, na = "null"),
            file.path(OUT_DIR, "alpha_scores_v35.meta.json"))

cat("\n[Alpha Vector v3.5] === DONE === elapsed:",
    round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2), "min\n")
