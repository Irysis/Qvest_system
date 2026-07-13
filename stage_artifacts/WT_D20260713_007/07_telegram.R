`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
lcode <- "L-AR-20260713_183418"
CH <- file.path(ROOT,"stage_artifacts/WT_D20260713_007/charts")
charts <- file.path(CH, c("01_severity_lift.png","02_controlled_or.png","03_fragility.png","04_label_hardening.png"))
charts <- charts[file.exists(charts)]

r <- tg_agent_brief(
  agent="Q-Lead",
  title="제출지연 x 심각사건 한정 재과녁(R23): 방향은 예측대로 집중(2.07->3.74·명목 p 0.011 통과)이나 47건이 단 6개 회사 = 강건히 성립 못함, 프론티어 유지",
  charts=charts,
  sections=list(
    list(type="bullet", emoji="🎯", heading="연구 컨텍스트 (한글)", items=c(
      "R22가 post-hoc 채택을 거부한 부분집합(심각사건만)을 신규 사전등록으로 정당 재검",
      "표적: 향후 12개월 내 상폐·관리종목 지정·불성실공시 지정 (단기 거래정지 제외)",
      "신호: 제출지연 최악 10퍼센트(R22 정의 그대로 동결) — 문턱 재선택 없음",
      "본 라운드는 예측 성립만 판정 — 성립해도 자본·필터 주장 금지(2단 분리)")),
    list(type="bullet", emoji="📖", heading="쉬운 설명", items=c(
      "시도: 연차보고서를 아주 늦게 낸 회사가 1년 안에 상폐·관리종목 사고를 더 내는지 확인",
      "R22 문제: 짧은 거래정지까지 섞으니 신호가 묽어져 아슬하게 미달(p 0.075)이었음",
      "이번: 짧은 거래정지를 빼니 사고율이 평균의 3.7배로 뚜렷해지고 통계도 명목상 통과",
      "함정: 그 3.7배가 사실 단 6개 회사 이야기 — 한 회사가 늦게 내면 12개월 내내 같은 사고를 가리켜 47건처럼 보일 뿐",
      "결론: 방향은 맞지만 '독립된 회사 사례'가 6개뿐이라 통계로 확정 불가 -> 성립 아님, 다음은 전체 공시 회사로 확대")),
    list(type="kv", emoji="📊", heading="핵심 실측 (표적=향후 12개월 내 상폐·관리종목·불성실공시)", kv=list(
      "합집합 Lift 변화"="R22 2.07배(단기정지 포함) -> R23 3.74배(심각사건만) — 예측대로 집중",
      "통제 전/후 승산비"="4.08 -> 3.43 (거의 안 줄어듦 = 소형주 위장 아님)",
      "명목 1차 기준"="통제후 승산비 3.43 · cluster-robust p 0.011 통과",
      "검정력 벽 (핵심)"="47건 사고 = 단 6개 종목 · 티커-부트 CI [0.95,7.25] 1 포함",
      "종목 제거 검정"="사고보유 6종목 중 3종목 각각 빼면 p>=0.05로 붕괴",
      "사건유형별 Lift"="상폐 6.38 · 관리 4.24 · 불성실 3.82 (R22 일치)",
      "연속 지연-상폐 hazard"="승산비 1.18 (p 0.62) = 극단꼬리·비단조(R22 재확인)",
      "시대 안정성"="전 신호 2016년 이후 · 2016년 이전은 추정 불가(지각제출 표본 없음)")),
    list(type="kv", emoji="🔬", heading="사건 라벨 PIT 경화 (R22 P3 실행 — 백데이팅 미래참조 배제)", kv=list(
      "원천"="disc_ck 공시목록 506,874행·348종목 (실제 지정 공시일)",
      "괴리 분포"="플래그 onset=지정 공시월 동월 89% · 중앙값 0개월",
      "판정"="백데이팅 미래참조 없음 — 플래그 onset은 PIT 청정",
      "coverage 정직 라벨"="교차 36/2492(생존편향) -> 경화=플래그 동일, 청정성만 입증")),
    list(type="bullet", emoji="⚖️", heading="판정 평문", items=c(
      "판정 = CONFIG_SCOPED_NEGATIVE (강건히 성립 못함) + 프론티어 유지",
      "성립 = 지뢰(사고) 예측 지식 확보를 뜻하지만, 이번 근거는 6개 회사뿐이라 아직 '지식 확보' 못함",
      "자본 적용은 다음 단계 — 이번엔 그 다음 단계(필터 재설계)를 열지 않음(2단 분리 준수)",
      "R22 희석 가설은 방향으로 확증 — 벽이 '희석'에서 '독립 지각제출 회사 부족'으로 이동(해결 가능한 벽)")),
    list(type="bullet", emoji="➡️", heading="다음 단계 (재도전 3건)", items=c(
      "P1(주력): 전체 DART 공시 회사(전체 KOSPI+KOSDAQ)로 재검 — 대형주 지각제출 극소를 벗어나 독립 사례 수십~수백 확보",
      "P2: 에피소드 단위 설계(회사-지각제출 1건=1관측) + 이산-시간 hazard + firm wild bootstrap로 중복계상 제거",
      "P3: 라벨 경화 coverage를 상폐·관리 소형주 꼬리까지 확장(현재 36/2492만 검증)")),
    list(type="kv", emoji="🔒", heading="감사", kv=list(
      "사전등록 해시"="4b880cfb (심각-union association 무관측 상태에서 동결)",
      "R22와의 관계"="별건 신규 사전등록 — 문턱 동결, 표적·라벨경화만 변경",
      "선택 유형"="chain / n_trials=1 (단일 feature·문턱·표적 = confirmatory)",
      "학습코드"=lcode))
  )
)
cat("[telegram] ok =", isTRUE(r$ok) %||% FALSE, " ", r$error %||% "", "\n")
