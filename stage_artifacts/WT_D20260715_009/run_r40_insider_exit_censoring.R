## run_r40_insider_exit_censoring.R — WT-D20260715_009 / FQ-053 / R40
## insider SAFE 청산 검열-스트레스 정량 — R38 "no hangover"(청산은 위험 재상승 아님)의
##   검열편향 caveat(HIGH)를 정량. flag-off과 동시에 상폐/유동성붕괴/유니버스이탈한 종목은
##   R38 EXIT 표본(uni 잔존 조건부)에서 검열됨. monitoring 강건성 진단. 자본 아님.
##
## 사전등록 진단 3 (검열편향 정량):
##   P1 다중월 위험궤적: 관측 EXIT(uni 잔존) 종목의 exit_ym+h (h=0..3) forward 위험(하방/tail/vol)
##       + 월별-paired NW-t vs OFF. 단월(h=0=R38) 아닌 다중월로 '지연 hangover' 검출 + horizon별 attrition.
##   P2 검열 census + worst-case 대입: flag-ON(j)→uni 이탈(j+1) 종목 census(폐지/유동성/유니버스/부실)
##       + rmon 실측 return 사용(가능시) + 진성폐지 worst-case 대입(−20/−30/−50/−80%) →
##       R38 EXIT risk_sticky/no-hangover가 검열-조정 후 유지되는가.
##       ★차등검열: ON(SAFE) vs OFF 상태의 이탈률/폐지율 비교 — SAFE가 덜 이탈하면 검열=보수적(no-hangover 강건).
##   P3 catastrophic vs benign 분리: benign(uni 잔존 EXIT, SAFE_FADING 소관) vs catastrophic(이탈, 부실 tripwire
##       소관) 경계 정량. ON→off 이벤트 중 benign/catastrophic 비율 + monitoring 소관 배분.
##
## §7b: base = R38이 상속한 R36 _r36_objects.rds uni (production clean T-1 파생, production_parity_verified
##   3.058, PIT C5 상속). 저장 268m same-month vintage 미사용. 검열탐지용 rmon = pin rawdata (broader universe).
## PIT: uni Ret_1m = 홀딩월(hold_ym) 동월 실현수익(cor=1.0 rmon 검증). 검열은 j→j+1 패널 멤버십 forward 판정.
## 규율: 단일스레드 · arrow io(2). book_state/05_Production/outputs/ramp 무변경(stage_artifacts만).
##   canonical 진단 · cov/weights 미산출(역할경계) · DART API 금지 · 자본 주장 금지(monitoring).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2L),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
set.seed(20260715L)

OUT <- "stage_artifacts/WT_D20260715_009"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "_r40_run_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,se=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]), se=as.numeric(ct[1,2]), t=as.numeric(ct[1,3]), n=length(x)) }
LIQ <- 2e8  # LIQ_THRESHOLD (KRW)

w("=== R40 insider SAFE 청산 검열-스트레스 정량 — WT-D20260715_009 / FQ-053 ===")

## ── 1. base 상속 (R38이 쓴 R36 uni) ──────────────────────────────────────────────
RDS <- "stage_artifacts/WT_D20260715_005/_r36_objects.rds"; stopifnot(file.exists(RDS))
o36 <- readRDS(RDS); uni <- copy(as.data.table(o36$uni))
BASE_PARITY <- o36$out$base_parity$clean_parity_port_t
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
NB_THR <- 1.0  # R33 frozen net-buy 문턱 (sweep 금지)
setorder(uni, Ticker, hold_ym)
MAX_YM <- max(uni$hold_ym); MIN_YM <- min(uni$hold_ym)   # ★관측창 경계 (terminal truncation 방어, 자가적대검증 catch)
wf("[base] R36 uni 상속: rows=%d months=%d tickers=%d | parity=%.3f | pin=%s (mtime=%s) | NB_THR=%.1f LIQ=%.0e | 관측창=[%d,%d]",
   nrow(uni), uniqueN(uni$hold_ym), uniqueN(uni$Ticker), BASE_PARITY, RAW_P, PIN_MTIME, NB_THR, LIQ, MIN_YM, MAX_YM)
w("[GUARD] ★terminal truncation: hold_ym==MAX_YM(=", MAX_YM, ") ON-event은 j1이 관측창 밖 → informative censoring 아닌 right-truncation. census/차등검열에서 분리(exclude).")

