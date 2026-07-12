## run_ramp_r10_weighting.R — RAMP R10: P-pure 비중 고도화 (종목 점수-비례 × 팩터 성과-비례)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 질문 2026-07-13: "비중 결정 방법 통계적 고도화 적용해봤니". FQ-023.
## 질문: P-pure(W36_K20)의 동일가중(종목 EW × 팩터 EW)을 알파/점수-비례 계열로 교체하면 개선되는가.
##
## [설계] R6 P-pure 선별(sel_traj, W36_K20 풀)을 *고정* — R10은 WEIGHTING 축만 테스트(선별 재실행 아님).
##   base   = P-pure W36_K20 (종목 EW × 팩터 EW)  — 저장 계열 재사용(R6 2.6124 parity 앵커)
##   W-stock  = 종목 가중 = 합의 z-점수 선형 비례 (positive-shift, cap[0,0.20], Σw=1, ≤25)
##   W-factor = 팩터 합산 가중 = trailing NW-t positive-shift 비례 (PIT: 선별 시점 값만) · 종목 EW
##   W-both   = W-factor 합성 + W-stock 종목 틸트
##   W-stock-sqrt = 점수-비례 완만화(sqrt) — 강한 틸트가 standalone FAIL과 수렴하는지 판별(재량 config4)
##
## [prior] project-hrp-frontier-weighting-settled: LinearTilt(알파-비례)가 24변형 지배(단일클러스터 book).
##   단 EW=통계 sizing 천장(추정오차>신호)·위험기반(HRP/MVO/공분산) settled-negative → 본 측정서 제외.
##   교차조회(INV-7): score-tilt/alpha-tilt 가중은 QEPM catalog 다수(STR_1699 등)이나 P-pure composite 위
##   적용은 미검증 → 중복 아님(유일 양성 prior LinearTilt를 신규 substrate에 적용).
##
## [판정] cap-w authoritative(nwt act_bm) + EW-uni 진단 병기 + HARD 3종 + 2017+ 분리 +
##   **paired NW-t vs base(핵심, 문턱 2.0)** + 회전율 변화(delta-based 15bps 계약 내장) + DSR(누적 sweep).
## [KILL 사전등록] 전 config paired < 2.0 → "P-pure 비중 축 소진 — EW 유지 확정".
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유. 자체합성 금지.
##   base parity: base cap-w PORT_t == R6 저장 2.6124 (bit-consistent 요구).
## [실행] 단일스레드 · arrow io_thread(2) · pin r6 vintage 대조 · governor 정지 · book 무변경.
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns
source("02_Infrastructure/contracts/weighted_screen_bt.R")     # weighted_screen_bt (임의가중 계약경로)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "outputs/ramp"; RUNTAG <- "20260713"
logf <- file.path(".cache", sprintf("_ramp_r10_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimator (R6 gates() 자구동일 — 동일 추정량 보장) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_); .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); median(r, na.rm=TRUE) }
post2017 <- as.Date("2017-01-01")

## ── 사전등록 config (hash 동결) ──
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; K20 <- 20L
CAP <- 0.20; FLOOR_FRAC <- 0.25   # positive-shift floor: 최약 선택명 base = floor_frac*range (틸트 완충)
GATE_PT <- 2.95; PAIRED_KILL <- 2.0
N_TRIALS_R10 <- 4L                # W-stock, W-factor, W-both, W-stock-sqrt
N_TRIALS_LINEAGE <- 6L + 4L + N_TRIALS_R10   # P-pure 계보 누적: R6 6 + R7 4 + R10 4 = 14
CONFIGS <- c("W_stock","W_factor","W_both","W_stock_sqrt")
PREREG <- list(mode="RAMP", round="R10", fq="FQ-023",
  question="P-pure(W36_K20) 동일가중(종목 EW × 팩터 EW) → 알파/점수-비례 계열 교체 시 개선?",
  base="Ppure_W36_K20 (종목 EW × 팩터 EW, R6 저장 2.6124 parity 앵커)",
  selection_fixed="R6 sel_traj W36_K20 풀 재사용 (선별 재실행 아님 — WEIGHTING 축만)",
  configs=list(
    W_stock ="종목 가중 = 합의 z-점수 선형 positive-shift 비례 (cap[0,0.20], Σw=1, ≤25) · 팩터 EW",
    W_factor="팩터 합산 가중 = trailing NW-t positive-shift 비례 (PIT 선별시점값) · 종목 EW",
    W_both  ="W-factor 합성 + W-stock 종목 틸트",
    W_stock_sqrt="점수-비례 완만화 sqrt(positive-shift) · 팩터 EW (강한틸트 FAIL수렴 판별 config4)"),
  weighting_spec=list(positive_shift="p = s - min(s_sel) + floor_frac*range(s_sel); floor_frac=0.25",
    linear="raw = p", sqrt="raw = sqrt(p)", cap="iterative water-fill cap=0.20, Σw=1",
    factor_tilt="wfac_j = tt_j - min(tt_pool) + floor_frac*range(tt_pool); tt=trailing NW-t at anchor (PIT)"),
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
  primary_criterion="paired NW-t(cap-w active) vs base >= 2.0 (문턱)",
  kill_rule="전 config paired < 2.0 -> P-pure 비중 축 소진(EW 유지 확정)",
  top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  n_trials_r10=N_TRIALS_R10, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="sweep",
  dsr_note="DSR n_trials=P-pure 계보 누적 14 (R6 6+R7 4+R10 4). selection_type=sweep.",
  honest_prior="EW=통계 sizing 천장(추정오차>신호). 위험기반 sizing settled-negative(제외). 유일 양성=LinearTilt(HRP 단일클러스터).",
  xmode_check="hypothesis_index: STR_1699 Alpha-Tilted/score_tilt catalog 다수 존재하나 P-pure composite 위 미검증 → 중복 아님(INV-7)",
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 가중변형 회전증가 자동 반영)",
  vintage_pin="r6_session_20260711 (sel_traj/pure_factor_scores/factor_group_scores/rawdata; N1 d3 parity Δ=0 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R10_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r10_weighting_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R10: P-pure 비중 고도화 (config_hash=%s) ===", CFG_HASH)
wf("configs: %s | n_trials R10=%d lineage=%d | floor_frac=%.2f cap=%.2f", paste(CONFIGS,collapse=","),
   N_TRIALS_R10, N_TRIALS_LINEAGE, FLOOR_FRAC, CAP)

## ── 데이터 (R6/N1 동일 소스) ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"))); g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates); rm(g)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawdata[Date %in% .me[!is.na(.me)]]
## size_dt (challenge: cap-tier 분해) — 월말 Size를 sig_date로 매핑
me_map <- data.table(Date_me=.me, Date=sig_dates)[!is.na(Date_me)]
SIZE_DT <- merge(rawme_f[, .(Date_me=as.Date(Date), Ticker, Size)], me_map, by="Date_me")[, .(Date, Ticker, Size)]
fwd <- build_monthly_forward_returns(rawme_f, sig_dates); rm(rawdata, rawme_f); invisible(gc())
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]  # EW-uni 벤치(진단, R6 동일)

sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())

## ── 선별 궤적 (R6 캐시 재사용 — 재선별 아님) ──
sel_traj <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
wf("substrate: %d approved factors | %d sig months %s~%s | W36 anchors=%d",
   length(POOL_FACS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]),
   length(sel_traj[["36"]]$anchors))

## ── 공용: positive-shift 틸트 + cap water-fill ──
cap_normalize <- function(raw, cap=CAP){
  raw <- pmax(raw, 0); if(sum(raw)<=0) return(rep(1/length(raw), length(raw)))
  w <- raw/sum(raw)
  for(it in 1:50){ over <- w > cap + 1e-12; if(!any(over)) break
    excess <- sum(w[over]-cap); w[over] <- cap; under <- !over
    if(!any(under)||sum(w[under])<=0){ w <- w/sum(w); break }
    w[under] <- w[under] + excess*w[under]/sum(w[under]) }
  w/sum(w)
}
tilt_shift <- function(x, floor_frac=FLOOR_FRAC){ rng <- max(x)-min(x)
  if(!is.finite(rng)||rng<1e-9) return(rep(mean(abs(x))+1e-6, length(x)))
  x - min(x) + floor_frac*rng }
stock_weights <- function(scores, mode){   # mode: ew | linear | sqrt
  n <- length(scores); if(mode=="ew") return(rep(1/n, n))
  p <- tilt_shift(scores); raw <- if(mode=="sqrt") sqrt(p) else p; cap_normalize(raw) }

