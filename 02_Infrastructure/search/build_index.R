#==============================================================================
# build_index.R — v7.1-lite Sprint 1.1 Unified Search Index Builder
#
# JSONL append-only output: qepm/observability/search_index.jsonl
# 1 row per indexable entity. type ∈ {lcode|wt|cert|paper|axiom|registry|lawbook|critic|governance}.
#
# Source map:
#   - lcode      qepm/memory/methodology_memory_v55_extensions.md (^L-\d{3} headers)
#   - axiom      qepm/memory/axioms/active/AX-*.json
#   - wt         qepm/mailbox/worktask/*/request.json + status.json (1 row per WT)
#   - cert       qepm/mailbox/worktask/*/*_certificate.json
#   - critic     qepm/mailbox/worktask/*/codex_critic_response_*.json
#   - governance qepm/mailbox/worktask/*/governance_log.json + qepm/mailbox/governor/governance_log.json (events[] 순회)
#   - registry   06_Registry/{strategy,idea,paper}_registry.json + strategy_grades.json
#   - paper      04_Research/paper_notes/P*.md (front-matter title + first 500 chars)
#   - lawbook    00_Lawbook/**/*.md (path + first 1k chars)
#
# Row schema:
#   {id, type, title, body, source_path, wt_id, timestamp, tags}
#
# Usage:
#   Rscript build_index.R                       # default rebuild
#   Rscript build_index.R --dry-run             # warning summary only, no write
#   Rscript build_index.R --include-examples    # include 02_Infrastructure/docs/examples/qvest_workflows/
#
# Plan: v7-1-cheerful-balloon.md Sprint 1.1
#==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = "")
if (PROJ_ROOT == "" || !dir.exists(PROJ_ROOT)) {
  PROJ_ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot"))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

OUT_PATH <- file.path(PROJ_ROOT, "qepm/observability/search_index.jsonl")

args <- commandArgs(trailingOnly = TRUE)
DRY_RUN <- "--dry-run" %in% args
INCLUDE_EXAMPLES <- "--include-examples" %in% args

# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────

source_warnings <- character()
warn_missing <- function(label, path) {
  source_warnings <<- c(source_warnings,
                         sprintf("[MISSING] %s — %s", label, path))
}

emit_row <- function(rows, id, type, title, body, source_path,
                      wt_id = NULL, timestamp = NULL, tags = list()) {
  body_truncated <- if (nchar(body) > 4000) {
    paste0(substr(body, 1, 4000), " ... [truncated]")
  } else body
  rows[[length(rows) + 1]] <- list(
    id = id,
    type = type,
    title = title,
    body = body_truncated,
    source_path = source_path,
    wt_id = wt_id,
    timestamp = timestamp,
    tags = tags
  )
  rows
}

# ─────────────────────────────────────────────────────────────────
# Source extractors
# ─────────────────────────────────────────────────────────────────

build_lcode <- function() {
  rows <- list()
  src <- file.path(PROJ_ROOT, "qepm/memory/methodology_memory_v55_extensions.md")
  if (!file.exists(src)) {
    warn_missing("lcode", src)
    return(rows)
  }
  lines <- readLines(src, warn = FALSE)
  # Find ^L-\d{3} headers (e.g. "## L-249 ..." or "L-249 ...")
  header_idx <- grep("^#{1,3}\\s*L-[0-9]{3}", lines)
  if (length(header_idx) == 0) {
    # Fallback: any line starting with L-NNN
    header_idx <- grep("^L-[0-9]{3}", lines)
  }
  for (i in seq_along(header_idx)) {
    start <- header_idx[i]
    end <- if (i < length(header_idx)) header_idx[i + 1] - 1 else length(lines)
    block <- lines[start:end]
    title <- trimws(gsub("^#+\\s*", "", lines[start]))
    body <- paste(block, collapse = "\n")
    m <- regmatches(title, regexec("L-([0-9]{3})", title))
    lcode_id <- if (length(m[[1]]) >= 2) paste0("L-", m[[1]][2]) else paste0("lcode-", i)
    rows <- emit_row(rows, id = lcode_id, type = "lcode",
                     title = title, body = body,
                     source_path = "qepm/memory/methodology_memory_v55_extensions.md",
                     tags = list("lcode"))
  }
  rows
}

build_axiom <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/active")
  if (!dir.exists(dir_path)) {
    warn_missing("axiom", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "^AX-.*\\.json$",
                        full.names = TRUE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                      error = function(e) NULL)
    if (is.null(data)) next
    ax_id <- data$memory_id %||% data$axiom_id %||% data$ax_code %||%
      tools::file_path_sans_ext(basename(f))
    title <- sprintf("%s — %s", ax_id,
                      data$canonical_statement %||% data$summary %||%
                        data$statement %||% data$text %||% "(no summary)")
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = ax_id, type = "axiom",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/axioms/active",
                                              basename(f)),
                     timestamp = data$promoted_at %||% data$created_at %||% NULL,
                     tags = list("axiom",
                                 data$memory_kind %||% "axiom_active",
                                 data$axiom_class %||% "",
                                 data$authority %||% "high",
                                 data$enforcement_mode %||% "",
                                 data$status %||% "active"))
  }
  rows
}

