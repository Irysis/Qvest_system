# test_lcode_cell_relabel.R — 강화 셀 L-code 재라벨 계약 (2026-09-23 · 플랜 P0-M3 후반 · 감사 D6-03)
#
# 사건: 강화 셀 워커(rf_cell_worker.R → run_paper_replication)가 셀마다 mode="paper_replication"
#   '충실구현' L-code 를 발행했다. stage_artifacts/l_code/paper_replication/ 1,172건 중 1,106건이 셀
#   (lesson_text 'RF_PAR_' 접두 또는 '[무인 병렬' 포함)이고 진짜 충실구현은 66건이었다
#   → corpus 의 'paper_replication' 57% · hypothesis_index 40% 가 셀. 셀은 strategy_id(RP_*)·l_code(L-RP-*)가
#   충실구현과 같은 모양이라 조회면에서 구분되지 않았다.
# 조치(도훈 승인 '삭제 없음'): 제자리 필드 재라벨 research_mode="reinforcement_cell"
#   + relabeled_from/relabeled_at/relabel_reason. 원 필드(tags·created_by·lesson_text·l_code) 불변.
#
# 이 검사가 지키는 것 (네 축):
#   A. 원장 불변식 — 디렉터리의 셀은 전부 reinforcement_cell · 비셀은 전부 paper_replication(재라벨 흔적 없음)
#      · 재라벨 수는 1,106 아래로 줄지 않는다(삭제 없음) · 원 필드 보존. + 검출 술어 위반 주입.
#   B. 스키마 — reinforcement_cell 이 enum 에 있다(없으면 validate_lcode 가 정정 기록을 '비표준'으로 뒤집는다).
#   C. 소비자 — **소비자의 함수로** 잰다(데이터 재독이 아니라): 샌드박스에서 harvester 를 돌려
#      필드가 디렉터리를 이기는지 · positive_context 최근교훈이 셀을 빼는지 · hypothesis_index 가
#      모드를 행에 싣는지(보충 스캔 경로 + corpus 경로 둘 다). 누출 픽스처가 그대로 보이는 것이 양성 대조다.
#   D. 앞으로의 누출 가드 — rf_cell_worker.R 이 최상위에서 QVEST_RP_NO_LCODE="1" 을 호출 **전에** 켜는지,
#      run_paper_replication.R 이 그 스위치로 emit_lcode(mode="paper_replication") 를 else 가지에 가두는지
#      **파스 트리에서 재도출**한다(주석·문자열 grep 아님). 돌연변이 4종(삭제·주석화·if(FALSE)·환경변수명 변조)이
#      전부 빨강이어야 계기로 센다.
#
# 격리: 쓰기는 tempfile() 샌드박스에만. 생산 트리는 읽기만 한다(A·B·D).
# 실행: Rscript 08_Tests/axiom/test_lcode_cell_relabel.R

suppressPackageStartupMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi = "") { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"lcode_cell_relabel","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":[', paste(vapply(SKIPS, function(s)
    sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, gsub('"', "'", s$reason), s$missing),
    character(1)), collapse = ","), "]")
  cat(paste0(j, "}\n")); quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

# ── 루트: --file 기준 + marker 검증 (r-portability ③) ─────────────────────────────
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
.marker <- "02_Infrastructure/hooks/qvest_hook_router.py"
ROOT <- NA_character_
for (cand in c(file.path(.self, "..", ".."), Sys.getenv("QM_ROOT", ""))) {
  if (!nzchar(cand)) next
  # 정규화를 검사보다 먼저(r-portability ③). '..' 를 접어 두지 않으면 긴 루트에서 파일 경로가 MAX_PATH(260)를
  #   넘어 fromJSON 이 파일명 긴 것만 골라 실패한다(돌연변이 샌드박스에서 실측 — 파싱 실패로 위장).
  cand <- normalizePath(cand, winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, .marker))) { ROOT <- cand; break }
  message(sprintf("[test_lcode_cell_relabel] 루트 후보 기각(marker 부재): %s", cand))
}
if (is.na(ROOT)) { sk("root", "프로젝트 루트 marker 미충족", .marker); emit() }

