#==============================================================================
# Factor DB Connector — Factor DB → Architecture Bridge
#
# Connects the Factor DB (monthly long parquets, .cache/factor_db/) to the
# regime-conditional factor allocation engine.
# Factor counts vary by month — 고정 "N factors" 표기 금지 (2026-06-10 실측:
#   registry 373 등록 / 월간 parquet distinct 342 (최신월 202605 = 315) /
#   IC history 327 / 일간 DB 304).
# Registry 제안(미백필, open item): entry별 "storage" 필드(monthly/daily/both)
#   — 신규 등재 2건(AC14_Discretionary_Accruals, XF_Q06_Op_Margin)에만 시범 도입.
#
# Functions:
#   load_month_factors(sig_date, coverage_min, factor_names)
#   load_daily_factors(ym | date_range, factors, align_direction)   [v2.3 — C15 daily 관문]
#   compute_rolling_ic_all(sig_date, min_months, max_months)
#   group_factors_by_family(registry)
#   align_factor_direction(factor_dt, registry)
#
# PIT: All functions use data available at or before sig_date only.
# v2.0 (L-168 fix): align_factor_direction() uses Usable_Date <= sig_date
#   for IC-based direction inference (expanding window, 36-month burn-in).
#   Backward compatible: sig_date=NULL triggers registry-only safe default.
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
  library(dplyr)
  library(jsonlite)
})

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                              (length(a) == 1L && is.na(a))) b else a
}

# ---- Paths ----
.fdc_self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FACTOR_DB_DIR")) FACTOR_DB_DIR
    else if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db")
    else file.path(
      Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")),
      "02_Infrastructure", "factor_db"
    )
  }
)

if (!exists("CACHE_DIR")) {
  source(file.path(dirname(.fdc_self_dir), "config.R"))
}

FACTOR_DB_DIR <- file.path(CACHE_DIR, "factor_db")
FACTOR_DB_DAILY_DIR <- file.path(CACHE_DIR, "factor_db_daily")
FACTOR_IC_MONTHLY_PATH <- file.path(FACTOR_DB_DIR, "factor_ic_monthly.parquet")
FACTOR_REG_PATH <- file.path(FACTOR_DB_DIR, "factor_registry.json")

# ---- Load registry (cached) ----
.fdc_registry <- NULL

.load_registry <- function() {
  if (!is.null(.fdc_registry)) return(.fdc_registry)

  # Try multiple paths
  candidates <- c(
    file.path(FUNC_PATH, "factor_db", "factor_registry.json"),
    file.path(.fdc_self_dir, "factor_registry.json"),
    FACTOR_REG_PATH
  )
  reg_path <- NULL
  for (p in candidates) {
    if (file.exists(p)) { reg_path <- p; break }
  }
  if (is.null(reg_path)) {
    cat("[connector] WARNING: factor_registry.json not found in any candidate path\n")
    return(list())
  }
  .fdc_registry <<- fromJSON(reg_path)
  .fdc_registry
}

# ---- de-dup 소비 배선 (2026-08-09) --------------------------------------------
# registry 의 dedup 선언을 **행동으로** 잇는 지점. 라벨만 있고 소비자가 0이면
# 선언된 중복은 선별·Ω 추정에서 계속 이중 투표한다(2026-08-09 실측: 표본 6월
# 전건에서 선언 cluster 44개·224쌍이 같은 풀에 동시 출현, 초과 표 82~83 = 풀의 ~25%).
#
# ★기본 동작 무변경 원칙: 모든 진입점의 dedup 기본값은 FALSE 다. 인자 없이 부르면
#   기존과 **값이 동일**하다. 정본 해석은 명시 opt-in(dedup=TRUE)으로만 일어난다.
#   대신 접을 수 있는 alias 가 풀에 있는데 접지 않은 경우 **세션당 1회** 알린다
#   (매 호출 경고는 소음이 되어 무시된다 — emission_guard 설계원칙 ②).
.fdc_dedup_notified <- FALSE

.fdc_dedup_available <- function() {
  if (exists("collapse_alias_rows", mode = "function")) return(TRUE)
  p <- file.path(.fdc_self_dir, "factor_dup_scan.R")
  if (!file.exists(p)) return(FALSE)
  source(p)
  exists("collapse_alias_rows", mode = "function")
}

#' dedup=TRUE 요청을 처리한다. API 를 못 찾으면 **fail-closed** — 조용히
#' 미적용 데이터를 돌려주면 "요청했으니 됐겠지"가 되어 결손이 정상값으로
#' 내려앉는다. 그래서 stop() 한다.
.fdc_apply_dedup <- function(dt, dedup, what = "panel") {
  if (!isTRUE(dedup)) return(dt)
  if (!.fdc_dedup_available()) {
    stop("[connector] dedup=TRUE 인데 factor_dup_scan.R 의 collapse_alias_rows() 를 ",
         "로드할 수 없다 — 정본 해석 없이 반환하지 않는다(fail-closed). 경로: ",
         file.path(.fdc_self_dir, "factor_dup_scan.R"))
  }
  collapse_alias_rows(dt, registry = .load_registry())
}

