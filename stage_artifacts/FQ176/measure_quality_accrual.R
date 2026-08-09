## FQ176 — 조건부 IC 측정 · 그룹 quality_accrual (Q* / AC* / XF*)
## metric_type = canonical_screen_diag. 자본 주장 없음.
##
## ★PIT 정렬 (명시)
##   - 패널 1행 = (Date = 월말 t, Ticker). 팩터 z 는 t 월말 관측치.
##   - Ret_1m[t] = t -> t+1 forward 1M 수익 (build_monthly_forward_returns 규약).
##   - 따라서 IC[t] = spearman( z[t], Ret_1m[t] ) = "t 월말 팩터값 x t 이후 1개월 수익".
##   - 하락신호 S*[t] 는 t 월말에 관측 가능 (BM_Ret shift(1) 로 이미 실현된 수익만 사용).
##   - 요구 정렬: signal at t  ->  IC measured at t+1  (즉 IC[t+1] = z[t+1] x ret(t+1->t+2)).
##     신호를 t 월말에 본 뒤 t+1 월말에 포지션을 짜서 t+2 까지 보유하는 구조 → 미래참조 없음.
##   - 코드상 구현 = IC 시계열을 팩터별로 정렬한 뒤, 신호를 **1개월 lead** 시켜 결합
##     (동치: IC 행에 signal_prev = S[t-1] 을 붙이고 signal_prev 로 ON/OFF 분할).

suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[qa] ", fmt, "\n"), ...)); flush.console() }

GROUP   <- "quality_accrual"
MIN_XS  <- 30L      # 자격 단계와 동일 (월별 rank-IC 최소 횡단면)
SE_INFL <- 1.25     # 지시 규약: se = ic_sd*sqrt(1/n_on+1/n_off)*1.25
T_BAR   <- 2.0

in_grp <- function(x) grepl("^(Q[0-9]|AC[0-9]|XF_)", x)

## =============================================================
## 1. 입력 실측 (가정 금지)
## =============================================================
say("=== 1. 입력 실측 ===")
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
say("  panel_full : %d행 · %d개월 · %s ~ %s · Ticker %d",
    nrow(PN), length(mo), format(min(mo)), format(max(mo)), uniqueN(PN$Ticker))
say("  관측단위   : 1행 = (월말 Date=t) x Ticker · Ret_1m = t->t+1 forward")
pm <- PN[, .N, by=Date][order(Date)]
say("  월별 종목수: median %.0f (min %d / max %d) · Ret_1m NA %d",
    median(pm$N), min(pm$N), max(pm$N), sum(is.na(PN$Ret_1m)))

ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  eligible   : %d쌍 (팩터 %d종)", nrow(ELI), uniqueN(ELI$factor))

SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
setorder(SIG, Date)
stopifnot(identical(SIG$Date, mo))
say("  signals    : %d개월 · Date 집합 == panel 월 집합 (검증 통과)", nrow(SIG))
for (s in c("S1","S2","S3"))
  say("    %s ON %d (%.1f%%) / OFF %d", s, sum(SIG[[s]]), 100*mean(SIG[[s]]), sum(!SIG[[s]]))

## =============================================================
## 2. 그룹 쌍 선택 (0 은 정지 신호)
## =============================================================
say("=== 2. 그룹 '%s' 자격통과 쌍 선택 (^Q / ^AC / ^XF) ===", GROUP)
G <- ELI[in_grp(factor)][order(factor, signal)]
say("  선택된 쌍 %d (전체 자격통과 %d 중)", nrow(G), nrow(ELI))
if (!nrow(G)) {
  say("  ★그룹 소속 자격통과 쌍 0건 — 정지 신호. 빈 결과 저장 후 종료.")
  fwrite(data.table(), file.path(OUT, "measured_quality_accrual.csv"))
  quit(save="no")
}
for (i in seq_len(nrow(G)))
  say("    %-24s %s  ic_mean %+.5f · ic_sd %.5f · required(prereg) %.5f · n_ON/n_OFF %d/%d",
      G$factor[i], G$signal[i], G$ic_mean[i], G$ic_sd[i], G$required[i], G$n_ON[i], G$n_OFF[i])
FSEL <- sort(unique(G$factor))

