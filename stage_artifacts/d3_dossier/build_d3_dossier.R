## build_d3_dossier.R — N1: D3형(벤치-상대 배포성) 결정 패키지 실사 (2026-07-13 야간)
## ─────────────────────────────────────────────────────────────────────────────
## 목적: R8이 자격 회복시킨 R6 P-pure(W36_K20) + V02_EP(FQ-009)의 벤치-상대 배포
##       결정을 위한 실측 재료 — 수용력(capacity)·추적특성·비용 현실성.
## 규율: 재측정 아님(수익 계열은 기존 계약 산출 재구성-parity 검증 후 소비).
##       거래대금/상관/TE/시나리오 = 실사 산술(due-diligence arithmetic) 라벨.
##       book/실주문 무변경. 신규 백테 없음(선별·비용 컨벤션은 canonical_screen_bt 복제).
## metric_type 라벨:
##   - 수익 시계열: canonical_screen 재구성 (R6/R7 저장 계열과 parity 검증 — Δ=0 요구)
##   - capacity / TE / corr / 비용 시나리오: due_diligence_arithmetic (게이트/판정 비바인딩)
## vintage: pin_cache tag=d3_dossier_20260713 (rawdata/pure_factor_scores/factor_group_scores/panel)
## ─────────────────────────────────────────────────────────────────────────────
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(sandwich); library(lmtest); library(jsonlite)
})
setDTthreads(1); try(arrow::set_cpu_count(1), silent=TRUE); try(arrow::set_io_thread_count(2), silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
source("02_Infrastructure/config.R")
source("02_Infrastructure/data/pin_cache.R")
source("02_Infrastructure/ramp/factor_validation.R")   # build_monthly_forward_returns

OUT <- "stage_artifacts/d3_dossier"; dir.create(OUT, recursive=TRUE, showWarnings=FALSE)
logf <- file.path(OUT, "_build_d3_dossier_log.txt")
con <- file(logf, "w", encoding="UTF-8")
w  <- function(...){ writeLines(paste0(...), con); flush(con) }
wf <- function(...){ w(sprintf(...)) }

PIN_TAG <- "d3_dossier_20260713"
PIN_FILES <- c(".cache/rawdata.parquet",
               "outputs/ramp/pure_factor_scores.parquet",
               "outputs/ramp/factor_group_scores.parquet",
               "outputs/ramp/r6_factor_deployzone_active.parquet",
               "06_Registry/ramp/approved_factor_library.parquet")
if (!dir.exists(file.path(".cache/pins", PIN_TAG))) {
  pin_cache(PIN_FILES, PIN_TAG)
}
pp <- function(p) read_pinned(p, PIN_TAG)
wf("=== D3 dossier 실사 (pin tag=%s) ===", PIN_TAG)

TOP_N <- 25L; COST_BPS <- 15; LIQ_MIN <- 2e8; W36 <- 36L; K20 <- 20L
PART_RATE <- 0.10   # 참여율 10%/일 가정 (mandate)

## ── 공용 함수 (R6 러너/계약과 동일 산식) ──────────────────────────────────────
zc  <- function(x){ m<-mean(x,na.rm=TRUE); s<-sd(x,na.rm=TRUE); if(is.na(s)||s<1e-9) x-m else (x-m)/s }
srf <- function(x){ x<-x[is.finite(x)]; if(length(x)<6) return(NA_real_); mean(x)/sd(x)*sqrt(12) }
nwt <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(NA_real_)
  m<-lm(x~1); as.numeric(coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))[1,3]) }
oos3 <- function(act){ .splits<-c(0.55,0.65,0.75)
  r <- sapply(.splits, function(fr){ k<-floor(length(act)*fr)
    if(k<12||(length(act)-k)<6) return(NA_real_)
    .is<-srf(act[1:k]); .oo<-srf(act[(k+1):length(act)])
    if(!is.na(.is)&&.is>0) .oo/.is else NA_real_ })
  median(r, na.rm=TRUE) }

