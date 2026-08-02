# =============================================================================
# run_wt015_rotation.R — WT-D20260802_015 튜닝 5팩터 국면-조건부 로테이션 실측
#   사전등록: stage_artifacts/WT_D20260802_015/preregistration.json (측정 전 고정)
#   PRIMARY : 튜닝 5팩터, regime별 expanding 조건부 IC clip0-비례 비중 합성 → canonical top-25 EW
#   대조군  : C1 EW-정적(튜닝) / C2 base-5 동일 로테이션(재탕 판별) / C3 M01_PATHQ 단일
#   PIT     : assert_overlay_pit HARD + regime lag1 스트레스 + 오염 주입 probe(r_{t+1})
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_015/run_wt015_rotation.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(xts); library(PerformanceAnalytics)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_015")
IN9 <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt015] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/validation/overlay_pit_guard.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()

TUNED_F <- c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB")
BASE_F  <- c("V01_BM", "M01_Mom_12_1", "D03_RealVol", "Q01_GPA", "V06_fDY")

# ── 1. 패널 + 하네스 (WT-009와 동일 vintage) ─────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet(file.path(IN9, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: SIG %d개월 (%s~%s) returns %d행", length(SIG), min(SIG), max(SIG), nrow(returns_dt))

score_of <- function(fname) {
  sc <- if (fname %in% BASE$Factor_Name) BASE[Factor_Name == fname, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == fname, .(Date, Ticker, score = score)]
  merge(sc, UNIV, by = c("Date", "Ticker"))
}
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 2. 국면 라벨 + PIT 가드 ──────────────────────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))
u <- u[, .(RegDate = as.Date(Date), YM, Category)]
setkey(u, YM)
reg_of_ym <- function(ym) u[J(ym), Category]
regdate_of_ym <- function(ym) u[J(ym), RegDate]
ym_of <- function(d) format(as.Date(d), "%Y-%m")
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}

# PIT HARD assert (clean 타이밍): 신호월 t의 라벨(월말 RegDate) < 홀딩월(t+1) 시작
used_cutoff_clean <- regdate_of_ym(ym_of(SIG))
holding_start <- holdings_signal_cutoff(SIG)
assert_overlay_pit(used_cutoff_clean, holding_start, label = "WT015_regime_clean")
say("PIT assert (clean r_t): PASS — %d개월 전부 컷오프 < 홀딩월 시작", length(SIG))

# 위반 주입: r_{t+1}(홀딩월 자체 라벨) 사용 시 assert가 stop해야 함 (차단 실효 실증)
inj_block <- tryCatch({
  assert_overlay_pit(regdate_of_ym(ym_add(ym_of(SIG), 1L)), holding_start,
                     label = "WT015_regime_contaminated")
  FALSE  # stop 미발화 = 가드 사망
}, error = function(e) grepl("LOOK-AHEAD", conditionMessage(e)))
say("PIT 위반 주입(r_{t+1}): %s", if (isTRUE(inj_block)) "차단 발화 (PASS)" else "★가드 미발화 (FAIL)")
stopifnot(isTRUE(inj_block))

# ── 3. 월별 IC (팩터 × 신호월, 유니버스 내 Spearman) ─────────────────────────
ic_of <- function(fname) {
  d <- merge(score_of(fname), returns_dt, by = c("Date", "Ticker"))
  d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date]
}
IC_T <- setNames(lapply(TUNED_F, ic_of), TUNED_F)
IC_B <- setNames(lapply(BASE_F, ic_of), BASE_F)
say("IC 계산 완료 (tuned 5 + base 5)")

