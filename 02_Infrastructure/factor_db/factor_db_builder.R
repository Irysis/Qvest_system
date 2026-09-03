#==============================================================================
# Factor DB Builder — Central Orchestrator
# Version: 1.0.0
#
# Computes and stores standardized factors for the entire universe.
# Each compute_*.R module returns data.table(Ticker, Factor_Name, Raw_Value)
# for one category. This builder combines them, adds Z_Score/Z_Sector/Rank_Pct,
# and saves to .cache/factor_db/factor_db_YYYYMM.parquet.
#
# Usage:
#   source("02_Infrastructure/config.R")
#   source("02_Infrastructure/factor_db_builder.R")
#   build_factor_db("2026-02-28")                   # one date
#   build_factor_db_monthly("2020-01-01","2026-02-28")  # batch
#   dt <- load_factor_db("2026-02-28")              # load cached
#   ic <- get_factor_ic("V01_BM", 60)               # IC history
#   update_factor_db_daily()                         # cron hook
#
# PIT Rules:
#   - Fundamentals: Factor_Date <= sig_date (most recent per Ticker×Item)
#   - Consensus: Date <= sig_date (most recent per Ticker)
#   - Price/Volume: Date <= sig_date
#   - All z-scores: CROSS-SECTIONAL at sig_date (NOT time-series)
#==============================================================================

# ─── Self-locate & source config ────────────────────────────────────────────
# ★2026-08-09 수리(FQ-163 시범 산출 중 적발). 구 코드는 `tryCatch(dirname(sys.frame(1)$ofile), ...)`
#   하나만 믿었는데, **중첩 source 에서 `sys.frame(1)$ofile` 은 이 파일이 아니라 최상위 스크립트를
#   가리키면서 에러를 던지지 않는다** → error 핸들러(올바른 resolver)가 영영 발화하지 않아
#   fallback 이 dead code 였다. 실측: stage_artifacts/fq163/trial_build_consensus.R 이
#   `source("factor_db/factor_db_builder.R")` 를 호출하자 config 를 `stage_artifacts/config.R` 에서
#   찾다 중단. 같은 계통을 canonical_screen_bt.R(.CANON_DIR)에서 이미 한 번 수리했다(WT-015 R2).
#   ★규약: **존재 검사로 정체 검사를 대체하지 말 것** — 후보 경로가 "있다"가 아니라
#   "이 파일 자신을 담고 있다"를 확인한다(r-portability 금칙 ④ 정합).
.ofile_guess <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NA_character_)
.self_dir <- local({
  .is_self <- function(d) {
    is.character(d) && length(d) == 1L && !is.na(d) && nzchar(d) &&
      file.exists(file.path(d, "factor_db_builder.R")) &&
      file.exists(file.path(dirname(d), "config.R"))     # 정체 확인 (marker 2종)
  }
  cands <- c(
    .ofile_guess,
    if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db") else NA_character_,
    file.path(Sys.getenv("CLAUDE_PROJECT_DIR"), "02_Infrastructure", "factor_db"),
    file.path(Sys.getenv("QM_ROOT"),            "02_Infrastructure", "factor_db"),
    file.path(getwd(), "02_Infrastructure", "factor_db"),
    file.path(getwd(), "factor_db")
  )
  for (d in cands) if (.is_self(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  stop("[factor_db_builder] self_dir 해석 실패 — factor_db_builder.R 과 ../config.R 을 함께 담은 ",
       "디렉토리를 찾지 못했습니다. CLAUDE_PROJECT_DIR 또는 QM_ROOT 를 설정하십시오.")
})

if (!exists("PROJECT_ROOT")) {
  source(file.path(dirname(.self_dir), "config.R"))
}

# ─── Packages ────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(jsonlite)
})

# ─── Constants ───────────────────────────────────────────────────────────────
FACTOR_DB_DIR    <- file.path(CACHE_DIR, "factor_db")
FACTOR_IC_PATH   <- file.path(FACTOR_DB_DIR, "factor_ic_history.parquet")
FACTOR_REG_PATH  <- file.path(FACTOR_DB_DIR, "factor_registry.json")

# ★월 빌드용 RAWDATA 슬라이스 폭 (2026-09-01 수리).
#   구값 1400일 = 실측 **935 거래일**이었는데, M12_LR_Reversal 의 정의가 "60m-13m 누적수익
#   (1260-273 거래일)" 이다 — **창이 팩터 자신의 정의보다 좁아** 443개월 전 구간 0행이었다.
#   생산자는 멀쩡했다: 같은 sig_date 에 창만 1900일(1,274 거래일)로 넓히면 2,124행이 나온다.
#   실패가 아니라 침묵으로 나타나 emission_guard 의 "생산자는 있는데 도달 불가"(FQ-163 계통)에
#   올라 있었다 — 계기는 결측을 봤지만 사유는 창이었다.
#   ★새 팩터의 최장 lookback 이 이 값을 넘으면 여기를 함께 넓혀야 한다. 안 넓히면 조용히 0행이다.
.FDB_SLICE_DAYS <- 1900L
COMPUTE_MOD_DIR  <- file.path(FUNC_PATH, "factor_db")

# ─── IC pair 완결성 판정 (순수 함수, 2026-07-26 R-ICGUARD 분리) ──────────────
# 인라인이던 판정을 별도 파일로 뺐다 — 단독 실행이 가능해야 위반 주입 테스트를
# 걸 수 있고, 검사 없는 가드는 조용히 무력화된다.
# 상설 검사: 08_Tests/factor_db/test_ic_completion_guard.R
# 경로는 "있다"가 아니라 표지 파일 확인으로 고른다(r-portability ③④).
.ic_guard_src <- NULL
for (.c in c(file.path(COMPUTE_MOD_DIR, "ic_pair_completeness.R"),
             file.path(.self_dir, "ic_pair_completeness.R"))) {
  if (file.exists(.c)) { .ic_guard_src <- .c; break }
}
if (is.null(.ic_guard_src)) {
  stop("[factor_db_builder] ic_pair_completeness.R 부재 — IC 완결성 가드 없이 진행 불가")
}
source(.ic_guard_src)
rm(.c, .ic_guard_src)

# ─── 배출 감시 (등재 대비 실산출 대조, 2026-08-08 FQ-163) ────────────────────
# compute_consensus 의 7개 블록이 440개월 전 구간 0행이었는데 아무 경보도 없었다 —
# 빌더가 "등재된 팩터가 실제로 나왔는가" 를 묻는 코드를 갖고 있지 않았기 때문이다.
# ic_pair_completeness 와 같은 이유로 별도 파일: 단독 실행이 가능해야 위반 주입
# 테스트를 걸 수 있다. 상설 검사: 08_Tests/factor_db/test_emission_guard.R
.emit_guard_src <- NULL
for (.c in c(file.path(COMPUTE_MOD_DIR, "emission_guard.R"),
             file.path(.self_dir, "emission_guard.R"))) {
  if (file.exists(.c)) { .emit_guard_src <- .c; break }
}
if (is.null(.emit_guard_src)) {
  stop("[factor_db_builder] emission_guard.R 부재 — 배출 감시 없이 진행 불가")
}
source(.emit_guard_src)
rm(.c, .emit_guard_src)
FACTOR_EMISSION_BASELINE <- file.path(FUNC_PATH, "factor_db", "emission_expected_absent.json")
# 정체 검사 3축(D/T/I)의 선언 래칫 — 시장레벨 상수처럼 **정당한** 무분산 배출을 선언한다.
# (2026-08-09 FQ-210. 존재 축의 emission_expected_absent.json 과 같은 방식·다른 축)
FACTOR_IDENTITY_BASELINE <- file.path(FUNC_PATH, "factor_db", "emission_declared_identity.json")

# Ensure output directory exists
if (!dir.exists(FACTOR_DB_DIR)) {
  dir.create(FACTOR_DB_DIR, recursive = TRUE, showWarnings = FALSE)
}

cat("[factor_db_builder] Loaded. FACTOR_DB_DIR:", FACTOR_DB_DIR, "\n")

#==============================================================================
# v54 Gate 13.1 — build_hash helpers
#   (2026-07-26 P4 수리: '_unknown' 침묵 실패 근절 + 빌드 중 HEAD 이동 오귀속 제거)
#
# 실측 근거 — 2026-07-25 전기간 재빌드 로그(tasks/b6qidm6qn.output):
#   ① 440 write 중 415건이 '_unknown'. 구현이 `system(intern=TRUE)` 를 썼는데
#      명령 실패는 R 이 *warning* 으로만 신호한다 → tryCatch(error=) 는 잡지
#      못하고 character(0) 이 그대로 "unknown" 으로 치환됐다. 게다가
#      ignore.stderr=TRUE 가 원인 문자열을 버려 사후 진단이 불가능했고,
#      경고는 "There were 50 or more warnings" 로 집계돼 사실상 보이지 않았다.
#   ② 앞 25건 rev=1c70d27c, 이어진 4건 rev=4fbc3733 — 같은 프로세스가 13:49:56
#      에 읽은 *같은 코드* 로 빌드하는 동안 auto-commit 이 HEAD 를 움직여 rev 가
#      바뀌었다. rev 는 '쓰는 시점' 이 아니라 '코드를 읽은 시점' 에 한 번만
#      확정해야 한다(부작용으로 git 호출이 440회 → 1회).
#
# 계약: build_hash.txt 1행 = "<YYYYMMDDHHMMSS>_<rev>" (소비자는 전부 n=1 읽기).
#       rev 가 git 이 아닐 때만 2행에 진단이 붙는다(1행 계약 불변).
#       rev 후보: <gitshort> | <gitshort>-dirty | nogit<8hex 코드 다이제스트>
#                 | hashfail(둘 다 실패 — 반드시 경고 동반)
#==============================================================================

.fdb_hash_env <- new.env(parent = emptyenv())

#' git 호출 1회 — 종료코드/stderr 를 버리지 않고 함께 돌려준다.
#' (r-portability: system2(env=) 미사용, Sys.which 로 실행파일 확인)
.fdb_run_git <- function(args, repo = NULL) {
  git <- Sys.which("git")
  if (!nzchar(git)) {
    return(list(ok = FALSE, out = character(0), status = -1L,
                err = "git executable not found (Sys.which('git') empty)"))
  }
  a <- if (is.null(repo)) args else c("-C", repo, args)
  errf <- tempfile("fdb_git_err_")
  on.exit(unlink(errf), add = TRUE)   # 함수 내부 on.exit — 정상 발화
  out <- tryCatch(
    suppressWarnings(system2(git, a, stdout = TRUE, stderr = errf)),
    error = function(e) structure(character(0), status = -2L)
  )
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  err <- tryCatch(paste(readLines(errf, warn = FALSE), collapse = " | "),
                  error = function(e) "")
  out <- as.character(out)
  list(ok = identical(as.integer(st), 0L) && length(out) > 0L && nzchar(out[1]),
       out = out, status = as.integer(st), err = err)
}

#' 저장소 루트 해석 — 존재검사(dir.exists)가 아니라 git 정체성 질의로 판정.
#' (worktree 는 .git 이 파일이므로 dir.exists 판정이 오답 — r-portability 금칙 ③)
.fdb_resolve_repo <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""),      # 우선순위 ④: CPD 먼저
             Sys.getenv("QM_ROOT", ""),
             if (exists("PROJECT_ROOT")) PROJECT_ROOT else "",
             tryCatch(dirname(dirname(.self_dir)), error = function(e) ""),
             getwd())
  cands <- unique(cands[nzchar(cands) & !is.na(cands)])
  for (p in cands) {
    if (!dir.exists(p)) next
    r <- .fdb_run_git(c("rev-parse", "--show-toplevel"), repo = p)
    if (r$ok) return(trimws(r$out[1]))
  }
  NULL
}

