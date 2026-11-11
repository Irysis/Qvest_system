## test_round_core_v2_v1parity.R — 'v1 결과 동일' 시험(코어 v2 출시 · 2026-11-11): v1 코어 시험 7종을 코어 경로만 v2 로 바꿔 그대로 돌린다.
##   통과 조건: 모든 단언이 통과한다 — 단, 아래 EXPECT 에 사유와 함께 적은 단언(v2 의 의도한 변화 · 결정 P4-BASE-POOL-GRADE-PATH-TAU-20261111 (나) ·
##   판단 T1 C-20261111-001)만 실패해야 한다. 예상 실패가 통과로 바뀌거나(목록이 썩는다) 목록 밖 실패 · 중단(요약 줄 없음)이 나오면 실패.
##   픽스처 보정(사본에만 · 원본 무접촉 · 적용 횟수 단정 — 치환이 빗나가 가짜 대조가 되지 않게):
##     ① 코어 경로 round_core/v1 → v2 ② 사슬 기저 픽스처(권위 등급 B 경로 · v2 에 없음)를 같은 엔진의 상설 표준 칸 통과 행으로 바꿔 넣는 입력 보정
##     (.v2p_wrapper — 판정 함수 rc_p4_base_pool 은 그대로 부른다 · 칸 사양 없는 픽스처 상설 항목은 표준 칸으로 본다) ③ 시험이 p4.R 을 다시 적재하면 보정을 다시 씌운다
##     ④ v2 에서 지운 함수(.rcp4_rule_benefit) 호출은 실패 표식으로(시험이 중단되지 않게 — 해당 단언은 EXPECT 의 예상 실패)
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/programs/test_round_core_v2_v1parity.R   (약 2분 · 임시 폴더만 쓴다)
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v2/load.R"))) stop("저장소 루트가 아니다(v2 없음): ", ROOT)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
TD <- gsub("\\\\", "/", file.path(tempdir(), "rc_v2_parity")); unlink(TD, recursive = TRUE); dir.create(TD, recursive = TRUE)
if (startsWith(tolower(TD), tolower(paste0(ROOT, "/")))) stop("임시 폴더가 저장소 안이다 — 중단")

SHIM <- c(
  "## [v1 동일 대조 입력 보정 — test_round_core_v2_v1parity] v2 기저 풀에는 등급 경로가 없다(결정 (나)). 사슬 기저 픽스처(engine:T_ok · E_ok · E_nob)를",
  "##   같은 엔진의 상설 표준 칸 통과 행으로 넣고, 칸 사양이 없는 픽스처 상설 항목(구성 판독 NA)은 표준 칸으로 본다. 판정 함수는 그대로 부른다.",
  ".v2p_wrapper <- function(root = rc_root(), registry_path = NULL, standing = NULL, fdv_ledger_path = NULL) {",
  "  Q <- data.table::copy(standing %||% rc_standing_qualified(root = root))",
  "  if (!(\"construction\" %in% names(Q))) Q[, construction := rep(NA_character_, .N)]",
  "  Q[is.na(construction), construction := \"standard\"]",
  "  R <- .rcp4_registry_engines(pr_load(root, registry_path))",
  "  add <- if (!is.null(R)) R[key %in% c(\"engine:T_ok\", \"engine:E_ok\", \"engine:E_nob\")] else NULL",
  "  if (!is.null(add) && nrow(add)) {",
  "    ep <- vapply(add$engine_raw, function(p) .rcp4_rel(p, root), \"\")",
  "    Q <- rbind(Q, data.table::data.table(round_id = \"V2P_fixture\", edition = 1L, code = paste0(\"V2P_\", sub(\"^engine:\", \"\", add$key)), engine = add$key,",
  "                                         engine_path = ep, engine_md5 = vapply(ep, function(p) rc_md5(.rcp4_abs(p, root)), \"\"), engine_same = TRUE,",
  "                                         artifacts = vapply(add$artifacts_raw, function(p) .rcp4_rel(p, root), \"\"), paper_key = add$paper_key,",
  "                                         verdict_at = \"2026-11-10T12:00:00+0900\", ledger = \"v2p_fixture\", construction = \"standard\"), fill = TRUE)",
  "  }",
  "  .V2P_POOL(root, registry_path, Q, fdv_ledger_path)",
  "}",
  ".v2p_reshim <- function() { cur <- get(\"rc_p4_base_pool\", envir = globalenv()); if (!identical(cur, .v2p_wrapper)) assign(\".V2P_POOL\", cur, envir = globalenv())",
  "                            assign(\"rc_p4_base_pool\", .v2p_wrapper, envir = globalenv()) }",
  ".v2p_reshim()")

## 시험별 사본 만들기 — 치환 목록(찾을 글 · 바꿀 글 · 기대 횟수 하한)
SUITES <- list(
  list(f = "08_Tests/programs/test_round_core_v1.R", shim = FALSE, subs = list()),
  list(f = "08_Tests/programs/test_round_core_v1_flow.R", shim = FALSE, subs = list()),
  list(f = "08_Tests/programs/test_round_core_v1_standing.R", shim = FALSE, subs = list()),
  list(f = "08_Tests/programs/test_round_core_v1_p2.R", shim = FALSE, subs = list()),
  list(f = "08_Tests/programs/test_round_core_v1_p4_chain.R", shim = TRUE, subs = list()),
  list(f = "08_Tests/scenarios/test_scn_l1_chain_e2e.R", shim = TRUE, subs = list(
    list("rbu <- .rcp4_rule_benefit(A_SRB, TR)", "rbu <- tryCatch(.rcp4_rule_benefit(A_SRB, TR), error = function(e) list(benefit = \"removed_in_v2\"))", 1L),
    list("restore_p4 <- function() sys.source(\"04_Research/programs/_lib/round_core/v2/p4.R\", envir = globalenv())",
         "restore_p4 <- function() { sys.source(\"04_Research/programs/_lib/round_core/v2/p4.R\", envir = globalenv()); .v2p_reshim() }", 1L),
    list("sys.source(mu$path, envir = globalenv());", "sys.source(mu$path, envir = globalenv()); .v2p_reshim();", 1L),
    list("sys.source(mcm$path, envir = globalenv())", "sys.source(mcm$path, envir = globalenv()); .v2p_reshim()", 1L))),
  list(f = "08_Tests/scenarios/test_scn_chain_tick_core.R", shim = TRUE, subs = list()))

