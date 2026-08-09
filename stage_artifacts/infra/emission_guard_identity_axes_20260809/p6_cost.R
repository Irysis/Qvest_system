## P6 — 배선 비용 실측 (추가 IO 는 0이지만 계산은 0이 아니다)
##   축 I 의 전x전 랭크 상관 격자가 지배적 비용인지 분해한다.
##   max_identity_factors=1 로 축 I 만 끄고 재면 D+T 비용이 나온다.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
say <- function(fmt, ...) cat(sprintf(paste0("[p6] ", fmt, "\n"), ...))
suppressMessages({
  source("02_Infrastructure/config.R")
  source("02_Infrastructure/factor_db/factor_db_connector.R")
  source("02_Infrastructure/factor_db/emission_guard.R")
})
DEDUP <- emission_dedup_pairs("02_Infrastructure/factor_db/factor_registry.json")
IDB   <- emission_load_identity_baseline("02_Infrastructure/factor_db/emission_declared_identity.json")

z <- suppressWarnings(load_month_factors(as.Date("2026-06-30"), coverage_min = 0))
zt <- as.data.table(z)
res <- zt[, .(Ticker, Factor_Name, Raw_Value = Z_Score_Aligned,
              Z_Score = Z_Score_Aligned, Coverage = TRUE)]
say("패널 %s행 · %d팩터 · %d종목", format(nrow(res), big.mark = ","),
    uniqueN(res$Factor_Name), uniqueN(res$Ticker))

## ★promise 를 replicate 에 넘기면 첫 force 에서만 평가되고 나머지는 0.00s 가 나온다
##   (실측: 중앙 0.00s → "공짜"로 읽힘 = 계측 사망). 클로저로 넘겨 매회 재평가시킨다.
tm <- function(f, n = 3L) {
  v <- vapply(seq_len(n), function(i) system.time(f())[["elapsed"]], numeric(1))
  c(median = median(v), min = min(v), max = max(v))
}
a <- tm(function() factor_identity_check(res, "202606", dedup_pairs = DEDUP, identity_baseline = IDB))
b <- tm(function() factor_identity_check(res, "202606", dedup_pairs = DEDUP, identity_baseline = IDB,
                                         max_identity_factors = 1L))   # 축 I 생략
say("3축 전체        : 중앙 %.2fs [%.2f, %.2f]", a[1], a[2], a[3])
say("축 D+T 만       : 중앙 %.2fs [%.2f, %.2f]", b[1], b[2], b[3])
say("축 I (격자) 몫  : 중앙 %.2fs = 전체의 %.0f%%", a[1] - b[1], 100 * (a[1] - b[1]) / a[1])
say("")
say("함의: 증분 월 빌드 1회 +%.1fs. 440개월 전면 재빌드면 +%.0f분.", a[1], a[1] * 440 / 60)
say("      전면 재빌드에서 부담되면 run_identity=FALSE 로 끄는 레버가 이미 있다(기본 TRUE).")
