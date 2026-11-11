## test_round_core_v3_v2parity.R — 'v2 결과 동일' 시험(코어 v3 · 2026-11-11 · 판 2 P1S02): v2 출시 때 v2 경로로 돌린 시험 전부를 코어 경로만 v3 로 바꿔 그대로 돌린다.
##   대상 = test_round_core_v2.R(v2 → v3) + test_round_core_v2_v1parity.R 가 v2 경로로 돌린 v1 코어 시험 7종(v1 → v3 · 같은 입력 보정 SHIM).
##   통과 조건: 모든 단언이 통과한다 — 단, 아래 EXPECT 에 사유와 함께 적은 단언(v2 가 이미 실패하던 것 · v3 의 의도한 변화 — 설계
##   portfolio_paper_layer_split_20261112 §6-4 · §8 · 판단 Superfan T4 R-20261111-008)만 실패해야 한다. 예상 실패가 통과로 바뀌거나(목록이 썩는다)
##   목록 밖 실패 · 중단(요약 줄 없음)이 나오면 실패.
##   픽스처 보정(사본에만 · 원본 무접촉 · 적용 횟수 단정 — 치환이 빗나가 가짜 대조가 되지 않게):
##     ① 코어 경로 round_core/v1 · v2 → v3 ② v2 시험의 판 이름 단정 3곳(RC_VERSION · 매니페스트 판 · 출시 기록 판)을 v3 로
##     ③ v1 시험 7종 = test_round_core_v2_v1parity.R 의 입력 보정(SHIM · 치환 4) 그대로
##     ④ v1 상설 시험의 대체 워커 — v3 측정 관문(셀 엔진 기저 정합 진단 필수)을 통과하는 정상 진단(rf_engine_diag.json)을 임시 산출 폴더에 쓴다
##        (실제 P0R01 산출 폴더에는 쓰지 않는다 · 관문 자체의 양방향 시험은 test_round_core_v3.R M · P 절)
##     ⑤ 사슬 시험의 가짜 러너 산출 — 같은 방식의 정상 진단을 쓴다(아래 P4_DIAG · 치환 횟수 단정)
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/programs/test_round_core_v3_v2parity.R   (약 3분 · 임시 폴더만 쓴다)
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v3/load.R"))) stop("저장소 루트가 아니다(v3 없음): ", ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
TD <- gsub("\\\\", "/", file.path(tempdir(), "rc_v3_parity")); unlink(TD, recursive = TRUE); dir.create(TD, recursive = TRUE)
if (startsWith(tolower(TD), tolower(paste0(ROOT, "/")))) stop("임시 폴더가 저장소 안이다 — 중단")

## ③ v2 출시 때의 입력 보정 — test_round_core_v2_v1parity.R 에서 그대로 읽는다(사본을 만들지 않는다 · 경로만 v3)
V2P <- readLines("08_Tests/programs/test_round_core_v2_v1parity.R", encoding = "UTF-8", warn = FALSE)
pe <- new.env(); a <- grep("^SHIM <- c\\(", V2P); b <- grep("^## 시험별 사본 만들기", V2P)
eval(parse(text = V2P[a:(b - 1L)], encoding = "UTF-8"), envir = pe)
a2 <- grep("^SUITES <- list\\(", V2P); b2 <- grep("^## 예상 실패", V2P)
eval(parse(text = V2P[a2:(b2 - 1L)], encoding = "UTF-8"), envir = pe)
SHIM <- pe$SHIM; V1S <- pe$SUITES
## ⑤ 사슬 시험(SHIM 대상 3종)의 가짜 러너는 셀 엔진을 돌리지 않아 진단 파일이 없다 — 진단 파일이 아예 없는 경우만 관문 대상 아님으로 본다
##   (진단이 있으면 관문을 그대로 탄다 · 관문 자체의 양방향 시험 = test_round_core_v3.R P 절 · 실제 산출 폴더에는 쓰지 않는다)
SHIM <- c(SHIM,
  "## [v3 동일 대조 입력 보정 — test_round_core_v3_v2parity] 가짜 러너 산출에는 셀 엔진 진단(rf_engine_diag.json)이 없다 — 파일이 없을 때만 관문 비대상",
  ".v3p_gate <- rc_standing_base_alignment",
  "rc_standing_base_alignment <- function(cell_spec, artifacts, tau, root = rc_root()) {",
  "  if (!file.exists(file.path(as.character(artifacts)[1], \"rf_engine_diag.json\"))) return(list(need = FALSE, ok = TRUE, error = NA_character_, why = \"v3 parity shim\", summary = NULL))",
  "  .v3p_gate(cell_spec, artifacts, tau, root)",
  "}")
