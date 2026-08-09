## P0 — 축을 넣기 전에: 그 통계가 그 면에서 **변동하는지** 먼저 잰다.
##
## 왜 (2026-08-09 실사고): 정체 감사의 초판이 sd(Z_Score) 를 죽은 배출의 판별통계로
## 썼는데, Z 는 횡단면 표준화 산물이라 331종 전부 정확히 1.0000 이 나온다.
## 판별력이 **원리적으로 0**인 통계로 "죽은 배출 0종"을 산출했다 — 결과가 아니라
## 계측 사망이었다. 그래서 배선 전에 후보 통계별로 다음을 실측한다:
##   (1) 값 범위가 실제로 벌어지는가 (상수면 죽은 통계)
##   (2) 알려진 결함(C15/D60/Q16)에서 정상 팩터와 갈리는가
##
## 경로: load_month_factors() 경유(C15) + emission_ledger.csv 재판독. 재빌드 없음.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/emission_guard_identity_axes_20260809")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
say <- function(fmt, ...) { cat(sprintf(paste0("[p0] ", fmt, "\n"), ...)); flush.console() }
t0 <- Sys.time()

source("02_Infrastructure/config.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")

MONTHS <- as.Date(c("2018-06-30", "2022-06-30", "2026-06-30"))
led <- fread(".cache/factor_db/emission_ledger.csv", colClasses = list(character = "ym"))

modal_uniq <- function(v) {
  v <- v[is.finite(v)]
  n <- length(v)
  if (!n) return(c(NA_real_, NA_real_))
  r <- rle(sort(round(v, 10)))
  c(max(r$lengths) / n, length(r$lengths) / n)
}

res <- list()
for (d in MONTHS) {
  d <- as.Date(d, origin = "1970-01-01")
  z <- load_month_factors(d, coverage_min = 0)
  fil <- attr(z, "factor_db_file")
  ymf <- sub("^factor_db_([0-9]{6})[.]parquet$", "\\1", fil)
  zt <- as.data.table(z)
  st <- zt[, {
    m <- modal_uniq(Z_Score_Aligned)
    .(n_obs = .N, sd_z = sd(Z_Score_Aligned, na.rm = TRUE),
      modal_frac = m[1], uniq_ratio = m[2])
  }, by = Factor_Name]
  st[, ym := ymf]
  res[[ymf]] <- st

  led_set <- led[ym == ymf & n_rows > 0, unique(Factor_Name)]
  invis <- sort(setdiff(led_set, unique(zt$Factor_Name)))
  say("%s: 커넥터 가시 %d종 · 원장 배출 %d종 · 배출O/가시X = %d종",
      ymf, uniqueN(zt$Factor_Name), length(led_set), length(invis))
}
lv <- rbindlist(res)
fwrite(lv, file.path(OUT, "p0_statistic_liveness.csv"))

say("")
say("=== 후보 통계별 판별력 (커넥터 가시분, 월 %d개 · 셀 %d) ===", uniqueN(lv$ym), nrow(lv))
chk <- function(nm, v) {
  v <- v[is.finite(v)]
  rng <- range(v)
  say("  %-14s 범위 [%.6f, %.6f] · sd %.6f · 고유값 %d  → %s",
      nm, rng[1], rng[2], sd(v), length(unique(round(v, 10))),
      if (diff(rng) < 1e-9) "★죽은 통계 (판별력 0) — 축으로 쓰면 안 됨" else "변동함 (사용 가능)")
}
chk("sd(Z)", lv$sd_z)
chk("modal_frac", lv$modal_frac)
chk("uniq_ratio", lv$uniq_ratio)

say("")
say("=== 알려진 결함이 정상 팩터와 갈리는가 (같은 면에서) ===")
KNOWN_BAD <- c("SE02_Consensus_Revision", "C08_Coverage", "L04_Bid_Ask_Proxy")
POS <- c("M26_Revenue_Mom", "V01_BM", "M01_Mom_12_1", "Q02_ROE", "C18_Earnings_CAR_3d")
for (f in c(KNOWN_BAD, POS)) {
  a <- lv[Factor_Name == f]
  if (!nrow(a)) { say("  %-26s 패널 부재", f); next }
  say("  %-26s sd_z [%.4f,%.4f] · modal_frac max %.4f · uniq_ratio min %.4f",
      f, min(a$sd_z), max(a$sd_z), max(a$modal_frac), min(a$uniq_ratio))
}
say("")
say("총 %.1fs", as.numeric(difftime(Sys.time(), t0, units = "secs")))
