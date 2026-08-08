# =============================================================================
# fq157_d_era_structure.R — FQ-157: 전이 벽 핸디캡 d 의 시대·국면 구조
#
# NP-A 확정: d = (cap-w 유니버스 벤치 − EW 유니버스 벤치) 는 arm 무관 상수이며
#            2012-08~2026-06 에서 연 +3.82%. 다른 창(n=96)에서는 2.46배였다.
# 질문: d 는 시대 의존인가. 축소되는 국면이 실재하면 같은 알파가 그 국면에서
#       cap-w 를 통과할 수 있다 = 국면-조건부 자본 자격이라는 미측정 면.
#
# ★포트폴리오 무관: 벤치마크 두 계열만 쓴다(비중·알파 산출물 없음).
# 자체합성 금지: 연도/국면 집계는 월수익 평균(기술통계)이며 포트 수익 구성 아님.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
W007 <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[fq157] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")

main <- function() {
  ## ── 1. 두 벤치 월별 계열 재구성 (NP-A 와 동일 vintage) ────────────────────
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
  MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
  RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
  META  <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
  fwd   <- build_monthly_forward_returns(RAWME, sig_all)
  returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
  bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]

  ## EW 벤치 = POOL_EW arm 의 패널 유니버스 (NP-A 에서 arm 간 차이 미미 실증)
  MAINP <- as.data.table(read_parquet(file.path(W007, "composite_main.parquet")))
  MAINP[, Date := as.Date(Date)]
  u  <- unique(MAINP[arm == "POOL_EW" & !is.na(score), .(Date, Ticker)])
  ew <- merge(u, returns_dt, by = c("Date","Ticker"))[, .(ew = mean(Ret_1m)), by = Date]

  D <- merge(bench_dt, ew, by = "Date")[Date >= as.Date("2012-08-31") & Date <= as.Date("2026-06-30")]
  D[, d := BM_Ret - ew][, year := as.integer(format(Date, "%Y"))]
  say("월 관측 %d · 전기간 d 평균 %.4f%%/월 (연 %.2f%%)", nrow(D), mean(D$d)*100, mean(D$d)*12*100)

  ## ── 2. 연도별 분해 ────────────────────────────────────────────────────────
  BY <- D[, .(n = .N, d_mean_m = mean(d), d_ann = mean(d)*12,
              capw_ann = mean(BM_Ret)*12, ew_ann = mean(ew)*12,
              d_pos_share = mean(d > 0)), by = year][order(year)]
  say("--- 연도별 d (cap-w 벤치 − EW 벤치) ---")
  print(BY[, .(year, n, d_ann = round(d_ann,4), capw_ann = round(capw_ann,4),
               ew_ann = round(ew_ann,4), d_pos_share = round(d_pos_share,3))])

  ## ── 3. 시대 분할: 2017 mega 레짐 가설 ─────────────────────────────────────
  D[, era := ifelse(year <= 2016, "pre2017", "post2017")]
  ERA <- D[, .(n = .N, d_ann = mean(d)*12, sd_m = sd(d), d_pos_share = mean(d > 0)), by = era]
  say("--- 시대 분할 (2017+ mega 레짐 가설) ---"); print(ERA)
  tt <- t.test(D[era == "post2017", d], D[era == "pre2017", d])
  say("post2017 − pre2017 월 d 차 = %.5f · t = %.3f · p = %.4f",
      diff(rev(tt$estimate)), tt$statistic, tt$p.value)

  ## ── 4. 국면 라벨별 분해 (regime_daily_v2 월말 스냅) ───────────────────────
  reg_path <- ".cache/regime_daily_v2.parquet"
  if (file.exists(reg_path)) {
    RG <- as.data.table(read_parquet(reg_path))
    RG[, Date := as.Date(Date)]
    lab_col <- intersect(c("regime","state","label","regime_label"), names(RG))
    if (length(lab_col)) {
      lc <- lab_col[1]
      RGm <- RG[Date %in% D$Date, c("Date", lc), with = FALSE]
      setnames(RGm, lc, "regime")
      DR <- merge(D, RGm, by = "Date")
      if (nrow(DR) > 0) {
        RR <- DR[, .(n = .N, d_ann = mean(d)*12, d_pos_share = mean(d > 0)), by = regime][order(-n)]
        say("--- 국면 라벨별 d (컬럼 '%s', 매칭 %d/%d월) ---", lc, nrow(DR), nrow(D))
        print(RR)
      } else say("국면 병합 0행 — 월말 Date 불일치(라벨 패널은 일간). 연도 분해만 유효")
    } else say("regime 라벨 컬럼 미발견: %s", paste(head(names(RG), 12), collapse = ", "))
  } else say("regime 패널 부재 — 연도/시대 분해만")

  saveRDS(list(D = D, by_year = BY, by_era = ERA), file.path(OUT, "fq157_results.rds"))
  fwrite(BY, file.path(OUT, "fq157_d_by_year.csv"))
  say("저장: fq157_results.rds · fq157_d_by_year.csv")
  invisible(0L)
}

main()
