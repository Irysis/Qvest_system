## PIT 정렬 검증 — frd$Ret_1m 이 Date 라벨 월의 *미래* 수익인지 독립 원천으로 확인
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
S <- readRDS("stage_artifacts/WT-D20260821_002/step0_inputs.rds")
frd <- as.data.table(S$frd); bench <- as.data.table(S$bench_dt)

## 1) frd 월별 횡단면 평균 vs RAWDATA 실제 월 수익 (독립 재구성)
rd <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select=c("Date","Ticker","Ret")))
rd[, ym := format(Date, "%Y-%m")]
mo <- rd[is.finite(Ret), .(mret = prod(1+Ret)-1), by=.(Ticker, ym)]      # 종목-월 실현수익
mo_cs <- mo[, .(cs_mean_realized = mean(mret, na.rm=TRUE)), by=ym][order(ym)]

frd[, ym_label := format(Date, "%Y-%m")]
f_cs <- frd[, .(cs_mean_frd = mean(Ret_1m, na.rm=TRUE)), by=ym_label][order(ym_label)]

## lead/lag 스캔: frd 의 Date 라벨이 어느 실현월과 일치하는가
seq_shift <- function(ymv, k) format(seq(as.Date(paste0(ymv,"-01")), by=paste(k,"month"), length.out=2)[2], "%Y-%m")
tab <- data.table()
for (k in -2:2) {
  a <- copy(f_cs); a[, ym_join := sapply(ym_label, seq_shift, k=k)]
  j <- merge(a, mo_cs, by.x="ym_join", by.y="ym")
  tab <- rbind(tab, data.table(shift_months=k, n=nrow(j),
                               cor=cor(j$cs_mean_frd, j$cs_mean_realized, use="complete.obs")))
}
cat("=== frd$Ret_1m(Date 라벨) vs RAWDATA 실현 월수익 — shift 스캔 ===\n")
cat("  shift=0 최대여야 'Date 라벨 = 수익 실현월' 확정\n"); print(tab)

## 2) 벤치도 동일 정렬인가
bench[, ym_label := format(Date, "%Y-%m")]
jb <- merge(f_cs, bench[, .(ym_label, BM_Ret)], by="ym_label")
cat("\n벤치 BM_Ret vs frd 횡단면평균 동월 상관:", round(cor(jb$cs_mean_frd, jb$BM_Ret, use="complete.obs"),4), "\n")

## 3) 결정적 PIT 검사: sig_date 가 수익 실현월 시작 이전인가
sc <- as.data.table(S$panels$armA)[, .(Date, sig_date)]
u <- unique(sc)[, .(sig_date = max(sig_date)), by=Date][order(Date)]
u[, holding_start := as.Date(format(Date, "%Y-%m-01"))]
u[, gap_days := as.integer(holding_start - as.Date(sig_date))]
cat("\n=== sig_date -> 홀딩월 시작 간격 (C5: 반드시 > 0) ===\n")
cat(sprintf("  min %d일 · median %d일 · max %d일 · 음수/0 건수 %d\n",
    min(u$gap_days), as.integer(median(u$gap_days)), max(u$gap_days), sum(u$gap_days <= 0)))
print(tail(u[, .(Date, sig_date, holding_start, gap_days)], 3))

write_json(list(shift_scan=tab, bench_cor=cor(jb$cs_mean_frd, jb$BM_Ret, use="complete.obs"),
                sig_to_holding_gap=list(min=min(u$gap_days), median=median(u$gap_days),
                                        max=max(u$gap_days), n_nonpositive=sum(u$gap_days<=0))),
           "stage_artifacts/WT-D20260821_002/pit_align_check.json", auto_unbox=TRUE, pretty=TRUE, digits=8)
