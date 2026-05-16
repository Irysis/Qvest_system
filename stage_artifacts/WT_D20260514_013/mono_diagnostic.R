#==============================================================================
# Mono diagnostic deep-dive
# Question: why does M6 lockbox mono drop from 0.99 (full ML panel) to -0.61
# (STR_1715 universe overlap, KOSPI200∪KOSDAQ150 + LIQ≥2e8)?
#
# Hypotheses:
# H1: STR_1715 universe filters to LARGE liquid stocks → ML alpha trained on
#     small-cap heavy panel may invert in large-cap universe (small-firm bias).
# H2: STR_1715 Ret_1m field is NOT the same return convention as ML training target
#     (e.g., ML trained on log-return / forward 1M, STR_1715 may use spot 1M).
# H3: Decile rank within reduced universe (~250 stocks) ≠ rank within full ML
#     panel (~2,600 stocks). High-alpha decile in subset may not be high in panel.
#==============================================================================
suppressPackageStartupMessages({
  library(arrow); library(data.table)
})

# Reload
m6 <- as.data.table(read_parquet("stage_artifacts/WT_D20260514_014_phase1_full/predictions.parquet"))[model == "M6_Ensemble"]
m6[, sig_date := as.Date(sig_date)]
m6[, ym_signal := format(sig_date, "%Y-%m")]

s1 <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet"))
s1[, sig_date_str := as.Date(Date)]
s1[, ym_signal := format(sig_date_str - 1, "%Y-%m")]

cat("=== H3 test: decile-rank within FULL ML panel vs STR_1715 overlap ===\n")
# Full-panel decile rank
m6_lockbox <- m6[mode == "lockbox"]
m6_lockbox[, alpha_decile_full := cut(frank(-score, ties.method = "average") / .N,
                                        breaks = seq(0, 1, 0.1), labels = 1:10,
                                        include.lowest = TRUE),
            by = sig_date]

# Bring in STR_1715 ret_1m
ret <- s1[, .(ym_signal, Ticker, ret_1m = Ret_1m)]
m6_lb_ret <- merge(m6_lockbox, ret, by = c("ym_signal", "Ticker"), all.x = TRUE)
m6_lb_ret_overlap <- m6_lb_ret[!is.na(ret_1m)]
m6_lb_ret_full <- copy(m6_lb_ret)  # includes NA ret_1m (stocks not in STR_1715 universe)

cat("\nLockbox panel:\n")
cat("  Total rows:", nrow(m6_lockbox), "\n")
cat("  With STR_1715 ret_1m (overlap):", nrow(m6_lb_ret_overlap), "\n")
cat("  Coverage:", sprintf("%.1f%%", 100 * nrow(m6_lb_ret_overlap) / nrow(m6_lockbox)), "\n")

# Full-panel decile statistics on overlap subset
cat("\n--- Full-panel decile rank, mean ret_1m on STR_1715 overlap ---\n")
dec_full <- m6_lb_ret_overlap[, .(mean_ret = mean(ret_1m, na.rm = TRUE),
                                    n = .N,
                                    mean_score = mean(score)), by = alpha_decile_full]
setorder(dec_full, alpha_decile_full)
print(dec_full)
mono_full_panel_rank <- cor(as.integer(dec_full$alpha_decile_full),
                              dec_full$mean_ret, method = "spearman")
cat(sprintf("Mono (full-panel decile rank, overlap subset): %.4f\n", mono_full_panel_rank))

# Now within-overlap decile rank
m6_lb_ret_overlap[, alpha_decile_within := cut(frank(-score, ties.method = "average") / .N,
                                                  breaks = seq(0, 1, 0.1), labels = 1:10,
                                                  include.lowest = TRUE),
                    by = sig_date]
cat("\n--- Within-overlap decile rank, mean ret_1m ---\n")
dec_within <- m6_lb_ret_overlap[, .(mean_ret = mean(ret_1m, na.rm = TRUE),
                                      n = .N,
                                      mean_score = mean(score)), by = alpha_decile_within]
