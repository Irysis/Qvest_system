## WT-D20260822_009 — 사전점검 (측정 전). 구조 census + 검정력만. 성과수치 산출 금지.
suppressMessages({library(data.table);library(arrow);library(jsonlite);library(sandwich);library(lmtest)})
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT <- file.path(ROOT,"stage_artifacts/WT-D20260822_009"); dir.create(OUT,FALSE,TRUE)
say <- function(f,...) cat(sprintf(paste0("[pre] ",f,"\n"),...))
J <- list()

## ── A. 선행 라운드에서 **직접 측정된** paired Δactive 산포 (계약 기본값 아님) ──
r14 <- readRDS("stage_artifacts/WT_D20260802_014/wt014_eval_results.rds")
ps  <- as.data.table(r14$paired_series)
say("WT014 paired_series cols: %s", paste(names(ps), collapse=", "))
dcol <- intersect(c("d_active","dact","d"), names(ps))[1]
sd_d <- sd(ps[[dcol]], na.rm=TRUE); n14 <- sum(is.finite(ps[[dcol]]))
say("측정 sd(Δactive) = %.6f /월  (n=%d, 출처 WT-D20260802_014 동일 base·동일 하네스·동일 섭동유형)", sd_d, n14)
J$measured_sd <- list(value=sd_d, n=n14, source="stage_artifacts/WT_D20260802_014/wt014_eval_results.rds$paired_series",
  note="계약 기본 sd 미사용 — 동일 base(cleanT1 production_parity_verified)·동일 하네스(top25 cap_norm weighted_screen_bt 15bps)·동일 섭동유형(유니버스 배제필터)의 실측 월별 paired Δactive 표준편차")
J$prior_art_effect <- list(delta_ir=r14$paired$delta_ir, paired_t=r14$paired$paired_t,
  port_t_base=r14$base$portfolio_alpha_t_nw_lag3, port_t_filt=r14$filtered$portfolio_alpha_t_nw_lag3,
  ir_base=r14$base$information_ratio, ir_filt=r14$filtered$information_ratio,
  n_months=nrow(ps), mean_d=mean(ps[[dcol]],na.rm=TRUE))
say("★양성 대조(창-도달가능성): WT014 복권필터 ΔIR=%+.4f 인데 paired NW t=%+.3f (n=%d)", 
    r14$paired$delta_ir, r14$paired$paired_t, nrow(ps))

## ── B. 패널 정렬 census ──────────────────────────────────────────────────────
SI <- readRDS("stage_artifacts/WT_D20260714_004/screen_inputs.rds")
fwd_ret <- as.data.table(SI$fwd_ret); liqf <- as.data.table(SI$liqf); SIZE <- as.data.table(SI$SIZE)
for (dt in list(fwd_ret,liqf,SIZE)) dt[, Date := as.Date(Date)]
CLEAN <- as.data.table(read_parquet("05_Production/2.Factor_Model/2-1.STR_1715_AR_on_M4_R05_overlay_PG2/02_holdings_universe/alpha_scores_str1715_268m_cleanT1.parquet"))
CLEAN[, Date := as.Date(Date)]
stopifnot(CLEAN$vintage_verified[1]=="production_parity_verified")
P <- as.data.table(read_parquet("stage_artifacts/WT-D20260813_006/absorb_panel.parquet"))
P[, Date := as.Date(Date)]
AB <- P[is.finite(absorb), .(Date, Ticker, absorb)]
say("CLEAN %d행 %d월 [%s..%s] | absorb %d행 %d월 [%s..%s]", nrow(CLEAN),uniqueN(CLEAN$Date),
    min(CLEAN$Date),max(CLEAN$Date), nrow(AB),uniqueN(AB$Date),min(AB$Date),max(AB$Date))

d0map <- data.table(d0=sort(unique(fwd_ret$Date)))[, ym:=format(d0,"%Y-%m")]
CL <- copy(CLEAN)[, map_ym := format(Date-1,"%Y-%m")]
CLd <- merge(CL, d0map, by.x="map_ym", by.y="ym")
S0 <- merge(CLd[is.finite(score_eff), .(Date=d0,Ticker,sc=score_eff)], SIZE, by=c("Date","Ticker"))
S0 <- merge(S0, liqf, by=c("Date","Ticker"), all.x=TRUE)
S0 <- S0[is.na(adv)|adv>=2e8]
say("base 후보(liq 후) %d행 %d월 [%s..%s]", nrow(S0),uniqueN(S0$Date),min(S0$Date),max(S0$Date))
## absorb Date 가 d0 격자와 정확히 같은가
ab_d <- sort(unique(AB$Date)); s0_d <- sort(unique(S0$Date))
say("absorb Date ∩ base d0 = %d (base %d월 중) — 격자 정합 %s",
    length(intersect(ab_d,s0_d)), length(s0_d),
    if(length(intersect(ab_d,s0_d))>=0.95*length(s0_d)) "OK" else "★불일치")
common <- as.Date(intersect(ab_d,s0_d), origin="1970-01-01")
J$grid <- list(clean_months=uniqueN(CLEAN$Date), absorb_months=length(ab_d),
  base_d0_months=length(s0_d), common_months=length(common),
  common_start=as.character(min(common)), common_end=as.character(max(common)))

## ── C. 배제 census (X=20% 하위분위) — 성과 아님, 구조량 ──────────────────────
SM <- merge(S0[Date %in% common], AB, by=c("Date","Ticker"), all.x=TRUE)
mk <- function(SM,X){ S2<-copy(SM)
  S2[, thr := { v<-absorb[is.finite(absorb)]
    if(length(v)>=30L) quantile(v, X, type=7, names=FALSE) else -Inf }, by=Date]
  S2[, excluded := is.finite(absorb) & absorb <= thr]; S2 }
