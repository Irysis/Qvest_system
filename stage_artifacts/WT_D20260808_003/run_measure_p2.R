# =============================================================================
# run_measure_p2.R — WT-D20260808_003 본 측정 (사전등록 preregistration.json 고정 후)
#   판정 형태 = 월-횡단면 FMB 기울기(전표본). paired 포트폴리오 형태는 P0 에서 폐기.
#   B3 격리 하 진행 — 채널 귀속 주장 금지.
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260808_003/run_measure_p2.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260808_003")
say <- function(fmt, ...) cat(sprintf(paste0("[m2] ", fmt, "\n"), ...))
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/required_effect_size.R")
PRE <- fromJSON(file.path(OUT, "preregistration.json"))
P0  <- readRDS(file.path(OUT, "p0_panels.rds"))
P1  <- readRDS(file.path(OUT, "prereg_p1.rds"))
R <- list(generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), metric_type = "canonical_screen / diag")

N <- P0$N; E <- P0$E; BETA <- P0$BETA
returns_dt <- P0$returns_dt; bench_dt <- P0$bench_dt; liq_dt <- P0$liq_dt
D <- P1$D
say("INPUT 판정패널 D nrow=%d 관측단위=MONTHLY(월×종목) n_month=%d 범위 %s~%s 월평균 %.1f종목",
    nrow(D), uniqueN(D$Date), min(D$Date), max(D$Date), D[, .N, by = Date][, mean(N)])
say("INPUT BETA nrow=%d n_month=%d · E nrow=%d · liq nrow=%d", nrow(BETA), uniqueN(BETA$Date), nrow(E), nrow(liq_dt))

nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
nw_se <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(NA_real_)
  f <- lm(x ~ 1); tryCatch(sqrt(sandwich::NeweyWest(f, lag = lag, prewhite = FALSE)[1,1]), error = function(e) NA_real_) }
nw_ci <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 12L) return(c(NA_real_, NA_real_))
  mean(x) + c(-1,1)*qt(0.975, df = length(x)-1L)*nw_se(x, lag) }
zs <- function(v) { s <- sd(v, na.rm = TRUE); if (!is.finite(s) || s <= 0) rep(NA_real_, length(v)) else (v - mean(v, na.rm = TRUE))/s }

# ── 1. MAX5 원변수 산출 (F2 통제 — 부모 라운드 결손 해소) ────────────────────
say("=== 1. MAX5 원변수 산출 (일간 RAWDATA → 월별 상위 5일 평균수익) ===")
MAX5_F <- file.path(OUT, "max5_panel.rds")
if (file.exists(MAX5_F)) { MAX5 <- readRDS(MAX5_F); say("  MAX5 캐시 재사용 nrow=%d n_month=%d", nrow(MAX5), uniqueN(MAX5$Date))
} else {
  RW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Close")))[, Date := as.Date(Date)]
  say("  RAWDATA(Close) nrow=%d 관측단위=DAILY n_day=%d %s~%s", nrow(RW), uniqueN(RW$Date), min(RW$Date), max(RW$Date))
  setorder(RW, Ticker, Date)
  RW[, dret := Close/shift(Close) - 1, by = Ticker]
  RW <- RW[is.finite(dret)][, ym := format(Date, "%Y-%m")]
  MAX5 <- RW[, .(max5 = mean(sort(dret, decreasing = TRUE)[seq_len(min(5L, .N))]), nday = .N), by = .(Ticker, ym)]
  MEND <- RW[, .(Date = max(Date)), by = ym]
  MAX5 <- merge(MAX5, MEND, by = "ym")[nday >= 10L][, .(Date, Ticker, max5)]
  rm(RW); gc(verbose = FALSE); saveRDS(MAX5, MAX5_F)
  say("  MAX5 산출 nrow=%d n_month=%d (월 내 상위5일 평균 일수익, 최소 10거래일)", nrow(MAX5), uniqueN(MAX5$Date))
}
VOL63 <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/WT_D20260802_009/tuned_panel.parquet")))[
  Factor_Name == "D03_EWMA", .(Date = as.Date(Date), Ticker, d03 = score)]
