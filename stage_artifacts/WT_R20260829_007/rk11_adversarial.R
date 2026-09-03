# RK11 — Self-Adversarial 재도출 (진술이 아니라 재측정)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT<-getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3<-readRDS(file.path(OUT,"rk3_objects.rds")); o4<-readRDS(file.path(OUT,"rk4_objects.rds"))
o6<-readRDS(file.path(OUT,"rk6_objects.rds")); o7<-readRDS(file.path(OUT,"rk7_objects.rds"))
B<-o4$B; Om<-o4$Om_lw; dv<-o4$dv; wf<-o6$wf; w_cap<-o6$w_cap; STY<-o3$STY
condf <- function(M){e<-eigen((M+t(M))/2,symmetric=TRUE,only.values=TRUE)$values; c(mn=min(e),cond=max(e)/max(min(e),1e-16))}
mk <- function(Bm,Omm,Dvv){S<-Bm%*%Omm%*%t(Bm); diag(S)<-diag(S)+Dvv; (S+t(S))/2}

## ── S1: 특이위험 바닥 민감도 ──
cat("=== S1 특이위험 바닥 민감도 ===\n")
s1 <- rbindlist(lapply(c(0.00,0.02,0.05,0.10,0.20,0.30), function(q){
  fl <- if(q==0) 0 else as.numeric(quantile(dv$v_shrunk,q,na.rm=TRUE))
  Dvv <- pmax(dv$v_shrunk,fl)[match(rownames(B),dv$Ticker)]
  S <- mk(B,Om,Dvv); cc <- condf(S)
  v <- as.numeric(t(wf)%*%S%*%wf); d<-wf-w_cap
  data.table(floor_q=q, floor_vol_ann=sqrt(fl*12), cond=cc["cond"], min_eig=cc["mn"],
    book_vol_ann=sqrt(v*12), factor_share=as.numeric(t(as.numeric(t(B)%*%wf))%*%Om%*%as.numeric(t(B)%*%wf))/v,
    te_capw_ann=sqrt(as.numeric(t(d)%*%S%*%d)*12),
    beta_capw=as.numeric(t(wf)%*%S%*%w_cap)/as.numeric(t(w_cap)%*%S%*%w_cap),
    pass_500=cc["cond"]<500)}))
print(s1)

## ── S3: 구간 이질성이 절단점 선택의 산물인가 (라벨 없는 rolling) ──
cat("\n=== S3 라벨 없는 rolling 36M 진단 ===\n")
MS <- o7$MS[order(dt)]
roll <- function(x,k=36) sapply(seq_along(x), function(i) if(i<k) NA_real_ else mean(x[(i-k+1):i],na.rm=TRUE))
MS[, rv36 := roll(sqrt(var_b*252))][, rc36 := roll(avg_corr)]
cat(sprintf("rolling36 book vol: min %.3f max %.3f ratio %.2f | 절단점판 min %.3f max %.3f ratio %.2f\n",
  min(MS$rv36,na.rm=TRUE),max(MS$rv36,na.rm=TRUE),max(MS$rv36,na.rm=TRUE)/min(MS$rv36,na.rm=TRUE),
  min(o7$sp$book_vol_ann),max(o7$sp$book_vol_ann),max(o7$sp$book_vol_ann)/min(o7$sp$book_vol_ann)))
cat(sprintf("rolling36 pairwise corr: min %.4f max %.4f ratio %.2f | 절단점판 %.4f~%.4f ratio %.2f\n",
  min(MS$rc36,na.rm=TRUE),max(MS$rc36,na.rm=TRUE),max(MS$rc36,na.rm=TRUE)/min(MS$rc36,na.rm=TRUE),
  min(o7$sp$avg_pairwise_corr),max(o7$sp$avg_pairwise_corr),max(o7$sp$avg_pairwise_corr)/min(o7$sp$avg_pairwise_corr)))
cat("rolling36 vol 상위/하위 시점:\n")
print(MS[!is.na(rv36)][order(-rv36)][c(1,2,.N-1,.N),.(ym,rv36,rc36)])

## ── S4: SIGNAL 을 위험요인에서 빼면 결론이 바뀌는가 ──
cat("\n=== S4 SIGNAL 제외 Σ ===\n")
keep <- setdiff(colnames(B),"SIGNAL")
B2 <- B[,keep,drop=FALSE]; Om2 <- Om[keep,keep]
Dv2 <- o6$Dv  # 잔차는 재추정 없이 기존값 사용(보수적: SIGNAL 분산이 D 로 안 감 → 총위험 과소)
S2 <- mk(B2,Om2,Dv2); c2 <- condf(S2)
v2 <- as.numeric(t(wf)%*%S2%*%wf); d<-wf-w_cap
bw2 <- as.numeric(t(B2)%*%wf)
cat(sprintf("cond %.1f (원 %.1f) · book vol %.4f (원 %.4f) · 요인share %.4f (원 %.4f) · TE %.4f (원 %.4f) · beta %.3f (원 %.3f)\n",
  c2["cond"], o6$ca["cond"], sqrt(v2*12), o6$sig_ann,
  as.numeric(t(bw2)%*%Om2%*%bw2)/v2, o6$fac_var/o6$sig2,
  sqrt(as.numeric(t(d)%*%S2%*%d)*12), sqrt(o7$av2*12),
  as.numeric(t(wf)%*%S2%*%w_cap)/as.numeric(t(w_cap)%*%S2%*%w_cap), o7$bet_cap))
# SIGNAL 제외 시 top common risk 순위
grp2 <- c(MKT="MKT", setNames(rep("SECTOR",length(o4$secs_a)),o4$secs_a), setNames(setdiff(STY,"SIGNAL"),setdiff(STY,"SIGNAL")))
cs2 <- tapply(bw2*as.numeric(Om2%*%bw2), grp2[colnames(B2)], sum)/v2
print(round(100*sort(cs2,decreasing=TRUE),2))

## ── S2: 결정 도메인이 25종으로 고정된 경우의 추정기 순위 ──
cat("\n=== S2 25종 고정 도메인 bias 재확인 ===\n")
WF <- readRDS(file.path(OUT,"rk5_wf.rds")); mu<-mean(WF$ret)
for(k in c("v_struct_l","v_struct_s","v_dir_s","v_dir_l","v_dir_n"))
  cat(sprintf("  %-12s bias %.4f |bias-1| %.4f\n", k, sd((WF$ret-mu)/sqrt(WF[[k]]),na.rm=TRUE),
      abs(sd((WF$ret-mu)/sqrt(WF[[k]]),na.rm=TRUE)-1)))
saveRDS(list(s1=s1, MS=MS, s4=list(cond=c2["cond"],vol=sqrt(v2*12),cs2=cs2)), file.path(OUT,"rk11_objects.rds"))
cat("\n[RK11] done\n")
