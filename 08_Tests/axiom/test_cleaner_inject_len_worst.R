#!/usr/bin/env Rscript
#==============================================================================
# test_cleaner_inject_len_worst.R — 주간 스윕 HOLD 게이트 '주입 길이 > 1900' 의 판정 입력 안정화 (2026-09-23)
#
# 근거: Axiom 동결 워크플로 적대검증 — 게이트가 .cache/axiom_inject_last.json(마지막 Agent 스폰 1건)을 읽어
#   마지막 스폰 에이전트 종류(훅 헤더 기본/forge/judge/book × 강화 라운드)에 따라 len 이 흔들려 문턱 1,900 을
#   스폰 순서가 넘나들었다. 열화 기록(positive_context 부재 · len 1,441 · 마커 0/3)이 마지막이면 '통과'로 오판.
# 수리(문턱 불변): weekly_cleaner_sweep.R::.inj_len_worst() — 운영 훅을 샌드박스에서 헤더 변형 전부 × {일반, 강화}로
#   렌더해 최댓값을 판정 입력으로 쓴다.
#
# 축 (양성 대조 + 위반 주입/돌연변이)
#   W1 형태: 파스 트리에서 꺼낸 함수가 basis=worst_header_render(n=8) · 변형 이름(forge·judge·book·기본 × 강화)
#   W2 정확성: 결과 = 독립 렌더(테스트가 직접 훅을 돌린 8변형)의 최댓값
#   W3 스폰 순서 무관: root 의 axiom_inject_last.json 을 열화(1441)/고값(1999) 기록으로 바꿔도 결과 동일
#        양성 대조: 구 입력(마지막 기록 len)은 두 경우에 1441 vs 1999 로 갈린다 — 흔들림이 실재함을 증명
#   W4 격리: root 의 axiom_inject_last.json 바이트 불변(HARD_10 입력 무접촉) · CLAUDE_PROJECT_DIR 원복
#   W5 실측성: root 에서 positive_context.json 을 빼면 결과가 줄어든다(상수를 내는 계기가 아님)
#   M-W1 돌연변이: 헤더 재도출을 기본 1종으로 축소한 사본 → W2 불일치(검출)
#   M-W2 돌연변이: CLAUDE_PROJECT_DIR 원복 on.exit 제거 사본 → W4 원복 단정 실패(검출)
#
# 격리: 쓰기는 tempdir() 샌드박스에만. 운영 트리는 읽기만 한다. 텔레그램·원장·로그 쓰기 없음.
# 실행: Rscript 08_Tests/axiom/test_cleaner_inject_len_worst.R
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a)) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, if (nzchar(d)) paste0(" :: ", d) else "", "\n") }
chk <- function(m, cond, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)

ROOT <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
SWEEP <- file.path(ROOT, "02_Infrastructure/ops/weekly_cleaner_sweep.R")
HOOK <- file.path(ROOT, "02_Infrastructure/hooks/axiom_context_inject.sh")
SB0 <- gsub("\\", "/", tempfile("injworst_"), fixed = TRUE)
dir.create(SB0, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB0, recursive = TRUE, force = TRUE), onexit = TRUE))
.cpd0 <- Sys.getenv("CLAUDE_PROJECT_DIR", NA_character_)
.cpd_restore <- function() if (is.na(.cpd0)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = .cpd0)

# 파스 트리에서 `.inj_len_worst <- function(...)` 대입식을 꺼내 격리 env 에 적재(스윕 전체를 돌리지 않는다)
.extract_fn <- function(src_lines, name = ".inj_len_worst") {
  ex <- parse(text = src_lines, keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(name)), as.list(ex))
  if (length(hit) != 1L) stop(sprintf("%s 대입식 %d개", name, length(hit)))
  env <- new.env(parent = globalenv())
  env$`%||%` <- `%||%`
  eval(hit[[1]], env)
  get(name, envir = env)
}
sweep_src <- readLines(SWEEP, warn = FALSE, encoding = "UTF-8")
fn <- tryCatch(.extract_fn(sweep_src), error = function(e) e)
if (inherits(fn, "error")) { ng("W0 .inj_len_worst 추출", conditionMessage(fn)); quit(save = "no", status = 1L) }
ok("W0 weekly_cleaner_sweep.R 에서 .inj_len_worst 대입식 1개 추출")