#' git 부재 시의 대체 코드-버전 식별자 (팩터 계산 코드 + registry 의 md5 요약).
#' 'unknown' 처럼 정보가 0 인 토큰 대신 최소한 코드 버전은 구분되게 한다.
.fdb_code_digest <- function() {
  tryCatch({
    files <- c(list.files(COMPUTE_MOD_DIR, pattern = "\\.R$", full.names = TRUE),
               FACTOR_REG_PATH)
    files <- sort(files[file.exists(files)])
    if (!length(files)) return(NA_character_)
    ms <- tools::md5sum(files)
    tf <- tempfile("fdb_codedig_"); on.exit(unlink(tf), add = TRUE)
    writeLines(paste(basename(files), as.character(ms), sep = ":"), tf)
    substr(unname(tools::md5sum(tf)), 1, 8)
  }, error = function(e) NA_character_)
}

#' 코드 버전 rev 확정 — 프로세스당 1회 (source 시점 = 코드를 읽은 시점).
.fdb_init_code_rev <- function(force = FALSE, quiet = FALSE) {
  if (!force && !is.null(.fdb_hash_env$code_rev)) return(invisible(.fdb_hash_env$code_rev))
  reason <- ""
  repo <- .fdb_resolve_repo()
  res <- NULL
  if (!is.null(repo)) {
    r <- .fdb_run_git(c("rev-parse", "--short", "HEAD"), repo = repo)
    if (r$ok) {
      rev <- trimws(r$out[1])
      d <- .fdb_run_git(c("status", "--porcelain", "--",
                          "02_Infrastructure/factor_db"), repo = repo)
      if (identical(d$status, 0L) && length(d$out) > 0L && any(nzchar(d$out)))
        rev <- paste0(rev, "-dirty")
      res <- list(rev = rev, source = "git", reason = "", repo = repo)
    } else {
      reason <- sprintf("git rev-parse failed (status=%s) %s", r$status, r$err)
    }
  } else {
    reason <- "repo root unresolvable (git identity query failed for all candidates)"
  }
  if (is.null(res)) {
    cd <- .fdb_code_digest()
    res <- if (!is.na(cd))
      list(rev = paste0("nogit", cd), source = "code_digest", reason = reason, repo = repo)
    else
      list(rev = "hashfail", source = "none",
           reason = paste(reason, "| code digest also failed"), repo = repo)
  }
  .fdb_hash_env$code_rev <- res
  if (!identical(res$source, "git") && !quiet) {
    cat(sprintf(paste0(
      "[factor_db_builder] !!! WARN: build_hash 의 git rev 산출 실패 — ",
      "대체 식별자 '%s' 사용 (source=%s)\n",
      "[factor_db_builder] !!!   사유: %s\n",
      "[factor_db_builder] !!!   결과: 이 빌드의 코드 버전 추적이 약화됩니다. ",
      "git 가용성/저장소 경로를 확인하세요.\n"), res$rev, res$source, res$reason))
    warning(sprintf("factor_db build_hash: git rev 산출 실패 — %s (rev='%s')",
                    res$reason, res$rev), call. = FALSE, immediate. = TRUE)
  }
  invisible(res)
}

#' Write build_hash.txt to FACTOR_DB_DIR (timestamp + code rev).
#' Called at end of build_factor_db() and build_factor_db_monthly().
.write_build_hash <- function() {
  cr <- .fdb_init_code_rev(quiet = TRUE)
  hash_str <- paste(format(Sys.time(), "%Y%m%d%H%M%S"), cr$rev, sep = "_")
  hash_path <- file.path(FACTOR_DB_DIR, "build_hash.txt")
  lines <- hash_str
  if (!identical(cr$source, "git")) {
    lines <- c(hash_str,
               sprintf("# rev_source=%s reason=%s", cr$source, cr$reason))
    cat(sprintf(paste0("[factor_db_builder] !!! WARN: build_hash rev 가 git 이 아님 ",
                       "(source=%s) — 사유: %s\n"), cr$source, cr$reason))
    warning(sprintf("factor_db build_hash written with non-git rev '%s' (%s)",
                    cr$rev, cr$reason), call. = FALSE, immediate. = TRUE)
  }
  ok <- tryCatch({ writeLines(lines, hash_path); TRUE },
                 error = function(e) {
                   cat(sprintf("[factor_db_builder] !!! WARN: build_hash 쓰기 실패: %s\n",
                               conditionMessage(e)))
                   warning(sprintf("factor_db build_hash write failed: %s",
                                   conditionMessage(e)), call. = FALSE, immediate. = TRUE)
                   FALSE
                 })
  if (ok)
    cat(sprintf("[factor_db_builder] build_hash written: %s -> %s\n", hash_str, hash_path))
  invisible(ok)
}

# 코드 버전은 source 시점에 1회 확정 (빌드 도중 auto-commit 이 HEAD 를 움직여도 불변)
.fdb_init_code_rev()

#==============================================================================
# Internal: Load base data (cached within session)
#==============================================================================

.fdb_env <- new.env(parent = emptyenv())

.load_base_data <- function(force = FALSE) {
  if (!force && exists("RAWDATA", envir = .fdb_env)) return(invisible(NULL))

  cat("[factor_db_builder] Loading base data...\n")

  # RAWDATA
  .fdb_env$RAWDATA <- as.data.table(read_parquet(RAWDATA_CACHE))
  cat(sprintf("  RAWDATA: %s rows | %s ~ %s\n",
              format(nrow(.fdb_env$RAWDATA), big.mark = ","),
              min(.fdb_env$RAWDATA$Date), max(.fdb_env$RAWDATA$Date)))

  # VIX column from macro_fred (for D32_Beta_VIX in compute_defense.R)
  macro_path <- file.path(CACHE_DIR, "macro_fred.parquet")
  if (!("VIX" %in% names(.fdb_env$RAWDATA)) && file.exists(macro_path)) {
    tryCatch({
      macro <- as.data.table(read_parquet(macro_path))
      macro[, Date := as.Date(Date)]
      vix_col <- if ("Series_ID" %in% names(macro) &&
                      "VIXCLS" %in% macro[["Series_ID"]]) {
        macro[Series_ID == "VIXCLS" & !is.na(Value),
              .(Date, VIX = Value)][, .(VIX = last(VIX)), by = Date]
      } else if ("VIX" %in% macro[["Series"]]) {
        macro[Series == "VIX" & !is.na(Value),
              .(Date, VIX = Value)][, .(VIX = last(VIX)), by = Date]
      } else NULL
      if (!is.null(vix_col) && nrow(vix_col) > 0L) {
        setkey(vix_col, Date)
        # ffill VIX over all RAWDATA dates
        all_dates <- data.table(Date = sort(unique(.fdb_env$RAWDATA$Date)))
        vix_filled <- vix_col[all_dates, on = "Date", roll = TRUE]
        .fdb_env$RAWDATA <- merge(.fdb_env$RAWDATA, vix_filled, by = "Date", all.x = TRUE)
        cat(sprintf("  RAWDATA: VIX column added (%d carry-forwarded values)\n",
                    sum(!is.na(vix_filled$VIX))))
      }
    }, error = function(e) {
      cat(sprintf("  RAWDATA: VIX merge failed (%s)\n", conditionMessage(e)))
    })
  }

  # Fundamentals
  fund_path <- file.path(CACHE_DIR, "fundamental_merged.parquet")
  if (file.exists(fund_path)) {
    .fdb_env$FUND <- as.data.table(read_parquet(fund_path))
    cat(sprintf("  Fundamentals: %s rows\n",
                format(nrow(.fdb_env$FUND), big.mark = ",") ))

    # ── Item alias mapping (compute_*.R name compatibility) ──────────────
    # Append rows with canonical names expected by compute modules whose
    # source names differ from fundamental_merged.parquet schema.
    # Audit (2026-05-23):
    #   compute_accrual.R expects CurrentLiabilities/TotalLiabilities
    #   compute_growth.R  expects RnDExpense (PPE/Inventories/SharesOutstanding
    #                              are derived below)
    # Other names (CashAndEquiv, DepAmort, SGAExpense, FinanceCF, AccountsRecv,
    # AccountsPay) match exactly — no alias needed.
    .item_aliases <- list(
      CurrentLiabilities = "CurrentLiab",
      TotalLiabilities   = "TotalLiab",
      RnDExpense         = "RandD",
      AccountsReceivable = "AccountsRecv",
      AccountsPayable    = "AccountsPay"
    )
    .alias_rows <- list()
    for (canonical in names(.item_aliases)) {
      orig <- .item_aliases[[canonical]]
      if (orig %in% .fdb_env$FUND$Item && !(canonical %in% .fdb_env$FUND$Item)) {
        sub <- .fdb_env$FUND[Item == orig]
        if (nrow(sub) > 0L) {
          sub <- copy(sub)[, Item := canonical]
          .alias_rows[[canonical]] <- sub
        }
      }
    }
    if (length(.alias_rows) > 0L) {
      .fdb_env$FUND <- rbindlist(c(list(.fdb_env$FUND), .alias_rows),
                                  use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals alias: +%d Items (%s)\n",
                  length(.alias_rows),
                  paste(names(.alias_rows), collapse = ", ")))
    }

    # Inventories: derive from working capital approximation
    # (CurrentAssets - CashAndEquiv - AccountsRecv) ≈ Inventories + other current assets
    # Best-effort; may be wide. compute_*.R handles NA gracefully.
    if (!("Inventories" %in% .fdb_env$FUND$Item) &&
        all(c("CurrentAssets","CashAndEquiv","AccountsRecv") %in% .fdb_env$FUND$Item)) {
      ca <- .fdb_env$FUND[Item == "CurrentAssets",
                          .(Ticker, Factor_Date, Period, ca = Value)]
      ch <- .fdb_env$FUND[Item == "CashAndEquiv",
                          .(Ticker, Factor_Date, Period, cash = Value)]
      rv <- .fdb_env$FUND[Item == "AccountsRecv",
                          .(Ticker, Factor_Date, Period, recv = Value)]
      inv_est <- merge(merge(ca, ch, by = c("Ticker","Factor_Date","Period"), all = FALSE),
                       rv, by = c("Ticker","Factor_Date","Period"), all = FALSE)
      inv_est[, Inv_proxy := ca - cash - recv]
      inv_est <- inv_est[!is.na(Inv_proxy) & Inv_proxy >= 0]
      if (nrow(inv_est) > 0L) {
        src <- .fdb_env$FUND[Item == "CurrentAssets",
                              .SD[1L], by = .(Ticker, Factor_Date, Period)]
        inv_rows <- merge(inv_est[, .(Ticker, Factor_Date, Period, Value = Inv_proxy)],
                          src[, .(Ticker, Factor_Date, Period, Period_Date, Source)],
                          by = c("Ticker","Factor_Date","Period"), all.x = TRUE)
        inv_rows[, Item := "Inventories"][, Source := paste0(Source %||% "derived", "_proxy")]
        .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND,
                                          inv_rows[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source)]),
                                    use.names = TRUE, fill = TRUE)
        cat(sprintf("  Fundamentals derived: Inventories proxy (+%d rows)\n", nrow(inv_rows)))
      }
    }

    # SharesOutstanding: derive from RAWDATA Size / Close (market cap / price)
    if (!("SharesOutstanding" %in% .fdb_env$FUND$Item) &&
        all(c("Date","Close","Size") %in% names(.fdb_env$RAWDATA))) {
      sh <- .fdb_env$RAWDATA[!is.na(Close) & Close > 1e-6 & !is.na(Size) & Size > 0,
                              .(Ticker, Date, est_shares = Size / Close)]
      # Quarterly snapshot — end of quarter
      sh[, qtr := paste0(year(Date), "Q", quarter(Date))]
      sh_q <- sh[, .SD[.N], by = .(Ticker, qtr)]
      sh_q[, `:=`(Factor_Date = Date,
                  Period_Date = Date,
                  Period = qtr,
                  Item = "SharesOutstanding",
                  Value = est_shares,
                  Source = "derived_from_size")]
      .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND,
                                        sh_q[, .(Ticker, Period, Period_Date, Factor_Date, Item, Value, Source)]),
                                  use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals derived: SharesOutstanding (+%d rows)\n", nrow(sh_q)))
    }

    # PPE: alias from TangibleAssets if available
    if (!("PPE" %in% .fdb_env$FUND$Item) && "TangibleAssets" %in% .fdb_env$FUND$Item) {
      sub <- copy(.fdb_env$FUND[Item == "TangibleAssets"])[, Item := "PPE"]
      .fdb_env$FUND <- rbindlist(list(.fdb_env$FUND, sub), use.names = TRUE, fill = TRUE)
      cat(sprintf("  Fundamentals alias: PPE <- TangibleAssets (+%d rows)\n", nrow(sub)))
    }
  } else {
    .fdb_env$FUND <- NULL
    cat("  Fundamentals: NOT FOUND\n")
  }
  if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

  # Valuation (pre-computed fPER/fPBR/fDY/EV_EBITDA/PSR)
  val_path <- file.path(CACHE_DIR, "valuation.parquet")
  if (file.exists(val_path)) {
    .fdb_env$VALUATION <- as.data.table(read_parquet(val_path))
    cat(sprintf("  Valuation: %s rows\n",
                format(nrow(.fdb_env$VALUATION), big.mark = ",")))
  } else {
    .fdb_env$VALUATION <- NULL
    cat("  Valuation: NOT FOUND\n")
  }

  # Consensus — load all available parquets
  cons_dir <- file.path(CACHE_DIR, "consensus")
  .fdb_env$CONSENSUS <- list()
  if (dir.exists(cons_dir)) {
    cons_files <- list.files(cons_dir, pattern = "\\.parquet$", full.names = TRUE)
    for (cf in cons_files) {
      nm <- gsub("\\.parquet$", "", basename(cf))
      .fdb_env$CONSENSUS[[nm]] <- as.data.table(read_parquet(cf))
    }
    cat(sprintf("  Consensus: %d tables (%s)\n",
                length(.fdb_env$CONSENSUS),
                paste(names(.fdb_env$CONSENSUS), collapse = ", ")))
  } else {
    cat("  Consensus: NOT FOUND\n")
  }

  # Investor (거래주체) — wide format parquet
  if (exists("INVESTOR_CACHE")) {
    inv_wide_path <- file.path(INVESTOR_CACHE, "investor_wide.parquet")
  } else {
    inv_wide_path <- file.path(CACHE_DIR, "investor_stock", "investor_wide.parquet")
  }
  if (file.exists(inv_wide_path)) {
    .fdb_env$INVESTOR <- as.data.table(read_parquet(inv_wide_path))
    .fdb_env$INVESTOR[, Date := as.Date(Date)]
    cat(sprintf("  Investor: %s rows | %d tickers\n",
                format(nrow(.fdb_env$INVESTOR), big.mark = ","),
                uniqueN(.fdb_env$INVESTOR$Ticker)))
  } else {
    .fdb_env$INVESTOR <- NULL
    cat("  Investor: NOT FOUND\n")
  }

  # ─── Ensure Date columns are proper Date class (arrow may return IDate) ──────
  # This guarantees compute modules do NOT need copy(RAWDATA)[, Date := as.Date(Date)]
  # to do a conversion — they will still call it but it becomes a near-no-op.
  if (!inherits(.fdb_env$RAWDATA$Date, "Date")) {
    .fdb_env$RAWDATA[, Date := as.Date(Date)]
  }
  if (!is.null(.fdb_env$FUND) && "Factor_Date" %in% names(.fdb_env$FUND)) {
    if (!inherits(.fdb_env$FUND$Factor_Date, "Date")) {
      .fdb_env$FUND[, Factor_Date := as.Date(Factor_Date)]
    }
  }

  # ─── Performance indexes (built once, reused every month) ──────────────────
  setkey(.fdb_env$RAWDATA, Date, Ticker)
  if (!is.null(.fdb_env$FUND) && nrow(.fdb_env$FUND) > 0) {
    setkey(.fdb_env$FUND, Factor_Date, Ticker, Item)
  }
  if (!is.null(.fdb_env$VALUATION) && nrow(.fdb_env$VALUATION) > 0) {
    setkey(.fdb_env$VALUATION, Date, Ticker)
  }
  # Pre-compute sorted unique dates — avoids sort(unique(...)) in every PIT call
  .fdb_env$trading_dates     <- sort(unique(.fdb_env$RAWDATA$Date))
  if (!is.null(.fdb_env$VALUATION)) {
    .fdb_env$valuation_dates <- sort(unique(.fdb_env$VALUATION$Date))
  }

  invisible(NULL)
}


