## WT-D20260809_001 P3 — P2 예측 반증에 대한 의무 조사
## 사전등록(p2_prediction.json) falsifier 조항: "결과를 그대로 채택하지 않고 두 측정 중 하나가 오류인지 조사"
## 혐의 1: staleness arm 이 과거월 종목을 현재월에 들고 있어 Ret_1m 결측 -> NA->0 강제(수익 위장)
## 혐의 2: K=2 비단조 + oos_retention>1 = 인공물 지문
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/WT_D20260809_001")
say  <- function(fmt, ...) { cat(sprintf(paste0("[p3] ", fmt, "\n"), ...)); flush.console() }

source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- readRDS(file.path(OUT, "p0_panels.rds"))
A <- P$A; ret <- P$ret; liq <- P$liq
S0 <- A[, .(Date, Ticker, score = M26_Revenue_Mom)][!is.na(score)]
dts <- sort(unique(S0$Date)); idx <- data.table(Date = dts, mi = seq_along(dts))
R <- as.data.table(ret)[!is.na(Ret_1m)]

stale_scores <- function(K) {
  if (K == 1L) return(copy(S0))
  ix <- copy(idx)[, blk := (mi - 1L) %/% K]
  ix[, src_mi := min(mi), by = blk]
  src <- merge(ix[, .(Date, src_mi)], idx[, .(src_Date = Date, src_mi = mi)], by = "src_mi")
  Sx <- merge(S0[, .(src_Date = Date, Ticker, score)], src[, .(Date, src_Date)],
              by = "src_Date", allow.cartesian = TRUE)
  Sx[, .(Date, Ticker, score)]
}

## ---- 혐의 1: top-25 선택분의 Ret_1m 커버리지 (계약 내장 가드와 동일 정의) ----
say("=== 혐의 1: 선택분 수익 커버리지 (NA->0 위장 여부) ===")
cov_rows <- list()
for (K in c(1L, 2L, 3L, 6L)) {
  S <- stale_scores(K)
  L <- as.data.table(liq)[, .(Date, Ticker, adv)]
  S <- merge(S, L, by = c("Date","Ticker"), all.x = TRUE)
  S <- S[is.na(adv) | adv >= 2e8][, adv := NULL]
  setorder(S, Date, -score)
  W <- S[, { n <- min(25L, .N); .(Ticker = Ticker[seq_len(n)]) }, by = Date]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  cov <- WR[, mean(!is.na(Ret_1m))]
  n_na <- WR[, sum(is.na(Ret_1m))]
  ## 결측이 몰린 달
  bym <- WR[, .(na = sum(is.na(Ret_1m)), n = .N), by = Date][order(-na)]
  say("  K=%d : 커버리지 %.4f · 결측 %d/%d 슬롯 · 최악월 결측 %d/%d (%s)",
      K, cov, n_na, nrow(WR), bym$na[1], bym$n[1], bym$Date[1])
  cov_rows[[length(cov_rows) + 1L]] <- data.table(K = K, coverage = cov, n_na = n_na,
                                                   n_slots = nrow(WR))
}
COV <- rbindlist(cov_rows)
say("  ★계약 내장 가드 문턱 = 0.95. 위 커버리지가 전부 >=0.95 면 혐의 1 기각.")

## ---- 혐의 1b: NA->0 을 '제외'로 바꾼 재측정 (위장 제거 반사실) --------------
say("=== 혐의 1b: 결측 슬롯 제외 재측정 (0-fill 대신 drop) ===")
runK_drop <- function(K) {
  S <- stale_scores(K)
  ## 결측 수익 종목을 선별 전에 제거 -> NA->0 경로 자체를 차단
  S <- merge(S, R[, .(Date, Ticker)], by = c("Date","Ticker"))
  r <- canonical_screen_bt(S, P$ret, P$bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = P$liq, liq_min = 2e8,
                           run_id = sprintf("p3_drop_K%d", K), strategy_id = sprintf("M26_drop_K%d", K),
                           diag_dual_basis = FALSE)
  data.table(K = K, n_months = r$n_months, port_t_capw = r$portfolio_alpha_t_nw_lag3,
             alpha_ann = r$alpha_annualized, turnover_ann = r$turnover_annual)
}
DROP <- rbindlist(lapply(c(1L, 2L, 3L, 6L), runK_drop))
print(DROP[, .(K, n_months, port_t_capw = round(port_t_capw, 3),
               alpha_ann = round(alpha_ann, 4), turnover_ann = round(turnover_ann, 2))])

## ---- 혐의 2: 블록 위상(phase) 의존성 — K=3 을 3가지 시작 위상으로 -----------
say("=== 혐의 2: 블록 위상 민감도 (K=3, offset 0/1/2) ===")
stale_phase <- function(K, off) {
  ix <- copy(idx)[, blk := (mi - 1L + off) %/% K]
  ix[, src_mi := min(mi), by = blk]
  src <- merge(ix[, .(Date, src_mi)], idx[, .(src_Date = Date, src_mi = mi)], by = "src_mi")
  Sx <- merge(S0[, .(src_Date = Date, Ticker, score)], src[, .(Date, src_Date)],
              by = "src_Date", allow.cartesian = TRUE)
  Sx[, .(Date, Ticker, score)]
}
PH <- rbindlist(lapply(0:2, function(off) {
  S <- stale_phase(3L, off)
  r <- canonical_screen_bt(S, P$ret, P$bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = P$liq, liq_min = 2e8,
                           run_id = sprintf("p3_ph%d", off), strategy_id = sprintf("M26_ph%d", off),
                           diag_dual_basis = FALSE)
  data.table(K = 3L, offset = off, port_t_capw = r$portfolio_alpha_t_nw_lag3,
             alpha_ann = r$alpha_annualized, turnover_ann = r$turnover_annual)
}))
print(PH[, .(K, offset, port_t_capw = round(port_t_capw, 3),
             alpha_ann = round(alpha_ann, 4), turnover_ann = round(turnover_ann, 2))])
say("  ★위상 스프레드: PORT_t %.3f ~ %.3f (폭 %.3f)",
    min(PH$port_t_capw), max(PH$port_t_capw), diff(range(PH$port_t_capw)))
say("  ★해석: 폭이 K=3 vs K=1 차이(+0.307)와 비슷하거나 크면, 그 차이는 신호가 아니라 **위상 추첨**이다.")

saveRDS(list(cov = COV, drop = DROP, phase = PH), file.path(OUT, "p3_results.rds"))
say("=== P3 완료 ===")
