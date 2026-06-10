#!/usr/bin/env Rscript
# dpl_best_full_eval.R — Qvest v8.x: DPL best-cell FULL contract-grade eval (마지막 희망 판정).
#
# 본 스크립트는 dpl_eval_contract.R(portfolio-α t NW lag3 / IR / net SR / TE / TO, 단일 contract 경로)에
#   추가로 (a) OOS retention (early≤2015 vs late>2015 active-Sharpe), (b) Carhart4 t (NW lag6),
#   (c) DSR(honest n_trials=6) 를 합쳐 best cell 1건의 최종 판정표를 만든다.
# 비교: STR_1715(incumbent α-t 5.34 / net SR 1.07 / OOS retention 0.91) ·
#       EW_top20 / MVO_2stage · (참고치) 90f DPL baseline α-t 2.906 / 8f net SR 0.35.
# metric_type=backtested. 자체합성 금지: 모든 backtest 수치는 build_benchmark_compare() 단일경로.
#   retention/Carhart는 contract가 산출하는 active-Sharpe와 표준 회귀(carhart_4factor.R) — 손계산 backtest 아님.

suppressPackageStartupMessages({ library(arrow); library(data.table); library(jsonlite) })

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
WTDIR <- Sys.getenv("DPL_WT_DIR", "WT_DPL_ALPHASEARCH2")
OUT  <- file.path(ROOT, "stage_artifacts", WTDIR)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/attribution/carhart_4factor.R"))

ym_key <- function(d) format(as.Date(d), "%Y-%m")

# ── benchmark (month-key) ─────────────────────────────────────────────
bm <- as.data.table(read_parquet(file.path(OUT, "benchmark_monthly.parquet")))
bm[, ymk := ym_key(date)]
bm_keyed <- bm[, .(ymk, benchmark_ret = BM_Ret_1m)]

# ── series 적재 ───────────────────────────────────────────────────────
dpl  <- as.data.table(read_parquet(file.path(OUT, "dpl_best_net_returns.parquet")))
base <- as.data.table(read_parquet(file.path(OUT, "baselines_net_returns.parquet")))
str1715 <- as.data.table(read_parquet(
  file.path(ROOT, "stage_artifacts/WT_WT-S20260504_002/str1715_monthly_returns.parquet")))

series_list <- list()
d <- dpl[, .(ymk = ym_key(date), ret_net, traded)]
series_list[["DPL_best"]] <- d
for (mth in unique(base$method)) {
  series_list[[mth]] <- base[method == mth, .(ymk = ym_key(date), ret_net, traded)]
}
series_list[["STR_1715"]] <- str1715[, .(ymk = ym_key(date), ret_net, traded = NA_real_)]

# DPL OOS 윈도우로 모든 비교군 정렬 (apples-to-apples)
oos_ymk <- sort(unique(d$ymk))

# ── contract-grade 1종 평가 (portfolio-α t NW lag3 / IR / net SR / TE / TO) ──
eval_one <- function(name, dt) {
  dt <- merge(dt[ymk %in% oos_ymk], bm_keyed, by = "ymk")
  if (nrow(dt) == 0) return(NULL)
  setorder(dt, ymk)
  dates <- as.Date(paste0(dt$ymk, "-01"))
  pr <- data.table(date = dates, ret_net = dt$ret_net, frequency = "monthly")
  br <- data.table(date = dates, benchmark_ret = dt$benchmark_ret,
                   benchmark_id = "KOSPI200_total_return")
  bc <- build_benchmark_compare(pr, br, run_id = paste0("dpl_full_", name),
                                strategy_id = name, annualization_factor = 12)
  getbc <- function(nm) { v <- bc[metric_name == nm, active_value]; if (length(v)==0) NA_real_ else as.numeric(v[1]) }
  active <- dt$ret_net - dt$benchmark_ret
  net_sr <- mean(active) / sd(active) * sqrt(12)
  to_ann <- if (all(is.na(dt$traded))) NA_real_ else mean(dt$traded, na.rm = TRUE) * 12
  list(strategy = name, n_months = nrow(dt),
       portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
       portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
       information_ratio = getbc("Information_Ratio"),
       alpha_annualized  = getbc("Alpha_Annualized"),
       net_active_sr = net_sr, tracking_error = getbc("Tracking_Error"),
       turnover_annual = to_ann, metric_type = "backtested")
}

