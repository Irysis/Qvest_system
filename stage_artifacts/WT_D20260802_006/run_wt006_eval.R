# =============================================================================
# run_wt006_eval.R — WT-D20260802_006 평가 (사전등록 primary 단일 판정)
#   1. primary SIG_LEVY_PV_63 = −A_pv → canonical_screen_bt (top25, dual-basis)
#   2. 레벨별 기여 분해 (진단 — 선택 아님)
#   3. 직교성: WT_004 패널(M01/D03/D41/D45/D55) + 자체 레벨1
#   4. lag1 스트레스 + placebo(증분 순서 셔플 5시드)
#   5. 반증: 후속 홀딩월 기관+외국인 flow (A6)
#   6. 국면 조건부 귀속 (unified_regime_signal — 사후 slicing만, C5 비발동)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_006/run_wt006_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_006")
W4  <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt006e] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
source(file.path(OUT, "signature_lib.R"))

sc_before <- ast_sidecar_status()
say("sidecar before: live=%d live_with_ast=%d", sc_before$live, sc_before$live_with_ast)

# ── 1. 패널 + 하네스 ─────────────────────────────────────────────────────────
PAN <- as.data.table(read_parquet(file.path(OUT, "signature_panel.parquet")))
SIG <- sort(unique(PAN$Date))
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
size_dt    <- as.data.table(read_parquet(file.path(OUT, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: returns %d행 bench %d월", nrow(returns_dt), nrow(bench_dt))

# ── 2. 월별 CS winsorize 3sd + z ─────────────────────────────────────────────
cs_z <- function(dt, col, orient = +1) {
  d <- dt[is.finite(get(col)), .(Date, Ticker, x = orient * get(col))]
  d[, {
    mu <- mean(x); s <- sd(x)
    if (!is.finite(s) || s <= 0) list(Ticker = Ticker, score = rep(NA_real_, .N))
    else {
      xw <- pmin(pmax(x, mu - 3 * s), mu + 3 * s)
      list(Ticker = Ticker, score = (xw - mean(xw)) / sd(xw))
    }
  }, by = Date][is.finite(score)]
}

# 사전등록 orientation: primary = −A_pv
STRATS <- list(
  SIG_LEVY_PV_63 = cs_z(PAN, "A_pv", -1),          # ★ PRIMARY (사전등록)
  LVL1_P_63      = cs_z(PAN, "lvl1_p", +1),        # 레벨1 가격(모멘텀 등가) — 진단
  LVL1_V_63      = cs_z(PAN, "lvl1_v", +1),        # 레벨1 거래대금 추세 — 진단
  A_TP_63        = cs_z(PAN, "A_tp", +1),          # 레벨2 time-price — 진단
  A_TV_63        = cs_z(PAN, "A_tv", +1),          # 레벨2 time-volume — 진단
  LOGSIG3_PPV_63 = cs_z(PAN, "logsig3_ppv", +1),   # 레벨3 — 진단
  LOGSIG3_PVV_63 = cs_z(PAN, "logsig3_pvv", +1),   # 레벨3 — 진단
  A_PV_W21       = cs_z(PAN, "A_pv_w21", -1),      # 창 강건성 — 진단
  A_PV_W126      = cs_z(PAN, "A_pv_w126", -1)      # 창 강건성 — 진단
)
PRIM <- "SIG_LEVY_PV_63"

# ── 3. 라벨 방향 감사 (WT_004 M01 재사용 — forward 라벨 방향 동적 확인) ─────
m01 <- as.data.table(read_parquet(file.path(W4, "panel_M01_Mom_12_1_canonical.parquet")))
m01[, Date := as.Date(Date)]
chk <- merge(m01[is.finite(value), .(Date, Ticker, score = value)], returns_dt, by = c("Date", "Ticker"))
ic_chk <- chk[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date]
say("라벨 방향 감사: M01 rank-IC 평균 %+.4f (양수 기대 → forward 라벨 방향 정상)",
    ic_chk[, mean(ic, na.rm = TRUE)])
label_direction_ic <- ic_chk[, mean(ic, na.rm = TRUE)]

# ── 4. ast_features (SPECIAL_OP escape — 수기 구성, 정직 라벨) ───────────────
feats_primary <- list(
  node_count = 3, max_depth = 3, free_param_count = 2,
  distinct_field_count = 2, conditional_op_count = 0, window_variety = 1,
  restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "수기 구성(SPECIAL_OP는 ast_compile 비대상) — CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:levy_area_pv_63))"
)

# ── 5. canonical_screen_bt 실측 (전 전략 — primary만 판정, 나머지 진단) ──────
bt <- list()
for (tag in names(STRATS)) {
  r <- canonical_screen_bt(STRATS[[tag]], returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_006", strategy_id = paste0("WT_D20260802_006_", tag),
        diag_dual_basis = TRUE, size_dt = size_dt,
        ast_features = if (tag == PRIM) feats_primary else NULL)
  bt[[tag]] <- r
  ew <- r$diag_ew_universe
  say("%-15s PORT_t=%+.2f (p=%.3f) netSR=%+.3f IR=%+.3f TO=%.0f%% n=%d | EW-uni t=%+.2f post17_t=%+.2f",
      tag, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue %||% NA,
      r$net_sr %||% NA, r$information_ratio %||% NA, 100 * (r$turnover_annual %||% NA),
      r$n_months, ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_)
}

# ── 6. advisory 진단 (rank IC / ICIR / monotonicity / subperiod) ─────────────
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
    .(dq = mean(Ret_1m[q == 10]) - mean(Ret_1m[q == 1]),
      dec_rets = list(tapply(Ret_1m, q, mean)))
  }, by = Date]
  dm <- colMeans(do.call(rbind, dec$dec_rets), na.rm = TRUE)
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
DIAG <- lapply(STRATS, diag_of)
for (tag in names(DIAG)) {
  r <- DIAG[[tag]]
  say("%-15s IC=%+.4f ICIR=%+.3f t=%+.2f mono=%+.2f | sub: %+.3f / %+.3f / %+.3f",
      tag, r$rank_ic, r$icir, r$ic_t, r$monotonicity,
      r$ic_pre2015, r$ic_2015_2019, r$ic_2020p)
}

# primary 부기간 PORT_t (active 시계열 슬라이스 NW t)
prA <- as.data.table(bt[[PRIM]]$period_returns)
prA[, active := ret_net - benchmark_ret]
sub_port_t <- list(
  pre2015   = nw_t(prA[date <= "2014-12-31", active]),
  y2015_19  = nw_t(prA[date >= "2015-01-01" & date <= "2019-12-31", active]),
  y2020p    = nw_t(prA[date >= "2020-01-01", active]),
  post2017  = nw_t(prA[date >= "2017-01-01", active]))
say("primary 부기간 PORT_t: pre2015=%+.2f 2015-19=%+.2f 2020+=%+.2f post2017=%+.2f",
    sub_port_t$pre2015, sub_port_t$y2015_19, sub_port_t$y2020p, sub_port_t$post2017)

# ── 7. 직교성 (월별 CS Spearman) — WT_004 5팩터 + 자체 레벨1 ─────────────────
orth_targets <- c("M01_Mom_12_1", "D03_RealVol", "D41_Vol_of_Vol",
                  "D45_Downside_Dev", "D55_Vol_Trend")
Pz <- STRATS[[PRIM]][, .(Date, Ticker, prim = score)]
ORTH <- list()
for (f in orth_targets) {
  fp <- as.data.table(read_parquet(file.path(W4, sprintf("panel_%s_canonical.parquet", f))))
  fp[, Date := as.Date(Date)]
  m <- merge(Pz, fp[is.finite(value), .(Date, Ticker, v = value)], by = c("Date", "Ticker"))
  rc <- m[, .(r = suppressWarnings(cor(prim, v, method = "spearman")), n = .N), by = Date]
  ORTH[[f]] <- list(mean = rc[, mean(r, na.rm = TRUE)], sd = rc[, sd(r, na.rm = TRUE)])
}
for (f in c("LVL1_P_63", "LVL1_V_63", "A_TP_63", "A_TV_63")) {
  m <- merge(Pz, STRATS[[f]][, .(Date, Ticker, v = score)], by = c("Date", "Ticker"))
  rc <- m[, .(r = suppressWarnings(cor(prim, v, method = "spearman"))), by = Date]
  ORTH[[f]] <- list(mean = rc[, mean(r, na.rm = TRUE)], sd = rc[, sd(r, na.rm = TRUE)])
}
say("--- 직교성 (primary vs 기존/자체) ---")
for (f in names(ORTH)) say("  vs %-18s rho = %+.3f ± %.3f", f, ORTH[[f]]$mean, ORTH[[f]]$sd)

# ── 8. lag1 스트레스 (신호 1개월 지연 — 동월 누출 판별) ──────────────────────
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
lag1 <- copy(STRATS[[PRIM]])
lag1[, i := sig_idx[as.character(Date)] + 1L]
lag1 <- lag1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
bt_lag1 <- canonical_screen_bt(lag1, returns_dt, bench_dt, top_n = 25L,
    cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
    run_id = "WT-D20260802_006_lag1", strategy_id = "WT_D20260802_006_SIG_LEVY_lag1",
    diag_dual_basis = FALSE)
say("lag1 스트레스: base PORT_t=%+.2f → lag1 %+.2f (base≫lag1 붕괴 시 동월누출 의심)",
    bt[[PRIM]]$portfolio_alpha_t_nw_lag3, bt_lag1$portfolio_alpha_t_nw_lag3)

# ── 9. placebo — 일간 증분 순서 셔플(경로-순서 파괴, 5시드) ──────────────────
say("placebo: 증분 순서 셔플 5시드 (경로-순서 정보가 원천임을 입증)")
D <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select = c("Date", "Ticker", "Close", "Vol")))
D[, Date := as.Date(Date)]
D <- D[Ticker %chin% unique(PAN$Ticker) & is.finite(Close) & Close > 0 &
         is.finite(Vol) & Vol > 0]
