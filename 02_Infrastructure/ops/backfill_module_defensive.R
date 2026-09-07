#!/usr/bin/env Rscript
#==============================================================================
# backfill_module_defensive.R — module_catalog 소급 채움: essence_grade + defensive_score
#                               (2026-09-07 · 끊긴 이음매 수리의 소급 짝)
#
# 무엇을 고치나: `essence_score.R` 이 defensive_score 를 산출하고(:627 부근) 2계층 풀이
#   그것을 소비하는데(`build_module_performance.R` → `ds_pool_eligible`), **등재기가 그
#   값을 카탈로그에 안 실었다**. 실측 2026-09-07: module_catalog 275건 중 defensive_score
#   보유 0건 · top-level essence_grade 0건. 방어형 경로는 전 이력 한 번도 발화하지 않았다.
#   등재기(register_module.R)는 같은 날 수리했고, 이 스크립트는 **이미 등재된 275건**을
#   기존 산출물로 채운다.
#
# ★새 측정을 돌리지 않는다.
#   ① tier=artifact       — authoritative_remeasure.json 에 이미 실린 defensive_score 를 읽는다.
#   ② tier=stored_series  — 그게 없으면 **저장된 수익 시계열**(03_period_returns.csv +
#      05_benchmark_returns.csv)로 ds_score() 를 계산한다. 백테스트가 아니다: NAV 재시뮬레이션도
#      리밸런싱도 없고, 이미 계약을 통과해 저장된 순수익 계열의 월별 집계일 뿐이다.
#      (`02_Infrastructure/ops/retro_rolling_defensive.R` 이 replication 레인에 대해 하는 것과
#       같은 경로 — 그 스크립트는 stage_artifacts/replication 만 순회해서 alpha_search 레인의
#       275 모듈을 한 번도 안 건드렸다.)  --no-derive 로 ② 를 끌 수 있다.
#   ③ 둘 다 없으면 **조용히 채우지 않는다** — defensive_score 를 NULL 로 남기고 사유를 센다.
#      부재(never measured)와 거짓(measured, not defensive)은 다른 것이다.
#
# essence_grade 우선순위 (백필 시):
#   meta.essence_grade(v9.21 재채점, essence_regrade_ref 있음) > 산출물 essence_grade > meta
#   ★근거: `essence_regrade_apply.R` 은 "top-level grade 는 불변" 이라 명시하고 권위 등급을
#     meta 에 병기했다. 그리고 alpha_search 레인 산출물 19건은 **재채점 이전 판**이라
#     hard_fail(MDD) 규칙으로 F 가 박혀 있다(현행 규칙은 MDD 로 등급을 접지 않는다).
#
# 실행:
#   Rscript -e 'source("02_Infrastructure/ops/backfill_module_defensive.R")'            # dry-run(기본)
#   BF_WRITE=1 Rscript -e 'source("02_Infrastructure/ops/backfill_module_defensive.R")' # 실제 기록
#   (인자판: --write / --no-derive / --limit N)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.bf_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
              Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(p)) next
    p <- gsub("\\\\", "/", p)   # R 문자열 안 Windows 백슬래시(\U)는 즉사 — 슬래시로만
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[backfill_module_defensive] 프로젝트 루트 해석 실패 — QM_ROOT 확인")
}
ROOT <- .bf_root(); setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/defensive_score.R")))

.args   <- commandArgs(trailingOnly = TRUE)
WRITE   <- ("--write" %in% .args) || identical(Sys.getenv("BF_WRITE", "0"), "1")
DERIVE  <- !("--no-derive" %in% .args) && !identical(Sys.getenv("BF_NO_DERIVE", "0"), "1")
LIMIT   <- { i <- which(.args == "--limit"); if (length(i)) suppressWarnings(as.integer(.args[i[1]+1L])) else NA_integer_ }
STAMP   <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
MCP     <- file.path(ROOT, "06_Registry/module_catalog.json")
DP      <- ds_params(ROOT)

cat(sprintf("[backfill] 모드=%s · 저장계열 파생=%s · catalog=%s\n",
            if (WRITE) "★실기록" else "dry-run(기본)", if (DERIVE) "ON" else "OFF", MCP))

