#==============================================================================
# pit_audit_compile.R — 2계층 국면 예측기 후보 PIT 감사 정리 (Task A) → pit_audit.json
#
# 판정 범주: PIT-clean / usable-with-lag(지연 명시) / contaminated(사유 명시).
# 근거 = 코드 판독(아래 각 항목 code_findings 에 파일:행) + 실증(이 폴더의 build_*·jm_truncation_check 산출 · 여기서 계산하는 값 차이).
# 입력(읽기만): work/msm_asof_fit.json · work/msm_asof_daily.parquet · work/hmm2_asof_fit.json · work/hmm2_asof_daily.parquet ·
#   work/jm_trunc_*.json · work/test_jm_causal.log · .cache/*(regime) · stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet ·
#   06_Registry/pit_quarantine.json(판독기 pit_quarantine.R) · 02_Infrastructure/data/cache_registry.json
# 실행: cd 04_Research/l2_role_rotation ; Rscript --no-save -e 'source("pit_audit_compile.R")'
#==============================================================================
source("lib_mc1.R")
qe <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/validation/pit_quarantine.R"), envir = qe)
qhits <- function(txt) as.character(qe$pitq_source_hits(txt, ROOT))
bm <- load_bm()
months_all <- format(seq(as.Date("2005-01-01"), as.Date("2026-09-01"), by = "month"), "%Y-%m")
DT <- decision_table(months_all, bm$Date)
DT[, is := ym <= "2015-12"]

# ── 1. MSM 운영 캐시(msm_update.R) vs as-of 수리판 — 결정일 값 차이 ─────────────────
msm_fit <- fromJSON(file.path(WORK, "msm_asof_fit.json"), simplifyVector = FALSE)
st <- as.data.table(read_parquet(file.path(ROOT, ".cache/msm_daily_latest.parquet"))); st[, Date := as.Date(Date)]
ma <- as.data.table(read_parquet(file.path(WORK, "msm_asof_daily.parquet")))
DT[, msm_prod := asof_value(st$Date, st$Crisis_Prob, t)$value]
DT[, msm_asof := asof_value(ma$Date, ma$Crisis_Prob_asof, t)$value]
gap <- function(a, b) { ok <- is.finite(a) & is.finite(b); a <- a[ok]; b <- b[ok]
  list(n = length(a), mean_abs = mean(abs(a - b)), median_abs = median(abs(a - b)), max_abs = max(abs(a - b)),
       spearman = suppressWarnings(cor(a, b, method = "spearman")), share_flip_0.5 = mean((a > 0.5) != (b > 0.5)),
       share_flip_0.8 = mean((a >= 0.8) != (b >= 0.8))) }
msm_gap <- list(IS_2005_2015 = DT[is == TRUE, gap(msm_prod, msm_asof)], OOS_2016_2026 = DT[is == FALSE, gap(msm_prod, msm_asof)],
                by_year_mean_abs = DT[, .(mean_abs = round(mean(abs(msm_prod - msm_asof)), 4)), by = .(y = substr(ym, 1, 4))])
# as-of 수리판 자체 접두 불변(블록 모수 고정 · 자른 수익으로 재필터 → 패널 값과 같아야)
fk <- fast_msm_kernel(); RT <- msm_returns(bm)
fits_tbl <- rbindlist(lapply(msm_fit$asof_fits, function(f) data.table(cut = as.Date(f$cut), m0 = f$guard_par$m0, sigma = f$guard_par$sigma, b = f$guard_par$b, g1 = f$guard_par$gamma_1, action = f$guard_action)))
msm_asof_prefix <- lapply(as.Date(c("2008-09-30", "2011-08-31", "2015-12-30")), function(tc) {
  fd <- ma[Date == tc, fit_date]; p <- fits_tbl[cut == fd]
  v <- tail(fk$msm_fast_filter(RT[Date <= tc]$r, 10L, p$m0, p$sigma, p$b, p$g1, TRUE)$crisis_prob, 1)
  list(cut = as.character(tc), fit_date = as.character(fd), panel = ma[Date == tc, Crisis_Prob_asof], recomputed_truncated = v,
       abs_diff = abs(ma[Date == tc, Crisis_Prob_asof] - v))
})

