# =============================================================================
# run_wt014_eval.R — WT-D20260802_014 복권형 제외-필터 소비면 (FQ-103)
#   사전등록: stage_artifacts/WT_D20260802_014/preregistration.json (측정 전 고정)
#
#   base    = cleanT1 production_parity_verified 패널 score_eff top-25 cap_norm(Size)
#             (plumbing_fq044 p1 parity2 경로 VERBATIM — anchor 3.0583 재현 의무)
#   primary = 동일 하네스 + MAX5_63 상위 10% 제외-필터 (WT-010 ot_panel.max5 동결분)
#   판정    = ΔIR ≥ +0.05 + paired NW lag-3 t / 발동률 / liq 긴장
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_014/run_wt014_eval.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_014")
W10 <- file.path(ROOT, "stage_artifacts/WT_D20260802_010")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[wt014] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")   # contract + sidecar 경로
source("02_Infrastructure/contracts/weighted_screen_bt.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]
  if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}

# ── 1. 입력 로드 ─────────────────────────────────────────────────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
for (dt in list(fwd_ret, bench, liqf, SIZE)) dt[, Date := as.Date(Date)]

CLEAN <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1] == "production_parity_verified")   # §7b 라벨 게이트

PAN <- as.data.table(read_parquet(file.path(W10, "ot_panel.parquet")))
PAN[, Date := as.Date(Date)]
MAX5 <- PAN[is.finite(max5), .(Date, Ticker, max5)]
say("입력: CLEAN %d행/%d월, MAX5 %d행/%d월", nrow(CLEAN), uniqueN(CLEAN$Date),
    nrow(MAX5), uniqueN(MAX5$Date))

# ── 2. parity2 경로 VERBATIM — d0 매핑 + 후보 집합 ───────────────────────────
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}

d0map <- data.table(d0 = sort(unique(fwd_ret$Date))); d0map[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN); CL[, map_ym := format(Date - 1, "%Y-%m")]
CLd <- merge(CL, d0map, by.x = "map_ym", by.y = "ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date = d0, Ticker, sc = score_eff)], SIZE,
            by = c("Date", "Ticker"))
S0 <- merge(S0, liqf, by = c("Date", "Ticker"), all.x = TRUE)
S0 <- S0[is.na(adv) | adv >= 2e8]

top25_capw <- function(S) {
  dd <- sort(unique(S$Date)); W <- vector("list", length(dd))
  for (i in seq_along(dd)) {
    sub <- S[Date == dd[i]]
    if (nrow(sub) < 25) next
    setorder(sub, -sc)
    hd <- head(sub, 25)
    W[[i]] <- data.table(Date = dd[i], Ticker = hd$Ticker, w = cap_norm(hd$Size))
  }
  rbindlist(W)
}

