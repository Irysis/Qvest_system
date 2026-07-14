setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
Sys.setenv(QM_ROOT="C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source("02_Infrastructure/telegram/telegram_notify.R")
WT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/WT_D20260715_004"
CH <- file.path(WT,"charts")
tg_agent_brief(
  agent = "Alpha",
  title = "R35 (FQ-047 P1) SP 매출-yield 소비면 재라우팅 — screen-tier 보존 + R31 '2024+ 생존' 정정",
  sections = list(
    list(type="summary",
      body="SP 매출-yield = screen-tier feature 보존. 자본 미달·수용력 micro. ★R31 '2024+ 생존'은 프레임 아티팩트, 절대신호는 pre-2024 지배."),
    list(type="bullet", emoji="📖", heading="쉬운 설명",
      items=c(
        "질문: R31이 SP(매출대비 저평가)를 '유일 2024+ 살아있는 밸류'로 지목 → 이걸 어디에 쓸까?",
        "3가지로 시험: (1)단독 동일가중(EW) 배포책 (2)기존 북에 얹는 오버레이 (3)2024+ 강건성",
        "결과1: EW 단독은 신호 진짜지만 담을 수 있는 돈이 0.5억원(초소형) → 배포 불가",
        "결과2: 오버레이로 얹으면 과거엔 도움(paired 1.88)이나 2024년 이후엔 효과 사라짐(~0)",
        "★결과3(정정): SP는 사실 옛날(2008-14·2020-23)에 강하고 2024+는 오히려 약함(2.51 vs 1.12)",
        "→ R31의 '2024+ 생존'은 대형주가중 상대비교 착시였음. SP=순환-가치·국면의존 신호",
        "결론: 자본용 아님. '보관용 feature'로 남기고 국면 반전 시 부활 대기")),
    list(type="kv", emoji="📊", heading="Part1 EW-basis 배포성 (canonical_screen 실측)",
      kv=list(
        "SP EW top-25 PORT_t"="cap-w 2.236 / EW-uni 2.758 (둘 다 <2.95 자본미달)",
        "최근 강도 (post2017 t)"="1.16 (약함)",
        "oos_v2 (과적합)"="EW 0.902 / cap-w 0.029 (EW강함=2020-23 revival 반영)",
        "수용력 (5% ADV)"="median 0.5억원 = 초소형·배포 불가",
        "P-pure 대비 상관/중첩"="0.458 / Jaccard 0.064 (<0.5 diversifying)",
        "PIT 검증"="지연1 2.758→2.182 정상감쇠 · 위약 p=0.000 (실신호)")),
    list(type="kv", emoji="🔎", heading="Part2 오버레이 + Part3 2024+ 강건성",
      kv=list(
        "오버레이 (기본 북 위)"="paired 1.882 (이전 1.96 / 2024+ -0.18)",
        "오버레이 (현직 북 위)"="paired 1.127 (이전 1.17 / 2024+ -0.03)",
        "→ 한계기여 이전기간 한정"="양쪽 북 동일 = SP-특이 감쇠 (실시간 레버 아님)",
        "SP 절대신호 부기간"="08-14: 2.28 / 15-19: -0.24 / 20-23: 2.51 / 24+: 1.12",
        "★2024+ 정정"="이전 2.508 > 이후 1.119 = 이전기간 지배 (구조 프리미엄 아님)",
        "섹터/품질"="집중도 0.10 광역(순환-가치) · 저품질함정 아님(이익수익률 중립)")),
    list(type="bullet", emoji="🚩", heading="Challenge flags (self-adversarial)",
      items=c(
        "C1 ACCEPT: 'SP 2024+ 생존' = 대형주가중 상대-vs-붕괴base 프레임 아티팩트 → R31 서사 정정",
        "C2 ACCEPT: EW-basis 배포 불가 (대형주가중 벤치 mandate + 수용력 0.5억 micro)",
        "C3 PARTIAL: 저품질함정 미지지(EP중립)이나 EP-z proxy 한계(극단꼬리 미배제)",
        "C4 ACCEPT: 2024+ 표본 29개월 얇음 → single-regime 라벨",
        "C5 REBUTTAL: SP diversifying(corr<0.5)이나 상관 낮음≠자본자격",
        "C6 ACCEPT: 오버레이 pre-2024-only가 base·incumbent 양쪽 확인 = SP-특이 감쇠")),
    list(type="kv", emoji="➡️", heading="판정 + 다음 단계",
      kv=list(
        "판정"="screen-tier feature 보존 + 배포·오버레이 config-scoped negative",
        "소비면"="선별라벨 feature · 감시선 tripwire · RAMP 조건부 입력",
        "P1"="SP를 RAMP 국면조건부 입력으로 (지금 가능, 저EV)",
        "P2"="SP 절대 rolling-24m EW PORT_t 지속>2 부활 tripwire (R31 P2 정정)",
        "부활조건"="순환-가치 레짐 부활 OR value-vs-mega 로테이션 반전",
        "무접촉"="book·05_Production·outputs.ramp. L-AR-20260715_030004"))
  ),
  charts = c(file.path(CH,"sp_ewbasisequity_curve.png"),
             file.path(CH,"sp_subperiod.png"),
             file.path(CH,"sp_overlay.png"))
)
cat("TG_DONE\n")
