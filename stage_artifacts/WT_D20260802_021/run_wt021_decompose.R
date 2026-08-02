# =============================================================================
# run_wt021_decompose.R — WT-D20260802_021 (FQ-116) 다팩터 합성 손실 기전 분해
#   사전등록: stage_artifacts/WT_D20260802_021/preregistration.json (측정 전 고정)
#   primary  : C1_EW_STATIC_TUNED(0.338) vs C3_SINGLE_M01_PATHQ(2.050) — WT-015 승계
#   기전 3후보: M1 slot 잠식 / M2 평균화 뭉갬 / M3 커버리지 이질
#   probe    : POS2_EW (M01_PATHQ+V01_SECREL) canonical 1회 — 사전 예측 고정
#   parity   : 재구성 ret_net vs WT-015 저장 period_returns — max|diff|<1e-8 필수
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_021/run_wt021_decompose.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260802_021")
IN9  <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")
IN15 <- file.path(ROOT, "stage_artifacts/WT_D20260802_015")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt021] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()

TUNED_F <- c("V01_SECREL", "M01_PATHQ", "D03_EWMA", "Q01_EB", "V06_EB")
NEG_F <- c("D03_EWMA", "Q01_EB", "V06_EB")   # 사전등록: standalone canonical PORT_t < 0.5
POS_F <- c("M01_PATHQ", "V01_SECREL")