# ─── v7.2.1 신규 5 type ──────────────────────────────────────────

build_lesson <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/lessons")
  if (!dir.exists(dir_path)) {
    warn_missing("lesson", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "\\.json$", full.names = TRUE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(data)) next
    lid <- data$l_code %||% tools::file_path_sans_ext(basename(f))
    title <- sprintf("%s — %s", lid, data$title %||% "(no title)")
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = lid, type = "lesson",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/lessons",
                                             basename(f)),
                     timestamp = data$timestamp %||% NULL,
                     tags = list("lesson",
                                 data$category %||% "",
                                 data$grade %||% "",
                                 "authority:low"))
  }
  rows
}

build_axiom_candidate <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/candidates")
  if (!dir.exists(dir_path)) {
    warn_missing("axiom_candidate", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "\\.json$", full.names = TRUE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(data)) next
    cid <- data$memory_id %||% data$candidate_id %||%
      tools::file_path_sans_ext(basename(f))
    title <- sprintf("[CAND] %s — %s", cid,
                     data$canonical_statement %||% data$statement_draft %||%
                       "(no statement)")
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = cid, type = "axiom_candidate",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/axioms/candidates",
                                             basename(f)),
                     timestamp = data$created_at %||% NULL,
                     tags = list("axiom_candidate",
                                 data$axiom_class %||% "",
                                 data$status %||% "pending_5axis",
                                 "authority:medium"))
  }
  rows
}

build_axiom_deprecated <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/deprecated")
  if (!dir.exists(dir_path)) {
    warn_missing("axiom_deprecated", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "\\.json$", full.names = TRUE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(data)) next
    did <- data$memory_id %||% data$axiom_id %||% data$candidate_id %||%
      tools::file_path_sans_ext(basename(f))
    title <- sprintf("[DEPRECATED] %s — %s", did,
                     data$deprecation_reason %||% data$canonical_statement %||%
                       "(superseded)")
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = sprintf("dep-%s", did),
                     type = "axiom_deprecated",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/axioms/deprecated",
                                             basename(f)),
                     timestamp = data$deprecation_date %||%
                       data$created_at %||% NULL,
                     tags = list("axiom_deprecated",
                                 "authority:retired"))
  }
  rows
}

build_axiom_review <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/axioms/review_log")
  if (!dir.exists(dir_path)) {
    warn_missing("axiom_review", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "\\.json$", full.names = TRUE,
                       recursive = FALSE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(data)) next
    # 2026-07-25: review_log 필드명 실측 정합 (종전 = 소수파 필드만 조회).
    #   식별자: candidate_id 287 / axiom_id_candidate 6 / axiom 3 / axiom_id 2  (구 체인은 8/309만 커버)
    #   시각  : logged_at 288 / created_at 10 / generated_at 5 / reviewed_at 3 / 기타 4  (구 체인은 10/309)
    # 결과적으로 299/309(97%)가 timestamp NULL·제목 "(review log)"로 색인되고 있었다.
    rid <- data$memory_id %||% data$axiom_id_candidate %||% data$axiom_id %||%
      data$candidate_id %||% data$axiom %||%
      tools::file_path_sans_ext(basename(f))
    # 게이트-리뷰 로그(지배 스키마)는 purpose/status 가 없으므로 판정 요약으로 대체.
    verdict <- if (!is.null(data$all_hurdles_pass))
      sprintf("hurdles %s%s",
              if (isTRUE(data$all_hurdles_pass)) "PASS" else "FAIL",
              if (!is.null(data$weighted_score))
                sprintf(" (score %s)", format(data$weighted_score)) else "")
      else NULL
    title <- sprintf("[REVIEW] %s — %s", rid,
                     data$purpose %||% data$status %||% verdict %||% "(review log)")
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = sprintf("review-%s",
                                        tools::file_path_sans_ext(basename(f))),
                     type = "axiom_review",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/axioms/review_log",
                                             basename(f)),
                     timestamp = data$created_at %||% data$logged_at %||%
                       data$generated_at %||% data$reviewed_at %||%
                       data$decided_at %||% data$prepared_at %||%
                       data$timestamp %||% NULL,
                     tags = list("axiom_review",
                                 data$status %||% data$mode %||% "",
                                 "authority:audit"))
  }
  rows
}

