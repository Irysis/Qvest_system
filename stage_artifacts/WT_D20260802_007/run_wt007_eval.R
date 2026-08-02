# =============================================================================
# run_wt007_eval.R — WT-D20260802_007 평가 (사전등록 primary = INS_MAGQ3 단일 판정)
#   1. 6 신호 canonical_screen_bt (top25, 15bps, liq 2e8, dual-basis + cap-tier)
#   2. paired: primary vs INS01_BASE3(R9 재현) vs INS_MAG_NOFILT3(분해)
#   3. FQ-079 축 구분: INS_SEQ12 vs INS02_BREADTH6(R33) 월별 CS Spearman
#   4. lag1 스트레스 + placebo(cr 월내 셔플 5시드) + PIT truncation-invariance
#   5. 반증: 후속 홀딩월 기관+외국인 flow (WT-006 동일 구조)
#   6. 국면 조건부 귀속 (사후 slicing)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_007/run_wt007_eval.R", encoding="UTF-8")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_007")
W4  <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt007e] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")

sc_before <- ast_sidecar_status()
say("sidecar before: live=%d live_with_ast=%d", sc_before$live, sc_before$live_with_ast)

## ── 1. 패널 + 하네스 ─────────────────────────────────────────────────────────
PAN <- as.data.table(read_parquet(file.path(OUT, "insider_axes_panel.parquet")))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)

## sig_ym → 월말 거래일 매핑
me_map <- data.table(Date = MEND, sig_ym = format(MEND, "%Y%m"))
PAN <- merge(PAN, me_map, by = "sig_ym")
SIG <- sort(unique(PAN$Date))
say("신호월 %d (%s ~ %s)", length(SIG), format(min(SIG), "%Y-%m"), format(max(SIG), "%Y-%m"))

sig_all <- MEND[MEND >= min(SIG)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[(K200 == TRUE | KQ150 == TRUE) & is.finite(Size) & Size > 0,
                    .(Date, Ticker, Size)]
say("harness: returns %d행 bench %d월", nrow(returns_dt), nrow(bench_dt))

## ── 2. 월별 CS winsorize 3sd + z (EVT3는 raw — 월내 1~2명 sd 붕괴 방지) ──────
cs_z <- function(dt, col, orient = +1) {
  d <- dt[is.finite(get(col)), .(Date, Ticker, x = orient * get(col))]
  d[, {
    mu <- mean(x); s <- sd(x)
    if (!is.finite(s) || s <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
    else {
      xw <- pmin(pmax(x, mu - 3 * s), mu + 3 * s)
      s2 <- sd(xw)
      if (!is.finite(s2) || s2 <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
      else list(Ticker = Ticker, score = (xw - mean(xw)) / s2)
    }
  }, by = Date][is.finite(score)]
}
cs_raw <- function(dt, col, orient = +1)
  dt[is.finite(get(col)), .(Date, Ticker, score = orient * get(col))]

STRATS <- list(
  INS_MAGQ3       = cs_z(PAN, "INS_MAGQ3", +1),        # ★ PRIMARY (FQ-078 사전등록)
  INS_MAG_NOFILT3 = cs_z(PAN, "INS_MAG_NOFILT3", +1),  # 분해 대조
  INS01_BASE3     = cs_z(PAN, "INS01_BASE3", +1),      # R9 '참여 여부' 재현 baseline
  INS_SEQ12       = cs_z(PAN, "INS_SEQ12", +1),        # FQ-079 대조축
  INS_EVT3        = cs_raw(PAN, "INS_EVT3", +1),       # FQ-080 대조축 (sparse, raw)
  INS02_BREADTH6  = cs_z(PAN, "INS02_BREADTH6", +1)    # R33 재현 (rank-cor 대조 전용)
)
PRIM <- "INS_MAGQ3"
for (tag in names(STRATS)) say("  %s: %d행 %d월", tag, nrow(STRATS[[tag]]), uniqueN(STRATS[[tag]]$Date))

## ── 3. 라벨 방향 감사 (WT_004 M01) ───────────────────────────────────────────
m01 <- as.data.table(read_parquet(file.path(W4, "panel_M01_Mom_12_1_canonical.parquet")))
m01[, Date := as.Date(Date)]
chk <- merge(m01[is.finite(value), .(Date, Ticker, score = value)], returns_dt, by = c("Date", "Ticker"))
label_direction_ic <- chk[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))),
                          by = Date][, mean(ic, na.rm = TRUE)]
