#==============================================================================
# Lookahead Detector — 미래참조 자동 검출 (C1~C9)
# run_all.R 실행 전 자동 스캔. 위반 시 실행 차단.
#
# 2026-09-24 (PIT C11 판정서 ⑤-8 방어선 · S6_defense): C3 macro/regime 면제 삭제 + C11 을 문자열
#   휴리스틱에서 파일 단위 계보 분석기로 교체(.la_c11_scan_r / .la_c11_scan_py — 규칙 정본
#   06_Registry/fred_availability_rules.json). 양방향 검사 = 08_Tests/validation/test_pit_c11_positive_control.R.
#
# 2026-07-03 (DATA-P1-4): .py 지원 추가 — Python 리서치(1급 언어, python-policy.md)
#   PIT 자동탐지 사각 해소. PY_* 패턴 블록 (shift(-N) / merge_asof forward /
#   full-sample fit-transform / bfill / centered rolling 등).
#
# Usage:
#   source("02_Infrastructure/validation/lookahead_detector.R")
#   result <- detect_lookahead("path/to/run_all.R")   # .R 또는 .py
#   if (!isTRUE(result$clean)) stop("Lookahead detected or NOT SCANNED!")
#   ★clean 은 3값이다: TRUE(스캔했고 위반 0) / FALSE(위반 있음) / NA(미스캔 — PASS 아님).
#    `!result$clean` 은 NA 에서 오류가 나므로 반드시 isTRUE() 로 받을 것.
#==============================================================================