# alias -> canonical 지도는 세션당 1회만 만든다 (매 호출 registry 순회 방지).
.fdc_alias_map <- NULL
.fdc_get_alias_map <- function() {
  if (!is.null(.fdc_alias_map)) return(.fdc_alias_map)
  reg <- .load_registry()
  m <- vapply(reg, function(e) {
    d <- e$dedup
    if (is.null(d) || !identical(as.character(d$role)[1], "alias") ||
        is.null(d$canonical)) NA_character_ else as.character(d$canonical)[1]
  }, character(1))
  .fdc_alias_map <<- m[!is.na(m)]
  .fdc_alias_map
}

#' dedup 을 끈 채로 접을 수 있는 alias 가 풀에 있으면 세션당 1회 알린다.
.fdc_dedup_notice <- function(factor_names) {
  if (.fdc_dedup_notified) return(invisible(NULL))
  if (identical(Sys.getenv("QVEST_DEDUP_NOTICE"), "0")) return(invisible(NULL))
  amap <- .fdc_get_alias_map()
  if (!length(amap)) return(invisible(NULL))
  fn <- unique(as.character(factor_names))
  cand <- intersect(names(amap), fn)
  al <- cand[amap[cand] %in% fn]
  if (!length(al)) return(invisible(NULL))
  .fdc_dedup_notified <<- TRUE
  cat(sprintf(paste0("[connector] NOTE: 이 풀에 정본과 함께 등재된 alias %d종이 있다",
                     " (%s). 선별/Ω 추정이면 dedup=TRUE 로 접을 것 — 기본값은 무변경",
                     "(FALSE)이라 지금은 중복 투표한다. 이 알림은 세션당 1회.\n"),
              length(al), paste(al, collapse = ", ")))
  invisible(NULL)
}

# ---- IC history (cached) ----
.fdc_ic_hist <- NULL
.fdc_ic_dir_cache <- new.env(parent = emptyenv())

.load_ic_history <- function() {
  if (!is.null(.fdc_ic_hist)) return(.fdc_ic_hist)
  if (!file.exists(FACTOR_IC_MONTHLY_PATH)) {
    stop("[connector] factor_ic_monthly.parquet not found. Run compute_all_factor_ic_monthly() first.")
  }
  # v2.1: col_select — N_Stocks 미사용. any_of()로 Usable_Date 부재 legacy 파일 호환 유지.
  .fdc_ic_hist <<- as.data.table(read_parquet(
    FACTOR_IC_MONTHLY_PATH,
    col_select = tidyselect::any_of(c("Factor_Name", "IC", "Date", "Usable_Date"))
  ))
  .fdc_ic_hist[, Date := as.Date(Date)]
  # v2.0 (L-168): ensure Usable_Date is also Date type for consistent filtering
  if ("Usable_Date" %in% names(.fdc_ic_hist)) {
    .fdc_ic_hist[, Usable_Date := as.Date(Usable_Date)]
  }
  .fdc_ic_hist
}

.ic_direction_cache_path <- function(sig_d, min_ic_months) {
  info <- tryCatch(file.info(FACTOR_IC_MONTHLY_PATH), error = function(e) NULL)
  stamp <- "noic"
  size_tag <- "0"
  if (!is.null(info) && nrow(info) > 0 && !is.na(info$mtime[1])) {
    stamp <- format(as.POSIXct(info$mtime[1]), "%Y%m%d%H%M%S")
    size_tag <- as.character(info$size[1] %||% 0)
  }
  cache_dir <- file.path(FACTOR_DB_DIR, "ic_direction_cache_v1")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  file.path(
    cache_dir,
    sprintf("ic_dir_%s_m%d_%s_%s.rds",
            format(as.Date(sig_d), "%Y%m%d"), as.integer(min_ic_months),
            stamp, size_tag)
  )
}

.load_ic_direction_cached <- function(sig_d, min_ic_months = 36L) {
  sig_d <- as.Date(sig_d)
  cache_key <- sprintf("%s_m%d", format(sig_d, "%Y%m%d"), as.integer(min_ic_months))
  if (exists(cache_key, envir = .fdc_ic_dir_cache, inherits = FALSE)) {
    return(get(cache_key, envir = .fdc_ic_dir_cache, inherits = FALSE))
  }

  cache_path <- .ic_direction_cache_path(sig_d, min_ic_months)
  if (file.exists(cache_path)) {
    cached <- tryCatch(readRDS(cache_path), error = function(e) NULL)
    if (is.data.table(cached) && all(c("Factor_Name", "ic_sign") %in% names(cached))) {
      assign(cache_key, cached, envir = .fdc_ic_dir_cache)
      return(cached)
    }
  }

  ic_hist <- tryCatch(.load_ic_history(), error = function(e) NULL)
  if (is.null(ic_hist) || nrow(ic_hist) == 0) return(NULL)

  if ("Usable_Date" %in% names(ic_hist)) {
    ic_avail <- ic_hist[Usable_Date <= sig_d]
  } else {
    cat("[WARN] align_factor_direction: factor_ic_monthly.parquet missing Usable_Date. Using Date < sig_d (legacy).\n")
    ic_avail <- ic_hist[Date < sig_d]
  }
  if (nrow(ic_avail) == 0) return(NULL)

  ic_dir <- ic_avail[, {
    n <- .N
    if (n >= min_ic_months) {
      m <- mean(IC, na.rm = TRUE)
      list(Mean_IC = m, ic_sign = fifelse(m >= 0, 1L, -1L), N_IC = n)
    } else {
      list(Mean_IC = NA_real_, ic_sign = NA_integer_, N_IC = n)
    }
  }, by = Factor_Name]

  tmp <- sprintf("%s.%s.tmp", cache_path, Sys.getpid())
  tryCatch({
    saveRDS(ic_dir, tmp)
    if (!file.rename(tmp, cache_path) && !file.exists(cache_path)) {
      file.copy(tmp, cache_path, overwrite = FALSE)
    }
    if (file.exists(tmp)) unlink(tmp)
  }, error = function(e) {
    if (file.exists(tmp)) unlink(tmp)
    NULL
  })

  assign(cache_key, ic_dir, envir = .fdc_ic_dir_cache)
  ic_dir
}