# 운영 입력의 읽기 전용 사본으로 가짜 root 를 만든다(함수는 root 에서 읽고, 자기 내부 샌드박스에만 쓴다)
.mk_root <- function(tag, with_pc = TRUE) {
  r <- file.path(SB0, tag)
  dir.create(file.path(r, "qepm/memory/axioms"), recursive = TRUE)
  dir.create(file.path(r, ".cache")); dir.create(file.path(r, "02_Infrastructure/hooks"), recursive = TRUE)
  file.copy(file.path(ROOT, "qepm/memory/axioms/active"), file.path(r, "qepm/memory/axioms"), recursive = TRUE)
  file.copy(file.path(ROOT, "qepm/memory/axioms/tombstones.json"), file.path(r, "qepm/memory/axioms/tombstones.json"))
  if (with_pc) file.copy(file.path(ROOT, ".cache/positive_context.json"), file.path(r, ".cache/positive_context.json"))
  file.copy(file.path(ROOT, "CLAUDE.md"), file.path(r, "CLAUDE.md"))
  file.copy(HOOK, file.path(r, "02_Infrastructure/hooks/axiom_context_inject.sh"))
  file.copy(file.path(ROOT, "02_Infrastructure/hooks/_shared_parse.sh"), file.path(r, "02_Infrastructure/hooks/_shared_parse.sh"))
  r
}
.fake_last <- function(r, len) writeLines(sprintf('{"at":"2026-09-23T19:25:31+09:00","len":%d,"agent":"alpha-research","pc_status":"%s"}',
                                                 len, if (len < 1500) "missing" else "ok"), file.path(r, ".cache/axiom_inject_last.json"))
.old_input <- function(r) tryCatch(as.integer(fromJSON(file.path(r, ".cache/axiom_inject_last.json"))$len), error = function(e) NA_integer_)

# 독립 렌더 — 테스트가 직접 훅을 돌린다(함수 구현과 독립). 기대 헤더 4종 × {일반, 강화}.
.indep_max <- function(r) {
  sb <- file.path(SB0, paste0("indep_", basename(r)))
  dir.create(file.path(sb, ".cache"), recursive = TRUE); dir.create(file.path(sb, "qepm/memory/axioms"), recursive = TRUE)
  file.copy(file.path(r, "qepm/memory/axioms/active"), file.path(sb, "qepm/memory/axioms"), recursive = TRUE)
  for (f in c("qepm/memory/axioms/tombstones.json", ".cache/positive_context.json", "CLAUDE.md"))
    if (file.exists(file.path(r, f))) file.copy(file.path(r, f), file.path(sb, f))
  Sys.setenv(CLAUDE_PROJECT_DIR = sb); on.exit(.cpd_restore(), add = TRUE)
  lens <- c()
  for (a in c("forge", "judge", "book", "alpha-research")) for (rt in c("", "WT-R20260923_001 강화")) {
    il <- file.path(sb, ".cache/axiom_inject_last.json"); unlink(il)
    inp <- sprintf('{"tool_name":"Agent","tool_input":{"subagent_type":"%s","prompt":"%s"}}', a, rt)
    invisible(suppressWarnings(system2("bash", shQuote(HOOK), stdout = TRUE, stderr = FALSE, input = inp)))
    lens[paste(a, nzchar(rt))] <- tryCatch(as.integer(fromJSON(il)$len), error = function(e) NA_integer_)
  }
  lens
}

cat("\n[W1·W2] 형태 · 독립 렌더 최댓값과 일치\n")
r1 <- .mk_root("r1")
.fake_last(r1, 1441L)
md5_before <- unname(tools::md5sum(file.path(r1, ".cache/axiom_inject_last.json")))
w_a <- fn(r1)
ind <- .indep_max(r1)
chk("W1 basis = worst_header_render(n=8)", identical(w_a$basis, "worst_header_render(n=8)"), w_a$basis)
chk("W1 변형 이름 = forge·judge·book·기본 × {일반, +reinforce}",
    all(c("forge", "judge", "book", "zz-default-header-probe", "judge+reinforce", "zz-default-header-probe+reinforce") %in% names(w_a$by)),
    paste(names(w_a$by), collapse = ","))
chk("W2 결과 = 독립 렌더 8변형 최댓값", !anyNA(ind) && identical(w_a$len, max(ind)),
    sprintf("fn=%s indep=%s", w_a$len, paste(ind, collapse = "/")))
chk("W2 변형 간 len 이 실제로 다르다(흔들림 실재 — 입력 안정화가 필요한 이유)", length(unique(ind)) >= 2L, paste(ind, collapse = "/"))

