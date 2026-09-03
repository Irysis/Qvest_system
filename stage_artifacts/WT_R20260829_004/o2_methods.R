# O2 — weight method 배터리 (사전선언 selection_predeclaration.json 준수 · 상한 5종)
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT,"02_Infrastructure/contracts/weighted_screen_bt.R"))
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
O1 <- readRDS(file.path(OUT,"o1_objects.rds")); RI <- readRDS(file.path(OUT,"risk_inputs.rds"))
AS <- O1$AS; SIG <- O1$SIG; R <- O1$R; BENCH <- O1$BENCH
SECM <- as.data.table(RI$SECM); SECM[is.na(Sector)|Sector=="", Sector := "UNKNOWN"]
TOPN <- 25L; KAPPA <- 0.5; SECCAP <- 0.30; PPY <- 12L; COST_BPS <- 15

panic_map <- SIG[is.finite(panic), .(signal_ym, panic_use=panic)]
AS2 <- merge(AS, panic_map, by="signal_ym", all.x=TRUE); AS2[is.na(panic_use), panic_use := 0L]
AS2 <- merge(AS2, SECM, by=c("Date","Ticker"), all.x=TRUE)
AS2[is.na(Sector)|Sector=="", Sector := "UNKNOWN"]
cat(sprintf("[O2] sector 결측(=UNKNOWN) 비율 %.4f%%\n", 100*mean(AS2$Sector=="UNKNOWN")))

## ── 선택(구성) ────────────────────────────────────────────────────────────────
pick <- function(scorecol){ x <- copy(AS2); setorderv(x, c("Date",scorecol), c(1,-1))
  x[, head(.SD, TOPN), by=Date, .SDcols=c("Ticker","score","score_base_momentum",
      "vol126_ann","panic_use","Sector")] }
H_on  <- pick("score")                # 패닉월 구성 교체 반영(alpha spec)
H_off <- pick("score_base_momentum")  # 무조건화(모멘텀 상시)

## ── 비중 규칙 ────────────────────────────────────────────────────────────────
.norm <- function(w){ w[!is.finite(w)|w<0] <- 0; if(sum(w)<=0) return(rep(1/length(w),length(w))); w/sum(w) }
w_ew   <- function(D) rep(1/nrow(D), nrow(D))
w_iv   <- function(D){ s <- D$vol126_ann; s[!is.finite(s)|s<=0] <- median(s[is.finite(s)&s>0])
                       if(all(!is.finite(s))) return(w_ew(D)); .norm(1/s) }
w_at   <- function(D, scorecol){ v <- D[[scorecol]]; m <- mean(v); sdv <- stats::sd(v)
                       z <- if(!is.finite(sdv)||sdv==0) rep(0,length(v)) else (v-m)/sdv
                       .norm(pmax(0, 1 + KAPPA*z)) }
SECCAP_LOG <- new.env(); SECCAP_LOG$rows <- list()
w_sec  <- function(D){ w <- w_ew(D); sec <- D$Sector; nsec <- uniqueN(sec)
  feasible <- (nsec * SECCAP >= 1 - 1e-12)
  for(k in 1:100){
    s <- tapply(w, sec, sum); over <- names(s)[s > SECCAP + 1e-12]
    if(!length(over)) break
    exc <- 0
    for(o in over){ ix <- which(sec==o); sc <- SECCAP/s[[o]]; exc <- exc + sum(w[ix])*(1-sc); w[ix] <- w[ix]*sc }
    fr <- which(!(sec %in% over)); if(!length(fr)) break
    w[fr] <- w[fr] + exc * w[fr]/sum(w[fr])
  }
  w <- .norm(w)
  smax <- max(tapply(w, sec, sum))
  if(smax > SECCAP + 1e-6) SECCAP_LOG$rows[[length(SECCAP_LOG$rows)+1]] <-
      data.table(Date=D$Date[1], n_sectors=nsec, achieved_top_sector=smax, feasible=feasible)
  w }

build_w <- function(H, method, scorecol){
  H <- copy(H); setorder(H, Date)
  H[, w := {
      D <- .SD
      switch(method,
        EW      = w_ew(D),
        IV      = w_iv(D),
        ATILT   = w_at(D, scorecol),
        SECCAP  = w_sec(D),
        WCH_IV  = if (D$panic_use[1] == 1L) w_iv(D) else w_ew(D))
    }, by=Date, .SDcols=c("Date","Ticker","score","score_base_momentum","vol126_ann","panic_use","Sector")]
  H[, .(Date, Ticker, w, Sector, panic_use, vol126_ann)]
}

