## ============================================================
## PG2 공격형 오버레이 Round 2 — 방향-구조(4-state) 오버라이드 배터리
## 도훈 지시 2026-07-02. Round 1 지배 패턴(SR↑=방어강화 vs bull참여 trade-off)을
## "추세 방향 구조" 신호로 깨는 시도. 근거 논문: Goulding-Harvey-Mazzoleni
## "Breaking Bad Trends" (FAJ 2024) — SLOW(12M)/FAST(1~2M) 부호 조합 4-state:
##   Bull(+,+) / Correction(+,-) / Bear(-,-) / Rebound(-,+)
## 핵심 가설: vol 기반 신호(σ², 백분위)는 랠리-vol과 크래시-vol을 구분 못함
## (F6 pct-오버라이드 미발화의 원인). 방향 구조는 구분 가능 — Rebound 조기
## 재진입 + Bull 브레이크 해제 + Correction 관용이 bull 참여를 회복하되
## Bear에서는 기존 방어를 그대로 유지.
## ============================================================
## PIT: 모든 신호 월말값 → 익월 적용(ym_next merge, canonical과 동일).
## 비용: |ΔE|×15bps. selection_type=sweep, n_trials 누적 기록 (R1 13 + R2 10).
## metric_type = backtested(panel-overlay)
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
T_HALF <- 16L; PAPER_COEF <- c(a=0.13, d=0.79, e=-0.17, f=0.09); COST <- 0.0015

cat("[1] panel + KOSPI 신호 (Round 1 복제)\n")
p <- fread(file.path(BASE_DIR, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym)
bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]; bm[, Date := as.Date(Date)]
bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
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
bm[, phi_d := phi]   # ★버그수리(2026-07-02): by-group에서 전역 phi 참조 시 last(전역)=상수 브로드캐스트 — 컬럼 승격 필수
bm[, S_semi := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2d + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2*(phi<0)]
bm[, ym := format(Date, "%Y-%m")]

## 월간 KOSPI 수익 (calendar month, 표준함수) → SLOW/FAST 부호 → 4-state
bm_x <- xts(bm[[bcol]], order.by=bm$Date)
mret <- apply.monthly(bm_x, Return.cumulative)
mdt <- data.table(ym=format(index(mret), "%Y-%m"), mret=as.numeric(mret))
mdt[, cum12 := frollapply(mret, 12, function(z) prod(1+z)-1)]   # 신호 구성용 trailing (성과보고 아님)
mdt[, cum2  := frollapply(mret, 2,  function(z) prod(1+z)-1)]
mdt[, cum1  := mret]
mdt[, state2 := fifelse(!is.finite(cum12) | !is.finite(cum2), "NA",
              fifelse(cum12 >= 0 & cum2 >= 0, "Bull",
              fifelse(cum12 >= 0 & cum2 <  0, "Correction",
              fifelse(cum12 <  0 & cum2 <  0, "Bear", "Rebound"))))]
mdt[, state1 := fifelse(!is.finite(cum12) | !is.finite(cum1), "NA",
              fifelse(cum12 >= 0 & cum1 >= 0, "Bull",
              fifelse(cum12 >= 0 & cum1 <  0, "Correction",
              fifelse(cum12 <  0 & cum1 <  0, "Bear", "Rebound"))))]

me <- bm[, .(S_semi=last(S_semi), phi_m=last(phi_d)), by=ym]
me <- merge(me, mdt[, .(ym, state2, state1)], by="ym", all.x=TRUE); setorder(me, ym)
me[, ym_next := format(as.Date(paste0(ym,"-01")) %m+% months(1), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_next, S_semi, phi_m, state2, state1)], by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
p[is.na(state2), state2 := "NA"]; p[is.na(state1), state1 := "NA"]

cat("[2] F3 진단 (Round 1: F3 ≡ C2_no_faith 원인 규명)\n")
der <- p[beta_faith < 1]
cat(sprintf("    β_faith<1 개월수 = %d | 그중 phi_m>0 = %d (%.0f%%) | phi_m<=0 = %d\n",
    nrow(der), der[phi_m > 0, .N], 100*der[phi_m > 0, .N]/max(nrow(der),1), der[phi_m <= 0, .N]))
cat("    phi_m 분포(β_faith<1 구간): ", paste(round(quantile(der$phi_m, c(0,.25,.5,.75,1), na.rm=TRUE),2), collapse=" / "), "\n")

cat("[3] expanding pct + 매핑 (Round 1 복제)\n")
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
map_cont <- function(pp, t0){ if(!is.finite(pp)) return(1.0)
  max(0.4, min(1.0, 1 - 0.6*max(0,(pp - t0))/(1 - t0))) }
