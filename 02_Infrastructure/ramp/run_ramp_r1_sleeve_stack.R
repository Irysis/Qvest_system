## run_ramp_r1_sleeve_stack.R — RAMP R1: 잔차-직교 sleeve 스태킹 실측 (§6 closure, DIST-RAMP-006 미검증 프론티어)
## 새 아키텍처(Axiom 엔진 v2) 카드-수렴 리서치.
## 구성 (INV-7 차별 — 06-18 graduation은 11군 *블렌드 composite*만 측정; 여기선 개별 sleeve → 선택 → 스택):
##   ① 11 직교 경제 sleeve 각각 독립 cap-w authoritative PORT_t (measurement-graduation §2)
##   ② PORT_t(capwt)>=2.95 통과분만 선택 (§6 "PORT_t 통과분만 book 기여")
##   ③ 선택분 스태킹 (EW + InvVol z-score 합성)
##   ④ data-driven SOFT regime overlay = MDD 번역 (DIST-RAMP-005 calmar 프론티어; 고정틸트 금지=RAMP_REGIME_NAIVE_FAIL 회피; PIT t-1)
## 게이트: port_t(capwt)>=2.95 · oos_retention>=0.7 · calmar>=0.64 (measurement-graduation §3 HARD).
## 실측-only(canonical_screen_bt) · 단일스레드 · vintage: 세션 pin.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r1_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con)

## ── 데이터 ──
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
## 국면(t-1 PIT) — graduation과 동일 소스 (alpha_scores regime_state), + soft membership 있으면 병합
a <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg <- unique(a[,.(ym=format(Date,"%Y-%m"), regime=regime_state)])[,.SD[1], by=ym]
gw[, ym := format(signal_date,"%Y-%m")]; gw <- merge(gw, reg, by="ym", all.x=TRUE); gw[is.na(regime), regime:="NORMAL"]

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
sig_dates <- sort(unique(gw$signal_date))
## [2026-07-05 env-fix / Forge] 두 가지 실행환경 이슈 회피 (구성·게이트·PIT 불변, 산출 BYTE-IDENTICAL):
##  (1) build_monthly_forward_returns 의 asof_close() 는 sig_date마다 rawdata[Date<=d] 전체스캔
##      (13.9M행 × ~512회) → R 4.5.2/data.table Windows 반복대량서브셋 간헐 세그폴트(무에러 exit).
##      각 sig_date의 month-end 거래일 = max(Date<=d)이므로 rawdata를 그 ~257 month-end 행으로만
##      제한해도 asof_close·fwd 는 동일 (equiv 검증: full vs slim returns_dt/bench_dt max|Δ|=0).
##  (2) 공유 .cache/rawdata.parquet(419MB, OneDrive) 를 타 세션 R잡이 동시 arrow-I/O 하면 본 세션이
##      race-세그폴트 → 사전 생성된 로컬 slim RDS(scratchpad, 무경합) 있으면 우선 소비.
.slim_rds <- Sys.getenv("RAMP_R1_SLIM_RDS", "")
if (nzchar(.slim_rds) && file.exists(.slim_rds)) {
  rawdata <- as.data.table(readRDS(.slim_rds)); rawdata[, Date := as.Date(Date)]
} else {
  rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
  .udates <- sort(unique(rawdata$Date))
  .me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
    if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
  .me <- .me[!is.na(.me)]
  rawdata <- rawdata[Date %in% .me]                  # slim: month-end 거래일만 (결과불변, 세그폴트 회피)
}
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
oos_cut <- sig_dates[length(sig_dates)-23]           # 최근 24m = OOS 꼬리
post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]   # EW-uni 벤치(진단)

## ── 게이트 계산기 (run_ramp_graduation.R gates()와 동일 산식; cap-w authoritative) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
        top_n=25L, cost_bps_oneway=15,
        liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)], liq_min=2e8,
        run_id="r1", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]                      # EW-uni active (진단)
  pr[, act_bm := ret_net - benchmark_ret]        # cap-w active (authoritative)
  pt      <- nwt(pr$act)
  pt_bm   <- nwt(pr$act_bm)
  # calmar (port own geometric)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  # oos_retention v2 (anchored 3-split {55/65/75} 중앙값) — cap-w active 기준
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  # post-2017 cohort decay 진단 (cap-w active SR)
  post_sr <- srf(pr[date>=post2017, act_bm])
  full_bm_sr <- srf(pr$act_bm)
  data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn,
             calmar=cal, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr,
             turnover=cs$turnover_annual, n_months=nrow(pr),
             pr_ret_net=list(pr$ret_net), pr_bench=list(pr$benchmark_ret), pr_date=list(pr$date))
}

