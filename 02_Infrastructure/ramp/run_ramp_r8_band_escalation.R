## run_ramp_r8_band_escalation.R — RAMP R8: R7 EW-basis oos 0.51 band escalation 보강증거 3종 실측
## ─────────────────────────────────────────────────────────────────────────────
## 도훈 지시 2026-07-12 "실패를 실패로 규정 말고 자가발전 계속". FQ-016. R7 E2 후속.
## 배경: R7이 EW-oos 0.5064를 단일 0.7 문턱으로 'EW-real 미달' 종결했으나
##   measurement-graduation §3 band [0.5,0.7) escalation(보강증거 2/3 조건부 PASS)을 미적용 = 미소진 판정 절차.
##
## [측정 대상] R6 최선 Ppure_W36_K20의 EW-유니버스 active 수익 시계열 (R7 E2 재구성분 재사용, parity 검증).
## [보강증거 3종 — §3, EW 진단 basis 적용]
##   e1 trailing-subwindow PORT_t>0 : EW-active 3분할 last-third IRf>0 ∧ nwt>0 (v3verify 컨벤션)
##   e2 placebo p<0.05             : EW-active 시계열 대상 월-셔플 placebo(선별 신호 월 재배열→재스크린→EW PORT_t null)
##   e3 book-marginal ΔSR>0 ∧|cor|<0.30 : 현직 book(STR_1715 noLayer4 recon net-active) 대비 상관 + 소량 블렌드 한계 ΔIR
##   holdout은 증거 불가(§3 봉인 원칙) — 미사용.
## [판정 프레임 — 정직 의무]
##   2/3 → EW-basis 조건부 band-PASS = D3형(벤치-상대 배포성) 도훈 결정 재료 자격 회복 (자본 게이트=cap-w authoritative 통과 아님)
##   <2/3 → band FAIL 확정 = EW-real 미달 절차적 완결.
##   이번 실측 = R7 종결의 절차 보완이지 재-sweep 아님(n_trials 증가 없음. escalation=판정 절차).
## [vintage] R7 frozen(Jul-12) 재사용 — 패널 r6_20260711 + rawdata Jul-12(April-gap 백필 후). pin 동일성 기록.
## 단일스레드 · arrow io=2. book 무변경(read-only) · governor 정지.
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; Sys.setenv(QM_ROOT=QM); setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns
source("02_Infrastructure/contracts/canonical_screen_bt.R")
zc <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
`%||%` <- function(a,b) if(is.null(a)||length(a)==0||(length(a)==1&&is.na(a))) b else a
OUT <- "outputs/ramp"; RUNTAG <- "20260712"
N_PLACEBO <- as.integer(Sys.getenv("R8_NPLAC","60"))
logf <- file.path(".cache", sprintf("_ramp_r8_%s.txt", RUNTAG))
con <- file(logf,"w",encoding="UTF-8"); w<-function(...){ writeLines(paste0(...),con); flush(con) }; wf<-function(...){w(sprintf(...))}

IRf <- function(x){x<-x[is.finite(x)];if(length(x)<6)return(NA);mean(x)/sd(x)*sqrt(12)}
nwt <- function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}
oos_ret <- function(act){n<-length(act);md<-sapply(c(.55,.65,.75),function(fr){k<-floor(n*fr);if(k<12||(n-k)<6)return(NA_real_);is<-IRf(act[1:k]);oo<-IRf(act[(k+1):n]);if(!is.na(is)&&is>0)oo/is else NA_real_});median(md,na.rm=TRUE)}

