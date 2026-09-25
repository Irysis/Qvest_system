#!/usr/bin/env Rscript
#==============================================================================
# test_rf_backfill_lifecycle.R — 무인 백필 tick 의 lifecycle 자격 술어 (C11 2단계 · 2026-09-25)
#
# 왜: rf_factor_backfill_tick.R::rf_backfill_candidates 가 lifecycle 을 deprecated **한 값만** 뺐다.
#   2026-09-24 C11 퇴역(decision_register PIT-C11-MA0102)으로 status "retired" 가 된 MA01·MA02 는
#   산출이 멈춰 IC 개월수가 줄면 후보가 되고, compute_regime 이 더는 내지 않으니 443개월을 "empty" 로
#   헛돌린다(백필 예산 소진 · 퇴역 팩터 부활 시도). 수리 = 소비자(rf_factor_arms::rf_factor_pool)와 같은
#   화이트리스트 술어 rf_bf_lifecycle_live(status 없음 = active, 그 밖엔 "active" 만).
#
# 설계(양방향):
#   T1 양성   — active · status 미기재 팩터는 후보(소비자 폴백과 같은 뜻)
#   T2 음성   — deprecated · retired · 그 밖의 비활성 값(candidate)은 후보 아님
#   T3 술어 단위 — NULL 항목 = FALSE(등재 없는 id 는 팩터가 아니다)
#   T4 배선   — 후보 함수가 술어를 **실제로 부른다**: 술어를 돌연변이로 갈아끼우면 결과가 바뀌어야 한다
#               (M1 구판 의미 "deprecated 만 제외" → retired 가 샌다 · M2 항상 TRUE → 비활성 전부 샌다)
#   T5 실물 재도출 — 운영 registry 를 JSON 으로 따로 읽어 active 가 아닌 집합을 세고, 술어가 뺀 집합과 같은지
#               (MA01·MA02 가 retired 로 빠지는지) — 읽기 전용
# 실행: cd <ROOT> && Rscript 08_Tests/ops/test_rf_backfill_lifecycle.R
#   (돌연변이 대상 파일 주입: QVEST_BF_SRC=<경로> — 수리 전 판을 넣으면 red 여야 한다)
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC <- Sys.getenv("QVEST_BF_SRC", file.path(ROOT, "02_Infrastructure/ops/rf_factor_backfill_tick.R"))

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

cat(sprintf("== 백필 lifecycle 자격 (%s) ==\n", SRC))
if (!file.exists(SRC)) { ng("대상 파일 부재", SRC); cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail)); quit(status = 1L) }

# ── AST 적재 (파일 끝에서 main() 이 돌므로 source 불가) · jlog 는 무음 스텁 ─────
EXPRS <- parse(SRC, encoding = "UTF-8")
ENV <- new.env(parent = globalenv())
assign("%||%", `%||%`, envir = ENV)
assign("jlog", function(event, ...) invisible(NULL), envir = ENV)
.load <- function(nm) {
  for (e in EXPRS) if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") &&
                       identical(as.character(e[[2]]), nm)) {
    assign(nm, eval(e[[3]], envir = ENV), envir = ENV); return(TRUE) }
  FALSE
}
has_pred <- .load("rf_bf_lifecycle_live")
has_cand <- .load("rf_backfill_candidates")
if (!has_pred) ng("술어 rf_bf_lifecycle_live 부재 — lifecycle 판정이 다시 인라인(블랙리스트)으로 돌아갔다")
if (!has_cand) ng("rf_backfill_candidates 부재")

# ── 합성 픽스처 루트: registry + 월 파일 이름 2개(내용 불요 — 개수만 센다) · IC 없음 → have 0 ──
FIX <- list(
  A_active  = list(category = "value",  lifecycle = list(status = "active")),
  B_dep     = list(category = "value",  lifecycle = list(status = "deprecated")),
  C_ret     = list(category = "regime", lifecycle = list(status = "retired")),
  D_nolc    = list(category = "value"),                                   # lifecycle 미기재
  E_cand    = list(category = "value",  lifecycle = list(status = "candidate")),
  F_nostat  = list(category = "value",  lifecycle = list(research_stage = "S0"))  # status 키 없음
)
.mkroot <- function(reg) {
  d <- file.path(tempdir(), paste0("bfl_", paste(sample(letters, 8), collapse = "")))
  dir.create(file.path(d, ".cache/factor_db"), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(reg, auto_unbox = TRUE, pretty = TRUE), file.path(d, ".cache/factor_db/factor_registry.json"))
  for (ym in c("200501", "200502")) file.create(file.path(d, ".cache/factor_db", sprintf("factor_db_%s.parquet", ym)))
  d
}
.cands <- function(root) {
  assign("ROOT", root, envir = ENV); assign("FDB", file.path(root, ".cache/factor_db"), envir = ENV)
  r <- suppressWarnings(capture.output(res <- get("rf_backfill_candidates", envir = ENV)(root = root)))
  if (is.null(res)) character(0) else as.character(res$id)
}

