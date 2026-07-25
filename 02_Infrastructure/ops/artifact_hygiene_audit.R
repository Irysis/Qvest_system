# =============================================================================
# artifact_hygiene_audit.R — 일간 파일위생 감사 (자동정리 + 감지·경고)
#
# (2026-07-04 파일위생 mandate — artifact-storage.md 집행 2선.
#  1선 = hooks/artifact_placement_guard.sh advisory)
#
# (a) 자동 정리 (실삭제 — QVEST_HYGIENE_DRY=1 시 dry-run):
#   a1. 지정 로그 디렉토리(TEMP/TMP//tmp)의 qm_/qvest_ 접두 *.log 90일+ 삭제
#   a2. .cache/scratch/ 30일+ 파일 삭제 (artifact-storage.md §4 Retention)
#   a3. 빈 디렉토리 삭제 — 청소 허용 존 한정, 보존 구역 절대 제외
#   모든 삭제는 hygiene_report.json + .cache/hygiene_manifest.log 에 기록.
#
# (b) 감지·경고만 (삭제 안 함 — stderr WARN + report):
#   b1. 루트 직하 무허가 항목 (§2 고정 13항목 + INDEX/ARTIFACTS 외)
#   b2. 02_Infrastructure 내 '_' 접두 파일 (§3 — 인프라 코드전용)
#   b3. 4대 산출물 존 밖 산출물성 파일 (results/output 명명 데이터 파일)
#   b4. index_descriptions.json 미등재 신규 최상위 항목 (존별 미분류)
#
# 산출: <registry>/hygiene_report.json 갱신. 위반 존재 시 stderr [hygiene][WARN].
# 텔레그램 직접 발송 금지 (tg 규약) — daily_refresh 로그로만 노출.
# 실행: Rscript 02_Infrastructure/ops/artifact_hygiene_audit.R
#       (daily_refresh.sh 말미, artifact index 재생성 직전 fail-soft 호출)
# =============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

DRY  <- Sys.getenv("QVEST_HYGIENE_DRY", "0") == "1"
LOG_RETENTION_DAYS     <- 90
SCRATCH_RETENTION_DAYS <- 30
now <- Sys.time()

# ---- 경로 해석 (QM_ROOT env 우선 — normalizePath 미사용, 한글경로 정책) --------
root <- Sys.getenv("QM_ROOT", "")
if (!nzchar(root)) {
  args <- commandArgs(trailingOnly = FALSE)
  fa <- grep("^--file=", args, value = TRUE)
  if (length(fa) == 1) {
    sd   <- gsub("\\\\", "/", dirname(sub("^--file=", "", fa)))
    root <- sub("/02_Infrastructure/ops/?$", "", sd)
  } else root <- getwd()
}
root <- sub("/+$", "", gsub("\\\\", "/", root))
if (!dir.exists(file.path(root, "02_Infrastructure")))
  stop("[hygiene] project root 미해석: ", root)
registry_zone <- if (dir.exists(file.path(root, "06_Registry"))) "06_Registry" else "07_Registry"

cat(sprintf("[hygiene] audit start @ %s root=%s dry_run=%s\n",
            format(now, "%Y-%m-%d %H:%M:%S"), root, DRY))