say("  vol63(D03_EWMA z) nrow=%d n_month=%d", nrow(VOL63), uniqueN(VOL63$Date))

X <- merge(D, MAX5, by = c("Date","Ticker"), all.x = TRUE)
X <- merge(X, VOL63, by = c("Date","Ticker"), all.x = TRUE)
X <- merge(X, BETA,  by = c("Date","Ticker"), all.x = TRUE)
X <- merge(X, P0$N[, .(Date, Ticker, lsz)], by = c("Date","Ticker"), all.x = TRUE)
say("  통제변수 결합 후: max5 결측 %.2f%% · d03 결측 %.2f%% · beta 결측 %.2f%%",
    100*mean(!is.finite(X$max5)), 100*mean(!is.finite(X$d03)), 100*mean(!is.finite(X$beta)))

# ── 2. FMB 기울기 (판정량) ───────────────────────────────────────────────────
say("=== 2. FMB 월별 횡단면 기울기 (act ~ z_std [+통제]) — 판정량 ===")
fmb <- function(dt, zcol, ctrls = character(0), tag = "") {
  need <- c("act", zcol, ctrls)
  d <- dt[complete.cases(dt[, ..need])]
  s <- d[, {
    y <- act; xz <- zs(get(zcol))
    if (sum(is.finite(xz)) < 30L || !is.finite(sd(xz))) .(b = NA_real_, n = .N) else {
      if (length(ctrls)) {
        C <- as.data.table(lapply(ctrls, function(cc) zs(get(cc)))); setnames(C, ctrls)
        ok <- is.finite(xz) & complete.cases(C)
        if (sum(ok) < 30L) .(b = NA_real_, n = sum(ok)) else
          .(b = unname(coef(lm(y[ok] ~ xz[ok] + as.matrix(C[ok])))[2]), n = sum(ok))
      } else .(b = unname(coef(lm(y ~ xz))[2]), n = .N)
    } }, by = Date][is.finite(b)]
  ci <- nw_ci(s$b)
  out <- list(tag = tag, z = zcol, controls = ctrls, n_month = nrow(s), n_avg = mean(s$n),
    slope_monthly = mean(s$b), slope_ann_pct = 100*12*mean(s$b), t_nw = nw_t(s$b),
    ci_ann_pct = 100*12*ci, series = s)
  say("  %-34s 기울기 연 %+.2f%%  NW t %+.2f  CI[%+.2f,%+.2f]  n=%d개월 (월평균 %.0f종목)",
      tag, out$slope_ann_pct, out$t_nw, out$ci_ann_pct[1], out$ci_ann_pct[2], out$n_month, out$n_avg)
  out
}
A1 <- fmb(X, "q01",   character(0),                "A1 raw Q01")
A2 <- fmb(X, "q01_n", character(0),                "A2 중립 Q01")
A3 <- fmb(X, "q01_n", c("max5","d03"),             "A3 중립 + MAX5·vol63 통제")
A3r<- fmb(X, "q01",   c("max5","d03"),             "A3' raw + MAX5·vol63 통제")
A4 <- fmb(X, "q01_n", c("beta"),                   "A4 중립 + β 통제")
A5 <- fmb(X, "q01_n", c("max5","d03","beta","lsz"),"A5 중립 + 전통제")
# paired 기울기 차 (중립 − raw), 같은 월 집합
pm <- merge(A1$series[, .(Date, b_raw = b)], A2$series[, .(Date, b_neu = b)], by = "Date")
pm[, d := b_neu - b_raw]
say("  paired 기울기 차(중립−raw): 연 %+.2f%%  NW t %+.2f  CI[%+.2f,%+.2f]  n=%d",
    100*12*mean(pm$d), nw_t(pm$d), 100*12*nw_ci(pm$d)[1], 100*12*nw_ci(pm$d)[2], nrow(pm))
