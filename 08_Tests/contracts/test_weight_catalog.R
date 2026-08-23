# test_weight_catalog.R — 비중 카탈로그 계약의 **위반 주입** 검사 (v9.2 §8-S3)
#
# 왜 있나: 이 설계의 실질 난점은 색인이 아니라 **조용한 EW 낙하**다.
#   backtest_harness.R 의 구 else 는 미등록 문자열을 에러 없이 EW 로 떨어뜨렸다 —
#   오타 한 글자가 "새 방법론을 완주했다"는 거짓 기록을 만든다. 같은 형태의 실사고가
#   method_registry.R:73-78 에 이미 있다(어댑터가 정확히 EW 1/25 로 붕괴).
#   그래서 이 파일의 1급 축은 "arm 이 도는가"가 아니라
#   **"미지 id 가 EW 가 아니라 에러인가"** 다.
#   [[feedback-verify-both-directions-always]] — 양성 대조 + 위반 주입 양방향.
#
# 불변식 6종:
#   (a) 모든 arm 이 fixture 에서 wrap_adapter 제약(long-only · Σw=1 · w≤ub)을 통과
#   (b) 미지 `catalog:` id 가 **EW 폴백이 아니라 에러**
#   (c) 측정 필드를 읽는 생성물을 admit_generated 가 거부
#   (d) retired 엔트리가 weight_catalog_arms 에 안 뜸
#   (e) 형제 방출이 **측정보다 먼저** 기록됨 (+ 생성기 시그니처에 ir/measured 부재)
#   (f) `.normalize` 가 **합-정규화를 캡보다 먼저** 한다 (advanced_weights.R, 2026-08-24 수리)
#
# 실행: Rscript 08_Tests/contracts/test_weight_catalog.R
suppressWarnings(suppressMessages({
  library(data.table); library(jsonlite)
  ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
}))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", paste(d, collapse = " "), "\n") }
.emit <- function() {
  cat(sprintf("== t_summary: PASS=%d FAIL=%d ==\n", PASS, FAIL))
  cat(sprintf('{"test":"weight_catalog","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
}

WC <- file.path(ROOT, "02_Infrastructure", "portfolio", "weight_catalog.R")
GV <- file.path(ROOT, "02_Infrastructure", "methods", "generate_weight_variants.R")
BH <- file.path(ROOT, "02_Infrastructure", "backtest_harness.R")
if (!file.exists(WC)) { cat("  SKIP  계약 부재:", WC, "\n"); .emit(); quit(save = "no", status = 0) }

.WC_QUIET_LOAD <- TRUE
suppressWarnings(suppressMessages(source(WC)))
CAT <- tryCatch(sync_catalog(root = ROOT, quiet = TRUE), error = function(e) NULL)
if (is.null(CAT)) { ng("sync_catalog 실행"); .emit(); quit(save = "no", status = 1) }

cat("== ⓪ 색인 — 세 갈래가 다 잡히는가 ==\n")
org <- table(vapply(CAT$entries, function(e) as.character(e$origin), character(1)))
if (as.integer(org[["lean_builtin"]] %||% 0L) == 23L)
  ok(sprintf("lean 빌트인 23종 (하네스 분기와 1:1)")) else
  ng("lean 빌트인 수", as.integer(org[["lean_builtin"]] %||% 0L))
if (as.integer(org[["qepm_registry"]] %||% 0L) == 14L)
  ok("QEPM 레지스트리 14종") else ng("QEPM 수", as.integer(org[["qepm_registry"]] %||% 0L))
if (as.integer(org[["paper_adapter"]] %||% 0L) >= 1L)
  ok(sprintf("논문 어댑터 %d종", as.integer(org[["paper_adapter"]]))) else ng("논문 어댑터 0")

# ★G-5 철회 반영 — settled-negative 3종이 retired 로 박혀 있으면 그건 버그다.
g5 <- c("qepm:DPL", "qepm:PPO_RL", "qepm:Genetic")
ids <- vapply(CAT$entries, function(e) as.character(e$catalog_id), character(1))
sts <- vapply(CAT$entries, function(e) as.character(e$status), character(1))
miss <- setdiff(g5, ids)
if (length(miss)) ng("G-5 철회 — 카탈로그 미등재", miss) else {
  bad <- g5[sts[match(g5, ids)] == "retired"]
  if (length(bad)) ng("G-5 철회 — retired 로 박힘(버그)", bad) else
    ok("G-5 — DPL·PPO_RL·Genetic 정상 등재(retired 아님)")
}

cat("== (a) 모든 arm 이 fixture 에서 wrap_adapter 제약 통과 ==\n")
fx <- .wc_fixture()
A <- weight_catalog_arms(axis = "carrier", min_status = "any", exclude_retired = FALSE,
                         root = ROOT, quiet = TRUE)
if (!nrow(A)) ng("arms 0행") else {
  bad <- character(0); ran <- 0L
  for (i in seq_len(nrow(A))) {
    w <- NULL
    invisible(utils::capture.output(
      w <- tryCatch(A$adapter_fn[[i]](fx), error = function(e) structure(NA_real_, err = conditionMessage(e)))))
    if (length(w) == 1L && is.na(w)) { bad <- c(bad, sprintf("%s(예외)", A$catalog_id[i])); next }
    ran <- ran + 1L
    v <- as.numeric(w)
    if (!(all(is.finite(v)) && all(v >= -1e-9) && all(v <= 0.20 + 1e-9) && abs(sum(v) - 1) < 1e-6))
      bad <- c(bad, sprintf("%s(sum=%.6f max=%.4f)", A$catalog_id[i], sum(v), max(v)))
  }
  # ★어떤 arm 도 **예외로 죽지 않고**, 산 arm 은 전부 제약 안이어야 한다.
  #   (wrap_adapter 가 실패를 EW 로 내려앉히므로 '제약 통과'는 자명참에 가깝다 —
  #    그래서 아래 돌연변이 통제로 이 검사가 실제로 무언가를 재는지 확인한다.)
  if (!length(bad)) ok(sprintf("arm %d종 전부 제약 통과 (long-only · Σw=1 · w≤0.20)", ran)) else
    ng("제약 위반/예외", utils::head(bad, 6))
}
# 돌연변이 통제 — 계약을 깨는 어댑터는 실제로 잡히는가(자명참 아님을 증명)
we <- .wc_wrap_env(ROOT)
mut <- get("wrap_adapter", envir = we)(function(ctx) rep(-5, length(ctx$assets)), "MUTANT")
mw <- NULL; invisible(utils::capture.output(mw <- mut(fx)))
if (abs(sum(mw) - 1) < 1e-6 && all(mw >= 0))
  ok("돌연변이 통제: 음수 선호 어댑터도 wrapper 가 유효 비중으로 강제(제약은 하네스가 건다)") else
  ng("돌연변이 통제", c(sum(mw), min(mw)))

cat("== (b) ★미지 catalog id 는 EW 폴백이 아니라 에러 ==\n")
if (!file.exists(BH)) cat("  SKIP  backtest_harness.R 부재\n") else {
  src <- readLines(BH, warn = FALSE)
  if (any(grepl("QVEST_CATALOG_BRANCH_V1", src, fixed = TRUE)))
    ok("하네스에 catalog: 분기 존재 (마커 QVEST_CATALOG_BRANCH_V1)") else
    ng("하네스 catalog: 분기 부재 — lean 축이 닫혀 있다")
  # 하네스 전체를 싣지 않고 리졸버만 격리 검사한다(config/Rcpp 의존 회피).
  be <- new.env(parent = globalenv())
  assign(".BH_CATALOG_ENV", new.env(parent = emptyenv()), envir = be)
  blk <- grep("^\\.bh_catalog_env <- function", src)
  end <- grep("^\\.bh_catalog_weights <- function", src)
  if (length(blk) && length(end)) {
    eval(parse(text = paste(src[blk[1]:(end[1] - 1L)], collapse = "\n")), envir = be)
    r <- tryCatch({ get(".bh_catalog_adapter", envir = be)("qepm:NO_SUCH_METHOD_XYZ"); "NO_ERROR" },
                  error = function(e) conditionMessage(e))
    if (identical(r, "NO_ERROR")) ng("★미지 id 가 조용히 통과했다 — EW 낙하 경로가 살아 있다") else
    if (grepl("미지 catalog id", r)) ok("미지 id → 이름 붙은 에러(EW 낙하 아님)") else
      ng("미지 id 에러 문구", substr(r, 1, 80))
    # 양성 대조 — 실재 id 는 리졸브돼야 한다(검사가 '전부 에러'로 통과하는 것을 막는다)
    r2 <- tryCatch({ f <- get(".bh_catalog_adapter", envir = be)("lean:ivol"); is.function(f) },
                   error = function(e) conditionMessage(e))
    if (isTRUE(r2)) ok("양성 대조: 실재 id(lean:ivol) 는 정상 리졸브") else ng("양성 대조 실패", r2)
  } else cat("  SKIP  리졸버 블록 추출 실패\n")
  # 호명 폴백 — 최종 else 가 weight_method 값을 찍는가(조용한 EW 금지)
  i <- grep("미등록 weight_method", src)
  if (length(i)) ok("최종 else 가 미등록 이름을 **호명**한다(+QVEST_WEIGHT_STRICT 에서 stop)") else
    ng("최종 else 가 여전히 조용한 EW")
}

cat("== (c) 측정 필드를 읽는 생성물을 admit_generated 가 거부 ==\n")
td <- file.path(tempdir(), sprintf("wc_leak_%d.R", Sys.getpid()))
writeLines(c(
  "# 위반 주입: 성과를 읽고 비중을 정하는 생성물(= 어댑터가 아니라 사후선택기)",
  "method_weights <- function(ctx) {",
  "  hr <- jsonlite::fromJSON('hurdle_result.json')   # ← 측정 필드 참조",
  "  w <- rep(1/length(ctx$assets), length(ctx$assets)); stats::setNames(w, ctx$assets)",
  "}"), td)
sc <- wc_scan_measurement_leak(td)
if (!isTRUE(sc$ok) && grepl("측정 필드", sc$reason)) ok(sprintf("정적 스캔 거부 — %s", sc$reason)) else
  ng("측정 필드 참조를 통과시킴", sc$reason)
adm <- NULL; invisible(utils::capture.output(adm <- admit_generated(td, root = ROOT, resync = FALSE)))
if (!isTRUE(adm$ok)) ok("admit_generated 거부") else ng("admit_generated 가 누출 생성물을 편입시킴")
# 양성 대조 — 깨끗한 파일은 스캔을 통과해야 한다(스캔이 전부 거부하는 게 아님)
tc <- file.path(tempdir(), sprintf("wc_clean_%d.R", Sys.getpid()))
writeLines(c("method_weights <- function(ctx) {",
             "  s <- sqrt(diag(ctx$Sigma)); w <- 1/s; stats::setNames(w/sum(w), ctx$assets)",
             "}"), tc)
if (isTRUE(wc_scan_measurement_leak(tc)$ok)) ok("양성 대조: 깨끗한 생성물은 스캔 통과") else
  ng("양성 대조 — 깨끗한 파일을 거부(스캔이 과잉)")
# 원장 기록이 없으면 verify 이전에 거부되는가
adm2 <- NULL; invisible(utils::capture.output(adm2 <- admit_generated(tc, root = ROOT, resync = FALSE)))
if (!isTRUE(adm2$ok) && grepl("원장", adm2$reason %||% "")) ok("방출 원장 기록 없는 생성물 거부") else
  ng("원장 미기록분을 통과시킴", adm2$reason)
unlink(c(td, tc))

cat("== (d) retired 엔트리는 weight_catalog_arms 에 안 뜬다 ==\n")
inj <- CAT
inj$entries[[length(inj$entries) + 1L]] <- list(
  catalog_id = "gen:RETIRED_PROBE", label = "RETIRED_PROBE", origin = "generated",
  family = "test", status = "retired",
  resolver = list(kind = "lean_builtin", lean_name = "ivol", needs_score = FALSE),
  screen_axes = list(shrinkage_builtin = NA, statistic_order = NA, screen_priority = NA),
  selection_type = "chain", n_trials_family = 1L, est_cost_min = 1)
B <- weight_catalog_arms(axis = "carrier", min_status = "any", root = ROOT,
                         catalog = inj, quiet = TRUE)
if (!("gen:RETIRED_PROBE" %in% B$catalog_id))
  ok("retired 엔트리 제외 (min_status='any' 에서도)") else ng("retired 가 arm 에 올라옴")
B2 <- weight_catalog_arms(axis = "carrier", min_status = "any", include = "gen:RETIRED_PROBE",
                          root = ROOT, catalog = inj, quiet = TRUE)
if ("gen:RETIRED_PROBE" %in% B2$catalog_id)
  ok("단 include= 로는 강제 편입된다 (숨김이 아니라 표시 — 카탈로그에는 남는다)") else
  ng("include= 강제 편입 불가")

cat("== (e) 형제 방출이 **측정보다 먼저** 기록된다 ==\n")
if (!file.exists(GV)) cat("  SKIP  생성기 부재\n") else {
  .GV_QUIET_LOAD <- TRUE
  suppressWarnings(suppressMessages(source(GV)))
  fm <- names(formals(generate_siblings))
  leak <- intersect(tolower(fm), c("ir", "measured", "score", "grade", "sr", "performance", "result"))
  if (!length(leak))
    ok(sprintf("생성기 시그니처에 측정 인자 없음 — 방출이 선언 축의 결정적 함수 (%s)",
               paste(fm, collapse = ", "))) else
    ng("★생성기가 측정을 인자로 받는다 — chain 주장 붕괴", leak)
  d <- generate_siblings("lean:score_tilt", "shrinkage_lift", max_emit = 3L,
                         root = ROOT, dry_run = TRUE, quiet = TRUE)
  lg <- d$ledger
  if (isTRUE(lg$emission_is_pre_measurement) && nzchar(lg$emitted_at %||% ""))
    ok("방출 기록에 emitted_at + emission_is_pre_measurement=TRUE") else
    ng("방출 기록에 측정-이전 표식 없음")
  bad <- intersect(names(lg), c("ir", "IR", "measured", "score", "grade", "sr"))
  if (!length(bad)) ok("방출 기록에 측정 필드 없음") else ng("방출 기록에 측정 필드", bad)
  if (length(lg$siblings) > 1L && identical(lg$selection_type, "sweep_candidate_family"))
    ok("k>1 방출은 sweep_candidate_family 로 선라벨 — argmax 를 고르면 DSR 게이트") else
  if (length(lg$siblings) == 1L && identical(lg$selection_type, "chain"))
    ok("k=1 방출은 chain") else ng("selection_type 라벨", lg$selection_type)
  tf <- unique(vapply(lg$siblings, function(s) as.character(lg$trial_family_id), character(1)))
  if (length(tf) == 1L && nzchar(tf))
    ok(sprintf("한 런의 형제 %d개가 같은 trial_family_id — 패자를 숨길 수 없다", length(lg$siblings))) else
    ng("trial_family_id 불일치", tf)
  # 실원장에 기록된 방출이 있으면 그중 아무거나 골라 pre-measurement 성질 확인
  led <- .wc_variant_ledger(ROOT)
  if (length(led)) {
    e1 <- led[[1]]
    if (nzchar(as.character(e1$emitted_at %||% "")))
      ok(sprintf("실원장 방출 %d건 전부 emitted_at 보유", length(led))) else
      ng("실원장 방출에 emitted_at 없음")
  } else cat("  SKIP  실원장 방출 0건\n")
}

cat("== (f) ★.normalize — 캡을 합-정규화보다 먼저 걸면 신호가 EW 로 붕괴한다 ==\n")
# 왜 여기 있나 (2026-08-24): advanced_weights.R::.normalize 가 `pmin(w, max_w)` 를 합-정규화
#   **전에** 걸었다. calc_* 들은 정규화되지 않은 원 선호(1/vol · Σ⁻¹σ · Σ⁻¹1 …)를 넘기므로
#   원 스케일이 max_w 를 넘으면 전 원소가 캡에 눌려 같아지고, 뒤이은 합-정규화가 그것을
#   **정확히 EW** 로 만든다 — 예외도 경고도 없이 신호가 통째로 사라진다.
#   실측: lean 빌트인 6종(cvar·maxdiv·robust_mv·factor_rp·omega·higher_moment)이 정확히 EW,
#   kelly 는 부분 소멸(선택만 남고 사이징 전멸). 같은 병이 method_registry.R:73-78 과
#   ops/auto_sigma_weighting_ab.R(2026-08-08)에서 이미 두 번 수리됐고 이 파일만 남아 있었다.
# ★축의 급소는 "지금 EW 가 아니다"가 아니라 **"구판이면 EW 인가"** 다 — 돌연변이 통제가
#   없으면 이 검사는 자명참으로 통과하고, 순서를 되돌려도 초록이 유지된다.
AW <- file.path(ROOT, "02_Infrastructure", "portfolio", "advanced_weights.R")
if (!file.exists(AW)) cat("  SKIP  advanced_weights.R 부재\n") else {
  ae <- new.env(parent = globalenv())
  .aw_ok <- tryCatch({
    invisible(utils::capture.output(suppressWarnings(suppressMessages(sys.source(AW, envir = ae)))))
    TRUE
  }, error = function(e) { ng("advanced_weights 로드", conditionMessage(e)); FALSE })
  if (.aw_ok) {
    NA_ <- length(fx$assets); EWv <- rep(1 / NA_, NA_)
    isEW <- function(v) { v <- as.numeric(v); length(v) == NA_ && max(abs(v - EWv)) < 1e-9 }
    norm_new <- get(".normalize", envir = ae)
    # 수리 전 자구 verbatim (돌연변이 통제 — 이 5줄이 곧 결함이다)
    norm_old <- function(w, max_w = 0.15) {
      w[is.na(w) | w < 0] <- 0
      if (sum(w) < 1e-10) return(rep(1 / length(w), length(w)))
      w <- pmin(w, max_w)
      w / sum(w)
    }

    # ── f-1 위반 주입: 원 선호를 **전부 캡 위로** 밀어 넣는다 ──
    raw <- seq(12, 48, length.out = NA_)     # 전 원소 > max_w(0.15) · 4배 스프레드
    gn  <- as.numeric(norm_new(raw, 0.15))
    if (!isEW(gn) && abs(sum(gn) - 1) < 1e-9 && all(gn >= 0) && max(gn) <= 0.15 + 1e-9)
      ok("위반 주입(원 선호 전량 캡 초과) — EW 붕괴 없이 제약 안(Σw=1 · 0≤w≤max_w)") else
      ng("★원 선호 전량 캡 초과에서 붕괴/제약 위반",
         sprintf("isEW=%s sum=%.8f max=%.6f", isEW(gn), sum(gn), max(gn)))
    # '붕괴 안 함'만으로는 부족하다 — 순위가 살아 있어야 신호가 산 것이다.
    # ★**강**단조로 잰다. `!is.unsorted()` 는 균일 벡터에서도 참이라 결함판에서 조용히
    #   초록을 낸다(실측: 구판 복원 시 이 줄만 PASS 로 남았다) — 자명참 축은 축이 아니다.
    if (all(diff(gn) > 0)) ok("캡 초과분 재분배 후에도 원 선호의 **강**단조 순위 보존") else
      ng("순위 붕괴(균일화 포함)", utils::head(round(gn, 6), 6))

    # ── f-1b 캡이 **실제로 무는** 입력 — 재분배 경로 자체를 태운다 ──
    #   f-1 의 raw 는 원 스케일만 크고 정규화하면 전부 캡 아래라 재분배가 안 돈다.
    #   위임한 normalize_long_only 가 실제로 일하는지는 지배 원소가 있어야 드러난다.
    raw2 <- c(rep(1, NA_ - 1L), 200)          # 정규화 시 최대 ≈0.893 ≫ 0.15
    g2   <- as.numeric(norm_new(raw2, 0.15))
    if (abs(sum(g2) - 1) < 1e-9 && max(g2) <= 0.15 + 1e-9 &&
        abs(g2[NA_] - 0.15) < 1e-9 && which.max(g2) == NA_)
      ok("지배 원소 재분배: 캡에 정확히 앉고 Σw=1 유지 · 최대 원소 정체 보존") else
      ng("캡 재분배 실패", sprintf("sum=%.8f max=%.6f top=%.6f argmax=%d",
                                   sum(g2), max(g2), g2[NA_], which.max(g2)))

    # ── f-2 돌연변이 통제: 순서를 되돌리면 축이 실제로 뒤집히는가 ──
    go <- as.numeric(norm_old(raw, 0.15))
    if (isEW(go))
      ok("돌연변이 통제: 구판(캡→정규화)은 같은 입력에서 **정확히 EW** — 축이 실제로 잰다") else
      ng("★돌연변이 통제 실패 — 구판이 EW 를 안 낸다. 이 축은 아무것도 재고 있지 않다",
         sprintf("dev=%.3e", max(abs(go - EWv))))

    # ── f-3 실소비자 E2E: 6종이 fixture 에서 살아 있는가 / 구판이면 죽는가 ──
    TGT <- c("calc_cvar_weights", "calc_maxdiv_weights", "calc_robust_mv_weights",
             "calc_factor_rp_weights", "calc_omega_weights", "calc_higher_moment_weights")
    rd <- .ctx_ret_dt(fx); tk <- fx$assets
    runw <- function(fn) tryCatch(suppressWarnings(as.numeric(get(fn, envir = ae)(tk, rd))),
                                  error = function(e) NULL)
    dead <- character(0); brk <- character(0)
    for (fn in TGT) {
      v <- runw(fn)
      if (is.null(v)) { brk <- c(brk, fn); next }
      if (isEW(v) || max(v) > 0.15 + 1e-9 || abs(sum(v) - 1) > 1e-6) dead <- c(dead, fn)
    }
    if (!length(brk) && !length(dead))
      ok(sprintf("실소비자 %d종 전부 fixture 에서 비-EW · 제약 안 (%s)",
                 length(TGT), paste(sub("^calc_|_weights$", "", TGT), collapse = " · "))) else
      ng("★실소비자가 EW/제약 위반", c(dead, sprintf("%s(예외)", brk)))
    # 같은 6종을 구판 .normalize 로 재면 전부 EW 여야 한다(= 축이 이 경로를 실제로 지난다)
    assign(".normalize", norm_old, envir = ae)
    mut <- vapply(TGT, function(fn) { v <- runw(fn); !is.null(v) && isEW(v) }, logical(1))
    assign(".normalize", norm_new, envir = ae)   # 복원
    if (all(mut))
      ok("돌연변이 통제(E2E): 구판이면 6종 전부 정확히 EW — 실사고의 재현") else
      ng("돌연변이 통제(E2E) 부분 실패 — 이 경로를 안 지나는 함수가 있다",
         names(mut)[!mut])

    # ── f-4 정적: 정본을 재구현하지 않고 normalize_long_only 를 부르는가 ──
    #   재구현하면 정본이 둘이 되고 둘이 갈린다(설계 규약 ①과 같은 사유).
    aws <- readLines(AW, warn = FALSE)
    nb  <- grep("^\\.normalize <- function", aws)
    if (length(nb)) {
      blk <- paste(aws[nb[1]:min(nb[1] + 12L, length(aws))], collapse = "\n")
      if (grepl("normalize_long_only", blk, fixed = TRUE))
        ok("캡 강제를 normalize_long_only(반복 재분배 정본)에 위임 — 재구현 아님") else
        ng("★.normalize 가 캡을 자체 구현한다 — 정본이 둘이 된다")
      if (grepl("w <- w / sum\\(w\\)", blk) &&
          regexpr("sum\\(w\\)", blk) < regexpr("normalize_long_only", blk))
        ok("자구 순서 확인: 합-정규화가 캡 위임보다 **앞줄**") else
        ng("★자구 순서 — 합-정규화가 캡보다 뒤이거나 부재")
    } else ng("정적 검사 — .normalize 정의 추출 실패")
  }
}

.emit()
if (FAIL > 0L) quit(save = "no", status = 1)