## ── 측정 ─────────────────────────────────────────────────────────────────────
measure <- function(W, rid){
  m <- weighted_screen_bt(W[,.(Date,Ticker,w)], R, BENCH, COST_BPS, rid, rid)
  pr <- as.data.table(m$period_returns); r <- pr$ret_net; n <- length(r)
  nav <- cumprod(1+r); mdd <- min(nav/cummax(nav)-1); cg <- prod(1+r)^(PPY/n)-1
  fit <- lm(r ~ pr$benchmark_ret); ct <- coeftest(fit, vcov=NeweyWest(fit,lag=3,prewhite=FALSE))
  hhi <- W[, .(h=sum(w^2), mx=max(w), neff=1/sum(w^2)), by=Date]
  list(m=m, pr=pr, n_months=n, port_t=m$portfolio_alpha_t_nw_lag3, ir=m$information_ratio,
       sr=mean(r)/stats::sd(r)*sqrt(PPY), cagr=cg, mdd=mdd, calmar=cg/abs(mdd),
       beta=unname(ct[2,1]), alpha_ann_pct=100*PPY*unname(ct[1,1]), t_alpha=unname(ct[1,3]),
       net_active_sr=m$net_sr, to=m$turnover_annual, cost_ann=m$turnover_annual*COST_BPS/1e4,
       hhi_mean=mean(hhi$h), max_w_mean=mean(hhi$mx), max_w_max=max(hhi$mx),
       neff_mean=mean(hhi$neff), n_names_max=max(W[,.N,by=Date]$N),
       sumw_dev=max(abs(W[, sum(w), by=Date]$V1 - 1)), min_w=min(W$w))
}

METHODS <- list(
  W1_EW      = list(H="on",  wm="EW",     sc="score"),
  W2_IV      = list(H="on",  wm="IV",     sc="score"),
  W3_ATILT   = list(H="on",  wm="ATILT",  sc="score"),
  W4_SECCAP  = list(H="on",  wm="SECCAP", sc="score"),
  W5_WCH_IV  = list(H="off", wm="WCH_IV", sc="score_base_momentum")
)
CTRL <- list(
  C1_EW_off     = list(H="off", wm="EW",     sc="score_base_momentum"),
  C2_IV_off     = list(H="off", wm="IV",     sc="score_base_momentum"),
  C3_ATILT_off  = list(H="off", wm="ATILT",  sc="score_base_momentum"),
  C4_SECCAP_off = list(H="off", wm="SECCAP", sc="score_base_momentum")
)
run_set <- function(SET){ out <- list()
  for(nm in names(SET)){ s <- SET[[nm]]; H <- if(s$H=="on") H_on else H_off
    W <- build_w(H, s$wm, s$sc); out[[nm]] <- list(W=W, M=measure(W, paste0("wt004_",nm))) }
  out }
RES  <- run_set(METHODS); RESC <- run_set(CTRL)

pr1 <- function(nm, M) cat(sprintf("%-14s SR=%+.4f CAGR=%+.4f MDD=%+.4f Calmar=%+.4f | b=%.3f a=%+.3f%%/yr t(a)=%+.2f | PORT_t=%+.3f IR=%+.3f | TO=%.3f cost=%.4f | maxw=%.4f neff=%.1f\n",
  nm, M$sr, M$cagr, M$mdd, M$calmar, M$beta, M$alpha_ann_pct, M$t_alpha, M$port_t, M$ir, M$to, M$cost_ann, M$max_w_mean, M$neff_mean))
cat("\n===== METHODS (overlay 적용) =====\n"); for(nm in names(RES)) pr1(nm, RES[[nm]]$M)
cat("\n===== CONTROLS (무조건화 쌍 — 선택 후보 아님) =====\n"); for(nm in names(RESC)) pr1(nm, RESC[[nm]]$M)
cat("\n[제약] Sigma w 최대편차 / 최소 w / n_max:\n")
for(nm in names(RES)) cat(sprintf("  %-12s sumw_dev=%.2e min_w=%.6f n_max=%d\n", nm,
   RES[[nm]]$M$sumw_dev, RES[[nm]]$M$min_w, RES[[nm]]$M$n_names_max))
if(length(SECCAP_LOG$rows)) { L <- rbindlist(SECCAP_LOG$rows)
  cat(sprintf("[SECCAP] 상한 미달성 월 %d / 최대 top-sector %.4f · 구조적 불가(n_sec*cap<1) %d\n",
      nrow(L), max(L$achieved_top_sector), sum(!L$feasible))) } else cat("[SECCAP] 전 월 상한 달성\n")
saveRDS(list(RES=RES, RESC=RESC, H_on=H_on, H_off=H_off, AS2=AS2,
             seccap_log=if(length(SECCAP_LOG$rows)) rbindlist(SECCAP_LOG$rows) else NULL),
        file.path(OUT,"o2_objects.rds"))