## ── 데이터 (R6와 동일 소스, pin 경유) ────────────────────────────────────────
af <- as.data.table(read_parquet(pp("06_Registry/ramp/approved_factor_library.parquet")))
APPROVED <- af[status=="approved", factor_id]

g <- as.data.table(read_parquet(pp("outputs/ramp/factor_group_scores.parquet")))
g[, signal_date := as.Date(signal_date)]
sig_dates <- sort(unique(g$signal_date)); n_sig <- length(sig_dates); rm(g)

.need <- c("Date","Ticker","Close","K200","KQ150","Vol","Size","Ret","Sector","BM_Ret")
rawme <- as.data.table(read_parquet(pp(".cache/rawdata.parquet"), col_select=all_of(.need)))
rawme[, Date := as.Date(Date)]
.udates <- sort(unique(rawme$Date))
.me <- as.Date(vapply(sig_dates, function(d){ v <- .udates[.udates <= d]
  if(length(v)) as.character(max(v)) else NA_character_ }, character(1)))
rawme_f <- rawme[Date %in% .me[!is.na(.me)]]
fwd <- build_monthly_forward_returns(rawme_f, sig_dates)
RET_DT   <- fwd$returns_dt[,.(Date=as.Date(Date), Ticker, Ret_1m)]
BENCH_DT <- fwd$bench_dt[,.(Date=as.Date(Date), BM_Ret)]
LIQ_DT   <- fwd$liq_dt[,.(Date=as.Date(Date), Ticker, adv)]
ewb <- fwd$returns_dt[, .(ew=mean(Ret_1m,na.rm=TRUE)), by=.(date=as.Date(Date))]
## K200/KQ150 멤버십 (월말 기준 — 보유 tier/시장 구분용)
## rawme_f Date = 실제 월말 거래일(.me) / W Date = signal 캘린더 월말 → sig_date로 매핑
me_map <- data.table(Date_me=.me, Date=sig_dates)[!is.na(Date_me)]
memb <- merge(rawme_f[, .(Date_me=as.Date(Date), Ticker, K200=(K200==TRUE), KQ150=(KQ150==TRUE), Size)],
              me_map, by="Date_me")[, .(Date, Ticker, K200, KQ150, Size)]
rm(rawme_f); invisible(gc())

sc <- as.data.table(read_parquet(pp("outputs/ramp/pure_factor_scores.parquet"),
        col_select=c("signal_date","security_id","factor_id","z")))
sc <- sc[factor_id %in% APPROVED]; sc[, signal_date := as.Date(signal_date)]
POOL_FACS <- sort(intersect(APPROVED, unique(sc$factor_id)))
wf("substrate: %d approved factors | %d sig months %s~%s", length(POOL_FACS), n_sig,
   as.character(sig_dates[1]), as.character(sig_dates[n_sig]))

## ── 선별 궤적 (R6 캐시 그대로 소비 — 재선별 아님) ─────────────────────────────
sel_traj <- readRDS(".cache/_ramp_r6_sel_20260711.rds")
anchors36 <- sel_traj[["36"]]$anchors

## ── P-pure W36_K20 점수 재구성 (R6 build_arm_score 복제) ─────────────────────
fw <- dcast(sc, signal_date + security_id ~ factor_id, value.var="z")
FW_FACS <- intersect(POOL_FACS, names(fw))
fw_z <- fw[, c("signal_date","security_id", FW_FACS), with=FALSE]; setkey(fw_z, signal_date)
rm(fw); invisible(gc())

