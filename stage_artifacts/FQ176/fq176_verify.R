## FQ176 검증 + 리포트 재출력 (join drop 정체 확인 포함)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[vf] ", fmt, "\n"), ...)); flush.console() }

## --- A. join drop 정체 확인: 유니버스 제한인가 키 불일치인가 -------------
say("=== A. inner join drop 정체 (955,597 -> 85,354) ===")
S0 <- as.data.table(readRDS(file.path(OUT,"slice_0.rds")))
S0[, Date := as.Date(Date)]
P  <- readRDS(file.path(ROOT,"stage_artifacts/WT_D20260809_001/p0_panels.rds"))
RET <- as.data.table(P$ret)[, .(Date=as.Date(Date), Ticker, Ret_1m)]

d <- as.Date("2015-01-30")
dd <- sort(unique(S0$Date)); d <- dd[which.min(abs(as.numeric(dd - as.Date("2015-01-31"))))]
fw_t  <- unique(S0[Date==d, Ticker])
ret_t <- unique(RET[Date==d, Ticker])
say("  표본월 %s: 팩터패널 티커 %d · ret패널 티커 %d · 교집합 %d",
    format(d), length(fw_t), length(ret_t), length(intersect(fw_t, ret_t)))
say("  ret 티커 중 팩터패널에 없는 것: %d  (키 불일치라면 이 값이 클 것)",
    length(setdiff(ret_t, fw_t)))
say("  -> ret 패널은 build_monthly_forward_returns 가 (K200|KQ150) 로 제한 → 유니버스 제한이 drop 원인")
RETm <- RET[Date %in% dd, .N, by=Date]
say("  ret 패널 월별 종목수(팩터패널 월 한정): median %.0f (min %d / max %d)",
    median(RETm$N), min(RETm$N), max(RETm$N))
say("  Date 키 정합: 팩터패널 282개월 중 ret 패널에 존재하는 월 = %d",
    sum(dd %in% unique(RET$Date)))
rm(S0); invisible(gc(FALSE))

## --- B. 신호 ---------------------------------------------------------------
say("=== B. 하락신호 실측 ===")
SIG <- fread(file.path(OUT,"signals.csv"))
N <- nrow(SIG)
say("  패널기간 %d개월 (%s ~ %s)", N, min(SIG$Date), max(SIG$Date))
for (s in c("S1","S2","S3")) {
  v <- as.logical(SIG[[s]])
  say("  %s: n_ON %3d / %d (%5.1f%%) · n_OFF %3d", s, sum(v), N, 100*mean(v), N-sum(v))
}
ov <- SIG[, .(S1_only=sum(S1&!S2&!S3), S2_only=sum(!S1&S2&!S3), S3_only=sum(!S1&!S2&S3),
              all3=sum(S1&S2&S3), any=sum(S1|S2|S3))]
print(ov)
say("  S1 발화월 목록: %s", paste(format(SIG[S1==TRUE, Date]), collapse=", "))

## --- C. 자격 판정 ----------------------------------------------------------
say("=== C. 자격 판정 ===")
PA <- fread(file.path(OUT,"pairs_all.csv"))
EL <- fread(file.path(OUT,"eligible.csv"))
say("  총 쌍 %d (팩터 %d x 신호 3) · 자격통과 %d · 미달 %d",
    nrow(PA), uniqueN(PA$factor), nrow(EL), sum(!PA$eligible))
say("  --- 자격통과 쌍 (전건) ---")
EL <- EL[order(ratio)]
for (i in seq_len(nrow(EL)))
  say("    %-30s %s  req %.5f <= bar %.5f  ratio %.3f  n_ON %3d n_OFF %3d  ic_mean %+.5f ic_sd %.5f",
      EL$factor[i], EL$signal[i], EL$required[i], EL$bar[i], EL$ratio[i],
      EL$n_ON[i], EL$n_OFF[i], EL$ic_mean[i], EL$ic_sd[i])
say("  신호별 자격통과: %s",
    paste(sprintf("%s=%d", c("S1","S2","S3"),
      sapply(c("S1","S2","S3"), function(s) sum(EL$signal==s))), collapse=" · "))
say("  자격통과 고유 팩터 %d종: %s", uniqueN(EL$factor), paste(sort(unique(EL$factor)), collapse=", "))

EX <- PA[eligible==FALSE][order(ratio)]
EX[, reason_class := fifelse(grepl("degenerate", reason), "degenerate_split", "required_exceeds_bar")]
say("  --- 제외 사유 요약 ---")
print(EX[, .(n=.N, ratio_min=round(min(ratio,na.rm=TRUE),3),
             ratio_median=round(median(ratio,na.rm=TRUE),3),
             ratio_max=round(max(ratio,na.rm=TRUE),3)), by=.(reason_class, signal)][order(reason_class, signal)])
say("  --- 제외 쌍 전건 (%d) ---", nrow(EX))
for (i in seq_len(nrow(EX)))
  say("    %-30s %s  %s", EX$factor[i], EX$signal[i], EX$reason[i])

say("  경계 근처(ratio 1.0~1.5) 쌍 %d건:", nrow(EX[ratio<=1.5]))
for (i in seq_len(nrow(EX[ratio<=1.5]))) {
  r <- EX[ratio<=1.5][i]
  say("    %-30s %s ratio %.3f", r$factor, r$signal, r$ratio)
}

say("=== D. report json ===")
cat(readLines(file.path(OUT,"power_gate_report.json")), sep="\n")
IS <- fread(file.path(OUT,"ic_stats.csv"))
say("\n  ic_sd: median %.5f · min %.5f (%s) · max %.5f (%s)",
    median(IS$ic_sd), min(IS$ic_sd), IS$factor[which.min(IS$ic_sd)],
    max(IS$ic_sd), IS$factor[which.max(IS$ic_sd)])
