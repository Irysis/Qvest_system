# panel_alignment_guard.R — period_returns panel 월-라벨 정렬 가드 (2026-07-02 도훈 mandate)
#
# 배경(결함): 백테 엔진이 리밸일에 "직전 리밸 이후 실현 수익"을 기록하는데, panel이 그 수익을
#   *기록한 달*(리밸월) 이름 realized_ym으로 라벨링 → 실제 수익월보다 1개월 앞선 라벨.
#   내부 merge는 전부 이 realized_ym으로 일관돼 결과는 정확하나, *외부* 달력월 데이터
#   (KOSPI200·팩터)를 realized_ym으로 순진 조인하면 1개월 오정렬 + look-ahead 위험.
#
# 규약: realized_ym = 리밸/장부 기록월 (내부 join key, 불변) · return_ym = 진짜 수익 달력월(= realized_ym - 1)
#   → 외부 달력 데이터 조인·성과보고·벤치비교는 return_ym 사용.
# 본 가드: build 시 return_ym 정렬 β(vs KOSPI200)가 롱온리 β≈0.9인지 검증, 어긋나면 hard-abort → 재발 물리적 차단.

suppressWarnings(suppressMessages(library(data.table)))

# realized_ym(라벨月) → return_ym(진짜 수익월 = 전월). 첫날-1일 = 전월 말일 트릭(base R).
add_return_ym <- function(dt) {
  dt <- as.data.table(dt)
  stopifnot("realized_ym" %in% names(dt))
  dt[, return_ym := format(as.Date(paste0(realized_ym, "-01")) - 1, "%Y-%m")]
  # realized_ym 바로 뒤로 배치
  if ("realized_ym" %in% names(dt)) {
    oc <- names(dt); oc <- oc[oc != "return_ym"]
    pos <- match("realized_ym", oc)
    setcolorder(dt, append(oc, "return_ym", after = pos))
  }
  dt[]
}

# 정렬 가드: return_ym 기준 롱온리 β≈0.9 검증 (아니면 stop). KOSPI200 = .cache/indices.parquet.
assert_panel_alignment <- function(dt, ret_col = "ret_orig", min_beta = 0.5, kospi_path = NULL) {
  dt <- as.data.table(dt)
  if (is.null(kospi_path)) kospi_path <- file.path(Sys.getenv("QM_ROOT", "."), ".cache/indices.parquet")
  if (!file.exists(kospi_path)) { warning("[panel_guard] KOSPI200 캐시 부재 — 가드 스킵"); return(invisible(NA)) }
  if (!(ret_col %in% names(dt)) || !("return_ym" %in% names(dt))) { warning("[panel_guard] 컬럼 부족 — 스킵"); return(invisible(NA)) }
  suppressWarnings(suppressMessages(library(arrow)))
  idx <- as.data.table(read_parquet(kospi_path))
  idx[, ym := format(as.Date(Date), "%Y-%m")]
  k <- idx[, .(close = data.table::last(kospi200)), by = ym][order(ym)]
  k[, kr := close / shift(close) - 1]
  bof <- function(key) {
    m <- merge(dt[, .(kk = get(key), r = get(ret_col))], k[, .(kk = ym, kr)], by = "kk")
    m <- m[is.finite(r) & is.finite(kr)]
    if (nrow(m) < 24) return(NA_real_)
    unname(coef(stats::lm(r ~ kr, m))[2])
  }
  b_ret <- bof("return_ym"); b_lab <- bof("realized_ym")
  cat(sprintf("[panel_guard] β vs KOSPI200: return_ym=%.3f(정렬) realized_ym=%.3f(라벨月)\n", b_ret, b_lab))
  if (!is.na(b_ret) && b_ret < min_beta)
    stop(sprintf("[panel_guard] ABORT: return_ym 정렬 β=%.3f < %.2f — panel 월-라벨 정렬 결함 재발. add_return_ym/수익 shift 확인 요.", b_ret, min_beta))
  invisible(b_ret)
}