build_ppure_score <- function(W, k){
  anchors <- sel_traj[[as.character(W)]]$anchors; deploy_idx <- (W+1L):(n_sig-1L); rows <- list()
  for(i in deploy_idx){
    ga <- max(anchors[anchors <= i])
    facs <- intersect(sel_traj[[as.character(W)]]$traj[[as.character(ga)]]$pool[[paste0("K",k)]], FW_FACS)
    if(length(facs)==0) next
    sub <- fw_z[.(sig_dates[i])]; if(nrow(sub)==0) next
    Xz <- sub[, lapply(.SD, zc), .SDcols=facs]; Xm <- as.matrix(Xz); Xm[is.na(Xm)] <- 0
    rows[[as.character(i)]] <- data.table(signal_date=sig_dates[i], security_id=sub$security_id, score=rowMeans(Xm))
  }
  s <- rbindlist(rows); s[, score := zc(score), by=signal_date]; s
}

## ── canonical 선별/비용 복제 (canonical_screen_bt 내부와 동일 코드경로) ────────
##    반환: W(월별 보유+비중), port(월별 gross/traded/cost/ret_net), dw(월별 종목단 |Δw|)
canon_holdings <- function(score_dt, label){
  S <- score_dt[!is.na(score), .(Date=as.Date(signal_date), Ticker=security_id, score)]
  S <- merge(S, LIQ_DT[, .(Date, Ticker, adv)], by=c("Date","Ticker"), all.x=TRUE)
  S <- S[is.na(adv) | adv >= LIQ_MIN]; S[, adv := NULL]
  R <- RET_DT[!is.na(Ret_1m)]
  setorder(S, Date, -score)
  W <- S[, { n <- min(TOP_N, .N); .(Ticker=Ticker[seq_len(n)], w=rep(1/n, n)) }, by=Date]
  WR <- merge(W, R[, .(Date, Ticker, Ret_1m)], by=c("Date","Ticker"), all.x=TRUE)
  WR[is.na(Ret_1m), Ret_1m := 0]
  port <- WR[, .(port_gross=sum(w*Ret_1m)), by=Date]
  dts <- sort(unique(W$Date))
  traded <- numeric(length(dts)); names(traded) <- as.character(dts)
  dw_rows <- list()
  prev <- data.table(Ticker=character(0), w=numeric(0))
  for(i in seq_along(dts)){
    cur <- W[Date==dts[i], .(Ticker, w)]
    m <- merge(cur, prev, by="Ticker", all=TRUE, suffixes=c("_cur","_prev"))
    m[is.na(w_cur), w_cur := 0]; m[is.na(w_prev), w_prev := 0]
    traded[i] <- sum(abs(m$w_cur - m$w_prev))
    dw_rows[[i]] <- data.table(Date=dts[i], Ticker=m$Ticker, dw=abs(m$w_cur - m$w_prev))
    prev <- cur
  }
  setorder(port, Date)
  port[, traded := traded[as.character(Date)]]
  port[, cost := traded * COST_BPS/1e4]
  port[, ret_net := port_gross - cost]
  wf("  [%s] months=%d turnover_annual=%.4f (mean traded x12)", label, nrow(port), mean(port$traded)*12)
  list(W=W, port=port, dw=rbindlist(dw_rows))
}

## ═══════════ 1. P-pure W36_K20 재구성 + parity ═══════════
wf("\n=== 1. P-pure W36_K20 보유 재구성 + parity ===")
pp_sc <- build_ppure_score(W36, K20)
PPH <- canon_holdings(pp_sc, "Ppure_W36_K20")
r6 <- readRDS(".cache/_ramp_r6_20260711.rds")
st <- as.data.table(r6$PR[["Ppure_W36_K20"]]); st[, date := as.Date(date)]
pm <- merge(PPH$port[, .(date=Date, ret_net_new=ret_net)], st[, .(date, ret_net_st=ret_net)], by="date")
PAR_PP <- max(abs(pm$ret_net_new - pm$ret_net_st))
wf("  parity vs R6 stored PR: n=%d max|d ret_net|=%.3e -> %s", nrow(pm), PAR_PP,
   ifelse(PAR_PP < 1e-10, "PASS(bit-consistent)", "FAIL"))
if (PAR_PP >= 1e-10) w("  ★ WARNING: parity 미달 — capacity/시나리오 수치를 재구성 계열로 라벨 강등해야 함")

