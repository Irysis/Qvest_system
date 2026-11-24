##=============================================================================
## index_factor_beta.R — 지수별 팩터 민감도(베타) 뷰 v2 (diagnostic_monitoring)
## ★실지수 기반 (도훈 지시 "벤치마크 데이터 보면 있을 것"): 월말 실지수 종가
##   (코스피/코스피 200/코스닥/코스닥 150 — krx_index_monthend_backfill.R 산출 · 2026-11-13 부터 퀀티와이즈 지수 정본 1순위 ·
##   KRX OPEN API 는 빈 날짜만) 월수익을 KR FF5 팩터(MKT/SMB/HML/RMW/CMA)에 trailing 36개월 OLS. benchmark.parquet(IKS200)와
##   교차검증 로그. 시장 리뷰 전용 — 전략/자본 인용 금지.
## ★진행월 MTD 회귀점(2026-11-13 개정): 지수 종가와 FF5 MTD 가 **같은 날짜까지의** 부분월일 때만 넣는다(구판은 달만 맞으면 넣었다).
##   못 넣으면 창 라벨에 사유를 적는다 — '36개월 ~<완결월> · 진행월 제외(<사유>)'(브리핑 절 제목 · 차트 제목이 이 라벨을 쓴다).
##=============================================================================
suppressMessages({ library(arrow); library(data.table); library(jsonlite) })
setDTthreads(1)
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT_DIR <- Sys.getenv("FF5_KR_OUT_DIR", "outputs/ff5_kr")              # 검사용 덮어쓰기(운영 = 기본값)
SB_DIR  <- Sys.getenv("SMARTBETA_KR_OUT_DIR", "outputs/smartbeta_kr")
wf <- function(fmt, ...) cat(sprintf(fmt, ...), "\n")

## v4 (2026-11-24 도훈 "스타일 국면 브리핑 국면판독 부분 개선"): FF = 한국 FF 요인 정본(02_Infrastructure/data/build_kr_factor_returns.R ·
##   밤 갱신 [5c] · 월간 = 완결월 · 진행월 MTD = 정본 일간 복리). 구 트래커(ff5_kr_monthly · ff5_kr_mtd.json)는 CMA 부호 반전 ·
##   월말 종가 비율 수익(가격 이음매) 결함(검토 04_Research/01_reports/style_regime_brief_review_20261124)이라 정본이 없을 때만
##   쓰고 출처 라벨(ff_source)에 적는다. 경로 덮어쓰기(검사용) = KR_FACTOR_DIR(기본 .cache).
KF_DIR <- Sys.getenv("KR_FACTOR_DIR", ".cache")
.kf_m <- file.path(KF_DIR, "kr_factor_returns_v2.parquet"); .kf_d <- file.path(KF_DIR, "kr_factor_returns_daily.parquet")
FF_SRC <- if (file.exists(.kf_m) && file.exists(.kf_d)) "정본 요인" else "구 트래커"
if (identical(FF_SRC, "정본 요인")) {
  FF <- as.data.table(read_parquet(.kf_m, col_select = c("ym", "MKT", "SMB", "HML", "RMW", "CMA", "RF")))
  FF[, ym := sprintf("%s-%s", substr(as.character(ym), 1, 4), substr(as.character(ym), 5, 6))]
  setnames(FF, "RF", "rf_m"); setorder(FF, ym)
  KD <- as.data.table(read_parquet(.kf_d, col_select = c("Date", "MKT", "SMB", "HML", "RMW", "CMA", "RF")))
  KD[, Date := as.Date(Date)]; KD <- KD[complete.cases(KD)]
  kd_last <- max(KD$Date); kd_ym <- format(kd_last, "%Y-%m")
  FF <- FF[ym < kd_ym]                                                   # 진행월 행은 월간에서 빼고 아래 MTD 로만
  .mk <- KD[format(Date, "%Y-%m") == kd_ym]
  mtd5 <- if (nrow(.mk)) list(as_of = format(kd_last), ym = kd_ym, n_days = nrow(.mk), rf_mtd = prod(1 + .mk$RF) - 1,
                              MKT = prod(1 + .mk$MKT) - 1, SMB = prod(1 + .mk$SMB) - 1, HML = prod(1 + .mk$HML) - 1,
                              RMW = prod(1 + .mk$RMW) - 1, CMA = prod(1 + .mk$CMA) - 1) else NULL
  rm(KD, .mk)
} else {
  FF <- as.data.table(read_parquet(file.path(OUT_DIR, "ff5_kr_monthly.parquet"))); setorder(FF, ym)
  mtd5 <- tryCatch(jsonlite::fromJSON(file.path(OUT_DIR, "ff5_kr_mtd.json")), error = function(e) NULL)
}
wf("FF 원천: %s (%s~%s)", FF_SRC, min(FF$ym), max(FF$ym))
IX <- as.data.table(read_parquet(file.path(OUT_DIR, "krx_index_monthend.parquet")))
IX[, Date := as.Date(Date)]; setorder(IX, idx, Date)
if (!"src" %in% names(IX)) IX[, src := "krx"]                          # 구판 산출(원천 열 없음) = KRX
ix_last <- max(IX$Date)
SRC_LAB <- switch(paste(sort(unique(IX$src)), collapse = "+"),
                  quantiwise = "퀀티와이즈 지수", krx = "KRX 지수", "krx+quantiwise" = "퀀티와이즈·KRX 지수", "실지수")
