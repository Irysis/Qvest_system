## FQ-182 적대검증(other_markets) — STEP 1: 후보 계열 커버리지 실측 (read-only)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
say <- function(fmt, ...) { cat(sprintf(paste0("[cov] ", fmt, "\n"), ...)); flush.console() }

IDX <- as.data.table(read_parquet(".cache/indices.parquet"))[order(Date)]
FRW <- as.data.table(read_parquet(".cache/fred_macro_wide.parquet"))[order(Date)]

rep_col <- function(dt, cn, src) {
  v <- dt[[cn]]; d <- dt$Date
  ok <- is.finite(v)
  if (sum(ok) < 10) { say("  %-16s [%s] 유효 %d — 스킵", cn, src, sum(ok)); return(NULL) }
  d1 <- d[ok]; v1 <- v[ok]
  ## 일간 간격 중앙값으로 관측단위 확인
  gap <- as.numeric(median(diff(as.numeric(d1))))
  ## 내부 결측 구멍 (첫 유효~마지막 유효 사이 결측일 비율)
  span <- dt[Date >= min(d1) & Date <= max(d1)]
  hole <- mean(!is.finite(span[[cn]]))
  say("  %-16s [%s] 유효 %5d · %s ~ %s · 간격중앙 %.0f일 · 구간내결측 %.1f%%",
      cn, src, sum(ok), min(d1), max(d1), gap, 100*hole)
  data.table(series = cn, src = src, n = sum(ok), from = min(d1), to = max(d1),
             gap_med = gap, hole_pct = 100*hole)
}

say("=== indices.parquet (KR 지수, 레벨) ===")
r1 <- rbindlist(Filter(Negate(is.null), lapply(setdiff(names(IDX), "Date"), function(c1) rep_col(IDX, c1, "indices"))))
say("=== fred_macro_wide (US/글로벌) — 수익계열 후보만 ===")
cand <- c("SP500", "Copper_Price", "KRW_USD", "VIX")
r2 <- rbindlist(Filter(Negate(is.null), lapply(cand, function(c1) rep_col(FRW, c1, "fred"))))

R <- rbind(r1, r2)
fwrite(R, "stage_artifacts/FQ182/adv_om_coverage.csv")
say("=== 저장 완료: %d 계열 ===", nrow(R))
