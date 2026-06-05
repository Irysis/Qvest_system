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

rollback_axiom <- function(ax_id, apply = FALSE) {
  root <- .rb_root()
  active_dir <- file.path(root, "qepm", "memory", "axioms", "active")
  hits <- list.files(active_dir, pattern = sprintf("^%s\\.json$", ax_id), full.names = TRUE, recursive = TRUE)
  if (!length(hits)) { cat(sprintf("[rollback] %s active에 없음\n", ax_id)); return(invisible(NULL)) }
  ax_path <- hits[1]
  axiom <- fromJSON(ax_path, simplifyVector = FALSE)

  # 1) 마커 블록 삭제: CLAUDE.md + 9 prompts
  prompts <- c("alpha_research_init.md", "risk_research_init.md", "optimizer_research_init.md",
               "forge_init.md", "judge_init.md", "governor_init.md",
               "execution_init.md", "monitoring_init.md", "qlead_init.md")
  targets <- c(file.path(root, "CLAUDE.md"), file.path(root, "02_Infrastructure", "prompts", prompts))
  total <- 0L
  for (t in targets) total <- total + .remove_axiom_block(t, ax_id, apply)

  # 2) active → deprecated + back-link 해제
  if (isTRUE(apply)) {
    dep_dir <- file.path(root, "qepm", "memory", "axioms", "deprecated")
    dir.create(dep_dir, recursive = TRUE, showWarnings = FALSE)
    axiom$status <- "rolled_back"
    axiom$rolled_back_at <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    dst <- file.path(dep_dir, sprintf("%s_rollback_%s.json", ax_id, format(Sys.Date(), "%Y%m%d")))
    write_json(axiom, dst, pretty = TRUE, auto_unbox = TRUE, null = "null")
    file.remove(ax_path)
    # sot_map entry 제거 (INV-3 완전 복원 — orphan 방지)
    sp <- file.path(root, "qepm", "memory", "axioms", "axiom_sot_map.json")
    if (file.exists(sp)) {
      sot <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
      if (!is.null(sot) && !is.null(sot$axioms)) {
        before <- length(sot$axioms)
        sot$axioms <- Filter(function(a) (a$axiom_id %||% "") != ax_id, sot$axioms)
        if (length(sot$axioms) < before) {
          write_json(sot, sp, pretty = TRUE, auto_unbox = TRUE, null = "null")
          cat(sprintf("  [rollback] sot_map -= %s\n", ax_id))
        }
      }
    }
    # back-link 해제
    for (lc in (axiom$supporting_l_codes %||% character(0))) {
      lf <- list.files(file.path(root, "stage_artifacts"), pattern = "^l_code_.*\\.json$",
                       full.names = TRUE, recursive = TRUE)
      for (f in lf) { d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
        if (!is.null(d) && identical(d$promoted_to_axiom, ax_id)) {
          d$promoted_to_axiom <- NULL
          d$rollback_note <- sprintf("%s rolled back %s", ax_id, axiom$rolled_back_at)
          write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null"); break } }
    }
    cat(sprintf("[rollback] %s → deprecated/%s (%d줄 복원)\n", ax_id, basename(dst), total))
  } else {
    cat(sprintf("[rollback] dry-run: %s would rollback (%d줄 제거 예정). --apply로 실행.\n", ax_id, total))
  }
  invisible(list(ax_id = ax_id, lines_removed = total, applied = isTRUE(apply)))
}

if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .a <- commandArgs(trailingOnly = TRUE)
  apply <- "--apply" %in% .a; .a <- setdiff(.a, "--apply")
  if (length(.a)) invisible(rollback_axiom(.a[1], apply = apply))
}
cat("[axiom_rollback] Loaded. rollback_axiom(ax_id, apply=FALSE)\n")
