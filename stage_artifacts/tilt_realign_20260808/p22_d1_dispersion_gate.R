# p22_d1_dispersion_gate.R — D1/I4: 횡단면 분산을 'de-risk 억제 게이트'로 소비 (overlay 계열 마지막 probe)
# 근거: P9 에서 `횡단면분산 ≥ q80` 발화월의 평균 sleeve 수익이 **+8.08% 로 전 그룹 최고**였다
#   (위험 신호가 아니라 종목선택 기회 신호). 그렇다면 분산이 높은 달엔 β 축소를 **보류**하는 게
#   맞을 수 있다 — 위험 신호를 하나 더 얹는 게 아니라 기존 축소를 *억제*하는 형태.
# ★PIT: 분산은 decision_date 이전 20거래일만. 문턱은 expanding(past-only) q80.
# ★제약: MDD < 25% 상한 (K1 규약). selection_type=sweep.
suppressMessages({ library(data.table); library(arrow); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
BPS <- 0.0015; MDD_CAP <- 25.0
M <- fread("stage_artifacts/tilt_realign_20260808/p16_j1_close.csv"); M[, decision_date := as.Date(decision_date)]
R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(decision_date=as.Date(decision_date), eval_date=as.Date(eval_date))]
D <- merge(M[, .(decision_date, regime, beta_R05, m4)], R[, .(decision_date, eval_date, gross=gA, turn=tA)], by="decision_date")
setorder(D, decision_date)
D[, base_beta := fcase(regime=="CRISIS",0.50, regime=="CAUTION",0.70, default=1.00)]

raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Ret")))
raw[, Date := as.Date(Date)]; raw <- raw[is.finite(Ret) & Ret > -0.95 & Ret < 1.0]
DA <- raw[, .(disp = sd(Ret, na.rm=TRUE), n=.N), by=Date][n >= 100][order(Date)]
D[, disp20 := sapply(decision_date, function(dd) { h <- DA[Date < dd]; if (nrow(h) < 20) NA_real_ else mean(tail(h,20)$disp) })]
expq <- function(x,p,mn=36L) sapply(seq_along(x), function(i) if (i<=mn) NA_real_ else quantile(x[1:(i-1)],p,names=FALSE,na.rm=TRUE))
D[, q80 := expq(disp20, 0.80)]
D[, hi_disp := is.finite(q80) & is.finite(disp20) & disp20 >= q80]
cat(sprintf("[분산 게이트] 발화 %d개월 (%.1f%%) | 그중 β 축소중이던 달 %d\n",
  sum(D$hi_disp), 100*mean(D$hi_disp), sum(D$hi_disp & D$beta_R05*D$m4 < 0.999)))

mk <- function(inv, lbl) { inv <- pmin(pmax(inv,0),1)
  net <- D$gross*inv - BPS*D$turn*inv
  x <- xts(net, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, 평균노출=round(mean(inv),3), SR=round(as.numeric(t[3,1]),3),
    CAGR=round(as.numeric(t[1,1])*100,2), MDD=round(as.numeric(maxDrawdown(x))*100,2),
    Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3)) }
cur <- D$beta_R05 * D$m4
# 억제 3형태: ①완전 억제(β→base) ②부분(중간값) ③m4 만 억제
sup_full <- ifelse(D$hi_disp, D$base_beta, D$beta_R05) * D$m4
sup_half <- ifelse(D$hi_disp, (D$beta_R05 + D$base_beta)/2, D$beta_R05) * D$m4
sup_m4   <- D$beta_R05 * ifelse(D$hi_disp, 1, D$m4)
# K1 최선(B: m4 제거) 위에 얹은 형태
b_nom4   <- D$beta_R05
sup_on_b <- ifelse(D$hi_disp, D$base_beta, D$beta_R05)
arms <- rbindlist(list(
  mk(cur,      "A. 현행"),
  mk(sup_full, "F1. 분산高 → β 완전 억제"),
  mk(sup_half, "F2. 분산高 → β 절반 억제"),
  mk(sup_m4,   "F3. 분산高 → m4 만 억제"),
  mk(b_nom4,   "B. m4 제거 (K1 최선)"),
  mk(sup_on_b, "G. m4 제거 + 분산高 억제")))
arms[, 제약 := ifelse(MDD < MDD_CAP, "O", "X")]
setorder(arms, -CAGR)
cat(sprintf("\n===== 분산 억제 게이트 (MDD 상한 %.0f%%) =====\n", MDD_CAP)); print(arms)
a0 <- arms[arm=="A. 현행"]; ok <- arms[제약=="O"]; best <- ok[which.max(CAGR)]
cat(sprintf("\n[현행] CAGR %.2f%% · MDD %.2f%% · Calmar %.3f\n", a0$CAGR, a0$MDD, a0$Calmar))
cat(sprintf("[제약 안 최선] %s → CAGR %.2f%% (%+.2f) · MDD %.2f%% · Calmar %.3f (%+.3f)\n",
  best$arm, best$CAGR, best$CAGR-a0$CAGR, best$MDD, best$Calmar, best$Calmar-a0$Calmar))
nb <- D$gross*sup_on_b - BPS*D$turn*sup_on_b; nB <- D$gross*b_nom4 - BPS*D$turn*b_nom4
tt <- t.test(nb - nB)
cat(sprintf("[paired G vs B] %+.4f%%/월 · t=%.2f · p=%.4f → 분산 억제가 m4 제거 위에 %s\n",
  mean(nb-nB)*100, tt$statistic, tt$p.value, ifelse(tt$p.value<0.05 && mean(nb-nB)>0, "추가 기여", "추가 기여 없음")))
fwrite(arms, "stage_artifacts/tilt_realign_20260808/p22_d1_dispersion_gate.csv")
