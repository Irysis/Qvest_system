#!/usr/bin/env Rscript
#==============================================================================
# run_weekly_direction.R — 주간 방향 결정 채점 드라이버 (2026-09-21 도훈 승인 플랜 Part 3 · D4)
#   weekly_cleaner_sweep.R [3.5b] 이 부른다. 산출 = qepm/memory/axioms/review_log/direction_replay_<YYYYMMDD>.{json,md}
#   --dry-run = 계산·출력만 · --root=<data root> (검사). 원장·결정 기록 읽기만. 마지막 줄 `[direction_replay] verdict=... n=...`.
#==============================================================================
ARGS <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) { v <- grep(paste0("^", flag, "="), ARGS, value = TRUE); if (length(v)) sub(paste0("^", flag, "="), "", v[1]) else default }
.norm <- function(p) sub("/+$", "", gsub("\\", "/", p, fixed = TRUE))
ROOT <- .norm(.arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
CODE_ROOT <- local({ a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) { cr <- sub("/02_Infrastructure/axiom/replay/?$", "", dirname(.norm(sub("^--file=", "", a[1])))); if (file.exists(file.path(cr, "02_Infrastructure/ops/rf_director.R"))) return(cr) }
  ROOT })
DRY <- "--dry-run" %in% ARGS
source(file.path(CODE_ROOT, "02_Infrastructure/axiom/replay/direction_world.R"))
cfg <- (.dw_rj(file.path(ROOT, "06_Registry/reinforce_auto_config.json")) %||% list())$director %||% list()
MIN_N <- as.integer(cfg$scoring_min_decisions %||% 8L)    # 플랜 Part 3 §7 — 결과가 붙은 행동 결정 8건 전 채점 보류
RE <- tryCatch({ Sys.setenv(QVEST_DIRECTOR_NO_MAIN = "1"); e <- new.env(parent = globalenv())
                 invisible(capture.output(suppressMessages(sys.source(file.path(CODE_ROOT, "02_Infrastructure/ops/rf_director.R"), envir = e)))); e }, error = function(e) NULL)
W <- dw_build(ROOT); S <- dw_score(W, MIN_N, RE)
tag <- format(Sys.Date(), "%Y%m%d")
out <- list(schema = "direction_replay_v0", as_of = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), score = S,
            rows = lapply(W$rows, function(r) r[setdiff(names(r), character(0))]))
if (!DRY) {
  od <- file.path(ROOT, "qepm/memory/axioms/review_log"); dir.create(od, recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(toJSON(out, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE)), file.path(od, sprintf("direction_replay_%s.json", tag)), useBytes = TRUE)
  writeLines(enc2utf8(dw_report_md(S, tag)), file.path(od, sprintf("direction_replay_%s.md", tag)), useBytes = TRUE)
}
cat(dw_report_md(S, tag), sep = "\n")
cat(sprintf("[direction_replay] verdict=%s n=%d acted=%d measured=%d min_n=%d%s\n", S$verdict, S$n_decisions, S$n_acted, S$n_measured, MIN_N, if (DRY) " (dry)" else ""))
