# Sprint 4 AX-P1: CLAUDE.md + prompts/ Axiom Injector
# 승격된 axiom을 CLAUDE.md `## Axioms` 섹션과 prompts/*_init.md
# `<!-- AXIOM_INJECT -->` 마크업에 자동 주입.
#
# 안전장치:
#   1) .cache/axiom_inject_<AX>_<ts>.diff 자동 생성 (roll-back 가능)
#   2) QVEST_AXIOM_AUTO_INJECT=0 이면 dry-run
#   3) 중복 주입 방지 (AX-ID 검색)
#
# Usage:
#   source("02_Infrastructure/axiom/inject.R")
#   inject_axiom("qepm/memory/axioms/active/AX-003.json")
#
# Env:
#   QVEST_AXIOM_AUTO_INJECT=1 : real write
#   QVEST_AXIOM_AUTO_INJECT=0 : dry-run (default)

suppressPackageStartupMessages({
  library(jsonlite)
})

.ij_root <- function() {
  cands <- c(
    Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
    Sys.getenv("QVEST_PROJECT_DIR", ""),
    Sys.getenv("PROJECT_ROOT", ""),
    getwd()
  )
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 ||
                             (length(a) == 1 && is.na(a))) b else a

# ─── Axiom block formatter ──────────────────────────────────────────
.format_block <- function(axiom) {
  ax_id <- axiom$axiom_id
  stmt <- axiom$statement %||% "(no statement)"
  scope <- axiom$scope %||% list()
  ev <- axiom$evidence %||% list()
  fa <- axiom$falsification %||% list()
  oo <- axiom$oos_validation %||% list()
  me <- axiom$mechanism %||% list()
  pr <- axiom$promotion %||% list()
  enforcement <- axiom$enforcement %||% ""

  scope_str <- paste(
    if (!is.null(scope$market)) sprintf("market=%s", scope$market),
    if (!is.null(scope$factor_family)) sprintf("family=%s", scope$factor_family),
    if (!is.null(scope$regime)) sprintf("regime=%s", paste(scope$regime, collapse = "/")),
    sep = ", "
  )
  scope_str <- gsub("NULL, |, NULL", "", scope_str)

  supporting <- paste(axiom$supporting_l_codes %||% character(0), collapse = ", ")
  type_str <- if (identical(axiom$type, "methodological")) "[방법론]" else "[실증]"
  polarity_str <- switch(axiom$polarity %||% "unknown",
    positive = "성공", conditional = "조건부", negative = "실패",
    "unknown")

  lines <- c(
    sprintf("### %s %s [%s]: %s", ax_id, type_str, polarity_str, stmt),
    sprintf("- 범위: %s", scope_str),
    sprintf("- 근거: %s (L-code %d건)",
             supporting, length(axiom$supporting_l_codes %||% list())),
    sprintf("- 5축 점수: %.2f (I=%.2f R=%.2f F=%.2f E=%.2f M=%.2f)",
             pr$weighted_score %||% 0,
             pr$axis_scores$independence %||% 0, pr$axis_scores$rigor %||% 0,
             pr$axis_scores$falsification %||% 0, pr$axis_scores$external %||% 0,
             pr$axis_scores$mechanism %||% 0),
    sprintf("- 승격: %s | 다음 검토: %s",
             pr$promoted_at %||% "?", pr$next_review %||% "?")
  )
  if (nzchar(enforcement)) lines <- c(lines, sprintf("- Enforcement: %s", enforcement))
  paste(lines, collapse = "\n")
}