detect_lookahead <- function(run_all_path, verbose = TRUE) {
  # [2026-08-02 수리 — "미스캔을 PASS 로 내려앉히지 말 것"]
  #  종전: 파일이 없으면 clean = TRUE 를 반환했다. 즉 **스캔을 0회 수행한 사실이
  #  '위반 없음(PIT 통과)'이라는 판정**이 됐다. 경로 오타·산출 지연·리네임만으로
  #  PIT lookahead 게이트가 무증상 통과한다 — AX-002 동급 노출.
  #  ★같은 기전의 다른 얼굴: lineage_utils 의 git_dirty(호출 실패 → 0행 → "clean tree").
  #  정본: 미측정은 NA(+scanned=FALSE+error). 소비부는 전부 isTRUE(pit$clean) 를 쓰므로
  #  (10개 alpha_search 러너 · hook_batch_runner · backfill) NA 는 자동으로 not-clean 이 된다.
  #  backfill_alpha_search_contracts.R:151 이 이미 "파일 없음 → clean = NA" 규약을 쓰고 있었고,
  #  검출기 본체만 어긋나 있었다.
  if (!file.exists(run_all_path)) {
    if (verbose) cat("[lookahead] File not found (미스캔 — PASS 아님):", run_all_path, "\n")
    return(list(clean = NA, scanned = FALSE, violations = list(),
                file = run_all_path, n_violations = 0L,
                error = sprintf("scan not performed — file not found: %s", run_all_path)))
  }

  lines <- readLines(run_all_path, warn = FALSE)
  n_lines <- length(lines)
  violations <- list()

  # File-type dispatch: .py → Python idiom scan / else → R scan (기존 경로 유지)
  is_python <- grepl("\\.py$", run_all_path, ignore.case = TRUE)

  # Helper: get context window (surrounding lines as single string)
  get_context <- function(i, window = 5) {
    start <- max(1L, i - window)
    end   <- min(n_lines, i + window)
    paste(lines[start:end], collapse = " ")
  }

  # Helper: add violation
  add_violation <- function(check, line_num, code, msg) {
    violations[[length(violations) + 1L]] <<- list(
      check = check,
      line  = line_num,
      code  = trimws(code),
      msg   = msg
    )
  }

  c3_pending <- list()   # C3 동월 조회 후보 — C11 계보 분석기가 판정한 줄을 뺀 나머지를 루프 뒤에 낸다

  for (i in seq_along(lines)) {
    line <- lines[i]
    line_trimmed <- trimws(line)

    # Skip comments and empty lines
    if (grepl("^\\s*#", line) || nchar(line_trimmed) == 0) next

    # =========================================================================
    # PY_* block: Python lookahead idioms (.py 파일 전용 — 2026-07-03 DATA-P1-4)
    # R 패턴과 동일 구조 (check code + line + msg). .py이면 이 블록만 실행.
    # =========================================================================
    if (is_python) {

      # PY_C7_NEG_SHIFT: negative shift pulls future rows to present.
      # df.shift(-1) / .shift(periods=-3) / groupby().shift(-N)
      # 예외: forward label 구성으로 validate_label_direction() 검증이 context에
      # 명시된 경우만 (python-policy.md — forward label은 검증 의무와 함께 허용).
      if (grepl("\\.shift\\(\\s*-\\s*\\d|shift\\(\\s*periods\\s*=\\s*-\\s*\\d", line)) {
        ctx <- get_context(i, 10)
        if (!grepl("validate_label_direction", ctx)) {
          add_violation("PY_C7_NEG_SHIFT", i, line_trimmed,
            "Negative shift(-N) pulls FUTURE values to current row — direct lookahead. Forward labels must pass validate_label_direction() (python-policy.md); features must use shift(+N).")
        }
      }

      # PY_C10_PCT_CHANGE_FWD: pct_change with negative periods = forward return
      if (grepl("pct_change\\(\\s*-\\s*\\d|pct_change\\(\\s*periods\\s*=\\s*-\\s*\\d", line)) {
        add_violation("PY_C10_PCT_CHANGE_FWD", i, line_trimmed,
          "pct_change(-N) computes FORWARD return — direct lookahead if used as feature/signal.")
      }

      # PY_C7_FWD_FEATURE: ranking/sorting on forward/future return columns
      # (R C7b 등가)
      if (grepl("(fwd_ret|future_ret|next_ret|ret_fwd)", line, ignore.case = TRUE) &&
          grepl("(rank|sort_values|qcut|argsort|nlargest|nsmallest)", line, ignore.case = TRUE)) {
        add_violation("PY_C7_FWD_FEATURE", i, line_trimmed,
          "Ranking/sorting on forward/future returns detected. This is a direct lookahead (R C7b equivalent).")
      }

      # PY_C2_MERGE_ASOF_FWD: merge_asof direction='forward'/'nearest' joins
      # future rows onto current timestamp
      if (grepl("merge_asof", line) &&
          grepl("direction\\s*=\\s*['\"](forward|nearest)['\"]", line)) {
        add_violation("PY_C2_MERGE_ASOF_FWD", i, line_trimmed,
          "merge_asof(direction='forward'/'nearest') joins FUTURE rows. Use direction='backward' (default) for PIT.")
      }

      # PY_C1_FULLSAMPLE_FIT: scaler/transformer fit on full sample then applied
      # to history (fit-then-transform leak). rolling/expanding/train-split
      # context가 없으면 warn.
      if (grepl("fit_transform\\(|\\.fit\\(", line)) {
        ctx <- get_context(i, 10)
        is_scaler_ctx <- grepl("[Ss]caler|StandardScaler|MinMaxScaler|RobustScaler|QuantileTransformer|PCA|normalize", ctx)
        has_pit_ctx   <- grepl("train|split|expanding|rolling|walk.?forward|fold|\\bcv\\b|purg", ctx, ignore.case = TRUE)
        if ((grepl("fit_transform\\(", line) || is_scaler_ctx) && !has_pit_ctx) {
          add_violation("PY_C1_FULLSAMPLE_FIT", i, line_trimmed,
            "Full-sample fit/fit_transform without train-split or expanding/rolling context — global stats leak into past rows (R C7a scale() equivalent). Fit on train window only, transform forward.")
        }
      }

      # PY_C1_FULLSAMPLE_ZSCORE: (x - x.mean()) / x.std() on full column in
      # signal context, without rolling/expanding/date-groupby
      if (grepl("\\.mean\\(\\)", line) && grepl("\\.std\\(\\)", line)) {
        ctx <- get_context(i)
        if (grepl("Score|signal|weight|z_|zscore|rank", ctx, ignore.case = TRUE) &&
            !grepl("rolling|expanding|groupby\\([^)]*([Dd]ate|ym|month)", ctx)) {
          add_violation("PY_C1_FULLSAMPLE_ZSCORE", i, line_trimmed,
            "z-score using full-column .mean()/.std() in signal context — full-sample stats (C1). Use rolling/expanding window or per-date cross-sectional groupby.")
        }
      }

      # PY_C9_BFILL: backward fill propagates future values backward
      if (grepl("\\.bfill\\(|method\\s*=\\s*['\"](bfill|backfill)['\"]|fillna\\([^)]*['\"](bfill|backfill)['\"]", line)) {
        add_violation("PY_C9_BFILL", i, line_trimmed,
          "Backward fill (bfill) propagates FUTURE values to earlier rows. Use ffill for PIT-safe imputation.")
      }

      # PY_C5_ROLLING_CENTER: centered rolling window includes future observations
      if (grepl("rolling\\([^)]*center\\s*=\\s*True", line)) {
        add_violation("PY_C5_ROLLING_CENTER", i, line_trimmed,
          "rolling(center=True) window includes FUTURE observations. Use trailing window (center=False, default).")
      }

      # PY_C12_FULLSAMPLE_OPT: full-sample parameter optimization
      # (R C12와 동일 패턴 — 언어 무관 문자열)
      py_c12_patterns <- c("best_sharpe", "best_blend", "best_score.*=",
                           "grid.*sharpe", "if.*sr.*>.*best", "if.*sharpe.*>.*best")
      for (pat in py_c12_patterns) {
        if (grepl(pat, line_trimmed, ignore.case = TRUE)) {
          add_violation("PY_C12_FULLSAMPLE_OPT", i, line_trimmed,
            "Full-sample parameter optimization detected. Use expanding-window or pre-commit ratio.")
        }
      }

      next  # .py: R 전용 패턴은 건너뜀
    }

    # =========================================================================
    # C1: Full-sample statistics — sd/mean/var on full vector without rolling
    # =========================================================================
    # Pattern: sd(vector_name) * sqrt(252) without [1:i] or rollapply context
    # Targets time-series vol calculation on full sample
    if (grepl("\\bsd\\([a-zA-Z_]+\\)\\s*\\*\\s*sqrt", line)) {
      # Check CURRENT LINE only for expanding window markers
      has_expanding <- grepl("\\[1\\s*:\\s*[ij]\\]", line)
      has_rolling   <- grepl("rollapply|frollapply|frollmean|slider::", line)
      # Check current line for cross-sectional markers
      has_by <- grepl("by\\s*=|,\\s*by\\s*=|tapply|sapply.*Sector", line)
      if (!has_expanding && !has_rolling && !has_by) {
        add_violation("C1", i, line_trimmed,
          "sd() on full vector * sqrt() without rolling/expanding window — possible full-sample vol")
      }
    }

    # C1b: Full-sample quantile/ecdf used in signal construction
    if (grepl("\\b(quantile|ecdf)\\(\\w+\\$", line)) {
      ctx <- get_context(i)
      if (!grepl("\\[1\\s*:\\s*[ij]\\]|rollapply|expanding|by\\s*=", ctx) &&
          grepl("Score|signal|weight|z_|rank", ctx, ignore.case = TRUE)) {
        add_violation("C1b", i, line_trimmed,
          "quantile/ecdf on full column — verify not used for signal construction")
      }
    }

    # =========================================================================
    # C2/C5: VT scale applied without 1-day lag
    # =========================================================================
    # Pattern: after_vt <- X * vt_scale (missing "lagged" or shift)
    if (grepl("after_vt\\s*<-.*\\*\\s*vt_scale\\b", line) &&
        !grepl("lagged|lag|shift|\\[.*-\\s*1\\]", line)) {
      add_violation("C5_VT", i, line_trimmed,
        "VT scale applied without 1-day lag. Use vt_scale_lagged or shift().")
    }

    # =========================================================================
    # C2/C5: DD exposure applied without 1-day lag
    # =========================================================================
    # Pattern: after_dd <- X * dd_exp (not lagged)
    if (grepl("(after_dd|combined_ret)\\s*<-.*\\*\\s*dd_exp", line) &&
        !grepl("lagged|lag|shift", line)) {
      add_violation("C5_DD", i, line_trimmed,
        "DD exposure without 1-day lag. Use dd_exp_*_lagged or shift().")
    }

    # =========================================================================
    # C5: DD short window includes current day i
    # =========================================================================
    # Pattern: window_ret <- X[(i-19):i] or X[(i-20):i] (should be (i-1) end)
    if (grepl("\\(i\\s*-\\s*\\d+\\)\\s*:\\s*i\\s*\\]", line) &&
        grepl("window|dd|drawdown", line, ignore.case = TRUE)) {
      # Check it's not (i-20):(i-1) which is correct
      if (!grepl(":\\s*\\(\\s*i\\s*-\\s*1\\s*\\)", line)) {
        add_violation("C5_DDshort", i, line_trimmed,
          "DD/window calculation includes day i. Use (i-N):(i-1) to exclude current day.")
      }
    }

    # =========================================================================
    # C8: Factor Momentum weight uses same-day trailing return
    # =========================================================================
    # Pattern: rets <- c(cum_xxx[i], ...) without [i-1]
    # FM weight at day i must use trailing return as of day i-1
    if (grepl("rets\\s*<-\\s*c\\(cum_", line)) {
      # Count [i] vs [i-1] or [i - 1]
      n_same_day <- length(gregexpr("\\[i\\]", line)[[1]])
      n_lagged   <- length(gregexpr("\\[i\\s*-\\s*1\\]", line)[[1]])
      # If [i] references exist and no [i-1], it's same-day FM
      if (n_same_day > 0 && grepl("\\[i\\]", line) && !grepl("\\[i\\s*-\\s*1\\]", line)) {
        add_violation("C8_FM", i, line_trimmed,
          "FM weight uses day-i trailing return (same-day circular). Use [i-1] for 1-day lag.")
      }
    }

    # =========================================================================
    # C3: Same-month aggregate applied to same month (non-macro)
    # =========================================================================
    if (grepl("YM\\s*==\\s*(daily_ym|ym_i|current_ym)", line, ignore.case = TRUE)) {
      # [2026-09-24 면제 삭제 — PIT C11 판정서 ③·⑤-8, decision_register PIT-C11-CONVENTIONS ④]
      #  종전: 주변 5행에 mrs|macro|regime|fred **단어가 보이면** 통과("Macro/regime lookups are OK … monthly
      #  published"). 코드로 굳은 합리화였다 — VIX 는 일간이고, 월간 공표 계열을 같은 달에 쓴 것이 바로
      #  L-441(SR ~18% 과대)의 선례다. 이제 단어로 면제하지 않는다: 해외(FRED) 계보 표의 기간 조회는 줄 루프 뒤
      #  C11 계보 분석기가 lag 증거(전월 키·기간 이동·가용시점 층)로 판정하고(같은 달이면 C11_FRED_SAMEDATE),
      #  그 밖의 조회와 분석기가 판정하지 못한 줄(규칙 없음·파싱 실패 포함)은 C3 로 잡는다(아래 c3_pending 처리).
      c3_pending[[length(c3_pending) + 1L]] <- list(i = i, code = line_trimmed)
    }

    # =========================================================================
    # C4: Financial statement without proper lag
    # =========================================================================
    # Pattern: merge on Date == financial_date without lag
    if (grepl("(annual|quarterly|fiscal|재무)", line, ignore.case = TRUE) &&
        grepl("merge|join|\\[.*==", line, ignore.case = TRUE)) {
      ctx <- get_context(i, 8)
      if (!grepl("lag|shift|\\-\\s*(45|60|90|120|150)\\b|5월|리밸런싱", ctx, ignore.case = TRUE)) {
        add_violation("C4", i, line_trimmed,
          "Financial statement merge without visible lag. Annual->May rebal, Quarterly->45d+ lag required.")
      }
    }

    # =========================================================================
    # C6: Survivorship bias — using current universe for past dates
    # =========================================================================
    if (grepl("universe\\s*<-.*current|today|Sys\\.Date", line, ignore.case = TRUE) &&
        grepl("backtest|simulation|historical", get_context(i), ignore.case = TRUE)) {
      add_violation("C6", i, line_trimmed,
        "Possible survivorship bias: using current universe for historical backtest.")
    }

    # =========================================================================
    # C7: Automatic pattern detection — common lookahead anti-patterns
    # =========================================================================
    # 7a: scale/normalize using full-sample stats then apply to signal
    if (grepl("scale\\(\\w+\\)", line) && !grepl("by\\s*=|tapply|group", get_context(i))) {
      ctx <- get_context(i)
      if (grepl("Score|signal|weight|factor", ctx, ignore.case = TRUE)) {
        add_violation("C7a", i, line_trimmed,
          "scale() on full sample — uses global mean/sd. Use rolling z-score or cross-sectional z.")
      }
    }

    # 7b: Sort/rank on future returns
    if (grepl("(fwd_ret|future_ret|next_ret|ret_fwd)", line, ignore.case = TRUE) &&
        grepl("(rank|order|sort|ntile|cut)", line, ignore.case = TRUE)) {
      add_violation("C7b", i, line_trimmed,
        "Ranking on forward/future returns detected. This is a direct lookahead.")
    }

    # =========================================================================
    # C10: Liquidity filter includes today's volume (Session 38b)
    # =========================================================================
    # Pattern: frollmean(TradingValue or Close*Vol) without shift(lag)
    if (grepl("frollmean\\(.*[Tt]rad|frollmean\\(.*[Cc]lose.*[Vv]ol", line)) {
      ctx <- get_context(i, 3)
      if (!grepl("shift|lag", ctx, ignore.case = TRUE)) {
        add_violation("C10_LIQ", i, line_trimmed,
          "Liquidity filter (AvgTV) includes today volume. Use shift(frollmean(...), lag=1) to exclude today.")
      }
    }

    # =========================================================================
    # C11: Data timeline — 해외(FRED) 시계열 가용시점
    # =========================================================================
    # [2026-09-24 교체 — PIT C11 판정서 ③·⑤-8] 종전 C11_FRED("fred 읽는 줄 주변 10행에 shift|lag|1d 문자열")는
    #  문자열 휴리스틱이라 `verbose_flag`·paste0("macro_","fred.parquet") 돌연변이에서 거짓 음성, 올바르게 lag 한
    #  파일의 읽기 줄에서 거짓 양성을 냈고 실제 결합 지점을 가리키지 못했다. 줄 루프 뒤의 파일 단위 계보 분석기
    #  (.la_c11_scan_r / .la_c11_scan_py — 파일 하단 정의)가 대신한다. 규칙 = 06_Registry/fred_availability_rules.json.

    # C11b: Monthly regime applied to same month (MRS lookahead)
    if (grepl("YM\\s*==\\s*daily_ym|YM.*==.*format.*Date", line)) {
      ctx <- get_context(i, 8)
      if (grepl("Macro_Risk_Score|MRS|mrs_monthly|regime", ctx, ignore.case = TRUE) &&
          !grepl("lagged|shift|apply_month|전월|prev_month", ctx, ignore.case = TRUE)) {
        add_violation("C11_MRS", i, line_trimmed,
          "Monthly regime data applied to same month. Must use previous month's data or regime_engine_v4 with apply_month.")
      }
    }

    # =========================================================================
    # INV13: Foreign_Resid_Individual — 5종 PIT 패턴 (H_1685_v2 선결 조건)
    # =========================================================================
    # INV13_C1: beta_t must use shift(cum_SxY/cum_Sxx, 1L) — strict lag
    if (grepl("INV13|Foreign_Resid_Individual", line, ignore.case = TRUE)) {
      ctx <- get_context(i, 15)
      # Pattern 1: expanding beta without lag
      if (grepl("SxY\\s*/\\s*Sxx|cum_SxY.*Sxx|beta_t\\s*<-", ctx) &&
          !grepl("shift.*1L|shift.*1\\b|n_months.*>=.*60|burn.?in", ctx, ignore.case = TRUE)) {
        add_violation("INV13_C1_EXPANDING_LAG", i, line_trimmed,
          "INV13 beta_t must use shift(cum_SxY/cum_Sxx, 1L) with burn-in >= 60 months (C1 strict lag).")
      }
      # Pattern 2: date filter not strict less-than
      if (grepl("inv\\[Date\\s*(<=|==)", ctx)) {
        add_violation("INV13_C2_DATE_STRICT", i, line_trimmed,
          "INV13 investor data must use Date < sig_d (strict less-than, C2). Found <= or ==.")
      }
      # Pattern 3: manual sign flip on residual
      if (grepl("residual\\s*\\*\\s*-1|z_F\\s*\\*\\s*-1|-1\\s*\\*\\s*z_F", ctx)) {
        add_violation("INV13_C13_ZSCORE_ALIGNED", i, line_trimmed,
          "INV13 residual manual sign flip detected. Use Z_Score_Aligned pattern, no manual negation (C13).")
      }
    }
    # INV13_C11: Usable_Date check for investor flow data
    if (grepl("INV13|inv13|Foreign_Resid", line, ignore.case = TRUE)) {
      ctx <- get_context(i, 10)
      if (grepl("Usable_Date.*>|Date.*>.*sig|Date.*>=.*sig", ctx) &&
          !grepl("Usable_Date\\s*<=|Date\\s*<\\s*sig", ctx)) {
        add_violation("INV13_C11_TIMING", i, line_trimmed,
          "INV13 Usable_Date check may be reversed. Must use Usable_Date <= sig_date or Date < sig_d (C11).")
      }
    }

    # =========================================================================
    # C9: Vol equalization on full sample (critical — STR_759~765 failure)
    # =========================================================================
    # Pattern: sd(ret_xxx) without [1:i] — full sample vol eq
    if (grepl("\\bsd\\(ret_\\w+\\)", line) && grepl("scale|vol_eq|normalize", get_context(i), ignore.case = TRUE)) {
      if (!grepl("\\[1\\s*:\\s*[ij]\\]", line)) {
        add_violation("C9", i, line_trimmed,
          "Vol equalization using full-sample sd(ret_xxx). Must use expanding window [1:i].")
      }
    }

    # C12: Full-sample parameter optimization (blend ratio, weight grid search)
    # Selecting best parameters by comparing full-sample Sharpe/CAGR = lookahead
    c12_patterns <- c("best_sharpe", "best_blend", "best_score.*<-",
                       "quick_sharpe.*blended", "grid.*sharpe",
                       "if.*sr.*>.*best", "if.*sharpe.*>.*best")
    for (pat in c12_patterns) {
      if (grepl(pat, line_trimmed, ignore.case = TRUE)) {
        add_violation("C12_FULLSAMPLE_OPT", i, line_trimmed,
          "Full-sample parameter optimization detected. Use expanding-window or pre-commit ratio.")
      }
    }

    # C13: Manual direction negation (should use Z_Score_Aligned from connector)
    c13_patterns <- c("NEGATE_FACTORS", "FLIP_SIGN", "Z_Score\\s*:=\\s*-Z_Score",
                       "Z_Score\\s*\\*\\s*-1", "sign_adj.*-1")
    for (pat in c13_patterns) {
      if (grepl(pat, line_trimmed, ignore.case = FALSE)) {
        add_violation("C13_MANUAL_DIRECTION", i, line_trimmed,
          "Manual direction negation detected. Use Z_Score_Aligned from factor_db_connector instead.")
      }
    }

    # C14: IC access with <= (should use Usable_Date or strict < for Date)
    if (grepl("IC.*Date.*<=.*sig|ic_hist\\[Date\\s*<=", line_trimmed, ignore.case = TRUE)) {
      if (!grepl("Usable_Date", line_trimmed)) {
        add_violation("C14_IC_TIMING", i, line_trimmed,
          "IC access with <= on Date (not Usable_Date). IC[t] uses future return t->t+1. Use Usable_Date <= sig_d or Date < sig_d.")
      }
    }

    # C15: Direct parquet load bypassing connector
    if (grepl("read_parquet.*factor_db.*parquet|factor_db_\\d{6}", line_trimmed)) {
      if (!grepl("function|#|compute_all", line_trimmed)) {
        add_violation("C15_DIRECT_PARQUET", i, line_trimmed,
          "Direct Factor DB parquet load detected. Use load_month_factors() from factor_db_connector.R.")
      }
    }

    # =========================================================================
    # C17: Infrastructure PIT — align_factor_direction without sig_date
    # (Gate15_C1 in v3.5.4 Admission Rule)
    # Pattern: align_factor_direction( called directly without sig_date arg
    # Exception: load_month_factors internal call (line 123) passes sig_date automatically
    # =========================================================================
    if (grepl("align_factor_direction\\s*\\(", line_trimmed)) {
      is_internal_def <- grepl("^align_factor_direction\\s*<-\\s*function|^function.*sig_date", line_trimmed)
      is_load_month   <- any(grepl("load_month_factors", lines[max(1, i-10):i]))
      is_commented    <- grepl("^#", line_trimmed)
      if (!is_internal_def && !is_load_month && !is_commented) {
        has_sig_date <- grepl("sig_date\\s*=|sig_date\\s*,|,\\s*sig_date", line_trimmed)
        # context window 검사 폐기 — 주석으로 우회 가능한 false negative 방지 (v3.5.4 patch)
        if (!has_sig_date) {
          add_violation("C17_INFRA_PIT_DIRECTION", i, line_trimmed,
            "align_factor_direction() called without sig_date — uses full-sample Mean_IC (L-168 violation). Pass sig_date = current_rebalance_date or use load_month_factors().")
        }
      }
    }

    # =========================================================================
    # C18: Infrastructure PIT — factor_ic_monthly direct read + mean(IC)
    # (Gate15_C3 in v3.5.4 Admission Rule)
    # Pattern: read_parquet on factor_ic_monthly then mean(IC) — bypasses PIT-safe connector
    # =========================================================================
    if (grepl("read_parquet.*factor_ic_monthly|factor_ic_monthly.*read_parquet", line_trimmed)) {
      ctx_window <- get_context(i, window = 10)
      if (grepl("\\bmean\\s*\\(\\s*IC\\b|\\bmean\\s*\\(.*IC.*\\)", ctx_window)) {
        add_violation("C18_INFRA_PIT_IC_PARQUET", i, line_trimmed,
          "factor_ic_monthly.parquet direct read + mean(IC) detected — full-sample IC direction bias (L-168). Use load_month_factors(sig_date=...) instead.")
      }
    }

    # C16 (v53 S2.8): Combinatorial hiding — grid search + winner selection without set.seed
    # expand.grid / crossing / combn + which.max / arrange(desc(sharpe)) / best_ 변수
    # 파일 전체에 set.seed 없으면 재현성 없는 은밀한 조합 탐색 의심.
    c16_patterns <- c(
      "expand\\.grid.*which\\.max",
      "crossing.*which\\.max",
      "expand\\.grid.*arrange.*desc",
      "combn.*sharpe.*>",
      "best_combination\\s*<-",
      "best_blend_id\\s*<-",
      "best_weight_grid\\s*<-"
    )
    for (pat in c16_patterns) {
      if (grepl(pat, line_trimmed, ignore.case = TRUE)) {
        # 파일 전체에 set.seed 존재 여부
        has_seed <- any(grepl("\\bset\\.seed\\s*\\(", lines))
        if (!has_seed) {
          add_violation("C16_COMBINATORIAL", i, line_trimmed,
            "Grid/combinatorial search + winner selection without set.seed — possible hidden exhaustive optimization. Use set.seed + grid_runner::run_grid().")
        }
      }
    }

  }  # end of line loop

  # =========================================================================
  # C11 가용시점 계보 분석 (파일 단위 — 2026-09-24, 정의는 파일 하단)
  # =========================================================================
  #  분석기 내부 오류는 해외 원천을 만지는 파일에서만 위반으로 친다(판정 불가 = 통과 아님). 원천과 무관한
  #  파일(1계층 엔진 등)을 분석기 결함으로 막지는 않는다 — 그 경우 오류는 message 로만 알린다.
  c11_judged <- integer(0)
  tryCatch({
    if (is_python) .la_c11_scan_py(run_all_path, lines, add_violation)
    else { .r11 <- .la_c11_scan_r(run_all_path, lines, add_violation); if (is.list(.r11)) c11_judged <- .r11$judged }
  }, error = function(e) {
    if (any(grepl("fred", lines, ignore.case = TRUE)))
      add_violation("C11_ANALYZER_ERROR", 1L, basename(run_all_path),
        sprintf("C11 분석기 내부 오류 — 판정 불가 = 통과 아님(fail-closed): %s", conditionMessage(e)))
    else message(sprintf("[lookahead] C11 분석기 오류(원천 무관 파일 — 위반 아님): %s", conditionMessage(e)))
  })
  # C3 동월 조회: 해외 계보 기간 조회로 분석기가 판정한 줄만 빼고 낸다(단어 면제 없음 — 위 C3 주석)
  for (.cp in c3_pending) if (!(.cp$i %in% c11_judged))
    add_violation("C3", .cp$i, .cp$code,
      "Same-month lookup (macro·regime 포함 — 단어 면제 없음). 전월 데이터로 결합하거나 해외 계열은 가용시점 층(fred_asof_join) 경유.")

  # =========================================================================
  # Report
  # =========================================================================
  clean <- length(violations) == 0

  if (verbose) {
    if (!clean) {
      cat(sprintf("\n[LOOKAHEAD] %d violation(s) in %s\n",
                  length(violations), basename(run_all_path)))
      for (v in violations) {
        cat(sprintf("  [%s] Line %d: %s\n    Code: %s\n",
                    v$check, v$line, v$msg, v$code))
      }
      cat("[LOOKAHEAD] FIX ALL VIOLATIONS BEFORE RUNNING.\n\n")
    } else {
      cat(sprintf("[LOOKAHEAD] CLEAN: %s (%d lines scanned)\n",
                  basename(run_all_path), n_lines))
    }
  }

  list(clean = clean, scanned = TRUE, violations = violations, file = run_all_path,
       n_lines = n_lines, n_violations = length(violations))
}

