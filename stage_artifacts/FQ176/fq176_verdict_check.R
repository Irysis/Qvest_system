## FQ176 최종판정 검증 — 종합자가 독립 재현 + 미실시 적대검정
##  V1. 입력 실측 (가정 금지)
##  V2. 21쌍 ΔIC/t parity (저장 CSV 대비)
##  V3. 순환이동 귀무 재현 (placebo 렌즈 주장 독립확인)
##  V4. ★미실시 검정 — era 렌즈 step H 의 에피소드-t 3.074 가
##      "4/4 부호일관으로 고른 뒤 그 부호를 검정" 이라는 순환성을 통과하나
suppressPackageStartupMessages({ library(data.table) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[chk] ", fmt, "\n"), ...)); flush.console() }

SIG <- fread(file.path(OUT,"signals.csv")); SIG[, Date := as.Date(Date)]
IC  <- as.data.table(readRDS(file.path(OUT,"ic_series.rds"))); IC[, Date := as.Date(Date)]
EL  <- as.data.table(readRDS(file.path(OUT,"eligible.rds")))

## ---------------- V1. 입력 실측 ----------------
say("=== V1. 입력 실측 ===")
mo <- sort(unique(SIG$Date))
say("  signals.csv: %d행 · %d고유월 · %s ~ %s", nrow(SIG), length(mo), format(min(mo)), format(max(mo)))
say("  ic_series : %d행 · %d팩터 · %d고유월 · ic NA %d",
    nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date), sum(is.na(IC$ic)))
say("  월격자 간격(일): min %d / median %d / max %d",
    min(diff(mo)), median(as.numeric(diff(mo))), max(diff(mo)))
say("  n_ON: S1 %d · S2 %d · S3 %d (총 %d월)", sum(SIG$S1), sum(SIG$S2), sum(SIG$S3), length(mo))
say("  eligible.rds: %d쌍 · 팩터 %d종", nrow(EL), uniqueN(EL$factor))
icn <- IC[, .(n=.N), by=factor][order(n)]
say("  팩터별 IC월수: min %d (%s) / max %d", icn$n[1], icn$factor[1], max(icn$n))

## 정렬: 신호 index k -> IC index k+1 (adv_era_05_final.R 와 동일)
KI <- data.table(Date=mo, k=seq_along(mo))
build <- function(sig_col) {
  A <- data.table(sig_date=mo, k=seq_along(mo), on=SIG[match(mo, Date)][[sig_col]])
  A[, ki := k+1L]
  A
}
ICW <- dcast(IC, Date ~ factor, value.var="ic")
ICW <- merge(ICW, KI, by="Date"); setnames(ICW, "k", "ki")
FACS <- setdiff(names(ICW), c("Date","ki"))

## PIT 재확인: 측정 IC월 > 신호월 인가
A3 <- merge(build("S3"), ICW[, .(ki, ic_date=Date)], by="ki")
say("  PIT: meas_Date > sig_Date  %d/%d (위반 %d)",
    sum(A3$ic_date > A3$sig_date), nrow(A3), sum(A3$ic_date <= A3$sig_date))

## ---------------- V2. ΔIC / t parity ----------------
say("=== V2. 21쌍 ΔIC·t 독립 재현 (se = ic_sd_full*sqrt(1/n_on+1/n_off)*1.25) ===")
stat_one <- function(f, sig_col, on_vec=NULL) {
  A <- build(sig_col)
  if (!is.null(on_vec)) A[, on := on_vec]
  M <- merge(A, ICW[, c("ki", f), with=FALSE], by="ki")
  setnames(M, f, "ic"); M <- M[!is.na(ic)]
  on <- M[on==TRUE]$ic; off <- M[on==FALSE]$ic
  if (length(on) < 2 || length(off) < 2) return(list(d=NA_real_, t=NA_real_, n_on=length(on), n_off=length(off)))
  sdf <- sd(M$ic)
  d <- mean(on) - mean(off)
  se <- sdf * sqrt(1/length(on) + 1/length(off)) * 1.25
  list(d=d, t=d/se, n_on=length(on), n_off=length(off), se=se)
}
res <- rbindlist(lapply(seq_len(nrow(EL)), function(i) {
  f <- EL$factor[i]; s <- EL$signal[i]
  r <- stat_one(f, s)
  data.table(factor=f, signal=s, d_ic=r$d, t=r$t, n_on=r$n_on, n_off=r$n_off)
}))
res <- res[order(-abs(t))]
say("  재현 21쌍 · |t| 최대 5건:")
for (i in 1:5) say("    %-30s %s  dIC %+.5f  t %+.3f  (n_on %d)",
                   res$factor[i], res$signal[i], res$d_ic[i], res$t[i], res$n_on[i])
say("  |t| >= 2.0 인 쌍: %d개", sum(abs(res$t) >= 2.0, na.rm=TRUE))
say("  방향: 양(+) %d / 음(-) %d", sum(res$d_ic>0, na.rm=TRUE), sum(res$d_ic<0, na.rm=TRUE))

## 저장 CSV 대비 parity
chk <- list()
rv <- fread(file.path(OUT,"measured_risk_vol.csv"))
for (i in seq_len(nrow(rv))) {
  r <- res[factor==rv$factor[i] & signal==rv$signal[i]]
  chk[[length(chk)+1]] <- data.table(src="risk_vol", f=rv$factor[i], dd=abs(r$d_ic - rv$delta_ic[i]), dt=abs(r$t - rv$t_stat[i]))
}
vg <- fread(file.path(OUT,"measured_value_growth.csv"))
for (i in seq_len(nrow(vg))) {
  r <- res[factor==vg$factor[i] & signal==vg$signal[i]]
  chk[[length(chk)+1]] <- data.table(src="value_growth", f=vg$factor[i], dd=abs(r$d_ic - vg$delta_ic[i]), dt=abs(r$t - vg$t[i]))
}
qa <- fread(file.path(OUT,"measured_quality_accrual.csv"))
for (i in seq_len(nrow(qa))) {
  r <- res[factor==qa$factor[i] & signal==qa$signal[i]]
  chk[[length(chk)+1]] <- data.table(src="quality_accrual", f=qa$factor[i], dd=abs(r$d_ic - qa$delta_ic[i]), dt=abs(r$t - qa$t_stat[i]))
}
CH <- rbindlist(chk)
say("  parity vs 저장CSV (%d행): max|Δd| %.3e · max|Δt| %.3e", nrow(CH), max(CH$dd), max(CH$dt))

## ---------------- V3. 순환이동 귀무 ----------------
say("=== V3. 순환이동 귀무 (ON 블록구조 보존, 전수 shift) ===")
n <- length(mo)
on3 <- SIG[match(mo, Date)]$S3
shifts <- 1:(n-1)
obs_t <- res$t; names(obs_t) <- paste(res$factor, res$signal)
null_max <- numeric(length(shifts))
pcnt <- setNames(numeric(nrow(res)), paste(res$factor, res$signal))
for (si in seq_along(shifts)) {
  s <- shifts[si]
  onp <- c(on3[(n-s+1):n], on3[1:(n-s)])
  tv <- numeric(0)
  for (i in seq_len(nrow(res))) {
    if (res$signal[i] != "S3") next
    r <- stat_one(res$factor[i], "S3", on_vec=onp)
    key <- paste(res$factor[i], res$signal[i])
    tv <- c(tv, abs(r$t))
    if (!is.na(r$t) && abs(r$t) >= abs(obs_t[key])) pcnt[key] <- pcnt[key] + 1
  }
  null_max[si] <- max(tv, na.rm=TRUE)
}
s3keys <- paste(res$factor, res$signal)[res$signal=="S3"]
pv <- (pcnt[s3keys] + 1) / (length(shifts) + 1)
say("  S3 19쌍 개별 양측 p: min %.4f (%s) · median %.4f · p<0.05 인 쌍 %d개",
    min(pv), names(pv)[which.min(pv)], median(pv), sum(pv < 0.05))
obs_fw <- max(abs(obs_t[s3keys]))
p_fw <- (sum(null_max >= obs_fw) + 1) / (length(shifts) + 1)
say("  가족단위: 관측 max|t| %.3f · 귀무 max|t| 중앙값 %.3f · p_FW %.4f",
    obs_fw, median(null_max), p_fw)

## ---------------- V4. ★에피소드-t 의 선별 순환성 검정 ----------------
say("=== V4. era렌즈 step H (에피소드 t=3.074) 의 선별-조건부 귀무 ===")
runs_of <- function(v) {           # 원형 run 분해
  r <- rle(v); idx <- cumsum(r$lengths); st <- idx - r$lengths + 1
  L <- data.table(val=r$values, s=st, e=idx)[val==TRUE]
  if (nrow(L) >= 2 && v[1] && v[length(v)]) { # wrap 병합
    L[1, s := L[.N, s] - length(v)]; L <- L[-.N]
  }
  L
}
epi_stat <- function(f, onv) {
  M <- merge(data.table(ki=seq_along(mo)+1L, on=onv), ICW[, c("ki", f), with=FALSE], by="ki")
  setnames(M, f, "ic"); M <- M[!is.na(ic)]
  if (nrow(M) < 50) return(NULL)
  offm <- mean(M[on==FALSE]$ic)
  L <- runs_of(M$on)
  if (nrow(L) != 4) return(NULL)
  dv <- sapply(seq_len(nrow(L)), function(j) {
    ii <- L$s[j]:L$e[j]; ii <- ((ii - 1) %% nrow(M)) + 1
    mean(M$ic[ii]) - offm
  })
  if (any(!is.finite(dv)) || sd(dv) == 0) return(NULL)
  list(dv=dv, t=as.numeric(t.test(dv)$statistic), consistent=(all(dv>0) || all(dv<0)))
}
S3F <- unique(res[signal=="S3"]$factor)
obs <- rbindlist(lapply(S3F, function(f) {
  e <- epi_stat(f, on3); if (is.null(e)) return(NULL)
  data.table(factor=f, t_epi=e$t, consistent=e$consistent)
}))
say("  관측: S3 %d팩터 중 4/4 부호일관 %d개", nrow(obs), sum(obs$consistent))
say("  일관 팩터: %s", paste(sprintf("%s (t_epi %+.3f)", obs[consistent==TRUE]$factor, obs[consistent==TRUE]$t_epi), collapse=", "))
obs_sel <- max(abs(obs[consistent==TRUE]$t_epi))
say("  ★선별-조건부 관측통계 = max|t_epi| among 4/4일관 = %.3f", obs_sel)
say("  (참고) 일관 무시 전체 max|t_epi| = %.3f (%s)", max(abs(obs$t_epi)), obs$factor[which.max(abs(obs$t_epi))])

nullsel <- rep(NA_real_, length(shifts)); nullcons <- integer(length(shifts))
for (si in seq_along(shifts)) {
  s <- shifts[si]
  onp <- c(on3[(n-s+1):n], on3[1:(n-s)])
  tv <- c()
  for (f in S3F) { e <- epi_stat(f, onp); if (!is.null(e) && e$consistent) tv <- c(tv, abs(e$t)) }
  nullcons[si] <- length(tv)
  if (length(tv)) nullsel[si] <- max(tv)
}
valid <- !is.na(nullsel)
p_sel <- (sum(nullsel[valid] >= obs_sel) + 1) / (sum(valid) + 1)
say("  귀무 shift %d개 중 4/4일관 팩터가 존재한 경우 %d회 (%.0f%%)", length(shifts), sum(valid), 100*mean(valid))
say("  귀무 일관팩터 개수: 평균 %.2f · 관측 %d (관측이 %s)",
    mean(nullcons), sum(obs$consistent), ifelse(sum(obs$consistent) < mean(nullcons), "★귀무평균 미만", "귀무평균 이상"))
say("  귀무 max|t_epi| 분포: 중앙값 %.3f · q90 %.3f · q95 %.3f · 최대 %.3f",
    median(nullsel[valid]), quantile(nullsel[valid],.90), quantile(nullsel[valid],.95), max(nullsel[valid]))
say("  ★★선별-조건부 p = %.4f  -> %s", p_sel,
    ifelse(p_sel < 0.05, "생존", "반증 (에피소드 t 는 선별로 만들어진 값)"))
saveRDS(list(res=res, pv=pv, p_fw=p_fw, obs=obs, obs_sel=obs_sel, p_sel=p_sel,
             nullsel=nullsel, nullcons=nullcons),
        file.path(OUT, "verdict_check.rds"))
say("=== 완료 ===")
