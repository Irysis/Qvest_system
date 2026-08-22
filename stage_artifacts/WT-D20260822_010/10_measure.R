## WT-D20260822_010 — 규모-중립 배제 (본 측정)
## 사전등록: PREREG.json (본 실행 전 봉인) · 관문: PREREG_GATE.json → 00_precheck.json$gate PASS(0.1465)
## base = cleanT1 production_parity_verified score_eff top-25 cap_norm(Size), anchor 3.0583
## primary = 동일 하네스 + **직교화 축(score_orth) 하위 20% 배제** (X 는 WT-009 와 동일 고정)
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(PerformanceAnalytics); library(xts)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(f, ...) cat(sprintf(paste0("[m] ", f, "\n"), ...))
source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1)
  tryCatch(as.numeric(lmtest::coeftest(fit,
      vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1, 3]), error = function(e) NA_real_)
}
ym_add <- function(ym, k) { y <- as.integer(substr(ym,1,4)); m <- as.integer(substr(ym,6,7)) + k
  y <- y + (m-1L) %/% 12L; m <- (m-1L) %% 12L + 1L; sprintf("%04d-%02d", y, m) }
R <- list()

O <- readRDS(file.path(OUT, "00_precheck_objects.rds"))
SMx <- O$SMx; Wb <- O$Wb; S <- O$S; ORTH <- O$ORTH; common_d0 <- O$common_d0
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)]
bench <- as.data.table(SI$bench)[, Date := as.Date(Date)]
liqf <- as.data.table(SI$liqf)[, Date := as.Date(Date)]
SIZE <- as.data.table(SI$SIZE)[, Date := as.Date(Date)]
PC <- fromJSON(file.path(OUT, "00_precheck.json"))
stopifnot(isTRUE(PC$gate$pass))
R$gate_precondition <- list(ratio = PC$gate$ratio, threshold = PC$gate$threshold, pass = PC$gate$pass)

cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
top25_capw <- function(Sx) { dd <- sort(unique(Sx$Date)); W <- vector("list", length(dd))
  for (i in seq_along(dd)) { sub <- Sx[Date == dd[i]]; if (nrow(sub) < 25) next
    setorder(sub, -sc); hd <- head(sub, 25)
    W[[i]] <- data.table(Date = dd[i], Ticker = hd$Ticker, w = cap_norm(hd$Size)) }
  rbindlist(W) }
mk_filter <- function(SMin, X, col) { S2 <- copy(SMin)
  S2[, thr := { v <- get(col); v <- v[is.finite(v)]
                if (length(v) >= 30L) quantile(v, X, type = 7, names = FALSE) else -Inf }, by = Date]
  S2[, excluded := is.finite(get(col)) & get(col) <= thr]; S2 }