# Convenience: scan all R + Python files in a strategy directory
detect_lookahead_dir <- function(strategy_dir, verbose = TRUE) {
  r_files <- list.files(strategy_dir, pattern = "\\.(R|py)$", full.names = TRUE,
                        recursive = FALSE)
  all_violations <- list()
  total <- 0L
  n_unscanned <- 0L

  for (f in r_files) {
    result <- detect_lookahead(f, verbose = FALSE)
    # ★!result$clean 은 NA 에서 `if (NA)` 오류가 난다 — isTRUE 로 3값(TRUE/FALSE/NA) 처리.
    if (!isTRUE(result$scanned)) {
      n_unscanned <- n_unscanned + 1L
      if (verbose) cat(sprintf("[LOOKAHEAD] 미스캔: %s\n", basename(f)))
      next
    }
    if (!isTRUE(result$clean)) {
      total <- total + result$n_violations
      all_violations <- c(all_violations, result$violations)
      if (verbose) {
        cat(sprintf("[LOOKAHEAD] %d violation(s) in %s\n",
                    result$n_violations, basename(f)))
        for (v in result$violations) {
          cat(sprintf("  [%s] Line %d: %s\n", v$check, v$line, v$msg))
        }
      }
    }
  }

  # [2026-08-02 수리] 종전 `clean <- total == 0L` 은 **스캔 대상이 0개일 때도 TRUE** 였다.
  #  경로 오타·빈 디렉토리가 "ALL CLEAN: 0 files scanned" 라는 합격 판정으로 출력됐다 —
  #  0 이 '위반 없음'으로 읽히는 자리(= git_dirty 계통). 미스캔 파일이 섞여도 마찬가지.
  n_scanned <- length(r_files) - n_unscanned
  clean <- if (n_scanned == 0L || n_unscanned > 0L) NA else (total == 0L)
  if (verbose) {
    if (is.na(clean)) {
      cat(sprintf("[LOOKAHEAD] 판정 불가(미측정): %d/%d 파일 미스캔 in %s — PASS 아님\n",
                  n_unscanned, length(r_files), basename(strategy_dir)))
    } else if (clean) {
      cat(sprintf("[LOOKAHEAD] ALL CLEAN: %d files scanned in %s\n",
                  n_scanned, basename(strategy_dir)))
    } else {
      cat(sprintf("[LOOKAHEAD] TOTAL: %d violations across %s\n",
                  total, basename(strategy_dir)))
    }
  }

  list(clean = clean, violations = all_violations, n_violations = total,
       n_files = length(r_files), n_scanned = n_scanned, n_unscanned = n_unscanned)
}

# =============================================================================
# Gate15 INFRA_PIT_SCAN — v3.5.4 Admission Rule (2026-04-19)
# Scans strategy directory for C17/C18 infra PIT violations.
# Returns list: clean, gate15_violations, files_scanned
# =============================================================================
detect_gate15_infra_pit <- function(strategy_dir, verbose = TRUE) {
  r_files <- list.files(strategy_dir, pattern = "\\.R$", full.names = TRUE,
                        recursive = TRUE)
  # Exclude the connector itself (exempt: internal definition)
  r_files <- r_files[!grepl("factor_db_connector\\.R$", r_files)]

  gate15_violations <- list()
  total <- 0L
  n_unscanned <- 0L

  for (f in r_files) {
    result <- detect_lookahead(f, verbose = FALSE)
    if (!isTRUE(result$scanned)) {
      n_unscanned <- n_unscanned + 1L
      if (verbose) cat(sprintf("[Gate15] 미스캔: %s\n", basename(f)))
      next
    }
    infra_v <- Filter(function(v) grepl("^C17|^C18", v$check), result$violations)
    if (length(infra_v) > 0) {
      total <- total + length(infra_v)
      gate15_violations <- c(gate15_violations, infra_v)
      if (verbose) {
        cat(sprintf("[Gate15] %d infra PIT violation(s) in %s\n",
                    length(infra_v), basename(f)))
        for (v in infra_v) {
          cat(sprintf("  [%s] Line %d: %s\n    Code: %s\n",
                      v$check, v$line, v$msg, v$code))
        }
      }
    }
  }

  # [2026-08-02 수리] 종전 `total == 0L` 은 스캔 대상 0개(경로 오타·빈 디렉토리)에서도
  #  "INFRA_PIT_SCAN PASS: 0 files" 를 냈다. 0 을 합격으로 읽는 자리 — admission 게이트에서
  #  가장 위험한 형태다. 미측정은 NA 로 분리하고 소비부의 isTRUE() 가 not-pass 로 받게 한다.
  n_scanned <- length(r_files) - n_unscanned
  clean <- if (n_scanned == 0L || n_unscanned > 0L) NA else (total == 0L)
  if (verbose) {
    if (is.na(clean)) {
      cat(sprintf("[Gate15] INFRA_PIT_SCAN 판정 불가(미측정): %d/%d 파일 미스캔 — PASS 아님\n",
                  n_unscanned, length(r_files)))
    } else if (clean) {
      cat(sprintf("[Gate15] INFRA_PIT_SCAN PASS: %d files, 0 C17/C18 violations.\n",
                  n_scanned))
    } else {
      cat(sprintf("[Gate15] INFRA_PIT_SCAN FAIL: %d C17/C18 violation(s) in %d files.\n",
                  total, n_scanned))
      cat("[Gate15] REJECT — Fix align_factor_direction sig_date / load_month_factors usage.\n")
    }
  }

  list(clean = clean, gate15_violations = gate15_violations,
       n_violations = total, files_scanned = n_scanned,
       n_unscanned = n_unscanned, n_files = length(r_files))
}

# =============================================================================
# C11 가용시점 분석기 (2026-09-24 S6_defense — PIT C11 판정서 ⑤-8 방어선 · decision_register
#   PIT-C11-CONVENTIONS ④). 근거 = 04_Research/01_reports/pit_c11_20260924/PIT_C11_verdict_20260924.md
#   ②(계열별 lag 규약 · 원칙 a/b/c) · ③ "방어선이 C11을 못 잡은 이유".
#
# 무엇이 바뀌었나 — 종전 C11_FRED 는 "fred 를 읽는 줄 주변 10행에 shift/lag/1d 문자열이 있는가"였다.
#   ① 문자열 휴리스틱이라 `verbose_flag`(부분문자열 lag)·`paste0("macro_","fred.parquet")` 두 돌연변이에서
#     거짓 음성, ② 올바르게 lag 한 compute_regime·regime_engine_daily 의 **읽기 줄**에서 거짓 양성,
#   ③ 실제 결합 지점(빌더 :311-312)이 아니라 읽기 줄을 가리켰다(판정서 ③).
# 새 판정: 파일을 R 파서로 읽어(주석·문자열은 판정에 쓰지 않는다) 해외 원천에서 나온 값의 **계보**를 따라가고,
#   그 값이 한국 날짜와 만나는 지점(결합·as-of 절단·KR 적용 패널 저장)에서 가용시점 규칙
#   (06_Registry/fred_availability_rules.json — 기반 S0 층의 규칙 정본)과 대조한다.
#   - 가용시점 층 경유(fred_asof_join / fred_avail_annotate / fred_avail_date / avail_date 필터) = 적합.
#   - lag 없이 만남 = C11_FRED_SAMEDATE (판정서 V-08 형태).
#   - 임시 lag(shift ≥1 · Date < d · Date <= d - k · Date + k)는 **규칙이 '다음 한국 거래일'(kr_trading_days_after
#     n ≤ 1)뿐인 계열에만** 충분하다(판정서 ② VIXCLS 행: 미국 날짜 < 한국 날짜). 주간·월간·ICE OAS(d+2)·미식별 계열에
#     임시 lag 를 건 것 = C11_PUB_LAG (판정서 V-01·V-11 형태). 규칙 수치는 여기 없다 — 규칙 파일의 bound 로 분류한다.
#   - 금지 계열(규칙 파일 status=prohibited: DEXKOUS/KRW_USD) = C11_PROHIBITED_SERIES (CONVENTIONS ①).
#   - 기간 라벨 조회(표[YM == 키])는 같은 달이면 C11_FRED_SAMEDATE, 전월 키·기간 이동(shift·MI + 1)이면 판정서 1-6
#     레거시 분류대로 적합으로 본다. 이런 줄은 C3 줄 규칙 대신 이 분석기가 판정한다(C3 는 단어 면제 없이 나머지를 잡는다).
#   - 소비자가 부르는 어댑터(source() 한 파일 · 같은 파일 함수)는 본문이 실제로 가용시점 층을 부르는지 읽어서 인정한다.
#   - 해외 원천을 만지는 파일인데 규칙 파일을 못 읽거나 파싱이 안 되면 fail-closed(C11_RULES_UNAVAILABLE/C11_UNPARSEABLE).
# 판정 범위 = 해외(FRED) 계열(규칙 파일 source "FRED…"). ECOS 국내 계열(판정서 ② "시각 미검증 · lag 1 권장")은
#   이 검출기가 막지 않는다 — 도우미 결합은 ECOS 도 규칙대로 하지만, 정적 차단은 판정서가 확정한 해외 결합에 한정한다.
# 한계(정직 신고): 정적 분석이다. 소비 형태 (b)(노출 × 종가→종가 수익 — 1행 lag 도 부족)는 구분하지 못한다 —
#   exposure_return 모드는 가용시점 층을 경유해야 판정된다. 함수 인자로 넘어간 값의 계보·열 단위 계보
#   (예: regime_daily_v2 VIX_z_smooth 이름 충돌 V-10)는 따라가지 않는다. 파생 패널(regime_daily_v2 등)을
#   읽는 소비자는 원천으로 보지 않는다(그 패널의 오염은 06_Registry/pit_quarantine.json 이 막는다). 기간 이동 1기간의
#   충분성(월간 공표 계열)은 보증하지 않는다. 파이썬은 파일 단위 근사다.
# =============================================================================

.LA_SELF_PATH <- local(tryCatch({    # source() 한 이 파일의 경로(sys.frame ofile) — 전역에 임시 변수를 남기지 않는다
  f <- NA_character_
  for (i in rev(seq_len(sys.nframe()))) {
    of <- tryCatch(sys.frame(i)$ofile, error = function(e) NULL)
    if (!is.null(of) && nzchar(of)) { f <- of; break }
  }
  if (!is.na(f)) gsub("\\\\", "/", f) else NA_character_
}, error = function(e) NA_character_))

.la_c11_env <- new.env(parent = emptyenv())

# 코드 패턴(수치 아님). 원천 식별 = 판정서 ①의 실제 원천 이름(macro_fred·fred_macro·FRED_*_CACHE·fred_robust 수집기).
.LA_C11 <- list(
  path_lit   = "(?i)fred|macro_regime\\.parquet",   # 원천 파일 리터럴(연결된 리터럴 포함 — paste0("macro_","fred…")) · r1: macro_regime = FRED 계열 값을 담은 파생 패널(V-14)
  path_excl  = "(?i)fred_(avail|asof|join_violations|kr_calendar|decision_date|series_rule)",  # 가용시점 층 자체(도우미·규칙 파일·함수 이름)는 원천이 아니다
  # r1(V6 B1): 소문자 경로 변수(fred_cache <- ...)도 원천 경로다 — 대소문자 무시
  path_sym   = "(?i)^fred_[A-Za-z0-9_]*(CACHE|PATH|FILE|LONG|WIDE|DIR)$|^(macro_fred|fred_macro)[A-Za-z0-9_]*$",
  loader_fn  = "^(fred_(load|fetch|read|get)[A-Za-z0-9_]*|load_(fred|macro)[A-Za-z0-9_]*)$",
  read_fn    = "(?<![.A-Za-z0-9_])(read_parquet|open_dataset|fread|readRDS|read\\.csv|read_csv|read_feather|qread)\\s*\\(",
  avail_fn   = "(?<![.A-Za-z0-9_])(fred_asof_join|fred_avail_annotate|fred_avail_date|fred_join_violations)\\s*\\(|(?<![.A-Za-z0-9_])avail_date\\s*<",
  join       = "(?<![.A-Za-z0-9_])(merge|left_join|right_join|inner_join|full_join|foverlaps)\\s*\\(|(?<![.A-Za-z0-9_])(on|roll)\\s*=",
  # 패널 저장(표 형식) — 한국 날짜 적용 패널(regime_daily_v2·macro_regime 형태)이 여기서 굳는다. 객체 저장(saveRDS)은 결과물이라 제외.
  persist    = "(?<![.A-Za-z0-9_])(write_parquet|write_dataset|fwrite|write\\.csv|write_csv|write_feather)\\s*\\(",
  asof       = "(?<![.A-Za-z0-9_])Date\\s*<",
  # r1(V6 B1): 'Date < d + 1' 은 'Date <= d'(lag 아님) — 오른쪽에 양의 가산이 있으면 lag 로 치지 않는다 · 'Date <= d - 0L' 도 lag 아님
  lag_lt     = "(?<![.A-Za-z0-9_])Date\\s*<(?!=)(?![^\\]\\[,&|;)]*\\+\\s*[0-9]*[1-9])",
  lag_minus  = "(?<![.A-Za-z0-9_])Date\\s*<=\\s*\\(?\\s*[.A-Za-z][.A-Za-z0-9_$]*\\s*-\\s*(?!0+L?(?![0-9.]))[0-9(.A-Za-z]",
  lag_plus   = "(?<![.A-Za-z0-9_])Date\\s*:?=\\s*\\(?\\s*Date\\s*\\+",
  lag_cna    = "(?<![.A-Za-z0-9_])c\\s*\\(\\s*NA[A-Za-z_]*\\s*,\\s*[.A-Za-z][.A-Za-z0-9_$]*\\s*\\[\\s*-",
  lag_dplyr  = "dplyr::lag\\s*\\(",
  # 기간 라벨을 앞으로 미는 것(관측월 M 의 값을 M+k 에 적용 — MI := MIq + 1L · ym_apply <- ym + 1 · %m+% months(1))
  lag_period = "(?<![.A-Za-z0-9_])(MI|MIq|YM|ym|[A-Za-z_]*[Mm]onth[A-Za-z_]*|[A-Za-z_]*_ym|ym_[A-Za-z_]*|apply_[A-Za-z_]*)\\s*(:?=|<-)\\s*\\(?\\s*[.A-Za-z][.A-Za-z0-9_]*\\s*\\+\\s*[1-9]|%m\\+%\\s*months\\s*\\(\\s*[1-9]",
  series_ctx = "(?<![.A-Za-z0-9_])Series(_ID)?(?![.A-Za-z0-9_])",
  subset_ctx = "\\[|(?<![.A-Za-z0-9_])(subset|filter)\\s*\\(",
  # 기간 라벨 동등 선택(macro_regime_dt[YM == ym] — 판정서 V-14 동월 조회) · 기간 키를 뒤로 민 정의(dd - 32 · %m-%)
  period_eq  = "(?<![.A-Za-z0-9_])(YM|ym|MI|yyyymm|YYYYMM|YearMonth|month|Month)\\s*==\\s*[^,\\]&|)]+",
  period_lhs = "^(YM|ym|MI|yyyymm|YYYYMM|YearMonth|month|Month)\\s*==\\s*",
  period_minus = "-\\s*[0-9(]|%m-%|months\\s*\\(\\s*-",
  # 결합 키 지정(by/on) · 날짜/기간 키 · 기간 키
  join_key   = "(?<![.A-Za-z0-9_])(by|on|by\\.x|by\\.y)\\s*=\\s*(c\\s*\\([^)]*\\)|\"[^\"]*\"|'[^']*'|[.A-Za-z][.A-Za-z0-9_$]*)",
  date_key   = "(?i)date|(?<![A-Za-z])(dt|time|ym|mi|yyyymm|yearmonth|month|period)(?![A-Za-z])",
  period_key = "(?<![A-Za-z])(YM|ym|MI|yyyymm|YYYYMM|YearMonth|[Mm]onth)(?![A-Za-z])",
  # 가용일 열(가용시점 층이 붙인 결정 가능일)을 쓰는 문장 — 파일이 가용시점 층을 실제로 쓸 때만 인정(이름만으로는 인정하지 않는다)
  avail_key  = "(?<![.A-Za-z0-9_])(avail_date|Avail_Date|Asof_Date|asof_date|avail_ts)(?![.A-Za-z0-9_])",
  # r1(V6 B1 — fail-closed): merge/on=/roll= 밖의 날짜 정렬 형태도 결합으로 본다(구판이 잡던 형태):
  #   match·findInterval·approx·between/inrange 에 날짜 · Date == d(루프 조회) · Date %in% · substr/format(Date) == 기간 ·
  #   이름 벡터 조회 x[as.character(Date)] · (data.table X[Y] 키 결합은 본체가 계보 상태로 따로 잡는다)
  align      = "(?<![.A-Za-z0-9_])(match|findInterval|approx|approxfun|between|inrange)\\s*\\([^;\\n]*[Dd]ate|(?<![.A-Za-z0-9_])Date\\s*(==|%in%)|==\\s*Date(?![.A-Za-z0-9_])|(?<![.A-Za-z0-9_])(substr|substring|format)\\s*\\(\\s*[^,]*[Dd]ate[^)]*\\)\\s*==|\\[\\s*(as\\.character|format)\\s*\\(\\s*[^)]*[Dd]ate"
)

