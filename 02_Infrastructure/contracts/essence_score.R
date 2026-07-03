#!/usr/bin/env Rscript
#==============================================================================
# essence_score.R — Qvest 본질 스코어 + 등급 (Dual-Mode SOT §3.5)
#
# 본질 = 리스크 대비 수익률. 계약 bt_result에서 5 본질지표를 *읽기만* 하고
# A/B/C/F 등급을 산정한다. 자체합성(prod(1+r)/수동 Sharpe) 금지 — 계약값만 사용.
# DSR만 계약 미산출 → net active 시계열에서 BLdP(2014) 공식으로 보강 산출.
#
# Grade A 임계 (전부 문서값/도출값 — 지어낸 것 없음):
#   PORT_t ≥ 2.95   (Harvey-Liu-Zhu 2016 — 문헌-레벨 다중검정 이미 반영)
#   OOS retention ≥ 0.7  (활성 Sharpe OOS/IS, 65/35; 과적합 게이트 — DSR 대체)
#   Sharpe ≥ 0.8, CAGR ≥ 16%  (legacy hurdle_gate Grade A 유지 / CLAUDE.md 제2목표)
#   Calmar ≥ 0.64   (= 16%/25%, CAGR16·MDD25 제2목표서 도출 — "리스크 대비 수익" 위험조정 게이트)
#   DSR ≥ 0.5 (BLdP 2014)  ← **sweep형 selection(열거집합 argmax/threshold-pick: ML스윕/optimizer서치/앙상블/사전등록 grid)에서만 게이트.**
#                            1논문/1알파 + 가설주도 순차개선 chain(selection_type="chain")엔 부적용
#                            (도훈 mandate 2026-05-31/2026-06-10; chain 자격 = IS-only 변형선택 + holdout 1회 — measurement-graduation §3).
#                            DSR 수치는 n_trials>1이면 진단용으로 항상 산출(게이트와 무관).
#
# 18-component proxy 합산(hurdle_gate.R)은 폐기 — 진단용으로만 retain.
#
# essence_score(bt_result, n_trials_cumulative = NULL, hard_fail = NULL, ..., selection_type = NULL)
#   bt_result : build_bt_result() 10-component (계약). 필수: metrics, benchmark_compare.
#   n_trials_cumulative : DSR 산출용 누적 시행수 (기록 의무 유지 — 게이트 적용 여부와 별개).
#   hard_fail : 외부 주입(judge). NULL이면 MDD 깊이 단독이 아니라
#               drawdown episode 빈도/지속성으로 구조적 hard fail 추론.
#   selection_type : "sweep"(게이트 강제) / "chain"(가설주도 순차개선 — 게이트 면제) /
#                    NULL(legacy: n_trials>1 휴리스틱 유지, 기존 sweep caller 호환).
#   oos_stat_version : "v2"(기본, 2026-06-10 도훈 mandate C1) = anchored 3분할{55/65/75} retention 중앙값
#                      / "v1" = 단일 65/35 (legacy 재현용).
#   escalation_evidence : C1 borderline band [0.5,0.7) 보강증거 (2/3 충족 시 조건부 PASS).
#                      list(trailing_port_t=, placebo_p=, book_marginal_delta_sr=, cor_vs_book=).
#                      ① trailing PORT_t>0 ② placebo p<0.05 ③ ΔSR>0 ∧ |cor|<0.30. holdout은 증거 불가(봉인).
#                      retention<0.5는 증거 무관 FAIL(band 남용 차단).
#   oos_fail_pattern : 선택 라벨 "overfit"/"decay" — FAIL 시 사유 분리(decay→screen_route 라우팅, 자본졸업 불가).
# Returns: list(grade, metric_type, essence{...}, hard_fail, reasons)
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