say("라벨 방향 감사: M01 rank-IC 평균 %+.4f (양수 = forward 라벨 정상)", label_direction_ic)

## ── 4. ast_features (SPECIAL_OP escape — 수기 구성, 정직 라벨) ───────────────
feats_primary <- list(
  node_count = 4, max_depth = 4, free_param_count = 3,
  distinct_field_count = 3, conditional_op_count = 1, window_variety = 2,
  restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "수기 구성 — CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:insider_commitment_magq3 {cr=|dQ|/max(Qb,Qa), rolling-36m tercile cut, trailing 3m signed sum}))"
)

## ── 5. canonical_screen_bt 실측 (primary만 판정 — 나머지 대조/진단) ──────────
bt <- list()
for (tag in names(STRATS)) {
  r <- canonical_screen_bt(STRATS[[tag]], returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_007", strategy_id = paste0("WT_D20260802_007_", tag),
        diag_dual_basis = TRUE, size_dt = size_dt,
        ast_features = if (tag == PRIM) feats_primary else NULL)
  bt[[tag]] <- r
  ew <- r$diag_ew_universe
  say("%-16s PORT_t=%+.2f (p=%.3f) netSR=%+.3f IR=%+.3f TO=%.0f%% n=%d | EW-uni t=%+.2f post17_t=%+.2f",
      tag, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue %||% NA,
      r$net_sr %||% NA, r$information_ratio %||% NA, 100 * (r$turnover_annual %||% NA),
      r$n_months, ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_)
  ct <- r$diag_cap_tier
  if (!is.null(ct)) say("   cap-tier: %s", paste(capture.output(print(ct))[-1], collapse = " | "))
}

## ── 6. advisory 진단 ─────────────────────────────────────────────────────────
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
diag_of <- function(sc) {
  d <- merge(sc, returns_dt, by = c("Date", "Ticker"))
  ics <- d[, .(ic = if (.N >= 5L) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_,
               n = .N), by = Date]
  dec <- d[, if (.N >= 30L) {
    q <- cut(frank(score, ties.method = "random"), breaks = 10, labels = FALSE)
    .(dq = mean(Ret_1m[q == 10]) - mean(Ret_1m[q == 1]),
      dec_rets = list(tapply(Ret_1m, q, mean)))
  } else NULL, by = Date]
  dm <- if (nrow(dec)) colMeans(do.call(rbind, dec$dec_rets), na.rm = TRUE) else rep(NA_real_, 10)
  mono <- suppressWarnings(cor(seq_along(dm), dm, method = "spearman"))
  n <- ics[, sum(is.finite(ic))]
  icm <- ics[, mean(ic, na.rm = TRUE)]; icsd <- ics[, sd(ic, na.rm = TRUE)]
  sub <- function(a, b) ics[Date >= a & Date <= b, mean(ic, na.rm = TRUE)]
  list(rank_ic = icm, icir = icm / icsd, ic_t = icm / icsd * sqrt(n), n_ic = n,
       monotonicity = mono, decile_means = as.list(round(dm, 5)),
       ic_pre2015 = sub("1900-01-01", "2014-12-31"),
       ic_2015_2019 = sub("2015-01-01", "2019-12-31"),
       ic_2020p = sub("2020-01-01", "2099-01-01"),
       ic_series = ics)
}
set.seed(20260802)
DIAG <- lapply(STRATS, diag_of)
for (tag in names(DIAG)) {
  r <- DIAG[[tag]]
  say("%-16s IC=%+.4f ICIR=%+.3f t=%+.2f mono=%+.2f | sub: %+.3f / %+.3f / %+.3f (n_ic=%d)",
      tag, r$rank_ic, r$icir, r$ic_t, r$monotonicity,
      r$ic_pre2015, r$ic_2015_2019, r$ic_2020p, r$n_ic)
}

