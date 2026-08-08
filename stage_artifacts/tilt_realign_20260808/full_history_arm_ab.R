# full_history_arm_ab.R — 가중 규약 3-arm 전기간(269m) paired A/B
# 목적: ④ 정렬 결정 입력 — "실배포 공식(z-선형)이 역사 전체에서 어떤 전략인가"
# 엔진 = extract_book_carrier.R 57-99 verbatim (검증: replay max|dw|=0, 북 재현 cor 0.999973)
# arms (선별·수익엔진 동일, 지정 축만 변경):
#   A canonical : 선별 top-N→liq / rank-tilt + tophi φ=3 + CRISIS ub=0.10   (북·게이트 정본)
#   B zlin_only : 선별 top-N→liq / z-선형, tophi 없음, CRISIS ub 없음        (가중 축만 격리)
#   C deployed  : 선별 liq→top-N / z-선형, tophi 없음, CRISIS ub 없음        (실배포 생성기 전체 레시피)
# 지표 = PerformanceAnalytics 표준함수 (table.AnnualizedReturns / maxDrawdown). 자체합성 금지 준수.
# metric_type = carrier_recon_paired (forge 아님 — HARD 게이트 판정용 아님, arm 간 대조용)
suppressMessages({ library(data.table); library(arrow); library(jsonlite); library(PerformanceAnalytics); library(xts) })
options(scipen=999)
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/portfolio/strategy_tilt_weights.R")
OUT <- "stage_artifacts/tilt_realign_20260808"

TOPN<-20L; MINN<-15L; LIQ<-2e8; LAM<-1.5; PHI<-3.0; UB<-0.20; UBCR<-0.10; BPS<-0.0015

ap <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); ap[, Date:=as.Date(Date)]
raw <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=c("Date","Ticker","Close","Vol","Ret")))
raw[, Date:=as.Date(Date)]; raw[, TV:=Close*Vol]; setkey(raw, Date, Ticker)

# 실배포 생성기의 인라인 함수 (verbatim — forward_weights_R05_noLayer4_M4gAE.R:29-30)
.norm <- function(w,lb=0,ub=UB,ts=1,mi=50){w[is.na(w)]<-0;w[w<lb]<-lb;w[w>ub]<-ub;for(i in seq_len(mi)){s<-sum(w);if(abs(s-ts)<1e-8)break;if(s==0)break;w<-w*(ts/s);w[w>ub]<-ub;w[w<lb]<-lb};w}
.tilt <- function(a,lam=LAM,lb=0,ub=UB){if(!length(a))return(numeric(0));z<-(a-mean(a))/pmax(sd(a),1e-10);w<-pmax(0,1/length(a)+lam*z/length(a));if(sum(w)>0)w<-w/sum(w);.norm(w,lb,ub)}

sig_dates <- sort(unique(ap[!is.na(score_eff), Date]))
cat(sprintf("[input] sig_dates=%d (%s~%s)\n", length(sig_dates), min(sig_dates), max(sig_dates)))

res <- list(); wprev <- list(A=NULL, B=NULL, C=NULL)
for (i in seq_len(length(sig_dates)-1L)) {
  sd_i <- sig_dates[i]; nx <- sig_dates[i+1L]
  panel <- ap[Date==sd_i & !is.na(score_eff)]; if (!nrow(panel)) next
  regime_i <- panel$regime_state[1L]
  start_d <- min(raw[Date>=sd_i]$Date); if (!length(start_d) || is.na(start_d)) next
  end_d <- { z <- min(raw[Date>=nx]$Date); if (!length(z)||is.na(z)) max(raw$Date) else z }
  liqd <- raw[Date>=(start_d-30L) & Date<start_d, .(ADV=mean(TV,na.rm=TRUE)), by=Ticker]
  liquid <- liqd[ADV>=LIQ, Ticker]
  setorder(panel, -score_eff)

  # 선별 (canonical: top-N → liq 교집합)
  N_elig <- nrow(panel); N_tgt <- min(TOPN,N_elig); if (N_tgt<MINN && N_elig>=MINN) N_tgt <- MINN
  if (N_tgt < 5L) next
  a_can <- setNames(panel[seq_len(N_tgt)]$score_eff, panel[seq_len(N_tgt)]$Ticker)
  tk <- intersect(names(a_can), liquid); if (length(tk)<5L) tk <- names(a_can)
  a_can <- a_can[tk]
  # 선별 (deployed: liq 필터 → top-N)
  pf <- panel[Ticker %in% liquid]; if (nrow(pf)<5L) pf <- panel
  pf <- pf[seq_len(min(TOPN,nrow(pf)))]
  a_dep <- setNames(pf$score_eff, pf$Ticker)

  ubA <- if (identical(regime_i,"CRISIS")) min(UB,UBCR) else UB
  wA <- normalize_long_only(linear_tilt_to_penalty_qd(a_can, lambda=LAM, w_prev=wprev$A, phi=PHI, lb=0, ub=ubA), lb=0, ub=ubA, target_sum=1)
  names(wA) <- names(a_can)
  wB <- .tilt(a_can); names(wB) <- names(a_can)
  wC <- .tilt(a_dep); names(wC) <- names(a_dep)

  pd <- raw[Date>start_d & Date<=end_d, .(Date,Ticker,Ret)]
  sret <- pd[, .(rf=prod(1+Ret,na.rm=TRUE)-1), by=Ticker]
  gross <- function(w){ x <- merge(data.table(Ticker=names(w), w=as.numeric(w)), sret, by="Ticker", all.x=TRUE); x[is.na(rf), rf:=0]; sum(x$w*x$rf) }
  # 턴오버: Σ|Δw| (양 leg). 비용 = BPS × Σ|Δw| — drift 미반영, 3 arm 동일 적용 (라벨: paired_approx)
  to <- function(w, wp){ if (is.null(wp)) return(sum(abs(w))); u <- union(names(w),names(wp)); a<-setNames(rep(0,length(u)),u); a[names(w)]<-w; b<-setNames(rep(0,length(u)),u); b[names(wp)]<-wp; sum(abs(a-b)) }
  res[[length(res)+1L]] <- data.table(eval_date=end_d, decision_date=sd_i, regime=regime_i,
    gA=gross(wA), gB=gross(wB), gC=gross(wC), tA=to(wA,wprev$A), tB=to(wB,wprev$B), tC=to(wC,wprev$C),
    nA=length(wA), nB=length(wB), nC=length(wC), maxA=max(wA), maxB=max(wB), maxC=max(wC))
  wprev$A <- wA; wprev$B <- wB; wprev$C <- wC
  if (i %% 60 == 0) cat(sprintf("  ... %s (%d/%d)\n", sd_i, i, length(sig_dates)-1L))
}
R <- rbindlist(res); setorder(R, eval_date)
cat(sprintf("[replay] months=%d (%s~%s)\n", nrow(R), min(R$eval_date), max(R$eval_date)))

