# test_b_ewcw_paired.R — b_ewcw_paired.R(PR-L1 1차 기전 지표 · 짝지은 Δ + NW-t) 양방향 검증 (합성 · tempdir 만 씀 · 운영 무접촉)
#
# 재는 것
#   C  설정 fail-closed — 부재 · 미지 lag 규칙 · b 비율 범위 · fixed-b 계수 개수 · alpha ≠ 0.05 · 필수 키 부재
#   N  NW 패리티 — t = 정본 backtest_result_contract.R::.nw_t_mean(x, lag) · value/se = t · 평균 이동에 se 불변 · lag = max(W, ⌈b·T⌉)
#   P  양성 대조(알려진 Δ 주입 회수) — arm 에 δ 를 더하면 value 가 정확히 δ · se 불변 · CI 평행 이동 · δ = −4·SE → t = −4 · CI 상한 < 0
#   K  구조 주입(tilt 적재 추정 경로 그대로) — 합성 수익(알려진 종목 β_e)에서 .ta_roll_ols·.ta_shrink 로 낸 적재의 두 포트 짝 Δ 가
#      참 Δ × 축소 가중(Vasicek w)에 모인다 · 축소 없음 대조는 참 Δ 에 모인다
#   Z  귀무 보정(무작위 쌍 · T=5400 · R=200) — fixed-b 5% 위양성률 ∈ 설정 띠 · t ≤ −3 꼬리 ≤ 설정 상한 · 평균 t ≈ 0 ·
#      fixed-b 90% CI 의 0 제외율 ≈ 10% · 대조: 자동 lag(NW 1994)는 띠 밖
#   I  입력 계약(tilt 산출 형식) — 정상 짝 = 핵심 · 최상위 measurement_regime · 규약/regime key/설정 md5/데이터 지문/창/주입 산출/표본 겹침/
#      라벨/날짜 중복 위반 → stop
#   W  쓰기 — out_dir 없으면 멈춤 · 명시 경로 JSON 최상위 value·t·se·ci·ci_level·measurement_regime
#   RT 소비자 왕복(2026-09-26) — 판정 입력 검사 정본 rf_prereg.R::.rfp_check_measurement 가 bew_write 산출을 합성 루트(tempdir)에서
#      받는가: 등재·고정값 = 계약 설정(ci_level · nw_b_fraction) · 양성(수치 재도출 = 계약 값) · 거부(규약 불일치 · measurement_regime 누락 ·
#      대역폭 쇼핑 · ci_level 변조 · 손 수치 · 바뀐 파일). ★소비자 부재 = FAIL(P2-01 배포 뒤 INTEG — 조용한 생략 없음)
#   M  돌연변이 — (M1) lag → 자동 규칙 → Z1 red · (M2) CI 를 정규 분위로 → Z4 red · (M3) 규약 대조 제거 → I red ·
#      (M4) 데이터 지문 대조 제거 → I red · (M5) 정본 NW 에 lag 인자 누락(기본 lag 3) → N1 red ·
#      (M6) 산출 최상위 measurement_regime 누락 → RT3 red(소비자 거부) · (M7) 소비자 설정에서 nw_b_fraction 고정 제거 → RT6 red(쇼핑 통과)
# 실행: Rscript 08_Tests/contracts/test_b_ewcw_paired.R (빈 Renviron 권장)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
CONTRACT <- file.path(ROOT, "02_Infrastructure/contracts/b_ewcw_paired.R")
CFG_SRC  <- file.path(ROOT, "02_Infrastructure/contracts/b_ewcw_paired_config.json")
TILT     <- file.path(ROOT, "02_Infrastructure/contracts/tilt_attribution.R")
if (!file.exists(CONTRACT)) stop("검사 앵커 실패 — 계약 부재: ", CONTRACT)

