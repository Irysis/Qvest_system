# =============================================================================
# run_wt013_eval.R — WT-D20260802_013 M01_PATHQ_RESID vol-잔차 순수판 판별
#   사전등록: stage_artifacts/WT_D20260802_013/preregistration.json (측정 전 고정)
#   1. RESID 패널 생성 (월별 CS OLS: PATHQ_z ~ D03z, 잔차 = score)
#   2. placebo 5시드 (D03z → N(0,1) 치환, 동일 교집합 행)
#   3. canonical 실측: base M01 / PATHQ(parity) / RESID(dual-basis) / placebo 5 / lag1
#   4. paired NW lag-3: RESID vs base (primary) + PATHQ vs base (parity) + placebo vs base
#   5. 부기간 분해 + F2 재검(jump-기여) + vol-적재 정량화 + AX-001 + advisory
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_013/run_wt013_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(xts); library(PerformanceAnalytics)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260802_009")   # 승계 자산 (재계산 금지)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_013")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt013e] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/ast_sidecar.R")
sc_before <- ast_sidecar_status()
say("sidecar before: live=%d live_with_ast=%d", sc_before$live, sc_before$live_with_ast)

# ── 1. 승계 패널 로드 + RESID 생성 ──────────────────────────────────────────
BASE <- as.data.table(read_parquet(file.path(SRC, "base_panel.parquet")))
BASE[, Date := as.Date(Date)]
TUNED <- as.data.table(read_parquet(file.path(SRC, "tuned_panel.parquet")))
TUNED[, Date := as.Date(Date)]
SIG <- sort(unique(BASE$Date))

PQ <- TUNED[Factor_Name == "M01_PATHQ", .(Date, Ticker, p = score)]
DV <- BASE[Factor_Name == "D03_RealVol", .(Date, Ticker, d3 = z)]
M <- merge(PQ, DV, by = c("Date", "Ticker"))          # 교집합만 (사전등록)
M <- M[is.finite(p) & is.finite(d3)]
M[, n_m := .N, by = Date]
M <- M[n_m >= 50L][, n_m := NULL]                     # 월 유효쌍 >= 50
say("교집합: PATHQ %d행 / D03 %d행 -> 교집합 %d행 (%d개월, 커버율 %.1f%%)",
    nrow(PQ), nrow(DV), nrow(M), uniqueN(M$Date), 100 * nrow(M) / nrow(PQ))

# 월별 CS OLS 잔차 (b = cov/var 폐형식)
M[, `:=`(b = {
    vb <- var(d3)
    if (!is.finite(vb) || vb < 1e-12) 0 else cov(p, d3) / vb
  }), by = Date]
M[, resid := p - (mean(p) - b * mean(d3)) - b * d3, by = Date]
RESID <- M[is.finite(resid), .(Date, Ticker, score = resid)]
B_SERIES <- unique(M[, .(Date, b)])
say("RESID: %d행 | b_t 평균 %+.4f 중앙값 %+.4f", nrow(RESID),
    B_SERIES[, mean(b)], B_SERIES[, median(b)])
write_parquet(RESID, file.path(OUT, "resid_panel.parquet"))
write_parquet(B_SERIES, file.path(OUT, "vol_beta_series.parquet"))

# placebo 5시드 — 동일 교집합 행, D03z만 노이즈 치환 (사전등록 통제)
placebo_panel <- function(seed) {
  set.seed(seed)
  P <- copy(M)[, noise := rnorm(.N)]
  P[, `:=`(bn = {
      vb <- var(noise)
      if (!is.finite(vb) || vb < 1e-12) 0 else cov(p, noise) / vb
    }), by = Date]
  P[, resid_n := p - (mean(p) - bn * mean(noise)) - bn * noise, by = Date]
  P[is.finite(resid_n), .(Date, Ticker, score = resid_n)]
}

# ── 2. canonical 하네스 (WT-009 규격 그대로 — 유니버스 선-제한 포함) ────────
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
size_dt <- as.data.table(read_parquet(file.path(SRC, "size_panel.parquet")))
size_dt[, Date := as.Date(Date)]
say("harness: returns %d행 bench %d월", nrow(returns_dt), nrow(bench_dt))

restrict <- function(sc) merge(sc, UNIV, by = c("Date", "Ticker"))
score_named <- list(
  M01_Mom_12_1 = restrict(BASE[Factor_Name == "M01_Mom_12_1", .(Date, Ticker, score = z)]),
  M01_PATHQ    = restrict(TUNED[Factor_Name == "M01_PATHQ", .(Date, Ticker, score)]),
  M01_PATHQ_RESID = restrict(RESID))

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 12L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