#==============================================================================
# 1. load_month_factors()
#==============================================================================

#' Load factor DB for a signal date with coverage filter + direction alignment.
#' @param sig_date Date or character. Signal date (monthly)
#' @param coverage_min Numeric. Min coverage fraction to include factor (0-1)
#' @param factor_names Optional character vector. If supplied, only these factor
#'   names are direction-aligned and returned. This preserves C15 because the
#'   caller still uses the PIT-safe connector rather than reading parquet
#'   directly.
#' @return data.table: Ticker, Factor_Name, Z_Score_Aligned (higher=better).
#'   attr "factor_db_asof_date" = 반환 패널의 실제 계산 기준일(월 파일 Date 컬럼 =
#'   해당 월 **거래일** 말일). 요청 sig_date 와 다를 수 있다 —
#'     (a) 캘린더 월말로 요청했는데 거래말이 더 이르다 (실측 36% 월),
#'     (b) 해당 월 파일 부재로 closest-earlier 파일이 대체 로드됐다.
#'   행 라벨(Date)이 필요한 소비자는 이 attribute 를 쓰고 요청일로 **합성하지 말 것**
#'   (합성 시 거래일 월말 그리드와 어긋나 AS_OF 조인이 전월값을 당김 — 2026-08-02
#'   ast_compile factor_db_monthly provider 1개월 stale 사건).
#'   attr "factor_db_asof_date" 는 로드 실패/0행 시 NA — 소비자는 fail-closed 처리.
#' @param dedup Logical (기본 FALSE = 기존 동작과 값 동일). TRUE 면 registry
#'   dedup 선언에 따라 **alias 행을 접는다** — canonical 이 같은 패널에 있을 때만
#'   제거하고, 없으면 alias 를 그대로 남긴다(개명하지 않는다: 그 달 배출되지 않은
#'   코드를 날조하지 않기 위해). 반환값 attribute `dedup_dropped` /
#'   `dedup_orphan_alias` / `dedup_redundant` 에 무엇을 했는지 전부 노출된다.
#'   ★선별·랭킹·Ω 추정에 쓰는 풀이면 TRUE 를 권장한다. 단순 조회·재현은 FALSE.
load_month_factors <- function(sig_date, coverage_min = 0.05, factor_names = NULL,
                               dedup = FALSE) {
  sig_d <- as.Date(sig_date)
  ym_tag <- format(sig_d, "%Y%m")
  fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", ym_tag, ".parquet"))

  if (!file.exists(fpath)) {
    # Find closest available month
    avail <- list.files(FACTOR_DB_DIR, pattern = "^factor_db_\\d{6}\\.parquet$")
    ym_avail <- gsub("factor_db_(\\d{6})\\.parquet", "\\1", avail)
    ym_avail <- sort(ym_avail)
    closest <- max(ym_avail[ym_avail <= ym_tag])
    if (is.na(closest)) stop("[connector] No factor DB available for ", sig_date)
    fpath <- file.path(FACTOR_DB_DIR, paste0("factor_db_", closest, ".parquet"))
  }

  if (!is.null(factor_names)) {
    factor_names <- unique(as.character(factor_names))
    factor_names <- factor_names[nzchar(factor_names)]
  }

  # v2.2: when caller requests specific factors, push the Factor_Name filter
  # through Arrow before collect(). This keeps the PIT-safe connector boundary
  # while avoiding full monthly factor DB materialization for combo runners.
  # v2.4: Date 는 **선택(any_of)**, 나머지는 필수(all_of). 구 vintage 파케이가 Date 를
  # 안 담고 있어도 로드는 살고, as-of 만 NA 로 정직하게 결손 보고된다(소비자 fail-closed).
  # 필수 컬럼에 any_of 를 쓰면 결손이 조용히 통과하므로 섞지 않는다.
  .req_cols <- c("Ticker", "Factor_Name", "Z_Score", "Coverage")
  dt <- if (!is.null(factor_names) && length(factor_names)) {
    as.data.table(
      open_dataset(fpath, format = "parquet") %>%
        select(all_of(.req_cols), any_of("Date")) %>%
        filter(Factor_Name %in% factor_names) %>%
        collect()
    )
  } else {
    # v2.1: col_select — only columns needed downstream (Coverage filter + direction
    # alignment). Raw_Value/Z_Sector/Rank_Pct unused here → IO/메모리 절감.
    # v2.4: Date 재포함 — 패널 as-of(실제 vintage) 보고용. 월당 단일값 date32 라
    # IO 비용 실측 무의미(콜드 139→150ms/file, 웜 역전 — 측정 오차 내), 대신
    # 소비자의 라벨 합성을 없앤다.
    as.data.table(read_parquet(
      fpath,
      col_select = c(all_of(.req_cols), any_of("Date"))
    ))
  }

  # v2.4 (2026-08-02): 패널 as-of = 월 파일의 Date 컬럼(빌더가 기록한 계산 기준일 =
  # 거래일 월말). 필터 이전 값으로 확정한다 — coverage/factor 필터로 0행이 돼도
  # "요청일로 되돌아가는" 침묵 대체가 생기지 않도록.
  asof_date <- if ("Date" %in% names(dt) && nrow(dt) > 0L) {
    max(as.Date(dt$Date), na.rm = TRUE)
  } else {
    as.Date(NA)
  }

  # Coverage filter: exclude factors with too few stocks.
  # v2.1: N_Covered = Coverage & !is.na(Z_Score) — 시장레벨 dead 팩터(RE*/MA05-07/
  # M31_Breadth_Mom/CR03 등)는 Z 전부 NA인데 Coverage=TRUE 전행이라 구 sum(Coverage)
  # 집계가 필터를 무력화했음. 빌더 Coverage 재정의와 이중 방어 (구 parquet에도 즉효).
  n_tickers <- uniqueN(dt$Ticker)
  factor_cov <- dt[, .(N_Covered = sum(Coverage == TRUE & !is.na(Z_Score))), by = Factor_Name]
  factor_cov[, Pct := N_Covered / n_tickers]
  keep_factors <- factor_cov[Pct >= coverage_min, Factor_Name]

  dt <- dt[Factor_Name %in% keep_factors & Coverage == TRUE & !is.na(Z_Score)]

  # Direction alignment (v2.0 PIT-safe: pass sig_date for expanding IC window)
  registry <- .load_registry()
  dt <- align_factor_direction(dt, registry, sig_date = sig_d)

  result <- dt[, .(Ticker, Factor_Name, Z_Score_Aligned)]

  # de-dup 소비 (기본 FALSE = 무변경). collapse_alias_rows() 가 자기 attribute
  # (dedup_dropped/dedup_orphan_alias/dedup_redundant)를 붙이고, 아래에서 factor_db
  # attribute 를 덧붙인다 — 둘 다 보존된다.
  if (isTRUE(dedup)) {
    result <- .fdc_apply_dedup(result, TRUE, "load_month_factors")
  } else {
    .fdc_dedup_notice(unique(result$Factor_Name))
  }

  # v54 Gate 13.1 — attach build hash for traceability
  build_hash_path <- file.path(FACTOR_DB_DIR, "build_hash.txt")
  build_hash <- if (file.exists(build_hash_path)) {
    tryCatch(readLines(build_hash_path, n = 1L), error = function(e) "unknown")
  } else {
    "unknown"
  }
  attr(result, "factor_db_build_hash") <- build_hash
  attr(result, "factor_db_asof_date") <- asof_date
  attr(result, "factor_db_file") <- basename(fpath)

  result
}