R$fmb <- list(
  A1 = A1[setdiff(names(A1),"series")], A2 = A2[setdiff(names(A2),"series")],
  A3 = A3[setdiff(names(A3),"series")], A3_raw = A3r[setdiff(names(A3r),"series")],
  A4 = A4[setdiff(names(A4),"series")], A5 = A5[setdiff(names(A5),"series")],
  paired_neutral_minus_raw = list(ann_pct = 100*12*mean(pm$d), t_nw = nw_t(pm$d),
    ci_ann_pct = 100*12*nw_ci(pm$d), n = nrow(pm)))
# F2 판정 (잔존율)
f2_ret <- A3$slope_monthly / A2$slope_monthly
say("  ★F2 잔존율(중립 기울기: MAX5·vol63 통제 후/전) = %.3f (사전 문턱 0.30)", f2_ret)
R$F2 <- list(retention = f2_ret, threshold = 0.30, pass = is.finite(f2_ret) && f2_ret >= 0.30,
  raw_retention = A3r$slope_monthly / A1$slope_monthly,
  note = "MAX5 원변수 통제는 부모 라운드 결손(A4_vol_axis residual_gap) 해소")

# ── 3. 분위 배터리 + rank-IC + monotonicity (F4 · d1) ────────────────────────
say("=== 3. 분위 조건부 act + rank-IC + monotonicity (F4 · 판별절차 d1) ===")
quint <- function(dt, zcol, tag) {
  d <- dt[is.finite(get(zcol)) & is.finite(act)]
  s <- d[, { qr <- frank(get(zcol))/.N
    .(q1 = mean(act[qr <= 0.2]), q2 = mean(act[qr > 0.2 & qr <= 0.4]), q3 = mean(act[qr > 0.4 & qr <= 0.6]),
      q4 = mean(act[qr > 0.6 & qr <= 0.8]), q5 = mean(act[qr > 0.8]),
      q5m1 = mean(act[qr > 0.8]) - mean(act[qr <= 0.2]),
      q5m1_med = median(act[qr > 0.8]) - median(act[qr <= 0.2])) }, by = Date]
  ic <- d[, if (.N >= 10L && sd(get(zcol)) > 0 && sd(act) > 0) .(ic = cor(get(zcol), act, method = "spearman")) else .(ic = NA_real_), by = Date][is.finite(ic)]
  qm <- c(mean(s$q1), mean(s$q2), mean(s$q3), mean(s$q4), mean(s$q5))
  mono <- mean(diff(qm) > 0)
  out <- list(tag = tag, quintile_mean_ann_pct = 100*12*qm, monotonicity = mono,
    q5m1_ann_pct = 100*12*mean(s$q5m1), q5m1_t = nw_t(s$q5m1), q5m1_ci_ann = 100*12*nw_ci(s$q5m1),
    q5m1_median_ann_pct = 100*12*mean(s$q5m1_med), q5m1_median_t = nw_t(s$q5m1_med),
    rank_ic = mean(ic$ic), icir = mean(ic$ic)/sd(ic$ic), harvey_t_nw = nw_t(ic$ic), n_month = nrow(s),
    ic_series = ic, q_series = s)
  say("  %-12s 분위 연수익 [%s]  mono=%.2f | Q5−Q1 연 %+.2f%% (t %+.2f, CI[%+.2f,%+.2f]) 중앙값판 %+.2f%% (t %+.2f) | rank-IC %+.4f ICIR %.3f Harvey-t %+.2f",
      tag, paste(sprintf("%+.1f", 100*12*qm), collapse = " "), mono,
      out$q5m1_ann_pct, out$q5m1_t, out$q5m1_ci_ann[1], out$q5m1_ci_ann[2],
      out$q5m1_median_ann_pct, out$q5m1_median_t, out$rank_ic, out$icir, out$harvey_t_nw)
  out
}
Qr <- quint(X, "q01", "raw Q01"); Qn <- quint(X, "q01_n", "중립 Q01")
pq <- merge(Qr$q_series[, .(Date, a = q5m1)], Qn$q_series[, .(Date, b = q5m1)], by = "Date")[, d := b - a]
say("  ★d1 paired 스프레드 차(중립−raw): 연 %+.2f%%  NW t %+.2f  CI[%+.2f,%+.2f]",
    100*12*mean(pq$d), nw_t(pq$d), 100*12*nw_ci(pq$d)[1], 100*12*nw_ci(pq$d)[2])
