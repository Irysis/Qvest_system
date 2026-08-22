## probe_a5_falsify4.R — J. 가족규모별 FWER 보정 곡선 (n_trials=56 지점 직접 답)
##                        K. 2026 부분연도 지배력 해부 (oos_retention 0.704 의 실제 담지자)
suppressPackageStartupMessages({library(data.table); library(arrow)})
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/contracts/backtest_result_contract.R")
OUTD <- "stage_artifacts/probe_a5_20260822"
sink(file.path(OUTD, "probe_a5_log4.txt"), split = TRUE)
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
  pr <- rep(NA_real_,NM); tov <- rep(NA_real_,NM); wprev <- rep(1/NAx,NAx); wcur <- NULL; WH <- matrix(NA_real_,NM,NAx)
  for(m in start_m:NM){ d <- m-1
    if(is.null(wcur) || ((m-start_m-phase_off) %% freq == 0)){
      s <- S[d,]; pos <- which(is.finite(s)&s>0); w <- rep(0,NAx)
      if(length(pos)==0){ w[1] <- 1 } else if(mode=="cont"){ w[1+pos] <- s[pos]/sum(s[pos])
      } else { rk <- rank(s[pos]); w[1+pos] <- rk/sum(rk) }
      wcur <- w }
    WH[m,] <- wcur
    ri <- RET[m,]; dlt <- sum(abs(wcur-wprev)); tov[m] <- dlt
    pr[m] <- sum(wcur*ri)-(bps/1e4)*dlt
    wd <- wcur*(1+ri); wprev <- wd/sum(wd); wcur <- wprev }
  list(pr=pr, tov=tov, W=WH) }
oos3 <- function(a){ median(sapply(c(.55,.65,.75), function(fr){ a<-a[is.finite(a)]; n<-length(a); k<-floor(n*fr)
  if(k<6||(n-k)<6) return(NA_real_); ia<-a[1:k]; oa<-a[(k+1):n]
  ii<-mean(ia)/sd(ia)*sqrt(12); oo<-mean(oa)/sd(oa)*sqrt(12)
  if(is.finite(ii)&&ii>0.05&&is.finite(oo)) oo/ii else NA_real_ }), na.rm=TRUE) }

WINS <- c(3,6,9,12,18,24); MODES <- c("cont","rank"); FREQS <- c(1,3,6)
GRID <- CJ(win=WINS, mode=MODES, freq=FREQS, sorted=FALSE); GRID[, phase := 0L]
GP <- rbindlist(lapply(1:2, function(p){ g <- copy(GRID[freq>1]); g[, phase := p]; g }))
GRID <- rbind(GRID, GP); NG <- nrow(GRID)
iA5 <- which(GRID$win==12 & GRID$mode=="cont" & GRID$freq==3 & GRID$phase==0)
SIGS <- lapply(setNames(WINS, as.character(WINS)), mk_sig)
fam_pt <- function(SL){ vapply(seq_len(NG), function(i){ g <- GRID[i]
  S <- SL[[as.character(g$win)]]; sm <- max(13, g$win+1)
  r <- run_arm(S, g$mode, 15, g$freq, sm, g$phase); kk <- is.finite(r$pr)
  PT(r$pr[kk]-mon$Market[kk]) }, numeric(1)) }
realf <- fam_pt(SIGS); obs <- realf[iA5]

cat("================ J: 가족규모별 FWER 보정 곡선 ================\n")
set.seed(20260822); B <- 800
NULLM <- matrix(NA_real_, B, NG)
t0 <- Sys.time()
for(b in 1:B){ pm <- sample(NM); NULLM[b,] <- fam_pt(lapply(SIGS, function(S) S[pm,,drop=FALSE])) }
cat(sprintf("  (%d 셔플 x %d 팔 = %s run, %.0fs)\n", B, NG, format(B*NG, big.mark=","),
    as.numeric(difftime(Sys.time(),t0,units="secs"))))
saveRDS(list(NULLM=NULLM, GRID=GRID, realf=realf), file.path(OUTD,"j_null_matrix.rds"))
cat(sprintf("  단일팔(A5 좌표) 귀무 pt: mean=%.3f sd=%.3f q95=%.3f | 단독 p=%.4f\n",
    mean(NULLM[,iA5]), sd(NULLM[,iA5]), quantile(NULLM[,iA5],.95), mean(NULLM[,iA5]>=obs)))
