## ============================================================
## PG2 공격형 오버레이 Round 1 배터리 — 스칼라 β 매핑 변형 실측
## 도훈 지시 2026-07-02 "현 PG2 오버레이는 방어형 — 공격형 설계"
## ============================================================
## 대상: W1(강세장 참여 부족, 2026 YTD +65% vs KOSPI +85%) 직격.
## 방법: canonical run_layer5_faith_overlay.R의 신호 산출을 그대로 복제하고
##       β 매핑/레이어 결합만 변형. 신호 timing(월말 S → 익월 적용 lag-1,
##       expanding past-only percentile ≥24obs)은 canonical과 동일 = PIT 상속.
## selection_type = sweep (변형 열거 후 비교) — n_trials 기록, graduation 시 DSR 적용 대상.
## 비용: 주 convention = |ΔE|×15bps (E = β_R05×m4×β_faith 총 exposure, delta-based v2.4 정합).
##       참조로 incumbent 기록 convention(|Δβ_faith|+|Δβ_R05| 별도 과금)도 병기.
## metric_type = backtested (panel = forge 검증된 layer5 산출물 위 overlay 재계산)
## ============================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
  library(PerformanceAnalytics); library(xts); library(lubridate)
})
BASE_DIR <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
OUT_DIR  <- file.path(BASE_DIR, "stage_artifacts/pg2_offense_overlay")
dir.create(OUT_DIR, recursive=TRUE, showWarnings=FALSE)
T_HALF <- 16L; PAPER_COEF <- c(a=0.13, d=0.79, e=-0.17, f=0.09)
COST <- 0.0015

cat("[1] faith panel 로드 (canonical 산출물 — 269m)\n")
p <- fread(file.path(BASE_DIR, "05_Production/2.Factor_Model/2-2.STR_1715_FaithTrend_on_M4_R05_overlay_PG2/04_backtest_results/period_returns_layer5_faith.csv"))
p[, anchor_date := as.Date(anchor_date)]; setorder(p, realized_ym)
stopifnot(nrow(p) > 250, all(is.finite(p$ret_orig)))
cat(sprintf("    %d개월 %s ~ %s\n", nrow(p), p$realized_ym[1], p$realized_ym[.N]))

cat("[2] KOSPI 일별 신호 재산출 (canonical 복제) + 변형 신호 2종\n")
bm <- as.data.table(read_parquet(file.path(BASE_DIR, ".cache/benchmark.parquet")))
bcol <- intersect(c("BM_Ret","Ret"), names(bm))[1]; bm[, Date := as.Date(Date)]
bm <- bm[is.finite(get(bcol))]; setorder(bm, Date)
r <- bm[[bcol]]; n <- length(r)
rm252 <- frollmean(r, 252, na.rm=TRUE); rs252 <- frollapply(r, 252, sd, na.rm=TRUE)
rhat <- pmin(pmax((r - rm252)/(rs252 + 1e-12), -20), 20); rhat[!is.finite(rhat)] <- NA
al <- 1 - exp(-1/T_HALF)
## σ² 표준 (canonical) + σ²_down (하방 세미분산 EWMA, ×2 스케일 보정)
sig2 <- rep(NA_real_, n); acc <- 1.0
sig2d <- rep(NA_real_, n); accd <- 1.0
for (t in seq_len(n)) if (is.finite(rhat[t])) {
  acc  <- al*rhat[t]^2 + (1-al)*acc;  sig2[t]  <- acc
  dsq  <- if (rhat[t] < 0) 2*rhat[t]^2 else 0
  accd <- al*dsq + (1-al)*accd;       sig2d[t] <- accd
}
N <- 6L*T_HALF; wn <- (0:N)*exp(-2*(0:N)/T_HALF); wn <- wn/sqrt(sum(wn^2))
phi <- rep(NA_real_, n)
for (t in (N+1):n) { seg <- rhat[(t-N):t]; if (all(is.finite(seg))) phi[t] <- pmin(pmax(sum(wn*rev(seg)),-2.5),2.5) }
bm[, S_faith := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2 + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2]
## F4: 추세-비대칭 S (ϕ² 벌점은 ϕ<0에만 — 상승추세 무벌점)
bm[, S_asym  := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2  + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2*(phi<0)]
## F5: 하방 세미분산 S (+ 추세-비대칭 ϕ²)
bm[, S_semi  := PAPER_COEF["a"] + PAPER_COEF["d"]*sig2d + PAPER_COEF["e"]*phi + PAPER_COEF["f"]*phi^2*(phi<0)]
bm[, ym := format(Date, "%Y-%m")]
me <- bm[, .(S=last(S_faith), S_asym=last(S_asym), S_semi=last(S_semi), phi_m=last(phi)), by=ym]
setorder(me, ym)
me[, ym_next := format(as.Date(paste0(ym,"-01")) %m+% months(1), "%Y-%m")]
p <- merge(p, me[, .(realized_ym=ym_next, S_chk=S, S_asym, S_semi, phi_m)], by="realized_ym", all.x=TRUE)
setorder(p, realized_ym)
## sanity: 복제 S ≈ 기록 S_faith
chk <- p[is.finite(S_faith) & is.finite(S_chk), max(abs(S_faith - S_chk))]
cat(sprintf("    S 복제 검증 max|diff| = %.2e %s\n", chk, ifelse(chk < 1e-6, "(OK)", "(*** MISMATCH — 중단 검토 ***)")))
stopifnot(chk < 1e-4)

