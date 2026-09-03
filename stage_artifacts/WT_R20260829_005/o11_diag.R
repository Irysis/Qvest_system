## WT-R20260829_005 Optimizer — Step C: 선택 판정 + as-of 위험지표 + 진단
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite); library(quadprog)})

S5 <- readRDS("stage_artifacts/WT_R20260829_005/opt_r5.rds")
S7 <- readRDS("stage_artifacts/WT_R20260829_005/opt_r7.rds")
res <- S7$res; sched <- S7$sched
BM <- S5$BM; RET <- S5$RET; sel <- S5$sel
ap <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/alpha_package.json", simplifyVector = FALSE)
rp <- fromJSON("qepm/mailbox/worktask/WT-R20260829_005/risk_package.json", simplifyVector = FALSE)
LCF <- rp$handoff_to_optimizer$level_calibration_factor$value

## ---------- 1. 사전선언 규칙 적용 ----------
tab <- rbindlist(lapply(names(res), function(n) {
  x <- res[[n]]; data.table(method=n, net_ir=x$net_ir, act_ann=x$mean_act_ann, te=x$te_ann,
    to_ann=x$to_ann, cagr=x$cagr, mdd=x$mdd, calmar=x$calmar, hhi=x$hhi, wmax=x$wmax,
    act_cvar95=x$act_cvar95, fallback=x$fallback_n, gross_ir=x$gross_ir, cost_ann=x$cost_ann)
}))
tab[, dq_turnover := to_ann > 11.0]
cat("=== 사전선언 규칙 적용 ===\n"); print(tab[, .(method, net_ir=round(net_ir,4), to_ann=round(to_ann,3), dq_turnover)])
elig <- tab[dq_turnover == FALSE][order(-net_ir)]
best <- elig$net_ir[1]
elig[, in_band := (best - net_ir) < 0.10]
cat("\n적격(TO<=11):\n"); print(elig[, .(method, net_ir=round(net_ir,4), to_ann=round(to_ann,3), in_band)])
band <- elig[in_band == TRUE][order(to_ann)]
SELECTED <- band$method[1]
cat("\n밴드 내 전원 비결정 -> tie-break ① 최저 회전율 =>", SELECTED, "\n")

## ---------- 2. 진단 A: KR 낙폭상태 (risk 정정 ②) ----------
bm <- BM[order(Date)]; bm[, cum := cumprod(1+BM_Ret)]; bm[, dd := cum/cummax(cum)-1]
bear <- bm[dd <= -0.20, Date]
cat("\n=== KR_Bear 상태(벤치 낙폭<=-20%) 개월:", length(bear), "/", nrow(bm), "===\n")
bear_diag <- rbindlist(lapply(names(sched), function(n) {
  R <- merge(sched[[n]]$R, BM, by="Date"); R[, act := net - BM_Ret]
  data.table(method=n,
    bear_strat_cum = prod(1+R[Date %in% bear]$net)-1,
    bear_bench_cum = prod(1+R[Date %in% bear]$BM_Ret)-1,
    bear_act_ann   = mean(R[Date %in% bear]$act)*12,
    norm_act_ann   = mean(R[!Date %in% bear]$act)*12)
}))
bear_diag[, bear_excess_pp := bear_strat_cum - bear_bench_cum]
print(bear_diag)

## ---------- 3. 진단 B: fallback 구간 제외 부표본 (2007-01~) ----------
sub <- rbindlist(lapply(names(sched), function(n) {
  R <- merge(sched[[n]]$R, BM, by="Date")[Date >= as.Date("2007-01-01")]
  act <- R$net - R$BM_Ret
  data.table(method=n, sub_net_ir = mean(act)*12/(sd(act)*sqrt(12)), sub_to = mean(R$to)*12, n=nrow(R))
}))
cat("\n=== 부표본 2007-01~ (위험기반 arm 이 실제로 작동한 구간) ===\n"); print(sub)

