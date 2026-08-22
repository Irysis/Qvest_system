## WT-D20260822_009 — 저-absorb 배제 유니버스 필터 (측정)
## 사전등록: stage_artifacts/WT-D20260822_009/PREREG.json (측정 전 고정)
## base = cleanT1 production_parity_verified score_eff top-25 cap_norm(Size), anchor 3.0583
## primary = 동일 하네스 + absorb 하위 20% 배제 (X 단일 고정)
## 판정 = ΔIR >= +0.05 + paired NW lag-3 t + 발동률 + liq 긴장
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_009")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(f, ...) cat(sprintf(paste0("[m] ", f, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")

nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]),
    error = function(e) NA_real_)
}
ym_add <- function(ym, k) {
  y <- as.integer(substr(ym,1,4)); m <- as.integer(substr(ym,6,7)) + k
  y <- y + (m-1L) %/% 12L; m <- (m-1L) %% 12L + 1L
  sprintf("%04d-%02d", y, m)
}
R <- list()

## ── 1. 입력 ────────────────────────────────────────────────────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret); bench <- as.data.table(SI$bench)
liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
for (dt in list(fwd_ret, bench, liqf, SIZE)) dt[, Date := as.Date(Date)]

CLEAN <- as.data.table(read_parquet(
  "05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1] == "production_parity_verified")   # §7b 라벨 게이트

P <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))
P[, Date := as.Date(Date)]
AB <- P[is.finite(absorb), .(Date, Ticker, absorb)]
say("입력: CLEAN %d행/%d월, absorb %d행/%d월", nrow(CLEAN), uniqueN(CLEAN$Date),
    nrow(AB), uniqueN(AB$Date))

## ── 2. parity2 경로 VERBATIM ───────────────────────────────────────────────
cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}

d0map <- data.table(d0 = sort(unique(fwd_ret$Date)))[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN)[, map_ym := format(Date - 1, "%Y-%m")]
CLd <- merge(CL, d0map, by.x = "map_ym", by.y = "ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date = d0, Ticker, sc = score_eff)], SIZE,
            by = c("Date", "Ticker"))
S0 <- merge(S0, liqf, by = c("Date", "Ticker"), all.x = TRUE)
S0 <- S0[is.na(adv) | adv >= 2e8]

top25_capw <- function(S) {
  dd <- sort(unique(S$Date)); W <- vector("list", length(dd))
  for (i in seq_along(dd)) {
    sub <- S[Date == dd[i]]; if (nrow(sub) < 25) next
    setorder(sub, -sc); hd <- head(sub, 25)
    W[[i]] <- data.table(Date = dd[i], Ticker = hd$Ticker, w = cap_norm(hd$Size))
  }
  rbindlist(W)
}