## ── composite 재구성 (R6 build_arm_score/build_ppure_score 일반화) ──
## factor_mode: "ew"(rowMeans) | "tt"(trailing NW-t positive-shift 가중). 반환: (signal_date, security_id, score[re-z])
build_composite <- function(W, k, factor_mode){
  anchors <- sel_traj[[as.character(W)]]$anchors; deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i])
    tr <- sel_traj[[as.character(W)]]$traj[[as.character(ga)]]
    facs <- intersect(tr$pool[[paste0("K",k)]], FW_FACS); if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    if(factor_mode=="tt"){
      tt <- tr$trailing_t[facs]; tt[!is.finite(tt)] <- min(tt[is.finite(tt)], na.rm=TRUE)
      wfac <- tilt_shift(tt); wfac <- wfac/sum(wfac)
      sco <- as.numeric(Xm %*% wfac)
    } else sco <- rowMeans(Xm)
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=sco)
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ── weights_dt 빌더: composite -> top-25 선택 -> 종목 가중 ──
build_weights <- function(comp, stock_mode){
  S <- comp[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  setorder(S, Date, -score)
  S[, {
    n <- min(TOP_N, .N); sc_sel <- score[seq_len(n)]
    .(Ticker=Ticker[seq_len(n)], w=stock_weights(sc_sel, stock_mode))
  }, by=Date]
}

## ── config 스펙 (base + 4 variant) ──
SPEC <- list(
  base         = list(factor_mode="ew", stock_mode="ew"),
  W_stock      = list(factor_mode="ew", stock_mode="linear"),
  W_factor     = list(factor_mode="tt", stock_mode="ew"),
  W_both       = list(factor_mode="tt", stock_mode="linear"),
  W_stock_sqrt = list(factor_mode="ew", stock_mode="sqrt"))

## ── gates: weighted_screen_bt -> period_returns -> R6 estimator ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r10_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(r) || is.null(r$period_returns)) return(NULL)
  pr <- as.data.table(r$period_returns); pr[, date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt_ew <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  retn <- oos3(pr$act_bm)
  ## DSR (R6 자구동일, n_trials=lineage 14)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA_real_
  dsr <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS_LINEAGE*0.05 else NA_real_
  post_sr <- srf(pr[date>=post2017, act_bm])
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt_ew, oos_retention=retn, calmar=cal,
         dsr=dsr, post2017_bm_sr=post_sr, turnover=r$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, act, ret_net, benchmark_ret)], W=Wdt)
}

## ── concentration 진단 (challenge point 2/3): HHI, eff-N, cap-tier ──
conc_diag <- function(Wdt, lab){
  Z <- copy(SIZE_DT); Z <- Z[!is.na(Size)]; setorder(Z, Date, -Size); Z[, crank:=seq_len(.N), by=Date]
  Z[, tier:=fifelse(crank<=10L,"MEGA",fifelse(crank<=30L,"MID","OTHER"))]
  H <- merge(as.data.table(Wdt), Z[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
  H[is.na(tier), tier:="UNRANKED"]
  hhi <- H[, .(hhi=sum(w^2), n_eff=1/sum(w^2), maxw=max(w), n_hold=.N), by=Date]
  tw  <- H[, .(wshare=sum(w)), by=.(Date, tier)]
  twa <- tw[, .(wshare=mean(wshare)), by=tier]
  tiers <- c("MEGA","MID","OTHER","UNRANKED"); ts <- setNames(rep(0,4), tiers)
  for(t in tiers) if(t %in% twa$tier) ts[t] <- twa[tier==t, wshare]
  data.table(model=lab, hhi=mean(hhi$hhi), n_eff=mean(hhi$n_eff), maxw=mean(hhi$maxw),
    w_MEGA=ts["MEGA"], w_MID=ts["MID"], w_OTHER=ts["OTHER"], w_UNRANKED=ts["UNRANKED"])
}

## ════════════ 측정 ════════════
wf("\n=== 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list()
for(nm in names(SPEC)){
  sp <- SPEC[[nm]]
  comp <- build_composite(W36, K20, sp$factor_mode)
  Wdt <- build_weights(comp, sp$stock_mode)
  gg <- gate_one(Wdt, nm)
  if(!is.null(gg)){ RES[[nm]]<-gg$dt; PR[[nm]]<-gg$pr; WMAP[[nm]]<-gg$W; CONC[[nm]]<-conc_diag(Wdt, nm) }
  wf("  [%-13s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
     nm, gg$dt$port_t_capwt, gg$dt$port_t_EWuni, gg$dt$oos_retention, gg$dt$calmar, gg$dt$dsr,
     gg$dt$post2017_bm_sr, gg$dt$turnover)
}
TAB <- rbindlist(RES, fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── base parity: cap-w == R6 저장 2.6124 ──
base_pt <- TAB[model=="base", port_t_capwt]
R6_BASE <- 2.6124
parity_delta <- abs(base_pt - R6_BASE)
parity_ok <- is.finite(parity_delta) && parity_delta < 5e-3
wf("\n[base parity] R10 base cap-w PORT_t=%.4f vs R6 저장 %.4f -> |Δ|=%.2e ok=%s",
   base_pt, R6_BASE, parity_delta, parity_ok)
if(!parity_ok) w("  ★ WARNING: base parity 미달 — 재구성 계열 라벨 강등 필요")

## ── paired NW-t vs base (cap-w primary + EW-uni diag) ──
pair1 <- function(la, lb, col){ if(is.null(PR[[la]])||is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=get(col))], PR[[lb]][,.(date, b=get(col))], by="date")
  d <- m$a - m$b; data.table(model=la, base=lb, basis=col, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=nwt(d), n=nrow(m)) }
paired <- list()
for(nm in CONFIGS){
  p1<-pair1(nm,"base","act_bm"); if(!is.null(p1)) paired[[length(paired)+1]]<-p1
  p2<-pair1(nm,"base","act");    if(!is.null(p2)) paired[[length(paired)+1]]<-p2 }
PAIRED <- rbindlist(paired, fill=TRUE)
wf("\n=== paired NW-t vs base (문턱 %.1f) ===", PAIRED_KILL)
for(i in seq_len(nrow(PAIRED))) wf("  [%-13s vs base | %-6s] Δ(ann)=%+.4f paired_t=%+.3f (n=%d)",
  PAIRED$model[i], ifelse(PAIRED$basis[i]=="act_bm","cap-w","EW-uni"), PAIRED$mean_diff_ann[i], PAIRED$paired_t[i], PAIRED$n[i])

## ── KILL 판정 ──
maxp_capw <- suppressWarnings(max(PAIRED[basis=="act_bm", paired_t], na.rm=TRUE))
best_cfg  <- if(nrow(PAIRED[basis=="act_bm"])) PAIRED[basis=="act_bm"][which.max(paired_t), model] else NA
KILL <- !(is.finite(maxp_capw) && maxp_capw >= PAIRED_KILL)
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT & TAB$model!="base")
wf("\n=== KILL gate (사전등록 paired cap-w >= %.1f) ===", PAIRED_KILL)
wf("  max paired (variant vs base, cap-w) = %+.3f (%s)", maxp_capw, best_cfg)
wf("  any variant HARD PORT_t>=2.95 = %s", any_grad)
wf("  => KILL(P-pure 비중 축 소진) = %s", KILL)

## ── HARD 게이트표 ──
wf("\n=== HARD 게이트 (capwt 2.95 / oos 0.7 / calmar 0.64 / DSR 0.5, n_trials=%d) ===", N_TRIALS_LINEAGE)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=2.95), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64), dsr=isTRUE(r$dsr>=0.5))
  wf("  [%-13s] %s -> %s", r$model, paste(names(p),ifelse(p,"✓","✗"),collapse=" "), ifelse(all(p),"★GRADUATION","미달")) }

