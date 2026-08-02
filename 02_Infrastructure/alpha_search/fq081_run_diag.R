# =============================================================================
# fq081_run_diag.R — FQ-081 3-arm 실측 진단 (canonical_screen_bt 권위)
#   arm A : 무조건부  ΔPM, ΔATO                      (baseline)
#   arm B : 업종내 demean  ΔPM, ΔATO                 (조건화 축 1: 업종 상대)
#   arm C : B + 업종내 수준 + 수준×변화 교호항        (조건화 축 2: 경쟁위치 교호)
#   결합기는 3 arm 공통 = 확장창 Fama-MacBeth (동일 추정기·중첩 피처집합)
#     → A→B→C 증분이 "조건화 축의 순효과"로 격리된다.
#   보조: A0/B0 = 동일가중 z 합 (추정기 없는 sanity)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(dplyr) })
setDTthreads(2)

ROOT <- local({
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd()))
    if (nzchar(p) && file.exists(file.path(p, "CLAUDE.md"))) return(gsub("\\\\", "/", p))
  stop("root")
})
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT, "02_Infrastructure/alpha_search/fq081_dupont_panel.R"))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

OUT <- file.path(ROOT, "stage_artifacts", "alpha_search", "FQ081_diag")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

TOP_N   <- 25L
COST    <- 15
START   <- "2005-01-01"
MIN_FM  <- 36L

cat("\n[FQ081] 1) 재무 vintage 패널\n")
fv <- fq081_build_fundamental_vintages(CACHE_DIR)
cat(sprintf("  vintages=%d | tickers=%d | Factor_Date %s ~ %s\n",
            nrow(fv), uniqueN(fv$Ticker), min(fv$Factor_Date), max(fv$Factor_Date)))

cat("[FQ081] 2) 월간 패널 (stored Ret)\n")
mon <- fq081_build_monthly_panel(CACHE_DIR)
cat(sprintf("  rows=%d | months=%d | %s ~ %s\n", nrow(mon), uniqueN(mon$ym),
            min(mon$ym), max(mon$ym)))
bmm <- fq081_build_benchmark(CACHE_DIR)

cat("[FQ081] 3) as-of 결합 (PIT: Factor_Date <= sig_date, 1년전 vintage 별도)\n")
j <- fq081_asof_join(mon, fv)
# ---- 유니버스: KOSPI200 ∪ KOSDAQ150 (PIT 시변) + 유동성 2e8 ----
u <- j[in_index == TRUE & is.finite(adv) & adv >= 2e8 & !is.na(Sector)]
u <- u[ym >= format(as.Date(START), "%Y%m")]
cat(sprintf("  universe rows=%d | months=%d | 평균종목/월=%.0f\n",
            nrow(u), uniqueN(u$ym), nrow(u) / max(1, uniqueN(u$ym))))

# ---- PIT 자가검증 (self-assert) ----
stopifnot(all(u$vint_cur <= u$sig_date, na.rm = TRUE))
stopifnot(all(u$vint_lag <= (u$sig_date - 365L), na.rm = TRUE))
cat("  [PIT self-assert] vintage <= sig_date, lag vintage <= sig_date-365 : OK\n")

cat("[FQ081] 4) 피처 (전역 z / 업종내 z / 교호항)\n")
d <- fq081_build_features(u)
cat(sprintf("  feature rows=%d | months=%d | %s ~ %s\n", nrow(d), uniqueN(d$ym),
            min(d$ym), max(d$ym)))
cat(sprintf("  업종내 z 결측률 (sector n<5): %.3f\n", mean(is.na(d$i_dPM))))
cat(sprintf("  ΔPM  분포: mean=%.4f sd=%.4f | ΔATO mean=%.4f sd=%.4f\n",
            mean(d$dPM), sd(d$dPM), mean(d$dATO), sd(d$dATO)))

# ---- 4b. Fama-MacBeth 진단 (전기간, advisory) ----
fm_diag <- function(feats, label) {
  D <- d[is.finite(ret_fwd)][complete.cases(d[is.finite(ret_fwd), feats, with = FALSE])]
  b <- D[, {
    if (.N >= 30L) {
      X <- as.matrix(.SD[, feats, with = FALSE])
      cf <- tryCatch(coef(lm.fit(cbind(1, X), ret_fwd)), error = function(e) NULL)
      if (is.null(cf)) as.list(setNames(rep(NA_real_, length(feats)), feats))
      else as.list(setNames(cf[-1], feats))
    } else as.list(setNames(rep(NA_real_, length(feats)), feats))
  }, by = ym_i, .SDcols = c("ret_fwd", feats)]
  b <- b[complete.cases(b)]
  cat(sprintf("\n  [FM %s] n_months=%d\n", label, nrow(b)))
  for (f in feats) {
    x <- b[[f]]
    nw <- tryCatch({
      m <- lm(x ~ 1)
      sqrt(sandwich::NeweyWest(m, lag = 3, prewhite = FALSE))[1, 1]
    }, error = function(e) sd(x) / sqrt(length(x)))
    cat(sprintf("    %-8s  mean=%9.5f  t_NW3=%6.3f\n", f, mean(x), mean(x) / nw))
  }
  b
}
suppressWarnings(suppressMessages(library(sandwich)))
fm_A <- fm_diag(c("g_dPM", "g_dATO"), "A 무조건부")
fm_B <- fm_diag(c("i_dPM", "i_dATO"), "B 업종내")
fm_C <- fm_diag(c("i_dPM", "i_dATO", "i_PM", "i_ATO", "x_PM", "x_ATO"), "C 업종내+교호")