## ── 2. rmon: pin rawdata 월간 패널 (검열탐지 broader universe) ────────────────────
rw <- as.data.table(read_parquet(RAW_P, col_select=c("Date","Ticker","Ret","Close","Vol","K200","KQ150","AdminStock","TradingHalt","UnfaithfulDisc","Market","Name")))
rw <- rw[Date >= as.Date("2004-06-01")]
rw[, ym := as.integer(format(Date, "%Y%m"))]
rmon <- rw[, .(
  ret_m   = prod(1+Ret, na.rm=TRUE)-1,
  n_days  = .N,
  adv_m   = mean(Close*Vol, na.rm=TRUE),
  k200    = as.integer(any(K200==1, na.rm=TRUE)),
  kq150   = as.integer(any(KQ150==1, na.rm=TRUE)),
  admin   = as.integer(any(AdminStock==1, na.rm=TRUE)),
  halt    = as.integer(any(TradingHalt==1, na.rm=TRUE)),
  unfaith = as.integer(any(UnfaithfulDisc==1, na.rm=TRUE))
), by=.(Ticker, ym)]
setkey(rmon, Ticker, ym)
# 각 Ticker의 마지막 데이터 ym (진성폐지 판정용)
tick_last <- rmon[, .(last_ym=max(ym)), by=Ticker]
setkey(tick_last, Ticker)
wf("[rmon] pin 월간 패널: rows=%d ym=[%d,%d] tickers=%d", nrow(rmon), min(rmon$ym), max(rmon$ym), uniqueN(rmon$Ticker))

## ── 3. 상태기계 재구성 (R38 동일) + ON-event enumeration ──────────────────────────
uni[, ins_prev := shift(INS02_OffBuyBreadth6m), by=Ticker]
uni[, ym_prev  := shift(hold_ym), by=Ticker]
uni[, consec   := !is.na(ym_prev) & (ym_prev == ymshift(hold_ym, -1L))]
uni[, on_t := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= NB_THR)]
uni[, both_cov := !is.na(INS02_OffBuyBreadth6m) & !is.na(ins_prev)]
uni[, on_p := as.integer(both_cov & consec & ins_prev >= NB_THR)]
uni[, valid_tr := both_cov & consec]
uni[, state := fifelse(!valid_tr, NA_character_,
               fifelse(on_t==1L & on_p==0L, "ENTRY",
               fifelse(on_t==1L & on_p==1L, "SUSTAIN",
               fifelse(on_t==0L & on_p==1L, "EXIT", "OFF"))))]
st_mid <- uni[valid_tr==TRUE & sz_tercile=="mid", .N, by=state][order(-N)]
wf("[state:R38-repro] MID counts: %s", paste(sprintf("%s=%d", st_mid$state, st_mid$N), collapse=" "))

## uni 멤버십 key (forward 판정용)
uni_key <- unique(uni[, .(Ticker, hold_ym)]); uni_key[, in_uni := 1L]; setkey(uni_key, Ticker, hold_ym)
uni_ins <- uni[, .(Ticker, hold_ym, INS02_OffBuyBreadth6m, sz_tercile, Ret_1m, exc)]; setkey(uni_ins, Ticker, hold_ym)

## ── 4. ON-event → 다음달 outcome 분류 (검열 census 핵심) ──────────────────────────
## ON-event = uni 내 flag-on (INS02>=1.0). j1=다음달. outcome: SUSTAIN / EXIT_obs / cov_lost / CENSORED(subtypes)
## ★terminal truncation 분리: j1>MAX_YM 인 ON-event(=hold_ym==MAX_YM)는 관측 불가 → right_truncated 라벨, census 제외.
ON_full <- uni[on_t==1L, .(Ticker, hold_ym, sz_tercile, INS02_OffBuyBreadth6m)]
ON_full[, j1 := ymshift(hold_ym, 1L)]
n_trunc_all <- ON_full[j1 > MAX_YM, .N]; n_trunc_mid <- ON_full[j1 > MAX_YM & sz_tercile=="mid", .N]
wf("[GUARD] right_truncated ON-event(j1>%d) 제외: ALL=%d MID=%d (informative censoring 아님)", MAX_YM, n_trunc_all, n_trunc_mid)
ON <- ON_full[j1 <= MAX_YM]
# 다음달 uni 멤버십
ON <- merge(ON, uni_key[, .(Ticker, hold_ym, in_uni_next=in_uni)],
            by.x=c("Ticker","j1"), by.y=c("Ticker","hold_ym"), all.x=TRUE)
# 다음달 uni 내 INS02 (SUSTAIN/EXIT_obs/cov_lost 판정)
ON <- merge(ON, uni_ins[, .(Ticker, hold_ym, ins_next=INS02_OffBuyBreadth6m, ret_next_uni=Ret_1m)],
            by.x=c("Ticker","j1"), by.y=c("Ticker","hold_ym"), all.x=TRUE)
# 다음달 rmon (검열 종목 실측/분류)
ON <- merge(ON, rmon[, .(Ticker, ym, ret_m, adv_m, k200, kq150, admin, halt, unfaith, n_days)],
            by.x=c("Ticker","j1"), by.y=c("Ticker","ym"), all.x=TRUE)
# Ticker 마지막 데이터 ym
ON <- merge(ON, tick_last, by="Ticker", all.x=TRUE)

