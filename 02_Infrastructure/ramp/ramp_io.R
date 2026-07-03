## ramp_io.R — RAMP 공용 I/O 헬퍼 (§2.4 출력 메타 규약 강제)
## 모든 RAMP parquet/json 산출은 ramp_write_parquet/ramp_write_json 경유 — as_of_date/generated_at/source_version 자동 주입.
## security_id 매핑: KRX Ticker = security_id (문서화). 본 RAMP 단계 산출은 전략-레벨/팩터-레벨이라
##   security_id가 strategy_id 또는 factor_id로 치환되는 곳은 id_field 메타로 명시.

suppressMessages({ library(data.table); library(jsonlite) })
if (!requireNamespace("arrow", quietly = TRUE)) stop("[ramp_io] arrow required")

RAMP_SOURCE_VERSION <- "ramp_v1.0_gate3_4"

#' 현재 UTC ISO8601 타임스탬프
ramp_now_iso <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

#' as_of_date: 데이터 최신성 기준일 (호출자가 전달, 없으면 today)
ramp_meta_fields <- function(as_of_date = Sys.Date(), source_version = RAMP_SOURCE_VERSION) {
  list(
    as_of_date     = as.character(as.Date(as_of_date)),
    generated_at   = ramp_now_iso(),
    source_version = source_version
  )
}

#' parquet 산출 — data.table에 메타 컬럼 부착 후 기록.
#' @param dt data.table
#' @param path 출력 경로
#' @param as_of_date 데이터 기준일
#' @param id_field "security_id" 매핑 대상 컬럼명 문서화 (예: "strategy_id"/"factor_id"/"Ticker")
ramp_write_parquet <- function(dt, path, as_of_date = Sys.Date(),
                               source_version = RAMP_SOURCE_VERSION, id_field = "Ticker") {
  stopifnot(is.data.frame(dt))
  dt <- as.data.table(copy(dt))
  m <- ramp_meta_fields(as_of_date, source_version)
  dt[, as_of_date := m$as_of_date]
  dt[, generated_at := m$generated_at]
  dt[, source_version := m$source_version]
  dt[, security_id_field := id_field]   # §2.4 security_id 매핑 문서화
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(dt, path)
  cat(sprintf("[ramp_io] parquet -> %s  (nrow=%d, id_field=%s)\n", path, nrow(dt), id_field))
  invisible(path)
}

#' json 산출 — 메타 3필드 + payload.
ramp_write_json <- function(obj, path, as_of_date = Sys.Date(),
                            source_version = RAMP_SOURCE_VERSION, id_field = "Ticker") {
  m <- ramp_meta_fields(as_of_date, source_version)
  out <- c(list(as_of_date = m$as_of_date, generated_at = m$generated_at,
                source_version = m$source_version, security_id_field = id_field),
           obj)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(out, path, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 8)
  cat(sprintf("[ramp_io] json -> %s\n", path))
  invisible(path)
}

cat("[ramp_io.R] Loaded — ramp_write_parquet/ramp_write_json (§2.4 meta enforced)\n")
