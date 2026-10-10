#==============================================================================
# build_l2v1_labels.R — PR-L2-ROLESLEEVE-V1 방어 슬리브 v1 라벨(as-of 하방 베타 β− 하위 삼분위) · 사전등록 잠금 뒤 1회
#
# 정의(l2v1_design.json#defensive_v1 · 초안 pins 가 이 파일·lib_l2v1.R·설계의 sha256 을 고정):
#   결정일 dd = 보유월 첫날(2015-10-01 … 2026-09-01 · 132). 창 W(dd) = 정본 벤치 거래일 중 date < dd 인 마지막 252일(t−1 에서 끝).
#   후보 i(v0 후보 65) 적격 ⇔ W(dd) 252일 전부에 유한 ret_net ∧ β− 유한.
#   β−_i = cov(r_i, r_m | r_m < μ_m) / var(r_m | r_m < μ_m) (Ang, Chen & Xing 2006 eq.1) · 슬리브 = 적격 중 β− 오름차순 상위 ceiling(n/3).
#   진단(선택 불가): FP(2014) 총 베타 β_TS · v0 as-of 방어 라벨(asof_roles.parquet phase defensive) 소속·t.
# PIT: 라벨이 읽는 자료는 전부 date < dd. 매 실행 누출 대조(결정일 3개 — 처음·가운데·끝):
#   (음성 3종) dd 이후 자료 전부 ①잡음 교체 ②충격 교체(벤치 −5% 근방 · 모듈 잡음) ③삭제 → 라벨(적격·β−·순위·소속) 비트 동일(아니면 중단)
#   (양성 2종) 일부러 dd 이후를 넣는 '틀린' 창(lib l2v1_window leak=k): ①1일 누출 × 충격 교체 ②21일(≈1개월 동월) 누출 × 잡음 교체
#     → β− 가 바뀌어야 한다 = 계기 발화 실증(아니면 중단). ★1일 누출 × 일반 잡음은 발화가 보장되지 않는다 — β− 는 상승일을
#     보지 않으므로 교란된 그날이 상승일로 남으면 값이 같다(잠금 전 드라이런 실측 2013-11-01) → 충격 교체로 하락일을 강제한다.
# 입력(읽기 전용): work/l2v0_candidates.csv(v0 후보 · 동결) · 각 후보 계열 03_period_returns.csv(rfd_read_series) ·
#   .cache/benchmark.parquet BM_Ret(rfd_bench_daily) · asof_roles.parquet(진단) — 수익률을 읽지만 결과 지표(MC2·H1)는 계산하지 않는다.
# 쓰기(덮어쓰기 거부): work/l2v1_defensive_labels.parquet · work/l2v1_labels_summary.json · work/l2v1_inputs_manifest.json
#   L2V1_DRYRUN=1 = 잠금 전 코드 검사: L2V1_OUT_DIR(이 디렉터리 밖)에만 쓰고 결정일 = L2V1_DRY_FIRST~L2V1_DRY_LAST(< 평가 창 첫 보유월).
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("build_l2v1_labels.R")'
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[l2v1_labels] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
PREREG_ID <- "PR-L2-ROLESLEEVE-V1"
sha <- function(p) digest::digest(file = p, algo = "sha256")
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
rel <- function(p) sub(paste0("^", ROOT, "/"), "", normalizePath(p, winslash = "/"))
fpi <- function(p) list(path = rel(p), sha256 = sha(p), bytes = file.info(p)$size, mtime = format(file.info(p)$mtime, "%Y-%m-%dT%H:%M:%S%z"))
SELF <- file.path(L2DIR, "build_l2v1_labels.R"); LIB <- file.path(L2DIR, "lib_l2v1.R"); DESIGN_P <- file.path(L2DIR, "l2v1_design.json")
DESIGN <- fromJSON(DESIGN_P, simplifyVector = FALSE)
source(LIB)
DV <- DESIGN$defensive_v1
WIN <- as.integer(DV$window_days); MIN_OBS <- as.integer(DV$min_obs)
stopifnot(WIN >= 2L, MIN_OBS == WIN)

