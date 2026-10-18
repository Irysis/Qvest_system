## =============================================================================
## diff_check_mutation_test.R — template_diff_check.R 양방향 검사(양성 대조 없는 계기는 방어선으로 세지 않는다)
##   사본 디렉터리 tests/_out/diffcheck/<사례>/ 에 템플릿 · 생성 엔진 7개를 복사하고 사례마다 한 곳을 소스 텍스트 치환(치환 성사 단정 ·
##   deparse 금지)으로 바꾼 뒤 그 사본의 매니페스트를 새로 써서(차분 대조만 시험되게) 검사기가 기대한 사유로 실패하는지 단정한다.
##   바꾸지 않은 사본은 통과해야 한다. 매니페스트 사례는 매니페스트만 바꾼다.
## 실행: Rscript tests/diff_check_mutation_test.R      (종료 코드 0 = 전 사례 기대대로)
## =============================================================================
suppressPackageStartupMessages(library(jsonlite))
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))) if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))) { ROOT <- gsub("\\\\", "/", p); break }
REL_DT <- "04_Research/strategies/DT_2002_06975"
DT <- file.path(ROOT, REL_DT)
SRC_REL <- "04_Research/strategies/RP_AUTO_2002_06975/engine.R"
RULES <- c("Q50", "V1", "V2", "N1", "N2", "S1", "S2")
source(file.path(DT, "template_diff_check.R"))
OUT_REL <- file.path(REL_DT, "tests", "_out", "diffcheck")
unlink(file.path(ROOT, OUT_REL), recursive = TRUE)
md5f <- function(p) unname(as.character(tools::md5sum(p)))
rd <- function(p) { r <- readBin(p, "raw", file.info(p)$size); x <- rawToChar(r); Encoding(x) <- "UTF-8"; x }
wr <- function(x, p) writeBin(charToRaw(enc2utf8(x)), p)
subst1 <- function(p, old, new) {                         # 소스 텍스트 치환 — 정확히 1회 · 성사 단정
  x <- rd(p); n <- lengths(regmatches(x, gregexpr(old, x, fixed = TRUE)))
  if (n != 1L) stop(sprintf("치환 대상 %d회(1회여야 한다): %s @ %s", n, old, basename(p)))
  y <- sub(old, new, x, fixed = TRUE)
  if (identical(x, y) || !grepl(new, y, fixed = TRUE)) stop("치환 불성사: ", old)
  wr(y, p); invisible(TRUE)
}
mk_copy <- function(case) {
  crel <- file.path(OUT_REL, case); cdir <- file.path(ROOT, crel)
  dir.create(file.path(cdir, "rx0s"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(DT, c("engine_template.R", sprintf("engine_%s.R", RULES))), cdir, overwrite = TRUE)
  file.copy(file.path(DT, "rx0s", "engine_RX0S.R"), file.path(cdir, "rx0s"), overwrite = TRUE)
  list(rel = crel, dir = cdir)
}
write_manifest <- function(cp, src_rel = SRC_REL) {
  eng <- lapply(RULES, function(r) { p <- file.path(cp$rel, sprintf("engine_%s.R", r)); if (!file.exists(file.path(ROOT, p))) return(NULL)
    list(rule = r, path = p, md5 = md5f(file.path(ROOT, p))) })
  eng <- Filter(Negate(is.null), eng)
  man <- list(schema = "dt_engines_manifest_v1", generated_at = "test",
              template = list(path = file.path(cp$rel, "engine_template.R"), md5 = md5f(file.path(cp$dir, "engine_template.R"))),
              generator = list(path = file.path(REL_DT, "make_engines.R"), md5 = md5f(file.path(DT, "make_engines.R"))),
              source_engine = list(path = src_rel, md5 = md5f(file.path(ROOT, src_rel))),
              rx0s = if (file.exists(file.path(cp$dir, "rx0s", "engine_RX0S.R")))
                       list(path = file.path(cp$rel, "rx0s", "engine_RX0S.R"), md5 = md5f(file.path(cp$dir, "rx0s", "engine_RX0S.R"))) else NULL,
              engines = eng)
  writeLines(toJSON(man, auto_unbox = TRUE, pretty = TRUE), file.path(cp$dir, "engines_manifest.json"))
}
run_case <- function(case, mutate = NULL, expect = NULL, src_rel = SRC_REL, after_manifest = NULL) {
  cp <- mk_copy(case)
  if (!is.null(mutate)) mutate(cp)
  write_manifest(cp, src_rel)
  if (!is.null(after_manifest)) after_manifest(cp)
  r <- dt_template_diff_check(ROOT, dt_dir = cp$dir, source_engine = file.path(ROOT, src_rel))
  hit <- if (is.null(expect)) isTRUE(r$ok) else (!isTRUE(r$ok) && any(grepl(expect, r$errors, fixed = TRUE)))
  cat(sprintf("[diffcheck-test] %-26s 기대 %-34s → %s%s\n", case, if (is.null(expect)) "통과" else paste0("실패('", expect, "')"),
              if (hit) "OK" else "어긋남", if (!isTRUE(r$ok)) paste0(" · 사유: ", substr(paste(r$errors, collapse = " | "), 1L, 220L)) else ""))
  list(case = case, expect = expect %||% "pass", ok = hit, checker_ok = isTRUE(r$ok), errors = r$errors)
}

res <- list()
res[[1]] <- run_case("clean_copy")
res[[2]] <- run_case("out_of_zone_constant", function(cp) {                 # 보호 상수(표적 수평) 1글자 — 구역 밖
  subst1(file.path(cp$dir, "engine_template.R"), ".HORIZON  <- 5L", ".HORIZON  <- 6L")
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), ".HORIZON  <- 5L", ".HORIZON  <- 6L") }, "구역 밖 차분")
res[[3]] <- run_case("out_of_zone_comment", function(cp) {                  # 원본 머리말 주석 1글자 — 구역 밖
  subst1(file.path(cp$dir, "engine_template.R"), "# Masaya Abe · Kei Nakagawa", "# Masaya Abe · Kei Nakagawa.")
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), "# Masaya Abe · Kei Nakagawa", "# Masaya Abe · Kei Nakagawa.") }, "구역 밖 차분")
res[[4]] <- run_case("out_of_zone_python", function(cp) {                   # 파이썬 학습 수치(epoch) — 구역 밖
  subst1(file.path(cp$dir, "engine_template.R"), "EPOCHS = 20  ", "EPOCHS = 21  ")
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), "EPOCHS = 20  ", "EPOCHS = 21  ") }, "구역 밖 차분")
res[[5]] <- run_case("wrong_orig_declaration", function(cp) {               # 구역 선언 범위 거짓
  subst1(file.path(cp$dir, "engine_template.R"), "## >>> DT_ZONE py_head orig=470-470", "## >>> DT_ZONE py_head orig=471-471")
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), "## >>> DT_ZONE py_head orig=470-470", "## >>> DT_ZONE py_head orig=471-471") }, "구역 밖 차분")
res[[6]] <- run_case("zone_replaces_protected", function(cp) {              # 선언은 맞게 · 보호 행(옵티마이저)을 구역으로 대체
  old <- "    opt = torch.optim.Adam(model.parameters(), lr=LR)\n## >>> DT_ZONE py_loss_def orig=492-492\n"
  new <- "## >>> DT_ZONE py_loss_def orig=491-492\n    opt = torch.optim.Adam(model.parameters(), lr=LR * 10)\n"
  subst1(file.path(cp$dir, "engine_template.R"), old, new)
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), old, new) }, "보호 범위")
res[[7]] <- run_case("unclosed_zone", function(cp) {                        # 끝 표지 삭제
  subst1(file.path(cp$dir, "engine_template.R"), "## <<< DT_ZONE py_forward\n", "")
  for (r in RULES) subst1(file.path(cp$dir, sprintf("engine_%s.R", r)), "## <<< DT_ZONE py_forward\n", "") }, "닫히기 전에")