## EW-basis active 재구성 + 검증 (R8 3.9191)
pp_pr <- merge(PPH$port[, .(date=Date, ret_net, traded)], ewb, by="date")
pp_pr <- merge(pp_pr, BENCH_DT[, .(date=Date, bm=BM_Ret)], by="date")
pp_pr[, act_ew := ret_net - ew]; pp_pr[, act_bm := ret_net - bm]
wf("  EW PORT_t(NW lag3) = %.4f (R8 저장 3.9191) | cap-w PORT_t = %.4f (저장 2.6124)",
   nwt(pp_pr$act_ew), nwt(pp_pr$act_bm))
wf("  TE(EW, ann) = %.4f (R7 저장 0.1176) | corr(port, EW bench) = %.4f (저장 0.8951)",
   sd(pp_pr$act_ew)*sqrt(12), cor(pp_pr$ret_net, pp_pr$ew))
wf("  EW IR = %.4f | EW oos(3-split med) = %.4f (저장 0.5064)", srf(pp_pr$act_ew), oos3(pp_pr$act_ew))

## ═══════════ 2. V02_EP 재구성 + parity (R6 panel 대비) ═══════════
wf("\n=== 2. V02_EP top-25 EW 재구성 + parity ===")
v02_sc <- sc[factor_id=="V02_EP", .(signal_date, security_id, score=z)][!is.na(score)]
VPH <- canon_holdings(v02_sc, "V02_EP")
PANEL <- as.data.table(read_parquet(pp("outputs/ramp/r6_factor_deployzone_active.parquet")))
PANEL[, signal_date := as.Date(signal_date)]
vst <- PANEL[factor_id=="V02_EP", .(date=signal_date, ret_net_st=ret_net)]
vm <- merge(VPH$port[, .(date=Date, ret_net_new=ret_net)], vst, by="date")
PAR_V02 <- max(abs(vm$ret_net_new - vm$ret_net_st))
wf("  parity vs R6 panel: n=%d max|d ret_net|=%.3e -> %s", nrow(vm), PAR_V02,
   ifelse(PAR_V02 < 1e-10, "PASS(bit-consistent)", "FAIL"))
v02_pr <- merge(VPH$port[, .(date=Date, ret_net, traded)], ewb, by="date")
v02_pr <- merge(v02_pr, BENCH_DT[, .(date=Date, bm=BM_Ret)], by="date")
v02_pr[, act_ew := ret_net - ew]; v02_pr[, act_bm := ret_net - bm]
wf("  V02_EP: EW PORT_t=%.4f | cap-w PORT_t=%.4f (R6 panel full 2.047) | EW IR=%.4f | EW oos=%.4f | TE(EW)=%.4f",
   nwt(v02_pr$act_ew), nwt(v02_pr$act_bm), srf(v02_pr$act_ew), oos3(v02_pr$act_ew), sd(v02_pr$act_ew)*sqrt(12))

## ═══════════ 3. ADV20 (일별 rawdata 20거래일 평균 거래대금) ═══════════
wf("\n=== 3. ADV20 산출 (실사 산술 — 일별 Vol x Close 20거래일 평균) ===")
held_tk <- unique(c(PPH$W$Ticker, VPH$W$Ticker))
wf("  보유 유니언 종목수 = %d", length(held_tk))
DV <- as.data.table(read_parquet(pp(".cache/rawdata.parquet"), col_select=c("Date","Ticker","Vol","Close")))
DV[, Date := as.Date(Date)]
cal <- sort(unique(DV$Date))                       # 전체 거래 캘린더 (필터 前)
DV <- DV[Ticker %in% held_tk]
DV[, val := as.numeric(Vol) * as.numeric(Close)]
DV <- DV[, .(Date, Ticker, val)]; setkey(DV, Date)
hold_dates <- sort(unique(c(PPH$W$Date, VPH$W$Date)))
adv_rows <- list()
for(d in as.list(hold_dates)){
  d <- as.Date(d)
  wnd <- tail(cal[cal <= d], 20)
  if(length(wnd) < 10) next
  sub <- DV[.(wnd), nomatch=0]
  a <- sub[, .(adv20=mean(val, na.rm=TRUE), n_obs=sum(is.finite(val))), by=Ticker]
  a[, Date := d]
  adv_rows[[as.character(d)]] <- a
}
ADV <- rbindlist(adv_rows)
rm(DV); invisible(gc())
wf("  ADV20 rows=%d (%d 리밸월)", nrow(ADV), length(unique(ADV$Date)))