## ---------- 4. 진단 C: 회전율 두 규약 ----------
to_drift <- function(W) {
  W2 <- merge(W, RET, by=c("Date","Ticker"), all.x=TRUE); W2[is.na(Ret_1m), Ret_1m:=0]
  ds <- sort(unique(W2$Date)); prev <- data.table(Ticker=character(), wp=numeric()); v <- numeric(length(ds))
  for (i in seq_along(ds)) { cur <- W2[Date==ds[i], .(Ticker,w,Ret_1m)]
    m <- merge(cur[,.(Ticker,w)], prev, by="Ticker", all=TRUE); m[is.na(w),w:=0]; m[is.na(wp),wp:=0]
    v[i] <- sum(abs(m$w-m$wp)); prev <- cur[, .(Ticker, wp=w*(1+Ret_1m)/sum(w*(1+Ret_1m)))] }
  mean(v)*12
}
tocmp <- rbindlist(lapply(names(sched), function(n) data.table(method=n,
  to_nodrift_x12 = res[[n]]$to_ann, to_drift_x12 = to_drift(sched[[n]]$W),
  to_roundtrip_x2 = res[[n]]$to_ann*2)))
cat("\n=== 회전율 규약 대조 ===\n"); print(tocmp)

## ---------- 5. as-of 위험지표 (권위 Sigma, 원본 그대로) ----------
CV <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/covariance.parquet"))
tick <- CV$Ticker; Sg <- as.matrix(CV[, -1]); rownames(Sg) <- tick
BCV <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/benchmark_covariance.parquet"))
EXP <- as.data.table(read_parquet("stage_artifacts/WT_R20260829_005/exposure_matrix.parquet"))
d_last <- max(sel$Date)
W_last <- sched[[SELECTED]]$W[Date == d_last]
tk <- W_last$Ticker; w <- W_last$w; names(w) <- tk
stopifnot(all(tk %in% tick))
Sg25 <- Sg[tk, tk]
wb <- setNames(rep(0, length(tick)), tick)
bw <- BCV$bench_weight_proxy; names(bw) <- BCV$Ticker
wb[names(bw)] <- bw
wfull <- setNames(rep(0, length(tick)), tick); wfull[tk] <- w
act <- wfull - wb
var_m  <- as.numeric(t(wfull) %*% Sg %*% wfull)
te_m   <- sqrt(as.numeric(t(act) %*% Sg %*% act))
vol_ann_raw <- sqrt(var_m*12); vol_ann_cal <- vol_ann_raw*LCF
te_ann_raw  <- te_m*sqrt(12);  te_ann_cal  <- te_ann_raw*LCF
z95 <- qnorm(0.05); cvar_mult <- dnorm(z95)/0.05          # 2.0627
cvar95_m_raw <- cvar_mult*sqrt(var_m); cvar95_m_cal <- cvar95_m_raw*LCF
alp <- unlist(ap$alpha_vector); alb <- unlist(ap$alpha_lower_bound_vector); cnf <- unlist(ap$confidence_vector)
exp_act <- sum(w*alp[tk]); exp_act_lb <- sum(w*alb[tk])
R_sel <- merge(sched[[SELECTED]]$R, BM, by="Date"); act_ser <- R_sel$net - R_sel$BM_Ret
cat(sprintf("\n=== as-of (%s) %s 위험지표 ===\n", d_last, SELECTED))
cat(sprintf("predicted vol ann  raw %.4f | x1.3842 %.4f\n", vol_ann_raw, vol_ann_cal))
cat(sprintf("tracking error ann raw %.4f | x1.3842 %.4f\n", te_ann_raw, te_ann_cal))
cat(sprintf("param CVaR95 (1M)  raw %.4f | x1.3842 %.4f\n", cvar95_m_raw, cvar95_m_cal))
cat(sprintf("realized CVaR95 total(1M) %.4f | active %.4f\n",
    -mean(sort(R_sel$net)[1:ceiling(0.05*nrow(R_sel))]), -mean(sort(act_ser)[1:ceiling(0.05*length(act_ser))])))
