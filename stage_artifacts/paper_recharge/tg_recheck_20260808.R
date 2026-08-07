PROJECT_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR")
if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent   = "AlphaSearch",
  title   = "팩터 심층 재검 (tier-2) — 2608.05755 중복 판정",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(type = "summary",
         body = "tier-2 재검 1건 처리. 논문이 포착한 산업 모멘텀 + 단기 역전 신호가 우리 팩터 DB(M07/M11/M24)에 이미 완전히 등재돼 있어 중복(redundant) 판정. 실제 자본 배정으로 이어지는 신호는 없고, 두 개의 미측정 소비면을 다음 탐색 큐에 등재했습니다."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: LSTM에 섹터 임베딩을 붙여 산업별 수익 패턴을 포착하는 미국 논문을 심층 검토했습니다",
           "방법: 전문 정독 후 우리 팩터 DB 373개와 신호 정확 대조 + KR 이식 가능성 평가",
           "결과: 논문이 발견한 핵심 신호 2종(산업 모멘텀·단기 역전)이 이미 DB에 있어 새 팩터로 가져올 게 없습니다",
           "의미: 이 논문에서 자본 배정 후보는 없고, 대신 기존 팩터 2건의 추가 측정 아이디어를 도출했습니다"
         )),

    list(type = "kv", emoji = "📊", heading = "판정 결과",
         kv = list(
           "입력 후보"     = "1건",
           "승격(testable)" = "0건",
           "중복(redundant)" = "1건 — 2608.05755",
           "확정기각"      = "0건",
           "still_uncertain" = "0건"
         )),

    list(type = "bullet", emoji = "🔍", heading = "중복 근거 (2608.05755)",
         items = c(
           "섹터 임베딩 Δ_c 편향 = M07_IndMom (산업 12-1개월 모멘텀, 증거등급 A, S7)",
           "LSTM 60일 시계열 신호 = M11_ST_Reversal (5일 단기 역전, evidence_tier B)",
           "M24_Sector_Rel_Mom (섹터 상대 모멘텀) 도 추가 커버",
           "논문 기여 = ML 구성 방법(architecture), 경제적 신규 팩터 없음",
           "데이터: 미국 S&P 500 전용 — KR 이식 검증 없음"
         )),

    list(type = "bullet", emoji = "➡️", heading = "다음 탐색 큐 (next_probe 2건)",
         items = c(
           "FQ-NEW-IndMom_STRev_Composite: M07×M11 교차 composite KR PORT_t 미측정 — rank(M07)+rank(-M11) top-N 측정",
           "FQ-NEW-SectorRelMom_CapTier: M24 post-2017 KR 감쇠가 mega-cap 벤치 아티팩트인지 genuine 신호 소멸인지 cap-tier 분해 미측정",
           "done.json 26건 누적 — 재큐 방지 처리 완료"
         ))
  )
)