res <- list()
for (nm in names(series_list)) {
  r <- eval_one(nm, series_list[[nm]])
  if (!is.null(r)) res[[nm]] <- r
}

# ── OOS retention: early(≤2015) vs late(>2015) active-Sharpe (단일 OOS 시계열 시간분할) ──
#    measurement-graduation §3 oos_retention≥0.7. 이 sweep은 full-sample IS refit series 미보유 →
#    walk-forward OOS series를 2015 경계로 분할해 실현성과의 시간 안정성(early=IS proxy, late=OOS)으로 측정.
active_sharpe <- function(dt) {
  dt <- merge(dt[ymk %in% oos_ymk], bm_keyed, by = "ymk"); setorder(dt, ymk)
  a <- dt$ret_net - dt$benchmark_ret
  if (length(a) < 6 || sd(a) == 0) return(NA_real_)
  mean(a) / sd(a) * sqrt(12)
}
retention_split <- function(dt, cut = "2015-12") {
  dt <- merge(dt[ymk %in% oos_ymk], bm_keyed, by = "ymk"); setorder(dt, ymk)
  early <- dt[ymk <= cut]; late <- dt[ymk > cut]
  se <- if (nrow(early) >= 6 && sd(early$ret_net - early$benchmark_ret) > 0)
          mean(early$ret_net - early$benchmark_ret)/sd(early$ret_net - early$benchmark_ret)*sqrt(12) else NA_real_
  sl <- if (nrow(late) >= 6 && sd(late$ret_net - late$benchmark_ret) > 0)
          mean(late$ret_net - late$benchmark_ret)/sd(late$ret_net - late$benchmark_ret)*sqrt(12) else NA_real_
  ret <- if (!is.na(se) && se != 0) sl / se else NA_real_
  list(is_early_sr = se, oos_late_sr = sl, retention = ret,
       n_early = nrow(early), n_late = nrow(late))
}

# ── Carhart4 t (NW lag6) — KR factor returns(.cache/kr_factor_returns_v2.parquet) ──
fr_raw <- as.data.table(read_parquet(file.path(ROOT, ".cache/kr_factor_returns_v2.parquet")))
fr_raw[, Date := as.Date(Date)]
fr_raw[, ymk := ym_key(Date)]
# Carhart4 = MKT/SMB/HML/UMD; UMD = WML(winners-minus-losers momentum). RF로 excess 변환.
fr <- fr_raw[, .(ymk, MKT, SMB, HML, UMD = WML, RF)]

carhart_for <- function(dt) {
  dt <- merge(dt[ymk %in% oos_ymk], fr, by = "ymk")
  if (nrow(dt) < 24) return(list(alpha_t = NA_real_, alpha_annualized = NA_real_,
                                 r_squared = NA_real_, n = nrow(dt)))
  setorder(dt, ymk)
  pr <- data.table(Date = as.Date(paste0(dt$ymk, "-01")),
                   port_excess_ret = dt$ret_net - dt$RF)
  frd <- data.table(Date = as.Date(paste0(dt$ymk, "-01")),
                    MKT = dt$MKT, SMB = dt$SMB, HML = dt$HML, UMD = dt$UMD)
  ch <- carhart_4factor(pr, frd, nw_lag = 6L)
  list(alpha_t = ch$alpha_t, alpha_annualized = ch$alpha_annualized,
       r_squared = ch$r_squared, n = ch$n,
       betas = as.list(ch$betas), beta_t = as.list(ch$beta_t))
}

# augment res with retention + Carhart (DPL_best 중심, 비교군도)
for (nm in names(res)) {
  rt <- retention_split(series_list[[nm]])
  ch <- carhart_for(series_list[[nm]])
  res[[nm]]$oos_retention_early_late <- rt$retention
  res[[nm]]$is_early_sr <- rt$is_early_sr
  res[[nm]]$oos_late_sr <- rt$oos_late_sr
  res[[nm]]$carhart4_alpha_t <- ch$alpha_t
  res[[nm]]$carhart4_alpha_ann <- ch$alpha_annualized
  res[[nm]]$carhart4_r2 <- ch$r_squared
}

