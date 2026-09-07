#!/usr/bin/env Rscript
#==============================================================================
# test_rf_audit_not_run_blocks_open.R — 감사 없이 개설 불가: rf_audit_gate + verify·레인·킬스위치 배선 (2026-09-06)
#
# 실사고: 2026-09-05 킬스위치(enabled=false)·claude CLI 부재로 감사 3건이 안 돌았고, 09-06 에는 역슬래시
#   QM_ROOT 로 병합기가 즉사했다. 네 경우 전부 verify 가 부재를 unverifiable 로 읽어 proceed → 감사 없이
#   ledger_consumed·entry 개설. 도훈 처분(09-04): misdeclared → 재구현 1회 + 소비 보류. 수리안:
#   ①감사는 루프 킬스위치를 따르지 않는다 ②미실행은 별개 사건(저널·텔레그램·꼬리표) ③감사 없이 개설 불가.
#
# ★verify 전체를 격리 실행하지 않는다 — 계약(run_paper_replication)이 실데이터 백테스트라 검사 1건에 수십 분이다.
#   대신 감사 절을 lib 함수 rf_audit_gate 로 옮겨 그 함수를 **실물로** 잰다(스폰 함수 주입 · 임시 wdir).
#   verify·레인 쪽은 소비자 소스에서 **순서와 분기를 재도출**한다(줄번호 단정 없음). 킬스위치는 audit.sh 를
#   격리 설정(QVEST_RF_CONFIG)으로 실제 실행해 halt 사유로 잰다.
# 양방향: A 게이트 — no-op 스폰 → audit_required·스폰 1+2·재시도 저널 2 / 정상 스폰 → proceed·스폰 1 /
#           두 번째 산출 → 스폰 2 / 낡은 파일은 이번 감사가 아니다 / 파손 산출 / 스폰 예외 / 감사자 판정 통과
#         B verify — audit_required 분기가 소비·개설·큐 미러 앞에 서고 그 안에 개설이 없다 · 우회 호출 0
#         C 레인 — audit_not_run + engine.R → 에이전트 없이 verify 만 (claude -p 앞에서 분기)
#         D audit.sh — 루프 enabled=false 여도 fidelity_audit.enabled=true 면 돈다 (halt_no_engine 까지 감) ·
#           fidelity_audit.enabled=false 면 halt_disabled (양성 대조)
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
Sys.setenv(QVEST_RP_JLOG = file.path(tempdir(), sprintf("rf_test_jlog_%d.jsonl", Sys.getpid())))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R"), local = TRUE))
TMP <- file.path(tempdir(), sprintf("fid_gate_%d", Sys.getpid()))
W <- file.path(TMP, "wdir"); dir.create(W, recursive = TRUE, showWarnings = FALSE)
AP <- file.path(W, "fidelity_audit.json")
wrj <- function(x, p = AP) write(toJSON(x, auto_unbox = TRUE, null = "null"), p)
FAITH <- list(verdict = "faithful", undeclared_changes = list(), signal_mismatch = list(),
              evidence = "3절 대조 완료", confidence = "high", note = "n")
LOGS <- list()
logf <- function(event, ...) LOGS[[length(LOGS) + 1L]] <<- c(list(event = event), list(...))
evts <- function(e) sum(vapply(LOGS, function(x) identical(x$event, e), logical(1)))
gate <- function(spawn, max_retries = 2L, retries_done = 0L) {
  LOGS <<- list()
  rf_audit_gate(W, spawn, max_retries = max_retries, retries_done = retries_done, log_fn = logf)
}

