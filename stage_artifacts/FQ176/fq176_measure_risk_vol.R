## FQ176 — 조건부 IC 측정 · 그룹 risk_vol (D*/R* = 변동성·VaR·CVaR·베타)
## metric_type = canonical_screen_diag. 자본 주장 없음.
## PIT 정렬 (명시):
##   신호 S[t] : 월말 t 시점 관측가능분 (BM 실현수익 shift(1) 기반, 자격단계 규약)
##   측정 IC   : IC[t+1] = corr_spearman( z(Date=t+1) , Ret_1m(Date=t+1) )
##               Ret_1m(Date=d) 는 이미 forward 1M (d -> d+1) 이므로
##               IC[t+1] 의 수익창 = (t+1) -> (t+2)  ⇒ 신호 t 에 대해 전량 미래.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[rv] ", fmt, "\n"), ...)); flush.console() }

MIN_XS <- 30L   # 자격단계와 동일 규약
GRP_RE <- "^(D|R)[0-9]{2}_"   # 그룹 risk_vol 정의

## =========================================================
## 0. ★입력 실측 (가정 금지)
## =========================================================
say("=== 0. 입력 실측 ===")
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
say("  panel_full.rds : %d행 · %d개월 · %s ~ %s", nrow(PN), length(mo),
    format(min(mo)), format(max(mo)))
say("  관측단위       : 1행 = (신호월말 Date x Ticker)  [wide: 팩터 1컬럼당 z]")
say("  컬럼 %d개 (Date/Ticker/adv/Ret_1m 제외 팩터 %d)", ncol(PN),
    length(setdiff(names(PN), c("Date","Ticker","Ret_1m","adv"))))
pm <- PN[, .N, by = Date][order(Date)]
say("  월별 종목수    : median %.0f (min %d / max %d) · 고유 Ticker %d",
    median(pm$N), min(pm$N), max(pm$N), uniqueN(PN$Ticker))
say("  Ret_1m         : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(PN$Ret_1m, na.rm=TRUE), sd(PN$Ret_1m, na.rm=TRUE),
    min(PN$Ret_1m, na.rm=TRUE), max(PN$Ret_1m, na.rm=TRUE), sum(is.na(PN$Ret_1m)))
## 월 격자 연속성 실측 (t+1 매핑의 전제)
gap <- as.integer(diff(mo))
say("  월격자 간격(일): min %d · median %.0f · max %d · 60일초과 간격 %d건",
    min(gap), median(gap), max(gap), sum(gap > 60))
if (sum(gap > 60)) print(data.table(from = mo[-length(mo)][gap>60], to = mo[-1][gap>60], gap = gap[gap>60]))

SIG <- fread(file.path(OUT, "signals.csv"))
SIG[, Date := as.Date(Date)]
say("  signals.csv    : %d행 · %s ~ %s · S1 ON %d · S2 ON %d · S3 ON %d",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)),
    sum(SIG$S1), sum(SIG$S2), sum(SIG$S3))
say("  신호 Date 격자 == 패널 월격자 : %s",
    identical(sort(SIG$Date), mo))

ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  eligible.rds   : %d쌍 · 고유팩터 %d", nrow(ELI), uniqueN(ELI$factor))

## =========================================================
## 1. 그룹 선별 (risk_vol)
## =========================================================
say("=== 1. 그룹 risk_vol 선별 (정규식 %s) ===", GRP_RE)
allF   <- setdiff(names(PN), c("Date","Ticker","Ret_1m","adv"))
grpF   <- sort(allF[grepl(GRP_RE, allF)])
say("  패널 내 D*/R* 팩터 %d개: %s", length(grpF), paste(grpF, collapse=", "))
EG <- ELI[grepl(GRP_RE, factor)][order(factor, signal)]
say("  그 중 자격통과 쌍 %d개", nrow(EG))
notEli <- setdiff(grpF, unique(EG$factor))
say("  자격 미통과(측정 제외) 팩터 %d개: %s", length(notEli),
    ifelse(length(notEli), paste(notEli, collapse=", "), "-"))
if (nrow(EG) == 0L) {
  say("★ 그룹 내 자격통과 쌍 0 — 빈 결과 반환 (0 은 정지 신호이지 합격 아님)")
  fwrite(data.table(), file.path(OUT, "measured_risk_vol.csv")); quit(save="no")
}
for (i in seq_len(nrow(EG)))
  say("    %-14s %s  required %.5f · n_ON(자격) %d / n_OFF %d · ic_mean %+.5f · ic_sd %.5f",
      EG$factor[i], EG$signal[i], EG$required[i], EG$n_ON[i], EG$n_OFF[i], EG$ic_mean[i], EG$ic_sd[i])

