## Paper router v2 telegram brief — 20260626 (Q-Lead inline, single tg_agent_brief call)
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||is.na(a[1])) b else a

TODAY <- "20260626"
base  <- file.path("stage_artifacts", "paper_recharge")
rt    <- fromJSON(file.path(base, sprintf("alpha_search_route_%s.json", TODAY)), simplifyVector = FALSE)
mq    <- fromJSON(file.path(base, sprintf("mode_queue_%s.json", TODAY)), simplifyVector = FALSE)

cr <- rt$counts_by_route
summary_txt <- sprintf(
  "신규 14편(06-21~26) 라우팅 + 20편 06-20 재사용 = rolling 34편 배분: alpha %d / optimizer %d / risk %d / regime %d / skip %d. testable 신규 팩터 %d건(신선 KR 횡단면 알파 희귀). curated %d편(전 15편 처리완료).",
  cr$alpha, cr$optimizer, cr$risk, cr$regime, cr$skip,
  rt$n_factor_candidates, rt$n_curated)

# (1) autorun = 0 (분류/큐/텔레그램만)
b_auto <- c(
  "AUTORUN=0 — 자동 alpha-search 미실행(큐만 적재). Q-Lead 인라인 라우팅(헤드리스 미사용).",
  "신규 route=alpha 1건(2606.22719 Leakage-aware LLM factor ranking)은 kr_feasible=false(LLM/매크로 nowcast=alt-data) → 알파 큐 미편입.",
  "기존 pending testable 0 — p_index(2606.08569)/ReSGA(2606.04576) 모두 처리완료·QUARANTINE(done).")

# (2) route 무관 발굴 팩터 — 신규 14편 testable=0, flag만 정직 보고
b_fac <- c(
  "신규 14편 testable 횡단면 팩터 0건.",
  "비-testable flag 2건: market_body_tail_leg(uncertain·시장수준 분해라 per-stock 신호 아님)",
  "llm_nowcast_factor_rank(infeasible·매크로 nowcast=alt-data)")

# (3) optimizer/risk/regime 큐 (신규 delta)
opt_t <- sapply(mq$optimizer, function(x) x$title)
risk_t<- sapply(mq$risk,      function(x) x$title)
reg_t <- sapply(mq$regime,    function(x) x$title)
short <- function(v, n=4) { v <- as.character(v); if (length(v) > n) c(v[1:n], sprintf("…외 %d건", length(v)-n)) else v }
b_queue <- c(
  sprintf("optimizer %d: %s", length(opt_t), paste(short(opt_t), collapse=" | ")),
  sprintf("risk %d: %s",      length(risk_t), paste(short(risk_t), collapse=" | ")),
  sprintf("regime %d: %s",    length(reg_t),  paste(short(reg_t), collapse=" | ")))

sections <- list(
  list(emoji = "🔭", heading = "alpha-search (AUTORUN=0 · 큐만)", type = "bullet", items = b_auto),
  list(emoji = "🧬", heading = "발굴 팩터 (route 무관)", type = "bullet", items = b_fac),
  list(emoji = "📥", heading = "optimizer/risk/regime 큐 (신규 delta)", type = "bullet", items = b_queue))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "Research Source Routing + Factor Mining (paper router v2 · 06-26)",
  as_of = "2026-06-26",
  relaxed = TRUE, force = TRUE,
  lock_scope = sprintf("paper_router_%s", TODAY),
  sections = sections,
  footer = paste(c(summary_txt, "산출: alpha_search_route/mode_queue/alpha_search_queue(06-26)"), collapse=" — "))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
