#==============================================================================
# verdict_l2v1.R — PR-L2-ROLESLEEVE-V1 H1 판정 (v0 규칙 그대로 · 1회만 · 단계 3 뒤)
#
# 입력 = 4 arm(T_var·K·S·EW_all) 러너 산출물(runs_v1/<arm>/<run_id>/authoritative_remeasure.json · bt_result.rds) +
#        sanity_v1/sanity_v1.json(MC3) + verdict_v1/mc2_v1.json(MC2_v1 — PASS 여야 이 단계가 있다) + predictor_selection_IS.json(MC1).
# 수치는 R 계약으로만(lib_l2v1.R 가 계약 함수를 주입받아 부른다 — 재구현 없음):
#   H1 = beta_controlled_alpha(r_T_var, r_K, 252, nw_lag 3)$port_t · value = active_ann/252 · se = value/t
#   보조 = 같은 계약 lag 21 · S−K · T−S · T−EW_all · rf_prereg.R::rf_prereg_paired_boot(mean·calmar)
# 라벨(v0 규칙 · 초안 criteria·decision_params·implied_effect 를 읽어 집행 — lib l2v1_h1_label):
#   판본 불일치 = invalid · 잠금 전 측정 = invalid · MC3 미달 → undetermined · t ≤ −1.96 → failed · t ≥ 1.96 → confirmed ·
#   −1.96<t<1.96 ∧ (value − ie)/se ≤ −1.96 → powered_null(ie = 1%/yr) · 그 밖 → undetermined
# rf_prereg_verdict 미사용(등록 차단 — prereg_registration_attempt_v1.json) · rf_record_decision 기록 없음 · 쓰기 = verdict_v1/ (1회)
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("verdict_l2v1.R")'
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[verdict_l2v1] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
VD <- file.path(L2DIR, "verdict_v1"); out_v <- file.path(VD, "h1_verdict_v1.json")
if (file.exists(out_v)) stop("[verdict_l2v1] 판정은 1회 — 이미 있다: ", out_v)
PREREG_ID <- "PR-L2-ROLESLEEVE-V1"
sha <- function(p) digest::digest(file = p, algo = "sha256")
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jw1 <- function(x, p) { if (file.exists(p)) stop("[verdict_l2v1] 덮어쓰기 거부: ", p)
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p, useBytes = TRUE); sha(p) }
DESIGN <- fromJSON(file.path(L2DIR, "l2v1_design.json"), simplifyVector = FALSE)
ARMS <- names(DESIGN$arms)
source(file.path(L2DIR, "lib_l2v1.R"))

