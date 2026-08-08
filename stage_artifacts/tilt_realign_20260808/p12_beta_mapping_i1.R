# p12_beta_mapping_i1.R — I1: β 매핑 재설계 (이산 2×2 표 → 연속 f(z))
# ★1단계 = 현행 매핑 재현 검증. 재현 못 하면 대안 arm 이 기준 없이 뜬다(오늘 반복 교훈).
#   현행: β_R05_V5 = CRISIS&z<q20 0.30 / CRISIS 0.50 / CAUTION&z<q20 0.50 / CAUTION 0.70 /
#                    BULL·NORMAL&z<q20 0.85 / else 1.00,  invested = gate × β_R05
# 2단계 = 재현되면 연속 매핑 sweep. selection_type=sweep → DSR 대상(본 산출은 곡선 보고).
suppressMessages({ library(data.table); library(arrow); library(dplyr); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/factor_db/factor_db_connector.R")
BPS <- 0.0015

R <- fread("stage_artifacts/tilt_realign_20260808/arm_ab_monthly_269m.csv")
R[, `:=`(eval_date=as.Date(eval_date), decision_date=as.Date(decision_date))]
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
E <- merge(R[, .(decision_date, eval_date, regime, gross=gA, turn=tA)],
           unique(car[, .(decision_date, invested)]), by="decision_date")
setorder(E, decision_date)
hold <- car[, .(decision_date, Ticker)]
reg <- .load_registry()

## --- R05 보유종목 평균 z (C15 정본 경로) ---
z <- rbindlist(lapply(seq_len(nrow(E)), function(i) {
  dd <- E$decision_date[i]
  f <- tryCatch(load_month_factors(dd, factor_names="R05_Tail_Risk"), error=function(e) NULL)
  if (is.null(f) || !nrow(f)) return(NULL)
  f <- as.data.table(f)
  if (!("Z_Score" %in% names(f)) && "Z_Score_Aligned" %in% names(f)) setnames(f,"Z_Score_Aligned","Z_Score")
  if (!("Z_Score" %in% names(f))) return(NULL)
  if ("Coverage" %in% names(f)) f <- f[Coverage == TRUE]
  f <- f[is.finite(Z_Score)]; if (!nrow(f)) return(NULL)
  fa <- as.data.table(tryCatch(align_factor_direction(copy(f)[, sig_date := dd], reg, sig_date=dd, min_ic_months=12L),
                               error=function(e) copy(f)))
  zc <- if ("Z_Score_Aligned" %in% names(fa)) "Z_Score_Aligned" else "Z_Score"
  hk <- hold[decision_date==dd, Ticker]
  data.table(decision_date=dd, z_port=mean(fa[[zc]][fa$Ticker %in% hk], na.rm=TRUE))
}), fill=TRUE)
E <- merge(E, z, by="decision_date", all.x=TRUE); setorder(E, decision_date)
cat(sprintf("[z] 산출 %d/%d개월\n", sum(is.finite(E$z_port)), nrow(E)))

## --- 1단계: 현행 매핑 재현 ---
E[, q20 := sapply(seq_len(.N), function(i) if (i<=36L) NA_real_ else quantile(z_port[1:(i-1)],0.20,names=FALSE,na.rm=TRUE))]
E[, zlt := is.finite(q20) & is.finite(z_port) & z_port < q20]
E[, beta_hat := fcase(regime=="CRISIS" & zlt, 0.30, regime=="CRISIS", 0.50,
                      regime=="CAUTION" & zlt, 0.50, regime=="CAUTION", 0.70,
                      regime %in% c("BULL","NORMAL") & zlt, 0.85, default=1.00)]
V <- E[is.finite(q20)]
cat(sprintf("\n[재현 검증] %d개월 | invested==beta_hat 일치 %.1f%% | max|diff| %.4f | cor %.4f\n",
            nrow(V), 100*mean(abs(V$invested - V$beta_hat) < 1e-6), max(abs(V$invested - V$beta_hat)),
            suppressWarnings(cor(V$invested, V$beta_hat))))
cat("[불일치 상위]\n")
print(V[abs(invested-beta_hat) > 1e-6][order(-abs(invested-beta_hat))][1:6,
        .(ym=format(eval_date,"%Y-%m"), regime, z=round(z_port,3), zlt, actual=round(invested,3), recon=round(beta_hat,3))])

mk <- function(inv, lbl) {
  net <- V$gross*inv - BPS*V$turn*inv
  x <- xts(net, order.by=V$eval_date); t <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, 평균노출=round(mean(inv),3), SR=round(as.numeric(t[3,1]),3),
             CAGR=round(as.numeric(t[1,1])*100,2), MDD=round(as.numeric(maxDrawdown(x))*100,2),
             Calmar=round(as.numeric(t[1,1])/pmax(as.numeric(maxDrawdown(x)),1e-9),3))
}
## --- 2단계: 연속 매핑 sweep — 라벨 base 위에 z-percentile 연속 조정 ---
V[, base := fcase(regime=="CRISIS",0.50, regime=="CAUTION",0.70, default=1.00)]
V[, zpct := sapply(seq_len(.N), function(i) if (i<=36L) NA_real_ else mean(z_port[1:(i-1)] < z_port[i], na.rm=TRUE))]
V[!is.finite(zpct), zpct := 0.5]
arms <- list(mk(V$invested, "A. 현행 (이산 2×2)"), mk(V$base, "B. 라벨만 (z 미사용)"))
for (k in c(0.2, 0.4, 0.6)) {
  # 연속: z 가 낮을수록(위험 高) β 축소. 하위 20%p 당 k 비율 축소, 하한 0.30
  inv <- pmax(0.30, V$base * (1 - k * pmax(0, 0.5 - V$zpct) * 2))
  arms[[length(arms)+1L]] <- mk(inv, sprintf("C. 연속 f(z) k=%.1f", k))
}
out <- rbindlist(arms); setorder(out, MDD)
cat("\n===== β 매핑 arm (sweep, n_trials=5 → 채택 시 DSR 대상) =====\n"); print(out)
fwrite(out, "stage_artifacts/tilt_realign_20260808/p12_beta_mapping.csv")
fwrite(V[, .(eval_date, regime, z_port, zlt, invested, beta_hat)],
       "stage_artifacts/tilt_realign_20260808/p12_beta_recon_detail.csv")
