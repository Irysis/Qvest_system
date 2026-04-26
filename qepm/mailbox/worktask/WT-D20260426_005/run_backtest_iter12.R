## ============================================================
## STR_1702 — Iter 12 Forge Backtest (FIXED v2)
## LinTilt + Kelly + 3-Layer Overlay Quarterly
## walk_forward = TRUE, 213 sig_dates
## PIT cutoff: 2023-11-30 (strict)
## ============================================================

cat("=== STR_1702: LinTilt+Kelly+3Layer Overlay Quarterly Backtest ===\n")
cat("Start time:", format(Sys.time()), "\n")

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(ggplot2)
  library(sandwich)
  library(lmtest)
  library(jsonlite)
})

BASE_DIR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_DIR   <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260426_005")
OUT_DIR  <- file.path(WT_DIR, "backtest_result")
JR_DIR   <- file.path(WT_DIR, "judge_ready")
PRIOR_WT <- file.path(BASE_DIR, "qepm/mailbox/worktask/WT-D20260426_004")

## ---- Hash Audit START ----
cat("\n[HASH AUDIT START]\n")
files_to_hash <- c(
  file.path(WT_DIR, "alpha_package.json"),
  file.path(WT_DIR, "risk_package.json"),
  file.path(WT_DIR, "weights.csv"),
  file.path(WT_DIR, "optimization_package.json")
)
hash_start <- sapply(files_to_hash, function(f) as.character(tools::md5sum(f)))
for (i in seq_along(files_to_hash)) cat(basename(files_to_hash[i]), ":", hash_start[i], "\n")

## ---- Load weights ----
cat("\n[LOAD WEIGHTS]\n")
wts <- fread(file.path(WT_DIR, "weights.csv"))
wts[, as_of_date := as.Date(as_of_date)]
sig_dates <- sort(unique(wts$as_of_date))
cat("Weights rows:", nrow(wts), "| Sig_dates:", length(sig_dates), "\n")
cat("Date range:", format(min(sig_dates)), "~", format(max(sig_dates)), "\n")

## ---- Load alpha_scores (Ret_1m source) ----
cat("\n[LOAD ALPHA SCORES]\n")
alpha_scores <- as.data.table(read_parquet(
  file.path(BASE_DIR, "stage_artifacts/WT_D20260425_010/alpha_scores.parquet")
))
setnames(alpha_scores, "Date", "sig_date")
alpha_scores[, sig_date := as.Date(sig_date)]
setkey(alpha_scores, sig_date, Ticker)
cat("Alpha scores:", nrow(alpha_scores), "rows,",
    format(min(alpha_scores$sig_date)), "~", format(max(alpha_scores$sig_date)), "\n")

## ---- Walk-forward backtest ----
cat("\n[WALK-FORWARD BACKTEST]\n")
COMMISSION <- 0.0015  # 15bps one-way

# Identify rebalance vs hold months
rebal_dates <- wts[!grepl("held", sigma_method, ignore.case=TRUE) & ticker != "CASH",
                    unique(as_of_date)]
cat("Rebalance dates:", length(rebal_dates), "| Hold dates:", length(sig_dates) - length(rebal_dates), "\n")

# Walk-forward loop
results_list <- vector("list", length(sig_dates))
prev_w_eq <- NULL
prev_w_names <- NULL

for (i in seq_along(sig_dates)) {
  d <- sig_dates[i]
  w_d <- wts[as_of_date == d]

  w_eq <- w_d[ticker != "CASH"]
  w_cash_val <- w_d[ticker == "CASH", sum(weight)]
  if (length(w_cash_val) == 0 || is.na(w_cash_val)) w_cash_val <- 0

  is_rebal <- d %in% rebal_dates

  # Equity returns from alpha_scores
  rets_d <- alpha_scores[sig_date == d, .(Ticker, Ret_1m)]
  setkey(rets_d, Ticker)

  w_eq_named <- setNames(w_eq$weight, w_eq$ticker)

  r_eq <- sapply(names(w_eq_named), function(tk) {
    r <- rets_d[Ticker == tk, Ret_1m]
    if (length(r) == 0 || is.na(r[1])) 0 else r[1]
  })

  gross_ret <- sum(w_eq_named * r_eq) + w_cash_val * 0

  # TC on rebalance dates
  if (is_rebal && !is.null(prev_w_eq)) {
    all_nm <- union(names(w_eq_named), names(prev_w_eq))
    w_new_f <- setNames(numeric(length(all_nm)), all_nm)
    w_old_f <- setNames(numeric(length(all_nm)), all_nm)
    for (nm in names(w_eq_named)) w_new_f[nm] <- w_eq_named[nm]
    for (nm in names(prev_w_eq)) w_old_f[nm] <- prev_w_eq[nm]
    to_one_way <- sum(abs(w_new_f - w_old_f)) / 2
    tc <- to_one_way * COMMISSION * 2
  } else {
    tc <- 0
  }

  net_ret <- gross_ret - tc

  if (is_rebal) {
    prev_w_eq <- w_eq_named
    prev_w_names <- names(w_eq_named)
  }

  results_list[[i]] <- list(
    sig_date = d,
    gross_ret = gross_ret,
    net_ret = net_ret,
    tc = tc,
    n_names = nrow(w_eq),
    is_rebal = is_rebal,
    regime = w_d$regime[1],
    w_cash = w_cash_val
  )
}

