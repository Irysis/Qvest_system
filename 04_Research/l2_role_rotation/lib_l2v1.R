#==============================================================================
# lib_l2v1.R — PR-L2-ROLESLEEVE-V1 순수 함수(입출력·전역 상태 없음 · 2026-10-10)
#
# 빌더(build_l2v1_labels.R) · MC2(mc2_l2v1.R) · 판정(verdict_l2v1.R) 이 같이 쓴다 — 사전등록(초안 pins)이 sha256 을 고정한다.
#
# 정의와 근거(수치·정의의 출처):
#   · 하방 베타 β− = cov(r_i, r_m | r_m < μ_m) / var(r_m | r_m < μ_m) · μ_m = 추정 창의 시장 평균 수익(조건부 적률)
#       Ang, Chen & Xing (2006) "Downside Risk", Review of Financial Studies 19(4) eq.(1) https://doi.org/10.1093/rfs/hhj035
#       — 원문은 일간 초과수익 · 12개월 창. 여기서는 원수익(무위험 미차감): 창 안 상수 차감은 cov·var·하락일 집합을 바꾸지 않는다.
#   · 총 베타(진단 전용 · 슬리브 선택에 쓰지 않는다) β_TS = ρ̂ · σ̂_i / σ̂_m — σ̂ = 1년(252일) 일간 로그수익 표준편차(최소 120일) ·
#       ρ̂ = 5년(1260일) 겹치는 3일 로그수익 상관(최소 750) — Frazzini & Pedersen (2014) "Betting against beta",
#       Journal of Financial Economics 111(1) §3.1 https://doi.org/10.1016/j.jfineco.2013.10.005
#   · 하위 삼분위 = 적격 n 중 β− 오름차순 상위 ceiling(n/3) — 3분위 등분(dplyr::ntile 1군 크기와 같다) ·
#       동률 = member_id 오름차순(C 로캘 radix — 자료 무관 결정론)
#   · NW t = 평균의 Newey-West(Bartlett) t — 계산은 계약(backtest_result_contract.R::.nw_t_mean · beta_controlled_alpha.R)이 한다.
#       이 파일은 계약 함수를 인자로 받아 부를 뿐 재구현하지 않는다(AX-008 · 손계산 금지).
#==============================================================================
suppressPackageStartupMessages({ library(data.table) })

# 창 — 정본 벤치 거래일 cal(정렬된 Date) 중 결정일 dd 보다 **엄격히 이전**(date < dd)인 마지막 n 일의 위치. 모자라면 NULL.
#   leak = k(>0) 는 누출 양성 대조 전용 — 결정일 이후 첫 k 거래일까지 넣는 '틀린' 창(계기가 발화하는지 보이는 용도). 운영 경로는 0.
l2v1_window <- function(cal, dd, n, leak = 0L) {
  i <- which(cal < dd)
  if (leak > 0L) { j <- which(cal >= dd); if (length(j) < leak) return(NULL); i <- c(i, j[seq_len(leak)]) }
  if (length(i) < n) return(NULL)
  utils::tail(i, n)
}

# ACX(2006) eq.(1) 하방 베타 — 입력에 결측이 하나라도 있으면 NA(조용한 표본 축소 금지 · 적격 판정은 호출부가 먼저 한다)
l2v1_beta_minus <- function(ri, rmk) {
  ri <- as.numeric(ri); rmk <- as.numeric(rmk)
  if (length(ri) != length(rmk) || !length(rmk)) stop("[lib_l2v1] β−: 길이 불일치 또는 빈 입력")
  if (any(!is.finite(ri)) || any(!is.finite(rmk))) return(c(beta = NA_real_, n_down = NA_real_, mu = NA_real_))
  mu <- mean(rmk); dn <- rmk < mu; nd <- sum(dn)
  if (nd < 2L) return(c(beta = NA_real_, n_down = nd, mu = mu))          # 분산 정의 최소(2) — 252일 창에서는 도달 불가
  v <- stats::var(rmk[dn])
  if (!is.finite(v) || v <= 0) return(c(beta = NA_real_, n_down = nd, mu = mu))
  c(beta = stats::cov(ri[dn], rmk[dn]) / v, n_down = nd, mu = mu)
}