.la_c11_rules_path <- function() {
  o <- getOption("lookahead.c11_rules")
  if (!is.null(o)) return(as.character(o))
  if (!is.na(.LA_SELF_PATH)) {
    p <- file.path(dirname(dirname(dirname(.LA_SELF_PATH))), "06_Registry", "fred_availability_rules.json")
    if (file.exists(p)) return(p)
  }
  r <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ""))
  if (nzchar(r)) return(file.path(r, "06_Registry", "fred_availability_rules.json"))
  NA_character_
}

# 규칙 파일 → 계열 분류. class0 = 당일 가용(n=0) · class1 = 다음 한국 거래일(n≤1: 임시 1일 lag 충분)
#   · class2 = 그 밖(주간·월간·us_release·n≥2 — 가용시점 층 필수) · prohibited = status≠active.
.la_c11_rules <- function() {
  p <- .la_c11_rules_path()
  if (is.na(p) || !file.exists(p)) return(list(ok = FALSE, why = sprintf("규칙 파일 없음(%s)", p)))
  fi <- file.info(p)
  key <- paste(p, fi$size, as.numeric(fi$mtime))
  hit <- .la_c11_env[[key]]
  if (!is.null(hit)) return(hit)
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(list(ok = FALSE, why = "jsonlite 미설치"))
  raw <- tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(raw) || !identical(raw$schema, "fred_availability_rules/v1") || !length(raw$series))
    return(list(ok = FALSE, why = sprintf("규칙 파일 형식 불량(%s)", p)))
  key2id <- character(0); cls <- character(0); repl <- character(0); ids <- character(0); als <- character(0)
  frn <- logical(0)
  for (s in raw$series) {
    id <- as.character(s$id)
    if (length(id) != 1L || !nzchar(id)) return(list(ok = FALSE, why = "규칙 파일 series.id 불량"))
    al <- as.character(unlist(s$aliases))
    ids <- c(ids, id); als <- c(als, al)
    for (k in unique(c(id, al))) key2id[k] <- id
    st <- as.character(s$status)
    cl <- if (!identical(st, "active")) "prohibited" else {
      b <- s$bounds
      simple <- length(b) > 0L && all(vapply(b, function(x)
        identical(x$type, "kr_trading_days_after") && is.numeric(x$n) && length(x$n) == 1L, logical(1)))
      if (!simple) "class2" else {
        nmax <- max(vapply(b, function(x) as.numeric(x$n), numeric(1)))
        if (nmax <= 0) "class0" else if (nmax <= 1) "class1" else "class2"
      }
    }
    cls[id] <- cl
    if (identical(cl, "prohibited")) repl[id] <- if (is.null(s$replacement)) "" else as.character(s$replacement)
    src <- if (is.null(s$source)) "" else as.character(s$source)[1]
    frn[id] <- grepl("^FRED", src)               # 해외(FRED) 계열 — 이 검출기의 판정 범위(판정서 ① 해외 결합)
  }
  R <- list(ok = TRUE, path = p, version = as.character(raw$version), key2id = key2id, cls = cls,
            ids = ids, aliases = setdiff(als, ids), repl = repl, foreign = frn)
  assign(key, R, envir = .la_c11_env)
  R
}

# 주석 제거(문자열 보존) / 주석·문자열 내용 제거. 문자열 안의 # 은 문자열로 먼저 소비된다(왼쪽 우선 일치).
.la_c11_strip <- function(txt, keep_strings = TRUE, py = FALSE) {
  repl <- function(v) vapply(v, function(s) {
    if (startsWith(s, "#")) return(strrep(" ", nchar(s)))
    if (keep_strings || startsWith(s, "`")) return(s)
    q <- if (py && (startsWith(s, '"""') || startsWith(s, "'''"))) substr(s, 1, 3) else substr(s, 1, 1)
    paste0(q, gsub("[^\n]", " ", substr(s, nchar(q) + 1L, nchar(s) - nchar(q))), q)
  }, character(1), USE.NAMES = FALSE)
  if (py) {   # 파이썬은 여러 줄 docstring 이 흔해 파일 전체에 한 번(파일이 작다)
    pat <- '"""[\\s\\S]*?"""|\'\'\'[\\s\\S]*?\'\'\'|"(?:[^"\\\\\\n]|\\\\.)*"|\'(?:[^\'\\\\\\n]|\\\\.)*\'|#[^\\n]*'
    m <- gregexpr(pat, txt, perl = TRUE)
    regmatches(txt, m) <- lapply(regmatches(txt, m), repl)
    return(txt)
  }
  # R: 줄 단위 벡터화(한 덩어리 문자열에 regmatches<- 를 쓰면 큰 파일에서 느리다).
  #   한계: 여러 줄에 걸친 문자열 리터럴은 줄마다 따로 보므로 그 내용이 코드로 남을 수 있다(R 코드에서 드묾).
  L <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  if (!length(L)) return(txt)
  pat <- '"(?:[^"\\\\]|\\\\.)*"|\'(?:[^\'\\\\]|\\\\.)*\'|`(?:[^`\\\\]|\\\\.)*`|#.*$'
  m <- gregexpr(pat, L, perl = TRUE)
  has <- vapply(m, function(z) z[1] > 0L, logical(1))
  if (any(has)) {
    x <- L[has]
    mm <- gregexpr(pat, x, perl = TRUE)          # r1(r-portability 금칙 ⑥): 색인을 perl=TRUE 로 이 자리에서 다시 만든다
    regmatches(x, mm) <- lapply(regmatches(x, mm), repl)
    L[has] <- x
  }
  paste(L, collapse = "\n")
}

.la_c11_literals <- function(code) {
  m <- regmatches(code, gregexpr('"(?:[^"\\\\]|\\\\.)*"|\'(?:[^\'\\\\]|\\\\.)*\'', code, perl = TRUE))[[1]]
  if (!length(m)) return(character(0))
  substr(m, 2L, nchar(m) - 1L)
}

.la_c11_refs <- function(nostr) {
  m <- regmatches(nostr, gregexpr("(?<![A-Za-z0-9._$@])[.A-Za-z][.A-Za-z0-9_]*(\\s*\\$\\s*[.A-Za-z][.A-Za-z0-9_]*)?",
                                  nostr, perl = TRUE))[[1]]
  unique(gsub("\\s+", "", m))
}

.la_c11_calls <- function(nostr) {
  m <- regmatches(nostr, gregexpr("(?<![A-Za-z0-9._$@])[.A-Za-z][.A-Za-z0-9_]*(?=\\s*\\()", nostr, perl = TRUE))[[1]]
  unique(m)
}

# shift(...) 호출 목록: 시작·끝 글자 위치 · lag 여부(n ≥ 1, lead 아님) · 첫 인자. 위치는 문자열을 지운 판(nostr)에서 찾고
#  (문자열 안의 "shift(" 는 lag 가 아니다), 인자는 같은 위치의 문자열 보존 판(code)에서 읽는다(type = "lead" 판별).
.la_c11_shift_spans <- function(code, nostr = code) {
  out <- data.frame(start = integer(0), end = integer(0), lag = logical(0), arg1 = character(0), stringsAsFactors = FALSE)
  st <- gregexpr("(?<![.A-Za-z0-9_])shift\\s*\\(", nostr, perl = TRUE)[[1]]
  if (st[1] < 0L) return(out)
  ch <- strsplit(code, "", fixed = TRUE)[[1]]
  n <- length(ch)
  for (k in seq_along(st)) {
    i <- st[k] + attr(st, "match.length")[k] - 1L        # '(' 위치
    depth <- 0L; j <- i; args <- character(0); cur <- character(0)
    while (j <= n) {
      c1 <- ch[j]
      if (c1 %in% c("(", "[", "{")) { depth <- depth + 1L; if (depth > 1L) cur <- c(cur, c1) }
      else if (c1 %in% c(")", "]", "}")) {
        depth <- depth - 1L
        if (depth == 0L) { args <- c(args, paste(cur, collapse = "")); break }
        cur <- c(cur, c1)
      } else if (c1 == "," && depth == 1L) { args <- c(args, paste(cur, collapse = "")); cur <- character(0) }
      else if (depth >= 1L) cur <- c(cur, c1)
      j <- j + 1L
    }
    a <- trimws(args)
    lg <- TRUE
    if (any(grepl("^type\\s*=\\s*[\"'](lead|shift)[\"']", a))) lg <- FALSE
    nm <- grepl("^n\\s*=", a)
    nval <- if (any(nm)) sub("^n\\s*=\\s*", "", a[nm][1]) else if (length(a) >= 2L && !grepl("^[.A-Za-z_]+\\s*=", a[2])) a[2] else "1"
    if (grepl("^-", nval)) lg <- FALSE
    if (grepl("^0+L?$", nval)) lg <- FALSE
    out[nrow(out) + 1L, ] <- list(as.integer(st[k]), as.integer(min(j, n)), lg, if (length(a)) a[1] else "")
  }
  out
}

# shift(...) 호출 중 하나라도 lag 이면 TRUE — 열 무관(구판 판정). 계열에 묶은 판정 = .la_c11_shift_lag_on.
.la_c11_shift_lag <- function(code, nostr = code) any(.la_c11_shift_spans(code, nostr)$lag)

# ★r1(V6 B2 — 통합 검증 BLOCKING): lag 증거를 **결합된 계열 열**에 묶는다. names = 그 문장이 다루는 해외 계보 이름
#   (계보 변수·계열 id·별칭·Value). TRUE = (1) lag shift 의 첫 인자가 names 를 참조하고 (2) shift(...) 구간과 대입 대상
#   (x := · 인자 이름 x =)을 지운 나머지에 names 가 남지 않는다(= 그 계열을 lag 판으로만 쓴다).
#   무관한 열의 shift(ret_prev := shift(ret))와 차분(dVIX := VIX - shift(VIX) — 당일 VIX 를 그대로 쓴다)은 lag 가 아니다.
.la_c11_shift_lag_on <- function(code, nostr, names) {
  names <- unique(names[!is.na(names) & nzchar(names)])
  if (!length(names)) return(FALSE)
  sp <- .la_c11_shift_spans(code, nostr)
  if (!nrow(sp) || !any(sp$lag)) return(FALSE)
  names <- names[grepl("^[.A-Za-z_][.A-Za-z0-9_$]*$", names)]          # 식별자 모양만(정규식 메타 없음 — . 과 $ 만 이스케이프)
  if (!length(names)) return(FALSE)
  esc <- gsub("$", "\\$", gsub(".", "\\.", names, fixed = TRUE), fixed = TRUE)
  rx <- sprintf("(?<![.A-Za-z0-9_$])(%s)(?![.A-Za-z0-9_])", paste(esc, collapse = "|"))
  if (!any(sp$lag & grepl(rx, sp$arg1, perl = TRUE))) return(FALSE)
  ch <- strsplit(nostr, "", fixed = TRUE)[[1]]
  for (i in seq_len(nrow(sp))) { e <- min(sp$end[i], length(ch)); if (e >= sp$start[i]) ch[sp$start[i]:e] <- " " }
  rest <- paste(ch, collapse = "")
  rest <- gsub("`:=`", " ", rest, fixed = TRUE)
  rest <- gsub("(?<![.A-Za-z0-9_$])[.A-Za-z][.A-Za-z0-9_]*\\s*:?=(?!=)", " ", rest, perl = TRUE)   # 대입 대상
  !grepl(rx, rest, perl = TRUE)
}

# names 를 주면 shift 는 계열에 묶어 판정(.la_c11_shift_lag_on — r1), 안 주면 구판(아무 shift). 날짜 절단형 lag 는 문장 단위.
.la_c11_has_lag <- function(code, nostr, names = NULL) {
  P <- .LA_C11
  (if (is.null(names)) .la_c11_shift_lag(code, nostr) else .la_c11_shift_lag_on(code, nostr, names)) ||
    grepl(P$lag_lt, nostr, perl = TRUE) || grepl(P$lag_minus, nostr, perl = TRUE) ||
    grepl(P$lag_plus, nostr, perl = TRUE) || grepl(P$lag_cna, nostr, perl = TRUE) || grepl(P$lag_dplyr, nostr, perl = TRUE) ||
    grepl(P$lag_period, nostr, perl = TRUE)
}