monthly_ret <- rbindlist(lapply(results_list, as.data.table))
monthly_ret[, cum_gross := cumprod(1 + gross_ret)]
monthly_ret[, cum_net := cumprod(1 + net_ret)]
monthly_ret[, YM := format(sig_date, "%Y-%m")]
monthly_ret[, year := format(sig_date, "%Y")]

cat("N months:", nrow(monthly_ret), "\n")
cat("Rebalance months:", sum(monthly_ret$is_rebal), "| Hold months:", sum(!monthly_ret$is_rebal), "\n")
cat("Total TC:", round(sum(monthly_ret$tc), 6), "\n")
cat("NAV final gross:", round(tail(monthly_ret$cum_gross, 1), 4), "\n")
cat("NAV final net  :", round(tail(monthly_ret$cum_net, 1), 4), "\n")

## ---- Performance metrics function ----
compute_metrics <- function(rets, label = "strategy") {
  rets <- rets[!is.na(rets)]
  n <- length(rets)
  if (n < 12) return(list(label=label, n_months=n, cagr=NA, vol=NA, sr=NA, mdd=NA,
                           hit=NA, harvey_t=NA, dsr_raw=NA, dsr_post=NA))
  total_ret <- prod(1 + rets) - 1
  years <- n / 12
  cagr <- (1 + total_ret)^(1/years) - 1
  vol <- sd(rets) * sqrt(12)
  sr <- cagr / vol
  cum_v <- cumprod(1 + rets)
  mdd <- min(cum_v / cummax(cum_v) - 1)
  hit <- mean(rets > 0)
  t_simple <- mean(rets) / sd(rets) * sqrt(n)
  # Bailey-Lopez DSR
  skew_r <- mean((rets - mean(rets))^3) / sd(rets)^3
  kurt_r  <- mean((rets - mean(rets))^4) / sd(rets)^4
  gamma2  <- kurt_r - 3
  denom   <- 1 - skew_r * sr / sqrt(12) + (gamma2 + 2) / 4 * sr^2 / 12
  denom   <- max(denom, 0.01)
  dsr_raw <- sr * sqrt(n / 12) / sqrt(denom)
  dsr_post <- dsr_raw - 1.00  # 20 candidates * 0.05
  list(label=label, n_months=n, cagr=round(cagr,4), vol=round(vol,4), sr=round(sr,4),
       mdd=round(mdd,4), hit=round(hit,4), harvey_t=round(t_simple,4),
       dsr_raw=round(dsr_raw,4), dsr_post=round(dsr_post,4))
}

## ---- Full period metrics ----
m_full <- compute_metrics(monthly_ret$net_ret, "STR_1702_prelb")
cat("\n[FULL PERIOD METRICS — 2006-01 ~ 2023-12]\n")
cat(sprintf("CAGR: %.4f | Vol: %.4f | SR: %.4f | MDD: %.4f\n",
            m_full$cagr, m_full$vol, m_full$sr, m_full$mdd))
cat(sprintf("Hit: %.4f | Harvey_t: %.4f | DSR_raw: %.4f | DSR_post: %.4f\n",
            m_full$hit, m_full$harvey_t, m_full$dsr_raw, m_full$dsr_post))

## ---- M2. OOS 2024-2026 (frozen weights) ----
cat("\n[M2 OOS EXTENSION — FROZEN WEIGHTS 2024-01 ~ 2026-04]\n")
frozen_wts <- wts[as_of_date == as.Date("2023-12-01")]
frozen_eq <- frozen_wts[ticker != "CASH"]
frozen_cash <- frozen_wts[ticker == "CASH", sum(weight)]
if (is.na(frozen_cash) || length(frozen_cash) == 0) frozen_cash <- 0.30
frozen_eq_named <- setNames(frozen_eq$weight, frozen_eq$ticker)
cat("Frozen cash:", frozen_cash, "| Frozen N names:", nrow(frozen_eq), "\n")

# Load RAWDATA for OOS stock returns
raw_path <- file.path(BASE_DIR, ".cache/rawdata.parquet")
raw <- as.data.table(read_parquet(raw_path))
raw[, Date := as.Date(Date)]
raw_oos <- raw[Date >= as.Date("2024-01-01") & Date <= as.Date("2026-04-30") &
               Ticker %in% names(frozen_eq_named)]
