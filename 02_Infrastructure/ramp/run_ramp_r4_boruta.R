## run_ramp_r4_boruta.R — RAMP R4: Boruta all-relevant 팩터-존 축소 팩터 로테이션 (arm S 정적 1차)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-11: "보루타 알고리즘을 이용한 팩터 로테이션 모델도 구현해봐, RAMP 써도 되고"
##
## [novelty triage] 재료=기존 factor DB return-파생 11 직교 경제군(R1/R2와 동일 substrate, 기존).
##   그리드=RAMP 배분(기존). 기전=Boruta all-relevant 선별(shadow-feature null 통제) = 신규.
##   hypothesis_index Boruta 0건(XGB/lightgbm/HGB/NGBoost/attention은 예측기였지 선별-규율 아님).
##   차별 = "어떤 팩터군이 무작위 그림자보다 정보가 있는가"의 원리적 factor-zoo 축소(research_philosophy ①).
##   ⚠ regime-조건부(arm R)는 settled(L-QPM-20260705_105130 FAIL·DIST-RAMP-003 screen-tier) —
##     kill gate로 통제(arm S 선별 실효+방향 양+paired>=2.0일 때만 착수).
##
## [설계] Arm S = 정적 Boruta factor-zoo 축소 배분 (regime 조건 없음, 순수 선별-규율 테스트):
##   rolling 학습창(36/60월, C1 trailing-only) → Boruta(RF + shadow features, Confirmed only) →
##   confirmed 팩터군 집합 → 배분(EW / IC-가중 2형). 총 arm S = 2창 × 2가중 = 4 config(사전등록).
##   base(control, 비-trial) = all-11 {EW, ICW} walk-forward.
##
## [측정 규율] cap-w authoritative(R1/R2 gates() 복제) + HARD 3종 + 2017+ 분리 + DSR(sweep n=4).
##   base 대비 paired NW-t(lag3, 가중 매칭). 실측-only(canonical_screen_bt). PIT: 학습창 trailing-only.
##   선별 실효 검증: confirmed 집합 크기 시계열 + turnover(전 팩터 confirmed면 선별 무의미 정직보고).
##
## [KILL 사전등록] arm S 전 config가 base 대비 paired < 2.0 → "shadow-null 선별도 배분 개선 불가" 확정.
##   arm R 착수 = arm S에서 선별 실효(팩터 실제 거름 + 방향 양) + paired>=2.0 보일 때만.
##
## 실측-only · 단일스레드 · vintage: 세션 pin. Forge (RAMP 백테=forge).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(Boruta); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- format(Sys.Date(),"%Y%m%d")
logf <- file.path(".cache", sprintf("_ramp_r4_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...) writeLines(paste0(...),con); wf<-function(...){w(sprintf(...))}

## ── 사전등록 config (hash 고정) ──
BORUTA <- list(nmax=3000L, ntree=100L, maxRuns=40L, imp="RfZ_default", decide="Confirmed_only", seed_base=4000L)
WINDOWS <- c(36L, 60L)             # 학습창 (개월)
WEIGHTS <- c("EW","ICW")           # 가중
CADENCE <- 6L                      # 재선별 주기 (개월, semiannual)
TOP_N   <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
GATE_PT <- 2.95; N_TRIALS <- 4L    # arm S sweep config 수 (DSR deflation)
PAIRED_KILL <- 2.0                 # 사전등록 kill 문턱
PREREG <- list(mode="RAMP", round="R4", mechanism="Boruta_all_relevant_factor_zoo_reduction",
               substrate="outputs/ramp/factor_group_scores.parquet (11 orthogonal economic families)",
               boruta=BORUTA, windows=WINDOWS, weights=WEIGHTS, cadence_months=CADENCE,
               arm_s_configs=length(WINDOWS)*length(WEIGHTS), bases=c("all11_EW","all11_ICW"),
               top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN,
               gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
               n_trials_dsr=N_TRIALS, paired_kill_threshold=PAIRED_KILL,
               target="within-month z-scored forward 1M return (cross-sectional)",
               pit="training window trailing-only (last W sig_dates strictly before rebalance t; fwd realized by t)",
               vintage_pin=sprintf("session_%s", RUNTAG))
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH

## ── 데이터 (R1/R2 동일 소스) ──
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
FAMS <- sort(unique(g$family))
gw <- dcast(g, signal_date + security_id ~ family, value.var="group_z")
## 국면(t-1 PIT) — arm R용 (arm S는 미사용)
a <- as.data.table(read_parquet("stage_artifacts/WT_D20260425_010/alpha_scores.parquet")); a[,Date:=as.Date(Date)]
reg <- unique(a[,.(ym=format(Date,"%Y-%m"), regime=regime_state)])[,.SD[1], by=ym]
gw[, ym := format(signal_date,"%Y-%m")]; gw <- merge(gw, reg, by="ym", all.x=TRUE); gw[is.na(regime), regime:="NORMAL"]

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
sig_dates <- sort(unique(gw$signal_date)); n_sig <- length(sig_dates)
.slim_rds <- Sys.getenv("RAMP_R1_SLIM_RDS", "")
if (nzchar(.slim_rds) && file.exists(.slim_rds)) {
  rawdata <- as.data.table(readRDS(.slim_rds)); rawdata[, Date := as.Date(Date)]
} else {
  rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
  .udates <- sort(unique(rawdata$Date))
  .me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
    if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
  rawdata <- rawdata[Date %in% .me[!is.na(.me)]]      # slim: month-end 거래일만 (결과불변, 세그폴트 회피)
}
fwd <- build_monthly_forward_returns(rawdata, sig_dates)
ret <- fwd$returns_dt[,.(signal_date=as.Date(Date), security_id=Ticker, Ret_1m)]
oos_cut <- sig_dates[n_sig-23]; post2017 <- as.Date("2017-01-01")
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]

## 팩터군 점수에 forward-ret merge (Boruta target + IC 가중용)
panel <- merge(gw[, c("signal_date","security_id", FAMS), with=FALSE], ret, by=c("signal_date","security_id"), all.x=TRUE)
panel[, y := { m<-mean(Ret_1m,na.rm=TRUE); s<-sd(Ret_1m,na.rm=TRUE); if(is.na(s)||s<1e-9) Ret_1m-m else (Ret_1m-m)/s }, by=signal_date]

wf("=== RAMP R4: Boruta 팩터-존 축소 배분 (arm S 정적 1차) ===")
wf("config_hash=%s | windows={%s} weights={%s} cadence=%dm | Boruta nmax=%d ntree=%d maxRuns=%d Confirmed-only",
   CFG_HASH, paste(WINDOWS,collapse=","), paste(WEIGHTS,collapse=","), CADENCE, BORUTA$nmax, BORUTA$ntree, BORUTA$maxRuns)
wf("substrate: 11 families {%s} | %d months %s~%s | ~%d stocks/mo",
   paste(FAMS,collapse=","), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), median(gw[,.N,by=signal_date]$N))