pass <- 0L; fail <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { pass <<- pass + 1L; cat(sprintf("  [PASS] %s %s\n", name, detail)) }
  else { fail <<- fail + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
expect_stop <- function(name, expr, pat = NULL) {
  e <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  chk(name, !is.null(e) && (is.null(pat) || grepl(pat, e)), if (is.null(e)) "(멈추지 않음)" else sprintf("(%s)", substr(e, 1, 90)))
}
TMP <- normalizePath(file.path(tempdir(), paste0("bew_test_", Sys.getpid())), winslash = "/", mustWork = FALSE)
dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
inside <- function(p, q) startsWith(tolower(normalizePath(p, winslash = "/", mustWork = FALSE)), tolower(paste0(normalizePath(q, winslash = "/", mustWork = FALSE), "/")))
if (inside(TMP, ROOT)) stop("tempdir 가 루트 안이다 — 쓰기 위험(중단): ", TMP)
ROOT_FP <- function() { fs <- c(list.files(file.path(ROOT, "02_Infrastructure/contracts"), full.names = TRUE), list.files(file.path(ROOT, "06_Registry"), full.names = TRUE))
  fs <- fs[file.exists(fs) & !dir.exists(fs)]; setNames(unname(tools::md5sum(fs)), fs) }
FP0 <- ROOT_FP()

invisible(capture.output(source(CONTRACT, encoding = "UTF-8")))
CFG <- bew_config(ROOT, CFG_SRC)
W <- as.integer(fromJSON(file.path(ROOT, "02_Infrastructure/contracts/tilt_attribution_config.json"))$loadings$window_market_days)
CAL <- CFG$calibration; band <- as.numeric(unlist(CAL$fpr_band))

# ═══ C 설정 fail-closed ═══
cat("\n[C] 설정 fail-closed\n")
c0 <- fromJSON(CFG_SRC, simplifyVector = FALSE)
wcfg <- function(x, nm) { p <- file.path(TMP, nm); writeLines(toJSON(x, auto_unbox = TRUE, pretty = TRUE, digits = NA), p); p }
expect_stop("C1 설정 부재 → stop", bew_config(ROOT, file.path(TMP, "none.json")), "설정 부재")
x <- c0; x$nw$lag_rule <- "nw1994"; expect_stop("C2 미지 lag 규칙 → stop", bew_config(ROOT, wcfg(x, "c2.json")), "lag_rule")
x <- c0; x$nw$b_fraction <- 0; expect_stop("C3 b 비율 0 → stop", bew_config(ROOT, wcfg(x, "c3.json")), "b_fraction")
x <- c0; x$nw$fixed_b$coef_975 <- list(1.96, 2.97); expect_stop("C4 fixed-b 계수 개수 → stop", bew_config(ROOT, wcfg(x, "c4.json")), "coef")
x <- c0; x$nw$fixed_b$alpha_two_sided <- 0.10; expect_stop("C5 alpha ≠ 0.05(다항식은 97.5% 분위) → stop", bew_config(ROOT, wcfg(x, "c5.json")), "alpha")
x <- c0; x$input$min_common_frac <- NULL; expect_stop("C6 필수 키 부재 → stop", bew_config(ROOT, wcfg(x, "c6.json")), "min_common_frac")

# ── 합성 귀무 쌍 생성기(검사 전용) — 종목 적재 추정 = 참값 + 창 W 이동평균 오차(겹친 창) · 지속 보유(월 교체 p) ──
gen_B <- function(Tn, N, W, noise = 0.25) {
  beta <- rnorm(N, 0.8, 0.4)
  U <- matrix(rnorm((Tn + W) * N), Tn + W, N); C <- rbind(0, apply(U, 2, cumsum))
  E <- (C[(W + 1):(Tn + W), , drop = FALSE] - C[1:Tn, , drop = FALSE]) / sqrt(W) * noise
  sweep(E, 2, beta, "+")
}
gen_hold <- function(Tn, N, n, p, month = 21L) {
  M <- matrix(0, Tn, N); h <- sample.int(N, n); m <- ceiling(Tn / month)
  for (k in seq_len(m)) {
    if (k > 1) { r <- runif(n) < p; if (any(r)) h[r] <- sample(setdiff(seq_len(N), h), sum(r)) }
    idx <- ((k - 1) * month + 1):min(k * month, Tn); M[idx, h] <- 1 / n
  }
  M
}
null_pair <- function(Tn, N = 150L, n = 25L, p = as.numeric(CAL$turnover_one_way_monthly)) {
  B <- gen_B(Tn, N, W); rowSums(gen_hold(Tn, N, n, p) * B) - rowSums(gen_hold(Tn, N, n, p) * B)
}
TZ <- 5400L

# ═══ N NW 패리티 ═══
cat("\n[N] NW 패리티(정본 .nw_t_mean)\n")
set.seed(11); d0 <- null_pair(TZ); dates0 <- seq(as.Date("2005-01-03"), by = "day", length.out = length(d0))
L <- bew_nw_lag(W, length(d0), CFG); nwf <- .bew_nw_fun(ROOT)
s0 <- bew_nw_stats(d0, L, ROOT)
chk("N1 t = 정본 .nw_t_mean(x, lag)", isTRUE(all.equal(s0$t, nwf(d0, lag = L), tolerance = 1e-10)), sprintf("(%.6f vs %.6f)", s0$t, nwf(d0, lag = L)))
chk("N2 value/se = t", isTRUE(all.equal(s0$value / s0$se, s0$t, tolerance = 1e-12)))
s0b <- bew_nw_stats(d0 + 0.37, L, ROOT)
chk("N3 평균 이동 → se 불변(잔차만)", isTRUE(all.equal(s0b$se, s0$se, tolerance = 1e-12)))
chk("N4 lag = max(W, ⌈b·T⌉)", identical(L, as.integer(max(W, ceiling(as.numeric(CFG$nw$b_fraction) * length(d0))))), sprintf("(L=%d · W=%d · T=%d)", L, W, length(d0)))
chk("N5 짧은 표본은 lag 하한 W(겹친 창)", identical(bew_nw_lag(W, 600L, CFG), W))
chk("N6 lag 3 = PORT_t 정본 식과 같은 경로", isTRUE(all.equal(bew_nw_stats(d0, 3L, ROOT)$t, nwf(d0, lag = 3L), tolerance = 1e-10)))

# ═══ P 양성 대조 — 알려진 Δ 주입 회수 ═══
cat("\n[P] 알려진 Δ 주입 회수\n")
set.seed(12); bF <- rnorm(TZ, 0.8, 0.02); bA <- bF + d0          # 귀무 짝(참 평균 0)
r0 <- bew_paired_delta_series(dates0, bA, bF, W, CFG, ROOT)
for (dl in c(-0.05, 0.02)) {
  r1 <- bew_paired_delta_series(dates0, bA + dl, bF, W, CFG, ROOT)
  chk(sprintf("P1 δ=%+.2f → value 가 정확히 δ 만큼", dl), abs((r1$value - r0$value) - dl) < 1e-12, sprintf("(Δvalue %.12f)", r1$value - r0$value))
  chk(sprintf("P2 δ=%+.2f → se 불변 · t = value/se", dl), isTRUE(all.equal(r1$se, r0$se, tolerance = 1e-12)) && isTRUE(all.equal(r1$t, r1$value / r1$se)))
  chk(sprintf("P3 δ=%+.2f → CI 평행 이동", dl), abs((r1$ci_lo - r0$ci_lo) - dl) < 1e-10 && abs((r1$ci_hi - r0$ci_hi) - dl) < 1e-10)
}
r2 <- bew_paired_delta_series(dates0, bA - 4 * r0$se - r0$value, bF, W, CFG, ROOT)
chk("P4 δ = −4·SE(평균 0 으로 맞춘 뒤) → t = −4 ≤ −3 검출", is.finite(r2$t) && abs(r2$t + 4) < 1e-8, sprintf("(t %.4f)", r2$t))
chk("P5 δ = −4·SE → fixed-b CI 상한 < 0 · fixed-b 5% 기각", r2$ci_hi < 0 && isTRUE(r2$nw$fixed_b$reject), sprintf("(ci_hi %.4f · crit %.3f)", r2$ci_hi, r2$nw$fixed_b$crit))
bb0 <- L / TZ
chk("P6 fixed-b 임계 = 설정 다항식 · ci_level = 설정(사전등록 pinned 대조)",
    isTRUE(all.equal(r0$nw$fixed_b$crit, sum(as.numeric(unlist(CFG$nw$fixed_b$coef_975)) * c(1, bb0, bb0^2, bb0^3)))) &&
      isTRUE(all.equal(r0$ci_level, as.numeric(CFG$nw$fixed_b$ci_level))) && r0$nw$fixed_b$crit > 1.96)

# ═══ K 구조 주입(tilt 적재 추정 경로) ═══
cat("\n[K] 구조 주입 — tilt .ta_roll_ols·.ta_shrink 경로\n")
if (!file.exists(TILT)) chk("K0 tilt 계약 존재", FALSE, TILT) else {
  TE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(TILT, envir = TE, keep.source = FALSE)))
  tcfg <- fromJSON(file.path(ROOT, "02_Infrastructure/contracts/tilt_attribution_config.json"), simplifyVector = FALSE)$loadings
  set.seed(21); D <- 1400L; N <- 120L
  fm <- rnorm(D, 0.0003, 0.012); fe <- rnorm(D, 0, 0.006)
  be <- rnorm(N, 0.9, 0.5); bm <- rnorm(N, 1, 0.2)
  Rm <- outer(fm, bm) + outer(fe, be) + matrix(rnorm(D * N, 0, 0.015), D, N)
  Wk <- as.integer(tcfg$window_market_days); mo <- as.integer(tcfg$min_obs)
  L1 <- TE$.ta_roll_ols(Rm, cbind(fm, fe), Wk, mo, as.numeric(tcfg$det_rel_tol))
  U <- matrix(TRUE, D, N); wts <- as.numeric(tcfg$shrink_weight_ts)
  Be <- TE$.ta_shrink(L1$B, U, wts, as.integer(tcfg$min_prior_n))[[2]]; ok <- which(rowSums(is.finite(Be)) == N)
  lo <- order(be)[1:25]; rd <- sample(setdiff(seq_len(N), lo), 25)
  dk <- seq(as.Date("2015-01-01"), by = "day", length.out = length(ok))
  rk <- bew_paired_delta_series(dk, rowMeans(Be[ok, lo]), rowMeans(Be[ok, rd]), Wk, CFG, ROOT)
  truth <- mean(be[lo]) - mean(be[rd]); ratio <- rk$value / truth
  chk("K1 구조 주입 부호 회수(저 β_e 포트 − 무작위 포트 < 0 · t ≤ −3)", rk$value < 0 && rk$t <= -3, sprintf("(value %.4f · t %.2f · 참 Δ %.4f)", rk$value, rk$t, truth))
  chk("K2 회수 비율 ≈ 축소 가중 w(Vasicek — 같은 날 사전 상쇄)", abs(ratio - wts) < 0.1, sprintf("(value/참Δ %.3f · w %.2f)", ratio, wts))
  B1u <- TE$.ta_shrink(L1$B, U, 1, as.integer(tcfg$min_prior_n))[[2]]
  rku <- bew_paired_delta_series(dk, rowMeans(B1u[ok, lo]), rowMeans(B1u[ok, rd]), Wk, CFG, ROOT)
  chk("K3 대조 — 축소 없는 적재는 참 Δ 에 모인다(감쇠의 원인 = 축소)", abs(rku$value / truth - 1) < 0.1, sprintf("(%.3f)", rku$value / truth))
}

