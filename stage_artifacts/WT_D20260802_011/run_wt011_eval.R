# =============================================================================
# run_wt011_eval.R — WT-D20260802_011 평가 (시그니처 3M 평활판, WT-006 NP-2)
#   0. 승계: WT-006 alpha_scores.parquet(base z) 그대로 소비 — 시그니처 재계산 금지
#   1. 3M 평활(primary, min 2 valid) + 6M 평활(진단, min 4 valid) — 멤버십 가드
#   2. canonical_screen_bt dual-basis 실측 — 1차 관문 = turnover_annual <= 11.0
#   3. 부기간 PORT_t + advisory 진단(IC/ICIR/mono)
#   4. lag1 스트레스 + placebo(Gaussian 치환 5시드, 동일 평활 파이프라인)
#   5. 반증: 후속 홀딩월 기관+외국인 flow (base t=+4.08 대비 보존율)
#   6. 국면 조건부 + AX-001 (bad=CRISIS∪CAUTION IC ratio + crisis active)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_011/run_wt011_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_011")
W6  <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt011e] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")

sc_before <- ast_sidecar_status()
say("sidecar before: live=%d live_with_ast=%d", sc_before$live, sc_before$live_with_ast)

# ── 0. 승계 자산 로드 (재계산 금지) ─────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(W6, "alpha_scores.parquet")))
BASE[, Date := as.Date(Date)]
PAN_MEMB <- unique(as.data.table(read_parquet(file.path(W6, "signature_panel.parquet"),
             col_select = c("Date", "Ticker")))[, Date := as.Date(Date)])
SIG <- sort(unique(BASE$Date))
say("base 스코어: %d행, 신호월 %d개 (%s~%s)", nrow(BASE), length(SIG),
    as.character(min(SIG)), as.character(max(SIG)))

