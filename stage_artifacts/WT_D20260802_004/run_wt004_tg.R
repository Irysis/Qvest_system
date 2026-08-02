# run_wt004_tg.R — WT-D20260802_004 Alpha 완료 브리핑 (tg_agent_brief 단일 진입점)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-D20260802_004 ALPHA_DONE — 변동성 조합 가설 기각 (AX-001 조건부 재평가 최초 수행)",
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "변동성 팩터 조합이 단일 대비 위기 국면 초과수익을 높이는지 조건부 3축으로 최초 실측 — 조합 개선 없음(기각). 단 하락형 위기 4번 전부에서 저변동 방어가 실재함을 분리 실측, 소비처는 오버레이 입력."),
    list(type = "bullet", emoji = "📖", heading = "쉬운 설명",
         items = c("과거 저변동 전략 탈락 5건이 규정(AX-001)이 금지한 전기간 채점으로 죽었음을 원문에서 확인했습니다",
                   "그래서 규정대로 위기 구간만 떼어 다시 채점했습니다 — 그래도 탈락이지만 이유가 다릅니다",
                   "폭락기(2008 금융위기·2020 코로나 등 4번)엔 저변동 보유가 시장을 +5~10%p 이겼습니다",
                   "그러나 평상시 만성 손실이 그 보호를 압도해 단독 전략으론 부적격입니다",
                   "위기 라벨이 붙었는데 시장이 +33.7% 오른 구간(2026-02~07)도 발견 — 라벨 개선 과제로 등재")),
    list(type = "table", emoji = "📊", heading = "AX-001 조건부 3축 (방어 배향, 258개월 실측)",
         df = data.frame(
           구성 = c("D03 단일(총변동성)", "D55 단일(변동성추세)", "C_ORTH 조합(3축)", "Core 참조(모멘텀)"),
           위기alpha월 = c("-4.94%", "-2.88%", "-5.26%", "-5.10%"),
           하락위기누적 = c("+24.4%", "+11.4%", "+8.4%", "-13.2%"),
           최대낙폭 = c("79.2%", "60.4%", "77.8%", "59.5%")
         )),
    list(type = "bullet", emoji = "🚩", heading = "Challenge Flags (5건)",
         items = c("조합이 단일 최선을 못 넘음 — 가설 본체 기각 (위기 채점축에서도 동일)",
                   "방어 배향 정보계수가 하락월에 더 음수(-0.11~-0.14) — 저변동=방어 직관이 이 유니버스에서 불성립",
                   "변동성 5축 중 3축은 상관 0.91~0.97로 사실상 같은 축 — 조합의 실질은 3축 이하",
                   "방향정렬 실측: 시스템 정본 배향은 고변동 롱(정보계수 +0.11~0.14 전 구간) — 어느 배향도 top-25 실현 alpha 없음",
                   "LowVol 선례가 family 오분류로 AX-001 강제 hook을 우회했던 정황 — 거버넌스 수리 등재")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("Risk 단계 진행 비권고 (기대 alpha 음수) — 상태 ABORTED 기록, Q-Lead 판단 대기",
                   "next_probe: AX-001 hook family 수리 / 위기 정의 이원화 표준 / 개인 순매수 기전 검증 / 오버레이-입력화(FQ 후보)",
                   "산출물: alpha_package + alpha_validation + challenge_note (mailbox WT-D20260802_004)"))
  )
)
cat("[wt004tg] sent\n")
