# R6 — walk-forward 베타/시장share 보강 + crowding 3m delta + 산출물 emit(parquet/json) + lineage
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
source(file.path(ROOT,"02_Infrastructure/factor_db/crowding_score_per_factor.R"))
S1 <- readRDS(file.path(OUT,"risk_calc_stage1.rds")); S2 <- readRDS(file.path(OUT,"risk_calc_stage2.rds"))
S3 <- readRDS(file.path(OUT,"risk_calc_stage3.rds")); RI <- readRDS(file.path(OUT,"risk_inputs.rds"))
SIG_DATE <- as.Date("2026-08-28"); MON <- 21L
EXP<-S1$EXP; HOLDH<-S1$HOLDH; FCOLS<-S1$FCOLS; secs<-S1$secs; STYLES<-S1$STYLES
Om<-S2$Om_f; Sig<-S2$Sig; Dvec<-S2$Dvec; grp<-S2$grp; Ecur<-S1$Ecur; HOLD_CUR<-S1$HOLD_CUR

## walk-forward 평균 베타 / 시장분산 share (as_of 단일 스냅샷 아티팩트 방어 — risk-style Cycle2 교훈)
wfl <- rbindlist(lapply(sort(unique(HOLDH$hold_ym)), function(hm){
  E <- EXP[hold_ym==hm & Ticker %chin% HOLDH[hold_ym==hm]$Ticker]
  if(nrow(E)<10L) return(NULL)
  data.table(hold_ym=hm, beta=mean(E$beta), x_mom=mean(E$x_mom), x_vol=mean(E$x_vol),
             x_size=mean(E$x_size), n=nrow(E)) }))
wf_beta <- mean(wfl$beta)
# 월별 시장분산 share (그 달 Omega 는 직전 504일 rolling — PIT)
Xfull<-S1$Xfull; FRET<-S1$FRET; yms<-S1$yms
ms <- rbindlist(lapply(sort(unique(HOLDH$hold_ym)), function(hm){
  hi <- which(FRET$ym < hm); if(length(hi)<504L) return(NULL)
  Xi <- Xfull[tail(hi,504L),,drop=FALSE]; lc <- which(apply(Xi,2,sd)>1e-14)
  O <- matrix(0,length(FCOLS),length(FCOLS),dimnames=list(FCOLS,FCOLS)); O[lc,lc] <- cov(Xi[,lc,drop=FALSE])
  E <- EXP[hold_ym==hm & Ticker %chin% HOLDH[hold_ym==hm]$Ticker]; if(nrow(E)<10L) return(NULL)
  B <- matrix(0,nrow(E),length(FCOLS),dimnames=list(E$Ticker,FCOLS)); B[,"Market"]<-E$beta
  for(s in secs){cn<-paste0("SEC_",s); if(cn%in%FCOLS) B[,cn]<-as.integer(E$Sector==s)}
  for(st in STYLES) B[,st]<-E[[st]]
  wv <- rep(1/nrow(E), nrow(E)); Bw <- as.numeric(t(B)%*%wv)
  dv <- rep(median(S1$RVM[ym<hm]$sv_d, na.rm=TRUE), nrow(E))
  tot <- as.numeric(t(wv)%*%(B%*%O%*%t(B))%*%wv) + sum(wv^2*dv)
  fc <- outer(Bw,Bw)*O
  data.table(hold_ym=hm, mkt=sum(fc[which(grp=="Market"),])/tot, sec=sum(fc[which(grp=="Sector"),])/tot,
             sty=sum(fc[which(grp=="Style"),])/tot, spec=sum(wv^2*dv)/tot) }))
wf_share <- ms[, .(Market=mean(mkt), Sector=mean(sec), Style=mean(sty), Specific=mean(spec), n=.N)]
cat(sprintf("[R6] walk-forward 평균 beta %.3f (as-of %.3f) | 평균 분산share Market %.1f%% Sector %.1f%% Style %.1f%% Spec %.1f%% (n=%d)\n",
  wf_beta, S3$stress_scenarios$portfolio_beta, 100*wf_share$Market, 100*wf_share$Sector,
  100*wf_share$Style, 100*wf_share$Specific, wf_share$n))

## crowding 3개월 delta (RAPID_INCREASE 감지)
prev_d <- sort(unique(EXP$Date)); prev_d <- prev_d[prev_d < SIG_DATE]; d3 <- tail(prev_d,3)[1]
Ep <- EXP[Date==d3]
FE3 <- rbindlist(list(
  data.table(Ticker=Ep$Ticker, factor_name="Momentum_JT1993_6M_skip1", exposure=Ep$x_mom),
  data.table(Ticker=Ep$Ticker, factor_name="LowVol_realized126d",      exposure=-Ep$x_vol),
  data.table(Ticker=Ep$Ticker, factor_name="Size_logMktCap",           exposure=Ep$x_size),
  data.table(Ticker=Ep$Ticker, factor_name="Liquidity_ADV20",          exposure=Ep$x_liq)))
