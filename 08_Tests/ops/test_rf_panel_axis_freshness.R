#!/usr/bin/env Rscript
#==============================================================================
# test_rf_panel_axis_freshness.R — 축 사이드카 갱신의 **술어·배선·실패 가시성** 검사
#
# 왜 (실사고 2026-09-01~21, 20일): `factor_panel_axis.json` 이 369종에 멈춰 있었다. 원인이 둘이었다.
#   ① 갱신 조건이 "이번 tick 이 백필했는가"(length(done))였다. 자동등록 레인은 자기가 직접
#      backfill+IC 를 돌리므로 그 done 에 절대 안 들어온다 → 남이 채운 팩터는 영영 반영 안 됨.
#      게다가 호출이 `nothing_to_backfill` **조기 반환 뒤**라 백필 없는 밤엔 도달조차 못 했다.
#   ② 그 호출이 실제로 돌던 때도 **죽어 있었다** — classify_panel_axis.py 는 pandas 를 쓰는데
#      QVEST_PY(시스템 Python 3.12)에 pandas 가 없다. system2 는 종료코드로 예외를 안 던지므로
#      `tryCatch(error=)` 는 아무것도 못 잡았다. 낡은 게 아니라 **줄곧 실패했고 조용했다**.
#
# 설계: 양방향. 술어는 합성 픽스처로 양성/음성, 실패는 **주입**해서 보이는지 본다.
# 실행: cd <ROOT> && Rscript 08_Tests/ops/test_rf_panel_axis_freshness.R
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
SRC <- file.path(ROOT, "02_Infrastructure/ops/rf_factor_backfill_tick.R")

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

# ── AST 적재 (파일 끝에서 main() 이 돌므로 source 불가) · jlog 은 포획 스텁으로 ──
EXPRS <- parse(SRC)
ENV <- new.env(parent = globalenv())
assign("%||%", `%||%`, envir = ENV); assign("ROOT", ROOT, envir = ENV)
.EV <- new.env(); .EV$log <- list()
assign("jlog", function(event, ...) { .EV$log[[length(.EV$log) + 1L]] <- c(list(event = event), list(...)); invisible(NULL) }, envir = ENV)
.load <- function(nm) {
  for (e in EXPRS) if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && identical(as.character(e[[2]]), nm)) {
    assign(nm, eval(e[[3]], envir = ENV), envir = ENV); return(TRUE) }
  FALSE
}
for (nm in c("rf_panel_axis_stale", "rf_panel_axis_py", "rf_panel_axis_refresh"))
  if (!.load(nm)) { cat(sprintf("  [NG] %s 부재 — 갱신이 다시 인라인으로 돌아갔다\n", nm)); .fail <- .fail + 1L }

cat("== 축 사이드카 신선도 ==\n")