# ═══ Z 귀무 보정 — 무작위 쌍 위양성률 ═══
cat("\n[Z] 귀무 보정 — 교환 가능한 무작위 쌍(T=5400)\n")
RZ <- 200L
set.seed(20260925); DL <- lapply(seq_len(RZ), function(i) null_pair(TZ))
cz <- bew_calibrate(DL, W, CFG, thr = -3, root = ROOT)
chk("Z1 fixed-b 5% 위양성률 ∈ 설정 띠", cz$fpr_fixed_b >= band[1] && cz$fpr_fixed_b <= band[2],
    sprintf("(%.3f · 정규 1.96 %.3f · 띠 %s · lag %d)", cz$fpr_fixed_b, cz$fpr_normal, paste(band, collapse = "~"), as.integer(cz$lag)))
chk("Z2 t ≤ −3 귀무 꼬리 ≤ 설정 상한(fixed-b 이론 ≈ 1.3%)", cz$fpr_thr <= as.numeric(CAL$t_thr_tail_max), sprintf("(%.3f)", cz$fpr_thr))
chk("Z3 평균 t ≈ 0(|평균| ≤ 0.25 — 교환 가능 쌍)", abs(cz$mean_t) <= 0.25, sprintf("(%.3f · sd %.3f)", cz$mean_t, cz$sd_t))
chk("Z4 fixed-b 90% CI 의 0 제외율 ≈ 1 − ci_level(± 0.05)", abs(cz$ci_excl0 - cz$ci_nominal) <= 0.05, sprintf("(%.3f · 명목 %.2f)", cz$ci_excl0, cz$ci_nominal))
t94 <- vapply(DL, function(d) bew_nw_stats(d, max(1L, as.integer(floor(4 * (length(d) / 100)^(2 / 9)))), ROOT)$t, 0)
chk("Z5 대조 — 자동 lag(NW 1994) 위양성률 > 띠 상단(의존 미포착 · lag 규칙이 일을 한다)", mean(abs(t94) > 1.96) > band[2], sprintf("(%.3f)", mean(abs(t94) > 1.96)))

