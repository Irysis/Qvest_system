## run_ramp_r2_topn.R — RAMP R2 Track A: envelope-안 top-N 민감도 실측
## 질문: top_n ∈ {15,20,25} (비용 15bps 고정, 종목수<=25) 로 바꾸면
##       개별 sleeve 또는 스택(상위4 EW) 중 cap-w PORT_t>=2.95 넘는 게 생기나?
## ★제약 방화벽: 비용 15bps 고정(완화 금지), 종목수 <=25만(N∈{15,20,25}), 게이트 2.95 불변.
## R1 (run_ramp_r1_sleeve_stack.R) 검증된 gates()/canonical_screen_bt 패턴 복제.
## gates()의 top_n=25L 를 파라미터화 → N 루프. 그 외 구성·PIT·산식 R1과 BYTE-호환.
## 실측-only(canonical_screen_bt) · 단일스레드 · vintage: 세션 pin. Forge (RAMP 백테=forge).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)  # io=2 (1 금지)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r2_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)

N_GRID <- c(15L, 20L, 25L)   # envelope: 종목수 <=25만
GATE_PT <- 2.95              # cap-w authoritative (불변)

## ── 데이터 (R1과 동일 소스) ──
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
a <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg <- unique(a[,.(ym=format(Date,"%Y-%m"), regime=regime_state)])[,.SD[1], by=ym]
gw[, ym := format(signal_date,"%Y-%m")]; gw <- merge(gw, reg, by="ym", all.x=TRUE); gw[is.na(regime), regime:="NORMAL"]

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
sig_dates <- sort(unique(gw$signal_date))
## R1 env-fix 재사용 (세그폴트/race 회피, 결과불변):
.slim_rds <- Sys.getenv("RAMP_R1_SLIM_RDS", "")
if (nzchar(.slim_rds) && file.exists(.slim_rds)) {
  rawdata <- as.data.table(readRDS(.slim_rds)); rawdata[, Date := as.Date(Date)]
  w(sprintf("[slim] RDS 소비: %s", .slim_rds))
} else {
  rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
  .udates <- sort(unique(rawdata$Date))
  .me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
    if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
  .me <- .me[!is.na(.me)]
  rawdata <- rawdata[Date %in% .me]                  # slim: month-end 거래일만 (결과불변, 세그폴트 회피)
  w(sprintf("[slim] rawdata month-end 제한: %d rows / %d dates", nrow(rawdata), length(.me)))
}
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
oos_cut <- sig_dates[length(sig_dates)-23]
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]

## ── 게이트 계산기 (R1 gates()와 동일, top_n 파라미터화) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab, top_n){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
        top_n=top_n, cost_bps_oneway=15,          # ★15bps 고정 (완화 금지)
        liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)], liq_min=2e8,
        run_id="r2", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]
  pr[, act_bm := ret_net - benchmark_ret]        # cap-w active (authoritative)
  pt      <- nwt(pr$act)
  pt_bm   <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  post_sr <- srf(pr[date>=post2017, act_bm])
  full_bm_sr <- srf(pr$act_bm)
  data.table(top_n=top_n, model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn,
             calmar=cal, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr,
             turnover=cs$turnover_annual, n_months=nrow(pr))
}

## ── 스택 스코어 빌더 (R1 mk_stack EW; stack_fams 고정 인자) ──
mk_stack <- function(fams){
  Xz <- gw[, lapply(.SD, function(c){ zc(c) }), .SDcols=fams, by=signal_date]  # 월별 z
  Xm <- as.matrix(Xz[, ..fams]); Xm[is.na(Xm)] <- 0
  wv <- rep(1/length(fams), length(fams))                                      # EW
  sc <- data.table(signal_date=Xz$signal_date, security_id=gw$security_id, score=as.numeric(Xm %*% wv))
  sc[, score := zc(score), by=signal_date]; sc
}

## ── N 루프: 11 sleeve + 스택(상위4 EW) ──
## 스택 대상 fams 선정 규칙 = R1과 동일(상위4 cap-w PORT_t). N별로 재선정하되, 참조 일관성 위해
##   (a) N-재선정 top-4 스택 + (b) R1(N=25) 고정 top-4 스택 둘 다 측정 → 어느 것이든 2.95 넘나 확인.
R1_STACK_FAMS <- c("Consensus","Value","Growth_Profit","Momentum")   # R1 진단스택 (N=25 기준)

