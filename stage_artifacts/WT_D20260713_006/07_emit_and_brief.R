`%||%` <- function(a,b) if(is.null(a)||length(a)==0) b else a
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
source(file.path(ROOT,"02_Infrastructure/axiom/lcode_emit.R"))

res <- emit_lcode(
  mode="alpha_research", strategy_id="WT-D20260713_006", grade="F",
  metric_type="unavailable", construction_type="single", selection_type="sweep", record_type="process",
  core_reference="FQ-035 R22 / parent FQ-033 settled_negative + L-AR-20260713_173418 next_probe 1 / preregistration.sha256 3455656218 / verdict.json",
  mechanism_hypothesis="포렌식 신호(Benford FSD·m1 문장길이·제출 지연)의 construct-valid 과녁 = 월간 포트 꼬리(R20 반증)가 아니라 12개월 내 이산 악재 이벤트(불성실공시·관리종목·장기 거래정지·상폐). RAWDATA 기존 플래그 소비(API 0)",
  falsification_attempts="사전등록 hash 동결(feature->event 무관측 상태에서) / 4-trial sweep(3 단독+스택, Bonferroni x4) / ticker-cluster-robust logistic Size·tier·유동성 통제 / ticker-cluster 부트스트랩 lift CI / pre-post 2016 안정성 / 연속 days-late·top-quintile 대체 검정 / 사건유형별 lift 분해 / delisting C6 last-obs 도출·생존편향 방향 명시",
  lesson_text=paste0(
    "포렌식 스택 이벤트-예측 재과녁(R22): 사전등록 문턱(통제 후 controlled OR p<0.05 full-sample AND pre/post-2016 stable) 미달 = CONFIG_SCOPED_NEGATIVE. ",
    "Benford(controlled OR 1.09 p 0.70·AUC 0.51)·m1(OR 1.01 p 0.97·부호 불안정)·스택(OR 1.32 p 0.63) = flat null -> event-predictor 종결(feature 보존). ",
    "제출 지연(F3)만 live sub-threshold: 최악10% lift 2.07(Wilson [1.61,2.65] 제외 1이나 ticker-cluster boot [0.71,3.65] 포함 1), controlled OR 2.06(raw 2.18에서 거의 안 줄어듦 = 크기위장 아님, 통제가 authoritative), full-sample p 0.075(검정력)·post-2016 OR 2.58 p 0.022(pre-2016 미추정 -> 안정성 clause 미충족). ",
    "핵심 진단: 합집합 과녁이 진짜 신호를 희석 — delay 최악10% 사건유형별 lift = 상폐 6.4x·관리종목 4.2x·불성실공시 3.8x vs 기저 큰 단기 거래정지 1.8x. 심각사건-특이·극단꼬리 국소(연속/quintile 확대 시 희석·비단조). ",
    "R20 대비: 월간꼬리 프레임이 못 본 size-robust 심각사건-late-filing 관계를 이벤트 프레임이 표면화 -> 프레임 부분 입증이나 union/decile config 검정력 미달. ",
    "2단 분리 준수: 사전등록 문턱 미충족 -> 필터 재설계(stage-2) 미개시. 심각사건 한정 재과녁은 NEW 사전등록 라운드(post-hoc 금지)."),
  tags=c("non_return","forensic_stack","event_prediction","config_scoped_negative","size_robust","frontier_open","delay_severe_event")
)
cat("[emit] l_code =", res$l_code %||% "?", "\n")
saveRDS(res$l_code, "stage_artifacts/WT_D20260713_006/_lcode.rds")

# ---- Telegram v7 (Q-Lead 발송, charts 첨부) ----
source(file.path(ROOT,"02_Infrastructure/telegram/telegram_notify.R"))
CH <- file.path(ROOT,"stage_artifacts/WT_D20260713_006/charts")
charts <- file.path(CH, c("01_lift_bars.png","02_control_before_after.png","03_delay_eventtype.png"))
charts <- charts[file.exists(charts)]
cat("[charts]", length(charts),"\n")

