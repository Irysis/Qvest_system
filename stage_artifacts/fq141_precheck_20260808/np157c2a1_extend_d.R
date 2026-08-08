# =============================================================================
# np157c2a1_extend_d.R — d 계열을 전 가용구간으로 확장 + 정합 검증
#
# 발단: NP-157c2a1(고-핸디캡 라벨 유용성 검정) 착수 전 확인에서, 라벨이 **계산 불가**임이 먼저 문제였다.
#       NP-160b1 관측 측정 창이 12~295개월인데 내 d 계열은 167개월(WT-007 walk-forward OOS)뿐이었다.
# 실측: 유니버스 패널은 440개월(1990-01~2026-08) 가용 → 한계는 데이터가 아니라 창 선택이었다.
#
# ★정의 변경 명시: 확장 d 는 **K200∪KQ150 멤버십 유니버스**를 쓴다(스코어 패널은 1990 까지 못 감).
#   기존 d 는 POOL_EW **스코어 패널** 유니버스였다. 두 정의가 겹치는 167개월에서 **정합 검증**을 먼저 한다.
#   정합이 깨지면 확장본을 쓰지 않는다(정의가 다른 계열을 이어붙이는 것은 이 저장소가 반복 검거한 계통).
#
# ★시장 관측만. 포트폴리오·비중 산출물 없음.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
say <- function(fmt, ...) cat(sprintf(paste0("[c2a1] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")

main <- function() {
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
  MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
  RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
  say("월말 스냅 %d개월 (%s ~ %s)", length(MEND), min(MEND), max(MEND))

  ## 전 구간 forward return (계약 함수 경유 — 자체합성 아님)
  fwd <- build_monthly_forward_returns(RAWME, MEND)
  returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]

  ## 멤버십 유니버스 + Size
  uni <- RAWME[(K200 == TRUE | KQ150 == TRUE) & !is.na(Size) & Size > 0,
               .(Date, Ticker, Size)]
  P <- merge(uni, returns_dt, by = c("Date","Ticker"))
  P[, `:=`(w_cap = Size / sum(Size), w_ew = 1 / .N), by = Date]
  P[, contrib := (w_cap - w_ew) * Ret_1m]
  DX <- P[, .(d = sum(contrib), n_names = .N), by = Date][order(Date)]
  say("확장 d 계열 %d개월 (%s ~ %s) · 종목수 중앙 %d",
      nrow(DX), min(DX$Date), max(DX$Date), median(DX$n_names))

  ## ── ★정합 검증: 겹치는 167개월에서 기존(스코어 패널) d 와 대조 ──────────
  old <- readRDS(file.path(OUT, "fq157_results.rds"))$D
  old <- as.data.table(old)[, .(Date, d_old = d)]
  M <- merge(DX[, .(Date, d_new = d)], old, by = "Date")
  say("--- 정합 검증 (겹침 %d개월) ---", nrow(M))
  say("  cor(d_new, d_old) = %.5f", cor(M$d_new, M$d_old))
  say("  평균 d_new %.5f vs d_old %.5f · 평균 절대차 %.5f",
      mean(M$d_new), mean(M$d_old), mean(abs(M$d_new - M$d_old)))
  say("  최대 절대차 %.5f", max(abs(M$d_new - M$d_old)))
  ok <- cor(M$d_new, M$d_old) > 0.95
  say("  판정: %s", if (ok) "정합 — 확장본 사용 가능" else "불일치 — 확장본 사용 금지(정의 차 실재)")
  if (!ok) { say("정합 실패로 중단 — 확장 계열을 저장하지 않는다"); return(invisible(1L)) }

  ## ── 전 구간 시대 구조 ───────────────────────────────────────────────────
  DX[, year := as.integer(format(Date, "%Y"))]
  say("--- 전 구간 d_ann (5년 단위) ---")
  DX[, era5 := paste0(floor(year/5)*5, "s+")]
  print(DX[, .(n = .N, d_ann = round(mean(d)*12, 4)), by = era5][order(era5)])

  say("--- 2025+ 제외 전 구간 ---")
  say("  %d개월 d_ann = %+.4f  (전 구간 %+.4f)",
      nrow(DX[year < 2025]), mean(DX[year < 2025]$d)*12, mean(DX$d)*12)

  ## ── 18개월 롤링 d_ann 분포에서 최신 창의 위치 (표본 150 → 확장) ─────────
  L <- 18L; dts <- DX$Date
  roll <- rbindlist(lapply(seq_len(length(dts)-L+1L), function(i) {
    w <- DX[i:(i+L-1L)]
    data.table(win_end = max(w$Date), d_ann = mean(w$d)*12)
  }))
  cur <- roll[win_end == max(win_end)]
  say("--- 18m 롤링 창 %d개(확장) ---", nrow(roll))
  print(round(quantile(roll$d_ann, c(.05,.25,.5,.75,.95)), 4))
  say("  최신 창 d_ann = %.4f → 백분위 %.1f%% (구 표본 150창에서는 99.3%%)",
      cur$d_ann, mean(roll$d_ann <= cur$d_ann)*100)

  fwrite(DX, file.path(OUT, "np157c2a1_d_extended.csv"))
  fwrite(roll, file.path(OUT, "np157c2a1_rolling_extended.csv"))
  say("저장: np157c2a1_d_extended.csv · np157c2a1_rolling_extended.csv")
  invisible(0L)
}

main()