LC_DIR  <- file.path(ROOT, "stage_artifacts", "l_code", "paper_replication")
SCH     <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_schema.R")
HARV    <- file.path(ROOT, "02_Infrastructure", "axiom", "lcode_harvester.py")
HI      <- file.path(ROOT, "02_Infrastructure", "tools", "hypothesis_index.R")
WORKER  <- file.path(ROOT, "02_Infrastructure", "ops", "rf_cell_worker.R")
RPR     <- file.path(ROOT, "02_Infrastructure", "alpha_search", "run_paper_replication.R")

NEW_MODE <- "reinforcement_cell"; OLD_MODE <- "paper_replication"
N_RELABELED_FLOOR <- 1106L   # 2026-09-23 재라벨 실적(매니페스트). '삭제 없음' — 이 아래로 줄면 기록이 사라진 것이다
N_FAITHFUL_FLOOR  <- 66L     # 같은 날 비셀(충실구현) 실측. 새 충실구현은 늘 수 있으므로 하한만 건다

# 샌드박스 정리 — 최상위 on.exit 은 no-op 이라(r-portability ②) finalizer 로 건다
SB <- gsub("\\\\", "/", tempfile("lcrl_"))
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE, force = TRUE), onexit = TRUE))

# ── 검출 술어 (생산 디렉터리와 위반 주입 픽스처에 **같은 함수**를 쓴다) ─────────────
.is_cell_text <- function(lt) {
  lt <- as.character(lt %||% "")[1]; if (is.na(lt)) lt <- ""
  startsWith(lt, "RF_PAR_") || grepl("[무인 병렬", lt, fixed = TRUE)
}
.scan <- function(dir) {
  fs <- sort(list.files(dir, pattern = "^l_code_.*\\.json$", full.names = TRUE))
  rows <- lapply(fs, function(f) {
    # 일시적 파일 잠금(동기화·백신)에 한 번 실패한 것을 판정으로 굳히지 않도록 짧게 3회까지 다시 읽는다.
    d <- NULL
    for (k in 1:3) {
      d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(d)) break
      Sys.sleep(0.3)
    }
    if (is.null(d)) return(data.frame(path = basename(f), parse_ok = FALSE, is_cell = NA, mode = NA_character_,
                                      relabeled_from = NA_character_, relabeled_at = NA_character_,
                                      reason = NA_character_, created_by = NA_character_, stringsAsFactors = FALSE))
    data.frame(path = basename(f), parse_ok = TRUE, is_cell = .is_cell_text(d$lesson_text),
               mode = as.character(d$research_mode %||% NA_character_)[1],
               relabeled_from = as.character(d$relabeled_from %||% NA_character_)[1],
               relabeled_at = as.character(d$relabeled_at %||% NA_character_)[1],
               reason = as.character(d$relabel_reason %||% NA_character_)[1],
               created_by = as.character(d$created_by %||% NA_character_)[1],
               stringsAsFactors = FALSE)
  })
  if (!length(rows)) return(NULL)
  do.call(rbind, rows)
}
.leaks <- function(sc) sc$path[sc$parse_ok & sc$is_cell & !(sc$mode %in% NEW_MODE)]
.faithful_violations <- function(sc) sc$path[sc$parse_ok & !sc$is_cell &
                                               (!(sc$mode %in% OLD_MODE) | !is.na(sc$relabeled_from))]

