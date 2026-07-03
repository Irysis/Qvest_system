## ============================================================
## PG2 공격형 오버레이 Round 3 — 클린-타이밍 재판정 (전 변형 +1개월 lag)
## 도훈 지시 2026-07-02 스레드. 발견: layer5 panel row의 수익 윈도우는
## realized_ym 라벨보다 1개월 뒤(backward: (anchor[r-1], anchor[r]], β-스캔
## cor 0.731 vs forward 0.058) — 따라서 canonical ym_next(+1) merge는 신호를
## 자기 수익 윈도우 *안*(종료 ~3일 전)에 적용 = 동월 누출 의심.
## 클린 규칙: 신호 월말(m) → row m+2 (윈도우 = 달력월 m+1, 신호가 윈도우
## 시작 전에 확정) — 전 변형 동일 적용해 공정 재판정.
## 주의: panel의 m4/beta_R05/beta_AR(*_lag)도 동일 의심이나 전 변형 공유라
## head-to-head 공정성 유지. 절대수치는 별도 감사 대상(후속 WT).
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
BM_PIN   <- file.path(OUT_DIR, "benchmark_pinned_20260702.parquet")
T_HALF <- 16L; PAPER_COEF <- c(a=0.13, d=0.79, e=-0.17, f=0.09); COST <- 0.0015

cat("[1] panel + pinned 신호 (Round 2.5와 동일 산출, merge만 클린 lag)\n")
p <- fread(file.path(BASE_DIR, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym); stopifnot(nrow(p)==269)
bm <- as.data.table(read_parquet(BM_PIN))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]; bm[, Date := as.Date(Date)]
bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
r <- bm[[bcol]]; n <- length(r)
rm252 <- frollmean(r, 252, na.rm=TRUE); rs252 <- frollapply(r, 252, sd, na.rm=TRUE)
rhat <- pmin(pmax((r - rm252)/(rs252 + 1e-12), -20), 20); rhat[!is.finite(rhat)] <- NA
al <- 1 - exp(-1/T_HALF)
sig2 <- rep(NA_real_, n); acc <- 1.0; sig2d <- rep(NA_real_, n); accd <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) {
  acc <- al*rhat[t]^2 + (1-al)*acc; sig2[t] <- acc
  dsq <- if (rhat[t] < 0) 2*rhat[t]^2 else 0; accd <- al*dsq + (1-al)*accd; sig2d[t] <- accd }
N <- 6L*T_HALF; wn <- (0:N)*exp(-2*(0:N)/T_HALF); wn <- wn/sqrt(sum(wn^2))
phi <- rep(NA_real_, n)
for (t in (N+1):n) { seg <- rhat[(t-N):t]; if (all(is.finite(seg))) phi[t] <- pmin(pmax(sum(wn*rev(seg)),-2.5),2.5) }
bm[, phi_d := phi]
bm[, S_faith := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2  + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2]
bm[, S_semi  := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2d + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2*(phi<0)]
bm[, ym := format(Date, "%Y-%m")]
bm_x <- xts(bm[[bcol]], order.by=bm$Date)
mret <- apply.monthly(bm_x, Return.cumulative)
mdt <- data.table(ym=format(index(mret), "%Y-%m"), mret=as.numeric(mret))
mdt[, cum12 := frollapply(mret, 12, function(z) prod(1+z)-1)]
mdt[, cum2  := frollapply(mret, 2,  function(z) prod(1+z)-1)]
mk_state <- function(c12, cf) fifelse(!is.finite(c12) | !is.finite(cf), "NA",
  fifelse(c12 >= 0 & cf >= 0, "Bull", fifelse(c12 >= 0 & cf < 0, "Correction",
  fifelse(c12 < 0 & cf < 0, "Bear", "Rebound"))))
