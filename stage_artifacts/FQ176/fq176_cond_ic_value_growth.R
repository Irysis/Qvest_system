## FQ176 — 조건부 IC 측정 · 그룹 value_growth (V*/GR*)
## metric_type = canonical_screen_diag. 자본 주장 없음.
##
## ★PIT 정렬 (지시 4항 명시 구현)
##   신호 S[t]      : 월말 t 에 관측가능한 벤치 하락신호 (power_gate 5절: BM_Ret shift(1) 사용)
##   측정 대상 IC   : IC[t+1] = spearman( z(t+1) , Ret_1m(t+1) )
##   Ret_1m(t+1)    : t+1 -> t+2 forward (build_monthly_forward_returns 규약)
##   => 신호(월말 t) 는 팩터관측(월말 t+1) 보다 앞서고, 수익은 t+1 이후 실현. 미래참조 없음.
##   구현 = 패널 월 그리드에서 신호월의 '다음 행' 을 타겟월로 매핑 (nxt map).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cond-vg] ", fmt, "\n"), ...)); flush.console() }

GROUP     <- "value_growth"
GRP_RE    <- "^(V|GR)[0-9]{2}_"    # V01_BM/V02_EP/V03_CFP/V04_fPER + GR01~GR04
T_THRESH  <- 2.0
SE_INFL   <- 1.25                  # 지시 규약: se = ic_sd*sqrt(1/n_on+1/n_off)*1.25

## =============================================================
## 1. ★입력 실측 (가정 금지 — 행수/개월수/관측단위/범위)
## =============================================================
say("=== 1. ★입력 실측 ===")
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
pm <- PN[, .N, by = Date][order(Date)]
say("  panel_full.rds")
say("    행수        : %d", nrow(PN))
say("    개월수      : %d", length(mo))
say("    기간        : %s ~ %s", format(min(mo)), format(max(mo)))
say("    관측단위    : (신호월말 Date x Ticker) 1행 = 1종목월")
say("    월별 종목수 : median %.1f (min %d / max %d)", median(pm$N), min(pm$N), max(pm$N))
say("    고유 Ticker : %d · 컬럼 %d", uniqueN(PN$Ticker), ncol(PN))
say("    Ret_1m      : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(PN$Ret_1m), sd(PN$Ret_1m), min(PN$Ret_1m), max(PN$Ret_1m), sum(is.na(PN$Ret_1m)))
gaps <- as.numeric(diff(mo))
say("    월 간격(일) : median %.0f (min %.0f / max %.0f) — 월간 그리드 확인",
    median(gaps), min(gaps), max(gaps))

IC <- as.data.table(readRDS(file.path(OUT, "ic_series.rds")))
IC[, Date := as.Date(Date)]
say("  ic_series.rds : %d행 · 팩터 %d · 개월 %d (%s ~ %s) · 관측단위 = (factor x Date) 월별 rank-IC",
    nrow(IC), uniqueN(IC$factor), uniqueN(IC$Date), format(min(IC$Date)), format(max(IC$Date)))
say("    ic          : mean %+.5f · sd %.5f · n_xs median %.0f",
    mean(IC$ic), sd(IC$ic), median(IC$n_xs))

SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
for (s in c("S1","S2","S3")) set(SIG, j = s, value = as.logical(SIG[[s]]))
say("  signals.csv   : %d행 (%s ~ %s) · 관측단위 = 월(신호 관측시점 = 그 월말)",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)))
for (s in c("S1","S2","S3"))
  say("    %s: n_ON %d (%.1f%%) / n_OFF %d", s, sum(SIG[[s]]), 100*mean(SIG[[s]]), sum(!SIG[[s]]))

ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  eligible.rds  : 자격통과 쌍 %d (고유 팩터 %d)", nrow(ELI), uniqueN(ELI$factor))

## =============================================================
## 2. ★PIT 검증 A — ic_series 의 의미 재현 (z(d) x Ret_1m(d))
## =============================================================
say("=== 2. ★PIT 검증 A: ic_series 재현 (같은 Date 의 z 와 Ret_1m) ===")
chk_f <- "V02_EP"
chk_d <- IC[factor == chk_f, Date]
chk_d <- chk_d[round(seq(1, length(chk_d), length.out = 3))]
for (d in chk_d) {
  d <- as.Date(d, origin = "1970-01-01")
  D <- PN[Date == d & !is.na(get(chk_f)) & !is.na(Ret_1m)]
  man <- suppressWarnings(cor(D[[chk_f]], D$Ret_1m, method = "spearman"))
  sto <- IC[factor == chk_f & Date == d, ic]
  say("    %s %s : 수동재계산 %+.6f vs ic_series %+.6f  (차 %.2e, n_xs %d) %s",
      chk_f, format(d), man, sto, abs(man - sto), nrow(D),
      ifelse(abs(man - sto) < 1e-10, "일치", "★불일치"))
}