# ── 0. 모드 · 출력 · 잠금 대조 ────────────────────────────────────────────────────
DRY <- identical(Sys.getenv("L2V1_DRYRUN", ""), "1")
first_hm <- as.Date(DESIGN$window$first_holding_month); last_hm <- as.Date(DESIGN$window$last_holding_month)
if (DRY) {
  OUT <- Sys.getenv("L2V1_OUT_DIR", "")
  if (!nzchar(OUT)) stop("[l2v1_labels] 드라이런은 L2V1_OUT_DIR 필수")
  OUT <- normalizePath(OUT, winslash = "/", mustWork = FALSE)
  if (startsWith(tolower(OUT), tolower(normalizePath(L2DIR, winslash = "/")))) stop("[l2v1_labels] 드라이런 출력은 이 디렉터리 밖이어야 한다")
  DDS <- seq(as.Date(Sys.getenv("L2V1_DRY_FIRST")), as.Date(Sys.getenv("L2V1_DRY_LAST")), by = "month")
  if (!length(DDS) || max(DDS) >= first_hm) stop("[l2v1_labels] 드라이런 결정일은 평가 창 첫 보유월보다 앞이어야 한다(창 자료 미접촉)")
  LOCK <- list(mode = "dryrun", note = "잠금 전 코드 검사 — 평가 창 결정일 없음")
} else {
  OUT <- file.path(L2DIR, "work")
  DDS <- seq(first_hm, last_hm, by = "month")
  source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"))
  pcfg <- rf_prereg_config(ROOT)
  pr <- rf_prereg_load(PREREG_ID, "draft", root = ROOT, cfg = pcfg)        # 색인 sha256 대조(변조 거부)
  integ <- attr(pr, "integrity")
  irow <- Filter(function(r) identical(r$prereg_id, PREREG_ID) && identical(r$kind, "draft") && identical(as.integer(r$rev), as.integer(integ$rev)),
                 rf_prereg_index(ROOT, pcfg))[[1]]
  need <- list(labels_builder = SELF, lib = LIB, design = DESIGN_P)
  for (k in names(need)) if (!identical(pr$pins[[k]]$sha256, sha(need[[k]])))
    stop(sprintf("[l2v1_labels] %s sha256 ≠ 사전등록 초안 pins.%s — 잠금 뒤 코드/설계가 바뀌었다(개정 = 새 초안 rev)", rel(need[[k]]), k))
  LOCK <- list(mode = "production", prereg_id = PREREG_ID, draft_path = integ$path, draft_sha256 = integ$sha256, draft_rev = integ$rev,
               draft_written_at = irow$written_at, verified_at = now())
}
out_lab <- file.path(OUT, "l2v1_defensive_labels.parquet"); out_sum <- file.path(OUT, "l2v1_labels_summary.json")
out_man <- file.path(OUT, "l2v1_inputs_manifest.json")
for (p in c(out_lab, out_sum, out_man)) if (file.exists(p)) stop("[l2v1_labels] 덮어쓰기 거부(1회 생성): ", p)
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── 1. 자료(정본 판독기) ────────────────────────────────────────────────────────
G <- new.env(parent = globalenv())
sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_diversification_gate.R"), envir = G, keep.source = FALSE)
dcfg <- G$rfd_cfg(ROOT)
bm <- G$rfd_bench_daily(ROOT, dcfg)                                              # date · bm (BM_Ret)
bench_path <- attr(bm, "rfd_path")
if (!identical(normalizePath(bench_path, winslash = "/"), normalizePath(file.path(ROOT, ".cache/benchmark.parquet"), winslash = "/")))
  stop("[l2v1_labels] 정본 벤치 경로가 .cache/benchmark.parquet 가 아니다: ", bench_path)
setorder(bm, date)
if (anyDuplicated(bm$date)) stop("[l2v1_labels] 벤치 날짜 중복")
CAL <- bm$date; RMV <- as.numeric(bm$bm)
cand <- fread(file.path(ROOT, DESIGN$candidates$file))
if (nrow(cand) != as.integer(DESIGN$candidates$expected_n) || anyDuplicated(cand$member_id)) stop("[l2v1_labels] 후보 수/중복 이상")
setorder(cand, member_id)
M <- matrix(NA_real_, nrow = length(CAL), ncol = nrow(cand), dimnames = list(NULL, cand$member_id))
ser_meta <- vector("list", nrow(cand))
for (i in seq_len(nrow(cand))) {
  p <- file.path(ROOT, cand$series_dir[i], "03_period_returns.csv")
  s <- G$rfd_read_series(p)
  if (is.null(s) || !identical(s$freq, "daily")) stop(sprintf("[l2v1_labels] %s: 일간 계열 판독 실패", cand$member_id[i]))
  dt <- s$dt[is.finite(ret)]
  if (anyDuplicated(dt$date)) stop(sprintf("[l2v1_labels] %s: 날짜 중복", cand$member_id[i]))
  ix <- match(dt$date, CAL)
  M[ix[!is.na(ix)], i] <- dt$ret[!is.na(ix)]
  ser_meta[[i]] <- list(member_id = cand$member_id[i], path = rel(p), sha256 = sha(p), first = format(min(dt$date)), last = format(max(dt$date)),
                        n = nrow(dt), n_off_bench_calendar = sum(is.na(ix)))
}

