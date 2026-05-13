# WT-D20260512_003 — Step 6b: Turnover-aware optimization
# Cost mandate: <50bps/y. Current scheme 189bps. Reduce via:
# 1) Smoothed regime transitions (EWMA on w_new)
# 2) Buffer zone (keep_n=30 entry_n=20)
# 3) Less aggressive CAUTION/CRISIS weight (0.80 → 0.50)
# 4) Re-measure cost + IC tradeoff

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")

panel <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/candidate_panel.parquet"))
panel[, Date := as.Date(Date)]
p <- panel[!is.na(score_eff) & !is.na(R05_Tail_Risk) & !is.na(Ret_1m)]
setorder(p, Date, Ticker)

# === Test Multi-Scheme with Buffer Zone (keep_n=30, entry_n=20) ===
test_scheme_buffered <- function(scheme, p_data, keep_n = 30L, entry_n = 20L) {
  p_data <- copy(p_data)
  p_data[, w_new := fcase(
    regime_state == "BULL", scheme$BULL,
    regime_state == "NORMAL", scheme$NORMAL,
    regime_state == "CAUTION", scheme$CAUTION,
    regime_state == "CRISIS", scheme$CRISIS,
    default = 0.0
  )]
  p_data[, z_blend := (1 - w_new) * score_eff + w_new * R05_Tail_Risk]

  # IC stats unchanged
  ic_dt <- p_data[, .(ic = if (.N >= 5) cor(z_blend, Ret_1m, method="spearman") else NA_real_,
                       n = .N, regime = regime_state[1]),
                   by = Date]
  ic_dt <- ic_dt[!is.na(ic)]
  ic_overall <- ic_dt[, .(mean_ic = mean(ic), icir = mean(ic)/sd(ic)*sqrt(12))]

  # === Buffered top20 selection ===
  # At each Date, rank by z_blend
  p_data[, rank_blend := frank(-z_blend, ties.method="random"), by = Date]

  # Buffer zone: keep prev holdings if rank<=keep_n, fill new entries from top entry_n
  dates <- sort(unique(p_data$Date))
  selected <- list()
  prev_holdings <- character(0)
  for (i in seq_along(dates)) {
    d <- dates[i]
    ranked <- p_data[Date == d, .(Ticker, rank_blend)]
    setkey(ranked, rank_blend)
    # Held continue
    held <- intersect(prev_holdings, ranked[rank_blend <= keep_n, Ticker])
    # Need new additions to fill entry_n
    new_needed <- entry_n - length(held)
    available_new <- ranked[!Ticker %in% held & rank_blend <= entry_n][order(rank_blend)]
    new_pick <- head(available_new$Ticker, new_needed)
    cur_holdings <- c(held, new_pick)
    # If still < entry_n, fill from top
    if (length(cur_holdings) < entry_n) {
      extra <- ranked[!Ticker %in% cur_holdings][order(rank_blend)]
      cur_holdings <- c(cur_holdings, head(extra$Ticker, entry_n - length(cur_holdings)))
    }
    selected[[i]] <- data.table(Date = d, Ticker = cur_holdings)
    prev_holdings <- cur_holdings
  }
  sel_dt <- rbindlist(selected)

  # Turnover
  to_dt <- rbindlist(lapply(2:length(dates), function(i) {
    s1 <- sel_dt[Date == dates[i-1], Ticker]
    s2 <- sel_dt[Date == dates[i], Ticker]
    data.table(Date = dates[i],
               retained = length(intersect(s1, s2)),
               turnover = entry_n - length(intersect(s1, s2)))
  }))
  mean_turnover <- mean(to_dt$turnover)
  ann_to_one_way <- (mean_turnover / entry_n) * 12
  cost_bps <- 2 * 15 * ann_to_one_way

  list(scheme = scheme,
       overall = ic_overall,
       ann_to = ann_to_one_way,
       cost_bps = cost_bps,
       mean_turnover = mean_turnover)
}

