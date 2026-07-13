`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
lcode <- "L-AR-20260713_191430"
CH <- file.path(ROOT,"stage_artifacts/WT_D20260713_008/charts")
charts <- file.path(CH, c("01_independent_firms.png","02_lift_by_definition.png","03_controlled_or.png","04_size_tier.png"))
charts <- charts[file.exists(charts)]

r <- tg_agent_brief(
  agent="Alpha",
  title="제출지연 x 심각사건 (R24 · 전체-필러+에피소드 설계): 동결 1차기준은 성립 못함(임의지각으로 희석), 그러나 R23 검정력 벽 해소 — 극단꼬리는 독립회사 6->27개로 강건, 단 소형주 국소",
  charts=charts,
  sections=list(
    list(type="bullet", emoji="🎯", heading="연구 컨텍스트 (한글)", items=c(
      "R23 벽 = 배포 유니버스 내 독립 지각제출 회사 6개뿐(검정력 벽, 신호부재 아님)",
      "R24 = R23 처방 결합: (P1) 측정가능 최대 유니버스 + (P2) 에피소드 단위 설계",
      "Stage-1 지식 라운드 — 예측 성립만 판정, 자본/필터 주장 없음(2단 분리)",
      "DART API 미사용(로컬만). 무-API상 제출지연 데이터는 677종목 상한")),
    list(type="bullet", emoji="📖", heading="쉬운 설명", items=c(
      "시도: 연차보고서를 아주 늦게 낸 회사가 1년 내 상폐·관리·불성실 사고를 더 내는지",
      "R23 문제: 배포 유니버스 대형주는 지각이 드물어 독립 사례 6개뿐 -> 확정 불가",
      "R24 개선: 회사-연도 1건=1관측 + 유니버스 확대 -> 독립 사례 27개로 강건해짐",
      "반전1: 동결한 '최악10%'가 '조금이라도 늦은 전부'로 넓어져 신호 희석 -> 미성립",
      "반전2: 진짜 신호는 극단지각 소수에만(사고율 10배), 그마저 전부 소형주",
      "결론: '극단지각 소형주=위험'은 강건 재현이나 배포 유니버스 밖 이야기")),
    list(type="kv", emoji="📊", heading="핵심 실측 (표적=12개월 내 상폐·관리·불성실)", kv=list(
      "독립 회사 수"="R23 6개(취약) -> R24 극단꼬리 27개(LOO 全생존)",
      "동결 1차기준(임의지각)"="1105에피소드/528회사 · Lift 1.23 · 부트 CI[0.86,1.62]∋1",
      "동결 1차 승산비"="연도통제 2.34 (p=0.051 근소 미달) · no-FE 1.33 (p=0.14)",
      "극단꼬리 진단"="29에피소드/27회사/6사고 · Lift 10.0 · 부트 CI[3.5,17.3]∌1",
      "극단꼬리 승산비"="연도통제 6.19 (p<0.001) · LOO 27회사 全생존(최소 5.38)",
      "연속 지연-상폐"="승산비 1.10 (p 0.19)=평평=비단조·극단꼬리 집중(R22/R23)",
      "사건 구성"="관리 16 · 불성실 7 · 상폐 2 (공시일자 지정 지배=아티팩트 아님)")),
    list(type="kv", emoji="🔬", heading="규모 분해 (소형주 재발견 여부 점검)", kv=list(
      "극단꼬리 사고 분포"="소형 6 / 중형 0 / 대형 0 (전부 소형주)",
      "소형 내 Lift"="12.2배(소형 기저율 0.035) — 규모 통제후 승산비 6.2 생존",
      "구조적 함의"="대·중형 극단지각 15에피소드 0사고 -> R23 기아는 구조",
      "자본 관련성"="배포 유니버스 밖 소형주 국소 -> 확정돼도 적용성 제한")),
    list(type="kv", emoji="🗺️", heading="커버리지 조사 (정직 유니버스 축소·동결)", kv=list(
      "측정가능 종목수"="677종목(과거 K200∪KQ150 합집합)=제출지연 데이터 상한",
      "전체 원자료 종목"="3,914종목(사건측면은 전체)이나 제출일은 677에만 존재",
      "정직 축소 사유"="무-API로 전체~2500 불가 -> 실측·동결(우회 없음)",
      "생존편향 방향"="상장폐지 소형주 부재=상폐 과소관측=양성에 보수적")),
    list(type="bullet", emoji="⚖️", heading="판정 평문", items=c(
      "판정 = CONFIG_SCOPED_NEGATIVE (동결 1차기준 미성립) + 프론티어 유지",
      "성립=부실 조기경보 지식 확보이나 동결 기준 미성립(희석) — 투자 적용은 다음 단계",
      "R23 검정력 벽 해소: 극단꼬리 독립회사 6->27, 부트스트랩 CI가 1 배제=강건 재현",
      "goalpost 규율: 동결 1차기준이 판정 권위 — 극단꼬리로 갈아타 성립선언 금지",
      "핵심 지식: '극단지각 연차보고->심각사고'는 참이나 배포 유니버스 밖 소형주 국한")),
    list(type="bullet", emoji="➡️", heading="다음 단계 (next_probe 3건)", items=c(
      "P1: 극단꼬리 정의를 association 前 사전등록한 확정 라운드(강건성 이미 확인)",
      "P2: 소형주 coverage 확장(예약 크롤/disc_ck)으로 극단꼬리 사고수(현재 6) 확대",
      "P3: 지정공시-only 채널(관리+불성실=공시일자) 분리 사전등록으로 최청정 검정")),
    list(type="kv", emoji="🔒", heading="감사", kv=list(
      "사전등록 해시"="e13d4251 (coverage census 후·association 무관측 상태에서 동결)",
      "라벨 PIT 경화"="disc_ck 교차 89% 동월(중앙값 0) = 백데이팅 미래참조 없음(R23 재사용)",
      "선택 유형"="chain / n_trials=1 (단일 feature·문턱·표적·설계 = confirmatory)",
      "DART API 호출"="0 (로컬 아카이브만)",
      "학습코드"=lcode))
  )
)
cat("[telegram] ok =", isTRUE(r$ok) %||% FALSE, " ", r$error %||% "", "\n")
