## 시행 회계 — 강화 셀 sweep 채점 배선 (2026-09-23 · 강화 전수감사 D3-01 · 플랜 P0-01)
## 실사고: run_paper_replication.R:338 이 essence_score(n_trials=1, "chain") 을 하드코딩해, 격자 argmax·승격 사슬로
##   고르는 강화 셀 1,099/1,099 가 chain(DSR 면제 · dsr=null · n_trials 필드 부재)으로 채점됐다. judge.md 6축을 문자 그대로
##   적용하면 강화 레인 A 는 전부 무효 — A 가 나와도 BOOK 경로가 끊겨 있었다.
## 이 검사가 재는 것 (DSR 게이트 자체는 contract_regression/test_essence_score.R 가 이미 잰다 — 여기선 **배선**):
##   A. 러너 판정 함수(순수) — 계보 사슬·측정 칸 계수·회계 블록 (양성 + 순환/결손/미측정 주입)
##   B. 워커 인자 함수(.rf_sel_args) — 회계 있음 → sweep·N / 없음 → sweep·1·unknown 라벨(추정 금지 · fail-closed)
##   C. 계약: 워커가 넘기는 이름 ⊆ run_paper_replication formals · 기본값 chain/1(충실구현 비트 동일) ·
##      essence 호출이 리터럴이 아니라 인자를 쓴다 (돌연변이 사본으로 red 확인)
##   D. 원장 재도출 — 실제 계보에서 N 이 단조·양수이고 러너가 이 함수들을 부른다
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
GATES  <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")
WORKER <- file.path(ROOT, "02_Infrastructure/ops/rf_cell_worker.R")
RPR    <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
RUNNER <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")

## 파일에서 `name <- function(...)` 정의 식 하나만 꺼내 평가한다(스크립트 본문은 실행하지 않는다)
.def_from <- function(path, name, env = new.env(parent = globalenv())) {
  ex <- parse(file = path, encoding = "UTF-8", keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") &&
                  identical(as.character(e[[2]]), name), as.list(ex))
  if (!length(hit)) return(NULL)
  eval(hit[[1]], envir = env); get(name, envir = env)
}

cat("=== A. 러너 판정 함수 (rf_runner_gates.R · 순수) ===\n")
ge <- new.env(parent = globalenv())
suppressMessages(sys.source(GATES, envir = ge))
m <- function(pt) list(essence = list(port_t = pt))
ents <- list(
  list(base_id = "R",       attempts = list(m(1.2), m(NULL), m(2.0), list(grade = "NA (미결)"))),     # 측정 2
  list(base_id = "R_p1",    parent = list(base_id = "R"),    attempts = list(m(3.1), m(NA_real_), m(0.5))), # 측정 2 (NA 제외)
  list(base_id = "R_p2",    parent = list(base_id = "R_p1"), attempts = list(m(4.0))),                 # 측정 1
  list(base_id = "OTHER",   attempts = list(m(9), m(9), m(9))))                                         # 다른 계보
ids <- ge$rf_lineage_ids(ents, "R_p2")
if (identical(ids, c("R_p2", "R_p1", "R"))) ok("A1 계보 사슬 = 자신 → 부모 → 조부모") else ng("A1 사슬", paste(ids, collapse = ">"))
n <- ge$rf_lineage_measured(ents, ids)
if (identical(as.numeric(n), 5)) ok("A2 측정 칸만 계수 (NULL·NA·미측정 제외, 다른 계보 제외) = 5") else ng("A2 계수", n)
cyc <- list(list(base_id = "X", parent = list(base_id = "Y"), attempts = list()),
            list(base_id = "Y", parent = list(base_id = "X"), attempts = list()))
ids_c <- ge$rf_lineage_ids(cyc, "X")
if (identical(ids_c, c("X", "Y"))) ok("A3 순환 사슬은 끊긴다 (무한 루프 없음)") else ng("A3 순환", paste(ids_c, collapse = ">"))
ids_m <- ge$rf_lineage_ids(list(list(base_id = "Z", parent = list(base_id = "GONE"), attempts = list())), "Z")
if (identical(ids_m, c("Z", "GONE"))) ok("A4 결손 부모는 id 만 남기고 종료 (계수 0 기여)") else ng("A4 결손", paste(ids_m, collapse = ">"))
sa <- ge$rf_selection_accounting(ids, 5, 3L)
if (identical(sa$selection_type, "sweep") && identical(sa$n_family_at_registration, 8L) && identical(sa$family_root, "R"))
  ok("A5 회계 블록: sweep · N = 선행 5 + 배치 3 = 8 · family_root = 최상위 조상") else ng("A5 회계", toJSON(sa, auto_unbox = TRUE))
