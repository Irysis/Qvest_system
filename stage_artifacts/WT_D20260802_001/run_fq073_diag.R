# =============================================================================
# run_fq073_diag.R — WT-D20260802_001 / FQ-073
#   기전 진단 + 동적 PIT 검정 + 대형주-제한 변형(F5) + essence_score 사이드카
#
#   ★동적 검정 병행 = SOT §4 HARD (정적 PASS가 면제하지 않음):
#     ① lag1 스트레스  ② strict-PIT A/B  ③ vintage-swap  ④ validate_label_direction(러너에서 수행)
# =============================================================================
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_001")
`%||%` <- function(a, b) if (is.null(a)) b else a
say <- function(fmt, ...) cat(sprintf(paste0("[diag] ", fmt, "\n"), ...))

source("02_Infrastructure/contracts/canonical_screen_bt.R")
source("02_Infrastructure/ramp/factor_validation.R")

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150","Sector")))
RAW[, Date := as.Date(Date)]; RAW <- RAW[Date >= as.Date("2014-11-01")]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date); RAWME <- RAW[Date %in% MEND]
fwd <- build_monthly_forward_returns(RAWME, MEND)
returns_dt <- fwd$returns_dt[, .(Date = as.Date(Date), Ticker, Ret_1m)]
bench_dt   <- fwd$bench_dt[,   .(Date = as.Date(Date), BM_Ret)]
liq_dt     <- fwd$liq_dt[,     .(Date = as.Date(Date), Ticker, adv)]
size_dt    <- RAWME[, .(Date, Ticker, Size)]

msr <- function(sc, top_n = 25L) {
  sc <- sc[is.finite(score)]
  if (!nrow(sc)) return(NULL)
  canonical_screen_bt(sc, returns_dt, bench_dt, top_n = top_n, cost_bps_oneway = 15,
                      liq_dt = liq_dt, liq_min = 2e8, diag_dual_basis = TRUE, size_dt = size_dt)
}
brief <- function(r, tag) {
  if (is.null(r)) { say("%-34s : 측정 불가", tag); return(invisible(NULL)) }
  say("%-34s : PORT_t=%7.3f p=%.3f n=%3d IR=%6.3f TO=%6.1f%% | EW PORT_t=%7.3f",
      tag, r$portfolio_alpha_t_nw_lag3, r$portfolio_alpha_t_pvalue, r$n_months,
      r$information_ratio, 100*r$turnover_annual,
      r$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_)
}

DIAG <- list()
P1 <- as.data.table(read_parquet(file.path(OUT, "alpha_scores_F1_export_surprise.parquet")))

# ---------------------------------------------------------------------------
# A. 유효 횡단면 차원 — "firm-level" 주장의 실측 검증
#    같은 HS4 단일 매핑 종목은 동일 스코어를 받는다 → 유효 차원 = 서로 다른 HS 믹스 수
# ---------------------------------------------------------------------------
tie <- P1[!is.na(value), .(n_firms = .N, n_distinct = uniqueN(round(value, 10))), by = Date]
DIAG$effective_cross_section <- list(
  metric_type = "diagnostic",
  n_firms_scored_avg = round(tie[, mean(n_firms)], 1),
  n_distinct_scores_avg = round(tie[, mean(n_distinct)], 1),
  distinct_ratio = round(tie[, mean(n_distinct / n_firms)], 4),
  note = "distinct_ratio < 1 = 동일 HS4 버킷 종목이 구분 불가(동점). 'firm-level' 신호의 실제 해상도.")
say("유효 횡단면: 월평균 스코어부여 %.0f종목 중 서로 다른 값 %.0f개 (비율 %.3f)",
    tie[, mean(n_firms)], tie[, mean(n_distinct)], tie[, mean(n_distinct/n_firms)])

# ---------------------------------------------------------------------------
# B. rank-IC 계열 (ADVISORY — 선택 권위 아님)
# ---------------------------------------------------------------------------
icm <- merge(P1[!is.na(value)], returns_dt, by = c("Date", "Ticker"))
ic <- icm[, if (.N >= 10L && sd(value) > 0 && sd(Ret_1m) > 0)
             .(ic = cor(value, Ret_1m, method = "spearman")) else .(ic = NA_real_), by = Date]
ic <- ic[is.finite(ic)]
ic_mean <- ic[, mean(ic)]; ic_sd <- ic[, sd(ic)]; icir <- ic_mean / ic_sd
ic_t <- ic_mean / (ic_sd / sqrt(nrow(ic)))
DIAG$rank_ic <- list(metric_type = "advisory", rank_ic = round(ic_mean, 5),
                     icir = round(icir, 4), ic_t_stat = round(ic_t, 3), n_months = nrow(ic))