# ═══ I 입력 계약(tilt 산출 형식) ═══
cat("\n[I] 입력 계약\n")
mk_tilt <- function(dir, dates, b, exec = "close_t1", rk = paste0(exec, "_k"), cmd5 = "CFGMD5", fp = list(raw = list(size = 1, mtime = "t")),
                    win = W, inject = NULL, label = "진단 — 등급 대체 아님") {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  js <- list(label = label, version = "tilt_attribution_v1",
             input = list(artifact = dir, dir = dir, exec_price = exec, regime_key = rk, strategy_id = basename(dir), essence_grade_auth = "B",
                          inject_alpha_ann = inject),
             config = list(md5 = cmd5, window = win), state = list(data_fp = fp))
  writeLines(toJSON(js, auto_unbox = TRUE, null = "null", digits = NA), file.path(dir, "tilt_attribution.json"))
  fwrite(data.table(date = dates, b_ewcw_2f = b, GL = 1), file.path(dir, "tilt_attribution_daily.csv"))
  file.path(dir, "tilt_attribution.json")
}
jA <- mk_tilt(file.path(TMP, "tA"), dates0, bA); jF <- mk_tilt(file.path(TMP, "tF"), dates0, bF)
ri <- bew_paired_delta(jA, jF, CFG, ROOT)
chk("I1 정상 짝 = 순수 핵심과 같은 value·t·ci", isTRUE(all.equal(ri$value, r0$value)) && isTRUE(all.equal(ri$t, r0$t)) && isTRUE(all.equal(ri$ci_hi, r0$ci_hi)))
chk("I2 최상위 measurement_regime.exec_price(사전등록 artifact_regime_required 대조 키)", identical(ri$measurement_regime$exec_price, "close_t1"))
chk("I3 라벨 = 진단 · 계약명", identical(ri$label, "진단 — 등급 대체 아님") && identical(ri$contract, "b_ewcw_paired_delta"))
expect_stop("I4 집행 규약 불일치 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX1"), dates0, bA, exec = "close_d_legacy", rk = "close_t1_k"), jF, CFG, ROOT), "집행 규약")
expect_stop("I5 regime key 불일치 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX1b"), dates0, bA, rk = "close_t1_other"), jF, CFG, ROOT), "regime key")
expect_stop("I6 tilt 설정 md5 불일치 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX2"), dates0, bA, cmd5 = "OTHER"), jF, CFG, ROOT), "설정 md5")
expect_stop("I7 데이터 지문 불일치 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX3"), dates0, bA, fp = list(raw = list(size = 2, mtime = "t"))), jF, CFG, ROOT), "데이터 지문")
expect_stop("I8 적재 창 불일치 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX4"), dates0, bA, win = W + 1L), jF, CFG, ROOT), "적재 창")
expect_stop("I9 주입(양성 대조) 산출 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX5"), dates0, bA, inject = 0.05), jF, CFG, ROOT), "주입")
expect_stop("I10 공통 수익일 부족 → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX6"), dates0[1:3000], bA[1:3000]), jF, CFG, ROOT), "공통 수익일")
expect_stop("I11 tilt 산출 아님(라벨) → stop", bew_paired_delta(mk_tilt(file.path(TMP, "tX7"), dates0, bA, label = "등급"), jF, CFG, ROOT), "tilt 계약 산출")
expect_stop("I12 날짜 중복 → stop", bew_paired_delta_series(c(dates0[1], dates0[1:(TZ - 1)]), bA, bF, W, CFG, ROOT), "중복")

