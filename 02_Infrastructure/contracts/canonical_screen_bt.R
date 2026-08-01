# canonical_screen_bt.R — Qvest v8.x WS1 (Real-Computation, 하이브리드 C)
#
# 목적: alpha/risk 단계가 portfolio-alpha t / SR 등 성능수치를 **proxy 손계산**
#       (top-quintile EW + turnover×15bps 인라인 근사)으로 보고하던 것을 폐기하고,
#       표준 canonical 포트폴리오를 **contract 경유 실측**으로 산출하게 하는 공용 helper.
#
# 설계:
#   - 표준 top-N EW **long-only** + 유동성필터(2e8) + 실 15bps 비용.
#   - period 수익률을 contract `build_benchmark_compare()`로 routing → portfolio_alpha_t_nw_lag3
#     (NW lag-3) + IR + alpha를 **contract-grade**로 산출 (forge와 동일 함수, 일관성).
#   - metric_type = "canonical_screen" — forge build_bt_result(="backtested", 최적화 weights)도,
#     proxy도 아님. **admission binding 수치 아님**(그건 forge). screening/직교 측정용 실측.
#
# 비용 규약 (FLOW/optimizer 정합, double-count 금지):
#   traded_t = sum(|w_t - w_{t-1}|)            # 월별 매매 notional(매수+매도)
#   cost_t   = traded_t * cost_bps/1e4         # one-way 15bps를 traded 단위마다 1회
#   turnover_annual(보고) = mean(traded_t) * 12
#
# PIT: scores_dt는 sig_date 기준(t에 알 수 있는 값), returns_dt의 Ret_1m은 forward 실현수익.
#      유동성필터는 t-1 ADV(C10). 호출자가 PIT-aligned 입력 보장 의무.
#
# [2026-07-10 additive — v8.3 M2 dual-basis 진단. 판정 권위 경계]
#   ★ HARD 게이트(PORT_t 2.95 / oos_retention / calmar)의 basis는 **기존 cap-w 벤치(bench_dt) 단일 권위 — 불변**.
#   신규 필드 diag_ew_universe / diag_cap_tier는 **진단 병기 전용**(metric_type="canonical_screen_diag",
#   게이트/판정/admission 비바인딩). 기존 필드·값 불변(bit-parity 실증) + 기본값 TRUE로 진단 2필드
#   append(호출당 진단 연산 추가 — 성능 민감 루프는 diag_dual_basis=FALSE 권장).
#   근거(실측): post-2017 "알파 감쇠"의 상당분 = cap-weighted mega-cap 벤치 아티팩트
#   (동일 알파가 EW-유니버스 벤치 대비 생존: post2017_t 0.41→2.04, oos −0.02→0.57 사례) +
#   cap-tier 국소화(MID tier 11-30위 LS t=3.02 生 / MEGA top-10 t=0.59 死).
#   → 진짜 알파를 벤치 구성 미스매치로 기각하는 오판을 막기 위한 병기 진단.

suppressMessages({
  library(data.table)
})

# contract 재사용 (build_benchmark_compare + .nw_t_mean)
.CANON_DIR <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "02_Infrastructure/contracts")
local({
  f <- file.path(.CANON_DIR, "backtest_result_contract.R")
  if (file.exists(f)) suppressMessages(source(f))
})

# ── [additive 2026-07-10] 진단 헬퍼 (비바인딩 — 상단 경계 주석 참조) ─────────────

# NW lag-3 t 재사용 wrapper — backtest_result_contract.R::.nw_t_mean(기존과 동일 함수 경로)만 사용.
# 계약 미로드 시 자체 재구현 대신 NA 반환(자체합성 금지 정합).
.canon_nw_t <- function(x, lag = 3L) {
  if (!exists(".nw_t_mean", mode = "function")) return(NA_real_)
  .nw_t_mean(x, lag = lag)
}

# oos retention 대략치 — anchored 3분할 {55/65/75%} 중앙값(essence_score oos_stat_version="v2"의
# active-SR 비율 개념을 따른 *진단용 근사*. 게이트 권위 아님 — 권위는 essence_score.R).
.canon_oos_rough <- function(active, frac = c(0.55, 0.65, 0.75), ppy = 12L) {
  n <- length(active)
  if (n < 24L) return(NA_real_)
  sr1 <- function(x) {
    if (length(x) < 6L) return(NA_real_)
    s <- stats::sd(x)
    if (!is.finite(s) || s <= 0) return(NA_real_)
    mean(x) / s * sqrt(ppy)
  }
  r <- vapply(frac, function(f) {
    k <- floor(n * f)
    if (k < 6L || (n - k) < 6L) return(NA_real_)
    is_sr <- sr1(active[1:k]); oos_sr <- sr1(active[(k + 1):n])
    if (is.na(is_sr) || is.na(oos_sr) || is_sr <= 0) return(NA_real_)
    oos_sr / is_sr
  }, numeric(1))
  if (all(is.na(r))) NA_real_ else stats::median(r, na.rm = TRUE)
}

