## run_r38_insider_exit_timing.R — WT-D20260715_007 / FQ-052 / R38
## insider SAFE 청산-타이밍 대칭검정 — 진입(flag on)은 확립됐으나 청산(flag off)이 대칭적으로
##   정보성을 갖는가. monitoring tripwire 청산규칙 필요성 판정. 자본 아님(monitoring 진단).
##
## 사전등록 진단 3 (판별 목적 · monitoring 소비면):
##   P1 청산 타이밍 대칭: INS02 net-buy flag의 상태기계(ENTRY/SUSTAIN/EXIT/OFF, 연속월+insider-covered
##       내 z 임계 교차)로 각 상태의 forward SAFE(Ret_1m·excess·downside·tail). 대칭 = ON-경계(진입)
##       lift 와 OFF-경계(청산) 위험재상승의 거울상. EXIT≈OFF(t≈0) → SAFE는 신호 지속기간 국한(청산규칙 필요).
##       EXIT<OFF → 청산 자체가 능동 경보(hangover). EXIT>OFF → SAFE 점착(청산규칙 지연 허용).
##   P2 hold-duration 효과: ON-run 연속월수(dur=1 진입 / 2-3 / 4+)별 forward SAFE 감쇠 — 신호 신선도.
##   P3 monitoring 운영 함의: tripwire 청산규칙(flag off 시 SAFE 라벨 해제) 필요성 판정.
##
## §7b: base = R36 _r36_objects.rds uni (production clean T-1 파생, production_parity_verified 3.058,
##   PIT C5 검증 상속). 저장 268m same-month vintage 미사용. DART API X.
## PIT (C5): uni 상속 — clean T-1 홀딩월 + insider signal(월말 m)→홀딩월(m+1) flag, 홀딩월 시작 전.
##   상태기계는 연속 hold_ym(m-1→m) + 양월 insider-covered 요구 → coverage-gap 아닌 z-level 교차만.
##   lag1 스트레스로 동월누출 배제.
## 규율: 단일스레드 · arrow io(2). book_state/05_Production/outputs/ramp 무변경(stage_artifacts만).
##   canonical 진단 · cov/weights 미산출(역할경계) · 자본 주장 금지(monitoring).
suppressPackageStartupMessages({library(data.table); library(arrow); library(sandwich); library(lmtest); library(digest); library(jsonlite)})
setDTthreads(1); try(arrow::set_cpu_count(1),silent=TRUE); try(arrow::set_io_thread_count(2L),silent=TRUE)
QM <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"; setwd(QM)
set.seed(20260715L)

OUT <- "stage_artifacts/WT_D20260715_007"; dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
logf <- file.path(OUT, "_r38_run_log.txt"); if(file.exists(logf)) try(file.remove(logf), silent=TRUE)
w  <- function(...){ try({ .lc<-file(logf,"a",encoding="UTF-8"); writeLines(paste0(...), .lc); close(.lc)}, silent=TRUE); cat(paste0(...),"\n") }
wf <- function(...) w(sprintf(...))
ymshift <- function(ymv,k){y<-ymv%/%100L;m<-ymv%%100L;t<-(y*12L+(m-1L))+k;(t%/%12L)*100L+(t%%12L)+1L}
## NW lag-3 mean/se/t on a monthly series
nw_fit <- function(x){ x<-x[is.finite(x)]; if(length(x)<12) return(list(mean=NA,se=NA,t=NA,n=length(x)))
  m<-lm(x~1); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(mean=as.numeric(ct[1,1]), se=as.numeric(ct[1,2]), t=as.numeric(ct[1,3]), n=length(x)) }
nwt <- function(x) nw_fit(x)$t
mdd <- function(r){ r<-r[is.finite(r)]; if(length(r)<3) return(NA_real_); nav<-cumprod(1+r); min(nav/cummax(nav)-1) }

w("=== R38 insider SAFE 청산-타이밍 대칭검정 — WT-D20260715_007 / FQ-052 ===")