cat("[3] expanding past-only percentile + freq-match 임계 (canonical 복제)\n")
exp_pct <- function(x) { out <- rep(NA_real_, length(x))
  for (i in seq_along(x)) { past <- x[seq_len(i-1)]; past <- past[is.finite(past)]
    if (length(past) >= 24 && is.finite(x[i])) out[i] <- mean(past < x[i]) }
  out }
p[, pct_faith := exp_pct(S_faith)]
p[, pct_asym  := exp_pct(S_asym)]
p[, pct_semi  := exp_pct(S_semi)]
## freq-match 임계 (canonical): β_AR 분포에서 lo 레벨별 [1-cum-f, 1-cum) 구간
freq <- prop.table(table(round(p$beta_AR,2))); lo <- sort(as.numeric(names(freq))[as.numeric(names(freq)) < 0.999])
cumf <- 0; thr <- list()
for (l in lo) { f <- as.numeric(freq[as.character(l)]); if (is.na(f)) f <- 0
  thr[[length(thr)+1]] <- c(l, 1-cumf-f, 1-cumf); cumf <- cumf+f }
map_freq <- function(pp){ if(!is.finite(pp)) return(1.0)
  for (tt in thr) if (pp >= tt[2] && pp < tt[3]) return(tt[1])
  if (length(lo) && pp >= 1-cumf) return(lo[1]); 1.0 }
## 변형 매핑 함수들
map_thr <- function(pp, t1, t2){ if(!is.finite(pp)) return(1.0)
  if (pp >= t2) return(0.4); if (pp >= t1) return(0.7); 1.0 }
map_cont <- function(pp, t0){ if(!is.finite(pp)) return(1.0)
  max(0.4, min(1.0, 1 - 0.6*max(0,(pp - t0))/(1 - t0))) }

cat("[4] 변형군 구성 (13 variants + 4 controls)\n")
p[, beta_faith_repl := sapply(pct_faith, map_freq)]   # canonical 매핑 복제 (검증용)
repl_match <- p[, mean(abs(beta_faith_repl - beta_faith) < 1e-9, na.rm=TRUE)]
cat(sprintf("    β_faith 매핑 복제 일치율 = %.1f%%\n", 100*repl_match))

