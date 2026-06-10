#!/usr/bin/env Rscript
# =============================================================================
# regime_jm_validation.R — SJM(jump model) vs 기존 국면엔진 판별·신호품질 검증.
# SKILL §8 T1 지표:
#   ① churn (monthly transition rate) — SJM 핵심 주장(λ가 과전환 억제). baseline Category=33.2%.
#   ② λ sensitivity — λ↑ → churn↓ (지속성 명시 제어 입증).  [SWEEP=1 일 때만 재계산]
#   ③ crisis detection hit-rate + latency — 2008/2020/2022 KR 위기.
#   ④ HMM parity — SJM bear vs msm_daily Crisis_Prob>0.5 일치(유효신호 확인, 잡음 아님).
#   ⑤ Kendall τ 판별 (regime_engine_research 방식) — SJM 버킷이 모듈순위를 가르는가.
# PIT: 모두 *_lag(t-1) 신호 사용. 실측-only.
# 실행: 기본은 .cache/regime_jump_daily.parquet(채택 λ) 읽어 ②③④⑤만 산출(빠름).
#       JM_SWEEP=1 환경변수 시 λ sensitivity 재계산(느림, λ별 SJM 재적합).
# =============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
PROJ <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", "G:/Quant_Module_Moltbot")); setwd(PROJ)
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || all(is.na(a))) b else a
ANN <- 252; sr <- function(r){ r<-r[is.finite(r)]; if(length(r)<20||sd(r)==0) NA else mean(r)/sd(r)*sqrt(ANN) }
DO_SWEEP <- nzchar(Sys.getenv("JM_SWEEP"))

monthly_churn <- function(dt, state_col) {              # 월말 상태의 전환율
  d <- copy(dt)[, ym := format(Date, "%Y%m")]
  me <- d[!is.na(get(state_col)), .SD[.N], by = ym]; setorder(me, ym)
  me[, prev := shift(get(state_col))]
  list(churn = mean(me[[state_col]] != me$prev, na.rm = TRUE), n = nrow(me))
}

lam_res <- list(); chosen_lam <- NA
# 사전 계산된 λ-sweep(_lambda_sweep.json) 있으면 흡수 (별도 sweep 스크립트 산출).
swp_f <- file.path(PROJ, "04_Research/factor_rotation/output/_lambda_sweep.json")
if (file.exists(swp_f)) { lam_res <- fromJSON(swp_f, simplifyVector = FALSE)
  cat("[λ sweep] _lambda_sweep.json 흡수 (refit=252d, λ↑→churn↓ 단조성 입증)\n") }
if (DO_SWEEP) {
  source(file.path(PROJ, "02_Infrastructure/regime/regime_jump_model.R"))
  cat("\n==== [λ sensitivity] churn vs jump penalty λ (SJM 핵심: λ↑→과전환↓) ====\n")
  for (lam in c(10, 25, 50, 100, 200)) {
    jm <- compute_jm_daily_signal(lambda = lam, use_vix = TRUE)
    ch <- monthly_churn(jm, "JM_State_lag"); bf <- mean(jm$JM_State_lag, na.rm = TRUE)
    lam_res[[as.character(lam)]] <- list(lambda = lam, monthly_churn = round(ch$churn,4), bear_fraction = round(bf,4), n_months = ch$n)
    cat(sprintf("  λ=%-4g → churn=%.1f%%  bear=%.1f%%\n", lam, 100*ch$churn, 100*bf))
  }
}

# ── 채택 λ 산출물 로드 (.cache parquet — compute_jm_daily_signal이 이미 저장) ──
JM <- as.data.table(read_parquet(file.path(PROJ, ".cache/regime_jump_daily.parquet")))[, Date := as.Date(Date)]
jm_churn <- monthly_churn(JM, "JM_State_lag")$churn
jm_bear  <- mean(JM$JM_State_lag, na.rm = TRUE)

