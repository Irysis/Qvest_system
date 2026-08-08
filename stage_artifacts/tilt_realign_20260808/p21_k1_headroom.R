# p21_k1_headroom.R — K1: MDD 제약이 '상한'이라는 점을 이용해 여유를 CAGR 로 전환할 수 있는가
# 문제 설정 정정: 나는 세션 내내 MDD 를 *낮추는* 방향만 쟀다(I1 flag 심화). 그러나 목표는
#   MDD < 25% 라는 **상한**이고 현행은 23.27% — 여유 1.73%pt 가 있다. 상한 안에서 CAGR 최대화가
#   목표 정합적 질문이다.
# 재료: K2 에서 m4 제거가 MDD 불변(23.27%)인데 CAGR +1.69%pt 임이 확인됐다 = **여유를 안 쓰고 얻는 이득**.
#   여기에 flag 완화를 더해 상한 안에서 어디까지 갈 수 있는지 메뉴를 만든다.
# ★selection_type=sweep — 채택 시 DSR + holdout 사전등록. 본 산출은 제약-안 메뉴 보고.
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
D[, flag := beta_R05 < base_beta - 1e-9]

mk <- function(inv, lbl) {
  inv <- pmin(pmax(inv, 0), 1)
  net <- D$gross*inv - BPS*D$turn*inv
  x <- xts(net, order.by=D$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, 평균노출=round(mean(inv),3), SR=round(as.numeric(t[3,1]),3),
             CAGR=round(as.numeric(t[1,1])*100,2), MDD=round(as.numeric(maxDrawdown(x))*100,2),
             Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3))
}
# flag 완화: 발화월의 β 를 base 쪽으로 d 만큼 되돌림 (d=0 현행, d=full 무시)
relax <- function(d, use_m4) {
  b <- D$beta_R05 + ifelse(D$flag, pmin(d, D$base_beta - D$beta_R05), 0)
  b * (if (use_m4) D$m4 else 1)
}
arms <- rbindlist(list(
  mk(D$beta_R05 * D$m4, "A. 현행 (flag + m4)"),
  mk(relax(0.00, FALSE), "B. m4 제거만 (flag 유지)"),
  mk(relax(0.05, FALSE), "C1. m4 제거 + flag 완화 0.05"),
  mk(relax(0.10, FALSE), "C2. m4 제거 + flag 완화 0.10"),
  mk(relax(0.15, FALSE), "C3. m4 제거 + flag 완화 0.15"),
  mk(relax(9.99, FALSE), "D. m4 제거 + flag 무시"),
  mk(relax(0.10, TRUE),  "E. m4 유지 + flag 완화 0.10")))
arms[, `제약충족` := ifelse(MDD < MDD_CAP, "O", "X")]
setorder(arms, -CAGR)
cat(sprintf("===== 제약-안 메뉴 (MDD 상한 %.0f%%) =====\n", MDD_CAP)); print(arms)
base <- arms[arm == "A. 현행 (flag + m4)"]
ok <- arms[제약충족 == "O"]
best <- ok[which.max(CAGR)]
cat(sprintf("\n[현행] CAGR %.2f%% · MDD %.2f%% (여유 %.2f%%pt) · Calmar %.3f\n",
            base$CAGR, base$MDD, MDD_CAP - base$MDD, base$Calmar))
cat(sprintf("[제약 안 최대 CAGR] %s → CAGR %.2f%% (%+.2f%%pt) · MDD %.2f%% (여유 %.2f%%pt) · Calmar %.3f (%+.3f)\n",
            best$arm, best$CAGR, best$CAGR-base$CAGR, best$MDD, MDD_CAP-best$MDD, best$Calmar, best$Calmar-base$Calmar))
cat(sprintf("[제약 위반 arm] %d개 — %s\n", sum(arms$제약충족=="X"),
            ifelse(any(arms$제약충족=="X"), paste(arms[제약충족=="X", arm], collapse=" · "), "없음")))
# paired 유의성 (최선 vs 현행)
inv_b <- switch(sub("\\..*","",best$arm), "A"=D$beta_R05*D$m4, "B"=relax(0,FALSE),
  "C1"=relax(0.05,FALSE), "C2"=relax(0.10,FALSE), "C3"=relax(0.15,FALSE), "D"=relax(9.99,FALSE), "E"=relax(0.10,TRUE))
nb <- D$gross*inv_b - BPS*D$turn*inv_b; na_ <- D$gross*(D$beta_R05*D$m4) - BPS*D$turn*(D$beta_R05*D$m4)
tt <- t.test(nb - na_)
cat(sprintf("[paired 최선 vs 현행] %+.4f%%/월 · t=%.2f · p=%.4f\n", mean(nb-na_)*100, tt$statistic, tt$p.value))
fwrite(arms, "stage_artifacts/tilt_realign_20260808/p21_k1_headroom.csv")
