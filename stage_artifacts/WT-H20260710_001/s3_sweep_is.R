# WT-H20260710_001 Stage 3 — IS-only sweep (2005..2018-12) over 25 pre-registered configs.
# selection authority = canonical PORT_t (NW lag-3). paired NW-t vs rebuilt-incumbent. rank-IC advisory.
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")
source(file.path(ROOT,"02_Infrastructure","contracts","canonical_screen_bt.R"))
inp <- readRDS(file.path(SA,"inputs.rds"))
m08v <- readRDS(file.path(SA,"m08_variants.rds"))
cv   <- readRDS(file.path(SA,"c_variants.rds"))
scope<-inp$scope; returns_dt<-inp$returns_dt; benchdt<-inp$benchdt; ap<-inp$ap
IS_END <- as.Date("2018-12-01")

.winsor_z <- function(x, sigma=2.5){ if(!is.finite(sigma)) return(x); m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}
.zmad <- function(x){md<-median(x,na.rm=TRUE);ma<-mad(x,na.rm=TRUE);if(is.na(ma)||ma<1e-10)x-md else (x-md)/ma}

# master panel: all factor & variant z-cols on scope
mp <- merge(inp$core_panel, inp$def_panel, by=c("Date","Ticker"), all=TRUE)
mp <- merge(mp, m08v[, c("Date","Ticker", paste0("z_", c("B1_126_21_capm","B2_378_21_capm","B3_252_0_capm","B4_252_21_raw"))), with=FALSE],
            by=c("Date","Ticker"), all.x=TRUE)
mp <- merge(mp, cv[, .(Date,Ticker, z_esbr_3, z_esbr_6, z_tpgap_5, z_tpgap_21)], by=c("Date","Ticker"), all.x=TRUE)

# sleeve builder over explicit column set
build_sleeve <- function(P, cols, sigma, std, missing){
  wl <- list()
  for (fn in cols){ v <- P[, .winsor_z(get(fn), sigma), by=Date]$V1; wl[[fn]] <- v }
  M <- do.call(cbind, wl)
  if (missing=="strict") s <- rowSums(M) else { s <- rowMeans(M, na.rm=TRUE)*ncol(M); s[rowSums(!is.na(M))==0]<-NA_real_ }
  P2 <- data.table(Date=P$Date, Ticker=P$Ticker, sraw=s)
  if (std=="classic") P2[, sz := .zc(sraw), by=Date] else P2[, sz := .zmad(sraw), by=Date]
  P2[, .(Date,Ticker,sz)]
}
build_score <- function(core_cols, def_cols, sigma, std, missing){
  cz <- build_sleeve(mp, core_cols, sigma, std, missing); setnames(cz,"sz","cz")
  dz <- build_sleeve(mp, def_cols, sigma, std, missing); setnames(dz,"sz","dz")
  s <- merge(cz, dz, by=c("Date","Ticker"))
  s[, score := 0.65*cz + 0.35*dz]
  s[!is.na(score), .(Date,Ticker,score)]
}

