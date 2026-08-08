# p23_fq093_precheck.R — FQ-093 착수 전 사전 확인
# FQ-093 제안: "vol rank 상승 속도(단면 평균 vol_rank_t − vol_rank_lag3)를 위기 조기경보 overlay 입력으로"
# ★오늘 세션이 이미 인접 계열을 전수 측정했다: P7 의 5종 횡단면·미시구조 신호(횡단면분산·분산급확대·
#   동조화·거래대금z·상승종목비율)가 분류·경제 이중 채점에서 전건 FAIL, D1/I4 의 분산 억제 게이트도 무기여.
#   FQ-093 의 신호가 그 계열과 실제로 겹치는지 **측정으로** 확인한다(주장 아님).
# 측정: ①FQ-093 신호를 명세대로 구성 ②오늘 P7 의 `disp_trend` 와 상관 ③오늘 P9 의 경제 채점 적용
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015
M <- fread("stage_artifacts/tilt_realign_20260808/p16_j1_close.csv"); M[, decision_date := as.Date(decision_date)]
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
D <- merge(M[, .(decision_date, beta_R05, m4)], R[, .(decision_date, eval_date, gross=gA, turn=tA)], by="decision_date")
setorder(D, decision_date)
D[, invested := beta_R05 * m4]

raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
raw[, ymd := as.Date(paste0(format(Date,"%Y-%m"),"-01"))]
# 월별 종목 변동성 → 횡단면 vol rank
V <- raw[, .(vol = sd(Ret, na.rm=TRUE), nd = .N), by=.(Ticker, ymd)][nd >= 10 & is.finite(vol)]
V[, vr := frank(vol, ties.method="average")/.N, by=ymd]
MV <- V[, .(mean_vr = mean(vr), disp = sd(vr)), by=ymd][order(ymd)]
MV[, `:=`(vr_speed = mean_vr - shift(mean_vr, 3),          # FQ-093 명세: 상승 속도(3개월)
          disp_speed = disp / shift(disp, 3))]
# 오늘 P7 의 disp_trend 등가(20일/60일 횡단면 분산비)를 월 단위로 근사 재구성
DA <- raw[, .(cs = sd(Ret, na.rm=TRUE), n=.N), by=Date][n>=100][order(Date)]
DA[, ymd := as.Date(paste0(format(Date,"%Y-%m"),"-01"))]
MD <- DA[, .(cs_m = mean(cs)), by=ymd][order(ymd)]
MD[, disp_trend := cs_m / frollmean(cs_m, 3, align="right")]
X <- merge(MV, MD, by="ymd")
X[, ym := format(ymd, "%Y%m")]
D[, ym := format(as.Date(cut(decision_date, "month")), "%Y%m")]
E <- merge(D, X[, .(ym, vr_speed, disp_speed, disp_trend)], by="ym")
E <- E[is.finite(vr_speed) & is.finite(disp_trend)]; setorder(E, decision_date)
cat(sprintf("[표본] %d개월 %s~%s\n", nrow(E), E$ym[1], E$ym[nrow(E)]))

cat(sprintf("\n[① 겹침 실측] FQ-093 vr_speed ↔ 오늘 disp_trend: Pearson %.4f · Spearman %.4f\n",
  cor(E$vr_speed, E$disp_trend), cor(E$vr_speed, E$disp_trend, method="spearman")))
cat(sprintf("             vr_speed ↔ disp_speed(분산 속도): Spearman %.4f\n",
  cor(E$vr_speed, E$disp_speed, method="spearman", use="complete.obs")))

# ② 오늘 P9 의 경제 채점 그대로 적용
expq <- function(x,p,mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)],p,names=FALSE,na.rm=TRUE))
base_x <- xts(E$gross*E$invested - BPS*E$turn*E$invested, order.by=E$eval_date)
bt <- table.AnnualizedReturns(base_x, scale=12, Rf=0)
b_sr <- as.numeric(bt[3,1]); b_mdd <- as.numeric(maxDrawdown(base_x))*100
score <- function(v, lbl, hi=TRUE) {
  q <- expq(v, if (hi) 0.80 else 0.20)
  f <- if (hi) (is.finite(q) & v >= q) else (is.finite(q) & v <= q); f[is.na(f)] <- FALSE
  if (sum(f) < 5) return(NULL)
  tt <- t.test(E$gross[f], E$gross[!f])
  inv2 <- pmin(E$invested, ifelse(f, 0.50, 1))
  n2 <- E$gross*inv2 - BPS*E$turn*inv2; x2 <- xts(n2, order.by=E$eval_date)
  t2 <- table.AnnualizedReturns(x2, scale=12, Rf=0)
  data.table(신호=lbl, 발화=sum(f), 발화월평균=round(100*mean(E$gross[f]),2),
    미발화평균=round(100*mean(E$gross[!f]),2), t=round(as.numeric(tt$statistic),2), p=round(tt$p.value,4),
    dSR=round(as.numeric(t2[3,1])-b_sr,3), dMDD=round(as.numeric(maxDrawdown(x2))*100-b_mdd,2))
}
S <- rbindlist(Filter(Negate(is.null), list(
  score(E$vr_speed,   "FQ-093 vol rank 상승속도 ≥ q80"),
  score(E$disp_speed, "분산 속도 ≥ q80"),
  score(E$disp_trend, "[오늘 측정] disp_trend ≥ q80"))))
cat(sprintf("\n[② 경제 채점 — 기준선 SR %.3f · MDD %.2f%%]\n", b_sr, b_mdd)); print(S)
cat(sprintf("\n[사전 확인 판정] %s\n", ifelse(all(S$발화월평균 > S$미발화평균) | all(S$dSR <= 0),
  "★FQ-093 신호도 발화월 수익이 낮지 않음/dSR 음수 — 오늘 전수 측정한 계열과 동일 결론. 라운드 착수 EV 낮음",
  "일부 축이 다름 — 라운드 착수 검토")))
fwrite(S, "stage_artifacts/tilt_realign_20260808/p23_fq093_precheck.csv")