#==============================================================================
# Internal: Module preloader — source each compute_*.R ONCE per session
#==============================================================================

.preload_modules <- function() {
  if (isTRUE(.fdb_env$.modules_loaded)) return(invisible(NULL))

  module_map <- list(
    value            = "compute_value.R",
    momentum         = "compute_momentum.R",
    quality          = "compute_quality.R",
    quality_xf_native = "compute_quality_xf_native.R",
    defense          = "compute_defense.R",
    size             = "compute_size.R",
    consensus        = "compute_consensus.R",
    liquidity        = "compute_liquidity.R",
    accrual          = "compute_accrual.R",
    risk             = "compute_risk.R",
    regime           = "compute_regime.R",
    crowding         = "compute_crowding.R",
    growth           = "compute_growth.R",
    investor         = "compute_investor.R",
    technical        = "compute_technical.R",
    xlsx_fund        = "xlsx_factor_calculator.R",
    custom           = "compute_custom_factors.R"
  )
  func_name_map <- list(
    value            = "compute_value",
    momentum         = "compute_momentum",
    quality          = "compute_quality",
    quality_xf_native = "compute_quality_xf_native",
    defense          = "compute_defense",
    size             = "compute_size",
    consensus        = "compute_consensus",
    liquidity        = "compute_liquidity",
    accrual          = "compute_accrual",
    risk             = "compute_risk",
    regime           = "compute_regime",
    crowding         = "compute_crowding",
    growth           = "compute_growth",
    investor         = "compute_investor",
    technical        = "compute_technical",
    xlsx_fund        = "compute_xlsx_fundamentals",
    custom           = "compute_custom_factors"
  )

  .fdb_env$module_funcs <- list()
  n_loaded <- 0L

  for (nm in names(module_map)) {
    fpath <- file.path(COMPUTE_MOD_DIR, module_map[[nm]])
    if (!file.exists(fpath)) {
      cat(sprintf("  [PRELOAD SKIP] %s not found\n", module_map[[nm]]))
      next
    }
    tryCatch({
      env <- new.env(parent = globalenv())
      source(fpath, local = env)
      fn_name <- func_name_map[[nm]]
      if (exists(fn_name, envir = env, inherits = FALSE)) {
        .fdb_env$module_funcs[[nm]] <- get(fn_name, envir = env)
        n_loaded <- n_loaded + 1L
      } else {
        cat(sprintf("  [PRELOAD WARN] %s: function '%s' not found\n",
                    module_map[[nm]], fn_name))
      }
    }, error = function(e) {
      cat(sprintf("  [PRELOAD ERROR] %s: %s\n", module_map[[nm]], conditionMessage(e)))
    })
  }

  .fdb_env$.modules_loaded <- TRUE
  cat(sprintf("[factor_db_builder] Preloaded %d/%d compute modules\n",
              n_loaded, length(module_map)))
  invisible(NULL)
}


#==============================================================================
# Internal: PIT-safe data extraction helpers
#==============================================================================

#' Get latest fundamental value per Ticker×Item as of sig_date
#' PIT: Factor_Date <= sig_date, then most recent per Ticker×Item
.pit_fund <- function(sig_date, items = NULL) {
  fund <- .fdb_env$FUND
  if (is.null(fund) || nrow(fund) == 0) return(NULL)

  sig_d <- as.Date(sig_date)
  # Binary-search cutoff via setkey(Factor_Date) index
  dt <- fund[Factor_Date <= sig_d]
  if (!is.null(items)) dt <- dt[Item %in% items]
  if (nrow(dt) == 0) return(NULL)

  # Most recent per Ticker × Item — last row after key-sorted order
  dt[, .SD[.N], by = .(Ticker, Item)]
}

#' Get RAWDATA snapshot on sig_date (or most recent trading day <= sig_date)
.pit_rawdata <- function(sig_date) {
  sig_d <- as.Date(sig_date)

  # findInterval: O(log N) lookup into pre-sorted trading_dates vector
  dates <- .fdb_env$trading_dates
  idx   <- findInterval(sig_d, dates)
  if (idx == 0L) return(NULL)
  actual_date <- dates[idx]

  .fdb_env$RAWDATA[.(actual_date), nomatch = 0L]  # keyed join on Date
}

#' Get price history up to sig_date (for momentum/vol calculations)
.pit_price_history <- function(sig_date, lookback_days = 260L) {
  sig_d   <- as.Date(sig_date)
  start_d <- sig_d - lookback_days

  # setkey(Date, Ticker) → range scan is fast
  .fdb_env$RAWDATA[Date >= start_d & Date <= sig_d]
}

#' Get latest consensus value per Ticker as of sig_date
.pit_consensus <- function(sig_date, table_name) {
  cons <- .fdb_env$CONSENSUS[[table_name]]
  if (is.null(cons) || nrow(cons) == 0) return(NULL)

  sig_d <- as.Date(sig_date)

  # Ensure keyed by Date for fast range scan; key once per table if needed
  if (!isTRUE(.fdb_env$.cons_keyed[[table_name]])) {
    if (is.null(.fdb_env$.cons_keyed)) .fdb_env$.cons_keyed <- list()
    if ("Date" %in% names(cons)) {
      setkeyv(cons, "Date")
      .fdb_env$.cons_keyed[[table_name]] <- TRUE
    }
  }

  dt <- cons[Date <= sig_d]
  if (nrow(dt) == 0) return(NULL)

  # Most recent per Ticker — setorder + .SD[.N] is faster than which.max()
  setorder(dt, Ticker, Date)
  dt[, .SD[.N], by = Ticker]
}

