#!/usr/bin/env Rscript
#==============================================================================
# test_rf_runner_lane_select.R — 러너 active 선택 절(레인 순서 · 반사실 선위임 · 반사실 양보 · 실험 제외) **추출 실행** (2026-09-25)
#   결정 D-G(prereg > 신규 논문 > 승격 > 반사실) · 플랜 P1-08 · 감사 D8-02. 러너 main() 안 분기라 source 로 못 부른다 —
#   test_rf_runner_standing_adversary.R 와 같은 방식(표지로 절을 잘라 격리 환경에서 실행 · 원장 적재·next_paper 호출은 스텁).
# 판정:
#   R1 반사실(원장 첫 줄) + 신규 논문 active → 신규 논문 선택 · 선위임 없음 · lane_selected 로그
#   R2 반사실만 active · 요청 없음 → next_paper 선위임 1회 · 그 뒤 반사실 선택(양보 없음)
#   R3 반사실만 active · 요청 pending → 선위임 1회 · 반사실 양보(return 0 · yield 로그)
#   R4 실험 + 신규 논문 active → 신규 논문 · 실험 제외 로그
#   R5 lanes 설정 없음 → 구판(원장 첫 active = 반사실 · 선위임 없음 · lane_cfg_unavailable)
#   R6 선위임한 next_paper 가 승격 자식을 열었다 → 다시 골라 승격 자식(반사실보다 앞)
#   M1 양보 절 제거 → R3 red · M2 선위임 절 제거 → R2 red
# 부작용 없음(tempdir · 운영 원장·설정 무접촉).
#==============================================================================
suppressMessages(library(jsonlite))
.slash <- function(p) sub("/+$", "", gsub("\\\\", "/", p))   # 경로 정규화 함수 대신 구분자만 통일(저장소 규칙 — 한글 경로)
ROOT <- .slash(Sys.getenv("QM_ROOT", getwd())); stopifnot(dir.exists(ROOT))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(c, m, d = "") if (isTRUE(c)) ok(m) else ng(m, d)
RUN <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
CFG0 <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)
TMPB <- .slash(tempfile("rflsel_")); dir.create(file.path(TMPB, "06_Registry"), recursive = TRUE)
dir.create(file.path(TMPB, "02_Infrastructure/reinforcement"), recursive = TRUE)
for (f in c("rf_lane_rules.R", "rf_spec_sig.R")) file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(TMPB, "02_Infrastructure/reinforcement", f))

extract <- function(path) {
  src <- sub("\r$", "", readLines(path, warn = FALSE, encoding = "UTF-8"))
  i0 <- grep("^## ── ★레인 순서", src)[1]
  i1 <- grep("^E <- act\\[\\[1\\]\\]; BID <- E\\$base_id$", src)[1]
  if (is.na(i0) || is.na(i1)) return(NULL)
  j <- which(grepl("^\\}$", src) & seq_along(src) > i1)[1]      # 양보 절 닫는 괄호
  src[i0:j]
}
run_sel <- function(block, entries, cfg = CFG0, req = NULL, after_delegate = NULL) {
  env <- new.env(parent = globalenv())
  env$ROOT <- TMPB; env$CFG <- cfg; env$LOGS <- list(); env$DELEG <- 0L; env$LED <- list(entries = entries)
  env$jlog <- function(event, ...) env$LOGS[[length(env$LOGS) + 1L]] <- c(list(event = event), list(...))
  env$rf_load <- function(layer, root) env$LED
  env$system2 <- function(cmd, args, ...) { if (grepl("reinforce_auto_next_paper", paste(args, collapse = " "))) {
    env$DELEG <- env$DELEG + 1L; if (is.function(after_delegate)) env$LED <- after_delegate(env$LED) }; 0L }
  env$led <- env$LED
  rp <- file.path(TMPB, "06_Registry/replication_request.json"); unlink(rp)
  if (!is.null(req)) write(toJSON(req, auto_unbox = TRUE), rp)
  code <- c("function() {", block, "list(E = E, BID = BID, act = act)", "}")
  f <- eval(parse(text = paste(code, collapse = "\n")), envir = env)
  environment(f) <- env
  r <- tryCatch(f(), error = function(e) list(.err = conditionMessage(e)))
  list(r = r, logs = env$LOGS, deleg = env$DELEG)
}
ev <- function(x, e) Filter(function(z) identical(z$event, e), x$logs)
en <- function(id, priority = NULL, parent = NULL, experiment = NULL) {
  e <- list(base_id = id, status = "active", opened_at = "2026-09-24T00:00:00+0900")
  if (!is.null(priority)) e$priority <- priority
  if (!is.null(parent)) e$parent <- list(base_id = parent)
  if (!is.null(experiment)) e$experiment <- experiment
  e }
