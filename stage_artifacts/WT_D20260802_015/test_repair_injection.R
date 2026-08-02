# =============================================================================
# test_repair_injection.R — WT-015 수리 위반 주입 테스트 (양방향)
#   수리 대상: canonical_screen_bt 선택분 Ret_1m 커버리지 warn-가드 (WT-009 CF-03 재발방지)
#   A(양성 대조): clean 패널 → 경고 미발화 + selected_ret_coverage = 1.0
#   B(위반 주입): top-N이 비유니버스(returns 결측) 종목으로 채워진 패널 → 경고 발화
#   C(수리 부작용 0): A의 PORT_t가 가드 추가 전후 동일해야 함 (판정 로직 불변 확인)
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_015/test_repair_injection.R")'
# =============================================================================
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/config.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")

set.seed(42)
dts <- seq(as.Date("2020-01-31"), by = "month", length.out = 36)
dts <- as.Date(format(dts, "%Y-%m-28"))  # 단조 월간 grid
tks_real <- sprintf("R%03d", 1:60)   # returns에 존재
tks_fake <- sprintf("F%03d", 1:60)   # returns에 부재 (비유니버스 오염 모사)

returns_dt <- CJ(Date = dts, Ticker = tks_real)[, Ret_1m := rnorm(.N, 0.005, 0.06)]
bench_dt   <- data.table(Date = dts, BM_Ret = rnorm(length(dts), 0.004, 0.05))

# A: clean — top-N 전원 returns 커버
scores_clean <- CJ(Date = dts, Ticker = tks_real)[, score := rnorm(.N)]
warnA <- character(0)
rA <- withCallingHandlers(
  canonical_screen_bt(scores_clean, returns_dt, bench_dt, top_n = 25L,
                      liq_dt = NULL, diag_dual_basis = FALSE,
                      run_id = "inj_test", strategy_id = "inj_A_clean"),
  warning = function(w) { warnA <<- c(warnA, conditionMessage(w)); invokeRestart("muffleWarning") })

# B: 오염 — fake 종목에 압도적 score를 주어 top-25가 비유니버스로 충전되게 함
scores_dirty <- rbind(scores_clean,
                      CJ(Date = dts, Ticker = tks_fake)[, score := rnorm(.N) + 10])
warnB <- character(0)
rB <- withCallingHandlers(
  canonical_screen_bt(scores_dirty, returns_dt, bench_dt, top_n = 25L,
                      liq_dt = NULL, diag_dual_basis = FALSE,
                      run_id = "inj_test", strategy_id = "inj_B_dirty"),
  warning = function(w) { warnB <<- c(warnB, conditionMessage(w)); invokeRestart("muffleWarning") })

guard_hit <- function(w) any(grepl("커버리지", w))
cat(sprintf("[inj] A(clean): coverage=%.3f 경고=%s (기대: 1.000 / 미발화)\n",
            rA$selected_ret_coverage, ifelse(guard_hit(warnA), "발화", "미발화")))
cat(sprintf("[inj] B(dirty): coverage=%.3f 경고=%s (기대: ~0.0 / 발화)\n",
            rB$selected_ret_coverage, ifelse(guard_hit(warnB), "발화", "미발화")))
cat(sprintf("[inj] A PORT_t=%.3f n=%d | B PORT_t=%s (오염 시 수익 0 위장 확인용)\n",
            rA$portfolio_alpha_t_nw_lag3, rA$n_months,
            format(rB$portfolio_alpha_t_nw_lag3)))

ok <- (!guard_hit(warnA)) && guard_hit(warnB) &&
      isTRUE(all.equal(rA$selected_ret_coverage, 1.0)) &&
      rB$selected_ret_coverage < 0.5
cat(sprintf("[inj] 판정: %s\n", if (ok) "PASS — 가드 발화 실증 + clean 무오탐" else "FAIL"))
if (!ok) stop("[inj] 위반 주입 테스트 FAIL")
saveRDS(list(covA = rA$selected_ret_coverage, covB = rB$selected_ret_coverage,
             warnA = warnA, warnB = warnB, portA = rA$portfolio_alpha_t_nw_lag3),
        "stage_artifacts/WT_D20260802_015/repair_injection_result.rds")