## ── 3. base anchor STOP ────────────────────────────────────────────────────
Wb_full <- top25_capw(S0)
rb_full <- weighted_screen_bt(Wb_full, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT009_base_full", strategy_id = "WT009_base_full")
say("base anchor(%d m): PORT_t=%.4f (target 3.0583) IR=%.4f",
    rb_full$n_months, rb_full$portfolio_alpha_t_nw_lag3, rb_full$information_ratio)
if (abs(rb_full$portfolio_alpha_t_nw_lag3 - 3.0583) > 0.01)
  stop("ANCHOR FAIL — 사전등록 STOP 조건. 측정 무효.")
R$base_anchor <- list(port_t = rb_full$portfolio_alpha_t_nw_lag3, ir = rb_full$information_ratio,
                      n_months = rb_full$n_months, target = 3.0583, pass = TRUE)

## ── 4. paired 공통월 ───────────────────────────────────────────────────────
common_d0 <- sort(intersect(unique(S0$Date), unique(AB$Date)))
S <- S0[Date %in% common_d0]
say("paired 공통월 %d (base %d 중)", length(common_d0), uniqueN(S0$Date))

## ── 5. 필터 (X = 0.20 사전 단일 고정, 하위분위 배제) ───────────────────────
SM <- merge(S, AB, by = c("Date", "Ticker"), all.x = TRUE)
mk_filter <- function(SM, X) {
  S2 <- copy(SM)
  S2[, thr := { v <- absorb[is.finite(absorb)]
                if (length(v) >= 30L) quantile(v, X, type = 7, names = FALSE) else -Inf },
     by = Date]
  S2[, excluded := is.finite(absorb) & absorb <= thr]
  S2
}
SMx <- mk_filter(SM, 0.20)
cov_tab <- SMx[, .(n_cand = .N, n_fin = sum(is.finite(absorb)), n_ex = sum(excluded),
                   n_left = sum(!excluded)), by = Date]
say("필터 X=20%%: 월평균 후보 %.0f / absorb 커버 %.1f%% / 배제 %.1f / 잔여 %.0f (min %d)",
    cov_tab[, mean(n_cand)], 100*cov_tab[, sum(n_fin)/sum(n_cand)],
    cov_tab[, mean(n_ex)], cov_tab[, mean(n_left)], cov_tab[, min(n_left)])
R$coverage <- list(mean_cand = cov_tab[, mean(n_cand)], absorb_coverage = cov_tab[, sum(n_fin)/sum(n_cand)],
                   mean_excluded = cov_tab[, mean(n_ex)], mean_left = cov_tab[, mean(n_left)],
                   min_left = cov_tab[, min(n_left)], months = nrow(cov_tab))

## criteria iii — liq 긴장
short_m <- cov_tab[n_left < 25]
say("liq 긴장: 배제 후 후보<25 월 = %d", nrow(short_m))
R$liq_tension <- list(months_lt25 = nrow(short_m), share = nrow(short_m)/nrow(cov_tab),
                      primary_void = (nrow(short_m)/nrow(cov_tab) > 0.05))
stopifnot(!R$liq_tension$primary_void)

## ── 6. base vs filtered (cap-w primary) ────────────────────────────────────
Wb <- top25_capw(S)
Wf <- top25_capw(SMx[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rb <- weighted_screen_bt(Wb, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT009_base", strategy_id = "WT009_base_common")
rf <- weighted_screen_bt(Wf, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT009_filt", strategy_id = "WT009_filtered_absorbLo20")
pb <- as.data.table(rb$period_returns)[, .(date, ab = ret_net - benchmark_ret)]
pf <- as.data.table(rf$period_returns)[, .(date, af = ret_net - benchmark_ret)]
PD <- merge(pb, pf, by = "date")[, d_active := af - ab]
delta_ir <- rf$information_ratio - rb$information_ratio
paired_t <- nw_t(PD$d_active)
say("base    : PORT_t=%+.3f IR=%+.4f absSR=%+.3f absCAGR=%+.2f%% TO=%.0f%%",
    rb$portfolio_alpha_t_nw_lag3, rb$information_ratio, rb$abs_net_sr, 100*rb$abs_cagr, 100*rb$turnover_annual)
say("filtered: PORT_t=%+.3f IR=%+.4f absSR=%+.3f absCAGR=%+.2f%% TO=%.0f%%",
    rf$portfolio_alpha_t_nw_lag3, rf$information_ratio, rf$abs_net_sr, 100*rf$abs_cagr, 100*rf$turnover_annual)
say("★ ΔIR=%+.4f (기준 +0.05) | paired NW t=%+.3f | mean Δactive %+.5f/월 (연 %+.3f%%p) n=%d",
    delta_ir, paired_t, PD[, mean(d_active)], 1200*PD[, mean(d_active)], nrow(PD))

grab <- function(r) list(port_t = r$portfolio_alpha_t_nw_lag3, ir = r$information_ratio,
  net_sr = r$net_sr, abs_net_sr = r$abs_net_sr, abs_cagr = r$abs_cagr,
  turnover_annual = r$turnover_annual, n_months = r$n_months, metric_type = "weighted_screen")
R$base <- grab(rb); R$filtered <- grab(rf)
R$paired <- list(delta_ir = delta_ir, paired_nw_t = paired_t,
  mean_d_active = PD[, mean(d_active)], sd_d_active = PD[, sd(d_active)],
  annual_pp = 1200*PD[, mean(d_active)], n = nrow(PD),
  basis = "screen-IR (cap-w top25 cap_norm, net 15bps) — book recon NAV IR 아님")

## ── 7. 발동 실효성 ─────────────────────────────────────────────────────────
hb <- Wb[, .(set = list(sort(Ticker))), by = Date]
hf <- Wf[, .(set = list(sort(Ticker))), by = Date]
hh <- merge(hb, hf, by = "Date", suffixes = c("_b","_f"))
hh[, n_diff := mapply(function(a,b) length(setdiff(a,b)), set_b, set_f)]
bexc <- merge(Wb[, .(Date, Ticker)], SMx[, .(Date, Ticker, excluded)], by = c("Date","Ticker"), all.x = TRUE)
firing <- bexc[, .(n_cut = sum(excluded, na.rm = TRUE)), by = Date]
eff <- merge(hh[, .(Date, n_diff)], firing, by = "Date")
say("발동: 구성변화월 %.1f%% (%d/%d) / 월평균 교체 %.2f종 / base top-25 내 배제대상 평균 %.2f종 (max %d)",
    100*eff[, mean(n_diff>0)], eff[, sum(n_diff>0)], nrow(eff), eff[, mean(n_diff)],
    eff[, mean(n_cut)], eff[, max(n_cut)])
R$effectiveness <- list(fire_share = eff[, mean(n_diff>0)], months_fired = eff[, sum(n_diff>0)],
  months = nrow(eff), mean_swap = eff[, mean(n_diff)], mean_cut_in_base_top25 = eff[, mean(n_cut)],
  max_cut = eff[, max(n_cut)], honest_null_non_applicable = (eff[, mean(n_diff>0)] < 0.05))

## ── 8. lag1 스트레스 ───────────────────────────────────────────────────────
d0_all <- sort(unique(AB$Date)); idx <- setNames(seq_along(d0_all), as.character(d0_all))
ABlag <- copy(AB)[, i := idx[as.character(Date)] + 1L][i <= length(d0_all)]
ABlag <- ABlag[, .(Date = d0_all[i], Ticker, absorb)]
SMl <- mk_filter(merge(S, ABlag, by = c("Date","Ticker"), all.x = TRUE), 0.20)
Wfl <- top25_capw(SMl[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rfl <- weighted_screen_bt(Wfl, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT009_lag1", strategy_id = "WT009_filtered_lag1")
pfl <- as.data.table(rfl$period_returns)[, .(date, afl = ret_net - benchmark_ret)]
PDl <- merge(pb, pfl, by = "date")[, dl := afl - ab]
say("lag1: ΔIR=%+.4f paired t=%+.3f (base판 ΔIR=%+.4f t=%+.3f)",
    rfl$information_ratio - rb$information_ratio, nw_t(PDl$dl), delta_ir, paired_t)
R$lag1 <- list(delta_ir = rfl$information_ratio - rb$information_ratio, paired_t = nw_t(PDl$dl),
  port_t = rfl$portfolio_alpha_t_nw_lag3,
  note = "붕괴 시 동월 누출 의심. 단, WT-014 선례처럼 fast-decay 신호는 lag1 에서 정상적으로도 소멸한다 — 누출 판별은 strict-PIT A/B(assert_overlay_pit + 위반주입)와 병행 해석.")

## ── 9. X 민감도 (진단 병기 — 판정 사용 금지) ───────────────────────────────
xdiag <- list()
for (X in c(0.10, 0.30)) {
  SMd <- mk_filter(SM, X)
  Wfd <- top25_capw(SMd[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
  rfd <- weighted_screen_bt(Wfd, fwd_ret, bench, cost_bps_oneway = 15,
      run_id = sprintf("WT009_X%02d", round(100*X)), strategy_id = sprintf("WT009_X%02d_diag", round(100*X)))
  pfd <- as.data.table(rfd$period_returns)[, .(date, afd = ret_net - benchmark_ret)]
  PDd <- merge(pb, pfd, by = "date")[, dd := afd - ab]
  xdiag[[sprintf("X%02d", round(100*X))]] <- list(delta_ir = rfd$information_ratio - rb$information_ratio,
    paired_t = nw_t(PDd$dd), port_t = rfd$portfolio_alpha_t_nw_lag3, turnover_annual = rfd$turnover_annual)
  say("진단 X=%.0f%%: ΔIR=%+.4f paired t=%+.3f PORT_t=%+.3f", 100*X,
      xdiag[[sprintf("X%02d", round(100*X))]]$delta_ir, xdiag[[sprintf("X%02d", round(100*X))]]$paired_t,
      xdiag[[sprintf("X%02d", round(100*X))]]$port_t)
}
R$xdiag <- xdiag

## ── 10. 창 분해 (진단) ─────────────────────────────────────────────────────
cut201512 <- as.Date("2015-12-01")
wsplit <- list()
for (tag in c("pre201512","post201512")) {
  sel <- if (tag == "pre201512") PD$date < cut201512 else PD$date >= cut201512
  sub <- PD[sel]
  wsplit[[tag]] <- list(n = nrow(sub), mean_d_active = sub[, mean(d_active)],
    annual_pp = 1200*sub[, mean(d_active)], paired_t = nw_t(sub$d_active))
  say("창 %s: n=%d mean=%+.5f (연 %+.2f%%p) t=%+.3f", tag, nrow(sub),
      sub[, mean(d_active)], 1200*sub[, mean(d_active)], nw_t(sub$d_active))
}
R$window_split <- wsplit

## ── 11. EW dual-basis ──────────────────────────────────────────────────────
feats <- list(node_count = 4, max_depth = 3, free_param_count = 2, distinct_field_count = 2,
  conditional_op_count = 1, window_variety = 1, restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "배제필터 = WHERE(CS_RANK_PCT(SPECIAL_OP:absorb_3m) > 0.20) 게이트 x 저장 base score_eff. free_param = {창 3개월, X 0.20}")
sc_b <- S[, .(Date, Ticker, score = sc)]
sc_f <- SMx[excluded == FALSE, .(Date, Ticker, score = sc)]
size_pan <- SIZE[, .(Date, Ticker, Size)]
cb <- canonical_screen_bt(sc_b, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT009_ew_base", strategy_id = "WT009_ew_base",
    diag_dual_basis = TRUE, size_dt = size_pan)
cf <- canonical_screen_bt(sc_f, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT009_ew_filt", strategy_id = "WT009_ew_filtered",
    diag_dual_basis = TRUE, size_dt = size_pan, ast_features = feats)
say("EW top-25: base PORT_t=%+.3f IR=%+.4f | filt PORT_t=%+.3f IR=%+.4f (ΔIR=%+.4f)",
    cb$portfolio_alpha_t_nw_lag3, cb$information_ratio,
    cf$portfolio_alpha_t_nw_lag3, cf$information_ratio, cf$information_ratio - cb$information_ratio)
ewu_b <- cb$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_
ewu_f <- cf$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_
say("EW-유니버스 벤치 대비: base t=%+.3f filt t=%+.3f", ewu_b, ewu_f)
R$ew <- list(base = list(port_t = cb$portfolio_alpha_t_nw_lag3, ir = cb$information_ratio),
  filtered = list(port_t = cf$portfolio_alpha_t_nw_lag3, ir = cf$information_ratio),
  delta_ir = cf$information_ratio - cb$information_ratio,
  ew_universe_bench = list(base_t = ewu_b, filt_t = ewu_f),
  metric_type = "canonical_screen")

## ── 12. 국면 분해 (AX-001 v2 축) ───────────────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
PD[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
PDr <- merge(PD, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- PDr[!is.na(Category), .(n = .N, mean_d = mean(d_active), t_nw = nw_t(d_active)), by = Category]
say("--- 국면별 Δactive (filtered − base) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-10s n=%3d mean=%+.5f t=%+.2f", reg_tab$Category[i], reg_tab$n[i], reg_tab$mean_d[i], reg_tab$t_nw[i])
R$regime <- as.list(split(reg_tab, seq_len(nrow(reg_tab))))
R$regime_tab <- reg_tab

## ── 13. screening tier (screen_pass 1절 — 계약 산출 SR/CAGR) ───────────────
sp_first <- (rf$abs_net_sr >= 0.7 && rf$abs_cagr >= 0.12)
sp_first_b <- (rb$abs_net_sr >= 0.7 && rb$abs_cagr >= 0.12)
say("screen_pass 1절(SR>=0.7 & CAGR>=12%%): filtered %s (SR %.3f CAGR %.2f%%) | base %s (SR %.3f CAGR %.2f%%)",
    sp_first, rf$abs_net_sr, 100*rf$abs_cagr, sp_first_b, rb$abs_net_sr, 100*rb$abs_cagr)
R$screening <- list(clause1_pass_filtered = sp_first, clause1_pass_base = sp_first_b,
  abs_net_sr_filtered = rf$abs_net_sr, abs_cagr_filtered = rf$abs_cagr,
  caveat = "run_hurdle_gate() 는 일별 sim_result(strategy_xts/DAILY_NAV_DT)를 요구한다 — alpha 단계 산출물이 아니라 forge 산출물이다. 여기서는 screen_pass 정의의 **1절(SR>=0.7 AND ann_ret>=0.12)** 만 계약 산출치(abs_net_sr/abs_cagr, weighted_screen_bt)로 평가했다. 2절(total_score>=40 AND SR>=0.5)은 18-component 채점이 필요해 alpha 단계 미산출. 따라서 clause1_pass=TRUE 는 screen_pass 충족의 **충분조건**(1절 단독 통과), FALSE 는 미결(2절 미평가).")

saveRDS(list(rb = rb, rf = rf, rfl = rfl, PD = PD, SMx = SMx, S = S, Wb = Wb, Wf = Wf,
             cov_tab = cov_tab, eff = eff, cb = cb, cf = cf),
        file.path(OUT, "10_measure_objects.rds"))
write_json(R, file.path(OUT, "10_measure.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
