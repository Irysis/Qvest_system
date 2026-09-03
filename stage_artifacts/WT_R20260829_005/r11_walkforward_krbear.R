# ── R11 — 스킬 결손 2건 수리
#   (a) KR_Bear 스트레스 구간 (스킬 필수 6종 중 누락분) — 벤치 낙폭에서 데이터-도출, 임의지정 아님
#   (b) walk-forward 판정 (Cycle 2 교훈) — RF-R1 시장분산비중 / beta 를 as-of 단일단면이 아니라
#       월별 재추정의 walk-forward 평균으로 재판정. single-snapshot 과대/과소평가 금지.
#  PIT: 각 월 m 의 Sigma 는 m 이전 자료만. top-25 는 그 달 신호(alpha_scores read-only).
suppressWarnings(suppressMessages({library(data.table); library(arrow); library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
SIG <- as.Date("2026-07-31")

R1<-readRDS(file.path(OUT,"risk_r1.rds")); R2<-readRDS(file.path(OUT,"risk_r2.rds"))
R3<-readRDS(file.path(OUT,"risk_r3.rds")); R4<-readRDS(file.path(OUT,"risk_r4.rds"))
EXPO<-R1$EXPO; ME_win<-R1$ME_win; FR<-R2$FR; UR<-R2$UR
fac_names<-R2$fac_names; SECLV<-R2$SECLV; STY<-R2$STY; WIN_D<-R2$WIN_D
FLOOR <- R3$floor_frac

mk_X <- function(ex) {
  n <- nrow(ex); sec <- factor(ex$Sector, levels = SECLV)
  Xs <- matrix(0, n, length(SECLV)-1L); li <- as.integer(sec)
  for (k in seq_len(length(SECLV)-1L)) Xs[,k] <- as.numeric(li == k)
  Xs[li == length(SECLV), ] <- -1
  colnames(Xs) <- paste0("SEC_", SECLV[-length(SECLV)])
  X <- cbind(MKT = 1, Xs, as.matrix(ex[, ..STY])); rownames(X) <- ex$Ticker; X
}

## ══ (a) KR_Bear — 벤치 월별 낙폭에서 에피소드 도출 ══════════════════════════
PR <- fread(file.path(OUT,"period_returns_production.csv"))
PR[, holding_ym := as.character(holding_ym)]
PR <- PR[holding_ym <= "2026-07"]                      # C11 PIT 절단
setorder(PR, holding_ym)
nav_b <- cumprod(1 + PR$benchmark_ret)
dd_b  <- nav_b / cummax(nav_b) - 1
PR[, bench_dd := dd_b]
## 에피소드 = 낙폭이 0 에서 벗어나 저점 <= -20% 를 찍고 0 으로 복귀할 때까지
in_ep <- FALSE; st <- 0L; eps <- list()
for (i in seq_len(nrow(PR))) {
  if (!in_ep && dd_b[i] < 0) { in_ep <- TRUE; st <- i }
  if (in_ep && (dd_b[i] >= -1e-12 || i == nrow(PR))) {
    seg <- st:i
    if (min(dd_b[seg]) <= -0.20) eps[[length(eps)+1L]] <- seg
    in_ep <- FALSE
  }
}
kr <- rbindlist(lapply(seq_along(eps), function(k) {
  s <- eps[[k]]; sub <- PR[s]
  data.table(scenario = sprintf("KR_Bear_%d", k),
             from = sub$holding_ym[1], to = sub$holding_ym[nrow(sub)], months = nrow(sub),
             trough_dd_bench = min(dd_b[s]),
             strat_cum = prod(1+sub$ret_net)-1, bench_cum = prod(1+sub$benchmark_ret)-1,
             active_cum = prod(1+sub$ret_net)-prod(1+sub$benchmark_ret),
             worst_month = min(sub$ret_net), coverage = 1.0, reliability = "OK")
}))
all_m <- unlist(eps)
kr_all <- data.table(scenario="KR_Bear_ALL", from=PR$holding_ym[min(all_m)], to=PR$holding_ym[max(all_m)],
  months=length(all_m), trough_dd_bench=min(dd_b[all_m]),
  strat_cum=prod(1+PR$ret_net[all_m])-1, bench_cum=prod(1+PR$benchmark_ret[all_m])-1,
  active_cum=prod(1+PR$ret_net[all_m])-prod(1+PR$benchmark_ret[all_m]),
  worst_month=min(PR$ret_net[all_m]), coverage=1.0, reliability="OK")
KR <- rbind(kr, kr_all)
cat("[R11-a] KR_Bear episodes (benchmark drawdown <= -20%):\n"); print(KR)

## ══ (b) walk-forward 판정 ═══════════════════════════════════════════════════
AS <- as.data.table(read_parquet(file.path(OUT,"alpha_scores.parquet")))
AS[, Date := as.Date(Date)]
fdates <- sort(unique(FR$Date))
wf <- list()
for (i in seq_along(ME_win)) {
  m <- ME_win[i]
  fw <- fdates[fdates <= m]; fw <- tail(fw, WIN_D)
  if (length(fw) < 400L) next
  ex <- EXPO[Date == m]; if (nrow(ex) < 100L) next
  setorder(ex, Ticker)
  sc <- AS[Date == m & Ticker %in% ex$Ticker & is.finite(score), .(Ticker, score)]
  if (nrow(sc) < 50L) next
  setorder(sc, -score)
  sel <- sc$Ticker[1:25]
  Bx <- mk_X(ex)
  Fw <- as.matrix(FR[Date %in% fw, ..fac_names]); Om <- cov(Fw)
  e0 <- eigen(Om, symmetric=TRUE)
  Om <- e0$vectors %*% diag(pmax(e0$values, max(e0$values)*1e-6)) %*% t(e0$vectors)
  Uw <- UR[Date %in% fw & Ticker %in% ex$Ticker]
  Dsx <- Uw[, .(n=.N, v=var(u)), by=Ticker][n >= 120L]
  if (!nrow(Dsx)) next
  mv <- median(Dsx$v, na.rm=TRUE); Dsx[, sh := pmin(1,120/n)]
  Dsx[, v_sh := pmax((1-sh)*v + sh*mv, FLOOR*mv)]
  dv <- setNames(rep(mv, nrow(ex)), ex$Ticker); dv[Dsx$Ticker] <- Dsx$v_sh

  w <- setNames(rep(0, nrow(ex)), ex$Ticker); w[sel] <- 1/length(sel)
  k2 <- ex[mkt == "K200"]
  wb <- setNames(rep(0, nrow(ex)), ex$Ticker)
  if (nrow(k2)) wb[k2$Ticker] <- k2$Size/sum(k2$Size)
  x  <- as.numeric(t(Bx) %*% w);  names(x)  <- fac_names
  xb <- as.numeric(t(Bx) %*% wb); names(xb) <- fac_names
  dvv <- dv[ex$Ticker]
  var_p <- as.numeric(t(x) %*% Om %*% x) + sum(w^2*dvv)
  var_b <- as.numeric(t(xb) %*% Om %*% xb) + sum(wb^2*dvv)
  cov_pb<- as.numeric(t(x) %*% Om %*% xb) + sum(w*wb*dvv)
  Omx <- as.numeric(Om %*% x)
  wf[[length(wf)+1L]] <- data.table(
    Date = m,
    mkt_var_share  = x["MKT"]*Omx[1]/var_p,
    spec_var_share = sum(w^2*dvv)/var_p,
    beta_model     = cov_pb/var_b,
    vol_ann        = sqrt(var_p*252),
    x_RVOL = x["X_RVOL"], x_VAL = x["X_VAL"], x_MOM = x["X_MOM"], x_SIZE = x["X_SIZE"])
}
WF <- rbindlist(wf)
cat(sprintf("[R11-b] walk-forward months = %d (%s .. %s)\n", nrow(WF), min(WF$Date), max(WF$Date)))
sm <- function(v) sprintf("mean %.4f sd %.4f min %.4f max %.4f", mean(v), sd(v), min(v), max(v))
cat("  mkt_var_share :", sm(WF$mkt_var_share), "\n")
cat("  spec_var_share:", sm(WF$spec_var_share), "\n")
cat("  beta_model    :", sm(WF$beta_model), "\n")
cat("  x_RVOL        :", sm(WF$x_RVOL), "\n")
cat(sprintf("  as-of single snapshot: mkt %.4f  spec %.4f  (walk-forward 평균 대비 %+.1f%%p / %+.1f%%p)\n",
            WF[Date==SIG, mkt_var_share], WF[Date==SIG, spec_var_share],
            100*(WF[Date==SIG, mkt_var_share]-mean(WF$mkt_var_share)),
            100*(WF[Date==SIG, spec_var_share]-mean(WF$spec_var_share))))
rf1_wf <- mean(WF$mkt_var_share)
cat(sprintf("  RF-R1 walk-forward 판정: mean %.4f > 0.40 -> %s (월별 발화율 %.1f%%)\n",
            rf1_wf, if (rf1_wf > 0.40) "TRIGGERED" else "clear",
            100*mean(WF$mkt_var_share > 0.40)))

## 실현 beta 의 walk-forward (36개월 롤링, PIT)
PRb <- PR[order(holding_ym)]
roll <- 36L; rb <- list()
for (i in roll:nrow(PRb)) {
  s <- (i-roll+1L):i
  rb[[length(rb)+1L]] <- data.table(holding_ym = PRb$holding_ym[i],
    beta_realized = cov(PRb$ret_net[s], PRb$benchmark_ret[s])/var(PRb$benchmark_ret[s]))
}
RB <- rbindlist(rb)
cat(sprintf("[R11-b] realized rolling-36m beta: %s | full-sample(alpha) = 0.8688\n", sm(RB$beta_realized)))
cat(sprintf("  최근 12개월 평균 %.4f | beta<1 인 창 비율 %.1f%%\n",
            mean(tail(RB$beta_realized,12)), 100*mean(RB$beta_realized < 1)))

saveRDS(list(KR = KR, WF = WF, RB = RB, rf1_wf = rf1_wf,
             wf_summary = list(
               mkt_var_share = list(mean=mean(WF$mkt_var_share), sd=sd(WF$mkt_var_share),
                                    min=min(WF$mkt_var_share), max=max(WF$mkt_var_share),
                                    as_of=WF[Date==SIG, mkt_var_share],
                                    pct_months_above_40 = mean(WF$mkt_var_share > 0.40)),
               spec_var_share= list(mean=mean(WF$spec_var_share), sd=sd(WF$spec_var_share),
                                    min=min(WF$spec_var_share), max=max(WF$spec_var_share),
                                    as_of=WF[Date==SIG, spec_var_share]),
               beta_model    = list(mean=mean(WF$beta_model), sd=sd(WF$beta_model),
                                    min=min(WF$beta_model), max=max(WF$beta_model),
                                    as_of=WF[Date==SIG, beta_model]),
               x_RVOL        = list(mean=mean(WF$x_RVOL), sd=sd(WF$x_RVOL),
                                    min=min(WF$x_RVOL), max=max(WF$x_RVOL),
                                    as_of=WF[Date==SIG, x_RVOL]),
               beta_realized_roll36 = list(mean=mean(RB$beta_realized), sd=sd(RB$beta_realized),
                                    min=min(RB$beta_realized), max=max(RB$beta_realized),
                                    last12_mean=mean(tail(RB$beta_realized,12)),
                                    pct_below_1=mean(RB$beta_realized < 1),
                                    n_windows=nrow(RB)))),
        file.path(OUT, "risk_r11.rds"))
write_parquet(WF, file.path(OUT, "walk_forward_risk.parquet"))
cat("[R11] done\n")
