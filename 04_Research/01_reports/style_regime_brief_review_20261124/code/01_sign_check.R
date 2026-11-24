## 01_sign_check.R — 스타일 국면 브리핑 입력의 부호 점검 (검토 전용 · 운영 코드 무변경)
##   의심: 팩터 DB 저장값이 Q06_Asset_Growth = −(자산증가율) · D03_RealVol = −sd(Ret) 인데
##         ff5_kr_tracker.R(CMA = Q06 낮을수록 보수) · smartbeta_kr_tracker.R(LOWVOL = D03 낮을수록)은
##         저장값을 원래 양(자산증가율 · 변동성)으로 가정한다 → CMA · LOWVOL 부호 반전 가능.
##   판별(자료의 성질만 · 문턱 없음):
##     (1) 진짜 CMA 는 HML 과 양의 상관(Fama-French 2015 JFE 116(1) 표 4 · 미국 0.7 안팎) → 음이면 반전 신호
##     (2) 진짜 저변동성 초과수익(시총가중 유니버스 대비)은 시장과 음의 상관(저베타) → 양이면 고변동성
##   입력 = 아침 산출물 사본(스크래치) · 팩터 DB · 재무 캐시는 읽지 않는다.
suppressMessages({ library(arrow); library(data.table) })
args <- commandArgs(trailingOnly = TRUE)
SNAP <- if (length(args) >= 1) args[1] else "."
OUT  <- if (length(args) >= 2) args[2] else "."
FF <- as.data.table(read_parquet(file.path(SNAP, "ff5_kr_monthly.parquet")))
SB <- as.data.table(read_parquet(file.path(SNAP, "smartbeta_kr_monthly.parquet")))
cat(sprintf("FF5 %d개월 %s~%s | SB %d개월 %s~%s\n", nrow(FF), min(FF$ym), max(FF$ym), nrow(SB), min(SB$ym), max(SB$ym)))

cm <- function(d, cols) round(cor(d[, ..cols], use = "pairwise.complete.obs"), 2)
f5 <- c("MKT", "SMB", "HML", "RMW", "CMA")
cat("\n[FF5 상관 · 전기간]\n"); print(cm(FF, f5))
cat("\n[FF5 상관 · 2005-06~2015-12]\n"); print(cm(FF[ym <= "2015-12"], f5))
cat("\n[FF5 상관 · 2016-01~]\n"); print(cm(FF[ym >= "2016-01"], f5))

m <- merge(SB, FF[, .(ym, MKT, SMB, HML, RMW, CMA)], by = "ym")
sty <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
cat("\n[스마트베타 스타일 초과수익의 시장 β · 상관 (FF5 MKT 와 같은 실현월)]\n")
res <- rbindlist(lapply(sty, function(s) {
  x <- m[!is.na(get(s)) & !is.na(MKT)]
  b <- coef(lm(x[[s]] ~ x$MKT))[2]
  data.table(style = s, n = nrow(x), beta_mkt = round(b, 3), cor_mkt = round(cor(x[[s]], x$MKT), 3),
             cor_SMB = round(cor(x[[s]], x$SMB), 3), cor_HML = round(cor(x[[s]], x$HML), 3),
             mean_pct = round(mean(x[[s]]) * 100, 3))
}))
print(res)

## 판 사이 일관성: 날짜별 FF5 사본(CSV)의 CMA 가 같은 부호로 계산돼 왔나
csvs <- sort(Sys.glob(file.path(SNAP, "vint", "ff5_kr_monthly_*.csv")))
if (length(csvs)) {
  ref <- FF[, .(ym, CMA_now = CMA, HML_now = HML)]
  vt <- rbindlist(lapply(csvs, function(p) {
    v <- fread(p, select = c("ym", "HML", "CMA"))
    j <- merge(v, ref, by = "ym")
    data.table(vintage = sub(".*_(\\d{8})\\.csv$", "\\1", p), n = nrow(j),
               cor_CMA_vs_now = round(cor(j$CMA, j$CMA_now, use = "complete.obs"), 3),
               cor_HML_vs_now = round(cor(j$HML, j$HML_now, use = "complete.obs"), 3),
               cor_HML_CMA_in_vintage = round(cor(v$HML, v$CMA, use = "complete.obs"), 3))
  }))
  cat("\n[날짜별 사본 대 현재 판]\n"); print(vt)
  fwrite(vt, file.path(OUT, "sign_check_vintages.csv"))
}
fwrite(res, file.path(OUT, "sign_check_smartbeta_beta.csv"))
fwrite(as.data.table(cm(FF, f5), keep.rownames = "factor"), file.path(OUT, "sign_check_ff5_cor.csv"))