## ── 1. R36 uni 상속 (PIT 검증 완료 base) ────────────────────────────────────────
RDS <- "stage_artifacts/WT_D20260715_005/_r36_objects.rds"; stopifnot(file.exists(RDS))
o36 <- readRDS(RDS); uni <- copy(as.data.table(o36$uni))
RAW_P <- ".cache/pin/rawdata_r9_pin_20260715.parquet"; if(!file.exists(RAW_P)) RAW_P <- ".cache/rawdata.parquet"
PIN_MTIME <- as.character(file.info(RAW_P)$mtime)
BASE_PARITY <- o36$out$base_parity$clean_parity_port_t
NB_THR <- 1.0   # R33 사전고정 net-buy 문턱 (sweep 금지)
wf("[base] R36 uni 상속: rows=%d months=%d | parity_PORT_t=%.3f | pin=%s (mtime=%s) | NB_THR=%.1f(frozen)",
   nrow(uni), uniqueN(uni$hold_ym), BASE_PARITY, RAW_P, PIN_MTIME, NB_THR)

## ── 2. 상태기계: ENTRY/SUSTAIN/EXIT/OFF (연속월 + 양월 insider-covered, z-level 교차) ──
setorder(uni, Ticker, hold_ym)
uni[, ins_prev := shift(INS02_OffBuyBreadth6m), by=Ticker]
uni[, ym_prev  := shift(hold_ym), by=Ticker]
uni[, consec   := !is.na(ym_prev) & (ym_prev == ymshift(hold_ym, -1L))]
uni[, gap      := is.na(ym_prev) | (ym_prev != ymshift(hold_ym, -1L))]
uni[, on_t := as.integer(!is.na(INS02_OffBuyBreadth6m) & INS02_OffBuyBreadth6m >= NB_THR)]
## z-transition 정의는 양월 insider-covered + 연속월에서만 (coverage 등장/소멸 아닌 신호강도 교차)
uni[, both_cov := !is.na(INS02_OffBuyBreadth6m) & !is.na(ins_prev)]
uni[, on_p := as.integer(both_cov & consec & ins_prev >= NB_THR)]
uni[, valid_tr := both_cov & consec]     # 상태 판정 유효 (전이 정의 가능)
uni[, state := fifelse(!valid_tr, NA_character_,
               fifelse(on_t==1L & on_p==0L, "ENTRY",
               fifelse(on_t==1L & on_p==1L, "SUSTAIN",
               fifelse(on_t==0L & on_p==1L, "EXIT", "OFF"))))]

## ── 2b. hold-duration: ON-run 연속월수 (신호 신선도) ─────────────────────────────
## 블록 = on 상태 변화 또는 gap 에서 새 블록. dur = 블록 내 위치.
uni[, on_run := as.integer(on_t==1L)]
uni[, newblk := (on_run != shift(on_run, fill=-9L)) | gap, by=Ticker]
uni[, blk := cumsum(newblk), by=Ticker]
uni[, dur := seq_len(.N), by=.(Ticker, blk)]      # ON-run 이면 연속 ON 개월수
uni[on_t==0L, dur := NA_integer_]                  # OFF/EXIT 는 dur 무의미
## EXIT 직전 run 길이 (얼마나 오래 켜져있다 꺼졌나) — 점착 진단용
uni[, prev_run_len := shift(dur), by=Ticker]        # EXIT 행에서 = 직전 ON-run 길이

wf("[state] 유효 전이 행=%d (both_cov & consecutive) / 전체 uni=%d", uni[valid_tr==TRUE,.N], nrow(uni))
st_cnt <- uni[valid_tr==TRUE, .N, by=state][order(-N)]
wf("[state] counts: %s", paste(sprintf("%s=%d", st_cnt$state, st_cnt$N), collapse=" "))
st_mid <- uni[valid_tr==TRUE & sz_tercile=="mid", .N, by=state][order(-N)]
wf("[state] mid-tercile counts: %s", paste(sprintf("%s=%d", st_mid$state, st_mid$N), collapse=" "))

## ── 3. 상태별 forward SAFE 요약 (raw + excess + downside + tail + vol) ────────────
state_summary <- function(DT){
  DT[!is.na(state), .(
    n_obs      = .N,
    mean_fwd   = mean(Ret_1m, na.rm=TRUE),
    mean_exc   = mean(exc,    na.rm=TRUE),
    downside   = mean(Ret_1m[Ret_1m<0], na.rm=TRUE),
    tail_hit   = mean(Ret_1m < -0.15, na.rm=TRUE),
    vol        = sd(Ret_1m, na.rm=TRUE),
    win_rate   = mean(Ret_1m > 0, na.rm=TRUE)
  ), by=state][order(match(state, c("OFF","ENTRY","SUSTAIN","EXIT")))]
}
SS_all <- state_summary(uni)
SS_mid <- state_summary(uni[sz_tercile=="mid"])
w("\n[summary:ALL] state별 forward SAFE:")
for(i in seq_len(nrow(SS_all))){ r<-SS_all[i]
  wf("   %-8s n=%5d fwd=%+.4f exc=%+.4f downside=%+.4f tail(<-15%%)=%.3f vol=%.4f win=%.3f",
     r$state, r$n_obs, r$mean_fwd, r$mean_exc, r$downside, r$tail_hit, r$vol, r$win_rate) }
