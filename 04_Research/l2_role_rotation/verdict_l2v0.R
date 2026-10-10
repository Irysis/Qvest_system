#==============================================================================
# verdict_l2v0.R — PR-L2-ROLESLEEVE-V0 판정 (사전등록 규칙 그대로 · 1회만)
#
# 입력 = 5 arm 의 러너 산출물(runs/<arm>/<run_id>/authoritative_remeasure.json · bt_result.rds) + sanity/sanity_v0.json(MC3) +
#        predictor_selection_IS.json(MC1) + 모듈 계열(MC2). 수치는 R 계약으로만:
#   H1  = beta_controlled_alpha(r_T_var, r_K, periods_per_year=252, nw_lag=3)$port_t  (= mean(r_T−r_K) 의 NW lag-3 t ·
#         backtest_result_contract.R PORT_t 와 같은 규약 · measurement-graduation §2) · value = active_ann/252 · se = value/t
#   보조 = 같은 계약 nw_lag 21(보고) · rf_prereg.R::rf_prereg_paired_boot(stat mean·calmar · 설정 B·seed·블록) · S−K · T−K_eq · T−EW_all
#   MC1 = predictor_selection_IS.json MSM_asof_CrisisProb.variance.ci95 하한 > 0.5 (IS 전용 · 기존 산출)
#   MC2 = strategy_role.R::sr_card(방어 슬리브 월수익 · 사후 PS 국면 = 평가 표적 전용) 의 방어 평균 > 0 ∧
#         NW lag-3 t(backtest_result_contract.R::.nw_t_mean · 약세월 잔차 e = r − β·b) ≥ 1.0
#   MC3 = sanity_v0.json MC3(슬리브 처치 전달량 ≥ 0.05) — 미달이면 H1 = undetermined(처치 미전달)
# 라벨(사전등록 draft1 criteria · rf_prereg.R null_t_quantile 판정식과 같은 꼴):
#   MC3 미달 → undetermined(treatment_not_delivered) / t ≤ −1.96 → failed / t ≥ 1.96 → confirmed /
#   −1.96<t<1.96 ∧ (value − ie)/se ≤ −1.96 → powered_null (ie = SESOI 1%/yr = 0.01/252 일) / 그 밖 → undetermined
#   ★판본 대조: 5 arm 의 data_cutoff·data_fingerprint digest 가 다르면 판정하지 않는다(invalid: vintage_mismatch).
# ★rf_prereg_verdict 미사용 사유: 사전등록이 등록(registered) 단계로 못 올라갔다(L2 바닥 부재 등 — prereg_registration_attempt_v0.json).
#   판정 규칙은 초안(sha256 고정)에 있고 이 스크립트가 그대로 집행한다. rf_record_decision 기록 없음(등록본 전용 경로).
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("verdict_l2v0.R")' · 쓰기 = verdict/ (덮어쓰기 거부 = 1회 판정)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(xts) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[verdict_l2v0] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
VD <- file.path(L2DIR, "verdict"); out_v <- file.path(VD, "h1_verdict_v0.json")
if (file.exists(out_v)) stop("[verdict_l2v0] 판정은 1회 — 이미 있다: ", out_v)
dir.create(VD, recursive = TRUE, showWarnings = FALSE)
PREREG_ID <- "PR-L2-ROLESLEEVE-V0"
sha <- function(p) digest::digest(file = p, algo = "sha256")
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
jw1 <- function(x, p) { if (file.exists(p)) stop("[verdict_l2v0] 덮어쓰기 거부: ", p)
  writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p, useBytes = TRUE); sha(p) }
DESIGN <- fromJSON(file.path(L2DIR, "l2v0_design.json"), simplifyVector = FALSE)
ARMS <- names(DESIGN$arms)

