#==============================================================================
# Optimizer Telegram Brief — v6 SOT (tg_agent_brief 단일 진입점)
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
WT_ID <- "WT-D20260527_001"
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

pkg <- fromJSON(file.path("qepm/mailbox/worktask", WT_ID, "optimization_package.json"),
                simplifyVector = FALSE)

sections <- list(
  list(type = "summary",
       body = sprintf("M06_MVO_Breadth 선택 (n=15 Grinold). netIR %.3f.",
                     pkg$expected_net_information_ratio)),
  list(type = "table",
       df = data.frame(
         Method = c("M04_lam2", "M05_lam5", "M06_breadth(P)", "M02_AlphaProp(B2)", "M01_EW"),
         netIR = c("0.078 corner", "0.077 corner", "0.071 SELECT", "0.050 backup", "0.038 base")
       )),
  list(type = "bullet",
       items = c(
         sprintf("제약: 종목 %d 합 %.2f 최대 %.3f", pkg$n_names, pkg$sum_weights, pkg$max_weight),
         sprintf("스케줄 밀도 %.3f (v6.3 §9 통과)", pkg$walk_forward_diagnostics$schedule_density_ratio),
         "Codex 거부 후 자율 해결 8건 (수용 5 / 일부 2 / 반박 1)",
         "꼬리위험 초과 명시적 인정 (요청서에 한도 미선언)"
       )),
  list(type = "kv",
       kv = list(
         "순정보계수" = sprintf("%.4f", pkg$expected_net_information_ratio),
         "정보계수" = sprintf("%.4f", pkg$expected_information_ratio),
         "초과수익" = sprintf("%.2f%%/y", pkg$expected_active_return * 100),
         "추적오차" = sprintf("%.2f%%/y", pkg$expected_tracking_error * 100),
         "회전율" = sprintf("%.2f/y", pkg$turnover_analysis$annual_L1_turnover),
         "비용" = sprintf("%.2f%%/y", pkg$turnover_analysis$estimated_annual_cost * 100),
         "종목수" = sprintf("%d", pkg$n_names),
         "집중도지수" = sprintf("%.3f", pkg$hhi)
       ))
)

tg_agent_brief(
  agent = "Optimizer",
  title = sprintf("WT-D20260527_001 OPTIMIZER_DONE — M06_Breadth netIR %.3f",
                  pkg$expected_net_information_ratio),
  sections = sections,
  as_of = "2023-12-28",
  dry_run = FALSE
)