## ── Boruta 선별 궤적 (window별, semiannual anchor) — 체크포인트 캐시 ──
## anchor index a: 학습창 [a-W, a-1] (trailing-only, PIT). 선별 = months [a, next_anchor-1] governing.
## confirmed set 은 weight 무관 → window당 1궤적 (2 windows total). ICW 가중은 같은 창의 trailing IC.
boruta_select <- function(train_idx, seed){
  win_dates <- sig_dates[train_idx]
  pan <- panel[signal_date %in% win_dates & is.finite(y)]
  if(nrow(pan) < 200) return(list(confirmed=FAMS, n=nrow(pan), degenerate="too_few_rows"))
  set.seed(seed); idx <- if(nrow(pan)>BORUTA$nmax) sample(nrow(pan), BORUTA$nmax) else seq_len(nrow(pan))
  X <- pan[idx, ..FAMS]; for(f in FAMS) X[[f]][is.na(X[[f]])] <- 0
  yv <- pan$y[idx]
  set.seed(seed)
  bor <- tryCatch(Boruta(x=as.data.frame(X), y=yv, maxRuns=BORUTA$maxRuns, doTrace=0, ntree=BORUTA$ntree),
                  error=function(e) NULL)
  if(is.null(bor)) return(list(confirmed=FAMS, n=length(idx), degenerate="boruta_error"))
  dec <- bor$finalDecision
  conf <- names(dec)[dec=="Confirmed"]
  tent <- names(dec)[dec=="Tentative"]
  deg <- NA_character_
  if(length(conf) < 2){ conf <- union(conf, tent); deg <- "confirmed<2_add_tentative" }  # 최소 2군
  if(length(conf) < 1){ conf <- FAMS; deg <- "confirmed=0_fallback_all" }
  # importance median (진단)
  impmed <- tryCatch({ ih <- bor$ImpHistory; ih[is.infinite(ih)] <- NA
    apply(ih[, FAMS, drop=FALSE], 2, median, na.rm=TRUE) }, error=function(e) setNames(rep(NA_real_,length(FAMS)),FAMS))
  list(confirmed=conf, tentative=tent, n=length(idx), degenerate=deg, imp_median=impmed,
       n_confirmed=length(conf))
}
trailing_ic <- function(train_idx, fams){
  win_dates <- sig_dates[train_idx]
  pan <- panel[signal_date %in% win_dates]
  sapply(fams, function(fm){
    d <- pan[is.finite(get(fm)) & is.finite(Ret_1m)]
    if(nrow(d) < 30) return(0)
    icv <- d[, { if(.N>=10 && sd(get(fm))>0 && sd(Ret_1m)>0) .(ic=cor(get(fm),Ret_1m,method="spearman")) else .(ic=NA_real_) }, by=signal_date]$ic
    m <- mean(icv, na.rm=TRUE); if(is.na(m)) 0 else m
  })
}

