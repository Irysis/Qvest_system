# ── R5 — 최종 Sigma 구성의 bias 재검증 + 산출물(parquet/json) 발행
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
set.seed(20260829L)

R1 <- readRDS(file.path(OUT,"risk_r1.rds")); R2 <- readRDS(file.path(OUT,"risk_r2.rds"))
R3 <- readRDS(file.path(OUT,"risk_r3.rds")); R4 <- readRDS(file.path(OUT,"risk_r4.rds"))
D <- R1$D; EXPO <- R1$EXPO; ME_win <- R1$ME_win; SIG <- R1$SIG
FR <- R2$FR; UR <- R2$UR; fac_names <- R2$fac_names; SECLV <- R2$SECLV; STY <- R2$STY
WIN_D <- R2$WIN_D; ASSETS <- R2$ASSETS; B <- R2$B; Om <- R2$Omega_d; win_d <- R2$win_d
Sig_d <- R3$Sigma_d; dvec <- R3$dvec_final; FLOOR <- R3$floor_frac
alldates <- sort(unique(D$Date)); setkey(D, Date, Ticker)

mk_X <- function(ex) {
  n <- nrow(ex); sec <- factor(ex$Sector, levels = SECLV)
  Xs <- matrix(0, n, length(SECLV)-1L); li <- as.integer(sec)
  for (k in seq_len(length(SECLV)-1L)) Xs[,k] <- as.numeric(li == k)
  Xs[li == length(SECLV), ] <- -1
  colnames(Xs) <- paste0("SEC_", SECLV[-length(SECLV)])
  X <- cbind(MKT = 1, Xs, as.matrix(ex[, ..STY])); rownames(X) <- ex$Ticker; X
}

## ── (A) 최종 구성(floor 0.40) walk-forward bias 재검증 ──────────────────────
test_me <- tail(ME_win, 25L); fdates <- sort(unique(FR$Date)); NB <- 100L; NH <- 25L
zr <- list()
for (i in 1:(length(test_me)-1L)) {
  d_a <- test_me[i]; d_e <- test_me[i+1L]
  dd <- alldates[alldates > d_a & alldates <= d_e]; if (length(dd) < 10L) next
  fw <- tail(fdates[fdates <= d_a], WIN_D); if (length(fw) < 400L) next
  Fw <- as.matrix(FR[Date %in% fw, ..fac_names]); Omx <- cov(Fw)
  e0 <- eigen(Omx, symmetric=TRUE); Omx <- e0$vectors %*% diag(pmax(e0$values, max(e0$values)*1e-6)) %*% t(e0$vectors)
  Dt <- D[Date %in% dd, .(Date, Ticker, Ret)]
  cnt <- Dt[, .N, by=Ticker][N >= length(dd)-2L]
  exa <- EXPO[Date == d_a][Ticker %in% cnt$Ticker]; setorder(exa, Ticker)
  if (nrow(exa) < 60L) next
  Bx <- mk_X(exa)
  Uw <- UR[Date %in% fw & Ticker %in% exa$Ticker]
  Dsx <- Uw[, .(n=.N, v=var(u)), by=Ticker][n >= 120L]
  mv <- median(Dsx$v, na.rm=TRUE); Dsx[, sh := pmin(1,120/n)]
  Dsx[, v_sh := pmax((1-sh)*v + sh*mv, FLOOR*mv)]
  dv <- setNames(rep(mv, nrow(exa)), exa$Ticker); dv[Dsx$Ticker] <- Dsx$v_sh
  Sf <- Bx %*% Omx %*% t(Bx) + diag(dv[exa$Ticker]); dimnames(Sf) <- list(exa$Ticker, exa$Ticker)
  RT <- dcast(Dt, Date ~ Ticker, value.var="Ret"); RT[, Date := NULL]; RT <- as.matrix(RT)
  RT[!is.finite(RT)] <- 0
  pool <- intersect(exa$Ticker, colnames(RT)); nd <- length(dd)
  for (b in 1:NB) {
    bs <- sample(pool, NH); w <- rep(1/NH, NH)
    real <- prod(1 + rowMeans(RT[, bs, drop=FALSE])) - 1
    v <- as.numeric(t(w) %*% Sf[bs,bs] %*% w) * nd
    if (is.finite(v) && v > 0) zr[[length(zr)+1L]] <- data.table(month=d_e, z=real/sqrt(v))
  }
}
Zf <- rbindlist(zr)
bias_final <- list(bias_stat = sd(Zf$z), mean_z = mean(Zf$z), n = nrow(Zf))
cat(sprintf("[R5-A] FINAL factor Sigma (floor %.2f) bias_stat = %.3f (mean_z %.3f, n=%d)\n",
            FLOOR, bias_final$bias_stat, bias_final$mean_z, bias_final$n))