# ═══ W 쓰기 ═══
cat("\n[W] 쓰기\n")
expect_stop("W1 out_dir 없으면 멈춤", bew_write(ri), "out_dir")
wp <- bew_write(ri, file.path(TMP, "out"))
wj <- fromJSON(wp, simplifyVector = FALSE)
chk("W2 JSON 최상위 value·t·se·ci_lo·ci_hi·ci_level·measurement_regime", all(c("value", "t", "se", "ci_lo", "ci_hi", "ci_level", "measurement_regime") %in% names(wj)) &&
      identical(wj$measurement_regime$exec_price, "close_t1"))

# ═══ RT 소비자 왕복 — rf_prereg.R 판정 입력 검사(.rfp_check_measurement)가 이 계약 산출을 받는가 ═══
cat("\n[RT] 소비자 왕복(rf_prereg 판정 입력 검사 정본)\n")
PRL <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"); PRC <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
rt_ok <- file.exists(PRL) && file.exists(PRC)
chk("RT0 소비자(rf_prereg.R · prereg_config.json) 존재 — INTEG 는 P2-01 뒤", rt_ok, if (rt_ok) "" else "(부재 — 소비 계약을 잴 수 없다)")
RTX <- NULL
if (rt_ok) {
  RR <- file.path(TMP, "rt_root")
  for (d in c("02_Infrastructure/contracts", "06_Registry/prereg", "stage_artifacts/prereg/PR-RT")) dir.create(file.path(RR, d), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(RR, "02_Infrastructure/config.R"))                          # rf_prereg 루트 표지(.rfp_is_root)
  file.copy(PRC, file.path(RR, "06_Registry/prereg/prereg_config.json"))
  file.copy(CONTRACT, file.path(RR, "02_Infrastructure/contracts/b_ewcw_paired.R"))  # 계약 파일 존재 검사용 사본
  PE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(PRL, envir = PE, keep.source = FALSE)))
  pcfg <- PE$rf_prereg_config(RR); cdef <- pcfg$verdict$contracts[[BEW_CONTRACT]]
  chk("RT1 소비자 설정에 이 계약 등재(파일 = 이 계약 · artifact_regime_required)", is.list(cdef) && identical(cdef$file, "02_Infrastructure/contracts/b_ewcw_paired.R") &&
        isTRUE(cdef$artifact_regime_required), if (is.list(cdef)) "" else "(미등재 — prereg_config Part B 미배포)")
  pv <- function(cf, k) { p <- cf$verdict$contracts[[BEW_CONTRACT]]$pinned[[k]]; if (is.null(p)) return(NULL)
    w <- cf; for (kk in strsplit(as.character(p), ".", fixed = TRUE)[[1]]) w <- if (is.list(w)) w[[kk]] else NULL; w }
  chk("RT2 소비자 고정값 = 계약 설정(ci_level · nw_b_fraction — 등록 동결 · 계약 설정이 원천)",
      isTRUE(all.equal(as.numeric(pv(pcfg, "ci_level")), as.numeric(CFG$nw$fixed_b$ci_level))) && isTRUE(all.equal(as.numeric(pv(pcfg, "nw_b_fraction")), as.numeric(CFG$nw$b_fraction))),
      sprintf("(ci_level %s vs %s · b %s vs %s)", format(pv(pcfg, "ci_level")), format(CFG$nw$fixed_b$ci_level), format(pv(pcfg, "nw_b_fraction")), format(CFG$nw$b_fraction)))
  ADIR <- file.path(RR, "stage_artifacts/prereg/PR-RT")
  PRX <- list(metrics = list(list(id = "bew", contract = BEW_CONTRACT)), floors = list(list(id = "F")), arms = list(list(id = "A1")),
              contrasts = list(list(id = "A1-F")), se_cells = list(), measurement_regime = list(exec_price = "close_t1"))
  rel <- function(p) substring(normalizePath(p, winslash = "/"), nchar(normalizePath(RR, winslash = "/")) + 2L)
  mkm <- function(p, ..., regime = "close_t1") c(list(metric = "bew", target = "A1-F"), list(...),
    list(source = list(contract = BEW_CONTRACT, artifact = rel(p), artifact_sha256 = PE$.rfp_sha_file(p), measurement_regime = list(exec_price = regime))))
  RTX <- function(m, pr = PRX, cf = pcfg) tryCatch(PE$.rfp_check_measurement(m, pr, RR, cf, TRUE), error = function(e) conditionMessage(e))
  ap_ok <- bew_write(ri, ADIR, prefix = "rt_ok")
  mm <- RTX(mkm(ap_ok))
  chk("RT3 양성 — 소비자가 산출을 받고 value·se·t·ci_lo·ci_hi·ci_level 을 산출물에서 재도출(= 계약 값)",
      is.list(mm) && all(abs(c(mm$value - ri$value, mm$se - ri$se, mm$t - ri$t, mm$ci_lo - ri$ci_lo, mm$ci_hi - ri$ci_hi)) < 1e-12) && isTRUE(all.equal(mm$ci_level, ri$ci_level)),
      if (is.character(mm)) sprintf("(거부: %s)", substr(mm, 1, 110)) else sprintf("(t %.3f)", mm$t))
  e4 <- RTX(mkm(ap_ok), pr = modifyList(PRX, list(measurement_regime = list(exec_price = "close_d_legacy"))), cf = pcfg)
  chk("RT4 사전등록 규약 ≠ 산출 규약 → 거부(실현값 대조)", is.character(e4) && grepl("규약", e4), substr(as.character(e4)[1], 1, 90))
  r5 <- ri; r5$measurement_regime <- NULL; ap5 <- bew_write(r5, ADIR, prefix = "rt_noregime")
  e5 <- RTX(mkm(ap5)); chk("RT5 산출 measurement_regime 누락 → 거부(artifact_regime_required)", is.character(e5) && grepl("measurement_regime", e5), substr(as.character(e5)[1], 1, 90))
  r6 <- ri; r6$nw_b_fraction <- 0.1; ap6 <- bew_write(r6, ADIR, prefix = "rt_bshop")
  e6 <- RTX(mkm(ap6)); chk("RT6 대역폭 비율 쇼핑(nw_b_fraction 0.1) → 거부(pinned)", is.character(e6) && grepl("nw_b_fraction", e6) && grepl("쇼핑", e6), substr(as.character(e6)[1], 1, 90))
  r7 <- ri; r7$ci_level <- 0.95; ap7 <- bew_write(r7, ADIR, prefix = "rt_cishop")
  e7 <- RTX(mkm(ap7)); chk("RT7 ci_level 변조(0.95) → 거부(pinned)", is.character(e7) && grepl("ci_level", e7), substr(as.character(e7)[1], 1, 90))
  e8 <- RTX(mkm(ap_ok, value = ri$value + 0.01)); chk("RT8 손 수치(주장 value ≠ 산출) → 거부(AX-008)", is.character(e8) && grepl("산출물에서만", e8), substr(as.character(e8)[1], 1, 90))
  m9 <- mkm(ap_ok); cat(" ", file = ap_ok, append = TRUE)
  e9 <- RTX(m9); chk("RT9 등록 뒤 바뀐 산출 파일(sha 불일치) → 거부", is.character(e9) && grepl("sha256", e9), substr(as.character(e9)[1], 1, 90))
}