BORUTA_CACHE <- file.path(".cache", sprintf("_ramp_r4_boruta_traj_%s.rds", RUNTAG))
if(file.exists(BORUTA_CACHE) && !nzchar(Sys.getenv("RAMP_R4_FORCE",""))){
  traj_all <- readRDS(BORUTA_CACHE); wf("[cache] Boruta 궤적 재사용: %s", BORUTA_CACHE)
} else {
  traj_all <- list()
  for(W in WINDOWS){
    anchors <- seq(W+1L, n_sig-1L, by=CADENCE)   # 재선별 시점 (deploy i in [W+1, n-1])
    tj <- list()
    for(k in seq_along(anchors)){
      a_i <- anchors[k]; tr <- (a_i-W):(a_i-1L)
      sel <- boruta_select(tr, seed=BORUTA$seed_base + a_i)
      icw <- trailing_ic(tr, sel$confirmed)
      icw_all <- trailing_ic(tr, FAMS)
      tj[[as.character(a_i)]] <- list(anchor_idx=a_i, anchor_date=as.character(sig_dates[a_i]),
        train_range=as.character(range(sig_dates[tr])), confirmed=sel$confirmed, n_confirmed=sel$n_confirmed,
        degenerate=sel$degenerate, imp_median=sel$imp_median, ic_confirmed=icw, ic_all=icw_all, n_rows=sel$n)
      wf("  [W=%d anchor %s] confirmed=%d/%d {%s}%s", W, as.character(sig_dates[a_i]),
         length(sel$confirmed), length(FAMS), paste(sel$confirmed,collapse=","),
         if(!is.na(sel$degenerate)) paste0(" [",sel$degenerate,"]") else "")
    }
    traj_all[[as.character(W)]] <- list(anchors=anchors, traj=tj)
    saveRDS(traj_all, BORUTA_CACHE)   # 체크포인트 (window마다 저장)
  }
  wf("[cache] Boruta 궤적 저장: %s", BORUTA_CACHE)
}

## ── walk-forward 스코어 빌더 ──
## deploy month i (index): governing anchor = max anchor <= i. confirmed set + weight 고정(anchor간 hold).
##   composite score(i) = sum_{f in confirmed} w_f * z_f(i), z_f = within-month z of family f at signal_date i.
gw_z_month <- gw[, c("signal_date","security_id"), with=FALSE]
for(f in FAMS) gw_z_month[[f]] <- gw[[f]]
build_wf_score <- function(W, weight_scheme, use_confirmed=TRUE){
  tj <- traj_all[[as.character(W)]]; anchors <- tj$anchors
  deploy_idx <- (W+1L):(n_sig-1L)
  rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); node <- tj$traj[[as.character(ga)]]
    fams <- if(use_confirmed) node$confirmed else FAMS
    if(weight_scheme=="EW"){ wv <- setNames(rep(1/length(fams), length(fams)), fams) }
    else { icv <- if(use_confirmed) node$ic_confirmed[fams] else node$ic_all[fams]
           icv[!is.finite(icv)] <- 0; icv <- pmax(icv, 0)
           wv <- if(sum(icv) < 1e-9) setNames(rep(1/length(fams),length(fams)),fams) else icv/sum(icv) }
    sub <- gw_z_month[signal_date==sig_dates[i]]
    Xz <- sub[, lapply(.SD, zc), .SDcols=fams]           # within-month z
    Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    sc <- as.numeric(Xm %*% wv[fams])
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=sc)
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ── 게이트 계산기 (R1/R2 gates() 복제; cap-w authoritative) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
gates <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)],
        fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)],
        top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)], liq_min=LIQ_MIN,
        run_id="r4", strategy_id=lab), error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA
  .splits<-c(0.55,0.65,0.75); .rets<-sapply(.splits,function(fr){ k<-floor(nrow(pr)*fr)
    if(k<12||(nrow(pr)-k)<6) return(NA_real_); .is<-srf(pr$act_bm[1:k]); .oo<-srf(pr$act_bm[(k+1):nrow(pr)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  retn <- median(.rets, na.rm=TRUE)
  # DSR (deflated, n_trials sweep)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA
  dsr <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS*0.05 else NA
  post_sr <- srf(pr[date>=post2017, act_bm]); full_bm_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_EWuni=pt, port_t_capwt=pt_bm, oos_retention=retn, calmar=cal,
             dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_bm_sr, turnover=cs$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, ret_net, benchmark_ret)])
}

