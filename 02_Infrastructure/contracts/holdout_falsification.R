#!/usr/bin/env Rscript
#==============================================================================
# holdout_falsification.R — C3: holdout 사전등록 예측구간 falsification (Level 0 계약)
#
# 배경 (2026-06-10 도훈 mandate, calibration 백로그 C3):
#   holdout 18~24개월 Sharpe의 표준오차는 ±0.7~0.8 — "성과 좋았나" 채점은 통계적으로 무력.
#   질문을 바꾼다: "채택 시점에 사전 기록한 예측구간을 벗어났는가" (반증 체크, Popper식).
#   - 실측 < q05  → FAIL_FALSIFIED   (전략이 진짜라면 ~5% 미만 확률의 사건 — 믿음 반증)
#   - q05~q95    → PASS_LOW_INFO    (모순 없음. "검증됨" 아님 — 저정보 명시, 성과 해석 금지)
#   - > q95      → PASS_PLUS        (기대 이상)
#
# 규율:
#   ① 사전등록: 구간은 holdout 열람 *전에* 기록 (build → save). 기존 파일 overwrite 금지.
#   ② 소모: holdout 열람 후 파라미터 수정 시 mark_consumed() — 새 봉인 구간 누적 전 재판정 금지.
#   ③ 라이브 연장: 채택 후 페이퍼/실측 월수익은 holdout의 자동 연장 — judge_holdout()를
#      trailing live window에 동일 적용 (monitoring 월간 대조; 하단 침범 → alert, 퇴출은 도훈 수동).
#
# 통계: 이동블록 부트스트랩 (block=12개월, IS+OOS 월수익 재추출) — 시계열 의존성 보존.
#   진단/규약용 통계이며 백테스트 성과 합성이 아님 (backtest-contract 비적용 영역, metric_type=diagnostic).
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite) })

# ── 사전등록 구간 생성 ─────────────────────────────────────────────────────────
# returns_monthly : 채택 시점까지의 월간 수익률 벡터 (IS+OOS — holdout/live 미포함)
# holdout_months  : 봉인 구간 길이 (기본 21 = 18~24 중앙)
# 반환: list(q05, q95, sr_input, n_input, holdout_months, block, B, seed, ...)
build_holdout_interval <- function(returns_monthly, holdout_months = 21L,
                                   block = 12L, B = 4000L, seed = 7L,
                                   strategy_id = NA_character_) {
  r <- as.numeric(returns_monthly); r <- r[is.finite(r)]; n <- length(r)
  stopifnot(n >= 60L, holdout_months >= 6L, block >= 2L)
  sr <- function(x) if (sd(x) > 0) mean(x) / sd(x) * sqrt(12) else NA_real_
  set.seed(seed)
  nb <- ceiling(holdout_months / block)
  boot <- replicate(B, {
    st <- sample.int(n - block + 1L, nb, replace = TRUE)
    x <- unlist(lapply(st, function(s) r[s:(s + block - 1L)]))[seq_len(holdout_months)]
    sr(x)
  })
  boot <- boot[is.finite(boot)]
  q <- stats::quantile(boot, c(0.05, 0.95), names = FALSE)
  list(schema_version = "c3_v1.0",
       strategy_id    = strategy_id,
       generated      = as.character(Sys.Date()),
       n_input_months = n,
       sr_input       = round(sr(r), 4),
       holdout_months = as.integer(holdout_months),
       block = as.integer(block), B = as.integer(B), seed = as.integer(seed),
       q05 = round(q[1], 4), q95 = round(q[2], 4),
       boot_median = round(stats::median(boot), 4),
       consumed = FALSE, consumed_reason = NA_character_,
       note = "사전등록 예측구간. 판정은 judge_holdout(). 열람 후 수정 시 mark_consumed() 의무 (C3 소모 규칙).")
}

# ── 사전등록 저장 (불변 — 존재 시 overwrite 거부) ───────────────────────────────
save_holdout_interval <- function(interval, path, overwrite = FALSE) {
  if (file.exists(path) && !isTRUE(overwrite))
    stop(sprintf("[C3] 사전등록 구간 이미 존재 — overwrite 금지(불변 원칙): %s", path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_json(interval, path, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 6)
  invisible(path)
}

# ── 판정 (holdout 또는 trailing live window 공용) ──────────────────────────────
# realized_monthly : 봉인 구간(또는 라이브 trailing window)의 실측 월수익률
judge_holdout <- function(interval, realized_monthly, window_label = "holdout") {
  if (isTRUE(interval$consumed))
    stop(sprintf("[C3] 이 구간은 소모됨(%s) — 새 봉인 구간 누적 전 재판정 금지.", interval$consumed_reason))
  x <- as.numeric(realized_monthly); x <- x[is.finite(x)]
  if (length(x) < 6L) return(list(verdict = "INSUFFICIENT", n = length(x),
                                  note = "실측 6개월 미만 — 판정 보류"))
  sr_real <- if (sd(x) > 0) mean(x) / sd(x) * sqrt(12) else NA_real_
  verdict <- if (!is.finite(sr_real)) "INSUFFICIENT"
             else if (sr_real < interval$q05) "FAIL_FALSIFIED"
             else if (sr_real > interval$q95) "PASS_PLUS"
             else "PASS_LOW_INFO"
  list(verdict = verdict, window = window_label, n = length(x),
       realized_sr = round(sr_real, 4),
       interval = c(q05 = interval$q05, q95 = interval$q95),
       note = switch(verdict,
         FAIL_FALSIFIED = "사전 예측구간 하단 미만 — 믿음 반증. 도훈 보고 의무 (자동 퇴출 아님).",
         PASS_LOW_INFO  = "구간 내 — 모순 없음. 저정보: 구간 내 위치로 우열 해석 금지.",
         PASS_PLUS      = "구간 상단 초과 — 기대 이상.",
         "표본 부족"))
}

# ── 소모 처리 (열람 후 파라미터 수정 시 의무) ──────────────────────────────────
mark_consumed <- function(path, reason) {
  iv <- fromJSON(path, simplifyVector = TRUE)
  iv$consumed <- TRUE; iv$consumed_reason <- as.character(reason)
  iv$consumed_date <- as.character(Sys.Date())
  write_json(iv, path, auto_unbox = TRUE, pretty = TRUE, na = "null", digits = 6)
  invisible(iv)
}

if (sys.nframe() == 0) cat("[holdout_falsification] Loaded — build_holdout_interval / save / judge_holdout / mark_consumed (C3).\n")