## ═══════════ 4. Capacity (참여율 10%/일) ═══════════
## 정의(실사 산술):
##   cap_1d  = min_i [PART_RATE x ADV20_i / w_i]   — 신규 전량 구축을 1거래일에 끝낼 수 있는 포트 규모 상한
##   cap_5d  = 5 x cap_1d                          — 5거래일 분할 구축 시 상한(선형)
##   build_days(F) = max_i [F x w_i / (PART_RATE x ADV20_i)]      — 규모 F 전량 구축 소요일
##   rebal_days(F) = max_i [F x |dw_i| / (PART_RATE x ADV20_i)]   — 규모 F 월간 리밸 소요일
cap_table <- function(HP, label){
  H <- merge(HP$W, ADV, by=c("Date","Ticker"), all.x=TRUE)
  H <- merge(H, memb[, .(Date, Ticker, K200, KQ150, Size)], by=c("Date","Ticker"), all.x=TRUE)
  H[n_obs < 10, adv20 := NA_real_]
  capm <- H[, .(
    n_hold      = .N,
    n_adv_na    = sum(is.na(adv20)),
    min_adv     = suppressWarnings(min(adv20, na.rm=TRUE)),
    p25_adv     = quantile(adv20, 0.25, na.rm=TRUE),
    med_adv     = median(adv20, na.rm=TRUE),
    n_below_1e9 = sum(adv20 < 1e9, na.rm=TRUE),
    n_below_5e8 = sum(adv20 < 5e8, na.rm=TRUE),
    k200_share  = mean(K200==TRUE, na.rm=TRUE),
    kq150_share = mean(KQ150==TRUE, na.rm=TRUE),
    cap_1d      = suppressWarnings(min(PART_RATE * adv20 / w, na.rm=TRUE))
  ), by=Date]
  capm[!is.finite(min_adv), c("min_adv","cap_1d") := NA_real_]
  capm[, cap_5d := 5 * cap_1d]
  wf("  [%s] cap_1d(억): med=%.1f p10=%.1f worst=%.1f | 최근36m med=%.1f | ADV<10억 보유수 med=%.1f",
     label, median(capm$cap_1d,na.rm=TRUE)/1e8, quantile(capm$cap_1d,0.10,na.rm=TRUE)/1e8,
     min(capm$cap_1d,na.rm=TRUE)/1e8, median(tail(capm[order(Date)],36)$cap_1d,na.rm=TRUE)/1e8,
     median(capm$n_below_1e9,na.rm=TRUE))
  list(H=H, capm=capm)
}
wf("\n=== 4. Capacity ===")
CP <- cap_table(PPH, "P-pure W36_K20")
CV <- cap_table(VPH, "V02_EP")

