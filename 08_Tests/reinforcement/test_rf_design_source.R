#!/usr/bin/env Rscript
#==============================================================================
# test_rf_design_source.R — 칸 단위 설계 출처 도출 (P1-02 · O0a 2026-09-25 · 설계 organic_design_final §1.0(e) E3 · §0.2 사실 3)
#
#   D1 B1 가림 계약 적재 — rf_b1_design_lib.R 에서 정의 추출(복제 금지) · 교차 절·교훈 없음 머리글이 생산자 코드에 실재
#   D2 재료 노출 도출(파일별) — 교차 절 수치 잔존 = crossentry_exposed · 가림(<stat>) = masked · 교훈 없음 = own_entry ·
#      표지 없음 = unknown · 재료가 설계보다 새것 = unknown(이 설계를 낳은 재료라는 증명 없음)
#   D3 조립 지점 표식 → 출처 — grid · 격자 스냅샷(full_sample_ic) = rule_full_ic · 상주 = standing · 선정기 as-of/전표본 ·
#      카탈로그 픽커 = rule_catalog · 블록 설계 레인 = llm_exposure_unknown · B1 설계 = 재료 노출로 3분(칸 단위 — entry 단위 아님)
#   D4 [정보] 이 root 의 실제 B1 재료 전수 분류(표본이 없으면 정보 줄만 — 합격으로 세지 않는다)
#   X  돌연변이 — 수치 잔존 판정 제거 → D2 exposed 가 masked 로 = red · 머리글 계약 어긋남 → 전부 unknown = red
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
TMP <- normalizePath(tempdir(), winslash = "/")
R <- file.path(TMP, sprintf("rfds_%d", Sys.getpid())); unlink(R, recursive = TRUE, force = TRUE)
dir.create(file.path(R, "02_Infrastructure/ops"), recursive = TRUE); dir.create(file.path(R, ".cache/rf_b1_design"), recursive = TRUE)
file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), file.path(R, "02_Infrastructure/ops/rf_b1_design_lib.R"))
P <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_trial_producers.R"), envir = P)

cat("=== D1 계약 ===\n")
C1 <- P$.rftp_contract(R)
chk(isTRUE(C1$ok) && isTRUE(C1$header_ok) && is.function(C1$env$rf_b1_has_stats), "D1 가림 계약(rf_b1_has_stats·마스크) 추출 · 머리글 2종 생산자 코드에 실재", C1$why)

cat("\n=== D2 재료 노출 ===\n")
mat <- function(name, lines, age = 0) { p <- file.path(R, ".cache/rf_b1_design", name); writeLines(lines, p, useBytes = TRUE)
  if (age != 0) Sys.setFileTime(p, Sys.time() + age); p }
hdr <- P$RF_TP_XENTRY_HDR
e1 <- P$rf_design_exposure(mat("x1.materials.txt", c("## 기저", "- id", "", paste0(hdr, " (2블록)"), "### RP_Z / L-1", "- 기전: B1_1 L19 PORT_t 0.338 · Calmar 0.412", "## 규칙", "x")), R)
e2 <- P$rf_design_exposure(mat("x2.materials.txt", c("## 기저", paste0(hdr, " (2블록)"), "### RP_Z / L-1", "- 기전: B1_1 L19 PORT_t <stat> · Calmar <stat>", "## 규칙")), R)
e3 <- P$rf_design_exposure(mat("x3.materials.txt", c("## 기저", "", P$RF_TP_OWN_HDR, "## 규칙")), R)
e4 <- P$rf_design_exposure(mat("x4.materials.txt", c("## 기저", "아무 절도 없음")), R)
dj <- file.path(R, ".cache/rf_b1_design/x5.json"); writeLines("{}", dj); Sys.setFileTime(dj, Sys.time() - 3600)
e5 <- P$rf_design_exposure(mat("x5.materials.txt", c(paste0(hdr, " (1블록)"), "- 기전: <stat>")), R, design_json = dj)
chk(identical(e1$exposure, "crossentry_exposed"), "D2a 교차 절 수치 잔존(PORT_t 0.338) → crossentry_exposed", e1$exposure)
chk(identical(e2$exposure, "masked") && isTRUE(e2$n_mask >= 2L), "D2b 교차 절 가림(<stat> 2) → masked", sprintf("%s n_mask=%s", e2$exposure, e2$n_mask))
chk(identical(e3$exposure, "own_entry"), "D2c '앞선 논문 교훈: 없음' → own_entry", e3$exposure)
chk(identical(e4$exposure, "unknown") && identical(e4$why, "no_section_marker"), "D2d 표지 없음 → unknown", e4$why)
chk(identical(e5$exposure, "unknown") && identical(e5$why, "materials_newer_than_design"), "D2e 재료가 설계 json 보다 1시간 새것 → unknown(대응 증명 없음)", e5$why)
chk(identical(P$rf_design_exposure(file.path(R, "nope.txt"), R)$why, "materials_absent"), "D2f 재료 부재 → unknown(materials_absent)")

