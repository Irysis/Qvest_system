## run_ramp_r11_ppure_dev.R — RAMP R11: P-pure 발전 chain (선별 신선도 / 보유밴드 / 선별-vintage 앙상블)
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 mandate 2026-07-13: "P-pure 더 발전시켜봐". FQ-024.
## 공략 대상 = P-pure(W36_K20)의 바인딩 실패 = **oos·post-2017 감쇠 추적** (cap-tier 국소화×cap-w 벽 아님 — 정직 명시).
##
## [chain 규율] measurement-graduation §3 — selection_type="chain"(sweep 아님. 각 arm이 R7/R8/R10 진단에 1:1):
##   · 각 arm = 독립 기전 가설 + 변경사유 기전 진단 1줄(prereg 기록)
##   · arm 간 선택 = **IS-only**(OOS 반복조회 금지). oos_retention은 최종 게이트 산출로만.
##   · 2차 결합은 1차 IS 승자 확정 후에만. DSR은 진단용 산출(chain → 게이트 부적용).
##
## [1차 3-arm] base = P-pure W36_K20 (종목 EW × 팩터 EW, R6 저장 2.6124 parity 앵커)
##   arm F (선별 신선도): 선별 갱신 반기(cadence 6)→분기(cadence 3). 패널 Pmat에서 trailing PORT_t 재선별.
##       기전: 풀 자기상관 0.86~0.92 sticky → 감쇠 팩터 만기 지연 → 갱신 단축이 post-2017/oos 추적 개선.
##       ⚠적대검증: factor-momentum 타이밍 null(06-30) 수렴 여부 = 풀 churn·회전 증가로 판별. 비용은 delta 15bps 내장.
##   arm B (보유밴드): base 선별(cadence 6) + 종목 히스테리시스(진입 rank≤25 / 이탈 rank>35, 밴드폭 35 고정).
##       기전: 경계 churn = 잡음 거래 + 비용 → 밴드가 net·oos 개선(S3_consensus_band paired +2.03 선례).
##   arm V (선별-vintage 앙상블): 반기 선별을 3개월 offset 두 코호트(A: 37+6k / B: 40+6k) trailing_t 평균 → top-K.
##       기전: 선별-시점 timing-luck(SPEC-2 산포) → 코호트 분산으로 완화.
##
## [2차 결합] 1차 IS 승자 × W-stock-sqrt 틸트(R10 최고 paired +1.78 구성). 결합 IS < 승자 단독 → 폐기(진단 기록).
##
## [판정] cap-w authoritative(nwt act_bm) + EW-uni 진단 병기 + HARD 3종 + 2017+ 분리 + paired NW-t vs base.
##   1차 승자 = IS paired-t vs base 최대(IS-only). oos_retention = 감쇠 추적 target(최종 게이트 산출).
## [측정 규율] proxy 손계산 없음 — weighted_screen_bt(계약, build_benchmark_compare) 경유. base parity == R6 2.6124.
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
logf <- file.path(".cache", sprintf("_ramp_r11_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimators (R6/R10 자구동일) ──
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
CAP <- 0.20; FLOOR_FRAC <- 0.25
CADENCE_BASE <- 6L; CADENCE_F <- 3L; V_OFFSET <- 3L
BAND_ENTER <- 25L; BAND_EXIT <- 35L
GATE_PT <- 2.95; PAIRED_MEANINGFUL <- 2.0
IS_FRAC <- 0.65                    # chain: IS-only 승자 지목용 (첫 65% 배포월)
N_TRIALS_R11 <- 4L                 # arm F, arm B, arm V, combine
N_TRIALS_LINEAGE <- 14L + N_TRIALS_R11   # P-pure 계보 누적: R6 6 + R7 4 + R10 4 + R11 4 = 18 (chain — DSR 진단용)
ARMS <- c("armF_cadence3","armB_band2535","armV_vintage")
PREREG <- list(mode="RAMP", round="R11", fq="FQ-024",
  question="P-pure(W36_K20)의 oos·post-2017 감쇠 추적 실패를 세 독립 기전으로 공략(선별 신선도/보유밴드/선별-vintage 앙상블)",
  base="Ppure_W36_K20 (종목 EW × 팩터 EW, R6 저장 2.6124 parity 앵커)",
  selection_type="chain",
  chain_discipline="arm 간 선택 IS-only(첫 65% 배포월 paired-t) · oos는 최종 게이트 산출로만 · 2차는 1차 IS 승자 후 · DSR 진단용(게이트 부적용)",
  arms=list(
    armF_cadence3=list(mechanism="선별 갱신 반기(cadence 6)→분기(cadence 3)",
      diag="풀 자기상관 0.86~0.92 sticky → 감쇠 팩터 만기 지연이 감쇠 추적 실패 원인 — 갱신 단축이 post-2017/oos 추적 개선",
      adversarial="factor-momentum 타이밍 null(06-30) 수렴 여부 = 풀 churn·회전 증가로 판별. 회전비용 delta 15bps 내장"),
    armB_band2535=list(mechanism="종목 히스테리시스 밴드(진입 rank<=25 / 이탈 rank>35, 밴드폭 35 고정)",
      diag="경계 churn = 잡음 거래 + 비용 — 밴드가 net·oos 개선(S3_consensus_band paired +2.03 선례)"),
    armV_vintage=list(mechanism="반기 선별 3개월 offset 두 코호트(A:37+6k / B:40+6k) trailing_t 평균 top-K",
      diag="선별-시점 timing-luck(SPEC-2 산포)가 oos 불안정에 기여 — 코호트 분산으로 완화")),
  combine_2nd="1차 IS 승자 × W-stock-sqrt(R10 최고 paired +1.78). IS < 승자 단독 → 폐기",
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64, dsr=0.5),
  primary_criterion="1차 승자 = IS paired NW-t(cap-w act_bm) vs base 최대(IS-only). 최종 판정 = full HARD 3종 + full paired vs base + oos_retention(감쇠 target)",
  kill_rule="전 arm full paired < 2.0 AND HARD 3종 0/N AND oos_retention 0.7 미도달 → P-pure 구조 개선 chain 소진 — 남은 경로 재료(R9 insider)",
  honest_frame="본 라운드=oos·감쇠 추적 공략. cap-tier 국소화×cap-w 벽은 못 풂(보고 명시). return-derived substrate 재사용(신규 재료 아님)",
  is_frac=IS_FRAC, top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, cap=CAP, floor_frac=FLOOR_FRAC,
  cadence_base=CADENCE_BASE, cadence_F=CADENCE_F, v_offset=V_OFFSET, band_enter=BAND_ENTER, band_exit=BAND_EXIT,
  n_trials_r11=N_TRIALS_R11, n_trials_lineage=N_TRIALS_LINEAGE,
  cost_model="delta-based |Δw|×15bps one-way (weighted_screen_bt 내장 — 밴드/선별 회전 자동 반영)",
  xmode_check="hypothesis_index: factor-momentum timing NULL(06-30) prior — armF는 '갱신 주기'로 구분하되 수렴 여부 적대검증. band/vintage는 R11 신규(중복 아님, INV-7)",
  vintage_pin="r6_session_20260711 (sel_traj/pure_factor_scores/factor_group_scores/rawdata/panel; base parity Δ=0 확인)",
  as_of_date="2026-07-13", source_version="RAMP_R11_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r11_ppure_dev_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R11: P-pure 발전 chain (config_hash=%s) ===", CFG_HASH)
wf("arms: %s | selection_type=chain | IS_FRAC=%.2f | n_trials R11=%d lineage=%d",
   paste(ARMS,collapse=","), IS_FRAC, N_TRIALS_R11, N_TRIALS_LINEAGE)

## ── 데이터 (R6/R10 동일 소스) ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"))); g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates); rm(g)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawdata[Date %in% .me[!is.na(.me)]]
me_map <- data.table(Date_me=.me, Date=sig_dates)[!is.na(Date_me)]
SIZE_DT <- merge(rawme_f[, .(Date_me=as.Date(Date), Ticker, Size)], me_map, by="Date_me")[, .(Date, Ticker, Size)]
fwd <- build_monthly_forward_returns(rawme_f, sig_dates); rm(rawdata, rawme_f); invisible(gc())
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]  # EW-uni 벤치(진단)

sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())

## ── 선별 궤적 (R6 캐시 = base cadence 6) ──
sel_traj <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
base_anchors <- sel_traj[["36"]]$anchors
wf("substrate: %d approved factors | %d sig months %s~%s | base(cadence6) anchors=%d",
   length(POOL_FACS), n_sig, as.character(sig_dates[1]), as.character(sig_dates[n_sig]), length(base_anchors))

## ── 배포권 패널 Pmat 재구성 (arm F/V 재선별용 — R6 factor_deployzone_active 재사용) ──
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))
wf("[panel] Pmat %d months x %d factors (재선별 substrate)", n_pm, length(PANEL_FACS))

## trailing PORT_t 벡터 (R6 trailing_portt 자구동일 — 102 factor 각 NW-t lag3)
trailing_portt_vec <- function(W, a_idx){
  lo <- a_idx - W; hi <- a_idx - 1L
  if(lo < 1L || hi > n_pm) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) })
}
## anchor 집합: cadence-3(F) 는 cohortA(37+6k)·cohortB(40+6k) 를 포함 — 한 번에 계산
anchors_F <- seq(W36+1L, n_sig-1L, by=CADENCE_F)
cohortA   <- seq(W36+1L, n_sig-1L, by=CADENCE_BASE)          # = base R6 anchors
cohortB   <- seq(W36+1L+V_OFFSET, n_sig-1L, by=CADENCE_BASE) # offset +3
TT_ANCHORS <- sort(unique(c(anchors_F, cohortA, cohortB)))
TT_CACHE <- file.path(".cache", sprintf("_ramp_r11_tt_%s.rds", RUNTAG))
if(file.exists(TT_CACHE) && !nzchar(Sys.getenv("RAMP_R11_FORCE_TT",""))){
  TT_ALL <- readRDS(TT_CACHE); wf("[cache] trailing_t 재사용: %s (%d anchors)", TT_CACHE, length(TT_ALL))
} else {
  wf("[compute] trailing_t %d anchors (cadence-3 superset) ...", length(TT_ANCHORS))
  t0 <- Sys.time(); TT_ALL <- list()
  for(a in TT_ANCHORS){ tv <- trailing_portt_vec(W36, a); if(!is.null(tv)) TT_ALL[[as.character(a)]] <- tv }
  saveRDS(TT_ALL, TT_CACHE)
  wf("[compute] trailing_t 완료 %.0fs (%d valid anchors)", as.numeric(Sys.time()-t0,units="secs"), length(TT_ALL))
}
topK_from_tt <- function(tt, k=K20){ tt<-tt[is.finite(tt)]; if(length(tt)<k) return(names(tt)); names(sort(tt, decreasing=TRUE))[seq_len(k)] }

