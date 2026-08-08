# run_f1_tieaware.R — F1: 분위 형성 실패 수리 후 4신호 재확인
# FQ-139 판정이 w_amt 단일 신호 위에 서 있었다. 나머지 3신호는 값 동률(0 등) 때문에 하위20 이
# 형성되지 않았다 — 분위 함수가 조용히 한 칸을 비우고 그게 '표본 부족'으로만 보고됐다.
# 수리: ①분포부터 보고 ②동률-인지 분할(상위20 vs 나머지 · 중앙값 분할 · 0초과 vs 0)로 재시험.
#      ★단일 분할에 의존하지 않고 3종 분할 전부에서 부호가 유지되는지 확인 = 강건성 시험
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/fq139_mechanism_falsification"

P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Institutional","Foreign")))
IV[, Date := as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
raw[, Date := as.Date(Date)]; raw[, TV := Close*Vol]
IV <- merge(IV, raw[, .(Date, Ticker, TV)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y-%m")]
MF <- IV[, .(inst=sum(Institutional,na.rm=TRUE), forg=sum(Foreign,na.rm=TRUE), tv=sum(TV,na.rm=TRUE)), by=.(Ticker, ym)]
MF[, `:=`(inst_n=inst/pmax(tv,1), forg_n=forg/pmax(tv,1),
          mi=as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7)))]
E <- copy(P); E[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
for (h in 1:3) { a <- MF[, .(Ticker, mi, inst_n, forg_n)]; a[, mi := mi-h]
  setnames(a, c("inst_n","forg_n"), paste0(c("i","f"), h)); E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE) }
E[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("i1","i2","i3")]
E[, inst_3m := rowSums(.SD, na.rm=TRUE), .SDcols=c("i1","i2","i3")]
E[, forg_3m := rowSums(.SD, na.rm=TRUE), .SDcols=c("f1","f2","f3")]
E <- E[n_ok == 3L]
cat(sprintf("[표본] %d건 · %d종목 · %d개월\n", nrow(E), uniqueN(E$Ticker), uniqueN(E$ym)))

SIGS <- c("ratio_rev_sum","w_amt","amt_sum","n_contracts")
cat("\n===== 신호 분포 (분위 형성 실패 원인 확인) =====\n")
for (s in SIGS) {
  v <- E[[s]]; v <- v[is.finite(v)]
  cat(sprintf("  %-14s n=%d | 0값 %.1f%% | 최빈값 비중 %.1f%% | q20=%.4g q50=%.4g q80=%.4g\n",
      s, length(v), 100*mean(v==0), 100*max(table(v))/length(v),
      quantile(v,0.2,names=FALSE), quantile(v,0.5,names=FALSE), quantile(v,0.8,names=FALSE)))
}

tst <- function(hi, lo, lab, s, split) {
  if (length(hi) < 20 || length(lo) < 20) return(NULL)
  tt <- t.test(hi$inst_3m, lo$inst_3m); tf <- t.test(hi$forg_3m, lo$forg_3m)
  data.table(signal=s, 분할=split, n_hi=nrow(hi), n_lo=nrow(lo),
    기관차이=round(mean(hi$inst_3m)-mean(lo$inst_3m),5), 기관t=round(as.numeric(tt$statistic),2), 기관p=round(tt$p.value,4),
    외국인차이=round(mean(hi$forg_3m)-mean(lo$forg_3m),5), 외국인t=round(as.numeric(tf$statistic),2), 외국인p=round(tf$p.value,4))
}
res <- list()
for (s in SIGS) {
  D <- E[is.finite(get(s))]
  # ① 상위20 vs 나머지 (동률 무관)
  D[, r := frank(get(s), ties.method="average")/.N, by=ym]
  res[[length(res)+1L]] <- tst(D[r > 0.8], D[r <= 0.8], "", s, "상위20 vs 나머지")
  # ② 중앙값 분할
  res[[length(res)+1L]] <- tst(D[r > 0.5], D[r <= 0.5], "", s, "중앙값 분할")
  # ③ 0 초과 vs 0 (해당 신호에 0 이 있을 때만)
  if (any(D[[s]] == 0)) res[[length(res)+1L]] <- tst(D[get(s) > 0], D[get(s) == 0], "", s, "0초과 vs 0")
}
R <- rbindlist(Filter(Negate(is.null), res))
cat("\n===== 3종 분할 × 4신호 =====\n"); print(R)
cat(sprintf("\n[부호 일관성] 기관 차이 음수 %d/%d · 외국인 차이 양수 %d/%d\n",
    sum(R$기관차이 < 0), nrow(R), sum(R$외국인차이 > 0), nrow(R)))
cat(sprintf("[유의 건수] 기관 p<0.05 %d건 · 외국인 p<0.05 %d건\n", sum(R$기관p<0.05), sum(R$외국인p<0.05)))
cat(sprintf("\n[F1 판정] %s\n", ifelse(mean(R$기관차이<0) >= 0.75 && mean(R$외국인차이>0) >= 0.75,
  "FQ-139 결론 유지 — 기관 음수·외국인 양수 부호가 분할·신호 전반에서 일관",
  "★부호 불일관 — w_amt 특이성 가능성, 재분류 필요")))
fwrite(R, file.path(OUT, "f1_tieaware_verdicts.csv"))