R$quintile <- list(raw = Qr[setdiff(names(Qr), c("ic_series","q_series"))],
                   neutral = Qn[setdiff(names(Qn), c("ic_series","q_series"))],
                   d1_paired_spread_diff = list(ann_pct = 100*12*mean(pq$d), t_nw = nw_t(pq$d),
                     ci_ann_pct = 100*12*nw_ci(pq$d)))
R$F4 <- list(neutral_harvey_t = Qn$harvey_t_nw, neutral_monotonicity = Qn$monotonicity,
  transfer_negative_signature = is.finite(Qn$harvey_t_nw) && Qn$harvey_t_nw >= 3 && Qn$monotonicity < 0.5,
  raw_harvey_t = Qr$harvey_t_nw, raw_monotonicity = Qr$monotonicity)

# ── 4. B4 시기 프로파일 — 연속 시간추세 상호작용 (분할 금지) ─────────────────
say("=== 4. B4 시기 프로파일 (연속 시간추세 상호작용 — 분할 판정 금지) ===")
trend_reg <- function(s, vcol, tag) {
  d <- copy(as.data.table(s))[is.finite(get(vcol))][order(Date)]
  d[, yr := as.numeric(format(Date, "%Y")) + (as.numeric(format(Date, "%m")) - 1)/12]
  d[, yc := yr - mean(yr)]
  f <- lm(d[[vcol]] ~ d$yc)
  ct <- lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = 3L, prewhite = FALSE))
  out <- list(tag = tag, intercept = ct[1,1], intercept_t = ct[1,3],
    trend_per_year = ct[2,1], trend_t = ct[2,3], n = nrow(d),
    fitted_2010 = ct[1,1] + ct[2,1]*(2010 - mean(d$yr)),
    fitted_2018 = ct[1,1] + ct[2,1]*(2018 - mean(d$yr)),
    fitted_2024 = ct[1,1] + ct[2,1]*(2024 - mean(d$yr)))
  say("  %-26s 중심 수준 %+.5f (t %+.2f) · 연간 추세 %+.6f/yr (t %+.2f) | 적합값 2010 %+.5f / 2018 %+.5f / 2024 %+.5f",
      tag, out$intercept, out$intercept_t, out$trend_per_year, out$trend_t,
      out$fitted_2010, out$fitted_2018, out$fitted_2024)
  out
}
R$B4 <- list(
  neutral_ic_trend   = trend_reg(Qn$ic_series, "ic", "중립 Q01 rank-IC"),
  raw_ic_trend       = trend_reg(Qr$ic_series, "ic", "raw Q01 rank-IC"),
  neutral_slope_trend= trend_reg(A2$series, "b", "중립 Q01 FMB 기울기"),
  note = "분할 판정 아님. 적합값은 추세선 위 점이며 구간 평균이 아니다")

# ── 5. F3 — 개인 순매수 시그니처가 중립 z 에 부착되는가 ──────────────────────
say("=== 5. F3 — 개인 순매수 부착 (raw z vs 중립 z, log(Size) 통제) ===")
IND <- as.data.table(read_parquet(".cache/investor_stock/investor_individual.parquet",
        col_select = c("Date","Ticker","NetBuy")))[, Date := as.Date(Date)]
