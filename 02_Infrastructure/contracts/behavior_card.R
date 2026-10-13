#==============================================================================
# behavior_card.R — 행동 카드 계약 (v10.01 · 2026-10-13 · 도훈 지시 "투자철학 실현을 위한 리서치 프로세스")
#
# 왜: v10.01 은 등급(A)을 직접 최적화하지 않고 '행동 목표'로 설계한다(개선안 §2 · §7 · 대안 설계).
#   도훈 철학 = 남들 다 깨질 때 덜 잃고(하락 포착률), 강세장을 충분히 따라가(상승 포착률 ≥ uc_floor),
#   그 비대칭으로 복리를 지킨다. 이 계약은 그 행동을 '위기 단위'로 잰다 —
#   하락월 평균(defensive_score.R)과 베타 잔차(strategy_role.R)의 다음 단계.
#
# 무엇을 재나 (벤치 = 공표 KOSPI200):
#   ① 위기 = 일간 벤치의 누적 고점 → (그 고점을 되찾기 전) 최저점 구간 중 깊이 ≥ crisis_depth(관례 −20%).
#      ★PS 월간 연대기만 쓰면 표본 끝 전환점이 확정되지 않아 2026-06~07 −40.9% 급락을 놓친다(10-13 실측) — 그래서 위기는 낙폭으로 잰다.
#   ② 위기별: 같은 구간 전략의 최대낙폭 → 낙폭 포착률 dd_capture · 누적 포착률 cum_capture · 고점 회복 일수(중도절단 표시)
#   ③ 강세 = Pagan-Sossounov 강세 국면(월간 · CRAN bbdetection 기본값 = strategy_role.R::sr_regimes 와 같은 정의)
#      → 상승 포착률 up_capture(누적수익 비)
#   ④ CR 판정 strong / normal / weak / insufficient — 문턱은 설정(06_Registry/behavior_card.json).
#      '강함'의 누적 포착률 문턱은 uc_floor 에서 도출한다(bc_dc_strong_max — 새 숫자 없음).
#      '강함'은 같은 창 전략 MDD ≤ 벤치 MDD 도 요구한다(strong_mdd_vs_bench_max · 2026-10-13 도훈 수용 GRADE-V3-S0-BANDS ④) —
#      위기 포착은 벤치 위기 구간 안만 보므로, 시장이 멀쩡할 때 혼자 무너진 전략을 '강함'에서 거른다.
#   ⑤ CDaR(α) · MDD · CAGR · Calmar(월간) · 베타(전체·하락·상승) · 롤링 36M 통과율(rolling_grade.R::rg_rolling 재사용)
#   ⑥ τ_D 분할 — 보는 창(위기가 τ_D 이전에 시작·바닥) / 시험 창(τ_D 이후 시작) 요약을 따로 낸다
#
# 경계: 등급을 내지 않는다(등급 정본 = essence_score.R). 산출은 기록이고 소비자는 처방 루프 · 철학 감독관 · 텔레그램이다.
#   크기 짝 · 노출 짝 대조(R5 · 개선안 §3.5 조건)는 보유 기록으로 만든 대조 수익이 필요하다 — bc_attach_controls() 로 붙인다
#   (생성기 · 귀속 라벨 = matched_controls.R · MC8 — 측정 디렉터리에서 카드+대조를 한 번에 내는 정본 경로는 mc_card()).
#   대조가 없으면 controls$status = "not_provided" 로 남는다(침묵 통과 아님 — 방어 '실력' 주장은 대조 없이는 불가).
#
# 공개: bc_cfg · bc_monthly · bc_regimes · bc_phases · bc_crises · bc_dc_strong_max · bc_card ·
#       bc_attach_controls · bc_card_from_artifacts · bc_write
# 검사: 08_Tests/contracts/test_behavior_card.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.bc_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.bc_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[behavior_card] 프로젝트 루트 해석 실패")
}