#==============================================================================
# 1b. load_daily_factors()  [v2.3, 2026-07-25 — AST v1.1 §3 불변식 ⑥ C15 carve-out 해소]
#==============================================================================

#' Load daily factor DB (fdb_daily_YYYYMM.parquet) through the PIT-safe connector.
#'
#' 일간 팩터 DB 전용 관문 — .cache/factor_db_daily/ parquet 직접 read 금지(C15)의
#' 일간 등가. 월간 load_month_factors()와의 구조 차이(정의 차이 — 실측 2026-07-25):
#'   * 스키마: 일간 DB = WIDE (Date, Ticker, 팩터 1열씩. 202607 = 318 cols /
#'     199001 = 277 cols — 초기 vintage는 컨센서스·수급 등 부재, unify로 NA 채움).
#'     월간 DB = LONG (Ticker, Factor_Name, Z_Score, Coverage).
#'   * 값 semantics: 일간 = **winsorized RAW value** (phase10: 날짜별 1%/99% cap,
#'     SKIP 컬럼 예외 — S01_Size/L26_Log_MktCap/PTR·RE_* 등은 미캡). 월간 = 횡단면
#'     Z_Score. 따라서 본 함수의 방향정렬은 부호 flip만 수행하며(순서 보존),
#'     팩터 간 결합 전 횡단면 표준화는 caller 책임.
#'   * Coverage 컬럼 부재 — coverage 필터 없음 (NA가 곧 미커버).
#'
#' C13 방향정렬: align_direction=TRUE 시 **월간 ic_sign 경로 재사용**
#'   (.load_ic_direction_cached — factor_ic_monthly.parquet의 Usable_Date <=
#'   pit_max expanding window, 36개월 burn-in, registry fallback). 일간 IC 패널
#'   (analysis/daily_ic_panel 계열)은 Usable_Date 체계가 없어 PIT-safe 방향추론에
#'   쓸 수 없음 — 한계로 문서화하고 월간 ic_sign을 적용한다 (방향은 저빈도
#'   속성이라 월간 추론으로 충분하다는 가정, 명시 라벨).
#'
#' PIT: 반환 전 Date <= pit_max(요청 상한) 하드 강제. ic_sign 추론도 동일
#'   pit_max 기준 expanding window (미래 IC 미참조).
#'
#' ⚠ Incremental parity caveat (memory: project-fdb-daily-incremental-parity,
#'   2026-07-18): update_daily_fdb(ym) 단일월 증분 재빌드는 전량 재빌드와
#'   bit-parity가 아님 — rcpp 롤링 누산이 경로-의존 (실측: R13_NCSKEW 증분 0 vs
#'   전량 9.87e9 급 괴리 사례). 횡단면 rank는 290/298 팩터 보존. 도훈 채택 A
#'   (caveat 유지 + AUTOREBUILD ON). 즉 증분 갱신월의 누산계열 팩터
#'   (R13_NCSKEW 등)는 값-레벨 재현성을 보장하지 않음 — rank 기반 소비 권장.
#'
#' @param ym Character/numeric vector. "YYYYMM" 월 태그 (예: c("202606","202607")).
#'   date_range와 택일 (둘 다 주면 ym 우선 + date_range로 행 필터).
#' @param date_range Date/character length-2. c(start, end) — 해당 구간이 걸치는
#'   월 파일만 로드 (전체 441파일 스캔 금지, Arrow dataset column/row pushdown).
#' @param factors Optional character vector. 팩터 컬럼명 선택 (NULL = 전 팩터).
#'   스키마에 없는 요청은 WARN 후 제외.
#' @param align_direction Logical. TRUE(기본) = C13 방향정렬 (value * ic_sign,
#'   higher = better). ic_sign map은 attr "ic_sign_map"으로 첨부.
#' @return data.table (wide): Date, Ticker, <factor cols>. attrs:
#'   pit_max / months_loaded / value_semantics / direction_aligned /
#'   ic_sign_map (정렬 시) / fdb_daily_registry_version
load_daily_factors <- function(ym = NULL, date_range = NULL, factors = NULL,
                               align_direction = TRUE) {
  if (is.null(ym) && is.null(date_range)) {
    stop("[load_daily_factors] ym 또는 date_range 중 하나는 필수입니다.")
  }

  # ---- Resolve months + PIT upper bound ----
  d_lo <- NULL; d_hi <- NULL
  if (!is.null(date_range)) {
    if (length(date_range) != 2L) stop("[load_daily_factors] date_range는 c(start, end) length-2.")
    d_lo <- as.Date(date_range[1]); d_hi <- as.Date(date_range[2])
    if (is.na(d_lo) || is.na(d_hi) || d_lo > d_hi) {
      stop("[load_daily_factors] date_range 파싱 실패 또는 start > end.")
    }
  }
  if (!is.null(ym)) {
    ym_tags <- sort(unique(sprintf("%06d", as.integer(as.character(ym)))))
    if (any(!grepl("^\\d{6}$", ym_tags))) stop("[load_daily_factors] ym은 YYYYMM 형식.")
  } else {
    mseq <- seq(as.Date(format(d_lo, "%Y-%m-01")),
                as.Date(format(d_hi, "%Y-%m-01")), by = "month")
    ym_tags <- format(mseq, "%Y%m")
  }

  # PIT 상한: date_range 상한 우선, 없으면 최대 요청월의 말일
  pit_max <- if (!is.null(d_hi)) d_hi else {
    last_ym <- max(ym_tags)
    first_next <- as.Date(paste0(last_ym, "01"), format = "%Y%m%d")
    seq(first_next, by = "month", length.out = 2L)[2L] - 1L
  }

  # ---- File resolution (요청 월만 — 전체 스캔 금지) ----
  fpaths <- file.path(FACTOR_DB_DAILY_DIR, paste0("fdb_daily_", ym_tags, ".parquet"))
  missing_f <- !file.exists(fpaths)
  if (all(missing_f)) {
    stop("[load_daily_factors] 요청 월 parquet 전무: ",
         paste(ym_tags, collapse = ", "), " (dir=", FACTOR_DB_DAILY_DIR, ")")
  }
  if (any(missing_f)) {
    cat(sprintf("[load_daily_factors] WARN: %d개 월 파일 부재 — 제외: %s\n",
                sum(missing_f), paste(ym_tags[missing_f], collapse = ", ")))
    fpaths <- fpaths[!missing_f]; ym_tags <- ym_tags[!missing_f]
  }

  # ---- Arrow dataset: column + row pushdown (unify_schemas — vintage별 열 차이) ----
  ds <- open_dataset(fpaths, format = "parquet", unify_schemas = TRUE)
  all_cols <- names(ds)
  fac_avail <- setdiff(all_cols, c("Date", "Ticker"))

  if (!is.null(factors)) {
    factors <- unique(as.character(factors)); factors <- factors[nzchar(factors)]
    not_found <- setdiff(factors, fac_avail)
    if (length(not_found)) {
      cat(sprintf("[load_daily_factors] WARN: 스키마 부재 팩터 %d건 제외: %s\n",
                  length(not_found), paste(not_found, collapse = ", ")))
    }
    sel_facs <- intersect(factors, fac_avail)
    if (!length(sel_facs)) stop("[load_daily_factors] 요청 팩터가 스키마에 하나도 없습니다.")
  } else {
    sel_facs <- fac_avail
  }

  q <- ds %>% select(tidyselect::all_of(c("Date", "Ticker", sel_facs)))
  # row pushdown: PIT 상한 (+ 하한이 있으면 함께)
  q <- q %>% filter(Date <= pit_max)
  if (!is.null(d_lo)) q <- q %>% filter(Date >= d_lo)
  dt <- as.data.table(collect(q))
  dt[, Date := as.Date(Date)]

  # ---- PIT hard enforcement (반환 전 재확인 — pushdown 실패 대비 이중 방어) ----
  n_viol <- dt[Date > pit_max, .N]
  if (n_viol > 0L) {
    cat(sprintf("[load_daily_factors] PIT: Date > %s %d행 제거 (pushdown 미적용분)\n",
                pit_max, n_viol))
    dt <- dt[Date <= pit_max]
  }

  # ---- C13 direction alignment (월간 ic_sign 경로 재사용) ----
  ic_sign_map <- NULL
  if (isTRUE(align_direction) && nrow(dt) > 0L) {
    ic_dir <- .load_ic_direction_cached(pit_max, min_ic_months = 36L)
    registry <- .load_registry()
    reg_sign <- if (!is.null(registry) && length(registry)) {
      data.table(
        Factor_Name = names(registry),
        sign = sapply(registry, function(x) {
          d <- x$direction %||% "higher_better"
          if (identical(d, "lower_better")) -1L else 1L
        }),
        src = "registry"
      )
    } else NULL

    ic_sign_map <- data.table(Factor_Name = sel_facs, sign = 1L, src = "default")
    if (!is.null(reg_sign)) {
      ic_sign_map[reg_sign, on = "Factor_Name", `:=`(sign = i.sign, src = i.src)]
    }
    if (!is.null(ic_dir) && nrow(ic_dir[!is.na(ic_sign)])) {
      ic_sign_map[ic_dir[!is.na(ic_sign)], on = "Factor_Name",
                  `:=`(sign = i.ic_sign, src = "ic")]
    }
    flip <- ic_sign_map[sign == -1L, Factor_Name]
    if (length(flip)) {
      dt[, (flip) := lapply(.SD, function(x) -x), .SDcols = flip]
    }
    cat(sprintf(
      "[load_daily_factors] C13 정렬(월간 ic_sign 재사용, pit_max=%s): IC=%d / registry=%d / default=%d | flip=%d\n",
      pit_max, ic_sign_map[src == "ic", .N], ic_sign_map[src == "registry", .N],
      ic_sign_map[src == "default", .N], length(flip)))
    if (ic_sign_map[src == "default", .N] > 0L) {
      .dnames <- ic_sign_map[src == "default", Factor_Name]
      cat(sprintf("[load_daily_factors] WARN: IC/registry 부재 %d열 — sign=+1 가정 (PTR/RE_* 시장레벨 열 포함 가능): %s%s\n",
                  length(.dnames), paste(head(.dnames, 8L), collapse = ", "),
                  if (length(.dnames) > 8L) sprintf(" ... (+%d)", length(.dnames) - 8L) else ""))
    }
  }

  # ---- Attrs ----
  reg_path <- file.path(FACTOR_DB_DAILY_DIR, "factor_db_daily_registry.json")
  reg_ver <- if (file.exists(reg_path)) {
    tryCatch({ r <- fromJSON(reg_path); paste0(r$version %||% "?", "@", r$created %||% "?") },
             error = function(e) "unknown")
  } else "unknown"
  setattr(dt, "pit_max", pit_max)
  setattr(dt, "months_loaded", ym_tags)
  setattr(dt, "value_semantics", "winsorized_raw (NOT z-score — 횡단면 표준화는 caller 책임)")
  setattr(dt, "direction_aligned", isTRUE(align_direction))
  if (!is.null(ic_sign_map)) setattr(dt, "ic_sign_map", ic_sign_map)
  setattr(dt, "fdb_daily_registry_version", reg_ver)

  cat(sprintf("[load_daily_factors] %d행 x %d팩터 | %s~%s | months=%s\n",
              nrow(dt), length(sel_facs),
              if (nrow(dt)) format(min(dt$Date)) else "NA",
              if (nrow(dt)) format(max(dt$Date)) else "NA",
              paste(ym_tags, collapse = ",")))
  dt
}