setorder(dec_within, alpha_decile_within)
print(dec_within)
mono_within <- cor(as.integer(dec_within$alpha_decile_within),
                     dec_within$mean_ret, method = "spearman")
cat(sprintf("Mono (within-overlap decile rank): %.4f\n", mono_within))

# Quintile (5-bucket) check — less noisy
m6_lb_ret_overlap[, alpha_quintile := cut(frank(-score, ties.method = "average") / .N,
                                            breaks = seq(0, 1, 0.2), labels = 1:5,
                                            include.lowest = TRUE),
                    by = sig_date]
dec_q5 <- m6_lb_ret_overlap[, .(mean_ret = mean(ret_1m, na.rm = TRUE),
                                  n = .N,
                                  mean_score = mean(score)), by = alpha_quintile]
setorder(dec_q5, alpha_quintile)
cat("\n--- Within-overlap QUINTILE (5-bucket) ---\n")
print(dec_q5)
mono_q5 <- cor(as.integer(dec_q5$alpha_quintile), dec_q5$mean_ret, method = "spearman")
cat(sprintf("Mono Q5 (within-overlap): %.4f\n", mono_q5))

# Top decile vs bottom decile spread
top_dec_ret <- m6_lb_ret_overlap[alpha_decile_within == "1", mean(ret_1m, na.rm = TRUE)]
bot_dec_ret <- m6_lb_ret_overlap[alpha_decile_within == "10", mean(ret_1m, na.rm = TRUE)]
cat(sprintf("\nTop-decile mean ret: %.4f\n", top_dec_ret))
cat(sprintf("Bot-decile mean ret: %.4f\n", bot_dec_ret))
cat(sprintf("Spread: %.4f\n", top_dec_ret - bot_dec_ret))

# Spearman rank IC pooled on overlap
ic_overlap_pooled <- cor(m6_lb_ret_overlap$score, m6_lb_ret_overlap$ret_1m, method = "spearman")
cat(sprintf("\nPooled Spearman IC (overlap, lockbox): %.4f\n", ic_overlap_pooled))

# Also check by sig_date IC mean
ic_per_date <- m6_lb_ret_overlap[, .(rank_ic = cor(score, ret_1m, method = "spearman", use = "complete.obs"),
                                        n = .N), by = sig_date]
cat(sprintf("Per-sig_date IC: mean=%.4f / median=%.4f / sd=%.4f / ICIR=%.4f / n_months=%d\n",
            mean(ic_per_date$rank_ic, na.rm = TRUE),
            median(ic_per_date$rank_ic, na.rm = TRUE),
            sd(ic_per_date$rank_ic, na.rm = TRUE),
            mean(ic_per_date$rank_ic, na.rm = TRUE) / sd(ic_per_date$rank_ic, na.rm = TRUE),
            nrow(ic_per_date)))

# Hypothesis: Top-30 (Production bi-monthly pre-selection) returns
cat("\n=== Top-30 (Production-safe pre-selection) per sig_date ===\n")
top30_perf <- m6_lb_ret_overlap[, {
  ord <- order(-score)
  top30 <- head(ord, 30)
  list(top30_mean_ret = mean(ret_1m[top30], na.rm = TRUE),
       universe_mean_ret = mean(ret_1m, na.rm = TRUE),
       active_ret = mean(ret_1m[top30], na.rm = TRUE) - mean(ret_1m, na.rm = TRUE),
       n_universe = .N)
}, by = sig_date]
cat(sprintf("Top-30 active ret (vs universe mean): mean=%.4f / median=%.4f / n_months=%d\n",
            mean(top30_perf$active_ret, na.rm = TRUE),
            median(top30_perf$active_ret, na.rm = TRUE),
            nrow(top30_perf)))
cat(sprintf("Top-30 SR proxy (active ret * sqrt(12) / sd): %.4f\n",
            mean(top30_perf$active_ret, na.rm = TRUE) * sqrt(12) /
              sd(top30_perf$active_ret, na.rm = TRUE)))