cat(sprintf("E[active] 1M %.5f (ann %.4f) | lower-bound 1M %.5f (ann %.4f) | IR_ex_ante %.3f\n",
    exp_act, exp_act*12, exp_act_lb, exp_act_lb*12, (exp_act*12)/te_ann_raw))
cat(sprintf("confidence range on held names: %.3f ~ %.3f\n", min(cnf[tk]), max(cnf[tk])))

## ---------- 6. Step 5 민감도: 권위 Sigma 기반 as-of 대안 (선택 후보 아님) ----------
sens <- list()
iv <- 1/diag(Sg25); sens$IVP_asof <- iv/sum(iv)
dm <- diag(Sg25); Dv <- solve(Sg25 + diag(1e-8, 25))
one <- rep(1,25); mv <- Dv %*% one; mv <- as.numeric(mv/sum(mv))
sens$MinVar_unconstrained <- setNames(mv, tk)
qp <- solve.QP(Dmat = 2*(Sg25 + diag(1e-8,25)), dvec = rep(0,25),
               Amat = cbind(rep(1,25), diag(25)), bvec = c(1, rep(0,25)), meq = 1)
sens$MinVar_longonly <- setNames(qp$solution, tk)
lam <- 2.0
qp2 <- solve.QP(Dmat = lam*(Sg25 + diag(1e-8,25)), dvec = alp[tk],
                Amat = cbind(rep(1,25), diag(25)), bvec = c(1, rep(0,25)), meq = 1)
sens$MVO_lam2_longonly <- setNames(qp2$solution, tk)
cat("\n=== as-of 민감도 (권위 Sigma, 25종 부분행렬) — 선택 후보 아님 ===\n")
for (n in names(sens)) {
  ww <- sens[[n]]
  cat(sprintf("%-22s HHI %.4f | wmax %.3f | n_eff %.1f | vol_ann_raw %.4f | corr(w,EW-dev) L1dist_to_EW %.3f\n",
      n, sum(ww^2), max(ww), 1/sum(ww^2), sqrt(as.numeric(t(ww)%*%Sg25%*%ww)*12), sum(abs(ww-1/25))))
}
cat(sprintf("%-22s HHI %.4f | wmax %.3f | n_eff %.1f | vol_ann_raw %.4f\n", "EW(selected)",
    sum(w^2), max(w), 1/sum(w^2), sqrt(as.numeric(t(w)%*%Sg25%*%w)*12)))

## ---------- 7. as-of 섹터 분포 ----------
secs <- merge(data.table(Ticker=tk, w=w), EXP[, .(Ticker, Sector, mkt, adv, Size)], by="Ticker", all.x=TRUE)
sd_ <- secs[, .(w=sum(w), n=.N), by=Sector][order(-w)]
cat("\n=== as-of 섹터 분포 ===\n"); print(sd_)
cat("sector HHI:", sum(sd_$w^2), " n_eff_sector:", 1/sum(sd_$w^2), " KQ150 share:", secs[mkt!="K200", sum(w)], "\n")
cat("min adv20:", min(secs$adv, na.rm=TRUE), " (floor 2e8)\n")

saveRDS(list(tab=tab, elig=elig, SELECTED=SELECTED, bear_diag=bear_diag, bear_n=length(bear), sub=sub,
             tocmp=tocmp, d_last=d_last, w=w, tk=tk, vol_ann_raw=vol_ann_raw, vol_ann_cal=vol_ann_cal,
             te_ann_raw=te_ann_raw, te_ann_cal=te_ann_cal, cvar95_m_raw=cvar95_m_raw, cvar95_m_cal=cvar95_m_cal,
             exp_act=exp_act, exp_act_lb=exp_act_lb, sens=sens, secs=secs, sd_=sd_, LCF=LCF,
             realized_cvar_total=-mean(sort(R_sel$net)[1:ceiling(0.05*nrow(R_sel))]),
             realized_cvar_act=-mean(sort(act_ser)[1:ceiling(0.05*length(act_ser))])),
        "stage_artifacts/WT_R20260829_005/opt_r11.rds")
cat("\nsaved o11.\n")