variants <- list()
## --- Controls ---
variants[["C0_incumbent_recorded"]] <- list(type="recorded")                       # 기록 convention 그대로
variants[["C1_incumbent_dE"]]       <- list(beta=p$beta_faith, r05=p$beta_R05, m4=p$m4)  # 주 baseline
variants[["C2_no_faith"]]           <- list(beta=rep(1,nrow(p)), r05=p$beta_R05, m4=p$m4)
variants[["C3_naked"]]              <- list(beta=rep(1,nrow(p)), r05=rep(1,nrow(p)), m4=rep(1,nrow(p)))
## --- F1 백분위 임계 비대칭 ---
variants[["F1a_thr80_95"]] <- list(beta=sapply(p$pct_faith, map_thr, 0.80, 0.95), r05=p$beta_R05, m4=p$m4)
variants[["F1b_thr70_90"]] <- list(beta=sapply(p$pct_faith, map_thr, 0.70, 0.90), r05=p$beta_R05, m4=p$m4)
## --- F2 연속 매핑 ---
variants[["F2a_cont60"]] <- list(beta=sapply(p$pct_faith, map_cont, 0.60), r05=p$beta_R05, m4=p$m4)
variants[["F2b_cont75"]] <- list(beta=sapply(p$pct_faith, map_cont, 0.75), r05=p$beta_R05, m4=p$m4)
## --- F3 추세 확증 (ϕ>0이면 β=1 강제) ---
b3 <- p$beta_faith; b3[is.finite(p$phi_m) & p$phi_m > 0] <- 1.0
variants[["F3_trend_gate"]] <- list(beta=b3, r05=p$beta_R05, m4=p$m4)
## --- F4 추세-비대칭 S ---
variants[["F4_S_asym"]] <- list(beta=sapply(p$pct_asym, map_freq), r05=p$beta_R05, m4=p$m4)
## --- F5 하방 세미분산 S ---
variants[["F5_S_semi"]] <- list(beta=sapply(p$pct_semi, map_freq), r05=p$beta_R05, m4=p$m4)
## --- F6 리스크-on 오버라이드 (⚠ max-cash 결합 FALSIFIED 인접 — 메커니즘 차이 검증 목적) ---
variants[["F6a_riskon_ovr30"]] <- list(beta=p$beta_faith, r05=p$beta_R05, m4=p$m4, override_pct=0.30)
variants[["F6b_riskon_ovr20"]] <- list(beta=p$beta_faith, r05=p$beta_R05, m4=p$m4, override_pct=0.20)
## --- F7 감속 2개월 확증 (상향 즉시, 하향 2연속 요구) ---
b7 <- pmax(p$beta_faith, shift(p$beta_faith, 1, fill=1.0))
variants[["F7_derisk_confirm"]] <- list(beta=b7, r05=p$beta_R05, m4=p$m4)
## --- F8 방어층 완화 ---
variants[["F8a_r05_floor70"]] <- list(beta=p$beta_faith, r05=pmax(p$beta_R05, 0.7), m4=p$m4)
variants[["F8b_m4_floor85"]]  <- list(beta=p$beta_faith, r05=p$beta_R05, m4=pmax(p$m4, 0.85))
## --- F9 결합 최유망 (F4 신호 × F7 전이 — 사전등록 결합 1건만) ---
b9 <- pmax(sapply(p$pct_asym, map_freq), shift(sapply(p$pct_asym, map_freq), 1, fill=1.0))
variants[["F9_asym_confirm"]] <- list(beta=b9, r05=p$beta_R05, m4=p$m4)

cat("[5] 수익 시리즈 + 지표 (KOSPI anchor-window 정렬)\n")
## KOSPI 수익을 anchor window (anchor[i-1], anchor[i]] 로 정렬 (라벨 무관 정확 정렬)
bm_x <- xts(bm[[bcol]], order.by=bm$Date)
anchor <- p$anchor_date
bm_win <- rep(NA_real_, nrow(p))
for (i in 2:nrow(p)) {
  seg <- bm_x[index(bm_x) > anchor[i-1] & index(bm_x) <= anchor[i]]
  if (nrow(seg) > 0) bm_win[i] <- as.numeric(Return.cumulative(seg))
}
p[, bm_ret := bm_win]

nw_t <- function(d, lag=3) {   # paired Newey-West t (mean of diff)
  d <- d[is.finite(d)]; nn <- length(d); if (nn < 24) return(NA_real_)
  mu <- mean(d); e <- d - mu
  s0 <- sum(e^2)/nn
  for (L in 1:lag) { w <- 1 - L/(lag+1); s0 <- s0 + 2*w*sum(e[(L+1):nn]*e[1:(nn-L)])/nn }
  mu / sqrt(s0/nn)
}

calc_row <- function(ret, expo, dE, name, ret_base=NULL) {
  x <- xts(ret, order.by=p$anchor_date)
  sr  <- as.numeric(table.AnnualizedReturns(x, scale=12)[3,1])
  cag <- as.numeric(Return.annualized(x, scale=12))
  mdd <- as.numeric(maxDrawdown(x))
  cal <- as.numeric(CalmarRatio(x, scale=12))
  srt <- as.numeric(SortinoRatio(x, MAR=0))
  ud  <- tryCatch(UpDownRatios(x, xts(p$bm_ret, order.by=p$anchor_date), method="Capture", side="Up"), error=function(e) NA)
  dd  <- tryCatch(UpDownRatios(x, xts(p$bm_ret, order.by=p$anchor_date), method="Capture", side="Down"), error=function(e) NA)
  y26 <- as.numeric(Return.cumulative(x[format(index(x),"%Y")=="2026"]))
  bm26<- as.numeric(Return.cumulative(xts(p$bm_ret, order.by=p$anchor_date)[format(p$anchor_date,"%Y")=="2026"]))
  pt  <- if (!is.null(ret_base)) nw_t(ret - ret_base) else NA_real_
  data.table(variant=name, n_months=sum(is.finite(ret)), SR=round(sr,3), CAGR=round(cag,4),
             MDD=round(mdd,4), Calmar=round(cal,3), Sortino_m=round(srt,4),
             up_capture=round(as.numeric(ud),3), down_capture=round(as.numeric(dd),3),
             ret_2026=round(y26,4), bm_2026=round(bm26,4),
             avg_expo=round(mean(expo, na.rm=TRUE),3), full_expo_share=round(mean(expo > 0.999, na.rm=TRUE),3),
             turnover_dE=round(sum(dE, na.rm=TRUE),2), paired_nw_t_vs_C1=round(pt,2))
}

