# WT-H20260710_001 Stage 1 — input bundle + incumbent parity check
# PIT: per-sig-date cross-sectional only; benchmark pinned (vintage §7).
suppressMessages({library(arrow); library(data.table)})
options(scipen=999); setDTthreads(1L); set.seed(20260710L)
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR=ROOT, QM_ROOT=ROOT)
source(file.path(ROOT,"02_Infrastructure","config.R"))
source(file.path(ROOT,"02_Infrastructure","factor_db","factor_db_connector.R"))
SA <- file.path(ROOT,"stage_artifacts","WT-H20260710_001")

.winsor_z <- function(x, sigma=2.5){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)return(x);pmax(pmin(x,m+sigma*s),m-sigma*s)}
.zc <- function(x){m<-mean(x,na.rm=TRUE);s<-sd(x,na.rm=TRUE);if(is.na(s)||s<1e-10)x-m else (x-m)/s}

# ---- 1. stored incumbent alpha panel ----
ap <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/WT_D20260425_010/alpha_scores.parquet")))
ap[, Date := as.Date(Date)]
cat("[ap] rows=",nrow(ap)," dates=",uniqueN(ap$Date)," theta_core uniq=",paste(unique(ap$theta_core),collapse=","),
    " theta_def uniq=",paste(unique(ap$theta_defense),collapse=","),"\n")
scope <- ap[, .(Date, Ticker)]           # pinned book scope per month
dts <- sort(unique(ap$Date))

# ---- 2. benchmark (pinned) -> monthly forward ----
bm <- as.data.table(read_parquet(file.path(ROOT,".cache/benchmark_pin20260703.parquet")))
bm[, Dt := as.Date(Date)]; bm <- bm[is.finite(BM_Ret)]; bm[, ym := format(Dt,"%Y-%m")]
bm_m <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
# align to ap sig-date month labels: ap Date -> ym ; forward = next month's realized bm
ap_ym <- data.table(Date=dts, ym=format(dts,"%Y-%m"))
bm_m[, ym_next := format(as.Date(paste0(ym,"-01")) - 1, "%Y-%m")]  # map realized month back to prior sig month? handle below
# Simpler robust alignment: benchdt$BM_Ret at sig-date Date = realized return of the month AFTER sig month.
bm_m2 <- bm[, .(bm_ret=expm1(sum(log1p(BM_Ret)))), by=ym][order(ym)]
bm_m2[, sig_date := as.Date(paste0(ym,"-01"))]
bm_m2[, bm_fwd := shift(bm_ret, type="lead", n=1L)]
# benchdt keyed by sig month-first date
benchdt_raw <- bm_m2[!is.na(bm_fwd), .(ym, BM_Ret=bm_fwd)]
# ap Date -> ym ; join
ap_map <- data.table(Date=dts, ym=format(dts,"%Y-%m"))
benchdt <- merge(ap_map, benchdt_raw, by="ym")[, .(Date, BM_Ret)]
cat("[benchdt] n=",nrow(benchdt)," range=",as.character(min(benchdt$Date)),"..",as.character(max(benchdt$Date)),"\n")

returns_dt <- ap[!is.na(Ret_1m), .(Date, Ticker, Ret_1m)]

# ---- 3. core per-factor aligned-Z via load_month_factors ----
core_facs <- c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","C06_TP_Gap")
cl <- vector("list", length(dts))
for (i in seq_along(dts)) {
  sd <- dts[i]
  fm <- tryCatch(load_month_factors(sd, factor_names=core_facs), error=function(e) NULL)
  if (is.null(fm) || nrow(fm)==0) next
  fm <- as.data.table(fm)
  w <- dcast(fm, Ticker ~ Factor_Name, value.var="Z_Score_Aligned", fun.aggregate=function(x) x[1])
  w[, Date := sd]; cl[[i]] <- w
  if (i %% 50 == 0) cat("  core loaded",i,"/",length(dts),"\n")
}
core_panel <- rbindlist(cl, use.names=TRUE, fill=TRUE)
core_panel <- merge(scope, core_panel, by=c("Date","Ticker"))   # restrict to book scope
cat("[core_panel] rows=",nrow(core_panel)," cols=",paste(setdiff(names(core_panel),c("Date","Ticker")),collapse=","),"\n")
covc <- core_panel[, lapply(.SD, function(x) round(mean(!is.na(x)),3)), .SDcols=intersect(core_facs,names(core_panel))]
cat("[core coverage]\n"); print(t(covc))

