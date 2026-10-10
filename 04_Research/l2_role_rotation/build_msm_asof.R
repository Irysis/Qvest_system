#==============================================================================
# build_msm_asof.R — MSM(Calvet-Fisher, k̄=10) 위기확률의 as-of 판 (PIT C1 수리판 · 엔진 무수정)
#
# 왜: 운영 .cache/msm_daily_latest.parquet 의 생산자는 04_Research/regime_comparison/msm_update.R
#   (설계안 §2.2 가 적은 "2-state HMM · 30일 재적합"이 아니다 — 그것은 daily_refresh 의 폴백 msm_daily_refit.R).
#   msm_update.R 의 Hamilton 필터는 전방(인과)이고 디민도 2026-08-13 에 expanding 으로 수리됐으나, 모수 4개
#   (m0·sigma·b·gamma_1)는 05_Production/.../K_Fractal_Master_2026-01-20.xlsx 의 **전기간 MLE**(Last_Trained 2026-01-18 ·
#   표본 1990-01-04~2026-01-16)를 핀으로 쓴다 → 2005~2015 의 값이 2026 년까지의 자료로 정한 모수를 쓴다(C1).
#   위기 상태 정의(s > sigma)도 그 전기간 sigma 에 묶인다.
# 수리(이 드라이버 안에서만): 같은 모형·같은 필터·같은 디민·같은 목적함수(MSM.R estimate_msm_windows 의 음의 우도·벌점 경계·
#   3 초기점)를 **refit 일 r 이하 자료로만** 매년 말 재추정 → 블록 [r_k, r_{k+1}) 의 위기확률은 θ_k 로 전방 필터.
#   (운영 NM maxit 1000 그대로 돌린 v0 은 PC3 실패 — work/msm_asof_fit_v0_prodNM.json 보존. 아래 fit_msm 주석)
#   t 의 값은 r_1..r_t 와 θ(r_k <= t)만의 함수 = PIT.
# 양성 대조(PC): PC1 고속 커널 == 운영 조밀 커널(같은 모수 경로 일치) · PC2 저장 캐시 == 운영 커널 재계산 ·
#   PC3 전기간 MLE ~ 핀 모수(같은 자료에서 우리 최적점 음의 우도 <= 핀 모수 음의 우도) · PC4 운영 커널 접두 불변.
# 출력: work/msm_asof_daily.parquet (Date, Crisis_Prob_asof, Vol_asof, fit_date) · work/msm_asof_fit.json
# 실행: cd 04_Research/l2_role_rotation ; Rscript --no-save -e 'source("build_msm_asof.R")'
#==============================================================================
source("lib_mc1.R")
suppressPackageStartupMessages(library(parallel))
t_start <- Sys.time()
K_BAR <- 10L                                     # msm_update.R extract_msm_path(k_bar = 10L) 그대로
bm <- load_bm()
RT <- msm_returns(bm)                            # Date, r_raw, r(expanding demean)
pin_j <- fromJSON(file.path(ROOT, "02_Infrastructure/ops/msm_param_pin.json"))
pin <- unlist(pin_j$params)[c("m0", "sigma", "b", "gamma_1")]
fk <- fast_msm_kernel()
pk <- prod_msm_kernel()
out <- list(script = "04_Research/l2_role_rotation/build_msm_asof.R", started_at = now_kst(),
            inputs = list(benchmark = file_sig(".cache/benchmark.parquet"),
                          msm_cache = file_sig(".cache/msm_daily_latest.parquet"),
                          param_pin = file_sig("02_Infrastructure/ops/msm_param_pin.json"),
                          producer = file_sig("04_Research/regime_comparison/msm_update.R")),
            pinned_params = as.list(pin), pinned_file = pin_j$file)

# ── PC1 고속 == 운영 조밀 커널 ────────────────────────────────────────────────
pd_full <- pk$extract_msm_path(RT$r, K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]])
fd_full <- fk$msm_fast_filter(RT$r, K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]], TRUE)
pc1 <- max(abs(pd_full$CrisisProb - fd_full$crisis_prob))
stopifnot(pc1 < 1e-10)
out$PC1_fast_vs_dense_max_abs <- pc1

# ── PC2 저장 캐시 == 운영 커널 재계산(핀 모수 · 현 벤치) ──────────────────────
st <- as.data.table(read_parquet(file.path(ROOT, ".cache/msm_daily_latest.parquet"))); st[, Date := as.Date(Date)]
m2 <- merge(st[, .(Date, cp_store = Crisis_Prob)], data.table(Date = RT$Date, cp = pd_full$CrisisProb), by = "Date")
out$PC2_store_vs_recompute <- list(n_store = nrow(st), n_match = nrow(m2), max_abs = max(abs(m2$cp_store - m2$cp)),
                                   store_cols = names(st), note = "저장 열 = Date,Price,Vol_Est,Crisis_Prob (HMM_State 없음) → msm_update.R 산출(폴백 msm_daily_refit 판 아님)")

