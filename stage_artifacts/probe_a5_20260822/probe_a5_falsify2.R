## probe_a5_falsify2.R — probe1 자기정정 + 결정적 추가 반증
##  [자기정정 1] probe1 Q5 의 대안분할 {50/60/70/80} 선택이 부동소수점으로 붕괴
##               (seq(0.40,0.85,0.05) %in% c(.5,.6,.7,.8) 가 2점만 매치) -> round() 로 수리
##  [자기정정 2] probe1 의 essence splits 출력 경로 오기 (diagnostics$ 아님, 최상위 필드)
##  [추가] B 말월 부분관측 / C 가족단위 경험적 max-pt 귀무 / D oos 미세민감도 / E 위상팔 전지표 / F 감쇠
suppressPackageStartupMessages({library(data.table); library(arrow); library(xts)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
source("02_Infrastructure/contracts/audit_bt_result.R")
source("02_Infrastructure/contracts/essence_score.R")
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log2.txt"), split = TRUE)
IRf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
PT  <- function(x) .nw_t_mean(x[is.finite(x)], lag = 3L)

R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market"))
R[, ym := format(Date, "%Y-%m")]
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x), x, 0))-1),
             .(medate=max(Date), ndays=.N)), by=ym, .SDcols=c("Market", fac)]
setorder(mon, medate); NM <- nrow(mon); NAx <- 1+length(fac)
RET <- as.matrix(mon[, c("Market", fac), with=FALSE]); RET[!is.finite(RET)] <- 0

mk_sig <- function(win){ S <- matrix(NA_real_, NM, length(fac)); colnames(S) <- fac
  for(fi in seq_along(fac)) for(m in win:NM){ w <- (m-win+1):m
    S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w]) - 1 }; S }
S12 <- mk_sig(12); S6 <- mk_sig(6); S24 <- mk_sig(24)

run_arm <- function(S, mode="cont", bps=15, freq=1, start_m=13, phase_off=0, dec_lag=1, nmax=NM){
  pr <- rep(NA_real_, NM); tov <- rep(NA_real_, NM); wprev <- rep(1/NAx, NAx); wcur <- NULL
  st <- start_m + max(dec_lag-1, 0)
  for(m in st:nmax){ d <- m - dec_lag; if(d < 1) next
    if(is.null(wcur) || ((m - st - phase_off) %% freq == 0)){
      s <- S[d,]; pos <- which(is.finite(s) & s > 0); w <- rep(0, NAx)
      if(length(pos)==0){ w[1] <- 1 } else if(mode=="cont"){ w[1+pos] <- s[pos]/sum(s[pos])
      } else { rk <- rank(s[pos]); w[1+pos] <- rk/sum(rk) }
      wcur <- w }
    ri <- RET[m,]; dlt <- sum(abs(wcur-wprev)); tov[m] <- dlt
    pr[m] <- sum(wcur*ri) - (bps/1e4)*dlt
    wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }
  list(pr=pr, tov=tov) }
run_a5e <- function(S, bps=15, start_m=13, nmax=NM){
  W <- lapply(1:3, function(i) rep(1/NAx, NAx))
  pr <- rep(NA_real_, NM); tov <- rep(NA_real_, NM); wprev <- rep(1/NAx, NAx)
  for(m in start_m:nmax){ d <- m-1
    for(ci in 1:3) if(m==start_m || ((m-start_m-(ci-1)) %% 3 == 0)){
      s <- S[d,]; pos <- which(is.finite(s)&s>0); w <- rep(0,NAx)
      if(length(pos)==0) w[1] <- 1 else w[1+pos] <- s[pos]/sum(s[pos]); W[[ci]] <- w }
    wcur <- (W[[1]]+W[[2]]+W[[3]])/3; ri <- RET[m,]
    dlt <- sum(abs(wcur-wprev)); tov[m] <- dlt; pr[m] <- sum(wcur*ri)-(bps/1e4)*dlt
    for(ci in 1:3){ wd <- W[[ci]]*(1+ri); W[[ci]] <- wd/sum(wd) }
    wd <- wcur*(1+ri); wprev <- wd/sum(wd) }
  list(pr=pr, tov=tov) }