#==============================================================================
# 2. align_factor_direction()
#==============================================================================

#' Flip factor z-scores so higher = better for all factors.
#'
#' v2.0 PIT-SAFE (L-168 fix): When sig_date is provided, uses ONLY IC history
#' with Usable_Date <= sig_date (expanding window). This ensures no future IC
#' information leaks into direction inference. Matches compute_rolling_ic_all()
#' PIT treatment (line 220-230 of this file).
#'
#' Logic: IC = corr(Raw_Value, Forward_Return)
#'   If expanding mean IC > 0 → higher Raw_Value = higher return → Z_Aligned = Z_Score
#'   If expanding mean IC < 0 → higher Raw_Value = lower return → Z_Aligned = -Z_Score
#'   If IC unknown or insufficient → fall back to registry direction
#'
#' Backward compatibility: sig_date=NULL triggers registry-only mode (safe default).
#'
#' @param factor_dt data.table with Factor_Name, Z_Score columns
#' @param registry Parsed factor_registry.json (fallback / primary when no sig_date)
#' @param sig_date Date or character. Signal date for PIT-safe IC filtering (default: NULL)
#' @param min_ic_months Integer. Minimum IC observations for direction inference (default: 36)
#' @return factor_dt with Z_Score_Aligned column added
align_factor_direction <- function(factor_dt, registry, sig_date = NULL, min_ic_months = 36L) {

  # ---- Registry-based direction map (always computed as fallback) ----
  reg_dir <- NULL
  if (!is.null(registry) && length(registry) > 0) {
    reg_dir <- data.table(
      Factor_Name = names(registry),
      reg_sign = sapply(registry, function(x) {
        d <- x$direction %||% "higher_better"
        if (d == "lower_better") -1L else 1L
      })
    )
  }

  # ---- IC-based direction: PIT-safe expanding window ----
  ic_dir <- NULL

  if (!is.null(sig_date)) {
    sig_d <- as.Date(sig_date)
    ic_dir <- .load_ic_direction_cached(sig_d, min_ic_months)
    if (!is.null(ic_dir) && nrow(ic_dir) > 0) {
      # v2.1: 구 로그(IC-history 전체 기준 카운트) 제거 — 로드된 팩터 기준
      # 집계로 대체 (merge 이후 하단). IC-history에 아예 없는 팩터(구 73건)가
      # 로그에 비가시화되던 문제 해소.
      cat(sprintf("[align_factor_direction] PIT-safe: sig_date=%s | min_months=%d\n",
                  sig_d, min_ic_months))
    }
  } else {
    # No sig_date: registry-only mode (backward compatible, PIT-safe by construction)
    cat("[align_factor_direction] No sig_date provided — registry-only direction (PIT-safe default).\n")
  }

  # ---- Merge direction into factor_dt (v2.1: per-factor source tracking) ----
  if (!is.null(ic_dir) && nrow(ic_dir[!is.na(ic_sign)]) > 0) {
    # Primary: IC-based direction (PIT-filtered)
    factor_dt <- merge(factor_dt, ic_dir[, .(Factor_Name, ic_sign)],
                       by = "Factor_Name", all.x = TRUE)
    factor_dt[, dir_source := fifelse(is.na(ic_sign), NA_character_, "ic")]

    # Secondary fallback: registry direction for factors without sufficient IC
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir, by = "Factor_Name", all.x = TRUE)
      factor_dt[is.na(ic_sign) & !is.na(reg_sign), dir_source := "registry"]
      factor_dt[is.na(ic_sign), ic_sign := reg_sign]
      factor_dt[, reg_sign := NULL]
    }

    # Tertiary fallback: default higher_better — WARN emitted below (v2.1)
    factor_dt[is.na(ic_sign), `:=`(ic_sign = 1L, dir_source = "default")]
  } else {
    # Registry-only path (no IC available or no sig_date)
    if (!is.null(reg_dir)) {
      factor_dt <- merge(factor_dt, reg_dir[, .(Factor_Name, ic_sign = reg_sign)],
                         by = "Factor_Name", all.x = TRUE)
      factor_dt[, dir_source := fifelse(is.na(ic_sign), NA_character_, "registry")]
      factor_dt[is.na(ic_sign), `:=`(ic_sign = 1L, dir_source = "default")]
    } else {
      factor_dt[, `:=`(ic_sign = 1L, dir_source = "default")]
    }
  }

  # ---- v2.1 direction-source log: LOADED-factor 기준 (IC-history 전체 아님) ----
  .src_per_factor <- factor_dt[, .(src = dir_source[1L]), by = Factor_Name]
  n_dir_ic  <- .src_per_factor[src == "ic", .N]
  n_dir_reg <- .src_per_factor[src == "registry", .N]
  n_dir_def <- .src_per_factor[src == "default", .N]
  cat(sprintf("[align_factor_direction] loaded-factor direction: IC-inferred=%d / registry-fallback=%d / default-fallback=%d (n_factors=%d)\n",
              n_dir_ic, n_dir_reg, n_dir_def, n_dir_ic + n_dir_reg + n_dir_def))
  if (n_dir_def > 0) {
    .def_names <- sort(.src_per_factor[src == "default", Factor_Name])
    cat(sprintf("[align_factor_direction] WARN: %d factor(s) in neither IC history nor registry — defaulted ic_sign=1 (higher_better 가정): %s%s\n",
                n_dir_def,
                paste(head(.def_names, 10L), collapse = ", "),
                if (length(.def_names) > 10L) sprintf(" ... (+%d more)", length(.def_names) - 10L) else ""))
  }
  factor_dt[, dir_source := NULL]

  # Apply direction: Z_Score_Aligned = Z_Score * ic_sign
  # This ensures higher Z_Score_Aligned = higher expected return for ALL factors
  factor_dt[, Z_Score_Aligned := Z_Score * ic_sign]
  factor_dt[, ic_sign := NULL]

  # RC1 fix: re-standardize to sd=1 after direction flip (winsorize in builder may leave sd!=1)
  # Prevents M08 +1761% / R12=D01 +1316% / R16 +529% distortion (Scout 9/12 CRITICAL finding)
  factor_dt[!is.na(Z_Score_Aligned), Z_Score_Aligned := {
    s <- sd(Z_Score_Aligned, na.rm = TRUE)
    if (!is.na(s) && s > 1e-12) Z_Score_Aligned / s else Z_Score_Aligned
  }, by = Factor_Name]

  factor_dt
}