# ═══ M 돌연변이 ═══
cat("\n[M] 돌연변이\n")
src <- readLines(CONTRACT, encoding = "UTF-8", warn = FALSE)
mutant <- function(from, to) {
  hit <- which(grepl(from, src, fixed = TRUE)); if (length(hit) != 1L) return(NULL)
  s2 <- src; s2[hit] <- sub(from, to, s2[hit], fixed = TRUE)
  p <- file.path(TMP, sprintf("mut_%d.R", sample.int(1e6, 1))); writeLines(s2, p, useBytes = TRUE)
  e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(p, envir = e, keep.source = FALSE))); e
}
mchk <- function(name, m, fn) if (is.null(m)) chk(paste(name, "— 대상 줄 1곳"), FALSE) else fn(m)
mchk("M1", mutant("as.integer(max(W, ceiling(as.numeric(cfg$nw$b_fraction) * n)))", "max(1L, as.integer(floor(4 * (n / 100)^(2 / 9))))"), function(m) {
  cm <- m$bew_calibrate(DL[1:100], W, CFG, thr = -3, root = ROOT)
  chk("M1 lag → 자동 규칙 돌연변이는 Z1 을 red 로(위양성률 띠 이탈)", !(cm$fpr_fixed_b >= band[1] && cm$fpr_fixed_b <= band[2]), sprintf("(%.3f)", cm$fpr_fixed_b)) })
