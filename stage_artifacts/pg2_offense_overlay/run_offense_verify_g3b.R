## ============================================================
## PG2 공격형 오버레이 Round 2.5 — G3b/G3a 검증 배터리 (pinned vintage)
## 도훈 지시 2026-07-02 후속. Round 2 승자 G3b(F5 세미분산 + Bull-state 총노출
## floor 1.0)의 견고성 검증: OOS retention v2 / placebo(state 순환시프트) /
## 신호지연 스트레스 / bullE×state 그리드 / DSR 진단 / 계약 bt_result / F3 재테스트.
## ============================================================
## vintage: benchmark_pinned_20260702.parquet (yfinance ^KS200 교차검증 완료 vintage 고정)
## PIT: canonical과 동일 (월말 신호 → 익월 적용 ym_next merge)
## selection: sweep 누적 기록 — R1 13 + R2 9 + R2.5 신규 5 (G3 grid 4 + F3_fixed 1) = 27
## metric_type = backtested(panel-overlay) / DSR·retention은 diagnostic-tier
##   (graduation-authoritative는 추후 forge/essence_score 경유 — measurement-graduation §1~3)
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
BM_PIN   <- Sys.getenv("BM_PIN", file.path(OUT_DIR, "benchmark_pinned_20260702.parquet"))
T_HALF <- 16L; PAPER_COEF <- c(a=0.13, d=0.79, e=-0.17, f=0.09); COST <- 0.0015

cat("[1] panel + pinned KOSPI 신호\n")
p <- fread(file.path(BASE_DIR, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym)
stopifnot(nrow(p) == 269)
bm <- as.data.table(read_parquet(BM_PIN))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]; bm[, Date := as.Date(Date)]
bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
cat(sprintf("    pinned vintage: %s ~ %s (%d일)\n", min(bm$Date), max(bm$Date), nrow(bm)))
r <- bm[[bcol]]; n <- length(r)
rm252 <- frollmean(r, 252, na.rm=TRUE); rs252 <- frollapply(r, 252, sd, na.rm=TRUE)
rhat <- pmin(pmax((r - rm252)/(rs252 + 1e-12), -20), 20); rhat[!is.finite(rhat)] <- NA
al <- 1 - exp(-1/T_HALF)
sig2d <- rep(NA_real_, n); accd <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) { dsq <- if (rhat[t] < 0) 2*rhat[t]^2 else 0
  accd <- al*dsq + (1-al)*accd; sig2d[t] <- accd }
N <- 6L*T_HALF; wn <- (0:N)*exp(-2*(0:N)/T_HALF); wn <- wn/sqrt(sum(wn^2))
phi <- rep(NA_real_, n)
for (t in (N+1):n) { seg <- rhat[(t-N):t]; if (all(is.finite(seg))) phi[t] <- pmin(pmax(sum(wn*rev(seg)),-2.5),2.5) }
bm[, phi_d := phi]                       # 컬럼 승격 (Round 2 phi_m 버그 수리 반영)
bm[, S_semi := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2d + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2*(phi<0)]
bm[, ym := format(Date, "%Y-%m")]
bm_x <- xts(bm[[bcol]], order.by=bm$Date)
mret <- apply.monthly(bm_x, Return.cumulative)
mdt <- data.table(ym=format(index(mret), "%Y-%m"), mret=as.numeric(mret))
mdt[, cum12 := frollapply(mret, 12, function(z) prod(1+z)-1)]
mdt[, cum2  := frollapply(mret, 2,  function(z) prod(1+z)-1)]
mdt[, cum1  := mret]
mk_state <- function(c12, cf) fifelse(!is.finite(c12) | !is.finite(cf), "NA",
  fifelse(c12 >= 0 & cf >= 0, "Bull", fifelse(c12 >= 0 & cf < 0, "Correction",
  fifelse(c12 < 0 & cf < 0, "Bear", "Rebound"))))
mdt[, state2 := mk_state(cum12, cum2)]; mdt[, state1 := mk_state(cum12, cum1)]
me <- bm[, .(S_semi=last(S_semi), phi_m=last(phi_d)), by=ym]
me <- merge(me, mdt[, .(ym, state2, state1)], by="ym", all.x=TRUE); setorder(me, ym)
me[, ym_next := format(as.Date(paste0(ym,"-01")) %m+% months(1), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_next, S_semi, phi_m, state2, state1)], by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
p[is.na(state2), state2 := "NA"]; p[is.na(state1), state1 := "NA"]
stopifnot(nrow(p) == 269)