res[[8]] <- run_case("engine_extra_diff", function(cp)                      # 생성 엔진 하나에 규칙 줄 밖 차이
  subst1(file.path(cp$dir, "engine_V1.R"), ".DT_VETO_SHARE <- 0.2 ", ".DT_VETO_SHARE <- 0.3 "), "engine_V1.R: 템플릿과 다른 줄 2개")
res[[9]] <- run_case("engine_wrong_rule", function(cp)                      # 파일 이름과 규칙 줄 불일치
  subst1(file.path(cp$dir, "engine_V1.R"), '.DT_RULE <- "V1"', '.DT_RULE <- "V2"'), "engine_V1.R")
res[[10]] <- run_case("engine_missing", function(cp) unlink(file.path(cp$dir, "engine_S2.R")), "생성 엔진 없음: engine_S2.R")
res[[11]] <- run_case("engine_unexpected_file", function(cp) file.copy(file.path(cp$dir, "engine_Q50.R"), file.path(cp$dir, "engine_X.R")), "예정에 없는 엔진 파일")
res[[length(res) + 1L]] <- run_case("rx0s_extra_diff", function(cp)                         # RX0S 에 시드 · 디렉터리 · 꼬리표 밖 차이
  subst1(file.path(cp$dir, "rx0s", "engine_RX0S.R"), ".HORIZON  <- 5L", ".HORIZON  <- 6L"), "RX0S: 원본과 다른 줄")
