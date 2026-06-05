#==============================================================================
# WT-D20260518_001 — Risk Research Telegram Brief
# Uses tg_agent_brief() single-entry-point per v6 SOT
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

result <- tg_agent_brief(
  agent = "Risk",
  title = "WT-D20260518_001 RISK_DONE — Sigma LW+ridge cond 91 PSD",
  sections = list(
    list(
      type = "summary",
      body = "Sigma post-ridge cond=91 PSD pass, Hill alpha 4.10, Codex 8/8 disposed."
    ),
    list(
      type = "table",
      heading = "Sigma estimator 5-candidate compare",
      df = data.frame(
        Method = c("sample", "ledoit_wolf", "gerber_rmt", "LW+ridge005", "LW+ridge010"),
        Cond_PSD = c("1.03M Y", "767k Y", "842k Y", "207 Y", "91 Y SEL"),
        stringsAsFactors = FALSE
      ),
      max_col_width = 14L,
      notes = "Selected: LW + ridge lambda=0.10 (Codex C1 PARTIAL_ACCEPT, cond<=100 mandate)"
    ),
    list(
      type = "table",
      heading = "Tail risk metrics (BM-descriptive)",
      df = data.frame(
        Metric = c("EVT shape xi", "Hill alpha k=20", "CVaR_95 EVT", "CDaR_95 BM", "VaR_95 CF"),
        Value = c("-0.070", "4.099", "0.148", "-0.752", "0.099"),
        stringsAsFactors = FALSE
      ),
      max_col_width = 18L,
      notes = "Codex C3 REBUTTAL: BM-descriptive NOT portfolio cap. Forge Stage 5 emits overlay-adjusted."
    ),
    list(
      type = "bullet",
      heading = "Crowding vs PG2 STR_1715",
      items = c(
        "cor bear vs PG2 alpha = -0.136 ORTHOGONAL_PASS",
        "TDC_lower q=0.10 = 0.077 near-zero tail dep",
        "M4 full agree = 87.7 percent REDUNDANT_WARN",
        "P M4_crisis given bear=1 = 31.4 percent"
      )
    ),
    list(
      type = "bullet",
      heading = "위험 도전 사항 다섯건",
      items = c(
        "첫번째 주성분 53.5 percent 차원축소 위협 높음",
        "기존 레짐 트리거 동시발화 87.7 percent 중복 높음",
        "역사적 스트레스 worst 마이너스 22.7 percent 월간 중간",
        "다음 단계 마흔네개 신호 전체 재구축 중간",
        "다음 단계 증분 정보 검증 디볼드-마리아노 중간"
      )
    )
  ),
  footer = "Next: Optimizer Agent spawn (or Forge cycle for full 44-feature Sigma rebuild). AX-008 1.5/3 floor (self + Codex PARTIAL post-disposition)."
)

cat(sprintf("\n[Risk Telegram] dispatch ok=%s\n",
            ifelse(is.list(result) && isTRUE(result$ok), "TRUE", as.character(result$ok))))
if (is.list(result) && !isTRUE(result$ok)) {
  cat(sprintf("  reason=%s\n", result$error %||% "unknown"))
}
