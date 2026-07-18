# run_R5_regime_beta_attribution.R — R5 lane: regime_beta_attribution
# 핵심질문: R4 cap-tilt lift(EW momentum active port_t 1.277 -> size_prop_cap 2.100)가
#   (i) 2024-26 mega/반도체 레짐·size-beta 노출 = REGIME_MEGA_BETA(standalone 아님, β-예산/오버레이 라우팅)인가,
#   (ii) 전기간 균등·잔차 alpha = ROBUST_CONSTRUCTION(optimizer/RAMP/book 기본가중 이식 실이득)인가?
# 절차: (1) cap-tilt active(vs cap-w KOSPI200) + EW momentum active 월별 산출
#       (2) 기간분해 pre-2017 / 2017-2020 / 2020-2026 (active-t NW·평균)
#       (3) β-귀속: active ~ market(BM_Ret) + SIZE(large-minus-small LMS) → lift = size/market beta인가 잔차 α인가
# PIT: Size는 t-관측 slow-moving 비-알파(재가중·SMB 구성 PIT-safe). weights_R4는 R4 산출(clean). metric_type=weighted.
setwd("C:/Users/99922/OneDrive/Quant_Module_Moltbot")
suppressMessages({library(data.table); library(arrow); library(jsonlite); library(sandwich); library(lmtest)})
setDTthreads(1)
source("04_Research/method_frontier/wt006_exog_forecast/eval_harness.R")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
W6 <- "04_Research/method_frontier/wt006_exog_forecast"

# NW t helper for a mean (reuse harness .nw_t_mean)
nwt <- function(x, lag=3) .nw_t_mean(x, lag=lag)

# ---------- (1) cap-tilt active(deployable size_prop_cap) + EW momentum active ----------
W4 <- as.data.table(read_parquet(file.path(W6,"weights_R4_best_bench_aware.parquet")))
W4[, Date := as.Date(Date)]
r_ct <- weighted_screen_bt(W4, .Rg, .BMg, cost_bps_oneway=15, run_id="r5_captilt", strategy_id="r5_captilt")
pr_ct <- as.data.table(r_ct$period_returns)   # date, ret_net, benchmark_ret
pr_ct[, active := ret_net - benchmark_ret]
cat(sprintf("[R5] cap-tilt full: n=%d port_t=%.3f mean_active=%.5f (ann %.4f)\n",
            nrow(pr_ct), r_ct$portfolio_alpha_t_nw_lag3, mean(pr_ct$active), mean(pr_ct$active)*12))

# EW momentum active (harness .a_mom) — same OOS window
ew <- copy(.a_mom)[, .(date, active_ew=active)]
M <- merge(pr_ct[, .(date, active_ct=active, ret_ct=ret_net, bench=benchmark_ret)], ew, by="date")
M[, date := as.Date(date)]
setorder(M, date)
cat(sprintf("[R5] merged window: n=%d (%s ~ %s)\n", nrow(M), min(M$date), max(M$date)))
cat(sprintf("[R5] EW mom active: mean=%.5f (ann %.4f) t=%.3f | cap-tilt active: mean=%.5f (ann %.4f) t=%.3f\n",
            mean(M$active_ew), mean(M$active_ew)*12, nwt(M$active_ew),
            mean(M$active_ct), mean(M$active_ct)*12, nwt(M$active_ct)))
cat(sprintf("[R5] LIFT (ct - ew): mean=%.5f (ann %.4f) t=%.3f\n",
            mean(M$active_ct-M$active_ew), mean(M$active_ct-M$active_ew)*12, nwt(M$active_ct-M$active_ew)))

# ---------- (2) 기간분해 ----------
M[, yr := as.integer(format(date, "%Y"))]
period_of <- function(y) fifelse(y<2017,"pre2017", fifelse(y<2020,"2017-2020","2020-2026"))
M[, period := period_of(yr)]
per_stat <- M[, .(n=.N,
                  ew_mean_ann = mean(active_ew)*12, ew_t = nwt(active_ew),
                  ct_mean_ann = mean(active_ct)*12, ct_t = nwt(active_ct),
                  lift_mean_ann = mean(active_ct-active_ew)*12, lift_t = nwt(active_ct-active_ew)),
              by=period][order(factor(period,levels=c("pre2017","2017-2020","2020-2026")))]
cat("\n===== (2) PERIOD DECOMPOSITION =====\n"); print(per_stat)