# ── 4. 로테이션 비중 (사전등록 규칙 — expanding, m <= t-1, 조건부 n>=12, 총 24, clip0) ──
MIN_HIST <- 24L; MIN_REG <- 12L
build_weights <- function(IC_list, fnames) {
  # 팩터별 월 IC 행렬 (SIG index 기준)
  icm <- sapply(fnames, function(f) {
    v <- rep(NA_real_, length(SIG))
    ii <- match(IC_list[[f]]$Date, SIG)
    v[ii[!is.na(ii)]] <- IC_list[[f]]$ic[!is.na(ii)]
    v
  })
  r_sig <- reg_of_ym(ym_of(SIG))                # r_m: 신호월 라벨
  W <- matrix(NA_real_, nrow = length(SIG), ncol = length(fnames),
              dimnames = list(as.character(SIG), fnames))
  mode <- character(length(SIG))
  for (t in seq_along(SIG)) {
    hist <- seq_len(t - 1L)
    avail <- fnames[colSums(!is.na(icm[hist, , drop = FALSE])) > 0]
    if (length(hist) < MIN_HIST || length(avail) == 0L) {
      # 초기 EW (커버리지 있는 팩터만 — 그 달 composite에서 재확정)
      W[t, ] <- 1 / length(fnames); mode[t] <- "EW_INIT"; next
    }
    r_t <- r_sig[t]
    w_raw <- sapply(fnames, function(f) {
      x <- icm[hist, f]
      xr <- x[!is.na(x) & r_sig[hist] == r_t]
      ic_hat <- if (length(xr) >= MIN_REG) mean(xr) else mean(x, na.rm = TRUE)
      if (!is.finite(ic_hat)) 0 else max(0, ic_hat)
    })
    if (sum(w_raw) <= 0) { W[t, ] <- 1 / length(fnames); mode[t] <- "EW_ALLCLIP" }
    else { W[t, ] <- w_raw / sum(w_raw)
           mode[t] <- if (all(sapply(fnames, function(f)
             sum(!is.na(icm[hist, f]) & r_sig[hist] == r_t) >= MIN_REG))) "COND" else "MIXED" }
  }
  list(W = W, mode = mode, r_sig = r_sig, icm = icm)
}
ROT_T <- build_weights(IC_T, TUNED_F)
ROT_B <- build_weights(IC_B, BASE_F)
say("비중 경로: tuned mode 분포 = %s", paste(names(table(ROT_T$mode)), table(ROT_T$mode), collapse = " "))

# ── 5. Composite 합성 (월별 유니버스 재-z, 종목별 비결측 >=3, 비중 재정규화) ──
build_zl <- function(fnames) {
  zl <- rbindlist(lapply(fnames, function(f) {
    s <- score_of(f)
    s[, z := as.numeric(scale(score)), by = Date]
    s[, .(Date, Ticker, Factor_Name = f, z)]
  }))
  cov <- zl[!is.na(z), .N, by = .(Date, Factor_Name)]
  zl <- merge(zl, cov, by = c("Date", "Factor_Name"))
  zl[N >= 100L][, N := NULL]      # 월 커버리지 <100 팩터는 그 달 제외 (사전등록)
}
ZL_T <- build_zl(TUNED_F)
ZL_B <- build_zl(BASE_F)

composite_scores <- function(zl, Wmat, fnames) {
  wdt <- data.table(Date = rep(SIG, times = length(fnames)),
                    Factor_Name = rep(fnames, each = length(SIG)),
                    w = as.vector(Wmat))
  m <- merge(zl[!is.na(z)], wdt, by = c("Date", "Factor_Name"))
  cs <- m[, {
    if (.N >= 3L && sum(w) > 0) .(score = sum(w * z) / sum(w), nf = .N)
    else .(score = NA_real_, nf = .N)
  }, by = .(Date, Ticker)]
  cs[!is.na(score), .(Date, Ticker, score)]
}
EW_W_T <- matrix(1 / length(TUNED_F), nrow = length(SIG), ncol = length(TUNED_F),
                 dimnames = list(as.character(SIG), TUNED_F))
SC_PRIMARY <- composite_scores(ZL_T, ROT_T$W, TUNED_F)
SC_C1_EW   <- composite_scores(ZL_T, EW_W_T, TUNED_F)
SC_C2_BROT <- composite_scores(ZL_B, ROT_B$W, BASE_F)
say("composite: primary %d행 / EW %d행 / base-rot %d행",
    nrow(SC_PRIMARY), nrow(SC_C1_EW), nrow(SC_C2_BROT))

# ── 6. canonical 실측 ────────────────────────────────────────────────────────
FEAT_ROT <- list(node_count = 8, max_depth = 4, free_param_count = 2,
  distinct_field_count = 5, conditional_op_count = 1, window_variety = 2,
  restatement_exposure = 2, escape_leaf_count = 2, escape_leaf_types = list("SPECIAL_OP"),
  note = "regime-conditional IC-proportional weighted sum of WT-009 tuned 5 (전거: preregistration.json)")