## ── pool getters (arm별) ──
## base = R6 sel_traj (cadence 6)
getter_base <- function(i){ ga <- max(base_anchors[base_anchors<=i]); sel_traj[["36"]]$traj[[as.character(ga)]]$pool[["K20"]] }
## arm F = cadence 3
getter_F <- function(i){ ga <- max(anchors_F[anchors_F<=i]); tt <- TT_ALL[[as.character(ga)]]; if(is.null(tt)) getter_base(i) else topK_from_tt(tt) }
## arm V = 두 코호트 trailing_t 평균 top-K (PIT: gaA,gaB <= i)
getter_V <- function(i){
  aA <- cohortA[cohortA<=i]; aB <- cohortB[cohortB<=i]
  gaA <- if(length(aA)) max(aA) else NA; gaB <- if(length(aB)) max(aB) else NA
  ttA <- if(!is.na(gaA)) TT_ALL[[as.character(gaA)]] else NULL
  ttB <- if(!is.na(gaB)) TT_ALL[[as.character(gaB)]] else NULL
  if(is.null(ttA) && is.null(ttB)) return(getter_base(i))
  if(is.null(ttB)) return(topK_from_tt(ttA))
  if(is.null(ttA)) return(topK_from_tt(ttB))
  avg <- (ttA + ttB)/2   # 동일 102 factor 순서 정합
  topK_from_tt(avg)
}

## ── 공용: positive-shift 틸트 + cap water-fill (R10 자구동일) ──
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

