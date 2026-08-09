#==============================================================================
# compute_consensus.R — Consensus / Earnings Factor 계산 모듈 (C01~C08)
#
# 함수: compute_consensus(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL)
# 반환: data.table(Ticker, Factor_Name, Raw_Value)
#
# PIT 준수: Date <= sig_date for consensus data
# CONSENSUS 스키마: Date, Ticker, sue, eps_chg_1m, eps_chg_3m, esbr, escr,
#                   target_price, coverage (+ 기타)
#==============================================================================
suppressPackageStartupMessages({
  library(data.table)
})

#------------------------------------------------------------------------------
# .cons_history() — CONSENSUS 원천에서 지표 1종의 PIT 이력을 직접 꺼낸다
#
# ★2026-08-08 수리(FQ-163)의 핵심. 구 코드는 병합 산출물 `cons` 를 `%in% names(cons)`
#   로 훑어 지표를 찾았는데, 성능 리팩터가 `cons` 를 (Ticker, Date) 2열로 줄이면서
#   그 조건이 **영구 거짓**이 됐고 7개 블록이 442개월 전 구간 0행이 됐다.
#   병합 산출물을 다시 뚱뚱하게 만드는 대신(리팩터 의도 보존), 이력이 필요한 블록은
#   원천 CONSENSUS[[metric]] 를 직접 본다 — compute_momentum.R 의 M25/M26/M28 이
#   쓰는 형태가 정본이고 그 패턴을 따른다.
#
# 반환: data.table(Date, Ticker, <metric>) — Ticker 내 **최신이 먼저**(Date 내림차순).
#       하류 블록의 `.SD[1L]` / `x[1:n]` 규약이 이 정렬에 의존한다.
#       사용 불가 시 NULL (호출부가 사유를 구분해 보고한다).
#
# 주의: 원천 테이블을 참조 수정하지 않는다(컬럼 부분집합 = 새 data.table).
#------------------------------------------------------------------------------
.cons_history <- function(CONSENSUS, metric, sig_d) {
  if (!is.list(CONSENSUS) || length(CONSENSUS) == 0L) return(NULL)
  src <- CONSENSUS[[metric]]
  if (is.null(src) || !is.data.table(src) || nrow(src) == 0L) return(NULL)
  if (!all(c("Date", "Ticker", metric) %in% names(src))) return(NULL)
  h <- src[, c("Date", "Ticker", metric), with = FALSE]
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[Date <= sig_d & !is.na(get(metric))]
  if (nrow(h) == 0L) return(NULL)
  setorderv(h, c("Ticker", "Date"), c(1L, -1L))
  h[]
}

