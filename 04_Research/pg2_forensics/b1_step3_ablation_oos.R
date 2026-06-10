# =============================================================================
# b1_step3_ablation_oos.R — PG2 forensics B1: deliverables 3 + 4
#   3. b1_family_attribution.json  — sleeve ablation (Core/Defense/blend + 단독 defense)
#   4. b1_oos27m_decomposition.json — 최근 27개월 sleeve·regime 분해
#
# DIAGNOSTIC ONLY — 등급 선언 없음. top-20 EW 재구성은 production(λ-tilt Iter31,
# 유동성 필터, buffer zone)의 "근사"이며 production 재현이 아님. 실제 book 수익률
# 권위 = period_returns_layer5.csv ret_orig (backtested).
#
# 포트폴리오 수익률: PerformanceAnalytics::Return.portfolio ONLY (자체합성 금지).
# SR/MDD: SharpeRatio.annualized / maxDrawdown / Return.annualized / StdDev.annualized.
#
# PIT: score @ Date t = month-end(t) 데이터, Ret_1m @ t = calendar month(t)+1 수익
#      (b0b/b0e 실증 검증 — weights 인덱스를 수익월 직전 월말로 두어 lookahead 없음).
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PROD_DIR <- file.path(PROJECT_ROOT, "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2")
OUT_DIR <- file.path(PROJECT_ROOT, "04_Research/pg2_forensics")
INT_DIR <- file.path(OUT_DIR, "intermediate")