mets <- function(r){ k <- is.finite(r$pr); p <- r$pr[k]; a <- p - mon$Market[k]
  nav <- cumprod(1+p); n <- length(p); cg <- prod(1+p)^(12/n)-1; mdd <- min(nav/cummax(nav)-1)
  list(n=n, pt=PT(a), IR=IRf(a), SR=IRf(p), CAGR=cg, MDD=mdd, calmar=cg/abs(mdd),
       TO=mean(r$tov[k],na.rm=TRUE)*12, act=a, ret=p, dates=mon$medate[k]) }
oos_at <- function(a, fr){ a<-a[is.finite(a)]; n<-length(a); k<-floor(n*fr)
  if(k<6||(n-k)<6) return(c(NA,NA,NA))
  ia<-a[1:k]; oa<-a[(k+1):n]; ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  c(ii, oo, if(is.finite(ii)&&ii>0.05&&is.finite(oo)) oo/ii else NA_real_) }
mk_bt <- function(mm, nm, rb="quarterly"){
  sim <- list(DAILY_NAV_DT=data.table(Date=mm$dates, Strategy_Ret=mm$ret, NAV=cumprod(1+mm$ret)),
              strategy_xts=xts(mm$ret, order.by=mm$dates),
              bm_xts=xts(mm$ret-mm$act, order.by=mm$dates), cost_model_version="probe_a5_15bps")
  spec <- list(strategy_name=nm, description="A5 반증", universe="KR broad-21", rebalance=rb,
               signal="factor momentum")
  build_bt_result(sim, spec, run_id=tolower(nm), strategy_id=toupper(nm), benchmark_id="CAPW_PARENT",
    benchmark_name="cap-w parent", transaction_cost_bps=15, slippage_bps=0, frequency="monthly",
    universe_id="K200_KQ150", code_version="probe_a5_falsify2.R", created_by_agent="Q-Lead") }
ess <- function(mm, nm, rb="quarterly"){ e <- essence_score(mk_bt(mm,nm,rb), n_trials_cumulative=56,
    selection_type="chain"); list(g=e$grade, pt=e$essence$portfolio_alpha_t_nw_lag3,
    oos=e$essence$oos_retention, sp=e$oos_retention_splits, cal=e$essence$calmar,
    band=e$oos_band_status, dsr=e$essence$dsr) }

A5 <- mets(run_arm(S12,"cont",15,3,13)); a5a <- A5$act; n5 <- length(a5a)

## ======================= B. 말월 부분관측 =======================
cat("================ B: 표본 끝단 / 부분관측 월 ================\n")
cat(sprintf("  mon 마지막 3개월 거래일수: %s\n", paste(sprintf("%s(%dd)", tail(mon$ym,3), tail(mon$ndays,3)), collapse=" ")))
cat(sprintf("  A5 평가구간 실측 = %s .. %s (n=%d)  ※과제 브리프의 '2007-02~2026-07' 과 불일치\n",
    mon$ym[13], mon$ym[NM], A5$n))
e_full <- ess(A5, "PROBE_A5_FULL")
cat(sprintf("  [전체 n=236] pt=%.4f oos=%.4f(%s) splits=%s calmar=%.4f grade=%s\n",
    e_full$pt, e_full$oos, e_full$band, paste(sprintf("%.3f",e_full$sp),collapse="/"), e_full$cal, e_full$g))
for(cut in 1:3){ mm <- mets(run_arm(S12,"cont",15,3,13,nmax=NM-cut)); e <- ess(mm, sprintf("PROBE_A5_M%d",cut))
  cat(sprintf("  [말미 %d개월 제거 n=%d, ~%s] pt=%.4f oos=%.4f(%s) splits=%s calmar=%.4f\n",
      cut, mm$n, mon$ym[NM-cut], e$pt, e$oos, e$band, paste(sprintf("%.3f",e$sp),collapse="/"), e$cal)) }
