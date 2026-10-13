#!/usr/bin/env Rscript
#==============================================================================
# 02_tables.R — 01 의 상태 경로(out/replay.rds) + 측정 산출물(RX3 · RX0)로 서술 표만 만든다 · ≤ τ_D
#   ① 연도별 발화 비율(시그널일 기준 상태 · 집행일 기준 산출물 Σw<1)
#   ② 위기 4창별 지배 시그널일의 상태(창 = 행동 카드 보는 창 위기 · 고점→바닥)
#   ③ 2015 보유월 표 — 상태 · Σw · 산출물 월 수익(03_period_returns ret_net 의 달력월 곱) · 벤치 월 수익
#   ④ 공표 지수 2015 연간 수익(.cache/indices.parquet — 지수 수준의 연말 대비, 자작 포트폴리오 아님)
#   수익은 계약 산출물의 일간 ret_net 을 달력월로 묶을 뿐이다(자작 백테스트·합성 수익 없음).
#==============================================================================
options(warn = 1, width = 220, datatable.print.nrows = 400)
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
TAU  <- as.Date("2022-12-31")
DIAG <- file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/diag_rx3_overlay")
OUTD <- file.path(DIAG, "out")
RX3_DIR <- file.path(ROOT, "stage_artifacts/replication/20261013_175043_25968")
RX0_DIR <- file.path(ROOT, "stage_artifacts/replication/20261013_165251_20896")
R <- readRDS(file.path(OUTD, "replay.rds")); D <- R$D; DC <- R$DC
say <- function(...) cat(sprintf(...), "\n", sep = "")

# 시그널일 → 다음 시그널일의 집행일(보유창 끝) — 보유창 = (exec_k, exec_{k+1}] (close_t1)
D <- D[order(Date)]
D[, exec_next := shift(exec_date, 1L, type = "lead")]

#── ① 연도별 ──────────────────────────────────────────────────────────────────────
y_sig <- D[, .(n_signals = .N, n_state_active = sum(guard == "ACTIVE"), g_max = max(g_eff),
               n_warmup_block = sum(guard == "warmup_below_months<24"), n_below = sum(below),
               shadow_q_max = suppressWarnings(max(q, na.rm = TRUE))), by = .(year = year(Date))]
y_exe <- D[!is.na(exec_date), .(n_rebal = .N, n_sumw_lt1 = sum(active_artifact), sumw_mean = mean(sum_w_rx3),
                                sumw_min = min(sum_w_rx3)), by = .(year = year(exec_date))]
Y <- merge(y_sig, y_exe, by = "year", all = TRUE)
Y[, `:=`(share_state_active = n_state_active / n_signals, share_realized = n_sumw_lt1 / n_rebal)]
Y[!is.finite(shadow_q_max), shadow_q_max := NA_real_]
fwrite(Y, file.path(OUTD, "activation_by_year.csv"))
say("── ① 연도별 발화(상태 = 시그널일 연도 · 산출물 = 집행일 연도)"); print(Y)

#── ② 위기 창 ─────────────────────────────────────────────────────────────────────
W <- data.table(window = c("2007-10→2008-10", "2011-05→2011-09", "2017-11→2020-03", "2021-06→2022-09"),
                peak = as.Date(c("2007-10-11", "2011-05-02", "2017-11-03", "2021-06-25")),
                trough = as.Date(c("2008-10-24", "2011-09-26", "2020-03-19", "2022-09-30")))
CW <- rbindlist(lapply(seq_len(nrow(W)), function(i) {
  x <- D[!is.na(exec_date) & exec_date < W$trough[i] & (is.na(exec_next) | exec_next >= W$peak[i])]
  x[, window := W$window[i]]
  x[, .(window, signal_date = Date, exec_date, r252, below, run_now, n_below_hist, k_star_full, q, g = g_eff, guard,
        sum_w_rx3, ps_phase_hold_month)]
}))
fwrite(CW, file.path(OUTD, "crisis_windows_state.csv"))
CS <- CW[, .(n_governing = .N, n_below = sum(below), n_active = sum(guard == "ACTIVE"),
             first_below = if (any(below)) as.character(min(signal_date[below])) else NA_character_,
             first_active = if (any(guard == "ACTIVE")) as.character(min(signal_date[guard == "ACTIVE"])) else NA_character_,
             g_max = max(g), sumw_min = min(sum_w_rx3), sumw_mean = mean(sum_w_rx3),
             n_warmup_block = sum(guard == "warmup_below_months<24"),
             shadow_q_max = suppressWarnings(max(q, na.rm = TRUE))), by = window]
CS[!is.finite(shadow_q_max), shadow_q_max := NA_real_]
# 반사실(이력 1990-01 기점)의 같은 지배 시그널일 상태
CS[, cf_n_active := vapply(window, function(w) {
  s <- CW[window == w, signal_date]; DC[Date %in% s, sum(guard == "ACTIVE")] }, integer(1))]
CS[, cf_g_max := vapply(window, function(w) {
  s <- CW[window == w, signal_date]; DC[Date %in% s, max(g)] }, numeric(1))]
fwrite(CS, file.path(OUTD, "crisis_windows_summary.csv"))
say("── ② 위기 창 요약(지배 시그널일 = 보유창이 고점~바닥과 겹치는 시그널)"); print(CS)
say("── ② 위기 창 상세"); print(CW)

