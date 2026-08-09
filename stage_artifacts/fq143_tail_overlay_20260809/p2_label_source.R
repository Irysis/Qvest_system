## FQ-143 P2 — 라벨 원천 정체 확인 + PIT 컷오프 실측
## 왜: "현행 국면 라벨"이라는 이름 하나에 서로 다른 시간축의 계열이 여럿 붙어 있다.
##     소비 전에 (a) 어느 파일인가 (b) 관측단위/범위 (c) 발화가 어느 달을 보고 정해졌나 를 실측한다.
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
DIR  <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")

cands <- c("unified_regime_signal.parquet", "unified_regime_signal_daily.parquet",
           "regime_daily_v2.parquet", "regime_forecast_series.parquet",
           "regime_forecast_series_v2.parquet", "regime_forecast_series_v3.parquet",
           "macro_regime.parquet", "msm_daily_latest.parquet")
for (f in cands) {
  fp <- file.path(ROOT, ".cache", f)
  if (!file.exists(fp)) { cat(sprintf("[MISS] %s\n", f)); next }
  d <- tryCatch(as.data.table(read_parquet(fp)), error = function(e) NULL)
  if (is.null(d)) { cat(sprintf("[ERR ] %s\n", f)); next }
  dcol <- intersect(c("Date","date","ym","month"), names(d))[1]
  rng <- if (!is.na(dcol)) sprintf("%s ~ %s", min(d[[dcol]], na.rm=TRUE), max(d[[dcol]], na.rm=TRUE)) else "no date col"
  cat(sprintf("\n[FILE] %-38s nrow=%6d  cols=%s\n        범위: %s\n", f, nrow(d),
              paste(head(names(d), 12), collapse=","), rng))
  lc <- intersect(c("regime","state","label","regime_label","signal"), names(d))
  for (L in lc) { tb <- table(d[[L]]); cat(sprintf("        %s: %s\n", L, paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse=" "))) }
}
cat("\n[P2 DONE]\n")
