# run_f3_normalization.R — F3: '계약→외국인 매수' 결론이 정규화 선택의 산물인가
# 나는 이 결론을 "즉시 소비 가능한 확정 산출"로 상신했다. 그렇다면 통제가 필요하다:
#   순매수를 **거래대금(TV)** 으로 정규화했는데, 다른 축(시총·원화 절대액·거래대금 로그)에서도
#   부호와 유의성이 유지되는가. 유지되면 정규화 아티팩트가 아니다.
# ★단일 정규화 위의 결론에 무게를 싣지 않는다는 오늘의 규율(F1 이 단일 분할 과장을 정정한 것과 같은 축).
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FQ <- "04_Research/method_frontier/fq002_contract_magnitude"
OUT <- "stage_artifacts/fq139_mechanism_falsification"

P <- as.data.table(read_parquet(file.path(FQ,"panelx_A.parquet")))
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Foreign","Institutional")))
IV[, Date := as.Date(Date)]
rw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Size")))
rw[, Date := as.Date(Date)]; rw[, TV := Close*Vol]
IV <- merge(IV, rw[, .(Date,Ticker,TV,Size)], by=c("Date","Ticker"), all.x=TRUE)
IV[, ym := format(Date, "%Y%m")]
MF <- IV[, .(forg = sum(Foreign, na.rm=TRUE), inst = sum(Institutional, na.rm=TRUE),
             tv = sum(TV, na.rm=TRUE), size = median(Size, na.rm=TRUE)), by=.(Ticker, ym)]
MF <- MF[is.finite(tv) & tv > 0]
# 정규화 4종
MF[, `:=`(n_tv    = forg / tv,                              # 기존: 거래대금
          n_size  = forg / pmax(size, 1),                    # 시총
          n_raw   = forg / 1e8,                              # 원화 절대액(억원)
          n_logtv = forg / pmax(log1p(tv), 1e-9) / 1e8)]     # 로그-거래대금
MF[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
E <- copy(P); E[, mi := as.integer(substr(ym,1,4))*12L + as.integer(substr(ym,6,7))]
cols <- c("n_tv","n_size","n_raw","n_logtv")
for (h in 1:3) {
  a <- MF[, c("Ticker","mi",cols), with=FALSE]; a[, mi := mi - h]
  setnames(a, cols, paste0(cols, "_", h)); E <- merge(E, a, by=c("Ticker","mi"), all.x=TRUE)
}
res <- list()
for (cc in cols) {
  k <- paste0(cc, "_", 1:3)
  E[, ok := rowSums(!is.na(.SD)), .SDcols=k]
  E[, val := rowSums(.SD, na.rm=TRUE), .SDcols=k]
  S <- E[ok == 3L & is.finite(val)]
  S[, has_contract := amt_sum > 0]
  hi <- S[has_contract==TRUE, val]; lo <- S[has_contract==FALSE, val]
  if (length(hi) < 20 || length(lo) < 20) next
  tt <- t.test(hi, lo); wt <- suppressWarnings(wilcox.test(hi, lo))
  res[[length(res)+1L]] <- data.table(정규화=cc, n_계약=length(hi), n_무계약=length(lo),
    차이=signif(mean(hi)-mean(lo),4), t=round(as.numeric(tt$statistic),2), p=round(tt$p.value,4),
    p_wilcox=round(wt$p.value,4), 부호=ifelse(mean(hi)>mean(lo),"+","−"))
}
R <- rbindlist(res)
cat("===== F3: 정규화 축 4종 — 계약보유 vs 무계약, 외국인 t+1~t+3 =====\n"); print(R)
cat(sprintf("\n[부호 일관성] + %d/%d | [t 유의] p<0.05 %d/%d · Wilcoxon p<0.05 %d/%d\n",
  sum(R$부호=="+"), nrow(R), sum(R$p<0.05), nrow(R), sum(R$p_wilcox<0.05), nrow(R)))
cat(sprintf("[F3 판정] %s\n", ifelse(all(R$부호=="+") && sum(R$p<0.05) >= 3,
  "통제 통과 — '계약→외국인 매수'는 정규화 선택의 산물이 아님(소비 상신 유지)",
  ifelse(all(R$부호=="+"), "★부호는 일관하나 유의성이 정규화에 의존 — 상신 강도 하향 필요",
         "★★부호가 정규화에 따라 갈림 — 상신 철회하고 재설계"))))
fwrite(R, file.path(OUT, "f3_normalization.csv"))
