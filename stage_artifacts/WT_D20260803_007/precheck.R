# =============================================================================
# precheck.R — WT-D20260803_007 (FQ-135) 착수 전 사전 확인 (read-only, 측정 아님)
#   목적: 라운드 설계의 *전제*를 잰다 (가설 아님).
#   P-a  WT-005 canonical_pool.rds 재사용 가능성 + A 행렬 시간축
#   P-b  walk-forward 격자에서 step 별 era 수 / OOS 월 수 (설계 실행가능성)
#   P-c  era-demean worst-era 지표의 분포 · 동점 비율 (선택자가 실제로 판별하나)
#   P-d  canonical_screen_bt 1회 소요 (arm 수 예산)
#   P-e  full-z 월 로드 소요 (composite 는 top-80 절단 불가 → 전체 z 필요)
# 실행: Rscript stage_artifacts/WT_D20260803_007/precheck.R
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) cat(sprintf(paste0("[pre007] ", fmt, "\n"), ...))

SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
CP   <- readRDS(file.path(SRC5, "canonical_pool.rds"))
PR5  <- readRDS(file.path(SRC5, "persistence_results.rds"))
say("P-a canonical_pool.rds: res %d factor | summary %d행 | parity 목록 %s",
    length(CP$res), nrow(CP$summary), paste(names(CP$parity), collapse = "/"))
A <- PR5$A
say("P-a A 행렬(중복제거 후): %d월 x %d factor | %s ~ %s",
    nrow(A), ncol(A), rownames(A)[1], rownames(A)[nrow(A)])
say("P-a 완전관측 factor %d / NA 셀 %.2f%%", sum(colSums(is.na(A)) == 0L),
    100 * mean(is.na(A)))

# ── P-b walk-forward 격자 ───────────────────────────────────────────────────
n <- nrow(A); IS0 <- 120L; OOSB <- 24L
steps <- list(); s <- IS0
while (s < n) {
  e <- min(s + OOSB, n)
  steps[[length(steps) + 1L]] <- list(is_end = s, oos = (s + 1L):e)
  s <- e
}
say("P-b walk-forward: IS0=%d, OOS블록=%d → step %d개 | OOS 월 총 %d (%s ~ %s)",
    IS0, OOSB, length(steps), sum(vapply(steps, function(x) length(x$oos), 1L)),
    rownames(A)[steps[[1]]$oos[1]], rownames(A)[tail(steps[[length(steps)]]$oos, 1)])
for (i in seq_along(steps)) {
  ise <- steps[[i]]$is_end
  say("   step%d: IS 1..%d (%s~%s) | era(W=36,비중첩,IS끝정렬) %d개 | OOS %d월 (%s~%s)",
      i, ise, rownames(A)[1], rownames(A)[ise], ise %/% 36L,
      length(steps[[i]]$oos), rownames(A)[steps[[i]]$oos[1]],
      rownames(A)[tail(steps[[i]]$oos, 1)])
}