# diag_ew_universe — 동일 패널의 유동성필터 前 유니버스 동일가중(EW) 벤치 대비 net active 진단.
# PORT_t는 기존과 동일 경로(build_benchmark_compare → Portfolio_Alpha_t_NW_lag3).
.canon_diag_ew_universe <- function(univ_prefilter, returns_R, pr,
                                    run_id, strategy_id, periods_per_year) {
  ewb <- merge(univ_prefilter, returns_R[, .(Date, Ticker, Ret_1m)], by = c("Date", "Ticker"))
  if (nrow(ewb) == 0) {
    return(list(metric_type = "canonical_screen_diag", n_months = 0L,
                note = "no EW-universe return overlap"))
  }
  ewb <- ewb[, .(ew_bench_ret = mean(Ret_1m)), by = Date]   # 결측수익 종목은 그 달 EW평균에서 제외
  pe <- merge(pr[, .(date, ret_net)], ewb[, .(date = Date, ew_bench_ret)], by = "date")
  if (nrow(pe) == 0) {
    return(list(metric_type = "canonical_screen_diag", n_months = 0L,
                note = "no EW-universe overlap"))
  }
  period_returns_tbl <- data.table(date = pe$date, ret_net = pe$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pe$date, benchmark_ret = pe$ew_bench_ret,
                                      benchmark_id = "EW_universe_prefilter")
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                run_id = paste0(run_id, "_diagEW"), strategy_id = strategy_id,
                                annualization_factor = periods_per_year)
  getbc <- function(nm) {
    v <- bc[metric_name == nm, active_value]
    if (length(v) == 0) NA_real_ else as.numeric(v[1])
  }
  active_ew <- pe$ret_net - pe$ew_bench_ret
  p17 <- pe$date >= as.Date("2017-01-01")
  sd_a <- stats::sd(active_ew)
  list(
    metric_type = "canonical_screen_diag",
    metric_type_note = "EW-유니버스(해당월 유동성필터 前 패널 동일가중) 벤치 대비 진단. HARD 게이트 비바인딩 — cap-w basis(bench_dt)가 판정 권위. 결측수익 종목은 그 달 EW 벤치에서 제외 — 본판정 0-fill과 비대칭, 진단에 보수(하방) 방향.",
    benchmark_id = "EW_universe_prefilter",
    n_months = nrow(pe),
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized  = getbc("Alpha_Annualized"),
    net_sr = if (is.finite(sd_a) && sd_a > 0) mean(active_ew) / sd_a * sqrt(periods_per_year) else NA_real_,
    oos_retention_approx = .canon_oos_rough(active_ew, ppy = periods_per_year),
    oos_retention_approx_note = "anchored 3분할{55/65/75} 중앙값 근사 — 게이트 권위는 essence_score.R",
    post2017_t_nw_lag3 = .canon_nw_t(active_ew[p17]),
    n_months_post2017 = sum(p17),
    benchmark_compare = bc,
    period_returns = data.table(date = pe$date, ret_net = pe$ret_net,
                                ew_bench_ret = pe$ew_bench_ret, active_ew = active_ew)
  )
}