cat("=== A. rf_audit_gate — 실물 (스폰 함수 주입) ===\n")
unlink(AP, force = TRUE)
g <- gate(function() 0L)                                   # no-op: 레인이 rc 0 을 내면서 파일을 안 쓴다(halt_* 형태)
if (identical(g$disp$action, "audit_required")) ok("A1 산출 없는 스폰 → audit_required ★감사 없이 개설 불가") else ng("A1", g$disp$action)
if (identical(g$spawns, 3L) && identical(g$retries, 2L)) ok("A2 스폰 1+2 회(max_retries=2)") else ng("A2 스폰 횟수", sprintf("spawns=%s retries=%s", g$spawns, g$retries))
if (evts("fidelity_audit_retry") == 2L) ok("A3 재시도 저널 fidelity_audit_retry 2건(사이 rc 기록)") else ng("A3 재시도 저널", evts("fidelity_audit_retry"))
if (nzchar(as.character(g$reason %||% "")) && identical(g$last_rc, 0L)) ok(sprintf("A4 사유·마지막 rc 가 실린다(%s · rc %d)", g$reason, g$last_rc)) else ng("A4 사유/rc", sprintf("%s/%s", g$reason %||% "NULL", g$last_rc))
if (!file.exists(AP)) ok("A5 감사 파일은 여전히 없다(게이트가 지어내지 않는다)") else ng("A5 파일이 생겼다")

g <- gate(function() { wrj(FAITH); 0L })
if (identical(g$disp$action, "proceed") && identical(g$spawns, 1L) && evts("fidelity_audit_retry") == 0L)
  ok("A6 첫 스폰이 산출하면 proceed · 스폰 1회 · 재시도 없음 (대조)") else ng("A6", sprintf("%s spawns=%s", g$disp$action, g$spawns))
if (identical(g$aud$verdict, "faithful")) ok("A7 판정이 그대로 실린다") else ng("A7", g$aud$verdict)

n <- 0L
g <- gate(function() { n <<- n + 1L; if (n >= 2L) wrj(FAITH); 7L })
if (identical(g$disp$action, "proceed") && identical(g$spawns, 2L) && identical(g$retries, 1L))
  ok("A8 두 번째 스폰에서 산출 → proceed · 스폰 2회") else ng("A8", sprintf("%s spawns=%s", g$disp$action, g$spawns))
r1 <- Filter(function(x) identical(x$event, "fidelity_audit_retry"), LOGS)
if (length(r1) == 1L && identical(r1[[1]]$rc, 7L) && identical(r1[[1]]$n, 1L)) ok("A9 재시도 저널에 직전 rc(7)·회차(1)") else ng("A9 재시도 저널 내용")

wrj(FAITH)                                                  # 낡은 감사 파일(앞 판 엔진의 것)
g <- gate(function() 0L)
if (identical(g$disp$action, "audit_required")) ok("A10 낡은 fidelity_audit.json 은 이번 감사가 아니다 — 스폰 전에 지운다 ★") else ng("A10 낡은 파일을 이번 감사로 읽었다", g$disp$action)
if (!file.exists(AP)) ok("A11 낡은 파일이 지워져 있다") else ng("A11 낡은 파일 잔존")

g <- gate(function() { writeLines("{not json", AP); 0L })
if (identical(g$disp$action, "audit_required") && grepl("파손", g$reason %||% "", fixed = TRUE))
  ok("A12 파손 산출 → audit_required(파손 사유)") else ng("A12", sprintf("%s/%s", g$disp$action, g$reason %||% ""))

g <- tryCatch(gate(function() stop("boom")), error = function(e) e)
if (!inherits(g, "error") && identical(g$disp$action, "audit_required") && evts("fidelity_audit_spawn_failed") >= 1L && identical(g$last_rc, -1L))
  ok("A13 스폰 예외 → 죽지 않고 audit_required + spawn_failed 저널 + rc -1") else ng("A13 스폰 예외 처리", if (inherits(g, "error")) conditionMessage(g) else g$disp$action)

g <- gate(function() { wrj(FAITH); NULL })
if (identical(g$disp$action, "proceed") && identical(g$last_rc, -1L)) ok("A14 rc 를 안 돌려주는 스폰도 산출이 있으면 proceed(rc -1 기록)") else ng("A14", sprintf("%s rc=%s", g$disp$action, g$last_rc))

MD <- list(verdict = "misdeclared", undeclared_changes = list("논문은 t-1 인데 구현은 t — FIDELITY.changed 에 없음"),
           signal_mismatch = list(), evidence = "2절 식 (4)", confidence = "high")
