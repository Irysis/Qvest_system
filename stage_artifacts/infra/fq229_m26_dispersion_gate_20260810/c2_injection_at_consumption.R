## =============================================================================
## FQ-229 (C2) — 위반 주입을 **소비면에서** 건다 (PREREG §7-2)
##  c1 이 남긴 질문: arm5(복합+G4) PORT_t +3.0625 는 게이트 덕인가, 자유도인가?
##  귀무: 같은 승수 다중집합을 **무작위 월에 재배정**(분산 연결만 파괴, 노출분포는 완전 보존)
##  → ΔPORT_t / paired t 의 귀무분포에서 관측치 백분위.
## metric_type: canonical_screen_diag (귀무분포) · 관측 arm 은 canonical_screen.
## =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT); setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/infra/fq229_m26_dispersion_gate_20260810")
SRC <- file.path(ROOT, "stage_artifacts/WT_D20260808_002")
say <- function(fmt, ...) { cat(sprintf(paste0("[c2] ", fmt, "\n"), ...)); flush.console() }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
set.seed(20260815L); NWLAG <- 3L; B_INJ <- 250L
source("02_Infrastructure/config.R")
source("02_Infrastructure/ramp/factor_validation.R")
source("02_Infrastructure/contracts/canonical_screen_bt.R")
nw_t <- function(x, lag = NWLAG) { x <- x[is.finite(x)]; n <- length(x); if (n < 20L) return(NA_real_)
  m <- mean(x); e <- x - m; s <- sum(e^2)/n
  for (l in 1:lag) s <- s + 2*(1-l/(lag+1))*sum(e[(l+1):n]*e[1:(n-l)])/n; m/sqrt(s/n) }

A <- as.data.table(read_parquet(file.path(SRC, "alpha_scores.parquet"))); A[, Date := as.Date(Date)]
G <- fread(file.path(OUT, "b2_gate_multipliers.csv"))
say("★입력 실측: 패널 %d행 · 게이트 %d개월", nrow(A), nrow(G))
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date","Ticker","Close","Vol","Size","K200","KQ150")))
RAW[, Date := as.Date(Date)]
ME <- sort(RAW[, .(Date = max(Date)), by = .(ym = format(Date, "%Y-%m"))]$Date)
RAWME <- RAW[Date %in% ME]; rm(RAW); gc(FALSE)
fwd <- build_monthly_forward_returns(RAWME, ME)
ret <- fwd$returns_dt; bench <- fwd$bench_dt; liq <- fwd$liq_dt
size_dt <- RAWME[, .(Date, Ticker, Size)]

MAP <- unique(A[, .(signal_ym, Date)])[order(Date)]
run_pt <- function(mvec, tag) {
  gm <- data.table(signal_ym = MAP$signal_ym, mm = mvec)
  AA <- merge(A, gm, by = "signal_ym")
  S <- AA[, .(Date, Ticker, score = C01_SUE + C02_EPS_Chg_1m + C04_ESBR + mm * M26_Revenue_Mom)]
  r <- canonical_screen_bt(S, ret, bench, top_n = 25L, cost_bps_oneway = 15, liq_dt = liq, liq_min = 2e8,
                           run_id = tag, strategy_id = tag, diag_dual_basis = FALSE, size_dt = size_dt)
  p <- as.data.table(r$period_returns); p[, act := ret_net - benchmark_ret]
  list(pt = r$portfolio_alpha_t_nw_lag3 %||% NA_real_, act = p[, .(date, act)])
}
BASE <- run_pt(rep(1, nrow(MAP)), "base_EW")
say("기저(복합 EW) PORT_t %+.4f · n %d", BASE$pt, nrow(BASE$act))
stat_vs_base <- function(o) { m <- merge(BASE$act[, .(date, ab = act)], o$act[, .(date, ag = act)], by = "date")
  d <- m$ag - m$ab
  ir_b <- mean(m$ab)/sd(m$ab)*sqrt(12); ir_g <- mean(m$ag)/sd(m$ag)*sqrt(12)
  list(d_pt = o$pt - BASE$pt, ptrd = nw_t(d), d_ir = ir_g - ir_b) }

say("================ 귀무분포 (승수 다중집합 무작위 재배정, B=%d) ================", B_INJ)
RESN <- list()
for (gname in c("G1_n", "G4_n")) {
  mv <- G[[gname]]
  obs <- stat_vs_base(run_pt(mv, paste0("obs_", gname)))
  t0 <- Sys.time()
  nd <- rbindlist(lapply(seq_len(B_INJ), function(b) {
    s <- stat_vs_base(run_pt(sample(mv), sprintf("null_%s_%03d", gname, b)))
    data.table(d_pt = s$d_pt, ptrd = s$ptrd, d_ir = s$d_ir) }))
  el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  say("--- %s (관측 ΔPORT_t %+.4f · paired t %+.3f · ΔIR %+.4f) · 귀무 %d회 %.0fs ---",
      gname, obs$d_pt, obs$ptrd, obs$d_ir, B_INJ, el)
  say("   ΔPORT_t 귀무: 중앙 %+.4f · 5%%~95%% [%+.4f, %+.4f] ⇒ p_우측 %.4f (백분위 %.1f%%)",
      median(nd$d_pt), quantile(nd$d_pt,.05), quantile(nd$d_pt,.95), mean(nd$d_pt >= obs$d_pt), mean(nd$d_pt <= obs$d_pt)*100)
  say("   paired t 귀무: 중앙 %+.3f · 5%%~95%% [%+.3f, %+.3f] ⇒ p_우측 %.4f",
      median(nd$ptrd), quantile(nd$ptrd,.05), quantile(nd$ptrd,.95), mean(nd$ptrd >= obs$ptrd))
  say("   ΔIR      귀무: 중앙 %+.4f · 5%%~95%% [%+.4f, %+.4f] ⇒ p_우측 %.4f",
      median(nd$d_ir), quantile(nd$d_ir,.05), quantile(nd$d_ir,.95), mean(nd$d_ir >= obs$d_ir))
  say("   ★판정: %s", if (mean(nd$d_pt >= obs$d_pt) < 0.05 && mean(nd$ptrd >= obs$ptrd) < 0.05)
    "무작위 재배정으로는 재현 안 됨 — 개선이 분산 연결에 귀속" else
    "★무작위 재배정으로도 흔히 재현 — 개선은 게이트가 아니라 자유도(월별 가중 흔들기) 산물")
  RESN[[gname]] <- list(obs = obs, nd = nd)
  fwrite(nd, file.path(OUT, sprintf("c2_null_%s.csv", gname)))
}
saveRDS(RESN, file.path(OUT, "c2_results.rds"))
say("저장 완료 -> %s", OUT)
say("★★[C2 요약] G1 ΔPORT_t p %.4f / paired t p %.4f · G4 ΔPORT_t p %.4f / paired t p %.4f",
    mean(RESN$G1_n$nd$d_pt >= RESN$G1_n$obs$d_pt), mean(RESN$G1_n$nd$ptrd >= RESN$G1_n$obs$ptrd),
    mean(RESN$G4_n$nd$d_pt >= RESN$G4_n$obs$d_pt), mean(RESN$G4_n$nd$ptrd >= RESN$G4_n$obs$ptrd))