say("  INPUT investor_individual nrow=%d 관측단위=DAILY n_day=%d %s~%s", nrow(IND), uniqueN(IND$Date), min(IND$Date), max(IND$Date))
IND[, ym := format(Date, "%Y-%m")]
INM <- IND[, .(nb = sum(NetBuy, na.rm = TRUE)), by = .(ym, Ticker)]; rm(IND); gc(verbose = FALSE)
SIGM <- data.table(Date = sort(unique(X$Date)))[, ym := format(Date, "%Y-%m")]
INM <- merge(INM, SIGM, by = "ym")[, ym := NULL]
SZ <- P0$N[, .(Date, Ticker, Size, lsz)]
INM <- merge(INM, SZ, by = c("Date","Ticker"))[is.finite(Size) & Size > 0][, nb_norm := nb/Size]
f3 <- list()
for (zc in c("q01","q01_n")) {
  Dz <- merge(X[, .(Date, Ticker, z = get(zc))], INM[, .(Date, Ticker, nb_norm, lsz)], by = c("Date","Ticker"))
  s <- Dz[, { ok <- is.finite(z) & is.finite(nb_norm) & is.finite(lsz)
    if (sum(ok) >= 30L) { y <- zs(nb_norm[ok]); x1 <- zs(z[ok]); x2 <- zs(lsz[ok])
      if (all(is.finite(y)) && all(is.finite(x1)) && all(is.finite(x2)))
        .(b_ctl = unname(coef(lm(y ~ x1 + x2))[2]), b_raw = unname(coef(lm(y ~ x1))[2]), n = sum(ok))
      else .(b_ctl = NA_real_, b_raw = NA_real_, n = sum(ok))
    } else .(b_ctl = NA_real_, b_raw = NA_real_, n = sum(ok)) }, by = Date][is.finite(b_ctl)]
  f3[[zc]] <- list(b_raw = mean(s$b_raw), t_raw = nw_t(s$b_raw), b_size_ctl = mean(s$b_ctl),
    t_size_ctl = nw_t(s$b_ctl), ci = nw_ci(s$b_ctl), n_month = nrow(s))
  say("  %-6s: 기울기 %+.4f (t %+.2f) → log(Size) 통제 후 %+.4f (t %+.2f) CI[%+.4f,%+.4f] n=%d",
      zc, mean(s$b_raw), nw_t(s$b_raw), mean(s$b_ctl), nw_t(s$b_ctl), nw_ci(s$b_ctl)[1], nw_ci(s$b_ctl)[2], nrow(s))
}
R$F3 <- c(f3, list(note = "동시기 관측 — 예측 주장 아님(부모 라벨 승계)",
  attachment_ratio_neutral_over_raw = f3$q01_n$b_size_ctl / f3$q01$b_size_ctl))

# ── 6. canonical arm (schema 필수 필드 + d2 Δmean/ΔSE 분해) ─────────────────
say("=== 6. canonical_screen_bt arm (판정 권위 아님 — 저검정력 확정, CI 병기) ===")
run_arm <- function(scores, tag, dual = FALSE)
  canonical_screen_bt(scores, returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liq_dt, liq_min = 2e8, run_id = paste0("wt003_", tag), strategy_id = tag, diag_dual_basis = dual)