build_evidence_summary <- function() {
  rows <- list()
  dir_path <- file.path(PROJ_ROOT, "qepm/memory/evidence_summary")
  if (!dir.exists(dir_path)) {
    warn_missing("evidence_summary", dir_path)
    return(rows)
  }
  for (f in list.files(dir_path, pattern = "\\.json$", full.names = TRUE)) {
    data <- tryCatch(fromJSON(f, simplifyVector = FALSE),
                     error = function(e) NULL)
    if (is.null(data)) next
    eid <- tools::file_path_sans_ext(basename(f))
    title <- sprintf("[EVIDENCE] %s", eid)
    body <- toJSON(data, auto_unbox = TRUE, pretty = FALSE)
    rows <- emit_row(rows, id = sprintf("ev-%s", eid),
                     type = "evidence_summary",
                     title = title, body = body,
                     source_path = file.path("qepm/memory/evidence_summary",
                                             basename(f)),
                     # 2026-07-25: timestamp 인자를 아예 넘기지 않아 319행 전부 무시각이었다.
                     # 실측 원천 필드 = summarized_at 210/250 · committed_at 40/250.
                     timestamp = data$summarized_at %||% data$committed_at %||%
                       data$created_at %||% NULL,
                     tags = list("evidence_summary", "authority:audit"))
  }
  rows
}

build_wt <- function() {
  rows <- list()
  wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) {
    warn_missing("wt", wt_root)
    return(rows)
  }
  for (d in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
    wt_id <- basename(d)
    req_path <- file.path(d, "request.json")
    sta_path <- file.path(d, "status.json")
    title <- wt_id
    body_parts <- c()
    ts <- NULL
    if (file.exists(req_path)) {
      req <- tryCatch(fromJSON(req_path, simplifyVector = FALSE),
                       error = function(e) NULL)
      if (!is.null(req)) {
        title <- sprintf("%s — %s",
                          wt_id, req$hypothesis_title %||%
                                  req$theme %||% "(no title)")
        body_parts <- c(body_parts,
                         req$hypothesis_description %||% "",
                         req$theme %||% "")
      }
    }
    if (file.exists(sta_path)) {
      sta <- tryCatch(fromJSON(sta_path, simplifyVector = TRUE),
                       error = function(e) NULL)
      if (!is.null(sta)) {
        body_parts <- c(body_parts,
                         sprintf("phase: %s", sta$current_phase %||% "?"))
        ts <- sta$updated_at %||% sta$created_at %||% NULL
      }
    }
    body <- paste(body_parts, collapse = " | ")
    rows <- emit_row(rows, id = wt_id, type = "wt",
                     title = title, body = body,
                     source_path = file.path("qepm/mailbox/worktask", wt_id),
                     wt_id = wt_id, timestamp = ts, tags = list("wt"))
  }
  rows
}

