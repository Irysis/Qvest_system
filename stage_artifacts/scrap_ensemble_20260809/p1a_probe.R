#!/usr/bin/env Rscript
# =============================================================================
# p1a_probe.R — ★첫 출력은 입력 실측. 형태 가정 금지.
#   (feedback-assert-input-shape-before-measuring: rawdata 를 월간으로 가정해 55분 전량 폐기한 전례)
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(PROJ)) PROJ <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(PROJ); OUT <- file.path(PROJ, "stage_artifacts/scrap_ensemble_20260809")
sink(file.path(OUT, "p1a_probe.log"), split = TRUE)

cat("=== [0] INPUT SHAPE (실측, 가정 아님) ===\n")
P <- readRDS(file.path(OUT, "p0_panel.rds"))
cat(sprintf("  p0_panel.rds top-level names: %s\n", paste(names(P), collapse = ", ")))
PAN <- P$PAN
cat(sprintf("  class(PAN)          = %s\n", paste(class(PAN), collapse = "/")))
cat(sprintf("  dim(PAN)            = %d rows x %d cols\n", nrow(PAN), ncol(PAN)))
cat(sprintf("  PAN ym range        = %s .. %s   (n_unique_ym=%d)\n",
            min(PAN$ym), max(PAN$ym), uniqueN(PAN$ym)))
cat(sprintf("  ym duplicated?      = %s (dup rows=%d)  ⇒ 관측단위 = %s\n",
            any(duplicated(PAN$ym)), sum(duplicated(PAN$ym)),
            if (any(duplicated(PAN$ym))) "WIDE 아님(중복 ym)" else "wide: 1 row = 1 month"))
cat(sprintf("  ym 형식 예시        = %s (nchar=%d)\n", PAN$ym[1], nchar(PAN$ym[1])))
# 월 연속성 실측
ymv <- sort(unique(PAN$ym))
yy <- as.integer(substr(ymv,1,4)); mm <- as.integer(substr(ymv,5,6)); midx <- yy*12+mm
cat(sprintf("  월 연속성           : 기대 %d개월, 실제 %d개월, gap=%d\n",
            max(midx)-min(midx)+1, length(midx), (max(midx)-min(midx)+1)-length(midx)))
cat(sprintf("  scrap_ok=%d  elite_ok=%d  start_ym=%s\n",
            length(P$scrap_ok), length(P$elite_ok), P$start_ym))
cat(sprintf("  bm: n=%d finite=%d  mean=%.5f sd=%.5f min=%.5f max=%.5f\n",
            length(PAN$bm), sum(is.finite(PAN$bm)), mean(PAN$bm, na.rm=TRUE),
            sd(PAN$bm, na.rm=TRUE), min(PAN$bm, na.rm=TRUE), max(PAN$bm, na.rm=TRUE)))
cat(sprintf("  ⇒ bm 스케일: |mean| %.4f → %s 수익률\n", abs(mean(PAN$bm,na.rm=TRUE)),
            if (abs(mean(PAN$bm,na.rm=TRUE)) < 0.05) "소수(decimal) 월간" else "퍼센트 의심"))
mod1 <- P$scrap_ok[1]
cat(sprintf("  모듈 예시 %s: finite=%d mean=%.5f sd=%.5f\n", mod1,
            sum(is.finite(PAN[[mod1]])), mean(PAN[[mod1]], na.rm=TRUE), sd(PAN[[mod1]], na.rm=TRUE)))
cat(sprintf("  PAN 비-모듈 컬럼    : %s\n",
            paste(setdiff(names(PAN), c("ym", P$scrap_ok, P$elite_ok)), collapse=", ")))

cat("\n=== [1] REGIME PARQUET SHAPE ===\n")
rp <- file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")
cat(sprintf("  exists = %s\n", file.exists(rp)))
if (file.exists(rp)) {
  RG <- as.data.table(read_parquet(rp))
  cat(sprintf("  dim = %d rows x %d cols\n", nrow(RG), ncol(RG)))
  cat(sprintf("  cols = %s\n", paste(names(RG), collapse = ", ")))
  dcol <- intersect(c("Date","date","DATE"), names(RG))
  if (length(dcol)) {
    d <- RG[[dcol[1]]]
    cat(sprintf("  %s: class=%s range %s .. %s  n_unique=%d\n", dcol[1],
                paste(class(d), collapse="/"), as.character(min(d)), as.character(max(d)), uniqueN(d)))
    cat(sprintf("  ⇒ 관측단위 실측: 총 %d행 / %d 고유일자 = %.2f (1.0 이면 일간 1행)\n",
                nrow(RG), uniqueN(d), nrow(RG)/uniqueN(d)))
    dd <- sort(unique(as.Date(d))); gaps <- as.integer(diff(dd))
    cat(sprintf("  일자 간격 median=%d days  max=%d days\n", median(gaps), max(gaps)))
  }
  if ("Category" %in% names(RG)) {
    cat("  Category 분포:\n"); print(RG[, .N, by=Category][order(-N)])
  } else cat("  ★ Category 컬럼 없음 — 대체 컬럼 확인 필요\n")
  cat("  head 3:\n"); print(head(RG, 3))
}
cat("\n[done]\n"); sink()
