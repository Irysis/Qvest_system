# 2026-08-08 세션 리서치 요약 텔레그램 발송 (qvest-telegram v7 SOT 준수)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
source(file.path(ROOT, "02_Infrastructure/telegram/tg_chart_pack.R"))

OUT <- file.path(ROOT, "stage_artifacts/fq141_precheck_20260808")

# 차트: 측정 창 길이별 벤치 핸디캡 (원칙 9 — 실측 수치 보고는 그래프 동반)
ts <- read.csv(file.path(OUT, "np_c3_term_structure.csv"), stringsAsFactors = FALSE)
ts <- ts[ts$len %in% c(12, 24, 36, 60, 120, 167, 220, 269, 439), ]
charts <- tg_chart_sweep(
  labels = paste0(ts$len, "개월"),
  values = round(ts$d_ann * 100, 2),
  out_dir = OUT,
  title = "측정 창 길이별 벤치마크 핸디캡 (연 %, 2026-07 종료)",
  value_label = "연 %",
  hline = 0, hline_label = "0 = 중립",
  highlight = "269개월",
  filename = "session_20260808_handicap_term_structure.png"
)

tg_agent_brief(
  agent = "Q-Lead",
  title = "전이 벽의 정체 규명 — 현행 운용 북 영향 없음",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "우리 전략이 지수를 못 이기는 원인을 추적했습니다. 현행 운용 북에는 영향이 없습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 원인이 우리 전략의 종목 크기 편향인지 확인했습니다",
           "방법: 1990년부터 439개월치를 다시 계산했습니다",
           "결과: 원인은 전략이 아니라 벤치마크에 담긴 삼성·하이닉스 급등이었습니다",
           "의미: 자본 배분은 그대로 두고, 시장이 정상으로 돌아오면 재도전합니다")),

    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "현행 북"   = "영향 없음 (연 0.79% 순풍, 판정 불변)",
           "최근 12개월" = "핸디캡 연 +69.5% (역대 상위 1%)",
           "장기 269개월" = "핸디캡 연 -1.5% (오히려 순풍)",
           "2025년 정체" = "삼성전자 51% + SK하이닉스 44%",
           "현재 상태"  = "ELEVATED — 재도전 시점 아님")),

    list(type = "bullet", emoji = "🚩", heading = "한계와 주의",
         items = c(
           "핸디캡 수치 자체는 통계적 유의성 미확립 (t값 0.87~1.82)",
           "국면 조건부 검증은 표본이 얇아 연 27.7% 효과라야 검출됩니다",
           "감시 장치는 아직 자동 실행 미배선 — 수동 재산출만 가능합니다",
           "오늘 판정·가설이 16회 뒤집혔고 다수가 저희 직전 산출이었습니다")),

    list(type = "bullet", emoji = "➡️", heading = "다음 단계",
         items = c(
           "기존 기각들은 유효 — 장기 창에서는 오히려 순풍을 받았습니다",
           "계약수주 알파 사전등록 완료 — 측정 위임 대기 중입니다",
           "프론티어 큐 결과 기록 규격 도입 여부는 도훈 결정 사항입니다",
           "감시가 정상화 신호를 내면 중형주 구성부터 재도전합니다"))
  ),
  charts = charts,
  footer = "📚 32라운드 · 산출: stage_artifacts/fq141_precheck_20260808/"
)
cat("[send] done\n")
