##=============================================================================
## index_factor_beta.R — 지수별 팩터 민감도(베타) 뷰 v2 (diagnostic_monitoring)
## ★실지수 기반 (도훈 지시 "벤치마크 데이터 보면 있을 것"): KRX OPEN API 월말 실지수
##   (코스피/코스피 200/코스닥/코스닥 150 — krx_index_monthend_backfill.R 산출) 월수익을
##   KR FF5 팩터(MKT/SMB/HML/RMW/CMA)에 trailing 36개월 OLS. benchmark.parquet(IKS200)와
##   교차검증 로그. 시장 리뷰 전용 — 전략/자본 인용 금지.
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- "outputs/ff5_kr"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

FF <- as.data.table(read_parquet(file.path(OUT_DIR, "ff5_kr_monthly.parquet"))); setorder(FF, ym)
IX <- as.data.table(read_parquet(file.path(OUT_DIR, "krx_index_monthend.parquet")))
IX[, Date := as.Date(Date)]; setorder(IX, idx, Date)
IX[, ret := close / shift(close) - 1, by = idx]
IX[, ym := format(Date, "%Y-%m")]
W <- dcast(IX[!is.na(ret)], ym ~ idx, value.var = "ret")
setnames(W, old = c("코스피", "코스피 200", "코스닥", "코스닥 150"),
         new = c("KOSPI", "KOSPI200", "KOSDAQ", "KOSDAQ150"), skip_absent = TRUE)

## 교차검증: KRX 코스피200 vs benchmark.parquet(IKS200) 월수익
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
bm_me <- bm[Date %in% IX[idx == "코스피 200", Date]][order(Date)]
bm_me[, ret_bm := BM_Close / shift(BM_Close) - 1]
xc <- merge(W[, .(ym, KOSPI200)], bm_me[, .(ym = format(Date, "%Y-%m"), ret_bm)], by = "ym")
wf("교차검증 KRX코스피200 vs benchmark(IKS200): n=%d cor=%.4f max|d|=%.4f",
   nrow(xc), cor(xc$KOSPI200, xc$ret_bm, use = "complete.obs"), max(abs(xc$KOSPI200 - xc$ret_bm), na.rm = TRUE))

## trailing 36개월 FF5 베타
D <- merge(W, FF[, .(ym, MKT, SMB, HML, RMW, CMA, rf_m)], by = "ym")
D <- tail(D[complete.cases(D)], 36)
stopifnot(nrow(D) >= 30)
IDXN <- c("KOSPI200", "KOSDAQ150", "KOSPI", "KOSDAQ")
KRL <- c(KOSPI200 = "코스피200", KOSDAQ150 = "코스닥150", KOSPI = "코스피", KOSDAQ = "코스닥")
FN <- c("MKT", "SMB", "HML", "RMW", "CMA")
B <- list(); TOPS <- list()
for (ix in IDXN) {
  m <- lm(D[[ix]] - D$rf_m ~ MKT + SMB + HML + RMW + CMA, data = D)
  cf <- coef(m)[FN]
  B[[ix]] <- as.list(round(cf, 3))
  nonmkt <- cf[c("SMB", "HML", "RMW", "CMA")]
  top <- names(nonmkt)[which.max(abs(nonmkt))]
  TOPS[[ix]] <- sprintf("%s %+.2f", top, nonmkt[top])
  wf("%-10s MKT %+.2f | SMB %+.2f HML %+.2f RMW %+.2f CMA %+.2f | R2 %.2f | 최대(비시장) %s",
     ix, cf["MKT"], cf["SMB"], cf["HML"], cf["RMW"], cf["CMA"], summary(m)$r.squared, TOPS[[ix]])
}

## 차트: 4지수 x 비시장 4팩터 베타 (MKT는 라벨 병기)
Bm <- sapply(IDXN, function(ix) unlist(B[[ix]])[c("SMB", "HML", "RMW", "CMA")])
colnames(Bm) <- KRL[IDXN]
lab <- vapply(IDXN, function(ix) sprintf("%s\n(MKT %.2f)", KRL[ix], B[[ix]]$MKT), character(1))
fc <- c(SMB = "firebrick", HML = "steelblue", RMW = "darkgreen", CMA = "purple")
png(file.path(OUT_DIR, "charts", "index_factor_beta.png"), width = 1250, height = 560)
par(mar = c(6, 5, 3.5, 8), cex.main = 1.45, cex.lab = 1.2)
bp <- barplot(Bm, beside = TRUE, names.arg = lab, col = fc, border = NA, cex.names = 1.2, cex.axis = 1.15,
              main = sprintf("지수별 FF5 팩터 베타 — trailing 36개월 (~%s, KRX 실지수)", max(D$ym)),
              ylab = "베타", ylim = range(0, Bm) * 1.3)
abline(h = 0)
text(x = bp, y = Bm + sign(Bm) * max(abs(Bm)) * 0.06, labels = sprintf("%+.2f", Bm), cex = 0.95, xpd = TRUE)
legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4],
       legend = names(fc), fill = fc, bty = "n", cex = 1.2, xpd = TRUE)
dev.off()
wf("chart written: index_factor_beta.png")

write_json(list(metric_type = "diagnostic_monitoring", window = sprintf("36m ~%s", max(D$ym)),
                source = "KRX OPEN API 실지수 월말 (krx_index_monthend.parquet)",
                note = "y = 지수 월수익 - CD91월할, X = KR FF5. 교차검증: KRX 코스피200 vs IKS200 benchmark",
                betas = B, top_nonmkt = TOPS,
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, "index_factor_beta.json"), auto_unbox = TRUE, pretty = TRUE, digits = 4)
wf("[index_factor_beta] done")
