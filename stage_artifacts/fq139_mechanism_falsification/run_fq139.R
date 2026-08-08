# run_fq139.R — FQ-139: 계약수주 메커니즘 직접 반증 (기관 후속 순매수 경로가 실재하는가)
# 가설(alpha_package.falsification #1, 미측정): mechanism.path = '기관 후속 매수로 가격 반영'.
#   → score 상위분위 종목의 t+1~t+3 기관 순매수가 하위분위 대비 유의하게 증가해야 한다.
#   증가하지 않으면 그 경로는 기각되고 국면 의존을 다른 기전으로 재서술해야 한다.
# ★성과가 아닌 **부수 관측**으로 기전을 시험 — 성과 동어반복 회피(큐 ev_rationale).
# 데이터: 04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet
#         .cache/investor_stock/investor_wide.parquet (Institutional = 순매수 금액)
suppressMessages({ library(data.table); library(arrow) })
options(scipen=999)
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
OUT <- "stage_artifacts/fq139_mechanism_falsification"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)

P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_A.parquet"))
cat(sprintf("[panelx_A] rows=%s cols=%d\n  names: %s\n", format(nrow(P), big.mark=","), ncol(P),
            paste(names(P), collapse=", ")))
dcol <- names(P)[sapply(P, function(x) inherits(x,"Date")||inherits(x,"IDate"))][1]
if (is.na(dcol)) { dcol <- grep("date|Date", names(P), value=TRUE)[1]; P[, (dcol) := as.Date(get(dcol))] }
scol <- grep("score|signal|magnitude|amt|value", names(P), value=TRUE, ignore.case=TRUE)
cat(sprintf("[열 추정] date=%s | score 후보=%s\n", dcol, paste(scol, collapse=",")))
stopifnot(length(scol) >= 1, "Ticker" %in% names(P))
SC <- scol[1]
setnames(P, c(dcol, SC), c("Date","score"), skip_absent=TRUE)
P <- P[is.finite(score) & !is.na(Date) & !is.na(Ticker)]
cat(sprintf("[panelx_A] 유효 %s행 | %s ~ %s | 종목 %d | 이벤트일 %d\n", format(nrow(P), big.mark=","),
            min(P$Date), max(P$Date), uniqueN(P$Ticker), uniqueN(P$Date)))

IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
        col_select=c("Date","Ticker","Institutional","Foreign","Individual")))
IV[, Date := as.Date(Date)]; setkey(IV, Ticker, Date)
# 거래대금 정규화용
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol")))
raw[, Date := as.Date(Date)]; raw[, TV := Close*Vol]; setkey(raw, Ticker, Date)
IV <- merge(IV, raw[, .(Ticker, Date, TV)], by=c("Ticker","Date"), all.x=TRUE)
IV[, `:=`(inst_n = Institutional / pmax(TV, 1), forg_n = Foreign / pmax(TV, 1))]
setkey(IV, Ticker, Date)

# 각 이벤트에 대해 t+1..t+3 기관 순매수(거래대금 정규화) 합산
ev <- P[, .(Date, Ticker, score)]
setkey(ev, Ticker, Date)
fwd <- function(k1, k2) {
  IV[, .(Ticker, Date, inst_n, forg_n)][ev, on=.(Ticker, Date), roll=FALSE, nomatch=NULL]
}
# 종목별 시계열 인덱스로 t+1~t+3 취득
IV[, idx := seq_len(.N), by=Ticker]
ev2 <- merge(ev, IV[, .(Ticker, Date, idx)], by=c("Ticker","Date"))
cat(sprintf("[매칭] 이벤트 %s건 중 투자자패널 매칭 %s건 (%.1f%%)\n",
    format(nrow(ev), big.mark=","), format(nrow(ev2), big.mark=","), 100*nrow(ev2)/nrow(ev)))
acc <- IV[, .(Ticker, idx, inst_n, forg_n)]
for (h in 1:3) {
  a <- copy(acc); a[, idx := idx - h]
  setnames(a, c("inst_n","forg_n"), c(paste0("i",h), paste0("f",h)))
  ev2 <- merge(ev2, a[, .(Ticker, idx, get(paste0("i",h)), get(paste0("f",h)))], by=c("Ticker","idx"), all.x=TRUE)
  setnames(ev2, c("V3","V4"), c(paste0("i",h), paste0("f",h)))
}
ev2[, inst_3d := rowSums(.SD, na.rm=TRUE), .SDcols=c("i1","i2","i3")]
ev2[, forg_3d := rowSums(.SD, na.rm=TRUE), .SDcols=c("f1","f2","f3")]
ev2[, n_ok := rowSums(!is.na(.SD)), .SDcols=c("i1","i2","i3")]
E <- ev2[n_ok == 3L]
cat(sprintf("[t+1~t+3 완비] %s건\n", format(nrow(E), big.mark=",")))

# 이벤트일 내 횡단면 분위 (PIT 안전 — 같은 날 정보만)
E[, q := cut(frank(score, ties.method="average")/.N, breaks=c(0,0.2,0.8,1.0), labels=c("하위20","중간","상위20")), by=Date]
S <- E[!is.na(q), .(n=.N, inst_3d_mean=mean(inst_3d), inst_3d_med=median(inst_3d),
                    forg_3d_mean=mean(forg_3d)), by=q][order(q)]
cat("\n===== 분위별 t+1~t+3 기관 순매수 (거래대금 정규화) =====\n"); print(S)
hi <- E[q=="상위20", inst_3d]; lo <- E[q=="하위20", inst_3d]
tt <- t.test(hi, lo); wt <- suppressWarnings(wilcox.test(hi, lo))
cat(sprintf("\n[상위20 vs 하위20] 평균 %+.5f vs %+.5f | 차이 %+.5f | Welch t=%.3f p=%.4f | Wilcoxon p=%.4f\n",
    mean(hi), mean(lo), mean(hi)-mean(lo), tt$statistic, tt$p.value, wt$p.value))
hf <- E[q=="상위20", forg_3d]; lf <- E[q=="하위20", forg_3d]
tf <- t.test(hf, lf)
cat(sprintf("[외국인 대조] 평균 %+.5f vs %+.5f | 차이 %+.5f | t=%.3f p=%.4f\n",
    mean(hf), mean(lf), mean(hf)-mean(lf), tf$statistic, tf$p.value))
cat(sprintf("\n[판정] mechanism.path('기관 후속 매수로 가격 반영') : %s\n",
    ifelse(tt$p.value < 0.05 && mean(hi) > mean(lo), "지지 (상위분위 기관 순매수 유의 증가)",
           "★기각 — 유의한 증가 없음 → 국면 의존을 다른 기전으로 재서술 필요")))
fwrite(S, file.path(OUT, "fq139_quantile_summary.csv"))
fwrite(E[, .(Date, Ticker, score, q, inst_3d, forg_3d)], file.path(OUT, "fq139_event_detail.csv"))
cat(sprintf("[saved] %s\n", OUT))
