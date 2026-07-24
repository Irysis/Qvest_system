#==============================================================================
# d1_us_append_20260725.R — Universe_Support_update.xlsx → us_* 8패널 append 병합
#
# 배경 (D1, 2026-07-25):
#   - us_* 패널 종점 2026-03-31 (2026-06 정기변경 미반영, AST 리프 맵 v0 적발)
#   - incremental_update_file.R::incremental_universe_support()는
#     parse_universe_support(us_update)를 force=FALSE로 호출 → 캐시 히트 전량 스킵(no-op).
#     force=TRUE로 바꿔도 교체 semantics라 1990~2026-03 역사가 update 범위로 소실됨.
#   - 본 스크립트 = 올바른 증분: update xlsx 파싱 → 기존 패널 종점 이후 행만 append.
#
# 가드:
#   - 사전 pin: .cache/pins/d1_universe_20260725/ (실행 전 완료 확인)
#   - HARD: 신규 행에 2026-04 / 2026-05 / 2026-06 월말 행 전부 존재해야 쓰기 진행
#     (하나라도 결측 = 이음매 구멍 → 전 시트 중단, 쓰기 0건)
#   - Ticker overlap >= 0.90 (파싱 사고 방어)
#   - temp-rename 쓰기 (arrow mmap 잠금 회피)
#   - Date 컬럼 타입은 기존 파일 클래스(POSIXct/Date)에 맞춰 보존 (스키마 드리프트 방지)
#==============================================================================

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure", "config.R"))
source(file.path(ROOT, "02_Infrastructure", "data", "parse_universe_support.R"))

suppressPackageStartupMessages({ library(data.table); library(arrow) })

US_UPDATE <- file.path(ROOT, "03_Universe", "Update_File", "Universe_Support_update.xlsx")
stopifnot(file.exists(US_UPDATE))

REQUIRED_MONTHS <- c("2026-04", "2026-05", "2026-06")   # HARD 이음매 가드

cat("=== D1 Universe_Support append merge ===\n")
cat(sprintf("update xlsx: %s (mtime %s)\n", US_UPDATE,
            format(file.mtime(US_UPDATE), "%Y-%m-%d %H:%M:%S")))

# ── Phase 1: 전 시트 파싱 + HARD 가드 (쓰기 전 전량 검증) ────────────────────
parsed <- list()
for (s in names(UNIVERSE_SUPPORT_SHEET_META)) {
  meta <- UNIVERSE_SUPPORT_SHEET_META[[s]]
  new_long <- parse_one_us_sheet(US_UPDATE, s, meta)
  if (is.null(new_long) || nrow(new_long) == 0) {
    stop(sprintf("[D1] 시트 '%s' 파싱 결과 0행 — 중단 (쓰기 0건)", s))
  }
  new_long[, Date := as.Date(Date)]
  months_have <- sort(unique(format(new_long$Date, "%Y-%m")))
  missing <- setdiff(REQUIRED_MONTHS, months_have)
  if (length(missing) > 0) {
    stop(sprintf("[D1] HARD 이음매 가드 실패 — 시트 '%s'에 월말 결측: %s (보유: %s)",
                 s, paste(missing, collapse = ", "),
                 paste(months_have, collapse = ", ")))
  }
  parsed[[s]] <- new_long
  cat(sprintf("  [parsed] %-14s %s rows | %s ~ %s | months: %s\n",
              s, format(nrow(new_long), big.mark = ","),
              min(new_long$Date), max(new_long$Date),
              paste(months_have, collapse = " ")))
}
cat("[D1] Phase 1 OK — 8시트 전부 2026-04/05/06 월말 보유. 쓰기 시작.\n\n")

# ── Phase 2: append (temp-rename) ────────────────────────────────────────────
summary_rows <- list()
for (s in names(UNIVERSE_SUPPORT_SHEET_META)) {
  meta <- UNIVERSE_SUPPORT_SHEET_META[[s]]
  pq_path <- file.path(UNIVERSE_SUPPORT_CACHE, sprintf("us_%s.parquet", meta$cache_name))
  stopifnot(file.exists(pq_path))

  old <- as.data.table(read_parquet(pq_path))
  valcol <- setdiff(names(old), c("Date", "Ticker"))
  stopifnot(length(valcol) == 1)

  new_long <- copy(parsed[[s]])
  setnames(new_long, "Value", valcol)

  old_dates <- as.Date(old$Date)
  old_max   <- max(old_dates)
  add <- new_long[Date > old_max]
  if (nrow(add) == 0) {
    cat(sprintf("  [skip] %-14s 신규 행 없음 (기존 max %s)\n", s, old_max))
    next
  }

  # Ticker overlap 가드
  ov <- mean(unique(add$Ticker) %in% unique(old$Ticker))
  if (ov < 0.90) {
    stop(sprintf("[D1] Ticker overlap %.3f < 0.90 — 시트 '%s' 파싱 사고 의심, 중단", ov, s))
  }

  # Date 타입을 기존 스키마에 정합
  if (inherits(old$Date, "POSIXct")) {
    tzv <- attr(old$Date, "tzone"); if (is.null(tzv) || tzv == "") tzv <- "UTC"
    add[, Date := as.POSIXct(format(Date), tz = tzv)]
  } else {
    add[, Date := as.Date(Date)]
  }

  combined <- rbind(old, add, use.names = TRUE)
  setorder(combined, Date, Ticker)
  n_old <- nrow(old); n_add <- nrow(add)
  rm(old, new_long); gc()

  tmp <- paste0(pq_path, ".tmp")
  write_parquet(combined, tmp)
  if (file.exists(pq_path)) file.remove(pq_path)
  file.rename(tmp, pq_path)

  cat(sprintf("  [write] %-14s +%s rows (old %s → %s) | new max %s\n",
              s, format(n_add, big.mark = ","),
              format(n_old, big.mark = ","),
              format(nrow(combined), big.mark = ","),
              max(as.Date(combined$Date))))
  summary_rows[[s]] <- data.table(sheet = s, added = n_add,
                                  new_max = max(as.Date(combined$Date)))
  rm(combined); gc()
}

cat("\n=== D1 append 완료 ===\n")
if (length(summary_rows) > 0) print(rbindlist(summary_rows))
