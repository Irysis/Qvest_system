#!/usr/bin/env Rscript
#==============================================================================
# test_rf_mark_vintage.R — 빈티지 표식 writer 양방향 검사 (2026-09-23 · 도훈 결정 "목록화 + 표식만")
#
# 대상: reinforce_ledger.R::rf_mark_vintage_batch / rf_mark_vintage / rf_has_vintage_flag
# 계약: append-only(보호 투영 = 표식 필드·last_updated 뺀 원장 전체 불변) · 허용 키만(essence·grade 실어 보내면 거부) ·
#       멱등 · 러너 claim 잠금 · CAS(적재 후 바뀐 원장 덮어쓰기 거부) · 배치 원자성 · 직렬화 왕복 드리프트 거부.
# 격리: 합성 픽스처 root(tempdir)만 쓴다. QVEST_RF_CLAIM 을 지워 claim 도 픽스처 root/.cache 아래에만 잡힌다.
#       운영 원장은 읽기만(픽스처 flag 이름 'zzfix_' 누출 0 확인).
# 구성:
#   P  양성 대조 — 표식이 붙고, 보호 투영·essence·grade 가 **검사 자체 구현**으로 불변, 텍스트는 last_updated 만 바뀜
#   R  위반 주입 — 허용 밖 키(essence·grade) · 판정/flag/근거 불량 · 부재 entry·n · 미측정 · 배치 원자성
#   L  잠금·CAS — 살아 있는 owner 가 쥔 claim 이면 거부 · 적재 후 외부 쓰기면 거부
#   M  돌연변이(자식 Rscript · RF_LEDGER_SRC=사본) — 잠금 제거 · 보호 가드 제거+essence 쓰기 · 멱등 제거 ·
#      키 허용목록 제거 · CAS 제거 → 이 검사가 red 여야 한다. 원본 사본(대조)은 green 이어야 한다.
#      + 가드 유지 상태의 essence 쓰기 주입 → writer 가 스스로 거부(보호 투영 불일치)해야 한다.
# env: RF_LEDGER_SRC(검사 대상 소스 · 기본 운영 파일) · RF_VINTAGE_CORE_ONLY=1(자식 모드: P/R/L 만)
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- Sys.getenv("RF_LEDGER_SRC", file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"))
CORE <- identical(Sys.getenv("RF_VINTAGE_CORE_ONLY"), "1")
Sys.unsetenv("QVEST_RF_CLAIM")        # 운영 claim 무접촉 — writer 기본값이 <픽스처 root>/.cache 로 떨어진다
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_mark_vintage","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L) }
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
md5 <- function(p) unname(tools::md5sum(p))

invisible(capture.output(source(SRC, encoding = "UTF-8")))
if (!exists("rf_mark_vintage_batch")) { ng("S0 rf_mark_vintage_batch 부재", SRC); finish() }