# ── DSR (honest n_trials = 6, sweep search size) — sweep_results.json 우선, 없으면 NA ──
dsr_best <- NA_real_; dsr_ntrials <- NA_integer_
swp <- file.path(OUT, "sweep_results.json")
if (file.exists(swp)) {
  sj <- tryCatch(fromJSON(swp), error = function(e) NULL)
  if (!is.null(sj) && !is.null(sj$best)) {
    dsr_best <- if (!is.null(sj$best$DSR_honest6)) sj$best$DSR_honest6
                else if (!is.null(sj$best$DSR)) sj$best$DSR else NA_real_
    dsr_ntrials <- if (!is.null(sj$best$DSR_n_trials_honest)) sj$best$DSR_n_trials_honest
                   else if (!is.null(sj$n_trials)) sj$n_trials else NA_integer_
  }
}
if (!is.null(res[["DPL_best"]])) {
  res[["DPL_best"]]$DSR <- dsr_best
  res[["DPL_best"]]$DSR_n_trials <- dsr_ntrials
}

# ── 출력 ──────────────────────────────────────────────────────────────
cat("\n===== DPL best-cell FULL contract-grade eval (OOS, NW lag-3) =====\n")
cat(sprintf("WT dir: %s | OOS window: %s .. %s (%d months)\n",
            WTDIR, oos_ymk[1], oos_ymk[length(oos_ymk)], length(oos_ymk)))
cat(sprintf("%-12s %8s %9s %7s %7s %9s %9s %7s\n",
            "strategy","alpha_t","p_val","IR","net_SR","C4_a_t","retention","TO/yr"))
ord <- c("DPL_best","EW_top20","MVO_2stage","STR_1715")
for (nm in ord) {
  if (is.null(res[[nm]])) next
  r <- res[[nm]]
  cat(sprintf("%-12s %8.3f %9.4f %7.3f %7.3f %9.3f %9s %7s\n",
              r$strategy, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue,
              r$information_ratio, r$net_active_sr,
              ifelse(is.na(r$carhart4_alpha_t), NA_real_, r$carhart4_alpha_t),
              ifelse(is.na(r$oos_retention_early_late), "NA", sprintf("%.3f", r$oos_retention_early_late)),
              ifelse(is.na(r$turnover_annual), "NA", sprintf("%.2f", r$turnover_annual))))
}
db <- res[["DPL_best"]]
cat("\n--- DPL_best detail ---\n")
cat(sprintf("  portfolio-α t (NW lag3) = %.3f  (p=%.4f)\n", db$portfolio_alpha_t_nw_lag3, db$portfolio_alpha_t_pvalue))
cat(sprintf("  Carhart4 α t (NW lag6)  = %.3f  (α_ann=%.4f, R²=%.3f)\n",
            db$carhart4_alpha_t, db$carhart4_alpha_ann, db$carhart4_r2))
cat(sprintf("  net active SR (full OOS)= %.3f\n", db$net_active_sr))
cat(sprintf("  OOS retention (≤2015 vs >2015): early_SR=%.3f late_SR=%.3f retention=%.3f %s\n",
            db$is_early_sr, db$oos_late_sr, db$oos_retention_early_late,
            ifelse(!is.na(db$oos_retention_early_late) && db$oos_retention_early_late >= 0.7, "[PASS]","[fail]")))
cat(sprintf("  DSR (honest n_trials=%s) = %s\n", db$DSR_n_trials,
            ifelse(is.na(db$DSR), "NA", sprintf("%.3f", db$DSR))))
cat(sprintf("  turnover/yr = %.2f\n", db$turnover_annual))

cat("\nHurdle (Harvey-Liu-Zhu 2016): portfolio-α t >= 2.95\n")
cat("references: STR_1715 incumbent α-t 5.34 / net SR 1.07 / OOS retention 0.91\n")
cat("            90f DPL baseline α-t 2.906 (memory line15 '천장') / 8f DPL net SR 0.35\n")

write_json(list(wt_dir = WTDIR,
                oos_window = c(oos_ymk[1], oos_ymk[length(oos_ymk)]),
                n_oos_months = length(oos_ymk),
                results = res),
           file.path(OUT, "dpl_best_full_eval.json"), auto_unbox = TRUE, pretty = TRUE)
cat(sprintf("\n[eval] -> %s\n", file.path(OUT, "dpl_best_full_eval.json")))
