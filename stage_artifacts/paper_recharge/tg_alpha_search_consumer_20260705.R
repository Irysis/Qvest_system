source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "AlphaSearch",
  title = "alpha-search 큐 가동 (팩터→모드)",
  relaxed = TRUE,
  force = TRUE,
  sections = list(
    list(type = "summary", emoji = "📌",
         body = "20260705 런: 큐에 미소비 testable 팩터 0건 → 자동실행 0편. 날조 없이 정직 종료(batch_434 가드)."),
    list(type = "bullet", emoji = "📥", heading = "큐 상태",
         items = c("testable 후보 총 2건(p_index 2606.08569 · ReSGA 2606.04576) 모두 이미 소비+quarantine(done 등재)",
                   "route 0702/0703/0704 전부 n_factor_testable=0",
                   "queue 0626 candidates=[] · 0704 신규 2편은 kr_feasible=false 또는 DB redundant")),
    list(type = "bullet", emoji = "🗄️", heading = "기소비 이력(참고)",
         items = c("p_index(LOW): grade C · PORT_t -2.76 · IR -0.63 → QUARANTINE(robustness+fidelity)",
                   "ReSGA(size×tail): POS essence F · PORT_t -2.81 → QUARANTINE(robustness+fidelity)")),
    list(type = "bullet", emoji = "➡️", heading = "다음",
         items = c("신규 testable 팩터는 tier-1/tier-2 라우터 발굴 후 재가동",
                   "0704 deferred: 볼륨-변동성 음(-)예측 기존팩터 SIGN 가설(저 prior EV) 선택적 후속"))
  )
)
