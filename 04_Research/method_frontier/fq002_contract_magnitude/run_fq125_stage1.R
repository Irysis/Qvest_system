# =============================================================================
# run_fq125_stage1.R — FQ-125 1단계 확정 판정 (WT-D20260803_008)
#
# 판정 규칙은 WT-D20260802_023 이 **측정 전에** 고정했다 (사후 변경 금지):
#   · 통과 : 합산 t_NW >= 1.5  AND  신규 구간 mean IC > 0  AND  국면 분해 수행
#   · abort: 합산 t_NW <  1.0
#   · 사이 (1.0 <= t_NW < 1.5) = 미확정 — 그대로 보고
#
# 신호/스코어/필터 로직은 WT-018/023 과 **완전 동일** (mk_scores·ic_stats·nw_t 복제,
# 로직 이원화 금지). 바뀐 것은 창(2019-12~) 과 그리드 파일뿐.
#
# 측정 규율: IC = 진단 통계(cor()). 포트 실측은 canonical_screen_bt() 만
#   (metric_type="canonical_screen"). proxy 손계산·자체합성 없음.
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
WT   <- "WT-D20260803_008"
STG  <- file.path("stage_artifacts", paste0("WT_", gsub("^WT-", "", WT)))
dir.create(STG, recursive = TRUE, showWarnings = FALSE)
source("02_Infrastructure/contracts/canonical_screen_bt.R")

CKDIR <- ".cache/dart/contract_backfill"
YM_MIN <- 201901L   # ★pre-2019 제외 사유는 아래 census 게이트에서 실측 확인 후 기록

# ── 0) 체크포인트 코퍼스 게이트 ──────────────────────────────────────────────
fs <- list.files(CKDIR, pattern = "^\\d{6}\\.csv$", full.names = TRUE)
raw <- rbindlist(lapply(fs, function(f) fread(f, colClasses = list(character = "corp_code"))), fill = TRUE)
D <- raw[!is.na(rcept_no)]
NO_SOURCE <- c("NO_SOURCE_CORRECTION", "NO_SOURCE_014")
census <- D[, .(rows = .N, ok = sum(parse_status == "OK"),
                no_source = sum(parse_status %in% NO_SOURCE),
                parse_fail = sum(!parse_status %in% c("OK", NO_SOURCE))),
            by = .(era = fifelse(ym >= 201901L, "usable_2019plus", "pre2019"))]
print(census)
pre <- census[era == "pre2019"]
if (nrow(pre)) cat(sprintf("[stage1] ★pre-2019(%d행): OK %d (%.1f%%) — 파싱 실패 %d건으로 사용 불가 → 제외\n",
                           pre$rows, pre$ok, 100 * pre$ok / pre$rows, pre$parse_fail))
Duse <- D[ym >= YM_MIN]
n_avail <- nrow(Duse[!parse_status %in% NO_SOURCE])
cat(sprintf("[stage1] 사용 코퍼스 %d행 / %d개월 | 원문제공 %d 중 OK %d (%.1f%%)\n",
            nrow(Duse), uniqueN(Duse$ym), n_avail, nrow(Duse[parse_status == "OK"]),
            100 * nrow(Duse[parse_status == "OK"]) / n_avail))
# 월 결측 0 단언 (개수 아닌 distinct-YM)
exp_ym <- as.integer(format(seq(as.Date("2019-01-01"), as.Date("2026-07-01"), by = "month"), "%Y%m"))
stopifnot(length(setdiff(exp_ym, unique(Duse$ym))) == 0L)

# ── 1) 패널 A / B 빌드 (정본 빌더 재사용 — 로직 이원화 금지) ─────────────────
# Panel A = 최초 체결값만 (is_correction 제외)  = PIT 정본
# Panel B = 정정 반영값을 **최초 공시일에 소급 주입** = ★위반 주입 (사후 정보 누출)
ORIG <- Duse[is_correction == FALSE & parse_status == "OK"]
CORR <- Duse[is_correction == TRUE  & parse_status == "OK"]
CORR[, rc_dt := as.IDate(as.character(rcept_dt), "%Y%m%d")]
ORIG[, rc_dt := as.IDate(as.character(rcept_dt), "%Y%m%d")]
setorder(CORR, corp_code, rc_dt)
B_sub <- copy(ORIG); matched <- 0L
if (nrow(CORR)) for (i in seq_len(nrow(CORR))) {
  cc <- CORR$corp_code[i]; cd <- CORR$rc_dt[i]
  cand <- B_sub[corp_code == cc & rc_dt < cd & rc_dt >= cd - 180L]
  if (!nrow(cand)) next
  j <- which(B_sub$rcept_no == cand[which.max(rc_dt), rcept_no])[1]
  B_sub[j, `:=`(contract_amount = CORR$contract_amount[i], recent_revenue = CORR$recent_revenue[i],
                ratio_to_revenue = CORR$ratio_to_revenue[i])]
  matched <- matched + 1L
}
cat(sprintf("[stage1] 정정 매칭(위반 주입용): %d/%d\n", matched, nrow(CORR)))