# ─── CLAUDE.md 편집 ─────────────────────────────────────────────────
.update_claude_md <- function(axiom, claude_md_path, do_write) {
  if (!file.exists(claude_md_path)) {
    stop("CLAUDE.md not found: ", claude_md_path)
  }
  raw <- readLines(claude_md_path, warn = FALSE, encoding = "UTF-8")

  # 중복 주입 방지
  if (any(grepl(sprintf("^### %s", axiom$axiom_id), raw, perl = TRUE))) {
    return(list(changed = FALSE, reason = "already present in CLAUDE.md"))
  }

  block <- .format_block(axiom)
  # Axioms 섹션 위치 탐지 (## Axioms ... 로 시작하는 헤더)
  ax_hdr <- grep("^##\\s+Axioms", raw, perl = TRUE)

  if (length(ax_hdr) == 0L) {
    new_lines <- c(raw, "", "## Axioms (auto-injected -- agent premises, Level 0)", "", block)
  } else {
    # 섹션 끝(다음 ## 또는 EOF) 찾기
    start <- ax_hdr[1]
    next_hdr <- grep("^##\\s+", raw, perl = TRUE)
    next_hdr <- next_hdr[next_hdr > start]
    end <- if (length(next_hdr) == 0L) length(raw) else (next_hdr[1] - 1L)
    new_lines <- c(raw[1:end], "", block, raw[(end + 1L):length(raw)])
    # handle end == length(raw) edge case
    if (end >= length(raw)) {
      new_lines <- c(raw, "", block)
    }
  }

  if (do_write) {
    writeLines(new_lines, claude_md_path, useBytes = TRUE)
  }
  list(changed = TRUE, n_lines_added = length(new_lines) - length(raw),
       new_lines = new_lines, old_lines = raw)
}

# ─── prompts/*_init.md 편집 ─────────────────────────────────────────
.update_prompt <- function(axiom, prompt_path, do_write) {
  if (!file.exists(prompt_path)) return(list(changed = FALSE, reason = "not found"))
  raw <- readLines(prompt_path, warn = FALSE, encoding = "UTF-8")

  start_mark <- "<!-- AXIOM_INJECT_START -->"
  end_mark <- "<!-- AXIOM_INJECT_END -->"
  s_idx <- grep(start_mark, raw, fixed = TRUE)
  e_idx <- grep(end_mark, raw, fixed = TRUE)

  block <- .format_block(axiom)

  if (length(s_idx) == 0L || length(e_idx) == 0L) {
    # 마크업 없음 — append section
    append_block <- c(
      "",
      "## Active Axioms (Level 0 전제)",
      start_mark,
      block,
      end_mark
    )
    new_lines <- c(raw, append_block)
  } else {
    s <- s_idx[1]; e <- e_idx[1]
    existing <- paste(raw[(s + 1):(e - 1)], collapse = "\n")
    # 중복 방지
    if (grepl(sprintf("^### %s", axiom$axiom_id), existing, perl = TRUE)) {
      return(list(changed = FALSE, reason = "already present in prompt"))
    }
    new_inner <- c(raw[s], if (nzchar(existing)) c(existing, "") else NULL, block, raw[e])
    new_lines <- c(raw[1:(s - 1)], new_inner,
                   if (e < length(raw)) raw[(e + 1):length(raw)] else character(0))
  }

  if (do_write) {
    writeLines(new_lines, prompt_path, useBytes = TRUE)
  }
  list(changed = TRUE, n_lines_added = length(new_lines) - length(raw))
}

# ─── Diff 파일 기록 ─────────────────────────────────────────────────
.write_diff <- function(axiom, claude_result) {
  root <- .ij_root()
  diff_dir <- file.path(root, ".cache")
  dir.create(diff_dir, showWarnings = FALSE, recursive = TRUE)
  ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
  diff_path <- file.path(diff_dir, sprintf("axiom_inject_%s_%s.diff",
                                             axiom$axiom_id, ts))

  # unified diff 시뮬레이션 (R에 diff tool이 없어 간이 출력)
  added <- setdiff(claude_result$new_lines, claude_result$old_lines)
  writeLines(c(
    sprintf("--- CLAUDE.md (before inject %s)", axiom$axiom_id),
    sprintf("+++ CLAUDE.md (after)"),
    sprintf("## added %d line(s):", length(added)),
    paste0("+ ", added)
  ), diff_path)

  diff_path
}