## 예상 실패(단언 머리 id) — 사유는 v2 의 의도한 변화
EXPECT <- list(
  test_round_core_v1_flow = c(C3 = "사전등록 코어 판 표기 = v2(시험이 'v1' 을 단정 — 판 이름만 다르다)"),
  test_round_core_v1_standing = c(H5 = "v1 에서도 실패(11-11 15:12 P1S01 실제 등록 뒤 — 시험이 복사한 등록부에 실제 판이 하나 더 있다 · 판 목록 판독은 맞다 · 시험 격리 결함)"),
  test_round_core_v1_p4_chain = c(A4 = "등급 B 행 사유 = not_qualified;factor_db_stale(등급 경로 폐지 — 결정 (나))",
                                  J1 = "기저가 상설 표준 칸 행이 되어 p4.same_construction = TRUE(v1 픽스처는 등급 경로 기저 = FALSE)"),
  test_scn_l1_chain_e2e = c(P3 = "규칙 변경 수혜 기록 제외는 등급 경로의 사유(v2 = 등급 경로 없음 → not_qualified)",
                            P5 = ".rcp4_rule_benefit 은 v2 에서 지웠다(등급 경로 전용)",
                            P6 = "돌연변이 대상(등급 경로 수혜 검사) 코드가 v2 에 없다(치환 0)"))

parse_log <- function(L) {
  rx <- "^\\s*\\[(ok|PASS|FAIL)\\]\\s+(\\S+)"
  m <- regmatches(L, regexec(rx, L)); m <- m[vapply(m, length, 0L) == 3L]
  data.frame(st = vapply(m, `[`, "", 2), id = vapply(m, `[`, "", 3), stringsAsFactors = FALSE)
}
for (S in SUITES) {
  nm <- sub("[.]R$", "", basename(S$f)); src <- readLines(S$f, encoding = "UTF-8", warn = FALSE)
  n1 <- sum(lengths(regmatches(src, gregexpr("round_core/v1", src, fixed = TRUE)))) + sum(lengths(regmatches(src, gregexpr("\"round_core\", \"v1\"", src, fixed = TRUE))))
  src <- gsub("round_core/v1", "round_core/v2", src, fixed = TRUE); src <- gsub("\"round_core\", \"v1\"", "\"round_core\", \"v2\"", src, fixed = TRUE)
  ok_sub <- n1 >= 1L; why <- sprintf("코어 경로 %d", n1)
  if (isTRUE(S$shim)) {
    i <- grep("round_core/v2/load.R", src, fixed = TRUE)[1]
    if (is.na(i)) { ok_sub <- FALSE; why <- c(why, "코어 적재 줄 없음") } else src <- append(src, SHIM, after = i)
  }
  for (s in S$subs) { k <- sum(lengths(regmatches(src, gregexpr(s[[1]], src, fixed = TRUE)))); if (k < s[[3]]) { ok_sub <- FALSE; why <- c(why, sprintf("치환 빗나감(%d): %s", k, substr(s[[1]], 1, 50))) }
                      src <- gsub(s[[1]], s[[2]], src, fixed = TRUE) }
  chk(sprintf("%s — 사본 보정 적용(경로 · 입력 보정 · 치환 횟수 단정)", nm), ok_sub, why)
  f2 <- file.path(TD, paste0(nm, "_v2.R")); writeLines(src, f2, useBytes = TRUE)
  t0 <- Sys.time(); out <- suppressWarnings(system2("Rscript", shQuote(f2), stdout = TRUE, stderr = TRUE)); sec <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))
  writeLines(out, file.path(TD, paste0(nm, "_v2.log")), useBytes = TRUE)
  P <- parse_log(out); fails <- unique(P$id[P$st == "FAIL"]); exp <- names(EXPECT[[nm]] %||% character(0))
  done <- any(grepl("\"test\":", out, fixed = TRUE)) || any(grepl("^== .*(PASS|ok)", out))
  chk(sprintf("%s — 끝까지 돌았다(요약 줄 · 단언 %d · %d초)", nm, nrow(P), sec), done && nrow(P) > 0L, tail(out, 3))
  chk(sprintf("%s — 목록 밖 실패 0", nm), !length(setdiff(fails, exp)), setdiff(fails, exp))
  chk(sprintf("%s — 예상 실패 %d건은 실제로 실패한다(목록이 썩지 않았다)", nm, length(exp)), !length(setdiff(exp, fails)), setdiff(exp, fails))
  cat(sprintf("     %s: 통과 %d · 실패 %d(예상 %d)\n", nm, sum(P$st != "FAIL"), length(fails), length(exp)))
}
cat(sprintf("\n== test_round_core_v2_v1parity: %d ok · %d FAIL ==\n", PASS, FAIL))
quit(status = if (FAIL) 1L else 0L)