mkdir_ck <- function(nm, DT) {
  d <- file.path(tempdir(), nm); dir.create(d, showWarnings = FALSE)
  file.remove(list.files(d, full.names = TRUE))
  for (m in unique(DT$ym)) fwrite(DT[ym == m][, rc_dt := NULL], file.path(d, paste0(m, ".csv")))
  d
}
CK_A <- mkdir_ck("fq125s1_A", copy(ORIG))
CK_B <- mkdir_ck("fq125s1_B", copy(B_sub))

build_panel <- function(ckdir, out, window = 12L, scope = "all") {
  keys <- c("CONTRACT_CKDIR", "CONTRACT_PANEL_OUT", "WINDOW_M", "SCOPE", "CLAUDE_PROJECT_DIR")
  old  <- vapply(keys, function(k) Sys.getenv(k, unset = NA_character_), character(1))
  on.exit(for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else
            do.call(Sys.setenv, setNames(list(old[[k]]), k)), add = TRUE)
  Sys.setenv(CONTRACT_CKDIR = ckdir, CONTRACT_PANEL_OUT = out, WINDOW_M = as.character(window),
             SCOPE = scope, CLAUDE_PROJECT_DIR = ROOT)
  log <- suppressWarnings(system2("Rscript", args = "02_Infrastructure/alpha_search/build_contract_panel.R",
                                  stdout = TRUE, stderr = TRUE))
  if (!file.exists(out)) stop("panel build 실패: ", paste(tail(log, 4), collapse = " | "))
  invisible(log)
}
PA <- file.path(OUTD, "panelx_A.parquet"); PB <- file.path(OUTD, "panelx_B_corrected.parquet")
if (file.exists(PA)) file.remove(PA); if (file.exists(PB)) file.remove(PB)
build_panel(CK_A, PA); build_panel(CK_B, PB)
panelA <- as.data.table(read_parquet(PA)); panelB <- as.data.table(read_parquet(PB))
cat(sprintf("[stage1] Panel A %d행 (ym %s~%s, %d종목) / Panel B %d행\n",
            nrow(panelA), min(panelA$ym), max(panelA$ym), uniqueN(panelA$Ticker), nrow(panelB)))

# ── 2) 그리드 로드 (확장 빈티지) ─────────────────────────────────────────────
Rg <- as.data.table(read_parquet(file.path(OUTD, "gridx_returns.parquet"))); Rg[, Date := as.Date(Date)]
Bg <- as.data.table(read_parquet(file.path(OUTD, "gridx_bench.parquet")));   Bg[, Date := as.Date(Date)]
Lg <- as.data.table(read_parquet(file.path(OUTD, "gridx_liq.parquet")));     Lg[, Date := as.Date(Date)]
MEM <- as.data.table(read_parquet(file.path(OUTD, "gridx_universe_size.parquet"))); MEM[, Date := as.Date(Date)]
SZ <- MEM[, .(Date, Ticker, Size)]
GRID_VINTAGE <- readLines(file.path(OUTD, "gridx_vintage.txt"))[1]
ym_of <- function(d) format(d, "%Y%m")
me_dates <- Rg[, .(Date = max(Date)), by = .(ym = ym_of(Date))]

