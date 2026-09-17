#!/usr/bin/env Rscript
#==============================================================================
# rf_overlay_audit_merge.R — G1 적대적 설계시점 감사의 축별 산출을 **하나의 판정으로 병합** (v10.4 2026-09-17)
#
# 왜 R 이 병합하나: LLM 판정자를 하나 더 세우면 그 판정자가 다시 분류한다(충실도 팬아웃과 같은 이유).
#   병합 규칙은 결정론이므로 코드가 진다 — 그리고 **진술은 증거가 아니다**: 축이 "reject" 라고 적어도
#   채택된 발견이 0건이면 pass 다. 반대로 축이 "pass" 라고 적어도 채택된 발견이 있으면 reject 다.
#
# 채택 규칙 (정본 = 06_Registry/rf_overlay_adversary_axes.json evidence_rule):
#   · leak / probe_evasion / full_sample / degenerate — evidence 가 `<kind>.R:<행> <인용>` 이고 병합기가
#     arm 파일을 **다시 읽어** 그 행(주석 걷은 본문)에 그 인용이 실재할 때만 채택. 아니면 무시 + ignored 기록.
#   · duplicate — duplicate_of 가 **활성** 카탈로그 id(자기 자신 제외)일 때만 채택.
#   · 종합: 채택 발견 ≥1 → reject · required 축 미산출/파손 → unavailable(호출자는 등재 금지) · 그 밖 pass.
#     reject > unavailable > pass (거부는 확정 정보, 미산출은 재실행 사유).
#
# 산출: <out_dir>/<kind>/audit.json — {kind, verdict, reasons[], duplicate_of, axis_verdicts[], ignored_findings[], …}
# 사용: 라이브러리 — source() 후 rf_overlay_audit_merge(kind, root)
#       CLI      — Rscript rf_overlay_audit_merge.R <kind>   (종료 0 pass · 3 reject · 4 unavailable)
#   경로 재지정(검사·샌드박스): QVEST_OA_OUT(산출 루트) · QVEST_OA_AXES · QVEST_OA_CATALOG · QVEST_OA_ARMDIR
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.OA_ROOT <- function() gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))

.OA_TYPES <- c("leak", "probe_evasion", "full_sample", "degenerate", "duplicate")
.OA_HARD  <- c("leak", "probe_evasion", "full_sample", "degenerate")   # 검증된 근거 1건이면 reject

.oa_norm <- function(s) trimws(gsub("[[:space:]]+", " ", as.character(s %||% "")))
.oa_strip_quote <- function(q) {
  q <- .oa_norm(q)
  q <- gsub("^[`\"'\u201c\u201d]+|[`\"'\u201c\u201d]+$", "", q)   # 감싼 따옴표·백틱
  q <- sub("#.*$", "", q)                                           # 인용 속 주석은 코드가 아니다
  .oa_norm(q)
}

#' 근거 문자열 파싱 — "<file>:<line> <quote>" · 여러 위치는 ';' 또는 줄바꿈으로
.oa_parse_evidence <- function(ev) {
  ev <- as.character(ev %||% "")[1]
  if (is.na(ev) || !nzchar(ev)) return(list())
  parts <- strsplit(ev, "\\s*;\\s*|\n", perl = TRUE)[[1]]
  out <- list()
  for (p in parts) {
    m <- regmatches(p, regexec("^\\s*`?(.*?\\.(R|r|json))`?\\s*:\\s*(\\d+)\\s*:?\\s*(.*)$", p, perl = TRUE))[[1]]
    if (length(m) == 5L)
      out[[length(out) + 1L]] <- list(file = basename(trimws(m[2])), line = suppressWarnings(as.integer(m[4])), quote = m[5])
  }
  out
}

