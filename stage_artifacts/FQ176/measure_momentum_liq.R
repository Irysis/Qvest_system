## FQ176 — 조건부 IC 측정 · 그룹 momentum_liq (M*/L*)
## metric_type = canonical_screen_diag. 자본 주장 없음.
## 입력: panel_full.rds (신호월말 Date x Ticker, Ret_1m = forward 1M)
##       eligible.rds  (자격 통과 (팩터,신호) 쌍 + required 바)
##       signals.csv   (하락신호 3종 — 게이트 단계 산출물, 동일 정의 재사용)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[mliq] ", fmt, "\n"), ...)); flush.console() }

GROUP    <- "momentum_liq"
GRP_RE   <- "^(M|L)[0-9]{2}_"      # M01~M04 (모멘텀) · L01~L04 (유동성)
MIN_XS   <- 30L                     # 게이트 단계와 동일 선언
SE_INFL  <- 1.25                    # 지시 규약 (자기상관 팽창계수)
T_CRIT   <- 2.0

## =============================================================
## 1. ★입력 실측 (가정 금지 — 행수·개월수·관측단위·범위)
## =============================================================
say("=== 1. ★입력 실측 ===")
PN <- as.data.table(readRDS(file.path(OUT, "panel_full.rds")))
PN[, Date := as.Date(Date)]
mo <- sort(unique(PN$Date))
pm <- PN[, .N, by = Date][order(Date)]
say("  panel_full.rds")
say("    행수       : %d", nrow(PN))
say("    개월수     : %d", length(mo))
say("    범위       : %s ~ %s", format(min(mo)), format(max(mo)))
say("    관측단위   : 1행 = 1(신호월말 Date, Ticker) — 종목월")
say("    고유 Ticker: %d · 월별 종목수 median %.1f (min %d / max %d)",
    uniqueN(PN$Ticker), median(pm$N), min(pm$N), max(pm$N))
say("    Ret_1m     : mean %+.5f · sd %.5f · min %+.4f · max %+.4f · NA %d",
    mean(PN$Ret_1m), sd(PN$Ret_1m), min(PN$Ret_1m), max(PN$Ret_1m), sum(is.na(PN$Ret_1m)))
## 월 간격 실측 (관측단위가 월간인지 직접 확인 — 가정 금지)
gaps <- as.numeric(diff(mo))
say("    월간격(일) : median %.0f · min %d · max %d  => 관측단위 확인 = %s",
    median(gaps), min(gaps), max(gaps),
    ifelse(median(gaps) >= 28 && median(gaps) <= 31, "MONTHLY", "★NOT MONTHLY"))
gap_big <- sum(gaps > 40)
say("    비연속 월경계(>40일 간격) %d건 %s", gap_big,
    ifelse(gap_big == 0, "(연속)", "★결측월 존재 — lead 정의 시 실제 다음행 사용"))

ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
say("  eligible.rds : %d쌍 · 고유팩터 %d · 신호 %s",
    nrow(ELI), uniqueN(ELI$factor), paste(sort(unique(ELI$signal)), collapse=","))

SIG <- fread(file.path(OUT, "signals.csv"))
SIG[, Date := as.Date(Date)]
setorder(SIG, Date)
for (s in c("S1","S2","S3")) set(SIG, j = s, value = as.logical(SIG[[s]]))
say("  signals.csv  : %d행 · %s ~ %s · S1 ON %d · S2 ON %d · S3 ON %d",
    nrow(SIG), format(min(SIG$Date)), format(max(SIG$Date)),
    sum(SIG$S1), sum(SIG$S2), sum(SIG$S3))
stopifnot(identical(SIG$Date, mo))
say("  ★SIG$Date == panel 월 시퀀스 동일 (%d개월) — 정렬 기준축 확정", length(mo))

## =============================================================
## 2. 그룹 선별 (M*/L*) — 자격 통과 쌍만
## =============================================================
say("=== 2. 그룹 %s 선별 (정규식 %s) ===", GROUP, GRP_RE)
FN_ALL <- setdiff(names(PN), c("Date","Ticker","Ret_1m","adv"))
grp_factors <- sort(FN_ALL[grepl(GRP_RE, FN_ALL)])
say("  패널 내 그룹 팩터 %d개: %s", length(grp_factors), paste(grp_factors, collapse=", "))
TGT <- ELI[grepl(GRP_RE, factor)]
setorder(TGT, factor, signal)
say("  자격통과 ∩ 그룹 = %d쌍", nrow(TGT))
if (nrow(TGT)) for (i in seq_len(nrow(TGT)))
  say("    %-16s %s  required %.6f · ic_mean %+.6f · ic_sd %.6f · n_ON %d / n_OFF %d",
      TGT$factor[i], TGT$signal[i], TGT$required[i], TGT$ic_mean[i], TGT$ic_sd[i],
      TGT$n_ON[i], TGT$n_OFF[i])