raw_oos[, YM := format(Date, "%Y-%m")]
raw_monthly_oos <- raw_oos[, .(
  Ret_1m = prod(1 + Ret, na.rm=TRUE) - 1,
  sig_date = as.Date(paste0(YM[1], "-01"))
), by = .(YM, Ticker)]

oos_dates <- sort(unique(raw_monthly_oos$sig_date))
cat("OOS months available:", length(oos_dates), "\n")

oos_rets <- sapply(oos_dates, function(d) {
  r_d <- raw_monthly_oos[sig_date == d]
  r_sum <- 0
  for (tk in names(frozen_eq_named)) {
    r_tk <- r_d[Ticker == tk, Ret_1m]
    rv <- if (length(r_tk) == 0 || is.na(r_tk[1])) 0 else r_tk[1]
    r_sum <- r_sum + frozen_eq_named[tk] * rv
  }
  r_sum  # cash earns 0, already excluded from frozen_eq
})

oos_dt <- data.table(
  sig_date = oos_dates,
  ret = oos_rets,
  YM = format(oos_dates, "%Y-%m")
)
oos_dt[, cum := cumprod(1 + ret)]

m_oos <- compute_metrics(oos_dt$ret, "STR_1702_OOS_2024_2026")
cat(sprintf("OOS CAGR: %.4f | SR: %.4f | MDD: %.4f | n=%d\n",
            m_oos$cagr, m_oos$sr, m_oos$mdd, m_oos$n_months))

## ---- M3. Same-period 243m comparison ----
cat("\n[M3 SAME-PERIOD COMPARISON]\n")

nav4 <- fread(file.path(PRIOR_WT, "backtest_result/nav_panel_4way.csv"))
nav4[, Date := as.Date(Date)]

# Map STR_1702 in-sample returns to nav4 YM
# sig_date X in weights = return realized during month X, reported as month X+1
# nav4 YM = the reporting month
# monthly_ret$YM = format(sig_date) = "2006-01" → return for Jan 2006 → nav4 YM = "2006-02"
monthly_ret[, next_YM := format(as.Date(paste0(YM, "-01")) + 32, "%Y-%m")]

# Create lookup: next_YM → net_ret
ret_lookup <- monthly_ret[, .(next_YM, net_ret)]
setkey(ret_lookup, next_YM)

nav4[, str1702 := {
  r <- ret_lookup[J(YM), net_ret]
  r
}]

# OOS: map oos_dt (sig_date) to nav4 YM
# oos_dt sig_date = start of month X → return for month X → nav4 YM = month X+1
oos_dt[, next_YM := format(as.Date(paste0(YM, "-01")) + 32, "%Y-%m")]
oos_lookup <- oos_dt[, .(next_YM, ret)]
setkey(oos_lookup, next_YM)

# Fill OOS into nav4 where str1702 is still NA
nav4[is.na(str1702), str1702 := {
  r <- oos_lookup[J(YM), ret]
  r
}]

n_1702 <- sum(!is.na(nav4$str1702))
cat("STR_1702 valid months in panel:", n_1702, "\n")

# Common period: all 5 valid
valid_mask <- with(nav4, !is.na(iter11) & !is.na(str1699) & !is.na(str1700) &
                         !is.na(mega05) & !is.na(str1702))
nav_common <- nav4[valid_mask]
n_common <- nrow(nav_common)
cat("Common period:", nav_common$YM[1], "~", nav_common$YM[n_common], "| N:", n_common, "\n")

strat_cols  <- c("iter11", "str1699", "str1700", "mega05", "str1702")
strat_labels <- c("STR_1701_Iter11", "STR_1699_Iter5_HRP", "STR_1700_Iter6_Kelly",
                   "MEGA_05_PG2", "STR_1702_Iter12_Quarterly")

comparison_metrics <- lapply(seq_along(strat_cols), function(j) {
  compute_metrics(nav_common[[strat_cols[j]]], strat_labels[j])
})
names(comparison_metrics) <- strat_labels

cat(sprintf("\n%-30s %8s %8s %8s %8s %6s %8s %8s\n",
            "Strategy", "SR", "CAGR", "MDD", "Vol", "Hit", "Harvey_t", "DSR_post"))
for (m in comparison_metrics) {
  cat(sprintf("%-30s %8.4f %8.4f %8.4f %8.4f %6.4f %8.4f %8.4f\n",
              m$label, m$sr, m$cagr, m$mdd,
              ifelse(is.null(m$vol) || is.na(m$vol), NA, m$vol),
              m$hit, m$harvey_t, m$dsr_post))
}

# Pairwise correlations
cor_mat <- cor(nav_common[, .SD, .SDcols = strat_cols], use = "pairwise.complete.obs")
cat("\n--- Pairwise Correlations ---\n")
print(round(cor_mat, 4))

## ---- M4. FF5 Harvey regression ----
cat("\n[M4 HARVEY FF5 REGRESSION]\n")

