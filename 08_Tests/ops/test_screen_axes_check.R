#!/usr/bin/env Rscript
# test_screen_axes_check.R — STEP 1-b 2축 검사기의 위반 주입 테스트 (2026-08-08).
#
# 왜 있나: 라우터 프롬프트에 "optimizer/risk 항목에 shrinkage_builtin·statistic_order·
#   screen_priority 를 실어라"고 적었다. **지시만 있고 검사가 없으면 조용히 안 지켜진다** —
#   이번 세션에서 반복 확인된 부류(screen_route 소비자 0 · AST 사이드카 배선 · dispatch_done=isfile).
#   그래서 소비단에 검사를 넣었고, 이 파일은 **그 검사가 진짜로 잡는지**를 확인한다.
#
# ★설계 축:
#   (A) clean 선확인 — 완전한 항목이 100% 로 통과해야 위반 검거가 의미를 갖는다
#   (B) 결측 검거 — 필드 누락
#   (C) ★enum밖 검거 — **존재 검사로 유효성 검사를 대체하지 않는가**.
#       필드가 있어도 값이 enum 밖이면 소비단이 우선순위를 못 매기므로 없는 것과 같다.
#       이 축이 이 검사기의 존재 이유다(존재만 세는 검사기는 여기서 통과해버린다).
#   (D) 빈 큐 = NULL (0건을 위반으로 세지 않음)
#   (E) 커버리지 산술 — 부분 결손이 비율로 정확히 잡히는가
#   돌연변이: 존재만 보는 구판 검사를 동반 실행 — (C)를 **놓쳐야** 이 검사가 유효하다.
#
# ★검사 대상 = 사본이 아니라 원본 .R 의 마커 구간 추출.
#   >>> SCREEN_AXES_CHECK … <<< SCREEN_AXES_CHECK

