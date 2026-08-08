# prereg_holdout_proposal.R — P1' 준비: rank|φ=1 후보의 holdout 예측구간 *제안* 산출
# ★봉인(06_Registry/live_track 등재)은 채택 시점 거버넌스 행위 — 도훈 confirm 전까지 하지 않는다.
#   여기서는 stage_artifacts 에 제안본만 만들어, 승인 즉시 save_holdout_interval() 로 봉인 가능하게 준비.
# 계약 함수 그대로 사용: 02_Infrastructure/contracts/holdout_falsification.R::build_holdout_interval()
#   (오늘 census 대상이 '정본 함수 있는데 인라인 재구현' 이므로 재구현하지 않음)
# ⚠ DSR 게이트는 **active(초과수익) 시계열** 기준이라 forge 산출이 필요 — 여기서 산출하지 않는다.
#   (net 시계열로 DSR 흉내내면 proxy 게이트 통과 = measurement-graduation 위반)
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
source("02_Infrastructure/contracts/holdout_falsification.R")
OUT <- "stage_artifacts/tilt_realign_20260808"
TOPN<-20L; MINN<-15L; LIQ<-2e8; LAM<-1.5; UB<-0.20; UBCR<-0.10; BPS<-0.0015

car <- as.data.table(read_parquet("06_Registry/book_carrier/carrier_STR_1715_on_M4gAE_R05_noLayer4_PG2.parquet"))
car[, decision_date := as.Date(decision_date)]
ovl <- unique(car[, .(decision_date, invested)]); setkey(ovl, decision_date)
ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]; setkey(raw, Date, Ticker)
sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))

MO <- list()
for (i in seq_len(length(sig_dates)-1L)) {
  sd_i <- sig_dates[i]; nx <- sig_dates[i+1L]
  if (!nrow(ovl[decision_date==sd_i])) next
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
.apply_tophi <- function(w_tilt, w_prev, phi, ub) {
  if (is.null(w_prev) || phi <= 0) return(w_tilt)
  wp <- numeric(length(w_tilt)); names(wp) <- names(w_tilt)
  common <- intersect(names(w_tilt), names(w_prev)); wp[common] <- w_prev[common]
  dropped <- 1 - sum(wp); if (dropped > 0) wp <- wp + dropped * w_tilt
  if (sum(wp) > 0) wp <- wp / sum(wp)
  blend <- phi/(1+phi)
  normalize_long_only(blend*wp + (1-blend)*w_tilt, lb=0, ub=ub, target_sum=1)
}
run_arm <- function(phi) {
  wp <- NULL; npv <- NULL; out <- numeric(length(MO))
  for (k in seq_along(MO)) {
    m <- MO[[k]]; ub <- if (identical(m$regime,"CRISIS")) UBCR else UB
    wt <- linear_tilt_qd(m$a, lambda=LAM, lb=0, ub=ub); names(wt) <- names(m$a)
    w <- .apply_tophi(wt, wp, phi, ub)
    g <- sum(w * m$r[names(w)]) * m$inv
    nw <- w * m$inv
    d <- if (is.null(npv)) sum(abs(nw)) else { u <- union(names(nw),names(npv))
      x<-setNames(rep(0,length(u)),u); x[names(nw)]<-nw; y<-setNames(rep(0,length(u)),u); y[names(npv)]<-npv; sum(abs(x-y)) }
    out[k] <- g - BPS*d; wp <- w; npv <- nw
  }
  out
}
eval_dates <- as.Date(sapply(MO, function(m) as.character(m$ed)))
r_can <- run_arm(3); r_c1 <- run_arm(1)
cat(sprintf("[series] months=%d (%s~%s)\n", length(MO), min(eval_dates), max(eval_dates)))

props <- list()
for (nm in c("canonical_phi3","candidate_phi1")) {
  r <- if (nm=="canonical_phi3") r_can else r_c1
  iv <- build_holdout_interval(returns_monthly=r, holdout_months=21L, block=12L, B=4000L, seed=7L,
        strategy_id=sprintf("STR_1715_M4gAE_noLayer4__rank_%s", nm))
  props[[nm]] <- iv
  cat(sprintf("[prereg 제안 %s] n_input=%d | SR_input=%.3f | holdout %d개월 예측구간 [%.3f, %.3f]\n",
              nm, iv$n_input_months, iv$sr_input, iv$holdout_months, iv$q05, iv$q95))
}
d <- r_c1 - r_can
tt <- t.test(d)
cat(sprintf("\n[후보 vs 정본 paired] mean %+.4f%%/월 · t=%.3f · p=%.4f · 승월 %d/%d (%.1f%%)\n",
            mean(d)*100, tt$statistic, tt$p.value, sum(d>0), length(d), 100*mean(d>0)))
cat(sprintf("[구간 중첩] 정본 [%.3f, %.3f] vs 후보 [%.3f, %.3f] — 봉인 구간이 겹치면 holdout 21개월로는 두 규약을 구별 불가\n",
            props$canonical_phi3$q05, props$canonical_phi3$q95, props$candidate_phi1$q05, props$candidate_phi1$q95))

write_json(list(schema="prereg_proposal_v1", status="PROPOSAL_NOT_SEALED",
  seal_gate="도훈 정렬 confirm + 채택 결정 후 save_holdout_interval() 로 06_Registry/live_track 등재",
  generated=as.character(Sys.time()), months=length(MO),
  metric_type="carrier_recon_paired", overlay="carrier invested_t (arm 불변)",
  cost_model="15bps × Σ|Δ(invested·w)|",
  dsr_note="DSR 게이트는 active 시계열 기준 — forge 산출 필요. 본 제안에서 미산출(proxy 대체 금지).",
  proposals=props,
  paired_candidate_vs_canonical=list(mean_pct=mean(d)*100, t=as.numeric(tt$statistic), p=tt$p.value,
                                     win_rate=mean(d>0))),
  file.path(OUT,"prereg_holdout_proposal.json"), pretty=TRUE, auto_unbox=TRUE)
fwrite(data.table(eval_date=eval_dates, net_canonical_phi3=r_can, net_candidate_phi1=r_c1, diff=d),
       file.path(OUT,"arm_series_canonical_vs_phi1.csv"))
cat(sprintf("\n[saved] %s/prereg_holdout_proposal.json + arm_series_canonical_vs_phi1.csv (봉인 아님 — 제안본)\n", OUT))
