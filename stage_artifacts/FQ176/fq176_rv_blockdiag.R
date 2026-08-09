## FQ176 risk_vol — 보조 진단: ON 월의 에피소드 군집성 → 유효표본 축소
## metric_type = canonical_screen_diag. 판정 변경 아님(보조).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[rvblk] ", fmt, "\n"), ...)); flush.console() }

SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
setorder(SIG, Date)
mo <- SIG$Date
SIG[, idx := .I]
SIG[, meas_idx := idx + 1L]
S <- SIG[meas_idx <= length(mo)]
S[, meas_Date := mo[meas_idx]]

on_idx <- S[S3 == TRUE, meas_idx]
say("ON 측정월 %d개", length(on_idx))
## 연속 구간(에피소드) 분해
b <- cumsum(c(1L, diff(sort(on_idx)) != 1L))
ep <- data.table(idx = sort(on_idx), ep = b)[, .(n_months = .N,
        from = format(mo[min(idx)]), to = format(mo[max(idx)])), by = ep]
say("에피소드 %d개 (연속 ON 구간):", nrow(ep))
for (i in seq_len(nrow(ep))) say("  ep%d: %s ~ %s (%d개월)", ep$ep[i], ep$from[i], ep$to[i], ep$n_months[i])
say("★ 유효 독립표본 ≈ 에피소드 수 %d (월 %d 아님) — 월단위 se 는 하한", nrow(ep), length(on_idx))

## 에피소드-클러스터 se 로 t 재계산 (보조)
IC <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
M  <- fread(file.path(OUT, "measured_risk_vol.csv"))
MAP <- S[, .(Date = meas_Date, on = S3)]
epmap <- data.table(Date = mo[sort(on_idx)], ep = b)
rows <- list()
for (i in seq_len(nrow(M))) {
  f <- M$factor[i]
  J <- merge(IC[factor == f, .(Date, ic)], MAP, by = "Date")
  J <- merge(J, epmap, by = "Date", all.x = TRUE)
  onJ <- J[on == TRUE]; offJ <- J[on == FALSE]
  ## ON 측은 에피소드 평균을 관측단위로 (군집 1개 = 1관측)
  epm <- onJ[, .(ic = mean(ic)), by = ep]
  n_ep <- nrow(epm)
  d <- mean(onJ$ic) - mean(offJ$ic)
  se_cl <- sqrt(var(epm$ic)/n_ep + var(offJ$ic)/nrow(offJ))
  rows[[i]] <- data.table(factor = f, signal = M$signal[i], delta_ic = d,
                          t_month = M$t_stat[i], n_ep = n_ep,
                          se_cluster = se_cl, t_cluster = d/se_cl,
                          mde_cluster_2se = 2*se_cl)
}
B <- rbindlist(rows)[order(-abs(t_cluster))]
for (i in seq_len(nrow(B)))
  say("  %-14s ΔIC %+.5f | t(월기반) %+.3f -> t(에피소드클러스터) %+.3f | 에피소드 %d · MDE(2se) %.5f",
      B$factor[i], B$delta_ic[i], B$t_month[i], B$t_cluster[i], B$n_ep[i], B$mde_cluster_2se[i])
fwrite(B, file.path(OUT, "measured_risk_vol_blockdiag.csv"))
say("저장: measured_risk_vol_blockdiag.csv")
