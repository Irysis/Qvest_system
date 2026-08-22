## WT-D20260822_006 P1b — 상태변수 월간화 + PIT 컷오프 + 지속성 (MEAN-BLIND)
suppressPackageStartupMessages({library(data.table); library(arrow)})
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/config.R")
OUT <- "stage_artifacts/WT-D20260822_006"; W004 <- "stage_artifacts/WT-D20260822_004"
P0 <- readRDS(file.path(OUT,"p0_probe.rds")); agree <- P0$agree
months <- as.Date(names(P0$sel_rank))
cat("holding months:", length(months), format(min(months)), "~", format(max(months)), "\n")

## --- bear_prob 월간화: effective_date < 홀딩월 첫날 (locf) ---
sm <- as.data.table(read_parquet("outputs/ramp/smv_factor_regime_daily.parquet"))
sm[, Date := as.Date(Date)]
sm[, eff := as.Date(effective_date)]
## effective_date 결측(최근 2일)은 Date+2 영업일 근사 대신 제외 — 보수적
sm <- sm[is.finite(bear_prob) & !is.na(eff)]
setorder(sm, factor, eff)
bp <- rbindlist(lapply(months, function(m) {
  s <- sm[eff < m]
  if (!nrow(s)) return(data.table(Date=m, factor=NA_character_, bear_prob=NA_real_))
  s[, .SD[which.max(eff)], by=factor][, .(Date=m, factor, bear_prob)]
}))
cov <- bp[!is.na(bear_prob), .(n_fac=.N), by=Date]
cat("bear_prob 커버 월:", nrow(cov), "/", length(months), "  첫 커버월:", format(min(cov$Date)), "\n")
bpw <- dcast(bp[!is.na(bear_prob)], Date ~ factor, value.var="bear_prob")
bpw[, bp_mean := rowMeans(.SD, na.rm=TRUE), .SDcols=setdiff(names(bpw),"Date")]
cat(sprintf("bp_mean: 평균 %.4f sd %.4f AR1 %.4f  range [%.3f, %.3f]\n",
  mean(bpw$bp_mean), sd(bpw$bp_mean),
  cor(bpw$bp_mean[-1], bpw$bp_mean[-nrow(bpw)]), min(bpw$bp_mean), max(bpw$bp_mean)))

## --- 상태 A: 팩터 간 일치도 (성과 무관, 221개월 전체) ---
st <- copy(agree)[, .(Date, agree)]
st[, disagree := 1 - agree]
## 확장창 백분위 (PIT: t 까지의 정보만; agree_t 는 당월 z 횡단면 = C0 와 동일 vintage)
st[, s_pct := sapply(seq_len(.N), function(i) mean(disagree[1:i] <= disagree[i]))]
cat(sprintf("\nagree: 평균 %.4f sd %.4f AR1 %.4f | disagree AR1 %.4f | s_pct sd %.4f\n",
  mean(st$agree), sd(st$agree), cor(st$agree[-1], st$agree[-nrow(st)]),
  cor(st$disagree[-1], st$disagree[-nrow(st)]), sd(st$s_pct)))
cat(" s_pct 분위:", paste(sprintf("%.3f", quantile(st$s_pct, c(0,.25,.5,.75,1))), collapse=" / "), "\n")
cat(" ★확장창 warm-up: 첫 36개월 s_pct 는 표본 적음 — 사전등록에서 warm-up 처리 명시 필요\n")

## --- 상태 B(보조): 전월 횡단면 수익 분산 (lag1, PIT-safe) ---
disp <- copy(P0$disp)[, .(Date, disp)]
setorder(disp, Date); disp[, disp_lag1 := shift(disp, 1L)]
d2 <- disp[Date %in% months]
cat(sprintf("\ndisp_lag1: n_valid %d AR1 %.4f\n", sum(is.finite(d2$disp_lag1)),
  cor(d2$disp_lag1[-1], d2$disp_lag1[-nrow(d2)], use="complete.obs")))

STATE <- merge(st, bpw[, .(Date, bp_mean)], by="Date", all.x=TRUE)
STATE <- merge(STATE, d2[, .(Date, disp_lag1)], by="Date", all.x=TRUE)
cat("\ncor(s_pct, bp_mean) =", sprintf("%.4f", cor(STATE$s_pct, STATE$bp_mean, use="complete.obs")), "\n")
cat("cor(s_pct, disp_lag1) =", sprintf("%.4f", cor(STATE$s_pct, STATE$disp_lag1, use="complete.obs")), "\n")
saveRDS(STATE, file.path(OUT,"p1b_state.rds"))
cat("\n[saved] p1b_state.rds\nOK\n")
