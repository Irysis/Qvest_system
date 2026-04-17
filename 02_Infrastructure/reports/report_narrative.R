#==============================================================================
# Quant Module — Report Narrative Generator
# report_narrative.R
#
# Strategy classification + dynamic narrative generation.
# No hardcoded text — all content is derived from strategy code + metrics.
#
# Usage: source("02_Infrastructure/report_narrative.R")
#==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0) return(b)
  if (length(a) == 1 && is.na(a)) return(b)
  a
}

cat("[report_narrative] Loading...\n")

#==============================================================================
# classify_strategy() — Parse run_all.R to determine strategy type
#==============================================================================
classify_strategy <- function(run_all_path) {

  if (!file.exists(run_all_path)) {
    warning("[classify_strategy] run_all.R not found: ", run_all_path)
    return(list(type = "single_factor", n_sleeves = 1, overlays = character(0),
                has_fm = FALSE, has_sector_neutral = FALSE,
                sleeve_names = character(0), description = "Unknown strategy"))
  }

  code <- paste(readLines(run_all_path, warn = FALSE), collapse = "\n")
  code_lower <- tolower(code)

  # Count sleeves
  sleeve_pattern <- "sim_sleeve_|sim_def|sim_ind|sim_cons|sim_gate|sim_val|sim_mom|sim_qual|phase 1[a-z]\\]|sleeve.*\\(n="
  sleeve_matches <- gregexpr(sleeve_pattern, code_lower)[[1]]
  n_sleeves_raw <- if (sleeve_matches[1] > 0) length(sleeve_matches) else 0

  # More precise counting: look for Phase 1a, 1b, 1c, 1d patterns
  phase_matches <- regmatches(code, gregexpr("Phase 1[a-h]\\]|\\[Phase 1[a-h]\\]", code, ignore.case = TRUE))[[1]]
  n_phases <- length(unique(phase_matches))

  # Also count sim_XXX assignments as sleeve indicator
  sim_assigns <- regmatches(code, gregexpr("sim_(def|ind|cons|gate|val|mom|qual|rev)\\s*<-", code))[[1]]
  n_sim_assigns <- length(unique(sim_assigns))

  # Prefer precise counts (phases, sim assignments) over raw pattern matching
  n_sleeves <- if (n_phases >= 2 || n_sim_assigns >= 2) {
    max(n_phases, n_sim_assigns)
  } else if (n_sleeves_raw >= 2) {
    min(n_sleeves_raw, 6L)
  } else {
    1L
  }

  # Extract sleeve names from comments or code
  sleeve_names <- character(0)
  sleeve_label_matches <- regmatches(code,
    gregexpr("Phase 1[a-h]\\]\\s*([A-Za-z_]+)\\s+sleeve|sim_(def|ind|cons|gate|val|mom|qual|rev)", code, ignore.case = TRUE))[[1]]
  if (length(sleeve_label_matches) > 0) {
    sleeve_names <- unique(gsub(".*sim_(\\w+).*|.*\\]\\s*(\\w+)\\s+sleeve.*", "\\1\\2",
                                sleeve_label_matches, ignore.case = TRUE))
    sleeve_names <- sleeve_names[nchar(sleeve_names) > 0]
  }

  # Detect overlays
  has_vt <- grepl("vol_target|vt_target|vt_scale|vol_lookback|exposure.*vol", code_lower)
  has_dd_brake <- grepl("dd_brake|drawdown.*brake|dd_exp|dd_start|short_dd_start|multi.*timeframe.*dd",
                        code_lower)
  has_soft_mrs <- grepl("soft.*mrs|mrs_score|mrs_low|mrs_high|mrs_min_exp|macro_risk_score",
                        code_lower)
  has_hard_mrs <- grepl("macro_hard_thresh|hard.*mrs|cashout", code_lower) && !has_soft_mrs
  has_fm <- grepl("factor.*momentum|fm_weight|trailing.*return.*sleeve|fm_window|cum_def.*cum_ind",
                  code_lower)
  has_sector_neutral <- grepl("sector.*neutral|sector_z|sector.*dispersion|z_disp",
                              code_lower)
  has_dispersion_tilt <- grepl("disp_tilt|dispersion.*tilt|sector.*dispersion.*z", code_lower)
  has_vol_eq <- grepl("vol.*equali|scale_ind|expanding.*window.*vol", code_lower)
  has_buffer <- grepl("buffer_zone|keep_n|entry_n", code_lower)

  # Build overlay list
  overlays <- character(0)
  if (has_vt) overlays <- c(overlays, "vol_target")
  if (has_dd_brake) overlays <- c(overlays, "dd_brake")
  if (has_soft_mrs) overlays <- c(overlays, "soft_mrs")
  if (has_hard_mrs) overlays <- c(overlays, "hard_mrs")

  # Extract VT target value
  vt_val <- NA_real_
  vt_match <- regmatches(code, regexpr("VT_TARGET\\s*<-\\s*([0-9.]+)", code))
  if (length(vt_match) > 0) vt_val <- as.numeric(sub(".*<-\\s*", "", vt_match))

  # Extract DD brake params
  dd_start <- NA_real_; dd_full <- NA_real_
 dd_match_start <- regmatches(code, regexpr("(SHORT_DD_START|dd_start)\\s*<-\\s*([0-9.]+)", code, ignore.case = TRUE))
  if (length(dd_match_start) > 0) dd_start <- as.numeric(sub(".*<-\\s*", "", dd_match_start))

  # Extract N holdings
  n_holdings <- NA_integer_
  n_match <- regmatches(code, regexpr("n_holdings\\s*=\\s*(\\d+)", code))
  if (length(n_match) > 0) n_holdings <- as.integer(sub(".*=\\s*", "", n_match))

  # Determine type
  type <- if (n_sleeves >= 3) {
    "multi_sleeve_ensemble"
  } else if (n_sleeves == 2) {
    "dual_sleeve"
  } else {
    "single_factor"
  }

  # Extract description from comments at top of file
  first_lines <- readLines(run_all_path, n = 5, warn = FALSE)
  description <- paste(grep("^##", first_lines, value = TRUE), collapse = " | ")
  description <- gsub("^##\\s*", "", description)

  list(
    type = type,
    n_sleeves = n_sleeves,
    overlays = overlays,
    has_fm = has_fm,
    has_sector_neutral = has_sector_neutral,
    has_dispersion_tilt = has_dispersion_tilt,
    has_vol_eq = has_vol_eq,
    has_buffer = has_buffer,
    has_dd_brake = has_dd_brake,
    sleeve_names = sleeve_names,
    vt_target = vt_val,
    dd_start = dd_start,
    n_holdings = n_holdings,
    description = description
  )
}