# diag_cap_tier — 시총(size_dt) 월별 랭킹으로 포트 보유를 MEGA(top-10)/MID(11-30)/OTHER 분해.
# size_dt는 호출자 제공(선택). 미제공 시 available=FALSE + 사유만 반환(억지 산출 금지).
# ⚠ 랭킹은 size_dt 패널 *내* 상대랭킹 — 유니버스 전체 시총 패널 전달 권장(보유종목만 넘기면 보유 내 랭킹이 됨).
.canon_diag_cap_tier <- function(WR, size_dt, periods_per_year) {
  if (is.null(size_dt)) {
    return(list(available = FALSE, metric_type = "canonical_screen_diag",
                note = "size_dt 미제공 — canonical_screen_bt 기본 입력(scores/returns/bench)에는 시총이 없음. size_dt(Date,Ticker,Size)를 넘기면 산출."))
  }
  Z <- as.data.table(size_dt)
  need <- c("Date", "Ticker", "Size")
  if (!all(need %in% names(Z))) {
    return(list(available = FALSE, metric_type = "canonical_screen_diag",
                note = paste0("size_dt 컬럼 요건 미충족(필요: Date,Ticker,Size / 실제: ",
                              paste(names(Z), collapse = ","), ")")))
  }
  Z <- Z[!is.na(Size), .(Date, Ticker, Size)]
  if (nrow(Z) == 0) {
    return(list(available = FALSE, metric_type = "canonical_screen_diag",
                note = "size_dt 전행 Size 결측"))
  }
  setorder(Z, Date, -Size)
  Z[, cap_rank := seq_len(.N), by = Date]
  Z[, tier := fifelse(cap_rank <= 10L, "MEGA", fifelse(cap_rank <= 30L, "MID", "OTHER"))]
  HT <- merge(WR, Z[, .(Date, Ticker, tier)], by = c("Date", "Ticker"), all.x = TRUE)
  HT[is.na(tier), tier := "UNRANKED"]
  comp <- HT[, .(weight_share = sum(w), contrib_gross = sum(w * Ret_1m)), by = .(Date, tier)]
  tiers <- c("MEGA", "MID", "OTHER", "UNRANKED")
  wshare <- dcast(comp, Date ~ tier, value.var = "weight_share", fill = 0)
  cgross <- dcast(comp, Date ~ tier, value.var = "contrib_gross", fill = 0)
  tier_mean <- function(dc) {
    out <- lapply(tiers, function(tt) if (tt %in% names(dc)) mean(dc[[tt]]) else 0)
    names(out) <- tiers
    out
  }
  w_avg <- tier_mean(wshare)
  c_avg <- tier_mean(cgross)
  list(
    available = TRUE,
    metric_type = "canonical_screen_diag",
    metric_type_note = "포트 보유의 시총-tier 분해 진단(size_dt 패널 내 월별 Size 내림차순 랭킹). HARD 게이트 비바인딩.",
    tier_def = "MEGA = cap rank 1-10 / MID = 11-30 / OTHER = 31+ / UNRANKED = size_dt에 없음",
    n_months = length(unique(HT$Date)),
    weight_share_avg = w_avg,                 # tier별 평균 보유비중 (합 ≈ 1)
    contrib_gross_monthly_avg = c_avg,        # tier별 월평균 gross 기여 (tier 합 = 포트 gross 월평균)
    contrib_gross_annualized = lapply(c_avg, function(v) v * periods_per_year),
    by_month = comp                           # (Date, tier, weight_share, contrib_gross)
  )
}