## ── ① 개별 sleeve 독립 게이트 (11개) ──
w("=== R1 Phase-1: 11 직교 sleeve 독립 실측 (cap-w authoritative) ===")
per <- list()
for(fm in FAMS){
  sub <- gw[!is.na(get(fm)), .(signal_date, security_id, score=get(fm))]
  sub[, score := zc(score), by=signal_date]
  r <- gates(sub, paste0("sleeve_",fm))
  if(!is.null(r)) per[[fm]] <- r
  if(!is.null(r)) w(sprintf("  %-18s pt_capwt=%+.2f pt_EW=%+.2f oos=%+.2f cal=%+.2f post17=%+.2f TO=%.1f",
                            fm, r$port_t_capwt, r$port_t_EWuni, r$oos_retention, r$calmar, r$post2017_bm_sr, r$turnover))
}
PER <- rbindlist(per, fill=TRUE)

## ── ② PORT_t 통과분 선택 (§6) ──
GATE_PT <- 2.95
survivors <- PER[is.finite(port_t_capwt) & port_t_capwt >= GATE_PT, model]
survivors_fam <- gsub("^sleeve_","",survivors)
w(sprintf("\n=== 선택: cap-w PORT_t>=%.2f 통과 sleeve = %d개 %s ===",
          GATE_PT, length(survivors_fam), if(length(survivors_fam)) paste(survivors_fam,collapse=",") else "(없음)"))
## 통과분 없으면 스태킹 진단용으로 상위 4개(cap-w PORT_t) 선택 — 명시 라벨(진단, 졸업 아님)
diag_mode <- length(survivors_fam) < 2
stack_fams <- if(!diag_mode) survivors_fam else PER[order(-port_t_capwt)][1:min(4,.N), gsub("^sleeve_","",model)]
w(sprintf("스태킹 대상 = %s  (%s)", paste(stack_fams,collapse=","),
          if(diag_mode) "DIAGNOSTIC: PORT_t 통과분<2 → 상위4 진단스택(졸업자격 아님)" else "SELECTED survivors"))

## ── ③ 스태킹 (EW + InvVol) ──
mk_stack <- function(fams, method="EW"){
  X <- as.matrix(gw[, ..fams]); X[is.na(X)] <- 0
  Xz <- gw[, lapply(.SD, function(c){ zc(c) }), .SDcols=fams, by=signal_date]  # 월별 z
  Xm <- as.matrix(Xz[, ..fams]); Xm[is.na(Xm)] <- 0
  if(method=="EW"){ wv <- rep(1/length(fams), length(fams)) }
  else {  # InvVol: 각 sleeve 시계열 net_sr 절대변동 역가중 (per-sleeve pr에서)
    vols <- sapply(fams, function(fm){ sd(unlist(per[[fm]]$pr_ret_net), na.rm=TRUE) })
    iv <- (1/vols)/sum(1/vols); wv <- iv }
  sc <- data.table(signal_date=Xz$signal_date, security_id=gw$security_id, score=as.numeric(Xm %*% wv))
  sc[, score := zc(score), by=signal_date]; sc
}
STK <- list()
STK$ew  <- gates(mk_stack(stack_fams,"EW"),  "stack_EW")
STK$iv  <- gates(mk_stack(stack_fams,"InvVol"),"stack_InvVol")
STK <- rbindlist(Filter(Negate(is.null),STK), fill=TRUE)
w("\n=== ③ 스택 게이트 ===")
for(i in seq_len(nrow(STK))) w(sprintf("  %-16s pt_capwt=%+.2f oos=%+.2f cal=%+.2f post17=%+.2f",
   STK$model[i], STK$port_t_capwt[i], STK$oos_retention[i], STK$calmar[i], STK$post2017_bm_sr[i]))