manifest_path <- file.path(root, ".cache", "hygiene_manifest.log")
log_deletion <- function(kind, path) {
  line <- sprintf("%s\t%s\t%s%s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                  kind, path, if (DRY) "\t[DRY]" else "")
  try(cat(line, "\n", sep = "", file = manifest_path, append = TRUE), silent = TRUE)
}

deleted <- list(logs = character(0), scratch = character(0), empty_dirs = character(0))

# =============================================================================
# (a1) 지정 로그 디렉토리 — qm_/qvest_ 접두 *.log 90일+ 삭제
#   대상: OS temp 계열만 (daily_refresh/hook 로그 산실). 프로젝트 내부·보존 구역은
#   건드리지 않는다 (stage_artifacts/qepm 내 로그 = 불변 런 기록, §6).
# =============================================================================
log_dirs <- unique(Filter(function(d) nzchar(d) && dir.exists(d), c(
  gsub("\\\\", "/", Sys.getenv("TEMP", "")),
  gsub("\\\\", "/", Sys.getenv("TMP", "")),
  "C:/Users/99922/AppData/Local/Temp",
  "/tmp")))
for (ld in log_dirs) {
  fs <- list.files(ld, pattern = "^(qm_|qvest_).*\\.log$", full.names = TRUE)
  if (!length(fs)) next
  age <- suppressWarnings(as.numeric(difftime(now, file.info(fs)$mtime, units = "days")))
  old <- fs[!is.na(age) & age > LOG_RETENTION_DAYS]
  for (f in old) {
    ok <- if (DRY) TRUE else isTRUE(suppressWarnings(file.remove(f)))
    if (ok) { deleted$logs <- c(deleted$logs, f); log_deletion("log90d", f) }
  }
}

# =============================================================================
# (a2) .cache/scratch/ — 30일+ 파일 삭제 (§3 스크래치 존 + §4 Retention 30d)
# =============================================================================
scratch <- file.path(root, ".cache", "scratch")
if (dir.exists(scratch)) {
  fs <- list.files(scratch, recursive = TRUE, full.names = TRUE,
                   all.files = TRUE, no.. = TRUE)
  if (length(fs)) {
    fi <- file.info(fs)
    fs <- fs[!is.na(fi$isdir) & !fi$isdir]
    if (length(fs)) {
      age <- suppressWarnings(as.numeric(difftime(now, file.info(fs)$mtime, units = "days")))
      old <- fs[!is.na(age) & age > SCRATCH_RETENTION_DAYS]
      for (f in old) {
        ok <- if (DRY) TRUE else isTRUE(suppressWarnings(file.remove(f)))
        if (ok) { deleted$scratch <- c(deleted$scratch, f); log_deletion("scratch30d", f) }
      }
    }
  }
}

# =============================================================================
# (a2b) .cache/ 루트 `_` 접두 리서치-모드 스크래치 30일+ 삭제
#   (2026-07-04 RAMP 갭 봉합) RAMP 등 리서치 모드가 .cache 루트에 직접 쓰는
#   `_ramp*.rds`·`_*.txt`·`_*.out` 중간 체크포인트는 재생성 가능(canonical=outputs/<mode>/).
#   활성 운영 파일은 `_` 접두를 쓰지 않으므로 접두 규칙이 곧 안전 필터.
#   그래도 만일에 대비해 keep-list 명시 보호.
# =============================================================================
CACHE_ROOT_KEEP <- c("update_file_last_processed.rds", "lens2_liq_sweep.rds")
cache_root <- file.path(root, ".cache")
if (dir.exists(cache_root)) {
  rf <- list.files(cache_root, pattern = "^_.*\\.(rds|txt|out|log|R)$",
                   full.names = TRUE, all.files = TRUE, no.. = TRUE)
  rf <- rf[!(basename(rf) %in% CACHE_ROOT_KEEP)]
  if (length(rf)) {
    age <- suppressWarnings(as.numeric(difftime(now, file.info(rf)$mtime, units = "days")))
    old <- rf[!is.na(age) & age > SCRATCH_RETENTION_DAYS]
    for (f in old) {
      ok <- if (DRY) TRUE else isTRUE(suppressWarnings(file.remove(f)))
      if (ok) { deleted$scratch <- c(deleted$scratch, f); log_deletion("cache_root_scratch30d", f) }
    }
  }
}

# =============================================================================
# (a3) 빈 디렉토리 삭제 — 청소 허용 존 한정. 보존 구역(05_Production/01_Literature/
#   stage_artifacts/qepm/06_Registry/.git/04_Research/strategies) 절대 제외.
#   deepest-first 순회로 연쇄 빈 부모까지 1-pass 정리.
# =============================================================================
EMPTY_SCAN_ZONES <- c("02_Infrastructure", "04_Research", "outputs", ".cache", "08_Tests")
PRESERVE_RE <- paste0("(^|/)(05_Production|01_Literature|stage_artifacts|qepm|",
                      "06_Registry|07_Registry|\\.git|\\.venv[^/]*)(/|$)",
                      "|/04_Research/strategies(/|$)")
for (z in EMPTY_SCAN_ZONES) {
  zp <- file.path(root, z)
  if (!dir.exists(zp)) next
  dirs <- setdiff(list.dirs(zp, recursive = TRUE, full.names = TRUE), zp)
  dirs <- gsub("\\\\", "/", dirs)
  dirs <- dirs[!grepl(PRESERVE_RE, dirs)]
  dirs <- dirs[order(nchar(dirs), decreasing = TRUE)]   # deepest-first
  for (d in dirs) {
    if (length(list.files(d, all.files = TRUE, no.. = TRUE)) == 0) {
      ok <- if (DRY) TRUE else unlink(d, recursive = TRUE) == 0
      if (isTRUE(ok)) { deleted$empty_dirs <- c(deleted$empty_dirs, d); log_deletion("empty_dir", d) }
    }
  }
}

# =============================================================================
# (b) 감지·경고만 — 삭제하지 않는다
# =============================================================================
warnings_out <- list()

# (b1) 루트 직하 무허가 항목 (dot항목 제외)
ALLOW_ROOT <- c("00_Lawbook", "01_Literature", "02_Infrastructure", "03_Universe",
                "04_Research", "05_Production", "06_Registry", "08_Tests",
                "outputs", "qepm", "stage_artifacts",
                "ARTIFACTS.md", "CHANGELOG.md", "CLAUDE.md", "INDEX.md")
tops <- list.files(root, no.. = TRUE)          # dot항목은 기본 미포함
warnings_out$root_unauthorized <- as.list(setdiff(tops, ALLOW_ROOT))

# (b2) 02_Infrastructure 내 '_' 접두 파일/디렉토리 (공용 예외 + 아카이브 제외)
UNDERSCORE_OK <- c("_shared_parse.sh", "_shared_prefix.md")   # 위치 무관 공용 모듈 (basename 매칭)
# 라이브 의존 예외 (2026-07-25 도훈 confirm) — 상대경로 매칭.
#   여기서 '_' 접두는 §3이 표적하는 '1회용 디버그'가 아니라 'private 모듈'을 뜻한다.
#   전부 실소비자가 있어 삭제 시 파이프라인 파손 — 괄호 안이 소비자.
UNDERSCORE_OK_PATHS <- c(
  "ops/morning_steps/_root.R",                            # morning_steps 9종이 source()
  "search/_query.py",                                     # search/qvest_search CLI
  "observability/_wt_pretty.py",                          # observability/qvest_wt CLI
  "ramp/debug/_cache_pool.rds",                           # 04_Research/ramp/run_ramp_gate3_4.R CACHE_POOL
  "portfolio/frontier_hrp/_validate_dynamic_regime_rp.R"  # dynamic_regime_rp.R:46 재현 검증본
)
infra <- file.path(root, "02_Infrastructure")
inf_all <- list.files(infra, recursive = TRUE, full.names = FALSE, include.dirs = TRUE)
und <- inf_all[grepl("(^|/)_[^/_]", inf_all)]                      # '_x...' (‘__’ 계열 제외)
und <- und[!grepl("(^|/)(__pycache__|_archive[^/]*)(/|$)", und)]   # 아카이브/캐시 제외
und <- und[!(basename(und) %in% UNDERSCORE_OK | und %in% UNDERSCORE_OK_PATHS)]
warnings_out$infra_underscore <- as.list(und)

# (b3) 4대 산출물 존 밖 산출물성 파일 (results/output 명명 데이터 파일)
#   스캔: 4대 존·qepm·보존 구역 밖의 코드/문서 존만. 데이터 확장자 한정 (코드 .R/.py는
#   훅이 신규 생성 시점에 advisory — 기존 코드 오탐 방지).
MISPLACE_SCAN <- c("02_Infrastructure", "00_Lawbook", "03_Universe", "08_Tests")
misplaced <- character(0)
for (z in MISPLACE_SCAN) {
  zp <- file.path(root, z)
  if (!dir.exists(zp)) next
  fs <- list.files(zp, recursive = TRUE, full.names = FALSE)
  hit <- fs[grepl("\\.(json|csv|parquet|rds|rdata|txt|log)$", fs, ignore.case = TRUE) &
            grepl("(^|[._-])(results?|outputs?)($|[._-])",
                  sub("\\.[A-Za-z0-9]+$", "", basename(fs)), ignore.case = TRUE)]
  if (length(hit)) misplaced <- c(misplaced, file.path(z, hit))
}
root_files <- tops[!dir.exists(file.path(root, tops))]
hit_root <- root_files[grepl("\\.(json|csv|parquet|rds|rdata|txt|log)$", root_files, ignore.case = TRUE) &
                       grepl("(^|[._-])(results?|outputs?)($|[._-])",
                             sub("\\.[A-Za-z0-9]+$", "", root_files), ignore.case = TRUE)]
warnings_out$misplaced_outputs <- as.list(c(misplaced, hit_root))

# (b4) index_descriptions.json 미등재 신규 최상위 항목 (build_artifact_index '미분류' 동일 로직)
desc_path <- file.path(root, registry_zone, "index_descriptions.json")
unindexed <- list()
if (file.exists(desc_path)) {
  descs <- tryCatch(fromJSON(desc_path, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(descs)) {
    descs[["_meta"]] <- NULL
    parse_desc_tokens <- function(key_rel) {
      s <- sub("\\s*\\([^()]*\\)\\s*$", "", key_rel)
      parts <- trimws(strsplit(s, " \\+ ")[[1]])
      toks <- unlist(lapply(parts, function(p) {
        if (grepl("^\\{.*\\}$", p)) {
          ts <- trimws(strsplit(sub("^\\{(.*)\\}$", "\\1", p), ",")[[1]])
          sub("\\s*×[0-9]+\\s*$", "", ts)
        } else p
      }))
      toks <- sub("/+$", "", trimws(toks))
      toks[nzchar(toks)]
    }
    for (zone_rel in c("02_Infrastructure", "04_Research", registry_zone, "08_Tests")) {
      zp <- file.path(root, zone_rel)
      if (!dir.exists(zp)) next
      pref <- paste0(zone_rel, "/")
      keys <- names(descs)[startsWith(names(descs), pref)]
      all_toks <- unique(unlist(lapply(substring(keys, nchar(pref) + 1L), parse_desc_tokens)))
      ztops <- setdiff(list.files(zp, no.. = TRUE), "INDEX.md")
      covered <- vapply(ztops, function(nm) {
        length(all_toks) > 0 && any(vapply(all_toks, function(tk) {
          if (grepl("[*?]", tk)) grepl(utils::glob2rx(tk), nm)
          else tk == nm || startsWith(tk, paste0(nm, "/"))
        }, FALSE))
      }, FALSE)
      unk <- ztops[!covered]
      if (length(unk)) unindexed[[zone_rel]] <- as.list(unk)
    }
  } else warnings_out$index_db_parse_fail <- desc_path
} else warnings_out$index_db_missing <- desc_path
warnings_out$unindexed_top <- unindexed

# =============================================================================
# 리포트 + stderr WARN
# =============================================================================
n_warn <- length(warnings_out$root_unauthorized) +
          length(warnings_out$infra_underscore) +
          length(warnings_out$misplaced_outputs) +
          sum(vapply(unindexed, length, 0L))
n_del  <- length(deleted$logs) + length(deleted$scratch) + length(deleted$empty_dirs)

report <- list(
  generated_at   = format(now, "%Y-%m-%d %H:%M:%S"),
  generator      = "02_Infrastructure/ops/artifact_hygiene_audit.R",
  rule_sot       = "02_Infrastructure/docs/rules/artifact-storage.md",
  dry_run        = DRY,
  retention_days = list(logs = LOG_RETENTION_DAYS, scratch = SCRATCH_RETENTION_DAYS),
  cleanup = list(
    n_deleted          = n_del,
    logs_deleted       = as.list(deleted$logs),
    scratch_deleted    = as.list(deleted$scratch),
    empty_dirs_removed = as.list(deleted$empty_dirs),
    manifest           = ".cache/hygiene_manifest.log"
  ),
  n_warnings = n_warn,
  warnings   = warnings_out
)
rep_path <- file.path(root, registry_zone, "hygiene_report.json")
write_json(report, rep_path, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
cat(sprintf("[hygiene] cleanup: %d 삭제 (logs %d / scratch %d / empty_dirs %d)%s\n",
            n_del, length(deleted$logs), length(deleted$scratch),
            length(deleted$empty_dirs), if (DRY) " [DRY-RUN — 실삭제 없음]" else ""))
cat(sprintf("[hygiene] report → %s (경고 %d건)\n", rep_path, n_warn))

if (n_warn > 0) {
  w <- function(...) cat(sprintf(...), file = stderr())
  w("[hygiene][WARN] 저장규칙 위반 %d건 감지 — %s 참조 (규칙: artifact-storage.md)\n",
    n_warn, file.path(registry_zone, "hygiene_report.json"))
  if (length(warnings_out$root_unauthorized))
    w("[hygiene][WARN] 루트 무허가 항목 %d: %s\n", length(warnings_out$root_unauthorized),
      paste(head(unlist(warnings_out$root_unauthorized), 10), collapse = ", "))
  if (length(warnings_out$infra_underscore))
    w("[hygiene][WARN] 02_Infrastructure '_' 파일 %d: %s\n", length(warnings_out$infra_underscore),
      paste(head(unlist(warnings_out$infra_underscore), 10), collapse = ", "))
  if (length(warnings_out$misplaced_outputs))
    w("[hygiene][WARN] 존 밖 산출물성 파일 %d: %s\n", length(warnings_out$misplaced_outputs),
      paste(head(unlist(warnings_out$misplaced_outputs), 10), collapse = ", "))
  if (sum(vapply(unindexed, length, 0L)) > 0)
    w("[hygiene][WARN] index_descriptions.json 미등재 최상위 항목 %d (존: %s)\n",
      sum(vapply(unindexed, length, 0L)), paste(names(unindexed), collapse = ", "))
}
cat("[hygiene] done\n")
