## RISK Stage 6 — 조건수 진단 · 군집(crowding) 재측정 · 산출물 emission
suppressPackageStartupMessages({library(data.table);library(arrow);library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE)
QM<-"C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
S <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/wt006"
O <-"C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/0c0807c3-c2cd-4903-8044-987993f6f62f/scratchpad/risk006"
AR<-"stage_artifacts/WT_R20260829_006"
R1<-readRDS(file.path(O,"r1_reg.rds")); R2<-readRDS(file.path(O,"r2_omega.rds"))
R3<-readRDS(file.path(O,"r3_sigma.rds")); R4<-readRDS(file.path(O,"r4_diag.rds")); R5<-readRDS(file.path(O,"r5_tail.rds"))
R2b<-readRDS(file.path(O,"r2b_paired.rds"))
mk<-readRDS(file.path(S,"p1s_market.rds"))
U<-R3$U; B<-R3$B; OM<-R3$OM; SIGMA<-R3$SIGMA; Dvec<-R3$Dvec; FACN<-R3$FACN
cn <- function(M){e<-eigen(M,symmetric=TRUE,only.values=TRUE)$values; max(e)/max(min(e),1e-16)}

## ── 1. 조건수 분해 + D 민감도 ───────────────────────────────────────────────
cond_om <- cn(OM); cond_D <- max(Dvec)/min(Dvec); cond_S <- R3$cond_sigma
cat(sprintf("[cond] Omega %.1f | D(diag ratio) %.1f | SIGMA %.1f | min_eig %.3e\n",
            cond_om, cond_D, cond_S, R3$min_eig))
ER<-R1$ER; setorder(ER,Ticker,Date); lam<-0.5^(1/24); ER[, r2:=resid^2]
Dl <- ER[, { n<-.N; w<-lam^((n:1)-1); .(dvar=sum(w*r2)/sum(w), nobs=n) }, by=Ticker]
med<-median(Dl[nobs>=12]$dvar); Dl[nobs<12, dvar:=0.5*dvar+0.5*med]
sens <- list()
for (q in list(c(0.02,0.98), c(0.05,0.95), c(0.10,0.90))) {
  qq<-quantile(Dl[nobs>=12]$dvar, q); dv<-pmin(pmax(Dl$dvar,qq[1]),qq[2])
  dvv<-setNames(dv, Dl$Ticker)
  d2 <- ifelse(U$Ticker %in% names(dvv), dvv[U$Ticker], med); names(d2)<-U$Ticker
  Sx <- B%*%OM%*%t(B)+diag(d2); Sx<-(Sx+t(Sx))/2
  sens[[paste0("winsor_",q[1]*100,"_",q[2]*100)]] <-
     list(cond_sigma=round(cn(Sx),1), cond_D=round(max(d2)/min(d2),1),
          mean_specific_vol_ann=round(mean(sqrt(d2*12))*100,2))
  cat(sprintf("  [D winsor %.0f/%.0f] cond(SIGMA) %.1f  cond(D) %.1f  mean idio vol %.2f pct\n",
      q[1]*100,q[2]*100, cn(Sx), max(d2)/min(d2), mean(sqrt(d2*12))*100))
}
## 팩터 상관 경보 (RF-R5)
CO <- cov2cor(OM); hi <- which(abs(CO)>0.8 & upper.tri(CO), arr.ind=TRUE)
pairs_hi <- if (nrow(hi)) paste0(FACN[hi[,1]],"~",FACN[hi[,2]],"(",round(CO[hi],3),")") else character(0)
cat("[RF-R5] |rho|>0.8 factor pairs:", length(pairs_hi),
    if(length(pairs_hi)) paste(pairs_hi,collapse=", ") else "", "\n")
topcor <- sort(abs(CO[upper.tri(CO)]),decreasing=TRUE)[1:5]
cat("[Omega] top-5 |rho|:", paste(round(topcor,3),collapse=" "),"\n")

## ── 2. crowding 재측정 (라이브 유니버스 기준) ───────────────────────────────
source("02_Infrastructure/factor_db/crowding_score_per_factor.R")
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date:=as.Date(Date)]
FAMS<-R1$FAMS; SIG<-as.Date("2026-08-28")
FZp <- as.data.table(read_parquet(file.path(S,"p1s_family_z_panel.parquet")))
d3  <- max(FZp$Date[FZp$Date <= as.Date("2026-05-31")])
live_now <- U$Ticker
live_3m  <- mk$UNIV_DT[Date==d3]$Ticker
liq3 <- mk$LIQ_DT[Date==d3 & adv>=2e8]$Ticker
live_3m <- intersect(live_3m, liq3)
cat("[crowding] live universe now",length(live_now)," 3m ago(",as.character(d3),")",length(live_3m),"\n")
mkcrowd <- function(tickers, exposures_dt, dref) {
  rw <- RAW[Ticker %in% tickers & Date<=dref]
  bm <- RAW[Date==dref & (K200==1|KQ150==1)]$Ticker
  as.data.table(crowding_score_per_factor(exposures_dt, as.character(dref), rw,
                 benchmark_tickers=bm, top_n=25L)) }
