#==============================================================================
# compute_custom.R — 커스텀 팩터 등록 파이프라인
#
# 함수: register_custom_factor(factor_name, compute_fn, family, direction,
#                               description, core_reference, tags)
#
# 역할:
#   1. 사용자 정의 compute_fn을 검증 (C13~C15 호환, Z_Score_Aligned 방향)
#   2. factor_registry.json에 메타데이터 등록
#   3. method_registry.json에 경제적 근거 기록
#   4. 등록된 팩터를 load_month_factors() 경유로 조회 가능하게 설정
#
# PIT 준수:
#   - compute_fn은 sig_date 이전 데이터만 수신 (load 단계에서 필터)
#   - C13: direction = "positive" 또는 "negative" 명시. 수동 부호 반전 금지.
#   - C15: register 후 load_month_factors()로만 접근
#
# 사용 예:
#   source("02_Infrastructure/factor_db/compute_custom.R")
#   register_custom_factor(
#     factor_name    = "MyBeta",
#     compute_fn     = function(RAWDATA, sig_date) { ... },
#     family         = "defense",
#     direction      = "negative",          # 낮은 beta = 좋음
#     description    = "CAPM beta (252d)",
#     core_reference = "Frazzini & Pedersen (2014) — Betting Against Beta",
#     tags           = c("beta", "defense", "low_risk")
#   )
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

# ---- 경로 설정 ----
.cc_self_dir <- tryCatch(
  dirname(sys.frame(1)$ofile),
  error = function(e) {
    if (exists("FUNC_PATH")) file.path(FUNC_PATH, "factor_db")
    else file.path(
      "/mnt/c/Users/User/OneDrive/\ubc14\ud0d5 \ud654\uba74/Quant_Module_Moltbot",
      "02_Infrastructure", "factor_db"
    )
  }
)

.cc_infra_dir <- dirname(.cc_self_dir)

if (!exists("CACHE_DIR")) {
  source(file.path(.cc_infra_dir, "config.R"))
}

FACTOR_REG_PATH    <- file.path(CACHE_DIR, "factor_db", "factor_registry.json")
METHOD_REG_PATH    <- file.path(.cc_self_dir, "method_registry.json")
CUSTOM_FACTOR_ENV  <- new.env(parent = emptyenv())  # 등록된 compute_fn 저장소

# ---- 내부 헬퍼 ----

.load_registry_rw <- function() {
  if (file.exists(FACTOR_REG_PATH)) {
    tryCatch(fromJSON(FACTOR_REG_PATH, simplifyVector = FALSE),
             error = function(e) list())
  } else {
    list()
  }
}

.save_registry <- function(reg) {
  dir.create(dirname(FACTOR_REG_PATH), recursive = TRUE, showWarnings = FALSE)
  write_json(reg, FACTOR_REG_PATH, auto_unbox = TRUE, pretty = TRUE)
}

.load_method_registry <- function() {
  if (file.exists(METHOD_REG_PATH)) {
    tryCatch(fromJSON(METHOD_REG_PATH, simplifyVector = FALSE),
             error = function(e) list())
  } else {
    list()
  }
}

.save_method_registry <- function(mreg) {
  write_json(mreg, METHOD_REG_PATH, auto_unbox = TRUE, pretty = TRUE)
}

# C13 호환 방향 검증
.validate_direction <- function(direction) {
  valid <- c("positive", "negative")
  if (!direction %in% valid) {
    stop(sprintf(
      "[compute_custom] C13 위반: direction='%s' 불허. 'positive' 또는 'negative'만 허용. 수동 부호 반전 금지.",
      direction
    ))
  }
}

# compute_fn 시그니처 검증: function(RAWDATA, sig_date, ...) 형태여야 함
.validate_compute_fn <- function(compute_fn) {
  if (!is.function(compute_fn)) {
    stop("[compute_custom] compute_fn이 function이 아닙니다.")
  }
  fn_args <- names(formals(compute_fn))
  required <- c("RAWDATA", "sig_date")
  missing_args <- setdiff(required, fn_args)
  if (length(missing_args) > 0) {
    stop(sprintf(
      "[compute_custom] compute_fn 시그니처 오류: 필수 인자 '%s' 누락. function(RAWDATA, sig_date, ...) 형태 필요.",
      paste(missing_args, collapse = ", ")
    ))
  }
}

# 반환값 검증: data.table(Ticker, Factor_Name, Raw_Value)
.validate_fn_output <- function(result, factor_name) {
  if (!is.data.table(result)) {
    stop(sprintf("[compute_custom] compute_fn 반환값이 data.table이 아닙니다. (%s)", factor_name))
  }
  required_cols <- c("Ticker", "Factor_Name", "Raw_Value")
  missing_cols <- setdiff(required_cols, names(result))
  if (length(missing_cols) > 0) {
    stop(sprintf(
      "[compute_custom] 반환 data.table에 필수 컬럼 '%s' 누락. (%s)",
      paste(missing_cols, collapse = ", "), factor_name
    ))
  }
}