chk("P0 v2 출시 보정 판독 — SHIM · 시험 7종(test_round_core_v2_v1parity.R)", length(SHIM) > 5L && length(V1S) == 7L, length(V1S))
fixsub <- function(s) { s[[1]] <- gsub("round_core/v2", "round_core/v3", s[[1]], fixed = TRUE); s[[2]] <- gsub("round_core/v2", "round_core/v3", s[[2]], fixed = TRUE); s }
for (i in seq_along(V1S)) V1S[[i]]$subs <- lapply(V1S[[i]]$subs, fixsub)

## ④ 상설 대체 워커 — 정상 진단(규칙 month_snap_v1 · base_kind factors · 격자 이탈 0)을 결과 옆 임시 산출 폴더에 쓴다
STUB_OLD <- '             "writeLines(as.character(jsonlite::toJSON(list(n = 1, code = code, ok = TRUE, artifacts = art), auto_unbox = TRUE)), out)"), STUB)'
STUB_NEW <- paste0('             "art <- file.path(dirname(out), paste0(code, \'_v3art\')); dir.create(art, recursive = TRUE, showWarnings = FALSE); ',
                   's <- jsonlite::fromJSON(a[1], simplifyVector = FALSE); p <- s$base_signal$path; ba <- list(); ',
                   'ba[[paste0(basename(dirname(p)), \'/\', basename(p))]] <- list(rule = \'month_snap_v1\', n_engine_dates = 1L, n_cell_dates = 1L, n_moved = 0L, n_superseded = 0L, n_offcal = 0L, base_kind = \'factors\'); ',
                   'writeLines(as.character(jsonlite::toJSON(list(schema = \'rf_engine_diag_v1\', base_alignment = ba), auto_unbox = TRUE)), file.path(art, \'rf_engine_diag.json\'))",\n', STUB_OLD)
for (i in seq_along(V1S)) if (grepl("test_round_core_v1_standing", V1S[[i]]$f)) V1S[[i]]$subs <- c(V1S[[i]]$subs, list(list(STUB_OLD, STUB_NEW, 1L)))
## ⑤-b 사슬 e2e 의 동시 측정 자식 프로세스(C10)에도 같은 보정 한 줄(자식은 SHIM 을 받지 않는다)
KID_OLD <- '             "a <- commandArgs(trailingOnly = TRUE)",'
KID_NEW <- paste0(KID_OLD, '\n             ".v3p_gate <- rc_standing_base_alignment; rc_standing_base_alignment <- function(cell_spec, artifacts, tau, root = rc_root()) { ',
                  'if (!file.exists(file.path(as.character(artifacts)[1], \'rf_engine_diag.json\'))) return(list(need = FALSE, ok = TRUE, error = NA_character_, why = \'v3 parity shim\', summary = NULL)); ',
                  '.v3p_gate(cell_spec, artifacts, tau, root) }",')
for (i in seq_along(V1S)) if (grepl("test_scn_l1_chain_e2e", V1S[[i]]$f)) V1S[[i]]$subs <- c(V1S[[i]]$subs, list(list(KID_OLD, KID_NEW, 1L)))

SUITES <- c(list(list(f = "08_Tests/programs/test_round_core_v2.R", from = "v2", shim = FALSE, subs = list(
  list('identical(RC_VERSION, "v2")', 'identical(RC_VERSION, "v3")', 1L),
  list('identical(m2$version, "v2")', 'identical(m2$version, "v3")', 1L),
  list('identical(r$version, "v2")', 'identical(r$version, "v3")', 1L)))),
  lapply(V1S, function(s) c(s, list(from = "v1"))))