# 원천 경로 리터럴 = 'fred' 를 품은 **공백 없는**(파일명·경로 모양) 리터럴. 메시지 문자열("FRED 캐시 없음")은 원천이 아니다.
#  paste0("macro_", "fred.parquet") 처럼 쪼갠 경로는 한 문장 안의 공백 없는 조각끼리 이어서 본다.
.la_c11_pathish_src <- function(lits) {
  P <- .LA_C11
  pl <- lits[nzchar(lits) & !grepl("\\s", lits)]
  if (!length(pl)) return(FALSE)
  cand <- c(pl, paste(pl, collapse = ""))
  cand <- cand[grepl("[./\\\\]", cand)]                  # 파일명·경로 모양(확장자·구분자) — "fred_asof_join" 같은 이름 문자열 제외
  any(grepl(P$path_lit, cand, perl = TRUE) & !grepl(P$path_excl, cand, perl = TRUE))
}

# 금지 계열 별칭의 모호성: 파일이 금지 계열의 대체 계열(규칙 파일 replacement — 예: DEXKOUS → ECOS_KRW_USD)을
#  id·별칭·파일명(소문자 id)으로 쓰고 금지 계열 id 는 명시하지 않으면, 그 별칭(KRW_USD)은 대체 계열의 열 이름으로 본다.
.la_c11_disambiguate <- function(R, lits) {
  if (!isTRUE(R$ok) || !length(R$repl)) return(R)
  for (pid in names(R$repl)) {
    rep <- R$repl[[pid]]
    if (!nzchar(rep) || !(rep %in% R$ids) || pid %in% lits) next
    ev <- unique(c(rep, tolower(rep), names(R$key2id)[R$key2id == rep & names(R$key2id) != pid]))
    if (!any(vapply(ev, function(e) any(grepl(e, lits, fixed = TRUE)), logical(1)))) next
    al <- names(R$key2id)[R$key2id == pid & names(R$key2id) != pid]
    R$key2id[al] <- rep
  }
  R
}

# 파일이 해외 원천을 만지는가(저비용 사전 검사 — 아니면 파서를 돌리지 않는다).
.la_c11_touch <- function(code_all, nostr_all, R) {
  P <- .LA_C11
  lits <- .la_c11_literals(code_all)
  if (any(vapply(lits, function(l) .la_c11_pathish_src(l), logical(1)))) return(TRUE)
  for (l in strsplit(code_all, "\n", fixed = TRUE)[[1]]) if (.la_c11_pathish_src(.la_c11_literals(l))) return(TRUE)
  refs <- .la_c11_refs(nostr_all)
  if (any(grepl(P$path_sym, refs, perl = TRUE)) || any(grepl(P$loader_fn, .la_c11_calls(nostr_all), perl = TRUE))) return(TRUE)
  isTRUE(R$ok) && any(lits %in% R$ids[R$foreign[R$ids] %in% TRUE])      # 해외(FRED) 계열 id 리터럴
}

.la_c11_series_of <- function(lits, nostr, R, ctx_required_for_alias = TRUE) {
  if (!isTRUE(R$ok) || !length(lits)) return(character(0))
  ids <- unname(R$key2id[intersect(lits, R$ids)])
  al <- intersect(lits, R$aliases)
  if (length(al) && (!ctx_required_for_alias || grepl(.LA_C11$series_ctx, nostr, perl = TRUE)))
    ids <- c(ids, unname(R$key2id[al]))
  unique(ids)
}

# ── 가용시점 층 어댑터 인식 ────────────────────────────────────────────────────────
#  소비자는 도우미를 직접 부르지 않고 어댑터(예: factor_db_daily_pit.R::fdb_fred_on_kr_dates)를 부를 수 있다.
#  이름 목록을 믿지 않는다 — 분석 대상이 source() 하는 파일을 실제로 읽어, 본문이 가용시점 층
#  (fred_asof_join·fred_avail_annotate·fred_avail_date) 또는 그런 함수를 부르는 최상위 함수만 어댑터로 인정한다.
.LA_C11_AVAIL_CORE <- c("fred_asof_join", "fred_avail_annotate", "fred_avail_date")

.la_c11_code_root <- function() {
  if (!is.na(.LA_SELF_PATH)) return(dirname(dirname(dirname(.LA_SELF_PATH))))
  gsub("\\\\", "/", Sys.getenv("QM_ROOT", ""))
}

.la_c11_source_targets <- function(path, code_all) {
  m <- gregexpr("(?<![.A-Za-z0-9_])(source|sys\\.source)\\s*\\(", code_all, perl = TRUE)[[1]]
  if (m[1] < 0L) return(character(0))
  root <- .la_c11_code_root(); d <- dirname(path); out <- character(0)
  for (st in as.integer(m)) {
    seg <- sub("\n.*$", "", substr(code_all, st, st + 400L))
    lits <- .la_c11_literals(seg)
    k <- which(grepl("\\.[Rr]$", lits))
    if (!length(k)) next
    tailp <- paste(lits[seq_len(k[1])], collapse = "/")
    cands <- unique(c(lits[k[1]], file.path(d, lits[k[1]]), file.path(d, tailp), file.path(root, tailp),
                      file.path(root, "02_Infrastructure", tailp)))
    hit <- cands[file.exists(cands) & !dir.exists(cands)]
    if (length(hit)) out <- c(out, gsub("\\\\", "/", hit[1]))
  }
  unique(out)
}

.la_c11_wrappers_in <- function(f) {
  fi <- file.info(f)
  key <- paste("wrap", f, fi$size, as.numeric(fi$mtime))
  hit <- .la_c11_env[[key]]
  if (!is.null(hit)) return(hit)
  ex <- tryCatch(parse(f, keep.source = FALSE, encoding = "UTF-8"), error = function(e) NULL)
  calls <- list()
  for (e in as.list(ex)) {
    if (is.call(e) && as.character(e[[1]])[1] %in% c("<-", "=", "<<-") && length(e) == 3L &&
        is.call(e[[3]]) && identical(e[[3]][[1]], as.name("function")) && is.name(e[[2]]))
      calls[[as.character(e[[2]])]] <- all.names(e[[3]])
  }
  w <- names(calls)[vapply(calls, function(a) any(a %in% .LA_C11_AVAIL_CORE), logical(1))]
  for (it in 1:5) w <- union(w, names(calls)[vapply(calls, function(a) any(a %in% w), logical(1))])
  assign(key, w, envir = .la_c11_env)
  w
}

