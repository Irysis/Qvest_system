## WT-D20260822_009 — 반증(F1/F2 승계분) + 기전 진단 + prior-art 중복
## 사전등록: PREREG.json falsification_side_observation / prior_art_overlap_obligation
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(sandwich); library(lmtest); library(PerformanceAnalytics); library(xts)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT-D20260822_009")
`%||%` <- function(a,b) if (is.null(a)) b else a
say <- function(f, ...) cat(sprintf(paste0("[d] ", f, "\n"), ...))
source("02_Infrastructure/contracts/weighted_screen_bt.R")
nw_t <- function(x, lag = 3L) { x <- x[is.finite(x)]; if (length(x) < 6L) return(NA_real_)
  fit <- lm(x ~ 1); tryCatch(as.numeric(lmtest::coeftest(fit,
    vcov. = sandwich::NeweyWest(fit, lag = lag, prewhite = FALSE))[1,3]), error = function(e) NA_real_) }
ym_add <- function(ym,k){y<-as.integer(substr(ym,1,4));m<-as.integer(substr(ym,6,7))+k
  y<-y+(m-1L)%/%12L;m<-(m-1L)%%12L+1L;sprintf("%04d-%02d",y,m)}
D <- list()
O <- readRDS(file.path(OUT, "10_measure_objects.rds"))
SMx <- O$SMx; S <- O$S; Wb <- O$Wb; Wf <- O$Wf; rb <- O$rb; rf <- O$rf

SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret)[, Date := as.Date(Date)]
bench <- as.data.table(SI$bench)[, Date := as.Date(Date)]
SIZE <- as.data.table(SI$SIZE)[, Date := as.Date(Date)]
P <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))
P[, Date := as.Date(Date)]

## ── F1 (승계): 배제군의 fwd_foreign_3m + fwd_inst_3m vs 동월 유니버스 중앙값 ──
FW <- P[, .(Date, Ticker, smart = fwd_foreign_3m_n + fwd_inst_3m_n)]
M1 <- merge(SMx[, .(Date, Ticker, excluded)], FW, by = c("Date","Ticker"))
M1 <- M1[is.finite(smart)]
f1 <- M1[, .(sp = mean(smart[excluded]) - median(smart), n_e = sum(excluded)),
         by = Date][is.finite(sp) & n_e >= 3]
f1_t <- nw_t(f1$sp)
f1_fired <- isTRUE(f1_t >= 2.0)
say("F1: 배제군 smart-money(fwd_for+fwd_inst) − 유니버스 중앙값 : 월평균 %+.6f NW t=%+.3f → 발화(기전기각) = %s (기각조건 t>=+2.0)",
    mean(f1$sp), f1_t, f1_fired)
D$F1 <- list(spec = "저-absorb 배제군의 후속 3M 외국인+기관 순매수/Size − 동월 유니버스 중앙값",
  mean_spread = mean(f1$sp), nw_t = f1_t, n_months = nrow(f1),
  reject_threshold = 2.0, fired = f1_fired,
  reading = if (f1_fired) "기전 기각 — 스마트머니가 오히려 배제군을 매집" else
            if (isTRUE(f1_t <= -2.0)) "기전 지지 방향 (스마트머니 이탈 유의)" else "기전 기각 아님, 지지도 유의하지 않음(미결)")

## ── F2 (승계): 꼬리 실현월 하락일 개인 순매수 — 저-absorb vs 고-absorb ───────
## 꼬리 실현 = 홀딩월 Ret_1m <= -0.20 (NP2 tail_fixed_dn 동일 문턱)
RET <- fwd_ret[, .(Date, Ticker, Ret_1m)]
Q <- copy(SMx)[, `:=`(qlo = excluded)]
Q[, thr_hi := { v <- absorb[is.finite(absorb)]
                if (length(v) >= 30L) quantile(v, 0.80, type = 7, names = FALSE) else Inf }, by = Date]
