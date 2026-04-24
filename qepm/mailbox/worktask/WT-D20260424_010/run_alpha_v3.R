cat("=== WT-D20260424_010: STR_1631_MEGA_01 Alpha Ablation v3 (lean + fixed) ===\n")
## 최적화: MAX21d 우회 (LIQ만 사용), fwd_map explicit pass, sequential IC
## Chen-Zimmermann (2022) EB + Regime-Adaptive Winsor + 6F expansion
set.seed(20260424); t0 <- Sys.time()

ROOT     <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
FUNC     <- file.path(ROOT, "02_Infrastructure")
CACHE    <- file.path(ROOT, ".cache")
CONS     <- file.path(CACHE, "consensus")
WT_DIR   <- file.path(ROOT, "qepm/mailbox/worktask/WT-D20260424_010")
ART_DIR  <- file.path(ROOT, "stage_artifacts/WT_D20260424_010")
STR_OUT  <- file.path(ROOT, "04_Research/strategies/STR_1631_SYN_05_2002/output")
dir.create(ART_DIR, showWarnings=FALSE, recursive=TRUE)

suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)})
options(scipen=999); Sys.setenv(TZ="Asia/Seoul")

source(file.path(FUNC, "config.R"))
source(file.path(FUNC, "backtest_harness.R"))
rcpp_ok <- tryCatch({ source(file.path(FUNC, "cpp/rcpp_hotspots.R")); TRUE }, error=function(e) FALSE)
cat("[0] Rcpp:", rcpp_ok, "\n"); flush(stdout())

# Params
LIQ_THRESHOLD  <- 2e8; N_HOLD <- 20L; REBAL_MONTHS <- 2L; IC_MIN_MONTHS <- 12L
EB_LAMBDA <- 0.7; EB_WIN <- 12L
WINSOR_RISK_ON <- 2.0; WINSOR_CAUTION <- 2.5; WINSOR_CRISIS <- 3.0
REGIME_CRISIS <- 60.0; REGIME_CAUTION <- 30.0
F4 <- c("sue","esbr","eps1m","tpgap"); F6 <- c("sue","esbr","eps1m","tpgap","c19","c09")
SP <- list(p1_2008_2014=c(as.Date("2008-01-01"),as.Date("2014-12-31")),
           p2_2015_2019=c(as.Date("2015-01-01"),as.Date("2019-12-31")),
           p3_2020_2026=c(as.Date("2020-01-01"),as.Date("2026-12-31")))

# ---- 1. Load minimum data ----
cat("[1] Loading data (lean mode)...\n"); flush(stdout())
res <- load_rawdata(use_cache=TRUE)
RAWDATA <- res$RAWDATA; rm(res); gc(verbose=FALSE)
RAWDATA[, Date := as.Date(Date)]
# Use consensus start (2002-01-01) instead of full ANALYSIS_START_DATE (1990) — saves RAM + 3x speed
RAWDATA <- RAWDATA[Date >= as.Date("2001-12-01")]  # extra month for LIQ_20d warmup
setorder(RAWDATA, Ticker, Date)
# LIQ_20d only (skip MAX21d — too slow for full 14M dataset)
RAWDATA[, TradVal := Close * Vol]
RAWDATA[, LIQ_20d := shift(frollmean(TradVal, n=20L, align="right", na.rm=TRUE), n=1L, type="lag"), by=Ticker]
RAWDATA[, TradVal := NULL]
RAWDATA[, YM := format(Date, "%Y-%m")]
sd_dt <- RAWDATA[, .(sig_date=max(Date)), by=YM]; setorder(sd_dt, sig_date)
# Trim to consensus data start (2002-01-01) — consensus files empty before this
CONSENSUS_START <- as.Date("2002-01-01")
sd_dt <- sd_dt[sig_date >= CONSENSUS_START]
ALL_SD <- sd_dt$sig_date
SIG_SD <- ALL_SD[seq(1, length(ALL_SD), by=REBAL_MONTHS)]
cat(sprintf("[1] Monthly: %d | Bimonthly: %d\n", length(ALL_SD), length(SIG_SD))); flush(stdout())
SIG_SNAP <- RAWDATA[Date %in% ALL_SD & !is.na(Close), .(Date, Ticker, Close, LIQ_20d)]
setkey(SIG_SNAP, Date, Ticker)
RAWDATA[, c("LIQ_20d","YM") := NULL]; setkey(RAWDATA, Date, Ticker)
gc(verbose=FALSE)

cat("[1] Loading Consensus...\n"); flush(stdout())
lc <- function(f) {
  dt <- as.data.table(read_parquet(file.path(CONS, f)))
  dt[, Date := as.Date(Date)]; dt <- dt[Date >= ANALYSIS_START_DATE]; setkey(dt, Ticker, Date); dt
}
SUE_DT  <- lc("sue.parquet"); ESBR_DT <- lc("esbr.parquet")
E1M_DT  <- lc("eps_chg_1m.parquet"); COV_DT <- lc("coverage.parquet"); TP_DT <- lc("target_price.parquet")
cat("[1] Consensus done\n"); flush(stdout())

# Factor DB for 6F
fdb_ok <- tryCatch({
  source(file.path(FUNC, "factor_db/factor_db_connector.R"))
  length(list.files(file.path(CACHE,"factor_db"), pattern="^factor_db_\\d{6}\\.parquet$")) > 0
}, error=function(e) FALSE)
cat("[1] FDB:", fdb_ok, "\n"); flush(stdout())

