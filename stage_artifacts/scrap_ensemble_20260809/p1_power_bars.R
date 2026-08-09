#!/usr/bin/env Rscript
# =============================================================================
# p1_power_bars.R — FQ-174 착수 전 검정력 바 (사전등록 前 필수, ABORT 권한)
#
# 왜: "국면-조건부·분할 = 구조적 저검정력" (2026-08-08, 하루 3회 재현).
#     사전등록 전에 필요효과를 산출하고 비현실적이면 착수 전 폐기한다.
#
# 방식 (계약 required_effect() 와 동등하되 sd 를 실측으로 대체):
#   required_monthly = t_thr * sd(d) / sqrt(n) * nw_inflation
#   d = arm 월수익 - base(EW) 월수익  (paired 차이 계열)
#   ★ 계약의 SPREAD_SD_MONTHLY_25EW(0.0394) 는 top-25 종목 바스켓 쌍 실측이라
#     모듈-NAV 앙상블 차이 계열과 변동성이 다르다 → 계약 주석 109행 지시대로
#     "해당 계열의 실제 sd" 를 p0_panel 에서 직접 산출해 넣는다.
#
# 헌법: 포트 구성 = PerformanceAnalytics::Return.portfolio 만. 손계산 합성 금지.
#       d = arm - base 는 active(초과) 계열 정의이지 포트 합성이 아니다.
# metric_type = diagnostic_precheck (자본 판정 아님)
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(xts); library(PerformanceAnalytics); library(jsonlite)
})
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1_power.log"), split = TRUE)
set.seed(20260809)

T_THR   <- 2.0
NW_LAG  <- 3
N_DRAW12 <- 300L
N_DRAW25 <- 200L
N_BOOT   <- 1000L
BLOCK    <- 12L

## ---------------------------------------------------------------- 입력 실측
P <- readRDS(file.path(OUT, "p0_panel.rds"))
PAN <- P$PAN; scrap_ok <- P$scrap_ok; elite_ok <- P$elite_ok
sub <- PAN[ym >= P$start_ym & is.finite(bm)]; setorder(sub, ym)
M0  <- as.matrix(sub[, ..scrap_ok])
cov_m <- colSums(is.finite(M0)); keep <- which(cov_m >= 253)
rows <- complete.cases(M0[, keep, drop = FALSE])
M <- M0[rows, keep, drop = FALSE]; ids <- scrap_ok[keep]
bmv <- sub$bm[rows]; ymv <- sub$ym[rows]
n_all <- nrow(M)
cat(sprintf("=== [0] INPUT 실측: %d months x %d modules ; %s..%s ===\n",
            n_all, ncol(M), ymv[1], ymv[n_all]))
cat(sprintf("    관측단위=월(월수익 median|r|=%.5f). NW lag=%d 는 월 기준.\n",
            median(abs(M)), NW_LAG))
dts <- as.Date(paste0(substr(ymv,1,4), "-", substr(ymv,5,6), "-01"))

## ---------------------------------------------------- dedup (p0f 와 동일 규칙)
C <- cor(M); diag(C) <- 0
hi <- which(C >= 0.999, arr.ind = TRUE); hi <- hi[hi[,1] < hi[,2], , drop = FALSE]
comp <- local({
  par <- seq_len(ncol(M))
  fnd <- function(x) { while (par[x] != x) x <- par[x]; x }
  if (nrow(hi)) for (r in seq_len(nrow(hi))) {
    a <- fnd(hi[r,1]); b <- fnd(hi[r,2]); if (a != b) par[b] <- a }
  vapply(seq_len(ncol(M)), fnd, integer(1))
})
reps <- vapply(unique(comp), function(g) which(comp == g)[1], integer(1))
Mu <- M[, reps, drop = FALSE]; idu <- ids[reps]; NU <- ncol(Mu)
cat(sprintf("=== [1] dedup(corr>=0.999 union-find): %d -> %d  (p0f 재현 확인: %s)\n",
            ncol(M), NU, if (NU == 85L) "일치 85" else paste("불일치", NU)))
stopifnot(NU == 85L)

Xu  <- xts(Mu, order.by = dts)
X91 <- xts(M,  order.by = dts)