# ── 픽스처 — 운영 serializer(.rf_write)로 쓴 합성 원장. 한글·중첩·빈 배열·null·정수/실수 혼재 ───────────
mk_root <- function(tag) {
  d <- file.path(tempdir(), sprintf("rfmv_%s_%d_%d", tag, Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  normalizePath(d, winslash = "/")
}
ess <- function(pt, cm) list(cell_code = "B1_1", block = "B1", port_t = pt, net_sharpe = 0.978, cagr = 0.216,
                             mdd = 0.571, calmar = cm, oos_retention = -0.387, dsr = NULL,
                             selection_type = "sweep", n_trials_cumulative = 73L,
                             spec = "C:/x/.cache/rf_parallel/spec_B1_1__FIX.json", source = "authoritative_remeasure.json")
att <- function(n, grade, e) list(n = n, date = "20260920", cell_code = sprintf("B1_%d", n),
                                  idea = sprintf("[픽스처] 칸 %d — 모멘텀·가치 결합", n), keyword_axis = "multifactor",
                                  root_papers = list(), wt_id = NULL, evidence = "none", unmapped_families = list(),
                                  axiom_injected = TRUE, grade = grade, essence = e,
                                  artifacts = if (is.null(e)) NULL else sprintf("C:/x/stage_artifacts/replication/2026092%d_000000_1", n),
                                  lessons = if (is.null(e)) NULL else sprintf("[B1_%d] Grade %s · 교훈 서술", n, grade),
                                  opened_at = "2026-09-20T10:00:00+0900", closed_at = "2026-09-20T10:30:00+0900")
mk_fixture <- function(tag) {
  R <- mk_root(tag)
  obj <- .rf_skeleton(1L)
  obj$entries <- list(
    list(base_id = "FIX_A", base_grade = "B", paper_key = "2002.06975", paper_id = "", base_artifacts = "C:/x/base",
         engine_path = "C:/x/engine.R", status = "active", target_grade = "A", measurement_axis = "n_max_25",
         axis_valid = TRUE, attempts_used = 3L, judge = list(spawned = FALSE, verdict_path = NULL),
         opened_at = "2026-09-20T09:00:00+0900",
         attempts = list(att(1L, "B", ess(2.166, 0.378)), att(2L, "C", ess(1.5, 0.3)), att(3L, NA, NULL))),
    list(base_id = "FIX_B", base_grade = "C", paper_key = "2003.02515", paper_id = "", base_artifacts = "C:/x/base2",
         engine_path = "C:/x/engine2.R", status = "exhausted", target_grade = "A", measurement_axis = "n_max_25",
         axis_valid = TRUE, attempts_used = 1L, judge = list(spawned = FALSE, verdict_path = NULL),
         opened_at = "2026-09-19T09:00:00+0900", carry = list(factors = list(list(kind = "db", id = "M01_Mom_12_1"))),
         attempts = list(att(1L, "B", ess(3.1, 0.49)))))
  .rf_write(obj, 1L, R)
  R
}
L1P <- function(R) .rf_path(1L, R)
# 검사 **자체** 보호 투영 — writer 의 .rf_vintage_same 를 쓰지 않는다(돌연변이가 그 함수를 망가뜨려도 여기서 잡힌다)
t_strip <- function(o) {
  o$last_updated <- NULL
  o$entries <- lapply(o$entries, function(e) { e$base_vintage_flags <- NULL
    e$attempts <- lapply(e$attempts, function(a) { a$vintage_flags <- NULL; a }); e })
  o
}
t_same <- function(p_before_txt, p_after) {
  b <- fromJSON(p_before_txt, simplifyVector = FALSE); a <- fromJSON(p_after, simplifyVector = FALSE)
  identical(t_strip(b), t_strip(a))
}
ess_grade_same <- function(p_before_txt, p_after) {
  b <- fromJSON(p_before_txt, simplifyVector = FALSE); a <- fromJSON(p_after, simplifyVector = FALSE)
  all(unlist(Map(function(eb, ea) unlist(Map(function(x, y) identical(x$essence, y$essence) && identical(x$grade, y$grade),
                                              eb$attempts, ea$attempts)), b$entries, a$entries)))
}
norm_lines <- function(txt) sub(",$", "", sub("[[:space:]]+$", "", strsplit(txt, "\r?\n")[[1]]))
mk <- function(base_id, ak, flag, verdict = "consumed", evidence = "픽스처 근거 — run X · 9월 리밸 2026-09-01", ...)
  c(list(base_id = base_id, attempt_key = ak, flag = flag, verdict = verdict, evidence = evidence, source = "fixture"), list(...))
W <- function(R, marks, ...) rf_mark_vintage_batch(1L, marks, root = R, wait_s = 2, poll_s = 0.3, ...)

cat("=== P 양성 대조 ===\n")
R <- mk_fixture("p"); p <- L1P(R)
txt0 <- paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n"); m0 <- md5(p)
marks <- list(mk("FIX_A", 1L, "zzfix_v1"), mk("FIX_A", "2", "zzfix_v1", verdict = "possible"), mk("FIX_B", "base", "zzfix_v1"))
res <- NULL
e <- err_of(res <- W(R, marks))
if (is.na(e) && isTRUE(res$written) && identical(res$n_new, 3L)) ok("P1 3건 표식(n=1 · n=2 · base) 기록") else
  ng("P1 표식 실패", if (is.na(e)) sprintf("n_new=%s written=%s", res$n_new, res$written) else paste("P1_ERR:", e))
L <- rf_load(1L, R)
a1 <- L$entries[[1]]$attempts[[1]]; a2 <- L$entries[[1]]$attempts[[2]]; b0 <- L$entries[[2]]
f1 <- a1$vintage_flags[[1]] %||% list()
if (identical(f1$flag, "zzfix_v1") && identical(f1$verdict, "consumed") && nzchar(f1$evidence %||% "") &&
    nzchar(f1$policy %||% "") && nzchar(f1$marked_at %||% "") && identical(f1$source, "fixture"))
  ok("P2 레코드 필드(flag·verdict·evidence·source·policy·marked_at)") else ng("P2 레코드", toJSON(f1, auto_unbox = TRUE))
if (identical(a2$vintage_flags[[1]]$verdict, "possible") && length(b0$base_vintage_flags) == 1L &&
    is.null(L$entries[[1]]$attempts[[3]]$vintage_flags) && exists("rf_has_vintage_flag") &&
    isTRUE(rf_has_vintage_flag(a1, "zzfix_v1")) && isTRUE(rf_has_vintage_flag(b0, "zzfix_v1")) &&
    !isTRUE(rf_has_vintage_flag(L$entries[[1]]$attempts[[3]], "zzfix_v1")))
  ok("P3 possible·base 표식 + 대상 밖 칸 무표식 + rf_has_vintage_flag 판독") else ng("P3 표식 배치/판독")
if (t_same(txt0, p)) ok("P4 보호 투영 불변(검사 자체 구현 — 표식·last_updated 제외 원장 전체 identical)") else ng("P4 보호 투영이 바뀌었다")
if (ess_grade_same(txt0, p)) ok("P5 전 attempt essence·grade 비트 동일") else ng("P5 essence/grade 변경")
rm_lines <- setdiff(norm_lines(txt0), norm_lines(paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")))
if (length(rm_lines) == 1L && grepl('"last_updated"', rm_lines)) ok("P6 텍스트: 사라진 원래 줄 = last_updated 1줄뿐(append-only)") else
  ng("P6 원래 줄이 사라졌다", paste(head(rm_lines, 3), collapse = " | "))
m1 <- md5(p)
res2 <- NULL; e <- err_of(res2 <- W(R, marks))
if (is.na(e) && identical(res2$n_new, 0L) && identical(res2$n_already, 3L) && !isTRUE(res2$written) && identical(md5(p), m1))
  ok("P7 멱등 — 같은 배치 재실행: 신규 0 · 기존 3 · 쓰기 없음(md5 동일)") else ng("P7 멱등", if (is.na(e)) sprintf("n_new=%s", res2$n_new) else e)
res3 <- NULL; e <- err_of(res3 <- W(R, list(mk("FIX_A", 1L, "zzfix_v2"), mk("FIX_A", 1L, "zzfix_v2"))))
L <- rf_load(1L, R)
if (is.na(e) && identical(res3$n_new, 1L) && identical(res3$n_already, 1L) && length(L$entries[[1]]$attempts[[1]]$vintage_flags) == 2L)
  ok("P8 배치 안 중복 1회만 · 다른 flag 는 누적(v1+v2)") else ng("P8 배치 안 중복", e)
cl <- file.path(R, ".cache", "reinforce_auto.claim")
if (!dir.exists(cl) || file.exists(file.path(cl, "released.json"))) ok("P9 성공 후 claim 해제(디렉터리 부재 또는 해제 표식)") else ng("P9 claim 잔존")

cat("\n=== R 위반 주입 ===\n")
R <- mk_fixture("r"); p <- L1P(R); m0 <- md5(p)
e <- err_of(W(R, list(mk("FIX_A", 1L, "zzfix_x", essence = list(port_t = 9.9)))))
if (!is.na(e) && grepl("허용 밖 키", e) && identical(md5(p), m0)) ok("R1 essence 를 실은 표식 거부 · 원장 불변") else ng("R1 essence 주입", e)
e <- err_of(W(R, list(mk("FIX_A", 1L, "zzfix_x", grade = "A"))))
if (!is.na(e) && grepl("허용 밖 키", e) && identical(md5(p), m0)) ok("R2 grade 를 실은 표식 거부 · 원장 불변") else ng("R2 grade 주입", e)
bad <- list(mk("FIX_A", 1L, "zzfix_x", verdict = "not_consumed"), mk("FIX_A", 1L, "Bad-Flag"),
            mk("FIX_A", 1L, "zzfix_x", evidence = ""), mk("FIX_A", "n1", "zzfix_x"))
e_all <- vapply(bad, function(b) err_of(W(R, list(b))), character(1))
if (all(!is.na(e_all)) && identical(md5(p), m0)) ok("R3 판정 not_consumed · flag 형식 · 빈 근거 · attempt_key 형식 — 4종 거부") else
  ng("R3 형식 거부", paste(e_all, collapse = " | "))
e_all <- c(err_of(W(R, list(mk("NOPE", 1L, "zzfix_x")))), err_of(W(R, list(mk("FIX_A", 99L, "zzfix_x")))),
           err_of(W(R, list(mk("FIX_A", 3L, "zzfix_x")))))
if (all(!is.na(e_all)) && grepl("미측정", e_all[3]) && identical(md5(p), m0)) ok("R4 부재 entry · 부재 n · 미측정 칸 거부") else
  ng("R4 대상 거부", paste(e_all, collapse = " | "))
e <- err_of(W(R, list(mk("FIX_A", 1L, "zzfix_ok"), mk("FIX_A", 99L, "zzfix_ok"))))
if (!is.na(e) && identical(md5(p), m0)) ok("R5 배치 원자성 — 유효 1 + 무효 1 이면 아무것도 안 쓴다") else ng("R5 부분 쓰기", e)
# 직렬화 드리프트: 다른 writer 가 7자리 이상 수를 써 둔 원장 → .rf_write(digits=6) 왕복이 essence 를 깎는다 → 거부
Rd <- mk_fixture("d"); pd <- L1P(Rd)
tx <- readLines(pd, warn = FALSE, encoding = "UTF-8"); k <- grep('"port_t": 2.166', tx, fixed = TRUE)[1]
tx[k] <- sub("2.166", "2.16612345678", tx[k], fixed = TRUE); writeLines(tx, pd, useBytes = TRUE); md <- md5(pd)
e <- err_of(W(Rd, list(mk("FIX_A", 1L, "zzfix_d"))))
if (!is.na(e) && grepl("직렬화 왕복", e) && identical(md5(pd), md)) ok("R6 직렬화 왕복이 essence 자릿수를 깎는 원장 → 쓰기 거부 · 원장 불변") else
  ng("R6 직렬화 드리프트 미검출", e)

cat("\n=== L 잠금 · CAS ===\n")
R <- mk_fixture("l"); p <- L1P(R); m0 <- md5(p)
cl <- file.path(R, ".cache", "reinforce_auto.claim"); dir.create(cl, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(pid = Sys.getpid(), started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")), auto_unbox = TRUE),
           file.path(cl, "owner.json"))
t0 <- Sys.time(); e <- err_of(W(R, list(mk("FIX_A", 1L, "zzfix_l"))))
if (!is.na(e) && grepl("잠금", e) && identical(md5(p), m0)) ok(sprintf("L1 살아 있는 owner 가 claim 보유 → 대기 후 거부 · 원장 불변 (%.1fs)",
                                                          as.numeric(difftime(Sys.time(), t0, units = "secs")))) else ng("L1 잠금 무시", e)
unlink(cl, recursive = TRUE)
e <- err_of(W(R, list(mk("FIX_A", 1L, "zzfix_l"))))
if (is.na(e) && !identical(md5(p), m0)) ok("L2 claim 해제 후 같은 배치 기록") else ng("L2 해제 후 기록 실패", e)
m1 <- md5(p)
hook <- function(pp) { x <- readLines(pp, warn = FALSE, encoding = "UTF-8"); writeLines(c(x, ""), pp, useBytes = TRUE) }
e <- err_of(W(R, list(mk("FIX_A", 2L, "zzfix_cas")), .pre_write_hook = hook))
mh <- md5(p)
if (!is.na(e) && grepl("동시 쓰기", e) && !identical(mh, m1) && !any(grepl("zzfix_cas", readLines(p, warn = FALSE))))
  ok("L3 CAS — 적재 후 외부 쓰기 → 덮어쓰지 않고 거부(외부 판 보존)") else ng("L3 CAS 미검출", e)

if (CORE) finish()

cat("\n=== M 돌연변이 (자식 Rscript · 사본 소스) ===\n")
src_txt <- readLines(SRC, warn = FALSE, encoding = "UTF-8")
EMPTY_ENV <- file.path(tempdir(), sprintf("rfmv_empty_%d.Renviron", Sys.getpid())); writeLines(character(0), EMPTY_ENV)
THIS <- normalizePath(file.path(ROOT, "08_Tests/reinforcement/test_rf_mark_vintage.R"), winslash = "/", mustWork = FALSE)
if (!file.exists(THIS)) THIS <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]), winslash = "/")
run_child <- function(src_lines, tag) {
  f <- file.path(tempdir(), sprintf("rfmv_mut_%s_%d.R", tag, Sys.getpid()))
  writeLines(src_lines, f, useBytes = TRUE)
  # ★system2(env=) 는 Windows 에서 명령을 못 띄운다(실측 status 5 · 출력 0) — 부모 env 를 잠시 세우고 상속시킨 뒤 되돌린다
  kv <- c(RF_LEDGER_SRC = normalizePath(f, winslash = "/"), RF_VINTAGE_CORE_ONLY = "1",
          R_ENVIRON_USER = normalizePath(EMPTY_ENV, winslash = "/"), QM_ROOT = ROOT)
  old <- Sys.getenv(names(kv), unset = NA)
  do.call(Sys.setenv, as.list(kv))
  out <- tryCatch(suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(THIS), stdout = TRUE, stderr = TRUE)),
                  finally = { for (k in names(kv)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) })
  j <- tail(grep('^\\{"test":"rf_mark_vintage"', out, value = TRUE), 1)
  s <- if (length(j)) fromJSON(j) else list(pass = NA, fail = NA)
  list(pass = s$pass, fail = s$fail, out = out)
}
subst <- function(lines, from, to, expect) {
  hits <- sum(vapply(lines, function(l) lengths(regmatches(l, gregexpr(from, l, fixed = TRUE))), integer(1)))
  if (hits != expect) return(NULL)
  vapply(lines, function(l) gsub(from, to, l, fixed = TRUE), character(1), USE.NAMES = FALSE)
}
ctl <- run_child(src_txt, "ctl")
if (identical(as.integer(ctl$fail), 0L) && isTRUE(ctl$pass > 0)) ok(sprintf("M0 대조 — 원본 사본으로 자식 검사 green (%s 통과)", ctl$pass)) else
  ng("M0 대조가 green 이 아니다(돌연변이 판정 무의미)", paste(tail(ctl$out, 5), collapse = " | "))
