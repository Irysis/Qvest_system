## FQ-143 P13 — 텔레그램 보고 (tg_agent_brief 단일 진입점)
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
DIR <- file.path(ROOT, "stage_artifacts/fq143_tail_overlay_20260809")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260809_002 ALPHA_DONE — 큰 하락 표적 오버레이: 라벨은 살고 레버가 죽었다",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "국면 라벨은 진짜 꼬리 검출기이나 노출 축소로 바꾸면 손해다 — 현행 대비 짝지은 t -1.84, 최대낙폭 개선 0.00%pt."),

    list(type = "bullet", emoji = "\U0001F4D6", heading = "쉬운 설명",
         items = c(
           "[비유] 라벨은 '오늘 사고가 나면 크게 난다'는 예보다. 그런데 '사고가 날지'는 못 맞힌다",
           "[그래서] 그 예보를 듣고 차를 세우면(노출 축소) 사고는 못 피하고 못 간 거리만 손해",
           "[숫자] 라벨이 켜진 달의 평균 수익이 오히려 더 높았다 (+4.01% vs +3.41%)",
           "[결론] 라벨을 버리는 게 아니라 쓰는 자리를 바꿔야 한다 — 노출 레버 말고 경보·위험모델")),

    list(type = "kv", emoji = "\U0001F4CA", heading = "핵심 수치 (269개월 배포창, 15bps 반영)",
         kv = list(
           "라벨 꼬리 적중배수" = "2.67 (전표본 428개월, p 3.15e-06)",
           "브리핑 인용치 정정" = "3.19 -> 2.67 (동월 정렬 미래참조 15.8% 부풀림)",
           "현행 대비 짝지은 t값" = "-1.84 (깊이 30/50/70% 전부 동일)",
           "정보비율 변화" = "-0.156 (t값과 부호 일치)",
           "최대낙폭 변화" = "0.00%pt (연복리수익률만 -2.69%pt)",
           "오라클 천장" = "t +3.18 / 최대낙폭 -2.09%pt (미래 예지 시)",
           "필요 적중배수" = "10.8~16.2 (실측 2.1~2.7 — 5~6배 부족)")),

    list(type = "bullet", emoji = "\U0001F52C", heading = "기전 — 왜 안 되는가",
         items = c(
           "라벨 발화월 변동성 1.58~2.14배, 방향 정보는 0 (변동성 통제 후 t=+0.01)",
           "선형 노출 레버는 조건부 '평균'만 수확하는데 그 평균이 양수라 축소가 손해",
           "현행 오버레이가 이미 최대낙폭 40.7%->23.3% 회수 — 잔여 여지가 2%pt뿐",
           "라벨은 현행 오버레이의 실제 최대낙폭 구간에 아예 켜지지 않는다")),

    list(type = "bullet", emoji = "\U0001F6A9", heading = "검증 통과 항목",
         items = c(
           "PIT 3종 — assert_overlay_pit 269/269 통과, lag1 스트레스 유지",
           "strict A/B가 브리핑 인용 수치의 미래참조를 검출 (15.8~16.4% 부풀림)",
           "오라클 양성대조 t +3.03/+5.87 = 계측 생존 실증 (음수는 진짜 결과)",
           "무정보 대조 t -4.75 = 판별력 없는 신호의 발화-비례 유해성 재현",
           "사전선언 반증 2축 모두 생존 — 가설이 아니라 레버가 기각됐다",
           "자본 주장 0건. governor·book_state 미접촉, 05_Production 읽기 전용")),

    list(type = "bullet", emoji = "\U0001F4A1", heading = "다음 탐침",
         items = c(
           "NP-1 라벨을 무비용 경보로 소비 (상방을 포기하지 않으므로 보험료 0)",
           "NP-2 라벨을 위험모델 입력으로 — 변동성을 재는 신호의 제자리는 공분산 쪽",
           "NP-3 노출 대신 집중도를 조이는 변형 (25종 상한 안쪽 이동, 제약 완화 아님)",
           "NP-4 라벨 저장 패널의 vintage 확보 — 양성 소비 승격의 선행 조건",
           "[주의] 브리핑의 FQ-143 은 원장에서 무관한 항목(CV_Vol) — 발번 정정 필요"))
  ),
  charts = c(file.path(DIR, "chart_lift.png"), file.path(DIR, "chart_ceiling.png"))
)
cat("[telegram] sent\n")