## =============================================================
## 3. ★PIT 검증 B — Ret_1m 의 forward 방향 (벤치 대조)
## =============================================================
say("=== 3. ★PIT 검증 B: Ret_1m forward 방향 (횡단면평균 vs BM_Ret 시차별 상관) ===")
P0  <- readRDS(file.path(ROOT, "stage_artifacts/WT_D20260809_001/p0_panels.rds"))
BEN <- as.data.table(P0$bench)[, .(Date = as.Date(Date), BM_Ret)][order(Date)]
XS  <- PN[, .(xs_ret = mean(Ret_1m)), by = Date][order(Date)]
MG  <- merge(XS, BEN, by = "Date", all.x = TRUE)[order(Date)]
MG[, `:=`(bm_lead = shift(BM_Ret, 1L, type = "lead"), bm_lag = shift(BM_Ret, 1L, type = "lag"))]
say("    cor(xs_ret[t], BM_Ret[t])   = %+.4f   <- 둘 다 forward 면 최대여야",
    cor(MG$xs_ret, MG$BM_Ret, use = "complete.obs"))
say("    cor(xs_ret[t], BM_Ret[t+1]) = %+.4f", cor(MG$xs_ret, MG$bm_lead, use = "complete.obs"))
say("    cor(xs_ret[t], BM_Ret[t-1]) = %+.4f", cor(MG$xs_ret, MG$bm_lag,  use = "complete.obs"))
say("    (power_gate 5절 규약: BM_Ret[t] = t->t+1 forward. lag0 최대 = Ret_1m 도 forward)")

## =============================================================
## 4. ★PIT 검증 C — 신호월 t -> 타겟 IC 월 t+1 매핑
## =============================================================
say("=== 4. ★PIT 검증 C: 신호월 t -> 측정월 t+1 매핑 ===")
NXT <- data.table(sig_month = mo[-length(mo)], ic_month = mo[-1])
NXT[, gap_days := as.numeric(ic_month - sig_month)]
say("    매핑 쌍 %d (패널 %d개월 중 마지막 월 %s 는 신호월로 사용 불가 = 후속 IC 없음)",
    nrow(NXT), length(mo), format(mo[length(mo)]))
say("    첫 월 %s 는 타겟월로 사용 불가 (선행 신호월 없음)", format(mo[1]))
say("    gap_days: median %.0f (min %.0f / max %.0f) — 전건 1개월 간격 %s",
    median(NXT$gap_days), min(NXT$gap_days), max(NXT$gap_days),
    ifelse(all(NXT$gap_days >= 26 & NXT$gap_days <= 40), "확인", "★이상"))
s3_on <- SIG[S3 == TRUE, Date]
ex <- head(NXT[sig_month %in% s3_on], 5)
say("    예시(S3 ON 신호월 -> 측정 IC 월):")
for (i in seq_len(nrow(ex)))
  say("      신호 t=%s (월말 관측) -> IC 측정월 t+1=%s  [z(t+1) x Ret_1m(t+1): t+1->t+2 수익]",
      format(ex$sig_month[i]), format(ex$ic_month[i]))

## =============================================================
## 5. 그룹 선별 — value_growth (V*/GR*) 중 자격통과 쌍만
## =============================================================
say("=== 5. 그룹 선별 (%s = %s) ===", GROUP, GRP_RE)
all_grp_factors <- sort(grep(GRP_RE, unique(IC$factor), value = TRUE))
say("    패널 내 %s 계열 팩터 %d종: %s", GROUP, length(all_grp_factors),
    paste(all_grp_factors, collapse = ", "))
G <- ELI[grepl(GRP_RE, factor)][order(factor, signal)]
say("    자격통과 쌍 %d건 (전체 자격통과 %d건 중):", nrow(G), nrow(ELI))
if (nrow(G) == 0L) say("    ★0건 — 정지 신호 (합격 아님)")
for (i in seq_len(nrow(G)))
  say("      %-22s %s  ic_mean %+.5f · ic_sd %.5f · n_mo %d · required %.5f (bar %.5f, ratio %.3f)",
      G$factor[i], G$signal[i], G$ic_mean[i], G$ic_sd[i], G$n_months[i],
      G$required[i], G$bar[i], G$ratio[i])
excl <- setdiff(all_grp_factors, unique(G$factor))
say("    자격 미달로 제외된 %s 팩터: %s", GROUP,
    ifelse(length(excl) == 0, "(없음)", paste(excl, collapse = ", ")))