## 예상 실패(단언 머리 id) — 사유
EXPECT <- list(
  test_round_core_v1_flow = c(C3 = "사전등록 코어 판 표기 = v3(시험이 'v1' 을 단정 — 판 이름만 다르다 · v2 때와 같은 사유)"),
  test_round_core_v1_standing = c(H5 = "v1 · v2 에서도 실패(11-11 P1S01 실제 등록 뒤 — 시험이 복사한 등록부에 실제 판이 하나 더 있다 · 시험 격리 결함 · RELEASES v2 known_limits)"),
  test_round_core_v1_p4_chain = c(A4 = "v2 때와 같다 — 등급 경로 폐지(결정 (나))", J1 = "v2 때와 같다 — 기저가 상설 표준 칸 행"),
  test_scn_l1_chain_e2e = c(P3 = "v2 때와 같다 — 등급 경로 사유", P5 = "v2 때와 같다 — .rcp4_rule_benefit 삭제", P6 = "v2 때와 같다 — 돌연변이 대상 코드 없음"))

parse_log <- function(L) {
  rx <- "^\\s*\\[(ok|PASS|FAIL)\\]\\s+(\\S+)"
  m <- regmatches(L, regexec(rx, L)); m <- m[vapply(m, length, 0L) == 3L]
  data.frame(st = vapply(m, `[`, "", 2), id = vapply(m, `[`, "", 3), stringsAsFactors = FALSE)
}
cnt <- function(src, s) sum(lengths(regmatches(src, gregexpr(s, src, fixed = TRUE))))
for (S in SUITES) {
  nm <- sub("[.]R$", "", basename(S$f)); src <- readLines(S$f, encoding = "UTF-8", warn = FALSE); fr <- S$from
  n1 <- cnt(src, paste0("round_core/", fr)) + cnt(src, sprintf("\"round_core\", \"%s\"", fr))
  src <- gsub(paste0("round_core/", fr), "round_core/v3", src, fixed = TRUE); src <- gsub(sprintf("\"round_core\", \"%s\"", fr), "\"round_core\", \"v3\"", src, fixed = TRUE)
  if (identical(fr, "v2")) {   # v2 시험 안의 v1 자식 프로세스(run_core("v1", …))는 그대로 v1 — 코어 경로 치환은 v2 경로만 건드린다
    src <- src }
  ok_sub <- n1 >= 1L; why <- sprintf("코어 경로 %d", n1)
  if (isTRUE(S$shim)) {
    i <- grep("round_core/v3/load.R", src, fixed = TRUE)[1]
    if (is.na(i)) { ok_sub <- FALSE; why <- c(why, "코어 적재 줄 없음") } else src <- append(src, gsub("round_core/v2", "round_core/v3", SHIM, fixed = TRUE), after = i)
  }
  for (s in S$subs) { k <- cnt(src, s[[1]]); if (k < s[[3]]) { ok_sub <- FALSE; why <- c(why, sprintf("치환 빗나감(%d): %s", k, substr(s[[1]], 1, 50))) }
                      src <- gsub(s[[1]], s[[2]], src, fixed = TRUE) }
  chk(sprintf("%s — 사본 보정 적용(경로 %s → v3 · 입력 보정 · 치환 횟수 단정)", nm, fr), ok_sub, why)
  f2 <- file.path(TD, paste0(nm, "_v3.R")); writeLines(src, f2, useBytes = TRUE)
  t0 <- Sys.time(); out <- suppressWarnings(system2("Rscript", shQuote(f2), stdout = TRUE, stderr = TRUE)); sec <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
  writeLines(out, file.path(TD, paste0(nm, "_v3.log")), useBytes = TRUE)
  P <- parse_log(out); fails <- unique(P$id[P$st == "FAIL"]); exp <- names(EXPECT[[nm]] %||% character(0))
  done <- any(grepl("\"test\":", out, fixed = TRUE)) || any(grepl("^== .*(PASS|ok)", out))
  chk(sprintf("%s — 끝까지 돌았다(요약 줄 · 단언 %d · %d초)", nm, nrow(P), sec), done && nrow(P) > 0L, tail(out, 3))
  chk(sprintf("%s — 목록 밖 실패 0", nm), !length(setdiff(fails, exp)), setdiff(fails, exp))
  chk(sprintf("%s — 예상 실패 %d건은 실제로 실패한다(목록이 썩지 않았다)", nm, length(exp)), !length(setdiff(exp, fails)), setdiff(exp, fails))
  cat(sprintf("     %s: 통과 %d · 실패 %d(예상 %d) · 로그 %s\n", nm, sum(P$st != "FAIL"), length(fails), length(exp), file.path(TD, paste0(nm, "_v3.log"))))
}
cat(sprintf("\n== test_round_core_v3_v2parity: %d ok · %d FAIL ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v3_v2parity","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL) 1L else 0L)
