# send_telegram.R — WT-D20260803_006 (FQ-133) 완료 브리핑
suppressPackageStartupMessages({ library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260803_006")
source("02_Infrastructure/telegram/telegram_notify.R")

charts <- file.path(OUT, "charts", c("accuracy_by_arm.png", "era_timeline.png", "detection_lag.png"))
charts <- charts[file.exists(charts)]

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260803_006 ALPHA_DONE — era 사전 추정 불가 (FQ-133 구속 관문)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "팩터가 통하는 시기는 실재하나 미리 알 수 없다 — 실시간 추정 10종 전부 기준선 미달."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("배경: 앞선 라운드에서 '팩터의 합격·불합격은 그 시기 전체가 좌우한다'가 확인됐습니다",
                   "질문: 그러면 그 시기를 미리 맞힐 수 있나 — 맞히면 세 갈래 연구가 동시에 열립니다",
                   "방법: 지금까지의 자료만 써서 다음 2년이 어떤 시기인지 매달 예측하고 채점했습니다",
                   "결과: 적중률 55.2%인데 아무 정보 없이 찍어도 50.3%라 차이가 의미 없었습니다",
                   "결정적: 시기가 실제로 바뀌는 달에는 25.9%로 동전 던지기보다 못했습니다",
                   "의미: 미리 알 수 없으므로 이 갈래는 지금 자료로는 닫힙니다 — 새 자료가 있어야 열립니다")),
    list(type = "table", emoji = "📊", heading = "적중률 — 전체 / 전환기",
         df = data.frame(
           방식 = c("기준선(정보 없이 찍기)", "핵심 추정(단절 탐지)", "6개월 엿보기",
                    "전기간 엿보기", "정답 공개"),
           `전체·전환기` = c("0.503 / 0.469", "0.552 / 0.259", "0.650 / 0.407",
                             "0.764 / 0.593", "1.000 / 1.000"),
           check.names = FALSE)),
    list(type = "kv", emoji = "🔬", heading = "판정 근거",
         kv = list(
           "평가 개월" = "203 (2007-08~2024-06)",
           "유효 독립 블록" = "5.6 (검정력 낮음, 정직 라벨)",
           "차이 유의성" = "p=0.362 (미유의)",
           "주요 전환 탐지 지연" = "24개월 / 22개월 (예측 지평 24개월 이상)",
           "era 실재 검증" = "표본 반분 상관 0.988",
           "앞 라운드 정합" = "창별 양수비율 정확 재현 (부호 일치 1.000)")),
    list(type = "bullet", emoji = "🚩", heading = "자체 적대검증 — 거짓 우위 2건을 스스로 걷어냄",
         items = c("전기간 적합 상한 0.857: 무작위 정답으로 바꿔도 0.850 — 공허해서 증거 제외",
                   "13지표 실시간 0.650: 그 구간에선 한 방향 찍기가 0.733 — 구간이 밀린 착시라 증거 제외",
                   "1개월 지연 스트레스 통과 · 정답 공개 대조 정확히 1.000 (측정 배관 정상)",
                   "미해결 위험 아님 — 두 건 다 자체 적발·기각 완료")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("자격 게이트 갈래: 현 자료 조건에서 닫힘 — 구조 판결 아님(검정력 부족 명시)",
                   "여는 조건: 시기 전환을 앞서가는 수익률 외 자료(대차·공매도 잔고 / 투자자 주체별 수급 구조)",
                   "매크로 갈래는 과거 시점 원본 미보관이라 지금은 측정 자체가 금지 — 저장 배관이 선행 과제",
                   "자본 관련 주장 없음 · 심사 대상 아님(gate_eligible=FALSE)"))
  ),
  charts = charts
)
cat("[wt006TG] sent\n")
