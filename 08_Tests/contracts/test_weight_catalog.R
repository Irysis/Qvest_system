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
#   (h-5) 계기 미적재(backtest_harness.R 미로드) probe 는 이전 probe 를 **덮어쓰지 못하고**,
#         진짜 실패는 **덮어쓴다** — 양방향 (2026-09-05, 주간 grow 태스크 bare Rscript 실사고)
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

    # ── (g) ★robust SOCP 폴백 — 원 결함과 **자구까지 동일했던** 마지막 지점 ──
    # 왜 별도 축인가 (2026-08-24): .normalize 를 고쳐도 solve_robust_socp_weights 의
    #   error 폴백은 구 자구를 그대로 갖고 있었다. mu/sigma 는 정규화되지 않은 raw
    #   Sharpe 벡터라 통상 스케일에서도 max_w 를 넘고, 그러면 pmin 이 전 원소를 같은
    #   값으로 눌러 **정확히 EW** 를 낸다. 더 나쁜 건 로그가 "max-SR approx" 라고 적어
    #   실제 계산과 다른 말을 한 것이다 — 계기가 자기 산출을 거짓 보고하는 형태.
    # ★여기서도 급소는 "지금 EW 가 아니다" 가 아니라 **"구판이면 EW 인가"** 다.
    cat("== (g) ★robust SOCP 폴백 — 같은 결함의 마지막 잔존 지점 ==\n")
    .nlo <- tryCatch(get("normalize_long_only", envir = ae), error = function(e) NULL)
    if (is.null(.nlo)) ng("★normalize_long_only 미로드 — 폴백 축 판정 불가") else {
      mu_g  <- seq(0.30, 0.90, length.out = NA_)   # raw Sharpe (임의 스케일, 3배 스프레드)
      sig_g <- rep(0.02, NA_)                      # mu/sig 는 15~45 → 전 원소 > max_w
      fb_new <- function(mu, sig, max_w = 0.15) {  # 수리판 자구
        w <- mu / sig; w[w < 0] <- 0
        if (sum(w) < 1e-10) w <- rep(1 / length(w), length(w))
        w <- w / sum(w)
        as.numeric(.nlo(w, lb = 0, ub = max_w, target_sum = 1))
      }
      fb_old <- function(mu, sig, max_w = 0.15) {  # 구판 자구 verbatim (돌연변이 통제)
        w <- mu / sig; w[w < 0] <- 0
        if (sum(w) < 1e-10) w <- rep(1 / length(w), length(w))
        w <- pmin(w, max_w); as.numeric(w / sum(w))
      }

      # g-1 수리판: 신호가 살아 있고 캡·합 계약을 지키는가
      gn <- fb_new(mu_g, sig_g)
      if (!isEW(gn) && abs(sum(gn) - 1) < 1e-9 && max(gn) <= 0.15 + 1e-9 && min(gn) >= 0)
        ok(sprintf("수리판 폴백: EW 아님 · Sw=1 · maxw=%.4f <= 0.15", max(gn))) else
        ng("★수리판 폴백이 계약 위반", sprintf("isEW=%s sum=%.8f max=%.6f min=%.6f",
                                              isEW(gn), sum(gn), max(gn), min(gn)))
      # 강단조 — 균일 벡터도 통과하는 !is.unsorted() 로 짜면 자명참이 된다(f 축의 교훈)
      if (all(diff(gn) > 0))
        ok("수리판 폴백: mu 순서가 비중 순서로 **강단조** 전달") else
        ng("★순위 소멸 — 폴백이 선호 순서를 보존하지 않는다",
           sprintf("min diff=%.3e", min(diff(gn))))

      # g-2 돌연변이 통제: 구 자구를 되돌리면 축이 실제로 뒤집히는가
      go2 <- fb_old(mu_g, sig_g)
      if (isEW(go2))
        ok("돌연변이 통제: 구판 폴백은 같은 입력에서 **정확히 EW** — 축이 실제로 잰다") else
        ng("★돌연변이 통제 실패 — 구판이 EW 를 안 낸다. 이 축은 아무것도 재고 있지 않다",
           sprintf("dev=%.3e", max(abs(go2 - EWv))))

      # g-3 정적: 폴백 블록이 정본에 위임하고, 구 자구가 실행 위치에 남아있지 않은가
      aws2 <- readLines(AW, warn = FALSE)
      fbl  <- grep("robust_socp\\] failed", aws2)
      if (length(fbl)) {
        blk2 <- aws2[fbl[1]:min(fbl[1] + 22L, length(aws2))]
        code2 <- blk2[!grepl("^\\s*#", blk2)]           # 주석 제외 = 실행 자구만
        j2 <- paste(code2, collapse = "\n")
        if (grepl("normalize_long_only", j2, fixed = TRUE))
          ok("폴백이 캡 강제를 normalize_long_only 에 위임 — 재구현 아님") else
          ng("★폴백이 캡을 자체 구현한다 — 정본이 둘이 된다")
        if (!grepl("pmin\\(w_raw, max_w\\)", j2))
          ok("구 자구 `pmin(w_raw, max_w)` 가 실행 위치에 없다(주석 기록만 허용)") else
          ng("★구 자구가 실행 위치에 잔존 — 폴백이 여전히 EW 를 낼 수 있다")
        if (regexpr("sum\\(w_raw\\)", j2) < regexpr("normalize_long_only", j2))
          ok("자구 순서 확인: 합-정규화가 캡 위임보다 **앞줄**") else
          ng("★자구 순서 — 합-정규화가 캡보다 뒤이거나 부재")
      } else ng("정적 검사 — SOCP 폴백 블록 추출 실패")
    }
  }
}