# ── 3) 스코어·IC (WT-018/023 동일 로직) ──────────────────────────────────────
mk_scores <- function(panel, denom = c("revenue", "size")) {
  denom <- match.arg(denom)
  S <- merge(me_dates, panel[, .(ym, Ticker, w_amt, w_ratio)], by = "ym")
  if (denom == "revenue") { S[, score := w_ratio] } else {
    S <- merge(S, SZ, by = c("Date", "Ticker"), all.x = TRUE)
    S[, score := ifelse(is.finite(Size) & Size > 0, w_amt / Size, NA_real_)]
  }
  S <- merge(S, MEM[, .(Date, Ticker, member = TRUE)], by = c("Date", "Ticker"), all.x = TRUE)
  S <- merge(S, Lg, by = c("Date", "Ticker"), all.x = TRUE)
  S[member %in% TRUE & !is.na(adv) & adv >= 2e8 & is.finite(score) & score > 0, .(Date, Ticker, score)]
}
nw_t <- function(x, lag = 3L) {
  x <- x[is.finite(x)]; n <- length(x); if (n < 8) return(NA_real_)
  m <- mean(x); e <- x - m; v <- sum(e^2) / n
  for (l in 1:lag) { if (l >= n) break
    cv <- sum(e[1:(n - l)] * e[(l + 1):n]) / n; v <- v + 2 * (1 - l / (lag + 1)) * cv }
  se <- sqrt(v / n); if (!is.finite(se) || se <= 0) return(NA_real_); m / se
}
ic_series_of <- function(S, min_n = 8L) {
  M <- merge(S, Rg, by = c("Date", "Ticker"))
  M <- M[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]
  ics <- M[, .(n = .N, ic = if (.N >= min_n) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_),
           by = Date]
  ics[is.finite(ic)][order(Date)]
}
summ_ic <- function(ics) {
  if (!nrow(ics)) return(list(n_months = 0L))
  list(n_months = nrow(ics), mean_ic = mean(ics$ic), sd_ic = sd(ics$ic),
       t_plain = mean(ics$ic) / sd(ics$ic) * sqrt(nrow(ics)), t_nw = nw_t(ics$ic),
       icir = mean(ics$ic) / sd(ics$ic), pos_share = mean(ics$ic > 0), mean_names = mean(ics$n))
}

SA <- mk_scores(panelA, "size"); SB <- mk_scores(panelB, "size")
ICS_A <- ic_series_of(SA); ICS_B <- ic_series_of(SB)
cat(sprintf("[stage1] IC 월수: A=%d (%s~%s)\n", nrow(ICS_A),
            format(min(ICS_A$Date)), format(max(ICS_A$Date))))

# ── 3b) ★파일럿 parity (승계 자산 정확 재현) ────────────────────────────────
PILOT_START <- as.Date("2024-07-01")   # 기존 panel_A ym 최소 = 202407
pil <- ICS_A[Date >= PILOT_START]
pil_s <- summ_ic(pil)
parity_ok <- is.finite(pil_s$mean_ic) && abs(pil_s$mean_ic - 0.080559) < 1e-5 &&
             abs(pil_s$t_plain - 1.972226) < 1e-4 && pil_s$n_months == 24L
cat(sprintf("[stage1] parity(파일럿 24M): meanIC=%.6f (기대 0.080559) t_plain=%.6f (기대 1.972226) n=%d → %s\n",
            pil_s$mean_ic, pil_s$t_plain, pil_s$n_months, ifelse(parity_ok, "PASS", "★MISMATCH")))
if (!parity_ok) cat("[stage1] ⚠ parity 불일치 — 승계 구간 값이 달라졌다. 원인 병기 후 진행(중단 아님, 확장 라운드).\n")

# ── 4) ★게이트 판정 (사전 고정 규칙) ────────────────────────────────────────
comb <- summ_ic(ICS_A)
new_seg <- ICS_A[Date < PILOT_START]; new_s <- summ_ic(new_seg)
t_nw_comb <- comb$t_nw
verdict <- if (!is.finite(t_nw_comb)) "INDETERMINATE_NA" else
           if (t_nw_comb < 1.0) "ABORT" else
           if (t_nw_comb >= 1.5 && is.finite(new_s$mean_ic) && new_s$mean_ic > 0) "PASS" else
           "INDETERMINATE"
cat(sprintf("\n[stage1] ★★합산 n=%d | mean IC=%+.5f | t_plain=%+.4f | t_NW(lag3)=%+.4f | ICIR=%+.4f | pos=%.1f%%\n",
            comb$n_months, comb$mean_ic, comb$t_plain, comb$t_nw, comb$icir, 100 * comb$pos_share))
cat(sprintf("[stage1] ★★신규 구간 n=%d | mean IC=%+.5f | t_NW=%+.4f | pos=%.1f%%\n",
            new_s$n_months, new_s$mean_ic, new_s$t_nw, 100 * new_s$pos_share))
cat(sprintf("[stage1] ★★게이트 판정 = %s  (통과 t_NW>=1.5 & 신규 meanIC>0 / abort t_NW<1.0)\n\n", verdict))

