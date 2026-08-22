## WT-D20260822_010 — 손익 분해 + 미결/효과없음 라벨 판정 + 창-도달가능성
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_010")
say <- function(f, ...) cat(sprintf(paste0("[x] ", f, "\n"), ...))
D <- list()
O <- readRDS(file.path(OUT, "10_measure_objects.rds")); PD <- O$PD; rb <- O$rb; rf <- O$rf
M  <- fromJSON(file.path(OUT, "10_measure.json"))
PC <- fromJSON(file.path(OUT, "00_precheck.json"))

## ── 1. paired 평균의 NW 신뢰구간 (미결 vs 효과없음 분리의 근거) ────────────
x <- PD$d_active; fit <- lm(x ~ 1)
se <- sqrt(sandwich::NeweyWest(fit, lag = 3L, prewhite = FALSE)[1,1])
mu <- mean(x); ci <- c(mu - 1.96*se, mu + 1.96*se)
say("paired Δactive: mean %+.6f/월 (연 %+.4f%%p) | NW SE %.6f | 95%% CI [%+.6f, %+.6f]/월 = [%+.4f, %+.4f]%%p/yr",
    mu, 1200*mu, se, ci[1], ci[2], 1200*ci[1], 1200*ci[2])
implied_hi <- PC$gate$P2_monthly; implied_lo <- PC$gate$P1_monthly
mech_in_ci <- (implied_hi >= ci[1] && implied_hi <= ci[2])
zero_in_ci <- (0 >= ci[1] && 0 <= ci[2])
say("기전-함의 상한 P2 = %+.6f/월 (연 %+.4f%%p) → CI 안에 있나: %s | 0 이 CI 안에 있나: %s",
    implied_hi, 1200*implied_hi, mech_in_ci, zero_in_ci)
D$paired_ci <- list(mean_monthly = mu, annual_pp = 1200*mu, nw_se = se, nw_t = mu/se,
  ci95_monthly = ci, ci95_annual_pp = 1200*ci, n = length(x),
  mechanism_implied_P1_monthly = implied_lo, mechanism_implied_P2_monthly = implied_hi,
  mechanism_implied_inside_ci = mech_in_ci, zero_inside_ci = zero_in_ci,
  mde80_monthly = PC$gate$mde80_monthly, mde80_annual_pp = PC$gate$mde80_annual_pp)

## ── 2. 라벨 판정 (미결 / 효과없음 / 가려짐) ───────────────────────────────
lbl <- if (mech_in_ci) "미결(underpowered) — 기전-함의 크기가 CI 안에 있어 그 크기의 효과를 배제할 수 없다" else
       if (zero_in_ci) "효과없음(powered null)" else "유의 효과 검출"
D$label <- list(effect_detection_axis = lbl,
  capital_gate_axis = "FAIL — ΔIR 게이트는 점추정 게이트이고 점추정이 -0.0899 로 반대 부호다. 유의성과 무관하게 미충족.",
  masked_check = "가려짐 아님 — 양성 대조가 동일 창·하네스에서 ΔIR +0.1642 를 냈으므로 하네스가 눈이 먼 상태가 아니다.",
  note = "두 축은 처분이 다르다: 검출 축은 '미결', 자본 축은 '기각'. 미결을 자본 통과로 읽지 않는다.")
say("★라벨: 검출축 = %s", lbl)
say("★라벨: 자본축 = FAIL (ΔIR 점추정 -0.0899)")

## ── 3. 창-도달가능성 (양성 대조 기준) ──────────────────────────────────────
D$window_reachability <- list(
  positive_control_delta_ir = M$poscontrol$delta_ir, positive_control_paired_t = M$poscontrol$paired_nw_t,
  positive_control_annual_pp = M$poscontrol$annual_pp,
  reading = paste0("동일 창에서 MAX5 배제는 ΔIR +", round(M$poscontrol$delta_ir,4),
    " (연 ", round(M$poscontrol$annual_pp,3), "%p) 를 냈다 — 즉 이 창은 게이트급 ΔIR 을 **낼 수 있다**. ",
    "따라서 본 null 은 창의 무능이 아니다. 다만 양성 대조의 paired NW t 도 ",
    round(M$poscontrol$paired_nw_t,3), " 로 2 미만이다 — 이 하네스의 전도성은 ΔIR 점추정 수준이지 ",
    "유의성 수준이 아니다(정직 표기)."))
say("창-도달가능성: 양성대조 ΔIR %+.4f (연 %+.3f%%p, paired t %+.3f)",
    M$poscontrol$delta_ir, M$poscontrol$annual_pp, M$poscontrol$paired_nw_t)

