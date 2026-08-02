# =============================================================================
# run_fq002_pilot.R — FQ-002 계약수주 magnitude 파일럿 측정 (WT-D20260802_018)
#
# 사전등록: 04_Research/method_frontier/fq002_contract_magnitude_prereg.md (크롤 전 고정)
#   · WINDOW_M=12 · SCOPE=all · n_holdings=20 고정 / DENOM {revenue,size} 진단 병기
#   · 1차 판정 = IC 부호·크기 (rank-IC + FMB t). PORT_t 는 참고(파일럿 표본 얇음).
#   · 정정 A/B: Panel A(최초 체결값) vs Panel B(정정값 소급 주입) — B 우수 = 누출 지문
#   · lag1 스트레스 / 커버리지 / dual-basis(cap-w·EW-uni·cap-tier) 병기
#
# 측정 규율: canonical_screen_bt() 실측(metric_type=canonical_screen), proxy 손계산 없음.
#   IC 는 순수 진단 통계(성과 합성 아님 — cor() 는 백테스트 자체합성에 해당하지 않음).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
setDTthreads(2)

.rt <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
ROOT <- .rt(); setwd(ROOT)
OUTD <- "04_Research/method_frontier/fq002_contract_magnitude"
dir.create(OUTD, recursive = TRUE, showWarnings = FALSE)

source("02_Infrastructure/contracts/canonical_screen_bt.R")

CKDIR <- ".cache/dart/contract_backfill"
fs <- list.files(CKDIR, pattern = "^\\d{6}\\.csv$", full.names = TRUE)
cat(sprintf("[fq002] 체크포인트 %d개월\n", length(fs)))
stopifnot(length(fs) >= 30)   # 파일럿 36개월 기대 — 대폭 미달이면 크롤 미완

raw <- rbindlist(lapply(fs, function(f) fread(f, colClasses = list(character = "corp_code"))), fill = TRUE)
D <- raw[!is.na(rcept_no)]
cat(sprintf("[fq002] 원시 %d행 | OK %d | 정정 %d | parse실패 %d\n",
            nrow(D), nrow(D[parse_status == "OK"]), sum(D$is_correction),
            nrow(D[parse_status != "OK"])))

# ── Panel B 용 파생 체크포인트: 정정값을 최초 공시일에 소급 주입 ─────────────
#    매칭 규칙(사전등록): 정정 rcept 를 같은 corp_code 의 직전 180일 내 가장 최근
#    최초 체결 공시에 매칭. 다중 정정 = 최신 정정 우선. 매칭 실패 = 제외(보수적).
ORIG <- D[is_correction == FALSE & parse_status == "OK"]
CORR <- D[is_correction == TRUE & parse_status == "OK"]
CORR[, rc_dt := as.IDate(as.character(rcept_dt), "%Y%m%d")]
ORIG[, rc_dt := as.IDate(as.character(rcept_dt), "%Y%m%d")]
setorder(CORR, corp_code, rc_dt)
matched <- 0L
B_sub <- copy(ORIG)
if (nrow(CORR)) {
  for (i in seq_len(nrow(CORR))) {
    cc <- CORR$corp_code[i]; cd <- CORR$rc_dt[i]
    cand <- B_sub[corp_code == cc & rc_dt < cd & rc_dt >= cd - 180L]
    if (!nrow(cand)) next
    j <- which(B_sub$rcept_no == cand[which.max(rc_dt), rcept_no])[1]
    # 최신 정정 우선: 이후 정정이 다시 덮어씀 (CORR 이 rc_dt 순 정렬)
    B_sub[j, `:=`(contract_amount = CORR$contract_amount[i],
                  recent_revenue  = CORR$recent_revenue[i],
                  ratio_to_revenue = CORR$ratio_to_revenue[i])]
    matched <- matched + 1L
  }
}
cat(sprintf("[fq002] 정정 매칭: %d/%d (매칭 실패 %d = Panel B 미반영)\n",
            matched, nrow(CORR), nrow(CORR) - matched))

CKDIR_B <- file.path(tempdir(), "fq002_ckpt_B"); dir.create(CKDIR_B, showWarnings = FALSE)
for (m in unique(B_sub$ym)) fwrite(B_sub[ym == m][, rc_dt := NULL], file.path(CKDIR_B, paste0(m, ".csv")))