all_sleeve <- list(); all_stack <- list()
for(N in N_GRID){
  w(sprintf("\n######## top_n = %d ########", N))
  ## ① 개별 sleeve
  per <- list()
  for(fm in FAMS){
    sub <- gw[!is.na(get(fm)), .(signal_date, security_id, score=get(fm))]
    sub[, score := zc(score), by=signal_date]
    r <- gates(sub, paste0("sleeve_",fm), N)
    if(!is.null(r)) per[[fm]] <- r
    if(!is.null(r)) w(sprintf("  %-16s pt_capwt=%+.2f pt_EW=%+.2f oos=%+.2f cal=%+.2f post17=%+.2f TO=%.1f",
                              fm, r$port_t_capwt, r$port_t_EWuni, r$oos_retention, r$calmar, r$post2017_bm_sr, r$turnover))
  }
  PER <- rbindlist(per, fill=TRUE)
  all_sleeve[[as.character(N)]] <- PER

  ## ② 스택: (a) N-재선정 top-4 cap-w PORT_t
  topN_fams <- PER[order(-port_t_capwt)][1:min(4,.N), gsub("^sleeve_","",model)]
  sa <- gates(mk_stack(topN_fams), "stack_EW_topNsel", N)
  ## (b) R1 고정 top-4
  sb <- gates(mk_stack(R1_STACK_FAMS), "stack_EW_R1fixed", N)
  st <- rbindlist(Filter(Negate(is.null), list(sa,sb)), fill=TRUE)
  if(nrow(st)){
    st[, stack_fams := c(if(!is.null(sa)) paste(topN_fams,collapse=",") else NULL,
                         if(!is.null(sb)) paste(R1_STACK_FAMS,collapse=",") else NULL)]
    for(i in seq_len(nrow(st))) w(sprintf("  %-18s pt_capwt=%+.2f oos=%+.2f cal=%+.2f post17=%+.2f  [%s]",
       st$model[i], st$port_t_capwt[i], st$oos_retention[i], st$calmar[i], st$post2017_bm_sr[i], st$stack_fams[i]))
  }
  all_stack[[as.character(N)]] <- st
}

SLEEVE <- rbindlist(all_sleeve, fill=TRUE)
STACK  <- rbindlist(all_stack,  fill=TRUE)

## ── 2.95 초과 config 강조 ──
w("\n=== 2.95 초과 스캔 (cap-w PORT_t authoritative) ===")
pass_sleeve <- SLEEVE[is.finite(port_t_capwt) & port_t_capwt >= GATE_PT]
pass_stack  <- STACK[is.finite(port_t_capwt) & port_t_capwt >= GATE_PT]
if(nrow(pass_sleeve)) for(i in seq_len(nrow(pass_sleeve)))
  w(sprintf("  ★PASS sleeve  N=%d %-16s pt_capwt=%+.2f oos=%+.2f cal=%+.2f",
    pass_sleeve$top_n[i], pass_sleeve$model[i], pass_sleeve$port_t_capwt[i], pass_sleeve$oos_retention[i], pass_sleeve$calmar[i]))
if(nrow(pass_stack)) for(i in seq_len(nrow(pass_stack)))
  w(sprintf("  ★PASS stack   N=%d %-18s pt_capwt=%+.2f oos=%+.2f cal=%+.2f",
    pass_stack$top_n[i], pass_stack$model[i], pass_stack$port_t_capwt[i], pass_stack$oos_retention[i], pass_stack$calmar[i]))
any_pass <- (nrow(pass_sleeve)+nrow(pass_stack)) > 0
if(!any_pass) w("  (없음) — 어떤 (N, 구성)도 cap-w PORT_t 2.95 미달")

## ── N별 best 요약표 ──
w("\n=== N별 best (개별 sleeve 최고 + 스택 최고) ===")
for(N in N_GRID){
  sl <- SLEEVE[top_n==N]; sk <- STACK[top_n==N]
  bs <- sl[which.max(port_t_capwt)]; bk <- sk[which.max(port_t_capwt)]
  w(sprintf("  N=%2d | best sleeve %-14s pt=%+.2f | best stack %-18s pt=%+.2f",
    N, gsub("^sleeve_","",bs$model), bs$port_t_capwt,
    bk$model, bk$port_t_capwt))
}

## ── 저장 ──
write_parquet(SLEEVE, file.path(OUT, "r2_topn_sleeve_gates.parquet"))
write_parquet(STACK,  file.path(OUT, "r2_topn_gates.parquet"))
res <- list(
  n_grid = N_GRID, gate_pt = GATE_PT, cost_bps_oneway = 15,
  sleeve = SLEEVE, stack = STACK,
  any_pass = any_pass,
  pass_configs = if(any_pass) rbind(pass_sleeve[,.(top_n,model,port_t_capwt,oos_retention,calmar)],
                                    pass_stack[,.(top_n,model,port_t_capwt,oos_retention,calmar)], fill=TRUE) else data.table(),
  r1_baseline_note = "R1(N=25): best sleeve Consensus pt_capwt=2.07, stack_EW=2.54, all<2.95",
  n_sig = length(sig_dates), date_range = as.character(range(sig_dates)),
  vintage_pin = "session_2026-07-05"
)
jsonlite::write_json(res, file.path(OUT, sprintf("r2_topn_summary_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)

w("\n=== VERDICT ===")
w(sprintf("  N∈{15,20,25} × (11 sleeve + 2 stack variant): 2.95 초과 = %s", if(any_pass) "존재" else "0건"))
w(sprintf("  => top-N 민감도로 R1 음성 결론이 %s",
   if(any_pass) "뒤집힘 (survivor 존재 → book-marginal 후속)" else
   "뒤집히지 않음 (음성 유지 — envelope-안 top-N 축은 2.95 벽 못 넘음)"))
close(con); cat(sprintf("R2_DONE. log=%s any_pass=%s\n", logf, any_pass))
cat(readLines(logf), sep="\n")
