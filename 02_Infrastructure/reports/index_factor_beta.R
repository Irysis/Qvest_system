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

## trailing 36개월 + 진행월 MTD 회귀점 (도훈 지시 07-18 — 지수·팩터 동일 부분창 측정 = 유효 포인트)
D <- merge(W, FF[, .(ym, MKT, SMB, HML, RMW, CMA, rf_m)], by = "ym")
D <- tail(D[complete.cases(D)], 36)
stopifnot(nrow(D) >= 30)
IDXN <- c("KOSPI200", "KOSDAQ150", "KOSPI", "KOSDAQ")
mtd5 <- tryCatch(jsonlite::fromJSON(file.path(OUT_DIR, "ff5_kr_mtd.json")), error = function(e) NULL)
sbmj <- tryCatch(jsonlite::fromJSON("outputs/smartbeta_kr/smartbeta_kr_mtd.json"), error = function(e) NULL)
mtd_ym3 <- W[.N, ym]
mtd_ix <- if (!is.null(mtd5) && !is.null(mtd5$rf_mtd) && identical(mtd_ym3, mtd5$ym) &&
              all(IDXN %in% names(W)) && !anyNA(unlist(W[.N, IDXN, with = FALSE]))) W[.N] else NULL
win_lab <- if (!is.null(mtd_ix)) sprintf("36개월+MTD ~%s", mtd5$as_of) else sprintf("36개월 ~%s", max(D$ym))
D_fit <- D
if (!is.null(mtd_ix)) D_fit <- rbind(D, data.table(ym = mtd_ym3,
    KOSPI200 = mtd_ix$KOSPI200, KOSDAQ150 = mtd_ix$KOSDAQ150, KOSPI = mtd_ix$KOSPI, KOSDAQ = mtd_ix$KOSDAQ,
    MKT = mtd5$MKT, SMB = mtd5$SMB, HML = mtd5$HML, RMW = mtd5$RMW, CMA = mtd5$CMA, rf_m = mtd5$rf_mtd), fill = TRUE)
wf("회귀 창: %s (n=%d)", win_lab, nrow(D_fit))
KRL <- c(KOSPI200 = "코스피200", KOSDAQ150 = "코스닥150", KOSPI = "코스피", KOSDAQ = "코스닥")
FN <- c("MKT", "SMB", "HML", "RMW", "CMA")
B <- list(); TOPS <- list()
for (ix in IDXN) {
  m <- lm(D_fit[[ix]] - D_fit$rf_m ~ MKT + SMB + HML + RMW + CMA, data = D_fit)
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
              main = sprintf("지수별 FF5 팩터 베타 — %s (KRX 실지수)", win_lab),
              ylab = "베타", ylim = range(0, Bm) * 1.3)
abline(h = 0)
text(x = bp, y = Bm + sign(Bm) * max(abs(Bm)) * 0.06, labels = sprintf("%+.2f", Bm), cex = 0.95, xpd = TRUE)
legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4],
       legend = names(fc), fill = fc, bty = "n", cex = 1.2, xpd = TRUE)
dev.off()
wf("chart written: index_factor_beta.png")