## ── (B) 단위 변환: 월간(21거래일) ───────────────────────────────────────────
SCALE <- 21
Sig_m  <- Sig_d * SCALE
Om_m   <- Om * SCALE
dvec_m <- dvec * SCALE
ev <- eigen(Sig_m, symmetric=TRUE, only.values=TRUE)$values
cat(sprintf("[R5-B] Sigma_monthly: p=%d cond=%.1f min_eig=%.3g PD=%s\n",
            nrow(Sig_m), max(ev)/min(ev), min(ev), min(ev) > 0))

## ── (C) 벤치마크 프록시로 모델 검증 (K200 cap-weight) ───────────────────────
mem_now <- R1$mem[Date == SIG]
k2 <- mem_now[mkt == "K200", Ticker]; k2 <- intersect(k2, ASSETS)
sz <- R2$ex_now[Ticker %in% k2, .(Ticker, Size)]
wb <- setNames(rep(0, length(ASSETS)), ASSETS); wb[sz$Ticker] <- sz$Size/sum(sz$Size)
sig_b_vec <- as.numeric(Sig_m %*% wb); names(sig_b_vec) <- ASSETS
var_b <- as.numeric(t(wb) %*% Sig_m %*% wb)
## ★검증 기준은 **같은 추정창의 실현치**여야 한다. alpha diagnostics 의 벤치 vol 22.52%는
##   2005~2026 전기간 **월별** 계열이고, 본 Sigma 는 2023-08~2026-07 **일별** 창이다 —
##   두 수를 맞대면 2배 괴리가 나오는데 그것은 모델 오차가 아니라 창/주기 불일치다.
bm_win_ann <- sd(R1$BMd[Date %in% win_d, BM_Ret]) * sqrt(252)
Dw <- D[Date %in% win_d & Ticker %in% ASSETS, .(Date, Ticker, Ret)]
Wm <- dcast(Dw, Date ~ Ticker, value.var = "Ret"); wdts <- Wm$Date; Wm[, Date := NULL]; Wm <- as.matrix(Wm)
Wm <- Wm[, ASSETS, drop = FALSE]; okm <- is.finite(Wm); Wm[!okm] <- 0
insample <- function(wv) {
  wv <- wv[ASSETS]; wv[!is.finite(wv)] <- 0
  den <- as.numeric(okm %*% wv); den[den <= 0] <- NA
  r <- as.numeric(Wm %*% wv) / den
  list(pred_ann = sqrt(as.numeric(t(wv) %*% Sig_d %*% wv) * 252),
       real_ann = sd(r, na.rm = TRUE) * sqrt(252), r = r)
}
w25 <- setNames(rep(0, length(ASSETS)), ASSETS); w25[R4$top25] <- 1/length(R4$top25)
wew <- setNames(rep(1/length(ASSETS), length(ASSETS)), ASSETS)
cal_rows <- list()
for (nm in c("ew_top25_reference","ew_universe_340","k200_capw_proxy")) {
  wv <- switch(nm, ew_top25_reference = w25, ew_universe_340 = wew, k200_capw_proxy = wb)
  s <- insample(wv)
  cal_rows[[nm]] <- data.table(basis = nm, pred_vol_ann = s$pred_ann, realized_vol_ann = s$real_ann,
                               ratio = s$pred_ann / s$real_ann)
}
CAL <- rbindlist(cal_rows); print(CAL)
cat(sprintf("[R5-C] benchmark realized vol in SAME window = %.2f%% ann (daily). model K200 proxy = %.2f%%\n",
            100*bm_win_ann, 100*sqrt(var_b*12)))
## 월별 집계 검사 — 일별 Sigma x 21 이 월간 실현분산을 재현하는가
s25 <- insample(w25)
mo <- data.table(Date = wdts, r = s25$r)[is.finite(r)]
mo[, ym := format(Date, "%Y-%m")]
mret <- mo[, .(mr = prod(1 + r) - 1, nd = .N), by = ym][nd >= 15L]
agg_ratio <- (sd(mret$mr) * sqrt(12)) / s25$real_ann
cat(sprintf("[R5-C] temporal aggregation: monthly-realized vol %.2f%% ann vs sqrt(21)x daily %.2f%% ann -> ratio %.3f\n",
            100*sd(mret$mr)*sqrt(12), 100*s25$real_ann, agg_ratio))

## ── (D) parquet / json 발행 ─────────────────────────────────────────────────
ex_now <- R2$ex_now
EXP_OUT <- data.table(Ticker = ASSETS)
Bm <- B[ASSETS, , drop=FALSE]
for (cn in colnames(Bm)) EXP_OUT[[cn]] <- as.numeric(Bm[, cn])
EXP_OUT <- merge(EXP_OUT, ex_now[, .(Ticker, Sector, mkt, Size, adv, beta_blume = beta, rvol_ann = rvol)],
                 by = "Ticker")
EXP_OUT[, as_of_date := as.character(SIG)]
write_parquet(EXP_OUT, file.path(OUT, "exposure_matrix.parquet"))

FC <- data.table(factor = fac_names)
for (j in seq_along(fac_names)) FC[[fac_names[j]]] <- as.numeric(Om_m[, j])
write_parquet(FC, file.path(OUT, "factor_covariance.parquet"))