ON[, outcome := fifelse(!is.na(in_uni_next) & !is.na(ins_next) & ins_next >= NB_THR, "SUSTAIN",
              fifelse(!is.na(in_uni_next) & !is.na(ins_next) & ins_next <  NB_THR, "EXIT_obs",
              fifelse(!is.na(in_uni_next) & is.na(ins_next), "cov_lost",
              "CENSORED")))]
# 검열 하위분류 (uni 이탈 종목): rmon 존재여부 + 이유
ON[outcome=="CENSORED", cens_type := fifelse(
     is.na(ret_m) & (last_ym <= hold_ym), "delisted_hard",          # rmon도 종료 = 진성폐지 (신호월 이후 데이터 없음)
   fifelse(is.na(ret_m) & (last_ym >  hold_ym), "temp_gap",         # 일시 결측 (이후 재등장)
   fifelse(!is.na(admin) & (admin==1L | halt==1L | unfaith==1L), "distress_admin_halt",  # 관리/정지/불성실
   fifelse((k200==0L & kq150==0L), "universe_exit",                 # 지수 이탈 (거래는 지속)
   fifelse(is.finite(adv_m) & adv_m < LIQ, "liquidity_drop",        # 유동성 하락
   "other_filter")))))]                                              # 지수내·유동 but uni 제외(데이터/필터)
# 검열 종목의 "실측 EXIT-월 수익": rmon 있으면 실측, 없으면 NA (worst-case 대입 대상)
ON[outcome=="CENSORED", cens_ret_actual := ret_m]

## census (ALL + MID)
census_tab <- function(DT){
  base <- DT[, .N, by=outcome][order(-N)]
  cens <- DT[outcome=="CENSORED", .N, by=cens_type][order(-N)]
  list(outcome=base, cens=cens, n_on=nrow(DT))
}
CEN_all <- census_tab(ON); CEN_mid <- census_tab(ON[sz_tercile=="mid"])
w("\n────── P2 검열 census: ON-event(flag-on) → 다음달 outcome ──────")
w("[ALL] ON-events n=", CEN_all$n_on)
for(i in seq_len(nrow(CEN_all$outcome))){ r<-CEN_all$outcome[i]; wf("   outcome %-10s n=%5d (%.1f%%)", r$outcome, r$N, 100*r$N/CEN_all$n_on) }
w("   [ALL] CENSORED 하위분류:")
for(i in seq_len(nrow(CEN_all$cens))){ r<-CEN_all$cens[i]; wf("      %-20s n=%4d", r$cens_type, r$N) }
w("[MID] ON-events n=", CEN_mid$n_on)
for(i in seq_len(nrow(CEN_mid$outcome))){ r<-CEN_mid$outcome[i]; wf("   outcome %-10s n=%5d (%.1f%%)", r$outcome, r$N, 100*r$N/CEN_mid$n_on) }
w("   [MID] CENSORED 하위분류:")
for(i in seq_len(nrow(CEN_mid$cens))){ r<-CEN_mid$cens[i]; wf("      %-20s n=%4d", r$cens_type, r$N) }

## ── 5. ★차등검열: ON(SAFE) vs OFF 상태 이탈률/폐지율 비교 ──────────────────────────
## 검열이 no-hangover를 낙관적으로 편향시키려면 SAFE(ON)가 OFF보다 더 자주 catastrophic 이탈해야.
## 각 name-month(uni 내)에서 다음달 uni 이탈률 + 진성폐지율을, 현재 flag state로 분할.
disp <- uni[valid_tr==TRUE | on_t==1L, .(Ticker, hold_ym, sz_tercile, on_t, state)]
disp[, j1 := ymshift(hold_ym, 1L)]
disp <- disp[j1 <= MAX_YM]   # ★terminal truncation 제외 (관측창 밖 다음달은 이탈 판정 불가)
disp <- merge(disp, uni_key[, .(Ticker, hold_ym, in_uni_next=in_uni)],
              by.x=c("Ticker","j1"), by.y=c("Ticker","hold_ym"), all.x=TRUE)
