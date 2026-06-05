## ──────────────────────────────────────────────────────────────────────────────
## Alpha Source Correlation Analysis
## 2026-03-14  |  Q-Lead
## ──────────────────────────────────────────────────────────────────────────────

suppressPackageStartupMessages({
  library(xts)
  library(data.table)
  library(ggplot2)
})

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
OUT_DIR <- file.path(ROOT, "research_output", "regime_analysis")

# ─── 1. Load all sim results ─────────────────────────────────────────────────
strategies <- list(
  "STR_840\nRevBreadth+SUE"   = "STR_840_breadth_sue_ivol65",
  "STR_857\nInfoAsym"          = "STR_857_analyst_disagree",
  "STR_855\nConsensusMom"      = "STR_855_pure_consensus_mom",
  "STR_889\nRevRevision"       = "STR_889_revenue_revision",
  "STR_890\nSUE_Streak"        = "STR_890_sue_streak"
)

# Short names for text output
short_names <- c("STR_840", "STR_857", "STR_855", "STR_889", "STR_890")

daily_list   <- list()
monthly_list <- list()
bm_monthly   <- NULL

for (nm in names(strategies)) {
  fpath <- file.path(ROOT, "research_output", "strategies", strategies[[nm]], "sim_result.rds")
  if (!file.exists(fpath)) {
    cat("[SKIP] Not found:", fpath, "\n")
    next
  }
  sim <- readRDS(fpath)
  strat_xts <- sim$strategy_xts
  colnames(strat_xts) <- nm

  # Monthly returns (compound daily)
  mret <- apply.monthly(strat_xts, function(x) prod(1 + x) - 1)
  colnames(mret) <- nm

  daily_list[[nm]]   <- strat_xts
  monthly_list[[nm]] <- mret

  # Grab benchmark once

if (is.null(bm_monthly)) {
    bm_xts <- sim$bm_xts
    colnames(bm_xts) <- "KOSPI200"
    bm_monthly <- apply.monthly(bm_xts, function(x) prod(1 + x) - 1)
    colnames(bm_monthly) <- "KOSPI200"
  }
}

cat(sprintf("\n=== Loaded %d strategies ===\n", length(monthly_list)))

# ─── 2. Merge monthly returns ────────────────────────────────────────────────
monthly_merged <- do.call(merge, monthly_list)
# Trim to common date range
monthly_merged <- na.omit(monthly_merged)
cat(sprintf("Common period: %s ~ %s  (%d months)\n",
            index(monthly_merged)[1], tail(index(monthly_merged), 1), nrow(monthly_merged)))

# Add benchmark
monthly_all <- merge(monthly_merged, bm_monthly)
monthly_all <- na.omit(monthly_all)

# ─── 3. Correlation matrix (strategy-only) ──────────────────────────────────
cor_mat <- cor(monthly_merged, use = "pairwise.complete.obs")
cat("\n=== Monthly Return Correlation Matrix ===\n")
print(round(cor_mat, 3))

# Correlation with benchmark
bm_cor <- cor(monthly_all, use = "pairwise.complete.obs")
cat("\n=== Correlation with KOSPI200 ===\n")
bm_col <- bm_cor[, "KOSPI200"]
bm_col <- bm_col[names(bm_col) != "KOSPI200"]
for (i in seq_along(bm_col)) {
  cat(sprintf("  %s : %.3f\n", names(bm_col)[i], bm_col[i]))
}

# ─── 4. Key findings ────────────────────────────────────────────────────────
n <- ncol(cor_mat)
pairs_df <- data.frame(A = character(), B = character(), corr = numeric(), stringsAsFactors = FALSE)
for (i in 1:(n-1)) {
  for (j in (i+1):n) {
    pairs_df <- rbind(pairs_df, data.frame(
      A = colnames(cor_mat)[i],
      B = colnames(cor_mat)[j],
      corr = cor_mat[i, j],
      stringsAsFactors = FALSE
    ))
  }
}
pairs_df <- pairs_df[order(pairs_df$corr), ]

low_corr  <- pairs_df[pairs_df$corr < 0.5, ]
high_corr <- pairs_df[pairs_df$corr > 0.8, ]