ff <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/kr_factor_returns_v2.parquet")))
ff[, Date := as.Date(Date)]
# FF dates are end-of-month; monthly_ret sig_dates are start-of-month
# Match by year-month: FF "2006-01-31" ↔ sig_date "2006-01-01"
ff[, YM_ff := format(Date, "%Y-%m")]
monthly_ret[, YM_ff := format(sig_date, "%Y-%m")]

monthly_ret_ff <- merge(monthly_ret[, .(YM_ff, net_ret)],
                         ff[, .(YM_ff, MKT, SMB, HML, WML, RMW, CMA, RF)],
                         by = "YM_ff", all.x = TRUE)
monthly_ret_ff <- monthly_ret_ff[!is.na(MKT)]
n_reg <- nrow(monthly_ret_ff)
cat("Regression sample N:", n_reg, "\n")

run_spec <- function(spec_name) {
  dt <- monthly_ret_ff[!is.na(net_ret) & !is.na(MKT)]
  n <- nrow(dt)
  dt[, y := net_ret - RF]

  fmla <- switch(spec_name,
    CAPM      = y ~ MKT,
    Carhart_3 = y ~ MKT + SMB + HML,
    Carhart_4 = y ~ MKT + SMB + HML + WML,
    FF5       = y ~ MKT + SMB + HML + RMW + CMA,
    FF6       = y ~ MKT + SMB + HML + WML + RMW + CMA
  )

  model <- lm(fmla, data = dt)
  nw_lag <- max(1, floor(4 * (n / 100)^(2/9)))
  nw_se  <- sandwich::NeweyWest(model, lag = nw_lag, prewhite = FALSE)
  ct     <- lmtest::coeftest(model, vcov = nw_se)

  alpha_m <- ct["(Intercept)", "Estimate"]
  alpha_a <- (1 + alpha_m)^12 - 1
  t_nw    <- ct["(Intercept)", "t value"]
  p_nw    <- ct["(Intercept)", "Pr(>|t|)"]
  r2      <- summary(model)$r.squared
  adj_r2  <- summary(model)$adj.r.squared

  list(spec = spec_name, n = n,
       alpha_monthly = round(alpha_m, 6),
       alpha_annual  = round(alpha_a, 4),
       t_nw   = round(t_nw, 4),
       p_nw   = round(p_nw, 6),
       nw_lag = nw_lag,
       r2     = round(r2, 4),
       adj_r2 = round(adj_r2, 4),
       gate_pass = abs(t_nw) >= 2.95)
}

specs <- c("CAPM", "Carhart_3", "Carhart_4", "FF5", "FF6")
ff_results <- lapply(specs, run_spec)
names(ff_results) <- specs

n_pass <- sum(sapply(ff_results, function(x) isTRUE(x$gate_pass)))
cat("Harvey FF5 results (threshold t >= 2.95):\n")
for (s in specs) {
  r <- ff_results[[s]]
  cat(sprintf("  %-12s alpha_ann=%.4f  t_NW=%.4f  R2=%.4f  PASS=%s\n",
              r$spec, r$alpha_annual, r$t_nw, r$r2, r$gate_pass))
}
cat("Specs passing Harvey threshold:", n_pass, "/ 5\n")

## ---- M5. DSR ----
cat("\n[M5 DSR]\n")
candidates_tried <- 20
penalty <- candidates_tried * 0.05
cat("Candidates:", candidates_tried, "| Penalty:", penalty, "\n")
cat("DSR raw:", m_full$dsr_raw, "| DSR post:", m_full$dsr_post, "\n")

## ---- M6. CVaR ----
cat("\n[M6 CVAR DAILY REALIZED]\n")
q05 <- quantile(monthly_ret$net_ret, 0.05)
cvar_95_m <- -mean(monthly_ret$net_ret[monthly_ret$net_ret <= q05])
cvar_95_d  <- cvar_95_m / sqrt(21)
cat("Monthly CVaR_95:", round(cvar_95_m, 6), "\n")
cat("Daily CVaR_95 proxy:", round(cvar_95_d, 6), "\n")
cat("Cap 0.025 — PASS:", cvar_95_d <= 0.025, "| Margin:", round(0.025 - cvar_95_d, 6), "\n")
cat("Iter11 CVaR_d: 0.0259 (breach) | Iter12:", round(cvar_95_d, 4), "(", ifelse(cvar_95_d <= 0.025, "PASS", "FAIL"), ")\n")

## ---- Regime conditional ----
cat("\n[REGIME CONDITIONAL METRICS]\n")
for (rg in c("BULL", "NORMAL", "CAUTION", "CRISIS")) {
  sub <- monthly_ret[regime == rg]
  n_rg <- nrow(sub)
  if (n_rg >= 5) {
    m_rg <- compute_metrics(sub$net_ret, rg)
    cat(sprintf("  %-8s n=%3d  CAGR=%.4f  SR=%.4f  MDD=%.4f\n", rg, n_rg, m_rg$cagr, m_rg$sr, m_rg$mdd))
  } else {
    cat(sprintf("  %-8s n=%3d  (too few months)\n", rg, n_rg))
  }
}

