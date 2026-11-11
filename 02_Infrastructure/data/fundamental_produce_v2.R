#==============================================================================
# fundamental_produce_v2.R — 재무 원천 v2 생산기(2026-11-09 · 도훈 결정 '퀀티 메인 · DART 서브' · '보충 끝나면 전체 재빌드')
#
#   build_fundamental_v2.py(퀀티 메인 · DART 정정 검사 · 실제 공시일)
#   → build_fundamental_merged_v2.R(날짜 순서 계약 · 옛 Source 역할 표지)
#   → 후보 검사 → 지금 정본 사본(.cache/fundamental_backup/<시각>/) → 정본 교체:
#       .cache/fundamental_merged.parquet  ← 병합 표
#       .cache/fundamental_xlsx.parquet    ← 분기 표(XF 팩터 · xlsx_factor_calculator.R)
#
# 부르는 곳: build_fundamental_derived.R(06_Registry/fundamental_source.json::active == "v2" 일 때 위임 —
#   월간 [5a2/7] · DART 보충 완료 단계). 직접 실행: Rscript fundamental_produce_v2.R [--candidate-only]
#   --candidate-only = 후보만 만들고 검사(정본 그대로 · 전환 전 리허설).
# 정본을 바꾸기 전에 멈추는 것: 입력 없음 · 하위 단계 실패 · 후보 검사 실패(열 · 항목 수 · 종목 수 · 날짜 순서 · 행 수 급감).
# 종료: 0 성공 · 1 실패(정본 그대로) · 3 입력 없음
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
args <- commandArgs(trailingOnly = TRUE)
CAND_ONLY <- "--candidate-only" %in% args
t0 <- Sys.time()
.say <- function(...) cat("[fund-v2-produce]", sprintf(...), "\n")

# 루트: 환경변수 후보를 '/' 로 고친 뒤 표식 파일로 검증(r-portability ③) · 순서 = CLAUDE_PROJECT_DIR → QM_ROOT(금칙 ④ 표준 계열)
.root_ok <- function(p) nzchar(p) && file.exists(file.path(p, "02_Infrastructure/hooks/qvest_hook_router.py"))
ROOT <- ""
for (cand in c(Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"))) {
  cand <- gsub("\\\\", "/", cand)
  if (.root_ok(cand)) { ROOT <- cand; break }
  if (nzchar(cand)) .say("루트 후보 기각(표식 없음): %s", cand)
}
if (!nzchar(ROOT)) {
  .self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L])
  cand <- gsub("\\\\", "/", dirname(dirname(dirname(.self))))
  if (.root_ok(cand)) ROOT <- cand
}
if (!nzchar(ROOT)) { .say("오류: 프로젝트 루트를 찾지 못했다"); quit(save = "no", status = 1) }
DATA <- file.path(ROOT, "02_Infrastructure", "data")
CACHE <- file.path(ROOT, ".cache")
V2D <- file.path(CACHE, "fundamental_v2")
CAND_M <- file.path(V2D, "candidate_fundamental_merged.parquet")
CAND_X <- file.path(V2D, "candidate_fundamental_xlsx.parquet")
CANON_M <- file.path(CACHE, "fundamental_merged.parquet")
CANON_X <- file.path(CACHE, "fundamental_xlsx.parquet")

# ---- 0. 입력 ---------------------------------------------------------------------------------------
need <- c(file.path(CACHE, "qw_fund_v2", paste0("FundV2_", c("BS", "IS", "CF", "META"), ".parquet")),
          file.path(CACHE, "qw_fund_v2", "fiscal_month.parquet"), file.path(CACHE, "fundamental_dart.parquet"),
          file.path(CACHE, "dart", "dart_raw_financials.parquet"), file.path(CACHE, "RAWDATA.parquet"))
miss <- need[!file.exists(need)]
if (length(miss)) { .say("입력 없음: %s", paste(miss, collapse = " · ")); quit(save = "no", status = 3) }

# ---- 1. 파이썬(venv · 기능 확인으로 채택 — 시스템 Python 에는 pandas 가 없다) ---------------------------------
PY <- file.path(ROOT, ".venv_qvest_ml", "Scripts", "python.exe")
if (!file.exists(PY)) PY <- file.path(ROOT, ".venv_qvest_ml", "bin", "python")
probe <- if (file.exists(PY)) suppressWarnings(system2(PY, c("-c", shQuote("import pandas, pyarrow")), stdout = FALSE, stderr = FALSE)) else 127L
if (!identical(as.integer(probe), 0L)) { .say("오류: venv 파이썬이 pandas · pyarrow 를 못 읽는다(%s rc=%s)", PY, probe); quit(save = "no", status = 1) }
Sys.setenv(PYTHONUTF8 = "1")
.say("1/4 재무 v2 분기 표(build_fundamental_v2.py)...")
rc <- system2(PY, c("-X", "utf8", shQuote(file.path(DATA, "build_fundamental_v2.py")), "--root", shQuote(ROOT)))
if (!identical(as.integer(rc), 0L)) { .say("오류: build_fundamental_v2.py rc=%s — 정본 그대로", rc); quit(save = "no", status = 1) }

# ---- 2. 병합 표 · 분기 표 후보 ------------------------------------------------------------------------
RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
.say("2/4 병합 표 · 분기 표 후보(build_fundamental_merged_v2.R)...")
rc <- system2(RS, c("--no-save", shQuote(file.path(DATA, "build_fundamental_merged_v2.R")), "--root", shQuote(ROOT),
                    "--out", shQuote(CAND_M), "--out-xlsx", shQuote(CAND_X)))