## ------------------------------------------------------------ base / 앵커 확인
pf <- function(x, w) as.numeric(Return.portfolio(x, weights = w, rebalance_on = "months"))
base85 <- pf(Xu,  rep(1/NU, NU))
base91 <- pf(X91, rep(1/ncol(M), ncol(M)))
mdd_of <- function(v) as.numeric(maxDrawdown(xts(v, order.by = dts)))
ann_of <- function(v) { a <- table.AnnualizedReturns(xts(v, order.by = dts), scale = 12); as.numeric(a[,1]) }
a85 <- ann_of(base85); a91 <- ann_of(base91)
cat(sprintf("=== [2] base 앵커 (metric_type=backtested, Return.portfolio/table.AnnualizedReturns/maxDrawdown)\n"))
cat(sprintf("    EW(191 raw)  CAGR=%.2f%% SR=%.3f MDD=%.1f%%   [P0 보고: 11.46 / 0.599 / 41.6]\n",
            100*a91[1], a91[3], 100*mdd_of(base91)))
cat(sprintf("    EW(85 dedup) CAGR=%.2f%% SR=%.3f MDD=%.1f%%   <- 본 라운드 base\n",
            100*a85[1], a85[3], 100*mdd_of(base85)))
elite_use <- intersect(elite_ok, colnames(PAN))
Xe <- xts(as.matrix(sub[rows, ..elite_use]), order.by = dts)
elite_ok_cc <- all(is.finite(coredata(Xe)))
eliteR <- if (elite_ok_cc) pf(Xe, rep(1/length(elite_use), length(elite_use))) else rep(NA_real_, n_all)
if (elite_ok_cc) cat(sprintf("    ELITE EW(%d)  CAGR=%.2f%% SR=%.3f MDD=%.1f%%   [P0: 17.47 / 1.126 / 24.6]\n",
            length(elite_use), 100*ann_of(eliteR)[1], ann_of(eliteR)[3], 100*mdd_of(eliteR)))

## ----------------------------------------------------------------- 상태 버킷
st <- ifelse(bmv <= -0.05, "DOWN", ifelse(bmv >= 0.05, "SURGE", "FLAT"))
nb <- table(st)
cat(sprintf("=== [3] 버킷 실측: DOWN=%d SURGE=%d FLAT=%d (합 %d)  [P0: 31/49/174]\n",
            nb[["DOWN"]], nb[["SURGE"]], nb[["FLAT"]], sum(nb)))

## ------------------------------------------------- NW(lag3) SE (평균에 대한)
se_nw <- function(x, L = NW_LAG) {
  n <- length(x); e <- x - mean(x)
  g0 <- sum(e*e)/n; om <- g0
  if (L > 0) for (l in seq_len(L)) {
    gl <- sum(e[(l+1):n] * e[1:(n-l)]) / n
    om <- om + 2 * (1 - l/(L+1)) * gl
  }
  if (om <= 0) return(NA_real_)
  sqrt(om / n)
}
se_iid <- function(x) sd(x) / sqrt(length(x))

## --------------------------------------------- 무작위 arm 표본 → paired sd 실측
draw_sd <- function(K, ndraw) {
  res <- data.table(sd_full=numeric(ndraw), sd_DOWN=numeric(ndraw),
                    sd_SURGE=numeric(ndraw), sd_FLAT=numeric(ndraw), nwfac=numeric(ndraw))
  for (i in seq_len(ndraw)) {
    sel <- sample.int(NU, K)
    r   <- pf(Xu[, sel, drop = FALSE], rep(1/K, K))
    d   <- r - base85
    res$sd_full[i]  <- sd(d)
    res$sd_DOWN[i]  <- sd(d[st == "DOWN"])
    res$sd_SURGE[i] <- sd(d[st == "SURGE"])
    res$sd_FLAT[i]  <- sd(d[st == "FLAT"])
    s1 <- se_nw(d); s0 <- se_iid(d)
    res$nwfac[i] <- if (is.finite(s1)) s1/s0 else NA_real_
  }
  res
}
cat("=== [4] 무작위 arm paired-diff sd 실측 (Return.portfolio 경유) ===\n")
tA <- Sys.time(); D12 <- draw_sd(12L, N_DRAW12); D25 <- draw_sd(25L, N_DRAW25)
cat(sprintf("    draws: K=12 n=%d · K=25 n=%d   (%.0f s)\n", N_DRAW12, N_DRAW25,
            as.numeric(difftime(Sys.time(), tA, units="secs"))))
