# O5 — 진단: 선택 안정성(anchored) · DSR/oos · Sigma as-of 위험분해 · 집중 · 꼬리 · 회전율
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/validation/statistical_defense.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
O2 <- readRDS(file.path(OUT,"o2_objects.rds")); O3 <- readRDS(file.path(OUT,"o3_objects.rds"))
RES <- O2$RES; RESC <- O2$RESC; PPY <- 12L
SEL <- "W2_IV"; W_sel <- RES[[SEL]]$W; M_sel <- RES[[SEL]]$M

## ── 1. anchored-window method 선택 안정성 (IS-selection 노출 실측) ───────────
cal <- function(r){ n<-length(r); nav<-cumprod(1+r); mdd<-min(nav/cummax(nav)-1); (prod(1+r)^(PPY/n)-1)/abs(mdd) }
srf <- function(r) mean(r)/stats::sd(r)*sqrt(PPY)
PRs <- lapply(RES, function(x) as.data.table(x$M$pr)$ret_net)
nT <- length(PRs[[1]])
anch <- rbindlist(lapply(c(0.55,0.65,0.75,1.00), function(f){ k <- floor(nT*f)
  z <- sapply(PRs, function(r) cal(r[1:k]))
  data.table(frac=f, k=k, winner=names(which.max(z)), t(as.data.table(as.list(round(z,4))))) }), fill=TRUE)
sel_stability <- rbindlist(lapply(c(0.55,0.65,0.75,1.00), function(f){ k <- floor(nT*f)
  z <- sapply(PRs, function(r) cal(r[1:k])); data.table(frac=f, k=k, winner=names(which.max(z)),
    W2_IV=z[["W2_IV"]], W5_WCH_IV=z[["W5_WCH_IV"]], W1_EW=z[["W1_EW"]]) }))
print(sel_stability)

## ── 2. DSR (sweep n_trials=5) + oos_retention 근사 ───────────────────────────
pr_sel <- as.data.table(M_sel$pr); r <- pr_sel$ret_net; act <- r - pr_sel$benchmark_ret
sk <- function(x) mean((x-mean(x))^3)/stats::sd(x)^3; ek <- function(x) mean((x-mean(x))^4)/stats::sd(x)^4 - 3
dsr_abs <- compute_dsr(mean(r)/stats::sd(r), length(r), 5, sk(r), ek(r))
dsr_act <- compute_dsr(mean(act)/stats::sd(act), length(act), 5, sk(act), ek(act))
oos_rough <- median(sapply(c(0.55,0.65,0.75), function(f){ k <- floor(length(act)*f)
  srf(act[(k+1):length(act)])/srf(act[1:k]) }))
cat(sprintf("[O5] DSR(abs SR, n_trials=5)=%.4f | DSR(active)=%.4f | oos_retention(active, v2근사)=%.4f\n",
            dsr_abs$dsr, dsr_act$dsr, oos_rough))

## ── 3. Sigma as-of 위험분해 (risk 발행 Sigma 소비 — 재추정 없음) ────────────
CV <- as.data.table(read_parquet(file.path(OUT,"covariance.parquet")))
EXP <- as.data.table(read_parquet(file.path(OUT,"exposure_matrix.parquet")))
cn <- names(CV); tick_col <- if("Ticker" %in% cn) "Ticker" else cn[1]
tk <- CV[[tick_col]]; S <- as.matrix(CV[, setdiff(cn, tick_col), with=FALSE]); rownames(S) <- tk
asof <- max(W_sel$Date); Wa <- W_sel[Date==asof]
stopifnot(all(Wa$Ticker %in% rownames(S)))
S <- S[Wa$Ticker, Wa$Ticker]
w_iv <- Wa$w; w_ew <- rep(1/nrow(Wa), nrow(Wa))
ann <- function(w) sqrt(as.numeric(t(w)%*%S%*%w))*sqrt(12)
rc <- function(w){ mrc <- as.numeric(S%*%w); v <- as.numeric(t(w)%*%S%*%w); (w*mrc)/v }
secv <- Wa$Sector; semi <- which(secv=="반도체")
blk <- function(w){ v <- as.numeric(t(w)%*%S%*%w); ws <- w; ws[-semi] <- 0
  list(weight=sum(w[semi]), var_contrib=as.numeric(t(ws)%*%S%*%w)/v,
       internal=as.numeric(t(ws)%*%S[,,drop=FALSE]%*%ws)/v) }
EXPm <- EXP[match(Wa$Ticker, EXP$Ticker)]
bt <- function(w) sum(w*EXPm$Market)
sig_diag <- list(as_of=as.character(asof), n=nrow(Wa),
  ew=list(vol_ann=ann(w_ew), beta_exposure=bt(w_ew), max_rc=max(rc(w_ew)), hhi=sum(w_ew^2),
          max_w=max(w_ew), semi=blk(w_ew)),
  sel=list(vol_ann=ann(w_iv), beta_exposure=bt(w_iv), max_rc=max(rc(w_iv)), hhi=sum(w_iv^2),
          max_w=max(w_iv), semi=blk(w_iv)),
  note="risk 발행 covariance.parquet(as-of, monthly var) 소비 — 재추정 없음. as-of 단면 진단 전용이며 walk-forward 비중 산출에는 Sigma 를 일절 쓰지 않았다(RISK-CH2 해소).")
cat(sprintf("[O5] as-of %s | EW vol=%.3f beta=%.3f semi_w=%.3f semi_varC=%.3f maxRC=%.4f\n",
   asof, sig_diag$ew$vol_ann, sig_diag$ew$beta_exposure, sig_diag$ew$semi$weight,
   sig_diag$ew$semi$var_contrib, sig_diag$ew$max_rc))