# ── 3. base anchor 재현 (전 268월) — 3.0583 ± 0.01 필수 ──────────────────────
Wb_full <- top25_capw(S0)
rb_full <- weighted_screen_bt(Wb_full, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT014_base_full", strategy_id = "WT014_base_full")
say("base anchor(268m): PORT_t=%.4f (target 3.0583) IR=%.4f n=%d",
    rb_full$portfolio_alpha_t_nw_lag3, rb_full$information_ratio, rb_full$n_months)
if (abs(rb_full$portfolio_alpha_t_nw_lag3 - 3.0583) > 0.01)
  stop("ANCHOR FAIL — 하네스가 parity 기록을 재현하지 못함. 측정 무효 (사전등록 STOP 조건).")

# ── 4. paired 공통월 제한 (max5 가용 d0만) ───────────────────────────────────
common_d0 <- sort(intersect(unique(S0$Date), unique(MAX5$Date)))
S <- S0[Date %in% common_d0]
say("paired 공통월: %d (전체 %d 중; max5 시작 %s)", length(common_d0),
    uniqueN(S0$Date), as.character(min(common_d0)))

# ── 5. 필터 구성 (사전등록 X=10% 단일) ───────────────────────────────────────
SM <- merge(S, MAX5, by = c("Date", "Ticker"), all.x = TRUE)
mk_filter <- function(SM, X) {
  SM2 <- copy(SM)
  SM2[, thr := { v <- max5[is.finite(max5)]
                 if (length(v) >= 30L) quantile(v, 1 - X, type = 7, names = FALSE) else Inf },
      by = Date]
  SM2[, excluded := is.finite(max5) & max5 >= thr]
  SM2
}
SMx <- mk_filter(SM, 0.10)
cov_tab <- SMx[, .(n_cand = .N, n_finite = sum(is.finite(max5)), n_excl = sum(excluded)), by = Date]
say("필터: 월평균 후보 %.0f / max5 커버 %.1f%% / 배제 %.1f종",
    cov_tab[, mean(n_cand)], 100 * cov_tab[, sum(n_finite) / sum(n_cand)], cov_tab[, mean(n_excl)])

# ── 6. base(공통월) vs filtered 실측 + paired ────────────────────────────────
Wb <- top25_capw(S)
Wf <- top25_capw(SMx[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rb <- weighted_screen_bt(Wb, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT014_base", strategy_id = "WT014_base_common")
rf <- weighted_screen_bt(Wf, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT014_filt", strategy_id = "WT014_filtered_X10")
pb <- as.data.table(rb$period_returns)[, .(date, ab = ret_net - benchmark_ret)]
pf <- as.data.table(rf$period_returns)[, .(date, af = ret_net - benchmark_ret)]
PD <- merge(pb, pf, by = "date")
PD[, d_active := af - ab]
delta_ir  <- rf$information_ratio - rb$information_ratio
paired_t  <- nw_t(PD$d_active)
say("base(공통월):  PORT_t=%+.3f IR=%+.4f netSR=%+.3f TO=%.0f%%",
    rb$portfolio_alpha_t_nw_lag3, rb$information_ratio, rb$net_sr, 100 * rb$turnover_annual)
say("filtered X10: PORT_t=%+.3f IR=%+.4f netSR=%+.3f TO=%.0f%%",
    rf$portfolio_alpha_t_nw_lag3, rf$information_ratio, rf$net_sr, 100 * rf$turnover_annual)
say("★ ΔIR=%+.4f (기준 +0.05) | paired NW t=%+.3f | Δactive 평균 %+.5f/월 n=%d",
    delta_ir, paired_t, PD[, mean(d_active)], nrow(PD))

# ── 7. 발동 실효성 ───────────────────────────────────────────────────────────
hb <- Wb[, .(set = list(sort(Ticker))), by = Date]
hf <- Wf[, .(set = list(sort(Ticker))), by = Date]
hh <- merge(hb, hf, by = "Date", suffixes = c("_b", "_f"))
hh[, n_diff := mapply(function(a, b) length(setdiff(a, b)), set_b, set_f)]
# base top-25 중 배제 플래그 종목 수 (would-be 편입이 실제 잘린 수)
bexc <- merge(Wb[, .(Date, Ticker)], SMx[, .(Date, Ticker, excluded)],
              by = c("Date", "Ticker"), all.x = TRUE)
firing <- bexc[, .(n_cut = sum(excluded, na.rm = TRUE)), by = Date]
eff <- merge(hh[, .(Date, n_diff)], firing, by = "Date")
say("발동: 구성변화월 %.1f%% (%d/%d) / 월평균 교체 %.2f종 / base top-25 내 배제대상 평균 %.2f종 (max %d)",
    100 * eff[, mean(n_diff > 0)], eff[, sum(n_diff > 0)], nrow(eff),
    eff[, mean(n_diff)], eff[, mean(n_cut)], eff[, max(n_cut)])

# ── 8. liq 긴장 ──────────────────────────────────────────────────────────────
short_m <- SMx[excluded == FALSE, .N, by = Date][N < 25]
say("liq 긴장: 배제 후 후보<25종 월 = %d", nrow(short_m))

# ── 9. AX-001 위기월 분해 (hold_ym = d0월+1) ─────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym, 1, 4)); m <- as.integer(substr(ym, 6, 7)) + k
  y <- y + (m - 1L) %/% 12L; m <- (m - 1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
PD[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
PDr <- merge(PD, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- PDr[!is.na(Category),
               .(n = .N, mean_d = mean(d_active), t_nw = nw_t(d_active)), by = Category]
say("--- 국면별 Δactive (filtered − base) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-8s n=%3d mean=%+.5f t=%+.2f", reg_tab$Category[i], reg_tab$n[i],
      reg_tab$mean_d[i], reg_tab$t_nw[i])

# ── 10. lag1 스트레스 (max5 1개월 지연) ──────────────────────────────────────
d0_all <- sort(unique(MAX5$Date))
idx <- setNames(seq_along(d0_all), as.character(d0_all))
M5lag <- copy(MAX5)[, i := idx[as.character(Date)] + 1L][i <= length(d0_all)]
M5lag <- M5lag[, .(Date = d0_all[i], Ticker, max5)]
SMl <- mk_filter(merge(S, M5lag, by = c("Date", "Ticker"), all.x = TRUE), 0.10)
Wfl <- top25_capw(SMl[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rfl <- weighted_screen_bt(Wfl, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT014_lag1", strategy_id = "WT014_filtered_X10_lag1")
pfl <- as.data.table(rfl$period_returns)[, .(date, afl = ret_net - benchmark_ret)]
PDl <- merge(pb, pfl, by = "date")[, dl := afl - ab]
say("lag1: ΔIR=%+.4f paired t=%+.3f (base ΔIR=%+.4f t=%+.3f)",
    rfl$information_ratio - rb$information_ratio, nw_t(PDl$dl), delta_ir, paired_t)

# ── 11. X 민감도 (진단 병기만 — 선택 사용 금지) ──────────────────────────────
xdiag <- list()
for (X in c(0.05, 0.20)) {
  SMd <- mk_filter(SM, X)
  Wfd <- top25_capw(SMd[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
  rfd <- weighted_screen_bt(Wfd, fwd_ret, bench, cost_bps_oneway = 15,
      run_id = sprintf("WT014_X%02d", round(100 * X)),
      strategy_id = sprintf("WT014_filtered_X%02d_diag", round(100 * X)))
  pfd <- as.data.table(rfd$period_returns)[, .(date, afd = ret_net - benchmark_ret)]
  PDd <- merge(pb, pfd, by = "date")[, dd := afd - ab]
  xdiag[[sprintf("X%02d", round(100 * X))]] <-
    list(delta_ir = rfd$information_ratio - rb$information_ratio,
         paired_t = nw_t(PDd$dd), port_t = rfd$portfolio_alpha_t_nw_lag3,
         turnover_annual = rfd$turnover_annual)
  say("진단 X=%.0f%%: ΔIR=%+.4f paired t=%+.3f", 100 * X,
      xdiag[[sprintf("X%02d", round(100 * X))]]$delta_ir,
      xdiag[[sprintf("X%02d", round(100 * X))]]$paired_t)
}

# ── 12. EW dual-basis 병기 (canonical_screen_bt, ast sidecar 전달) ───────────
feats <- list(
  node_count = 4, max_depth = 3, free_param_count = 2,
  distinct_field_count = 1, conditional_op_count = 1, window_variety = 1,
  restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "제외-필터 = WHERE(CS_RANK_PCT(SPECIAL_OP:max5_63) < 0.90) 게이트 x 저장 base score. free_param = {window 63, X 0.10}"
)
sc_b <- S[, .(Date, Ticker, score = sc)]
sc_f <- SMx[excluded == FALSE, .(Date, Ticker, score = sc)]
size_pan <- as.data.table(read_parquet(file.path(W10, "size_panel.parquet")))
size_pan[, Date := as.Date(Date)]
cb <- canonical_screen_bt(sc_b, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT014_ew_base", strategy_id = "WT014_ew_base",
    diag_dual_basis = TRUE, size_dt = size_pan)
cf <- canonical_screen_bt(sc_f, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT014_ew_filt", strategy_id = "WT014_ew_filtered_X10",
    diag_dual_basis = TRUE, size_dt = size_pan, ast_features = feats)
say("EW top-25: base PORT_t=%+.3f IR=%+.4f | filtered PORT_t=%+.3f IR=%+.4f (ΔIR=%+.4f)",
    cb$portfolio_alpha_t_nw_lag3, cb$information_ratio,
    cf$portfolio_alpha_t_nw_lag3, cf$information_ratio,
    cf$information_ratio - cb$information_ratio)
say("EW-uni diag: base t=%+.2f filt t=%+.2f", cb$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA,
    cf$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA)

# ── 13. 반증 부수관측: 배제군 홀딩월 개인 순매수 vs 잔여 후보 ────────────────
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet"))
IV[, Date := as.Date(Date)]
IV <- IV[Ticker %chin% unique(SMx$Ticker), .(Date_d = Date, Ticker, indiv = Individual)]
IV[, hold_ym := format(Date_d, "%Y-%m")]
hold_flow <- IV[, .(flow = sum(indiv), nd = .N), by = .(hold_ym, Ticker)]
FL <- copy(SMx)[, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
FL <- merge(FL[, .(Date, hold_ym, Ticker, excluded, adv)], hold_flow, by = c("hold_ym", "Ticker"))
FL <- FL[is.finite(adv) & adv > 0 & nd > 0, .(Date, Ticker, excluded, fint = flow / (adv * nd))]
fsp <- FL[, .(spread = mean(fint[excluded]) - mean(fint[!excluded]),
              n_e = sum(excluded)), by = Date][is.finite(spread) & n_e >= 3]
fals_t <- nw_t(fsp$spread)
say("반증 부수관측: 배제군−잔여 홀딩월 개인순매수/ADV·일 스프레드 %+.6f, NW t=%+.2f (t<1 → 복권수요 기전 기각)",
    fsp[, mean(spread)], fals_t)

# ── 14. 저장 ─────────────────────────────────────────────────────────────────
slim <- function(r) r[setdiff(names(r), "benchmark_compare")]
saveRDS(list(
  base_full = slim(rb_full), base = slim(rb), filtered = slim(rf),
  paired = list(delta_ir = delta_ir, paired_t_nw_lag3 = paired_t,
                mean_d_active = PD[, mean(d_active)], n_months = nrow(PD)),
  effectiveness = list(fire_share = eff[, mean(n_diff > 0)],
                       mean_swap = eff[, mean(n_diff)],
                       mean_cut_in_base_top25 = eff[, mean(n_cut)],
                       max_cut = eff[, max(n_cut)], by_month = eff),
  coverage = cov_tab, liq_short_months = short_m,
  regime_tab = reg_tab, lag1 = list(delta_ir = rfl$information_ratio - rb$information_ratio,
                                    paired_t = nw_t(PDl$dl)),
  xdiag = xdiag,
  ew = list(base = slim(cb), filtered = slim(cf)),
  falsification = list(mean_spread = fsp[, mean(spread)], t_nw = fals_t, n_months = nrow(fsp)),
  paired_series = PD, feats = feats
), file.path(OUT, "wt014_eval_results.rds"))

EX <- SMx[, .(Date, Ticker, max5, excluded)]
write_parquet(EX, file.path(OUT, "alpha_scores.parquet"))   # 제외-필터 신호 패널
say("완료 — wt014_eval_results.rds + alpha_scores.parquet")
