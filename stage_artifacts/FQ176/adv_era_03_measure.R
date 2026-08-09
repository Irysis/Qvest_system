## FQ176 적대검증 — 렌즈 era_split · STEP 3 (정정판): 정렬 2종 x scope 3종 전수 재측정
## 목적 = 반증. metric_type = canonical_screen_diag. 자본 주장 없음.
##
## ★정렬 규약 실측 확인 (원 스크립트 grep):
##   flow_consensus  : primary = same-row  (신호월 t 의 IC[t])
##   value_growth / risk_vol / quality_accrual / momentum_liq : primary = lead1 (IC[t+1])
##   -> 은폐 없이 두 정렬 모두 산출하고, 각 산출물의 *자기* primary 로 판정한다.
## ★시대 귀속 = **신호월 t** 기준 (정렬을 전체 타임라인에서 만든 뒤 분할 —
##   시대 내부에서 정렬을 재구성하면 경계월이 유실되어 분할 자체가 표본을 바꾼다)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ176")
say  <- function(fmt, ...) { cat(sprintf(paste0("[era3] ", fmt, "\n"), ...)); flush.console() }
SE_INFL <- 1.25; T_CRIT <- 2.0
CUT <- as.Date("2012-12-31")

IC  <- as.data.table(readRDS(file.path(OUT, "ic_series.rds"))); IC[, Date := as.Date(Date)]
SIG <- fread(file.path(OUT, "signals.csv")); SIG[, Date := as.Date(Date)]
ELI <- as.data.table(readRDS(file.path(OUT, "eligible.rds")))
mo  <- sort(unique(SIG$Date))
MIDX <- data.table(sig_date = mo, k = seq_along(mo))
SG <- merge(SIG, MIDX, by.x="Date", by.y="sig_date")[order(k)]
setnames(SG, "Date", "sig_date")
SG[, era := fifelse(sig_date <= CUT, "E1", "E2")]

## 각 산출물의 primary 정렬 (실측 확인분)
PRIM <- data.table(
  factor = c("C02_EPS_Chg_1m","C03_EPS_Chg_3m","CR04_Ownership_Concentration",
             "GR02_Earnings_Growth","GR04_GPA_Growth","V02_EP","V03_CFP","V04_fPER",
             "R01_VaR_95","R02_VaR_99","R03_CVaR_95","R04_CVaR_99","D01_IdioVol","D03_RealVol",
             "Q02_ROE","Q03_ROA","Q04_Piotroski_F","XF_LL02_NetDebt","L02_Turnover"),
  grp = c(rep("flow_consensus",3), rep("value_growth",5), rep("risk_vol",6),
          rep("quality_accrual",4), "momentum_liq"))
PRIM[, primary := fifelse(grp == "flow_consensus", "same", "lead1")]

## ------------------------------------------------------------------
meas <- function(dt, ic_sd_scope) {
  ## dt: sig_date, on, ic (이미 정렬·scope 필터됨)
  dt <- dt[order(sig_date)]
  on_ic <- dt[on == TRUE]$ic; off_ic <- dt[on == FALSE]$ic
  n_on <- length(on_ic); n_off <- length(off_ic)
  out <- list(n_on=n_on, n_off=n_off, ic_on=NA_real_, ic_off=NA_real_, delta=NA_real_,
              ic_sd=ic_sd_scope, se=NA_real_, t=NA_real_, required=NA_real_, t_welch=NA_real_,
              n_blk_on=NA_integer_, n_blk_off=NA_integer_, t_clu=NA_real_, req_clu=NA_real_,
              verdict="DEGENERATE_SPLIT")
  if (n_on < 2L || n_off < 2L) {
    if (n_on >= 1L) out$ic_on <- mean(on_ic); if (n_off >= 1L) out$ic_off <- mean(off_ic)
    return(out)
  }
  d  <- mean(on_ic) - mean(off_ic)
  se <- ic_sd_scope * sqrt(1/n_on + 1/n_off) * SE_INFL
  rl <- rle(dt$on); dt[, blk := rep(seq_along(rl$lengths), rl$lengths)]
  BL <- dt[, .(on = on[1], m = mean(ic)), by = blk]
  bo <- BL[on==TRUE]$m; bf <- BL[on==FALSE]$m
  se_c <- if (length(bo)>=2 && length(bf)>=2) sqrt(var(bo)/length(bo)+var(bf)/length(bf)) else NA_real_
  out$ic_on<-mean(on_ic); out$ic_off<-mean(off_ic); out$delta<-d; out$se<-se; out$t<-d/se
  out$required <- T_CRIT*se; out$t_welch <- d/sqrt(var(on_ic)/n_on+var(off_ic)/n_off)
  out$n_blk_on<-length(bo); out$n_blk_off<-length(bf)
  out$t_clu <- d/se_c; out$req_clu <- T_CRIT*se_c
  out$verdict <- if (abs(out$t) >= T_CRIT) "SIGNIFICANT"
                 else if (abs(d) >= out$required) "NULL_POWERED" else "INCONCLUSIVE_UNDERPOWERED"
  out
}