# ── 0. 사전등록 초안(무결성 · pins) ─────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
cfg <- rf_prereg_config(ROOT)
pr <- rf_prereg_load(PREREG_ID, "draft", root = ROOT, cfg = cfg)
integ <- attr(pr, "integrity")
idx <- Filter(function(r) identical(r$prereg_id, PREREG_ID) && identical(r$kind, "draft") && identical(as.integer(r$rev), as.integer(integ$rev)), rf_prereg_index(ROOT, cfg))
draft_written_at <- as.POSIXct(idx[[1]]$written_at, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
for (k in c("verdict", "lib", "design")) {
  p <- file.path(ROOT, pr$pins[[k]]$path)
  if (!identical(pr$pins[[k]]$sha256, sha(p))) stop(sprintf("[verdict_l2v1] %s sha256 ≠ 초안 pins.%s", pr$pins[[k]]$path, k))
}
IE <- as.numeric(pr$power$implied_effect$value)
T_LO <- as.numeric(Filter(function(p) identical(p$id, "t_crit_lo"), pr$decision_params)[[1]]$value)
T_HI <- as.numeric(Filter(function(p) identical(p$id, "t_crit_hi"), pr$decision_params)[[1]]$value)
MC3_THR <- as.numeric(pr$manipulation_checks$MC3$threshold)
stopifnot(is.finite(IE), IE > 0, is.finite(T_LO), is.finite(T_HI), T_LO < 0, T_HI > 0, is.finite(MC3_THR))
mc2p <- file.path(VD, "mc2_v1.json"); mc2 <- fromJSON(mc2p, simplifyVector = FALSE)
if (!isTRUE(mc2$pass)) stop("[verdict_l2v1] MC2_v1 PASS 아님 — 사전등록상 단계 3·판정 없음")
dir.create(VD, recursive = TRUE, showWarnings = FALSE)

# ── 1. arm 산출물(각 1건 · 잠금 뒤 측정 · 같은 판본) ─────────────────────────────
arm_dir <- function(a, base = file.path(L2DIR, "runs_v1")) {
  f <- list.files(file.path(base, a), pattern = "^authoritative_remeasure[.]json$", recursive = TRUE, full.names = TRUE)
  if (length(f) != 1L) stop(sprintf("[verdict_l2v1] arm %s 산출물 %d건 — 정확히 1건이어야 한다", a, length(f)))
  dirname(f)
}
read_ret <- function(d) { bt <- readRDS(file.path(d, "bt_result.rds")); as.data.table(bt$period_returns)[, .(date = as.Date(date), ret = as.numeric(ret_net))][order(date)] }
AUTH <- list(); RET <- list()
for (a in ARMS) {
  d <- arm_dir(a); au <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE)
  if (!identical(au$status, "OK")) stop(sprintf("[verdict_l2v1] arm %s auth status=%s", a, au$status))
  tm <- as.POSIXct(au$remeasured_at, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  pr_t <- read_ret(d)
  AUTH[[a]] <- list(dir = sub(paste0("^", ROOT, "/"), "", d), auth_sha256 = sha(file.path(d, "authoritative_remeasure.json")),
                    measured_after_draft = isTRUE(tm > draft_written_at), remeasured_at = au$remeasured_at,
                    essence_grade = au$essence_grade, essence = au$essence, exec_price = au$measurement_regime$exec_price,
                    data_cutoff = au$measurement_regime$data_cutoff %||% NA, fp_digest = au$measurement_regime$data_fingerprint$digest %||% NA,
                    n_max = au$replication$n_max, has_short = au$replication$has_short, n_days = nrow(pr_t),
                    first_day = format(min(pr_t$date)), last_day = format(max(pr_t$date)))
  RET[[a]] <- pr_t
}
fps <- unique(vapply(AUTH, function(z) as.character(z$fp_digest %||% NA), character(1)))
cuts <- unique(vapply(AUTH, function(z) as.character(z$data_cutoff %||% NA), character(1)))
regs <- unique(vapply(AUTH, function(z) as.character(z$exec_price %||% NA), character(1)))
vintage_ok <- length(fps) == 1L && !anyNA(fps) && length(cuts) == 1L && identical(cuts, DESIGN$window$data_cutoff) && identical(regs, "close_t1")
after_ok <- all(vapply(AUTH, function(z) isTRUE(z$measured_after_draft), logical(1)))

# ── 2. 짝지은 일간 대조 — beta_controlled_alpha 계약 ─────────────────────────────
bca_env <- new.env(parent = globalenv()); sys.source(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R"), envir = bca_env, keep.source = FALSE)
BCA <- bca_env$beta_controlled_alpha
H1 <- l2v1_contrast(RET$T_var, RET$K, "T_var-K", 3L, BCA)
H1_lag21 <- l2v1_contrast(RET$T_var, RET$K, "T_var-K", 21L, BCA)
SK <- l2v1_contrast(RET$S, RET$K, "S-K", 3L, BCA); TS <- l2v1_contrast(RET$T_var, RET$S, "T_var-S", 3L, BCA)
TEW <- l2v1_contrast(RET$T_var, RET$EW_all, "T_var-EW_all", 3L, BCA)
pTK <- merge(RET$T_var[, .(date, ra = ret)], RET$K[, .(date, rb = ret)], by = "date")
boot_mean <- rf_prereg_paired_boot(pTK$ra, pTK$rb, stat = "mean", root = ROOT, cfg = cfg)
boot_calmar <- rf_prereg_paired_boot(pTK$ra, pTK$rb, stat = "calmar", root = ROOT, cfg = cfg)

# ── 3. MC1 · MC2_v1 · MC3 · EW_all 재현(진단) ─────────────────────────────────────
isj <- fromJSON(file.path(L2DIR, "predictor_selection_IS.json"), simplifyVector = FALSE)
mv <- isj$results$MSM_asof_CrisisProb$variance
MC1 <- list(auc = mv$auc, ci95 = unlist(mv$ci95), pass = isTRUE(as.numeric(mv$ci95[[1]]) > 0.5),
            source = "predictor_selection_IS.json results.MSM_asof_CrisisProb.variance (IS · 기존 산출 · v0 와 같음)")
MC2 <- list(pass = mc2$pass, value = mc2$primary$value, t = mc2$primary$t, n_bear_months = mc2$window$n_bear_months,
            bear_beta_diff = mc2$secondary$bear_beta_diff$value, v0_style_sleeve = mc2$secondary$v0_style$sleeve_v1,
            path = "04_Research/l2_role_rotation/verdict_v1/mc2_v1.json", sha256 = sha(mc2p))
sres <- fromJSON(file.path(L2DIR, "sanity_v1/sanity_v1.json"), simplifyVector = FALSE)
MC3 <- list(value = sres$MC3$value, threshold = MC3_THR, pass = isTRUE(as.numeric(sres$MC3$value) >= MC3_THR),
            stock_level_T_K = sres$MC3b_stock_level$T_var_vs_K, source = "sanity_v1/sanity_v1.json (측정 전 · 비중만)")
ew0 <- tryCatch(read_ret(arm_dir("EW_all", file.path(L2DIR, "runs"))), error = function(e) NULL)
EWREP <- if (is.null(ew0)) list(status = "v0_unavailable") else {
  z <- merge(ew0[, .(date, r0 = ret)], RET$EW_all[, .(date, r1 = ret)], by = "date")
  list(status = "compared", n_common = nrow(z), n_v0 = nrow(ew0), n_v1 = nrow(RET$EW_all), max_abs_diff = max(abs(z$r0 - z$r1)),
       note = "v1 EW_all 은 v0 EW_all 과 같은 정의(슬리브 무시) — 같은 판본이면 같은 일간 수익(재현 대조 · 판정 무관)")
}

# ── 4. 라벨(사전등록 규칙 = v0 규칙) ──────────────────────────────────────────────
L <- l2v1_h1_label(H1, IE, T_LO, T_HI, MC3$pass, vintage_ok, after_ok)

# ── 5. 산출물(1회) ──────────────────────────────────────────────────────────────
regime <- list(exec_price = "close_t1", data_cutoff = DESIGN$window$data_cutoff, fp_digest = fps[1])
a_h1 <- jw1(c(H1, list(contract_file = "02_Infrastructure/contracts/beta_controlled_alpha.R", measurement_regime = regime)), file.path(VD, "h1_TvarK_beta_controlled_alpha_v1.json"))
a_bm <- jw1(c(boot_mean, list(target = "T_var-K", measurement_regime = regime)), file.path(VD, "boot_mean_TvarK_v1.json"))
a_bc <- jw1(c(boot_calmar, list(target = "T_var-K", measurement_regime = regime)), file.path(VD, "boot_calmar_TvarK_v1.json"))
grades <- lapply(AUTH, function(z) list(essence_grade = z$essence_grade, port_t = z$essence$portfolio_alpha_t_nw_lag3, net_sharpe = z$essence$net_sharpe,
                                         cagr = z$essence$cagr, mdd = z$essence$mdd, calmar = z$essence$calmar, oos_retention = z$essence$oos_retention,
                                         n_max = z$n_max, has_short = z$has_short, dir = z$dir, auth_sha256 = z$auth_sha256,
                                         remeasured_at = z$remeasured_at, n_days = z$n_days, first_day = z$first_day, last_day = z$last_day))
V <- list(schema = "l2v1_verdict_v1", prereg_id = PREREG_ID, prereg_draft = integ, at = now(), status = L$status, label = L$label,
          recorded_via_rf_prereg_verdict = FALSE,
          recorded_note = "사전등록 등록 차단(prereg_registration_attempt_v1.json) — 규칙은 초안(sha256 고정) 그대로 이 스크립트가 집행 · 1회(덮어쓰기 거부)",
          rule = list(t_lo = T_LO, t_hi = T_HI, implied_effect_daily = IE, implied_effect_ann = IE * 252, mc3_threshold = MC3_THR,
                      te = L$te, zero_in = L$zero_in, implied_excluded = L$implied_excluded,
                      text = "MC3 미달→undetermined · t≤t_lo→failed · t≥t_hi→confirmed · t_lo<t<t_hi ∧ (value−ie)/se≤t_lo→powered_null · 그 밖→undetermined (v0 규칙)"),
          H1 = H1, H1_robust_lag21 = H1_lag21, S_minus_K = SK, T_minus_S = TS, T_minus_EW_all = TEW,
          boot = list(mean = boot_mean[c("value", "se", "ci_lo", "ci_hi", "p_gt0", "block_len", "B", "seed", "valid_frac")],
                      calmar = boot_calmar[c("value", "se", "ci_lo", "ci_hi", "p_gt0", "block_len", "B", "seed", "valid_frac", "boot_bias")]),
          MC1 = MC1, MC2_v1 = MC2, MC3 = MC3, ew_all_reproduction_vs_v0 = EWREP,
          vintage = list(ok = vintage_ok, fingerprints = as.list(fps), cutoffs = as.list(cuts), exec_prices = as.list(regs)),
          measured_after_draft = after_ok, arms = grades,
          artifacts = list(h1 = list(path = "04_Research/l2_role_rotation/verdict_v1/h1_TvarK_beta_controlled_alpha_v1.json", sha256 = a_h1),
                           boot_mean = list(path = "04_Research/l2_role_rotation/verdict_v1/boot_mean_TvarK_v1.json", sha256 = a_bm),
                           boot_calmar = list(path = "04_Research/l2_role_rotation/verdict_v1/boot_calmar_TvarK_v1.json", sha256 = a_bc)),
          not_a_grade = "등급은 essence 하나 — 라벨은 H1(타이밍 기여) 반증 시도의 판정", scope = pr$scope)
v_sha <- jw1(V, out_v)
cat(sprintf("[verdict_l2v1] status=%s · label=%s · H1 t=%.3f (Δ %+.3f%%/yr) · MC2_v1 %s(t %.2f) · MC3 %.4f %s · 판본 %s · EW 재현 %s · %s\n",
            L$status, L$label %||% "NA", H1$t, H1$value_ann * 100, MC2$pass, MC2$t, MC3$value, MC3$pass, vintage_ok,
            if (is.list(EWREP) && identical(EWREP$status, "compared")) sprintf("%.2e", EWREP$max_abs_diff) else "NA", substr(v_sha, 1, 12)))