#' Get valuation snapshot on sig_date
.pit_valuation <- function(sig_date) {
  val <- .fdb_env$VALUATION
  if (is.null(val) || nrow(val) == 0) return(NULL)

  sig_d <- as.Date(sig_date)
  # Use pre-computed valuation_dates if available, otherwise fall back
  vdates <- if (!is.null(.fdb_env$valuation_dates)) .fdb_env$valuation_dates
            else sort(unique(val$Date))
  idx <- findInterval(sig_d, vdates)
  if (idx == 0L) return(NULL)
  actual_date <- vdates[idx]

  val[.(actual_date), nomatch = 0L]  # keyed join on Date
}


#==============================================================================
# Internal: Standardization (cross-sectional z-score, sector-neutral, rank)
#==============================================================================

#' Standardize raw factor values cross-sectionally
#' @param dt data.table with Ticker, Factor_Name, Raw_Value
#' @param sector_map data.table with Ticker, Sector (from RAWDATA snapshot)
#' @return dt with Z_Score, Z_Sector, Rank_Pct, Coverage columns added
.standardize_factors <- function(dt, sector_map) {
  if (nrow(dt) == 0) return(dt[, .(Ticker, Factor_Name, Raw_Value,
                                    Z_Score = numeric(0),
                                    Z_Sector = numeric(0),
                                    Rank_Pct = numeric(0),
                                    Coverage = logical(0))])

  # Merge sector info
  dt <- merge(dt, sector_map[, .(Ticker, Sector)], by = "Ticker", all.x = TRUE)

  # ── Raw-value winsorize (P1 2026-06-10): cross-sectional 1/99 clip ────────
  # Ratio factors with near-zero denominators let a single ticker dominate
  # mean/sd (e.g., A015390 |Z|≈50 → Q11_Net_Margin 79.6% identical-Z collapse
  # via the ±3 clip + re-standardize below: post-clip sd≈0 re-inflates Z).
  # Clip Raw_Value per factor BEFORE z-scoring. Output Raw_Value and Rank_Pct
  # stay computed from the ORIGINAL Raw_Value (reversibility guaranteed).
  .winsorize_raw <- function(x) {
    if (sum(!is.na(x)) < 20L) return(x)
    q <- quantile(x, c(0.01, 0.99), na.rm = TRUE, names = FALSE)
    if (!all(is.finite(q))) return(x)
    pmin(pmax(x, q[1]), q[2])
  }
  dt[, Raw_W := .winsorize_raw(Raw_Value), by = Factor_Name]

  # Universe z-score (cross-sectional, winsorized raw)
  dt[, Z_Score := {
    vals <- Raw_W
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else (vals - mu) / s
  }, by = Factor_Name]

  # Sector-neutral z-score (winsorized raw; clip bounds are universe-level 1/99)
  dt[, Z_Sector := {
    vals <- Raw_W
    mu <- mean(vals, na.rm = TRUE)
    s  <- sd(vals, na.rm = TRUE)
    if (is.na(s) || s < 1e-12) rep(NA_real_, .N)
    else (vals - mu) / s
  }, by = .(Factor_Name, Sector)]

  # Rank percentile (0~1, higher = higher raw value)
  dt[, Rank_Pct := {
    vals <- Raw_Value
    r <- frank(vals, ties.method = "average", na.last = "keep")
    n_valid <- sum(!is.na(vals))
    if (n_valid > 1) (r - 1) / (n_valid - 1) else rep(NA_real_, .N)
  }, by = Factor_Name]

  # Winsorize z-scores at +/- 3
  dt[!is.na(Z_Score), Z_Score := pmin(pmax(Z_Score, -3), 3)]
  dt[!is.na(Z_Sector), Z_Sector := pmin(pmax(Z_Sector, -3), 3)]

  # Option A fix: re-standardize after winsorize to guarantee sd=1
  # Winsorize clips tails → sd < 1 for heavy-tailed factors (M08 +1761%, R16 +529%)
  dt[!is.na(Z_Score), Z_Score := {
    s <- sd(Z_Score, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score / s else Z_Score
  }, by = Factor_Name]
  dt[!is.na(Z_Sector), Z_Sector := {
    s <- sd(Z_Sector, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Sector / s else Z_Sector
  }, by = .(Factor_Name, Sector)]

  # Coverage (P1 2026-06-10 redefinition): raw present AND usable Z exists.
  # Market-level factors (cross-sectional sd=0 → Z all NA, e.g. RE*/MA05~07/
  # M31_Breadth_Mom/CR03) become FALSE so connector coverage_min filtering
  # actually bites. Previously: Coverage = !is.na(Raw_Value) only.
  dt[, Coverage := !is.na(Raw_Value) & !is.na(Z_Score)]

  # Drop working columns (not in output schema)
  dt[, c("Sector", "Raw_W") := NULL]

  dt
}


#==============================================================================
# 1. build_factor_db(sig_date) — Compute all factors for one signal date
#==============================================================================

#' Build factor DB for a single signal date.
#'
#' Sources each compute_*.R module, combines results, standardizes,
#' and saves to .cache/factor_db/factor_db_YYYYMM.parquet.
#'
#' @param sig_date Character or Date. Signal date (e.g., "2026-02-28")
#' @param save Logical. Save to parquet? (default: TRUE)
#' @param force Logical. Overwrite existing cache? (default: FALSE)
#' @return data.table in long format: Date, Ticker, Factor_Name, Raw_Value,
#'         Z_Score, Z_Sector, Rank_Pct, Coverage
#' @export
build_factor_db <- function(sig_date, save = TRUE, force = FALSE) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  out_path <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  # Check cache

if (!force && file.exists(out_path)) {
    cat(sprintf("[build_factor_db] Cache exists: %s (use force=TRUE to rebuild)\n", out_path))
    return(as.data.table(read_parquet(out_path)))
  }

  cat(sprintf("\n[build_factor_db] === Building factor DB for %s ===\n", sig_d))
  t0 <- Sys.time()

  # Load base data (no-op if already loaded this session)
  .load_base_data()
  # Preload compute modules once per session
  .preload_modules()

  # Get RAWDATA snapshot for sector mapping
  snap <- .pit_rawdata(sig_d)
  if (is.null(snap) || nrow(snap) == 0) {
    warning("[build_factor_db] No RAWDATA on or before ", sig_d)
    return(NULL)
  }
  sector_map <- snap[, .(Ticker, Sector)]
  cat(sprintf("  Universe: %d tickers on %s\n", nrow(sector_map), snap$Date[1]))

  # ─── Pre-slice data once — avoids 14× redundant full-scan inside modules ──
  # M12 Long-Run Reversal needs ~1260 trading days (~1400 calendar days).
  # All other modules need ≤365 calendar days. Use 1400d as conservative bound.
  RAWDATA_sliced <- .fdb_env$RAWDATA[Date <= sig_d & Date >= (sig_d - .FDB_SLICE_DAYS)]
  setkey(RAWDATA_sliced, Date, Ticker)

  # Pre-filter fundamentals: modules do copy(FUND)[Factor_Date <= sig_d] N times.
  # Passing the already-filtered subset avoids repeated full-FUND scans.
  FUND_pit <- if (!is.null(.fdb_env$FUND) && nrow(.fdb_env$FUND) > 0L)
                .fdb_env$FUND[Factor_Date <= sig_d]
              else
                NULL

  cat(sprintf("  Pre-sliced RAWDATA: %s rows (full: %s) | FUND_pit: %s rows\n",
              format(nrow(RAWDATA_sliced), big.mark = ","),
              format(nrow(.fdb_env$RAWDATA),  big.mark = ","),
              format(if (!is.null(FUND_pit)) nrow(FUND_pit) else 0L, big.mark = ",")))

  # ─── Execute preloaded compute modules ───────────────────────────────────
  all_factors <- list()

  # Module display names (for logging)
  module_display <- list(
    value = "compute_value.R", momentum = "compute_momentum.R",
    quality = "compute_quality.R",
    quality_xf_native = "compute_quality_xf_native.R",
    defense = "compute_defense.R",
    size = "compute_size.R", consensus = "compute_consensus.R",
    liquidity = "compute_liquidity.R", accrual = "compute_accrual.R",
    risk = "compute_risk.R", regime = "compute_regime.R",
    crowding = "compute_crowding.R", growth = "compute_growth.R",
    investor = "compute_investor.R", technical = "compute_technical.R",
    xlsx_fund = "xlsx_factor_calculator.R",
    custom = "custom_factors"
  )

  for (nm in names(.fdb_env$module_funcs)) {
    fn <- .fdb_env$module_funcs[[nm]]
    display <- module_display[[nm]]
    tryCatch({
      result <- fn(RAWDATA = RAWDATA_sliced, sig_date = sig_d,
                   FUND = FUND_pit, CONSENSUS = .fdb_env$CONSENSUS)
      if (!is.null(result) && nrow(result) > 0) {
        cat(sprintf("  [OK] %s: %d factor×ticker rows (%d factors)\n",
                    display, nrow(result), uniqueN(result$Factor_Name)))
        all_factors[[nm]] <- result
      } else {
        cat(sprintf("  [EMPTY] %s returned 0 rows\n", display))
      }
    }, error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", display, conditionMessage(e)))
    })
  }

  # Combine all non-NULL results
  all_factors <- all_factors[!sapply(all_factors, is.null)]
  if (length(all_factors) == 0) {
    warning("[build_factor_db] No factors computed for ", sig_d)
    return(NULL)
  }

  combined <- rbindlist(all_factors, use.names = TRUE, fill = TRUE)

  # Remove XF_ factors (xlsx originals already merged into DART names)
  # Inline xlsx-into-dart merge (per Quality factor merge principle):
  #   - 19 mapped pairs (DART <- XF): DART preferred (higher quality),
  #     XF fills gap only when DART has 0 rows for this sig_date
  #   - Unmapped XF_* (DU/EF/GD/LL/PR/RI) preserved as standalone
  # See merge_xlsx_into_dart.R for batch post-process (legacy compatibility)
  .XF_TO_DART <- c(
    XF_Q01_GPA               = "Q01_GPA",
    XF_Q02_ROE               = "Q02_ROE",
    XF_Q03_ROA               = "Q03_ROA",
    XF_A01_Accrual           = "Q05_Accrual",
    XF_Q05_Gross_Margin      = "Q10_Gross_Margin",
    XF_Q07_Net_Margin        = "Q11_Net_Margin",
    XF_Q04_Asset_Turnover    = "Q12_Asset_Turnover",
    XF_Q08_Interest_Coverage = "Q32_Interest_Coverage",
    XF_L01_Debt_to_Equity    = "Q15_Debt_to_Equity",
    XF_L02_Current_Ratio     = "Q14_Current_Ratio",
    XF_P01_Piotroski_F       = "Q04_Piotroski_F",
    XF_V01_BM                = "V01_BM",
    XF_V02_EP                = "V02_EP",
    XF_V03_CFP               = "V03_CFP",
    XF_V04_SP                = "V08_PSR",
    XF_G01_Asset_Growth      = "GR03_Asset_Growth",
    XF_G02_Revenue_Growth    = "GR01_Revenue_Growth",
    XF_G03_Earnings_Growth   = "GR02_Earnings_Growth",
    XF_A02_NOA               = "AC05_NOA"
  )
  # Per-ticker merge: for each (ticker, sig_date) pair, DART value preferred;
  # XF (QuantiWise) used only when DART lacks coverage for that specific ticker.
  # Dohoon mandate (2026-05-23): "DART에서 구할 수 없는 과거데이터를 퀀티와이즈로 보강"
  .n_filled <- 0L; .n_dropped_dup <- 0L
  for (xf_nm in names(.XF_TO_DART)) {
    dart_nm <- .XF_TO_DART[[xf_nm]]
    xf_rows   <- combined[Factor_Name == xf_nm]
    if (nrow(xf_rows) == 0L) next
    dart_tickers <- combined[Factor_Name == dart_nm, unique(Ticker)]
    # XF tickers NOT covered by DART → adopt as fill (renamed to DART)
    xf_fill <- xf_rows[!Ticker %in% dart_tickers]
    xf_drop <- nrow(xf_rows) - nrow(xf_fill)
    if (nrow(xf_fill) > 0L) {
      xf_fill <- copy(xf_fill)[, Factor_Name := dart_nm]
      .n_filled <- .n_filled + nrow(xf_fill)
    }
    # Remove all mapped XF rows + append fill rows under DART name
    combined <- rbindlist(list(combined[Factor_Name != xf_nm], xf_fill),
                          use.names = TRUE, fill = TRUE)
    .n_dropped_dup <- .n_dropped_dup + xf_drop
  }
  if (.n_filled + .n_dropped_dup > 0L) {
    cat(sprintf("  Quality merge: %d XF→DART filled (per-ticker), %d XF dropped (DART covered)\n",
                .n_filled, .n_dropped_dup))
  }
  # Unmapped XF (DU/EF/GD/LL/PR/RI 25개): both compute_quality_xf_native (DART)
  # AND xlsx_factor_calculator (QuantiWise) emit same Factor_Name.
  # Per-(Ticker, Factor_Name) dedup keep first → DART preferred (module called earlier).
  # QuantiWise row remains only for tickers not in DART. Dohoon mandate 2026-05-23.
  .unmapped_xf <- c(
    "XF_DU01_NetMargin","XF_DU02_AssetTurnover","XF_DU03_EquityMultiplier",
    "XF_LL01_DebtToCapital","XF_LL02_NetDebt","XF_LL03_CashRatio",
    "XF_LL04_QuickRatio","XF_LL05_WorkingCapital",
    "XF_PR01_EBITDA_Margin","XF_PR02_RetainedEarnings_Ratio",
    "XF_PR03_TaxRate","XF_PR04_NetInterestMargin","XF_PR05_EBITDA_to_Assets",
    "XF_EF01_InventoryTurnover","XF_EF02_DaysPayable",
    "XF_EF03_DaysReceivable","XF_EF04_CCC",
    "XF_GD01_GrossProfit_Growth","XF_GD02_OpProfit_Growth",
    "XF_GD03_OCF_Growth","XF_GD04_Dividend_Growth",
    "XF_RI01_RnD_to_Revenue","XF_RI02_CapEx_proxy","XF_RI03_SGA_to_Revenue"
  )
  .unmapped_present <- intersect(.unmapped_xf, unique(combined$Factor_Name))
  if (length(.unmapped_present) > 0L) {
    xf_rows <- combined[Factor_Name %in% .unmapped_present]
    before_n <- nrow(xf_rows)
    xf_dedupe <- unique(xf_rows, by = c("Ticker","Factor_Name"), fromLast = FALSE)
    after_n <- nrow(xf_dedupe)
    combined <- rbindlist(list(
      combined[!Factor_Name %in% .unmapped_present],
      xf_dedupe
    ), use.names = TRUE, fill = TRUE)
    cat(sprintf("  Unmapped XF dedup: %d rows kept (DART preferred, was %d)\n",
                after_n, before_n))
  }

  # Ensure required columns
  stopifnot(all(c("Ticker", "Factor_Name", "Raw_Value") %in% names(combined)))

  # ─── Standardize ─────────────────────────────────────────────────────────
  cat("  Standardizing (z-score, sector-neutral, rank)...\n")
  result <- .standardize_factors(combined, sector_map)

  # Add Date column
  result[, Date := sig_d]
  setcolorder(result, c("Date", "Ticker", "Factor_Name", "Raw_Value",
                         "Z_Score", "Z_Sector", "Rank_Pct", "Coverage"))

  # ─── Summary stats ──────────────────────────────────────────────────────
  n_factors <- uniqueN(result$Factor_Name)
  n_tickers <- uniqueN(result$Ticker)
  n_covered <- result[Coverage == TRUE, uniqueN(paste(Ticker, Factor_Name))]
  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)

  cat(sprintf("  TOTAL: %d factors x %d tickers = %d rows (%d covered) [%.1fs]\n",
              n_factors, n_tickers, nrow(result), n_covered, elapsed))

  # Coverage summary per factor
  cov_summary <- result[, .(
    N_Total = .N,
    N_Covered = sum(Coverage, na.rm = TRUE),
    Pct_Covered = round(100 * mean(Coverage, na.rm = TRUE), 1)
  ), by = Factor_Name][order(Factor_Name)]
  cat("  Coverage by factor:\n")
  print(cov_summary, topn = 5)

  # ─── 배출 감시 (write 직전, 2026-08-08 FQ-163) ────────────────────────────
  # ★stop 하지 않는다 — 정당한 vintage 결측까지 죽이면 가드가 꺼진다.
  #   경고 + 사이드카 기록이 정본. save=FALSE(시범 산출)면 판정만 하고 원장은
  #   건드리지 않는다(드라이런이 역사를 오염시키면 회귀 판정이 무너진다).
  .emission_report <- factor_emission_guard(
    result        = result,
    ym            = ym_tag,
    fdb_dir       = FACTOR_DB_DIR,
    registry_path = file.path(FUNC_PATH, "factor_db", "factor_registry.json"),
    baseline_path = FACTOR_EMISSION_BASELINE,
    write_artifacts = isTRUE(save),
    # 정체 3축 — `result` 가 이미 Raw_Value/Z_Score/Coverage 를 갖고 있으므로 추가 IO 0.
    identity_baseline_path = FACTOR_IDENTITY_BASELINE,
    run_identity = TRUE
  )

  # ─── Save ─────────────────────────────────────────────────────────────────
  if (save) {
    write_parquet(result, out_path)
    cat(sprintf("  Saved: %s (%.1f MB)\n",
                out_path,
                file.size(out_path) / 1e6))
    # v54 Gate 13.1 — update build hash on every save
    .write_build_hash()
  }

  result
}