#==============================================================================
# select_visualizations() — Choose chart combination based on classification
#==============================================================================
select_visualizations <- function(classification) {

  # Common charts for all strategies
  viz <- c("equity_curve", "drawdown_chart", "annual_returns", "rolling_sharpe",
           "ff_alpha_table", "stress_test_table", "tail_risk_metrics", "holdings_table")

  cls <- classification

  # Type-specific additions
  if (cls$type == "multi_sleeve_ensemble") {
    viz <- c(viz, "sleeve_contribution", "sleeve_correlation",
             "sleeve_weights_timeline", "sleeve_individual_perf")
  } else if (cls$type == "dual_sleeve") {
    viz <- c(viz, "sleeve_contribution", "sleeve_correlation")
  } else {
    # single_factor
    viz <- c(viz, "ic_timeseries", "sector_exposure")
  }

  # Overlay-specific additions
  if (length(cls$overlays) >= 2) {
    viz <- c(viz, "overlay_attribution", "exposure_timeline")
  }

  if (cls$has_dd_brake) {
    viz <- c(viz, "dd_brake_activation")
  }

  unique(viz)
}

#==============================================================================
# Narrative helper functions
#==============================================================================

describe_type <- function(cls, lang = "en") {
  if (lang == "kr") return(describe_type_kr(cls))

  base <- switch(cls$type,
    "multi_sleeve_ensemble" = sprintf("%d-sleeve all-weather factor portfolio", cls$n_sleeves),
    "dual_sleeve" = "dual-sleeve factor portfolio",
    "single_factor" = "single-factor strategy"
  )
  if (length(cls$overlays) > 0) {
    base <- paste(base, "with", describe_overlays(cls$overlays, lang))
  }
  base
}

describe_type_kr <- function(cls) {
  base <- switch(cls$type,
    "multi_sleeve_ensemble" = sprintf("%d-슬리브 전천후 팩터 포트폴리오", cls$n_sleeves),
    "dual_sleeve" = "2-슬리브 팩터 포트폴리오",
    "single_factor" = "단일 팩터 전략"
  )
  if (length(cls$overlays) > 0) {
    base <- paste0(base, " (", describe_overlays(cls$overlays, "kr"), ")")
  }
  base
}

