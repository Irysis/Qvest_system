## FQ176 적대검증 — 렌즈 era_split · STEP 2: 21개 자격쌍 시대별 재측정
## 목적 = 확인이 아니라 반증. metric_type = canonical_screen_diag. 자본 주장 없음.
##
## 원 설계 재현 (fq176_meas_* 공통 규약):
##   IC[t] = spearman(z_t, Ret_1m[t]) , Ret_1m = forward t->t+1  (PIT clean)
##   신호 S[t] = 월말 t 관측가능 (ret_realized = BM_Ret[t-1] 기반)
##   H1(primary, same-row) : ON 월 t 의 IC[t]  vs  OFF 월의 IC
##   se = ic_sd * sqrt(1/n_on + 1/n_off) * 1.25 ; required = 2.0 * se
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[era2] ", fmt, "\n"), ...)); flush.console() }
SE_INFL <- 1.25; T_CRIT <- 2.0

IC  <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
CUT <- as.Date("2012-12-31")
era_of <- function(d) fifelse(d <= CUT, "E1_2003_2012", "E2_2013_2026")
IC[, era := era_of(Date)]; SIG[, era := era_of(Date)]

say("=== 0. 재현 대조 (전표본 H1 을 내가 직접 재계산) ===")

## 공통 측정 함수 --------------------------------------------------
meas <- function(ics, sig_dt, scol, lab) {
  ## ics: factor 별 IC (Date, ic) ; sig_dt: Date, scol
  M <- merge(ics[, .(Date, ic)], sig_dt[, .(Date, on = get(scol))], by = "Date")
  M <- M[order(Date)]
  on_ic <- M[on == TRUE]$ic; off_ic <- M[on == FALSE]$ic
  n_on <- length(on_ic); n_off <- length(off_ic)
  if (n_on < 2L || n_off < 2L)
    return(list(scope=lab, n_on=n_on, n_off=n_off, ic_on=if(n_on)mean(on_ic) else NA_real_,
                ic_off=if(n_off)mean(off_ic) else NA_real_, delta=NA_real_, ic_sd=sd(M$ic),
                se=NA_real_, t=NA_real_, required=NA_real_, t_welch=NA_real_,
                n_blk_on=NA_integer_, n_blk_off=NA_integer_, se_clu=NA_real_, t_clu=NA_real_,
                verdict="DEGENERATE_SPLIT"))
  ic_sd <- sd(M$ic)                      # 해당 scope 의 IC 변동성 (게이트 재료)
  d  <- mean(on_ic) - mean(off_ic)
  se <- ic_sd * sqrt(1/n_on + 1/n_off) * SE_INFL
  se_w <- sqrt(var(on_ic)/n_on + var(off_ic)/n_off)
  ## 군집(연속 에피소드) 강건 진단
  rl <- rle(M$on); M[, blk := rep(seq_along(rl$lengths), rl$lengths)]
  BL <- M[, .(on = on[1], m = mean(ic)), by = blk]
  bo <- BL[on == TRUE]$m; bf <- BL[on == FALSE]$m
  se_c <- if (length(bo) >= 2 && length(bf) >= 2) sqrt(var(bo)/length(bo) + var(bf)/length(bf)) else NA_real_
  req <- T_CRIT * se
  vd  <- if (!is.na(d/se) && abs(d/se) >= T_CRIT) "SIGNIFICANT"
         else if (abs(d) >= req) "NULL_POWERED" else "INCONCLUSIVE_UNDERPOWERED"
  list(scope=lab, n_on=n_on, n_off=n_off, ic_on=mean(on_ic), ic_off=mean(off_ic),
       delta=d, ic_sd=ic_sd, se=se, t=d/se, required=req, t_welch=d/se_w,
       n_blk_on=length(bo), n_blk_off=length(bf), se_clu=se_c, t_clu=d/se_c, verdict=vd)
}