mchk("M2", mutant('cc <- bew_fixed_b_crit(L / n, cfg, "ci")', "cc <- stats::qnorm(0.95)"), function(m) {
  cm <- m$bew_calibrate(DL, W, CFG, thr = -3, root = ROOT)
  chk("M2 CI 를 정규 분위로 낸 돌연변이는 Z4 를 red 로(과신)", abs(cm$ci_excl0 - cm$ci_nominal) > 0.05, sprintf("(%.3f)", cm$ci_excl0)) })
mchk("M3", mutant("if (!identical(epA, epF)) stop(", "if (FALSE) stop("), function(m) {
  e <- tryCatch({ m$bew_paired_delta(mk_tilt(file.path(TMP, "tM3"), dates0, bA, exec = "close_d_legacy", rk = "close_t1_k"), jF, CFG, ROOT); "no_error" }, error = function(e) conditionMessage(e))
  chk("M3 규약 대조 제거 돌연변이는 I4 를 red 로(멈추지 않는다)", identical(e, "no_error"), substr(e, 1, 60)) })
mchk("M4", mutant("if (!.bew_fp_same(A$json$state$data_fp, Fl$json$state$data_fp))", "if (FALSE)"), function(m) {
  e <- tryCatch({ m$bew_paired_delta(mk_tilt(file.path(TMP, "tM4"), dates0, bA, fp = list(raw = list(size = 9, mtime = "t"))), jF, CFG, ROOT); "no_error" }, error = function(e) conditionMessage(e))
  chk("M4 데이터 지문 대조 제거 돌연변이는 I7 을 red 로", identical(e, "no_error"), substr(e, 1, 60)) })