#==============================================================================
# 2. build_factor_db_monthly(start_date, end_date) — Batch build for range
#==============================================================================

#' Build factor DB for all month-end dates in range.
#'
#' Finds all month-end trading days in RAWDATA between start_date and end_date,
#' then calls build_factor_db() for each.
#'
#' @param start_date Character or Date
#' @param end_date Character or Date
#' @param force Logical. Overwrite existing cache? (default: FALSE)
#' @return Invisibly, the list of signal dates processed
#' @export
build_factor_db_monthly <- function(start_date = format(ANALYSIS_START_DATE, "%Y-%m-%d"),
                                    end_date   = Sys.Date(),
                                    force      = FALSE) {
  .load_base_data()
  .preload_modules()   # source once here; build_factor_db() will skip re-load

  start_d <- as.Date(start_date)
  end_d   <- as.Date(end_date)

  # Use pre-indexed trading dates
  all_dates <- .fdb_env$trading_dates
  all_dates <- all_dates[all_dates >= start_d & all_dates <= end_d]

  # Extract month-end dates: last trading day of each month
  dt_dates <- data.table(Date = all_dates)
  dt_dates[, YM := format(Date, "%Y%m")]
  month_ends <- dt_dates[, .(sig_date = max(Date)), by = YM][order(YM)]$sig_date

  cat(sprintf("[build_factor_db_monthly] %d month-ends from %s to %s\n",
              length(month_ends), start_d, end_d))

  t0 <- Sys.time()
  n_total <- length(month_ends)

  for (i in seq_along(month_ends)) {
    elapsed_s <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    eta_s     <- if (i > 1) elapsed_s / (i - 1) * (n_total - i + 1) else NA_real_
    eta_str   <- if (is.finite(eta_s)) sprintf(", ETA %.0f min", eta_s / 60) else ""
    cat(sprintf("\n--- [%d/%d] %s (%.0fs elapsed%s) ---\n",
                i, n_total, month_ends[i], elapsed_s, eta_str))
    tryCatch(
      build_factor_db(month_ends[i], save = TRUE, force = force),
      error = function(e) {
        cat(sprintf("  [FATAL] %s: %s\n", month_ends[i], conditionMessage(e)))
      }
    )
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  cat(sprintf("\n[build_factor_db_monthly] Complete: %d months in %.1f minutes\n",
              length(month_ends), elapsed))

  # v54 Gate 13.1 — record build hash after batch completion
  .write_build_hash()

  invisible(month_ends)
}


#==============================================================================
# 2-A2. backfill_custom_factor() — SCOPED backfill (신규 custom 팩터만)
#
# 온보딩 효율화: custom_factors.json 로 선언한 신규 팩터를 기존 월별 parquet에
# "컬럼 추가"만 한다. 나머지 276개 팩터는 재계산하지 않음(~수초/월 vs 전면 ~3분/월).
# add_factor() 직후 이력 확보용. 복잡(전용 compute_*) 팩터는 build_factor_db_monthly(force).
#==============================================================================

#' @param id  단일 factor id, 또는 NULL(=custom_factors.json 의 모든 custom 팩터)
#' @param start_date/end_date  YYYY-MM 범위(NULL=전체 캐시). @param force  존재해도 재계산
#' @return invisibly 처리 요약 리스트
#' @export
#' @param module  어느 compute 모듈이 그 팩터를 내는가 (기본 "custom").
#'   ★2026-09-01 일반화: 이 함수는 'custom 전용' 이 아니라 **팩터 단위 scoped backfill** 이다.
#'   모듈만 갈아끼우면 그대로 쓸 수 있는데 한 줄 때문에 custom 에 묶여 있었다. technical 12종처럼
#'   생산자가 새로 생긴 계열은 전면 재빌드(수시간) 말고 이 경로로 채운다.
backfill_custom_factor <- function(id = NULL, start_date = NULL, end_date = NULL, force = FALSE,
                                   module = "custom") {
  .load_base_data(); .preload_modules()
  if (!module %in% names(.fdb_env$module_funcs))
    stop(sprintf("[backfill] %s 모듈 미로드 (compute_%s.R 확인)", module, module))
  cf <- .fdb_env$module_funcs[[module]]

  files <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$", full.names = TRUE)
  if (!length(files)) stop("[backfill] 월별 parquet 없음: ", FACTOR_DB_DIR)
  yms <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(files))
  if (!is.null(start_date)) files <- files[yms >= format(as.Date(start_date), "%Y%m")]
  if (!is.null(end_date))   files <- files[sub("^factor_db_(\\d{6})\\.parquet$","\\1",basename(files)) <= format(as.Date(end_date), "%Y%m")]
  files <- sort(files)
  cat(sprintf("[backfill_custom_factor] id=%s, %d개 월별 parquet 대상 (force=%s)\n",
              if (is.null(id)) "ALL custom" else id, length(files), force))

  n_done <- 0L; n_skip <- 0L; n_empty <- 0L; n_err <- 0L; t0 <- Sys.time()
  for (pq in files) {
    ym <- sub("^factor_db_(\\d{6})\\.parquet$", "\\1", basename(pq))
    existing <- tryCatch(as.data.table(read_parquet(pq)), error = function(e) NULL)
    if (is.null(existing) || !"Date" %in% names(existing) || nrow(existing) == 0) { n_err <- n_err + 1L; next }
    sig_d <- as.Date(existing$Date[1])

    status <- tryCatch({
      RAWDATA_sliced <- .fdb_env$RAWDATA[Date <= sig_d & Date >= (sig_d - .FDB_SLICE_DAYS)]
      setkey(RAWDATA_sliced, Date, Ticker)
      raw <- cf(RAWDATA = RAWDATA_sliced, sig_date = sig_d,
                FUND = .fdb_env$FUND, CONSENSUS = .fdb_env$CONSENSUS)
      raw <- if (is.null(raw)) NULL else as.data.table(raw)
      if (!is.null(id) && !is.null(raw)) raw <- raw[Factor_Name == id]
      if (is.null(raw) || nrow(raw) == 0) { "empty" } else {
        target_ids <- unique(raw$Factor_Name)
        # idempotent: 이미 **쓸 수 있는 값**이 있으면 스킵 (force=FALSE 일 때).
        # ★2026-09-01 수리 — 구판은 "이미 있나"(Factor_Name 존재)만 봤다. 그런데 고쳐야 하는 것은
        #   대개 **있는데 못 쓰는** 값이다: C15_Forecast_Error_Trend 는 301개월에 존재하지만 전 종목
        #   0.0 이라 횡단면 sd=0 → Z 전건 NA → Coverage FALSE 였고(구 생산자 산물), 생산자가 수리된
        #   뒤에도 백필이 "이미 있음" 으로 건너뛰어 **영원히 안 고쳐졌다**(실측: 201006/201506/202006
        #   전부 distinct 1 · Coverage 0 유지). 멱등 검사가 물어야 할 것은 존재가 아니라 가용성이다.
        if (!force) {
          .usable <- if ("Coverage" %in% names(existing))
            unique(existing[Coverage == TRUE, Factor_Name]) else unique(existing$Factor_Name)
          target_ids <- setdiff(target_ids, .usable)
        }
        if (!length(target_ids)) { "skip" } else {
          raw <- raw[Factor_Name %in% target_ids]
          snap <- .pit_rawdata(sig_d); sector_map <- snap[, .(Ticker, Sector)]
          std <- .standardize_factors(raw, sector_map)
          std[, Date := sig_d]
          keep <- intersect(names(existing), names(std))
          std2 <- std[, ..keep]
          merged <- rbindlist(list(existing[!Factor_Name %in% target_ids], std2),
                              use.names = TRUE, fill = TRUE)
          setcolorder(merged, names(existing))
          tmp <- paste0(pq, ".tmp")
          write_parquet(merged, tmp)          # arrow write → tmp만 (mmap 1224 회피)
          gc()                                # read mmap 해제 (Windows 파일락)
          file.copy(tmp, pq, overwrite = TRUE); file.remove(tmp)  # base-R overwrite
          "done"
        }
      }
    }, error = function(e) { cat(sprintf("  [ERR %s] %s\n", ym, conditionMessage(e))); "err" })

    if (status == "done") n_done <- n_done + 1L
    else if (status %in% c("skip")) n_skip <- n_skip + 1L
    else if (status == "empty") n_empty <- n_empty + 1L
    else n_err <- n_err + 1L
    if ((n_done + n_skip + n_empty + n_err) %% 24L == 0L)
      cat(sprintf("  ...%s  done=%d skip=%d empty=%d err=%d (%.0fs)\n",
                  ym, n_done, n_skip, n_empty, n_err, as.numeric(difftime(Sys.time(), t0, units="secs"))))
  }
  cat(sprintf("[backfill_custom_factor] 완료: done=%d skip=%d empty=%d err=%d / %.1f min\n",
              n_done, n_skip, n_empty, n_err, as.numeric(difftime(Sys.time(), t0, units="mins"))))
  if (n_done > 0L) .write_build_hash()
  invisible(list(done = n_done, skip = n_skip, empty = n_empty, err = n_err))
}