run_canon <- function(sc, tag, feats = NULL, dual = TRUE) {
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260802_015", strategy_id = paste0("WT_D20260802_015_", tag),
    diag_dual_basis = dual, size_dt = if (dual) size_dt else NULL,
    ast_features = feats)
}
bt <- list()
bt$PRIMARY   <- run_canon(SC_PRIMARY, "ROT_TUNED", FEAT_ROT)
bt$C1_EW     <- run_canon(SC_C1_EW,   "EW_TUNED")
bt$C2_BROT   <- run_canon(SC_C2_BROT, "ROT_BASE")
bt$C3_SINGLE <- run_canon(score_of("M01_PATHQ"), "M01_PATHQ")
for (k in names(bt)) {
  r <- bt[[k]]
  ew <- r$diag_ew_universe
  say("%-10s PORT_t=%+.2f netSR=%+.3f IR=%+.3f TO=%.1f/yr n=%d cov=%.3f | EWuni t=%+.2f post17=%+.2f oos~%.2f",
      k, r$portfolio_alpha_t_nw_lag3, r$net_sr %||% NA, r$information_ratio %||% NA,
      r$turnover_annual %||% NA, r$n_months, r$selected_ret_coverage %||% NA,
      ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_,
      ew$oos_retention_approx %||% NA_real_)
}

# ── 7. paired 판정 (재탕 판별 + 로테이션 부가가치) ───────────────────────────
paired <- function(a, b) {
  pa <- as.data.table(bt[[a]]$period_returns); pb <- as.data.table(bt[[b]]$period_returns)
  m <- merge(pa[, .(date, x = ret_net - benchmark_ret)],
             pb[, .(date, y = ret_net - benchmark_ret)], by = "date")
  m[, d := x - y]
  list(n = nrow(m), t = nw_t(m$d), mean_d_ann = mean(m$d) * 12,
       t_post2017 = m[date >= "2017-01-01", nw_t(d)], d_series = m)
}
PAIRED <- list(
  rerun_tunedRot_vs_baseRot = paired("PRIMARY", "C2_BROT"),
  value_tunedRot_vs_ewStatic = paired("PRIMARY", "C1_EW"),
  value_tunedRot_vs_single   = paired("PRIMARY", "C3_SINGLE"),
  base_check_baseRot_vs_ew   = NULL)
for (nm in c("rerun_tunedRot_vs_baseRot", "value_tunedRot_vs_ewStatic", "value_tunedRot_vs_single"))
  say("paired %s: t=%+.2f (n=%d, %+.2f%%/yr, post17 t=%+.2f)", nm,
      PAIRED[[nm]]$t, PAIRED[[nm]]$n, 100 * PAIRED[[nm]]$mean_d_ann, PAIRED[[nm]]$t_post2017)

# ── 8. regime lag1 스트레스 + 오염판(진단 전용) ──────────────────────────────
build_weights_shift <- function(IC_list, fnames, shift_k) {
  # r_t 대신 r_{t+shift_k} 사용 (lag1: shift_k=-1 / 오염: shift_k=+1). 조건부 이력 r_m은 불변.
  icm <- sapply(fnames, function(f) {
    v <- rep(NA_real_, length(SIG))
    ii <- match(IC_list[[f]]$Date, SIG)
    v[ii[!is.na(ii)]] <- IC_list[[f]]$ic[!is.na(ii)]
    v
  })
  r_sig <- reg_of_ym(ym_of(SIG))
  r_dec <- reg_of_ym(ym_add(ym_of(SIG), shift_k))
  W <- matrix(NA_real_, nrow = length(SIG), ncol = length(fnames),
              dimnames = list(as.character(SIG), fnames))
  for (t in seq_along(SIG)) {
    hist <- seq_len(t - 1L)
    if (length(hist) < MIN_HIST || is.na(r_dec[t])) { W[t, ] <- 1 / length(fnames); next }
    w_raw <- sapply(fnames, function(f) {
      x <- icm[hist, f]
      xr <- x[!is.na(x) & r_sig[hist] == r_dec[t]]
      ic_hat <- if (length(xr) >= MIN_REG) mean(xr) else mean(x, na.rm = TRUE)
      if (!is.finite(ic_hat)) 0 else max(0, ic_hat)
    })
    W[t, ] <- if (sum(w_raw) <= 0) rep(1 / length(fnames), length(fnames)) else w_raw / sum(w_raw)
  }
  W
}
SC_LAG1 <- composite_scores(ZL_T, build_weights_shift(IC_T, TUNED_F, -1L), TUNED_F)
bt$LAG1 <- run_canon(SC_LAG1, "ROT_TUNED_regimelag1", dual = FALSE)
say("regime lag1: PORT_t %+.2f (clean %+.2f)", bt$LAG1$portfolio_alpha_t_nw_lag3,
    bt$PRIMARY$portfolio_alpha_t_nw_lag3)