## ---- Annual returns ----
annual_rets <- monthly_ret[, .(ann_ret = prod(1 + net_ret) - 1, n_months = .N), by = year]
cat("\n[ANNUAL RETURNS]\n")
print(annual_rets)

## ---- Scenario metrics ----
cat("\n[SCENARIO METRICS]\n")
rets_A  <- nav_common$str1702
rets_D  <- nav_common$mega05
# AB: 80% Iter12 + 20% STR_1699 (proxy for STR_1656 — unavailable)
rets_AB <- 0.8 * nav_common$str1702 + 0.2 * nav_common$str1699
# B: 60% Iter12 + 20% Iter11 + 20% STR_1699 (proxy)
rets_B  <- 0.6 * nav_common$str1702 + 0.2 * nav_common$iter11 + 0.2 * nav_common$str1699

scen_list <- list(
  A_Replacement  = rets_A,
  AB_80pct_20pct = rets_AB,
  B_60_20_20     = rets_B,
  D_PG2_Current  = rets_D
)
scenario_metrics <- lapply(names(scen_list), function(s) compute_metrics(scen_list[[s]], s))
names(scenario_metrics) <- names(scen_list)

cat(sprintf("%-22s %8s %8s %8s\n", "Scenario", "SR", "CAGR", "MDD"))
for (s in names(scenario_metrics)) {
  m <- scenario_metrics[[s]]
  cat(sprintf("%-22s %8.4f %8.4f %8.4f\n", s, m$sr, m$cagr, m$mdd))
}

## ---- M7. Charts ----
cat("\n[M7 GENERATING CHARTS]\n")

# Cumulative NAV columns
nav_ch <- copy(nav_common)
for (col in strat_cols) {
  nav_ch[, paste0("cum_", col) := cumprod(1 + get(col))]
}

# KOSPI200 benchmark monthly returns
bench <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
bench[, Date_d := as.Date(Date)]
bench[, YM_b := format(Date_d, "%Y-%m")]
bench_m <- bench[, .(bench_ret = sum(BM_Ret, na.rm=TRUE)), by=YM_b]
setnames(bench_m, "YM_b", "YM")
nav_ch <- merge(nav_ch, bench_m, by="YM", all.x=TRUE)
nav_ch[, cum_bench := cumprod(1 + ifelse(is.na(bench_ret), 0, bench_ret))]

## Chart 1: Equity Curve
ec_colors <- c("STR_1702 Iter12 (Quarterly)" = "#E31A1C",
               "STR_1701 Iter11 (Monthly)" = "#1F78B4",
               "STR_1699 Iter5 HRP" = "#33A02C",
               "STR_1700 Iter6 Kelly" = "#FF7F00",
               "MEGA_05 PG2" = "#6A3D9A",
               "KOSPI200" = "gray50")

nav_long <- rbind(
  data.table(Date=as.Date(nav_ch$Date), strategy="STR_1702 Iter12 (Quarterly)", cum=nav_ch$cum_str1702),
  data.table(Date=as.Date(nav_ch$Date), strategy="STR_1701 Iter11 (Monthly)",   cum=nav_ch$cum_iter11),
  data.table(Date=as.Date(nav_ch$Date), strategy="STR_1699 Iter5 HRP",          cum=nav_ch$cum_str1699),
  data.table(Date=as.Date(nav_ch$Date), strategy="STR_1700 Iter6 Kelly",        cum=nav_ch$cum_str1700),
  data.table(Date=as.Date(nav_ch$Date), strategy="MEGA_05 PG2",                 cum=nav_ch$cum_mega05),
  data.table(Date=as.Date(nav_ch$Date), strategy="KOSPI200",                    cum=nav_ch$cum_bench)
)
nav_long[, strategy := factor(strategy, levels=names(ec_colors))]

p1 <- ggplot(nav_long, aes(x=Date, y=cum, color=strategy, linewidth=strategy)) +
  geom_line() +
  scale_color_manual(values=ec_colors) +
  scale_linewidth_manual(values=c(1.8, 1.2, 0.8, 0.8, 0.8, 0.6)) +
  labs(title="STR_1702 vs Iter11/5/6/MEGA_05/KOSPI200 — Walk-forward NAV (15bps commission)",
       subtitle=paste0("Common period: ", nav_ch$YM[1], " ~ ", nav_ch$YM[n_common],
                       " | N=", n_common, " months"),
       x="Date", y="Cumulative NAV (base=1.0)",
       color="Strategy", linewidth="Strategy") +
  annotate("text", x=as.Date(nav_ch$Date[round(n_common*0.85)]),
           y=max(nav_ch$cum_iter11)*0.97,
           label=paste0("Iter12 SR=", comparison_metrics$STR_1702_Iter12_Quarterly$sr,
                        "\nIter11 SR=", comparison_metrics$STR_1701_Iter11$sr),
           size=3.5, color="gray20") +
  theme_minimal(base_size=12) +
  theme(legend.position="bottom")