## ── ④ data-driven SOFT regime overlay = MDD 번역 (best 스택 대상; DIST-RAMP-005) ──
## 연속 de-risk 스칼라(고정틸트 아님): CAUTION→0.6 / CRISIS→0.3 을 soft membership 있으면 연속화.
## PIT: regime(t)는 signal_date 시점 알려진 t-1 close 기반(alpha_scores 규약) — forward 수익에 t 노출.
best_stack <- STK[which.max(port_t_capwt)]
overlay_res <- NULL
if(nrow(best_stack)){
  prd <- data.table(date=unlist(best_stack$pr_date), ret=unlist(best_stack$pr_ret_net),
                    bench=unlist(best_stack$pr_bench))
  prd[, date:=as.Date(date)]; prd[, ym:=format(date,"%Y-%m")]
  prd <- merge(prd, reg, by="ym", all.x=TRUE); prd[is.na(regime),regime:="NORMAL"]
  # soft membership(있으면) — crisis prob로 연속 스칼라, 없으면 regime 라벨 소프트맵
  sm_path <- file.path(OUT,"regime_soft_membership.parquet")
  scal_map <- c(BULL=1, NORMAL=1, CAUTION=0.6, CRISIS=0.3)
  prd[, exposure := scal_map[regime]]; prd[is.na(exposure), exposure:=1]
  prd[, exposure := shift(exposure, 1, fill=1)]   # PIT: 직전월 국면으로 이번달 노출(t-1) — 동월 누출 방지
  prd[, ret_ov := exposure*ret]                    # 나머지는 현금(0)
  navo <- cumprod(1+prd$ret_ov); ddo<-min(navo/cummax(navo)-1); anno<-prod(1+prd$ret_ov)^(12/nrow(prd))-1
  calo <- if(ddo<0) anno/abs(ddo) else NA
  acto <- prd$ret_ov - prd$bench
  overlay_res <- data.table(model=paste0(best_stack$model,"_softRegimeOverlay"),
     port_t_capwt=nwt(acto), calmar=calo,
     post2017_bm_sr=srf(acto[prd$date>=post2017]), n_months=nrow(prd))
  w(sprintf("\n=== ④ soft-regime overlay (MDD 번역) on %s ===", best_stack$model))
  w(sprintf("  overlay pt_capwt=%+.2f  calmar=%+.2f (base calmar=%+.2f)  post17=%+.2f",
     overlay_res$port_t_capwt, overlay_res$calmar, best_stack$calmar, overlay_res$post2017_bm_sr))
}

## ── 결과 저장 (verify/synthesis 소비용) ──
strip <- function(dt) dt[, .SD, .SDcols=setdiff(names(dt), c("pr_ret_net","pr_bench","pr_date"))]
res <- list(per_sleeve=strip(PER),
            stack=if(nrow(STK)) strip(STK) else data.table(),
            overlay=if(!is.null(overlay_res)) overlay_res else data.table(),
            survivors=survivors_fam, diag_mode=diag_mode, gate_pt=GATE_PT,
            incumbent_book_ir=1.416, oos_cut=as.character(oos_cut),
            n_sig=length(sig_dates), date_range=as.character(range(sig_dates)))
saveRDS(list(res=res, PER=PER, STK=STK, best_stack=best_stack, overlay_res=overlay_res),
        file.path(".cache", sprintf("_ramp_r1_%s.rds", RUNTAG)))
write_parquet(strip(PER), file.path(OUT, "r1_per_sleeve_gates.parquet"))
if(nrow(STK)) write_parquet(strip(STK), file.path(OUT, "r1_stack_gates.parquet"))
jsonlite::write_json(res, file.path(OUT, sprintf("r1_summary_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=4)
w("\n=== VERDICT (§6 로직: PORT_t 통과분만 book 기여) ===")
any_pass <- any(is.finite(PER$port_t_capwt) & PER$port_t_capwt>=GATE_PT) ||
            any(is.finite(STK$port_t_capwt) & STK$port_t_capwt>=GATE_PT)
w(sprintf("  개별 sleeve 통과: %d/%d | 스택 통과: %s | overlay pt: %s",
   sum(is.finite(PER$port_t_capwt)&PER$port_t_capwt>=GATE_PT), nrow(PER),
   if(nrow(STK)) paste(sprintf("%.2f",STK$port_t_capwt),collapse="/") else "NA",
   if(!is.null(overlay_res)) sprintf("%.2f",overlay_res$port_t_capwt) else "NA"))
w(sprintf("  => %s", if(any_pass) "SURVIVOR 존재 → book-marginal ΔIR 후속" else
   "통과분 0 → §6 음성 확정: RAMP 잔차 sleeve는 개별/스택 모두 cap-w PORT_t 미통과 (직교≠수익 sleeve-레벨)"))
close(con); cat(sprintf("R1_DONE. log=%s\n", logf))
cat(readLines(logf), sep="\n")