cat("\n=== D3 조립 지점 표식 → 출처 ===\n")
ds <- function(cell, bid = "BID") P$rf_cell_design_source(cell, bid, R)$design_source
file.copy(file.path(R, ".cache/rf_b1_design/x1.materials.txt"), file.path(R, ".cache/rf_b1_design/RP_EXPO.materials.txt"))
file.copy(file.path(R, ".cache/rf_b1_design/x2.materials.txt"), file.path(R, ".cache/rf_b1_design/RP_MASK.materials.txt"))
got <- c(grid = ds(list(code = "B2_6")),
         snapshot = ds(list(code = "B1_1", selection_basis = "full_sample_ic")),
         standing = ds(list(code = "B5_31", standing = TRUE)),
         f_asof = ds(list(code = "B1_2", design_origin = "rule_factor", selection_basis = "asof_ic")),
         f_full = ds(list(code = "B1_3", design_origin = "rule_factor", selection_basis = "full_sample_ic")),
         f_none = ds(list(code = "B1_4", design_origin = "rule_factor")),
         fallback = ds(list(code = "B1_5", design_origin = "rule_factor_fallback")),
         overlay = ds(list(code = "B5_16", design_origin = "rule_overlay")),
         weight = ds(list(code = "B2_7", design_origin = "rule_weight")),
         block = ds(list(code = "B3_11", design_origin = "llm_block")),
         b1_expo = ds(list(code = "B1_1", design_origin = "llm_b1"), "RP_EXPO"),
         b1_mask = ds(list(code = "B1_1", design_origin = "llm_b1"), "RP_MASK"),
         b1_none = ds(list(code = "B1_1", design_origin = "llm_b1"), "RP_NOFILE"))
want <- c(grid = "grid", snapshot = "rule_full_ic", standing = "standing", f_asof = "rule_asof", f_full = "rule_full_ic", f_none = "unknown",
          fallback = "rule_full_ic", overlay = "rule_catalog", weight = "rule_catalog", block = "llm_exposure_unknown",
          b1_expo = "llm_crossentry_exposed", b1_mask = "llm_masked", b1_none = "llm_exposure_unknown")
for (k in names(want)) chk(identical(got[[k]], want[[k]]), sprintf("D3 %s → %s", k, want[[k]]), got[[k]])
led <- new.env(); invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), envir = led)))
chk(all(unname(got) %in% led$RF_DESIGN_SOURCES), "D3b 도출 값 전부 원장 어휘(RF_DESIGN_SOURCES) 안", paste(setdiff(got, led$RF_DESIGN_SOURCES), collapse = ","))

cat("\n=== D4 [정보] 실제 B1 재료 전수 분류 ===\n")
real <- list.files(file.path(ROOT, ".cache/rf_b1_design"), pattern = "[.]materials[.]txt$", full.names = TRUE)
if (!length(real)) cat("  (정보) 이 root 에 B1 재료 표본 없음 — 분류 생략(합격으로 세지 않는다)\n") else {
  cls <- vapply(real, function(m) { j <- sub("[.]materials[.]txt$", ".json", m)
    P$rf_design_exposure(m, ROOT, design_json = if (file.exists(j)) j else NULL)$exposure }, character(1))
  tb <- table(cls); cat(sprintf("  (정보) 재료 %d건 — %s\n", length(real), paste(sprintf("%s=%d", names(tb), as.integer(tb)), collapse = " · ")))
  withj <- file.exists(sub("[.]materials[.]txt$", ".json", real))
  cat(sprintf("  (정보) 설계 json 이 있는 재료 %d건 중 crossentry_exposed %d · masked %d · own_entry %d · unknown %d\n", sum(withj),
              sum(cls[withj] == "crossentry_exposed"), sum(cls[withj] == "masked"), sum(cls[withj] == "own_entry"), sum(cls[withj] == "unknown")))
  chk(length(cls) == length(real) && all(cls %in% c("crossentry_exposed", "masked", "own_entry", "unknown")), "D4 실제 재료 전수 분류(어휘 안 · 오류 0)")
}