build_cert <- function() {
  rows <- list()
  wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) return(rows)
  for (d in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
    wt_id <- basename(d)
    for (cf in list.files(d, pattern = "_certificate\\.json$",
                           full.names = TRUE)) {
      data <- tryCatch(fromJSON(cf, simplifyVector = FALSE),
                        error = function(e) NULL)
      if (is.null(data)) next
      cert_type <- gsub("_certificate\\.json$", "", basename(cf))
      issued <- isTRUE(data$issued)
      title <- sprintf("[%s] %s — %s",
                        wt_id, cert_type,
                        if (issued) "ISSUED" else "NOT_ISSUED")
      body <- sprintf("issued=%s reason=%s",
                       data$issued %||% "?",
                       data$non_issuance_reason %||% "all_pass")
      rows <- emit_row(rows,
                        id = sprintf("%s-%s", wt_id, cert_type),
                        type = "cert",
                        title = title, body = body,
                        source_path = file.path("qepm/mailbox/worktask",
                                                 wt_id, basename(cf)),
                        wt_id = wt_id,
                        timestamp = data$issued_at %||% NULL,
                        tags = list("cert", cert_type,
                                    if (issued) "ISSUED" else "NOT_ISSUED"))
    }
  }
  rows
}

build_critic <- function() {
  rows <- list()
  wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  if (!dir.exists(wt_root)) return(rows)
  for (d in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
    wt_id <- basename(d)
    for (cf in list.files(d, pattern = "^codex_critic_response_.*\\.json$",
                           full.names = TRUE)) {
      data <- tryCatch(fromJSON(cf, simplifyVector = FALSE),
                        error = function(e) NULL)
      if (is.null(data)) next
      role <- data$agent_role %||% gsub(
        "^codex_critic_response_(.*)\\.json$", "\\1", basename(cf))
      stance <- data$stance %||% "?"
      title <- sprintf("[%s] codex %s — stance=%s", wt_id, role, stance)
      n_concerns <- length(data$critical_concerns %||% list())
      body <- sprintf("stance=%s n_concerns=%d weakest=%s",
                       stance, n_concerns,
                       data$weakest_assumption %||% "")
      rows <- emit_row(rows,
                        id = sprintf("%s-codex-%s", wt_id, role),
                        type = "critic",
                        title = title, body = body,
                        source_path = file.path("qepm/mailbox/worktask",
                                                 wt_id, basename(cf)),
                        wt_id = wt_id,
                        # 2026-07-25: reviewed_at 은 실제 산출물에 없는 필드였다(0/315).
                        # 실측 원천 필드 = timestamp 186 · generated_at 2 · executed_at 1.
                        timestamp = data$reviewed_at %||% data$timestamp %||%
                          data$generated_at %||% data$executed_at %||% NULL,
                        tags = list("critic", role, stance))
    }
  }
  rows
}

build_governance <- function(event_cap = 50000L) {
  rows <- list()
  paths <- character()
  wt_root <- file.path(PROJ_ROOT, "qepm/mailbox/worktask")
  if (dir.exists(wt_root)) {
    for (d in list.dirs(wt_root, full.names = TRUE, recursive = FALSE)) {
      gp <- file.path(d, "governance_log.json")
      if (file.exists(gp)) paths <- c(paths, gp)
    }
  }
  global_gov <- file.path(PROJ_ROOT, "qepm/mailbox/governor/governance_log.json")
  if (file.exists(global_gov)) paths <- c(paths, global_gov)

  total_events <- 0L
  malformed <- 0L
  for (p in paths) {
    if (total_events >= event_cap) break
    fsize <- file.info(p)$size
    if (!is.na(fsize) && fsize > 100 * 1024 * 1024) {
      # Chunk fallback (현 단계 미발동 — 100MB+ governance_log 부재)
      next
    }
    data <- tryCatch(fromJSON(p, simplifyVector = FALSE),
                      error = function(e) NULL)
    if (is.null(data) || is.null(data$events)) next
    is_global <- identical(p, global_gov)
    wt_id <- if (is_global) NULL else basename(dirname(p))
    for (e in data$events) {
      if (total_events >= event_cap) break
      total_events <- total_events + 1L
      ts <- e$timestamp %||% ""
      action <- e$action %||% "?"
      summary <- e$summary %||% e$directive_quote %||% ""
      tryCatch({
        title <- sprintf("[%s] %s — %s",
                          wt_id %||% "global", action,
                          substr(summary, 1, 80))
        body <- sprintf("action=%s agent=%s summary=%s",
                         action, e$agent %||% "?", summary)
        row_id <- sprintf("%s-event-%s",
                           wt_id %||% "global",
                           gsub("[^0-9]", "", ts %||% "0"))
        if (!nzchar(row_id) || nchar(row_id) < 5) {
          row_id <- sprintf("%s-event-%d",
                             wt_id %||% "global", total_events)
        }
        rows <- emit_row(rows, id = row_id, type = "governance",
                          title = title, body = body,
                          source_path = sub(paste0(PROJ_ROOT, "/?"),
                                             "", p),
                          wt_id = wt_id,
                          timestamp = ts,
                          tags = list("governance", action))
      }, error = function(err) {
        malformed <<- malformed + 1L
      })
    }
  }
  if (malformed > 0) {
    source_warnings <<- c(source_warnings,
                            sprintf("[GOVERNANCE] skipped %d malformed events",
                                    malformed))
  }
  attr(rows, "event_count") <- total_events
  rows
}