## ── 사전등록 (판정 절차 보완 — n_trials 증가 없음) ──
GATE_OOS <- 0.7; BAND_LO <- 0.5; BAND_HI <- 0.7; EW_REAL_PT <- 2.95
PREREG <- list(mode="RAMP", round="R8", fq="FQ-016",
  procedure="measurement-graduation §3 band [0.5,0.7) escalation on EW-basis oos_retention (R7 E2)",
  record_type="judgment_procedure_completion (NOT a re-sweep; n_trials unchanged from R7 family=20)",
  target="R6 best Ppure_W36_K20 EW-universe active return series (R7 E2 재구성 재사용)",
  evidence=list(
    e1="trailing-subwindow PORT_t>0 : EW-active 3-split last-third IRf>0 AND nwt(NW lag3)>0",
    e2=sprintf("placebo p<0.05 : month-shuffle of selection scores -> re-screen -> EW-active PORT_t null (N=%d, v3verify convention)", N_PLACEBO),
    e3="book-marginal deltaSR>0 AND |cor|<0.30 : STR_1715 noLayer4 recon net-active(vs KOSPI200) blend"),
  rule="oos in [0.5,0.7) AND sum(e1,e2,e3)>=2 -> band_escalated (conditional PASS). holdout=inadmissible(sealed).",
  frame_pass="EW-basis conditional band-PASS = D3 (benchmark-relative deployability) decision material. NOT capital gate (cap-w authoritative unchanged FAIL).",
  frame_fail="band FAIL = EW-real 미달 procedurally complete.",
  incumbent_book="STR_1715_on_M4_R05_noLayer4_PG2 (book_state incumbent_book_ir=1.416, ir_convention=net_active_recon_v1, KOSPI200, 269m)",
  vintage_pin="R7 frozen Jul-12: candidate series from .cache/_ramp_r7_20260712.rds PR[[capwrepro_W36_K20]] (=R6 Ppure_W36_K20 bit-identical); substrate panel r6_20260711 + rawdata Jul-12",
  as_of_date="2026-07-12", source_version="RAMP_R8_v1",
  security_id="Ticker (rawdata) -> factor_id z (pure_factor_scores.z=Z_Score_Aligned)")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