cat("\n=== X 돌연변이 ===\n")
P$.RFTP[[paste0("c|", R)]]$env$rf_b1_has_stats <- function(x) FALSE
x1 <- P$rf_design_exposure(file.path(R, ".cache/rf_b1_design/x1.materials.txt"), R)$exposure
rm(list = ls(P$.RFTP), envir = P$.RFTP)
chk(identical(x1, "masked"), "X1 [돌연변이] 수치 잔존 판정 제거 → 노출 재료가 masked 로 = D2a 가 이 결함을 잡는다", x1)
P$RF_TP_XENTRY_HDR <- "## 바뀐 머리글"; rm(list = ls(P$.RFTP), envir = P$.RFTP)
x2 <- P$rf_design_exposure(file.path(R, ".cache/rf_b1_design/x1.materials.txt"), R)$exposure
chk(identical(x2, "unknown"), "X2 [돌연변이] 머리글 계약 어긋남(생산자 코드에 없음) → unknown(조용한 오분류 대신) = D2a 가 이 결함을 잡는다", x2)
cat("\n=== D5 러너 조립 지점 — B1 픽 표식 자리(P1-06 통제 칸 보존 · 10-03 시스템 렌즈) ===\n")
## 러너 B1 픽커 블록(.b1_slots ~ 블록 끝)을 소스에서 추출 실행(스텁 픽커 · 쓰기 = tempdir). 통제 칸(B1 머리 · standing)은 standing 으로,
##   픽 칸만 rule_asof(픽) · rule_full_ic(폴백)로 — 시행 로그 b1_factor_pick '선택' 에 통제 칸 팩터 집합이 들면 안 된다.
RUN5 <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
src5 <- sub("\r$", "", readLines(RUN5, warn = FALSE, encoding = "UTF-8"))
i_p0 <- grep("^\\.b1_slots <- if \\(length\\(batch\\)\\) rf_batch_open_slots\\(batch\\) else integer\\(0\\)$", src5)[1]
i_pb <- grep('^if \\(length\\(batch\\) && identical\\(first\\$block, "B1"\\) && !length\\(\\.b1_design\\) && length\\(\\.b1_slots\\)\\) \\{$', src5)[1]
i_p1 <- if (is.na(i_pb)) NA_integer_ else i_pb + which(grepl("^\\}$", src5[(i_pb + 1L):length(src5)]))[1]
G5 <- new.env(parent = P)   # 생산자(P: rf_tp_fset_key 등) 위에 관문·격자 함수
g5 <- tryCatch({ for (f in c("rf_spec_sig.R", "rf_block_design.R", "rf_runner_gates.R"))
                   invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement", f), envir = G5))))
                 G5$rfbd_control_cells(ROOT) }, error = function(e) conditionMessage(e))
