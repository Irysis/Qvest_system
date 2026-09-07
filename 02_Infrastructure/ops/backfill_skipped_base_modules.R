#!/usr/bin/env Rscript
#==============================================================================
# backfill_skipped_base_modules.R — 음수 알파 게이트가 버린 건의 **소급 등재**
#                                   (도훈 승인 2026-09-07 "등재하고 소급까지")
#
# 무엇을 고치나: `rf_replication_verify.R` 의 `base_below_threshold` 분기는 **전기간**
#   PORT_t < 0 하나로 강화를 생략하고 논문을 `ledger_consumed` 로 영구 소비했다.
#   그 분기는 `defensive_score` 를 보지 않았다. 실측 2026-09-07: 그렇게 버려진 14건 중
#   **11건이 계약 기준 방어형**이었다(하락월 t 9.95 · 8.63 · 6.38 · 6.23 · 5.47 · 3.72 …).
#   방어형의 값어치는 전기간 평균이 아니라 벤치가 마이너스를 낸 국면에서 나므로,
#   전기간 통계량으로 그것을 버리는 것은 AX-001 이 금지하는 평가다.
#   게이트는 같은 날 수리했고(방어형이면 등재 후 소비), 이 스크립트는 **이미 버려진 건**을
#   같은 규칙으로 소급 등재한다.
#
# ★새 측정을 돌리지 않는다 — 각 entry 의 `base_artifacts` 에 이미 있는
#   authoritative_remeasure.json(판정) + 계약 CSV(재료)를 읽어 옮길 뿐이다.
#   판정도 재료 조립도 전부 `register_measured_module.R` 이 한다(사본 없음).
#
# 실행:
#   Rscript 02_Infrastructure/ops/backfill_skipped_base_modules.R            # dry-run(기본)
#   Rscript 02_Infrastructure/ops/backfill_skipped_base_modules.R --write    # 실제 등재
#   옵션: --catalog <path>(대체 카탈로그 — 검사용) · --limit N · --all(강화 entry 포함)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.bs_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
              Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)     # R 문자열 안 Windows 백슬래시(\U)는 즉사 — 슬래시로만
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry")))
      return(sub("/+$", "", p))
  }
  stop("[backfill_skipped_base] 프로젝트 루트 해석 실패 — QM_ROOT 확인")
}
ROOT <- .bs_root(); setwd(ROOT)
Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)

.args  <- commandArgs(trailingOnly = TRUE)
WRITE  <- ("--write" %in% .args) || identical(Sys.getenv("BSB_WRITE", "0"), "1")
ALL    <- "--all" %in% .args
LIMIT  <- { i <- which(.args == "--limit");   if (length(i)) suppressWarnings(as.integer(.args[i[1]+1L])) else NA_integer_ }
CATP   <- { i <- which(.args == "--catalog"); if (length(i)) .args[i[1]+1L] else NULL }
LEDGER <- { i <- which(.args == "--ledger");  if (length(i)) .args[i[1]+1L] else
              file.path(ROOT, "06_Registry/reinforce_ledger_l1.json") }

.rmm <- new.env(parent = globalenv())          # 전역 %||% 오염 방지 — 격리 적재
suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts/register_measured_module.R"),
                            envir = .rmm))

.c1 <- function(x, alt = NA_character_) {
  v <- suppressWarnings(as.character(x)[1])
  if (length(v) != 1L || is.na(v) || !nzchar(v)) alt else v
}
.n1 <- function(x) { v <- suppressWarnings(as.numeric(x)[1]); if (length(v) == 1L) v else NA_real_ }
.g  <- function(x, k) if (is.null(x) || !is.list(x) || !(k %in% names(x))) NULL else x[[k]]

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
L <- fromJSON(LEDGER, simplifyVector = FALSE)
ents <- L$entries %||% list()

## skipped_base 판별 — base_id 접미 또는 park 사유. 둘 중 하나만 보면 형식이 바뀌었을 때 샌다.
.is_skipped <- function(e) {
  bid <- .c1(.g(e, "base_id"), "")
  pr  <- .c1(.g(e, "parked_reason"), "")
  grepl("_skipped_base$", bid) || startsWith(pr, "skipped_base_quality")
}
sel <- if (ALL) ents else Filter(.is_skipped, ents)
if (!is.na(LIMIT) && LIMIT > 0L) sel <- utils::head(sel, LIMIT)

