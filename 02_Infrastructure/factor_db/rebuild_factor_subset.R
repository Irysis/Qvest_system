#!/usr/bin/env Rscript
#==============================================================================
# rebuild_factor_subset.R — 빌더 결함 수리 뒤 영향 팩터만 전 기간 다시 계산해 월 파일에 바꿔 끼운다
#   (2026-11-09 · decision_register FACTOR-DIRECTION-STORAGE-REPAIR-20261109 · 도훈 '재무DB v2 기준으로 팩터 계산 다시해')
#
# 왜: 월간 빌더에 두 결함이 있었다(서브에이전트 코드 감사).
#   ① XF 채우기(factor_db_builder.R .XF_TO_DART) — DART 에 없는 종목을 엑셀(퀀티) XF 값으로 채울 때 이름만 바꿔 넣어,
#      DART 쪽이 음수로 저장하는 Q05 · Q15 · GR03 · AC05 는 채움 행만 부호가 반대였고 V08_PSR 은 채움 행이 역수였다.
#   ② XF 계열 DART 쪽 정의(compute_quality_xf_native.R)가 등록부 · 엑셀 쪽과 다른 양이었다 — LL05(금액 대 비율) · PR02(분모) ·
#      EF01(분자) · GD02 · GD03(전기 음수면 부호 반전) · RI02(절댓값 대 음수화) · PR04(엑셀 쪽 = 순이자비용/총자산).
#   수리된 코드로 대상 팩터만 다시 계산한다 — 다른 팩터는 같은 코드라 다시 계산해도 값이 같다(전체 재빌드 ≈ 10시간 대신).
#
# 방법(달마다): build_factor_db(sig_d, save = FALSE, force = TRUE, modules = MODS) — 재무 모듈만 돌리고 빌더의 XF 병합 · 표준화를
#   그대로 탄다(표준화는 팩터별 독립 — backfill_custom_factor 와 같은 전제) → 대상 팩터 행만 골라 기존 월 파일의 그 팩터 행과 교체 →
#   임시 파일에 쓰고 덮어쓰기(빌더 관례 · Windows 매핑 잠금 회피 = 읽기 mmap = FALSE).
# 단정(달마다 · 어기면 그 달은 쓰지 않는다): 대상 밖 행은 옛 파일과 같다(행 수 · 값) · 열 이름 · 순서 · 형이 같다 · 새 행 Date = 신호일.
# 기록: .cache/factor_db/subset_rebuild_log.jsonl(달 · 팩터별 옛/새 행 수 · 부호 반전 · 역수 · 그대로 · 바뀜 행 수 · 코드 rev · 시각).
#
# 사용:
#   Rscript 02_Infrastructure/factor_db/rebuild_factor_subset.R [--from YYYYMM] [--to YYYYMM] [--months YYYYMM,...] [--dry-run]
#                                  [--log PATH] [--no-hash]   # 병렬 작업자 = 달 범위를 나누고 --log 를 따로 · 해시는 끝에 한 번(.write_build_hash)
#   Rscript 02_Infrastructure/factor_db/rebuild_factor_subset.R --check-full YYYYMM   # 양성 대조: 부분 산출 = 전체 산출(대상 팩터 · 쓰기 없음)
#   ★월간 재빌드가 도는 동안에는 그 재빌드가 아직 안 지은 달을 건드리지 않는다(뒤에 옛 코드로 다시 덮인다) — --to 로 막는다.
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
if (!exists("%||%", mode = "function")) `%||%` <- function(a, b) if (is.null(a)) b else a

.rfs_root <- function() {
  r <- Sys.getenv("QM_ROOT", "")
  if (!nzchar(r)) r <- getwd()
  gsub("\\\\", "/", r)
}

