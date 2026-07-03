## run_ramp_gate6_m0.R — RAMP Gate 6 첫 단계: M0 baseline (11 직교군 EW 합성)
## M0 score = 11 group composite z 평균 → top-25 long-only net 15bps → canonical_screen_bt 실측.
## 비교: BM(KOSPI200 TR) / 최고 개별군 / (참고)STR_1715 admit SR.
## 명제 시험: 약한 직교군 조합이 개별군보다 net 우월한가? 단일스레드·실측-only.
suppressPackageStartupMessages({library(data.table); library(arrow)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source(file.path(QM,"02_Infrastructure/config.R"))
source("02_Infrastructure/ramp/factor_validation.R")  # validate_factor, build_monthly_forward_returns, %||%
con <- file(".cache/_gate6_m0.txt","w",encoding="UTF-8"); w<-function(...)writeLines(paste0(...),con)

# 11 group composite signals
g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet"))
g[, signal_date := as.Date(signal_date)]
groups <- sort(unique(g$family))
w(sprintf("group 입력: %d군 (%s)", length(groups), paste(groups,collapse=",")))

# M0 = EW: (date×ticker)별 group_z 평균 → 월별 재표준화
m0 <- g[, .(score = mean(group_z, na.rm=TRUE), n_grp = uniqueN(family)), by=.(signal_date, security_id)]
m0 <- m0[n_grp >= 6]   # 최소 6군 커버 종목만 (희소 제거)
m0[, score := { mu<-mean(score,na.rm=T); s<-sd(score,na.rm=T); if(is.na(s)||s<1e-9) score-mu else (score-mu)/s }, by=signal_date]

# 검증 인프라
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet")); rawdata[,Date:=as.Date(Date)]
sig_dates <- sort(unique(m0$signal_date))
fwd <- build_monthly_forward_returns(rawdata, sig_dates)

# M0 top-25 long-only net
m0_in <- m0[, .(signal_date, security_id, factor_id="M0_EW11", neutralized_z=score)]
v0 <- validate_factor(m0_in, fwd, top_n=25L, cost_bps=15)
w("")
w("=== M0 (11군 EW, top-25 long-only net 15bps) ===")
w(sprintf("  n_months=%d | net_sr=%+.3f | port_alpha_t=%+.2f | IR=%+.2f | rank_ic_ir=%+.3f | TO_ann=%.2f",
  v0$n_months, v0$net_sr %||% NA, v0$portfolio_alpha_t_nw %||% NA, v0$information_ratio %||% NA,
  v0$rank_ic_ir %||% NA, v0$turnover_annual %||% NA))

# 비교: 최고 개별군 (정제 결과 metrics)
cm <- tryCatch(readRDS(".cache/_consolidation.rds")$metrics, error=function(e) NULL)
if(!is.null(cm)){
  best <- cm[which.max(port_t)]
  w("")
  w("=== 비교 ===")
  w(sprintf("  최고 개별군: %s net_sr=%+.3f port_t=%+.2f", best$group, best$net_sr, best$port_t))
  w(sprintf("  11군 평균 개별 net_sr: %+.3f", mean(cm$net_sr,na.rm=T)))
  w(sprintf("  M0 조합:    net_sr=%+.3f port_t=%+.2f", v0$net_sr %||% NA, v0$portfolio_alpha_t_nw %||% NA))
  d_sr <- (v0$net_sr %||% NA) - best$net_sr
  w(sprintf("  → M0 − 최고개별군 net_sr Δ = %+.3f (%s)", d_sr, ifelse(!is.na(d_sr)&&d_sr>0,"조합 우월 ✓","조합 미달")))
}
w("  (참고) STR_1715 admit SR 1.76 = Core+Defense 블렌드+오버레이. M0는 오버레이 전 raw 합성.")

w("")
w("[Gate6 M0] 약한 직교군 EW 조합 baseline 산출. 다음=M1~4 국면조건부 + 오버레이.")
saveRDS(list(m0_metrics=v0, m0_scores=m0), ".cache/_gate6_m0.rds")
close(con); cat("M0_DONE\n")
