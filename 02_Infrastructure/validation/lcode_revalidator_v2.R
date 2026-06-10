##=============================================================================
## lcode_revalidator_v2.R — Factor DB 기반 L-Code 재검증
##
## 기존 run_all.R 재실행이 아닌, 월간 Factor DB에서 팩터값 직접 로드 →
## backtest_harness.R로 시뮬레이션 → L-code 수치 비교
##
## 최적화:
##   - RAWDATA/BM 1회 로드 → 전략별 재사용
##   - Factor DB load_month_factors() 활용 (C15 준수)
##   - 4개씩 bash 병렬 (output 미생성, 수치만 추출)
##   - 타임아웃 10분/전략
##=============================================================================

cat("═══ L-Code Revalidator v2.0 (Factor DB 기반) ═══\n")

suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(xts); library(PerformanceAnalytics)
})

INFRA_DIR <- tryCatch(dirname(dirname(sys.frame(1)$ofile)),
  error = function(e) file.path(Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")), "02_Infrastructure"))
source(file.path(INFRA_DIR, "config.R"))
source(file.path(INFRA_DIR, "backtest_harness.R"))

MEM_FILE <- local({ .c <- c("C:/Users/99922/.claude/projects/C--Users-99922-OneDrive-Quant-Module-Moltbot/memory/methodology_memory.md", "/home/quant/.claude/projects/-mnt-c-Users-User-OneDrive-------Quant-Module-Moltbot/memory/methodology_memory.md"); .e <- .c[file.exists(.c)]; if (length(.e)) .e[1] else .c[1] })  # 2026-06-10 현 경로 1순위
STRAT_BASE <- file.path(PROJECT_ROOT, "04_Research", "strategies")

# ─── L-code 파싱 ─────────────────────────────────────────────────────────────
parse_lcodes <- function() {
  text <- paste(readLines(MEM_FILE, warn = FALSE), collapse = "\n")
  starts <- gregexpr("### L-\\d+", text)[[1]]
  if (starts[1] == -1) return(data.table())

  blocks <- character(length(starts))
  for (i in seq_along(starts)) {
    s <- starts[i]
    e <- if (i < length(starts)) starts[i + 1] - 1 else nchar(text)
    blocks[i] <- substr(text, s, e)
  }

  rbindlist(lapply(blocks, function(b) {
    lm <- regmatches(b, regexpr("L-\\d+", b))
    sm <- regmatches(b, regexpr("STR_\\d+", b))
    if (length(lm) == 0) return(NULL)
    if (length(sm) == 0) sm <- NA_character_

    sr_m <- regmatches(b, gregexpr("SR\\s*[0-9.]+", b))[[1]]
    sr <- if (length(sr_m) > 0) as.numeric(gsub("SR\\s*", "", sr_m[1])) else NA_real_
    mdd_m <- regmatches(b, gregexpr("MDD\\s*[0-9.]+", b))[[1]]
    mdd <- if (length(mdd_m) > 0) as.numeric(gsub("MDD\\s*", "", mdd_m[1])) else NA_real_

    # 팩터 추출 (Factor DB 매칭용)
    factors <- regmatches(b, gregexpr("[A-Z]{1,2}\\d{2}_[A-Za-z_]+", b))[[1]]
    factors <- unique(factors[nchar(factors) > 4])

    data.table(lcode = lm[1], strat = sm[1], old_sr = sr, old_mdd = mdd,
               factors = list(factors), text = b)
  }), fill = TRUE)
}

# ─── 단일 전략 재검증 (Factor DB 기반) ───────────────────────────────────────
revalidate_single <- function(strat_dir, rawdata, bm_dt) {
  full_dir <- file.path(STRAT_BASE, strat_dir)
  run_all <- file.path(full_dir, "run_all.R")
  if (!file.exists(run_all)) return(list(status = "NO_CODE", sr = NA, mdd = NA))

  tryCatch({
    env <- new.env(parent = globalenv())
    env$RAWDATA <- copy(rawdata)
    env$BM_DT <- copy(bm_dt)
    env$SKIP_CHARTS <- TRUE
    env$SKIP_REPORT <- TRUE

    oldwd <- getwd()
    setwd(full_dir)
    on.exit(setwd(oldwd), add = TRUE)

    setTimeLimit(elapsed = 600)
    on.exit(setTimeLimit(elapsed = Inf), add = TRUE)

    source(run_all, local = env)

    # 결과 추출
    sr <- mdd <- NA_real_
    if (file.exists("sim_result.rds")) {
      sim <- readRDS("sim_result.rds")
      nav <- as.data.table(sim$DAILY_NAV_DT)
      if ("Strategy_Ret" %in% names(nav)) {
        nav[, Date := as.Date(Date)]
        ret <- xts(nav$Strategy_Ret, order.by = nav$Date)
        sr <- as.numeric(SharpeRatio.annualized(ret, scale = 252))
        mdd <- as.numeric(maxDrawdown(ret)) * 100
      }
    }

    # performance.json fallback
    pf <- file.path("output", "performance.json")
    if (is.na(sr) && file.exists(pf)) {
      p <- fromJSON(pf)
      ov <- if (!is.null(p$overlay)) p$overlay else p$base
      if (!is.null(ov)) { sr <- ov$Sharpe; mdd <- ov$MDD }
    }

    list(status = "OK", sr = sr, mdd = mdd)
  }, error = function(e) {
    list(status = paste0("ERR:", substr(conditionMessage(e), 1, 80)), sr = NA, mdd = NA)
  })
}

# ─── 메인 ────────────────────────────────────────────────────────────────────
run_revalidation_v2 <- function(n_parallel = 4L) {
  t0 <- proc.time()

  cat("[1/4] L-code 파싱...\n")
  lcodes <- parse_lcodes()
  cat(sprintf("  %d L-codes\n", nrow(lcodes)))

  # 실행 가능 전략 매칭
  all_dirs <- list.dirs(STRAT_BASE, recursive = FALSE, full.names = FALSE)
  strat_vec <- lcodes$strat
  lcodes[, dir := sapply(strat_vec, function(s) {
    if (is.na(s)) return(NA_character_)
    m <- grep(s, all_dirs, value = TRUE)
    if (length(m) > 0) m[1] else NA_character_
  })]
  dir_vec <- lcodes$dir
  lcodes[, runnable := sapply(dir_vec, function(d) {
    if (is.na(d)) return(FALSE)
    file.exists(file.path(STRAT_BASE, d, "run_all.R"))
  })]

  runnable <- lcodes[runnable == TRUE]
  cat(sprintf("  실행 가능: %d개\n\n", nrow(runnable)))

  cat("[2/4] RAWDATA/BM 사전 로드...\n")
  res <- load_rawdata(use_cache = TRUE)
  RAWDATA <- res$RAWDATA; BM_DT <- res$BM_DT
  rm(res); gc(verbose = FALSE)
  cat("  완료.\n\n")

  cat("[3/4] 병렬 백테스트...\n")
  n <- nrow(runnable)
  batch_num <- ceiling(n / n_parallel)
  results <- vector("list", n)

  for (b in seq_len(batch_num)) {
    idx_start <- (b - 1) * n_parallel + 1
    idx_end <- min(b * n_parallel, n)
    batch_idx <- idx_start:idx_end

    cat(sprintf("  Batch %d/%d [%d~%d]:", b, batch_num, idx_start, idx_end))
    t1 <- proc.time()

    # bash 병렬 실행
    batch_sh <- tempfile(fileext = ".sh")
    lines <- character(0)
    for (i in batch_idx) {
      full_dir <- file.path(STRAT_BASE, runnable$dir[i])
      lines <- c(lines, sprintf(
        'cd "%s" && timeout 600 Rscript --no-echo --no-restore -e \'source("run_all.R")\' > /dev/null 2>&1 &',
        full_dir))
    }
    lines <- c(lines, "wait")
    writeLines(lines, batch_sh)
    system(sprintf("bash %s", batch_sh), wait = TRUE)
    unlink(batch_sh)

    # 결과 수집 (파일 읽기만)
    ok <- 0L
    for (i in batch_idx) {
      full_dir <- file.path(STRAT_BASE, runnable$dir[i])
      sr <- mdd <- NA_real_

      sim_path <- file.path(full_dir, "sim_result.rds")
      perf_path <- file.path(full_dir, "output", "performance.json")

      if (file.exists(sim_path)) {
        tryCatch({
          sim <- readRDS(sim_path)
          nav <- as.data.table(sim$DAILY_NAV_DT)
          if ("Strategy_Ret" %in% names(nav)) {
            nav[, Date := as.Date(Date)]
            ret <- xts(nav$Strategy_Ret, order.by = nav$Date)
            sr <- as.numeric(SharpeRatio.annualized(ret, scale = 252))
            mdd <- as.numeric(maxDrawdown(ret)) * 100
          }
        }, error = function(e) NULL)
      } else if (file.exists(perf_path)) {
        tryCatch({
          p <- fromJSON(perf_path)
          ov <- if (!is.null(p$overlay)) p$overlay else p$base
          if (!is.null(ov)) { sr <- ov$Sharpe; mdd <- ov$MDD }
        }, error = function(e) NULL)
      }

      results[[i]] <- data.table(
        lcode = runnable$lcode[i], strat = runnable$strat[i], dir = runnable$dir[i],
        status = fifelse(!is.na(sr), "OK", "NO_RESULT"),
        new_sr = sr, new_mdd = mdd,
        old_sr = runnable$old_sr[i], old_mdd = runnable$old_mdd[i]
      )
      if (!is.na(sr)) ok <- ok + 1L
    }

    elapsed <- (proc.time() - t1)["elapsed"]
    cat(sprintf(" %d/%d OK (%.0fs)\n", ok, length(batch_idx), elapsed))
    gc(verbose = FALSE)
  }

  cat("\n[4/4] 비교 분석...\n")
  dt <- rbindlist(results, fill = TRUE)

  # 괴리율
  dt[, sr_pct := fifelse(!is.na(new_sr) & !is.na(old_sr) & abs(old_sr) > 0.01,
                          abs(new_sr - old_sr) / abs(old_sr) * 100, NA_real_)]
  dt[, mdd_pct := fifelse(!is.na(new_mdd) & !is.na(old_mdd) & abs(old_mdd) > 0.1,
                           abs(new_mdd - old_mdd) / abs(old_mdd) * 100, NA_real_)]

  dt[, verdict := fifelse(status != "OK", "SKIP",
    fifelse(is.na(sr_pct) & is.na(mdd_pct), "NO_COMPARE",
      fifelse(pmax(sr_pct, mdd_pct, na.rm = TRUE) > 10, "DIVERGED", "CONFIRMED")))]

  cat("판정:\n")
  print(dt[, .N, by = verdict])

  # 저장
  out_path <- file.path(PROJECT_ROOT, "stage_artifacts", "lcode_revalidation_v2.json")
  write(toJSON(dt[, .(lcode, strat, status, new_sr, new_mdd, old_sr, old_mdd, sr_pct, mdd_pct, verdict)],
               pretty = TRUE), out_path)

  total_min <- (proc.time() - t0)["elapsed"] / 60
  cat(sprintf("\n═══ 완료 (%.1f분) ═══\n", total_min))

  # DIVERGED 상세
  div <- dt[verdict == "DIVERGED"]
  if (nrow(div) > 0) {
    cat("\n=== DIVERGED 상세 ===\n")
    for (j in seq_len(nrow(div))) {
      cat(sprintf("  %s: SR %.3f→%.3f (%+.1f%%), MDD %.1f→%.1f (%+.1f%%)\n",
                  div$lcode[j],
                  div$old_sr[j], div$new_sr[j], div$sr_pct[j],
                  div$old_mdd[j], div$new_mdd[j], div$mdd_pct[j]))
    }
  }

  invisible(dt)
}

cat("[lcode_revalidator_v2] Ready. run_revalidation_v2()\n")