PREREG$generated_at <- format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z")
jsonlite::write_json(PREREG, file.path(OUT, sprintf("r8_band_escalation_prereg_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("=== RAMP R8: EW-basis oos band escalation (FQ-016) === config_hash=%s N_placebo=%d", PREREG$config_hash, N_PLACEBO)

## ════════════════ 후보 시계열 (R7 E2 재사용) ════════════════
r7 <- readRDS(".cache/_ramp_r7_20260712.rds")
prc <- r7$PR[["capwrepro_W36_K20"]]      # date, act(EW active), act_bm(cap-w active), ret_net, benchmark_ret
stopifnot(all(c("date","act","act_bm","ret_net","benchmark_ret") %in% names(prc)))
prc <- prc[order(date)]; nC <- nrow(prc)
ew_oos    <- oos_ret(prc$act)
ew_port_t <- nwt(prc$act)
capw_oos  <- oos_ret(prc$act_bm); capw_port_t <- nwt(prc$act_bm)
wf("[candidate] n=%d %s~%s | EW: PORT_t=%.4f IR=%.4f oos=%.4f | cap-w: PORT_t=%.4f oos=%.4f",
   nC, as.character(min(prc$date)), as.character(max(prc$date)), ew_port_t, IRf(prc$act), ew_oos, capw_port_t, capw_oos)
## stored E2 parity
e2s <- r7$res$e2$cap_w
wf("[parity vs R7 stored E2] EWuni Δ=%.2e  ew_oos Δ=%.2e  cap-w_t Δ=%.2e  cap-w_oos Δ=%.2e",
   abs(ew_port_t-e2s$port_t_EWuni), abs(ew_oos-e2s$ew_oos_retention), abs(capw_port_t-e2s$port_t_capwt), abs(capw_oos-e2s$oos_retention))
oos_in_band <- is.finite(ew_oos) && ew_oos>=BAND_LO && ew_oos<BAND_HI
wf("[band eligibility] EW-oos=%.4f in [%.1f,%.1f)=%s (band escalation %s)", ew_oos, BAND_LO, BAND_HI, oos_in_band,
   if(oos_in_band) "ELIGIBLE" else if(ew_oos>=BAND_HI) "N/A (>=0.7 pass)" else "N/A (<0.5 unconditional FAIL)")

## ════════════════ e1: trailing-subwindow PORT_t (EW-basis, last-third) ════════════════
thirds <- split(prc$act, cut(seq_len(nC),3,labels=FALSE))
e1_last_ir <- IRf(thirds[[3]]); e1_last_t <- nwt(thirds[[3]])
e1 <- isTRUE(is.finite(e1_last_ir) && e1_last_ir>0 && is.finite(e1_last_t) && e1_last_t>0)
wf("\n[e1 trailing] EW thirds nwt = %s | last-third IRf=%.4f nwt=%.4f -> e1=%s",
   paste(sprintf("%.2f",sapply(thirds,nwt)),collapse=" / "), e1_last_ir, e1_last_t, e1)

## ════════════════ 데이터 로드 (R7 verbatim, e2 placebo용) ════════════════
wf("\n[data load] rawdata + forward returns + pure scores (R7 vintage)")
t_load0 <- Sys.time()
af <- as.data.table(read_parquet("06_Registry/ramp/approved_factor_library.parquet")); APPROVED <- af[status=="approved", factor_id]
g <- as.data.table(read_parquet(file.path(OUT,"factor_group_scores.parquet"))); g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates)
.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawdata <- as.data.table(read_parquet(".cache/rawdata.parquet", col_select=all_of(.need))); rawdata[,Date:=as.Date(Date)]
.udates <- sort(unique(rawdata$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]; if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawdata <- rawdata[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawdata, sig_dates); rm(rawdata)
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
sc <- as.data.table(read_parquet(file.path(OUT,"pure_factor_scores.parquet"), col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]; POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
wf("[data load] done in %.1fs | n_sig=%d POOL_FACS=%d", as.numeric(difftime(Sys.time(),t_load0,units="secs")), n_sig, length(POOL_FACS))

## panel(cap-w active) -> W36 trailing 선별 재현 (real arm 재빌드용)
PANEL <- as.data.table(read_parquet(file.path(OUT,"r6_factor_deployzone_active.parquet"))); PANEL[, signal_date := as.Date(signal_date)]
PANEL_FACS <- sort(unique(PANEL$factor_id))
Pw_capw <- dcast(PANEL, signal_date ~ factor_id, value.var="active_bm"); setorder(Pw_capw, signal_date)
panel_dates <- Pw_capw$signal_date; n_pm <- length(panel_dates)
Pmat_capw <- as.matrix(Pw_capw[, ..PANEL_FACS]); rownames(Pmat_capw) <- as.character(panel_dates)
WIN <- 36L; KK <- 20L; CAD <- 6L; TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8
trailing_nwt <- function(Pmat, W, a_idx){ lo<-a_idx-W; hi<-a_idx-1L; if(lo<1L) return(NULL); sub<-Pmat[lo:hi,,drop=FALSE]
  apply(sub,2,function(x){x<-x[is.finite(x)];if(length(x)<12)return(NA_real_);m<-lm(x~1);as.numeric(coeftest(m,vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3])}) }
anchors <- seq(WIN+1L, n_sig-1L, by=CAD); sel <- list()
for(a in anchors){ if(a-1L>n_pm) next; tv<-trailing_nwt(Pmat_capw,WIN,a); if(is.null(tv)) next
  ord<-names(sort(tv[is.finite(tv)],decreasing=TRUE)); sel[[as.character(a)]] <- head(ord,KK) }
## fw_z (composite z wide)
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z"); FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
build_arm_score <- function(sel_pools){    # sel_pools: named list anchor_idx->factor pool
  deploy_idx <- (WIN+1L):(n_sig-1L); rows <- list(); ach <- as.integer(names(sel_pools))
  for(i in deploy_idx){ ga <- max(ach[ach<=i]); facs <- intersect(sel_pools[[as.character(ga)]], FW_FACS); if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm)) }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s }
screen_ew_portt <- function(score_dt, lab){
  cs <- tryCatch(canonical_screen_bt(score_dt[,.(Date=as.Date(signal_date),Ticker=security_id,score)], RET_DT, BENCH_DT,
        top_n=TOP_N, cost_bps_oneway=COST_BPS, liq_dt=LIQ_DT, liq_min=LIQ_MIN, run_id="r8", strategy_id=lab),
        error=function(e){ w("  [screen ERR ",lab,"] ",conditionMessage(e)); NULL })
  if(is.null(cs)||is.null(cs$period_returns)) return(NULL)
  pr<-as.data.table(cs$period_returns); pr[,date:=as.Date(date)]; pr<-merge(pr,ewb,by="date",all.x=TRUE)
  list(ew_t=nwt(pr$ret_net-pr$ew), n_months=nrow(pr)) }

## ── real arm 재빌드 + parity (cache PORT_t 3.92와 대조) ──
real_score <- build_arm_score(sel)
rr <- screen_ew_portt(real_score, "real_W36_K20")
real_ew_t <- rr$ew_t
wf("[e2 real re-screen] EW PORT_t=%.4f (cache=%.4f Δ=%.3f) n=%d", real_ew_t, ew_port_t, abs(real_ew_t-ew_port_t), rr$n_months)

## ════════════════ e2: month-shuffle placebo ════════════════
udates <- sort(unique(real_score$signal_date)); nud <- length(udates)
wf("\n[e2 placebo] month-shuffle x %d (선별 score 월 라벨 재배열 -> 재스크린 -> EW PORT_t)", N_PLACEBO)
t_p0 <- Sys.time(); null_t <- numeric(0)
for(d in seq_len(N_PLACEBO)){ set.seed(1000+d)
  perm <- sample(udates); names(perm) <- as.character(udates)   # udates[i] -> perm[i]
  sp <- copy(real_score); sp[, signal_date := perm[as.character(signal_date)]]
  pv <- screen_ew_portt(sp, sprintf("plac_%d",d)); if(!is.null(pv) && is.finite(pv$ew_t)) null_t <- c(null_t, pv$ew_t)
  if(d %% 10 == 0) wf("  ..placebo %d/%d done (%.1fs, valid=%d)", d, N_PLACEBO, as.numeric(difftime(Sys.time(),t_p0,units="secs")), length(null_t)) }
p_plac <- if(length(null_t)) mean(null_t >= real_ew_t) else NA_real_
e2 <- isTRUE(is.finite(p_plac) && p_plac < 0.05)
wf("[e2 placebo] real EW PORT_t=%.3f | null mean=%.3f sd=%.3f p95=%.3f max=%.3f | p(null>=real)=%.4f -> e2=%s (valid draws=%d)",
   real_ew_t, mean(null_t), sd(null_t), quantile(null_t,.95), max(null_t), p_plac, e2, length(null_t))

## ════════════════ e3: book-marginal (STR_1715 noLayer4 net-active) ════════════════
wf("\n[e3 book-marginal] incumbent = STR_1715_on_M4_R05_noLayer4_PG2 (recon net-active vs KOSPI200)")
bt <- readRDS("qepm/mailbox/worktask/WT-D20260702_002/output/bt_result_C_noL4_CLEAN_ann12.rds")
prb <- as.data.table(bt$period_returns)[,.(date=as.Date(date), book_net=ret_net)]
bbm <- as.data.table(bt$benchmark_returns)[,.(date=as.Date(date), kospi_b=benchmark_ret)]
book <- merge(prb, bbm, by="date"); book[, book_act := book_net - kospi_b]
book_ir_full <- IRf(book$book_act)
wf("  [book] n=%d IR(net-active)=%.4f (book_state incumbent_book_ir=1.416)", nrow(book), book_ir_full)
## 월-정합: KOSPI200 fingerprint offset scan (realized_ym 지연 보정, reference-book-benchmark-alignment-realized-ym)
ymI <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))
cand <- data.table(ym=ymI(prc$date), kospi_c=prc$benchmark_ret, cand_actbm=prc$act_bm, cand_actew=prc$act, cand_net=prc$ret_net)
bk   <- data.table(ym=ymI(book$date), kospi_b=book$kospi_b, book_act=book$book_act, book_net=book$book_net)
best_off <- 0L; best_cor <- -Inf
for(off in -3:3){ bk2<-copy(bk); bk2[,ym:=ym+off]; mm<-merge(cand,bk2,by="ym"); if(nrow(mm)<24) next
  cc<-suppressWarnings(cor(mm$kospi_c, mm$kospi_b)); if(is.finite(cc)&&cc>best_cor){best_cor<-cc; best_off<-off} }