g <- gate(function() { wrj(MD); 0L }, retries_done = 0L)
if (identical(g$disp$action, "reimplement") && identical(g$spawns, 1L)) ok("A15 misdeclared 산출 → reimplement(처분 통과 · 재스폰 없음)") else ng("A15", g$disp$action)
g <- gate(function() { wrj(MD); 0L }, retries_done = 1L)
if (identical(g$disp$action, "proceed_suspect")) ok("A16 retries_done 이 처분에 전달된다(2회차 → proceed_suspect)") else ng("A16", g$disp$action)
g <- gate(function() { wrj(list(verdict = "unverifiable", note = "원문 못 읽음")); 0L })
if (identical(g$disp$action, "proceed") && identical(g$spawns, 1L)) ok("A17 감사자 자신의 unverifiable 은 proceed · 재스폰 없음(미실행과 다르다)") else ng("A17", sprintf("%s spawns=%s", g$disp$action, g$spawns))
g <- gate(function() 0L, max_retries = 0L)
if (identical(g$spawns, 1L) && identical(g$disp$action, "audit_required")) ok("A18 max_retries=0 → 스폰 1회") else ng("A18", g$spawns)

cat("\n=== B. verify 배선 — audit_required 분기가 소비·개설·큐 미러보다 앞에 서고 그 안에 개설이 없다 (재도출) ===\n")
vf <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"), warn = FALSE, encoding = "UTF-8")
code <- sub("#.*$", "", vf)
i_gate <- which(grepl("rf_audit_gate(", code, fixed = TRUE))[1]
i_req  <- which(grepl('identical(.disp$action, "audit_required")', code, fixed = TRUE))[1]
i_open <- which(grepl("rf_open_entry(1L, BID", code, fixed = TRUE))[1]
i_con  <- which(grepl("ledger_consumed", code, fixed = TRUE))[1]
i_mir  <- which(grepl(".qmirror(PKEY", code, fixed = TRUE))[1]
i_quit <- if (is.na(i_req)) NA_integer_ else which(grepl("quit(status = 0)", code, fixed = TRUE) & seq_along(code) > i_req)[1]
if (!is.na(i_gate)) ok(sprintf("B1 verify 는 rf_audit_gate 를 부른다(%d행)", i_gate)) else ng("B1 rf_audit_gate 호출 없음")
if (!is.na(i_req) && !is.na(i_quit)) ok("B2 audit_required 분기 + 조기 종료 quit(status = 0)") else ng("B2 분기/종료", sprintf("req=%s quit=%s", i_req, i_quit))
if (!anyNA(c(i_gate, i_req, i_quit, i_open, i_con, i_mir)) && i_gate < i_req && i_req < i_quit &&
    i_quit < min(i_open, i_con, i_mir))
  ok(sprintf("B3 순서: gate(%d) < audit_required(%d) < quit(%d) < 소비·개설·미러(%d) ★", i_gate, i_req, i_quit, min(i_open, i_con, i_mir))) else
  ng("B3 순서", sprintf("gate=%s req=%s quit=%s open=%s con=%s mir=%s", i_gate, i_req, i_quit, i_open, i_con, i_mir))
