# =============================================================================
# run_wt122_measure.R — WT-D20260808_001 (FQ-122) 본측정
#   사전등록: stage_artifacts/WT_D20260808_001/preregistration.json (측정 전 고정)
#   (a) 타이브레이커 = F4 킬스위치로 사전 기각 → 측정하지 않음
#   P1 (주판정, 검정력 확보): 소비 구간 내 조건부 기울기 — 전표본 횡단면 FMB
#   P2 (부판정, 사전적 저검정력): (b) 하위분위 제외필터 paired 한계기여 — CI 보고
#   F2/F3: 기전 부수관측 (개인 순매수 집중 / β-drag)
#   국면: 연속 조건화 상호작용만 (분할 금지) · ADVISORY
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_001/run_wt122_measure.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260808_001")
IN9  <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
IN15 <- file.path(ROOT, "stage_artifacts/WT_D20260802_015")
say <- function(fmt, ...) cat(sprintf(paste0("[wt122] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/required_effect_size.R")

FILT <- c("D03_EWMA", "Q01_EB")
Q_PRIMARY <- 0.20
Q_SENS <- c(0.10, 0.30)

# ── 0. 입력 형태 실측 (규약) ─────────────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))
say("INPUT base_panel nrow=%d MONTHLY n_month=%d %s~%s", nrow(BASE), uniqueN(BASE$Date), min(BASE$Date), max(BASE$Date))
say("INPUT tuned_panel nrow=%d MONTHLY n_month=%d %s~%s", nrow(TUNED), uniqueN(TUNED$Date), min(TUNED$Date), max(TUNED$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))[, Date := as.Date(Date)]
say("INPUT RAWDATA nrow=%d DAILY n_day=%d %s~%s", nrow(RAW), uniqueN(RAW$Date), min(RAW$Date), max(RAW$Date))
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(verbose = FALSE)
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
SIZE <- RAWME[, .(Date, Ticker, Size)]

fwd <- readRDS(file.path(OUT, "fwd_cache.rds"))
returns_dt <- as.data.table(fwd$returns_dt)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- as.data.table(fwd$bench_dt)[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- as.data.table(fwd$liq_dt)[,     .(Date = as.Date(Date), Ticker, adv)]
say("INPUT fwd returns nrow=%d MONTHLY n_month=%d %s~%s", nrow(returns_dt), uniqueN(returns_dt$Date),
    min(returns_dt$Date), max(returns_dt$Date))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]),
           error = function(e) NA_real_)
}
nw_ci <- function(x, lag = 3L, level = 0.95) {
  x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  fit <- lm(x ~ 1)
  se <- tryCatch(sqrt(sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_)
  z <- qt(1 - (1 - level)/2, df = length(x) - 1L)
  mean(x) + c(-1, 1) * z * se
}
score_of <- function(f) {
  sc <- if (f %in% BASE$Factor_Name) BASE[Factor_Name == f, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == f, .(Date, Ticker, score = score)]
  merge(sc[!is.na(score)], UNIV, by = c("Date","Ticker"))
}

SC_M01 <- score_of("M01_PATHQ")
E <- merge(SC_M01, liq_dt, by = c("Date","Ticker"), all.x = TRUE)
E <- E[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(E, Date, -score)
E[, rk := seq_len(.N), by = Date]
E <- E[Date %in% returns_dt$Date]
FZ <- rbindlist(lapply(FILT, function(f) score_of(f)[, .(Date, Ticker, fz = score, F_ = f)]))
FZ <- merge(FZ, E[, .(Date, Ticker)], by = c("Date","Ticker"))    # eligible 한정
FZ[, q_rank := frank(fz) / .N, by = .(Date, F_)]
RB <- merge(returns_dt, bench_dt, by = "Date")[, .(Date, Ticker, act = Ret_1m - BM_Ret)]
say("eligible %d행 / %d개월 / 월평균 %.1f종목", nrow(E), uniqueN(E$Date), E[, .N, by = Date][, mean(N)])

RES <- list()

# ── 1. base arm + parity gate ────────────────────────────────────────────────
say("=== 1. base arm (M01 단일 top-25) + parity gate ===")
cs_base <- canonical_screen_bt(E[, .(Date, Ticker, score)], returns_dt, bench_dt,
             top_n = 25L, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
             run_id = "wt122_base", strategy_id = "BASE_M01_TOP25", diag_dual_basis = TRUE)
say("base canonical: PORT_t=%+.3f  IR=%+.3f  alpha_ann=%+.2f%%  net_sr=%+.3f  TO=%.2f  n=%d",
    cs_base$portfolio_alpha_t_nw_lag3, cs_base$information_ratio,
    100*cs_base$alpha_annualized, cs_base$net_sr, cs_base$turnover_annual, cs_base$n_months)

R15 <- readRDS(file.path(IN15, "wt015_results.rds"))
st <- as.data.table(R15$bt[["C3_SINGLE"]]$period_returns)
pm <- merge(as.data.table(cs_base$period_returns)[, .(date, mine = ret_net)],
            st[, .(date, stored = ret_net)], by = "date")
par_max <- max(abs(pm$mine - pm$stored))
say("PARITY(base vs WT-015 C3_SINGLE): max|diff| = %.3e (gate < 1e-8, n=%d)", par_max, nrow(pm))
stopifnot(par_max < 1e-8)
RES$parity <- list(max_abs_diff = par_max, n_overlap = nrow(pm), gate = "PASS")

# ── 2. P1 주판정 — 소비 구간 내 조건부 기울기 (전표본 횡단면 FMB) ────────────
say("=== 2. P1 (주판정) 소비 구간 내 조건부 기울기 — 전표본 횡단면 FMB ===")
fmb <- function(dt, xcol = "fz") {
  s <- dt[, {
    x <- get(xcol); y <- act; ok <- is.finite(x) & is.finite(y)
    if (sum(ok) >= 8L && sd(x[ok]) > 1e-8) {
      xz <- (x[ok] - mean(x[ok])) / sd(x[ok])
      .(b = unname(coef(lm(y[ok] ~ xz))[2]), n = sum(ok))
    } else .(b = NA_real_, n = sum(ok))
  }, by = Date][is.finite(b)]
  ci <- nw_ci(s$b)
  list(n_month = nrow(s), n_avg = mean(s$n), mean_b = mean(s$b), ann_pct = 100*12*mean(s$b),
       t_nw = nw_t(s$b), ci_ann_pct = 100*12*ci, series = s)
}
p1 <- list()
for (f in FILT) for (K in c(25L, 50L)) {
  D <- merge(E[rk <= K], FZ[F_ == f, .(Date, Ticker, fz)], by = c("Date","Ticker"))
  D <- merge(D, RB, by = c("Date","Ticker"))
  r <- fmb(D)
  key <- sprintf("%s_top%d", f, K)
  p1[[key]] <- r
  say("  %-16s 기울기 연 %+.2f%%/1sd  NW t=%+.2f  CI[%+.2f, %+.2f]  월평균 %.1f종목  n=%d",
      key, r$ann_pct, r$t_nw, r$ci_ann_pct[1], r$ci_ann_pct[2], r$n_avg, r$n_month)
}
# 대조: 전 eligible 구간 기울기 (소비 구간 밖 포함)
for (f in FILT) {
  D <- merge(E, FZ[F_ == f, .(Date, Ticker, fz)], by = c("Date","Ticker"))
  D <- merge(D, RB, by = c("Date","Ticker"))
  r <- fmb(D); p1[[sprintf("%s_all_eligible", f)]] <- r
  say("  %-16s 기울기 연 %+.2f%%/1sd  NW t=%+.2f  CI[%+.2f, %+.2f]  월평균 %.1f종목 [대조: 전구간]",
      sprintf("%s_ALL", f), r$ann_pct, r$t_nw, r$ci_ann_pct[1], r$ci_ann_pct[2], r$n_avg)
}
RES$P1 <- lapply(p1, function(r) r[setdiff(names(r), "series")])

# ── 3. P2 부판정 — (b) 제외필터 paired 한계기여 ──────────────────────────────
say("=== 3. P2 (부판정, 사전적 저검정력) 제외필터 paired 한계기여 ===")
run_filter_arm <- function(f, q) {
  ex <- FZ[F_ == f & q_rank <= q, .(Date, Ticker, drop_ = TRUE)]
  S <- merge(E[, .(Date, Ticker, score)], ex, by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(drop_)][, drop_ := NULL]
  cs <- canonical_screen_bt(S, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
         liq_dt = liq_dt, liq_min = 2e8,
         run_id = sprintf("wt122_%s_q%02.0f", f, q*100),
         strategy_id = sprintf("EXCL_%s_q%02.0f", f, q*100), diag_dual_basis = TRUE)
  d <- merge(as.data.table(cs_base$period_returns)[, .(date, b = ret_net)],
             as.data.table(cs$period_returns)[, .(date, tr = ret_net)], by = "date")
  d[, delta := tr - b]
  ci <- nw_ci(d$delta)
  list(cs = cs, delta = d,
       delta_ann_pct = 100*12*mean(d$delta), t_nw = nw_t(d$delta),
       ci_ann_pct = 100*12*ci, n_months = nrow(d),
       sd_monthly = sd(d$delta))
}
p2 <- list()
for (f in FILT) for (q in c(Q_PRIMARY, Q_SENS)) {
  a <- run_filter_arm(f, q)
  key <- sprintf("%s_q%02.0f", f, q*100)
  req <- required_effect(n = a$n_months, t_threshold = 2.0, sd_monthly = a$sd_monthly, design = "full")
  vw <- verdict_with_power(observed_t = a$t_nw, observed_monthly = mean(a$delta$delta),
                           n = a$n_months, sd_monthly = a$sd_monthly, design = "full")
  p2[[key]] <- list(q = q, factor = f, tag = if (q == Q_PRIMARY) "PRIMARY" else "SENSITIVITY_ONLY",
    delta_ann_pct = a$delta_ann_pct, t_nw = a$t_nw, ci_ann_pct = a$ci_ann_pct,
    n_months = a$n_months, delta_sd_monthly = a$sd_monthly,
    required_ann_pct_at_t2 = 100*req$required_annual,
    power_verdict = vw$verdict,
    arm_port_t = a$cs$portfolio_alpha_t_nw_lag3, base_port_t = cs_base$portfolio_alpha_t_nw_lag3,
    arm_turnover = a$cs$turnover_annual, base_turnover = cs_base$turnover_annual,
    arm_net_sr = a$cs$net_sr, base_net_sr = cs_base$net_sr,
    arm_alpha_ann_pct = 100*a$cs$alpha_annualized,
    arm_ew_uni_port_t = a$cs$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    base_ew_uni_port_t = cs_base$diag_ew_universe$portfolio_alpha_t_nw_lag3)
  say("  %-14s [%s] Δ연 %+.2f%%  NW t=%+.2f  CI[%+.2f, %+.2f]  필요치 %+.2f%%  → %s",
      key, p2[[key]]$tag, a$delta_ann_pct, a$t_nw, a$ci_ann_pct[1], a$ci_ann_pct[2],
      100*req$required_annual, vw$verdict)
  say("        PORT_t %+.3f→%+.3f | TO %.2f→%.2f | EW-uni PORT_t %+.3f→%+.3f",
      cs_base$portfolio_alpha_t_nw_lag3, a$cs$portfolio_alpha_t_nw_lag3,
      cs_base$turnover_annual, a$cs$turnover_annual,
      cs_base$diag_ew_universe$portfolio_alpha_t_nw_lag3,
      a$cs$diag_ew_universe$portfolio_alpha_t_nw_lag3)
  if (q == Q_PRIMARY) p2[[key]]$delta_series <- a$delta
}
RES$P2 <- lapply(p2, function(x) x[setdiff(names(x), "delta_series")])

# 항등 검증 (primary q, gross 기준)
say("--- 항등 검증: Δ_gross = (1/25)(Σ_added − Σ_dropped) ---")
ident <- list()
for (f in FILT) {
  ex <- FZ[F_ == f & q_rank <= Q_PRIMARY, .(Date, Ticker, drop_ = TRUE)]
  S <- merge(E[, .(Date, Ticker, score)], ex, by = c("Date","Ticker"), all.x = TRUE)
  Wt <- S[is.na(drop_)][order(Date, -score)][, .SD[seq_len(min(25L, .N))], by = Date][, .(Date, Ticker)]
  Wb <- E[rk <= 25L, .(Date, Ticker)]
  U <- merge(Wb[, .(Date, Ticker, inB = TRUE)], Wt[, .(Date, Ticker, inT = TRUE)],
             by = c("Date","Ticker"), all = TRUE)
  U[is.na(inB), inB := FALSE][is.na(inT), inT := FALSE]
  U <- merge(U, returns_dt, by = c("Date","Ticker"), all.x = TRUE)
  U[is.na(Ret_1m), Ret_1m := 0]
  idt <- U[, .(d_id = (sum(Ret_1m[inT & !inB]) - sum(Ret_1m[!inT & inB]))/25,
               k_swap = sum(inB & !inT)), by = Date]
  gb <- merge(Wb, returns_dt, by = c("Date","Ticker"), all.x = TRUE)[is.na(Ret_1m), Ret_1m := 0][
        , .(g = sum(Ret_1m)/25), by = Date]
  gt <- merge(Wt, returns_dt, by = c("Date","Ticker"), all.x = TRUE)[is.na(Ret_1m), Ret_1m := 0][
        , .(g = sum(Ret_1m)/25), by = Date]
  cmp <- merge(merge(gb[, .(Date, gb = g)], gt[, .(Date, gt = g)], by = "Date"), idt, by = "Date")
  err <- max(abs((cmp$gt - cmp$gb) - cmp$d_id))
  ident[[f]] <- list(max_err = err, k_swap_mean = mean(cmp$k_swap))
  say("  %s: max|err| = %.3e  (교체 평균 %.2f/25)", f, err, mean(cmp$k_swap))
}
RES$identity <- ident

# ── 4. F2 — 개인 순매수 집중 (기전 주체) ─────────────────────────────────────
say("=== 4. F2 — 개인 순매수 집중 (연속 조건화, 팩터별 분리) ===")
IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select = c("Date","Ticker","NetBuy")))[, Date := as.Date(Date)]
say("INPUT investor_individual nrow=%d DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date),
    min(IND$Date), max(IND$Date))