b_f5  <- sapply(p$pct_semi, map_freq)          # Round 1 F5 재현
## Round 1 F2b 재현 (S_faith 원신호 pct — 재계산)
sig2 <- rep(NA_real_, n); acc <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) { acc <- al*rhat[t]^2 + (1-al)*acc; sig2[t] <- acc }
bm[, S_faith2 := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2 + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2]
me2 <- bm[, .(S_f=last(S_faith2)), by=ym]; setorder(me2, ym)
me2[, ym_next := format(as.Date(paste0(ym,"-01")) %m+% months(1), "%Y-%m")]
p <- merge(p, me2[, .(realized_ym=ym_next, S_f)], by="realized_ym", all.x=TRUE); setorder(p, realized_ym)
p[, pct_f := exp_pct(S_f)]
b_f2b <- sapply(p$pct_f, map_cont, 0.75)

cat("[4] Round 2 변형군 (state-conditional)\n")
st <- p$state2
mk_state_beta <- function(base_beta, rebound1=FALSE, corr_floor=NA, bull_beta1=FALSE, use_state=st) {
  b <- base_beta
  if (rebound1)  b[use_state == "Rebound"] <- 1.0
  if (is.finite(corr_floor)) b[use_state == "Correction"] <- pmax(b[use_state == "Correction"], corr_floor)
  if (bull_beta1) b[use_state == "Bull"] <- 1.0
  b
}
variants <- list()
variants[["C1_incumbent_dE"]] <- list(beta=p$beta_faith, r05=p$beta_R05, m4=p$m4)
variants[["R1_F5_base"]]      <- list(beta=b_f5, r05=p$beta_R05, m4=p$m4)
## G1: 순수 4-state 매핑 (percentile 없이 방향 구조만): Bull 1.0 / Corr 0.7 / Bear 0.4 / Rebound 1.0
b_g1 <- fifelse(st=="Bull", 1.0, fifelse(st=="Correction", 0.7, fifelse(st=="Bear", 0.4, fifelse(st=="Rebound", 1.0, 1.0))))
variants[["G1_bbt_pure"]] <- list(beta=b_g1, r05=p$beta_R05, m4=p$m4)
## G2: F5 + Rebound 조기 재진입 (β=1)
variants[["G2_f5_rebound"]]      <- list(beta=mk_state_beta(b_f5, rebound1=TRUE), r05=p$beta_R05, m4=p$m4)
variants[["G2b_f5_rebound_1m"]]  <- list(beta=mk_state_beta(b_f5, rebound1=TRUE, use_state=p$state1), r05=p$beta_R05, m4=p$m4)
## G3: F5 + Bull-state 총노출 floor (모든 레이어 관통)
variants[["G3a_f5_bullE85"]]  <- list(beta=b_f5, r05=p$beta_R05, m4=p$m4, bullE=0.85)
variants[["G3b_f5_bullE100"]] <- list(beta=b_f5, r05=p$beta_R05, m4=p$m4, bullE=1.00)
## G4: F5 + Correction 관용 (β floor 0.7 — 상승추세 내 조정은 크래시 아님)
variants[["G4_f5_corr70"]] <- list(beta=mk_state_beta(b_f5, corr_floor=0.7), r05=p$beta_R05, m4=p$m4)
## G5: 풀콤보 (Rebound=1 + Corr floor 0.7 + Bull E floor 0.85)
variants[["G5_f5_bbt_full"]] <- list(beta=mk_state_beta(b_f5, rebound1=TRUE, corr_floor=0.7), r05=p$beta_R05, m4=p$m4, bullE=0.85)
## G6: F2b(연속, R1 t최고) + Rebound=1
variants[["G6_f2b_rebound"]] <- list(beta=mk_state_beta(b_f2b, rebound1=TRUE), r05=p$beta_R05, m4=p$m4)
## G7: F5 + Bull에서 방어층 부분 해제 (r05 floor 0.7 / m4 floor 0.85) + Rebound β=1
r05_g7 <- p$beta_R05; r05_g7[st=="Bull"] <- pmax(r05_g7[st=="Bull"], 0.7)
m4_g7  <- p$m4;       m4_g7[st=="Bull"]  <- pmax(m4_g7[st=="Bull"], 0.85)
variants[["G7_f5_bull_release"]] <- list(beta=mk_state_beta(b_f5, rebound1=TRUE), r05=r05_g7, m4=m4_g7)

cat("[5] 수익/지표 산출\n")
anchor <- p$anchor_date
bm_win <- rep(NA_real_, nrow(p))
for (i in 2:nrow(p)) { seg <- bm_x[index(bm_x) > anchor[i-1] & index(bm_x) <= anchor[i]]
  if (nrow(seg) > 0) bm_win[i] <- as.numeric(Return.cumulative(seg)) }
p[, bm_ret := bm_win]
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn) }
mk_ret <- function(v) {
  E <- v$r05 * v$m4 * v$beta
  if (!is.null(v$bullE)) E <- ifelse(st == "Bull", pmax(E, v$bullE), E)
  dE <- abs(E - shift(E, 1, fill=1.0))
  list(ret = E * p$ret_orig - dE*COST, E=E, dE=dE) }