# ── 1. 하네스 (WT-006 동일) ─────────────────────────────────────────────────
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- as.data.table(read_parquet(file.path(W6, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: returns %d행 bench %d월", nrow(returns_dt), nrow(bench_dt))

# ── 2. 평활 (신호월 인덱스 trailing 평균 + 당월 멤버십 가드 + 월별 CS re-z) ──
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
smooth_k <- function(base, k, min_valid) {
  b <- copy(base)[, i := sig_idx[as.character(Date)]]
  L <- rbindlist(lapply(0:(k - 1L), function(o) b[, .(Ticker, i = i + o, z = score)]))
  s <- L[i >= k & i <= length(SIG), .(m = mean(z), nv = .N), by = .(Ticker, i)]
  s <- s[nv >= min_valid][, Date := SIG[i]]
  s <- s[PAN_MEMB, on = c("Date", "Ticker"), nomatch = 0L]   # 당월 유니버스 멤버십 가드
  s[, {
    mu <- mean(m); sd_ <- sd(m)
    if (!is.finite(sd_) || sd_ <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
    else list(Ticker = Ticker, score = (m - mu) / sd_)
  }, by = Date][is.finite(score)][, .(Date, Ticker, score)]
}
STRATS <- list(
  SIG_LEVY_PV_63_SM3 = smooth_k(BASE, 3L, 2L),   # ★ PRIMARY (사전등록)
  SIG_LEVY_PV_63_SM6 = smooth_k(BASE, 6L, 4L)    # 진단 — 선택 비사용
)
PRIM <- "SIG_LEVY_PV_63_SM3"
say("SM3 %d행 (%d월) / SM6 %d행", nrow(STRATS[[1]]), length(unique(STRATS[[1]]$Date)),
    nrow(STRATS[[2]]))

# ── 3. 라벨 방향 감사 (WT-004 M01 재사용) ───────────────────────────────────
m01 <- as.data.table(read_parquet(file.path(ROOT,
        "stage_artifacts/WT_D20260802_004/panel_M01_Mom_12_1_canonical.parquet")))
m01[, Date := as.Date(Date)]
chk <- merge(m01[is.finite(value), .(Date, Ticker, score = value)], returns_dt,
             by = c("Date", "Ticker"))
label_direction_ic <- chk[, .(ic = suppressWarnings(
    cor(score, Ret_1m, method = "spearman"))), by = Date][, mean(ic, na.rm = TRUE)]
say("라벨 방향 감사: M01 rank-IC 평균 %+.4f (양수 기대)", label_direction_ic)

# ── 4. ast_features (SPECIAL_OP escape + TS_MEAN 평활 — 수기 구성) ───────────
feats_primary <- list(
  node_count = 4, max_depth = 4, free_param_count = 3,
  distinct_field_count = 2, conditional_op_count = 0, window_variety = 2,
  restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "수기 구성 — CS_ZSCORE(TS_MEAN(CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:levy_area_pv_63)), 3m))"
)

# ── 5. canonical_screen_bt 실측 (1차 관문 = 회전) ────────────────────────────
bt <- list()
for (tag in names(STRATS)) {
  r <- canonical_screen_bt(STRATS[[tag]], returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_011", strategy_id = paste0("WT_D20260802_011_", tag),
        diag_dual_basis = TRUE, size_dt = size_dt,
        ast_features = if (tag == PRIM) feats_primary else NULL)
  bt[[tag]] <- r
  ew <- r$diag_ew_universe
  say("%-18s PORT_t=%+.2f (p=%.3f) netSR=%+.3f TO=%.0f%% n=%d | EW-uni t=%+.2f post17_t=%+.2f",
      tag, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue %||% NA,
      r$net_sr %||% NA, 100 * (r$turnover_annual %||% NA), r$n_months,
      ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_)
}
to_sm3 <- bt[[PRIM]]$turnover_annual
say("★ 1차 관문: SM3 turnover %.2f/yr — 제약 11.0 → %s", to_sm3,
    if (to_sm3 <= 11.0) "충족" else "미충족")

# ── 6. advisory 진단 + 부기간 PORT_t ─────────────────────────────────────────
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
  ics <- d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date]
  dec <- d[, {
    q <- cut(frank(score), breaks = 10, labels = FALSE)
    .(dec_rets = list(tapply(Ret_1m, q, mean)))
  }, by = Date]
  dm <- colMeans(do.call(rbind, dec$dec_rets), na.rm = TRUE)
  mono <- suppressWarnings(cor(seq_along(dm), dm, method = "spearman"))
  n <- ics[, sum(is.finite(ic))]
  icm <- ics[, mean(ic, na.rm = TRUE)]; icsd <- ics[, sd(ic, na.rm = TRUE)]
  sub <- function(a, b) ics[Date >= a & Date <= b, mean(ic, na.rm = TRUE)]
  list(rank_ic = icm, icir = icm / icsd, ic_t = icm / icsd * sqrt(n), n_ic = n,
       monotonicity = mono,
       ic_pre2015 = sub("1900-01-01", "2014-12-31"),
       ic_2015_2019 = sub("2015-01-01", "2019-12-31"),
       ic_2020p = sub("2020-01-01", "2099-01-01"),
       ic_series = ics)
}
DIAG <- lapply(STRATS, diag_of)
for (tag in names(DIAG)) {
  r <- DIAG[[tag]]
  say("%-18s IC=%+.4f ICIR=%+.3f t=%+.2f mono=%+.2f | sub: %+.3f / %+.3f / %+.3f",
      tag, r$rank_ic, r$icir, r$ic_t, r$monotonicity,
      r$ic_pre2015, r$ic_2015_2019, r$ic_2020p)
}
prA <- as.data.table(bt[[PRIM]]$period_returns)
prA[, active := ret_net - benchmark_ret]
sub_port_t <- list(
  pre2015  = nw_t(prA[date <= "2014-12-31", active]),
  y2015_19 = nw_t(prA[date >= "2015-01-01" & date <= "2019-12-31", active]),
  y2020p   = nw_t(prA[date >= "2020-01-01", active]),
  post2017 = nw_t(prA[date >= "2017-01-01", active]))
say("SM3 부기간 PORT_t: pre2015=%+.2f 2015-19=%+.2f 2020+=%+.2f post2017=%+.2f",
    sub_port_t$pre2015, sub_port_t$y2015_19, sub_port_t$y2020p, sub_port_t$post2017)

# ── 7. lag1 스트레스 (평활판 반감기) ────────────────────────────────────────
lag1 <- copy(STRATS[[PRIM]])
lag1[, i := sig_idx[as.character(Date)] + 1L]
lag1 <- lag1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
bt_lag1 <- canonical_screen_bt(lag1, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260802_011_lag1", strategy_id = "WT_D20260802_011_SM3_lag1",
    diag_dual_basis = FALSE)
say("lag1: SM3 %+.2f → lag1 %+.2f", bt[[PRIM]]$portfolio_alpha_t_nw_lag3,
    bt_lag1$portfolio_alpha_t_nw_lag3)

# ── 8. placebo — Gaussian 치환 5시드 (동일 평활 파이프라인) ──────────────────
placebo_res <- list()
for (seed in 1:5) {
  set.seed(20260811 + seed)
  fake <- copy(BASE)[, score := rnorm(.N)]
  plz <- smooth_k(fake, 3L, 2L)
  btp <- canonical_screen_bt(plz, returns_dt, bench_dt, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
      run_id = sprintf("WT-D20260802_011_placebo%d", seed),
      strategy_id = sprintf("WT_D20260802_011_placebo%d", seed), diag_dual_basis = FALSE)
  dpl <- merge(plz, returns_dt, by = c("Date", "Ticker"))
  icp <- dpl[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))),
             by = Date][, mean(ic, na.rm = TRUE)]
  placebo_res[[seed]] <- list(port_t = btp$portfolio_alpha_t_nw_lag3, rank_ic = icp,
                              turnover = btp$turnover_annual)
  say("  placebo seed %d: PORT_t=%+.2f rank_IC=%+.4f TO=%.2f", seed,
      btp$portfolio_alpha_t_nw_lag3, icp, btp$turnover_annual)
}