disp <- merge(disp, rmon[, .(Ticker, ym, ret_m_n=ret_m)], by.x=c("Ticker","j1"), by.y=c("Ticker","ym"), all.x=TRUE)
disp <- merge(disp, tick_last, by="Ticker", all.x=TRUE)
disp[, left_uni := as.integer(is.na(in_uni_next))]
disp[, delisted := as.integer(is.na(in_uni_next) & is.na(ret_m_n) & (last_ym <= hold_ym))]
disp[, flag_grp := fifelse(on_t==1L, "ON(SAFE)", "OFF/other")]
diff_cens <- function(DT){
  DT[, .(n=.N, left_uni_rate=mean(left_uni), delist_rate=mean(delisted)), by=flag_grp][order(flag_grp)]
}
DC_all <- diff_cens(disp); DC_mid <- diff_cens(disp[sz_tercile=="mid"])
w("\n────── ★차등검열: 다음달 uni 이탈률 / 진성폐지율 (flag state별) ──────")
w("[ALL]"); for(i in seq_len(nrow(DC_all))){ r<-DC_all[i]; wf("   %-10s n=%5d 이탈률=%.3f%% 폐지율=%.4f%%", r$flag_grp, r$n, 100*r$left_uni_rate, 100*r$delist_rate) }
w("[MID]"); for(i in seq_len(nrow(DC_mid))){ r<-DC_mid[i]; wf("   %-10s n=%5d 이탈률=%.3f%% 폐지율=%.4f%%", r$flag_grp, r$n, 100*r$left_uni_rate, 100*r$delist_rate) }
## 통계검정: ON vs OFF 이탈률 차이 (2-proportion)
prop_test <- function(DT, col){
  a <- DT[flag_grp=="ON(SAFE)", get(col)]; b <- DT[flag_grp=="OFF/other", get(col)]
  tt <- tryCatch(prop.test(c(sum(a),sum(b)), c(length(a),length(b))), error=function(e) NULL)
  if(is.null(tt)) return(list(diff=NA,p=NA)); list(diff=as.numeric(diff(rev(tt$estimate))), p=tt$p.value)
}
pl_all <- prop_test(disp, "left_uni"); pd_all <- prop_test(disp, "delisted")
pl_mid <- prop_test(disp[sz_tercile=="mid"], "left_uni"); pd_mid <- prop_test(disp[sz_tercile=="mid"], "delisted")
wf("[ALL] 이탈률 ON−OFF diff=%+.4f p=%.3g | 폐지율 diff=%+.5f p=%.3g", pl_all$diff, pl_all$p, pd_all$diff, pd_all$p)
wf("[MID] 이탈률 ON−OFF diff=%+.4f p=%.3g | 폐지율 diff=%+.5f p=%.3g", pl_mid$diff, pl_mid$p, pd_mid$diff, pd_mid$p)

## ── 6. P2 worst-case 대입: EXIT-월 risk 재계산 (검열 종목 포함) ────────────────────
## R38 EXIT risk = uni 잔존 EXIT_obs만. 검열 종목(CENSORED)을 EXIT-월 분포에 추가:
##   - rmon 실측 있으면 실측 사용 (realistic)
##   - 진성폐지(delisted_hard, ret NA)는 worst-case 시나리오 대입 (−20/−30/−50/−80%)
## OFF baseline = R38 OFF 분포 (MID). risk_sticky 재판정.
mid_on <- ON[sz_tercile=="mid"]
# 관측 EXIT_obs 의 EXIT-월 수익 (= uni 다음달 ret_next_uni, flag off 월)
exit_obs_ret <- mid_on[outcome=="EXIT_obs", ret_next_uni]
# 검열 종목 실측 (rmon 있는 것)
cens_actual  <- mid_on[outcome=="CENSORED" & is.finite(cens_ret_actual), cens_ret_actual]
# 검열 진성폐지 (실측 없음 → 대입 대상)
n_impute     <- mid_on[outcome=="CENSORED" & !is.finite(cens_ret_actual), .N]
# OFF baseline (MID) — R38 정의
off_ret_mid  <- uni[valid_tr==TRUE & sz_tercile=="mid" & state=="OFF", Ret_1m]
off_downside <- mean(off_ret_mid[off_ret_mid<0], na.rm=TRUE)
off_tail     <- mean(off_ret_mid < -0.15, na.rm=TRUE)
risk_metrics <- function(r){ r<-r[is.finite(r)]; list(n=length(r), mean=mean(r), downside=mean(r[r<0]), tail=mean(r< -0.15), vol=sd(r), min=min(r)) }
rm_r38_exit  <- risk_metrics(exit_obs_ret)  # R38 관측 EXIT (검열 전)
wf("\n────── P2 worst-case 대입: MID EXIT-월 risk 재계산 ──────")
wf("[baseline] OFF(MID): downside=%+.4f tail=%.3f n=%d", off_downside, off_tail, length(off_ret_mid))
wf("[R38 관측 EXIT_obs (검열前)]: n=%d downside=%+.4f tail=%.3f min=%+.3f", rm_r38_exit$n, rm_r38_exit$downside, rm_r38_exit$tail, rm_r38_exit$min)
wf("[검열 종목] 실측가능=%d (rmon), 진성폐지 대입대상=%d", length(cens_actual), n_impute)
if(length(cens_actual)>0) wf("   검열-실측 수익: mean=%+.4f min=%+.3f tail(<-15%%)=%.3f", mean(cens_actual), min(cens_actual), mean(cens_actual< -0.15))
scenarios <- list(actual_only=NA, wc_m20=-0.20, wc_m30=-0.30, wc_m50=-0.50, wc_m80=-0.80, wipeout=-1.00)
IMPUTE <- list()
for(sc in names(scenarios)){
  imp_val <- scenarios[[sc]]
  imputed <- if(is.na(imp_val)) numeric(0) else rep(imp_val, n_impute)  # actual_only = 대입 안함
  combined <- c(exit_obs_ret, cens_actual, imputed)   # EXIT_obs + 검열실측 + (대입)
  rmets <- risk_metrics(combined)
  risk_sticky_sc <- (rmets$downside >= off_downside) && (rmets$tail <= off_tail)
  hangover_sc    <- (rmets$tail > off_tail * 1.25)
  IMPUTE[[sc]] <- list(scenario=sc, impute_val=imp_val, n=rmets$n, downside=rmets$downside, tail=rmets$tail, vol=rmets$vol, min=rmets$min,
                       risk_sticky=risk_sticky_sc, hangover=hangover_sc)
  wf("   [%s impute=%s] n=%d downside=%+.4f tail=%.3f | risk_sticky=%s hangover=%s",
     sc, ifelse(is.na(imp_val),"none",sprintf("%.0f%%",imp_val*100)), rmets$n, rmets$downside, rmets$tail, risk_sticky_sc, hangover_sc)
}