Ds <- R3$Ds; med_v <- R3$med_v
SR <- data.table(Ticker = ASSETS,
                 specific_var_monthly = as.numeric(dvec_m[ASSETS]),
                 specific_vol_ann = sqrt(as.numeric(dvec_m[ASSETS]) * 12))
SR <- merge(SR, Ds[, .(Ticker, n_obs = n, raw_var_daily = v)], by = "Ticker", all.x = TRUE)
SR[, floored := is.finite(raw_var_daily) & raw_var_daily < FLOOR * med_v]
SR[, fallback_median := is.na(n_obs)]
write_parquet(SR, file.path(OUT, "specific_risk.parquet"))

CV <- data.table(Ticker = ASSETS)
for (j in seq_along(ASSETS)) CV[[ASSETS[j]]] <- as.numeric(Sig_m[, j])
write_parquet(CV, file.path(OUT, "covariance.parquet"))

BENCH <- data.table(Ticker = ASSETS, cov_with_bench_monthly = sig_b_vec, bench_weight_proxy = wb[ASSETS])
write_parquet(BENCH, file.path(OUT, "benchmark_covariance.parquet"))

RHO <- R4$RHO
REG <- R4$REG
RC <- rbindlist(list(
  cbind(scope = "rolling_24m_series", RHO[, .(key = as.character(Date), mean_pairwise_cor = rho_bar,
        n_names = as.numeric(n_names), n_months = 24, regime_dir, regime_vol, regime_crisis)]),
  cbind(scope = "regime_aggregate", REG[, .(key = regime, mean_pairwise_cor,
        n_names = as.numeric(median_n_names), n_months = as.numeric(n_months),
        regime_dir = NA_character_, regime_vol = NA_character_, regime_crisis = NA_character_)])),
  fill = TRUE)
write_parquet(RC, file.path(OUT, "regime_correlation.parquet"))

tm <- R4$tail_m; ev95 <- R4$ev95; ev99 <- R4$ev99; cf99 <- R4$cf99; cd <- R4$cd
tail_json <- list(
  task_id = "WT-R20260829_005", as_of_date = as.character(SIG),
  pit_note = "실현 월별 계열은 holding_ym <= 2026-07 까지만 (2026-08 은 sig_date 시점 미실현). 259 -> 258개월.",
  realized_monthly = list(
    n_months = tm$n_months, source = "stage_artifacts/WT_R20260829_005/period_returns_production.csv (PIT-cut)",
    empirical = tm$empirical, skew = tm$skew, excess_kurtosis = tm$kurt - 3,
    evt_gpd_95 = ev95, evt_gpd_99 = ev99,
    cornish_fisher_99 = cf99, cdar_95 = cd,
    hill_alpha_strategy = R4$h_m$alpha, hill_k_strategy = R4$h_m$k,
    hill_alpha_benchmark = R4$h_b$alpha),
  current_basket_daily = list(
    note = "as-of top-25 균등 기준바스켓의 과거 756거래일 역투영 — 구성 아티팩트(현행 종목을 과거에 소급) 존재. 진단 전용.",
    n_days = 756, name_coverage = R4$cov_daily,
    evt_gpd_99 = R4$ev_d, hill_alpha = R4$h_d$alpha),
  interpretation = paste0(
    "월별 GPD shape xi=", round(ev95$shape_xi,3), " > 0 = 두꺼운 꼬리(Frechet 영역). ",
    "전략 Hill alpha ", round(R4$h_m$alpha,2), " 가 벤치 ", round(R4$h_b$alpha,2),
    " 보다 크다 = 월별 손실 꼬리는 벤치보다 얇다. 반면 현행 바스켓 **일별** Hill alpha ",
    round(R4$h_d$alpha,2), " 는 훨씬 두껍다 — 월 집계가 일별 꼬리를 평활한다는 뜻이며, ",
    "월 단위 CVaR 만 보면 일중/주중 꼬리를 과소평가한다."))
write_json(tail_json, file.path(OUT, "tail_risk.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

saveRDS(list(bias_final = bias_final, Sig_m = Sig_m, Om_m = Om_m, dvec_m = dvec_m,
             cond_m = max(ev)/min(ev), min_eig_m = min(ev), var_b = var_b,
             sig_b_vec = sig_b_vec, wb = wb, n_k200 = length(k2), SCALE = SCALE,
             CAL = CAL, bm_win_ann = bm_win_ann, agg_ratio = agg_ratio,
             mo_vol_ann = sd(mret$mr)*sqrt(12)),
        file.path(OUT, "risk_r5.rds"))
cat("[R5] artifacts written\n")
for (f in c("exposure_matrix.parquet","factor_covariance.parquet","specific_risk.parquet",
            "covariance.parquet","benchmark_covariance.parquet","regime_correlation.parquet","tail_risk.json"))
  cat(sprintf("   %-34s %8.1f KB\n", f, file.size(file.path(OUT,f))/1024))
cat("[R5] done\n")