# ── 1. 하네스 (WT-015 동일 vintage 재현) ─────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(IN9, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(IN9, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "Close", "Vol", "Size", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
RAWME <- RAW[Date %in% MEND]
rm(RAW); gc(verbose = FALSE)
sig_all <- MEND[MEND >= min(SIG)]
UNIV <- RAWME[(K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
fwd <- build_monthly_forward_returns(RAWME, sig_all)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt <- as.data.table(read_parquet(file.path(IN9, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: SIG %d개월 (%s~%s)", length(SIG), min(SIG), max(SIG))

score_of <- function(fname) {
  sc <- if (fname %in% BASE$Factor_Name) BASE[Factor_Name == fname, .(Date, Ticker, score = z)]
        else TUNED[Factor_Name == fname, .(Date, Ticker, score = score)]
  merge(sc, UNIV, by = c("Date", "Ticker"))
}
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 2. 합성 스코어 재구성 (WT-015 §5 동일 규칙: 재-z, 월 커버리지>=100, nf>=3) ──
build_zl <- function(fnames) {
  zl <- rbindlist(lapply(fnames, function(f) {
    s <- score_of(f)
    s[, z := as.numeric(scale(score)), by = Date]
    s[, .(Date, Ticker, Factor_Name = f, z)]
  }))
  cov <- zl[!is.na(z), .N, by = .(Date, Factor_Name)]
  zl <- merge(zl, cov, by = c("Date", "Factor_Name"))
  zl[N >= 100L][, N := NULL]
}
ZL_T <- build_zl(TUNED_F)
SC_EW <- ZL_T[!is.na(z), {
  if (.N >= 3L) .(score = mean(z), nf = .N) else .(score = NA_real_, nf = .N)
}, by = .(Date, Ticker)][!is.na(score), .(Date, Ticker, score)]
SC_M01 <- score_of("M01_PATHQ")[!is.na(score)]
say("composite EW %d행 / M01 단일 %d행", nrow(SC_EW), nrow(SC_M01))

# ── 3. 선택 재구성 (canonical 동일 규칙: liq filter → top-25) + parity gate ──
select_top <- function(sc, top_n = 25L) {
  S <- as.data.table(sc)[!is.na(score)]
  S <- merge(S, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  S[, {
    n <- min(top_n, .N)
    .(Ticker = Ticker[seq_len(n)], w = rep(1 / n, n), rk = seq_len(n))
  }, by = Date]
}
W_EW  <- select_top(SC_EW)
W_M01 <- select_top(SC_M01)

port_from_w <- function(W, cost_bps = 15) {
  WR <- merge(W, returns_dt, by = c("Date", "Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur", "_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, ret_net := port_gross - traded * cost_bps / 1e4]
  setorder(port, Date)
  port
}
P_EW  <- port_from_w(W_EW)
P_M01 <- port_from_w(W_M01)

R15 <- readRDS(file.path(IN15, "wt015_results.rds"))
parity_check <- function(mine, arm) {
  st <- as.data.table(R15$bt[[arm]]$period_returns)
  m <- merge(mine[, .(date = Date, ret_net_mine = ret_net)],
             st[, .(date, ret_net_stored = ret_net)], by = "date")
  max(abs(m$ret_net_mine - m$ret_net_stored))
}
par_ew  <- parity_check(P_EW,  "C1_EW")
par_m01 <- parity_check(P_M01, "C3_SINGLE")
say("PARITY: EW %.2e / M01 %.2e (gate < 1e-8)", par_ew, par_m01)
stopifnot(par_ew < 1e-8, par_m01 < 1e-8)   # 사전등록 parity gate — 불일치 시 분해 무효

# ── 4. gap 정의 + 항등 검증 ──────────────────────────────────────────────────
G <- merge(P_EW[, .(Date, gC = port_gross, nC = ret_net)],
           P_M01[, .(Date, gS = port_gross, nS = ret_net)], by = "Date")
G[, d_gross := gC - gS]
G[, d_net := nC - nS]
say("gap(연율): gross %+.2f%%/yr, net %+.2f%%/yr, NW t(d_net)=%+.2f",
    100 * mean(G$d_gross) * 12, 100 * mean(G$d_net) * 12, nw_t(G$d_net))

# IN/OUT (양쪽 모두 25종 월 한정)
n_by <- merge(W_EW[, .N, by = Date], W_M01[, .N, by = Date], by = "Date")
full25 <- n_by[N.x == 25L & N.y == 25L, Date]
say("both-25 월: %d / %d", length(full25), nrow(G))
ret_l <- returns_dt[, .(Date, Ticker, Ret_1m)]
SETS <- merge(W_EW[Date %in% full25, .(Date, Ticker, inC = TRUE)],
              W_M01[Date %in% full25, .(Date, Ticker, inS = TRUE)],
              by = c("Date", "Ticker"), all = TRUE)
SETS[is.na(inC), inC := FALSE][is.na(inS), inS := FALSE]
SETS <- merge(SETS, ret_l, by = c("Date", "Ticker"), all.x = TRUE)
SETS[is.na(Ret_1m), Ret_1m := 0]   # canonical NA→0 동일 규칙 (항등 유지)
OVER <- SETS[, .(overlap = sum(inC & inS), k_in = sum(inC & !inS)), by = Date]
say("overlap: mean %.1f/25 (min %d, max %d) | 잠식 slot 평균 %.1f",
    mean(OVER$overlap), min(OVER$overlap), max(OVER$overlap), mean(OVER$k_in))

# 항등: d_gross = (1/25)(Σ_IN r − Σ_OUT r)
ID <- SETS[, .(d_id = (sum(Ret_1m[inC & !inS]) - sum(Ret_1m[!inC & inS])) / 25), by = Date]
ID <- merge(ID, G[, .(Date, d_gross)], by = "Date")
say("항등 검증: max|d_id − d_gross| = %.2e", max(abs(ID$d_id - ID$d_gross)))
stopifnot(max(abs(ID$d_id - ID$d_gross)) < 1e-10)

# ── 5. M1 slot 잠식 — advocate 귀속 ──────────────────────────────────────────
ZW <- dcast(ZL_T[!is.na(z)], Date + Ticker ~ Factor_Name, value.var = "z")
SETS <- merge(SETS, ZW, by = c("Date", "Ticker"), all.x = TRUE)
zcols <- intersect(TUNED_F, names(SETS))
adv_of <- function(sd) {
  m <- as.matrix(sd)
  apply(m, 1L, function(r) {
    ok <- which(is.finite(r))
    if (!length(ok)) NA_character_ else zcols[ok[which.max(r[ok])]]
  })
}
SETS[, advocate := adv_of(.SD), .SDcols = zcols]
OUTBAR <- SETS[!inC & inS, .(r_out_bar = mean(Ret_1m)), by = Date]
INS <- merge(SETS[inC & !inS], OUTBAR, by = "Date")
INS[, contrib := (Ret_1m - r_out_bar) / 25]
M1_attr <- INS[, .(n_picks = .N, contrib_ann_pct = 100 * sum(contrib) / length(full25) * 12,
                   mean_excess_vs_out = mean(Ret_1m - r_out_bar)), by = advocate][order(contrib_ann_pct)]
say("M1 advocate 귀속 (IN 종목의 대변 팩터별 실현 기여, %%/yr):")
print(M1_attr)
neg_contrib <- M1_attr[advocate %in% NEG_F, sum(contrib_ann_pct)]
tot_gap_ann <- 100 * mean(ID$d_gross) * 12
say("M1: NEG 팩터 advocate 기여 %+.2f%%/yr / 총 gross gap %+.2f%%/yr (share %.0f%%)",
    neg_contrib, tot_gap_ann, 100 * neg_contrib / tot_gap_ann)
d_inout <- ID$d_id
m1_t <- nw_t(d_inout)
say("M1: IN-vs-OUT 격차 NW t = %+.2f", m1_t)

# ── 6. M2 평균화 뭉갬 — M01 백분위 + 꼬리 기울기 ─────────────────────────────
M01P <- SC_M01[, .(Date, Ticker, m01_pct = frank(score) / .N), by = Date
               ][, .(Date, Ticker, m01_pct)]
CP <- merge(W_EW[, .(Date, Ticker)], M01P, by = c("Date", "Ticker"), all.x = TRUE)
say("M2: 합성 top-25의 M01 백분위 — median %.3f / mean %.3f / P(>=0.9) %.2f / M01결측 %.3f",
    median(CP$m01_pct, na.rm = TRUE), mean(CP$m01_pct, na.rm = TRUE),
    mean(CP$m01_pct >= 0.9, na.rm = TRUE), mean(is.na(CP$m01_pct)))

# M01 자체 rank-bucket 기울기 (liq filter 후 구현가능 순위 기준)
SL <- merge(SC_M01, liq_dt, by = c("Date", "Ticker"), all.x = TRUE)
SL <- SL[is.na(adv) | adv >= 2e8][, adv := NULL]
setorder(SL, Date, -score)
SL[, rk := seq_len(.N), by = Date]
SL <- merge(SL, ret_l, by = c("Date", "Ticker"), all.x = TRUE)
SL <- merge(SL, bench_dt, by = "Date")
SL[, act := Ret_1m - BM_Ret]
BK <- SL[!is.na(act) & rk <= 100,
         .(b1 = mean(act[rk <= 25]), b2 = mean(act[rk > 25 & rk <= 50]),
           b3 = mean(act[rk > 50])), by = Date]
m2_grad_t <- nw_t(BK$b1 - BK$b2)
say("M2: M01 bucket 월평균 active — 1-25 %+.3f%% / 26-50 %+.3f%% / 51-100 %+.3f%% | (b1-b2) NW t=%+.2f",
    100 * mean(BK$b1, na.rm = TRUE), 100 * mean(BK$b2, na.rm = TRUE),
    100 * mean(BK$b3, na.rm = TRUE), m2_grad_t)

# 보조: 합성 픽을 M01 백분위 구간별로 실현 기여 분해
CPR <- merge(CP, ret_l, by = c("Date", "Ticker"), all.x = TRUE)
CPR <- merge(CPR, bench_dt, by = "Date")
CPR[, act := Ret_1m - BM_Ret]
CPQ <- CPR[!is.na(m01_pct) & !is.na(act),
           .(mean_act = mean(act), n = .N),
           by = .(bucket = cut(m01_pct, c(0, .5, .8, .9, 1), include.lowest = TRUE))][order(bucket)]
say("M2 보조: 합성 픽의 M01 백분위 구간별 실현 active:")
print(CPQ)

# ── 7. M3 커버리지 이질 ──────────────────────────────────────────────────────
univ_n <- UNIV[, .(n_univ = .N), by = Date]
COV <- rbindlist(lapply(TUNED_F, function(f)
  score_of(f)[!is.na(score), .(n_f = .N, Factor_Name = f), by = Date]))
COV <- merge(COV, univ_n, by = "Date")
COV[, cov_rel := n_f / n_univ]
COVW <- dcast(COV, Date ~ Factor_Name, value.var = "cov_rel", fill = 0)
covm <- as.matrix(COVW[, ..TUNED_F])
gap_vs_max <- 1 - covm / apply(covm, 1, max)
het_share  <- mean(apply(gap_vs_max, 1, max) > 0.20)          # 최대격차>20% 월 비중
absent_share <- colMeans(covm == 0)
say("M3: 최대격차>20%% 월 비중 %.2f | 팩터 통째 결측월 share: %s",
    het_share, paste(TUNED_F, sprintf("%.2f", absent_share), collapse = " "))
het <- data.table(Date = COVW$Date, het_sd = apply(covm, 1, sd))
HG <- merge(het, G[, .(Date, d_gross)], by = "Date")
HG[, terc := cut(het_sd, quantile(het_sd, c(0, 1/3, 2/3, 1)), include.lowest = TRUE, labels = c("lo", "mid", "hi"))]
m3_fit <- lm(d_gross ~ I(terc == "hi"), data = HG[terc %in% c("lo", "hi")])
m3_t <- tryCatch(as.numeric(lmtest::coeftest(m3_fit,
  vcov. = sandwich::NeweyWest(m3_fit, lag = 3, prewhite = FALSE))[2, 3]), error = function(e) NA_real_)
say("M3: d_gross by het tercile — lo %+.3f%% / hi %+.3f%% (월평균) | hi-lo NW t=%+.2f",
    100 * HG[terc == "lo", mean(d_gross)], 100 * HG[terc == "hi", mean(d_gross)], m3_t)
zshare <- ZL_T[!is.na(z)][W_EW[, .(Date, Ticker)], on = c("Date", "Ticker"), nomatch = 0][
  , .(abs_z_share = sum(abs(z))), by = Factor_Name][, share := abs_z_share / sum(abs_z_share)][]
say("M3: 합성 선택분 |z| 기여 share: %s",
    paste(zshare$Factor_Name, sprintf("%.3f", zshare$share), collapse = " "))

# ── 8. POS2 probe (사전등록 예측 고정 — 진단 전용 canonical 1회) ─────────────
SC_POS2 <- ZL_T[Factor_Name %in% POS_F & !is.na(z), {
  if (.N >= 2L) .(score = mean(z)) else .(score = NA_real_)
}, by = .(Date, Ticker)][!is.na(score), .(Date, Ticker, score)]
FEAT_POS2 <- list(node_count = 4, max_depth = 3, free_param_count = 0,
  distinct_field_count = 2, conditional_op_count = 0, window_variety = 2,
  restatement_exposure = 0, escape_leaf_count = 2, escape_leaf_types = list("STORED_SCORE"),
  note = "mechanism probe: EW of WT-009 tuned M01_PATHQ + V01_SECREL (전거: WT-021 preregistration.json)")
bt_pos2 <- canonical_screen_bt(SC_POS2, returns_dt, bench_dt, top_n = 25L,
  cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
  run_id = "WT-D20260802_021", strategy_id = "WT_D20260802_021_POS2_EW",
  diag_dual_basis = TRUE, size_dt = size_dt, ast_features = FEAT_POS2)
ew2 <- bt_pos2$diag_ew_universe
say("POS2: PORT_t=%+.3f netSR=%+.3f TO=%.1f/yr n=%d | EWuni t=%+.2f post17=%+.2f oos~%.2f",
    bt_pos2$portfolio_alpha_t_nw_lag3, bt_pos2$net_sr, bt_pos2$turnover_annual,
    bt_pos2$n_months, ew2$portfolio_alpha_t_nw_lag3 %||% NA_real_,
    ew2$post2017_t_nw_lag3 %||% NA_real_, ew2$oos_retention_approx %||% NA_real_)
pp <- as.data.table(bt_pos2$period_returns)
ps <- as.data.table(R15$bt$C3_SINGLE$period_returns)
PM <- merge(pp[, .(date, x = ret_net - benchmark_ret)],
            ps[, .(date, y = ret_net - benchmark_ret)], by = "date")
PM[, d := x - y]
pos2_vs_single_t <- nw_t(PM$d)
say("POS2 vs single paired: NW t=%+.2f (%+.2f%%/yr, n=%d)",
    pos2_vs_single_t, 100 * mean(PM$d) * 12, nrow(PM))
gap_recovery <- (bt_pos2$portfolio_alpha_t_nw_lag3 - 0.338) / (2.050 - 0.338)
say("POS2 gap 회복률(PORT_t 기준): %.0f%% (사전 예측: M1 지배면 >=60%%)", 100 * gap_recovery)

# ── 9. Grinold 3항 대조 — 팩터별 rank-IC vs 전이(PORT_t) ─────────────────────
ic_of <- function(fname) {
  d <- merge(score_of(fname), returns_dt, by = c("Date", "Ticker"))
  d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman")), n = .N), by = Date]
}
GRIN <- rbindlist(lapply(TUNED_F, function(f) {
  ic <- ic_of(f)$ic
  data.table(Factor = f, mean_ic = mean(ic, na.rm = TRUE),
             icir = mean(ic, na.rm = TRUE) / sd(ic, na.rm = TRUE),
             ic_nw_t = nw_t(ic))
}))
# standalone canonical PORT_t (WT-009 실측 승계 — 재계산 금지)
GRIN[, port_t_wt009 := c(1.42, 2.05, -1.73, -0.212, 0.315)[match(Factor, TUNED_F)]]
GRIN[, transfer_sign_break := (mean_ic > 0) != (port_t_wt009 > 0)]
say("Grinold 대조표:")
print(GRIN)

# ── 10. 저장 ─────────────────────────────────────────────────────────────────
sc_after <- ast_sidecar_status()
slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(
  parity = c(ew = par_ew, m01 = par_m01),
  gap = list(gross_ann = mean(G$d_gross) * 12, net_ann = mean(G$d_net) * 12,
             t_net = nw_t(G$d_net), t_gross = nw_t(G$d_gross), n = nrow(G)),
  overlap = OVER, m1 = list(attr = M1_attr, neg_contrib_ann = neg_contrib,
                            tot_gap_ann = tot_gap_ann, inout_t = m1_t),
  m2 = list(pct_median = median(CP$m01_pct, na.rm = TRUE),
            pct_mean = mean(CP$m01_pct, na.rm = TRUE),
            pct_ge90 = mean(CP$m01_pct >= 0.9, na.rm = TRUE),
            bucket_means = colMeans(BK[, .(b1, b2, b3)], na.rm = TRUE),
            grad_t = m2_grad_t, comp_by_m01_bucket = CPQ),
  m3 = list(het_share = het_share, absent_share = absent_share,
            terc_lo = HG[terc == "lo", mean(d_gross)], terc_hi = HG[terc == "hi", mean(d_gross)],
            hi_lo_t = m3_t, zshare = zshare),
  pos2 = c(slim(bt_pos2), list(paired_vs_single_t = pos2_vs_single_t,
           paired_mean_ann = mean(PM$d) * 12, gap_recovery = gap_recovery)),
  grinold = GRIN, d_series = G, het_series = HG,
  sidecar = list(before = sc_before[c("live", "live_with_ast")],
                 after = sc_after[c("live", "live_with_ast")])
), file.path(OUT, "wt021_results.rds"))
write_parquet(SC_EW, file.path(OUT, "alpha_scores.parquet"))
say("완료 — wt021_results.rds + alpha_scores.parquet")
