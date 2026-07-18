##=============================================================================
## index_factor_beta.R — 지수별 팩터 민감도(베타) 뷰 (diagnostic_monitoring)
## KOSPI200/KOSDAQ150/KOSPI/KOSDAQ 월수익(rawdata 시총가중 proxy — 실지수 아님 라벨)을
## KR FF5 팩터(MKT/SMB/HML/RMW/CMA)에 trailing 36개월 OLS → "지금 어떤 팩터에 민감한가".
## 시장 리뷰 전용 — 전략/자본 인용 금지.
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(dplyr); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- "outputs/ff5_kr"
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

FF <- as.data.table(read_parquet(file.path(OUT_DIR, "ff5_kr_monthly.parquet"))); setorder(FF, ym)

## ── 지수 proxy 월수익 (완결월) ──
ud <- sort(unique(as.Date(as.data.table(read_parquet(".cache/rawdata.parquet", col_select = "Date"))$Date)))
mgrid <- seq(as.Date("2004-12-01"), max(ud), by = "1 month")
me <- unique(as.Date(vapply(mgrid, function(d) { m0 <- as.Date(cut(d, "month")); e <- seq(m0, by = "1 month", length.out = 2)[2] - 1
  v <- ud[ud <= e & ud >= m0]; if (length(v)) as.character(max(v)) else NA_character_ }, character(1))))
me <- sort(me[!is.na(me)])
pn <- as.data.table(open_dataset(".cache/rawdata.parquet") |> filter(Date %in% me) |>
        select(all_of(c("Date", "Ticker", "Close", "Size", "K200", "KQ150", "Market"))) |> collect())
pn[, Date := as.Date(Date)]
pn <- pn[!is.na(Close) & Close > 0 & !is.na(Size) & Size > 0]
setorder(pn, Ticker, Date)
me_idx <- data.table(Date = me, i = seq_along(me))
pn <- merge(pn, me_idx, by = "Date")
pn[, `:=`(Close_p = shift(Close), i_p = shift(i), Size_p = shift(Size),
          K200_p = shift(K200), KQ150_p = shift(KQ150), Mkt_p = shift(Market)), by = Ticker]
r <- pn[!is.na(Close_p) & i_p == i - 1 & !is.na(Size_p) & Size_p > 0]
r[, ret := Close / Close_p - 1]; r <- r[ret <= 5 & ret >= -1]
r[, ym := format(Date, "%Y-%m")]
r <- r[ym < format(max(ud), "%Y-%m")]                        # 완결월만
wf("Market 라벨 표본: %s", paste(head(unique(r$Mkt_p), 8), collapse = " | "))
r[, kq := grepl("KOSDAQ|코스닥", Mkt_p, ignore.case = TRUE)]
r[, ks := !kq & !is.na(Mkt_p) & !grepl("KONEX|코넥스", Mkt_p, ignore.case = TRUE)]
vw <- function(x, w) sum(x * w) / sum(w)
IDX <- r[, .(KOSPI200  = vw(ret[K200_p == TRUE], Size_p[K200_p == TRUE]),
             KOSDAQ150 = vw(ret[KQ150_p == TRUE], Size_p[KQ150_p == TRUE]),
             KOSPI     = vw(ret[ks], Size_p[ks]),
             KOSDAQ    = vw(ret[kq], Size_p[kq])), by = ym][order(ym)]
wf("index proxy months=%d (%s..%s)", nrow(IDX), min(IDX$ym), max(IDX$ym))

## ── trailing 36개월 FF5 베타 ──
D <- merge(IDX, FF[, .(ym, MKT, SMB, HML, RMW, CMA, rf_m)], by = "ym")
D <- tail(D[complete.cases(D)], 36)
stopifnot(nrow(D) >= 30)
IDXN <- c("KOSPI200", "KOSDAQ150", "KOSPI", "KOSDAQ")
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

## ── 차트: 4지수 x 비시장 4팩터 베타 (MKT는 축 라벨 병기) ──
Bm <- sapply(IDXN, function(ix) unlist(B[[ix]])[c("SMB", "HML", "RMW", "CMA")])
lab <- vapply(IDXN, function(ix) sprintf("%s\n(MKT %.2f)", ix, B[[ix]]$MKT), character(1))
fc <- c(SMB = "firebrick", HML = "steelblue", RMW = "darkgreen", CMA = "purple")
png(file.path(OUT_DIR, "charts", "index_factor_beta.png"), width = 1250, height = 560)
par(mar = c(6, 5, 3.5, 8), cex.main = 1.45, cex.lab = 1.2)
bp <- barplot(Bm, beside = TRUE, names.arg = lab, col = fc, border = NA, cex.names = 1.15, cex.axis = 1.15,
              main = sprintf("지수별 FF5 팩터 베타 — trailing 36개월 (%s까지, 시총가중 proxy)", max(D$ym)),
              ylab = "베타", ylim = range(0, Bm) * 1.3)
abline(h = 0)
text(x = bp, y = Bm + sign(Bm) * max(abs(Bm)) * 0.06, labels = sprintf("%+.2f", Bm), cex = 0.95, xpd = TRUE)
legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4],
       legend = names(fc), fill = fc, bty = "n", cex = 1.2, xpd = TRUE)
dev.off()
wf("chart written: index_factor_beta.png")

write_json(list(metric_type = "diagnostic_monitoring", window = sprintf("36m ~%s", max(D$ym)),
                note = "지수=rawdata 시총가중 proxy(실지수 아님). y=지수월수익-CD91, X=KR FF5",
                betas = B, top_nonmkt = TOPS,
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, "index_factor_beta.json"), auto_unbox = TRUE, pretty = TRUE, digits = 4)
wf("[index_factor_beta] done")