## 탈락 그룹 쌍 전건 명시 (침묵 스킵 없음)
PA <- fread(file.path(OUT, "pairs_all.csv"))
EXG <- PA[grepl(GRP_RE, factor) & eligible == FALSE][order(ratio)]
say("  --- 그룹 내 자격 미달 쌍 %d건 (전건 명시) ---", nrow(EXG))
for (i in seq_len(nrow(EXG)))
  say("    %-16s %s  ratio %.3f  %s", EXG$factor[i], EXG$signal[i], EXG$ratio[i], EXG$reason[i])

if (nrow(TGT) == 0L) {
  say("★ 그룹 %s 자격통과 쌍 0건 — 빈 결과 정직 반환 (0은 정지신호이지 합격 아님)", GROUP)
  fwrite(data.table(), file.path(OUT, "measured_momentum_liq.csv"))
  quit(save = "no", status = 0)
}

## =============================================================
## 3. 월별 rank-IC 재산출 (panel_full 로부터) + 기존 ic_series 대조
## =============================================================
say("=== 3. 월별 rank-IC 재산출 (spearman, z(t) x Ret_1m(t)=forward, 최소 횡단면 %d) ===", MIN_XS)
ic_list <- list()
for (f in sort(unique(TGT$factor))) {
  D <- PN[!is.na(get(f)) & !is.na(Ret_1m), .(Date, z = get(f), r = Ret_1m)]
  ICm <- D[, .(n_xs = .N, ic = if (.N >= MIN_XS)
                 suppressWarnings(cor(z, r, method = "spearman")) else NA_real_), by = Date]
  ICm <- ICm[!is.na(ic)][order(Date)]
  ic_list[[f]] <- data.table(factor = f, Date = ICm$Date, ic = ICm$ic, n_xs = ICm$n_xs)
  say("  %-16s n_mo %3d · ic_mean %+.6f · ic_sd %.6f · %s ~ %s",
      f, nrow(ICm), mean(ICm$ic), sd(ICm$ic), format(min(ICm$Date)), format(max(ICm$Date)))
}
ICG <- rbindlist(ic_list)
## 게이트 산출물과 대조 (동일성 확인)
ICref <- as.data.table(readRDS(file.path(OUT, "ic_series.rds")))
ICref[, Date := as.Date(Date)]
CMP <- merge(ICG[, .(factor, Date, ic_new = ic)],
             ICref[, .(factor, Date, ic_ref = ic)], by = c("factor","Date"), all = TRUE)
say("  ic_series.rds 대조: 공통 %d · 신규만 %d · 기존만 %d · max|diff| %.3g",
    sum(!is.na(CMP$ic_new) & !is.na(CMP$ic_ref)), sum(is.na(CMP$ic_ref)), sum(is.na(CMP$ic_new)),
    max(abs(CMP$ic_new - CMP$ic_ref), na.rm = TRUE))

## =============================================================
## 4. ★PIT 정렬 — 신호 t -> IC 행 t+1 (lead 1)
## =============================================================
say("=== 4. ★PIT 정렬 검증 ===")
say("  규약: 신호 S(t) = 월말 t 관측가능 (ret_realized[t]=BM_Ret[t-1] 기반)")
say("        IC(d)     = corr( z(d), Ret_1m(d) ), Ret_1m(d)=forward d->d+1")
say("        지시 정렬 = 신호 ON 인 t 의 **다음 행 t+1** 의 IC  => IC(t+1)=corr(z(t+1), ret(t+1->t+2))")
say("        (참고) 동시 정렬 t+0 = corr(z(t), ret(t->t+1)) 도 민감도로 병기 — 자격 바는 t+0 분할로 산출됨")
IDX <- data.table(Date = mo, i = seq_along(mo))
SIGX <- merge(SIG[, .(Date, S1, S2, S3)], IDX, by = "Date")
setorder(SIGX, i)
## lead map: i -> i+1 (실제 다음 행. 결측월 없음은 위 gap 실측으로 확인)
lead_map <- data.table(i = IDX$i, i_lead = IDX$i + 1L)
lead_map <- merge(lead_map, IDX[, .(i_lead = i, Date_lead = Date)], by = "i_lead", all.x = TRUE)
setorder(lead_map, i)
LM <- merge(IDX, lead_map[, .(i, Date_lead)], by = "i")
## 검증 출력: 처음/마지막 3건
vv <- merge(SIGX, LM[, .(Date, Date_lead)], by = "Date")[order(i)]
say("  정렬 샘플 (신호월 -> IC측정월):")
for (k in c(1,2,3, nrow(vv)-2, nrow(vv)-1, nrow(vv)))
  say("    t=%s (S3=%s) -> IC월 %s", format(vv$Date[k]), vv$S3[k],
      ifelse(is.na(vv$Date_lead[k]), "NA(패널 끝 — 제외)", format(vv$Date_lead[k])))
