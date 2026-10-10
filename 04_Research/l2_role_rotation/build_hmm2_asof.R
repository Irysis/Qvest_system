#==============================================================================
# build_hmm2_asof.R — 2-state HMM 스트레스 확률의 as-of(필터) 판 + 폴백 msm_daily_refit.R 오염 실증 (엔진 무수정)
#
# 대상: 02_Infrastructure/regime/msm_daily_refit.R::compute_hmm_daily_signal(min_warmup 252, refit_freq_days 30)
#   = daily_refresh.sh 의 MSM 폴백(주 생산자 msm_update.R 실패 시 .cache/msm_daily_latest.parquet 를 쓴다).
#   설계안 §2.2 가 'MSM 위기확률'로 적은 모형이 이것이다.
# 코드 판독 결함 2개(C1):
#   (a) Crisis_Prob = fit$gamma = .hmm_forward_backward 의 **평활** 확률 γ_t = P(s_t | r_1..r_T) — 창 끝 T 까지의 미래 수익 사용.
#   (b) 매 refit 이 crisis_prob[valid_idx] <- gamma_stress 로 1..end_i 전 구간을 **덮어쓴다** → 마지막 refit(행 n 강제)이
#       전 이력을 '전기간 모수 + 전기간 평활' 값으로 바꾼다.
# 수리판(이 파일): 같은 추정기(regime_hmm.R::.hmm_em · max_iter 50 · tol 1e-5 · warm start 사슬)·같은 refit 격자(행 253부터 30행)·
#   같은 원수익(로그 종가수익) — 바꾼 것은 둘뿐: ① 값 = **필터** 확률 α_t = P(s_t | r_1..r_t)(.hmm_forward)
#   ② t 의 값은 refit 일 r <= t 인 마지막 모수로만(덮어쓰기 없음). stress = sigma 큰 상태(원 코드와 같은 규칙).
# 출력: work/hmm2_asof_daily.parquet (Date, Stress_Prob_asof, fit_date, smooth_full, smooth_2015) · work/hmm2_asof_fit.json
# 실행: cd 04_Research/l2_role_rotation ; Rscript --no-save -e 'source("build_hmm2_asof.R")'
#==============================================================================
source("lib_mc1.R")
t_start <- Sys.time()
MIN_WARMUP <- 252L; REFIT_FREQ <- 30L            # msm_daily_refit.R 기본값 그대로
he <- new.env(); he$PROJECT_ROOT <- ROOT; he$CACHE_DIR <- file.path(ROOT, ".cache")
invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/regime/regime_hmm.R"), envir = he)))

bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet")))
bm[, Date := as.Date(Date)]; setorder(bm, Date); bm <- bm[!is.na(BM_Close)]
bm[, log_ret := log(BM_Close / shift(BM_Close, 1L))]
returns_all <- bm$log_ret; dates_all <- bm$Date; n <- length(returns_all)
refit_idx <- seq(MIN_WARMUP + 1L, n, by = REFIT_FREQ)
if (tail(refit_idx, 1) != n) refit_idx <- c(refit_idx, n)

last_mu <- c(0.0005, -0.002); last_sigma <- c(0.010, 0.025)
fits <- vector("list", length(refit_idx))
for (i in seq_along(refit_idx)) {
  end_i <- refit_idx[i]
  w <- returns_all[1:end_i]; w <- w[!is.na(w)]
  if (length(w) < MIN_WARMUP) next
  fit <- tryCatch(he$.hmm_em(w, max_iter = 50L, tol = 1e-5, mu_init = last_mu, sigma_init = last_sigma), error = function(e) NULL)
  if (is.null(fit)) next
  ss <- if (fit$sigma[2] > fit$sigma[1]) 2L else 1L
  fits[[i]] <- list(i = end_i, date = dates_all[end_i], mu = fit$mu, sigma = fit$sigma, A = fit$A, pi0 = fit$pi0,
                    stress = ss, n_iter = fit$n_iter, loglik = fit$log_lik,
                    gamma_stress = if (i == length(refit_idx)) fit$gamma[, ss] else NULL)
  last_mu <- fit$mu; last_sigma <- fit$sigma
  if (i %% 50 == 0) cat(sprintf("  refit %d/%d %s  sigma=[%.4f %.4f] iters=%d\n", i, length(refit_idx), dates_all[end_i], fit$sigma[1], fit$sigma[2], fit$n_iter))
}
ok <- which(!vapply(fits, is.null, logical(1)))
fits <- fits[ok]
cat(sprintf("[hmm2] %d refits fitted (%.1f min)\n", length(fits), as.numeric(difftime(Sys.time(), t_start, units = "mins"))))

