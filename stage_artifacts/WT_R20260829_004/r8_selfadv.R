# R8 — Self-Adversarial Challenge 의 정량 검증 4종 + risk_package 보강
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004"); MB <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
S1<-readRDS(file.path(OUT,"risk_calc_stage1.rds")); S2<-readRDS(file.path(OUT,"risk_calc_stage2.rds"))
MON <- 21L; w <- rep(1/25,25)

## SC4 — 국면 배율의 에피소드 수준 분산 (실질 자유도 4)
RC <- copy(S2$RC); PAN <- S1$PANIC_YM
epi <- data.table(ym=sort(PAN))
epi[, ord := seq_len(.N)]
epi[, d := as.integer(substr(ym,1,4))*12 + as.integer(substr(ym,6,7))]
epi[, brk := cumsum(c(1, diff(d)!=1))]
RCp <- merge(RC, epi[, .(ym, brk)], by="ym")
base_vol <- RC[panic==0L, mean(vol_ann, na.rm=TRUE)]
ep <- RCp[, .(n=.N, vol=mean(vol_ann,na.rm=TRUE), corr=mean(mean_corr,na.rm=TRUE)), by=brk]
ep[, ratio := vol/base_vol]
cat("[SC4] 에피소드별 실현 vol 배율(비패닉 평균 대비):\n"); print(ep)
cat(sprintf("[SC4] 배율 범위 %.2f~%.2f · 에피소드 sd %.3f · n_episodes=%d\n",
            min(ep$ratio), max(ep$ratio), sd(ep$ratio), nrow(ep)))

## SC5 — EVT threshold 안정성 (xi 가 threshold 아티팩트인가)
SLD <- S1$SLD; rd <- SLD$ret_d
gpd <- function(r, q){ l <- -r[is.finite(r)]; u <- as.numeric(quantile(l,q)); ex <- l[l>u]-u; Nu<-length(ex)
  if(Nu<20) return(c(NA,NA,Nu))
  nll <- function(p){ xi<-p[1]; b<-exp(p[2]); if(xi< -0.5) return(1e10)
    z<-1+xi*ex/b; if(any(z<=0)) return(1e10); Nu*log(b)+(1+1/xi)*sum(log(z)) }
  f <- optim(c(0.1, log(mean(ex))), nll, method="Nelder-Mead")
  c(xi=f$par[1], beta=exp(f$par[2]), n=Nu) }
TH <- rbindlist(lapply(c(0.90,0.925,0.95,0.975), function(q){ z<-gpd(rd,q)
  data.table(threshold_q=q, xi=z[1], beta=z[2], n_exceed=z[3]) }))
cat("[SC5] GPD threshold 안정성:\n"); print(TH)

## SC6 — D 추정 민감도 (halflife x floor)
RVM <- S1$RVM; yms <- S1$yms; HOLD <- S1$HOLD_CUR; cur_ym <- "2026-08"
d_est2 <- function(tickers, hl, fl, n_back=24L){
  ymk <- tail(yms[yms<=cur_ym], n_back); Z <- RVM[ym %in% ymk & Ticker %chin% tickers]
  wt <- data.table(ym=ymk, w=(0.5^(1/hl))^((length(ymk)-1):0)); Z <- merge(Z,wt,by="ym")
  agg <- Z[, .(sv=sum(sv_d*w)/sum(w), nm=.N), by=Ticker]
  med <- median(RVM[ym %in% ymk]$sv_d, na.rm=TRUE)
  out <- setNames(rep(med,length(tickers)),tickers); ok<-agg[nm>=6L]; out[ok$Ticker]<-ok$sv
  pmax(out, fl*med) }
Bm <- S1$Bmat; Om <- S2$Om_f
SENS <- rbindlist(lapply(c(3,6,12), function(hl) rbindlist(lapply(c(0.10,0.25,0.50), function(fl){
  dv <- d_est2(HOLD, hl, fl); Sg <- (Bm%*%Om%*%t(Bm)+diag(dv[rownames(Bm)]))*MON
  tot <- as.numeric(t(w)%*%Sg%*%w)
  data.table(hl_months=hl, floor_x_median=fl, vol_ann=sqrt(tot*12),
             spec_share=sum(w^2*dv)*MON/tot) }))))
cat("[SC6] D 민감도:\n"); print(SENS)
cat(sprintf("[SC6] vol 범위 %.3f~%.3f (기준 hl=6 floor=0.25: %.3f) · spec_share 범위 %.4f~%.4f\n",
  min(SENS$vol_ann), max(SENS$vol_ann), SENS[hl_months==6 & floor_x_median==0.25]$vol_ann,
  min(SENS$spec_share), max(SENS$spec_share)))

## SC7 — 섹터 집중이 Sigma 안에 있는가 (반도체 블록 분산 기여)
Ecur <- S1$Ecur; Sig <- S2$Sig
tot <- as.numeric(t(w)%*%Sig%*%w)
blk <- lapply(unique(Ecur$Sector), function(s){
  idx <- which(Ecur$Sector==s)
  list(sector=s, n=length(idx), weight=length(idx)/25,
       within_block_var_share = sum(outer(w[idx],w[idx])*Sig[idx,idx,drop=FALSE])/tot,
       total_contribution = sum(w[idx]*(Sig[idx,,drop=FALSE]%*%w))/tot) })
BLK <- rbindlist(lapply(blk, as.data.table))[order(-total_contribution)]
cat("[SC7] 섹터 블록 분산 기여:\n"); print(BLK)

saveRDS(list(ep=ep, TH=TH, SENS=SENS, BLK=BLK, base_vol=base_vol), file.path(OUT,"risk_calc_stage5.rds"))
cat("[R8] done\n")