## =========================================================
## 2. 월별 rank-IC 재산출 (그룹 팩터만) + 기존 ic_series 대조
## =========================================================
say("=== 2. 월별 rank-IC 재산출 (spearman, 최소 횡단면 %d) ===", MIN_XS)
icl <- list()
for (f in unique(EG$factor)) {
  D <- PN[!is.na(get(f)) & !is.na(Ret_1m), .(Date, z = get(f), r = Ret_1m)]
  M <- D[, .(n_xs = .N, ic = if (.N >= MIN_XS) suppressWarnings(cor(z, r, method="spearman")) else NA_real_), by = Date]
  M <- M[!is.na(ic)][order(Date)]
  icl[[f]] <- data.table(factor = f, Date = M$Date, ic = M$ic, n_xs = M$n_xs)
  say("  %-14s IC월 %d (%s~%s) · ic_mean %+.5f · ic_sd %.5f · 월평균 횡단면 %.0f",
      f, nrow(M), format(min(M$Date)), format(max(M$Date)), mean(M$ic), sd(M$ic), mean(M$n_xs))
}
IC <- rbindlist(icl)
## 자격단계 산출물과 대조 (재현성)
IC0 <- as.data.table(readRDS(file.path(OUT, "ic_series.rds")))[factor %in% unique(EG$factor)]
IC0[, Date := as.Date(Date)]
CK <- merge(IC[, .(factor, Date, ic_new = ic)], IC0[, .(factor, Date, ic_old = ic)],
            by = c("factor","Date"), all = TRUE)
say("  자격단계 ic_series 대조: 공통 %d행 · NA쌍 %d · max|차| %.3e",
    nrow(CK), sum(is.na(CK$ic_new) | is.na(CK$ic_old)),
    max(abs(CK$ic_new - CK$ic_old), na.rm = TRUE))

## =========================================================
## 3. ★PIT 정렬: 신호 t -> IC(t+1)  (명시 + 검증 출력)
## =========================================================
say("=== 3. PIT 정렬 구축 · 검증 ===")
MOI <- data.table(Date = mo, idx = seq_along(mo))
SIGX <- merge(SIG[, .(Date, S1, S2, S3)], MOI, by = "Date")
setorder(SIGX, idx)
## 신호월 t (idx i) -> 측정월 t+1 (idx i+1)
SIGX[, meas_idx  := idx + 1L]
SIGX[, meas_Date := ifelse(meas_idx <= length(mo), as.character(mo[pmin(meas_idx, length(mo))]), NA_character_)]
SIGX[meas_idx > length(mo), meas_Date := NA_character_]
SIGX[, meas_Date := as.Date(meas_Date)]
say("  매핑: 신호월 %d개 -> 측정월 %d개 (마지막 월 %s 는 t+1 부재로 탈락)",
    nrow(SIGX), sum(!is.na(SIGX$meas_Date)), format(max(mo)))
## 검증 출력 A: S3 ON 인 신호월 앞 5건의 (t, t+1) 짝 + 그 달 IC 수익창
say("  --- 검증 A: S3 ON 신호월 -> 측정월 매핑 (앞 6건) ---")
vA <- SIGX[S3 == TRUE][order(idx)][1:min(6, sum(SIGX$S3))]
for (i in seq_len(nrow(vA))) {
  d_t  <- vA$Date[i]; d_n <- vA$meas_Date[i]
  nxt  <- if (!is.na(d_n)) mo[vA$meas_idx[i] + 1L] else NA
  say("    t=%s (S3 ON) -> 측정 IC Date=%s ; 그 IC 의 수익창 = %s -> %s (전량 t 이후)",
      format(d_t), format(d_n), format(d_n), format(nxt))
}
## 검증 B: 측정 IC Date 는 항상 신호 Date 보다 크다
chk <- SIGX[!is.na(meas_Date)]
say("  --- 검증 B: 측정월 > 신호월 성립 %d/%d (위반 %d) ---",
    sum(chk$meas_Date > chk$Date), nrow(chk), sum(chk$meas_Date <= chk$Date))
## 검증 C: 동월/과거 IC 사용 없음 = 신호 Date 자신의 IC 는 어떤 집단에도 안 들어감
say("  --- 검증 C: 측정에 쓰는 IC Date 집합 ∩ 신호 자기달 = 오프셋 1 (동월 IC 미사용 확인) ---")
say("      신호 Date 예시 %s / 측정 Date 예시 %s (오프셋 %d개월)",
    format(chk$Date[1]), format(chk$meas_Date[1]),
    round(as.numeric(chk$meas_Date[1] - chk$Date[1])/30.44))

