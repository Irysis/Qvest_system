#==============================================================================
# Discovery Substrate Loader — P7 처방: 발굴 기질 ≠ 생산 기질 분리
#
# 생산 로더(factor_db_connector.R::load_month_factors)는 C13 정렬된
#   Z_Score_Aligned(단조·부호고정)를 준다 = 다이닝룸(book) 통로.
# 발굴 로더(이 파일)는 ⑤ 정렬 *이전*의 Raw_Value / Z_Score / Z_Sector /
#   Rank_Pct 를 wide(Ticker × Factor) 행렬로 노출한다 = 테스트키친(발굴) 통로.
#   목적: 비단조·상호작용·조건부 구조를 *모델이 보기 전에 붕괴시키지 않음*.
#
# ★ 방화벽 원칙 (discovery ≠ production):
#   이 로더 산출물은 *발굴 전용*이며 자본 자격이 없다. 반드시 검수 게이트
#   (canonical_screen_bt / PORT_t / oos_retention / 기존 span 증분 IR)를 통과한
#   신호만 생산(book)으로 *번역*된다. 이 함수를 book/forge 경로에서 직접 호출 금지.
#
# PIT:
#   factor_db_YYYYMM.parquet 자체가 sig_date PIT 스냅샷이다(빌더가 Factor_Date≤sig_d
#   로 구축). 따라서 파일 단위 선택만으로 누수 없음 — C13 IC-정렬(미래평균 부호)을
#   적용하지 않아도 PIT-safe.
#   ※ C13 미적용은 *의도*다: 방향/비단조성을 모델이 스스로 학습한다. C13의 PIT 목적
#     (전기간 부호 수동flip 금지)은, 발굴 산출이 게이트에서 *forward-return*으로
#     평가되므로 우회가 아니다(부호를 사람이 박는 게 아니라 모델이 OOS로 검증받음).
#
# Functions:
#   load_factors_discovery(sig_date, value, coverage_min, factor_names, wide, universe_tickers)
#   list_discovery_months()
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})
# ※ arrow::set_cpu_count(1)/set_io_thread_count(1) 호출 금지 — 이 머신서 parquet read
#   segfault/HANG 유발(실측 + [[project-ramp-fullcycle-graduation]]). 기본 스레드 유지.

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                              (length(a) == 1L && is.na(a))) b else a
}

# ---- Path resolution (factor_db_connector 와 동일 규약) ----
.disc_self_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
.disc_root <- Sys.getenv("CLAUDE_PROJECT_DIR",
                Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
if (!exists("CACHE_DIR")) {
  cfg <- file.path(.disc_root, "02_Infrastructure", "config.R")
  if (file.exists(cfg)) source(cfg) else CACHE_DIR <- file.path(.disc_root, ".cache")
}
.DISC_FDB_DIR <- file.path(CACHE_DIR, "factor_db")

.VALUE_COLS <- c(raw = "Raw_Value", z = "Z_Score", zsector = "Z_Sector", rank = "Rank_Pct")

#' 사용 가능한 발굴 substrate 월 목록 (YYYYMM)
list_discovery_months <- function() {
  f <- list.files(.DISC_FDB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
  sort(gsub("factor_db_(\\d{6})\\.parquet", "\\1", f))
}

.disc_resolve_path <- function(sig_date) {
  ym <- format(as.Date(sig_date), "%Y%m")
  p <- file.path(.DISC_FDB_DIR, paste0("factor_db_", ym, ".parquet"))
  if (file.exists(p)) return(p)
  avail <- list_discovery_months()
  le <- avail[avail <= ym]
  if (!length(le)) stop("[discovery] No factor_db parquet at or before ", sig_date)
  file.path(.DISC_FDB_DIR, paste0("factor_db_", max(le), ".parquet"))
}

#' 발굴 기질 로드 — C13 정렬 *이전*의 횡단면 값을 노출 (PIT-safe, 비정렬)
#'
#' @param sig_date Date/character. 신호 월.
#' @param value    "raw"(Raw_Value, 기본) / "z"(Z_Score) / "zsector"(Z_Sector) / "rank"(Rank_Pct)
#' @param coverage_min numeric. 팩터별 최소 커버리지(종목 비율) 필터.
#' @param factor_names optional. 특정 팩터만.
#' @param wide      TRUE(기본)=Ticker×Factor wide 행렬, FALSE=long.
#' @param universe_tickers optional character. 투자 유니버스 PIT 멤버십(예: K200∪KQ150).
#'        NULL이면 DB 전체 종목(필터는 게이트/caller 책임).
#' @return wide: data.table(Ticker, <Factor1>, <Factor2>, ...)  / long: (Ticker, Factor_Name, Value)
#'         attr "value_kind", "sig_month", "factor_db_build_hash"
load_factors_discovery <- function(sig_date,
                                   value = "raw",
                                   coverage_min = 0.05,
                                   factor_names = NULL,
                                   wide = TRUE,
                                   universe_tickers = NULL) {
  value <- match.arg(value, names(.VALUE_COLS))
  valcol <- .VALUE_COLS[[value]]
  fpath <- .disc_resolve_path(sig_date)

  cols <- unique(c("Ticker", "Factor_Name", valcol, "Coverage"))
  dt <- as.data.table(read_parquet(fpath, col_select = cols))
  setnames(dt, valcol, "Value")

  # 비정렬: C13 align_factor_direction 호출하지 않음 (의도) — Raw 방향 보존
  if (!is.null(factor_names)) {
    factor_names <- unique(as.character(factor_names))
    dt <- dt[Factor_Name %in% factor_names]
  }
  if (!is.null(universe_tickers)) {
    dt <- dt[Ticker %in% unique(as.character(universe_tickers))]
  }

  # 유효값만
  dt <- dt[Coverage == TRUE & !is.na(Value)]

  # 팩터별 커버리지 필터
  n_tickers <- uniqueN(dt$Ticker)
  if (n_tickers > 0 && coverage_min > 0) {
    cov <- dt[, .(N = .N), by = Factor_Name]
    cov[, Pct := N / n_tickers]
    keep <- cov[Pct >= coverage_min, Factor_Name]
    dt <- dt[Factor_Name %in% keep]
  }
  dt[, Coverage := NULL]

  res <- if (wide) {
    dcast(dt, Ticker ~ Factor_Name, value.var = "Value")
  } else {
    dt[]
  }

  bh_path <- file.path(.DISC_FDB_DIR, "build_hash.txt")
  attr(res, "value_kind") <- value
  attr(res, "sig_month") <- gsub(".*factor_db_(\\d{6})\\.parquet", "\\1", fpath)
  attr(res, "factor_db_build_hash") <- if (file.exists(bh_path))
    tryCatch(readLines(bh_path, n = 1L), error = function(e) "unknown") else "unknown"
  attr(res, "discovery_substrate") <- TRUE   # 자본 게이트 미경유 표식
  res
}

cat("[discovery_loader] Loaded. load_factors_discovery() — pre-C13 발굴 기질 (방화벽: 게이트 전 자본 사용 금지)\n")