# ── 2. 폴백 msm_daily_refit(2-state HMM) — 평활·덮어쓰기 실증 + 수리판 접두 불변 ───────
hmm_fit <- fromJSON(file.path(WORK, "hmm2_asof_fit.json"), simplifyVector = FALSE)
ha <- as.data.table(read_parquet(file.path(WORK, "hmm2_asof_daily.parquet")))
he <- new.env(); he$PROJECT_ROOT <- ROOT; he$CACHE_DIR <- file.path(ROOT, ".cache")
invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/regime/regime_hmm.R"), envir = he)))
lr_all <- c(NA_real_, diff(log(bm$BM_Close)))
# 수치 확인: 같은 모수(마지막 refit 의 저장 모수는 반올림이라 쓰지 않는다)로 — 2015-12-30 까지 자료로 EM 1회 → 필터를 (a) tc 까지 (b) 자료 끝까지 돌려 tc 값 비교
w15 <- lr_all[!is.na(lr_all) & bm$Date <= as.Date("2015-12-30")]
f15 <- he$.hmm_em(w15, max_iter = 50L, tol = 1e-5, mu_init = c(0.0005, -0.002), sigma_init = c(0.010, 0.025))
ss <- if (f15$sigma[2] > f15$sigma[1]) 2L else 1L
tc <- as.Date("2011-08-31")
a_cut <- he$.hmm_forward(lr_all[!is.na(lr_all) & bm$Date <= tc], f15$mu, f15$sigma, f15$A, f15$pi0)
a_all <- he$.hmm_forward(lr_all[!is.na(lr_all)], f15$mu, f15$sigma, f15$A, f15$pi0)
rv_all <- lr_all[!is.na(lr_all)]; d_all <- bm$Date[!is.na(lr_all)]
i_tc <- nrow(a_cut)
gam_at <- function(h) { e_i <- min(i_tc + h, length(rv_all)); fb <- he$.hmm_forward_backward(rv_all[1:e_i], f15$mu, f15$sigma, f15$A, f15$pi0); fb$gamma[i_tc, ss] }
hs <- c(0L, 1L, 5L, 21L, 63L, length(rv_all) - i_tc)
gam <- vapply(hs, gam_at, numeric(1))
# 같은 비교를 IS 결정일 전체로: γ_t(창 끝 t+21거래일) − α_t(= γ_t 창 끝 t)
DTi <- DT[is == TRUE]
ii <- match(DTi$t, d_all)
fb63 <- he$.hmm_forward_backward(rv_all, f15$mu, f15$sigma, f15$A, f15$pi0)
al_full <- he$.hmm_forward(rv_all, f15$mu, f15$sigma, f15$A, f15$pi0)
hmm2_prefix_numeric <- list(params = "EM on data <= 2015-12-30 (fixed, msm_daily_refit inits)", t = as.character(tc),
  filtered_alpha_trunc_at_t = a_cut[i_tc, ss], filtered_alpha_full_data = a_all[i_tc, ss],
  filtered_abs_diff = abs(a_cut[i_tc, ss] - a_all[i_tc, ss]),
  smoothed_gamma_t_by_window_end = data.table(window_end_plus_trading_days = hs, window_end = as.character(d_all[pmin(i_tc + hs, length(d_all))]), gamma_t = round(gam, 6)),
  IS_decision_dates_full_window_smoothed_vs_filtered = list(n = length(ii), mean_abs = mean(abs(fb63$gamma[ii, ss] - al_full[ii, ss])),
    max_abs = max(abs(fb63$gamma[ii, ss] - al_full[ii, ss])), share_flip_0.5 = mean((fb63$gamma[ii, ss] > 0.5) != (al_full[ii, ss] > 0.5))),
  reading = "같은 모수에서 필터 α_t 는 t 이후 자료와 무관(접두 불변), 평활 γ_t 는 창 끝이 t 를 지나면 바뀐다(정보원 = t 이후 수일~수주; 먼 미래 영향은 급감)")