bk2<-copy(bk); bk2[,ym:=ym+best_off]; M<-merge(cand,bk2,by="ym"); setorder(M,ym)
wf("  [align] best KOSPI offset=%+d (KOSPI-KOSPI cor=%.4f) -> overlap n=%d", best_off, best_cor, nrow(M))
if(best_cor < 0.98) wf("  [align WARN] KOSPI fingerprint cor<0.98 — 월-정합 불완전, cor/ΔIR 해석 주의")
## 상관 (primary: cap-w net-active vs book net-active; robustness: EW-active, net-return)
cor_capw <- cor(M$cand_actbm, M$book_act); cor_ew <- cor(M$cand_actew, M$book_act); cor_net <- cor(M$cand_net, M$book_net)
wf("  [cor] cap-w active vs book active=%.4f | EW active vs book active=%.4f | net vs net=%.4f", cor_capw, cor_ew, cor_net)
## 소량 블렌드 한계 ΔIR (net-active vs KOSPI200): book_net (1-w) + cand_net w
book_ir_overlap <- IRf(M$book_act)
dsr_tab <- rbindlist(lapply(c(0.05,0.10,0.20), function(wt){
  blend_net <- (1-wt)*M$book_net + wt*M$cand_net; blend_act <- blend_net - (M$book_net - M$book_act)  # blend_act = blend_net - kospi
  data.table(w=wt, ir_blend=IRf(blend_act), delta_ir=IRf(blend_act)-book_ir_overlap) }))
