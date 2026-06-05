#==============================================================================
# Hypothesis A — Step 8 Telegram brief (overnight + sleep mode short)
# v6 SOT schema: type/heading/emoji + body|items|kv|df
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PROJ)

source("02_Infrastructure/telegram/telegram_notify.R")

pkg <- fromJSON(file.path("qepm/mailbox/worktask/WT-D20260528_003/alpha_package_A.json"),
                simplifyVector = FALSE)

# Section 1: Summary (1-line verdict)
sec1 <- list(
  type = "summary",
  emoji = "📌",
  heading = "Verdict",
  body = "Distribution Moments Pure (D43+D44) multi-sleeve — graduation FAIL 2/6, TERMINATE 권고."
)

# Section 2: 핵심 metrics 표 (mobile-safe: ncol<=2 enforced)
sec2 <- list(
  type = "kv",
  emoji = "📊",
  heading = "핵심 metrics (PIT-clean, t-1 liquidity)",
  kv = list(
    "정보계수 안정성 (D43 워크포워드)" = "+0.232",
    "다중검정 t값 (복합 가설 NW 보정)" = sprintf("%+.2f (기준 %.2f 본페로니)",
        pkg$diagnostics$harvey_t_stat_composite_nneg,
        pkg$diagnostics$harvey_threshold),
    "단조성 (D43 / D44)" = "-0.20 / -0.46 (역전)",
    "조정 샤프지수 p값" = "0.376 (기준 0.50)",
    "위기/평상 정보계수 비율" = "D43 +3.61 / D44 +7.41 (취약 잔존)",
    "다중슬리브 vs 단일슬리브" = "-33.3% (메커니즘 실패)",
    "연환산 회전율" = "6.98 (한도 6.0 초과)"
  )
)

# Section 3: Challenge flags
sec3 <- list(
  type = "bullet",
  emoji = "🚩",
  heading = "도전 신호 11건 중 핵심",
  items = c(
    "단조성 붕괴 (높음) — Boyer-Mitton-Vorkink 2010 복권 선호 가설 한국 시장 역전",
    "다중검정 통과 0/3 (높음) — 시도 횟수 분쟁 미해결로 임계값 추가 상승 위험",
    "다중슬리브 평가 음수 (중간) — D43 단일 20종 대비 36% 열세, 회피 메커니즘 실증 미달",
    "다중검정 통과 후에도 verdict 동일 — 시점 t-1 유동성 + 비음 가중치 적용 후 합격 기준 2/6"
  )
)

# Section 4: Codex Round + 다음
sec4 <- list(
  type = "bullet",
  emoji = "➡️",
  heading = "Codex 비판 + 다음 단계",
  items = c(
    "Codex 거부 (REJECT) — 비판 7건 + 반론 의무 5건 모두 처리",
    "수정 적용: 시점 t-1 유동성 + 비음 가중치 + 미래수익 격리 + 가설 A 전용 계보",
    "방어형 잔존 신호 철회 — 위기 11개월 표본만 + 핵심 낙폭 비교 미산출",
    "발굴 작업 종료 — 위험/최적화/주조 단계 미진입",
    "다음 가설 권고: D43 단일 50종 이상 또는 장기-단기 (다중슬리브 회피 예외 2번 또는 3번)"
  )
)

# Dispatch — lock_scope override for hypothesis A
res <- tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260528_003 hypothesis A — ALPHA_DONE FAIL/TERMINATE",
  sections = list(sec1, sec2, sec3, sec4),
  as_of = "2026-05-28",
  lock_scope = "Alpha_WT-D20260528_003_overnightA"
)

cat("Telegram dispatch result:\n")
print(res)
