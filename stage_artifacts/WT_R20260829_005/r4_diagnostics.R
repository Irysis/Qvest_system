# ── R4 — 위험분해 / 꼬리 / 스트레스 / 크라우딩 / 집중 / 레짐상관
#  경계: alpha 재해석 없음. 비중 결정 없음. 아래 EW 기준바스켓은 **진단 기준선**이며
#        optimizer 의 비중 권고가 아니다(risk_summary.diagnostic_basis 에 명시).
#  PIT : 모든 자료 sig_date(2026-07-31) 이하. 실현수익 계열은 holding_ym <= 2026-07 까지만.
suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics)
}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
## ★인프라 결손: tail_risk_engine.R 는 fExtremes 를 hard-require 하는데 본 환경에 미설치.
##   공유 인프라를 수정할 권한이 없으므로(역할/경계) 동일 정의를 evir(설치됨) 기반으로
##   국소 재구현한다. 정의는 Pfaff(2016) Ch.6/7/12 및 tail_risk_engine.R 원문과 동형.
##   -> challenge_flags 에 INFRA-1 로 등재.
suppressWarnings(suppressMessages(library(evir)))
compute_evt_var <- function(r, p = 0.99, threshold_q = 0.95, min_tail_n = 60L) {
  r <- r[is.finite(r)]; losses <- -r; n <- length(losses)
  u <- as.numeric(quantile(losses, threshold_q)); ex <- losses[losses > u]
  if (length(ex) < min_tail_n) {
    threshold_q <- max(0.85, threshold_q - 0.05)
    u <- as.numeric(quantile(losses, threshold_q)); ex <- losses[losses > u]
  }
  if (length(ex) < 20L) {
    v <- as.numeric(quantile(losses, p))
    return(list(var_evt = v, es_evt = mean(losses[losses > v]), shape_xi = NA_real_,
                scale_beta = NA_real_, threshold_u = u, n_exceedances = length(ex),
                method = "empirical_fallback"))
  }
  fit <- tryCatch(evir::gpd(losses, threshold = u), error = function(e) NULL)
  if (is.null(fit)) {
    v <- as.numeric(quantile(losses, p))
    return(list(var_evt = v, es_evt = mean(losses[losses > v]), shape_xi = NA_real_,
                scale_beta = NA_real_, threshold_u = u, n_exceedances = length(ex),
                method = "empirical_fallback"))
  }
  xi <- as.numeric(fit$par.ests["xi"]); beta <- as.numeric(fit$par.ests["beta"])
  Nu <- length(ex)
  var_e <- u + (beta / xi) * (((n / Nu) * (1 - p))^(-xi) - 1)
  es_e  <- if (xi < 1) (var_e + beta - xi * u) / (1 - xi) else NA_real_
  list(var_evt = var_e, es_evt = es_e, shape_xi = xi, scale_beta = beta,
       threshold_u = u, n_exceedances = Nu, method = "gpd_mle_evir")
}
compute_cf_var <- function(r, p = 0.99) {
  r <- r[is.finite(r)]; mu <- mean(r); s <- sd(r)
  S <- mean((r-mu)^3)/s^3; K <- mean((r-mu)^4)/s^4 - 3
  z <- qnorm(1 - p)
  zcf <- z + (z^2-1)*S/6 + (z^3-3*z)*K/24 - (2*z^3-5*z)*S^2/36
  list(var_cf = -(mu + zcf*s), skew = S, exkurt = K, method = "cornish_fisher")
}
compute_cdar <- function(nav, alpha = 0.95) {
  nav <- nav[is.finite(nav)]; rmax <- cummax(nav); dd <- -((nav - rmax)/rmax)
  vd <- as.numeric(quantile(dd, alpha))
  list(max_dd = max(dd), avg_dd = mean(dd), var_dd = vd, cdar = mean(dd[dd >= vd]))
}
source(file.path(ROOT, "02_Infrastructure/factor_db/crowding_score_per_factor.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
set.seed(20260829L)

R1 <- readRDS(file.path(OUT, "risk_r1.rds"))
R2 <- readRDS(file.path(OUT, "risk_r2.rds"))
R3 <- readRDS(file.path(OUT, "risk_r3.rds"))
SIG <- R1$SIG; B <- R2$B; ASSETS <- R2$ASSETS; Om <- R2$Omega_d; fac_names <- R2$fac_names
SECLV <- R2$SECLV; STY <- R2$STY; ex_now <- R2$ex_now
Sig_d <- R3$Sigma_d; dvec <- R3$dvec_final
D <- R1$D; FR <- R2$FR; win_d <- R2$win_d

## ── 기준바스켓 (진단 전용) — alpha top-25 균등 ──────────────────────────────
ap <- fromJSON(file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json"),
               simplifyVector = TRUE)
av <- unlist(ap$alpha_vector)
top25 <- names(sort(av, decreasing = TRUE))[1:25]
top25 <- top25[top25 %in% ASSETS]
w <- setNames(rep(1/length(top25), length(top25)), top25)
cat(sprintf("[R4] reference basket (DIAGNOSTIC ONLY): %d names, EW\n", length(top25)))

wv <- setNames(rep(0, length(ASSETS)), ASSETS); wv[names(w)] <- w
tot_var_d <- as.numeric(t(wv) %*% Sig_d %*% wv)
x <- as.numeric(t(B) %*% wv); names(x) <- fac_names
fac_var_d <- as.numeric(t(x) %*% Om %*% x)
spec_var_d <- sum(wv^2 * dvec[ASSETS])
ann <- function(v) sqrt(v * 252)
cat(sprintf("[R4] basket vol ann = %.2f%% | factor %.1f%% / specific %.1f%% of variance\n",
            100*ann(tot_var_d), 100*fac_var_d/tot_var_d, 100*spec_var_d/tot_var_d))

## 팩터별 분산기여 (x_k * (Omega x)_k / total_var)
Omx <- as.numeric(Om %*% x)
contrib <- x * Omx / tot_var_d
names(contrib) <- fac_names
sec_idx <- grep("^SEC_", fac_names)
sty_idx <- match(STY, fac_names)
grp <- c(MKT = contrib["MKT"],
         SECTOR_TOTAL = sum(contrib[sec_idx]),
         setNames(contrib[sty_idx], STY),
         SPECIFIC = spec_var_d / tot_var_d)
grp <- sort(grp, decreasing = TRUE)
print(round(100*grp, 2))
sec_contrib <- sort(contrib[sec_idx], decreasing = TRUE)
cat("[R4] top sectors:\n"); print(round(100*head(sec_contrib, 5), 2))

## ── 집중 진단 ───────────────────────────────────────────────────────────────
exb <- ex_now[Ticker %in% top25]
hhi_name <- sum(w^2); n_eff_name <- 1/hhi_name
secw <- exb[, .(sw = sum(w[Ticker])), by = Sector]
hhi_sec <- sum(secw$sw^2); n_eff_sec <- 1/hhi_sec
cat(sprintf("[R4] HHI name=%.4f (n_eff %.1f) | HHI sector=%.4f (n_eff %.1f, %d sectors)\n",
            hhi_name, n_eff_name, hhi_sec, n_eff_sec, nrow(secw)))
print(secw[order(-sw)][1:min(6,.N)])

## cap-tier (canonical_screen_bt 정의: size rank<=10 MEGA / <=30 MID / else OTHER)
snap_size <- R1$SEC  # placeholder
SZ <- ex_now[, .(Ticker, Size)]
SZall <- unique(D[Date == SIG, .(Ticker, Size)])[is.finite(Size)]
setorder(SZall, -Size); SZall[, crank := .I]
SZall[, tier := fifelse(crank <= 10L, "MEGA", fifelse(crank <= 30L, "MID", "OTHER"))]
tb <- merge(data.table(Ticker = names(w), w = as.numeric(w)), SZall[, .(Ticker, tier)],
            by = "Ticker", all.x = TRUE)
tb[is.na(tier), tier := "UNRANKED"]
tier_w <- tb[, .(w = sum(w)), by = tier]
## tier 별 active risk share (분산기여)
Sw <- as.numeric(Sig_d[names(w), names(w)] %*% w)
mrc <- setNames(w * Sw / tot_var_d, names(w))
tb[, rc := mrc[Ticker]]
tier_rc <- tb[, .(risk_share = sum(rc), w = sum(w), n = .N), by = tier]
print(tier_rc)
## ★dual-basis (v8.3.1) — OTHER 92.7% 가 신호의 소형주 편향인지 유니버스 구조인지 분리
##   basis A: EW-universe (340종 균등)  basis B: cap-w universe
tb_u <- merge(data.table(Ticker = ASSETS), SZall[, .(Ticker, tier, Size)], by = "Ticker", all.x = TRUE)
tb_u[is.na(tier), tier := "UNRANKED"]
tb_u[, w_ew := 1/.N]
tb_u[, w_cw := Size / sum(Size, na.rm = TRUE)]
base_tier <- tb_u[, .(ew_universe = sum(w_ew), capw_universe = sum(w_cw, na.rm = TRUE)), by = tier]
DUAL <- merge(base_tier, tier_w, by = "tier", all = TRUE)
setnames(DUAL, "w", "basket_top25_ew")
DUAL[is.na(DUAL)] <- 0
DUAL <- merge(DUAL, tier_rc[, .(tier, basket_risk_share = risk_share)], by = "tier", all.x = TRUE)
DUAL[, divergence_vs_ew_universe := basket_top25_ew - ew_universe]
print(DUAL)

## ── 유동성 ─────────────────────────────────────────────────────────────────
liq <- R1$liq_dt[Date == SIG & Ticker %in% top25, .(Ticker, adv)]
liq <- merge(data.table(Ticker = names(w), w = as.numeric(w)), liq, by = "Ticker", all.x = TRUE)
BOOK <- 1e10   # 100억원 가정 book (용량 진단 기준선, 비중 권고 아님)
liq[, notional := w * BOOK]
liq[, days_to_liq := notional / pmax(0.10 * adv, 1)]   # 10% 참여율
setorder(liq, -days_to_liq)
cat(sprintf("[R4] liquidity @ book 100억: median DTL=%.2fd  p90=%.2fd  max=%.2fd  (10%% ADV 참여)\n",
            median(liq$days_to_liq, na.rm=TRUE), quantile(liq$days_to_liq, .9, na.rm=TRUE),
            max(liq$days_to_liq, na.rm=TRUE)))
print(head(liq[, .(Ticker, adv, days_to_liq)], 5))

## ── 꼬리위험 ───────────────────────────────────────────────────────────────
PR <- fread(file.path(OUT, "period_returns_production.csv"))
PR[, holding_ym := as.character(holding_ym)]
PR_pit <- PR[holding_ym <= "2026-07"]     # ★sig_date 기준 실현된 달만 (2026-08 은 미실현)
cat(sprintf("[R4] realized monthly series: %d -> %d months after PIT cut (drop holding_ym 2026-08)\n",
            nrow(PR), nrow(PR_pit)))
rm_ <- PR_pit$ret_net; ra_ <- PR_pit$active_net; rb_ <- PR_pit$benchmark_ret

emp <- function(r, q) list(var = as.numeric(-quantile(r, q)), es = -mean(r[r <= quantile(r, q)]))
tail_m <- list(
  n_months = nrow(PR_pit),
  empirical = list(
    var_95 = emp(rm_, 0.05)$var, es_95 = emp(rm_, 0.05)$es,
    var_99 = emp(rm_, 0.01)$var, es_99 = emp(rm_, 0.01)$es,
    active_var_95 = emp(ra_, 0.05)$var, active_es_95 = emp(ra_, 0.05)$es,
    bench_var_95 = emp(rb_, 0.05)$var, bench_es_95 = emp(rb_, 0.05)$es),
  skew = as.numeric(PerformanceAnalytics::skewness(rm_, method = "moment")),
  kurt = as.numeric(PerformanceAnalytics::kurtosis(rm_, method = "moment")))
ev95 <- tryCatch(suppressWarnings(compute_evt_var(rm_, p = 0.95, threshold_q = 0.90, min_tail_n = 20L)), error=function(e) NULL)
ev99 <- tryCatch(suppressWarnings(compute_evt_var(rm_, p = 0.99, threshold_q = 0.90, min_tail_n = 20L)), error=function(e) NULL)
cf99 <- tryCatch(compute_cf_var(rm_, p = 0.99), error = function(e) NULL)
nav <- cumprod(1 + rm_)
cd <- tryCatch(compute_cdar(nav, alpha = 0.95), error = function(e) NULL)
hill <- function(r, k_frac = 0.15) {
  L <- sort(-r[r < 0], decreasing = TRUE)
  k <- max(10L, floor(length(L) * k_frac)); k <- min(k, length(L) - 1L)
  if (k < 10L) return(list(alpha = NA_real_, k = k))
  list(alpha = 1 / mean(log(L[1:k]) - log(L[k + 1])), k = k)
}
h_m <- hill(rm_); h_b <- hill(rb_)
cat(sprintf("[R4] monthly tail: emp ES95=%.3f ES99=%.3f | EVT VaR95=%.3f ES95=%.3f xi=%s | Hill a=%.2f (bench %.2f)\n",
            tail_m$empirical$es_95, tail_m$empirical$es_99,
            if(!is.null(ev95)) ev95$var_evt else NA, if(!is.null(ev95)) ev95$es_evt else NA,
            if(!is.null(ev95)) sprintf("%.3f", ev95$shape_xi) else "NA", h_m$alpha, h_b$alpha))

## 현행 바스켓 일별 꼬리 (역투영 — 구성 아티팩트 경고 동반)
Db <- D[Date %in% win_d & Ticker %in% top25, .(Date, Ticker, Ret)]
Wd <- dcast(Db, Date ~ Ticker, value.var = "Ret"); Wd[, Date := NULL]; Wd <- as.matrix(Wd)
Wd[!is.finite(Wd)] <- NA
rb_daily <- rowMeans(Wd, na.rm = TRUE)
cov_daily <- mean(rowMeans(is.finite(Wd)))
ev_d <- tryCatch(suppressWarnings(compute_evt_var(rb_daily, p = 0.99, threshold_q = 0.95, min_tail_n = 30L)),
                 error = function(e) NULL)
h_d <- hill(rb_daily)
cat(sprintf("[R4] current-basket daily tail (n=%d, name-coverage %.1f%%): EVT VaR99=%.4f ES99=%.4f xi=%s Hill a=%.2f\n",
            length(rb_daily), 100*cov_daily,
            if(!is.null(ev_d)) ev_d$var_evt else NA, if(!is.null(ev_d)) ev_d$es_evt else NA,
            if(!is.null(ev_d)) sprintf("%.3f", ev_d$shape_xi) else "NA", h_d$alpha))

## ── 스트레스 (A) 실현 에피소드 ──────────────────────────────────────────────
stress_def <- list(
  list(name="Terror_9_11", s="2001-09", e="2001-12"), list(name="GFC", s="2007-10", e="2009-03"),
  list(name="Euro_Debt", s="2011-07", e="2011-12"), list(name="China_Shock", s="2015-06", e="2016-02"),
  list(name="US_China_Trade", s="2018-03", e="2018-12"), list(name="COVID", s="2020-01", e="2020-06"),
  list(name="Rate_Hike", s="2022-01", e="2022-12"), list(name="Iran_War", s="2026-02", e="2026-04"))
srow <- list()
for (sp in stress_def) {
  sub <- PR_pit[holding_ym >= sp$s & holding_ym <= sp$e]
  n_exp <- length(seq(as.Date(paste0(sp$s,"-01")), as.Date(paste0(sp$e,"-01")), by="month"))
  cov <- nrow(sub) / n_exp
  srow[[length(srow)+1L]] <- data.table(
    scenario = sp$name, months = nrow(sub), months_expected = n_exp, coverage = cov,
    strat_cum = if (nrow(sub)) prod(1+sub$ret_net)-1 else NA_real_,
    bench_cum = if (nrow(sub)) prod(1+sub$benchmark_ret)-1 else NA_real_,
    active_cum = if (nrow(sub)) prod(1+sub$ret_net)-prod(1+sub$benchmark_ret) else NA_real_,
    worst_month = if (nrow(sub)) min(sub$ret_net) else NA_real_,
    reliability = fifelse(cov >= 0.85, "OK", "UNRELIABLE"))
}
STR <- rbindlist(srow); print(STR)

## ── 스트레스 (B) 조건부 팩터 충격 (현행 노출 x Omega) ───────────────────────
##  E[f | f_k = shock] = Omega[,k]/Omega[k,k] * shock  (다변량 정규 조건부 평균)
Fm <- as.matrix(FR[Date %in% win_d, ..fac_names])
f_mo_sd <- apply(Fm, 2, sd) * sqrt(21)     # 월간 환산 표준편차
## 조건부 평균 E[f | f_k = s] = Omega[,k]/Omega[k,k] * s.  조건부 베타는 척도불변이므로
## 일별 Omega 로 구한 베타에 **월 규모 1회성 충격 s** 를 그대로 태운다(시간 스케일링 없음).
shock_of <- function(k, shock) as.numeric(sum(x * (Om[, k] / Om[k, k]) * shock))
scen <- list(
  market_down_5              = shock_of("MKT",   -0.05),
  market_down_10             = shock_of("MKT",   -0.10),
  value_crash_2sd            = shock_of("X_VAL", -2 * f_mo_sd["X_VAL"]),
  momentum_reversal_2sd      = shock_of("X_MOM", -2 * f_mo_sd["X_MOM"]),
  size_rotation_to_large_2sd = shock_of("X_SIZE", 2 * f_mo_sd["X_SIZE"]),
  size_rotation_to_small_2sd = shock_of("X_SIZE",-2 * f_mo_sd["X_SIZE"]),
  liquidity_crunch_2sd       = shock_of("X_LIQ",  2 * f_mo_sd["X_LIQ"]),
  highvol_selloff_2sd        = shock_of("X_RVOL",-2 * f_mo_sd["X_RVOL"]))
print(round(unlist(scen), 4))
## 경험적 역사 재현 — 현행 노출 x 실제 월별 팩터 실현치 (모수가정 없음)
FRm <- copy(FR); FRm[, ym := format(Date, "%Y-%m")]
FMO <- FRm[, lapply(.SD, sum), by = ym, .SDcols = fac_names]      # 일별 로그근사 합 = 월간
pl_hist <- data.table(ym = FMO$ym, pnl = as.numeric(as.matrix(FMO[, ..fac_names]) %*% x))
setorder(pl_hist, pnl)
cat("[R4] historical replay (current exposures x realized monthly factor returns) worst 5:\n")
print(head(pl_hist, 5)); cat("  best 2:\n"); print(tail(pl_hist, 2))
cat(sprintf("[R4] basket factor exposures: MKT=%.3f SIZE=%.3f VAL=%.3f MOM=%.3f LIQ=%.3f RVOL=%.3f BETA=%.3f\n",
            x["MKT"], x["X_SIZE"], x["X_VAL"], x["X_MOM"], x["X_LIQ"], x["X_RVOL"], x["X_BETA"]))

## ── 크라우딩 (Acadian 2026) ─────────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/backtest_harness.R"))
rl <- load_rawdata(use_cache = TRUE); RD <- rl$RAWDATA; rm(rl)
RD[, Date := as.Date(Date)]
RD <- RD[Date <= SIG & Date >= SIG - 100]        # 스냅샷 창 (rd_last 가 실제 최근값이 되도록)
bench_t <- R1$mem[Date == SIG, Ticker]
crowd_at <- function(d_sig, RDx) {
  exq <- R1$EXPO[Date == d_sig]
  if (!nrow(exq)) return(NULL)
  sc <- ap$alpha_vector
  fe <- rbindlist(list(
    data.table(Ticker = exq$Ticker, factor_name = "Value_V01_BM",  exposure = exq$X_VAL),
    data.table(Ticker = exq$Ticker, factor_name = "Momentum_6_1",  exposure = exq$X_MOM),
    data.table(Ticker = exq$Ticker, factor_name = "Combined_rank_avg",
               exposure = 0.5*frank(exq$X_VAL)/nrow(exq) + 0.5*frank(exq$X_MOM)/nrow(exq))))
  crowding_score_per_factor(fe, d_sig, RDx, benchmark_tickers = bench_t, top_n = 25L)
}
CR <- crowd_at(SIG, RD)
print(CR)
d_3m <- R1$ME_win[length(R1$ME_win) - 3L]
RD3 <- rl2 <- NULL
RDall <- load_rawdata(use_cache = TRUE)$RAWDATA; RDall[, Date := as.Date(Date)]
CR3 <- crowd_at(d_3m, RDall[Date <= d_3m & Date >= d_3m - 100])
rm(RDall); gc(verbose = FALSE)
CRd <- merge(CR[, .(factor_name, crowding_score)], CR3[, .(factor_name, cs_3m_ago = crowding_score)],
             by = "factor_name", all.x = TRUE)
CRd[, delta_3m := crowding_score - cs_3m_ago]
print(CRd)

## ── 레짐 상관 ───────────────────────────────────────────────────────────────
MRET <- R1$MRET; BMM <- R1$BMM; mem <- R1$mem
MRET <- MRET[Date <= as.Date("2026-06-30")]      # holding month <= 2026-07 (PIT)
BMM  <- BMM[Date <= as.Date("2026-06-30")]
setorder(BMM, Date)
BMM[, r12 := frollapply(BM_Ret, 12, function(z) prod(1+z)-1, align="right")]
BMM[, v12 := frollapply(BM_Ret, 12, sd, align="right")]
BMM[, v12_med := cummedian <- sapply(seq_len(.N), function(i) if (i < 24) NA_real_ else median(v12[1:i], na.rm=TRUE))]
BMM[, regime_dir := fifelse(is.na(r12), NA_character_, fifelse(r12 > 0, "BULL", "BEAR"))]
BMM[, regime_vol := fifelse(is.na(v12)|is.na(v12_med), NA_character_, fifelse(v12 > v12_med, "HIGHVOL", "LOWVOL"))]
crisis_m <- unlist(lapply(stress_def, function(sp)
  format(seq(as.Date(paste0(sp$s,"-01")), as.Date(paste0(sp$e,"-01")), by="month"), "%Y-%m")))
BMM[, hym := format(as.Date(Date) + 15, "%Y-%m")]   # signal month label -> holding month
BMM[, regime_crisis := fifelse(hym %in% crisis_m, "CRISIS", "NORMAL")]

WM <- dcast(MRET, Date ~ Ticker, value.var = "Ret_1m")
wd <- WM$Date; WM[, Date := NULL]; WMm <- as.matrix(WM); rownames(WMm) <- as.character(wd)
## ★구성 통제: 레짐별로 전 기간을 pooling 하면 이름 집합이 레짐마다 달라져(실측 101 vs 210)
##   상관 차이가 국면이 아니라 구성에서 온다. 대신 **후행 24개월 창**마다 그 창 안에서
##   완전관측인 종목만으로 평균 쌍상관 rho_t 를 구하고, rho_t 를 그 달의 국면에 배정한다.
##   각 rho_t 는 자기 창의 이름집합으로 내부 정합 · 후행창이므로 PIT(C1) 정합.
ROLL <- 24L
roll_rows <- list()
for (i in ROLL:length(wd)) {
  rows <- wd[(i - ROLL + 1L):i]
  M <- WMm[as.character(rows), , drop = FALSE]
  M <- M[, colSums(is.finite(M)) == ROLL, drop = FALSE]
  if (ncol(M) < 30L) next
  C <- cor(M)
  roll_rows[[length(roll_rows)+1L]] <- data.table(Date = wd[i], n_names = ncol(M),
                                                  rho_bar = mean(C[upper.tri(C)]))
}
RHO <- rbindlist(roll_rows)
RHO <- merge(RHO, BMM[, .(Date, regime_dir, regime_vol, regime_crisis, r12, v12)], by = "Date")
cat(sprintf("[R4] rolling-24m rho_bar: %d months, median n_names=%.0f, range %.3f..%.3f\n",
            nrow(RHO), median(RHO$n_names), min(RHO$rho_bar), max(RHO$rho_bar)))
reg_rows <- list()
add_reg <- function(lbl, sel) {
  s <- RHO[sel]
  reg_rows[[lbl]] <<- data.table(regime = lbl, mean_pairwise_cor = mean(s$rho_bar),
                                 sd_rho = sd(s$rho_bar), median_n_names = median(s$n_names),
                                 n_months = nrow(s), small_sample = nrow(s) < 30L)
}
add_reg("ALL", rep(TRUE, nrow(RHO)))
add_reg("BULL", RHO$regime_dir == "BULL" & !is.na(RHO$regime_dir))
add_reg("BEAR", RHO$regime_dir == "BEAR" & !is.na(RHO$regime_dir))
add_reg("HIGHVOL", RHO$regime_vol == "HIGHVOL" & !is.na(RHO$regime_vol))
add_reg("LOWVOL", RHO$regime_vol == "LOWVOL" & !is.na(RHO$regime_vol))
add_reg("CRISIS", RHO$regime_crisis == "CRISIS")
add_reg("NORMAL", RHO$regime_crisis == "NORMAL")
REG <- rbindlist(reg_rows); print(REG)

## 팩터 간 하방 tail dependence (TDC, 경험적)
key_f <- c("MKT","X_VAL","X_MOM","X_SIZE","X_LIQ","X_RVOL")
tdc <- function(a, b, q = 0.10) {
  ua <- a <= quantile(a, q); ub <- b <= quantile(b, q)
  sum(ua & ub) / sum(ua)
}
TD <- list()
for (i in 1:(length(key_f)-1)) for (j in (i+1):length(key_f))
  TD[[paste0(key_f[i], "_vs_", key_f[j])]] <- tdc(Fm[, key_f[i]], Fm[, key_f[j]])
print(round(unlist(TD), 3))
fcor <- cor(Fm[, key_f]); hi_pairs <- which(abs(fcor) > 0.8 & upper.tri(fcor), arr.ind = TRUE)
cat(sprintf("[R4] factor |corr|>0.8 pairs among key styles: %d\n", nrow(hi_pairs)))

saveRDS(list(w = w, top25 = top25, x = x, contrib = contrib, grp = grp, sec_contrib = sec_contrib,
             tot_var_d = tot_var_d, fac_var_d = fac_var_d, spec_var_d = spec_var_d,
             hhi_name = hhi_name, n_eff_name = n_eff_name, hhi_sec = hhi_sec, n_eff_sec = n_eff_sec,
             secw = secw, tier_rc = tier_rc, liq = liq, tail_m = tail_m, ev95 = ev95, ev99 = ev99,
             cf99 = cf99, cd = cd, h_m = h_m, h_b = h_b, ev_d = ev_d, h_d = h_d,
             cov_daily = cov_daily, STR = STR, scen = scen, f_mo_sd = f_mo_sd,
             CR = CR, CRd = CRd, REG = REG, RHO = RHO, TD = TD, n_hi_pairs = nrow(hi_pairs),
             mrc = mrc, PR_n = nrow(PR_pit), DUAL = DUAL, tier_w = tier_w,
             pl_hist = pl_hist, fcor = fcor, hi_pairs = hi_pairs, tb = tb),
        file.path(OUT, "risk_r4.rds"))
cat("[R4] done\n")