r <- tg_agent_brief(
  agent="Q-Lead",
  title="포렌식 스택 이벤트-예측 재과녁(R22): 사전등록 합격선 미달 — 단 '제출 지연'은 크기위장 아닌 심각사건 신호(프론티어 유지)",
  charts=charts,
  sections=list(
    list(type="bullet", emoji="🎯", heading="연구 컨텍스트 (한글)", items=c(
      "R20이 반증한 것은 '월간 포트폴리오 꼬리' 프레임 — 이번엔 과녁을 이산 악재 사건(불성실공시·관리종목·장기 거래정지·상폐)으로 교체",
      "보존 feature 3종(Benford 이탈·m1 문장길이·제출 지연)이 향후 12개월 내 사건을 기저율 대비 유의 lift로 예측하는지 검정",
      "본 라운드는 예측 성립 여부만 판정(자본 개선 주장 금지) — 성립 시에만 지뢰제거 필터 논의를 별도 라운드로 재개")),
    list(type="bullet", emoji="📖", heading="쉬운 설명", items=c(
      "시도: 회계·문서·제출 습관이 수상한 회사가 1년 안에 상장폐지·관리종목 같은 사고를 더 자주 내는지 확인",
      "방법: 각 지표의 최악 10% 회사군의 사고율을 전체 평균과 비교하고, 회사 크기 효과를 통계로 제거",
      "결과: Benford·문장길이·스택은 예측력 없음. '제출 지연'만 사고율 2배로 나왔고 이건 소형주 때문이 아님",
      "다만: 제출 지연도 사전에 정한 엄격한 통계 합격선(p<0.05)에는 아슬하게 못 미침 — 사고 표본 수가 적어서")),
    list(type="kv", emoji="📊", heading="핵심 실측 (사고=향후 12개월 내 상폐·관리종목·장기정지·불성실공시)", kv=list(
      "벤포드 회계숫자 이탈"="배수 1.05 · 통제후 승산비 1.09 (p 0.70) · AUC 0.51 — 무신호",
      "문장길이 난독화"="배수 1.09 · 통제후 승산비 1.01 (p 0.97) · 부호 불안정 — 무신호",
      "제출 지연"="배수 2.07 · 통제후 승산비 2.06 (p 0.075) — 크기위장 아님, 검정력만 미달",
      "스택(2개 이상 플래그)"="배수 1.44 · 통제후 승산비 1.32 (p 0.63) — 두 무신호가 지연을 희석",
      "지연의 사건유형별 배수"="상폐 6.4배 · 관리종목 4.2배 · 불성실 3.8배 · (단기정지 1.8배가 합집합 희석)",
      "다중검정 보정"="Bonferroni 4중 최소 p 0.30 — 보정 후 생존 0")),
    list(type="bullet", emoji="⚖️", heading="판정 평문", items=c(
      "판정 = CONFIG_SCOPED_NEGATIVE (사전등록 합격선 미달, 자본 아님)",
      "Benford·m1·스택 = 이벤트 예측력 없음 -> event-predictor 종결(feature는 기존 용도로만 보존)",
      "제출 지연 = 소형주 위장이 아닌 진짜 심각사건 신호이나, 합집합 과녁+최악10% 표본이 검정력을 억제해 아슬하게 미달 -> 프론티어 유지",
      "'이게 성립해야 지뢰제거(사고위험 상위 제외) 필터 논의가 다시 열립니다' — 이번 config로는 아직 열리지 않음")),
    list(type="bullet", emoji="➡️", heading="다음 단계 (next_probe >= 2)", items=c(
      "P1: 심각사건 한정 재과녁 — 지연 극단꼬리 vs {상폐+관리+불성실} (단기 거래정지 제외). 사건유형 분해상 4~6x 예상, 동일 꼬리로 p<0.05 가능성. NEW 사전등록",
      "P2: 문턱 확대 아닌 커버리지로 검정력 — 극단꼬리 유지 + 24개월 창 / 전체 DART 공시 유니버스 풀링 / 상폐 이산-시간 hazard 모형",
      "P3: 사건라벨 PIT 경화 — 실제 지정 공시일(플래그 onset vs 사유발생일) 확보로 백데이팅 look-ahead 배제 후에만 자본 논의")),
    list(type="kv", emoji="🔒", heading="감사", kv=list(
      "사전등록 해시"="3455656218 (feature-사건 무관측 상태에서 동결)",
      "이벤트 원천"="불성실공시(2009년+)·관리종목·장기 거래정지(20일 이상)·상폐(마지막 관측 도출)",
      "생존편향 방향"="완전상폐 초소형주 일부 누락 -> 사고 표본 하방편의 = 양성판정에 보수적",
      "학습코드"=res$l_code %||% "?"))
  )
)
cat("[telegram] ok =", isTRUE(r$ok) %||% FALSE, " ", r$error %||% "", "\n")
