# audit_batch434_labels.R — batch_434 codegen 폴백 라벨 오염 전수 감사 (2026-06-13)
# 목적: strategy_idea/name에 codegen 마커가 있는 alpha-search 런 전수에 대해
#   (A) 실제 실행 신호(runner FACTOR_NAMES) vs 가설명 비교
#   (B) NAV md5(run_id 컬럼 제외 값 기준) 그룹핑으로 동일-NAV 클러스터 식별
#   (C) module_catalog / module_quarantine 등재 상태 조인
# 산출: audit_runs.csv / runner_map.csv / nav_clusters.csv / summary.txt
# 주의: 읽기 전용 감사 — 레지스트리/카탈로그/아티팩트 일절 수정하지 않음.

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
  library(digest)
})

root <- Sys.getenv("CLAUDE_PROJECT_DIR", "")
if (!nzchar(root) || !file.exists(file.path(root, "02_Infrastructure", "config.R"))) {
  cand <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  while (!file.exists(file.path(cand, "02_Infrastructure", "config.R"))) {
    parent <- dirname(cand)
    if (identical(parent, cand)) stop("project root not found")
    cand <- parent
  }
  root <- cand
}
out_dir <- file.path(root, "04_Research", "audits", "batch434_label_audit_20260613")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

MARKER_PAT <- "requires code generation|patched blocked runner"

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

## ── 1. runner map (codegen_direct_409 우선, codegen_409 보조) ───────────────
runner_dirs <- c(
  file.path(root, "stage_artifacts/batch_434/20260612_codegen_direct_409/runners"),
  file.path(root, "stage_artifacts/batch_434/20260612_codegen_409/runners")
)
unquote_r <- function(line) {
  # '  strategy_name = "...",' 형태에서 첫/마지막 따옴표 사이 추출 (deparse 이스케이프 복원)
  v <- sub('^[^"]*"', "", line)
  v <- sub('"\\s*,?\\s*$', "", v)
  gsub('\\\\"', '"', v, fixed = FALSE)
}
parse_runner <- function(path, batch_label) {
  txt <- tryCatch(readLines(path, warn = FALSE, encoding = "UTF-8"), error = function(e) character())
  if (!length(txt)) return(NULL)
  pick <- function(p) { m <- grep(p, txt, value = TRUE, perl = TRUE); if (length(m)) m[[1]] else NA_character_ }
  fn_line <- pick('Sys\\.setenv\\(FACTOR_NAMES')
  sn_line <- pick('^\\s*strategy_name\\s*=')
  data.table(
    item_id = sub("\\.R$", "", basename(path)),
    runner_batch = batch_label,
    runner_path = sub(paste0("^", root, "/?"), "", normalizePath(path, winslash = "/")),
    runner_strategy_name = if (!is.na(sn_line)) unquote_r(sn_line) else NA_character_,
    actual_factor_names = if (!is.na(fn_line)) unquote_r(fn_line) else NA_character_,
    actual_engine = if (any(grepl("fe_factor_momentum", txt, fixed = TRUE))) "fm"
                    else if (any(grepl("fe_factor_combo", txt, fixed = TRUE))) "combo"
                    else "other",
    runner_weight_method = { wl <- pick('^\\s*weight_method\\s*='); if (!is.na(wl)) unquote_r(wl) else NA_character_ },
    runner_n_holdings = { nl <- pick('^\\s*n_holdings\\s*='); if (!is.na(nl)) suppressWarnings(as.integer(gsub("[^0-9]", "", nl))) else NA_integer_ },
    has_vol_target = any(grepl("^\\s*vol_target\\s*=", txt, perl = TRUE)),
    has_dd_brake = any(grepl("^\\s*dd_brake\\s*=", txt, perl = TRUE))
  )
}
runner_list <- list()
for (i in seq_along(runner_dirs)) {
  rd <- runner_dirs[i]
  if (!dir.exists(rd)) next
  lbl <- basename(dirname(rd))
  for (f in list.files(rd, pattern = "\\.R$", full.names = TRUE)) {
    runner_list[[length(runner_list) + 1L]] <- parse_runner(f, lbl)
  }
}
runners <- rbindlist(runner_list, fill = TRUE)
# direct 우선 dedupe (같은 item_id가 양 디렉토리에 있으면 direct만)
setorder(runners, item_id, runner_batch)  # codegen_409 < codegen_direct_409 (알파벳) → direct가 뒤
runners <- runners[, .SD[runner_batch == max(runner_batch)][1], by = item_id]
fwrite(runners, file.path(out_dir, "runner_map.csv"), bom = TRUE)

