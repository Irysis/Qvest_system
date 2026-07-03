## Paper Router v2 — 텔레그램 브리핑 (2026-07-03). 외부 .R + source 패턴(인라인 멀티라인 -e 금지).
suppressWarnings(suppressMessages(source("02_Infrastructure/telegram/telegram_notify.R")))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "리서치 소스 배분 + 팩터 마이닝 (2026-07-03)",
  as_of = "2026-07-03",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = "paper_router_20260703",
  sections = list(
    list(emoji = "📊", heading = "소스 배분 (arxiv 신규 5 / 재출현 33 / curated 신규 0)",
         type = "text",
         body = paste(
           "38건 중 5건만 신규(33=180일창 재출현, route 유지·재디스패치 X).",
           "전체: opt 6·risk 10·regime 6·skip 16·alpha 0.",
           "신규 5: opt 1·risk 1·regime 1·skip 2·alpha 0. testable 팩터 0.", sep = "\n")),
    list(emoji = "🔭", heading = "신규 소스 verdict (팩터마이닝)",
         type = "bullet",
         items = c(
           "[NEW] E2E Parametric Portfolio Policy 크로스에셋 선물(2607.00475) → optimizer (DPL A/B fuel)",
           "[NEW] Financial Rogue-Wave 실시간 온셋 탐지(2606.31475) → regime (온셋타이밍 KR settled-null, 탐지-flag)",
           "[NEW] Large-Deviations 스트레스 시나리오(2606.31122) → risk (스트레스 모듈)",
           "[NEW] ESG Greenwashing 측정(2606.31469) → skip (다중 ESG레이팅=alt-data)",
           "[NEW] Pareto Insurance(2606.30779) → skip (계리이론)",
           "팩터: novel 횡단면 0. near-miss=SMAR volume(uncertain)·Hurst(KR settled-fail)·body/tail(=size)")),
    list(emoji = "⚖️", heading = "큐 상태",
         type = "text",
         body = paste(
           "신규 큐: opt 1(00475 α̂고정 A/B) · risk 1(31122 flag) · regime 1(31475 flag).",
           "재출현 33건 = 이전 dispatch.R 이미 소비(재적재 X).", sep = "\n")),
    list(emoji = "📥", heading = "산출",
         type = "text",
         body = paste(
           "alpha_search_route_20260703.json / mode_queue_20260703.json",
           "curated_routed last_run→20260703 (신규 0).", sep = "\n"))
  ),
  footer = "➡️ near-null day: 신규 횡단면 알파 0 · testable 팩터 0. 신규 소스 5건은 opt/risk/regime 방법론 배분. 정직 보고(합성 없음)."
)
cat("TG_OK=", isTRUE(res$ok), " bytes=", ifelse(is.null(res$bytes), NA, res$bytes),
    " err=", ifelse(is.null(res$error), "", as.character(res$error)), "\n", sep = "")