build_registry <- function() {
  rows <- list()
  reg_dir <- file.path(PROJ_ROOT, "06_Registry")
  if (!dir.exists(reg_dir)) {
    warn_missing("registry", reg_dir)
    return(rows)
  }
  for (rf in list.files(reg_dir, pattern = "\\.json$",
                          full.names = TRUE)) {
    reg_name <- tools::file_path_sans_ext(basename(rf))
    data <- tryCatch(fromJSON(rf, simplifyVector = FALSE),
                      error = function(e) NULL)
    if (is.null(data)) next
    items <- data
    # registry는 list 또는 nested object — best-effort flatten
    if (is.list(data) && !is.null(names(data))) {
      candidates <- names(data)
      # if there's a top-level "strategies" / "ideas" / "papers" key, drill
      for (k in c("strategies", "ideas", "papers", "items", "registry")) {
        if (k %in% candidates && is.list(data[[k]])) {
          items <- data[[k]]
          break
        }
      }
    }
    if (is.list(items) && length(items) > 0) {
      for (idx in seq_along(items)) {
        it <- items[[idx]]
        if (!is.list(it)) next
        item_id <- it$id %||% it$str_id %||% it$paper_id %||%
                    it$idea_id %||% names(items)[idx] %||%
                    sprintf("%s-%d", reg_name, idx)
        title <- it$name %||% it$title %||% it$strategy_name %||%
                  it$hypothesis %||% paste(reg_name, item_id)
        body <- toJSON(it, auto_unbox = TRUE, pretty = FALSE)
        # [2026-07-25] 조회 체인 확장 — 종전 3필드(created_at/updated_at/registered_at)는
        # 06_Registry 생산자들이 실제로 쓰는 이름과 어긋나 1451행 중 3행만 시각을 얻었다.
        # ★"원천에 시각 필드 부재"라는 앞선 진단은 오측정이었다 — 필드명 불일치가 원인.
        # 값-유효(문자열 "None"·빈값 제외) 기준 실측:
        #   hypothesis_index date 965/965 · distilled_knowledge created_at 89/89 ·
        #   paper_registry date_added 211/458 · strategy_registry committed_at 86+created 16 = 114/389 ·
        #   idea_registry date_added 23+date_found 13 = 23/62 · frontier_queue verdict_date 7/73
        # ※키 존재 수로 세면 paper_registry가 458/458로 보인다(값이 "None" 문자열) — 키 카운트는
        #   커버리지 지표가 아니다. 진짜 부재는 strategy_grades(257, 15키 전부 성과지표)뿐.
        ts <- it$created_at %||% it$updated_at %||% it$registered_at %||%
               it$date_added %||% it$committed_at %||% it$created %||%
               it$date_found %||% it$date %||% it$logged_at %||%
               it$approved_at %||% it$verdict_date %||% NULL
        tag_list <- list("registry", reg_name)
        if (!is.null(it$grade)) tag_list <- c(tag_list, it$grade)
        rows <- emit_row(rows,
                          id = sprintf("%s-%s", reg_name, item_id),
                          type = "registry",
                          title = title, body = body,
                          source_path = file.path("06_Registry",
                                                    basename(rf)),
                          timestamp = ts,
                          tags = tag_list)
      }
    }
  }
  rows
}