cat("[2] F3 재진단 (phi_m 버그 수리 후 — 진짜 분포)\n")
der <- p[beta_faith < 1]
cat(sprintf("    β_faith<1 = %d개월 | phi_m>0 = %d (%.0f%%) | phi_m 분위: %s\n",
    nrow(der), der[phi_m > 0, .N], 100*der[phi_m > 0, .N]/max(nrow(der),1),
    paste(round(quantile(der$phi_m, c(0,.25,.5,.75,1), na.rm=TRUE),2), collapse=" / ")))

cat("[3] 매핑 + 변형군\n")
exp_pct <- function(x) { out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[seq_len(i-1)]; past <- past[is.finite(past)]
    if (length(past) >= 24 && is.finite(x[i])) out[i] <- mean(past < x[i]) }
  out }
p[, pct_semi := exp_pct(S_semi)]
freq <- prop.table(table(round(p$beta_AR,2))); lo <- sort(as.numeric(names(freq))[as.numeric(names(freq)) < 0.999])
cumf <- 0; thr <- list()
for (l in lo) { f <- as.numeric(freq[as.character(l)]); if (is.na(f)) f <- 0
  thr[[length(thr)+1]] <- c(l, 1-cumf-f, 1-cumf); cumf <- cumf+f }
map_freq <- function(pp){ if(!is.finite(pp)) return(1.0)
  for (tt in thr) if (pp >= tt[2] && pp < tt[3]) return(tt[1])
  if (length(lo) && pp >= 1-cumf) return(lo[1]); 1.0 }
b_f5 <- sapply(p$pct_semi, map_freq)

mk_E <- function(beta, r05, m4, bull_floor=NA, st_vec=p$state2) {
  E <- r05 * m4 * beta
  if (is.finite(bull_floor)) E <- ifelse(st_vec == "Bull", pmax(E, bull_floor), E)
  E }
ret_of <- function(E) { dE <- abs(E - shift(E, 1, fill=1.0)); list(ret=E*p$ret_orig - dE*COST, dE=dE) }
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn) }
ann_sr <- function(ret, idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(ret, order.by=idx), scale=12)[3,1])

E_list <- list(
  C1_incumbent = mk_E(p$beta_faith, p$beta_R05, p$m4),
  F5_base      = mk_E(b_f5, p$beta_R05, p$m4),
  F3_fixed     = { b3 <- p$beta_faith; b3[is.finite(p$phi_m) & p$phi_m > 0] <- 1.0; mk_E(b3, p$beta_R05, p$m4) },
  G1_bbt_pure  = { bg <- fifelse(p$state2=="Bull",1.0, fifelse(p$state2=="Correction",0.7, fifelse(p$state2=="Bear",0.4, 1.0))); mk_E(bg, p$beta_R05, p$m4) },
  G3_E70_s2    = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=0.70),
  G3a_E85_s2   = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=0.85),
  G3b_E100_s2  = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=1.00),
  G3_E70_s1    = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=0.70, st_vec=p$state1),
  G3_E85_s1    = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=0.85, st_vec=p$state1),
  G3_E100_s1   = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=1.00, st_vec=p$state1),
  G3b_lag1     = mk_E(b_f5, p$beta_R05, p$m4, bull_floor=1.00, st_vec=shift(p$state2, 1, fill="NA"))
)
R <- lapply(E_list, ret_of)
ret_c1 <- R$C1_incumbent$ret; ret_f5 <- R$F5_base$ret

res <- rbindlist(lapply(names(E_list), function(nm) {
  ret <- R[[nm]]$ret; x <- xts(ret, order.by=p$anchor_date)
  data.table(variant=nm,
    SR=round(ann_sr(ret),3), CAGR=round(as.numeric(Return.annualized(x, scale=12)),4),
    MDD=round(as.numeric(maxDrawdown(x)),4), Calmar=round(as.numeric(CalmarRatio(x, scale=12)),3),
    ret_2025=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2025"])),4),
    ret_2026=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"])),4),
    avg_expo=round(mean(E_list[[nm]], na.rm=TRUE),3), turnover_dE=round(sum(R[[nm]]$dE, na.rm=TRUE),2),
    nw_t_vs_C1=round(nw_t(ret - ret_c1),2), nw_t_vs_F5=round(nw_t(ret - ret_f5),2))
}))
cat("\n===== [4] 그리드 + 지연 스트레스 (pinned vintage) =====\n"); print(res, nrow=99)