# ── 2. 결정일 1개 라벨 ───────────────────────────────────────────────────────────
lab_one <- function(dd, M, rmv, cal, leak = 0L) {
  W <- l2v1_window(cal, dd, WIN, leak = leak)
  if (is.null(W)) stop(sprintf("[l2v1_labels] %s: 벤치 창 %d일 부족", format(dd), WIN))
  rmw <- rmv[W]
  n_obs <- colSums(is.finite(M[W, , drop = FALSE]))
  bmv <- t(vapply(seq_len(ncol(M)), function(i) {
    if (n_obs[i] < MIN_OBS) return(c(beta = NA_real_, n_down = NA_real_, mu = NA_real_))
    l2v1_beta_minus(M[W, i], rmw)
  }, numeric(3)))
  ter <- l2v1_low_tercile(bmv[, "beta"], colnames(M))
  data.table(decision_date = dd, member_id = colnames(M), eligible = is.finite(bmv[, "beta"]), n_obs = as.integer(n_obs),
             n_down = as.integer(bmv[, "n_down"]), mu_m = bmv[, "mu"], beta_minus = bmv[, "beta"], rank_bm = ter$rank,
             n_eligible = ter$n, n_low = ter$k, in_sleeve = ter$in_sleeve, window_first = cal[W[1]], window_last = cal[W[length(W)]])
}
fp_one <- function(dd, M, rmv, cal) {
  W1 <- l2v1_window(cal, dd, WIN)
  i5 <- which(cal < dd); W5 <- utils::tail(i5, 5L * WIN)                    # 5년 = 5 × 252 (FP 2014 §3.1)
  lm1 <- log1p(rmv[W1]); lm5 <- log1p(rmv[W5])
  v <- t(vapply(seq_len(ncol(M)), function(i) l2v1_fp_beta(log1p(M[W1, i]), lm1, log1p(M[W5, i]), lm5), numeric(6)))
  data.table(member_id = colnames(M), fp_beta_ts = v[, "beta_ts"], fp_sigma_i = v[, "sigma_i"], fp_sigma_m = v[, "sigma_m"],
             fp_rho = v[, "rho"], fp_n_vol = as.integer(v[, "n_vol"]), fp_n_cor = as.integer(v[, "n_cor"]))
}

LAB <- rbindlist(lapply(DDS, function(dd) merge(lab_one(dd, M, RMV, CAL), fp_one(dd, M, RMV, CAL), by = "member_id")))
LAB <- merge(LAB, cand[, .(member_id, module_key)], by = "member_id")
if (any(LAB$window_last >= LAB$decision_date)) stop("[l2v1_labels] PIT: 창 끝이 결정일 이후")

# v0 as-of 방어 라벨(진단)
ar <- as.data.table(read_parquet(file.path(ROOT, DESIGN$labels_other_roles$file)))
v0d <- ar[ps_confirm == DESIGN$labels_other_roles$ps_confirm & role == "defensive" & decision_date %in% DDS & member_id %in% cand$member_id,
          .(decision_date = as.Date(decision_date), member_id, v0_def_member = is_member %in% TRUE, v0_def_t = t)]
LAB <- merge(LAB, v0d, by = c("decision_date", "member_id"), all.x = TRUE)
LAB[is.na(v0_def_member), v0_def_member := FALSE]
setcolorder(LAB, c("decision_date", "member_id", "module_key"))
setorder(LAB, decision_date, member_id)