feats_field <- list(node_count = 1, max_depth = 1, free_param_count = 0,
  distinct_field_count = 1, conditional_op_count = 0, window_variety = 0,
  restatement_exposure = 1, escape_leaf_count = 0, escape_leaf_types = list(),
  note = "registry FIELD 리프 (factor_db_monthly Z_Score_Aligned 그대로)")
FEATS <- list(
  M01_Mom_12_1 = feats_field,
  M01_PATHQ = list(node_count = 4, max_depth = 3, free_param_count = 3,
    distinct_field_count = 1, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 0, escape_leaf_count = 1, escape_leaf_types = list("SPECIAL_OP"),
    note = "WT-009 승계 — CS_ZSCORE(CS_WINSORIZE(SPECIAL_OP:path_efficiency_252_21))"),
  M01_PATHQ_RESID = list(node_count = 6, max_depth = 4, free_param_count = 3,
    distinct_field_count = 2, conditional_op_count = 0, window_variety = 1,
    restatement_exposure = 1, escape_leaf_count = 1, escape_leaf_types = list("SPECIAL_OP"),
    note = "CS_RESIDUALIZE(SPECIAL_OP:path_efficiency, FIELD:D03_RealVol) — 잔차화 1연산 추가"))

bt <- list()
for (a in names(score_named)) {
  r <- canonical_screen_bt(score_named[[a]], returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_013", strategy_id = paste0("WT_D20260802_013_", a),
        diag_dual_basis = TRUE, size_dt = size_dt, ast_features = FEATS[[a]])
  bt[[a]] <- r
  ew <- r$diag_ew_universe
  say("%-16s PORT_t=%+.2f netSR=%+.3f TO=%.0f%% n=%d | EWuni t=%+.2f post17=%+.2f",
      a, r$portfolio_alpha_t_nw_lag3, r$net_sr %||% NA,
      100 * (r$turnover_annual %||% NA), r$n_months,
      ew$portfolio_alpha_t_nw_lag3 %||% NA_real_, ew$post2017_t_nw_lag3 %||% NA_real_)
}

# placebo 5 arm (dual-basis 불요)
PLACEBO_BT <- list()
for (sd_ in 1:5) {
  pp <- restrict(placebo_panel(sd_))
  r <- canonical_screen_bt(pp, returns_dt, bench_dt, top_n = 25L,
        cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
        run_id = "WT-D20260802_013_placebo", strategy_id = sprintf("WT_D20260802_013_PLC%d", sd_),
        diag_dual_basis = FALSE)
  PLACEBO_BT[[sd_]] <- r
  say("placebo seed%d PORT_t=%+.2f n=%d", sd_, r$portfolio_alpha_t_nw_lag3, r$n_months)
}

# ── 3. paired (primary + parity + placebo) ──────────────────────────────────
active_of <- function(r) {
  pr <- as.data.table(r$period_returns)
  pr[, .(date, act = ret_net - benchmark_ret)]
}
paired_of <- function(rt, rb) {
  m <- merge(active_of(rt)[, .(date, at = act)], active_of(rb)[, .(date, ab = act)], by = "date")
  m[, d := at - ab]
  sub <- function(a, b) m[date >= a & date <= b, nw_t(d)]
  list(n_months = nrow(m), mean_d_annualized = mean(m$d) * 12, paired_t_nw = nw_t(m$d),
       sub_pre2015 = sub("1900-01-01", "2014-12-31"),
       sub_2015_19 = sub("2015-01-01", "2019-12-31"),
       sub_2020p = sub("2020-01-01", "2099-01-01"),
       sub_post2017 = sub("2017-01-01", "2099-01-01"),
       d_series = m)
}
P_RESID  <- paired_of(bt$M01_PATHQ_RESID, bt$M01_Mom_12_1)   # ★ primary
P_PATHQ  <- paired_of(bt$M01_PATHQ, bt$M01_Mom_12_1)         # parity (WT-009 +2.028 재현 확인)
P_RvsP   <- paired_of(bt$M01_PATHQ_RESID, bt$M01_PATHQ)      # 잔차화 순효과
P_PLC <- lapply(PLACEBO_BT, function(r) paired_of(r, bt$M01_Mom_12_1))
say("★ PRIMARY RESID vs base: paired t=%+.3f (n=%d, d %.2f%%/yr) | sub %+.2f / %+.2f / %+.2f | post17 %+.2f",
    P_RESID$paired_t_nw, P_RESID$n_months, 100 * P_RESID$mean_d_annualized,
    P_RESID$sub_pre2015, P_RESID$sub_2015_19, P_RESID$sub_2020p, P_RESID$sub_post2017)