#' 설정 정본 읽기 — 필수 키가 없으면 멈춘다(기본값을 지어내지 않는다)
bc_cfg <- function(root = NULL, path = NULL) {
  p <- .bc_or(path, file.path(.bc_root(root), "06_Registry/behavior_card.json"))
  cfg <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(cfg)) stop("[behavior_card] 설정 판독 불가: ", p)
  need <- c("tau_d", "period_start", "uc_floor", "dc_derive_window", "majority_share",
            "weak_capture_floor", "cdar_alpha", "crisis_depth", "strong_mdd_vs_bench_max")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[behavior_card] 설정 키 누락: ", paste(miss, collapse = ","))
  # 위기 정의 어휘(2026-10-13 도훈 결정 CRISIS-DEF-LT2020) — 없으면 구판(running_peak_drawdown)이다(구 설정 사본 · 사전등록 판 재현)
  def <- .bc_or(cfg[["crisis_episode_def"]], "running_peak_drawdown")
  if (!def %in% c("running_peak_drawdown", "lt_first_passage"))
    stop("[behavior_card] crisis_episode_def 어휘 밖: ", def, " (running_peak_drawdown | lt_first_passage)")
  if (identical(def, "lt_first_passage")) {
    for (k in c("crisis_lambda_down", "crisis_lambda_up")) {
      v <- cfg[[k]]
      if (!is.numeric(v) || length(v) != 1L || !is.finite(v) || v <= 0 || v >= 1)
        stop("[behavior_card] lt_first_passage 는 ", k, " ∈ (0, 1) 가 필요하다")
    }
  }
  cfg$crisis_episode_def <- def
  cfg
}

# (date, 수익열) → 정렬된 (date, r)
.bc_series <- function(x, col) {
  d <- as.data.table(x)
  if (!"date" %in% names(d)) stop("[behavior_card] date 열 없음")
  if (!col %in% names(d)) stop("[behavior_card] 수익 열 없음: ", col)
  d <- d[is.finite(get(col)), .(date = as.Date(date), r = as.numeric(get(col)))][order(date)]
  if (!nrow(d)) stop("[behavior_card] 유효한 수익 행 없음: ", col)
  d
}

#' 일간 또는 월간 수익 → 월간 (ym, r)
bc_monthly <- function(x, col) {
  d <- .bc_series(x, col)
  d[, ym := format(date, "%Y-%m")]
  d[, .(r = prod(1 + r) - 1), by = ym][order(ym)]
}

.bc_is_daily <- function(d) {
  n <- d[, .N, by = .(format(date, "%Y-%m"))]$N
  length(n) && stats::median(n) > 3
}

#' 벤치 월간 수익 → 약세 표식(Pagan-Sossounov). NA(연대기 끝 미확정)는 그대로 둔다
bc_regimes <- function(bm_monthly) {
  if (!requireNamespace("bbdetection", quietly = TRUE))
    stop("[behavior_card] bbdetection 미설치 — install.packages('bbdetection')")
  x <- copy(as.data.table(bm_monthly))[order(ym)]
  x[, nav := cumprod(1 + r)]
  bbdetection::setpar_dating_alg()
  bull <- bbdetection::run_dating_alg(x$nav)
  x[, bear := !as.logical(bull)]
  x[, .(ym, bear)]
}

#' 연속된 같은 국면을 묶는다 (PS 연대기 → 강세/약세 국면)
bc_phases <- function(reg) {
  r <- copy(as.data.table(reg))[!is.na(bear)][order(ym)]
  if (!nrow(r)) return(data.table(start_ym = character(0), end_ym = character(0),
                                  n_months = integer(0), kind = character(0)))
  r[, run := rleid(bear)]
  ep <- r[, .(start_ym = ym[1], end_ym = ym[.N], n_months = .N,
              kind = if (isTRUE(bear[1])) "bear" else "bull"), by = run]
  ep[, run := NULL][]
}