# ── 3. 누출 대조(음성 2종 + 양성) ─────────────────────────────────────────────────
KEYC <- c("member_id", "eligible", "n_obs", "beta_minus", "rank_bm", "in_sleeve")
same <- function(a, b) identical(a[order(member_id), ..KEYC], b[order(member_id), ..KEYC])
ctrl_dd <- unique(DDS[unique(c(1L, ceiling(length(DDS) / 2), length(DDS)))])
n_chg <- function(x, y) { a0 <- x$beta_minus; a1 <- y$beta_minus; sum((is.finite(a0) != is.finite(a1)) | (is.finite(a0) & is.finite(a1) & a0 != a1)) }
CTRL <- lapply(ctrl_dd, function(dd) {
  base <- lab_one(dd, M, RMV, CAL)
  fut <- CAL >= dd
  set.seed(as.integer(DESIGN$control_seed))
  M2 <- M; M2[fut, ] <- stats::rnorm(sum(fut) * ncol(M), 0, 0.05)              # ① 잡음: 값·존재 모두 교란(결측이던 자리도 채운다)
  R2 <- RMV; R2[fut] <- stats::rnorm(sum(fut), 0, 0.05)
  R3 <- RMV; R3[fut] <- -0.05 + stats::rnorm(sum(fut), 0, 0.005)               # ② 충격: 결정일 이후 벤치 = 큰 하락일(β− 가 보는 날로 강제)
  neg_noise <- same(base, lab_one(dd, M2, R2, CAL))
  neg_shock <- same(base, lab_one(dd, M2, R3, CAL))
  neg_delete <- same(base, lab_one(dd, M[!fut, , drop = FALSE], RMV[!fut], CAL[!fut]))
  pos_1d <- n_chg(lab_one(dd, M, RMV, CAL, leak = 1L), lab_one(dd, M2, R3, CAL, leak = 1L))
  pos_21d <- n_chg(lab_one(dd, M, RMV, CAL, leak = 21L), lab_one(dd, M2, R2, CAL, leak = 21L))
  list(decision_date = format(dd), negative_noise_identical = neg_noise, negative_shock_identical = neg_shock, negative_delete_identical = neg_delete,
       positive_leak1d_shock_changed = pos_1d, positive_leak21d_noise_changed = pos_21d, positive_fired = pos_1d > 0L && pos_21d > 0L)
})
ctrl_ok <- all(vapply(CTRL, function(z) isTRUE(z$negative_noise_identical) && isTRUE(z$negative_shock_identical) &&
                        isTRUE(z$negative_delete_identical) && isTRUE(z$positive_fired), logical(1)))
if (!ctrl_ok) stop("[l2v1_labels] 누출 대조 실패: ", toJSON(CTRL, auto_unbox = TRUE))

