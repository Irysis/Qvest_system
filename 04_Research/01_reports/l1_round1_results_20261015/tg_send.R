## 1차 라운드 결과 · 다음 리서치 브리핑 — 텔레그램 2통(도훈 10-15: 텍스트 요약 + 시각화 · PDF 없음 · 결과 뒤 다음 리서치 브리핑으로 연속성)
## 실행: Rscript tg_send.R   (미리보기) / Rscript tg_send.R send   (발송)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
A <- commandArgs(trailingOnly = TRUE); SEND <- "send" %in% A; ONLY_BRIEF <- "briefing" %in% A
## force(briefing 재발송): 발송기 중복 차단 키가 제목의 한글을 밑줄로 접어 다른 [1계층] 제목과 충돌한 오탐(10-15) — 내용이 다른 메시지만 명시 우회
if (!SEND) Sys.setenv(QVEST_TG_DRY_RUN = "1")
D <- file.path(ROOT, "04_Research/01_reports/l1_round1_results_20261015")
figs <- c("① 돈을 버나 — 누적 수익 · 낙폭 · 지표(엔진 vs KOSPI200)" = file.path(D, "fig1_money.png"),
          "② 개선이 알파를 만들었나 — 기준 엔진 대비 증분 알파(β-통제 · 95% 구간)" = file.path(D, "fig2_alpha.png"),
          "③ 대표 개선의 손익 — DNN 원형 기준 vs 개선 · KOSPI200" = file.path(D, "fig3_improvement_pl.png"))
stopifnot(all(file.exists(figs)))
r1 <- if (ONLY_BRIEF) list(ok = NA) else tg_agent_brief(
  agent = "Q-Lead",
  title = "[1계층] 1차 라운드 결과 — 돈은 번다 · 개선은 알파를 못 만들었다",
  sections = list(
    list(type = "summary", emoji = "\U0001F4CC",
         body = "DNN 계열 엔진 연 19.8~25.9%(KOSPI200 10.7%) · 알파 유의 · 최대 낙폭은 시장과 같은 53~55%"),
    list(type = "bullet", heading = "① 돈을 버나 — 번다(2005~2026 · 15bps 순비용)", emoji = "\U0001F4B0",
         items = c("CAGR: B6_36(DNN 계보) 25.9% · DNN 원형 19.8% vs KOSPI200 10.7%",
                   "β-통제 알파: 연 +17.2%(t 3.88) · +12.1%(t 3.55) — 시장 노출을 걷어내도 남는 초과수익",
                   "Sharpe 1.03 · 0.88 vs 0.55 · Calmar 0.47 · 0.37 vs 0.20",
                   "최대 낙폭 54.9% · 53.4% vs 52.9% — 2008 급락을 못 피함 → 등급 A(Calmar 0.64) 미달의 이유",
                   "시험 창(2023~): 강세장 수익은 KOSPI200(42.2%)에 뒤졌지만 낙폭은 절반(20.8% · 24.6% vs 40.9%)",
                   "모멘텀 12-1 은 연 −13.3% — 엔진 탈락")),
    list(type = "bullet", heading = "② 개선이 알파를 만들었나 — 아니다", emoji = "\U0001F9EA",
         items = c("붙인 장치 12종 중 보는 창에서 알파를 유의하게 늘린 것 0",
                   "방어 장치 6종: 위기 손실은 줄였지만 알파를 깎음(추세 현금 연 −5.3% · t −3.2)",
                   "구성 5종: 역변동성만 알파 손실 없이 Calmar 소폭 개선(0.37 → 0.38 · 시험 창 1.04 → 1.18)",
                   "정제 공분산 최소분산: 위기 중앙값 손실 0.74 → 0.36 이지만 최대 낙폭 57.9% 로 커짐 — 반증"))),
  charts = figs, relaxed = TRUE, glossary = FALSE)
r2 <- tg_agent_brief(
  agent = "Q-Lead",
  title = "[1계층] 다음 리서치 브리핑 — 알파는 엔진에, 막힌 곳은 급락기 낙폭",
  sections = list(
    list(type = "summary", emoji = "\U0001F9ED",
         body = "다음 목표: 알파를 지키면서 급락기 최대 낙폭을 줄이기(Calmar 0.37~0.47 → 0.64)"),
    list(type = "bullet", heading = "1차에서 배운 것", emoji = "\U0001F4A1",
         items = c("알파 원천은 엔진(DNN 계열의 종목 선택)이다 — 붙인 장치가 아니다",
                   "월간 신호 방어 장치는 위기 중앙값은 지키지만 2008 · 2020 급락의 최대 낙폭은 못 막는다",
                   "구성 변경은 알파 중립 — 역변동성이 유일한 공짜 개선")),
    list(type = "bullet", heading = "다음에 할 것(순서)", emoji = "\U000027A1\UFE0F",
         items = c("① 새 알파 원천 확보 — 충실구현 레인 재개(예약 작업 켬). 큐 논문을 하나씩 재료로 · DNN 계열과 상관이 낮은 엔진을 찾는다",
                   "② 방어(P2) 다음 라운드 — 검증 장치 2종(저변동 틸트 · 추세 현금+저변동)이 알파를 깎은 원인을 노출 축소 vs 종목 선택으로 분해한 뒤 '알파를 덜 깎는 방어' 가설을 사전등록",
                   "③ 구성(P3) — 역변동성은 P4 조립 후보로 보관")),
    list(type = "bullet", heading = "결정 대기(도훈)", emoji = "\U0001F5F3\UFE0F",
         items = c("P0 안건: 목표 영역 0/21 — 목표 재검토 · 축 재검토 · 탐색 확장 · 새 엔진 뒤 재시도 중 선택(그때까지 P4 조립 차단)",
                   "MSM 국면 모수(PIT-C1-MSM-PARAMS) — 원문 기준 A′ 권고 확인")),
    list(type = "bullet", heading = "다음 보고에서 볼 것", emoji = "\U0001F50E",
         items = c("같은 차트 3장으로 비교 — 누적 수익 vs KOSPI200 · 증분 알파 · 급락기 낙폭",
                   "새 재료가 DNN 계열과 얼마나 다른가(상관)"))),
  relaxed = TRUE, glossary = FALSE, force = ONLY_BRIEF)
cat("results:", isTRUE(r1$ok %||% TRUE), "· briefing:", isTRUE(r2$ok %||% TRUE), "\n")
