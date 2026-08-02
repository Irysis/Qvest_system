## run_wt003_weighting_ab.R — WT-D20260802_003 Alpha Research: 조합 가중의 realized-PORT_t 정렬 A/B
## ─────────────────────────────────────────────────────────────────────────────
## 가설 (도훈 mandate 2026-08-02): 멀티팩터 조합의 **가중**을 realized-PORT_t 정렬로 결정하면
##   고정가중/EW/relevance-가중 대비 유의 개선이 있는가.
##
## [자가발전 차별 설계 — 선례 2건과의 관계 (재탕 방지 핵심)]
##   R6 (07-11): PORT_t-정렬 *선별* + EW 가중 = 2.6124 (첫 양성, paired +3.01 vs ctrl_all102)
##   R10 (07-13): PORT_t-*선별된* 풀 위에 PORT_t-비례 *가중*(W_factor) = paired −0.16 null
##   → 기측정 3셀: [기존선별×EW]=7F EW SCREEN_TIER · [PORT_t선별×EW]=R6 · [PORT_t선별×PORT_t가중]=R10
##   → **본 WT = 미검 셀 [기존규율(relevance) 선별 × PORT_t 가중]** — 2×2 완성.
##   판별 기전: (i) "정렬은 어디 적용돼도 유효" ⇒ W_portt가 base 대비 유의 양
##             (ii) "정렬은 membership 경유로만 유효, 강도(θ)는 잡음지배" ⇒ null (R10 일반화)
##   R10과의 기술 차별 2점: ① substrate = ICIR(relevance) 선별 풀 — PORT_t 정보가 선별에 미주입
##     (R10은 선별이 이미 PORT_t라 가중 slot의 정렬 정보가 중복·압축) ② 가중형 = clip-at-zero 비례
##     (R10 floor_frac=0.25 positive-shift는 틸트 희석 — 본 설계는 정렬 신호 전강도 허용)
##
## [사전등록] primary = paired NW-t(cap-w active) W_portt vs base_icir_EW >= 2.0.
##   adoption candidate = W_portt 단독(사전지정). famfix/icir/ivar = 대조군(채택 불가) → selection_type=chain.
##   kill rule: primary < 2.0 → config-scoped negative (기전 (ii) 지지). 천장 대비: cap-w 2.937 (R12).
## [측정] canonical_screen_bt(계약) cap-w authoritative + EW-uni 병기 + cap-tier 분해 + HARD 3종.
##   proxy 손계산 없음. PIT: 모든 trailing 통계는 anchor a에서 창 [a-36, a-1] (실현완료분만).
## [parity] R6 Ppure_W36_K20 재구성 → R10 저장 2.6124와 동일 기간 대조 (하네스 정합 앵커).
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")           # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")    # canonical_screen_bt (계약)
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
OUT <- "stage_artifacts/WT_D20260802_003"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
RUNTAG <- "20260802"
logf <- file.path(OUT, sprintf("_wt003_log_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

## ── estimator (R6/R10 자구동일 — 동일 추정량 보장) ──
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_); .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ }); median(r, na.rm=TRUE) }
post2017 <- as.Date("2017-01-01")

