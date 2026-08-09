## FQ176 — quality_accrual 그룹: 입력 실측 (측정 전 probe)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[probe] ", fmt, "\n"), ...)); flush.console() }

PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
say("=== A. panel_full 입력 실측 ===")
say("  행수      : %d", nrow(PN))
say("  컬럼수    : %d", ncol(PN))
say("  컬럼명(앞15): %s", paste(head(names(PN),15), collapse=", "))
say("  컬럼명(뒤6) : %s", paste(tail(names(PN),6), collapse=", "))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
say("  개월수    : %d", length(mo))
say("  기간      : %s ~ %s", format(min(mo)), format(max(mo)))
say("  관측단위  : 1행 = (Date=신호월말) x Ticker")
say("  고유 Ticker: %d", uniqueN(PN$Ticker))
pm <- PN[, .N, by=Date][order(Date)]
say("  월별 종목수: median %.0f (min %d / max %d)", median(pm$N), min(pm$N), max(pm$N))
gaps <- as.numeric(diff(mo))
say("  월 간격(일): median %.0f · min %.0f · max %.0f · 30~34일 벗어난 간격 %d건",
    median(gaps), min(gaps), max(gaps), sum(gaps < 26 | gaps > 40))
say("  Ret_1m    : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(PN$Ret_1m,na.rm=TRUE), sd(PN$Ret_1m,na.rm=TRUE),
    min(PN$Ret_1m,na.rm=TRUE), max(PN$Ret_1m,na.rm=TRUE), sum(is.na(PN$Ret_1m)))

say("=== B. eligible.rds 실측 ===")
ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  자격통과 쌍 %d · 컬럼: %s", nrow(ELI), paste(names(ELI), collapse=", "))
say("  신호별: %s", paste(sprintf("%s=%d", c("S1","S2","S3"),
    sapply(c("S1","S2","S3"), function(s) sum(ELI$signal==s))), collapse=" · "))

say("=== C. 그룹 선택 (quality_accrual = ^Q / ^AC / ^XF) ===")
GRP <- "quality_accrual"
in_grp <- function(x) grepl("^(Q[0-9]|AC[0-9]|XF_)", x)
allf <- sort(unique(fread(file.path(OUT,"pairs_all.csv"))$factor))
say("  전체 팩터 %d 중 그룹 소속: %s", length(allf), paste(allf[in_grp(allf)], collapse=", "))
G <- ELI[in_grp(factor)]
say("  ★자격통과 ∩ 그룹 = %d쌍", nrow(G))
if (nrow(G)) for (i in seq_len(nrow(G)))
  say("    %-24s %s  ic_mean %+.5f · ic_sd %.5f · n_months %d · n_ON %d / n_OFF %d · required %.5f",
      G$factor[i], G$signal[i], G$ic_mean[i], G$ic_sd[i], G$n_months[i],
      G$n_ON[i], G$n_OFF[i], G$required[i])
say("  (참고) 그룹 소속인데 자격 미달인 쌍:")
PA <- fread(file.path(OUT,"pairs_all.csv"))
EXg <- PA[eligible==FALSE & in_grp(factor)]
say("    %d쌍 (팩터 %d종) — ratio min %.2f / median %.2f",
    nrow(EXg), uniqueN(EXg$factor), min(EXg$ratio,na.rm=TRUE), median(EXg$ratio,na.rm=TRUE))

say("=== D. signals.csv 실측 ===")
SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
say("  %d개월 (%s ~ %s)", nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)))
for (s in c("S1","S2","S3")) {
  v <- as.logical(SIG[[s]])
  say("  %s ON %d (%.1f%%) · OFF %d", s, sum(v), 100*mean(v), sum(!v))
}
say("  signals.csv Date 집합 == panel 월 집합? %s",
    identical(sort(SIG$Date), mo))
say("  S3 ON 월 목록: %s", paste(format(SIG[S3==TRUE, Date]), collapse=", "))