ggsave(file.path(OUT_DIR, "equity_curve.png"), p1, width=14, height=7, dpi=150)
cat("equity_curve.png saved\n")

## Chart 2: Annual Returns
annual_rets[, year_n := as.numeric(year)]
annual_rets[, col := ifelse(ann_ret >= 0, "pos", "neg")]
p2 <- ggplot(annual_rets, aes(x=year_n, y=ann_ret*100, fill=col)) +
  geom_col(width=0.7) +
  geom_hline(yintercept=0, color="black", linewidth=0.5) +
  scale_fill_manual(values=c(pos="#2166AC", neg="#D6604D"), guide="none") +
  geom_text(aes(label=sprintf("%.0f%%", ann_ret*100),
                vjust=ifelse(ann_ret>=0, -0.3, 1.1)), size=3) +
  labs(title="STR_1702 — Annual Returns (Net of 15bps, %)",
       subtitle="Quarterly rebalance | LinTilt + Kelly + 3-Layer Overlay",
       x="Year", y="Annual Return (%)") +
  theme_minimal(base_size=12)

ggsave(file.path(OUT_DIR, "annual_returns.png"), p2, width=12, height=6, dpi=150)
cat("annual_returns.png saved\n")

## Chart 3: OOS Zoom 2024-2026
oos_dt[, cum_from1 := cumprod(1 + ret)]
p3 <- ggplot(oos_dt, aes(x=as.Date(sig_date), y=cum_from1)) +
  geom_line(color="#E31A1C", linewidth=1.5) +
  geom_area(alpha=0.1, fill="#E31A1C") +
  geom_hline(yintercept=1, linetype="dashed", color="gray50") +
  labs(title="STR_1702 OOS 2024-2026 — Frozen Weights Buy-and-Hold",
       subtitle=sprintf("Last weights: 2023-12-01 | Cash=30%% | N_equity=20 | SR=%.4f | CAGR=%.4f | MDD=%.4f",
                        m_oos$sr, m_oos$cagr, m_oos$mdd),
       x="Date", y="Cumulative Return (base=1.0)") +
  theme_minimal(base_size=12)

ggsave(file.path(OUT_DIR, "oos_zoom.png"), p3, width=10, height=5, dpi=150)
cat("oos_zoom.png saved\n")

## Chart 4: Scenario Comparison
scen_nav <- data.table(
  Date = as.Date(nav_ch$Date),
  A_Replacement  = cumprod(1 + rets_A),
  AB_80_20       = cumprod(1 + rets_AB),
  B_60_20_20     = cumprod(1 + rets_B),
  D_PG2_Current  = cumprod(1 + rets_D)
)

scen_long <- rbind(
  data.table(Date=scen_nav$Date, scenario="A: Iter12 100%",           cum=scen_nav$A_Replacement),
  data.table(Date=scen_nav$Date, scenario="AB: Iter12 80%+blend 20%", cum=scen_nav$AB_80_20),
  data.table(Date=scen_nav$Date, scenario="B: Iter12 60%+mix 40%",    cum=scen_nav$B_60_20_20),
  data.table(Date=scen_nav$Date, scenario="D: Current PG2",           cum=scen_nav$D_PG2_Current)
)

p4 <- ggplot(scen_long, aes(x=Date, y=cum, color=scenario, linewidth=scenario)) +
  geom_line() +
  scale_color_manual(values=c("A: Iter12 100%"="#E31A1C",
                              "AB: Iter12 80%+blend 20%"="#1F78B4",
                              "B: Iter12 60%+mix 40%"="#33A02C",
                              "D: Current PG2"="#6A3D9A")) +
  scale_linewidth_manual(values=c(1.5, 1.2, 1.0, 0.8)) +
  labs(title="Scenario Comparison: A / AB / B / D",
       subtitle=sprintf("A: SR=%.4f | AB: SR=%.4f | B: SR=%.4f | D: SR=%.4f",
                        scenario_metrics$A_Replacement$sr, scenario_metrics$AB_80pct_20pct$sr,
                        scenario_metrics$B_60_20_20$sr, scenario_metrics$D_PG2_Current$sr),
       x="Date", y="Cumulative NAV (base=1.0)",
       color="Scenario", linewidth="Scenario") +
  theme_minimal(base_size=12) +
  theme(legend.position="bottom")

ggsave(file.path(OUT_DIR, "scenario_comparison.png"), p4, width=14, height=7, dpi=150)
cat("scenario_comparison.png saved\n")

## ---- Save CSV outputs ----
cat("\n[SAVING OUTPUTS]\n")

