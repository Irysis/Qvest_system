# R4 — 최종 Sigma 확정(ewma_hl126 + eigen-floor) · 위험분해 · 국면별 Sigma 이질성
# C5: panic 라벨은 alpha 산출 regime_signal_timeseries(used_cutoff <= holding_month_start) 소비만.
#     일자 d 의 라벨 = d 가 속한 홀딩월의 라벨 = 그 월 시작 전에 확정된 값(동월 정보 미사용).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
source(file.path(ROOT,"02_Infrastructure/portfolio/hrp_core.R"))
S <- readRDS(file.path(OUT,"risk_calc_stage1.rds")); MON <- 21L
FRET<-S$FRET; EXP<-S$EXP; secs<-S$secs; STYLES<-S$STYLES; FCOLS<-S$FCOLS
Bmat<-S$Bmat; Dvec<-S$Dvec; HOLD_CUR<-S$HOLD_CUR; Xfull<-S$Xfull; yms<-S$yms
M2 <- readRDS(file.path(OUT,"risk_factor_model.rds")); ERES <- M2$ERES; ERES[, ym := format(Date,"%Y-%m")]
PANIC_YM <- S$PANIC_YM
cond_of <- function(Z){ ev<-eigen((Z+t(Z))/2,symmetric=TRUE,only.values=TRUE)$values
  list(cond=max(ev)/max(min(ev),.Machine$double.eps), min_ev=min(ev), psd=min(ev)>=-1e-12) }
eig_floor <- function(Z, frac){ e<-eigen((Z+t(Z))/2,symmetric=TRUE)
  lam<-pmax(e$values, frac*max(e$values)); O<-e$vectors%*%diag(lam)%*%t(e$vectors)
  dimnames(O)<-dimnames(Z); (O+t(O))/2 }

SEL <- "ewma_hl126"
Om_raw <- S$OM[[SEL]]; live <- attr(Om_raw,"live")
c_before <- cond_of(Om_raw[live,live,drop=FALSE])
Om_f <- Om_raw; Om_f[live,live] <- eig_floor(Om_raw[live,live,drop=FALSE], frac=1/400)
c_after <- cond_of(Om_f[live,live,drop=FALSE])
sig_of <- function(B,Om,dv) { Z<-B%*%Om%*%t(B)+diag(dv[rownames(B)],nrow(B)); (Z+t(Z))/2*MON }
Sig_raw <- sig_of(Bmat, Om_raw, Dvec); Sig <- sig_of(Bmat, Om_f, Dvec)
cs_b <- cond_of(Sig_raw); cs_a <- cond_of(Sig)
w <- rep(1/25, 25)
pv <- function(Z) as.numeric(t(w) %*% Z %*% w)
cat(sprintf("[R4] Omega cond %.1f -> %.1f (eigen-floor 1/400) | Sigma cond %.1f -> %.1f | volEW %.1f%% -> %.1f%%\n",
  c_before$cond, c_after$cond, cs_b$cond, cs_a$cond, 100*sqrt(pv(Sig_raw)*12), 100*sqrt(pv(Sig)*12)))

## 위험분해 (EW 진단기준 · 비중 제안 아님)
grp <- ifelse(FCOLS=="Market","Market", ifelse(FCOLS %in% STYLES,"Style","Sector"))
Bw <- as.numeric(t(Bmat) %*% w)
tot <- pv(Sig)
fac_cov_contrib <- outer(Bw,Bw)*Om_f*MON
spec_var <- sum(w^2*Dvec)*MON
grp_share <- sapply(c("Market","Sector","Style"), function(g){
  idx <- which(grp==g); sum(fac_cov_contrib[idx, , drop=FALSE])/tot })
fac_share <- sapply(seq_along(FCOLS), function(i) sum(fac_cov_contrib[i,])/tot)
names(fac_share) <- FCOLS
spec_share <- spec_var/tot
cat(sprintf("[R4] 분산분해 Market %.1f%% Sector %.1f%% Style %.1f%% Specific %.1f%% (합 %.1f%%)\n",
  100*grp_share[1],100*grp_share[2],100*grp_share[3],100*spec_share,
  100*(sum(grp_share)+spec_share)))
top_fac <- sort(fac_share, decreasing=TRUE)[1:8]
print(round(100*top_fac,2))

