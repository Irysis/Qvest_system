## ============================================================================
## audit_bt_result.R — Backtest Result Contract v1.0 audit (**18 checks**, 구 표기 11 정정)
## L3 hard block trigger: Critical FAIL 시 metrics is_official=FALSE 강제
## Lawbook §20
## L-249 enforcement (2026-04-29): Check 11 frequency-cadence mismatch detection
##   — Charter v1.5 §13: frequency/annualization_factor vs actual data spacing
##   — Frequency mislabel inflates Sharpe by sqrt(N_declared/N_actual)
##   — Bi-monthly inner-join + 'daily' annotation = AX-002 fabrication
##   — Trigger: median(diff(date)) outside declared-frequency tolerance band
## Check 17 신설 (2026-08-09): benchmark **값** 타당성 + 퇴화 계열 차단
##   — Check 5(benchmark_aligned)는 날짜 겹침만 세므로 -89.38% 벤치가 "alignment PASS" 통과,
##     alpha_search 16 run 이 그 벤치로 채점됨(연 초과 15/16 부호 반전). 존재↔정체 혼동 계통.
##   — 검사기 08_Tests/hooks/test_benchmark_values_plausible.R
##     실데이터 466 run 재생: 오염 16/16 발화 · 청정 450/450 무발화 · MUT-1 이 Check 5 구멍 실증.
## ============================================================================

suppressMessages({library(data.table)})

