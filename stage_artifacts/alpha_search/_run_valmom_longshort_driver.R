# =============================================================================
# _run_valmom_longshort_driver.R
#   alpha-search LONG-SHORT 진단 (결정적 실험, 순수 진단 — KR 공매도 제약상 실편입 불가)
# -----------------------------------------------------------------------------
# 목적: long-only top-decile valmom(Sharpe 0.825, Carhart4 t 1.63, OOS retention -0.06)이
#       OOS서 붕괴한 원인이 (a) long-only 제약(1st eigenmode 시장노출) 인지 (b) 알파 자체 부재 인지
#       를 분리. measurement-graduation §6 "KR long-only 수익률직교 구조적 불가" 직접 검증.
#
# 신호: fe_valmom.R(AMP2013 value(BM)+mom(12-1) z-combo, 이미 PIT-CLEAN 검증)을 그대로 재사용.
#       유니버스 K200∪KQ150, start_date 2005-01-01 (run_alpha_search 표준과 동일 필터).
#
# long-short 구성:
#   - 각 시그널 월말 t: combo Score 상위 decile = LONG, 하위 decile = SHORT (equal-weight).
#   - 보유 t -> t+1 월말. 월간 자산수익(월말 Close 종가-종가). 시장중립 = LONG - SHORT.
#   - 비용 15bps 양변(long leg + short leg 각각 turnover x 15bps).
#   - ★ 자체합성 금지: 각 leg 월간수익은 PerformanceAnalytics Return.portfolio()로 구성.
#     prod(1+r)/cumprod/(w*r).sum() 직접 가중합 금지. LS = 두 표준함수 시계열의 차감(허용).
#
# 측정: (1) 연율 Sharpe (table.AnnualizedReturns)  (2) Carhart4 alpha t (이제 시장중립 → 직교 알파 순수)
#       (3) OOS retention (IS<=2015 vs OOS>=2016 LS Sharpe)
# PIT: fe_valmom 신호 그대로(t-1 lag, 과거윈도우, 재무 PIT). 실현수익만 사용. lookahead 없음.
# =============================================================================
suppressWarnings(suppressMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
}))

PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", "G:/Quant_Module_Moltbot")
INFRA <- file.path(PROJ, "02_Infrastructure")
source(file.path(INFRA, "config.R"))
source(file.path(INFRA, "backtest_harness.R"))          # load_rawdata, summarise_perf
source(file.path(INFRA, "factor_portfolios.R"))          # load_kr_factor_returns, run_multifactor_regression

OUT_DIR <- file.path(PROJ, "stage_artifacts", "alpha_search")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

START_DATE <- as.Date("2005-01-01")
COMMISSION <- 0.0015   # 15bps one-way, 양변 적용
DECILE_FRAC <- 0.10

# ---- 1. Data ----
res <- load_rawdata(use_cache = TRUE)
RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT; rm(res); gc(verbose = FALSE)
if (!inherits(RAWDATA$Date, "Date")) RAWDATA[, Date := as.Date(Date)]
if (!inherits(BM_DT$Date, "Date"))   BM_DT[,   Date := as.Date(Date)]

# ---- 2. Signal: fe_valmom.R 재사용 (PIT-CLEAN 검증된 신호 로직 그대로) ----
#   fe_valmom.R은 RAWDATA(전역)와 load_month_factors를 사용해 FACTORS(Date,Ticker,Score)를 만든다.
source(file.path(INFRA, "alpha_search", "fe_valmom.R"))
stopifnot(exists("FACTORS"), is.data.table(FACTORS),
          all(c("Date","Ticker","Score") %in% names(FACTORS)))

# start_date + K200_KQ150 유니버스 필터 (run_alpha_search와 동일)
FACTORS <- FACTORS[Date >= START_DATE]
.me_uni <- unique(FACTORS$Date)
.mem <- unique(RAWDATA[Date %in% .me_uni & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)])
FACTORS <- merge(FACTORS, .mem, by = c("Date","Ticker"))
setorder(FACTORS, Date, Ticker)
sig_dates <- sort(unique(FACTORS$Date))
cat(sprintf("[LS] FACTORS rows=%d | signal months=%d | range=%s..%s\n",
            nrow(FACTORS), length(sig_dates), min(sig_dates), max(sig_dates)))

# ---- 3. 월말 Close 패널 (월간 자산 수익 계산용) ----
RAWDATA[, .ym := format(Date, "%Y-%m")]
.me_all <- RAWDATA[, .(Date = max(Date)), by = .ym]$Date     # 모든 월말일
me_panel <- RAWDATA[Date %in% .me_all, .(Date, Ticker, Close)]
RAWDATA[, .ym := NULL]
setkey(me_panel, Ticker, Date)
all_me <- sort(unique(me_panel$Date))

# 다음 월말일 lookup
next_me <- function(d) { nx <- all_me[all_me > d]; if (!length(nx)) return(NA) ; nx[1] }