# ---- pre-registered config expansion (25 distinct + refs) ----
CORE0 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
DEF0  <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
cfgs <- list()
# Block A: 16
for (sg in c(2.0,2.5,3.0,Inf)) for (st in c("classic","robust_mad")) for (ms in c("strict","tolerant")){
  id <- sprintf("A_w%s_%s_%s", ifelse(is.finite(sg),sg,"Inf"), ifelse(st=="classic","cl","mad"), substr(ms,1,3))
  cfgs[[id]] <- list(block="A", core=CORE0, def=DEF0, sigma=sg, std=st, missing=ms)
}
# Block B: 4 new (incumbent formation 2.5/classic/strict, swap M08)
for (b in c("B1_126_21_capm","B2_378_21_capm","B3_252_0_capm","B4_252_21_raw")){
  cfgs[[b]] <- list(block="B", core=CORE0, def=c("Q07_Earnings_Stability", paste0("z_",b), "Q25_Ohlson_O"),
                    sigma=2.5, std="classic", missing="strict")
}
# Block C: 5 new (swap C04/C06 in core)
cfgs[["C1_esbr3m"]]      <- list(block="C", core=c("C01_SUE","C02_EPS_Chg_1m","z_esbr_3","C06_TP_Gap"), def=DEF0, sigma=2.5, std="classic", missing="strict")
cfgs[["C2_esbr6m"]]      <- list(block="C", core=c("C01_SUE","C02_EPS_Chg_1m","z_esbr_6","C06_TP_Gap"), def=DEF0, sigma=2.5, std="classic", missing="strict")
cfgs[["C3_tp5d"]]        <- list(block="C", core=c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","z_tpgap_5"), def=DEF0, sigma=2.5, std="classic", missing="strict")
cfgs[["C4_tp21d"]]       <- list(block="C", core=c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","z_tpgap_21"), def=DEF0, sigma=2.5, std="classic", missing="strict")
cfgs[["C5_esbr3m_tp5d"]] <- list(block="C", core=c("C01_SUE","C02_EPS_Chg_1m","z_esbr_3","z_tpgap_5"), def=DEF0, sigma=2.5, std="classic", missing="strict")
cat("[grid] n_configs=",length(cfgs)," (A16 + B4 + C5). incumbent cell = A_w2.5_cl_str\n")

# ---- IS canonical runner ----
run_is <- function(scores){
  sIS <- scores[Date <= IS_END]
  r <- canonical_screen_bt(sIS, returns_dt, benchdt, top_n=25L, cost_bps_oneway=15,
                           liq_dt=NULL, run_id="is", strategy_id="is", diag_dual_basis=FALSE)
  list(port_t=r$portfolio_alpha_t_nw_lag3, ir=r$information_ratio, sr=r$net_sr,
       to=r$turnover_annual, n=r$n_months, pr=as.data.table(r$period_returns))
}
nw_t <- function(x,lag=3){ if(exists(".nw_t_mean",mode="function")) .nw_t_mean(x,lag=lag) else mean(x)/sd(x)*sqrt(length(x)) }

# incumbent references
inc_rb_score <- build_score(CORE0, DEF0, 2.5, "classic", "strict")           # rebuilt-incumbent (same pipeline)
inc_stored   <- ap[!is.na(score_eff), .(Date,Ticker,score=score_eff)]        # stored book score_eff
R_incrb <- run_is(inc_rb_score); R_stor <- run_is(inc_stored)
cat(sprintf("\n[REF] stored score_eff  IS: PORT_t=%.3f IR=%.3f SR=%.3f TO=%.1f n=%d\n", R_stor$port_t,R_stor$ir,R_stor$sr,R_stor$to,R_stor$n))
cat(sprintf("[REF] rebuilt-incumbent IS: PORT_t=%.3f IR=%.3f SR=%.3f TO=%.1f n=%d\n", R_incrb$port_t,R_incrb$ir,R_incrb$sr,R_incrb$to,R_incrb$n))
incpr <- R_incrb$pr[, .(date, inc_active = ret_net - benchmark_ret)]

# sweep
rows <- list(); prstore <- list()
for (id in names(cfgs)){
  cf <- cfgs[[id]]
  sc <- build_score(cf$core, cf$def, cf$sigma, cf$std, cf$missing)
  R <- run_is(sc)
  pr <- R$pr[, .(date, act = ret_net - benchmark_ret)]
  pm <- merge(pr, incpr, by="date")
  d  <- pm$act - pm$inc_active
  paired_t <- if (sd(d)>0) nw_t(d) else NA_real_
  rows[[id]] <- data.table(config=id, block=cf$block, sigma=ifelse(is.finite(cf$sigma),cf$sigma,Inf),
                           std=cf$std, missing=cf$missing,
                           IS_port_t=round(R$port_t,3), IS_ir=round(R$ir,3), IS_sr=round(R$sr,3),
                           IS_to=round(R$to,1), n=R$n, paired_t_vs_incRB=round(paired_t,3),
                           d_meanactive_bps=round(mean(d)*1e4,2))
  prstore[[id]] <- R$pr
  cat(sprintf("  %-20s block=%s PORT_t=%.3f IR=%.3f paired_t=%.2f dMeanAct=%.1fbps\n",
      id, cf$block, R$port_t, R$ir, ifelse(is.na(paired_t),0,paired_t), mean(d)*1e4))
}
tab <- rbindlist(rows)
tab[, is_incumbent_cell := config=="A_w2.5_cl_str"]
setorder(tab, -IS_port_t)
cat("\n===== IS SWEEP TABLE (sorted by IS PORT_t) =====\n"); print(tab)

# winner candidate = highest IS PORT_t among non-incumbent, must exceed rebuilt-incumbent & stored refs
cand <- tab[is_incumbent_cell==FALSE][order(-IS_port_t)]
winner <- cand[1, config]
cat(sprintf("\n[REF PORT_t] stored=%.3f  rebuilt-incumbent=%.3f\n", R_stor$port_t, R_incrb$port_t))
cat(sprintf("[TOP non-incumbent] %s IS_port_t=%.3f paired_t_vs_incRB=%.3f\n",
    winner, cand[1,IS_port_t], cand[1,paired_t_vs_incRB]))

saveRDS(list(tab=tab, cfgs=cfgs, R_stor=R_stor, R_incrb=R_incrb, winner=winner,
             ref_stored_port_t=R_stor$port_t, ref_incrb_port_t=R_incrb$port_t,
             CORE0=CORE0, DEF0=DEF0), file.path(SA,"sweep_is.rds"))
fwrite(tab, file.path(SA,"sweep_is_table.csv"))
cat("\n[saved] sweep_is.rds + sweep_is_table.csv\n")
