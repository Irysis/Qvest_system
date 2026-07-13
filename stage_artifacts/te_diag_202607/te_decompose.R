## ============================================================================
## TE 과소추정 진단 (task #47, 2026-07-13) — risk-research diagnostic
## READ-ONLY. book_state/배포 파라미터 무수정. weight 제안 없음.
## 실현 TE 0.3324/yr vs 예측(full-sample) 0.1898/yr, ratio 1.751 > 1.5 임계 원인 분해.
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(data.table); library(arrow); library(jsonlite)
}))
setDTthreads(1)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
OUT  <- file.path(ROOT, "stage_artifacts/te_diag_202607")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

## ---- 1. 데이터 로드: rds(계약-authoritative book+bm) + panel(ret_orig+exposure) ----
bt <- readRDS(file.path(ROOT, "qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds"))
pr <- as.data.table(bt$period_returns)[, .(date = as.Date(date), book_rds = ret_net)]
bm <- as.data.table(bt$benchmark_returns)[, .(date = as.Date(date), bm = benchmark_ret)]
pan <- fread(file.path(ROOT, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
pan[, anchor_date := as.Date(anchor_date)]
pan <- pan[, .(date = anchor_date, realized_ym, regime, ret_orig, beta_R05, m4)]
pan[, exposure := beta_R05 * m4]           # 투자비중 (나머지 현금, r_cash≈0)
COST <- 0.0015

d <- Reduce(function(a,b) merge(a,b,by="date",all=FALSE), list(pr, bm, pan))
setorder(d, date)
stopifnot(nrow(d) >= 265)
cat(sprintf("[merge] n=%d  %s ~ %s\n", nrow(d), min(d$date), max(d$date)))

## book 재구성 (내부정합 분해용): book_recon = exposure*ret_orig - dR05*cost
d[, dR05 := abs(beta_R05 - shift(beta_R05, 1, fill = 1.0))]
d[, book_recon := exposure * ret_orig - dR05 * COST]
## rds book vs recon 정합 점검
d[, book_gap := book_rds - book_recon]
cat(sprintf("[recon check] |book_rds - book_recon| median=%.5f  max=%.5f  (last month gap=%.5f)\n",
            median(abs(d$book_gap)), max(abs(d$book_gap)), d$book_gap[nrow(d)]))
cat("  gap>0.005 months:\n"); print(d[abs(book_gap)>0.005, .(date, book_rds=round(book_rds,4), book_recon=round(book_recon,4), gap=round(book_gap,4))])

## ---- active 시계열 (두 basis) ----
d[, active_rds   := book_rds   - bm]   # authoritative (0.1898/0.3324 재현용)
d[, active_recon := book_recon - bm]   # 분해용 (sel+ovl 정확 합)
## 성분: 선택 sel = (fully-invested base) - bm ;  오버레이 ovl = (exposure-1)*ret_orig
d[, sel := ret_orig - bm]
d[, ovl := (exposure - 1) * ret_orig]
d[, cost_term := -dR05 * COST]
## active_recon = sel + ovl + cost_term (항등 검증)
d[, ident_err := active_recon - (sel + ovl + cost_term)]
cat(sprintf("[identity] max|active_recon-(sel+ovl+cost)|=%.2e\n", max(abs(d$ident_err))))

te <- function(x) sd(x, na.rm=TRUE) * sqrt(12)
n <- nrow(d)
idx21 <- (n-20):n ; idx12 <- (n-11):n ; idx36 <- (n-35):n

## ---- 2. 전기간 vs trailing TE (authoritative rds-basis) ----
cat("\n===== [A] TE 재현 (rds-authoritative) =====\n")
cat(sprintf("  full(%d)   TE=%.4f  active_ann=%.4f\n", n, te(d$active_rds), mean(d$active_rds)*12))
cat(sprintf("  trail36    TE=%.4f\n", te(d$active_rds[idx36])))
cat(sprintf("  trail21    TE=%.4f  ratio_vs_full=%.3f\n", te(d$active_rds[idx21]), te(d$active_rds[idx21])/te(d$active_rds)))
cat(sprintf("  trail12    TE=%.4f\n", te(d$active_rds[idx12])))

## ---- 3. 구조 분해: Var(active) = Var(sel)+Var(ovl)+2Cov (recon-basis) ----
vdecomp <- function(ix, lab){
  a <- d$active_recon[ix]; s <- d$sel[ix]; o <- d$ovl[ix]
  Va <- var(a); Vs <- var(s); Vo <- var(o); Cso <- cov(s,o)
  # variance shares (annualized te = sqrt(V)*sqrt(12)); 성분 기여는 분산가법
  data.table(window=lab, n=length(ix),
             TE_recon = sqrt(Va)*sqrt(12),
             TE_from_sel = sqrt(max(Vs,0))*sqrt(12),
             TE_from_ovl = sqrt(max(Vo,0))*sqrt(12),
             var_share_sel = Vs/Va, var_share_ovl = Vo/Va, var_share_2cov = 2*Cso/Va,
             cov_sel_ovl = Cso, corr_sel_ovl = Cso/sqrt(Vs*Vo))
}
cat("\n===== [B] 구조분해 sel(선택) vs ovl(오버레이 노출스위칭) =====\n")
dec <- rbind(vdecomp(1:n,"full"), vdecomp(idx36,"trail36"), vdecomp(idx21,"trail21"), vdecomp(idx12,"trail12"))
print(dec[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(dec, file.path(OUT,"decomp_sel_vs_overlay.csv"))

## ---- 4. 시간 국소화: melt-up window (2024-10~2026-06 = trailing21) 성분별 월기여 ----
cat("\n===== [C] 월별 active^2 기여 top (trailing21 분산 집중도) =====\n")
d21 <- d[idx21]
d21[, contrib_var := (active_rds - mean(d21$active_rds))^2]
d21[, contrib_pct := contrib_var / sum(contrib_var)]
setorder(d21, -contrib_pct)
print(d21[1:8, .(date, realized_ym, regime, exposure=round(exposure,3), ret_orig=round(ret_orig,3),
                 bm=round(bm,3), active_rds=round(active_rds,3),
                 sel=round(sel,3), ovl=round(ovl,3), contrib_pct=round(contrib_pct,3))])
cat(sprintf("→ 상위 3개월이 trailing21 active 분산의 %.1f%% 차지\n", 100*sum(d21$contrib_pct[1:3])))
setorder(d21, date)
fwrite(d21[, .(date, realized_ym, regime, exposure, ret_orig, bm, book_rds, active_rds, sel, ovl, contrib_pct)],
       file.path(OUT,"trailing21_monthly.csv"))

## melt-up 월 정의: 2025-01 이후 대형 BM월 (bm>10%) 제거 시 TE
meltup_ix <- which(d$date >= as.Date("2025-01-01") & d$bm > 0.10)
cat(sprintf("\n[melt-up 월] bm>10%% & 2025+ : %d개월 (%s)\n", length(meltup_ix),
            paste(format(d$date[meltup_ix],"%Y-%m"), collapse=", ")))
ix21_ex <- setdiff(idx21, meltup_ix)
cat(sprintf("  trailing21 TE(전체)=%.4f  →  melt-up월 제거후 TE=%.4f  (Δ=%.4f)\n",
            te(d$active_rds[idx21]), te(d$active_rds[ix21_ex]), te(d$active_rds[idx21])-te(d$active_rds[ix21_ex])))

## ---- 5. 국면조건부 TE ----
cat("\n===== [D] 국면조건부 active vol (TE_regime) =====\n")
reg <- d[, .(n=.N, active_te = te(active_rds), active_mean_ann = mean(active_rds)*12,
             bm_vol_ann = sd(bm)*sqrt(12), mean_exposure = mean(exposure)), by=regime][order(-active_te)]
print(reg[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(reg, file.path(OUT,"regime_conditional_te.csv"))

## ---- 6. 벤치 자체 변동성 (component 4 proxy: 집중/melt-up 유발 BM vol 폭발) ----
cat("\n===== [E] BM 자체 변동성 (full vs trailing) — 집중레짐 proxy =====\n")
cat(sprintf("  BM vol_ann: full=%.4f  trail36=%.4f  trail21=%.4f  trail12=%.4f\n",
            sd(d$bm)*sqrt(12), sd(d$bm[idx36])*sqrt(12), sd(d$bm[idx21])*sqrt(12), sd(d$bm[idx12])*sqrt(12)))
cat(sprintf("  book vol_ann: full=%.4f  trail21=%.4f\n", sd(d$book_rds)*sqrt(12), sd(d$book_rds[idx21])*sqrt(12)))
cat(sprintf("  up_capture trail21=%.3f  down_capture trail21=%.3f (BM 상승 못따라감 = active 음의 꼬리)\n",
            sum(pmax(d$book_rds[idx21],0))/sum(pmax(d$bm[idx21],0)),
            sum(pmin(d$book_rds[idx21],0))/sum(pmin(d$bm[idx21],0))))

## ---- 7. 워크포워드 TE 예측기 평가 (PIT: 각 시점 과거만) ----
## 후보: (i) expanding constant  (ii) rolling-36  (iii) EWMA λ=0.94  (iv) EWMA λ=0.97
## (v) regime-conditional (과거 동일국면 sd). realized proxy = |active_t| (1-step) → σ̂_t 대비.
cat("\n===== [F] 워크포워드 TE 예측기 평가 (PIT past-only) =====\n")
a <- d$active_rds; rg <- d$regime; N <- length(a)
ewma_sig <- function(a, lam){ s <- rep(NA_real_, N); v <- var(a[1:12]);
  for(t in 13:N){ v <- lam*v + (1-lam)*a[t-1]^2; s[t] <- sqrt(v) }; s }  # PIT: t-1까지
sig_exp <- rep(NA_real_,N); sig_r36 <- rep(NA_real_,N); sig_reg <- rep(NA_real_,N)
for(t in 13:N){
  sig_exp[t] <- sd(a[1:(t-1)])
  w <- a[max(1,t-36):(t-1)]; sig_r36[t] <- sd(w)
  past_same <- a[1:(t-1)][rg[1:(t-1)] == rg[t]]
  sig_reg[t] <- if(length(past_same)>=6) sd(past_same) else sd(a[1:(t-1)])
}
sig_e94 <- ewma_sig(a, 0.94); sig_e97 <- ewma_sig(a, 0.97)
ests <- list(expand_const=sig_exp, roll36=sig_r36, ewma94=sig_e94, ewma97=sig_e97, regime_cond=sig_reg)
ev_tab <- rbindlist(lapply(names(ests), function(nm){
  s <- ests[[nm]]; ok <- which(is.finite(s) & s>0)
  z <- a[ok]/s[ok]                          # 표준화 잔차 (예측 정확 시 var(z)=1)
  ratio_ann <- sqrt(mean(z^2))              # 실현/예측 분산비 (>1 = 과소예측)
  # 12m 실현 TE / 시작시점 예측 TE 의 alert(>1.5) 빈도
  br <- 0; cnt <- 0
  for(t in ok){ if(t+11<=N){ realTE <- sd(a[t:(t+11)]); if(realTE/s[t] > 1.5){br<-br+1}; cnt<-cnt+1 }}
  data.table(estimator=nm, n_eval=length(ok),
             realized_over_pred = ratio_ann,          # 1.0 이상 = 과소추정
             pct_z_gt1 = mean(abs(z)>1),
             alert_1p5_rate = if(cnt>0) br/cnt else NA_real_,
             current_TE_forecast_ann = s[N]*sqrt(12)) # 현 vintage 예측(t=N, 과거만)
}))
print(ev_tab[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(ev_tab, file.path(OUT,"walkforward_estimator_eval.csv"))

## ---- 8. 갱신 TE 예측 + CI (2 시나리오) ----
## χ² 기반 분산 CI: (m-1)s²/σ² ~ χ²_{m-1}; TE_hat = sd*sqrt(12)
ci_te <- function(x){ m <- length(x); s2 <- var(x);
  lo <- (m-1)*s2/qchisq(0.95, m-1); hi <- (m-1)*s2/qchisq(0.05, m-1)
  c(te=sqrt(s2)*sqrt(12), lo=sqrt(lo)*sqrt(12), hi=sqrt(hi)*sqrt(12)) }
cat("\n===== [G] 갱신 TE 예측 + 90% CI (시나리오 병기) =====\n")
sc_persist  <- ci_te(a[idx21])                      # melt-up 지속 = trailing21
sc_persist12<- ci_te(a[idx12])
sc_normal   <- ci_te(a[idx36])                      # 정상화 = trailing36 (blended)
sc_full     <- ci_te(a)                             # full-sample (구 예측 기준)
scen <- data.table(
  scenario = c("현행(구예측=full-sample)","정상화(trail36 blended)","melt-up지속(trail21)","melt-up지속-보수(trail12)"),
  TE_forecast = c(sc_full["te"], sc_normal["te"], sc_persist["te"], sc_persist12["te"]),
  CI90_lo = c(sc_full["lo"], sc_normal["lo"], sc_persist["lo"], sc_persist12["lo"]),
  CI90_hi = c(sc_full["hi"], sc_normal["hi"], sc_persist["hi"], sc_persist12["hi"]))
print(scen[, lapply(.SD, function(x) if(is.numeric(x)) round(x,4) else x)])
fwrite(scen, file.path(OUT,"te_forecast_scenarios.csv"))

## EWMA94 현 vintage + regime-cond 현 국면(NEUTRAL≈NORMAL) 예측
cat(sprintf("\n  EWMA94 현 vintage 예측 TE=%.4f  | regime_cond(현 NORMAL/NEUTRAL) 예측 TE=%.4f\n",
            sig_e94[N]*sqrt(12), sig_reg[N]*sqrt(12)))

## ---- 저장: 종합 json ----
res <- list(
  as_of = "2026-07-13", book = "STR_1715_on_M4_R05_noLayer4_PG2", basis = "recon_backtested read-only",
  te_authoritative = list(full = te(d$active_rds), trail36 = te(d$active_rds[idx36]),
                          trail21 = te(d$active_rds[idx21]), trail12 = te(d$active_rds[idx12]),
                          ratio_21_vs_full = te(d$active_rds[idx21])/te(d$active_rds)),
  recon_check = list(book_gap_median = median(abs(d$book_gap)), book_gap_max = max(abs(d$book_gap)),
                     last_month_gap = d$book_gap[nrow(d)]),
  structural_decomp_trail21 = as.list(dec[window=="trail21"]),
  structural_decomp_full = as.list(dec[window=="full"]),
  meltup_months = format(d$date[meltup_ix],"%Y-%m"),
  te_trail21_ex_meltup = te(d$active_rds[ix21_ex]),
  estimator_eval = ev_tab, forecast_scenarios = scen,
  bm_vol = list(full = sd(d$bm)*sqrt(12), trail21 = sd(d$bm[idx21])*sqrt(12)))
write_json(res, file.path(OUT,"te_diag_summary.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
fwrite(d[, .(date, realized_ym, regime, exposure, ret_orig, bm, book_rds, book_recon, active_rds, sel, ovl)],
       file.path(OUT,"merged_series.csv"))
cat("\n[DONE] outputs →", OUT, "\n")
