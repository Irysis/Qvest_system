# run_wt017_telegram.R — WT-017 완료 브리프 (tg_agent_brief 단일 진입점 + 차트)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
source("02_Infrastructure/telegram/telegram_notify.R")

tg_agent_brief(
  agent = "Alpha",
  title = "WT-017 ALPHA_DONE — 국면 라벨 overlay 소비: 한계기여 없음 (FQ-115 negative)",
  sections = list(
    list(type = "summary", text = paste0(
      "국면 라벨(CRISIS/CAUTION)로 현행 M4×R05 overlay 위에 노출을 추가 축소하는 규칙(사전 고정 단일값)을 ",
      "269개월 book carrier에서 실측 — 한계기여 paired t = -1.85 (-2.38%/yr), ΔIR(정보비율 차) = -0.22. ",
      "독립 기여 없음, 점추정은 유해 방향입니다.")),
    list(type = "plain", text = paste0(
      "쉬운 설명: '위기 경보가 켜지면 주식 비중을 줄인다'는 규칙을 현재 운용 중인 방어장치 위에 하나 더 얹어봤습니다. ",
      "결과는 손해였습니다. 이유는 경보 자체가 실제 하락달을 못 맞히기 때문입니다 — 경보가 켜진 달의 시장은 평균적으로 ",
      "오히려 크게 올랐고(연율 +90%), 진짜 하락달을 맞힌 비율은 10%로 동전던지기(41%)보다도 낮았습니다. ",
      "지난 라운드(WT-015)에서 위기 라벨 달에 성과가 좋아 보였던 것(+4.98%)은 방어 성공이 아니라, ",
      "경보가 반등장·급등장에 잘못 켜진 달들이 몰려 있었던 우연으로 판명됐습니다.")),
    list(type = "table", title = "핵심 실측 (269개월, 2004-01~2026-05 홀딩)", rows = list(
      c("현행 BOOK(M4×R05) PORT_t", "+6.18 (절대 샤프지수 1.711, 최대낙폭 -23.3%)"),
      c("후보(BOOK×국면라벨 g) PORT_t", "+5.08 (샤프지수 1.686, 최대낙폭 -23.3% — 개선 0)"),
      c("한계기여 paired t / ΔIR", "-1.85 (-2.38%/yr) / -0.22"),
      c("EW 기저 / lag2 / 비용반영", "-2.04 / -2.57 / -1.87 (전부 부정 방향 일관)"),
      c("라벨→실현하락 판별력", "recall 0.10 < 무작위 0.41, fisher p=1.0 (BM<-8%에서도 p=0.196)"),
      c("오라클(하락월 완전예지, 진단)", "paired +1.18, 최대낙폭 -23.3%→-9.2% — 소비면 자체는 유효")
    )),
    list(type = "bullet", title = "판정·검증", items = list(
      "(c) WT-015 CRISIS +4.98% = 라벨 우연 확정 — CRISIS 라벨월 15건의 실현 벤치 연율 +90%(2009·2020 반등, 2026 멜트업). 그 달들 노출 축소 시 active 연율 -25%→-64%로 악화",
      "병목은 소비 경로가 아니라 라벨 품질 — 오라클 진단이 overlay 감β 소비면의 유효성은 입증(+2.1%/yr, 최대낙폭 절반)",
      "PIT: assert_overlay_pit 269개월 HARD 통과(라벨월말→홀딩시작 간격 1일) + 위반 주입 시 차단 발화 실증 + lag 스트레스 + strict A/B 동일",
      "측정 결함 2건 자체 적발·수리(가중 정규화 그룹핑 붕괴 → BOOK==EW 동치 지문으로 발화, 재발 가드 배선) — alpha_validation.repairs",
      "회전 10.3/yr(상한 11.0 이내), 오버레이 회전 증분 0.22/yr — 회전은 관문 아님. 자본 주장 없음(overlay 변경은 도훈 수동 영역)"
    )),
    list(type = "bullet", title = "다음 단계 (next_probe)", items = list(
      "NP-1: 라벨 엔진 지연-지표 기전 규명 — MSM 위기확률 연속값의 실현-하락 선행력 직접 실측(이산 라벨 대비), 발화 시점 분포(위기 전/중/후) 분해. FQ 등재",
      "NP-2: 실현-하락 nowcast 대체 라벨(트레일링 낙폭/변동성 단순 규칙)의 동일 사전등록 스케줄 재측정 — 오라클 갭 +2.1%/yr가 상금. FQ 등재",
      "부활 조건: ① 라벨 recall > base rate(fisher p<0.05) 회복 시 재측정 ② carrier 2026-07+ 재생성 시 7월 폭락 방어 순액 재판정(2026-06월말 라벨=CRISIS — stopped-clock 여부 확정)"
    ))
  ),
  charts = c("stage_artifacts/WT_D20260802_017/wt017_chart_marginal.png")
)
cat("[wt017] telegram 발송 완료\n")
