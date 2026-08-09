## FQ176 적대검증 — 렌즈 era_split · STEP 1: 입력 실측 + 시대별 ON 분포
## metric_type = canonical_screen_diag. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[era1] ", fmt, "\n"), ...)); flush.console() }

## ---------------- 0. 입력 실측 (가정 금지) ----------------
say("=== 0. 입력 실측 ===")
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo_p <- sort(unique(PN$Date))
say("panel_full.rds")
say("  행수        : %d", nrow(PN))
say("  개월수      : %d", length(mo_p))
say("  기간        : %s ~ %s", format(min(mo_p)), format(max(mo_p)))
say("  관측단위    : 1행 = 신호관측월말(Date) x Ticker")
say("  컬럼수      : %d  (팩터열 %d)", ncol(PN), ncol(PN)-4L)
say("  고유 Ticker : %d", uniqueN(PN$Ticker))
pm <- PN[, .N, by = Date][order(Date)]
say("  월별 종목수 : median %.0f (min %d / max %d)", median(pm$N), min(pm$N), max(pm$N))
say("  Ret_1m      : mean %+.5f sd %.5f min %+.4f max %+.4f NA %d",
    mean(PN$Ret_1m), sd(PN$Ret_1m), min(PN$Ret_1m), max(PN$Ret_1m), sum(is.na(PN$Ret_1m)))
## 월 간격 실측 -> 관측단위가 월간인지 확인 (NW lag 는 관측단위 종속)
dif <- as.numeric(diff(mo_p))
say("  월말 간격(일): median %.0f · min %d · max %d  -> 관측단위 = %s",
    median(dif), min(dif), max(dif), ifelse(median(dif) > 20 && median(dif) < 40, "월간(확인)", "★비월간"))

IC <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
say("ic_series.rds")
say("  행수 %d · 팩터 %d · 개월 %d · %s ~ %s (관측단위 = 팩터 x 월)",
    nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date), format(min(IC$Date)), format(max(IC$Date)))
say("  ic: mean %+.5f sd %.5f min %+.4f max %+.4f · n_xs median %.0f (min %d)",
    mean(IC$ic), sd(IC$ic), min(IC$ic), max(IC$ic), median(IC$n_xs), min(IC$n_xs))

SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
say("signals.csv: %d개월 · %s ~ %s · ON: S1 %d · S2 %d · S3 %d",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)), sum(SIG$S1), sum(SIG$S2), sum(SIG$S3))

ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("eligible.rds: %d쌍 · 고유팩터 %d · 신호 %s",
    nrow(ELI), uniqueN(ELI$factor), paste(sort(unique(ELI$signal)), collapse="/"))

## ---------------- 1. 시대 분할 정의 + ON 분포 ----------------
say("=== 1. 시대 분할 (E1 = 2003-2012 / E2 = 2013-2026) ===")
SIG[, era := fifelse(Date <= as.Date("2012-12-31"), "E1_2003_2012", "E2_2013_2026")]
IC[,  era := fifelse(Date <= as.Date("2012-12-31"), "E1_2003_2012", "E2_2013_2026")]

era_mo <- SIG[, .(n_months = .N, d_min = min(Date), d_max = max(Date)), by = era][order(era)]
print(era_mo)

say("--- 신호별 시대 ON 분포 ---")
for (s in c("S1","S2","S3")) {
  tb <- SIG[, .(n_months = .N, n_on = sum(get(s)), pct = 100*mean(get(s))), by = era][order(era)]
  for (i in seq_len(nrow(tb)))
    say("  %s %s: %d/%d ON (%.1f%%)", s, tb$era[i], tb$n_on[i], tb$n_months[i], tb$pct[i])
  say("  %s 전표본: %d/%d ON (%.1f%%)", s, sum(SIG[[s]]), nrow(SIG), 100*mean(SIG[[s]]))
}

## ON 에피소드(연속 런) — 유효표본의 실질 단위
say("--- ON 에피소드(연속 런) 실측: 유효표본은 월수가 아니라 런 수 ---")
run_tab <- function(v, dts) {
  r <- rle(v); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  idx <- which(r$values)
  if (!length(idx)) return(data.table())
  data.table(start = dts[starts[idx]], end = dts[ends[idx]], len = r$lengths[idx])
}
for (s in c("S1","S2","S3")) {
  RT <- run_tab(SIG[[s]], SIG$Date)
  say("  %s 전표본 런 %d개 (총 %d개월, 최장 %d)", s, nrow(RT), sum(RT$len), max(RT$len))
  RT[, era := fifelse(start <= as.Date("2012-12-31"), "E1", "E2")]
  for (i in seq_len(nrow(RT)))
    say("     [%s] %s ~ %s (%d개월)", RT$era[i], format(RT$start[i]), format(RT$end[i]), RT$len[i])
  say("  %s 런 분포: E1 %d런 / E2 %d런", s, sum(RT$era=="E1"), sum(RT$era=="E2"))
}

## ---------------- 2. 시대별 IC 기초통계 (자격 게이트 재료) ----------------
say("=== 2. 시대별 팩터 IC 기초통계 (자격 게이트 재료가 시대 의존인가) ===")
EFAC <- sort(unique(ELI$factor))
ST <- IC[factor %in% EFAC, .(n = .N, ic_mean = mean(ic), ic_sd = sd(ic)), by = .(factor, era)]
STF <- IC[factor %in% EFAC, .(n_full = .N, ic_mean_full = mean(ic), ic_sd_full = sd(ic)), by = factor]
W <- dcast(ST, factor ~ era, value.var = c("n","ic_mean","ic_sd"))
W <- merge(W, STF, by = "factor")
setorder(W, -ic_mean_full)
say("  팩터별 ic_mean: 전표본 / E1 / E2")
for (i in seq_len(nrow(W)))
  say("    %-30s full %+.5f (n=%d) | E1 %+.5f (n=%d) | E2 %+.5f (n=%d) | E1-E2 %+.5f",
      W$factor[i], W$ic_mean_full[i], W$n_full[i],
      W$ic_mean_E1_2003_2012[i], W$n_E1_2003_2012[i],
      W$ic_mean_E2_2013_2026[i], W$n_E2_2013_2026[i],
      W$ic_mean_E1_2003_2012[i] - W$ic_mean_E2_2013_2026[i])
fwrite(W, file.path(OUT, "adv_era_ic_by_era.csv"))
say("  부호 반전 팩터 수: %d / %d",
    sum(sign(W$ic_mean_E1_2003_2012) != sign(W$ic_mean_E2_2013_2026)), nrow(W))
say("=== STEP1 완료 ===")