## =============================================================
## 3. 월별 rank-IC 재계산 (panel_full 에서 독립 재산출 + ic_series 대조)
## =============================================================
say("=== 3. 월별 rank-IC 재산출 (spearman, min_xs=%d) ===", MIN_XS)
ic_list <- list()
for (f in FSEL) {
  D <- PN[!is.na(get(f)) & !is.na(Ret_1m), .(Date, z = get(f), r = Ret_1m)]
  ICm <- D[, .(n_xs = .N,
               ic = if (.N >= MIN_XS) suppressWarnings(cor(z, r, method="spearman")) else NA_real_),
           by = Date][!is.na(ic)][order(Date)]
  ic_list[[f]] <- data.table(factor = f, Date = ICm$Date, ic = ICm$ic, n_xs = ICm$n_xs)
  say("  %-24s %d개월 · ic_mean %+.5f · ic_sd %.5f · xs median %.0f",
      f, nrow(ICm), mean(ICm$ic), sd(ICm$ic), median(ICm$n_xs))
}
IC <- rbindlist(ic_list)

## 대조: 자격 단계 산출물 ic_series.rds
IC0 <- as.data.table(readRDS(file.path(OUT, "ic_series.rds")))[factor %in% FSEL]
IC0[, Date := as.Date(Date)]
CMP <- merge(IC[, .(factor, Date, ic_new = ic)], IC0[, .(factor, Date, ic_old = ic)],
             by = c("factor","Date"), all = TRUE)
say("  ic_series.rds 대조: 공통행 %d · new-only %d · old-only %d · max|diff| %.3e",
    sum(!is.na(CMP$ic_new) & !is.na(CMP$ic_old)), sum(is.na(CMP$ic_old)), sum(is.na(CMP$ic_new)),
    max(abs(CMP$ic_new - CMP$ic_old), na.rm = TRUE))

## =============================================================
## 4. ★PIT 정렬 구축 + 검증 출력
## =============================================================
say("=== 4. ★PIT 정렬: signal at t -> IC at t+1 ===")
MOIDX <- data.table(Date = mo, idx = seq_along(mo))
SIGL <- merge(SIG, MOIDX, by = "Date")
## 신호를 1개월 lead: IC 행(t+1)에 붙일 signal 은 직전월(t) 값
LEAD <- copy(SIGL)[, `:=`(idx_ic = idx + 1L)]
LEAD <- merge(LEAD, MOIDX[, .(Date_ic = Date, idx_ic = idx)], by = "idx_ic")
LEAD <- LEAD[, .(Date_ic, Date_sig = Date, S1, S2, S3)]
say("  lead 매핑: 신호월 %d개 중 다음 패널월이 존재하는 %d개만 사용 (마지막 월 %s 는 t+1 없음 → 제외)",
    nrow(SIGL), nrow(LEAD), format(max(mo)))
lag_days <- as.numeric(LEAD$Date_ic - LEAD$Date_sig)
say("  정렬 검증 A: Date_ic - Date_sig 일수 → median %.0f · min %.0f · max %.0f · 1개월 아닌 건 %d",
    median(lag_days), min(lag_days), max(lag_days), sum(lag_days < 26 | lag_days > 40))
say("  정렬 검증 B: Date_ic > Date_sig 전건? %s (%d/%d)",
    all(LEAD$Date_ic > LEAD$Date_sig), sum(LEAD$Date_ic > LEAD$Date_sig), nrow(LEAD))
ex <- head(LEAD[S3 == TRUE], 3)
for (i in seq_len(nrow(ex)))
  say("  정렬 예시 %d: S3 신호 관측 %s(월말) → IC 측정월 %s (= z[%s] x ret %s→다음월). 신호가 IC 재료보다 %.0f일 앞섬",
      i, format(ex$Date_sig[i]), format(ex$Date_ic[i]), format(ex$Date_ic[i]), format(ex$Date_ic[i]),
      as.numeric(ex$Date_ic[i] - ex$Date_sig[i]))
say("  → 신호(t 월말 관측) 이후 시점의 팩터값·수익만 IC 에 들어감 = 미래참조 없음")