.mkroot <- function(reg_ids, ax_ids) {
  d <- file.path(tempdir(), paste0("pax_", paste(sample(letters, 6), collapse = "")))
  dir.create(file.path(d, ".cache/factor_db"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  wr <- function(p, ids) write(toJSON(list(factors = setNames(
    lapply(ids, function(z) list(lifecycle = list(status = "active"))), ids)), auto_unbox = TRUE), p)
  wr(file.path(d, ".cache/factor_db/factor_registry.json"), reg_ids)
  wr(file.path(d, "06_Registry/factor_panel_axis.json"), ax_ids)
  d
}

if (exists("rf_panel_axis_stale", envir = ENV)) {
  F <- get("rf_panel_axis_stale", envir = ENV)
  # T1 [양성] registry 에만 있는 id → stale
  r1 <- F(.mkroot(c("A", "B", "C"), c("A", "B")))
  if (isTRUE(r1$stale) && identical(r1$missing, "C")) ok("T1 [양성] registry 에만 있는 id 를 미등재로 집는다")
  else ng("T1 stale 미탐지", toJSON(r1$missing, auto_unbox = TRUE))
  # T2 [음성] 집합이 같으면 not stale — 상시 갱신(상시 오탐)이 되지 않는다
  r2 <- F(.mkroot(c("A", "B"), c("A", "B")))
  if (!isTRUE(r2$stale)) ok("T2 [음성] 집합이 같으면 갱신하지 않는다(상시 재생성 방지)")
  else ng("T2 음성 대조 실패", r2$reason)
  # T3 사이드카 부재 → stale (첫 생성 경로)
  d3 <- .mkroot(c("A"), c("A")); unlink(file.path(d3, "06_Registry/factor_panel_axis.json"))
  if (isTRUE(F(d3)$stale)) ok("T3 사이드카 부재 → stale") else ng("T3 부재를 신선으로 읽었다")
  # T7 실물 — 지금 저장소가 맞아 있는가
  rr <- F(ROOT)
  if (!isTRUE(rr$stale)) ok(sprintf("T7 실물 신선 — %s", rr$reason))
  else ng("T7 실물 미등재", paste(utils::head(rr$missing, 3), collapse = ","))
}

# ── T4 인터프리터 — 고른 실행기가 **실제로 pandas 를 갖고 있는가**(재도출) ──
if (exists("rf_panel_axis_py", envir = ENV)) {
  py <- get("rf_panel_axis_py", envir = ENV)(ROOT)
  if (!nzchar(py)) ng("T4 인터프리터 미발견") else {
    st <- suppressWarnings(system2(py, c("-c", shQuote("import pandas")), stdout = TRUE, stderr = TRUE))
    if (identical(as.integer(attr(st, "status") %||% 0L), 0L))
      ok(sprintf("T4 선택된 실행기에 pandas 있음 (%s)", basename(dirname(dirname(py)))))
    else ng("T4 선택된 실행기에 pandas 없음 — 갱신이 조용히 죽는다", py)
  }
}

# ── T5 [실패 주입] 스크립트가 없는 가짜 root → status!=0 을 **보고** 하는가 ──
if (exists("rf_panel_axis_refresh", envir = ENV)) {
  .EV$log <- list()
  res <- get("rf_panel_axis_refresh", envir = ENV)("test_injected", root = .mkroot(c("A"), c("A")))
  evs <- vapply(.EV$log, function(z) as.character(z$event), character(1))
  if (isFALSE(res) && "panel_axis_failed" %in% evs)
    ok("T5 [실패 주입] 종료코드 비0 을 실패로 기록한다(예외가 아니어도)")
  else ng("T5 실패를 삼켰다", sprintf("res=%s events=%s", res, paste(evs, collapse = ",")))
}

# ── T6 배선 순서 재도출 — 갱신이 `nothing_to_backfill` 조기 반환보다 **앞**인가 ──
.body <- NULL
## ★`function(a) b` 의 AST 는 [[1]]=function · [[2]]=formals · [[3]]=**body** · [[4]]=srcref 다.
##   초판이 length() 로 마지막을 집어 srcref 를 본문으로 읽고 파싱에 실패했다(검사 쪽 오류).
for (e in EXPRS) if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") && identical(as.character(e[[2]]), "main"))
  .body <- e[[3]][[3]]
if (is.null(.body)) ng("T6 main 본문 파싱 실패") else {
  txt <- vapply(as.list(.body)[-1], function(x) paste(deparse(x), collapse = " "), character(1))
  i_ax <- which(grepl("rf_panel_axis_stale|rf_panel_axis_refresh", txt))
  i_rt <- which(grepl("nothing_to_backfill", txt))
  if (length(i_ax) && length(i_rt) && min(i_ax) < min(i_rt))
    ok(sprintf("T6 갱신(%d번째)이 조기 반환(%d번째)보다 앞", min(i_ax), min(i_rt)))
  else ng("T6 갱신이 조기 반환 뒤 — 백필 없는 밤엔 도달하지 못한다",
          sprintf("ax=%s rt=%s", paste(i_ax, collapse = ","), paste(i_rt, collapse = ",")))
}

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L)