#' Canonical screening backtest — top-N EW long-only, contract-grade.
#' @param scores_dt  data.table(Date, Ticker, score)  higher score = 선호
#' @param returns_dt data.table(Date, Ticker, Ret_1m) forward 1M 실현수익(PIT-aligned)
#' @param bench_dt   data.table(Date, BM_Ret)
#' @param top_n      integer (default 20; max 25 mandate 내)
#' @param cost_bps_oneway numeric one-way bps (default 15)
#' @param liq_dt     optional data.table(Date, Ticker, adv) — 20d 평균 거래대금(t-1)
#' @param liq_min    numeric (default 2e8)
#' @param diag_dual_basis logical (default TRUE) — [2026-07-10 additive] TRUE면 진단 전용 필드
#'                    diag_ew_universe / diag_cap_tier를 리스트 *끝에 append만* 함(기존 필드·값 불변).
#'                    FALSE면 기존 반환 형태 그대로.
#' @param size_dt    optional data.table(Date, Ticker, Size) — 시총 패널(유니버스 전체 권장).
#'                    diag_cap_tier 산출에만 사용. NULL(기본)이면 diag_cap_tier$available=FALSE.
#' @return list(metric_type, n_months, portfolio_alpha_t_nw_lag3, portfolio_alpha_t_pvalue,
#'              information_ratio, alpha_annualized, net_sr, mean_active_net, turnover_annual,
#'              benchmark_compare, note)
#'         + [diag_dual_basis=TRUE 시 append] diag_ew_universe, diag_cap_tier
#'           (metric_type="canonical_screen_diag" — 판정/게이트 비바인딩 병기 진단)
canonical_screen_bt <- function(scores_dt, returns_dt, bench_dt,
                                 top_n = 20L, cost_bps_oneway = 15,
                                 liq_dt = NULL, liq_min = 2e8,
                                 run_id = "canonical_screen", strategy_id = "canonical_screen",
                                 periods_per_year = 12L,
                                 diag_dual_basis = TRUE, size_dt = NULL,
                                 ast_features = NULL) {
  # ast_features: [2026-08-02 additive] ast_compile manifest 구조특징 list.
  #   판정에 일절 관여하지 않는다 — Step 4 사이드카 기록 전용(NULL = 비-AST 표식).
  # periods_per_year: 리밸/마킹 빈도 (월간=12 기본. 분기 리밸·분기수익 측정=4).
  #   3개월-horizon 신호를 분기 리밸 sleeve로 운용 시 4가 자연 cadence — 월간 마킹 강제 아님.
  stopifnot(all(c("Date","Ticker","score") %in% names(scores_dt)))
  stopifnot(all(c("Date","Ticker","Ret_1m") %in% names(returns_dt)))
  stopifnot(all(c("Date","BM_Ret") %in% names(bench_dt)))

  S <- as.data.table(scores_dt)[!is.na(score)]
  R <- as.data.table(returns_dt)[!is.na(Ret_1m)]

  # ── [R44 2026-07-15, WT-D20260715_013] Ret_1m sanity assert (입력단 이중 방어) ──
  #   1차 방화벽 = rawdata_sanitize Step5(일간 Ret). 여기선 monthly forward return의 물리불가
  #   잔존만 backstop: Ret_1m > +500%(월간 상한 초월) 또는 < -100%(손실>100% 물리 불가능).
  #   clean 유니버스 월 |fwd| 최대 ~2.47(R43 census) ≪ 5.0 → 미발화·known-case parity 보장.
  #   assert-only(warn+NA·본판정 비중단) — sanitize 미적용 vintage 소비 시 소비면 보호.
  bad_1m <- is.finite(R$Ret_1m) & (R$Ret_1m > 5.0 | R$Ret_1m < -1.0)
  if (any(bad_1m)) {
    warning(sprintf("[canonical_screen_bt] Ret_1m sanity 방화벽: %d 물리불가 월수익 격리(Ret_1m>5.0 or <-1.0) — rawdata_sanitize 방화벽 미적용 vintage 의심.", sum(bad_1m)))
    R <- R[!bad_1m]
  }
  # [additive 2026-07-10] 유동성필터 前 패널 유니버스 스냅샷 — diag_ew_universe(EW 벤치)용.
  univ_prefilter <- if (isTRUE(diag_dual_basis)) unique(S[, .(Date, Ticker)]) else NULL
  if (!is.null(liq_dt)) {
    L <- as.data.table(liq_dt)
    S <- merge(S, L[, .(Date, Ticker, adv)], by = c("Date","Ticker"), all.x = TRUE)
    S <- S[is.na(adv) | adv >= liq_min]   # 유동성필터(adv 없으면 통과 — 호출자 책임)
    S[, adv := NULL]
  }

  # per-Date: top_n EW long-only weights
  setorder(S, Date, -score)
  W <- S[, {
    n <- min(top_n, .N)
    .(Ticker = Ticker[seq_len(n)], w = rep(1 / n, n))
  }, by = Date]

  # gross monthly port return = sum(w_t * Ret_1m_t)
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"), all.x = TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross = sum(w * Ret_1m)), by = Date]

  # turnover: traded_t = sum(|w_t - w_{t-1}|)  (ticker union)
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  prev <- data.table(Ticker = character(0), w = numeric(0))
  for (i in seq_along(dts)) {
    cur <- W[Date == dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by = "Ticker", all = TRUE, suffixes = c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * cost_bps_oneway / 1e4]
  port[, ret_net := port_gross - cost]

  # benchmark merge → period_returns_tbl + benchmark_returns_tbl (contract 형식)
  pr <- merge(port[, .(date = Date, ret_net)], bench_dt[, .(date = Date, benchmark_ret = BM_Ret)],
              by = "date")
  if (nrow(pr) == 0) {
    return(list(metric_type = "canonical_screen", n_months = 0L,
                portfolio_alpha_t_nw_lag3 = NA_real_, note = "no overlap"))
  }
  period_returns_tbl <- data.table(date = pr$date, ret_net = pr$ret_net, frequency = "monthly")
  benchmark_returns_tbl <- data.table(date = pr$date, benchmark_ret = pr$benchmark_ret,
                                       benchmark_id = "KOSPI200_total_return")

  # contract-grade: build_benchmark_compare (= forge와 동일 함수, NW t 포함)
  bc <- build_benchmark_compare(period_returns_tbl, benchmark_returns_tbl,
                                 run_id = run_id, strategy_id = strategy_id,
                                 annualization_factor = periods_per_year)
  getbc <- function(nm) {
    v <- bc[metric_name == nm, active_value]
    if (length(v) == 0) NA_real_ else as.numeric(v[1])
  }
  active <- pr$ret_net - pr$benchmark_ret
  net_sr <- mean(active) / stats::sd(active) * sqrt(periods_per_year)
  turnover_annual <- mean(port$traded, na.rm = TRUE) * periods_per_year

  out <- list(
    metric_type = "canonical_screen",
    metric_type_note = "표준 top-N EW long-only 실측(contract build_benchmark_compare 경유). admission binding 아님 — forge build_bt_result가 authoritative.",
    n_months = nrow(pr),
    top_n = top_n,
    portfolio_alpha_t_nw_lag3 = getbc("Portfolio_Alpha_t_NW_lag3"),
    portfolio_alpha_t_pvalue  = getbc("Portfolio_Alpha_t_pvalue"),
    information_ratio = getbc("Information_Ratio"),
    alpha_annualized  = getbc("Alpha_Annualized"),
    net_sr = net_sr,
    mean_active_net = mean(active),
    turnover_annual = turnover_annual,
    benchmark_compare = bc,
    period_returns = pr   # [2026-06-18 additive] 월별 시계열(date·ret_net·benchmark_ret) — 오버레이 등 후처리용
  )

  # ── [additive 2026-07-10] dual-basis 진단 append (기존 필드·값 불변, 실패해도 본판정 불변) ──
  if (isTRUE(diag_dual_basis)) {
    out$diag_ew_universe <- tryCatch(
      .canon_diag_ew_universe(univ_prefilter, R, pr, run_id, strategy_id, periods_per_year),
      error = function(e) list(metric_type = "canonical_screen_diag",
                               error = paste0("diag_ew_universe failed: ", conditionMessage(e))))
    out$diag_cap_tier <- tryCatch(
      .canon_diag_cap_tier(WR, size_dt, periods_per_year),
      error = function(e) list(available = FALSE, metric_type = "canonical_screen_diag",
                               error = paste0("diag_cap_tier failed: ", conditionMessage(e))))
  }

  # ── [2026-08-02 신규] AST v1.1 Step 4 사이드카 — screening lane 배선 ────────
  #  왜 여기인가: essence_score() 는 run_alpha_search.R:330 권위측정 사다리
  #  (grade A/B 또는 screen_pass) 를 통과한 소수만 경유한다 — 실측으로 확인된
  #  생존편향 구조. SOT §5 가 명문 요구한 "거절분 포함 전량 로깅"을 만족하려면
  #  **기각분이 반드시 지나는** 스크리닝 판정 지점에서 잡아야 한다.
  #  판정 무관여·fail-soft·append-only (본 함수 반환값 불변).
  try({
    if (!exists("ast_sidecar_log", mode = "function")) {
      .cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                  Sys.getenv("QM_ROOT", unset = ""), getwd())
      for (.c0 in .cands) {
        if (!nzchar(.c0)) next
        .c0 <- gsub("\\\\", "/", .c0)
        if (!(file.exists(file.path(.c0, "CLAUDE.md")) &&
              dir.exists(file.path(.c0, "06_Registry")))) next
        .sc <- file.path(.c0, "02_Infrastructure", "contracts", "ast_sidecar.R")
        if (file.exists(.sc)) { source(.sc); break }
      }
    }
    if (exists("ast_sidecar_log", mode = "function")) {
      .ew <- out$diag_ew_universe
      ast_sidecar_log(
        lane = "canonical_screen",
        strategy_id = strategy_id,
        ast_features = ast_features,          # 호출자가 AST manifest 를 주면 기록, 아니면 NULL 표식
        metrics = list(
          metric_type = "canonical_screen",
          port_t = out$portfolio_alpha_t_nw_lag3,
          net_ir = out$information_ratio,
          net_sr = out$net_sr,
          alpha_annualized = out$alpha_annualized,
          turnover_annual = out$turnover_annual
        ),
        extra = list(
          run_id = run_id, n_months = out$n_months, top_n = top_n,
          cost_bps_oneway = cost_bps_oneway,
          # dual-basis: cap-w 판정 옆에 EW-유니버스 대비를 같이 남긴다(v8.3 기각 전 확인 의무)
          diag_ew_port_t = if (is.list(.ew)) .ew$portfolio_alpha_t_nw_lag3 else NULL,
          diag_cap_tier_available = isTRUE(out$diag_cap_tier$available)
        )
      )
    }
  }, silent = TRUE)

  out
}

cat("[canonical_screen_bt.R] Loaded — canonical_screen_bt() (v8.x WS1 real-computation helper)\n")