#' 근거 검증 — 재도출. 인용이 arm 파일의 그 행(주석 걷은 본문)에 실재하는가
.oa_verify_evidence <- function(ev, arm_lines, arm_file) {
  locs <- .oa_parse_evidence(ev)
  if (!length(locs)) return(list(ok = FALSE, why = "근거 형식 아님(<kind>.R:<행> <인용> 필요)"))
  whys <- character(0)
  for (l in locs) {
    if (!identical(l$file, arm_file)) { whys <- c(whys, sprintf("%s 는 arm 파일(%s)이 아니다", l$file, arm_file)); next }
    if (is.na(l$line) || l$line < 1L || l$line > length(arm_lines)) {
      whys <- c(whys, sprintf("행 %s 없음(파일 %d행)", as.character(l$line), length(arm_lines))); next }
    q <- .oa_strip_quote(l$quote)
    if (nchar(q) < 4L) { whys <- c(whys, sprintf("행 %d 인용이 공백이거나 너무 짧다", l$line)); next }
    body <- .oa_norm(sub("#.*$", "", arm_lines[l$line]))
    if (nzchar(body) && grepl(q, body, fixed = TRUE))
      return(list(ok = TRUE, why = sprintf("%s:%d 실재", arm_file, l$line)))
    whys <- c(whys, sprintf("행 %d 본문에 인용이 없다", l$line))
  }
  list(ok = FALSE, why = paste(whys, collapse = " / "))
}