#' 위기 구간 — 벤치(일간 권장) 누적 고점 → 그 고점을 되찾기 전 최저점. 깊이 ≥ depth 만
#' @param bm data.table(date, r)  @return data.table(peak_date, trough_date, recover_date, depth, ongoing)
bc_crises <- function(bm, depth) {
  b <- copy(as.data.table(bm))[order(date)]
  nav <- cumprod(1 + b$r); dts <- b$date
  out <- list(); i <- 1L; n <- length(nav)
  pk <- nav[1]; pk_i <- 1L; tr <- nav[1]; tr_i <- 1L; under <- FALSE
  for (j in seq_len(n)) {
    v <- nav[j]
    if (v >= pk) {
      if (under && (1 - tr / pk) >= depth)
        out[[length(out) + 1L]] <- data.table(peak_date = dts[pk_i], trough_date = dts[tr_i],
                                              recover_date = dts[j], depth = 1 - tr / pk, ongoing = FALSE)
      pk <- v; pk_i <- j; tr <- v; tr_i <- j; under <- FALSE
    } else {
      under <- TRUE
      if (v < tr) { tr <- v; tr_i <- j }
    }
  }
  if (under && (1 - tr / pk) >= depth)
    out[[length(out) + 1L]] <- data.table(peak_date = dts[pk_i], trough_date = dts[tr_i],
                                          recover_date = as.Date(NA), depth = 1 - tr / pk, ongoing = TRUE)
  if (!length(out)) return(data.table(peak_date = as.Date(character(0)), trough_date = as.Date(character(0)),
                                      recover_date = as.Date(character(0)), depth = numeric(0), ongoing = logical(0)))
  rbindlist(out)
}

#' 위기 구간 — Lunde & Timmermann(2004) 첫 통과 규칙(2026-10-13 도훈 결정 CRISIS-DEF-LT2020)
#'   강세 상태에서 국지 고점 대비 λ_down 하락 = 약세 전환(그 고점이 위기 시작) · 약세 상태에서 국지 저점 대비 λ_up 반등 = 강세 전환(그 저점이 위기 바닥).
#'   구판(bc_crises)과 달리 '이전 고점을 되찾아야' 끝나지 않는다 — 여러 파동이 뭉친 긴 하락(2017-11→2020-03 · 2008)을 반등 기준으로 가른다.
#'   근거: Lunde, A. & Timmermann, A. (2004) Duration Dependence in Stock Prices: An Analysis of Bull and Bear Markets,
#'   Journal of Business & Economic Statistics 22(3):253-273 · 알고리즘 서술 = Maheu, McCurdy & Song 의 정리(Ntantamis 2010,
#'   CREATES RP 2010-51 부록 A 재인용) · 문턱 관례 0.2(같은 문헌: "A conventional value used in the financial press is 0.2 for both thresholds").
#' @return data.table(peak_date, trough_date, recover_date, depth, ongoing) — bc_crises 와 같은 열
bc_crises_lt <- function(bm, l_down, l_up) {
  b <- copy(as.data.table(bm))[order(date)]
  P <- cumprod(1 + b$r); D <- b$date; n <- length(P)
  empty <- data.table(peak_date = as.Date(character(0)), trough_date = as.Date(character(0)),
                      recover_date = as.Date(character(0)), depth = numeric(0), ongoing = logical(0))
  if (n < 2L) return(empty)
  out <- list(); st <- 1L; ext <- P[1]; exti <- 1L; pki <- NA_integer_
  rec <- function(pk, from) { k <- which(P[from:n] >= P[pk]); if (length(k)) D[from + k[1] - 1L] else as.Date(NA) }
  for (t in 2:n) {
    if (st == 1L) {
      if (P[t] >= ext) { ext <- P[t]; exti <- t }
      else if (P[t] <= (1 - l_down) * ext) { pki <- exti; st <- 0L; ext <- P[t]; exti <- t }
    } else {
      if (P[t] <= ext) { ext <- P[t]; exti <- t }
      else if (P[t] >= (1 + l_up) * ext) {
        out[[length(out) + 1L]] <- data.table(peak_date = D[pki], trough_date = D[exti], recover_date = rec(pki, exti),
                                              depth = 1 - P[exti] / P[pki], ongoing = FALSE)
        st <- 1L; ext <- P[t]; exti <- t
      }
    }
  }
  if (st == 0L) out[[length(out) + 1L]] <- data.table(peak_date = D[pki], trough_date = D[exti], recover_date = as.Date(NA),
                                                      depth = 1 - P[exti] / P[pki], ongoing = TRUE)
  if (!length(out)) return(empty)
  rbindlist(out)
}