.root <- local({
  .marker <- file.path("02_Infrastructure", "ops", "paper_research_dispatch.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
})
TARGET <- file.path(.root, "02_Infrastructure", "ops", "paper_research_dispatch.R")

PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

extract <- function(path) {
  if (!file.exists(path)) { cat("FATAL: 대상 부재:", path, "\n"); quit(status = 2) }
  ln <- readLines(path, warn = FALSE)
  b <- grep(">>> SCREEN_AXES_CHECK", ln, fixed = TRUE)
  e <- grep("<<< SCREEN_AXES_CHECK", ln, fixed = TRUE)
  if (length(b) != 1L || length(e) != 1L || e <= b) {
    cat("FATAL: 마커를 찾지 못했다 — 마커가 바뀌었으면 이 추출기부터 고칠 것. 조용히 0건 검사 방지.\n")
    quit(status = 2)
  }
  blk <- paste(ln[(b + 1):(e - 1)], collapse = "\n")
  for (sym in c("check_screen_axes", "SCREEN_AX_ENUM")) {
    if (!grepl(sym, blk, fixed = TRUE)) { cat(sprintf("FATAL: 추출 구간에 `%s` 부재.\n", sym)); quit(status = 2) }
  }
  blk
}
BLK <- extract(TARGET)
env <- new.env(parent = globalenv())
assign("%||%", function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b, envir = env)
eval(parse(text = BLK), envir = env)
chk <- get("check_screen_axes", envir = env)

# 돌연변이: 존재만 보고 enum 은 안 보는 구판
legacy <- function(items, route) {
  n <- length(items); if (n == 0L) return(NULL)
  miss <- character(0)
  for (i in seq_len(n)) for (f in c("shrinkage_builtin", "statistic_order", "screen_priority")) {
    v <- items[[i]][[f]]
    if (is.null(v) || !nzchar(as.character(v)[1])) miss <- c(miss, f)
  }
  list(n_items = n, coverage = 1 - length(miss) / (n * 3), missing = miss, invalid_enum = character(0))
}

good <- function(id) list(arxiv_id = id, title = paste0("t-", id),
                          shrinkage_builtin = "yes", statistic_order = "<=2nd", screen_priority = "⭐⭐")
run <- function(f, items) { o <- NULL; utils::capture.output(o <- f(items, "optimizer")); o }

cat("== STEP 1-b 2축 검사기 위반 주입 테스트 ==\n\n")

cat("[A] clean 선확인\n")
r <- run(chk, list(good("a"), good("b")))
if (!is.null(r) && identical(r$coverage, 1) && length(r$missing) == 0 && length(r$invalid_enum) == 0) {
  ok("완전한 2건 → 커버리지 100%, 결측 0, enum밖 0")
} else{
  bad("clean", sprintf("coverage=%s miss=%d bad=%d", r$coverage, length(r$missing), length(r$invalid_enum)))
}

cat("\n[B] 결측 검거\n")
m1 <- good("c"); m1$statistic_order <- NULL
r <- run(chk, list(good("a"), m1))
if (length(r$missing) == 1L && grepl("statistic_order", r$missing[1])) {
  ok("필드 1개 누락 → 정확히 1건 결측 검거")
} else{
  bad("결측", sprintf("miss=%s", paste(r$missing, collapse = ",")))
}
m2 <- list(arxiv_id = "d", title = "t-d")   # 3필드 전무
r <- run(chk, list(m2))
if (length(r$missing) == 3L) ok("3필드 전무 → 3건 결측") else bad("전무", sprintf("miss=%d", length(r$missing)))

cat("\n[C] ★enum밖 검거 — 존재 검사로 유효성 검사를 대체하지 않는가\n")
e1 <- good("e"); e1$shrinkage_builtin <- "partial"      # enum 밖
e2 <- good("f"); e2$statistic_order   <- "2nd"          # enum 밖 (정본은 "<=2nd")
r <- run(chk, list(e1, e2))
if (length(r$invalid_enum) == 2L && length(r$missing) == 0L) {
  ok("enum밖 2건 검거, 결측 0 (필드는 존재하므로)")
} else{
  bad("enum", sprintf("bad=%d miss=%d", length(r$invalid_enum), length(r$missing)))
}

cat("\n[D] 빈 큐\n")
if (is.null(run(chk, list()))) ok("0건 → NULL (위반으로 세지 않음)") else bad("빈 큐", "NULL 아님")

cat("\n[E] 커버리지 산술\n")
r <- run(chk, list(good("a"), m2))          # 2항목 × 3필드 = 6, 결손 3 → 0.5
if (isTRUE(all.equal(r$coverage, 0.5))) {
  ok("2항목 중 1건 전무 → 커버리지 0.500")
} else{
  bad("커버리지", sprintf("coverage=%s (기대 0.5)", r$coverage))
}

cat("\n[F] 돌연변이 — 존재만 보는 구판은 [C]를 놓쳐야 한다\n")
rl <- run(legacy, list(e1, e2))
if (length(rl$invalid_enum) == 0L && isTRUE(all.equal(rl$coverage, 1))) {
  ok("구판: enum밖 2건을 100% 통과시킴 = 이 검사기의 판별력 실증")
} else{
  bad("돌연변이", "구판이 enum밖을 잡았다 — 픽스처가 두 판을 구별 못 함")
}
rl2 <- run(legacy, list(good("a"), m2))
if (isTRUE(all.equal(rl2$coverage, 0.5))) {
  ok("구판도 결측은 잡음 (차이가 enum 축에만 있음을 확인)")
} else{
  bad("돌연변이 대조", "구판이 결측도 못 잡음 — 비교가 성립 안 함")
}

cat(sprintf("\nFINAL: passed=%d failed=%d\n", PASS, FAIL))
## ★러너 집계용 요약 JSON — 이 줄이 없으면 run_all_hooks.sh 가 이 suite 를
##   UNREPORTED(=1 fail)로 계상하고 **통과 건수는 통째로 사라진다**.
##   위 FINAL 줄은 사람용이라 유지한다(둘 다 남긴다). 2026-08-09 추가.
cat(sprintf("{\"test\":\"screen_axes_check\",\"pass\":%d,\"fail\":%d,\"total\":%d}\n",
            PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0) 1 else 0)
