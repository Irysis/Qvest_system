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
source(file.path(HARN, "banded_holdings_sim.R"))   # 보유밴드 변형(turnover mitigation)

# 사전등록 밴드폭 (과최적화 금지 — 2종만)
BAND_SPECS <- list(
  band_A = list(n_entry = 20L, n_exit = 30L, max_hold = 6L),   # 넓은 버퍼(강 회전억제)
  band_B = list(n_entry = 25L, n_exit = 35L, max_hold = 3L)    # 좁은 버퍼·짧은 보유
)

MIN_CONTIG <- as.integer(Sys.getenv("MIN_CONTIG_MONTHS", "60"))
INCUMBENT_IR <- 1.416   # book_state.json incumbent_book_ir (net_active_recon_v1)

# ── 1) 신호 패널 ─────────────────────────────────────────────────────────────
panel <- as.data.table(read_parquet(file.path(HARN, "data", "officer_netbuy_panel.parquet")))
panel[, Date := as.Date(Date)]                 # usable-month begin
panel[, hold_ym := format(Date, "%Y-%m")]      # 홀딩월(=usable month)

# ── 2) 슬림 월별 시장입력 (prep_market_monthly.py 산출 — R arrow RAWDATA halt 회피) ──
#   무거운 daily→monthly 집계는 Python 에서 수행됨. 여기선 슬림 parquet 3개만 읽는다.
ym_begin <- function(ym) as.Date(paste0(ym, "-01"))
.reqf <- function(p) { if (!file.exists(p)) stop(sprintf(
  "missing %s — run: python stage_artifacts/insider_graduation_harness/prep_market_monthly.py", basename(p))); p }

returns_dt <- as.data.table(read_parquet(.reqf(file.path(HARN, "data", "market_returns_monthly.parquet"))))
returns_dt[, Date := as.Date(Date)]
returns_dt[, hold_ym := format(Date, "%Y-%m")]
returns_dt <- returns_dt[, .(Date, Ticker, Ret_1m, hold_ym)]

bench_dt <- as.data.table(read_parquet(.reqf(file.path(HARN, "data", "bench_monthly.parquet"))))
bench_dt[, Date := as.Date(Date)]
bench_dt <- bench_dt[, .(Date, BM_Ret)]

liq_dt <- as.data.table(read_parquet(.reqf(file.path(HARN, "data", "liq_monthly.parquet"))))
liq_dt[, Date := as.Date(Date)]
liq_dt <- liq_dt[, .(Date, Ticker, adv)]

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

# eras — derive largest contiguous hold_ym run dynamically (not hardcoded).
hold_months <- sort(unique(panel$hold_ym))
mp <- as.integer(sub("-", "", hold_months)) # yyyymm int not contiguous-safe; use ordinal
ord <- as.integer(factor(hold_months, levels =
  format(seq(as.Date(paste0(min(hold_months), "-01")),
             as.Date(paste0(max(hold_months), "-01")), by = "month"), "%Y-%m")))
best_len <- run <- 1L; best_i <- start_i <- 1L
for (i in 2:length(ord)) {
  if (ord[i] == ord[i-1] + 1L) { run <- run + 1L; if (run > best_len) { best_len <- run; best_i <- start_i } }
  else { run <- 1L; start_i <- i }
}
contig_range <- c(hold_months[best_i], hold_months[best_i + best_len - 1L])
era_def <- list(
  contiguous_run = contig_range,                      # 최장 연속 hold_ym 블록
  combined_all   = c(min(hold_months), max(hold_months))  # 전체(갭 포함, 실측 overlap만)
)
in_era <- function(dt, era) dt[hold_ym >= era[1] & hold_ym <= era[2]]

# turnover gate (screening hard-fail): 1,100%/yr (measurement-graduation 2026-06-13).
TURNOVER_GATE <- 11.0   # annual traded (1,100%)