## ── 사전등록 config (hash 동결) ──
TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; K20 <- 20L; CADENCE <- 6L
GATE_PT <- 2.95; PAIRED_KILL <- 2.0; CEILING_CAPW <- 2.937
N_TRIALS_WT <- 4L      # 변형 4 (famfix/icir/portt/ivar). adoption candidate는 W_portt 단독(사전지정)
CONFIGS <- c("W_famfix","W_icir","W_portt","W_ivar")
PREREG <- list(mode="QEPM_alpha", task_id="WT-D20260802_003", round="WT003",
  question="기존규율(trailing ICIR top-K) 선별 풀에서 조합 가중을 realized-PORT_t 정렬로 결정하면 EW/고정(가족균등)/relevance(ICIR)-가중 대비 유의 개선?",
  matrix_2x2="기측정: [기존선별xEW]=7F_EW SCREEN_TIER / [PORTt선별xEW]=R6 2.6124 / [PORTt선별xPORTt가중]=R10 W_factor paired -0.16 null. 본 WT = 미검 셀 [기존선별xPORTt가중]",
  selection_fixed="trailing 36m rank-IC ICIR top-20 (relevance 기존규율, cadence 6m, anchor에서 창 [a-36,a-1] PIT) — 전 arm 공유(가중만 A/B)",
  base="base_icir_EW (ICIR top-20 풀, 팩터 EW x 종목 top-25 EW)",
  configs=list(
    W_famfix="고정가중(이론/구조): 가족 균등 x 가족내 EW (데이터 무반응 사전고정)",
    W_icir  ="relevance-정렬 가중: theta ∝ max(trailing ICIR, 0) (Grinold theta∝IC)",
    W_portt ="★가설 arm: theta ∝ max(trailing 배포권 active NW-t, 0) (clip-at-zero, all<=0 → EW fallback)",
    W_ivar  ="위험기반 대조: theta ∝ 1/var(trailing 배포권 active) (inverse-variance — NCO 단순형 대리, full NCO 아님 정직 라벨)"),
  primary_criterion="paired NW-t(cap-w active) W_portt vs base >= 2.0",
  adoption_candidate="W_portt 단독 사전지정 — famfix/icir/ivar는 대조군(채택 불가). selection_type=chain 근거",
  kill_rule="primary < 2.0 → config-scoped negative (membership-경유 기전 (ii) 지지)",
  ceiling_ref=c(capw_ceiling=CEILING_CAPW, oos_ceiling_delta=0.12),
  gate_hard=c(port_t_capwt=GATE_PT, oos_retention=0.7, calmar=0.64),
  top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_min=LIQ_MIN, window=W36, kpool=K20, cadence=CADENCE,
  n_trials_wt=N_TRIALS_WT, n_trials_substrate_lineage="P-pure 계보 33 (R6~R15) + 본 WT 4 — substrate 공유하나 선별규율 상이(ICIR 신규)",
  selection_type="chain",
  dsr_note="DSR은 진단 산출(chain — 게이트 아님). 보수적으로 n_trials=4 패널티 병기",
  cost_model="delta-based |dw| x 15bps one-way (canonical_screen_bt 내장)",
  substrate="102 approved factors pure_factor_scores.z (=Z_Score_Aligned parity) + r6_factor_deployzone_active.parquet (top-25 EW net active, 07-14 재빌드 byte-parity)",
  pit="선별 ICIR/가중 tt/var 전부 anchor a 기준 창 [a-36,a-1] — 창 말단 월의 forward return은 anchor 시점 실현완료. IC(s)=Spearman(z_j(s), Ret_1m(s))는 s+1 실현 후에만 소비",
  parity_anchor="R6 Ppure_W36_K20 재구성 → R10 저장 2.6124 (동일기간 절단 대조)",
  as_of_date="2026-08-02", source_version="WT003_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
CFG_HASH <- substr(digest::digest(PREREG, algo="sha256"), 1, 16)
PREREG$config_hash <- CFG_HASH
PREREG$generated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("wt003_prereg_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== WT-D20260802_003: 조합 가중 PORT_t-정렬 A/B (config_hash=%s) ===", CFG_HASH)

## ── 데이터 (R6/R10 동일 소스) ──
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet"))
APPROVED <- af[status=="approved", factor_id]
fam_of <- function(fid){ p<-toupper(substr(fid,1,2)); p1<-substr(p,1,1)
  if(p1=="V") "Value" else if(p1=="M"&&p!="MA") "Momentum" else if(p1=="Q") "Quality"
  else if(p1=="D") "LowRisk" else if(p1=="L") "Size_Liquidity" else if(p1=="S"&&p!="SE") "Size_Liquidity"
  else if(p1=="R") "Reversal" else if(p=="GR") "Growth_Profit" else if(p=="AC") "Accruals"
  else if(p1=="C"&&p!="CR") "Consensus" else if(p=="CR") "Credit" else if(p=="IN") "Growth_Profit"
  else if(p=="XF") "Composite" else if(p=="MA") "Macro" else if(p1=="T") "Size_Liquidity" else "Composite" }

g <- as.data.table(read_parquet("outputs/ramp/factor_group_scores.parquet", col_select="signal_date"))
sig_dates <- sort(unique(as.Date(g$signal_date))); n_sig <- length(sig_dates); rm(g)
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
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
ret <- fwd$returns_dt[,.(signal_date=as.Date(Date), security_id=Ticker, Ret_1m)]

sc <- as.data.table(read_parquet("outputs/ramp/pure_factor_scores.parquet",
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw, sc); invisible(gc())
FAC_FAM <- setNames(sapply(FW_FACS, fam_of), FW_FACS)
wf("substrate: %d factors | %d sig months %s ~ %s", length(FW_FACS), n_sig,
   as.character(sig_dates[1]), as.character(sig_dates[n_sig]))

## ── 배포권 패널 (trailing PORT_t/var 재료 — 07-14 재빌드 캐시 소비) ──
PANEL <- as.data.table(read_parquet("outputs/ramp/r6_factor_deployzone_active.parquet"))
PANEL[, signal_date := as.Date(signal_date)]
Pw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw, signal_date)
PANEL_FACS <- setdiff(names(Pw), "signal_date")
panel_dates <- Pw$signal_date; n_pm <- length(panel_dates)
Pmat <- as.matrix(Pw[, ..PANEL_FACS]); rownames(Pmat) <- as.character(panel_dates)
stopifnot(all(panel_dates == sig_dates[1:n_pm]))   # 인덱스 정렬 불변식
wf("deployzone PANEL: %d factors x %d months (~%s)", length(PANEL_FACS), n_pm, as.character(max(panel_dates)))

## ── IC 패널 (trailing ICIR 선별 재료): IC_j(s) = Spearman(z_j(s), Ret_1m(s)) ──
wf("\n=== IC 패널 계산 (%d months x %d factors, Spearman) ===", n_sig-1L, length(FW_FACS))
t0 <- Sys.time()
IC_rows <- vector("list", n_sig-1L)
for(i in seq_len(n_sig-1L)){
  sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
  rr <- ret[signal_date==sig_dates[i], .(security_id, Ret_1m)]
  m <- merge(sub, rr, by="security_id"); if(nrow(m) < 30) next
  X <- as.matrix(m[, ..FW_FACS])
  ic <- suppressWarnings(as.numeric(cor(X, m$Ret_1m, method="spearman", use="pairwise.complete.obs")))
  IC_rows[[i]] <- ic
}
ICmat <- do.call(rbind, lapply(seq_len(n_sig-1L), function(i)
  if(is.null(IC_rows[[i]])) rep(NA_real_, length(FW_FACS)) else IC_rows[[i]]))
colnames(ICmat) <- FW_FACS; rownames(ICmat) <- as.character(sig_dates[1:(n_sig-1L)])
wf("IC 패널 완료 (%.0fs)", as.numeric(Sys.time()-t0, units="secs"))

## ── trailing 통계 (전부 창 [a-W, a-1] — PIT) ──
trail_icir <- function(a){ lo<-a-W36; hi<-a-1L; if(lo<1L) return(NULL)
  sub <- ICmat[lo:min(hi, nrow(ICmat)), , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    s<-sd(x); if(!is.finite(s)||s<=0) return(NA_real_); mean(x)/s }) }
