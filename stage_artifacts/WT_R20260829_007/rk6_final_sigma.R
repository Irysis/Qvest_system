# RK6 — 최종 Σ 확정 + 위험 분해 + dual-basis/cap-tier + 집중도
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR=ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_007")
o3 <- readRDS(file.path(OUT,"rk3_objects.rds")); o4 <- readRDS(file.path(OUT,"rk4_objects.rds"))
B <- o4$B; Om_lw <- o4$Om_lw; Om_s <- o4$Om_s; dv <- o4$dv; Ba <- o4$Ba; asof <- o4$asof; STY <- o3$STY
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
ap <- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_007/alpha_package.json"))
av <- unlist(ap$alpha_vector)
condf <- function(M){e<-eigen((M+t(M))/2,symmetric=TRUE,only.values=TRUE)$values; c(mn=min(e),mx=max(e),cond=max(e)/max(min(e),1e-16))}

## 특이위험 바닥(BARRA specific-risk floor) — p10
fl <- as.numeric(quantile(dv$v_shrunk, 0.10, na.rm=TRUE))
Dv <- pmax(dv$v_shrunk, fl); names(Dv) <- dv$Ticker
Dv <- Dv[rownames(B)]
mk <- function(Om,Dvv){S <- B%*%Om%*%t(B); diag(S)<-diag(S)+Dvv; (S+t(S))/2}
Sig_before <- mk(Om_s, o4$Dvec_raw)
Sig <- mk(Om_lw, Dv)
cb <- condf(Sig_before); ca <- condf(Sig)
cat(sprintf("[RK6] cond before %.1f (min_eig %.3e) → after %.1f (min_eig %.3e) · 특이위험 floor %.1f%%ann\n",
  cb["cond"],cb["mn"],ca["cond"],ca["mn"],100*sqrt(fl*12)))
stopifnot(ca["mn"]>0)

## 참조 book (진단용 — 비중결정 아님): 전략 자체 규칙 = alpha_hat 상위 25 EW
top <- names(sort(av, decreasing=TRUE))[1:25]
w <- setNames(rep(1/25,25), top)
wf <- setNames(rep(0,nrow(B)), rownames(B)); wf[top] <- 1/25
sig2 <- as.numeric(t(wf)%*%Sig%*%wf); sig_ann <- sqrt(sig2*12)
Bw <- as.numeric(t(B)%*%wf); names(Bw) <- colnames(B)
fac_var <- as.numeric(t(Bw)%*%Om_lw%*%Bw); spec_var <- sum(wf^2*Dv)
contrib <- Bw * as.numeric(Om_lw%*%Bw)     # 요인별 분산기여(공분산 포함)
cat(sprintf("[RK6] book σ %.2f%%/yr · 요인 %.1f%% · 특이 %.1f%%\n",100*sig_ann,100*fac_var/sig2,100*spec_var/sig2))
grp <- c(MKT="MKT", setNames(rep("SECTOR",length(o4$secs_a)), o4$secs_a), setNames(STY,STY))
cs <- tapply(contrib, grp[names(contrib)], sum)/sig2
print(round(100*sort(cs,decreasing=TRUE),2))
sty_share <- round(100*contrib[STY]/sig2,2); print(sty_share)

## dual basis: EW-universe / cap-weighted universe
w_ew <- setNames(rep(1/nrow(B),nrow(B)), rownames(B))
capv <- Ba$Size[match(rownames(B),Ba$Ticker)]; w_cap <- capv/sum(capv); names(w_cap) <- rownames(B)
te <- function(wa){ d <- wf-wa; sqrt(as.numeric(t(d)%*%Sig%*%d)*12) }
tot <- function(wa) sqrt(as.numeric(t(wa)%*%Sig%*%wa)*12)
cat(sprintf("[RK6] TE vs EW-uni %.2f%% · TE vs cap-w %.2f%% · σ(EW-uni) %.2f%% · σ(cap-w) %.2f%%\n",
  100*te(w_ew),100*te(w_cap),100*tot(w_ew),100*tot(w_cap)))

## cap-tier (as_of 유니버스 Size 3분위)
Ba[, tier := cut(frank(Size)/.N, c(0,1/3,2/3,1), labels=c("SMALL","MID","MEGA"))]
tm <- Ba[,.(Ticker,tier,Size,sec)]
tt <- data.table(Ticker=rownames(B), w=wf, alpha=av[rownames(B)])
tt <- merge(tt, tm, by="Ticker")
# tier 별 active(vs cap-w) 위험 기여
d_cap <- wf-w_cap; mc <- as.numeric(Sig%*%d_cap); names(mc) <- rownames(B)
tt[, rc := d_cap[Ticker]*mc[Ticker]]
tt[, aw := w]
cap_tier <- tt[,.(n_held=sum(w>0), w_share=sum(w), active_risk_share=sum(rc)/sum(tt$rc),
                  alpha_share=sum(alpha*w)/sum(tt$alpha*tt$w)), by=tier][order(-w_share)]
print(cap_tier)

## 집중도
hhi_name <- sum(w^2); neff <- 1/hhi_name
sec_w <- tt[w>0, .(sw=sum(w)), by=sec][order(-sw)]
hhi_sec <- sum(sec_w$sw^2); neff_sec <- 1/hhi_sec
cat(sprintf("[RK6] n_effective %.1f · sector HHI %.4f (n_eff %.1f) · 최대섹터 %s %.0f%%\n",
  neff,hhi_sec,neff_sec,sec_w$sec[1],100*sec_w$sw[1]))
print(sec_w)

## 저장
Sdt <- as.data.table(Sig); Sdt[, Ticker := rownames(Sig)]; setcolorder(Sdt,"Ticker")
write_parquet(Sdt, file.path(OUT,"covariance.parquet"))
Bdt <- as.data.table(B); Bdt[, Ticker := rownames(B)]; setcolorder(Bdt,"Ticker")
write_parquet(Bdt, file.path(OUT,"exposure_matrix.parquet"))
Odt <- as.data.table(Om_lw); Odt[, factor := colnames(Om_lw)]; setcolorder(Odt,"factor")
write_parquet(Odt, file.path(OUT,"factor_covariance.parquet"))
write_parquet(data.table(Ticker=rownames(B), specific_var_monthly=as.numeric(Dv),
                         specific_vol_annual=sqrt(as.numeric(Dv)*12)), file.path(OUT,"specific_risk.parquet"))
saveRDS(list(Sig=Sig,Dv=Dv,fl=fl,w=w,wf=wf,top=top,sig2=sig2,sig_ann=sig_ann,Bw=Bw,
  fac_var=fac_var,spec_var=spec_var,contrib=contrib,cs=cs,sty_share=sty_share,cb=cb,ca=ca,
  te_ew=te(w_ew),te_cap=te(w_cap),tot_ew=tot(w_ew),tot_cap=tot(w_cap),cap_tier=cap_tier,
  hhi_name=hhi_name,neff=neff,hhi_sec=hhi_sec,neff_sec=neff_sec,sec_w=sec_w,tt=tt,w_cap=w_cap,w_ew=w_ew),
  file.path(OUT,"rk6_objects.rds"))
cat("[RK6] done\n")