for(i in seq_len(nrow(dsr_tab))) wf("  [blend w=%.2f] IR_blend=%.4f ΔIR=%+.4f", dsr_tab$w[i], dsr_tab$ir_blend[i], dsr_tab$delta_ir[i])
delta_ir_marg <- dsr_tab[w==0.05, delta_ir]     # 한계(가장 소량) ΔIR
e3 <- isTRUE(is.finite(delta_ir_marg) && delta_ir_marg>0 && is.finite(cor_capw) && abs(cor_capw)<0.30)
wf("[e3 book-marginal] marginal ΔIR(w=0.05)=%+.4f (>0=%s) ∧ |cor_capw|=%.3f (<0.30=%s) -> e3=%s",
   delta_ir_marg, delta_ir_marg>0, abs(cor_capw), abs(cor_capw)<0.30, e3)

## ════════════════ 종합 판정 ════════════════
n_pass <- sum(c(e1,e2,e3)); esc_pass <- n_pass>=2L
band_status <- if(!is.finite(ew_oos)) NA_character_ else if(ew_oos>=BAND_HI) "pass" else if(ew_oos<BAND_LO) "fail" else if(esc_pass) "band_escalated" else "band_fail"
## cap-w authoritative 자본 게이트 (불변 — R7)
capw_hard <- list(port_t=capw_port_t>=2.95, oos=capw_oos>=0.7, calmar=(e2s$calmar %||% NA)>=0.64)
capital_gate_pass <- isTRUE(capw_hard$port_t) && isTRUE(capw_hard$oos) && isTRUE(capw_hard$calmar)
ew_real_bandpass <- isTRUE(ew_port_t>=EW_REAL_PT) && identical(band_status,"band_escalated")
wf("\n=== 종합 ===")
wf("  보강증거: e1(trailing)=%s  e2(placebo p=%.3f)=%s  e3(book-marginal)=%s  -> %d/3 -> esc_pass=%s", e1, p_plac, e2, e3, n_pass, esc_pass)
wf("  EW-oos=%.4f band_status=%s", ew_oos, band_status)
wf("  cap-w authoritative(자본 게이트): PORT_t %.2f>=2.95=%s | oos %.2f>=0.7=%s | calmar %.2f>=0.64=%s -> capital_gate=%s",
   capw_port_t, capw_hard$port_t, capw_oos, capw_hard$oos, e2s$calmar %||% NA, capw_hard$calmar, capital_gate_pass)
wf("  EW-real(EW-uni>=2.95 ∧ band_escalated)=%s", ew_real_bandpass)
verdict <- if(ew_real_bandpass) "EW-basis 조건부 band-PASS = D3형(벤치-상대 배포성) 도훈 결정 재료 자격 회복 — 자본 게이트(cap-w authoritative) 통과 아님"
           else "band FAIL 확정 = EW-real 미달 절차적 완결 (cap-w authoritative FAIL 정합)"
wf("  VERDICT: %s", verdict)

