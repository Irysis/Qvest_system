#==============================================================================
# 148 DART Indicator Systematic Screening
# ICIR, t-stat, correlation matrix, top indicator ranking
#==============================================================================
library(data.table); library(arrow)
source("02_Infrastructure/config.R")
source("02_Infrastructure/telegram_notify.R")

cat("=== 148 DART Indicator Systematic Screening ===\n\n")

# ── Load data ──
RAWDATA <- as.data.table(read_parquet(file.path(CACHE_DIR, "RAWDATA.parquet")))
RAWDATA[, Date := as.Date(Date)]
setorder(RAWDATA, Ticker, Date)

FUND_DT <- as.data.table(read_parquet(file.path(CACHE_DIR, "fundamental_dart.parquet")))
setnames(FUND_DT, "bsns_year", "biz_year", skip_absent = TRUE)
FUND_DT[, Factor_Date := as.Date(Factor_Date)]

BM_DT <- as.data.table(read_parquet(file.path(CACHE_DIR, "benchmark.parquet")))
BM_DT[, Date := as.Date(Date)]

cat(sprintf("RAWDATA: %d rows | FUND_DT: %d rows (%d tickers)\n",
            nrow(RAWDATA), nrow(FUND_DT), uniqueN(FUND_DT$Ticker)))

# ── Identify testable indicators ──
# Exclude non-numeric, identifiers, and metadata columns
skip_cols <- c("Ticker","biz_year","Factor_Date","report_nm","stock_code",
               "AltmanZone","IsZombie","IsDistressed","F_ROA_pos","F_OCF_pos",
               "F_ROA_up","F_Accrual","F_LTDebt_down","F_CR_up",
               "F_NoEquityIssue","F_GM_up","F_AT_up")

all_cols <- names(FUND_DT)
numeric_cols <- all_cols[sapply(FUND_DT, is.numeric)]
test_cols <- setdiff(numeric_cols, skip_cols)
# Remove raw balance sheet items (keep derived ratios)
raw_items <- c("Revenue","COGS","SGA","OP","NI","TotalAssets","TotalEquity",
               "TotalLiab","CurrentAssets","CurrentLiab","Cash","Inventory",
               "Receivable","Payable","FixedAssets","LongTermDebt","ShortTermDebt",
               "IntangibleAssets","NonCurrentAssets","NonCurrentLiab",
               "RetainedEarnings","CapitalStock","DepAmort","InterestExpense",
               "IncomeTax","Dividend","RandD","OCF","ICF","FCF_raw",
               "AvgAssets","AvgEquity","AvgInventory","AvgRecv","AvgPay",
               "GrossProfit","EBITDA","EBIT","WorkingCapital","TotalDebt",
               "NetDebt","FCF","NetInterest","NOPAT")
test_cols <- setdiff(test_cols, raw_items)

cat(sprintf("Testing %d indicators\n\n", length(test_cols)))

# ── Build signal dates (quarterly, March/June/Sep/Dec end) ──
RAWDATA[, YM := format(Date, "%Y-%m")]
sig_dates <- RAWDATA[, .(Signal_Date = max(Date)), by = YM]
sig_dates[, Month := as.integer(substr(YM, 6, 7))]
quarterly <- sig_dates[Month %in% c(3, 6, 9, 12)]$Signal_Date
quarterly <- sort(quarterly[quarterly >= as.Date("2016-06-30")])  # DART starts 2016

cat(sprintf("Signal dates: %d quarters (%s ~ %s)\n\n",
            length(quarterly), min(quarterly), max(quarterly)))

# ── Compute forward 3M returns for each signal date ──
cat("[1/4] Computing forward returns...\n")
fwd_list <- list()
all_dates <- sort(unique(RAWDATA$Date))

for (sig_d in quarterly) {
  sig_d <- as.Date(sig_d)
  idx <- which(all_dates == sig_d)
  fwd_end_idx <- min(idx + 63, length(all_dates))  # ~3 months forward
  fwd_end <- all_dates[fwd_end_idx]

  # Get returns
  fwd <- RAWDATA[Date > sig_d & Date <= fwd_end,
                  .(Fwd_3M = prod(1 + Ret, na.rm = TRUE) - 1), by = Ticker]
  fwd[, Signal_Date := sig_d]
  fwd_list[[length(fwd_list) + 1]] <- fwd
}
fwd_dt <- rbindlist(fwd_list)

