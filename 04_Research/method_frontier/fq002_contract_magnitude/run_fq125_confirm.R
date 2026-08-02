# =============================================================================
# run_fq125_confirm.R — FQ-125 시총-분모 primary 확정 라운드 (WT-D20260802_023)
#
# 사전등록: qepm/mailbox/worktask/WT-D20260802_023/preregistration.json (측정 전 고정)
#   · primary = CTR_MAG_12M_MCAP = w_amt / Size (panel_A 최초 체결값, SCOPE=all)
#   · 판정 = 섭동 분포 q05 (FQ-109 규약): 멤버십 drop p=0.10 60시드 + 스코어
#     rank-z N(0,0.10^2) 60시드 → draw별 IC 시계열 t_NW(lag3) pooled q05 > 0
#   · WT-018 parity 의무: A_size mean_ic 0.080559 / t_plain 1.972226 재현 (불일치 STOP)
#   · 재크롤·재파싱 없음 — 패널·grid 전부 WT-018 산출 재사용 (빈티지 고정)
#
# 측정 규율: IC = 진단 통계(cor(), 백테스트 자체합성 아님). 포트 실측은
#   canonical_screen_bt() 경유(metric_type=canonical_screen)만.
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
WT   <- "WT-D20260802_023"
STG  <- file.path("stage_artifacts", paste0("WT_", gsub("^WT-", "", WT)))
dir.create(STG, recursive = TRUE, showWarnings = FALSE)

source("02_Infrastructure/contracts/canonical_screen_bt.R")

# ── 승계 자산 로드 (재크롤 없음) ─────────────────────────────────────────────
panelA <- as.data.table(read_parquet(file.path(OUTD, "panel_A.parquet")))
panelB <- as.data.table(read_parquet(file.path(OUTD, "panel_B_corrected.parquet")))
Rg <- as.data.table(read_parquet(file.path(OUTD, "grid_returns.parquet"))); Rg[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "grid_bench.parquet")));  Bg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "grid_liq.parquet")));    Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "grid_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
SZ <- MEM[, .(Date, Ticker, Size)]
GRID_VINTAGE <- readLines(file.path(OUTD, "grid_vintage.txt"))[1]
ym_of <- function(d) format(d, "%Y%m")
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]

# ── 스코어 (WT-018 mk_scores 동일 로직 — 로직 이원화 금지) ───────────────────
mk_scores <- function(panel, denom = c("revenue", "size")) {
  denom <- match.arg(denom)
  S <- merge(me_dates, panel[, .(ym, Ticker, w_amt, w_ratio)], by = "ym")
  if (denom == "revenue") { S[, score := w_ratio] } else {
    S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
    S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
  }
  S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
  S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
  S <- S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0,
         .(Date, Ticker, score)]
  S
}

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
  M <- M[Ret_1m <= 5 & Ret_1m >= -1]   # WT-018 동일 sanity 격리
  ics <- M[, .(n = .N, ic = if (.N >= min_n) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_),
           by = Date]
  ics <- ics[is.finite(ic)]
  list(n_months = nrow(ics), mean_ic = mean(ics$ic), sd_ic = sd(ics$ic),
       t_plain = mean(ics$ic) / sd(ics$ic) * sqrt(nrow(ics)),
       t_nw = nw_t(ics$ic), icir = mean(ics$ic) / sd(ics$ic),
       pos_share = mean(ics$ic > 0), mean_names = mean(ics$n),
       ic_series = ics[, .(Date = as.character(Date), n, ic)])
}

SA <- mk_scores(panelA, "size")
SB <- mk_scores(panelB, "size")
IC_A <- ic_stats(SA)
IC_B <- ic_stats(SB)

# ── ★ WT-018 parity 검증 (사전등록 STOP 조건) ────────────────────────────────
stopifnot(abs(IC_A$mean_ic - 0.080559) < 1e-5,
          abs(IC_A$t_plain - 1.972226) < 1e-4,
          IC_A$n_months == 24L)
cat(sprintf("[fq125] parity PASS: A_size meanIC=%.6f t_plain=%.6f t_NW=%.4f (WT-018 정확 재현)\n",
            IC_A$mean_ic, IC_A$t_plain, IC_A$t_nw))

# ── 섭동 판정 (사전등록: drop 0.10 / noise 0.10 / 60시드×2가족 고정) ─────────
Mbase <- merge(SA, Rg, by = c("Date", "Ticker"))
Mbase <- Mbase[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]
setorder(Mbase, Date, Ticker)