qs <- function(v) sprintf("%.4f [%.4f,%.4f]", median(v,na.rm=TRUE),
                          quantile(v,.05,na.rm=TRUE), quantile(v,.95,na.rm=TRUE))
for (nm in c("sd_full","sd_DOWN","sd_SURGE","sd_FLAT","nwfac"))
  cat(sprintf("    K=12 %-8s median[5,95%%] = %s   |  K=25 = %s\n", nm, qs(D12[[nm]]), qs(D25[[nm]])))

NWFAC <- median(D12$nwfac, na.rm = TRUE)
cat(sprintf("    ★NW(lag3) 팽창계수 실측 = %.3f (계약 기본값 1.25 대신 이 값 사용, 전표본 바에만)\n", NWFAC))

## ------------------------------------------------- IS 천장 + 지속성-함의 기대치
# 상태-조건부 고정 로스터의 IS 최적(전표본 지식) = 어떤 상태-조건부 멤버십 규칙도 못 넘는 상한
A <- Mu - matrix(base85, n_all, NU)   # 각 모듈의 base 대비 차이 (active-to-base)
ceil_state <- function(mask, K = 12L) {
  mu  <- colMeans(A[mask, , drop = FALSE])
  sel <- order(mu, decreasing = TRUE)[1:K]
  r   <- pf(Xu[, sel, drop = FALSE], rep(1/K, K))
  mean((r - base85)[mask])
}
RHO <- c(DOWN = 0.462, SURGE = 0.498, FLAT = -0.436, full = -0.130)  # P0 §4/§5 실측
ceilv <- c(full  = ceil_state(rep(TRUE, n_all)),
           DOWN  = ceil_state(st == "DOWN"),
           SURGE = ceil_state(st == "SURGE"),
           FLAT  = ceil_state(st == "FLAT"))
cat("=== [5] IS 천장 (전표본 지식 top-12 고정 로스터, K=12) + 지속성-함의 기대 OOS ===\n")
for (k in names(ceilv))
  cat(sprintf("    %-6s IS천장=%+.3f%%/m  rho=%+.3f  →  기대OOS≈rho x 천장 = %+.3f%%/m\n",
              k, 100*ceilv[k], RHO[k], 100*ceilv[k]*max(RHO[k],0)))
cat("    ※ 기대OOS 는 'IS 순위와 OOS 성과의 상관 rho 만큼만 천장을 회수' 가정. label=estimated\n")

## ------------------------------------------------------------------ 바 1~4
mk_bar <- function(name, n, sdv, nwf, ceil, rho) {
  req_m <- T_THR * sdv / sqrt(n) * nwf
  list(arm_or_bucket = name, n = n,
       sd_monthly_pct = 100*sdv,
       required_effect_pct_per_month = 100*req_m,
       required_pct_per_year = 100*req_m*12,
       book_annual_contrib_pct = 100*req_m*12*n/n_all,
       nw_inflation = nwf,
       is_ceiling_pct_per_month = 100*ceil,
       persistence_rho = unname(rho),
       expected_oos_pct_per_month = 100*ceil*max(rho, 0),
       required_over_ceiling = req_m/ceil,
       required_over_expected_oos = if (rho > 0) req_m/(ceil*rho) else Inf)
}
bars <- list(
  mk_bar("FULL_254m",  n_all,        median(D12$sd_full),  NWFAC, ceilv[["full"]],  RHO[["full"]]),
  mk_bar("DOWN_n31",   nb[["DOWN"]], median(D12$sd_DOWN),  1.0,   ceilv[["DOWN"]],  RHO[["DOWN"]]),
  mk_bar("SURGE_n49",  nb[["SURGE"]],median(D12$sd_SURGE), 1.0,   ceilv[["SURGE"]], RHO[["SURGE"]]),
  mk_bar("FLAT_n174",  nb[["FLAT"]], median(D12$sd_FLAT),  1.0,   ceilv[["FLAT"]],  RHO[["FLAT"]])
)
cat("=== [6] 검정력 바 (paired |t|>=2.0, K=12 arm vs EW85 base) ===\n")
for (b in bars) cat(sprintf(
  "    %-11s n=%3d sd=%.3f%%/m  필요 %+.4f%%/m (연 %+.2f%%p, 북기여 연 %+.2f%%p) | IS천장 %+.3f 기대OOS %+.3f | 필요/천장=%.2f 필요/기대=%.2f\n",
  b$arm_or_bucket, b$n, b$sd_monthly_pct, b$required_effect_pct_per_month,
  b$required_pct_per_year, b$book_annual_contrib_pct,
  b$is_ceiling_pct_per_month, b$expected_oos_pct_per_month,
  b$required_over_ceiling, b$required_over_expected_oos))