# ── Merge DART indicators with forward returns ──
cat("[2/4] Merging indicators with forward returns...\n")

ic_results <- list()

for (sig_d in quarterly) {
  sig_d <- as.Date(sig_d)

  # Find latest DART data available
  avail <- sort(unique(FUND_DT$Factor_Date))
  valid <- avail[avail <= sig_d]
  if (length(valid) == 0) next
  latest_fd <- max(valid)

  fund_snap <- FUND_DT[Factor_Date == latest_fd]
  fwd_snap <- fwd_dt[Signal_Date == sig_d]

  merged <- merge(fund_snap, fwd_snap[, .(Ticker, Fwd_3M)], by = "Ticker")
  if (nrow(merged) < 50) next

  # Compute IC for each indicator
  for (col in test_cols) {
    vals <- merged[[col]]
    if (is.null(vals) || all(is.na(vals))) next
    valid_mask <- !is.na(vals) & !is.na(merged$Fwd_3M) & is.finite(vals)
    if (sum(valid_mask) < 30) next

    # Rank IC (Spearman)
    ic <- cor(rank(vals[valid_mask]), merged$Fwd_3M[valid_mask],
              use = "pairwise.complete.obs")
    if (is.na(ic)) next

    ic_results[[length(ic_results) + 1]] <- data.table(
      Indicator = col, Signal_Date = sig_d, IC = ic, N = sum(valid_mask))
  }
}

if (length(ic_results) == 0) stop("No IC results computed")
ic_dt <- rbindlist(ic_results)

# ── Compute ICIR and summary stats ──
cat("[3/4] Computing ICIR and ranking...\n")

ic_summary <- ic_dt[, .(
  IC_Mean = mean(IC, na.rm = TRUE),
  IC_Std  = sd(IC, na.rm = TRUE),
  ICIR    = mean(IC, na.rm = TRUE) / pmax(sd(IC, na.rm = TRUE), 0.001),
  IC_PosRate = mean(IC > 0, na.rm = TRUE) * 100,
  N_Quarters = .N,
  Avg_N = round(mean(N))
), by = Indicator]

# t-stat
ic_summary[, t_stat := IC_Mean / (IC_Std / sqrt(N_Quarters))]
ic_summary[, p_value := 2 * pt(-abs(t_stat), df = N_Quarters - 1)]

# Sort by absolute ICIR
ic_summary[, abs_ICIR := abs(ICIR)]
setorder(ic_summary, -abs_ICIR)

cat("\n=== TOP 30 Indicators by |ICIR| ===\n")
print(ic_summary[1:min(30, nrow(ic_summary)),
                  .(Indicator, IC_Mean = round(IC_Mean, 4),
                    ICIR = round(ICIR, 3), t_stat = round(t_stat, 2),
                    IC_PosRate = round(IC_PosRate, 1),
                    N_Quarters, Avg_N)])

cat("\n=== Significantly Positive IC (t > 1.65) ===\n")
sig_pos <- ic_summary[t_stat > 1.65][order(-t_stat)]
if (nrow(sig_pos) > 0) {
  print(sig_pos[, .(Indicator, IC_Mean = round(IC_Mean, 4),
                      ICIR = round(ICIR, 3), t_stat = round(t_stat, 2),
                      IC_PosRate = round(IC_PosRate, 1))])
} else cat("  None\n")

cat("\n=== Significantly Negative IC (t < -1.65) ===\n")
sig_neg <- ic_summary[t_stat < -1.65][order(t_stat)]
if (nrow(sig_neg) > 0) {
  print(sig_neg[, .(Indicator, IC_Mean = round(IC_Mean, 4),
                      ICIR = round(ICIR, 3), t_stat = round(t_stat, 2),
                      IC_PosRate = round(IC_PosRate, 1))])
} else cat("  None\n")

