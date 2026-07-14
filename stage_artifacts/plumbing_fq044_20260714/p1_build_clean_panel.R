## ============================================================================
## p1_build_clean_panel.R — FQ-044 P2 (task #73): clean(T-1, off=0) 268m panel rebuild
## Recipe = R28/R29 calibrated builder (stage_artifacts/WT_D20260714_004/_build_score.R,
##   verbatim port of production _recompute_alpha_asof.R) with theta_mode="stored"
##   (stored panel's own theta_core, = 0.25x4 core EW) — i.e., recon variant `0_stored_S7`.
## NO reinvention: builder sourced as-is; screening = r29_screen.R path verbatim.
## Parity targets:
##   (1) score-level: identical to recon_panels$`0_stored_S7` (max|d| ~ 0)
##   (2) screen-level: cap-w top-25 PORT_t == 3.058 (R28/R29 measured, stored theta clean base)
## Output (intermediate, task dir only — production write happens in p2 after prod parity):
##   clean_panel_stage.parquet + p1_parity.rds
## READ-ONLY vs 05_Production. book_state untouched.
## ============================================================================
suppressPackageStartupMessages({library(arrow); library(data.table); library(jsonlite);
  library(lubridate); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
TD <- file.path(QM, "stage_artifacts/plumbing_fq044_20260714")
save_safe <- function(obj, path, writer){tmp<-paste0(path,".tmp_",Sys.getpid()); writer(obj,tmp)
  if(file.exists(path))file.remove(path); if(!file.rename(tmp,path))stop("rename ",path)}

## ---- original (contaminated) stored panel: dates + stored theta ----
BKP <- file.path(QM,"05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m.parquet")
bk <- as.data.table(read_parquet(BKP)); bk[,Date:=as.Date(Date)]
asofs <- sort(unique(bk$Date))
cat(sprintf("stored panel: %d months %s..%s\n", length(asofs), as.character(min(asofs)), as.character(max(asofs))))
theta_map <- unique(bk[,.(Date, theta_core)])
get_stored_theta <- function(d){ s<-theta_map[Date==d,theta_core][1]; if(is.na(s))return(NULL); unlist(fromJSON(s)) }

## ---- R28 builder (verbatim reuse — defines recon_init/build_month_score) ----
source(file.path(QM,"stage_artifacts/WT_D20260714_004/_build_score.R"))
SLEEVE_CORE7 <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
recon_init()

rows <- vector("list", length(asofs)); errs <- list()
t0 <- Sys.time()
for(i in seq_along(asofs)){
  AS_OF <- asofs[i]
  th <- get_stored_theta(AS_OF)
  if(is.null(th)){ errs[[as.character(AS_OF)]] <- "no stored theta"; next }
  r <- tryCatch(build_month_score(AS_OF, SLEEVE_CORE7, theta_mode="stored", theta_override=th),
                error=function(e) list(err=conditionMessage(e)))
  if(is.null(r) || !is.null(r$err)){ errs[[as.character(AS_OF)]] <- if(is.null(r)) "NULL (factor_db missing)" else r$err; next }
  rows[[i]] <- r$dt
  if(i %% 40 == 0) cat(sprintf("  ...%d/%d (%s) %.1fs\n", i, length(asofs), as.character(AS_OF),
    as.numeric(Sys.time()-t0, units="secs")))
}
CLEAN <- rbindlist(rows, fill=TRUE)
cat(sprintf("clean rebuild: %d rows, %d/%d months. build errors: %d\n",
  nrow(CLEAN), uniqueN(CLEAN$Date), length(asofs), length(errs)))
if(length(errs)){ cat("ERROR months:\n"); for(nm in names(errs)) cat("  ", nm, ":", errs[[nm]], "\n") }

## ---- parity (1): vs recon_panels `0_stored_S7` (R29-measured object) ----
PAN <- as.data.table(read_parquet(file.path(QM,"stage_artifacts/WT_D20260714_004/recon_panels.parquet")))
PAN[,Date:=as.Date(Date)]
## recon keyed by d0 (fwd sig month-end); AS_OF = first-of-month(month(d0)+1)
PAN[, AS_OF := as.Date(paste0(format(Date %m+% months(1), "%Y-%m"), "-01"))]
M1 <- merge(CLEAN[,.(AS_OF=Date,Ticker,score_clean=score_eff)],
            PAN[is.finite(`0_stored_S7`),.(AS_OF,Ticker,score_recon=`0_stored_S7`)],
            by=c("AS_OF","Ticker"))
p1_maxd <- M1[, max(abs(score_clean-score_recon))]
p1_cor  <- M1[, cor(score_clean, score_recon)]
n_clean_only <- nrow(CLEAN) - nrow(M1)
cat(sprintf("[parity1 score vs recon 0_stored_S7] n=%d max|d|=%.3e cor=%.10f rows_clean_not_in_recon=%d\n",
  nrow(M1), p1_maxd, p1_cor, n_clean_only))

## ---- parity (2): cap-w top-25 screen == 3.058 (r29_screen.R path verbatim) ----
source(file.path(QM,"02_Infrastructure/contracts/weighted_screen_bt.R"))
zc2 <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-9)x-m else (x-m)/s}
cap_norm<-function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
SI <- readRDS(file.path(QM,"stage_artifacts/WT_D20260714_004/screen_inputs.rds"))
fwd_ret<-SI$fwd_ret; bench<-SI$bench; liqf<-SI$liqf; SIZE<-SI$SIZE
## map CLEAN AS_OF -> d0 (month-end of AS_OF-1 month) exactly as screen_r28.R did for stored panel
d0map <- data.table(d0=sort(unique(fwd_ret$Date))); d0map[, ym := format(d0, "%Y-%m")]
CL <- copy(CLEAN); CL[, map_ym := format(Date-1, "%Y-%m")]   # Date is first-of-month; Date-1 = prev month end
CLd <- merge(CL, d0map, by.x="map_ym", by.y="ym")
S <- merge(CLd[is.finite(score_eff),.(Date=d0,Ticker,sc=score_eff)], SIZE, by=c("Date","Ticker"))
S <- merge(S, liqf, by=c("Date","Ticker"), all.x=TRUE); S <- S[is.na(adv)|adv>=2e8]
dd <- sort(unique(S$Date)); W<-list()
for(i in seq_along(dd)){d<-dd[i]; sub<-S[Date==d]; if(nrow(sub)<25) next
  setorder(sub,-sc); hd<-head(sub,25); W[[as.character(d)]]<-data.table(Date=d,Ticker=hd$Ticker,w=cap_norm(hd$Size))}
