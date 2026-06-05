#==============================================================================
# WT-D20260518_001 — Optimizer Research Telegram Brief
# Uses tg_agent_brief() single-entry-point per v6 SOT
#==============================================================================
suppressPackageStartupMessages({
  library(jsonlite)
})
setwd("/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")

result <- tg_agent_brief(
  agent = "Optimizer",
  title = "WT-D20260518_001 OPTIMIZER_DONE — M05 Sequential Layer 6 Hysteresis",
  sections = list(
    list(
      type = "summary",
      body = "Bear sensor Layer 6 overlay. M05 Hysteresis selected. Codex 7/7 disposed."
    ),
    list(
      type = "table",
      heading = "Method shopping top 5 (10 cap post Codex C3)",
      df = data.frame(
        Method = c("M01 Naive tau05", "M03 EWMA", "M04 KofN", "M05 Hysteresis", "M07 Replace M4"),
        Status = c("REJ rationale", "REJ EWMA lag", "REJ symmetric", "SELECTED", "DB-A reserved"),
        stringsAsFactors = FALSE
      ),
      max_col_width = 18L,
      notes = "M11 calibrator ensemble relocated DB-B. M12 linear taper deleted (M10 dominated)."
    ),
    list(
      type = "table",
      heading = "Policy spec M05 default",
      df = data.frame(
        Field = c("beta_NORMAL", "beta_CAUTION", "beta_CRISIS", "tau_caution", "tau_crisis", "hysteresis"),
        Value = c("1.0", "0.7", "0.3", "q70 calib expanding", "q90 calib expanding", "5 pct buffer"),
        stringsAsFactors = FALSE
      ),
      max_col_width = 20L,
      notes = "Production echo: STR_1715 Layer 4 AR + Layer 5 R05 discrete scalar consistent."
    ),
    list(
      type = "bullet",
      heading = "Codex 일곱건 처리 결과",
      items = c(
        "첫번째 overlay 스키마 부분반박 underlying 보유종목 해시 추가",
        "두번째 W3 시뮬레이션 수용 완전 삭제 self synthesis 제거",
        "세번째 method shopping 열두건에서 열건으로 수용 엄격 cap",
        "네번째 비용 단위 회전율 곱 15bps 곱 두 사이드 수용 통일",
        "다섯번째 Diebold-Mariano 양 path 의무 부분수용",
        "여섯번째 위기 네단계 프로토콜 부분수용 현금슬리브",
        "일곱번째 alpha 점수 phase_a 면제 반박 경로 오타 증거"
      )
    ),
    list(
      type = "bullet",
      heading = "Forge 다섯번째 단계 의무 (세변종 백테스팅)",
      items = c(
        "첫경로 Sequential Layer 여섯 히스테리시스 디폴트 입장 p 0.15 미만",
        "두경로 교체 M4 더 엄격 분기 입장 p 0.05 미만",
        "세경로 M4 단독 통제군 기준",
        "Diebold-Mariano 전체 더하기 윈도우 다섯건 더하기 레짐 네건 층화",
        "위기 폴백 실제 최대낙폭 CVaR 현금슬리브 비중 일별 emit"
      )
    )
  ),
  footer = "Next: Forge cycle Stage 1 build full 44 features + Sigma reconstruct, Stage 4 emit p_bad_t, Stage 5 apply M05 policy + DM test + admission verdict. AX-008 1.5/3 floor (self + Codex PARTIAL post-disposition)."
)

cat(sprintf("\n[Optimizer Telegram] dispatch ok=%s\n",
            ifelse(is.list(result) && isTRUE(result$ok), "TRUE", as.character(result$ok))))
if (is.list(result) && !isTRUE(result$ok)) {
  cat(sprintf("  reason=%s\n", result$error %||% "unknown"))
}