## 규모별 소요일 (구축/월간리밸) — 규모 그리드
SIZES <- c(1e9, 3e9, 5e9, 1e10, 3e10)   # 10억~300억
days_table <- function(HP, CT, label){
  H <- CT$H
  DWA <- merge(HP$dw[dw > 1e-12], ADV, by=c("Date","Ticker"), all.x=TRUE)
  DWA[n_obs < 10, adv20 := NA_real_]
  rows <- list()
  for(F in SIZES){
    bd <- H[, .(build_days = suppressWarnings(max(F*w/(PART_RATE*adv20), na.rm=TRUE))), by=Date]
    rd <- DWA[, .(rebal_days = suppressWarnings(max(F*dw/(PART_RATE*adv20), na.rm=TRUE))), by=Date]
    bd[!is.finite(build_days), build_days := NA_real_]; rd[!is.finite(rebal_days), rebal_days := NA_real_]
    bd36 <- tail(bd[order(Date)], 36); rd36 <- tail(rd[order(Date)], 36)
    rows[[as.character(F)]] <- data.table(fund_krw=F,
      build_days_med=median(bd$build_days,na.rm=TRUE), build_days_p90=quantile(bd$build_days,0.9,na.rm=TRUE),
      build_days_med_36m=median(bd36$build_days,na.rm=TRUE),
      rebal_days_med=median(rd$rebal_days,na.rm=TRUE), rebal_days_p90=quantile(rd$rebal_days,0.9,na.rm=TRUE),
      rebal_days_med_36m=median(rd36$rebal_days,na.rm=TRUE))
  }
  dt <- rbindlist(rows)
  wf("  [%s] 규모별 소요일(중앙값, 전기간/최근36m):", label)
  for(i in seq_len(nrow(dt))) wf("    %6.0f억: 구축 %.1f/%.1f일 · 월리밸 %.2f/%.2f일",
    dt$fund_krw[i]/1e8, dt$build_days_med[i], dt$build_days_med_36m[i], dt$rebal_days_med[i], dt$rebal_days_med_36m[i])
  dt
}
DP <- days_table(PPH, CP, "P-pure")
DVt <- days_table(VPH, CV, "V02_EP")

## ═══════════ 5. 비용 시나리오 (15/20/30/40/50 bps one-way) ═══════════
wf("\n=== 5. 비용 시나리오 (실사 산술 — 계약 계열에서 증분 비용 차감) ===")
BPS_GRID <- c(15, 20, 30, 40, 50)
cost_scen <- function(pr, label){
  rows <- list()
  for(b in BPS_GRID){
    adj <- pr$traded * (b - COST_BPS)/1e4
    ae <- pr$act_ew - adj; ab <- pr$act_bm - adj
    rows[[as.character(b)]] <- data.table(model=label, bps_oneway=b,
      ew_port_t=nwt(ae), ew_ir=srf(ae), ew_oos=oos3(ae),
      capw_port_t=nwt(ab),
      ann_cost_drag=mean(pr$traded)*12*b/1e4)
  }
  dt <- rbindlist(rows)
  for(i in seq_len(nrow(dt))) wf("  [%s] %2.0fbps: EW t=%.3f IR=%.3f oos=%.3f | cap-w t=%.3f | drag=%.2f%%/yr",
    label, dt$bps_oneway[i], dt$ew_port_t[i], dt$ew_ir[i], dt$ew_oos[i], dt$capw_port_t[i], dt$ann_cost_drag[i]*100)
  dt
}
CS_PP <- cost_scen(pp_pr, "Ppure_W36_K20")
CS_V02 <- cost_scen(v02_pr, "V02_EP")
## break-even (EW t = 2.95) 선형보간
be <- function(dt){
  x <- dt$bps_oneway; y <- dt$ew_port_t
  if(all(y > 2.95)) return(Inf); if(all(y < 2.95)) return(NA_real_)
  approx(y, x, xout=2.95)$y }
BE_PP <- be(CS_PP); BE_V02 <- be(CS_V02)
wf("  break-even(EW t=2.95): P-pure ~%.0f bps | V02_EP ~%.0f bps (선형보간, 실사 산술)", BE_PP, BE_V02)