ic_of <- function(M, min_n = 8L) {
  ics <- M[, .(ic = if (.N >= min_n) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_),
           by = Date]
  ics$ic[is.finite(ics$ic)]
}

N_SEED <- 60L; DROP_P <- 0.10; NOISE_SD <- 0.10
draws <- list()
for (s in seq_len(N_SEED)) {                        # family M: 멤버십 drop
  set.seed(1000L + s)
  Mp <- Mbase[runif(.N) >= DROP_P]
  v <- ic_of(Mp)
  draws[[length(draws) + 1L]] <- data.table(family = "M", seed = s,
    t_nw = nw_t(v), mean_ic = mean(v), n_months = length(v))
}
for (s in seq_len(N_SEED)) {                        # family S: rank-z + noise
  set.seed(2000L + s)
  Mp <- copy(Mbase)
  Mp[, rz := { r <- rank(score); (r - mean(r)) / max(sd(r), 1e-12) }, by = Date]
  Mp[, score := rz + rnorm(.N, 0, NOISE_SD)]
  v <- ic_of(Mp)
  draws[[length(draws) + 1L]] <- data.table(family = "S", seed = s,
    t_nw = nw_t(v), mean_ic = mean(v), n_months = length(v))
}
DR <- rbindlist(draws)
q05_pool <- quantile(DR$t_nw, 0.05, type = 7, names = FALSE)
q05_M    <- quantile(DR[family == "M", t_nw], 0.05, type = 7, names = FALSE)
q05_S    <- quantile(DR[family == "S", t_nw], 0.05, type = 7, names = FALSE)
q05_ic   <- quantile(DR$mean_ic, 0.05, type = 7, names = FALSE)
confirmed  <- is.finite(q05_pool) && q05_pool > 0
pay_reco   <- confirmed && q05_M > 0 && q05_S > 0

cat(sprintf("[fq125] 섭동 %d draws: t_NW q05 pooled=%+.4f (M=%+.4f / S=%+.4f) | mean_ic q05=%+.5f\n",
            nrow(DR), q05_pool, q05_M, q05_S, q05_ic))
cat(sprintf("[fq125] draw t_NW 분포: min=%+.3f q25=%+.3f med=%+.3f q75=%+.3f max=%+.3f sd=%.3f\n",
            min(DR$t_nw), quantile(DR$t_nw, .25, names = FALSE), median(DR$t_nw),
            quantile(DR$t_nw, .75, names = FALSE), max(DR$t_nw), sd(DR$t_nw)))
cat(sprintf("[fq125] ★판정: q05>0 %s → %s | 전구간 크롤 지불 권고 = %s\n",
            ifelse(confirmed, "충족", "미충족"),
            ifelse(confirmed, "확정(lead 확립)", "미확정"),
            ifelse(pay_reco, "권고", "비권고")))

# ── 보조 진단 (병기 — primary 판정 불변) ─────────────────────────────────────
# 1) 정정 A/B (size 셀 paired — WT-018은 revenue 셀만 paired 산출)
ab <- merge(IC_A$ic_series[, .(Date, ic_A = ic)],
            IC_B$ic_series[, .(Date, ic_B = ic)], by = "Date")
d <- ab$ic_B - ab$ic_A
corr_ab_size <- list(n = nrow(ab), mean_diff_B_minus_A = mean(d),
                     t_paired = if (nrow(ab) >= 8) mean(d) / sd(d) * sqrt(nrow(ab)) else NA_real_)

# 2) lag1 스트레스 (A_size — C5)
lag1 <- local({
  key <- me_dates[order(Date)]; key[, Date_next := shift(Date, -1)]
  S2 <- merge(SA, key[, .(Date, Date_next)], by = "Date")
  S2[!is.na(Date_next), .(Date = Date_next, Ticker, score)]
})
IC_lag1 <- ic_stats(lag1)

# 3) 부기간 (전반 12 / 후반 12)
half <- local({
  v <- IC_A$ic_series[order(Date)]
  h1 <- v$ic[1:12]; h2 <- v$ic[13:24]
  list(first12 = list(mean_ic = mean(h1), t_plain = mean(h1) / sd(h1) * sqrt(12)),
       last12  = list(mean_ic = mean(h2), t_plain = mean(h2) / sd(h2) * sqrt(12)))
})

