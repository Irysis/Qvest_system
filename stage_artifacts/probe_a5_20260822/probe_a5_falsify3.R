## probe_a5_falsify3.R — 결정적 3종
##  G. 창(window) 과 위상(phase) 의 분리  — probe2 의 '선두 j개월 제거' 는 start_m 이동이라 위상 교락이었음(자기정정 3)
##  H. 영향점 분석 (연도/월 제거, winsorize)  — 2026 부분연도 act_ann +31.0% 의 지배력
##  I. 확장 가족(48팔) 실측 argmax + 경험적 max-pt 귀무 -> n_trials 56 규모 탐색의 FWER 보정 임계 t
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log3.txt"), split = TRUE)
IRf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
PT  <- function(x) .nw_t_mean(x[is.finite(x)], lag = 3L)
R <- as.data.table(read_parquet("outputs/ramp/dfa_index_returns_broad_202608.parquet"))
R[, Date := as.Date(Date)]; setorder(R, Date); R <- R[is.finite(Market)]
fac <- setdiff(names(R), c("Date","ym","as_of_date","source_version","Market")); R[, ym := format(Date,"%Y-%m")]
mon <- R[, c(lapply(.SD, function(x) prod(1+ifelse(is.finite(x),x,0))-1), .(medate=max(Date))),
         by=ym, .SDcols=c("Market",fac)]
setorder(mon, medate); NM <- nrow(mon); NAx <- 1+length(fac)
RET <- as.matrix(mon[, c("Market",fac), with=FALSE]); RET[!is.finite(RET)] <- 0
mk_sig <- function(win){ S <- matrix(NA_real_,NM,length(fac)); colnames(S) <- fac
  for(fi in seq_along(fac)) for(m in win:NM){ w <- (m-win+1):m
    S[m,fi] <- prod(1+mon[[fac[fi]]][w])/prod(1+mon$Market[w])-1 }; S }
run_arm <- function(S, mode="cont", bps=15, freq=1, start_m=13, phase_off=0){
  pr <- rep(NA_real_,NM); tov <- rep(NA_real_,NM); wprev <- rep(1/NAx,NAx); wcur <- NULL
  for(m in start_m:NM){ d <- m-1
    if(is.null(wcur) || ((m-start_m-phase_off) %% freq == 0)){
      s <- S[d,]; pos <- which(is.finite(s)&s>0); w <- rep(0,NAx)
      if(length(pos)==0){ w[1] <- 1 } else if(mode=="cont"){ w[1+pos] <- s[pos]/sum(s[pos])
      } else { rk <- rank(s[pos]); w[1+pos] <- rk/sum(rk) }
      wcur <- w }
    ri <- RET[m,]; dlt <- sum(abs(wcur-wprev)); tov[m] <- dlt
    pr[m] <- sum(wcur*ri)-(bps/1e4)*dlt
    wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }
  list(pr=pr, tov=tov) }
S12 <- mk_sig(12)
r5 <- run_arm(S12,"cont",15,3,13); k5 <- is.finite(r5$pr)
a5 <- r5$pr[k5] - mon$Market[k5]; dt5 <- mon$medate[k5]; n5 <- length(a5)
yy <- as.integer(format(dt5,"%Y"))
oos3 <- function(a){ median(sapply(c(.55,.65,.75), function(fr){ a<-a[is.finite(a)]; n<-length(a); k<-floor(n*fr)
  if(k<6||(n-k)<6) return(NA_real_); ia<-a[1:k]; oa<-a[(k+1):n]
  ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  if(is.finite(ii)&&ii>0.05&&is.finite(oo)) oo/ii else NA_real_ }), na.rm=TRUE) }