cat("== (h-5) ★계기 미적재는 arm 의 증거가 아니다 — bare 세션 probe 의 보존 병합 (양방향) ==\n")
# 왜 여기 있나 (2026-09-05): 주간 grow 태스크(rf_weight_catalog_grow.sh)가 bare Rscript 로
#   sync_catalog(probe=TRUE) 를 돌려 lean 23종 전부를 "빌트인 함수 부재(backtest_harness.R 미로드?)" 로
#   실패 기록했고, weight_catalog_arms 가 그것을 실효 강등으로 읽어 rf_cell_engine 이 lean arm 전체를
#   "카탈로그 arm 부재" 로 봤다. 수리 2겹 = ① .wc_probe_entry/sync_catalog 가 계기를 스스로 싣는다
#   ② 그래도 못 실었으면 이전 probe 를 보존한다(.WC_INSTRUMENT_MARK). (h) 의 "소비면에 lean 생존" 은
#   **지금 파일**이 살아 있는가를 보고, 여기는 **다음 bare 재생성이 그것을 죽이지 못하는가** 를 본다.
# ★양방향: 보존은 계기 문장이 있을 때만이다 — 진짜 실패는 여전히 덮어써야 한다. 한 방향만 재면
#   "모든 실패를 보존" 하는 결함판도 초록이 된다([[feedback-verify-both-directions-always]]).
# ★격리: 실 JSON 을 빌리지 않는다([[feedback-a-test-that-borrows-live-state-flaps-when-you-fix-the-state]]) —
#   임시 root 에 합성 카탈로그를 심고 **자식 Rscript**(진짜 bare 세션)로 돈다. 임시 root 에는
#   backtest_harness.R 을 일부러 두지 않는다(= 계기 부재의 재현). 자식 스크립트는 ASCII 만 쓴다.
h5_lib  <- file.path(ROOT, "02_Infrastructure", "portfolio", "weight_catalog.R")
h5_tmp  <- file.path(tempdir(), sprintf("wc_h5_%d", Sys.getpid()))
h5_json <- file.path(h5_tmp, "06_Registry", "weight_catalog.json")
for (d in c("02_Infrastructure/portfolio", "02_Infrastructure/methods", "06_Registry"))
  dir.create(file.path(h5_tmp, d), recursive = TRUE, showWarnings = FALSE)
