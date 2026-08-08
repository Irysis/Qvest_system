# phi_sweep_under_overlay.R — P2 확장: φ 다이얼이 overlay 결합 하에서도 같은 기울기인가?
# 동기: bare sleeve 곡선(φ↓ → SR↑MDD↑)은 overlay 없는 값. 북은 overlay 적용 상태이고
#       MDD 레버가 overlay 이므로, 정렬 판정은 overlay 결합 곡선으로 해야 한다.
# overlay = 캐리어 실측 invested_t (= M4∩AE gate × β_R05, D3 전환 반영분) — arm 불변(paired).
# 비용 = 15bps × Σ|Δ(invested_t·w_t)| (종목별 Δ보유명목, v2.4 delta 사상. 현금 leg 포함)
#        ★bare 판(15bps×Σ|Δw|)보다 충실 — overlay 진출입 회전까지 과금.
# 지표 = PerformanceAnalytics 표준함수. metric_type=carrier_recon_paired (forge 아님).
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
OUT <- "stage_artifacts/tilt_realign_20260808"
TOPN<-20L; MINN<-15L; LIQ<-2e8; LAM<-1.5; UB<-0.20; UBCR<-0.10; BPS<-0.0015

## overlay 스케줄 (캐리어 실측)
car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
ovl <- unique(car[, .(decision_date, invested)])
setkey(ovl, decision_date)
cat(sprintf("[overlay] %d개월 (%s~%s) | invested 분포: min %.2f / 중앙 %.2f / max %.2f | invested<1 인 달 %d\n",
            nrow(ovl), min(ovl$decision_date), max(ovl$decision_date),
            min(ovl$invested), median(ovl$invested), max(ovl$invested), sum(ovl$invested < 0.999)))

ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]; setkey(raw, Date, Ticker)
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))

MO <- list()
for (i in seq_len(length(sig_dates)-1L)) {
  sd_i <- sig_dates[i]; nx <- sig_dates[i+1L]
  if (!nrow(ovl[decision_date == sd_i])) next          # overlay 실측 있는 달만 (paired 유지)
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
  MO[[length(MO)+1L]] <- list(dd=sd_i, ed=end_d, regime=panel$regime_state[1L], a=a, r=rv,
                              inv=ovl[decision_date==sd_i, invested][1])
}
cat(sprintf("[precompute] months=%d (%s~%s)\n", length(MO), MO[[1]]$dd, MO[[length(MO)]]$dd))

.znorm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.ztilt <- function(a,ub){z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+LAM*z/length(a));if(sum(w)>0)w<-w/sum(w);.znorm(w,0,ub)}
.apply_tophi <- function(w_tilt, w_prev, phi, ub, normfun) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi/(1+phi); normfun(blend*wp + (1-blend)*w_tilt, ub)
}
make_w <- function(a, w_prev, shape, phi, ub) {
  if (shape=="rank") { wt <- linear_tilt_qd(a, lambda=LAM, lb=0, ub=ub); names(wt) <- names(a)
    .apply_tophi(wt, w_prev, phi, ub, function(w,u) normalize_long_only(w, lb=0, ub=u, target_sum=1))
  } else { wt <- .ztilt(a, ub); names(wt) <- names(a)
    .apply_tophi(wt, w_prev, phi, ub, function(w,u) .znorm(w, 0, u)) }
}
dnot <- function(cur, prv) { u <- union(names(cur), names(prv))
  x <- setNames(rep(0,length(u)),u); x[names(cur)] <- cur
  y <- setNames(rep(0,length(u)),u); y[names(prv)] <- prv; sum(abs(x-y)) }