# 공용 result entry 빌더 — raw/band 모두 사용. scr 는 canonical_screen_bt 또는 banded_holdings_bt 산출.
build_entry <- function(scr, vn, en, ric, extra = list()) {
  pr <- as.data.table(scr$period_returns)
  oos <- oos_retention_v2(copy(pr))
  cal <- calmar_from_pr(copy(pr))
  port_t <- scr$portfolio_alpha_t_nw_lag3
  ir <- scr$information_ratio
  delta_ir <- if (is.finite(ir)) ir - INCUMBENT_IR else NA_real_
  to <- scr$turnover_annual
  hard_port <- is.finite(port_t) && port_t >= 2.95
  hard_oos  <- is.finite(oos$retention) && oos$retention >= 0.7
  hard_cal  <- is.finite(cal$calmar) && cal$calmar >= 0.64
  to_ok     <- is.finite(to) && to <= TURNOVER_GATE
  c(list(
    variant = vn, era = en,
    n_signal_months = scr$n_months, top_n = scr$top_n,
    portfolio_alpha_t_nw_lag3 = port_t, portfolio_alpha_t_pvalue = scr$portfolio_alpha_t_pvalue,
    information_ratio = ir, alpha_annualized = scr$alpha_annualized,
    net_sr = scr$net_sr, mean_active_net = scr$mean_active_net,
    turnover_annual = to, turnover_pct = if (is.finite(to)) to * 100 else NA_real_,
    oos_retention = oos$retention, oos_splits = as.list(oos$splits),
    calmar = cal$calmar, cagr = cal$cagr, mdd = cal$mdd,
    book_marginal_delta_ir = delta_ir, incumbent_ir = INCUMBENT_IR,
    rank_ic_mean = ric$mean_ic, rank_icir = ric$icir, rank_ic_t = ric$t, rank_ic_n = ric$n,
    hard_gate = list(port_t_ge_2.95 = hard_port, oos_ret_ge_0.7 = hard_oos, calmar_ge_0.64 = hard_cal,
                     turnover_le_1100pct = to_ok,
                     all_pass = hard_port && hard_oos && hard_cal && to_ok)
  ), extra)
}

