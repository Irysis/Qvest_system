# Phase 2b — axis screen (IS-only) + multi-axis MID composite selection + final dual-basis
suppressMessages({library(arrow); library(data.table)})
setDTthreads(1); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-D20260710_001")
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
panel <- readRDS(file.path(SA,"panel.rds"))

# ---- inputs ----
bm <- as.data.table(read_parquet(file.path(ROOT,".cache","benchmark.parquet")))
bm[, Dt := as.Date(Date)]; bm[, ym := format(Dt,"%Y-%m")]; bm <- bm[!is.na(BM_Ret)]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m[, Date := as.Date(paste0(ym,"-01"))]; bm_m[, bm_fwd := shift(bm_ret, type="lead", n=1L)]
benchdt <- bm_m[!is.na(bm_fwd), .(Date, BM_Ret=bm_fwd)]
returns_dt <- panel[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]
liq_dt  <- panel[, .(Date, Ticker, adv=tv20)]
size_dt <- panel[, .(Date, Ticker, Size)]

IS_END <- as.Date("2018-12-01")
is_dates <- function(dt) dt[Date <= IS_END]

axes <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap","M08_Residual_Mom",
          "Q07_Earnings_Stability","Q25_Ohlson_O","V02_EP","V12_Composite_Value",
          "Q01_GPA","Q02_ROE","M01_Mom_12_1","M13_VolAdj_Mom","D01_IdioVol",
          "D18_BAB_Rank","L01_Amihud","M11_ST_Reversal")
family <- c(C01_SUE="revision",C02_EPS_Chg_1m="revision",C04_ESBR="revision",C06_TP_Gap="revision",
            M08_Residual_Mom="momentum",Q07_Earnings_Stability="quality",Q25_Ohlson_O="quality",
            V02_EP="value",V12_Composite_Value="value",Q01_GPA="quality",Q02_ROE="quality",
            M01_Mom_12_1="momentum",M13_VolAdj_Mom="momentum",D01_IdioVol="lowvol",
            D18_BAB_Rank="lowvol",L01_Amihud="liquidity",M11_ST_Reversal="reversal")

pt <- function(scores_dt, top_n=25L){
  r <- canonical_screen_bt(scores_dt, returns_dt, benchdt, top_n=top_n, cost_bps_oneway=15,
                           liq_dt=liq_dt, liq_min=2e8, run_id="scr", strategy_id="scr",
                           diag_dual_basis=FALSE)
  c(port_t=r$portfolio_alpha_t_nw_lag3, ir=r$information_ratio, n=r$n_months, to=r$turnover_annual)
}
# rank-IC (Spearman) mean over months, restricted to subset
rank_ic <- function(dt, axcol, subset_tier=NULL){
  d <- dt[!is.na(get(axcol)) & !is.na(Ret_1m)]
  if(!is.null(subset_tier)) d <- d[tier==subset_tier]
  ics <- d[, {if(.N>=8) .(ic=cor(get(axcol), Ret_1m, method="spearman")) else .(ic=NA_real_)}, by=Date]$ic
  mean(ics, na.rm=TRUE)
}

# ================= AXIS SCREEN (IS-only) =================
cat("\n===== AXIS SCREEN (IS <= 2018-12) =====\n")
panelIS <- is_dates(panel)
axtab <- rbindlist(lapply(axes, function(ax){
  sc <- panelIS[!is.na(get(paste0("zc_",ax))), .(Date, Ticker, score=get(paste0("zc_",ax)))]
  p_all <- pt(sc, 25L)
  ic_all <- rank_ic(panelIS, paste0("zc_",ax))
  ic_mid <- rank_ic(panelIS, paste0("zt_",ax), subset_tier="MID")
  data.table(axis=ax, family=family[[ax]], IS_port_t=round(p_all["port_t"],3),
             IS_ir=round(p_all["ir"],3), IS_ic_all=round(ic_all,4), IS_ic_MID=round(ic_mid,4))
}))
setorder(axtab, -IS_port_t)
print(axtab)