trail_tt <- function(a){ lo<-a-W36; hi<-a-1L; if(lo<1L||hi>n_pm) hi<-min(hi,n_pm); if(lo<1L) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
    m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }) }
trail_var <- function(a){ lo<-a-W36; hi<-min(a-1L, n_pm); if(lo<1L) return(NULL)
  sub <- Pmat[lo:hi, , drop=FALSE]
  apply(sub, 2, function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_); var(x) }) }

anchors <- seq(W36+1L, n_sig-1L, by=CADENCE)
wf("anchors: %d개 (%d..%d)", length(anchors), min(anchors), max(anchors))
ANCH <- list()
for(a in anchors){
  icir_a <- trail_icir(a); tt_a <- trail_tt(a); var_a <- trail_var(a)
  fin <- icir_a[is.finite(icir_a)]
  pool <- names(sort(fin, decreasing=TRUE))[seq_len(min(K20, length(fin)))]
  ANCH[[as.character(a)]] <- list(anchor_idx=a, anchor_date=as.character(sig_dates[a]),
    pool=pool, icir=icir_a, tt=tt_a, var=var_a)
}

## ── theta 빌더 (arm별 팩터 가중 — anchor에서 결정, 다음 anchor까지 유지) ──
theta_of <- function(an, arm){
  F <- intersect(an$pool, FW_FACS); K <- length(F); if(K==0) return(NULL)
  th <- switch(arm,
    base = rep(1/K, K),
    W_famfix = { fams <- FAC_FAM[F]; nf <- table(fams)
                 as.numeric(1/length(nf) / nf[fams]) },
    W_icir = { v <- pmax(an$icir[F], 0); v[!is.finite(v)] <- 0
               if(sum(v)<=0) rep(1/K,K) else v/sum(v) },
    W_portt = { v <- pmax(an$tt[F], 0); v[!is.finite(v)] <- 0
                if(sum(v)<=0) rep(1/K,K) else v/sum(v) },
    W_ivar = { v <- an$var[F]; bad <- !is.finite(v)|v<=0
               if(all(bad)) rep(1/K,K) else { v[bad] <- median(v[!bad]); iv <- 1/v; iv/sum(iv) } })
  setNames(th, F)
}

