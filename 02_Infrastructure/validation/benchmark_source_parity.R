# ============================================================================
# benchmark_source_parity.R — 벤치마크 2소스 정합 검사 (읽기 전용)
# ----------------------------------------------------------------------------
# 신설: 2026-08-02 (Q-Lead 야간 라운드 — 2026-07 BM_Ret 오염 적발 후 재발 방지)
#
# ## 왜 필요한가 (실측)
# `.cache/RAWDATA.parquet::BM_Ret` 과 `.cache/benchmark.parquet::BM_Ret` 은
# **독립적으로 생성**된다:
#   · krx_build_rawdata.R:223  bm_new[, BM_Ret := BM_Close / shift(BM_Close) - 1]
#       → KRX 종가로 자체 계산. 벤치 종가가 결측되면 전일값이 carry 되어 **BM_Ret = 0**.
#   · incremental_update_file.R:181  merge(raw, bm[, .(Date, BM_Ret)], by="Date")
#       → benchmark.parquet 조인.
# 두 경로가 같은 컬럼을 채우는데 **정합 검사가 없었다.**
#
# 2026-08-02 적발 실측:
#   불일치 = 2026-07 단 8일 (07-06/07/21/22/28/29/30/31). 1990-01~2026-06 전 8,990일 diff=0.
#   그중 4일은 RAWDATA 가 정확히 0 — **07-28 은 benchmark -11.55% 인데 RAWDATA 0**
#   (폭락일 벤치 수익 소실). 2026-07 월 누적 benchmark -23.63% vs RAWDATA -17.70%
#   = **5.93%p 괴리**. 정본은 benchmark.parquet(Naver 패처 복구분·폭락 실측 정합).
#
# 이는 2026-07-25 "benchmark date32 writer 불일치 → 조인 silent all-NA(β 54 전멸),
# 7일 방치 원인 = 감지장치 0" 과 **같은 계통의 재발**이다. 그때는 dtype, 이번엔 값.
# 소스가 둘이면 정합 검사가 있어야 한다 — 없으면 조용히 갈린다.
#
# ## 사용
#   source("02_Infrastructure/validation/benchmark_source_parity.R")
#   res <- benchmark_source_parity()          # 전 기간
#   res <- benchmark_source_parity(recent_days = 120)
#   print(res$severity)   # OK / WARN / CRITICAL
#
# 판정 (근거: 정상 운영에서 두 소스는 bit-일치해야 한다 — 실측 8,990/8,998 일치):
#   CRITICAL : 최근 90일 내 불일치 존재  또는  임의 월 누적 괴리 |gap| > 0.5%p
#   WARN     : 과거 구간에만 불일치 존재
#   OK       : 불일치 없음
# 부가 지문: carry-forward 의심(BM_Close 가 전일과 완전 동일) 별도 집계 — 결측을
#   전일값으로 메운 흔적. 값이 0 이라 "정상 데이터"처럼 보이는 게 이 결함의 위장 기전이다.
#
# 규범: r-portability.md(루트 marker 검증) · answer-principles(회피표현 금지).
# 읽기 전용 — 어떤 캐시도 수정하지 않는다.
# ============================================================================

suppressWarnings(suppressMessages({
  library(arrow); library(data.table)
}))

.bsp_is_root <- function(p) {
  if (is.null(p) || !nzchar(p)) return(FALSE)
  p <- gsub("\\\\", "/", p)
  file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))
}

.bsp_root <- function() {
  for (c0 in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
               Sys.getenv("QM_ROOT", unset = "")))
    if (.bsp_is_root(c0)) return(gsub("\\\\", "/", c0))
  p <- gsub("\\\\", "/", getwd())
  for (i in 1:6) {
    if (.bsp_is_root(p)) return(p)
    par <- dirname(p); if (identical(par, p)) break; p <- par
  }
  NA_character_
}