## primary 부기간 PORT_t
prA <- as.data.table(bt[[PRIM]]$period_returns)
prA[, active := ret_net - benchmark_ret]
sub_port_t <- list(
  pre2015  = nw_t(prA[date <= "2014-12-31", active]),
  y2015_19 = nw_t(prA[date >= "2015-01-01" & date <= "2019-12-31", active]),
  y2020p   = nw_t(prA[date >= "2020-01-01", active]),
  post2017 = nw_t(prA[date >= "2017-01-01", active]))
say("primary 부기간 PORT_t: pre2015=%+.2f 2015-19=%+.2f 2020+=%+.2f post2017=%+.2f",
    sub_port_t$pre2015, sub_port_t$y2015_19, sub_port_t$y2020p, sub_port_t$post2017)

## ── 7. paired 비교 (FQ-078 mandate: tercile 제거 arm vs 전체 arm, 동일 기질) ──
paired_diff <- function(tagA, tagB) {
  a <- as.data.table(bt[[tagA]]$period_returns)[, .(date, aA = ret_net - benchmark_ret)]
  b <- as.data.table(bt[[tagB]]$period_returns)[, .(date, aB = ret_net - benchmark_ret)]
  m <- merge(a, b, by = "date")
  list(n = nrow(m), mean_diff_bps_m = 1e4 * m[, mean(aA - aB)], t_nw = nw_t(m[, aA - aB]))
}
PD <- list(
  prim_vs_base    = paired_diff(PRIM, "INS01_BASE3"),
  prim_vs_nofilt  = paired_diff(PRIM, "INS_MAG_NOFILT3"),
  nofilt_vs_base  = paired_diff("INS_MAG_NOFILT3", "INS01_BASE3")
)
for (k in names(PD)) say("paired %s: n=%d mean=%+.1f bps/m NW t=%+.2f", k, PD[[k]]$n, PD[[k]]$mean_diff_bps_m, PD[[k]]$t_nw)

## ── 8. FQ-079 축 구분 실측: SEQ12 vs R33 breadth + 상호 rank-cor 행렬 ─────────
rank_cor_pair <- function(tagA, tagB) {
  m <- merge(STRATS[[tagA]][, .(Date, Ticker, a = score)],
             STRATS[[tagB]][, .(Date, Ticker, b = score)], by = c("Date", "Ticker"))
  rc <- m[, if (.N >= 5L) .(r = suppressWarnings(cor(a, b, method = "spearman")), n = .N), by = Date]
  list(mean = rc[, mean(r, na.rm = TRUE)], sd = rc[, sd(r, na.rm = TRUE)],
       n_months = nrow(rc), mean_n = rc[, mean(n)])
}
RC <- list(
  seq_vs_breadth   = rank_cor_pair("INS_SEQ12", "INS02_BREADTH6"),   # ★ 축 구분 판정
  seq_vs_base      = rank_cor_pair("INS_SEQ12", "INS01_BASE3"),
  prim_vs_base     = rank_cor_pair(PRIM, "INS01_BASE3"),
  prim_vs_nofilt   = rank_cor_pair(PRIM, "INS_MAG_NOFILT3"),
  prim_vs_breadth  = rank_cor_pair(PRIM, "INS02_BREADTH6"),
  prim_vs_seq      = rank_cor_pair(PRIM, "INS_SEQ12")
)
for (k in names(RC)) say("rank-cor %s: %+.3f ± %.3f (%d개월, 평균 %d명)",
    k, RC[[k]]$mean, RC[[k]]$sd, RC[[k]]$n_months, round(RC[[k]]$mean_n))

## 기존 admitted alpha와의 직교성 (WT_004 컴파일 패널 5종)
orth_targets <- c("M01_Mom_12_1", "D03_RealVol", "D41_Vol_of_Vol", "D45_Downside_Dev", "D55_Vol_Trend")
Pz <- STRATS[[PRIM]][, .(Date, Ticker, prim = score)]
ORTH <- list()
for (f in orth_targets) {
  fp <- as.data.table(read_parquet(file.path(W4, sprintf("panel_%s_canonical.parquet", f))))
  fp[, Date := as.Date(Date)]
  m <- merge(Pz, fp[is.finite(value), .(Date, Ticker, v = value)], by = c("Date", "Ticker"))
  rc <- m[, if (.N >= 5L) .(r = suppressWarnings(cor(prim, v, method = "spearman"))), by = Date]
  ORTH[[f]] <- list(mean = rc[, mean(r, na.rm = TRUE)], sd = rc[, sd(r, na.rm = TRUE)])
  say("직교성 vs %-18s rho = %+.3f ± %.3f", f, ORTH[[f]]$mean, ORTH[[f]]$sd)
}

