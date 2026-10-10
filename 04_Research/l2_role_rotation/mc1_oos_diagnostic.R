#==============================================================================
# mc1_oos_diagnostic.R — MC1 OOS(2016-01 ~ 최근 완결월) 판별력 **진단 전용** (선정 변경 금지)
#
# 순서 계약: predictor_selection_IS.json 이 먼저 있어야 한다(없으면 중단). 그 파일의 md5·작성 시각을 기록하고,
#   주 예측기는 그 파일에서 읽기만 한다 — 여기 수치로 선정·규칙을 바꾸지 않는다(설계 §2.2 · §6 "OOS 를 보고 예측기 고르기" 금지).
# 표적·AUC·부트스트랩 정의 = IS 와 같음(lib_mc1.R). 분산 표적 문턱 = IS 3분위 문턱(IS 파일 값) — 보조로 OOS 자체 3분위 병기.
# PS 연대기 꼬리: t_censor 6 → 마지막 6개월 국면은 잠정 — 본 값(2016-01~최근 완결월)과 확정 구간(꼬리 6개월 제외) 병기.
# 실행: cd 04_Research/l2_role_rotation ; Rscript --no-save -e 'source("mc1_oos_diagnostic.R")'
#==============================================================================
source("lib_mc1.R")
IS_PATH <- file.path(L2DIR, "predictor_selection_IS.json")
if (!file.exists(IS_PATH)) stop("[MC1 OOS] predictor_selection_IS.json 부재 — IS 선정을 먼저(순서 계약)")
IS <- fromJSON(IS_PATH, simplifyVector = FALSE)
is_md5 <- unname(tools::md5sum(IS_PATH))
cands <- unlist(IS$selection$eligible)
primary <- IS$selection$primary
q_var_IS <- IS$sample$rv_tercile_threshold_IS
specs <- lapply(cands, function(nm) IS$results[[nm]]$spec); names(specs) <- cands

bm <- load_bm()
last_complete <- format(seq(as.Date(format(max(bm$Date), "%Y-%m-01")), by = "-1 month", length.out = 2)[2], "%Y-%m")
months <- format(seq(as.Date("2016-01-01"), as.Date(paste0(last_complete, "-01")), by = "month"), "%Y-%m")
DT <- decision_table(months, bm$Date)
PS <- ps_chronology()
RV <- monthly_rv(bm)
P <- data.table(ym = months, t = DT$t, t_lag1 = DT$t_lag1, y_dir = PS$ps_bear[match(months, PS$ym)], rv = RV$rv[match(months, RV$ym)])
P[, y_var_ISthr := rv > q_var_IS]
P[, y_var_OOSterc := rv > quantile(rv, 2 / 3, type = 7)]
censor_from <- format(seq(as.Date(paste0(last_complete, "-01")), by = "-1 month", length.out = 6)[6], "%Y-%m")
P[, label_provisional := ym >= censor_from]

for (nm in cands) {
  s <- specs[[nm]]
  x <- as.data.table(read_parquet(file.path(ROOT, s$file))); x[, Date := as.Date(Date)]; setorder(x, Date)
  a <- asof_value(x$Date, x[[s$col]], P$t); stopifnot(all(a$src_date <= P$t, na.rm = TRUE))
  P[, (nm) := a$value]; P[, (paste0(nm, "__lag1")) := asof_value(x$Date, x[[s$col]], P$t_lag1)$value]
}
lr <- c(NA_real_, diff(log(bm$BM_Close)))
P[, REF_vol20 := asof_value(bm$Date, frollapply(lr, 20L, sd, align = "right"), t)$value]
P[, REF_negret12m := -asof_value(bm$Date, bm$BM_Close / shift(bm$BM_Close, 252L) - 1, t)$value]
ma_raw <- as.data.table(read_parquet(file.path(WORK, "msm_asof_daily.parquet"))); ma_raw[, Date := as.Date(Date)]
P[, SENS_MSM_asof_raw := asof_value(ma_raw$Date, ma_raw$Crisis_Prob_asof_raw, t)$value]

IDX <- cbb_indices(nrow(P), L = 12L, B = 5000L, seed = 20261010L)
IDXs <- cbb_indices(sum(!P$label_provisional), L = 12L, B = 5000L, seed = 20261010L)
one <- function(score, y, idx) { bt <- boot_auc(score, y, idx); list(auc = auc_mw(score, y), ci95 = ci_q(bt, 0.025, 0.975), n_pos = sum(y), n = length(y)) }
res <- list()
for (nm in c(cands, "REF_vol20", "REF_negret12m", "SENS_MSM_asof_raw")) {
  sc <- P[[nm]]; st <- !P$label_provisional
  r <- list(direction = one(sc, P$y_dir, IDX),
            direction_stable_labels = one(sc[st], P$y_dir[st], IDXs),
            variance_IS_threshold = one(sc, P$y_var_ISthr, IDX),
            variance_OOS_tercile = one(sc, P$y_var_OOSterc, IDX),
            shift_null_direction = shift_null_p(sc, P$y_dir, 12L)[c("p_one_sided", "null_q95")])
  if (nm %in% cands) r$direction_lag1_auc <- auc_mw(P[[paste0(nm, "__lag1")]], P$y_dir)
  r$role <- if (nm %in% cands) (if (nm == primary) "primary (IS-selected)" else "eligible_not_selected") else if (startsWith(nm, "SENS_")) "sensitivity_not_candidate" else "reference_only"
  res[[nm]] <- r
}
out <- list(schema = "l2_mc1_predictor_oos_diagnostic_v1", written_at = now_kst(),
            stage = "OOS_DIAGNOSTIC (선정에 쓰지 않음)",
            is_selection_file = list(path = "04_Research/l2_role_rotation/predictor_selection_IS.json", md5 = is_md5,
                                     written_at = IS$written_at, primary = primary, mc1_pass_IS = IS$selection$mc1_pass),
            sample = list(months = c(first(months), last(months)), n = nrow(P), n_bear = sum(P$y_dir), share_bear = mean(P$y_dir),
                          provisional_label_months_from = censor_from, n_stable = sum(!P$label_provisional),
                          n_highvol_IS_threshold = sum(P$y_var_ISthr), rv_threshold_IS = q_var_IS,
                          bm_last_date = as.character(max(bm$Date))),
            results = res,
            note = "진단 전용 — IS 선정 파일을 바꾸지 않는다. 낮은 OOS 판별력은 '선정 재고'가 아니라 MC1 해석·사전등록 갱신 사안으로 도훈/Q-Lead 에 보고")
fwrite(P, file.path(WORK, "mc1_panel_OOS.csv"))
write_json_atomic(out, file.path(L2DIR, "predictor_oos_diagnostic.json"))
cat(sprintf("[MC1 OOS] %s..%s n=%d bear=%d | primary %s\n", first(months), last(months), nrow(P), sum(P$y_dir), primary))
for (nm in names(res)) cat(sprintf("  %-22s dir %.3f [%.3f,%.3f] stable %.3f | var(ISthr) %.3f [%.3f,%.3f] | lag1 %s\n", nm,
  res[[nm]]$direction$auc, res[[nm]]$direction$ci95[1], res[[nm]]$direction$ci95[2], res[[nm]]$direction_stable_labels$auc,
  res[[nm]]$variance_IS_threshold$auc, res[[nm]]$variance_IS_threshold$ci95[1], res[[nm]]$variance_IS_threshold$ci95[2],
  if (is.null(res[[nm]]$direction_lag1_auc)) "-" else sprintf("%.3f", res[[nm]]$direction_lag1_auc)))