# 오염판 — assert가 차단하는 타이밍(r_{t+1})을 '진단 전용'으로 정량화 (본판정 절대 비사용)
SC_CONTAM <- composite_scores(ZL_T, build_weights_shift(IC_T, TUNED_F, +1L), TUNED_F)
bt$CONTAM <- run_canon(SC_CONTAM, "ROT_TUNED_CONTAM_DIAGONLY", dual = FALSE)
ab <- overlay_lookahead_ab(bt$CONTAM$portfolio_alpha_t_nw_lag3,
                           bt$PRIMARY$portfolio_alpha_t_nw_lag3, "PORT_t(오염 vs clean)")
say("오염판(r_{t+1}, 진단): PORT_t %+.2f | %s", bt$CONTAM$portfolio_alpha_t_nw_lag3, ab$message)

# ── 9. AX-001 국면 slicing + 라벨-실현 병기 + oos 근사 + 비중 경로 진단 ──────
pr <- as.data.table(bt$PRIMARY$period_returns)
pr[, active := ret_net - benchmark_ret]
pr[, hold_ym := ym_add(ym_of(date), 1L)]
pr <- merge(pr, u[, .(hold_ym = YM, Category)], by = "hold_ym", all.x = TRUE)
AX001 <- pr[!is.na(Category), .(n = .N, mean_active = mean(active), t_nw = nw_t(active),
                                bench_mean = mean(benchmark_ret)), by = Category]
say("AX001 primary: %s", paste(AX001$Category, sprintf("n=%d t=%+.2f bench=%+.3f",
    AX001$n, AX001$t_nw, AX001$bench_mean), collapse = " | "))
mdd_primary <- {
  x <- xts::xts(pr$ret_net, order.by = as.Date(pr$date))
  as.numeric(PerformanceAnalytics::maxDrawdown(x))
}
oos_rough <- function(arm) {
  p <- as.data.table(bt[[arm]]$period_returns)
  a <- p$ret_net - p$benchmark_ret
  .canon_oos_rough(a)
}
OOS <- sapply(c("PRIMARY", "C1_EW", "C2_BROT", "C3_SINGLE"), oos_rough)
say("oos_rough(진단): %s", paste(names(OOS), sprintf("%.2f", OOS), collapse = " "))

# 비중 경로: 국면별 평균 비중 + 비중 L1 회전
r_sig <- ROT_T$r_sig
w_by_reg <- rbindlist(lapply(unique(na.omit(r_sig)), function(rg) {
  idx <- which(r_sig == rg & ROT_T$mode != "EW_INIT")
  if (!length(idx)) return(NULL)
  data.table(regime = rg, n = length(idx), t(colMeans(ROT_T$W[idx, , drop = FALSE])))
}), fill = TRUE)
w_l1_turnover <- mean(rowSums(abs(diff(ROT_T$W))), na.rm = TRUE) * 12
say("비중 L1 회전(연): %.2f | 국면별 평균 비중:", w_l1_turnover)
print(w_by_reg)

# 국면 라벨 vs 실현(벤치) 병기 — 라벨 오염 인지 (WT-004: 2026 CRISIS 멜트업)
label_realized <- pr[!is.na(Category), .(n = .N, bench_ann = mean(benchmark_ret) * 12,
                                          active_ann = mean(active) * 12), by = Category]

# ── 10. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
sc_after <- ast_sidecar_status()
saveRDS(list(bt = lapply(bt, slim), paired = PAIRED,
             rot_tuned = list(W = ROT_T$W, mode = ROT_T$mode, r_sig = ROT_T$r_sig),
             rot_base = list(W = ROT_B$W, mode = ROT_B$mode),
             ax001 = AX001, label_realized = label_realized, mdd_primary = mdd_primary,
             oos_rough = OOS, w_by_reg = w_by_reg, w_l1_turnover = w_l1_turnover,
             contam_ab = ab, inj_block = inj_block,
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after = sc_after[c("live", "live_with_ast")])),
        file.path(OUT, "wt015_results.rds"))
# alpha_scores (primary 최신월 + 전 이력)
write_parquet(SC_PRIMARY, file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt015_results.rds + alpha_scores.parquet")