if (has_cand) {
  root <- .mkroot(FIX)
  ids <- .cands(root)
  # T1 양성
  if (all(c("A_active", "D_nolc", "F_nostat") %in% ids))
    ok("T1 [양성] active · lifecycle/status 미기재 팩터는 후보(소비자 폴백 = active)")
  else ng("T1 양성 누락", paste(setdiff(c("A_active", "D_nolc", "F_nostat"), ids), collapse = ","))
  # T2 음성
  leak <- intersect(c("B_dep", "C_ret", "E_cand"), ids)
  if (!length(leak)) ok("T2 [음성] deprecated · retired · candidate(비활성) 는 후보 아님")
  else ng("T2 비활성 팩터가 후보로 샜다", paste(leak, collapse = ","))
}
if (has_pred && has_cand) {
  # T3 술어 단위
  P <- get("rf_bf_lifecycle_live", envir = ENV)
  u <- c(null = P(NULL), act = P(list(lifecycle = list(status = "active"))),
         ret = P(list(lifecycle = list(status = "retired"))), dep = P(list(lifecycle = list(status = "deprecated"))),
         nolc = P(list(category = "x")), empty_status = P(list(lifecycle = list(status = character(0)))))
  exp <- c(null = FALSE, act = TRUE, ret = FALSE, dep = FALSE, nolc = TRUE, empty_status = TRUE)
  if (identical(u, exp)) ok("T3 술어 단위 6경우 (NULL=FALSE · active=TRUE · retired/deprecated=FALSE · 미기재=TRUE)")
  else ng("T3 술어 단위 불일치", paste(names(u)[u != exp], collapse = ","))

  # T4 배선 — 술어를 돌연변이로 바꾸면 후보가 바뀌어야 한다(후보 함수가 술어를 실제로 부르는가)
  P0 <- P
  assign("rf_bf_lifecycle_live", function(e) !identical(as.character((e$lifecycle %||% list())$status %||% "")[1], "deprecated"), envir = ENV)
  m1 <- .cands(root)
  assign("rf_bf_lifecycle_live", function(e) TRUE, envir = ENV)
  m2 <- .cands(root)
  assign("rf_bf_lifecycle_live", P0, envir = ENV)
  if ("C_ret" %in% m1 && !("B_dep" %in% m1))
    ok("T4a [돌연변이 M1 구판 의미 'deprecated 만 제외'] retired 가 샌다 = 이 검사가 red 를 낸다")
  else ng("T4a 돌연변이 M1 이 결과를 못 바꿨다 — 후보 함수가 술어를 안 부른다(배선 끊김)", paste(m1, collapse = ","))
  if (all(c("B_dep", "C_ret", "E_cand") %in% m2))
    ok("T4b [돌연변이 M2 항상 TRUE] 비활성 3종 전부 샌다 = red")
  else ng("T4b 돌연변이 M2 무반응", paste(m2, collapse = ","))
  if (identical(sort(.cands(root)), sort(ids))) ok("T4c 원 술어 복원 후 결과 복귀(돌연변이 누수 없음)")
  else ng("T4c 복원 후 결과 불일치")

  # T5 실물 재도출 — 운영 registry(읽기 전용)
  rp <- file.path(ROOT, ".cache/factor_db/factor_registry.json")
  if (!file.exists(rp)) ng("T5 운영 registry 부재", rp) else {
    reg <- fromJSON(rp, simplifyVector = FALSE)
    st <- vapply(reg, function(e) { s <- (e$lifecycle %||% list())$status; if (is.null(s) || !length(s)) "active" else as.character(s)[1] }, character(1))
    want_out <- sort(names(st)[st != "active"])
    got_out  <- sort(names(reg)[!vapply(reg, P, logical(1))])
    if (identical(want_out, got_out) && all(c("MA01_GDP_Sensitivity", "MA02_CPI_Sensitivity") %in% got_out))
      ok(sprintf("T5 실물 재도출 — 비활성 %d종(%s) = 술어 제외 집합 · MA01/MA02 포함",
                 length(got_out), paste(sprintf("%s %d", names(table(st[got_out])), as.integer(table(st[got_out]))), collapse = " · ")))
    else ng("T5 실물 불일치", sprintf("재도출 %s vs 술어 %s", paste(want_out, collapse = ","), paste(got_out, collapse = ",")))
  }
}

cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
# 요약 JSON(run_all_hooks.sh 계약 — 없으면 UNMEASURED · 2026-09-25 C11 S9 에서 미측정으로 드러남)
cat(sprintf('{"test":"test_rf_backfill_lifecycle","pass":%d,"fail":%d,"skipped":0,"total":%d,"skips":[]}\n', .pass, .fail, .pass + .fail))
if (.fail > 0L) quit(status = 1L)