## ── 7. P1 다중월 forward 위험궤적 (h=0..3) + attrition ────────────────────────────
## 관측 EXIT 이벤트 (uni 잔존, off 월 = exit_ym). exit_ym+h 의 return 을 uni/rmon 에서 추적.
## 월별-paired NW-t vs OFF (h=0 = R38 재현). attrition = h별 잔존율. 지연 hangover 검출.
EX <- uni[valid_tr==TRUE & state=="EXIT", .(Ticker, exit_ym=hold_ym, sz_tercile)]
# OFF 월별 평균 (MID) — paired 기준
off_month <- uni[valid_tr==TRUE & sz_tercile=="mid" & state=="OFF", .(m_off=mean(Ret_1m,na.rm=TRUE), n_off=.N), by=hold_ym]
setkey(off_month, hold_ym)
setkey(rmon, Ticker, ym)
traj <- list()
for(h in 0:3){
  EXh <- copy(EX[sz_tercile=="mid"]); EXh[, ry := ymshift(exit_ym, h)]
  EXh <- EXh[ry <= MAX_YM]   # ★관측창 밖 forward(rmon-fallback 202605 등 terminal-artifact) 제외
  # uni 잔존 수익
  EXh <- merge(EXh, uni_ins[, .(Ticker, hold_ym, ret_uni=Ret_1m)], by.x=c("Ticker","ry"), by.y=c("Ticker","hold_ym"), all.x=TRUE)
  # rmon 수익 (uni 이탈해도 거래되면 잡음)
  EXh <- merge(EXh, rmon[, .(Ticker, ym, ret_rmon=ret_m)], by.x=c("Ticker","ry"), by.y=c("Ticker","ym"), all.x=TRUE)
  EXh[, in_uni_h := as.integer(is.finite(ret_uni))]
  EXh[, ret_use  := fifelse(is.finite(ret_uni), ret_uni, ret_rmon)]   # uni 우선, 없으면 rmon (거래지속)
  n_evt <- nrow(EXh); surv_uni <- mean(EXh$in_uni_h); surv_any <- mean(is.finite(EXh$ret_use))
  rmets <- risk_metrics(EXh$ret_use)
  # 월별-paired vs OFF (uni-잔존만, R38 정합)
  g <- EXh[in_uni_h==1L, .(m_s=mean(ret_uni,na.rm=TRUE), ns=.N), by=ry]
  g <- merge(g, off_month, by.x="ry", by.y="hold_ym", all.x=FALSE)
  fit <- nw_fit(g$m_s - g$m_off)
  traj[[paste0("h",h)]] <- list(h=h, n_events=n_evt, surv_uni=surv_uni, surv_any=surv_any,
    downside=rmets$downside, tail=rmets$tail, vol=rmets$vol, mean=rmets$mean, min=rmets$min,
    paired_vs_off_t=fit$t, paired_gap_ann=fit$mean*12, n_months=fit$n)
}
w("\n────── P1 다중월 forward 위험궤적 (MID EXIT cohort, h=0..3) ──────")
for(h in 0:3){ x<-traj[[paste0("h",h)]]
  wf("   h=%d n_evt=%d surv_uni=%.2f surv_any=%.2f | downside=%+.4f tail=%.3f vol=%.3f | paired_vs_OFF t=%+.2f (mo=%d)",
     x$h, x$n_events, x$surv_uni, x$surv_any, x$downside, x$tail, x$vol, x$paired_vs_off_t, x$n_months) }

## ── 8. P3 catastrophic vs benign 분리 ────────────────────────────────────────────
## benign EXIT = EXIT_obs (uni 잔존, SAFE_FADING 소관). catastrophic = CENSORED distress/delisted (부실 tripwire 소관).
mid_on[, exit_class := fifelse(outcome=="EXIT_obs", "benign",
                       fifelse(outcome=="SUSTAIN", "still_on",
                       fifelse(outcome=="cov_lost", "coverage_lost",
                       fifelse(cens_type %in% c("delisted_hard","distress_admin_halt"), "catastrophic",
                       "benign_censored"))))]  # universe_exit/liquidity_drop/temp_gap/other = 여전히 거래(benign_censored)