## ================= G. 창 vs 위상 분리 =================
cat("================ G: 창(window) 과 위상(phase) 분리 ================\n")
cat("  probe2 의 '선두 j개월 제거'(start_m=13+j) 는 리밸 위상을 함께 이동시켜 교락되어 있었다.\n")
cat("  여기서는 위상을 offset0 로 고정한 채(동일 pr 시계열) 평가창만 잘라낸다.\n")
GG <- rbindlist(lapply(0:12, function(j){ s <- (j+1):n5
  data.table(drop_head=j, from=format(dt5[j+1],"%Y-%m"), n=length(s), pt=PT(a5[s]),
             IR=IRf(a5[s]), oos=oos3(a5[s])) }))
print(GG, digits=4)
cat(sprintf("  -> 위상 고정 시 선두 절단 pt 범위 %.3f~%.3f, 2.95 미달 %d/13  (교락판 2.208 은 위상효과였음)\n",
    min(GG$pt), max(GG$pt), sum(GG$pt<2.95)))

## ================= H. 영향점 =================
cat("\n================ H: 영향점 / 이상월 지배력 ================\n")
cat(sprintf("  전체: pt=%.4f IR=%.4f mean_act_ann=%.4f oos=%.4f\n", PT(a5), IRf(a5), mean(a5)*12, oos3(a5)))
cat("  [H1] 2026 부분연도(8개월) 처리\n")
for(lab in c("2026 제외","2025-2026 제외")){ s <- if(lab=="2026 제외") yy<=2025 else yy<=2024
  cat(sprintf("    %-14s: n=%d pt=%.4f IR=%.4f oos=%.4f\n", lab, sum(s), PT(a5[s]), IRf(a5[s]), oos3(a5[s]))) }
top <- order(a5, decreasing=TRUE)[1:8]
cat("  [H2] 상위 active 월 8개\n")
print(data.table(rank=1:8, ym=format(dt5[top],"%Y-%m"), act=round(a5[top],4)))
for(j in c(1,2,3,5)){ s <- setdiff(seq_len(n5), order(a5, decreasing=TRUE)[1:j])
  cat(sprintf("    상위 %d개월 제거: n=%d pt=%.4f IR=%.4f oos=%.4f %s\n", j, length(s),
      PT(a5[s]), IRf(a5[s]), oos3(a5[s]), ifelse(PT(a5[s])>=2.95,"[pt PASS]","[pt FAIL]"))) }
cat("  [H3] winsorize (양측)\n")
for(q in c(0.01, 0.025, 0.05)){ lo <- quantile(a5,q); hi <- quantile(a5,1-q); w <- pmin(pmax(a5,lo),hi)
  cat(sprintf("    %4.1f%%: pt=%.4f IR=%.4f oos=%.4f %s\n", q*100, PT(w), IRf(w), oos3(w),
      ifelse(PT(w)>=2.95,"[pt PASS]","[pt FAIL]"))) }
cat("  [H4] leave-one-MONTH-out : pt 최저 5\n")
LM <- rbindlist(lapply(seq_len(n5), function(i) data.table(drop=format(dt5[i],"%Y-%m"),
  act=a5[i], pt=PT(a5[-i])))); setorder(LM, pt)
print(head(LM,5), digits=4)
cat(sprintf("    LOO-month pt: min=%.4f max=%.4f | 2.95 미달 %d/%d\n",
    min(LM$pt), max(LM$pt), sum(LM$pt<2.95), n5))
fwrite(LM, file.path(OUTD,"h_leave_one_month.csv"))