# ---------- (3) β-귀속 회귀 ----------
# SIZE factor LMS = large-minus-small: 유니버스 K200∪KQ150 내 Size 상위테르셀 EW ret - 하위테르셀 EW ret
uni <- .FAM[(K200==1 | KQ150==1) & Date %in% M$date, .(Date, Ticker, Size)]
uni <- merge(uni, .Rg[, .(Date, Ticker, Ret_1m)], by=c("Date","Ticker"))
uni <- uni[is.finite(Size) & Size>0 & is.finite(Ret_1m)]
lms <- uni[, {
  q <- quantile(Size, c(1/3, 2/3), na.rm=TRUE)
  big <- Ret_1m[Size >= q[2]]; sml <- Ret_1m[Size <= q[1]]
  .(LMS = mean(big) - mean(sml), n_big=length(big), n_sml=length(sml))
}, by=Date]
setnames(lms, "Date", "date")
mkt <- .BMg[, .(date=Date, MKT=BM_Ret)]
REG <- Reduce(function(a,b) merge(a,b,by="date"), list(M[,.(date,active_ct,active_ew,lift=active_ct-active_ew)], lms[,.(date,LMS)], mkt))
setorder(REG, date)
cat(sprintf("\n[R5] regression window n=%d. LMS mean_ann=%.4f t=%.3f | MKT mean_ann=%.4f\n",
            nrow(REG), mean(REG$LMS)*12, nwt(REG$LMS), mean(REG$MKT)*12))

nw_reg <- function(form, dat){
  fit <- lm(form, data=dat)
  ct  <- coeftest(fit, vcov.=NeweyWest(fit, lag=3, prewhite=FALSE))
  list(fit=fit, ct=ct, r2=summary(fit)$r.squared)
}
report_reg <- function(tag, form, dat){
  z <- nw_reg(form, dat); ct <- z$ct
  cf <- rownames(ct)
  out <- list(tag=tag, r2=round(z$r2,3), n=nrow(dat))
  for(nm in cf){
    key <- if(nm=="(Intercept)") "alpha" else nm
    out[[paste0(key,"_coef")]] <- round(ct[nm,"Estimate"], 6)
    out[[paste0(key,"_t")]]    <- round(ct[nm,"t value"], 3)
  }
  out[["alpha_ann"]] <- round(ct["(Intercept)","Estimate"]*12, 5)
  cat(sprintf("\n[reg %s] R2=%.3f n=%d\n", tag, z$r2, nrow(dat)))
  print(round(ct[, c("Estimate","Std. Error","t value","Pr(>|t|)")], 5))
  cat(sprintf("  alpha_ann=%.4f  alpha_t=%.3f\n", ct["(Intercept)","Estimate"]*12, ct["(Intercept)","t value"]))
  out
}

reg_ct   <- report_reg("cap_tilt_active ~ MKT + LMS", active_ct ~ MKT + LMS, REG)
reg_ew   <- report_reg("EW_active ~ MKT + LMS",       active_ew ~ MKT + LMS, REG)
reg_lift <- report_reg("LIFT(ct-ew) ~ MKT + LMS",     lift      ~ MKT + LMS, REG)

# 분산분해: cap-tilt active 평균 중 size-beta로 설명되는 몫
beta_lms_ct  <- reg_ct[["LMS_coef"]]; beta_mkt_ct <- reg_ct[["MKT_coef"]]
mean_ct_ann  <- mean(REG$active_ct)*12
explained_size_ann <- beta_lms_ct * mean(REG$LMS) * 12
explained_mkt_ann  <- beta_mkt_ct * mean(REG$MKT) * 12
resid_alpha_ann    <- reg_ct[["alpha_ann"]]
cat(sprintf("\n[R5] cap-tilt active mean_ann=%.4f = size_beta(%.4f) + mkt_beta(%.4f) + resid_alpha(%.4f)\n",
            mean_ct_ann, explained_size_ann, explained_mkt_ann, resid_alpha_ann))
frac_size <- explained_size_ann/mean_ct_ann; frac_alpha <- resid_alpha_ann/mean_ct_ann
cat(sprintf("[R5] fraction: size_beta=%.1f%%  mkt_beta=%.1f%%  resid_alpha=%.1f%%\n",
            frac_size*100, explained_mkt_ann/mean_ct_ann*100, frac_alpha*100))

# LIFT 귀속(핵심): lift가 size-beta인가 잔차인가
beta_lms_lift <- reg_lift[["LMS_coef"]]
mean_lift_ann <- mean(REG$lift)*12
lift_size_ann <- beta_lms_lift * mean(REG$LMS) * 12
lift_alpha_ann<- reg_lift[["alpha_ann"]]
cat(sprintf("[R5] LIFT mean_ann=%.4f = size_beta(%.4f, %.0f%%) + resid_alpha(%.4f, t=%.2f)\n",
            mean_lift_ann, lift_size_ann, lift_size_ann/mean_lift_ann*100, lift_alpha_ann, reg_lift[["alpha_t"]]))

# ---------- (4) 판정 ----------
# 레짐 집중: 2020-2026 lift_t 유의 & pre2017 미미면 regime.  균등 & 잔차 α 유의면 robust.
p2020 <- per_stat[period=="2020-2026"]; ppre <- per_stat[period=="pre2017"]; p1720 <- per_stat[period=="2017-2020"]
lift_alpha_sig <- abs(reg_lift[["alpha_t"]]) >= 1.7          # lift 잔차 α 유의?
ct_alpha_sig   <- abs(reg_ct[["alpha_t"]]) >= 1.7            # cap-tilt active 잔차 α 유의?
size_dominant  <- frac_size >= 0.5                          # size-beta가 cap-tilt 평균의 과반?
lift_size_dom  <- (lift_size_ann/mean_lift_ann) >= 0.5      # lift의 과반이 size-beta?
regime_concentrated <- (p2020$lift_t >= 1.5) && (ppre$lift_t < 1.0)  # 2020+ 집중