say("=== 1. 정렬 2종 x scope 3종 전수 측정 ===")
rows <- list()
for (i in seq_len(nrow(ELI))) {
  f <- ELI$factor[i]; s <- ELI$signal[i]
  ics <- IC[factor == f][order(Date)]
  ICI <- merge(ics[, .(ic_date = Date, ic)], data.table(ic_date = mo, ki = seq_along(mo)), by="ic_date")
  for (al in c("same","lead1")) {
    off <- if (al == "same") 0L else 1L
    A <- SG[, .(sig_date, k, on = get(s), era)]
    A[, ki := k + off]
    M <- merge(A, ICI, by = "ki")           # inner: IC 없는 월 자동 제외
    for (sc in c("FULL","E1","E2")) {
      MM <- if (sc == "FULL") copy(M) else copy(M[era == sc])
      sd_sc <- sd(MM$ic)
      m <- meas(MM[, .(sig_date, on, ic)], sd_sc)
      rows[[length(rows)+1L]] <- data.table(
        factor=f, signal=s, alignment=al, scope=sc,
        n_on=m$n_on, n_off=m$n_off, ic_on=m$ic_on, ic_off=m$ic_off, delta_ic=m$delta,
        ic_sd_scope=m$ic_sd, se=m$se, t=m$t, required=m$required, t_welch=m$t_welch,
        n_blk_on=m$n_blk_on, n_blk_off=m$n_blk_off, t_clu=m$t_clu, req_clu=m$req_clu,
        verdict=m$verdict, metric_type="canonical_screen_diag")
    }
  }
}
R <- rbindlist(rows)
R <- merge(R, PRIM[, .(factor, grp, primary)], by="factor", all.x=TRUE)
R[, is_primary := alignment == primary]
fwrite(R, file.path(OUT, "adv_era_measured_all.csv"))
say("  측정 완료: %d행 (쌍 %d x 정렬 2 x scope 3)", nrow(R), nrow(ELI))