## ── composite 재구성 (R10 build_composite EW 경로 자구동일 — pool getter만 파라미터화) ──
build_composite_g <- function(pool_getter){
  deploy_idx <- (W36+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    facs <- intersect(pool_getter(i), FW_FACS); if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ── weights_dt 빌더: composite -> top-25 -> 종목 가중 (R10 build_weights 자구동일) ──
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

## ── 보유밴드 빌더 (arm B): 진입 rank<=BAND_ENTER / 이탈 rank>BAND_EXIT, 히스테리시스, EW 또는 sqrt ──
##   weight_mode: "ew" | "sqrt"(held 내 점수-비례 완만화). ≤25 hard(retain>25 시 score 상위 25).
build_weights_band <- function(comp, weight_mode="ew"){
  S <- comp[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  dts <- sort(unique(S$Date)); held <- character(0); rows <- vector("list", length(dts))
  churn_ct <- 0L; n_reb <- 0L
  for(ix in seq_along(dts)){
    d <- dts[ix]; cur <- S[Date==d][order(-score)]
    if(nrow(cur) < TOP_N){ next }
    cur[, rk := seq_len(.N)]                                  # 1 = best
    top_enter <- cur[rk <= BAND_ENTER, Ticker]                # 진입 자격
    keep_pool <- cur[rk <= BAND_EXIT, Ticker]                 # 잔류 자격(밴드)
    retain <- intersect(held, keep_pool)
    if(length(retain) > TOP_N) retain <- cur[Ticker %in% retain][order(-score)][seq_len(TOP_N), Ticker]
    slots <- TOP_N - length(retain); fill <- character(0)
    if(slots > 0){ cand <- setdiff(top_enter, retain)
      if(length(cand) > 0) fill <- cur[Ticker %in% cand][order(-score)][seq_len(min(slots, length(cand))), Ticker] }
    newsel <- unique(c(retain, fill))
    if(ix > 1){ churn_ct <- churn_ct + length(setdiff(newsel, held)); n_reb <- n_reb + 1L }
    held <- newsel
    scv <- cur[Ticker %in% held][match(held, Ticker), score]
    ww <- if(weight_mode=="sqrt") stock_weights(scv, "sqrt") else rep(1/length(held), length(held))
    rows[[ix]] <- data.table(Date=d, Ticker=held, w=ww)
  }
  wdt <- rbindlist(rows)
  attr(wdt, "name_churn_per_reb") <- if(n_reb>0) churn_ct/n_reb else NA_real_
  wdt
}

## ── gate: weighted_screen_bt -> period_returns -> R6 estimator (R10 gate_one 자구동일) ──
gate_one <- function(Wdt, lab){
  r <- tryCatch(weighted_screen_bt(Wdt, RET_DT, BENCH_DT, cost_bps_oneway=COST_BPS,
        run_id=paste0("r11_",lab), strategy_id=lab), error=function(e){ w("  [gate ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(r) || is.null(r$period_returns)) return(NULL)
  pr <- as.data.table(r$period_returns); pr[, date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt_ew <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  retn <- oos3(pr$act_bm)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(den>1e-10) sr_m/den else NA_real_
  dsr <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS_LINEAGE*0.05 else NA_real_
  post_sr <- srf(pr[date>=post2017, act_bm]); full_sr <- srf(pr$act_bm)
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt_ew, oos_retention=retn, calmar=cal,
         dsr=dsr, post2017_bm_sr=post_sr, full_bm_sr=full_sr, turnover=r$turnover_annual, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, act, ret_net, benchmark_ret)], W=Wdt)
}
conc_diag <- function(Wdt, lab){
  Z <- copy(SIZE_DT); Z <- Z[!is.na(Size)]; setorder(Z, Date, -Size); Z[, crank:=seq_len(.N), by=Date]
  Z[, tier:=fifelse(crank<=10L,"MEGA",fifelse(crank<=30L,"MID","OTHER"))]
  H <- merge(as.data.table(Wdt), Z[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
  H[is.na(tier), tier:="UNRANKED"]
  hhi <- H[, .(hhi=sum(w^2), n_eff=1/sum(w^2), maxw=max(w), n_hold=.N), by=Date]
  tw  <- H[, .(wshare=sum(w)), by=.(Date, tier)]; twa <- tw[, .(wshare=mean(wshare)), by=tier]
  tiers <- c("MEGA","MID","OTHER","UNRANKED"); ts <- setNames(rep(0,4), tiers)
  for(t in tiers) if(t %in% twa$tier) ts[t] <- twa[tier==t, wshare]
  data.table(model=lab, hhi=mean(hhi$hhi), n_eff=mean(hhi$n_eff), maxw=mean(hhi$maxw), n_hold=mean(hhi$n_hold),
    w_MEGA=ts["MEGA"], w_MID=ts["MID"], w_OTHER=ts["OTHER"], w_UNRANKED=ts["UNRANKED"])
}

## ════════════ 1차 측정 (base + 3 arm) ════════════
wf("\n=== 1차 측정 (cap-w authoritative, weighted_screen_bt 계약경로) ===")
RES <- list(); PR <- list(); WMAP <- list(); CONC <- list(); META <- list()

comp_base <- build_composite_g(getter_base)
W_base <- build_weights(comp_base, "ew")
gb <- gate_one(W_base, "base"); RES[["base"]]<-gb$dt; PR[["base"]]<-gb$pr; WMAP[["base"]]<-W_base; CONC[["base"]]<-conc_diag(W_base,"base")
wf("  [base         ] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gb$dt$port_t_capwt, gb$dt$port_t_EWuni, gb$dt$oos_retention, gb$dt$calmar, gb$dt$dsr, gb$dt$post2017_bm_sr, gb$dt$turnover)

comp_F <- build_composite_g(getter_F)
W_F <- build_weights(comp_F, "ew")
gF <- gate_one(W_F, "armF_cadence3"); RES[["armF_cadence3"]]<-gF$dt; PR[["armF_cadence3"]]<-gF$pr; WMAP[["armF_cadence3"]]<-W_F; CONC[["armF_cadence3"]]<-conc_diag(W_F,"armF_cadence3")
wf("  [armF_cadence3] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gF$dt$port_t_capwt, gF$dt$port_t_EWuni, gF$dt$oos_retention, gF$dt$calmar, gF$dt$dsr, gF$dt$post2017_bm_sr, gF$dt$turnover)

W_B <- build_weights_band(comp_base, "ew")
gBb <- gate_one(W_B, "armB_band2535"); RES[["armB_band2535"]]<-gBb$dt; PR[["armB_band2535"]]<-gBb$pr; WMAP[["armB_band2535"]]<-W_B; CONC[["armB_band2535"]]<-conc_diag(W_B,"armB_band2535")
META[["armB_name_churn_per_reb"]] <- attr(W_B, "name_churn_per_reb")
wf("  [armB_band2535] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f (name_churn/reb=%.2f)",
   gBb$dt$port_t_capwt, gBb$dt$port_t_EWuni, gBb$dt$oos_retention, gBb$dt$calmar, gBb$dt$dsr, gBb$dt$post2017_bm_sr, gBb$dt$turnover, META[["armB_name_churn_per_reb"]])

comp_V <- build_composite_g(getter_V)
W_V <- build_weights(comp_V, "ew")
gV <- gate_one(W_V, "armV_vintage"); RES[["armV_vintage"]]<-gV$dt; PR[["armV_vintage"]]<-gV$pr; WMAP[["armV_vintage"]]<-W_V; CONC[["armV_vintage"]]<-conc_diag(W_V,"armV_vintage")
wf("  [armV_vintage ] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSR=%+.3f post17SR=%+.3f TO=%.2f",
   gV$dt$port_t_capwt, gV$dt$port_t_EWuni, gV$dt$oos_retention, gV$dt$calmar, gV$dt$dsr, gV$dt$post2017_bm_sr, gV$dt$turnover)

## ── base parity: cap-w == R6 저장 2.6124 ──
base_pt <- RES[["base"]]$port_t_capwt; R6_BASE <- 2.6124
parity_delta <- abs(base_pt - R6_BASE); parity_ok <- is.finite(parity_delta) && parity_delta < 5e-3
wf("\n[base parity] R11 base cap-w PORT_t=%.4f vs R6 저장 %.4f -> |Δ|=%.2e ok=%s", base_pt, R6_BASE, parity_delta, parity_ok)
if(!parity_ok) w("  ★ WARNING: base parity 미달 — 재구성 계열 라벨 강등 필요")

## ── paired NW-t (full + IS-only) vs base ──
pair_full <- function(la){ if(is.null(PR[[la]])||is.null(PR[["base"]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=act_bm)], PR[["base"]][,.(date, b=act_bm)], by="date")
  d <- m$a - m$b; n_is <- floor(nrow(m)*IS_FRAC)
  data.table(model=la, mean_diff_ann=mean(d,na.rm=TRUE)*12,
    paired_t_full=nwt(d), paired_t_IS=nwt(d[seq_len(n_is)]), paired_t_OOS=nwt(d[(n_is+1L):nrow(m)]),
    n=nrow(m), n_is=n_is) }
PAIRED <- rbindlist(lapply(ARMS, pair_full), fill=TRUE)
wf("\n=== paired NW-t vs base (IS_FRAC=%.2f: IS=첫 %d월 / OOS=나머지) ===", IS_FRAC, PAIRED$n_is[1])
for(i in seq_len(nrow(PAIRED))) wf("  [%-13s] Δ(ann)=%+.4f | paired_t: full=%+.3f IS=%+.3f OOS=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$mean_diff_ann[i], PAIRED$paired_t_full[i], PAIRED$paired_t_IS[i], PAIRED$paired_t_OOS[i], PAIRED$n[i])

## ── 1차 IS-only 승자 지목 (chain 규율) ──
winner <- PAIRED[which.max(paired_t_IS), model]
winner_is_t <- PAIRED[model==winner, paired_t_IS]
wf("\n=== 1차 IS-only 승자 (chain: OOS 미조회) ===")
wf("  winner = %s (IS paired_t=%+.3f) | 서열(IS): %s", winner, winner_is_t,
   paste(sprintf("%s=%.2f", PAIRED$model, PAIRED$paired_t_IS), collapse=" > "))

## ════════════ 2차 결합: 승자 × W-stock-sqrt ════════════
wf("\n=== 2차 결합: %s × W-stock-sqrt ===", winner)
comb_lab <- sprintf("comb_%s_sqrt", winner)
if(winner=="armB_band2535"){
  W_comb <- build_weights_band(comp_base, "sqrt")
} else {
  comp_win <- if(winner=="armF_cadence3") comp_F else if(winner=="armV_vintage") comp_V else comp_base
  W_comb <- build_weights(comp_win, "sqrt")
}
gC <- gate_one(W_comb, comb_lab)
if(!is.null(gC)){ RES[[comb_lab]]<-gC$dt; PR[[comb_lab]]<-gC$pr; WMAP[[comb_lab]]<-W_comb; CONC[[comb_lab]]<-conc_diag(W_comb, comb_lab) }
pcomb <- pair_full(comb_lab); if(!is.null(pcomb)) PAIRED <- rbind(PAIRED, pcomb, fill=TRUE)
comb_is_t <- if(!is.null(pcomb)) pcomb$paired_t_IS else NA_real_
combine_keep <- is.finite(comb_is_t) && is.finite(winner_is_t) && comb_is_t >= winner_is_t
wf("  [%s] pt_capwt=%+.3f oos=%+.3f calmar=%+.3f | IS paired_t=%+.3f vs 승자 단독 %+.3f -> %s",
   comb_lab, gC$dt$port_t_capwt, gC$dt$oos_retention, gC$dt$calmar, comb_is_t, winner_is_t,
   ifelse(combine_keep, "결합 유지(IS 비악화)", "결합 폐기(IS 악화)"))

TAB <- rbindlist(lapply(RES, function(x) x), fill=TRUE)
CONCT <- rbindlist(CONC, fill=TRUE)

## ── HARD 게이트표 ──
wf("\n=== HARD 게이트 (capwt %.2f / oos 0.7 / calmar 0.64 / DSR 0.5[chain 진단], n_trials lineage=%d) ===", GATE_PT, N_TRIALS_LINEAGE)
for(i in seq_len(nrow(TAB))){ r<-TAB[i]
  p<-c(port_t=isTRUE(r$port_t_capwt>=GATE_PT), oos=isTRUE(r$oos_retention>=0.7), cal=isTRUE(r$calmar>=0.64))
  wf("  [%-16s] pt=%+.3f %s oos=%+.3f %s cal=%+.3f %s -> %s", r$model, r$port_t_capwt, ifelse(p["port_t"],"✓","✗"),
     r$oos_retention, ifelse(p["oos"],"✓","✗"), r$calmar, ifelse(p["cal"],"✓","✗"), ifelse(all(p),"★GRADUATION","미달")) }

## ── concentration ──
wf("\n=== concentration (소형농축·유효종목수·HHI) ===")
wf("  %-16s %6s %6s %6s %6s | %6s %6s %6s", "model","HHI","effN","maxw","nHold","MEGA","MID","OTHER")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-16s %6.4f %6.2f %6.3f %6.1f | %6.3f %6.3f %6.3f", r$model, r$hhi, r$n_eff, r$maxw, r$n_hold, r$w_MEGA, r$w_MID, r$w_OTHER) }

## ════════════ 챌린지 진단 3종 ════════════
wf("\n=== 챌린지 진단 (self-adversarial 재료) ===")
## ① arm F: factor-momentum 수렴 여부 — 선별 풀 churn(cadence3 vs cadence6) + trailing_t rank 자기상관
pool_churn <- function(anchors){
  aa <- anchors[anchors %in% as.integer(names(TT_ALL))]; ch <- c()
  for(j in 2:length(aa)){ p1<-topK_from_tt(TT_ALL[[as.character(aa[j-1])]]); p2<-topK_from_tt(TT_ALL[[as.character(aa[j])]])
    ch <- c(ch, length(setdiff(p2,p1))/K20) }
  mean(ch, na.rm=TRUE) }
rank_ac <- function(anchors){
  aa <- anchors[anchors %in% as.integer(names(TT_ALL))]; rc <- c()
  for(j in 2:length(aa)){ t1<-TT_ALL[[as.character(aa[j-1])]]; t2<-TT_ALL[[as.character(aa[j])]]
    cf <- intersect(names(t1[is.finite(t1)]), names(t2[is.finite(t2)])); if(length(cf)>=10) rc<-c(rc, cor(t1[cf],t2[cf],method="spearman")) }
  mean(rc, na.rm=TRUE) }
churn6 <- pool_churn(cohortA); churn3 <- pool_churn(anchors_F); ac6 <- rank_ac(cohortA); ac3 <- rank_ac(anchors_F)
armF_to <- TAB[model=="armF_cadence3", turnover]; base_to <- TAB[model=="base", turnover]
wf("  ① arm F factor-momentum 판별: 풀 churn/refresh cadence6=%.3f cadence3=%.3f | trailing_t rank AC c6=%.2f c3=%.2f | stock TO base=%.2f→F=%.2f (Δ%+.2f)",
   churn6, churn3, ac6, ac3, base_to, armF_to, armF_to-base_to)
## ② arm B: oos 개선 vs IS만 개선 (경계 잡음 vs 신호) + 회전 절감
bB <- PAIRED[model=="armB_band2535"]; armB_to <- TAB[model=="armB_band2535", turnover]
wf("  ② arm B 밴드 판별: paired IS=%+.3f OOS=%+.3f (OOS≥IS면 신호, OOS≪IS면 경계잡음) | stock TO base=%.2f→B=%.2f (Δ%+.2f) | oos_ret base=%+.3f→B=%+.3f",
   bB$paired_t_IS, bB$paired_t_OOS, base_to, armB_to, armB_to-base_to, TAB[model=="base",oos_retention], TAB[model=="armB_band2535",oos_retention])
## ③ arm V: 코호트 상관 (분산축소 실효) — cohortA/B trailing_t Spearman + K20 pool Jaccard
coh_corr <- c(); coh_jac <- c()
for(i in (W36+1L):(n_sig-1L)){
  aA<-cohortA[cohortA<=i]; aB<-cohortB[cohortB<=i]
  if(!length(aA)||!length(aB)) next
  ttA<-TT_ALL[[as.character(max(aA))]]; ttB<-TT_ALL[[as.character(max(aB))]]
  if(is.null(ttA)||is.null(ttB)) next
  cf<-intersect(names(ttA[is.finite(ttA)]),names(ttB[is.finite(ttB)]))
  if(length(cf)>=10) coh_corr<-c(coh_corr, cor(ttA[cf],ttB[cf],method="spearman"))
  pA<-topK_from_tt(ttA); pB<-topK_from_tt(ttB); coh_jac<-c(coh_jac, length(intersect(pA,pB))/length(union(pA,pB)))
}
wf("  ③ arm V 코호트 판별: trailing_t Spearman mean=%.3f | K20 pool Jaccard mean=%.3f (1에 가까울수록 분산축소 실효 無)",
   mean(coh_corr,na.rm=TRUE), mean(coh_jac,na.rm=TRUE))

## ── KILL 판정 (사전등록) ──
maxp_full <- suppressWarnings(max(PAIRED[model %in% ARMS, paired_t_full], na.rm=TRUE))
any_grad <- any(is.finite(TAB$port_t_capwt) & TAB$port_t_capwt>=GATE_PT &
                is.finite(TAB$oos_retention) & TAB$oos_retention>=0.7 &
                is.finite(TAB$calmar) & TAB$calmar>=0.64 & TAB$model!="base")
best_oos <- max(TAB[model!="base", oos_retention], na.rm=TRUE)
KILL <- !(is.finite(maxp_full) && maxp_full >= PAIRED_MEANINGFUL) && !any_grad && !(is.finite(best_oos) && best_oos>=0.7)
wf("\n=== KILL gate (사전등록) ===")
wf("  max full paired (arm vs base) = %+.3f (문턱 %.1f)", maxp_full, PAIRED_MEANINGFUL)
wf("  any arm GRADUATION(HARD 3종) = %s | best oos_retention(비-base) = %+.3f (target 0.7)", any_grad, best_oos)
wf("  => KILL(P-pure 구조 개선 chain 소진) = %s", KILL)

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-07-13", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
    source_version="RAMP_R11_v1", security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)"),
  results=TAB, paired=PAIRED, concentration=CONCT,
  base_parity=list(r11_base_pt=base_pt, r6_stored=R6_BASE, delta=parity_delta, ok=parity_ok),
  winner_1st=winner, winner_is_t=winner_is_t, combine_2nd=comb_lab, combine_is_t=comb_is_t, combine_keep=combine_keep,
  challenge=list(armF=list(pool_churn_c6=churn6, pool_churn_c3=churn3, rank_ac_c6=ac6, rank_ac_c3=ac3, to_base=base_to, to_armF=armF_to),
                 armB=list(paired_is=bB$paired_t_IS, paired_oos=bB$paired_t_OOS, to_base=base_to, to_armB=armB_to,
                           name_churn_per_reb=META[["armB_name_churn_per_reb"]], oos_base=TAB[model=="base",oos_retention], oos_armB=TAB[model=="armB_band2535",oos_retention]),
                 armV=list(cohort_spearman_mean=mean(coh_corr,na.rm=TRUE), cohort_jaccard_mean=mean(coh_jac,na.rm=TRUE))),
  kill=KILL, max_paired_full=maxp_full, any_graduation=any_grad, best_oos_nonbase=best_oos,
  n_trials_r11=N_TRIALS_R11, n_trials_lineage=N_TRIALS_LINEAGE, selection_type="chain", n_sig=n_sig,
  date_range=as.character(range(sig_dates)),
  r10_ref=list(w_stock_capwt=2.9303, w_stock_sqrt_paired=1.7816, base_capwt=2.6124))
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, WMAP=WMAP, CONC=CONCT), file.path(".cache", sprintf("_ramp_r11_%s.rds", RUNTAG)))
write_parquet(TAB, file.path(OUT, sprintf("r11_ppure_dev_gates_%s.parquet", RUNTAG)))
if(nrow(PAIRED)) write_parquet(PAIRED, file.path(OUT, sprintf("r11_ppure_dev_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("r11_ppure_dev_conc_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r11_ppure_dev_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)

## ── best variant period_returns (텔레그램 차트용) ──
best_lab <- TAB[model!="base"][which.max(port_t_capwt), model]
if(!is.null(PR[[best_lab]])){
  bpr <- merge(PR[[best_lab]][,.(date, ret_net)], BENCH_DT[,.(date=Date, BM_Ret)], by="date")
  saveRDS(list(best_lab=best_lab,
               period_returns=data.table(date=bpr$date, ret_net=bpr$ret_net, benchmark_ret=bpr$BM_Ret),
               base_pr=merge(PR[["base"]][,.(date,ret_net)], BENCH_DT[,.(date=Date,BM_Ret)], by="date")),
          file.path(".cache", sprintf("_ramp_r11_bestpr_%s.rds", RUNTAG)))
}

wf("\n=== VERDICT ===")
bv <- TAB[model!="base"][which.max(port_t_capwt)]
wf("  best cap-w variant: %s pt_capwt=%+.3f oos=%+.3f calmar=%+.3f | base=%.4f", bv$model, bv$port_t_capwt, bv$oos_retention, bv$calmar, base_pt)
wf("  1차 IS 승자=%s | 2차 결합 %s(%s) | max full paired=%+.3f | KILL=%s | base_parity=%s",
   winner, comb_lab, ifelse(combine_keep,"유지","폐기"), maxp_full, KILL, parity_ok)
close(con)
cat(sprintf("R11_DONE. winner=%s KILL=%s any_grad=%s max_paired_full=%.3f best_oos=%.3f base_parity=%s(Δ%.2e) log=%s\n",
   winner, KILL, any_grad, maxp_full, best_oos, parity_ok, parity_delta, logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