w("[summary:MID] mid-tercile (SAFE 신호 서식지):")
for(i in seq_len(nrow(SS_mid))){ r<-SS_mid[i]
  wf("   %-8s n=%5d fwd=%+.4f exc=%+.4f downside=%+.4f tail=%.3f vol=%.4f", r$state, r$n_obs, r$mean_fwd, r$mean_exc, r$downside, r$tail_hit, r$vol) }

## ── 4. P1 대칭 검정: 월별-paired NW-t (state vs OFF, dual-basis) ─────────────────
## 각 월에서 (state 평균 − OFF 평균) 월별 시계열 → NW lag-3 t. ON-경계(ENTRY) vs OFF-경계(EXIT) 대조.
paired_vs_off <- function(DT, target_state, basis="Ret_1m"){
  d <- DT[state %in% c(target_state,"OFF")]
  g <- d[, .(m_s = mean(get(basis)[state==target_state], na.rm=TRUE),
             m_o = mean(get(basis)[state=="OFF"], na.rm=TRUE),
             ns = sum(state==target_state), no = sum(state=="OFF")), by=hold_ym][ns>0 & no>0]
  fit <- nw_fit(g$m_s - g$m_o)
  list(state=target_state, basis=basis, gap_ann=fit$mean*12, gap_t=fit$t, se=fit$se, n_months=fit$n,
       avg_state_mo=mean(g$ns), gap_series=(g$m_s-g$m_o), months=g$hold_ym)
}
## paired (state vs SUSTAIN) — 실제 전이 델타 (ON 유지 대비 진입/청산)
paired_vs_ref <- function(DT, target_state, ref_state, basis="Ret_1m"){
  d <- DT[state %in% c(target_state, ref_state)]
  g <- d[, .(m_s = mean(get(basis)[state==target_state], na.rm=TRUE),
             m_r = mean(get(basis)[state==ref_state], na.rm=TRUE),
             ns = sum(state==target_state), nr = sum(state==ref_state)), by=hold_ym][ns>0 & nr>0]
  fit <- nw_fit(g$m_s - g$m_r)
  list(target=target_state, ref=ref_state, basis=basis, gap_ann=fit$mean*12, gap_t=fit$t, n_months=fit$n)
}
run_p1 <- function(DT, lab){
  res <- list(label=lab)
  for(st in c("ENTRY","SUSTAIN","EXIT")){
    for(bs in c("Ret_1m","exc")){
      key <- paste0(st,"_vs_OFF_",bs)
      res[[key]] <- paired_vs_off(DT, st, bs)
    }
  }
  ## 청산 전이 델타: EXIT vs SUSTAIN (신호 켜진 상태 대비 꺼진 첫달)
  res$EXIT_vs_SUSTAIN_ret <- paired_vs_ref(DT, "EXIT","SUSTAIN","Ret_1m")
  res$EXIT_vs_SUSTAIN_exc <- paired_vs_ref(DT, "EXIT","SUSTAIN","exc")
  ## 진입 전이 델타: ENTRY vs OFF 는 위 있음. 대칭 요약.
  res
}
P1_all <- run_p1(uni, "ALL insider-covered")
P1_mid <- run_p1(uni[sz_tercile=="mid"], "MID tercile")

pr <- function(x) sprintf("gap_ann=%+.4f t=%+.2f (mo=%d)", x$gap_ann, x$gap_t, x$n_months)
w("\n────── P1 대칭 검정 (월별-paired NW-t, state vs OFF) ──────")
for(lab in c("ALL","MID")){ P<-if(lab=="ALL") P1_all else P1_mid
  w(sprintf("[%s]", P$label))
  wf("   ENTRY   vs OFF: raw %s | exc %s", pr(P$ENTRY_vs_OFF_Ret_1m), pr(P$ENTRY_vs_OFF_exc))
  wf("   SUSTAIN vs OFF: raw %s | exc %s", pr(P$SUSTAIN_vs_OFF_Ret_1m), pr(P$SUSTAIN_vs_OFF_exc))
  wf("   EXIT    vs OFF: raw %s | exc %s", pr(P$EXIT_vs_OFF_Ret_1m), pr(P$EXIT_vs_OFF_exc))
  wf("   EXIT vs SUSTAIN(전이델타): raw %s | exc %s", pr(P$EXIT_vs_SUSTAIN_ret), pr(P$EXIT_vs_SUSTAIN_exc))
}