# ══ A. 원장 불변식 (생산 디렉터리 — 읽기만) ═══════════════════════════════════════
cat("\n── A. 원장 불변식 (stage_artifacts/l_code/paper_replication) ──\n")
if (!dir.exists(LC_DIR)) sk("A_ledger", "디렉터리 부재", LC_DIR) else {
  sc <- .scan(LC_DIR)
  if (is.null(sc)) ng("A0 디렉터리가 비었다", LC_DIR) else {
    if (all(sc$parse_ok)) ok(sprintf("A0 %d파일 전부 파싱", nrow(sc))) else
      ng("A0 파싱 실패 파일", paste(head(sc$path[!sc$parse_ok], 5), collapse = ","))
    lk <- .leaks(sc)
    if (!length(lk)) ok(sprintf("A1 셀 %d건 전부 %s — paper_replication 으로 남은 셀 0", sum(sc$is_cell, na.rm = TRUE), NEW_MODE)) else
      ng(sprintf("★A1 셀이 paper_replication 으로 남았다(누출 또는 재라벨 누락) %d건", length(lk)),
         paste(head(lk, 5), collapse = ","))
    rl <- sc[sc$parse_ok & sc$is_cell & sc$mode %in% NEW_MODE, ]
    if (nrow(rl) >= N_RELABELED_FLOOR) ok(sprintf("A2 재라벨 셀 %d건 ≥ %d (삭제 없음)", nrow(rl), N_RELABELED_FLOOR)) else
      ng("★A2 재라벨 셀 수가 실적 아래로 줄었다 — 기록 삭제 의심", sprintf("%d < %d", nrow(rl), N_RELABELED_FLOOR))
    trace_bad <- rl$path[!(rl$relabeled_from %in% OLD_MODE) | is.na(rl$relabeled_at) | !nzchar(rl$reason %||% "") | is.na(rl$reason)]
    if (!length(trace_bad)) ok("A3 재라벨 흔적 3필드(relabeled_from=paper_replication · at · reason) 전건") else
      ng("★A3 재라벨 흔적 결손", paste(head(trace_bad, 5), collapse = ","))
    # 제자리 필드 재라벨이면 발행 당시 created_by 가 그대로다 — 다시 쓴 기록이면 이 값이 바뀐다
    cb_bad <- rl$path[!(rl$created_by %in% "emit:paper_replication")]
    if (!length(cb_bad)) ok("A4 원 필드 보존 — 재라벨 셀 created_by 가 발행 당시 값(emit:paper_replication) 그대로") else
      ng("★A4 원 필드가 바뀌었다(재라벨이 필드 한정이 아니다)", paste(head(cb_bad, 5), collapse = ","))
    nf <- sum(sc$parse_ok & !sc$is_cell)
    fv <- .faithful_violations(sc)
    if (nf >= N_FAITHFUL_FLOOR && !length(fv))
      ok(sprintf("A5 충실구현 %d건(≥%d) 전부 paper_replication · 재라벨 흔적 0 — 비대상 불변", nf, N_FAITHFUL_FLOOR)) else
      ng("★A5 충실구현이 건드려졌다", sprintf("n=%d · 위반=%s", nf, paste(head(fv, 5), collapse = ",")))
  }
}

# ── 픽스처 (위반 주입 · 소비자 샌드박스 공용) ────────────────────────────────────
.fx <- function(l_code, sid, lesson, mode, grade, relabel = FALSE) {
  d <- list(l_code = l_code, strategy_id = sid, grade = grade, core_reference = "",
            lesson_text = lesson, tags = "PAPER_REPLICATION", created_at = "2026-09-23",
            research_mode = mode)
  if (relabel) d <- c(d, list(relabeled_from = OLD_MODE, relabeled_at = "2026-09-23",
                              relabel_reason = "픽스처 — 재라벨된 셀"))
  c(d, list(created_by = "emit:paper_replication", metric_type = "backtested",
            construction_type = "single_factor_long_only", lcode_schema_version = 3L,
            selection_type = "chain", next_probes = list("픽스처 다음 1", "픽스처 다음 2"),
            record_type = "performance"))
}
FX <- list(
  cell  = .fx("L-RP-FX_CELL",  "RP_FX_CELL",  "RF_PAR_B9_99_FX 충실구현: 등급 C. [무인 병렬 B9_99] 재라벨된 셀 픽스처", NEW_MODE, "C", TRUE),
  faith = .fx("L-RP-FX_FAITH", "RP_FX_FAITH", "FX_Paper_LS 충실구현: 등급 F. 논문 그대로 픽스처", OLD_MODE, "F"),
  leak  = .fx("L-RP-FX_LEAK",  "RP_FX_LEAK",  "RF_PAR_B9_98_FX 충실구현: 등급 B. [무인 병렬 B9_98] 누출(미재라벨) 픽스처", OLD_MODE, "B")
)
.write_fx <- function(dir, fx) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (nm in names(fx))
    writeLines(toJSON(fx[[nm]], auto_unbox = TRUE, pretty = TRUE), file.path(dir, sprintf("l_code_FX_%s.json", nm)),
               useBytes = TRUE)
}

cat("\n── A'. 위반 주입 — 검출 술어가 실제로 발화하는가 ──\n")
INJ <- file.path(SB, "inject", "paper_replication")
.write_fx(INJ, FX)
sci <- .scan(INJ)
lki <- .leaks(sci)
if (identical(lki, "l_code_FX_leak.json")) ok("A6 누출 셀(RF_PAR_ · paper_replication) 주입 → A1 술어가 정확히 그 1건을 잡는다") else
  ng("★A6 주입한 누출을 못 잡았다(또는 오탐)", paste(lki, collapse = ","))