if (!anyNA(c(i_req, i_quit))) {
  blk <- paste(code[i_req:i_quit], collapse = "\n")
  if (grepl("failed_needs_session", blk, fixed = TRUE) && grepl('"audit_not_run"', blk, fixed = TRUE))
    ok("B4 분기가 요청을 failed_needs_session/audit_not_run 으로 쓴다") else ng("B4 요청 상태 배선")
  if (grepl("fidelity_audit_not_run", blk, fixed = TRUE)) ok("B5 저널 fidelity_audit_not_run") else ng("B5 저널 없음")
  if (grepl('tg_agent_brief(agent = "AlphaSearch", relaxed = TRUE', blk, fixed = TRUE) &&
      grepl("충실도 감사 미실행", blk, fixed = TRUE)) ok("B6 텔레그램 [1계층] 미실행 표제(relaxed)") else ng("B6 텔레그램")
  if (!grepl("rf_open_entry", blk, fixed = TRUE) && !grepl(".qmirror", blk, fixed = TRUE) &&
      !grepl("ledger_consumed", blk, fixed = TRUE) && !grepl("rf_park_entry", blk, fixed = TRUE))
    ok("B7 분기 안에 원장 개설·소비·큐 미러가 없다 ★") else ng("B7 분기 안에 개설/소비 코드")
  if (!grepl('d$status <- "done"', blk, fixed = TRUE) && !grepl("completed_at", blk, fixed = TRUE))
    ok("B8 done 필드를 쓰지 않는다") else ng("B8 done 필드 오염")
}
if (sum(grepl("rf_audit_read(", code, fixed = TRUE)) == 0L && sum(grepl("rf_audit_disposition(", code, fixed = TRUE)) == 0L)
  ok("B9 verify 에 게이트 우회 호출(rf_audit_read/rf_audit_disposition 직접)이 없다") else ng("B9 우회 호출 잔존")
if (sum(grepl("rf_fidelity_audit.sh", code, fixed = TRUE)) == 1L) ok("B10 감사 레인 스폰 지점은 하나") else ng("B10 스폰 지점 수", sum(grepl("rf_fidelity_audit.sh", code, fixed = TRUE)))

cat("\n=== C. 레인 배선 — audit_not_run + engine.R 이면 에이전트 없이 verify 만 (재도출) ===\n")
au <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), warn = FALSE, encoding = "UTF-8")
ac <- sub("#.*$", "", au)
i_fn  <- which(grepl("^rp_verify()", ac))[1]
i_vo  <- which(grepl('"$PREV_FAIL" = "audit_not_run"', ac, fixed = TRUE) & grepl('-s "$WDIR/engine.R"', ac, fixed = TRUE))[1]
i_cl  <- which(grepl("claude -p", ac, fixed = TRUE))[1]
i_wd  <- which(grepl('WDIR="$ROOT/04_Research/strategies/RP_AUTO_${SLUG}"', ac, fixed = TRUE))[1]
calls <- which(grepl("^\\s*rp_verify; exit", ac))
if (!is.na(i_fn)) ok("C1 verify 호출이 함수 rp_verify 하나로 모였다") else ng("C1 rp_verify 없음")
if (!is.na(i_vo)) ok("C2 audit_not_run + engine.R 분기 존재") else ng("C2 분기 없음")
if (!anyNA(c(i_wd, i_fn, i_vo, i_cl)) && i_wd < i_fn && i_fn < i_vo && i_vo < i_cl)
  ok(sprintf("C3 순서: WDIR(%d) < rp_verify 정의(%d) < 분기(%d) < claude -p(%d) — 에이전트 앞에서 갈린다 ★", i_wd, i_fn, i_vo, i_cl)) else
  ng("C3 순서", sprintf("wd=%s fn=%s vo=%s cl=%s", i_wd, i_fn, i_vo, i_cl))
if (length(calls) == 2L && !is.na(i_vo) && !is.na(i_cl) && any(calls > i_vo & calls < i_cl) && any(calls > i_cl))
  ok("C4 rp_verify 호출 2곳 — 분기 안(에이전트 전) + 정상 경로(에이전트 후)") else ng("C4 호출 지점", paste(calls, collapse = ","))
if (sum(grepl('Rscript "$ROOT/02_Infrastructure/ops/rf_replication_verify.R"', ac, fixed = TRUE)) == 1L)
  ok("C5 검증기 직접 호출은 rp_verify 안 한 줄뿐(env·인자 재사용)") else ng("C5 검증기 직접 호출 수")
