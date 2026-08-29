## p8_universe_v2.R — universe 민감도 진단 (L-227 mandate: ICIR 0.089 < 0.15 → v2 비교 의무)
## ★고정 축은 K200∪KQ150 이다 — 본 스크립트는 **판정을 바꾸지 않는 진단**이며,
##   묻는 것 하나: T2 의 powered null(이익 축이 가격 축에 포섭)이 universe-restricted 아티팩트인가.
## ★라벨 정직성: build_universe_v2() 는 sig_date 마다 rawdata 전체를 재읽어 260회 호출이 불가하다.
##   그 함수의 Option A 는 free-float 결측 시 Size 랭킹으로 폴백하므로, 여기서는 동일 랭킹 기준을
##   1회 읽기로 인라인 구현하고 라벨을 'KR_TOP500_MKTCAP_inline' 으로 **다르게** 붙인다
##   (계약 라벨 KR_TOP500_FREEFLOAT 를 참칭하지 않는다).
suppressPackageStartupMessages({library(data.table); library(arrow); library(jsonlite)
                                library(sandwich); library(lmtest)})
setDTthreads(2)
QM <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/factor_db/factor_db_connector.R")
source(file.path(QM,"02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(QM,"02_Infrastructure/contracts/canonical_screen_bt.R"))

OUT <- "stage_artifacts/WT_R20260829_001"
NQ <- 3L; TOP_N <- 25L; LIQ_MIN <- 2e8
COST <- 20   # v2 universe 권고 비용(FREEFLOAT=20bps) — mandate_compliance_check 정합

.nwt <- function(x, lag=3L){ x <- x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,3]) }
.nwse <- function(x, lag=3L){ x <- x[is.finite(x)]; if(length(x)<12L) return(NA_real_)
  m <- lm(x ~ 1); as.numeric(coeftest(m, vcov=NeweyWest(m, lag=lag, prewhite=FALSE))[1,2]) }

RET   <- as.data.table(read_parquet(file.path(OUT,"panel_returns.parquet")))[, Date := as.Date(Date)]
BENCH <- as.data.table(read_parquet(file.path(OUT,"panel_bench.parquet")))[, Date := as.Date(Date)]
LIQ   <- as.data.table(read_parquet(file.path(OUT,"panel_liq.parquet")))[, Date := as.Date(Date)]
setattr(LIQ, "liq_ruler", "adv20_t1")
ME <- sort(unique(as.data.table(read_parquet(file.path(OUT,"pit_asof.parquet")))$Date))
ME <- as.Date(ME)

## ── v2 유니버스: 각 sig_date 시총(Size) 상위 500 (rawdata 1회 읽기) ────────────
RAW <- as.data.table(read_parquet(".cache/rawdata.parquet",
        col_select=c("Date","Ticker","Size","K200","KQ150")))[, Date := as.Date(Date)]
RAWME <- RAW[Date %in% ME & is.finite(Size) & Size > 0]; rm(RAW); invisible(gc())
setorder(RAWME, Date, -Size)
RAWME[, rk := seq_len(.N), by=Date]
U2 <- RAWME[rk <= 500L, .(Date, Ticker, Size, rk)]
cat(sprintf("[p8] v2 유니버스 월 중앙 %d종목 | K200/KQ150 대비 신규 편입 중앙 %d종목\n",
    as.integer(median(U2[,.N,by=Date]$N)),
    as.integer(median(merge(U2, RAWME[, .(Date,Ticker,inK=(!is.na(K200)&K200==1)|(!is.na(KQ150)&KQ150==1))],
                            by=c("Date","Ticker"))[inK==FALSE, .N, by=Date]$N))))

## ── 팩터 패널 (유니버스 무제한, 2팩터만) ────────────────────────────────────
FL <- rbindlist(lapply(ME, function(d){
  x <- tryCatch(load_month_factors(d, coverage_min=0, factor_names=c("M02_Mom_6_1","C01_SUE")),
                error=function(e) NULL)
  if (is.null(x) || nrow(x)==0) return(NULL)
  as.data.table(x)[, .(Date=d, Ticker, Factor_Name, z=Z_Score_Aligned)]
}), fill=TRUE)
FW2 <- dcast(FL, Date + Ticker ~ Factor_Name, value.var="z")
FW2 <- merge(FW2, U2, by=c("Date","Ticker"))
FW2 <- merge(FW2, LIQ, by=c("Date","Ticker"), all.x=TRUE)

