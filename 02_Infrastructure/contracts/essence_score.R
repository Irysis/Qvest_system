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
#   DSR ≥ 0.5 (BLdP 2014)  ← **다중검정 스타일(n_trials>1: ML스윕/optimizer서치/앙상블)에서만 추가 게이트.**
#                            1논문/1알파 검증엔 부적용(PORT_t 2.95가 이미 문헌 다중검정 반영, 중복).
#
# 18-component proxy 합산(hurdle_gate.R)은 폐기 — 진단용으로만 retain.
#
# essence_score(bt_result, n_trials_cumulative = NULL, hard_fail = NULL)
#   bt_result : build_bt_result() 10-component (계약). 필수: metrics, benchmark_compare.
#   n_trials_cumulative : DSR 산출용 누적 시행수. NULL이면 DSR=NA → Grade A 불가(B 이하).
#   hard_fail : 외부 주입(judge). NULL이면 MDD>mdd_hard로 추론.
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

essence_score <- function(bt_result, n_trials_cumulative = NULL,
                          hard_fail = NULL, mdd_hard = 0.45,
                          oos_is_ratio_override = NULL, calmar_min = 0.64) {
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

  # --- 활성(alpha) 시계열: OOS retention(과적합, DSR 대체) + DSR(스윕 한정) ---
  af <- suppressWarnings(as.numeric(M[["annualization_factor"]][1]))
  if (length(af) != 1 || !is.finite(af)) af <- 12
  dsr <- NA_real_; oos_retention <- NA_real_
  # DSR 적용 = 다중검정 스타일(ML 스윕/optimizer 서치/앙상블 스윕)에서만. n_trials>1이 그 신호.
  is_sweep <- !is.null(n_trials_cumulative) && is.finite(n_trials_cumulative) && n_trials_cumulative > 1
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
        # OOS retention = 활성 Sharpe(OOS) / 활성 Sharpe(IS), 65/35 chronological
        k <- floor(n * 0.65)
        if (k >= 6 && (n - k) >= 6) {
          ia <- a[1:k]; oa <- a[(k + 1):n]
          is_ir  <- if (sd(ia) > 0) mean(ia) / sd(ia) * sqrt(af) else NA_real_
          oos_ir <- if (sd(oa) > 0) mean(oa) / sd(oa) * sqrt(af) else NA_real_
          if (is.finite(is_ir) && is_ir > 0.05) oos_retention <- oos_ir / is_ir
        }
        # DSR(BLdP) = 스윕에서만. 1논문/1알파엔 부적용(PORT_t 2.95가 이미 문헌 다중검정 반영).
        if (is_sweep) {
          mu <- mean(a); s <- sd(a)
          dsr <- .essence_dsr(mean(a) / s * sqrt(af), n, n_trials_cumulative,
                              mean(((a - mu) / s)^3), mean(((a - mu) / s)^4), A = af)
        }
      }
    }
  }
  # judge lockbox 실 OOS 비율 주입 시 우선 (65/35 fallback 대체)
  if (!is.null(oos_is_ratio_override) && is.finite(oos_is_ratio_override)) oos_retention <- oos_is_ratio_override

  # --- hard_fail: 외부(judge) 주입 우선, 없으면 MDD 한도로 추론 ---
  if (is.null(hard_fail)) hard_fail <- isTRUE(is.finite(mdd) && mdd > mdd_hard)

  # --- 등급 (SOT §3.5): 유의성=PORT_t / 과적합=OOS retention / 위험조정=Calmar / DSR=스윕한정 ---
  reasons <- character(0)
  contract_ok <- is.finite(port_t) && is.finite(net_ir)  # 계약 경유 여부
  # DSR 게이트: 스윕(n_trials>1)에서만 요구. 1논문/1알파에선 부적용(통과 간주).
  dsr_ok <- if (is_sweep) (is.finite(dsr) && dsr >= 0.5) else TRUE
  a_core <- (is.finite(port_t) && port_t >= 2.95 &&
             is.finite(oos_retention) && oos_retention >= 0.7 &&
             is.finite(sharpe) && sharpe >= 0.8 &&
             is.finite(cagr)   && cagr   >= 0.16 &&
             is.finite(calmar) && calmar >= calmar_min)

  if (!contract_ok) {
    grade <- "uncertain"
    reasons <- "PORT_t/net_IR 미산출(계약 미경유) — 추정 등급 금지"
  } else if (hard_fail) {
    grade <- "F"
    reasons <- sprintf("hard_fail (MDD %.1f%% > %.0f%% 또는 외부주입)", mdd * 100, mdd_hard * 100)
  } else if (port_t <= 0 || net_ir <= 0) {
    grade <- "F"
    reasons <- "non-positive alpha (PORT_t<=0 또는 net_IR<=0)"
  } else if (a_core && dsr_ok) {
    grade <- "A"
    reasons <- sprintf("Standalone: PORT_t>=2.95 & OOS_ret>=0.7 & Sharpe>=0.8 & CAGR>=16%% & Calmar>=%.2f%s",
                       calmar_min, if (is_sweep) " & DSR>=0.5(sweep)" else "")
  } else if (port_t >= 2.0 && net_ir > 0.2) {
    grade <- "B"
    miss <- c(if (!is.finite(oos_retention) || oos_retention < 0.7) "OOS_ret<0.7" else NULL,
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
      cagr                       = .rn(cagr)
    ),
    hard_fail = hard_fail,
    n_trials_cumulative = n_trials_cumulative,
    reasons = reasons
  )
}

if (sys.nframe() == 0) cat("[essence_score] Loaded — essence_score(bt_result, n_trials_cumulative).\n")