IND[, ym := format(Date, "%Y-%m")]
INM <- IND[, .(nb = sum(NetBuy, na.rm = TRUE)), by = .(ym, Ticker)]
rm(IND); gc(verbose = FALSE)
SIGM <- data.table(Date = sort(unique(E$Date)))[, ym := format(Date, "%Y-%m")]
INM <- merge(INM, SIGM, by = "ym")[, ym := NULL]
INM <- merge(INM, SIZE, by = c("Date","Ticker"))
INM <- INM[is.finite(Size) & Size > 0, .(Date, Ticker, nb_norm = nb / Size)]
say("  월간 개인 순매수 패널: %d행 / %d개월", nrow(INM), uniqueN(INM$Date))
f2 <- list()
for (f in FILT) {
  D <- merge(FZ[F_ == f, .(Date, Ticker, fz)], INM, by = c("Date","Ticker"))
  s <- D[, {
    x <- fz; y <- nb_norm; ok <- is.finite(x) & is.finite(y)
    if (sum(ok) >= 20L && sd(x[ok]) > 1e-8 && sd(y[ok]) > 1e-12) {
      xz <- (x[ok]-mean(x[ok]))/sd(x[ok]); yz <- (y[ok]-mean(y[ok]))/sd(y[ok])
      .(b = unname(coef(lm(yz ~ xz))[2]), n = sum(ok))
    } else .(b = NA_real_, n = sum(ok))
  }, by = Date][is.finite(b)]
  ci <- nw_ci(s$b)
  f2[[f]] <- list(mean_b = mean(s$b), t_nw = nw_t(s$b), ci = ci, n_month = nrow(s), n_avg = mean(s$n))
  say("  %s: 필터 z → 개인 순매수(정규화) 기울기 %+.4f sd/1sd  NW t=%+.2f  CI[%+.4f, %+.4f]  n=%d개월",
      f, mean(s$b), nw_t(s$b), ci[1], ci[2], nrow(s))
}
RES$F2 <- f2