muts <- list(
  list(tag = "nolock", d = "잠금 획득 제거(항상 ok)", s = list(c("ac <- .cl$rf_claim_acquire(claim, stale_hours = 6)", "ac <- list(ok = TRUE)", 1L))),
  list(tag = "noguard_ess", d = "보호 가드 3곳 제거 + essence 쓰기 주입",
       s = list(c("obj$entries[[i]]$attempts[[j]]$vintage_flags <- c(fl, list(rec))",
                  "obj$entries[[i]]$attempts[[j]]$vintage_flags <- c(fl, list(rec)); obj$entries[[i]]$attempts[[j]]$essence$port_t <- 0", 1L),
                c("if (!.rf_vintage_same(obj, orig))", "if (FALSE)", 1L),
                c("if (!.rf_vintage_same(.rt, orig))", "if (FALSE)", 1L),
                c("if (is.null(back) || !.rf_vintage_same(back, orig))", "if (FALSE)", 1L))),
  list(tag = "noidem", d = "멱등(기존 flag 건너뛰기) 제거", s = list(c("n_already <- n_already + 1L; next }", "invisible(NULL) }", 2L))),
  list(tag = "nokeys", d = "키 허용목록 제거", s = list(c("if (length(extra))", "if (FALSE)", 1L))),
  list(tag = "nocas", d = "CAS 제거", s = list(c("if (!identical(unname(tools::md5sum(p)), md5_0))", "if (FALSE)", 1L))))
