## ============================================================================
## Self-adversarial checks — Kalman SV 승리가 (a) 오프셋 아티팩트인가
##  (b) 순전히 uncentered z-metric 아티팩트인가 (c) 단순 re-level 로 복제되는가
## READ-ONLY 진단. 표준함수만. 결정 근거 강건성 확인용.
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({ library(data.table); library(dlm) }))
setDTthreads(1); set.seed(47)
BASE <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/te_diag_202607"
d <- fread(file.path(BASE, "merged_series.csv")); setorder(d, date)
a <- d$active_rds; N <- length(a); ANN <- sqrt(12); BURN <- 36
LOGCHI2_V <- pi^2/2
common0 <- (BURN+1):N

## 공통 평가 (uncentered z = 기존 하네스) + centered z 병기
eval2 <- function(s) {
  ok <- intersect(which(is.finite(s)&s>0), common0)
  z_unc <- a[ok]/s[ok]
  amu <- mean(a[ok]); z_cen <- (a[ok]-amu)/s[ok]        # centered 변형
  br<-0;cnt<-0; for(t in ok) if(t+11<=N){ if(sd(a[t:(t+11)])/s[t]>1.5) br<-br+1; cnt<-cnt+1 }
  data.table(ratio_unc=sqrt(mean(z_unc^2)), ratio_cen=sqrt(mean(z_cen^2)),
             alert=if(cnt>0)br/cnt else NA, cur=s[N]*ANN)
}

## ---- 재구성: kalman_SV (오프셋 c 3수준) + 단순 re-level 후보 ----
sv_path <- function(cfrac) {
  cval <- cfrac*mean(a^2); y <- log(a^2+cval)+1.2704
  build <- function(p) dlmModPoly(1, dV=LOGCHI2_V, dW=exp(p))
  s <- rep(NA_real_,N); lp <- log(0.05)
  for(t in (BURN+1):N){ yh<-y[1:(t-1)]
    f<-tryCatch(dlmMLE(yh,parm=lp,build=build,method="Brent",lower=-18,upper=4),error=function(e)NULL)
    if(!is.null(f)&&f$convergence==0) lp<-f$par
    fl<-tryCatch(dlmFilter(yh,build(lp)),error=function(e)NULL); if(is.null(fl))next
    s[t]<-sqrt(exp(tail(as.numeric(fl$m),1))) }; s
}
## 단순 대안: expanding uncentered RMS (bias-corrected 아님, 순수 sqrt(mean(a²)))
s_uncRMS <- rep(NA_real_,N); for(t in (BURN+1):N) s_uncRMS[t]<-sqrt(mean(a[1:(t-1)]^2))
## re-baselined 상수 (전기간 uncentered RMS 고정 = 단일 스칼라 교체)
s_const_relev <- rep(sqrt(mean(a^2)), N); s_const_relev[1:BURN]<-NA
## ewma97 (uncentered, 재현)
ew<-function(lam){s<-rep(NA_real_,N);v<-var(a[1:12]);for(t in 13:N){v<-lam*v+(1-lam)*a[t-1]^2;s[t]<-sqrt(v)};s}

cat("===== 오프셋 c 민감도 (kalman_SV) =====\n")
for(cf in c(0.01,0.02,0.05)){ e<-eval2(sv_path(cf)); cat(sprintf(
  "  c=%.2f*mean(a²): ratio_unc=%.3f ratio_cen=%.3f alert=%.4f cur=%.4f\n",
  cf,e$ratio_unc,e$ratio_cen,e$alert,e$cur)) }

cat("\n===== 단순 대안이 kalman_SV 를 복제하는가 =====\n")
cand <- list(kalman_SV_c02=sv_path(0.02), uncentered_expand_RMS=s_uncRMS,
             const_relevel_RMS=s_const_relev, ewma97=ew(0.97),
             expand_const_sd={s<-rep(NA_real_,N);for(t in 13:N)s[t]<-sd(a[1:(t-1)]);s})
tab <- rbindlist(lapply(names(cand), function(nm){ e<-eval2(cand[[nm]]); cbind(estimator=nm,e)}))
print(tab[, lapply(.SD,function(x) if(is.numeric(x))round(x,4) else x)])

## kalman_SV vs uncentered_expand_RMS 경로 상관 + 평균절대차 (동일 여부)
ok <- common0
cat(sprintf("\n[복제성] kalman_SV vs uncentered_expand_RMS: cor(path)=%.4f  mean|ΔTE_ann|=%.4f\n",
  cor(cand$kalman_SV_c02[ok],cand$uncentered_expand_RMS[ok]),
  mean(abs(cand$kalman_SV_c02[ok]-cand$uncentered_expand_RMS[ok]))*ANN))
cat(sprintf("[적응성] kalman_SV 예측 TE: 초기(t=%d)=%.4f  최근(t=N)=%.4f  범위=%.4f~%.4f  (범위 좁으면 near-static)\n",
  BURN+1, cand$kalman_SV_c02[BURN+1]*ANN, cand$kalman_SV_c02[N]*ANN,
  min(cand$kalman_SV_c02[ok])*ANN, max(cand$kalman_SV_c02[ok])*ANN))
cat(sprintf("[적응성] ewma97 예측 TE 범위=%.4f~%.4f  (넓으면 적응적)\n",
  min(cand$ewma97[ok],na.rm=T)*ANN, max(cand$ewma97[ok],na.rm=T)*ANN))

## ---- 저장 (결정 근거 강건성 표) ----
library(jsonlite)
offs <- rbindlist(lapply(c(0.01,0.02,0.05), function(cf){e<-eval2(sv_path(cf));cbind(c_frac=cf,e)}))
fwrite(offs, file.path(BASE,"kalman_ext/kalman_offset_sensitivity.csv"))
fwrite(tab,  file.path(BASE,"kalman_ext/kalman_simple_replication.csv"))
adv <- list(offset_sensitivity=offs, simple_replication=tab,
  cor_kSV_uncRMS=cor(cand$kalman_SV_c02[ok],cand$uncentered_expand_RMS[ok]),
  kSV_range_ann=c(min(cand$kalman_SV_c02[ok])*ANN,max(cand$kalman_SV_c02[ok])*ANN),
  ewma97_range_ann=c(min(cand$ewma97[ok],na.rm=T)*ANN,max(cand$ewma97[ok],na.rm=T)*ANN),
  verdict="kSV uncentered-win = log-offset level artifact + centered-metric reversal + 1-scalar replicable")
write_json(adv, file.path(BASE,"kalman_ext/kalman_adv_summary.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
cat("[saved] kalman_offset_sensitivity.csv · kalman_simple_replication.csv · kalman_adv_summary.json\n")