# ── 5. F3 — β-drag (D03 최상위 분위 β) ───────────────────────────────────────
say("=== 5. F3 — 시장 β (trailing 60m, PIT) ===")
RM <- merge(returns_dt, bench_dt, by = "Date")
dts <- sort(unique(E$Date)); di <- setNames(seq_along(dts), as.character(dts))
beta_l <- vector("list", length(dts))
for (i in seq_along(dts)) {
  if (i <= 36L) next
  w <- RM[Date %in% dts[max(1L, i-60L):(i-1L)]]
  bb <- w[, {
    ok <- is.finite(Ret_1m) & is.finite(BM_Ret)
    if (sum(ok) >= 24L && var(BM_Ret[ok]) > 0) .(beta = cov(Ret_1m[ok], BM_Ret[ok])/var(BM_Ret[ok]), nb = sum(ok))
    else .(beta = NA_real_, nb = sum(ok))
  }, by = Ticker][is.finite(beta)]
  bb[, Date := dts[i]]
  beta_l[[i]] <- bb[, .(Date, Ticker, beta)]
}
BETA <- rbindlist(beta_l)
say("  β 패널: %d행 / %d개월 (trailing 60m, 최소 24관측, 당월 미포함 = PIT)", nrow(BETA), uniqueN(BETA$Date))
f3 <- list()
for (f in FILT) {
  D <- merge(FZ[F_ == f, .(Date, Ticker, fz, q_rank)], BETA, by = c("Date","Ticker"))
  s <- D[, .(b_top = median(beta[q_rank > 0.8]), b_med = median(beta),
             b_bot = median(beta[q_rank <= 0.2])), by = Date]
  s <- s[is.finite(b_top) & is.finite(b_med)]
  f3[[f]] <- list(top_minus_median = mean(s$b_top - s$b_med), t_nw = nw_t(s$b_top - s$b_med),
                  bot_minus_median = mean(s$b_bot - s$b_med), bot_t_nw = nw_t(s$b_bot - s$b_med),
                  beta_top_median = mean(s$b_top), beta_universe_median = mean(s$b_med),
                  n_month = nrow(s))
  say("  %s: 최상위분위 β %.3f vs 유니버스 중앙 %.3f (차 %+.3f, NW t=%+.2f) | 최하위분위 차 %+.3f (t=%+.2f)",
      f, mean(s$b_top), mean(s$b_med), mean(s$b_top - s$b_med), nw_t(s$b_top - s$b_med),
      mean(s$b_bot - s$b_med), nw_t(s$b_bot - s$b_med))
}
RES$F3 <- f3