## 요인 상관 경고
sdv <- sqrt(diag(Om_f)); ok <- which(sdv>0)
Cor <- Om_f[ok,ok]/outer(sdv[ok],sdv[ok])
pairs_hi <- which(abs(Cor)>0.8 & upper.tri(Cor), arr.ind=TRUE)
fc_warn <- if(nrow(pairs_hi)) data.table(f1=colnames(Cor)[pairs_hi[,1]], f2=colnames(Cor)[pairs_hi[,2]],
                                          rho=Cor[pairs_hi]) else data.table()
cat(sprintf("[R4] abs(rho)>0.8 요인쌍 %d개\n", nrow(fc_warn)))

## 국면별 Sigma 이질성 (구조 비교 · B 는 현재로 고정)
pidx <- which(FRET$panic==1L); nidx <- which(FRET$panic==0L)
Xp <- Xfull[pidx,,drop=FALSE]; Xn <- Xfull[nidx,,drop=FALSE]
lp <- which(apply(Xp,2,sd)>1e-14); ln <- which(apply(Xn,2,sd)>1e-14)
Om_p <- matrix(0,length(FCOLS),length(FCOLS),dimnames=list(FCOLS,FCOLS)); Om_n <- Om_p
Om_p[lp,lp] <- eig_floor(cov(Xp[,lp,drop=FALSE]), 1/400)
Om_n[ln,ln] <- eig_floor(cov(Xn[,ln,drop=FALSE]), 1/400)
ERES_p <- ERES[ym %in% PANIC_YM]; ERES_n <- ERES[!ym %in% PANIC_YM]
sv_p <- median(ERES_p[, .(v=mean(e^2)), by=.(Ticker,ym)]$v, na.rm=TRUE)
sv_n <- median(ERES_n[, .(v=mean(e^2)), by=.(Ticker,ym)]$v, na.rm=TRUE)
kappa <- sv_p/sv_n
Dp <- Dvec*kappa; Dn <- Dvec
Sig_p <- sig_of(Bmat, Om_p, Dp); Sig_n <- sig_of(Bmat, Om_n, Dn)
share_of <- function(Om, dv, Sg){ fc <- outer(Bw,Bw)*Om*MON; t_ <- as.numeric(t(w)%*%Sg%*%w)
  c(Market=sum(fc[which(grp=="Market"),])/t_, Sector=sum(fc[which(grp=="Sector"),])/t_,
    Style=sum(fc[which(grp=="Style"),])/t_, Specific=sum(w^2*dv)*MON/t_) }
sh_p <- share_of(Om_p,Dp,Sig_p); sh_n <- share_of(Om_n,Dn,Sig_n)
cor_of <- function(Z){ s<-sqrt(diag(Z)); C<-Z/outer(s,s); mean(C[upper.tri(C)]) }
reg <- list(
  n_panic_months=length(PANIC_YM), n_panic_days=length(pidx), n_normal_days=length(nidx),
  vol_ann_panic=sqrt(as.numeric(t(w)%*%Sig_p%*%w)*12), vol_ann_normal=sqrt(as.numeric(t(w)%*%Sig_n%*%w)*12),
  vol_ratio=sqrt(as.numeric(t(w)%*%Sig_p%*%w)/as.numeric(t(w)%*%Sig_n%*%w)),
  mean_pairwise_corr_panic=cor_of(Sig_p), mean_pairwise_corr_normal=cor_of(Sig_n),
  share_panic=as.list(sh_p), share_normal=as.list(sh_n),
  cond_panic=cond_of(Sig_p)$cond, cond_normal=cond_of(Sig_n)$cond,
  specific_var_kappa=kappa,
  market_factor_vol_ann_panic=sqrt(Om_p["Market","Market"]*252),
  market_factor_vol_ann_normal=sqrt(Om_n["Market","Market"]*252))
cat(sprintf("[R4] 국면 Sigma: vol panic %.1f%% vs normal %.1f%% (x%.2f) | corr %.3f vs %.3f | mktshare %.1f%% vs %.1f%% | spec %.1f%% vs %.1f%% | kappa %.2f\n",
  100*reg$vol_ann_panic,100*reg$vol_ann_normal,reg$vol_ratio,
  reg$mean_pairwise_corr_panic,reg$mean_pairwise_corr_normal,
  100*sh_p["Market"],100*sh_n["Market"],100*sh_p["Specific"],100*sh_n["Specific"],kappa))