#==============================================================================
# 2-B. build_factor_db_daily() — Daily Factor DB for ML
#
# 최적화 이력:
#   v1.1 (2026-04-04): parallel::mclapply 날짜 병렬화 + RAWDATA 월별 사전 슬라이싱
#   - workers = min(20, parallel::detectCores()-2) 기본값
#   - 각 worker는 COW fork 공유 메모리로 RAWDATA 중복 없음 (Unix-only)
#   - chunk_size: N 날짜를 workers×4 청크로 나눠 진행률 확인 가능
#   - Windows/WSL 환경: mclapply → lapply 자동 강등 (fork 미지원)
#==============================================================================

#' Build daily-frequency Factor DB. Saves to .cache/factor_db_daily/.
#' Each file: factor_db_daily_YYYYMMDD.parquet
#' Resumable: skips dates with existing files (force=FALSE).
#'
#' @param start_date Start date (default "2005-01-01" — pre-2005 data sparse)
#' @param end_date End date
#' @param force Rebuild existing dates
#' @param workers Integer. Parallel workers. Default: min(20, nCores-2).
#'   Set 1 to disable parallelism.
#' @param chunk_size Integer. Dates per progress-report chunk.
build_factor_db_daily <- function(start_date  = format(ANALYSIS_START_DATE, "%Y-%m-%d"),
                                  end_date    = Sys.Date(),
                                  force       = FALSE,
                                  workers     = NULL,
                                  chunk_size  = NULL) {
  daily_dir <- file.path(CACHE_DIR, "factor_db_daily")
  dir.create(daily_dir, showWarnings = FALSE, recursive = TRUE)

  .load_base_data()
  .preload_modules()

  start_d <- as.Date(start_date)
  end_d   <- as.Date(end_date)
  all_dates <- .fdb_env$trading_dates
  target_dates <- all_dates[all_dates >= start_d & all_dates <= end_d]

  # Skip existing
  if (!force) {
    existing <- gsub("factor_db_daily_(\\d{8})\\.parquet", "\\1",
                     list.files(daily_dir, "^factor_db_daily_\\d{8}\\.parquet$"))
    target_tags <- format(target_dates, "%Y%m%d")
    target_dates <- target_dates[!target_tags %in% existing]
  }

  n_target <- length(target_dates)
  cat(sprintf("[build_factor_db_daily] %d dates to build (%s ~ %s)\n",
              n_target,
              if (n_target > 0) as.character(min(target_dates)) else "none",
              if (n_target > 0) as.character(max(target_dates)) else "none"))

  if (n_target == 0) return(invisible(NULL))

  # ── Worker 수 결정 ───────────────────────────────────────────────────────────
  n_cores <- tryCatch(parallel::detectCores(logical = FALSE), error = function(e) 1L)
  if (is.null(workers)) workers <- max(1L, min(20L, n_cores - 2L))

  # fork 가용성 실제 테스트 (WSL2는 OS.type==unix이고 fork 작동)
  use_parallel <- FALSE
  if (workers > 1L && .Platform$OS.type == "unix") {
    fork_ok <- tryCatch({
      r <- parallel::mclapply(1:2, function(x) x^2, mc.cores = 2L)
      !inherits(r[[1]], "try-error")
    }, error = function(e) FALSE)
    use_parallel <- fork_ok
    if (!fork_ok) {
      cat("[build_factor_db_daily] fork 테스트 실패 → workers=1 강등\n")
      workers <- 1L
    }
  } else if (workers > 1L) {
    cat("[build_factor_db_daily] Windows 환경 → workers=1 강등\n")
    workers <- 1L
  }
  cat(sprintf("[build_factor_db_daily] workers=%d | parallel=%s\n",
              workers, use_parallel))

  # ── 청크 사이즈 ─────────────────────────────────────────────────────────────
  if (is.null(chunk_size)) {
    chunk_size <- max(workers * 4L, 50L)
  }

  # ── 월별 사전 슬라이싱 (fork COW 깨짐 방지) ────────────────────────────────
  # 핵심: worker가 .fdb_env$RAWDATA (14M rows)에 직접 접근하면 data.table [
  # 연산이 COW를 깨뜨려 worker당 ~2GB 복사 → OOM.
  # 해결: 부모에서 월별로 RAWDATA를 사전 슬라이싱 → 작은 조각만 worker에 전달.

  cat("[build_factor_db_daily] Pre-slicing RAWDATA by month...\n")
  t_slice <- Sys.time()

  # 날짜를 월별로 그룹화
  dt_target <- data.table(sig_d = target_dates, ym = format(target_dates, "%Y%m"))
  month_groups <- dt_target[, .(dates = list(sig_d)), by = ym][order(ym)]

  # 각 월 그룹에 필요한 RAWDATA 범위 = min(sig_d) - 1400 ~ max(sig_d)
  raw <- .fdb_env$RAWDATA
  fund <- .fdb_env$FUND
  cons <- .fdb_env$CONSENSUS
  module_funcs <- .fdb_env$module_funcs
  trd_dates <- .fdb_env$trading_dates

  cat(sprintf("  %d month-groups, slicing took %.1fs\n",
              nrow(month_groups),
              as.numeric(difftime(Sys.time(), t_slice, units = "secs"))))

  # ── 날짜 1건 처리 (사전 슬라이싱된 데이터 사용) ─────────────────────────────
  .build_one_daily_v2 <- function(sig_d, rd_slice, fund_pit) {
    tag      <- format(sig_d, "%Y%m%d")
    out_path <- file.path(daily_dir, paste0("factor_db_daily_", tag, ".parquet"))
    if (!force && file.exists(out_path)) return(invisible(NULL))

    tryCatch({
      # snapshot: 최근 거래일 <= sig_d
      idx <- findInterval(sig_d, trd_dates)
      if (idx == 0L) return(invisible(NULL))
      actual_d <- trd_dates[idx]
      snap <- rd_slice[Date == actual_d]
      if (nrow(snap) == 0L) return(invisible(NULL))
      sector_map <- snap[, .(Ticker, Sector)]

      daily_modules <- c("value", "momentum", "quality", "defense", "size",
                         "consensus", "liquidity", "growth", "accrual",
                         "investor", "crowding", "risk")

      all_factors <- list()
      for (nm in daily_modules) {
        fn <- module_funcs[[nm]]
        if (is.null(fn)) next
        res <- tryCatch(
          fn(RAWDATA = rd_slice, sig_date = sig_d,
             FUND = fund_pit, CONSENSUS = cons),
          error = function(e) NULL
        )
        if (!is.null(res) && nrow(res) > 0L)
          all_factors[[length(all_factors) + 1L]] <- res
      }

      if (length(all_factors) == 0L) return(invisible(NULL))
      combined <- rbindlist(all_factors, use.names = TRUE, fill = TRUE)
      if (nrow(combined) == 0L) return(invisible(NULL))

      combined <- .standardize_factors(combined, sector_map)
      combined[, Signal_Date := sig_d]
      arrow::write_parquet(combined, out_path)
    }, error = function(e) {
      cat(sprintf("  [ERROR] %s: %s\n", sig_d, conditionMessage(e)))
    })
    invisible(NULL)
  }

  # ── 월 단위 실행 (월 내 날짜는 병렬) ───────────────────────────────────────
  t0 <- Sys.time()
  done_total <- 0L

  for (mi in seq_len(nrow(month_groups))) {
    ym     <- month_groups$ym[mi]
    m_dates <- month_groups$dates[[mi]]

    # 부모에서 이 월 그룹에 필요한 RAWDATA 슬라이스 생성
    slice_start <- min(m_dates) - 1400L
    slice_end   <- max(m_dates)
    rd_slice <- raw[Date >= slice_start & Date <= slice_end]
    setkey(rd_slice, Date, Ticker)

    # FUND PIT 슬라이스
    fund_pit <- if (!is.null(fund) && nrow(fund) > 0L)
                  fund[Factor_Date <= slice_end]
                else NULL

    # 진행률
    elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
    eta_str <- if (done_total > 0) {
      eta <- elapsed / done_total * (n_target - done_total)
      sprintf(", ETA %.0f min", eta)
    } else ""
    cat(sprintf("\n[Month %d/%d] %s: %d dates (%.1f min%s) | slice: %s rows\n",
                mi, nrow(month_groups), ym, length(m_dates),
                elapsed, eta_str,
                format(nrow(rd_slice), big.mark = ",")))

    if (use_parallel && length(m_dates) > 1L) {
      parallel::mclapply(m_dates, .build_one_daily_v2,
                         rd_slice = rd_slice,
                         fund_pit = fund_pit,
                         mc.cores     = workers,
                         mc.preschedule = TRUE,
                         mc.silent    = FALSE)
    } else {
      lapply(m_dates, .build_one_daily_v2,
             rd_slice = rd_slice,
             fund_pit = fund_pit)
    }

    done_total <- done_total + length(m_dates)

    # 메모리 정리 (슬라이스 해제)
    rm(rd_slice, fund_pit)
    if (mi %% 12 == 0) gc(verbose = FALSE)
  }

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  n_built <- length(list.files(daily_dir, "^factor_db_daily_\\d{8}\\.parquet$"))
  per_date <- if (n_target > 0) round(elapsed * 60 / n_target, 1) else NA_real_
  cat(sprintf("\n[build_factor_db_daily] Done: %d dates in %.1f min (~%.1fs/date, total cached: %d)\n",
              n_target, elapsed, per_date, n_built))
}