# 설정이 정한 위기 정의로 위기 구간을 낸다
.bc_crises_by_cfg <- function(bm, cfg) {
  if (identical(.bc_or(cfg[["crisis_episode_def"]], "running_peak_drawdown"), "lt_first_passage"))
    bc_crises_lt(bm, cfg[["crisis_lambda_down"]], cfg[["crisis_lambda_up"]]) else bc_crises(bm, cfg$crisis_depth)
}

# 수익 경로 → 누적수익 · 경로 최대낙폭(시작 수준 1 포함)
.bc_path <- function(v) {
  nav <- cumprod(1 + v)
  path <- c(1, nav)
  list(cum = nav[length(nav)] - 1, dd = max(1 - path / cummax(path)))
}

# 시작 수준(=1)을 되찾는 데 걸린 관측 수 — 한 번도 밑돌지 않았으면 0, 끝까지 못 되찾으면 중도절단
.bc_recovery <- function(v_from_start) {
  nav <- cumprod(1 + v_from_start)
  if (all(nav >= 1)) return(list(n = 0L, censored = FALSE))
  low <- which.min(nav)
  back <- which(nav[low:length(nav)] >= 1)
  if (!length(back)) return(list(n = NA_integer_, censored = TRUE))
  list(n = as.integer(low + back[1] - 1L), censored = FALSE)
}

#' '강함' 누적 포착률 문턱 — PS 강세→약세 쌍마다 (1+uc·U)(1−d·D) ≥ (1+U)(1−D) 를 만족하는 d 상한의 중앙값.
#' d 상한이 음수인 쌍(약세를 0 으로 막아도 강세 손실을 못 메우는 사이클)도 정직하게 포함한다.
bc_dc_strong_max <- function(phases_bm, uc_floor, window) {
  e <- as.data.table(phases_bm)[start_ym >= window[1] & end_ym <= window[2]][order(start_ym)]
  rows <- list()
  if (nrow(e) >= 2L) for (i in seq_len(nrow(e) - 1L)) {
    if (e$kind[i] != "bull" || e$kind[i + 1L] != "bear") next
    U <- e$bm_cum[i]; D <- -e$bm_cum[i + 1L]
    if (!is.finite(U) || !is.finite(D) || U <= 0 || D <= 0 || D >= 1) next
    d <- (1 - (1 + U) * (1 - D) / (1 + uc_floor * U)) / D
    rows[[length(rows) + 1L]] <- data.table(bull_start = e$start_ym[i], bear_end = e$end_ym[i + 1L],
                                            U = U, D = D, d_max = d)
  }
  P <- rbindlist(rows)
  list(value = if (nrow(P)) stats::median(P$d_max) else NA_real_, n_pairs = nrow(P), pairs = P)
}

.bc_beta <- function(s, k) {
  ok <- is.finite(s) & is.finite(k); s <- s[ok]; k <- k[ok]
  if (length(s) < 6L || stats::var(k) <= 0) return(NA_real_)
  unname(stats::coef(stats::lm.fit(cbind(1, k), s))[2])
}

.bc_cdar <- function(v, alpha) {
  nav <- cumprod(1 + v); dd <- 1 - nav / cummax(nav)
  k <- max(1L, as.integer(ceiling((1 - alpha) * length(dd))))
  mean(sort(dd, decreasing = TRUE)[seq_len(k)])
}