#==============================================================================
# register_custom_factor()
#
# @param factor_name    팩터 코드 (예: "MyBeta"). factor_registry의 Factor_Name과 일치해야 함.
# @param compute_fn     function(RAWDATA, sig_date, ...) → data.table(Ticker, Factor_Name, Raw_Value)
# @param family         팩터 패밀리 (예: "defense", "momentum", "value", ...)
# @param direction      "positive" (높을수록 좋음) 또는 "negative" (낮을수록 좋음)
#                       C13: Z_Score_Aligned이 이 방향을 자동 적용. 수동 반전 금지.
# @param description    팩터 설명 (한/영 가능)
# @param core_reference 학술 근거 (논문명 + 저자 + 연도)
# @param tags           문자열 벡터 (검색/필터용)
# @param overwrite      기존 동명 팩터 덮어쓰기 여부 (기본 FALSE)
# @return factor_name (invisible)
#==============================================================================
register_custom_factor <- function(
  factor_name,
  compute_fn,
  family,
  direction,
  description    = "",
  core_reference = "",
  tags           = character(0),
  overwrite      = FALSE
) {
  # ── 입력 검증 ────────────────────────────────────────────────────────────
  stopifnot(is.character(factor_name), length(factor_name) == 1, nchar(factor_name) > 0)
  stopifnot(is.character(family),      length(family) == 1)
  .validate_direction(direction)
  .validate_compute_fn(compute_fn)

  if (nchar(core_reference) == 0) {
    warning(sprintf(
      "[compute_custom] core_reference가 비어 있습니다 (%s). S0 규칙: 학술 근거 필수.",
      factor_name
    ))
  }

  # ── 드라이런 검증 (dummy RAWDATA로 반환값 구조 확인) ─────────────────────
  tryCatch({
    dummy_rd <- data.table(
      Ticker = c("A001", "A002", "A003"),
      Date   = as.Date(c("2020-01-02", "2020-01-02", "2020-01-02")),
      Ret    = c(0.01, -0.02, 0.005),
      BM_Ret = c(0.005, 0.005, 0.005),
      Close  = c(1000, 2000, 1500),
      Vol    = c(1e8, 2e8, 1.5e8),
      Size   = c(1e11, 2e11, 1.5e11)
    )
    dummy_out <- compute_fn(dummy_rd, as.Date("2020-01-02"))
    .validate_fn_output(dummy_out, factor_name)
    cat(sprintf("[compute_custom] Dry-run OK: %s (returned %d rows)\n",
                factor_name, nrow(dummy_out)))
  }, error = function(e) {
    stop(sprintf("[compute_custom] 드라이런 실패 (%s): %s", factor_name, conditionMessage(e)))
  })

  # ── factor_registry.json 등록 ─────────────────────────────────────────────
  registry <- .load_registry_rw()

  existing_idx <- which(vapply(registry, function(x) {
    identical(x$Factor_Name %||% x$factor_name, factor_name)
  }, logical(1)))

  if (length(existing_idx) > 0 && !overwrite) {
    cat(sprintf("[compute_custom] '%s'는 이미 등록됨. overwrite=TRUE로 재등록 가능.\n", factor_name))
    # compute_fn은 메모리에 등록 (registry 변경 없음)
    assign(factor_name, compute_fn, envir = CUSTOM_FACTOR_ENV)
    return(invisible(factor_name))
  }

  new_entry <- list(
    Factor_Name    = factor_name,
    family         = family,
    direction      = direction,
    description    = description,
    core_reference = core_reference,
    tags           = as.list(tags),
    source         = "compute_custom",
    registered_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    custom         = TRUE
  )

  if (length(existing_idx) > 0) {
    registry[[existing_idx[1]]] <- new_entry
    cat(sprintf("[compute_custom] '%s' 갱신 (overwrite=TRUE)\n", factor_name))
  } else {
    registry <- c(registry, list(new_entry))
    cat(sprintf("[compute_custom] '%s' 신규 등록 (total: %d)\n", factor_name, length(registry)))
  }

  .save_registry(registry)

  # ── method_registry.json 등록 ─────────────────────────────────────────────
  mreg <- .load_method_registry()

  method_entry <- list(
    factor_name    = factor_name,
    family         = family,
    direction      = direction,
    core_reference = core_reference,
    description    = description,
    tags           = as.list(tags),
    registered_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  )

  existing_m <- which(vapply(mreg, function(x) {
    identical(x$factor_name, factor_name)
  }, logical(1)))

  if (length(existing_m) > 0) {
    mreg[[existing_m[1]]] <- method_entry
  } else {
    mreg <- c(mreg, list(method_entry))
  }
  .save_method_registry(mreg)

  # ── compute_fn 메모리 등록 (load_month_factors 경유 호출용) ──────────────
  assign(factor_name, compute_fn, envir = CUSTOM_FACTOR_ENV)

  cat(sprintf("[compute_custom] 등록 완료: %s | family=%s | direction=%s\n",
              factor_name, family, direction))
  cat(sprintf("  core_ref: %s\n", if (nchar(core_reference) > 0) core_reference else "(없음)"))
  cat(sprintf("  tags: %s\n", if (length(tags) > 0) paste(tags, collapse=", ") else "(없음)"))

  invisible(factor_name)
}