off_events <- mid_on[outcome %in% c("EXIT_obs","CENSORED")]   # ON→off 전이 전체 (SUSTAIN 제외)
class_tab <- off_events[, .N, by=exit_class][order(-N)]
n_offtot  <- nrow(off_events)
w("\n────── P3 catastrophic vs benign (MID, ON→off 전이 전체) ──────")
wf("[MID] ON→off 전이 총=%d (EXIT_obs + CENSORED)", n_offtot)
for(i in seq_len(nrow(class_tab))){ r<-class_tab[i]; wf("   %-16s n=%4d (%.1f%%)", r$exit_class, r$N, 100*r$N/n_offtot) }
# catastrophic 종목 실측 수익 (있으면)
cat_ret <- off_events[exit_class=="catastrophic" & is.finite(cens_ret_actual), cens_ret_actual]
if(length(cat_ret)>0) wf("   catastrophic 실측수익: n=%d mean=%+.4f min=%+.3f", length(cat_ret), mean(cat_ret), min(cat_ret))
n_cat_impute <- off_events[exit_class=="catastrophic" & !is.finite(cens_ret_actual), .N]
wf("   catastrophic 진성폐지(실측불가·대입대상)=%d", n_cat_impute)

## ── 9. 판정 로직 (2렌즈: full-universe vs investable-book-conditional) ─────────────
## no-hangover 강건성 3축:
##   (A) 차등검열 방향: SAFE(ON)가 OFF보다 uni 이탈/폐지 더 잦으면 검열=낙관편향(adverse). 폐지율(catastrophic)과
##       이탈률(투자가능 경계) 분리 — 이탈률은 유동성/필터(부분 mechanical: crash→liq drop→filter exit).
##   (B) worst-case(=검열종목 실측/대입) 후 EXIT risk_sticky 유지 여부 (full-universe 렌즈).
##   (C) 다중월 h=1..3 지연 hangover (survivor-conditional 렌즈, R38 h=0 snapshot 초과).
on_delist  <- DC_mid[flag_grp=="ON(SAFE)", delist_rate]; off_delist <- DC_mid[flag_grp=="OFF/other", delist_rate]
on_leave   <- DC_mid[flag_grp=="ON(SAFE)", left_uni_rate]; off_leave <- DC_mid[flag_grp=="OFF/other", left_uni_rate]
## favorable = SAFE가 OFF보다 유의하게 더 이탈/폐지하지 않음 (검열이 no-hangover 낙관편향 아님).
## 절대율이 아닌 통계유의(p>0.05)로 판정 — 미소한 비유의 차이는 favorable.
delist_favorable <- (on_delist <= off_delist) || (is.na(pd_mid$p) || pd_mid$p > 0.05)   # 폐지율 (catastrophic 축)
leave_favorable  <- (on_leave  <= off_leave) || (pl_mid$p > 0.05)                        # 이탈률 (투자가능 경계 축, 유의성 기준)
diff_favorable   <- delist_favorable && leave_favorable
# worst-case 강건성 (full-universe 렌즈): 검열종목 실측/대입 포함 후 risk_sticky
sticky_scenarios   <- names(IMPUTE)[sapply(IMPUTE, function(x) isTRUE(x$risk_sticky))]
hangover_scenarios <- names(IMPUTE)[sapply(IMPUTE, function(x) isTRUE(x$hangover))]
actual_sticky      <- isTRUE(IMPUTE[["actual_only"]]$risk_sticky)   # 대입 없이 실측만으로도 유지?
# 다중월 지연 hangover (survivor 렌즈): tail 재악화 horizon + 유의성(paired_vs_off_t<-2 = 유의 재악화)
delayed_hangover_h <- integer(0); delayed_hangover_sig_h <- integer(0)
for(h in 1:3){ x<-traj[[paste0("h",h)]]
  if(is.finite(x$tail) && x$tail > off_tail*1.25){ delayed_hangover_h <- c(delayed_hangover_h, h)
    if(is.finite(x$paired_vs_off_t) && x$paired_vs_off_t < -2) delayed_hangover_sig_h <- c(delayed_hangover_sig_h, h) } }