describe_overlays <- function(overlays, lang = "en") {
  overlays <- as.character(unlist(overlays))
  if (lang == "kr") {
    names_kr <- c(vol_target = "변동성 타겟팅",
                  dd_brake = "드로다운 브레이크",
                  soft_mrs = "국면 인식 노출 조절",
                  hard_mrs = "마르코프 국면 전환")
    return(paste(names_kr[overlays], collapse = ", "))
  }
  names_en <- c(vol_target = "volatility targeting",
                dd_brake = "drawdown brake",
                soft_mrs = "regime-aware exposure control (Soft MRS)",
                hard_mrs = "Markov regime switching (Hard MRS)")
  paste(names_en[overlays], collapse = ", ")
}

describe_performance <- function(m, lang = "en") {
  cagr <- as.numeric(m$CAGR %||% m$cagr %||% NA)
  sharpe <- as.numeric(m$Sharpe %||% m$sharpe %||% NA)
  mdd <- as.numeric(m$MDD %||% m$mdd %||% NA)

  targets <- c()
  if (!is.na(cagr) && cagr >= 16) {
    targets <- c(targets, sprintf("CAGR %.1f%% (target: 16%%+)", cagr))
  }
  if (!is.na(sharpe) && sharpe >= 2.0) {
    targets <- c(targets, sprintf("Sharpe %.3f (target: 2.0+)", sharpe))
  }
  if (!is.na(mdd) && mdd <= 25) {
    targets <- c(targets, sprintf("MDD -%.1f%% (target: <25%%)", mdd))
  }

  if (length(targets) == 3) {
    if (lang == "kr") {
      sprintf("3개 목표 모두 달성: %s.", paste(targets, collapse = ", "))
    } else {
      sprintf("It achieved all three target thresholds: %s.", paste(targets, collapse = ", "))
    }
  } else {
    if (lang == "kr") {
      sprintf("주요 지표: CAGR %.1f%%, Sharpe %.3f, MDD -%.1f%%.", cagr, sharpe, mdd)
    } else {
      sprintf("Key metrics: CAGR %.1f%%, Sharpe %.3f, MDD -%.1f%%.", cagr, sharpe, mdd)
    }
  }
}

