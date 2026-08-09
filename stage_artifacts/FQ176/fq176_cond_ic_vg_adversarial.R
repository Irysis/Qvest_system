## FQ176 value_growth — 자가 적대검증 (off-by-one / 강건성 / 검정력)
## metric_type = canonical_screen_diag
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[adv-vg] ", fmt, "\n"), ...)); flush.console() }

IC  <- as.data.table(readRDS(file.path(OUT,"ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
for (s in c("S1","S2","S3")) set(SIG, j=s, value=as.logical(SIG[[s]]))
R   <- fread(file.path(OUT,"measured_value_growth.csv"))
mo  <- sort(unique(SIG$Date))

## 시차 h 별 dIC/t (h=0 동시월, h=1 정본, h=2 두달 뒤, h=-1 역방향=미래참조 대조)
lagged <- function(f, s, h, ic_sd_full) {
  on_sig  <- SIG[get(s)==TRUE,  Date]
  idx     <- match(mo, mo)
  map <- data.table(sig_month = mo, tgt = c(rep(NA, max(0,-h)), mo, rep(NA, max(0,h)))[
                      seq_along(mo) + h + max(0,-h)])
  map <- map[!is.na(tgt)]
  on_t  <- map[sig_month %in% on_sig,  tgt]
  off_t <- map[!(sig_month %in% on_sig), tgt]
  icf <- IC[factor==f]
  v_on <- icf[Date %in% on_t, ic]; v_off <- icf[Date %in% off_t, ic]
  if (!length(v_on) || !length(v_off)) return(c(NA,NA,NA,NA))
  d <- mean(v_on)-mean(v_off)
  se <- ic_sd_full*sqrt(1/length(v_on)+1/length(v_off))*1.25
  c(d, d/se, length(v_on), length(v_off))
}

say("=== A. 시차 스캔 (h=-1 역방향대조 / h=0 동시 / h=+1 정본 / h=+2) ===")
say("    h=-1 = 신호가 IC 보다 *뒤* (미래참조 방향) — 정본과 비슷하면 정렬이 무의미하다는 뜻")
for (i in seq_len(nrow(R))) {
  o <- sapply(c(-1,0,1,2), function(h) lagged(R$factor[i], R$signal[i], h, R$ic_sd_full[i]))
  say("    %-22s %s | dIC/t  h-1 %+.5f/%+.2f · h0 %+.5f/%+.2f · h+1(정본) %+.5f/%+.2f · h+2 %+.5f/%+.2f",
      R$factor[i], R$signal[i], o[1,1],o[2,1], o[1,2],o[2,2], o[1,3],o[2,3], o[1,4],o[2,4])
}
say("    정본 h+1 재현 확인 (measured csv 대조):")
for (i in seq_len(nrow(R))) {
  o <- lagged(R$factor[i], R$signal[i], 1, R$ic_sd_full[i])
  say("      %-22s %s  t 재계산 %+.4f vs csv %+.4f  %s · n_on %d/%d n_off %d/%d",
      R$factor[i], R$signal[i], o[2], R$t[i],
      ifelse(abs(o[2]-R$t[i])<1e-9,"일치","★불일치"), o[3], R$n_on[i], o[4], R$n_off[i])
}

say("=== B. 최대 |t| 쌍 강건성 (영향 관측 / 하위기간) ===")
bi <- which.max(abs(R$t)); f <- R$factor[bi]; s <- R$signal[bi]
on_sig <- SIG[get(s)==TRUE, Date]
NXT <- data.table(sig_month=mo[-length(mo)], ic_month=mo[-1])
on_t  <- NXT[sig_month %in% on_sig, ic_month]
icf   <- IC[factor==f]
v_on  <- icf[Date %in% on_t, ic]; d_on <- icf[Date %in% on_t, Date]
v_off <- icf[!(Date %in% on_t) & Date %in% NXT$ic_month, ic]
say("    대상 %s %s : dIC %+.5f  t %+.3f", f, s, R$delta_ic[bi], R$t[bi])
ord <- order(-abs(v_on - mean(v_off)))
say("    ON 상위 기여월 5건: %s", paste(sprintf("%s(ic %+.3f)", format(d_on[ord][1:5]), v_on[ord][1:5]), collapse=", "))
for (k in c(1,3,5)) {
  keep <- setdiff(seq_along(v_on), ord[seq_len(k)])
  d2 <- mean(v_on[keep]) - mean(v_off)
  se2 <- R$ic_sd_full[bi]*sqrt(1/length(keep)+1/length(v_off))*1.25
  say("    상위 %d개월 제거 -> dIC %+.5f  t %+.3f", k, d2, d2/se2)
}
half <- median(d_on)
h1 <- v_on[d_on <= half]; h2 <- v_on[d_on > half]
say("    ON 전반부(<=%s, n=%d) mean %+.5f · 후반부(n=%d) mean %+.5f · OFF mean %+.5f",
    format(half), length(h1), mean(h1), length(h2), mean(h2), mean(v_off))

say("=== C. 검정력 진단 (탐지가능 최소효과 vs 관측효과) ===")
for (i in seq_len(nrow(R)))
  say("    %-22s %s  탐지가능 최소 |dIC| (t=2) = %.5f · 관측 |dIC| %.5f (%.2fx) · 전기간 ic_mean %.5f 의 %.2fx",
      R$factor[i], R$signal[i], 2*R$se[i], abs(R$delta_ic[i]), abs(R$delta_ic[i])/(2*R$se[i]),
      R$required[i]/2, (2*R$se[i])/(R$required[i]/2))
say("=== 완료 ===")