## ── 저장 ──
res <- list(prereg=PREREG, config_hash=PREREG$config_hash,
  meta=list(as_of_date="2026-07-12", generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"), source_version="RAMP_R8_v1",
            security_id="Ticker->factor_id z (pure_factor_scores.z=Z_Score_Aligned)", record_type=PREREG$record_type),
  candidate=list(model="Ppure_W36_K20 (R6 best = R7 E2)", n_months=nC, date_range=as.character(range(prc$date)),
    ew_port_t=ew_port_t, ew_ir=IRf(prc$act), ew_oos=ew_oos, capw_port_t=capw_port_t, capw_oos=capw_oos,
    parity_vs_r7=list(ewuni_delta=abs(ew_port_t-e2s$port_t_EWuni), ew_oos_delta=abs(ew_oos-e2s$ew_oos_retention))),
  band=list(oos=ew_oos, lo=BAND_LO, hi=BAND_HI, in_band=oos_in_band, status=band_status),
  evidence=list(
    e1=list(pass=e1, last_third_ir=e1_last_ir, last_third_t=e1_last_t, thirds_t=as.numeric(sapply(thirds,nwt))),
    e2=list(pass=e2, p_placebo=p_plac, real_ew_t=real_ew_t, null_mean=mean(null_t), null_sd=sd(null_t),
            null_p95=as.numeric(quantile(null_t,.95)), null_max=max(null_t), n_draws=length(null_t), n_placebo_req=N_PLACEBO,
            real_rescreen_parity_delta=abs(real_ew_t-ew_port_t)),
    e3=list(pass=e3, cor_capw_active=cor_capw, cor_ew_active=cor_ew, cor_net=cor_net,
            book_ir_full=book_ir_full, book_ir_overlap=book_ir_overlap, marginal_delta_ir_w05=delta_ir_marg,
            blend_table=dsr_tab, align_offset=best_off, align_kospi_cor=best_cor, overlap_n=nrow(M),
            incumbent="STR_1715_on_M4_R05_noLayer4_PG2", incumbent_book_ir_declared=1.416)),
  n_pass=n_pass, esc_pass=esc_pass,
  cap_w_authoritative=list(port_t=capw_port_t, oos=capw_oos, calmar=e2s$calmar, hard=capw_hard, capital_gate_pass=capital_gate_pass),
  ew_real_bandpass=ew_real_bandpass, verdict=verdict,
  frame="escalation은 판정 절차(n_trials 불변). D3=도훈 결정 재료이지 자본 아님. 자본 게이트=cap-w authoritative(불변).")
saveRDS(list(res=res, null_t=null_t, M=M, dsr_tab=dsr_tab), file.path(".cache", sprintf("_ramp_r8_%s.rds",RUNTAG)))
jsonlite::write_json(res, file.path(OUT, sprintf("r8_band_escalation_%s.json",RUNTAG)), auto_unbox=TRUE, pretty=TRUE, digits=6)
ev_tab <- data.table(evidence=c("e1_trailing","e2_placebo","e3_book_marginal"),
  pass=c(e1,e2,e3),
  stat=c(sprintf("last3_IR=%.3f,t=%.3f",e1_last_ir,e1_last_t), sprintf("p=%.4f(real_t=%.2f,null_mean=%.2f)",p_plac,real_ew_t,mean(null_t)),
         sprintf("dIR=%+.4f,|cor|=%.3f",delta_ir_marg,abs(cor_capw))))
write_parquet(ev_tab, file.path(OUT, sprintf("r8_band_escalation_evidence_%s.parquet",RUNTAG)))
write_parquet(data.table(draw=seq_along(null_t), placebo_ew_port_t=null_t), file.path(OUT, sprintf("r8_placebo_null_%s.parquet",RUNTAG)))

close(con)
cat(sprintf("R8_DONE. e1=%s e2=%s(p=%.3f) e3=%s -> %d/3 esc_pass=%s band=%s | EW-real_bandpass=%s capital_gate=%s | log=%s\n",
   e1,e2,p_plac,e3,n_pass,esc_pass,band_status,ew_real_bandpass,capital_gate_pass,logf))
cat(readLines(logf), sep="\n")