# ── 3. JM 실자료 접두 불변 + 저장 재현 + 저장소 검사 ─────────────────────────────
jm_tr <- lapply(sort(Sys.glob(file.path(WORK, "jm_trunc_*.json"))), function(f) { d <- fromJSON(f, simplifyVector = FALSE)
  list(cut = d$cut, identical = d$comparison$identical, n_matched = d$comparison$n_matched, max_abs_Bear_Prob = d$comparison$max_abs_Bear_Prob,
       n_state_mismatch = d$comparison$n_JM_State_mismatch, status_stored = d$jm_causal_status_stored,
       status_recomputed = d$jm_causal_status_recomputed, c11 = d$jm_input_c11_status_recomputed) })
tl <- readLines(file.path(WORK, "test_jm_causal.log"), warn = FALSE, encoding = "UTF-8")
jm_test <- grep("최종:", tl, value = TRUE)
jm <- as.data.table(read_parquet(file.path(ROOT, ".cache/regime_jump_daily.parquet")))

# ── 4. 예측 시계열 v1·v1vix·v2·v3 — 계보 ─────────────────────────────────────────
reg <- fromJSON(file.path(ROOT, "02_Infrastructure/data/cache_registry.json"), simplifyVector = FALSE)
reg_items <- reg$caches
writer_of <- function(path) {
  fs <- Sys.glob(file.path(ROOT, "02_Infrastructure/regime/regime_forecaster*.R"))
  w <- fs[vapply(fs, function(f) any(grepl(paste0("write_parquet\\(.*", gsub(".", "\\.", basename(path), fixed = TRUE)), readLines(f, warn = FALSE))), TRUE)]
  sub(paste0(ROOT, "/"), "", w)
}
fc_files <- c(".cache/regime_forecast_series.parquet", ".cache/regime_forecast_series_v1vix.parquet",
              ".cache/regime_forecast_series_v2.parquet", ".cache/regime_forecast_series_v3.parquet")
fc_lineage <- lapply(fc_files, function(p) {
  x <- as.data.table(read_parquet(file.path(ROOT, p)))
  rp <- Filter(function(e) identical(e$path, p), reg_items)
  list(file = file_sig(p), columns = names(x), n = nrow(x), first_forecast_ym = x[!is.na(forecast_regime), min(ym)],
       last_ym = max(x$ym), writer_in_code = writer_of(p),
       cache_registry_producer = if (length(rp)) rp[[1]]$producer else NA, quarantine_hits = qhits(p))
})
un <- as.data.table(read_parquet(file.path(ROOT, ".cache/unified_regime_signal_daily.parquet"))); un[, Date := as.Date(Date)]
mu <- merge(un[, .(Date, u = MSM_Crisis_Prob)], st[, .(Date, s = Crisis_Prob)], by = "Date")
unified_msm_equals_prod <- list(n = nrow(mu), max_abs = max(abs(mu$u - mu$s), na.rm = TRUE))

# ── 5. AE ───────────────────────────────────────────────────────────────────────
ae <- as.data.table(read_parquet(file.path(ROOT, "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet")))
ae_facts <- list(file = file_sig("stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet"), n = nrow(ae),
                 first_decision = as.character(min(as.Date(ae$decision_date))), last_decision = as.character(max(as.Date(ae$decision_date))),
                 c11_feat_join = unique(ae$c11_feat_join), c11_vintage = unique(ae$c11_vintage),
                 c11_vintage_unresolved = unique(ae$c11_vintage_unresolved), c11_vintage_resolved = unique(ae$c11_vintage_resolved),
                 IS_months_covered = sum(format(as.Date(ae$decision_date), "%Y-%m") >= "2005-01" & format(as.Date(ae$decision_date), "%Y-%m") <= "2015-12"),
                 quarantine_hits = qhits("stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet ae_regime_monthly"))

