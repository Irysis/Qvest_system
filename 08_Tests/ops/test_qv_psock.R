#==============================================================================
# test_qv_psock.R — PSOCK 클러스터 포트 탐색기(qv_psock.R) 검사 (2026-11-09)
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md 금칙 ⑧ (makePSOCKcluster · makeCluster 직접 호출 금지 → qv_psock_cluster())
# 전제(메인 PC 실측 11-08): Windows 포트 예약이 R parallel 기본 범위 11000–11999 의 53% 를 막는다. 점유된 포트는 예약 포트와
#   같은 오류('creation of server socket failed: port N cannot be opened')를 내므로 시험은 포트를 미리 점유해 어느 PC 에서나 재현한다.
#
# 축: ① 정상 — 작업자가 실제로 일한다 · 쓴 포트 기록 ② ★위반 주입 — 첫 후보 포트를 미리 점유 → 건너뛰고 다음 후보로 성공
#   ③ 후보가 전부 막힘 → stop(조용히 NULL 아님) · 메시지에 예약 확인 명령 ④ 포트 아닌 오류는 재시도 없이 그대로 올라온다
#   ⑤ R_PARALLEL_PORT(숫자) = 그 포트 그대로 ⑥ 전역 난수(.Random.seed) 불변 ⑦ 후보 순서 = 범위 안 · 중복 없음
#   ⑧ 돌연변이 통제: 재시도를 지운 사본은 ② 에서 잡혀야 한다(소스 텍스트 치환 · 치환 성사 확인)
#   ⑨ 정적: 운영 R 코드에 makePSOCKcluster · makeCluster 직접 호출 0(이 도우미 · 08_Tests · 보관소 제외)
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))

.self <- tryCatch(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1]),
                                winslash = "/", mustWork = TRUE), error = function(e) NA_character_)
.cands <- c(if (!is.na(.self)) dirname(dirname(dirname(.self))),
            Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))
.cands <- gsub("\\\\", "/", .cands[nzchar(.cands)])
ROOT <- .cands[file.exists(file.path(.cands, "02_Infrastructure/ops/qv_psock.R"))][1]
if (is.na(ROOT)) stop("프로젝트 루트 미발견(02_Infrastructure/ops/qv_psock.R 표지)")
SRC <- file.path(ROOT, "02_Infrastructure/ops/qv_psock.R")

PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)
cl_ok <- function(cl) isTRUE(tryCatch(identical(unlist(parallel::clusterCall(cl, function() 1L + 1L)), rep(2L, length(cl))), error = function(e) FALSE))
free_port <- function(from, avoid = integer(0)) {   # 지금 열 수 있는 포트(열었다 닫는다)
  for (q in setdiff(from:(from + 400L), avoid)) { s <- tryCatch(serverSocket(q), error = function(e) NULL); if (!is.null(s)) { close(s); return(q) } }
  NA_integer_
}

cat("=== qv_psock ===\n")
Sys.unsetenv("R_PARALLEL_PORT")
E <- new.env(parent = globalenv()); sys.source(SRC, envir = E)

# ─── ① 정상 ─────────────────────────────────────────────────────────────────
cl <- tryCatch(E$qv_psock_cluster(2L), error = function(e) e)
chk("ok_default_cluster_works", !inherits(cl, "error") && cl_ok(cl) && length(cl) == 2L,
    if (inherits(cl, "error")) conditionMessage(cl) else sprintf("작업자 2 · 포트 %s", attr(cl, "qv_port")))
chk("ok_port_recorded_in_range", !inherits(cl, "error") && isTRUE(attr(cl, "qv_port") >= 11000L && attr(cl, "qv_port") <= 11999L))
if (!inherits(cl, "error")) parallel::stopCluster(cl)

# ─── ② 위반 주입 — 첫 후보 점유 ──────────────────────────────────────────────
P1 <- free_port(20001L); P2 <- free_port(20501L, avoid = P1)
hold <- tryCatch(serverSocket(P1), error = function(e) NULL)
chk("inject_port_occupied", !is.null(hold) && inherits(tryCatch(serverSocket(P1), error = function(e) e), "error"),
    sprintf("P1 %s 점유 · 두 번째 열기 = 오류(예약 포트와 같은 증상)", P1))
cl <- tryCatch(E$qv_psock_cluster(1L, ports = c(P1, P2)), error = function(e) e)
chk("inject_skips_blocked_port", !inherits(cl, "error") && identical(attr(cl, "qv_port"), as.integer(P2)) && cl_ok(cl),
    if (inherits(cl, "error")) conditionMessage(cl) else sprintf("막힌 %d 건너뜀 → %d", P1, attr(cl, "qv_port")))
if (!inherits(cl, "error")) parallel::stopCluster(cl)

# ─── ③ 전부 막힘 → stop ──────────────────────────────────────────────────────
e3 <- tryCatch(E$qv_psock_cluster(1L, ports = c(P1)), error = function(e) e)
chk("all_blocked_stops_loudly", inherits(e3, "error") && grepl("못 찾았다", conditionMessage(e3)) && grepl("excludedportrange", conditionMessage(e3)),
    if (inherits(e3, "error")) substr(conditionMessage(e3), 1, 90) else "오류 없이 돌아옴")
if (!is.null(hold)) close(hold)