## ── base (control) + arm S (4 config) 측정 ──
## base = window·weight 매칭 (선별효과만 순수 격리): arm S와 confirmed(Boruta subset) vs all-11 만 차이,
##   window(deploy 범위·ICW lookback)·weight는 동일. → boruta_W{W}_{wt} 는 base_W{W}_{wt}와 paired.
wf("\n=== 측정: base(window·weight 매칭 control) + arm S(4 config) — cap-w authoritative ===")
RES <- list(); PR <- list()
# base (all 11) — window·weight별
for(W in WINDOWS) for(wt in WEIGHTS){
  lab <- sprintf("base_W%d_%s", W, wt)
  gg <- gates(build_wf_score(W, wt, use_confirmed=FALSE), lab)
  if(!is.null(gg)){ RES[[lab]] <- gg$dt; PR[[lab]] <- gg$pr }
}
# arm S (Boruta confirmed subset)
for(W in WINDOWS) for(wt in WEIGHTS){
  lab <- sprintf("boruta_W%d_%s", W, wt)
  gg <- gates(build_wf_score(W, wt, use_confirmed=TRUE), lab)
  if(!is.null(gg)){ RES[[lab]] <- gg$dt; PR[[lab]] <- gg$pr }
}
TAB <- rbindlist(RES, fill=TRUE)
wf("  %-22s %9s %9s %9s %7s %7s %8s %6s", "model","pt_capwt","pt_EWuni","oos_ret","calmar","DSR","post17SR","TO")
for(i in seq_len(nrow(TAB))) wf("  %-22s %+9.2f %+9.2f %+9.2f %+7.2f %+7.2f %+8.2f %6.0f",
  TAB$model[i], TAB$port_t_capwt[i], TAB$port_t_EWuni[i], TAB$oos_retention[i], TAB$calmar[i], TAB$dsr[i], TAB$post2017_bm_sr[i], TAB$turnover[i])