# FP(2014) 총 베타(진단) — li/lm = 일간 로그수익. 1y = 252일 창 · 5y = 1260일 창(앞쪽 결측 허용 — 3일 합은 세 날 모두 유효할 때만)
l2v1_fp_beta <- function(li_1y, lm_1y, li_5y, lm_5y, min_vol = 120L, min_cor = 750L, k = 3L) {
  na <- c(beta_ts = NA_real_, sigma_i = NA_real_, sigma_m = NA_real_, rho = NA_real_, n_vol = NA_real_, n_cor = NA_real_)
  ok1 <- is.finite(li_1y) & is.finite(lm_1y)
  if (sum(ok1) < min_vol) { na["n_vol"] <- sum(ok1); return(na) }
  si <- stats::sd(li_1y[ok1]); sm <- stats::sd(lm_1y[ok1])
  s3 <- function(x) { n <- length(x); if (n < k) return(numeric(0)); as.numeric(stats::filter(x, rep(1, k), sides = 1))[k:n] }
  ri3 <- s3(as.numeric(li_5y)); rm3 <- s3(as.numeric(lm_5y))
  ok <- is.finite(ri3) & is.finite(rm3)
  out <- c(beta_ts = NA_real_, sigma_i = si, sigma_m = sm, rho = NA_real_, n_vol = sum(ok1), n_cor = sum(ok))
  if (sum(ok) < min_cor || !is.finite(sm) || sm <= 0) return(out)
  rho <- stats::cor(ri3[ok], rm3[ok])
  out["rho"] <- rho; out["beta_ts"] <- rho * si / sm
  out
}

# 하위 삼분위 — beta 가 유한한 것만 적격. 반환: in_sleeve(논리) · rank(적격 안 순위 · 부적격 NA) · n · k
l2v1_low_tercile <- function(beta, ids) {
  beta <- as.numeric(beta); ids <- as.character(ids)
  ok <- is.finite(beta); n <- sum(ok); k <- if (n > 0L) as.integer(ceiling(n / 3)) else 0L
  in_s <- rep(FALSE, length(beta)); rk <- rep(NA_integer_, length(beta))
  if (n > 0L) {
    w <- which(ok); o <- order(beta[ok], ids[ok], method = "radix")
    rk[w[o]] <- seq_len(n)
    in_s[w[o[seq_len(k)]]] <- TRUE
  }
  list(in_sleeve = in_s, rank = rk, n = n, k = k)
}

# MC2 월 표 — mon(member_id, ym, r: 정본 월간화) · lab(ym = 보유월, member_id, eligible, in_sleeve) · bmm(ym, b)
#   r_s = 슬리브 구성원 중 그 달 수익이 유한한 것의 동일가중 · r_c = 그 결정일 적격 후보 중 수익이 유한한 것의 동일가중
#   포함 월 = 슬리브 구성원 수익 ≥1 (v0 MC2 와 같은 규칙) ∩ 벤치 월 ∩ 평가 창
l2v1_mc2_table <- function(mon, lab, hm_ym, bmm) {
  s <- merge(lab[in_sleeve %in% TRUE, .(ym, member_id)], mon, by = c("ym", "member_id"))[is.finite(r), .(r_s = mean(r), n_s = .N), by = ym]
  cc <- merge(lab[eligible %in% TRUE, .(ym, member_id)], mon, by = c("ym", "member_id"))[is.finite(r), .(r_c = mean(r), n_c = .N), by = ym]
  x <- merge(merge(s, cc, by = "ym"), bmm[, .(ym, b)], by = "ym")
  x <- x[ym %in% hm_ym][order(ym)]
  x[, d := r_s - r_c]
  x[]
}