# ── 6. 국면 — 연속 조건화 상호작용 (ADVISORY, 분할 금지) ─────────────────────
say("=== 6. 국면 상호작용 (연속 조건화, ADVISORY — CI만) ===")
BMT <- copy(bench_dt)[order(Date)]
BMT[, bm_trail12 := frollsum(BM_Ret, 12L, align = "right")]
BMT[, bm_trail12 := shift(bm_trail12, 1L)]      # PIT: 당월 미포함
IND_INT <- INM[, .(ind_intensity = mean(abs(nb_norm), na.rm = TRUE)), by = Date][order(Date)]
IND_INT[, ind_intensity := shift(ind_intensity, 1L)]
reg_res <- list()
for (f in FILT) {
  key <- sprintf("%s_q%02.0f", f, Q_PRIMARY*100)
  d <- p2[[key]]$delta_series
  if (is.null(d)) next
  dd <- merge(d[, .(Date = date, delta)], BMT[, .(Date, bm_trail12)], by = "Date")
  dd <- merge(dd, IND_INT, by = "Date", all.x = TRUE)
  out <- list()
  for (v in c("bm_trail12","ind_intensity")) {
    sub <- dd[is.finite(get(v)) & is.finite(delta)]
    if (nrow(sub) < 36L) next
    sub[, xz := (get(v) - mean(get(v))) / sd(get(v))]
    fit <- lm(delta ~ xz, data = sub)
    ct <- lmtest::coeftest(fit, vcov. = sandwich::NeweyWest(fit, lag = 3L, prewhite = FALSE))
    cf <- confint(fit)
    out[[v]] <- list(slope_ann_pct = 100*12*ct[2,1], t_nw = ct[2,3],
                     ci_ann_pct = 100*12*cf[2,], n = nrow(sub))
    say("  %s × %s: 상호작용 연 %+.2f%%/1sd  NW t=%+.2f  CI[%+.2f, %+.2f]  n=%d  [ADVISORY]",
        f, v, 100*12*ct[2,1], ct[2,3], 100*12*cf[2,1], 100*12*cf[2,2], nrow(sub))
  }
  reg_res[[f]] <- out
}
RES$regime_interaction <- reg_res
RES$regime_note <- "ADVISORY — 국면 분할 금지 mandate 준수(연속 조건화 상호작용만). 저검정력이므로 CI 보고이며 '국면에서 효과 없음' 단정 금지."

RES$base_arm <- list(port_t = cs_base$portfolio_alpha_t_nw_lag3, ir = cs_base$information_ratio,
  alpha_ann_pct = 100*cs_base$alpha_annualized, net_sr = cs_base$net_sr,
  turnover_annual = cs_base$turnover_annual, n_months = cs_base$n_months,
  ew_uni_port_t = cs_base$diag_ew_universe$portfolio_alpha_t_nw_lag3,
  selected_ret_coverage = cs_base$selected_ret_coverage)
saveRDS(RES, file.path(OUT, "wt122_results.rds"))
say("=== 본측정 완료 → wt122_results.rds ===")