## ── paired NW-t (arm S − matching base, cap-w active) ──
wf("\n=== paired NW-t (lag3): arm S(confirmed) − base(all11), 가중 매칭 ===")
paired <- list()
for(W in WINDOWS) for(wt in WEIGHTS){
  la <- sprintf("boruta_W%d_%s", W, wt); lb <- sprintf("base_W%d_%s", W, wt)
  if(is.null(PR[[la]]) || is.null(PR[[lb]])) next
  m <- merge(PR[[la]][,.(date, a=act_bm)], PR[[lb]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; tval <- nwt(d)
  paired[[la]] <- data.table(model=la, base=lb, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=tval, n=nrow(m))
  wf("  %-22s vs %-18s Δmean(ann)=%+.4f paired_t=%+.2f (n=%d)", la, lb, mean(d,na.rm=TRUE)*12, tval, nrow(m))
}
PAIRED <- rbindlist(paired, fill=TRUE)

## ── 선별 실효 진단 (confirmed 집합 크기·turnover) ──
wf("\n=== 선별 실효 진단 (Boruta가 실제로 거르는가) ===")
sel_diag <- list()
for(W in WINDOWS){
  tj <- traj_all[[as.character(W)]]$traj
  sizes <- sapply(tj, function(x) x$n_confirmed)
  sets <- lapply(tj, function(x) x$confirmed)
  # turnover: 연속 anchor 간 Jaccard 거리 (1 - |∩|/|∪|)
  jac <- if(length(sets)>=2) sapply(2:length(sets), function(k){ i<-intersect(sets[[k]],sets[[k-1]]); u<-union(sets[[k]],sets[[k-1]]); 1-length(i)/length(u) }) else NA
  vacuous <- mean(sizes >= length(FAMS))  # 전 팩터 confirmed 비율 (선별 무의미)
  sel_diag[[as.character(W)]] <- data.table(window=W, n_anchors=length(sizes),
    conf_size_mean=mean(sizes), conf_size_min=min(sizes), conf_size_max=max(sizes),
    frac_all_confirmed=vacuous, set_turnover_jaccard=mean(jac,na.rm=TRUE))
  wf("  W=%d: anchors=%d | confirmed size mean=%.1f [min=%d max=%d] | 전팩터-confirmed 비율=%.2f | set-turnover(Jaccard)=%.2f",
     W, length(sizes), mean(sizes), min(sizes), max(sizes), vacuous, mean(jac,na.rm=TRUE))
}
SELDIAG <- rbindlist(sel_diag, fill=TRUE)
# 팩터군별 confirmed 빈도 (어느 군이 살아남나)
conf_freq <- lapply(WINDOWS, function(W){ tj<-traj_all[[as.character(W)]]$traj
  fr <- sapply(FAMS, function(fm) mean(sapply(tj, function(x) fm %in% x$confirmed)))
  data.table(window=W, t(fr)) }) |> rbindlist(fill=TRUE)
wf("\n  팩터군별 confirmed 빈도 (창별):")
for(i in seq_len(nrow(conf_freq))){ W<-conf_freq$window[i]
  fr <- unlist(conf_freq[i, ..FAMS]); ord <- order(-fr)
  wf("   W=%d: %s", W, paste(sprintf("%s=%.2f",FAMS[ord],fr[ord]),collapse=" "))
}

## ── KILL gate 판정 (사전등록) ──
max_paired <- if(nrow(PAIRED)) max(PAIRED$paired_t, na.rm=TRUE) else NA
any_pass_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt >= GATE_PT &
                     grepl("^boruta_", TAB$model))
selection_effective <- any(SELDIAG$frac_all_confirmed < 0.5)  # 선별이 실제로 거르는가(전팩터 confirmed<50%)
paired_beats <- is.finite(max_paired) && max_paired >= PAIRED_KILL
kill_triggered <- !paired_beats   # arm S 전 config paired<2.0 → kill
wf("\n=== KILL gate (사전등록 paired>=%.1f) ===", PAIRED_KILL)
wf("  max paired_t(arm S vs base) = %+.2f | 선별 실효(전팩터-confirmed<50%%) = %s | graduation pass = %s",
   max_paired, selection_effective, any_pass_grad)
wf("  => arm R 착수 조건(선별 실효 ∧ paired>=%.1f) = %s", PAIRED_KILL, (selection_effective && paired_beats))
wf("  => KILL = %s %s", kill_triggered,
   if(kill_triggered) "(arm S가 base 대비 paired<2.0 → shadow-null 선별도 배분 개선 불가 확정)" else "(arm S 실효 → arm R 조건부 착수)")

## ── HARD 게이트 판정표 ──
wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64 / DSR 0.5) ===")
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
  wf("  [%-22s] %s → %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")) }

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  results=TAB, paired=PAIRED, selection_diag=SELDIAG, conf_freq=conf_freq,
  kill_triggered=kill_triggered, max_paired_t=max_paired, selection_effective=selection_effective,
  any_graduation=any_pass_grad, arm_r_launch=(selection_effective && paired_beats),
  n_sig=n_sig, date_range=as.character(range(sig_dates)),
  incumbent_book_ir=1.416, families=FAMS)
saveRDS(list(res=res, PR=PR, traj=traj_all), file.path(".cache", sprintf("_ramp_r4_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, "r4_boruta_gates.parquet"))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, "r4_boruta_paired.parquet"))
jsonlite::write_json(res, file.path(OUT, sprintf("r4_boruta_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)
## 사전등록 별도 파일 (감사)
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r4_boruta_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)

wf("\n=== VERDICT (arm S) ===")
b <- TAB[grepl("^boruta_",model)][which.max(port_t_capwt)]
wf("  best arm-S: %s pt_capwt=%+.2f oos=%+.2f calmar=%+.2f DSR=%+.2f",
   b$model, b$port_t_capwt, b$oos_retention, b$calmar, b$dsr)
wf("  graduation=%s | kill=%s | arm R launch=%s",
   any_pass_grad, kill_triggered, (selection_effective && paired_beats))
close(con); cat(sprintf("R4_DONE. kill=%s any_grad=%s max_paired=%.2f log=%s\n",
   kill_triggered, any_pass_grad, max_paired, logf))
cat(readLines(logf), sep="\n")