# 위기 표 · 강세 표 → 요약과 판정
# mdd_ratio = 같은 창 전략 MDD / 벤치 MDD — '강함'의 자기 낙폭 조건(GRADE-V3-S0-BANDS ④ · 도훈 수용 10-13).
#   위기 포착은 벤치 위기 구간 안만 본다. 시장이 멀쩡할 때 전략 혼자 무너진 낙폭은 거기 안 잡힌다
#   (S0 실측: MDD 80.5% · CAGR 0% 기저가 위기 구간 포착만으로 '강함'이었다).
.bc_verdict <- function(cr, bull, cfg, dc_strong, mdd_ratio = NA_real_) {
  n_cr <- if (is.null(cr)) 0L else nrow(cr); n_bull <- if (is.null(bull)) 0L else nrow(bull)
  out <- list(n_crisis = n_cr, n_bull = n_bull,
              crisis_cum_capture_median = if (n_cr) stats::median(cr$cum_capture) else NA_real_,
              crisis_dd_capture_median = if (n_cr) stats::median(cr$dd_capture) else NA_real_,
              crisis_dd_capture_worst = if (n_cr) max(cr$dd_capture) else NA_real_,
              bull_up_capture_median = if (n_bull) stats::median(bull$up_capture) else NA_real_,
              share_crisis_strong = if (n_cr) mean(cr$cum_capture <= dc_strong) else NA_real_,
              share_crisis_weak = if (n_cr) mean(cr$dd_capture >= cfg$weak_capture_floor) else NA_real_)
  out$asymmetry <- if (is.finite(out$bull_up_capture_median) && is.finite(out$crisis_dd_capture_median) &&
                       out$crisis_dd_capture_median > 0) out$bull_up_capture_median / out$crisis_dd_capture_median else NA_real_
  out$mdd_vs_bench <- mdd_ratio
  # '매번'은 정의상 둘 이상의 위기를 요구한다 — 하나로는 지속성을 판정할 수 없다
  out$verdict <- if (n_cr < 2L || !is.finite(dc_strong)) "insufficient"
    else if (out$share_crisis_weak > cfg$majority_share) "weak"
    else if (out$share_crisis_strong > cfg$majority_share &&
             is.finite(out$bull_up_capture_median) && out$bull_up_capture_median >= cfg$uc_floor &&
             out$crisis_dd_capture_worst < cfg$weak_capture_floor &&
             is.finite(mdd_ratio) && mdd_ratio <= cfg$strong_mdd_vs_bench_max) "strong"
    else "normal"
  out
}