#' Audit bt_result — 10 checks
#' @param bt_result list (10 components)
#' @return bt_result with audit table populated AND metrics is_official adjusted
audit_bt_result <- function(bt_result) {
  audit_rows <- list()
  add_check <- function(group, name, status, details, affected = "", severity = "low") {
    audit_rows[[length(audit_rows) + 1]] <<- data.table(
      run_id = bt_result$manifest$run_id[1],
      check_group = group, check_name = name, status = status,
      details = details, affected_metrics = affected, severity = severity
    )
  }

  # Check 1: realized_return_vector_exists
  pr <- bt_result$period_returns
  if (is.null(pr) || nrow(pr) == 0 || !"ret_net" %in% names(pr) ||
      all(is.na(pr$ret_net))) {
    add_check("return", "realized_return_vector_exists", "FAIL",
              "period_returns$ret_net 부재 또는 모두 NA",
              "Sharpe,Sortino,CVaR,WinRate", "critical")
  } else {
    add_check("return", "realized_return_vector_exists", "PASS",
              sprintf("n=%d ret_net obs", nrow(pr)), "", "low")
  }

  # Check 2: nav_path_exists
  nav <- bt_result$nav
  if (is.null(nav) || nrow(nav) == 0 || !"nav_net" %in% names(nav)) {
    add_check("nav", "nav_path_exists", "FAIL",
              "nav$nav_net 부재", "CAGR,MDD,Calmar", "critical")
  } else {
    add_check("nav", "nav_path_exists", "PASS",
              sprintf("n=%d nav obs", nrow(nav)), "", "low")
  }

  # Check 3: rebalance_path_executed
  hd <- bt_result$holdings
  if (is.null(hd) || nrow(hd) == 0) {
    add_check("rebalance", "rebalance_path_executed", "WARN",
              "holdings 부재 — turnover NA", "Turnover", "medium")
  } else {
    n_dates <- uniqueN(hd$date)
    if (n_dates < 2) {
      add_check("rebalance", "rebalance_path_executed", "WARN",
                sprintf("holdings 단일 시점 (n=%d)", n_dates),
                "Turnover", "medium")
    } else {
      add_check("rebalance", "rebalance_path_executed", "PASS",
                sprintf("%d rebalance dates", n_dates), "", "low")
    }
  }

  # Check 4: transaction_cost_param_recorded
  cb <- bt_result$manifest$transaction_cost_bps
  if (is.null(cb) || is.na(cb) || cb == 0) {
    add_check("cost", "transaction_cost_param_recorded", "WARN",
              "manifest$transaction_cost_bps 부재 또는 0 — gross == net 가능",
              "Cost reproducibility", "medium")
  } else {
    add_check("cost", "transaction_cost_param_recorded", "PASS",
              sprintf("commission_bps=%s", cb), "", "low")
  }

  # Check 5: benchmark_aligned
  bm <- bt_result$benchmark_returns
  if (is.null(bm) || nrow(bm) == 0) {
    add_check("benchmark", "benchmark_aligned", "WARN",
              "benchmark_returns 부재", "IR,Beta,Alpha", "medium")
  } else {
    common_dates <- intersect(pr$date, bm$date)
    if (length(common_dates) < min(nrow(pr), nrow(bm)) * 0.9) {
      add_check("benchmark", "benchmark_aligned", "WARN",
                sprintf("date alignment %d / %d (90%% 미달)",
                        length(common_dates), min(nrow(pr), nrow(bm))),
                "IR,Beta,Alpha", "medium")
    } else {
      add_check("benchmark", "benchmark_aligned", "PASS",
                sprintf("alignment %d dates", length(common_dates)), "", "low")
    }
  }

  # Check 6: risk_free_rate_defined
  rf_src <- bt_result$manifest$risk_free_rate_source
  if (is.null(rf_src) || is.na(rf_src) || rf_src == "") {
    add_check("rf", "risk_free_rate_defined", "WARN",
              "manifest$risk_free_rate_source 부재",
              "Sharpe,Sortino,IR", "medium")
  } else {
    add_check("rf", "risk_free_rate_defined", "PASS",
              sprintf("source=%s", rf_src), "", "low")
  }

  # Check 7: point_in_time_checked
  spec <- bt_result$strategy_spec
  lp <- spec$lookahead_prevention
  # 컬럼 부재(NULL)/length-0 시 length-1 NA로 정규화 (downstream grepl이 logical(0) → if(NA) crash 방지)
  if (is.null(lp) || length(lp) == 0) lp <- NA_character_ else lp <- lp[1]
  if (is.null(lp) || is.na(lp) || lp == "") {
    add_check("PIT", "point_in_time_checked", "FAIL",
              "strategy_spec$lookahead_prevention 부재 (PIT 검증 방식 명시 필요)",
              "All metrics", "high")
  } else {
    add_check("PIT", "point_in_time_checked", "PASS",
              sprintf("lookahead_prevention=%s", lp), "", "low")
  }

  # Check 8: lookahead_bias_checked (PIT C1~C15 명시 또는 기본 통과)
  lp_str <- as.character(lp)
  c_ref_pattern <- grepl("C\\d+", lp_str)
  if (isTRUE(c_ref_pattern)) {
    add_check("PIT", "lookahead_bias_checked", "PASS",
              "C1-C15 reference 명시", "", "low")
  } else {
    add_check("PIT", "lookahead_bias_checked", "WARN",
              "C1-C15 명시적 reference 부재", "All metrics", "medium")
  }

  # Check 9: survivorship_bias_checked
  sbc <- spec$survivorship_bias_control
  if (is.null(sbc) || is.na(sbc) || sbc == "") {
    add_check("data", "survivorship_bias_checked", "WARN",
              "strategy_spec$survivorship_bias_control 부재",
              "All metrics", "medium")
  } else {
    add_check("data", "survivorship_bias_checked", "PASS",
              sprintf("control=%s", sbc), "", "low")
  }

  # Check 10: estimated_metrics_separated_from_backtested
  m <- bt_result$metrics
  if (is.null(m) || nrow(m) == 0 || !"metric_type" %in% names(m)) {
    add_check("metric", "estimated_metrics_separated_from_backtested", "FAIL",
              "metrics$metric_type 컬럼 부재",
              "official metrics", "critical")
  } else {
    invalid <- setdiff(unique(m$metric_type),
                       c("backtested", "estimated", "proxy", "unavailable"))
    if (length(invalid) > 0) {
      add_check("metric", "estimated_metrics_separated_from_backtested", "FAIL",
                sprintf("invalid metric_type: %s", paste(invalid, collapse = ",")),
                "official metrics", "critical")
    } else {
      add_check("metric", "estimated_metrics_separated_from_backtested", "PASS",
                sprintf("metric_type 유효: %s",
                        paste(unique(m$metric_type), collapse = ",")), "", "low")
    }
  }

  # Check 11 (L-249 enforcement): frequency-vs-cadence consistency
  # Charter v1.5 §13: declared frequency/annualization_factor must match actual data spacing
  # Mislabel (e.g. bi-monthly inner-join declared as 'daily') inflates Sharpe by sqrt(N_declared/N_actual)
  # Use period_returns$frequency (data-level label) NOT manifest$frequency (strategy signal cadence)
  declared_freq <- tryCatch({
    if (!is.null(pr) && nrow(pr) > 0 && "frequency" %in% names(pr)) {
      # period_returns frequency is most authoritative (set during build_period_returns)
      unique(pr$frequency[!is.na(pr$frequency)])[1]
    } else {
      bt_result$manifest$frequency[1]
    }
  }, error = function(e) NA_character_)
  declared_ann  <- tryCatch({
    # annualization_factor stored in metrics or manifest
    ann_from_metrics <- if (!is.null(bt_result$metrics) && "annualization_factor" %in% names(bt_result$metrics)) {
      unique(bt_result$metrics$annualization_factor[!is.na(bt_result$metrics$annualization_factor)])
    } else numeric(0)
    if (length(ann_from_metrics) > 0) ann_from_metrics[1] else NA_real_
  }, error = function(e) NA_real_)

  pr_for_cadence <- bt_result$period_returns
  freq_mislabel_detected <- FALSE

  if (!is.null(pr_for_cadence) && nrow(pr_for_cadence) >= 3 &&
      "date" %in% names(pr_for_cadence)) {
    date_seq <- sort(as.Date(pr_for_cadence$date))
    date_diffs <- as.numeric(diff(date_seq))
    med_diff <- median(date_diffs, na.rm = TRUE)

    # Tolerance bands per declared frequency
    # daily:     1-5 days (trading days)
    # weekly:    5-10 days
    # monthly:   28-31 days
    # quarterly: 88-95 days
    # bi-monthly/semi-monthly: ~55-65 days (NO valid declared frequency → mislabel if declared daily/monthly)
    declared_band_ok <- if (!is.na(declared_freq)) {
      switch(tolower(declared_freq),
        "daily"     = (med_diff >= 1  && med_diff <= 5),
        "weekly"    = (med_diff >= 5  && med_diff <= 10),
        "monthly"   = (med_diff >= 28 && med_diff <= 31),
        "quarterly" = (med_diff >= 88 && med_diff <= 95),
        TRUE  # unknown frequency label — do not block
      )
    } else {
      TRUE  # no declared frequency — skip this check
    }

    if (!is.na(declared_freq) && !declared_band_ok) {
      freq_mislabel_detected <- TRUE
      # Compute inflation factor vs declared annualization
      actual_ann_implied <- if (med_diff >= 1 && med_diff <= 5) 252 else
                            if (med_diff >= 5 && med_diff <= 10) 52 else
                            if (med_diff >= 28 && med_diff <= 31) 12 else
                            if (med_diff >= 88 && med_diff <= 95) 4 else
                            round(365 / med_diff, 1)
      inflation_sqrt <- if (!is.na(declared_ann) && declared_ann > 0 && actual_ann_implied > 0) {
        round(sqrt(declared_ann / actual_ann_implied), 3)
      } else NA_real_

      add_check("frequency",
                "frequency_cadence_consistency",
                "FAIL",
                sprintf(
                  "L-249 VIOLATION: declared freq='%s' ann=%s but median(diff(date))=%.1f days (implies ~%sx ann). Sharpe inflation ~%.2fx. Charter v1.5 §13 + AX-002.",
                  declared_freq %||% "?",
                  ifelse(is.na(declared_ann), "?", as.character(declared_ann)),
                  med_diff,
                  actual_ann_implied,
                  inflation_sqrt %||% NA_real_
                ),
                "Sharpe,Sortino,Calmar,CAGR",
                "critical")
    } else {
      # (2026-07-04 DEF-08 사각 봉합) 라벨-간격은 정합해도 선언 annualization_factor가
      # 빈도-함의값과 다르면 동일한 부풀림 발생 (monthly 데이터+monthly 라벨+factor 252
      # = 구 Check 11 PASS였던 실오염 케이스). 함의값 대조를 추가.
      freq_implied_ann <- switch(tolower(declared_freq %||% ""),
        "daily" = 252, "weekly" = 52, "monthly" = 12, "quarterly" = 4, NA_real_)
      if (!is.na(freq_implied_ann) && !is.na(declared_ann) &&
          declared_ann != freq_implied_ann) {
        add_check("frequency",
                  "frequency_cadence_consistency",
                  "FAIL",
                  sprintf(
                    "DEF-08 VIOLATION: freq='%s' 함의 factor=%s인데 선언 factor=%s — Sharpe 부풀림 ~%.2fx (CAGR/Calmar는 지수적). AX-002.",
                    declared_freq, freq_implied_ann, declared_ann,
                    sqrt(declared_ann / freq_implied_ann)),
                  "Sharpe,Sortino,Calmar,CAGR,AnnVol,IR",
                  "critical")
        freq_mislabel_detected <- TRUE
      } else {
        add_check("frequency",
                  "frequency_cadence_consistency",
                  "PASS",
                  sprintf("declared freq='%s' consistent with median date_diff=%.1f days (ann=%s)",
                          declared_freq %||% "?", med_diff,
                          ifelse(is.na(declared_ann), "?", as.character(declared_ann))),
                  "", "low")
      }
    }
  } else {
    add_check("frequency",
              "frequency_cadence_consistency",
              "WARN",
              "period_returns < 3 obs or missing date column — cadence check skipped",
              "", "medium")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 12 (L-258 enforcement): gross_ret - cost == net_ret 실 검증
  # ────────────────────────────────────────────────────────────────────────────
  pr_full <- bt_result$period_returns
  if (!is.null(pr_full) && nrow(pr_full) > 0L &&
      all(c("ret_gross", "ret_net", "cost_ret") %in% names(pr_full))) {
    diff_check <- pr_full$ret_gross - pr_full$cost_ret - pr_full$ret_net
    max_abs_diff <- max(abs(diff_check), na.rm = TRUE)
    if (is.finite(max_abs_diff) && max_abs_diff > 1e-6) {
      add_check("cost", "cost_decomposition_consistency", "FAIL",
                sprintf("ret_gross - cost_ret != ret_net (max |diff|=%.2e > 1e-6). Cost 차감 audit 실패.",
                        max_abs_diff),
                "All cost-adjusted metrics", "critical")
    } else {
      add_check("cost", "cost_decomposition_consistency", "PASS",
                sprintf("ret_gross - cost_ret == ret_net (max |diff|=%.2e ≤ 1e-6, %d obs)",
                        max_abs_diff %||% 0, nrow(pr_full)), "", "low")
    }
  } else {
    add_check("cost", "cost_decomposition_consistency", "WARN",
              "period_returns ret_gross/cost_ret/ret_net 컬럼 부재 — cost decomposition 검증 skip",
              "Cost reproducibility", "medium")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 13 (L-258): T+1 cadence 검사 (rebalance_rule + holdings buy_close_date)
  # ────────────────────────────────────────────────────────────────────────────
  reb_rule <- bt_result$manifest$rebalance_rule[1] %||% ""
  is_t1_declared <- grepl("t\\+?1|T\\+?1|first[_ ]?biz|first[_ ]?trad", reb_rule, ignore.case = TRUE)
  hd <- bt_result$holdings
  if (is_t1_declared) {
    if (!is.null(hd) && nrow(hd) > 0L &&
        all(c("date", "entry_date") %in% names(hd))) {
      sample_dates <- unique(hd[!is.na(entry_date), .(date, entry_date)])[1:min(20L, .N)]
      if (nrow(sample_dates) > 0L) {
        # entry_date should be ≥ date (sig_label) — first business day after sig_label
        violations <- sample_dates[as.Date(entry_date) < as.Date(date)]
        if (nrow(violations) > 0L) {
          add_check("schedule", "t_plus_1_cadence_consistency", "FAIL",
                    sprintf("declared rebalance_rule='%s' but %d/%d sample holdings have entry_date < date (sig_label) — T+0 동작 의심",
                            reb_rule, nrow(violations), nrow(sample_dates)),
                    "All metrics", "high")
        } else {
          add_check("schedule", "t_plus_1_cadence_consistency", "PASS",
                    sprintf("declared T+1 + entry_date ≥ date in %d sample holdings", nrow(sample_dates)),
                    "", "low")
        }
      } else {
        add_check("schedule", "t_plus_1_cadence_consistency", "WARN",
                  "holdings entry_date 컬럼 NA — T+1 cadence 검증 skip",
                  "schedule_fidelity", "medium")
      }
    } else {
      add_check("schedule", "t_plus_1_cadence_consistency", "WARN",
                "holdings 또는 entry_date 컬럼 부재 — T+1 cadence 검증 skip",
                "schedule_fidelity", "medium")
    }
  } else {
    add_check("schedule", "t_plus_1_cadence_consistency", "PASS",
              sprintf("rebalance_rule='%s' (T+1 미선언, skip)", reb_rule), "", "low")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 14 (L-258): C15 path — Factor DB load 경로 검증 (factor_engine R 파일 grep)
  # 직접 read_parquet on factor_db/* 위반 검출. PIT equivalence proof 흔적 보너스 점검.
  # ────────────────────────────────────────────────────────────────────────────
  factor_engine_path <- bt_result$strategy_spec$factor_engine_path[1] %||%
                         bt_result$manifest$factor_engine_path[1] %||% ""
  if (nzchar(factor_engine_path) && file.exists(factor_engine_path)) {
    src_lines <- tryCatch(readLines(factor_engine_path, warn = FALSE),
                           error = function(e) character(0))
    direct_parquet <- grep("read_parquet\\s*\\(.*factor_db", src_lines, value = TRUE)
    lmf_calls <- grep("load_month_factors\\s*\\(", src_lines, value = TRUE)
    align_calls <- grep("align_factor_direction\\s*\\(", src_lines, value = TRUE)
    pit_proof <- grep("Usable_Date|cor.*0\\.999|equiv_proof", src_lines, value = TRUE)

    if (length(direct_parquet) > 0L &&
        length(lmf_calls) == 0L && length(align_calls) == 0L) {
      add_check("PIT", "c15_factor_db_load_path", "FAIL",
                sprintf("factor_engine 직접 read_parquet(factor_db) 사용 (%d hits) + load_month_factors/align_factor_direction 호출 부재. C15 위반.",
                        length(direct_parquet)),
                "All factor-derived metrics", "high")
    } else if (length(direct_parquet) > 0L) {
      add_check("PIT", "c15_factor_db_load_path", "PASS_WITH_NOTES",
                sprintf("bulk read_parquet %d hits + (lmf=%d / align=%d / pit_proof=%d) — letter 위반, spirit 정합 (PIT equivalence proof 필요)",
                        length(direct_parquet), length(lmf_calls), length(align_calls), length(pit_proof)),
                "", "low")
    } else {
      add_check("PIT", "c15_factor_db_load_path", "PASS",
                sprintf("factor_engine 직접 read_parquet(factor_db) 부재 + lmf=%d / align=%d hits",
                        length(lmf_calls), length(align_calls)), "", "low")
    }
  } else {
    add_check("PIT", "c15_factor_db_load_path", "WARN",
              "manifest$factor_engine_path 부재 또는 file 부재 — C15 path 검증 skip",
              "PIT integrity", "medium")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 15 (L-258): lookahead_detector self-call (자체 PIT scan)
  # ────────────────────────────────────────────────────────────────────────────
  ld_path <- "02_Infrastructure/validation/lookahead_detector.R"
  if (file.exists(ld_path) && nzchar(factor_engine_path) && file.exists(factor_engine_path)) {
    tryCatch({
      source(ld_path, local = TRUE)
      if (exists("scan_lookahead", inherits = FALSE)) {
        scan_result <- scan_lookahead(factor_engine_path)
        prod_violations <- if (is.list(scan_result)) {
          # 일반 lookahead_detector 결과: list(C1=integer, C2=integer, ...)
          sum(sapply(scan_result, function(x) if (is.numeric(x)) length(x) else 0L))
        } else 0L
        if (prod_violations > 0L) {
          add_check("PIT", "lookahead_detector_self_scan", "FAIL",
                    sprintf("scan_lookahead %s production violations (factor_engine_path)",
                            prod_violations),
                    "All metrics", "high")
        } else {
          add_check("PIT", "lookahead_detector_self_scan", "PASS",
                    "scan_lookahead 0 production violations", "", "low")
        }
      } else {
        add_check("PIT", "lookahead_detector_self_scan", "WARN",
                  "scan_lookahead 함수 부재 — lookahead self-call skip",
                  "PIT integrity", "medium")
      }
    }, error = function(e) {
      add_check("PIT", "lookahead_detector_self_scan", "WARN",
                sprintf("lookahead_detector 호출 실패: %s", conditionMessage(e)),
                "PIT integrity", "medium")
    })
  } else {
    add_check("PIT", "lookahead_detector_self_scan", "WARN",
              "lookahead_detector.R 또는 factor_engine_path 부재 — self-call skip",
              "PIT integrity", "medium")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 16 (L-258, F-04): nav frequency vs declared frequency 정합 검증
  # Backtest Contract v1.0 §6 schema는 nav를 daily로 의도.
  # nav가 monthly이면서 manifest$frequency="daily"이면 fabrication risk.
  # ────────────────────────────────────────────────────────────────────────────
  nav_dt <- bt_result$nav
  if (!is.null(nav_dt) && nrow(nav_dt) >= 3L && "date" %in% names(nav_dt)) {
    nav_dates <- sort(as.Date(nav_dt$date))
    nav_med_diff <- as.numeric(median(diff(nav_dates), na.rm = TRUE))
    nav_implied_freq <- if (nav_med_diff <= 5)        "daily"
                       else if (nav_med_diff <= 10)    "weekly"
                       else if (nav_med_diff <= 31)    "monthly"
                       else if (nav_med_diff <= 95)    "quarterly"
                       else                             "irregular"
    declared_strat_freq <- bt_result$manifest$frequency[1] %||% NA
    if (!is.na(declared_strat_freq) &&
        tolower(declared_strat_freq) == "daily" &&
        nav_implied_freq != "daily") {
      add_check("frequency", "nav_cadence_label_consistency", "FAIL",
                sprintf("nav cadence %.1f days (~%s) but manifest$frequency='daily' — Contract §6 nav daily 의도 위반 + L-249 fabrication 패턴",
                        nav_med_diff, nav_implied_freq),
                "Daily-derived metrics (drawdown_net, daily SR)", "high")
    } else {
      add_check("frequency", "nav_cadence_label_consistency", "PASS",
                sprintf("nav median diff %.1f days (~%s), manifest$frequency='%s'",
                        nav_med_diff, nav_implied_freq, declared_strat_freq %||% "?"),
                "", "low")
    }
  } else {
    add_check("frequency", "nav_cadence_label_consistency", "WARN",
              "nav < 3 obs or missing date column — nav cadence check skipped",
              "Daily-derived metrics", "medium")
  }

  # ────────────────────────────────────────────────────────────────────────────
  # Check 17 (2026-08-09 도훈 적발 "26년 수익률 이상"): 벤치 **값** 타당성
  #   사건: benchmark.parquet 에 스케일 이음매가 생겨 2026-07-29 이 -89.38%(참값 -6.185%)로
  #   기록됐고, alpha_search **16 run**이 그 벤치로 채점돼 Grade B 까지 받았다. 21.5년 벤치
  #   총수익이 +717% → -7.5% 로 뒤집혀 전략이 시장을 이긴 것처럼 보였다(연 초과 15/16 부호 반전).
  #   ★Check 5(benchmark_aligned)는 **날짜 겹침만** 세므로 전 건 "alignment 5305 dates" PASS —
  #   존재 검사가 정체 검사를 대체한 전형. 값 축을 여기서 닫는다.
  #
  #   문턱 = 수리된 KOSPI200 1990~2026(9,003일) 실측 캘리브레이션:
  #     일간 실제 최대 |ret| 0.1998(2026-07-31) · 주간 0.1966 · 월간 0.3534(2026-05)
  #     반면 스케일 이음매는 1.5×만 돼도 -0.333/+0.500, 실제 사고(8.834×)는 -0.887/+7.834.
  #     두 분포가 겹치지 않는다. th 에서 실측 오탐 0건(일간 th=0.30 / 월간 th=0.45).
  #   ⚠벤치를 KOSPI200 이외로 바꾸면 이 문턱을 재캘리브레이션할 것.
  # ────────────────────────────────────────────────────────────────────────────
  bmv <- bt_result$benchmark_returns
  if (!is.null(bmv) && nrow(bmv) > 0L && "benchmark_ret" %in% names(bmv)) {
    br <- bmv$benchmark_ret
    br_ok <- br[is.finite(br)]

    # 17a: 퇴화 계열 (전부 NA / 무변동 / 전부 0) — "빈 결과 = 합격" 계통 차단
    if (length(br_ok) < max(3L, 0.5 * nrow(bmv))) {
      add_check("benchmark", "benchmark_series_non_degenerate", "FAIL",
                sprintf("benchmark_ret 유효값 %d/%d — 벤치 계열 결손(조인 실패/all-NA 의심)",
                        length(br_ok), nrow(bmv)),
                "IR,Beta,Alpha,ActiveReturn", "critical")
    } else if (sd(br_ok) < 1e-12) {
      add_check("benchmark", "benchmark_series_non_degenerate", "FAIL",
                sprintf("benchmark_ret 무변동 (sd=%.2e, %d obs) — beta 정의 불가, active=전략수익으로 위장",
                        sd(br_ok), length(br_ok)),
                "IR,Beta,Alpha,ActiveReturn", "critical")
    } else {
      add_check("benchmark", "benchmark_series_non_degenerate", "PASS",
                sprintf("유효 %d/%d obs, sd=%.4f", length(br_ok), nrow(bmv), sd(br_ok)),
                "", "low")
    }

    # 17b: 물리적으로 불가능한 단일 이동 = 스케일 이음매/단위 오류
    if (length(br_ok) >= 3L && "date" %in% names(bmv)) {
      bm_dates <- sort(as.Date(bmv$date))
      bm_med   <- as.numeric(median(diff(bm_dates), na.rm = TRUE))
      th <- if (bm_med <= 5) 0.30 else if (bm_med <= 10) 0.35 else
            if (bm_med <= 31) 0.45 else 0.60
      cad <- if (bm_med <= 5) "daily" else if (bm_med <= 10) "weekly" else
             if (bm_med <= 31) "monthly" else "quarterly+"
      bad_i <- which(abs(bmv$benchmark_ret) > th & is.finite(bmv$benchmark_ret))
      if (length(bad_i) > 0L) {
        wi <- bad_i[which.max(abs(bmv$benchmark_ret[bad_i]))]
        worst <- bmv$benchmark_ret[wi]
        implied_scale <- if (worst < 0) 1 / (1 + worst) else 1 + worst
        add_check("benchmark", "benchmark_values_plausible", "FAIL",
                  sprintf(paste0("벤치 %s 수익률 %d건이 |%.2f| 초과 — 최악 %s %+.4f ",
                                 "(함의 스케일 오류 %.2f×). 지수에서 물리적으로 불가 = ",
                                 "스케일 이음매/단위 오류 의심. 벤치-상대 지표 전부 무효. ",
                                 "실측 상한: 일간 0.1998·월간 0.3534 (KOSPI200 1990-2026)."),
                          cad, length(bad_i), th, format(bm_dates[wi]), worst, implied_scale),
                  "IR,Beta,Alpha,ActiveReturn,PORT_t", "critical")
      } else {
        add_check("benchmark", "benchmark_values_plausible", "PASS",
                  sprintf("%s 벤치 max|ret|=%.4f ≤ %.2f (%d obs)",
                          cad, max(abs(br_ok)), th, length(br_ok)),
                  "", "low")
      }
    } else {
      add_check("benchmark", "benchmark_values_plausible", "WARN",
                "benchmark_returns < 3 유효 obs 또는 date 컬럼 부재 — 값 타당성 검사 skip",
                "IR,Beta,Alpha", "medium")
    }
  } else {
    add_check("benchmark", "benchmark_values_plausible", "WARN",
              "benchmark_returns 부재 또는 benchmark_ret 컬럼 없음 — 값 타당성 검사 skip",
              "IR,Beta,Alpha", "medium")
  }

  audit_tbl <- rbindlist(audit_rows, use.names = TRUE, fill = TRUE)
  bt_result$audit <- audit_tbl

  # Critical FAIL 시 official metrics 차단
  critical_fails <- audit_tbl[severity == "critical" & status == "FAIL"]
  if (nrow(critical_fails) > 0) {
    cat(sprintf("[audit_bt_result] %d critical FAILs — disabling official metrics\n",
                nrow(critical_fails)))
    if (!is.null(bt_result$metrics) && nrow(bt_result$metrics) > 0) {
      affected_metrics_str <- paste(critical_fails$affected_metrics, collapse = ",")
      affected_list <- unlist(strsplit(affected_metrics_str, "[,\\s]+"))
      affected_list <- affected_list[nchar(affected_list) > 0]
      bt_result$metrics[metric_name %in% affected_list, `:=`(
        is_official = FALSE,
        metric_type = "unavailable"
      )]
    }
    bt_result$manifest[, integrity_status := "FAIL"]
  } else if (nrow(audit_tbl[status == "FAIL"]) > 0) {
    bt_result$manifest[, integrity_status := "WARNING"]
  } else if (nrow(audit_tbl[status == "WARN"]) > 0) {
    bt_result$manifest[, integrity_status := "WARNING"]
  } else {
    bt_result$manifest[, integrity_status := "PASS"]
  }

  # Attach L-249 flag to manifest for downstream consumption
  bt_result$manifest[, frequency_mislabel_detected := freq_mislabel_detected]

  cat(sprintf("[audit_bt_result] Audit complete — %d checks | PASS=%d FAIL=%d WARN=%d | integrity=%s | L249_freq_mislabel=%s\n",
              nrow(audit_tbl),
              nrow(audit_tbl[status == "PASS"]),
              nrow(audit_tbl[status == "FAIL"]),
              nrow(audit_tbl[status == "WARN"]),
              bt_result$manifest$integrity_status[1],
              freq_mislabel_detected))

  bt_result
}

cat("[audit_bt_result.R] Loaded — audit_bt_result() (11 checks, L3 trigger, L-249 frequency_cadence_consistency)\n")