for(cut in 1:3){ mm <- mets(run_arm(S12,"cont",15,3,13+cut)); e <- ess(mm, sprintf("PROBE_A5_S%d",cut))
  cat(sprintf("  [선두 %d개월 제거 n=%d, %s~] pt=%.4f oos=%.4f(%s) calmar=%.4f\n",
      cut, mm$n, mon$ym[13+cut], e$pt, e$oos, e$band, e$cal)) }

## ======================= C. 가족단위 경험적 max-pt 귀무 =======================
cat("\n================ C: 다중검정 — 경험적 가족 귀무분포 ================\n")
FAM <- function(Sp12, Sp6, Sp24){ c(
  C1  = PT(mets(run_arm(Sp12,"cont",15,1,13))$act),
  A2  = PT(mets(run_arm(Sp12,"rank",15,1,13))$act),
  A3  = PT(mets(run_arm(Sp6, "cont",15,1,13))$act),
  A4  = PT(mets(run_arm(Sp24,"cont",15,1,25))$act),
  A5p0= PT(mets(run_arm(Sp12,"cont",15,3,13,phase_off=0))$act),
  A5p1= PT(mets(run_arm(Sp12,"cont",15,3,13,phase_off=1))$act),
  A5p2= PT(mets(run_arm(Sp12,"cont",15,3,13,phase_off=2))$act)) }
real <- FAM(S12, S6, S24)
cat("  [실측 가족 7팔 pt]\n"); print(round(real,3))
set.seed(20260822); B <- 300
NULLM <- matrix(NA_real_, B, length(real)); colnames(NULLM) <- names(real)
t0 <- Sys.time()
for(b in 1:B){ pm <- sample(NM); NULLM[b,] <- FAM(S12[pm,,drop=FALSE], S6[pm,,drop=FALSE], S24[pm,,drop=FALSE]) }
cat(sprintf("  (%d 셔플, %.1fs)\n", B, as.numeric(difftime(Sys.time(),t0,units="secs"))))
mx5 <- apply(NULLM[, c("C1","A2","A3","A4","A5p0")], 1, max, na.rm=TRUE)
mx7 <- apply(NULLM, 1, max, na.rm=TRUE)
qs <- function(v) sprintf("mean=%.3f sd=%.3f q50=%.3f q90=%.3f q95=%.3f q99=%.3f",
    mean(v), sd(v), quantile(v,.5), quantile(v,.9), quantile(v,.95), quantile(v,.99))
cat(sprintf("  단일팔 A5p0 귀무 pt : %s | p(null>=3.232)=%.4f\n", qs(NULLM[,"A5p0"]), mean(NULLM[,"A5p0"]>=real["A5p0"])))
cat(sprintf("  가족5 max-pt 귀무   : %s | FWER p=%.4f\n", qs(mx5), mean(mx5>=real["A5p0"])))
cat(sprintf("  가족7 max-pt 귀무   : %s | FWER p=%.4f\n", qs(mx7), mean(mx7>=real["A5p0"])))
cat(sprintf("  -> 가족5 95%% 임계 t=%.3f / 가족7 95%% 임계 t=%.3f (관측 3.232 : %s / %s)\n",
    quantile(mx5,.95), quantile(mx7,.95), ifelse(real["A5p0"]>=quantile(mx5,.95),"통과","미달"),
    ifelse(real["A5p0"]>=quantile(mx7,.95),"통과","미달")))
cat(sprintf("  ※셔플 귀무 평균이 0 이 아님(단일팔 %.3f) = broad-21 풀 자체의 팩터 프리미엄 드리프트\n", mean(NULLM[,"A5p0"])))
fwrite(as.data.table(NULLM), file.path(OUTD, "c_family_null.csv"))