for (a in c("A","B","C")) R[[paste0("net",a)]] <- R[[paste0("g",a)]] - BPS*R[[paste0("t",a)]]

summ <- function(lbl, rets, tos, nms, mxs) {
  x <- xts(rets, order.by=as.Date(R$eval_date))
  tab <- table.AnnualizedReturns(x, scale=12, Rf=0)
  data.table(arm=lbl, CAGR_pct=round(as.numeric(tab[1,1])*100,2), SD_pct=round(as.numeric(tab[2,1])*100,2),
             SR=round(as.numeric(tab[3,1]),3), MDD_pct=round(as.numeric(maxDrawdown(x))*100,2),
             turnover_mean=round(mean(tos),3), n_names_mean=round(mean(nms),1), max_w_mean=round(mean(mxs),4))
}
cat("\n===== GROSS (비용 전) =====\n")
gt <- rbindlist(list(summ("A canonical (rank+tophi+CRISIScap)", R$gA,R$tA,R$nA,R$maxA),
                     summ("B z-linear (가중축만)",              R$gB,R$tB,R$nB,R$maxB),
                     summ("C deployed (z-lin+선별순서)",        R$gC,R$tC,R$nC,R$maxC)))
print(gt)
cat("\n===== NET (15bps × Σ|Δw|, drift 미반영 · 3 arm 동일 적용 [paired_approx]) =====\n")
nt <- rbindlist(list(summ("A canonical", R$netA,R$tA,R$nA,R$maxA),
                     summ("B z-linear",  R$netB,R$tB,R$nB,R$maxB),
                     summ("C deployed",  R$netC,R$tC,R$nC,R$maxC)))
print(nt)

cat("\n===== CRISIS 국면 서브샘플 (net) =====\n")
cr <- R[regime=="CRISIS"]
cat(sprintf("  n_months=%d | A mean %+.2f%% / B %+.2f%% / C %+.2f%% | A-C spread %+.2f%%pt\n",
            nrow(cr), mean(cr$netA)*100, mean(cr$netB)*100, mean(cr$netC)*100, (mean(cr$netA)-mean(cr$netC))*100))
cat(sprintf("  CRISIS 최대비중 평균: A %.4f (cap %.2f) vs C %.4f\n", mean(cr$maxA), UBCR, mean(cr$maxC)))
cat(sprintf("  CRISIS MDD: A %.2f%% / C %.2f%%\n", maxDrawdown(xts(cr$netA, as.Date(cr$eval_date)))*100,
            maxDrawdown(xts(cr$netC, as.Date(cr$eval_date)))*100))

pt <- t.test(R$netA - R$netC)
cat(sprintf("\n[paired A−C] mean %+.4f%%/월  t=%.3f  p=%.4f  (월 |스프레드| 평균 %.2f%%pt)\n",
            mean(R$netA-R$netC)*100, pt$statistic, pt$p.value, mean(abs(R$netA-R$netC))*100))
fwrite(R, file.path(OUT,"arm_ab_monthly_269m.csv"))
write_json(list(metric_type="carrier_recon_paired", engine="extract_book_carrier.R 57-99 verbatim",
  cost_model="15bps × Σ|Δw| (drift 미반영, paired_approx)", months=nrow(R),
  gross=gt, net=nt, paired_A_minus_C=list(mean_pct=mean(R$netA-R$netC)*100, t=as.numeric(pt$statistic), p=pt$p.value),
  note="forge 아님 — HARD 게이트 판정 불가. arm 간 대조 전용."),
  file.path(OUT,"arm_ab_summary.json"), pretty=TRUE, auto_unbox=TRUE)
cat(sprintf("\n[saved] %s/arm_ab_monthly_269m.csv + arm_ab_summary.json\n", OUT))