cat("\n=== Pairs with correlation < 0.5 (good for ensemble) ===\n")
if (nrow(low_corr) > 0) {
  for (r in 1:nrow(low_corr)) {
    cat(sprintf("  %s <-> %s : %.3f\n", low_corr$A[r], low_corr$B[r], low_corr$corr[r]))
  }
} else cat("  (none)\n")

cat("\n=== Pairs with correlation > 0.8 (redundant) ===\n")
if (nrow(high_corr) > 0) {
  for (r in 1:nrow(high_corr)) {
    cat(sprintf("  %s <-> %s : %.3f\n", high_corr$A[r], high_corr$B[r], high_corr$corr[r]))
  }
} else cat("  (none)\n")

# ─── 5. Heatmap ─────────────────────────────────────────────────────────────
melted <- data.table(
  Strategy1 = rep(rownames(cor_mat), ncol(cor_mat)),
  Strategy2 = rep(colnames(cor_mat), each = nrow(cor_mat)),
  Correlation = as.vector(cor_mat)
)

p_heat <- ggplot(melted, aes(x = Strategy1, y = Strategy2, fill = Correlation)) +
  geom_tile(color = "white", linewidth = 0.5) +
  geom_text(aes(label = sprintf("%.2f", Correlation)), color = "black", size = 4.5, fontface = "bold") +
  scale_fill_gradient2(low = "#2166AC", mid = "white", high = "#B2182B",
                       midpoint = 0, limits = c(-1, 1), name = "Corr") +
  labs(title = "Alpha Source Correlation Matrix (Monthly Returns)",
       subtitle = sprintf("Period: %s ~ %s | %d months",
                           index(monthly_merged)[1], tail(index(monthly_merged), 1), nrow(monthly_merged)),
       x = "", y = "") +
  theme_minimal(base_size = 13) +
  theme(
    axis.text.x = element_text(angle = 30, hjust = 1, size = 10),
    axis.text.y = element_text(size = 10),
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(size = 11, color = "grey40"),
    panel.grid = element_blank()
  ) +
  coord_fixed()

heatmap_path <- file.path(OUT_DIR, "alpha_correlation_matrix.png")
ggsave(heatmap_path, p_heat, width = 10, height = 8, dpi = 150)
cat(sprintf("\n[OK] Heatmap saved: %s\n", heatmap_path))

# ─── 6. Rolling 36M correlation ─────────────────────────────────────────────
rolling_window <- 36  # months
n_obs <- nrow(monthly_merged)

if (n_obs > rolling_window) {
  rolling_results <- list()
  for (r in 1:nrow(pairs_df)) {
    a <- pairs_df$A[r]
    b <- pairs_df$B[r]
    roll_cor <- rollapply(monthly_merged[, c(a, b)], width = rolling_window,
                          FUN = function(x) cor(x[,1], x[,2]),
                          by.column = FALSE, align = "right")
    colnames(roll_cor) <- paste0(gsub("\n", " ", a), " vs ", gsub("\n", " ", b))
    rolling_results[[r]] <- roll_cor
  }

  roll_merged <- do.call(merge, rolling_results)
  roll_df <- data.table(Date = index(roll_merged), as.data.frame(coredata(roll_merged)))
  roll_long <- data.table::melt(roll_df, id.vars = "Date", variable.name = "Pair", value.name = "Correlation")

  p_roll <- ggplot(roll_long, aes(x = Date, y = Correlation, color = Pair)) +
    geom_line(linewidth = 0.8) +
    geom_hline(yintercept = c(0, 0.5, 0.8), linetype = "dashed", color = "grey50", alpha = 0.5) +
    labs(title = "Rolling 36M Pairwise Correlation",
         subtitle = "Dashed lines: 0, 0.5, 0.8 thresholds",
         x = "", y = "Correlation") +
    theme_minimal(base_size = 12) +
    theme(
      legend.position = "bottom",
      legend.text = element_text(size = 8),
      plot.title = element_text(face = "bold")
    ) +
    guides(color = guide_legend(ncol = 2))

  roll_path <- file.path(OUT_DIR, "alpha_rolling_correlation_36m.png")
  ggsave(roll_path, p_roll, width = 14, height = 7, dpi = 150)
  cat(sprintf("[OK] Rolling corr saved: %s\n", roll_path))
}

