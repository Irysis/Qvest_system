# =============================================================================
# b1_step2_ic_redundancy.R — PG2 forensics B1: deliverables 1 + 2
#   1. b1_factor_ic_table.json   — 7-factor monthly rank-IC diagnostics
#   2. b1_redundancy_matrix.json — Core-4 score corr + factor-return corr
#
# DIAGNOSTIC ONLY. 모든 IC 지표는 advisory (measurement-graduation §3) —
# 의사결정 지표는 PORT_t. 등급 선언 없음.
#
# PIT: factor z @ Date t = month-end(t) Factor DB build (builder Date <= sig_date),
#      Ret_1m @ Date t = calendar month(t)+1 return (b0b/b0e에서 실증 검증).
#      IC[t]는 month(t)+1 종료 후에만 알 수 있는 사후 진단치.
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})

PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- file.path(PROJECT_ROOT, "04_Research/pg2_forensics")
INT_DIR <- file.path(OUT_DIR, "intermediate")

FACTORS_7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap",
               "Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
CORE_4 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
FAMILY <- c(C01_SUE="core_earnings_surprise", C02_EPS_Chg_1m="core_estimate_revision",
            C04_ESBR="core_estimate_breadth", C06_TP_Gap="core_target_price",
            Q07_Earnings_Stability="defense_quality", M08_Residual_Mom="defense_residual_momentum",
            Q25_Ohlson_O="defense_distress")

pan <- as.data.table(read_parquet(file.path(INT_DIR, "factor_panel_7f.parquet")))
pan[, Date := as.Date(Date)]
cat(sprintf("[step2] panel: %d rows, %d dates\n", nrow(pan), uniqueN(pan$Date)))

IC_LABEL <- "diagnostic_only — 의사결정 지표는 PORT_t (rank-IC는 advisory, measurement-graduation §3)"

# ---------------------------------------------------------------------------
# Deliverable 1: 7-factor monthly rank-IC table
# ---------------------------------------------------------------------------
ic_long <- rbindlist(lapply(FACTORS_7, function(f) {
  d <- pan[!is.na(get(f)) & !is.na(Ret_1m),
           .(ic = if (.N >= 30) suppressWarnings(cor(get(f), Ret_1m, method = "spearman")) else NA_real_,
             n_stocks = .N),
           by = Date]
  d[, Factor_Name := f]
  d
}))
ic_long <- ic_long[!is.na(ic)]
fwrite(ic_long, file.path(INT_DIR, "monthly_rank_ic_7f.csv"))

nw_t <- function(x, lag = 3L) {
  x <- x[!is.na(x)]
  if (length(x) < 24) return(NA_real_)
  m <- lm(x ~ 1)
  v <- sandwich::NeweyWest(m, lag = lag, prewhite = FALSE, adjust = TRUE)
  unname(coef(m)[1] / sqrt(v[1, 1]))
}

last36_cut <- sort(unique(ic_long$Date), decreasing = TRUE)[min(36L, uniqueN(ic_long$Date))]

ic_stats <- ic_long[, {
  ics <- ic
  list(
    n_months          = .N,
    mean_rank_ic      = mean(ics),
    icir              = mean(ics) / sd(ics),
    nw_t_lag3         = nw_t(ics, 3L),
    hit_ratio         = mean(ics > 0),
    recent_36m_mean_ic = mean(ics[Date >= last36_cut]),
    recent_36m_hit     = mean(ics[Date >= last36_cut] > 0),
    recent_36m_n       = sum(Date >= last36_cut),
    avg_n_stocks      = mean(n_stocks)
  )
}, by = Factor_Name]
setorder(ic_stats, -mean_rank_ic)
print(ic_stats)