# ---- select best-of-family (IS_port_t), require MID-live (IS_ic_MID>0) ----
axtab[, midlive := IS_ic_MID > 0]
sel <- axtab[midlive==TRUE][order(-IS_port_t)][, .SD[1], by=family]
selected_axes <- sel$axis
cat("\n[selected multi-axis menu | best-of-family, MID-live]:\n"); print(sel[, .(axis,family,IS_port_t,IS_ic_MID)])

# ---- composite builder ----
tier_mult <- c(MEGA=0.25, MID=1.0, OTHER=0.5)
build_score <- function(dt, axset, mode, isw=NULL){
  zc_cols <- paste0("zc_",axset); zt_cols <- paste0("zt_",axset)
  if(mode=="EW_notier"){
    s <- rowMeans(as.matrix(dt[, ..zc_cols]), na.rm=TRUE)
  } else if(mode=="EW_midemph"){
    s <- rowMeans(as.matrix(dt[, ..zt_cols]), na.rm=TRUE) * tier_mult[dt$tier]
  } else if(mode=="ISw_midemph"){
    W <- isw/sum(isw); M <- as.matrix(dt[, ..zt_cols])
    s <- as.numeric(M %*% W) ; s <- s * tier_mult[dt$tier]
  } else if(mode=="EW_MIDgate"){
    s <- rowMeans(as.matrix(dt[, ..zt_cols]), na.rm=TRUE)  # MID pool only applied by caller
  }
  s
}
isw <- pmax(sel$IS_port_t, 0)  # IS-strength weights (clipped >=0)

# ================= COMPOSITE CANDIDATES (IS selection) =================
cat("\n===== COMPOSITE CANDIDATES (IS <= 2018-12 whole-univ top-25) =====\n")
mk <- function(dt, mode, midgate=FALSE){
  d <- copy(dt)
  if(midgate) d <- d[tier=="MID"]
  d[, score := build_score(d, selected_axes, if(midgate)"EW_MIDgate" else mode, isw)]
  d[!is.na(score), .(Date,Ticker,score)]
}
cand_defs <- list(
  C1_multiEW_notier = list(mode="EW_notier", midgate=FALSE, top=25L),
  C2_multiEW_midemph= list(mode="EW_midemph",midgate=FALSE, top=25L),
  C3_multiISw_midemph=list(mode="ISw_midemph",midgate=FALSE, top=25L),
  C4_multiEW_MIDgate= list(mode="EW_MIDgate", midgate=TRUE,  top=20L)
)
cand_IS <- rbindlist(lapply(names(cand_defs), function(nm){
  cd <- cand_defs[[nm]]
  sc <- mk(panelIS, cd$mode, cd$midgate)
  p <- pt(sc, cd$top)
  data.table(cand=nm, IS_port_t=round(p["port_t"],3), IS_ir=round(p["ir"],3), IS_to=round(p["to"],2))
}))
# reference incumbent
sc0 <- panelIS[!is.na(score_eff), .(Date,Ticker,score=score_eff)]; p0 <- pt(sc0,25L)
cand_IS <- rbind(data.table(cand="C0_score_eff_ref", IS_port_t=round(p0["port_t"],3),
                            IS_ir=round(p0["ir"],3), IS_to=round(p0["to"],2)), cand_IS)
setorder(cand_IS, -IS_port_t)
print(cand_IS)
cstar <- cand_IS[cand!="C0_score_eff_ref"][which.max(IS_port_t), cand]
cat("\n[SELECTED composite by IS whole-univ port_t]:", cstar, "\n")

# ================= FINAL: full-period + dual-basis for C* and score_eff =================
cat("\n===== FINAL (full period, dual-basis) =====\n")
run_final <- function(dt, mode, midgate, top, sid){
  sc <- mk(dt, mode, midgate)
  canonical_screen_bt(sc, returns_dt, benchdt, top_n=top, cost_bps_oneway=15,
                      liq_dt=liq_dt, liq_min=2e8, run_id=sid, strategy_id=sid,
                      diag_dual_basis=TRUE, size_dt=size_dt)
}
cd <- cand_defs[[cstar]]
fin <- run_final(panel, cd$mode, cd$midgate, cd$top, cstar)
# also score_eff full with dual-basis
fin0 <- canonical_screen_bt(panel[!is.na(score_eff), .(Date,Ticker,score=score_eff)],
                            returns_dt, benchdt, top_n=25L, cost_bps_oneway=15, liq_dt=liq_dt,
                            liq_min=2e8, run_id="score_eff", strategy_id="score_eff",
                            diag_dual_basis=TRUE, size_dt=size_dt)