## ── composite 빌더 (deploy: anchor 최신값 소비; 258월 = 알파 emit 전용) ──
build_composite_arm <- function(arm){
  deploy_idx <- (W36+1L):n_sig; rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); an <- ANCH[[as.character(ga)]]
    th <- theta_of(an, arm); if(is.null(th)) next
    facs <- names(th)
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id,
                                          score=as.numeric(Xm %*% th))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ── gates (R6 자구동일 + canonical_screen_bt 계약; sidecar ast_features=NULL escape 표식) ──
gates <- function(score_dt, lab, dual=FALSE){
  cs <- tryCatch(canonical_screen_bt(
        score_dt[,.(Date=as.Date(signal_date), Ticker=security_id, score)],
        RET_DT, BENCH_DT, top_n=TOP_N, cost_bps_oneway=COST_BPS,
        liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="wt003", strategy_id=paste0("WT003_",lab),
        diag_dual_basis=dual, size_dt=if(dual) SIZE_DT else NULL),
        error=function(e){ w("  [gates ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs) || is.null(cs$period_returns)) return(NULL)
  pr <- as.data.table(cs$period_returns); pr[,date:=as.Date(date)]
  pr <- merge(pr, ewb, by="date", all.x=TRUE)
  pr[, act := ret_net - ew]; pr[, act_bm := ret_net - benchmark_ret]
  pt_ew <- nwt(pr$act); pt_bm <- nwt(pr$act_bm)
  nav <- cumprod(1+pr$ret_net); dd <- min(nav/cummax(nav)-1); ann <- prod(1+pr$ret_net)^(12/nrow(pr))-1
  cal <- if(dd<0) ann/abs(dd) else NA_real_
  retn <- oos3(pr$act_bm)
  sr_m <- mean(pr$act_bm)/sd(pr$act_bm); nn <- nrow(pr)
  sk <- tryCatch(e1071::skewness(pr$act_bm),error=function(e)0); ku <- tryCatch(e1071::kurtosis(pr$act_bm)+3,error=function(e)3)
  den <- sqrt((1-sk*sr_m+(ku-1)/4*sr_m^2)/(nn-1)); dsr_raw <- if(is.finite(den)&&den>1e-10) sr_m/den else NA_real_
  dsr_pen <- if(!is.na(dsr_raw)) dsr_raw - N_TRIALS_WT*0.05 else NA_real_
  post_t <- nwt(pr[date>=post2017, act_bm]); post_sr <- srf(pr[date>=post2017, act_bm])
  post_t_ew <- nwt(pr[date>=post2017, act])
  list(dt=data.table(model=lab, port_t_capwt=pt_bm, port_t_EWuni=pt_ew, oos_retention=retn, calmar=cal,
         dsr_raw=dsr_raw, dsr_pen=dsr_pen, post2017_t_capw=post_t, post2017_t_EWuni=post_t_ew,
         post2017_bm_sr=post_sr, turnover=cs$turnover_annual, net_sr=cs$net_sr,
         information_ratio=cs$information_ratio, n_months=nrow(pr)),
       pr=pr[,.(date, act_bm, act, ret_net, benchmark_ret)], cs=cs)
}

## ── cap-tier 분해 (top-25 EW 보유 — R10 conc_diag 자구동일) ──
conc_diag <- function(score_dt, lab){
  S <- score_dt[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  setorder(S, Date, -score)
  Wdt <- S[, { n <- min(TOP_N, .N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n, n)) }, by=Date]
  Z <- copy(SIZE_DT); Z <- Z[!is.na(Size)]; setorder(Z, Date, -Size); Z[, crank:=seq_len(.N), by=Date]
  Z[, tier:=fifelse(crank<=10L,"MEGA",fifelse(crank<=30L,"MID","OTHER"))]
  H <- merge(Wdt, Z[,.(Date,Ticker,tier)], by=c("Date","Ticker"), all.x=TRUE)
  H[is.na(tier), tier:="UNRANKED"]
  tw  <- H[, .(wshare=sum(w)), by=.(Date, tier)]
  twa <- tw[, .(wshare=mean(wshare)), by=tier]
  tiers <- c("MEGA","MID","OTHER","UNRANKED"); ts <- setNames(rep(0,4), tiers)
  for(t in tiers) if(t %in% twa$tier) ts[t] <- twa[tier==t, wshare]
  data.table(model=lab, w_MEGA=ts["MEGA"], w_MID=ts["MID"], w_OTHER=ts["OTHER"], w_UNRANKED=ts["UNRANKED"])
}

## ════════════ 측정 ════════════
wf("\n=== 측정 (cap-w authoritative, canonical_screen_bt 계약) ===")
ARMS <- c("base", CONFIGS)
RES <- list(); PR <- list(); CONC <- list(); COMP <- list(); CS_KEEP <- list()
for(nm in ARMS){
  comp <- build_composite_arm(nm)
  COMP[[nm]] <- comp
  gg <- gates(comp, nm, dual=(nm %in% c("base","W_portt")))
  if(!is.null(gg)){ RES[[nm]]<-gg$dt; PR[[nm]]<-gg$pr; CONC[[nm]]<-conc_diag(comp, nm)
    if(nm %in% c("base","W_portt")) CS_KEEP[[nm]] <- gg$cs }
  if(!is.null(gg)) wf("  [%-9s] pt_capwt=%+.3f pt_EWuni=%+.3f oos=%+.3f calmar=%+.3f DSRraw=%+.2f post17t=%+.2f TO=%.2f n=%d",
     nm, gg$dt$port_t_capwt, gg$dt$port_t_EWuni, gg$dt$oos_retention, gg$dt$calmar,
     gg$dt$dsr_raw, gg$dt$post2017_t_capw, gg$dt$turnover, gg$dt$n_months)
}
TAB <- rbindlist(RES, fill=TRUE); CONCT <- rbindlist(CONC, fill=TRUE)

## ── parity 앵커: R6 Ppure_W36_K20 재구성 (trailing PORT_t 선별 + EW) → 2.6124 대조 ──
wf("\n=== parity: Ppure_W36_K20 재구성 (R10 저장 2.6124, 동일기간 절단) ===")
PP <- list()
for(a in anchors){
  tt_a <- ANCH[[as.character(a)]]$tt; fin <- tt_a[is.finite(tt_a)]
  PP[[as.character(a)]] <- names(sort(fin, decreasing=TRUE))[seq_len(min(K20, length(fin)))]
}
build_ppure <- function(){
  deploy_idx <- (W36+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i]); facs <- intersect(PP[[as.character(ga)]], FW_FACS)
    if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}
ppg <- gates(build_ppure(), "Ppure_rebuild")
parity_full <- if(!is.null(ppg)) ppg$dt$port_t_capwt else NA_real_
parity_trunc <- if(!is.null(ppg)) nwt(ppg$pr[date <= as.Date("2026-04-30"), act_bm]) else NA_real_
wf("  Ppure 재구성: full(n=%d)=%.4f | 기간절단(<=2026-04)=%.4f vs R10 저장 2.6124 (|d|=%.4f)",
   if(!is.null(ppg)) ppg$dt$n_months else 0L, parity_full, parity_trunc, abs(parity_trunc-2.6124))
if(!is.null(ppg)) RES[["Ppure_rebuild"]] <- ppg$dt

## ── paired NW-t (사전등록 비교 세트) ──
pair1 <- function(la, lb, col="act_bm"){ if(is.null(PR[[la]])||is.null(PR[[lb]])) return(NULL)
  m <- merge(PR[[la]][,.(date, a=get(col))], PR[[lb]][,.(date, b=get(col))], by="date")
  d <- m$a - m$b
  data.table(model=la, base=lb, basis=col, mean_diff_ann=mean(d,na.rm=TRUE)*12, paired_t=nwt(d), n=nrow(m)) }
PAIRS <- list(c("W_portt","base"), c("W_icir","base"), c("W_famfix","base"), c("W_ivar","base"),
              c("W_portt","W_icir"))
paired <- list()
for(p in PAIRS){ for(cl in c("act_bm","act")){
  pp <- pair1(p[1], p[2], cl); if(!is.null(pp)) paired[[length(paired)+1]] <- pp } }
PAIRED <- rbindlist(paired, fill=TRUE)
wf("\n=== paired NW-t (사전등록 primary = W_portt vs base cap-w >= %.1f) ===", PAIRED_KILL)
for(i in seq_len(nrow(PAIRED))) wf("  [%-9s vs %-8s | %-6s] d(ann)=%+.4f paired_t=%+.3f (n=%d)",
  PAIRED$model[i], PAIRED$base[i], ifelse(PAIRED$basis[i]=="act_bm","cap-w","EW-uni"),
  PAIRED$mean_diff_ann[i], PAIRED$paired_t[i], PAIRED$n[i])

## ── 판정 ──
prim <- PAIRED[model=="W_portt" & base=="base" & basis=="act_bm", paired_t]
KILL <- !(length(prim)==1 && is.finite(prim) && prim >= PAIRED_KILL)
wp_pt <- TAB[model=="W_portt", port_t_capwt]
vs_ceiling <- wp_pt - CEILING_CAPW
wf("\n=== 판정 ===")
wf("  primary paired(W_portt vs base, cap-w) = %+.3f -> KILL(config-scoped negative)=%s", prim, KILL)
wf("  W_portt cap-w PORT_t=%.3f vs 천장 %.3f (d=%+.3f) | HARD 2.95 = %s", wp_pt, CEILING_CAPW, vs_ceiling, wp_pt>=GATE_PT)

## ── cap-tier 분해 ──
wf("\n=== cap-tier 보유 분해 (top-25 EW) ===")
for(i in seq_len(nrow(CONCT))){ r<-CONCT[i]
  wf("  %-9s MEGA=%.3f MID=%.3f OTHER=%.3f UNRK=%.3f", r$model, r$w_MEGA, r$w_MID, r$w_OTHER, r$w_UNRANKED) }

## ── advisory 진단 (W_portt): rank IC / ICIR / monotonicity / subperiod ──
adv_diag <- function(comp){
  m <- merge(comp[,.(signal_date, security_id, score)], ret, by=c("signal_date","security_id"))
  icm <- m[, .(ic = suppressWarnings(cor(score, Ret_1m, method="spearman", use="complete.obs")), n=.N), by=signal_date]
  icm <- icm[is.finite(ic) & n>=30]
  ic_mean <- mean(icm$ic); icir <- ic_mean/sd(icm$ic)
  harvey_t <- ic_mean/sd(icm$ic)*sqrt(nrow(icm))
  m[, dec := cut(frank(-score, ties.method="first"), breaks=quantile(seq_len(.N), probs=0:10/10),
                 labels=FALSE, include.lowest=TRUE), by=signal_date]
  dr <- m[, .(r=mean(Ret_1m,na.rm=TRUE)), by=dec][order(dec)]
  mono <- suppressWarnings(cor(dr$dec, dr$r, method="spearman"))
  sp <- sapply(list(c("2008-01-01","2014-12-31"),c("2015-01-01","2019-12-31"),c("2020-01-01","2026-12-31")),
    function(rg){ s<-icm[signal_date>=as.Date(rg[1]) & signal_date<=as.Date(rg[2])]
      if(nrow(s)<12) NA_real_ else mean(s$ic) })
  subst <- if(all(is.finite(sp)) && max(abs(sp))>0) min(sp)/max(sp) else NA_real_
  list(rank_ic=ic_mean, icir=icir, harvey_t=harvey_t, monotonicity=-mono, subperiod_ics=sp, subperiod_stability=subst,
       n_ic_months=nrow(icm))
}
AD <- adv_diag(COMP[["W_portt"]])
wf("\n=== advisory 진단 (W_portt): rank_ic=%.4f icir=%.3f harvey_t=%.2f mono=%.2f substab=%.2f (subICs: %s) ===",
   AD$rank_ic, AD$icir, AD$harvey_t, AD$monotonicity, AD$subperiod_stability,
   paste(sprintf("%.4f", AD$subperiod_ics), collapse="/"))

## ── dual-basis 계약 진단 (W_portt canonical diag) ──
dw <- CS_KEEP[["W_portt"]]
if(!is.null(dw$diag_ew_universe)){
  de <- dw$diag_ew_universe
  wf("dual-basis(W_portt): EW-uni PORT_t=%.3f post17_t=%.3f oos_approx=%.3f",
     de$portfolio_alpha_t_nw_lag3, de$post2017_t_nw_lag3, de$oos_retention_approx)
}

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=CFG_HASH,
  meta=list(as_of_date="2026-08-02", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"),
            source_version="WT003_v1", n_sig=n_sig, date_range=as.character(range(sig_dates))),
  results=rbindlist(RES, fill=TRUE), paired=PAIRED, concentration=CONCT,
  parity=list(ppure_rebuild_full=parity_full, ppure_rebuild_trunc_2026_04=parity_trunc,
              r10_stored=2.6124, delta=abs(parity_trunc-2.6124)),
  primary_paired=prim, kill=KILL, w_portt_capwt=wp_pt, vs_ceiling=vs_ceiling,
  advisory_w_portt=AD[c("rank_ic","icir","harvey_t","monotonicity","subperiod_stability","n_ic_months")],
  subperiod_ics=AD$subperiod_ics,
  dual_basis_w_portt=if(!is.null(dw$diag_ew_universe)) list(
    ew_uni_port_t=dw$diag_ew_universe$portfolio_alpha_t_nw_lag3,
    ew_uni_post2017_t=dw$diag_ew_universe$post2017_t_nw_lag3,
    ew_uni_oos_approx=dw$diag_ew_universe$oos_retention_approx) else NULL)
saveRDS(list(res=res, PR=PR, TAB=TAB, PAIRED=PAIRED, COMP_final=COMP[["W_portt"]][signal_date==max(signal_date)],
             ANCH_last=ANCH[[as.character(max(anchors))]]),
        file.path(OUT, sprintf("wt003_full_%s.rds", RUNTAG)))
write_parquet(rbindlist(RES, fill=TRUE), file.path(OUT, sprintf("wt003_gates_%s.parquet", RUNTAG)))
write_parquet(PAIRED, file.path(OUT, sprintf("wt003_paired_%s.parquet", RUNTAG)))
write_parquet(CONCT, file.path(OUT, sprintf("wt003_conc_%s.parquet", RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("wt003_summary_%s.json", RUNTAG)),
                     auto_unbox=TRUE, pretty=TRUE, digits=4)
## alpha_scores: W_portt 전월 패널 (2008-01 ~ 2026-06 emit월 포함)
write_parquet(COMP[["W_portt"]][,.(Date=signal_date, Ticker=security_id, score)],
              file.path(OUT, "alpha_scores.parquet"))
close(con)
cat(sprintf("WT003_DONE. KILL=%s primary=%.3f wp_pt=%.3f parity_d=%.4f log=%s\n",
    KILL, prim, wp_pt, abs(parity_trunc-2.6124), logf))
cat(readLines(logf, encoding="UTF-8"), sep="\n")