say("parity PATHQ vs base: paired t=%+.3f (WT-009 기록 +2.028)", P_PATHQ$paired_t_nw)
say("RESID vs PATHQ: paired t=%+.3f", P_RvsP$paired_t_nw)
say("placebo paired t: %s", paste(sprintf("%+.2f", vapply(P_PLC, `[[`, numeric(1), "paired_t_nw")), collapse = " "))

# ── 4. vol-적재 정량화 + 직교성 (성과 무참조 기전 정보) ─────────────────────
cs_cor_m <- function(A, B) {
  m <- merge(A[, .(Date, Ticker, s1 = score)], B[, .(Date, Ticker, s2 = score)],
             by = c("Date", "Ticker"))
  m[, .(r = suppressWarnings(cor(s1, s2, method = "spearman")), n = .N), by = Date][n >= 50]
}
pq_sc <- PQ[, .(Date, Ticker, score = p)]
dv_sc <- DV[, .(Date, Ticker, score = d3)]
base_sc <- BASE[Factor_Name == "M01_Mom_12_1", .(Date, Ticker, score = z)]
cl <- list(
  pathq_vs_d03  = cs_cor_m(pq_sc, dv_sc),
  base_vs_d03   = cs_cor_m(base_sc, dv_sc),
  resid_vs_d03  = cs_cor_m(RESID, dv_sc),
  resid_vs_pathq = cs_cor_m(RESID, pq_sc),
  resid_vs_base = cs_cor_m(RESID, base_sc))
VOLLOAD <- lapply(cl, function(x) list(mean = x[, mean(r, na.rm = TRUE)],
                                        t_nw = nw_t(x$r), n = nrow(x)))
say("vol-적재: cor(PATHQ,D03)=%.3f (t=%+.1f) | cor(base,D03)=%.3f | cor(RESID,D03)=%.3f | cor(RESID,PATHQ)=%.3f",
    VOLLOAD$pathq_vs_d03$mean, VOLLOAD$pathq_vs_d03$t_nw, VOLLOAD$base_vs_d03$mean,
    VOLLOAD$resid_vs_d03$mean, VOLLOAD$resid_vs_pathq$mean)

# ── 5. F2 재검 (jump-기여, WT-009 규격 그대로 — base vs RESID) ──────────────
common_m <- sort(intersect(
  score_named$M01_Mom_12_1[, .N, by = Date][N >= 100, Date],
  score_named$M01_PATHQ_RESID[, .N, by = Date][N >= 100, Date]))
common_m <- as.Date(common_m, origin = "1970-01-01")
top25 <- function(arm, d) {
  sc <- score_named[[arm]][Date == d]
  lq <- liq_dt[Date == d & adv >= 2e8, Ticker]
  head(sc[Ticker %chin% lq][order(-score)], 25L)$Ticker
}
D <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
      col_select = c("Date", "Ticker", "Ret")))
D[, Date := as.Date(Date)]
D <- D[Ticker %chin% unique(BASE$Ticker) & !is.na(Ret)]
setkey(D, Ticker, Date)
jump_contrib <- function(tk, d) {
  W <- D[Date > d - 550L & Date <= d & Ticker %chin% tk]
  W <- W[, tail(.SD, 252L), by = Ticker]
  ct <- W[, {
    n <- .N
    if (n < 252L) list(jc = NA_real_) else {
      lr <- log(1 + Ret[1:(n - 21L)]); lr <- lr[is.finite(lr)]
      net <- sum(lr)
      if (abs(net) < 0.05) list(jc = NA_real_) else {
        top5 <- order(-abs(lr))[1:5]
        list(jc = sum(lr[top5]) / net)
      }
    }
  }, by = Ticker]
  median(ct$jc, na.rm = TRUE)
}
t0 <- Sys.time()
f2_m <- rbindlist(lapply(as.list(common_m), function(d)
  data.table(Date = d, jc_base = jump_contrib(top25("M01_Mom_12_1", d), d),
             jc_resid = jump_contrib(top25("M01_PATHQ_RESID", d), d))))
F2 <- list(jc_base = f2_m[, mean(jc_base, na.rm = TRUE)],
           jc_resid = f2_m[, mean(jc_resid, na.rm = TRUE)],
           t_diff = nw_t(f2_m[, jc_base - jc_resid]))
say("F2재검 jump기여: base=%.3f resid=%.3f t(diff)=%+.2f (%.1f min)",
    F2$jc_base, F2$jc_resid, F2$t_diff,
    as.numeric(difftime(Sys.time(), t0, units = "mins")))