## ======================= D. oos_retention 미세 민감도 =======================
cat("\n================ D: oos_retention 0.704 취약성 ================\n")
grid <- round(seq(0.40, 0.90, by=0.01), 2)
OS <- rbindlist(lapply(grid, function(f){ v <- oos_at(a5a, f)
  data.table(split=f, k_IS=floor(n5*f), IS_IR=v[1], OOS_IR=v[2], retention=v[3]) }))
show <- OS[split %in% round(seq(0.40,0.90,0.05),2)]
print(show, digits=4)
g3 <- function(s) { v <- sapply(s, function(f) oos_at(a5a,f)[3]); median(v, na.rm=TRUE) }
cat(sprintf("\n  계약 v2 {55/65/75}      -> %s | median=%.4f  %s\n",
    paste(sprintf("%.4f", sapply(c(.55,.65,.75), function(f) oos_at(a5a,f)[3])), collapse=" / "),
    g3(c(.55,.65,.75)), ifelse(g3(c(.55,.65,.75))>=0.7,"PASS","FAIL")))
cat(sprintf("  [정정] 대안 {50/60/70/80} -> %s | median=%.4f  %s\n",
    paste(sprintf("%.4f", sapply(c(.50,.60,.70,.80), function(f) oos_at(a5a,f)[3])), collapse=" / "),
    g3(c(.50,.60,.70,.80)), ifelse(g3(c(.50,.60,.70,.80))>=0.7,"PASS","FAIL")))
for(alt in list(c(.50,.65,.80), c(.60,.70,.80), c(.50,.60,.70), c(.45,.60,.75), c(.55,.70,.85), c(.60,.65,.70)))
  cat(sprintf("  대안 {%s} -> median=%.4f  %s\n", paste(round(alt*100), collapse="/"),
      g3(alt), ifelse(g3(alt)>=0.7,"PASS","FAIL")))
cat(sprintf("\n  전 그리드(0.40~0.90, 0.01 간격, %d점): >=0.7 비율=%.3f | median=%.4f | min=%.4f max=%.4f\n",
    nrow(OS), mean(OS$retention>=0.7, na.rm=TRUE), median(OS$retention,na.rm=TRUE),
    min(OS$retention,na.rm=TRUE), max(OS$retention,na.rm=TRUE)))
cat("  중앙 앵커(0.65) 국소 민감도 — 1개월 이동만으로:\n")
for(k in (floor(n5*0.65)+(-3:3))){ ia<-a5a[1:k]; oa<-a5a[(k+1):n5]
  ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  cat(sprintf("    k=%d (split=%.4f, IS 끝=%s): retention=%.4f %s\n", k, k/n5,
      format(A5$dates[k],"%Y-%m"), oo/ii, ifelse(oo/ii>=0.7,"(>=0.7)","(<0.7)"))) }
cat("  중앙값 결정구조: {55,65,75} 정렬 -> 중앙값 = 0.65 분할 단 1점이 게이트를 결정\n")
## 날짜 기준 분할
for(cy in c(2014,2016,2017,2018,2020)){ k <- sum(as.integer(format(A5$dates,"%Y")) <= cy)
  ia<-a5a[1:k]; oa<-a5a[(k+1):n5]; ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  cat(sprintf("  날짜분할 IS<=%d (k=%d, %.3f): IS_IR=%.3f OOS_IR=%.3f retention=%.4f\n",
      cy, k, k/n5, ii, oo, oo/ii)) }
fwrite(OS, file.path(OUTD, "d_oos_grid.csv"))

