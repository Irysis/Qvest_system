## WT-D20260606_001 Optimizer — FINALIZE: book-marginal dIR (vs BM, NW), weights.csv schedule, turnover
suppressMessages({library(arrow); library(data.table); library(PerformanceAnalytics); library(xts); library(jsonlite)})
# Newey-West lag-L t-stat for mean of a series (HAC on intercept-only regression)
nw_tstat_mean <- function(x, L=3){
  x <- x[is.finite(x)]; n <- length(x); mu <- mean(x); e <- x - mu
  g0 <- sum(e^2)/n
  v <- g0
  if(L>0) for(l in 1:L){ w <- 1 - l/(L+1); gl <- sum(e[(l+1):n]*e[1:(n-l)])/n; v <- v + 2*w*gl }
  se <- sqrt(v/n)
  mu/se
}
options(warn=1); root <- "G:/Quant_Module_Moltbot"; setwd(root); set.seed(606)
OUT <- "stage_artifacts/WT_D20260606_001"
S <- readRDS(file.path(OUT,"opt_intermediate.rds")); sl <- S$sl; inc <- S$inc; m_r05 <- S$m_r05
OV <- readRDS(file.path(OUT,"overlay_intermediate.rds")); J <- OV$J

# ---- benchmark forward monthly (KOSPI200 TR) from RAW ----
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet")); RAW[,Date:=as.Date(Date)]; RAW[,ym:=format(Date,"%Y-%m")]
bm <- unique(RAW[!is.na(BM_Ret), .(Date,ym,BM_Ret)])
bm_m <- bm[, .(bm_ret=prod(1+BM_Ret)-1), by=ym]; setorder(bm_m, ym)
bm_m[, bm_fwd := shift(bm_ret,1L,type="lead")]   # forward month
J2 <- merge(J, bm_m[,.(ym,bm_fwd)], by="ym"); setorder(J2, Date)
J2 <- J2[is.finite(bm_fwd)]
cat("panel w/ BM:", nrow(J2), "\n")

# book-marginal IR (active vs BM, NW lag-3 t-stat on active series)
ir_nw <- function(book_ret, bm_ret){
  act <- book_ret - bm_ret
  ir <- mean(act)/sd(act)*sqrt(12)
  tt <- nw_tstat_mean(act, L=3)
  list(IR=ir, alpha_ann=mean(act)*12, t_nw=as.numeric(tt))
}

cat("\n=== book-marginal dIR vs BM (NW lag-3) ===\n")
base_ir <- ir_nw(J2$r05_net, J2$bm_fwd)
cat(sprintf(" R05 incumbent:  IR %.3f  alpha_ann %.3f  t_nw %.2f\n", base_ir$IR, base_ir$alpha_ann, base_ir$t_nw))
res <- list()
for(a in c(0.05,0.10,0.15,0.20)){
  book <- (1-a)*J2$r05_net + a*J2$sleeve_net
  m <- ir_nw(book, J2$bm_fwd)
  dIR <- m$IR - base_ir$IR
  res[[as.character(a)]] <- list(a=a, IR=m$IR, dIR=dIR, alpha_ann=m$alpha_ann, t_nw=m$t_nw,
                                 SR=as.numeric(Return.annualized(xts(book,J2$Date),12)/StdDev.annualized(xts(book,J2$Date),12)))
  cat(sprintf(" R05+%.0f%%sleeve: IR %.3f  dIR %+.3f  alpha_ann %.3f  t_nw %.2f  bookSR %.3f\n",
      a*100, m$IR, dIR, m$alpha_ann, m$t_nw, res[[as.character(a)]]$SR))
}

# overlay-applied book (regime de-risk thr0.6 exp0.3) dIR
sig <- pmax(J2$MSM_Crisis_Prob_lag, J2$combined_regime, na.rm=TRUE); sig[is.na(sig)]<-0
expo <- ifelse(sig>=0.6, 0.3, 1.0)
book_ov <- expo*((1-0.15)*J2$r05_net + 0.15*J2$sleeve_net)
# overlay applies to BM too (de-risked book holds cash) -> active = book_ov - expo*bm? No: benchmark stays fully invested.
m_ov <- ir_nw(book_ov, J2$bm_fwd)
cat(sprintf("\n overlay(a0.15,regime de-risk): IR %.3f dIR %+.3f bookSR %.3f MDD %.3f\n",
    m_ov$IR, m_ov$IR-base_ir$IR, as.numeric(Return.annualized(xts(book_ov,J2$Date),12)/StdDev.annualized(xts(book_ov,J2$Date),12)),
    as.numeric(maxDrawdown(xts(book_ov,J2$Date)))))

# ---- TURNOVER round-trip for sleeve (one-way * 2) ----
ew_to_oneway <- mean(sl[["EW"]]$series$turnover_oneway, na.rm=TRUE)
cat(sprintf("\nsleeve EW turnover: one-way/mo %.3f -> annual round-trip %.2f (=oneway*12*2)\n",
            ew_to_oneway, ew_to_oneway*12*2))

# ===================================================================
# WEIGHTS.CSV — monthly schedule. BOOK = (1-a)*R05_holdings + a*sleeve_holdings.
# Optimizer scope here = the residual-mom SLEEVE target weights (R05 holdings are incumbent/frozen book).
# We emit the SLEEVE leg target weights at each sig_date (EW top-20, capped [0,0.20]) PLUS book allocation a and overlay exposure.
# This gives forge a full schedule with as_of_date column (RF-O9 walk-forward).
# ===================================================================
W <- sl[["EW"]]$weights   # Date,Ticker,w (sleeve internal, sums to 1 per date)
A_BOOK <- 0.15            # selected book allocation to sleeve (conservative, vol-aware per RX-3)
# scale sleeve weights by book allocation -> contribution to total book; cap check at book level
W[, book_weight := w * A_BOOK]
# attach overlay exposure per date (from regime signal at that date)
ov <- inc[, .(Date, sig=pmax(MSM_Crisis_Prob_lag, combined_regime, na.rm=TRUE))]
ov[is.na(sig), sig:=0]; ov[, exposure := ifelse(sig>=0.6, 0.3, 1.0)]
W <- merge(W, ov[,.(Date,exposure)], by="Date", all.x=TRUE); W[is.na(exposure), exposure:=1.0]
W[, effective_weight := book_weight * exposure]
setorder(W, Date, -w)
W[, as_of_date := Date]
fwrite(W[, .(as_of_date, Date, Ticker, sleeve_weight=w, book_allocation=A_BOOK, book_weight, overlay_exposure=exposure, effective_book_weight=effective_weight)],
       file.path(OUT,"weights.csv"))

# schedule density
n_sched <- length(unique(W$Date)); n_sig <- length(unique(inc$Date))
cat(sprintf("\nweights.csv: unique_dates %d | alpha sig_dates(269 panel; book-overlap %d) | density vs book %.3f\n",
            n_sched, n_sig, n_sched/269))

# latest target weights (most recent sig_date) for optimization_package target_weights
last_d <- max(W$Date)
tw <- W[Date==last_d]
cat(sprintf("\nlatest sig_date: %s  n_names %d  sum sleeve_w %.4f  max sleeve_w %.4f\n",
            as.character(last_d), nrow(tw), sum(tw$w), max(tw$w)))

saveRDS(list(res=res, base_ir=base_ir, m_ov=m_ov, A_BOOK=A_BOOK, last_d=last_d, tw=tw,
             ew_to_oneway=ew_to_oneway, n_sched=n_sched), file.path(OUT,"finalize_intermediate.rds"))
cat("\n[done finalize -> weights.csv written]\n")