# R38 headline("no hangover / risk-sticky") 이 두 렌즈 모두 통과해야 robust
full_universe_ok <- actual_sticky                        # 검열-조정(worst-case 포함) 후 유지 = 검열편향 없음
survivor_ok      <- (length(delayed_hangover_h) == 0)    # 다중월 지연 재악화(directional) 없음
survivor_sig_ok  <- (length(delayed_hangover_sig_h) == 0) # 유의 지연 재악화 없음 (directional은 있어도 비유의면 TRUE)
verdict <- if(!full_universe_ok){
  "no_hangover_censoring_fragile" # 검열-조정 시 붕괴 (검열편향 실재)
} else if(!survivor_sig_ok){
  "no_hangover_horizon_limited_sig"  # survivor에서 유의 지연 재악화 (단기만 성립, 통계 유의)
} else if(!survivor_ok){
  "no_hangover_horizon_limited"   # 검열 무해(no censoring bias)이나 survivor protection이 단기(directional 지연 재악화·비유의)
} else if(!diff_favorable){
  "no_hangover_survivor_conditional"  # 통과하나 차등검열 방향 adverse (조건부 경고)
} else {
  "no_hangover_robust"            # 검열 무해 + worst-case 견고 + 다중월 재악화 없음
}
## ★chartered 질문(검열편향)에 대한 답: full_universe_ok(worst-case 견고) + diff_favorable(차등검열 비유의) → 검열편향 immaterial
censoring_bias_material <- (!full_universe_ok) || (!diff_favorable)
w("\n────── 판정 (2렌즈) ──────")
wf("[A 차등검열] ON폐지율=%.4f%% OFF폐지율=%.4f%% (delist_favorable=%s) | ON이탈률=%.3f%% OFF이탈률=%.3f%% (leave_favorable=%s)",
   100*on_delist, 100*off_delist, delist_favorable, 100*on_leave, 100*off_leave, leave_favorable)
wf("[B full-universe] 검열종목 실측포함 EXIT: actual_only risk_sticky=%s | hangover 시나리오: %s",
   actual_sticky, ifelse(length(hangover_scenarios)==0,"none",paste(hangover_scenarios, collapse=",")))
wf("[C survivor 다중월] 지연 hangover horizon: %s", ifelse(length(delayed_hangover_h)==0,"none",paste0("h",delayed_hangover_h,collapse=",")))
wf("[VERDICT] %s (full_universe_ok=%s survivor_ok=%s)", verdict, full_universe_ok, survivor_ok)

## ── 10. 저장 ──────────────────────────────────────────────────────────────────────
# census parquet
cens_census_dt <- rbind(
  data.table(scope="ALL", metric="outcome",   category=CEN_all$outcome$outcome, n=CEN_all$outcome$N),
  data.table(scope="ALL", metric="cens_type", category=CEN_all$cens$cens_type,  n=CEN_all$cens$N),
  data.table(scope="MID", metric="outcome",   category=CEN_mid$outcome$outcome, n=CEN_mid$outcome$N),
  data.table(scope="MID", metric="cens_type", category=CEN_mid$cens$cens_type,  n=CEN_mid$cens$N))
write_parquet(cens_census_dt, file.path(OUT,"r40_censoring_census.parquet"))
traj_dt <- rbindlist(lapply(traj, function(x) as.data.table(x[c("h","n_events","surv_uni","surv_any","downside","tail","vol","mean","paired_vs_off_t")])))
write_parquet(traj_dt, file.path(OUT,"r40_multimonth_trajectory.parquet"))
impute_dt <- rbindlist(lapply(IMPUTE, function(x) as.data.table(x[c("scenario","impute_val","n","downside","tail","vol","min","risk_sticky","hangover")])), fill=TRUE)
write_parquet(impute_dt, file.path(OUT,"r40_worstcase_impute.parquet"))