## ── 5. P2 hold-duration 효과 (신선도) ────────────────────────────────────────────
## ON 상태(ENTRY+SUSTAIN)를 dur 버킷으로: dur=1(진입) / 2-3 / 4+. forward SAFE vs OFF (월별-paired NW-t).
uni[, dur_bkt := fifelse(is.na(dur) | on_t==0L, NA_character_,
                 fifelse(dur==1L,"d1", fifelse(dur<=3L,"d2_3","d4plus")))]
dur_summary <- function(DT){
  DT[!is.na(dur_bkt), .(n=.N, mean_fwd=mean(Ret_1m,na.rm=TRUE), mean_exc=mean(exc,na.rm=TRUE),
     downside=mean(Ret_1m[Ret_1m<0],na.rm=TRUE), tail=mean(Ret_1m< -0.15,na.rm=TRUE)),
     by=dur_bkt][order(match(dur_bkt,c("d1","d2_3","d4plus")))]
}
dur_vs_off <- function(DT, bkt, basis="Ret_1m"){
  d <- DT[dur_bkt==bkt | state=="OFF"]
  g <- d[, .(m_s=mean(get(basis)[dur_bkt==bkt & !is.na(dur_bkt)],na.rm=TRUE),
             m_o=mean(get(basis)[state=="OFF"],na.rm=TRUE),
             ns=sum(dur_bkt==bkt & !is.na(dur_bkt)), no=sum(state=="OFF")), by=hold_ym][ns>0 & no>0]
  fit <- nw_fit(g$m_s - g$m_o)
  list(bkt=bkt, basis=basis, gap_ann=fit$mean*12, gap_t=fit$t, n_months=fit$n, avg_mo=mean(g$ns))
}
DS_all <- dur_summary(uni); DS_mid <- dur_summary(uni[sz_tercile=="mid"])
P2_all <- lapply(c("d1","d2_3","d4plus"), function(b) dur_vs_off(uni, b, "Ret_1m"))
P2_mid <- lapply(c("d1","d2_3","d4plus"), function(b) dur_vs_off(uni[sz_tercile=="mid"], b, "Ret_1m"))
names(P2_all) <- names(P2_mid) <- c("d1","d2_3","d4plus")
w("\n────── P2 hold-duration 효과 (신호 신선도) ──────")
w("[ALL] dur별 forward SAFE 요약:")
for(i in seq_len(nrow(DS_all))){ r<-DS_all[i]; wf("   %-7s n=%5d fwd=%+.4f exc=%+.4f downside=%+.4f tail=%.3f", r$dur_bkt, r$n, r$mean_fwd, r$mean_exc, r$downside, r$tail) }
for(b in c("d1","d2_3","d4plus")){ x<-P2_all[[b]]; wf("   [ALL] %-7s vs OFF: gap_ann=%+.4f t=%+.2f (mo=%d)", b, x$gap_ann, x$gap_t, x$n_months) }
w("[MID] dur별:")
for(i in seq_len(nrow(DS_mid))){ r<-DS_mid[i]; wf("   %-7s n=%5d fwd=%+.4f exc=%+.4f downside=%+.4f", r$dur_bkt, r$n, r$mean_fwd, r$mean_exc, r$downside) }
for(b in c("d1","d2_3","d4plus")){ x<-P2_mid[[b]]; wf("   [MID] %-7s vs OFF: gap_ann=%+.4f t=%+.2f (mo=%d)", b, x$gap_ann, x$gap_t, x$n_months) }
## 신선도 추세: dur 을 연속변수로 forward Ret_1m 회귀 (ON 상태 내, 월내 demean 후)
onset <- uni[on_t==1L & !is.na(dur) & !is.na(Ret_1m)]
onset[, ret_dm := Ret_1m - mean(Ret_1m, na.rm=TRUE), by=hold_ym]   # 월내 demean (시장/월효과 제거)
dur_slope <- tryCatch({ m<-lm(ret_dm ~ dur, data=onset); ct<-coeftest(m, vcov=sandwich::NeweyWest(m,lag=3,prewhite=FALSE))
  list(slope=as.numeric(ct[2,1]), t=as.numeric(ct[2,3]), n=nrow(onset)) }, error=function(e) list(slope=NA,t=NA,n=nrow(onset)))
