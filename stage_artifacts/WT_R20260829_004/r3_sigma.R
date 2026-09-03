# R3 — Sigma = B Omega B' + D 추정 · 추정기 method shopping(상한 5) · PIT rolling only(C1)
# 선택축 = PSD·cond<500 게이트(조건수) + 위험예측 캘리브레이션(Barra bias statistic).
#   ★bias test 는 무작위 롱온리 25종 EW 포트(알파 무관)가 1급 — 알파 수익 기반 선택 금지(R4 P3).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
source(file.path(ROOT,"02_Infrastructure/portfolio/hrp_core.R"))
SIG_DATE <- as.Date("2026-08-28"); t0 <- Sys.time(); MON <- 21L

M <- readRDS(file.path(OUT,"risk_factor_model.rds"))
FRET<-M$FRET; ERES<-M$ERES; EXP<-M$EXP; secs<-M$secs; STYLES<-M$STYLES
P <- readRDS(file.path(OUT,"panel.rds"))
A <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
SG<- as.data.table(read_parquet(file.path(OUT,"regime_signal_timeseries.parquet")))
AP<- fromJSON(file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004/alpha_package.json"), simplifyVector=FALSE)
HOLD_CUR <- names(AP$alpha_vector); FCOLS <- setdiff(names(FRET), c("Date","ym"))
PANIC_YM <- SG[panic==1L]$holding_ym; FRET[, panic := as.integer(ym %in% PANIC_YM)]

setorder(A, Date, -score)
HOLDH <- A[, .(Ticker=Ticker[seq_len(min(25L,.N))]), by=Date]
HOLDH[, hold_ym := {d<-as.POSIXlt(Date); sprintf("%04d-%02d", d$year+1900+(d$mon+1)%/%12,(d$mon+1)%%12+1)}]
DD <- as.data.table(P$DAILY)[Date <= SIG_DATE]; DD[, ym := format(Date,"%Y-%m")]
DD[, wl := fifelse(Date >= as.Date("2015-06-15"), 0.31, 0.16)][, Ret := pmin(pmax(Ret,-wl),wl)][, wl := NULL]
setkey(DD, ym, Ticker)
MRET <- DD[, .(ret_m = prod(1+Ret)-1, nd=.N), by=.(ym,Ticker)][nd>=10L]; setkey(MRET, ym, Ticker)
SLD <- merge(DD, HOLDH[, .(Ticker, ym=hold_ym)], by=c("Ticker","ym"))[, .(ret_d=mean(Ret,na.rm=TRUE),n_h=.N), by=Date][order(Date)]
SLD <- merge(SLD, unique(DD[,.(Date,ym)]), by="Date")
ERES[, ym := format(Date,"%Y-%m")]
RVM <- ERES[, .(sv_d=mean(e^2), nd=.N), by=.(Ticker,ym)][nd>=10L]; setkey(RVM, ym, Ticker)
yms <- sort(unique(FRET$ym)); Xfull <- as.matrix(FRET[, ..FCOLS])
setkey(EXP, hold_ym)

ewma_cov <- function(X,hl){ n<-nrow(X); w<-(0.5^(1/hl))^((n-1):0); w<-w/sum(w)
  Xc<-sweep(X,2,colSums(X*w)); crossprod(Xc*sqrt(w)) }
omega_est <- function(X, method){
  lc <- which(apply(X,2,sd) > 1e-14); Xl <- X[,lc,drop=FALSE]
  Om <- switch(method, sample=cov(Xl), ewma_hl126=ewma_cov(Xl,126),
    ledoit_wolf=.get_cor_cov(Xl,"ledoit_wolf")$cov, lw_nls=.get_cor_cov(Xl,"lw_nls")$cov,
    gerber_rmt=.get_cor_cov(Xl,"gerber_rmt")$cov)
  full <- matrix(0, ncol(X), ncol(X), dimnames=list(colnames(X),colnames(X)))
  full[lc,lc] <- Om; attr(full,"live") <- colnames(X)[lc]; full }
cond_of <- function(S){ ev<-eigen((S+t(S))/2,symmetric=TRUE,only.values=TRUE)$values
  list(cond=max(ev)/max(min(ev),.Machine$double.eps), min_ev=min(ev), psd=min(ev)>=-1e-12) }
cond_live <- function(Om){ lc<-attr(Om,"live"); cond_of(Om[lc,lc,drop=FALSE]) }
eigen_floor <- function(S, frac=1e-3){ e<-eigen((S+t(S))/2,symmetric=TRUE)
  lam<-pmax(e$values, frac*max(e$values)); Z<-e$vectors%*%diag(lam)%*%t(e$vectors)
  dimnames(Z)<-dimnames(S); (Z+t(Z))/2 }
d_est <- function(tickers, upto_ym, n_back=24L, hl=6){
  ymk <- tail(yms[yms<=upto_ym], n_back)
  Z <- RVM[.(ymk)][Ticker %chin% tickers]
  wtab <- data.table(ym=ymk, w=(0.5^(1/hl))^((length(ymk)-1):0))
  Z <- merge(Z, wtab, by="ym"); agg <- Z[, .(sv=sum(sv_d*w)/sum(w), nm=.N), by=Ticker]
  med <- median(RVM[.(ymk)]$sv_d, na.rm=TRUE)
  out <- setNames(rep(med,length(tickers)), tickers); ok <- agg[nm>=6L]
  out[ok$Ticker] <- ok$sv; pmax(out, 0.25*med) }
build_B <- function(E){ B<-matrix(0,nrow(E),length(FCOLS),dimnames=list(E$Ticker,FCOLS))
  B[,"Market"]<-E$beta
  for(s in secs){cn<-paste0("SEC_",s); if(cn%in%FCOLS) B[,cn]<-as.integer(E$Sector==s)}
  for(st in STYLES) B[,st]<-E[[st]]; B }
sigma_of <- function(B,Om,dv){ S<-B%*%Om%*%t(B)+diag(dv[rownames(B)],nrow(B)); (S+t(S))/2*MON }

## ── 페어드 walk-forward bias test (2개월 간격 · 무작위 8포트 + 슬리브) ─────
methods <- c("sample","ewma_hl126","ledoit_wolf","lw_nls","gerber_rmt")
set.seed(20260829L)
test_yms <- yms[yms >= "2008-01"]; test_yms <- test_yms[seq(1,length(test_yms),by=2L)]
BSL <- list()
for (hm in test_yms) {
  hi <- which(FRET$ym < hm); if(length(hi)<504L) next
  Xi <- Xfull[tail(hi,504L),,drop=FALSE]
  Eh <- EXP[.(hm)]; if(is.null(Eh)||nrow(Eh)<60L) next
  pv <- yms[which(yms==hm)-1L]; if(!length(pv)||is.na(pv)) next
  dv <- d_est(Eh$Ticker, pv)
  MR <- MRET[.(hm)]; setkey(MR, Ticker)
  ports <- c(list(HOLDH[hold_ym==hm]$Ticker),
             replicate(8L, sample(Eh$Ticker, min(25L,nrow(Eh))), simplify=FALSE))
  Bs <- lapply(ports, function(tt){ Ei<-Eh[Ticker %chin% tt]; if(nrow(Ei)<20L) NULL else Ei })
  reals <- sapply(Bs, function(Ei) if(is.null(Ei)) NA_real_ else
                    mean(MR[.(Ei$Ticker)]$ret_m, na.rm=TRUE))
  for (m in methods) {
    Om <- tryCatch(omega_est(Xi,m), error=function(e) NULL); if(is.null(Om)) next
    for (q in seq_along(Bs)) {
      Ei <- Bs[[q]]; if(is.null(Ei)||!is.finite(reals[q])) next
      Bi <- build_B(Ei); Si <- sigma_of(Bi,Om,dv); w <- rep(1/nrow(Ei),nrow(Ei))
      pred <- sqrt(max(as.numeric(t(w)%*%Si%*%w),1e-12)); b <- reals[q]/pred
      BSL[[length(BSL)+1L]] <- data.table(ym=hm, method=m, port=ifelse(q==1L,"sleeve","random"), b=b)
    }
  }
}
BSD <- rbindlist(BSL)
VOLM <- EXP[, .(univ_vol_med = median(vol126_ann, na.rm=TRUE)), by=hold_ym]
BSD <- merge(BSD, VOLM, by.x="ym", by.y="hold_ym", all.x=TRUE)
vq <- quantile(unique(BSD[,.(ym,univ_vol_med)])[["univ_vol_med"]], c(1/3,2/3), na.rm=TRUE)
BSD[, vol_tercile := fifelse(univ_vol_med<=vq[1],"LOW", fifelse(univ_vol_med<=vq[2],"MID","HIGH"))]
cat(sprintf("[R3] bias test 완료 %.0fs · test months %d\n", as.numeric(difftime(Sys.time(),t0,units="secs")), length(test_yms)))

Xw <- Xfull[(nrow(Xfull)-504L+1L):nrow(Xfull),,drop=FALSE]
Ecur <- EXP[Date==SIG_DATE & Ticker %chin% HOLD_CUR]; setkey(Ecur,Ticker); Ecur <- Ecur[HOLD_CUR]
Bmat <- build_B(Ecur); Dvec <- d_est(HOLD_CUR, format(SIG_DATE,"%Y-%m"))
OM <- list(); MS <- list()
for (m in methods) {
  Om <- tryCatch(omega_est(Xw,m), error=function(e) NULL)
  if(is.null(Om)){ MS[[m]]<-list(name=m,error=TRUE); next }
  OM[[m]] <- Om; co <- cond_live(Om); Sg <- sigma_of(Bmat,Om,Dvec); cs <- cond_of(Sg)
  MS[[m]] <- list(name=m, cond_omega_live=co$cond, psd_omega=co$psd, n_live=length(attr(Om,"live")),
    cond_sigma=cs$cond, psd_sigma=cs$psd, min_ev_sigma=cs$min_ev,
    bias_random=sd(BSD[method==m & port=="random"]$b,na.rm=TRUE), n_random=nrow(BSD[method==m & port=="random"]),
    bias_random_highvol=sd(BSD[method==m & port=="random" & vol_tercile=="HIGH"]$b,na.rm=TRUE),
    n_random_highvol=nrow(BSD[method==m & port=="random" & vol_tercile=="HIGH"]),
    bias_sleeve=sd(BSD[method==m & port=="sleeve"]$b,na.rm=TRUE), n_sleeve=nrow(BSD[method==m & port=="sleeve"]),
    bias_sleeve_highvol=sd(BSD[method==m & port=="sleeve" & vol_tercile=="HIGH"]$b,na.rm=TRUE),
    port_vol_ann_ew=sqrt(sum(Sg/(25^2))*12))
  cat(sprintf("  [%-11s] condO=%9.2f condS=%7.2f biasRnd=%.3f biasSlv=%.3f volEW=%.1f%%\n",
      m, co$cond, cs$cond, MS[[m]]$bias_random, MS[[m]]$bias_sleeve, 100*MS[[m]]$port_vol_ann_ew))
}
saveRDS(list(MS=MS,OM=OM,Bmat=Bmat,Dvec=Dvec,Ecur=Ecur,SLD=SLD,HOLDH=HOLDH,FRET=FRET,RVM=RVM,
  yms=yms,FCOLS=FCOLS,Xfull=Xfull,PANIC_YM=PANIC_YM,secs=secs,STYLES=STYLES,EXP=EXP,MRET=MRET,
  HOLD_CUR=HOLD_CUR,BSD=BSD,vq=vq,DD=DD), file.path(OUT,"risk_calc_stage1.rds"))
cat(sprintf("[R3] done %.1fs\n", as.numeric(difftime(Sys.time(),t0,units="secs"))))