## ── concentration 진단 (challenge 2/3) ──
wf("\n=== concentration 진단 (challenge: 소형주농축·유효종목수·HHI) ===")
wf("  %-13s %6s %6s %6s | %6s %6s %6s %6s", "model","HHI","effN","maxw","MEGA","MID","OTHER","UNRK")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-13s %6.4f %6.2f %6.3f | %6.3f %6.3f %6.3f %6.3f",
     r$model, r$hhi, r$n_eff, r$maxw, r$w_MEGA, r$w_MID, r$w_OTHER, r$w_UNRANKED) }

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R10_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT,
  base_parity=list(r10_base_pt=base_pt, r6_stored=R6_BASE, delta=parity_delta, ok=parity_ok),
  kill=KILL, max_paired_capw=maxp_capw, best_config=best_cfg, any_graduation=any_grad,
  n_trials_r10=N_TRIALS_R10, n_trials_lineage=N_TRIALS_LINEAGE, n_sig=n_sig,
  date_range=as.character(range(sig_dates)),
  r6_ref=list(ppure_w36_k20_capwt=2.6124, ppure_ewuni=3.9191, ppure_oos=-0.0759, ppure_calmar=0.45, ppure_to=9.2705))
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT), file.path(".cache", sprintf("_ramp_r10_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r10_weighting_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r10_weighting_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r10_weighting_conc_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r10_weighting_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용) ──
best_lab <- if(is.finite(maxp_capw)) best_cfg else "W_stock"
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab, period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[["base"]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r10_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
bv <- TAB[model!="base"][which.max(port_t_capwt)]
wf("  best variant (cap-w): %s pt_capwt=%+.3f oos=%+.3f calmar=%+.3f | base=%.4f", bv$model, bv$port_t_capwt, bv$oos_retention, bv$calmar, base_pt)
wf("  max paired vs base(cap-w)=%+.3f | KILL=%s | graduation=%s | base_parity=%s", maxp_capw, KILL, any_grad, parity_ok)
close(con)
cat(sprintf("R10_DONE. KILL=%s any_grad=%s max_paired=%.3f base_parity=%s(Δ%.2e) log=%s\n",
   KILL, any_grad, maxp_capw, parity_ok, parity_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
