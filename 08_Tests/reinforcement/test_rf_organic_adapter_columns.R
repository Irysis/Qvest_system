#!/usr/bin/env Rscript
#==============================================================================
# test_rf_organic_adapter_columns.R — 원장 투영 어댑터 열 허용목록 (O0a · 2026-09-25 · 설계 organic_design_final §1.0(d) · §3 G2)
#
#   P1 [양성] 투영 열 = config organic.view.columns 와 **정확히 같다**(순서 포함) · 행 = 원장 등록 칸 전수 · 결정론(정규형 2회 동일)
#   P2 사실 투영 — 블록 = 격자 코드 접두(essence$block 아님) · 상속·측정·종결·무처치 = 불리언 · 규약 사실 = 관문 술어 · 뿌리 계보
#   P3 연구 시점 r — closed_at < r 인 칸만(미측정 칸 제외)
#   P4 값 누출 0 — 투영 표 어디에도 전기간 지표 값(port_t·calmar 픽스처 값)이 나타나지 않는다
#   F  fail-closed — 허용목록에 금지 열(calmar·grade·oos_retention·essence_*) → stop · 모르는 열 → stop · 허용목록 부재 → stop
#   X  돌연변이 — 어댑터가 calmar 열을 덧붙이고 내부 대조를 지운 판 → P1(열 집합 = 허용목록) 단정이 red
#   S  정적 봉쇄 — 어댑터(adapter 역할) 통과 · 같은 코드를 decision 역할로 보면 적발(원장 판독 = 이 파일만의 면제)
# 격리: 임시 root · 운영 원장 md5 불변.
#==============================================================================
suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
err_of <- function(expr) tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
REAL <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"); real_md5 <- unname(tools::md5sum(REAL))
TMP <- normalizePath(tempdir(), winslash = "/")
CUR <- as.character(fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$execution$exec_price)
mk_root <- function(tag) {
  d <- file.path(TMP, sprintf("rfoa_%s_%d", tag, Sys.getpid())); unlink(d, recursive = TRUE, force = TRUE)
  for (s in c("02_Infrastructure/reinforcement", "02_Infrastructure/worktask", "02_Infrastructure/contracts", "06_Registry", "arts", "specs"))
    dir.create(file.path(d, s), recursive = TRUE, showWarnings = FALSE)
  for (f in c("02_Infrastructure/config.R", "02_Infrastructure/worktask/constraint_defaults.json", "06_Registry/reinforce_auto_config.json",
              "02_Infrastructure/contracts/essence_score.R", "06_Registry/a_eligibility_gate.json", "06_Registry/pit_quarantine.json"))
    file.copy(file.path(ROOT, f), file.path(d, f))
  for (f in c("reinforce_ledger.R", "rf_spec_sig.R", "rf_runner_gates.R", "rf_lineage_flags.R", "rf_organic_ledger_adapter.R", "rf_organic_guard.R"))
    file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(d, "02_Infrastructure/reinforcement", f))
  att <- function(bid, n, code, measured = TRUE, closed = "2026-09-20T10:00:00+0900", extra = list(), spec = list()) {
    art <- file.path(d, "arts", sprintf("%s_%d", bid, n)); dir.create(art, showWarnings = FALSE)
    writeLines(toJSON(list(essence_grade = "C", measurement_regime = list(exec_price = CUR)), auto_unbox = TRUE), file.path(art, "authoritative_remeasure.json"))
    sp <- file.path(d, "specs", sprintf("%s_%d.json", bid, n))
    s <- list(code = code, factors = list(list(kind = "db", id = "F1"), list(kind = "db", id = "F2")), weighting = list(kind = "catalog", catalog_id = "qepm:hrp"),
              universe = list(kind = "k200_kq150"), overlay_cell = list(), floor_code = "B1_3")
    for (k in names(spec)) s[[k]] <- spec[[k]]
    writeLines(toJSON(s, auto_unbox = TRUE), sp)
    a <- list(n = n, cell_code = code, grade = if (measured) "C" else NA, artifacts = art, closed_at = if (measured) closed else NULL,
              essence = if (measured) list(cell_code = code, block = "B9", port_t = 1.2345 + n, calmar = 0.4321, oos_retention = 0.5555,
                                           window_deviation_months = 0, spec = sp) else NULL)
    for (k in names(extra)) a[[k]] <- extra[[k]]
    a
  }
  e1 <- list(base_id = "RP_A", status = "exhausted", attempts = list(
    att("RP_A", 1, "B1_1", extra = list(design = list(design_source = "rule_asof", design_lane = "rule_factor"))),
    att("RP_A", 2, "B2_6", closed = "2026-09-22T10:00:00+0900", extra = list(vintage_flags = list(list(flag = "pit_c11", verdict = "consumed")))),
    att("RP_A", 3, "B4_21", extra = list(terminal = TRUE, terminal_reason = "스펙 중복(B2_6) — 측정 생략, 결과 승계")),
    att("RP_A", 4, "B3_12", measured = FALSE, extra = list(terminal = TRUE, terminal_reason = "무처치(carry 동일) — factors=…"))))
  e1$attempts[[3]]$essence$inherited_from <- "B2_6"
  e2 <- list(base_id = "RP_A_promo1", status = "active", parent = list(base_id = "RP_A", depth = 1L),
             attempts = list(att("RP_A_promo1", 1, "B5_16", spec = list(overlay_cell = list(list(kind = "arm", arm_id = "ov_a"))))))
  writeLines(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 35L, entries = list(e1, e2)), auto_unbox = TRUE, pretty = TRUE, null = "null"),
             file.path(d, "06_Registry/reinforce_ledger_l1.json"))
  normalizePath(d, winslash = "/")
}
R <- mk_root("p")
A <- new.env(); sys.source(file.path(R, "02_Infrastructure/reinforcement/rf_organic_ledger_adapter.R"), envir = A)
cols <- as.character(unlist(fromJSON(file.path(R, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)$organic$view$columns))

cat("=== P 양성 ===\n")
df <- A$rfo_project(R)
chk(length(cols) >= 10L && identical(names(df), cols), "P1a 투영 열 = config organic.view.columns(순서 포함)", paste(setdiff(names(df), cols), collapse = ","))
chk(nrow(df) == 5L && identical(df$cell_key, c("RP_A#1", "RP_A#2", "RP_A#3", "RP_A#4", "RP_A_promo1#1")), "P1b 행 = 등록 칸 5 · 결정론 정렬(base_id, n)", paste(df$cell_key, collapse = ","))
chk(identical(A$rfo_project_canonical(A$rfo_project(R)), A$rfo_project_canonical(df)), "P1c 정규형 2회 동일(결정론 · view_md5 입력)")
chk(identical(df$block, c("B1", "B2", "B4", "B3", "B5")), "P2a 블록 = 격자 코드 접두(essence$block 'B9' 아님)", paste(df$block, collapse = ","))
chk(identical(df$inherited, c(FALSE, FALSE, TRUE, FALSE, FALSE)) && identical(df$measured, c(TRUE, TRUE, TRUE, FALSE, TRUE)) &&
      identical(df$cell_no_treatment, c(FALSE, FALSE, FALSE, TRUE, FALSE)) && identical(df$terminal, c(FALSE, FALSE, TRUE, TRUE, FALSE)),
    "P2b 상속·측정·무처치·종결 = 불리언 투영")
chk(identical(df$design_source, c("rule_asof", "unknown", "unknown", "unknown", "unknown")) && identical(df$flags[2], "pit_c11") &&
      all(df$regime_ok[df$measured]) && identical(df$root_lineage[5], "RP_A") && identical(df$parent_chain[5], "RP_A_promo1>RP_A"),
    "P2c 설계 출처(원장 attempt$design · 없으면 unknown) · 표식 · 규약 사실(관문 술어) · 뿌리 계보")
dr <- A$rfo_project(R, r = "2026-09-21T00:00:00+0900")
chk(identical(dr$cell_key, c("RP_A#1", "RP_A#3", "RP_A_promo1#1")), "P3 r=09-21 → closed_at < r 인 측정 칸만(09-22 칸·미측정 칸 제외)", paste(dr$cell_key, collapse = ","))
txt <- A$rfo_project_canonical(df)
chk(!grepl("1.2345|2.2345|0.4321|0.5555", txt), "P4 투영 표에 전기간 지표 값(port_t·calmar·retention 픽스처) 0")

cat("\n=== F fail-closed ===\n")
cfgp <- file.path(R, "06_Registry/reinforce_auto_config.json"); cfg0 <- readLines(cfgp, warn = FALSE, encoding = "UTF-8")
setcols <- function(v) { j <- fromJSON(cfgp, simplifyVector = FALSE); j$organic$view$columns <- as.list(v); writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), cfgp) }
for (bad in c("calmar", "grade", "oos_retention", "essence_port_t")) { setcols(c(cols, bad))
  m <- err_of(A$rfo_project(R)); chk(!is.na(m) && grepl("금지 열", m), sprintf("F1 허용목록에 %s → stop", bad), m) }