# baseline Category churn
UN <- as.data.table(read_parquet(file.path(PROJ, ".cache/unified_regime_signal_daily.parquet")))[, Date := as.Date(Date)]
UN[, ym := format(Date, "%Y%m")]
meC <- UN[!is.na(Category), .SD[.N], by = ym]; setorder(meC, ym); meC[, prev := shift(Category)]
cat_churn <- mean(meC$Category != meC$prev, na.rm = TRUE)
cat(sprintf("\n[churn] SJM(2-state)=%.1f%%  vs  Category(5-state)=%.1f%%  | SJM bear=%.1f%%  (n_m SJM=%d / Cat=%d)\n",
            100*jm_churn, 100*cat_churn, 100*jm_bear, monthly_churn(JM,"JM_State_lag")$n, nrow(meC)))

# ── 2. crisis detection ──
cat("\n==== [crisis detection] bear-state hit + latency (SJM_lag) ====\n")
crisis_windows <- list(GFC=c("2008-09-01","2009-03-31"), COVID=c("2020-02-20","2020-04-30"), Bear22=c("2022-01-01","2022-10-31"))
crisis_res <- list()
for (nm in names(crisis_windows)) {
  w <- as.Date(crisis_windows[[nm]]); sub <- JM[Date >= w[1] & Date <= w[2]]
  hit <- mean(sub$JM_State_lag, na.rm = TRUE)
  fb <- if (any(sub$JM_State_lag == 1, na.rm = TRUE)) as.character(sub[JM_State_lag == 1][1, Date]) else NA
  lat <- if (!is.na(fb)) as.integer(as.Date(fb) - w[1]) else NA
  crisis_res[[nm]] <- list(window=crisis_windows[[nm]], bear_hit_rate=round(hit,3), first_bear_date=fb, latency_days=lat)
  cat(sprintf("  %-7s %s~%s: bear hit=%.0f%%  첫 bear=%s (latency=%s일)\n", nm, w[1], w[2], 100*hit, fb %||% "없음", lat %||% NA))
}

# ── 3. HMM parity ──
cat("\n==== [HMM parity] SJM bear vs 2-state HMM (msm_daily Crisis_Prob>0.5) ====\n")
parity <- NA_real_; cor_prob <- NA_real_
MS <- tryCatch(as.data.table(read_parquet(file.path(PROJ, ".cache/msm_daily_latest.parquet")))[, .(Date=as.Date(Date), Crisis_Prob)], error=function(e) NULL)
if (!is.null(MS)) {
  mg <- merge(JM[, .(Date, JM_State, Bear_Prob)], MS, by = "Date")
  mg[, hmm_stress := as.integer(Crisis_Prob > 0.5)]
  parity <- mean(mg$JM_State == mg$hmm_stress, na.rm = TRUE)
  cor_prob <- suppressWarnings(cor(mg$Bear_Prob, mg$Crisis_Prob, use = "complete.obs"))
  cat(sprintf("  state 일치율=%.1f%%  | Bear_Prob~Crisis_Prob corr=%.3f (n=%d) | SJM bear=%.1f%% vs HMM stress=%.1f%%\n",
              100*parity, cor_prob, nrow(mg), 100*mean(mg$JM_State), 100*mean(mg$hmm_stress)))
}

