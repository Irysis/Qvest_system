#!/usr/bin/env Rscript
#==============================================================================
# test_phase9b_standalone_regime_key.R — phase9b 를 **혼자(별도 R 프로세스)** 돌렸을 때 RE04 가 산출되는가
#   (PIT C11 2단계 · 2026-09-25 · 재빌드 스모크 적발 결함의 회귀 검사)
#
# 왜: factor_db_daily_phase9b.R 은 regime_daily_v2 스탬프 가드(fdb_regime_c11_ok)로 MRS 를 거른다. 가드는 현행 규칙
#   epoch 를 fred_avail_rules_meta() 로 읽는데, 9b 는 phase6·7 과 달리 fred_availability.R 을 싣지 않았다 → 혼자 돌면
#   현행 키 NA → 스탬프가 맞아도 MRS 전부 NA → RE04 전 기간 NA(fail-closed 상시 발화). 9b 는 run_fdb_rebuild.sh 에
#   없어 늘 별도 프로세스로 돈다 — 기존 검사(test_daily_fdb_pit_c11.R)는 도우미를 같은 세션에 올린 채 블록을 평가해 못 잡았다.
#   (2026-09-24 스모크: 40종목 샌드박스 전 월 재빌드에서 RE04 valid 0 · 로그 '현행 NA')
#
# 설계 — 운영 데이터의 5종목 부분집합으로 만든 **임시 루트**(QM_ROOT)에서 실제 phase9b 를 Rscript 로 돌린다(운영 무접촉):
#   T1 [양성]     수리판 9b + 현행 epoch 스탬프 regime → RE04 유효값 > 0 · '미수리판' 경고 없음
#   T2 [돌연변이] 수리판에서 fred_availability.R source 줄만 뺀 판 → RE04 = 0 (= 결함 재현, 이 검사가 red 를 낸다)
#   T3 [음성]     수리판 9b + 스탬프 **없는** regime → RE04 = 0 (수리가 가드를 우회하지 않는다 — fail-closed 유지)
#   텔레그램: 9b 말미 tg_send 는 잠금 바인딩 스텁으로 막는다(+ 프록시 127.0.0.1:9 로 네트워크 차단).
#   ★격리(2026-09-25 통합 수리 · 적대 검증 SMALL B1): 자식 R 은 시작 때 ~/.Renviron 을 적용해 Sys.setenv 로 물려준 QM_ROOT 를
#     운영 경로로 덮는다 → config.R 의 CACHE_DIR 이 운영 .cache 가 되어 9b 가 운영 RAWDATA 로 돌고 운영 factor_db_daily 를 다시 썼다
#     (스위트 러너·야간 수집은 R_ENVIRON_USER 를 비우지 않는다). 수리 = 자식에게 빈 Renviron + 식 맨 앞에서 루트 재고정 +
#     config 가 해석한 CACHE_DIR 이 임시 루트 아래인지 확인한 뒤에만 9b 를 싣는다 + T4 운영(및 Renviron 루트) factor_db_daily 무접촉 단정.
# 실행: cd <ROOT> && Rscript 08_Tests/factor_db/test_phase9b_standalone_regime_key.R   (약 2~3분 — Rcpp 컴파일 캐시 공유)
#   대상 주입: QVEST_P9B_SRC=<phase9b 경로> (기본 = 운영 02_Infrastructure/factor_db/factor_db_daily_phase9b.R)
#==============================================================================
suppressMessages({ library(data.table); library(arrow); library(dplyr, warn.conflicts = FALSE) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
SRC  <- Sys.getenv("QVEST_P9B_SRC", file.path(ROOT, "02_Infrastructure/factor_db/factor_db_daily_phase9b.R"))
C    <- file.path(ROOT, ".cache")
.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
cat(sprintf("== phase9b 단독 실행 RE04 (%s) ==\n", SRC))
need <- c(file.path(C, c("RAWDATA.parquet", "benchmark.parquet", "regime_daily_v2.parquet", "fundamental_merged.parquet")), SRC)
if (!all(file.exists(need))) { cat("  SKIP 입력 부재:", paste(need[!file.exists(need)], collapse = ","), "\n"); quit(status = 0L) }

TMP <- normalizePath(file.path(tempdir(), paste0("p9b_", format(Sys.time(), "%H%M%S"))), winslash = "/", mustWork = FALSE)
RCPP_CACHE <- file.path(TMP, "rcpp_cache"); dir.create(RCPP_CACHE, recursive = TRUE)
EMPTY_RENV <- file.path(TMP, "empty.Renviron"); file.create(EMPTY_RENV)
.renv_orig <- Sys.getenv("R_ENVIRON_USER", unset = "")
.renv_root <- local({   # 이 프로세스가 읽은 Renviron 의 QM_ROOT = 격리가 깨지면 자식이 쓰게 될 루트
  f <- if (nzchar(.renv_orig)) .renv_orig else file.path(Sys.getenv("HOME", path.expand("~")), ".Renviron")
  l <- if (file.exists(f)) grep("^\\s*QM_ROOT\\s*=", readLines(f, warn = FALSE), value = TRUE) else character(0)
  if (length(l)) gsub("\\\\", "/", trimws(gsub("^[\"']|[\"']$", "", trimws(sub("^[^=]*=", "", l[length(l)]))))) else NA_character_
})
.guard_dirs <- unique(file.path(na.omit(c(ROOT, .renv_root)), ".cache/factor_db_daily"))
.fdb_snap <- function() { f <- unlist(lapply(.guard_dirs[dir.exists(.guard_dirs)], list.files, full.names = TRUE))
  if (!length(f)) return(character(0)); i <- file.info(f); sort(paste(f, i$size, format(i$mtime, "%Y%m%d%H%M%OS3"))) }
FDB0 <- .fdb_snap()
fa <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"), envir = fa)
KEY <- fa$fred_avail_rules_meta()$regime_key

# ── 임시 루트 1개 = 데이터(.cache) + 코드 사본(02_Infrastructure · 06_Registry 규칙) ──
mk_root <- function(tag, p9b_lines, stamped) {
  r <- file.path(TMP, tag); dc <- file.path(r, ".cache"); fd <- file.path(dc, "factor_db_daily")
  for (d in c(fd, file.path(r, "02_Infrastructure/factor_db"), file.path(r, "02_Infrastructure/data"), file.path(r, "06_Registry")))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  for (f in c("config.R", "data/fred_availability.R", "factor_db/factor_db_daily_pit.R", "factor_db/factor_db_daily_rcpp.cpp"))
    file.copy(file.path(ROOT, "02_Infrastructure", f), file.path(r, "02_Infrastructure", f))
  file.copy(file.path(ROOT, "06_Registry/fred_availability_rules.json"), file.path(r, "06_Registry"))
  writeLines(p9b_lines, file.path(r, "02_Infrastructure/factor_db/factor_db_daily_phase9b.R"), useBytes = TRUE)
  file.copy(file.path(C, "benchmark.parquet"), dc)
  write_parquet(RW_SUB, file.path(dc, "RAWDATA.parquet")); write_parquet(FM_SUB, file.path(dc, "fundamental_merged.parquet"))
  rg <- REG; if (stamped) attr(rg, "c11_avail_regime_key") <- KEY
  write_parquet(rg, file.path(dc, "regime_daily_v2.parquet"))
  for (ym in c("202011", "202012")) {   # 9b 는 FDB_DIR 의 월 파일에 병합하고 [4/4] 에서 202012 를 하드코딩으로 읽는다
    x <- as.data.table(RW_SUB)[format(as.Date(Date), "%Y%m") == ym, .(Date = as.Date(Date), Ticker)]
    write_parquet(x, file.path(fd, sprintf("fdb_daily_%s.parquet", ym)))
  }
  r
}
run_9b <- function(r) {
  ## 식 맨 앞에서 루트를 다시 세우고(자식 Renviron 이 덮은 QM_ROOT 무효화), config.R 이 해석한 CACHE_DIR 이 임시 루트 아래가
  ##   아니면 9b 를 싣기 전에 중단한다(운영 .cache 에 한 줄도 쓰지 않는다).
  expr <- sprintf(paste0("Sys.setenv(QM_ROOT = '%s', CLAUDE_PROJECT_DIR = '%s'); source('config.R'); ",
                         "if (!startsWith(tolower(gsub('\\\\\\\\', '/', CACHE_DIR)), tolower('%s'))) stop('[p9b test] CACHE_DIR 가 임시 루트 밖: ', CACHE_DIR); ",
                         "options(rcpp.cache.dir = '%s'); tg_send <- function(...) invisible(list(ok = FALSE)); ",
                         "lockBinding('tg_send', globalenv()); source('factor_db/factor_db_daily_phase9b.R')"), r, r, r, RCPP_CACHE)
  env <- c(sprintf("QM_ROOT=%s", r), sprintf("CLAUDE_PROJECT_DIR=%s", r), sprintf("R_ENVIRON_USER=%s", EMPTY_RENV),
           "http_proxy=http://127.0.0.1:9", "https_proxy=http://127.0.0.1:9", "HTTP_PROXY=http://127.0.0.1:9", "HTTPS_PROXY=http://127.0.0.1:9")
  owd <- setwd(file.path(r, "02_Infrastructure")); on.exit(setwd(owd))
  # system2 의 env 인자는 Windows 에서 무시된다 — Sys.setenv 로 자식에 상속시키고 되돌린다
  old <- Sys.getenv(c("QM_ROOT", "CLAUDE_PROJECT_DIR", "R_ENVIRON_USER", "http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"), unset = NA)
  kv <- strsplit(env, "=", fixed = TRUE); do.call(Sys.setenv, setNames(lapply(kv, `[`, 2), vapply(kv, `[`, "", 1)))
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  log <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("--no-save", "-e", shQuote(expr)), stdout = TRUE, stderr = TRUE))
  st <- as.integer(attr(log, "status") %||% 0L)
  x <- tryCatch(as.data.table(read_parquet(file.path(r, ".cache/factor_db_daily/fdb_daily_202012.parquet"), mmap = FALSE)), error = function(e) NULL)
  list(status = st, log = log, re04 = if (!is.null(x) && "RE04_HighVol_Beta" %in% names(x)) sum(!is.na(x$RE04_HighVol_Beta)) else NA_integer_,
       warned = any(grepl("phase9b RE04 regime_daily_v2 미수리판", log)))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ── 데이터 부분집합(읽기 전용): 2020-12-30 거래 종목 중 5종 · 전 이력(RE04 252일 창 · MRS 누적 백분위) ──
ds <- open_dataset(file.path(C, "RAWDATA.parquet"))
tk <- as.data.table(ds |> filter(Date == as.Date("2020-12-30")) |> select(Ticker) |> collect())$Ticker
set.seed(9); tk <- sort(sample(tk, 5))
RW_SUB <- ds |> filter(Ticker %in% tk) |> collect()
FM_SUB <- open_dataset(file.path(C, "fundamental_merged.parquet")) |> filter(Ticker %in% tk) |> collect()
REG <- as.data.frame(read_parquet(file.path(C, "regime_daily_v2.parquet"), mmap = FALSE))
attr(REG, "c11_avail_regime_key") <- NULL

src_lines <- readLines(SRC, encoding = "UTF-8", warn = FALSE)
anchor <- grepl('^\\s*source\\(file\\.path\\(INFRA_DIR, "data", "fred_availability\\.R"\\)\\)', src_lines)
if (!any(anchor)) ng("수리 줄(source fred_availability.R) 부재 — 9b 단독 실행 시 현행 키 NA → RE04 전 기간 NA (T1 에서 재현된다)")

r1 <- run_9b(mk_root("fixed", src_lines, stamped = TRUE))
if (identical(r1$status, 0L) && isTRUE(r1$re04 > 0L) && !r1$warned)
  ok(sprintf("T1 [양성] 단독 실행 · 현행 epoch 스탬프 → RE04 유효 %d셀 · 가드 경고 없음", r1$re04)) else
  ng("T1 RE04 미산출", sprintf("rc=%s re04=%s warned=%s | %s", r1$status, r1$re04, r1$warned,
                               paste(tail(grep("C11|Error|error", r1$log, value = TRUE), 2), collapse = " / ")))

if (any(anchor)) {
  r2 <- run_9b(mk_root("mutant", src_lines[!anchor], stamped = TRUE))
  if (identical(r2$re04, 0L) && r2$warned) ok("T2 [돌연변이] fred_availability.R source 제거판 → RE04 0 · '현행 NA' 가드 발화(= 결함 재현, 검사 red)")
  else ng("T2 돌연변이가 결함을 재현하지 못했다(검사 검출력 없음)", sprintf("re04=%s warned=%s", r2$re04, r2$warned))
}
r3 <- run_9b(mk_root("unstamped", src_lines, stamped = FALSE))
if (identical(r3$re04, 0L) && r3$warned) ok("T3 [음성] 스탬프 없는 regime → RE04 0 · 가드 발화(수리가 fail-closed 를 우회하지 않는다)") else
  ng("T3 스탬프 없는 regime 인데 RE04 산출", sprintf("re04=%s warned=%s", r3$re04, r3$warned))

if (identical(.fdb_snap(), FDB0)) ok(sprintf("T4 [격리] %s 무접촉(자식이 ~/.Renviron QM_ROOT 로 새지 않았다)", paste(.guard_dirs, collapse = " · "))) else
  ng("T4 ★운영(또는 Renviron 루트) factor_db_daily 가 바뀌었다 — 자식 격리 실패", paste(setdiff(.fdb_snap(), FDB0)[1:3], collapse = " / "))
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
# 요약 JSON(run_all_hooks.sh 계약 — 없으면 UNMEASURED · 2026-09-25 C11 S9 에서 미측정으로 드러남)
cat(sprintf('{"test":"test_phase9b_standalone_regime_key","pass":%d,"fail":%d,"skipped":0,"total":%d,"skips":[]}\n', .pass, .fail, .pass + .fail))
if (.fail > 0L) quit(status = 1L)