# ── 5) 국면 분해 (게이트 필수 조건) ─────────────────────────────────────────
# 5-A. 벤치 상승/하락 · 위기
IX <- merge(ICS_A, Bg, by = "Date")
# 5-B. mega-cap 랠리 지표: 시총 top-10 평균수익 − 유니버스 중앙수익 (홀딩월)
megasp <- local({
  X <- merge(Rg, SZ, by = c("Date", "Ticker"))
  X <- X[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1 & is.finite(Size)]
  X[, rk := frank(-Size, ties.method = "first"), by = Date]
  X[, .(mega_spread = mean(Ret_1m[rk <= 10]) - median(Ret_1m),
        size_ret_rho = suppressWarnings(cor(Size, Ret_1m, method = "spearman"))), by = Date]
})
IX <- merge(IX, megasp, by = "Date", all.x = TRUE)
IX <- merge(IX, SA[, .(n_cov = .N), by = Date], by = "Date", all.x = TRUE)
IX[, era := fifelse(Date >= PILOT_START, "pilot", "new")]

bucket <- function(dt, lab) if (!nrow(dt)) list(bucket = lab, n = 0L) else
  list(bucket = lab, n = nrow(dt), mean_ic = mean(dt$ic), t_plain = if (nrow(dt) >= 3)
       mean(dt$ic) / sd(dt$ic) * sqrt(nrow(dt)) else NA_real_, pos_share = mean(dt$ic > 0))
regime <- list(
  corr_ic_bench      = cor(IX$ic, IX$BM_Ret),
  corr_ic_megaspread = cor(IX$ic, IX$mega_spread, use = "complete.obs"),
  corr_ic_sizerho    = cor(IX$ic, IX$size_ret_rho, use = "complete.obs"),
  corr_ic_ncov       = cor(IX$ic, IX$n_cov, use = "complete.obs"),
  by_bench   = list(bucket(IX[BM_Ret > 0], "bench_up"), bucket(IX[BM_Ret <= 0], "bench_down"),
                    bucket(IX[BM_Ret > 0.05], "bench_up5"), bucket(IX[BM_Ret < -0.05], "bench_down5")),
  by_mega    = list(bucket(IX[mega_spread > 0], "mega_led"), bucket(IX[mega_spread <= 0], "broad_led"),
                    bucket(IX[mega_spread > quantile(IX$mega_spread, .75, na.rm = TRUE)], "mega_top_quartile")),
  by_era     = list(bucket(IX[era == "new"], "new_2019_12_2024_06"), bucket(IX[era == "pilot"], "pilot_2024_07plus")),
  by_year    = IX[, .(n = .N, mean_ic = mean(ic), pos = mean(ic > 0), mean_bm = mean(BM_Ret),
                      mean_mega = mean(mega_spread, na.rm = TRUE)), by = .(yr = format(Date, "%Y"))][order(yr)]
)
cat("[stage1] 국면 corr: IC~BM %+.4f | IC~mega_spread %+.4f | IC~size_rho %+.4f | IC~n_cov %+.4f\n",
    regime$corr_ic_bench, regime$corr_ic_megaspread, regime$corr_ic_sizerho, regime$corr_ic_ncov)
cat(sprintf("[stage1] 국면 corr: IC~BM %+.4f | IC~mega %+.4f | IC~size_rho %+.4f | IC~ncov %+.4f\n",
            regime$corr_ic_bench, regime$corr_ic_megaspread, regime$corr_ic_sizerho, regime$corr_ic_ncov))
print(regime$by_year)
for (b in c(regime$by_bench, regime$by_mega, regime$by_era))
  if (b$n > 0) cat(sprintf("  · %-22s n=%3d meanIC=%+.5f t=%+.3f pos=%.0f%%\n",
                           b$bucket, b$n, b$mean_ic, b$t_plain, 100 * b$pos_share))

# ── 6) 섭동 q05 (FQ-109 규약 — WT-023 과 동일 파라미터, 창만 확장) ──────────
Mbase <- merge(SA, Rg, by = c("Date", "Ticker"))
Mbase <- Mbase[is.finite(Ret_1m) & Ret_1m <= 5 & Ret_1m >= -1]
setorder(Mbase, Date, Ticker)
ic_of <- function(M, min_n = 8L) {
  v <- M[, .(ic = if (.N >= min_n) suppressWarnings(cor(score, Ret_1m, method = "spearman")) else NA_real_), by = Date]
  v$ic[is.finite(v$ic)]
}
N_SEED <- 60L; DROP_P <- 0.10; NOISE_SD <- 0.10
draws <- list()
for (s in seq_len(N_SEED)) { set.seed(1000L + s)
  v <- ic_of(Mbase[runif(.N) >= DROP_P])
  draws[[length(draws) + 1L]] <- data.table(family = "M", seed = s, t_nw = nw_t(v), mean_ic = mean(v), n_months = length(v)) }
