# O6 — 산출물 발행: weights.csv · optimization_package.json (+ 보조 진단 집계)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
MB  <- file.path(ROOT,"qepm/mailbox/worktask/WT-R20260829_004")
O1<-readRDS(file.path(OUT,"o1_objects.rds")); O2<-readRDS(file.path(OUT,"o2_objects.rds"))
O3<-readRDS(file.path(OUT,"o3_objects.rds")); O5<-readRDS(file.path(OUT,"o5_objects.rds"))
RES<-O2$RES; RESC<-O2$RESC; PPY<-12L; SEL<-"W2_IV"; W<-RES[[SEL]]$W; M<-RES[[SEL]]$M
srf <- function(x) mean(x)/stats::sd(x)*sqrt(PPY)
oosr <- function(m){ pr<-as.data.table(m$pr); a<-pr$ret_net-pr$benchmark_ret
  median(sapply(c(0.55,0.65,0.75), function(f){k<-floor(length(a)*f); srf(a[(k+1):length(a)])/srf(a[1:k])})) }
A0 <- RESC$C1_EW_off$M; A0_ALPHA <- A0$alpha_ann_pct; F7_FLOOR <- A0_ALPHA - 1.0

row <- function(nm, m, off=NULL) list(
  method=nm, calmar=m$calmar, sr=m$sr, cagr=m$cagr, mdd=m$mdd,
  net_ir=m$ir, port_t=m$port_t, beta=m$beta, alpha_beta_ctl_ann_pct=m$alpha_ann_pct, t_alpha=m$t_alpha,
  turnover_annual=m$to, cost_annual=m$cost_ann, max_w_mean=m$max_w_mean, max_w_max=m$max_w_max,
  neff_mean=m$neff_mean, hhi_mean=m$hhi_mean, n_names_max=m$n_names_max,
  oos_retention_rough=oosr(m),
  F7_delta_vs_A0_pp = m$alpha_ann_pct - A0_ALPHA,
  F7_pass = (m$alpha_ann_pct >= F7_FLOOR - 1e-12),
  TO_pass = (m$to <= 11.0),
  constraint_pass = (m$n_names_max<=25 && m$min_w>=0 && m$sumw_dev<1e-6),
  F7_delta_vs_own_off_pp = if(is.null(off)) NA_real_ else m$alpha_ann_pct - off$alpha_ann_pct)
offmap <- list(W1_EW="C1_EW_off", W2_IV="C2_IV_off", W3_ATILT="C3_ATILT_off",
               W4_SECCAP="C4_SECCAP_off", W5_WCH_IV="C1_EW_off")
MC <- lapply(names(RES), function(nm) row(nm, RES[[nm]]$M, RESC[[offmap[[nm]]]]$M)); names(MC)<-names(RES)
CC <- lapply(names(RESC), function(nm) row(nm, RESC[[nm]]$M)); names(CC)<-names(RESC)

## ── weights.csv (선택 method · 전 sig_date 시계열) ───────────────────────────
WC <- copy(W)[order(Date, -w)]
WC[, rank := seq_len(.N), by=Date]
WC[, holding_ym := substr(format(as.Date(format(Date,"%Y-%m-01"))+32L,"%Y-%m"),1,7)]
WC <- WC[, .(as_of_date=Date, signal_ym=format(Date,"%Y-%m"), holding_ym, ticker=Ticker,
             weight=w, rank, sector=Sector, panic=panic_use, vol126_ann)]
fwrite(WC, file.path(OUT,"weights.csv"))
n_alpha_dates <- uniqueN(O1$AS$Date); n_w_dates <- uniqueN(WC$as_of_date)
dens <- n_w_dates/n_alpha_dates
cat(sprintf("[O6] weights.csv rows=%d dates=%d / alpha sig_dates=%d -> density=%.4f\n",
            nrow(WC), n_w_dates, n_alpha_dates, dens))

asof <- O5$asof; Wa <- O5$Wa[order(-w)]
tw <- setNames(as.list(round(Wa$w, 8)), Wa$Ticker)
cat(sprintf("[O6] as-of %s | n=%d sum=%.10f min=%.6f max=%.6f\n", asof, length(tw),
            sum(unlist(tw)), min(unlist(tw)), max(unlist(tw))))
saveRDS(list(MC=MC, CC=CC, WC=WC, tw=tw, dens=dens, n_alpha_dates=n_alpha_dates,
             n_w_dates=n_w_dates, A0_ALPHA=A0_ALPHA, F7_FLOOR=F7_FLOOR, asof=asof, Wa=Wa),
        file.path(OUT,"o6_objects.rds"))
cat("\n=== method table ===\n")
for(nm in names(MC)){ z<-MC[[nm]]; cat(sprintf("%-11s Calmar=%+.4f SR=%+.4f netIR=%+.4f a=%+.3f (F7 %s, d=%+.3fpp) TO=%.3f(%s) oos=%+.3f\n",
  nm, z$calmar, z$sr, z$net_ir, z$alpha_beta_ctl_ann_pct, ifelse(z$F7_pass,"PASS","FAIL"),
  z$F7_delta_vs_A0_pp, z$turnover_annual, ifelse(z$TO_pass,"ok","OVER"), z$oos_retention_rough)) }
cat("\n=== controls (무조건화) ===\n")
for(nm in names(CC)){ z<-CC[[nm]]; cat(sprintf("%-14s Calmar=%+.4f SR=%+.4f netIR=%+.4f a=%+.3f TO=%.3f oos=%+.3f\n",
  nm, z$calmar, z$sr, z$net_ir, z$alpha_beta_ctl_ann_pct, z$turnover_annual, z$oos_retention_rough)) }
cat(sprintf("\n[F7] A0(무조건화 EW) alpha=%.4f%%/yr -> floor=%.4f%%/yr\n", A0_ALPHA, F7_FLOOR))