# ---- 4. leg별 월간 포트폴리오 수익을 Return.portfolio로 구성 ----
#   각 시그널 월말 t에서 decile 멤버 = leg. equal-weight. 보유 t->t+1.
#   leg마다: 멤버 월간수익(t->t+1) + EW weight -> Return.portfolio (단일 리밸 윈도우, drift 무시 가능
#   = 1개월 보유라 weight drift 영향 미미하나 PerformanceAnalytics 표준 경유로 자체합성 회피).
#   여기서는 월간 단일기간이므로 leg 월간수익 = Return.portfolio(R=월간멤버수익행, w=EW) 1행.
#   turnover(이전월 대비 멤버 weight 변화)로 15bps 비용 차감.
make_leg_monthly <- function(side) {
  # side: "long" (top decile) or "short" (bottom decile)
  rows <- vector("list", length(sig_dates))
  prev_w <- NULL  # named vector ticker->weight (직전 leg 구성, turnover용)
  for (i in seq_along(sig_dates)) {
    d  <- sig_dates[i]
    nd <- next_me(d)
    if (is.na(nd)) next
    fd <- FACTORS[Date == d]
    if (nrow(fd) < 10L) next
    n_dec <- max(2L, as.integer(ceiling(nrow(fd) * DECILE_FRAC)))
    setorder(fd, -Score)
    sel <- if (side == "long") head(fd, n_dec) else tail(fd, n_dec)
    tks <- sel$Ticker
    # 멤버 월간수익 t->t+1 (월말 Close 종가-종가)
    p0 <- me_panel[.(tks, d),  Close]
    p1 <- me_panel[.(tks, nd), Close]
    ok <- is.finite(p0) & is.finite(p1) & p0 > 0
    tks <- tks[ok]; p0 <- p0[ok]; p1 <- p1[ok]
    if (length(tks) < 2L) next
    r_m <- p1 / p0 - 1                       # 멤버 월간 수익 (실현)
    w   <- rep(1 / length(tks), length(tks)) # equal-weight
    names(w) <- tks
    # Return.portfolio (PerformanceAnalytics 표준; 1기간 = EW 가중평균을 표준함수로)
    R_x <- xts(matrix(r_m, nrow = 1), order.by = nd); colnames(R_x) <- tks
    w_x <- xts(matrix(w,   nrow = 1), order.by = d);  colnames(w_x) <- tks
    leg_ret <- as.numeric(Return.portfolio(R = R_x, weights = w_x))
    # turnover 비용: 직전 leg 대비 weight L1 변화 (one-way) x 15bps
    cur_w <- w
    if (is.null(prev_w)) {
      to <- 1.0
    } else {
      allt <- union(names(prev_w), names(cur_w))
      pv <- setNames(rep(0, length(allt)), allt); pv[names(prev_w)] <- prev_w
      cv <- setNames(rep(0, length(allt)), allt); cv[names(cur_w)]  <- cur_w
      to <- sum(abs(cv - pv)) / 2   # one-way turnover (0~1)
    }
    cost <- to * COMMISSION
    prev_w <- cur_w
    rows[[i]] <- data.table(Date = nd, ret_gross = leg_ret,
                            ret_net = leg_ret - cost, turnover = to)
  }
  rbindlist(Filter(Negate(is.null), rows))
}

long_m  <- make_leg_monthly("long")
short_m <- make_leg_monthly("short")
setnames(long_m,  c("ret_gross","ret_net","turnover"), c("long_gross","long_net","long_to"))
setnames(short_m, c("ret_gross","ret_net","turnover"), c("short_gross","short_net","short_to"))
ls_m <- merge(long_m, short_m, by = "Date")
# LONG - SHORT = 시장중립 (두 표준함수 시계열의 차감 — 자체합성 아님)
ls_m[, ls_gross := long_gross - short_gross]
ls_m[, ls_net   := long_net   - short_net]
ls_m[, ym := format(Date, "%Y-%m")]
setorder(ls_m, Date)
cat(sprintf("[LS] months=%d | range=%s..%s | mean LS_net(m)=%.4f\n",
            nrow(ls_m), min(ls_m$ym), max(ls_m$ym), mean(ls_m$ls_net)))

# ---- 5. 측정 (1) 연율 Sharpe (table.AnnualizedReturns, PerformanceAnalytics 표준) ----
ls_xts_net   <- xts(ls_m$ls_net,   order.by = ls_m$Date)
ls_xts_gross <- xts(ls_m$ls_gross, order.by = ls_m$Date)
long_xts_net  <- xts(ls_m$long_net,  order.by = ls_m$Date)
short_xts_net <- xts(ls_m$short_net, order.by = ls_m$Date)

tar <- function(x) {
  t <- tryCatch(table.AnnualizedReturns(x, scale = 12, Rf = 0), error = function(e) NULL)
  if (is.null(t)) return(c(ann_ret = NA, ann_sd = NA, sharpe = NA))
  c(ann_ret = as.numeric(t[1,1]), ann_sd = as.numeric(t[2,1]), sharpe = as.numeric(t[3,1]))
}
ls_net_stats   <- tar(ls_xts_net)
ls_gross_stats <- tar(ls_xts_gross)
long_stats     <- tar(long_xts_net)
short_stats    <- tar(short_xts_net)
cat(sprintf("[LS] Sharpe net=%.3f gross=%.3f | long leg Sharpe=%.3f | short leg Sharpe=%.3f\n",
            ls_net_stats["sharpe"], ls_gross_stats["sharpe"], long_stats["sharpe"], short_stats["sharpe"]))