IX[, ret := close / shift(close) - 1, by = idx]
IX[, ym := format(Date, "%Y-%m")]
W <- dcast(IX[!is.na(ret)], ym ~ idx, value.var = "ret")
setnames(W, old = c("코스피", "코스피 200", "코스닥", "코스닥 150"),
         new = c("KOSPI", "KOSPI200", "KOSDAQ", "KOSDAQ150"), skip_absent = TRUE)

## 교차검증: 지수 패널 코스피200 vs benchmark.parquet(IKS200) 월수익
bm <- as.data.table(read_parquet(".cache/benchmark.parquet"))
bm[, Date := as.Date(Date)]
bm_me <- bm[Date %in% IX[idx == "코스피 200", Date]][order(Date)]
bm_me[, ret_bm := BM_Close / shift(BM_Close) - 1]
xc <- merge(W[, .(ym, KOSPI200)], bm_me[, .(ym = format(Date, "%Y-%m"), ret_bm)], by = "ym")
wf("교차검증 지수 패널 코스피200(%s) vs benchmark(IKS200): n=%d cor=%.4f max|d|=%.4f", SRC_LAB,
   nrow(xc), cor(xc$KOSPI200, xc$ret_bm, use = "complete.obs"), max(abs(xc$KOSPI200 - xc$ret_bm), na.rm = TRUE))

## trailing 36개월 + 진행월 MTD 회귀점 (도훈 지시 07-18 — 지수·팩터 동일 부분창 측정 = 유효 포인트)
D <- merge(W, FF[, .(ym, MKT, SMB, HML, RMW, CMA, rf_m)], by = "ym")
D <- tail(D[complete.cases(D)], 36)
stopifnot(nrow(D) >= 30)
IDXN <- c("KOSPI200", "KOSDAQ150", "KOSPI", "KOSDAQ")
sbmj <- tryCatch(jsonlite::fromJSON(file.path(SB_DIR, "smartbeta_kr_mtd.json")), error = function(e) NULL)
mtd_ym3 <- W[.N, ym]
## 진행월 점 판정 — 같은 날짜까지의 부분월끼리만(지수 종가일 = FF5 MTD as_of). 사유는 창 라벨에 그대로 실린다.
mtd_reason <- if (is.null(mtd5) || is.null(mtd5$rf_mtd) || is.null(mtd5$as_of)) "FF5 진행월 MTD 없음" else
  if (!identical(mtd_ym3, mtd5$ym)) sprintf("지수 종가 %s까지", format(ix_last)) else
  if (!identical(format(ix_last), as.character(mtd5$as_of))) sprintf("지수 %s · FF5 %s 기준일 불일치", format(ix_last), mtd5$as_of) else
  if (!all(IDXN %in% names(W)) || anyNA(unlist(W[.N, IDXN, with = FALSE]))) "진행월 지수 결측" else ""
mtd_ix <- if (!nzchar(mtd_reason)) W[.N] else NULL
win_lab <- if (!is.null(mtd_ix)) sprintf("36개월+MTD ~%s", mtd5$as_of) else
  sprintf("36개월 ~%s · 진행월 제외(%s)", max(D$ym), mtd_reason)
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
              main = sprintf("지수별 FF5 팩터 베타 — %s (%s · FF %s)", win_lab, SRC_LAB, FF_SRC),
              ylab = "베타", ylim = range(0, Bm) * 1.3)
