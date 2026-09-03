#!/usr/bin/env Rscript
#==============================================================================
# test_rf_send_verdict.R — "보냈다" 가 실제 발송인지 **거동으로** 검사 (2026-08-31)
#
# 실증: 2026-08-30 07:16 텔레그램 429(레이트 리밋)로 "논문풀 적재 상세 21/29~29/29" 9건이
#   유실됐는데 발신자는 전부 sent=true 로 기록했다. tg_send() 는 HTTP 실패를 예외가 아니라
#   list(ok=FALSE,...) 로 돌려주는데 상위가 그 값을 **버렸기** 때문이다.
#   아래층은 정직했고 위층이 안 들었다 — 계기가 재기 쉬운 것(예외 부재)을 쟀다.
#
# 판정 3경우: ①성공 전파 ②실패 전파(위반 주입) ③구판 형태 하위호환
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_auto_notify.R")))
# telegram_notify.R 재로드를 막아 stub 이 살아남게 한다(발송 없음)
.orig <- base::source
source <- function(file, ...) {
  if (is.character(file) && grepl("telegram_notify", file)) return(invisible(NULL))
  .orig(file, ...)
}
BID <- Sys.getenv("QVEST_RF_TEST_BID", "")
if (!nzchar(BID)) {
  led <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  # ★"5칸 있다" 가 아니라 "**측정된** 5칸이 있다" 로 고른다. 루프를 tick 중간에 멈추면
  #   사전등록만 된 미측정 엔트리가 최신으로 남고, 거기서 FALSE 는 결함이 아니라 정답이다
  #   (rf_notify_table 이 보고할 것이 없어 NULL). 2026-09-03 오탐.
  .measured <- function(e) sum(vapply(e$attempts, function(a) {
    sp <- a$essence$spec %||% ""; nzchar(sp) && file.exists(sp) }, logical(1)))
  act <- Filter(function(e) .measured(e) >= 5L, led$entries)
  if (!length(act)) { cat("  FAIL 측정된 entry 가 없어 검사 불가\n"); quit(status = 1) }
  BID <- act[[length(act)]]$base_id
}
PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }
run <- function(stub) { tg_agent_brief <<- stub
  isTRUE(suppressWarnings(rf_auto_notify(BID, 5L, kind = "block"))) }

if (isTRUE(run(function(...) invisible(list(ok = TRUE,  bytes = 1L, error = NULL)))))
  ok("발송 성공 → TRUE") else ng("성공인데 FALSE")
if (isFALSE(run(function(...) invisible(list(ok = FALSE, bytes = 1L, error = "http_error/429")))))
  ok("HTTP 실패 → FALSE (위반 주입 적발)") else ng("실패를 성공으로 읽는다", "429 유실이 조용해진다")
if (isTRUE(run(function(...) invisible(NULL))))
  ok("반환값 없는 구판 형태 → TRUE (하위호환)") else ng("하위호환 깨짐")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_send_verdict","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
