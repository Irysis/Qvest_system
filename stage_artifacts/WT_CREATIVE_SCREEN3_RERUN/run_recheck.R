#!/usr/bin/env Rscript
# ============================================================================
# WT_CREATIVE_SCREEN3_RERUN  (the "idea" = sector_pair_meanrev rigor recheck)
#
# (A) screen2 IN-SAMPLE multiplicity correction on the EXISTING 325-pair table:
#     BH-FDR(q=0.10) + Bonferroni + DSR(expected-max-t under null, n_trials=325)
#     vs chance. Uses the materialized nw_t column (NOT 'nw_tstat').
# (C) screen2 CLEAN walk-forward OOS: reconstruct the SAME sector-index panel
#     from .cache/rawdata.parquet (identical methodology to screen2 run_screen.R),
#     select pairs ONLY on pre-2019 data (z-rule + NW t>2 + net>0), FREEZE them,
#     then measure reversion on 2019-01-01..lockbox(2023-12-22) test window.
#     OOS hold fraction vs chance.
#
# This is the original screen2 idea (sector pair mean-reversion). screen3's
# Sector-RV is the same family (sector relative-value reversion) -> this rerun
# subsumes both: PART A/C answer "is the 18/325 GO real after correction + OOS".
#
# SCREEN ONLY (advisory, NOT tradeable). No backtest contract, no admission.
# PIT: signal uses spread up to t-1 (shift lag1, rolling 252d) [C1/C2];
#      forward label via shift(.,n=H,type='lead') [forward form, shift-rule ok];
#      lockbox 2023-12-22 strict (all data <= lockbox); cap weight lagged [C2].
# Honesty: any missing dependency -> {"executed":false, reason:...}. No fabrication.
# ============================================================================

suppressMessages({ library(data.table); library(arrow) })

ROOT    <- "/mnt/c/Users/User/OneDrive/바탕 화면/Quant_Module_Moltbot"
setwd(ROOT)
OUT     <- file.path(ROOT, "stage_artifacts", "WT_CREATIVE_SCREEN3_RERUN")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
LOG     <- file.path(OUT, "run_log.txt")
logln <- function(...) { m <- paste0(format(Sys.time(),"%H:%M:%S "), sprintf(...)); cat(m,"\n"); cat(m,"\n",file=LOG,append=TRUE) }

# dependency-free JSON writer (flat list of scalars/short vectors)
write_json <- function(obj, path) {
  esc <- function(s) gsub('"','\\\\"', s)
  tv <- function(v) {
    if (is.null(v)) return("null")
    if (length(v)==1 && is.na(v)) return("null")
    if (is.logical(v) && length(v)==1) return(tolower(as.character(v)))
    if (is.numeric(v) && length(v)==1) return(if (is.finite(v)) format(v,digits=8,scientific=FALSE) else "null")
    if (is.character(v) && length(v)==1) return(paste0('"',esc(v),'"'))
    paste0("[", paste(sapply(v,tv),collapse=", "), "]")
  }
  writeLines(c("{", paste(sapply(names(obj), function(k) paste0('  "',k,'": ',tv(obj[[k]]))), collapse=",\n"), "}"), path)
}

LOCKBOX   <- as.Date("2023-12-22")
OOS_SPLIT <- as.Date("2019-01-01")
H <- 21L; Z_THR <- 2.0; WIN <- 252L; COST_RT <- 4*0.0015; MIN_EVENTS <- 20L; MIN_NAMES_SECTOR <- 3L

# Newey-West t of the mean of a series (matches screen2 newey_t exactly)
newey_t <- function(x, lag=H) {
  x <- x[is.finite(x)]; n <- length(x)
  if (n < 10) return(c(mean=NA_real_, t=NA_real_, n=n))
  mu <- mean(x); e <- x-mu; g0 <- sum(e^2)/n; s <- g0; L <- min(lag, n-1)
  for (k in 1:L) { w <- 1-k/(L+1); gk <- sum(e[(k+1):n]*e[1:(n-k)])/n; s <- s+2*w*gk }
  c(mean=mu, t=mu/sqrt(s/n), n=n)
}