mchk("M5", mutant("t1 <- nw(y, lag = lag)", "t1 <- nw(y)"), function(m) {
  s5 <- m$bew_nw_stats(d0, L, ROOT)
  chk("M5 정본 NW 에 lag 인자 누락(기본 3) 돌연변이는 N1 을 red 로", !isTRUE(all.equal(s5$t, nwf(d0, lag = L), tolerance = 1e-8)), sprintf("(%.3f vs %.3f)", s5$t, nwf(d0, lag = L))) })
if (is.function(RTX)) {
  mchk("M6", mutant("         measurement_regime = mr,", ""), function(m) {
    r6m <- m$bew_paired_delta(jA, jF, CFG, ROOT); p6m <- bew_write(r6m, ADIR, prefix = "rt_mut6")
    e <- RTX(mkm(p6m))
    chk("M6 산출 최상위 measurement_regime 누락 돌연변이는 RT3 을 red 로(소비자가 거부)", is.character(e) && grepl("measurement_regime", e), substr(as.character(e)[1], 1, 70)) })
  pc7 <- pcfg; pc7$verdict$contracts[[BEW_CONTRACT]]$pinned$nw_b_fraction <- NULL
  x7 <- RTX(mkm(ap6), cf = pc7)
  chk("M7 소비자 설정에서 nw_b_fraction 고정을 끈 돌연변이는 RT6 을 red 로(대역폭 쇼핑 산출을 받는다 — 고정이 일을 한다)", is.list(x7), if (is.character(x7)) substr(x7, 1, 70) else "")
} else chk("M6·M7 소비자 왕복 돌연변이 — 소비자 부재로 잴 수 없다", FALSE)

# ═══ R 읽기 전용 ═══
cat("\n[R] 루트 읽기 전용\n")
FP1 <- ROOT_FP()
chk("R1 루트 contracts·06_Registry 최상위 지문 불변", identical(FP0, FP1), sprintf("(%d 파일)", length(FP0)))

cat(sprintf("\n결과: PASS %d · FAIL %d\n", pass, fail))
cat(sprintf('{"test":"b_ewcw_paired","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
unlink(TMP, recursive = TRUE)
quit(status = if (fail > 0L) 1L else 0L)
