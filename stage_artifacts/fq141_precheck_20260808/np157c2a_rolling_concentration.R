# =============================================================================
# np157c2a_rolling_concentration.R — NP-157c2a: 상위-2 지배가 상시 기전인가 에피소드인가
#
# NP-157c2 판정: 2025+ 18개월 핸디캡의 95.0% 를 삼성전자+SK하이닉스가 만들었다 → "에피소드에 가깝다".
# ★이 라운드는 그 판정을 **스스로 시험**한다: 과거 18개월 롤링 창마다 상위-2 share 를 산출해
#   2025+ 가 분포의 어디에 있는지 본다. 분포가 두터우면 상시 기전이고 판정을 철회해야 한다.
#
# 주의: d 가 0 근처/음수인 창에서 share 는 불안정하다(분모 폭발). 따라서
#   ①d>0 창만 share 판정에 쓰고 ②전 창에는 절대기여 기반 HHI 를 병기한다.
#
# ★시장 관측만. 포트폴리오·비중 산출물 없음.
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")
W007 <- file.path(ROOT, "stage_artifacts/WT_D20260803_007")
SRC5 <- file.path(ROOT, "stage_artifacts/WT_D20260803_005")
say <- function(fmt, ...) cat(sprintf(paste0("[157c2a] ", fmt, "\n"), ...))

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

  MAINP <- as.data.table(read_parquet(file.path(W007, "composite_main.parquet")))
  MAINP[, Date := as.Date(Date)]
  u  <- unique(MAINP[arm == "POOL_EW" & !is.na(score), .(Date, Ticker)])
  sz <- RAWME[, .(Date, Ticker, Size)][!is.na(Size)]
  P  <- merge(merge(u, returns_dt, by = c("Date","Ticker")), sz, by = c("Date","Ticker"))[Size > 0]
  P[, `:=`(w_cap = Size / sum(Size), w_ew = 1 / .N), by = Date]
  P[, contrib := (w_cap - w_ew) * Ret_1m]

  dates <- sort(unique(P$Date)); L <- 18L
  say("전체 %d개월 · 롤링 창 %d개월 → 창 %d개", length(dates), L, length(dates) - L + 1L)

  rows <- lapply(seq_len(length(dates) - L + 1L), function(i) {
    win <- dates[i:(i + L - 1L)]
    W <- P[Date %in% win]
    A <- W[, .(total = sum(contrib)), by = Ticker][order(-total)]
    tot <- sum(A$total)
    pos <- A[total > 0]
    hhi_abs <- { a <- abs(A$total); sum((a / sum(a))^2) }
    data.table(
      win_start = min(win), win_end = max(win),
      d_ann = tot / L * 12,
      top1 = A[1, Ticker], top2 = A[2, Ticker],
      top2_share = if (tot > 0) sum(head(A$total, 2)) / tot else NA_real_,
      top2_share_pos = if (nrow(pos)) sum(head(pos$total, 2)) / sum(pos$total) else NA_real_,
      hhi_abs = hhi_abs, eff_n = 1 / hhi_abs)
  })
  R <- rbindlist(rows)

  cur <- R[win_end == max(win_end)]
  say("--- 최신 창(2025+ 해당) ---")
  print(cur[, .(win_start, win_end, d_ann = round(d_ann,4), top1, top2,
                top2_share = round(top2_share,3), eff_n = round(eff_n,2))])

  posw <- R[!is.na(top2_share) & d_ann > 0]
  say("--- d>0 창 %d개에서 top2_share 분포 ---", nrow(posw))
  q <- quantile(posw$top2_share, c(.05,.25,.5,.75,.95), na.rm = TRUE)
  print(round(q, 3))
  say("  최신 창 top2_share = %.3f → 백분위 %.1f%%",
      cur$top2_share, mean(posw$top2_share <= cur$top2_share, na.rm = TRUE) * 100)

  say("--- 전 창 유효 종목수(절대기여 HHI 역수) 분포 ---")
  print(round(quantile(R$eff_n, c(.05,.25,.5,.75,.95), na.rm = TRUE), 2))
  say("  최신 창 eff_n = %.2f → 백분위 %.1f%% (낮을수록 집중)",
      cur$eff_n, mean(R$eff_n <= cur$eff_n, na.rm = TRUE) * 100)

  say("--- 상위-2 가 삼성+하이닉스인 창 비율 ---")
  say("  %.1f%% (%d/%d)", mean(R$top1 %in% c("A005930","A000660") &
                                R$top2 %in% c("A005930","A000660")) * 100,
      sum(R$top1 %in% c("A005930","A000660") & R$top2 %in% c("A005930","A000660")), nrow(R))

  say("--- d_ann 분포(전 창) ---")
  print(round(quantile(R$d_ann, c(.05,.25,.5,.75,.95)), 4))
  say("  최신 창 d_ann = %.4f → 백분위 %.1f%%", cur$d_ann,
      mean(R$d_ann <= cur$d_ann) * 100)

  fwrite(R, file.path(OUT, "np157c2a_rolling.csv"))
  say("저장: np157c2a_rolling.csv")
  invisible(0L)
}

main()
