# qlead_emit_and_brief.R — Phase A 판정 후처리 (Q-Lead): L-code emit + 차트 첨부 텔레그램
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure/axiom/lcode_emit.R"))

res <- emit_lcode(
  mode = "alpha_research",
  strategy_id = "WT-D20260711_002",
  grade = "C",
  metric_type = "canonical_screen",
  selection_type = "chain",
  record_type = "performance",
  portfolio_alpha_t = 1.37,
  oos_months = 60,
  core_reference = "파일럿 L-AR-20260711_165505 (H-d ρ -0.316) chain 스케일업 / preregistration.sha256 96b7e06d / alpha_validation.json",
  mechanism_hypothesis = "난독화(Li 2008 처리비용) 신호가 KR에서는 문장길이(m1) 단일 차원만 실재 — lag12 스트레스서 강화되는 느린 구조적 공시 특질이며, 명료 상위 25종의 0.96이 벤치-외 소형 tier = cap-w 트랩 국소화로 대형 tier는 signal-dead",
  falsification_attempts = "placebo 월셔플(m1 p 0.008 실재·composite p 0.716 null) / Size partial(cor logSize 0.071, partial Harvey-t -2.52) / lag12 스트레스(t -3.06 강화) / cap-tier·유동성 tercile 전반 / dual-basis(EW-uni 병기) / leave-one-out composite 분해 / 사전등록 hash 대조",
  lesson_text = paste0(
    "공시 텍스트 난독화 객관 전수(Phase A: 사업보고서 MD&A 4,432/4,866건, 2010-2023, 669종목, 객관 가독성 6지표 hash-frozen) = ",
    "사전등록 primary composite NULL(cap-w PORT_t 1.37, rank-IC placebo p 0.716). ",
    "파일럿 ρ -0.316의 방향은 m1(문장길이) 단일 차원에서만 확증: cap-w 2.35<2.95, EW-uni 2.13, Size-무관 실신호(placebo p 0.008), ",
    "단 OOS(2019+) 0.18 감쇠 + 명료-상위 포트가 0.96 소형 tier = cap-w 트랩 국소화. ",
    "leave-one-out: m1 제거 시 composite 부호 반전(+0.64) — m2/m3/m5는 희석 노이즈(합성이 신호를 죽인 사례). ",
    "객관·주관(LLM) complexity는 부분 상이 측정(수익 운반체 m1의 LLM 수렴 0.147). ",
    "판정 = screen-tier FAIL_CANONICAL_HARD_GATE, screen_route TEXT_READABILITY_FEATURE(m1) -> OVERLAY_CANDIDATE/feature 보존. ",
    "비-return 텍스트 원천도 top-25 long-only IC->PORT_t 전이 벽 재확인."),
  tags = c("text_alpha", "non_return", "screen_tier", "cap_tier_trap", "phase_a")
)
cat("[emit] l_code =", res$l_code %||% "?", "\n")

# ── 텔레그램 v7 판정 보고 (차트 4장 첨부 — prereg상 에이전트 발송 금지분을 Q-Lead가 발송) ──
source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))
CH <- file.path(ROOT, "stage_artifacts/WT_D20260711_002/charts")
charts <- file.path(CH, c("family_portt_sweep.png", "m1_equity_curve.png",
                          "m1_annual_returns.png", "m1_drawdown.png"))
charts <- charts[file.exists(charts)]
cat("[charts] found:", length(charts), "\n")

r <- tg_agent_brief(
  agent = "Q-Lead",
  title = "공시 난독화 전수 검증: 합격선에는 못 미침 — 문장길이 신호만 참고자산으로 보존",
  sections = list(
    list(type = "bullet", emoji = "🎯", heading = "연구 컨텍스트 (한글)",
         items = c(
           "목적: 어제 파일럿에서 잡힌 '읽기 어려운 공시 = 나쁜 주식' 신호를 사업보고서 전수로 확대 검증",
           "검토: 4,432건 보고서에 객관 가독성 지표 6종을 사전등록하고 실측 관문에 회부",
           "결론: 사전등록 종합지표는 무신호, 문장길이 지표 하나만 진짜 신호이나 자본 투입 기준에는 미달")),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: 회사가 보고서를 어렵게 쓸수록 주가가 나쁜지 14년치 전체를 확인했습니다",
           "방법: 문장길이 등 6가지 읽기 난이도 점수를 미리 고정해 두고 모의 운용을 돌렸습니다",
           "결과: 6가지를 합친 점수는 효과가 없었고, 문장길이 하나만 진짜 신호였습니다",
           "의미: 신호가 작은 회사들에 몰려 있어 실제 포트폴리오 기준(t값 2.95)에는 못 미쳤습니다")),
    list(type = "kv", emoji = "📊", heading = "핵심 실측",
         kv = list(
           "사전등록 종합지표" = "다중검정 t값 1.37 — 무신호 판정 (우연 검증 p 0.716)",
           "문장길이 단독" = "다중검정 t값 2.35 — 합격선 2.95 미달, 2019년 이후 감쇠",
           "크기 함정 검사" = "통과 — 회사 크기와 무관한 독립 신호임은 확인됨",
           "신호 위치" = "명료한 공시 상위 종목의 대부분이 벤치마크 밖 소형주 — 대형주에서는 무신호")),
    list(type = "bullet", emoji = "⚖️", heading = "판정 평문",
         items = c(
           "판정: 자본 투입 불가 — 이 신호로는 실제 돈을 배정하지 않습니다",
           "보존: 문장길이 지표는 다른 전략의 보조 재료(참고 신호)로 등재해 두었습니다",
           "교훈: 여러 지표를 합치면 좋아질 거라는 가정이 틀렸습니다 — 합성이 오히려 유일한 신호를 희석했습니다"))
  ),
  charts = charts,
  force = TRUE
)
cat("[tg] ok =", isTRUE(r$ok), "\n")