# ===========================================================================
# PART A: multiplicity correction on existing 325-pair table
# ===========================================================================
A <- list(part="A_screen2_inSample_multiplicity", executed=FALSE)
tryCatch({
  csv2 <- file.path(ROOT,"stage_artifacts","WT_CREATIVE_SCREEN2","sector_pair_meanrev","pair_reversion_table.csv")
  if (!file.exists(csv2)) stop("pair_reversion_table.csv not found")
  dt <- fread(csv2)
  if (!"nw_t" %in% names(dt)) stop("nw_t column missing")
  dt[, nw_t := suppressWarnings(as.numeric(nw_t))]
  dt <- dt[is.finite(nw_t)]
  N <- nrow(dt)
  logln("PART A: %d pairs (finite nw_t)", N)

  # original GO criterion replicated: t>2 AND net_mean>0
  n_go_orig <- dt[nw_t>2 & is.finite(net_mean) & net_mean>0, .N]
  n_t_gt2   <- dt[nw_t>2, .N]
  n_abs_t2  <- dt[abs(nw_t)>2, .N]

  # two-sided p from NW t (normal approx). Reversion is positive tail (t>2).
  dt[, p_two := 2*pnorm(-abs(nw_t))]
  dt[, p_one_pos := pnorm(-nw_t)]   # one-sided upper (reversion): small p = strong reversion

  alpha <- 0.05; q <- 0.10
  # chance baselines
  exp_false_two <- alpha*N            # |t|>1.96 expected under null ~16.25
  exp_false_one <- 0.025*N            # t>+1.96 expected under null ~8.125

  # Bonferroni (two-sided)
  bonf_p <- alpha/N
  n_bonf <- dt[p_two < bonf_p, .N]
  # Bonferroni one-sided positive
  n_bonf_one <- dt[p_one_pos < alpha/N, .N]

  # BH-FDR q=0.10 on one-sided-positive p (reversion direction is the hypothesis)
  o <- order(dt$p_one_pos); ps <- dt$p_one_pos[o]
  thr <- (seq_len(N)/N)*q
  pass <- which(ps <= thr); k_bh <- if (length(pass)) max(pass) else 0L
  bh_p_cut <- if (k_bh>0) ps[k_bh] else 0
  dt[, bh_survivor := p_one_pos <= bh_p_cut]
  n_bh <- dt[bh_survivor==TRUE, .N]

  # BH-FDR also on two-sided p (report both)
  o2 <- order(dt$p_two); ps2 <- dt$p_two[o2]
  pass2 <- which(ps2 <= thr); k_bh2 <- if (length(pass2)) max(pass2) else 0L
  n_bh_two <- k_bh2

  # DSR-style haircut: expected max of N iid N(0,1) (Bailey & Lopez de Prado 2014)
  g <- 0.5772156649
  emax_t <- (1-g)*qnorm(1-1/N) + g*qnorm(1-1/(N*exp(1)))
  best_t <- max(dt$nw_t, na.rm=TRUE)
  best_survives <- best_t > emax_t
  # how many exceed the expected-max-under-null threshold
  n_gt_emax <- dt[nw_t > emax_t, .N]

  setorder(dt, -nw_t)
  fwrite(dt[bh_survivor==TRUE, .(pair,a,b,n,cond_rev_mean,nw_t,net_mean,hit,p_one_pos,p_two,nw_t_pre,net_mean_pre)],
         file.path(OUT,"screen2_fdr_survivors.csv"))

  verdict <- if (n_bh > exp_false_one*1.5 && best_survives) "FDR_SURVIVORS_EXCEED_CHANCE"
             else if (n_bh > 0 || best_survives) "BORDERLINE_FEW_SURVIVORS"
             else "NEAR_CHANCE_DROP"

  A <- list(part="A_screen2_inSample_multiplicity", executed=TRUE,
    n_pairs=N, original_go_n_t_gt2_and_net_pos=n_go_orig, n_t_gt2=n_t_gt2, n_abs_t_gt2=n_abs_t2,
    chance_exp_false_two_sided=exp_false_two, chance_exp_false_one_sided_pos=exp_false_one,
    n_survive_bonferroni_two=n_bonf, n_survive_bonferroni_one_pos=n_bonf_one,
    n_survive_bh_fdr_q0.10_one_pos=n_bh, bh_p_cutoff=bh_p_cut,
    n_survive_bh_fdr_q0.10_two=n_bh_two,
    best_nw_t=best_t, dsr_expected_max_t_under_null=emax_t,
    best_survives_dsr=best_survives, n_pairs_above_emax=n_gt_emax,
    verdict_fdr=verdict,
    note="p from NW t via normal approx. DSR via expected-max-t (Bailey-LdP 2014); no per-pair daily PnL series in summary CSV. Clean OOS in PART C.")
  logln("PART A done: n_go_orig=%d n_bh(one)=%d n_bh(two)=%d n_bonf=%d best_t=%.3f emax=%.3f exp_false_one=%.1f -> %s",
        n_go_orig, n_bh, n_bh_two, n_bonf, best_t, emax_t, exp_false_one, verdict)
}, error=function(e){ A <<- list(part="A_screen2_inSample_multiplicity", executed=FALSE, reason=paste0("INFEASIBLE: ", conditionMessage(e))); logln("PART A FAIL: %s", conditionMessage(e)) })
write_json(A, file.path(OUT,"screen2_recheck.json"))