# 충실구현을 잘못 재라벨한 경우 (셀 판정 술어가 너무 넓어져 충실구현을 먹는 회귀)
fx_bad <- FX["faith"]; fx_bad$faith$research_mode <- NEW_MODE; fx_bad$faith$relabeled_from <- OLD_MODE
INJ2 <- file.path(SB, "inject2", "paper_replication"); .write_fx(INJ2, fx_bad)
fv2 <- .faithful_violations(.scan(INJ2))
if (length(fv2) == 1L) ok("A7 충실구현 오재라벨 주입 → A5 술어가 잡는다") else
  ng("★A7 충실구현 오재라벨을 못 잡았다", paste(fv2, collapse = ","))

# ══ B. 스키마 enum ═══════════════════════════════════════════════════════════════
cat("\n── B. 스키마 (lcode_schema.R) ──\n")
e <- new.env(parent = globalenv())
loaded <- file.exists(SCH) && tryCatch({ suppressMessages(sys.source(SCH, envir = e)); TRUE },
                                       error = function(x) { ng("B0 lcode_schema 로드", conditionMessage(x)); FALSE })
if (!loaded) sk("B_schema", "schema 미로드", SCH) else {
  if (NEW_MODE %in% e$LCODE_VALID_MODES) ok("B1 reinforcement_cell ∈ LCODE_VALID_MODES") else
    ng("★B1 enum 에 없다 — validate_lcode 가 정정 기록을 비표준으로 뒤집는다")
  if (OLD_MODE %in% e$LCODE_VALID_MODES) ok("B2 paper_replication 존치(충실구현 66건 · 신규 발행)") else
    ng("★B2 paper_replication 이 enum 에서 빠졌다")
  if (exists("sc") && !is.null(sc)) {
    rl_paths <- file.path(LC_DIR, sc$path[sc$parse_ok & sc$is_cell & sc$mode %in% NEW_MODE])
    mode_err <- 0L
    for (p in rl_paths) {
      d <- fromJSON(p, simplifyVector = FALSE)
      v <- e$validate_lcode(d)
      if (any(grepl("research_mode", v$errors, fixed = TRUE))) mode_err <- mode_err + 1L
    }
    if (length(rl_paths) && mode_err == 0L) ok(sprintf("B3 재라벨 실물 %d건 validate_lcode research_mode 오류 0", length(rl_paths))) else
      ng("★B3 재라벨 실물이 research_mode 로 거부된다", sprintf("%d/%d", mode_err, length(rl_paths)))
  }
  # 음성 대조: enum 검사가 살아 있는가 (비표준 값은 여전히 거부)
  bad <- e$validate_lcode(modifyList(FX$cell, list(research_mode = "reinforcement_cellX")))
  if (any(grepl("research_mode='reinforcement_cellX'", bad$errors, fixed = TRUE)))
    ok("B4 음성 대조 — 비표준 모드(reinforcement_cellX)는 여전히 거부") else
    ng("★B4 enum 검사가 죽었다(아무 값이나 통과)", paste(bad$errors, collapse = "; "))
}

# ══ C. 소비자 — 샌드박스에서 실제 소비 함수로 잰다 ════════════════════════════════
cat("\n── C. 소비자 (harvester · positive_context · hypothesis_index — 샌드박스) ──\n")
PY <- ""
for (cand in c(Sys.getenv("QVEST_PY_BIN", ""), Sys.getenv("QVEST_PY", ""),
               file.path(ROOT, ".venv_qvest_ml", "Scripts", "python.exe")))
  if (nzchar(cand) && file.exists(cand)) { PY <- cand; break }
SBP <- file.path(SB, "proj")
.write_fx(file.path(SBP, "stage_artifacts", "l_code", "paper_replication"), FX)

# C3a — hypothesis_index 보충 스캔 경로(corpus 부재 → 원본 직접 파싱)
hi_env <- new.env(parent = globalenv())
hi_loaded <- file.exists(HI) && tryCatch({ suppressMessages(sys.source(HI, envir = hi_env)); TRUE },
                                         error = function(x) { ng("C0 hypothesis_index 로드", conditionMessage(x)); FALSE })
