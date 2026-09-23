# axiom_rollback.R — 공리 롤백 (v8.0 INV-3 안전망)
#
# rollback_axiom(ax_id): active→deprecated + 마커 블록을 전 타겟(CLAUDE.md + 9 prompts)에서 삭제.
# inject.R의 simulated additions-only diff 역적용이 아니라, axiom_id 마커 블록 직접 삭제
# (review.R 마커 로직과 동형) — 완전 복원. mode-local/global 모두 지원.
#
# Usage: Rscript axiom_rollback.R AX-AS-001 [--apply]
suppressPackageStartupMessages({ library(jsonlite) })

.rb_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
             Sys.getenv("QVEST_PROJECT_DIR", ""), Sys.getenv("PROJECT_ROOT", ""), getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# ── 원자적 JSON 쓰기 (2026-09-23) — 정본 = 02_Infrastructure/utils/atomic_json.R::qvest_atomic_write_json.
#   promote.R::.px_write_json 과 같은 적재 규약(root → QM_ROOT → CLAUDE_PROJECT_DIR). 못 찾으면 stop()
#   (비원자 강등 안 함). 직렬화 인자는 이 파일의 기존 write_json 호출과 같다 — 형식 불변.
.RB_ATOMIC <- new.env(parent = emptyenv())
.rb_write_json <- function(obj, path, root = NULL) {
  fn <- .RB_ATOMIC$fn
  if (is.null(fn)) {
    cands <- unique(Filter(nzchar, c(if (!is.null(root)) as.character(root)[1] else "",
                                     Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""))))
    src <- NA_character_
    for (r in cands) {
      p <- file.path(gsub("\\\\", "/", r), "02_Infrastructure", "utils", "atomic_json.R")
      if (file.exists(p)) { src <- p; break }
    }
    if (is.na(src)) stop("[rollback] atomic_json.R 를 찾지 못함 — 원자 쓰기 불가: ", paste(cands, collapse = " | "))
    e <- new.env(parent = globalenv()); sys.source(src, envir = e)
    fn <- e$qvest_atomic_write_json; .RB_ATOMIC$fn <- fn
  }
  fn(obj, path, pretty = TRUE, auto_unbox = TRUE, null = "null", tag = "rollback")
}

# ### AX-ID 헤더 블록 + 마커 내 단일 줄 삭제
.remove_axiom_block <- function(file_path, ax_id, apply) {
  if (!file.exists(file_path)) return(0L)
  raw <- readLines(file_path, warn = FALSE, encoding = "UTF-8")
  drop <- integer(0)
  hdr <- grep(sprintf("^###\\s+%s\\b", ax_id), raw, perl = TRUE)
  if (length(hdr)) {
    s <- hdr[1]
    nxt <- grep("^(###|##|<!-- AXIOM)", raw, perl = TRUE); nxt <- nxt[nxt > s]
    e <- if (length(nxt)) nxt[1] - 1L else length(raw)
    drop <- c(drop, s:e)
  }
  line_hits <- grep(sprintf("\\b%s\\b", ax_id), raw, perl = TRUE)  # 마커 내 - AX-ID 줄
  drop <- sort(unique(c(drop, line_hits)))
  if (!length(drop)) return(0L)
  if (isTRUE(apply)) {
    writeLines(raw[-drop], file_path, useBytes = TRUE)
    cat(sprintf("  [rollback] %s: %d줄 제거 ← %s\n", ax_id, length(drop), basename(file_path)))
  } else {
    cat(sprintf("  [rollback][dry-run] %s: %d줄 제거 예정 ← %s\n", ax_id, length(drop), basename(file_path)))
  }
  length(drop)
}