#==============================================================================
# 3. compute_rolling_ic_all()
#==============================================================================

#' Compute expanding-window IC and ICIR for all factors up to sig_date.
#' PIT ENFORCED: Uses Usable_Date column — IC[t] is only usable after t+1.
#' IC[t] = corr(factor[t], return[t→t+1]), so we need Usable_Date <= sig_date.
#'
#' @param sig_date Date. Current signal date
#' @param min_months Integer. Min months for valid ICIR (default 36)
#' @param max_months Integer. Max lookback months (default 120)
#' @param dedup Logical (기본 FALSE = 무변경). TRUE 면 반환 표에서 alias 행을
#'   접는다. ★이 표는 ICIR 랭킹의 입력이다 — alias 를 두면 같은 신호가 상위
#'   K 자리를 두 번 차지하고 ICIR 가중합에서도 두 번 계산된다
#'   (소비자: alpha_search/fe_factor_momentum.R, regime_factor_alloc_engine.R,
#'    factor_research_pipeline.R). 랭킹·가중에 쓰면 TRUE 권장.
#' @return data.table: Factor_Name, Mean_IC, ICIR, Hit_Rate, N_Months
compute_rolling_ic_all <- function(sig_date, min_months = 36L, max_months = 120L,
                                   dedup = FALSE) {
  sig_d <- as.Date(sig_date)
  ic_hist <- .load_ic_history()

  # PIT ENFORCED: use Usable_Date if available, otherwise Date < sig_d (2-month safety)
  if ("Usable_Date" %in% names(ic_hist)) {
    ic_avail <- ic_hist[Usable_Date <= sig_d]
  } else {
    # Legacy fallback: Date < sig_d excludes current month's IC
    # But this still has 1-month lookahead risk — warn
    cat("[WARN] factor_ic_monthly.parquet missing Usable_Date. Using Date < sig_d (legacy).\n")
    ic_avail <- ic_hist[Date < sig_d]
  }

  if (nrow(ic_avail) == 0) {
    return(data.table(Factor_Name = character(), Mean_IC = numeric(),
                      ICIR = numeric(), Hit_Rate = numeric(), N_Months = integer()))
  }

  # Limit lookback
  if (max_months < Inf) {
    cutoff <- sort(unique(ic_avail$Date), decreasing = TRUE)
    if (length(cutoff) > max_months) {
      cutoff_date <- cutoff[max_months]
      ic_avail <- ic_avail[Date >= cutoff_date]
    }
  }

  # Compute ICIR per factor
  result <- ic_avail[, {
    n <- .N
    if (n < min_months) {
      list(Mean_IC = NA_real_, ICIR = NA_real_, Hit_Rate = NA_real_, N_Months = n)
    } else {
      m <- mean(IC, na.rm = TRUE)
      s <- sd(IC, na.rm = TRUE)
      list(
        Mean_IC = m,
        ICIR = if (s > 1e-8) m / s else NA_real_,
        Hit_Rate = mean(IC > 0, na.rm = TRUE),
        N_Months = n
      )
    }
  }, by = Factor_Name]

  result <- result[!is.na(ICIR)]
  if (isTRUE(dedup)) result <- .fdc_apply_dedup(result, TRUE, "compute_rolling_ic_all")
  else .fdc_dedup_notice(result$Factor_Name)
  result
}