# MC2 1차·2차 통계 — 계약 함수 주입: nw_t_mean = backtest_result_contract.R::.nw_t_mean · bca = beta_controlled_alpha.R::beta_controlled_alpha
#   R = sr_regimes() (ym, ps_bear …) · lag = NW lag · thr = 1차 t 문턱(사전등록)
l2v1_mc2_stats <- function(x, R, nw_t_mean, bca, lag, thr) {
  m <- merge(x, R[, .(ym, ps_bear)], by = "ym")[order(ym)]
  bear <- m$ps_bear %in% TRUE
  d_b <- m$d[bear]
  if (length(d_b) < 12L) stop(sprintf("[lib_l2v1] 약세월 %d < 12 — beta_controlled_alpha 판정 불가", length(d_b)))
  t_nw <- nw_t_mean(d_b, lag = lag)
  bc <- bca(m$r_s[bear], m$r_c[bear], periods_per_year = 12, nw_lag = lag)
  if (!isTRUE(abs(t_nw - bc$port_t) < 1e-8)) stop(sprintf("[lib_l2v1] MC2 t 불일치: .nw_t_mean %.10f ≠ beta_controlled_alpha port_t %.10f", t_nw, bc$port_t))
  bd <- bca(d_b, m$b[bear], periods_per_year = 12, nw_lag = lag)              # (r_s − r_c) = a + (β_s − β_c)·b + e
  bs <- bca(m$r_s[bear], m$b[bear], periods_per_year = 12, nw_lag = lag)
  bcc <- bca(m$r_c[bear], m$b[bear], periods_per_year = 12, nw_lag = lag)
  nb <- !bear
  t_nb <- if (sum(nb) >= lag + 2L) nw_t_mean(m$d[nb], lag = lag) else NA_real_
  bs_all <- bca(m$r_s, m$b, periods_per_year = 12, nw_lag = lag); bc_all <- bca(m$r_c, m$b, periods_per_year = 12, nw_lag = lag)
  list(
    n_months = nrow(m), n_bear_months = sum(bear), first_ym = m$ym[1], last_ym = m$ym[nrow(m)],
    primary = list(value = mean(d_b), value_ann_x12 = 12 * mean(d_b), t = t_nw, t_crosscheck_bca_port_t = bc$port_t,
                   t_threshold = thr, pass = isTRUE(mean(d_b) > 0) && isTRUE(t_nw >= thr),
                   rule = "mean_bear(r_sleeve − r_candEW) > 0 ∧ NW t ≥ 문턱"),
    secondary = list(
      bear_beta_diff = list(value = bd$beta, t_beta_nw = bd$t_beta, beta_sleeve = bs$beta, beta_cand = bcc$beta,
                            alpha_diff_ann = bd$alpha_ann, t_alpha_diff = bd$t_alpha,
                            note = "약세월만 회귀: (r_s − r_c) = α + (β_s − β_c)·b — β 는 OLS 선형성으로 β_s − β_c 와 같다"),
      bear_sleeve_vs_cand_bca = list(alpha_ann = bc$alpha_ann, t_alpha = bc$t_alpha, beta = bc$beta,
                                     note = "약세월 r_s 를 r_c 에 회귀(보고)"),
      nonbear = list(n = sum(nb), mean_d = if (any(nb)) mean(m$d[nb]) else NA_real_, nw_t = t_nb),
      means = list(bear = list(r_s = mean(m$r_s[bear]), r_c = mean(m$r_c[bear]), b = mean(m$b[bear])),
                   nonbear = list(r_s = if (any(nb)) mean(m$r_s[nb]) else NA_real_, r_c = if (any(nb)) mean(m$r_c[nb]) else NA_real_,
                                  b = if (any(nb)) mean(m$b[nb]) else NA_real_)),
      full_window_beta = list(sleeve = bs_all$beta, cand = bc_all$beta)),
    table = m)
}

# 짝지은 일간 대조(v0 verdict_l2v0.R::contrast 와 같은 식) — A, B = data.table(date, ret)
l2v1_contrast <- function(A, B, target, lag, bca) {
  x <- merge(A[, .(date, ra = ret)], B[, .(date, rb = ret)], by = "date")
  cf <- nrow(x) / max(nrow(A), nrow(B))
  r <- bca(x$ra, x$rb, periods_per_year = 252, nw_lag = lag)
  v <- r$active_ann / 252; t <- r$port_t; se <- if (is.finite(t) && t != 0) v / t else NA_real_
  list(target = target, contract = "beta_controlled_alpha", nw_lag = lag, n = r$n, n_dropped = r$n_dropped,
       common_frac = cf, value = v, value_ann = r$active_ann, t = t, se = se,
       ci_level = 0.90, ci_lo = v - stats::qnorm(0.95) * se, ci_hi = v + stats::qnorm(0.95) * se,
       t_alpha = r$t_alpha, alpha_ann = r$alpha_ann, beta = r$beta, t_beta = r$t_beta)
}

# H1 라벨(v0 규칙 그대로 — verdict_l2v0.R §4) — IE = 함의 효과(일) · T_LO/T_HI = 결정 파라미터
l2v1_h1_label <- function(H1, IE, T_LO, T_HI, mc3_pass, vintage_ok, after_ok) {
  te <- if (is.finite(H1$se) && H1$se > 0) (H1$value - IE) / H1$se else NA_real_
  zero_in <- is.finite(H1$t) && H1$t > T_LO && H1$t < T_HI
  excl_ie <- is.finite(te) && te <= T_LO
  label <- if (!vintage_ok || !after_ok) NA_character_ else if (!mc3_pass) "undetermined" else
           if (is.finite(H1$t) && H1$t <= T_LO) "failed" else if (is.finite(H1$t) && H1$t >= T_HI) "confirmed" else
           if (zero_in && excl_ie) "powered_null" else "undetermined"
  status <- if (!vintage_ok) "invalid:vintage_mismatch" else if (!after_ok) "invalid:measured_before_lock" else
            if (!mc3_pass) "concluded:treatment_not_delivered" else "concluded"
  list(label = label, status = status, te = te, zero_in = zero_in, implied_excluded = excl_ie)
}
