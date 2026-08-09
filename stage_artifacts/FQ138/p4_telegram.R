suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/FQ138")
source("02_Infrastructure/config.R"); source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")
labs <- c("계약신호 (위기국면)","중립대조 (위기국면)","계약신호 (평시)","중립대조 (평시)")
vals <- c(25.74, -1.05, -3.71, 0.65)
paths <- tg_chart_sweep(labels = labs, values = vals, out_dir = OUT,
  title = "국면별 초과수익 연율(%) — 대조군이 0이면 순풍 아님", hline = 0, highlight = 1L)
cat("[tg] chart:", paths, "\n")
tg_agent_brief(
  agent = "Q-Lead",
  title = "계약수주 신호 — 특정 시장국면에서만 통하는 것이 확인됨 (사전등록 검증 통과)",
  sections = list(
    list(type="summary", emoji="📌",
      body="대형주가 부진한 달에만 계약 신호가 통한다는 발견이, 미리 정한 규칙대로 재검증에서 살아남았습니다."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c("시도: 수주 공시가 많은 기업이 특정 시장 상황에서 더 오르는지 확인",
              "방법: 결과를 보기 전에 검증 규칙을 못 박아두고 그대로 실행",
              "결과: 해당 국면에서 연 26% 초과, 우연일 가능성은 사실상 배제",
              "의미: 아직 실제 돈은 안 넣습니다 — 자본 심사는 다음 단계")),
    list(type="kv", emoji="📊", heading="핵심 수치",
      kv=list("국면별 격차"="연 +26.1%",
              "t값"="+3.71 (기준 2.0)",
              "대조군 성과"="연 -1.1% (거의 0)",
              "가짜신호 200회"="기대치와 일치")),
    list(type="bullet", emoji="🚩", heading="주의",
      items=c("자본 배정 자격은 별도 심사 — 이번 라운드는 자격 주장 없음",
              "표본 79개월 중 해당 국면은 27개월로 짧습니다",
              "2026년 데이터에 결함 발견 — 제외해도 결과는 유지됐습니다",
              "신호 정의를 처음에 잘못 골랐다가 원본 코드로 바로잡았습니다")),
    list(type="bullet", emoji="➡️", heading="다음",
      items=c("자본 심사 기준 3종 측정 — 통과해야 실제 배정 논의 가능",
              "2026년 데이터 결함은 별도 수리 작업으로 분리",
              "왜 그 국면에서만 통하는지 기전은 아직 미해명"))),
  charts = paths,
  footer = "📚 산출: stage_artifacts/FQ138/ · 사전등록 2026-08-08"
)
cat("[tg] 발송 완료\n")
