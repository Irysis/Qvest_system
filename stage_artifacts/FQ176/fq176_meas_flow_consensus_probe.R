## FQ176 — flow_consensus 그룹 측정 · STEP 1: 입력 실측 + 시간축 정렬 검증
## metric_type = canonical_screen_diag. 자본 주장 없음.
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[fc] ", fmt, "\n"), ...)); flush.console() }

## ---------------------------------------------------------------
## 1. ★입력 실측 (가정 금지)
## ---------------------------------------------------------------
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
pm <- PN[, .N, by = Date][order(Date)]
say("=== 1. panel_full.rds 입력 실측 ===")
say("  행수        : %d", nrow(PN))
say("  컬럼수      : %d", ncol(PN))
say("  개월수      : %d", length(mo))
say("  기간        : %s ~ %s", format(min(mo)), format(max(mo)))
say("  관측단위    : (Date=신호월말) x Ticker  — 1행 = 1 종목월")
say("  월간격 실측 : median %.1f일 (min %d / max %d)",
    median(as.numeric(diff(mo))), min(as.numeric(diff(mo))), max(as.numeric(diff(mo))))
say("  월별 종목수 : median %.0f (min %d / max %d)", median(pm$N), min(pm$N), max(pm$N))
say("  고유 Ticker : %d", uniqueN(PN$Ticker))
say("  Ret_1m      : mean %+.5f sd %.5f min %+.4f max %+.4f NA %d",
    mean(PN$Ret_1m, na.rm=TRUE), sd(PN$Ret_1m, na.rm=TRUE),
    min(PN$Ret_1m, na.rm=TRUE), max(PN$Ret_1m, na.rm=TRUE), sum(is.na(PN$Ret_1m)))

IC <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  ic_series   : %d행 · %d팩터 · %d개월 · %s~%s",
    nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date), format(min(IC$Date)), format(max(IC$Date)))
say("  signals     : %d행 · %s~%s · S1 ON %d / S2 ON %d / S3 ON %d",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)),
    sum(SIG$S1), sum(SIG$S2), sum(SIG$S3))
say("  eligible    : %d쌍 · 팩터 %d", nrow(ELI), uniqueN(ELI$factor))
say("  signals$Date == panel months ? %s", identical(sort(SIG$Date), mo))

## ---------------------------------------------------------------
## 2. ★시간축 정렬 실측 — Ret_1m 이 정말 forward(d -> d+1) 인가
##    벤치 BM_Ret[d] = d->d+1 forward (power_gate 규약 선언). 이를 대조군으로 사용.
## ---------------------------------------------------------------
say("=== 2. Ret_1m 정렬 실측 (선언 검증, 가정 금지) ===")
P <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
BEN <- as.data.table(P$bench)[, .(Date = as.Date(Date), BM_Ret)][order(Date)]
XS  <- PN[, .(xs_mean_ret = mean(Ret_1m, na.rm = TRUE)), by = Date][order(Date)]
M   <- merge(XS, BEN, by = "Date", all.x = TRUE)[order(Date)]
M[, `:=`(bm_lag1 = shift(BM_Ret, 1L), bm_lead1 = shift(BM_Ret, -1L))]
say("  cor(xs_mean_ret[d], BM_Ret[d])      = %+.4f   <- 같은 행 정렬(둘 다 forward 이면 高)",
    cor(M$xs_mean_ret, M$BM_Ret, use = "complete.obs"))
say("  cor(xs_mean_ret[d], BM_Ret[d-1])    = %+.4f   <- panel 이 realized 이면 高",
    cor(M$xs_mean_ret, M$bm_lag1, use = "complete.obs"))
say("  cor(xs_mean_ret[d], BM_Ret[d+1])    = %+.4f", cor(M$xs_mean_ret, M$bm_lead1, use = "complete.obs"))
say("  -> 최대 상관 위치가 정렬 규약의 실측 증거")

## 신호 정의와의 정합: S3(dd12<=-0.20) ON 월의 '직전 실현' 벤치 수익 분포
SG <- merge(SIG, BEN, by = "Date", all.x = TRUE)[order(Date)]
SG[, bm_realized := shift(BM_Ret, 1L)]
say("  S1 ON 월의 bm_realized: mean %+.4f (n=%d) / OFF: mean %+.4f",
    mean(SG[S1 == TRUE]$bm_realized, na.rm=TRUE), sum(SG$S1),
    mean(SG[S1 == FALSE]$bm_realized, na.rm=TRUE))
say("  (S1 정의 = ret_realized <= -0.10 이므로 ON 평균이 대폭 음수여야 정합)")

## ---------------------------------------------------------------
## 3. 그룹 필터 — flow_consensus = INV*/CR*/C*/MA*/S*
## ---------------------------------------------------------------
say("=== 3. 그룹 flow_consensus 필터 ===")
GRP_RE <- "^(INV[0-9]|CR[0-9]|C[0-9]|MA[0-9]|S[0-9])"
ELI[, in_group := grepl(GRP_RE, factor)]
say("  정규식: %s", GRP_RE)
say("  자격통과 21쌍 중 그룹 소속 %d쌍", sum(ELI$in_group))
print(ELI[in_group == TRUE, .(factor, signal, ic_mean, ic_sd, n_ON, n_OFF, required, bar, ratio)])
say("  --- 그룹 소속이나 자격 미달로 제외된 쌍 확인 (pairs_all) ---")
PA <- fread(file.path(OUT, "pairs_all.csv"))
PA[, in_group := grepl(GRP_RE, factor)]
say("  그룹 전체 쌍 %d · 자격통과 %d · 미달 %d",
    sum(PA$in_group), sum(PA$in_group & PA$eligible), sum(PA$in_group & !PA$eligible))
print(PA[in_group == TRUE][order(ratio)][, .(factor, signal, ratio, eligible)])
say("=== probe 완료 ===")