.hi_modes <- function(out_path) {
  idx <- fromJSON(out_path, simplifyVector = FALSE)
  m <- list()
  for (en in idx$entries) m[[en$strategy_id]] <- list(mode = en$research_mode %||% NA_character_,
                                                     row_mode = hi_env$.hi_row(en)$research_mode,
                                                     src = paste(unlist(en$source_types), collapse = ","))
  m
}
.check_hi <- function(tag, m, want_src) {
  got <- vapply(c("RP_FX_CELL", "RP_FX_FAITH", "RP_FX_LEAK"), function(s) as.character(m[[s]]$mode %||% NA)[1], "")
  rowm <- vapply(c("RP_FX_CELL", "RP_FX_FAITH"), function(s) as.character(m[[s]]$row_mode %||% NA)[1], "")
  src_ok <- all(vapply(c("RP_FX_CELL", "RP_FX_FAITH"), function(s) grepl(want_src, m[[s]]$src %||% ""), TRUE))
  exp <- c(RP_FX_CELL = NEW_MODE, RP_FX_FAITH = OLD_MODE, RP_FX_LEAK = OLD_MODE)
  if (identical(unname(got), unname(exp)) && identical(unname(rowm), unname(exp[1:2])) && src_ok)
    ok(sprintf("%s 셀 행=%s · 충실구현 행=%s · 누출 픽스처=%s(양성 대조) · lookup 행에도 모드 · 원천=%s",
               tag, got[1], got[2], got[3], want_src)) else
    ng(sprintf("★%s hypothesis_index 가 모드를 행에 싣지 않는다", tag),
       sprintf("got=%s row=%s src_ok=%s", paste(got, collapse = "/"), paste(rowm, collapse = "/"), src_ok))
}
if (!hi_loaded) sk("C3_hi", "hypothesis_index.R 미로드", HI) else {
  o1 <- file.path(SB, "hi_supplement.json")
  r1 <- tryCatch({ hi_env$build_hypothesis_index(root = SBP, out_path = o1, verbose = FALSE); TRUE },
                 error = function(x) { ng("C3a 샌드박스 빌드 실패", conditionMessage(x)); FALSE })
  if (isTRUE(r1)) .check_hi("C3a(보충 스캔)", .hi_modes(o1), "lcode_supplement")
}