## ── 지수 x 스마트베타 7스타일 민감도 (도훈 지시 07-18 — 시장통제 이변량) ──
## 설계: 7스타일 동시회귀는 공선성 왜곡 → 스타일별 lm(지수초과 ~ MKT + style_active) 계수.
SBm <- as.data.table(read_parquet("outputs/smartbeta_kr/smartbeta_kr_monthly.parquet")); setorder(SBm, ym)
sty <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
KRS <- c(VAL = "가치포워드", QUAL = "퀄리티(fROE)", MOM = "모멘텀", LOWVOL = "저변동성",
         SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
D2 <- merge(D, SBm[, c("ym", sty), with = FALSE], by = "ym")
if (!is.null(mtd_ix) && !is.null(sbmj) && all(sty %in% names(sbmj))) {
  D2 <- rbind(D2, data.table(ym = mtd_ym3,
      KOSPI200 = mtd_ix$KOSPI200, KOSDAQ150 = mtd_ix$KOSDAQ150, KOSPI = mtd_ix$KOSPI, KOSDAQ = mtd_ix$KOSDAQ,
      MKT = mtd5$MKT, SMB = mtd5$SMB, HML = mtd5$HML, RMW = mtd5$RMW, CMA = mtd5$CMA, rf_m = mtd5$rf_mtd,
      VAL = sbmj$VAL, QUAL = sbmj$QUAL, MOM = sbmj$MOM, LOWVOL = sbmj$LOWVOL,
      SIZE = sbmj$SIZE, DIV = sbmj$DIV, EREV = sbmj$EREV), fill = TRUE)
}
SB_B <- matrix(NA_real_, nrow = length(IDXN), ncol = length(sty), dimnames = list(IDXN, sty))
for (ix in IDXN) for (st in sty) {
  ok <- complete.cases(D2[[ix]], D2$MKT, D2[[st]])
  if (sum(ok) >= 30) {
    m2 <- lm(D2[[ix]][ok] - D2$rf_m[ok] ~ D2$MKT[ok] + D2[[st]][ok])
    SB_B[ix, st] <- round(coef(m2)[3], 3)
  }
}
SB_TOPS <- lapply(IDXN, function(ix) { v <- SB_B[ix, ]; top <- names(v)[which.max(abs(v))]
  sprintf("%s %+.2f", KRS[top], v[top]) })
names(SB_TOPS) <- IDXN
for (ix in IDXN) wf("%-10s SB-beta: %s | 최대 %s", ix, paste(sprintf("%s %+.2f", sty, SB_B[ix, ]), collapse = " "), SB_TOPS[[ix]])

## 차트 2: 4지수 x 7스타일 베타 히트맵
brk2 <- max(abs(SB_B), na.rm = TRUE)
pal2 <- colorRampPalette(c("#2166AC", "#F7F7F7", "#B2182B"))(64)
png(file.path(OUT_DIR, "charts", "index_smartbeta_beta.png"), width = 1250, height = 440)
par(mar = c(7, 8, 3.5, 2), cex.main = 1.45)
Hm2 <- SB_B[rev(seq_len(nrow(SB_B))), , drop = FALSE]
image(x = seq_len(ncol(SB_B)), y = seq_len(nrow(SB_B)), z = t(Hm2), col = pal2, zlim = c(-brk2, brk2),
      axes = FALSE, xlab = "", ylab = "",
      main = sprintf("지수 x 스마트베타 민감도 — %s·시장통제 베타", win_lab))
axis(2, at = seq_len(nrow(SB_B)), labels = KRL[rev(rownames(SB_B))], las = 1, tick = FALSE, cex.axis = 1.25)
axis(1, at = seq_len(ncol(SB_B)), labels = KRS[colnames(SB_B)], las = 2, tick = FALSE, cex.axis = 1.1)
for (i in seq_len(ncol(SB_B))) for (j in seq_len(nrow(SB_B)))
  text(i, j, sprintf("%+.2f", t(Hm2)[i, j]), cex = 1.05, col = ifelse(abs(t(Hm2)[i, j]) > brk2 * 0.55, "white", "gray20"))
abline(h = (0:nrow(SB_B)) + 0.5, col = "white", lwd = 2)
dev.off()
wf("chart written: index_smartbeta_beta.png")

write_json(list(metric_type = "diagnostic_monitoring", window = win_lab,
                source = "KRX OPEN API 실지수 월말 (krx_index_monthend.parquet)",
                note = "FF5: y=지수월수익-CD91, X=KR FF5 다변량 / SB: 스타일별 이변량(MKT 통제). 교차검증: KRX 코스피200 vs IKS200",
                betas = B, top_nonmkt = TOPS,
                sb_betas = setNames(lapply(seq_len(nrow(SB_B)), function(i) as.list(SB_B[i, ])), rownames(SB_B)),
                sb_top = SB_TOPS,
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, "index_factor_beta.json"), auto_unbox = TRUE, pretty = TRUE, digits = 4)
wf("[index_factor_beta] done")