pan <- as.data.table(read_parquet(file.path(INT_DIR, "factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]

# ---- sanity: mid-sample NA Ret_1m must be 0 (all NAs at last date) ----
last_d <- max(pan$Date)
n_na_mid <- pan[Date < last_d, sum(is.na(Ret_1m))]
cat(sprintf("[step3] mid-sample NA Ret_1m: %d (expect 0) | last-date rows: %d (all NA, excluded)\n",
            n_na_mid, pan[Date == last_d, .N]))
stopifnot(n_na_mid == 0)

# ---- blend formula verification: score_eff ?= 0.65*core + 0.35*defense ----
chk <- pan[!is.na(score_eff) & !is.na(score_core_z) & !is.na(score_defense_z)]
blend_recon <- chk[, 0.65 * score_core_z + 0.35 * score_defense_z]
cat(sprintf("[step3] blend formula check: cor(0.65*core+0.35*def, score_eff) = %.4f | max|diff| = %.4g\n",
            cor(blend_recon, chk$score_eff), max(abs(blend_recon - chk$score_eff))))
BLEND_EXACT <- max(abs(blend_recon - chk$score_eff)) < 1e-6

# ---- variant score definitions ----
DEF_F <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
pan[, score_blend_q07 := 0.65 * score_core_z + 0.35 * Q07_Earnings_Stability]
pan[, score_blend_m08 := 0.65 * score_core_z + 0.35 * M08_Residual_Mom]
pan[, score_blend_q25 := 0.65 * score_core_z + 0.35 * Q25_Ohlson_O]
pan[, score_def_q07 := Q07_Earnings_Stability]
pan[, score_def_m08 := M08_Residual_Mom]
pan[, score_def_q25 := Q25_Ohlson_O]

VARIANTS <- c(
  blend_65_35   = "score_eff",
  core_only     = "score_core_z",
  defense_only  = "score_defense_z",
  blend_core65_q07only = "score_blend_q07",
  blend_core65_m08only = "score_blend_m08",
  blend_core65_q25only = "score_blend_q25",
  defense_q07_only = "score_def_q07",
  defense_m08_only = "score_def_m08",
  defense_q25_only = "score_def_q25"
)

month_end <- function(d) seq(as.Date(format(d, "%Y-%m-01")), by = "1 month", length.out = 2)[2] - 1L
# weight index = month-end(t) (수익월 t+1 시작 직전), return index = month-end(t+1)
pan[, w_idx := as.Date(sapply(Date, function(d) as.character(month_end(d))))]
pan[, r_idx := as.Date(sapply(Date, function(d) as.character(month_end(seq(as.Date(d), by = "1 month", length.out = 2)[2]))))]

bt_dates <- sort(unique(pan[Date < last_d, Date]))  # 267 score dates with returns

# ---- selection: top-20 per variant per date ----
sel_list <- list()
for (v in names(VARIANTS)) {
  scol <- VARIANTS[[v]]
  s <- pan[Date %in% bt_dates & !is.na(get(scol)),
           .SD[order(-get(scol))][1:min(20, .N)],
           by = Date, .SDcols = c("Ticker", scol, "Ret_1m", "w_idx", "r_idx", "regime_state")]
  s[, variant := v]
  sel_list[[v]] <- s[, .(Date, Ticker, Ret_1m, w_idx, r_idx, regime_state, variant)]
}
sel <- rbindlist(sel_list)
fwrite(sel, file.path(INT_DIR, "variant_top20_selections.csv"))

# ---- Return.portfolio per variant ----
run_variant <- function(v) {
  s <- sel[variant == v]
  tickers <- sort(unique(s$Ticker))
  # R: wide xts of held-stock forward returns indexed at month-end(t+1)
  Rdt <- dcast(s, r_idx ~ Ticker, value.var = "Ret_1m")
  Rxts <- xts(as.matrix(Rdt[, -1]), order.by = Rdt$r_idx)
  Rxts[is.na(Rxts)] <- 0  # non-held months: weight 0이므로 영향 없음
  # W: EW 1/N at month-end(t)
  s[, w := 1 / .N, by = Date]
  Wdt <- dcast(s, w_idx ~ Ticker, value.var = "w", fill = 0)
  Wxts <- xts(as.matrix(Wdt[, -1]), order.by = Wdt$w_idx)
  Wxts <- Wxts[, colnames(Rxts)]
  pf <- Return.portfolio(Rxts, weights = Wxts, verbose = TRUE)
  ret <- pf$returns
  colnames(ret) <- v
  # one-way turnover (진단): 0.5 * sum|BOP_t - EOP_{t-1}| (첫 달 = 1.0 full buy)
  bop <- pf$BOP.Weight; eop <- pf$EOP.Weight
  to <- rep(NA_real_, nrow(ret))
  to[1] <- 1.0
  if (nrow(ret) > 1) {
    for (i in 2:nrow(ret)) to[i] <- 0.5 * sum(abs(as.numeric(bop[i, ]) - as.numeric(eop[i - 1, ])))
  }
  list(ret = ret, turnover = xts(to, order.by = index(ret)))
}

cat("[step3] running Return.portfolio for", length(VARIANTS), "variants...\n")
res <- lapply(names(VARIANTS), run_variant)
names(res) <- names(VARIANTS)

R_all <- do.call(merge, lapply(res, `[[`, "ret"))
TO_all <- do.call(merge, lapply(res, `[[`, "turnover"))
colnames(TO_all) <- names(VARIANTS)

# net: production cost 공식 ret_net = ret_gross - 0.0015 * one-way turnover (estimated)
R_net <- R_all - 0.0015 * TO_all
colnames(R_net) <- paste0(colnames(R_all), "_net")

# ---- production authority series (backtested) ----
pr <- fread(file.path(PROD_DIR, "04_backtest_results/period_returns_layer5.csv"))
# realized_ym m covers calendar m-1 → calendar month-end index = month_end(m-1)
pr[, cal_month := format(seq(as.Date(paste0(realized_ym, "-01")), by = "-1 month", length.out = 2)[2], "%Y-%m"), by = realized_ym]
pr[, r_idx := as.Date(sapply(paste0(cal_month, "-01"), function(d) as.character(month_end(as.Date(d)))))]
prod_xts <- xts(pr$ret_orig, order.by = pr$r_idx); colnames(prod_xts) <- "production_ret_orig"

metrics_of <- function(R) {
  R <- na.omit(R)
  list(
    n_months = nrow(R),
    ann_return = as.numeric(Return.annualized(R, scale = 12)),
    ann_vol = as.numeric(StdDev.annualized(R, scale = 12)),
    sharpe = as.numeric(SharpeRatio.annualized(R, Rf = 0, scale = 12)),
    mdd = as.numeric(maxDrawdown(R))
  )
}

full_stats <- list()
for (v in names(VARIANTS)) {
  g <- metrics_of(R_all[, v])
  n <- metrics_of(R_net[, paste0(v, "_net")])
  full_stats[[v]] <- list(
    gross = lapply(g, function(x) round(x, 4)),
    net_est = c(lapply(n, function(x) round(x, 4)),
                list(note = "production cost 공식 ret - 0.0015×one-way TO (metric_type=estimated)")),
    avg_oneway_turnover_monthly = round(mean(as.numeric(TO_all[, v]), na.rm = TRUE), 4)
  )
}
prod_stats <- metrics_of(prod_xts)

sr_g <- function(v) full_stats[[v]]$gross$sharpe
mdd_g <- function(v) full_stats[[v]]$gross$mdd

# 포트 간 corr (gross)
cor_var <- cor(na.omit(R_all), use = "pairwise.complete.obs")

fam_json <- list(
  artifact = "b1_family_attribution",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "proxy",
  label = paste("diagnostic_only — top-20 EW 재구성은 production(λ-tilt Iter31 + 유동성 필터 + buffer)의",
                "근사이며 production 재현 아님. 실제 book 수익률 권위 = period_returns_layer5.csv ret_orig",
                "(metric_type=backtested). 등급 선언 금지."),
  method = list(
    construction = "각 score 상위 20종목 EW, 월간 리밸런스. Return.portfolio(PerformanceAnalytics) 사용 — 자체합성 없음",
    pit = "score @ Date t = month-end(t) 데이터 / 수익 = calendar month(t)+1 (Ret_1m, b0b/b0e 검증). weights 인덱스 = month-end(t)",
    blend_formula = sprintf("score_eff = 0.65*score_core_z + 0.35*score_defense_z (검증: exact=%s)", BLEND_EXACT),
    net_cost = "production 공식 ret_gross - 0.0015 × one-way turnover (estimated 라벨)",
    period = sprintf("%s ~ %s score dates → calendar %s ~ %s 수익월 (267개월)",
                     min(bt_dates), max(bt_dates),
                     format(min(index(R_all)), "%Y-%m"), format(max(index(R_all)), "%Y-%m"))
  ),
  production_authority = c(lapply(prod_stats, function(x) round(x, 4)),
                           list(metric_type = "backtested",
                                source = "period_returns_layer5.csv ret_orig (Iter31 base, cost embedded)")),
  variants = full_stats,
  delta = list(
    dSR_blend_minus_core = round(sr_g("blend_65_35") - sr_g("core_only"), 4),
    dMDD_blend_minus_core = round(mdd_g("blend_65_35") - mdd_g("core_only"), 4),
    dSR_blend_minus_defense = round(sr_g("blend_65_35") - sr_g("defense_only"), 4),
    dMDD_blend_minus_defense = round(mdd_g("blend_65_35") - mdd_g("defense_only"), 4),
    note = "gross 기준. MDD 음수 delta = blend가 MDD 더 얕음(개선)"
  ),
  variant_return_correlation_gross = {
    l <- lapply(seq_len(nrow(cor_var)), function(i) as.list(setNames(round(cor_var[i, ], 3), colnames(cor_var))))
    setNames(l, rownames(cor_var))
  }
)
write_json(fam_json, file.path(OUT_DIR, "b1_family_attribution.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[step3] wrote b1_family_attribution.json\n")

# ---------------------------------------------------------------------------
# Deliverable 4: OOS 27m decomposition (calendar 2024-02 ~ 2026-04 수익월)
# ---------------------------------------------------------------------------
oos_r_from <- index(R_all)[length(index(R_all)) - 26]  # 마지막 27개 수익월
R_oos <- R_all[index(R_all) >= oos_r_from]
cat(sprintf("[step3] OOS window: %s ~ %s (%d months)\n",
            format(min(index(R_oos)), "%Y-%m"), format(max(index(R_oos)), "%Y-%m"), nrow(R_oos)))

oos_stats <- lapply(names(VARIANTS), function(v) {
  m <- metrics_of(R_oos[, v])
  lapply(m, function(x) round(x, 4))
})
names(oos_stats) <- names(VARIANTS)

# regime 분해: score date t의 regime_state 기준 (수익월 = t+1)
reg_map <- unique(pan[Date %in% bt_dates, .(Date, regime_state, r_idx)])
reg_map <- reg_map[, .(regime_state = regime_state[1]), by = .(Date, r_idx)]
oos_reg <- reg_map[r_idx >= oos_r_from]
Rdt_oos <- as.data.table(R_oos); Rdt_oos[, r_idx := index(R_oos)]
Rreg <- merge(Rdt_oos, oos_reg[, .(r_idx, regime_state)], by = "r_idx")
reg_decomp <- Rreg[, c(.(n_months = .N),
                       lapply(.SD, function(x) round(mean(x), 5))),
                   by = regime_state, .SDcols = names(VARIANTS)]
print(reg_decomp)

# sleeve 원천: blend top-20과 core/defense top-20 명단 중첩 (OOS 월)
oos_dates <- sort(unique(oos_reg$Date))
ovl <- sel[Date %in% oos_dates & variant %in% c("blend_65_35","core_only","defense_only")]
ovl_w <- ovl[, .(tickers = list(Ticker)), by = .(Date, variant)]
ovl_stats <- rbindlist(lapply(oos_dates, function(d) {
  b <- ovl_w[Date == d & variant == "blend_65_35", tickers][[1]]
  c_ <- ovl_w[Date == d & variant == "core_only", tickers][[1]]
  df <- ovl_w[Date == d & variant == "defense_only", tickers][[1]]
  data.table(Date = d,
             n_blend_in_core = length(intersect(b, c_)),
             n_blend_in_defense = length(intersect(b, df)))
}))
# blend vs sleeve 수익 corr (OOS)
cor_oos_core <- cor(as.numeric(R_oos[, "blend_65_35"]), as.numeric(R_oos[, "core_only"]))
cor_oos_def  <- cor(as.numeric(R_oos[, "blend_65_35"]), as.numeric(R_oos[, "defense_only"]))

# production 최근 27 rows (참조)
pr_oos <- tail(pr[order(r_idx)], 27)
prod_oos_xts <- xts(pr_oos$ret_orig, order.by = pr_oos$r_idx); colnames(prod_oos_xts) <- "prod"
prod_oos_stats <- metrics_of(prod_oos_xts)
prod_oos_reg <- pr_oos[, .(n = .N, mean_ret_orig = round(mean(ret_orig), 5)), by = regime]

LOW_INFO <- "27m은 PASS_LOW_INFO 영역 (Sharpe SE ±0.6) — admission 근거 사용 금지"

oos_json <- list(
  artifact = "b1_oos27m_decomposition",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "proxy",
  label = LOW_INFO,
  label2 = "diagnostic_only — top-20 EW 근사 (production 재현 아님). 등급/admission 판단 금지.",
  window = list(
    return_months = sprintf("%s ~ %s (27개월)", format(min(index(R_oos)), "%Y-%m"), format(max(index(R_oos)), "%Y-%m")),
    score_dates = sprintf("%s ~ %s", min(oos_dates), max(oos_dates))
  ),
  variant_stats_27m = oos_stats,
  regime_decomposition = lapply(seq_len(nrow(reg_decomp)), function(i) as.list(reg_decomp[i])),
  sleeve_source = list(
    avg_blend_top20_overlap_with_core_top20 = round(mean(ovl_stats$n_blend_in_core), 2),
    avg_blend_top20_overlap_with_defense_top20 = round(mean(ovl_stats$n_blend_in_defense), 2),
    cor_blend_vs_core_27m = round(cor_oos_core, 4),
    cor_blend_vs_defense_27m = round(cor_oos_def, 4),
    note = "명단 중첩(20명 중) + 월수익 corr — blend 성과의 sleeve 원천 진단"
  ),
  production_reference_27rows = c(
    lapply(prod_oos_stats, function(x) round(x, 4)),
    list(metric_type = "backtested",
         calendar_coverage = sprintf("realized_ym %s~%s = calendar %s~%s",
                                     pr_oos[1, realized_ym], pr_oos[.N, realized_ym],
                                     pr_oos[1, cal_month], pr_oos[.N, cal_month]),
         regime_breakdown = lapply(seq_len(nrow(prod_oos_reg)), function(i) as.list(prod_oos_reg[i])))
  )
)
write_json(oos_json, file.path(OUT_DIR, "b1_oos27m_decomposition.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[step3] wrote b1_oos27m_decomposition.json\n")

# intermediates 보존
saveRDS(list(R_gross = R_all, R_net = R_net, TO = TO_all, prod = prod_xts),
        file.path(INT_DIR, "variant_returns_xts.rds"))
cat("[step3] DONE\n")