# ---- 4. defense per-factor aligned-Z ----
dp <- as.data.table(read_parquet(file.path(ROOT,"stage_artifacts/pg2_defense_optimize/defense_factor_panel.parquet")))
def_facs <- c("Q07_Earnings_Stability","M08_Residual_Mom","Q25_Ohlson_O")
dp <- dp[Factor_Name %in% def_facs]
def_panel <- dcast(dp, sig_date + Ticker ~ Factor_Name, value.var="Z_Aligned")
setnames(def_panel, "sig_date", "Date"); def_panel[, Date := as.Date(Date)]
def_panel <- merge(scope, def_panel, by=c("Date","Ticker"))
cat("[def_panel] rows=",nrow(def_panel)," cols=",paste(setdiff(names(def_panel),c("Date","Ticker")),collapse=","),"\n")
covd <- def_panel[, lapply(.SD, function(x) round(mean(!is.na(x)),3)), .SDcols=intersect(def_facs,names(def_panel))]
cat("[def coverage]\n"); print(t(covd))

# ---- 5. rebuild incumbent composite (winsor2.5/classic/strict) & parity vs stored ----
# strict sleeve builder: winsor_z each factor, EW-sum (NA propagates -> NA if any factor missing), then .zc
build_sleeve <- function(panel, facs, sigma=2.5, std="classic", missing="strict"){
  P <- copy(panel); facp <- intersect(facs, names(P))
  # winsor per Date per factor
  for (fn in facp) P[, (paste0("w_",fn)) := .winsor_z(get(fn), sigma), by=Date]
  wcols <- paste0("w_", facp)
  M <- as.matrix(P[, ..wcols])
  if (missing=="strict") {
    s <- rowSums(M)                      # NA propagates
  } else {                               # tolerant
    s <- rowMeans(M, na.rm=TRUE) * length(facp)
    s[rowSums(!is.na(M))==0] <- NA_real_
  }
  P[, sleeve_raw := s]
  if (std=="classic") P[, sleeve_z := .zc(sleeve_raw), by=Date]
  else { # robust MAD z
    P[, sleeve_z := { md<-median(sleeve_raw,na.rm=TRUE); ma<-mad(sleeve_raw,na.rm=TRUE)
                      if(is.na(ma)||ma<1e-10) sleeve_raw-md else (sleeve_raw-md)/ma }, by=Date]
  }
  P[, .(Date, Ticker, sleeve_z)]
}
core_z_rb <- build_sleeve(core_panel, core_facs)
setnames(core_z_rb, "sleeve_z", "core_z_rb")
def_z_rb  <- build_sleeve(def_panel, def_facs)
setnames(def_z_rb, "sleeve_z", "def_z_rb")
par <- merge(ap[, .(Date, Ticker, score_core_z, score_defense_z, score_eff)], core_z_rb, by=c("Date","Ticker"), all.x=TRUE)
par <- merge(par, def_z_rb, by=c("Date","Ticker"), all.x=TRUE)
par[, score_eff_rb := 0.65*core_z_rb + 0.35*def_z_rb]
pc <- par[!is.na(core_z_rb)&!is.na(score_core_z)]
pd <- par[!is.na(def_z_rb)&!is.na(score_defense_z)]
pe <- par[!is.na(score_eff_rb)&!is.na(score_eff)]
cat(sprintf("\n=== PARITY (rebuilt vs stored) ===\n core_z: cor=%.4f max_abs_err=%.4f n=%d\n def_z : cor=%.4f max_abs_err=%.4f n=%d\n eff   : cor=%.4f max_abs_err=%.4f n=%d\n",
  pc[, cor(core_z_rb, score_core_z)], pc[, max(abs(core_z_rb-score_core_z))], nrow(pc),
  pd[, cor(def_z_rb, score_defense_z)], pd[, max(abs(def_z_rb-score_defense_z))], nrow(pd),
  pe[, cor(score_eff_rb, score_eff)], pe[, max(abs(score_eff_rb-score_eff))], nrow(pe)))
# per-date cross-sectional cor (selection fidelity)
csc <- par[!is.na(score_eff_rb)&!is.na(score_eff), .(c=cor(score_eff_rb, score_eff)), by=Date]
cat(sprintf(" eff per-date cross-sec cor: mean=%.4f min=%.4f\n", mean(csc$c,na.rm=TRUE), min(csc$c,na.rm=TRUE)))

saveRDS(list(ap=ap, scope=scope, dts=dts, benchdt=benchdt, returns_dt=returns_dt,
             core_panel=core_panel, def_panel=def_panel, core_facs=core_facs, def_facs=def_facs,
             parity=list(core_cor=pc[, cor(core_z_rb, score_core_z)], def_cor=pd[, cor(def_z_rb, score_defense_z)],
                         eff_cor=pe[, cor(score_eff_rb, score_eff)], eff_csc_mean=mean(csc$c,na.rm=TRUE))),
        file.path(SA,"inputs.rds"))
cat("\n[saved] inputs.rds\n")