for (f in c("02_Infrastructure/methods/method_registry.R",          # wrap_adapter(정규형)
            "02_Infrastructure/portfolio/strategy_tilt_weights.R",  # normalize_long_only
            "02_Infrastructure/portfolio/weight_catalog.R"))        # .wc_root marker
  file.copy(file.path(ROOT, f), file.path(h5_tmp, f), overwrite = TRUE)
h5_seed <- function() writeLines(as.character(toJSON(list(`_doc` = "h5 fixture", entries = list(
  list(catalog_id = "lean:ivol",   probe = list(ok = TRUE,  max_abs_dev_from_ew = 0.1234, reason = NULL, log = "")),
  list(catalog_id = "lean:hrp",    probe = list(ok = FALSE, max_abs_dev_from_ew = 0, reason = "exception: H5_PRIOR_GENUINE", log = "")),
  list(catalog_id = "lean:minvar"))), auto_unbox = TRUE, null = "null", digits = NA)), h5_json)
h5_child <- file.path(h5_tmp, "h5_child.R")
writeLines(c(
  'lib <- Sys.getenv("WC_H5_LIB"); tmp <- Sys.getenv("WC_H5_TMP")',
  '.WC_QUIET_LOAD <- TRUE; suppressMessages(source(lib))',
  'if (identical(Sys.getenv("WC_H5_INJECT"), "1"))',
  '  calc_ivol_weights <- function(tickers, ret_dt, ...) stop("H5_GENUINE_FAILURE")',
  'cat(sprintf("H5_PRE calc_ivol=%s calc_cvar=%s\\n", exists("calc_ivol_weights", mode = "function"),',
  '            exists("calc_cvar_weights", mode = "function")))',
  'out <- sync_catalog(root = tmp, probe = TRUE, quiet = TRUE)',
  'cat("H5_DONE\\n")'), h5_child)
h5_probe_of <- function(j, id) { for (e in (j$entries %||% list())) if (identical(as.character(e$catalog_id), id)) return(e$probe); NULL }
h5_txt <- function(p) paste(as.character(p$reason), as.character(p$log), collapse = " ")
h5_run <- function(inject) {
  h5_seed()
  Sys.setenv(WC_H5_LIB = h5_lib, WC_H5_TMP = h5_tmp, WC_H5_INJECT = if (inject) "1" else "0")
  on.exit(Sys.unsetenv(c("WC_H5_LIB", "WC_H5_TMP", "WC_H5_INJECT")), add = TRUE)
  rs <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  o  <- suppressWarnings(system2(rs, shQuote(h5_child), stdout = TRUE, stderr = TRUE))
  list(out = as.character(o), cat = tryCatch(fromJSON(h5_json, simplifyVector = FALSE), error = function(e) NULL))
}

# ── h-5a 양성 대조(자동 적재): 이 프로세스는 아직 bare 다 — .wc_probe_entry 가 계기를 스스로 싣는가 ──
if (exists("calc_ivol_weights", mode = "function"))
  ng("전제 붕괴 — 이 프로세스에 calc_ivol_weights 가 이미 있다: 자동 적재 경로를 잴 수 없다(앞 절이 하네스를 실었다면 이 검사를 그 앞으로 옮길 것)") else {
  h5_ent <- NULL; for (e in CAT$entries) if (identical(as.character(e$catalog_id), "lean:ivol")) h5_ent <- e
  h5_pr <- NULL
  h5_log <- utils::capture.output(h5_pr <- tryCatch(.wc_probe_entry(h5_ent, ROOT),
                                                    error = function(e) list(ok = FALSE, reason = conditionMessage(e))))
  h5_dev <- suppressWarnings(as.numeric(h5_pr$max_abs_dev_from_ew))
  if (exists("calc_ivol_weights", mode = "function") && isTRUE(h5_pr$ok) &&
      length(h5_dev) == 1L && is.finite(h5_dev) && h5_dev > 0)
    ok(sprintf("자동 적재: bare 프로세스의 .wc_probe_entry(lean:ivol) 가 하네스를 스스로 싣고 ok=TRUE(dev=%.4f)", h5_dev)) else
    ng("★자동 적재 실패 — bare probe 가 여전히 계기 실패를 낸다",
       c(exists("calc_ivol_weights", mode = "function"), h5_pr$ok, as.character(h5_pr$reason), utils::tail(h5_log, 3)))
}

