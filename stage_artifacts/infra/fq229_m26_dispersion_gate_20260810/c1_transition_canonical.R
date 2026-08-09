## =============================================================================
## FQ-229 (C) — 전이 측정: canonical top-25 EW long-only 15bps
##  arm0  M26 단독            (FQ-161 +1.544 parity)
##  arm0g M26 단독 x G4~      (★구조 점검: 양의 스칼라 랭킹 불변 ⇒ no-op 이어야 함)
##  arm1  EW 4팩터 복합        (기저)
##  arm2~5 복합 + M26 다리에 G1~G4 (채택 소비면 = 복합 내 상대 가중)
## metric_type: canonical_screen (cap-w HARD 권위) + canonical_screen_diag (dual-basis)
## ★basis 정합: 1.544 는 *M26 단독* 값. 복합 arm 과 나란히 놓고 "움직였다" 로 읽지 않는다.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
say <- function(fmt, ...) { cat(sprintf(paste0("[c1] ", fmt, "\n"), ...)); flush.console() }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
set.seed(20260813L); NWLAG <- 3L
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
nw_t <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

## ---------------------------------------------------------------- 입력
A <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); A[, Date := as.Date(Date)]
say("★입력 실측: alpha_scores %d행 · %d개월 · 관측단위 (Date x Ticker)", nrow(A), uniqueN(A$Date))
G <- fread(file.path(OUT, "b2_gate_multipliers.csv"))
A <- merge(A, G, by = "signal_ym"); setorder(A, Date, Ticker)
say("게이트 병합 후 %d행 · 게이트 결측 %d", nrow(A), sum(!is.finite(A$G1_n)))

RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
size_dt <- RAWME[, .(Date, Ticker, Size)]
say("수익 %d행 · 벤치 %d행 · 유동성 %d행", nrow(ret), nrow(bench), nrow(liq))

## 복합 구성 요소의 실효 가중 (raw z 열의 월평균 sd) — EW 라벨의 실제 의미를 드러낸다
sds <- A[, lapply(.SD, sd), by = signal_ym, .SDcols = c("C01_SUE","C02_EPS_Chg_1m","C04_ESBR","M26_Revenue_Mom")]
say("★복합 구성요소 월별 sd 평균: %s ⇒ 'EW' 는 동일-sd 가중이 아니라 열 스케일 그대로의 합이다",
    paste(sprintf("%s %.3f", names(sds)[-1], sapply(sds[, -1], mean)), collapse = " · "))

## ---------------------------------------------------------------- arm 정의
mkscore <- function(expr_col) A[, .(Date, Ticker, score = eval(expr_col, .SD)), .SDcols = names(A)]
ARMS <- list(
  list(tag = "arm0_M26_alone",     s = A[, .(Date, Ticker, score = M26_Revenue_Mom)]),
  list(tag = "arm0g_M26_x_G4",     s = A[, .(Date, Ticker, score = G4_n * M26_Revenue_Mom)]),
  list(tag = "arm1_EW_composite",  s = A[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + M26_Revenue_Mom)]),
  list(tag = "arm2_comp_G1",       s = A[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + G1_n * M26_Revenue_Mom)]),
  list(tag = "arm3_comp_G2",       s = A[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + G2_n * M26_Revenue_Mom)]),
  list(tag = "arm4_comp_G3",       s = A[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + G3_n * M26_Revenue_Mom)]),
  list(tag = "arm5_comp_G4",       s = A[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + G4_n * M26_Revenue_Mom)]))

runone <- function(S, tag) {
  t0 <- Sys.time()
  r <- canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15,
                           liq_dt = liq, liq_min = 2e8,
                           run_id = paste0("FQ229_", tag), strategy_id = paste0("FQ229_", tag),
                           diag_dual_basis = TRUE, size_dt = size_dt)
  say("  %-20s PORT_t %+.4f · n %s · net_SR %s · calmar %s · TO %s · (%.0fs · metric_type %s)",
      tag, r$portfolio_alpha_t_nw_lag3 %||% NA_real_, r$n_months %||% NA,
      format(round(as.numeric(r$net_sr %||% NA), 3)), format(round(as.numeric(r$calmar %||% NA), 3)),
      format(round(as.numeric(r$turnover_annual %||% NA), 3)),
      as.numeric(difftime(Sys.time(), t0, units = "secs")), r$metric_type %||% "NA")
  ew <- r$diag_ew_universe
  if (is.list(ew) && !isFALSE(ew$available))
    say("      [dual-basis] EW-유니버스 PORT_t %s · post2017 t %s",
        format(round(as.numeric(ew$portfolio_alpha_t_nw_lag3 %||% NA), 3)),
        format(round(as.numeric(ew$post2017_t_nw_lag3 %||% NA), 3)))
  r
}
say("================ canonical 실행 (top-25 EW · 15bps · liq 2e8) ================")
RES <- lapply(ARMS, function(a) runone(a$s, a$tag)); names(RES) <- sapply(ARMS, function(a) a$tag)

