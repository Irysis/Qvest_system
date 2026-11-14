## frozen_holdings_diag.R — 위기 전 보유 동결 대조 진단 실행기(기록만 · 등급 · 노치 · 권위 기록 무접촉)
##   결정: 도훈 CHARTER-GAP14-FOLLOWUPS-20261113 (나) '기록부터' — 보유 회전 β 타이밍 = A′ 의 타이밍 · 등급 반영(v3.6)은 따로 정한다.
##   계약 = 02_Infrastructure/contracts/frozen_holdings_control.R · 설정 = 06_Registry/frozen_holdings_control.json
## 사용: Rscript 02_Infrastructure/programs/frozen_holdings_diag.R [--root R] (--dirs <파일> | --round <라운드 폴더> | --scope cr_strong)
##                                                                 [--limit N] [--out <csv>] [--list-only] [--write]
##   --dirs  = 저장소 상대 산출물 폴더 목록(한 줄에 하나)
##   --round = 라운드 폴더(results/*.json 의 artifacts) — 라운드 평가 뒤에 돌린다(round_core 는 등록 라운드의 핀 대상이라 코어 배선은 다음 코어 출시 때)
##   --scope cr_strong = 저장 권위 기록 중 grade_v3.cr.overall = strong(위기 방어 '강함' 판정이 있는 기록 — 선택/타이밍 판정이 등급에 닿는 기록)
##   --list-only = 대상 목록만 출력(자료 적재 · 계산 없음) · 기본 = 드라이런(표 출력) · --write = 원장(설정 ledger)에 추가(같은 키는 건너뜀)
##   무거운 계산(RAWDATA 전체 적재 · 기록마다 위기 수 × 플라시보 n) — 측정 창과 겹치지 않게 돌린다(오케스트레이터 11-14: P1R04 · P1S03 측정 뒤).
##   원장은 전기간 기록이다 — 판단 T1~T4 · 철학 P1 · P2 · P4 는 열지 않는다(보는 창 몫만 따로 건넨다 · 규약 §13-2).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
argv <- function(k, d = NULL) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }
ROOT <- sub("/+$", "", gsub("\\\\", "/", argv("--root", Sys.getenv("QM_ROOT", getwd()))))
if (!file.exists(file.path(ROOT, "CLAUDE.md"))) stop("[fhc diag] 저장소 루트가 아니다: ", ROOT)
WRITE <- "--write" %in% args; LIST_ONLY <- "--list-only" %in% args
LIMIT <- as.integer(argv("--limit", "0")); OUTCSV <- argv("--out", NULL)
DIRS_FILE <- argv("--dirs", NULL); ROUND <- argv("--round", NULL); SCOPE <- argv("--scope", NULL)
if (sum(!vapply(list(DIRS_FILE, ROUND, SCOPE), is.null, logical(1))) != 1L) stop("[fhc diag] --dirs · --round · --scope 중 하나만 준다")
if (!is.null(SCOPE) && !identical(SCOPE, "cr_strong")) stop("[fhc diag] --scope 어휘 밖: ", SCOPE, " (cr_strong)")
source(file.path(ROOT, "02_Infrastructure/contracts/frozen_holdings_control.R"))
rel <- function(p) sub(paste0("^", ROOT, "/"), "", sub("^.*?(stage_artifacts/)", "\\1", gsub("\\\\", "/", p)))