# ── 판정 ────────────────────────────────────────────────────────────────────────
srcs <- list(
  MSM_prod_CrisisProb = list(
    artifact = ".cache/msm_daily_latest.parquet::Crisis_Prob (+ msm_hybrid_latest Avg_Prob)",
    producer = "04_Research/regime_comparison/msm_update.R (daily_refresh.sh:399-415 주 생산자 · cache_registry 등재). ★설계안 §2.2 의 '2-state HMM·30일 재적합'은 폴백 msm_daily_refit.R 이며 현 캐시 생산자가 아니다(저장 열에 HMM_State 없음 · PC2 재계산 일치)",
    model = "Calvet-Fisher binomial MSM k=10 · Hamilton 필터(전방)",
    verdict = "contaminated",
    reason = "C1 — 모수 4개(m0·sigma·b·gamma_1) = K_Fractal_Master_2026-01-20.xlsx 의 전기간 MLE(Last_Trained 2026-01-18 · 표본 1990-01-04~2026-01-16 · MSM.R:173-195 전기간 디민). 위기 상태 정의(s > sigma)도 전기간 sigma. 필터는 평활이 아니라 **필터 확률**이고(msm_update.R C++ extract_msm_path: pi=pi*A → 우도 갱신 → 정규화) 디민도 expanding(2026-08-13 수리) → 시간축 누출은 모수 경로뿐. 지연(lag)으로 해소 불가",
    evidence = list(PC2_store_equals_msm_update_recompute = msm_fit$PC2_store_vs_recompute$max_abs,
                    PC4_prefix_invariance_filter = msm_fit$PC4_prefix_invariance_prod_kernel,
                    value_gap_prod_vs_asof_at_decision_dates = msm_gap),
    quarantine_hits = qhits(".cache/msm_daily_latest.parquet Crisis_Prob msm_update")),
  MSM_fallback_msm_daily_refit = list(
    artifact = "02_Infrastructure/regime/msm_daily_refit.R::compute_hmm_daily_signal → 같은 캐시(폴백 시)",
    model = "2-state Gaussian HMM (regime_hmm.R::.hmm_em) · refit 30행",
    verdict = "contaminated",
    reason = "C1 ×2 — (a) Crisis_Prob = fit$gamma = 순방향-역방향 **평활** 확률(regime_hmm.R:150-155 · msm_daily_refit.R:113-114) (b) 매 refit 이 crisis_prob[valid_idx] <- gamma_stress 로 1..end_i 전 이력을 덮어쓰고(msm_daily_refit.R:121-125) 마지막 refit 은 행 n 강제(:91) → 저장 이력 전체 = 전기간 모수·전기간 평활. refit_freq 와 무관하게 성립",
    evidence = list(hmm2_contamination_IS_month_ends = hmm_fit$fallback_contamination_IS_month_ends, smoothed_vs_filtered_same_params = hmm2_prefix_numeric),
    current_cache_affected = "아니오(현 캐시 = msm_update.R 산출, PC2) — msm_update.R 실패 시 폴백이 덮어쓴다(daily_refresh.sh:409-415 · self_heal.R:40-47)"),
  JM_regime_jump_daily = list(
    artifact = ".cache/regime_jump_daily.parquet::Bear_Prob · JM_State (+ *_lag)",
    model = "Statistical Jump Model K=2 (Shu-Yu-Mulvey 2024 §3.4) · jm_causal:v1",
    verdict = "PIT-clean",
    lag_note = "형태 (a) 결정일 t 종가 결정·월 보유 = Bear_Prob[t] 그대로. 일간 노출을 r_t(종가→종가)에 곱하는 형태 (b) 는 *_lag(1거래일) 열을 써야 한다(엔진 주석 · usable-with-lag 1d)",
    reason = "PIT-C11-JM-C1 수리판 확인 — 모수 = refit 일 r_k 이하 창 [r_k-2999, r_k] 적합·블록 (r_k, r_{k+1}] 적용, 상태 = 고정 모수 전방 DP 종점(역추적 없음), JM_Fit_Date < Date 전 행, VIX_z 입력 = c11_asof_align(가용일 결합 · avail_annotated · epoch c11_avail:2026-09-24.b4). VIX 는 개정 없는 시장 계열(빈티지 무관). 입력 VIX_z_smooth = 756행 rolling/expanding z + 우정렬 MA(regime_engine_daily.R:224-262 · 인과)",
    evidence = list(real_data_truncation = jm_tr, repo_test_test_jm_causal = jm_test,
                    jm_causal_attr = "jm_causal:v1", rows = nrow(jm), first = as.character(min(as.Date(jm$Date))),
                    fit_date_lt_date_all = all(as.Date(jm$JM_Fit_Date) < as.Date(jm$Date))),
    quarantine_hits = qhits(".cache/regime_jump_daily.parquet Bear_Prob JM_State regime_jump_model"),
    registry_caveat = "06_Registry/pit_quarantine.json PITQ-C11-20260924 가 아직 status=active 로 regime_jump_daily·JM_State·Bear_Prob·regime_jump_model 을 격리(V-10: 입력 VIX_z 무지연 — 원인은 2단계에서 수리됨). 실증상 PIT-clean 이나 2계층 소비 전 격리 해제(항목 status → released · 사유·주체 기록 = 도훈 결정) 필요"),
  forecasters_v1_v1vix_v2_v3 = list(
    artifact = ".cache/regime_forecast_series{,_v1vix,_v2,_v3}.parquet (ym, forecast_regime)",
    verdict = "contaminated",
    reason = "시점 구조는 walk-forward(월 m 예측 = m-1 월말 정보 · 전이행렬/다항로짓 학습 = t 이하)로 정상이나, 입력이 오염: ① CrisisP = unified MSM_Crisis_Prob = 운영 MSM(전기간 모수 C1 · 아래 unified_msm_equals_prod) ② Category = unified(MSM + FRED_MRS + KTRI) — MSM C1 상속 + FRED_MRS 의 NFCI(Chi_Fin_Cond) 최신 빈티지 ③ regime_daily_v2 의 Claims(ICSA)·v2 의 NFCI·STLFSI·UMCSENT = 개정 계열 최신 빈티지(regime_engine_daily.R 헤더 '값은 최신 빈티지 — C1·C11 미해소 라벨'). 지연으로 해소 불가. 산출물은 범주 argmax 뿐(확률 없음)",
    lineage = fc_lineage, unified_msm_equals_prod = unified_msm_equals_prod,
    lineage_issues = "① 파일에 계보 속성 없음(ym·forecast_regime 2열) ② cache_registry 생산자 표기가 한 칸씩 어긋남(실제 작성 스크립트와 불일치) ③ 4파일 모두 2026-09-25 11:36 생성 — 입력(unified·regime_daily_v2)은 그 뒤 재빌드(10-10)돼 현 입력으로 재현되는지 미확인 ④ 격리 PITQ-C11 V-10 active"),
  AE_lstm = list(
    artifact = "stage_artifacts/WT_D20260718_007/ae_regime_signal_ext.parquet (ae_regime_monthly.py)",
    verdict = "contaminated",
    reason = "C11 시간축(가용일 결합 decision_close)은 수리됐으나 빈티지 미해소 — 행 표식 c11_vintage=latest · c11_vintage_unresolved=Chi_Fin_Cond,StL_Fin_Stress(개정 계열을 최신 빈티지로 소급 · ALFRED 안 C 미시행). 부가: 발화 문턱 tau 가 기존 M4 의 전기간 발화율 0.126 에 맞춰짐(ae_regime_walkforward.py M4_FIRE_RATE · 연속 점수 ae_seq 순위에는 무관). IS 커버리지 2008-01~ 뿐",
    facts = ae_facts),
  unified_regime_signal = list(
    artifact = ".cache/unified_regime_signal(_daily).parquet (MSM_Crisis_Prob·FRED_MRS·KTRI → Regime_Score·Category)",
    verdict = "contaminated",
    reason = "MSM 성분 = 운영 MSM(C1 전기간 모수) + FRED_MRS 의 NFCI 최신 빈티지. C11 날짜 결합(V-05)은 09-25 재빌드로 가용일 결합 + c11_regime_key 표식. 격리 V-05 active",
    quarantine_hits = qhits(".cache/unified_regime_signal_daily.parquet")))

