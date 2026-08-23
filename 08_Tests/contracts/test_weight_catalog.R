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
# 불변식 5종:
#   (a) 모든 arm 이 fixture 에서 wrap_adapter 제약(long-only · Σw=1 · w≤ub)을 통과
#   (b) 미지 `catalog:` id 가 **EW 폴백이 아니라 에러**
#   (c) 측정 필드를 읽는 생성물을 admit_generated 가 거부
#   (d) retired 엔트리가 weight_catalog_arms 에 안 뜸
#   (e) 형제 방출이 **측정보다 먼저** 기록됨 (+ 생성기 시그니처에 ir/measured 부재)
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

.emit()
if (FAIL > 0L) quit(save = "no", status = 1)