## ── 2. 마커 런 전수 스캔 (strategy_manifest.json) ───────────────────────────
man_paths <- Sys.glob(file.path(root, "stage_artifacts/alpha_search/*/strategy_manifest.json"))
run_list <- list()
for (mp in man_paths) {
  m <- tryCatch(fromJSON(mp, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(m)) next
  idea <- paste(m$strategy_idea %||% "", collapse = " ")
  name <- paste(m$strategy_name %||% "", collapse = " ")
  if (!grepl(MARKER_PAT, paste(idea, name), perl = TRUE, ignore.case = TRUE)) next
  dirn <- basename(dirname(mp))
  nav_path <- file.path(dirname(mp), "02_nav.csv")
  nav_md5 <- NA_character_; nav_rows <- NA_integer_
  if (file.exists(nav_path)) {
    nv <- tryCatch(fread(nav_path), error = function(e) NULL)
    if (!is.null(nv) && nrow(nv)) {
      idc <- grep("run_id|strategy_id", names(nv), value = TRUE)
      if (length(idc)) nv[, (idc) := NULL]
      nav_md5 <- digest(do.call(paste, c(as.list(nv), sep = "|")), algo = "md5")
      nav_rows <- nrow(nv)
    }
  }
  run_list[[length(run_list) + 1L]] <- data.table(
    run_dir = dirn,
    strategy_id = m$strategy_id %||% NA_character_,
    strategy_name = name,
    created_at = m$created_at %||% NA_character_,
    hurdle_grade = tryCatch(m$verdict$grade %||% NA_character_, error = function(e) NA_character_),
    nav_md5 = nav_md5, nav_rows = nav_rows
  )
}
runs <- rbindlist(run_list, fill = TRUE)

## ── 3. run ↔ runner 조인 (strategy_name 완전일치) ──────────────────────────
runs <- merge(runs, runners, by.x = "strategy_name", by.y = "runner_strategy_name",
              all.x = TRUE, sort = FALSE)

## ── 4. 메커니즘 분류 (휴리스틱 — 적대 검증 표본 확인 대상) ─────────────────
dyn_pat <- paste0(
  "잔차|residual|FF5|FF3|\\bOU\\b|평균회귀|mean.?rever|스위치|스위칭|switch|전환|",
  "타이밍|timing|돌파|on.?off|동적|dynamic|walk.?forward|greedy|상관 최저|적응|adaptive|",
  "ablation|진단|머신|\\bML\\b|lightgbm|xgboost|catboost|forest|GRU|\\bNN\\b|stack|conformal|",
  "베이지안|bayes|Delta_|국면|regime|레짐|매크로|macro|ECOS|금리|환율|VIX|put.?call|",
  "계절|season|커버리지|coverage|네트워크|network|PCA|클러스터|cluster|kelly|sweep|토너먼트|tournament"
)
ovl_pat <- "overlay|\\bBRK\\b|MRS[0-9]{0,2}|\\bVT[0-9.]*\\b|vol.?target|dd.?brake|브레이크|vol.?managed|\\bDD[0-9]{0,2}\\b"
classify <- function(name, engine, has_vt, has_dd) {
  if (is.na(engine)) return("NO_RUNNER_MATCH")
  cls <- character()
  if (grepl(ovl_pat, name, perl = TRUE, ignore.case = TRUE) && !has_vt && !has_dd)
    cls <- c(cls, "MISMATCH_OVERLAY_ABSENT")
  if (grepl(dyn_pat, name, perl = TRUE, ignore.case = TRUE)) {
    cls <- c(cls, if (identical(engine, "fm")) "MISMATCH_VARIANT_GENERIC_FM" else "MISMATCH_MECHANISM")
  }
  if (!length(cls)) cls <- "PROXY_PLAUSIBLE"
  paste(cls, collapse = "+")
}
runs[, label_class := mapply(classify, strategy_name, actual_engine, has_vol_target, has_dd_brake)]

## ── 5. NAV 클러스터 ─────────────────────────────────────────────────────────
runs[, nav_cluster_size := .N, by = nav_md5]
clus <- runs[!is.na(nav_md5) & nav_cluster_size > 1L,
             .(n_runs = .N,
               n_distinct_names = uniqueN(strategy_name),
               run_dirs = paste(run_dir, collapse = ";"),
               names = paste(unique(strategy_name), collapse = " || ")),
             by = nav_md5][order(-n_runs)]
fwrite(clus, file.path(out_dir, "nav_clusters.csv"), bom = TRUE)

## ── 6. catalog / quarantine 조인 ────────────────────────────────────────────
cat_j <- fromJSON(file.path(root, "06_Registry/module_catalog.json"), simplifyVector = FALSE)
cat_dt <- rbindlist(lapply(names(cat_j$modules), function(id) {
  m <- cat_j$modules[[id]]
  data.table(strategy_id = id,
             catalog_grade = m$grade %||% NA_character_,
             fr_eligible = isTRUE(m$fr_eligible),
             frozen = isTRUE(m$frozen))
}), fill = TRUE)
runs <- merge(runs, cat_dt, by = "strategy_id", all.x = TRUE, sort = FALSE)
runs[, in_catalog := !is.na(catalog_grade)]
q_path <- file.path(root, "06_Registry/module_quarantine.json")
q_ids <- character()
if (file.exists(q_path)) {
  qj <- tryCatch(fromJSON(q_path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(qj)) {
    qm <- qj$modules %||% qj
    q_ids <- if (is.list(qm)) names(qm) else character()
  }
}
runs[, in_quarantine := strategy_id %in% q_ids]

setcolorder(runs, c("run_dir", "strategy_id", "strategy_name", "label_class",
                    "actual_factor_names", "actual_engine", "runner_weight_method",
                    "has_vol_target", "has_dd_brake", "item_id", "runner_batch",
                    "nav_md5", "nav_cluster_size", "nav_rows", "hurdle_grade",
                    "in_catalog", "catalog_grade", "fr_eligible", "frozen",
                    "in_quarantine", "created_at", "runner_path", "runner_n_holdings"))
fwrite(runs, file.path(out_dir, "audit_runs.csv"), bom = TRUE)

## ── 7. summary ──────────────────────────────────────────────────────────────
s <- c(
  sprintf("batch_434 codegen 라벨 오염 전수 감사 — %s", format(Sys.time(), "%Y-%m-%d %H:%M")),
  sprintf("마커 런 총수: %d (manifest 스캔 %d개 중)", nrow(runs), length(man_paths)),
  sprintf("runner 매칭: %d / 미매칭(NO_RUNNER_MATCH): %d",
          sum(!is.na(runs$item_id)), sum(is.na(runs$item_id))),
  "",
  "label_class 분포:",
  capture.output(print(runs[, .N, by = label_class][order(-N)])),
  "",
  sprintf("catalog 등재: %d (fr_eligible=true: %d) / quarantine: %d",
          sum(runs$in_catalog, na.rm = TRUE),
          sum(runs$fr_eligible, na.rm = TRUE),
          sum(runs$in_quarantine, na.rm = TRUE)),
  "",
  sprintf("동일-NAV 클러스터(>1런): %d개 클러스터 / 관련 런 %d건 / 서로 다른 가설명 보유 클러스터: %d개",
          nrow(clus), sum(clus$n_runs), sum(clus$n_distinct_names > 1L)),
  "",
  "catalog 등재 + MISMATCH 계열 (조치 우선):",
  capture.output(print(runs[in_catalog == TRUE & grepl("MISMATCH", label_class),
                            .N, by = .(label_class, catalog_grade)][order(-N)]))
)
writeLines(s, file.path(out_dir, "summary.txt"), useBytes = TRUE)
cat(paste(s, collapse = "\n"), "\n")
cat(sprintf("\n[audit] outputs: %s\n", out_dir))