# ===========================================================================
# Build sector-index panel from RAWDATA (replicate screen2 exactly)
# ===========================================================================
build_panel <- function() {
  rd <- as.data.table(read_parquet(".cache/rawdata.parquet"))
  needcols <- c("Date","Ticker","Close","Ret","Sector","Size","K200","KQ150")
  miss <- setdiff(needcols, names(rd))
  if (length(miss)) stop(paste0("RAWDATA missing cols: ", paste(miss,collapse=",")))
  rd[, Date := as.Date(Date)]
  rd <- rd[Date >= as.Date("2004-01-01") & Date <= LOCKBOX &
           !is.na(Close) & Close>0 & !is.na(Sector) & Sector!=""]
  rd <- rd[(K200==TRUE | KQ150==TRUE)]
  rd[, mcap := Size]; rd <- rd[!is.na(mcap) & mcap>0]
  setorder(rd, Ticker, Date)
  rd[, mcap_lag := shift(mcap,1L,type="lag"), by=Ticker]
  rd[, ret := Ret]
  rd <- rd[is.finite(ret) & is.finite(mcap_lag) & mcap_lag>0]
  sec <- rd[, .(sret=sum(ret*mcap_lag,na.rm=TRUE)/sum(mcap_lag,na.rm=TRUE), n=.N), by=.(Date,Sector)]
  sec <- sec[n>=MIN_NAMES_SECTOR]; setorder(sec, Sector, Date)
  sec[, idx := cumprod(1+sret), by=Sector]
  prc <- dcast(sec, Date~Sector, value.var="idx"); setorder(prc, Date)
  prc
}

panel <- NULL
tryCatch({ panel <- build_panel(); logln("PANEL built: %d dates x %d sectors", nrow(panel), ncol(panel)-1) },
         error=function(e){ logln("PANEL FAIL: %s", conditionMessage(e)) })