cat(sprintf("[backfill_skipped_base] 모드=%s · 원장=%s · 대상 %d / 전체 %d\n",
            if (WRITE) "★실등재" else "dry-run(기본)", .rmm$.rmm_rel(LEDGER, ROOT),
            length(sel), length(ents)))
if (!is.null(CATP)) cat(sprintf("[backfill_skipped_base] 카탈로그 대체 경로: %s\n", CATP))

.catalog_n <- function(p) {
  if (is.null(p)) p <- file.path(ROOT, "06_Registry/module_catalog.json")
  if (!file.exists(p)) return(0L)
  m <- tryCatch(fromJSON(p, simplifyVector = FALSE)$modules, error = function(e) NULL)
  length(m %||% list())
}
N_BEFORE <- .catalog_n(CATP)

LOG <- vector("list", length(sel)); k <- 0L
for (e in sel) {
  bid <- .c1(.g(e, "base_id"), "?")
  dir <- .c1(.g(e, "base_artifacts"), "")
  dir <- if (is.na(dir)) "" else gsub("\\\\", "/", dir)
  pk  <- .c1(.g(e, "paper_key"), "")
  row <- list(base_id = bid, paper_key = .c1(pk, ""), artifacts = dir)

  if (!nzchar(dir) || !dir.exists(dir)) {
    k <- k + 1L
    LOG[[k]] <- c(row, list(code = "artifacts_missing", route = NA_character_,
                            grade = NA_character_, registered = FALSE,
                            down_t = NA_real_, down_excess = NA_real_))
    next
  }
  auth <- .rmm$rmm_read_auth(dir)
  adm  <- if (is.null(auth)) NULL else .rmm$rmm_admission(auth)
  r <- .rmm$rmm_register_measured(
    dir, origin_mode = "replication_skipped_base_backfill",
    meta = list(ledger_base_id = bid, paper_key = .c1(pk, ""),
                parked_reason = substr(.c1(.g(e, "parked_reason"), ""), 1, 300),
                admitted_by = "backfill_skipped_base_modules (도훈 승인 2026-09-07)"),
    dry_run = !WRITE, catalog_path = CATP,
    quarantine_path = if (is.null(CATP)) NULL else
      file.path(dirname(CATP), "module_quarantine.json"))
  k <- k + 1L
  LOG[[k]] <- c(row, list(
    code = .c1(r$code, "unknown"),
    route = if (is.null(adm)) NA_character_ else .c1(adm$route),
    grade = if (is.null(adm)) NA_character_ else .c1(adm$grade),
    registered = isTRUE(r$registered),
    down_t = if (is.null(adm)) NA_real_ else .n1(adm$down_t),
    down_excess = if (is.null(adm)) NA_real_ else .n1(adm$down_excess)))
}
D <- rbindlist(lapply(LOG[seq_len(k)], as.data.table), fill = TRUE)

cat("\n── 건별 판정 ────────────────────────────────────────────────\n")
if (nrow(D)) for (i in seq_len(nrow(D)))
  cat(sprintf("  %-38s %-10s route=%-22s code=%-28s 하락월t=%s 초과=%s\n",
              substr(D$base_id[i], 1, 38), substr(.c1(D$paper_key[i], "-"), 1, 10),
              .c1(D$route[i], "-"), .c1(D$code[i], "-"),
              if (is.finite(D$down_t[i])) sprintf("%.2f", D$down_t[i]) else "-",
              if (is.finite(D$down_excess[i])) sprintf("%+.2f%%", 100 * D$down_excess[i]) else "-"))

cat("\n── 사유 집계 (부재 ≠ 거짓) ──────────────────────────────────\n")
if (nrow(D)) print(D[, .N, by = .(code)][order(-N)])
cat(sprintf("\n[backfill_skipped_base] 자격 있음 %d / %d (방어형 %d · 등급floor %d) · 실등재 %d\n",
            sum(!is.na(D$route)), nrow(D),
            sum(D$route %in% "defensive_specialist"), sum(D$route %in% "grade_floor"),
            sum(D$registered %in% TRUE)))
N_AFTER <- .catalog_n(CATP)
cat(sprintf("[backfill_skipped_base] module_catalog n: %d -> %d%s\n", N_BEFORE, N_AFTER,
            if (WRITE) "" else "  (dry-run — 아무것도 쓰지 않았다. 실등재 = --write)"))
invisible(D)