# ─── 7. Summary statistics table ────────────────────────────────────────────
cat("\n=== Summary Statistics (Monthly) ===\n")
for (nm in colnames(monthly_merged)) {
  x <- as.numeric(monthly_merged[, nm])
  cat(sprintf("  %-25s  Mean=%.2f%%  SD=%.2f%%  Sharpe(m)=%.3f  Min=%.2f%%  Max=%.2f%%\n",
              gsub("\n", " ", nm),
              mean(x)*100, sd(x)*100, mean(x)/sd(x),
              min(x)*100, max(x)*100))
}

# ─── 8. Telegram report ─────────────────────────────────────────────────────
tryCatch({
  source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

  # Build message
  msg_lines <- c(
    "<b>===  Alpha Correlation Analysis ===</b>",
    sprintf("Period: %s ~ %s (%d months)",
            index(monthly_merged)[1], tail(index(monthly_merged), 1), nrow(monthly_merged)),
    sprintf("Strategies: %d loaded (STR_868 no sim_result)", length(monthly_list)),
    ""
  )

  # Correlation matrix as text
  msg_lines <- c(msg_lines, "<b>Correlation Matrix:</b>", "<pre>")
  # Header row
  sn <- gsub("STR_", "", short_names[1:ncol(cor_mat)])
  hdr <- sprintf("%8s", "")
  for (j in 1:ncol(cor_mat)) hdr <- paste0(hdr, sprintf(" %6s", sn[j]))
  msg_lines <- c(msg_lines, hdr)
  for (i in 1:nrow(cor_mat)) {
    row_str <- sprintf("%8s", sn[i])
    for (j in 1:ncol(cor_mat)) row_str <- paste0(row_str, sprintf(" %6.2f", cor_mat[i,j]))
    msg_lines <- c(msg_lines, row_str)
  }
  msg_lines <- c(msg_lines, "</pre>", "")

  # Benchmark correlation
  msg_lines <- c(msg_lines, "<b>vs KOSPI200:</b>")
  for (i in seq_along(bm_col)) {
    msg_lines <- c(msg_lines, sprintf("  %s: %.3f", short_names[i], bm_col[i]))
  }
  msg_lines <- c(msg_lines, "")

  # Key findings
  msg_lines <- c(msg_lines, "<b>Corr &lt; 0.5 (ensemble):</b>")
  if (nrow(low_corr) > 0) {
    for (r in 1:nrow(low_corr)) {
      a_short <- sub("\n.*", "", low_corr$A[r])
      b_short <- sub("\n.*", "", low_corr$B[r])
      msg_lines <- c(msg_lines, sprintf("  %s vs %s: %.3f", a_short, b_short, low_corr$corr[r]))
    }
  } else msg_lines <- c(msg_lines, "  (none)")

  msg_lines <- c(msg_lines, "")
  msg_lines <- c(msg_lines, "<b>Corr &gt; 0.8 (redundant):</b>")
  if (nrow(high_corr) > 0) {
    for (r in 1:nrow(high_corr)) {
      a_short <- sub("\n.*", "", high_corr$A[r])
      b_short <- sub("\n.*", "", high_corr$B[r])
      msg_lines <- c(msg_lines, sprintf("  %s vs %s: %.3f", a_short, b_short, high_corr$corr[r]))
    }
  } else msg_lines <- c(msg_lines, "  (none)")

  tg_send(paste(msg_lines, collapse = "\n"))
  cat("[OK] Telegram text sent\n")

  # Send heatmap
  tg_send_photo(heatmap_path, caption = "Alpha Correlation Matrix (Monthly Returns)")
  cat("[OK] Telegram heatmap sent\n")

  if (exists("roll_path") && file.exists(roll_path)) {
    tg_send_photo(roll_path, caption = "Rolling 36M Pairwise Correlation")
    cat("[OK] Telegram rolling corr chart sent\n")
  }

}, error = function(e) {
  cat(sprintf("[WARN] Telegram failed: %s\n", e$message))
})

cat("\n=== DONE ===\n")
