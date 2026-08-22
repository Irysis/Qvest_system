## probe_a5_falsify.R — A5(분기리밸 x 연속가중 x broad-21) HARD 2종 통과의 반증 배터리
## 읽기 전용 프로브. 기존 파이프라인 파일 무수정. 산출물은 본 디렉터리에만.
## 구성부(가중->포트수익) = run_dfa_c1_followup_r10.R 의 run_arm 을 **축자 복제**하고
##                          캐시(.cache/_dfa_c1_followup_r10.rds)와 **비트 동치 parity** 로 검증한다.
##                          (감사 대상 코드경로를 그대로 재현해야 반증이 성립하므로)
## pt = 계약 함수 .nw_t_mean(backtest_result_contract.R) 권위. sandwich 판(nwt)은 병기 대조.
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
suppressMessages({library(sandwich); library(lmtest)})
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
set.seed(20260822)
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log.txt"), split = TRUE)

IRf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt_sw <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m, lag=3, prewhite=FALSE))[1,3]) }
PT <- function(x) .nw_t_mean(x[is.finite(x)], lag = 3L)   # 계약 권위

## ---------- 데이터 (r10 과 동일 경로) ----------
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
R[, ym := format(Date, "%Y-%m")]
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x), x, 0))-1), .(medate=max(Date))),
         by = ym, .SDcols = c("Market", fac)]
setorder(mon, medate); NM <- nrow(mon); NAx <- 1 + length(fac)
cat(sprintf("[data] months=%d  factors=%d  range=%s..%s\n", NM, length(fac),
            mon$ym[1], mon$ym[NM]))

mk_sig <- function(win, cols = fac){
  S <- matrix(NA_real_, NM, length(cols)); colnames(S) <- cols
  for(fi in seq_along(cols)){ f <- cols[fi]
    for(m in win:NM){ w <- (m-win+1):m
      S[m, fi] <- prod(1+mon[[f]][w]) / prod(1+mon$Market[w]) - 1 } }
  S }
S12 <- mk_sig(12)

## ---------- run_arm 축자 복제 (r10 원본과 동일) ----------
run_arm <- function(S, mode="cont", bps=15, freq=1, start_m=13, cols=fac, phase_off=0){
  nA <- 1 + length(cols)
  pr <- rep(NA_real_, NM); tov <- rep(NA_real_, NM); wprev <- rep(1/nA, nA); wcur <- NULL
  for(m in start_m:NM){ d <- m - 1
    if(is.null(wcur) || ((m - start_m - phase_off) %% freq == 0)){
      s <- S[d, ]; pos <- which(is.finite(s) & s > 0); w <- rep(0, nA)
      if(length(pos) == 0){ w[1] <- 1 } else if(mode == "cont"){ w[1+pos] <- s[pos]/sum(s[pos])
      } else { rk <- rank(s[pos]); w[1+pos] <- rk/sum(rk) }
      wcur <- w }
    ri <- unlist(mon[m, c("Market", cols), with=FALSE]); ri[!is.finite(ri)] <- 0
    dlt <- sum(abs(wcur - wprev)); tov[m] <- dlt
    pr[m] <- sum(wcur*ri) - (bps/1e4)*dlt
    wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }
  list(pr=pr, tov=tov) }

## ---------- 3-코호트 중첩 앙상블 (prereg amendment_1 A5E) ----------
## 매월 자본의 1/3 을 해당 코호트가 재결정(각 코호트 3개월 홀딩), 포트 = 3코호트 평균.
run_a5e <- function(S, bps=15, start_m=13, cols=fac){
  nA <- 1 + length(cols)
  W <- lapply(1:3, function(i) rep(1/nA, nA))       # 코호트별 현재 비중
  pr <- rep(NA_real_, NM); tov <- rep(NA_real_, NM); wprev <- rep(1/nA, nA)
  for(m in start_m:NM){ d <- m - 1
    for(ci in 1:3){
      if(m == start_m || ((m - start_m - (ci-1)) %% 3 == 0)){
        s <- S[d, ]; pos <- which(is.finite(s) & s > 0); w <- rep(0, nA)
        if(length(pos) == 0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos])
        W[[ci]] <- w } }
    wcur <- (W[[1]] + W[[2]] + W[[3]]) / 3
    ri <- unlist(mon[m, c("Market", cols), with=FALSE]); ri[!is.finite(ri)] <- 0
    dlt <- sum(abs(wcur - wprev)); tov[m] <- dlt
    pr[m] <- sum(wcur*ri) - (bps/1e4)*dlt
    for(ci in 1:3){ wd <- W[[ci]]*(1+ri); W[[ci]] <- wd/sum(wd) }
    wd <- wcur*(1+ri); wprev <- wd/sum(wd) }
  list(pr=pr, tov=tov) }