#── ③ 2015 보유월 ─────────────────────────────────────────────────────────────────
rd_ret <- function(dir, col = "ret_net", f = "03_period_returns.csv") {
  x <- fread(file.path(dir, f), select = c("date", col)); x[, date := as.Date(date)]; x[date <= TAU]
}
r3 <- rd_ret(RX3_DIR); r0 <- rd_ret(RX0_DIR)
bm <- fread(file.path(RX3_DIR, "05_benchmark_returns.csv"), select = c("date", "benchmark_ret")); bm[, date := as.Date(date)]
bm <- bm[date <= TAU]
mon <- function(x, col) x[, .(r = prod(1 + get(col)) - 1), by = .(ym = format(date, "%Y-%m"))]
MR <- Reduce(function(a, b) merge(a, b, by = "ym"), list(
  setnames(mon(r0, "ret_net"), "r", "rx0_ret"), setnames(mon(r3, "ret_net"), "r", "rx3_ret"),
  setnames(mon(bm, "benchmark_ret"), "r", "k200_ret")))
MR[, gap_rx3_minus_rx0 := rx3_ret - rx0_ret]
S15 <- merge(D[, .(hold_ym, signal_date = Date, exec_date, r252, run_now, n_below_hist, k_star_full, q, g = g_eff, guard,
                   sum_w_rx3, ps_phase_hold_month)], MR, by.x = "hold_ym", by.y = "ym")[substr(hold_ym, 1, 4) == "2015"]
fwrite(S15, file.path(OUTD, "y2015_months.csv"))
say("── ③ 2015 보유월(보유월 = 시그널 익월 · 수익 = 달력월)"); print(S15)
ann <- function(x, col) x[, .(r = prod(1 + get(col)) - 1), by = .(year = year(date))]
A <- Reduce(function(a, b) merge(a, b, by = "year"), list(setnames(ann(r0, "ret_net"), "r", "rx0"),
            setnames(ann(r3, "ret_net"), "r", "rx3"), setnames(ann(bm, "benchmark_ret"), "r", "k200")))
say("── 연도별 산출물 수익(달력년 · 대조용)"); print(A[year %in% 2013:2016])
act15 <- S15$guard == "ACTIVE"
say("2015 발화 보유월 %d개 — RX0 누적 %.4f · RX3 누적 %.4f | 미발화 보유월 %d개 — RX0 누적 %.4f · RX3 누적 %.4f",
    sum(act15), prod(1 + S15$rx0_ret[act15]) - 1, prod(1 + S15$rx3_ret[act15]) - 1,
    sum(!act15), prod(1 + S15$rx0_ret[!act15]) - 1, prod(1 + S15$rx3_ret[!act15]) - 1)
say("2015 발화 보유월 K200 누적 %.4f · 미발화 보유월 K200 누적 %.4f",
    prod(1 + S15$k200_ret[act15]) - 1, prod(1 + S15$k200_ret[!act15]) - 1)

#── ④ 공표 지수 2015 ────────────────────────────────────────────────────────────────
ix <- as.data.table(arrow::read_parquet(file.path(ROOT, ".cache/indices.parquet")))
ix[, Date := as.Date(Date)]; ix <- ix[Date <= TAU]
lv <- function(col, y) { v <- ix[year(Date) == y & is.finite(get(col))]; v[which.max(Date), get(col)] }
I15 <- rbindlist(lapply(c("kospi200", "kospi200_ew", "kosdaq150", "kosdaq", "kospi_small", "kosdaq_small"), function(cn)
  data.table(index = cn, ret_2015 = lv(cn, 2015) / lv(cn, 2014) - 1)))
fwrite(I15, file.path(OUTD, "published_index_2015.csv"))
say("── ④ 공표 지수 2015 연간(연말 수준 대비)"); print(I15)

#── ⑤ 발화 시그널의 국면 라벨(PS · 보유월 기준) ─────────────────────────────────────────
PA <- D[guard == "ACTIVE" & !is.na(exec_date), .(n_active = .N), by = ps_phase_hold_month]
say("── ⑤ 발화 보유월의 PS 국면(≤ τ_D 집행분)"); print(PA)
print(D[guard == "ACTIVE" & !is.na(exec_date) & ps_phase_hold_month == "bull", .(signal_date = Date, hold_ym, g = g_eff, sum_w_rx3)])
# 반사실 발화 보유월 국면(이력 1990 기점)
DC[, hold_ym := format(seq(as.Date(format(Date, "%Y-%m-01")), by = "month", length.out = 2L)[2L], "%Y-%m"), by = Date]
ymk <- rbindlist(lapply(seq_len(nrow(R$PH)), function(i) {
  ys <- seq(as.Date(paste0(R$PH$start_ym[i], "-01")), as.Date(paste0(R$PH$end_ym[i], "-01")), by = "month")
  data.table(ym = format(ys, "%Y-%m"), ps = R$PH$kind[i]) }))
DC[, ps := ymk$ps[match(hold_ym, ymk$ym)]]
say("── ⑤' 반사실 발화 시그널(2005-01 ~ 2022-11 · 보유월 국면)")
print(DC[guard == "ACTIVE" & Date >= as.Date("2005-01-01") & Date <= as.Date("2022-11-30"), .(n = .N), by = .(year = year(Date), ps)])