## ── 1. base vs filtered (cap-w primary / 판정 basis) ───────────────────────
Wf <- top25_capw(SMx[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rb <- weighted_screen_bt(Wb, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT010_base", strategy_id = "WT010_base_common")
rf <- weighted_screen_bt(Wf, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT010_filt", strategy_id = "WT010_filtered_orthAbsorbLo20")
pb <- as.data.table(rb$period_returns)[, .(date, ab = ret_net - benchmark_ret)]
pf <- as.data.table(rf$period_returns)[, .(date, af = ret_net - benchmark_ret)]
PD <- merge(pb, pf, by = "date")[, d_active := af - ab]
delta_ir <- rf$information_ratio - rb$information_ratio
paired_t <- nw_t(PD$d_active)
say("base    : PORT_t=%+.4f IR=%+.4f absSR=%+.3f absCAGR=%+.2f%% TO=%.0f%%",
    rb$portfolio_alpha_t_nw_lag3, rb$information_ratio, rb$abs_net_sr, 100*rb$abs_cagr, 100*rb$turnover_annual)
say("filtered: PORT_t=%+.4f IR=%+.4f absSR=%+.3f absCAGR=%+.2f%% TO=%.0f%%",
    rf$portfolio_alpha_t_nw_lag3, rf$information_ratio, rf$abs_net_sr, 100*rf$abs_cagr, 100*rf$turnover_annual)
say("★ ΔIR=%+.4f (게이트 +0.05) | paired NW t=%+.3f | mean Δactive %+.6f/월 (연 %+.4f%%p) n=%d",
    delta_ir, paired_t, PD[, mean(d_active)], 1200*PD[, mean(d_active)], nrow(PD))
say("   [WT-009 raw 축 대조: ΔIR -0.1153 / PORT_t 2.4348 / 연 -1.7262%%p]")
grab <- function(r) list(port_t = r$portfolio_alpha_t_nw_lag3, ir = r$information_ratio,
  net_sr = r$net_sr, abs_net_sr = r$abs_net_sr, abs_cagr = r$abs_cagr,
  turnover_annual = r$turnover_annual, n_months = r$n_months, metric_type = "weighted_screen")
R$base <- grab(rb); R$filtered <- grab(rf)
R$paired <- list(delta_ir = delta_ir, paired_nw_t = paired_t,
  mean_d_active = PD[, mean(d_active)], sd_d_active = PD[, sd(d_active)],
  annual_pp = 1200*PD[, mean(d_active)], n = nrow(PD),
  basis = "screen-IR (cap-w top25 cap_norm, net 15bps) — book recon NAV IR 아님",
  wt009_raw_reference = list(delta_ir = -0.115272463602773, port_t_filt = 2.43476408223255, annual_pp = -1.72618615026589))

## ── 2. 발동 실효성 ─────────────────────────────────────────────────────────
hb <- Wb[, .(set = list(sort(Ticker))), by = Date]; hf <- Wf[, .(set = list(sort(Ticker))), by = Date]
hh <- merge(hb, hf, by = "Date", suffixes = c("_b","_f"))
hh[, n_diff := mapply(function(a,b) length(setdiff(a,b)), set_b, set_f)]
bexc <- merge(Wb[, .(Date, Ticker)], SMx[, .(Date, Ticker, excluded)], by = c("Date","Ticker"), all.x = TRUE)
firing <- bexc[, .(n_cut = sum(excluded, na.rm = TRUE)), by = Date]
eff <- merge(hh[, .(Date, n_diff)], firing, by = "Date")
say("발동: 구성변화월 %.1f%% (%d/%d) / 월평균 교체 %.2f종 / base top-25 내 배제대상 %.2f종 (max %d)",
    100*eff[, mean(n_diff>0)], eff[, sum(n_diff>0)], nrow(eff), eff[, mean(n_diff)], eff[, mean(n_cut)], eff[, max(n_cut)])
R$effectiveness <- list(fire_share = eff[, mean(n_diff>0)], months_fired = eff[, sum(n_diff>0)],
  months = nrow(eff), mean_swap = eff[, mean(n_diff)], mean_cut_in_base_top25 = eff[, mean(n_cut)],
  max_cut = eff[, max(n_cut)], honest_null_non_applicable = (eff[, mean(n_diff>0)] < 0.05))

## ── 3. lag1 스트레스 ───────────────────────────────────────────────────────
d0_all <- sort(unique(ORTH$Date)); idx <- setNames(seq_along(d0_all), as.character(d0_all))
OL <- copy(ORTH)[, i := idx[as.character(Date)] + 1L][i <= length(d0_all)]
OL <- OL[, .(Date = d0_all[i], Ticker, score_orth)]
SMl <- mk_filter(merge(S, OL, by = c("Date","Ticker"), all.x = TRUE), 0.20, "score_orth")
Wfl <- top25_capw(SMl[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
rfl <- weighted_screen_bt(Wfl, fwd_ret, bench, cost_bps_oneway = 15,
    run_id = "WT010_lag1", strategy_id = "WT010_filtered_lag1")
pfl <- as.data.table(rfl$period_returns)[, .(date, afl = ret_net - benchmark_ret)]
PDl <- merge(pb, pfl, by = "date")[, dl := afl - ab]
say("lag1: ΔIR=%+.4f paired t=%+.3f PORT_t=%+.4f (base판 ΔIR=%+.4f t=%+.3f)",
    rfl$information_ratio - rb$information_ratio, nw_t(PDl$dl), rfl$portfolio_alpha_t_nw_lag3, delta_ir, paired_t)
R$lag1 <- list(delta_ir = rfl$information_ratio - rb$information_ratio, paired_t = nw_t(PDl$dl),
  port_t = rfl$portfolio_alpha_t_nw_lag3,
  note = "붕괴 시 동월 누출 의심. fast-decay 신호는 lag1 에서 정상적으로도 소멸 — strict-PIT A/B(assert_overlay_pit 268/268 + 위반주입 0/268)와 병행 해석.")

## ── 4. X 민감도 (진단 병기 — 판정 사용 금지) ───────────────────────────────
SM0 <- merge(S, ORTH, by = c("Date","Ticker"), all.x = TRUE)
xdiag <- list()
for (X in c(0.10, 0.30)) {
  SMd <- mk_filter(SM0, X, "score_orth")
  Wfd <- top25_capw(SMd[excluded == FALSE, .(Date, Ticker, sc, Size, adv)])
  rfd <- weighted_screen_bt(Wfd, fwd_ret, bench, cost_bps_oneway = 15,
      run_id = sprintf("WT010_X%02d", round(100*X)), strategy_id = sprintf("WT010_X%02d_diag", round(100*X)))
  pfd <- as.data.table(rfd$period_returns)[, .(date, afd = ret_net - benchmark_ret)]
  PDd <- merge(pb, pfd, by = "date")[, dd := afd - ab]
  k <- sprintf("X%02d", round(100*X))
  xdiag[[k]] <- list(delta_ir = rfd$information_ratio - rb$information_ratio, paired_t = nw_t(PDd$dd),
    port_t = rfd$portfolio_alpha_t_nw_lag3, turnover_annual = rfd$turnover_annual)
  say("진단 X=%.0f%%: ΔIR=%+.4f paired t=%+.3f PORT_t=%+.4f", 100*X,
      xdiag[[k]]$delta_ir, xdiag[[k]]$paired_t, xdiag[[k]]$port_t)
}
R$xdiag <- xdiag

## ── 5. 창 분해 (진단) ──────────────────────────────────────────────────────
cut201512 <- as.Date("2015-12-01"); wsplit <- list()
for (tag in c("pre201512","post201512")) {
  sel <- if (tag == "pre201512") PD$date < cut201512 else PD$date >= cut201512
  sub <- PD[sel]
  wsplit[[tag]] <- list(n = nrow(sub), mean_d_active = sub[, mean(d_active)],
    annual_pp = 1200*sub[, mean(d_active)], paired_t = nw_t(sub$d_active))
  say("창 %s: n=%d mean=%+.6f (연 %+.3f%%p) t=%+.3f", tag, nrow(sub),
      sub[, mean(d_active)], 1200*sub[, mean(d_active)], nw_t(sub$d_active))
}
R$window_split <- wsplit

## ── 6. basis 3종 — EW top-25 + EW-유니버스 벤치 ────────────────────────────
feats <- list(node_count = 6, max_depth = 4, free_param_count = 2, distinct_field_count = 4,
  conditional_op_count = 1, window_variety = 1, restatement_exposure = 0, escape_leaf_count = 1,
  escape_leaf_types = list("SPECIAL_OP"),
  note = "배제필터 = WHERE(CS_RANK_PCT(SPECIAL_OP:orth_absorb_3m) > 0.20) 게이트 x 저장 base score_eff. orth = 월별 횡단면 OLS 잔차(rank(win_vol)+rank(log_size) 통제). free_param = {창 3개월, X 0.20}")
sc_b <- S[, .(Date, Ticker, score = sc)]
sc_f <- SMx[excluded == FALSE, .(Date, Ticker, score = sc)]
size_pan <- SIZE[, .(Date, Ticker, Size)]
cb <- canonical_screen_bt(sc_b, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT010_ew_base", strategy_id = "WT010_ew_base",
    diag_dual_basis = TRUE, size_dt = size_pan)
cf <- canonical_screen_bt(sc_f, fwd_ret, bench, top_n = 25L, cost_bps_oneway = 15,
    liq_dt = liqf, liq_min = 2e8, run_id = "WT010_ew_filt", strategy_id = "WT010_ew_filtered",
    diag_dual_basis = TRUE, size_dt = size_pan, ast_features = feats)
ewu_b <- cb$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_
ewu_f <- cf$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_
say("EW top-25: base PORT_t=%+.4f IR=%+.4f | filt PORT_t=%+.4f IR=%+.4f (ΔIR=%+.4f)",
    cb$portfolio_alpha_t_nw_lag3, cb$information_ratio, cf$portfolio_alpha_t_nw_lag3,
    cf$information_ratio, cf$information_ratio - cb$information_ratio)
say("EW-유니버스 벤치 대비: base t=%+.4f filt t=%+.4f", ewu_b, ewu_f)
R$ew <- list(base = list(port_t = cb$portfolio_alpha_t_nw_lag3, ir = cb$information_ratio),
  filtered = list(port_t = cf$portfolio_alpha_t_nw_lag3, ir = cf$information_ratio),
  delta_ir = cf$information_ratio - cb$information_ratio,
  ew_universe_bench = list(base_t = ewu_b, filt_t = ewu_f),
  metric_type = "canonical_screen",
  binding = FALSE, note = "판정 basis 는 cap-w 고정(PREREG). EW 는 병기 진단 — 부호가 갈려도 판정 불변.")

## ── 7. MDD / calmar ────────────────────────────────────────────────────────
mkx <- function(r) xts(as.numeric(r$period_returns$ret_net), order.by = as.Date(r$period_returns$date))
mdd_b <- as.numeric(maxDrawdown(mkx(rb))); mdd_f <- as.numeric(maxDrawdown(mkx(rf)))
say("MDD(월간): base %.4f → filtered %.4f (Δ %+.4f%%p) | calmar %.4f → %.4f",
    mdd_b, mdd_f, 100*(mdd_b-mdd_f), rb$abs_cagr/mdd_b, rf$abs_cagr/mdd_f)
R$mdd <- list(base = mdd_b, filtered = mdd_f, delta_pp = 100*(mdd_b-mdd_f),
  calmar_base = rb$abs_cagr/mdd_b, calmar_filtered = rf$abs_cagr/mdd_f,
  caveat = "월간 수익 기반 MDD — 일별 NAV 기반 forge MDD 와 다름(월간은 낙폭 과소추정). metric_type=weighted_screen.",
  wt009 = list(calmar_base = 0.326704464537798, calmar_filtered = 0.291214446683798))

## ── 8. 국면 분해 (AX-001 v2 축, 진단) ──────────────────────────────────────
u <- as.data.table(read_parquet(".cache/unified_regime_signal.parquet"))[, .(Date = as.Date(Date), Category)]
u[, hold_ym := format(Date, "%Y-%m")]
PD[, hold_ym := ym_add(format(date, "%Y-%m"), 1L)]
PDr <- merge(PD, u[, .(hold_ym, Category)], by = "hold_ym", all.x = TRUE)
reg_tab <- PDr[!is.na(Category), .(n = .N, mean_d = mean(d_active), t_nw = nw_t(d_active)), by = Category]
say("--- 국면별 Δactive (filtered − base) ---")
for (i in seq_len(nrow(reg_tab)))
  say("  %-10s n=%3d mean=%+.6f t=%+.2f", reg_tab$Category[i], reg_tab$n[i], reg_tab$mean_d[i], reg_tab$t_nw[i])
R$regime_tab <- as.data.frame(reg_tab)

## ── 9. 치환 귀속 (노출 중립성의 본 측정 판) ────────────────────────────────
RET <- fwd_ret[, .(Date, Ticker, Ret_1m)]
SZr <- merge(SIZE[, .(Date, Ticker, Size)], data.table(Date = unique(Wb$Date)), by = "Date")
SZr[, srank := frank(Size)/.N, by = Date]
B <- merge(Wb, RET, by = c("Date","Ticker")); F_ <- merge(Wf, RET, by = c("Date","Ticker"))
kk <- function(d) paste(d$Date, d$Ticker)
B[, inF := kk(.SD) %chin% kk(F_)]; F_[, inB := kk(.SD) %chin% kk(B)]
rem <- B[inF == FALSE]; add <- F_[inB == FALSE]
rem <- merge(rem, SZr[, .(Date, Ticker, srank)], by = c("Date","Ticker"), all.x = TRUE)
add <- merge(add, SZr[, .(Date, Ticker, srank)], by = c("Date","Ticker"), all.x = TRUE)
nd <- uniqueN(B$Date)
say("치환: 제거 %.2f종(비중합 %.4f, srank %.3f) / 추가 %.2f종(비중합 %.4f, srank %.3f) | 비중합 비율 %.3f배",
    nrow(rem)/nd, rem[,sum(w)]/nd, rem[, mean(srank, na.rm=TRUE)],
    nrow(add)/nd, add[,sum(w)]/nd, add[, mean(srank, na.rm=TRUE)], (add[,sum(w)]/nd)/(rem[,sum(w)]/nd))
say("   [WT-009: 제거 비중합 0.0788 → 추가 0.1810 = 2.296배]")
say("   제거 평균수익 %+.4f 꼬리율 %.3f%% | 추가 평균수익 %+.4f 꼬리율 %.3f%%",
    rem[,mean(Ret_1m)], 100*rem[,mean(Ret_1m<=-0.20)], add[,mean(Ret_1m)], 100*add[,mean(Ret_1m<=-0.20)])
R$substitution <- list(mean_removed_names = nrow(rem)/nd, removed_weight_sum = rem[,sum(w)]/nd,
  mean_added_names = nrow(add)/nd, added_weight_sum = add[,sum(w)]/nd,
  weight_sum_ratio = (add[,sum(w)]/nd)/(rem[,sum(w)]/nd),
  removed_srank = rem[, mean(srank, na.rm=TRUE)], added_srank = add[, mean(srank, na.rm=TRUE)],
  removed_mean_ret = rem[,mean(Ret_1m)], added_mean_ret = add[,mean(Ret_1m)],
  added_minus_removed = add[,mean(Ret_1m)]-rem[,mean(Ret_1m)],
  removed_tail_rate = rem[,mean(Ret_1m<=-0.20)], added_tail_rate = add[,mean(Ret_1m<=-0.20)],
  removed_wcontrib = rem[,sum(w*Ret_1m)]/nd, added_wcontrib = add[,sum(w*Ret_1m)]/nd,
  removed_mean_w = rem[,mean(w)], added_mean_w = add[,mean(w)],
  wt009 = list(removed_weight_sum = 0.0788424064986886, added_weight_sum = 0.181040837075161, ratio = 2.29625))

## ── 10. 양성 대조 (MAX5 상위10% 배제, 동일 창·하네스) ──────────────────────
PANx <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_010/ot_panel.parquet"))[, Date := as.Date(Date)]
MAX5 <- PANx[is.finite(max5), .(Date, Ticker, max5)]
MM <- merge(SMx[, .(Date, Ticker, sc, Size, adv)], MAX5, by = c("Date","Ticker"), all.x = TRUE)
MM[, thr5 := { v <- max5[is.finite(max5)]; if (length(v) >= 30L) quantile(v, 0.90, type=7, names=FALSE) else Inf }, by = Date]
MM[, ex5 := is.finite(max5) & max5 >= thr5]
r5 <- weighted_screen_bt(top25_capw(MM[ex5 == FALSE, .(Date, Ticker, sc, Size, adv)]), fwd_ret, bench,
      cost_bps_oneway = 15, run_id = "WT010_pc_max5", strategy_id = "WT010_poscontrol_max5")
p5 <- as.data.table(r5$period_returns)[, .(date, a5 = ret_net - benchmark_ret)]
PD5 <- merge(pb, p5, by = "date")[, d := a5 - ab]
R$poscontrol <- list(delta_ir = r5$information_ratio - rb$information_ratio, paired_nw_t = nw_t(PD5$d),
  mean_d_active = mean(PD5$d), annual_pp = 1200*mean(PD5$d), n = nrow(PD5),
  port_t_pc = r5$portfolio_alpha_t_nw_lag3, port_t_base = rb$portfolio_alpha_t_nw_lag3,
  wt009_reference = list(delta_ir = 0.164172178623249, port_t_pc = 3.80239443710596),
  detected = isTRUE((r5$information_ratio - rb$information_ratio) >= 0.05),
  design = "동일 base·동일 하네스·동일 268월 창에서 기측정 양성(WT-014 MAX5 상위10% 배제) 재측정 = 검사기 전도성 확인")
say("양성대조 MAX5: ΔIR=%+.4f paired t=%+.3f PORT_t %.4f→%.4f | 검출=%s (WT-009 재측정 ΔIR +0.1642 / PORT_t 3.8024)",
    R$poscontrol$delta_ir, R$poscontrol$paired_nw_t, R$poscontrol$port_t_base, R$poscontrol$port_t_pc, R$poscontrol$detected)

## ── 11. screening tier 1절 ─────────────────────────────────────────────────
R$screening <- list(clause1_pass_filtered = (rf$abs_net_sr >= 0.7 && rf$abs_cagr >= 0.12),
  clause1_pass_base = (rb$abs_net_sr >= 0.7 && rb$abs_cagr >= 0.12),
  abs_net_sr_filtered = rf$abs_net_sr, abs_cagr_filtered = rf$abs_cagr,
  caveat = "run_hurdle_gate() 는 일별 sim_result 를 요구(forge 산출물). 여기서는 screen_pass 1절(SR>=0.7 AND ann_ret>=0.12)만 계약 산출치로 평가 — TRUE = 충족의 충분조건, FALSE = 미결(2절 미평가).")
say("screen_pass 1절: filtered %s (SR %.3f CAGR %.2f%%) | base %s",
    R$screening$clause1_pass_filtered, rf$abs_net_sr, 100*rf$abs_cagr, R$screening$clause1_pass_base)

## ── 12. 판정 ───────────────────────────────────────────────────────────────
R$verdict_inputs <- list(delta_ir = delta_ir, delta_ir_gate = 0.05, delta_ir_pass = (delta_ir >= 0.05),
  basis = "cap-w (고정)", ew_delta_ir_nonbinding = R$ew$delta_ir)
say("★★판정 입력: ΔIR(cap-w) %+.4f vs 게이트 +0.05 → %s | EW %+.4f (비바인딩)",
    delta_ir, ifelse(delta_ir >= 0.05, "PASS", "FAIL"), R$ew$delta_ir)

saveRDS(list(rb = rb, rf = rf, rfl = rfl, r5 = r5, PD = PD, SMx = SMx, S = S, Wb = Wb, Wf = Wf,
             eff = eff, cb = cb, cf = cf, ORTH = ORTH),
        file.path(OUT, "10_measure_objects.rds"))
write_json(R, file.path(OUT, "10_measure.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