## ----------------------------------------------------------- 바 5 : MDD/Calmar
cat("=== [7] MDD 축 block bootstrap (block=12, rep=1000, paired 동일 인덱스) ===\n")
boot_idx <- function(n, blk) {
  nb_ <- ceiling(n/blk)
  starts <- sample.int(n - blk + 1L, nb_, replace = TRUE)
  as.integer(unlist(lapply(starts, function(s) s:(s+blk-1L))))[1:n]
}
# 대표 arm 3종: 무작위 K=12 중 MDD 중앙 / MDD 최소 / ELITE EW
set.seed(20260809)
cand <- lapply(seq_len(400L), function(i) { sel <- sample.int(NU, 12L); pf(Xu[, sel, drop=FALSE], rep(1/12,12)) })
cmdd <- vapply(cand, mdd_of, numeric(1))
cat(sprintf("    정적 무작위 K=12 400회: min MDD=%.1f%% median=%.1f%%  [P0: 4000회 min 34.5%%]\n",
            100*min(cmdd), 100*median(cmdd)))
arms_mdd <- list(rand12_medianMDD = cand[[order(cmdd)[200]]],
                 rand12_bestMDD   = cand[[which.min(cmdd)]])
if (elite_ok_cc) arms_mdd$elite_ew <- eliteR

set.seed(20260810)
BI <- lapply(seq_len(N_BOOT), function(i) boot_idx(n_all, BLOCK))
mdd_boot <- function(v) vapply(BI, function(ix) mdd_of(v[ix]), numeric(1))
mb_base <- mdd_boot(base85)
cat(sprintf("    base EW85 MDD 실측=%.1f%%  boot mean=%.1f%% sd=%.2f%%p  [5%%,95%%]=[%.1f,%.1f]\n",
            100*mdd_of(base85), 100*mean(mb_base), 100*sd(mb_base),
            100*quantile(mb_base,.05), 100*quantile(mb_base,.95)))
mdd_rows <- list()
for (nm in names(arms_mdd)) {
  v  <- arms_mdd[[nm]]
  mb <- mdd_boot(v)
  dl <- mb_base - mb                      # paired ΔMDD (양수 = arm 이 개선)
  se <- sd(dl); obs <- mdd_of(base85) - mdd_of(v)
  mdd_rows[[nm]] <- list(arm = nm, mdd_arm_pct = 100*mdd_of(v),
                         delta_mdd_obs_pp = 100*obs, se_delta_pp = 100*se,
                         t_obs = obs/se, required_delta_pp = 100*T_THR*se)
  cat(sprintf("    %-18s MDD=%.1f%%  ΔMDD 관측=%+.1f%%p  paired SE=%.2f%%p  t=%+.2f  필요 Δ=%.2f%%p\n",
              nm, 100*mdd_of(v), 100*obs, 100*se, obs/se, 100*T_THR*se))
}
se_med <- median(vapply(mdd_rows, function(x) x$se_delta_pp, numeric(1))[
  intersect(names(mdd_rows), c("rand12_medianMDD","rand12_bestMDD"))])