MC <- fromJSON(MCP, simplifyVector = FALSE)
mods <- MC$modules
ids <- names(mods); if (!is.na(LIMIT) && LIMIT > 0L) ids <- head(ids, LIMIT)
cat(sprintf("[backfill] 대상 모듈 %d건 (catalog n=%d)\n", length(ids), length(mods)))

.c1 <- function(x) { v <- suppressWarnings(as.character(x)[1])
                     if (length(v) != 1L || is.na(v) || !nzchar(v)) NA_character_ else v }
## sprintf/paste 는 인자 길이 0이면 문자열이 통째로 사라진다 — 스칼라 폴백을 강제한다.
.or <- function(x, alt) { v <- .c1(x); if (is.na(v)) alt else v }
.get <- function(x, k) { if (is.null(x) || !is.list(x) || !(k %in% names(x))) NULL else x[[k]] }

.compact <- function(ds, src) {
  if (is.null(ds) || !is.list(ds) || length(ds) == 0L) return(NULL)
  .n1 <- function(v) { z <- suppressWarnings(as.numeric(v)[1]); if (length(z) == 1L) z else NA_real_ }
  .i1 <- function(v) { z <- suppressWarnings(as.integer(v)[1]); if (length(z) == 1L) z else NA_integer_ }
  .sg <- function(s) if (is.null(s) || !is.list(s)) NULL else
    list(n = .i1(s$n), excess = .n1(s$excess), hit = .n1(s$hit), t = .n1(s$t), capture = .n1(s$capture))
  list(status = .c1(ds$status),
       defensive = if (is.null(ds$defensive) || length(ds$defensive) == 0L) NA else as.logical(ds$defensive)[1],
       convex = isTRUE(ds$convex), n_months = .i1(ds$n_months),
       down = .sg(ds$down), deep = .sg(ds$deep), mid = .sg(ds$mid), up = .sg(ds$up),
       reason = .c1(ds$reason), source = src, backfilled_at = STAMP)
}

LOG <- vector("list", length(ids)); k <- 0L
for (id in ids) {
  rec <- mods[[id]]
  bt  <- .c1(.get(rec, "bt_result_path"))
  dir <- if (is.na(bt)) NA_character_ else dirname(file.path(ROOT, gsub("\\\\", "/", bt)))
  fa  <- if (is.na(dir)) NA_character_ else file.path(dir, "authoritative_remeasure.json")

  aj <- if (!is.na(fa) && file.exists(fa))
          tryCatch(fromJSON(fa, simplifyVector = FALSE), error = function(e) NULL) else NULL

  ## ── essence 등급 ──────────────────────────────────────────────────────────
  meta <- .get(rec, "meta")
  m_eg <- .c1(.get(meta, "essence_grade"))
  m_ref <- .c1(.get(meta, "essence_regrade_ref"))
  a_eg <- if (is.null(aj)) NA_character_ else .c1(aj$essence_grade)
  eg <- NA_character_; eg_src <- "none"
  if (!is.na(m_eg) && !is.na(m_ref)) { eg <- m_eg; eg_src <- "meta_regrade" }
  else if (!is.na(a_eg))             { eg <- a_eg; eg_src <- "artifact" }
  else if (!is.na(m_eg))             { eg <- m_eg; eg_src <- "meta" }

  ## ── 방어형 스코어 ─────────────────────────────────────────────────────────
  ds <- NULL; ds_src <- NA_character_; ds_reason <- NA_character_
  a_ds <- if (is.null(aj)) NULL else aj$defensive_score
  if (!is.null(a_ds) && is.list(a_ds) && length(a_ds)) {
    ds <- a_ds; ds_src <- "artifact"
  } else if (DERIVE && !is.na(dir)) {
    fr <- file.path(dir, "03_period_returns.csv"); fb <- file.path(dir, "05_benchmark_returns.csv")
    if (file.exists(fr) && file.exists(fb)) {
      pr <- tryCatch(fread(fr, select = c("date","ret_net"), showProgress = FALSE), error = function(e) NULL)
      br <- tryCatch(fread(fb, select = c("date","benchmark_ret"), showProgress = FALSE), error = function(e) NULL)
      if (!is.null(pr) && !is.null(br) && nrow(pr) && nrow(br)) {
        ds <- tryCatch(ds_score(pr, br, DP), error = function(e) NULL)
        if (is.null(ds)) ds_reason <- "ds_score_error" else ds_src <- "stored_series"
      } else ds_reason <- "series_unreadable"
    } else if (!file.exists(fr)) ds_reason <- "no_period_returns"
      else ds_reason <- "no_benchmark_returns"
  } else if (is.na(dir)) ds_reason <- "no_artifact_path"
    else ds_reason <- "derive_disabled"

  cds <- .compact(ds, ds_src)
  code <- if (is.null(cds)) paste0("absent:", .or(ds_reason, "unknown"))
          else if (!identical(cds$status, "ok")) paste0("not_ok:", .or(cds$status, "unknown"))
          else if (isTRUE(cds$defensive)) "defensive_TRUE" else "defensive_FALSE"

  k <- k + 1L
  LOG[[k]] <- data.table(
    id = id, artifact = !is.null(aj),
    grade_emit = .c1(.get(rec, "grade")), essence_grade = eg, eg_source = eg_src,
    ds_source = ds_src, ds_status = if (is.null(cds)) NA_character_ else cds$status,
    defensive = if (is.null(cds)) NA else cds$defensive,
    down_n = if (is.null(cds) || is.null(cds$down)) NA_integer_ else cds$down$n,
    down_excess = if (is.null(cds) || is.null(cds$down)) NA_real_ else cds$down$excess,
    down_t = if (is.null(cds) || is.null(cds$down)) NA_real_ else cds$down$t,
    code = code)

  if (!is.na(eg)) { mods[[id]]$essence_grade <- eg
                    mods[[id]]$essence_grade_source <- eg_src }
  if (!is.null(cds)) mods[[id]]$defensive_score <- cds
}
D <- rbindlist(LOG[seq_len(k)], fill = TRUE)