# ── v9.1 커밋14 (2026-08-23): tombstone 을 **같은 트랜잭션**으로 남긴다 ───────
# 왜 필수인가: promote.R::.promote_to_active 의 멱등 검사는 `active/modes/**` 만 스캔한다.
#   롤백은 파일을 `deprecated/` 로 옮기므로, 그 다음 주 스윕이 같은 클러스터를 **새 번호로
#   재발급**한다(AX-AS-001 롤백 → 다음 주 AX-AS-003 부활). tombstone 이 없으면 롤백은
#   1주일짜리 임시조치다. promote.R 이 tombstones.json 을 소비해 SKIP_TOMBSTONED 로 멈춘다.
# `reason` 은 **필수 인자**다 — 사유 없는 tombstone 은 해제 판단의 근거를 남기지 않는다.
# `revive_condition` 은 INV-7 정신: 영구 금지가 아니라 **조건부 보류**임을 명시한다
#   (해제 = promote.R::clear_tombstone(cluster_key, reason=)).
# ── 2026-09-23 `release_backlinks` (기본 TRUE = 구 동작 불변) ─────────────────────
#   FALSE 면 L-code 원장 파일(stage_artifacts/**/l_code_*.json)의 promoted_to_axiom 역링크를 **건드리지 않는다**.
#   근거: Axiom 전수감사 판정서 ⑤ "폐기는 삭제가 아니다 — deprecated/ + tombstone, 근거 L-code(원장)는 건드리지 않는다"
#   (도훈 AX-D3). 남는 역링크는 롤백된 공리 id 를 가리키는 **사료**이고, 그 공리는 deprecated/ + tombstone 으로
#   추적된다(harvester 는 promoted 여부를 active/ 에서 재도출하므로 이 필드를 소비하지 않는다).
#   deprecated 사본에 rollback_backlinks_released 를 남겨 어느 쪽이었는지 기록한다.
rollback_axiom <- function(ax_id, apply = FALSE, reason, revive_condition = NULL, release_backlinks = TRUE) {
  if (missing(reason) || !nzchar(as.character(reason)[1]))
    stop("rollback_axiom: reason 필수 — usage: rollback_axiom(\"AX-AS-001\", apply=TRUE, reason=\"...\", revive_condition=NULL)")
  root <- .rb_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  hits <- list.files(active_dir, pattern = sprintf("^%s\\.json$", ax_id), full.names = TRUE, recursive = TRUE)
  if (!length(hits)) { cat(sprintf("[rollback] %s active에 없음\n", ax_id)); return(invisible(NULL)) }
  ax_path <- hits[1]
  axiom <- fromJSON(ax_path, simplifyVector = FALSE)

  # 1) 마커 블록 삭제: CLAUDE.md + 5 prompts (v10 2026-09-03: governor/execution/monitoring/qlead 는 _retired_v10 이동)
  prompts <- c("alpha_research_init.md", "risk_research_init.md", "optimizer_research_init.md",
               "forge_init.md", "judge_init.md")
  targets <- c(file.path(root, "CLAUDE.md"), file.path(root, "02_Infrastructure", "prompts", prompts))
  total <- 0L
  for (t in targets) total <- total + .remove_axiom_block(t, ax_id, apply)

  # 2) active → deprecated + back-link 해제
  if (isTRUE(apply)) {
    dep_dir <- file.path(root, "qepm", "memory", "axioms", "deprecated")
    dir.create(dep_dir, recursive = TRUE, showWarnings = FALSE)
    axiom$status <- "rolled_back"
    axiom$rolled_back_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    axiom$rollback_reason <- as.character(reason)[1]
    if (!is.null(revive_condition)) axiom$revive_condition <- as.character(revive_condition)[1]
    axiom$rollback_backlinks_released <- isTRUE(release_backlinks)
    dst <- file.path(dep_dir, sprintf("%s_rollback_%s.json", ax_id, format(Sys.Date(), "%Y%m%d")))
    if (file.exists(dst)) stop(sprintf("[rollback] %s 이미 존재 — 같은 날 재롤백은 덮어쓰지 않는다(사료 보존)", dst))
    .rb_write_json(axiom, dst, root = root)
    file.remove(ax_path)
    # ★tombstone = 이동과 **같은 트랜잭션**. 이 줄이 빠지면 다음 주 스윕이 같은 클러스터를
    #   새 번호로 재발급한다(무인 승격에서는 사람이 그걸 볼 기회조차 없다).
    .rb_append_tombstone(root,
      cluster_key = as.character(axiom$cluster_key %||% "")[1],
      axiom_id = ax_id,
      source_candidate = as.character(axiom$promotion$source_candidate %||% "")[1],
      reason = reason, revive_condition = revive_condition)
    # sot_map entry 제거 (INV-3 완전 복원 — orphan 방지)
    sp <- file.path(root, "qepm", "memory", "axioms", "axiom_sot_map.json")
    if (file.exists(sp)) {
      sot <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(sot) && !is.null(sot$axioms)) {
        before <- length(sot$axioms)
        sot$axioms <- Filter(function(a) (a$axiom_id %||% "") != ax_id, sot$axioms)
        if (length(sot$axioms) < before) {
          .rb_write_json(sot, sp, root = root)
          cat(sprintf("  [rollback] sot_map -= %s\n", ax_id))
        }
      }
    }
    # back-link 해제 (release_backlinks=FALSE 면 원장 L-code 무접촉 — 위 머리말 참조)
    if (!isTRUE(release_backlinks))
      cat(sprintf("  [rollback] %s: L-code 역링크 무접촉(release_backlinks=FALSE — 원장 불변)\n", ax_id))
    for (lc in (if (isTRUE(release_backlinks)) axiom$supporting_l_codes %||% character(0) else character(0))) {
      lf <- list.files(file.path(root, "stage_artifacts"), pattern = "^l_code_.*\\.json$",
                       full.names = TRUE, recursive = TRUE)
      for (f in lf) { d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(d) && identical(d$promoted_to_axiom, ax_id)) {
          d$promoted_to_axiom <- NULL
          d$rollback_note <- sprintf("%s rolled back %s", ax_id, axiom$rolled_back_at)
          write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null"); break } }
    }
    cat(sprintf("[rollback] %s → deprecated/%s (%d줄 복원) | tombstone 기록 (cluster_key=%s)\n",
                ax_id, basename(dst), total, as.character(axiom$cluster_key %||% "?")[1]))
  } else {
    cat(sprintf("[rollback] dry-run: %s would rollback (%d줄 제거 예정) + tombstone append 예정 (cluster_key=%s, reason=%s). --apply로 실행.\n",
                ax_id, total, as.character(axiom$cluster_key %||% "?")[1], as.character(reason)[1]))
  }
  invisible(list(ax_id = ax_id, lines_removed = total, applied = isTRUE(apply),
                 cluster_key = as.character(axiom$cluster_key %||% "")[1],
                 reason = as.character(reason)[1],
                 backlinks_released = isTRUE(release_backlinks)))
}

