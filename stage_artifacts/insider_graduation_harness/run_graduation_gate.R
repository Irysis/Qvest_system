# run_graduation_gate.R — DART 임원 순매수 졸업-테스트 게이트 (canonical, contract-grade)
# =============================================================================
# 입력: stage_artifacts/insider_graduation_harness/data/officer_netbuy_panel.parquet
#         (Date=usable month-begin, Ticker, krw, nflow, ...) — build_officer_netbuy_signal.py 산출.
#       PIT: Date 는 홀딩월(=usable month) 시작. score(Date) → 그 usable 월의 실현수익에 적용.
#
# 절차:
#   1) RAWDATA(daily) → 월별 종목수익(Ret_1m, 홀딩월 실현) + 벤치(K200 total-ret proxy=BM_Ret 월누적)
#      + 유동성(20d ADV, t-1) + 유니버스(K200∪KQ150).
#   2) 신호 score = krw / nflow 두 변형. Date(=usable month begin) 정렬 →
#      canonical_screen_bt: top-25 EW long-only, 15bps v2.4 delta, LIQ 2e8, NW lag-3.
#   3) 시대별(pre-gap contiguous 2015-16 / recent 2024 / 결합-all) 실측.
#   4) 졸업 HARD 3종: PORT_t>=2.95 · oos_retention>=0.7(v2 3분할 중앙값) · calmar>=0.64
#      + book-marginal ΔIR vs incumbent(net_active_recon_v1 IR=1.416).
#   5) 커버리지 게이팅: 최장 contiguous run < 60월 → INTERIM_NONAUTHORITATIVE.
#
# 규율: real-computation only(canonical_screen_bt 경유). rank-IC≠PORT_t 둘 다 보고.
#       Σ/weight 산출 없음(alpha 경계). 자체합성 백테 없음.
# =============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
HARN <- file.path(ROOT, "stage_artifacts", "insider_graduation_harness")
source(file.path(ROOT, "02_Infrastructure", "contracts", "canonical_screen_bt.R"))

MIN_CONTIG <- as.integer(Sys.getenv("MIN_CONTIG_MONTHS", "60"))
INCUMBENT_IR <- 1.416   # book_state.json incumbent_book_ir (net_active_recon_v1)

# ── 1) 신호 패널 ─────────────────────────────────────────────────────────────
panel <- as.data.table(read_parquet(file.path(HARN, "data", "officer_netbuy_panel.parquet")))
panel[, Date := as.Date(Date)]                 # usable-month begin
panel[, hold_ym := format(Date, "%Y-%m")]      # 홀딩월(=usable month)

# ── 2) RAWDATA → 월별 수익/벤치/유동성/유니버스 ──────────────────────────────
rd <- as.data.table(read_parquet(file.path(ROOT, ".cache", "RAWDATA.parquet"),
                                 col_select = c("Date","Ticker","Ret","BM_Ret","Close","Vol","K200","KQ150")))
rd[, Date := as.Date(Date)]
rd[, ym := format(Date, "%Y-%m")]
setorder(rd, Ticker, Date)

# 월별 종목수익 = (1+일수익) 누적 - 1 (표준 compounding; PerformanceAnalytics 계열과 정합)
rd[, lr := log1p(pmax(Ret, -0.99))]
mret <- rd[, .(mret = expm1(sum(lr, na.rm = TRUE)),
               K200 = as.integer(any(K200 > 0, na.rm = TRUE)),
               KQ150 = as.integer(any(KQ150 > 0, na.rm = TRUE)),
               close_me = last(Close)),
           by = .(Ticker, ym)]
mret[, univ := (K200 == 1) | (KQ150 == 1)]

# 벤치: BM_Ret 은 일별 index return(종목 무관 동일) → 날짜별 1행으로 월누적
bench_d <- unique(rd[, .(Date, ym, BM_Ret)])
bench_m <- bench_d[, .(BM_Ret = expm1(sum(log1p(pmax(BM_Ret, -0.99)), na.rm = TRUE))), by = ym]

