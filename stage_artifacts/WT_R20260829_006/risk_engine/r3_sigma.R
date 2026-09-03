## RISK Stage 3 — as_of exposure B / specific risk D / Sigma = B*Om*Bt + D / period heterogeneity
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
S <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
source("02_Infrastructure/portfolio/hrp_core.R")

R1<-readRDS(file.path(O,"r1_reg.rds")); R2<-readRDS(file.path(O,"r2_omega.rds"))
Fm<-R2$Fm; FAMS<-R1$FAMS; SEC_LV<-R1$SEC_LV; SECMAP<-R1$SECMAP; XCOLS<-R1$XCOLS
mk<-readRDS(file.path(S,"p1s_market.rds"))
SIG <- as.Date("2026-08-28")

PIT_EXCLUDE <- c("C01_SUE","C02_EPS_Chg_1m","C03_EPS_Chg_3m","C04_ESBR","C05_ESCR","C06_TP_Gap",
 "C08_Coverage","C11_Earnings_Streak","C12_Estimate_Dispersion_Proxy","C16_EPS_Acceleration",
 "C18_Earnings_CAR_3d","C19_Composite_Earnings","SE02_Consensus_Revision","V04_fPER","V05_fPBR",
 "V06_fDY","V09_PEG","D32_Beta_VIX","MA01_GDP_Sensitivity","MA03_Rate_Sensitivity",
 "MA04_YieldCurve_Sensitivity","C07_TP_Mom","MA02_CPI_Sensitivity")
FAMMAP <- fread(file.path(S,"p1s_family_map.csv"))

z <- as.data.table(load_month_factors(SIG, dedup=TRUE))
z <- z[!Factor_Name %in% PIT_EXCLUDE]
z <- merge(z[, .(Ticker, Factor_Name, Z_Score_Aligned)], FAMMAP, by="Factor_Name")
z <- z[is.finite(Z_Score_Aligned)]
FZ_asof <- dcast(z[, .(z_fam=mean(Z_Score_Aligned)), by=.(Ticker,family)],
                 Ticker ~ family, value.var="z_fam")
cat("[asof famz] tickers",nrow(FZ_asof)," families",ncol(FZ_asof)-1,":",
    paste(setdiff(names(FZ_asof),"Ticker"),collapse=","),"\n")
setnames(FZ_asof, setdiff(names(FZ_asof),"Ticker"), paste0("f_",setdiff(names(FZ_asof),"Ticker")))

RB <- merge(mk$RET_DT, mk$BENCH_DT, by="Date")
w60 <- tail(sort(unique(RB$Date)),60L)
bb <- RB[Date %in% w60, .(nobs=.N, cvb=if(.N>=12L) stats::cov(Ret_1m,BM_Ret) else NA_real_,
                          vb =if(.N>=12L) stats::var(BM_Ret) else NA_real_), by=Ticker]
bb[, beta := 0.67*(cvb/vb)+0.33]
bb[, beta_fallback := !is.finite(beta) | nobs < 24L]
bb[!is.finite(beta), beta := 1.0]          ## Blume prior — 신규상장 등 이력부족분
BET <- bb[, .(Ticker, beta, beta_nobs=nobs, beta_fallback)]
cat("[asof beta] n",nrow(BET)," fallback(<24m or NA):",sum(BET$beta_fallback),
    " window",as.character(min(w60)),"~",as.character(max(w60)),"\n")

## as_of 유동성 adv20 (C10: t-1 규약 — 당일 미포함). LIQ_DT 는 forward 수익 필요분까지만
## 생성되어 2026-07-31 이 마지막이므로 as_of(2026-08-28) 는 원장에서 직접 재계산한다.
source("02_Infrastructure/ramp/factor_validation.R")
RAWv <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Vol","Close")))
RAWv[, Date := as.Date(Date)]
ADV <- as.data.table(build_adv20_t1(RAWv[, .(Date,Ticker,Vol,Close)], at_dates=SIG))
setnames(ADV, names(ADV), sub("^adv20$","adv",names(ADV)))
cat("[asof adv20] rows",nrow(ADV)," non-NA",sum(is.finite(ADV$adv)),
    " median",format(median(ADV$adv,na.rm=TRUE),digits=4),"\n")
rm(RAWv); invisible(gc())

sec <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Sector")))
sec[, Date:=as.Date(Date)]; sec <- sec[Date==SIG, .(Ticker, Sector)]
sec[, sec9 := SECMAP[Sector]]; sec[is.na(sec9), sec9:="OTHER"]