for (mu in muts) {
  L2 <- src_txt; okk <- TRUE
  for (s in mu$s) { L2 <- subst(L2, s[1], s[2], as.integer(s[3])); if (is.null(L2)) { okk <- FALSE; break } }
  if (!okk) { ng(sprintf("M-%s 주입 실패(대상 문자열 수 불일치 — 소스가 바뀌었다)", mu$tag)); next }
  r <- run_child(L2, mu$tag)
  if (isTRUE(r$fail > 0)) ok(sprintf("M-%s %s → 검사 red (실패 %s)", mu$tag, mu$d, r$fail)) else
    ng(sprintf("M-%s %s 를 못 잡는다", mu$tag, mu$d), sprintf("pass=%s fail=%s", r$pass, r$fail))
}
# 가드 유지 상태의 essence 쓰기 주입 → writer 가 스스로 거부해야 한다(자식 P1 이 보호 투영 불일치 메시지로 실패)
L2 <- subst(src_txt, "obj$entries[[i]]$attempts[[j]]$vintage_flags <- c(fl, list(rec))",
            "obj$entries[[i]]$attempts[[j]]$vintage_flags <- c(fl, list(rec)); obj$entries[[i]]$attempts[[j]]$essence$port_t <- 0", 1L)
if (is.null(L2)) ng("G1 주입 실패") else {
  r <- run_child(L2, "guard_ess")
  if (any(grepl("P1_ERR:.*표식 밖 필드가 바뀌었다", r$out))) ok("G1 essence 쓰기 주입(가드 유지) → writer 가 보호 투영 불일치로 스스로 거부") else
    ng("G1 가드가 essence 쓰기를 못 막는다", paste(head(grep("P1", r$out, value = TRUE), 3), collapse = " | "))
}

cat("\n=== C 운영 무접촉 ===\n")
leak <- vapply(c(1L, 2L), function(ly) { pp <- .rf_path(ly, ROOT)
  file.exists(pp) && any(grepl("zzfix_", readLines(pp, warn = FALSE), fixed = TRUE)) }, logical(1))
if (!any(leak)) ok("C1 운영 원장 L1/L2 에 픽스처 flag('zzfix_') 누출 0") else ng("C1 운영 원장에 픽스처 표식이 새었다")
finish()