# 유동성: 20일 평균 거래대금(t-1). ADV_daily = Close*Vol. 월말 시점의 trailing-20d 평균을
#         '그 달' 리밸에 쓰되, 홀딩월 시작 전(=직전월말) 값이어야 PIT(C10). 여기서는
#         홀딩월 hold_ym 의 유동성필터를 '직전월말 20d ADV'로 근사 (t-1).
rd[, adv_daily := Close * Vol]
rd[, adv20 := frollmean(adv_daily, 20, align = "right"), by = Ticker]
adv_me <- rd[, .(adv20_me = last(adv20)), by = .(Ticker, ym)]   # 월말 trailing-20d ADV

# returns_dt: Date = 홀딩월 begin (신호 Date와 정렬), Ret_1m = 그 홀딩월 실현수익
ym_begin <- function(ym) as.Date(paste0(ym, "-01"))
returns_dt <- mret[univ == TRUE, .(Date = ym_begin(ym), Ticker, Ret_1m = mret, hold_ym = ym)]

# liq_dt: 홀딩월 begin 기준, adv = 직전월말(=holding 직전월) trailing-20d ADV (t-1 PIT)
prev_ym <- function(ym) format(ym_begin(ym) - 1, "%Y-%m")   # first-of-month minus 1 day => prev month
adv_me[, hold_ym := format(ym_begin(ym) %m+% months(1), "%Y-%m")]  # this month's ADV usable next month
# (need lubridate for %m+%) — avoid dependency: compute via seq
adv_me[, hold_ym := {
  d <- ym_begin(ym); nd <- as.Date(format(d, "%Y-%m-01")); # first of ADV month
  format(seq(nd, by = "month", length.out = 2)[2], "%Y-%m")  # next month
}, by = ym]
liq_dt <- adv_me[, .(Date = ym_begin(hold_ym), Ticker, adv = adv20_me)]

bench_dt <- bench_m[, .(Date = ym_begin(ym), BM_Ret)]

# ── 3) canonical screen 실행 (시대별 + 변형별) ───────────────────────────────
run_screen <- function(scores_dt, label) {
  if (nrow(scores_dt) == 0) return(NULL)
  res <- tryCatch(
    canonical_screen_bt(scores_dt = scores_dt, returns_dt = returns_dt, bench_dt = bench_dt,
                        top_n = 25L, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                        run_id = paste0("insider_", label), strategy_id = paste0("insider_", label),
                        periods_per_year = 12L),
    error = function(e) list(error = conditionMessage(e)))
  res
}