## 위반 주입 — 미측정을 세는 돌연변이는 A2 를 깨야 한다(계수 술어가 실제로 필터링함을 확인)
mut <- ge$rf_lineage_measured; body(mut) <- quote(sum(vapply(Filter(function(x) x$base_id %in% ids, entries), function(x) length(x$attempts), numeric(1))))
if (!identical(as.numeric(mut(ents, ids)), 5)) ok("A6 위반 주입: 미측정까지 세는 돌연변이는 5 가 아니다 (A2 가 판별력 있음)") else ng("A6 판별력 없음")

cat("\n=== B. 워커 인자 함수 (.rf_sel_args) ===\n")
sel <- .def_from(WORKER, ".rf_sel_args")
if (is.null(sel)) { ng("B0 .rf_sel_args 정의 부재") } else {
  a1 <- sel(list(selection_accounting = list(n_family_at_registration = 42L, n_trials_basis = "lineage_measured_cells_at_registration", family_root = "R")))
  if (identical(a1$selection_type, "sweep") && identical(a1$n_trials_cumulative, 42L) && identical(a1$family_root, "R"))
    ok("B1 회계 있음 → sweep · N=42 · family_root 전달") else ng("B1", toJSON(a1, auto_unbox = TRUE))
  a2 <- sel(list(code = "B1_1"))
  if (identical(a2$selection_type, "sweep") && identical(a2$n_trials_cumulative, 1L) &&
      identical(a2$n_trials_basis, "unknown_legacy_spec_no_accounting"))
    ok("B2 회계 없음(구 spec 재개) → N 추정 안 함: sweep · 1 · unknown 라벨 (A 분기 fail-closed)") else ng("B2", toJSON(a2, auto_unbox = TRUE))
  a3 <- sel(list(selection_accounting = list(n_family_at_registration = "abc")))
  if (identical(a3$n_trials_cumulative, 1L) && grepl("unknown", a3$n_trials_basis)) ok("B3 비정상 N → 1 · unknown (조용한 수치 날조 없음)") else ng("B3", toJSON(a3, auto_unbox = TRUE))
}
wsrc <- readLines(WORKER, warn = FALSE, encoding = "UTF-8"); wcode <- wsrc[!grepl("^\\s*#", wsrc)]
if (any(grepl('Sys.setenv(QVEST_RP_NO_LCODE = "1")', wcode, fixed = TRUE)))
  ok("B4 워커가 셀 L-code 억제 스위치를 켠다 (P0-M3 · 셀 '충실구현' L-code 누출 차단)") else ng("B4 ★QVEST_RP_NO_LCODE 미설정 — 셀이 paper_replication L-code 를 낸다")

cat("\n=== C. 계약: 워커 호출 인자 ⊆ formals · 기본값 · essence 호출이 인자를 쓴다 ===\n")
.fn_expr <- function(path, name) {
  ex <- parse(file = path, encoding = "UTF-8", keep.source = FALSE)
  hit <- Filter(function(e) is.call(e) && identical(as.character(e[[1]]), "<-") && identical(as.character(e[[2]]), name), as.list(ex))
  if (length(hit)) hit[[1]][[3]] else NULL
}
fx <- .fn_expr(RPR, "run_paper_replication")
fml <- if (!is.null(fx)) names(fx[[2]]) else character(0)
if (all(c("selection_type", "n_trials_cumulative", "measurement_tags") %in% fml)) ok("C1 run_paper_replication formals 에 selection_type · n_trials_cumulative · measurement_tags") else ng("C1 formals", paste(fml, collapse = ","))
if (!is.null(fx) && identical(fx[[2]]$selection_type, "chain") && identical(fx[[2]]$n_trials_cumulative, 1L))
  ok("C2 기본값 chain / 1L — 충실구현(선택 없는 논문 1안) 채점 비트 동일") else ng("C2 기본값이 바뀌었다 — 충실구현 등급이 달라진다")