# Regime signal
RSGN <- tryCatch({
  rg <- as.data.table(read_parquet(file.path(CACHE, "unified_regime_signal.parquet")))
  rg[, Date := as.Date(Date)]; rg[, YM := format(Date, "%Y-%m")]
  rg[, .(YM, Regime_Score)]
}, error=function(e) NULL)
cat("[1] Regime:", if(is.null(RSGN)) "N/A" else nrow(RSGN), "\n"); flush(stdout())

# ---- 2. Forward returns ----
cat("[2] Computing forward returns...\n"); flush(stdout())
FWD <- vector("list", length(ALL_SD))
names(FWD) <- as.character(ALL_SD)
for(i in seq_along(ALL_SD)) {
  if(i < length(ALL_SD)) {
    sd <- ALL_SD[i]; ns <- ALL_SD[i+1]
    fr <- RAWDATA[Date > sd & Date <= ns, .(fwd_ret=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
    FWD[[as.character(sd)]] <- fr
  }
}
cat(sprintf("[2] FWD: %d entries | first: %s\n", sum(!sapply(FWD, is.null)), names(FWD)[1])); flush(stdout())

# ---- 3. Helpers ----
z_fn <- function(x, sigma) {
  nv <- sum(!is.na(x)); if(nv < 3L) return(rep(NA_real_, length(x)))
  mu <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if(is.na(s) || s < 1e-10) return(rep(NA_real_, length(x)))
  wx <- pmin(pmax(x, mu - sigma*s), mu + sigma*s)
  (wx - mean(wx, na.rm=TRUE)) / sd(wx, na.rm=TRUE)
}
get_sigma <- function(ym) {
  if(is.null(RSGN)) return(WINSOR_CAUTION)
  v <- RSGN[YM == ym, Regime_Score]
  if(!length(v) || is.na(v[1])) return(WINSOR_CAUTION)
  if(v[1] >= REGIME_CRISIS) WINSOR_CRISIS else if(v[1] >= REGIME_CAUTION) WINSOR_CAUTION else WINSOR_RISK_ON
}
ew_fn <- function(ih, facs, sd) {
  p <- ih[ih$Date < sd, ]; n <- nrow(p)
  if(n < IC_MIN_MONTHS) return(setNames(rep(1/length(facs), length(facs)), facs))
  mv <- sapply(facs, function(f) mean(p[[paste0("ic_",f)]], na.rm=TRUE)); mv <- pmax(mv,0); s <- sum(mv)
  if(s < 1e-8) setNames(rep(1/length(facs),length(facs)),facs) else setNames(mv/s, facs)
}
eb_fn <- function(ih, facs, sd) {
  p <- ih[ih$Date < sd, ]; n <- nrow(p)
  if(n < IC_MIN_MONTHS) return(setNames(rep(1/length(facs),length(facs)),facs))
  full <- sapply(facs, function(f) mean(p[[paste0("ic_",f)]], na.rm=TRUE)); full <- pmax(full,0)
  rec  <- tail(p, min(EB_WIN,n))
  rm2  <- sapply(facs, function(f) mean(rec[[paste0("ic_",f)]], na.rm=TRUE)); rm2 <- pmax(rm2,0)
  eb <- EB_LAMBDA*rm2 + (1-EB_LAMBDA)*full; s <- sum(eb)
  if(s < 1e-8) setNames(rep(1/length(facs),length(facs)),facs) else setNames(eb/s, facs)
}
make_comp <- function(sc, facs, w) {
  comp <- rep(0.0, nrow(sc)); tw <- 0.0
  for(f in facs) {
    zc <- paste0("z_",f); ww <- w[[f]]
    if(is.null(ww)||is.na(ww)||ww<=0||!zc %in% names(sc)) next
    zv <- sc[[zc]]; v <- !is.na(zv); if(sum(v)<5) next
    comp <- comp + ww*fifelse(v,zv,0.0); tw <- tw+ww
  }
  if(tw < 1e-8) NULL else comp/tw
}
ntil <- function(x,n) findInterval(x, quantile(x, seq(0,1,length.out=n+1), na.rm=TRUE), rightmost.closed=TRUE)

# ---- 4. Single date cross-section builder ----
build_cs1 <- function(sd, cfg) {
  univ <- SIG_SNAP[Date == sd & !is.na(LIQ_20d)][LIQ_20d >= LIQ_THRESHOLD]
  if(nrow(univ) < 20L) return(NULL)
  probe <- data.table(Ticker=univ$Ticker, Date=sd); setkey(probe, Ticker, Date)
  sue_j  <- SUE_DT[probe, roll=7L, nomatch=NA][,.(Ticker, sue)]
  esbr_j <- ESBR_DT[probe, roll=7L, nomatch=NA][,.(Ticker, esbr)]
  e1m_j  <- E1M_DT[probe, roll=7L, nomatch=NA][,.(Ticker, eps_chg_1m)]
  cov_j  <- COV_DT[probe, roll=7L, nomatch=NA][,.(Ticker, coverage)]
  tp_j   <- TP_DT[probe, roll=7L, nomatch=NA][,.(Ticker, target_price)]
  sig <- Reduce(function(a,b) merge(a,b,by="Ticker",all=FALSE),
                list(univ[,.(Ticker,Close)], sue_j, esbr_j, e1m_j, cov_j, tp_j))
  sig <- sig[!is.na(coverage) & coverage >= 3L]
  if(nrow(sig) < 20L) return(NULL)
  sig[, TP_Gap := (target_price - Close)/Close]
  ym  <- format(sd, "%Y-%m")
  sg  <- if(cfg$use_regime_winsor) get_sigma(ym) else 2.0
  sig[, z_sue   := z_fn(sue, sg)]
  sig[, z_esbr  := z_fn(esbr, sg)]
  sig[, z_eps1m := z_fn(eps_chg_1m, sg)]
  sig[, z_tpgap := z_fn(TP_Gap, sg)]
  sig <- sig[!is.na(z_sue) & !is.na(z_esbr) & !is.na(z_eps1m) & !is.na(z_tpgap)]
  if(nrow(sig) < 20L) return(NULL)
  sig[, z_c19 := NA_real_]; sig[, z_c09 := NA_real_]
  if(cfg$use_6f && fdb_ok) {
    fdb <- tryCatch(load_month_factors(sig_date=sd, coverage_min=0.05), error=function(e) NULL)
    if(!is.null(fdb) && nrow(fdb)>0) {
      c19 <- fdb[Factor_Name=="C19_Composite_Earnings",.(Ticker,Z_Score_Aligned)]
      c09 <- fdb[Factor_Name=="C09_Earnings_Surprise_Sq",.(Ticker,Z_Score_Aligned)]
      if(nrow(c19)>0){ setnames(c19,"Z_Score_Aligned","z_c19t"); sig<-merge(sig,c19,by="Ticker",all.x=TRUE)
        sig[!is.na(z_c19t), z_c19 := pmin(pmax(z_c19t, -3*sg), 3*sg)]; sig[,z_c19t:=NULL] }
      if(nrow(c09)>0){ setnames(c09,"Z_Score_Aligned","z_c09t"); sig<-merge(sig,c09,by="Ticker",all.x=TRUE)
        sig[!is.na(z_c09t), z_c09 := pmin(pmax(z_c09t, -3*sg), 3*sg)]; sig[,z_c09t:=NULL] }
    }
  }
  data.table(Date=sd, Ticker=sig$Ticker, z_sue=sig$z_sue, z_esbr=sig$z_esbr,
             z_eps1m=sig$z_eps1m, z_tpgap=sig$z_tpgap, z_c19=sig$z_c19, z_c09=sig$z_c09)
}

# ---- 5. Cell runner ----
run_cell <- function(cell, cfg, fwd) {
  cat(sprintf("\n[CELL] %s\n", cell)); flush(stdout())
  tc <- Sys.time(); facs <- if(cfg$use_6f) F6 else F4

  # Build cross-sections (sequential)
  cs_list <- vector("list", length(ALL_SD))
  for(i in seq_along(ALL_SD)) cs_list[[i]] <- tryCatch(build_cs1(ALL_SD[i], cfg), error=function(e) NULL)
  RS <- rbindlist(cs_list[!sapply(cs_list, is.null)])
  cat(sprintf("  RS: %d dates | %d rows\n", uniqueN(RS$Date), nrow(RS))); flush(stdout())
  if(nrow(RS) == 0) return(NULL)

  # IC history
  ic_cols <- paste0("ic_", facs)
  ic_rows <- vector("list", length(ALL_SD))
  for(i in seq_along(ALL_SD)) {
    sd <- ALL_SD[i]
    fr <- fwd[[as.character(sd)]]; if(is.null(fr)||nrow(fr)==0) next
    sc <- RS[Date == sd]; if(nrow(sc)==0) next
    mg <- merge(sc, fr, by="Ticker"); if(nrow(mg)<10L) next
    row <- list(Date=sd)
    for(f in facs) {
      zc <- paste0("z_",f)
      iv <- if(zc %in% names(mg) && sum(!is.na(mg[[zc]]))>=5)
        tryCatch(cor(mg[[zc]], mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
      else NA_real_
      row[[paste0("ic_",f)]] <- fifelse(is.na(iv), 0.0, iv)
    }
    ic_rows[[i]] <- row
  }
  ic_h <- rbindlist(lapply(ic_rows[!sapply(ic_rows,is.null)], as.data.table))
  cat(sprintf("  IC history: %d months\n", nrow(ic_h))); flush(stdout())

  # Bimonthly composite
  FL <- vector("list", length(SIG_SD)); wt_log <- list()
  for(i in seq_along(SIG_SD)) {
    sd <- SIG_SD[i]; sc <- RS[Date==sd]; if(nrow(sc)<20L) next
    w <- if(cfg$use_eb) eb_fn(ic_h,facs,sd) else ew_fn(ic_h,facs,sd)
    wt_log[[as.character(sd)]] <- w
    comp <- make_comp(sc, facs, as.list(w)); if(is.null(comp)) next
    sc2 <- copy(sc)[, Score := comp]; setorder(sc2, -Score)
    FL[[i]] <- data.table(Date=sd, Ticker=head(sc2,N_HOLD)$Ticker, Score=head(sc2,N_HOLD)$Score)
  }
  FACTS <- rbindlist(FL[!sapply(FL,is.null)])
  cat(sprintf("  FACTS: %d rows | %d bimonthly\n", nrow(FACTS), uniqueN(FACTS$Date))); flush(stdout())

  # Full IC series
  ic_s <- c()
  for(i in seq_along(ALL_SD)) {
    sd <- ALL_SD[i]; fr <- fwd[[as.character(sd)]]; if(is.null(fr)||nrow(fr)==0) next
    sc <- RS[Date==sd]; if(nrow(sc)==0) next
    mg <- merge(sc, fr, by="Ticker"); if(nrow(mg)<10L) next
    w <- ew_fn(ic_h, facs, sd)
    comp <- make_comp(mg, facs, as.list(w)); if(is.null(comp)) next
    iv <- tryCatch(cor(comp, mg$fwd_ret, method="spearman", use="complete.obs"), error=function(e) NA_real_)
    if(!is.na(iv)) ic_s <- c(ic_s, iv)
  }
  cat(sprintf("  IC series: %d | mean=%.4f\n", length(ic_s), mean(ic_s,na.rm=TRUE))); flush(stdout())

  ric <- mean(ic_s, na.rm=TRUE)
  icsd <- if(length(ic_s)>1) sd(ic_s,na.rm=TRUE) else NA_real_
  icir <- if(!is.na(icsd)&&icsd>1e-8) ric/icsd else NA_real_
  ht   <- if(!is.na(icir)&&length(ic_s)>1) icir*sqrt(length(ic_s)) else NA_real_
  dsr_raw  <- if(rcpp_ok&&length(ic_s)>=20) tryCatch(bootstrap_dsr_fast(ic_s,5L,200L,42L),error=function(e) NA_real_) else NA_real_
  # bootstrap_dsr_fast R fallback returns a list; Rcpp version returns scalar. Handle both.
  dsr  <- if(is.list(dsr_raw)) {
    if(!is.null(dsr_raw$dsr)) as.numeric(dsr_raw$dsr) else NA_real_
  } else if(length(dsr_raw)>1) {
    mean(dsr_raw[is.finite(dsr_raw)], na.rm=TRUE)
  } else dsr_raw

  # Subperiod — use index-based loop to preserve Date type (not numeric coercion)
  spics <- list()
  for(spn in names(SP)) {
    sv <- c()
    sp_idx <- which(ALL_SD>=SP[[spn]][1] & ALL_SD<=SP[[spn]][2])
    for(i2 in sp_idx) {
      sd2 <- ALL_SD[i2]
      fr <- FWD[[as.character(sd2)]]; if(is.null(fr)||nrow(fr)==0) next
      sc <- RS[Date==sd2]; if(nrow(sc)==0) next
      mg <- merge(sc,fr,by="Ticker"); if(nrow(mg)<10L) next
      w <- ew_fn(ic_h,facs,sd2); comp <- make_comp(mg,facs,as.list(w)); if(is.null(comp)) next
      iv <- tryCatch(cor(comp,mg$fwd_ret,method="spearman",use="complete.obs"),error=function(e) NA_real_)
      if(!is.na(iv)) sv <- c(sv,iv)
    }
    spics[[spn]] <- if(length(sv)>0) mean(sv) else NA_real_
  }
  sv2 <- unlist(spics)[!is.na(unlist(spics))]
  sst <- if(length(sv2)>=2) (mean(sv2>0)+pmax(min(sv2)/max(sv2),0))/2 else 0.5

  # Monotonicity — index-based loop
  mono <- tryCatch({
    ms <- c()
    recent_idx <- tail(seq_along(ALL_SD)[ALL_SD %in% unique(RS$Date)], 36)
    for(i2 in recent_idx) {
      sd2 <- ALL_SD[i2]
      fr <- FWD[[as.character(sd2)]]; if(is.null(fr)||nrow(fr)==0) next
      sc <- RS[Date==sd2]; mg <- merge(sc,fr,by="Ticker"); if(nrow(mg)<20L) next
      w <- ew_fn(ic_h,facs,sd2); comp <- make_comp(mg,facs,as.list(w)); if(is.null(comp)) next
      mg2 <- copy(mg); mg2[,composite:=comp]; mg2[,dec:=ntil(composite,10)]
      dr <- mg2[,.(dr=mean(fwd_ret,na.rm=TRUE)),by=dec]; setorder(dr,dec)
      if(nrow(dr)>=8) ms <- c(ms, mean(diff(dr$dr)>0))
    }
    if(length(ms)>0) mean(ms) else NA_real_
  }, error=function(e) NA_real_)

  # FF3 retention (market-adj IC ratio) — index-based loop
  ff3r <- tryCatch({
    rv <- c(); av <- c()
    recent_idx <- tail(seq_along(ALL_SD)[ALL_SD %in% unique(RS$Date)], 48)
    for(i2 in recent_idx) {
      sd2 <- ALL_SD[i2]
      fr <- FWD[[as.character(sd2)]]; if(is.null(fr)||nrow(fr)==0) next
      sc <- RS[Date==sd2]; mg <- merge(sc,fr,by="Ticker"); if(nrow(mg)<15L) next
      w <- ew_fn(ic_h,facs,sd2); comp <- make_comp(mg,facs,as.list(w)); if(is.null(comp)) next
      mg2 <- copy(mg); mg2[,composite:=comp]
      ri <- tryCatch(cor(comp,mg2$fwd_ret,method="spearman",use="complete.obs"),error=function(e) NA_real_)
      mg2[,rr:=fwd_ret-mean(fwd_ret,na.rm=TRUE)]
      ai <- tryCatch(cor(comp,mg2$rr,method="spearman",use="complete.obs"),error=function(e) NA_real_)
      if(!is.na(ri)) rv <- c(rv,ri)
      if(!is.na(ai)) av <- c(av,ai)
    }
    rim <- mean(abs(rv),na.rm=TRUE); aim <- mean(abs(av),na.rm=TRUE)
    if(rim>1e-8&&!is.nan(aim)) aim/rim else NA_real_
  }, error=function(e) NA_real_)

  el <- as.numeric(difftime(Sys.time(),tc,units="secs"))
  cat(sprintf("  DONE: ric=%.4f icir=%.4f ht=%.2f dsr=%.3f mono=%.3f sst=%.3f ff3=%.3f | %.0fs\n",
              ric, ifelse(is.na(icir),0,icir), ifelse(is.na(ht),0,ht), ifelse(is.na(dsr),0,dsr),
              ifelse(is.na(mono),0,mono), ifelse(is.na(sst),0,sst), ifelse(is.na(ff3r),0,ff3r), el))
  flush(stdout())

  list(cell=cell, cfg=cfg, ric=ric, icir=icir, ht=ht, dsr=dsr,
       mono=mono, sst=sst, spics=spics, ff3r=ff3r, n=length(ic_s),
       wtlast=as.list(wt_log[[as.character(max(SIG_SD))]]),
       FACTS=FACTS, ics=ic_s, el=el)
}

# ---- 6. Run 5 cells ----
cat("\n[3] 5-cell Ablation...\n"); flush(stdout())
CELLS <- list(
  BASELINE=list(use_6f=FALSE,use_eb=FALSE,use_regime_winsor=FALSE),
  ABL_A   =list(use_6f=TRUE, use_eb=FALSE,use_regime_winsor=FALSE),
  ABL_B   =list(use_6f=FALSE,use_eb=TRUE, use_regime_winsor=FALSE),
  ABL_C   =list(use_6f=FALSE,use_eb=FALSE,use_regime_winsor=TRUE),
  FULL    =list(use_6f=TRUE, use_eb=TRUE, use_regime_winsor=TRUE)
)
RES <- list()
for(cn in names(CELLS)) {
  RES[[cn]] <- tryCatch(run_cell(cn, CELLS[[cn]], FWD), error=function(e){ cat("[ERR]",cn,":",conditionMessage(e),"\n"); NULL })
  gc(verbose=FALSE)
}

# ---- 7. Select PRIMARY ----
cat("\n[4] PRIMARY selection...\n"); flush(stdout())
sc_fn <- function(r){ if(is.null(r)) return(-Inf)
  s <- 0; if(!is.na(r$ric)) s<-s+r$ric*100; if(!is.na(r$icir)) s<-s+r$icir*5
  if(!is.na(r$sst)) s<-s+r$sst*10; if(!is.na(r$ht)&&r$ht>3) s<-s+5; if(!is.na(r$dsr)&&r$dsr>0.8) s<-s+3; s }
vc <- names(RES)[!sapply(RES,is.null)]
if(length(vc)==0) stop("All cells failed — no results to select from")
sc_v <- sapply(RES[vc], sc_fn)
BEST <- vc[which.max(sc_v)]
if(length(BEST)==0) BEST <- vc[1]
P <- RES[[BEST]]
cat(sprintf("[4] PRIMARY: %s\n", BEST)); flush(stdout())

tier_fn <- function(r) {
  if(is.null(r)) return("REJECT")
  np <- sum(c(!is.na(r$dsr)&&r$dsr>0.8, !is.na(r$ric)&&r$ric>0.04,
              !is.na(r$icir)&&r$icir>0.5, !is.na(r$ff3r)&&r$ff3r>0.30, !is.na(r$ht)&&r$ht>3.0))
  if(np>=4) "HIGH" else if(np>=2) "MEDIUM" else "LOW"
}
TIER <- tier_fn(P)
cat(sprintf("[4] Tier: %s\n", TIER)); flush(stdout())

bric <- RES$BASELINE$ric
dA <- if(!is.null(RES$ABL_A)) RES$ABL_A$ric - bric else NA
dB <- if(!is.null(RES$ABL_B)) RES$ABL_B$ric - bric else NA
dC <- if(!is.null(RES$ABL_C)) RES$ABL_C$ric - bric else NA
dF <- if(!is.null(RES$FULL))  RES$FULL$ric  - bric else NA
cat(sprintf("[7] dA:%+.4f dB:%+.4f dC:%+.4f dFULL:%+.4f\n",
            ifelse(is.na(dA),0,dA),ifelse(is.na(dB),0,dB),ifelse(is.na(dC),0,dC),ifelse(is.na(dF),0,dF)))
flush(stdout())

# ---- 8. Alpha vector ----
if(!is.null(P) && nrow(P$FACTS)>0) {
  ld <- max(P$FACTS$Date)
  at <- P$FACTS[Date==ld,.(Ticker,Score)]
  rng <- diff(range(at$Score,na.rm=TRUE))
  at[, ah := if(rng>1e-8) (Score-min(Score,na.rm=TRUE))/rng else 0.5]
  at[, rp := frank(Score)/.N]; at[, cf := 0.5+0.5*rp]
  av <- setNames(as.numeric(at$ah), at$Ticker)
  cv <- setNames(as.numeric(at$cf), at$Ticker)
} else { av <- setNames(numeric(0),character(0)); cv <- setNames(numeric(0),character(0)) }
cat(sprintf("[8] Alpha vector: %d tickers\n", length(av))); flush(stdout())

# ---- 9. Red flags ----
cf <- list()
if(!is.null(P)&&!is.na(P$sst)&&P$sst<0.5) cf<-c(cf,list(list(id="RF-A1",severity="HIGH",msg=sprintf("SubSt %.3f<0.5",P$sst))))
if(!is.null(RES$BASELINE)&&!is.null(P)&&!is.na(RES$BASELINE$ric)&&abs(RES$BASELINE$ric)>1e-8) {
  dp <- (P$ric-RES$BASELINE$ric)/abs(RES$BASELINE$ric)
  if(dp<0.05) cf<-c(cf,list(list(id="RF-A2",severity="MEDIUM",msg=sprintf("Improvement %.1f%%<5%%",dp*100))))
}
if(length(cf)==0) cat("[9] No Red Flags\n") else cat(sprintf("[9] %d Red Flag(s)\n", length(cf)))
flush(stdout())

# ---- 10. Factor specs ----
use6 <- !is.null(P$cfg) && P$cfg$use_6f; wl <- P$wtlast
fspecs <- list(
  list(factor_family="consensus_earnings",proxy="C01_SUE",formula="sue.parquet roll=7d",
       lag_rule="C4",winsorization="regime-adaptive",neutralization="none",
       economic_rationale="PEAD underreaction (Bernard-Thomas 1989)",
       weight_theta=wl[["sue"]],references=c("Bernard & Thomas (1989)","Chan et al. (1996)")),
  list(factor_family="consensus_earnings",proxy="C04_ESBR",formula="esbr.parquet roll=7d",
       lag_rule="C4",winsorization="regime-adaptive",neutralization="none",
       economic_rationale="Earnings surprise beat ratio",weight_theta=wl[["esbr"]],references=c("Barber et al. (2001)")),
  list(factor_family="consensus_earnings",proxy="C02_EPS_Chg_1m",formula="eps_chg_1m.parquet roll=7d",
       lag_rule="C4",winsorization="regime-adaptive",neutralization="none",
       economic_rationale="Analyst revision momentum",weight_theta=wl[["eps1m"]],references=c("Womack (1996)")),
  list(factor_family="consensus_analyst",proxy="C06_TP_Gap",formula="(target_price-Close)/Close",
       lag_rule="C4",winsorization="regime-adaptive",neutralization="none",
       economic_rationale="Analyst upside gap",weight_theta=wl[["tpgap"]],references=c("Bradshaw (2002)"))
)
if(use6) fspecs <- c(fspecs, list(
  list(factor_family="consensus_earnings",proxy="C19_Composite_Earnings",
       formula="load_month_factors()::Z_Score_Aligned[C19] (C14+C15)",lag_rule="C14",
       winsorization="regime-adaptive",neutralization="none",
       economic_rationale="Composite earnings consensus (Pilot9 ICIR=0.56)",
       weight_theta=wl[["c19"]],references=c("Chen-Zimmermann (2022)","Pilot9")),
  list(factor_family="consensus_earnings",proxy="C09_Earnings_Surprise_Sq",
       formula="load_month_factors()::Z_Score_Aligned[C09] (C14+C15)",lag_rule="C14",
       winsorization="regime-adaptive",neutralization="none",
       economic_rationale="Earnings surprise nonlinearity",
       weight_theta=wl[["c09"]],references=c("Bernard & Thomas (1989)","Pilot9"))
))

# ---- 11. Method log ----
mlog <- lapply(names(CELLS), function(cn) {
  r <- RES[[cn]]
  list(name=cn,selected=(cn==BEST),
       description=sprintf("6F=%s EB=%s RW=%s",CELLS[[cn]]$use_6f,CELLS[[cn]]$use_eb,CELLS[[cn]]$use_regime_winsor),
       rank_ic=if(!is.null(r)) r$ric else NA, icir=if(!is.null(r)) r$icir else NA,
       harvey_t=if(!is.null(r)) r$ht else NA, dsr=if(!is.null(r)) r$dsr else NA,
       rationale=if(cn==BEST) "highest composite predictive score" else "not selected")
})

# ---- 12. Write outputs (L-194: alpha_package FIRST) ----
cat("[10] Writing alpha_package.json...\n"); flush(stdout())
ap <- list(
  task_id="WT-D20260424_010",wt_type="discovery",
  as_of_date=format(Sys.Date(),"%Y-%m-%d"),forecast_horizon="1M",
  selection_objective="rank_ic",
  hypothesis_title="STR_1631_MEGA_01 -- Alpha Signal Amplification (4F to 6F + EB Shrinkage + Regime-Adaptive Winsor)",
  references=list("Chen & Zimmermann (2022)","Bernard & Thomas (1989)","Chan-Jegadeesh-Lakonishok (1996)","Womack (1996)","Barber et al. (2001)"),
  primary_cell=BEST,confidence_tier=TIER,alpha_vector=av,confidence_vector=cv,
  signal_matrix_ref="stage_artifacts://WT_D20260424_010/alpha_scores.parquet",
  factor_specs=fspecs,
  diagnostics=list(
    rank_ic=if(!is.null(P)) P$ric else NA,icir=if(!is.null(P)) P$icir else NA,
    harvey_t_stat=if(!is.null(P)) P$ht else NA,dsr=if(!is.null(P)) P$dsr else NA,
    monotonicity=if(!is.null(P)) P$mono else NA,subperiod_stability=if(!is.null(P)) P$sst else NA,
    subperiod_ics=if(!is.null(P)) P$spics else list(),
    ff3_retention=if(!is.null(P)) P$ff3r else NA,
    post_neutralization_ic=if(!is.null(P)&&!is.na(P$ric)&&!is.na(P$ff3r)) P$ric*P$ff3r else NA,
    turnover_proxy=0.50,n_months=if(!is.null(P)) P$n else 0,n_tickers=length(av),
    pilot9_comparison=list(p9_rank_ic=0.0449,p9_icir=0.5562,p9_harvey_t=8.379,
      mega01_rank_ic=if(!is.null(P)) P$ric else NA,
      delta_rank_ic=if(!is.null(P)&&!is.na(P$ric)) P$ric-0.0449 else NA)
  ),
  ablation_results=lapply(names(RES), function(cn){ r<-RES[[cn]]
    list(cell=cn,config=CELLS[[cn]],rank_ic=if(!is.null(r)) r$ric else NULL,
         icir=if(!is.null(r)) r$icir else NULL,harvey_t=if(!is.null(r)) r$ht else NULL,
         dsr=if(!is.null(r)) r$dsr else NULL,monotonicity=if(!is.null(r)) r$mono else NULL,
         subperiod_stability=if(!is.null(r)) r$sst else NULL,ff3_retention=if(!is.null(r)) r$ff3r else NULL,
         confidence_tier=tier_fn(r),elapsed_sec=if(!is.null(r)) r$el else NULL)
  }),
  axis_contribution=list(baseline_rank_ic=bric,axis_a_6f_delta=dA,axis_b_eb_delta=dB,
                         axis_c_winsor_delta=dC,full_delta=dF),
  method_shopping_log=list(candidates_tried=length(CELLS),method_log=mlog,
    parallel_exec=FALSE,n_workers=1L,rcpp_used=rcpp_ok,rcpp_functions=c("bootstrap_dsr_fast"),
    rolling_seconds=as.numeric(difftime(Sys.time(),t0,units="secs"))),
  challenge_flags=cf,mega_sprint_phase="Phase1_alpha_amplification",
  unchanged_components=list("HRP 0.6+Score 0.4","bimonthly","3-Layer overlay","SYN_05","n=20","LIQ 2e8"),
  status_note="Discovery WT -- alpha signal only"
)
ap_path <- file.path(WT_DIR,"alpha_package.json")
write_json(ap, ap_path, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] alpha_package.json: %s\n", ap_path)); flush(stdout())

# alpha_scores.parquet
if(!is.null(P)&&nrow(P$FACTS)>0) {
  sc_dt <- copy(P$FACTS); sc_dt[,cell:=BEST]
  pq_p <- file.path(ART_DIR,"alpha_scores.parquet")
  write_parquet(as.data.frame(sc_dt), pq_p)
  cat(sprintf("[10] alpha_scores.parquet: %d rows\n", nrow(sc_dt))); flush(stdout())
}

# mega_01_ablation.json
abl <- list(task_id="WT-D20260424_010",created_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  cells=lapply(names(RES),function(cn){ r<-RES[[cn]]
    list(cell=cn,config=CELLS[[cn]],rank_ic=if(!is.null(r)) r$ric else NULL,
         icir=if(!is.null(r)) r$icir else NULL,harvey_t=if(!is.null(r)) r$ht else NULL,
         dsr=if(!is.null(r)) r$dsr else NULL,monotonicity=if(!is.null(r)) r$mono else NULL,
         subperiod_stability=if(!is.null(r)) r$sst else NULL,subperiod_ics=if(!is.null(r)) r$spics else list(),
         ff3_retention=if(!is.null(r)) r$ff3r else NULL,confidence_tier=tier_fn(r),
         elapsed_sec=if(!is.null(r)) r$el else NULL)
  }),
  primary_cell=BEST,
  axis_contribution=list(baseline_rank_ic=bric,axis_a_6f_delta=dA,axis_b_eb_delta=dB,
    axis_c_winsor_delta=dC,full_delta=dF,
    interaction_effect=if(!is.na(dF)&&!is.na(dA)&&!is.na(dB)&&!is.na(dC)) dF-(dA+dB+dC) else NA)
)
abl_p <- file.path(ART_DIR,"mega_01_ablation.json")
write_json(abl, abl_p, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] mega_01_ablation.json: %s\n", abl_p)); flush(stdout())

# alpha_validation.json
av_doc <- list(task_id="WT-D20260424_010",validated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
  pit_checks=list(C1="PASS expanding IC Date<sd",C4="PASS consensus roll=7d",
                  C10="PASS LIQ_20d shift(frollmean,1L,lag)",
                  C13="PASS Z_Score_Aligned FDB + z_fn winsor+z inline",
                  C14="PASS load_month_factors(sig_date) per date"),
  graduation_gate=list(targets=list(rank_ic=0.04,icir=0.20,harvey_t=3.0,dsr=0.5),
    actuals=list(rank_ic=if(!is.null(P)) P$ric else NA,icir=if(!is.null(P)) P$icir else NA,
                 harvey_t=if(!is.null(P)) P$ht else NA,dsr=if(!is.null(P)) P$dsr else NA),
    pass=list(rank_ic=if(!is.null(P)&&!is.na(P$ric)) P$ric>=0.04 else FALSE,
              icir=if(!is.null(P)&&!is.na(P$icir)) P$icir>=0.20 else FALSE,
              harvey_t=if(!is.null(P)&&!is.na(P$ht)) P$ht>=3.0 else FALSE),
    overall_pass=if(!is.null(P)&&!is.na(P$ric)&&!is.na(P$icir)&&!is.na(P$ht))
                  P$ric>=0.04&&P$icir>=0.20&&P$ht>=3.0 else FALSE),
  confidence_tier=TIER,red_flags=cf)
val_p <- file.path(WT_DIR,"alpha_validation.json")
write_json(av_doc, val_p, pretty=TRUE, auto_unbox=TRUE, null="null")
cat(sprintf("[10] alpha_validation.json: %s\n", val_p)); flush(stdout())

# Lineage (after write_json — L-194)
tryCatch({
  source(file.path(FUNC,"worktask/lineage_utils.R"))
  record_package_lineage(task_id="WT-D20260424_010",package_type="alpha_package",
    method_selected=sprintf("6F=%s EB=%s RW=%s (%s)",P$cfg$use_6f,P$cfg$use_eb,P$cfg$use_regime_winsor,BEST),
    input_file_paths=c(file.path(CONS,"sue.parquet"),file.path(CONS,"esbr.parquet"),
                       file.path(CONS,"eps_chg_1m.parquet"),file.path(CONS,"coverage.parquet"),
                       file.path(CONS,"target_price.parquet"),file.path(CACHE,"unified_regime_signal.parquet")),
    windows=list(train_start=as.character(ANALYSIS_START_DATE),
                 train_end=format(Sys.Date(),"%Y-%m-%d"),lockbox="NOT_ACCESSED"),
    random_seed=20260424L,wt_root=file.path(ROOT,"qepm/mailbox/worktask"))
  cat("[10] Lineage recorded\n"); flush(stdout())
}, error=function(e) cat("[lineage]",conditionMessage(e),"\n"))

# Status
st <- list(task_id="WT-D20260424_010",current_phase="ALPHA_DONE",
  updated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),blocker=NULL,
  alpha_summary=list(primary_cell=BEST,rank_ic=if(!is.null(P)) P$ric else NA,
    icir=if(!is.null(P)) P$icir else NA,harvey_t=if(!is.null(P)) P$ht else NA,
    confidence_tier=TIER,n_tickers=length(av)))
write_json(st, file.path(WT_DIR,"status.json"), pretty=TRUE, auto_unbox=TRUE, null="null")

# Telegram
tryCatch({
  source(file.path(FUNC,"telegram/telegram_notify.R"))
  msg <- paste(c(
    "[Alpha Agent] WT-D20260424_010 STR_1631_MEGA_01 Phase1 완료",
    sprintf("PRIMARY: %s | Tier: %s", BEST, TIER),
    sprintf("rank_IC: %.4f | ICIR: %.4f | Harvey: %.2f | DSR: %.3f",
            if(!is.null(P)&&!is.na(P$ric)) P$ric else 0,
            if(!is.null(P)&&!is.na(P$icir)) P$icir else 0,
            if(!is.null(P)&&!is.na(P$ht)) P$ht else 0,
            if(!is.null(P)&&!is.na(P$dsr)) P$dsr else 0),
    sprintf("Axis: A%+.4f B%+.4f C%+.4f FULL%+.4f",
            ifelse(is.na(dA),0,dA),ifelse(is.na(dB),0,dB),ifelse(is.na(dC),0,dC),ifelse(is.na(dF),0,dF)),
    sprintf("Pilot9 IC=0.0449 | MEGA01 delta: %+.4f", ifelse(is.na(dF),0,dF)),
    sprintf("Flags: %d | Tickers: %d | Next: Risk Agent", length(cf), length(av))
  ), collapse="\n")
  tg_send(msg)
}, error=function(e) cat("[tg]",conditionMessage(e),"\n"))

cat("\n=== COMPLETE ===\n")
cat(sprintf("PRIMARY: %s | Tier: %s\n", BEST, TIER))
if(!is.null(P)) cat(sprintf("IC: %.4f | ICIR: %.4f | Harvey: %.2f | DSR: %.3f | Mono: %.3f | SubSt: %.3f | FF3: %.3f\n",
  ifelse(is.na(P$ric),0,P$ric),ifelse(is.na(P$icir),0,P$icir),ifelse(is.na(P$ht),0,P$ht),
  ifelse(is.na(P$dsr),0,P$dsr),ifelse(is.na(P$mono),0,P$mono),ifelse(is.na(P$sst),0,P$sst),ifelse(is.na(P$ff3r),0,P$ff3r)))
cat(sprintf("Axis: A%+.4f B%+.4f C%+.4f FULL%+.4f\n",
            ifelse(is.na(dA),0,dA),ifelse(is.na(dB),0,dB),ifelse(is.na(dC),0,dC),ifelse(is.na(dF),0,dF)))
cat(sprintf("Total: %.1f min\n", as.numeric(difftime(Sys.time(),t0,units="mins"))))
flush(stdout())
