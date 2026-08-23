PROJECT_ROOT <- Sys.getenv("QM_ROOT")
if (nchar(PROJECT_ROOT) == 0) PROJECT_ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"

source(file.path(PROJECT_ROOT, "02_Infrastructure/telegram/telegram_notify.R"))

tg_agent_brief(
  agent  = "AlphaSearch",
  title  = "팩터 심층 재검 (tier-2) — 20260823",
  relaxed = TRUE,
  force   = TRUE,
  sections = list(
    list(type = "summary",
         body = "이슬람 금융 분류 변경 팩터(2608.12634) 정밀 재검 완료 — KR 적용 불가 확정. 승격 0건, 확정 기각 1건."),

    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c(
           "시도: '이슬람 율법 준수 주식 목록 변경' 신호가 한국 주식에도 쓸 수 있는지 논문 67페이지 전문을 정독했습니다",
           "방법: 373개 기존 팩터 레지스트리와 대조하고 KR 데이터로 구현 가능한지 단계별로 점검했습니다",
           "결과: 핵심 신호가 말레이시아 공식 기관(SC Malaysia) 인증 목록에만 의존 — 한국에 동등 기관이 없어 구현 불가",
           "의미: 이 아이디어는 채택하지 않습니다. 방법론 착안 2건은 새 후보(FQ)로 등록합니다"
         )),

    list(type = "kv", emoji = "📊", heading = "재검 결과",
         kv = list(
           "입력 후보"       = "1건",
           "승격 (testable)" = "0건",
           "확정 기각"       = "1건 — 2608.12634 shariah_classification_change",
           "still_uncertain" = "0건"
         )),

    list(type = "bullet", emoji = "🔬", heading = "기각 근거 (2608.12634)",
         items = c(
           "기관 데이터 부재: SC Malaysia 반기 목록은 Bursa Malaysia 상장주 전용 — KR 등가 기관 없음",
           "기전 비이전: 가격 효과 기전은 이슬람 금융 기관의 강제 매매(AUM 편출입) — KR Islamic AUM≈0",
           "미국 에뮬레이션 실패: 품질+스크린 통제 후 eligibility premium 소멸 (t=-0.35)",
           "저자 결론: 알파 팩터 아님, portfolio-monitoring state 변수로만 권고"
         )),

    list(type = "bullet", emoji = "➡️", heading = "파생 next_probe 2건 (신규 FQ 후보)",
         items = c(
           "NP1 index_boundary_proximity: KOSPI200/KOSDAQ150 편입 기준(시총·유동성·거래일) 경계 근접도 — 패시브 자금 강제 편출입 메커니즘 적용, RAWDATA 완전 구현 가능",
           "NP2 multi_screen_disagreement_kr: 다중 스크린(ESG·거버넌스·코스피200 적격 기준) 불일치 지수 — 기관 투자자 기반 분열 가설, 데이터 가용성 착수 전 확인 필요"
         ))
  )
)
