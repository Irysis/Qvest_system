# =============================================================================
# np157c2_d_attribution.R — NP-157c2: 2025+ 핸디캡의 종목 귀속
#
# NP-157c 확정: 전이 벽 핸디캡 d 는 최근 18개월(2025+)이 단독 생성한다
#               (2025+ 제외 149개월 d_ann = -0.0223, 2025+ 단독 +0.4898).
# 질문: 그 18개월의 d 는 **소수 종목이 만든 사건**인가 **광범위한 레짐**인가.
#       재현 가능한 레짐이면 재측정을 미뤄야 하고, 단발 사건이면 그 구간을 통제하면 된다.
#
# 분해 (항등식):
#   d_t = Σ_i w_cap,i·r_i − (1/N)Σ_i r_i = Σ_i (w_cap,i − 1/N)·r_i
#   ⇒ 종목 i 의 기여 = (시총가중 − 동일가중) × 그 달 수익.  포트폴리오 무관.
#
# ★시장 관측만. 비중 결정·알파 산출물 없음.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
W007 <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[157c2] ", fmt, "\n"), ...))

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")

main <- function() {
  RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
          col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
  RAW[, Date := as.Date(Date)]; RAW[, ym := format(Date, "%Y-%m")]
  MEND  <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
  RAWME <- RAW[Date %in% MEND]; rm(RAW); gc(FALSE)
  META  <- readRDS(file.path(SRC5, "pool_meta.rds")); sig_all <- META$sig_all
  fwd   <- build_monthly_forward_returns(RAWME, sig_all)
  returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]

  ## EW 벤치와 동일한 유니버스 패널 (POOL_EW) — FQ-157 과 일치
  MAINP <- as.data.table(read_parquet(file.path(W007, "composite_main.parquet")))
  MAINP[, Date := as.Date(Date)]
  u <- unique(MAINP[arm == "POOL_EW" & !is.na(score), .(Date, Ticker)])

  ## 시총(Size)을 신호월 말 기준으로 부착 → cap 가중
  sz <- RAWME[, .(Date, Ticker, Size)][!is.na(Size)]
  P <- merge(merge(u, returns_dt, by = c("Date","Ticker")), sz, by = c("Date","Ticker"))
  P <- P[Size > 0]
  P[, `:=`(w_cap = Size / sum(Size), w_ew = 1 / .N), by = Date]
  P[, contrib := (w_cap - w_ew) * Ret_1m]

  ## 검산: 월별 contrib 합 == d_t
  chk <- P[, .(d_recon = sum(contrib)), by = Date][order(Date)]
  say("월별 재구성 %d개월 · 전기간 평균 d_recon = %.5f/월 (연 %.2f%%)",
      nrow(chk), mean(chk$d_recon), mean(chk$d_recon)*12*100)

  W <- P[Date >= as.Date("2025-01-01")]
  say("2025+ 구간 %d개월 · %d 종목-월", uniqueN(W$Date), nrow(W))
  say("2025+ 평균 d = %.5f/월 (연 %.2f%%)",
      mean(W[, .(d = sum(contrib)), by = Date]$d),
      mean(W[, .(d = sum(contrib)), by = Date]$d)*12*100)

  ## ── 종목별 총 기여 (2025+ 누적) ─────────────────────────────────────────
  A <- W[, .(total = sum(contrib), months = .N,
             avg_w_cap = mean(w_cap), avg_w_ew = mean(w_ew)), by = Ticker]
  setorder(A, -total)
  tot <- sum(A$total)
  A[, share := total / tot]
  say("--- 2025+ 누적 d 기여 상위 12 (총 %.4f) ---", tot)
  print(head(A[, .(Ticker, total = round(total,4), share = round(share,3),
                   avg_w_cap = round(avg_w_cap,4), months)], 12))

  ## ── 집중도 ──────────────────────────────────────────────────────────────
  A[, cum := cumsum(share)]
  n_pos <- nrow(A[total > 0])
  say("--- 집중도 ---")
  say("  기여 종목 총 %d (양수 %d)", nrow(A), n_pos)
  for (k in c(1,3,5,10,20)) {
    if (nrow(A) >= k) say("  상위 %2d 종목 누적 share = %.3f", k, A[k, cum])
  }
  ## 허핀달 (양수 기여분 기준)
  pos <- A[total > 0]; hh <- sum((pos$total/sum(pos$total))^2)
  say("  양수기여 허핀달 HHI = %.4f (1/HHI = 유효 종목수 %.1f)", hh, 1/hh)

  ## ── 상위 종목 제거 시 d 가 어떻게 되는가 (단발 사건 검정) ───────────────
  say("--- 상위 k 종목 제거 후 2025+ d_ann ---")
  for (k in c(0,1,2,3,5,10)) {
    drop <- head(A$Ticker, k)
    Wd <- W[!Ticker %in% drop]
    dk <- Wd[, .(d = sum(contrib)), by = Date]
    say("  k=%2d 제거 → d_ann = %+.4f", k, mean(dk$d)*12)
  }

  fwrite(A, file.path(OUT, "np157c2_ticker_attribution.csv"))
  saveRDS(list(A = A, monthly = chk), file.path(OUT, "np157c2_results.rds"))
  say("저장: np157c2_ticker_attribution.csv · np157c2_results.rds")
  invisible(0L)
}

main()