for (s in seq_len(N_SEED)) { set.seed(2000L + s)
  Mp <- copy(Mbase)
  Mp[, rz := { r <- rank(score); (r - mean(r)) / max(sd(r), 1e-12) }, by = Date]
  Mp[, score := rz + rnorm(.N, 0, NOISE_SD)]
  v <- ic_of(Mp)
  draws[[length(draws) + 1L]] <- data.table(family = "S", seed = s, t_nw = nw_t(v), mean_ic = mean(v), n_months = length(v)) }
DR <- rbindlist(draws)
q05_pool <- quantile(DR$t_nw, .05, type = 7, names = FALSE)
q05_M <- quantile(DR[family == "M", t_nw], .05, type = 7, names = FALSE)
q05_S <- quantile(DR[family == "S", t_nw], .05, type = 7, names = FALSE)
cat(sprintf("\n[stage1] 섭동 %d draws: t_NW q05 pooled=%+.4f (M=%+.4f / S=%+.4f) | min=%+.3f med=%+.3f max=%+.3f sd=%.3f\n",
            nrow(DR), q05_pool, q05_M, q05_S, min(DR$t_nw), median(DR$t_nw), max(DR$t_nw), sd(DR$t_nw)))
cat(sprintf("[stage1] (파일럿 q05 1.4405 대비 %s)\n", ifelse(q05_pool > 1.4405, "개선", "악화")))

# ── 7) ★위반 주입: 정정값 소급(사후 정보) A/B ──────────────────────────────
ab <- merge(ICS_A[, .(Date, ic_A = ic)], ICS_B[, .(Date, ic_B = ic)], by = "Date")
dd <- ab$ic_B - ab$ic_A
inj <- list(n = nrow(ab), mean_ic_A = mean(ab$ic_A), mean_ic_B = mean(ab$ic_B),
            mean_diff_B_minus_A = mean(dd),
            t_paired = if (nrow(ab) >= 8) mean(dd) / sd(dd) * sqrt(nrow(ab)) else NA_real_,
            t_nw_B = nw_t(ab$ic_B), t_nw_A = nw_t(ab$ic_A),
            interpretation = "B(정정 소급)가 A 대비 유의하게 높으면 사후정보 누출 지문. 검사기가 살아있는지의 대조군.")
cat(sprintf("[stage1] ★위반주입(정정 소급): meanIC A=%+.5f B=%+.5f | paired diff=%+.5f t=%+.3f | t_NW A=%+.3f B=%+.3f\n",
            inj$mean_ic_A, inj$mean_ic_B, inj$mean_diff_B_minus_A, inj$t_paired, inj$t_nw_A, inj$t_nw_B))

# ── 8) lag1 스트레스 (C5) ───────────────────────────────────────────────────
lag1 <- local({
  key <- me_dates[order(Date)]; key[, Date_next := shift(Date, -1)]
  S2 <- merge(SA, key[, .(Date, Date_next)], by = "Date")
  S2[!is.na(Date_next), .(Date = Date_next, Ticker, score)]
})
IC_lag1 <- summ_ic(ic_series_of(lag1))
cat(sprintf("[stage1] lag1 스트레스: meanIC=%+.5f t_NW=%+.4f n=%d (base %+.5f / %+.4f)\n",
            IC_lag1$mean_ic, IC_lag1$t_nw, IC_lag1$n_months, comb$mean_ic, comb$t_nw))

# ── 9) dual-basis canonical 실측 (전이 벽) ─────────────────────────────────
CN <- canonical_screen_bt(SA[, .(Date, Ticker, score)], Rg, Bg, top_n = 20L,
                          cost_bps_oneway = 15, liq_dt = Lg, liq_min = 2e8,
                          run_id = "fq125_stage1_A_size", strategy_id = "fq125_stage1_A_size",
                          periods_per_year = 12L, diag_dual_basis = TRUE, size_dt = SZ)
cat(sprintf("[stage1] canonical: cap-w PORT_t=%+.3f (n=%d) | EW-uni t=%+.3f | net_SR=%.3f | TO=%.2f/yr\n",
            CN$portfolio_alpha_t_nw_lag3, CN$n_months,
            CN$diag_ew_universe$portfolio_alpha_t_nw_lag3, CN$net_sr, CN$turnover_annual))
