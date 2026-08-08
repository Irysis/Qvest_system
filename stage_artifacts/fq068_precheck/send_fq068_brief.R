ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
source(file.path(ROOT,"02_Infrastructure/telegram/tg_chart_pack.R"))
OUT <- file.path(ROOT,"stage_artifacts/fq068_precheck")

# 6개 설계의 정보계수 비교 (기준선 0.04 = 유의미 문턱)
charts <- tg_chart_sweep(
  labels = c("미국PPI 전체", "미국PPI 반도체내", "KR반도체(달러)",
             "KR장비(달러)", "KR반도체(원화)", "KR장비(원화)"),
  values = c(-1.12, -0.63, 1.11, -0.63, 0.72, -1.21),
  out_dir = OUT,
  title = "반도체 가격 신호 6설계 정보계수 (x100, 문턱 4.0)",
  value_label = "IC x100",
  hline = 4.0, hline_label = "유의미 문턱 0.04",
  filename = "fq068_ic_compare.png")

tg_agent_brief(
  agent = "Q-Lead",
  title = "신규 알파 발굴 — 반도체 가격 신호 3원천 검증",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "반도체 가격으로 종목을 고를 수 있는지 3개 원천으로 검증 — 신호 없음을 확인했습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 반도체 값이 오르면 어떤 종목이 오르는지 예측되는가",
           "방법: 미국 물가·한국 수출물가·장비 가격 3원천 · 최장 36년",
           "결과: 6개 설계 전부 신호 없음. 검출력은 충분했습니다",
           "의미: 이 재료는 종목 선택에 쓰지 않습니다. 다른 재료로 넘어갑니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "미탐색 여부" = "완전 신규 (과거 기록 0건)",
           "검증 원천"   = "3개 · 설계 6개 · 최장 438개월",
           "최고 정보계수" = "0.011 (문턱 0.04 대비 1/4)",
           "검출력"      = "정보계수 0.04면 t 2.7~4.1로 잡힘",
           "판정"        = "의미 있는 크기에서 음성 확정")),

    list(type = "bullet", emoji = "🚩", heading = "한계와 주의",
         items = c(
           "발표 지연 39~43일 — 주간·일간 원천은 여전히 미검입니다",
           "제외필터 소비면은 아직 안 만졌습니다 (랭킹만 검증)",
           "측정 전 전제를 1회 정정했습니다 (신선도 개선이 미미했음)",
           "코드 버그 1건 자체 적발 — 날짜 형식 불일치로 빈 병합")),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c(
           "한계는 데이터가 아니라 기전 — 원천을 3개 바꿔도 같았습니다",
           "제외필터 면 1회 확인 후 이 재료는 정리합니다",
           "업종별 경기실사지수(BSI)로 재료 교체 예정입니다",
           "실제 자본 배분에는 아무 영향 없습니다"))
  ),
  charts = charts,
  footer = "📚 FQ-068 아크 6라운드 · stage_artifacts/fq068_precheck/"
)
cat("[send] done\n")
