#!/usr/bin/env Rscript
#==============================================================================
# grade_v3_retro.R — 등급 v3 소급 재채점 (S0 진단 · v10.01 2026-10-13)
#
# 무엇: 1계층 원장(reinforce_ledger_l1.json)의 측정 산출물 디렉터리(강화 칸 + 기저)를 모아
#   contracts/grade_v3.R 로 채점한다. 새 백테스트는 없다 — 이미 있는 측정 산출물만 다시 읽는다.
# 경계: 쓰기 = 보고서 디렉터리(--out)뿐. 원장·등록부·권위 등급은 건드리지 않는다(진단 — 판정 인용 금지).
#   측정 체계가 다른 산출물은 섞지 않는다 — close_t1 체계(09-25 rebase 이후 정본 집행가)만 집계한다.
#
# 사용: Rscript 02_Infrastructure/programs/grade_v3_retro.R [--root <ROOT>] [--out <DIR>] [--workers 6] [--limit N]
# 산출: retro_scores.csv · retro_summary.json · retro_details.rds · retro_errors.csv
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(parallel) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
args <- commandArgs(trailingOnly = TRUE)
argv <- function(k, d = NULL) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1L] }

ROOT0 <- argv("--root", NULL)
for (p in c(ROOT0, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
  if (is.null(p) || !nzchar(p)) next
  if (file.exists(file.path(p, "02_Infrastructure/contracts/grade_v3.R"))) { ROOT0 <- gsub("\\\\", "/", p); break }
}
source(file.path(ROOT0, "02_Infrastructure/contracts/grade_v3.R"))
ROOT <- .gv3_root(ROOT0)
OUT <- argv("--out", file.path(ROOT, "04_Research/01_reports/l1_prescription_redesign_20261013/s0_grade_v3"))
WORKERS <- as.integer(argv("--workers", "6")); LIMIT <- as.integer(argv("--limit", "0"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
cat(sprintf("[grade_v3_retro] root=%s out=%s workers=%d\n", ROOT, OUT, WORKERS))

# ── 1) 원장 → 측정 디렉터리 ─────────────────────────────────────────────────────
L <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
norm <- function(p) {
  if (is.null(p) || !length(p) || !nzchar(p[[1]])) return(NA_character_)
  p <- sub("/+$", "", gsub("\\\\", "/", p[[1]]))
  if (!grepl("^[A-Za-z]:/", p)) p <- file.path(ROOT, p)
  p
}
att_dir <- function(a) {
  rb <- a$rebase_log
  if (length(rb)) { p <- rb[[length(rb)]]$remeasure_path; if (!is.null(p)) return(dirname(norm(p))) }
  ar <- a$artifacts
  if (is.character(ar)) return(norm(ar))
  if (is.list(ar) && !is.null(ar$authoritative)) return(dirname(norm(ar$authoritative)))
  NA_character_
}
base_dir <- function(e) {
  if (!is.null(e$base_remeasure$path)) return(dirname(norm(e$base_remeasure$path)))
  d <- if (is.character(e$base_artifacts)) norm(e$base_artifacts) else NA_character_
  if (!is.na(d) && file.exists(file.path(d, "authoritative_remeasure.json"))) d else NA_character_
}
flags_of <- function(x) vapply(x %||% list(), function(z) paste0(z$flag %||% "?", "=", z$verdict %||% "?"), "")
ids <- vapply(L$entries, function(e) as.character(e$base_id), "")
par <- setNames(vapply(L$entries, function(e) as.character(e$parent$base_id %||% NA_character_), ""), ids)
root_of <- function(b) {
  seen <- character(0)
  while (b %in% names(par) && !is.na(par[[b]]) && !(b %in% seen)) { seen <- c(seen, b); b <- par[[b]] }
  b
}
rows <- list()
for (e in L$entries) {
  bf <- flags_of(e$base_vintage_flags); rt <- root_of(e$base_id)
  bd <- base_dir(e)
  if (!is.na(bd)) rows[[length(rows) + 1L]] <- data.table(dir = bd, kind = "base", base_id = e$base_id, root_lineage = rt,
    n = 0L, cell_code = NA_character_, keyword_axis = NA_character_, paper_key = as.character(e$paper_key %||% NA),
    ledger_grade = as.character(e$base_grade %||% NA), flags = paste(bf, collapse = ";"))
  for (a in e$attempts %||% list()) {
    if (is.null(a$essence$port_t)) next
    d <- att_dir(a); if (is.na(d)) next
    rows[[length(rows) + 1L]] <- data.table(dir = d, kind = "cell", base_id = e$base_id, root_lineage = rt,
      n = as.integer(a$n %||% NA), cell_code = as.character(a$cell_code %||% NA),
      keyword_axis = as.character(a$keyword_axis %||% NA), paper_key = as.character(e$paper_key %||% NA),
      ledger_grade = as.character(a$grade %||% NA), flags = paste(c(bf, flags_of(a$vintage_flags)), collapse = ";"))
  }
}
REF <- rbindlist(rows)
REF[, dir := sub("/+$", "", dir)]
# 같은 측정(디렉터리)을 여러 원장 위치가 가리킨다(승격 기저 = 부모 칸 측정) — 디렉터리 단위로 합친다
DIRS <- REF[, .(kind = kind[1], base_id = base_id[1], root_lineage = root_lineage[1], n = n[1], cell_code = cell_code[1],
                keyword_axis = keyword_axis[1], paper_key = paper_key[1], ledger_grade = ledger_grade[1],
                flags = paste(unique(unlist(strsplit(flags, ";", fixed = TRUE))), collapse = ";"),
                refs = paste(unique(sprintf("%s:%s", base_id, n)), collapse = ";"), n_refs = .N), by = dir]
DIRS[, exists := file.exists(file.path(dir, "authoritative_remeasure.json")) & file.exists(file.path(dir, "03_period_returns.csv"))]
cat(sprintf("[grade_v3_retro] 원장 참조 %d → 디렉터리 %d (산출물 있음 %d)\n", nrow(REF), nrow(DIRS), sum(DIRS$exists)))
todo <- DIRS[exists == TRUE]$dir
if (LIMIT > 0L) todo <- head(todo, LIMIT)

# ── 2) 병렬 채점 ────────────────────────────────────────────────────────────────
t0 <- Sys.time()
score_one <- function(d) tryCatch(list(ok = TRUE, r = gv3_score_dir(d, ROOT, CTX)),
                                  error = function(err) list(ok = FALSE, dir = d, err = conditionMessage(err)))
res <- if (WORKERS > 1L) {
  cl <- makeCluster(WORKERS)
  out <- tryCatch({
    clusterExport(cl, "ROOT")
    invisible(clusterEvalQ(cl, {
      suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
      source(file.path(ROOT, "02_Infrastructure/contracts/grade_v3.R"))
      .e <- .gv3_deps(ROOT)
      CTX <- list(cfg = gv3_cfg(ROOT), th = gv3_thresholds(ROOT), bc_cfg = .e$bc_cfg(ROOT),
                  rg = .e$rg_params(ROOT), bm_hist = gv3_bench_history(ROOT))
      NULL }))
    parLapplyLB(cl, todo, score_one)
  }, finally = stopCluster(cl))
  out
} else {
  .e <- .gv3_deps(ROOT)
  CTX <- list(cfg = gv3_cfg(ROOT), th = gv3_thresholds(ROOT), bc_cfg = .e$bc_cfg(ROOT),
              rg = .e$rg_params(ROOT), bm_hist = gv3_bench_history(ROOT))
  lapply(todo, score_one)
}
cat(sprintf("[grade_v3_retro] 채점 %d건 · %.1f분\n", length(res), as.numeric(difftime(Sys.time(), t0, units = "mins"))))

okr <- Filter(function(z) isTRUE(z$ok), res)
ERR <- rbindlist(lapply(Filter(function(z) !isTRUE(z$ok), res), function(z) data.table(dir = z$dir, err = z$err)))
S_ROWS <- rbindlist(lapply(okr, function(z) gv3_row(z$r)), fill = TRUE)
S_ROWS[, dir := sub("/+$", "", gsub("\\\\", "/", dir))]
TAB <- merge(DIRS[, !"exists"], S_ROWS, by = "dir", all.y = TRUE)
TAB[, close_t1 := startsWith(as.character(regime), "close_t1")]
TAB[, c1_flag := grepl("selection_basis_full_sample_ic[a-z_]*=consumed", flags)]
setorder(TAB, -S)
fwrite(TAB, file.path(OUT, "retro_scores.csv"))
if (nrow(ERR)) fwrite(ERR, file.path(OUT, "retro_errors.csv"))
saveRDS(lapply(okr, function(z) z$r), file.path(OUT, "retro_details.rds"))

# ── 3) 요약(close_t1 체계만) ─────────────────────────────────────────────────────
th <- gv3_thresholds(ROOT); cfg <- gv3_cfg(ROOT)
T1 <- TAB[close_t1 == TRUE]
cnt <- function(x) { t <- table(x, useNA = "ifany"); setNames(as.list(as.integer(t)), ifelse(is.na(names(t)), "NA", names(t))) }
s_b_star <- (th$port_t_b / th$port_t_a)^cfg$weights$port_t   # 'A Calmar + B PORT_t' 칸의 S — 기존 숫자에서 나오는 B 경계 후보
cuts <- c(1.0, 0.9, round(s_b_star, 4), 0.8, 0.7, 0.6, 0.5)
summ <- list(
  schema = "grade_v3_retro_summary_v1", created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  mode = cfg$mode, note = "진단 — 권위 등급은 essence_score.R. B·C 경계는 D1 미정",
  population = list(ledger_refs = nrow(REF), dirs = nrow(DIRS), dirs_with_artifacts = sum(DIRS$exists),
                    scored = nrow(TAB), errors = nrow(ERR), close_t1 = nrow(T1),
                    close_t1_cells = T1[kind == "cell", .N], close_t1_bases = T1[kind == "base", .N],
                    lineages = uniqueN(T1$root_lineage)),
  integrity = list(parity_max_abs = max(T1$parity_max_abs, na.rm = TRUE), json_gap_max_abs = max(T1$json_gap_max_abs, na.rm = TRUE)),
  bench_calmar = as.list(stats::quantile(T1$bench_calmar, c(0, 0.5, 1), na.rm = TRUE)),
  grade_v3 = cnt(T1$grade_v3),
  S_ge = setNames(lapply(cuts, function(k) T1[S >= k, .N]), sprintf("S>=%s", format(cuts))),
  S_zero = T1[S == 0, .N],
  S_quantiles = as.list(stats::quantile(T1$S, c(0.5, 0.75, 0.9, 0.95, 0.99, 1), na.rm = TRUE)),
  s_b_star = list(value = s_b_star, derivation = "(grade_b_min_portfolio_alpha_t / min_portfolio_alpha_t_nw)^w_port_t — Calmar 가 A 문턱에 있고 PORT_t 가 현행 B 문턱에 있는 칸의 S"),
  cr = cnt(T1$cr), cr_test = cnt(T1$cr_test),
  uc_ge_floor = T1[uc_median >= 0.55, .N],
  floors_pass = list(port_t = mean(T1$floor_port_t), calmar = mean(T1$floor_calmar), cagr = mean(T1$floor_cagr),
                     sharpe = mean(T1$floor_sharpe), all = mean(T1$floor_port_t & T1$floor_calmar & T1$floor_cagr & T1$floor_sharpe)),
  oos = list(gate_pass = mean(T1$oos_gate, na.rm = TRUE),
             pass_oos_quantiles = as.list(stats::quantile(T1$pass_oos, c(0.5, 0.9, 1), na.rm = TRUE)),
             S_oos_zero_share = mean(T1$S_oos == 0, na.rm = TRUE)),
  b_boundary_S = as.list(stats::quantile(T1$S_B, c(0, 0.5, 1), na.rm = TRUE)),
  band = cnt(T1$band),
  notch = list(up = T1[notch == 1L, .N], down = T1[notch == -1L, .N], to_A = T1[notch_a == TRUE, .N]),
  c1_flagged = T1[c1_flag == TRUE, .N],
  crosstab_band_x_v3 = {
    x <- T1[, .N, by = .(band, grade_v3)][order(band, grade_v3)]
    lapply(split(x, x$band), function(z) setNames(as.list(z$N), z$grade_v3)) },
  crosstab_essence_x_v3 = {
    x <- T1[, .N, by = .(essence_grade, grade_v3)][order(essence_grade, grade_v3)]
    lapply(split(x, x$essence_grade), function(z) setNames(as.list(z$N), z$grade_v3)) }
)
writeLines(toJSON(summ, auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null", na = "null"),
           file.path(OUT, "retro_summary.json"), useBytes = TRUE)
cat(sprintf("[grade_v3_retro] close_t1 %d (칸 %d · 기저 %d) · S>=1 %d · 오류 %d · 재현 최대 %.2g\n",
            nrow(T1), summ$population$close_t1_cells, summ$population$close_t1_bases, T1[S >= 1, .N], nrow(ERR),
            summ$integrity$parity_max_abs))