for (X in c(0.10,0.20,0.30)) {
  S2 <- mk(SM,X)
  ct <- S2[, .(n_cand=.N, n_fin=sum(is.finite(absorb)), n_ex=sum(excluded), n_left=sum(!excluded)), by=Date]
  say("X=%2.0f%%: 월평균 후보 %.0f / absorb 커버 %.1f%% / 배제 %.1f종 / 잔여 %.0f종 / 잔여<25 월수 %d (min 잔여 %d)",
      100*X, ct[,mean(n_cand)], 100*ct[,sum(n_fin)/sum(n_cand)], ct[,mean(n_ex)], ct[,mean(n_left)],
      ct[n_left<25,.N], ct[,min(n_left)])
  if (abs(X-0.20)<1e-9) J$census_X20 <- list(mean_cand=ct[,mean(n_cand)], coverage=ct[,sum(n_fin)/sum(n_cand)],
      mean_excluded=ct[,mean(n_ex)], mean_left=ct[,mean(n_left)], min_left=ct[,min(n_left)],
      months_left_lt25=ct[n_left<25,.N], n_months=nrow(ct))
}
## 청정창(2015-12~) 분해
S2 <- mk(SM,0.20); ct <- S2[, .(n_cand=.N,n_fin=sum(is.finite(absorb)),n_ex=sum(excluded),n_left=sum(!excluded)), by=Date]
lateN <- ct[Date>=as.Date("2015-12-01"), .N]; earlyN <- ct[Date<as.Date("2015-12-01"), .N]
say("창 분해: pre-2015-12 %d월 / 2015-12~ %d월", earlyN, lateN)
J$window_split <- list(pre201512_months=earlyN, post201512_months=lateN)

## ── D. MDE / implied_t (사전) ────────────────────────────────────────────────
nfull <- length(common); nlate <- lateN
mde <- function(n, sd, pw=2.802) pw*sd/sqrt(n)     # 80% power, alpha .05 two-sided
say("MDE(80%%,alpha .05): full n=%d -> %.5f/월 (연 %.3f%%p) | late n=%d -> %.5f/월 (연 %.3f%%p)",
    nfull, mde(nfull,sd_d), 1200*mde(nfull,sd_d), nlate, mde(nlate,sd_d), 1200*mde(nlate,sd_d))
## 선행 실측 효과크기가 이 창에서 내는 implied t
imp <- function(n, meand, sd) meand/(sd/sqrt(n))
say("implied t @ WT014 효과크기(mean Δactive=%.5f): full %.2f / late %.2f (iid 근사; 실측 NW t=%.3f)",
    J$prior_art_effect$mean_d, imp(nfull,J$prior_art_effect$mean_d,sd_d),
    imp(nlate,J$prior_art_effect$mean_d,sd_d), J$prior_art_effect$paired_t)
J$power <- list(sd_monthly=sd_d, n_full=nfull, n_late=nlate,
  mde_full_monthly=mde(nfull,sd_d), mde_full_annual_pp=1200*mde(nfull,sd_d),
  mde_late_monthly=mde(nlate,sd_d), mde_late_annual_pp=1200*mde(nlate,sd_d),
  implied_t_at_prior_effect_full=imp(nfull,J$prior_art_effect$mean_d,sd_d),
  implied_t_at_prior_effect_late=imp(nlate,J$prior_art_effect$mean_d,sd_d),
  note="iid 근사. 실측 NW lag-3 t 는 자기상관 보정으로 이보다 작다 — WT014 실측 t 1.565 vs iid implied 로 배율 확인")
J$nw_deflation_factor <- J$prior_art_effect$paired_t / imp(n14, J$prior_art_effect$mean_d, sd_d)
say("NW 보정 배율(실측 t / iid t) = %.3f", J$nw_deflation_factor)

## ── E. PIT — 오버레이 신호 타이밍 HARD ───────────────────────────────────────
source("02_Infrastructure/validation/overlay_pit_guard.R")
d0s <- sort(unique(SM$Date))
hold_start <- as.Date(format(seq(d0s[1], by="1 month", length.out=1)+31,"%Y-%m-01"))
res <- sapply(seq_along(d0s), function(i){
  d0 <- d0s[i]; hs <- as.Date(format(d0+20,"%Y-%m-01"))   # 홀딩월 1일
  tryCatch({assert_overlay_pit(d0, hs, "absorb_excl"); TRUE}, error=function(e) FALSE)})
say("assert_overlay_pit: %d/%d PASS", sum(res), length(res))
## 위반 주입 — 컷오프를 홀딩월 말로 밀면 반드시 FAIL 이어야
inj <- sapply(seq_along(d0s), function(i){ d0<-d0s[i]; hs<-as.Date(format(d0+20,"%Y-%m-01"))
  tryCatch({assert_overlay_pit(hs+27, hs, "absorb_INJ"); TRUE}, error=function(e) FALSE)})
say("위반 주입: %d/%d 통과(=검사기 무력) — 0 이어야 정상", sum(inj), length(inj))
J$pit <- list(assert_pass=sum(res), assert_n=length(res), injection_pass=sum(inj),
  detector_alive=(sum(inj)==0))

write_json(J, file.path(OUT,"00_precheck.json"), auto_unbox=TRUE, pretty=TRUE, digits=NA, na="null")
say("done")