set.seed(77); NSUB <- 400
CURVE <- rbindlist(lapply(c(1,3,5,7,10,15,20,30,40,56,70,84), function(N){
  if(N > NG) return(NULL)
  ps <- numeric(NSUB); c95 <- numeric(NSUB)
  for(s in 1:NSUB){ idx <- if(N==1) iA5 else c(iA5, sample(setdiff(1:NG, iA5), N-1))
    mx <- apply(NULLM[, idx, drop=FALSE], 1, max, na.rm=TRUE)
    ps[s] <- mean(mx >= obs); c95[s] <- quantile(mx, .95) }
  data.table(family_N=N, FWER_p=mean(ps), FWER_p_sd=sd(ps), crit_t_05=mean(c95),
             verdict=ifelse(mean(ps)<0.05, "유의", "비유의")) }))
print(CURVE, digits=4)
cat(sprintf("\n  ★ n_trials_cumulative=56 지점: FWER p=%.3f, alpha=.05 임계 t=%.3f (관측 %.3f -> %s)\n",
    CURVE[family_N==56, FWER_p], CURVE[family_N==56, crit_t_05], obs,
    ifelse(CURVE[family_N==56, FWER_p]<0.05, "생존", "미생존")))
cat(sprintf("  ★ 이번 라운드 사전등록 5팔만 셀 때(N=5): FWER p=%.3f, 임계 t=%.3f -> %s\n",
    CURVE[family_N==5, FWER_p], CURVE[family_N==5, crit_t_05],
    ifelse(CURVE[family_N==5, FWER_p]<0.05, "생존", "미생존")))
nb <- CURVE[FWER_p >= 0.05, min(family_N)]
cat(sprintf("  ★ 유의성이 깨지는 가족규모 임계 = N>=%d (그 이하면 생존)\n", nb))
fwrite(CURVE, file.path(OUTD,"j_fwer_curve.csv"))

cat("\n================ K: 2026 부분연도 지배력 해부 ================\n")
r5 <- run_arm(mk_sig(12),"cont",15,3,13); k5 <- is.finite(r5$pr)
a5 <- r5$pr[k5]-mon$Market[k5]; dt5 <- mon$medate[k5]; n5 <- length(a5); yy <- as.integer(format(dt5,"%Y"))
cat("  [K1] 2026 월별 (active = 포트 - Market)\n")
i26 <- which(yy==2026)
print(data.table(ym=format(dt5[i26],"%Y-%m"), port=round(r5$pr[k5][i26],4),
                 mkt=round(mon$Market[k5][i26],4), active=round(a5[i26],4)))
cat(sprintf("  2026 8개월 누적 active 합=%.4f (전체 236개월 active 합=%.4f 의 %.1f%%)\n",
    sum(a5[i26]), sum(a5), 100*sum(a5[i26])/sum(a5)))
cat("  [K2] 2026-05 최대월 기여 팩터 (결정월 2026-04 말 비중 x 당월 초과수익)\n")
m05 <- which(mon$ym=="2026-05"); w05 <- r5$W[m05,]
contrib <- w05*(RET[m05,]-RET[m05,1]); names(contrib) <- c("Market",fac)
print(head(sort(contrib, decreasing=TRUE),6), digits=4)
cat("  [K3] oos_retention 담지자 — 말미 절단\n")
for(cut in c(0,1,2,3,4,6,8,12)){ s <- 1:(n5-cut)
  cat(sprintf("    말미 %2d개월 제거(~%s, n=%d): pt=%.4f oos=%.4f %s\n", cut, format(dt5[n5-cut],"%Y-%m"),
      length(s), PT(a5[s]), oos3(a5[s]), ifelse(oos3(a5[s])>=0.7,"[oos PASS]","[oos FAIL]"))) }
cat("  [K4] 2026-05 단일월만 제거\n")
s <- setdiff(1:n5, which(format(dt5,"%Y-%m")=="2026-05"))
cat(sprintf("    n=%d pt=%.4f oos=%.4f %s\n", length(s), PT(a5[s]), oos3(a5[s]),
    ifelse(oos3(a5[s])>=0.7,"[oos PASS]","[oos FAIL]")))
cat("  [K5] OOS 구간(split .65 = 2019-10~) 내부 분해\n")
k65 <- floor(n5*0.65); oa <- a5[(k65+1):n5]; od <- dt5[(k65+1):n5]
cat(sprintf("    OOS n=%d (%s~%s) IR=%.4f\n", length(oa), format(od[1],"%Y-%m"),
    format(od[length(od)],"%Y-%m"), IRf(oa)))
o26 <- as.integer(format(od,"%Y"))==2026
cat(sprintf("    OOS 중 2026 제외 시 IS_IR=%.4f OOS_IR=%.4f -> retention=%.4f\n",
    IRf(a5[1:k65]), IRf(oa[!o26]), IRf(oa[!o26])/IRf(a5[1:k65])))
cat("\nPROBE4_DONE\n")
sink()