# ── as-of 필터 경로: 블록 [r_k, r_{k+1}) 를 θ_k 로 전방 필터 ──────────────────
valid_pos <- which(!is.na(returns_all))                          # 원 코드와 같은 NA 제거 축
rows <- list()
for (k in seq_along(fits)) {
  f <- fits[[k]]
  r_k <- f$i; r_next <- if (k < length(fits)) fits[[k + 1L]]$i else n + 1L
  blk <- r_k:(r_next - 1L)
  end_i <- r_next - 1L
  vp <- valid_pos[valid_pos <= end_i]
  a <- he$.hmm_forward(returns_all[vp], f$mu, f$sigma, f$A, f$pi0)
  pos <- match(blk, vp)
  rows[[k]] <- data.table(Date = dates_all[blk], Stress_Prob_asof = a[pos, f$stress], fit_date = f$date)
}
AS <- rbindlist(rows)
stopifnot(!anyDuplicated(AS$Date), all(AS$fit_date <= AS$Date))

# ── 폴백 오염 실증 ────────────────────────────────────────────────────────────
#  (1) 폴백이 최종적으로 쓰는 값 = 마지막 refit(행 n · 전기간)의 평활 γ (덮어쓰기 (b))
fl <- fits[[length(fits)]]
smooth_full <- data.table(Date = dates_all[valid_pos], smooth_full = fl$gamma_stress)
#  (2) 같은 날짜 t 의 평활값이 t 이후 자료에 따라 바뀌는가: 2015-12-30 까지 창으로 EM(사슬 warm start) → γ_2015
cut15 <- max(dates_all[dates_all <= as.Date("2015-12-30")])
i15 <- which(dates_all == cut15)
prev <- fits[[max(which(vapply(fits, function(f) f$i, 1L) <= i15))]]
w15 <- returns_all[1:i15]; w15 <- w15[!is.na(w15)]
f15 <- he$.hmm_em(w15, max_iter = 50L, tol = 1e-5, mu_init = prev$mu, sigma_init = prev$sigma)
ss15 <- if (f15$sigma[2] > f15$sigma[1]) 2L else 1L
smooth_15 <- data.table(Date = dates_all[valid_pos[valid_pos <= i15]], smooth_2015 = f15$gamma[, ss15])
AS <- merge(AS, smooth_full, by = "Date", all.x = TRUE)
AS <- merge(AS, smooth_15, by = "Date", all.x = TRUE)
setorder(AS, Date)
write_parquet(AS, file.path(WORK, "hmm2_asof_daily.parquet"))

me <- AS[, .SD[which.max(Date)], by = .(ym = format(Date, "%Y-%m"))][ym >= "2004-12" & ym <= "2015-11"]
dd <- function(a, b) { ok <- is.finite(a) & is.finite(b); list(n = sum(ok), mean_abs = mean(abs(a[ok] - b[ok])), max_abs = max(abs(a[ok] - b[ok])),
                                                              share_side_of_0.5_flips = mean((a[ok] > 0.5) != (b[ok] > 0.5))) }
out <- list(script = "04_Research/l2_role_rotation/build_hmm2_asof.R", started_at = format(t_start, "%Y-%m-%dT%H:%M:%S%z"),
            finished_at = now_kst(), elapsed_min = round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 2),
            inputs = list(benchmark = file_sig(".cache/benchmark.parquet"), estimator = file_sig("02_Infrastructure/regime/regime_hmm.R"),
                          target_engine = file_sig("02_Infrastructure/regime/msm_daily_refit.R")),
            spec = list(min_warmup = MIN_WARMUP, refit_freq_days = REFIT_FREQ, n_refits = length(fits),
                        value = "filtered alpha_t[stress] with params of last refit r <= t", stress_rule = "sigma larger"),
            fallback_contamination_IS_month_ends = list(
              note = "IS 결정일(2004-12~2015-11 월말 마지막 거래일)에서 비교. smooth_full = 폴백이 최종 저장할 값(전기간 모수·평활) · smooth_2015 = 2015-12-30 까지 자료로 같은 절차",
              smooth_full_vs_filtered_asof = dd(me$smooth_full, me$Stress_Prob_asof),
              smooth_2015_vs_smooth_full = dd(me$smooth_2015, me$smooth_full),
              smooth_2015_vs_filtered_asof = dd(me$smooth_2015, me$Stress_Prob_asof)),
            last_fit = list(date = as.character(fl$date), mu = fl$mu, sigma = fl$sigma, A = fl$A),
            refits = lapply(fits, function(f) list(date = as.character(f$date), sigma = round(f$sigma, 6), mu = signif(f$mu, 6),
                                                   p_stay = round(diag(f$A), 6), stress = f$stress, n_iter = f$n_iter)),
            asof_daily = list(path = "04_Research/l2_role_rotation/work/hmm2_asof_daily.parquet", n = nrow(AS),
                              first = as.character(min(AS$Date)), last = as.character(max(AS$Date))))
write_json_atomic(out, file.path(WORK, "hmm2_asof_fit.json"))
cat(sprintf("[build_hmm2_asof] done %.1f min · rows %d · IS smooth_full vs filtered mean|d| %.3f · smooth_2015 vs smooth_full mean|d| %.3f\n",
            out$elapsed_min, nrow(AS), out$fallback_contamination_IS_month_ends$smooth_full_vs_filtered_asof$mean_abs,
            out$fallback_contamination_IS_month_ends$smooth_2015_vs_smooth_full$mean_abs))