# ── 4. 요약(라벨 수준 진단 — 평가 창 성과 미계산) ─────────────────────────────────
sp <- function(x, y) { ok <- is.finite(x) & is.finite(y); if (sum(ok) < 5L) NA_real_ else suppressWarnings(stats::cor(x[ok], y[ok], method = "spearman")) }
BY <- LAB[, {
  el <- eligible %in% TRUE
  fp_ok <- el & is.finite(fp_beta_ts)
  fpt <- l2v1_low_tercile(ifelse(fp_ok, fp_beta_ts, NA_real_), member_id)
  bmt <- l2v1_low_tercile(ifelse(fp_ok, beta_minus, NA_real_), member_id)                 # 같은 부분집합에서 β− 삼분위(겹침 비교용)
  v0m <- v0_def_member & el
  .(n_eligible = n_eligible[1], n_low = n_low[1], n_in_sleeve = sum(in_sleeve),
    n_v0_def = sum(v0m), overlap_v0 = sum(in_sleeve & v0m),
    jaccard_v0 = { u <- sum(in_sleeve | v0m); if (u) sum(in_sleeve & v0m) / u else NA_real_ },
    n_fp = sum(fp_ok), overlap_fp_low = sum(fpt$in_sleeve & bmt$in_sleeve), k_fp = fpt$k,
    spearman_bm_fp = sp(beta_minus[el], fp_beta_ts[el]), spearman_bm_v0t = sp(beta_minus[el], v0_def_t[el]),
    mean_bm_sleeve = mean(beta_minus[in_sleeve]), mean_bm_elig = mean(beta_minus[el]),
    mean_fp_sleeve = mean(fp_beta_ts[in_sleeve & is.finite(fp_beta_ts)]), mean_fp_elig = mean(fp_beta_ts[fp_ok]))
}, by = decision_date][order(decision_date)]
mem_by <- split(LAB[in_sleeve == TRUE]$member_id, LAB[in_sleeve == TRUE]$decision_date)
turn <- vapply(seq_along(mem_by)[-1], function(j) { a <- mem_by[[j - 1L]]; b <- mem_by[[j]]; length(union(setdiff(a, b), setdiff(b, a))) / (length(a) + length(b)) }, numeric(1))
q3 <- function(x) { x <- x[is.finite(x)]; if (!length(x)) return(list(min = NA, median = NA, max = NA, mean = NA)); list(min = min(x), median = stats::median(x), max = max(x), mean = mean(x)) }
SUM <- list(
  schema = "l2v1_labels_summary_v1", prereg_id = PREREG_ID, built_at = now(), lock = LOCK,
  definition = DV[c("definition", "estimator", "window_rule", "eligibility", "down_day_rule", "tercile")],
  n_decision_dates = length(DDS), first_decision = format(min(DDS)), last_decision = format(max(DDS)),
  sleeve_size = list(n_eligible = q3(BY$n_eligible), n_low = q3(BY$n_low),
                     distinct = lapply(split(BY, by = c("n_eligible", "n_low"), keep.by = TRUE), function(z)
                       list(n_eligible = z$n_eligible[1], n_low = z$n_low[1], n_months = nrow(z), first = format(min(z$decision_date)), last = format(max(z$decision_date))))),
  sleeve_turnover_monthly = q3(turn), months_with_change = sum(turn > 0),
  diagnostics = list(overlap_v0_share_of_sleeve = q3(BY$overlap_v0 / BY$n_low), jaccard_v0 = q3(BY$jaccard_v0),
                     spearman_bm_fp = q3(BY$spearman_bm_fp), overlap_fp_low_share = q3(BY$overlap_fp_low / BY$k_fp),
                     spearman_bm_v0t = q3(BY$spearman_bm_v0t), mean_bm_sleeve = q3(BY$mean_bm_sleeve), mean_bm_elig = q3(BY$mean_bm_elig),
                     mean_fp_sleeve = q3(BY$mean_fp_sleeve), mean_fp_elig = q3(BY$mean_fp_elig),
                     note = "라벨 수준 진단(결정일 이전 자료만) — 선택 입력 아님 · 평가 창 성과와 무관"),
  controls = list(leakage = CTRL, all_ok = ctrl_ok),
  by_date = lapply(seq_len(nrow(BY)), function(i) { z <- as.list(BY[i]); z$decision_date <- format(z$decision_date); z }),
  series = list(n = length(ser_meta), first_min = min(vapply(ser_meta, `[[`, "", "first")), first_max = max(vapply(ser_meta, `[[`, "", "first")),
                last_min = min(vapply(ser_meta, `[[`, "", "last")), last_max = max(vapply(ser_meta, `[[`, "", "last")),
                off_calendar_days = sum(vapply(ser_meta, function(z) as.numeric(z$n_off_bench_calendar), numeric(1)))))

# ── 5. 쓰기 ────────────────────────────────────────────────────────────────────
arrow::write_parquet(LAB, out_lab)
writeLines(toJSON(SUM, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out_sum, useBytes = TRUE)
MAN <- list(
  schema = "l2v1_inputs_manifest_v1", prereg_id = PREREG_ID, built_at = now(), lock = LOCK,
  builder = fpi(SELF), lib = fpi(LIB),
  note = "엔진 v1(allocator_engine_v1.R)이 files 의 sha256 을 전부 대조한다. provenance = 라벨 원천(벤치·모듈 계열) 지문(대조 기록용).",
  files = list(
    design = fpi(DESIGN_P),
    asof_roles = fpi(file.path(ROOT, DESIGN$labels_other_roles$file)),
    msm_asof_daily = fpi(file.path(ROOT, DESIGN$predictor$file)),
    candidates = fpi(file.path(ROOT, DESIGN$candidates$file)),
    holdings_panel = fpi(file.path(ROOT, DESIGN$construction$holdings_panel)),
    defensive_labels = fpi(out_lab),
    reinforce_program_fixed_axes = fpi(file.path(ROOT, "06_Registry/reinforce_program.json"))),
  provenance = list(benchmark = fpi(bench_path), labels_summary = fpi(out_sum), series = ser_meta))
if (DRY) MAN$files$defensive_labels$path <- normalizePath(out_lab, winslash = "/")    # 드라이런 = 절대 경로(이 디렉터리 밖)
writeLines(toJSON(MAN, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), out_man, useBytes = TRUE)
cat(sprintf("[l2v1_labels] %s · 결정일 %d (%s~%s) · 적격 %s~%s · 슬리브 %s~%s · 누출 대조 %s · %s\n", LOCK$mode, length(DDS),
            format(min(DDS)), format(max(DDS)), min(BY$n_eligible), max(BY$n_eligible), min(BY$n_low), max(BY$n_low),
            if (ctrl_ok) "OK" else "FAIL", rel(out_man)))