## ── 4. 손익 분해 — 왜 기전이 참인데 성과가 나쁜가 ─────────────────────────
sb <- M$substitution
gross_swap <- sb$added_wcontrib - sb$removed_wcontrib
to_delta <- rf$turnover_annual - rb$turnover_annual
cost_delta_monthly <- -(to_delta * 0.0015) / 12
D$pnl_decomposition <- list(
  removed = list(names = sb$mean_removed_names, weight_sum = sb$removed_weight_sum,
    mean_ret = sb$removed_mean_ret, tail_rate = sb$removed_tail_rate, wcontrib = sb$removed_wcontrib,
    srank = sb$removed_srank),
  added = list(names = sb$mean_added_names, weight_sum = sb$added_weight_sum,
    mean_ret = sb$added_mean_ret, tail_rate = sb$added_tail_rate, wcontrib = sb$added_wcontrib,
    srank = sb$added_srank),
  gross_swap_monthly = gross_swap,
  tail_rate_gain_pp = 100*(sb$removed_tail_rate - sb$added_tail_rate),
  mean_ret_loss_pp = 100*(sb$added_mean_ret - sb$removed_mean_ret),
  turnover_delta_annual = to_delta, cost_delta_monthly_15bps = cost_delta_monthly,
  measured_d_active_monthly = mu,
  reading = paste0("배제는 예측대로 꼬리를 줄였다(제거군 꼬리율 ", round(100*sb$removed_tail_rate,3),
    "% → 추가군 ", round(100*sb$added_tail_rate,3), "%, ",
    round(100*(sb$removed_tail_rate-sb$added_tail_rate),3),
    "%p 개선). 그런데 대체 편입은 base 랭킹 26위 이하라 평균수익이 ",
    round(100*(sb$added_mean_ret-sb$removed_mean_ret),3),
    "%p 낮다 — 랭킹 여백 손실이 꼬리 회피 편익을 넘는다. 이것이 배제-소비 형태의 구조적 비용이다."))
say("분해: 제거 %.2f종(w합 %.4f, ret %+.4f, tail %.3f%%) → 추가 %.2f종(w합 %.4f, ret %+.4f, tail %.3f%%)",
    sb$mean_removed_names, sb$removed_weight_sum, sb$removed_mean_ret, 100*sb$removed_tail_rate,
    sb$mean_added_names, sb$added_weight_sum, sb$added_mean_ret, 100*sb$added_tail_rate)
say("  꼬리 개선 %+.3f%%p vs 평균수익 손실 %+.3f%%p | 가중기여 차 %+.6f/월 | 회전율 Δ %+.1f%%p → 비용 %+.6f/월",
    100*(sb$removed_tail_rate - sb$added_tail_rate), 100*(sb$added_mean_ret - sb$removed_mean_ret),
    gross_swap, 100*to_delta, cost_delta_monthly)

## ── 5. 기전-정합성 요약 (전부 참인데 성과는 음수) ─────────────────────────
FA <- fromJSON(file.path(OUT, "11_falsify.json"))
D$mechanism_consistency <- list(
  cross_sectional_tail = list(excluded = PC$tail_realization$lo, kept_top = PC$tail_realization$hi,
    verdict = "기전 정합 (NP2 재현)"),
  conditional_on_top25_tail = list(excluded = FA$transition_wall$table$tail_rate[2],
    kept = FA$transition_wall$table$tail_rate[1], verdict = "기전 정합 — 고-score 조건부에서도 배제군 꼬리율이 높다"),
  conditional_on_top25_mean = list(monthly_spread = FA$transition_wall$mean_spread_monthly,
    nw_t = FA$transition_wall$nw_t, verdict = "기전 정합 방향(배제군이 덜 벌었다) — 단 유의 미달"),
  falsification_fired = FA$fired_count,
  exposure_neutrality = list(size_abs = FA$N1$size_abs, vol_abs = FA$N1$vol_abs, threshold = 0.126, fired = FA$N1$fired),
  paradox = paste0("기전 진단 4축(횡단면 꼬리 · 조건부 꼬리 · 조건부 평균 · 하락일 개인지지)이 전부 정합이고 ",
    "반증 3건 전부 미발화인데 ΔIR 은 -0.0899 다. 모순이 아니다 — 기전의 참·거짓과 **그 기전을 배제 형태로 소비했을 때의 손익**이 ",
    "다른 문제이기 때문이다. 배제는 꼬리를 줄이지만 랭킹 여백을 강제로 소비한다."))

write_json(D, file.path(OUT, "12_decomp.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
