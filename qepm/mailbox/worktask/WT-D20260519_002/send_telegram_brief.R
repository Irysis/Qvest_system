# =========================================================================
# WT-D20260519_002 — Optimizer Telegram Brief
# =========================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

wt_root_proj <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(wt_root_proj)

source("02_Infrastructure/telegram/telegram_notify.R")

agent_name <- "Optimizer"
title_kr <- "WT-D20260519_002 OPTIMIZER_DONE — 약세 예측 엔진 v1 sensor overlay policy Phase A"

summary_kr <- "Codex 7 disposition 완료. Q-Lead escalate. Path B Layer 6 default. TO 5.888 PASS. Forge 13 binding."

# Table: 7 비평사항 처리 (2열 한정, 한글 풀어 쓰기)
table_concerns <- data.frame(
  "사안" = c("1번 치명", "2번 치명", "3번 상", "4번 상", "5번 상", "6번 상", "7번 중"),
  "처리방향" = c(
    "부분수용 일정생성",
    "부분수용 5.888 통과",
    "부분수용 예외선언",
    "완전수용 356.6",
    "부분수용 일정통합",
    "부분반론 자료정합",
    "부분수용 신규5건"
  ),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# KV: 핵심 수치 (named list — 한글 키 의무, 영어 ≤ 40%)
kv_metrics <- list(
  "연간 회전율 전체"   = "5.888 통과 (상한 6.0, 여유 0.112)",
  "거래수수료 연간bp"  = "176.6 (회전율 5.888 곱 30bp)",
  "총비용 τ=0.5 연간"   = "356.6 베이시스포인트 재현가능",
  "순효과 τ=0.5 사전"   = "-30bp (선행시간 가치 위주)",
  "순효과 τ=0.7 보수"   = "+25bp (경계상 양호)",
  "겹침방지 일정 개월" = "267개월 2004-02~2026-04",
  "베어계수 분포"      = "1.0=250 / 0.7=15 / 0.5=2",
  "포지 검증 조건수"   = "13개 (기본 8 + 신규 5)",
  "디플레이트 시도수"  = "54 (베일리-LdP 임계 1.5)",
  "공리008 충족도"     = "1/3 (포지+아키텍트 대기)"
)

# Bullets: ≤ 80자 strict, 영어 약어 ≤ 1건 per bullet
bullets_kr <- c(
  "6개 본질 수정 모두 반영 (범위면제 + 일정파일 + 회전율 + 비용공식 + 자료정합)",
  "일정파일 267개월 15컬럼 (베어계수 + 현금비중 + 전환사건 시점 명시)",
  "단일월 지속규칙 적용 — 사후 학습엔진 실측치 대체 의무 부과",
  "자기합리화 4건 모두 정상화 (표면적 표현 → 측정값 기반 재기술)",
  "총괄리드 격상 사건 기록 (심각도 6 임계 5 도과)",
  "표준 5층 기본 선정 (해석가능 + 계보 일관 + Kritzman 2011 인용)",
  "후속단계 포지 가동 (검증조건 13건 의무 + 병행 과제 연동)"
)

# Compose sections (telegram_notify v6 spec)
sections <- list(
  list(type = "summary", title = "요약", body = summary_kr),
  list(type = "table", title = "Codex 7 Disposition", df = table_concerns),
  list(type = "kv", title = "핵심 수치", kv = kv_metrics),
  list(type = "bullet", title = "후속 + 통찰", items = bullets_kr)
)

# Send
result <- tryCatch({
  tg_agent_brief(
    agent = agent_name,
    title = title_kr,
    sections = sections,
    force = TRUE
  )
}, error = function(e) {
  cat("ERROR: ", conditionMessage(e), "\n")
  return(invisible(NULL))
})

cat("\n=== Telegram brief sent ===\n")
cat("agent: ", agent_name, "\n")
cat("title: ", title_kr, "\n")
