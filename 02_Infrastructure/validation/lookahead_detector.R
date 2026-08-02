#==============================================================================
# Lookahead Detector — 미래참조 자동 검출 (C1~C9)
# run_all.R 실행 전 자동 스캔. 위반 시 실행 차단.
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
      ctx <- get_context(i)
      # Macro/regime lookups are OK (MRS, FRED, regime are monthly published)
      if (!grepl("mrs|macro|regime|fred|Macro_Risk", ctx, ignore.case = TRUE)) {
        add_violation("C3", i, line_trimmed,
          "Same-month lookup for non-macro data. Verify PIT compliance (use previous month).")
      }
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
    # C11: Data timeline — FRED/외부 데이터 시차 미반영 (Session 38b)
    # =========================================================================
    # Pattern: read_parquet.*fred or FRED without shift/lag nearby
    if (grepl("read_parquet.*fred|FRED_MACRO_CACHE|FRED_REGIME_CACHE|macro_fred", line, ignore.case = TRUE)) {
      ctx <- get_context(i, 10)
      if (!grepl("shift|lag|1일|1d|lagged|regime_engine_v[34]", ctx, ignore.case = TRUE)) {
        add_violation("C11_FRED", i, line_trimmed,
          "FRED data loaded without visible lag. US data needs 1-day lag for KST timezone. Use shift(lag=1) or regime_engine_v4.")
      }
    }

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

cat("[lookahead_detector] Loaded. Functions: detect_lookahead(), detect_lookahead_dir(), detect_gate15_infra_pit()\n")