# ── PC4 운영 커널 접두 불변(필터·디민 인과성) — t 에서 자른 입력으로 재계산 ─────
pfx <- lapply(as.Date(c("2008-09-30", "2011-08-31", "2015-12-30")), function(tc) {
  bt <- bm[Date <= tc]; rt <- msm_returns(bt)
  p <- pk$extract_msm_path(rt$r, K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]])
  full <- pd_full$CrisisProb[RT$Date <= tc]
  list(cut = as.character(tc), n = length(p$CrisisProb), max_abs_vs_full = max(abs(p$CrisisProb - full)),
       value_at_cut_trunc = tail(p$CrisisProb, 1), value_at_cut_full = tail(full, 1))
})
out$PC4_prefix_invariance_prod_kernel <- pfx

# ── 추정 = MSM.R estimate_msm_windows 의 목적함수·벌점 경계·3 초기점 그대로 + 수렴 보강 ──────────────
#   1차 실행(운영 절차 그대로: 원모수 NM maxit 1000)은 PC3 에서 실패했다 — 같은 전기간 자료에서 핀 모수의 음의 우도
#   (-25661.06)보다 나쁜 점(-25659.58)에서 멈췄고, 해마다 퇴화 모드(gamma_1→0 · b≈5.5 · m0≈1.5)와 정규 모드 사이를 오갔다.
#   그래서 같은 초기점에서 (i) 경계를 R^4 로 펴는 변환 모수 NM(재시작 수렴) → (ii) BFGS 연마를 붙인다.
#   초기점에 미래 정보(핀 모수 등)를 넣지 않는다 — 3 초기점은 자료 무관(+ 창의 sd)이다.
fit_msm <- function(ret, k_bar = 10L) {
  e <- fast_msm_kernel()
  nll <- function(par) e$msm_fast_filter(ret, k_bar, par[1], par[2], par[3], par[4], FALSE)$negloglik
  inb <- function(par) par[1] > 1.001 && par[1] < 1.999 && par[2] > 0 && par[3] > 1.0 && par[4] > 0 && par[4] < 0.999
  to_th <- function(p) c(qlogis((p[1] - 1.001) / 0.998), log(p[2]), log(p[3] - 1), qlogis(p[4] / 0.999))
  to_p <- function(th) c(1.001 + 0.998 * plogis(th[1]), exp(th[2]), 1 + exp(th[3]), 0.999 * plogis(th[4]))
  obj_th <- function(th) { p <- to_p(th); if (!all(is.finite(p)) || !inb(p)) return(1e10); nll(p) }
  grids <- list(c(m0 = 1.3, sigma = sd(ret), b = 2.0, gamma_1 = 0.05),
                c(m0 = 1.4, sigma = sd(ret), b = 3.0, gamma_1 = 0.01),
                c(m0 = 1.5, sigma = sd(ret), b = 5.0, gamma_1 = 0.10))
  t0 <- Sys.time()
  one <- function(g) {
    th <- to_th(g); v <- obj_th(th); n_ev <- 0L
    for (rs in 1:8) {                                    # NM 재시작 — 개선 < 1e-7 이면 수렴
      o <- optim(th, obj_th, method = "Nelder-Mead", control = list(maxit = 3000, reltol = 1e-12))
      n_ev <- n_ev + o$counts[1]
      if (v - o$value < 1e-7) { th <- if (o$value < v) o$par else th; v <- min(v, o$value); break }
      th <- o$par; v <- o$value
    }
    b <- tryCatch(optim(th, obj_th, method = "BFGS", control = list(maxit = 500, reltol = 1e-14)), error = function(err) NULL)
    if (!is.null(b) && b$value < v) { th <- b$par; v <- b$value }
    list(par = to_p(th), value = v, evals = n_ev)
  }
  res <- lapply(grids, one)
  vals <- vapply(res, function(z) z$value, numeric(1))
  best <- res[[which.min(vals)]]
  list(par = as.list(setNames(best$par, c("m0", "sigma", "b", "gamma_1"))), negloglik = best$value,
       convergence = 0L, counts = sum(vapply(res, function(z) as.numeric(z$evals), 1)), all_values = vals,
       all_par = lapply(res, function(z) unname(z$par)), secs = as.numeric(difftime(Sys.time(), t0, units = "secs")))
}

