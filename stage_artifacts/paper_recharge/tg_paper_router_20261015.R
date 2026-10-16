source("02_Infrastructure/telegram/telegram_notify.R")
route <- jsonlite::fromJSON("stage_artifacts/paper_recharge/alpha_search_route_20261015.json", simplifyVector = FALSE)
papers <- route$papers
ce <- route$counts_by_engine
cr <- route$counts_by_route
n_redundant <- sum(vapply(papers, function(p) identical(p$verdict, "redundant"), logical(1)))
n_dpr <- sum(vapply(papers, function(p) identical(p$verdict, "data_pipeline_required"), logical(1)))
n_testable <- sum(vapply(papers, function(p) identical(p$verdict, "testable"), logical(1)))
n_skip_true <- cr$skip - n_redundant - n_dpr
n_new <- ce$return + ce$defense + ce$construction + ce$not_relevant
headline <- sprintf("신규 %d편(수익 %d · 방어 %d · 구성 %d · 무관 %d) · testable %d · dpr %d · skip %d · redund %d",
                     n_new, ce$return, ce$defense, ce$construction, ce$not_relevant,
                     n_testable, n_dpr, n_skip_true, n_redundant)
testable_titles <- vapply(papers, function(p) {
  if (identical(p$verdict, "testable")) sprintf("[%s] %s", p$engine, p$title) else NA_character_
}, character(1))
testable_titles <- testable_titles[!is.na(testable_titles)]
defense_titles <- vapply(papers, function(p) {
  if (identical(p$verdict, "testable") && identical(p$engine, "defense")) p$title else NA_character_
}, character(1))
defense_titles <- defense_titles[!is.na(defense_titles)]
secs <- list(
  list(type = "summary", heading = "트리아지 결과", body = headline),
  list(type = "bullet", heading = "방어 엔진 testable (전부)", items = defense_titles),
  list(type = "bullet", heading = "testable → replication 대기 (상위 15)", items = head(testable_titles, 15)),
  list(type = "summary", heading = "산출", body = sprintf("route json(alpha_search_route_20261015.json) + data_pipeline_queue append %d건", n_dpr))
)
tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 논문 트리아지", relaxed = TRUE, force = TRUE, lock_scope = "paper_router_20261015", sections = secs)
cat("[paper_router] tg sent\n")