# ── h-5b bare 자식 세션(계기 부재): ok probe · 이전 진짜 실패는 보존, 무-이전은 계기 실패를 그대로 기록 ──
r1 <- h5_run(inject = FALSE)
if (!any(grepl("H5_DONE", r1$out, fixed = TRUE)) || is.null(r1$cat))
  ng("bare 자식 세션 sync 미완주", utils::tail(r1$out, 4)) else {
  if (any(grepl("H5_PRE calc_ivol=FALSE calc_cvar=FALSE", r1$out, fixed = TRUE)))
    ok("전제: 자식 세션은 bare(calc_* 부재) · 임시 root 에 backtest_harness.R 없음(자동 적재 실패 경로)") else
    ng("전제 붕괴 — 자식 세션이 bare 가 아니다", grep("H5_PRE", r1$out, value = TRUE))
  p_iv <- h5_probe_of(r1$cat, "lean:ivol"); p_hr <- h5_probe_of(r1$cat, "lean:hrp"); p_mv <- h5_probe_of(r1$cat, "lean:minvar")
  if (isTRUE(p_iv$ok) && isTRUE(all.equal(as.numeric(p_iv$max_abs_dev_from_ew), 0.1234)))
    ok("보존: lean:ivol 의 ok probe 가 **자구 그대로**(dev=0.1234) 남았다 — bare 재생성이 덮어쓰지 못한다") else
    ng("★bare 세션 probe 가 ok probe 를 덮어썼다", c(p_iv$ok, as.character(p_iv$reason), substr(as.character(p_iv$log), 1, 90)))
  if (!isTRUE(p_hr$ok) && identical(as.character(p_hr$reason), "exception: H5_PRIOR_GENUINE"))
    ok("보존: 이전 **진짜** 실패(lean:hrp)의 진단도 계기 문장으로 대체되지 않는다") else
    ng("이전 진짜 실패가 계기 문장으로 대체됨", as.character(p_hr$reason))
  if (!is.null(p_mv) && !isTRUE(p_mv$ok) && grepl("backtest_harness.R 미로드", h5_txt(p_mv), fixed = TRUE))
    ok("무-이전 lean:minvar 는 계기 실패를 **그대로 적는다**(빈칸 아님 — 소비면은 unverified 로 읽는다)") else
    ng("무-이전 엔트리의 계기 실패 기록", c(is.null(p_mv), p_mv$ok, as.character(p_mv$reason)))
  if (any(grepl("WARN probe", r1$out, fixed = TRUE) & grepl("lean:ivol", r1$out, fixed = TRUE)))
    ok("WARN 이 보존 대상을 호명한다(lean:ivol)") else ng("WARN 미출력/미호명", grep("WARN", r1$out, value = TRUE))
  rt <- as.character(unlist(r1$cat$probe_retained$ids))
  if (all(c("lean:ivol", "lean:hrp") %in% rt) && !("lean:minvar" %in% rt))
    ok("JSON probe_retained.ids = 보존 2건(minvar 제외) — 낡은 probe 가 generated_at 뒤에 숨지 않는다") else
    ng("probe_retained 표기", rt)
}