if (isTRUE(CN$diag_cap_tier$available)) str(CN$diag_cap_tier, max.level = 2)

# ── 10) 저장 ────────────────────────────────────────────────────────────────
cov_m <- SA[, .(n_cov = .N), by = Date][order(Date)]
strip_cn <- function(x) x[setdiff(names(x), c("benchmark_compare"))]
out <- list(
  task_id = WT, measured_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  metric_type_note = "IC 계열 = 진단 통계(cor). 포트 수치 = canonical_screen(실측).",
  grid_vintage = GRID_VINTAGE,
  corpus = list(checkpoint_months = uniqueN(D$ym), used_from_ym = YM_MIN,
                pre2019_excluded = as.list(pre), usable = as.list(census[era == "usable_2019plus"])),
  panel = list(A_rows = nrow(panelA), B_rows = nrow(panelB),
               ym_min = min(panelA$ym), ym_max = max(panelA$ym), n_tickers = uniqueN(panelA$Ticker),
               correction_matched = matched, correction_total = nrow(CORR)),
  parity_pilot = list(pass = parity_ok, mean_ic = pil_s$mean_ic, t_plain = pil_s$t_plain,
                      n_months = pil_s$n_months, expected_mean_ic = 0.080559, expected_t_plain = 1.972226),
  gate = list(rule = "PASS: t_NW>=1.5 AND new_mean_ic>0 AND regime_decomp / ABORT: t_NW<1.0 / else INDETERMINATE",
              rule_fixed_by = "WT-D20260802_023 (측정 전 고정)", verdict = verdict,
              combined = comb, new_segment = new_s,
              pilot_segment = pil_s),
  ic_series = ICS_A[, .(Date = as.character(Date), n, ic)],
  regime = regime,
  perturbation = list(protocol = list(n_seeds_per_family = N_SEED, drop_p = DROP_P, noise_sd = NOISE_SD,
                                      statistic = "t_NW(lag3) of monthly IC series", q05_type = 7),
                      q05_t_nw_pooled = q05_pool, q05_t_nw_family_M = q05_M, q05_t_nw_family_S = q05_S,
                      pilot_q05_reference = 1.4405,
                      summary = list(min = min(DR$t_nw), q25 = quantile(DR$t_nw, .25, names = FALSE),
                                     median = median(DR$t_nw), q75 = quantile(DR$t_nw, .75, names = FALSE),
                                     max = max(DR$t_nw), sd = sd(DR$t_nw)),
                      draws = DR),
  violation_injection_correction_backdate = inj,
  lag1_stress = IC_lag1,
  canonical_A_size = strip_cn(CN),
  coverage = list(mean_names = mean(cov_m$n_cov), min_names = min(cov_m$n_cov),
                  max_names = max(cov_m$n_cov), n_months = nrow(cov_m),
                  by_year = cov_m[, .(mean_cov = mean(n_cov)), by = .(yr = format(Date, "%Y"))])
)
write_json(out, file.path(OUTD, "fq125_stage1_results.json"), pretty = TRUE, auto_unbox = TRUE,
           digits = 8, null = "null")

# alpha_scores (최신 시그널월 단면)
last_ym <- max(panelA$ym); last_me <- MEM[, max(Date)]
Sx <- panelA[ym == last_ym, .(Ticker, w_amt, w_n)]
Sx <- merge(Sx, MEM[Date == last_me, .(Ticker, Size)], by = "Ticker")
Sx <- merge(Sx, Lg[Date == last_me, .(Ticker, adv)], by = "Ticker", all.x = TRUE)
Sx <- Sx[!is.na(adv) & adv >= 2e8 & is.finite(Size) & Size > 0 & w_amt > 0]
Sx[, score := w_amt / Size]
zs <- (rank(Sx$score) - mean(rank(Sx$score))) / max(sd(rank(Sx$score)), 1e-12)
Sx[, alpha := comb$mean_ic * zs * 0.06]
Sx[, confidence := pmin(1, pmax(0.2, 0.4 + 0.05 * pmin(w_n, 6)))]
setorder(Sx, -alpha)
write_parquet(Sx[, .(Date = last_me, Ticker, score, alpha, confidence)], file.path(STG, "alpha_scores.parquet"))
cat("[stage1] → ", file.path(OUTD, "fq125_stage1_results.json"), "\n")
cat("[stage1] → ", file.path(STG, "alpha_scores.parquet"), "\n")
