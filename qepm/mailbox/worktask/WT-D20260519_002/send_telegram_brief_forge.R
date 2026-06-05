# =========================================================================
# WT-D20260519_002 — Forge Telegram Brief
# =========================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

wt_root_proj <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(wt_root_proj)

source("02_Infrastructure/telegram/telegram_notify.R")

agent_name <- "Forge"
title_kr <- "WT-D20260519_002 FORGE_DONE — 약세 예측 엔진 v1 Layer 6 ADMIT REJECT 권고 (정직한 실패 선언)"

summary_kr <- "5모델 앙상블 워크포워드 완주. G1 0/5 하드페일, 보정실패 근본원인. Layer 6 도입 거부 권고."

# Table: G1~G5 + 13 OPT bindings 요약 (2열 한정)
table_gates <- data.frame(
  "검증항목" = c("G1 하위문턱", "G2 PIT", "G3 안정성", "G4 보정",
                  "OPT4 m4상관", "OPT6 회전율", "OPT9 꼬리종속", "OPT11 DSR",
                  "아키텍트 우위 AUC", "아키텍트 우위 재현율"),
  "결과" = c(
    "0/5 통과 하드페일",
    "통과 시점이동 엄격",
    "통과 지니 0.391",
    "수치통과 의미실패",
    "0.537 통과 별개",
    "5.86 통과 여유 0.14",
    "0.75 거부임계 초과",
    "5.9 베이스 상속분",
    "0.612 통과 0.17 향상",
    "0 실패 임계 0.6"
  ),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

# KV: 핵심 수치 (한글 정통 용어, 영어 < 40% 의무)
kv_metrics <- list(
  "하위문턱 통과수"          = "0/5 하드페일 — 4창 모두 재현율 0",
  "W4 평가창 분류성능"       = "0.794 양호 — 브라이어 0.079",
  "W5 평가창 분류성능"       = "0.853 최고 — 브라이어 0.051",
  "W3 평가창 반예측"         = "0.364 — 2021-2022 코로나 후 체제전환",
  "아키텍트 기준선 분류성능"  = "0.4438 — 단순회귀 3특징",
  "포지 앙상블 평균 분류"     = "0.6117 — 격차 +0.17 향상",
  "포지 앙상블 평균 재현율"   = "0 — 기준선과 동일, 보정실패 근본원인",
  "L5 V2 4층 합격선 샤프지수" = "1.886 — 4층 합격 기준선",
  "L6 임계 0.5 256m 샤프"     = "1.865 — 격차 -0.021 후퇴",
  "L6 임계 0.7 256m 샤프"     = "1.879 — 격차 -0.007 거의동일",
  "OOS 134m L6 임계 0.7 샤프" = "1.928 — 기준선과 정확동일 발동 0회",
  "최대낙폭 전체"             = "-24.81% 변동없음 감지실패",
  "꼬리종속 TDC 측정"         = "0.75 — Joe-Clayton 임계 0.7 초과 거부",
  "회전율 임계 0.5 연간"      = "5.86 통과 — 상한 6.0 여유 0.14",
  "총비용 임계 0.5 연간"      = "176.6 거래 + 변동 위양성",
  "DSR Z 54시도 환산"         = "5.9 — L5 V2 상속분 베어센서 기여 음수",
  "특징 구축률"               = "20/32 — Phase B 12건 보류",
  "순기능 대체 선언수"        = "6건 — 학습기 대체 LightGBM XGBoost 변환",
  "AX-008 충족"               = "정직거부 1/3 + Codex REJECT 2/3 합의"
)

# Bullets (한글 풀어 쓰기, 영어 약어 ≤ 1건 per bullet)
bullets_kr <- c(
  "5모델 앙상블 정상가동 — 로지스틱 + 그래디언트 부스팅 + 랜덤포레스트 + 지연회귀 + 마르코프 전환",
  "Pure Function 통과 — 3-package 해시 시작 종료 동일, 경계 엄격",
  "정직선언 통과 — 자체합성 사용 없음, 합리화 표현 0건",
  "보정실패 근본원인 — 단순평균 확률 기저비율 0.13 근처, 임계 0.5 도달 못함",
  "체제전환 표류 — 2021-2022 코로나 후 평가창 분류 0.36 반예측, 구조변화 시그니처",
  "꼬리종속 측정 — 베어 신호와 4층 신호 꼬리 동시발화 75% 거부임계 초과",
  "운용제약 통과 — 회전율 5.86 + 종목수 20 + 가중합 1 + 유동성 2억원 베이스 상속",
  "차기 사이클 명제 — Platt 보정 필수 + 비용민감 분류기 + 임계값 최적화 + 체제별 재학습",
  "직감 적중 — 약세 예측은 한계 아닌 실험설계 부실 정확 진단, 보정누락 근본원인",
  "병행 과제 DPL_KR_v3 포지 단계 차단 — 통합검증 부득이 보류"
)

# Compose sections (telegram_notify v6 spec)
sections <- list(
  list(type = "summary", title = "요약", body = summary_kr),
  list(type = "table", title = "G1-G5 + 13 OPT 검증", df = table_gates),
  list(type = "kv", title = "핵심 수치", kv = kv_metrics),
  list(type = "bullet", title = "통찰 + 후속", items = bullets_kr)
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