## =============================================================
## 5. 조건부 IC 측정
## =============================================================
say("=== 5. 조건부 IC 측정 ===")
res <- list()
for (i in seq_len(nrow(G))) {
  f <- G$factor[i]; s <- G$signal[i]
  ICf <- IC[factor == f][order(Date)]
  M <- merge(ICf, LEAD[, .(Date = Date_ic, Date_sig, sg = get(s))], by = "Date")
  M <- M[!is.na(sg)]
  on  <- M[sg == TRUE,  ic]
  off <- M[sg == FALSE, ic]
  n_on <- length(on); n_off <- length(off)

  ic_sd_full <- sd(ICf$ic)                       # 자격 단계와 동일 컨벤션(전기간 ic_sd)
  d_ic <- mean(on) - mean(off)
  se   <- ic_sd_full * sqrt(1/n_on + 1/n_off) * SE_INFL
  tval <- d_ic / se
  req_prereg   <- G$required[i]                                            # 자격 단계 값
  req_measured <- T_BAR * ic_sd_full * sqrt(1/n_on + 1/n_off) * SE_INFL     # 실측 분할로 재계산

  verdict <- if (abs(tval) >= T_BAR) "SIGNIFICANT"
             else if (abs(d_ic) >= req_prereg) "NULL_POWERED"
             else "INCONCLUSIVE_UNDERPOWERED"

  ## 진단: 동월(비-lead) 정렬 — 자격 단계가 쓴 정렬. 판정용 아님.
  Msm <- merge(ICf, SIG[, .(Date, sg = get(s))], by = "Date")
  on_sm <- Msm[sg == TRUE, ic]; off_sm <- Msm[sg == FALSE, ic]
  d_sm <- mean(on_sm) - mean(off_sm)
  se_sm <- ic_sd_full * sqrt(1/length(on_sm) + 1/length(off_sm)) * SE_INFL

  ## Welch 진단(참고): 그룹별 실제 분산 사용
  se_w <- sqrt(var(on)/n_on + var(off)/n_off)

  res[[i]] <- data.table(
    group = GROUP, factor = f, signal = s,
    alignment = "signal_t_to_ic_t+1",
    n_months_ic = nrow(ICf), n_on = n_on, n_off = n_off,
    ic_on_mean = mean(on), ic_off_mean = mean(off), delta_ic = d_ic,
    ic_sd_full = ic_sd_full, se = se, t_stat = tval,
    required_prereg = req_prereg, required_measured = req_measured,
    abs_delta_over_required = abs(d_ic)/req_prereg,
    verdict = verdict,
    direction = ifelse(d_ic > 0, "IC_higher_after_drawdown", "IC_lower_after_drawdown"),
    ic_all_mean = mean(ICf$ic),
    ic_on_sd = sd(on), ic_off_sd = sd(off),
    t_welch_diag = d_ic/se_w,
    delta_ic_samemonth_diag = d_sm, t_samemonth_diag = d_sm/se_sm,
    n_on_prereg = G$n_ON[i], n_off_prereg = G$n_OFF[i],
    metric_type = "canonical_screen_diag")
}
R <- rbindlist(res)
R <- R[order(-abs(t_stat))]

say("  --- 결과 (|t| 내림차순) ---")
for (i in seq_len(nrow(R)))
  say("  %-24s %s | n_ON %d n_OFF %d | IC_ON %+.5f  IC_OFF %+.5f  ΔIC %+.5f | se %.5f  t %+.3f | req(prereg) %.5f (|Δ|/req %.2f) | %s",
      R$factor[i], R$signal[i], R$n_on[i], R$n_off[i], R$ic_on_mean[i], R$ic_off_mean[i],
      R$delta_ic[i], R$se[i], R$t_stat[i], R$required_prereg[i],
      R$abs_delta_over_required[i], R$verdict[i])

say("  --- 진단 대조 (판정 아님) ---")
for (i in seq_len(nrow(R)))
  say("  %-24s t(pooled) %+.3f · t(Welch) %+.3f · ΔIC 동월정렬 %+.5f (t %+.3f) · required 재계산 %.5f",
      R$factor[i], R$t_stat[i], R$t_welch_diag[i], R$delta_ic_samemonth_diag[i],
      R$t_samemonth_diag[i], R$required_measured[i])

say("  판정 분포: %s", paste(sprintf("%s=%d", names(table(R$verdict)), as.integer(table(R$verdict))), collapse=" · "))
say("  방향: 양(+ΔIC, 하락 후 IC 상승) %d / 음 %d", sum(R$delta_ic > 0), sum(R$delta_ic < 0))

## ON 월의 에피소드 구조 (독립 표본 수 진단)
onm <- LEAD[S3 == TRUE, Date_ic]
brk <- c(1, which(as.numeric(diff(onm)) > 45) + 1)
say("  ★ON 월 %d개의 에피소드 구조: %d개 군집 (연속월 덩어리) — 유효 독립표본은 월수보다 훨씬 작음",
    length(onm), length(brk))
for (k in seq_along(brk)) {
  st <- brk[k]; en <- if (k < length(brk)) brk[k+1]-1 else length(onm)
  say("    군집 %d: %s ~ %s (%d개월)", k, format(onm[st]), format(onm[en]), en-st+1)
}

fwrite(R, file.path(OUT, "measured_quality_accrual.csv"))
say("=== 저장: %s (%d행) ===", file.path(OUT,"measured_quality_accrual.csv"), nrow(R))
cat(toJSON(R[, .(factor, signal, n_on, n_off, delta_ic, t_stat, required_prereg, verdict, direction)],
           digits = NA, pretty = TRUE), "\n")