## ═══════════ 6. 추적 특성 + book 간섭 ═══════════
wf("\n=== 6. 추적 특성 ===")
## 상호 중첩 (P-pure vs V02_EP 보유)
ov_pv <- merge(PPH$W[, .(Date, Ticker)], VPH$W[, .(Date, Ticker, v=1)], by=c("Date","Ticker"), all.x=TRUE)
ov_pv_m <- ov_pv[, .(overlap=mean(!is.na(v))), by=Date]
wf("  P-pure vs V02_EP 보유 중첩(월평균) = %.1f%%", mean(ov_pv_m$overlap)*100)
## 두 트랙 active 상관
pv <- merge(pp_pr[, .(date, a=act_ew)], v02_pr[, .(date, b=act_ew)], by="date")
wf("  P-pure vs V02_EP EW-active 상관 = %.3f (n=%d)", cor(pv$a, pv$b), nrow(pv))
## book 종목단 중첩 시도 (bt_result holdings 컴포넌트)
book_overlap <- tryCatch({
  bt <- readRDS("qepm/mailbox/worktask/WT-H20260513_001/output/bt_result_layer5_R05.rds")
  h <- as.data.table(bt$holdings)
  wf("  [book holdings] cols: %s | rows=%d", paste(names(h), collapse=","), nrow(h))
  if(all(c("date","ticker") %in% tolower(names(h)))){
    setnames(h, names(h), tolower(names(h)))
    h[, ym := format(as.Date(date), "%Y-%m")]
    ## P-pure 보유월 = signal월+1 (forward 실현월) — base R 월 증가 (lubridate 미사용)
    ppw <- copy(PPH$W)
    ppw[, ym := { d <- as.Date(Date); m <- as.integer(format(d,"%m")); y <- as.integer(format(d,"%Y"))
                  sprintf("%04d-%02d", y + (m %/% 12L), (m %% 12L) + 1L) }]
    ovb <- merge(ppw[, .(ym, Ticker)], h[, .(ym, Ticker=ticker, b=1)], by=c("ym","Ticker"), all.x=TRUE)
    ovm <- ovb[, .(overlap=mean(!is.na(b))), by=ym]
    list(available=TRUE, mean_overlap=mean(ovm$overlap), n_months=nrow(ovm))
  } else list(available=FALSE, note=paste0("holdings 스키마 비호환: ", paste(names(h), collapse=",")))
}, error=function(e) list(available=FALSE, note=paste0("book holdings 소비 실패: ", conditionMessage(e))))
if(isTRUE(book_overlap$available)){
  wf("  book(STR_1715 M4_R05) 보유 중첩(월평균) = %.1f%% (n=%d)", book_overlap$mean_overlap*100, book_overlap$n_months)
} else wf("  book 종목단 중첩 = 산출 불가 (%s) — R8 e3 수익상관 재인용으로 대체", book_overlap$note)

## ═══════════ 7. 저장 ═══════════
wf("\n=== 7. 저장 ===")
write_parquet(CP$capm, file.path(OUT, "capacity_monthly_ppure.parquet"))
write_parquet(CV$capm, file.path(OUT, "capacity_monthly_v02ep.parquet"))
fwrite(CP$capm, file.path(OUT, "capacity_monthly_ppure.csv"))
fwrite(CV$capm, file.path(OUT, "capacity_monthly_v02ep.csv"))
fwrite(rbind(CS_PP, CS_V02), file.path(OUT, "cost_scenarios.csv"))
fwrite(DP[, model := "Ppure_W36_K20"][], file.path(OUT, "days_to_build_ppure.csv"))
fwrite(DVt[, model := "V02_EP"][], file.path(OUT, "days_to_build_v02ep.csv"))
## 최신월 보유 스냅샷 (도훈 열람용)
snap <- function(CT, label){
  H <- CT$H[Date == max(Date)]
  H <- H[order(-w, -adv20)][, .(Ticker, w=round(w,4), adv20_krw=round(adv20), K200, KQ150)]
  fwrite(H, file.path(OUT, sprintf("holdings_latest_%s.csv", label))); H }
sn_pp <- snap(CP, "ppure"); sn_v02 <- snap(CV, "v02ep")
write_parquet(PPH$W, file.path(OUT, "holdings_monthly_ppure.parquet"))
write_parquet(VPH$W, file.path(OUT, "holdings_monthly_v02ep.parquet"))
saveRDS(list(pp_pr=pp_pr, v02_pr=v02_pr, CS_PP=CS_PP, CS_V02=CS_V02,
             capm_pp=CP$capm, capm_v02=CV$capm, DP=DP, DVt=DVt,
             ov_pv_m=ov_pv_m, book_overlap=book_overlap), file.path(OUT, "_d3_series.rds"))