# ── 패널 빌드 (정본 빌더 재사용 — 로직 이원화 금지) ─────────────────────────
build_panel <- function(ckdir, out, window = 12L, scope = "all") {
  keys <- c("CONTRACT_CKDIR", "CONTRACT_PANEL_OUT", "WINDOW_M", "SCOPE", "CLAUDE_PROJECT_DIR")
  old  <- vapply(keys, function(k) Sys.getenv(k, unset = NA_character_), character(1))
  on.exit(for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else
            do.call(Sys.setenv, setNames(list(old[[k]]), k)), add = TRUE)
  Sys.setenv(CONTRACT_CKDIR = ckdir, CONTRACT_PANEL_OUT = out,
             WINDOW_M = as.character(window), SCOPE = scope, CLAUDE_PROJECT_DIR = ROOT)
  log <- suppressWarnings(system2("Rscript",
           args = "02_Infrastructure/alpha_search/build_contract_panel.R",
           stdout = TRUE, stderr = TRUE))
  if (!file.exists(out)) stop("panel build 실패: ", paste(tail(log, 3), collapse = " | "))
  invisible(log)
}
PA <- file.path(OUTD, "panel_A.parquet"); PB <- file.path(OUTD, "panel_B_corrected.parquet")
build_panel(CKDIR,   PA)
build_panel(CKDIR_B, PB)
panelA <- as.data.table(read_parquet(PA))
panelB <- as.data.table(read_parquet(PB))
cat(sprintf("[fq002] Panel A %d행 / Panel B %d행\n", nrow(panelA), nrow(panelB)))

# ── 측정 그리드 (신선 빈티지 — build_fq002_grid.R 산출. wt005 grid 는 07-03 pin 이라
#    2026-07 폭락월 미편입 → 소비 금지. grid_vintage.txt 에 빈티지 기록) ─────────
Rg <- as.data.table(read_parquet(file.path(OUTD, "grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "grid_bench.parquet")));  Bg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "grid_liq.parquet")));    Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "grid_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
SZ <- MEM[, .(Date, Ticker, Size)]
GRID_VINTAGE <- readLines(file.path(OUTD, "grid_vintage.txt"))[1]
ym_of <- function(d) format(d, "%Y%m")
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]

# 신호 스코어 테이블: (Date, Ticker, score) — 월말 Date 에 패널 ym 조인
mk_scores <- function(panel, denom = c("revenue", "size")) {
  denom <- match.arg(denom)
  S <- merge(me_dates, panel[, .(ym, Ticker, w_amt, w_ratio)], by = "ym")
  if (denom == "revenue") { S[, score := w_ratio] } else {
    S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
    S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
  }
  # 멤버십 필터 (K200∪KQ150 at sig date — PIT 시변) + 유동성 필터 (t-1 30d ADV)
  S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
  S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
  S <- S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0,
         .(Date, Ticker, score)]
  S
}

# ── IC + FMB (진단 통계) ─────────────────────────────────────────────────────
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 8) return(NA_real_)
  m <- mean(x); e <- x - m; v <- sum(e^2) / n
  for (l in 1:lag) { if (l >= n) break
    cv <- sum(e[1:(n - l)] * e[(l + 1):n]) / n; v <- v + 2 * (1 - l / (lag + 1)) * cv }
  se <- sqrt(v / n); if (!is.finite(se) || se <= 0) return(NA_real_); m / se
}
ic_stats <- function(S, min_n = 8L) {
  M <- merge(S, Rg, by = c("Date", "Ticker"))
  M <- M[is.finite(Ret_1m)]
  # canonical_screen_bt 와 동일한 Ret_1m sanity 격리 (물리불가 월수익 — FMB 선형회귀 왜곡 방지)
  n_q <- nrow(M[Ret_1m > 5 | Ret_1m < -1])
  if (n_q > 0) cat(sprintf("  [ic] Ret_1m sanity 격리 %d행\n", n_q))
  M <- M[Ret_1m <= 5 & Ret_1m >= -1]
  ics <- M[, .(n = .N, ic = if (.N >= min_n) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_,
               lam = if (.N >= min_n) {
                 z <- (rank(score) - mean(rank(score))) / sd(rank(score))
                 fit <- tryCatch(coef(summary(lm(Ret_1m ~ z)))["z", ], error = function(e) c(NA, NA, NA, NA))
                 fit[1]
               } else NA_real_), by = Date]
  ics <- ics[is.finite(ic)]
  list(n_months = nrow(ics), mean_ic = mean(ics$ic), sd_ic = sd(ics$ic),
       t_plain = mean(ics$ic) / sd(ics$ic) * sqrt(nrow(ics)),
       t_nw    = nw_t(ics$ic),
       icir    = mean(ics$ic) / sd(ics$ic),
       fmb_lambda_mean = mean(ics$lam, na.rm = TRUE),
       fmb_t = { l <- ics$lam[is.finite(ics$lam)]
                 if (length(l) >= 8) mean(l) / sd(l) * sqrt(length(l)) else NA_real_ },
       pos_share = mean(ics$ic > 0),
       mean_names = mean(ics$n),
       ic_series = ics[, .(Date = as.character(Date), n, ic)])
}

cells <- list(
  A_revenue = mk_scores(panelA, "revenue"),
  A_size    = mk_scores(panelA, "size"),
  B_revenue = mk_scores(panelB, "revenue"),
  B_size    = mk_scores(panelB, "size")
)
IC <- lapply(cells, ic_stats)