if (!is.na(i_vo)) {
  j_fi <- which(grepl("^fi\\s*$", ac) & seq_along(ac) > i_vo)[1]
  blk <- paste(ac[i_vo:j_fi], collapse = "\n")
  if (grepl("verify_only_retry", blk, fixed = TRUE)) ok("C6 분기가 verify_only_retry 저널을 남긴다") else ng("C6 저널 없음")
  if (grepl("d['failure']=''", blk, fixed = TRUE)) ok("C7 분기가 낡은 audit_not_run 표식을 지운다(재구현 프롬프트 오염 방지)") else ng("C7 표식 미소거")
}
if (any(grepl("'audit_not_run':", au, fixed = TRUE))) ok("C8 FAILFB 프레이밍에 audit_not_run 항목(엔진이 없을 때의 안내)") else ng("C8 프레이밍 없음")
if (any(grepl("auto_retries", au, fixed = TRUE)) && any(grepl("n < 3", au, fixed = TRUE))) ok("C9 재시도 상한 규약(auto_retries<3) 불변") else ng("C9 재시도 규약")

cat("\n=== D. audit.sh — 감사는 루프 킬스위치를 따르지 않는다 (격리 설정으로 실행) ===\n")
AUD_SH <- file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh")
cfg0 <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(cfg0)) { ng("D0 설정 템플릿 읽기 실패") } else {
  run_audit <- function(cfg, tag) {
    cp <- file.path(TMP, sprintf("cfg_%s.json", tag)); jp <- file.path(TMP, sprintf("j_%s.jsonl", tag))
    write(toJSON(cfg, auto_unbox = TRUE, pretty = TRUE, null = "null"), cp)
    ## ★Windows 의 system2(env=) 는 무시된다 — 부모 환경에 심어 자식이 상속하게 한다(형제 검사와 같은 규약)
    old_c <- Sys.getenv("QVEST_RF_CONFIG", unset = NA_character_); old_j <- Sys.getenv("QVEST_RP_JLOG", unset = NA_character_)
    Sys.setenv(QVEST_RF_CONFIG = cp, QVEST_RP_JLOG = jp)
    on.exit({ if (is.na(old_c)) Sys.unsetenv("QVEST_RF_CONFIG") else Sys.setenv(QVEST_RF_CONFIG = old_c)
              if (is.na(old_j)) Sys.unsetenv("QVEST_RP_JLOG") else Sys.setenv(QVEST_RP_JLOG = old_j) }, add = TRUE)
    out <- suppressWarnings(system2("bash", c(shQuote(AUD_SH), shQuote(file.path(TMP, "no_such_wdir")), "x", "x", "TESTKEY"),
                                    stdout = TRUE, stderr = TRUE))
    ev <- if (file.exists(jp)) vapply(readLines(jp, warn = FALSE), function(l) tryCatch(fromJSON(l)$event %||% "", error = function(e) ""), character(1)) else character(0)
    list(events = ev, out = paste(out, collapse = " | "))
  }
  c1 <- cfg0; c1$enabled <- FALSE; c1$fidelity_audit$enabled <- TRUE
  r1 <- run_audit(c1, "loop_off")
  if ("halt_no_engine" %in% r1$events && !("halt_disabled" %in% r1$events))
    ok("D1 루프 enabled=false 여도 감사는 게이트를 지난다(halt_no_engine 까지 감 · halt_disabled 아님) ★") else
    ng("D1 루프 킬스위치가 감사를 막는다", paste(r1$events, collapse = ",")
       %||% "" )
  c2 <- cfg0; c2$enabled <- TRUE; c2$fidelity_audit$enabled <- FALSE
  r2 <- run_audit(c2, "audit_off")
  if ("halt_disabled" %in% r2$events && !("halt_no_engine" %in% r2$events))
    ok("D2 fidelity_audit.enabled=false 면 halt_disabled (감사만의 스위치는 산다 · 양성 대조)") else
    ng("D2 감사 스위치가 죽었다", paste(r2$events, collapse = ","))
  sh <- paste(sub("#.*$", "", readLines(AUD_SH, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
  if (!grepl("c.get('enabled') and", sh, fixed = TRUE)) ok("D3 게이트 코드에 루프 enabled 조건이 없다(주석 제외 재도출)") else ng("D3 구판 조건 잔존")
}
unlink(TMP, recursive = TRUE, force = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_audit_not_run_blocks_open","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