# tombstones.json append — promote.R::.tombstone_load 와 **같은 스키마**여야 한다
#   (생산자/소비자가 다른 파일에 있으므로 필드명을 여기 한 곳에서만 바꾸면 조용히 갈라진다).
.rb_append_tombstone <- function(root, cluster_key, axiom_id, source_candidate, reason,
                                 revive_condition = NULL) {
  p <- file.path(root, "qepm", "memory", "axioms", "tombstones.json")
  d <- if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL) else NULL
  if (is.null(d) || is.null(d$entries)) d <- list(schema_version = "v1_axiom_tombstone", entries = list())
  d$entries[[length(d$entries) + 1L]] <- list(
    cluster_key = as.character(cluster_key %||% "")[1],
    axiom_id = as.character(axiom_id)[1],
    rolled_back_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    source_candidate = as.character(source_candidate %||% "")[1],
    reason = as.character(reason)[1],
    revive_condition = if (is.null(revive_condition)) NULL else as.character(revive_condition)[1],
    cleared = FALSE)
  d$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  .rb_write_json(d, p, root = root)
  cat(sprintf("  [rollback] tombstone += %s (cluster_key=%s)%s\n", axiom_id,
              as.character(cluster_key %||% "?")[1],
              if (is.null(revive_condition)) "" else sprintf(" | 부활 조건: %s", revive_condition)))
  invisible(p)
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .a <- commandArgs(trailingOnly = TRUE)
  apply <- "--apply" %in% .a
  .reason <- sub("^--reason=", "", grep("^--reason=", .a, value = TRUE))
  .revive <- sub("^--revive=", "", grep("^--revive=", .a, value = TRUE))
  .a <- .a[!startsWith(.a, "--")]
  if (!length(.reason) || !nzchar(.reason[1]))
    stop("usage: Rscript axiom_rollback.R <AX-ID> --reason=\"...\" [--revive=\"...\"] [--apply]")
  .keep_bl <- "--keep-backlinks" %in% commandArgs(trailingOnly = TRUE)   # 2026-09-23: 원장 L-code 무접촉
  if (length(.a)) invisible(rollback_axiom(.a[1], apply = apply, reason = .reason[1],
                                           revive_condition = if (length(.revive)) .revive[1] else NULL,
                                           release_backlinks = !.keep_bl))
}
cat("[axiom_rollback] Loaded. rollback_axiom(ax_id, apply=FALSE, reason=, revive_condition=NULL, release_backlinks=TRUE) — reason 필수\n")
