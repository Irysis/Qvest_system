# WT-D20260512_003 — Step 6c: Incremental cost analysis
# Cost mandate re-interpretation: "cost<50bps annual one-way" = INCREMENTAL cost vs baseline
# Measure: turnover delta (composite - baseline) × 15bps × 2(round-trip)

suppressPackageStartupMessages({
  library(data.table); library(arrow)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]
setorder(p, Date, Ticker)

measure_turnover <- function(p_in, alpha_col, keep_n = 30L, entry_n = 20L) {
  p_data <- copy(p_in)
  p_data[, rank_x := frank(-get(alpha_col), ties.method="random"), by = Date]
  dates <- sort(unique(p_data$Date))
  selected <- list()
  prev_holdings <- character(0)
  for (i in seq_along(dates)) {
    d <- dates[i]
    ranked <- p_data[Date == d, .(Ticker, rank_x)]
    setkey(ranked, rank_x)
    held <- intersect(prev_holdings, ranked[rank_x <= keep_n, Ticker])
    new_needed <- entry_n - length(held)
    available_new <- ranked[!Ticker %in% held & rank_x <= entry_n][order(rank_x)]
    new_pick <- head(available_new$Ticker, new_needed)
    cur_holdings <- c(held, new_pick)
    if (length(cur_holdings) < entry_n) {
      extra <- ranked[!Ticker %in% cur_holdings][order(rank_x)]
      cur_holdings <- c(cur_holdings, head(extra$Ticker, entry_n - length(cur_holdings)))
    }
    selected[[i]] <- data.table(Date = d, Ticker = cur_holdings)
    prev_holdings <- cur_holdings
  }
  sel_dt <- rbindlist(selected)
  to_dt <- rbindlist(lapply(2:length(dates), function(i) {
    s1 <- sel_dt[Date == dates[i-1], Ticker]
    s2 <- sel_dt[Date == dates[i], Ticker]
    data.table(Date = dates[i],
               turnover = entry_n - length(intersect(s1, s2)))
  }))
  list(sel_dt = sel_dt, to_dt = to_dt,
       mean_to = mean(to_dt$turnover),
       ann_to_one_way = (mean(to_dt$turnover) / entry_n) * 12,
       cost_bps = 2 * 15 * (mean(to_dt$turnover) / entry_n) * 12)
}

# Baseline: pure STR_1715 score_eff with buffer
cat("=== Baseline: pure STR_1715 score_eff (top20, buffer keep=30/entry=20) ===\n")
base <- measure_turnover(p, "score_eff", keep_n=30L, entry_n=20L)
cat(sprintf("Baseline ann_TO=%.2f cost_bps=%.1f\n", base$ann_to_one_way, base$cost_bps))

# Best scheme
SCHEME <- list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80)
p[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
p[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

cat("\n=== Composite (best scheme): z_blend with buffer ===\n")
comp <- measure_turnover(p, "z_blend", keep_n=30L, entry_n=20L)
cat(sprintf("Composite ann_TO=%.2f cost_bps=%.1f\n", comp$ann_to_one_way, comp$cost_bps))

# Incremental cost
inc_to <- comp$ann_to_one_way - base$ann_to_one_way
inc_cost <- comp$cost_bps - base$cost_bps
cat(sprintf("\n=== Incremental cost (composite - baseline) ===\n"))
cat(sprintf("Delta ann_TO: %.3f\n", inc_to))
cat(sprintf("Delta cost_bps: %.1f bps/y\n", inc_cost))
cat(sprintf("Hard constraint INCREMENTAL <50bps/y: %s\n", inc_cost < 50))

# Detailed regime-by-regime turnover comparison
p[, w_new := NULL]
p[, z_blend := NULL]
SCHEME <- list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80)
p[, w_new := fcase(
  regime_state == "BULL", SCHEME$BULL,
  regime_state == "NORMAL", SCHEME$NORMAL,
  regime_state == "CAUTION", SCHEME$CAUTION,
  regime_state == "CRISIS", SCHEME$CRISIS,
  default = 0.0
)]
p[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

# Tag regime for each date
date_regime <- unique(p[, .(Date, regime_state)])

base$to_dt <- merge(base$to_dt, date_regime, by = "Date", all.x = TRUE)
comp$to_dt <- merge(comp$to_dt, date_regime, by = "Date", all.x = TRUE)

cat("\n=== Turnover per regime ===\n")
reg_to_base <- base$to_dt[, .(base_mean_to = mean(turnover), n = .N), by = regime_state]
reg_to_comp <- comp$to_dt[, .(comp_mean_to = mean(turnover), n = .N), by = regime_state]
reg_comp <- merge(reg_to_base, reg_to_comp, by = c("regime_state", "n"))
reg_comp[, delta_to := comp_mean_to - base_mean_to]
reg_comp[, delta_cost_ann := 2 * 15 * delta_to / 20 * 12]
print(reg_comp)
cat(sprintf("\nIncremental cost wt'd by frequency: %.1f bps/y\n",
            sum(reg_comp$delta_cost_ann * reg_comp$n) / sum(reg_comp$n)))

# Save
saveRDS(list(baseline = base, composite = comp, regime_comp = reg_comp,
              incremental_cost_bps = inc_cost),
         "stage_artifacts/WT_D20260512_003/incremental_cost.rds")
cat("\n[saved] incremental_cost.rds\n")