rf_overlay_audit_merge <- function(kind, root = .OA_ROOT(), out_dir = NULL, axes_path = NULL,
                                   catalog_path = NULL, arm_dir = NULL, write = TRUE) {
  out_dir      <- out_dir      %||% file.path(Sys.getenv("QVEST_OA_OUT",     file.path(root, ".cache/rf_overlay_audit")), kind)
  axes_path    <- axes_path    %||% Sys.getenv("QVEST_OA_AXES",    file.path(root, "06_Registry/rf_overlay_adversary_axes.json"))
  catalog_path <- catalog_path %||% Sys.getenv("QVEST_OA_CATALOG", file.path(root, "06_Registry/overlay_catalog.json"))
  arm_dir      <- arm_dir      %||% Sys.getenv("QVEST_OA_ARMDIR",  file.path(root, "02_Infrastructure/reinforcement/overlay_arms"))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  arm_file  <- paste0(kind, ".R")
  arm_path  <- file.path(arm_dir, arm_file)
  arm_lines <- if (file.exists(arm_path)) readLines(arm_path, warn = FALSE) else character(0)
  meta_path <- file.path(arm_dir, paste0(kind, ".arm.json"))
  meta <- if (file.exists(meta_path)) tryCatch(fromJSON(meta_path, simplifyVector = FALSE), error = function(e) list()) else list()
  self_id <- as.character(meta$id %||% paste0(kind, "_v1"))[1]

  AXES <- tryCatch(fromJSON(axes_path, simplifyVector = FALSE)$axes, error = function(e) NULL)
  CAT  <- tryCatch(fromJSON(catalog_path, simplifyVector = FALSE), error = function(e) NULL)
  active_ids <- character(0)
  for (a in CAT$arms %||% list()) {
    if (identical(as.character(a$status %||% ""), "active") &&
        !identical(as.character(a$id %||% ""), self_id) && !identical(as.character(a$kind %||% ""), kind))
      active_ids <- c(active_ids, as.character(a$id))
  }
  ls_path <- file.path(out_dir, "lane_status.json")
  lane_status <- if (file.exists(ls_path)) tryCatch(fromJSON(ls_path, simplifyVector = FALSE), error = function(e) NULL) else NULL

  rows <- list(); reasons <- character(0); ignored_all <- list()
  reject <- FALSE; unavailable <- FALSE; dup_of <- NA_character_
  if (is.null(AXES) || !length(AXES)) { unavailable <- TRUE; reasons <- c(reasons, sprintf("축 등록부를 못 읽었다: %s", axes_path)) }
  if (!length(arm_lines)) { unavailable <- TRUE; reasons <- c(reasons, sprintf("arm 파일 부재: %s — 근거를 재도출할 파일이 없다", arm_path)) }

  for (ax in AXES %||% list()) {
    id <- as.character(ax$id)
    f  <- file.path(out_dir, sprintf("axis_%s.json", id))
    A  <- if (file.exists(f)) tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL) else NULL
    st <- lane_status$axes[[id]] %||% list()
    row <- list(axis = id, required = isTRUE(ax$required), model = as.character(ax$model %||% ""),
                model_used = as.character(st$model_used %||% NA), fell_back = isTRUE(as.logical(st$fell_back %||% FALSE)),
                present = file.exists(f), parsed = is.list(A), declared_verdict = NA_character_,
                n_findings = 0L, n_verified = 0L, n_ignored = 0L, verified = list(), ignored = list(), status = "")
    if (!is.list(A)) {
      env <- as.character(st$env_failure %||% "")
      row$status <- if (file.exists(f)) "축 산출물 파손(JSON 아님)" else
                    if (nzchar(env)) sprintf("축 미산출 — 환경 실패(%s)", env) else "축 미산출(레인 실패·타임아웃)"
      if (isTRUE(ax$required)) { unavailable <- TRUE; reasons <- c(reasons, sprintf("[%s] %s", id, row$status)) }
      rows[[length(rows) + 1L]] <- row; next
    }
    row$declared_verdict <- as.character(A$verdict %||% "")[1]
    fnd <- A$findings %||% list()
    if (!is.list(fnd)) fnd <- list()
    for (fi in fnd) {
      if (!is.list(fi)) next
      ty <- as.character(fi$type %||% "")[1]; ev <- as.character(fi$evidence %||% "")[1]
      ex <- .oa_norm(fi$explanation %||% ""); dof <- as.character(fi$duplicate_of %||% "")[1]
      row$n_findings <- row$n_findings + 1L
      if (ty %in% .OA_HARD) {
        v <- .oa_verify_evidence(ev, arm_lines, arm_file)
        if (isTRUE(v$ok)) {
          reject <- TRUE
          row$verified <- c(row$verified, list(list(type = ty, evidence = ev, explanation = ex, check = v$why)))
          reasons <- c(reasons, sprintf("[%s] %s — %s (%s)", id, ty, ex, v$why))
        } else {
          row$ignored <- c(row$ignored, list(list(type = ty, evidence = ev, explanation = ex, why = v$why)))
        }
      } else if (identical(ty, "duplicate")) {
        if (nzchar(dof) && !identical(dof, "null") && dof %in% active_ids) {
          reject <- TRUE; if (is.na(dup_of)) dup_of <- dof
          row$verified <- c(row$verified, list(list(type = ty, duplicate_of = dof, explanation = ex, check = "활성 카탈로그 id 실재")))
          reasons <- c(reasons, sprintf("[%s] duplicate of active %s — %s", id, dof, ex))
        } else {
          why <- if (!nzchar(dof) || identical(dof, "null")) "duplicate_of 없음" else
                 if (identical(dof, self_id)) "duplicate_of 가 자기 자신" else "활성 카탈로그 id 아님(퇴역·미등재)"
          row$ignored <- c(row$ignored, list(list(type = ty, duplicate_of = dof, explanation = ex, why = why)))
        }
      } else {
        row$ignored <- c(row$ignored, list(list(type = ty, evidence = ev, explanation = ex, why = "알 수 없는 type")))
      }
    }
    row$n_verified <- length(row$verified); row$n_ignored <- length(row$ignored)
    row$status <- if (row$n_verified > 0L) "reject" else "pass"
    for (g in row$ignored) ignored_all[[length(ignored_all) + 1L]] <- c(list(axis = id), g)
    rows[[length(rows) + 1L]] <- row
  }

  verdict <- if (reject) "reject" else if (unavailable) "unavailable" else "pass"
  env_fail <- any(vapply(rows, function(r) grepl("환경 실패", r$status, fixed = TRUE), logical(1)))
  if (length(ignored_all))
    reasons <- c(reasons, sprintf("무시된 발견 %d건(근거 미실재·비활성 id) — ignored_findings 참조", length(ignored_all)))
  out <- list(kind = kind, verdict = verdict, reasons = as.list(reasons),
              duplicate_of = if (is.na(dup_of)) NULL else dup_of,
              axis_verdicts = rows, ignored_findings = ignored_all,
              n_axes = length(AXES %||% list()), env_failure = env_fail,
              active_ids_compared = length(active_ids), arm_file = arm_path,
              merged_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (isTRUE(write)) {
    p <- file.path(out_dir, "audit.json")
    write(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), p)
  }
  cat(sprintf("audit: %s | %s | 축 %d (%s) | 채택 %d · 무시 %d%s\n", kind, verdict, length(rows),
              paste(vapply(rows, function(r) sprintf("%s=%s", r$axis, if (nzchar(r$status)) r$status else "?"), character(1)), collapse = ","),
              sum(vapply(rows, function(r) r$n_verified, integer(1))), length(ignored_all),
              if (length(reasons)) paste0(" | ", paste(reasons, collapse = " / ")) else ""))
  invisible(out)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  if (!length(a) || !nzchar(a[1])) { cat("usage: Rscript rf_overlay_audit_merge.R <kind>\n"); quit(status = 4L) }
  r <- rf_overlay_audit_merge(a[1])
  quit(status = switch(r$verdict, pass = 0L, reject = 3L, 4L))
}