# oos_retention (essence_score v2: anchored splits {55/65/75} median of OOS_IR/IS_IR)
oos_retention_v2 <- function(pr) {
  # pr: data.table(date, ret_net, benchmark_ret)
  if (is.null(pr) || nrow(pr) < 12) return(list(retention = NA_real_, splits = NA_real_, n = nrow(pr)))
  setorder(pr, date)
  a <- pr$ret_net - pr$benchmark_ret; a <- a[is.finite(a)]; n <- length(a)
  if (n < 12 || sd(a) == 0) return(list(retention = NA_real_, splits = NA_real_, n = n))
  af <- 12
  splits <- c(0.55, 0.65, 0.75)
  rets <- vapply(splits, function(fr) {
    k <- floor(n * fr); if (k < 6 || (n - k) < 6) return(NA_real_)
    ia <- a[1:k]; oa <- a[(k+1):n]
    is_ir <- if (sd(ia) > 0) mean(ia)/sd(ia)*sqrt(af) else NA_real_
    oos_ir <- if (sd(oa) > 0) mean(oa)/sd(oa)*sqrt(af) else NA_real_
    if (is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir/is_ir else NA_real_
  }, numeric(1))
  ret <- if (any(is.finite(rets))) median(rets[is.finite(rets)]) else NA_real_
  list(retention = ret, splits = rets, n = n)
}

# calmar from period_returns net series (annualized CAGR / MDD)
calmar_from_pr <- function(pr) {
  if (is.null(pr) || nrow(pr) < 6) return(list(calmar = NA_real_, cagr = NA_real_, mdd = NA_real_))
  setorder(pr, date)
  r <- pr$ret_net; nav <- cumprod(1 + r)
  yrs <- nrow(pr) / 12
  cagr <- nav[length(nav)]^(1/yrs) - 1
  peak <- cummax(nav); dd <- nav/peak - 1; mdd <- -min(dd)
  calmar <- if (mdd > 0) cagr / mdd else NA_real_
  list(calmar = calmar, cagr = cagr, mdd = mdd)
}

# rank-IC (Spearman): score(Date) vs Ret_1m(그 Date 홀딩월). PORT_t와 구분 보고.
rank_ic <- function(scores_dt) {
  j <- merge(scores_dt, returns_dt[, .(Date, Ticker, Ret_1m)], by = c("Date","Ticker"))
  j <- j[is.finite(score) & is.finite(Ret_1m)]
  ics <- j[, {
    if (.N >= 8 && sd(score) > 0 && sd(Ret_1m) > 0)
      .(ic = cor(rank(score), rank(Ret_1m)))
    else .(ic = NA_real_)
  }, by = Date]$ic
  ics <- ics[is.finite(ics)]
  if (length(ics) < 3) return(list(mean_ic = NA_real_, icir = NA_real_, n = length(ics), t = NA_real_))
  m <- mean(ics); s <- sd(ics)
  list(mean_ic = m, icir = if (s > 0) m/s*sqrt(12) else NA_real_,
       n = length(ics), t = if (s > 0) m/(s/sqrt(length(ics))) else NA_real_)
}

# eras
era_def <- list(
  contiguous_2015_16 = c("2015-01","2016-01"),
  recent_2024        = c("2024-12","2024-12"),
  combined_all       = c(min(panel$hold_ym), max(panel$hold_ym))
)
in_era <- function(dt, era) dt[hold_ym >= era[1] & hold_ym <= era[2]]

variants <- list(krw = "krw", nflow = "nflow")
results <- list()
for (vn in names(variants)) {
  vcol <- variants[[vn]]
  sdt_all <- panel[, .(Date, Ticker, score = get(vcol), hold_ym)][is.finite(score)]
  for (en in names(era_def)) {
    sdt <- in_era(sdt_all, era_def[[en]])[, .(Date, Ticker, score)]
    key <- paste0(vn, "__", en)
    scr <- run_screen(sdt, key)
    ric <- rank_ic(in_era(sdt_all, era_def[[en]])[, .(Date, Ticker, score)])
    if (is.null(scr) || !is.null(scr$error)) {
      results[[key]] <- list(variant = vn, era = en, n_signal_months = length(unique(sdt$Date)),
                             error = if (!is.null(scr)) scr$error else "empty",
                             rank_ic = ric)
      next
    }
    pr <- as.data.table(scr$period_returns)  # date, ret_net, benchmark_ret
    oos <- oos_retention_v2(copy(pr))
    cal <- calmar_from_pr(copy(pr))
    # post-2017 sub-period PORT_t (if any months >= 2017)
    port_t <- scr$portfolio_alpha_t_nw_lag3
    ir <- scr$information_ratio
    delta_ir <- if (is.finite(ir)) ir - INCUMBENT_IR else NA_real_
    hard_port <- is.finite(port_t) && port_t >= 2.95
    hard_oos  <- is.finite(oos$retention) && oos$retention >= 0.7
    hard_cal  <- is.finite(cal$calmar) && cal$calmar >= 0.64
    results[[key]] <- list(
      variant = vn, era = en,
      n_signal_months = scr$n_months, top_n = scr$top_n,
      portfolio_alpha_t_nw_lag3 = port_t,
      portfolio_alpha_t_pvalue = scr$portfolio_alpha_t_pvalue,
      information_ratio = ir, alpha_annualized = scr$alpha_annualized,
      net_sr = scr$net_sr, mean_active_net = scr$mean_active_net,
      turnover_annual = scr$turnover_annual,
      oos_retention = oos$retention, oos_splits = as.list(oos$splits),
      calmar = cal$calmar, cagr = cal$cagr, mdd = cal$mdd,
      book_marginal_delta_ir = delta_ir, incumbent_ir = INCUMBENT_IR,
      rank_ic_mean = ric$mean_ic, rank_icir = ric$icir, rank_ic_t = ric$t, rank_ic_n = ric$n,
      hard_gate = list(port_t_ge_2.95 = hard_port, oos_ret_ge_0.7 = hard_oos, calmar_ge_0.64 = hard_cal,
                       all_pass = hard_port && hard_oos && hard_cal)
    )
  }
}

# ── 4) 커버리지 게이팅 ───────────────────────────────────────────────────────
meta <- fromJSON(file.path(HARN, "reports", "signal_build_meta.json"))
contig <- meta$coverage$largest_contiguous_run_months
authoritative <- is.finite(contig) && contig >= MIN_CONTIG
verdict_level <- if (authoritative) "GRADUATION_JUDGMENT_VALID" else "INTERIM_NONAUTHORITATIVE"

out <- list(
  harness = "dart_officer_netbuy_graduation",
  generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  verdict_level = verdict_level,
  coverage = list(
    largest_contiguous_run_months = contig,
    min_contig_required = MIN_CONTIG,
    n_signal_months_total = meta$coverage$n_signal_months,
    sig_month_range = meta$coverage$sig_month_range,
    n_gaps_within_range = length(meta$coverage$gaps_within_range),
    authoritative = authoritative
  ),
  incumbent_book_ir = INCUMBENT_IR,
  metric_type = "canonical_screen",
  results = results,
  caveats = c(
    "metric_type=canonical_screen (screening-tier, NOT forge-authoritative). 자본판정=forge build_bt_result 이후.",
    "officer reporter_type 는 2009+ 만 신뢰(pre-2009 sparse). 현 커버리지 대부분 갭 → underpowered.",
    "rank-IC ≠ PORT_t. 졸업 binding = PORT_t(NW lag-3).",
    "mechanical 제외 = report n_mechanical==0 (disc_change_qty NULL 이라 report-level 근사).",
    if (!authoritative) "★ INTERIM: contiguous run < 60월. 게이트 판정은 하네스 작동검증용, verdict 아님." else "graduation judgment valid (contig>=60)."
  )
)

writeLines(toJSON(out, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null"),
           file.path(HARN, "reports", "graduation_gate_result.json"))

cat("=== DART Officer Net-Buy Graduation Gate ===\n")
cat(sprintf("verdict_level: %s (contiguous run %s / min %d)\n", verdict_level,
            ifelse(is.na(contig), "NA", contig), MIN_CONTIG))
for (k in names(results)) {
  r <- results[[k]]
  if (!is.null(r$error)) { cat(sprintf("  %-24s : ERROR %s (n=%s)\n", k, r$error, r$n_signal_months)); next }
  cat(sprintf("  %-24s : n=%2d PORT_t=%+.2f IR=%+.2f oos=%s calmar=%s | rankIC=%s(t=%s) | HARD=%s\n",
              k, r$n_signal_months,
              r$portfolio_alpha_t_nw_lag3, r$information_ratio,
              ifelse(is.finite(r$oos_retention), sprintf("%.2f", r$oos_retention), "NA"),
              ifelse(is.finite(r$calmar), sprintf("%.2f", r$calmar), "NA"),
              ifelse(is.finite(r$rank_ic_mean), sprintf("%+.3f", r$rank_ic_mean), "NA"),
              ifelse(is.finite(r$rank_ic_t), sprintf("%.2f", r$rank_ic_t), "NA"),
              r$hard_gate$all_pass))
}
cat(sprintf("wrote %s\n", file.path(HARN, "reports", "graduation_gate_result.json")))