wf("[freshness] ON내 dur→forward Ret(월내demean) 기울기=%+.5f/mo NW-t=%+.2f (n=%d) — 음수유의=신선할수록 안전(감쇠)",
   dur_slope$slope, dur_slope$t, dur_slope$n)

## ── 6. lag-1 스트레스 (동월누출 배제, C5) ────────────────────────────────────────
## state 를 홀딩월 +1 로 밀어(신호가 2개월 전) — 대칭 구조가 붕괴하면 동월누출 의심.
uL <- copy(uni[valid_tr==TRUE, .(hold_ym=ymshift(hold_ym,1L), Ticker, state_lag=state)])
uJ <- merge(uni[, .(hold_ym, Ticker, Ret_1m, exc, sz_tercile)], uL, by=c("hold_ym","Ticker"), all.x=FALSE)
uJ[, state := state_lag]
L_entry <- paired_vs_off(uJ, "ENTRY","Ret_1m"); L_exit <- paired_vs_off(uJ, "EXIT","Ret_1m")
L_sust  <- paired_vs_off(uJ, "SUSTAIN","Ret_1m")
wf("\n[lag1-stress] ENTRY vs OFF gap_t=%+.2f | SUSTAIN vs OFF gap_t=%+.2f | EXIT vs OFF gap_t=%+.2f (붕괴시 동월누출)",
   L_entry$gap_t, L_sust$gap_t, L_exit$gap_t)

## ── 7. 북 held 슬리브 confirmatory (monitoring 대상 = 보유 종목) ─────────────────
o34 <- readRDS("stage_artifacts/WT_D20260715_003/_r34_objects.rds"); HELD <- as.data.table(o34$HELD)
held_key <- unique(HELD[, .(hold_ym, Ticker, held=1L)])
uH <- merge(uni[valid_tr==TRUE, .(hold_ym, Ticker, state, Ret_1m, exc, sz_tercile, dur_bkt, on_t)], held_key,
            by=c("hold_ym","Ticker"), all.x=FALSE)   # 보유 ∩ insider-covered 전이유효
uH_held <- uH[held==1L]
wf("[held-confirm] 보유∩insider-covered∩전이유효 = %d name-months", nrow(uH_held))
H_entry <- paired_vs_off(uH_held, "ENTRY","Ret_1m"); H_exit <- paired_vs_off(uH_held, "EXIT","Ret_1m")
H_sust  <- paired_vs_off(uH_held, "SUSTAIN","Ret_1m")
SS_held <- state_summary(uH_held)
w("[held-confirm] state별 (보유 슬리브):")
for(i in seq_len(nrow(SS_held))){ r<-SS_held[i]; wf("   %-8s n=%4d fwd=%+.4f exc=%+.4f downside=%+.4f tail=%.3f", r$state, r$n_obs, r$mean_fwd, r$mean_exc, r$downside, r$tail_hit) }
wf("[held-confirm] ENTRY vs OFF t=%+.2f | SUSTAIN vs OFF t=%+.2f | EXIT vs OFF t=%+.2f",
   H_entry$gap_t, H_sust$gap_t, H_exit$gap_t)