E <- FW2[is.finite(M02_Mom_6_1) & is.finite(C01_SUE) & (is.na(adv) | adv >= LIQ_MIN)]
E[, n_m := .N, by=Date]; E <- E[n_m >= 30L]
E[, pm := (frank(M02_Mom_6_1, ties.method="average")-0.5)/.N, by=Date]
E[, ps := (frank(C01_SUE,     ties.method="average")-0.5)/.N, by=Date]
E[, tm := pmin(NQ, floor(pm*NQ)+1L)]; E[, ts := pmin(NQ, floor(ps*NQ)+1L)]
cat(sprintf("[p8] v2 자격 %d행 / %d월 | 월 중앙 %d종목 (v1 은 288)\n",
    nrow(E), uniqueN(E$Date), as.integer(median(E[,.N,by=Date]$N))))

EM <- merge(E, RET, by=c("Date","Ticker"))
cr <- EM[, .(r=mean(Ret_1m,na.rm=TRUE), n=.N), by=.(Date,tm,ts)]
sl <- function(ctrl, targ){
  hi <- cr[cr[[targ]]==NQ]; lo <- cr[cr[[targ]]==1L]
  m <- merge(hi[, .(Date, L=get(ctrl), r_hi=r, n_hi=n)], lo[, .(Date, L=get(ctrl), r_lo=r, n_lo=n)],
             by=c("Date","L"))[n_hi>=5L & n_lo>=5L]
  m[, sp := r_hi - r_lo][] }
T1 <- sl("ts","tm"); T2 <- sl("tm","ts")
sm <- function(D){ per <- D[, .(nw_t=.nwt(sp), ann=12*mean(sp), n=.N), by=L][order(L)]
  a <- D[, .(sp=mean(sp)), by=Date]
  list(per_layer=per, avg=list(n=nrow(a), monthly=mean(a$sp), ann=12*mean(a$sp),
       nw_t=.nwt(a$sp), nw_se=.nwse(a$sp))) }
R1 <- sm(T1); R2 <- sm(T2)
cat("\n[v2] T1 (SUE 층 통제 후 가격 스프레드) 층별 NW-t:", sprintf("%.3f", R1$per_layer$nw_t),
    sprintf("| 층평균 연 %.2f%% NW-t %.3f", 100*R1$avg$ann, R1$avg$nw_t), "\n")
cat("[v2] T2 (가격 층 통제 후 SUE 스프레드) 층별 NW-t:", sprintf("%.3f", R2$per_layer$nw_t),
    sprintf("| 층평균 연 %.2f%% NW-t %.3f", 100*R2$avg$ann, R2$avg$nw_t), "\n")
pw <- function(res, implied){ se <- res$avg$nw_se; mde <- 2.8016*se; r <- implied/mde
  list(mde80=mde, ratio=r, expected_t=r*2.8016, power=pnorm(r*2.8016-1.96)) }
P1 <- pw(R1, 0.031/6); P2 <- pw(R2, 0.043/6)
cat(sprintf("[v2] 크기산술 T1 ratio %.4f 검정력 %.1f%% | T2 ratio %.4f 검정력 %.1f%%\n",
    P1$ratio, 100*P1$power, P2$ratio, 100*P2$power))

## Fama-MacBeth
FM <- EM[is.finite(Size) & Size>0][, lsz := log(Size)]
fmb <- FM[, { f <- try(lm(Ret_1m ~ pm + ps + lsz), silent=TRUE)
              if (inherits(f,"try-error")) NULL else as.list(coef(f)) }, by=Date]