setkey(D, Ticker, Date)
CAL <- sort(unique(D$Date))
levy_shuffled <- function(close, vol, perm_seedoff, min_days = 40L) {
  n <- length(close)
  if (n < min_days) return(NA_real_)
  dp <- diff(log(close)); dv <- diff(log(vol * close))
  sp <- sd(dp); sv <- sd(dv)
  if (!is.finite(sp) || sp <= 0 || !is.finite(sv) || sv <= 0) return(NA_real_)
  idx <- sample.int(n - 1L)          # 증분 (dp,dv) 쌍 공동 셔플 — 순서만 파괴
  x <- (dp / sp)[idx]; y <- (dv / sv)[idx]
  nn <- length(x)
  Px <- c(0, cumsum(x)[-nn]); Py <- c(0, cumsum(y)[-nn])
  (sum(Px * y) - sum(Py * x)) / 2
}
placebo_res <- list()
for (seed in 1:5) {
  set.seed(20260802 + seed)
  res <- vector("list", length(SIG))
  for (si in seq_along(SIG)) {
    sd_ <- SIG[si]
    i <- findInterval(sd_, CAL)
    s63 <- CAL[max(1L, i - 62L)]
    W <- D[PAN[Date == sd_, .(Ticker)], on = "Ticker"][Date >= s63 & Date <= sd_]
    f <- W[, .(A_pv_pl = levy_shuffled(Close, Vol, seed)), by = Ticker]
    f[, Date := sd_]
    res[[si]] <- f
  }
  PL <- rbindlist(res)
  plz <- cs_z(PL, "A_pv_pl", -1)
  btp <- canonical_screen_bt(plz, returns_dt, bench_dt, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
      run_id = sprintf("WT-D20260802_006_placebo%d", seed),
      strategy_id = sprintf("WT_D20260802_006_placebo%d", seed), diag_dual_basis = FALSE)
  dpl <- merge(plz, returns_dt, by = c("Date", "Ticker"))
  icp <- dpl[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date][, mean(ic, na.rm = TRUE)]
  placebo_res[[seed]] <- list(port_t = btp$portfolio_alpha_t_nw_lag3, rank_ic = icp)
  say("  placebo seed %d: PORT_t=%+.2f rank_IC=%+.4f", seed, btp$portfolio_alpha_t_nw_lag3, icp)
}

