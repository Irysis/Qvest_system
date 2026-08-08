# p9_economic_reframe.R — 라벨 lane L4: 판정 지표를 분류에서 경제로 바꾸면 결론이 유지되는가
# 재검토 동기: P6/P7 은 "최악 10분위 월"을 맞히는 **분류** 문제로 채점했다. 그러나 실제 소비는
#   연속적 de-risk(β 축소)다. 경제적으로 중요한 건 "위기월을 맞혔나"가 아니라
#   **발화월의 기대수익이 음수인가**(=줄이면 이득인가). 오탐이라도 그 달 수익이 음수면 손해가 아니다.
#   → 08-02 확립사실 "소비 경로가 판정을 바꾼다"의 자기적용. 분류 FAIL 이 경제 FAIL 을 함의하지 않는다.
# 채점: ① 발화월 평균 sleeve 수익 vs 미발화월 (Welch t) ② 발화월 β=0.5 적용 시 SR/MDD/CAGR 실측
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
setorder(R, decision_date)
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
R <- merge(R, unique(car[, .(decision_date, invested)]), by="decision_date", all.x=TRUE)
setorder(R, decision_date)

bm <- as.data.table(read_parquet(".cache/benchmark.parquet")); bm[, Date := as.Date(Date)]
bm <- bm[is.finite(BM_Ret)][order(Date)]; bm[, cum := cumprod(1+BM_Ret)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]; raw[, TV := Close*Vol]
DA <- raw[, .(n=.N, ew=mean(Ret), disp=sd(Ret), frac_neg=mean(Ret<0), tv=sum(TV,na.rm=TRUE)), by=Date][n>=100][order(Date)]
rm(raw); invisible(gc())

feat <- rbindlist(lapply(seq_len(nrow(R)), function(i) {
  dd <- R$decision_date[i]
  hb <- bm[Date < dd]; hd <- DA[Date < dd]
  if (nrow(hb) < 260 || nrow(hd) < 300) return(data.table(decision_date=dd, dd12=NA_real_, vol20=NA_real_,
      ret3m=NA_real_, volr=NA_real_, disp20=NA_real_, breadth=NA_real_, absorb=NA_real_, turnz=NA_real_, dtrend=NA_real_))
  b252 <- tail(hb,252); b20 <- tail(hb,20); b60 <- tail(hb,60); b63 <- tail(hb,63)
  d20 <- tail(hd,20); d60 <- tail(hd,60); d250 <- tail(hd,250)
  data.table(decision_date=dd,
    dd12 = tail(hb$cum,1)/max(b252$cum)-1, vol20 = sd(b20$BM_Ret)*sqrt(252),
    ret3m = prod(1+b63$BM_Ret)-1, volr = sd(b20$BM_Ret)/pmax(sd(b60$BM_Ret),1e-12),
    disp20 = mean(d20$disp), breadth = mean(1-d20$frac_neg),
    absorb = sd(d60$ew)/pmax(mean(d60$disp),1e-12),
    turnz = (mean(log(d20$tv))-mean(log(d250$tv)))/pmax(sd(log(d250$tv)),1e-12),
    dtrend = mean(d20$disp)/pmax(mean(d60$disp),1e-12))
}))
E <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA, invested)], feat, by="decision_date")
E <- E[is.finite(absorb) & is.finite(dd12) & is.finite(invested)]
setorder(E, decision_date)
cat(sprintf("[표본] %d개월 %s~%s | 전체 평균 sleeve %+.2f%%\n", nrow(E), min(E$eval_date), max(E$eval_date), 100*mean(E$gross)))

expq <- function(x,p,mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)],p,names=FALSE,na.rm=TRUE))
E[, `:=`(q_dd=expq(dd12,0.20), q_vol=expq(vol20,0.80), q_r3=expq(ret3m,0.20), q_vr=expq(volr,0.80),
         q_disp=expq(disp20,0.80), q_bre=expq(breadth,0.20), q_abs=expq(absorb,0.80),
         q_turn=expq(turnz,0.80), q_dt=expq(dtrend,0.80))]
E[, base_net := gross*invested - BPS*turn*invested]
base_x <- xts(E$base_net, order.by=E$eval_date); bt <- table.AnnualizedReturns(base_x, scale=12, Rf=0)
cat(sprintf("[기준선] SR %.3f · CAGR %.2f%% · MDD %.2f%%\n",
    as.numeric(bt[3,1]), as.numeric(bt[1,1])*100, as.numeric(maxDrawdown(base_x))*100))

sigs <- list(
  "라벨 CRISIS+CAUTION" = E$regime %in% c("CRISIS","CAUTION"),
  "낙폭 ≤ q20"        = E$dd12  <= E$q_dd,
  "변동성 ≥ q80"      = E$vol20 >= E$q_vol,
  "3개월수익 ≤ q20"   = E$ret3m <= E$q_r3,
  "변동성비 ≥ q80"    = E$volr  >= E$q_vr,
  "횡단면분산 ≥ q80"  = E$disp20>= E$q_disp,
  "상승종목비율 ≤ q20"= E$breadth<= E$q_bre,
  "동조화 ≥ q80"      = E$absorb>= E$q_abs,
  "거래대금z ≥ q80"   = E$turnz >= E$q_turn,
  "분산급확대 ≥ q80"  = E$dtrend>= E$q_dt)

rows <- lapply(names(sigs), function(nm) {
  f <- sigs[[nm]]; f[is.na(f)] <- FALSE
  if (sum(f) < 5 || sum(!f) < 5) return(NULL)
  tt <- t.test(E$gross[f], E$gross[!f])
  inv2 <- E$invested; inv2[f] <- pmin(inv2[f], 0.50)          # 발화월 β≤0.50 (기존 라벨과 동일 깊이)
  net2 <- E$gross*inv2 - BPS*E$turn*inv2
  x2 <- xts(net2, order.by=E$eval_date); t2 <- table.AnnualizedReturns(x2, scale=12, Rf=0)
  data.table(signal=nm, 발화=sum(f), 발화율=round(100*mean(f),1),
    발화월_평균=round(100*mean(E$gross[f]),2), 미발화월_평균=round(100*mean(E$gross[!f]),2),
    차이=round(100*(mean(E$gross[f])-mean(E$gross[!f])),2), t=round(as.numeric(tt$statistic),2),
    p=round(tt$p.value,4),
    SR=round(as.numeric(t2[3,1]),3), dSR=round(as.numeric(t2[3,1])-as.numeric(bt[3,1]),3),
    MDD=round(as.numeric(maxDrawdown(x2))*100,2), dMDD=round(as.numeric(maxDrawdown(x2))*100-as.numeric(maxDrawdown(base_x))*100,2))
})
out <- rbindlist(Filter(Negate(is.null), rows))
setorder(out, -dSR)
cat("\n===== 경제적 채점: 발화월 기대수익 + β0.5 적용 실측 (dSR 내림차순) =====\n"); print(out)
cat(sprintf("\n[해석] 발화월_평균 < 0 이면 그 달 노출을 줄이는 게 이득. 분류 precision 과 무관.\n"))
cat(sprintf("[대조] P6/P7 분류 채점서 자격 PASS 는 라벨 1종뿐이었음 — 경제 채점서 dSR>0 인 신호 %d종\n", sum(out$dSR > 0)))
fwrite(out, "stage_artifacts/tilt_realign_20260808/p9_economic_reframe.csv")
