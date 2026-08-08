# run_02_frozen_panel_anomaly.R — 동결 패널의 성격·이상 구간 특정
# run_01 발견: ①대부분의 달에서 동결 z 와 live z 의 **rank 상관이 0.9999+** (Pearson 만 0.57~0.97)
#   → '다른 지표'가 아니라 **같은 신호를 다른 횡단면에서 z-표준화**한 것(n_frozen 349 vs n_live 2400+).
#   ②그런데 **2026-06-01 만 n_frozen 2529 로 급증하고 rank 상관이 −0.689** — 마지막 달이 이질적.
# 이 스크립트: 동결 패널의 월별 행수·분포를 훑어 이상 구간이 언제부터인지, 성격이 무엇인지 특정.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/beta_z_source_20260808"

f <- as.data.table(read_parquet("stage_artifacts/WT_D20260512_003/alpha_scores_new.parquet"))
f[, Date := as.Date(Date)]
cat(sprintf("[패널] %s행 | 컬럼: %s\n", format(nrow(f), big.mark=","), paste(names(f), collapse=", ")))
S <- f[, .(n_row = .N,
           n_z = sum(is.finite(R05_Tail_Risk_Z)),
           mean_z = round(mean(R05_Tail_Risk_Z, na.rm=TRUE), 4),
           sd_z = round(sd(R05_Tail_Risk_Z, na.rm=TRUE), 4),
           min_z = round(min(R05_Tail_Risk_Z, na.rm=TRUE), 3),
           max_z = round(max(R05_Tail_Risk_Z, na.rm=TRUE), 3)), by=Date][order(Date)]
cat("\n[월별 행수 — 처음 3 / 마지막 8]\n"); print(rbind(head(S,3), tail(S,8)))
cat(sprintf("\n[행수 분포] 중앙 %d | 최소 %d(%s) | 최대 %d(%s)\n",
  median(S$n_row), min(S$n_row), as.character(S[which.min(n_row)]$Date),
  max(S$n_row), as.character(S[which.max(n_row)]$Date)))
big <- S[n_row > 3*median(S$n_row)]
cat(sprintf("[급증 구간] 중앙의 3배 초과인 달 %d개: %s\n", nrow(big),
            if (nrow(big)) paste(as.character(big$Date), collapse=", ") else "없음"))

## z 분포 이상: sd 나 평균이 튀는 달
S[, z_flag := abs(mean_z - median(S$mean_z)) > 3*mad(S$mean_z) | abs(sd_z - median(S$sd_z)) > 3*mad(S$sd_z)]
cat(sprintf("[z 분포 이상월] %d개: %s\n", sum(S$z_flag, na.rm=TRUE),
            paste(as.character(S[z_flag == TRUE]$Date), collapse=", ")))

## 마지막 달이 실제 β 계산에 쓰였는가 — top20 평균 z 로 확인
P <- fread("stage_artifacts/tilt_realign_20260808/p20_flag_spec_panel.csv"); P[, Date := as.Date(Date)]
cat("\n[β 계산에 들어간 마지막 6개월 z]\n")
print(merge(P[, .(Date, regime, z_top20 = round(z,4), q20 = round(q20,4), beta_spec, n_valid)],
            S[, .(Date, n_row, sd_z)], by="Date", all.x=TRUE)[order(-Date)][1:6])
cat(sprintf("\n[해석] 동결 패널 종점 %s. 그 달의 행수/분포가 다른 달과 다르면 마지막 β 도 오염 후보다.\n",
            as.character(max(S$Date))))
fwrite(S, file.path(OUT, "frozen_panel_monthly.csv"))