cat("\n[5] OOS retention v2 (anchored 3분할 {55,65,75} 중앙값 — diagnostic-tier)\n")
oos_v2 <- function(ret) {
  ns <- length(ret); rs <- sapply(c(0.55, 0.65, 0.75), function(f) {
    k <- floor(ns*f); is_sr <- ann_sr(ret[1:k], p$anchor_date[1:k])
    oos_sr <- ann_sr(ret[(k+1):ns], p$anchor_date[(k+1):ns])
    if (!is.finite(is_sr) || abs(is_sr) < 1e-9) return(NA_real_); oos_sr/is_sr })
  list(splits=round(rs,3), median=round(median(rs, na.rm=TRUE),3)) }
oos_tbl <- rbindlist(lapply(c("C1_incumbent","F5_base","G3a_E85_s2","G3b_E100_s2"), function(nm) {
  z <- oos_v2(R[[nm]]$ret)
  data.table(variant=nm, split55=z$splits[1], split65=z$splits[2], split75=z$splits[3], oos_retention_v2=z$median) }))
print(oos_tbl)

cat("\n[6] Placebo — state2 순환시프트 200회 (G3b bull-floor를 가짜 state에 부여)\n")
set.seed(42)
sts <- p$state2; nm_ <- length(sts)
real_dsr <- ann_sr(R$G3b_E100_s2$ret) - ann_sr(ret_f5)
ks <- sample(24:(nm_-24), 200, replace=TRUE)
plc <- sapply(ks, function(k) {
  st_sh <- sts[((seq_len(nm_)-1+k) %% nm_)+1]
  ann_sr(ret_of(mk_E(b_f5, p$beta_R05, p$m4, bull_floor=1.00, st_vec=st_sh))$ret) - ann_sr(ret_f5) })
plc_pct <- mean(plc < real_dsr)
cat(sprintf("    실제 ΔSR(G3b−F5) = %+.3f | placebo ΔSR 분포: mean %+.3f / q95 %+.3f / max %+.3f | 실제값 백분위 = %.1f%%\n",
    real_dsr, mean(plc), quantile(plc, 0.95), max(plc), 100*plc_pct))

cat("\n[7] Subperiod (2017 분할)\n")
pre <- p$anchor_date < as.Date("2017-01-01")
sub_tbl <- rbindlist(lapply(c("C1_incumbent","F5_base","G3b_E100_s2"), function(nm) {
  data.table(variant=nm,
    SR_pre2017=round(ann_sr(R[[nm]]$ret[pre], p$anchor_date[pre]),3),
    SR_post2017=round(ann_sr(R[[nm]]$ret[!pre], p$anchor_date[!pre]),3)) }))
print(sub_tbl)

cat("\n[8] DSR 진단 (Bailey-LdP deflated SR — sweep n_trials=27, diagnostic)\n")
## trial 풀: R1 13 + R2 9 + R2.5 신규 5 (G3grid 4 + F3_fixed). 주의: R1은 구vintage SR —
## SR 분산 추정용으로만 사용(보수적 근사). graduation-authoritative DSR은 essence_score 경유 필요.
trial_sr_ann <- c(2.224,2.156,2.152,2.138,2.129,2.124,2.124,2.119,2.117,2.090,1.930,1.924,1.897,  # R1
                  2.154,2.147,2.182,2.208,2.228,2.090,2.126,2.132,2.158,                           # R2 G군
                  res[variant %in% c("G3_E70_s2","G3_E70_s1","G3_E85_s1","G3_E100_s1","F3_fixed"), SR])