#------------------------------------------------------------------------------
# .cons_quarters() — 창의 단위를 "관측 행"이 아니라 "분기 릴리스"로 바꾼다
#
# ★2026-08-10 수리(FQ-218). .cons_history() 는 **행**을 최신순으로 준다. 그런데
#   원천 sue/esbr 은 **일간 캐리포워드**(관측 간격 중앙 1일)이고 값은 분기에 한 번만
#   바뀐다(변경 간격 중앙 91일). 그래서 `mean(sue[1:4])` 는 4분기가 아니라 3~5일을
#   평균했고, 창 안 고유값이 1개뿐이라 **이동평균이 항등변환**이 됐다:
#     mean == latest 비율 1.0000 (2010/2018/2024 전 티커) ⇒ C10 ≡ C01, C13 ≡ C04,
#     C15(= 최신 − 차상위)는 전 종목 0 ⇒ 횡단면 sd 0 ⇒ 소비면 도달 0행.
#
# 창 정의 = **연속-런(run) 붕괴 후 최신 n_take 런**. 실측 근거(3안 비교):
#   W0 최신 N행(현행)  : mean==latest 1.0000 · 창 고유값 1 · span 2~4일
#   W1 런 dedup(채택)  : 0.124~0.154   · 고유값 = n_take · span 중앙 273~362일
#   W2 달력 lag 3M     : 0.610~0.633   · 고유값 1 · span 중앙 0  ← 앵커가 전부
#   W3 달력 lag 4M     : 0.584~0.601   · 고유값 1 · span 중앙 0     같은 관측에 붙어
#                                                                   결함이 재발
#   (stage_artifacts/infra/cons_window_repair_20260810/p3_design_agg.csv)
#
# ★PIT: 런 경계 = 값이 패널에 **처음 나타난 날** = 가용일이다. 실측으로 확인했다 —
#   값 변경은 100% 4/6/9/12월의 **첫 영업일**(월초 1~3일 100%, 월말 0%, 주말 0건)에
#   일어나고, 이는 한국 분기 법정 제출기한 **이후**다. 즉 분기 종료일 스탬프가
#   아니라 벤더의 분기 일괄 공표일이다(p2_pit_convention.csv). 게다가 런은 이미
#   Date <= sig_d 로 자른 조각 위에서만 계산하므로 미래 관측이 런 경계를 못 바꾼다.
#
# ★stale 소급 차단: 런 기반은 그냥 두면 무한히 뒤로 간다(실측 max span 7,424일 =
#   20년). 커버리지가 끊긴 종목의 "최근 4분기"는 2005년 평균일 수 있다. 그래서
#   max_lookback_days 상한을 둔다. 상수 = n_take * 130 (정상 분기 간격 최대 121일
#   + 여유). 검증: 패널에 살아있는 정상격자 종목의 oldest-run age 는
#   p50=p95=p99=301.5일 · 최대 348일(sue) / 최대 302일(esbr) 이라
#   frac_within_bound = 1.000 — 상한이 legit 창을 **하나도 자르지 않는다**
#   (p6_bound_validate.csv). 상한은 오직 stale 소급만 막는다.
#
# ★min_runs: 상한 적용 후 런이 min_runs 미만이면 값을 만들지 않는다(NA).
#   억지로 1런으로 평균을 내면 곧 avg == latest 로 결함이 되살아난다.
#
# ★동률 병합은 남는 한계다: 인접 런 시작일 간격이 2분기 이상인 비율이
#   sue 12.7% / esbr 15.6% (커버리지 공백 또는 두 분기 값이 같아 런이 합쳐진 경우).
#   즉 창은 "최근 n_take 분기"가 아니라 "최근 n_take **개의 서로 다른 릴리스 값**"
#   이며, 상한이 그 소급 폭을 묶는다. 이 정의는 registry definition 과 함께 읽어야 한다.
#
# ★.cons_history() 의 계약은 바꾸지 않는다 — C11/C14/C17/C18 이 그 정렬 규약에
#   의존하고 있고(C14/C17 은 연속 개정 계열이라 63일 달력 lag 가 이미 정합),
#   계약을 바꾸면 이번 수리의 범위를 넘어 그 블록들까지 움직인다. 새 헬퍼를 더한다.
#
# 반환: data.table(Ticker, slot, value, run_start, run_end, n_used)
#       slot 1 = 최신 릴리스. 사용 가능 종목 없으면 NULL.
#------------------------------------------------------------------------------
.CONS_TIE_TOL         <- 1e-12   # 부동소수 잡음을 새 분기로 오인하지 않게
.CONS_QUARTER_GAP_MAX <- 130L    # 관측된 정상 분기 간격 최대 121일 + 여유

.cons_quarters <- function(hist, metric, sig_d, n_take,
                           max_lookback_days = n_take * .CONS_QUARTER_GAP_MAX,
                           min_runs = 2L) {
  if (is.null(hist) || !is.data.table(hist) || nrow(hist) == 0L) return(NULL)
  if (!all(c("Date", "Ticker", metric) %in% names(hist))) return(NULL)
  h <- hist[, c("Ticker", "Date", metric), with = FALSE]
  setnames(h, metric, "value")
  h <- h[!is.na(value)]
  if (nrow(h) == 0L) return(NULL)
  if (!inherits(h$Date, "Date")) h[, Date := as.Date(Date)]
  h <- h[Date <= sig_d]                      # PIT — 호출부를 신뢰하지 않고 다시 자른다
  if (nrow(h) == 0L) return(NULL)

  # 오름차순에서 런 경계를 벡터 1패스로 잡는다(그룹 반복 없음 = 440개월 빌드 비용 억제).
  setorderv(h, c("Ticker", "Date"), c(1L, 1L))
  h[, newrun := is.na(shift(value)) | Ticker != shift(Ticker) |
                abs(value - shift(value)) > .CONS_TIE_TOL]
  h[, runid := cumsum(newrun)]
  rt <- h[, .(Ticker = Ticker[1L], value = value[1L],
              run_start = min(Date), run_end = max(Date)), by = runid]

  setorderv(rt, c("Ticker", "run_start"), c(1L, -1L))   # slot 1 = 최신 릴리스
  rt[, slot := seq_len(.N), by = Ticker]
  rt <- rt[slot <= n_take]
  # 상한은 항상 slot 접미를 자른다(run_start 는 slot 증가에 따라 단조 감소)
  rt <- rt[as.integer(sig_d - run_start) <= max_lookback_days]
  if (nrow(rt) == 0L) return(NULL)
  rt[, n_used := .N, by = Ticker]
  rt <- rt[n_used >= min_runs]
  if (nrow(rt) == 0L) return(NULL)
  rt[, .(Ticker, slot, value, run_start, run_end, n_used)]
}