# ===========================================================================
# PART C: clean walk-forward OOS (select pre-2019, freeze, test 2019+)
# ===========================================================================
C <- list(part="C_screen2_clean_oos", executed=FALSE)
if (is.null(panel)) {
  C <- list(part="C_screen2_clean_oos", executed=FALSE, reason="INFEASIBLE: panel not built")
} else tryCatch({
  sectors <- setdiff(names(panel), "Date")
  cov_ok <- sectors[sapply(sectors, function(s) sum(is.finite(panel[[s]])) > (WIN+H+200))]
  sectors <- cov_ok
  logln("PART C: %d sectors with coverage", length(sectors))

  # reversion-event evaluator on a given window [d0,d1] of the prc panel
  eval_pair_win <- function(a, b, d0, d1) {
    d <- panel[, .(Date, A=get(a), B=get(b))]
    d <- d[is.finite(A) & is.finite(B) & A>0 & B>0 & Date>=d0 & Date<=d1]
    if (nrow(d) < WIN+H+60) return(NULL)
    setorder(d, Date)
    d[, spread := log(A)-log(B)]
    d[, sp_lag := shift(spread,1L,type="lag")]
    d[, mu := frollmean(sp_lag, WIN, align="right")]
    d[, sdv := frollapply(sp_lag, WIN, sd, align="right")]
    d[, z := (sp_lag-mu)/sdv]
    d[, sp_fwd := shift(spread, H, type="lead")]   # forward label (shift-rule compliant)
    d[, fwd_chg := sp_fwd - spread]
    ev <- d[is.finite(z) & abs(z)>Z_THR & is.finite(fwd_chg)]
    if (nrow(ev) < MIN_EVENTS) return(list(n=nrow(ev), insufficient=TRUE))
    ev[, rev := -sign(z)*fwd_chg]
    nw <- newey_t(ev$rev, lag=H)
    list(n=nrow(ev), cond_rev_mean=unname(nw["mean"]), nw_t=unname(nw["t"]),
         net_mean=unname(nw["mean"])-COST_RT, hit=mean(ev$rev>0), insufficient=FALSE)
  }

  combs <- t(combn(sectors,2))
  # TRAIN selection window: start .. (OOS_SPLIT-1)
  train_d0 <- as.Date("2004-01-01"); train_d1 <- OOS_SPLIT-1
  test_d0  <- OOS_SPLIT;             test_d1  <- LOCKBOX
  sel <- list()
  for (i in seq_len(nrow(combs))) {
    a <- combs[i,1]; b <- combs[i,2]
    rtr <- tryCatch(eval_pair_win(a,b,train_d0,train_d1), error=function(e) NULL)
    if (is.null(rtr) || isTRUE(rtr$insufficient)) next
    if (!is.finite(rtr$nw_t) || rtr$nw_t<=2 || !is.finite(rtr$net_mean) || rtr$net_mean<=0) next  # SELECT on TRAIN
    rte <- tryCatch(eval_pair_win(a,b,test_d0,test_d1), error=function(e) NULL)
    t_oos    <- if (!is.null(rte) && isFALSE(rte$insufficient)) rte$nw_t    else NA_real_
    net_oos  <- if (!is.null(rte) && isFALSE(rte$insufficient)) rte$net_mean else NA_real_
    n_oos    <- if (!is.null(rte) && isFALSE(rte$insufficient)) rte$n        else NA_integer_
    sel[[length(sel)+1]] <- data.table(pair=paste(a,b,sep=" / "), a=a,b=b,
      n_train=rtr$n, t_train=rtr$nw_t, net_train=rtr$net_mean,
      n_oos=n_oos, t_oos=t_oos, net_oos=net_oos)
  }
  RR <- if (length(sel)) rbindlist(sel, fill=TRUE) else data.table()
  n_sel <- nrow(RR)
  if (n_sel==0) stop("no pairs selected on TRAIN (pre-2019) with t>2 & net>0")
  setorder(RR, -t_train)
  fwrite(RR, file.path(OUT,"screen2_clean_oos_pairs.csv"))
  n_hold_t   <- RR[is.finite(t_oos) & t_oos>2, .N]                       # OOS still t>2
  n_hold_net <- RR[is.finite(t_oos) & t_oos>2 & is.finite(net_oos) & net_oos>0, .N]  # AND net>0
  n_oos_eval <- RR[is.finite(t_oos), .N]
  frac_t   <- if (n_oos_eval>0) n_hold_t/n_oos_eval else NA_real_
  frac_net <- if (n_oos_eval>0) n_hold_net/n_oos_eval else NA_real_
  verdict <- if (!is.na(frac_net) && frac_net>0.20 && n_hold_net>=3) "OOS_HOLDS"
             else if (!is.na(frac_net) && n_hold_net>=1) "OOS_WEAK_BORDERLINE"
             else "OOS_FAILS_DROP"
  C <- list(part="C_screen2_clean_oos", executed=TRUE,
    train_window=paste(train_d0,train_d1,sep=".."), test_window=paste(test_d0,test_d1,sep=".."),
    n_pairs_selected_on_train_t_gt2_net_pos=n_sel, n_oos_evaluable=n_oos_eval,
    n_oos_hold_t_gt2=n_hold_t, n_oos_hold_t_gt2_and_net_pos=n_hold_net,
    fraction_oos_hold_t=frac_t, fraction_oos_hold_t_and_net=frac_net,
    oos_chance_fraction_one_sided=0.025,
    median_t_oos=median(RR$t_oos,na.rm=TRUE), best_t_oos=suppressWarnings(max(RR$t_oos,na.rm=TRUE)),
    verdict_oos=verdict,
    note="Selection ONLY on pre-2019; frozen pair set tested on 2019-01-01..2023-12-22. t>2 OOS hold vs 2.5% chance.")
  logln("PART C done: sel=%d oos_eval=%d hold_t=%d hold_net=%d frac_net=%.3f -> %s",
        n_sel, n_oos_eval, n_hold_t, n_hold_net, ifelse(is.na(frac_net),-1,frac_net), verdict)
}, error=function(e){ C <<- list(part="C_screen2_clean_oos", executed=FALSE, reason=paste0("INFEASIBLE: ", conditionMessage(e))); logln("PART C FAIL: %s", conditionMessage(e)) })
write_json(C, file.path(OUT,"screen2_clean_oos.json"))

logln("ALL DONE."); cat("FINISHED\n")