## ── 8. 판정 로직 (대칭성 분류 — 수익축/위험축 분리) ──────────────────────────────
## 대표 = MID (SAFE 서식지). ON lift (SUSTAIN vs OFF) 양수 유의 전제.
## 수익축: EXIT vs OFF (return premium 재상승/복귀) · EXIT vs SUSTAIN (전이델타).
## 위험축: EXIT downside/tail 이 OFF 대비 여전히 나은가 (protection 점착) vs 재악화(hangover).
e_t  <- P1_mid$ENTRY_vs_OFF_Ret_1m$gap_t
s_t  <- P1_mid$SUSTAIN_vs_OFF_Ret_1m$gap_t
x_t  <- P1_mid$EXIT_vs_OFF_Ret_1m$gap_t      # 청산 vs OFF 수익축 (핵심)
xs_t <- P1_mid$EXIT_vs_SUSTAIN_ret$gap_t     # 청산 전이 델타 (SUSTAIN 대비 EXIT)
on_lift_present <- (is.finite(s_t) && s_t > 2.0)  # SUSTAIN 유의 lift = SAFE 신호 실재 전제
## 위험축 점착: MID EXIT downside/tail 이 OFF 보다 개선(더 안전)인가
mid_off  <- SS_mid[state=="OFF"];  mid_exit <- SS_mid[state=="EXIT"]
risk_sticky <- (mid_exit$downside >= mid_off$downside) && (mid_exit$tail_hit <= mid_off$tail_hit)   # downside 덜 나쁨 + tail 덜 잦음
risk_hangover <- (mid_exit$tail_hit > mid_off$tail_hit * 1.25)   # tail 25%+ 재악화 = 능동경보
## 수익축 복귀: EXIT 수익 premium 이 OFF 로 복귀(유의하지 않음) 여부
return_reverts <- is.finite(x_t) && x_t < 2.0     # EXIT vs OFF 수익 t 무유의 = premium 소멸/복귀
verdict_symmetry <- if(!on_lift_present){
  "on_lift_weak"                          # SAFE 신호 자체 약함 (대칭 논의 무의미)
} else if(risk_hangover){
  "asymmetric_hangover"                   # 청산 후 tail 재악화 (능동 경보 — 청산규칙 강함)
} else if(risk_sticky && return_reverts){
  "asymmetric_benign_risk_sticky"         # 수익 premium 은 복귀하나 위험 protection 점착 (청산=위험 아님·소프트 해제)
} else if(risk_sticky && !return_reverts){
  "sticky_safe_full"                      # 수익+위험 둘다 청산 후 점착 (청산규칙 지연 허용)
} else if(!risk_sticky && return_reverts){
  "symmetric_reversion"                   # 수익·위험 모두 OFF 복귀 (SAFE=신호지속기간 국한·청산규칙 필요)
} else { "mixed" }
## 청산규칙 필요성: hangover / 완전대칭복귀 → 필요. benign risk-sticky → 불요(소프트 해제로 충분).
exit_rule_needed <- verdict_symmetry %in% c("symmetric_reversion","asymmetric_hangover")
exit_rule_recommendation <- switch(verdict_symmetry,
  asymmetric_hangover = "HARD: flag-off 을 능동 CONCERN 경보로 (tail 재악화)",
  symmetric_reversion = "SOFT-CLEAR: flag-off 시 SAFE 라벨 즉시 해제 (premium·protection 모두 소멸)",
  asymmetric_benign_risk_sticky = "SOFT-LAG: flag-off 은 위험 아님 — SAFE 라벨 즉시해제 불요(위험 protection 점착), 수익 premium 만 소멸 → 라벨 강도 하향(SAFE→SAFE_FADING) 권고",
  sticky_safe_full = "LAG-OK: 청산 후에도 SAFE 유효 — 라벨 지연 해제 허용",
  on_lift_weak = "N/A: SAFE 신호 미약",
  "REVIEW")
w("\n────── 판정 로직 (수익축/위험축 분리) ──────")
wf("[verdict] on_lift(MID SUSTAIN t=%+.2f, present=%s)", s_t, on_lift_present)
wf("[verdict] 수익축: EXIT vs OFF t=%+.2f (return_reverts=%s) | EXIT vs SUSTAIN t=%+.2f", x_t, return_reverts, xs_t)
wf("[verdict] 위험축: EXIT downside=%+.4f (OFF %+.4f) tail=%.3f (OFF %.3f) → risk_sticky=%s hangover=%s",
   mid_exit$downside, mid_off$downside, mid_exit$tail_hit, mid_off$tail_hit, risk_sticky, risk_hangover)
wf("[verdict] symmetry=%s → 청산규칙 필요=%s | 권고: %s", verdict_symmetry, exit_rule_needed, exit_rule_recommendation)