# refit 일 = 매년 마지막 거래일(2003~2025) — 2003 은 lag-1 진단(2004-12-29)용 앞 블록
yr_last <- RT[, .(rf = max(Date)), by = .(y = as.integer(format(Date, "%Y")))][y >= 2003 & y <= 2025]
jobs <- c(lapply(seq_len(nrow(yr_last)), function(i) list(tag = paste0("asof_", yr_last$y[i]), cut = yr_last$rf[i], demean = "expanding")),
          list(list(tag = "PC3_full_expanding", cut = as.Date("2026-01-16"), demean = "expanding"),
               list(tag = "PC3_full_fullmean", cut = as.Date("2026-01-16"), demean = "fullsample")))
Sys.setenv(L2DIR_WD = L2DIR)
cl <- makeCluster(min(length(jobs), 13L))
clusterExport(cl, c("fit_msm", "RT", "K_BAR"))
clusterEvalQ(cl, { setwd(Sys.getenv("L2DIR_WD")); source("lib_mc1.R"); NULL })
fits <- parLapply(cl, jobs, function(j) {
  x <- RT[Date <= j$cut]
  ret <- if (identical(j$demean, "expanding")) x$r else (x$r_raw - mean(x$r_raw))
  f <- fit_msm(ret, K_BAR)
  c(j, list(n_obs = length(ret), first = as.character(min(x$Date)), last = as.character(max(x$Date))), f)
})
stopCluster(cl)
names(fits) <- vapply(jobs, `[[`, "", "tag")

# PC3: 같은 자료에서 핀 모수의 음의 우도 vs 우리 최적점
pc3 <- lapply(c("PC3_full_expanding", "PC3_full_fullmean"), function(tg) {
  f <- fits[[tg]]; x <- RT[Date <= f$cut]
  ret <- if (identical(f$demean, "expanding")) x$r else (x$r_raw - mean(x$r_raw))
  nl_pin <- fk$msm_fast_filter(ret, K_BAR, pin[["m0"]], pin[["sigma"]], pin[["b"]], pin[["gamma_1"]], FALSE)$negloglik
  list(tag = tg, fitted = f$par, negloglik_fitted = f$negloglik, negloglik_at_pinned = nl_pin,
       fitted_better_or_equal = f$negloglik <= nl_pin + 1e-6, convergence = f$convergence, secs = f$secs)
})
out$PC3_full_sample_mle_vs_pin <- pc3

# ── 식별 관문(2026-10-10 · AUC 계산 전 고정) ─────────────────────────────────────────────
#   v1(관문 없음 · work/msm_asof_fit_v1_unguarded.json)에서 2개 refit(2005·2011 말)이 퇴화 모드로 갔다:
#   gamma_1 ~ 0(최저주파 성분 기대 전환 간격 2/gamma_1 > 2e5 거래일 ≈ 800년 = 표본 안에서 얼어붙은 성분 → 비에르고딕)
#   → sigma 가 무조건 표준편차(MSM 에서 E[ΠM]=1 ⇒ Var = sigma^2) 의미를 잃는다(2011: sigma 0.148 = 창 표본 sd 의 7.6배).
#   위기 정의 s > sigma 가 무의미해지므로 그 해 모수는 '검증 실패'로 본다.
#   규칙: 퇴화 = gamma_1 < 1e-5 또는 sigma/sd(창) ∉ [0.8, 1.25]. 3 초기점 최적점 중 비퇴화 최고 우도 채택 ·
#   전부 퇴화면 직전 유효 모수 유지(과거 정보라 인과 — regime_jump_model.R 의 'refit 실패 = 직전 성공 모수 유지'와 같은 규칙).
#   관문 없는 최고 우도 판은 민감도 열 Crisis_Prob_asof_raw 로 함께 남긴다(후보 아님).
is_degen <- function(par, sdw) par[["gamma_1"]] < 1e-5 || (par[["sigma"]] / sdw) < 0.8 || (par[["sigma"]] / sdw) > 1.25
asof <- fits[grepl("^asof_", names(fits))]
asof <- asof[order(vapply(asof, function(f) as.character(f$cut), ""))]
prev_valid <- NULL
for (k in seq_along(asof)) {
  f <- asof[[k]]; sdw <- sd(RT[Date <= as.Date(f$cut)]$r)
  cand <- lapply(seq_along(f$all_par), function(i) list(par = setNames(as.list(f$all_par[[i]]), c("m0", "sigma", "b", "gamma_1")),
                                                         nll = f$all_values[i]))
  dg <- vapply(cand, function(cn) is_degen(cn$par, sdw), logical(1))
  f$window_sd <- sdw; f$init_degenerate <- dg; f$raw_par <- f$par
  if (any(!dg)) {
    j <- which(!dg)[which.min(vapply(cand[!dg], function(cn) cn$nll, 1))]
    f$guard_par <- cand[[j]]$par; f$guard_nll <- cand[[j]]$nll; f$guard_action <- if (j == which.min(f$all_values)) "mle" else "best_nondegenerate"
    prev_valid <- f$guard_par
  } else {
    f$guard_par <- prev_valid; f$guard_nll <- NA_real_; f$guard_action <- "carry_forward_previous"
  }
  asof[[k]] <- f
}
stopifnot(all(vapply(asof, function(f) !is.null(f$guard_par), logical(1))))