# ── Category summary ──
cat("\n=== Category Summary ===\n")
ic_summary[, Category := fcase(
  grepl("^(GPA|ROE|ROA|OPM|Gross|Net|EBITDA_M|ROIC|EBIT_|Oper|PreTax|OCF_R|FCF_M|Cash.*Ratio$)", Indicator), "Profitability",
  grepl("^(Asset.*Turn|Equity.*Turn|Inv.*Turn|Rec.*Turn|Pay.*Turn|Days|CCC|Fixed|WCT|SGA.*Eff)", Indicator), "Efficiency",
  grepl("^(Debt|LongTerm|Total.*Debt|Net.*Debt|Equity.*Mult|Interest|ICR|EBITDA_I|Fin.*Lev|Short.*Debt|Liab|Borrow|Equity.*Ratio|Non.*Liab)", Indicator), "Leverage",
  grepl("^(Current|Quick|Cash.*Ratio|Cash.*Assets|WC.*Assets|Def|Cash.*Burn|Current.*Asset.*Ratio)", Indicator), "Liquidity",
  grepl("^(Accrual|OCF|FCF|Invest.*Int|Fin.*Int|Reinv|Cash.*Gen)", Indicator), "CashFlow",
  grepl("^(Tang|Intang|Inv.*Assets|Recv.*Assets|Non.*Total|Cash.*Current|Retain|Cap.*Int)", Indicator), "AssetStructure",
  grepl("^(Rand|R&D)", Indicator), "R&D",
  grepl("^(Eff.*Tax|Payout|Retention|Div.*Assets|Tax.*Burden|SGR)", Indicator), "TaxDist",
  grepl("^(COGS|SGA.*Gross|Dep|Total.*Cost)", Indicator), "CostStructure",
  grepl("^DuPont", Indicator), "DuPont",
  grepl("^(Asset.*Growth|Revenue.*Growth|Gross.*Growth|OP.*Growth|NI.*Growth|EBITDA.*Growth|Equity.*Growth|OCF.*Growth|Inv.*Growth|Recv.*Growth|Debt.*Growth|SGA.*Growth)", Indicator), "Growth",
  grepl("^Delta_", Indicator), "RatioChange",
  grepl("^(Piotroski|Altman|Quality)", Indicator), "Composite",
  default = "Other"
)]

cat_stats <- ic_summary[, .(
  N_Indicators = .N,
  Best_ICIR = round(max(abs(ICIR)), 3),
  Best_Indicator = Indicator[which.max(abs(ICIR))],
  Avg_absIC = round(mean(abs(IC_Mean)), 4),
  N_Significant = sum(abs(t_stat) > 1.65)
), by = Category][order(-Best_ICIR)]
print(cat_stats)

# ── Correlation matrix of top indicators ──
cat("\n[4/4] Computing correlation matrix of top indicators...\n")

top_n <- min(20, nrow(ic_summary))
top_indicators <- ic_summary$Indicator[1:top_n]

# Use latest DART snapshot for cross-sectional correlation
latest_fd <- max(FUND_DT$Factor_Date)
snap <- FUND_DT[Factor_Date == latest_fd]

# Check which columns exist
available_top <- intersect(top_indicators, names(snap))
if (length(available_top) >= 5) {
  cor_mat <- cor(snap[, ..available_top], use = "pairwise.complete.obs")
  cat(sprintf("\n=== Correlation Matrix (top %d indicators, latest snapshot) ===\n",
              length(available_top)))

  # Print correlation clusters (|r| > 0.7)
  cat("\nHigh correlations (|r| > 0.7):\n")
  for (i in 1:(ncol(cor_mat)-1)) {
    for (j in (i+1):ncol(cor_mat)) {
      r <- cor_mat[i, j]
      if (!is.na(r) && abs(r) > 0.7) {
        cat(sprintf("  %s × %s: r=%.3f\n",
                    colnames(cor_mat)[i], colnames(cor_mat)[j], r))
      }
    }
  }
}

# ── Gate effectiveness: top indicators as exclusion gates ──
cat("\n=== Gate Effectiveness (Top 10, bottom 10% exclusion) ===\n")

# For each top indicator, test: remove bottom or top 10% → impact on forward return
gate_results <- list()