## ── 9. lag1 스트레스 (primary) ───────────────────────────────────────────────
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
lag1 <- copy(STRATS[[PRIM]])
lag1[, i := sig_idx[as.character(Date)] + 1L]
lag1 <- lag1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
bt_lag1 <- canonical_screen_bt(lag1, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260802_007_lag1", strategy_id = "WT_D20260802_007_MAGQ3_lag1",
    diag_dual_basis = FALSE)
say("lag1 스트레스: base PORT_t=%+.2f → lag1 %+.2f", bt[[PRIM]]$portfolio_alpha_t_nw_lag3,
    bt_lag1$portfolio_alpha_t_nw_lag3)

## ── 10. placebo — cr 월내 무작위 재배정 (5시드): 크기 정보 파괴, 참여 구조 보존 ──
slim <- as.data.table(read_parquet(file.path(OUT, "trades_slim.parquet")))
slim[, vd := as.Date(vd)]; slim[, rd := as.Date(rd)]
build_axes <- readRDS(file.path(OUT, "build_axes_fn.rds"))
YMG <- sort(unique(PAN$sig_ym))
placebo_res <- list()
for (seed in 1:5) {
  set.seed(20260807 + seed)
  sh <- copy(slim)
  sh[is.finite(cr), cr := sample(cr), by = sig_ym]
  Psh <- build_axes(sh, YMG)
  Psh <- merge(Psh, me_map, by = "sig_ym")
  plz <- cs_z(Psh, "INS_MAGQ3", +1)
  btp <- canonical_screen_bt(plz, returns_dt, bench_dt, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
      run_id = sprintf("WT-D20260802_007_pl%d", seed),
      strategy_id = sprintf("WT_D20260802_007_placebo%d", seed), diag_dual_basis = FALSE)
  dpl <- merge(plz, returns_dt, by = c("Date", "Ticker"))
  icp <- dpl[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date][, mean(ic, na.rm = TRUE)]
  placebo_res[[seed]] <- list(port_t = btp$portfolio_alpha_t_nw_lag3, rank_ic = icp)
  say("  placebo seed %d: PORT_t=%+.2f rank_IC=%+.4f", seed, btp$portfolio_alpha_t_nw_lag3, icp)
}

## ── 11. PIT truncation-invariance (표본월 3곳) ───────────────────────────────
pit_detail <- list(); pit_ok <- TRUE
axes_cols <- c("INS_MAGQ3", "INS_MAG_NOFILT3", "INS01_BASE3", "INS_SEQ12", "INS_EVT3", "INS02_BREADTH6")
smp <- YMG[pmax(1L, floor(length(YMG) * c(0.3, 0.6, 0.9)))]
for (m_star in smp) {
  g_tr <- build_axes(slim[sig_ym <= m_star], YMG[YMG <= m_star])
  a <- melt(PAN[sig_ym == m_star, c("Ticker", axes_cols), with = FALSE], id.vars = "Ticker", variable.factor = FALSE)
  b <- melt(g_tr[sig_ym == m_star, c("Ticker", axes_cols), with = FALSE], id.vars = "Ticker", variable.factor = FALSE)
  m2 <- merge(a, b, by = c("Ticker", "variable"), all = TRUE)
  same <- m2[, all(fifelse(is.na(value.x), is.na(value.y),
                           !is.na(value.y) & abs(value.x - value.y) < 1e-9))]
  pit_ok <- pit_ok && isTRUE(same)
  pit_detail[[m_star]] <- isTRUE(same)
  say("[PIT] truncation-invariance @%s: %s", m_star, ifelse(isTRUE(same), "PASS", "FAIL"))
}
stopifnot(pit_ok)