# ── 6. lag1 스트레스 (RESID) ────────────────────────────────────────────────
sig_idx <- setNames(seq_along(SIG), as.character(SIG))
l1 <- copy(score_named$M01_PATHQ_RESID)[, i := sig_idx[as.character(Date)] + 1L]
l1 <- l1[i <= length(SIG)][, Date := SIG[i]][, i := NULL]
r_l1 <- canonical_screen_bt(l1, returns_dt, bench_dt, top_n = 25L,
      cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
      run_id = "WT-D20260802_013_lag1", strategy_id = "WT_D20260802_013_RESID_lag1",
      diag_dual_basis = FALSE)
say("lag1 RESID: base_t=%+.2f -> lag1_t=%+.2f",
    bt$M01_PATHQ_RESID$portfolio_alpha_t_nw_lag3, r_l1$portfolio_alpha_t_nw_lag3)

# ── 7. AX-001 조건부 + MDD ──────────────────────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
AX001 <- list()
for (arm in c("M01_Mom_12_1", "M01_PATHQ", "M01_PATHQ_RESID")) {
  pr <- as.data.table(bt[[arm]]$period_returns)
  pr[, active := ret_net - benchmark_ret]
  pr[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
  pr <- merge(pr, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
  rg <- pr[!is.na(Category), .(n = .N, mean_active = mean(active), t_nw = nw_t(active)), by = Category]
  x <- xts::xts(as.data.table(bt[[arm]]$period_returns)$ret_net,
                order.by = as.Date(as.data.table(bt[[arm]]$period_returns)$date))
  AX001[[arm]] <- list(regime = rg, mdd = as.numeric(PerformanceAnalytics::maxDrawdown(x)))
  say("AX001 %-16s MDD=%.1f%%", arm, 100 * AX001[[arm]]$mdd)
}

# ── 8. advisory 진단 (RESID) ────────────────────────────────────────────────
diag_of <- function(arm) {
  d <- merge(score_named[[arm]], returns_dt, by = c("Date", "Ticker"))
  ics <- d[, .(ic = suppressWarnings(cor(score, Ret_1m, method = "spearman"))), by = Date]
  dec <- d[, {
    q <- cut(frank(score), breaks = 10, labels = FALSE)
    .(dec_rets = list(tapply(Ret_1m, q, mean)))
  }, by = Date]
  dm <- colMeans(do.call(rbind, dec$dec_rets), na.rm = TRUE)
  icm <- ics[, mean(ic, na.rm = TRUE)]; icsd <- ics[, sd(ic, na.rm = TRUE)]
  n <- ics[, sum(is.finite(ic))]
  list(rank_ic = icm, icir = icm / icsd, ic_t = icm / icsd * sqrt(n),
       monotonicity = suppressWarnings(cor(seq_along(dm), dm, method = "spearman")),
       ic_pre2015 = ics[Date <= "2014-12-31", mean(ic, na.rm = TRUE)],
       ic_2015_2019 = ics[Date >= "2015-01-01" & Date <= "2019-12-31", mean(ic, na.rm = TRUE)],
       ic_2020p = ics[Date >= "2020-01-01", mean(ic, na.rm = TRUE)])
}
DIAG <- lapply(setNames(names(score_named), names(score_named)), diag_of)
for (a in names(DIAG))
  say("adv %-16s IC=%+.4f ICIR=%+.3f mono=%+.2f", a, DIAG[[a]]$rank_ic,
      DIAG[[a]]$icir, DIAG[[a]]$monotonicity)

sc_after <- ast_sidecar_status()
say("sidecar after: live=%d live_with_ast=%d", sc_after$live, sc_after$live_with_ast)

# ── 9. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), c("benchmark_compare"))]
saveRDS(list(
  bt = lapply(bt, slim), lag1_t = r_l1$portfolio_alpha_t_nw_lag3,
  placebo_t = vapply(PLACEBO_BT, function(r) r$portfolio_alpha_t_nw_lag3, numeric(1)),
  paired_resid = P_RESID, paired_pathq_parity = P_PATHQ, paired_resid_vs_pathq = P_RvsP,
  paired_placebo = lapply(P_PLC, function(p) p[setdiff(names(p), "d_series")]),
  volload = VOLLOAD, volload_series = cl, b_series = B_SERIES,
  f2 = F2, f2_series = f2_m, ax001 = AX001, diag = DIAG, common_m = common_m,
  sidecar = list(before = sc_before[c("live", "live_with_ast")],
                 after = sc_after[c("live", "live_with_ast")])),
  file.path(OUT, "wt013_eval_results.rds"))
say("완료 — wt013_eval_results.rds")