## =========================================================
## 4. 조건부 IC 측정
## =========================================================
say("=== 4. 조건부 IC 측정 (ON=신호달 다음달 IC / OFF=나머지) ===")
res <- list()
for (k in seq_len(nrow(EG))) {
  f <- EG$factor[k]; s <- EG$signal[k]
  icf <- IC[factor == f][order(Date)]
  MAP <- SIGX[!is.na(meas_Date), .(sig_Date = Date, on = get(s), Date = meas_Date)]
  J   <- merge(icf[, .(Date, ic, n_xs)], MAP, by = "Date")   # inner: IC 존재하는 측정월만
  on  <- J[on == TRUE]; off <- J[on == FALSE]
  n_on <- nrow(on); n_off <- nrow(off)
  ic_on  <- if (n_on)  mean(on$ic)  else NA_real_
  ic_off <- if (n_off) mean(off$ic) else NA_real_
  dIC <- ic_on - ic_off
  ic_sd_full <- sd(icf$ic)                                   # 자격단계와 동일 (전기간 pooled)
  se  <- ic_sd_full * sqrt(1/n_on + 1/n_off) * 1.25
  tst <- dIC / se
  req_stage <- EG$required[k]
  req_meas  <- 2.0 * ic_sd_full * sqrt(1/n_on + 1/n_off) * 1.25
  ## Welch 보조 (진단용, 판정 아님)
  se_w <- sqrt(ifelse(n_on>1, var(on$ic)/n_on, NA_real_) + ifelse(n_off>1, var(off$ic)/n_off, NA_real_))
  t_w  <- dIC / se_w
  verdict <- if (!is.na(tst) && abs(tst) >= 2.0) "SIGNIFICANT" else
             if (!is.na(dIC) && abs(dIC) >= req_stage) "NULL_POWERED" else "INCONCLUSIVE_UNDERPOWERED"
  res[[k]] <- data.table(
    group = "risk_vol", factor = f, signal = s,
    n_meas_months = nrow(J), n_on = n_on, n_off = n_off,
    n_on_stage = EG$n_ON[k], n_off_stage = EG$n_OFF[k],
    ic_on = ic_on, ic_off = ic_off, delta_ic = dIC,
    ic_sd_full = ic_sd_full, se = se, t_stat = tst,
    se_welch = se_w, t_welch = t_w,
    required_stage = req_stage, required_measured = req_meas,
    abs_dic_over_required = abs(dIC)/req_stage,
    ic_full_mean = mean(icf$ic),
    sd_on = if (n_on>1) sd(on$ic) else NA_real_,
    sd_off = if (n_off>1) sd(off$ic) else NA_real_,
    verdict = verdict, metric_type = "canonical_screen_diag")
}
R <- rbindlist(res)
R <- R[order(-abs(t_stat))]
for (i in seq_len(nrow(R)))
  say("  %-14s %s | n_ON %2d / n_OFF %3d | IC_ON %+.5f  IC_OFF %+.5f  ΔIC %+.5f | se %.5f  t %+.3f (Welch %+.3f) | req %.5f (|ΔIC|/req %.3f) -> %s",
      R$factor[i], R$signal[i], R$n_on[i], R$n_off[i], R$ic_on[i], R$ic_off[i],
      R$delta_ic[i], R$se[i], R$t_stat[i], R$t_welch[i], R$required_stage[i],
      R$abs_dic_over_required[i], R$verdict[i])

fwrite(R, file.path(OUT, "measured_risk_vol.csv"))
say("  저장: %s", file.path(OUT, "measured_risk_vol.csv"))

## =========================================================
## 5. 방향 요약 + 판정 라벨 분포
## =========================================================
say("=== 5. 요약 ===")
say("  방향: ΔIC>0 %d쌍 / ΔIC<0 %d쌍 (ΔIC>0 = 하락신호 다음달 팩터 판별력 강화)",
    sum(R$delta_ic > 0), sum(R$delta_ic < 0))
print(R[, .N, by = verdict])
say("  ΔIC 범위 %+.5f ~ %+.5f · |t| 범위 %.3f ~ %.3f",
    min(R$delta_ic), max(R$delta_ic), min(abs(R$t_stat)), max(abs(R$t_stat)))
## ON 집단 중복성 진단: 모든 쌍이 같은 신호(S3)면 ON 월 집합이 동일 -> 쌍 간 독립 아님
say("  ON 월 집합 (신호별):")
for (s in unique(R$signal)) {
  onm <- SIGX[!is.na(meas_Date) & get(s) == TRUE, meas_Date]
  say("    %s : 측정월 %d개 = %s", s, length(onm),
      paste(format(head(sort(onm), 60)), collapse=" "))
}
summ <- list(
  metric_type = "canonical_screen_diag", group = "risk_vol",
  pit_alignment = "signal S[t] (obs at month-end t) -> IC[t+1] = spearman(z(t+1), Ret_1m(t+1)); Ret_1m(d)=forward d->d+1, so return window (t+1)->(t+2), strictly after t",
  n_pairs = nrow(R),
  n_significant = sum(R$verdict == "SIGNIFICANT"),
  n_null_powered = sum(R$verdict == "NULL_POWERED"),
  n_underpowered = sum(R$verdict == "INCONCLUSIVE_UNDERPOWERED"),
  n_positive = sum(R$delta_ic > 0), n_negative = sum(R$delta_ic < 0))
write_json(summ, file.path(OUT, "measured_risk_vol_summary.json"), auto_unbox = TRUE, digits = NA, pretty = TRUE)
say("=== 완료 ===")