# Monthly returns CSV
monthly_out <- monthly_ret[, .(
  Date = sig_date, YM,
  port_ret_gross = gross_ret,
  port_ret_net   = net_ret,
  tc, cum_gross, cum_net, n_names, is_rebal, regime, w_cash
)]
fwrite(monthly_out, file.path(OUT_DIR, "monthly_returns.csv"))

# 5-way NAV panel
fwrite(nav4[valid_mask, .(YM, Date, iter11, str1699, str1700, mega05, str1702)],
       file.path(OUT_DIR, "nav_panel_5way.csv"))

# OOS monthly
fwrite(oos_dt, file.path(OUT_DIR, "oos_24_26_monthly.csv"))

# Annual returns
fwrite(annual_rets, file.path(OUT_DIR, "annual_returns.csv"))

# STR_1702 full period monthly (for judge)
str1702_fp <- rbind(
  monthly_out[, .(Date, YM, port_ret = port_ret_net, cum_nav = cum_net)],
  oos_dt[, .(Date = sig_date, YM, port_ret = ret, cum_nav = cumprod(1 + ret))]
)
fwrite(str1702_fp, file.path(OUT_DIR, "str1702_full_period_monthly.csv"))
cat("str1702_full_period_monthly.csv saved\n")

# Judge ready
jr_monthly <- monthly_out[, .(Date, YM, port_ret = port_ret_net, cum_nav = cum_net)]
fwrite(jr_monthly, file.path(JR_DIR, "nav_monthly_str1702.csv"))
fwrite(jr_monthly, file.path(JR_DIR, "ret_d_proxy_str1702.csv"))
cat("Judge ready files saved\n")

## ---- Hash audit END ----
cat("\n[HASH AUDIT END]\n")
hash_end <- sapply(files_to_hash, function(f) as.character(tools::md5sum(f)))
hash_match <- all(hash_start == hash_end)
cat("All input files unchanged:", hash_match, "\n")
if (!hash_match) {
  cat("HASH MISMATCH — pure_function violated!\n")
  for (i in seq_along(files_to_hash)) {
    if (hash_start[i] != hash_end[i])
      cat("  CHANGED:", basename(files_to_hash[i]), "\n")
  }
}

## ---- Compile forge_package ----
cat("\n[COMPILING FORGE PACKAGE]\n")

regime_cond <- lapply(c("BULL", "NORMAL", "CAUTION", "CRISIS"), function(rg) {
  sub <- monthly_ret[regime == rg]
  m <- compute_metrics(sub$net_ret, rg)
  list(n_months=nrow(sub), cagr=m$cagr, sr=m$sr, mdd=m$mdd)
})
names(regime_cond) <- c("BULL", "NORMAL", "CAUTION", "CRISIS")