RFS_TARGET <- c("Q05_Accrual", "Q15_Debt_to_Equity", "GR03_Asset_Growth", "AC05_NOA", "V08_PSR",
                "XF_LL05_WorkingCapital", "XF_PR02_RetainedEarnings_Ratio", "XF_EF01_InventoryTurnover",
                "XF_GD02_OpProfit_Growth", "XF_GD03_OCF_Growth", "XF_RI02_CapEx_proxy", "XF_PR04_NetInterestMargin")
RFS_MODS <- c("value", "quality", "quality_xf_native", "accrual", "growth", "xlsx_fund")
RFS_FILL_NEG <- c("Q05_Accrual", "Q15_Debt_to_Equity", "GR03_Asset_Growth", "AC05_NOA")   # 채움 행 = −옛 값
RFS_FILL_RECIP <- "V08_PSR"                                                                # 채움 행 = 1/옛 값

.rfs_load <- function(root) {
  setwd(file.path(root, "02_Infrastructure"))
  suppressMessages(source("config.R"))
  invisible(capture.output(source("factor_db/factor_db_builder.R")))
  setwd(root)
}

# 다른 팩터 빌드(월간 재빌드 · 일간 phase · 재빌드 스크립트)가 돌고 있으면 그 이름 목록 — 쓰기 전에 거부한다(그 빌드가 아직 안 지은 달을
#   바꿔 끼우면 뒤에 옛 코드로 다시 덮이고, 같은 파일을 동시에 쓰면 손상된다). 이 도구 자신의 명령줄에는 빌더 이름이 없다.
.rfs_other_builds <- function() {
  cmd <- paste0("Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne ", Sys.getpid(),
                " -and $_.CommandLine -match 'factor_db_builder|factor_db_daily_phase|run_fdb_rebuild|run_factor_db_full_rebuild'",
                " -and $_.CommandLine -notmatch 'Get-CimInstance|rebuild_factor_subset|rfs_other_builds' } | ",
                "ForEach-Object { [string]$_.ProcessId + ' ' + $_.Name }")
  out <- tryCatch(system2("powershell.exe", c("-NoProfile", "-Command", shQuote(cmd)), stdout = TRUE, stderr = FALSE),
                  error = function(e) character(0))
  out <- trimws(out); out[nzchar(out) & !grepl("powershell", out, ignore.case = TRUE)]
}

.rfs_compare <- function(old, new, f) {
  o <- old[Factor_Name == f, .(Ticker, ov = Raw_Value)]
  n <- new[Factor_Name == f, .(Ticker, nv = Raw_Value)]
  m <- merge(o, n, by = "Ticker", all = TRUE)
  same <- m[is.finite(ov) & is.finite(nv) & abs(nv - ov) <= 1e-9 * pmax(1, abs(ov)), .N]
  neg <- m[is.finite(ov) & is.finite(nv) & abs(ov) > 1e-12 & abs(nv + ov) <= 1e-9 * pmax(1, abs(ov)), .N]
  rec <- m[is.finite(ov) & is.finite(nv) & abs(ov) > 1e-12 & abs(nv * ov - 1) <= 1e-9, .N]
  list(n_old = o[, .N], n_new = n[, .N], same = same, negated = neg, reciprocal = rec,
       changed = m[is.finite(ov) & is.finite(nv), .N] - same - neg - rec,
       only_old = m[is.finite(ov) & !is.finite(nv), .N], only_new = m[!is.finite(ov) & is.finite(nv), .N],
       big_abs_old = o[abs(ov) > 1e3, .N], big_abs_new = n[abs(nv) > 1e3, .N])
}