RC5 <- if (is.list(g5)) Filter(function(x) identical(x$control, "carry_replay"), g5) else list()
NC5 <- if (is.list(g5)) Filter(function(x) identical(x$control, "null_factor"), g5) else list()
if (anyNA(c(i_p0, i_pb, i_p1)) || !length(RC5) || !length(NC5)) {
  ng("D5 러너 B1 픽커 블록 · 통제 칸 추출 실패(P1-06 이 운영에 있는데 앵커·통제 칸이 없다)", paste(i_p0, i_pb, i_p1, if (is.character(g5)) g5 else length(RC5)))
} else {
  seg5 <- paste(src5[i_p0:i_p1], collapse = "\n")
  stub5 <- function(tag, ok_pick) {
    r0 <- file.path(TMP, sprintf("rfds5_%d_%s", Sys.getpid(), tag)); dir.create(file.path(r0, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
    writeLines(if (ok_pick) c("rf_pick_factor_sets <- function(n, exclude = character(0), seed_offset = 0L, depths = NULL, fallback_paper = NULL, root = NULL)",
      "  list(cells = lapply(seq_len(n), function(i) list(code = 'grid', label = sprintf('p%d', i), factors = list(list(kind = 'db', id = sprintf('P%d', i))),",
      "       selection_basis = 'asof_ic', selection_asof = '2005-01-01')), picked_ids = sprintf('P%d', seq_len(n)), seed_id = 's', seed_offset = 0L,",
      "       n_available = 10L, max_rho = 0, substrate_asof = 'x', excluded_no_ic = list(), excluded_axis = list())") else
      "rf_pick_factor_sets <- function(...) list(cells = list())", file.path(r0, "02_Infrastructure/ops/rf_factor_arms.R"))
    r0 }
  reg5 <- function(cd) list(code = cd, label = cd, block = "B1", axis = "multifactor", basis = "x · substrate 2026-07-31")
  run5 <- function(seg, tag, ok_pick) {
    env <- new.env(parent = G5); env$jlog <- function(event, ...) invisible(NULL)
    env$batch <- list(G5$rf_control_cell(RC5[[1]]), G5$rf_control_cell(NC5[[1]]), reg5("B1_1"), reg5("B1_2")); env$first <- env$batch[[1]]
    env$.b1_design <- list(); env$ROOT <- stub5(tag, ok_pick); env$E <- list(attempts = list()); env$led <- list(entries = list())
    env$PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE); env$.base_paper <- NULL; env$BID <- "T_DS5"
    env$.tl_try <- function(what, expr) { force(expr); TRUE }
    env$rf_tp_pick <- function(kind, base_id, picked, ...) { env$.PK <- as.character(picked); invisible(NULL) }
    err <- tryCatch({ invisible(capture.output(eval(parse(text = seg), envir = env))); NULL }, error = function(e) conditionMessage(e))
    list(err = err, ds = vapply(env$batch, function(c) P$rf_cell_design_source(c, "T_DS5", R)$design_source, character(1)), pk = env$.PK %||% character(0))
  }
  a5 <- run5(seg5, "pick", TRUE); b5 <- run5(seg5, "fb", FALSE)
  chk(is.null(a5$err) && identical(a5$ds, c("standing", "standing", "rule_asof", "rule_asof")) && identical(sort(a5$pk), c("P1", "P2")),
      "D5a as-of 픽 — 통제 칸 2 = standing · 픽 칸 2 = rule_asof · 시행 로그 선택 = 픽 칸 집합(P1·P2)",
      paste(a5$err %||% "", paste(a5$ds, collapse = ","), "|", paste(a5$pk, collapse = ",")))
  chk(is.null(b5$err) && identical(b5$ds, c("standing", "standing", "rule_full_ic", "rule_full_ic")) && length(b5$pk) == 2L,
      "D5b 픽커 폴백 — 통제 칸 2 = standing · 정규 칸 2 = rule_full_ic · 선택에 통제 칸 없음",
      paste(b5$err %||% "", paste(b5$ds, collapse = ","), "|", paste(b5$pk, collapse = ",")))
  m3 <- sub('if (exists(".b1_slots", inherits = FALSE)) .b1_slots else seq_along(batch)', "seq_along(batch)", seg5, fixed = TRUE)
  m4 <- sub('if (!isTRUE(c$standing)) c$design_origin <- "rule_factor_fallback"', 'c$design_origin <- "rule_factor_fallback"', seg5, fixed = TRUE)
  x3 <- if (identical(m3, seg5)) NULL else run5(m3, "m3", TRUE)
  x4 <- if (identical(m4, seg5)) NULL else run5(m4, "m4", FALSE)
  chk(!is.null(x3) && !identical(x3$ds, a5$ds) && identical(x3$ds[1], "unknown"),
      "X3 [돌연변이] 픽 표식을 위치 1..n 으로(CTRL 이전 가정) → 통제 칸 unknown · 픽 칸 grid = D5a 가 잡는다", if (is.null(x3)) "앵커 부재" else paste(x3$ds, collapse = ","))
  chk(!is.null(x4) && identical(x4$ds[1], "rule_full_ic"),
      "X4 [돌연변이] 폴백 표식이 통제 칸까지 → 통제 칸 rule_full_ic = D5b 가 잡는다", if (is.null(x4)) "앵커 부재" else paste(x4$ds, collapse = ","))
  unlink(Sys.glob(file.path(TMP, sprintf("rfds5_%d_*", Sys.getpid()))), recursive = TRUE, force = TRUE)
}
cat("\n=== D6 승자·바닥 기록 — P1-06 통제 칸 기각 사유(10-03 시스템 렌즈) ===\n")
## 통제 칸은 c0→c1 에서 rf_candidates_keep(control_cell)로 빠진다 — 시행 로그 사유가 '규약 자격 미달' 이면 오기(append-only 영구 기록).
CTL6 <- if (exists("G5") && is.function(G5$rf_control_codes)) tryCatch(as.character(unlist(G5$rf_control_codes(ROOT))), error = function(e) character(0)) else character(0)
if (length(CTL6) < 2L) ng("D6 통제 칸 코드 2개 이상 필요(P1-06 격자 standing_cells[control])", length(CTL6)) else {
  P6 <- new.env(parent = G5); invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_trial_producers.R"), envir = P6)))
  CAP6 <- NULL
  P6$rf_record_trial_decision <- function(kind, base_id, candidates, chosen, rule, scope = list(), cells = list(), root) {
    CAP6 <<- candidates; list(decision = list(decision_id = "t6")) }
  rs6 <- function() setNames(vapply(CAP6, function(c) as.character(c$reason %||% ""), ""), vapply(CAP6, function(c) as.character(c$id), ""))
  nt6 <- list(c0 = c(CTL6[1:2], "B1_3", "B1_4", "B1_5"), c1 = c("B1_4", "B1_5"), c2 = "B1_5", chosen = "B1_5", vals = c(1.1, 2.2), vcodes = c("B1_4", "B1_5"), by = "port_t")
  P6$rf_tp_winner("T6", "B1", nt6, "B2", ROOT); w6 <- rs6()
  P6$rf_tp_floor("T6", nt6, "attempt", "B1_5", "", "B2", ROOT); f6 <- rs6()
  WHY6 <- "통제 칸(P1-06 · 선정 후보 아님)"   # 리터럴 대조 — 생산자 상수와 비교하면 상수 부재(구판)에서 all(logical(0)) = 공허 통과
  chk(identical(unname(w6[CTL6[1:2]]), rep(WHY6, 2L)) && identical(unname(w6["B1_3"]), "후보 자격 미달(규약)") && identical(unname(w6["B1_5"]), ""),
      "D6a 승자 기록 — 통제 칸 = '통제 칸(P1-06)' · 일반 c0 탈락 = 규약 · 승자 사유 없음", paste(names(w6), w6, sep = "=", collapse = " | "))
  chk(identical(unname(f6[CTL6[1:2]]), rep(WHY6, 2L)) && identical(unname(f6["B1_3"]), "바닥 자격 미달(규약·유니버스·창)"),
      "D6b 바닥 기록 — 통제 칸 = '통제 칸(P1-06)' · 일반 탈락 = 바닥 자격", paste(names(f6), f6, sep = "=", collapse = " | "))
  had5 <- exists(".rftp_control_codes", envir = P6, inherits = FALSE)   # 돌연변이 대상이 실재해야 X5 가 의미 있다
  P6$.rftp_control_codes <- function(root) character(0)
  P6$rf_tp_winner("T6", "B1", nt6, "B2", ROOT); x5 <- rs6()
  chk(had5 && identical(unname(x5[CTL6[1]]), "후보 자격 미달(규약)"), "X5 [돌연변이] 통제 코드 집합 비움 → 통제 칸이 규약 탈락으로 = D6a 가 잡는다", paste(names(x5), x5, sep = "=", collapse = " | "))
}
unlink(R, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_design_source","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
