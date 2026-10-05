# test_sleeve_delivery.R — sleeve_delivery.R(처치 전달량 계약 · 결정 PR-L2-B7-EXCL-UNIT (c)) 양방향 검증 (합성 · tempdir 만 씀 · 운영 무접촉)
#
# 재는 것
#   P  양성 — 엔진 진단 형식(rf_sleeve.R::rf_sl_delivery 산출 그대로)에서 value(= δ 풀링 · 사전등록 treatment_delivery 문언)·mean_by_date·
#      min·median·share_zero·share_full 재도출 · 최상위 measurement_regime.exec_price = authoritative_remeasure.json 실현값 · cap_core 절 Σ코어 평균 ·
#      (P5) 슬리브 자리 수가 시그널일마다 갈리는 픽스처 — value = 풀링(5/7) ≠ 등가중(0.5) · per_date·n_signal_dates
#   I  입력 계약(fail-closed) — 진단 부재 · 실현 규약 파일 부재 · exec_price 비어 있음 · schema 불일치 · 절 부재 · Date 중복 ·
#      n_alpha/n_sleeve 식 위반 · n_new > n_sleeve · 엔진 요약 ≠ 재도출(변조) · cap_core Σ ≠ 1
#   W  쓰기 — out_dir 없으면 멈춤 · 원자 쓰기 · 최상위 value·measurement_regime · metric·target 실음(빈 값 거부)
#   RT 소비자 왕복 — 판정 입력 검사 정본 rf_prereg.R::.rfp_check_measurement (★배포 순서 무관 — 운영 설정의 등재 상태를 빌리지 않는다):
#      RT1a 미등재 설정(운영 설정에서 항목 제거) → '미등재 계약' 거부 · RT1b 운영 설정 그대로 — 미등재면 거부 · 등재면(preregfix 배포 뒤) 수락 ·
#      RT2~6 합성 설정(이 키트 권고 항목 file = contracts/sleeve_delivery.R)에서 양성 재도출 · 규약 불일치 · regime 누락 · 손 수치 · 바뀐 파일 거부 ·
#      RT7 preregfix 스테이징 항목 형식(file = rf_sleeve.R)으로도 수락 · metric/target 이 측정 객체와 다르면 거부
#   M  돌연변이 — (M1) 엔진 요약 대조 제거 → I9 red(변조 통과) · (M2) exec_price 검사 제거 → I3 red · (M3) n_new ≤ n_sleeve 검사 제거 → I8 red ·
#      (M4) 산출 measurement_regime 누락 → RT3 red(소비자 거부) · (M5) value 를 등가중 평균으로 되돌림 → P5 red
# 실행: Rscript 08_Tests/contracts/test_sleeve_delivery.R (빈 Renviron 권장)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
.self <- tryCatch({ a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "." }, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
if (!file.exists(file.path(ROOT, "02_Infrastructure/contracts/sleeve_delivery.R"))) ROOT <- Sys.getenv("QM_ROOT", ROOT)
CONTRACT <- file.path(ROOT, "02_Infrastructure/contracts/sleeve_delivery.R")
SLEEVE <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_sleeve.R")
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
invisible(capture.output(source(CONTRACT)))
SL <- new.env(parent = globalenv()); invisible(capture.output(sys.source(SLEEVE, envir = SL, keep.source = FALSE)))
TMP <- file.path(tempdir(), paste0("sdt_", Sys.getpid())); dir.create(TMP, recursive = TRUE, showWarnings = FALSE)
ROOT_FP <- function() { f <- c(list.files(file.path(ROOT, "02_Infrastructure/contracts"), full.names = TRUE), list.files(file.path(ROOT, "06_Registry"), full.names = TRUE))
  f <- f[file.info(f)$isdir %in% FALSE]; stats::setNames(as.character(file.info(f)$mtime), f) }
FP0 <- ROOT_FP()

# ── 합성: rf_sl_delivery 를 실제로 돌려 엔진과 같은 진단 형식을 만든다 ──
set.seed(5)
mk_sel <- function(n_dates = 12L, n = 60L, nmax = 25L) {
  P <- CJ(Date = seq(as.Date("2020-01-31"), by = "month", length.out = n_dates), Ticker = sprintf("T%02d", seq_len(n)))
  P[, Score := -as.integer(sub("T", "", Ticker)) + rnorm(.N, 0, 0.01)][, .zdef := runif(.N)]
  list(P = P, S = P[order(Date, -Score)][, head(.SD, nmax), by = Date])
}
X <- mk_sel(); RULE <- SL$rf_sl_parse(list(kind = "factor_topk", k = 5, exclude = "base_factors"))
OUT <- SL$rf_sl_select(X$P, X$S, RULE, 25L, ".zdef")
DLV <- SL$rf_sl_delivery(X$S, OUT, RULE, 25L)
mk_dir <- function(name, diag = NULL, auth = list(measurement_regime = list(exec_price = "close_t1")), sections = list(sleeve_delivery = TRUE)) {
  d <- file.path(TMP, name); dir.create(d, showWarnings = FALSE)
  if (is.null(diag)) {
    diag <- list(schema = "rf_engine_diag_v1", cell_code = "B7_37", spec_md5 = "abc", written_at = "t", n_sig_dates = nrow(DLV$rows))
    if (isTRUE(sections$sleeve_delivery))
      diag$sleeve_delivery <- list(rule = RULE, resolved_id = "D35_RealVol_63d", basis = "b", asof = "2005-01-01", exclude_rule = "base_factors",
                                   excluded_ids = c("D42_EWMA_Vol", "IN05_Net_Debt_Issuance"), excluded_in_pool = "D42_EWMA_Vol",
                                   summary = DLV$summary, rows = DLV$rows)
  }
  writeLines(toJSON(diag, auto_unbox = TRUE, pretty = TRUE, digits = NA, na = "null", null = "null", dataframe = "rows", Date = "ISO8601"),
             file.path(d, "rf_engine_diag.json"), useBytes = TRUE)
  if (!is.null(auth)) writeLines(toJSON(auth, auto_unbox = TRUE), file.path(d, "authoritative_remeasure.json"))
  d
}

cat("[P] 양성\n")
d_ok <- mk_dir("ok")
r <- sd_measure(d_ok, "sleeve_delivery")
v <- DLV$rows$n_new / DLV$rows$n_sleeve
chk("P1 value = δ 풀링 Σn_new/Σn_sleeve(독립 계산) · mean_by_date = 시그널일 평균 · min · median", isTRUE(all.equal(r$value, sum(DLV$rows$n_new) / sum(DLV$rows$n_sleeve))) &&
      isTRUE(all.equal(r$pooled, r$value)) && isTRUE(all.equal(r$mean_by_date, mean(v))) && isTRUE(all.equal(r$min, min(v))) &&
      isTRUE(all.equal(r$median, stats::median(v))), sprintf("(%.4f)", r$value))
chk("P2 최상위 measurement_regime.exec_price = 실현 규약 파일 값 · 계약명·라벨(진단)", identical(r$measurement_regime$exec_price, "close_t1") &&
      identical(r$contract, "sleeve_delivery") && grepl("등급 대체 아님", r$label))
chk("P3 제외 기록 승계(excluded_ids · excluded_in_pool · resolved_id) · 입력 sha256", identical(r$excluded_in_pool, "D42_EWMA_Vol") &&
      length(r$excluded_ids) == 2L && nchar(r$inputs$diag_sha256) == 64L && nchar(r$inputs$auth_sha256) == 64L)
CC <- list(compose = data.table(Date = as.Date(c("2020-01-31", "2020-02-29")), n_core = 2L, n_overlap = c(0L, 1L), n_truncated = c(2L, 1L),
                                n_hold = 25L, sum_core = c(0.30, 0.28), sum_sat = c(0.70, 0.72)),
           summary = list(k = 2L, satellite = "floor", mean_sum_core = 0.29, min_sum_core = 0.28, max_sum_core = 0.30, mean_overlap = 0.5, mean_truncated = 1.5))
dg_cc <- list(schema = "rf_engine_diag_v1", cell_code = "A1", spec_md5 = "x", cap_core = CC)
rc <- sd_measure(mk_dir("cc", diag = dg_cc), "cap_core")
chk("P4 cap_core 절 — Σ코어 평균 0.29 · k 2", isTRUE(all.equal(rc$value, 0.29)) && identical(rc$k, 2L))
# P5 — 슬리브 자리 수가 갈리는 날(바닥 후보가 n_max − k 보다 적은 달): d1 5자리 전부 새 이름 · d2 2자리 전부 바닥 이름
#   δ(풀링) = 5/7 · 등가중 = (1 + 0)/2 = 0.5 — 두 정의가 갈리는 픽스처라 value 가 어느 정의인지 판별된다(사전등록 문언 = 풀링)
RV <- data.table(Date = c("2020-01-31", "2020-02-29"), n_before = c(25L, 20L), n_after = c(25L, 22L), n_alpha = c(20L, 20L),
                 n_sleeve = c(5L, 2L), n_new = c(5L, 0L))
SV <- list(k = 5L, n_max = 25L, n_dates = 2L, n_dates_with_sleeve = 2L, mean_by_date = 0.5, pooled = 5 / 7, min = 0, median = 0.5,
           share_zero = 0.5, share_full = 0.5)
dg_v <- list(schema = "rf_engine_diag_v1", cell_code = "B7_37", spec_md5 = "v",
             sleeve_delivery = list(rule = RULE, resolved_id = "D35_RealVol_63d", summary = SV, rows = RV))
r5 <- tryCatch(sd_measure(mk_dir("vary", diag = dg_v), "sleeve_delivery"), error = function(e) conditionMessage(e))   # 죽어도 이름 붙은 red
chk("P5 자리 수가 갈리는 픽스처 — value = δ 풀링 5/7 ≠ 등가중 0.5 · per_date 2행(delivery 1·0) · n_signal_dates 2",
    is.list(r5) && isTRUE(all.equal(r5$value, 5 / 7)) && isTRUE(all.equal(r5$mean_by_date, 0.5)) && NROW(r5$per_date) == 2L &&
      isTRUE(all.equal(as.numeric(r5$per_date$delivery), c(1, 0))) && identical(as.integer(r5$n_signal_dates), 2L) &&
      identical(r5$source_sha256, r5$inputs$diag_sha256) && nchar(r5$source_sha256) == 64L,
    if (is.list(r5)) sprintf("(%.4f)", r5$value) else substr(r5, 1, 90))

cat("[I] 입력 계약\n")
expect_stop("I1 진단 파일 부재 → stop", sd_measure({ d <- file.path(TMP, "nodiag"); dir.create(d); d }), "진단 부재")
expect_stop("I2 실현 규약 파일 부재 → stop", sd_measure(mk_dir("noauth", auth = NULL)), "authoritative_remeasure")
expect_stop("I3 exec_price 비어 있음 → stop", sd_measure(mk_dir("noexec", auth = list(measurement_regime = list(exec_price = "")))), "exec_price")
dg_bad <- list(schema = "rf_engine_diag_v0"); expect_stop("I4 schema 불일치 → stop", sd_measure(mk_dir("schema", diag = dg_bad)), "schema")
expect_stop("I5 절 부재(이 칸은 슬리브 처치 없음) → stop", sd_measure(mk_dir("nosec", diag = dg_cc), "sleeve_delivery"), "절이 없다")
mk_tamper <- function(name, f) { dg <- list(schema = "rf_engine_diag_v1", cell_code = "B7_37", spec_md5 = "abc",
  sleeve_delivery = list(rule = RULE, resolved_id = "x", summary = DLV$summary, rows = copy(DLV$rows))); dg <- f(dg); mk_dir(name, diag = dg) }
expect_stop("I6 Date 중복 → stop", sd_measure(mk_tamper("dup", function(g) { g$sleeve_delivery$rows <- rbind(g$sleeve_delivery$rows, g$sleeve_delivery$rows[1]); g })), "중복")
expect_stop("I7 n_sleeve ≠ n_after − n_alpha(행 변조) → stop", sd_measure(mk_tamper("ns", function(g) { g$sleeve_delivery$rows[1, n_sleeve := n_sleeve + 1L]; g })), "n_sleeve|n_alpha")
expect_stop("I8 n_new > n_sleeve → stop", sd_measure(mk_tamper("nn", function(g) { g$sleeve_delivery$rows[1, `:=`(n_new = 6L)]; g })), "n_new")
expect_stop("I9 엔진 요약 변조(mean_by_date +0.1) → stop(엔진 요약을 믿지 않는다)",
            sd_measure(mk_tamper("sum", function(g) { g$sleeve_delivery$summary$mean_by_date <- g$sleeve_delivery$summary$mean_by_date + 0.1; g })), "재도출")
cc_bad <- dg_cc; cc_bad$cap_core$compose$sum_sat[1] <- 0.5
expect_stop("I10 cap_core Σ코어 + Σ위성 ≠ 1 → stop", sd_measure(mk_dir("ccbad", diag = cc_bad), "cap_core"), "≠ 1")

cat("[W] 쓰기\n")
expect_stop("W1 out_dir 없음 → stop(기본 쓰기 경로 없음)", sd_write(r, ""), "out_dir")
wp <- sd_write(r, file.path(TMP, "w"), metric = "treatment_delivery", target = "F1.B7_37"); wj <- fromJSON(wp, simplifyVector = FALSE)
chk("W2 JSON 최상위 value·measurement_regime·metric·target · 임시 파일 잔재 0", is.numeric(wj$value) && identical(wj$measurement_regime$exec_price, "close_t1") &&
      identical(wj$metric, "treatment_delivery") && identical(wj$target, "F1.B7_37") &&
      !length(list.files(file.path(TMP, "w"), pattern = "\\.tmp", all.files = TRUE)))
expect_stop("W3 metric 빈 문자열 → stop", sd_write(r, file.path(TMP, "w3"), metric = ""), "metric")

cat("[RT] 소비자 왕복(rf_prereg 판정 입력 검사 정본)\n")
PRL <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_prereg.R"); PRC <- file.path(ROOT, "06_Registry/prereg/prereg_config.json")
rt_ok <- file.exists(PRL) && file.exists(PRC)
chk("RT0 소비자(rf_prereg.R · prereg_config.json) 존재", rt_ok)
RTX <- NULL
if (rt_ok) {
  RR <- file.path(TMP, "rt_root")
  for (d in c("02_Infrastructure/contracts", "06_Registry/prereg", "stage_artifacts/prereg/PR-RT")) dir.create(file.path(RR, d), recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(RR, "02_Infrastructure/config.R"))
  file.copy(PRC, file.path(RR, "06_Registry/prereg/prereg_config.json"))
  file.copy(CONTRACT, file.path(RR, "02_Infrastructure/contracts/sleeve_delivery.R"))
  PE <- new.env(parent = globalenv()); invisible(capture.output(sys.source(PRL, envir = PE, keep.source = FALSE)))
  pcfg_live <- PE$rf_prereg_config(RR)
  ADIR <- file.path(RR, "stage_artifacts/prereg/PR-RT")
  PRX <- list(metrics = list(list(id = "dlv", contract = "sleeve_delivery")), floors = list(list(id = "F1")), arms = list(list(id = "F1.B7_37")),
              contrasts = list(), se_cells = list(), measurement_regime = list(exec_price = "close_t1"))
  rel <- function(p) substring(normalizePath(p, winslash = "/"), nchar(normalizePath(RR, winslash = "/")) + 2L)
  mkm <- function(p, ..., regime = "close_t1") c(list(metric = "dlv", target = "F1.B7_37"), list(...),
    list(source = list(contract = "sleeve_delivery", artifact = rel(p), artifact_sha256 = PE$.rfp_sha_file(p), fields = list(value = "value"),
                       measurement_regime = list(exec_price = regime))))
  ap_ok <- sd_write(r, ADIR, prefix = "rt_ok")
  # ★운영 설정의 등재 상태를 빌리지 않는다(배포 순서 무관) — 미등재 판은 합성으로 만든다
  pcfg_un <- pcfg_live; pcfg_un$verdict$contracts[["sleeve_delivery"]] <- NULL
  e1 <- tryCatch(PE$.rfp_check_measurement(mkm(ap_ok), PRX, RR, pcfg_un, TRUE), error = function(e) conditionMessage(e))
  chk("RT1a 미등재 설정 → '미등재 계약' 거부 — 등재 전에는 판정 입력이 될 수 없다(등재 = preregfix · prereg_config 개정)",
      is.character(e1) && grepl("미등재", e1), substr(as.character(e1)[1], 1, 80))
  cd_live <- pcfg_live$verdict$contracts[["sleeve_delivery"]]
  if (is.null(cd_live)) {
    e1b <- tryCatch(PE$.rfp_check_measurement(mkm(ap_ok), PRX, RR, pcfg_live, TRUE), error = function(e) conditionMessage(e))
    chk("RT1b 운영 설정 그대로(현재 미등재) → 거부", is.character(e1b) && grepl("미등재", e1b), substr(as.character(e1b)[1], 1, 80))
  } else {
    lf <- as.character(cd_live$file %||% "")
    if (nzchar(lf) && file.exists(file.path(ROOT, lf))) {
      dir.create(dirname(file.path(RR, lf)), recursive = TRUE, showWarnings = FALSE); file.copy(file.path(ROOT, lf), file.path(RR, lf), overwrite = TRUE) }
    m1b <- tryCatch(PE$.rfp_check_measurement(mkm(ap_ok), PRX, RR, pcfg_live, TRUE), error = function(e) conditionMessage(e))
    chk(sprintf("RT1b 운영 설정 그대로(등재 · file=%s) → 소비자가 이 계약 산출을 받고 value(δ 풀링) 재도출", lf),
        is.list(m1b) && isTRUE(all.equal(m1b$value, r$value)), if (is.character(m1b)) substr(m1b, 1, 100) else sprintf("(%.4f)", m1b$value))
  }
  pcfg <- pcfg_live
  pcfg$verdict$contracts[["sleeve_delivery"]] <- list(file = "02_Infrastructure/contracts/sleeve_delivery.R",
    artifact_hint = "PR-L2 처치 전달량 — sd_measure(산출 디렉터리 · section=sleeve_delivery) → sd_write JSON · 최상위 value(시그널일 평균)·measurement_regime",
    artifact_regime_required = TRUE)
  RTX <- function(m, pr = PRX, cf = pcfg) tryCatch(PE$.rfp_check_measurement(m, pr, RR, cf, TRUE), error = function(e) conditionMessage(e))
  mm <- RTX(mkm(ap_ok))
  chk("RT2 등재판 설정 — 소비자가 산출을 받고 value 를 산출물에서 재도출(= 계약 값)", is.list(mm) && isTRUE(all.equal(mm$value, r$value)),
      if (is.character(mm)) substr(mm, 1, 100) else sprintf("(%.4f)", mm$value))
  e3 <- RTX(mkm(ap_ok), pr = modifyList(PRX, list(measurement_regime = list(exec_price = "close_d_legacy"))))
  chk("RT3 사전등록 규약 ≠ 산출 규약 → 거부", is.character(e3) && grepl("규약", e3), substr(as.character(e3)[1], 1, 80))
  r4 <- r; r4$measurement_regime <- NULL; ap4 <- sd_write(r4, ADIR, prefix = "rt_noregime")
  e4 <- RTX(mkm(ap4)); chk("RT4 산출 measurement_regime 누락 → 거부(artifact_regime_required)", is.character(e4) && grepl("measurement_regime", e4), substr(as.character(e4)[1], 1, 80))
  e5 <- RTX(mkm(ap_ok, value = r$value + 0.01)); chk("RT5 손 수치(주장 value ≠ 산출) → 거부(AX-008)", is.character(e5) && grepl("산출물에서만", e5), substr(as.character(e5)[1], 1, 80))
  # RT7 — preregfix 스테이징 항목 형식(file = 02_Infrastructure/reinforcement/rf_sleeve.R)으로도 같은 산출을 받는다(교차 키트 정합 · 배포 순서 무관)
  dir.create(file.path(RR, "02_Infrastructure/reinforcement"), recursive = TRUE, showWarnings = FALSE)
  file.copy(SLEEVE, file.path(RR, "02_Infrastructure/reinforcement/rf_sleeve.R"), overwrite = TRUE)
  pcfg7 <- pcfg_live; pcfg7$verdict$contracts[["sleeve_delivery"]] <- list(file = "02_Infrastructure/reinforcement/rf_sleeve.R",
    artifact_hint = "preregfix 스테이징판 형식", artifact_regime_required = TRUE)
  ap7 <- sd_write(r, ADIR, prefix = "rt_7", metric = "dlv", target = "F1.B7_37")
  m7 <- RTX(c(list(metric = "dlv", target = "F1.B7_37"), list(source = list(contract = "sleeve_delivery", artifact = rel(ap7),
           artifact_sha256 = PE$.rfp_sha_file(ap7), measurement_regime = list(exec_price = "close_t1")))), cf = pcfg7)
  chk("RT7 preregfix 형식 항목(file = rf_sleeve.R · fields 없음 = 최상위 value) → 수락 · value = δ 풀링",
      is.list(m7) && isTRUE(all.equal(m7$value, r$value)), if (is.character(m7)) substr(m7, 1, 100) else sprintf("(%.4f)", m7$value))
  ap7b <- sd_write(r, ADIR, prefix = "rt_7b", metric = "dlv", target = "F1.B7_40")
  e7b <- RTX(c(list(metric = "dlv", target = "F1.B7_37"), list(source = list(contract = "sleeve_delivery", artifact = rel(ap7b),
           artifact_sha256 = PE$.rfp_sha_file(ap7b), measurement_regime = list(exec_price = "close_t1")))), cf = pcfg7)
  chk("RT7b 산출 target(F1.B7_40) ≠ 측정 target(F1.B7_37) → 거부(다른 칸 산출 오귀속 차단)", is.character(e7b) && grepl("다른 대상", e7b), substr(as.character(e7b)[1], 1, 80))
  m6 <- mkm(ap_ok); cat(" ", file = ap_ok, append = TRUE)
  e6 <- RTX(m6); chk("RT6 바뀐 산출 파일(sha 불일치) → 거부", is.character(e6) && grepl("sha256", e6), substr(as.character(e6)[1], 1, 80))
}

cat("[M] 돌연변이\n")
src <- readLines(CONTRACT, encoding = "UTF-8", warn = FALSE)
mutant <- function(from, to) {
  hit <- which(grepl(from, src, fixed = TRUE)); if (length(hit) != 1L) return(NULL)
  s2 <- src; s2[hit] <- sub(from, to, s2[hit], fixed = TRUE)
  p <- file.path(TMP, sprintf("mut_%d.R", sample.int(1e6, 1))); writeLines(s2, p, useBytes = TRUE)
  e <- new.env(parent = globalenv()); invisible(capture.output(sys.source(p, envir = e, keep.source = FALSE))); e
}
mchk <- function(name, m, fn) if (is.null(m)) chk(paste(name, "— 대상 줄 1곳"), FALSE) else fn(m)
mchk("M1", mutant(".sd_same <- function(a, b) (is.na(a) && is.na(b))", ".sd_same <- function(a, b) TRUE || (is.na(a) && is.na(b))"),
     function(m) { e <- tryCatch({ m$sd_measure(file.path(TMP, "sum"), "sleeve_delivery"); "no_error" }, error = function(e) conditionMessage(e))
       chk("M1 엔진 요약 대조 제거 돌연변이는 I9 를 red 로(변조 통과)", identical(e, "no_error"), substr(e, 1, 60)) })
mchk("M2", mutant('if (length(ep) != 1L || !nzchar(ep)) stop(', 'if (FALSE) stop('), function(m) {
  e <- tryCatch({ m$sd_measure(file.path(TMP, "noexec"), "sleeve_delivery"); "no_error" }, error = function(e) conditionMessage(e))
  chk("M2 exec_price 검사 제거 돌연변이는 I3 을 red 로", identical(e, "no_error"), substr(e, 1, 60)) })
mchk("M3", mutant('|| any(R$n_new > R$n_sleeve)) stop(', ') stop('), function(m) {
  e <- tryCatch({ m$sd_measure(file.path(TMP, "nn"), "sleeve_delivery"); "no_error" }, error = function(e) conditionMessage(e))
  chk("M3 n_new ≤ n_sleeve 검사 제거 돌연변이는 I8 을 red 로(다른 가드가 잡으면 그 메시지)", identical(e, "no_error") || !grepl("n_new", e), substr(e, 1, 60)) })
if (is.function(RTX)) {
  mchk("M4", mutant("         measurement_regime = list(exec_price = ep, source = auth_name),", ""), function(m) {
    rm4 <- m$sd_measure(d_ok, "sleeve_delivery"); p4 <- sd_write(rm4, ADIR, prefix = "rt_mut4")
    e <- RTX(mkm(p4))
    chk("M4 산출 measurement_regime 누락 돌연변이는 RT2 를 red 로(소비자가 거부)", is.character(e) && grepl("measurement_regime", e), substr(as.character(e)[1], 1, 70)) })
} else chk("M4 소비자 왕복 돌연변이 — 소비자 부재", FALSE)
mchk("M5", mutant("  out <- list(value = pooled,", "  out <- list(value = if (length(v)) mean(v) else NA_real_,"), function(m) {
  e <- tryCatch(m$sd_measure(file.path(TMP, "vary"), "sleeve_delivery"), error = function(e) conditionMessage(e))
  chk("M5 value 를 등가중 평균으로 되돌린 돌연변이는 P5 를 red 로(또는 요약 대조가 멈춘다)",
      is.character(e) || !isTRUE(all.equal(e$value, 5 / 7)), if (is.list(e)) sprintf("(value %.4f)", e$value) else substr(e, 1, 60)) })

cat("[R] 루트 읽기 전용\n")
chk("R1 루트 contracts·06_Registry 최상위 지문 불변", identical(FP0, ROOT_FP()), sprintf("(%d 파일)", length(FP0)))
unlink(TMP, recursive = TRUE)
cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", pass, fail))
cat(sprintf('{"test":"sleeve_delivery","pass":%d,"fail":%d,"total":%d}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