# ── 10. 반증: 후속 홀딩월 기관+외국인 순매수 (A6 investor flow) ──────────────
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
IV[, Date := as.Date(Date)]
IV <- IV[Ticker %chin% unique(PAN$Ticker)]
say("investor flow: %d행 (%s~%s) | Foreign 중앙값 크기 %.2e (단위 감사)",
    nrow(IV), as.character(min(IV$Date)), as.character(max(IV$Date)),
    IV[Foreign != 0, median(abs(Foreign))])
# 홀딩월 매핑: sig_date(t) → (t, next month-end] 의 flow 합
sig_next <- data.table(Date = SIG[-length(SIG)], hold_end = SIG[-1])
# 마지막 SIG는 MEND 다음달로
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
say("반증 검정: Q5−Q1 후속월 (외인+기관)/ADV·일 스프레드 평균 %+.5f, NW t=%+.2f (t<1 → 축적 주체 서사 기각)",
    fsp[, mean(spread, na.rm = TRUE)], fals_t)

# ── 11. 국면 조건부 귀속 (사후 slicing — C5 비발동) ──────────────────────────
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

# ── 12. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
saveRDS(list(bt = lapply(bt, slim), bt_lag1 = slim(bt_lag1),
             diag = lapply(DIAG, function(d) d[setdiff(names(d), "ic_series")]),
             ic_series_primary = DIAG[[PRIM]]$ic_series,
             sub_port_t = sub_port_t, orth = ORTH, placebo = placebo_res,
             falsification = list(mean_spread = fsp[, mean(spread, na.rm = TRUE)],
                                  t_nw = fals_t, n_months = nrow(fsp)),
             regime_tab = reg_tab, label_direction_ic = label_direction_ic,
             sidecar = list(before = sc_before[c("live", "live_with_ast")],
                            after  = sc_after[c("live", "live_with_ast")]),
             feats_primary = feats_primary),
        file.path(OUT, "wt006_eval_results.rds"))
write_parquet(STRATS[[PRIM]], file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt006_eval_results.rds + alpha_scores.parquet")