trial_sr_m <- trial_sr_ann / sqrt(12)
ret_g <- R$G3b_E100_s2$ret
sr_m <- mean(ret_g)/sd(ret_g); nn <- length(ret_g)
g3 <- mean((ret_g-mean(ret_g))^3)/sd(ret_g)^3; g4 <- mean((ret_g-mean(ret_g))^4)/sd(ret_g)^4
emc <- 0.5772156649; Ntr <- length(trial_sr_m); v_sr <- var(trial_sr_m)
sr0 <- sqrt(v_sr) * ((1-emc)*qnorm(1-1/Ntr) + emc*qnorm(1-1/(Ntr*exp(1))))
dsr <- pnorm(((sr_m - sr0) * sqrt(nn-1)) / sqrt(1 - g3*sr_m + (g4-1)/4*sr_m^2))
cat(sprintf("    n_trials=%d | SR_m(G3b)=%.4f | SR0(월간)=%.4f | 왜도 %.2f / 첨도 %.2f | DSR = %.4f %s\n",
    Ntr, sr_m, sr0, g3, g4, dsr, ifelse(dsr >= 0.5, "(>=0.5)", "(<0.5)")))

cat("\n[9] 계약 bt_result (G3b — build_bt_result)\n")
anchor <- p$anchor_date; bm_win <- rep(NA_real_, nrow(p))
for (i in 2:nrow(p)) { seg <- bm_x[index(bm_x) > anchor[i-1] & index(bm_x) <= anchor[i]]
  if (nrow(seg) > 0) bm_win[i] <- as.numeric(Return.cumulative(seg)) }
source(file.path(BASE_DIR, "02_Infrastructure/contracts/backtest_result_contract.R"))
strategy_spec <- list(strategy_id="STR_1715_FaithSemi_BullFloor_G3b_CANDIDATE",
  universe="KOSPI200 ∪ KOSDAQ150", rebalance="monthly", cost_bps=15,
  overlay="w_str1715 × m4 × β_semi(F5) × β_R05, Bull-state(12M+∧2M+) 총노출 floor 1.0 (BBT 4-state)")
sim_result <- list(period_returns=data.table(date=p$anchor_date, ret_net=R$G3b_E100_s2$ret),
                   holdings=NULL,
                   benchmark_returns=data.table(date=p$anchor_date, ret=bm_win))
bt <- tryCatch(build_bt_result(sim_result, strategy_spec, run_id="g3b_verify_20260702",
        strategy_id="STR_1715_FaithSemi_BullFloor_G3b_CANDIDATE", benchmark_id="KOSPI200",
        transaction_cost_bps=15),
      error=function(e){cat("    build_bt_result 예외:", conditionMessage(e), "\n"); NULL})
if (!is.null(bt)) { saveRDS(bt, file.path(OUT_DIR, "bt_result_g3b_candidate.rds"))
  cat("    bt_result 저장. audit:", tryCatch(bt$audit$integrity, error=function(e) "n/a"), "\n")
  pa <- tryCatch({ bc <- bt$benchmark_compare
    if (is.data.frame(bc) && "Portfolio_Alpha_t_NW_lag3" %in% (if("metric" %in% names(bc)) bc$metric else rownames(bc)))
      { if ("metric" %in% names(bc)) bc[bc$metric=="Portfolio_Alpha_t_NW_lag3", 2] else bc["Portfolio_Alpha_t_NW_lag3", 1] } else NA }, error=function(e) NA)
  cat("    Portfolio_Alpha_t_NW_lag3 (vs KOSPI200):", ifelse(is.na(pa), "row 미확인 — bt$benchmark_compare 구조 보고 요망", round(as.numeric(pa),3)), "\n") }

fwrite(res, file.path(OUT_DIR, "offense_verify_results.csv"))
fwrite(oos_tbl, file.path(OUT_DIR, "offense_verify_oos.csv"))
fwrite(sub_tbl, file.path(OUT_DIR, "offense_verify_subperiod.csv"))
meta <- list(date="2026-07-02", round="2.5-verify", vintage="benchmark_pinned_20260702.parquet (yfinance ^KS200 교차검증)",
  n_trials_cumulative=27L, note_r2_meta="R2 meta의 23은 오기(13+9=22) — 본 파일 27(=22+5)이 정정 권위",
  selection_type="sweep", placebo=list(n=200, method="state2 circular shift", real_dSR=round(real_dsr,4), pctile=round(plc_pct,4)),
  dsr_diag=round(dsr,4), metric_type="backtested(panel-overlay), diagnostic-tier",
  graduation_note="자본 편입은 forge full-rerun + essence_score + judge + governor(도훈 confirm) 필요 — 본 검증은 후보 승격 근거만")
write_json(meta, file.path(OUT_DIR, "offense_verify_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\n[DONE] Round 2.5 검증 산출:", OUT_DIR, "\n")