# -----------------------------------------------------------------------------
cat("\n[FQ081] 5) arm score 생성 + canonical_screen_bt\n")
FEATS <- list(
  A  = c("g_dPM", "g_dATO"),
  B  = c("i_dPM", "i_dATO"),
  C  = c("i_dPM", "i_dATO", "i_PM", "i_ATO", "x_PM", "x_ATO")
)
scores <- list()
for (nm in names(FEATS)) scores[[nm]] <- fq081_fm_scores(d, FEATS[[nm]], min_months = MIN_FM)
scores[["A0"]] <- fq081_ew_scores(d, c("g_dPM", "g_dATO"))
scores[["B0"]] <- fq081_ew_scores(d, c("i_dPM", "i_dATO"))

md <- unique(d[, .(ym, mdate)])
returns_dt <- unique(d[is.finite(ret_fwd), .(Date = mdate, Ticker, Ret_1m = ret_fwd)])
# 유니버스 전체 수익 패널(스코어 없는 종목 포함 X — canonical 은 스코어 종목만 사용)
bench_dt <- bmm[, .(Date = mdate, BM_Ret)]
liq_dt   <- unique(d[, .(Date = mdate, Ticker, adv)])
size_dt  <- unique(d[is.finite(Size), .(Date = mdate, Ticker, Size)])

res <- list()
for (nm in names(scores)) {
  s <- merge(scores[[nm]], md, by = "ym")[, .(Date = mdate, Ticker, score)]
  if (!nrow(s)) { cat(sprintf("  arm %s: score 0행 — skip\n", nm)); next }
  r <- tryCatch(
    canonical_screen_bt(s, returns_dt, bench_dt, top_n = TOP_N, cost_bps_oneway = COST,
                        liq_dt = liq_dt, liq_min = 2e8, size_dt = size_dt,
                        run_id = paste0("FQ081_", nm), strategy_id = paste0("FQ081_arm", nm)),
    error = function(e) { cat("  err:", conditionMessage(e), "\n"); NULL })
  if (is.null(r)) next
  res[[nm]] <- r
  ew <- r$diag_ew_universe
  cat(sprintf("\n  === arm %s === months=%d\n", nm, r$n_months))
  cat(sprintf("    PORT_t(cap-w, NW3) = %7.3f   IR = %6.3f   netSR = %6.3f   TO = %5.2f\n",
              r$portfolio_alpha_t_nw_lag3 %||% NA, r$information_ratio %||% NA,
              r$net_sr %||% NA, r$turnover_annual %||% NA))
  cat(sprintf("    alpha_ann = %6.3f%%  | dual-basis EW-유니버스 PORT_t = %s\n",
              100 * (r$alpha_annualized %||% NA),
              if (is.list(ew)) sprintf("%.3f", ew$portfolio_alpha_t_nw_lag3 %||% NA_real_) else "NA"))
  ct <- r$diag_cap_tier
  if (is.list(ct) && !identical(ct$available, FALSE)) {
    ws <- ct$weight_share_avg
    if (!is.null(ws)) cat(sprintf("    cap-tier 평균비중: %s\n",
      paste(sprintf("%s=%.2f", names(ws), unlist(ws)), collapse = " / ")))
  }
}

# -----------------------------------------------------------------------------
cat("\n[FQ081] 6) paired 증분 검정 (동일 월 active 수익 차이, NW lag-3)\n")
pair_t <- function(a, b, la, lb) {
  if (is.null(res[[a]]) || is.null(res[[b]])) return(invisible(NULL))
  pa <- as.data.table(res[[a]]$period_returns); pb <- as.data.table(res[[b]]$period_returns)
  m <- merge(pa[, .(date, aa = ret_net - benchmark_ret)],
             pb[, .(date, ab = ret_net - benchmark_ret)], by = "date")
  dif <- m$ab - m$aa
  fit <- lm(dif ~ 1)
  se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag = 3, prewhite = FALSE))[1, 1],
                 error = function(e) sd(dif) / sqrt(length(dif)))
  cat(sprintf("  %s → %s : Δmean_active = %+.5f/월 (%+.2f%%p/년)  t_NW3 = %+6.3f  n=%d\n",
              la, lb, mean(dif), 100 * 12 * mean(dif), mean(dif) / se, nrow(m)))
  invisible(list(delta = mean(dif), t = mean(dif) / se, n = nrow(m)))
}
p_AB <- pair_t("A", "B", "A(무조건부)", "B(업종내)")
p_BC <- pair_t("B", "C", "B(업종내)", "C(교호)")
p_AC <- pair_t("A", "C", "A(무조건부)", "C(교호)")
p_A0B0 <- pair_t("A0", "B0", "A0(EW 무조건부)", "B0(EW 업종내)")

# -----------------------------------------------------------------------------
saveRDS(list(res = res, fm = list(A = fm_A, B = fm_B, C = fm_C),
             pairs = list(AB = p_AB, BC = p_BC, AC = p_AC, A0B0 = p_A0B0)),
        file.path(OUT, "fq081_diag.rds"))
# 후속 factor_engine 소비용 스코어 패널
sc_out <- rbindlist(lapply(names(scores), function(nm)
  if (nrow(scores[[nm]])) cbind(scores[[nm]], arm = nm) else NULL))
sc_out <- merge(sc_out, md, by = "ym")
write_parquet(sc_out, file.path(OUT, "fq081_arm_scores.parquet"))
cat(sprintf("\n[FQ081] 저장: %s\n", OUT))
cat("[FQ081] DONE\n")
