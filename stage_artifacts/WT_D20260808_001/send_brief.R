setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/telegram/telegram_notify.R")
tg_agent_brief(
  agent = "Q-Lead",
  title = "버려진 신호 2건을 다른 방식으로 되살릴 수 있는지 검증 — 표본 부족으로 판정 유보",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "예측력은 있는데 종목 선정에 쓰면 손해였던 신호 2개를 '거르는 용도'로 바꿔 시험했습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 순위 매기기엔 실패했지만 예측력은 살아있는 신호 2개를 재활용",
           "방법: 25종목을 뽑는 데 쓰지 않고, 나쁜 후보를 걸러내는 필터로 사용",
           "결과: 효과 방향은 나왔으나 크기가 판정 기준에 못 미쳤습니다",
           "의미: '효과 없음'이 아니라 '표본이 부족해 판단 불가'입니다 — 다른 판정입니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "필요 효과"   = "연 +4.47% / +3.02%",
           "실제 관측"   = "연 +0.79% / +0.81%",
           "최상위 베타" = "0.765 vs 시장 0.979",
           "판정"        = "INCONCLUSIVE (검정력 부족)")),
    list(type = "bullet", emoji = "🔬", heading = "기전은 부분 확립",
         items = c(
           "베타 끌림 확인: 걸러낸 뒤 남는 종목이 시장보다 훨씬 둔감(t -12.7)",
           "개인 순매수가 필터 하위에 집중 — 시가총액 통제 후에도 잔존",
           "D03의 좌측 가설은 기각 — 이탈은 오히려 최상위 저변동 구간",
           "MAX5/변동성 축 재발견 여부는 배제 못 했습니다 (결손 명시)")),
    list(type = "bullet", emoji = "🚩", heading = "주의 · 정직 보고",
         items = c(
           "타이브레이커 방식은 사전 킬스위치가 발동해 측정 자체를 안 했습니다",
           "Q01 신호는 2015년 이후 예측력이 사라졌습니다",
           "검정력 확보를 사전등록했는데 과했고, 그대로 정정 기록했습니다",
           "산출물이 형식 검사를 우회한 채 발행된 하네스 결함 1건 발견")),
    list(type = "bullet", emoji = "💡", heading = "부수 수확 — 오히려 이게 큽니다",
         items = c(
           "왜 예측력이 수익으로 안 옮겨지는지의 산술적 정체를 잡았습니다",
           "순위 예측력은 우수(t 3.50)한데 5분위 평균수익은 거꾸로 감소",
           "고변동 꼬리의 쏠린 분포가 평균을 올리는데 순위지표는 못 봅니다",
           "이건 시스템 1순위 병목의 기전 — 선별 라벨 규칙으로 제안됨")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "돈 관점: 자본 배정 변경 없음 — 재료 회수 미확립입니다",
           "NP-1 업종·규모 중립화 후 재측정 (중립화 시 예측력 1.28배 강해짐)",
           "NP-2 D03을 변동성이 아닌 왜도 축으로 재표현",
           "risk-research 로 베타 실측 승계 — 위험축 재배치 근거"))
  ),
  charts = c("stage_artifacts/WT_D20260808_001/charts/fq122_marginal.png",
             "stage_artifacts/WT_D20260808_001/charts/fq122_shape.png"),
  footer = "📚 WT-D20260808_001 (FQ-122) · alpha_package.json · metric_type=canonical_screen"
)
cat("[wt122] telegram sent\n")