cand <- list(
  JM_BearProb = list(verdict = "PIT-clean", basis = "JM_regime_jump_daily", as_of_rule = "Bear_Prob at t (row Date == t; JM_Fit_Date < t)",
                     caveat = srcs$JM_regime_jump_daily$registry_caveat),
  MSM_asof_CrisisProb = list(verdict = "PIT-clean", basis = "driver repair of MSM_prod_CrisisProb",
                             as_of_rule = "filtered Crisis_Prob at t with params MLE on data <= fit_date (last year-end <= t)",
                             evidence = list(fit_date_le_date_all = all(ma$fit_date <= ma$Date), prefix_recompute = msm_asof_prefix,
                                             PC1_fast_equals_prod_kernel = msm_fit$PC1_fast_vs_dense_max_abs,
                                             PC3_full_sample_mle_vs_pin = msm_fit$PC3_full_sample_mle_vs_pin,
                                             identification_guard = msm_fit$identification_guard,
                                             guard_actions = fits_tbl[, .(fit = as.character(cut), action, m0 = round(m0, 4), sigma = round(sigma, 5), b = round(b, 3), g1 = signif(g1, 3))]),
                             caveat = "운영 캐시가 아니다 — 2계층 투입 시 엔진 수리(as-of 재추정) 또는 이 드라이버 산출 고정이 필요"),
  HMM2_asof_StressProb = list(verdict = "PIT-clean", basis = "driver repair of MSM_fallback_msm_daily_refit",
                              as_of_rule = "filtered alpha_t[stress] with params of last 30-row refit <= t (same estimator/grid/warm-start chain)",
                              evidence = list(fit_date_le_date_all = all(ha$fit_date <= ha$Date), filter_prefix = hmm2_prefix_numeric),
                              caveat = "운영 캐시가 아니다(폴백 엔진은 평활·덮어쓰기 그대로)"))

out <- list(schema = "l2_regime_predictor_pit_audit_v1", written_at = now_kst(),
            scope = "Task A — 2계층 역할 로테이션 국면 예측기 후보 PIT 감사(C1·C5·C11·C14)",
            categories = c("PIT-clean", "usable-with-lag", "contaminated"),
            sources = srcs, candidate_verdicts = cand,
            c5_timing_rule = "결정일 t = 보유월 첫날 이전 마지막 한국 거래일; 값은 Date <= t 만(overlay_pit_guard 의 first-day-of-holding-month 컷오프 정합)",
            quarantine_registry = list(file = file_sig("06_Registry/pit_quarantine.json"), active_ids = vapply(qe$pitq_load(ROOT), function(x) x$id, "")))
write_json_atomic(out, file.path(L2DIR, "pit_audit.json"))
cat("[pit_audit] written · MSM IS mean|Δ| ", round(msm_gap$IS_2005_2015$mean_abs, 4), " max ", round(msm_gap$IS_2005_2015$max_abs, 4),
    " flip0.5 ", round(msm_gap$IS_2005_2015$share_flip_0.5, 3), " | JM trunc identical: ", paste(vapply(jm_tr, function(x) isTRUE(x$identical), TRUE), collapse = ","), "\n")