cat(sprintf("[v2] Fama-MacBeth b(price)=%.4f t=%.3f · b(SUE)=%.5f t=%.3f (n=%d월)\n",
    mean(fmb$pm), .nwt(fmb$pm), mean(fmb$ps), .nwt(fmb$ps), nrow(fmb)))

## ICIR (attenuation 진단의 본체)
SR <- merge(E[, .(Date,Ticker,sc=pmin(pm,ps),pm,ps)], RET, by=c("Date","Ticker"))
icf <- function(col){ s <- SR[is.finite(get(col)) & is.finite(Ret_1m),
    .(ic=suppressWarnings(cor(get(col),Ret_1m,method="spearman")), n=.N), by=Date][n>=30]
  c(rank_ic=mean(s$ic,na.rm=TRUE), icir=mean(s$ic,na.rm=TRUE)/sd(s$ic,na.rm=TRUE), t=.nwt(s$ic)) }
IC <- list(joint=icf("sc"), mom=icf("pm"), sue=icf("ps"))
cat(sprintf("[v2] rank-IC joint %.4f (ICIR %.3f) | mom %.4f (%.3f) | sue %.4f (%.3f)\n",
    IC$joint[1],IC$joint[2],IC$mom[1],IC$mom[2],IC$sue[1],IC$sue[2]))

## canonical arm (v2 권고 비용 20bps)
arms <- list(joint2way = E[tm==NQ & ts==NQ, .(Date,Ticker,score=pmin(pm,ps))],
             mom_only  = E[, .(Date,Ticker,score=pm)],
             sue_only  = E[, .(Date,Ticker,score=ps)])
CSV <- list()
for (nm in names(arms)) {
  y <- tryCatch(canonical_screen_bt(arms[[nm]], RET, BENCH, top_n=TOP_N, cost_bps_oneway=COST,
        liq_dt=LIQ, liq_min=LIQ_MIN, size_dt=U2[, .(Date,Ticker,Size)],
        run_id="p8_v2", strategy_id=paste0(nm,"_v2"), diag_dual_basis=TRUE),
        error=function(e){cat("[ERR]",nm,conditionMessage(e),"\n"); NULL})
  if (is.null(y)) next
  CSV[[nm]] <- list(n_months=y$n_months, port_t=y$portfolio_alpha_t_nw_lag3,
    pvalue=y$portfolio_alpha_t_pvalue, alpha_ann=y$alpha_annualized, IR=y$information_ratio,
    turnover=y$turnover_annual,
    ew_universe_port_t=y$diag_ew_universe$portfolio_alpha_t_nw_lag3)
  cat(sprintf("[v2 arm] %-10s n=%d PORT_t %7.3f (p %.3f) alpha %6.2f%%/yr | EW-벤치 PORT_t %7.3f\n",
    nm, y$n_months, y$portfolio_alpha_t_nw_lag3, y$portfolio_alpha_t_pvalue,
    100*y$alpha_annualized, y$diag_ew_universe$portfolio_alpha_t_nw_lag3))
}

write_json(list(
  label = "KR_TOP500_MKTCAP_inline",
  label_honesty_note = "계약 라벨 KR_TOP500_FREEFLOAT 가 아니다 — build_universe_v2() 는 sig_date 마다 rawdata 전체를 재읽어 260회 호출이 비현실적이라, 그 함수 Option A 의 free-float 결측 폴백(Size 랭킹)과 동일 기준을 1회 읽기로 인라인 구현했다. free-float 조정 미적용.",
  cost_bps = COST, cost_rationale = "v2 universe 권고 20bps (mandate_compliance_check 정합)",
  n_names_median = as.integer(median(E[,.N,by=Date]$N)),
  T1 = R1, T2 = R2, power_T1 = P1, power_T2 = P2,
  fama_macbeth = list(n_months=nrow(fmb), b_price=mean(fmb$pm), t_price=.nwt(fmb$pm),
                      b_sue=mean(fmb$ps), t_sue=.nwt(fmb$ps)),
  ic = IC, arms = CSV
), file.path(OUT,"universe_comparison.json"), auto_unbox=TRUE, na="null", digits=6)
cat("[p8] DONE\n")