# ─── ④ 포트 아닌 오류는 재시도 없이 그대로 ────────────────────────────────────
calls <- 0L
fake_mk <- function(...) { calls <<- calls + 1L; stop("worker launch failed: rscript not found") }   # 포트가 아닌 실패
t4 <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
a4 <- "parallel::makePSOCKcluster(n, port = p, ...)"
n4 <- sum(grepl(a4, t4, fixed = TRUE))
F4 <- tempfile(fileext = ".R"); writeLines(gsub(a4, "fake_mk(n, port = p, ...)", t4, fixed = TRUE), F4, useBytes = TRUE)
E4 <- new.env(parent = globalenv()); sys.source(F4, envir = E4)
e4 <- tryCatch(E4$qv_psock_cluster(1L, ports = c(P1, P2)), error = function(e) e)
chk("non_port_error_not_retried", n4 == 1L && inherits(e4, "error") && grepl("worker launch failed", conditionMessage(e4)) && calls == 1L,
    sprintf("치환 %d곳 · 호출 %d회 · %s", n4, calls, if (inherits(e4, "error")) conditionMessage(e4) else "오류 없음"))

# ─── ⑤ R_PARALLEL_PORT(숫자) 존중 ────────────────────────────────────────────
P5 <- free_port(21001L, avoid = c(P1, P2))
S5 <- tempfile(fileext = ".R")   # 기본 포트는 parallel 을 불러올 때 정해지므로 새 프로세스에서 잰다(-e 대신 파일 — Windows 인용 회피)
writeLines(c(sprintf("source('%s')", SRC), "cl <- qv_psock_cluster(1L)",
             "cat('PORT', parallel:::getClusterOption('port'), 'ATTR', if (is.null(attr(cl, 'qv_port'))) 'none' else attr(cl, 'qv_port'), '\\n')",
             "parallel::stopCluster(cl)"), S5)
Sys.setenv(R_PARALLEL_PORT = as.character(P5))
r5 <- tryCatch(system2(file.path(R.home("bin"), "Rscript"), shQuote(S5), stdout = TRUE, stderr = TRUE), error = function(e) conditionMessage(e))
Sys.unsetenv("R_PARALLEL_PORT")
chk("env_port_respected", any(grepl(sprintf("PORT %d ATTR none", P5), r5)),
    paste(grep("PORT|rror", r5, value = TRUE), collapse = " | "))

# ─── ⑥ 전역 난수 불변 ────────────────────────────────────────────────────────
set.seed(20261109); s0 <- .Random.seed
cl <- tryCatch(E$qv_psock_cluster(1L), error = function(e) e)
chk("rng_untouched", identical(s0, .Random.seed), "set.seed 뒤 .Random.seed 그대로")
if (!inherits(cl, "error")) parallel::stopCluster(cl)

# ─── ⑦ 후보 순서 ─────────────────────────────────────────────────────────────
cd <- E$.qv_psock_candidates(1000L)
chk("candidates_cover_range_no_dup", length(cd) == 1000L && !anyDuplicated(cd) && all(cd >= 11000L & cd <= 11999L),
    sprintf("%d개 · 중복 %d · 범위 %d–%d", length(cd), sum(duplicated(cd)), min(cd), max(cd)))

# ─── ⑧ 돌연변이 통제 — 재시도 제거 사본은 ② 에서 잡혀야 한다 ──────────────────
src_txt <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
anchor <- "    tried <- c(tried, p)"
n_hit <- sum(src_txt == anchor)
mut <- src_txt; mut[mut == anchor] <- "    stop(cl)   # MUTANT: 재시도 없음"
MF <- tempfile(fileext = ".R"); writeLines(mut, MF, useBytes = TRUE)
EM <- new.env(parent = globalenv()); sys.source(MF, envir = EM)
hold <- tryCatch(serverSocket(P1), error = function(e) NULL)
em <- tryCatch(EM$qv_psock_cluster(1L, ports = c(P1, P2)), error = function(e) e)
if (!inherits(em, "error")) parallel::stopCluster(em)
if (!is.null(hold)) close(hold)
chk("mutant_no_retry_caught", n_hit == 1L && inherits(em, "error"),
    sprintf("치환 %d곳 · 돌연변이 = %s", n_hit, if (inherits(em, "error")) "막힌 포트에서 멈춤(검사가 잡는다)" else "통과(검사 사망)"))

# ─── ⑨ 정적 — 운영 R 코드 직접 호출 0 ─────────────────────────────────────────
rf <- list.files(file.path(ROOT, c("02_Infrastructure", "04_Research/programs")), pattern = "\\.[Rr]$", recursive = TRUE, full.names = TRUE)
rf <- rf[!grepl("/_archive|/99_Archive/|qv_psock\\.R$", rf)]
hits <- character(0)
for (f in rf) {
  L <- tryCatch(readLines(f, encoding = "UTF-8", warn = FALSE), error = function(e) character(0))
  i <- grep("(makePSOCKcluster|makeCluster)\\s*\\(", L, perl = TRUE)
  i <- i[!grepl("^\\s*#", L[i]) & !grepl("qv_psock_cluster", L[i])]
  if (length(i)) hits <- c(hits, sprintf("%s:%s", sub(paste0("^", ROOT, "/"), "", f), paste(i, collapse = ",")))
}
chk("static_no_direct_cluster_calls", length(hits) == 0L,
    if (length(hits)) paste("직접 호출:", paste(hits, collapse = " · ")) else sprintf("%d .R 스캔 · 0건", length(rf)))

cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "qv_psock", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