# ── as-of 일별 경로: 블록 [rf_k, rf_{k+1}) 를 θ_k 로 전방 필터(시작부터 블록 끝까지 1회 통과) ──
rows <- vector("list", length(asof))
for (k in seq_along(asof)) {
  f <- asof[[k]]; rf <- as.Date(f$cut)
  rf_next <- if (k < length(asof)) as.Date(asof[[k + 1L]]$cut) else max(RT$Date) + 1L
  end_i <- max(which(RT$Date < rf_next))
  g <- f$guard_par; r0 <- f$raw_par
  p <- fk$msm_fast_filter(RT$r[1:end_i], K_BAR, g$m0, g$sigma, g$b, g$gamma_1, TRUE)
  q <- fk$msm_fast_filter(RT$r[1:end_i], K_BAR, r0$m0, r0$sigma, r0$b, r0$gamma_1, TRUE)
  keep <- which(RT$Date[1:end_i] >= rf)
  rows[[k]] <- data.table(Date = RT$Date[keep], Crisis_Prob_asof = p$crisis_prob[keep], Vol_asof = p$vol[keep],
                          Crisis_Prob_asof_raw = q$crisis_prob[keep], fit_date = rf, guard_action = f$guard_action)
}
AS <- rbindlist(rows)
stopifnot(!anyDuplicated(AS$Date), all(AS$fit_date <= AS$Date))
setattr(AS, "msm_asof_spec", "Calvet-Fisher MSM k=10; params = MLE (MSM.R objective/bounds/3 inits + NM restarts + BFGS polish) on expanding-demeaned log returns with data <= fit_date (annual year-end refit); identification guard: degenerate if gamma_1<1e-5 or sigma/sd not in [0.8,1.25] -> best non-degenerate optimum else carry forward previous valid; filter = msm_update.R kernel (Kronecker-factored, PC1). Crisis_Prob_asof_raw = unguarded MLE (sensitivity)")
write_parquet(AS, file.path(WORK, "msm_asof_daily.parquet"))

out$asof_fits <- lapply(asof, function(f) f[c("tag", "cut", "n_obs", "first", "last", "par", "negloglik", "counts", "all_values", "all_par", "window_sd", "init_degenerate", "guard_par", "guard_nll", "guard_action", "secs")])
out$identification_guard <- "degenerate if gamma_1 < 1e-5 or sigma/sd(window) not in [0.8, 1.25]; choose best non-degenerate init optimum; else carry forward previous valid params (decided 2026-10-10 before any AUC; v1 unguarded record = work/msm_asof_fit_v1_unguarded.json)"
out$asof_daily <- list(path = "04_Research/l2_role_rotation/work/msm_asof_daily.parquet", n = nrow(AS),
                       first = as.character(min(AS$Date)), last = as.character(max(AS$Date)),
                       fit_date_lt_or_eq_date = all(AS$fit_date <= AS$Date))
out$finished_at <- now_kst()
out$elapsed_min <- round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 2)
write_json_atomic(out, file.path(WORK, "msm_asof_fit.json"))
cat(sprintf("[build_msm_asof] done %.1f min · PC1 %.2e · PC2 max %.2e · asof rows %d (%s..%s)\n",
            out$elapsed_min, pc1, out$PC2_store_vs_recompute$max_abs, nrow(AS), min(AS$Date), max(AS$Date)))
for (p in pc3) cat(sprintf("  %s: fitted m0=%.4f sigma=%.5f b=%.3f g1=%.6f | nll fit %.2f vs pin %.2f\n", p$tag,
                           p$fitted$m0, p$fitted$sigma, p$fitted$b, p$fitted$gamma_1, p$negloglik_fitted, p$negloglik_at_pinned))