## --- 전표본 재현 대조 ---
rep_rows <- list()
for (i in seq_len(nrow(ELI))) {
  f <- ELI$factor[i]; s <- ELI$signal[i]
  m <- meas(IC[factor == f], SIG, s, "FULL")
  rep_rows[[i]] <- data.table(factor=f, signal=s, delta_repro=m$delta, t_repro=m$t,
                              n_on=m$n_on, n_off=m$n_off, verdict=m$verdict)
}
REP <- rbindlist(rep_rows)
## 원 산출물과 대조
orig <- rbindlist(list(
  fread(file.path(OUT,"measured_flow_consensus.csv"))[, .(factor, signal, delta_orig=h1_delta_ic, t_orig=h1_t)],
  fread(file.path(OUT,"measured_value_growth.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t)],
  fread(file.path(OUT,"measured_risk_vol.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)],
  fread(file.path(OUT,"measured_quality_accrual.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)],
  fread(file.path(OUT,"measured_momentum_liq.csv"))[alignment=="contemp", .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)]
), use.names=TRUE)
CMP <- merge(REP, orig, by=c("factor","signal"), all.x=TRUE)
CMP[, d_diff := delta_repro - delta_orig]
say("  재현 대조 (내 재계산 vs 원 산출물) — 원 결과 인용이 아니라 재측정임을 실증:")
for (i in seq_len(nrow(CMP)))
  say("    %-30s %s | repro dIC %+.6f (t %+.3f) | orig %+.6f | 차이 %+.2e",
      CMP$factor[i], CMP$signal[i], CMP$delta_repro[i], CMP$t_repro[i],
      CMP$delta_orig[i], CMP$d_diff[i])
say("  최대 절대차이 %.3e (0 이면 완전재현) · 원 산출물 대응 없는 쌍 %d",
    max(abs(CMP$d_diff), na.rm=TRUE), sum(is.na(CMP$delta_orig)))
say("  전표본 재현 판정 분포: %s",
    paste(sprintf("%s=%d", names(table(REP$verdict)), as.integer(table(REP$verdict))), collapse=" · "))

## --- 시대별 측정 ---
say("=== 1. 시대별 재측정 (E1 2003-2012 / E2 2013-2026) ===")
rows <- list()
for (i in seq_len(nrow(ELI))) {
  f <- ELI$factor[i]; s <- ELI$signal[i]
  ic_f <- IC[factor == f]
  for (sc in c("FULL","E1_2003_2012","E2_2013_2026")) {
    if (sc == "FULL") { icx <- ic_f; sgx <- SIG }
    else { icx <- ic_f[era == sc]; sgx <- SIG[era == sc] }
    m <- meas(icx, sgx, s, sc)
    rows[[length(rows)+1L]] <- data.table(factor=f, signal=s, scope=sc,
      n_on=m$n_on, n_off=m$n_off, ic_on=m$ic_on, ic_off=m$ic_off, delta_ic=m$delta,
      ic_sd=m$ic_sd, se=m$se, t=m$t, required=m$required, t_welch=m$t_welch,
      n_blk_on=m$n_blk_on, n_blk_off=m$n_blk_off, se_clu=m$se_clu, t_clu=m$t_clu,
      verdict=m$verdict, metric_type="canonical_screen_diag")
  }
}
R <- rbindlist(rows)
fwrite(R, file.path(OUT, "adv_era_measured_by_era.csv"))

## --- 시대 일치성 / 검정력 바 ---
say("=== 2. 시대 재현성 판정 ===")
WD <- dcast(R, factor + signal ~ scope, value.var = c("delta_ic","t","required","n_on","n_off","verdict","t_clu"))
setnames(WD, gsub("_2003_2012|_2013_2026", "", names(WD)))
WD[, sign_match := fifelse(is.na(delta_ic_E1) | is.na(delta_ic_E2), NA,
                           sign(delta_ic_E1) == sign(delta_ic_E2))]
## 시대 상호작용 t: (dIC_E1 - dIC_E2) / sqrt(se_E1^2 + se_E2^2)
se1 <- R[scope=="E1_2003_2012", .(factor, signal, se1=se)]
se2 <- R[scope=="E2_2013_2026", .(factor, signal, se2=se)]
WD <- merge(merge(WD, se1, by=c("factor","signal")), se2, by=c("factor","signal"))
WD[, t_interaction := (delta_ic_E1 - delta_ic_E2)/sqrt(se1^2 + se2^2)]
setorder(WD, -abs(t_FULL))
say("  팩터 | 전표본 dIC(t) | E1 dIC(t, n_on) | E2 dIC(t, n_on) | 부호일치 | 상호작용 t")
for (i in seq_len(nrow(WD)))
  say("   %-30s %s | FULL %+.5f (t%+.2f) | E1 %+.5f (t%+.2f, n%s) | E2 %+.5f (t%+.2f, n%s) | %s | int_t %+.2f",
      WD$factor[i], WD$signal[i], WD$delta_ic_FULL[i], WD$t_FULL[i],
      WD$delta_ic_E1[i], WD$t_E1[i], as.character(WD$n_on_E1[i]),
      WD$delta_ic_E2[i], WD$t_E2[i], as.character(WD$n_on_E2[i]),
      ifelse(is.na(WD$sign_match[i]),"NA", ifelse(WD$sign_match[i],"일치","★반전")),
      WD$t_interaction[i])
fwrite(WD, file.path(OUT, "adv_era_reproduction.csv"))

say("=== 3. 검정력 바 (분할이 파괴한 검정력 실측) ===")
PB <- R[, .(mde_med = median(required, na.rm=TRUE)), by = scope]
say("  scope 별 필요 |dIC| (t=2 기준) 중앙값:")
print(PB)
mf <- PB[scope=="FULL"]$mde_med
for (sc in c("E1_2003_2012","E2_2013_2026"))
  say("  %s: MDE %.5f = FULL 대비 %.2f배", sc, PB[scope==sc]$mde_med, PB[scope==sc]$mde_med/mf)
say("  --- 관측 |dIC| 가 각 scope MDE 를 넘는 쌍 수 ---")
for (sc in unique(R$scope)) {
  X <- R[scope==sc & !is.na(delta_ic)]
  say("   %s: %d/%d (SIGNIFICANT %d · NULL_POWERED %d · UNDERPOWERED %d · DEGEN %d)",
      sc, sum(abs(X$delta_ic) >= X$required), nrow(X),
      sum(R[scope==sc]$verdict=="SIGNIFICANT"), sum(R[scope==sc]$verdict=="NULL_POWERED"),
      sum(R[scope==sc]$verdict=="INCONCLUSIVE_UNDERPOWERED"), sum(R[scope==sc]$verdict=="DEGENERATE_SPLIT"))
}
say("  부호 일치 %d / 판정가능 %d (기대 우연일치 50%%)",
    sum(WD$sign_match, na.rm=TRUE), sum(!is.na(WD$sign_match)))
say("  상호작용 |t| >= 2 인 쌍: %d / %d", sum(abs(WD$t_interaction)>=2, na.rm=TRUE), sum(!is.na(WD$t_interaction)))
say("=== STEP2 완료 → adv_era_measured_by_era.csv · adv_era_reproduction.csv ===")