say("rank-IC(advisory): IC=%.5f ICIR=%.4f t=%.3f n=%d", ic_mean, icir, ic_t, nrow(ic))

# ---------------------------------------------------------------------------
# C. 대형주-제한 변형 F5 — 라운드의 핵심 주장 직접 검정
#    "수출 신호는 대형 tier에도 산다" → 유니버스를 cap rank 1-100 으로 제한하면?
# ---------------------------------------------------------------------------
SR <- RAWME[(K200 == TRUE | KQ150 == TRUE) & is.finite(Size),
            .(Date, Ticker, cap_rank = frank(-Size, ties.method = "first")), by = .(Date)]
SR <- RAWME[(K200 == TRUE | KQ150 == TRUE) & is.finite(Size), .(Date, Ticker, Size)]
SR[, cap_rank := frank(-Size, ties.method = "first"), by = Date]
LARGE <- SR[cap_rank <= 100L, .(Date, Ticker)]
P1L <- merge(P1[!is.na(value), .(Date, Ticker, score = value)], LARGE, by = c("Date", "Ticker"))
r5 <- msr(P1L)
DIAG$F5_large_cap_restricted <- if (is.null(r5)) NULL else list(
  metric_type = "canonical_screen", universe = "cap_rank<=100 within K200uKQ150",
  portfolio_alpha_t_nw_lag3 = round(r5$portfolio_alpha_t_nw_lag3, 4),
  p = round(r5$portfolio_alpha_t_pvalue, 4), n_months = r5$n_months,
  information_ratio = round(r5$information_ratio, 4),
  turnover_annual = round(r5$turnover_annual, 3),
  n_scored_avg = round(P1L[, .N, by = Date][, mean(N)], 1),
  ew_universe_port_t = round(r5$diag_ew_universe$portfolio_alpha_t_nw_lag3 %||% NA_real_, 4))
brief(r5, "F5 대형주제한(cap_rank<=100)")

# ---------------------------------------------------------------------------
# D. 동적 PIT 검정 ① lag1 스트레스 — 신호를 1개월 더 늦춰 적용
#    base >> lag1 이면 동월 누출 의심. (음수 base 에서는 누출 여지가 없음을 확인하는 용도)
# ---------------------------------------------------------------------------
P1lag <- copy(P1)[!is.na(value)]
setorder(P1lag, Ticker, Date)
P1lag[, score := shift(value, 1L, type = "lag"), by = Ticker]
r_lag1 <- msr(P1lag[, .(Date, Ticker, score)])
DIAG$dynamic_lag1_stress <- if (is.null(r_lag1)) NULL else list(
  metric_type = "canonical_screen",
  base_port_t = round(readRDS(file.path(OUT,"fq073_ast_results.rds"))$results$F1_export_surprise$portfolio_alpha_t_nw_lag3, 4),
  lag1_port_t = round(r_lag1$portfolio_alpha_t_nw_lag3, 4), n_months = r_lag1$n_months,
  interpretation = "base 와 lag1 의 격차가 크면 동월 누출 의심. 본 라운드 base 가 음수라 누출 인플레 여지 없음 — 확인 목적.")
brief(r_lag1, "D lag1 스트레스")

# ---------------------------------------------------------------------------
# E. 동적 PIT 검정 ② strict-PIT A/B — 신호 컷오프를 홀딩월 첫날 기준으로 더 조임
#    현행: usable = M+1/15, score_date = M+1 월말 (버퍼 14~17일)
#    strict: 데이터월을 한 달 더 뒤로(M-1) = 홀딩월 H-3 → 여유 극대
# ---------------------------------------------------------------------------
P1s <- copy(P1)[!is.na(value)]; setorder(P1s, Ticker, Date)
P1s[, score := shift(value, 1L, type = "lag"), by = Ticker]   # = strict lane (M-1 데이터)
infl <- NA_real_
r_base <- readRDS(file.path(OUT,"fq073_ast_results.rds"))$results$F1_export_surprise
if (!is.null(r_lag1)) infl <- r_base$portfolio_alpha_t_nw_lag3 - r_lag1$portfolio_alpha_t_nw_lag3
DIAG$dynamic_strict_pit_ab <- list(
  metric_type = "canonical_screen",
  base_port_t = round(r_base$portfolio_alpha_t_nw_lag3, 4),
  strict_port_t = if (is.null(r_lag1)) NA_real_ else round(r_lag1$portfolio_alpha_t_nw_lag3, 4),
  inflation_base_minus_strict = round(infl, 4),
  verdict = if (is.finite(infl) && infl > 0.5) "INFLATION_SUSPECTED" else "NO_INFLATION",
  note = "strict lane = 데이터월 한 달 추가 지연. 인플레(base-strict)가 크면 타이밍 경계 누출.")