# 파이썬: import 한 모듈 파일이 가용시점 층(fred_asof_join)을 부르면, 그 모듈을 쓰는 파일은 그 층을 경유한 것으로 본다.
.la_c11_py_avail_import <- function(path, nostr_all) {
  mods <- c(regmatches(nostr_all, gregexpr("(?m)^\\s*import\\s+([A-Za-z_][A-Za-z0-9_]*)", nostr_all, perl = TRUE))[[1]],
            regmatches(nostr_all, gregexpr("(?m)^\\s*from\\s+([A-Za-z_][A-Za-z0-9_]*)\\s+import", nostr_all, perl = TRUE))[[1]])
  mods <- unique(sub("^\\s*(import|from)\\s+([A-Za-z_][A-Za-z0-9_]*).*$", "\\2", mods))
  if (!length(mods)) return(FALSE)
  root <- .la_c11_code_root(); d <- dirname(path)
  dirs <- unique(c(d, file.path(root, "02_Infrastructure", c("data", "regime", "ml_pipeline", "factor_db", "ops", "ast"))))
  for (m0 in mods) {
    f <- file.path(dirs, paste0(m0, ".py")); f <- f[file.exists(f)]
    if (!length(f)) next
    t <- paste(readLines(f[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    t <- .la_c11_strip(t, FALSE, py = TRUE)
    if (grepl("(?<![A-Za-z0-9_])(fred_asof_join|fred_avail_annotate)\\s*\\(", t, perl = TRUE)) return(TRUE)
  }
  FALSE
}

# ── 본체(R) ─────────────────────────────────────────────────────────────────────
#  계보 = 변수(렉시컬 스코프 — 함수마다) → 상태 list(kind = path|names|data, series, lagged, avail, roots, fred).
#  원천 데이터는 (원천 경로 + 읽기) · 원천 로더 호출 · Series==<규칙 계열 id> 부분집합 · 원천을 읽는 같은 파일 함수의
#  호출 결과에서 생긴다. 싱크(결합·as-of 절단·임시 lag 패널 저장)에서 가용시점 규칙과 대조한다.
.la_c11_scan_r <- function(path, lines, add) {
  txt <- paste(lines, collapse = "\n")
  code_all <- .la_c11_strip(txt, TRUE); nostr_all <- .la_c11_strip(txt, FALSE)
  R <- .la_c11_rules()
  if (!.la_c11_touch(code_all, nostr_all, R)) return(invisible(list(n = 0L, judged = integer(0))))
  if (!isTRUE(R$ok)) {
    add("C11_RULES_UNAVAILABLE", 1L, basename(path),
        sprintf("해외(FRED) 원천을 만지는 파일인데 가용시점 규칙을 못 읽음 — %s. 판정 불가 = 통과 아님(fail-closed)", R$why))
    return(invisible(list(n = 1L, judged = integer(0))))
  }
  ex <- tryCatch(parse(path, keep.source = TRUE, encoding = "UTF-8"), error = function(e) e)
  pd <- if (inherits(ex, "error")) NULL else tryCatch(utils::getParseData(ex, includeText = TRUE), error = function(e) NULL)
  if (is.null(pd) || !nrow(pd)) {
    add("C11_UNPARSEABLE", 1L, basename(path),
        sprintf("해외(FRED) 원천을 만지는 파일인데 R 파서가 실패 — 계보 판정 불가(fail-closed): %s",
                if (inherits(ex, "error")) conditionMessage(ex) else "parse data 없음"))
    return(invisible(list(n = 1L, judged = integer(0))))
  }
  P <- .LA_C11
  R <- .la_c11_disambiguate(R, .la_c11_literals(code_all))   # KRW_USD 가 ECOS 열 이름인 파일
  file_series <- .la_c11_series_of(.la_c11_literals(code_all), nostr_all, R, ctx_required_for_alias = FALSE)
  # r1(V6 B2): lag 증거를 묶을 해외 계열 이름(규칙 파일 id·별칭 + 원천 값 열 이름)
  SER_NAMES <- unique(c(R$ids, R$aliases, "Value", "value"))

  # ── 파스 트리 색인 ──
  pd <- pd[order(pd$line1, pd$col1, -pd$line2, -pd$col2, -pd$id), ]   # 같은 구간이면 부모(큰 id) 먼저
  rownames(pd) <- NULL
  n <- nrow(pd)
  row_of <- setNames(seq_len(n), as.character(pd$id))
  PROW <- unname(row_of[as.character(pd$parent)])
  KIDS <- split(seq_len(n), factor(PROW, levels = seq_len(n)))          # 행 → 자식 행(원문 순서)
  kids <- function(r) KIDS[[r]]
  EXPR <- c("expr", "equal_assign", "expr_or_assign_or_help")
  ASG  <- c("LEFT_ASSIGN", "EQ_ASSIGN", "RIGHT_ASSIGN")
  # 텍스트 조각은 파일 전체를 한 번 정리한 판(주석 제거 / 주석·문자열 내용 제거 — 글자 위치 보존)에서 잘라 쓴다.
  #  파스 데이터 열 번호는 탭을 8칸으로 편 표시 열이다 — 탭이 있는 줄만 글자 위치로 환산한다.
  LN <- lines; LC <- strsplit(code_all, "\n", fixed = TRUE)[[1]]; LS <- strsplit(nostr_all, "\n", fixed = TRUE)[[1]]
  length(LC) <- length(LN); length(LS) <- length(LN)
  LC[is.na(LC)] <- ""; LS[is.na(LS)] <- ""
  cidx <- function(li, col) {
    t <- LN[li]
    if (is.na(t) || !grepl("\t", t, fixed = TRUE)) return(col)
    ch <- strsplit(t, "", fixed = TRUE)[[1]]; dc <- 1L
    for (i in seq_along(ch)) { if (dc >= col) return(i); dc <- if (ch[i] == "\t") ((dc - 1L) %/% 8L + 1L) * 8L + 1L else dc + 1L }
    length(ch) + 1L
  }
  slice <- function(r, L) {
    l1 <- pd$line1[r]; l2 <- pd$line2[r]; c1 <- cidx(l1, pd$col1[r]); c2 <- cidx(l2, pd$col2[r])
    if (l1 == l2) return(substr(L[l1], c1, c2))
    paste(c(substring(L[l1], c1), if (l2 > l1 + 1L) L[(l1 + 1L):(l2 - 1L)], substr(L[l2], 1L, c2)), collapse = "\n")
  }
  txt_of <- function(r) slice(r, LC)
  first_line <- function(r) trimws(substring(LN[pd$line1[r]], cidx(pd$line1[r], pd$col1[r])))
  first_tok <- vapply(KIDS, function(k) if (length(k)) pd$token[k[1]] else "", "")
  is_fun <- pd$token %in% EXPR & first_tok == "FUNCTION"

  depth <- integer(n); fnanc <- rep(NA_integer_, n)            # 부모가 먼저 오므로 한 번에 전파된다
  for (r in seq_len(n)) {
    q <- PROW[r]
    if (!is.na(q)) { depth[r] <- depth[q] + 1L; fnanc[r] <- if (is_fun[q]) q else fnanc[q] }
  }
  # r1(V6 B1 — regime_derivatives 회귀): if/else 가지 안의 대입은 '그럴 수도 있는' 상태다. 한 가지의 빈 표(data.table())가
  #   다른 가지의 해외 계보를 지우면 뒤의 결합이 판정에서 빠진다 → 가지 안에서는 해외 계보를 지우지 않는다(may 합집합).
  has_if <- vapply(KIDS, function(k) length(k) > 0L && any(pd$token[k] == "IF"), logical(1))
  in_cond <- logical(n)
  for (r in seq_len(n)) { q <- PROW[r]; if (!is.na(q)) in_cond[r] <- if (is_fun[q]) FALSE else (in_cond[q] || has_if[q]) }
  compound <- logical(n)                                         # '{'·function 을 품은 노드와 그 조상
  mark <- which(pd$token %in% c("'{'", "FUNCTION"))
  while (length(mark)) { q <- unique(PROW[mark]); q <- q[!is.na(q) & !compound[q]]; compound[q] <- TRUE; mark <- q }
  scope_of <- function(r) if (is.na(fnanc[r])) "G" else as.character(fnanc[r])
  scope_chain <- function(s) {
    out <- s
    while (s != "G") { f <- as.integer(s); s <- if (is.na(fnanc[f])) "G" else as.character(fnanc[f]); out <- c(out, s) }
    out
  }

  is_stmt <- function(r) {
    if (!(pd$token[r] %in% EXPR)) return(FALSE)
    q <- PROW[r]
    if (is.na(q)) return(TRUE)
    k <- kids(q); tk <- pd$token[k]
    if (length(k) && tk[1] == "'{'") return(TRUE)
    pos <- match(r, k)
    if (any(tk %in% c("IF", "WHILE", "FUNCTION"))) { cp <- match("')'", tk); return(!is.na(cp) && pos > cp) }
    if (any(tk == "FOR")) { fc <- match("forcond", tk); return(!is.na(fc) && pos > fc) }
    if (any(tk %in% c("REPEAT", "ELSE"))) return(TRUE)
    FALSE
  }
  asg_info <- function(r) {
    if (!(pd$token[r] %in% EXPR)) return(NULL)
    k <- kids(r); tk <- pd$token[k]
    a <- which(tk %in% ASG)
    if (length(a) != 1L || a == 1L || a == length(k)) return(NULL)
    if (pd$text[k[a]] == ":=") return(NULL)
    lhs <- k[a - 1L]; rhs <- k[a + 1L]
    if (tk[a] == "RIGHT_ASSIGN") { tmp <- lhs; lhs <- rhs; rhs <- tmp }
    list(lhs = lhs, rhs = rhs, super = pd$text[k[a]] %in% c("<<-", "->>"))
  }
  lhs_key <- function(t) {
    t <- gsub("\\s+", "", t)
    m <- regmatches(t, regexpr("^[.A-Za-z][.A-Za-z0-9_]*(\\$[.A-Za-z][.A-Za-z0-9_]*)?", t, perl = TRUE))
    if (!length(m)) { m <- regmatches(t, regexpr("[.A-Za-z][.A-Za-z0-9_]*", t, perl = TRUE)); if (!length(m)) return(NA_character_) }
    m
  }

  # ── 상태(렉시컬 스코프) ──
  ST <- new.env(parent = emptyenv())
  sk <- function(scope, name) paste0(scope, "::", name)
  find_key <- function(ref, scope) {
    base <- sub("\\$.*$", "", ref)
    for (s in scope_chain(scope)) {
      for (nm in unique(c(ref, base))) { k <- sk(s, nm); if (exists(k, envir = ST, inherits = FALSE)) return(k) }
    }
    NA_character_
  }
  get_state <- function(ref, scope) { k <- find_key(ref, scope); if (is.na(k)) NULL else get(k, envir = ST) }
  PK <- new.env(parent = emptyenv())            # 뒤로 민 기간 키(prev_ym <- format(dd - 32, ...)) — 스코프 키
  pkey_lagged <- function(ref, scope) {
    for (s0 in scope_chain(scope)) { k <- sk(s0, ref); if (exists(k, envir = PK, inherits = FALSE)) return(get(k, envir = PK)) }
    FALSE
  }
  set_state <- function(name, scope, st, super = FALSE) {
    k <- sk(scope, name)
    if (super) { k0 <- find_key(name, if (scope == "G") "G" else { f <- as.integer(scope); if (is.na(fnanc[f])) "G" else as.character(fnanc[f]) })
                 k <- if (is.na(k0)) sk("G", name) else k0 }
    if (is.null(st)) { if (exists(k, envir = ST, inherits = FALSE)) rm(list = k, envir = ST) } else assign(k, st, envir = ST)
    k
  }
  root_series <- list(); root_avail <- list(); nroot <- 0L
  lag_ev <- list(); pending <- list(); deferred <- list(); CANDS <- list(); JUDGED <- integer(0)
  new_root <- function(line) { nroot <<- nroot + 1L; sprintf("r%d@L%d", nroot, line) }
  note_series <- function(roots, ser, avail) for (r in roots) {
    root_series[[r]] <<- unique(c(root_series[[r]], ser))
    if (isTRUE(avail)) root_avail[[r]] <<- unique(c(root_avail[[r]], ser))
  }
  add_lag <- function(k, line) if (!is.na(k)) lag_ev[[k]] <<- c(lag_ev[[k]], line)
  # r1(V6 B2): 계열 열에 묶인 lag 증거(일간 class1 판정용). 구판 lag_ev(아무 shift)는 구조 판정(저장·기간 결합·결합 후 lag)에 그대로 쓴다
  lag_ev_t <- list()
  add_lag_t <- function(k, line) if (!is.na(k)) lag_ev_t[[k]] <<- c(lag_ev_t[[k]], line)
  lit_is_src <- function(lits) .la_c11_pathish_src(lits)

  # ── 함수 요약·인자 기본값 ──
  FN <- list(); FN_scope <- list()
  for (r in which(is_fun)) {
    q <- PROW[r]
    nm <- NA_character_
    if (!is.na(q)) {
      k <- kids(q); tk <- pd$token[k]; a <- which(tk %in% ASG)
      if (length(a) == 1L && a > 1L && k[a + 1L] == r) nm <- lhs_key(txt_of(k[a - 1L]))
      if (length(a) == 1L && tk[a] == "RIGHT_ASSIGN" && a < length(k) && k[a - 1L] == r) nm <- lhs_key(txt_of(k[a + 1L]))
    }
    bc <- slice(r, LC); bn <- slice(r, LS)
    lits <- .la_c11_literals(bc)
    src <- any(vapply(strsplit(bc, "\n", fixed = TRUE)[[1]], function(l) lit_is_src(.la_c11_literals(l)), logical(1))) ||
           any(grepl(P$path_sym, .la_c11_refs(bn), perl = TRUE)) ||
           any(grepl(P$loader_fn, .la_c11_calls(bn), perl = TRUE))
    # 인자 기본값이 원천 경로면 그 인자를 원천 경로로 둔다(함수 스코프)
    k <- kids(r); tk <- pd$token[k]
    for (j in which(tk == "SYMBOL_FORMALS")) {
      if (j + 2L <= length(k) && tk[j + 1L] == "EQ_FORMALS") {
        dl <- .la_c11_literals(slice(k[j + 2L], LC))
        if (length(dl) && lit_is_src(dl))
          assign(sk(as.character(r), pd$text[k[j]]), list(kind = "path", series = character(0), lagged = FALSE,
                 avail = FALSE, roots = character(0), fred = TRUE), envir = ST)
      }
    }
    if (!is.na(nm) && nzchar(nm)) {
      FN[[nm]] <- list(src = src, calls = .la_c11_calls(bn), line = pd$line1[r],
                       series = .la_c11_series_of(lits, bn, R, FALSE), lagged = .la_c11_has_lag(bc, bn), lagged_t = .la_c11_has_lag(bc, bn, SER_NAMES),
                       avail = grepl(P$avail_fn, bn, perl = TRUE), pminus = grepl(P$period_minus, bn, perl = TRUE))
    }
  }
  for (it in 1:5) {
    srcs <- names(FN)[vapply(FN, function(f) isTRUE(f$src), logical(1))]
    for (j in seq_along(FN)) if (!isTRUE(FN[[j]]$src) && any(FN[[j]]$calls %in% srcs)) FN[[j]]$src <- TRUE
  }
  fn_roots <- list()
  # 가용시점 층 어댑터: source() 대상 파일의 어댑터 + 같은 파일에서 가용시점 층을 부르는 함수
  WRAP <- unique(unlist(lapply(.la_c11_source_targets(path, code_all), function(f)
    tryCatch(.la_c11_wrappers_in(f), error = function(e) character(0)))))
  WRAP <- unique(c(WRAP, names(FN)[vapply(FN, function(f) isTRUE(f$avail), logical(1))]))
  for (it in 1:6) {                              # 어댑터를 부르는 같은 파일 함수도 어댑터(전이 폐포)
    more <- names(FN)[vapply(FN, function(f) !isTRUE(f$avail) && any(f$calls %in% WRAP), logical(1))]
    if (!length(more)) break
    for (nm in more) FN[[nm]]$avail <- TRUE
    WRAP <- unique(c(WRAP, more))
  }
  file_uses_avail <- grepl(P$avail_fn, nostr_all, perl = TRUE) || length(WRAP) > 0L

  # ── 조각 평가 ──
  # tgt_pure = X[, … := …] 의 대상 X 가 '순수' 해외 계보(원천에서 파생·다른 표와 결합한 적 없음) — 그 표의 열 shift 는
  #   (계열 이름이 아니어도) 그 계보의 lag 다(prev_MRS := shift(Macro_Risk_Score) · 판정서 1-6). 결합으로 섞인 표(RW·RAWDATA)는
  #   계열 이름에 묶인 shift 만 인정(무관한 열 shift 는 lag 아님 — V6 B2).
  eval_piece <- function(code, nostr, line, scope, tgt_pure = FALSE) {
    refs <- .la_c11_refs(nostr)
    sts <- lapply(refs, get_state, scope = scope); sts <- sts[!vapply(sts, is.null, logical(1))]
    kinds <- vapply(sts, function(s) s$kind, "")
    data <- sts[kinds == "data"]; paths <- sts[kinds == "path"]; names_ <- sts[kinds == "names"]
    for (fnm in intersect(.la_c11_calls(nostr), names(FN))) {
      f <- FN[[fnm]]
      if (is.null(f) || !isTRUE(f$src)) next
      if (is.null(fn_roots[[fnm]])) fn_roots[[fnm]] <<- new_root(f$line)
      data[[length(data) + 1L]] <- list(kind = "data", series = f$series, lagged = f$lagged, lagged_t = f$lagged_t, avail = f$avail,
                                        roots = fn_roots[[fnm]], fred = TRUE, pure = TRUE)
    }
    lits <- .la_c11_literals(code)
    path_lit <- lit_is_src(lits)
    path_sym <- any(grepl(P$path_sym, refs, perl = TRUE))
    loader <- any(grepl(P$loader_fn, .la_c11_calls(nostr), perl = TRUE))
    reads <- grepl(P$read_fn, nostr, perl = TRUE)
    # 원천 값을 다루는 문장이면 별칭 리터럴(col_select=c("Date","VIX"))·별칭 열 이름(f[is.finite(KRW_USD)])도 계열 지정이다.
    on_src <- length(data) > 0L || length(paths) > 0L || path_lit || path_sym || loader
    lit_ser <- .la_c11_series_of(lits, nostr, R, !on_src)
    col_ser <- if (on_src) { cn <- sub("^.*\\$", "", refs); unname(R$key2id[intersect(cn, c(R$ids, R$aliases))]) } else character(0)
    narrow <- unique(c(lit_ser, col_ser, unlist(lapply(names_, function(s) s$series))))
    # r1(V6 B2): lag 증거 = 이 문장이 다루는 해외 계보 이름(계보 변수·계열 id·별칭·Value)에 묶인 shift 만
    data_refs <- refs[vapply(refs, function(rf) { s0 <- get_state(rf, scope); !is.null(s0) && identical(s0$kind, "data") }, logical(1))]
    #   자기 열 lag(col := shift(col, k) — 표의 그 열을 lag 판으로 덮어씀)도 그 계보의 lag 다(판정서 1-6 '1개월 shift 판 적합').
    self_lag <- regmatches(nostr, gregexpr("(?<![.A-Za-z0-9_$])([.A-Za-z][.A-Za-z0-9_]*)\\s*:?=\\s*shift\\s*\\(\\s*\\1(?![.A-Za-z0-9_])",
                                           nostr, perl = TRUE))[[1]]
    self_lag <- sub("\\s*:?=.*$", "", self_lag, perl = TRUE)
    tgt_cols <- if (isTRUE(tgt_pure)) unique(unlist(lapply(.la_c11_shift_spans(code, nostr)$arg1, .la_c11_refs))) else character(0)
    has_lag_t <- .la_c11_has_lag(code, nostr, unique(c(SER_NAMES, data_refs, sub("\\$.*$", "", data_refs), self_lag, tgt_cols)))
    has_lag <- .la_c11_has_lag(code, nostr)                      # 구판(아무 shift) — 구조 판정용
    is_mixjoin <- grepl(P$join, nostr, perl = TRUE) || grepl(P$align, nostr, perl = TRUE)
    pm <- regmatches(nostr, gregexpr(P$period_eq, nostr, perl = TRUE))[[1]]
    if (length(pm) && length(data) && !has_lag) {   # 뒤로 민 기간 키로 고른 행 = 기간 lag(판정서 1-6 레거시 분류)
      keys <- trimws(sub(P$period_lhs, "", pm, perl = TRUE))
      if (any(vapply(keys, function(x) grepl(P$period_minus, x, perl = TRUE) ||
            any(vapply(.la_c11_refs(x), function(rf) isTRUE(pkey_lagged(rf, scope)), logical(1))), logical(1)))) { has_lag <- TRUE; has_lag_t <- TRUE }
    }
    has_avail <- grepl(P$avail_fn, nostr, perl = TRUE) || any(.la_c11_calls(nostr) %in% WRAP) ||
                 (file_uses_avail && grepl(P$avail_key, nostr, perl = TRUE))
    subset_seed <- length(lit_ser) > 0L && grepl(P$series_ctx, nostr, perl = TRUE) && grepl(P$subset_ctx, nostr, perl = TRUE)
    out <- NULL
    if (length(data)) {
      out <- list(kind = "data",
                  series = if (length(narrow)) narrow else unique(unlist(lapply(data, function(s) s$series))),
                  lagged = has_lag || all(vapply(data, function(s) isTRUE(s$lagged), logical(1))),
                  lagged_t = has_lag_t || all(vapply(data, function(s) isTRUE(s$lagged_t), logical(1))),
                  avail = has_avail || all(vapply(data, function(s) isTRUE(s$avail), logical(1))),
                  roots = unique(unlist(lapply(data, function(s) s$roots))),
                  fred = any(vapply(data, function(s) isTRUE(s$fred), logical(1))),
                  pure = all(vapply(data, function(s) isTRUE(s$pure), logical(1))) && !is_mixjoin)
    } else if (loader || ((path_lit || path_sym || length(paths)) && reads) || subset_seed) {
      out <- list(kind = "data", series = narrow, lagged = has_lag, lagged_t = has_lag_t, avail = has_avail, roots = new_root(line),
                  fred = loader || path_lit || path_sym || length(paths) > 0L, pure = !is_mixjoin)
    } else if (path_lit || path_sym || length(paths)) {
      out <- list(kind = "path", series = character(0), lagged = FALSE, avail = FALSE, roots = character(0), fred = TRUE)
    } else if (length(narrow)) {
      out <- list(kind = "names", series = narrow, lagged = FALSE, avail = FALSE, roots = character(0), fred = FALSE)
    }
    if (!is.null(out) && out$kind == "data" && length(out$series)) note_series(out$roots, out$series, out$avail)
    list(state = out, data = data, has_lag = has_lag, has_lag_t = has_lag_t, has_avail = has_avail, refs = refs)
  }

  # ── 판정 ──
  # lagged_t = 그 lag 가 계열 열에 묶였는가(r1). lagged 인데 묶이지 않았으면 일간 class1 계열은 당일 값 사용(bad1).
  bad_of <- function(ser, lagged, fred, lagged_t = lagged) {
    # 판정 범위 = 해외(FRED) — FRED 원천 파일에서 온 계보(fred=TRUE)는 전부, 그 밖의 계보(Series== 부분집합 등)는
    #  규칙 파일 source 가 FRED 인 계열만. ECOS 국내 계열(시각 미검증 · 판정서 ② '권장')은 여기서 막지 않는다.
    if (!fred && length(ser)) { f <- R$foreign[ser]; ser <- ser[!is.na(f) & f] }
    if (!length(ser)) return(list(bad = if (fred) "<계열 미식별>" else character(0), prohib = character(0), bad1 = character(0)))
    cl <- R$cls[ser]; cl[is.na(cl)] <- "class2"
    prohib <- ser[cl == "prohibited"]
    list(bad = if (lagged) ser[cl == "class2"] else ser[cl %in% c("class1", "class2")],
         prohib = if (fred) prohib else character(0),                  # 원천 불명 계보의 별칭 금지 판정은 보류
         bad1 = if (lagged && !isTRUE(lagged_t)) ser[cl == "class1"] else character(0))
  }
  emit <- function(code, line, stmt, msg, roots)
    CANDS[[length(CANDS) + 1L]] <<- list(code = code, line = line, stmt = stmt, msg = msg, roots = roots)
  msg_same <- function(bad, kind) sprintf(
    "해외 계열(%s)의 관측일을 lag 없이 한국 날짜와 %s — 가용일 전 사용(판정서 V-08 형태). fred_asof_join()(02_Infrastructure/data/fred_availability.R) 경유 필요",
    paste(bad, collapse = ","), if (identical(kind, "asof")) "as-of 절단" else if (identical(kind, "period")) "같은 기간 라벨로 조회(동월)" else "결합")
  msg_pub <- function(bad) sprintf(
    "임시 lag(1일·1행)이 계열 %s 의 가용일 규칙(06_Registry/fred_availability_rules.json — 공표형·ICE d+2 등)에 못 미침(판정서 V-01·V-11 형태). fred_asof_join() 경유 필요",
    paste(bad, collapse = ","))
  msg_proh <- function(p) sprintf("금지 계열 %s 사용 — 대체 = %s (decision_register PIT-C11-CONVENTIONS ①, 규칙 파일 status=prohibited)",
                                  paste(p, collapse = ","), paste(unique(R$repl[p]), collapse = ","))
  msg_untied <- function(bad) sprintf(
    "해외 일간 계열(%s)의 lag 가 그 계열 열이 아니라 다른 열·차분(x - shift(x))에 걸려 있다 — 결합된 값은 관측일 당일 값(판정서 V-08 형태 · r1 V6 B2). fred_asof_join() 경유 필요",
    paste(bad, collapse = ","))
  judge <- function(line, stmt, st, lagged, kind, lhs_k, lagged_t = lagged) {
    if (!length(st$series)) {
      deferred[[length(deferred) + 1L]] <<- list(line = line, stmt = stmt, roots = st$roots, lagged = lagged,
                                                 lagged_t = lagged_t, kind = kind, lhs = lhs_k, fred = st$fred)
      return(invisible(NULL))
    }
    b <- bad_of(st$series, lagged, st$fred, lagged_t)
    if (length(b$prohib)) emit("C11_PROHIBITED_SERIES", line, stmt, msg_proh(b$prohib), st$roots)
    if (lagged && length(b$bad1)) emit("C11_FRED_SAMEDATE", line, stmt, msg_untied(b$bad1), st$roots)
    if (!length(b$bad)) return(invisible(NULL))
    if (!lagged && kind == "join" && !is.na(lhs_k)) {
      pending[[length(pending) + 1L]] <<- list(line = line, stmt = stmt, roots = st$roots, ser = st$series,
                                               lhs = lhs_k, fred = st$fred)
      return(invisible(NULL))
    }
    if (!lagged) emit("C11_FRED_SAMEDATE", line, stmt, msg_same(b$bad, kind), st$roots)
    else emit("C11_PUB_LAG", line, stmt, msg_pub(b$bad), st$roots)
    invisible(NULL)
  }
  sink <- function(nostr, line, stmt, ev, lhs_k, scope = "G", code = nostr) {
    d <- ev$data
    if (!length(d)) return(invisible(NULL))
    is_join <- grepl(P$join, nostr, perl = TRUE); is_asof <- grepl(P$asof, nostr, perl = TRUE)
    # r1(V6 B1 — fail-closed): 날짜 정렬 형태(match·findInterval·approx·between·Date == d·substr 기간·이름 벡터)와
    #   data.table 키 결합 X[Y](해외 계보 X 를 다른 표 Y 로 색인 — setkey 또는 Y 가 계보 변수)도 결합으로 본다.
    if (!is_join && grepl(P$align, nostr, perl = TRUE)) is_join <- TRUE
    if (!is_join) {
      mm <- regmatches(nostr, gregexpr("(?<![.A-Za-z0-9_$])[.A-Za-z][.A-Za-z0-9_]*\\s*\\[\\s*[.A-Za-z][.A-Za-z0-9_]*\\s*(?=[],])",
                                       nostr, perl = TRUE))[[1]]
      for (cp in mm) {
        o <- sub("\\s*\\[.*$", "", cp); i2 <- trimws(sub("^.*\\[", "", cp))
        so <- get_state(o, scope); si <- get_state(i2, scope)
        fo <- !is.null(so) && identical(so$kind, "data") && isTRUE(so$fred)
        fi <- !is.null(si) && identical(si$kind, "data") && isTRUE(si$fred)
        keyed <- grepl(sprintf("(?<![.A-Za-z0-9_])setkeyv?\\s*\\(\\s*%s(?![.A-Za-z0-9_])", gsub(".", "\\.", o, fixed = TRUE)),
                       nostr_all, perl = TRUE)
        if ((fo && (!is.null(si) || keyed)) || (fi && !is.null(so))) { is_join <- TRUE; break }
      }
    }
    is_persist <- grepl(P$persist, nostr, perl = TRUE)
    pm <- regmatches(nostr, gregexpr(P$period_eq, nostr, perl = TRUE))[[1]]
    is_period <- length(pm) > 0L
    period_join <- FALSE
    if (is_join && !grepl("(?<![.A-Za-z0-9_])roll\\s*=", nostr, perl = TRUE)) {
      spec <- regmatches(code, gregexpr(P$join_key, code, perl = TRUE))[[1]]
      if (length(spec)) {
        if (!any(grepl(P$date_key, spec, perl = TRUE))) is_join <- FALSE     # 날짜·기간이 아닌 키(by = "Ticker")
        else period_join <- any(grepl(P$period_key, spec, perl = TRUE)) &&
                            !any(grepl("(?i)date", spec, perl = TRUE))
      }
    }
    if (!(is_join || is_asof || is_persist || is_period)) return(invisible(NULL))
    if ((is_period || period_join) && any(vapply(d, function(s) isTRUE(s$fred), logical(1))))
      JUDGED <<- c(JUDGED, line)                  # 해외 계보의 기간 조회 — C3 줄 규칙 대신 이 계보 판정이 맡는다
    if (ev$has_avail || all(vapply(d, function(s) isTRUE(s$avail), logical(1)))) return(invisible(NULL))
    lagged <- ev$has_lag || all(vapply(d, function(s) isTRUE(s$lagged), logical(1)))
    lagged_t <- ev$has_lag_t || all(vapply(d, function(s) isTRUE(s$lagged_t), logical(1)))
    if (is_persist && !is_join && !is_asof && !is_period && !lagged) return(invisible(NULL))   # 관측일 그대로의 원천 저장 = 적합
    if (period_join && !is_asof) {                # 기간 키 결합: 기간을 민 표(shift 1행 = 1기간)면 판정서 1-6 분류대로 적합
      if (lagged) return(invisible(NULL))
      is_period <- TRUE; is_join <- FALSE
    }
    if (is_period && !is_join && !is_asof) {
      # 기간 라벨 선택: 키가 뒤로 민 기간(전월 등)이거나 데이터 라벨이 앞으로 밀렸으면 판정서 1-6 레거시 분류대로 적합.
      #  그 밖(같은 달 조회) = 동월 사용. 기간 lag 의 충분성(월간 공표 계열)은 이 정적 검사가 보증하지 않는다 — 한계로 신고.
      keys <- trimws(sub(P$period_lhs, "", pm, perl = TRUE))
      plag <- any(vapply(keys, function(x) grepl(P$period_minus, x, perl = TRUE) ||
                           any(vapply(.la_c11_refs(x), function(rf) isTRUE(pkey_lagged(rf, scope)), logical(1))), logical(1)))
      if (lagged || plag) return(invisible(NULL))
    }
    kind <- if (is_join) "join" else if (is_asof) "asof" else if (is_period) "period" else "persist"
    st <- ev$state
    if (is.null(st) || st$kind != "data")
      st <- list(series = unique(unlist(lapply(d, function(s) s$series))), roots = unique(unlist(lapply(d, function(s) s$roots))),
                 fred = any(vapply(d, function(s) isTRUE(s$fred), logical(1))))
    if (kind == "asof" && lagged && !length(st$series)) {        # 계열 미식별 임시 lag 절단 = 변환 — 계보 끝에서 판정
      deferred[[length(deferred) + 1L]] <<- list(line = line, stmt = stmt, roots = st$roots, lagged = TRUE, lagged_t = lagged_t,
                                                 kind = kind, lhs = lhs_k, fred = st$fred)
      return(invisible(NULL))
    }
    judge(line, stmt, st, lagged, kind, lhs_k, lagged_t)
  }

  # ── 후위 순회(안쪽 먼저, 원문 순서) ──
  cand <- which(pd$token %in% EXPR)
  cand <- cand[order(pd$line2[cand], pd$col2[cand], -depth[cand])]
  for (r in cand) {
    a <- asg_info(r)
    if (is.null(a) && compound[r]) next
    if (is.null(a) && !is_stmt(r)) next
    line <- pd$line1[r]; scope <- scope_of(r)
    if (!is.null(a)) {
      if (is_fun[a$rhs]) next
      name <- lhs_key(txt_of(a$lhs))
      code <- slice(a$rhs, LC); nostr <- slice(a$rhs, LS)
      ev <- eval_piece(code, nostr, line, scope)
      k_l <- if (is.na(name)) NA_character_ else sk(scope, name)
      if (!compound[a$rhs]) sink(nostr, line, first_line(r), ev, k_l, scope, code)
      if (!is.na(name)) {
        if (is.null(ev$state)) assign(sk(scope, name), grepl(P$period_minus, nostr, perl = TRUE) ||
          any(vapply(FN[intersect(.la_c11_calls(nostr), names(FN))], function(f) isTRUE(f$pminus), logical(1))), envir = PK)
        # 가지 안의 '빈 표 자리표시'(data.table()·data.frame()·list()·tibble()·NULL)만 계보를 지우지 않는다(스칼라 기본값은 덮어쓴다)
        empty_ph <- grepl("^\\s*(NULL|(data\\.table|data\\.frame|list|tibble)\\s*\\(\\s*\\))\\s*$", nostr, perl = TRUE)
        s_old <- if (is.null(ev$state) && in_cond[r] && empty_ph) get_state(name, scope) else NULL
        keep_old <- !is.null(s_old) && identical(s_old$kind, "data") && isTRUE(s_old$fred)
        k_l <- if (keep_old) find_key(name, scope) else set_state(name, scope, ev$state, a$super)
        if (ev$has_lag && !is.null(ev$state) && ev$state$kind == "data") add_lag(k_l, line)
        if (ev$has_lag_t && !is.null(ev$state) && ev$state$kind == "data") add_lag_t(k_l, line)
      }
      next
    }
    code <- slice(r, LC); nostr <- slice(r, LS)
    stmt <- first_line(r)
    mt <- regmatches(nostr, regexec("^\\s*([.A-Za-z][.A-Za-z0-9_]*(\\$[.A-Za-z][.A-Za-z0-9_]*)?)\\s*\\[", nostr, perl = TRUE))[[1]]
    if (length(mt) && grepl(":=", nostr, fixed = TRUE)) {        # X[..., := ...] 제자리 수정(참조 의미론)
      name <- mt[2]; off <- nchar(mt[1])
      k_t <- find_key(name, scope)
      tgt <- if (is.na(k_t)) NULL else get(k_t, envir = ST)
      tp <- !is.null(tgt) && identical(tgt$kind, "data") && isTRUE(tgt$fred) && isTRUE(tgt$pure)
      ev <- eval_piece(substring(code, off + 1L), substring(nostr, off + 1L), line, scope, tgt_pure = tp)
      ev2 <- ev
      if (!is.null(tgt) && tgt$kind == "data") ev2$data <- c(list(tgt), ev$data)
      sink(nostr, line, stmt, ev2, NA_character_, scope, code)
      rd <- ev$data
      if (!is.null(tgt) && tgt$kind == "data") {
        tgt$lagged <- (isTRUE(tgt$lagged) && all(vapply(rd, function(s) isTRUE(s$lagged), logical(1)))) || ev$has_lag
        tgt$lagged_t <- (isTRUE(tgt$lagged_t) && all(vapply(rd, function(s) isTRUE(s$lagged_t), logical(1)))) || ev$has_lag_t
        if (length(rd)) {
          tgt$roots <- unique(c(tgt$roots, unlist(lapply(rd, function(s) s$roots))))
          tgt$series <- unique(c(tgt$series, unlist(lapply(rd, function(s) s$series))))
          tgt$fred <- isTRUE(tgt$fred) || any(vapply(rd, function(s) isTRUE(s$fred), logical(1)))
        }
        if (ev$has_avail) tgt$avail <- TRUE
        if (length(rd) || grepl(P$join, nostr, perl = TRUE) || grepl(P$align, nostr, perl = TRUE)) tgt$pure <- FALSE   # 다른 표·결합이 섞이면 순수 아님
        assign(k_t, tgt, envir = ST)
      } else if (length(rd)) {
        k_t <- set_state(name, scope, list(kind = "data", series = unique(unlist(lapply(rd, function(s) s$series))),
                         lagged = ev$has_lag || all(vapply(rd, function(s) isTRUE(s$lagged), logical(1))),
                         lagged_t = ev$has_lag_t || all(vapply(rd, function(s) isTRUE(s$lagged_t), logical(1))),
                         avail = ev$has_avail, roots = unique(unlist(lapply(rd, function(s) s$roots))),
                         fred = any(vapply(rd, function(s) isTRUE(s$fred), logical(1)))))
      }
      if (ev$has_lag) add_lag(if (is.na(k_t)) sk(scope, name) else k_t, line)
      if (ev$has_lag_t) add_lag_t(if (is.na(k_t)) sk(scope, name) else k_t, line)
      next
    }
    ev <- eval_piece(code, nostr, line, scope)
    sink(nostr, line, stmt, ev, NA_character_, scope, code)
    if (ev$has_lag && length(ev$data))            # 반환식 등에서 결합 결과에 lag 를 거는 형태 — shift(j$x, 1)
      for (ref in ev$refs) { s0 <- get_state(ref, scope); if (!is.null(s0) && s0$kind == "data") {
        add_lag(find_key(ref, scope), line); if (ev$has_lag_t) add_lag_t(find_key(ref, scope), line) } }
  }

  # ── 계보 끝 판정 ──
  for (p in pending) {                            # 결합 뒤 같은 결과 변수에 lag 가 걸리면 임시 lag 판으로
    if (any(lag_ev[[p$lhs]] > p$line)) judge(p$line, p$stmt, list(series = p$ser, roots = p$roots, fred = p$fred),
                                             TRUE, "join_then_lag", NA_character_, lagged_t = any(lag_ev_t[[p$lhs]] > p$line))
    else { b <- bad_of(p$ser, FALSE, p$fred); if (length(b$bad)) emit("C11_FRED_SAMEDATE", p$line, p$stmt, msg_same(b$bad, "join"), p$roots) }
  }
  for (d in deferred) {                           # 계열 미식별 지점: root 에서 좁혀진 계열(가용시점 층 경유분 제외) → 파일 계열
    narrowed <- unique(unlist(root_series[d$roots]))
    ser <- setdiff(if (length(narrowed)) narrowed else file_series, unique(unlist(root_avail[d$roots])))
    if (!length(ser) && length(narrowed)) next    # 좁혀진 계열이 전부 가용시점 층 경유
    later <- !is.na(d$lhs) && any(lag_ev[[d$lhs]] > d$line)
    lg <- d$lagged || later
    lg_t <- isTRUE(d$lagged_t) || (!is.na(d$lhs) && any(lag_ev_t[[d$lhs]] > d$line))
    b <- bad_of(ser, lg, d$fred, lg_t)
    if (length(b$prohib)) emit("C11_PROHIBITED_SERIES", d$line, d$stmt, msg_proh(b$prohib), d$roots)
    if (lg && length(b$bad1)) emit("C11_FRED_SAMEDATE", d$line, d$stmt, msg_untied(b$bad1), d$roots)
    if (!length(b$bad)) next
    if (lg) emit("C11_PUB_LAG", d$line, d$stmt, msg_pub(b$bad), d$roots)
    else emit("C11_FRED_SAMEDATE", d$line, d$stmt, msg_same(b$bad, d$kind), d$roots)
  }
  # ── 방출: 줄 순서로, (코드, 계보)당 첫 지점만 — 같은 오염 계보를 소비처마다 되풀이하지 않는다 ──
  if (length(CANDS)) {
    CANDS <- CANDS[order(vapply(CANDS, function(z) as.integer(z$line), 0L))]
    seen <- list()
    for (cd in CANDS) {
      prev <- seen[[cd$code]]
      if (length(cd$roots) && length(prev) && all(cd$roots %in% prev)) next
      seen[[cd$code]] <- unique(c(prev, cd$roots))
      add(cd$code, cd$line, cd$stmt, cd$msg)
    }
  }
  invisible(list(n = length(CANDS), judged = unique(JUDGED)))
}

# r1: 가용시점 층을 쓰는 import 모듈의 이름(별칭 포함)과 from-import 함수 이름. 모듈 파일 본문이 fred_asof_join/annotate 를
#   부르거나 정의하면 그 모듈을 경유한 호출은 가용시점 층 경유로 본다(.la_c11_py_avail_import 와 같은 탐색 경로).
.la_c11_py_avail_mods <- function(path, nostr_all) {
  L <- strsplit(nostr_all, "\n", fixed = TRUE)[[1]]
  root <- .la_c11_code_root(); d <- dirname(path)
  dirs <- unique(c(d, file.path(root, "02_Infrastructure", c("data", "regime", "ml_pipeline", "factor_db", "ops", "ast"))))
  is_avail <- function(m0) {
    f <- file.path(dirs, paste0(m0, ".py")); f <- f[file.exists(f)]
    if (!length(f)) return(FALSE)
    t <- .la_c11_strip(paste(readLines(f[1], warn = FALSE, encoding = "UTF-8"), collapse = "\n"), FALSE, py = TRUE)
    grepl("(?<![A-Za-z0-9_])(fred_asof_join|fred_avail_annotate)\\s*\\(", t, perl = TRUE)
  }
  mods <- character(0); funs <- character(0)
  for (ln in L) {
    m1 <- regmatches(ln, regexec("^\\s*import\\s+([A-Za-z_][A-Za-z0-9_]*)(\\s+as\\s+([A-Za-z_][A-Za-z0-9_]*))?", ln, perl = TRUE))[[1]]
    if (length(m1) && is_avail(m1[2])) mods <- c(mods, if (nzchar(m1[4])) m1[4] else m1[2])
    m2 <- regmatches(ln, regexec("^\\s*from\\s+([A-Za-z_][A-Za-z0-9_]*)\\s+import\\s+(.+)$", ln, perl = TRUE))[[1]]
    if (length(m2) && is_avail(m2[2])) {
      nm <- trimws(strsplit(gsub("[()]", "", m2[3]), ",", fixed = TRUE)[[1]])
      nm <- sub("^.*\\s+as\\s+", "", nm, perl = TRUE)
      funs <- c(funs, nm[grepl("^[A-Za-z_][A-Za-z0-9_]*$", nm)])
    }
  }
  list(mods = unique(mods), funs = unique(funs))
}

# r1(V6 B2): 파이썬 해외 원천 변수 — 대입 줄 'x = …' 의 오른쪽이 원천 경로 리터럴(fred…)·FRED 경로 기호를 품거나
#   이미 원천 변수인 이름을 쓰면 x 도 원천 변수(전이). 가용시점 층(fred_asof_join·fred_avail_*)을 부르는 대입은 원천이 아니다.
.la_c11_py_fred_vars <- function(cl, nl) {
  asg <- regmatches(nl, regexec("^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*=(?!=)\\s*(.*)$", nl, perl = TRUE))
  sym_rx <- "(?<![A-Za-z0-9_])(FRED|fred)_[A-Za-z0-9_]*(CACHE|PATH|FILE|LONG|WIDE)(?![A-Za-z0-9_])"
  fv <- character(0)
  for (it in 1:6) {
    grew <- FALSE
    for (k in seq_along(asg)) {
      a <- asg[[k]]
      if (length(a) < 3L || a[2] %in% fv) next
      rhs_n <- a[3]
      if (grepl("(?<![A-Za-z0-9_])(fred_asof_join|fred_avail_annotate|fred_avail_date)\\s*\\(", rhs_n, perl = TRUE)) next
      rhs_c <- sub("^\\s*[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*", "", cl[k], perl = TRUE)
      hit <- .la_c11_pathish_src(.la_c11_literals(rhs_c)) || grepl(sym_rx, rhs_n, perl = TRUE) ||
        (length(fv) > 0L && grepl(sprintf("(?<![A-Za-z0-9_.])(%s)(?![A-Za-z0-9_])", paste(fv, collapse = "|")), rhs_n, perl = TRUE))
      if (isTRUE(hit)) { fv <- c(fv, a[2]); grew <- TRUE }
    }
    if (!grew) break
  }
  unique(fv)
}

# ── 본체(Python — 파일 단위 근사) ──────────────────────────────────────────────
#  파이썬은 이 검출기에서 파서를 쓰지 않는다. 파일이 해외 원천을 만지고, 날짜 결합(merge_asof/merge/join/reindex/asof)이
#  있는데 가용시점 층(fred_asof_join·fred_avail_*)을 쓰지 않으면 결합 줄마다 판정한다. 파일 안에 양의 shift 가
#  있으면 임시 lag 판(class2 계열만 위반), 없으면 lag 없음 판(class1·class2 위반).
.la_c11_scan_py <- function(path, lines, add) {
  txt <- paste(lines, collapse = "\n")
  code_all <- .la_c11_strip(txt, TRUE, py = TRUE); nostr_all <- .la_c11_strip(txt, FALSE, py = TRUE)
  R <- .la_c11_rules()
  P <- .LA_C11
  lits <- .la_c11_literals(code_all)
  cl <- strsplit(code_all, "\n", fixed = TRUE)[[1]]
  nl <- strsplit(nostr_all, "\n", fixed = TRUE)[[1]]
  fred_path <- any(vapply(lits, .la_c11_pathish_src, logical(1))) ||
    any(vapply(cl, function(l) .la_c11_pathish_src(.la_c11_literals(l)), logical(1))) ||
    grepl("(?<![A-Za-z0-9_])(FRED|fred)_[A-Za-z0-9_]*(CACHE|PATH|FILE|LONG|WIDE)(?![A-Za-z0-9_])", nostr_all, perl = TRUE)
  ids_hit <- isTRUE(R$ok) && any(lits %in% R$ids[R$foreign[R$ids] %in% TRUE])   # 해외(FRED) 계열 id 만
  if (!(fred_path || ids_hit)) return(invisible(0L))
  R <- .la_c11_disambiguate(R, lits)
  if (!isTRUE(R$ok)) {
    add("PY_C11_RULES_UNAVAILABLE", 1L, basename(path), sprintf("해외 원천을 만지는데 규칙 파일을 못 읽음 — %s (fail-closed)", R$why))
    return(invisible(1L))
  }
  uses_avail <- grepl("(?<![A-Za-z0-9_])(fred_asof_join|fred_avail_annotate|fred_avail_date)\\s*\\(", nostr_all, perl = TRUE) ||
    .la_c11_py_avail_import(path, nostr_all)
  # 날짜 결합 줄(os.path.join·"sep".join 은 문자열 결합이라 제외) · r1: .loc[:d, …] 절단(관측일 as-of)도 결합으로 본다(V6 PYB3)
  join_ln <- which(grepl("\\.merge_asof\\s*\\(|(?<![A-Za-z0-9_])merge_asof\\s*\\(|\\.merge\\s*\\(|(?<![A-Za-z0-9_])pd\\.merge\\s*\\(|(?<!path)(?<![\"'])\\.join\\s*\\(|\\.reindex\\s*\\(|\\.asof\\s*\\(|\\.loc\\s*\\[\\s*:\\s*[A-Za-z_]",
                           nl, perl = TRUE))
  if (!length(join_ln)) return(invisible(0L))
  if (uses_avail) {
    # ★r1(V6 B2): 가용시점 층을 한 번 부르거나 import 했다고 파일 전체를 면제하지 않는다 — 해외 원천에서 온 변수
    #   (원천 경로 리터럴·FRED 경로 기호로 읽은 변수와 그 파생)를 쓰는 결합 줄은 판정한다(fred_asof_join 을 부르는 줄 제외).
    fv <- .la_c11_py_fred_vars(cl, nl)
    if (!length(fv)) return(invisible(0L))
    rxv <- sprintf("(?<![A-Za-z0-9_.])(%s)(?![A-Za-z0-9_])", paste(fv, collapse = "|"))
    # 같은 줄에서 가용시점 층(또는 그 층을 쓰는 import 모듈의 함수 — gp.build(kr, f))을 거치는 결합은 제외
    am <- .la_c11_py_avail_mods(path, nostr_all)
    via <- "(?<![A-Za-z0-9_])(fred_asof_join|fred_avail_annotate|fred_avail_date)\\s*\\("
    if (length(am$mods)) via <- paste0(via, sprintf("|(?<![A-Za-z0-9_.])(%s)\\.[A-Za-z_][A-Za-z0-9_]*\\s*\\(", paste(am$mods, collapse = "|")))
    if (length(am$funs)) via <- paste0(via, sprintf("|(?<![A-Za-z0-9_.])(%s)\\s*\\(", paste(am$funs, collapse = "|")))
    join_ln <- join_ln[grepl(rxv, nl[join_ln], perl = TRUE) & !grepl(via, nl[join_ln], perl = TRUE)]
    if (!length(join_ln)) return(invisible(0L))
  }
  # ★r1(V6 B2): lag 는 **계열 열에 걸린** shift 만 — df["VIXCLS"].shift(1) · df.VIXCLS.shift() · df["Value"].shift(1).
  #   다른 열의 shift(kr.groupby("Ticker")["ret"].shift(1))는 해외 계열의 lag 가 아니다.
  nmx <- paste(gsub(".", "\\.", unique(c(R$ids, R$aliases, "Value", "value")), fixed = TRUE), collapse = "|")
  lag_rx <- sprintf("(\\[\\s*[\"'](%s)[\"']\\s*\\]|\\.(%s))\\s*\\.shift\\s*\\(\\s*(periods\\s*=\\s*)?([1-9]|\\))", nmx, nmx)
  lag_file <- grepl(lag_rx, code_all, perl = TRUE)
  ser <- .la_c11_series_of(lits, nostr_all, R, FALSE)
  if (!fred_path) ser <- ser[R$foreign[ser] %in% TRUE]      # FRED 원천 파일이 아니면 해외 계열만 판정
  if (!length(ser)) ser <- "<계열 미식별>"
  clv <- R$cls[ser]; clv[is.na(clv)] <- "class2"
  # 금지 계열: id 리터럴(DEXKOUS)이거나, FRED 원천 파일에서 별칭(KRW_USD)을 쓴 경우만 — ECOS 원/달러 별칭과 구분
  lit_ids <- unname(R$key2id[intersect(lits, R$ids)])
  prohib <- ser[clv == "prohibited" & (ser %in% lit_ids | fred_path)]
  bad <- if (lag_file) ser[clv == "class2"] else ser[clv %in% c("class1", "class2")]
  for (ln in join_ln) {
    stmt <- trimws(lines[ln])
    if (length(prohib)) add("PY_C11_PROHIBITED_SERIES", ln, stmt, sprintf("금지 계열 %s — 대체 = %s (PIT-C11-CONVENTIONS ①)",
                                                                  paste(prohib, collapse = ","), paste(unique(R$repl[prohib]), collapse = ",")))
    if (length(bad)) add(if (lag_file) "PY_C11_PUB_LAG" else "PY_C11_FRED_SAMEDATE", ln, stmt, sprintf(
      "해외 계열(%s) 날짜 결합이 가용시점 층을 거치지 않음(%s) — fred_availability.py fred_asof_join() 경유 필요(판정서 ②·V-03)",
      paste(bad, collapse = ","), if (lag_file) "임시 shift 로는 공표형 규칙 미충족" else "lag 없음"))
  }
  invisible(length(join_ln))
}

cat("[lookahead_detector] Loaded. Functions: detect_lookahead(), detect_lookahead_dir(), detect_gate15_infra_pit()\n")