build_paper <- function() {
  rows <- list()
  pn_dir <- file.path(PROJ_ROOT, "04_Research/paper_notes")
  if (!dir.exists(pn_dir)) {
    warn_missing("paper", pn_dir)
    return(rows)
  }
  # [2026-07-25] 시각 원천 2경로 (종전엔 timestamp 인자를 아예 안 넘겨 198행 전부 무시각).
  #   ① 노트 front-matter `registered_at:` — 신규 노트 등재 규약(소급 채우기 안 함)
  #   ② paper_registry.json 의 date_added 상속 (id = P### 로 1:1, 노트 198/198 매칭됨)
  # ★현 시점 실효 = 0/198: 노트 보유 P001~ 구간은 registry date_added 가 값 "None" 이고
  #   값-유효 211건은 노트가 없는 후기 논문이다(실측). 즉 이 배선은 **신규분부터** 효력이
  #   생긴다 — 지금 커버리지가 오르지 않는다고 배선이 틀린 게 아니며, 반대로 "고쳤다"고
  #   보고할 근거도 아니다. 자기진단이 실제 수치로 계속 신고한다.
  .paper_reg_dates <- tryCatch({
    rp <- file.path(PROJ_ROOT, "06_Registry/paper_registry.json")
    if (!file.exists(rp)) list() else {
      pr <- fromJSON(rp, simplifyVector = FALSE)
      pr <- if (!is.null(names(pr))) pr else pr
      out <- list()
      for (it in pr) {
        if (!is.list(it)) next
        v <- it$date_added %||% it$registered_at %||% NULL
        s <- if (is.null(v)) "" else trimws(as.character(v))
        if (nzchar(s) && !s %in% c("None", "none", "null", "NA", "-"))
          out[[as.character(it$id)]] <- s
      }
      out
    }
  }, error = function(e) list())
  for (pf in list.files(pn_dir, pattern = "^P[0-9]+.*\\.md$",
                          full.names = TRUE, recursive = FALSE)) {
    lines <- tryCatch(readLines(pf, warn = FALSE, n = 30),
                       error = function(e) character())
    title <- basename(pf)
    for (l in lines) {
      if (grepl("^#\\s+", l)) {
        title <- trimws(gsub("^#+\\s*", "", l))
        break
      }
    }
    full <- tryCatch(readLines(pf, warn = FALSE),
                      error = function(e) character())
    body <- substr(paste(full, collapse = " "), 1, 500)
    paper_id <- sub("^(P[0-9]+).*", "\\1", basename(pf))
    # front-matter `registered_at:` 우선 → 없으면 paper_registry date_added 상속
    ts <- NULL
    fm <- grep("^\\s*registered_at\\s*:", lines, value = TRUE)
    if (length(fm) > 0) {
      cand <- trimws(sub("^\\s*registered_at\\s*:\\s*", "", fm[1]))
      cand <- gsub('^["\']|["\']$', "", cand)
      if (nzchar(cand)) ts <- cand
    }
    if (is.null(ts)) ts <- .paper_reg_dates[[paper_id]] %||% NULL
    rows <- emit_row(rows, id = paper_id, type = "paper",
                      title = title, body = body,
                      source_path = file.path("04_Research/paper_notes",
                                                basename(pf)),
                      timestamp = ts,
                      tags = list("paper"))
  }
  rows
}

build_lawbook <- function() {
  rows <- list()
  lb_dir <- file.path(PROJ_ROOT, "00_Lawbook")
  if (!dir.exists(lb_dir)) {
    warn_missing("lawbook", lb_dir)
    return(rows)
  }
  for (lf in list.files(lb_dir, pattern = "\\.md$",
                          full.names = TRUE, recursive = TRUE)) {
    rel <- sub(paste0(PROJ_ROOT, "/?"), "", lf)
    full <- tryCatch(readLines(lf, warn = FALSE),
                      error = function(e) character())
    title <- basename(lf)
    for (l in full[1:min(10, length(full))]) {
      if (grepl("^#\\s+", l)) {
        title <- trimws(gsub("^#+\\s*", "", l))
        break
      }
    }
    body <- substr(paste(full, collapse = " "), 1, 1000)
    rows <- emit_row(rows,
                      id = sprintf("lawbook-%s", tools::file_path_sans_ext(basename(lf))),
                      type = "lawbook",
                      title = title, body = body,
                      source_path = rel,
                      tags = list("lawbook"))
  }
  rows
}

# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────

cat("=== build_index.R v7.1-lite Sprint 1.1 ===\n")
cat(sprintf("PROJ_ROOT: %s\n", PROJ_ROOT))
cat(sprintf("DRY_RUN: %s | INCLUDE_EXAMPLES: %s\n", DRY_RUN, INCLUDE_EXAMPLES))
cat("\n")