## ================= I. 확장 가족 + FWER 임계 t =================
cat("\n================ I: 확장 가족(자연 탐색공간) 실측 + 경험적 FWER ================\n")
WINS <- c(3,6,9,12,18,24); MODES <- c("cont","rank"); FREQS <- c(1,3,6)
GRID <- CJ(win=WINS, mode=MODES, freq=FREQS, sorted=FALSE)
GRID[, phase := 0L]
GP <- rbindlist(lapply(1:2, function(p){ g <- copy(GRID[freq>1]); g[, phase := p]; g }))
GRID <- rbind(GRID, GP)
cat(sprintf("  가족 크기 = %d 팔 (창6 x 가중2 x 주기3 = 36, + 주기>1 의 위상 2종 24 = 60)\n", nrow(GRID)))
SIGS <- lapply(setNames(WINS, as.character(WINS)), mk_sig)
fam_pt <- function(SL){ vapply(seq_len(nrow(GRID)), function(i){ g <- GRID[i]
  S <- SL[[as.character(g$win)]]; sm <- max(13, g$win+1)
  r <- run_arm(S, g$mode, 15, g$freq, sm, g$phase); kk <- is.finite(r$pr)
  PT(r$pr[kk]-mon$Market[kk]) }, numeric(1)) }
realf <- fam_pt(SIGS)
FR <- cbind(GRID, pt=realf); setorder(FR, -pt)
cat("  [실측 가족 상위 8]\n"); print(head(FR,8), digits=4)
cat("  [실측 가족 하위 4]\n"); print(tail(FR,4), digits=4)
cat(sprintf("  A5(win12/cont/freq3/phase0) 실측 pt=%.4f = 가족 내 순위 %d/%d (백분위 %.3f)\n",
    FR[win==12&mode=="cont"&freq==3&phase==0, pt],
    which(FR$win==12 & FR$mode=="cont" & FR$freq==3 & FR$phase==0), nrow(FR),
    mean(realf <= FR[win==12&mode=="cont"&freq==3&phase==0, pt])))
cat(sprintf("  가족 실측 max pt=%.4f (%s) | 2.95 통과 팔 %d/%d\n", max(realf),
    paste(FR[1, .(win,mode,freq,phase)], collapse="/"), sum(realf>=2.95), length(realf)))
set.seed(20260822); B <- 300
mxN <- numeric(B); t0 <- Sys.time()
for(b in 1:B){ pm <- sample(NM)
  SLp <- lapply(SIGS, function(S) S[pm,,drop=FALSE])
  mxN[b] <- max(fam_pt(SLp), na.rm=TRUE) }
cat(sprintf("  (%d 셔플 x %d 팔 = %d run, %.1fs)\n", B, nrow(GRID), B*nrow(GRID),
    as.numeric(difftime(Sys.time(),t0,units="secs"))))
cat(sprintf("  가족%d max-pt 귀무: mean=%.3f sd=%.3f q50=%.3f q90=%.3f q95=%.3f q99=%.3f\n",
    nrow(GRID), mean(mxN), sd(mxN), quantile(mxN,.5), quantile(mxN,.9), quantile(mxN,.95), quantile(mxN,.99)))
obs <- FR[win==12&mode=="cont"&freq==3&phase==0, pt]
cat(sprintf("  -> A5 pt=%.4f 의 FWER p = %.4f | 가족 실측 max=%.4f 의 FWER p = %.4f\n",
    obs, mean(mxN>=obs), max(realf), mean(mxN>=max(realf))))
cat(sprintf("  -> 이 가족규모(%d, 실제 상관구조 반영)에서 alpha=0.05 FWER 임계 t = %.3f (관측 %.3f : %s)\n",
    nrow(GRID), quantile(mxN,.95), obs, ifelse(obs>=quantile(mxN,.95),"통과","미달")))
cat(sprintf("  -> alpha=0.01 임계 t = %.3f (관측 %.3f : %s)\n", quantile(mxN,.99), obs,
    ifelse(obs>=quantile(mxN,.99),"통과","미달")))
cat(sprintf("  참고: 독립 56시행 Bonferroni 임계 t=%.3f / 독립 60시행 %.3f — 상관 무시 시 과대보정\n",
    qnorm(1-0.05/(2*56)), qnorm(1-0.05/(2*60))))
fwrite(FR, file.path(OUTD,"i_family_real.csv"))
fwrite(data.table(b=1:B, max_pt=mxN), file.path(OUTD,"i_family_null_max.csv"))
cat("\nPROBE3_DONE\n")
sink()
