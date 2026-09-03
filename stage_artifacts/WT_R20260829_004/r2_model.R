# R2 — Barra형 다요인 위험모형: r = beta*Mkt + Sector(24) + Style(4) + e
#   PIT: 모든 노출은 신호월말(t) 정보 · 요인수익은 홀딩월(t+1) 일간 · Sigma 추정창은 rolling only (C1)
#   C5: 국면 라벨은 regime_signal_timeseries 의 used_cutoff(<= holding_month_start) 산출물만 소비
suppressWarnings(suppressMessages({library(data.table); library(arrow)}))
ROOT <- Sys.getenv("QM_ROOT"); if(!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT_R20260829_004")
SIG_DATE <- as.Date("2026-08-28")
t0 <- Sys.time()

P  <- readRDS(file.path(OUT,"panel.rds"))
RI <- readRDS(file.path(OUT,"risk_inputs.rds"))
D  <- as.data.table(P$DAILY)[Date <= SIG_DATE]
BMD<- as.data.table(P$BMD)[Date <= SIG_DATE, .(Date, BM_Ret)]
ME <- as.Date(P$ME); ME <- ME[ME <= SIG_DATE]
SIZE <- as.data.table(P$SIZE)
LIQ  <- as.data.table(P$fwd$liq_dt)          # Date, Ticker, adv (t-1 PIT, C10)
A    <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
SECM <- as.data.table(RI$SECM)

setkey(D, Date, Ticker)
D <- merge(D, BMD, by="Date", all.x=TRUE)
D <- D[is.finite(Ret) & is.finite(BM_Ret)]
D[, wlim := fifelse(Date >= as.Date("2015-06-15"), 0.31, 0.16)]   # KRX 일간 가격제한폭(2015-06-15 부터 30%, 이전 15%) + 1%p 버퍼
N_WINS <- D[abs(Ret) > wlim, .N]
D[, Ret := pmin(pmax(Ret, -wlim), wlim)][, wlim := NULL]
cat(sprintf("[R2] 법정 가격제한폭 초과 관측 winsorize: %d건 (%.5f%%) — 무상증자·액면분할 미조정 결함 방어
", N_WINS, 100*N_WINS/nrow(D)))

## ── 1. 월말 노출(B) 산출: beta(252d rolling, Blume) + Size/Mom/Vol/Liq z + Sector ──
dts <- sort(unique(D$Date))
beta_rows <- vector("list", length(ME))
for (i in seq_along(ME)) {
  t_end <- ME[i]
  w_days <- dts[dts <= t_end]; if (length(w_days) < 252L) next
  w_days <- tail(w_days, 252L)
  S <- D[.(w_days), on="Date", nomatch=0L]
  bm_m <- mean(S$BM_Ret[!duplicated(S$Date)])
  bvar <- var(S$BM_Ret[!duplicated(S$Date)])
  bb <- S[, .(n=.N, cv = sum((Ret-mean(Ret))*(BM_Ret-bm_m))/(.N-1)), by=Ticker][n >= 150L]
  bb[, beta_raw := cv/bvar]
  bb[, beta := 0.67*pmin(pmax(beta_raw,-1),3) + 0.33]     # Blume
  beta_rows[[i]] <- data.table(Date=t_end, Ticker=bb$Ticker, beta=bb$beta, n_beta=bb$n)
}
BETA <- rbindlist(beta_rows)
cat(sprintf("[R2] BETA rows %d · months %d\n", nrow(BETA), uniqueN(BETA$Date)))

EXP <- merge(A[, .(Date, Ticker, momentum_raw, vol126_ann)], BETA, by=c("Date","Ticker"))
EXP <- merge(EXP, SIZE, by=c("Date","Ticker"), all.x=TRUE)
EXP <- merge(EXP, LIQ[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
# liq_dt 는 forward-return 이 있는 월말까지만(최종 2026-07-31) — 마지막 신호월말은 RD_slim 으로 직접 산출(t-1 PIT, C10)
RIx <- readRDS(file.path(OUT,"risk_inputs.rds"))$RD_slim
if (!is.null(RIx)) {
  RIx <- as.data.table(RIx)[, .(Date=as.Date(Date), Ticker, val = Close*Vol)]
  setorder(RIx, Ticker, Date)
  miss_dt <- sort(unique(EXP[is.na(adv)]$Date))
  add <- rbindlist(lapply(miss_dt, function(dd){
    W <- RIx[Date < dd]                                   # t-1 이전만 (C10)
    W <- W[Date %in% tail(sort(unique(W$Date)), 20L)]
    W[, .(Date = dd, adv20 = mean(val, na.rm=TRUE), nd=.N), by=Ticker][nd>=10L, .(Date,Ticker,adv20)]
  }))
  if (nrow(add)) { EXP <- merge(EXP, add, by=c("Date","Ticker"), all.x=TRUE)
                   EXP[is.na(adv) & is.finite(adv20), adv := adv20][, adv20 := NULL] }
  cat(sprintf("[R2] adv 보정: 결측 월말 %d개 · 보정행 %d\n", length(miss_dt), nrow(add)))
}
EXP <- merge(EXP, SECM, by=c("Date","Ticker"), all.x=TRUE)
EXP[is.na(Sector) | Sector=="", Sector := "UNKNOWN"]
zwin <- function(x){ x <- as.numeric(x); q <- quantile(x, c(.01,.99), na.rm=TRUE)
  x <- pmin(pmax(x, q[1]), q[2]); m <- mean(x, na.rm=TRUE); s <- sd(x, na.rm=TRUE)
  if(!is.finite(s)||s==0) rep(0,length(x)) else { z <- (x-m)/s; z[!is.finite(z)] <- 0; z } }
EXP[, `:=`(x_size = zwin(log(pmax(Size,1))),
           x_mom  = zwin(momentum_raw),
           x_vol  = zwin(vol126_ann),
           x_liq  = zwin(log(pmax(adv,1)))), by=Date]
EXP[!is.finite(beta), beta := 1]
STYLES <- c("x_size","x_mom","x_vol","x_liq")
secs <- sort(unique(EXP$Sector))
cat(sprintf("[R2] EXP rows %d · sectors %d · median names/월 %.0f\n",
            nrow(EXP), length(secs), median(EXP[, .N, by=Date]$N)))

## ── 2. 홀딩월 일간 횡단면 회귀 → 요인수익 f_d + 잔차 e_id ────────────────────
D[, ym := format(Date, "%Y-%m")]
EXP[, hold_ym := format(as.Date(format(Date+31,"%Y-%m-01")) , "%Y-%m")]   # 신호월말 → 다음달
EXP[, hold_ym := {d <- as.POSIXlt(Date); sprintf("%04d-%02d", d$year+1900 + (d$mon+1)%/%12, (d$mon+1)%%12 + 1)}]
hold_list <- sort(unique(EXP$hold_ym)); hold_list <- hold_list[hold_list <= format(SIG_DATE,"%Y-%m")]
fac_names <- c("Market", paste0("SEC_", secs), STYLES)
fout <- vector("list", length(hold_list)); eout <- vector("list", length(hold_list))
for (k in seq_along(hold_list)) {
  hm <- hold_list[k]
  E <- EXP[hold_ym == hm]
  if (nrow(E) < 50L) next
  Dk <- D[ym == hm]
  if (nrow(Dk) == 0L) next
  Dk <- merge(Dk, E[, .(Ticker, beta, x_size, x_mom, x_vol, x_liq, Sector, Size)], by="Ticker")
  if (nrow(Dk) == 0L) next
  Dk[, r_ex := Ret - beta*BM_Ret]                     # 시장성분 제거(관측 요인수익 = BM_Ret)
  Xall <- cbind(model.matrix(~ 0 + factor(Sector, levels=secs), data=Dk),
                as.matrix(Dk[, ..STYLES]))
  colnames(Xall) <- c(paste0("SEC_", secs), STYLES)
  wt <- sqrt(pmax(Dk$Size, 1)); wt <- wt/mean(wt)
  days <- sort(unique(Dk$Date))
  fm <- matrix(NA_real_, length(days), ncol(Xall), dimnames=list(NULL, colnames(Xall)))
  ev <- vector("list", length(days))
  for (j in seq_along(days)) {
    idx <- which(Dk$Date == days[j]); if (length(idx) < 40L) next
    Xj <- Xall[idx, , drop=FALSE]; yj <- Dk$r_ex[idx]; wj <- wt[idx]
    keepc <- which(colSums(abs(Xj)) > 0 & apply(Xj, 2, function(z) length(unique(z))>1 | sum(z)>=3))
    Xj2 <- Xj[, keepc, drop=FALSE]
    fit <- tryCatch(qr.solve(crossprod(Xj2*sqrt(wj)) + diag(1e-10, ncol(Xj2)),
                             crossprod(Xj2*sqrt(wj), yj*sqrt(wj))), error=function(e) NULL)
    if (is.null(fit)) next
    fm[j, colnames(Xj2)] <- as.numeric(fit)
    ev[[j]] <- data.table(Date=days[j], Ticker=Dk$Ticker[idx], e = yj - as.numeric(Xj2 %*% fit))
  }
  fdt <- data.table(Date=days, ym=hm)
  fdt <- cbind(fdt, as.data.table(fm))
  fout[[k]] <- fdt; eout[[k]] <- rbindlist(ev)
  if (k %% 60 == 0) cat(sprintf("  ..%s (%d/%d) %.0fs\n", hm, k, length(hold_list),
                                as.numeric(difftime(Sys.time(),t0,units="secs"))))
}
FRET <- rbindlist(fout, fill=TRUE)
FRET <- merge(FRET, BMD, by="Date", all.x=TRUE); setnames(FRET, "BM_Ret", "Market")
setcolorder(FRET, c("Date","ym","Market"))
ERES <- rbindlist(eout)
for (cc in setdiff(names(FRET), c("Date","ym"))) set(FRET, which(!is.finite(FRET[[cc]])), cc, 0)
cat(sprintf("[R2] FRET %d일 · %d요인 · ERES %d행 · %.0fs\n",
            nrow(FRET), ncol(FRET)-2, nrow(ERES), as.numeric(difftime(Sys.time(),t0,units="secs"))))

saveRDS(list(FRET=FRET, ERES=ERES, EXP=EXP, secs=secs, STYLES=STYLES, fac_names=fac_names,
             ME=ME, sig_date=SIG_DATE), file.path(OUT,"risk_factor_model.rds"))
cat(sprintf("[R2] done %.1fs\n", as.numeric(difftime(Sys.time(),t0,units="secs"))))