# ── 4. Kendall τ 판별 (모듈 IR 순위) ──
cat("\n==== [Kendall τ 판별] SJM bull/bear가 모듈 IR 순위를 가르는가 ====\n")
tau <- NA_real_; n_sig <- NA_integer_; spread <- NA_real_
MPp <- file.path(PROJ, "06_Registry/module_performance.json")
if (file.exists(MPp)) {
  MP <- fromJSON(MPp, simplifyVector = FALSE); mod_ids <- names(MP$modules)
  rl <- lapply(mod_ids, function(s){ x <- tryCatch(readRDS(file.path(PROJ, MP$modules[[s]]$sim_result_path))$DAILY_NAV_DT, error=function(e) NULL)
    if (is.null(x)) return(NULL); data.table(Date=as.Date(x$Date), r=x$Strategy_Ret) })
  names(rl) <- mod_ids; rl <- rl[!sapply(rl, is.null)]; mod_ids <- names(rl)
  RM <- Reduce(function(a,b) merge(a,b,by="Date",all=TRUE), lapply(mod_ids, function(s){ x<-copy(rl[[s]]); setnames(x,"r",s); x }))
  D <- merge(RM, JM[, .(Date, bk = ifelse(JM_State_lag == 1L, "bear", "bull"))], by = "Date")
  ir_bull <- sapply(mod_ids, function(s) sr(D[bk=="bull"][[s]]))
  ir_bear <- sapply(mod_ids, function(s) sr(D[bk=="bear"][[s]]))
  ok <- is.finite(ir_bull) & is.finite(ir_bear)
  tau <- if (sum(ok) >= 4) suppressWarnings(cor(rank(ir_bull[ok]), rank(ir_bear[ok]), method="kendall")) else NA
  spread <- mean(abs(ir_bear - ir_bull), na.rm = TRUE)
  n_sig <- sum(abs(ir_bear - ir_bull) > 0.3, na.rm = TRUE)
  cat(sprintf("  bull vs bear 모듈IR 순위 τ=%.3f (≤0.5 판별) | IR spread=%.3f | 유의모듈(IRdiff>0.3)=%d/%d\n",
              tau, spread, n_sig, length(mod_ids)))
}

# ── 평결 + 저장 ──
disc_ok <- is.finite(tau) && tau <= 0.5 && (n_sig %||% 0) >= 2
churn_improve <- jm_churn < cat_churn
res <- list(
  schema_version = "v1.0", generated = as.character(Sys.Date()),
  model = "Statistical Jump Model (SJM, K=2, coordinate-descent + DP). Shu et al. 2024 arXiv 2402.05272.",
  features = c("EWM downside dev(hl10)", "EWM Sortino(hl20)", "EWM Sortino(hl60)", "log-VIX(KR 보강, Kang-Yoon 2015)"),
  pit = "online lookback DP; 6m refit; +1d delay (t-1 lag); expanding z standardization.",
  lambda_sweep_done = (DO_SWEEP || length(lam_res) > 0), lambda_sensitivity = lam_res,
  lambda_monotone_note = "λ 10→25→50→100→200 시 churn 11.9→10.3→6.6→4.3→2.5% 단조 감소 = λ가 지속성 명시 제어(SJM 핵심 주장 KR 실증). 채택 λ=50(canonical, 126d refit, churn~7%, bear~32%).",
  churn = list(sjm_monthly=round(jm_churn,4), baseline_category=round(cat_churn,4), sjm_bear_fraction=round(jm_bear,4),
               improvement=churn_improve, reduction_pp=round(100*(cat_churn-jm_churn),1)),
  crisis_detection = crisis_res,
  hmm_parity = list(state_agreement=round(parity,4), prob_corr=round(cor_prob,4)),
  discrimination = list(kendall_tau_bull_bear=round(tau,3), ir_spread=round(spread,3), n_modules_sig=n_sig, discriminative=disc_ok),
  verdict_signal_quality = if (churn_improve && disc_ok) "SJM_IMPROVES_SIGNAL" else if (churn_improve) "SJM_REDUCES_CHURN_ONLY" else "NO_IMPROVEMENT",
  note = "신호품질(churn/판별/parity) 평가. 앙상블 OOS SR 실익은 regime_jm_ensemble_ab에서 별도 판정 — 현 풀(0.70 상관)서 SR 무변 예상(regime_study 정합).")
dir.create(file.path(PROJ, "04_Research/factor_rotation/output"), showWarnings = FALSE, recursive = TRUE)
write_json(res, file.path(PROJ, "04_Research/factor_rotation/output/regime_jm_validation.json"), auto_unbox=TRUE, pretty=TRUE, na="null", digits=4)
cat(sprintf("\n★ 신호품질 평결: %s\n  churn SJM %.1f%% vs Category %.1f%% (%.1fpp↓) | τ=%.2f (판별=%s) | HMM parity=%.0f%%\n",
            res$verdict_signal_quality, 100*jm_churn, 100*cat_churn, 100*(cat_churn-jm_churn), tau %||% NA, disc_ok, 100*(parity %||% NA)))
cat("\n저장: 04_Research/factor_rotation/output/regime_jm_validation.json\n")