# ── 9. 반증: 후속 홀딩월 기관+외국인 순매수 (WT-006 프레임 재사용) ───────────
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
IV[, Date := as.Date(Date)]
IV <- IV[Ticker %chin% unique(BASE$Ticker)]
sig_next <- data.table(Date = SIG[-length(SIG)], hold_end = SIG[-1])
last_hold_end <- MEND[findInterval(SIG[length(SIG)], MEND) + 1L]
sig_next <- rbind(sig_next, data.table(Date = SIG[length(SIG)], hold_end = last_hold_end))
IVL <- IV[, .(Date_d = Date, Ticker, netbuy = Foreign + Institutional)]
flow_hold <- rbindlist(lapply(seq_len(nrow(sig_next)), function(i) {
  d0 <- sig_next$Date[i]; d1 <- sig_next$hold_end[i]
  IVL[Date_d > d0 & Date_d <= d1, .(flow = sum(netbuy), nd = .N), by = Ticker][, Date := d0]
}))
FL <- merge(STRATS[[PRIM]], flow_hold, by = c("Date", "Ticker"))
FL <- merge(FL, liq_dt, by = c("Date", "Ticker"))
FL <- FL[is.finite(adv) & adv > 0 & nd > 0, .(Date, Ticker, score, fint = flow / (adv * nd))]
fsp <- FL[, {
  q <- cut(frank(score), breaks = 5, labels = FALSE)
  .(spread = mean(fint[q == 5], na.rm = TRUE) - mean(fint[q == 1], na.rm = TRUE))
}, by = Date]
fals_t <- nw_t(fsp$spread)
say("반증 검정(SM3): Q5-Q1 후속월 (외인+기관)/ADV·일 평균 %+.5f, NW t=%+.2f (base +4.08)",
    fsp[, mean(spread, na.rm = TRUE)], fals_t)

# ── 10. 국면 조건부 + AX-001 (bad=CRISIS∪CAUTION) ────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[
      , .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
prA[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
prR <- merge(prA, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- prR[!is.na(Category),
               .(n = .N, mean_active = mean(active), t_nw = nw_t(active)), by = Category]
say("--- 국면 조건부 active (SM3) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-10s n=%3d mean=%+.4f t=%+.2f", reg_tab$Category[i], reg_tab$n[i],
      reg_tab$mean_active[i], reg_tab$t_nw[i])
ics <- DIAG[[PRIM]]$ic_series
ics[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
icr <- merge(ics, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
ic_bad    <- icr[Category %in% c("CRISIS", "CAUTION"), mean(ic, na.rm = TRUE)]
ic_normal <- icr[Category %in% c("RISK_ON", "NEUTRAL"), mean(ic, na.rm = TRUE)]
crisis_t  <- reg_tab[Category == "CRISIS", t_nw]
say("AX-001: IC bad=%+.4f / normal=%+.4f (ratio %+.2f) | crisis active t=%+.2f",
    ic_bad, ic_normal, ic_bad / ic_normal,
    if (length(crisis_t)) crisis_t else NA_real_)

# ── 11. 보존율 (base 인용 — 재측정 없음) ─────────────────────────────────────
base_q <- list(port_t = 1.225, rank_ic = -0.00974, flow_t = 4.076, turnover = 15.78,
               lag1_port_t = 0.237)
retention <- list(
  port_t_ratio  = bt[[PRIM]]$portfolio_alpha_t_nw_lag3 / base_q$port_t,
  rank_ic_ratio = DIAG[[PRIM]]$rank_ic / base_q$rank_ic,
  flow_t_ratio  = fals_t / base_q$flow_t,
  turnover_ratio = to_sm3 / base_q$turnover)
say("보존율(SM3/base): PORT_t %.2f | rank_IC %.2f | flow_t %.2f | TO %.2f",
    retention$port_t_ratio, retention$rank_ic_ratio, retention$flow_t_ratio,
    retention$turnover_ratio)

sc_after <- ast_sidecar_status()
say("sidecar after: live=%d live_with_ast=%d", sc_after$live, sc_after$live_with_ast)

# ── 12. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
saveRDS(list(bt = lapply(bt, slim), bt_lag1 = slim(bt_lag1),
             diag = lapply(DIAG, function(d) d[setdiff(names(d), "ic_series")]),
             ic_series_primary = DIAG[[PRIM]]$ic_series,
             sub_port_t = sub_port_t, placebo = placebo_res,
             falsification = list(mean_spread = fsp[, mean(spread, na.rm = TRUE)],
                                  t_nw = fals_t, n_months = nrow(fsp)),
             regime_tab = reg_tab,
             ax001 = list(ic_bad = ic_bad, ic_normal = ic_normal,
                          ratio = ic_bad / ic_normal,
                          crisis_t = if (length(crisis_t)) crisis_t else NA_real_),
             retention = retention, base_quoted = base_q,
             label_direction_ic = label_direction_ic,
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after  = sc_after[c("live", "live_with_ast")]),
             feats_primary = feats_primary),
        file.path(OUT, "wt011_eval_results.rds"))
write_parquet(STRATS[[PRIM]], file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt011_eval_results.rds + alpha_scores.parquet")