# ── 0. 사전등록 초안(무결성) ─────────────────────────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
cfg <- rf_prereg_config(ROOT)
pr <- rf_prereg_load(PREREG_ID, "draft", root = ROOT, cfg = cfg)
integ <- attr(pr, "integrity")
idx <- Filter(function(r) identical(r$prereg_id, PREREG_ID), rf_prereg_index(ROOT, cfg))
draft_written_at <- as.POSIXct(idx[[length(idx)]]$written_at, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
IE <- as.numeric(pr$power$implied_effect$value)
T_LO <- as.numeric(Filter(function(p) identical(p$id, "t_crit_lo"), pr$decision_params)[[1]]$value)
T_HI <- as.numeric(Filter(function(p) identical(p$id, "t_crit_hi"), pr$decision_params)[[1]]$value)
MC3_THR <- as.numeric(pr$manipulation_checks$MC3$threshold)
MC2_T_THR <- as.numeric(pr$manipulation_checks$MC2$nw_t_threshold)
stopifnot(is.finite(IE), IE > 0, is.finite(T_LO), is.finite(T_HI), T_LO < 0, T_HI > 0, is.finite(MC3_THR), is.finite(MC2_T_THR))

# ── 1. arm 산출물(각 1건 · 등록 뒤 측정 · 같은 판본) ─────────────────────────────
arm_dir <- function(a) {
  f <- list.files(file.path(L2DIR, "runs", a), pattern = "^authoritative_remeasure[.]json$", recursive = TRUE, full.names = TRUE)
  if (length(f) != 1L) stop(sprintf("[verdict_l2v0] arm %s 산출물 %d건 — 정확히 1건이어야 한다", a, length(f)))
  dirname(f)
}
AUTH <- list(); RET <- list()
for (a in ARMS) {
  d <- arm_dir(a); au <- fromJSON(file.path(d, "authoritative_remeasure.json"), simplifyVector = FALSE)
  if (!identical(au$status, "OK")) stop(sprintf("[verdict_l2v0] arm %s auth status=%s", a, au$status))
  tm <- as.POSIXct(au$remeasured_at, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  bt <- readRDS(file.path(d, "bt_result.rds"))
  pr_t <- as.data.table(bt$period_returns)[, .(date = as.Date(date), ret = as.numeric(ret_net))][order(date)]
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

# ── 2. 짝지은 일간 차 — beta_controlled_alpha 계약 ────────────────────────────────
source(file.path(ROOT, "02_Infrastructure/contracts/beta_controlled_alpha.R"))
pair <- function(a, b) {
  x <- merge(RET[[a]][, .(date, ra = ret)], RET[[b]][, .(date, rb = ret)], by = "date")
  list(x = x, common_frac = nrow(x) / max(nrow(RET[[a]]), nrow(RET[[b]])))
}
contrast <- function(a, b, lag = 3L) {
  p <- pair(a, b); r <- beta_controlled_alpha(p$x$ra, p$x$rb, periods_per_year = 252, nw_lag = lag)
  v <- r$active_ann / 252; t <- r$port_t; se <- if (is.finite(t) && t != 0) v / t else NA_real_
  list(target = paste0(a, "-", b), contract = "beta_controlled_alpha", nw_lag = lag, n = r$n, n_dropped = r$n_dropped,
       common_frac = p$common_frac, value = v, value_ann = r$active_ann, t = t, se = se,
       ci_level = 0.90, ci_lo = v - stats::qnorm(0.95) * se, ci_hi = v + stats::qnorm(0.95) * se,
       t_alpha = r$t_alpha, alpha_ann = r$alpha_ann, beta = r$beta, t_beta = r$t_beta)
}
H1 <- contrast("T_var", "K", 3L)
H1_lag21 <- contrast("T_var", "K", 21L)
SK <- contrast("S", "K", 3L); TKeq <- contrast("T_var", "K_eq", 3L); TEW <- contrast("T_var", "EW_all", 3L); TS <- contrast("T_var", "S", 3L)
pTK <- pair("T_var", "K")
boot_mean <- rf_prereg_paired_boot(pTK$x$ra, pTK$x$rb, stat = "mean", root = ROOT, cfg = cfg)
boot_calmar <- rf_prereg_paired_boot(pTK$x$ra, pTK$x$rb, stat = "calmar", root = ROOT, cfg = cfg)

# ── 3. MC1 · MC2 · MC3 ──────────────────────────────────────────────────────────
isj <- fromJSON(file.path(L2DIR, "predictor_selection_IS.json"), simplifyVector = FALSE)
mv <- isj$results$MSM_asof_CrisisProb$variance
MC1 <- list(auc = mv$auc, ci95 = unlist(mv$ci95), ci_bonf = unlist(mv$ci_bonf), pass = isTRUE(as.numeric(mv$ci95[[1]]) > 0.5),
            source = "predictor_selection_IS.json results.MSM_asof_CrisisProb.variance (IS 2005-01~2015-12 · 블록 부트스트랩 B=5000 · 기존 산출)")
sres <- fromJSON(file.path(L2DIR, "sanity/sanity_v0.json"), simplifyVector = FALSE)
MC3 <- list(value = sres$MC3$value, threshold = MC3_THR, pass = isTRUE(as.numeric(sres$MC3$value) >= MC3_THR),
            stock_level_T_K = sres$MC3b_stock_level$T_var_vs_K, source = "sanity/sanity_v0.json (측정 전 · 비중만)")
# MC2 — 방어 슬리브(as-of phase · 후보 교집합 · 동일가중) 월수익 → strategy_role.R 계약
source(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R"))
scfg <- sr_cfg(ROOT); dcfg <- .sr_env$rfd_cfg(ROOT)
bm <- .sr_env$rfd_bench_daily(ROOT, dcfg); fac <- .sr_env$rfd_factor_monthly(ROOT, dcfg); R <- sr_regimes(bm)
cand <- fread(file.path(L2DIR, "work/l2v0_candidates.csv"))
ar <- as.data.table(arrow::read_parquet(file.path(ROOT, DESIGN$labels$file)))[ps_confirm == DESIGN$labels$ps_confirm & role == "defensive" & is_member == TRUE]
ar[, ym := format(as.Date(decision_date), "%Y-%m")]
hm_ym <- format(seq(as.Date(DESIGN$window$first_holding_month), as.Date(DESIGN$window$last_holding_month), by = "month"), "%Y-%m")
mon <- rbindlist(lapply(seq_len(nrow(cand)), function(i) {
  s <- .sr_env$rfd_read_series(file.path(ROOT, cand$series_dir[i], "03_period_returns.csv"))
  m <- .sr_env$rfd_monthly(s, bm, NULL)
  if (is.null(m)) return(NULL)
  m[, .(member_id = cand$member_id[i], ym, r)]
}))
dm <- merge(ar[ym %in% hm_ym & member_id %in% cand$member_id, .(ym, member_id)], mon, by = c("ym", "member_id"))
sleeve <- dm[is.finite(r), .(r = mean(r), n_members_with_return = .N), by = ym][order(ym)]
bmm <- bm[, .(b = prod(1 + bm) - 1), by = .(ym = format(date, "%Y-%m"))]
mdt <- merge(merge(sleeve[, .(ym, r)], bmm, by = "ym"), fac, by = "ym", all.x = TRUE)[ym %in% hm_ym][order(ym)]
card <- sr_card(mdt, R, scfg)
bt_env <- new.env(parent = globalenv())
for (e in as.list(parse(file.path(ROOT, "02_Infrastructure/contracts/backtest_result_contract.R"), encoding = "UTF-8", keep.source = FALSE)))
  if (is.call(e) && identical(as.character(e[[1]]), "<-") && is.name(e[[2]]) && identical(as.character(e[[2]]), ".nw_t_mean")) eval(e, bt_env)
mm2 <- merge(mdt, R, by = "ym")[order(ym)]
e_res <- mm2$r - card$beta * mm2$b
bear <- mm2$ps_bear %in% TRUE
nw_t_bear <- bt_env$.nw_t_mean(e_res[bear], lag = as.integer(scfg$grading$nw_lag %||% 3L))
MC2 <- list(n_months = card$n_months, beta = card$beta, n_bear_months = sum(bear), mean_bear_resid = card$roles$defensive$mean,
            mean_bear_resid_recomputed = mean(e_res[bear]), t_plain = card$roles$defensive$t, nw_t = nw_t_bear,
            nw_t_threshold = MC2_T_THR, members_per_month = list(min = min(sleeve$n_members_with_return), median = stats::median(sleeve$n_members_with_return), max = max(sleeve$n_members_with_return)),
            pass = isTRUE(card$roles$defensive$mean > 0) && isTRUE(nw_t_bear >= MC2_T_THR),
            source = "strategy_role.R::sr_card(방어 슬리브 월수익 · 사후 PS = 평가 표적 전용) + backtest_result_contract.R::.nw_t_mean(lag 3)")

# ── 4. 라벨(사전등록 규칙) ─────────────────────────────────────────────────────
te <- if (is.finite(H1$se) && H1$se > 0) (H1$value - IE) / H1$se else NA_real_
zero_in <- is.finite(H1$t) && H1$t > T_LO && H1$t < T_HI
excl_ie <- is.finite(te) && te <= T_LO
label <- if (!vintage_ok || !after_ok) NA_character_ else if (!MC3$pass) "undetermined" else if (is.finite(H1$t) && H1$t <= T_LO) "failed" else
         if (is.finite(H1$t) && H1$t >= T_HI) "confirmed" else if (zero_in && excl_ie) "powered_null" else "undetermined"
status <- if (!vintage_ok) "invalid:vintage_mismatch" else if (!after_ok) "invalid:measured_before_lock" else if (!MC3$pass) "concluded:treatment_not_delivered" else "concluded"

# ── 5. 산출물(1회) ──────────────────────────────────────────────────────────────
regime <- list(exec_price = "close_t1", data_cutoff = DESIGN$window$data_cutoff, fp_digest = fps[1])
a_h1 <- jw1(c(H1, list(contract_file = "02_Infrastructure/contracts/beta_controlled_alpha.R", measurement_regime = regime)), file.path(VD, "h1_TvarK_beta_controlled_alpha.json"))
a_bm <- jw1(c(boot_mean, list(target = "T_var-K", measurement_regime = regime)), file.path(VD, "boot_mean_TvarK.json"))
a_bc <- jw1(c(boot_calmar, list(target = "T_var-K", measurement_regime = regime)), file.path(VD, "boot_calmar_TvarK.json"))
a_mc2 <- jw1(c(MC2, list(sleeve_monthly = lapply(seq_len(nrow(mdt)), function(i) list(ym = mdt$ym[i], r = mdt$r[i], b = mdt$b[i])))), file.path(VD, "mc2_defensive_sleeve.json"))
grades <- lapply(AUTH, function(z) list(essence_grade = z$essence_grade, port_t = z$essence$portfolio_alpha_t_nw_lag3, net_sharpe = z$essence$net_sharpe,
                                         cagr = z$essence$cagr, mdd = z$essence$mdd, calmar = z$essence$calmar, oos_retention = z$essence$oos_retention,
                                         n_max = z$n_max, has_short = z$has_short, dir = z$dir, auth_sha256 = z$auth_sha256))
V <- list(schema = "l2v0_verdict_v1", prereg_id = PREREG_ID, prereg_draft = integ, at = now(), status = status, label = label,
          recorded_via_rf_prereg_verdict = FALSE,
          recorded_note = "사전등록이 registered 로 못 올라가(prereg_registration_attempt_v0.json) rf_prereg_verdict·rf_record_decision 미사용 — 규칙은 초안(sha256 고정) 그대로 이 스크립트가 집행 · 1회(덮어쓰기 거부)",
          rule = list(t_lo = T_LO, t_hi = T_HI, implied_effect_daily = IE, implied_effect_ann = IE * 252, mc3_threshold = MC3_THR,
                      te = te, zero_in = zero_in, implied_excluded = excl_ie,
                      text = "MC3 미달→undetermined · t≤t_lo→failed · t≥t_hi→confirmed · t_lo<t<t_hi ∧ (value−ie)/se≤t_lo→powered_null · 그 밖→undetermined"),
          H1 = H1, H1_robust_lag21 = H1_lag21, S_minus_K = SK, T_minus_S = TS, T_minus_K_eq = TKeq, T_minus_EW_all = TEW,
          boot = list(mean = boot_mean[c("value", "se", "ci_lo", "ci_hi", "p_gt0", "block_len", "B", "seed", "valid_frac")],
                      calmar = boot_calmar[c("value", "se", "ci_lo", "ci_hi", "p_gt0", "block_len", "B", "seed", "valid_frac", "boot_bias")]),
          MC1 = MC1, MC2 = MC2, MC3 = MC3,
          vintage = list(ok = vintage_ok, fingerprints = as.list(fps), cutoffs = as.list(cuts), exec_prices = as.list(regs)),
          measured_after_draft = after_ok, arms = grades,
          artifacts = list(h1 = list(path = "04_Research/l2_role_rotation/verdict/h1_TvarK_beta_controlled_alpha.json", sha256 = a_h1),
                           boot_mean = list(path = "04_Research/l2_role_rotation/verdict/boot_mean_TvarK.json", sha256 = a_bm),
                           boot_calmar = list(path = "04_Research/l2_role_rotation/verdict/boot_calmar_TvarK.json", sha256 = a_bc),
                           mc2 = list(path = "04_Research/l2_role_rotation/verdict/mc2_defensive_sleeve.json", sha256 = a_mc2)),
          not_a_grade = "등급은 essence 하나 — 라벨은 H1(타이밍 기여) 반증 시도의 판정", scope = pr$scope)
v_sha <- jw1(V, out_v)
cat(sprintf("[verdict_l2v0] status=%s · label=%s · H1 t=%.3f (Δ %.4f%%/yr) · MC1 %s · MC2 %s(NW t %.2f) · MC3 %.4f %s · 판본 %s · %s\n",
            status, label %||% "NA", H1$t, H1$value_ann * 100, MC1$pass, MC2$pass, MC2$nw_t, MC3$value, MC3$pass, vintage_ok, substr(v_sha, 1, 12)))