#------------------------------------------------------------------------------
# 정본 위임 — 계산은 하되 배출하지 않는 팩터
#
# registry(factor_registry.json) 의 lifecycle.status="deprecated" 와 **짝을 이룬다**.
# 한쪽만 바꾸면 배출 감시(emission_guard.R)가 곧바로 불일치를 경고한다.
# ★블록 자체는 계속 실행한다 — 코드가 죽은 채 방치되는 것이 이번 사고의 기전이었다.
#   실행돼야 깨질 때 깨진다. 배출만 선언적으로 막는다.
#------------------------------------------------------------------------------
.CONSENSUS_DEPRECATED <- c(
  "C14_Revenue_Surprise" = "M26_Revenue_Mom",
  "C17_OP_Revision"      = "M28_OP_Rev_Mom"
)

compute_consensus <- function(RAWDATA, sig_date, FUND = NULL, CONSENSUS = NULL) {
  sig_d <- as.Date(sig_date)
  results <- list()

  # ── 스킵 사유 수집 ─────────────────────────────────────────────────────────
  # ★조용한 스킵이 이번 사고의 기전이므로, 스킵은 반드시 흔적을 남긴다.
  #   단 1990~2000년대처럼 CONSENSUS 자체가 비는 vintage 에서 블록마다 warning()
  #   을 때리면 440개월 빌드가 경고로 뒤덮여 오히려 안 보이게 된다. 그래서
  #   **정체를 구분**한다: 원천 전체 부재(정상 vintage) = 조용한 1줄 요약,
  #   원천은 있는데 특정 지표만 부재 = warning() (이상 신호).
  .skips <- character(0)
  .note_skip <- function(factor_name, metric, have_source) {
    .skips <<- c(.skips, sprintf("%s(%s)", factor_name, metric))
    if (isTRUE(have_source)) {
      warning(sprintf(
        "[compute_consensus] %s 스킵 — CONSENSUS 는 로드됐으나 '%s' 테이블 부재/무효 (sig_date=%s)",
        factor_name, metric, as.character(sig_d)), call. = FALSE)
    }
    invisible(NULL)
  }
  .have_cons <- is.list(CONSENSUS) && length(CONSENSUS) > 0L

  # --- CONSENSUS is a named list of data.tables (e.g. CONSENSUS$sue, CONSENSUS$eps_1y, ...) ---
  # Merge all sub-tables into one wide data.table keyed by (Date, Ticker)
  if (!is.list(CONSENSUS) || length(CONSENSUS) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # ── Performance-optimized merge: extract latest per Ticker BEFORE joining ──
  # Old approach: Reduce(full-outer-join, 13 tables) → filter → last-per-ticker
  # New approach: filter → last-per-ticker per table → merge small tables (2506 rows each)
  latest_parts <- list()
  for (nm in names(CONSENSUS)) {
    sub <- CONSENSUS[[nm]]
    if (!is.data.table(sub) || nrow(sub) == 0L || !all(c("Date", "Ticker") %in% names(sub))) next
    if (!inherits(sub$Date, "Date")) sub[, Date := as.Date(Date)]
    sub_pit <- sub[Date <= sig_d]
    if (nrow(sub_pit) == 0L) next
    setorder(sub_pit, Ticker, Date)
    latest_sub <- sub_pit[, .SD[.N], by = Ticker]
    # Keep only Ticker, Date, and metric columns (drop duplicate Date from later merges)
    metric_cols <- setdiff(names(latest_sub), c("Ticker", "Date"))
    if (length(metric_cols) == 0L) next
    latest_parts[[nm]] <- latest_sub[, c("Ticker", "Date", metric_cols), with = FALSE]
  }

  if (length(latest_parts) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  # Now merge the small latest-per-ticker tables (each ~2506 rows max)
  # Take max Date from each part for the final "latest date" column
  latest <- latest_parts[[1L]]
  if (length(latest_parts) > 1L) {
    for (i in seq(2L, length(latest_parts))) {
      part <- latest_parts[[i]]
      # Rename "Date" to avoid collision; we'll resolve after
      metric_cols_i <- setdiff(names(part), c("Ticker", "Date"))
      part_sub <- part[, c("Ticker", metric_cols_i), with = FALSE]
      latest <- merge(latest, part_sub, by = "Ticker", all = TRUE)
    }
  }
  # ★2026-08-08 FQ-163: 구 `cons` 슬림 재구성 블록을 **삭제**했다.
  #   구 주석("some C07 code references it")은 사실이 아니었다 — C07 은 아래
  #   cons_for_lag 를 쓴다. `cons` 를 남겨두는 한 하류가 `%in% names(cons)` 로
  #   지표를 찾다 조용히 거짓이 되는 길이 열려 있으므로 변수를 없앤다.
  #   ★이제 누가 `names(cons)` 를 다시 쓰면 "object 'cons' not found" 로 **즉시**
  #     실패한다. 결손이 정상 분기(스킵)로 내려앉지 않는 것이 요점이다.
  #   이력이 필요한 블록(C10/C11/C13/C14/C15/C17/C18)은 .cons_history() 로
  #   원천 CONSENSUS[[metric]] 를 직접 본다.

  # C07 의 lag 조회용 target_price 이력 (원천 직참조)
  cons_for_lag <- NULL
  if ("target_price" %in% names(latest)) {
    tp_src <- CONSENSUS[["target_price"]]
    if (!is.null(tp_src) && nrow(tp_src) > 0L) {
      if (!inherits(tp_src$Date, "Date")) tp_src[, Date := as.Date(Date)]
      cons_for_lag <- tp_src[Date <= sig_d]
      setorder(cons_for_lag, Ticker, Date)
    }
  }

  # --- C01: SUE (Standardized Unexpected Earnings) ---
  if ("sue" %in% names(latest)) {
    c01 <- latest[!is.na(sue), .(Ticker, Factor_Name = "C01_SUE", Raw_Value = sue)]
    if (nrow(c01) > 0) results[["C01"]] <- c01
  }

  # --- C02: EPS Change 1m ---
  if ("eps_chg_1m" %in% names(latest)) {
    c02 <- latest[!is.na(eps_chg_1m), .(Ticker, Factor_Name = "C02_EPS_Chg_1m", Raw_Value = eps_chg_1m)]
    if (nrow(c02) > 0) results[["C02"]] <- c02
  }

  # --- C03: EPS Change 3m ---
  if ("eps_chg_3m" %in% names(latest)) {
    c03 <- latest[!is.na(eps_chg_3m), .(Ticker, Factor_Name = "C03_EPS_Chg_3m", Raw_Value = eps_chg_3m)]
    if (nrow(c03) > 0) results[["C03"]] <- c03
  }

  # --- C04: ESBR (Earnings Sentiment Breadth Ratio) ---
  if ("esbr" %in% names(latest)) {
    c04 <- latest[!is.na(esbr), .(Ticker, Factor_Name = "C04_ESBR", Raw_Value = esbr)]
    if (nrow(c04) > 0) results[["C04"]] <- c04
  }

  # --- C05: ESCR (Earnings Sentiment Consistency Ratio) ---
  if ("escr" %in% names(latest)) {
    c05 <- latest[!is.na(escr), .(Ticker, Factor_Name = "C05_ESCR", Raw_Value = escr)]
    if (nrow(c05) > 0) results[["C05"]] <- c05
  }

  # --- C06: TP Gap = (Target Price - Close) / Close ---
  if ("target_price" %in% names(latest)) {
    # Close from RAWDATA at sig_date — use .pit_rawdata pattern (setkey already applied)
    rd_snap <- RAWDATA[Date == sig_d]
    if (nrow(rd_snap) == 0L) {
      # sig_d may be non-trading day; take most recent available trading day
      avail_d <- sort(unique(RAWDATA$Date[RAWDATA$Date <= sig_d]))
      if (length(avail_d) > 0L) rd_snap <- RAWDATA[Date == avail_d[length(avail_d)]]
    }
    rd_latest <- rd_snap

    if ("Close" %in% names(rd_latest) && nrow(rd_latest) > 0) {
      tp_merged <- merge(
        latest[!is.na(target_price), .(Ticker, target_price)],
        rd_latest[!is.na(Close) & Close > 0, .(Ticker, Close)],
        by = "Ticker"
      )
      if (nrow(tp_merged) > 0) {
        c06 <- tp_merged[, .(Ticker, Factor_Name = "C06_TP_Gap",
                             Raw_Value = (target_price - Close) / Close)]
        c06 <- c06[is.finite(Raw_Value)]
        if (nrow(c06) > 0) results[["C06"]] <- c06
      }
    }
  }

  # --- C07: TP Momentum = delta(target_price, 35d lag) / target_price ---
  if ("target_price" %in% names(latest)) {
    lag_date <- sig_d - 35
    # Current TP: latest
    tp_curr <- latest[!is.na(target_price), .(Ticker, tp_curr = target_price)]

    # Lagged TP: use cons_for_lag (slim target_price history table)
    cons_lag <- if (!is.null(cons_for_lag)) cons_for_lag[Date <= lag_date] else NULL
    if (!is.null(cons_lag) && nrow(cons_lag) > 0) {
      setorder(cons_lag, Ticker, Date)
      tp_lag <- cons_lag[!is.na(target_price), .SD[.N], by = Ticker]
      tp_lag <- tp_lag[, .(Ticker, tp_lag = target_price)]

      tp_both <- merge(tp_curr, tp_lag, by = "Ticker")
      tp_both <- tp_both[tp_lag > 0]
      if (nrow(tp_both) > 0) {
        c07 <- tp_both[, .(Ticker, Factor_Name = "C07_TP_Mom",
                           Raw_Value = (tp_curr - tp_lag) / tp_lag)]
        c07 <- c07[is.finite(Raw_Value)]
        if (nrow(c07) > 0) results[["C07"]] <- c07
      }
    }
  }

  # --- C08: Coverage (analyst count) ---
  if ("coverage" %in% names(latest)) {
    c08 <- latest[!is.na(coverage), .(Ticker, Factor_Name = "C08_Coverage", Raw_Value = as.numeric(coverage))]
    if (nrow(c08) > 0) results[["C08"]] <- c08
  }

  # ==========================================================================
  # C09~C19: Additional Earnings / Consensus Factors (from extraction report)
  # ==========================================================================

  # --- C09: Earnings Surprise (normalized) ---
  # (Actual - Forecast) / |Forecast|.  Different from SUE: no std normalization.
  # Uses sue as proxy if actual/forecast not separately available.
  # If we have eps_1y (forecast) and a way to get actual, compute directly.
  # For now, abs(sue) gives magnitude; sue itself is the standardized version.
  # Distinct metric: sign(sue) * sue^2 amplifies large surprises.
  if ("sue" %in% names(latest)) {
    c09 <- latest[!is.na(sue), .(Ticker, Factor_Name = "C09_Earnings_Surprise_Sq",
                                  Raw_Value = sign(sue) * sue^2)]
    c09 <- c09[is.finite(Raw_Value)]
    if (nrow(c09) > 0) results[["C09"]] <- c09
  }

  # ── SUE / ESBR 이력 (원천 직참조 — .cons_history 규약: 최신이 먼저) ────────
  sue_hist  <- .cons_history(CONSENSUS, "sue",  sig_d)
  esbr_hist <- .cons_history(CONSENSUS, "esbr", sig_d)

  # --- C10: Earnings Surprise Persistence (PEAD proxy) ---
  # 최근 4개 **분기 릴리스**의 SUE 평균 — persistent drift.
  # 구현: 구 코드는 최근 4개 **행**(=3~5일)을 평균해 mean==latest 항등이 됐다(FQ-218).
  if (!is.null(sue_hist)) {
    q10 <- .cons_quarters(sue_hist, "sue", sig_d, n_take = 4L)
    if (!is.null(q10)) {
      sue_avg <- q10[, .(sue_avg4 = mean(value)), by = Ticker]
      c10 <- sue_avg[!is.na(sue_avg4) & is.finite(sue_avg4),
                      .(Ticker, Factor_Name = "C10_SUE_Persistence", Raw_Value = sue_avg4)]
      if (nrow(c10) > 0) results[["C10"]] <- c10
    } else {
      .note_skip("C10_SUE_Persistence", "sue(<2 quarterly releases in window)", .have_cons)
    }
  } else {
    .note_skip("C10_SUE_Persistence", "sue", .have_cons)
  }

  # --- C11: Earnings Streak (consecutive positive SUE count) ---
  # ⚠ M25_Earnings_Mom_Streak(compute_momentum.R:339-360)과 식·원천·정렬이 동일하다
  #   (2026-08-08 코드 대조). 정본 일원화는 registry 처분 사안이라 여기서 단독
  #   결정하지 않는다 — 배출은 유지하고 중복 판정을 별도 제안으로 올린다.
  if (!is.null(sue_hist)) {
    sue_streak <- sue_hist[, {
      streak <- 0L
      for (i in seq_len(.N)) {
        if (!is.na(sue[i]) && sue[i] > 0) streak <- streak + 1L else break
      }
      list(streak = as.numeric(streak))
    }, by = Ticker]
    c11 <- sue_streak[, .(Ticker, Factor_Name = "C11_Earnings_Streak", Raw_Value = streak)]
    if (nrow(c11) > 0) results[["C11"]] <- c11
  } else {
    .note_skip("C11_Earnings_Streak", "sue", .have_cons)
  }

  # --- C12: Estimate Dispersion (forecast std / |mean forecast|) ---
  # DATA_NEEDED: analyst-level EPS forecasts for proper dispersion
  # Proxy: use coverage & eps_1y to flag — if we had individual forecasts,
  # dispersion = sd(forecasts) / |mean(forecasts)|.
  # For now, return NA with comment.
  # Possible proxy: |eps_chg_1m - eps_chg_3m| / |eps_1y| as disagreement signal.
  if (all(c("eps_chg_1m", "eps_chg_3m", "eps_1y") %in% names(latest))) {
    c12 <- latest[!is.na(eps_chg_1m) & !is.na(eps_chg_3m) & !is.na(eps_1y) & abs(eps_1y) > 1e-6,
                   .(Ticker, Factor_Name = "C12_Estimate_Dispersion_Proxy",
                     Raw_Value = abs(eps_chg_1m - eps_chg_3m) / abs(eps_1y))]
    c12 <- c12[is.finite(Raw_Value)]
    if (nrow(c12) > 0) results[["C12"]] <- c12
  }

  # --- C13: Revision Breadth (smoothed ESBR — C04 는 최신 1개 릴리스) ---
  # 최근 3개 **분기 릴리스**의 ESBR 평균.
  # ⚠ 이름의 "3m" 은 원 코드가 관측을 월간이라 **가정**한 데서 왔다. 원천은 분기
  #   릴리스이므로 3 관측 = 3분기(≈9개월)다. 이름 재사용 금지 규약상 여기서 개명하지
  #   않는다 — registry definition 에 창 = (3 릴리스, 상한 390일)로 명시할 사안이다.
  if (!is.null(esbr_hist)) {
    q13 <- .cons_quarters(esbr_hist, "esbr", sig_d, n_take = 3L)
    if (!is.null(q13)) {
      esbr_avg <- q13[, .(esbr_avg3 = mean(value)), by = Ticker]
      c13 <- esbr_avg[!is.na(esbr_avg3) & is.finite(esbr_avg3),
                       .(Ticker, Factor_Name = "C13_Revision_Breadth_3m", Raw_Value = esbr_avg3)]
      if (nrow(c13) > 0) results[["C13"]] <- c13
    } else {
      .note_skip("C13_Revision_Breadth_3m", "esbr(<2 quarterly releases in window)", .have_cons)
    }
  } else {
    .note_skip("C13_Revision_Breadth_3m", "esbr", .have_cons)
  }

  # --- C14: Revenue Surprise (consensus revenue_fy1 change) ---
  # Jegadeesh-Livnat (2006): revenue surprises add incremental predictive power.
  # 63일 컨센서스 개정률 — C14(revenue) / C17(op_profit) 공통 계산
  # compute_momentum.R M26/M28 과 동일 식·동일 lag·동일 가드.
  .revision_63d <- function(hist, metric, factor_name) {
    if (is.null(hist)) return(NULL)
    lag_d <- sig_d - 63L
    now <- hist[, .SD[1L], by = Ticker][, .(Ticker, v_now = get(metric))]
    lagt <- hist[Date <= lag_d]
    if (nrow(lagt) == 0L) return(NULL)
    lagt <- lagt[, .SD[1L], by = Ticker][, .(Ticker, v_lag = get(metric))]
    both <- merge(now, lagt, by = "Ticker")
    out <- both[abs(v_lag) > 1e-6,
                .(Ticker, Factor_Name = factor_name,
                  Raw_Value = (v_now - v_lag) / abs(v_lag))]
    out <- out[is.finite(Raw_Value)]
    if (nrow(out) == 0L) return(NULL)
    out
  }

  rev_hist <- .cons_history(CONSENSUS, "revenue_fy1", sig_d)
  if (!is.null(rev_hist)) {
    c14 <- .revision_63d(rev_hist, "revenue_fy1", "C14_Revenue_Surprise")
    if (!is.null(c14)) results[["C14"]] <- c14
  } else {
    .note_skip("C14_Revenue_Surprise", "revenue_fy1", .have_cons)
  }

  # --- C15: Forecast Error Trend ---
  # SUE 의 분기간 변화: 최신 분기 릴리스 − 직전 분기 릴리스.
  # 구 코드는 sue[1]-sue[2] 를 **연속 행**(같은 날짜대)에서 취해 전 종목 0이었고,
  # 횡단면 sd 0 → Z 전건 NA → 소비면 도달 0행(50/50월 죽은 배출, FQ-210 축3a).
  if (!is.null(sue_hist)) {
    q15 <- .cons_quarters(sue_hist, "sue", sig_d, n_take = 2L)
    if (!is.null(q15)) {
      sue_delta <- q15[, .(sue_d = if (.N >= 2L) value[slot == 1L][1L] - value[slot == 2L][1L]
                                   else NA_real_), by = Ticker]
      c15 <- sue_delta[!is.na(sue_d) & is.finite(sue_d),
                        .(Ticker, Factor_Name = "C15_Forecast_Error_Trend", Raw_Value = sue_d)]
      if (nrow(c15) > 0) results[["C15"]] <- c15
    } else {
      .note_skip("C15_Forecast_Error_Trend", "sue(<2 quarterly releases in window)", .have_cons)
    }
  } else {
    .note_skip("C15_Forecast_Error_Trend", "sue", .have_cons)
  }

  # --- C16: EPS Acceleration (eps_chg_1m - eps_chg_3m / 3) ---
  # Recent revision speed vs longer-term average revision speed.
  if (all(c("eps_chg_1m", "eps_chg_3m") %in% names(latest))) {
    c16 <- latest[!is.na(eps_chg_1m) & !is.na(eps_chg_3m),
                   .(Ticker, Factor_Name = "C16_EPS_Acceleration",
                     Raw_Value = eps_chg_1m - eps_chg_3m / 3)]
    c16 <- c16[is.finite(Raw_Value)]
    if (nrow(c16) > 0) results[["C16"]] <- c16
  }

  # --- C17: OP Profit Revision (consensus operating profit change) ---
  op_hist <- .cons_history(CONSENSUS, "op_profit_fy1", sig_d)
  if (!is.null(op_hist)) {
    c17 <- .revision_63d(op_hist, "op_profit_fy1", "C17_OP_Revision")
    if (!is.null(c17)) results[["C17"]] <- c17
  } else {
    .note_skip("C17_OP_Revision", "op_profit_fy1", .have_cons)
  }

  # --- C18: Abnormal Returns around Earnings Announcements (3-day CAR proxy) ---
  # DATA_NEEDED: earnings_announcement_dates for true CAR
  # Proxy: for each ticker, find dates near SUE observations with large |SUE|
  # and compute 3-day cumulative abnormal return around those dates.
  # ★2026-08-08 FQ-163 수리 시 두 결함을 함께 고쳤다. 블록이 한 번도 실행된 적이
  #   없어(전 구간 0행) 드러난 적 없던 결함들이고, 그대로 되살리면 **미래참조를
  #   새로 주입**하는 셈이었다:
  #   (1) PIT 위반: 발표일 프록시 ad 를 sig_d 까지 허용한 뒤 [ad-3, ad+3] 창을
  #       썼다 → ad 가 sig_d 근방이면 sig_d **이후** 수익을 읽는다(C1/C2 위반).
  #       수리: 발표일 프록시를 Date <= sig_d - 3L 로 제한해 창 전체가 PIT 안에
  #       들어오게 한다. 부분 창으로 잘라 쓰면 종목마다 창 길이가 달라져
  #       횡단면 비교가 깨지므로, 창을 자르지 않고 **완전 관측 가능한 발표만** 쓴다.
  #   (2) 종목당 RAWDATA 전수 스캔(lapply + Ticker == tk) → 2,500회 비색인 스캔.
  #       수리: 1:다 조인 후 벡터 집계.
  #   (3) 신규 결정 — 발표일 프록시에 trailing 400일 상한을 둔다. SUE 가 수년째
  #       갱신 안 된 종목의 "직전 발표 CAR" 는 의미가 없고, 상한이 없으면
  #       RAWDATA 슬라이스가 전 역사로 벌어진다. 이 규칙은 신규 정의이며
  #       registry definition 과 함께 읽혀야 한다.
  .rd_ok <- is.data.table(RAWDATA) && nrow(RAWDATA) > 0 &&
            all(c("Ticker", "Date", "Ret", "BM_Ret") %in% names(RAWDATA))
  if (!is.null(sue_hist) && .rd_ok) {
    ann_cut <- sig_d - 3L          # 창 [ad-3, ad+3] 이 전부 sig_d 이하가 되도록
    ann_min <- sig_d - 400L        # trailing 상한 (3)
    ann_src <- sue_hist[Date <= ann_cut & Date >= ann_min]
    ann_dates <- if (nrow(ann_src) > 0L) {
      ann_src[, .(ann_date = Date[1L]), by = Ticker]   # .cons_history 정렬: 최신이 먼저
    } else {
      ann_src[0L][, .(Ticker = character(), ann_date = as.Date(character()))]
    }

    if (nrow(ann_dates) > 0L) {
      d_lo <- min(ann_dates$ann_date) - 3L
      rd <- RAWDATA[Date >= d_lo & Date <= sig_d, .(Ticker, Date, Ret, BM_Ret)]
      if (!inherits(rd$Date, "Date")) rd[, Date := as.Date(Date)]
      rd <- merge(rd, ann_dates, by = "Ticker")        # ann_dates 는 Ticker 당 1행
      rd <- rd[Date >= (ann_date - 3L) & Date <= (ann_date + 3L) &
                 !is.na(Ret) & !is.na(BM_Ret)]
      if (nrow(rd) > 0L) {
        car_dt <- rd[, .(n_obs = .N, car3d = sum(Ret - BM_Ret)), by = Ticker][n_obs >= 2L]
        c18 <- car_dt[is.finite(car3d),
                       .(Ticker, Factor_Name = "C18_Earnings_CAR_3d", Raw_Value = car3d)]
        if (nrow(c18) > 0) results[["C18"]] <- c18
      }
    }
  } else if (is.null(sue_hist)) {
    .note_skip("C18_Earnings_CAR_3d", "sue", .have_cons)
  } else {
    .note_skip("C18_Earnings_CAR_3d", "RAWDATA(Ret/BM_Ret)", TRUE)
  }

  # --- C19: Composite Earnings Factor ---
  # z(SUE) + z(ESBR) + z(EPS_chg_1m) + z(TP_Gap).  At least 2 of 4 required.
  z_safe <- function(x) {
    s <- sd(x, na.rm = TRUE)
    if (is.na(s) || s < 1e-8) return(rep(NA_real_, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }

  # Build a wide table from existing results for compositing
  comp_cols <- c("C01_SUE", "C04_ESBR", "C02_EPS_Chg_1m", "C06_TP_Gap")
  comp_list <- list()
  for (cc in comp_cols) {
    if (cc %in% names(results)) {
      tmp <- results[[sub("C0[0-9]_", "", cc)]]
    }
    # Try to find by iterating
    tmp <- NULL
    for (nm in names(results)) {
      if (grepl(cc, results[[nm]]$Factor_Name[1], fixed = TRUE)) {
        tmp <- results[[nm]]
        break
      }
    }
    if (!is.null(tmp) && nrow(tmp) > 0) {
      short_name <- gsub("^C[0-9]+_", "", cc)
      setnames_tmp <- copy(tmp)[, .(Ticker, val = Raw_Value)]
      setnames(setnames_tmp, "val", short_name)
      comp_list[[short_name]] <- setnames_tmp
    }
  }

  if (length(comp_list) >= 2L) {
    comp_dt <- Reduce(function(a, b) merge(a, b, by = "Ticker", all = TRUE), comp_list)
    comp_names <- setdiff(names(comp_dt), "Ticker")
    for (cn in comp_names) {
      zcol <- paste0("z_", cn)
      comp_dt[, (zcol) := z_safe(get(cn))]
    }
    z_cols <- paste0("z_", comp_names)
    comp_dt[, n_c := rowSums(!is.na(.SD)), .SDcols = z_cols]
    comp_dt[n_c >= 2L, C19_val := rowMeans(.SD, na.rm = TRUE), .SDcols = z_cols]
    c19 <- comp_dt[!is.na(C19_val) & is.finite(C19_val),
                    .(Ticker, Factor_Name = "C19_Composite_Earnings", Raw_Value = C19_val)]
    if (nrow(c19) > 0) results[["C19"]] <- c19
  }

  # ── 스킵 흔적 (조용한 스킵 금지) ──────────────────────────────────────────
  if (length(.skips) > 0L) {
    cat(sprintf("  [compute_consensus] %s 스킵 %d종: %s (원천 로드=%s)\n",
                as.character(sig_d), length(.skips),
                paste(.skips, collapse = ", "), .have_cons))
  }

  # 결합
  if (length(results) == 0) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }
  out <- rbindlist(results, use.names = TRUE, fill = TRUE)

  # ── 정본 위임분 배출 보류 (계산은 이미 수행됨 — 죽은 코드로 두지 않는다) ──
  dep_names <- names(.CONSENSUS_DEPRECATED)
  if (any(out$Factor_Name %in% dep_names)) {
    hit <- out[Factor_Name %in% dep_names, .(n = .N), by = Factor_Name]
    for (i in seq_len(nrow(hit))) {
      fn <- hit$Factor_Name[i]
      cat(sprintf("  [compute_consensus] %s 배출 보류(deprecated, %d행 계산됨) — 정본 %s\n",
                  fn, hit$n[i], .CONSENSUS_DEPRECATED[[fn]]))
    }
    out <- out[!Factor_Name %in% dep_names]
  }
  if (nrow(out) == 0L) {
    return(data.table(Ticker = character(), Factor_Name = character(), Raw_Value = numeric()))
  }

  out[, .(Ticker, Factor_Name, Raw_Value)]
}

cat("[factor_db] compute_consensus.R loaded (C01~C19)\n")