## 워커의 run_paper_replication(...) 호출에서 이름 붙은 인자 전부가 formals 에 있는가 (미지 인자 = 실행 시 예외)
.find_calls <- function(e, fname) {
  out <- list()
  if (is.call(e)) {
    if (identical(as.character(e[[1]])[1], fname)) out <- c(out, list(e))
    for (k in as.list(e)[-1]) if (!missing(k) && !is.null(k)) out <- c(out, .find_calls(k, fname))
  }
  out
}
wex <- parse(file = WORKER, encoding = "UTF-8", keep.source = FALSE)
wcalls <- do.call(c, lapply(as.list(wex), .find_calls, fname = "run_paper_replication"))
if (length(wcalls) == 1L) {
  an <- setdiff(names(as.list(wcalls[[1]])[-1]), "")
  bad <- setdiff(an, fml)
  if (!length(bad)) ok(sprintf("C3 워커 호출 인자 %d개 전부 formals 에 존재", length(an))) else ng("C3 ★미지 인자", paste(bad, collapse = ","))
  if (all(c("selection_type", "n_trials_cumulative") %in% an)) ok("C4 워커가 selection_type · n_trials_cumulative 를 넘긴다") else ng("C4 워커가 회계를 안 넘긴다")
} else ng("C3 워커의 run_paper_replication 호출을 1개로 특정 못함", length(wcalls))
## essence_score 호출이 인자(심볼)를 쓰는가 — 리터럴이면 formals 는 장식이다("인자를 받는 함수가 그 인자를 쓰는지까지 재라")
.essence_uses_args <- function(fexpr) {
  cs <- .find_calls(fexpr[[3]], "essence_score")
  length(cs) >= 1L && all(vapply(cs, function(cl) {
    a <- as.list(cl)[-1]
    is.name(a$selection_type) && identical(as.character(a$selection_type), "selection_type") &&
      is.name(a$n_trials_cumulative) && identical(as.character(a$n_trials_cumulative), "n_trials_cumulative")
  }, logical(1)))
}
if (!is.null(fx) && .essence_uses_args(fx)) ok("C5 run_paper_replication 의 essence_score 호출이 인자 심볼을 전달") else ng("C5 ★essence 호출이 리터럴 — 인자가 무시된다")
## 위반 주입 — 구판 하드코딩을 복원한 사본은 C5 를 깨야 한다(원본 불변)
rtxt <- readLines(RPR, warn = FALSE, encoding = "UTF-8")
mtxt <- sub("essence_score(bt, n_trials_cumulative = n_trials_cumulative, selection_type = selection_type)",
            'essence_score(bt, n_trials_cumulative = 1L, selection_type = "chain")', rtxt, fixed = TRUE)
if (!identical(mtxt, rtxt)) {
  tf <- tempfile(fileext = ".R"); writeLines(mtxt, tf, useBytes = TRUE)
  mfx <- .fn_expr(tf, "run_paper_replication"); unlink(tf)
  if (!.essence_uses_args(mfx)) ok("C6 위반 주입: 구판 하드코딩 사본은 C5 에서 걸린다 (판별력 확인)") else ng("C6 판별력 없음")
} else ng("C6 돌연변이 대상 줄을 못 찾음 — 수리 줄이 바뀌었나")
if (any(grepl("measurement_regime", rtxt, fixed = TRUE)) && any(grepl('exec_price = "close_d_legacy"', rtxt, fixed = TRUE)))
  ok("C7 auth 에 measurement_regime(현행 체결 규약 close_d_legacy 정직 기록) — P0-04 전환 전 regime 식별자") else ng("C7 measurement_regime 부재")

cat("\n=== D. 원장 재도출 + 러너 배선 ===\n")
rsrc <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8"); rcode <- rsrc[!grepl("^\\s*#", rsrc)]
if (any(grepl("rf_lineage_ids(led$entries, BID)", rcode, fixed = TRUE)) &&
    any(grepl("SPEC$selection_accounting <- rf_selection_accounting(", rcode, fixed = TRUE)))
  ok("D1 러너가 정본 함수로 회계를 spec 에 싣는다") else ng("D1 러너 배선 부재")
L <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE), error = function(e) NULL)
if (is.null(L)) ng("D2 원장 읽기 실패") else {
  deep <- Filter(function(e) !is.null(e$parent$base_id), L$entries)
  if (!length(deep)) ng("D2 승격 entry 없음 — 검사 표본 부재") else {
    ns <- vapply(deep, function(e) { ii <- ge$rf_lineage_ids(L$entries, e$base_id); c(length(ii), ge$rf_lineage_measured(L$entries, ii)) }, numeric(2))
    own <- vapply(deep, function(e) ge$rf_lineage_measured(L$entries, e$base_id), numeric(1))
    if (all(ns[1, ] >= 2) && all(ns[2, ] >= own)) ok(sprintf("D2 실원장 승격 entry %d개: 계보 길이 ≥2 · 계보 N ≥ 자기 entry N (최대 계보 N = %d)", length(deep), max(ns[2, ])))
    else ng("D2 계보 N 이 자기 entry N 보다 작다 — 사슬 계수 결함")
  }
}

cat(sprintf("\nTOTAL: %d pass / %d fail\n", P, F))
cat(sprintf('{"test":"rf_selection_accounting","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
quit(save = "no", status = if (F > 0L) 1L else 0L)