variants <- list(krw = "krw", nflow = "nflow")
results <- list()
for (vn in names(variants)) {
  vcol <- variants[[vn]]
  sdt_all <- panel[, .(Date, Ticker, score = get(vcol), hold_ym)][is.finite(score)]
  for (en in names(era_def)) {
    sdt <- in_era(sdt_all, era_def[[en]])[, .(Date, Ticker, score)]
    ric <- rank_ic(sdt)
    # ── RAW (canonical top-25 매월 재선정) ──
    key <- paste0(vn, "__", en)
    scr <- run_screen(sdt, key)
    if (is.null(scr) || !is.null(scr$error)) {
      results[[key]] <- list(variant = vn, era = en, method = "raw",
                             n_signal_months = length(unique(sdt$Date)),
                             error = if (!is.null(scr)) scr$error else "empty", rank_ic = ric)
    } else {
      results[[key]] <- build_entry(scr, vn, en, ric, extra = list(method = "raw"))
    }
    # ── BAND (hysteresis 보유밴드) — 사전등록 2폭 ──
    for (bn in names(BAND_SPECS)) {
      bs <- BAND_SPECS[[bn]]
      bkey <- paste0(vn, "__", en, "__", bn)
      bscr <- tryCatch(
        banded_holdings_bt(scores_dt = sdt, returns_dt = returns_dt, bench_dt = bench_dt,
                           n_entry = bs$n_entry, n_exit = bs$n_exit, max_hold = bs$max_hold,
                           top_n = 25L, cost_bps_oneway = 15, liq_dt = liq_dt, liq_min = 2e8,
                           run_id = paste0("insider_", bkey), strategy_id = paste0("insider_", bkey),
                           periods_per_year = 12L),
        error = function(e) list(error = conditionMessage(e)))
      if (is.null(bscr) || !is.null(bscr$error) || bscr$n_months == 0) {
        results[[bkey]] <- list(variant = vn, era = en, method = "band", band = bn,
                                error = if (!is.null(bscr$error)) bscr$error else "no_holdings", rank_ic = ric)
      } else {
        results[[bkey]] <- build_entry(bscr, vn, en, ric, extra = list(
          method = "band", band = bn, n_entry = bs$n_entry, n_exit = bs$n_exit,
          max_hold = bs$max_hold, avg_holdings = bscr$avg_holdings))
      }
    }
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
  turnover_gate_pct = TURNOVER_GATE * 100,
  band_specs = BAND_SPECS,
  results = results,
  caveats = c(
    "metric_type=canonical_screen (screening-tier, NOT forge-authoritative). 자본판정=forge build_bt_result 이후.",
    "officer reporter_type 는 2009+ 만 신뢰(pre-2009 sparse). 현 커버리지 대부분 갭 → underpowered.",
    "rank-IC ≠ PORT_t. 졸업 binding = PORT_t(NW lag-3).",
    "mechanical 제외 = report n_mechanical==0 (disc_change_qty NULL 이라 report-level 근사).",
    "band 변형 = hysteresis 보유밴드(turnover mitigation). raw vs band turnover_comparison.json 참조.",
    if (!authoritative) "★ INTERIM: contiguous run < 60월. 게이트 판정은 하네스 작동검증용, verdict 아님." else "graduation judgment valid (contig>=60)."
  )
)

writeLines(toJSON(out, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null"),
           file.path(HARN, "reports", "graduation_gate_result.json"))

# ── turnover_comparison.json: raw vs band (회전율·PORT_t·calmar 대조) ──
tc_rows <- list()
for (vn in names(variants)) for (en in names(era_def)) {
  raw_k <- paste0(vn, "__", en)
  rr <- results[[raw_k]]
  raw_to <- if (!is.null(rr) && is.null(rr$error)) rr$turnover_pct else NA_real_
  raw_pt <- if (!is.null(rr) && is.null(rr$error)) rr$portfolio_alpha_t_nw_lag3 else NA_real_
  raw_cal <- if (!is.null(rr) && is.null(rr$error)) rr$calmar else NA_real_
  for (bn in names(BAND_SPECS)) {
    bk <- paste0(vn, "__", en, "__", bn)
    br <- results[[bk]]
    if (is.null(br) || !is.null(br$error)) next
    tc_rows[[bk]] <- list(
      variant = vn, era = en, band = bn,
      raw_turnover_pct = raw_to, band_turnover_pct = br$turnover_pct,
      turnover_reduction_x = if (is.finite(raw_to) && is.finite(br$turnover_pct) && br$turnover_pct > 0)
                               raw_to / br$turnover_pct else NA_real_,
      band_below_1100pct = is.finite(br$turnover_pct) && br$turnover_pct <= 1100,
      raw_port_t = raw_pt, band_port_t = br$portfolio_alpha_t_nw_lag3,
      port_t_retained = is.finite(raw_pt) && is.finite(br$portfolio_alpha_t_nw_lag3) &&
                        br$portfolio_alpha_t_nw_lag3 >= 0.9 * raw_pt,
      raw_calmar = raw_cal, band_calmar = br$calmar,
      avg_holdings = br$avg_holdings
    )
  }
}
tc_out <- list(
  test = "raw vs holding-band turnover mitigation",
  turnover_gate_pct = 1100,
  interpretation = "밴드가 회전을 1,100% 아래로 낮추면서 PORT_t 를 유지(>=90% raw)하면 성공. 회전만 줄고 PORT_t 죽으면 실패(정직 보고).",
  comparisons = tc_rows
)
writeLines(toJSON(tc_out, pretty = TRUE, auto_unbox = TRUE, null = "null", na = "null"),
           file.path(HARN, "reports", "turnover_comparison.json"))

cat("=== DART Officer Net-Buy Graduation Gate (raw + holding-band) ===\n")
cat(sprintf("verdict_level: %s (contiguous run %s / min %d)\n", verdict_level,
            ifelse(is.na(contig), "NA", contig), MIN_CONTIG))
for (k in names(results)) {
  r <- results[[k]]
  if (!is.null(r$error)) { cat(sprintf("  %-32s : ERROR %s\n", k, r$error)); next }
  cat(sprintf("  %-32s : n=%2d PORT_t=%+.2f IR=%+.2f TO=%5.0f%% oos=%s cal=%s | rankIC=%s | HARD=%s\n",
              k, r$n_signal_months,
              r$portfolio_alpha_t_nw_lag3, r$information_ratio,
              ifelse(is.finite(r$turnover_pct), r$turnover_pct, NA),
              ifelse(is.finite(r$oos_retention), sprintf("%.2f", r$oos_retention), "NA"),
              ifelse(is.finite(r$calmar), sprintf("%.2f", r$calmar), "NA"),
              ifelse(is.finite(r$rank_ic_mean), sprintf("%+.3f", r$rank_ic_mean), "NA"),
              r$hard_gate$all_pass))
}
cat("\n--- turnover mitigation (raw vs band) ---\n")
for (k in names(tc_rows)) {
  v <- tc_rows[[k]]
  cat(sprintf("  %-32s : TO %5.0f%% -> %5.0f%% (%.1fx) below1100=%s | PORT_t %+.2f -> %+.2f retained=%s | holds=%.1f\n",
              k, ifelse(is.finite(v$raw_turnover_pct), v$raw_turnover_pct, NA),
              ifelse(is.finite(v$band_turnover_pct), v$band_turnover_pct, NA),
              ifelse(is.finite(v$turnover_reduction_x), v$turnover_reduction_x, NA),
              v$band_below_1100pct,
              ifelse(is.finite(v$raw_port_t), v$raw_port_t, NA),
              ifelse(is.finite(v$band_port_t), v$band_port_t, NA),
              v$port_t_retained,
              ifelse(is.finite(v$avg_holdings), v$avg_holdings, NA)))
}
cat(sprintf("wrote %s + turnover_comparison.json\n", file.path(HARN, "reports", "graduation_gate_result.json")))