## ── 12. 반증: 후속 홀딩월 기관+외국인 순매수 (WT-006 동일 구조) ──────────────
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
IV[, Date := as.Date(Date)]
IV <- IV[Ticker %chin% unique(PAN$Ticker)]
say("investor flow: %d행 (%s~%s)", nrow(IV), as.character(min(IV$Date)), as.character(max(IV$Date)))
sig_next <- data.table(Date = SIG[-length(SIG)], hold_end = SIG[-1])
last_hold_end <- MEND[findInterval(SIG[length(SIG)], MEND) + 1L]
if (!is.na(last_hold_end)) sig_next <- rbind(sig_next, data.table(Date = SIG[length(SIG)], hold_end = last_hold_end))
IVL <- IV[, .(Date_d = Date, Ticker, netbuy = Foreign + Institutional)]
flow_hold <- rbindlist(lapply(seq_len(nrow(sig_next)), function(i) {
  d0 <- sig_next$Date[i]; d1 <- sig_next$hold_end[i]
  IVL[Date_d > d0 & Date_d <= d1, .(flow = sum(netbuy), nd = .N), by = Ticker][, Date := d0]
}))
flow_test <- function(tag, min_names = 25L) {
  FL <- merge(STRATS[[tag]], flow_hold, by = c("Date", "Ticker"))
  FL <- merge(FL, liq_dt, by = c("Date", "Ticker"))
  FL <- FL[is.finite(adv) & adv > 0 & nd > 0, .(Date, Ticker, score, fint = flow / (adv * nd))]
  fsp <- FL[, if (.N >= min_names) {
    q <- cut(frank(score, ties.method = "random"), breaks = 5, labels = FALSE)
    .(spread = mean(fint[q == 5], na.rm = TRUE) - mean(fint[q == 1], na.rm = TRUE))
  } else NULL, by = Date]
  if (nrow(fsp) < 12L) return(list(mean_spread = NA_real_, t_nw = NA_real_, n_months = nrow(fsp)))
  list(mean_spread = fsp[, mean(spread, na.rm = TRUE)], t_nw = nw_t(fsp$spread), n_months = nrow(fsp))
}
set.seed(20260802)
FALS <- list(primary = flow_test(PRIM), seq12 = flow_test("INS_SEQ12"),
             base3 = flow_test("INS01_BASE3"))
for (k in names(FALS)) say("flow 링크 %s: Q5-Q1 %+.5f NW t=%+.2f (%d개월)",
    k, FALS[[k]]$mean_spread, FALS[[k]]$t_nw, FALS[[k]]$n_months)

## ── 13. 국면 조건부 귀속 (사후 slicing) ──────────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
prA[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
prR <- merge(prA, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- prR[!is.na(Category), .(n = .N, mean_active = mean(active), t_nw = nw_t(active)), by = Category]
say("--- 국면 조건부 active (primary) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-10s n=%3d mean=%+.4f t=%+.2f", reg_tab$Category[i], reg_tab$n[i],
      reg_tab$mean_active[i], reg_tab$t_nw[i])

sc_after <- ast_sidecar_status()
say("sidecar after: live=%d live_with_ast=%d", sc_after$live, sc_after$live_with_ast)

## ── 14. 저장 ─────────────────────────────────────────────────────────────────
slim_bt <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
saveRDS(list(bt = lapply(bt, slim_bt), bt_lag1 = slim_bt(bt_lag1),
             diag = lapply(DIAG, function(d) d[setdiff(names(d), "ic_series")]),
             ic_series_primary = DIAG[[PRIM]]$ic_series,
             sub_port_t = sub_port_t, paired = PD, rank_cor = RC, orth = ORTH,
             placebo = placebo_res, pit_truncation = pit_detail,
             falsification = FALS, regime_tab = reg_tab,
             label_direction_ic = label_direction_ic,
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after  = sc_after[c("live", "live_with_ast")]),
             feats_primary = feats_primary),
        file.path(OUT, "wt007_eval_results.rds"))
write_parquet(STRATS[[PRIM]], file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt007_eval_results.rds + alpha_scores.parquet")
