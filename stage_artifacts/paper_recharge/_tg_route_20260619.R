## Paper router v2 telegram brief — 20260619 (single tg_agent_brief call)
suppressWarnings(suppressMessages({
  library(jsonlite)
}))
ROOT <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT)
source(file.path(ROOT, "02_Infrastructure", "telegram", "telegram_notify.R"))

TODAY <- "20260619"
base  <- file.path("stage_artifacts", "paper_recharge")
rt    <- fromJSON(file.path(base, sprintf("alpha_search_route_%s.json", TODAY)), simplifyVector = FALSE)
mq    <- fromJSON(file.path(base, sprintf("mode_queue_%s.json", TODAY)), simplifyVector = FALSE)

cr <- rt$counts_by_route
summary_txt <- sprintf(
  "소스 %d편(arxiv %d + curated %d) 배분: alpha %d / optimizer %d / risk %d / regime %d / skip %d. testable 팩터 %d건. curated 신규처리 %d편.",
  rt$n_papers, rt$n_arxiv, rt$n_curated,
  cr$alpha, cr$optimizer, cr$risk, cr$regime, cr$skip,
  rt$n_factor_candidates, rt$n_curated)

# ① alpha-search autorun(=0) / 큐
b_auto <- c(
  "AUTORUN=0 → 자동실행 없음. alpha-search 큐 1건 적재: p-index (가격합성 put-insurance, testable)",
  "큐 외 flagged: topological-anomaly(infeasible·intraday), network-centrality(uncertain·수익미검증), ReSGA ES-sort(uncertain·롱숏), EA-day multimodal(infeasible·뉴스감성)")

# ② route 무관 발굴 testable 팩터
b_fac <- paste(
  "p_index_fair_downside_insurance [2606.08569, route=alpha] —",
  "δ목표수익 만기보장 1달러당 put 공정가(BS: 가격+과거σ+무위험금리 합성, 옵션데이터 불요).",
  "registry put/insurance 부재=novel, VaR/CVaR와 구별(forward 공정가). δ·정규화 medium")

# ③ optimizer/risk/regime 큐 후보 제목 (헤지펀드 소스 포함)
opt_t <- sapply(mq$optimizer, function(x) x$title)
risk_t<- sapply(mq$risk,      function(x) x$title)
reg_t <- sapply(mq$regime,    function(x) x$title)
short <- function(v, n=4) { v <- as.character(v); if (length(v) > n) c(v[1:n], sprintf("…외 %d건", length(v)-n)) else v }
b_queue <- c(
  sprintf("optimizer %d: %s", length(opt_t), paste(short(opt_t), collapse=" | ")),
  sprintf("risk %d: %s",      length(risk_t), paste(short(risk_t), collapse=" | ")),
  sprintf("regime %d: %s",    length(reg_t),  paste(short(reg_t), collapse=" | ")))

sections <- list(
  list(emoji = "🔭", heading = "alpha-search (AUTORUN=0)", type = "bullet", items = b_auto),
  list(emoji = "🧬", heading = "발굴 testable 팩터 (route 무관)", type = "text", body = b_fac),
  list(emoji = "📥", heading = "optimizer/risk/regime 큐", type = "bullet", items = b_queue)
)

res <- tg_agent_brief(
  agent = "AlphaSearch",
  title = "Research Source Routing + Factor Mining (paper router v2)",
  as_of = "2026-06-19",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("paper_router_%s", TODAY),
  sections = sections,
  footer = paste(c(summary_txt, "산출: alpha_search_route/mode_queue/alpha_search_queue/curated_routed"), collapse=" — "))

cat("TG_OK:", isTRUE(res$ok), " bytes:", res$bytes %||% NA, " err:", res$error %||% "NULL", "\n")