ic_json <- list(
  artifact = "b1_factor_ic_table",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "proxy",
  label = IC_LABEL,
  method = paste(
    "월간 cross-sectional Spearman rank-IC: Z_Score_Aligned(@ score date t, month-end(t) Factor DB,",
    "load_month_factors() 경유 C13/C14/C15 준수) vs Ret_1m(@t, calendar month(t)+1 forward return,",
    "production alpha panel). Universe = production panel rows (K200∪KQ150 + production filters).",
    "NW-t = Newey-West lag-3 t-stat of monthly IC series (sandwich::NeweyWest, intercept-only lm).",
    "recent_36m = 마지막 36개 IC 가용 월."),
  alignment_verification = list(
    ret_1m_covers = "calendar month(t)+1 (corr 0.8985 vs BM month t+1, b0b_align_check.R)",
    factor_db_vintage = "month-end(t) (factor_db_YYYYMM Date col = month-end, builder PIT Date <= sig_date)",
    production_coherence = "top-20 EW recon vs ret_orig pearson 0.81 @ realized_ym = month(t)+2 (b0e)"
  ),
  period = list(first_score_date = as.character(min(ic_long$Date)),
                last_score_date = as.character(max(ic_long$Date)),
                recent_36m_from = as.character(last36_cut)),
  factors = lapply(seq_len(nrow(ic_stats)), function(i) {
    r <- ic_stats[i]
    list(
      factor = r$Factor_Name,
      family = unname(FAMILY[r$Factor_Name]),
      sleeve = ifelse(r$Factor_Name %in% CORE_4, "core (IC-weighted, 65%)", "defense (EW, 35%)"),
      n_months = r$n_months,
      mean_rank_ic = round(r$mean_rank_ic, 5),
      icir = round(r$icir, 4),
      nw_t_lag3 = round(r$nw_t_lag3, 3),
      hit_ratio = round(r$hit_ratio, 4),
      recent_36m_mean_ic = round(r$recent_36m_mean_ic, 5),
      recent_36m_hit = round(r$recent_36m_hit, 4),
      recent_36m_n = r$recent_36m_n,
      avg_n_stocks = round(r$avg_n_stocks, 1),
      label = IC_LABEL
    )
  })
)
write_json(ic_json, file.path(OUT_DIR, "b1_factor_ic_table.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[step2] wrote b1_factor_ic_table.json\n")

# ---------------------------------------------------------------------------
# Deliverable 2: Core-4 redundancy matrix
# ---------------------------------------------------------------------------
# (a) cross-sectional score correlation, averaged over months
pair_grid <- CJ(f1 = CORE_4, f2 = CORE_4)[f1 < f2]
score_corr_m <- rbindlist(lapply(seq_len(nrow(pair_grid)), function(i) {
  f1 <- pair_grid$f1[i]; f2 <- pair_grid$f2[i]
  d <- pan[!is.na(get(f1)) & !is.na(get(f2)),
           .(rho = if (.N >= 30) suppressWarnings(cor(get(f1), get(f2), method = "spearman")) else NA_real_),
           by = Date]
  d[, `:=`(f1 = f1, f2 = f2)]
  d
}))
score_corr_avg <- score_corr_m[!is.na(rho), .(avg_rho = mean(rho), n_months = .N), by = .(f1, f2)]
print(score_corr_avg)

# (b) factor top-quintile EW monthly forward-return series (DIAGNOSTIC series —
#     단월 cross-sectional mean(Ret_1m), 복리합성/NAV 아님; 백테스트 주장 아님)
q_series <- rbindlist(lapply(CORE_4, function(f) {
  d <- pan[!is.na(get(f)) & !is.na(Ret_1m)]
  d[, qrank := frank(-get(f), ties.method = "average") / .N, by = Date]
  univ <- d[, .(univ_ret = mean(Ret_1m)), by = Date]
  tq <- d[qrank <= 0.20, .(q1_ret = mean(Ret_1m), n_q1 = .N), by = Date]
  out <- merge(tq, univ, by = "Date")
  out[, excess_ret := q1_ret - univ_ret]
  out[, Factor_Name := f]
  out
}))
fwrite(q_series, file.path(INT_DIR, "core4_top_quintile_series.csv"))

qw_raw <- dcast(q_series, Date ~ Factor_Name, value.var = "q1_ret")
qw_exc <- dcast(q_series, Date ~ Factor_Name, value.var = "excess_ret")
cor_raw <- cor(as.matrix(qw_raw[, ..CORE_4]), use = "pairwise.complete.obs")
cor_exc <- cor(as.matrix(qw_exc[, ..CORE_4]), use = "pairwise.complete.obs")
cat("raw top-quintile return corr:\n"); print(round(cor_raw, 3))
cat("market-excess top-quintile return corr:\n"); print(round(cor_exc, 3))

off_diag <- function(m) m[upper.tri(m)]
avg_score_rho <- mean(score_corr_avg$avg_rho)
avg_ret_rho_raw <- mean(off_diag(cor_raw))
avg_ret_rho_exc <- mean(off_diag(cor_exc))

# verdict rubric (명시 기준 — 진단용)
verdict <- if (avg_score_rho > 0.4 && avg_ret_rho_exc > 0.6) {
  "단일 Earnings 베팅 (score corr 높음 + excess return corr 높음)"
} else if (avg_score_rho < 0.3 && avg_ret_rho_exc < 0.5) {
  "내부 분산 존재 (score corr 낮음 + excess return corr 낮음~중간)"
} else {
  "중간 — 부분 중복 (아래 수치 참조)"
}

mat_to_named <- function(m) {
  l <- lapply(seq_len(nrow(m)), function(i) as.list(setNames(round(m[i, ], 4), colnames(m))))
  setNames(l, rownames(m))
}

red_json <- list(
  artifact = "b1_redundancy_matrix",
  generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  metric_type = "proxy",
  label = "diagnostic_only — top-quintile EW 월수익 시계열은 진단용 (백테스트 아님, NAV 합성 없음). 의사결정 지표는 PORT_t.",
  method = list(
    score_corr = "월별 cross-sectional Spearman corr (공통 비-NA ticker, n>=30), 268개월 평균",
    return_corr = paste("각 팩터 top-quintile(상위 20%) EW 월간 forward return 시계열(단월 mean(Ret_1m), 합성 없음)",
                        "간 Pearson corr. raw = 그대로 / market_excess = 동월 universe EW mean 차감(시장베타 제거)"),
    verdict_rubric = "단일베팅: avg_score_rho>0.4 AND avg_excess_ret_rho>0.6 / 내부분산: avg_score_rho<0.3 AND avg_excess_ret_rho<0.5 / 그 외 중간"
  ),
  score_correlation = list(
    pairwise_avg = lapply(seq_len(nrow(score_corr_avg)), function(i) {
      r <- score_corr_avg[i]
      list(pair = paste(r$f1, "x", r$f2), avg_spearman = round(r$avg_rho, 4), n_months = r$n_months)
    }),
    avg_pairwise = round(avg_score_rho, 4)
  ),
  return_correlation = list(
    raw = mat_to_named(cor_raw),
    market_excess = mat_to_named(cor_exc),
    avg_pairwise_raw = round(avg_ret_rho_raw, 4),
    avg_pairwise_market_excess = round(avg_ret_rho_exc, 4),
    note = "raw corr은 시장베타 공통항으로 상향 편의 — 중복 판정은 market_excess 기준"
  ),
  verdict = verdict
)
write_json(red_json, file.path(OUT_DIR, "b1_redundancy_matrix.json"), pretty = TRUE, auto_unbox = TRUE)
cat("[step2] wrote b1_redundancy_matrix.json\n")
cat("[step2] DONE\n")
