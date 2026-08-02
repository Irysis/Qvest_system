# =============================================================================
# run_wt009_eval.R — WT-D20260802_009 paired A/B 평가 (사전등록 판정 프레임)
#   1. 10 arm canonical_screen_bt (base 5 + tuned 5, dual-basis + cap-tier)
#   2. 팩터별 paired t (NW lag-3, d = active_tuned - active_base, 공통월)
#   3. 5x5 CS Spearman 상관 (base간 / tuned간) — breadth 訓 판정
#   4. AX-001 조건부 (P3/P5): 국면 slicing + MDD(PerformanceAnalytics) + Core 대비
#   5. lag1 스트레스 (tuned 5)
#   6. 반증 4종 (성과-독립): HHI / jump-기여 / vol-예측 MSE / EB노이즈-예측
#   7. advisory 진단 (rank IC / ICIR / mono / subperiod)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_009/run_wt009_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(xts); library(PerformanceAnalytics)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt009e] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()
say("sidecar before: live=%d live_with_ast=%d", sc_before$live, sc_before$live_with_ast)

PAIRS <- data.table(
  pair = c("P1_VALUE", "P2_MOMENTUM", "P3_LOWVOL", "P4_QUALITY", "P5_DIVIDEND"),
  base = c("V01_BM", "M01_Mom_12_1", "D03_RealVol", "Q01_GPA", "V06_fDY"),
  tuned = c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB"))

# ── 1. 패널 + 하네스 ─────────────────────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(OUT, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(OUT, "tuned_panel.parquet")))
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
# ★ 유니버스 멤버십 (K200∪KQ150 월말) — canonical liq필터는 adv결측=통과이므로
#   scores를 유니버스로 선-제한하는 것이 호출자 책임 (probe_sanity에서 실측 확인:
#   DB 전체 1800종목 패널 그대로 넣으면 top-25가 비유니버스로 채워져 Ret_1m NA→0 붕괴)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet(file.path(OUT, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: returns %d행 bench %d월", nrow(returns_dt), nrow(bench_dt))

score_of <- function(fname) {
  sc <- if (fname %in% BASE$Factor_Name) BASE[Factor_Name == fname, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == fname, .(Date, Ticker, score = score)]
  merge(sc, UNIV, by = c("Date", "Ticker"))   # 유니버스 선-제한 (호출자 책임)
}

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 2. 10 arm canonical 실측 ─────────────────────────────────────────────────
ARMS <- c(PAIRS$base, PAIRS$tuned)
# ast_features (사이드카 기록 전용 — 판정 비관여. base=registry FIELD 리프,
#   tuned P1/P4/P5=𝒪 내 표현, P2/P3=SPECIAL_OP escape — preregistration 선언 정합)
feats_field <- list(node_count = 1, max_depth = 1, free_param_count = 0,
  distinct_field_count = 1, conditional_op_count = 0, window_variety = 0,
  restatement_exposure = 1, escape_leaf_count = 0, escape_leaf_types = list(),
  note = "registry FIELD 리프 (factor_db_monthly Z_Score_Aligned 그대로)")
FEATS <- list(
  V01_BM = feats_field, M01_Mom_12_1 = feats_field, D03_RealVol = feats_field,
  Q01_GPA = feats_field, V06_fDY = feats_field,
  V01_SECREL = list(node_count = 3, max_depth = 3, free_param_count = 1,
    distinct_field_count = 2, conditional_op_count = 0, window_variety = 0,
    restatement_exposure = 1, escape_leaf_count = 0, escape_leaf_types = list(),
    note = "CS_ZSCORE(CS_NEUTRALIZE(FIELD:V01_BM, group=Sector, min8)) — 𝒪 내"),
  M01_PATHQ = list(node_count = 4, max_depth = 3, free_param_count = 3,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 0, escape_leaf_count = 1, escape_leaf_types = list("SPECIAL_OP"),
    note = "CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:path_efficiency_252_21)) — run_wt009_tuned.R"),
  D03_EWMA = list(node_count = 4, max_depth = 3, free_param_count = 2,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 0, escape_leaf_count = 1, escape_leaf_types = list("SPECIAL_OP"),
    note = "CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:ewma_vol_hl63_w252)) — run_wt009_tuned.R"),
  Q01_EB = list(node_count = 6, max_depth = 4, free_param_count = 2,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 1, escape_leaf_count = 0, escape_leaf_types = list(),
    note = "MUL(z, DIV_GUARD(1, ADD(1, MUL(TS_STD(z,36),TS_STD(z,36))))) — 𝒪 내"),
  V06_EB = list(node_count = 6, max_depth = 4, free_param_count = 2,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 0, escape_leaf_count = 0, escape_leaf_types = list(),
    note = "MUL(z, DIV_GUARD(1, ADD(1, MUL(TS_STD(z,36),TS_STD(z,36))))) — 𝒪 내"))
bt <- list()
for (a in ARMS) {
  r <- canonical_screen_bt(score_of(a), returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_009", strategy_id = paste0("WT_D20260802_009_", a),
        diag_dual_basis = TRUE, size_dt = size_dt, ast_features = FEATS[[a]])
  bt[[a]] <- r
  ew <- r$diag_ew_universe
  say("%-12s PORT_t=%+.2f netSR=%+.3f IR=%+.3f TO=%.0f%% n=%d | EWuni t=%+.2f post17=%+.2f",
      a, r$portfolio_alpha_t_nw_lag3, r$net_sr %||% NA, r$information_ratio %||% NA,
      100 * (r$turnover_annual %||% NA), r$n_months,
      ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_)
}

# ── 3. paired t (사전등록 primary) + 부기간 ──────────────────────────────────
paired_res <- list()
for (i in seq_len(nrow(PAIRS))) {
  pb <- as.data.table(bt[[PAIRS$base[i]]]$period_returns)
  pt_ <- as.data.table(bt[[PAIRS$tuned[i]]]$period_returns)
  m <- merge(pb[, .(date, ab = ret_net - benchmark_ret)],
             pt_[, .(date, at = ret_net - benchmark_ret)], by = "date")
  m[, d := at - ab]
  sub <- function(a, b) m[date >= a & date <= b, nw_t(d)]
  paired_res[[PAIRS$pair[i]]] <- list(
    n_months = nrow(m),
    mean_d_annualized = mean(m$d) * 12,
    paired_t_nw = nw_t(m$d),
    sub_pre2015 = sub("1900-01-01", "2014-12-31"),
    sub_2015_19 = sub("2015-01-01", "2019-12-31"),
    sub_2020p   = sub("2020-01-01", "2099-01-01"),
    sub_post2017 = sub("2017-01-01", "2099-01-01"),
    d_series = m)
  say("%s paired t=%+.2f (n=%d, mean d %.2f%%/yr) | sub %+.2f / %+.2f / %+.2f | post17 %+.2f",
      PAIRS$pair[i], paired_res[[PAIRS$pair[i]]]$paired_t_nw, nrow(m),
      100 * mean(m$d) * 12, paired_res[[PAIRS$pair[i]]]$sub_pre2015,
      paired_res[[PAIRS$pair[i]]]$sub_2015_19, paired_res[[PAIRS$pair[i]]]$sub_2020p,
      paired_res[[PAIRS$pair[i]]]$sub_post2017)
}

# ── 4. 5x5 CS Spearman 상관 (base간 / tuned간, 전 10패널 공통월) ─────────────
all10 <- lapply(ARMS, function(a) score_of(a)[, .N, by = Date][N >= 100, Date])
common_m <- Reduce(intersect, all10)
common_m <- as.Date(common_m, origin = "1970-01-01")
say("상관 공통월 %d (%s ~ %s)", length(common_m),
    format(min(common_m)), format(max(common_m)))
cs_cor <- function(f1, f2) {
  m <- merge(score_of(f1)[Date %in% common_m, .(Date, Ticker, s1 = score)],
             score_of(f2)[Date %in% common_m, .(Date, Ticker, s2 = score)],
             by = c("Date", "Ticker"))
  m[, .(r = suppressWarnings(cor(s1, s2, method = "spearman"))), by = Date][, mean(r, na.rm = TRUE)]
}
cor_mat <- function(fs) {
  M <- diag(1, 5); dimnames(M) <- list(fs, fs)
  for (i in 1:4) for (j in (i + 1):5) M[i, j] <- M[j, i] <- cs_cor(fs[i], fs[j])
  M
}
COR_BASE <- cor_mat(PAIRS$base)
COR_TUNED <- cor_mat(PAIRS$tuned)
off <- function(M) mean(abs(M[upper.tri(M)]))
pair_selfcor <- vapply(seq_len(5), function(i) cs_cor(PAIRS$base[i], PAIRS$tuned[i]), numeric(1))
say("mean|offdiag| base=%.3f tuned=%.3f delta=%+.3f", off(COR_BASE), off(COR_TUNED),
    off(COR_TUNED) - off(COR_BASE))
say("pair self-cor (base vs tuned): %s",
    paste(sprintf("%s=%.3f", PAIRS$pair, pair_selfcor), collapse = " "))

# ── 5. AX-001 조건부 (P3/P5) + 국면 slicing + MDD ────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
regime_of <- function(arm) {
  pr <- as.data.table(bt[[arm]]$period_returns)
  pr[, active := ret_net - benchmark_ret]
  pr[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
  pr <- merge(pr, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
  pr[!is.na(Category), .(n = .N, mean_active = mean(active), t_nw = nw_t(active)), by = Category]
}
mdd_of <- function(arm) {
  pr <- as.data.table(bt[[arm]]$period_returns)
  x <- xts::xts(pr$ret_net, order.by = as.Date(pr$date))
  as.numeric(PerformanceAnalytics::maxDrawdown(x))
}
AX001 <- list()
for (arm in c("D03_RealVol", "D03_EWMA", "V06_fDY", "V06_EB", "M01_Mom_12_1")) {
  AX001[[arm]] <- list(regime = regime_of(arm), mdd = mdd_of(arm))
  rg <- AX001[[arm]]$regime
  cr <- rg[Category == "CRISIS"]
  say("AX001 %-12s MDD=%.1f%% | CRISIS n=%d mean=%+.4f t=%+.2f", arm,
      100 * AX001[[arm]]$mdd, if (nrow(cr)) cr$n else 0L,
      if (nrow(cr)) cr$mean_active else NA, if (nrow(cr)) cr$t_nw else NA)
}

# ── 6. lag1 스트레스 (tuned 5) ───────────────────────────────────────────────
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
LAG1 <- list()
for (a in PAIRS$tuned) {
  sc <- score_of(a)
  l1 <- copy(sc)[, i := sig_idx[as.character(Date)] + 1L]
  l1 <- l1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
  r <- canonical_screen_bt(l1, returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_009_lag1", strategy_id = paste0("WT_D20260802_009_", a, "_lag1"),
        diag_dual_basis = FALSE)
  LAG1[[a]] <- r$portfolio_alpha_t_nw_lag3
  say("lag1 %-12s base_t=%+.2f -> lag1_t=%+.2f", a,
      bt[[a]]$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_nw_lag3)
}

# ── 7. 반증 4종 (성과-독립, 사전등록) ────────────────────────────────────────
top25 <- function(arm, d) {
  sc <- score_of(arm)[Date == d]
  lq <- liq_dt[Date == d & adv >= 2e8, Ticker]
  head(sc[Ticker %chin% lq][order(-score)], 25L)$Ticker
}
# F1: 섹터 HHI (P1)
SEC <- as.data.table(read_parquet(file.path(OUT, "sector_panel.parquet")))
SEC[, Date := as.Date(Date)]
hhi_m <- rbindlist(lapply(as.list(common_m), function(d) {
  h <- function(tk) {
    s <- SEC[Date == d & Ticker %chin% tk, Sector]
    if (length(s) < 15L) return(NA_real_)
    sum((table(s) / length(s))^2)
  }
  data.table(Date = d, hhi_base = h(top25("V01_BM", d)), hhi_tuned = h(top25("V01_SECREL", d)))
}))
f1 <- list(hhi_base = hhi_m[, mean(hhi_base, na.rm = TRUE)],
           hhi_tuned = hhi_m[, mean(hhi_tuned, na.rm = TRUE)],
           t_diff = nw_t(hhi_m[, hhi_base - hhi_tuned]))
say("F1 HHI: base=%.3f tuned=%.3f t(diff)=%+.2f", f1$hhi_base, f1$hhi_tuned, f1$t_diff)

# F2: jump 기여 (P2) — top-25 보유종목 12-1 창 상위5 |lr|일의 순수익 기여 중앙값
D <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select = c("Date", "Ticker", "Ret")))
D[, Date := as.Date(Date)]
D <- D[Ticker %chin% unique(BASE$Ticker) & !is.na(Ret)]
setkey(D, Ticker, Date)
jump_contrib <- function(tk, d) {
  W <- D[Date > d - 550L & Date <= d & Ticker %chin% tk]
  W <- W[, tail(.SD, 252L), by = Ticker]
  ct <- W[, {
    n <- .N
    if (n < 252L) list(jc = NA_real_) else {
      lr <- log(1 + Ret[1:(n - 21L)]); lr <- lr[is.finite(lr)]
      net <- sum(lr)
      if (abs(net) < 0.05) list(jc = NA_real_) else {
        top5 <- order(-abs(lr))[1:5]
        list(jc = sum(lr[top5]) / net)
      }
    }
  }, by = Ticker]
  median(ct$jc, na.rm = TRUE)
}
f2_m <- rbindlist(lapply(as.list(common_m), function(d)
  data.table(Date = d, jc_base = jump_contrib(top25("M01_Mom_12_1", d), d),
             jc_tuned = jump_contrib(top25("M01_PATHQ", d), d))))
f2 <- list(jc_base = f2_m[, mean(jc_base, na.rm = TRUE)],
           jc_tuned = f2_m[, mean(jc_tuned, na.rm = TRUE)],
           t_diff = nw_t(f2_m[, jc_base - jc_tuned]))
say("F2 jump기여: base=%.3f tuned=%.3f t(diff)=%+.2f", f2$jc_base, f2$jc_tuned, f2$t_diff)

# F3: vol 예측 MSE (P3) — EWMA vs 252d sd, 다음 21거래일 실현 vol (사후 진단 전용)
CAL <- sort(unique(D$Date))
f3_m <- rbindlist(lapply(as.list(SIG[SIG >= min(common_m)]), function(d) {
  i <- findInterval(d, CAL)
  if (i + 21L > length(CAL)) return(NULL)
  fut_end <- CAL[i + 21L]
  W <- D[Date > d - 550L & Date <= d]
  W <- W[, tail(.SD, 252L), by = Ticker]
  est <- W[, {
    n <- .N
    if (n < 120L) list(s_sd = NA_real_, s_ew = NA_real_) else {
      age <- (n - 1L):0L; w <- 0.5^(age / 63)
      list(s_sd = sd(Ret), s_ew = sqrt(sum(w * Ret^2) / sum(w)))
    }
  }, by = Ticker]
  FUT <- D[Date > d & Date <= fut_end, .(rv = if (.N >= 15L) sd(Ret) else NA_real_), by = Ticker]
  m <- merge(est, FUT, by = "Ticker")
  m <- m[is.finite(s_sd) & is.finite(s_ew) & is.finite(rv)]
  if (nrow(m) < 50L) return(NULL)
  data.table(Date = d, mse_sd = m[, mean((s_sd - rv)^2)], mse_ew = m[, mean((s_ew - rv)^2)],
             n = nrow(m))
}))
f3 <- list(mse_sd = f3_m[, mean(mse_sd)], mse_ew = f3_m[, mean(mse_ew)],
           t_diff = nw_t(f3_m[, mse_sd - mse_ew]),
           win_share = f3_m[, mean(mse_ew < mse_sd)])
say("F3 vol-MSE: sd=%.3e ewma=%.3e t(sd-ewma)=%+.2f ewma승률=%.2f",
    f3$mse_sd, f3$mse_ew, f3$t_diff, f3$win_share)

# F4/F5: EB 노이즈-예측 (sig2 vs |z_{t+1}-z_t|)
eb_fals <- function(detail_file, fac) {
  det <- as.data.table(read_parquet(file.path(OUT, detail_file)))
  det[, Date := as.Date(Date)]
  bz <- BASE[Factor_Name == fac, .(Date, Ticker, z)]
  bz[, idx := match(Date, SIG)]
  nz <- copy(bz)[, idx := idx - 1L]         # z_{t+1}을 t행에
  setnames(nz, "z", "z_next")
  m <- merge(bz, nz[, .(Ticker, idx, z_next)], by = c("Ticker", "idx"))
  m <- merge(m, det[is.finite(sig2), .(Date, Ticker, sig2)], by = c("Date", "Ticker"))
  rc <- m[, .(r = suppressWarnings(cor(sig2, abs(z_next - z), method = "spearman")), n = .N), by = Date]
  list(mean_rho = rc[, mean(r, na.rm = TRUE)], t_nw = nw_t(rc$r), n_months = nrow(rc))
}
f4 <- eb_fals("eb_q01_detail.parquet", "Q01_GPA")
f5 <- eb_fals("eb_v06_detail.parquet", "V06_fDY")
say("F4 EB(Q01): rho=%.3f t=%+.2f | F5 EB(V06): rho=%.3f t=%+.2f",
    f4$mean_rho, f4$t_nw, f5$mean_rho, f5$t_nw)

# ── 8. advisory 진단 ─────────────────────────────────────────────────────────
diag_of <- function(arm) {
  d <- merge(score_of(arm), returns_dt, by = c("Date", "Ticker"))
  ics <- d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date]
  dec <- d[, {
    q <- cut(frank(score), breaks = 10, labels = FALSE)
    .(dec_rets = list(tapply(Ret_1m, q, mean)))
  }, by = Date]
  dm <- colMeans(do.call(rbind, dec$dec_rets), na.rm = TRUE)
  icm <- ics[, mean(ic, na.rm = TRUE)]; icsd <- ics[, sd(ic, na.rm = TRUE)]
  n <- ics[, sum(is.finite(ic))]
  list(rank_ic = icm, icir = icm / icsd, ic_t = icm / icsd * sqrt(n),
       monotonicity = suppressWarnings(cor(seq_along(dm), dm, method = "spearman")),
       ic_pre2015 = ics[Date <= "2014-12-31", mean(ic, na.rm = TRUE)],
       ic_2015_2019 = ics[Date >= "2015-01-01" & Date <= "2019-12-31", mean(ic, na.rm = TRUE)],
       ic_2020p = ics[Date >= "2020-01-01", mean(ic, na.rm = TRUE)])
}
DIAG <- lapply(setNames(ARMS, ARMS), diag_of)
for (a in ARMS)
  say("adv %-12s IC=%+.4f ICIR=%+.3f mono=%+.2f", a, DIAG[[a]]$rank_ic,
      DIAG[[a]]$icir, DIAG[[a]]$monotonicity)

sc_after <- ast_sidecar_status()
say("sidecar after: live=%d live_with_ast=%d", sc_after$live, sc_after$live_with_ast)

# ── 9. 저장 ──────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
saveRDS(list(bt = lapply(bt, slim), paired = paired_res,
             cor_base = COR_BASE, cor_tuned = COR_TUNED, pair_selfcor = pair_selfcor,
             ax001 = AX001, lag1 = LAG1,
             fals = list(f1 = f1, f2 = f2, f3 = f3, f4 = f4, f5 = f5,
                         f1_series = hhi_m, f2_series = f2_m, f3_series = f3_m),
             diag = DIAG, common_m = common_m,
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after = sc_after[c("live", "live_with_ast")])),
        file.path(OUT, "wt009_eval_results.rds"))
say("완료 — wt009_eval_results.rds")