report_one <- function(f, lab){
  cat(sprintf("\n[%s] cap-w PORT_t=%.4f  IR=%.4f  net_sr=%.4f  TO=%.2f  n=%d\n",
              lab, f$portfolio_alpha_t_nw_lag3, f$information_ratio, f$net_sr, f$turnover_annual, f$n_months))
  ew <- f$diag_ew_universe
  cat(sprintf("     EW-univ diag: PORT_t=%.4f  post2017_t=%.4f  oos_ret_approx=%.4f  net_sr=%.4f  n=%d\n",
              ew$portfolio_alpha_t_nw_lag3 %||% NA, ew$post2017_t_nw_lag3 %||% NA,
              ew$oos_retention_approx %||% NA, ew$net_sr %||% NA, ew$n_months %||% NA))
  ct <- f$diag_cap_tier
  if(isTRUE(ct$available)){
    w <- ct$weight_share_avg; cg <- ct$contrib_gross_annualized
    cat(sprintf("     cap-tier weight: MEGA=%.3f MID=%.3f OTHER=%.3f UNRANK=%.3f\n",
                w$MEGA,w$MID,w$OTHER,w$UNRANKED))
    cat(sprintf("     cap-tier contrib(ann): MEGA=%.4f MID=%.4f OTHER=%.4f\n", cg$MEGA,cg$MID,cg$OTHER))
  }
}
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||is.na(a)) b else a
report_one(fin0, "C0_score_eff")
report_one(fin, cstar)

# post2017 cap-w for C*
pr <- as.data.table(fin$period_returns); pr17 <- pr[date>=as.Date("2017-01-01")]
a17 <- pr17$ret_net - pr17$benchmark_ret
nw_t <- function(x,lag=3){ if(exists(".nw_t_mean",mode="function")) .nw_t_mean(x,lag=lag) else mean(x)/sd(x)*sqrt(length(x)) }
cat(sprintf("\n[%s] cap-w post2017_t=%.4f (n=%d)\n", cstar, nw_t(a17), length(a17)))

# full-period rank-IC / ICIR / harvey-t (advisory) for composite score
sc_full <- mk(panel, cd$mode, cd$midgate)
scp <- merge(sc_full, panel[, .(Date,Ticker,Ret_1m)], by=c("Date","Ticker"))
icv <- scp[!is.na(Ret_1m), {if(.N>=8) .(ic=cor(score,Ret_1m,method="spearman")) else .(ic=NA_real_)}, by=Date]$ic
icv <- icv[!is.na(icv)]
rank_ic_mean <- mean(icv); icir <- mean(icv)/sd(icv); harvey_t <- mean(icv)/sd(icv)*sqrt(length(icv))
cat(sprintf("\n[%s advisory] rank_ic=%.4f icir=%.3f harvey_t=%.3f (n_months=%d)\n",
            cstar, rank_ic_mean, icir, harvey_t, length(icv)))

# correlation of C* vs score_eff (redundancy) — cross-sectional avg
mm <- merge(sc_full[, .(Date,Ticker,cs=score)], panel[, .(Date,Ticker,score_eff)], by=c("Date","Ticker"))
cor_vs_scoreeff <- mm[!is.na(score_eff), .(c=cor(cs,score_eff)), by=Date][, mean(c,na.rm=TRUE)]
cat(sprintf("[%s] avg cross-sec cor vs score_eff = %.3f\n", cstar, cor_vs_scoreeff))

saveRDS(list(axtab=axtab, sel=sel, selected_axes=selected_axes, isw=isw, cand_IS=cand_IS,
             cstar=cstar, cand_defs=cand_defs, fin=fin, fin0=fin0,
             rank_ic=rank_ic_mean, icir=icir, harvey_t=harvey_t, cor_vs_scoreeff=cor_vs_scoreeff,
             post2017_capw_t=nw_t(a17)),
        file.path(SA,"screen_result.rds"))
cat("\n[saved] screen_result.rds\n")