cat(sprintf("[O5] as-of %s | IV vol=%.3f beta=%.3f semi_w=%.3f semi_varC=%.3f maxRC=%.4f maxw=%.4f\n",
   asof, sig_diag$sel$vol_ann, sig_diag$sel$beta_exposure, sig_diag$sel$semi$weight,
   sig_diag$sel$semi$var_contrib, sig_diag$sel$max_rc, sig_diag$sel$max_w))

## ── 4. 섹터 집중 walk-forward (반도체 비중 · HHI) ───────────────────────────
secw <- W_sel[, .(sw=sum(w)), by=.(Date, Sector)]
semi_ts <- secw[Sector=="반도체"]
sec_hhi <- secw[, .(hhi=sum(sw^2)), by=Date]
ew_secw <- O2$RES$W1_EW$W[, .(sw=sum(w)), by=.(Date,Sector)][Sector=="반도체"]
conc <- list(semi_weight_mean_sel=mean(semi_ts$sw), semi_weight_max_sel=max(semi_ts$sw),
  semi_weight_asof_sel=semi_ts[Date==asof, sw], semi_weight_asof_ew=ew_secw[Date==asof, sw],
  semi_weight_mean_ew=mean(ew_secw$sw), sector_hhi_mean=mean(sec_hhi$hhi),
  months_semi_over_50pct=nrow(semi_ts[sw>0.5]), n_months=uniqueN(W_sel$Date))
cat(sprintf("[O5] 반도체 비중: sel 평균 %.4f 최대 %.4f as-of %.4f | EW as-of %.4f | >50%% 월 %d/%d\n",
   conc$semi_weight_mean_sel, conc$semi_weight_max_sel, conc$semi_weight_asof_sel,
   conc$semi_weight_asof_ew, conc$months_semi_over_50pct, conc$n_months))

## ── 5. 꼬리 (역사적 — 정규가정 미사용, RISK-CH6) ────────────────────────────
tailf <- function(r){ q <- quantile(r,0.05); nav<-cumprod(1+r); dd <- nav/cummax(nav)-1
  list(var95=unname(q), cvar95=mean(r[r<=q]), mdd=min(dd), cdar95=mean(dd[dd<=quantile(dd,0.05)]),
       skew=sk(r), exkurt=ek(r), worst=min(r)) }
tl <- list(selected=tailf(r), EW_overlayON=tailf(as.data.table(RES$W1_EW$M$pr)$ret_net),
           EW_overlayOFF_A0=tailf(as.data.table(RESC$C1_EW_off$M$pr)$ret_net),
           IV_overlayOFF=tailf(as.data.table(RESC$C2_IV_off$M$pr)$ret_net),
           basis="월간 net(15bps) 실현수익 259개월 · 역사적 분위(정규 가정 없음)")
cat(sprintf("[O5] 꼬리 sel: CVaR95=%.4f CDaR95=%.4f worst=%.4f | EW_ON CVaR95=%.4f | A0 CVaR95=%.4f\n",
   tl$selected$cvar95, tl$selected$cdar95, tl$selected$worst, tl$EW_overlayON$cvar95, tl$EW_overlayOFF_A0$cvar95))

## ── 6. 회전율 분해 (패닉 전이월 vs 정상월) ──────────────────────────────────
dts <- sort(unique(W_sel$Date)); tr <- numeric(length(dts)); prev <- NULL
for(i in seq_along(dts)){ cur <- W_sel[Date==dts[i], .(Ticker,w)]
  m <- if(is.null(prev)) copy(cur)[, w_prev := 0] else merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("","_prev"))
  m[is.na(w), w := 0]; m[is.na(w_prev), w_prev := 0]; tr[i] <- sum(abs(m$w - m$w_prev)); prev <- cur }
TRD <- data.table(Date=dts, traded=tr)
pu <- unique(W_sel[, .(Date, panic_use)]); TRD <- merge(TRD, pu, by="Date")
TRD[, panic_prev := shift(panic_use, 1L)][is.na(panic_prev), panic_prev := 0L]
TRD[, transition := as.integer(panic_use != panic_prev)]
to_diag <- list(turnover_annual=mean(TRD$traded[-1])*12, convention="mean_t sum_i|w_it-w_i,t-1| x 12 (매수+매도 합산 · weighted_screen_bt 계약)",
  cost_annual=mean(TRD$traded[-1])*12*15/1e4, cap=11.0, pass=(mean(TRD$traded[-1])*12 <= 11.0),
  traded_mean_transition=TRD[transition==1 & Date>dts[1], mean(traded)],
  traded_mean_steady=TRD[transition==0 & Date>dts[1], mean(traded)],
  n_transition_months=TRD[transition==1, .N])
cat(sprintf("[O5] TO=%.3f (cap 11.0 pass=%s) cost=%.4f/yr | 전이월 traded %.4f vs 정상월 %.4f (전이 %d회)\n",
   to_diag$turnover_annual, to_diag$pass, to_diag$cost_annual, to_diag$traded_mean_transition,
   to_diag$traded_mean_steady, to_diag$n_transition_months))

saveRDS(list(sel_stability=sel_stability, dsr_abs=dsr_abs, dsr_act=dsr_act, oos_rough=oos_rough,
             sig_diag=sig_diag, conc=conc, tail=tl, to_diag=to_diag, asof=asof, Wa=Wa),
        file.path(OUT,"o5_objects.rds"))