act_of <- function(r){ k <- is.finite(r$pr); r$pr[k] - mon$Market[k] }
mets <- function(r){ k <- is.finite(r$pr); p <- r$pr[k]; a <- p - mon$Market[k]
  nav <- cumprod(1+p); n <- length(p); cg <- prod(1+p)^(12/n)-1; mdd <- min(nav/cummax(nav)-1)
  list(n=n, pt=PT(a), pt_sw=nwt_sw(a), IR=IRf(a), SR=IRf(p), CAGR=cg, MDD=mdd,
       calmar=cg/abs(mdd), TO=mean(r$tov[k], na.rm=TRUE)*12, act=a, ret=p,
       dates=mon$medate[k]) }

## ---------- 계약 oos_retention 축자 복제 (essence_score.R L246-258) ----------
oos_ret_at <- function(a, fr, af = 12){
  a <- a[is.finite(a)]; n <- length(a); k <- floor(n*fr)
  if(k < 6 || (n-k) < 6) return(c(NA_real_, NA_real_, NA_real_))
  ia <- a[1:k]; oa <- a[(k+1):n]
  is_ir  <- if(sd(ia) > 0) mean(ia)/sd(ia)*sqrt(af) else NA_real_
  oos_ir <- if(sd(oa) > 0) mean(oa)/sd(oa)*sqrt(af) else NA_real_
  rt <- if(is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir/is_ir else NA_real_
  c(is_ir, oos_ir, rt) }

## ======================================================================
## PARITY 0 — 캐시 재현 (감사 대상 코드경로 동일성 확인)
## ======================================================================
cat("\n================ PARITY 0: 캐시 대조 ================\n")
SER <- readRDS(".cache/_dfa_c1_followup_r10.rds")
a5c <- SER[["A5_quart_15"]]
mine <- run_arm(S12, "cont", 15, freq=3, start_m=13)
cat(sprintf("  pr identical(캐시 vs 재현) : %s   (max|diff|=%.3e)\n",
    isTRUE(all.equal(a5c$pr, mine$pr, tolerance=0)), max(abs(a5c$pr-mine$pr), na.rm=TRUE)))
cat(sprintf("  tov identical              : %s\n", isTRUE(all.equal(a5c$tov, mine$tov, tolerance=0))))
A5 <- mets(mine)
cat(sprintf("  A5 15bps: n=%d pt(contract)=%.4f pt(sandwich)=%.4f IR=%.4f SR=%.4f MDD=%.4f calmar=%.4f TO=%.3f\n",
    A5$n, A5$pt, A5$pt_sw, A5$IR, A5$SR, A5$MDD, A5$calmar, A5$TO))
cat(sprintf("  구간: %s .. %s\n", format(A5$dates[1]), format(A5$dates[A5$n])))

## essence 계약 채점 (권위)
mk_bt <- function(mm, nm){
  sim <- list(DAILY_NAV_DT=data.table(Date=mm$dates, Strategy_Ret=mm$ret, NAV=cumprod(1+mm$ret)),
              strategy_xts=xts(mm$ret, order.by=mm$dates),
              bm_xts=xts(mm$ret-mm$act, order.by=mm$dates), cost_model_version="probe_a5_15bps")
  spec <- list(strategy_name=nm, description="A5 반증 프로브", universe="KR broad-21",
               rebalance="quarterly", signal="factor momentum")
  build_bt_result(sim, spec, run_id=tolower(nm), strategy_id=toupper(nm),
    benchmark_id="CAPW_PARENT", benchmark_name="cap-w parent", transaction_cost_bps=15,
    slippage_bps=0, frequency="monthly", universe_id="K200_KQ150",
    code_version="probe_a5_falsify.R", created_by_agent="Q-Lead") }
bt5 <- mk_bt(A5, "PROBE_A5")
es5 <- essence_score(bt5, n_trials_cumulative=56, selection_type="chain")
e5 <- es5$essence
cat(sprintf("  [essence 계약] grade=%s pt=%.4f oos=%.4f splits=%s calmar=%.4f SR=%.3f MDD=%.4f DSR=%.4f\n",
    es5$grade, e5$portfolio_alpha_t_nw_lag3, e5$oos_retention,
    paste(sprintf("%.3f", es5$diagnostics$oos_retention_splits), collapse="/"),
    e5$calmar, e5$net_sharpe, e5$mdd, e5$dsr))
## 내 oos 복제 parity
rep_splits <- sapply(c(.55,.65,.75), function(f) oos_ret_at(A5$act, f)[3])
cat(sprintf("  oos 복제 parity: splits=%s median=%.4f  (계약과 일치=%s)\n",
    paste(sprintf("%.4f", rep_splits), collapse="/"), median(rep_splits, na.rm=TRUE),
    isTRUE(all.equal(median(rep_splits, na.rm=TRUE), e5$oos_retention, tolerance=1e-6))))

## ======================================================================
## Q1 — 선택편향 정량화 (DSR / 다중검정 보정) [진단용, 게이트 아님]
## ======================================================================
cat("\n================ Q1: 선택편향 / 다중검정 ================\n")
af <- 12; a5a <- A5$act; n5 <- length(a5a); mu5 <- mean(a5a); sd5 <- sd(a5a)
sk5 <- mean(((a5a-mu5)/sd5)^3); ku5 <- mean(((a5a-mu5)/sd5)^4)
cat(sprintf("  active: n=%d  IR(ann)=%.4f  skew=%.3f  kurt=%.3f\n", n5, A5$IR, sk5, ku5))
dsr_tab <- rbindlist(lapply(c(1,2,5,6,10,21,56,100,200,500), function(nt)
  data.table(n_trials=nt, DSR=.essence_dsr(A5$IR, n5, nt, sk5, ku5, A=af))))
print(dsr_tab, digits=4)
cat(sprintf("  -> n_trials=56 DSR=%.4f  (sweep 게이트 0.5 대비 %s)  ※chain 이므로 게이트 부적용, 진단만\n",
    dsr_tab[n_trials==56, DSR], ifelse(dsr_tab[n_trials==56, DSR]>=0.5, "통과", "미달")))
## DSR=0.5 가 되는 n_trials 임계 (SR0 = 관측 SR 이 되는 지점)
f_dsr <- function(nt) .essence_dsr(A5$IR, n5, nt, sk5, ku5, A=af) - 0.5
nt_crit <- tryCatch(uniroot(f_dsr, c(2, 1e12))$root, error=function(e) NA_real_)
cat(sprintf("  DSR=0.5 이 되는 임계 n_trials = %.3g  (이보다 시행수가 많으면 DSR 게이트 탈락)\n", nt_crit))

## PORT_t 다중검정 보정
p5 <- 2*(1-pnorm(abs(A5$pt)))
cat(sprintf("\n  PORT_t=%.4f -> 단측/양측 p(정규근사) = %.3e / %.3e\n", A5$pt, 1-pnorm(A5$pt), p5))
for(N in c(5, 6, 56)){
  cat(sprintf("  N=%3d : Bonferroni p_adj=%.4f (%s@0.05) | Sidak p_adj=%.4f | Bonf 임계 t=%.3f (%s)\n",
      N, min(1, p5*N), ifelse(p5*N<0.05,"유의","비유의"), 1-(1-p5)^N,
      qnorm(1-0.05/(2*N)), ifelse(A5$pt>=qnorm(1-0.05/(2*N)),"통과","미달"))) }
## 독립시행 가정 하 최대-t 기대값 (Bailey SR0 논리의 t-스케일 등가)
emc <- 0.5772156649
for(N in c(5, 56, 100)){
  z1 <- qnorm(1-1/N); z2 <- qnorm(1-1/(N*exp(1))); et <- (1-emc)*z1 + emc*z2
  cat(sprintf("  N=%3d : 귀무 하 max-t 기대값 E[max t] = %.3f  (관측 %.3f 대비 %s)\n",
      N, et, A5$pt, ifelse(A5$pt>et, "초과", "미달"))) }

## 이번 라운드 5팔 상관 -> 유효 독립시행수
arms <- list(C1_base=run_arm(S12,"cont",15,1,13), A2_rank=run_arm(S12,"rank",15,1,13),
             A3_win6=run_arm(mk_sig(6),"cont",15,1,13), A4_win24=run_arm(mk_sig(24),"cont",15,1,25),
             A5_quart=mine)
AM <- sapply(arms, function(r) { p<-r$pr; ifelse(is.finite(p), p, NA_real_) - mon$Market })
AM <- AM[complete.cases(AM), ]
CR <- cor(AM); cat("\n  [이번 라운드 5팔 active 상관]\n"); print(round(CR,3))
ev <- eigen(CR, only.values=TRUE)$values; k5 <- ncol(CR)
Neff_kaiser <- sum(ev > 1); Neff_ent <- exp(-sum((ev/k5)*log(ev/k5)))
cat(sprintf("  유효 독립시행수: Kaiser(eig>1)=%d | 엔트로피기반=%.2f | 명목=%d\n",
    Neff_kaiser, Neff_ent, k5))
cat(sprintf("  -> 상관보정 N=%.2f 에서 Bonferroni 임계 t = %.3f (관측 %.3f : %s)\n",
    Neff_ent, qnorm(1-0.05/(2*max(Neff_ent,1))), A5$pt,
    ifelse(A5$pt>=qnorm(1-0.05/(2*max(Neff_ent,1))), "통과", "미달")))
fwrite(dsr_tab, file.path(OUTD, "q1_dsr_table.csv"))

## ======================================================================
## Q2 — 위상 의존성
## ======================================================================
cat("\n================ Q2: 분기 위상 ================\n")
cat("  [2a] 창 고정(start_m=13, n=236 동일) x 위상 offset 0/1/2\n")
ph <- rbindlist(lapply(0:2, function(o){ m <- mets(run_arm(S12,"cont",15,3,13,phase_off=o))
  data.table(variant="window_fixed", offset=o, n=m$n, pt=m$pt, IR=m$IR, SR=m$SR,
             MDD=m$MDD, calmar=m$calmar, TO=m$TO) }))
print(ph, digits=4)
cat("  [2b] r11 재현(start_m=13+off — 표본창이 함께 이동. 위상/창 교락)\n")
ph2 <- rbindlist(lapply(0:2, function(o){ m <- mets(run_arm(S12,"cont",15,3,13+o))
  data.table(variant="start_shift", offset=o, n=m$n, pt=m$pt, IR=m$IR, SR=m$SR,
             MDD=m$MDD, calmar=m$calmar, TO=m$TO) }))
print(ph2, digits=4)
cat("  [2c] A5E 3-코호트 중첩 앙상블 (위상 자유도 제거, prereg amendment_1)\n")
A5E <- mets(run_a5e(S12, 15, 13))
cat(sprintf("      n=%d pt=%.4f IR=%.4f SR=%.4f MDD=%.4f calmar=%.4f TO=%.3f\n",
    A5E$n, A5E$pt, A5E$IR, A5E$SR, A5E$MDD, A5E$calmar, A5E$TO))
btE <- mk_bt(A5E, "PROBE_A5E"); esE <- essence_score(btE, n_trials_cumulative=56, selection_type="chain")
cat(sprintf("      [essence] grade=%s pt=%.4f oos=%.4f splits=%s calmar=%.4f\n", esE$grade,
    esE$essence$portfolio_alpha_t_nw_lag3, esE$essence$oos_retention,
    paste(sprintf("%.3f", esE$diagnostics$oos_retention_splits), collapse="/"), esE$essence$calmar))
cat(sprintf("      3위상 pt 평균=%.4f  sd=%.4f  min=%.4f  (게이트 2.95 통과 위상 %d/3)\n",
    mean(ph$pt), sd(ph$pt), min(ph$pt), sum(ph$pt>=2.95)))
## paired NW-t : offset0 vs 나머지 위상
for(o in 1:2){ r0 <- run_arm(S12,"cont",15,3,13,phase_off=0); r1 <- run_arm(S12,"cont",15,3,13,phase_off=o)
  kk <- is.finite(r0$pr) & is.finite(r1$pr)
  cat(sprintf("      paired NW-t (offset0 - offset%d) = %+.3f\n", o, PT((r0$pr-r1$pr)[kk]))) }
fwrite(rbind(ph, ph2), file.path(OUTD, "q2_phase.csv"))

## ======================================================================
## Q3 — 팩터 수 민감도
## ======================================================================
cat("\n================ Q3: 팩터 수 민감도 ================\n")
sub_run <- function(cols){ Ssub <- S12[, cols, drop=FALSE]
  mets(run_arm(Ssub, "cont", 15, 3, 13, cols=cols)) }
draws <- function(k, B){ rbindlist(lapply(1:B, function(b){
  cs <- sample(fac, k); m <- sub_run(cs)
  data.table(k=k, draw=b, pt=m$pt, IR=m$IR, SR=m$SR, MDD=m$MDD, calmar=m$calmar, TO=m$TO,
             cols=paste(cs, collapse="|")) })) }
set.seed(20260822)
D20 <- rbindlist(lapply(c(6,12,18), function(k) draws(k, 20)))
cat("  [3a] 사양대로 각 k 20회 추출\n")
print(D20[, .(B=.N, pt_mean=mean(pt), pt_sd=sd(pt), pt_min=min(pt), pt_med=median(pt),
              pt_max=max(pt), frac_ge_2.95=mean(pt>=2.95),
              pct_of_3.232=mean(pt < 3.23180114)), by=k], digits=4)
set.seed(770422)
D200 <- rbindlist(lapply(c(6,12,18), function(k) draws(k, 200)))
cat("  [3b] 보강 각 k 200회 (백분위 정밀도)\n")
print(D200[, .(B=.N, pt_mean=mean(pt), pt_sd=sd(pt), pt_min=min(pt), pt_med=median(pt),
               pt_max=max(pt), frac_ge_2.95=mean(pt>=2.95),
               pct_of_3.232=mean(pt < 3.23180114)), by=k], digits=4)
cat(sprintf("  [3c] k=21 전수(A5 본체) pt=%.4f  — 위 분포의 기준점\n", A5$pt))
## 20개 팩터(1개 제거) leave-one-factor-out
LOO <- rbindlist(lapply(fac, function(f){ cs <- setdiff(fac, f); m <- sub_run(cs)
  data.table(dropped=f, pt=m$pt, IR=m$IR, calmar=m$calmar) }))
setorder(LOO, pt)
cat("  [3d] leave-one-factor-out (k=20, 전수 21케이스) — pt 하위 5 / 상위 3\n")
print(head(LOO, 5), digits=4); print(tail(LOO, 3), digits=4)
cat(sprintf("      LOO pt: min=%.3f med=%.3f max=%.3f | 2.95 미달 케이스 %d/21\n",
    min(LOO$pt), median(LOO$pt), max(LOO$pt), sum(LOO$pt < 2.95)))
fwrite(D200, file.path(OUTD, "q3_factor_subsets_B200.csv"))
fwrite(D20,  file.path(OUTD, "q3_factor_subsets_B20.csv"))
fwrite(LOO,  file.path(OUTD, "q3_leave_one_factor_out.csv"))

## ======================================================================
## Q4 — 구간 안정성 (확장윈도 + 잭나이프 + 롤링)
## ======================================================================
cat("\n================ Q4: 구간 안정성 ================\n")
yy <- format(A5$dates, "%Y"); yrs <- sort(unique(yy))
EXP <- rbindlist(lapply(2015:2026, function(Y){
  s <- as.integer(yy) <= Y; if(sum(s) < 24) return(NULL)
  data.table(through=Y, n=sum(s), pt=PT(A5$act[s]), IR=IRf(A5$act[s]),
             mean_act_ann=mean(A5$act[s])*12) }))
cat("  [4a] 확장윈도 (2007-02 시작, 각 연말까지)\n"); print(EXP, digits=4)
JK <- rbindlist(lapply(yrs, function(Y){ s <- yy != Y
  data.table(drop_year=Y, n=sum(s), pt=PT(A5$act[s]), IR=IRf(A5$act[s])) }))
setorder(JK, pt)
cat("  [4b] leave-one-year-out 잭나이프 — pt 하위 5\n"); print(head(JK, 5), digits=4)
cat(sprintf("      JK pt: min=%.3f med=%.3f max=%.3f | 2.95 미달 연도 %d/%d (%s)\n",
    min(JK$pt), median(JK$pt), max(JK$pt), sum(JK$pt<2.95), nrow(JK),
    paste(JK[pt<2.95, drop_year], collapse=",")))
ROLL <- rbindlist(lapply(seq(120, length(A5$act)), function(i){
  s <- (i-119):i; data.table(end=format(A5$dates[i], "%Y-%m"), pt=PT(A5$act[s]), IR=IRf(A5$act[s])) }))
cat(sprintf("  [4c] 롤링 120M pt: min=%.3f (%s) med=%.3f max=%.3f | >=2.95 비율=%.3f\n",
    min(ROLL$pt), ROLL[which.min(pt), end], median(ROLL$pt), max(ROLL$pt), mean(ROLL$pt>=2.95)))
## 후반부 단독
for(sy in c(2015, 2017, 2019)){ s <- as.integer(yy) >= sy
  cat(sprintf("      %d- 이후 단독: n=%d pt=%.3f IR=%.3f\n", sy, sum(s), PT(A5$act[s]), IRf(A5$act[s]))) }
fwrite(EXP, file.path(OUTD, "q4_expanding.csv")); fwrite(JK, file.path(OUTD, "q4_jackknife.csv"))
fwrite(ROLL, file.path(OUTD, "q4_rolling120.csv"))

## ======================================================================
## Q5 — oos_retention 0.704 의 취약성
## ======================================================================
cat("\n================ Q5: oos_retention 분할점 민감도 ================\n")
grid <- seq(0.40, 0.85, by=0.05)
OS <- rbindlist(lapply(grid, function(f){ v <- oos_ret_at(A5$act, f)
  data.table(split=f, k_IS=floor(n5*f), n_OOS=n5-floor(n5*f), IS_IR=v[1], OOS_IR=v[2], retention=v[3]) }))
print(OS, digits=4)
s_v2 <- OS[split %in% c(0.55,0.65,0.75), retention]
s_alt <- OS[split %in% c(0.50,0.60,0.70,0.80), retention]
cat(sprintf("\n  계약 v2 {55/65/75} : %s -> median=%.4f  (게이트 0.7 %s)\n",
    paste(sprintf("%.4f", s_v2), collapse=" / "), median(s_v2, na.rm=TRUE),
    ifelse(median(s_v2,na.rm=TRUE)>=0.7, "통과", "미달")))
cat(sprintf("  대안 {50/60/70/80}  : %s -> median=%.4f  (게이트 0.7 %s)\n",
    paste(sprintf("%.4f", s_alt), collapse=" / "), median(s_alt, na.rm=TRUE),
    ifelse(median(s_alt,na.rm=TRUE)>=0.7, "통과", "미달")))
cat(sprintf("  전 그리드 %d점: >=0.7 비율=%.3f | median=%.4f | min=%.4f max=%.4f\n",
    nrow(OS), mean(OS$retention>=0.7, na.rm=TRUE), median(OS$retention, na.rm=TRUE),
    min(OS$retention,na.rm=TRUE), max(OS$retention,na.rm=TRUE)))
## 1개월 단위 미세 그리드 (분할점 = 관측 인덱스)
FIN <- rbindlist(lapply(seq(floor(n5*0.40), floor(n5*0.85)), function(k){
  ia <- a5a[1:k]; oa <- a5a[(k+1):n5]
  ii <- mean(ia)/sd(ia)*sqrt(12); oo <- mean(oa)/sd(oa)*sqrt(12)
  data.table(k=k, split=k/n5, retention=if(ii>0.05) oo/ii else NA_real_) }))
cat(sprintf("  미세 그리드(월 단위 %d점, split 0.40~0.85): >=0.7 비율=%.3f median=%.4f\n",
    nrow(FIN), mean(FIN$retention>=0.7, na.rm=TRUE), median(FIN$retention, na.rm=TRUE)))
## C1(월간판) 대조
C1 <- mets(arms$C1_base)
c1_v2 <- sapply(c(.55,.65,.75), function(f) oos_ret_at(C1$act, f)[3])
cat(sprintf("  대조 C1 월간판 {55/65/75}: %s -> median=%.4f\n",
    paste(sprintf("%.4f", c1_v2), collapse=" / "), median(c1_v2, na.rm=TRUE)))
fwrite(OS, file.path(OUTD, "q5_oos_splits.csv")); fwrite(FIN, file.path(OUTD, "q5_oos_fine.csv"))

## ---------- 요약 저장 ----------
SUM <- data.table(
  metric=c("pt_contract","pt_sandwich","oos_v2_median","calmar","MDD","SR","IR","TO",
           "DSR_n56","DSR_crit_ntrials","phase_pt_min","phase_pt_mean","A5E_pt","A5E_oos",
           "loo_fail_count","jk_fail_count"),
  value=c(A5$pt, A5$pt_sw, median(s_v2,na.rm=TRUE), A5$calmar, A5$MDD, A5$SR, A5$IR, A5$TO,
          dsr_tab[n_trials==56, DSR], nt_crit, min(ph$pt), mean(ph$pt), A5E$pt,
          esE$essence$oos_retention, sum(LOO$pt<2.95), sum(JK$pt<2.95)))
fwrite(SUM, file.path(OUTD, "probe_a5_summary.csv"))
print(SUM, digits=5)
cat("\nPROBE_A5_DONE\n")
sink()