## ── 대상 ──
targets <- if (!is.null(DIRS_FILE)) {
  x <- trimws(readLines(DIRS_FILE, warn = FALSE, encoding = "UTF-8")); x[nzchar(x)]
} else if (!is.null(ROUND)) {
  rd <- if (grepl("^([A-Za-z]:)?/", ROUND)) ROUND else file.path(ROOT, ROUND)
  fs <- Sys.glob(file.path(rd, "results", "*.json"))
  unique(unlist(lapply(fs, function(f) { a <- tryCatch(fromJSON(f)$artifacts, error = function(e) NULL); if (is.null(a)) character(0) else rel(as.character(a)) })))
} else {
  ar <- list.files(file.path(ROOT, "stage_artifacts"), pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
  ar <- ar[!grepl("/stage_artifacts/WT_", gsub("\\\\", "/", ar))]
  keep <- vapply(ar, function(p) {
    A <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    !is.null(A) && identical(A$grade_scheme, "grade_v3") && identical(as.character(A$grade_v3$cr$overall %||% "")[1], "strong")
  }, logical(1))
  rel(dirname(ar[keep]))
}
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
targets <- sort(unique(targets))
miss <- targets[!dir.exists(file.path(ROOT, targets))]
if (length(miss)) stop("[fhc diag] 없는 산출물 폴더: ", paste(head(miss, 5), collapse = ", "), if (length(miss) > 5) " …" else "")
if (LIMIT > 0L) targets <- head(targets, LIMIT)
cat(sprintf("[fhc diag] 대상 %d건 · 모드 %s\n", length(targets), if (LIST_ONLY) "목록만" else if (WRITE) "쓰기" else "드라이런"))
if (LIST_ONLY) { cat(paste0("  ", targets), sep = "\n"); quit(status = 0L) }
if (!length(targets)) quit(status = 0L)

## ── 자료(한 번 적재) · 계산 ──
fcfg <- fhc_cfg(ROOT); d <- .fhc_deps(ROOT); cfg <- d$mc$mc_cfg(ROOT); bcfg <- d$bc$bc_cfg(ROOT)
t0 <- Sys.time()
raw <- d$mc$mc_load_raw(ROOT, hygiene = TRUE)
bmh <- d$mc$.mc_bench_history(ROOT)
cat(sprintf("[fhc diag] RAWDATA %s행 · 벤치 이력 %s~%s · 적재 %.1f분\n", format(nrow(raw), big.mark = ","), min(bmh$date), max(bmh$date),
            as.numeric(difftime(Sys.time(), t0, units = "mins"))))
lines <- list(); rows <- list()
for (k in seq_along(targets)) {
  t1 <- Sys.time(); dd <- file.path(ROOT, targets[k])
  res <- tryCatch(fhc_dir(dd, ROOT, raw = raw, bm_hist = bmh, fcfg = fcfg, cfg = cfg, bcfg = bcfg), error = function(e) list(error = conditionMessage(e)))
  if (!is.null(res$error)) {
    cat(sprintf("[fhc diag] %d/%d %s · 오류: %s\n", k, length(targets), targets[k], res$error))
    rows[[k]] <- data.table(dir = targets[k], error = res$error); next
  }
  o <- res$summary$overall
  cat(sprintf("[fhc diag] %d/%d %s · v3.5 %s · 동결 %s(%s · 위기 %d) · 가상 %s · %.0fs\n", k, length(targets), targets[k], res$v35_basis %||% "NA",
              res$label, if (is.finite(o$share_frozen_beats_size_beta)) sprintf("%.2f", o$share_frozen_beats_size_beta) else "NA", o$n_crisis,
              res$hypothetical_v36, as.numeric(difftime(Sys.time(), t1, units = "secs"))))
  rows[[k]] <- data.table(dir = targets[k], strategy = res$source$strategy_name %||% NA_character_, status = res$status, v35_basis = res$v35_basis %||% NA_character_,
                          label = res$label, hypothetical_v36 = res$hypothetical_v36, n_crisis = o$n_crisis,
                          share_frozen_beats_size_beta = o$share_frozen_beats_size_beta, share_frozen_beats_size = o$share_frozen_beats_size,
                          median_rotation_gap = o$median_rotation_gap, median_beta_frozen = o$median_beta_frozen,
                          visible_label = res$summary$visible$label, test_label = res$summary$test$label)
  lines[[length(lines) + 1L]] <- fhc_ledger_line(res, dd, ROOT)
}
tab <- rbindlist(rows, fill = TRUE)
if (!is.null(OUTCSV)) fwrite(tab, OUTCSV)
if (nrow(tab) && "hypothetical_v36" %in% names(tab)) {
  cat("[fhc diag] 가상 판정(건수):", paste(names(table(tab$hypothetical_v36)), table(tab$hypothetical_v36), sep = "=", collapse = " · "), "\n")
}
if (WRITE && length(lines)) {
  w <- fhc_ledger_append(lines, file.path(ROOT, fcfg$ledger))
  cat(sprintf("[fhc diag] 원장 %s — 씀 %d · 같은 키 건너뜀 %d\n", fcfg$ledger, w$written, w$skipped))
}
cat(sprintf("[fhc diag] 끝 %.1f분\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
