setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
source("02_Infrastructure/telegram/telegram_notify.R")
source("02_Infrastructure/telegram/tg_chart_pack.R")

## NP-A 실측: book 7종 상단-중간 갭 (연 %, np_a_verdict.json 산출)
png <- tryCatch(
  tg_chart_sweep(
    labels = c("잔차모멘텀 M08", "목표가갭 C06", "EPS개정 C02", "서프라이즈 C01",
               "어닝개정률 C04", "옐슨부실 Q25", "이익안정 Q07"),
    values = c(6.10, 5.75, 5.02, 1.78, 3.96, -0.44, -4.29),
    out_dir = "stage_artifacts/NP_A_hump_universality/charts",
    title = "현행 북 신호 7종: 상단분위 - 중간분위 연수익 격차 (기준선 0)",
    hline = 0),
  error = function(e) { message("chart skip: ", conditionMessage(e)); character(0) })

tg_agent_brief(
  agent = "Q-Lead",
  title = "상단이 죽었다는 어제 발견은 특정 재료에 한정 — 현행 북은 반대 방향",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "어제 나온 '상위 종목에 정보가 없다'는 현상은 탈락 재료의 특징이었고, 실제 운용 북의 신호들은 상위가 중간을 이깁니다."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "질문: 어제 발견한 '상위 분위가 오히려 나쁨' 현상이 시장 전체 성질인가",
           "방법: 실제 자본이 배정된 신호 7종의 분위별 수익을 전부 쟀습니다",
           "결과: 7종 중 5종이 상위 우세, 합산 격차 연 +2.61% (t 3.31)",
           "의미: 상위 25종목을 뽑는 현행 방식은 형태상 문제 없습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 수치",
         kv = list(
           "북 7종 합산 격차" = "연 +2.61% (t +3.31)",
           "혹 형태"          = "2/7 (이익안정·부실점수)",
           "어제 재료 Q01"    = "혹이지만 유의 미달 (p .83)",
           "판정"             = "일반화 기각 — 재료 한정")),
    list(type = "bullet", emoji = "🔬", heading = "검증 결과 (별건)",
         items = c(
           "독립 검증 6개가 어제 라운드 주장 4건을 심사했습니다",
           "결론은 유지되나 서술 오류 8곳·수치 오라벨을 적발해 정정했습니다",
           "발행 데이터 하나가 유동성 기준을 어겨 결함 표지를 붙였습니다",
           "제가 제안했던 자동 선별 규칙은 근거 부족으로 철회했습니다")),
    list(type = "bullet", emoji = "🧭", heading = "신규 착수 — 인플레이션 나침반",
         items = c(
           "도훈 아이디어: 인플레 측정 → 유망 섹터 → 이익성장 상위 25종목",
           "미국 기대인플레·한국 CPI·구리가격 합성 지수로 설계 (승인 반영)",
           "참고 논문의 4국면 분할은 통계 검정 불가라 연속 조정으로 변경",
           "가설설계 단계 진행 중 — 측정 결과는 별도 보고")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c(
           "돈 관점: 자본 배정 변경 없음 — 전부 측정·검증 단계입니다",
           "매출모멘텀을 북에 더하는 한계기여 측정 진행 중",
           "인플레 나침반 가설설계 완료 시 실측 착수"))
  ),
  charts = png,
  footer = "📚 FQ-171 판정 · 적대검증 wf_73808a6b · FQ-173 착수 · 갭 귀속 기존 유지 확정"
)
cat("[npa-brief] telegram sent\n")
