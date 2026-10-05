#==============================================================================
# test_overlay_probe_allowlist.R — overlay_probe ③d 허용 목록(allowlist) 양방향 검사 (R3R 2026-09-25 · P0-09 정적 probe 경화)
#
# 왜: ③c(호출자 스코프 스캔)는 막을 통로를 정규식으로 열거했다. R3 검증이 열거 밖 통로를 실증했다 —
#     eval.parent · rlang::caller_env · do.call("sys.frame") · 별칭 f <- sys.frames · 백틱 · 계산된 FUN · get/assign(envir =) ·
#     문자열 안 '#'(구 주석 걷기가 같은 줄 뒤 코드를 지웠다). 방향을 뒤집었다: 정본 arm 이 쓰는 이름 전수가 허용 집합이고 밖은 전부 거부.
#     1차 방어는 엔진 런타임 마스크(rf_cell_engine.R H[t, fwd := NA]) — 이 층은 등재 관문의 보조층이다.
#
# 재는 것 (양성 대조 · 위반 주입 · 수리 전 red · 돌연변이):
#   A 레지스트리 적재 · 정본 arm 전수 ③d 통과 · 정본 공통 arm 전수 전체 probe 통과 · pg2 는 sha 고정 허가로만 통과 · 빌더 재현
#   B 합성 arm(허용 밖 호출 1개 — 탐지기 검사용 최소 형태 · 미래 데이터를 실제로 읽지 않는다) → ③d 거부(규칙별) · 전체 probe 거부
#     B-red 수리 전 probe(QVEST_R3R_BASE_PROBE 또는 git HEAD 블롭 고정)는 같은 arm 을 통과시킨다(결함 실증)
#   C 주석 걷기 — 문자열 안 '#' 뒤 코드가 남는다(구판은 지웠다) · 진짜 주석은 걷힌다
#   D 레지스트리 fail-closed — 부재·파손·스키마·능력 계열 오염·참조 이름공간 부재·허가 sha 불일치
#   E 돌연변이 — ③d 무력화 / R5·R2·do.call 규칙 제거 / sha 대조 우회 / 구 주석 걷기 → 각각 해당 위반이 통과(검사가 하중을 진다)
#   F LOO(정보) — 공통 arm 하나를 빼고 만든 목록으로 그 arm 을 잰 통과율(새 arm 이 목록에 들어맞는 정도의 추정 · 판정 아님)
# 부작용: overlay_arms/ 에 zz_al_* 픽스처를 잠시 쓰고 지운다(함수 안 on.exit) · 나머지는 tempdir.
# 실행: QM_ROOT=<루트> R_ENVIRON_USER=<빈 파일> Rscript --no-environ 08_Tests/reinforcement/test_overlay_probe_allowlist.R
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT  <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
PROBE <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_probe.R")
REG   <- file.path(ROOT, "06_Registry/overlay_probe_allowlist.json")
ADIR  <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms")
writeLines(paste("ROOT =", ROOT))
PASS <- 0L; FAIL <- 0L; SKIP <- 0L
ok   <- function(m) { PASS <<- PASS + 1L; writeLines(paste("  OK   ", m)) }
ng   <- function(m, d = "") { FAIL <<- FAIL + 1L; writeLines(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else "")) }
skip <- function(m) { SKIP <<- SKIP + 1L; writeLines(paste("  SKIP ", m)) }
TD <- file.path(tempdir(), sprintf("r3r_al_%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
load_probe <- function(path) { e <- new.env(parent = globalenv()); suppressMessages(capture.output(sys.source(path, envir = e, keep.source = FALSE))); e }
pN <- load_probe(PROBE)
failed_at <- function(r) { z <- r$checks[r$checks$status == "FAIL", ]; if (nrow(z)) z$check[1] else NA_character_ }
row_of <- function(r, k) { z <- r$checks[r$checks$check == k, ]; if (nrow(z)) z$status[1] else "-" }
canon <- function() { f <- list.files(ADIR, pattern = "^[A-Za-z].*[.]R$", full.names = TRUE); f[!grepl("^zz_", basename(f))] }
inject <- function(pe, kind, lines, root = ROOT) {
  p <- file.path(root, "02_Infrastructure/reinforcement/overlay_arms", paste0(kind, ".R"))
  writeLines(lines, p); on.exit(unlink(p), add = TRUE)
  r <- NULL; invisible(capture.output(r <- pe$overlay_probe_arm(kind, root))); r
}
# 정상 arm 몸통(변동성 스케일 — 정본·기존 검사의 음성 대조와 같은 형태). 위반 1줄을 앞에 끼운다.
arm_lines <- function(kind, bad) c(
  sprintf("overlay_expo_%s <- function(H, t, ctx) {", kind),
  paste0("  ", bad),
  "  h <- H$rv60[is.finite(H$rv60)]",
  "  if (length(h) < 24L) return(1)",
  "  v <- H$rv60[t]",
  "  if (!is.finite(v) || v <= 0) return(1)",
  "  max(0, min(1, stats::median(h) / v))",
  "}")

# ══ A. 레지스트리 · 양성 대조 ═══════════════════════════════════════════════════
writeLines("=== A. 레지스트리 · 양성 대조(정본 arm 전수) ===")
AL <- pN$overlay_probe_allowlist_params(ROOT)
if (isTRUE(AL$ok) && !isTRUE(AL$fallback)) ok(sprintf("A1 레지스트리 적재 — %s · 공통 calls %d · 개별 허가 %s", basename(AL$path),
                                                     length(AL$common$calls), paste(names(AL$grants), collapse = ","))) else
  ng("A1 레지스트리", AL$reason %||% "폴백")
J <- fromJSON(REG, simplifyVector = FALSE)
src_k <- vapply(J$source_arms, function(a) a$kind, character(1))
cf <- canon(); ck <- sub("[.]R$", "", basename(cf))
if (length(src_k) && setequal(src_k, ck)) ok(sprintf("A1b 레지스트리 출처 arm %d종 = overlay_arms 정본 %d종(집합 일치)", length(src_k), length(ck))) else
  ng("A1b 출처 arm 집합 불일치 — 정본이 바뀌었으면 레지스트리 재검토", sprintf("레지스트리만 %s · 디렉터리만 %s",
     paste(setdiff(src_k, ck), collapse = ","), paste(setdiff(ck, src_k), collapse = ",")))
res <- rbindlist(lapply(cf, function(f) { k <- sub("[.]R$", "", basename(f))
  r <- pN$overlay_probe_allowlist_scan(f, kind = k, al = AL); data.table(kind = k, ok = r$ok, grant = r$grant, why = r$reason %||% "") }))
if (nrow(res) && all(res$ok)) ok(sprintf("A2 정본 arm %d종 전부 ③d 통과 (개별 허가 적용 %d종: %s)", nrow(res), sum(grepl("개별 허가", res$grant) & !grepl("무효", res$grant)),
                                         paste(res$kind[grepl("개별 허가", res$grant)], collapse = ","))) else
  ng("A2 정본 arm ③d 거부 = 과잉 차단", paste(sprintf("%s[%s]", res$kind[!res$ok], substr(res$why[!res$ok], 1, 90)), collapse = " "))
gk <- names(AL$grants)
for (k in gk) {
  r0 <- pN$overlay_probe_allowlist_scan(file.path(ADIR, paste0(k, ".R")), kind = NULL, al = AL)
  if (!isTRUE(r0$ok)) ok(sprintf("A2b %s 는 공통 목록만으로는 거부(%d건 — 능력 계열은 sha 고정 허가로만 산다)", k, nrow(r0$hits))) else
    ng(sprintf("A2b %s 가 허가 없이 통과 — 개별 허가가 하중을 안 진다", k))
}
# 전체 probe — 공통 arm 전수(외부 패널 로더 pg2 는 운영 패널 파일이 있어야 source 가 돈다 — ③d 는 A2 에서 쟀다)
t0 <- Sys.time(); full_bad <- character(0); nfull <- 0L
for (f in cf) { k <- sub("[.]R$", "", basename(f)); if (k %in% gk) next
  r <- NULL; invisible(capture.output(r <- pN$overlay_probe_arm(k, ROOT))); nfull <- nfull + 1L
  if (!isTRUE(r$ok) || !identical(row_of(r, "allowlist"), "PASS")) full_bad <- c(full_bad, sprintf("%s[%s: %s]", k, failed_at(r), substr(as.character(r$reason), 1, 80))) }
if (nfull > 0L && !length(full_bad)) ok(sprintf("A3 정본 공통 arm %d종 전체 probe(①~⑤) 통과 · allowlist 행 PASS (%.0fs)", nfull, as.numeric(difftime(Sys.time(), t0, units = "secs")))) else
  ng("A3 전체 probe 과잉 차단", paste(full_bad, collapse = " "))
# 빌더 재현 — 레지스트리에 적힌 출처 arm(같은 sha)으로 다시 빌드하면 같은 목록이 나와야 한다(손편집·드리프트 탐지)
sha_now <- vapply(cf, pN$.op_sha256, character(1)); names(sha_now) <- ck
src_sha <- vapply(J$source_arms, function(a) a$sha256, character(1)); names(src_sha) <- src_k
if (all(src_k %in% ck) && all(sha_now[src_k] == src_sha[src_k])) {
  bb <- pN$overlay_probe_allowlist_build(ADIR, as.character(unlist(J$ref_namespaces)), exclude = setdiff(ck, src_k))
  same_c <- all(vapply(names(AL$common), function(z) setequal(as.character(unlist(J$common[[z]])), as.character(unlist(bb$json$common[[z]]))), logical(1)))   # widened 는 빼고(원 common 만) 대조
  same_g <- setequal(names(bb$json$grants), gk) && all(vapply(gk, function(g) identical(bb$json$grants[[g]]$sha256, AL$grants[[g]]$sha256) &&
              all(vapply(setdiff(names(AL$common), character(0)), function(z) setequal(AL$grants[[g]][[z]], as.character(unlist(bb$json$grants[[g]][[z]]))), logical(1))), logical(1)))
  if (same_c && same_g) ok("A4 빌더 재현 — 출처 arm(같은 sha)으로 재빌드한 공통·개별 목록 = 레지스트리") else
    ng("A4 레지스트리 ≠ 재빌드 — 손편집 또는 빌더 드리프트", sprintf("common %s · grants %s", same_c, same_g))
} else skip("A4 출처 arm 이 바뀌었다(sha 불일치) — 재현 불가 · 레지스트리 재검토 대상")
# 파서 토큰 ↔ AST 머리 일치(추출기 두 구현) — 정본 전수
ref <- pN$.op_ref_index(AL$ref_ns)
mm <- Filter(nzchar, vapply(cf, function(f) { x <- pN$.op_allow_extract(f, ref)
  m <- setdiff(x$tok_calls, x$occ[x$occ$role == "head", ]$name); if (length(m)) paste0(basename(f), ":", paste(m, collapse = ",")) else "" }, character(1)))
if (!length(mm)) ok(sprintf("A5 파서 토큰(getParseData) 호출 머리 ⊆ AST 머리 — 정본 %d종(두 추출기가 갈리지 않는다)", length(cf))) else ng("A5 추출 불일치", paste(mm, collapse = " "))

# ══ B. 위반 주입 — 허용 목록 밖 1개 ══════════════════════════════════════════════
writeLines("=== B. 위반 주입 — 합성 arm(허용 밖 형태 1개) → ③d 거부 ===")
V <- list(
  B01 = list(bad = "z0 <- eval.parent(1)",                                  rule = "call_not_allowed", c3 = FALSE),
  B02 = list(bad = "z0 <- rlang::caller_env()",                             rule = "pkg_not_allowed",  c3 = FALSE),
  B03 = list(bad = "z0 <- do.call(\"sys.frame\", list(0L))",                rule = "docall_string",    c3 = FALSE),
  B04 = list(bad = "z0 <- sys.frames",                                      rule = "value_not_allowed", c3 = FALSE),
  B05 = list(bad = "z0 <- `sys.function`",                                  rule = "value_not_allowed", c3 = FALSE),
  B06 = list(bad = "z0 <- lapply(0L, paste0(\"sys.\", \"frame\"))",          rule = "computed_fn",      c3 = FALSE),
  B07 = list(bad = "z0 <- get0(\"zz\", envir = globalenv(), ifnotfound = 1)", rule = "call_not_allowed", c3 = FALSE),
  B08 = list(bad = "assign(\"zz_al\", 1, envir = new.env())",               rule = "call_not_allowed", c3 = FALSE),
  B09 = list(bad = "tag <- \"#\"; z0 <- dynGet(\"zz\", ifnotfound = 1)",    rule = "call_not_allowed", c3 = TRUE),
  B10 = list(bad = "z0 <- (sys.frame)(0L)",                                 rule = "call_not_allowed", c3 = FALSE),
  B11 = list(bad = "z0 <- lapply(1L, lapply, \"sum\")",                     rule = "fn_not_allowed",   c3 = FALSE),
  B12 = list(bad = "l0 <- list(1); z0 <- l0[[1L]](2)",                      rule = "computed_head",    c3 = FALSE),
  B13 = list(bad = "nm <- \"sum\"; z0 <- apply(matrix(1), 1L, nm)",         rule = "fn_not_allowed",   c3 = FALSE),
  B14 = list(bad = "g0 <- function(...) lapply(...)",                       rule = "hof_dots",         c3 = FALSE),
  B15 = list(bad = "zz_al_g <<- 1",                                         rule = "call_not_allowed", c3 = FALSE),
  B16 = list(bad = "H2 <- data.table::copy(H); H2[, zz := 1]",              rule = "call_not_allowed", c3 = FALSE),
  B17 = list(bad = "if (FALSE) sys.frame <- 1; z0 <- sys.frame",            rule = "value_not_allowed", c3 = FALSE),
  B18 = list(bad = "z0 <- base:::sys.function",                             rule = "internal",         c3 = FALSE),
  B19 = list(bad = "if (FALSE) z0 <- Sys.getenv(\"QM_ROOT\")",              rule = "call_not_allowed", c3 = FALSE),
  B20 = list(bad = "if (FALSE) z0 <- readRDS(\"x.rds\")",                   rule = "call_not_allowed", c3 = FALSE),
  B21 = list(bad = "z0 <- environment(stats::median)",                      rule = "call_not_allowed", c3 = FALSE),
  B22 = list(bad = "z0 <- stats::ave(1, 1, FUN = \"sys.frame\")",           rule = "fn_not_allowed",   c3 = FALSE),
  B23 = list(bad = "z0 <- nrow(RAWDATA_zz)",                                rule = "free_name",        c3 = FALSE),
  B24 = list(bad = "z0 <- match.fun(\"sum\")",                              rule = "call_not_allowed", c3 = FALSE))
nB <- 0L
for (nm in names(V)) {
  v <- V[[nm]]; k <- paste0("zz_al_", tolower(nm)); src <- paste(arm_lines(k, v$bad), collapse = "\n")
  s <- pN$overlay_probe_allowlist_scan(src, al = AL)
  if (!isTRUE(s$ok) && v$rule %in% s$hits$rule) nB <- nB + 1L else
    ng(sprintf("%s ③d 미검출 — %s", nm, v$bad), sprintf("rules=%s", paste(s$hits$rule, collapse = ",")))
}
if (nB == length(V)) ok(sprintf("B1~B24 ③d 가 %d종 전부 거부 — 기대 규칙으로(호출·값·함수 자리·계산된 머리·dots·<<-·:=·:::·능력 계열·자유 이름)", nB))
# 문자열 한 덩어리(파일이 아님) · 파싱 불가 = 거부
s <- pN$overlay_probe_allowlist_scan("overlay_expo_x <- function(H, t, ctx) {\n  1 +\n", al = AL)
if (!isTRUE(s$ok) && "unparseable" %in% s$hits$rule) ok("B25 파싱 불가 소스 = 거부(unparseable)") else ng("B25 파싱 불가", paste(s$hits$rule, collapse = ","))
# 음성 대조 — 경계(통과해야 할 것): 함수 리터럴 FUN · 지역 변수 이름이 참조 이름과 겹침 · pkg::name FUN · 연산자 문자열 FUN · 지역 도우미
okc <- list(
  N1 = "g1 <- function(r) r[1L]; z0 <- apply(matrix(1:4, 2L), 1L, g1)",
  N2 = "col <- 2L; nobs <- 3L; z0 <- col + nobs",
  N3 = "z0 <- apply(matrix(1:4, 2L), 2L, stats::sd)",
  N4 = "z0 <- sweep(matrix(1:4, 2L), 2L, c(1, 2), \"-\")",
  N5 = "rk <- function(x) rank(x) / length(x); z0 <- rk(c(3, 1, 2))",
  N6 = "z0 <- stats::ecdf(c(1, 2, 3))(2)",
  N7 = "tag <- \"#\"; z0 <- nzchar(tag) # 주석 속 parent.frame() 은 코드가 아니다",
  N8 = "z0 <- sweep(matrix(1:4, 2L), 2L, c(1, 2), \"*\")",
  N9 = "z0 <- vapply(list(c(1, 2)), \"[[\", numeric(1), 1L)")
bad_ok <- character(0)
for (nm in names(okc)) { k <- paste0("zz_al_", tolower(nm)); s <- pN$overlay_probe_allowlist_scan(paste(arm_lines(k, okc[[nm]]), collapse = "\n"), al = AL)
  if (!isTRUE(s$ok)) bad_ok <- c(bad_ok, sprintf("%s[%s]", nm, s$reason)) }
if (!length(bad_ok)) ok(sprintf("B26 음성 대조 %d종 통과 — 함수 리터럴 FUN · 지역 이름 col/nobs · stats::sd FUN · \"-\"·\"*\"·\"[[\" FUN · 지역 도우미 · ecdf(x)(v) · 문자열 #", length(okc))) else
  ng("B26 경계 오탐", paste(bad_ok, collapse = " "))
# 전체 probe — ③c 가 못 보는 통로(c3 = FALSE)는 allowlist 에서, B09(문자열 '#')는 이제 ③c 에서도 선다
full_miss <- character(0)
for (nm in c("B01", "B02", "B03", "B04", "B06", "B07", "B09", "B10", "B13", "B15", "B17", "B22")) {
  v <- V[[nm]]; k <- paste0("zz_al_", tolower(nm)); r <- inject(pN, k, arm_lines(k, v$bad))
  want <- if (isTRUE(v$c3)) c("scope", "allowlist") else "allowlist"
  if (isTRUE(r$ok) || !failed_at(r) %in% want) full_miss <- c(full_miss, sprintf("%s[%s]", nm, failed_at(r)))
}
if (!length(full_miss)) ok("B27 전체 probe 가 위반 arm 12종을 등재 전에 거부(③c 밖 통로 = allowlist · 문자열 '#' = scope)") else ng("B27 전체 probe 통과", paste(full_miss, collapse = " "))
# 수리 전 red — 같은 arm 을 수리 전 probe 가 통과시키는가(결함 실증)
BASE <- Sys.getenv("QVEST_R3R_BASE_PROBE", "")
if (!nzchar(BASE)) {
  b <- file.path(TD, "overlay_probe_base.R")
  st <- tryCatch(system2("git", c("-C", shQuote(ROOT), "show", "HEAD:02_Infrastructure/reinforcement/overlay_probe.R"), stdout = b, stderr = FALSE), error = function(e) 1L)
  sh <- tryCatch(system2("git", c("-C", shQuote(ROOT), "rev-parse", "HEAD:02_Infrastructure/reinforcement/overlay_probe.R"), stdout = TRUE, stderr = FALSE), error = function(e) "")
  if (identical(st, 0L) && identical(as.character(sh)[1], "6aad06038a8f5b830d7d42c8c6fed68142d6bc35")) BASE <- b
}
if (nzchar(BASE) && file.exists(BASE) && !any(grepl("overlay_probe_allowlist_scan", readLines(BASE, warn = FALSE), fixed = TRUE))) {
  pB <- load_probe(BASE); red <- character(0); green <- character(0)
  for (nm in c("B01", "B02", "B03", "B04", "B06", "B07", "B09", "B10")) {   # 런타임에 무해한 형태만(값을 안 쓴다) — 구판이 ④⑤ 까지 통과해야 red
    k <- paste0("zz_al_", tolower(nm)); r <- inject(pB, k, arm_lines(k, V[[nm]]$bad))
    if (isTRUE(r$ok)) red <- c(red, nm) else green <- c(green, sprintf("%s[%s]", nm, failed_at(r)))
  }
  if (length(red) == 8L) ok(sprintf("B28 수리 전 probe(%s) 는 위반 arm 8종을 전부 통과시킨다 — 결함 실증(red)", basename(BASE))) else
    ng("B28 수리 전 probe 가 이미 잡는다 — 결함 전제 재확인", paste(green, collapse = " "))
} else skip("B28 수리 전 probe 미확보(QVEST_R3R_BASE_PROBE 또는 HEAD 블롭 6aad0603)")

# ══ C. 주석 걷기 — 문자열 안 '#' ════════════════════════════════════════════════
writeLines("=== C. 주석 걷기(파서 기반) ===")
fC <- file.path(TD, "c_hash.R")
writeLines(c("f <- function(H, t, ctx) {", "  tag <- \"#\"; z <- dynGet(\"zz\", ifnotfound = 1)   # 진짜 주석: parent.frame()", "  1", "}"), fC)
nc <- pN$.op_src_nc(fC)
old_nc <- paste(sub("#.*$", "", readLines(fC, warn = FALSE)), collapse = "\n")
if (grepl("dynGet", nc, fixed = TRUE) && !grepl("parent.frame", nc, fixed = TRUE)) ok("C1 문자열 안 '#' 뒤 코드는 남고(dynGet) 진짜 주석은 걷힌다(parent.frame 언급)") else ng("C1 걷기", nc)
if (!grepl("dynGet", old_nc, fixed = TRUE)) ok("C1b 구 걷기 sub(\"#.*$\") 는 dynGet 을 지웠다(red)") else ng("C1b 구 걷기 전제")
sc <- pN$overlay_probe_scope_scan(fC)
if (nrow(sc) && "frame_walk" %in% sc$rule) ok("C2 ③c 스캔(경로 입력)이 문자열 '#' 뒤 dynGet 을 본다") else ng("C2 ③c", paste(sc$rule, collapse = ","))
if (!nrow(pN$overlay_probe_scope_scan(old_nc))) ok("C2b 구 걷기 결과로는 ③c 가 0건(red — 걷기가 하중을 진다)") else ng("C2b 전제")
fU <- file.path(TD, "c_unparse.R"); writeLines(c("f <- function( {", "  x # c"), fU)
if (isTRUE(attr(pN$.op_src_nc(fU), "parse_failed"))) ok("C3 파싱 불가 파일 = parse_failed 표식(③d 가 unparseable 로 거부)") else ng("C3 표식 없음")

# ══ D. 레지스트리 fail-closed ═══════════════════════════════════════════════════
writeLines("=== D. 레지스트리 fail-closed ===")
mk_root <- function(tag, reg) {
  r <- file.path(TD, paste0("root_", tag))
  dir.create(file.path(r, "02_Infrastructure/reinforcement/overlay_arms"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(ADIR, "dbeta_tilt.R"), file.path(r, "02_Infrastructure/reinforcement/overlay_arms"), overwrite = TRUE)
  if (is.character(reg)) writeLines(reg, file.path(r, "06_Registry/overlay_probe_allowlist.json"))
  else if (is.list(reg)) writeLines(toJSON(reg, auto_unbox = TRUE, pretty = TRUE), file.path(r, "06_Registry/overlay_probe_allowlist.json"))
  r
}
with_qm <- function(r, expr) { o <- Sys.getenv("QM_ROOT", unset = NA); Sys.setenv(QM_ROOT = r); on.exit(if (is.na(o)) Sys.unsetenv("QM_ROOT") else Sys.setenv(QM_ROOT = o)); force(expr) }
J2 <- function(...) { x <- J; v <- list(...); for (k in names(v)) x[[k]] <- v[[k]]; x }
capJ <- J; capJ$common$calls <- c(unlist(capJ$common$calls), "sys.frame")
nsJ  <- J; nsJ$ref_namespaces <- c(unlist(nsJ$ref_namespaces), "zzNotAPkgR3R")
cases <- list(list(tag = "absent", reg = NULL,              why = "부재"),
              list(tag = "broken", reg = "{ broken",        why = "JSON 파손"),
              list(tag = "schema", reg = J2(schema = "x"),  why = "schema"),
              list(tag = "cap",    reg = capJ,              why = "능력 계열 오염(sys.frame ∈ common)"),
              list(tag = "ns",     reg = nsJ,               why = "참조 이름공간 부재"))
for (cs in cases) {
  r <- mk_root(cs$tag, cs$reg)
  rr <- with_qm(r, { x <- NULL; invisible(capture.output(x <- pN$overlay_probe_arm("dbeta_tilt", r))); x })
  if (!isTRUE(rr$ok) && identical(failed_at(rr), "allowlist")) ok(sprintf("D %s → 정본 arm 도 allowlist FAIL(fail-closed)", cs$why)) else
    ng(sprintf("D %s 가 통과", cs$why), as.character(rr$reason))
}
# widened(사람 검토 확장) — 순수 함수는 넓혀지고 · 능력 계열을 넣으면 레지스트리째 무효
wJ <- J; wJ$widened <- list(calls = list("tanh"), reason = "test")
rW <- mk_root("wide_ok", wJ)
sW <- with_qm(rW, pN$overlay_probe_allowlist_scan(paste(arm_lines("zz_w", "z0 <- tanh(0.5)"), collapse = "\n"), root = rW))
s0 <- pN$overlay_probe_allowlist_scan(paste(arm_lines("zz_w", "z0 <- tanh(0.5)"), collapse = "\n"), al = AL)
if (isTRUE(sW$ok) && !isTRUE(s0$ok)) ok("D7 widened.calls 에 넣은 순수 함수(tanh)는 통과 · 정본 목록만으로는 거부") else ng("D7 widened", paste(sW$reason, s0$ok))
wJ2 <- J; wJ2$widened <- list(calls = list("sys.function"), reason = "test")
rW2 <- mk_root("wide_cap", wJ2)
rr <- with_qm(rW2, { x <- NULL; invisible(capture.output(x <- pN$overlay_probe_arm("dbeta_tilt", rW2))); x })
if (!isTRUE(rr$ok) && identical(failed_at(rr), "allowlist") && grepl("능력 계열", rr$reason, fixed = TRUE)) ok("D8 widened 에 능력 계열(sys.function) → 레지스트리 무효 · 정본 arm 도 FAIL") else ng("D8 widened 능력 계열", as.character(rr$reason))
# 개별 허가 sha — pg2 사본에 한 줄(환경 조작)만 더하면 허가가 풀리고 거부된다
if (length(gk)) {
  g1 <- gk[1]; fG <- file.path(TD, paste0(g1, ".R"))
  writeLines(c(readLines(file.path(ADIR, paste0(g1, ".R")), warn = FALSE, encoding = "UTF-8"),
               ".zz_peek <- function() get(\"zz_any\", envir = globalenv())"), fG, useBytes = TRUE)
  sG <- pN$overlay_probe_allowlist_scan(fG, kind = g1, al = AL)
  if (!isTRUE(sG$ok) && grepl("sha 불일치", sG$grant, fixed = TRUE)) ok(sprintf("D6 %s 한 줄 변경 → 개별 허가 무효(sha 불일치) · 거부 %d건", g1, nrow(sG$hits))) else
    ng("D6 sha 고정", paste(sG$grant, sG$reason))
} else skip("D6 개별 허가 없음")

# ══ E. 돌연변이 — 검사가 하중을 지는가 ══════════════════════════════════════════
writeLines("=== E. 돌연변이 ===")
PX <- readLines(PROBE, warn = FALSE, encoding = "UTF-8")
mutant <- function(tag, from, to) {
  h <- which(PX == from)
  if (length(h) != 1L) { ng(sprintf("E %s 돌연변이 앵커", tag), sprintf("%d건(1건이어야)", length(h))); return(NULL) }
  X <- PX; X[h] <- to; p <- file.path(TD, paste0("probe_mut_", tag, ".R")); writeLines(X, p, useBytes = TRUE); load_probe(p)
}
m1 <- mutant("no3d", "  al_s <- overlay_probe_allowlist_scan(p, kind = kind, root = root)",
                     "  al_s <- list(ok = TRUE, grant = \"MUTANT\", al_path = \"-\", fallback = FALSE)")
if (!is.null(m1)) {
  pass_m <- character(0)
  for (nm in c("B01", "B02", "B03", "B06")) { k <- paste0("zz_al_", tolower(nm)); r <- inject(m1, k, arm_lines(k, V[[nm]]$bad)); if (isTRUE(r$ok)) pass_m <- c(pass_m, nm) }
  if (length(pass_m) == 4L) ok("E1 ③d 무력화 → eval.parent·rlang::caller_env·do.call(\"sys.frame\")·계산된 FUN 4종 전부 통과(③c 만으로는 못 막는다 = ③d 가 하중)") else
    ng("E1 ③d 없이도 잡힌다 — 전제 재확인", paste(pass_m, collapse = ","))
}
scan_m <- function(pe, nm) pe$overlay_probe_allowlist_scan(paste(arm_lines("zz_m", V[[nm]]$bad), collapse = "\n"), al = AL)$ok
m2 <- mutant("r5", "      hit(\"computed_fn\", sprintf(\"%s(… %s …)\", o$hof[i], o$snip[i]))", "      NULL")
if (!is.null(m2)) { if (isTRUE(scan_m(m2, "B06"))) ok("E2 R5(계산된 함수 자리) 제거 → lapply(0L, paste0(\"sys.\",\"frame\")) 통과 = R5 가 하중") else ng("E2 R5 제거에도 거부") }
m3 <- mutant("r2", "      if (n %in% A$values || n %in% c(\"...\", sprintf(\"..%d\", 1:9))) next", "      next")
if (!is.null(m3)) { if (isTRUE(scan_m(m3, "B04")) && isTRUE(scan_m(m3, "B17"))) ok("E3 R2(값 자리) 제거 → 별칭 z0 <- sys.frames · 조건부 묶기 별칭 통과 = R2 가 하중") else ng("E3 R2 제거에도 거부") }
ALc <- AL; ALc$common$fnstrs <- c(ALc$common$fnstrs, "cbind")
dsrc <- paste(arm_lines("zz_d", "z0 <- do.call(\"cbind\", list(1, 2))"), collapse = "\n")
s4 <- pN$overlay_probe_allowlist_scan(dsrc, al = ALc)
m4 <- mutant("docall", "      if (identical(o$hof[i], \"do.call\")) { hit(\"docall_string\", sprintf('do.call(\"%s\", …)', n)); next }", "      NULL")
if (!isTRUE(s4$ok) && "docall_string" %in% s4$hits$rule && !is.null(m4) && isTRUE(m4$overlay_probe_allowlist_scan(dsrc, al = ALc)$ok))
  ok("E4 do.call 문자열 규칙 — \"cbind\" 가 fnstrs 에 있어도 do.call(\"cbind\") 거부 · 규칙 제거 돌연변이는 통과(규칙이 하중)") else ng("E4 do.call 문자열", paste(s4$hits$rule, collapse = ","))
if (length(gk)) {
  m5 <- mutant("sha", "    if (nzchar(g$sha256) && identical(tolower(sh), tolower(g$sha256))) {", "    if (TRUE) {")
  if (!is.null(m5)) { s5 <- m5$overlay_probe_allowlist_scan(fG, kind = gk[1], al = AL)
    if (isTRUE(s5$ok)) ok(sprintf("E5 sha 대조 우회 → 변경된 %s(get(…, envir = globalenv()) 추가)가 통과 = sha 고정이 하중", gk[1])) else ng("E5 sha 우회에도 거부", s5$reason) }
}
m6 <- mutant("strip", "  s <- .op_strip_comments(ln)", "  s <- sub(\"#.*$\", \"\", ln)")
if (!is.null(m6)) { if (!nrow(m6$overlay_probe_scope_scan(fC))) ok("E6 구 주석 걷기 돌연변이 → ③c 가 문자열 '#' 뒤 dynGet 을 놓친다(파서 걷기가 하중)") else ng("E6 구 걷기에도 ③c 검출") }

# ══ F. LOO (정보 — 판정 아님) ════════════════════════════════════════════════════
writeLines("=== F. LOO(정보) — 공통 arm 하나를 빼고 만든 목록으로 그 arm 을 잰다 ===")
comm <- setdiff(ck, gk)
loo <- rbindlist(lapply(comm, function(k) {
  bb <- pN$overlay_probe_allowlist_build(ADIR, AL$ref_ns, exclude = c(k, setdiff(ck, src_k)))
  al2 <- list(ok = TRUE, path = "loo", fallback = FALSE, ref_ns = AL$ref_ns, common = lapply(bb$json$common, as.character), grants = list(), schema_cols = character(0))
  r <- pN$overlay_probe_allowlist_scan(file.path(ADIR, paste0(k, ".R")), kind = k, al = al2)
  data.table(kind = k, ok = r$ok, why = paste(unique(r$hits$snippet), collapse = ","))
}))
writeLines(sprintf("  INFO  LOO 통과 %d/%d — 거부 arm 의 목록 밖 이름: %s", sum(loo$ok), nrow(loo),
                   paste(sprintf("%s{%s}", loo$kind[!loo$ok], loo$why[!loo$ok]), collapse = " ")))

left <- list.files(ADIR, pattern = "^zz_al_")
if (!length(left)) ok("G 픽스처 잔여 0") else ng("G 픽스처 잔여", paste(left, collapse = ","))
unlink(TD, recursive = TRUE, force = TRUE)
writeLines("")
writeLines(sprintf("합계: 통과 %d · 실패 %d · 건너뜀 %d", PASS, FAIL, SKIP))
cat(sprintf('{"test":"overlay_probe_allowlist","pass":%d,"fail":%d,"skip":%d,"total":%d}\n', PASS, FAIL, SKIP, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
