#!/usr/bin/env Rscript
# fq193_wamt_measure_20260809.R — FQ-193: 계약 커버 집합 천장(+0.4153)을 **w_amt(절대 계약금액)** 로 겨냥.
#
# ★사전등록(측정 전 고정, 본 헤더가 정본):
#  대상 축소 경위: FQ-193 이 명시한 4필드(n_contracts·amend_n·round_n·fx_n)는 착수 전 확인에서
#    커버 종목 안 0비율 62.5~97.9%, 분할불가 월 17~71/79 로 **전부 측정 제외**.
#    잔존 후보 중 w_n 은 w_ratio(F1 반증 종료)와 rho +0.785 = 부분 재탕이라 제외.
#    ⇒ **w_amt 단독**(w_ratio 와 rho +0.304 = 분모를 뺀 독립 축). 단일 테스트 → 다중검정 보정 불요.
#  형태: FQ-002(B)와 **동일 고정** — 커버 종목 중 하위 3분위 제외, 강도 k≈1. 흔들지 않는다.
#  방향: 절대 계약금액이 클수록 좋다(하위 제외). 기전 = 수주 규모의 실질 이익 기여.
#  판정 기준: **무작위 q95** (게이트 0.05 아님 — 무작위로도 넘는다). 회수율 = ΔIR / 0.4153.
#  F1 반증: ΔIR <= 무작위 q95 → 신호 아님.
#  F2 반증: q95 초과하되 회수율 <25% → 천장 실재하나 이 축으로는 못 캠.
#  F3 시대: 전·후반 부호 갈리면 교락 라벨, 단일 판정 금지.
#  F4 음성대조: 난수 신호 동일 절차가 무작위 분포와 구별되면 절차 편향 → 판정 무효.
#  ★F5 size 교락(신규): w_amt 는 대형주일수록 크다. book 내 rank/weight 와의 상관을 보고하고,
#    상관이 |0.5| 이상이면 결과를 **size 교락 미해결**로 라벨한다(캐리어에 시총 컬럼 부재 —
#    독립 size arm 은 rawdata 조인이 필요해 본 라운드 범위 밖. 숨기지 않고 한계로 명시).
#  PIT: 패널 ym = 홀딩월 M-1 (w_amt 는 12M 누적 — ym=M 은 동월 look-ahead).
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
setwd(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
Sys.setenv(QVEST_WEIGHTING_AB_NORUN = "1")
source("02_Infrastructure/contracts/weighted_screen_bt.R")
source("02_Infrastructure/ops/auto_weighting_ab.R")
say <- function(...) cat(sprintf(...), "\n", sep = "")

mt  <- fromJSON("06_Registry/book_carrier/carrier_meta.json", simplifyVector = FALSE)
car <- as.data.table(read_parquet(as.character(mt$parquet)))
car[, `:=`(decision_date = as.Date(decision_date), eval_date = as.Date(eval_date))]
car <- car[selected == TRUE & !is.na(ret_fwd)]
car[, ym := as.integer(format(decision_date, "%Y%m"))]
P <- as.data.table(read_parquet("04_Research/method_frontier/fq002_contract_magnitude/panelx_B_corrected.parquet"))
P[, ym := as.integer(ym)]
shift_ym <- function(y) { yr <- y %/% 100L; mo <- y %% 100L + 1L
  yr <- yr + (mo - 1L) %/% 12L; mo <- ((mo - 1L) %% 12L) + 1L; yr * 100L + mo }
P[, ym_use := shift_ym(ym)]
C <- merge(car, P[, .(ym_use, Ticker, w_amt, w_ratio)],
           by.x = c("ym", "Ticker"), by.y = c("ym_use", "Ticker"), all.x = TRUE)
C[, covered := !is.na(w_amt)]
ovm <- sort(unique(C[covered == TRUE]$ym)); C <- C[ym >= min(ovm) & ym <= max(ovm)]; setorder(C, ym)
say("창 %d개월(%d~%d) · 커버 %.2f종/%.1f (%.1f%%)", uniqueN(C$ym), min(C$ym), max(C$ym),
    C[covered==TRUE,.N]/uniqueN(C$ym), nrow(C)/uniqueN(C$ym), 100*mean(C$covered))

# F5: size 교락 지표 — w_amt 와 book 내 rank/weight 상관
r_rank <- suppressWarnings(cor(C[covered==TRUE]$w_amt, C[covered==TRUE]$rank, method="spearman"))
r_wt   <- suppressWarnings(cor(C[covered==TRUE]$w_amt, C[covered==TRUE]$weight_strategy, method="spearman"))
say("[F5] w_amt vs book rank rho %+.3f · vs weight rho %+.3f → %s",
    r_rank, r_wt, if (max(abs(c(r_rank, r_wt))) >= 0.5) "★size/선호 교락 의심" else "교락 낮음")

periods <- unique(C[, .(decision_date, eval_date)]); setorder(periods, eval_date)
bench_dt <- build_period_bench(periods)[!is.na(BM_Ret)]
returns_dt <- C[, .(Date = eval_date, Ticker, Ret_1m = ret_fwd)]
runW <- function(kp, tag) { d <- C[kp]
  W <- d[, .(Date=eval_date, Ticker, w=weight_strategy/sum(weight_strategy)), by=.(eval_date)][,.(Date,Ticker,w)]
  r <- weighted_screen_bt(W, returns_dt, bench_dt, cost_bps_oneway=15, run_id=tag, strategy_id=tag)
  list(IR=r$information_ratio, PORT_t=r$portfolio_alpha_t_nw_lag3, n=r$n_months) }

base <- runW(rep(TRUE, nrow(C)), "base")
say("기준선 book: IR %.4f · PORT_t %.3f · %d개월", base$IR, base$PORT_t, base$n)

C[, drop_sig := FALSE]
C[covered == TRUE, drop_sig := frank(w_amt, ties.method="average")/.N <= (1/3), by = ym]
nd <- mean(C[, sum(drop_sig), by=ym]$V1)
prim <- runW(!C$drop_sig, "primary_wamt_bottom_tercile")
say("\n[primary] w_amt 하위3분위 제외 — 월 %.2f종 · IR %.4f · ΔIR %+.4f · PORT_t %.3f (Δ %+.3f)",
    nd, prim$IR, prim$IR-base$IR, prim$PORT_t, prim$PORT_t-base$PORT_t)

set.seed(20260809); neg <- numeric(0)
for (s in 1:30) { C[, drop_ng := FALSE]
  C[covered==TRUE, drop_ng := frank(runif(.N), ties.method="first")/.N <= (1/3), by=ym]
  neg <- c(neg, runW(!C$drop_ng, sprintf("neg%d", s))$IR) }
q95 <- unname(quantile(neg,.95)) - base$IR
say("[F4 음성대조] 난수 30draw ΔIR 중앙 %+.4f · q95 %+.4f", median(neg)-base$IR, q95)

C[, drop_or := FALSE]; C[covered==TRUE, drop_or := frank(ret_fwd, ties.method="first") <= 1L, by=ym]
orc <- runW(!C$drop_or, "oracle")
say("[양성대조] 완전예지 ΔIR %+.4f (사전 +0.4153 재현)", orc$IR-base$IR)

mid <- sort(unique(C$ym))[ceiling(uniqueN(C$ym)/2)]
sub <- function(D, tg) { pr <- unique(D[,.(decision_date,eval_date)]); setorder(pr, eval_date)
  bd <- build_period_bench(pr)[!is.na(BM_Ret)]; rd <- D[,.(Date=eval_date,Ticker,Ret_1m=ret_fwd)]
  f <- function(kp,t2){ d<-D[kp]; W<-d[,.(Date=eval_date,Ticker,w=weight_strategy/sum(weight_strategy)),by=.(eval_date)][,.(Date,Ticker,w)]
    weighted_screen_bt(W,rd,bd,cost_bps_oneway=15,run_id=t2,strategy_id=t2)$information_ratio }
  c(b=f(rep(TRUE,nrow(D)),paste0(tg,"b")), f=f(!D$drop_sig,paste0(tg,"f"))) }
s1 <- sub(C[ym<=mid],"h1"); s2 <- sub(C[ym>mid],"h2")
say("[F3 시대] 전반 %+.4f · 후반 %+.4f · %s", s1["f"]-s1["b"], s2["f"]-s2["b"],
    if (sign(s1["f"]-s1["b"])==sign(s2["f"]-s2["b"])) "부호 일치" else "★부호 갈림(교락 라벨)")

dIR <- prim$IR-base$IR; rec <- dIR/0.4153
say("\n=== 사전등록 판정 ===")
say("  ΔIR %+.4f · 음성대조 q95 %+.4f · 회수율 %.1f%%", dIR, q95, 100*rec)
v <- if (dIR <= q95) "F1 반증 — 무작위 q95 이하. 신호 아님." else
     if (rec < 0.25) "F2 반증 — q95 초과하나 회수율 <25%. 이 축으로는 못 캠." else
     "사전등록 통과 — 단 F5 size 교락 라벨 확인 필요."
say("  ⇒ %s", v)

write(toJSON(list(schema="fq193_wamt_v1", date="20260809", metric_type="canonical_screen",
  window=c(min(C$ym),max(C$ym)), n_months=base$n, coverage_pct=round(100*mean(C$covered),2),
  mean_drop=round(nd,3),
  f5_size_confound=list(rho_rank=round(r_rank,3), rho_weight=round(r_wt,3),
                        flagged=max(abs(c(r_rank,r_wt)))>=0.5,
                        limit="캐리어에 시총 컬럼 부재 — 독립 size arm 은 rawdata 조인 필요, 본 라운드 범위 밖"),
  base=list(IR=round(base$IR,4), PORT_t=round(base$PORT_t,3)),
  primary=list(IR=round(prim$IR,4), dIR=round(dIR,4), PORT_t=round(prim$PORT_t,3)),
  negative_control=list(median_dIR=round(median(neg)-base$IR,4), q95_dIR=round(q95,4)),
  positive_control=list(oracle_dIR=round(orc$IR-base$IR,4), prior=0.4153),
  era=list(mid=mid, h1=round(unname(s1["f"]-s1["b"]),4), h2=round(unname(s2["f"]-s2["b"]),4)),
  recovery_rate=round(rec,4), verdict=v,
  scope_reduction="FQ-193 명시 4필드(n_contracts/amend_n/round_n/fx_n) 전부 분할 불가로 측정 제외 · w_n 은 w_ratio 와 rho 0.785 부분재탕으로 제외 → w_amt 단독"),
  pretty=TRUE, auto_unbox=TRUE, na="null"),
  "stage_artifacts/paper_recharge/fq193_wamt_results_20260809.json")
say("\n저장: stage_artifacts/paper_recharge/fq193_wamt_results_20260809.json")