#==============================================================================
# get_custom_compute_fn()
#
# load_month_factors()가 커스텀 팩터 요청 시 호출.
# C15: 직접 parquet 로드 없이 이 함수 경유.
#
# @param factor_name 팩터 코드
# @return compute_fn 또는 NULL
#==============================================================================
get_custom_compute_fn <- function(factor_name) {
  if (exists(factor_name, envir = CUSTOM_FACTOR_ENV, inherits = FALSE)) {
    get(factor_name, envir = CUSTOM_FACTOR_ENV, inherits = FALSE)
  } else {
    NULL
  }
}

#==============================================================================
# list_custom_factors()
#
# 현재 세션에 등록된 커스텀 팩터 목록 반환.
#==============================================================================
list_custom_factors <- function() {
  fnames <- ls(CUSTOM_FACTOR_ENV)
  if (length(fnames) == 0) {
    cat("[compute_custom] 등록된 커스텀 팩터 없음.\n")
    return(invisible(character(0)))
  }
  cat(sprintf("[compute_custom] 등록된 커스텀 팩터 %d건:\n", length(fnames)))
  for (fn in fnames) cat(sprintf("  - %s\n", fn))
  invisible(fnames)
}

#==============================================================================
# compute_custom_factor()
#
# 등록된 커스텀 팩터를 PIT 준수 방식으로 실행.
# C15: 이 함수가 load_month_factors() 내부에서 dispatch됨.
#
# @param factor_name 팩터 코드
# @param RAWDATA     원시 데이터 (Date <= sig_date 필터는 여기서 강제)
# @param sig_date    신호 날짜 (PIT 기준점)
# @return data.table(Ticker, Factor_Name, Raw_Value, Z_Score_Aligned)
#==============================================================================
compute_custom_factor <- function(factor_name, RAWDATA, sig_date) {
  fn <- get_custom_compute_fn(factor_name)
  if (is.null(fn)) {
    stop(sprintf("[compute_custom] '%s'가 등록되지 않았습니다. register_custom_factor() 먼저 호출하세요.", factor_name))
  }

  sig_d <- as.Date(sig_date)

  # C14/PIT: RAWDATA에서 sig_date 이후 데이터 강제 제거
  rd_pit <- RAWDATA[Date <= sig_d]
  if (nrow(rd_pit) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(),
                      Raw_Value = numeric(), Z_Score_Aligned = numeric()))
  }

  result <- tryCatch(
    fn(rd_pit, sig_d),
    error = function(e) {
      warning(sprintf("[compute_custom] '%s' 실행 오류 (%s): %s",
                      factor_name, sig_d, conditionMessage(e)))
      data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric())
    }
  )

  .validate_fn_output(result, factor_name)

  # C13: Z_Score_Aligned 자동 계산 (direction 기반, 수동 반전 금지)
  registry <- .load_registry_rw()
  reg_entry <- Filter(function(x) identical(x$Factor_Name %||% x$factor_name, factor_name), registry)
  direction <- if (length(reg_entry) > 0) reg_entry[[1]]$direction %||% "positive" else "positive"

  if (nrow(result) >= 5) {
    raw_vals <- result$Raw_Value
    mu  <- mean(raw_vals, na.rm = TRUE)
    sig <- sd(raw_vals,   na.rm = TRUE)
    z   <- if (!is.na(sig) && sig > 1e-10) (raw_vals - mu) / sig else rep(0, length(raw_vals))
    # C13: direction == "negative" → z 부호 반전 (낮을수록 좋음)
    if (direction == "negative") z <- -z
    result[, Z_Score_Aligned := z]
  } else {
    result[, Z_Score_Aligned := NA_real_]
  }

  result
}

# ---- null-coalescing (if not already loaded) ----
if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

cat("[compute_custom] Loaded. Functions: register_custom_factor(), get_custom_compute_fn(),\n")
cat("  list_custom_factors(), compute_custom_factor()\n")
cat("  C13/C14/C15 준수. direction='positive'/'negative'만 허용. 수동 반전 금지.\n")