# ─── 메인 함수 ─────────────────────────────────────────────────────
inject_axiom <- function(axiom_path, claude_md_path = NULL,
                         prompts_dir = NULL, auto_inject = NULL) {
  if (!file.exists(axiom_path)) stop("axiom not found: ", axiom_path)
  axiom <- fromJSON(axiom_path, simplifyVector = FALSE)
  root <- .ij_root()
  if (is.null(claude_md_path)) {
    claude_md_path <- file.path(root, "CLAUDE.md")
  }
  if (is.null(prompts_dir)) {
    prompts_dir <- file.path(root, "02_Infrastructure", "prompts")
  }

  do_write <- if (is.null(auto_inject)) {
    as.integer(Sys.getenv("QVEST_AXIOM_AUTO_INJECT", "0")) == 1L
  } else isTRUE(auto_inject)

  mode <- if (do_write) "REAL" else "DRY-RUN"
  cat(sprintf("[inject] %s — mode=%s, auto_inject=%s\n",
              axiom$axiom_id, mode, as.character(do_write)))

  # 1) CLAUDE.md
  claude_result <- .update_claude_md(axiom, claude_md_path, do_write)
  cat(sprintf("  CLAUDE.md: %s%s\n",
              if (claude_result$changed) "changed" else "unchanged",
              if (!is.null(claude_result$reason)) sprintf(" (%s)", claude_result$reason) else ""))

  diff_path <- if (claude_result$changed) .write_diff(axiom, claude_result) else NULL
  if (!is.null(diff_path)) cat(sprintf("  diff: %s\n", diff_path))

  # 2) prompts/*_init.md — tier/mode 인지 라우팅 (검증된 9개; scout/risk_manager 죽은 타겟 제거)
  tier <- axiom$tier %||% (if (grepl("^AX-[A-Z]+-", axiom$axiom_id %||% "")) "mode_local" else "global")
  ax_mode <- axiom$research_mode %||% ""
  .MODE_PROMPT <- list(
    alpha_research = "alpha_research_init.md", risk_research = "risk_research_init.md",
    optimizer_research = "optimizer_research_init.md",
    judge_gate = "judge_init.md", governor_admission = "governor_init.md")
  global_prompts <- c("alpha_research_init.md", "risk_research_init.md", "optimizer_research_init.md",
                      "forge_init.md", "judge_init.md", "governor_init.md",
                      "execution_init.md", "monitoring_init.md", "qlead_init.md")
  if (identical(tier, "mode_local")) {
    mp <- .MODE_PROMPT[[ax_mode]]
    prompt_files <- if (!is.null(mp)) mp else character(0)  # alpha_search/factor_rotation 전용 init 없음 → CLAUDE.md만
    cat(sprintf("  [inject] mode-local(%s) → %s\n", ax_mode,
                if (length(prompt_files)) paste(prompt_files, collapse = ",") else "CLAUDE.md only"))
  } else {
    prompt_files <- global_prompts
  }
  prompt_results <- list()
  for (pf in prompt_files) {
    pp <- file.path(prompts_dir, pf)
    r <- .update_prompt(axiom, pp, do_write)
    prompt_results[[pf]] <- r
    cat(sprintf("  %s: %s%s\n", pf,
                if (r$changed) "changed" else "unchanged",
                if (!is.null(r$reason)) sprintf(" (%s)", r$reason) else ""))
  }

  list(
    axiom_id = axiom$axiom_id,
    mode = mode,
    claude_md = claude_result,
    prompts = prompt_results,
    diff_path = diff_path
  )
}

# ── CLI entry point ──
if (!interactive() && length(commandArgs(trailingOnly = TRUE)) > 0) {
  .args <- commandArgs(trailingOnly = TRUE)
  invisible(inject_axiom(.args[1]))
}

cat("[inject] Loaded. Function: inject_axiom(axiom_path, auto_inject=env)\n")