#' 행동 카드
#' @param strat data.table(date, <ret_col>) 일간(권장) 또는 월간 전략 순수익
#' @param bm data.table(date, <bm_col>) 같은 기간 벤치 수익
#' @param bm_hist 연대기 · 위기 정의용 긴 벤치 이력(일간 권장 · 없으면 bm)
bc_card <- function(strat, bm, cfg = bc_cfg(), bm_hist = NULL,
                    ret_col = "ret_net", bm_col = "benchmark_ret", hist_col = bm_col,
                    strategy_id = NA_character_, root = NULL) {
  Sd <- .bc_series(strat, ret_col); Kd <- .bc_series(bm, bm_col)
  start <- as.Date(cfg$period_start); tau <- as.Date(cfg$tau_d)
  Sd <- Sd[date >= start]; Kd <- Kd[date >= start]
  Hd <- if (is.null(bm_hist)) .bc_series(bm, bm_col) else .bc_series(bm_hist, hist_col)

  # ── 월간(통계 · 강세 국면 · 롤링) ──
  S <- bc_monthly(Sd, "r"); K <- bc_monthly(Kd, "r")
  M <- merge(S[, .(ym, s = r)], K[, .(ym, k = r)], by = "ym")[order(ym)]
  if (nrow(M) < 24L) stop("[behavior_card] 겹치는 월이 24개 미만 — 카드를 낼 수 없다(n=", nrow(M), ")")
  Hm <- bc_monthly(Hd, "r")
  ph <- bc_phases(bc_regimes(Hm))
  ph[, bm_cum := vapply(seq_len(.N), function(i) {
    v <- Hm[ym >= start_ym[i] & ym <= end_ym[i]]$r
    if (length(v)) prod(1 + v) - 1 else NA_real_ }, numeric(1))]
  dcs <- bc_dc_strong_max(ph, cfg$uc_floor, cfg$dc_derive_window)

  tau_ym <- format(tau, "%Y-%m")
  bull_rows <- list()
  for (i in which(ph$kind == "bull")) {
    a <- ph$start_ym[i]; b <- ph$end_ym[i]
    if (b < M$ym[1] || a > M$ym[nrow(M)]) next                 # 표본 밖 국면은 조용히 건너뛴다
    W <- M[ym >= a & ym <= b]
    if (nrow(W) != ph$n_months[i]) next                         # 부분 겹침은 아래 excluded 에 남긴다
    ps <- .bc_path(W$s); pk <- .bc_path(W$k)
    bull_rows[[length(bull_rows) + 1L]] <- data.table(
      start_ym = a, end_ym = b, n_months = ph$n_months[i],
      window = if (b <= tau_ym) "visible" else if (a > tau_ym) "test" else "straddle",
      bm_cum = pk$cum, st_cum = ps$cum, up_capture = if (pk$cum > 0) ps$cum / pk$cum else NA_real_)
  }
  BU <- rbindlist(bull_rows)
  if (nrow(BU)) BU <- BU[is.finite(up_capture)]

  # ── 위기(일간 낙폭 구간) ──
  daily <- .bc_is_daily(Sd) && .bc_is_daily(Hd)
  J <- if (daily) merge(Sd[, .(date, s = r)], Kd[, .(date, k = r)], by = "date")[order(date)]
       else M[, .(date = as.Date(paste0(ym, "-28")), s, k)]
  Hc <- if (daily) Hd else Hm[, .(date = as.Date(paste0(ym, "-28")), r)]
  crises <- .bc_crises_by_cfg(Hc, cfg)
  cr_rows <- list(); excluded <- list()
  for (i in seq_len(nrow(crises))) {
    p0 <- crises$peak_date[i]; t0 <- crises$trough_date[i]
    if (t0 < J$date[1] || p0 > J$date[nrow(J)]) next            # 표본 밖 위기
    W <- J[date > p0 & date <= t0]
    covered <- p0 >= J$date[1] && nrow(W) > 0L
    if (!covered) {
      excluded[[length(excluded) + 1L]] <- list(peak = format(p0), trough = format(t0),
                                                reason = "strategy_data_starts_inside_crisis")
      next
    }
    ps <- .bc_path(W$s); pk <- .bc_path(W$k)
    after <- J[date > p0]
    rs <- .bc_recovery(after$s); rk <- .bc_recovery(after$k)
    cr_rows[[length(cr_rows) + 1L]] <- data.table(
      peak_date = p0, trough_date = t0, ongoing = crises$ongoing[i],
      window = if (t0 <= tau) "visible" else if (p0 > tau) "test" else "straddle",
      bm_depth_hist = crises$depth[i], bm_cum = pk$cum, st_cum = ps$cum, bm_dd = pk$dd, st_dd = ps$dd,
      cum_capture = if (pk$cum != 0) ps$cum / pk$cum else NA_real_,
      dd_capture = if (pk$dd > 0) ps$dd / pk$dd else NA_real_,
      st_recovery_obs = rs$n, st_recovery_censored = rs$censored,
      bm_recovery_obs = rk$n, bm_recovery_censored = rk$censored)
  }
  CR <- rbindlist(cr_rows)
  if (nrow(CR)) CR <- CR[is.finite(cum_capture) & is.finite(dd_capture)]

  # ── 자기 낙폭(같은 창 전략 MDD / 벤치 MDD) — 위기 포착과 같은 해상도(J)로, 판정 창마다 ──
  mdd_ratio <- function(W) {
    if (nrow(W) < 2L) return(NA_real_)
    ps <- .bc_path(W$s); pk <- .bc_path(W$k)
    if (pk$dd > 0) ps$dd / pk$dd else NA_real_
  }
  MR <- list(overall = mdd_ratio(J), visible = mdd_ratio(J[date <= tau]), test = mdd_ratio(J[date > tau]))

  # ── 통계 ──
  nav <- cumprod(1 + M$s); mdd <- max(1 - nav / cummax(nav))
  cagr <- prod(1 + M$s)^(12 / nrow(M)) - 1
  bdn <- M[k < 0]; bup <- M[k > 0]
  roll <- tryCatch({
    if (!exists("rg_rolling", mode = "function"))
      suppressMessages(source(file.path(.bc_root(root), "02_Infrastructure/contracts/rolling_grade.R"), local = TRUE))
    rr <- rg_rolling(data.table(date = as.Date(paste0(M$ym, "-28")), ret_net = M$s),
                     data.table(date = as.Date(paste0(M$ym, "-28")), benchmark_ret = M$k))
    list(status = rr$status, pass_life = rr$pass_life, pass_recent = rr$pass_recent,
         window_months = rr$window_months)
  }, error = function(e) list(status = paste("error:", conditionMessage(e))))

  sub <- function(w) .bc_verdict(if (nrow(CR)) CR[window == w] else CR,
                                 if (nrow(BU)) BU[window == w] else BU, cfg, dcs$value, MR[[w]])
  list(
    schema = "behavior_card_v1", strategy_id = strategy_id,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    period = c(M$ym[1], M$ym[nrow(M)]), n_months = nrow(M), crisis_resolution = if (daily) "daily" else "monthly",
    cfg = list(tau_d = cfg$tau_d, uc_floor = cfg$uc_floor, majority_share = cfg$majority_share,
               weak_capture_floor = cfg$weak_capture_floor, cdar_alpha = cfg$cdar_alpha,
               crisis_depth = cfg$crisis_depth, strong_mdd_vs_bench_max = cfg$strong_mdd_vs_bench_max,
               crisis_episode_def = .bc_or(cfg[["crisis_episode_def"]], "running_peak_drawdown"),
               crisis_lambda_down = .bc_or(cfg[["crisis_lambda_down"]], NA_real_), crisis_lambda_up = .bc_or(cfg[["crisis_lambda_up"]], NA_real_)),
    dc_strong_max = dcs$value, dc_strong_pairs = dcs$n_pairs, dc_strong_table = dcs$pairs,
    overall = .bc_verdict(CR, BU, cfg, dcs$value, MR$overall),
    visible = sub("visible"),
    test = sub("test"),
    crises = CR, bull_phases = BU, excluded = excluded,
    stats = list(cagr = cagr, mdd = mdd, calmar = if (mdd > 1e-9) cagr / mdd else NA_real_,
                 cdar = .bc_cdar(M$s, cfg$cdar_alpha),
                 beta = .bc_beta(M$s, M$k),
                 beta_down = if (nrow(bdn) >= 6L) .bc_beta(bdn$s, bdn$k) else NA_real_,
                 beta_up = if (nrow(bup) >= 6L) .bc_beta(bup$s, bup$k) else NA_real_),
    rolling = roll,
    controls = list(status = "not_provided",
                    note = "크기 짝 · 노출 짝 대조 수익이 없다 — 방어가 실력인지 크기 · 노출 효과인지 미판정")
  )
}

