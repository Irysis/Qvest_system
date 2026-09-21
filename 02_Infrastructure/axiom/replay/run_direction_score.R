#!/usr/bin/env Rscript
#==============================================================================
# run_direction_score.R — 방향 결정 규칙 채점 드라이버 (2026-09-21 도훈 승인 플랜 Part 3 · D4)
#   ★2026-09-21 도훈 지시 "규칙 채점 주기가 너무 길다 — 데일리로, Qvest 실행 시점에": 주기 무관 드라이버로 바꿨다.
#     호출 3곳 — ① /qvest 부팅 직전 세션이 --quiet 로 1회(≈2초 · 부팅 7번째 줄 `Rules:` 가 캐시를 읽는다)
#               ② 아침 무인 체인의 rf_director.R 이 매일 --quiet 로 1회  ③ 토요일 Cleaner 가 --archive 로 1회(날짜 파일 보존).
#   산출 — 매 실행: .cache/rf_direction_score_latest.json + review_log/direction_replay_latest.md (덮어씀)
#          --archive 또는 verdict=report: review_log/direction_replay_<YYYYMMDD>.{json,md} 도 남긴다(일간 실행이 review_log 를 불리지 않게).
#   --dry-run = 계산·출력만 · --quiet = verdict 줄만 · --root=<data root>(검사). 원장·결정 기록 읽기만.
#==============================================================================
ARGS <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) { v <- grep(paste0("^", flag, "="), ARGS, value = TRUE); if (length(v)) sub(paste0("^", flag, "="), "", v[1]) else default }
.norm <- function(p) sub("/+$", "", gsub("\\", "/", p, fixed = TRUE))
ROOT <- .norm(.arg("--root", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")))
CODE_ROOT <- local({ a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(a)) { cr <- sub("/02_Infrastructure/axiom/replay/?$", "", dirname(.norm(sub("^--file=", "", a[1])))); if (file.exists(file.path(cr, "02_Infrastructure/ops/rf_director.R"))) return(cr) }
  ROOT })
DRY <- "--dry-run" %in% ARGS; QUIET <- "--quiet" %in% ARGS; ARCHIVE <- "--archive" %in% ARGS
source(file.path(CODE_ROOT, "02_Infrastructure/axiom/replay/direction_world.R"))
cfg <- (.dw_rj(file.path(ROOT, "06_Registry/reinforce_auto_config.json")) %||% list())$director %||% list()
MIN_N <- as.integer(cfg$scoring_min_decisions %||% 8L)    # 플랜 Part 3 §7 — 결과가 붙은 행동 결정 8건 전 채점 보류
RE <- tryCatch({ Sys.setenv(QVEST_DIRECTOR_NO_MAIN = "1"); e <- new.env(parent = globalenv())
                 invisible(capture.output(suppressMessages(sys.source(file.path(CODE_ROOT, "02_Infrastructure/ops/rf_director.R"), envir = e)))); e }, error = function(e) NULL)
W <- dw_build(ROOT); S <- dw_score(W, MIN_N, RE)
tag <- format(Sys.Date(), "%Y%m%d"); now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
.f <- function(x, d = 3) if (is.finite(x)) format(x, digits = d) else "NA"
rep <- S$controls$positive_rule_reproduction
line <- sprintf("Rules: %s · 결정 %d/행동 %d/결과 %d(최소 %d) · Δ단위 %s · Δ프로그램 %s · 재현 %s/%s",
                if (identical(S$verdict, "insufficient")) "채점 보류" else "채점 가능", S$n_decisions, S$n_acted, S$n_measured, MIN_N,
                .f(S$d_unit_vs_best_calmar_median), .f(S$d_program_calmar_since_median),
                if (is.finite(rep$agree)) round(rep$agree * rep$n) else "-", rep$n)
if (nchar(line, type = "chars") > 120L) line <- paste0(substr(line, 1L, 117L), "…")
latest <- list(schema = "direction_score_v0", as_of = now, verdict = S$verdict, min_n = MIN_N, n_decisions = S$n_decisions, n_acted = S$n_acted, n_measured = S$n_measured,
               d_unit_vs_best_calmar_median = S$d_unit_vs_best_calmar_median, d_program_calmar_since_median = S$d_program_calmar_since_median,
               now_best_calmar = S$now_best_calmar, reproduction = rep, mc1_delivered_rate = S$mc1_delivered_rate, line = line)
out <- list(schema = "direction_replay_v0", as_of = now, score = S, rows = W$rows)
.wa <- function(txt, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); tmp <- sprintf("%s.tmp.%d", p, Sys.getpid())
  writeLines(enc2utf8(txt), tmp, useBytes = TRUE); if (!file.rename(tmp, p)) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) } }
if (!DRY) {
  od <- file.path(ROOT, "qepm/memory/axioms/review_log")
  .wa(toJSON(latest, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE), file.path(ROOT, ".cache/rf_direction_score_latest.json"))
  .wa(dw_report_md(S, "latest"), file.path(od, "direction_replay_latest.md"))
  if (ARCHIVE || identical(S$verdict, "report")) {
    .wa(toJSON(out, auto_unbox = TRUE, null = "null", na = "null", digits = 6, pretty = TRUE), file.path(od, sprintf("direction_replay_%s.json", tag)))
    .wa(dw_report_md(S, tag), file.path(od, sprintf("direction_replay_%s.md", tag))) }
}
if (!QUIET) cat(dw_report_md(S, tag), sep = "\n")
cat(line, "\n")
cat(sprintf("[direction_replay] verdict=%s n=%d acted=%d measured=%d min_n=%d%s%s\n", S$verdict, S$n_decisions, S$n_acted, S$n_measured, MIN_N, if (DRY) " (dry)" else "", if (ARCHIVE) " (archive)" else ""))
