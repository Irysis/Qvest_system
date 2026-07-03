## Paper router v2 telegram brief — 20260620 (single tg_agent_brief call)
suppressWarnings(suppressMessages({ library(jsonlite) }))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))
`%||%` <- function(a,b) if (is.null(a)||length(a)==0||is.na(a[1])) b else a

TODAY <- "20260620"
base  <- file.path("stage_artifacts", "paper_recharge")
rt    <- fromJSON(file.path(base, sprintf("alpha_search_route_%s.json", TODAY)), simplifyVector = FALSE)
mq    <- fromJSON(file.path(base, sprintf("mode_queue_%s.json", TODAY)), simplifyVector = FALSE)

cr <- rt$counts_by_route
summary_txt <- sprintf(
  "소스 %d편(arxiv %d + curated %d) 배분: alpha %d / optimizer %d / risk %d / regime %d / skip %d. testable 팩터 %d건. curated 신규처리 %d편(전 15편 처리완료).",
  rt$n_papers, rt$n_arxiv, rt$n_curated,
  cr$alpha, cr$optimizer, cr$risk, cr$regime, cr$skip,
  rt$n_factor_candidates, rt$n_curated)

# ① alpha-search autorun(=1) 결과
b_auto <- c(
  "AUTORUN=1 · 1건 실행 → ⚠️QUARANTINE: STR_AS_PINDEX_2606_08569 (p-index, gate failed=robustness,fidelity)",
  "양방향 long-only 모두 KR alpha 부재 — A(저p-index 롱): grade C, IR -0.62, FF3 alpha -3.4%/yr(t=-1.60) 음의알파 · B(고p-index 롱): grade F, MDD 66.7% structural-drawdown, oos 0.26",
  "충실구현 확인(논문 binomial p-index eq.6-8, BS 아님·폴백無). 논문 자체 보고 시장간 부호불안정(SSE↔SP500) KR서 재현. PIT pass·contract pass·robustness fail")

# ② route 무관 발굴 testable 팩터 + 비-testable flag
b_fac <- c(
  "p_index_fair_downside_insurance [2606.08569·alpha·testable→실행→quarantine]",
  "= δ목표수익 만기보장 1달러당 put 공정가(옵션데이터 불요). novel이나 KR long-only 음의 알파",
  "비-testable flag 4건 ↓",
  "topological-anomaly(infeasible·intraday) / network-centrality(uncertain·수익미검증)",
  "ReSGA ES-sort(uncertain·vol인접) / EA-day multimodal(infeasible·뉴스감성=alt-data)")

# ③ optimizer/risk/regime 큐 후보 제목
opt_t <- sapply(mq$optimizer, function(x) x$title)
risk_t<- sapply(mq$risk,      function(x) x$title)
reg_t <- sapply(mq$regime,    function(x) x$title)
short <- function(v, n=4) { v <- as.character(v); if (length(v) > n) c(v[1:n], sprintf("…외 %d건", length(v)-n)) else v }
b_queue <- c(
  sprintf("optimizer %d: %s", length(opt_t), paste(short(opt_t), collapse=" | ")),
  sprintf("risk %d: %s",      length(risk_t), paste(short(risk_t), collapse=" | ")),
  sprintf("regime %d: %s",    length(reg_t),  paste(short(reg_t), collapse=" | ")))

sections <- list(
  list(emoji = "🔭", heading = "alpha-search autorun (AUTORUN=1)", type = "bullet", items = b_auto),
  list(emoji = "🧬", heading = "발굴 testable 팩터 (route 무관)", type = "bullet", items = b_fac),
  list(emoji = "📥", heading = "optimizer/risk/regime 큐", type = "bullet", items = b_queue))

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "Research Source Routing + Factor Mining (paper router v2)",
  as_of = "2026-06-20",
  relaxed = TRUE, force = TRUE,
  lock_scope = sprintf("paper_router_%s", TODAY),
  sections = sections,
  footer = paste(c(summary_txt, "산출: alpha_search_route/mode_queue/auto_verify/auto_quarantine/curated_routed"), collapse=" — "))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