Wc <- rbindlist(W)
res <- weighted_screen_bt(Wc, fwd_ret, bench, cost_bps_oneway=15, run_id="cleanT1_parity", strategy_id="cleanT1_parity")
p2_pt <- res$portfolio_alpha_t_nw_lag3
cat(sprintf("[parity2 screen] PORT_t=%.4f (target R28/R29 stored-theta clean = 3.058) IR=%.3f n=%d\n",
  p2_pt, res$information_ratio, res$n_months))

## ---- Ret_1m convention check vs original panel (populate from canonical fwd_ret) ----
fr <- merge(CLd[,.(AS_OF=Date, Ticker, d0)], fwd_ret[,.(d0=Date,Ticker,Ret_1m_fwd=Ret_1m)], by=c("d0","Ticker"), all.x=TRUE)
cmp <- merge(fr, bk[,.(AS_OF=Date,Ticker,Ret_1m_orig=Ret_1m)], by=c("AS_OF","Ticker"))
both <- cmp[is.finite(Ret_1m_fwd) & is.finite(Ret_1m_orig)]
cat(sprintf("[Ret_1m check] common=%d finite-both=%d cor=%.4f max|d|=%.4g share|d|<1e-6=%.3f\n",
  nrow(cmp), nrow(both), both[,cor(Ret_1m_fwd,Ret_1m_orig)], both[,max(abs(Ret_1m_fwd-Ret_1m_orig))],
  both[,mean(abs(Ret_1m_fwd-Ret_1m_orig)<1e-6)]))

## ---- stage save (task dir) ----
save_safe(CLEAN, file.path(TD,"clean_panel_stage.parquet"), function(o,p) write_parquet(o,p))
saveRDS(list(p1_maxd=p1_maxd, p1_cor=p1_cor, n_m1=nrow(M1), n_clean=nrow(CLEAN),
             months_clean=uniqueN(CLEAN$Date), build_errors=errs,
             p2_port_t=p2_pt, p2_ir=res$information_ratio, p2_n_months=res$n_months,
             ret1m_cor=both[,cor(Ret_1m_fwd,Ret_1m_orig)],
             ret1m_exact_share=both[,mean(abs(Ret_1m_fwd-Ret_1m_orig)<1e-6)]),
        file.path(TD,"p1_parity.rds"))
cat("P1_BUILD_DONE\n")