verdict <- if(lift_size_dom && regime_concentrated && !lift_alpha_sig){
  "REGIME_MEGA_BETA"
} else if(!lift_size_dom && lift_alpha_sig && ct_alpha_sig){
  "ROBUST_CONSTRUCTION"
} else {
  "MIXED"
}

key_numbers <- sprintf(
  "cap-tilt active port_t=%.2f mean_ann=%.4f; EW port_t=%.2f; LIFT ann=%.4f t=%.2f. Period lift_t: pre2017=%.2f 2017-20=%.2f 2020-26=%.2f. cap-tilt active decomp: size_beta=%.0f%% mkt_beta=%.0f%% resid_alpha=%.0f%%(t=%.2f). LIFT decomp: size_beta=%.0f%% resid_alpha ann=%.4f(t=%.2f). beta_LMS(ct)=%.3f(t=%.2f).",
  r_ct$portfolio_alpha_t_nw_lag3, mean_ct_ann, nwt(M$active_ew), mean_lift_ann, nwt(M$active_ct-M$active_ew),
  ppre$lift_t, p1720$lift_t, p2020$lift_t,
  frac_size*100, explained_mkt_ann/mean_ct_ann*100, frac_alpha*100, reg_ct[["alpha_t"]],
  lift_size_ann/mean_lift_ann*100, lift_alpha_ann, reg_lift[["alpha_t"]],
  beta_lms_ct, reg_ct[["LMS_t"]])

method_note <- sprintf(
  "regime_beta_attribution: deployable cap-tilt momentum(size_prop_cap, R4 weights_R4_best_bench_aware.parquet, [0,0.20] cap) active vs cap-w KOSPI200(.BMg BM_Ret), n=%d months(%s~%s). EW momentum active=harness .a_mom. SIZE factor LMS=유니버스 K200∪KQ150 Size 상위테르셀 EW ret - 하위테르셀 EW ret(t-observable, PIT-safe). MKT=BM_Ret(active-return 회귀라 rf 상쇄). NW lag-3 회귀(sandwich::NeweyWest). weighted_screen_bt contract-grade(build_benchmark_compare). 판정 기준: lift의 과반이 size-beta ∧ 2020+ 집중 ∧ lift 잔차α 비유의 → REGIME_MEGA_BETA / 균등 ∧ 잔차α 유의 → ROBUST_CONSTRUCTION.",
  nrow(M), min(M$date), max(M$date))

out <- list(
  lane="R5 regime_beta_attribution", date=as.character(Sys.Date()),
  cap_tilt_port_t = round(r_ct$portfolio_alpha_t_nw_lag3,3),
  ew_active_t = round(nwt(M$active_ew),3),
  cap_tilt_active_mean_ann = round(mean_ct_ann,5),
  lift_mean_ann = round(mean_lift_ann,5), lift_t = round(nwt(M$active_ct-M$active_ew),3),
  period_decomp = per_stat,
  reg_cap_tilt = reg_ct, reg_ew = reg_ew, reg_lift = reg_lift,
  captilt_decomp = list(mean_ann=round(mean_ct_ann,5), size_beta_ann=round(explained_size_ann,5),
                        mkt_beta_ann=round(explained_mkt_ann,5), resid_alpha_ann=round(resid_alpha_ann,5),
                        frac_size=round(frac_size,3), frac_alpha=round(frac_alpha,3)),
  lift_decomp = list(mean_ann=round(mean_lift_ann,5), size_beta_ann=round(lift_size_ann,5),
                     size_frac=round(lift_size_ann/mean_lift_ann,3),
                     resid_alpha_ann=round(lift_alpha_ann,5), resid_alpha_t=round(reg_lift[["alpha_t"]],3)),
  flags=list(lift_size_dominant=lift_size_dom, regime_concentrated=regime_concentrated,
             lift_alpha_sig=lift_alpha_sig, ct_alpha_sig=ct_alpha_sig, size_dominant=size_dominant),
  verdict=verdict, key_numbers=key_numbers, method_note=method_note)
write_json(out, file.path(W6,"R5_regime_beta_attribution_summary.json"), pretty=TRUE, auto_unbox=TRUE, digits=6)
fwrite(per_stat, file.path(W6,"R5_period_decomp.csv"))
fwrite(REG, file.path(W6,"R5_regression_panel.csv"))
cat("\n===== R5 VERDICT:", verdict, "=====\n")
cat(key_numbers, "\n")
cat("[R5] saved R5_regime_beta_attribution_summary.json / R5_period_decomp.csv / R5_regression_panel.csv\n")
EOF
