# send_fq127_telegram.R — WT-D20260803_002 완료 보고 (tg_agent_brief 단일 진입점)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260803_002 ALPHA_DONE — FQ-127 base-의존성 재판정: 부분 계통 (필터형만 반전)",
  sections = list(
    list(type = "summary", emoji = "📌", lines = c(
      "8-2일 세션의 '개선' 주장 8건을 전수 감사 — 측정 base(포트 가중 규칙)를 production 실코드로 바꾸면 뒤집히는가. 결론: 배제-필터 주장 2건만 반전(기존 WT-022 판정 승계), 점수-교체 주장 2건은 5개 가중 방식 전부에서 부호 유지 — '전면 계통 오염'이 아니라 필터형에 국소."
    )),
    list(type = "easy", emoji = "🧭", lines = c(
      "쉬운 설명: 같은 '개선 효과'라도 어떤 저울로 재느냐(종목 비중을 시가총액으로 주느냐, 점수 순위로 주느냐)에 따라 +가 −로 뒤집힐 수 있음이 어제 실측됐습니다. 오늘은 어제 하루치 주장 전부를 다시 저울에 올렸습니다. '종목을 빼는' 방식의 개선만 저울에 민감했고, '점수를 바꾸는' 방식의 개선은 어느 저울에서도 방향이 같았습니다."
    )),
    list(type = "table", emoji = "📊", title = "재판정 결과 (ΔIR: 원 frame → production rank-tilt)", rows = list(
      c("CL-4 MAX5 배제 (WT-014)", "+0.169 → −0.113 반전 (승계)"),
      c("CL-5 MAX5 배제+overlay (WT-016)", "+0.128 → −0.149 반전 (승계)"),
      c("CL-3 경로효율 교체 (WT-009)", "+0.126 → +0.150 유지 (신규 실측, t +1.56)"),
      c("CL-8 2팩터 조합 (WT-021)", "+0.140 → +0.182 유지 (신규 실측, t +0.96 비유의)"),
      c("분류", "인벤토리 8주장: A 3(음성·parity base) / B 4(재판정) / C 4(라벨만)"),
      c("판정 평문", "부분 계통 — 필터형 개선 주장은 base 라벨 없이 소비 금지, 교체형은 이식성 확인")
    )),
    list(type = "bullet", emoji = "🚩", title = "Challenge Flags", lines = c(
      "CL-3 부호 유지 ≠ 교체 부활 — FQ-109 멤버십-섭동 철회는 독립 존치 (tilt에서도 t<2.0)",
      "WT-003 paired +2.569는 base 점수 패널 미저장으로 미검(C) — 약한 base(PORT_t 0.59) 위 주장이라 경고 최상급",
      "CRISIS 국면 상한 감응도 실측: 부호 불변 (T1 +0.144 / T2 +0.173)",
      "자본 주장 없음 — 감사 라운드, 기존 산출물 무수정"
    )),
    list(type = "bullet", emoji = "➡️", title = "다음 단계", lines = c(
      "NP-1: FQ-128 production-parity 라벨 배관에 개입유형 축(filter형=base 라벨 의무 / rerank형=면제 후보) 반영",
      "NP-2: WT-003 base 패널 재생성 시 CL-1 재판정 — FQ-096 착수 시 선행 gate로 병합",
      "NP-3: 고상관 rerank 쌍(0.95+)의 반례 1회 실측으로 '부분 계통' 경계 확정"
    ))
  ),
  charts = c(
    "stage_artifacts/WT_D20260803_002/chart_fq127_before_after.png",
    "stage_artifacts/WT_D20260803_002/chart_fq127_config_grid.png"
  )
)
cat("[fq127tg] 발송 완료\n")