# 4) canonical dual-basis (재실측 — WT-018 parity 확인용)
CN <- canonical_screen_bt(SA[, .(Date, Ticker, score)], Rg, Bg, top_n = 20L,
                          cost_bps_oneway = 15, liq_dt = Lg, liq_min = 2e8,
                          run_id = "fq125_A_size", strategy_id = "fq125_A_size",
                          periods_per_year = 12L, diag_dual_basis = TRUE, size_dt = SZ)
cat(sprintf("[fq125] canonical A_size: cap-w PORT_t=%+.3f | EW-uni t=%+.3f (WT-018: -0.371 / +1.488)\n",
            CN$portfolio_alpha_t_nw_lag3, CN$diag_ew_universe$portfolio_alpha_t_nw_lag3))

# 5) 커버리지
cov_m <- SA[, .(n_cov = .N), by = Date][order(Date)]

# ── alpha_scores (최신 시그널월 단면, primary = A_size) ──────────────────────
last_ym <- max(panelA$ym); last_me <- MEM[, max(Date)]
Sx <- panelA[ym == last_ym, .(Ticker, w_amt, w_n)]
Sx <- merge(Sx, MEM[Date == last_me, .(Ticker, Size)], by = "Ticker")
Sx <- merge(Sx, Lg[Date == last_me, .(Ticker, adv)], by = "Ticker", all.x = TRUE)
Sx <- Sx[!is.na(adv) & adv >= 2e8 & is.finite(Size) & Size > 0 & w_amt > 0]
Sx[, score := w_amt / Size]
zs <- (rank(Sx$score) - mean(rank(Sx$score))) / max(sd(rank(Sx$score)), 1e-12)
Sx[, alpha := IC_A$mean_ic * zs * 0.06]   # 실측 meanIC × 단면 산포 선형 맵 (진단 스케일)
Sx[, confidence := pmin(1, pmax(0.2, 0.4 + 0.05 * pmin(w_n, 6)))]
setorder(Sx, -alpha)
write_parquet(Sx[, .(Date = last_me, Ticker, score, alpha, confidence)],
              file.path(STG, "alpha_scores.parquet"))

# ── 저장 ─────────────────────────────────────────────────────────────────────
strip_cn <- function(x) x[setdiff(names(x), c("benchmark_compare"))]
out <- list(
  task_id = WT, measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  prereg = "qepm/mailbox/worktask/WT-D20260802_023/preregistration.json",
  grid_vintage = GRID_VINTAGE, panel_reuse = "WT-D20260802_018 panel_A/B (재크롤 없음)",
  parity_wt018 = list(pass = TRUE, mean_ic = IC_A$mean_ic, t_plain = IC_A$t_plain),
  perturbation = list(
    protocol = list(n_seeds_per_family = N_SEED, drop_p = DROP_P, noise_sd = NOISE_SD,
                    statistic = "t_NW(lag3) of monthly IC series", q05_type = 7),
    q05_t_nw_pooled = q05_pool, q05_t_nw_family_M = q05_M, q05_t_nw_family_S = q05_S,
    q05_mean_ic_pooled = q05_ic,
    t_nw_summary = list(min = min(DR$t_nw), q25 = quantile(DR$t_nw, .25, names = FALSE),
                        median = median(DR$t_nw), q75 = quantile(DR$t_nw, .75, names = FALSE),
                        max = max(DR$t_nw), sd = sd(DR$t_nw)),
    draws = DR),
  verdict = list(confirmed_q05_gt0 = confirmed,
                 full_crawl_payment_recommended = pay_reco,
                 rule = "사전등록: pooled q05(t_NW)>0 = 확정 / 지불 권고는 양 가족 q05>0 추가"),
  ic = list(A_size = IC_A[setdiff(names(IC_A), "ic_series")],
            B_size = IC_B[setdiff(names(IC_B), "ic_series")],
            A_size_lag1 = IC_lag1[setdiff(names(IC_lag1), "ic_series")]),
  ic_series = list(A_size = IC_A$ic_series),
  correction_ab_size = corr_ab_size,
  subperiod_halves = half,
  canonical_A_size = strip_cn(CN),
  coverage = list(mean_names = mean(cov_m$n_cov), min_names = min(cov_m$n_cov),
                  months_ge20 = mean(cov_m$n_cov >= 20), n_months = nrow(cov_m))
)
write_json(out, file.path(OUTD, "fq125_confirm_results.json"), pretty = TRUE,
           auto_unbox = TRUE, digits = 6, null = "null")
cat("[fq125] → ", file.path(OUTD, "fq125_confirm_results.json"), "\n")
cat("[fq125] → ", file.path(STG, "alpha_scores.parquet"), "\n")