## 실현 국면 상관 (보유종목 일간 상관, 홀딩월 단위)
DD <- S$DD; HOLDH <- S$HOLDH
mon_corr <- function(hm){ tk<-HOLDH[hold_ym==hm]$Ticker
  X<-dcast(DD[ym==hm & Ticker %chin% tk], Date~Ticker, value.var="Ret")
  X<-as.matrix(X[,-1]); if(is.null(ncol(X))||ncol(X)<5||nrow(X)<8) return(NULL)
  C<-suppressWarnings(cor(X, use="pairwise.complete.obs")); C[!is.finite(C)]<-NA
  data.table(ym=hm, n=ncol(X), mean_corr=mean(C[upper.tri(C)],na.rm=TRUE),
             vol_ann=sd(rowMeans(X,na.rm=TRUE),na.rm=TRUE)*sqrt(252)) }
RC <- rbindlist(lapply(intersect(yms, HOLDH$hold_ym), mon_corr))
RC[, panic := as.integer(ym %in% PANIC_YM)]
realized <- RC[, .(n_months=.N, mean_corr=mean(mean_corr,na.rm=TRUE), vol_ann=mean(vol_ann,na.rm=TRUE)), by=panic]
print(realized)

## PIT walk-forward: 국면 Sigma 배율의 사전 인지가능성
wf <- list()
for (hm in sort(PANIC_YM)) {
  prior <- FRET[ym < hm]; pp <- prior[panic==1L]; pn <- prior[panic==0L]
  if (nrow(pp) < 120L || nrow(pn) < 250L) next
  Xpp <- as.matrix(pp[, ..FCOLS]); Xnn <- as.matrix(tail(pn, 504L)[, ..FCOLS])
  lpp <- which(apply(Xpp,2,sd)>1e-14); lnn <- which(apply(Xnn,2,sd)>1e-14)
  Op <- matrix(0,length(FCOLS),length(FCOLS),dimnames=list(FCOLS,FCOLS)); On <- Op
  Op[lpp,lpp] <- eig_floor(cov(Xpp[,lpp,drop=FALSE]),1/400)
  On[lnn,lnn] <- eig_floor(cov(Xnn[,lnn,drop=FALSE]),1/400)
  Eh <- EXP[hold_ym==hm & Ticker %chin% HOLDH[hold_ym==hm]$Ticker]
  if(nrow(Eh)<20L) next
  Bi <- matrix(0,nrow(Eh),length(FCOLS),dimnames=list(Eh$Ticker,FCOLS)); Bi[,"Market"]<-Eh$beta
  for(s in secs){cn<-paste0("SEC_",s); if(cn %in% FCOLS) Bi[,cn]<-as.integer(Eh$Sector==s)}
  for(st in STYLES) Bi[,st]<-Eh[[st]]
  wi <- rep(1/nrow(Eh), nrow(Eh))
  pred_ratio <- sqrt(as.numeric(t(wi)%*%(Bi%*%Op%*%t(Bi))%*%wi) / as.numeric(t(wi)%*%(Bi%*%On%*%t(Bi))%*%wi))
  realv <- RC[ym==hm]$vol_ann
  base <- mean(RC[ym < hm & panic==0L]$vol_ann, na.rm=TRUE)
  wf[[length(wf)+1L]] <- data.table(ym=hm, pred_ratio=pred_ratio,
                                    realized_ratio = if(length(realv)) realv/base else NA_real_)
}
WF <- rbindlist(wf)
cat("[R4] 국면배율 사전예측 vs 실현:\n"); print(WF)
if(nrow(WF)>2) cat(sprintf("[R4] 상관 %.3f · 예측중앙 %.2f 실현중앙 %.2f\n",
   suppressWarnings(cor(WF$pred_ratio,WF$realized_ratio,use="complete.obs")),
   median(WF$pred_ratio,na.rm=TRUE), median(WF$realized_ratio,na.rm=TRUE)))

saveRDS(list(Sig=Sig, Sig_raw=Sig_raw, Om_f=Om_f, Om_p=Om_p, Om_n=Om_n, Sig_p=Sig_p, Sig_n=Sig_n,
  Dvec=Dvec, Dp=Dp, grp=grp, grp_share=grp_share, fac_share=fac_share, spec_share=spec_share,
  c_before=c_before, c_after=c_after, cs_b=cs_b, cs_a=cs_a, fc_warn=fc_warn, reg=reg,
  RC=RC, realized=realized, WF=WF, SEL=SEL, top_fac=top_fac, Bw=Bw),
  file.path(OUT,"risk_calc_stage2.rds"))
cat("[R4] done\n")