# ---- 6. 측정 (2) Carhart4 alpha t (시장중립 LS → 직교 알파 순수 측정) ----
#   run_multifactor_regression: strat_xts 월간 -> MKT/SMB/HML/WML(Carhart4) NW-HAC alpha t.
mf <- tryCatch(run_multifactor_regression(ls_xts_net, bm_xts = NULL,
                                          factor_dt = load_kr_factor_returns()),
               error = function(e) { cat("[LS] multifactor 실패:", conditionMessage(e), "\n"); NULL })
carhart4_t <- NA_real_; carhart4_alpha_ann <- NA_real_; ff3_t <- NA_real_; ff5_t <- NA_real_
if (!is.null(mf)) {
  if (!is.null(mf$Carhart4)) { carhart4_t <- mf$Carhart4$alpha_tstat; carhart4_alpha_ann <- mf$Carhart4$alpha * 12 * 100 }
  if (!is.null(mf$FF3))      ff3_t <- mf$FF3$alpha_tstat
  if (!is.null(mf$FF5))      ff5_t <- mf$FF5$alpha_tstat
  cat(sprintf("[LS] Carhart4 alpha=%.2f%%/yr t=%.3f | FF3 t=%.3f | FF5 t=%.3f\n",
              carhart4_alpha_ann, carhart4_t, ff3_t, ff5_t))
}

# ---- 7. 측정 (3) OOS retention (IS<=2015 vs OOS>=2016, LS Sharpe) ----
#   LS는 시장중립(벤치 없음) → raw LS Sharpe IS/OOS retention.
ann <- sqrt(12)
sharpe_of <- function(x) { x <- x[is.finite(x)]; s <- sd(x); if (!is.finite(s) || s <= 0) return(NA_real_); mean(x)/s*ann }
ls_m[, yr := as.integer(substr(ym,1,4))]
sr_is  <- sharpe_of(ls_m[yr <= 2015, ls_net])
sr_oos <- sharpe_of(ls_m[yr >= 2016, ls_net])
retention <- if (is.finite(sr_is) && abs(sr_is) > 1e-9) sr_oos / sr_is else NA_real_
n_is <- ls_m[yr <= 2015, .N]; n_oos <- ls_m[yr >= 2016, .N]
cat(sprintf("[LS] OOS retention: IS(<=2015,n=%d) Sharpe=%.3f | OOS(>=2016,n=%d) Sharpe=%.3f | retention=%.3f\n",
            n_is, sr_is, n_oos, sr_oos, retention))

# ---- 8. 저장 ----
fwrite(ls_m, file.path(OUT_DIR, "valmom_longshort_monthly.csv"))
out <- list(
  experiment = "valmom long-short diagnostic (market-neutral, KR short-sale infeasible — pure diagnostic)",
  paper = "Asness-Moskowitz-Pedersen 2013 value(BM)+momentum(12-1) z-combo, top/bottom decile EW",
  universe = "K200_KQ150", start_date = as.character(START_DATE),
  commission_oneway = COMMISSION, cost_both_legs = TRUE,
  n_months = nrow(ls_m), range = paste0(min(ls_m$ym), "..", max(ls_m$ym)),
  longshort_net = list(
    sharpe_annual = round(unname(ls_net_stats["sharpe"]),4),
    ann_ret_pct   = round(unname(ls_net_stats["ann_ret"])*100,3),
    ann_sd_pct    = round(unname(ls_net_stats["ann_sd"])*100,3)),
  longshort_gross_sharpe = round(unname(ls_gross_stats["sharpe"]),4),
  long_leg_sharpe_net  = round(unname(long_stats["sharpe"]),4),
  short_leg_sharpe_net = round(unname(short_stats["sharpe"]),4),
  carhart4_alpha_ann_pct = round(carhart4_alpha_ann,3),
  carhart4_alpha_t = round(carhart4_t,4),
  ff3_alpha_t = round(ff3_t,4),
  ff5_alpha_t = round(ff5_t,4),
  oos_retention = round(retention,4),
  oos_sharpe_IS = round(sr_is,4), oos_sharpe_OOS = round(sr_oos,4),
  oos_split = "IS<=2015 / OOS>=2016",
  longonly_baseline = list(sharpe = 0.825, carhart4_t = 1.63, oos_retention = -0.06),
  metric_type = "backtested_standard_functions",
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)
op <- file.path(OUT_DIR, "valmom_longshort_diagnostic.json")
write_json(out, op, auto_unbox = TRUE, pretty = TRUE, digits = 6)
cat(sprintf("\n[SAVED] %s\n", op))
cat(sprintf("[DONE] LS_net Sharpe=%.3f | Carhart4_t=%.3f | OOS_retention=%.3f\n",
            unname(ls_net_stats["sharpe"]), carhart4_t, retention))
