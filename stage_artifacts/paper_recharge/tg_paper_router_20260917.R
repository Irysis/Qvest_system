source("02_Infrastructure/telegram/telegram_notify.R")
route <- jsonlite::fromJSON("stage_artifacts/paper_recharge/alpha_search_route_20260917.json", simplifyVector = FALSE)
papers <- route$papers
n_repl <- route$counts_by_route$replication
n_skip <- route$counts_by_route$skip
n_dpr <- sum(vapply(papers, function(p) !is.null(p$factor_candidate) && identical(p$factor_candidate$verdict, "data_pipeline_required"), logical(1)))
n_redundant <- sum(vapply(papers, function(p) identical(p$reason, "redundant — 이미 registry/queue 에 처리 기록 존재"), logical(1)))
n_skip_true <- n_skip - n_dpr - n_redundant
testable_titles <- vapply(papers, function(p) {
  if (!is.null(p$factor_candidate) && identical(p$factor_candidate$verdict, "testable")) p$title else NA_character_
}, character(1))
testable_titles <- testable_titles[!is.na(testable_titles)]
headline <- sprintf("신규 208편: testable %d · dpr %d · skip %d · redund %d",
                     n_repl, n_dpr, n_skip_true, n_redundant)
top_bullets <- head(testable_titles, 12)
secs <- list(
  list(type = "summary", heading = "트리아지 결과", body = headline),
  list(type = "bullet", heading = "testable → replication 대기 (상위 12)", items = top_bullets),
  list(type = "summary", heading = "산출", body = "route json + queue append 2건, 백로그 0915=0")
)
tg_agent_brief(agent = "AlphaSearch", title = "[1계층] 논문 트리아지", relaxed = TRUE, force = TRUE, lock_scope = "paper_router_20260917", sections = secs)
cat("[paper_router] tg sent\n")
