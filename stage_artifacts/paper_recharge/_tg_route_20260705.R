suppressWarnings(suppressMessages({
  root <- Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", getwd()))
  library(jsonlite)
  source(file.path(root, "02_Infrastructure", "telegram", "telegram_notify.R"))
}))

TODAY <- "20260705"
mq <- jsonlite::fromJSON(file.path(root, "stage_artifacts", "paper_recharge",
                                    sprintf("mode_queue_%s.json", TODAY)), simplifyVector = FALSE)

short <- function(s, n = 70) {
  s <- gsub("\\s+", " ", s)
  if (nchar(s) > n) paste0(substr(s, 1, n - 1), "...") else s
}
titles <- function(lst) vapply(lst, function(e) sprintf("%s (%s)", short(e$title), e$id), character(1))

opt_items <- titles(mq$optimizer)
risk_items <- titles(mq$risk)
reg_items <- titles(mq$regime)

factor_items <- c(
  "[alpha] Kyle-lambda/Amihud (2607.01377) - REDUNDANT: L11_Kyle_Lambda + L01/09/10_Amihud + L14_Price_Impact 기존. signed order-flow(유일 novel)은 KR daily 불가",
  "[risk] Roll implied spread (2606.29018) - REDUNDANT: L08_Roll_Spread + L12_PS_Gamma 기존 (L01-L33 유동성축 포화)"
)

tg_agent_brief(
  agent = "AlphaSearch",
  title = "리서치 소스 배분 + 팩터 마이닝 (arxiv 20260705)",
  relaxed = TRUE,
  force = TRUE,
  lock_scope = sprintf("paper_router_%s", TODAY),
  sections = list(
    list(type = "summary", emoji = "\U0001F4DA",
         body = "arxiv 33편 배분: alpha1/opt5/risk8/regime5/skip14. testable 팩터 0(2건 중복). curated 신규 0. AUTORUN=0 큐만."),
    list(type = "kv", emoji = "\U0001F4CA", heading = "배분 요약",
         kv = list("소스" = "arxiv 33 + curated 0신규",
                   "route" = "alpha1 opt5 risk8 regime5 skip14",
                   "testable 팩터" = "0 (redundant 2)")),
    list(type = "bullet", emoji = "\U0001F9EC", heading = "발굴 팩터 (route 무관, 2건 전부 redundant)",
         items = factor_items),
    list(type = "bullet", emoji = "⚙️", heading = "Optimizer 큐 (α̂ 고정 A/B)",
         items = opt_items),
    list(type = "bullet", emoji = "\U0001F6E1️", heading = "Risk 큐",
         items = risk_items),
    list(type = "bullet", emoji = "\U0001F310", heading = "Regime 큐",
         items = reg_items)
  )
)