rebuild_factor_subset <- function(root = .rfs_root(), months = NULL, from = NULL, to = NULL, dry_run = FALSE,
                                  log_path = NULL, verbose = TRUE, write_hash = TRUE, allow_concurrent = FALSE) {
  if (!dry_run && !isTRUE(allow_concurrent)) {
    ob <- .rfs_other_builds()
    if (length(ob)) stop("[subset] 다른 팩터 빌드가 돌고 있다 — 끝난 뒤 다시(쓰기 거부): ", paste(ob, collapse = " · "))
  }
  .rfs_load(root)
  fdir <- FACTOR_DB_DIR
  files <- sort(list.files(fdir, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
  yms <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(files))
  sel <- rep(TRUE, length(files))
  if (!is.null(months)) sel <- yms %in% months
  if (!is.null(from)) sel <- sel & yms >= from
  if (!is.null(to)) sel <- sel & yms <= to
  files <- files[sel]; yms <- yms[sel]
  log_path <- log_path %||% file.path(fdir, "subset_rebuild_log.jsonl")
  rev <- tryCatch(system2("git", c("-C", root, "rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)
  cat(sprintf("[subset] 대상 %d개 달 · 팩터 %d · 모듈 %s · dry_run=%s\n", length(files), length(RFS_TARGET),
              paste(RFS_MODS, collapse = ","), dry_run))
  t0 <- Sys.time(); n_done <- 0L; n_bad <- 0L
  for (i in seq_along(files)) {
    fp <- files[i]; ym <- yms[i]; t1 <- Sys.time()
    fi0 <- file.info(fp)[, c("size", "mtime")]
    old <- as.data.table(read_parquet(fp, mmap = FALSE))
    sig_d <- as.Date(old$Date[1])
    invisible(capture.output(res <- build_factor_db(sig_d, save = FALSE, force = TRUE, modules = RFS_MODS)))
    if (is.null(res) || !nrow(res)) { cat(sprintf("  [ERR %s] 부분 산출 비어 있음\n", ym)); n_bad <- n_bad + 1L; next }
    res <- as.data.table(res)
    new <- res[Factor_Name %in% RFS_TARGET]
    miss <- setdiff(names(old), names(new))
    if (length(miss)) { cat(sprintf("  [ERR %s] 새 행에 없는 열: %s\n", ym, paste(miss, collapse = ","))); n_bad <- n_bad + 1L; next }
    new <- new[, names(old), with = FALSE]
    for (cn in names(old)) if (!identical(class(old[[cn]]), class(new[[cn]]))) {
      cv <- switch(class(old[[cn]])[1], Date = as.Date(new[[cn]]), numeric = as.numeric(new[[cn]]),
                   logical = as.logical(new[[cn]]), character = as.character(new[[cn]]), integer = as.integer(new[[cn]]),
                   stop(sprintf("[subset] 열 형 변환 모름: %s (%s → %s)", cn, class(new[[cn]])[1], class(old[[cn]])[1])))
      set(new, j = cn, value = cv)
    }
    keep <- old[!Factor_Name %in% RFS_TARGET]
    out <- rbindlist(list(keep, new), use.names = TRUE)
    ok <- nrow(keep) + nrow(new) == nrow(out) && nrow(new) > 0L && all(new$Date == sig_d) && identical(names(out), names(old)) &&
      identical(vapply(out, function(z) class(z)[1], ""), vapply(old, function(z) class(z)[1], ""))
    cmp <- setNames(lapply(RFS_TARGET, function(f) .rfs_compare(old, new, f)), RFS_TARGET)
    rec <- list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), ym = ym, sig_date = format(sig_d), code_rev = rev,
                dry_run = dry_run, ok = ok, rows_old = nrow(old), rows_new = nrow(out), per_factor = cmp,
                secs = round(as.numeric(difftime(Sys.time(), t1, units = "secs")), 1))
    if (!ok) { cat(sprintf("  [ERR %s] 단정 실패(대상 밖 행 · 열 · 날짜) — 쓰지 않음\n", ym)); n_bad <- n_bad + 1L }
    if (ok && !dry_run) {
      # 낙관적 동시성 — 읽은 뒤 다른 쓰기(예: 일일 체인 [6d] 백필)가 이 파일을 바꿨으면 이번 결과는 옛 내용 기준이라 쓰지 않는다.
      fi1 <- file.info(fp)[, c("size", "mtime")]
      if (!identical(fi0$size, fi1$size) || !identical(as.numeric(fi0$mtime), as.numeric(fi1$mtime))) {
        cat(sprintf("  [RETRY %s] 읽은 뒤 파일이 바뀜(동시 쓰기) — 이 달은 다음 실행/--verify 가 다시 한다\n", ym))
        rec$ok <- FALSE; rec$concurrent_change <- TRUE; n_bad <- n_bad + 1L
        cat(toJSON(rec, auto_unbox = TRUE, digits = NA), "\n", file = log_path, append = TRUE, sep = "")
        next
      }
      tmp <- paste0(fp, ".subset_tmp")
      write_parquet(out, tmp)
      rm(old); gc()
      if (!file.copy(tmp, fp, overwrite = TRUE)) { file.remove(tmp); stop("[subset] 덮어쓰기 실패: ", fp) }
      file.remove(tmp)
      # 쓴 뒤 다시 읽어 대조 — 대상 밖 행 = 옛 파일 그대로 · 대상 행 = 새 값(쓰기 손상 검거). 어긋나면 멈춘다(그 달은 build_factor_db(save = TRUE) 로 다시 짓는다).
      back <- as.data.table(read_parquet(fp, mmap = FALSE))
      chk_keep <- isTRUE(all.equal(back[!Factor_Name %in% RFS_TARGET][order(Factor_Name, Ticker)],
                                   keep[order(Factor_Name, Ticker)], check.attributes = FALSE))
      chk_new <- isTRUE(all.equal(back[Factor_Name %in% RFS_TARGET][order(Factor_Name, Ticker)],
                                  new[order(Factor_Name, Ticker)], check.attributes = FALSE))
      rm(back); gc()
      if (!chk_keep || !chk_new) stop(sprintf("[subset] 쓴 뒤 대조 실패 %s (대상 밖 %s · 대상 %s) — 이 달을 build_factor_db(save = TRUE) 로 다시 지을 것", ym, chk_keep, chk_new))
      fi2 <- file.info(fp)[, c("size", "mtime")]
      rec$written_size <- as.numeric(fi2$size); rec$written_mtime <- as.numeric(fi2$mtime)
      n_done <- n_done + 1L
    }
    cat(toJSON(rec, auto_unbox = TRUE, digits = NA), "\n", file = log_path, append = TRUE, sep = "")
    if (verbose) {
      q05 <- cmp[["Q05_Accrual"]]; v08 <- cmp[["V08_PSR"]]; ll5 <- cmp[["XF_LL05_WorkingCapital"]]
      cat(sprintf("  %s ok=%s · Q05 그대로 %d · 부호반전 %d · 바뀜 %d | V08 역수 %d | LL05 |x|>1e3 %d→%d · %.0fs\n", ym, ok,
                  q05$same, q05$negated, q05$changed, v08$reciprocal,
                  ll5$big_abs_old, ll5$big_abs_new, rec$secs))
    }
  }
  if (isTRUE(write_hash) && n_done > 0L && exists(".write_build_hash", mode = "function")) .write_build_hash()
  cat(sprintf("[subset] 끝: 쓴 달 %d · 실패 %d · %.1f분\n", n_done, n_bad, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  invisible(list(done = n_done, bad = n_bad))
}

# 잃은 쓰기 검사: 기록(--log 들)에 남긴 쓴 직후 지문(크기 · 수정 시각)과 지금 파일이 다르면 그 뒤 다른 쓰기가 덮은 것 —
#   그 달 목록을 돌려준다(진행기가 다시 돌린다). 기록에 없는 달(아직 안 한 달)도 함께 돌려준다.
verify_subset_writes <- function(log_paths, root = .rfs_root(), exclude = NULL) {
  .rfs_load(root)
  recs <- unlist(lapply(log_paths[file.exists(log_paths)], function(lp) lapply(readLines(lp, warn = FALSE), function(l)
    tryCatch(fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))), recursive = FALSE)
  recs <- Filter(function(r) !is.null(r) && isTRUE(r$ok) && !isTRUE(r$dry_run) && !is.null(r$written_mtime), recs)
  last <- list(); for (r in recs) last[[r$ym]] <- r
  files <- sort(list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE))
  yms <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(files))
  keep <- !(yms %in% exclude); files <- files[keep]; yms <- yms[keep]
  bad <- character(0)
  for (i in seq_along(files)) {
    r <- last[[yms[i]]]
    if (is.null(r)) { bad <- c(bad, yms[i]); next }
    fi <- file.info(files[i])
    if (!isTRUE(all.equal(as.numeric(fi$size), r$written_size)) || abs(as.numeric(fi$mtime) - r$written_mtime) > 1e-3) bad <- c(bad, yms[i])
  }
  cat(sprintf("[verify] 달 %d · 기록 %d · 다시 할 달 %d%s\n", length(files), length(last), length(bad),
              if (length(bad)) paste0(": ", paste(head(bad, 20), collapse = ","), if (length(bad) > 20) " …" else "") else ""))
  invisible(bad)
}

# 양성 대조: 같은 달을 전 모듈로 지은 값과 부분 산출 값이 대상 팩터에서 같은가(쓰기 없음)
check_full_equivalence <- function(ym, root = .rfs_root()) {
  .rfs_load(root)
  fp <- file.path(FACTOR_DB_DIR, sprintf("factor_db_%s.parquet", ym))
  sig_d <- as.Date(read_parquet(fp, col_select = "Date", mmap = FALSE)$Date[1])
  invisible(capture.output(full <- as.data.table(build_factor_db(sig_d, save = FALSE, force = TRUE))))
  invisible(capture.output(part <- as.data.table(build_factor_db(sig_d, save = FALSE, force = TRUE, modules = RFS_MODS))))
  cols <- c("Ticker", "Factor_Name", "Raw_Value", "Z_Score", "Z_Sector", "Rank_Pct", "Coverage")
  a <- full[Factor_Name %in% RFS_TARGET, ..cols][order(Factor_Name, Ticker)]
  b <- part[Factor_Name %in% RFS_TARGET, ..cols][order(Factor_Name, Ticker)]
  eq <- isTRUE(all.equal(a, b, check.attributes = FALSE))
  cat(sprintf("[check_full %s] 대상 팩터 행 전체 %d · 부분 %d · 같음 = %s\n", ym, nrow(a), nrow(b), eq))
  invisible(eq)
}

if (sys.nframe() == 0L) {
  a <- commandArgs(trailingOnly = TRUE)
  arg <- function(k) { i <- match(k, a); if (is.na(i) || i == length(a)) NULL else a[i + 1L] }
  if ("--verify" %in% a) {
    lp <- strsplit(arg("--verify"), ",", fixed = TRUE)[[1]]
    ex <- arg("--exclude"); ex <- if (is.null(ex)) NULL else strsplit(ex, ",", fixed = TRUE)[[1]]
    bad <- verify_subset_writes(lp, exclude = ex)
    cat("REDO:", paste(bad, collapse = ","), "\n")
    quit(save = "no", status = 0L)
  }
  if ("--check-full" %in% a) {
    ok <- check_full_equivalence(arg("--check-full"))
    quit(save = "no", status = if (isTRUE(ok)) 0L else 1L)
  }
  ms <- arg("--months"); ms <- if (is.null(ms)) NULL else strsplit(ms, ",", fixed = TRUE)[[1]]
  r <- rebuild_factor_subset(months = ms, from = arg("--from"), to = arg("--to"), dry_run = "--dry-run" %in% a,
                             log_path = arg("--log"), write_hash = !("--no-hash" %in% a))
  quit(save = "no", status = if (r$bad > 0L) 1L else 0L)
}