if (!identical(as.integer(rc), 0L)) { .say("오류: build_fundamental_merged_v2.R rc=%s — 정본 그대로", rc); quit(save = "no", status = 1) }

# ---- 3. 후보 검사 ----------------------------------------------------------------------------------
.fail <- character()
# was_v2 = 지금 정본이 이미 v2 산출(전환 뒤 월간 재생성) → 행 수가 5% 넘게 줄면 멈춘다(입력 결손 의심).
#   전환 직전(정본 = v1)은 v2 가 옛 표보다 커서 비교하지 않는다.
.check <- function(path, cols, n_items, label, canon, was_v2) {
  if (!file.exists(path)) { .fail <<- c(.fail, sprintf("%s 후보 없음", label)); return(invisible(NULL)) }
  d <- as.data.table(read_parquet(path))
  if (!identical(names(d), cols)) .fail <<- c(.fail, sprintf("%s 열 %s", label, paste(names(d), collapse = ",")))
  if (uniqueN(d$Item) != n_items) .fail <<- c(.fail, sprintf("%s 항목 %d(기대 %d)", label, uniqueN(d$Item), n_items))
  if (uniqueN(d$Ticker) < 2000L) .fail <<- c(.fail, sprintf("%s 종목 %d(< 2000)", label, uniqueN(d$Ticker)))
  setorder(d, Ticker, Item, Period_Date)
  bad <- d[, .(v = Factor_Date <= shift(Factor_Date) & Ticker == shift(Ticker) & Item == shift(Item))][v == TRUE, .N]
  if (bad > 0L) .fail <<- c(.fail, sprintf("%s 날짜 순서 계약 위반 %d", label, bad))
  if (any(d$Factor_Date <= d$Period_Date)) .fail <<- c(.fail, sprintf("%s Factor_Date <= Period_Date", label))
  if (was_v2 && file.exists(canon)) {
    n_old <- nrow(read_parquet(canon, col_select = "Ticker"))
    if (nrow(d) < 0.95 * n_old)
      .fail <<- c(.fail, sprintf("%s 행 %s < 지금 정본 %s 의 95%%", label, format(nrow(d), big.mark = ","), format(n_old, big.mark = ",")))
  }
  .say("   %s 후보: 행 %s · 종목 %d · 항목 %d · 날짜 %s~%s", label, format(nrow(d), big.mark = ","), uniqueN(d$Ticker),
       uniqueN(d$Item), format(min(d$Factor_Date)), format(max(d$Factor_Date)))
  invisible(d)
}
.say("3/4 후보 검사...")
WAS_V2 <- file.exists(file.path(CACHE, "fundamental_backup", "ACTIVE_V2"))
.check(CAND_M, c("Ticker", "Period", "Period_Date", "Factor_Date", "Item", "Value", "Source", "Origin", "Freq"), 181L,
       "병합 표", CANON_M, WAS_V2)
.check(CAND_X, c("Ticker", "Period", "Item", "Value", "Period_Date", "Factor_Date"), 41L, "분기 표", CANON_X, WAS_V2)
if (length(.fail)) { .say("오류: 후보 검사 실패 — 정본 그대로: %s", paste(.fail, collapse = " | ")); quit(save = "no", status = 1) }
if (CAND_ONLY) { .say("후보만(--candidate-only) — 정본 그대로 · %.0fs", as.numeric(difftime(Sys.time(), t0, units = "secs"))); quit(save = "no", status = 0) }

# ---- 4. 사본 · 교체 --------------------------------------------------------------------------------
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
bdir <- file.path(CACHE, "fundamental_backup", paste0(if (!WAS_V2) "pre_v2_" else "", stamp))
dir.create(bdir, recursive = TRUE, showWarnings = FALSE)
for (f in c(CANON_M, CANON_X)) if (file.exists(f) && !file.copy(f, file.path(bdir, basename(f)), overwrite = FALSE)) {
  .say("오류: 사본 실패 — 교체하지 않는다: %s", f); quit(save = "no", status = 1)
}
.say("4/4 사본: %s", bdir)
.replace <- function(src, dst) {
  tmp <- paste0(dst, ".tmp", Sys.getpid())
  if (!file.copy(src, tmp, overwrite = TRUE)) return(FALSE)
  if (file.exists(dst)) unlink(dst)
  file.rename(tmp, dst)
}
if (!.replace(CAND_M, CANON_M) || !.replace(CAND_X, CANON_X)) {
  .say("오류: 교체 실패 — 사본에서 되돌릴 것: %s", bdir); quit(save = "no", status = 1)
}
writeLines(c(stamp, bdir), file.path(CACHE, "fundamental_backup", "ACTIVE_V2"))
# 사본은 최근 3개만 남긴다(전환 직전 pre_v2_* 는 지우지 않는다)
olds <- sort(list.dirs(file.path(CACHE, "fundamental_backup"), recursive = FALSE, full.names = TRUE))
olds <- olds[!grepl("^pre_v2_", basename(olds))]
if (length(olds) > 3L) unlink(head(olds, length(olds) - 3L), recursive = TRUE)
.say("정본 교체 완료: %s · %s · %.0fs", CANON_M, CANON_X, as.numeric(difftime(Sys.time(), t0, units = "secs")))
quit(save = "no", status = 0)