for (ind in head(ic_summary$Indicator, 20)) {
  ic_sign <- sign(ic_summary[Indicator == ind]$IC_Mean)

  for (sig_d in quarterly) {
    sig_d <- as.Date(sig_d)
    avail <- sort(unique(FUND_DT$Factor_Date))
    valid <- avail[avail <= sig_d]
    if (length(valid) == 0) next
    latest_fd <- max(valid)

    fund_snap <- FUND_DT[Factor_Date == latest_fd, .(Ticker, ind_val = get(ind))]
    fwd_snap <- fwd_dt[Signal_Date == sig_d, .(Ticker, Fwd_3M)]
    merged <- merge(fund_snap, fwd_snap, by = "Ticker")
    merged <- merged[!is.na(ind_val) & !is.na(Fwd_3M) & is.finite(ind_val)]
    if (nrow(merged) < 50) next

    # Remove worst 10%
    if (ic_sign > 0) {
      # Positive IC → low values are bad → remove bottom 10%
      threshold <- quantile(merged$ind_val, 0.10)
      kept <- merged[ind_val >= threshold]
      removed <- merged[ind_val < threshold]
    } else {
      # Negative IC → high values are bad → remove top 10%
      threshold <- quantile(merged$ind_val, 0.90)
      kept <- merged[ind_val <= threshold]
      removed <- merged[ind_val > threshold]
    }

    if (nrow(kept) < 30 || nrow(removed) < 5) next
    gate_results[[length(gate_results) + 1]] <- data.table(
      Indicator = ind, Signal_Date = sig_d,
      Ret_Kept = mean(kept$Fwd_3M), Ret_Removed = mean(removed$Fwd_3M),
      N_Kept = nrow(kept), N_Removed = nrow(removed))
  }
}

if (length(gate_results) > 0) {
  gate_dt <- rbindlist(gate_results)
  gate_summary <- gate_dt[, .(
    VA_bps = round((mean(Ret_Kept) - mean(Ret_Removed)) * 10000),
    Ret_Kept = round(mean(Ret_Kept) * 100, 2),
    Ret_Removed = round(mean(Ret_Removed) * 100, 2),
    N_Quarters = .N
  ), by = Indicator][order(-VA_bps)]

  print(gate_summary)
}

# ── Save results ──
out_path <- file.path(RESEARCH_OUTPUT, "regime_comparison/output")
fwrite(ic_summary, file.path(out_path, "dart_indicator_icir_ranking.csv"))
if (length(gate_results) > 0)
  fwrite(gate_summary, file.path(out_path, "dart_gate_effectiveness.csv"))

cat(sprintf("\nSaved: dart_indicator_icir_ranking.csv (%d indicators)\n", nrow(ic_summary)))

# ── Telegram summary ──
top5 <- ic_summary[1:min(5, nrow(ic_summary))]
n_sig <- sum(abs(ic_summary$t_stat) > 1.65, na.rm = TRUE)

tg_msg <- sprintf(
'<b>📊 148 DART 지표 체계적 스크리닝 완료</b>

테스트: %d개 지표 | %d 분기 | %s~%s

<b>▸ TOP 5 by |ICIR|:</b>
1. %s (ICIR=%s, t=%s)
2. %s (ICIR=%s, t=%s)
3. %s (ICIR=%s, t=%s)
4. %s (ICIR=%s, t=%s)
5. %s (ICIR=%s, t=%s)

유의미 (|t|>1.65): %d개
카테고리별 best: 리포트 참조',
  length(test_cols), length(quarterly), min(quarterly), max(quarterly),
  top5$Indicator[1], round(top5$ICIR[1],3), round(top5$t_stat[1],2),
  top5$Indicator[2], round(top5$ICIR[2],3), round(top5$t_stat[2],2),
  top5$Indicator[3], round(top5$ICIR[3],3), round(top5$t_stat[3],2),
  top5$Indicator[4], round(top5$ICIR[4],3), round(top5$t_stat[4],2),
  top5$Indicator[5], round(top5$ICIR[5],3), round(top5$t_stat[5],2),
  n_sig)
tg_send(tg_msg)

cat("\n=== Screening Complete ===\n")