cat("\n[W3] 스폰 순서 무관 — 마지막 기록이 열화(1441)든 고값(1999)이든 결과 동일\n")
.fake_last(r1, 1999L)
w_b <- fn(r1)
chk("W3 결과 불변(1441 기록 vs 1999 기록)", identical(w_a$len, w_b$len), sprintf("%s vs %s", w_a$len, w_b$len))
.fake_last(r1, 1441L); o1 <- .old_input(r1); .fake_last(r1, 1999L); o2 <- .old_input(r1)
chk("W3 양성 대조: 구 입력(마지막 기록)은 1441 vs 1999 로 갈려 문턱 1900 판정이 뒤집힌다",
    identical(o1, 1441L) && identical(o2, 1999L) && (o1 > 1900L) != (o2 > 1900L))

cat("\n[W4] 격리 — 운영 계측 파일·환경변수\n")
.fake_last(r1, 1441L)
md5_b2 <- unname(tools::md5sum(file.path(r1, ".cache/axiom_inject_last.json")))
Sys.setenv(CLAUDE_PROJECT_DIR = "SENTINEL_CPD")
invisible(fn(r1))
cpd_after <- Sys.getenv("CLAUDE_PROJECT_DIR")
.cpd_restore()
chk("W4 root/.cache/axiom_inject_last.json 바이트 불변(HARD_10 입력 무접촉)",
    identical(md5_b2, unname(tools::md5sum(file.path(r1, ".cache/axiom_inject_last.json")))) && identical(md5_before, md5_b2))
chk("W4 CLAUDE_PROJECT_DIR 원복(스윕의 이후 promote 스폰이 샌드박스를 보지 않는다)", identical(cpd_after, "SENTINEL_CPD"), cpd_after)
chk("W4 root 에 렌더 캐시를 남기지 않는다(axiom_inject_body.md 부재)", !file.exists(file.path(r1, ".cache/axiom_inject_body.md")))

cat("\n[W5] 실측성 — positive_context 를 빼면 결과가 준다\n")
r2 <- .mk_root("r2_nopc", with_pc = FALSE)
w_c <- fn(r2)
chk("W5 positive_context 부재 root → 최악값 감소(변동부 소실을 그대로 잰다)", is.finite(w_c$len) && w_c$len < w_a$len,
    sprintf("%s vs %s", w_c$len, w_a$len))
chk("W5 열화 렌더는 pc_status=missing 으로 기록된다(basis 뒤 by 에 남음)",
    all(vapply(w_c$by, function(z) identical(z$pc_status, "missing"), logical(1))))

cat("\n[M] 돌연변이\n")
mpat <- '  agents <- c(unique(gsub("^\\\\s*\\\\*|\\\\*\\\\)$", "", m, perl = TRUE)), "zz-default-header-probe")  # 마지막 = 기본 헤더'
if (sum(sweep_src == mpat) != 1L) ng("M-W1 돌연변이 대상 줄 수 ≠ 1 — 계기 재설계 필요", as.character(sum(sweep_src == mpat))) else {
  fm <- .extract_fn(ifelse(sweep_src == mpat, '  agents <- "zz-default-header-probe"', sweep_src))
  wm <- fm(r1)
  chk("M-W1 헤더 재도출 축소 사본 → 독립 최댓값과 불일치(검출 — W2 가 잡는다)", !identical(wm$len, max(ind)),
      sprintf("mut=%s indep=%s", wm$len, max(ind)))
}
rpat <- "  on.exit(if (is.na(old_cpd)) Sys.unsetenv(\"CLAUDE_PROJECT_DIR\") else Sys.setenv(CLAUDE_PROJECT_DIR = old_cpd),"
ri <- which(sweep_src == rpat)
if (length(ri) != 1L) ng("M-W2 돌연변이 대상 줄 수 ≠ 1", as.character(length(ri))) else {
  fm2 <- .extract_fn(sweep_src[-c(ri, ri + 1L)])
  Sys.setenv(CLAUDE_PROJECT_DIR = "SENTINEL_CPD")
  invisible(fm2(r1))
  cpd_m <- Sys.getenv("CLAUDE_PROJECT_DIR")
  .cpd_restore()
  chk("M-W2 원복 제거 사본 → CLAUDE_PROJECT_DIR 가 샌드박스로 남는다(검출 — W4 가 잡는다)", !identical(cpd_m, "SENTINEL_CPD"), cpd_m)
}

cat("\n[info] 운영 입력 기준 현재 판정 입력(읽기 전용 사본)\n")
cat(sprintf("  최악값 %s (%s) · 변형별 %s\n", w_a$len, w_a$basis,
            paste(sprintf("%s=%d", names(w_a$by), vapply(w_a$by, function(z) z$len, integer(1))), collapse = " ")))

.cpd_restore()
cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"cleaner_inject_len_worst","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