cat("\n── essence_grade ────────────────────────────────────────────\n")
print(D[, .N, by = .(essence_grade, eg_source)][order(-N)])
cat("\n── defensive_score 소스 ─────────────────────────────────────\n")
print(D[, .N, by = .(ds_source)][order(-N)])
cat("\n── 판정 코드 (부재 ≠ 거짓) ──────────────────────────────────\n")
print(D[, .N, by = .(code)][order(-N)])
cat(sprintf("\n[backfill] essence_grade 채움 %d / %d · defensive_score 채움 %d / %d (부재 %d)\n",
            sum(!is.na(D$essence_grade)), nrow(D),
            sum(!is.na(D$ds_source)), nrow(D), sum(is.na(D$ds_source))))
cat(sprintf("[backfill] defensive=TRUE %d · FALSE %d · 판정불가 %d\n",
            sum(D$defensive %in% TRUE), sum(D$defensive %in% FALSE),
            sum(!is.na(D$ds_source) & is.na(D$defensive))))

if (!WRITE) {
  cat("\n[backfill] dry-run 종료 — 아무것도 쓰지 않았다. 실기록 = --write (또는 BF_WRITE=1)\n")
} else {
  BK <- paste0(MCP, ".bak_", format(Sys.time(), "%Y%m%d_%H%M%S"))
  file.copy(MCP, BK)
  MC$modules <- mods
  MC$last_updated <- STAMP
  MC$defensive_backfill <- list(
    ref = "defensive_backfill_20260907", applied_at = STAMP,
    n_essence_grade = sum(!is.na(D$essence_grade)),
    n_defensive_score = sum(!is.na(D$ds_source)),
    n_defensive_true = sum(D$defensive %in% TRUE),
    derive_from_stored_series = DERIVE,
    note = paste("register_module 이 싣지 않던 essence_grade/defensive_score 를 기존 산출물에서 소급.",
                 "새 측정 없음(artifact 판독 + 저장된 수익계열 월별 집계).",
                 "top-level grade 는 불변 — 발행 시점 기록."))
  txt <- toJSON(MC, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 8)
  if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
    stop("[backfill] 재파싱 검증 실패 — 기록 중단")
  tmp <- paste0(MCP, ".tmp"); write(txt, tmp)
  if (!isTRUE(suppressWarnings(file.rename(tmp, MCP))))
    stop("[backfill] 원자 교체 실패 (대상이 열려 있는지 확인): ", tmp)
  cat(sprintf("\n[backfill] ★기록 완료 — %s (백업 %s)\n", MCP, basename(BK)))
}
invisible(D)
