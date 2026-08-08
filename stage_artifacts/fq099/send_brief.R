setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

png_paths <- tryCatch(
  tg_chart_sweep(
    labels = c("영업이익", "매출", "영업현금흐름"),
    values = c(0.429, 0.429, 0.471),
    out_dir = "stage_artifacts/fq099",
    title = "교정 시 상위25 종목 일치율 (자카드) — 기준선 0.8",
    hline = 0.8),
  error = function(e) { message("chart skip: ", conditionMessage(e)); character(0) })

tg_agent_brief(
  agent = "Q-Lead",
  title = "재무 유량 데이터가 두 가지 잣대로 섞여 있었습니다 — 팩터 13.7% 영향",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "매출·영업이익 같은 항목이 어떤 종목은 3개월치, 어떤 종목은 1년치로 같은 표에서 비교되고 있었습니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 종목 고르는 재료(재무 데이터)가 제대로 정리돼 있는지 확인했습니다",
           "발견: 2014년까지는 분기(3개월), 2015년부터는 연간(12개월) 수치가 섞였습니다",
           "확인: 같은 회사 기준 연간값이 분기값의 4.3~4.7배 — 잣대가 4배 다릅니다",
           "결과: 고치면 상위 25종목 중 절반 이상이 다른 종목으로 바뀝니다",
           "의미: 지금 당장 손실은 아니지만, 종목 선별이 왜곡된 기준 위에 있습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "잣대 차이"   = "4.34~4.72배 (연간/분기)",
           "영향 팩터"   = "51 / 373 (13.7%)",
           "선별 일치율" = "자카드 0.429 (기준 0.8)",
           "왜곡 종목"   = "유니버스의 약 31%")),
    list(type = "bullet", emoji = "🚩", heading = "주의 · 한계",
         items = c(
           "정확한 TTM 파일은 이미 있는데 빌더가 다른 파일을 읽고 있었습니다",
           "왜곡은 순위 최상위가 아니라 분포 몸통에 있습니다",
           "실제 운용 북에 영향이 있는지는 아직 측정 안 했습니다",
           "고친 뒤 성과가 좋아지는지도 별도 측정 대상입니다")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "돈 관점: 자본 배정 변경 없음 — 재료 정합성 수리 건입니다",
           "수리는 신규 계산 불요 (기존 TTM 파일 결합만)",
           "FQ-099a 북 소비 경로 확정 → 그 뒤에야 북 영향 언급 가능",
           "FQ-099b 교정 후 성과 A/B 로 수리 우선순위 확정")),
    list(type = "bullet", emoji = "🔍", heading = "부수 발견",
         items = c(
           "검사기가 '영향 0건'을 두 번 냈는데 거짓이었습니다 (실제 51건)",
           "원인: 한글 섞인 문자열에서 정규식 단어경계가 조용히 실패",
           "규약 추가: 검사기의 0 은 결론이 아니라 정지 신호입니다"))
  ),
  charts = png_paths,
  footer = "📚 stage_artifacts/fq099/findings.md · FQ-099 status=measured_repair_pending"
)
cat("[fq099] telegram sent\n")
