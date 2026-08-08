# run_fq139_v2.R — FQ-139 (월간 패널 정합판)
# panelx_A 는 (ym, Ticker) **월간** 계약 집계다: n_contracts, amt_sum, ratio_rev_sum, w_amt, w_ratio …
# 시험: 계약신호 상위분위 종목이, 신호월 **다음 1~3개월**에 기관 순매수를 하위분위보다 유의하게 더 받는가.
#   받지 않으면 mechanism.path('기관 후속 매수로 가격 반영') 기각 → 국면 의존 재서술 필요.
# ★PIT: 분위는 **신호월 내 횡단면**으로만(같은 달 정보), 관측 창은 신호월 **이후**.
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/fq139_mechanism_falsification"

P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))
cat(sprintf("[panelx_A] %d행 | ym %s~%s | 종목 %d | scope=%s | metric_type=%s | window_m=%s\n",
  nrow(P), min(P$ym), max(P$ym), uniqueN(P$Ticker),
  paste(unique(P$scope), collapse=","), paste(unique(P$metric_type), collapse=","),
  paste(unique(P$window_m), collapse=",")))
print(P[, .(n_contracts=sum(n_contracts, na.rm=TRUE)), by=ym][order(ym)][c(1:3, .N-2:0)])

IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Institutional","Foreign")))
IV[, Date := as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
raw[, Date := as.Date(Date)]; raw[, TV := Close*Vol]
IV <- merge(IV, raw[, .(Date, Ticker, TV)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y-%m")]
MF <- IV[, .(inst = sum(Institutional, na.rm=TRUE), forg = sum(Foreign, na.rm=TRUE),
             tv = sum(TV, na.rm=TRUE)), by=.(Ticker, ym)]
MF[, `:=`(inst_n = inst/pmax(tv,1), forg_n = forg/pmax(tv,1))]
MF[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
setkey(MF, Ticker, mi)
cat(sprintf("[월간 투자자] %s행 | %s ~ %s\n", format(nrow(MF), big.mark=","), min(MF$ym), max(MF$ym)))

E <- P[is.finite(ratio_rev_sum) | is.finite(w_amt)]
E[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
for (h in 1:3) {
  a <- MF[, .(Ticker, mi, inst_n, forg_n)]; a[, mi := mi - h]
  setnames(a, c("inst_n","forg_n"), paste0(c("i","f"), h))
  E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE)
}
E[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("i1","i2","i3")]
E[, `:=`(inst_3m = rowSums(.SD, na.rm=TRUE)), .SDcols=c("i1","i2","i3")]
E[, forg_3m := rowSums(.SD, na.rm=TRUE), .SDcols=c("f1","f2","f3")]
E <- E[n_ok == 3L]
cat(sprintf("[t+1~t+3 완비] %d건 (%d 종목 · %d 개월)\n", nrow(E), uniqueN(E$Ticker), uniqueN(E$ym)))

run_one <- function(sig, lab) {
  D <- E[is.finite(get(sig))]
  D[, q := cut(frank(get(sig), ties.method="average")/.N, c(0,0.2,0.8,1), labels=c("하위20","중간","상위20")), by=ym]
  D <- D[!is.na(q)]
  S <- D[, .(n=.N, inst_3m_mean=round(mean(inst_3m),5), inst_3m_med=round(median(inst_3m),5),
             forg_3m_mean=round(mean(forg_3m),5)), by=q][order(q)]
  cat(sprintf("\n===== 신호 = %s (%s) =====\n", sig, lab)); print(S)
  hi <- D[q=="상위20", inst_3m]; lo <- D[q=="하위20", inst_3m]
  if (length(hi) < 20 || length(lo) < 20) { cat("  표본 부족 — 판정 보류\n"); return(NULL) }
  tt <- t.test(hi, lo); wt <- suppressWarnings(wilcox.test(hi, lo))
  hf <- D[q=="상위20", forg_3m]; lf <- D[q=="하위20", forg_3m]; tf <- t.test(hf, lf)
  cat(sprintf("  [기관] 상위 %+.5f vs 하위 %+.5f | 차이 %+.5f | t=%.3f p=%.4f | Wilcoxon p=%.4f\n",
      mean(hi), mean(lo), mean(hi)-mean(lo), tt$statistic, tt$p.value, wt$p.value))
  cat(sprintf("  [외국인 대조] 차이 %+.5f | t=%.3f p=%.4f\n", mean(hf)-mean(lf), tf$statistic, tf$p.value))
  cat(sprintf("  → mechanism.path: %s\n",
      ifelse(tt$p.value < 0.05 && mean(hi) > mean(lo), "지지", "★기각(유의 증가 없음)")))
  data.table(signal=sig, n_hi=length(hi), n_lo=length(lo), diff=mean(hi)-mean(lo),
             t=as.numeric(tt$statistic), p=tt$p.value, p_wilcox=wt$p.value,
             verdict=ifelse(tt$p.value<0.05 && mean(hi)>mean(lo), "지지","기각"))
}
res <- rbindlist(Filter(Negate(is.null), list(
  run_one("ratio_rev_sum", "계약금액/매출 비율"), run_one("w_amt", "가중 계약금액"),
  run_one("amt_sum", "계약금액 합"), run_one("n_contracts", "계약 건수"))))
cat("\n===== 종합 =====\n"); print(res)
fwrite(res, file.path(OUT, "fq139_verdicts.csv"))