## ── 9. 차트용 series 저장 ────────────────────────────────────────────────────────
## (A) 진입 vs 청산 forward 위험 막대 (MID, raw+exc+downside+tail)
chart_states <- SS_mid[, .(state, mean_fwd, mean_exc, downside, tail_hit, n_obs)]
write_parquet(chart_states, file.path(OUT,"r38_state_summary_mid.parquet"))
## (B) hold-duration 감쇠 (MID)
chart_dur <- DS_mid[, .(dur_bkt, mean_fwd, mean_exc, downside, n)]
write_parquet(chart_dur, file.path(OUT,"r38_duration_mid.parquet"))
saveRDS(list(uni_state=uni[valid_tr==TRUE, .(hold_ym,Ticker,state,dur,dur_bkt,Ret_1m,exc,sz_tercile,on_t)],
             SS_all=SS_all, SS_mid=SS_mid, SS_held=SS_held, DS_all=DS_all, DS_mid=DS_mid,
             P1_all=P1_all, P1_mid=P1_mid, P2_all=P2_all, P2_mid=P2_mid,
             dur_slope=dur_slope, lag1=list(entry=L_entry,sustain=L_sust,exit=L_exit),
             held=list(entry=H_entry,sustain=H_sust,exit=H_exit)), file.path(OUT,"_r38_objects.rds"))

## ── 10. 사전등록 해시 + 결과 저장 ─────────────────────────────────────────────────
PREREG <- list(mode="RAMP-adjacent monitoring 진단 (insider SAFE 청산-타이밍 대칭)", round="R38", fq="FQ-052", wt="WT-D20260715_007",
  parent="R34 P3 / R37 next_probe (SAFE 진입 확립 → 청산 타이밍 대칭성)",
  base_source="R36 _r36_objects.rds uni (production clean T-1 파생, production_parity_verified 3.058, PIT C5 상속)",
  state_machine="ENTRY/SUSTAIN/EXIT/OFF (연속 hold_ym m-1→m + 양월 insider-covered + INS02 z>=1.0 교차)",
  diagnostics=list(
    P1="청산 대칭: state별 forward SAFE(raw/exc/downside/tail/vol) + 월별-paired NW-t (state vs OFF, EXIT vs SUSTAIN 전이델타)",
    P2="hold-duration: ON-run dur 버킷(d1/d2_3/d4plus) forward SAFE + dur→ret 기울기(신선도)",
    P3="monitoring 운영: 청산규칙(flag off 시 SAFE 해제) 필요성 판정"),
  decision_axis="SAFE 진입 정보성이 청산 시 대칭 소멸/재상승/점착 판별 → tripwire 청산규칙 필요성. 자본 아님(monitoring).",
  flags=list(net_buy="INS02_OffBuyBreadth6m z>=+1.0 (R33 frozen)"),
  pit="uni 상속 clean T-1 + signal m→hold m+1 (C5) + 연속월 z-transition + lag1 스트레스",
  selection_type="chain (가설주도 고정 config · sweep 아님)", n_trials=1L,
  vintage_pin=RAW_P, pin_mtime=PIN_MTIME, as_of="2026-07-15")
PREREG$config_hash <- substr(digest::digest(PREREG, algo="sha256"),1,16)
write_json(PREREG, file.path(OUT,"prereg_r38.json"), auto_unbox=TRUE, pretty=TRUE, digits=6)
wf("\n[prereg] config_hash=%s selection_type=chain n_trials=1", PREREG$config_hash)