if (!nzchar(PY)) {
  sk("C1_C2_C3b", "python 실행기 부재 — QVEST_PY_BIN/QVEST_PY/.venv_qvest_ml", "python.exe")
} else if (!file.exists(HARV)) {
  sk("C1_C2_C3b", "harvester 부재", HARV)
} else {
  run_harvest <- function() {
    old <- Sys.getenv("PYTHONUTF8", unset = NA)
    Sys.setenv(PYTHONUTF8 = "1")   # system2(env=) 금지(r-portability ①) — setenv + 복원
    on.exit({ if (is.na(old)) Sys.unsetenv("PYTHONUTF8") else Sys.setenv(PYTHONUTF8 = old) }, add = TRUE)
    out <- suppressWarnings(system2(PY, c(shQuote(HARV), "--project-dir", shQuote(SBP)), stdout = TRUE, stderr = TRUE))
    list(rc = attr(out, "status") %||% 0L, out = out)
  }
  hv <- run_harvest()
  cp <- file.path(SBP, ".cache", "lcode_corpus.json")
  if (!identical(as.integer(hv$rc), 0L) || !file.exists(cp)) {
    ng("C1 샌드박스 harvester 실행 실패", paste(tail(hv$out, 3), collapse = " | "))
  } else {
    co <- fromJSON(cp, simplifyVector = FALSE)
    cm <- list(); for (x in co$lcodes) cm[[x$l_code]] <- as.character(x$research_mode %||% NA)[1]
    # C1 — 필드가 디렉터리를 이긴다 (셀 파일은 paper_replication/ 에 그대로 있다)
    if (identical(cm[["L-RP-FX_CELL"]], NEW_MODE) && identical(cm[["L-RP-FX_FAITH"]], OLD_MODE))
      ok("C1 harvester: 같은 디렉터리 안에서 셀=reinforcement_cell · 충실구현=paper_replication (필드 > 디렉터리)") else
      ng("★C1 harvester 가 디렉터리로 모드를 파생한다", sprintf("cell=%s faith=%s", cm[["L-RP-FX_CELL"]] %||% "NA", cm[["L-RP-FX_FAITH"]] %||% "NA"))
    # C1' — corpus 수준 검출: 셀 모양 lesson 인데 모드가 reinforcement_cell 이 아닌 항목 = 누출 픽스처 1건
    cl <- vapply(Filter(function(x) .is_cell_text(x$lesson_text) && !identical(x$research_mode, NEW_MODE), co$lcodes),
                 function(x) x$l_code, "")
    if (identical(cl, "L-RP-FX_LEAK")) ok("C1' corpus 누출 검출 — 주입한 미재라벨 셀 1건만 paper_replication 으로 보인다") else
      ng("★C1' corpus 누출 검출 실패/오탐", paste(cl, collapse = ","))
    # C2 — positive_context 최근교훈: 재라벨 셀 제외 · 충실구현 포함 · 누출 셀은 보인다(= 배제가 모드로 일어난다는 양성 대조)
    pcp <- file.path(SBP, ".cache", "positive_context.json")
    if (!file.exists(pcp)) ng("C2 positive_context 미생성", pcp) else {
      rb <- fromJSON(pcp, simplifyVector = FALSE)$recent_block %||% ""
      has <- function(id) grepl(id, rb, fixed = TRUE)
      if (!has("L-RP-FX_CELL") && has("L-RP-FX_FAITH") && has("L-RP-FX_LEAK"))
        ok("C2 최근교훈: 재라벨 셀 제외 · 충실구현 포함 · 미재라벨 셀은 보임(배제 기준 = research_mode)") else
        ng("★C2 최근교훈 배제가 모드 기준이 아니다", sprintf("cell=%s faith=%s leak=%s", has("L-RP-FX_CELL"), has("L-RP-FX_FAITH"), has("L-RP-FX_LEAK")))
    }
    # C3b — hypothesis_index corpus 경로 (corpus 가 원본보다 새로워 보충 스캔은 건너뛴다)
    if (hi_loaded) {
      o2 <- file.path(SB, "hi_corpus.json")
      r2 <- tryCatch({ hi_env$build_hypothesis_index(root = SBP, out_path = o2, verbose = FALSE); TRUE },
                     error = function(x) { ng("C3b 샌드박스 빌드 실패", conditionMessage(x)); FALSE })
      if (isTRUE(r2)) .check_hi("C3b(corpus)", .hi_modes(o2), "lcode_corpus")
    }
  }
}

