# phi_shape_cap_sweep.R — P2: 가중 규칙 3축 분해 sweep (271m, 선별 고정)
# 질문: 정본(SR 1.531) vs 실배포(1.718) 격차는 세 축 중 어디서 오나?
#   축1 tilt 모양   : rank(정본 linear_tilt_qd) vs z(실배포 .tilt)
#   축2 tophi phi   : 0 / 1 / 3(정본)   — w_prev 블렌드 강도 = 턴오버 패널티
#   축3 CRISIS cap  : on(ub 0.10) / off(0.20)
# = 2×3×2 = 12 arm. 선별은 canonical(top-N→liq) 고정 (B≈C 실측으로 선별축 무의미 확인됨).
# 엔진 = extract_book_carrier.R verbatim. 지표 = PerformanceAnalytics 표준함수.
# ★selection_type=sweep — argmax 채택 시 DSR 게이트 적용 대상. 본 산출은 곡선 보고(채택 아님).
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
OUT <- "stage_artifacts/tilt_realign_20260808"
TOPN<-20L; MINN<-15L; LIQ<-2e8; LAM<-1.5; UB<-0.20; UBCR<-0.10; BPS<-0.0015

ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]; setkey(raw, Date, Ticker)
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))

## --- 1) 월별 선별·수익 1회 precompute (arm 간 동일) ---
MO <- list()
for (i in seq_len(length(sig_dates)-1L)) {
  sd_i <- sig_dates[i]; nx <- sig_dates[i+1L]
  panel <- ap[Date==sd_i & !is.na(score_eff)]; if (!nrow(panel)) next
  start_d <- min(raw[Date>=sd_i]$Date); if (!length(start_d)||is.na(start_d)) next
  end_d <- { z <- min(raw[Date>=nx]$Date); if (!length(z)||is.na(z)) max(raw$Date) else z }
  setorder(panel, -score_eff)
  N_elig <- nrow(panel); N_tgt <- min(TOPN,N_elig); if (N_tgt<MINN && N_elig>=MINN) N_tgt <- MINN
  if (N_tgt < 5L) next
  a <- setNames(panel[seq_len(N_tgt)]$score_eff, panel[seq_len(N_tgt)]$Ticker)
  liqd <- raw[Date>=(start_d-30L) & Date<start_d, .(ADV=mean(TV,na.rm=TRUE)), by=Ticker]
  tk <- intersect(names(a), liqd[ADV>=LIQ, Ticker]); if (length(tk)<5L) tk <- names(a)
  a <- a[tk]
  sret <- raw[Date>start_d & Date<=end_d, .(rf=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
  rv <- setNames(sret$rf, sret$Ticker)[names(a)]; rv[is.na(rv)] <- 0
  MO[[length(MO)+1L]] <- list(dd=sd_i, ed=end_d, regime=panel$regime_state[1L], a=a, r=rv)
}
cat(sprintf("[precompute] months=%d (%s~%s)\n", length(MO), MO[[1]]$dd, MO[[length(MO)]]$dd))

## --- 2) 가중 규칙: 모양 × tophi × cap ---
.znorm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.ztilt <- function(a,ub){z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+LAM*z/length(a));if(sum(w)>0)w<-w/sum(w);.znorm(w,0,ub)}
# tophi 블렌드 = linear_tilt_to_penalty_qd 본문 verbatim (base tilt 만 교체 가능하게 분리)
.apply_tophi <- function(w_tilt, w_prev, phi, ub, normfun) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi/(1+phi)
  normfun(blend*wp + (1-blend)*w_tilt, ub)
}
make_w <- function(a, w_prev, shape, phi, ub) {
  if (shape == "rank") {
    wt <- linear_tilt_qd(a, lambda=LAM, lb=0, ub=ub); names(wt) <- names(a)
    .apply_tophi(wt, w_prev, phi, ub, function(w,u) normalize_long_only(w, lb=0, ub=u, target_sum=1))
  } else {
    wt <- .ztilt(a, ub); names(wt) <- names(a)
    .apply_tophi(wt, w_prev, phi, ub, function(w,u) .znorm(w, 0, u))
  }
}