req_mdd_pp <- T_THR * se_med
cat(sprintf("    ★MDD 바: 무작위 K=12 arm 기준 paired SE 중앙 %.2f%%p → 유의한 개선 주장에 필요 ΔMDD = %.2f%%p\n",
            se_med, req_mdd_pp))
cat(sprintf("      (EW85 MDD %.1f%% → %.1f%% 이하로 내려야 |t|>=2)\n",
            100*mdd_of(base85), 100*mdd_of(base85) - req_mdd_pp))
cat(sprintf("      정적 조합 천장(400회 min)=%.1f%% ⇒ 달성가능 ΔMDD 최대 %+.1f%%p → t=%+.2f\n",
            100*min(cmdd), 100*(mdd_of(base85)-min(cmdd)), (mdd_of(base85)-min(cmdd))/ (se_med/100)))

## ------------------------------------------------------------------- 저장
bars_out <- lapply(bars, function(b) {
  b$plausible <- if (!is.finite(b$required_over_expected_oos)) FALSE else
                 (b$required_over_expected_oos < 1)
  b$metric_type <- "diagnostic_precheck"
  b
})
mdd_bar <- list(arm_or_bucket = "MDD_axis_blockboot", n = n_all,
                sd_monthly_pct = se_med,               # 단위 = %p (ΔMDD 의 paired SE)
                required_effect_pct_per_month = req_mdd_pp,   # 단위 = %p
                required_pct_per_year = req_mdd_pp,
                unit_note = "단위는 %p(ΔMDD), 월수익률 아님",
                base_mdd_pct = 100*mdd_of(base85),
                achievable_best_mdd_pct = 100*min(cmdd),
                achievable_delta_pp = 100*(mdd_of(base85)-min(cmdd)),
                achievable_t = (mdd_of(base85)-min(cmdd))/(se_med/100),
                plausible = ((mdd_of(base85)-min(cmdd))*100) >= req_mdd_pp,
                per_arm = unname(mdd_rows), metric_type = "diagnostic_precheck")

write_json(list(
  meta = list(round = "FQ-174 scrap ensemble", stage = "prereg_power_bars",
              window = sprintf("%s..%s", ymv[1], ymv[n_all]), n_months = n_all,
              universe_dedup = NU, dedup_rule = "corr>=0.999 union-find (p0f 재현)",
              base = "EW(dedup 85), Return.portfolio rebalance_on=months",
              t_threshold = T_THR, nw_lag = NW_LAG, nw_inflation_measured = NWFAC,
              n_draws = list(K12 = N_DRAW12, K25 = N_DRAW25), boot = list(rep = N_BOOT, block = BLOCK),
              contract = "02_Infrastructure/contracts/required_effect_size.R (공식 동등, sd 는 실측 대체)",
              metric_type = "diagnostic_precheck"),
  base_anchor = list(ew191 = list(cagr=100*a91[1], sr=a91[3], mdd=100*mdd_of(base91)),
                     ew85  = list(cagr=100*a85[1], sr=a85[3], mdd=100*mdd_of(base85)),
                     elite = if (elite_ok_cc) list(cagr=100*ann_of(eliteR)[1], sr=ann_of(eliteR)[3],
                                                   mdd=100*mdd_of(eliteR)) else NULL),
  sd_distribution = list(
    K12 = lapply(c("sd_full","sd_DOWN","sd_SURGE","sd_FLAT","nwfac"),
                 function(nm) list(stat=nm, median=median(D12[[nm]],na.rm=TRUE),
                                   q05=unname(quantile(D12[[nm]],.05,na.rm=TRUE)),
                                   q95=unname(quantile(D12[[nm]],.95,na.rm=TRUE)))),
    K25 = lapply(c("sd_full","sd_DOWN","sd_SURGE","sd_FLAT","nwfac"),
                 function(nm) list(stat=nm, median=median(D25[[nm]],na.rm=TRUE),
                                   q05=unname(quantile(D25[[nm]],.05,na.rm=TRUE)),
                                   q95=unname(quantile(D25[[nm]],.95,na.rm=TRUE))))),
  bars = c(bars_out, list(mdd_bar))
), file.path(OUT, "prereg_power_bars.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
cat("\n[saved] ", file.path(OUT, "prereg_power_bars.json"), "\n")
sink()
