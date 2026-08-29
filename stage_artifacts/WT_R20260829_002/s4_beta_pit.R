# S4 — beta-통제 국면/지문 재검 · 기저 재현 대조 · PIT 하드게이트 (WT-R20260829_002)
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite); library(sandwich); library(lmtest)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd()
setwd(ROOT); Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
source(file.path(ROOT, "02_Infrastructure/config.R"))
source(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"))
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_002")
O <- readRDS(file.path(OUT, "s2_objects.rds")); O3 <- readRDS(file.path(OUT, "s3_objects.rds"))
P <- readRDS(file.path(OUT, "panel.rds"))
cells <- O$cells; B <- O3$B; LD <- O3$LD; PPY <- 12L

nwt <- function(x){x<-x[is.finite(x)]; m<-lm(x~1); as.numeric(coeftest(m,vcov=NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}

## 1. PIT 하드 게이트 — detect_lookahead(엔진)
pit <- detect_lookahead(file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"))
cat(sprintf("[S4][PIT] detect_lookahead clean=%s violations=%d\n",
            isTRUE(pit$clean), length(pit$violations %||% list())))

## 2. 활성수익의 alpha/beta 분해 (PORT_t 가 무엇을 섞는가 — measurement-graduation §2)
decomp <- rbindlist(lapply(names(cells), function(nm){
  pr <- cells[[nm]]$pr; f <- lm(pr$ret_net ~ pr$benchmark_ret)
  ct <- coeftest(f, vcov = NeweyWest(f, lag=3, prewhite=FALSE))
  a <- 12*ct[1,1]; b <- ct[2,1]; ebm <- 12*mean(pr$benchmark_ret)
  data.table(cell=nm, active_ann=12*mean(pr$ret_net-pr$benchmark_ret),
             alpha_ann=a, t_alpha=ct[1,3], beta=b, E_bm_ann=ebm,
             beta_contrib_ann=(b-1)*ebm,
             check=a+(b-1)*ebm, port_t=cells[[nm]]$port_t)}))

## 3. beta-통제 국면 잔차 (국면 효과에서 시장노출 제거)
resid_regime <- rbindlist(lapply(names(cells), function(nm){
  pr <- merge(cells[[nm]]$pr, B[, .(date=Date, regime)], by="date")
  f <- lm(ret_net ~ benchmark_ret, data=pr); pr[, e := residuals(f)]
  pr[, .(cell=nm, n=.N, resid_ann=12*mean(e), nw_t=nwt(e)), by=regime]}))
resid_wide <- dcast(resid_regime, regime ~ cell, value.var="resid_ann")
resid_t_wide <- dcast(resid_regime, regime ~ cell, value.var="nw_t")

## 4. 지문(a) beta-통제 — 숏 기여 ~ BM + recovery 더미 (시장방향 통제 후에도 반등월 특이?)
f_a <- lm(short_contrib ~ BM_Ret + is_rec, data=LD)
ct_a <- coeftest(f_a, vcov=NeweyWest(f_a, lag=3, prewhite=FALSE))
fp_a_ctl <- list(coef_recovery=as.numeric(ct_a["is_rec",1]), t_recovery=as.numeric(ct_a["is_rec",3]),
                 coef_bm=as.numeric(ct_a["BM_Ret",1]), t_bm=as.numeric(ct_a["BM_Ret",3]),
                 note="BM 수익 통제 후에도 recovery 계수가 음수·유의면 '패자 고베타' 로 환원되지 않는 반등월 특이 손실")
# 상승월 내부 대조 (expansion vs recovery — 둘 다 BM>0)
up_cmp <- LD[regime %in% c("expansion","recovery"),
             .(n=.N, bm_ann=12*mean(BM_Ret), short_contrib_ann=12*mean(short_contrib),
               lose_ann=12*mean(r_lose), win_ann=12*mean(r_win)), by=regime]

## 5. 기저 재현 대조 — cell1 에서 (a)유동성필터 (b)벤치 를 하나씩 되돌린다
FACTORS <- P$FACTORS; fwd <- P$fwd; R <- O$R
S_noliq <- FACTORS[, .(Date, Ticker, score=Score)]
cell_ls <- function(S, R, bench, frac=0.10, bpsv=15){
  SS <- copy(S); setorder(SS, Date, -score)
  W <- SS[, {n<-.N; k<-max(2L,as.integer(ceiling(n*frac)))
    if (n < 2L*k) list(Ticker=character(0), w=numeric(0)) else
    list(Ticker=c(Ticker[seq_len(k)], Ticker[(n-k+1L):n]), w=c(rep(1/k,k), rep(-1/k,k)))}, by=Date]
  W <- W[!is.na(Ticker)]
  WR <- merge(W, R[,.(Date,Ticker,Ret_1m)], by=c("Date","Ticker"), all.x=TRUE)
  WR[is.na(Ret_1m), Ret_1m:=0]
  port <- WR[, .(g=sum(w*Ret_1m)), by=Date]
  dts <- sort(unique(W$Date)); tr <- numeric(length(dts)); names(tr)<-as.character(dts)
  prev <- data.table(Ticker=character(0), w=numeric(0))
  for (i in seq_along(dts)){cur<-W[Date==dts[i],.(Ticker,w)]
    m<-merge(cur,prev,by="Ticker",all=TRUE,suffixes=c("_c","_p"))
    m[is.na(w_c),w_c:=0]; m[is.na(w_p),w_p:=0]; tr[i]<-sum(abs(m$w_c-m$w_p)); prev<-cur}
  port[, ret_net := g - tr[as.character(Date)]*bpsv/1e4]
  pr <- merge(port[,.(date=Date,ret_net)], bench[,.(date=Date,benchmark_ret=BM_Ret)], by="date")
  bc <- build_benchmark_compare(data.table(date=pr$date,ret_net=pr$ret_net,frequency="monthly"),
        data.table(date=pr$date,benchmark_ret=pr$benchmark_ret,benchmark_id="bm"),
        run_id="repro", strategy_id="repro", annualization_factor=PPY)
  list(pr=pr, port_t=as.numeric(bc[metric_name=="Portfolio_Alpha_t_NW_lag3", active_value][1]))
}
# KOSPI200 지수 벤치(기저 러너 규약) 월수익
BMM <- P$BMM[order(Date)]; BMM[, BM_Ret := BM_Close/shift(BM_Close)-1]
bm_idx <- BMM[is.finite(BM_Ret), .(Date, BM_Ret)]
bm_idx <- bm_idx[, .(Date=shift(Date, 1L, type="lead"), BM_Ret)][!is.na(Date)]  # 홀딩월 수익을 시그널일에 정렬
repro <- list(
  A_liqfilter_capwuniv_bench = cells$cell1_LS_decile$port_t,
  B_noliq_capwuniv_bench     = cell_ls(S_noliq, R, fwd$bench_dt)$port_t,
  C_noliq_kospi200_bench     = cell_ls(S_noliq, R, bm_idx)$port_t,
  D_liq_kospi200_bench       = cell_ls(O$S, R, bm_idx)$port_t,
  base_reported              = -1.291,
  note = "기저 RP_20260829_122020_9192 는 유동성필터 미적용 + KOSPI200 지수 벤치 + 일간 하네스. C 가 가장 가까운 대응.")

out <- list(pit_gate=list(clean=isTRUE(pit$clean), n_violations=length(pit$violations %||% list())),
            active_return_decomposition=decomp,
            beta_controlled_regime=list(resid_ann=resid_wide, resid_nw_t=resid_t_wide, long=resid_regime),
            fingerprint_a_beta_controlled=fp_a_ctl, up_month_contrast=up_cmp,
            base_reproduction=repro)
write_json(out, file.path(OUT, "s4_beta_pit.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")

cat("\n=== active = alpha + (beta-1)*E[bm] ===\n"); print(decomp)
cat("\n=== beta-통제 국면 잔차 (연환산) ===\n"); print(resid_wide)
cat("\n=== 그 NW-t ===\n"); print(resid_t_wide)
cat(sprintf("\n=== FP(a) BM 통제: recovery coef=%+.5f t=%+.3f | bm coef=%+.3f t=%+.2f\n",
            fp_a_ctl$coef_recovery, fp_a_ctl$t_recovery, fp_a_ctl$coef_bm, fp_a_ctl$t_bm))
cat("\n=== 상승월 내부 대조 (expansion vs recovery) ===\n"); print(up_cmp)
cat("\n=== 기저 재현 대조 (cell1 PORT_t) ===\n"); print(unlist(repro[1:5]))