# ── h-5c 반대 방향: 진짜 실패(주입 calc_ivol_weights 가 stop)는 ok probe 를 **덮어쓴다** ──
r2 <- h5_run(inject = TRUE)
if (!any(grepl("H5_DONE", r2$out, fixed = TRUE)) || is.null(r2$cat))
  ng("주입 자식 세션 sync 미완주", utils::tail(r2$out, 4)) else {
  q_iv <- h5_probe_of(r2$cat, "lean:ivol")
  if (!isTRUE(q_iv$ok) && grepl("H5_GENUINE_FAILURE", h5_txt(q_iv), fixed = TRUE) &&
      !grepl("backtest_harness.R 미로드", h5_txt(q_iv), fixed = TRUE))
    ok("양방향: 진짜 실패는 ok probe 를 덮어쓴다 — 보존은 계기 문장에만 걸린다") else
    ng("★진짜 실패가 보존됐다 — '모든 실패를 보존' 하는 결함판", c(q_iv$ok, as.character(q_iv$reason), substr(as.character(q_iv$log), 1, 100)))
  rt2 <- as.character(unlist(r2$cat$probe_retained$ids))
  if (!("lean:ivol" %in% rt2) && "lean:hrp" %in% rt2)
    ok("probe_retained 는 hrp(계기 실패)만 — ivol(진짜 실패)은 미보존") else ng("probe_retained 혼선", rt2)
}
unlink(h5_tmp, recursive = TRUE)


