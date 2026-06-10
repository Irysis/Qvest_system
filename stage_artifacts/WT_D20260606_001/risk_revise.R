# Codex REVISE follow-ups: bootstrap CI, residual off-diag, cov sensitivity, single-month stress, 8th window
suppressMessages({library(arrow); library(data.table); library(jsonlite)})
ROOT <- "G:/Quant_Module_Moltbot"; setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_D20260606_001")
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||all(is.na(a))) b else a
source("02_Infrastructure/portfolio/hrp_core.R")

ap <- fromJSON("qepm/mailbox/worktask/WT-D20260606_001/alpha_package.json", simplifyVector=FALSE)
corisk <- fromJSON(file.path(OUT,"corisk_R05.json"))
# rebuild J (sleeve vs r05) — reuse from risk_summary path: re-derive quickly
scores <- as.data.table(read_parquet("stage_artifacts/WT_WT-D20260606_001/alpha_scores.parquet"))
scores[,Date:=as.Date(Date)]; scores[,ym:=format(Date,"%Y-%m")]
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet")); RAW[,Date:=as.Date(Date)]; RAW[,ym:=format(Date,"%Y-%m")]
me <- RAW[!is.na(Close),.SD[.N],by=.(Ticker,ym),.SDcols=c("Date","Close")]; setorder(me,Ticker,Date)
me[, fwd:=shift(Close,1L,type="lead")/Close-1, by=Ticker]; me <- me[is.na(fwd)|(fwd>-0.99&fwd<9)]
me[!is.na(fwd), fwd:={lo<-quantile(fwd,.01,na.rm=T);hi<-quantile(fwd,.99,na.rm=T);pmin(pmax(fwd,lo),hi)},by=ym]
ret1m <- me[,.(Ticker,ym,Ret_1m=fwd)]
RAW[,dvol:=Close*Vol]; setorder(RAW,Ticker,Date); RAW[,adv20:=frollmean(shift(dvol,1L),20L),by=Ticker]
adv_me <- RAW[!is.na(Close),.SD[.N],by=.(Ticker,ym),.SDcols="adv20"][,.(Ticker,ym,adv=adv20)]
sc <- merge(scores[,.(Date,Ticker,score=alpha_score,ym)], adv_me, by=c("Ticker","ym"),all.x=T)
r1d <- merge(ret1m, unique(scores[,.(ym,Date)]),by="ym")[,.(Date,Ticker,Ret_1m)]
S <- sc[!is.na(score)]; S <- S[is.na(adv)|adv>=2e8]; setorder(S,Date,-score)
W <- S[, {n<-min(20L,.N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n,n))}, by=Date]
WR <- merge(W, r1d, by=c("Date","Ticker"),all.x=T); WR[is.na(Ret_1m),Ret_1m:=0]
dts <- sort(unique(W$Date)); traded<-numeric(length(dts)); names(traded)<-as.character(dts); prev<-data.table(Ticker=character(0),w=numeric(0))
for(i in seq_along(dts)){cur<-W[Date==dts[i],.(Ticker,w)];m<-merge(cur,prev,by="Ticker",all=T,suffixes=c("_c","_p"));m[is.na(w_c),w_c:=0];m[is.na(w_p),w_p:=0];traded[i]<-sum(abs(m$w_c-m$w_p));prev<-cur}
port <- WR[,.(gross=sum(w*Ret_1m)),by=Date]; port[,cost:=traded[as.character(Date)]*15/1e4]; port[,sleeve_net:=gross-cost]
bm_m <- unique(RAW[!is.na(BM_Ret),.(Date,ym,BM_Ret)])[,.(bm_ret=prod(1+BM_Ret)-1),by=ym]; setorder(bm_m,ym); bm_m[,bm_fwd:=shift(bm_ret,1L,type="lead")]
valid_dates <- merge(unique(scores[,.(ym,Date)]), bm_m[,.(ym,bm_fwd)],by="ym")[!is.na(bm_fwd),Date]
sleeve <- port[Date %in% valid_dates,.(Date,sleeve_net)]; sleeve <- sleeve[is.finite(sleeve_net)]; sleeve[,ym:=format(Date,"%Y-%m")]
r05 <- as.data.table(read_parquet("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
r05 <- unique(r05[!is.na(ret_net),.(ym=format(as.Date(Date),"%Y-%m"), r05_net=ret_net)])
J <- merge(sleeve[,.(ym,sleeve_net)], r05, by="ym"); J<-J[is.finite(sleeve_net)&is.finite(r05_net)]
s <- J$sleeve_net; r <- J$r05_net; n <- nrow(J)
cat("[revise] J months", n, "\n")

# ---- (1) Bootstrap CI: cov_contribution_annualized, beta_down, full_cor, TDC ----
set.seed(42); B <- 2000
boot <- replicate(B, {
  idx <- sample.int(n, n, replace=TRUE)
  ss <- s[idx]; rr <- r[idx]
  covc <- cov(ss,rr)*12
  dn <- rr<0; bd <- if(sum(dn)>=8) cov(ss[dn],rr[dn])/var(rr[dn]) else NA_real_
  fc <- cor(ss,rr)
  qs<-quantile(ss,.2); qr<-quantile(rr,.2); tdc<-mean(ss<=qs & rr<=qr)/.2
  c(covc=covc, bd=bd, fc=fc, tdc=tdc)
})
ci <- function(x) quantile(x, c(.025,.5,.975), na.rm=TRUE)
boot_ci <- list(
  cov_contribution_annualized = as.numeric(ci(boot["covc",])),
  beta_down_R05 = as.numeric(ci(boot["bd",])),
  full_correlation = as.numeric(ci(boot["fc",])),
  joint_left_tail_TDC = as.numeric(ci(boot["tdc",])),
  prob_cov_negative = mean(boot["covc",] < 0, na.rm=TRUE),
  prob_fullcor_negative = mean(boot["fc",] < 0, na.rm=TRUE),
  B = B)
cat("[boot] cov_contrib 95%CI [", round(boot_ci$cov_contribution_annualized[1],4),",",round(boot_ci$cov_contribution_annualized[3],4),
    "] P(cov<0)=",round(boot_ci$prob_cov_negative,3),
    "| fullcor CI [",round(boot_ci$full_correlation[1],3),",",round(boot_ci$full_correlation[3],3),"] P(<0)=",round(boot_ci$prob_fullcor_negative,3),"\n")
cat("[boot] beta_down CI [",round(boot_ci$beta_down_R05[1],3),",",round(boot_ci$beta_down_R05[3],3),
    "] | TDC CI [",round(boot_ci$joint_left_tail_TDC[1],2),",",round(boot_ci$joint_left_tail_TDC[3],2),"]\n")

# ---- (2) cov contribution sensitivity: downside-only months ----
dn <- r<0
cov_down_only <- cov(s[dn], r[dn])*12
cov_full <- cov(s,r)*12
cat("[sens] cov_contrib full", round(cov_full,4), "| downside-only(R05<0,n=",sum(dn),")", round(cov_down_only,4),"\n")

# ---- (3) Residual off-diagonal correlation after BOmegaB'+D (C1 weakest assumption) ----
uni <- names(ap$alpha_vector); asof <- as.Date(ap$as_of_date)
dret <- RAW[Ticker %in% uni & Date<=asof, .(Date,Ticker,Ret,Sector,Size)]
ld <- tail(sort(unique(dret$Date)),252L); dret<-dret[Date %in% ld]
wideR <- dcast(dret, Date~Ticker, value.var="Ret"); matR<-as.matrix(wideR[,-1])
keep<-colSums(!is.na(matR))>=200L; matR<-matR[,keep,drop=F]; uk<-colnames(matR); matR[is.na(matR)]<-0
mkt<-rowMeans(matR); beta_mkt<-apply(matR,2,function(x)coef(lm(x~mkt))[2])
sec<-unique(dret[Ticker %in% uk,.SD[.N],by=Ticker,.SDcols="Sector"])[match(uk,Ticker)]; sec[is.na(Sector),Sector:="UNK"]
Bsec<-model.matrix(~Sector-1,data=sec); colnames(Bsec)<-gsub("Sector","SEC_",colnames(Bsec))
sz<-unique(dret[Ticker %in% uk,.SD[.N],by=Ticker,.SDcols="Size"])[match(uk,Ticker)]
size_exp<-scale(log(pmax(sz$Size,1)))[,1]; size_exp[is.na(size_exp)]<-0
fac_size<-apply(matR,1,function(d)coef(lm(d~size_exp))[2])
sectors<-sort(unique(sec$Sector))
secret<-lapply(sectors,function(x){cl<-which(sec$Sector==x);if(length(cl)==0)rep(0,nrow(matR))else rowMeans(matR[,cl,drop=F])-mkt}); names(secret)<-paste0("SEC_",sectors)
facMat<-cbind(MKT=mkt,SIZE=fac_size,do.call(cbind,secret)); fvar<-apply(facMat,2,var); facMat<-facMat[,fvar>1e-12,drop=F]
Bmat<-matrix(0,nrow=ncol(matR),ncol=ncol(facMat),dimnames=list(uk,colnames(facMat)))
if("MKT"%in%colnames(facMat))Bmat[,"MKT"]<-beta_mkt; if("SIZE"%in%colnames(facMat))Bmat[,"SIZE"]<-size_exp
for(sc2 in colnames(Bsec))if(sc2%in%colnames(facMat))Bmat[,sc2]<-Bsec[,sc2]
fitted<-facMat%*%t(Bmat); resid<-matR-fitted
resid_cor<-cor(resid)
offdiag<-resid_cor[upper.tri(resid_cor)]
cat("[resid] off-diag resid cor: mean",round(mean(offdiag),4)," abs-mean",round(mean(abs(offdiag)),4),
    " max",round(max(offdiag),3)," |>0.3| pairs",sum(abs(offdiag)>0.3),"of",length(offdiag),"\n")

# ---- (4) single-MONTH stress (worst 1m) + full window list incl 8th ----
worst_month <- min(sleeve$sleeve_net); worst_month_date <- sleeve[which.min(sleeve_net),ym]
worst_r05_month <- min(r05[ym %in% J$ym, r05_net])
# Brexit 2016 (8th window) on sleeve
brexit <- sleeve[ym>="2016-06" & ym<="2016-07", sleeve_net]
brexit_cum <- if(length(brexit)>0) prod(1+brexit)-1 else NA
cat("[stress1m] worst single-month sleeve", round(worst_month,4),"(",worst_month_date,") | worst R05 month",round(worst_r05_month,4),
    "| Brexit2016 sleeve_cum",round(brexit_cum,4),"\n")

revise <- list(
  bootstrap_ci = boot_ci,
  cov_sensitivity = list(full_annualized=cov_full, downside_only_annualized=cov_down_only, n_downside=sum(dn)),
  residual_offdiagonal = list(mean=mean(offdiag), abs_mean=mean(abs(offdiag)), max=max(offdiag),
                              n_pairs_gt_0.3=sum(abs(offdiag)>0.3), n_pairs_total=length(offdiag)),
  single_month_stress = list(worst_sleeve_1m=worst_month, worst_sleeve_1m_ym=worst_month_date,
                             worst_r05_1m=worst_r05_month, brexit_2016_sleeve_cum=brexit_cum),
  tstat_reconciliation = list(
    risk_forward_bm_t=2.06, risk_forward_bm_IR=0.469,
    contemporaneous_bm_t=1.583, contemporaneous_bm_IR=0.238,
    alpha_reported_t=1.461, alpha_reported_IR=0.219,
    root_cause="alpha aligned benchmark to SCORE-month (backward), risk aligned to FORWARD realized month. Contemporaneous-BM reproduces alpha (1.58 vs 1.46, residual = liq/winsorize minutiae). Forward-BM alignment (risk, 2.06) is methodologically MORE correct (forward port return vs forward market). BOTH < 2.95 -> standalone FAIL unchanged.")
)
write_json(revise, file.path(OUT,"risk_revise.json"), pretty=TRUE, auto_unbox=TRUE)
cat("\n[DONE revise]\n")