setcols(c(cols, "foo")); m <- err_of(A$rfo_project(R)); chk(!is.na(m) && grepl("모르는 열", m), "F2 모르는 열 → stop", m)
j <- fromJSON(cfgp, simplifyVector = FALSE); j$organic$view <- NULL; writeLines(toJSON(j, auto_unbox = TRUE, pretty = TRUE, null = "null"), cfgp)
m <- err_of(A$rfo_project(R)); chk(!is.na(m) && grepl("부재", m), "F3 허용목록 부재 → stop(fail-closed)", m)
writeLines(cfg0, cfgp, useBytes = TRUE)

cat("\n=== X 돌연변이 ===\n")
src <- deparse(A$rfo_project, width.cutoff = 500L)
m1 <- sub('if (!identical(names(df), cols))', 'df$calmar <- 0.4321; if (FALSE)', src, fixed = TRUE)   # ASCII 조각만(deparse 가 한글을 이스케이프할 수 있다)
if (sum(src != m1) != 1L) ng("X1 돌연변이 주입 실패") else {
  g <- eval(parse(text = m1)); environment(g) <- environment(A$rfo_project)
  dm <- g(R)
  chk(!identical(names(dm), cols) && "calmar" %in% names(dm), "X1 [돌연변이] calmar 열 덧붙임 + 내부 대조 제거 → 열 집합 ≠ 허용목록 = P1a 가 이 결함을 잡는다")
}

cat("\n=== S 정적 봉쇄 ===\n")
G <- new.env(); sys.source(file.path(R, "02_Infrastructure/reinforcement/rf_organic_guard.R"), envir = G)
fa <- file.path(R, "02_Infrastructure/reinforcement/rf_organic_ledger_adapter.R")
sa <- G$rfo_static_scan(fa, "adapter"); sd <- G$rfo_static_scan(fa, "decision")
chk(isTRUE(sa$ok), "S1 어댑터(adapter 역할) 정적 봉쇄 통과(쓰기 0 · 동적 평가 0)", paste(apply(sa$violations, 1, paste, collapse = ":"), collapse = " | "))
chk(!sd$ok && any(sd$violations$kind %in% c("g2_token", "g2_string")), "S2 같은 코드를 decision 역할로 보면 원장 판독 토큰 적발 — 면제는 어댑터 하나뿐")
chk(identical(unname(tools::md5sum(REAL)), real_md5), "Z1 운영 원장 md5 불변")
unlink(R, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_organic_adapter_columns","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
