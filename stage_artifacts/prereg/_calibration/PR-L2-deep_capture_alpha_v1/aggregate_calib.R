## 교정 몬테카를로 집계 → calibration.json (PR-L2 1차 지표 문턱 α_cal · 계기 교정 산출물 · 등급 아님)
## 사용: Rscript aggregate_calib.R <ROOT> <calib_csv_dir> <out.json> <script_dir>
## 규칙(사전 고정 — 이 파일이 정본):
##   · 판정 통계 = rf_prereg_paired_boot(stat='deep_capture') 의 p_gt0 = P*(Δ*>0) (감소 방향 기전의 부트스트랩 p 값)
##   · 명목 규칙 = 90% CI 상한 < 0  (≈ p_gt0 < 0.05)
##   · 교정 = 귀무(참 Δ=0) 교정 세트에서 FPR(α) = P(p_gt0 < α · 유효) ≤ 0.05 인 격자(j/B) 최대 α — 실현 KOSPI200 심층 월 경로 위
##     세 잡음 형태(정규 · t5 이분산 · t5 이분산 AR(1)) 중 최소값을 α_cal 로 쓴다(최악 형태에서 크기 5% 이하)
##   · 검증 = 독립 seed 보류 세트에서 FPR(α_cal) 의 정확 이항 95% 구간 상한이 0.05 를 유의하게 넘지 않을 것 + 명목 규칙 재현(양성 대조)
suppressMessages({ library(data.table); library(jsonlite) })
a <- commandArgs(trailingOnly = TRUE)
ROOT <- normalizePath(a[1], winslash = "/", mustWork = TRUE); CD <- a[2]; OUT <- a[3]; SD <- a[4]
L <- new.env(parent = globalenv())
invisible(capture.output(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"), envir = L, keep.source = FALSE)))
cfg <- L$rf_prereg_config(ROOT); B <- as.integer(cfg$bootstrap$B)
fs <- list.files(CD, pattern = "\\.csv$", full.names = TRUE)
X <- rbindlist(lapply(fs, function(f) { z <- fread(f); z[, src := basename(f)]; z }), fill = TRUE)
X[, valid := is.finite(p_gt0)]
fpr <- function(p, v, al) mean(v & p < al)
grid <- (0:(B / 10)) / B                            # 0 ~ 0.1 (j/B)
alpha_max <- function(p, v) { ok <- vapply(grid, function(al) fpr(p, v, al) <= 0.05, logical(1)); max(grid[ok]) }
ebin <- function(x, n) { bt <- binom.test(x, n); list(rate = x / n, n = n, x = x, ci95 = as.numeric(bt$conf.int)) }
REAL <- c("real_norm", "real_t5het", "real_t5het_ar")
cal <- X[grepl("^cal_", src) & delta == 0]; hold <- X[grepl("^hold_", src) & delta == 0]
per <- lapply(REAL, function(s) { z <- cal[scenario == s]
  list(scenario = s, n = nrow(z), n_deep = unique(z$n_deep), invalid = mean(!z$valid),
       fpr_nominal_ci_hi = mean(z$valid & z$ci_hi < 0), fpr_nominal_p05 = fpr(z$p_gt0, z$valid, 0.05),
       alpha_5pct = alpha_max(z$p_gt0, z$valid), median_block = median(z$block_len, na.rm = TRUE)) })
names(per) <- REAL
alpha_cal <- min(vapply(per, function(z) z$alpha_5pct, numeric(1)))
hv <- lapply(REAL, function(s) { z <- hold[scenario == s]
  list(scenario = s, fpr_at_alpha_cal = ebin(sum(z$valid & z$p_gt0 < alpha_cal), nrow(z)),
       fpr_nominal_ci_hi = ebin(sum(z$valid & z$ci_hi < 0), nrow(z)),
       two_sided_inside = mean(z$valid & z$p_gt0 >= alpha_cal & z$p_gt0 <= 1 - alpha_cal),
       reversal_rate = mean(z$valid & z$p_gt0 > 1 - alpha_cal)) })
names(hv) <- REAL
adv <- X[scenario == "adv_B" & delta == 0]
pos <- list(scenario = "adv_B(적대검증 fpr_sim B 재현 · B=설정값)", n = nrow(adv), n_deep_median = median(adv$n_deep),
            fpr_nominal_ci_hi = ebin(sum(adv$valid & adv$ci_hi < 0), nrow(adv)), invalid = mean(!adv$valid),
            fpr_at_alpha_cal = ebin(sum(adv$valid & adv$p_gt0 < alpha_cal), nrow(adv)))
trend <- lapply(c("adv_B", "syn_n520", "syn_n1040"), function(s) { z <- X[scenario == s & delta == 0]
  if (!nrow(z)) return(NULL)
  list(scenario = s, n_months = unique(z$n)[1], n_deep_median = median(z$n_deep), median_block = median(z$block_len, na.rm = TRUE),
       fpr_nominal_ci_hi = ebin(sum(z$valid & z$ci_hi < 0), nrow(z))) })
blk <- lapply(c(1, 7, 12, 24), function(b) { z <- X[scenario == paste0("blk_", b) & delta == 0]
  if (!nrow(z)) return(NULL)
  list(block_len = b, n = nrow(z), fpr_nominal_ci_hi = ebin(sum(z$valid & z$ci_hi < 0), nrow(z)), invalid = mean(!z$valid)) })
pw <- lapply(sort(unique(X[delta > 0]$delta)), function(d) { z <- X[delta == d]
  list(delta_true = -d, scenario = unique(z$scenario), n = nrow(z),
       detect_nominal = mean(z$valid & z$ci_hi < 0), detect_alpha_cal = mean(z$valid & z$p_gt0 < alpha_cal),
       median_value = median(z$value, na.rm = TRUE), sd_value = sd(z$value, na.rm = TRUE)) })
## 관측 요약(원인 진단 — 데이터에서 문장을 만든다 · 손 서술 금지)
bl_f <- vapply(Filter(Negate(is.null), blk), function(b) b$fpr_nominal_ci_hi$rate, numeric(1))
bl_b <- vapply(Filter(Negate(is.null), blk), function(b) b$block_len, numeric(1))
tr_f <- vapply(Filter(Negate(is.null), trend), function(t) t$fpr_nominal_ci_hi$rate, numeric(1))
tr_n <- vapply(Filter(Negate(is.null), trend), function(t) t$n_deep_median, numeric(1))
findings <- list(
  block_len = as.list(bl_b), fpr_by_block = as.list(bl_f),
  block_monotone_up = length(bl_f) > 1 && all(diff(bl_f) >= 0), block_all_above_nominal = length(bl_f) > 0 && all(bl_f > 0.05),
  n_deep_trend = as.list(tr_n), fpr_by_n_deep = as.list(tr_f), n_deep_restores_size = length(tr_f) > 1 && tr_f[length(tr_f)] <= 0.05,
  conclusion = sprintf("블록 길이 %s → 명목 FPR %s (%s) · 합성 표본 심층 월 중앙 %s → 명목 FPR %s — %s",
                       paste(bl_b, collapse = "/"), paste(sprintf("%.3f", bl_f), collapse = "/"),
                       if (length(bl_f) > 1 && all(diff(bl_f) >= 0)) "블록이 길수록 악화" else "블록 길이와 단조 관계 아님",
                       paste(tr_n, collapse = "/"), paste(sprintf("%.3f", tr_f), collapse = "/"),
                       if (length(tr_f) > 1 && tr_f[length(tr_f)] <= 0.05) "표본이 커지면 명목 회복" else "표본 길이만으로 명목 크기가 회복되지 않음 → 블록 길이·표본 조정이 아니라 문턱 교정(크기 5% 직접 표적)을 채택"))
shaf <- function(p) L$.rfp_sha_file(p)
bmp <- file.path(ROOT, ".cache/benchmark.parquet")
res <- list(
  schema = "rf_prereg_calibration_v1", id = "PR-L2.deep_capture_delta.p_gt0.alpha_cal.v1",
  label = "계기 교정 — 등급 대체 아님 · 전략 산출물 미사용",
  created_at = L$.rfp_now(), created_by = "Q(세션) · DRAFT2 갈래 — R 몬테카를로(판정 계약 rf_prereg_paired_boot 그대로 호출)",
  target = list(metric = "deep_capture_delta", contract = "rf_prereg_paired_boot", stat = "p_gt0", direction = "decrease",
                nominal_rule = "ci_hi < 0 (90% 백분위 · ≈ p_gt0 < 0.05)"),
  problem = list(source = "scratchpad/p2_found/PREREG/report/adv/fpr_sim.json (적대검증 2026-09-25 · B=499)",
                 fpr_nominal_reported = 0.0866, expected = 0.05),
  instrument = list(rf_prereg_R_sha256 = shaf(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R")),
                    prereg_config_sha256 = attr(cfg, "sha256"), B = B, seed = cfg$bootstrap$seed, ci_level = cfg$bootstrap$ci_level,
                    block_rule_config = cfg$bootstrap$block_rule, block_rule_realized = unique(na.omit(cal$block_len)),
                    block_rule_note = "np 패키지 부재 → adv_block_len 이 HHJ n^(1/3) 로 폴백(설정 'auto' 의 Politis-White 는 이 환경에서 실현되지 않는다)",
                    deep_threshold = L$.rfp_src(ROOT, "02_Infrastructure/contracts/defensive_score.R", "ds")$ds_params(ROOT)$deep_threshold),
  bench = list(path = ".cache/benchmark.parquet", sha256 = shaf(bmp), mtime = format(file.info(bmp)$mtime, "%Y-%m-%dT%H:%M:%S%z"),
               months = "2005-01 ~ 마지막 완결월(달력월 복리 BM_Ret)", n_months = unique(cal$n)[1], n_deep = unique(cal$n_deep)),
  rule = list(alpha_cal = alpha_cal, grid = sprintf("j/B (B=%d)", B), criterion = "max α s.t. P0(p_gt0 < α ∧ 유효) ≤ 0.05 · 세 잡음 형태 최소",
              use_one_sided = "기전(감소) 성립 = p_gt0 < α_cal", use_two_sided = "0 포함(구별 불가) = α_cal ≤ p_gt0 ≤ 1 − α_cal",
              use_reversal = "유의한 반대 방향 = p_gt0 > 1 − α_cal"),
  findings = findings, calibration_set = per, holdout = hv, positive_control = pos, mechanism_ndeep_trend = trend, block_length_whatif = blk, power_cost = pw,
  reps = list(cal = nrow(cal), hold = nrow(hold), adv = nrow(adv)),
  inputs = lapply(fs, function(f) list(file = basename(f), sha256 = shaf(f), rows = nrow(fread(f)))),
  scripts = lapply(c("calib_deep_capture.R", "aggregate_calib.R", "run_calib.sh"), function(f) list(file = f, sha256 = shaf(file.path(SD, f)))),
  links = list(
    list(cite = "Hall (1986) On the bootstrap and confidence intervals. Annals of Statistics 14(4)", url = "https://doi.org/10.1214/aos/1176350164", use = "백분위 구간의 포함 확률 오차 — 교정(calibration)으로 명목 수준을 맞춘다"),
    list(cite = "Beran (1987) Prepivoting to reduce level error of confidence sets. Biometrika 74(3)", url = "https://doi.org/10.1093/biomet/74.3.457", use = "부트스트랩 p 값의 귀무 분포로 문턱을 다시 잡는다(prepivoting)"),
    list(cite = "Hall & Martin (1988) On bootstrap resampling and iteration. Biometrika 75(4)", url = "https://doi.org/10.1093/biomet/75.4.661", use = "수준 교정(iterated/calibrated bootstrap)"),
    list(cite = "Hesterberg (2015) What Teachers Should Know About the Bootstrap. The American Statistician 69(4)", url = "https://doi.org/10.1080/00031305.2015.1089789", use = "소표본 백분위 구간은 좁다(sqrt((n-1)/n) · z vs t) — 심층 월 n=10 의 부분 설명(블록 길이 악화분은 설명하지 못한다 · findings)"),
    list(cite = "Politis & White (2004) Automatic Block-Length Selection for the Dependent Bootstrap. Econometric Reviews 23(1)", url = "https://doi.org/10.1081/ETC-120028836", use = "블록 길이 선택 — 이 교정에서는 블록 길이 what-if 로 크기 회복 경로가 아님을 대조(findings)")))
dir.create(dirname(OUT), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(res, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), OUT, useBytes = TRUE)
cat(sprintf("alpha_cal = %.4f\n", alpha_cal))
for (s in REAL) cat(sprintf("  cal %-14s n=%d nominal=%.4f alpha5=%.4f | hold FPR(α_cal)=%.4f [%.4f,%.4f] nominal=%.4f inside2=%.3f\n", s, per[[s]]$n,
                            per[[s]]$fpr_nominal_ci_hi, per[[s]]$alpha_5pct, hv[[s]]$fpr_at_alpha_cal$rate, hv[[s]]$fpr_at_alpha_cal$ci95[1],
                            hv[[s]]$fpr_at_alpha_cal$ci95[2], hv[[s]]$fpr_nominal_ci_hi$rate, hv[[s]]$two_sided_inside))
cat(sprintf("  positive control adv_B nominal FPR = %.4f [%.4f,%.4f] · at α_cal = %.4f\n", pos$fpr_nominal_ci_hi$rate, pos$fpr_nominal_ci_hi$ci95[1], pos$fpr_nominal_ci_hi$ci95[2], pos$fpr_at_alpha_cal$rate))
for (t in Filter(Negate(is.null), trend)) cat(sprintf("  trend %-10s n=%d n_deep~%g block=%g nominal FPR=%.4f\n", t$scenario, t$n_months, t$n_deep_median, t$median_block, t$fpr_nominal_ci_hi$rate))
for (b in Filter(Negate(is.null), blk)) cat(sprintf("  block %2d nominal FPR=%.4f [%.4f,%.4f]\n", b$block_len, b$fpr_nominal_ci_hi$rate, b$fpr_nominal_ci_hi$ci95[1], b$fpr_nominal_ci_hi$ci95[2]))
for (p in pw) cat(sprintf("  power Δ=%.2f detect nominal=%.3f α_cal=%.3f (sd Δ̂ %.3f)\n", p$delta_true, p$detect_nominal, p$detect_alpha_cal, p$sd_value))