say("  lead 결측(패널 마지막 월) %d건 — 측정에서 제외", sum(is.na(vv$Date_lead)))
## S3 ON 월 -> lead 월 실제 간격 실측
on3 <- vv[S3 == TRUE & !is.na(Date_lead)]
say("  S3 ON %d개월 중 lead 유효 %d · 간격(일) median %.0f / min %d / max %d",
    sum(vv$S3), nrow(on3), median(as.numeric(on3$Date_lead - on3$Date)),
    min(as.numeric(on3$Date_lead - on3$Date)), max(as.numeric(on3$Date_lead - on3$Date)))

## =============================================================
## 5. 조건부 IC 측정
## =============================================================
say("=== 5. 조건부 IC 측정 (primary = lead1, secondary = contemporaneous) ===")
res <- list()
for (r in seq_len(nrow(TGT))) {
  f <- TGT$factor[r]; s <- TGT$signal[r]
  icf <- ICG[factor == f][order(Date)]
  ic_by_date <- setNames(icf$ic, format(icf$Date))
  ic_sd_gate <- TGT$ic_sd[r]           # 게이트가 required 산출에 쓴 값
  ic_sd_obs  <- sd(icf$ic)
  req        <- TGT$required[r]

  for (align in c("lead1","contemp")) {
    aa <- copy(vv)
    aa[, IC_Date := if (align == "lead1") Date_lead else Date]
    aa <- aa[!is.na(IC_Date)]
    aa[, ic := ic_by_date[format(IC_Date)]]
    aa <- aa[!is.na(ic)]                       # 팩터 관측월만
    on_v  <- aa[get(s) == TRUE, ic]
    off_v <- aa[get(s) == FALSE, ic]
    n_on <- length(on_v); n_off <- length(off_v)
    if (n_on == 0L || n_off == 0L) {
      res[[length(res)+1L]] <- data.table(
        group = GROUP, factor = f, signal = s, alignment = align,
        n_on = n_on, n_off = n_off, ic_on = NA_real_, ic_off = NA_real_,
        delta_ic = NA_real_, se = NA_real_, t_stat = NA_real_,
        required = req, abs_delta_vs_required = NA_real_,
        verdict = "DEGENERATE_SPLIT", metric_type = "canonical_screen_diag")
      next
    }
    ic_on <- mean(on_v); ic_off <- mean(off_v)
    d <- ic_on - ic_off
    se <- ic_sd_gate * sqrt(1/n_on + 1/n_off) * SE_INFL
    tt <- d / se
    verdict <- if (abs(tt) >= T_CRIT) "SIGNIFICANT" else
               if (abs(d) >= req)     "NULL_POWERED" else "INCONCLUSIVE_UNDERPOWERED"
    res[[length(res)+1L]] <- data.table(
      group = GROUP, factor = f, signal = s, alignment = align,
      n_on = n_on, n_off = n_off,
      ic_on = ic_on, ic_off = ic_off, ic_on_sd = sd(on_v), ic_off_sd = sd(off_v),
      delta_ic = d, se = se, t_stat = tt,
      required = req, abs_delta_vs_required = abs(d)/req,
      ic_sd_gate = ic_sd_gate, ic_sd_obs = ic_sd_obs,
      ic_mean_full = mean(icf$ic), n_months_factor = nrow(icf),
      verdict = verdict, metric_type = "canonical_screen_diag")
    say("  %-16s %s [%-7s] n_ON %2d / n_OFF %3d · IC_on %+.6f · IC_off %+.6f · dIC %+.6f · se %.6f · t %+.3f · req %.6f -> %s",
        f, s, align, n_on, n_off, ic_on, ic_off, d, se, tt, req, verdict)
  }
}
R <- rbindlist(res, use.names = TRUE, fill = TRUE)
setorder(R, factor, signal, -alignment)
fwrite(R, file.path(OUT, "measured_momentum_liq.csv"))
say("=== 저장: %s (%d행) ===", file.path(OUT, "measured_momentum_liq.csv"), nrow(R))

## 요약 JSON (참고용 — 반환은 에이전트가 수행)
summ <- list(group = GROUP, metric_type = "canonical_screen_diag",
  n_pairs_measured = nrow(R[alignment == "lead1"]),
  primary_alignment = "lead1 (signal t -> IC row t+1)",
  rows = R)
write_json(summ, file.path(OUT, "measured_momentum_liq_summary.json"),
           auto_unbox = TRUE, digits = NA, pretty = TRUE)
say("=== 완료 ===")
