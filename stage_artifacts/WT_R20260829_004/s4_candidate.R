# S4 — 실투형 후보 1건 구성·측정 + 검정력 계약 + 오버레이 PIT 4항(양성대조 포함)
# 단일 측정 규율: arm 배터리 없음. A0 는 F1/F2 가 검정한 슬리브이자 승계 좌표(2/20 cell4)이며
#   여기서는 F6/F7 상태 판정의 기준선으로만 재사용한다(새 arm 생성 아님).
suppressWarnings(suppressMessages({library(data.table); library(jsonlite)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/canonical_screen_bt.R"))
source(file.path(ROOT, "02_Infrastructure/validation/overlay_pit_guard.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
P <- readRDS(file.path(OUT, "panel.rds")); O2 <- readRDS(file.path(OUT, "s2_objects.rds"))
S <- O2$S; SIG <- O2$SIG; sv <- O2$sv
fwd <- P$fwd; SIZE <- P$SIZE
R <- as.data.table(fwd$returns_dt)[!is.na(Ret_1m)]; BENCH <- as.data.table(fwd$bench_dt)
TOPN <- 25L; POOL_MULT <- 2L; POOL_N <- TOPN*POOL_MULT; COST_BPS <- 15; PPY <- 12L
POOL_OFFSET <- 100

## ── 후보 점수 구성 (AST 와 1:1) ───────────────────────────────────────────────
#  비패닉월: score = CS_ZSCORE(momentum)
#  패닉월  : score = 100 * pool_indicator + CS_ZSCORE(-vol126)
#            pool_indicator = CLIP(51 - CS_RANK(momentum), 0, 1)   (CS_RANK: 1 = 최고 점수)
zsc <- function(x) { m <- mean(x, na.rm=TRUE); s <- stats::sd(x, na.rm=TRUE)
                     if (!is.finite(s) || s == 0) rep(0, length(x)) else (x-m)/s }
build_scores <- function(panic_map, label) {
  E <- merge(S, sv[, .(Date, Ticker, vol126_ann)], by = c("Date","Ticker"), all.x = TRUE)
  E[, signal_ym := format(Date, "%Y-%m")]
  E <- merge(E, panic_map, by = "signal_ym", all.x = TRUE)
  E[is.na(panic_use), panic_use := 0L]
  E[, rank_mom := frank(-score, ties.method = "first"), by = Date]
  E[, pool := pmin(pmax((POOL_N + 1L) - rank_mom, 0), 1)]
  E[, z_mom := zsc(score), by = Date]
  # 패닉월 z(-vol)은 pool 내부에서 산출(정의역 = 교체 후보 집합) — vol 결측은 pool 탈락
  E[, z_negvol := 0]
  E[panic_use == 1L & pool == 1L, z_negvol := zsc(-vol126_ann), by = Date]
  E[panic_use == 1L & pool == 1L & !is.finite(vol126_ann), `:=`(pool = 0, z_negvol = 0)]
  E[, score_final := fifelse(panic_use == 1L, POOL_OFFSET*pool + z_negvol, z_mom)]
  E[, label := label][]
}
panic_now  <- SIG[is.finite(panic), .(signal_ym, panic_use = panic)]
panic_lag1 <- copy(SIG)[order(signal_ym)][, panic_use := shift(panic, 1L)][
                        is.finite(panic_use), .(signal_ym, panic_use)]
# 위반 주입(양성 대조): 신호를 홀딩월 자신의 데이터로 계산한 것과 동형 = panic 을 1개월 앞당김
panic_viol <- copy(SIG)[order(signal_ym)][, panic_use := shift(panic, -1L)][
                        is.finite(panic_use), .(signal_ym, panic_use)]
panic_none <- SIG[is.finite(panic), .(signal_ym, panic_use = 0L)]

E_cand <- build_scores(panic_now,  "candidate")
E_base <- build_scores(panic_none, "A0_unconditional")
E_lag1 <- build_scores(panic_lag1, "lag1_stress")
E_viol <- build_scores(panic_viol, "violation_probe_sameMonth")

## ── 측정: canonical_screen_bt (top-25 EW · long-only · 15bps) ────────────────
sel_top <- function(E, n = TOPN) {
  x <- copy(E); setorder(x, Date, -score_final)
  x[, .(Ticker = Ticker[seq_len(min(n, .N))]), by = Date]
}
measure <- function(E, rid) {
  cs <- canonical_screen_bt(E[, .(Date, Ticker, score = score_final)], R, BENCH,
                            top_n = TOPN, cost_bps_oneway = COST_BPS, liq_dt = NULL,
                            run_id = rid, strategy_id = rid,
                            diag_dual_basis = TRUE, size_dt = SIZE)
  hold <- sel_top(E)
  pr <- as.data.table(cs$period_returns)
  setnames(pr, names(pr), sub("^date$", "Date", names(pr)))
  pr <- merge(pr[, .(Date, ret_net)], BENCH[, .(Date, BM_Ret)], by = "Date")[order(Date)]
  r <- pr$ret_net; n <- length(r)
  nav <- cumprod(1+r); peak <- cummax(nav); mdd <- min(nav/peak - 1)
  cagr <- prod(1+r)^(PPY/n) - 1
  sr <- mean(r)/stats::sd(r)*sqrt(PPY)
  act <- r - pr$BM_Ret
  fit <- lm(r ~ pr$BM_Ret); ct <- coeftest(fit, vcov = NeweyWest(fit, lag=3, prewhite=FALSE))
  list(cs = cs, pr = pr, hold = hold, n_months = n,
       port_t = cs$portfolio_alpha_t_nw_lag3, ir = cs$information_ratio,
       alpha_ann_vs_bm = cs$alpha_annualized,
       sr = sr, cagr = cagr, mdd = mdd, calmar = cagr/abs(mdd),
       net_active_sr = mean(act)/stats::sd(act)*sqrt(PPY),
       turnover_annual = cs$turnover_annual,
       beta = unname(ct[2,1]), alpha_beta_ctl_ann = PPY*unname(ct[1,1]),
       t_alpha_beta_ctl = unname(ct[1,3]),
       ew_univ_port_t = cs$diag_ew_universe$portfolio_alpha_t_nw_lag3,
       cap_share = cs$diag_cap_tier$weight_share_avg,
       n_names_max = max(hold[, .N, by = Date]$N))
}
M_cand <- measure(E_cand, "wt004_candidate")
M_base <- measure(E_base, "wt004_A0_unconditional")
M_lag1 <- measure(E_lag1, "wt004_lag1_stress")
M_viol <- measure(E_viol, "wt004_violation_probe")

## ── 부분기간 (F6: post-2017 단독) ────────────────────────────────────────────
sub_metrics <- function(M, from) {
  pr <- M$pr[Date >= as.Date(from)]; r <- pr$ret_net; n <- length(r)
  nav <- cumprod(1+r); mdd <- min(nav/cummax(nav) - 1); cagr <- prod(1+r)^(PPY/n)-1
  fit <- lm(r ~ pr$BM_Ret); ct <- coeftest(fit, vcov=NeweyWest(fit, lag=3, prewhite=FALSE))
  list(n = n, sr = mean(r)/stats::sd(r)*sqrt(PPY), cagr = cagr, mdd = mdd,
       calmar = cagr/abs(mdd), alpha_beta_ctl_ann = PPY*unname(ct[1,1]),
       t_alpha_beta_ctl = unname(ct[1,3]), beta = unname(ct[2,1]))
}
post_cand <- sub_metrics(M_cand, "2017-01-01"); post_base <- sub_metrics(M_base, "2017-01-01")

## ── 검정력 계약 (블록 부트스트랩 block=12, SR/Calmar 는 비율통계량) ──────────
PB <- merge(M_cand$pr[, .(Date, rc = ret_net)], M_base$pr[, .(Date, rb = ret_net)], by="Date")[order(Date)]
blk <- 12L; nb <- nrow(PB); nblk <- ceiling(nb/blk); B <- 4000L
set.seed(20260829L)
stat_pair <- function(rc, rb) {
  f <- function(r) { n <- length(r); nav <- cumprod(1+r); mdd <- min(nav/cummax(nav)-1)
                     cg <- prod(1+r)^(PPY/n)-1
                     c(sr = mean(r)/stats::sd(r)*sqrt(PPY), calmar = cg/abs(mdd)) }
  a <- f(rc); b <- f(rb); c(d_sr = a[["sr"]]-b[["sr"]], d_calmar = a[["calmar"]]-b[["calmar"]])
}
starts_all <- seq_len(nb - blk + 1L)
boot <- matrix(NA_real_, B, 2)
for (b in seq_len(B)) {
  st <- sample(starts_all, nblk, replace = TRUE)
  idx <- unlist(lapply(st, function(s) s:(s+blk-1L)))[seq_len(nb)]
  boot[b, ] <- stat_pair(PB$rc[idx], PB$rb[idx])
}
se_sr <- stats::sd(boot[,1], na.rm=TRUE); se_cal <- stats::sd(boot[,2], na.rm=TRUE)
T_THR <- 2.8016
DECAY <- 0.5   # 구성 레버 < 노출 레버 — KR 앵커의 절반으로 감쇠(사전등록)
KR_SR_GAIN <- 0.31           # L-AS-BSC_20260611 faithful L/S: SR 0.580 -> 0.761
KR_MDD_REDUC <- 1 - 0.272/0.529   # 52.9% -> 27.2%
implied_sr  <- DECAY * KR_SR_GAIN * M_base$sr
implied_cal <- DECAY * M_base$calmar * (1/(1-KR_MDD_REDUC) - 1)
pw <- function(implied, se) { mde <- T_THR*se; ratio <- implied/mde
  list(implied = implied, se_blockboot = se, mde80 = mde, ratio = ratio,
       expected_t = ratio*T_THR, power = pnorm(ratio*T_THR - 1.96)) }
power_calmar <- pw(implied_cal, se_cal); power_sr <- pw(implied_sr, se_sr)
obs_d_sr <- M_cand$sr - M_base$sr; obs_d_cal <- M_cand$calmar - M_base$calmar

## ── 오버레이 PIT 4항 ────────────────────────────────────────────────────────
sigm <- SIG[is.finite(panic)]
assert_overlay_pit(sigm$used_cutoff, sigm$holding_month_start, label = "candidate_regime")
ab_strict <- overlay_lookahead_ab(M_cand$calmar, M_cand$calmar, "Calmar(current vs strict)")
ab_probe  <- overlay_lookahead_ab(M_viol$calmar, M_cand$calmar, "Calmar(violation probe vs strict)")
ab_probe_sr <- overlay_lookahead_ab(M_viol$sr, M_cand$sr, "SR(violation probe vs strict)")
lag1_rel_calmar <- (M_lag1$calmar - M_cand$calmar)/abs(M_cand$calmar)
lag1_rel_sr <- (M_lag1$sr - M_cand$sr)/abs(M_cand$sr)

## ── 회전율/발화 진단 ────────────────────────────────────────────────────────
hc <- copy(M_cand$hold); hb <- copy(M_base$hold)
ov <- merge(hc[, .(Date, Ticker)], hb[, .(Date, Ticker, inbase = TRUE)], by=c("Date","Ticker"), all.x=TRUE)
ovm <- ov[, .(overlap = sum(!is.na(inbase))/.N), by = Date]
ovm[, signal_ym := format(Date, "%Y-%m")]
ovm <- merge(ovm, panic_now, by="signal_ym", all.x=TRUE)

res <- list(
  meta = list(wt_id="WT-R20260829_004", as_of="2026-08-29", metric_type="canonical_screen",
              measurement_authority="canonical_screen_bt (screening 실측) — SR/Calmar 판정 권위는 forge build_bt_result",
              single_measurement_discipline="arm 배터리 없음. A0 = F1/F2 슬리브이자 승계 좌표(2/20 cell4), lag1/violation 은 PIT 계기(F8) 이지 대비 arm 아님",
              spec = list(top_n=TOPN, pool_n=POOL_N, pool_multiplier=POOL_MULT,
                          pool_offset=POOL_OFFSET, weight="EW (Sigma w = 1, 현금 0, 레버리지 0)",
                          cost_bps_oneway=COST_BPS, liq_min=2e8, liq_ruler=fwd$liq_ruler,
                          universe="KOSPI200 U KOSDAQ150 (PIT 시변)", start="2005-01-01",
                          vol_estimator="종목 단변량 실현변동성 126거래일 연율 — 공분산/위험기여 추정 아님(Risk agent 경계)")),
  candidate = M_cand[c("n_months","port_t","ir","alpha_ann_vs_bm","sr","cagr","mdd","calmar",
                       "net_active_sr","turnover_annual","beta","alpha_beta_ctl_ann",
                       "t_alpha_beta_ctl","ew_univ_port_t","n_names_max")],
  A0_succession_coordinate = M_base[c("n_months","port_t","ir","alpha_ann_vs_bm","sr","cagr","mdd",
                                      "calmar","net_active_sr","turnover_annual","beta",
                                      "alpha_beta_ctl_ann","t_alpha_beta_ctl","ew_univ_port_t","n_names_max")],
  cap_tier = list(candidate = M_cand$cap_share, A0 = M_base$cap_share),
  firing = list(n_panic_months = sum(panic_now$panic_use),
                mean_overlap_panic = ovm[panic_use==1, mean(overlap)],
                mean_overlap_nonpanic = ovm[panic_use==0, mean(overlap)],
                note="비패닉월 overlap 1.0 = 후보가 그 달 A0 와 동일 보유(비발화가 정상)"),
  F6_post2017 = list(candidate = post_cand, A0 = post_base,
                     rule = "post-2017 단독 구간에서 후보의 Calmar 가 A0 대비 음이면 HARD reject (L-AS-BSC_20260611 next_probe 흡수)",
                     d_calmar = post_cand$calmar - post_base$calmar,
                     d_sr = post_cand$sr - post_base$sr,
                     status = if (post_cand$calmar - post_base$calmar >= 0) "PASS" else "FAIL"),
  F7_alpha_guard = list(rule = "beta-통제 alpha 가 무조건화 대비 -1.0%p 초과 하락하면 reject",
                        candidate_alpha_ann = M_cand$alpha_beta_ctl_ann,
                        A0_alpha_ann = M_base$alpha_beta_ctl_ann,
                        delta_pp = 100*(M_cand$alpha_beta_ctl_ann - M_base$alpha_beta_ctl_ann),
                        status = if (100*(M_cand$alpha_beta_ctl_ann - M_base$alpha_beta_ctl_ann) > -1.0) "PASS" else "FAIL"),
  power_contract = list(
    target_primary = "Calmar 차", target_secondary = "SR 차",
    se_method = "블록 부트스트랩 block=12 (SR/Calmar 는 비율통계량 — 순열 MDE 무효)",
    B = B, n_months = nb,
    effect_size_root = list(kr_anchor = "L-AS-BSC_20260611 (KR faithful L/S): SR 0.580->0.761 (+31%) · MDD 52.9%->27.2%",
                            decay_applied = DECAY,
                            decay_rationale = "구성 레버(현금 0)는 노출 레버(현금 스케일링)보다 좁다 — KR 앵커의 절반으로 사전 감쇠. US 헤드라인 사용 금지(약 2.7배 낙관)"),
    calmar = power_calmar, sharpe = power_sr,
    observed_d_calmar = obs_d_cal, observed_d_sr = obs_d_sr,
    disposition_rule = "ratio<0.15 = 착수금지구간 / 0.15~0.70 = 조건부(미결 최빈) / >=0.70 = 통상",
    disposition = if (power_calmar$ratio < 0.15) "BELOW_LAUNCH_THRESHOLD" else if (power_calmar$ratio < 0.70) "CONDITIONAL" else "NORMAL"),
  overlay_pit_F8 = list(
    item1_assert_overlay_pit = list(status="PASS", n_rows=nrow(sigm),
      max_used_cutoff=as.character(max(sigm$used_cutoff)),
      rule="used_cutoff <= holding_month_start (first-day-of-holding-month)"),
    item2_lag1_stress = list(calmar_lag1=M_lag1$calmar, calmar_base=M_cand$calmar,
      rel_change_calmar=lag1_rel_calmar, sr_lag1=M_lag1$sr, rel_change_sr=lag1_rel_sr,
      status = if (is.finite(lag1_rel_calmar) && lag1_rel_calmar > -0.25) "NO_COLLAPSE" else "COLLAPSE_SUSPECT"),
    item3_strict_ab = list(current_equals_strict=TRUE, inflation=ab_strict$inflation,
      message=ab_strict$message,
      positive_control_violation_probe=list(
        description="패닉 신호를 1개월 앞당겨 홀딩월 자신의 데이터로 계산한 것과 동형(BearProb 실사고 재현)",
        calmar=M_viol$calmar, sr=M_viol$sr,
        inflation_calmar=ab_probe$inflation, lookahead_flag_calmar=ab_probe$lookahead_suspected,
        inflation_sr=ab_probe_sr$inflation, lookahead_flag_sr=ab_probe_sr$lookahead_suspected,
        reading="계기가 실제로 발화하는지의 양성 대조 — 발화하지 않으면 이 A/B 는 방어선이 아니다")),
    item4_cutoff_rule = list(rule="first-day-of-holding-month", used="signal_month_end + 1d",
      anchor_date_used=FALSE, realized_ym_used=FALSE)))
write_json(res, file.path(OUT, "s4_candidate.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
saveRDS(list(E_cand=E_cand, E_base=E_base, M_cand=M_cand, M_base=M_base, M_lag1=M_lag1,
             M_viol=M_viol, PB=PB, ovm=ovm, boot=boot), file.path(OUT, "s4_objects.rds"))

## period_returns_production.csv (신호월 라벨 명시 + 벤치마크)
PRD <- copy(M_cand$pr)[, .(signal_month_end = Date, signal_ym = format(Date, "%Y-%m"),
                           holding_ym = substr(format(as.Date(format(Date, "%Y-%m-01")) + 32L, "%Y-%m"), 1, 7),
                           ret_net = ret_net, benchmark_ret = BM_Ret)]
PRD <- merge(PRD, SIG[, .(signal_ym, panic)], by = "signal_ym", all.x = TRUE)
PRD <- merge(PRD, M_base$pr[, .(signal_month_end = Date, ret_net_A0_unconditional = ret_net)],
             by = "signal_month_end", all.x = TRUE)
setorder(PRD, signal_month_end)
fwrite(PRD, file.path(OUT, "period_returns_production.csv"))

cat("\n===== CANDIDATE (실투형 단일 후보) =====\n")
p <- function(nm, M) cat(sprintf("%-22s n=%3d | PORT_t=%+.3f | SR=%+.3f CAGR=%+.2f%% MDD=%.2f%% Calmar=%+.3f | b=%.3f a=%+.2f%%/yr t(a)=%+.3f | TO=%.2f nmax=%d\n",
  nm, M$n_months, M$port_t, M$sr, 100*M$cagr, 100*M$mdd, M$calmar, M$beta,
  100*M$alpha_beta_ctl_ann, M$t_alpha_beta_ctl, M$turnover_annual, M$n_names_max))
p("candidate", M_cand); p("A0(승계좌표)", M_base); p("lag1 stress", M_lag1); p("violation probe", M_viol)
cat(sprintf("\npanic months=%d · overlap(panic)=%.3f · overlap(nonpanic)=%.3f\n",
            sum(panic_now$panic_use), ovm[panic_use==1, mean(overlap)], ovm[panic_use==0, mean(overlap)]))
cat(sprintf("F6 post2017: cand Calmar=%+.3f SR=%+.3f | A0 Calmar=%+.3f SR=%+.3f | dCalmar=%+.3f -> %s\n",
            post_cand$calmar, post_cand$sr, post_base$calmar, post_base$sr,
            post_cand$calmar-post_base$calmar, res$F6_post2017$status))
cat(sprintf("F7 alpha guard: cand a=%+.2f%%/yr vs A0 a=%+.2f%%/yr  delta=%+.2f%%p -> %s\n",
            100*M_cand$alpha_beta_ctl_ann, 100*M_base$alpha_beta_ctl_ann,
            res$F7_alpha_guard$delta_pp, res$F7_alpha_guard$status))
cat(sprintf("\nPOWER Calmar: implied=%.4f SE=%.4f MDE80=%.4f ratio=%.4f E[t]=%.3f power=%.3f (obs d=%+.4f)\n",
            power_calmar$implied, power_calmar$se_blockboot, power_calmar$mde80,
            power_calmar$ratio, power_calmar$expected_t, power_calmar$power, obs_d_cal))
cat(sprintf("POWER SR    : implied=%.4f SE=%.4f MDE80=%.4f ratio=%.4f E[t]=%.3f power=%.3f (obs d=%+.4f)\n",
            power_sr$implied, power_sr$se_blockboot, power_sr$mde80,
            power_sr$ratio, power_sr$expected_t, power_sr$power, obs_d_sr))
cat(sprintf("disposition = %s\n", res$power_contract$disposition))
cat(sprintf("\nPIT F8: assert=PASS | lag1 dCalmar=%+.1f%% (%s) | strict A/B infl=%.4f | 위반주입 infl(Calmar)=%+.1f%% flag=%s\n",
            100*lag1_rel_calmar, res$overlay_pit_F8$item2_lag1_stress$status, ab_strict$inflation,
            100*ab_probe$inflation, ab_probe$lookahead_suspected))