mdt[, state2 := mk_state(cum12, cum2)]
me <- bm[, .(S_faith=last(S_faith), S_semi=last(S_semi), phi_m=last(phi_d)), by=ym]
me <- merge(me, mdt[, .(ym, state2)], by="ym", all.x=TRUE); setorder(me, ym)
## ★ 클린 타이밍: 신호월 m → row m+2 (윈도우 = 달력월 m+1). 비교용 leaky(+1)도 산출.
me[, ym_p1 := format(as.Date(paste0(ym,"-01")) %m+% months(1), "%Y-%m")]
me[, ym_p2 := format(as.Date(paste0(ym,"-01")) %m+% months(2), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_p1, S_semi_lk=S_semi, state2_lk=state2)], by="realized_ym", all.x=TRUE)
p <- merge(p, me[, .(realized_ym=ym_p2, S_faith_cl=S_faith, S_semi_cl=S_semi, phi_cl=phi_m, state2_cl=state2)], by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
p[is.na(state2_lk), state2_lk := "NA"]; p[is.na(state2_cl), state2_cl := "NA"]

cat("[2] 매핑 (freq-match, Round 1과 동일 임계)\n")
exp_pct <- function(x) { out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[seq_len(i-1)]; past <- past[is.finite(past)]
    if (length(past) >= 24 && is.finite(x[i])) out[i] <- mean(past < x[i]) }
  out }
freq <- prop.table(table(round(p$beta_AR,2))); lo <- sort(as.numeric(names(freq))[as.numeric(names(freq)) < 0.999])
cumf <- 0; thr <- list()
for (l in lo) { f <- as.numeric(freq[as.character(l)]); if (is.na(f)) f <- 0
  thr[[length(thr)+1]] <- c(l, 1-cumf-f, 1-cumf); cumf <- cumf+f }
map_freq <- function(pp){ if(!is.finite(pp)) return(1.0)
  for (tt in thr) if (pp >= tt[2] && pp < tt[3]) return(tt[1])
  if (length(lo) && pp >= 1-cumf) return(lo[1]); 1.0 }
b_faith_cl <- sapply(exp_pct(p$S_faith_cl), map_freq)   # 클린 faith 재구축 (canonical recipe, lag만 정정)
b_f5_cl    <- sapply(exp_pct(p$S_semi_cl),  map_freq)   # 클린 F5
b_f5_lk    <- sapply(exp_pct(p$S_semi_lk),  map_freq)   # leaky F5 (참조)

cat("[3] 변형군 (클린 vs leaky 대조)\n")
mk_E <- function(beta, bull_floor=NA, st_vec=NULL) {
  E <- p$beta_R05 * p$m4 * beta
  if (is.finite(bull_floor) && !is.null(st_vec)) E <- ifelse(st_vec == "Bull", pmax(E, bull_floor), E)
  E }