res[[length(res) + 1L]] <- run_case("rx0s_wrong_seed", function(cp)                         # 시드 값이 정의와 다름
  subst1(file.path(cp$dir, "rx0s", "engine_RX0S.R"), ".SEED_BASE <- 20261018L", ".SEED_BASE <- 20261019L"), "부분 문자열만 치환")
res[[length(res) + 1L]] <- run_case("rx0s_original_workdir", function(cp)                   # 작업 디렉터리를 원본으로 되돌림(원본 캐시에 쓰게 됨)
  subst1(file.path(cp$dir, "rx0s", "engine_RX0S.R"), '"DT_2002_06975", "rx0s", "_work")', '"RP_AUTO_2002_06975", "_work")'), "RX0S: 원본과 다른 줄")
res[[length(res) + 1L]] <- run_case("rx0s_missing", function(cp) unlink(file.path(cp$dir, "rx0s", "engine_RX0S.R")), "RX0S 엔진 없음")
res[[length(res) + 1L]] <- run_case("manifest_md5", NULL, "매니페스트 md5 불일치", after_manifest = function(cp) {
  mf <- file.path(cp$dir, "engines_manifest.json"); m <- fromJSON(mf, simplifyVector = FALSE)
  m$engines[[3]]$md5 <- paste(rep("0", 32), collapse = ""); writeLines(toJSON(m, auto_unbox = TRUE, pretty = TRUE), mf) })
## 원본이 바뀌면(사본 원본에 1글자) — DT_SOURCE_MD5 불일치
src_copy_rel <- file.path(OUT_REL, "engine_source_modified.R")
dir.create(file.path(ROOT, OUT_REL), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(ROOT, SRC_REL), file.path(ROOT, src_copy_rel), overwrite = TRUE))
subst1(file.path(ROOT, src_copy_rel), "# Masaya Abe · Kei Nakagawa", "# Masaya Abe · Kei Nakagawa!")
res[[length(res) + 1L]] <- run_case("source_engine_changed", NULL, "DT_SOURCE_MD5", src_rel = src_copy_rel)

ok <- all(vapply(res, function(z) isTRUE(z$ok), logical(1)))
writeLines(toJSON(list(ok = ok, n_cases = length(res), cases = res, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")), auto_unbox = TRUE, pretty = TRUE),
           file.path(ROOT, OUT_REL, "..", "diff_check_mutation_results.json"))
unlink(file.path(ROOT, OUT_REL), recursive = TRUE)                                         # 사례별 사본(엔진 9개 × 사례) 삭제 — 결과 JSON 만 남긴다
cat(sprintf("[diffcheck-test] %s — 사례 %d 중 기대대로 %d (통과 기대 1 · 실패 기대 %d)\n", if (ok) "OK" else "FAIL", length(res),
            sum(vapply(res, function(z) isTRUE(z$ok), logical(1))), length(res) - 1L))
quit(status = if (ok) 0L else 1L)
