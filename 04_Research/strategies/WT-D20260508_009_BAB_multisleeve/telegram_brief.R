#==============================================================================
# WT-D20260508_009 Optimizer — Telegram Agent Brief (v6 SOT)
# 2026-05-08
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ_ROOT)

source("02_Infrastructure/telegram/telegram_notify.R")

# Load final package (or draft if final not yet built)
WT_BOX <- "qepm/mailbox/worktask/WT-D20260508_009"
final_path <- file.path(WT_BOX, "optimization_package.json")
draft_path <- file.path(WT_BOX, "optimization_package_draft.json")
pkg_path <- if (file.exists(final_path)) final_path else draft_path
pkg <- fromJSON(pkg_path, simplifyVector = FALSE)

method <- pkg$method_selected
exp_ir <- round(pkg$expected_information_ratio, 3)
exp_sr_ann <- round(pkg$expected_sr_annual_forward, 3)
exp_ar_mo_pct <- round(100 * pkg$expected_active_return_monthly, 3)
exp_te_mo_pct <- round(100 * pkg$expected_tracking_error_monthly, 3)
turnover_ann_pct <- round(100 * pkg$turnover_round_trip_annual, 1)
n_names <- length(pkg$target_weights)
sum_w <- sum(unlist(pkg$target_weights))
max_w <- max(unlist(pkg$target_weights))
hhi <- pkg$hard_constraint_audit$hhi_cap$actual
semi_pct <- 100 * pkg$rf_r3_advisory$semi_pct_actual / 100  # already pct
sched_density <- pkg$walk_forward_schedule$schedule_density_ratio
hybrid_best_sr <- round(pkg$hybrid_combine_simulation$best_sr_hybrid, 3)
hybrid_best_w <- pkg$hybrid_combine_simulation$best_weight_for_new_source
delta_sr <- round(pkg$hybrid_combine_simulation$delta_sr_vs_str_only, 3)
codex_stance <- pkg$codex_critic_round$stance %||% "pending"

tg_agent_brief(
  agent = "Optimizer",
  title = "베타 차익거래 다축 품질 알파 가중치 결정 완료",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = sprintf(
           "BAB 다축 품질 multi-sleeve 알파의 정통 MVO 가중치 결정. 20종 long-only Σw=1 정합 + 운용형 직교 source 후보 4번째 자격."
         )),
    list(type = "bullet", emoji = "📚", heading = "연구 컨텍스트",
         items = c(
           "목적: 알파+공분산 하 최적 가중치 + 운용형 직교성 검증",
           "검토: 6 방법론 × 3 sector_cap regime 18 셀, 196개월 walk-forward",
           "결론: MVO 사분구간 secap40 채택 + 운용형 결합 시 샤프 +0.33"
         )),
    list(type = "kv", emoji = "📊", heading = "핵심 비교",
         kv = list(
           "샤프지수" = exp_sr_ann,
           "정보비율" = exp_ir,
           "예상 알파" = sprintf("%.2f%%", exp_ar_mo_pct),
           "회전율" = sprintf("%.0f%%", turnover_ann_pct),
           "스케줄 밀도" = sched_density
         )),
    list(type = "table", emoji = "🔬", heading = "방법 비교",
         df = data.frame(
           방법 = c("MVO 채택", "cap無", "ERC"),
           `결과` = c("정보비율 0.516 / 반도체 40%",
                      "정보비율 0.521 / 반도체 70%",
                      "정보비율 0.479 / 반도체 70%")
         )),
    list(type = "bullet", emoji = "🚩", heading = "위험 신호",
         items = c(
           sprintf("회전율 %.0f%% — 600%% 한도 초과 (RF-O3)", turnover_ann_pct),
           "공분산 조건수 754 — bounds 0.10 + 페널티로 부분 완화",
           "반도체 30% 강제 시 수학적 infeasibility, 40% 채택",
           "ES95 -10.35% — Forge 단계 보호 오버레이 검토"
         )),
    list(type = "bullet", emoji = "🌟", heading = "직교 source 가치",
         items = c(
           "운용형 STR_1715 vs candidate 월간 cor=0.0023 (진정 직교)",
           sprintf("Hybrid 시뮬: w_new=%.2f → 샤프 %.3f (+%.3f vs 단일 STR_1715 %.3f)",
                   hybrid_best_w, hybrid_best_sr, delta_sr, hybrid_best_sr - delta_sr),
           "운용형 4번째 직교 source 후보 자격 → SR 2.0 도달 path 가능"
         )),
    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c(
           "Forge 백테스트 — 196개월 walk-forward weights.csv + LW const-corr 공분산 통합",
           "회전율 1037% 자연 결과 — 사분기 리밸 / 회전 패널티 / 진입유예 buffer_zone 검토",
           "Judge Gate 0~18 — 다중검정 t값 / 디플레이티드 샤프 / PIT C1~C15 검증",
           "Hybrid 70/15/15+α 또는 60/15/15/10 검토는 Governor 단계 (Architect 3rd-source spawn 후)"
         ))
  )
)

cat("Telegram brief 발송 완료.\n")