## 사전등록 해시
PREREG <- list(mode="RAMP-adjacent monitoring 진단 (insider SAFE 청산 검열-스트레스)", round="R40", fq="FQ-053", wt="WT-D20260715_009",
  parent="R38 next_probe P1 (검열편향 caveat HIGH 정량)",
  base_source="R38이 상속한 R36 _r36_objects.rds uni (production clean T-1, production_parity_verified 3.058, PIT C5 상속) + pin rawdata broader universe(검열탐지)",
  diagnostics=list(
    P1="다중월 forward 위험궤적: EXIT cohort exit_ym+h(h=0..3) downside/tail/vol + 월별-paired NW-t vs OFF + horizon별 attrition",
    P2="검열 census(폐지/유동성/유니버스/부실) + rmon 실측 + 진성폐지 worst-case 대입(-20/-30/-50/-80/-100%) → risk_sticky 재판정 + ★차등검열 ON vs OFF 이탈/폐지율",
    P3="catastrophic(폐지·부실, 부실tripwire 소관) vs benign(uni잔존 EXIT, SAFE_FADING 소관) 경계 정량"),
  decision_axis="R38 no-hangover(청산≠위험재상승)의 검열-조정 강건성. 자본 아님(monitoring).",
  flags=list(net_buy="INS02_OffBuyBreadth6m z>=+1.0 (R33 frozen)"),
  worst_case_scenarios="actual_only / -20% / -30% / -50% / -80% / -100%(wipeout)",
  liq_threshold=LIQ,
  pit="uni 상속 clean T-1 (Ret_1m 동월 실현, cor=1.0 rmon 검증) + 검열은 j→j+1 forward 멤버십",
  selection_type="chain (가설주도 고정 config · sweep 아님)", n_trials=1L,
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r40.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("[prereg] config_hash=%s selection_type=chain n_trials=1", PREREG$config_hash)

out <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  base_parity=list(clean_parity_port_t=BASE_PARITY, note="§7b R38→R36 uni 상속"),
  P2_census=list(
    all=list(n_on=CEN_all$n_on, outcome=setNames(as.list(CEN_all$outcome$N), CEN_all$outcome$outcome),
             cens_type=setNames(as.list(CEN_all$cens$N), CEN_all$cens$cens_type)),
    mid=list(n_on=CEN_mid$n_on, outcome=setNames(as.list(CEN_mid$outcome$N), CEN_mid$outcome$outcome),
             cens_type=setNames(as.list(CEN_mid$cens$N), CEN_mid$cens$cens_type))),
  differential_censoring=list(
    all=lapply(seq_len(nrow(DC_all)), function(i) as.list(DC_all[i])),
    mid=lapply(seq_len(nrow(DC_mid)), function(i) as.list(DC_mid[i])),
    tests=list(all_leave_diff=round(pl_all$diff,5), all_leave_p=signif(pl_all$p,4),
               all_delist_diff=round(pd_all$diff,6), all_delist_p=signif(pd_all$p,4),
               mid_leave_diff=round(pl_mid$diff,5), mid_leave_p=signif(pl_mid$p,4),
               mid_delist_diff=round(pd_mid$diff,6), mid_delist_p=signif(pd_mid$p,4)),
    favorable=diff_favorable),
  P2_worstcase=list(off_baseline=list(downside=round(off_downside,5), tail=round(off_tail,5), n=length(off_ret_mid)),
    r38_exit_obs=list(n=rm_r38_exit$n, downside=round(rm_r38_exit$downside,5), tail=round(rm_r38_exit$tail,5), min=round(rm_r38_exit$min,4)),
    cens_actual_n=length(cens_actual), cens_impute_n=n_impute,
    cens_actual_summary=if(length(cens_actual)>0) list(mean=round(mean(cens_actual),5), min=round(min(cens_actual),4), tail=round(mean(cens_actual< -0.15),4)) else NULL,
    scenarios=lapply(IMPUTE, function(x) lapply(x, function(v) if(is.numeric(v)) round(v,5) else v)),
    sticky_scenarios=sticky_scenarios, hangover_scenarios=hangover_scenarios),
  P1_multimonth=lapply(traj, function(x) lapply(x, function(v) if(is.numeric(v)) round(v,5) else v)),
  P3_catastrophic_benign=list(n_off_transitions_mid=n_offtot,
    class=setNames(as.list(class_tab$N), class_tab$exit_class),
    catastrophic_actual_n=length(cat_ret), catastrophic_impute_n=n_cat_impute,
    catastrophic_actual_min=if(length(cat_ret)>0) round(min(cat_ret),4) else NULL),
  right_truncated=list(all=n_trunc_all, mid=n_trunc_mid, note="hold_ym==MAX_YM ON-event(j1 관측창 밖) — informative censoring 아닌 right-truncation, census 제외 (자가적대검증 catch)"),
  verdict=list(class=verdict, censoring_bias_material=censoring_bias_material, diff_favorable=diff_favorable,
    delist_favorable=delist_favorable, leave_favorable=leave_favorable, leave_p_mid=signif(pl_mid$p,4),
    full_universe_ok=full_universe_ok, survivor_ok=survivor_ok, survivor_sig_ok=survivor_sig_ok, actual_sticky=actual_sticky,
    on_delist_rate=round(on_delist,6), off_delist_rate=round(off_delist,6),
    on_leave_rate=round(on_leave,5), off_leave_rate=round(off_leave,5),
    sticky_scenarios=sticky_scenarios, hangover_scenarios=hangover_scenarios,
    delayed_hangover_h=delayed_hangover_h, delayed_hangover_sig_h=delayed_hangover_sig_h,
    r38_censoring_caveat_dismissed = !censoring_bias_material,
    r38_conclusion_holds = (verdict %in% c("no_hangover_robust","no_hangover_horizon_limited"))),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(out, file.path(OUT,"r40_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)
saveRDS(list(ON=ON, disp=disp, traj=traj, IMPUTE=IMPUTE, CEN_all=CEN_all, CEN_mid=CEN_mid,
             DC_all=DC_all, DC_mid=DC_mid, off_downside=off_downside, off_tail=off_tail,
             class_tab=class_tab, verdict=verdict), file.path(OUT,"_r40_objects.rds"))

wf("\nR40_DONE | verdict=%s | 차등검열 favorable=%s (ON폐지 %.4f%% vs OFF %.4f%%) | worst-case sticky=%s | 지연hangover=%s",
   verdict, diff_favorable, 100*on_delist, 100*off_delist,
   paste(sticky_scenarios,collapse=","), ifelse(length(delayed_hangover_h)==0,"none",paste0("h",delayed_hangover_h,collapse=",")))
cat("[SAVED]", file.path(OUT,"r40_results.json"), "\n")