AS0 <- merge(mk$UNIV_DT[Date==SIG,.(Ticker)], ADV[, .(Ticker, adv)], by="Ticker", all.x=TRUE)
cat("[asof univ] K200|KQ150 n =",nrow(AS0)," adv 결측",sum(!is.finite(AS0$adv)),
    " liq FAIL(<2e8)",sum(is.finite(AS0$adv) & AS0$adv<2e8),"\n")
AS <- AS0[is.finite(adv) & adv>=2e8]
AS <- merge(AS, mk$SIZE_DT[Date==SIG,.(Ticker,Size)], by="Ticker")
AS <- merge(AS, BET, by="Ticker"); AS <- merge(AS, sec, by="Ticker", all.x=TRUE)
AS <- merge(AS, FZ_asof, by="Ticker", all.x=TRUE)
AS[is.na(sec9), sec9:="OTHER"]
fcols <- paste0("f_",FAMS)
for (cc in fcols) { if(!cc %in% names(AS)) set(AS,j=cc,value=0); v<-AS[[cc]]; v[!is.finite(v)]<-0; set(AS,j=cc,value=v) }
zsc <- function(x){ x<-as.numeric(x); mu<-mean(x,na.rm=TRUE); s<-stats::sd(x,na.rm=TRUE)
  if(!is.finite(s)||s<=0) return(rep(0,length(x))); y<-(x-mu)/s; y[!is.finite(y)]<-0; pmax(pmin(y,3),-3) }
AS[, `:=`(x_beta=zsc(beta), x_size=zsc(log(Size)), x_liq=zsc(log(pmax(adv,1))))]
for (cc in fcols) set(AS, j=paste0("x_",cc), value=zsc(AS[[cc]]))
for (s9 in SEC_LV) set(AS, j=paste0("s_",s9), value=as.numeric(AS$sec9==s9))
cat("[asof universe] eligible n =",nrow(AS),"\n")

apk <- fromJSON("qepm/mailbox/worktask/WT-R20260829_006/alpha_package.json", simplifyVector=TRUE)
av  <- data.table(Ticker=names(apk$alpha_vector), alpha=as.numeric(unlist(apk$alpha_vector)))
cat("[alpha] n",nrow(av)," overlap with eligible:",length(intersect(av$Ticker, AS$Ticker)),"\n")
drop_ids <- setdiff(av$Ticker, AS$Ticker)
if (length(drop_ids)) {
  dd0 <- AS0[Ticker %in% drop_ids]
  cat("[alpha] as_of 결격",length(drop_ids),"종 | 유니버스 이탈",
      length(setdiff(drop_ids, AS0$Ticker))," | liq<2e8",sum(is.finite(dd0$adv)&dd0$adv<2e8),
      " | adv 결측",sum(!is.finite(dd0$adv)),"\n")
}
U <- AS[Ticker %in% av$Ticker]; setorder(U, Ticker)
cat("[U] Sigma universe n =",nrow(U)," beta_fallback:",sum(U$beta_fallback),"\n")

FACN <- colnames(Fm)
B <- cbind(Intercept=1, as.matrix(U[, ..XCOLS]))
B <- B[, FACN, drop=FALSE]; rownames(B) <- U$Ticker

OM    <- suppressWarnings(.get_cor_cov(Fm, "lw_nls"))$cov; OM <- (OM+t(OM))/2
OM_lw <- suppressWarnings(.get_cor_cov(Fm, "ledoit_wolf"))$cov
OM_s  <- suppressWarnings(.get_cor_cov(Fm, "sample"))$cov
cn <- function(M){e<-eigen(M,symmetric=TRUE,only.values=TRUE)$values; max(e)/max(min(e),1e-16)}

ER <- R1$ER; setorder(ER, Ticker, Date); lam <- 0.5^(1/24); ER[, r2 := resid^2]
Dl <- ER[, { n<-.N; w<-lam^((n:1)-1); .(dvar=sum(w*r2)/sum(w), nobs=n) }, by=Ticker]
med <- median(Dl[nobs>=12]$dvar)
Dl[nobs<12, dvar := 0.5*dvar + 0.5*med]
## D winsorization: 2/98 -> cond(SIGMA) 483.5 / 5/95 -> 399.9 / 10/90 -> 313.4 (r6 민감도 실측).
## 5/95 채택 — 조건수 17% 개선 대비 평균 특이변동성 왜곡 1.1%(38.98->38.54pct). 사다리 전체를 원장에 남긴다.
qq <- quantile(Dl[nobs>=12]$dvar, c(0.05,0.95))
Dl[, dvar := pmin(pmax(dvar, qq[1]), qq[2])]
Dv <- setNames(Dl$dvar, Dl$Ticker)
miss <- setdiff(U$Ticker, names(Dv))
Dvec <- ifelse(U$Ticker %in% names(Dv), Dv[U$Ticker], med); names(Dvec) <- U$Ticker
cat("[D] no-history names:",length(miss),"-> cross-sectional median. med ann vol",
    round(sqrt(med*12)*100,2),"pct\n")

