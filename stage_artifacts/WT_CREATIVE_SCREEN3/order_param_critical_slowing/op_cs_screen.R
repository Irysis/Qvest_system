#!/usr/bin/env Rscript
#==============================================================================
# op_cs_screen.R — Cheap SCREEN: Order-Parameter / Critical-Slowing regime EWS
#
# IDEA (idea bank 3차):
#   상전이(regime collapse) 직전 cross-sectional 동조화↑ + dispersion↓ +
#   critical slowing(rolling Var↑, AR(1)↑)이 동시 발생 (Scheffer 2009
#   "Early-warning signals for critical transitions"). RE_MRS(level, 후행)와
#   달리 *선행* 진단을 노린다.
#
#   ★주의: EIGEN-ENTRY(λ1-share / Absorption Ratio k=1)가 동일 RE_MRS-incremental
#   테스트에서 incremental t=1.74 실패 (SCREEN2/.cache/eigen_entry_findings.json).
#   본 건은 λ1-share와 *다른* 구성 (order-param sign-align + dispersion +
#   critical-slowing rolling Var/AR1)이며, incremental 회귀에서 RE_MRS *및*
#   λ1-share를 동시 통제해 그 둘을 초과하는 설명력이 있어야 GO.
#   합격선: incremental |t|>=2 (EIGEN 1.74 를 넘어야).
#
# CHEAP TEST (event-study + RE_MRS-incremental), EIGEN-ENTRY 설계와 정합:
#   설계 일치 (직접 비교 가능):
#     - universe: rawdata K200==1 | KQ150==1 (PIT index flag)
#     - label: forward 21d BM return fwd_H = BM[t+21]/BM[t]-1 (shift n=H type=lead)
#     - RE_MRS control: .cache/regime_daily_v2.parquet column MRS -> expanding z (mrs_z)
#     - lambda1-share control: rolling 60d corr eigen lambda1/sum (EIGEN construct 재현)
#     - regression: OLS fwd_H ~ mrs_z + lambda1_z + ews_combo (continuous, EIGEN과 동형)
#   본 건 신규 feature: order_param |m|, dispersion, cs_var, cs_ar1 결합 EWS_combo
#
# PIT:
#   - 모든 feature는 trailing window <= t (decision use 시 t-1 lag).
#   - forward label만 미래 (C2 same-day circular 회피 위해 회귀 시 feature는 t-1 lag).
#   - expanding z-score (과거값만, warmup 60) — C1 full-sample stat 회피.
#   - lockbox 2023-12-22 strict (정규 리서치 incremental 검정 = lockbox 적용).
#   - C14: mrs_z, lambda1 모두 end_date<=t window. KR universe (K200|KQ150).
#
# SCREEN only — read-only. 백테/admission/full-package 금지. advisory.
#==============================================================================

suppressPackageStartupMessages({
  library(arrow); library(data.table); library(jsonlite)
})

PR <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(PR)
set.seed(1)

OUT_DIR     <- "stage_artifacts/WT_CREATIVE_SCREEN3/order_param_critical_slowing"
LOCKBOX_CUT <- as.Date("2023-12-22")
H           <- 21L     # forward horizon
WIN_CS      <- 63L     # rolling window for critical slowing (Var, AR1) ~3 months
LOOKBACK    <- 60L     # corr window for lambda1-share (EIGEN-ENTRY parity)
MIN_STOCKS  <- 50L     # min names for cross-sectional / corr measures
MIN_DAYS_PCT<- 0.80

infeasible <- function(reason) {
  writeLines(toJSON(list(screen="order_param_critical_slowing",
              data_feasible=FALSE, reason=reason), auto_unbox=TRUE, pretty=TRUE),
             file.path(OUT_DIR, "screen_findings.json"))
  cat(sprintf("[op_cs] INFEASIBLE: %s\n", reason)); quit(save="no", status=0)
}