# lag1 스트레스 (primary A_revenue): 신호를 1개월 늦게 적용 — base 대비 붕괴 = 동월누출 의심
lag1_scores <- local({
  S <- cells$A_revenue
  key <- me_dates[order(Date)]
  key[, Date_next := shift(Date, -1)]
  S2 <- merge(S, key[, .(Date, Date_next)], by = "Date")
  S2[!is.na(Date_next), .(Date = Date_next, Ticker, score)]
})
IC$A_revenue_lag1 <- ic_stats(lag1_scores)

# 정정 A/B 대조 (paired, 월별 IC 차)
ab <- merge(IC$A_revenue$ic_series[, .(Date, ic_A = ic)],
            IC$B_revenue$ic_series[, .(Date, ic_B = ic)], by = "Date")
ab_diff <- ab$ic_B - ab$ic_A
correction_ab <- list(n = nrow(ab), mean_diff_B_minus_A = mean(ab_diff),
                      t_paired = if (nrow(ab) >= 8) mean(ab_diff) / sd(ab_diff) * sqrt(nrow(ab)) else NA_real_)

# ── canonical_screen_bt 실측 (참고 — 파일럿 표본 얇음) ──────────────────────
canon <- function(S, id) {
  canonical_screen_bt(S[, .(Date, Ticker, score)], Rg, Bg, top_n = 20L,
                      cost_bps_oneway = 15, liq_dt = Lg, liq_min = 2e8,
                      run_id = id, strategy_id = id, periods_per_year = 12L,
                      diag_dual_basis = TRUE, size_dt = SZ)
}
CN <- list(A_revenue = canon(cells$A_revenue, "fq002_A_rev"),
           A_size    = canon(cells$A_size,    "fq002_A_size"),
           A_revenue_lag1 = canon(lag1_scores, "fq002_A_rev_lag1"))

# ── 커버리지 실측 ────────────────────────────────────────────────────────────
cov_m <- cells$A_revenue[, .(n_cov = .N), by = Date][order(Date)]
coverage <- list(mean_names = mean(cov_m$n_cov), min_names = min(cov_m$n_cov),
                 months_ge20 = mean(cov_m$n_cov >= 20), months_ge10 = mean(cov_m$n_cov >= 10),
                 n_months = nrow(cov_m),
                 monthly = cov_m[, .(Date = as.character(Date), n_cov)])

# ── 저장 ─────────────────────────────────────────────────────────────────────
strip_cn <- function(x) x[setdiff(names(x), c("benchmark_compare"))]
out <- list(
  task_id = "WT-D20260802_018", measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg = "04_Research/method_frontier/fq002_contract_magnitude_prereg.md",
  window_m = 12L, scope = "all", n_holdings = 20L, pilot_scope = "2023-08..2026-07 crawl",
  grid_vintage = GRID_VINTAGE,
  ic = lapply(IC, function(z) z[setdiff(names(z), "ic_series")]),
  ic_series = lapply(IC, `[[`, "ic_series"),
  correction_ab = correction_ab,
  canonical = lapply(CN, strip_cn),
  coverage = coverage
)
write_json(out, file.path(OUTD, "pilot_results.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 6, null = "null")
cat("\n=== FQ-002 파일럿 결과 요약 ===\n")
for (nm in names(IC)) {
  z <- IC[[nm]]
  cat(sprintf("%-16s n=%2d  meanIC=%+.4f  t=%+.2f (NW %+.2f)  FMB_t=%+.2f  pos%%=%.0f%%  names/m=%.0f\n",
              nm, z$n_months, z$mean_ic, z$t_plain, z$t_nw, z$fmb_t, 100 * z$pos_share, z$mean_names))
}
cat(sprintf("정정 A/B: mean(B-A)=%+.4f paired_t=%+.2f (n=%d)\n",
            correction_ab$mean_diff_B_minus_A, correction_ab$t_paired, correction_ab$n))
for (nm in names(CN)) {
  z <- CN[[nm]]
  cat(sprintf("canonical %-16s: PORT_t=%+.2f n=%d net_sr=%+.2f TO=%.1f | EW-uni t=%+.2f\n", nm,
              z$portfolio_alpha_t_nw_lag3, z$n_months, z$net_sr, z$turnover_annual,
              tryCatch(z$diag_ew_universe$portfolio_alpha_t_nw_lag3, error = function(e) NA_real_)))
}
cat(sprintf("커버리지: 평균 %.0f종/월 | ≥20종 월비율 %.0f%% | ≥10종 %.0f%%\n",
            coverage$mean_names, 100 * coverage$months_ge20, 100 * coverage$months_ge10))
cat("[fq002] → ", file.path(OUTD, "pilot_results.json"), "\n")
