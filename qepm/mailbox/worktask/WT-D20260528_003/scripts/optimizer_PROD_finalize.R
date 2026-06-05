#==============================================================================
# WT-D20260528_003 D_PROD — Optimizer Finalize
# Select method (net_ir, turnover-feasible) + RF-R1 MKT exposure analysis +
# walk-forward weights.csv (>=111 dates, density mandate) + draft package.
#==============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(quadprog)
})
ROOT <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"; setwd(ROOT)
WT <- "WT-D20260528_003"
ABASE <- "stage_artifacts/WT_D20260528_003"
RBASE <- "stage_artifacts/WT_D20260528_003_risk_PROD"
OUT_MB <- file.path("qepm/mailbox/worktask", WT)
COMMISSION <- 0.0015; WMAX <- 0.20; AS_OF <- as.Date("2023-11-30")

res <- readRDS(file.path(OUT_MB,"optimizer_method_results.rds"))
sched <- as.data.table(read_parquet(file.path(ABASE,"weights_schedule.parquet"))); sched[,Date:=as.Date(Date)]
alpha <- as.data.table(read_parquet(file.path(ABASE,"alpha_scores.parquet"))); alpha[,Date:=as.Date(Date)]
B  <- as.data.table(read_parquet(file.path(RBASE,"B_loadings.parquet"))); setkey(B,Ticker)
sig_dates <- sort(unique(alpha$Date)); N_SIG <- length(sig_dates)
N_SIG_REPORTED <- alpha[, uniqueN(Date)]   # 116

.normalize <- function(w){ w[w<0]<-0; if(sum(w)<=0) w<-rep(1,length(w)); w/sum(w) }
.cap_iter <- function(w, wmax=WMAX){ for(i in 1:200){ w<-.normalize(w); over<-w>wmax+1e-12; if(!any(over))break
  excess<-sum(w[over]-wmax); w[over]<-wmax; under<-!over&w>0; if(!any(under)){w<-w/sum(w);break}
  w[under]<-w[under]+excess*w[under]/sum(w[under]) }; .normalize(pmin(w,wmax)) }

# ── RF-R1: beta-capped low-turnover reweight of Schedule book ────────────────
# min ||w - w_sched||^2 s.t. Σw=1, 0<=w<=wmax, b'w <= beta_cap  (QP, minimal deviation)
beta_capped_reweight <- function(w0, bk, beta_cap){
  n <- length(w0)
  Dmat <- diag(n) + diag(1e-8,n)
  dvec <- w0
  # eq: sum=1 ; ineq: w>=0 ; w<=wmax ; -b'w >= -beta_cap (i.e. b'w<=beta_cap)
  Amat <- cbind(rep(1,n), diag(n), -diag(n), -bk)
  bvec <- c(1, rep(0,n), rep(-WMAX,n), -beta_cap)
  sol <- tryCatch(solve.QP(Dmat,dvec,Amat,bvec,meq=1)$solution, error=function(e) w0)
  .cap_iter(sol)
}

# Build Schedule weights at as_of + beta exposures
sw <- sched[Date==AS_OF]; w0 <- setNames(.normalize(sw$weight), sw$Ticker)
bk <- B[match(names(w0), Ticker), MKT]; bk[is.na(bk)] <- mean(bk,na.rm=TRUE)
beta_before <- sum(w0*bk)

exposures_before <- sapply(c("MKT","SMB","DEF","WML","STR"), function(f){
  v <- B[match(names(w0),Ticker)][[f]]; sum(w0*ifelse(is.na(v),0,v)) })

# Apply beta cap at 1.00 (mild) to the as_of book
w_bc <- beta_capped_reweight(w0, bk, beta_cap=1.00)
beta_after <- sum(w_bc*bk)
turn_bc_oneway <- sum(abs(w_bc - w0))/2     # incremental one-way turnover from cap
exposures_after <- sapply(c("MKT","SMB","DEF","WML","STR"), function(f){
  v <- B[match(names(w0),Ticker)][[f]]; sum(w_bc*ifelse(is.na(v),0,v)) })

cat(sprintf("[RF-R1] as_of book MKT beta: before=%.4f  after(cap1.00)=%.4f  incr_oneway_turn=%.4f\n",
            beta_before, beta_after, turn_bc_oneway))
cat("[RF-R1] exposures before:", paste(sprintf("%s=%.3f",names(exposures_before),exposures_before),collapse=" "),"\n")
cat("[RF-R1] exposures after :", paste(sprintf("%s=%.3f",names(exposures_after),exposures_after),collapse=" "),"\n")

