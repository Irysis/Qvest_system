suppressWarnings(suppressMessages({
  library(data.table)
  library(jsonlite)
}))
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/config.R")
source("C:/Users/99922/OneDrive/Quant_Module_Moltbot/02_Infrastructure/telegram/telegram_notify.R")

result <- tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "alpha-search queue 20260802 (MAX_ALPHA=2)",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(
      heading = "queue run result",
      type    = "bullet",
      items   = c(
        "MAX_ALPHA=2 | QUARANTINE=2 | ADOPT=0 | skip=0",
        "[1] C_VolRankStability_3M (2607.27461) QUARANTINE F -- OOS=0.045 Calmar=0.108 MDD=62%",
        "[2] T_RetAutoCorr_12M (2607.19497 2nd signal) QUARANTINE F -- OOS=0.24 Calmar=0.15 MDD=61%"
      )
    ),
    list(
      heading = "easy explanation",
      type    = "bullet",
      items   = c(
        "Tested 2 signals today: vol rank change + monthly return autocorrelation",
        "Both failed standalone long-only portfolios (MDD >60%, OOS <0.5)",
        "Autocorr has real cross-section premium FMB t=2.74 -- can be reused as overlay",
        "vol-rank 2 consecutive failures -- KR further search EV is low"
      )
    ),
    list(
      heading = "T_RetAutoCorr key metrics",
      type    = "kv",
      kv      = list(
        "등급" = "F | Score=7.3/100",
        "연복리수익률" = "9.2% (BM대비 -1.7%p)",
        "샤프지수" = "0.366",
        "최대낙폭" = "61.2%",
        "칼마지수" = "0.150 (기준 0.64 미달)",
        "OOS유지율" = "0.24 (기준 0.5 미달)",
        "FMB t값" = "2.74* (p<0.01) 횡단면 프리미엄 통계 유의",
        "포스트2017" = "SR비율 0.52 감쇄 확인"
      )
    ),
    list(
      heading = "next probe",
      type    = "bullet",
      items   = c(
        "FQ-094: autocorr 역방향 -- 고자기상관 종목 반전 후보",
        "FQ-095: autocorr x BearProb 오버레이 -- 강세장 지속성 conditional",
        "비-return lane: FQ-001~005 (공매도잔고·insider·담보) 우선순위 높음"
      )
    )
  )
)

cat("[queue_summary_tg] ok=", result$ok, "| bytes=", result$bytes, "\n")