#==============================================================================
# 4. group_factors_by_family()
#==============================================================================

#' Group factor names by economic family (7 groups for allocation).
#' @param registry Parsed factor_registry.json (default: auto-load)
#' @param dedup Logical (기본 FALSE = 무변경). TRUE 면 각 그룹에서 alias 를 빼고
#'   canonical 만 남긴다(drop_alias_factors). 이 함수의 산출은 그룹 내 ICIR
#'   가중의 입력이 되므로(regime_factor_alloc_engine.R), 배분에 쓰면 TRUE 권장.
#'   ★이름 수준 API 를 쓴다 — 패널이 아니라 이름 목록을 돌려주기 때문이다.
#'   그래서 여기서는 canonical 부재 시 개명이 아니라 **중복 제거**만 일어난다.
#' @return Named list: group_name -> character vector of factor IDs
group_factors_by_family <- function(registry = NULL, dedup = FALSE) {
  if (is.null(registry)) registry <- .load_registry()

  # Map registry categories to 7 allocation groups
  group_map <- list(
    defense   = c("defense", "risk"),
    quality   = c("quality", "accrual"),
    value     = c("value"),
    momentum  = c("momentum"),
    growth    = c("growth"),
    consensus = c("consensus"),
    liquidity = c("liquidity", "crowding")
  )

  groups <- list()
  for (gname in names(group_map)) {
    cats <- group_map[[gname]]
    factors <- names(registry)[sapply(registry, function(x) {
      (x$category %in% cats) || (x$labels$economic_family %in% cats)
    })]
    if (length(factors) > 0) groups[[gname]] <- factors
  }

  if (isTRUE(dedup)) {
    if (!.fdc_dedup_available()) {
      stop("[connector] dedup=TRUE 인데 factor_dup_scan.R 의 drop_alias_factors() 를 ",
           "로드할 수 없다 (fail-closed).")
    }
    groups <- lapply(groups, function(g)
      drop_alias_factors(g, registry = registry, warn = TRUE))
  } else {
    .fdc_dedup_notice(unlist(groups, use.names = FALSE))
  }

  # Excluded: regime, size (used as controls, not alpha sources)
  groups
}


cat("[factor_db_connector] Loaded. Functions: load_month_factors(), load_daily_factors(),\n")
cat("  compute_rolling_ic_all(), group_factors_by_family(), align_factor_direction()\n")
cat("  de-dup: 위 3종 모두 dedup=FALSE 기본(무변경). 선별/랭킹/Ω 추정이면 dedup=TRUE.\n")