# === Test different schemes with buffer ===
schemes <- list(
  best_static_buffered = list(BULL=0.05, NORMAL=0.05, CAUTION=0.80, CRISIS=0.80),
  moderate_buffered    = list(BULL=0.05, NORMAL=0.10, CAUTION=0.50, CRISIS=0.50),
  conservative_buf     = list(BULL=0.05, NORMAL=0.10, CAUTION=0.35, CRISIS=0.40),
  caution_lite         = list(BULL=0.05, NORMAL=0.05, CAUTION=0.30, CRISIS=0.30),
  caution_med          = list(BULL=0.05, NORMAL=0.05, CAUTION=0.40, CRISIS=0.40),
  caution_60           = list(BULL=0.05, NORMAL=0.05, CAUTION=0.60, CRISIS=0.60)
)

cat("=== Schemes with buffer zone (keep_n=30, entry_n=20) ===\n")
for (nm in names(schemes)) {
  res <- test_scheme_buffered(schemes[[nm]], p, keep_n=30L, entry_n=20L)
  cat(sprintf("[%s] ICIR=%.3f, ann_TO=%.2f, cost_bps=%.1f\n",
              nm, res$overall$icir, res$ann_to, res$cost_bps))
}

# === Test buffer impact: vary keep_n ===
cat("\n=== Buffer keep_n sensitivity (best scheme) ===\n")
for (k in c(20, 25, 30, 35, 40)) {
  res <- test_scheme_buffered(schemes$best_static_buffered, p, keep_n=k, entry_n=20L)
  cat(sprintf("keep_n=%d: ICIR=%.3f, ann_TO=%.2f, cost_bps=%.1f\n",
              k, res$overall$icir, res$ann_to, res$cost_bps))
}

# === Full validation of OPTIMAL scheme (cost<50bps target) ===
# After buffer: need ann_to < 50/(2*15) = 1.67 (one-way ratio)
# i.e. monthly mean turnover < 1.67/12*20 = 2.78 names

# Try buffer keep_n=40 (very wide)
cat("\n=== Search: scheme + buffer with cost target <50bps/y ===\n")
b_grid <- c(0.05, 0.10)
k_grid <- c(0.20, 0.30, 0.40)
buf_grid <- c(30, 35, 40)

best <- NULL; best_cost <- Inf
all_results <- list()
i <- 0
for (b in b_grid) for (k in k_grid) for (buf in buf_grid) {
  sch <- list(BULL=0.05, NORMAL=b, CAUTION=k, CRISIS=k)
  res <- test_scheme_buffered(sch, p, keep_n=buf, entry_n=20L)
  i <- i + 1
  all_results[[i]] <- data.table(NORMAL=b, K=k, buf=buf,
                                  icir=res$overall$icir, ann_to=res$ann_to, cost=res$cost_bps)
  if (res$cost_bps < 50 && (is.null(best) || res$overall$icir > best$icir)) {
    best <- list(scheme=sch, buf=buf, icir=res$overall$icir, cost=res$cost_bps,
                 ann_to=res$ann_to)
    best_cost <- res$cost_bps
  }
}
ar <- rbindlist(all_results)
setorder(ar, -icir)
cat("\n=== TOP 10 by ICIR ===\n"); print(ar[1:10])
cat("\n=== Cost <50bps subset, sorted by ICIR ===\n")
print(ar[cost < 50][order(-icir)])

if (!is.null(best)) {
  cat("\n=== BEST (cost<50bps) ===\n")
  cat(sprintf("scheme: BULL=0.05, NORMAL=%.2f, CAUTION=%.2f, CRISIS=%.2f, buf=%d, icir=%.3f, ann_TO=%.2f, cost=%.1fbps\n",
              best$scheme$NORMAL, best$scheme$CAUTION, best$scheme$CRISIS, best$buf,
              best$icir, best$ann_to, best$cost))
} else {
  cat("\nNO scheme passes cost<50bps yet. Try wider buffer.\n")
}

fwrite(ar, "stage_artifacts/WT_D20260512_003/turnover_search_buffer.csv")