E_list <- list(
  C0_recorded_leaky = p$beta_R05 * p$m4 * p$beta_faith,       # canonical 기록 (leaky 의심 참조)
  C1_faith_clean    = mk_E(b_faith_cl),                        # ★클린 incumbent 재구축
  C2_no_faith       = mk_E(rep(1, nrow(p))),                   # 타이밍-무관 anchor
  C3_naked          = rep(1, nrow(p)),
  F5_leaky          = mk_E(b_f5_lk),                           # 참조 (R1 F5 재현 예상)
  F5_clean          = mk_E(b_f5_cl),                           # ★클린 F5
  F3_clean          = { b3 <- b_faith_cl; b3[is.finite(p$phi_cl) & p$phi_cl > 0] <- 1.0; mk_E(b3) },
  G1_bbt_clean      = { bg <- fifelse(p$state2_cl=="Bull",1.0, fifelse(p$state2_cl=="Correction",0.7,
                          fifelse(p$state2_cl=="Bear",0.4, 1.0))); mk_E(bg) },
  G3a_clean         = mk_E(b_f5_cl, bull_floor=0.85, st_vec=p$state2_cl),
  G3b_clean         = mk_E(b_f5_cl, bull_floor=1.00, st_vec=p$state2_cl),
  G3b_on_faith_cl   = mk_E(b_faith_cl, bull_floor=1.00, st_vec=p$state2_cl)  # floor를 클린 faith 위에
)
ret_of <- function(E) { dE <- abs(E - shift(E, 1, fill=1.0)); list(ret=E*p$ret_orig - dE*COST, dE=dE) }
nw_t <- function(d, lag=3) { d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu; s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn) }
ann_sr <- function(ret, idx=p$anchor_date) as.numeric(table.AnnualizedReturns(xts(ret, order.by=idx), scale=12)[3,1])
R <- lapply(E_list, ret_of)
ret_c1 <- R$C1_faith_clean$ret; ret_f5 <- R$F5_clean$ret
res <- rbindlist(lapply(names(E_list), function(nm) {
  ret <- R[[nm]]$ret; x <- xts(ret, order.by=p$anchor_date)
  data.table(variant=nm,
    SR=round(ann_sr(ret),3), CAGR=round(as.numeric(Return.annualized(x, scale=12)),4),
    MDD=round(as.numeric(maxDrawdown(x)),4), Calmar=round(as.numeric(CalmarRatio(x, scale=12)),3),
    Sortino_m=round(as.numeric(SortinoRatio(x, MAR=0)),4),
    ret_2025=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2025"])),4),
    ret_2026=round(as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"])),4),
    avg_expo=round(mean(E_list[[nm]], na.rm=TRUE),3), turnover_dE=round(sum(R[[nm]]$dE, na.rm=TRUE),2),
    nw_t_vs_C1cl=round(nw_t(ret - ret_c1),2), nw_t_vs_F5cl=round(nw_t(ret - ret_f5),2))
}))
cat("\n===== ROUND 3 CLEAN-TIMING RESULTS =====\n"); print(res, nrow=99)

cat("\n[4] 클린 G3b OOS v2 + subperiod (생존 시 판정용)\n")
oos_v2 <- function(ret) { ns <- length(ret)
  rs <- sapply(c(0.55,0.65,0.75), function(f) { k <- floor(ns*f)
    is_sr <- ann_sr(ret[1:k], p$anchor_date[1:k]); oos_sr <- ann_sr(ret[(k+1):ns], p$anchor_date[(k+1):ns])
    if (!is.finite(is_sr) || abs(is_sr) < 1e-9) return(NA_real_); oos_sr/is_sr })
  round(median(rs, na.rm=TRUE),3) }
pre <- p$anchor_date < as.Date("2017-01-01")
sub <- rbindlist(lapply(c("C1_faith_clean","F5_clean","G3b_clean","G3b_on_faith_cl","C2_no_faith"), function(nm)
  data.table(variant=nm, oos_v2=oos_v2(R[[nm]]$ret),
    SR_pre2017=round(ann_sr(R[[nm]]$ret[pre], p$anchor_date[pre]),3),
    SR_post2017=round(ann_sr(R[[nm]]$ret[!pre], p$anchor_date[!pre]),3))))
print(sub)

cat("\n[5] 핵심 head-to-head 요약\n")
cat(sprintf("    faith 레이어 클린 기여: C1_faith_clean %.3f vs C2_no_faith %.3f (Δ %.3f)\n",
    res[variant=="C1_faith_clean",SR], res[variant=="C2_no_faith",SR],
    res[variant=="C1_faith_clean",SR]-res[variant=="C2_no_faith",SR]))
cat(sprintf("    세미분산 클린 개선: F5_clean %.3f vs C1_faith_clean %.3f (NW-t %s)\n",
    res[variant=="F5_clean",SR], res[variant=="C1_faith_clean",SR], res[variant=="F5_clean",nw_t_vs_C1cl]))
cat(sprintf("    bull-floor 클린 개선: G3b_clean %.3f vs F5_clean %.3f (NW-t %s)\n",
    res[variant=="G3b_clean",SR], res[variant=="F5_clean",SR], res[variant=="G3b_clean",nw_t_vs_F5cl]))
fwrite(res, file.path(OUT_DIR, "offense_round3_clean_results.csv"))
fwrite(sub, file.path(OUT_DIR, "offense_round3_clean_oos_sub.csv"))
meta <- list(date="2026-07-02", round="3-clean-timing",
  finding="panel row 수익윈도우 = realized_ym보다 1개월 뒤(backward, beta-scan cor .731 vs .058) → canonical ym_next merge는 동월 적용 의심. 본 라운드 = 전 신호 +1개월 추가 lag(신호월 m → row m+2) 재판정",
  caveat="m4/beta_R05/beta_AR(*_lag 패널 컬럼)도 동일 의심이나 전 변형 공유 — head-to-head는 공정, 절대수치는 후속 감사 필요",
  selection_type="sweep", n_trials_cumulative=31L, metric_type="backtested(panel-overlay), diagnostic-tier")
write_json(meta, file.path(OUT_DIR, "offense_round3_clean_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat("\n[DONE] Round 3 산출:", OUT_DIR, "\n")