#' 크기 짝 · 노출 짝 대조 붙이기 — 대조 수익(같은 평균 노출 · 같은 크기 분포의 무신호 포트폴리오)을 받아
#' 위기마다 전략과 대조의 낙폭 포착률을 비교한다. 대조 생성기 = matched_controls.R(MC8 · 보유 기록 필요).
#' controls = list(size_matched = data.table(date, ret), exposure_matched = data.table(date, ret)) — 하나만 와도 된다
#' 대조별 label 은 '그 대조를 과반 위기에서 넘었나'다. 여러 대조의 귀속 판정(선택 · 크기 · 노출 방어)은
#'   matched_controls.R::mc_attribution 의 controls$attribution 이 정본이다.
#' tol = 부동소수 동치 여유(결정 수치 아님 · 기본 0 = 엄격 비교) — 같은 경로를 다른 산술 순서로 잰 낙폭의 1e-15 차이를 '넘음'으로 세지 않게
bc_attach_controls <- function(card, controls, bm, bm_col = "benchmark_ret", ctrl_col = "ret", tol = 0) {
  if (is.null(controls) || !length(controls)) return(card)
  CR <- card$crises
  if (is.null(CR) || !nrow(CR)) { card$controls <- list(status = "no_crises"); return(card) }
  K <- .bc_series(bm, bm_col)
  res <- list(status = "ok")
  for (nm in names(controls)) {
    C <- .bc_series(controls[[nm]], ctrl_col)
    J <- merge(C[, .(date, c = r)], K[, .(date, k = r)], by = "date")[order(date)]
    per <- rbindlist(lapply(seq_len(nrow(CR)), function(i) {
      W <- J[date > CR$peak_date[i] & date <= CR$trough_date[i]]
      if (!nrow(W)) return(NULL)
      pc <- .bc_path(W$c); pk <- .bc_path(W$k)
      data.table(peak_date = CR$peak_date[i], window = CR$window[i],
                 strategy_dd_capture = CR$dd_capture[i],
                 control_dd_capture = if (pk$dd > 0) pc$dd / pk$dd else NA_real_)
    }))
    if (!nrow(per)) { res[[nm]] <- list(status = "control_not_covering"); next }
    per[, beats_control := strategy_dd_capture < control_dd_capture - tol]
    sb <- mean(per$beats_control, na.rm = TRUE)
    res[[nm]] <- list(status = "ok", per_crisis = per, share_beats = sb,
                      median_gap = stats::median(per$control_dd_capture - per$strategy_dd_capture, na.rm = TRUE),
                      label = if (sb > card$cfg$majority_share) "selection_defense" else "size_or_exposure_defense")
  }
  card$controls <- res
  card
}