#==============================================================================
# 3. load_factor_db(sig_date, factors) — Load from cache
#==============================================================================

#' Load factor DB from cache. Returns wide-format data.table.
#'
#' @param sig_date Character or Date. Signal date (finds matching YYYYMM)
#' @param factors Character vector of factor names to load. NULL = all.
#' @param format Character. "wide" (default) or "long".
#' @return data.table. Wide: Date, Ticker, V01_BM, M01_Mom12_1, ...
#'         (values are Z_Score by default). Long: full schema.
#' @export
load_factor_db <- function(sig_date, factors = NULL, format = "wide",
                           value_col = "Z_Score") {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  if (!file.exists(fpath)) {
    # Try to find closest available month
    avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
    if (length(avail) == 0) {
      stop("[load_factor_db] No cached factor DB found. Run build_factor_db() first.")
    }
    avail_ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
    cat(sprintf("[load_factor_db] %s not found. Available: %s\n",
                ym_tag, paste(tail(avail_ym, 10), collapse = ", ")))
    stop("[load_factor_db] Requested month not in cache.")
  }

  dt <- as.data.table(read_parquet(fpath))

  # Filter factors if specified
  if (!is.null(factors)) {
    dt <- dt[Factor_Name %in% factors]
    missing <- setdiff(factors, unique(dt$Factor_Name))
    if (length(missing) > 0) {
      warning("[load_factor_db] Requested factors not found: ",
              paste(missing, collapse = ", "))
    }
  }

  if (format == "long") return(dt)

  # Wide format: Date, Ticker, Factor1, Factor2, ...
  stopifnot(value_col %in% names(dt))
  wide <- dcast(dt, Date + Ticker ~ Factor_Name, value.var = value_col)
  wide
}


#==============================================================================
# 4. update_factor_db_daily() — Cron hook: compute current month if missing
#==============================================================================

#' Enumerate missing month tags between (last cached month + 1) and the month
#' BEFORE as_of's month. P1 2026-06-10: gap-scan support — previously
#' update_factor_db_daily() only built the current month, so any month the
#' machine was off on month-end stayed missing forever.
#' @param as_of Date. Reference "today" (default Sys.Date()).
#' @return Character vector of YYYYMM tags needing backfill (possibly empty).
.fdb_gap_months <- function(as_of = Sys.Date()) {
  cached_ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1",
                    list.files(FACTOR_DB_DIR, "^factor_db_\\d{6}\\.parquet$"))
  if (length(cached_ym) == 0L) return(character(0))

  last_first <- as.Date(paste0(max(cached_ym), "01"), format = "%Y%m%d")
  cur_first  <- as.Date(format(as.Date(as_of), "%Y-%m-01"))
  if (last_first >= cur_first) return(character(0))

  # Month firsts from last cached through current, then drop both endpoints
  # (last cached already exists; current month is handled by the caller).
  month_firsts <- seq(last_first, cur_first, by = "month")
  if (length(month_firsts) <= 2L) return(character(0))
  gap_yms <- format(month_firsts[-c(1L, length(month_firsts))], "%Y%m")
  setdiff(gap_yms, cached_ym)
}

#' Daily update hook for cron. Builds current month's factor DB if not cached.
#' P1 2026-06-10:
#'   1. Gap-scan: backfills all missing months (last cached month + 1 ~
#'      previous month) using each month's last trading day from RAWDATA.
#'   2. IC auto-refresh: compute_all_factor_ic_monthly() runs automatically
#'      after a month-end build or any gap backfill (was manual-only).
#' @export
update_factor_db_daily <- function() {
  today <- Sys.Date()
  ym_tag <- format(today, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  # If today is month-end or cache doesn't exist, rebuild
  next_day <- today + 1L
  is_month_end <- (format(today, "%m") != format(next_day, "%m"))

  # ── Gap-scan backfill (past missing months) ────────────────────────────────
  gap_yms <- .fdb_gap_months(today)
  n_backfilled <- 0L
  if (length(gap_yms) > 0L) {
    cat(sprintf("[update_factor_db_daily] Gap-scan: %d missing month(s): %s\n",
                length(gap_yms), paste(gap_yms, collapse = ", ")))
    .load_base_data()
    trd_dates <- .fdb_env$trading_dates
    trd_ym    <- format(trd_dates, "%Y%m")
    for (ym in gap_yms) {
      m_dates <- trd_dates[trd_ym == ym]
      if (length(m_dates) == 0L) {
        cat(sprintf("  [SKIP] %s: no trading days in RAWDATA\n", ym))
        next
      }
      m_last <- max(m_dates)
      cat(sprintf("  [BACKFILL] %s -> last trading day %s\n", ym, m_last))
      tryCatch({
        build_factor_db(m_last, save = TRUE)
        n_backfilled <- n_backfilled + 1L
      }, error = function(e) {
        cat(sprintf("  [ERROR] %s: %s\n", ym, conditionMessage(e)))
      })
    }
  }

  # ── Current month ───────────────────────────────────────────────────────────
  # D2 2026-07-25: intra-month freshness. The current-month file is a single-
  # sig_date snapshot; before this patch it froze at its first build date until
  # month-end (measured: factor_db_202607 stuck at Date=2026-07-03 for ~3 weeks
  # while RAWDATA ran to 2026-07-24 — silent staleness for load_month_factors
  # consumers). Weekly cadence via staleness check (snapshot Date lags latest
  # RAWDATA trading day > 7 calendar days -> force rebuild at that trading day),
  # not a weekday gate: self-heals if a scheduled run is missed. Daily force
  # was rejected as over-wiring: one build = ~2.3 min measured (2026-07-25,
  # 135.4s) x ~21 trading days/month for consumers that read monthly snapshots.
  rebuild_current <- !file.exists(fpath) || is_month_end
  force_current   <- is_month_end
  build_sig       <- today
  if (!rebuild_current) {
    stale_chk <- tryCatch({
      snap_d <- max(as.Date(as.data.table(
        read_parquet(fpath, col_select = "Date"))$Date), na.rm = TRUE)
      raw_d  <- max(as.Date(as.data.table(
        read_parquet(RAWDATA_CACHE, col_select = "Date"))$Date), na.rm = TRUE)
      list(snap_d = snap_d, raw_d = raw_d)
    }, error = function(e) NULL)
    if (!is.null(stale_chk) &&
        is.finite(as.numeric(stale_chk$raw_d - stale_chk$snap_d)) &&
        as.integer(stale_chk$raw_d - stale_chk$snap_d) > 7L &&
        format(stale_chk$raw_d, "%Y%m") == ym_tag) {
      # Guard: only refresh when latest RAWDATA date is IN the current month —
      # otherwise (RAWDATA itself stale) a rebuild buys nothing and a wrong
      # ym could clobber a prior month-end snapshot.
      cat(sprintf(paste0("[update_factor_db_daily] %s snapshot stale: ",
                         "Date=%s vs RAWDATA max=%s (lag %d d > 7) — weekly refresh\n"),
                  ym_tag, format(stale_chk$snap_d), format(stale_chk$raw_d),
                  as.integer(stale_chk$raw_d - stale_chk$snap_d)))
      rebuild_current <- TRUE
      force_current   <- TRUE
      build_sig       <- stale_chk$raw_d  # real trading day -> Date label = real sig_date
    }
  }
  if (rebuild_current) {
    cat(sprintf("[update_factor_db_daily] Building/updating %s (sig_date=%s)...\n",
                ym_tag, format(build_sig)))
    build_factor_db(build_sig, save = TRUE, force = force_current)
  } else {
    cat(sprintf("[update_factor_db_daily] %s already cached & fresh. Skipping.\n", ym_tag))
  }

  # ── IC auto-refresh ─────────────────────────────────────────────────────────
  # Month-end build per mandate; also after gap backfill (otherwise the IC
  # parquet stays stale for the backfilled months until the next month-end).
  if (is_month_end || n_backfilled > 0L) {
    cat("[update_factor_db_daily] Refreshing monthly IC (factor_ic_monthly.parquet)...\n")
    tryCatch(
      compute_all_factor_ic_monthly(),
      error = function(e) {
        cat(sprintf("[update_factor_db_daily] WARN: IC refresh failed: %s\n",
                    conditionMessage(e)))
      }
    )
  }
  invisible(NULL)
}


#==============================================================================
# 5. get_factor_ic(factor_name, n_months) — IC/ICIR history
#==============================================================================

#' Compute Information Coefficient (IC) history for a factor.
#'
#' IC = Spearman rank correlation between Factor[t] and Return[t+1].
#' ICIR = mean(IC) / sd(IC).
#'
#' @param factor_name Character. Factor ID (e.g., "V01_BM")
#' @param n_months Integer. Number of months to look back (default: 60)
#' @return List with ic_series (data.table: Date, IC), icir (numeric),
#'         mean_ic (numeric), hit_rate (fraction of positive IC months)
#' @export
get_factor_ic <- function(factor_name, n_months = 60L) {
  # Find available factor DB files
  avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$",
                      full.names = TRUE)
  if (length(avail) == 0) stop("[get_factor_ic] No factor DB files found.")

  avail <- sort(avail)
  # Use last n_months+1 files (need t and t+1 for IC)
  if (length(avail) > n_months + 1) {
    avail <- tail(avail, n_months + 1)
  }

  # Load base data for forward returns
  .load_base_data()
  raw <- .fdb_env$RAWDATA

  # Build IC series
  ic_list <- list()

  for (i in seq_along(avail)[-length(avail)]) {
    tryCatch({
      dt_t  <- as.data.table(read_parquet(avail[i]))
      dt_t1 <- as.data.table(read_parquet(avail[i + 1]))

      # Factor values at t
      fv <- dt_t[Factor_Name == factor_name & Coverage == TRUE,
                 .(Ticker, Raw_Value)]
      if (nrow(fv) < 20) next

      sig_d_t  <- dt_t$Date[1]
      sig_d_t1 <- dt_t1$Date[1]

      # Forward 1-month return: from sig_d_t to sig_d_t1
      # Use RAWDATA cumulative return
      ret_data <- raw[Date > sig_d_t & Date <= sig_d_t1,
                      .(Fwd_Ret = prod(1 + Ret, na.rm = TRUE) - 1),
                      by = Ticker]

      merged <- merge(fv, ret_data, by = "Ticker")
      merged <- merged[is.finite(Raw_Value) & is.finite(Fwd_Ret)]

      if (nrow(merged) < 20) next

      ic <- cor(merged$Raw_Value, merged$Fwd_Ret,
                method = "spearman", use = "complete.obs")

      ic_list[[length(ic_list) + 1]] <- data.table(
        Date = sig_d_t,
        Factor_Name = factor_name,
        IC = ic,
        N_Stocks = nrow(merged)
      )
    }, error = function(e) NULL)
  }

  if (length(ic_list) == 0) {
    cat("[get_factor_ic] No IC data computed for", factor_name, "\n")
    return(list(ic_series = data.table(), icir = NA_real_,
                mean_ic = NA_real_, hit_rate = NA_real_))
  }

  ic_dt <- rbindlist(ic_list)
  mean_ic  <- mean(ic_dt$IC, na.rm = TRUE)
  sd_ic    <- sd(ic_dt$IC, na.rm = TRUE)
  icir     <- if (sd_ic > 1e-8) mean_ic / sd_ic else NA_real_
  hit_rate <- mean(ic_dt$IC > 0, na.rm = TRUE)

  cat(sprintf("[get_factor_ic] %s: IC=%.4f, ICIR=%.3f, Hit=%.1f%% (%d months)\n",
              factor_name, mean_ic, icir, hit_rate * 100, nrow(ic_dt)))

  list(
    ic_series = ic_dt,
    icir      = icir,
    mean_ic   = mean_ic,
    hit_rate  = hit_rate
  )
}