# ── P-c 지표 판별력 ─────────────────────────────────────────────────────────
source("02_Infrastructure/contracts/backtest_result_contract.R")
nw_t <- function(x, lag = 3L) { xv <- x[is.finite(x)]; if (length(xv) < 20L) return(NA_real_); .nw_t_mean(xv, lag = lag) }
era_t <- function(mat, i0, i1) apply(mat[i0:i1, , drop = FALSE], 2, nw_t)
worst_era <- function(mat, is_end, W = 36L, demean = TRUE) {
  ne <- is_end %/% W
  if (ne < 2L) return(NULL)
  bnds <- lapply(seq_len(ne), function(k) c(is_end - k * W + 1L, is_end - (k - 1L) * W))
  TT <- do.call(rbind, lapply(bnds, function(b) era_t(mat, b[1], b[2])))
  if (demean) TT <- TT - rowMeans(TT, na.rm = TRUE)
  apply(TT, 2, function(v) if (all(is.na(v))) NA_real_ else min(v, na.rm = TRUE))
}
for (i in c(1L, length(steps))) {
  ise <- steps[[i]]$is_end
  wr <- worst_era(A, ise, 36L, TRUE)
  wa <- worst_era(A, ise, 36L, FALSE)
  lvl <- era_t(A, 1L, ise)
  say("P-c step%d: worst-era(demean) 유효 %d | 범위 [%.3f, %.3f] | 동점(상위20 경계) %d | cor(rel, level)=%.3f | cor(abs, level)=%.3f",
      i, sum(is.finite(wr)), min(wr, na.rm = TRUE), max(wr, na.rm = TRUE),
      sum(wr == sort(wr, decreasing = TRUE)[20], na.rm = TRUE),
      cor(wr, lvl, use = "pairwise.complete.obs"),
      cor(wa, lvl, use = "pairwise.complete.obs"))
  top20 <- names(sort(wr, decreasing = TRUE))[1:20]
  bot20 <- names(sort(wr, decreasing = FALSE))[1:20]
  say("      top20(rel): %s", paste(head(top20, 8), collapse = ", "))
  say("      bot20(rel): %s", paste(head(bot20, 8), collapse = ", "))
}
# 선택 안정성: step1 top20 vs step_last top20 자카드
w1 <- worst_era(A, steps[[1]]$is_end); wL <- worst_era(A, steps[[length(steps)]]$is_end)
t1 <- names(sort(w1, decreasing = TRUE))[1:20]; tL <- names(sort(wL, decreasing = TRUE))[1:20]
say("P-c 선택 회전: step1 ∩ stepL top20 = %d/20 (자카드 %.3f)",
    length(intersect(t1, tL)), length(intersect(t1, tL)) / length(union(t1, tL)))

# ── P-d canonical 1회 소요 ──────────────────────────────────────────────────
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
META <- readRDS(file.path(SRC5, "pool_meta.rds"))
sig_all <- META$sig_all
say("P-d sig_all %d월 | A 월수 %d | 일치=%s", length(sig_all), nrow(A),
    identical(as.character(sig_all), rownames(A)))
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
PANEL <- as.data.table(read_parquet(file.path(SRC5, "pool_panel.parquet")))
PANEL[, Date := as.Date(Date)]
sc <- PANEL[Factor_Name == "V01_BM", .(Date, Ticker, score)]
oos_d <- as.Date(rownames(A))[steps[[1]]$oos[1]:tail(steps[[length(steps)]]$oos, 1)]
t0 <- Sys.time()
r <- canonical_screen_bt(sc[Date %in% oos_d], returns_dt, bench_dt, top_n = 25L,
       cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
       run_id = "pre007", strategy_id = "pre007_V01BM", diag_dual_basis = FALSE)
el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
say("P-d canonical 1회 (%d월): %.2fs | PORT_t=%.3f | n_months=%d → 210 arm 예산 %.1f분",
    length(oos_d), el, r$portfolio_alpha_t_nw_lag3, r$n_months, 210 * el / 60)

# ── P-e full-z 월 로드 소요 ─────────────────────────────────────────────────
source("02_Infrastructure/factor_db/factor_db_connector.R")
sink(file.path(OUT, "precheck_connector.log"))
t0 <- Sys.time()
fd <- load_month_factors(as.Date("2015-06-30"), coverage_min = 0.05)
e1 <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
t0 <- Sys.time()
fd2 <- load_month_factors(as.Date("2015-07-31"), coverage_min = 0.05)
e2 <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
sink()
say("P-e load_month_factors: 1회차 %.2fs / 2회차 %.2fs | 행 %d | factor %d → 287월 %.1f분",
    e1, e2, nrow(fd), uniqueN(fd$Factor_Name), 287 * e2 / 60)
say("P-e 전체 z 규모 추정: %d factor x %d ticker x 287월 = %.1fM행",
    ncol(A), uniqueN(fd$Ticker), ncol(A) * uniqueN(fd$Ticker) * 287 / 1e6)

saveRDS(list(steps = steps, dates = as.Date(rownames(A)), n_factor = ncol(A),
             canon_secs = el, load_secs = e2), file.path(OUT, "precheck.rds"))
say("완료")