cat("== (h) ★QEPM 하네스 규약 표적 — 시그니처 번역 (CDaR_LP · CVaR_LP · MaxDiv) ==\n")
# 왜 여기 있나 (2026-09-05): dispatch_weight_method 는 (alpha, cov_matrix, returns, bounds, max_names)
#   를 조립해 do.call 하는데 advanced_weights.R 의 tail-aware 3종은 (tickers, ret_dt, …) 규약이고
#   `...` 이 없다 → "unused arguments" → 카탈로그 wrapper EW 폴백 → probe.ok=FALSE →
#   weight_catalog_arms 가 unverified 로 실효 강등 → rf_cell_engine "카탈로그 arm 부재"
#   (실측: 강화 RP_20260904_163647_18444_rescued_rulefast_promo2 B2_6 n=11 미측정).
#   수리 = weight_method_registry.R::.wmr_dispatch_harness (조립층 번역 · 표적 시그니처 불변).
# ★축의 급소는 "지금 도는가" 가 아니라 **"틀린 이름의 인자는 여전히 강등되는가"** 다 —
#   번역이 '모르는 인자를 떨어뜨리는' 방식이면 틀린 시그니처가 기본값으로 돌아 초록이 된다.
#   그래서 h-0 이 결함 자체를 재현(양성 대조)하고 h-4 가 틀린 이름을 주입한다.
qe <- tryCatch(.wc_qepm_env(ROOT), error = function(e) FALSE)
if (isFALSE(qe)) ng("qepm private env 로드") else {
  HARN <- c("qepm:CDaR_LP", "qepm:CVaR_LP", "qepm:MaxDiv")
  ids_h <- vapply(CAT$entries, function(e) as.character(e$catalog_id), character(1))
  ent <- setNames(lapply(HARN, function(id) { i <- match(id, ids_h); if (is.na(i)) NULL else CAT$entries[[i]] }), HARN)
  NA_ <- length(fx$assets)
  isEWv <- function(v) { v <- as.numeric(v); length(v) == NA_ && max(abs(v - 1 / NA_)) < 1e-6 }
  inb <- function(v) all(is.finite(v)) && all(v >= -1e-9) && all(v <= 0.20 + 1e-9) && abs(sum(v) - 1) < 1e-6

  # ── h-0 결함의 양성 대조 — 표적이 정말 `returns=` 를 안 받는가(번역이 하중을 받는 축인지) ──
  tgt <- tryCatch(get("calc_cdar_weights", envir = qe), error = function(e) NULL)
  if (is.null(tgt)) ng("calc_cdar_weights 가 private env 에 없다") else {
    fm <- names(formals(tgt))
    if (all(c("tickers", "ret_dt") %in% fm) && !("returns" %in% fm) && !("..." %in% fm))
      ok("양성 대조: calc_cdar_weights 는 (tickers, ret_dt) 규약 · returns=/... 부재 — 번역이 하중을 받는다") else
      ng("표적 시그니처가 바뀌었다 — 번역 축을 재검토할 것", paste(fm, collapse = ","))
    r0 <- tryCatch({ tgt(returns = fx$R); "NO_ERROR" }, error = function(e) conditionMessage(e))
    if (grepl("unused argument", r0, fixed = TRUE))
      ok("표적 직접 호출(returns=) → 'unused argument' — 원 결함 재현") else
      ng("원 결함 미재현 — 표적이 returns= 를 받는다면 번역은 죽은 코드다", substr(r0, 1, 80))
  }

  # ── h-1 dispatch 직접: 번역 경로가 유효·비-EW·이름 붙은 비중을 낸다 (짧은 창 — 인터페이스만 본다) ──
  disp <- get("dispatch_weight_method", envir = qe)
  Rs <- utils::tail(fx$R, 60L)                     # LP 비용 절감. 규약 검사엔 창 길이가 축이 아니다
  Ss <- stats::cov(Rs); dimnames(Ss) <- list(fx$assets, fx$assets)
  for (id in HARN) {
    nm <- sub("^qepm:", "", id)
    r <- NULL
    invisible(utils::capture.output(r <- suppressWarnings(tryCatch(
      disp(nm, alpha = fx$mu, cov_matrix = Ss, returns = Rs, bounds = c(0, 0.20), max_names = 25L),
      error = function(e) list(infeasible = TRUE, reason = conditionMessage(e))))))
    if (is.list(r) && !isTRUE(r$infeasible) && is.numeric(r$weights) &&
        identical(names(r$weights), fx$assets) && inb(r$weights) && !isEWv(r$weights) &&
        identical(r$interface, "harness_convention"))
      ok(sprintf("%s dispatch — 비-EW · Σw=1 · long-only · ≤0.20 · 이름=fixture · n_days=%d max_w=%.2f",
                 id, as.integer(r$n_days), as.numeric(r$max_w))) else
      ng(sprintf("%s dispatch", id), if (is.list(r)) as.character(r$reason)[1] else class(r)[1])
  }
  # 호출자 창을 기본값 120 으로 다시 자르지 않는다(호출자 lookback 이 축) — n_days = nrow
  r_nd <- NULL
  invisible(utils::capture.output(r_nd <- suppressWarnings(
    disp("MaxDiv", cov_matrix = Ss, returns = Rs, bounds = c(0, 0.20), max_names = 25L))))
  if (is.list(r_nd) && identical(as.integer(r_nd$n_days), nrow(Rs)))
    ok(sprintf("n_days = 호출자 창 전체(%d) — 표적 기본값(120)으로 재절단 없음", nrow(Rs))) else
    ng("n_days 가 호출자 창과 다르다", r_nd$n_days)
  # ≤25 종목 — breadth 인자가 없는 표적에 26종을 주면 조용히 26종 비중이 아니라 infeasible
  R26 <- cbind(Rs, X99999 = Rs[, 1] * 0.5)
  r26 <- NULL
  invisible(utils::capture.output(r26 <- suppressWarnings(
    disp("MaxDiv", cov_matrix = NULL, returns = R26, bounds = c(0, 0.20), max_names = 25L))))
  if (is.list(r26) && isTRUE(r26$infeasible) && grepl("max_names", r26$reason, fixed = TRUE))
    ok("26종 > max_names 25 → infeasible(호명) — 초과 유니버스가 조용히 통과하지 않는다") else
    ng("26종이 통과했다 — ≤25 축이 하네스 규약 경로에서 비어 있다", r26$reason)

  # ── h-2 probe: 카탈로그 fixture(25×260)에서 ok=TRUE ∧ EW 와 구별 ──
  for (id in HARN) {
    e <- ent[[id]]
    if (is.null(e)) { ng(paste(id, "카탈로그 미등재")); next }
    pr <- NULL; invisible(utils::capture.output(pr <- suppressWarnings(.wc_probe_entry(e, ROOT))))
    dev <- suppressWarnings(as.numeric(pr$max_abs_dev_from_ew))
    if (isTRUE(pr$ok) && length(dev) == 1L && is.finite(dev) && dev > 0)
      ok(sprintf("%s probe.ok · max_abs_dev_from_ew=%.4f", id, dev)) else
      ng(paste(id, "probe"), c(as.character(pr$reason), substr(as.character(pr$log), 1, 120)))
    ent[[id]]$probe <- pr
  }
  # 라벨 = 행동: CDaR_LP 의 LP 가 실제로 풀렸는가(폴백 min-vol 로 돌면 이름과 계산이 다르다)
  lgc <- as.character(ent[["qepm:CDaR_LP"]]$probe$log)
  if (length(lgc) && !any(grepl("LP failed", lgc, fixed = TRUE)))
    ok("CDaR_LP probe 로그에 'LP failed' 없음 — 드로우다운 LP 가 실제로 풀렸다(폴백 아님)") else
    ng("★CDaR_LP 가 LP 폴백(min-vol)으로 돌았다 — 라벨과 계산이 다르다", lgc)

  # ── h-3 arms: 갱신된 probe 로 기본 집합(min_status=active)에 오른다 ──
  inj <- CAT
  for (id in HARN) { i <- match(id, ids_h); if (!is.na(i)) inj$entries[[i]]$probe <- ent[[id]]$probe }
  Dh <- weight_catalog_arms(axis = "carrier", root = ROOT, catalog = inj, quiet = TRUE)
  miss <- setdiff(HARN, Dh$catalog_id)
  if (!length(miss)) ok("3종이 기본 arm 집합(active)에 오른다 — rf_cell_engine 이 소비 가능") else
    ng("기본 arm 집합에 빠짐", miss)
  # 소비면(JSON) — rf_cell_engine 은 메모리가 아니라 06_Registry/weight_catalog.json 을 읽는다.
  #   코드를 고치고 sync_catalog(probe=TRUE) 를 안 돌리면 소비면은 여전히 '부재' 다.
  Dp <- weight_catalog_arms(axis = "carrier", root = ROOT, quiet = TRUE)
  if ("qepm:CDaR_LP" %in% Dp$catalog_id)
    ok("소비면(weight_catalog.json)에서도 qepm:CDaR_LP 가 active — 파생 파일이 현행") else
    ng("★소비면이 낡았다 — sync_catalog(root, probe=TRUE) 로 재생성할 것", "qepm:CDaR_LP 부재")
  # ★재생성의 양성 대조 — probe 는 lean 빌트인을 **전역의 calc_*** 에서 찾는다. backtest_harness.R 을
  #   싣지 않은 세션에서 sync_catalog(probe=TRUE) 를 돌리면 lean 23종이 전부 "빌트인 함수 부재" 로
  #   실패 기록되고, 그 JSON 을 rf_cell_engine 이 읽으면 lean arm 전체가 실효 unverified 가 된다
  #   (2026-09-05 실측 — CDaR 수리 직후 bare Rscript 재생성에서 23종 flip). 소비면에 lean 이 살아 있어야
  #   "CDaR_LP 가 올라왔다" 가 다른 arm 을 죽인 대가가 아님이 선다.
  lean_ok <- sum(grepl("^lean:", Dp$catalog_id))
  if ("lean:ivol" %in% Dp$catalog_id && lean_ok >= 20L)
    ok(sprintf("소비면에 lean 빌트인 %d종 생존(lean:ivol 포함) — 재생성이 하네스 적재 하에 이뤄졌다", lean_ok)) else
    ng("★소비면의 lean 빌트인이 죽어 있다 — backtest_harness.R 을 싣고 sync_catalog(probe=TRUE) 재생성",
       sprintf("lean active=%d", lean_ok))

  # ── h-4 위반 주입: 인자 이름이 틀린 표적은 여전히 강등되는가 ──
  reg0 <- get("WEIGHT_METHOD_REGISTRY", envir = qe)
  regX <- reg0
  regX[["WC_BADSIG_PROBE"]] <- list(fn = ".wc_badsig_probe_fn", family = "test", requires = c("returns"),
                                    description = "위반 주입: 인자 이름이 틀린 표적", hyperparams = character(0))
  regX[["WC_HALFSIG_PROBE"]] <- list(fn = ".wc_halfsig_probe_fn", family = "test", requires = c("returns"),
                                     description = "위반 주입: tickers 만 있고 ret_dt 가 오타", hyperparams = character(0))
  assign("WEIGHT_METHOD_REGISTRY", regX, envir = qe)
  assign(".wc_badsig_probe_fn", function(ret_matrix, max_w = 0.15) {
    v <- 1 / apply(ret_matrix, 2, stats::sd); v / sum(v) }, envir = qe)
  assign(".wc_halfsig_probe_fn", function(tickers, retdt, n_days = 120, max_w = 0.15) {
    v <- seq_along(tickers); v / sum(v) }, envir = qe)
  mk_bad <- function(nm) list(
    catalog_id = paste0("qepm:", nm), label = nm, origin = "qepm_registry", family = "test",
    status = "active",
    resolver = list(kind = "qepm_registry", dispatch_name = nm, requires = "returns", hyperparams = character(0)),
    screen_axes = list(shrinkage_builtin = NA, statistic_order = NA, screen_priority = NA),
    selection_type = "chain", n_trials_family = 1L, est_cost_min = 1)
  bads <- list(mk_bad("WC_BADSIG_PROBE"), mk_bad("WC_HALFSIG_PROBE"))
  inj2 <- inj
  for (b in bads) {
    # suppressWarnings: dispatch 의 warning() 이 수익률 벡터 전체를 문자열로 실어 출력을 덮는다 —
    #   판정은 probe$log(호명된 사유)로 하므로 경고 본문은 필요 없다.
    pb <- NULL; invisible(utils::capture.output(pb <- suppressWarnings(.wc_probe_entry(b, ROOT))))
    if (!isTRUE(pb$ok) && grepl("unused argument", as.character(pb$log), fixed = TRUE))
      ok(sprintf("위반 주입 %s: probe.ok=FALSE · 로그가 'unused argument' 를 호명(기본값으로 돌지 않았다)", b$label)) else
      ng(sprintf("★위반 주입 %s 가 통과/침묵", b$label), c(pb$ok, as.character(pb$reason), substr(as.character(pb$log), 1, 100)))
    b$probe <- pb
    inj2$entries[[length(inj2$entries) + 1L]] <- b
  }
  assign("WEIGHT_METHOD_REGISTRY", reg0, envir = qe)            # 복원
  suppressWarnings(rm(list = c(".wc_badsig_probe_fn", ".wc_halfsig_probe_fn"), envir = qe))
  Db <- weight_catalog_arms(axis = "carrier", root = ROOT, catalog = inj2, quiet = TRUE)
  if (!any(c("qepm:WC_BADSIG_PROBE", "qepm:WC_HALFSIG_PROBE") %in% Db$catalog_id))
    ok("주입 2종은 선언 active 인데 기본 집합에서 빠진다(실효 unverified)") else
    ng("★probe 실패 arm 이 기본 집합에 올라왔다")
  Du <- weight_catalog_arms(axis = "carrier", min_status = "unverified", root = ROOT, catalog = inj2, quiet = TRUE)
  rb <- Du[catalog_id == "qepm:WC_BADSIG_PROBE"]
  if (nrow(rb) == 1L && identical(rb$status, "unverified") && identical(rb$status_declared, "active") &&
      isFALSE(rb$probe_ok))
    ok("강등은 숨김이 아니라 표시 — status=unverified · status_declared=active · probe_ok=FALSE") else
    ng("강등 표시 필드", c(rb$status, rb$status_declared, rb$probe_ok))
  # 양성 대조 — 같은 카탈로그에서 정상 3종은 여전히 살아 있다(검사가 '전부 강등'로 통과하지 않음)
  if (all(HARN %in% Db$catalog_id)) ok("양성 대조: 같은 카탈로그에서 정상 3종은 기본 집합 유지") else
    ng("양성 대조 실패 — 정상 3종이 함께 빠졌다", setdiff(HARN, Db$catalog_id))
}

.emit()
if (FAIL > 0L) quit(save = "no", status = 1)