abline(h = 0)
text(x = bp, y = Bm + sign(Bm) * max(abs(Bm)) * 0.06, labels = sprintf("%+.2f", Bm), cex = 0.95, xpd = TRUE)
legend(x = par("usr")[2] + diff(par("usr")[1:2]) * 0.01, y = par("usr")[4],
       legend = names(fc), fill = fc, bty = "n", cex = 1.2, xpd = TRUE)
dev.off()
wf("chart written: index_factor_beta.png")

## ── 지수 x 스마트베타 7스타일 민감도 (도훈 지시 07-18 — 시장통제 이변량) ──
## 설계: 7스타일 동시회귀는 공선성 왜곡 → 스타일별 lm(지수초과 ~ MKT + style_active) 계수.
SBm <- as.data.table(read_parquet(file.path(SB_DIR, "smartbeta_kr_monthly.parquet"))); setorder(SBm, ym)
sty <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
KRS <- c(VAL = "가치포워드", QUAL = "퀄리티(fROE)", MOM = "모멘텀", LOWVOL = "저변동성",
         SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
D2 <- merge(D, SBm[, c("ym", sty), with = FALSE], by = "ym")
## 스마트베타 진행월 점 — FF5 점이 들어갔고 스마트베타 MTD 가 같은 날짜까지일 때만(2026-11-13 · 날짜 일치 조건 추가)
sb_reason <- if (is.null(mtd_ix)) mtd_reason else
  if (is.null(sbmj) || !all(sty %in% names(sbmj)) || is.null(sbmj$as_of)) "스마트베타 진행월 MTD 없음" else
  if (!identical(as.character(sbmj$as_of), as.character(mtd5$as_of))) sprintf("스마트베타 %s · FF5 %s 기준일 불일치", sbmj$as_of, mtd5$as_of) else ""
sb_win_lab <- if (!nzchar(sb_reason)) win_lab else sprintf("36개월 ~%s · 진행월 제외(%s)", max(D$ym), sb_reason)
if (!nzchar(sb_reason)) {
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
      main = sprintf("지수 x 스마트베타 민감도 — %s · 시장 통제 베타 (%s)", sb_win_lab, SRC_LAB))
axis(2, at = seq_len(nrow(SB_B)), labels = KRL[rev(rownames(SB_B))], las = 1, tick = FALSE, cex.axis = 1.25)
axis(1, at = seq_len(ncol(SB_B)), labels = KRS[colnames(SB_B)], las = 2, tick = FALSE, cex.axis = 1.1)
for (i in seq_len(ncol(SB_B))) for (j in seq_len(nrow(SB_B)))
  text(i, j, sprintf("%+.2f", t(Hm2)[i, j]), cex = 1.05, col = ifelse(abs(t(Hm2)[i, j]) > brk2 * 0.55, "white", "gray20"))
abline(h = (0:nrow(SB_B)) + 0.5, col = "white", lwd = 2)
dev.off()
wf("chart written: index_smartbeta_beta.png")

wf("스마트베타 회귀 창: %s", sb_win_lab)
write_json(list(metric_type = "diagnostic_monitoring", window = win_lab, sb_window = sb_win_lab,
                as_of = if (!is.null(mtd_ix)) as.character(mtd5$as_of) else format(max(IX[format(Date, "%Y-%m") <= max(D$ym), Date])),
                mtd_included = !is.null(mtd_ix), sb_mtd_included = !nzchar(sb_reason),
                mtd_reason = if (is.null(mtd_ix)) mtd_reason else NA_character_,
                sb_mtd_reason = if (nzchar(sb_reason)) sb_reason else NA_character_,
                index_last = format(ix_last),
                source = sprintf("%s 월말 종가 (krx_index_monthend.parquet · 원천 %s)", SRC_LAB, paste(sort(unique(IX$src)), collapse = "+")),
                ff_source = FF_SRC,
                note = "FF5: y=지수월수익-CD91, X=KR FF5 다변량(ff_source) / SB: 스타일별 이변량(MKT 통제). 교차검증: 지수 패널 코스피200 vs IKS200",
                betas = B, top_nonmkt = TOPS,
                sb_betas = setNames(lapply(seq_len(nrow(SB_B)), function(i) as.list(SB_B[i, ])), rownames(SB_B)),
                sb_top = SB_TOPS,
                generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")),
           file.path(OUT_DIR, "index_factor_beta.json"), auto_unbox = TRUE, pretty = TRUE, digits = 4)
wf("[index_factor_beta] done")