for (f in c(".cache/rawdata.parquet",".cache/benchmark.parquet",
            ".cache/regime_daily_v2.parquet"))
  if (!file.exists(file.path(PR,f))) infeasible(paste("missing", f))

# ── load returns, restrict to KOSPI200 ∪ KOSDAQ150 PIT universe ─────
cat("[load] rawdata (universe-filtered)...\n")
raw <- as.data.table(read_parquet(file.path(PR,".cache/rawdata.parquet"),
        col_select=c("Date","Ticker","Ret","K200","KQ150")))
raw[, Date := as.Date(Date)]
raw <- raw[!is.na(Ret) & !is.na(Ticker) & (K200==1 | KQ150==1)]
setorder(raw, Date)
trading_dates <- sort(unique(raw$Date))
cat(sprintf("[load] %d rows, %d trading days\n", nrow(raw), length(trading_dates)))
td_idx <- data.table(Date=trading_dates, idx=seq_along(trading_dates)); setkey(td_idx, Date)

# ── benchmark forward label (CORRECT convention: shift n=H type=lead) ─
bm <- as.data.table(read_parquet(file.path(PR,".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- unique(bm, by="Date")
bm[, bm_ret := BM_Close/shift(BM_Close,1L,type="lag") - 1]
bm[, fwd_H  := shift(BM_Close, n=H, type="lead")/BM_Close - 1]   # forward (label)
bm[, bear   := as.integer(fwd_H <= -0.05)]

# ── order parameter |m| + dispersion (cross-section per date) ────────
cs <- raw[, .(n_xs        = .N,
              order_param = abs(mean(sign(Ret), na.rm=TRUE)),  # |m| sync
              dispersion  = sd(Ret, na.rm=TRUE)), by=Date]
cs <- cs[n_xs >= MIN_STOCKS]; setorder(cs, Date)
cat(sprintf("[cs] order_param/dispersion on %d dates (n_xs>=%d)\n", nrow(cs), MIN_STOCKS))

# ── critical slowing: rolling Var + rolling AR(1) of market (BM) return ─
mser <- merge(bm[, .(Date, bm_ret)], cs[, .(Date)], by="Date"); setorder(mser, Date)
mser[, cs_var := frollapply(bm_ret, WIN_CS, function(x) var(x, na.rm=TRUE), align="right")]
mser[, cs_ar1 := frollapply(bm_ret, WIN_CS, function(x){
  x <- x[is.finite(x)]; if (length(x) < 30) return(NA_real_)
  tryCatch(cor(x[-length(x)], x[-1]), error=function(e) NA_real_)
}, align="right")]

# ── lambda1-share control (EIGEN-ENTRY construct, parity) ───────────
# coarse 5-trading-day grid from 2007 + dense daily around 4 bear dates, ffill.
BEAR0 <- as.Date(c("2008-09-15","2011-08-08","2020-02-19","2022-09-26"))
base_grid <- trading_dates[trading_dates >= as.Date("2007-01-01")]
coarse <- base_grid[seq(1L, length(base_grid), by=5L)]
dense  <- base_grid[ Reduce(`|`, lapply(BEAR0, function(b) base_grid>=(b-120) & base_grid<=(b+40))) ]
calc_dates <- sort(unique(c(coarse, dense)))
cat(sprintf("[lam] lambda1-share on %d days (coarse-5d + dense around bears)\n", length(calc_dates)))

compute_l1 <- function(end_date) {
  avail <- td_idx[Date <= end_date]; if (!nrow(avail)) return(NA_real_)
  ei <- avail[.N, idx]; if (ei < LOOKBACK) return(NA_real_)
  wdates <- trading_dates[(ei-LOOKBACK+1L):ei]
  wd <- raw[Date %in% wdates]; if (!nrow(wd)) return(NA_real_)
  mind <- floor(length(wdates)*MIN_DAYS_PCT)
  valid <- wd[, .N, by=Ticker][N>=mind, Ticker]
  if (length(valid) < MIN_STOCKS) return(NA_real_)
  rw <- dcast(wd[Ticker %in% valid], Date ~ Ticker, value.var="Ret")
  m <- as.matrix(rw[,-1]); cv <- apply(m,2,var,na.rm=TRUE)
  keep <- !is.na(cv) & cv>1e-10; if (sum(keep) < MIN_STOCKS) return(NA_real_)
  m <- m[,keep]; m[is.na(m)] <- 0
  cm <- tryCatch(cor(m, use="pairwise.complete.obs"), error=function(e) NULL)
  if (is.null(cm)) return(NA_real_)
  cm[is.na(cm)] <- 0; diag(cm) <- 1
  eg <- tryCatch(eigen(cm, symmetric=TRUE, only.values=TRUE), error=function(e) NULL)
  if (is.null(eg)) return(NA_real_)
  lam <- pmax(0, eg$values); tot <- sum(lam); if (tot < 1e-10) return(NA_real_)
  max(lam)/tot
}
l1v <- vapply(calc_dates, compute_l1, numeric(1))
lam <- data.table(Date=calc_dates, lambda1_share=l1v)[!is.na(lambda1_share)]
cat(sprintf("[lam] %d valid days. lambda1-share mean=%.3f sd=%.3f\n",
            nrow(lam), mean(lam$lambda1_share), sd(lam$lambda1_share)))

# ── RE_MRS control (regime_daily_v2 MRS) -> expanding z ──────────────
ur <- as.data.table(read_parquet(file.path(PR,".cache/regime_daily_v2.parquet")))
ur[, Date := as.Date(Date)]; ur <- ur[!is.na(MRS), .(Date, mrs=MRS)]; setorder(ur, Date)
exp_z <- function(v){ out<-rep(NA_real_,length(v))
  for(i in seq_along(v)){ p<-v[1:i]; if(i>=60){ s<-sd(p,na.rm=TRUE)
    if(!is.na(s)&&s>1e-8) out[i]<-(v[i]-mean(p,na.rm=TRUE))/s }}; out }
ur[, mrs_z := exp_z(mrs)]

# ── assemble feature panel (one row per cs date) ────────────────────
feat <- merge(cs[, .(Date, order_param, dispersion)],
              mser[, .(Date, cs_var, cs_ar1)], by="Date")
feat[, z_op   := exp_z(order_param)]
feat[, z_disp := exp_z(dispersion)]
feat[, z_var  := exp_z(cs_var)]
feat[, z_ar1  := exp_z(cs_ar1)]
# EWS_combo: synchronization↑ + critical-slowing(Var,AR1)↑ - dispersion↓
feat[, ews_combo := z_op + z_var + z_ar1 - z_disp]
setorder(feat, Date)
saveRDS(feat, file.path(OUT_DIR, "feature_panel.rds"))

# ── merge controls + label; roll lambda1 forward (<= t, PIT) ────────
M <- merge(feat, bm[, .(Date, fwd_H, bear)], by="Date")
M <- merge(M, ur[, .(Date, mrs_z)], by="Date", all.x=TRUE)
setkey(M, Date); setkey(lam, Date)
M <- lam[M, roll=TRUE]                       # lambda1 as of <= Date
M[, lambda1_z := exp_z(lambda1_share)]
setorder(M, Date)

# ── event-study: EWS_combo around 4 bear dates (lead = near>pre) ─────
ev_window <- -25:5
ev_tab <- list(); leads <- list()
for (bd in BEAR0) {
  idx <- which.min(abs(M$Date - bd))
  pre  <- (idx-25):(idx-6); near <- (idx-5):(idx-1)
  pre  <- pre[pre>=1 & pre<=nrow(M)]; near <- near[near>=1 & near<=nrow(M)]
  pre_lv  <- mean(M$ews_combo[pre],  na.rm=TRUE)
  near_lv <- mean(M$ews_combo[near], na.rm=TRUE)
  leads[[as.character(bd)]] <- list(pre=round(pre_lv,3), near=round(near_lv,3),
                                    leads=isTRUE(near_lv>pre_lv))
  for (off in ev_window){ j<-idx+off
    if (j>=1 && j<=nrow(M)) ev_tab[[length(ev_tab)+1]] <-
      data.table(bear_date=bd, offset=off, ews_combo=M$ews_combo[j],
                 mrs_z=M$mrs_z[j], lambda1_z=M$lambda1_z[j]) }
}
fwrite(rbindlist(ev_tab), file.path(OUT_DIR, "event_study.csv"))
n_lead <- sum(vapply(leads, function(x) isTRUE(x$leads), logical(1)))
cat(sprintf("[event] %d/4 bear dates show pre-rise (near>pre)\n", n_lead))
for (nm in names(leads)) cat(sprintf("   %s: pre=%.3f near=%.3f leads=%s\n",
    nm, leads[[nm]]$pre, leads[[nm]]$near, leads[[nm]]$leads))

# ── incremental OLS (EIGEN parity) on lockbox window ────────────────
reg <- M[Date <= LOCKBOX_CUT &
         is.finite(fwd_H) & is.finite(ews_combo) &
         is.finite(mrs_z) & is.finite(lambda1_z)]
cat(sprintf("[reg] OLS sample (<= lockbox %s): n=%d\n", LOCKBOX_CUT, nrow(reg)))

getco <- function(fit, term, col="t value"){
  s <- summary(fit)$coefficients; if (!(term %in% rownames(s))) return(NA_real_)
  unname(s[term, col]) }

# Model A: ctrl RE_MRS only (matches EIGEN univariate-incremental design)
mA <- lm(fwd_H ~ mrs_z + ews_combo, data=reg)
# Model B: ctrl RE_MRS + lambda1-share (must beat the failed 1.74 construct)
mB <- lm(fwd_H ~ mrs_z + lambda1_z + ews_combo, data=reg)
# Components diagnostic
mC <- lm(fwd_H ~ mrs_z + lambda1_z + z_op + z_var + z_ar1 + z_disp, data=reg)

t_A <- getco(mA, "ews_combo")
t_B <- getco(mB, "ews_combo")
p_B <- getco(mB, "ews_combo", "Pr(>|t|)")
coef_B <- getco(mB, "ews_combo", "Estimate")
t_lam_B <- getco(mB, "lambda1_z")
dR2 <- summary(mB)$r.squared - summary(lm(fwd_H ~ mrs_z + lambda1_z, data=reg))$r.squared

cat(sprintf("\n[reg] Model A (ctrl RE_MRS):      ews_combo coef=%.5f t=%.2f\n",
    getco(mA,"ews_combo","Estimate"), t_A))
cat(sprintf("[reg] Model B (ctrl RE_MRS+lam1): ews_combo coef=%.5f t=%.2f  (lambda1_z t=%.2f)\n",
    coef_B, t_B, t_lam_B))
cat(sprintf("[reg] deltaR2 (ews over mrs+lam1) = %.5f\n", dR2))
cat(sprintf("[reg] cor(ews_combo, mrs_z)=%.3f  cor(ews_combo, lambda1_z)=%.3f\n",
    cor(reg$ews_combo, reg$mrs_z), cor(reg$ews_combo, reg$lambda1_z)))
comp <- list(z_op=getco(mC,"z_op"), z_var=getco(mC,"z_var"),
             z_ar1=getco(mC,"z_ar1"), z_disp=getco(mC,"z_disp"))
cat("[reg] component t (ctrl mrs+lam1): "); print(round(unlist(comp),3))

# sign check: EWS_combo intended as RISK signal -> coef should be NEGATIVE
sign_ok <- is.finite(coef_B) && coef_B < 0

# ── verdict ─────────────────────────────────────────────────────────
go_event <- (n_lead >= 3)
go_incr  <- is.finite(t_B) && abs(t_B) >= 2
verdict <- if (go_event && go_incr) {
  sprintf("GO (event lead %d/4 + EWS_combo |t|=%.2f >= 2 after RE_MRS+lambda1 ctrl; beats EIGEN 1.74)",
          n_lead, t_B)
} else {
  sprintf("NO-GO (event lead %d/4, EWS_combo t=%.2f vs |t|>=2 gate; EIGEN line 1.74)",
          n_lead, t_B)
}

findings <- list(
  screen="order_param_critical_slowing",
  run_date=as.character(Sys.Date()),
  idea="Order-parameter (cross-sectional sign-alignment |m|) + dispersion + critical-slowing (rolling Var + AR1) early-warning combo; RE_MRS-incremental forward-bear (Scheffer 2009). Aims to be a LEADING diagnostic distinct from RE_MRS (lagging) and from EIGEN-ENTRY lambda1-share (which failed at t=1.74).",
  test_type="event-study (4 KR bear dates) + RE_MRS-incremental OLS (fwd_21d ~ mrs_z + lambda1_z + ews_combo), EIGEN-ENTRY 설계 정합, lockbox strict <=2023-12-22",
  screen_only=TRUE, tradeable=FALSE, data_feasible=TRUE,
  n_obs=nrow(reg),
  horizon_days=H,
  label="forward 21d BM return <= -0.05 (bear) / continuous fwd_H for OLS",
  universe="KOSPI200 ∪ KOSDAQ150 (rawdata K200==1 | KQ150==1 PIT flags)",
  re_mrs_control=".cache/regime_daily_v2.parquet MRS -> expanding z",
  lambda1_control="rolling 60d cross-sectional corr eigen lambda1/sum (EIGEN-ENTRY construct reproduced)",
  event_lead_count=n_lead, event_lead_total=4,
  event_lead_detail=leads,
  ews_t_ctrl_remrs=round(t_A,3),
  ews_t_ctrl_remrs_plus_lambda1=round(t_B,3),
  ews_coef_ctrl_remrs_plus_lambda1=signif(coef_B,4),
  ews_p_ctrl_remrs_plus_lambda1=signif(p_B,4),
  ews_sign_is_risk_direction_negative=sign_ok,
  lambda1_z_t_in_model_B=round(t_lam_B,3),
  deltaR2_ews_over_mrs_lambda1=signif(dR2,4),
  cor_ews_mrs=round(cor(reg$ews_combo, reg$mrs_z),3),
  cor_ews_lambda1=round(cor(reg$ews_combo, reg$lambda1_z),3),
  component_t_ctrl_mrs_lambda1=lapply(comp, function(x) round(x,3)),
  eigen_failure_line=1.74,
  go_threshold="event lead>=3/4 AND ews_combo |t|>=2 (after RE_MRS + lambda1-share control)",
  verdict=verdict,
  pit_notes="features expanding-z (past-only, warmup 60); forward label only future (shift n=H type=lead CORRECT); lambda1/mrs end_date<=t; OLS sample strict <= lockbox 2023-12-22; C2 same-day circular avoided (label is forward).",
  caveats=c(
    "pooled-OLS forward-21d overlapping -> Newey-West HAC 미적용 (t 다소 낙관 가능, EIGEN-ENTRY와 동일 한계로 비교는 공정).",
    "EWS_combo는 4성분 단순 합 (가중 sweep 미수행, cheap spec).",
    "lambda1-share는 coarse-5d + dense around-bear grid + ffill (전기간 daily 미산출).",
    "WIN_CS=63, LOOKBACK=60 단일 설정 (민감도 미검증)."),
  recommendation="advisory only (not tradeable, Cycle2 교훈). PASS 시 order-parameter 성분에 한정해 canonical/forge 권고."
)
writeLines(toJSON(findings, auto_unbox=TRUE, pretty=TRUE),
           file.path(OUT_DIR, "screen_findings.json"))
cat(sprintf("\n[op_cs] VERDICT: %s\n[op_cs] DONE\n", verdict))