# ══ D. 앞으로의 누출 가드 — 파스 트리에서 재도출 + 돌연변이 ═════════════════════════
cat("\n── D. 누출 가드 (rf_cell_worker.R · run_paper_replication.R) ──\n")
.pd <- function(txt) {
  ex <- tryCatch(parse(text = txt, keep.source = TRUE), error = function(e) NULL)
  if (is.null(ex)) return(NULL)
  getParseData(ex, includeText = TRUE)
}
.call_node <- function(pd, tok_id) {   # SYMBOL_FUNCTION_CALL 토큰 → 함수명 expr → 호출 expr
  p1 <- pd$parent[pd$id == tok_id]; pd$parent[pd$id == p1]
}
# 워커: 최상위(무조건 실행) Sys.setenv(QVEST_RP_NO_LCODE = "1") 이 첫 run_paper_replication( 호출보다 앞선다
.worker_guard <- function(txt) {
  pd <- .pd(txt); if (is.null(pd)) return(list(ok = FALSE, why = "파스 실패"))
  fc <- pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
  se <- fc[fc$text == "Sys.setenv", , drop = FALSE]
  lines <- integer(0)
  for (i in seq_len(nrow(se))) {
    cid <- .call_node(pd, se$id[i])
    ct <- pd$text[pd$id == cid]
    if (grepl('(^|[^A-Za-z0-9_.])QVEST_RP_NO_LCODE\\s*=\\s*["\']1["\']', ct) && identical(pd$parent[pd$id == cid], 0L))
      lines <- c(lines, pd$line1[pd$id == cid])
  }
  rp <- fc$line1[fc$text == "run_paper_replication"]
  if (!length(lines)) return(list(ok = FALSE, why = "최상위 Sys.setenv(QVEST_RP_NO_LCODE=\"1\") 부재"))
  if (!length(rp)) return(list(ok = FALSE, why = "run_paper_replication 호출 부재"))
  if (min(lines) >= min(rp)) return(list(ok = FALSE, why = sprintf("스위치 L%d 가 호출 L%d 뒤", min(lines), min(rp))))
  list(ok = TRUE, why = sprintf("L%d 스위치 → L%d 호출", min(lines), min(rp)))
}
# 러너: if (<Sys.getenv("QVEST_RP_NO_LCODE") == "1">) {emit 없음} else {emit_lcode(mode="paper_replication")}
.rp_guard <- function(txt) {
  pd <- .pd(txt); if (is.null(pd)) return(list(ok = FALSE, why = "파스 실패"))
  ge <- pd[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == "Sys.getenv", , drop = FALSE]
  for (i in seq_len(nrow(ge))) {
    cid <- .call_node(pd, ge$id[i])
    if (!grepl('"QVEST_RP_NO_LCODE"', pd$text[pd$id == cid], fixed = TRUE)) next
    node <- cid; ifnode <- NA_integer_
    for (k in 1:8) {
      node <- pd$parent[pd$id == node]
      if (!length(node) || node <= 0L) break
      if (any(pd$parent == node & pd$token == "IF")) { ifnode <- node; break }
    }
    if (is.na(ifnode)) next
    ex <- tryCatch(parse(text = pd$text[pd$id == ifnode])[[1]], error = function(e) NULL)
    if (is.null(ex) || length(ex) < 4L) next
    sq <- function(z) gsub("\\s+", "", paste(deparse(z, width.cutoff = 500L), collapse = ""))
    cond <- sq(ex[[2]]); thn <- sq(ex[[3]]); els <- sq(ex[[4]])
    if (grepl('"QVEST_RP_NO_LCODE"', cond, fixed = TRUE) && grepl('"1"', cond, fixed = TRUE) &&
        !grepl("emit_lcode(", thn, fixed = TRUE) &&
        grepl('emit_lcode(mode="paper_replication"', els, fixed = TRUE))
      return(list(ok = TRUE, why = sprintf("L%d if(QVEST_RP_NO_LCODE==\"1\") → else emit_lcode(paper_replication)", pd$line1[pd$id == ifnode])))
  }
  list(ok = FALSE, why = "스위치로 emit_lcode(mode=\"paper_replication\") 를 가두는 if/else 부재")
}
.rd <- function(p) paste(readLines(p, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

if (!file.exists(WORKER) || !file.exists(RPR)) {
  sk("D_guard", "워커 또는 러너 부재", paste(WORKER, RPR))
} else {
  wt <- .rd(WORKER); rt <- .rd(RPR)
  g1 <- .worker_guard(wt); g2 <- .rp_guard(rt)
  if (isTRUE(g1$ok)) ok(sprintf("D1 rf_cell_worker.R: %s", g1$why)) else ng("★D1 워커 누출 스위치 부재 — 셀이 다시 충실구현 L-code 를 낸다", g1$why)
  if (isTRUE(g2$ok)) ok(sprintf("D2 run_paper_replication.R: %s", g2$why)) else ng("★D2 러너가 스위치를 안 읽는다", g2$why)
  # 돌연변이 — 계기가 실제로 발화하는가 (변이가 실제로 적용됐는지부터 확인한다)
  SW <- 'Sys.setenv(QVEST_RP_NO_LCODE = "1")'
  muts <- list(
    W1_삭제     = list(g = .worker_guard, src = wt, new = sub(SW, "", wt, fixed = TRUE)),
    W2_주석화   = list(g = .worker_guard, src = wt, new = sub(SW, paste0("# ", SW), wt, fixed = TRUE)),
    W3_if_FALSE = list(g = .worker_guard, src = wt, new = sub(SW, paste0("if (FALSE) ", SW), wt, fixed = TRUE)),
    R1_변수명   = list(g = .rp_guard, src = rt,
                       new = sub('Sys.getenv("QVEST_RP_NO_LCODE"', 'Sys.getenv("QVEST_RP_NO_LCODE_X"', rt, fixed = TRUE))
  )
  for (nm in names(muts)) {
    m <- muts[[nm]]
    if (identical(m$new, m$src)) { ng(sprintf("★D3 %s 변이 미적용 — 검사가 무효", nm), "원문에 변이 앵커 없음"); next }
    r <- m$g(m$new)
    if (!isTRUE(r$ok)) ok(sprintf("D3 돌연변이 %s → 빨강 (%s)", nm, r$why)) else
      ng(sprintf("★D3 돌연변이 %s 를 못 잡았다 — 가드가 장식이다", nm), r$why)
  }
}

emit()