#==============================================================================
# 6. Utility: list_available_months() / factor_db_status()
#==============================================================================

#' List all months with cached factor DB
#' @export
list_factor_db_months <- function() {
  avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
  if (length(avail) == 0) {
    cat("[factor_db] No cached months.\n")
    return(character(0))
  }
  ym <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
  ym <- sort(ym)
  cat(sprintf("[factor_db] %d months cached: %s ~ %s\n",
              length(ym), ym[1], tail(ym, 1)))
  ym
}

#' Print factor DB status summary
#' @export
factor_db_status <- function() {
  cat("=== Factor DB Status ===\n")
  months <- list_factor_db_months()
  if (length(months) == 0) return(invisible(NULL))

  # Load most recent
  latest_path <- file.path(FACTOR_DB_DIR,
                           paste0("factor_db_", tail(months, 1), ".parquet"))
  dt <- as.data.table(read_parquet(latest_path))

  cat(sprintf("Latest month: %s\n", tail(months, 1)))
  cat(sprintf("Factors: %d | Tickers: %d | Rows: %s\n",
              uniqueN(dt$Factor_Name), uniqueN(dt$Ticker),
              format(nrow(dt), big.mark = ",")))

  # Coverage summary
  cov <- dt[, .(
    Coverage_Pct = round(100 * mean(Coverage, na.rm = TRUE), 1)
  ), by = Factor_Name][order(Factor_Name)]
  print(cov)

  # Registry check
  if (file.exists(FACTOR_REG_PATH)) {
    reg <- fromJSON(FACTOR_REG_PATH)
    cat(sprintf("\nRegistry: %d factors defined\n", length(reg)))
    registered <- names(reg)
    computed   <- unique(dt$Factor_Name)
    missing    <- setdiff(registered, computed)
    extra      <- setdiff(computed, registered)
    if (length(missing) > 0) cat("  Missing from DB:", paste(missing, collapse = ", "), "\n")
    if (length(extra) > 0)   cat("  Extra (not in registry):", paste(extra, collapse = ", "), "\n")
  }

  invisible(dt)
}


#==============================================================================
# 7. Batch IC computation for all factors
#==============================================================================

#' Compute IC/ICIR for all factors in the most recent DB snapshot
#' @param n_months Integer. Lookback months for IC (default: 60)
#' @return data.table: Factor_Name, Mean_IC, ICIR, Hit_Rate, N_Months
#' @export
get_all_factor_ic <- function(n_months = 60L) {
  # Get factor names from most recent snapshot
  months <- list_factor_db_months()
  if (length(months) == 0) stop("No factor DB cached.")

  latest_path <- file.path(FACTOR_DB_DIR,
                           paste0("factor_db_", tail(months, 1), ".parquet"))
  dt <- as.data.table(read_parquet(latest_path))
  factor_names <- sort(unique(dt$Factor_Name))

  cat(sprintf("[get_all_factor_ic] Computing IC for %d factors...\n",
              length(factor_names)))

  results <- list()
  for (fn in factor_names) {
    res <- tryCatch(get_factor_ic(fn, n_months), error = function(e) NULL)
    if (!is.null(res) && !is.na(res$icir)) {
      results[[length(results) + 1]] <- data.table(
        Factor_Name = fn,
        Mean_IC     = round(res$mean_ic, 4),
        ICIR        = round(res$icir, 3),
        Hit_Rate    = round(res$hit_rate, 3),
        N_Months    = nrow(res$ic_series)
      )
    }
  }

  if (length(results) == 0) return(data.table())

  ic_all <- rbindlist(results)[order(-abs(ICIR))]

  # Save to parquet
  write_parquet(ic_all, FACTOR_IC_PATH)
  cat(sprintf("[get_all_factor_ic] Saved IC history: %s\n", FACTOR_IC_PATH))

  ic_all
}


#==============================================================================
# 7. compute_all_factor_ic_monthly() — Batch IC for allocation engine
#==============================================================================

#' Compute monthly IC for ALL factors across ALL months.
#' IC[t] = Spearman corr(Z_Score[t], Ret[t -> t+1]).
#' Saves to .cache/factor_db/factor_ic_monthly.parquet
#'
#' @return data.table: Date, Factor_Name, IC, N_Stocks
#' @export
compute_all_factor_ic_monthly <- function() {
  .load_base_data()
  raw <- .fdb_env$RAWDATA

  avail <- sort(list.files(FACTOR_DB_DIR,
                           pattern = "^factor_db_\\d{6}\\.parquet$",
                           full.names = TRUE))
  if (length(avail) < 2) stop("[IC_monthly] Need at least 2 months of factor DB.")

  cat(sprintf("[IC_monthly] Computing IC for %d month-pairs...\n", length(avail) - 1))
  t0 <- Sys.time()

  # 월별 RAWDATA 최종 거래일 — 루프 밖에서 1회만 만든다.
  # (구현은 pair 마다 RAWDATA 전체에 format() 을 돌렸다: 300+ pair × 수백만 행.
  #  가드가 느려서 뜯겨나가는 것도 가드가 무력화되는 경로다.)
  # 이름 조회는 x[key] — x[[key]] 는 Date 클래스를 떨궈 비교가 조용히 틀어진다.
  .rml <- raw[, .(.last = max(Date)), by = .(.ym = format(Date, "%Y-%m"))]
  .raw_month_last_map <- setNames(as.Date(.rml$.last), .rml$.ym)

  ic_list <- vector("list", length(avail) - 1)

  for (i in seq_along(avail)[-length(avail)]) {
    tryCatch({
      dt_t  <- as.data.table(read_parquet(avail[i]))
      dt_t1 <- as.data.table(read_parquet(avail[i + 1]))

      sig_d_t  <- dt_t$Date[1]
      sig_d_t1 <- dt_t1$Date[1]

      # Incomplete-terminal-pair guard (2026-07-25 신설 / 2026-07-26 2조건 강화 /
      # 2026-07-26 순수 함수 분리). 판정 본문·근거는 ic_pair_completeness.R,
      # 상설 위반 주입 테스트는 08_Tests/factor_db/test_ic_completion_guard.R.
      #   (a) 달력 종료  : 진행 중인 달의 부분 forward window 금지
      #   (b) 파일 도달  : 월말 재빌드 지연 시 sig 가 월중인데 달력만 넘어간 상태 금지
      .m_t1 <- format(sig_d_t1, "%Y-%m")
      .chk <- .ic_pair_complete(sig_d_t1, today = Sys.Date(),
                                raw_month_last = .raw_month_last_map[.m_t1])
      if (!isTRUE(.chk$complete)) {
        cat(sprintf("  [skip] pair %d: forward month %s incomplete (%s: %s)\n",
                    i, .m_t1, .chk$reason, .chk$detail))
        next
      }

      # Forward 1-month return per ticker
      ret_data <- raw[Date > sig_d_t & Date <= sig_d_t1,
                      .(Fwd_Ret = prod(1 + Ret, na.rm = TRUE) - 1),
                      by = Ticker]

      # Get all factors at time t
      fv <- dt_t[Coverage == TRUE, .(Ticker, Factor_Name, Raw_Value)]
      merged <- merge(fv, ret_data, by = "Ticker")
      merged <- merged[is.finite(Raw_Value) & is.finite(Fwd_Ret)]

      if (nrow(merged) < 30) next

      # IC per factor
      ic_per_factor <- merged[, {
        n <- .N
        if (n < 20) list(IC = NA_real_, N_Stocks = n)
        else list(
          IC = cor(Raw_Value, Fwd_Ret, method = "spearman", use = "complete.obs"),
          N_Stocks = n
        )
      }, by = Factor_Name]

      ic_per_factor <- ic_per_factor[!is.na(IC)]
      ic_per_factor[, Date := sig_d_t]
      # Usable_Date: this IC can only be used AFTER the forward return period ends
      # IC[t] uses return[t→t+1], so it's only known at t+1
      ic_per_factor[, Usable_Date := sig_d_t1]

      ic_list[[i]] <- ic_per_factor

      if (i %% 25 == 0) {
        cat(sprintf("  [%d/%d] %s — %d factors\n",
                    i, length(avail) - 1, sig_d_t, nrow(ic_per_factor)))
      }
    }, error = function(e) {
      cat(sprintf("  [WARN] %d: %s\n", i, conditionMessage(e)))
    })
  }

  ic_all <- rbindlist(ic_list[!sapply(ic_list, is.null)])
  setorder(ic_all, Factor_Name, Date)

  out_path <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
  write_parquet(ic_all, out_path)

  elapsed <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1)
  cat(sprintf("[IC_monthly] Done: %s rows | %d factors | %d months | %.1f min\n",
              format(nrow(ic_all), big.mark = ","),
              uniqueN(ic_all$Factor_Name),
              uniqueN(ic_all$Date), elapsed))
  cat(sprintf("  Saved: %s\n", out_path))

  invisible(ic_all)
}


cat("[factor_db_builder] Ready. Functions: build_factor_db(), build_factor_db_monthly(),\n")
cat("  load_factor_db(), update_factor_db_daily(), get_factor_ic(),\n")
cat("  compute_all_factor_ic_monthly(), factor_db_status()\n")