cs <- list()
cs$RAW25 <- run_arm(X[is.finite(q01),   .(Date, Ticker, score = q01)],   "Q01_RAW_TOP25", TRUE)
cs$NEU25 <- run_arm(X[is.finite(q01_n), .(Date, Ticker, score = q01_n)], "Q01_NEU_TOP25", TRUE)
cs$BASE  <- run_arm(E[, .(Date, Ticker, score)], "BASE_M01_TOP25", TRUE)
NQ <- X[is.finite(q01_n)][, qr := frank(q01_n)/.N, by = Date]
excl <- NQ[qr <= 0.2, .(Date, Ticker, drop_ = TRUE)]
SF <- merge(E[, .(Date, Ticker, score)], excl, by = c("Date","Ticker"), all.x = TRUE)[is.na(drop_)][, drop_ := NULL]
cs$FILT_NEU <- run_arm(SF, "BASE_x_NEUq20_EXCL", TRUE)
act_of <- function(x) { p <- as.data.table(x$period_returns); merge(p[, .(Date = as.Date(date), ret_net)], bench_dt, by = "Date")[, .(Date, a = ret_net - BM_Ret)] }
for (k in names(cs)) {
  a <- act_of(cs[[k]])
  say("  %-20s PORT_t %+.3f | 평균 active 연 %+.2f%% NW SE %.5f | net_sr %+.3f TO %.2f n=%d | EW-diag PORT_t %s",
      k, cs[[k]]$portfolio_alpha_t_nw_lag3, 100*12*mean(a$a), nw_se(a$a), cs[[k]]$net_sr,
      cs[[k]]$turnover_annual, cs[[k]]$n_months,
      if (!is.null(cs[[k]]$diag_ew_universe$portfolio_alpha_t_nw_lag3)) sprintf("%+.3f", cs[[k]]$diag_ew_universe$portfolio_alpha_t_nw_lag3) else "NA")
}
aR <- act_of(cs$RAW25); aN <- act_of(cs$NEU25)
d2 <- list(
  raw_mean_ann_pct = 100*12*mean(aR$a), neu_mean_ann_pct = 100*12*mean(aN$a),
  raw_nw_se = nw_se(aR$a), neu_nw_se = nw_se(aN$a),
  d_mean_ann_pct = 100*12*(mean(aN$a) - mean(aR$a)),
  d_se_pct = 100*(nw_se(aN$a)/nw_se(aR$a) - 1),
  raw_port_t = cs$RAW25$portfolio_alpha_t_nw_lag3, neu_port_t = cs$NEU25$portfolio_alpha_t_nw_lag3)
say("  ★d2 분해: Δmean 연 %+.2f%%p · ΔSE %+.1f%% · PORT_t %+.3f → %+.3f",
    d2$d_mean_ann_pct, d2$d_se_pct, d2$raw_port_t, d2$neu_port_t)
pd <- merge(aR[, .(Date, r = a)], aN[, .(Date, n = a)], by = "Date")[, d := n - r]
say("  paired(중립25−raw25) 연 %+.2f%% NW t %+.2f CI[%+.2f,%+.2f] — P0 에서 저검정력 확정(필요 연 4.00%%)",
    100*12*mean(pd$d), nw_t(pd$d), 100*12*nw_ci(pd$d)[1], 100*12*nw_ci(pd$d)[2])
R$canonical <- list(
  arms = lapply(cs, function(x) list(portfolio_alpha_t_nw_lag3 = x$portfolio_alpha_t_nw_lag3,
    portfolio_alpha_t_pvalue = x$portfolio_alpha_t_pvalue, net_sr = x$net_sr,
    alpha_annualized = x$alpha_annualized, turnover_annual = x$turnover_annual, n_months = x$n_months,
    information_ratio = x$information_ratio,
    diag_ew_universe_port_t = tryCatch(x$diag_ew_universe$portfolio_alpha_t_nw_lag3, error = function(e) NA_real_),
    diag_ew_universe_post2017_t = tryCatch(x$diag_ew_universe$post2017_t_nw_lag3, error = function(e) NA_real_))),
  d2_decomposition = d2,
  paired_neu_minus_raw = list(ann_pct = 100*12*mean(pd$d), t_nw = nw_t(pd$d), ci_ann_pct = 100*12*nw_ci(pd$d),
    n = nrow(pd), power_label = "P0 사전 확인에서 필요 연 4.00% 대비 함의 0.69% — 이 형태는 판정에 쓰지 않는다"))

