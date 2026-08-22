## WT-D20260822_007 P1c — 하네스 패리티 (공표 수치 2건 재현). 새 arm 측정 아님 = 하네스 검증.
##   ① 균등가중 -> FQ-244 C0 PORT_t 0.947410715814893
##   ② one-hot argmax(실현 IC) -> FQ-244 ORACLE_K PORT_t 4.64699909 / paired 13.6929981793759 %p/yr
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")
OUT <- "stage_artifacts/WT-D20260822_007"; SRC <- "stage_artifacts/fq233_probe0_20260813"
PB <- readRDS(file.path(OUT,"p1_probe.rds")); A4 <- PB$A4; months <- PB$months; icm <- PB$icm
pan <- as.data.table(read_parquet(file.path(SRC,"lane_a_feature_panel.parquet")))
pan[, anchor := as.Date(anchor)]
panh <- pan[anchor %in% A4$anchors & is.finite(fwd_ret_1m)]
TOPN <- A4$TOPN; K <- A4$K

## ---- 공통 가중 적용기: W = 221 x K 가중행렬 -> score = 유효 z 의 가중평균 ----
build_from_W <- function(W) rbindlist(lapply(seq_along(months), function(m) {
  nm <- months[m]; fs <- A4$sel_rank[[nm]]; d <- panh[anchor == as.Date(nm)]
  Z <- as.matrix(d[, ..fs]); w <- W[m, ]
  Wm <- matrix(w, nrow = nrow(Z), ncol = K, byrow = TRUE)
  Wm[!is.finite(Z)] <- 0; Z0 <- Z; Z0[!is.finite(Z0)] <- 0
  den <- rowSums(Wm); sc <- ifelse(den > 0, rowSums(Z0*Wm)/den, NA_real_)
  data.table(Date = as.Date(nm), Ticker = as.character(d$Ticker), score = sc)[is.finite(score)] }))

runbt <- function(s, id, bench = A4$bench_dt, dual = FALSE) { s <- copy(s); setorder(s, Date, Ticker)
  canonical_screen_bt(s[, .(Date,Ticker,score)], A4$returns_dt, bench, top_n = TOPN,
    cost_bps_oneway = 15, run_id = id, strategy_id = id, diag_dual_basis = dual) }

t0 <- Sys.time()
W_uni <- matrix(1/K, nrow = length(months), ncol = K)
B_uni <- runbt(build_from_W(W_uni), "FQ246NP1_parity_C0")
t1 <- Sys.time()
cat(sprintf("[timing] 1 run = %.2f sec\n", as.numeric(difftime(t1, t0, units="secs"))))

W_arg <- t(apply(icm, 1, function(x) { w <- rep(0, K); w[which.max(x)] <- 1; w }))
B_arg <- runbt(build_from_W(W_arg), "FQ246NP1_parity_ORACLE_K")

a_uni <- as.data.table(B_uni$period_returns)[, ret_net - benchmark_ret]
a_arg <- as.data.table(B_arg$period_returns)[, ret_net - benchmark_ret]
d <- a_arg - a_uni
ann <- mean(d)*12*100; tt <- .nw_t_mean(d, lag = 3L)

PAR <- data.table(
  check = c("C0_uniform_port_t", "ORACLE_K_port_t", "ORACLE_K_paired_ann_pct", "ORACLE_K_paired_t"),
  measured  = c(B_uni$portfolio_alpha_t_nw_lag3, B_arg$portfolio_alpha_t_nw_lag3, ann, tt),
  published = c(0.947410715814893, 4.64699909, 13.6929981793759, 4.28970507043012))
PAR[, delta := measured - published]
print(PAR)
cat(sprintf("\n  n months = %d (uni) / %d (arg)\n", length(a_uni), length(a_arg)))
cat("  ★패리티 판정: |delta| < 1e-6 이면 가중 프레임이 FQ-244 두 극점을 비트-동치로 재현 =\n")
cat("    사다리 중간 지점(형태 변주)의 해석 자격이 성립한다.\n")
saveRDS(list(PAR=PAR, a_uni=a_uni, a_arg=a_arg, W_uni=W_uni, W_arg=W_arg,
             dates = as.Date(as.data.table(B_uni$period_returns)$date)),
        file.path(OUT, "p1c_parity.rds"))
cat("\n[saved] p1c_parity.rds\nOK\n")