## =============================================================
## 6. 측정
## =============================================================
say("=== 6. 조건부 IC 측정 ===")
res <- list()
for (i in seq_len(nrow(G))) {
  f <- G$factor[i]; s <- G$signal[i]
  on_sig  <- SIG[get(s) == TRUE,  Date]
  off_sig <- SIG[get(s) == FALSE, Date]
  on_tgt  <- NXT[sig_month %in% on_sig,  ic_month]
  off_tgt <- NXT[sig_month %in% off_sig, ic_month]
  stopifnot(length(intersect(on_tgt, off_tgt)) == 0L)   # 타겟월 배타성

  icf  <- IC[factor == f]
  v_on  <- icf[Date %in% on_tgt,  ic]
  v_off <- icf[Date %in% off_tgt, ic]
  n_on <- length(v_on); n_off <- length(v_off)

  m_on  <- if (n_on  > 0) mean(v_on)  else NA_real_
  m_off <- if (n_off > 0) mean(v_off) else NA_real_
  dIC   <- m_on - m_off
  ic_sd_full <- G$ic_sd[i]                       # required 산출에 쓰인 전기간 ic_sd (일관성)
  ic_sd_used <- sd(c(v_on, v_off))               # 실제 사용 표본 sd (진단)
  se    <- ic_sd_full * sqrt(1/n_on + 1/n_off) * SE_INFL
  tstat <- dIC / se
  req   <- G$required[i]                          # 자격 단계 required 바
  req_used <- 2.0 * ic_sd_used * sqrt(1/n_on + 1/n_off) * SE_INFL

  lab <- if (!is.na(tstat) && abs(tstat) >= T_THRESH) "SIGNIFICANT"
         else if (!is.na(dIC) && abs(dIC) >= req)     "NULL_POWERED"
         else                                        "INCONCLUSIVE_UNDERPOWERED"

  res[[i]] <- data.table(
    group = GROUP, factor = f, signal = s,
    n_on_signal_months = length(on_sig), n_off_signal_months = length(off_sig),
    n_on = n_on, n_off = n_off,
    ic_on = m_on, ic_off = m_off, delta_ic = dIC,
    ic_sd_full = ic_sd_full, ic_sd_used = ic_sd_used,
    se = se, t = tstat,
    required = req, required_used = req_used,
    abs_dic_over_required = abs(dIC)/req,
    sd_on = if (n_on > 1) sd(v_on) else NA_real_,
    sd_off = if (n_off > 1) sd(v_off) else NA_real_,
    direction = ifelse(is.na(dIC), NA_character_, ifelse(dIC > 0, "ON_stronger", "ON_weaker")),
    label = lab, metric_type = "canonical_screen_diag")

  say("    %-22s %s | n_on %2d / n_off %3d | IC_on %+.5f  IC_off %+.5f  dIC %+.5f | se %.5f  t %+.3f | req %.5f | %s (%s)",
      f, s, n_on, n_off, m_on, m_off, dIC, se, tstat, req, lab,
      ifelse(dIC > 0, "ON 강화", "ON 약화"))
}
R <- if (length(res)) rbindlist(res) else data.table()

## =============================================================
## 7. 저장 + 요약
## =============================================================
outf <- file.path(OUT, "measured_value_growth.csv")
fwrite(R, outf)
say("=== 7. 저장: %s (%d행) ===", outf, nrow(R))

if (nrow(R)) {
  say("  라벨 분포: %s", paste(sprintf("%s=%d", names(table(R$label)), as.integer(table(R$label))), collapse = " · "))
  say("  방향: ON_stronger %d · ON_weaker %d", sum(R$direction=="ON_stronger"), sum(R$direction=="ON_weaker"))
  say("  |t| : median %.3f (min %.3f / max %.3f)", median(abs(R$t)), min(abs(R$t)), max(abs(R$t)))
  say("  --- SIGNIFICANT ---")
  SG <- R[label == "SIGNIFICANT"]
  if (!nrow(SG)) say("    (없음)")
  for (i in seq_len(nrow(SG)))
    say("    %-22s %s  dIC %+.5f  t %+.3f  (IC_on %+.5f vs IC_off %+.5f, n_on %d/n_off %d)",
        SG$factor[i], SG$signal[i], SG$delta_ic[i], SG$t[i], SG$ic_on[i], SG$ic_off[i], SG$n_on[i], SG$n_off[i])
  say("  ★주의: required = 2.0*ic_sd*sqrt(1/n+1/n)*1.25 = 2.0*se 이므로")
  say("     |dIC|>=required 는 |t|>=2.0 과 (표본수 드리프트 제외) 사실상 동일 조건 -> NULL_POWERED 가지는 거의 비발화")
  say("     검정력 진단은 required(%.5f~%.5f) 대비 자격단계 bar(2*|ic_mean|) 로 읽을 것",
      min(R$required), max(R$required))
}
say("=== 완료 ===")