bench_tk <- as.data.table(RI$memb)[K200==TRUE | KQ150==TRUE]$Ticker
CS3 <- tryCatch(crowding_score_per_factor(FE3, d3, as.data.table(RI$RD_slim),
        benchmark_tickers=bench_tk, top_n=25L), error=function(e) NULL)
CSn <- rbindlist(lapply(S3$crowding_score_per_factor, as.data.table), fill=TRUE)
if(!is.null(CS3)) { CSn <- merge(CSn, CS3[, .(factor_name, cs_3m_ago=crowding_score)], by="factor_name", all.x=TRUE)
  CSn[, delta_3m := crowding_score - cs_3m_ago]
  CSn[, alert := fifelse(crowding_score>=0.75, "LEVEL_HIGH",
                  fifelse(is.finite(delta_3m) & delta_3m>=0.15, "RAPID_INCREASE", "none"))] }
print(CSn[, .(factor_name, crowding_score=round(crowding_score,4), cs_3m_ago=round(cs_3m_ago,4),
              delta_3m=round(delta_3m,4), alert)])

## ── 산출물 parquet ────────────────────────────────────────────────────────
Bmat <- S1$Bmat
EXPO <- as.data.table(Bmat, keep.rownames="Ticker")
write_parquet(EXPO, file.path(OUT,"exposure_matrix.parquet"))
FCOV <- as.data.table(Om*MON, keep.rownames="factor")
write_parquet(FCOV, file.path(OUT,"factor_covariance.parquet"))
SPEC <- data.table(Ticker=names(Dvec), specific_var_daily=as.numeric(Dvec),
                   specific_var_monthly=as.numeric(Dvec)*MON,
                   specific_vol_annualized=sqrt(as.numeric(Dvec)*252))
write_parquet(SPEC, file.path(OUT,"specific_risk.parquet"))
COV <- as.data.table(Sig, keep.rownames="Ticker")
write_parquet(COV, file.path(OUT,"covariance.parquet"))
COVP <- as.data.table(S2$Sig_p, keep.rownames="Ticker"); write_parquet(COVP, file.path(OUT,"covariance_panic.parquet"))
COVN <- as.data.table(S2$Sig_n, keep.rownames="Ticker"); write_parquet(COVN, file.path(OUT,"covariance_normal.parquet"))
RCq <- copy(S2$RC); RCq[, regime := fifelse(panic==1L,"PANIC","NORMAL")]
sfun <- function(Z){ s<-sqrt(diag(Z)); C<-Z/outer(s,s); C }
CPl <- sfun(S2$Sig_p); CNl <- sfun(S2$Sig_n)
REGC <- rbindlist(list(
  data.table(scope="monthly_realized", regime=RCq$regime, ym=RCq$ym, n_names=RCq$n,
             mean_pairwise_corr=RCq$mean_corr, vol_ann=RCq$vol_ann, i=NA_character_, j=NA_character_, corr=NA_real_),
  data.table(scope="structural_sigma", regime="PANIC", ym=NA_character_, n_names=25L,
             mean_pairwise_corr=mean(CPl[upper.tri(CPl)]), vol_ann=S2$reg$vol_ann_panic,
             i=rownames(CPl)[row(CPl)[upper.tri(CPl)]], j=colnames(CPl)[col(CPl)[upper.tri(CPl)]],
             corr=CPl[upper.tri(CPl)]),
  data.table(scope="structural_sigma", regime="NORMAL", ym=NA_character_, n_names=25L,
             mean_pairwise_corr=mean(CNl[upper.tri(CNl)]), vol_ann=S2$reg$vol_ann_normal,
             i=rownames(CNl)[row(CNl)[upper.tri(CNl)]], j=colnames(CNl)[col(CNl)[upper.tri(CNl)]],
             corr=CNl[upper.tri(CNl)])), fill=TRUE)
write_parquet(REGC, file.path(OUT,"regime_correlation.parquet"))
write_json(S3$tail_risk, file.path(OUT,"tail_risk.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
cat("[R6] parquet/json emit 완료\n")
saveRDS(list(wf_beta=wf_beta, wf_share=wf_share, ms=ms, CSn=CSn, wfl=wfl), file.path(OUT,"risk_calc_stage4.rds"))