#==============================================================================
# generate_narrative() — Build narrative JSON from classification + metrics
#==============================================================================
generate_narrative <- function(strategy_id, classification, hurdle, metrics, lang = "en") {

  cls <- classification
  narrative <- list()

  # 1. Executive Summary
  type_desc <- describe_type(cls, lang)
  perf_desc <- describe_performance(metrics, lang)

  if (lang == "kr") {
    narrative$exec_summary <- sprintf(
      "%s: Korean equity (KOSPI/KOSDAQ) %s. %s",
      strategy_id, type_desc, perf_desc
    )
  } else {
    narrative$exec_summary <- sprintf(
      "%s is a %s designed for the Korean equity market (KOSPI/KOSDAQ universe). %s",
      strategy_id, type_desc, perf_desc
    )
  }

  # 2. Investment Thesis
  if (cls$type == "multi_sleeve_ensemble") {
    sleeve_desc <- if (length(cls$sleeve_names) > 0) {
      paste(cls$sleeve_names, collapse = ", ")
    } else {
      sprintf("%d independent alpha sources", cls$n_sleeves)
    }

    if (lang == "kr") {
      narrative$thesis <- sprintf(
        "전략은 %s 등 %d개의 독립적인 alpha source를 조합하여 구성됩니다. %s%s",
        sleeve_desc, cls$n_sleeves,
        if (cls$has_fm) "Factor Momentum을 통해 최근 성과가 좋은 슬리브에 동적으로 비중을 배분합니다. " else "",
        if (cls$has_vol_eq) "슬리브 간 expanding window 변동성 균등화를 적용합니다." else ""
      )
    } else {
      narrative$thesis <- sprintf(
        "The strategy combines %d orthogonal alpha sources (%s) to construct a diversified portfolio. %s%s",
        cls$n_sleeves, sleeve_desc,
        if (cls$has_fm) "Factor Momentum dynamically allocates to recently outperforming sleeves based on 63-day trailing returns. " else "",
        if (cls$has_vol_eq) "Expanding-window volatility equalization ensures fair comparison across sleeves." else ""
      )
    }
  } else if (cls$type == "dual_sleeve") {
    if (lang == "kr") {
      narrative$thesis <- sprintf(
        "2개의 슬리브를 조합하며, %s 방식으로 배분합니다.",
        if (cls$has_fm) "Factor Momentum 동적 배분" else "시장 국면 기반 배분"
      )
    } else {
      narrative$thesis <- sprintf(
        "The strategy blends two factor sleeves using %s allocation.",
        if (cls$has_fm) "Factor Momentum-based dynamic" else "regime-conditional"
      )
    }
  } else {
    if (lang == "kr") {
      narrative$thesis <- sprintf(
        "단일 팩터 전략으로, %s",
        if (nchar(cls$description) > 0) cls$description else "Korean equity market에서 alpha를 추출합니다."
      )
    } else {
      narrative$thesis <- sprintf(
        "This is a single-factor strategy. %s",
        if (nchar(cls$description) > 0) cls$description else "It exploits a documented anomaly in the Korean equity market."
      )
    }
  }

  # 3. Risk Overlay Section
  if (length(cls$overlays) > 0) {
    overlay_details <- list()

    if ("vol_target" %in% cls$overlays) {
      vt_pct <- if (!is.na(cls$vt_target)) sprintf("%.0f%%", cls$vt_target * 100) else "target level"
      if (lang == "kr") {
        overlay_details <- c(overlay_details, sprintf("Volatility Targeting (%s): 포트폴리오 변동성을 일정 수준으로 유지하여 Sharpe를 최적화합니다.", vt_pct))
      } else {
        overlay_details <- c(overlay_details, sprintf("Volatility Targeting (%s): Scales exposure to maintain constant portfolio volatility, optimizing Sharpe ratio.", vt_pct))
      }
    }

    if ("dd_brake" %in% cls$overlays) {
      if (lang == "kr") {
        overlay_details <- c(overlay_details, "Multi-Timeframe Drawdown Brake: 중기(4-35%) + 단기(20일 롤링) 이중 브레이크로 MDD를 독립적으로 제어합니다.")
      } else {
        overlay_details <- c(overlay_details, "Multi-Timeframe Drawdown Brake: Combines medium-term (4%-35% linear ramp) and short-term (20-day rolling) brakes for independent MDD control.")
      }
    }

    if ("soft_mrs" %in% cls$overlays) {
      if (lang == "kr") {
        overlay_details <- c(overlay_details, "Soft MRS (15->30): Macro Risk Score에 따라 선형적으로 노출도를 조절하며, binary on/off 대비 우수합니다.")
      } else {
        overlay_details <- c(overlay_details, "Soft MRS (15->30 linear ramp): Proportionally reduces exposure based on Macro Risk Score, superior to binary regime switching.")
      }
    }

    if ("hard_mrs" %in% cls$overlays) {
      if (lang == "kr") {
        overlay_details <- c(overlay_details, "Hard MRS: Macro Risk Score >= 30 시 현금 전환합니다.")
      } else {
        overlay_details <- c(overlay_details, "Hard MRS: Full cash-out when Macro Risk Score >= 30.")
      }
    }

    narrative$risk_overlay <- paste(overlay_details, collapse = " ")
    narrative$overlay_list <- overlay_details
  }

  # 4. Score Summary
  if (!is.null(hurdle)) {
    grade <- hurdle$grade %||% "?"
    score <- hurdle$total_score %||% NA
    axes <- hurdle$axes %||% list()

    if (lang == "kr") {
      narrative$score_summary <- sprintf(
        "Hurdle Gate Score: %.1f (Grade %s). Return %s / Risk %s / Robustness %s / Implementability %s / Diversification %s.",
        score, grade,
        axes$Return %||% "?", axes$Risk %||% "?",
        axes$Robustness %||% "?", axes$Implementability %||% "?",
        axes$Diversification %||% "?"
      )
    } else {
      narrative$score_summary <- sprintf(
        "Hurdle Gate Score: %.1f (Grade %s). Axis scores: Return %s / Risk %s / Robustness %s / Implementability %s / Diversification %s.",
        score, grade,
        axes$Return %||% "?", axes$Risk %||% "?",
        axes$Robustness %||% "?", axes$Implementability %||% "?",
        axes$Diversification %||% "?"
      )
    }
  }

  # 5. Key Insight (derived from hurdle diagnostics)
  if (!is.null(hurdle$diagnostics)) {
    diag_msgs <- sapply(hurdle$diagnostics, function(d) d$msg %||% "")

    # Extract OOS info
    oos_msg <- diag_msgs[grepl("OOS Validation", diag_msgs)]
    alpha_msg <- diag_msgs[grepl("Alpha Trend", diag_msgs)]

    insights <- c()
    if (length(oos_msg) > 0) insights <- c(insights, oos_msg[1])
    if (length(alpha_msg) > 0) insights <- c(insights, alpha_msg[1])

    if (length(insights) > 0) {
      narrative$key_insights <- insights
    }
  }

  narrative$lang <- lang
  narrative$strategy_id <- strategy_id
  narrative$classification <- cls

  narrative
}

cat("[report_narrative] Loaded: classify_strategy(), select_visualizations(), generate_narrative()\n")
