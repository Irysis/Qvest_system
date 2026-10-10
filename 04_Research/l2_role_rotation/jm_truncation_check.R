#==============================================================================
# jm_truncation_check.R — 희소 점프 모델(SJM) 운영 캐시의 실자료 접두 불변 검사 (엔진 무수정 · 운영 파일 읽기만)
#
# 묻는 것: .cache/regime_jump_daily.parquet 의 Date <= cut 행이, 입력(벤치·regime_daily_v2)을 cut 에서 자른 뒤
#   운영 엔진(regime_jump_model.R::compute_jm_daily_signal, 기본 인자 = 캐시 속성 jm_causal_spec 과 같은 값)을 다시 돌린 값과 같은가.
#   같다 = cut 이하 값이 cut 이후 자료에 의존하지 않는다(PIT-C11-JM-C1 수리판이 캐시에 실려 있다).
#   cut = 자료 끝이면 '저장 캐시 = 현 엔진·현 입력 재계산'(재현성) 검사가 된다.
# 쓰기: tempdir() 의 잘린 입력 사본 + work/jm_trunc_<cut>.json 뿐. 엔진은 write=FALSE.
# 실행: JM_CUT=2011-08-31 Rscript --no-save -e 'source("jm_truncation_check.R")'   (cut 미지정 = 자료 끝)
#==============================================================================
source("lib_mc1.R")
t0 <- Sys.time()
stored <- as.data.table(read_parquet(file.path(ROOT, ".cache/regime_jump_daily.parquet")))
stored[, Date := as.Date(Date)]; stored[, JM_Fit_Date := as.Date(JM_Fit_Date)]
cut_env <- Sys.getenv("JM_CUT", "")
cut <- if (nzchar(cut_env)) as.Date(cut_env) else max(stored$Date)
sbx <- normalizePath(file.path(tempdir(), paste0("jm_sbx_", format(cut, "%Y%m%d"))), winslash = "/", mustWork = FALSE)
dir.create(sbx, recursive = TRUE, showWarnings = FALSE)
bm <- as.data.table(read_parquet(file.path(ROOT, ".cache/benchmark.parquet"))); bm[, Date := as.Date(Date)]
rd <- as.data.table(read_parquet(file.path(ROOT, ".cache/regime_daily_v2.parquet"))); rd[, Date := as.Date(Date)]
write_parquet(bm[Date <= cut], file.path(sbx, "benchmark.parquet"))
write_parquet(rd[Date <= cut & avail_date <= cut], file.path(sbx, "regime_daily_v2.parquet"))

e <- new.env(parent = globalenv()); e$PROJECT_ROOT <- ROOT; e$CACHE_DIR <- sbx
invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/regime/regime_jump_model.R"), envir = e, keep.source = FALSE)))
log <- capture.output(res0 <- e$compute_jm_daily_signal(write = FALSE))
status_recomputed <- e$jm_causal_status(res0)
c11_recomputed <- attr(res0, "jm_input_c11_status")
res <- copy(as.data.table(res0)); res[, Date := as.Date(Date)]
st_panel <- read_parquet(file.path(ROOT, ".cache/regime_jump_daily.parquet"))
status_stored <- e$jm_causal_status(st_panel)

m <- merge(stored[Date <= cut], res, by = "Date", suffixes = c("_st", "_re"))
cmp <- list(
  n_stored_le_cut = nrow(stored[Date <= cut]), n_recomputed = nrow(res), n_matched = nrow(m),
  max_abs_Bear_Prob = max(abs(m$Bear_Prob_st - m$Bear_Prob_re)),
  max_abs_Bear_Prob_lag = max(abs(m$Bear_Prob_lag_st - m$Bear_Prob_lag_re)),
  n_JM_State_mismatch = sum(m$JM_State_st != m$JM_State_re),
  n_JM_State_lag_mismatch = sum(m$JM_State_lag_st != m$JM_State_lag_re),
  n_Fit_Date_mismatch = sum(m$JM_Fit_Date_st != as.Date(m$JM_Fit_Date_re)),
  value_at_cut_stored = stored[Date == max(Date[Date <= cut]), Bear_Prob],
  value_at_cut_recomputed = res[Date == max(Date), Bear_Prob])
cmp$identical <- isTRUE(cmp$max_abs_Bear_Prob < 1e-12 && cmp$n_JM_State_mismatch == 0L && cmp$n_Fit_Date_mismatch == 0L &&
                          cmp$n_matched == cmp$n_stored_le_cut)
out <- list(script = "04_Research/l2_role_rotation/jm_truncation_check.R", cut = as.character(cut), at = now_kst(),
            elapsed_min = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2),
            inputs = list(jm_cache = file_sig(".cache/regime_jump_daily.parquet"), benchmark = file_sig(".cache/benchmark.parquet"),
                          regime_daily_v2 = file_sig(".cache/regime_daily_v2.parquet"), engine = file_sig("02_Infrastructure/regime/regime_jump_model.R")),
            jm_causal_status_stored = status_stored, jm_causal_status_recomputed = status_recomputed,
            jm_input_c11_status_recomputed = c11_recomputed, comparison = cmp,
            engine_log_tail = tail(log, 4))
write_json_atomic(out, file.path(WORK, sprintf("jm_trunc_%s.json", format(cut, "%Y%m%d"))))
cat(sprintf("[jm_trunc %s] identical=%s maxΔBearProb=%.3g stateΔ=%d fitΔ=%d matched=%d/%d (%.1f min)\n", cut, cmp$identical,
            cmp$max_abs_Bear_Prob, cmp$n_JM_State_mismatch, cmp$n_Fit_Date_mismatch, cmp$n_matched, cmp$n_stored_le_cut, out$elapsed_min))