## ------------------------------------------------------------------
say("=== 2. 원 산출물 재현 대조 (각 산출물의 자기 primary 정렬로) ===")
orig <- rbindlist(list(
  fread(file.path(OUT,"measured_flow_consensus.csv"))[, .(factor, signal, delta_orig=h1_delta_ic, t_orig=h1_t)],
  fread(file.path(OUT,"measured_value_growth.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t)],
  fread(file.path(OUT,"measured_risk_vol.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)],
  fread(file.path(OUT,"measured_quality_accrual.csv"))[, .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)],
  fread(file.path(OUT,"measured_momentum_liq.csv"))[alignment=="lead1", .(factor, signal, delta_orig=delta_ic, t_orig=t_stat)]
), use.names=TRUE)
CM <- merge(R[scope=="FULL" & is_primary==TRUE, .(factor, signal, alignment, delta_repro=delta_ic, t_repro=t)],
            orig, by=c("factor","signal"))
CM[, dd := delta_repro - delta_orig]
for (i in seq_len(nrow(CM)))
  say("   %-30s %s [%s] repro %+.6f vs orig %+.6f  차이 %+.2e", CM$factor[i], CM$signal[i],
      CM$alignment[i], CM$delta_repro[i], CM$delta_orig[i], CM$dd[i])
say("  최대 |차이| = %.3e  -> %s", max(abs(CM$dd)),
    ifelse(max(abs(CM$dd)) < 1e-9, "전표본 완전재현 (내 파이프라인 검증됨)", "★불일치 잔존"))

## ------------------------------------------------------------------
say("=== 3. ★시대 재현성 (각 쌍의 primary 정렬) ===")
P <- R[is_primary == TRUE]
WD <- dcast(P, factor + signal + grp + alignment ~ scope,
            value.var = c("delta_ic","t","required","n_on","n_off","verdict","t_clu","n_blk_on"))
WD[, sign_match := sign(delta_ic_E1) == sign(delta_ic_E2)]
WD[, t_interaction := (delta_ic_E1 - delta_ic_E2)/sqrt((required_E1/2)^2 + (required_E2/2)^2)]
WD <- WD[order(-abs(t_FULL))]
say("  팩터 | FULL dIC(t) | E1 dIC(t,n_on) | E2 dIC(t,n_on) | 부호 | 상호작용t")
for (i in seq_len(nrow(WD)))
  say("   %-29s %s | F %+.5f (t%+.2f) | E1 %+.5f (t%+.2f n%2d) | E2 %+.5f (t%+.2f n%2d) | %s | %+.2f",
      WD$factor[i], WD$signal[i], WD$delta_ic_FULL[i], WD$t_FULL[i],
      WD$delta_ic_E1[i], WD$t_E1[i], WD$n_on_E1[i],
      WD$delta_ic_E2[i], WD$t_E2[i], WD$n_on_E2[i],
      ifelse(is.na(WD$sign_match[i]),"NA",ifelse(WD$sign_match[i],"일치","★반전")),
      WD$t_interaction[i])
fwrite(WD, file.path(OUT, "adv_era_reproduction.csv"))

say("=== 4. 판정 집계 ===")
for (sc in c("FULL","E1","E2")) {
  X <- P[scope==sc]
  say("  %s: SIGNIFICANT %d · NULL_POWERED %d · UNDERPOWERED %d · DEGEN %d (총 %d)",
      sc, sum(X$verdict=="SIGNIFICANT"), sum(X$verdict=="NULL_POWERED"),
      sum(X$verdict=="INCONCLUSIVE_UNDERPOWERED"), sum(X$verdict=="DEGENERATE_SPLIT"), nrow(X))
}
say("  부호 일치 %d / %d (우연기대 %.1f)", sum(WD$sign_match, na.rm=TRUE),
    sum(!is.na(WD$sign_match)), 0.5*sum(!is.na(WD$sign_match)))
say("  |상호작용 t| >= 2 : %d / %d", sum(abs(WD$t_interaction)>=2, na.rm=TRUE), sum(!is.na(WD$t_interaction)))
bt <- binom.test(sum(WD$sign_match, na.rm=TRUE), sum(!is.na(WD$sign_match)), 0.5)
say("  부호일치 이항검정 p = %.4f (귀무: 시대간 방향 무관 50%%)", bt$p.value)

say("=== 5. ★검정력 바 (분할 비용 실측) ===")
PB <- P[, .(mde_med = median(required, na.rm=TRUE),
            mde_clu_med = median(req_clu, na.rm=TRUE),
            obs_absd_med = median(abs(delta_ic), na.rm=TRUE)), by=scope]
print(PB)
mf <- PB[scope=="FULL"]$mde_med
for (sc in c("E1","E2"))
  say("  %s MDE(t=2) %.5f = FULL(%.5f) 대비 %.2f배 · 관측 |dIC| 중앙값 %.5f (MDE의 %.0f%%)",
      sc, PB[scope==sc]$mde_med, mf, PB[scope==sc]$mde_med/mf,
      PB[scope==sc]$obs_absd_med, 100*PB[scope==sc]$obs_absd_med/PB[scope==sc]$mde_med)
say("  군집(에피소드) 기준 MDE 중앙값: FULL %.5f · E1 %.5f · E2 %.5f",
    PB[scope=="FULL"]$mde_clu_med, PB[scope=="E1"]$mde_clu_med, PB[scope=="E2"]$mde_clu_med)
say("  ★S3 ON 에피소드: FULL 4개 -> E1 2개 / E2 2개 (군집 se 는 표본2로 사실상 정의불가)")
say("=== STEP3 완료 ===")
