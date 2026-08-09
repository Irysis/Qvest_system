## FQ176 — 검정력 게이팅 (라운드 자격 판정)
## metric_type = canonical_screen_diag. 자본 주장 없음.
## PIT: 팩터 z(Date=신호월말) x Ret_1m(forward, build_monthly_forward_returns 규약)
##      벤치 하락신호는 월말 t 시점 관측가능분만 (BM_Ret[d0]=d0->d1 forward 이므로 shift(1))
suppressPackageStartupMessages({
  library(data.table); library(jsonlite); library(PerformanceAnalytics); library(xts)
})
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[fq176] ", fmt, "\n"), ...)); flush.console() }

MIN_XS  <- 30L    # 선언: 월별 rank-IC 산출 최소 횡단면 종목수
LIQ_THR <- 2e8    # 20일 평균 거래대금 문턱 (adv 결측은 통과 — 지시 규약)

## =============================================================
## 1. 팩터 슬라이스 로드 -> wide (슬라이스별 dcast 후 rbind: 메모리 절약)
## =============================================================
say("=== 1. 팩터 슬라이스 로드 ===")
wide_list <- list(); slice_meta <- list()
for (i in 0:3) {
  f <- file.path(OUT, sprintf("slice_%d.rds", i))
  S <- as.data.table(readRDS(f))
  S[, Date := as.Date(Date)]
  slice_meta[[length(slice_meta)+1L]] <- data.table(
    slice = i, n_rows = nrow(S), n_months = uniqueN(S$Date),
    n_factors = uniqueN(S$Factor_Name),
    dmin = min(S$Date), dmax = max(S$Date))
  say("  slice_%d: %d행 · %d개월 · %d팩터 · %s ~ %s",
      i, nrow(S), uniqueN(S$Date), uniqueN(S$Factor_Name),
      format(min(S$Date)), format(max(S$Date)))
  W <- dcast(S, Date + Ticker ~ Factor_Name, value.var = "z")
  rm(S); invisible(gc(FALSE))
  wide_list[[length(wide_list)+1L]] <- W
  rm(W); invisible(gc(FALSE))
}
FW <- rbindlist(wide_list, use.names = TRUE, fill = TRUE)
rm(wide_list); invisible(gc(FALSE))
setkey(FW, Date, Ticker)
SM <- rbindlist(slice_meta)
say("  wide 결합: %d행 · %d개월 · 컬럼 %d (팩터 %d)",
    nrow(FW), uniqueN(FW$Date), ncol(FW), ncol(FW) - 2L)
dup_dates <- SM[, .N, by = .(dmin)][N > 1]
say("  슬라이스 월 중복 확인: 총 slice 월합 %d vs 결합 고유월 %d %s",
    sum(SM$n_months), uniqueN(FW$Date),
    ifelse(sum(SM$n_months) == uniqueN(FW$Date), "(중복 없음)", "★중복 존재"))

FN <- setdiff(names(FW), c("Date","Ticker"))

## =============================================================
## 2. 수익 · 유동성 병합
## =============================================================
say("=== 2. 수익/유동성 병합 ===")
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
RET <- as.data.table(P$ret)[, .(Date = as.Date(Date), Ticker, Ret_1m)]
LIQ <- as.data.table(P$liq)[, .(Date = as.Date(Date), Ticker, adv)]
BEN <- as.data.table(P$bench)[, .(Date = as.Date(Date), BM_Ret)][order(Date)]
say("  ret %d행/%d개월(%s~%s) · liq %d행 · bench %d행(%s~%s)",
    nrow(RET), uniqueN(RET$Date), format(min(RET$Date)), format(max(RET$Date)),
    nrow(LIQ), nrow(BEN), format(min(BEN$Date)), format(max(BEN$Date)))

n_before <- nrow(FW)
PN <- merge(FW, RET, by = c("Date","Ticker"))            # inner
rm(FW); invisible(gc(FALSE))
say("  inner join(ret): %d -> %d행 (%d개월)", n_before, nrow(PN), uniqueN(PN$Date))
PN <- merge(PN, LIQ, by = c("Date","Ticker"), all.x = TRUE)  # left
n_na_adv <- sum(is.na(PN$adv))
n_pre_liq <- nrow(PN)
PN <- PN[is.na(adv) | adv >= LIQ_THR]
say("  adv 결측 %d행(%.2f%%) · 유동성필터(결측 or >=%.0e): %d -> %d행 (%d개월)",
    n_na_adv, 100*n_na_adv/n_pre_liq, LIQ_THR, n_pre_liq, nrow(PN), uniqueN(PN$Date))

saveRDS(PN, file.path(OUT, "panel_full.rds"))
say("  저장: %s (%.1f MB)", file.path(OUT,"panel_full.rds"),
    file.size(file.path(OUT,"panel_full.rds"))/1e6)