SIGMA <- B %*% OM %*% t(B) + diag(Dvec); SIGMA <- (SIGMA+t(SIGMA))/2
ev <- eigen(SIGMA, symmetric=TRUE, only.values=TRUE)$values
cat(sprintf("[SIGMA] n=%d cond=%.1f min_eig=%.3e PD=%s\n", nrow(SIGMA), max(ev)/min(ev), min(ev), min(ev)>0))
cat("[SIGMA] mean ann vol =", round(mean(sqrt(diag(SIGMA)*12))*100,2),"pct  mean corr =",
    round(mean(cov2cor(SIGMA)[upper.tri(SIGMA)]),4),"\n")
BF <- B %*% OM %*% t(B)
fac_share <- sum(diag(BF))/sum(diag(SIGMA))
cat("[SIGMA] factor variance share (trace) =", round(fac_share,4)," specific =", round(1-fac_share,4),"\n")

S_lw <- B %*% OM_lw %*% t(B) + diag(Dvec); S_sa <- B %*% OM_s %*% t(B) + diag(Dvec)
cat("[SIGMA alt] cond ledoit_wolf =", round(cn((S_lw+t(S_lw))/2),1),
    " sample =", round(cn((S_sa+t(S_sa))/2),1),"\n")

dts <- as.Date(rownames(Fm))
i1 <- which(dts < as.Date("2015-01-01")); i2 <- which(dts >= as.Date("2015-01-01"))
O1 <- suppressWarnings(.get_cor_cov(Fm[i1,,drop=FALSE],"lw_nls"))$cov
O2 <- suppressWarnings(.get_cor_cov(Fm[i2,,drop=FALSE],"lw_nls"))$cov
cat(sprintf("[period] pre2015 n=%d  post2015 n=%d\n", length(i1), length(i2)))
v1 <- sqrt(diag(O1)*12)*100; v2 <- sqrt(diag(O2)*12)*100
cmp <- data.table(factor=FACN, vol_pre=round(v1,2), vol_post=round(v2,2), ratio=round(v2/v1,3))
print(cmp[order(-ratio)])
C1 <- cov2cor(O1); C2 <- cov2cor(O2)
cat("[period] corr relFro =", round(norm(C1-C2,"F")/norm((C1+C2)/2,"F"),4),
    " mean abs rho pre =", round(mean(abs(C1[upper.tri(C1)])),4),
    " post =", round(mean(abs(C2[upper.tri(C2)])),4),"\n")
pr <- function(M){ e<-eigen(M,symmetric=TRUE,only.values=TRUE)$values; e<-pmax(e,0); (sum(e)^2)/sum(e^2) }
cat("[period] participation ratio (eff indep factors) pre =",round(pr(C1),2)," post =",round(pr(C2),2),"\n")
cat("[period] Omega cond pre/post =",round(cn(O1),1),"/",round(cn(O2),1),"\n")
CVd <- R1$CV
cat("[period] cross-sec R2 pre =",round(mean(CVd[Date<as.Date("2015-01-01")]$r2),4),
    " post =",round(mean(CVd[Date>=as.Date("2015-01-01")]$r2),4),"\n")
cat("[period] specific sd ann pre =",round(mean(CVd[Date<as.Date("2015-01-01")]$sd_res)*sqrt(12)*100,2),
    "pct post =",round(mean(CVd[Date>=as.Date("2015-01-01")]$sd_res)*sqrt(12)*100,2),"pct\n")

saveRDS(list(U=U, B=B, OM=OM, OM_lw=OM_lw, OM_s=OM_s, Dvec=Dvec, SIGMA=SIGMA, FACN=FACN,
             O1=O1, O2=O2, i1=i1, i2=i2, dts=dts, cmp=cmp, av=av, AS=AS, Dl=Dl, med_d=med,
             BF=BF, fac_share=fac_share, cond_sigma=max(ev)/min(ev), min_eig=min(ev),
             AS0=AS0, ADV=ADV, drop_ids=drop_ids),
        file.path(O,"r3_sigma.rds"))
cat("[done]\n")