results <- list(); series <- data.table(realized_ym=p$realized_ym, anchor_date=p$anchor_date)
## C1 baseline 먼저 (paired t 기준)
mk_ret <- function(v) {
  if (!is.null(v$type) && v$type=="recorded") {
    E <- p$beta_R05 * p$beta_faith * p$m4
    dE <- abs(p$beta_faith - shift(p$beta_faith,1,fill=1)) + abs(p$beta_R05 - shift(p$beta_R05,1,fill=1))
    return(list(ret=p$ret_L5_faith, E=E, dE=dE))
  }
  E <- v$r05 * v$m4 * v$beta
  if (!is.null(v$override_pct)) E <- ifelse(is.finite(p$pct_faith) & p$pct_faith <= v$override_pct, pmax(E, 1.0), E)
  dE <- abs(E - shift(E, 1, fill=1.0))
  list(ret = E * p$ret_orig - dE*COST, E=E, dE=dE)
}
base <- mk_ret(variants[["C1_incumbent_dE"]])
for (nm in names(variants)) {
  z <- mk_ret(variants[[nm]])
  results[[nm]] <- calc_row(z$ret, z$E, z$dE, nm, ret_base=if(nm=="C1_incumbent_dE") NULL else base$ret)
  series[[paste0("ret_", nm)]] <- z$ret
  series[[paste0("E_", nm)]]   <- z$E
}
res <- rbindlist(results)
setorder(res, -SR)

cat("[6] 연도별 수익 테이블 (bull 참여 진단)\n")
yr_tbl <- data.table(year=format(p$anchor_date, "%Y"))
for (nm in c("C1_incumbent_dE","C3_naked","F1a_thr80_95","F3_trend_gate","F4_S_asym","F5_S_semi","F7_derisk_confirm","F9_asym_confirm")) {
  x <- xts(series[[paste0("ret_",nm)]], order.by=p$anchor_date)
  yv <- apply.yearly(x, Return.cumulative)
  tmp <- data.table(year=format(index(yv),"%Y"), v=round(as.numeric(yv),4)); setnames(tmp,"v",nm)
  yr_tbl <- merge(unique(yr_tbl), tmp, by="year", all.x=TRUE)
}
bx <- apply.yearly(xts(p$bm_ret, order.by=p$anchor_date), Return.cumulative)
yr_tbl <- merge(yr_tbl, data.table(year=format(index(bx),"%Y"), KOSPI=round(as.numeric(bx),4)), by="year", all.x=TRUE)

cat("\n================ RESULTS (SR 내림차순) ================\n")
print(res, nrow=99)
cat("\n================ 연도별 (bull 참여) ================\n")
print(yr_tbl, nrow=30)

fwrite(res, file.path(OUT_DIR, "offense_battery_results.csv"))
fwrite(yr_tbl, file.path(OUT_DIR, "offense_battery_yearly.csv"))
fwrite(series, file.path(OUT_DIR, "offense_battery_series.csv"))
meta <- list(date=format(Sys.Date()), n_trials=length(variants)-4L,  # controls 제외
  selection_type="sweep", cost_convention="|dE|x15bps (C0만 기록 convention)",
  metric_type="backtested(panel-overlay)", pit="canonical lag 구조 상속(S 월말→익월, expanding past-only pct)",
  base_panel="2-2 period_returns_layer5_faith.csv 269m", note="F6은 max-cash-FALSIFIED 인접 — 메커니즘 차이 검증 목적 명시")
write_json(meta, file.path(OUT_DIR, "offense_battery_meta.json"), auto_unbox=TRUE, pretty=TRUE)
cat(sprintf("\n[DONE] 산출: %s (results/yearly/series CSV + meta JSON)\n", OUT_DIR))