fmt_paired <- function(x) list(gap_ann=round(x$gap_ann,5), gap_t=round(x$gap_t,3), n_months=x$n_months, avg_state_mo=round(x$avg_state_mo,2))
out <- list(prereg=PREREG, vintage_pin=RAW_P, pin_mtime=PIN_MTIME,
  base_parity=list(clean_parity_port_t=BASE_PARITY, note="§7b R36 uni 상속 production_parity_verified"),
  state_counts=list(all=setNames(as.list(st_cnt$N), st_cnt$state), mid=setNames(as.list(st_mid$N), st_mid$state),
    valid_transition_rows=uni[valid_tr==TRUE,.N]),
  state_summary=list(
    all=lapply(seq_len(nrow(SS_all)), function(i){ r<-SS_all[i]; as.list(r) }),
    mid=lapply(seq_len(nrow(SS_mid)), function(i){ r<-SS_mid[i]; as.list(r) }),
    held=lapply(seq_len(nrow(SS_held)), function(i){ r<-SS_held[i]; as.list(r) })),
  P1_symmetry=list(
    all=list(ENTRY_vs_OFF_raw=fmt_paired(P1_all$ENTRY_vs_OFF_Ret_1m), ENTRY_vs_OFF_exc=fmt_paired(P1_all$ENTRY_vs_OFF_exc),
             SUSTAIN_vs_OFF_raw=fmt_paired(P1_all$SUSTAIN_vs_OFF_Ret_1m), SUSTAIN_vs_OFF_exc=fmt_paired(P1_all$SUSTAIN_vs_OFF_exc),
             EXIT_vs_OFF_raw=fmt_paired(P1_all$EXIT_vs_OFF_Ret_1m), EXIT_vs_OFF_exc=fmt_paired(P1_all$EXIT_vs_OFF_exc),
             EXIT_vs_SUSTAIN_raw=list(gap_ann=round(P1_all$EXIT_vs_SUSTAIN_ret$gap_ann,5), gap_t=round(P1_all$EXIT_vs_SUSTAIN_ret$gap_t,3))),
    mid=list(ENTRY_vs_OFF_raw=fmt_paired(P1_mid$ENTRY_vs_OFF_Ret_1m), ENTRY_vs_OFF_exc=fmt_paired(P1_mid$ENTRY_vs_OFF_exc),
             SUSTAIN_vs_OFF_raw=fmt_paired(P1_mid$SUSTAIN_vs_OFF_Ret_1m), SUSTAIN_vs_OFF_exc=fmt_paired(P1_mid$SUSTAIN_vs_OFF_exc),
             EXIT_vs_OFF_raw=fmt_paired(P1_mid$EXIT_vs_OFF_Ret_1m), EXIT_vs_OFF_exc=fmt_paired(P1_mid$EXIT_vs_OFF_exc),
             EXIT_vs_SUSTAIN_raw=list(gap_ann=round(P1_mid$EXIT_vs_SUSTAIN_ret$gap_ann,5), gap_t=round(P1_mid$EXIT_vs_SUSTAIN_ret$gap_t,3)))),
  P2_duration=list(
    all_summary=lapply(seq_len(nrow(DS_all)), function(i) as.list(DS_all[i])),
    mid_summary=lapply(seq_len(nrow(DS_mid)), function(i) as.list(DS_mid[i])),
    all_vs_off=lapply(P2_all, function(x) list(gap_ann=round(x$gap_ann,5), gap_t=round(x$gap_t,3), n_months=x$n_months)),
    mid_vs_off=lapply(P2_mid, function(x) list(gap_ann=round(x$gap_ann,5), gap_t=round(x$gap_t,3), n_months=x$n_months)),
    freshness_slope=list(slope=round(dur_slope$slope,6), t=round(dur_slope$t,3), n=dur_slope$n)),
  lag1_stress=list(entry_t=round(L_entry$gap_t,3), sustain_t=round(L_sust$gap_t,3), exit_t=round(L_exit$gap_t,3)),
  held_confirm=list(n_name_months=nrow(uH_held), entry_t=round(H_entry$gap_t,3), sustain_t=round(H_sust$gap_t,3), exit_t=round(H_exit$gap_t,3)),
  verdict=list(symmetry=verdict_symmetry, exit_rule_needed=exit_rule_needed, exit_rule_recommendation=exit_rule_recommendation,
    entry_t_mid=round(e_t,3), sustain_t_mid=round(s_t,3), exit_vs_off_t_mid=round(x_t,3), exit_vs_sustain_t_mid=round(xs_t,3),
    on_lift_present=on_lift_present, return_reverts=return_reverts, risk_sticky=risk_sticky, risk_hangover=risk_hangover,
    mid_exit_downside=round(mid_exit$downside,4), mid_off_downside=round(mid_off$downside,4),
    mid_exit_tail=round(mid_exit$tail_hit,4), mid_off_tail=round(mid_off$tail_hit,4)),
  generated_at=format(Sys.time(),"%Y-%m-%dT%H:%M:%S%z"))
write_json(out, file.path(OUT,"r38_results.json"), auto_unbox=TRUE, pretty=TRUE, digits=5)

wf("\nR38_DONE | symmetry=%s exit_rule_needed=%s | 권고=%s | MID: SUSTAIN t=%+.2f EXIT_vs_OFF t=%+.2f | risk_sticky=%s hangover=%s | lag1 exit_t=%+.2f | held exit_t=%+.2f",
   verdict_symmetry, exit_rule_needed, exit_rule_recommendation, s_t, x_t, risk_sticky, risk_hangover, L_exit$gap_t, H_exit$gap_t)
cat("[SAVED]", file.path(OUT,"r38_results.json"), "\n")