FE_now <- melt(U[, c("Ticker", paste0("x_f_",FAMS)), with=FALSE], id.vars="Ticker",
               variable.name="factor_name", value.name="exposure")
FE_now[, factor_name := sub("^x_f_","",as.character(factor_name))]
zsc<-function(x){x<-as.numeric(x);s<-sd(x,na.rm=TRUE);if(!is.finite(s)||s<=0) return(rep(0,length(x)))
  y<-(x-mean(x,na.rm=TRUE))/s;y[!is.finite(y)]<-0;pmax(pmin(y,3),-3)}
FE_3m <- FZp[Date==d3 & Ticker %in% live_3m, .(Ticker, factor_name=family, exposure=z_fam)]
FE_3m[, exposure := zsc(exposure), by=factor_name]
CR_now <- mkcrowd(live_now, FE_now, SIG)
CR_3m  <- mkcrowd(live_3m,  FE_3m,  d3)
CMP <- merge(CR_now[,.(factor_name, crowding_score, hhi_top, vol_concentration,
                       passive_overlap_proxy, demand_elasticity_proxy, n_universe)],
             CR_3m[,.(factor_name, cs_3m=crowding_score)], by="factor_name")
CMP[, delta_3m := round(crowding_score-cs_3m,4)]
setorder(CMP, -crowding_score)
print(CMP)
max_reach <- 0.30*1 + 0.25*max(CR_now$vol_concentration) + 0.25*max(CR_now$passive_overlap_proxy) +
             0.20*max(CR_now$demand_elasticity_proxy)
cat(sprintf("[crowding] 본 유니버스에서 composite 이 도달 가능한 상한 = %.4f (게이트 0.75)\n", max_reach))

## ── 3. 산출물 ───────────────────────────────────────────────────────────────
EXP <- data.table(Ticker=rownames(B)); EXP <- cbind(EXP, as.data.table(B))
write_parquet(EXP, file.path(AR,"exposure_matrix.parquet"))
FCOV <- data.table(factor=FACN); FCOV <- cbind(FCOV, as.data.table(OM)); setnames(FCOV, c("factor",FACN))
write_parquet(FCOV, file.path(AR,"factor_covariance.parquet"))
SPR <- merge(data.table(Ticker=names(Dvec), specific_var=as.numeric(Dvec)),
             Dl[,.(Ticker,nobs)], by="Ticker", all.x=TRUE)
