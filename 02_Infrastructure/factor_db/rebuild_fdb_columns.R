#==============================================================================
# rebuild_fdb_columns.R — 월간 factor DB **열 단위** 재빌드 (PIT C11 2단계 · 2026-09-25)
#
# 왜: C11 수리(가용시점 결합)로 값이 바뀐 팩터는 몇 개뿐인데 전체 재빌드(build_factor_db_monthly(force))는
#   수시간이 걸리고 다른 팩터를 흔든다(202603~07 빈티지 불일치 선례 — 판정서 ⑤ 안 B). 빌더의 기존 열 단위
#   도구 backfill_custom_factor() 는 (a) id 1개당 모듈 1회 호출(regime 3열 = 3배) (b) FUND 를 무필터로 넘김
#   (build_factor_db 는 Factor_Date <= sig_d 로 자른다) (c) 백업·원자 교체·열 제거가 없다 — 그래서 **같은 빌더
#   내부 함수**(.load_base_data · .preload_modules · .pit_rawdata · .standardize_factors · .FDB_SLICE_DAYS)를
#   그대로 쓰되 달마다 모듈 1회 · build_factor_db 와 같은 입력 슬라이스 · 열 제거 · 구판 월 파일 백업 · 원자 교체 ·
#   매니페스트를 붙였다. 빌더(factor_db_builder.R)는 **읽기만** 한다(변경 없음).
#
# 사양(무엇을 · 어느 달): 사양 JSON(예: 02_Infrastructure/factor_db/column_rebuild_c11_phase2.json) — 이 파일에 수치 없음.
#   recompute[] = 현행 코드로 재계산할 (id, module) · drop[] = 제거할 id(registry 비활성만 허용 — 활성 팩터 제거 = 배출 회귀라 거부)
#   range.from/to = 재계산 달 구간 · drop_scope = "all_months"(저장된 모든 달에서 제거) | "range"
#
# 불변식(달마다 쓰기 전에 검사 — 하나라도 어기면 그 달을 쓰지 않고 중단):
#   I1 비대상 행 불변 — recompute ∪ drop 밖의 모든 행이 구판과 행 집합으로 같다(fsetequal · 열·타입 동일)
#   I2 drop 열 부재 · I3 (Ticker, Factor_Name) 중복 0 · I4 Date 단일값 = 구판 Date
#   I5 대상 행 = 이번 재계산 표준화 결과와 동일(부분 기록 방지)
#   I6 배출: 새로 빠진 **활성** 팩터 ⊆ recompute 대상(대상이 PIT 로 산출 불가하면 오염값 제거 = 허용·기록)
#   쓰기 = tmp 기록 → 재판독 대조(행수·md5 안정) → file.rename(원자 교체). 구판은 백업 디렉터리에 1회만 복사(재실행이 덮지 않음).
#
# 사용 (ROOT 에서):
#   Rscript -e 'source("02_Infrastructure/factor_db/rebuild_fdb_columns.R")' --args --spec <json> --backup-dir <dir>
#       [--from YYYYMM] [--to YYYYMM] [--months YYYYMM,YYYYMM] [--fdb-dir <dir>] [--dry-run] [--no-ic] [--force]
#   Rscript -e 'source(".../rebuild_fdb_columns.R")' --args --spec <json> --verify-only --backup-dir <dir> [--sample N]
#   Rscript -e 'source(".../rebuild_fdb_columns.R")' --args --rollback <backup_dir> [--fdb-dir <dir>] [--force]
#   --fdb-dir 기본 = 빌더 FACTOR_DB_DIR(운영). 다른 디렉터리(스크래치 사본)면 IC 재계산·build_hash 갱신을 하지 않는다.
#   RFC_LIB_ONLY=1 이면 함수만 정의(검사용 — 08_Tests/factor_db/test_rebuild_fdb_columns.R).
# 종료: 0 정상 / 1 불변식 위반·검증 실패 / 2 입력·환경 오류
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
if (!exists("%||%")) `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.rfc_say <- function(...) { cat(sprintf(...)); flush(stdout()) }
.rfc_die <- function(code, ...) { cat("[rebuild_fdb_columns] ERROR ", sprintf(...), "\n", sep = ""); quit(status = code) }

#------------------------------------------------------------------------------
# 순수부 (빌더 불필요 — 검사가 합성 픽스처로 직접 구동)
#------------------------------------------------------------------------------

#' 사양 판독 + 형식 검증 (fail-closed)
rfc_read_spec <- function(path) {
  if (!file.exists(path)) stop("사양 파일 부재: ", path)
  s <- fromJSON(path, simplifyVector = FALSE)
  if (!identical(s$schema, "fdb_column_rebuild/v1")) stop("사양 schema 불일치: ", s$schema %||% "(없음)")
  rc <- s$recompute %||% list(); dr <- s$drop %||% list()
  ids_r <- vapply(rc, function(x) as.character(x$id %||% ""), character(1))
  mods  <- vapply(rc, function(x) as.character(x$module %||% ""), character(1))
  ids_d <- vapply(dr, function(x) as.character(x$id %||% ""), character(1))
  if (!length(ids_r) && !length(ids_d)) stop("사양에 recompute·drop 둘 다 비어 있음")
  if (any(!nzchar(ids_r)) || any(!nzchar(mods)) || any(!nzchar(ids_d))) stop("사양 id/module 공란")
  if (anyDuplicated(c(ids_r, ids_d))) stop("사양 id 중복(또는 recompute·drop 겹침): ",
                                           paste(c(ids_r, ids_d)[duplicated(c(ids_r, ids_d))], collapse = ","))
  fr <- as.character(s$range$from %||% ""); to <- as.character(s$range$to %||% "")
  if (length(ids_r) && (!grepl("^\\d{6}$", fr) || !grepl("^\\d{6}$", to) || fr > to))
    stop(sprintf("사양 range 형식 오류: from=%s to=%s", fr, to))
  ds <- as.character(s$drop_scope %||% "range")
  if (!ds %in% c("all_months", "range")) stop("drop_scope 는 all_months|range: ", ds)
  list(name = as.character(s$name %||% "unnamed"), targets = ids_r, modules = setNames(mods, ids_r),
       drops = ids_d, from = fr, to = to, drop_scope = ds, raw = s)
}

#' 사양을 registry 와 대조 — recompute 는 active 여야 하고(비활성 재계산 = 부활), drop 은 비활성이어야 한다
#'   (활성 팩터 제거 = 배출 회귀). module 은 적재된 compute 모듈 이름 중 하나.
rfc_check_spec_registry <- function(spec, registry, module_names = NULL) {
  st <- function(id) { e <- registry[[id]]; if (is.null(e)) return(NA_character_)
    s <- (e$lifecycle %||% list())$status; if (is.null(s) || !length(s)) "active" else as.character(s)[1] }
  bad <- character(0)
  for (id in spec$targets) {
    s <- st(id)
    if (is.na(s)) bad <- c(bad, sprintf("%s: registry 미등재", id))
    else if (!identical(s, "active")) bad <- c(bad, sprintf("%s: recompute 대상인데 status=%s", id, s))
    if (!is.null(module_names) && !spec$modules[[id]] %in% module_names)
      bad <- c(bad, sprintf("%s: module '%s' 미적재", id, spec$modules[[id]]))
  }
  for (id in spec$drops) {
    s <- st(id)
    if (!is.na(s) && identical(s, "active")) bad <- c(bad, sprintf("%s: drop 대상인데 status=active(배출 회귀)", id))
  }
  bad
}

#' 디렉터리의 월 파일 목록
rfc_month_files <- function(fdb_dir) {
  f <- sort(list.files(fdb_dir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
  data.table(ym = sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(f)), path = f)
}

#' 처리 계획 — 달마다 mode = recompute(구간 안) | drop_only(구간 밖·drop_scope all) | skip
rfc_plan <- function(month_dt, spec, from = spec$from, to = spec$to, months = NULL) {
  P <- copy(month_dt)
  in_rng <- if (length(spec$targets)) P$ym >= from & P$ym <= to else rep(FALSE, nrow(P))
  P[, mode := fifelse(in_rng, "recompute",
                      fifelse(length(spec$drops) > 0L & spec$drop_scope == "all_months", "drop_only", "skip"))]
  if (length(months)) P[!(ym %in% months), mode := "skip"]
  P[]
}

#' 재계산 표준화 결과(대상만)를 구판 모양으로 — Date = 구판 Date · 열 순서·타입 = 구판. 0행이면 0행 테이블.
rfc_shape_fresh <- function(fresh_std, targets, old) {
  if (is.null(fresh_std) || !nrow(fresh_std)) return(old[0L])
  add <- copy(fresh_std[Factor_Name %in% targets])
  if (!nrow(add)) return(old[0L])
  add[, Date := old$Date[1]]
  miss <- setdiff(names(old), names(add))
  if (length(miss)) stop("재계산 결과에 열 부재: ", paste(miss, collapse = ","))
  add <- add[, names(old), with = FALSE]
  for (cn in names(old)) if (!identical(class(add[[cn]]), class(old[[cn]]))) {
    cls <- class(old[[cn]])[1]
    v <- switch(cls, numeric = as.numeric(add[[cn]]), integer = as.integer(add[[cn]]),
                logical = as.logical(add[[cn]]), character = as.character(add[[cn]]),
                Date = as.Date(add[[cn]]), stop(sprintf("열 %s 타입 %s 로 맞출 수 없음", cn, cls)))
    set(add, j = cn, value = v)
  }
  add
}

#' 새 월 테이블 — 대상·drop 행을 빼고 재계산 표준화 결과(대상만)를 붙인다. 열 순서·Date 는 구판을 따른다.
rfc_new_month_dt <- function(old, fresh_std, targets, drops) {
  keep <- old[!(Factor_Name %in% c(targets, drops))]
  out <- rbindlist(list(keep, rfc_shape_fresh(fresh_std, targets, old)), use.names = TRUE)
  setcolorder(out, names(old))
  out
}

# 행 집합 동등 — 열 타입이 달라 fsetequal 이 던지면 '같지 않음'으로 접는다(예외로 검사가 죽지 않게)
.rfc_seteq <- function(a, b) isTRUE(tryCatch(fsetequal(a, b), error = function(e) FALSE))

#' 불변식 검사 — list(ok, fail = 사유 벡터, stats)
rfc_verify_month <- function(old, new, targets, drops, fresh_std = NULL, active_ids = NULL) {
  fail <- character(0)
  if (!identical(names(old), names(new))) fail <- c(fail, "I0 열 이름·순서 불일치")
  else for (cn in names(old)) if (!identical(class(old[[cn]]), class(new[[cn]])))
    fail <- c(fail, sprintf("I0 열 타입 불일치 %s", cn))
  touched <- c(targets, drops)
  a <- old[!(Factor_Name %in% touched)]; b <- new[!(Factor_Name %in% touched)]
  if (nrow(a) != nrow(b) || !.rfc_seteq(a, b)) fail <- c(fail, sprintf("I1 비대상 행 변경(구 %d · 신 %d)", nrow(a), nrow(b)))
  if (any(new$Factor_Name %in% drops)) fail <- c(fail, "I2 drop 열 잔존")
  if (anyDuplicated(new, by = c("Ticker", "Factor_Name"))) fail <- c(fail, "I3 (Ticker, Factor_Name) 중복")
  if (uniqueN(new$Date) != 1L || !identical(as.Date(new$Date[1]), as.Date(old$Date[1]))) fail <- c(fail, "I4 Date 불일치")
  if (!is.null(fresh_std) || length(targets)) {
    x <- new[Factor_Name %in% targets]; y <- rfc_shape_fresh(fresh_std, targets, old)
    if (nrow(x) != nrow(y) || (nrow(x) && !.rfc_seteq(x, y))) fail <- c(fail, "I5 대상 행 ≠ 재계산 결과")
  }
  lost <- character(0)
  if (!is.null(active_ids)) {
    ab_old <- setdiff(active_ids, unique(old$Factor_Name)); ab_new <- setdiff(active_ids, unique(new$Factor_Name))
    lost <- setdiff(ab_new, ab_old)
    extra <- setdiff(lost, targets)
    if (length(extra)) fail <- c(fail, sprintf("I6 비대상 활성 팩터 소실: %s", paste(extra, collapse = ",")))
  }
  st <- list()
  for (id in targets) {
    o <- old[Factor_Name == id, .(Ticker, ro = Raw_Value)]; n <- new[Factor_Name == id, .(Ticker, rn = Raw_Value)]
    m <- merge(o, n, by = "Ticker")
    sp <- if (nrow(m) >= 3L && sum(is.finite(m$ro) & is.finite(m$rn)) >= 3L &&
              stats::sd(m$ro, na.rm = TRUE) > 0 && stats::sd(m$rn, na.rm = TRUE) > 0)
            suppressWarnings(stats::cor(m$ro, m$rn, method = "spearman", use = "complete.obs")) else NA_real_
    st[[id]] <- list(n_old = nrow(o), n_new = nrow(n), n_common = nrow(m),
                     n_changed = sum(!(m$ro == m$rn) | xor(is.na(m$ro), is.na(m$rn)), na.rm = TRUE),
                     spearman_old_new = if (is.na(sp)) NA else round(sp, 6))
  }
  dropped <- setNames(lapply(drops, function(id) sum(old$Factor_Name == id)), drops)
  list(ok = !length(fail), fail = fail,
       stats = list(n_old = nrow(old), n_new = nrow(new), targets = st, dropped = dropped, target_lost = lost))
}

#' 원자 쓰기: tmp → 재판독 대조 → rename. 반환 = 새 md5
rfc_atomic_write <- function(dt, path) {
  tmp <- paste0(path, ".tmp_rfc_", Sys.getpid())
  write_parquet(dt, tmp)
  chk <- as.data.table(read_parquet(tmp, mmap = FALSE))
  if (nrow(chk) != nrow(dt) || !identical(names(chk), names(dt))) { unlink(tmp); stop("tmp 재판독 불일치: ", tmp) }
  md5 <- unname(tools::md5sum(tmp)); rm(chk); invisible(gc(verbose = FALSE))
  if (!file.rename(tmp, path)) { unlink(tmp); stop("원자 교체 실패(rename): ", path) }
  if (!identical(unname(tools::md5sum(path)), md5)) stop("교체 후 md5 불일치: ", path)
  md5
}

#' 구판 백업 — 백업 디렉터리에 없을 때만 복사(재실행이 '구판'을 덮지 않는다). 반환 = 백업 경로
rfc_backup_once <- function(path, bkdir) {
  dir.create(bkdir, recursive = TRUE, showWarnings = FALSE)
  dst <- file.path(bkdir, basename(path))
  if (!file.exists(dst)) {
    if (!file.copy(path, dst, copy.date = TRUE)) stop("백업 실패: ", path)
    if (!identical(unname(tools::md5sum(dst)), unname(tools::md5sum(path)))) stop("백업 md5 불일치: ", dst)
  }
  dst
}

#' 매니페스트(jsonl) 판독 — ym 별 마지막 기록
rfc_manifest_last <- function(bkdir) {
  p <- file.path(bkdir, "manifest.jsonl")
  if (!file.exists(p)) return(list())
  out <- list()
  for (ln in readLines(p, warn = FALSE, encoding = "UTF-8")) {
    o <- tryCatch(fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(o$ym)) out[[as.character(o$ym)]] <- o
  }
  out
}
rfc_manifest_append <- function(bkdir, rec) {
  cat(toJSON(rec, auto_unbox = TRUE, null = "null", na = "null", digits = NA), "\n",
      sep = "", file = file.path(bkdir, "manifest.jsonl"), append = TRUE)
}

#' 한 달 처리 (순수 + IO). compute_fn(sig_d) → list(std = 대상 표준화 결과 | NULL, drift = 진단)
#'   반환 = 매니페스트 레코드. dry_run 이면 쓰지 않는다.
rfc_process_month <- function(ym, path, mode, spec, bkdir, compute_fn = NULL, active_ids = NULL,
                              dry_run = FALSE, prev = NULL, force = FALSE) {
  md5_now <- unname(tools::md5sum(path))
  if (!is.null(prev) && identical(prev$status, "done")) {
    if (identical(prev$md5_after, md5_now)) return(list(ym = ym, status = "already_done", mode = mode))
    if (!identical(prev$md5_before, md5_now) && !force)
      stop(sprintf("%s: 파일이 매니페스트 기록(재빌드 후 %s)과 다르다 — 외부 변경 의심. --force 로만 재처리",
                   ym, substr(prev$md5_after, 1, 8)))
  }
  old <- as.data.table(read_parquet(path, mmap = FALSE))
  if (!nrow(old) || !"Date" %in% names(old)) stop(sprintf("%s: 빈 파일/Date 없음", ym))
  sig_d <- as.Date(old$Date[1])
  tg <- if (identical(mode, "recompute")) spec$targets else character(0)
  present_drop <- intersect(spec$drops, unique(old$Factor_Name))
  if (identical(mode, "drop_only") && !length(present_drop))
    return(list(ym = ym, status = "noop", mode = mode, sig_date = as.character(sig_d)))
  comp <- if (length(tg)) compute_fn(sig_d) else list(std = NULL, drift = NULL)
  new <- rfc_new_month_dt(old, comp$std, tg, spec$drops)
  v <- rfc_verify_month(old, new, tg, spec$drops, fresh_std = if (length(tg)) comp$std else NULL,
                        active_ids = active_ids)
  rec <- list(ym = ym, file = basename(path), mode = mode, sig_date = as.character(sig_d),
              md5_before = md5_now, n_before = nrow(old), n_after = nrow(new),
              stats = v$stats, drift_untargeted = comp$drift, fail = v$fail,
              ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (!v$ok) { rec$status <- "invariant_fail"; return(rec) }
  if (dry_run) { rec$status <- "dry_run_ok"; return(rec) }
  rfc_backup_once(path, bkdir)
  rec$md5_after <- rfc_atomic_write(new, path)
  rec$status <- "done"
  rec
}

#' 롤백 — 백업 월 파일을 원자 복원. 현재 파일이 매니페스트의 재빌드 후 md5 와 다르면(그 뒤 누가 또 썼다) --force 없이 거부
rfc_rollback <- function(bkdir, fdb_dir, force = FALSE) {
  man <- rfc_manifest_last(bkdir)
  bks <- sort(list.files(bkdir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
  n_ok <- 0L; skipped <- character(0)
  for (b in bks) {
    ym <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(b)); dst <- file.path(fdb_dir, basename(b))
    cur <- if (file.exists(dst)) unname(tools::md5sum(dst)) else NA_character_
    exp_after <- man[[ym]]$md5_after %||% NA_character_
    if (!is.na(cur) && !is.na(exp_after) && !identical(cur, exp_after) && !force) {
      skipped <- c(skipped, ym); next
    }
    tmp <- paste0(dst, ".tmp_rfc_rb_", Sys.getpid())
    if (!file.copy(b, tmp, overwrite = TRUE, copy.date = TRUE)) stop("롤백 복사 실패: ", b)
    if (!file.rename(tmp, dst)) { unlink(tmp); stop("롤백 교체 실패: ", dst) }
    if (!identical(unname(tools::md5sum(dst)), unname(tools::md5sum(b)))) stop("롤백 md5 불일치: ", dst)
    n_ok <- n_ok + 1L
  }
  for (aux in c("factor_ic_monthly.parquet", "build_hash.txt")) {
    b <- file.path(bkdir, aux)
    if (file.exists(b) && !identical(normalizePath(fdb_dir, winslash = "/", mustWork = FALSE),
                                     normalizePath(bkdir, winslash = "/", mustWork = FALSE))) {
      tmp <- file.path(fdb_dir, paste0(aux, ".tmp_rfc_rb"))
      file.copy(b, tmp, overwrite = TRUE, copy.date = TRUE); file.rename(tmp, file.path(fdb_dir, aux))
    }
  }
  list(restored = n_ok, skipped_changed = skipped)
}

#------------------------------------------------------------------------------
# 빌더 결합부 (운영 데이터 적재 — 읽기만)
#------------------------------------------------------------------------------

#' 빌더 적재 + C11 표지 확인. 반환 = list(regime_key, module_names)
rfc_load_builder <- function(root) {
  if (!exists("PROJECT_ROOT")) source(file.path(root, "02_Infrastructure", "config.R"))
  if (!exists(".load_base_data")) source(file.path(root, "02_Infrastructure", "factor_db", "factor_db_builder.R"))
  .load_base_data(); .preload_modules()
  st <- .fdb_env$C11_STATUS %||% list()
  list(vix = as.character(st$vix %||% "?"), regime_key = as.character(st$regime_key %||% NA_character_),
       module_names = names(.fdb_env$module_funcs))
}

#' 달 하나의 대상 재계산 — build_factor_db 와 **같은 입력 슬라이스**(RAWDATA .FDB_SLICE_DAYS · FUND_pit · CONSENSUS)로
#'   필요한 모듈만 1회씩 호출. 대상 외 산출 팩터는 저장값과 대조만 한다(비대상 드리프트 = 진단, 쓰지 않음).
rfc_make_compute_fn <- function(spec, old_reader = NULL) {
  mods <- unique(unname(spec$modules))
  function(sig_d) {
    RAW <- .fdb_env$RAWDATA[Date <= sig_d & Date >= (sig_d - .FDB_SLICE_DAYS)]
    setkey(RAW, Date, Ticker)
    FUND_pit <- if (!is.null(.fdb_env$FUND) && nrow(.fdb_env$FUND) > 0L) .fdb_env$FUND[Factor_Date <= sig_d] else NULL
    outs <- list()
    for (m in mods) {
      fn <- .fdb_env$module_funcs[[m]]
      if (is.null(fn)) stop("모듈 미적재: ", m)
      r <- fn(RAWDATA = RAW, sig_date = sig_d, FUND = FUND_pit, CONSENSUS = .fdb_env$CONSENSUS)
      outs[[m]] <- if (is.null(r)) NULL else as.data.table(r)
    }
    allout <- rbindlist(outs, use.names = TRUE, fill = TRUE)
    raw_t <- if (nrow(allout)) allout[Factor_Name %in% spec$targets, .(Ticker, Factor_Name, Raw_Value)] else NULL
    snap <- .pit_rawdata(sig_d)
    std <- if (!is.null(raw_t) && nrow(raw_t)) .standardize_factors(copy(raw_t), snap[, .(Ticker, Sector)]) else NULL
    drift <- NULL
    if (!is.null(old_reader) && nrow(allout)) {
      others <- allout[!(Factor_Name %in% c(spec$targets, spec$drops)), .(Ticker, Factor_Name, rn = Raw_Value)]
      od <- old_reader()[Factor_Name %in% unique(others$Factor_Name), .(Ticker, Factor_Name, ro = Raw_Value)]
      mm <- merge(od, others, by = c("Ticker", "Factor_Name"), all = TRUE)
      dd <- mm[, .(n_diff = sum(xor(is.na(ro), is.na(rn)) | (!is.na(ro) & !is.na(rn) & abs(ro - rn) > 1e-10))), by = Factor_Name][n_diff > 0L]
      drift <- list(n_other_factors = uniqueN(others$Factor_Name), n_drifted = nrow(dd),
                    top = if (nrow(dd)) head(dd[order(-n_diff)], 5L) else NULL)
    }
    list(std = std, drift = drift)
  }
}

#------------------------------------------------------------------------------
# 진입점
#------------------------------------------------------------------------------
rfc_parse_args <- function(a) {
  g <- function(k, d = NA_character_) { i <- which(a == k); if (length(i) && length(a) > i[1]) a[i[1] + 1L] else d }
  list(spec = g("--spec"), backup_dir = g("--backup-dir"), from = g("--from"), to = g("--to"),
       months = { m <- g("--months"); if (is.na(m)) NULL else strsplit(m, ",", fixed = TRUE)[[1]] },
       fdb_dir = g("--fdb-dir"), rollback = g("--rollback"), sample = as.integer(g("--sample", "6")),
       dry_run = "--dry-run" %in% a, verify_only = "--verify-only" %in% a,
       no_ic = "--no-ic" %in% a, force = "--force" %in% a)
}

rfc_main <- function(argv = commandArgs(trailingOnly = TRUE)) {
  A <- rfc_parse_args(argv)
  root <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
  if (!file.exists(file.path(root, "02_Infrastructure", "config.R"))) .rfc_die(2, "ROOT 해석 실패: %s", root)

  # ── 롤백 ──
  if (!is.na(A$rollback)) {
    if (is.na(A$fdb_dir)) { source(file.path(root, "02_Infrastructure", "config.R")); A$fdb_dir <- file.path(CACHE_DIR, "factor_db") }
    r <- rfc_rollback(A$rollback, A$fdb_dir, force = A$force)
    .rfc_say("[rebuild_fdb_columns] 롤백: 복원 %d개 · 외부 변경으로 건너뜀 %d개%s\n", r$restored, length(r$skipped_changed),
             if (length(r$skipped_changed)) paste0(" (", paste(head(r$skipped_changed, 8), collapse = ","), " — --force 로만)") else "")
    quit(status = if (length(r$skipped_changed)) 1L else 0L)
  }

  if (is.na(A$spec)) .rfc_die(2, "--spec 필수")
  spec_path <- if (file.exists(A$spec)) A$spec else file.path(root, A$spec)
  spec <- tryCatch(rfc_read_spec(spec_path), error = function(e) .rfc_die(2, "%s", conditionMessage(e)))
  if (is.na(A$backup_dir)) .rfc_die(2, "--backup-dir 필수(구판 월 파일·매니페스트 위치)")

  env <- tryCatch(rfc_load_builder(root), error = function(e) .rfc_die(2, "빌더 적재 실패: %s", conditionMessage(e)))
  fdb_dir <- if (is.na(A$fdb_dir)) FACTOR_DB_DIR else A$fdb_dir
  operational <- identical(normalizePath(fdb_dir, winslash = "/", mustWork = FALSE),
                           normalizePath(FACTOR_DB_DIR, winslash = "/", mustWork = FALSE))
  reg <- fromJSON(FACTOR_REG_PATH, simplifyVector = FALSE)
  bad <- rfc_check_spec_registry(spec, reg, env$module_names)
  if (length(bad)) .rfc_die(2, "사양-registry 불일치: %s", paste(bad, collapse = " | "))
  if (length(spec$targets) && any(spec$modules == "defense") && !identical(env$vix, "ok"))
    .rfc_die(2, "VIX 가용일 결합 실패(C11_STATUS vix=%s) — D32 재계산 불가(fail-closed)", env$vix)
  active_ids <- names(reg)[vapply(reg, function(e) { s <- (e$lifecycle %||% list())$status
                                    is.null(s) || !length(s) || identical(as.character(s)[1], "active") }, logical(1))]
  .rfc_say("[rebuild_fdb_columns] 사양 %s · 재계산 %s · 제거 %s · 구간 %s~%s · fdb=%s(%s) · C11 key=%s\n",
           spec$name, paste(spec$targets, collapse = ","), paste(spec$drops, collapse = ","),
           if (is.na(A$from)) spec$from else A$from, if (is.na(A$to)) spec$to else A$to,
           fdb_dir, if (operational) "운영" else "사본", env$regime_key)

  MF <- rfc_month_files(fdb_dir)
  plan <- rfc_plan(MF, spec, from = if (is.na(A$from)) spec$from else A$from,
                   to = if (is.na(A$to)) spec$to else A$to, months = A$months)
  .rfc_say("[rebuild_fdb_columns] 계획: recompute %d · drop_only %d · skip %d (전체 %d)\n",
           sum(plan$mode == "recompute"), sum(plan$mode == "drop_only"), sum(plan$mode == "skip"), nrow(plan))

  # ── 검증 전용: 모든 달 drop 부재 + 표본 달 대상 재계산 = 저장값 ──
  if (isTRUE(A$verify_only)) {
    fails <- character(0)
    for (i in seq_len(nrow(plan))) {
      fn <- as.data.table(read_parquet(plan$path[i], mmap = FALSE, col_select = "Factor_Name"))
      if (any(fn$Factor_Name %in% spec$drops) && plan$mode[i] != "skip") fails <- c(fails, sprintf("%s drop 잔존", plan$ym[i]))
    }
    rc_m <- plan[mode == "recompute"]
    # 표본 = 구간 양끝 포함 등간격(결정론 — 재실행해도 같은 달)
    smp <- if (nrow(rc_m) <= A$sample) rc_m$ym else rc_m$ym[unique(round(seq(1, nrow(rc_m), length.out = A$sample)))]
    cf <- rfc_make_compute_fn(spec)
    for (ym in smp) {
      p <- plan$path[match(ym, plan$ym)]
      cur <- as.data.table(read_parquet(p, mmap = FALSE))
      cmp <- cf(as.Date(cur$Date[1]))
      v <- rfc_verify_month(cur, cur, spec$targets, spec$drops, fresh_std = cmp$std, active_ids = active_ids)
      i5 <- grep("^I5|^I2|^I3", v$fail, value = TRUE)
      .rfc_say("  [verify] %s — %s\n", ym, if (length(i5)) paste(i5, collapse = " · ") else "대상 = 현행 코드 재계산 · drop 부재 · 중복 0")
      if (length(i5)) fails <- c(fails, sprintf("%s %s", ym, paste(i5, collapse = "/")))
    }
    man <- rfc_manifest_last(A$backup_dir)
    nd <- sum(vapply(man, function(o) identical(o$status, "done"), logical(1)))
    .rfc_say("[rebuild_fdb_columns] 검증: drop 잔존 달 %d · 표본 %d달 불일치 %d · 매니페스트 done %d\n",
             length(grep("drop 잔존", fails)), length(smp), length(grep("drop 잔존", fails, invert = TRUE)), nd)
    if (length(fails)) { .rfc_say("  실패: %s\n", paste(head(fails, 10), collapse = " | ")); quit(status = 1L) }
    .rfc_say("[rebuild_fdb_columns] VERIFY OK\n"); quit(status = 0L)
  }

  # ── 실행 ──
  dir.create(A$backup_dir, recursive = TRUE, showWarnings = FALSE)
  if (operational && !A$dry_run) for (aux in c("factor_ic_monthly.parquet", "build_hash.txt")) {
    p <- file.path(fdb_dir, aux); if (file.exists(p)) rfc_backup_once(p, A$backup_dir)
  }
  man <- rfc_manifest_last(A$backup_dir)
  n_done <- 0L; n_fail <- 0L; t0 <- Sys.time(); todo <- plan[mode != "skip"]
  for (i in seq_len(nrow(todo))) {
    ym <- todo$ym[i]; p <- todo$path[i]
    old_reader <- local({ pp <- p; function() as.data.table(read_parquet(pp, mmap = FALSE)) })
    cf <- rfc_make_compute_fn(spec, old_reader = old_reader)
    rec <- tryCatch(rfc_process_month(ym, p, todo$mode[i], spec, A$backup_dir, compute_fn = cf,
                                      active_ids = active_ids, dry_run = A$dry_run, prev = man[[ym]], force = A$force),
                    error = function(e) list(ym = ym, status = "error", mode = todo$mode[i], fail = conditionMessage(e)))
    if (!rec$status %in% c("already_done", "noop") && !A$dry_run) rfc_manifest_append(A$backup_dir, rec)
    if (rec$status == "done") n_done <- n_done + 1L
    if (rec$status %in% c("invariant_fail", "error")) {
      n_fail <- n_fail + 1L
      .rfc_say("  [FAIL] %s %s: %s\n", ym, rec$status, paste(unlist(rec$fail), collapse = " | "))
      break   # 첫 위반에서 멈춘다 — 이후 달은 손대지 않는다(롤백 범위 최소)
    }
    el <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
    if (i %% 12L == 0L || i == nrow(todo) || i <= 2L) {
      tg <- rec$stats$targets %||% list()
      .rfc_say("  [%d/%d] %s %s %s · %s · 경과 %.1f분 · ETA %.0f분\n", i, nrow(todo), ym, rec$mode, rec$status,
               paste(vapply(names(tg), function(k) sprintf("%s %s→%s ρ=%s", sub("_.*", "", k), tg[[k]]$n_old, tg[[k]]$n_new,
                                                          format(tg[[k]]$spearman_old_new)), character(1)), collapse = " "),
               el, el / i * (nrow(todo) - i))
    }
  }
  .rfc_say("[rebuild_fdb_columns] 완료: 기록 %d · 실패 %d · %.1f분%s\n", n_done, n_fail,
           as.numeric(difftime(Sys.time(), t0, units = "mins")), if (A$dry_run) " (dry-run — 쓰기 0)" else "")
  if (n_fail) quit(status = 1L)
  if (operational && !A$dry_run && n_done > 0L) {
    .write_build_hash()
    if (!A$no_ic) { .rfc_say("[rebuild_fdb_columns] IC 재계산(compute_all_factor_ic_monthly)...\n"); compute_all_factor_ic_monthly() }
  }
  quit(status = 0L)
}

if (!nzchar(Sys.getenv("RFC_LIB_ONLY", ""))) rfc_main()