grid <- CJ(shape=c("rank","z"), phi=c(0,1,3), cap=c(TRUE,FALSE), sorted=FALSE)
eval_dates <- as.Date(sapply(MO, function(m) as.character(m$ed)))
rows <- list(); series <- list()
for (g in seq_len(nrow(grid))) {
  sh <- grid$shape[g]; ph <- grid$phi[g]; cp <- grid$cap[g]
  wp <- NULL; npv <- NULL
  gb <- nb <- go <- no <- numeric(length(MO))
  for (k in seq_along(MO)) {
    m <- MO[[k]]; ub <- if (cp && identical(m$regime,"CRISIS")) UBCR else UB
    w <- make_w(m$a, wp, sh, ph, ub)
    gb[k] <- sum(w * m$r[names(w)])                      # bare gross
    nb[k] <- gb[k] - BPS*(if (is.null(wp)) sum(abs(w)) else dnot(w, wp))
    nw <- w * m$inv                                       # overlay 적용 명목
    go[k] <- gb[k] * m$inv                                # 현금 leg 수익 0
    no[k] <- go[k] - BPS*(if (is.null(npv)) sum(abs(nw)) else dnot(nw, npv))
    wp <- w; npv <- nw
  }
  mk <- function(v) { x <- xts(v, order.by=eval_dates); tab <- table.AnnualizedReturns(x, scale=12, Rf=0)
    list(SR=round(as.numeric(tab[3,1]),3), CAGR=round(as.numeric(tab[1,1])*100,2),
         MDD=round(as.numeric(maxDrawdown(x))*100,2)) }
  B <- mk(nb); O <- mk(no)
  lbl <- sprintf("%s|phi=%g|cap=%s", sh, ph, ifelse(cp,"on","off"))
  series[[lbl]] <- no
  rows[[g]] <- data.table(arm=lbl, shape=sh, phi=ph, cap=cp,
    bare_SR=B$SR, bare_MDD=B$MDD, ovl_SR=O$SR, ovl_CAGR=O$CAGR, ovl_MDD=O$MDD)
}
R <- rbindlist(rows)
base <- "rank|phi=3|cap=on"
R[, ovl_paired_t := sapply(arm, function(l) if (l==base) NA_real_ else
    round(as.numeric(t.test(series[[l]] - series[[base]])$statistic),3))]
setorder(R, -ovl_SR)
cat("\n===== overlay 결합 (net, 15bps × Σ|Δ보유명목|) — ovl_SR 내림차순 =====\n"); print(R)
cat(sprintf("\n[정본] %s : overlay SR %.3f / CAGR %.2f%% / MDD %.2f%%  (bare SR %.3f / MDD %.2f%%)\n",
            base, R[arm==base, ovl_SR], R[arm==base, ovl_CAGR], R[arm==base, ovl_MDD],
            R[arm==base, bare_SR], R[arm==base, bare_MDD]))
cat("\n[φ 주변효과 — overlay 하]\n")
for (p in c(0,1,3)) cat(sprintf("  phi=%g : SR %.3f / CAGR %.2f%% / MDD %.2f%%   (bare SR %.3f / MDD %.2f%%)\n",
  p, R[phi==p, mean(ovl_SR)], R[phi==p, mean(ovl_CAGR)], R[phi==p, mean(ovl_MDD)], R[phi==p, mean(bare_SR)], R[phi==p, mean(bare_MDD)]))
cat(sprintf("\n[cap 축 — overlay 하] on SR %.3f/MDD %.2f%% vs off SR %.3f/MDD %.2f%%\n",
            R[cap==TRUE, mean(ovl_SR)], R[cap==TRUE, mean(ovl_MDD)], R[cap==FALSE, mean(ovl_SR)], R[cap==FALSE, mean(ovl_MDD)]))
cat(sprintf("[모양 축 — overlay 하] rank SR %.3f vs z SR %.3f (Δ %+.3f)\n",
            R[shape=="rank", mean(ovl_SR)], R[shape=="z", mean(ovl_SR)], R[shape=="z", mean(ovl_SR)]-R[shape=="rank", mean(ovl_SR)]))
fwrite(R, file.path(OUT,"phi_sweep_under_overlay.csv"))
write_json(list(metric_type="carrier_recon_paired", selection_type="sweep", n_trials=nrow(R), months=length(MO),
  overlay="carrier invested_t (M4∩AE gate × beta_R05), arm-invariant",
  cost_model="15bps × Σ|Δ(invested·w)| (보유명목 delta, 현금 leg 포함)", arms=R),
  file.path(OUT,"phi_sweep_under_overlay.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[saved] %s/phi_sweep_under_overlay.csv (+json)\n", OUT))