# ---------------------------------------------------------------------------
# F. 동적 PIT 검정 ③ vintage-swap — customs 개정 스냅샷 2종 차분
# ---------------------------------------------------------------------------
VS <- file.path(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold/fq073/vintage_store")
snaps <- sort(list.files(VS, pattern = "^customs_hs_.*\\.parquet$", full.names = TRUE))
vsw <- list(n_snapshots = length(snaps), snapshots = basename(snaps))
if (length(snaps) >= 2) {
  a <- as.data.table(read_parquet(snaps[1]))[, .(hs, ym, exp_a = exp_usd)]
  b <- as.data.table(read_parquet(snaps[length(snaps)]))[, .(hs, ym, exp_b = exp_usd)]
  m <- merge(a, b, by = c("hs", "ym"))
  m[, chg := exp_b != exp_a]
  vsw$n_cells <- nrow(m); vsw$changed_share <- round(m[, mean(chg)], 6)
  vsw$max_ym_a <- a[, max(ym)]; vsw$max_ym_b <- b[, max(ym)]
  vsw$verdict <- if (m[, sum(chg)] == 0)
    "NO_REVISION_OBSERVED_IN_WINDOW — 두 스냅샷(6일 간격, 개정일 15일 미포함) 사이 개정 0. 개정폭 미측정(무증거≠무개정)."
    else "REVISION_OBSERVED"
}
DIAG$dynamic_vintage_swap <- vsw
say("vintage-swap: 스냅샷 %d개 · changed_share=%s · %s", vsw$n_snapshots,
    format(vsw$changed_share %||% NA), substr(vsw$verdict %||% "-", 1, 60))

# ---------------------------------------------------------------------------
# G. gross vs net — 음수가 비용 때문인가 신호 때문인가
# ---------------------------------------------------------------------------
r0 <- msr(P1[!is.na(value), .(Date, Ticker, score = value)])
r0_nocost <- canonical_screen_bt(P1[!is.na(value), .(Date, Ticker, score = value)],
                                 returns_dt, bench_dt, top_n = 25L, cost_bps_oneway = 0,
                                 liq_dt = liq_dt, liq_min = 2e8, diag_dual_basis = FALSE)
DIAG$gross_vs_net <- list(
  metric_type = "canonical_screen",
  net_15bps_port_t = round(r0$portfolio_alpha_t_nw_lag3, 4),
  gross_0bps_port_t = round(r0_nocost$portfolio_alpha_t_nw_lag3, 4),
  turnover_annual = round(r0$turnover_annual, 3),
  cost_drag_annual = round(r0$turnover_annual * 0.0015, 4),
  verdict = if (r0_nocost$portfolio_alpha_t_nw_lag3 < 0)
    "SIGNAL_NEGATIVE_GROSS — 비용 제거해도 음수. 비용 탓 아님." else "COST_BOUND")
say("gross(0bps) PORT_t=%.3f vs net(15bps) PORT_t=%.3f · TO=%.1f%% · 비용드래그=%.2f%%/yr",
    r0_nocost$portfolio_alpha_t_nw_lag3, r0$portfolio_alpha_t_nw_lag3,
    100*r0$turnover_annual, 100*r0$turnover_annual*0.0015)

# ---------------------------------------------------------------------------
# H. 부기간 안정성 (advisory)
# ---------------------------------------------------------------------------
sub <- list()
for (w in list(c("2016-01-01","2019-12-31"), c("2020-01-01","2022-12-31"), c("2023-01-01","2026-12-31"))) {
  s <- P1[!is.na(value) & Date >= as.Date(w[1]) & Date <= as.Date(w[2]), .(Date, Ticker, score = value)]
  rr <- tryCatch(msr(s), error = function(e) NULL)
  sub[[paste(w, collapse = "_")]] <- if (is.null(rr)) NA_real_ else round(rr$portfolio_alpha_t_nw_lag3, 3)
}
DIAG$subperiod_port_t <- sub
say("부기간 PORT_t: %s", paste(names(sub), unlist(sub), sep = "=", collapse = " | "))

write_json(DIAG, file.path(OUT, "fq073_diagnostics.json"), auto_unbox = TRUE,
           pretty = TRUE, null = "null", digits = 6)
saveRDS(list(F5 = r5, lag1 = r_lag1, base = r0, gross = r0_nocost),
        file.path(OUT, "fq073_diag_results.rds"))
say("→ fq073_diagnostics.json")