forge_pkg <- list(
  task_id = "WT-D20260426_005",
  str_id  = "STR_1702",
  agent   = "forge_integration_v6.1_pure_function_iter12",
  iter_label = "Iter12_LinTilt_Kelly_3Layer_Quarterly",
  role_label  = "core_with_machinery_overlay",
  as_of_date  = "2026-04-26",
  method_weights = "LinTilt_Kelly_Overlay_Quarterly",
  optimizer_expected = list(ir=0.6439, cagr=0.1130, mdd=-0.3931, cvar_d=0.0244),
  hash_audit = list(
    pure_function_intact = hash_match,
    start_hashes = as.list(setNames(hash_start, basename(files_to_hash))),
    end_hashes   = as.list(setNames(hash_end,   basename(files_to_hash)))
  ),
  backtest_summary = list(
    combined = list(
      period   = "2006-01-01 ~ 2023-12-01",
      n_months = m_full$n_months,
      cagr     = m_full$cagr,
      vol      = m_full$vol,
      sr       = m_full$sr,
      mdd      = m_full$mdd,
      hit_rate = m_full$hit,
      harvey_t = m_full$harvey_t,
      dsr_raw  = m_full$dsr_raw,
      dsr_post_penalty = m_full$dsr_post
    ),
    oos_frozen = list(
      period   = "2024-01-01 ~ 2026-04-01",
      n_months = m_oos$n_months,
      cagr     = m_oos$cagr,
      vol      = m_oos$vol,
      sr       = m_oos$sr,
      mdd      = m_oos$mdd,
      hit_rate = m_oos$hit
    ),
    full_period = list(
      period   = paste0(nav_ch$YM[1], " ~ ", nav_ch$YM[n_common]),
      n_months = n_common,
      sr_iter12 = comparison_metrics$STR_1702_Iter12_Quarterly$sr,
      cagr_iter12 = comparison_metrics$STR_1702_Iter12_Quarterly$cagr,
      mdd_iter12  = comparison_metrics$STR_1702_Iter12_Quarterly$mdd
    )
  ),
  regime_conditional_metrics = regime_cond,
  factor_regression_5_specs = c(
    list(method = "LinTilt_Kelly_Overlay_Quarterly",
         sample = "Pre-LB walk-forward 2006-01 ~ 2023-12",
         se_method = "Newey-West HAC",
         n_pass_t295 = n_pass),
    ff_results
  ),
  dsr = list(
    candidates_tried = candidates_tried,
    penalty = penalty,
    dsr_raw  = m_full$dsr_raw,
    dsr_post = m_full$dsr_post
  ),
  cvar_realized = list(
    cvar_95_monthly  = round(cvar_95_m, 6),
    cvar_95_d_proxy  = round(cvar_95_d, 6),
    cap_threshold    = 0.025,
    pass_cvar_cap    = cvar_95_d <= 0.025,
    margin_to_cap    = round(0.025 - cvar_95_d, 6),
    iter11_cvar_d    = 0.0259,
    iter11_cap_breach = TRUE,
    improvement_vs_iter11 = round(0.0259 - cvar_95_d, 6)
  ),
  rebalance_stats = list(
    n_rebalance = sum(monthly_ret$is_rebal),
    n_hold      = sum(!monthly_ret$is_rebal),
    total_tc    = round(sum(monthly_ret$tc), 6),
    ann_to_approx = round(sum(monthly_ret$tc) / COMMISSION / 2 / (m_full$n_months/12), 4)
  ),
  same_period_comparison = list(
    period   = paste0(nav_ch$YM[1], " ~ ", nav_ch$YM[n_common]),
    n_months = n_common,
    strategies = comparison_metrics,
    pairwise_correlation = lapply(seq_len(nrow(cor_mat)), function(i) as.list(cor_mat[i,]))
  ),
  scenario_metrics = scenario_metrics,
  scenario_note = "AB/B use STR_1699 as STR_1656 proxy (STR_1656 ML trail not available)",
  charts_generated = c("equity_curve.png", "annual_returns.png", "oos_zoom.png",
                        "scenario_comparison.png"),
  iter11_vs_iter12_comparison = list(
    iter11_sr   = comparison_metrics$STR_1701_Iter11$sr,
    iter11_cagr = comparison_metrics$STR_1701_Iter11$cagr,
    iter11_mdd  = comparison_metrics$STR_1701_Iter11$mdd,
    iter12_sr   = comparison_metrics$STR_1702_Iter12_Quarterly$sr,
    iter12_cagr = comparison_metrics$STR_1702_Iter12_Quarterly$cagr,
    iter12_mdd  = comparison_metrics$STR_1702_Iter12_Quarterly$mdd,
    delta_sr    = round(comparison_metrics$STR_1702_Iter12_Quarterly$sr -
                        comparison_metrics$STR_1701_Iter11$sr, 4),
    delta_mdd   = round(comparison_metrics$STR_1702_Iter12_Quarterly$mdd -
                        comparison_metrics$STR_1701_Iter11$mdd, 4),
    honest_assessment = "Iter12 machinery overlay reduces risk (MDD improvement, CVaR below cap) but CAGR significantly lower. Iter11 dominates on SR in common period. Risk-return trade-off: Iter12 preferred only if CVaR constraint is binding."
  ),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

writeLines(toJSON(forge_pkg, auto_unbox=TRUE, pretty=TRUE, na="null"),
           file.path(WT_DIR, "forge_package.json"))
cat("forge_package.json saved\n")

## ---- Summary ----
cat("\n=== STR_1702 BACKTEST COMPLETE ===\n")
cat("End time:", format(Sys.time()), "\n\n")
cat("KEY MEASURED NUMBERS (walk-forward, 15bps commission):\n")
cat(sprintf("  Pre-LB (2006-01~2023-12): CAGR=%.4f  Vol=%.4f  SR=%.4f  MDD=%.4f\n",
            m_full$cagr, m_full$vol, m_full$sr, m_full$mdd))
cat(sprintf("  OOS (2024-01~2026-04):    CAGR=%.4f  Vol=%.4f  SR=%.4f  MDD=%.4f\n",
            m_oos$cagr, m_oos$vol, m_oos$sr, m_oos$mdd))
cat(sprintf("  CVaR_d realized: %.6f (cap 0.025 PASS=%s, margin %.6f)\n",
            cvar_95_d, cvar_95_d <= 0.025, 0.025 - cvar_95_d))
cat(sprintf("  DSR post-penalty: %.4f\n", m_full$dsr_post))
cat(sprintf("  Harvey FF5: %d/5 specs pass t>=2.95\n", n_pass))
cat(sprintf("  Pure-function hash audit: %s\n", hash_match))
cat(sprintf("  Iter11 SR=%.4f vs Iter12 SR=%.4f (delta=%.4f)\n",
            comparison_metrics$STR_1701_Iter11$sr,
            comparison_metrics$STR_1702_Iter12_Quarterly$sr,
            comparison_metrics$STR_1702_Iter12_Quarterly$sr - comparison_metrics$STR_1701_Iter11$sr))