## =============================================================
## 3. ★입력 실측
## =============================================================
say("=== 3. ★입력 실측 (panel_full) ===")
mo <- sort(unique(PN$Date))
per_month_n <- PN[, .N, by = Date][order(Date)]
say("  행수         : %d", nrow(PN))
say("  개월수       : %d", length(mo))
say("  기간         : %s ~ %s", format(min(mo)), format(max(mo)))
say("  관측단위     : 신호월말 Date x Ticker (1행=1종목월)")
say("  월별 종목수  : median %.0f (min %d / max %d)",
    median(per_month_n$N), min(per_month_n$N), max(per_month_n$N))
say("  고유 Ticker  : %d", uniqueN(PN$Ticker))
say("  Ret_1m       : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(PN$Ret_1m), sd(PN$Ret_1m), min(PN$Ret_1m), max(PN$Ret_1m), sum(is.na(PN$Ret_1m)))
cov_dt <- data.table(factor = FN,
  nonmiss_rate = sapply(FN, function(f) mean(!is.na(PN[[f]]))),
  n_months_any = sapply(FN, function(f) uniqueN(PN[!is.na(get(f))]$Date)))
setorder(cov_dt, nonmiss_rate)
say("  팩터별 비결측률 (%d팩터, 오름차순):", length(FN))
for (i in seq_len(nrow(cov_dt)))
  say("    %-32s %6.2f%%  (관측월 %d)", cov_dt$factor[i], 100*cov_dt$nonmiss_rate[i], cov_dt$n_months_any[i])
fwrite(cov_dt, file.path(OUT, "input_coverage.csv"))

## =============================================================
## 4. 팩터별 월별 rank-IC
## =============================================================
say("=== 4. 월별 rank-IC (spearman, z vs Ret_1m; 최소 횡단면 %d) ===", MIN_XS)
ic_rows <- list()
for (f in FN) {
  D <- PN[!is.na(get(f)) & !is.na(Ret_1m), .(Date, z = get(f), r = Ret_1m)]
  ICm <- D[, .(n = .N, ic = if (.N >= MIN_XS)
                 suppressWarnings(cor(z, r, method = "spearman")) else NA_real_), by = Date]
  ICm <- ICm[!is.na(ic)]
  ic_rows[[f]] <- data.table(factor = f, Date = ICm$Date, ic = ICm$ic, n_xs = ICm$n)
}
IC <- rbindlist(ic_rows)
saveRDS(IC, file.path(OUT, "ic_series.rds"))
STAT <- IC[, .(n_months = .N, ic_mean = mean(ic), ic_sd = sd(ic),
               ic_ir = mean(ic)/sd(ic),
               d_min = min(Date), d_max = max(Date)), by = factor]
setorder(STAT, -ic_mean)
say("  팩터별 IC 요약 (ic_mean 내림차순):")
for (i in seq_len(nrow(STAT)))
  say("    %-32s ic_mean %+.5f  ic_sd %.5f  IR %+.4f  n_mo %3d",
      STAT$factor[i], STAT$ic_mean[i], STAT$ic_sd[i], STAT$ic_ir[i], STAT$n_months[i])
fwrite(STAT, file.path(OUT, "ic_stats.csv"))

## =============================================================
## 5. 하락신호 3종 (월말 t 관측가능분만)
## =============================================================
say("=== 5. 하락신호 3종 ===")
## BM_Ret[d0] = d0->d1 forward. 월말 t 에 '이미 실현된' 직전월 수익 = shift(1).
BEN[, ret_realized := shift(BM_Ret, 1L, type = "lag")]
say("  벤치 규약 확인: BM_Ret[t]=forward(t->t+1) -> ret_realized[t]=BM_Ret[t-1] (관측가능)")
say("  ret_realized: %d개 유효 · mean %+.5f · sd %.5f",
    sum(!is.na(BEN$ret_realized)), mean(BEN$ret_realized, na.rm=TRUE), sd(BEN$ret_realized, na.rm=TRUE))

bx <- xts(BEN$ret_realized, order.by = BEN$Date)
nB <- nrow(BEN)
cum3 <- rep(NA_real_, nB); dd12 <- rep(NA_real_, nB)
for (i in seq_len(nB)) {
  if (i >= 4L) {                        # ret_realized[2..] 유효 -> 3개 창은 i>=4
    w <- bx[(i-2):i]
    if (all(!is.na(w))) cum3[i] <- as.numeric(Return.cumulative(w))
  }
  if (i >= 13L) {
    w <- bx[(i-11):i]
    if (all(!is.na(w))) dd12[i] <- -as.numeric(maxDrawdown(w))
  }
}
BEN[, `:=`(cum3 = cum3, dd12 = dd12)]
BEN[, `:=`(S1 = ret_realized <= -0.10, S2 = cum3 <= -0.15, S3 = dd12 <= -0.20)]

SIG <- BEN[Date %in% mo, .(Date, ret_realized, cum3, dd12, S1, S2, S3)]
say("  패널기간 신호 커버리지: %d/%d개월 (신호 정의 결측: S1 %d · S2 %d · S3 %d)",
    nrow(SIG), length(mo), sum(is.na(SIG$S1)), sum(is.na(SIG$S2)), sum(is.na(SIG$S3)))
for (s in c("S1","S2","S3")) {
  v <- SIG[[s]]; v[is.na(v)] <- FALSE
  set(SIG, j = s, value = v)
}
N_PANEL <- nrow(SIG)
n_on <- c(S1 = sum(SIG$S1), S2 = sum(SIG$S2), S3 = sum(SIG$S3))
for (s in c("S1","S2","S3"))
  say("  %s: n_ON %d / %d (%.1f%%) · n_OFF %d", s, n_on[[s]], N_PANEL,
      100*n_on[[s]]/N_PANEL, N_PANEL - n_on[[s]])
fwrite(SIG, file.path(OUT, "signals.csv"))

## =============================================================
## 6. ★필요 ΔIC 바 + 자격 규칙 (사전 고정)
## =============================================================
say("=== 6. 필요 ΔIC 바 · 자격 판정 ===")
say("  required = 2.0 * ic_sd * sqrt(1/n_ON + 1/n_OFF) * 1.25")
say("  자격규칙 = required <= 2.0 * |ic_mean|  (사전 고정)")
rows <- list()
for (f in STAT$factor) {
  fm <- IC[factor == f, Date]
  st <- STAT[factor == f]
  for (s in c("S1","S2","S3")) {
    on_pair  <- sum(SIG[Date %in% fm][[s]])
    off_pair <- length(fm) - on_pair
    if (on_pair == 0L || off_pair == 0L) {
      rows[[length(rows)+1L]] <- data.table(
        factor = f, signal = s, ic_mean = st$ic_mean, ic_sd = st$ic_sd,
        n_months = st$n_months, n_ON_panel = n_on[[s]], n_OFF_panel = N_PANEL - n_on[[s]],
        n_ON = on_pair, n_OFF = off_pair, required = NA_real_,
        bar = 2.0*abs(st$ic_mean), ratio = NA_real_, eligible = FALSE,
        reason = sprintf("degenerate split (n_ON=%d, n_OFF=%d)", on_pair, off_pair))
      next
    }
    req <- 2.0 * st$ic_sd * sqrt(1/on_pair + 1/off_pair) * 1.25
    bar <- 2.0 * abs(st$ic_mean)
    el  <- req <= bar
    rows[[length(rows)+1L]] <- data.table(
      factor = f, signal = s, ic_mean = st$ic_mean, ic_sd = st$ic_sd,
      n_months = st$n_months, n_ON_panel = n_on[[s]], n_OFF_panel = N_PANEL - n_on[[s]],
      n_ON = on_pair, n_OFF = off_pair, required = req, bar = bar,
      ratio = req/bar, eligible = el,
      reason = if (el) "ELIGIBLE"
               else sprintf("required %.5f > 2*|ic_mean| %.5f (ratio %.2fx)", req, bar, req/bar))
  }
}
PAIRS <- rbindlist(rows)
setorder(PAIRS, -eligible, ratio)
fwrite(PAIRS, file.path(OUT, "pairs_all.csv"))

ELI <- PAIRS[eligible == TRUE]
saveRDS(ELI, file.path(OUT, "eligible.rds"))
fwrite(ELI, file.path(OUT, "eligible.csv"))

say("  총 쌍 %d (팩터 %d x 신호 3) · 자격통과 %d · 미달 %d",
    nrow(PAIRS), uniqueN(PAIRS$factor), nrow(ELI), nrow(PAIRS) - nrow(ELI))
if (nrow(ELI)) {
  say("  --- 자격통과 쌍 ---")
  for (i in seq_len(nrow(ELI)))
    say("    %-32s %s  req %.5f <= bar %.5f (ratio %.3f) · n_ON %d / n_OFF %d",
        ELI$factor[i], ELI$signal[i], ELI$required[i], ELI$bar[i], ELI$ratio[i],
        ELI$n_ON[i], ELI$n_OFF[i])
} else say("  자격통과 쌍 없음")

say("  --- 제외 쌍 (전건 명시, 침묵 스킵 없음) ---")
EX <- PAIRS[eligible == FALSE][order(ratio)]
for (i in seq_len(nrow(EX)))
  say("    %-32s %s  %s", EX$factor[i], EX$signal[i], EX$reason[i])

## 제외 사유 요약
EX[, reason_class := fifelse(grepl("degenerate", reason), "degenerate_split", "required_exceeds_bar")]
RS <- EX[, .(n = .N, ratio_min = min(ratio, na.rm = TRUE),
             ratio_med = median(ratio, na.rm = TRUE),
             ratio_max = max(ratio, na.rm = TRUE)), by = .(reason_class, signal)]
say("  --- 제외 사유 요약 ---")
print(RS)

report <- list(
  metric_type = "canonical_screen_diag",
  panel_rows = nrow(PN), panel_months = length(mo),
  period = c(format(min(mo)), format(max(mo))),
  median_names_per_month = median(per_month_n$N),
  n_factors = length(FN),
  n_pairs_total = nrow(PAIRS), n_eligible = nrow(ELI),
  signal_n_on = as.list(n_on),
  eligible_factors = sort(unique(ELI$factor)),
  median_ic_sd = median(STAT$ic_sd)
)
write_json(report, file.path(OUT, "power_gate_report.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
say("=== 완료 → panel_full.rds / eligible.rds / eligible.csv / pairs_all.csv / power_gate_report.json ===")