# Bailey-López de Prado (2014) Deflated Sharpe (per-period; dpl_ens_eval_contract.R와 동일 공식)
.essence_dsr <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, A = 12) {
  if (!is.finite(sr_ann) || !is.finite(n_obs) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649
  sr_m <- sr_ann / sqrt(A)
  var0 <- 1 / (n_obs - 1)
  if (is.null(n_trials) || !is.finite(n_trials) || n_trials < 2) {
    sr0 <- 0
  } else {
    z1 <- qnorm(1 - 1 / n_trials); z2 <- qnorm(1 - 1 / (n_trials * exp(1)))
    sr0 <- sqrt(var0) * ((1 - emc) * z1 + emc * z2)
  }
  den <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (!is.finite(den) || den <= 0) return(NA_real_)
  pnorm((sr_m - sr0) * sqrt(n_obs - 1) / den)
}

.rn <- function(x, d = 3) if (is.null(x) || !is.finite(x)) NA_real_ else round(as.numeric(x), d)

.essence_drawdown_profile <- function(bt_result, mdd,
                                      severe = 0.45, extreme = 0.55,
                                      catastrophic = 0.70,
                                      severe_hard_count = 15L,
                                      extreme_hard_count = 6L,
                                      severe_period_hard_frac = 0.25,
                                      severe_max_hard_periods = 252L) {
  pr_n <- tryCatch(nrow(as.data.table(bt_result$period_returns)), error = function(e) NA_integer_)
  pr <- tryCatch(as.data.table(bt_result$period_returns), error = function(e) NULL)
  if (!is.null(pr) && nrow(pr) > 0 && "ret_net" %in% names(pr)) {
    ret <- suppressWarnings(as.numeric(pr$ret_net))
    ret[!is.finite(ret)] <- 0
    nav <- cumprod(1 + pmax(ret, -0.9999))
    dd_path <- nav / cummax(nav) - 1
    .episodes <- function(th) {
      flag <- is.finite(dd_path) & dd_path <= -th
      if (!any(flag)) return(list(count = 0L, total = 0L, max = 0L, frac = 0))
      rr <- rle(flag)
      lens <- rr$lengths[rr$values]
      list(
        count = length(lens),
        total = sum(lens),
        max = max(lens),
        frac = sum(lens) / length(dd_path)
      )
    }
    ep_severe <- .episodes(severe)
    ep_extreme <- .episodes(extreme)
    mdd_path <- abs(min(dd_path, na.rm = TRUE))
    mdd_eff <- if (is.finite(mdd)) mdd else mdd_path
    structural <- isTRUE(is.finite(mdd_eff) && (
      mdd_eff >= catastrophic ||
        ep_severe$count >= severe_hard_count ||
        ep_extreme$count >= extreme_hard_count ||
        (is.finite(ep_severe$frac) && ep_severe$frac >= severe_period_hard_frac)
    ))

    return(list(
      severe_count = as.integer(ep_severe$count),
      extreme_count = as.integer(ep_extreme$count),
      severe_total_periods = as.integer(ep_severe$total),
      severe_max_periods = as.integer(ep_severe$max),
      severe_period_frac = ep_severe$frac,
      catastrophic_threshold = catastrophic,
      severe_hard_count = severe_hard_count,
      extreme_hard_count = extreme_hard_count,
      severe_period_hard_frac = severe_period_hard_frac,
      severe_max_hard_periods = severe_max_hard_periods,
      tail_review = isTRUE(is.finite(mdd_eff) && mdd_eff > severe && !structural),
      structural_hard_fail = structural,
      reason = if (structural) {
        "repeated/sample-dominant severe drawdown"
      } else if (isTRUE(ep_severe$max >= severe_max_hard_periods)) {
        "single long severe-drawdown episode; review, not hard fail"
      } else {
        "tail review or normal drawdown"
      }
    ))
  }

  dd <- tryCatch(as.data.table(bt_result$drawdowns), error = function(e) NULL)
  if (is.null(dd) || nrow(dd) == 0 || !"drawdown_depth" %in% names(dd)) {
    structural <- isTRUE(is.finite(mdd) && mdd >= catastrophic)
    return(list(
      severe_count = 0L, extreme_count = 0L,
      severe_total_periods = 0L, severe_max_periods = 0L,
      severe_period_frac = NA_real_,
      catastrophic_threshold = catastrophic,
      severe_hard_count = severe_hard_count,
      extreme_hard_count = extreme_hard_count,
      severe_period_hard_frac = severe_period_hard_frac,
      severe_max_hard_periods = severe_max_hard_periods,
      tail_review = isTRUE(is.finite(mdd) && mdd > severe && !structural),
      structural_hard_fail = structural,
      reason = "drawdowns table missing; catastrophic MDD only"
    ))
  }

  depth <- abs(suppressWarnings(as.numeric(dd$drawdown_depth)))
  len_col <- if ("total_underwater_period" %in% names(dd)) {
    "total_underwater_period"
  } else if ("drawdown_length" %in% names(dd)) {
    "drawdown_length"
  } else {
    NA_character_
  }
  len <- if (!is.na(len_col)) suppressWarnings(as.numeric(dd[[len_col]])) else rep(NA_real_, length(depth))
  if (length(len) != length(depth)) len <- rep(NA_real_, length(depth))
  len[!is.finite(len)] <- 0
  severe_idx <- is.finite(depth) & depth >= severe
  extreme_idx <- is.finite(depth) & depth >= extreme
  severe_count <- sum(severe_idx)
  extreme_count <- sum(extreme_idx)
  severe_total <- sum(len[severe_idx], na.rm = TRUE)
  severe_max <- if (any(severe_idx)) max(len[severe_idx], na.rm = TRUE) else 0
  severe_frac <- if (is.finite(pr_n) && pr_n > 0) severe_total / pr_n else NA_real_

  structural <- isTRUE(is.finite(mdd) && (
    mdd >= catastrophic ||
      severe_count >= severe_hard_count ||
      extreme_count >= extreme_hard_count ||
      (is.finite(severe_frac) && severe_frac >= severe_period_hard_frac)
  ))

  list(
    severe_count = as.integer(severe_count),
    extreme_count = as.integer(extreme_count),
    severe_total_periods = as.integer(severe_total),
    severe_max_periods = as.integer(severe_max),
    severe_period_frac = severe_frac,
    catastrophic_threshold = catastrophic,
    severe_hard_count = severe_hard_count,
    extreme_hard_count = extreme_hard_count,
    severe_period_hard_frac = severe_period_hard_frac,
    severe_max_hard_periods = severe_max_hard_periods,
    tail_review = isTRUE(is.finite(mdd) && mdd > severe && !structural),
    structural_hard_fail = structural,
    reason = if (structural) {
      "repeated/sample-dominant severe drawdown"
    } else if (isTRUE(severe_max >= severe_max_hard_periods)) {
      "single long recovery severe drawdown; review, not hard fail"
    } else {
      "tail review or normal drawdown"
    }
  )
}

essence_score <- function(bt_result, n_trials_cumulative = NULL,
                          hard_fail = NULL, mdd_hard = 0.45,
                          oos_is_ratio_override = NULL, calmar_min = 0.64,
                          selection_type = NULL,
                          oos_stat_version = "v2",
                          escalation_evidence = NULL,
                          oos_fail_pattern = NULL) {
  .nz <- function(x) { v <- suppressWarnings(as.numeric(if (is.null(x) || length(x) == 0L) NA else x[[1]])); v }
  stopifnot(is.list(bt_result),
            !is.null(bt_result$metrics), !is.null(bt_result$benchmark_compare))
  M  <- as.data.table(bt_result$metrics)
  BC <- as.data.table(bt_result$benchmark_compare)
  # 스키마 변종 robust: 컬럼명 alias 해소 + 결측 시 NA(크래시 금지 → uncertain 강등)
  .col <- function(dt, cands) { h <- intersect(cands, names(dt)); if (length(h)) h[1] else NA_character_ }
  m_nc <- .col(M, c("metric_name", "name")); m_vc <- .col(M, c("metric_value", "value"))
  bc_nc <- .col(BC, c("metric_name", "name")); bc_vc <- .col(BC, c("active_value", "value", "metric_value"))
  getm  <- function(nm) { if (is.na(m_nc) || is.na(m_vc)) return(NA_real_)
                          v <- M[get(m_nc) == nm, get(m_vc)];  if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  getbc <- function(nm) { if (is.na(bc_nc) || is.na(bc_vc)) return(NA_real_)
                          v <- BC[get(bc_nc) == nm, get(bc_vc)]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }

  # --- 5 본질지표 (계약값 읽기만) ---
  sharpe <- getm("Sharpe")
  cagr   <- getm("CAGR")
  mdd    <- getm("MDD")
  calmar <- getm("Calmar")
  net_ir <- getbc("Information_Ratio")
  port_t <- getbc("Portfolio_Alpha_t_NW_lag3")
  dd_profile <- .essence_drawdown_profile(bt_result, mdd, severe = mdd_hard)

  # --- 활성(alpha) 시계열: OOS retention(과적합, DSR 대체) + DSR(스윕 한정) ---
  af <- suppressWarnings(as.numeric(M[["annualization_factor"]][1]))
  if (length(af) != 1 || !is.finite(af)) af <- 12
  dsr <- NA_real_; oos_retention <- NA_real_; oos_retention_splits <- NA_real_
  # DSR *게이트* = sweep형 selection(열거집합 argmax/threshold-pick)에서만 (도훈 mandate 2026-06-10).
  #   selection_type "sweep"=강제 / "chain"(가설주도 순차개선, IS-only 선택 규율)=면제 /
  #   NULL(legacy)=n_trials>1 휴리스틱 (기존 sweep caller 호환). DSR 수치는 n_trials>1이면 진단용 항상 산출.
  has_trials <- !is.null(n_trials_cumulative) && is.finite(n_trials_cumulative) && n_trials_cumulative > 1
  is_sweep <- if (identical(selection_type, "chain")) FALSE
              else if (identical(selection_type, "sweep")) TRUE
              else has_trials
  pr <- bt_result$period_returns; br <- bt_result$benchmark_returns
  if (!is.null(pr) && !is.null(br)) {
    pr <- as.data.table(pr); br <- as.data.table(br)
    if (all(c("date", "ret_net") %in% names(pr)) &&
        all(c("date", "benchmark_ret") %in% names(br))) {
      m <- merge(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], by = "date")
      setorder(m, date)
      a <- m$ret_net - m$benchmark_ret; a <- a[is.finite(a)]
      n <- length(a)
      if (n >= 12 && sd(a) > 0) {
        # OOS retention (C1 v2, 2026-06-10 도훈 mandate): anchored 다중분할 {55/65/75} 중앙값
        #   — 단일 절단점의 임의성 노이즈 축소 (표본 노이즈 자체는 정보이론적 한계, 제거 불가).
        splits <- if (identical(oos_stat_version, "v1")) 0.65 else c(0.55, 0.65, 0.75)
        rets <- vapply(splits, function(fr) {
          k <- floor(n * fr)
          if (k < 6 || (n - k) < 6) return(NA_real_)
          ia <- a[1:k]; oa <- a[(k + 1):n]
          is_ir  <- if (sd(ia) > 0) mean(ia) / sd(ia) * sqrt(af) else NA_real_
          oos_ir <- if (sd(oa) > 0) mean(oa) / sd(oa) * sqrt(af) else NA_real_
          if (is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir / is_ir else NA_real_
        }, numeric(1))
        oos_retention_splits <- rets
        if (any(is.finite(rets))) oos_retention <- stats::median(rets[is.finite(rets)])
        # DSR(BLdP) 수치 = n_trials>1이면 진단용 산출 (게이트 적용은 is_sweep — 아래 dsr_ok).
        if (has_trials) {
          mu <- mean(a); s <- sd(a)
          dsr <- .essence_dsr(mean(a) / s * sqrt(af), n, n_trials_cumulative,
                              mean(((a - mu) / s)^3), mean(((a - mu) / s)^4), A = af)
        }
      }
    }
  }
  # judge lockbox 실 OOS 비율 주입 시 우선 (65/35 fallback 대체)
  if (!is.null(oos_is_ratio_override) && is.finite(oos_is_ratio_override)) oos_retention <- oos_is_ratio_override

  # --- hard_fail: 외부(judge) 주입 우선. 없으면 MDD 깊이 단독이 아니라 빈도/표본 점유율로 추론 ---
  # 단발/소수 시장 동반 폭락과 장기 회복 지연은 tail_review로 남기고,
  # repeated severe drawdown / sample-dominant severe drawdown만 hard fail.
  if (is.null(hard_fail)) hard_fail <- isTRUE(dd_profile$structural_hard_fail)

  # --- C1 borderline band [0.5, 0.7): 보강증거 2/3 충족 시 조건부 통과 (2026-06-10 도훈 mandate) ---
  #   retention >= 0.7 단독 PASS(불변) / < 0.5 무조건 FAIL(증거 무관) / band는 escalation 2/3.
  band_lo <- 0.5; band_hi <- 0.7
  esc_pass <- NA; esc_detail <- NULL
  if (!is.null(escalation_evidence) && is.list(escalation_evidence)) {
    ev <- escalation_evidence
    e1 <- isTRUE(is.finite(.nz(ev$trailing_port_t)) && .nz(ev$trailing_port_t) > 0)
    e2 <- isTRUE(is.finite(.nz(ev$placebo_p)) && .nz(ev$placebo_p) < 0.05)
    e3 <- isTRUE(is.finite(.nz(ev$book_marginal_delta_sr)) && .nz(ev$book_marginal_delta_sr) > 0 &&
                 is.finite(.nz(ev$cor_vs_book)) && abs(.nz(ev$cor_vs_book)) < 0.30)
    esc_pass <- sum(c(e1, e2, e3)) >= 2L
    esc_detail <- list(trailing_port_t_pos = e1, placebo_sig = e2, book_marginal = e3)
  }
  oos_in_band <- is.finite(oos_retention) && oos_retention >= band_lo && oos_retention < band_hi
  oos_ok <- (is.finite(oos_retention) && oos_retention >= band_hi) ||
            (oos_in_band && isTRUE(esc_pass))
  oos_band_status <- if (!is.finite(oos_retention)) NA_character_
                     else if (oos_retention >= band_hi) "pass"
                     else if (oos_in_band && isTRUE(esc_pass)) "band_escalated"
                     else if (oos_in_band) "band_fail"
                     else "fail"

  # --- 등급 (SOT §3.5): 유의성=PORT_t / 과적합=OOS retention / 위험조정=Calmar / DSR=스윕한정 ---
  reasons <- character(0)
  contract_ok <- is.finite(port_t) && is.finite(net_ir)  # 계약 경유 여부
  # DSR 게이트: sweep형 selection에서만 요구. chain/1논문/1알파에선 부적용(통과 간주).
  dsr_ok <- if (is_sweep) (is.finite(dsr) && dsr >= 0.5) else TRUE
  a_core <- (is.finite(port_t) && port_t >= 2.95 &&
             oos_ok &&
             is.finite(sharpe) && sharpe >= 0.8 &&
             is.finite(cagr)   && cagr   >= 0.16 &&
             is.finite(calmar) && calmar >= calmar_min)

  if (!contract_ok) {
    grade <- "uncertain"
    reasons <- "PORT_t/net_IR 미산출(계약 미경유) — 추정 등급 금지"
  } else if (hard_fail) {
    grade <- "F"
    reasons <- sprintf("hard_fail drawdown structure (MDD %.1f%%, %.0f%%+ episodes=%d, %.0f%%+ episodes=%d, max_underwater=%d periods)",
                       mdd * 100, mdd_hard * 100, dd_profile$severe_count,
                       max(0.55, mdd_hard + 0.10) * 100, dd_profile$extreme_count,
                       dd_profile$severe_max_periods)
  } else if (port_t <= 0 || net_ir <= 0) {
    grade <- "F"
    reasons <- "non-positive alpha (PORT_t<=0 또는 net_IR<=0)"
  } else if (a_core && dsr_ok) {
    grade <- "A"
    reasons <- sprintf("Standalone: PORT_t>=2.95 & OOS_ret %s & Sharpe>=0.8 & CAGR>=16%% & Calmar>=%.2f%s%s",
                       if (identical(oos_band_status, "band_escalated")) "band[0.5,0.7) escalated 2/3" else ">=0.7",
                       calmar_min, if (is_sweep) " & DSR>=0.5(sweep)" else "",
                       if (isTRUE(dd_profile$tail_review)) " & drawdown_tail_review" else "")
  } else if (port_t >= 2.0 && net_ir > 0.2) {
    grade <- "B"
    miss <- c(if (!oos_ok) sprintf("OOS_ret %s<0.7(band %s)",
                                   if (is.finite(oos_retention)) sprintf("%.2f", oos_retention) else "NA",
                                   if (is.na(oos_band_status)) "NA" else oos_band_status) else NULL,
              if (!is.finite(sharpe) || sharpe < 0.8) "Sharpe<0.8" else NULL,
              if (!is.finite(cagr) || cagr < 0.16) "CAGR<16%" else NULL,
              if (!is.finite(calmar) || calmar < calmar_min) sprintf("Calmar<%.2f", calmar_min) else NULL,
              if (is_sweep && !dsr_ok) "DSR<0.5(sweep)" else NULL)
    reasons <- paste0("Component: PORT_t>=2.0 & net_IR>0.2; A 미달[",
                      if (length(miss)) paste(miss, collapse = ",") else "?", "]")
  } else {
    grade <- "C"
    reasons <- "Ensemble: positive alpha이나 B 미달 (블렌드에서만 가치)"
  }

  list(
    grade = grade,
    metric_type = if (contract_ok) "backtested" else "uncertain",
    essence = list(
      net_sharpe                 = .rn(sharpe),
      net_ir                     = .rn(net_ir),
      portfolio_alpha_t_nw_lag3  = .rn(port_t),
      oos_retention              = .rn(oos_retention),
      dsr                        = .rn(dsr),
      mdd                        = .rn(mdd),
      calmar                     = .rn(calmar),
      cagr                       = .rn(cagr),
      drawdown_profile           = list(
        severe45_count = dd_profile$severe_count,
        severe55_count = dd_profile$extreme_count,
        severe45_total_periods = dd_profile$severe_total_periods,
        severe45_max_periods = dd_profile$severe_max_periods,
        severe45_period_frac = .rn(dd_profile$severe_period_frac, 4),
        catastrophic_mdd_threshold = dd_profile$catastrophic_threshold,
        severe45_hard_count = dd_profile$severe_hard_count,
        severe55_hard_count = dd_profile$extreme_hard_count,
        severe45_period_hard_frac = .rn(dd_profile$severe_period_hard_frac, 4),
        severe45_max_hard_periods = dd_profile$severe_max_hard_periods,
        tail_review = isTRUE(dd_profile$tail_review),
        structural_hard_fail = isTRUE(dd_profile$structural_hard_fail)
      )
    ),
    hard_fail = hard_fail,
    n_trials_cumulative = n_trials_cumulative,
    selection_type = selection_type,
    dsr_gate_applied = is_sweep,
    oos_stat_version = oos_stat_version,
    oos_retention_splits = round(oos_retention_splits, 3),
    oos_band_status = oos_band_status,
    oos_escalation = esc_detail,
    oos_fail_pattern = if (is.null(oos_fail_pattern)) NA_character_ else as.character(oos_fail_pattern),
    reasons = reasons
  )
}

if (sys.nframe() == 0) cat("[essence_score] Loaded — essence_score(bt_result, n_trials_cumulative, selection_type).\n")
