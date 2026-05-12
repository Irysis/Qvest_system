#==============================================================================
# WT-D20260508_004 — Step 8: Fix alpha_scores.parquet (Codex C1: RF-A7)
#
# Codex 지적: alpha_scores.parquet이 단일 ym snapshot.
# 정정: full time-series (Date_eom × Ticker × alpha_z) 저장.
# 추가: qepm/stage_artifacts/WT_WT-D20260508_004 alias path도 동시 보존.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
OUT  <- file.path(PROJ, "stage_artifacts", "WT_D20260508_004")
WT_ID <- "WT-D20260508_004"

# Full panel
mm <- as.data.table(read_parquet(file.path(OUT, "alpha_panel.parquet")))

# Keep all months ≥ 2013-01 (post-burn) where alpha is non-NA
ts <- mm[ym >= "2013-01" & !is.na(alpha) & eligible == TRUE,
         .(Ticker, ym, Date_eom, Sector,
           alpha_z = alpha,
           alpha_sn_z = alpha_sn,
           alpha_active_1m = alpha * 0.012 / 12,   # 1.2%/yr per 1σ → monthly
           alpha_active_12m = alpha * 0.012,
           n_used,
           FwdRet_1M, FwdRet_6M, FwdRet_12M)]
setorder(ts, Date_eom, Ticker)

# Confidence (same heuristic)
ts[, confidence := pmin(1, pmax(0,
  0.3 +
  0.3 * (n_used / 4) +
  0.2 * pmin(abs(alpha_z) / 2, 1) +
  0.2 * (1 - 1 * (abs(alpha_z) > 4))
))]

write_parquet(ts, file.path(OUT, "alpha_scores.parquet"))
cat("[08] alpha_scores.parquet rewritten as time-series:\n")
cat("  rows:", nrow(ts), "\n")
cat("  unique Ticker:", uniqueN(ts$Ticker), "\n")
cat("  unique Date_eom:", uniqueN(ts$Date_eom), "\n")
cat("  date range:", as.character(min(ts$Date_eom)), "to",
    as.character(max(ts$Date_eom)), "\n")

# Also save to qepm/stage_artifacts alias (codex suggested path)
alias_dir <- file.path(PROJ, "qepm", "stage_artifacts", paste0("WT_", WT_ID))
dir.create(alias_dir, showWarnings = FALSE, recursive = TRUE)
write_parquet(ts, file.path(alias_dir, "alpha_scores.parquet"))
cat("[08] also saved alias:", alias_dir, "\n")

# Forward-only snapshot for compatibility
fwd_only <- ts[ym == max(ym)]
write_parquet(fwd_only, file.path(OUT, "alpha_scores_forward_2026-04.parquet"))
cat("[08] forward-only snapshot saved separately:", nrow(fwd_only), "rows for ym=",
    max(ts$ym), "\n")