## ---------------------------------------------------------------- 판정
say("================ 판정 ================")
pt <- sapply(RES, function(r) r$portfolio_alpha_t_nw_lag3 %||% NA_real_)
say("★arm0 M26 단독 PORT_t %+.4f · FQ-161 기록 +1.544 · |Δ| %.4f ⇒ %s",
    pt[["arm0_M26_alone"]], abs(pt[["arm0_M26_alone"]] - 1.544),
    if (abs(pt[["arm0_M26_alone"]] - 1.544) < 0.01) "parity PASS" else "★차이 — 기록 대비 확인 필요")
noop_d <- abs(pt[["arm0g_M26_x_G4"]] - pt[["arm0_M26_alone"]])
say("★구조 점검 (no-op): M26 단독 %+.6f vs M26 x G4~ %+.6f · |Δ| %.2e ⇒ %s",
    pt[["arm0_M26_alone"]], pt[["arm0g_M26_x_G4"]], noop_d,
    if (noop_d < 1e-9) "완전 일치 — 단일 팩터 게이팅은 랭킹 불변 no-op (구조적 사실)" else "★불일치 — 프레임 결함 의심")

## paired t + ΔIR (arm1 대비, 동월)
pr <- function(tag) { p <- as.data.table(RES[[tag]]$period_returns); p[, act := ret_net - benchmark_ret]; p }
base <- pr("arm1_EW_composite")
CMP <- rbindlist(lapply(c("arm2_comp_G1","arm3_comp_G2","arm4_comp_G3","arm5_comp_G4"), function(tg) {
  g <- pr(tg); m <- merge(base[, .(date, act_b = act)], g[, .(date, act_g = act)], by = "date")
  d <- m$act_g - m$act_b
  ir_b <- mean(m$act_b)/sd(m$act_b)*sqrt(12); ir_g <- mean(m$act_g)/sd(m$act_g)*sqrt(12)
  data.table(arm = tg, n_common = nrow(m), port_t = pt[[tg]], port_t_base = pt[["arm1_EW_composite"]],
             delta_port_t = pt[[tg]] - pt[["arm1_EW_composite"]],
             mean_diff_bp = mean(d)*1e4, paired_t_nw3 = nw_t(d),
             ir_base = ir_b, ir_gated = ir_g, delta_ir = ir_g - ir_b,
             sign_agree = sign(ir_g - ir_b) == sign(nw_t(d)))
}))
for (i in seq_len(nrow(CMP))) with(CMP[i], say(
  "  %-16s PORT_t %+.4f (Δ %+.4f) · 월평균 차 %+.2fbp · paired t(NW3) %+.3f · ΔIR %+.4f · 부호일치 %s",
  arm, port_t, delta_port_t, mean_diff_bp, paired_t_nw3, delta_ir, sign_agree))
say("★부호 일치 규약: 불일치 arm = %s",
    { s <- CMP[sign_agree == FALSE, arm]; if (length(s)) paste(s, collapse=" / ") else "없음" })
say("★전이 판정: 복합 게이트 arm 중 |paired t| >= 2.0 인 arm = %s · HARD 2.95 도달 arm = %s",
    { s <- CMP[abs(paired_t_nw3) >= 2, arm]; if (length(s)) paste(s, collapse=" / ") else "0건" },
    { s <- CMP[port_t >= 2.95, arm]; if (length(s)) paste(s, collapse=" / ") else "0건" })

fwrite(data.table(arm = names(pt), port_t = as.numeric(pt)), file.path(OUT, "c1_arm_port_t.csv"))
fwrite(CMP, file.path(OUT, "c1_paired_comparison.csv"))
saveRDS(list(pt = pt, CMP = CMP, noop_delta = noop_d,
             sds = sapply(sds[, -1], mean)), file.path(OUT, "c1_results.rds"))
say("저장 완료 -> %s", OUT)
say("★★[C 요약] arm0 %+.3f (parity 1.544) · no-op |Δ| %.1e · 복합기저 %+.3f · 게이트 최대 %+.3f · HARD 2.95 도달 0 여부 %s",
    pt[["arm0_M26_alone"]], noop_d, pt[["arm1_EW_composite"]], max(CMP$port_t), all(CMP$port_t < 2.95))
