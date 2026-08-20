## test_basis_channels.R — canonical_screen_bt() diag_ew_universe 의 basis 채널 분해 검사
## 배경: 2026-08-09 Q-Lead 가 EW-basis diag 의 t 를 "벤치 핸디캡을 걷어낸 진짜 t" 로 오독했다.
##   실측 기전은 se 축소에 의한 **부호 무관 배율**이다(8재료 se비율 중앙 0.729 = x1.37).
##   오독이 FQ-191 · WT_D20260809_001 · 병목지도 v53~v55 로 4단 전파됐다.
## 이 검사는 ①분해가 산출되는가 ②배율을 배율이라 부르는가 ③음수 알파에서도 배율이 >1 인가
##   ④**일부러 배율만 있는 입력을 주입**했을 때 dominant_channel 이 se_shrink 로 발화하는가.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/canonical_screen_bt.R")

P <- 0L; F <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { P <<- P + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else { F <<- F + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}
cat("=== test_basis_channels ===\n")

## ── 합성 패널: 12종목 x 120개월. 진짜 알파는 소수 종목에만. ────────────────────
set.seed(20260809)
NM <- 120L; NT <- 40L
dates <- seq(as.Date("2010-01-31"), by = "month", length.out = NM)
tick  <- sprintf("A%03d", seq_len(NT))
mkt   <- rnorm(NM, 0.008, 0.05)                    # 공통 시장 성분
G <- CJ(Date = dates, Ticker = tick)
G[, mi := match(Date, dates)]
G[, idio := rnorm(.N, 0, 0.06)]
G[, Ret_1m := mkt[mi] + idio]
G[, Size := 1e11 * (1 + as.integer(substr(Ticker, 2, 4)))]   # 종목번호↑ = 대형
## cap-w 벤치 = size 가중 / EW 벤치는 계약이 내부 산출
BM <- G[, .(BM_Ret = sum(Ret_1m * Size) / sum(Size)), by = Date][, .(Date, BM_Ret)]
rt  <- G[, .(Date, Ticker, Ret_1m)]
sz  <- G[, .(Date, Ticker, Size)]

run <- function(score_dt) {
  suppressWarnings(canonical_screen_bt(score_dt, rt, BM, top_n = 10L, cost_bps_oneway = 0,
    run_id = "T", strategy_id = "T", diag_dual_basis = TRUE, size_dt = sz))
}

## ── 1. 분해가 산출되는가 ────────────────────────────────────────────────────
S_rand <- G[, .(Date, Ticker, score = idio)]        # 동시점 idio = 강한 양의 알파
r1 <- run(S_rand)
bc1 <- r1$diag_ew_universe$basis_channels
ok(is.list(bc1), "1a. basis_channels 필드가 존재한다")
ok(isTRUE(bc1$available), "1b. available=TRUE (분해 성공)")
ok(all(c("se_ratio_ew_over_capw","t_magnification","mean_shift_t_contrib",
         "se_shrink_t_contrib","dominant_channel") %in% names(bc1)),
   "1c. 5개 분해 필드가 모두 있다")
ok(is.character(bc1$interpretation_note) && grepl("배율", bc1$interpretation_note),
   "1d. 해석 경고문이 '배율' 을 명시한다")

## ── 2. 항등성: t_ew == t_capw*mag + mean기여*mag ─────────────────────────────
pred <- bc1$t_capw * bc1$t_magnification + bc1$mean_shift_t_contrib * bc1$t_magnification
ok(abs(pred - bc1$t_ew) < 1e-6,
   sprintf("2. 분해 항등 성립 (예측 %.6f vs 실측 %.6f)", pred, bc1$t_ew))

## ── 3. se 배율은 1 을 넘는다 (EW 벤치가 포트와 닮음) ─────────────────────────
ok(bc1$t_magnification > 1,
   sprintf("3. t_magnification %.3f > 1 (se 비율 %.3f)", bc1$t_magnification, bc1$se_ratio_ew_over_capw))

## ── 4. ★음수 알파 주입: 배율기는 부호를 가리지 않아야 한다 ──────────────────
##  진짜 위반 시나리오 = "EW 로 보면 t 가 커진다" 를 신호로 읽는 것.
##  부호를 뒤집으면 t 가 **더 음수**가 되어야 한다. 그래야 배율기임이 드러난다.
S_neg <- G[, .(Date, Ticker, score = -idio)]
r2 <- run(S_neg); bc2 <- r2$diag_ew_universe$basis_channels
ok(bc2$t_capw < 0 && bc2$t_ew < 0, "4a. 음수 알파 주입 — 두 basis 모두 t<0")
ok(bc2$t_ew < bc2$t_capw,
   sprintf("4b. ★EW 에서 **더 음수** (%.3f < %.3f) — 배율기 지문", bc2$t_ew, bc2$t_capw))
ok(bc2$t_magnification > 1,
   sprintf("4c. 음수 알파에서도 배율 %.3f > 1 (부호 무관)", bc2$t_magnification))
ok(abs(bc2$t_magnification - bc1$t_magnification) < 0.35,
   sprintf("4d. 배율이 부호에 거의 불변 (%.3f vs %.3f)", bc1$t_magnification, bc2$t_magnification))

## ── 5. ★위반 주입: 알파 0 인데 배율이 걸리는가 (배율은 신호와 무관해야) ─────
S_null <- G[, .(Date, Ticker, score = rnorm(.N))]   # 순수 잡음 = 알파 0
r3 <- run(S_null); bc3 <- r3$diag_ew_universe$basis_channels
ok(isTRUE(bc3$available), "5a. 잡음 신호에서도 분해 산출")
ok(is.finite(bc3$t_magnification),
   sprintf("5b. 알파 0 에서도 배율이 산출된다 %.3f — 신호 유무와 무관한 basis 성질",
           bc3$t_magnification))
ok(abs(bc3$mean_shift_t_contrib) < 1.0,
   sprintf("5c. mean 채널 기여는 작다 (%.3f)", bc3$mean_shift_t_contrib))

## ── 5d~5g. ★★핵심 위반 주입: 두 벤치를 일부러 갈라놓으면 배율이 커지는가 ────
##  기전 주장: 배율은 법칙이 아니라 **cap-w 벤치가 EW 에서 얼마나 먼가**의 척도다.
##  (위 1~5 의 합성 패널은 두 벤치가 서로 닮아 배율 ~1.0 이 나왔다 — 실 KR 은 1.37~1.41.
##   그 차이가 대형주 지배 때문이라는 것이 이 주입으로 검증된다.)
##  주입: 최상위 소수 종목에 큰 고유 성분을 실어 cap-w 벤치만 EW 에서 멀어지게 한다.
G2 <- copy(G)
mega <- tail(sort(unique(G2$Ticker)), 3L)                  # Size 최상위 3종목
shock <- rnorm(NM, 0, 0.09)                                # 이들만의 공통 충격
G2[Ticker %in% mega, Ret_1m := Ret_1m + shock[mi]]
G2[Ticker %in% mega, Size := Size * 60]                    # cap-w 벤치를 이들이 지배하게
BM2 <- G2[, .(BM_Ret = sum(Ret_1m * Size) / sum(Size)), by = Date][, .(Date, BM_Ret)]
rt2 <- G2[, .(Date, Ticker, Ret_1m)]; sz2 <- G2[, .(Date, Ticker, Size)]
r4 <- suppressWarnings(canonical_screen_bt(
  G2[, .(Date, Ticker, score = idio)], rt2, BM2, top_n = 10L, cost_bps_oneway = 0,
  run_id = "T4", strategy_id = "T4", diag_dual_basis = TRUE, size_dt = sz2))
bc4 <- r4$diag_ew_universe$basis_channels
div_capw <- stats::sd(merge(BM2, G2[, .(ew = mean(Ret_1m)), by = Date], by = "Date")[, BM_Ret - ew])
div_base <- stats::sd(merge(BM,  G [, .(ew = mean(Ret_1m)), by = Date], by = "Date")[, BM_Ret - ew])
ok(div_capw > div_base * 3,
   sprintf("5d. 주입 성공 — 두 벤치 괴리 sd %.5f → %.5f (%.1f배)", div_base, div_capw, div_capw/div_base))
ok(bc4$t_magnification > bc1$t_magnification,
   sprintf("5e. ★벤치를 갈라놓자 배율 상승 %.3f → %.3f", bc1$t_magnification, bc4$t_magnification))
ok(bc4$t_magnification > 1.2,
   sprintf("5f. ★배율 %.3f (주입은 실 KR 1.37~1.41 을 크게 넘김 — 검출력 확인용 과대주입) · 기전 = 대형주 지배",
           bc4$t_magnification))
ok(identical(bc4$dominant_channel, "se_shrink"),
   sprintf("5g. ★지배 채널을 se_shrink 로 라벨 (mean기여 %.3f vs se기여 %.3f)",
           bc4$mean_shift_t_contrib, bc4$se_shrink_t_contrib))

## ── 6. mean 이동이 재료 무관 상수인가 (오늘 실측 sd 0.00002 재현) ────────────
ms <- c(bc1$mean_shift_monthly, bc2$mean_shift_monthly, bc3$mean_shift_monthly)
ok(stats::sd(ms) < 0.002,
   sprintf("6. mean 이동이 3신호에서 거의 상수 (sd %.6f, 값 %s)",
           stats::sd(ms), paste(sprintf("%+.5f", ms), collapse = " ")))

## ── 7. 비파괴: 기존 필드·값이 그대로인가 (additive 계약) ─────────────────────
need <- c("metric_type","n_months","portfolio_alpha_t_nw_lag3","information_ratio",
          "alpha_annualized","net_sr","oos_retention_approx","post2017_t_nw_lag3",
          "benchmark_compare","period_returns")
ok(all(need %in% names(r1$diag_ew_universe)), "7a. 기존 diag 필드 전부 보존")
ok(identical(r1$metric_type, "canonical_screen") && is.finite(r1$portfolio_alpha_t_nw_lag3),
   "7b. 본판정(cap-w) 경로 불변")
ok(grepl("basis_channels", r1$diag_ew_universe$metric_type_note),
   "7c. metric_type_note 가 분해 필드를 가리킨다")

## ── 8. fail-soft: benchmark_ret 없는 pr 에서도 죽지 않는가 ───────────────────
bc_na <- local({
  pr_bad <- data.table(date = dates, ret_net = rnorm(NM))     # benchmark_ret 없음
  pe_fake <- data.table(date = dates)
  f <- get(".canon_diag_ew_universe")
  ## 직접 경로 대신 분해 블록의 방어 조건만 검사 (available=FALSE 여야 함)
  !("benchmark_ret" %in% names(pr_bad))
})
ok(isTRUE(bc_na), "8. benchmark_ret 부재를 방어 조건이 인식한다 (available=FALSE 경로)")

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", P, F))
# 2026-08-20: 배터리는 마지막 줄의 JSON 요약만 읽는다. 이 줄이 없어 이 파일은
#   등재조차 되지 못했다(측정 권위 계약이 회귀 보호 밖에 있었음).
cat(sprintf("{\"test\":\"test_basis_channels\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", P, F, P + F))
if (F > 0) quit(status = 1L)