## --- 3) 12 arm 실행 ---
grid <- CJ(shape=c("rank","z"), phi=c(0,1,3), cap=c(TRUE,FALSE), sorted=FALSE)
eval_dates <- as.Date(sapply(MO, function(m) as.character(m$ed)))
regimes <- sapply(MO, function(m) m$regime)
arm_rets <- list(); rows <- list()
for (g in seq_len(nrow(grid))) {
  sh <- grid$shape[g]; ph <- grid$phi[g]; cp <- grid$cap[g]
  wp <- NULL; gr <- numeric(length(MO)); tu <- numeric(length(MO)); mx <- numeric(length(MO))
  for (k in seq_along(MO)) {
    m <- MO[[k]]
    ub <- if (cp && identical(m$regime,"CRISIS")) UBCR else UB
    w <- make_w(m$a, wp, sh, ph, ub)
    gr[k] <- sum(w * m$r[names(w)])
    if (is.null(wp)) tu[k] <- sum(abs(w)) else {
      u <- union(names(w),names(wp)); x<-setNames(rep(0,length(u)),u); x[names(w)]<-w
      y<-setNames(rep(0,length(u)),u); y[names(wp)]<-wp; tu[k] <- sum(abs(x-y)) }
    mx[k] <- max(w); wp <- w
  }
  net <- gr - BPS*tu
  x <- xts(net, order.by=eval_dates); tab <- table.AnnualizedReturns(x, scale=12, Rf=0)
  lbl <- sprintf("%s | phi=%g | cap=%s", sh, ph, ifelse(cp,"on","off"))
  arm_rets[[lbl]] <- net
  rows[[g]] <- data.table(arm=lbl, shape=sh, phi=ph, crisis_cap=cp,
    SR=round(as.numeric(tab[3,1]),3), CAGR_pct=round(as.numeric(tab[1,1])*100,2),
    MDD_pct=round(as.numeric(maxDrawdown(x))*100,2), turnover=round(mean(tu),3), max_w=round(mean(mx),4))
}
R <- rbindlist(rows)
base_lbl <- "rank | phi=3 | cap=on"
R[, paired_t_vs_canonical := sapply(arm, function(l) if (l==base_lbl) NA_real_ else
    round(as.numeric(t.test(arm_rets[[l]] - arm_rets[[base_lbl]])$statistic),3))]
setorder(R, -SR)
cat("\n===== 12-arm sweep (net, 15bps × Σ|Δw| [paired_approx], SR 내림차순) =====\n")
print(R)
cat(sprintf("\n[정본 기준선] %s : SR %.3f / MDD %.2f%%\n", base_lbl, R[arm==base_lbl, SR], R[arm==base_lbl, MDD_pct]))
cat("\n[축별 주변효과 — SR 평균]\n")
cat(sprintf("  모양 rank %.3f vs z %.3f (Δ %+.3f)\n", R[shape=="rank", mean(SR)], R[shape=="z", mean(SR)], R[shape=="z", mean(SR)]-R[shape=="rank", mean(SR)]))
for (p in c(0,1,3)) cat(sprintf("  phi=%g : SR %.3f / MDD %.2f%% / 턴오버 %.3f\n", p, R[phi==p, mean(SR)], R[phi==p, mean(MDD_pct)], R[phi==p, mean(turnover)]))
cat(sprintf("  cap on %.3f (MDD %.2f%%) vs off %.3f (MDD %.2f%%)\n", R[crisis_cap==TRUE, mean(SR)], R[crisis_cap==TRUE, mean(MDD_pct)], R[crisis_cap==FALSE, mean(SR)], R[crisis_cap==FALSE, mean(MDD_pct)]))
fwrite(R, file.path(OUT,"phi_shape_cap_sweep.csv"))
write_json(list(metric_type="carrier_recon_paired", selection_type="sweep",
  dsr_note="argmax 채택 시 DSR 게이트 적용 대상 — 본 산출은 곡선 보고(채택 아님)",
  n_trials=nrow(R), months=length(MO), cost_model="15bps × Σ|Δw| (drift 미반영)", arms=R),
  file.path(OUT,"phi_shape_cap_sweep.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[saved] %s/phi_shape_cap_sweep.csv (+json)\n", OUT))