all_rows <- list()
sources <- list(
  list(name = "lcode", fn = build_lcode),
  list(name = "axiom", fn = build_axiom),
  list(name = "axiom_candidate", fn = build_axiom_candidate),
  list(name = "axiom_deprecated", fn = build_axiom_deprecated),
  list(name = "axiom_review", fn = build_axiom_review),
  list(name = "lesson", fn = build_lesson),
  list(name = "evidence_summary", fn = build_evidence_summary),
  list(name = "wt", fn = build_wt),
  list(name = "cert", fn = build_cert),
  list(name = "critic", fn = build_critic),
  list(name = "governance", fn = build_governance),
  list(name = "registry", fn = build_registry),
  list(name = "paper", fn = build_paper),
  list(name = "lawbook", fn = build_lawbook)
)

counts <- list()
for (s in sources) {
  rs <- tryCatch(s$fn(), error = function(e) {
    source_warnings <<- c(source_warnings,
                            sprintf("[ERROR] %s — %s",
                                    s$name, conditionMessage(e)))
    list()
  })
  counts[[s$name]] <- length(rs)
  all_rows <- c(all_rows, rs)
  cat(sprintf("  %s: %d rows\n", s$name, length(rs)))
}

cat(sprintf("\nTotal: %d rows\n", length(all_rows)))

if (length(source_warnings) > 0) {
  cat("\n=== WARNING SUMMARY ===\n")
  for (w in source_warnings) cat(sprintf("  %s\n", w))
}

if (DRY_RUN) {
  cat("\n[DRY RUN] no write\n")
  quit(status = 0)
}

# Write JSONL
# [2026-07-25] 최상위 on.exit(close(con)) 제거 — r-portability 금칙 ② 실사례.
#   `Rscript build_index.R`(진짜 최상위)에서는 on.exit 가 no-op 이라 무해했으나,
#   프로젝트 표준 실행 경로인 `source()` 로 돌리면 on.exit 가 source() 내부 프레임에
#   등록돼 **그 표현식 직후 즉시 발화** → 연결이 닫힌 뒤 writeLines 가
#   "invalid connection" 으로 죽었다(실측: 3509행 집계까지 정상 → 쓰기에서 halt).
#   즉 실행 방식에 따라 결과가 갈리는 상태였다. 명시 close() 로 교체 + 실패 시에도
#   닫히도록 tryCatch(finally=) 사용.
dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
con <- file(OUT_PATH, "w", encoding = "UTF-8")
tryCatch({
  for (r in all_rows) {
    writeLines(toJSON(r, auto_unbox = TRUE, null = "null"), con)
  }
}, finally = close(con))

cat(sprintf("\n[OK] index written: %s (%d rows)\n",
            OUT_PATH, length(all_rows)))

# ── 자기진단: type 별 timestamp 커버리지 (2026-07-25 신설) ────────────────────
# 배경: axiom_review 가 created_at 만 조회해 309건 중 299건(97%)을 timestamp 없이
# 색인해 왔는데, 생산자는 logged_at 을 쓰고 있었다. 필드명 불일치는 **조용히** 빈 값을
# 만들 뿐 오류를 내지 않으므로 감지 장치가 없으면 무기한 방치된다(실제로 그랬다).
# 소비자가 자기 눈먼 구간을 스스로 신고하게 한다. 판정 불차단(경고만).
.ts_cov <- list()
for (r in all_rows) {
  ty <- r$type %||% "?"
  prev <- .ts_cov[[ty]] %||% c(0, 0)
  .ts_cov[[ty]] <- c(prev[1] + 1, prev[2] + as.integer(!is.null(r$timestamp) &&
                                                        nzchar(as.character(r$timestamp))))
}
# [2026-07-25] 시각 개념이 설계상 없는 type = 면제. 단 **조용히 빼지 않고 명시 보고**한다 —
# 오탐 제거와 검사 사망은 겉보기가 같아서, 면제분을 숨기면 나중에 "왜 안 잡혔나"를 되물을 수
# 없다. 면제 근거는 여기 적힌 것이 전부이며, 새 type 을 면제에 넣으려면 근거를 함께 적을 것.
#   lawbook = 00_Lawbook/**.md 법령 문서. 등재(registration) 사건 자체가 없고 파일 mtime 은
#             편집 시각이라 연구/등재 시각의 대리가 될 수 없다(금일 W8/W9 mtime 오측정 계열).
.TS_EXEMPT <- c(lawbook = "법령 md — 등재 사건 부재, mtime은 시각 대리 불가")