CF <- en("CF", priority = "idle_only"); NEW <- en("NEW"); EXP <- en("ARM", priority = "prereg", experiment = list(prereg_id = "P"))
PEND <- list(requested_at = "2026-09-24T00:00:00+0900", status = "pending", paper = list(paper_key = "x"))

B <- extract(RUN)
if (is.null(B)) { ng("E0 러너 선택 절 추출 실패(표지 '## ── ★레인 순서' ~ 양보 절)"); quit(status = 1L) }
ok(sprintf("E0 러너 선택 절 추출(%d줄)", length(B)))
scen <- function(block) list(
  R1 = run_sel(block, list(CF, NEW)),
  R2 = run_sel(block, list(CF)),
  R3 = run_sel(block, list(CF), req = PEND),
  R4 = run_sel(block, list(EXP, NEW)),
  R5 = run_sel(block, list(CF, NEW), cfg = { c <- CFG0; c$lanes <- NULL; c }),
  R6 = run_sel(block, list(CF), after_delegate = function(L) { L$entries <- c(L$entries, list(en("P0_promo2", parent = "P0"))); L }))
S <- scen(B)
chk(identical(S$R1$r$BID, "NEW") && S$R1$deleg == 0L && length(ev(S$R1, "lane_selected")) == 1L, "R1 반사실(원장 첫 줄)+신규 → 신규 논문 선택 · 선위임 없음", S$R1$r$.err %||% "")
chk(identical(S$R2$r$BID, "CF") && S$R2$deleg == 1L && !length(ev(S$R2, "yield_nonblocking_to_replication")), "R2 반사실만 · 요청 없음 → next_paper 선위임 1회 → 반사실 진행", S$R2$r$.err %||% "")
chk(identical(S$R3$r, 0L) && S$R3$deleg == 1L && length(ev(S$R3, "yield_nonblocking_to_replication")) == 1L, "R3 반사실만 · 요청 pending → 선위임 · 반사실 양보(return 0 · 원장 동시 쓰기 차단)",
    paste(S$R3$r$.err %||% "", S$R3$deleg))
chk(identical(S$R4$r$BID, "NEW") && length(ev(S$R4, "experiment_entries_excluded")) == 1L, "R4 실험 entry 제외 · 신규 논문 선택")
chk(identical(S$R5$r$BID, "CF") && S$R5$deleg == 0L && length(ev(S$R5, "lane_cfg_unavailable")) == 1L, "R5 lanes 없음 → 구판(원장 첫 active · 선위임 없음)")
chk(identical(S$R6$r$BID, "P0_promo2") && S$R6$deleg == 1L, "R6 선위임이 승격 자식을 열면 다시 골라 승격 자식(반사실보다 앞)")
## 돌연변이
m1 <- B; k <- grep("rf_request_inflight", m1); if (length(k)) m1[k] <- sub("isTRUE\\(rf_request_inflight\\(\\.req_now\\(\\), \\.LANE\\)\\)", "FALSE", m1[k])
m2 <- B; k2 <- grep("!length\\(rf_blocking_active\\(led\\$entries, \\.LANE\\)\\)", m2); if (length(k2)) m2[k2] <- sub("!length\\(rf_blocking_active\\(led\\$entries, \\.LANE\\)\\)", "FALSE", m2[k2])
chk(!identical(m1, B) && !identical(run_sel(m1, list(CF), req = PEND)$r, 0L), "M1 양보 제거 사본 → R3 red(돌연변이 사살)")
chk(!identical(m2, B) && run_sel(m2, list(CF))$deleg == 0L, "M2 선위임 제거 사본 → R2 red(돌연변이 사살)")
unlink(TMPB, recursive = TRUE)
cat(sprintf("\n== test_rf_runner_lane_select: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_runner_lane_select","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
quit(status = if (F == 0L) 0L else 1L)