SPR[, `:=`(specific_vol_ann=sqrt(specific_var*12), history_fallback=is.na(nobs)|nobs<12)]
SPR <- merge(SPR, U[,.(Ticker, beta_fallback)], by="Ticker", all.x=TRUE)
write_parquet(SPR, file.path(AR,"specific_risk.parquet"))
COVD <- data.table(Ticker=rownames(SIGMA)); COVD <- cbind(COVD, as.data.table(SIGMA))
setnames(COVD, c("Ticker", rownames(SIGMA)))
write_parquet(COVD, file.path(AR,"covariance.parquet"))
## 구간 이질성
HET <- copy(R3$cmp); HET[, `:=`(period_pre="2005-12~2014-12", period_post="2015-01~2026-07")]
write_parquet(HET, file.path(AR,"sigma_period_heterogeneity.parquet"))
## regime correlation
REG <- copy(R4$REG); REGF <- copy(R4$REGF)
RC <- merge(REG, REGF, by="regime", all=TRUE)
RC[, fam_n_eff_nyholt := round(12/(1+11*fam_mean_abs_rho),3)]
RC2 <- rbindlist(list(
  RC[, .(scope="regime", label=regime, n=n_months, cross_sec_r2=mean_cross_sec_r2,
         specific_vol_ann, market_factor_vol_ann=market_fac_vol_ann,
         factor_mean_abs_rho=mean_abs_factor_rho, factor_participation_ratio=factor_pr,
         family_mean_abs_rho=fam_mean_abs_rho, family_participation_ratio=fam_pr,
         family_n_eff_nyholt=fam_n_eff_nyholt)],
  data.table(scope="period", label=c("pre2015","post2015"), n=c(109L,139L),
    cross_sec_r2=c(0.2622,0.2110), specific_vol_ann=c(32.24,35.86),
    market_factor_vol_ann=c(22.33,21.80),
    factor_mean_abs_rho=c(0.1315,0.1258), factor_participation_ratio=c(12.66,13.68),
    family_mean_abs_rho=c(0.2767,0.2816), family_participation_ratio=c(5.28,4.65),
    family_n_eff_nyholt=round(12/(1+11*c(0.2767,0.2816)),3))), use.names=TRUE)
write_parquet(RC2, file.path(AR,"regime_correlation.parquet"))
print(RC2)
## tail_risk.json
TL <- list(
  basis="strategy net monthly returns (period_returns_production.csv, 15bps delta 차감 후)",
  n_months=248L,
  moments=list(mean=round(mean(fread(file.path(AR,"period_returns_production.csv"))$ret_net),6)),
  full_sample=R5$TAIL$full, pre_2025=R5$TAIL$pre2025,
  active_leg=list(var_5=round(R5$ea5$var,4), es_5=round(R5$ea5$es,4),
                  var_1=round(R5$ea1$var,4), es_1=round(R5$ea1$es,4),
                  hill_alpha=round(R5$act_hill,3)),
  drawdown=list(monthly_mdd=round(R5$mdd,4), cdar_95=round(R5$cdar95,4)),
  sigma_implied=list(book_monthly_sd=round(R5$sig_m,5),
    normal_var_5=round(-qnorm(0.05)*R5$sig_m,4), normal_var_1=round(-qnorm(0.01)*R5$sig_m,4),
    t5_var_5=round(-qt(0.05,5)*sqrt(3/5)*R5$sig_m,4), t5_var_1=round(-qt(0.01,5)*sqrt(3/5)*R5$sig_m,4)),
  calibration_note=paste0("정규-Sigma 는 5% 지점에서 보수적(11.97 vs 실측 10.92)이나 1% 지점에서 ",
    "17% 과소(16.92 vs 실측 20.46). 꼬리 소비는 t(5) 또는 GPD 값을 쓸 것."),
  evt_caveat="월간 n=248, 90% 임계 초과 25개 — GPD/Hill 은 소표본 추정치. 일별 패널 부재로 정밀화 불가.",
  data_integrity_caveat="상류 WT006-17: 2025-01~ BM/수익 변동성 이상(sd 0.0759 -> 0.1162). pre_2025 절단본 병기.")
write_json(TL, file.path(AR,"tail_risk.json"), pretty=TRUE, auto_unbox=TRUE, digits=8)
saveRDS(list(sens=sens, CMP=CMP, pairs_hi=pairs_hi, cond_om=cond_om, cond_D=cond_D,
             max_reach=max_reach, RC2=RC2, topcor=topcor), file.path(O,"r6_emit.rds"))
cat("[done] artifacts written to", AR, "\n")