# 구조적 하한이 있는 type = 절대 임계(50%) 대신 **회귀 감시**로 판정한다.
# 이유: 하한 때문에 절대 기준을 영원히 못 넘으면 WARN 이 매번 울려 경보 피로가 되고,
# 그러면 진짜 신규 결손이 소음에 묻힌다(= 감시가 조용히 무의미해지는 계열).
# 그렇다고 면제하면 회귀를 못 잡으므로, **떨어지면 잡는다**로 바꾼다(suite_totals_watch 원칙).
.TS_FLOOR <- c(
  registry = paste0("구조적 하한: strategy_grades 257(2026-06-08 이후 동결·writer 부재) + ",
                    "paper_registry 역사분 date_added=\"None\" 247(소급 채우기 안 함 — 도훈 방침) + ",
                    "strategy_registry 역사분. 신규 등재는 date_added/committed_at 로 정상 유입")
)
.TS_BASE_PATH <- file.path(PROJ_ROOT, ".cache/search_index_ts_coverage.json")
.ts_prev <- tryCatch(
  if (file.exists(.TS_BASE_PATH)) fromJSON(.TS_BASE_PATH, simplifyVector = FALSE) else list(),
  error = function(e) list())

low <- character(0); exempt <- character(0); regressed <- character(0); floors <- character(0)
.ts_now <- list()
for (ty in names(.ts_cov)) {
  n <- .ts_cov[[ty]][1]; k <- .ts_cov[[ty]][2]
  .ts_now[[ty]] <- list(n = n, k = k, pct = round(100 * k / max(n, 1), 1))
  if (n < 20) next
  pct <- k / n
  if (ty %in% names(.TS_EXEMPT)) {
    exempt <- c(exempt, sprintf("%s %d/%d — %s", ty, k, n, .TS_EXEMPT[[ty]]))
    next
  }
  # 회귀 판정 (모든 type 공통): 직전 대비 절대 커버리지 2%p 이상 하락 = 신규 결손 의심
  pv <- .ts_prev[[ty]]
  if (!is.null(pv) && !is.null(pv$pct) && (pct * 100) < (as.numeric(pv$pct) - 2))
    regressed <- c(regressed, sprintf("%s %.0f%%→%.0f%%", ty, as.numeric(pv$pct), pct * 100))
  if (ty %in% names(.TS_FLOOR)) {
    floors <- c(floors, sprintf("%s %d/%d(%.0f%%) — %s", ty, k, n, pct * 100, .TS_FLOOR[[ty]]))
  } else if (pct < 0.5) {
    low <- c(low, sprintf("%s %d/%d(%.0f%%)", ty, k, n, pct * 100))
  }
}
if (length(regressed) > 0)
  cat(sprintf("[WARN] timestamp 커버리지 회귀 — 직전 실행 대비 하락(신규 결손 의심): %s\n",
              paste(regressed, collapse = " · ")))
if (length(low) > 0) {
  cat(sprintf("[WARN] timestamp 커버리지 저조 — 생산자 필드명과 조회 체인 불일치 의심: %s\n",
              paste(low, collapse = " · ")))
} else if (length(regressed) == 0) {
  cat("[OK] timestamp 커버리지 정상 (회귀 없음 · 하한/면제 type 제외 전부 >=50%)\n")
}
if (length(floors) > 0)
  cat(sprintf("[INFO] 하한 type (회귀 감시로 판정): %s\n", paste(floors, collapse = " · ")))
if (length(exempt) > 0)
  cat(sprintf("[INFO] 시각 면제 type (설계상 부재 — 은폐 아님): %s\n",
              paste(exempt, collapse = " · ")))
tryCatch(write(toJSON(.ts_now, auto_unbox = TRUE, pretty = TRUE), .TS_BASE_PATH),
         error = function(e) cat("[WARN] 커버리지 기준선 기록 실패:", conditionMessage(e), "\n"))