# ── Method selection (net_ir, turnover<=6.0 HARD feasibility) ────────────────
tab <- data.table(method=names(res),
  net_sr=sapply(res,\(x)x$sr_net), net_ir=sapply(res,\(x)x$ir),
  net_ar=sapply(res,\(x)x$net_active_ret), te=sapply(res,\(x)x$te),
  mdd=sapply(res,\(x)x$mdd), to_yr=sapply(res,\(x)x$turnover_yr),
  n_periods=sapply(res,\(x)x$n_periods))
tab[, to_pass := to_yr <= 6.0]
feas <- tab[to_pass==TRUE][order(-net_ir)]
SELECTED <- feas$method[1]    # Schedule_EWbase expected
cat(sprintf("\n[select] selection_objective=net_ir, feasibility=turnover<=6.0\n"))
cat(sprintf("[select] SELECTED = %s (net_ir=%.4f net_sr=%.4f to_yr=%.3f)\n",
            SELECTED, feas$net_ir[1], feas$net_sr[1], feas$to_yr[1]))
cat(sprintf("[select] EW baseline net_sr=%.4f net_ir=%.4f ; selected vs EW dSR=%+.4f dIR=%+.4f\n",
            res$EW$sr_net, res$EW$ir, res[[SELECTED]]$sr_net - res$EW$sr_net, res[[SELECTED]]$ir - res$EW$ir))

# ── Walk-forward weights.csv (selected method holdings, all sig_dates) ────────
sim_sel <- res[[SELECTED]]$sim
W <- copy(sim_sel$holds)                      # Date,Ticker,weight per rebalance (d0)
setnames(W, "Date", "as_of_date")
# normalize per date (safety) + add cap audit
W[, weight := weight/sum(weight), by=as_of_date]
W[, `:=`(method=SELECTED, task_id=WT)]
udates <- W[, uniqueN(as_of_date)]
density_ratio <- udates / N_SIG_REPORTED
cat(sprintf("\n[weights] unique as_of_dates=%d / alpha sig_dates=%d -> density=%.3f (mandate>=0.95)\n",
            udates, N_SIG_REPORTED, density_ratio))
# checks
maxw <- W[, max(weight)]; minw <- W[, min(weight)]
sumw_ok <- W[, .(s=sum(weight)), by=as_of_date][, all(abs(s-1)<1e-6)]
ncnt <- W[, .N, by=as_of_date][, max(N)]
cat(sprintf("[weights] max_w=%.4f min_w=%.4f Σw=1 all dates=%s max_names=%d\n", maxw, minw, sumw_ok, ncnt))

WPATH <- file.path(ABASE, "weights.csv")
fwrite(W[order(as_of_date,-weight), .(as_of_date, Ticker, weight, method, task_id)], WPATH)
cat(sprintf("[weights] written: %s (%d rows)\n", WPATH, nrow(W)))

# ── Selected method full metrics + estimated cost ────────────────────────────
m <- res[[SELECTED]]
est_cost_ann <- (m$turnover_yr/2) * 2 * COMMISSION   # round-trip turnover * one-way cost... = to_yr*COMMISSION
est_cost_ann <- m$turnover_yr * COMMISSION
cat(sprintf("[cost] annual est cost = turnover_yr(%.3f) * 15bps = %.4f (%.2f%%/yr)\n",
            m$turnover_yr, est_cost_ann, est_cost_ann*100))

# binding constraints at as_of for selected (Schedule): cap rarely binds for EW-ish; record
binding <- c()
asof_w <- W[as_of_date==AS_OF, weight]
if(any(asof_w > WMAX-1e-6)) binding <- c(binding, "weight_bound_0.20")
if(beta_before > 1.0) binding <- c(binding, "MKT_beta_structural_floor_long_only")

# save finalize bundle
saveRDS(list(SELECTED=SELECTED, tab=tab, feas=feas, m=m,
             beta_before=beta_before, beta_after=beta_after, turn_bc_oneway=turn_bc_oneway,
             exposures_before=exposures_before, exposures_after=exposures_after,
             density_ratio=density_ratio, udates=udates, N_SIG_REPORTED=N_SIG_REPORTED,
             est_cost_ann=est_cost_ann, maxw=maxw, sumw_ok=sumw_ok, ncnt=ncnt, binding=binding,
             ew=res$EW),
        file.path(OUT_MB,"optimizer_finalize_bundle.rds"))
cat("\n[finalize] bundle saved. Ready for draft package.\n")