#' 벤치마크 2소스 정합 검사
#'
#' @param rawdata_path   기본 <root>/.cache/RAWDATA.parquet
#' @param bench_path     기본 <root>/.cache/benchmark.parquet
#' @param tol            일치 허용오차 (기본 1e-9 — 두 소스는 bit-일치가 정상)
#' @param recent_days    NULL 이면 전 기간. 정수면 최근 N일만 대조(빠른 상시 점검)
#' @param recent_window  CRITICAL 판정용 "최근" 창 (기본 90일)
#' @param month_gap_pp   월 누적 괴리 CRITICAL 문턱 (기본 0.5%p)
benchmark_source_parity <- function(rawdata_path = NULL, bench_path = NULL,
                                    tol = 1e-9, recent_days = NULL,
                                    recent_window = 90L, month_gap_pp = 0.5) {
  root <- .bsp_root()
  if (is.na(root)) stop("benchmark_source_parity: 프로젝트 루트 resolve 실패.")
  if (is.null(rawdata_path)) rawdata_path <- file.path(root, ".cache", "RAWDATA.parquet")
  if (is.null(bench_path))   bench_path   <- file.path(root, ".cache", "benchmark.parquet")

  miss <- c(rawdata_path, bench_path)[!file.exists(c(rawdata_path, bench_path))]
  if (length(miss))
    return(list(severity = "UNMEASURED", note = paste("소스 부재:", paste(miss, collapse = ", ")),
                n_mismatch = NA_integer_))

  b <- as.data.table(read_parquet(bench_path))
  bcols <- intersect(c("Date", "BM_Ret", "BM_Close"), names(b))
  b <- b[, ..bcols]
  setnames(b, "BM_Ret", "bm_bench")

  r <- as.data.table(read_parquet(rawdata_path, col_select = c("Date", "BM_Ret")))
  r <- unique(r)                       # Date별 (Ticker 무관 동일이 정상)
  setnames(r, "BM_Ret", "bm_raw")

  # Date별 BM_Ret 유일성 — 깨지면 그 자체가 결함
  dup_dates <- r[, .N, by = Date][N > 1L]

  if (!is.null(recent_days)) {
    cutoff <- max(c(b$Date, r$Date), na.rm = TRUE) - as.integer(recent_days)
    b <- b[Date >= cutoff]; r <- r[Date >= cutoff]
  }

  m <- merge(r, b, by = "Date", all = FALSE)      # 공통 날짜만 대조
  m[, diff := bm_raw - bm_bench]
  mism <- m[!is.na(diff) & abs(diff) > tol][order(-abs(diff))]

  # 월 누적 괴리
  mm <- m[!is.na(bm_raw) & !is.na(bm_bench)]
  mm[, ym := format(Date, "%Y-%m")]
  agg <- mm[, .(raw = prod(1 + bm_raw) - 1, bench = prod(1 + bm_bench) - 1, n = .N), by = ym]
  agg[, gap_pp := (raw - bench) * 100]
  bad_months <- agg[abs(gap_pp) > month_gap_pp][order(-abs(gap_pp))]

  # carry-forward 의심 (BM_Close 가 전일과 완전 동일 → BM_Ret 0 위장)
  carry <- data.table()
  if ("BM_Close" %in% names(b)) {
    bc <- b[order(Date)]
    bc[, prev_close := shift(BM_Close)]
    carry <- bc[!is.na(prev_close) & BM_Close == prev_close, .(Date, BM_Close)]
  }
  zero_raw <- m[!is.na(bm_raw) & bm_raw == 0 & !is.na(bm_bench) & abs(bm_bench) > tol,
                .(Date, bm_raw, bm_bench)]

  max_date <- suppressWarnings(max(m$Date, na.rm = TRUE))
  recent_mism <- if (nrow(mism)) mism[Date >= (max_date - as.integer(recent_window))] else mism

  # ── 정본 판정 (2026-08-08 신설) — 상수 금지 ─────────────────────────────────
  #  08-02 사건: benchmark.parquet 가 정본, RAWDATA 가 오염(0-위장).
  #  08-08 사건: **정확히 반대**. benchmark 의 2026-07-27 = -0.885344(-88.5%) 로
  #    KOSPI200 에서 물리적으로 불가, RAWDATA 는 같은 날 +0.012922 로 정상이었다.
  #  그런데 이 함수는 canonical_source 를 **상수로 반환**했고 부팅이 그대로
  #  "정본=benchmark.parquet" 라고 안내했다. 그 안내를 따라 bench→RAWDATA 방향
  #  수리기(repair_rawdata_bmret_from_benchmark.R)를 돌리면 **정상 소스를 오염값으로
  #  덮어쓴다** — 경보는 맞는데 처방이 거꾸로인 상태.
  #  ∴ 어느 쪽이 정본인지는 사건마다 다르므로 **판정되어야 할 값**이다.
  #  판정축 = 값 타당성. 지수 일간수익이 물리적 한계를 넘는 쪽이 오염이다.
  #  (KOSPI 역대 최대 일간 변동 ≈ ±12%. 문턱 0.30 은 그보다 한참 위라 오탐 여지가 없다 —
  #   실제 폭락일을 오염으로 몰지 않기 위해 일부러 느슨하게 잡는다.)
  #  ★판정은 **날짜별**이다. 한 사건 안에서도 오염 측이 갈릴 수 있다
  #  (08-08 실측: 2026-07-27 은 benchmark 오염, 2026-08-05 는 RAWDATA 0-위장 — 정반대).
  #  스칼라 하나로 "정본"을 말하면 그 중 한쪽은 반드시 틀린 안내가 된다.
  #  증거축 2종 — 둘 다 "그 값이 데이터로서 불가능한가"를 묻지, 어느 파일인지를 묻지 않는다:
  #   (a) value_plausibility : 지수 일간수익이 물리적 한계 초과 (KOSPI 역대 최대 ≈ ±12%,
  #       문턱 0.30 은 한참 위 — 실제 폭락일을 오염으로 몰지 않기 위해 일부러 느슨)
  #   (b) zero_masked        : 한쪽만 정확히 0 — 결손이 "그날 안 움직였다"로 위장된 지문
  #       (08-02 실사고 기전. NA 였다면 즉시 드러났을 값)
  impl_bound <- as.numeric(getOption("qvest.bm_implausible_bound", 0.30))
  #  ★경계 제외: 시리즈 **첫 관측일**의 수익률은 직전일이 없어 정의되지 않는다.
  #   그 날의 0 은 결손이 아니라 경계값이므로 0-위장으로 몰면 영구 오탐이 된다
  #   (08-08 실측: 1990-01-05 = benchmark.parquet 첫 행, ret_from_close=NA → 0 이 정상).
  first_common <- suppressWarnings(min(m$Date, na.rm = TRUE))
  dirs <- if (nrow(mism) == 0L) data.table() else {
    d <- copy(mism)[Date > first_common]
    d[, contaminated := fifelse(abs(bm_bench) > impl_bound, "benchmark.parquet",
                        fifelse(abs(bm_raw)   > impl_bound, "RAWDATA::BM_Ret",
                         fifelse(bm_raw == 0 & bm_bench != 0, "RAWDATA::BM_Ret",
                          fifelse(bm_bench == 0 & bm_raw != 0, "benchmark.parquet",
                                  NA_character_))))]
    d[, evidence := fifelse(abs(bm_bench) > impl_bound | abs(bm_raw) > impl_bound,
                            "value_plausibility",
                     fifelse(is.na(contaminated), "undetermined", "zero_masked"))]
    d[, .(Date, bm_raw, bm_bench, diff, contaminated, evidence)]
  }
  impl_b <- if (nrow(mism)) mism[abs(bm_bench) > impl_bound] else mism
  impl_r <- if (nrow(mism)) mism[abs(bm_raw)   > impl_bound] else mism
  sides  <- if (nrow(dirs)) unique(dirs[!is.na(contaminated)]$contaminated) else character(0)
  n_und  <- if (nrow(dirs)) sum(is.na(dirs$contaminated)) else 0L
  canon <- if (nrow(mism) == 0L) {
    list(src = "benchmark.parquet", basis = "no_mismatch — 판정 불요")
  } else if (length(sides) == 1L && n_und == 0L) {
    # 오염이 한쪽에만 → 반대쪽이 그 사건의 정본
    list(src = setdiff(c("benchmark.parquet", "RAWDATA::BM_Ret"), sides),
         basis = sprintf("%s — 오염 %d일 전부 %s 측",
                         paste(unique(dirs$evidence), collapse = "+"), nrow(dirs), sides))
  } else if (length(sides) >= 1L) {
    list(src = "per_date",
         basis = sprintf("오염 측이 날짜별로 갈림(%s) 또는 미판정 %d일 — repair_directions 참조. ★단일 방향 수리 금지",
                         paste(sides, collapse = "/"), n_und))
  } else {
    list(src = "undetermined",
         basis = "증거축 2종 모두 무판정 — 외부 소스 대조 필요. ★자동 수리 금지")
  }

  severity <- if (nrow(dup_dates) > 0L || nrow(recent_mism) > 0L || nrow(bad_months) > 0L) {
    "CRITICAL"
  } else if (nrow(mism) > 0L) "WARN" else "OK"

  note <- if (severity == "OK") {
    sprintf("두 소스 BM_Ret 일치 (공통 %d일, tol=%g)", nrow(m), tol)
  } else if (nrow(dup_dates) > 0L) {
    sprintf("RAWDATA 한 Date 에 서로 다른 BM_Ret %d일 — 소스 자체 불일치", nrow(dup_dates))
  } else {
    sprintf("불일치 %d일 (최근 %d일 내 %d) · 월괴리>%.1f%%p %d개월 · 최대|diff|=%.6f · RAWDATA 0-위장 %d일 — 정본=%s (%s)",
            nrow(mism), recent_window, nrow(recent_mism), month_gap_pp,
            nrow(bad_months), max(abs(mism$diff)), nrow(zero_raw), canon$src, canon$basis)
  }

  list(
    severity = severity, note = note,
    n_common = nrow(m), n_mismatch = nrow(mism), n_recent_mismatch = nrow(recent_mism),
    max_abs_diff = if (nrow(mism)) max(abs(mism$diff)) else 0,
    mismatches = head(mism, 50),
    bad_months = bad_months,
    zero_masked = zero_raw,              # RAWDATA=0 인데 benchmark 는 non-zero → 소실 지문
    carry_forward_dates = carry,
    dup_dates = dup_dates,
    canonical_source = canon$src,          # ★상수 아님 — 사건마다 판정된다(위 주석)
    canonical_basis  = canon$basis,
    implausible_bench = impl_b,            # 수리 방향 결정 근거 — 이 쪽이 덮어써져야 할 값
    implausible_raw   = impl_r,
    repair_directions = dirs,              # ★날짜별 오염 측 + 증거축 (단일 방향 수리 금지의 근거)
    checked_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    paths = c(rawdata = rawdata_path, benchmark = bench_path)
  )
}

# CLI: Rscript 02_Infrastructure/validation/benchmark_source_parity.R [recent_days]
if (sys.nframe() == 0L && !interactive()) {
  a <- commandArgs(trailingOnly = TRUE)
  rd <- if (length(a) && nzchar(a[1])) as.integer(a[1]) else NULL
  res <- benchmark_source_parity(recent_days = rd)
  cat(sprintf("[benchmark_source_parity] %s — %s\n", res$severity, res$note))
  if (res$n_mismatch > 0L) {
    cat("불일치 상위:\n"); print(head(res$mismatches, 12))
    if (nrow(res$bad_months)) { cat("월 누적 괴리:\n"); print(res$bad_months) }
    if (nrow(res$zero_masked)) {
      cat(sprintf("★RAWDATA 0-위장 %d일 (benchmark 는 non-zero — 값 소실이 '정상 0%%'로 위장):\n",
                  nrow(res$zero_masked)))
      print(res$zero_masked)
    }
  }
  if (identical(res$severity, "CRITICAL")) quit(status = 2L)
}