Q[, qhi := is.finite(absorb) & absorb >= thr_hi]
Q <- merge(Q[, .(Date, Ticker, qlo, qhi)], RET, by = c("Date","Ticker"))
Q[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
say("꼬리 실현율(Ret_1m<=-20%%): 저-absorb %.3f%% / 고-absorb %.3f%% / 전체 %.3f%%",
    100*Q[qlo == TRUE, mean(tail_hit)], 100*Q[qhi == TRUE, mean(tail_hit)], 100*Q[, mean(tail_hit)])
D$tail_realization <- list(lo = Q[qlo == TRUE, mean(tail_hit)], hi = Q[qhi == TRUE, mean(tail_hit)],
  all = Q[, mean(tail_hit)], n_lo = Q[qlo == TRUE, .N], n_hi = Q[qhi == TRUE, .N],
  note = "NP2 tail_dn_prob_diff 의 배제-소비 유니버스(liq 통과 base 후보) 내 재현 확인용. 부호는 lo > hi 여야 NP2 정합.")

## 하락일 개인 순매수 (홀딩월)
IV <- as.data.table(read_parquet(".cache/investor_stock/investor_wide.parquet",
                                 col_select = c("Date","Ticker","Individual")))
IV[, Date := as.Date(Date)]
RW <- as.data.table(read_parquet(".cache/RAWDATA.parquet", col_select = c("Date","Ticker","Ret","Vol","Close")))
RW[, Date := as.Date(Date)]
DD <- merge(RW[is.finite(Ret) & Ret < 0, .(Date, Ticker, Vol, Close)], IV, by = c("Date","Ticker"))
DD[, hold_ym := format(Date, "%Y-%m")]
DN <- DD[, .(dn_flow = sum(Individual, na.rm = TRUE), dn_val = sum(Vol*Close, na.rm = TRUE), nd = .N),
         by = .(hold_ym, Ticker)]
QT <- Q[tail_hit == TRUE][, hold_ym := ym_add(format(Date, "%Y-%m"), 1L)]
QT <- merge(QT, DN, by = c("hold_ym","Ticker"))
QT <- QT[nd > 0 & is.finite(dn_val) & dn_val > 0, .(Date, Ticker, qlo, qhi, dnint = dn_flow/dn_val)]
f2 <- QT[, .(sp = mean(dnint[qlo]) - mean(dnint[qhi]), n_lo = sum(qlo), n_hi = sum(qhi)),
         by = Date][is.finite(sp) & n_lo >= 2 & n_hi >= 2]
f2_t <- nw_t(f2$sp)
f2_fired <- !isTRUE(f2_t < 0)      # 예측: 저 < 고 (t<0). t>=0 또는 NA = 구별 불가 → 발화
say("F2: 꼬리월 하락일 개인 순매수 강도 (저-absorb − 고-absorb): 월평균 %+.6f NW t=%+.3f n=%d → 발화 = %s",
    mean(f2$sp), f2_t, nrow(f2), f2_fired)
D$F2 <- list(spec = "꼬리 실현월(Ret_1m<=-20%) 하락일 개인 순매수/(하락일 거래대금) : 저-absorb − 고-absorb",
  mean_spread = mean(f2$sp), nw_t = f2_t, n_months = nrow(f2), fired = f2_fired,
  reading = if (f2_fired) "기전 기각 — 저-absorb 꼬리월의 개인 지지가 고-absorb 대비 약하지 않다" else "기전 지지 방향")

## ── ★기전 진단 A: NP2 우위가 base top-25 조건부로 살아남는가 (전이-벽 진단) ──
TOP <- merge(Wb[, .(Date, Ticker)], SMx[, .(Date, Ticker, excluded, absorb)], by = c("Date","Ticker"), all.x = TRUE)
TOP <- merge(TOP, RET, by = c("Date","Ticker"))
TOP[, tail_hit := is.finite(Ret_1m) & Ret_1m <= -0.20]
cond <- TOP[!is.na(excluded), .(n = .N, tail_rate = mean(tail_hit), mean_ret = mean(Ret_1m, na.rm = TRUE),
                                q10 = quantile(Ret_1m, 0.10, na.rm = TRUE)), by = excluded]
print(cond)
mt <- TOP[!is.na(excluded), .(sp = mean(Ret_1m[excluded], na.rm=TRUE) - mean(Ret_1m[!excluded], na.rm=TRUE),
                              n_e = sum(excluded)), by = Date][is.finite(sp) & n_e >= 1]
say("★조건부 진단: base top-25 **안에서** 배제대상 vs 잔류 월수익 차 = %+.5f/월 NW t=%+.3f (n=%d월)",
    mean(mt$sp), nw_t(mt$sp), nrow(mt))
D$conditional_on_top25 <- list(table = cond, mean_spread_monthly = mean(mt$sp), nw_t = nw_t(mt$sp),
  n_months = nrow(mt),
  reading = "양수 = 배제대상이 top-25 안에서 오히려 더 벌었다 = NP2 횡단면 우위가 고-score 조건부로 소멸/역전(전이-벽).")

## ── ★기전 진단 B: 배제대상의 규모 편향 (cap-w vs EW 갈림 설명) ─────────────
SZ <- merge(SMx[, .(Date, Ticker, excluded)], SIZE, by = c("Date","Ticker"))
SZ[, srank := frank(Size)/.N, by = Date]
szt <- SZ[, .(mean_srank_excl = mean(srank[excluded]), mean_srank_keep = mean(srank[!excluded])), by = Date]
say("규모 진단(전 후보): 배제대상 평균 size-백분위 %.3f vs 잔류 %.3f (NW t of diff = %+.3f)",
    mean(szt$mean_srank_excl), mean(szt$mean_srank_keep), nw_t(szt$mean_srank_excl - szt$mean_srank_keep))
SZt <- merge(Wb[, .(Date, Ticker, w)], SZ[, .(Date, Ticker, excluded, srank)], by = c("Date","Ticker"))
say("규모 진단(base top-25 내): 배제대상 평균 size-백분위 %.3f vs 잔류 %.3f | 배제대상 평균 비중 %.4f vs 잔류 %.4f",
    SZt[excluded == TRUE, mean(srank)], SZt[excluded == FALSE, mean(srank)],
    SZt[excluded == TRUE, mean(w)], SZt[excluded == FALSE, mean(w)])
D$size_bias <- list(all_excl_srank = mean(szt$mean_srank_excl), all_keep_srank = mean(szt$mean_srank_keep),
  top25_excl_srank = SZt[excluded == TRUE, mean(srank)], top25_keep_srank = SZt[excluded == FALSE, mean(srank)],
  top25_excl_meanw = SZt[excluded == TRUE, mean(w)], top25_keep_meanw = SZt[excluded == FALSE, mean(w)],
  reading = "배제대상이 top-25 안에서 **큰 비중**을 차지하면 cap-w basis 에서 손실이 증폭된다 — EW basis 와 갈리는 기전 후보.")

## ── MDD / calmar (PerformanceAnalytics 표준함수) ────────────────────────────
mkx <- function(r) xts(as.numeric(r$period_returns$ret_net), order.by = as.Date(r$period_returns$date))
mdd_b <- as.numeric(maxDrawdown(mkx(rb))); mdd_f <- as.numeric(maxDrawdown(mkx(rf)))
say("MDD(월간 net): base %.4f / filtered %.4f (Δ %+.2fpp) | calmar base %.3f filt %.3f",
    mdd_b, mdd_f, 100*(mdd_b - mdd_f), rb$abs_cagr/mdd_b, rf$abs_cagr/mdd_f)
D$mdd <- list(base = mdd_b, filtered = mdd_f, delta_pp = 100*(mdd_b - mdd_f),
  calmar_base = rb$abs_cagr/mdd_b, calmar_filtered = rf$abs_cagr/mdd_f,
  caveat = "월간 수익 기반 MDD — 일별 NAV 기반 forge MDD 와 다름(월간은 낙폭 과소추정). metric_type=weighted_screen.")

## ── prior-art 중복: MAX5 배제집합과의 교집합 + 한계 기여 ────────────────────
PANx <- as.data.table(read_parquet("stage_artifacts/WT_D20260802_010/ot_panel.parquet"))
PANx[, Date := as.Date(Date)]
MAX5 <- PANx[is.finite(max5), .(Date, Ticker, max5)]
MM <- merge(SMx[, .(Date, Ticker, sc, Size, adv, excluded_ab = excluded)], MAX5,
            by = c("Date","Ticker"), all.x = TRUE)
MM[, thr5 := { v <- max5[is.finite(max5)]
               if (length(v) >= 30L) quantile(v, 0.90, type = 7, names = FALSE) else Inf }, by = Date]
MM[, excluded_m5 := is.finite(max5) & max5 >= thr5]
ov <- MM[, .(n_ab = sum(excluded_ab), n_m5 = sum(excluded_m5),
             n_both = sum(excluded_ab & excluded_m5)), by = Date]
say("중복: absorb배제 월평균 %.1f / MAX5배제 %.1f / 교집합 %.1f → absorb배제 중 MAX5 중복 %.1f%%, 역 %.1f%%",
    ov[, mean(n_ab)], ov[, mean(n_m5)], ov[, mean(n_both)],
    100*ov[, sum(n_both)/sum(n_ab)], 100*ov[, sum(n_both)/sum(n_m5)])
D$overlap_with_max5 <- list(mean_n_absorb = ov[, mean(n_ab)], mean_n_max5 = ov[, mean(n_m5)],
  mean_n_both = ov[, mean(n_both)], share_of_absorb_in_max5 = ov[, sum(n_both)/sum(n_ab)],
  share_of_max5_in_absorb = ov[, sum(n_both)/sum(n_m5)])

cap_norm <- function(w){w[!is.finite(w)|w<0]<-0;if(sum(w)<=0)return(rep(1/length(w),length(w)));w<-w/sum(w)
  for(it in 1:50){if(all(w<=0.2000001))break;w[w>0.20]<-0.20;rem<-1-sum(w);ix<-w<0.20
    if(sum(ix)==0||rem<=0)break;w[ix]<-w[ix]+rem*w[ix]/sum(w[ix])};w[w>0.20]<-0.20;w/sum(w)}
top25_capw <- function(Sx){dd<-sort(unique(Sx$Date));W<-vector("list",length(dd))
  for(i in seq_along(dd)){sub<-Sx[Date==dd[i]];if(nrow(sub)<25)next;setorder(sub,-sc);hd<-head(sub,25)
    W[[i]]<-data.table(Date=dd[i],Ticker=hd$Ticker,w=cap_norm(hd$Size))};rbindlist(W)}
W_m5   <- top25_capw(MM[excluded_m5 == FALSE, .(Date,Ticker,sc,Size,adv)])
W_both <- top25_capw(MM[excluded_m5 == FALSE & excluded_ab == FALSE, .(Date,Ticker,sc,Size,adv)])
r_m5   <- weighted_screen_bt(W_m5, fwd_ret, bench, cost_bps_oneway = 15, run_id="WT009_m5", strategy_id="WT009_max5_only")
r_both <- weighted_screen_bt(W_both, fwd_ret, bench, cost_bps_oneway = 15, run_id="WT009_both", strategy_id="WT009_max5_plus_absorb")
say("한계기여: MAX5-only IR=%+.4f PORT_t=%+.3f | MAX5+absorb IR=%+.4f PORT_t=%+.3f → ΔIR_marginal=%+.4f",
    r_m5$information_ratio, r_m5$portfolio_alpha_t_nw_lag3,
    r_both$information_ratio, r_both$portfolio_alpha_t_nw_lag3,
    r_both$information_ratio - r_m5$information_ratio)
D$marginal_over_max5 <- list(ir_max5_only = r_m5$information_ratio, port_t_max5_only = r_m5$portfolio_alpha_t_nw_lag3,
  ir_max5_plus_absorb = r_both$information_ratio, port_t_max5_plus_absorb = r_both$portfolio_alpha_t_nw_lag3,
  delta_ir_marginal = r_both$information_ratio - r_m5$information_ratio,
  note = "MAX5-only 는 본 라운드 하네스/창(268m)에서의 재측정 — WT-014 원 수치(256m 공통월)와 창이 달라 직접 비교 금지.")

write_json(D, file.path(OUT, "11_diag.json"), auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null")
say("done")