calc_row <- function(ret, expo, dE, name, ret_c1, ret_f5) {
  x <- xts(ret, order.by=p$anchor_date)
  data.table(variant=name,
    SR=round(as.numeric(table.AnnualizedReturns(x, scale=12)[3,1]),3),
    CAGR=round(as.numeric(Return.annualized(x, scale=12)),4),
    MDD=round(as.numeric(maxDrawdown(x)),4),
    Calmar=round(as.numeric(CalmarRatio(x, scale=12)),3),
    Sortino_m=round(as.numeric(SortinoRatio(x, MAR=0)),4),
    up_capture=round(as.numeric(tryCatch(UpDownRatios(x, xts(p$bm_ret, order.by=p$anchor_date), method="Capture", side="Up"), error=function(e) NA)),3),
    down_capture=round(as.numeric(tryCatch(UpDownRatios(x, xts(p$bm_ret, order.by=p$anchor_date), method="Capture", side="Down"), error=function(e) NA)),3),
    ret_2025=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2025"])),4),
    ret_2026=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"])),4),
    avg_expo=round(mean(expo, na.rm=TRUE),3), turnover_dE=round(sum(dE, na.rm=TRUE),2),
    nw_t_vs_C1=round(nw_t(ret - ret_c1),2), nw_t_vs_F5=round(nw_t(ret - ret_f5),2)) }

zc1 <- mk_ret(variants[["C1_incumbent_dE"]]); zf5 <- mk_ret(variants[["R1_F5_base"]])
results <- list(); series <- data.table(realized_ym=p$realized_ym, anchor_date=p$anchor_date, state2=p$state2)
for (nm in names(variants)) { z <- mk_ret(variants[[nm]])
  results[[nm]] <- calc_row(z$ret, z$E, z$dE, nm, zc1$ret, zf5$ret)
  series[[paste0("ret_",nm)]] <- z$ret; series[[paste0("E_",nm)]] <- z$E }
res <- rbindlist(results); setorder(res, -SR)

cat("[6] state 분포 진단\n")
print(p[, .N, by=state2])
cat("    2025~2026 state 시퀀스:\n")
p[, b_f5_col := b_f5]   # ★버그수리(2026-07-02): j-내부 전역벡터 서브셋 인덱싱 = 재활용 오정렬 — 컬럼 승격 후 출력
print(p[realized_ym >= "2025-01", .(realized_ym, state2, state1, beta_faith, b_f5=round(b_f5_col,2), beta_R05, m4, ret_orig=round(ret_orig,3))][order(realized_ym)])
cat("    위기월 state 확인 (2008-06~2009-03, 2020-02~04, 2022-01~10):\n")
print(p[realized_ym %in% c(sprintf("2008-%02d",6:12),"2009-01","2009-02","2009-03","2020-02","2020-03","2020-04",sprintf("2022-%02d",1:10)), .(realized_ym, state2, beta_faith, beta_R05, m4)])

## 연도별
yr_tbl <- NULL
for (nm in names(variants)) { x <- xts(series[[paste0("ret_",nm)]], order.by=p$anchor_date)
  yv <- apply.yearly(x, Return.cumulative)
  tmp <- data.table(year=format(index(yv),"%Y"), v=round(as.numeric(yv),4)); setnames(tmp,"v",nm)
  yr_tbl <- if (is.null(yr_tbl)) tmp else merge(yr_tbl, tmp, by="year", all=TRUE) }
bx <- apply.yearly(xts(p$bm_ret, order.by=p$anchor_date), Return.cumulative)
yr_tbl <- merge(yr_tbl, data.table(year=format(index(bx),"%Y"), KOSPI=round(as.numeric(bx),4)), by="year", all.x=TRUE)

cat("\n================ ROUND 2 RESULTS (SR 내림차순) ================\n")
print(res, nrow=99)
cat("\n================ 연도별 ================\n")
print(yr_tbl, nrow=30)
fwrite(res, file.path(OUT_DIR, "offense_round2_results.csv"))
fwrite(yr_tbl, file.path(OUT_DIR, "offense_round2_yearly.csv"))
fwrite(series, file.path(OUT_DIR, "offense_round2_series.csv"))
meta <- list(date=format(Sys.Date()), round=2L, n_trials_round2=length(variants)-2L, n_trials_cumulative=23L,
  selection_type="sweep", cost_convention="|dE|x15bps", metric_type="backtested(panel-overlay)",
  paper_basis="Goulding-Harvey-Mazzoleni Breaking Bad Trends (FAJ 2024) 4-state, KR long-only 사상",
  pit="state/신호 월말→익월 ym_next merge (canonical 동일)")
write_json(meta, file.path(OUT_DIR, "offense_round2_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[DONE] Round 2 산출: %s\n", OUT_DIR))