## ======================= E. 위상팔 전지표 + 시프트 사다리 =======================
cat("\n================ E: 위상 3팔 전지표 + A5E + 시프트 사다리 ================\n")
PH <- list()
for(o in 0:2){ mm <- mets(run_arm(S12,"cont",15,3,13,phase_off=o)); e <- ess(mm, sprintf("PROBE_A5_PH%d",o))
  PH[[o+1]] <- data.table(arm=sprintf("A5_phase%d",o), n=mm$n, pt=e$pt, oos=e$oos, band=e$band,
    calmar=e$cal, SR=mm$SR, MDD=mm$MDD, TO=mm$TO, grade=e$g,
    HARD=sprintf("%s%s%s", ifelse(e$pt>=2.95,"P","F"), ifelse(e$oos>=0.7,"P","F"), ifelse(e$cal>=0.64,"P","F"))) }
mmE <- mets(run_a5e(S12,15,13)); eE <- ess(mmE, "PROBE_A5E")
PH[[4]] <- data.table(arm="A5E_ensemble", n=mmE$n, pt=eE$pt, oos=eE$oos, band=eE$band, calmar=eE$cal,
  SR=mmE$SR, MDD=mmE$MDD, TO=mmE$TO, grade=eE$g,
  HARD=sprintf("%s%s%s", ifelse(eE$pt>=2.95,"P","F"), ifelse(eE$oos>=0.7,"P","F"), ifelse(eE$cal>=0.64,"P","F")))
PHT <- rbindlist(PH); print(PHT, digits=4)
cat(sprintf("  A5E splits=%s\n", paste(sprintf("%.3f", eE$sp), collapse="/")))
cat("  [시프트 사다리 — 계약 PT 재산출]\n")
for(dl in 0:2){ mm <- mets(run_arm(S12,"cont",15,3,13,dec_lag=dl))
  cat(sprintf("    dec_lag=%d(%s): n=%d pt=%.4f IR=%.4f oos=%.4f\n", dl,
      c("동월(고의위반)","정본 m-1","실행지연 m-2")[dl+1], mm$n, mm$pt, mm$IR,
      median(sapply(c(.55,.65,.75), function(f) oos_at(mm$act,f)[3]), na.rm=TRUE))) }
fwrite(PHT, file.path(OUTD, "e_phase_full.csv"))

## ======================= F. 감쇠 =======================
cat("\n================ F: 알파 감쇠 ================\n")
yy <- as.integer(format(A5$dates, "%Y"))
h1 <- 1:floor(n5/2); h2 <- (floor(n5/2)+1):n5
cat(sprintf("  전반 %s~%s: mean_act_ann=%.4f IR=%.3f pt=%.3f\n", format(A5$dates[1],"%Y-%m"),
    format(A5$dates[max(h1)],"%Y-%m"), mean(a5a[h1])*12, IRf(a5a[h1]), PT(a5a[h1])))
cat(sprintf("  후반 %s~%s: mean_act_ann=%.4f IR=%.3f pt=%.3f\n", format(A5$dates[min(h2)],"%Y-%m"),
    format(A5$dates[n5],"%Y-%m"), mean(a5a[h2])*12, IRf(a5a[h2]), PT(a5a[h2])))
cat(sprintf("  차분 paired NW-t (전반-후반 평균차, 이표본) = %.3f\n",
    (mean(a5a[h1])-mean(a5a[h2]))/sqrt(var(a5a[h1])/length(h1)+var(a5a[h2])/length(h2))))
tt <- lm(a5a ~ seq_along(a5a)); ct <- lmtest::coeftest(tt, vcov=sandwich::NeweyWest(tt, lag=3, prewhite=FALSE))
cat(sprintf("  시간추세 회귀 active~t: slope=%.3e (NW t=%.3f, p=%.3f) — 음수면 감쇠\n",
    ct[2,1], ct[2,3], ct[2,4]))
YR <- rbindlist(lapply(sort(unique(yy)), function(Y) data.table(year=Y, n=sum(yy==Y),
  act_ann=mean(a5a[yy==Y])*12)))
cat("  연도별 active(연율):\n"); print(YR[, .(year, n, act_ann=round(act_ann,4))], nrows=25)
fwrite(YR, file.path(OUTD, "f_yearly_active.csv"))
cat("\nPROBE2_DONE\n")
sink()