recent36 <- function(capm) tail(capm[order(Date)], 36)
SUMMARY <- list(
  meta = list(generated_at=format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    pin_tag=PIN_TAG, participation_rate=PART_RATE,
    metric_type_returns="canonical_screen (재구성, parity 검증)",
    metric_type_dossier="due_diligence_arithmetic (게이트/판정 비바인딩 — D3 결정 재료)",
    parity=list(ppure_max_abs_delta=PAR_PP, v02ep_max_abs_delta=PAR_V02)),
  ppure = list(
    ew_port_t=nwt(pp_pr$act_ew), capw_port_t=nwt(pp_pr$act_bm),
    ew_ir=srf(pp_pr$act_ew), ew_oos=oos3(pp_pr$act_ew),
    te_ew_ann=sd(pp_pr$act_ew)*sqrt(12), corr_to_ew_bench=cor(pp_pr$ret_net, pp_pr$ew),
    turnover_annual=mean(pp_pr$traded)*12, n_months=nrow(pp_pr),
    cap_1d_med_krw=median(CP$capm$cap_1d, na.rm=TRUE),
    cap_1d_med_36m_krw=median(recent36(CP$capm)$cap_1d, na.rm=TRUE),
    cap_1d_worst_krw=min(CP$capm$cap_1d, na.rm=TRUE),
    cap_5d_med_36m_krw=median(recent36(CP$capm)$cap_5d, na.rm=TRUE),
    n_below_1e9_med=median(CP$capm$n_below_1e9, na.rm=TRUE),
    k200_share_avg=mean(CP$capm$k200_share, na.rm=TRUE),
    breakeven_bps_ew295=BE_PP,
    cost_scenarios=CS_PP),
  v02ep = list(
    ew_port_t=nwt(v02_pr$act_ew), capw_port_t=nwt(v02_pr$act_bm),
    ew_ir=srf(v02_pr$act_ew), ew_oos=oos3(v02_pr$act_ew),
    te_ew_ann=sd(v02_pr$act_ew)*sqrt(12),
    turnover_annual=mean(v02_pr$traded)*12, n_months=nrow(v02_pr),
    cap_1d_med_krw=median(CV$capm$cap_1d, na.rm=TRUE),
    cap_1d_med_36m_krw=median(recent36(CV$capm)$cap_1d, na.rm=TRUE),
    cap_1d_worst_krw=min(CV$capm$cap_1d, na.rm=TRUE),
    cap_5d_med_36m_krw=median(recent36(CV$capm)$cap_5d, na.rm=TRUE),
    n_below_1e9_med=median(CV$capm$n_below_1e9, na.rm=TRUE),
    k200_share_avg=mean(CV$capm$k200_share, na.rm=TRUE),
    breakeven_bps_ew295=BE_V02,
    cost_scenarios=CS_V02),
  cross = list(ppure_v02_holdings_overlap=mean(ov_pv_m$overlap),
               ppure_v02_ew_active_corr=cor(pv$a, pv$b),
               book_overlap=book_overlap,
               r8_recite=list(cor_capw_active=0.324104, cor_ew_active=-0.126796,
                              cor_net=0.638517, marginal_delta_ir_w05=-0.005189)),
  days_to_build = list(ppure=DP, v02ep=DVt)
)
write_json(SUMMARY, file.path(OUT, "d3_summary.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("saved: %s", file.path(OUT, "d3_summary.json"))
close(con)
cat(readLines(logf, encoding="UTF-8"), sep="\n")
cat(sprintf("\nD3_BUILD_DONE parity_pp=%.2e parity_v02=%.2e\n", PAR_PP, PAR_V02))