#' 측정 산출물 디렉터리(run_paper_replication)에서 바로 카드 — 연대기 · 위기는 긴 벤치 이력(.cache/benchmark.parquet)
bc_card_from_artifacts <- function(art_dir, root = NULL, cfg = bc_cfg(root)) {
  pr <- fread(file.path(art_dir, "03_period_returns.csv"))
  br <- fread(file.path(art_dir, "05_benchmark_returns.csv"))
  hist <- NULL
  bp <- file.path(.bc_root(root), ".cache/benchmark.parquet")
  if (file.exists(bp) && requireNamespace("arrow", quietly = TRUE)) {
    h <- as.data.table(arrow::read_parquet(bp))
    if (all(c("Date", "BM_Ret") %in% names(h))) hist <- h[, .(date = as.Date(Date), benchmark_ret = BM_Ret)]
  }
  sid <- tryCatch(as.character(pr$strategy_id[1]), error = function(e) NA_character_)
  bc_card(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], cfg = cfg, bm_hist = hist,
          strategy_id = sid, root = root)
}

#' 카드 저장 — behavior_card.json (원자적 쓰기: 임시 파일 → 이름 바꾸기)
bc_write <- function(card, out_dir, name = "behavior_card.json") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  p <- file.path(out_dir, name); tmp <- paste0(p, ".tmp")
  writeLines(toJSON(card, auto_unbox = TRUE, digits = NA, null = "null", na = "null", pretty = TRUE,
                    Date = "ISO8601"), tmp, useBytes = TRUE)
  file.rename(tmp, p)
  invisible(p)
}