# ── 7. 국면 상호작용 (advisory, 연속·CI만) ───────────────────────────────────
say("=== 7. 국면 상호작용 (advisory — 연속 조건화, 분할 금지, CI 보고) ===")
BMT <- copy(bench_dt)[order(Date)][, bm_trail12 := shift(frollsum(BM_Ret, 12L, align = "right"), 1L)]
INT <- INM[, .(ind_intensity = mean(abs(nb_norm), na.rm = TRUE)), by = Date][order(Date)][, ind_intensity := shift(ind_intensity, 1L)]
inter <- function(s, vcol, mod, mname, tag) {
  d <- merge(as.data.table(s)[, .(Date, v = get(vcol))], mod, by = "Date")
  setnames(d, mname, "m"); d <- d[is.finite(v) & is.finite(m)]
  d[, mz := zs(m)]
  f <- lm(v ~ mz, data = d); ct <- lmtest::coeftest(f, vcov. = sandwich::NeweyWest(f, lag = 3L, prewhite = FALSE))
  ci <- ct[2,1] + c(-1,1)*qt(0.975, nrow(d)-2)*ct[2,2]
  say("  %-30s 기울기/1sd 연 %+.2f%% (t %+.2f) CI[%+.2f,%+.2f] n=%d", tag, 100*12*ct[2,1], ct[2,3], 100*12*ci[1], 100*12*ci[2], nrow(d))
  list(tag = tag, slope_ann_pct_per_1sd = 100*12*ct[2,1], t_nw = ct[2,3], ci_ann_pct = 100*12*ci, n = nrow(d))
}
R$regime_advisory <- list(
  neutral_slope_x_bm_trail12 = inter(A2$series, "b", BMT[, .(Date, bm_trail12)], "bm_trail12", "중립 기울기 × 벤치 trailing12"),
  neutral_slope_x_ind_intensity = inter(A2$series, "b", INT, "ind_intensity", "중립 기울기 × 개인 강도"),
  crisis_sign_check = inter(pq[, .(Date, b = d)], "b", BMT[, .(Date, bm_trail12)], "bm_trail12", "d1 스프레드차 × 벤치 trailing12"),
  note = "ADVISORY — 승격 없음. 저검정력 사전등록, '효과 없음' 단정 금지")

# ── 8. 검정력 라벨 ───────────────────────────────────────────────────────────
say("=== 8. 검정력 라벨 (INCONCLUSIVE_UNDERPOWERED vs NEGATIVE_POWERED) ===")
lab <- function(t, monthly, n, sd_m, tag) {
  v <- verdict_with_power(observed_t = t, observed_monthly = monthly, n = n, sd_monthly = sd_m)
  say("  %-32s t=%+.2f 효과 연 %+.2f%% → %s", tag, t, 100*12*monthly, v$verdict)
  list(tag = tag, verdict = v$verdict, required_annual_pct = 100*v$required$required_annual)
}
R$power_labels <- list(
  A2_slope = lab(A2$t_nw, A2$slope_monthly, A2$n_month, P1$nulls$slope$sd_monthly, "A2 중립 기울기"),
  paired_slope = lab(nw_t(pm$d), mean(pm$d), nrow(pm), P1$paired_nulls$slope$sd_monthly, "paired 기울기 차"),
  d1_spread = lab(nw_t(pq$d), mean(pq$d), nrow(pq), P1$paired_nulls$q5q1$sd_monthly, "d1 스프레드 차"),
  neu_q5m1 = lab(Qn$q5m1_t, mean(Qn$q5m1_ann_pct)/1200, Qn$n_month, P1$nulls$q5q1$sd_monthly, "중립 Q5−Q1"),
  canonical_paired = lab(nw_t(pd$d), mean(pd$d), nrow(pd), 0.02289, "canonical paired(참고)"))

saveRDS(list(R = R, A1 = A1, A2 = A2, Qr = Qr, Qn = Qn, cs = cs, X = X), file.path(OUT, "measure_p2.rds"))
write_json(R, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = NA)
say("=== 측정 완료 → alpha_validation.json + measure_p2.rds ===")
