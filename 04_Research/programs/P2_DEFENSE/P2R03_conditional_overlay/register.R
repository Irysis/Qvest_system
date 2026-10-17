## P2R03 조건부 · 시변 노출 층 — 엔진 자체 구성(E2 EW · E3 엔트로피 비중) 위에 조건부 노출 층 6종을 얹으면, 같은 β 의 정적 현금 사본보다
##   깊은 위기 · 빠른 급락에서 덜 빠지고(헌장 빈칸 6 · 8) 하락장 β < 상승장 β 이며(빈칸 3) 강세 구간 과반에서 엔진의 80% 이상을 따라가고(빈칸 7)
##   엔진 알파를 잃지 않는가(빈칸 4C)
##   설계 = DESIGN.md v3 · Q 자율 판단(J-20261017-007 라운드 선택 · J-009 후보 · J-010 설계) · 판단 Superfan T1(R-20261017-005) · 철학 Superfan P1 ·
##   전액 현금 결함 수리(b234afb11 — P0R01 · P2R02 추세 현금 · 낙폭 브레이크 판정 무효 → 재시험)
## 실행:
##   Rscript register.R --draft      초안(검사 3종을 실제로 돌려 통과 수를 싣는다 · 리허설 요약이 통과 ∧ 현 evaluate.R 판이어야 한다 · 실패면 초안을 쓰지 않는다)
##   Rscript register.R --register   등록 — 검토판 보존 · 사양 · 운영 · 평가 경로 md5 · 패키지 · R 판 · 리허설 · 커밋 상태(고정 대상 전부)를 확인한 뒤에만
##   ★R2: 이 라운드의 측정 결과(results/P2R03_*.json)가 하나라도 있으면 사전등록을 바꾸지 않는다.
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
args <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--register" %in% args) "register" else if ("--draft" %in% args) "draft" else stop("usage: register.R --draft | --register")
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R03_conditional_overlay"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
source(file.path(RD, "round_rules.R"))
source(file.path(RD, "evaluate.R"))                                             # 장치 표(P2R03_DEVICES)만 — 본 실행 블록은 sys.nframe 가드
PR <- file.path(P$prereg_dir, "prereg.json"); DR <- file.path(RD, "prereg_draft.json")
## 격리 교차 점검을 받은 초안 보존본(있으면 등록판에 연결 — 없으면 --register 거부)
REVIEWED <- Filter(function(z) file.exists(z$path), list(
  list(version = 1L, path = file.path(RD, "prereg_draft_reviewed_v1.json"), review = "격리 교차 점검(결과 미열람 · 범용 에이전트)"),
  list(version = 2L, path = file.path(RD, "prereg_draft_reviewed_v2.json"), review = "격리 변경분 점검(v1 → v2 · 결과 미열람)"),
  list(version = 3L, path = file.path(RD, "prereg_draft_reviewed_v3.json"), review = "격리 변경분 점검(v2 → v3 · 좁은 범위)")))
rel <- function(p) sub(paste0("^", ROOT, "/"), "", p)
.measured_any <- function() length(Sys.glob(file.path(RD, "results", "P2R03_*.json"))) > 0L
if (.measured_any()) stop("[P2R03] 측정 결과가 생긴 뒤에는 사전등록을 바꿀 수 없다(R2)")
if (file.exists(PR)) stop("[P2R03] 사전등록이 이미 있다(R2) — 대체는 측정 전 · 별도 절차로만")

DEV <- P2R03_DEVICES
BASIS <- list(
  D1 = "Ang, Chen & Xing (2006) Downside Risk, RFS 19(4) — 하방베타 · 카탈로그 arm dbeta_tilt_rank 정의(낙폭 국면 × 하방베타 순위 축소)",
  D2 = "Ang, Hodrick, Xing & Zhang (2006) The Cross-Section of Volatility and Expected Returns, JF 61(1) — 특이변동 · arm csd_idio_tilt 정의(횡단면분산 국면 × 특이변동 순위 축소)",
  D3 = "거리 형식 = Kritzman & Li (2010) Skulls, Financial Turbulence, and Risk Management, FAJ 66(5) — 원문(자산 수익 벡터 거리) 구현 아님: 벤치 상태 벡터(rv60 · 횡단면분산 · 낙폭)의 확장창 마할라노비스 거리 게이트(T1 C-20261017-037)",
  D4 = "착상 = Christoffersen & Diebold (2006) Financial Asset Returns, Direction-of-Change Forecasting, and Volatility Dynamics, Management Science 52(8)(변동성 동학을 통한 방향 예측) — 원문 구현 아님: 이 arm(ml_tail_gate)은 확장창 로지스틱 꼬리 확률 게이트(노출 = 1 − p̂)",
  D5 = "착상 = Moskowitz, Ooi & Pedersen (2012) Time Series Momentum, JFE 104(2)(자산별 롱숏 · 변동성 조정 TSMOM) · Faber (2007) A Quantitative Approach to Tactical Asset Allocation, JWM 9(4)(10개월 이동평균) — 원문 구현 아님: 이 arm(ts_mom_sign)은 시장 12개월 부호 현금 게이트(재시험: P0R01 C1 측정은 전액 현금 결함 위)",
  D6 = "착상 = Grossman & Zhou (1993) Optimal Investment Strategies for Controlling Drawdowns, Mathematical Finance 3(3)(누적 최고 대비 쿠션 비례 규칙) — 원문 구현 아님: 이 arm(dd_brake_q)은 확장창 분위 램프(재시험: P0R01 C3 측정은 전액 현금 결함 위)",
  D7 = "맥락 = Daniel & Moskowitz (2016) Momentum Crashes, JFE 122(2)(약세장 · 고변동 뒤 반등이 급하다) — 원문 구현 아님: 이 arm(dd_recovery)은 낙폭이 확장창 중앙 위인 국면에서 직전 1개월 벤치가 오르면 노출 유지 · 아니면 현금(재진입 규칙 · 철학 P1 C-20261017-045 · 수리 판 첫 유효 측정)")
OPS <- c("02_Infrastructure/reinforcement/rf_cell_engine.R", "02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_axes.R",
         "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/reinforcement/rf_sleeve.R", "02_Infrastructure/ops/rf_cell_worker.R",
         "02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.R", "02_Infrastructure/reinforcement/overlay_arms/dbeta_tilt.arm.json",
         "02_Infrastructure/reinforcement/overlay_arms/gen_20260903_133452.R", "02_Infrastructure/reinforcement/overlay_arms/gen_20260903_133452.arm.json",
         "02_Infrastructure/validation/overlay_pit_guard.R",
         "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/methods/method_registry.R", "02_Infrastructure/portfolio/strategy_tilt_weights.R",
         "02_Infrastructure/portfolio/advanced_weights.R",
         "02_Infrastructure/alpha_search/run_paper_replication.R", "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/backtest_harness.R",
         "02_Infrastructure/config.R", "02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/behavior_card.R",
         "02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/matched_controls.R", "02_Infrastructure/contracts/grade_v3.R",
         "02_Infrastructure/contracts/tilt_attribution.R", "02_Infrastructure/contracts/beta_controlled_alpha.R", "06_Registry/matched_controls.json",
         "02_Infrastructure/worktask/constraint_defaults.json", "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
         "02_Infrastructure/factor_db/factor_db_connector.R", "04_Research/programs/_lib/round_kit.R", "04_Research/programs/_lib/measure_round_cell.R",
         "04_Research/programs/_lib/eval_parallel.sh", "02_Infrastructure/ops/refresh_barrier.sh",
         "02_Infrastructure/contracts/backtest_result_contract.R", "02_Infrastructure/contracts/save_bt_result.R", "02_Infrastructure/contracts/essence_score.R",
         "02_Infrastructure/contracts/tilt_attribution_config.json", "02_Infrastructure/contracts/rolling_grade.R", "06_Registry/rolling_grade.json",
         "02_Infrastructure/factor_db/factor_z_standard.R", "06_Registry/grade_v3.json")
EVALF <- c("evaluate.R", "evaluate_fixture.R", "precheck.R", "measure.sh", "fingerprint.sh", "round_rules.R")
PIN_CATS <- "lean:entropy"                                                       # E3 RX0 비중(엔진 정의)
.ops_pins <- function() {
  wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
  ents <- lapply(PIN_CATS, function(cid) { e <- Filter(function(z) identical(z$catalog_id, cid), wc)
    if (!length(e)) stop("[P2R03] 비중 카탈로그 엔트리 없음: ", cid); list(catalog_id = cid, status = e[[1]]$status, resolver = e[[1]]$resolver) })
  oc <- fromJSON(file.path(ROOT, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE)$arms
  arms <- lapply(DEV, function(d) { e <- Filter(function(z) identical(z$id, d$arm_id), oc)
    if (!length(e)) stop("[P2R03] 오버레이 카탈로그 arm 없음: ", d$arm_id)
    if (!identical(e[[1]]$kind, d$kind) || !identical(e[[1]]$status, "active")) stop("[P2R03] arm kind · status 불일치: ", d$arm_id)
    list(id = d$arm_id, entry = e[[1]]) })
  list(files = lapply(OPS, function(f) list(path = f, md5 = rk_md5(file.path(ROOT, f)))), catalog_entries = ents, overlay_arms = unname(arms),
       packages = list(bbdetection = as.character(utils::packageVersion("bbdetection")), PerformanceAnalytics = as.character(utils::packageVersion("PerformanceAnalytics")),
                       data.table = as.character(utils::packageVersion("data.table"))),
       r_version = R.version.string)
}
.eval_pins <- function() lapply(EVALF, function(f) { p <- file.path(RD, f); list(path = rel(p), md5 = rk_md5(p)) })
REH <- file.path(RD, "rehearsal", "summary.json")
.rehearsal <- function() {
  if (!file.exists(REH)) stop("[P2R03] 리허설 요약이 없다 — Rscript rehearse.R 먼저")
  s <- fromJSON(REH, simplifyVector = FALSE)
  if (!isTRUE(s$pass)) stop("[P2R03] 리허설 실패 — 등록하지 않는다")
  if (!identical(s$evaluate_md5, rk_md5(file.path(RD, "evaluate.R")))) stop("[P2R03] 리허설 뒤 evaluate.R 이 바뀌었다 — 다시 리허설")
  list(script = list(path = rel(file.path(RD, "rehearse.R")), md5 = rk_md5(file.path(RD, "rehearse.R"))), summary = list(path = rel(REH), md5 = rk_md5(REH)),
       evaluate_md5 = s$evaluate_md5, pass = TRUE, inputs = s$inputs, seconds = s$seconds)
}
## 철학 Superfan P1 수령 확인(10-17 · 등록 전 기계 확인) — 판단 원장에 이 라운드의 P1 리뷰(role philosophy · trigger P1 · round = ROUND)가 있고,
##   그 리뷰의 도전 · 정지 항목이 모두 Q 응답을 받았으며(status ≠ open) 열린 보류 요청이 없어야 한다. 거부권이 아니라 '건너뛸 수 없음'이다
##   (응답은 수용 · 반박 모두 가능 · 규약 superfan_protocol §11 '의견을 반영해 등록한다').
.p1_check <- function() {
  L <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/q_judgment_ledger.json"), simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(L)) return(list(ok = FALSE, why = "판단 원장 판독 실패"))
  rv <- Filter(function(r) identical(r$role, "philosophy") && identical(r$trigger, "P1") && identical(r$round, ROUND), L$reviews %||% list())
  if (!length(rv)) return(list(ok = FALSE, why = sprintf("이 라운드(%s)의 철학 P1 리뷰가 원장에 없다", ROUND)))
  ids <- unique(unlist(lapply(rv, function(r) unlist(r$challenges))))
  ch <- Filter(function(c) c$id %in% ids && (c$grade %||% "") %in% c("challenge", "stop"), L$challenges %||% list())
  open <- vapply(Filter(function(c) identical(c$status, "open") || !length(c$responses), ch), function(c) c$id, character(1))
  hold <- vapply(Filter(function(c) isTRUE(c$hold_request) && !(c$status %in% c("accepted", "withdrawn", "escalated", "settled")), ch), function(c) c$id, character(1))
  if (length(open)) return(list(ok = FALSE, why = paste("응답 없는 도전:", paste(open, collapse = ","))))
  if (length(hold)) return(list(ok = FALSE, why = paste("열린 보류 요청:", paste(hold, collapse = ","))))
  list(ok = TRUE, reviews = vapply(rv, function(r) r$id, character(1)), files = vapply(rv, function(r) r$file %||% NA_character_, character(1)),
       n_challenges = length(ch), statuses = setNames(vapply(ch, function(c) c$status %||% NA_character_, character(1)), vapply(ch, function(c) c$id, character(1))))
}
TESTF <- c("08_Tests/reinforcement/test_rf_overlay_full_cash.R", rel(file.path(RD, "evaluate_fixture.R")), "08_Tests/programs/test_round_kit_pair_alpha.R")
## 커밋 확인 대상 — 카탈로그 두 파일(weight_catalog · overlay_catalog)은 빼고 쓰이는 엔트리를 내용으로 핀한다(operational_pins) — 무인 작업
##   (Qvest_WeightCatalogGrow 등)이 다른 엔트리를 쓰면 파일 전체가 '미커밋'이 되어 등록을 막지만 판정에 닿는 것은 그 엔트리뿐이다
COMMIT_PATHS <- unique(c(TESTF, "08_Tests/reinforcement/test_rf_engine_overlay_stack.R", rel(RD), OPS))
.uncommitted <- function() { s <- system2("git", c("-C", ROOT, "status", "--porcelain", "--", COMMIT_PATHS), stdout = TRUE)
  s <- s[nzchar(s)]; s[!grepl("prereg_draft|results/|rehearsal/out", s)] }
.run_test <- function(path) {
  o <- suppressWarnings(system2("Rscript", c("--no-environ", shQuote(path)), stdout = TRUE, stderr = TRUE))   # QM_ROOT = 위 Sys.setenv 상속(Windows 에서 system2(env=) 는 Rscript 에 안 먹는다)
  j <- grep('^\\{"test"', o, value = TRUE)
  if (length(j)) { r <- fromJSON(j[length(j)]); return(list(path = rel(path), md5 = rk_md5(path), pass = r$pass, fail = r$fail)) }
  list(path = rel(path), md5 = rk_md5(path), pass = NA, fail = NA)
}

if (MODE == "register") {
  if (!file.exists(DR)) stop("[P2R03] 초안이 없다 — --draft 먼저")
  if (!length(REVIEWED)) stop("[P2R03] 격리 교차 점검 보존본이 없다 — 점검 뒤 등록")
  pre <- fromJSON(DR, simplifyVector = FALSE)
  if (!length(pre$changes_after_review)) stop("[P2R03] 교차 점검 반영 기록(changes_after_review)이 비었다")
  for (c in pre$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P2R03] 사양 md5 ≠ 초안: ", c$code)
  now <- .ops_pins()
  for (f in pre$operational_pins$files) {
    m <- Filter(function(z) identical(z$path, f$path), now$files)[[1]]$md5
    if (!identical(m, f$md5)) stop("[P2R03] 운영 경로 md5 ≠ 초안(초안 뒤 구현이 바뀌었다): ", f$path)
  }
  if (!identical(now$packages, pre$operational_pins$packages) || !identical(now$r_version, pre$operational_pins$r_version)) stop("[P2R03] 패키지 · R 판 ≠ 초안")
  cj <- function(x) as.character(toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
  if (!identical(cj(now$catalog_entries), cj(pre$operational_pins$catalog_entries))) stop("[P2R03] 비중 카탈로그 엔트리 ≠ 초안")
  if (!identical(cj(now$overlay_arms), cj(pre$operational_pins$overlay_arms))) stop("[P2R03] 오버레이 카탈로그 arm ≠ 초안")
  for (f in pre$evaluation$files) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P2R03] 평가 경로 md5 ≠ 초안: ", f$path)
  for (t in pre$tests) if (!identical(rk_md5(file.path(ROOT, t$path)), t$md5) || !identical(as.integer(t$fail), 0L)) stop("[P2R03] 검사 파일 변경 또는 실패: ", t$path)
  rh <- .rehearsal()
  if (!identical(rh$evaluate_md5, pre$rehearsal$evaluate_md5) || !identical(rh$summary$md5, pre$rehearsal$summary$md5) ||
      !identical(rh$script$md5, pre$rehearsal$script$md5)) stop("[P2R03] 리허설 기록(evaluate · 요약 · 리허설 스크립트 md5) ≠ 초안")
  if (!identical(rk_md5(file.path(ROOT, pre$behavior_card_cfg$path)), pre$behavior_card_cfg$md5)) stop("[P2R03] 행동 카드 설정 사본 md5 ≠ 초안")
  p1 <- .p1_check()                                                              # 철학 P1 수령 · 도전 응답 — 건너뛸 수 없게(도훈 10-17 '철학 Superfan 역할이 검토에서 끝이냐')
  if (!isTRUE(p1$ok)) stop("[P2R03] 철학 Superfan P1 조건 미충족 — 등록하지 않는다: ", p1$why)
  unc <- .uncommitted()
  if (length(unc)) stop("[P2R03] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n"))
  pre$status <- "registered"; pre$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); pre$draft_md5 <- rk_md5(DR)
  pre$reviewed_drafts <- lapply(REVIEWED, function(rv) list(version = rv$version, path = rel(rv$path), md5 = rk_md5(rv$path), review = rv$review))
  pre$git_head_at_register <- tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_)
  dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
  file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                n_variants = length(Filter(function(z) !isTRUE(z$reference) && !isTRUE(z$diagnostic), pre$cells)),
                                variants = unname(vapply(pre$cells, function(z) z$code, character(1)))), root = ROOT)
  cat(sprintf("[P2R03] 사전등록 %s (md5 %s) · 칸 %d · HEAD %s\n", PR, rk_md5(PR), length(pre$cells), pre$git_head_at_register))
  quit(status = 0)
}

## ── 초안 ─────────────────────────────────────────────────────────────────────
TESTS <- lapply(file.path(ROOT, TESTF), .run_test)
for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P2R03] 검사 실패 — 초안을 쓰지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")
EP <- ma_epoch(root = ROOT)
P0SP <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs")
.spec_root <- function(path) tryCatch(fromJSON(file.path(ROOT, path), simplifyVector = FALSE)$selection_accounting$family_root %||% NA_character_,
                                      error = function(e) NA_character_)
## 시행 회계 — 계보(family_root)마다 앞선 모든 사전등록 칸의 n_family 최댓값 + 이 라운드 장치 칸 수(RX0 · lag-1 진단 무가산 · P3R03 v2 규칙)
nf_prior <- function(root_id) {
  v <- unlist(lapply(Sys.glob(file.path(ROOT, "stage_artifacts/programs/*/*/prereg.json")), function(p) {
    d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    vapply(Filter(function(z) is.numeric(z$n_family) && !is.null(z$path) && identical(.spec_root(z$path), root_id), d$cells %||% list()),
           function(z) as.integer(z$n_family), integer(1))
  }))
  if (length(v)) max(v) else 0L
}
ENGINES <- list(E2 = list(ref = "P0R01_E2_C0", base_weighting = "EW(동일 비중 · 25종)"),
                E3 = list(ref = "P0R01_E3_C0", base_weighting = "lean:entropy(엔진 자체 엔트로피 비중 · 순위 버퍼 2배 · B6_36 정의)"))
for (e in names(ENGINES)) {
  ENGINES[[e]]$family_root <- .spec_root(file.path("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs", paste0(ENGINES[[e]]$ref, ".json")))
  if (is.na(ENGINES[[e]]$family_root)) stop("[P2R03] 기준 사양 계보(family_root) 판독 실패: ", ENGINES[[e]]$ref)
  ENGINES[[e]]$n_prior <- nf_prior(ENGINES[[e]]$family_root)
}
N_ROUND <- length(ENGINES) * length(DEV)
cells <- list(); bad <- character(0)
for (eid in names(ENGINES)) {
  e <- ENGINES[[eid]]
  b <- fromJSON(file.path(P0SP, paste0(e$ref, ".json")), simplifyVector = FALSE)
  nf <- as.integer(e$n_prior + N_ROUND)
  SA <- list(selection_type = "sweep", family_root = b$selection_accounting$family_root,
             lineage = c(paste0("RX_", ROUND), unlist(b$selection_accounting$lineage)), n_family_at_registration = nf,
             n_trials_basis = sprintf("P2R03: 앞선 사전등록 칸 중 계보 %s(E2 · E3 공통) 회계 최댓값 %d + 이 라운드 장치 칸 %d(엔진 %d × 장치 %d) · RX0 · lag-1 진단 무가산",
                                      e$family_root, as.integer(e$n_prior), N_ROUND, length(ENGINES), length(DEV)))
  for (k in names(DEV)) {
    d <- list(overlay = list(kind = DEV[[k]]$kind, arm_id = DEV[[k]]$arm_id))
    v <- rx_validate(d, ROOT); if (!isTRUE(v$ok)) { bad <- c(bad, sprintf("%s %s: %s", eid, k, paste(v$errors, collapse = " | "))); next }
    for (lag in c(FALSE, TRUE)) {
      code <- sprintf("P2R03_%s_%s", eid, if (lag) sub("^D", "L", k) else k)
      SAc <- if (lag) c(b$selection_accounting, list(stress_of = sprintf("P2R03_%s_%s", eid, k), n_trials_note = "lag-1 스트레스판(pit.md C5 의무 2) — 시행 수 무가산 · DSR 표본 아님(진단)")) else SA
      sp <- rx_compile_spec(b, d, code = code,
                            label = sprintf("%s × %s%s", eid, DEV[[k]]$name, if (lag) " — lag-1 스트레스판(노출 한 달 지연 · 진단)" else ""),
                            idea = sprintf("[P2R03 조건부 시변 노출 층 · %s × %s%s] %s", eid, k, if (lag) " · lag-1" else "", BASIS[[k]]),
                            selection_accounting = SAc, epoch = EP, root = ROOT)
      if (lag) sp$overlay_shift <- 1L
      f <- file.path(P$specs_dir, paste0(code, ".json")); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
      writeLines(toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
      cells[[code]] <- list(code = code, engine = eid, component = if (lag) paste0("L_", k) else k, path = rel(f), md5 = rk_md5(f),
                            n_family = if (lag) NA else nf, reference = FALSE, diagnostic = lag, lag = lag)
    }
  }
  code0 <- sprintf("P2R03_%s_RX0", eid)
  SA0 <- c(b$selection_accounting, list(remeasure_of = e$ref, n_trials_note = "같은 판본 기준 재측정 — 시행 수 무가산(research-program SKILL §2)"))
  sp0 <- rx_compile_spec(b, list(), code = code0, label = sprintf("%s × 기준 재측정(%s · %s 사양 그대로)", eid, e$base_weighting, e$ref),
                         idea = sprintf("[P2R03 RX0 · %s] 같은 배치 기준 재측정 — %s 사양 그대로 · 반증 · 비열등 · β 짝 원천 · 시행 수 무가산 · 카탈로그 미등재", eid, e$ref),
                         selection_accounting = SA0, epoch = EP, root = ROOT)
  f0 <- file.path(P$specs_dir, paste0(code0, ".json"))
  writeLines(toJSON(sp0, auto_unbox = TRUE, pretty = TRUE, null = "null"), f0, useBytes = TRUE)
  cells[[code0]] <- list(code = code0, engine = eid, component = "RX0", path = rel(f0), md5 = rk_md5(f0), n_family = NA, reference = TRUE, diagnostic = FALSE,
                         lag = FALSE, remeasure_of = e$ref)
}
if (length(bad)) stop("[P2R03] 검증 실패:\n", paste(bad, collapse = "\n"))
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json")
if (!file.exists(BCP)) file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = FALSE)   # 리허설이 먼저 만들었으면 그 사본(같은 원본)
FS <- p2r03_final_selection_rule(ROOT, BCP)
ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, status = "draft", draft_version = 1L,
  drafted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  judgments = list(round_selection = "J-20261017-007", candidates = "J-20261017-009", design = "J-20261017-010", triage = "J-20261017-008",
                   ledger = "06_Registry/q_judgment_ledger.json",
                   superfan_t1 = "R-20261017-005(04_Research/programs/_supervision/superfan/20261017_1854_T1.md · C-033~C-043)",
                   superfan_philosophy_p1 = "R-20261017-006(04_Research/programs/_supervision/superfan/philosophy/20261017_1931_P1_P2R03.md · C-044~C-054 · 설계 v2 기준)"),
  exposures = list(
    list(what = "1차 라운드(P0R01 · P1R01 · P2R02 · P3R01 · P3R02) · P3R03 종료 보고 — 보는 창 · 시험 창 지표 · 시각 보고", when = "2026-10-15 ~ 10-17", who = "Q(세션)"),
    list(what = "DIST-GEN-155 · 027(구 축 강화 격자 · 시험 창 포함 전기간 PORT_t) — 후보 범위 참고만(일부는 전액 현금 결함 위 측정일 수 있다)", when = "2026-10-17", who = "Q"),
    list(what = "전액 현금 결함 진단 — P0R01 C1 · C3 · C6 셀 로그의 노출 줄 · 보유 월 수 · 0 노출 달 일수익의 0 여부(부호 · 크기 판독 없음)", when = "2026-10-17", who = "Q"),
    list(what = "빠른 급락 정의에 드는 보는 창 위기를 벤치로 계산(전략 성과 무관) — 정의는 문헌이 정했고 결과로 고치지 않는다", when = "2026-10-17", who = "Q"),
    list(what = "철학 Superfan P2(R-20261017-004)는 P3R03_E3_HRP eval.json 시험 창 · 전기간 블록을, 판단 Superfan T1(R-20261017-005)은 등록부 P2R01 블록의 전기간 등급 · S · 시험 창 꼬리표를 열람 — 근거로 쓰지 않음(각 리뷰 파일 머리 선언)", when = "2026-10-17", who = "Superfan"),
    list(what = "철학 Superfan P1(R-20261017-006)은 results/<칸>/eval.json · full/ · authoritative_remeasure.json · 시험 창 차트를 열지 않았고 DIST-GEN 본문 · 커밋 문구의 전기간 수치는 봤으나 근거로 쓰지 않음(리뷰 파일 선언) · 근거로 쓴 β 수치 = P3R03 RX0 보는 창 패킷(구 판본)", when = "2026-10-17", who = "Superfan"),
    list(assessment = paste0("Q 는 시험 창 수치를 본 상태다(τ_D 노출). 선택 · 판정 규칙은 보는 창(≤ 2022-12-31) 지표로만 쓰고 시험 창은 사람 쪽 보고 전용이다. ",
                             "장치 6종은 원리(조건부 · 횡단면 · 다변량 상태 · 분포 표적 · 추세 · 낙폭)와 P2R02 기록 · 전액 현금 결함 발견으로 골랐고, 시험 창 성과로 고르지 않았다."))),
  purpose = paste0("엔진 자체 구성 위 조건부 시변 노출 층이 같은 β 정적 현금 사본보다 깊은 위기 · 빠른 급락에서 덜 빠지는가(헌장 빈칸 6 · 8) — ",
                   "하락장 β < 상승장 β · 강세 구간 과반 80% 이상 참여 · 엔진 알파 비열등 · S · 복리 경로 비악화를 지키면서. 등록부 P2_DEFENSE · 병목 = 급락기 낙폭(엔진 = 시장 동행)"),
  conclusion_scope = c(   # 철학 P1 C-20261017-046 여섯 줄(+ 기록 정정 1줄)
    "1 이번 결론은 엔진 자체 구성 위 조건부 시변 노출 층의 효과다. 이 arm 들(카탈로그 정식화 · 문헌 원문 구현 아님) · 상태 = 시장 실현 스트레스 4축(rv60 · 낙폭 · r252 · 신호일 횡단면 분산) · 월간 결정 · 보유월 시작 전 신호 · 이 축 · 이 엔진 둘에 한한다. 검증 0 이면 결론은 이 상태 계열 · 이 결정 주기에 대한 것이지 시변 층 일반이 아니다(장치 7종은 같은 상태 축을 공유한다 — 독립 시험 7개가 아니다).",
    "2 '방어'는 ③ β 짝 ∧ ⑤ 수준(하락 β < 상승 β · 칸)일 때만 쓴다. ④ 를 못 넘으면 '느린 약세 · 여진 방어'다. 장치 검증의 ⑤ 는 비대칭 변화량(하락/상승 β 비가 RX0 보다 낮아짐)이다.",
    "3 ③ · ④ · ⑤ 를 넘었으나 ⑥ · ⑦ · ⑨ · ⑫ · ⑬ 중 하나라도 못 넘으면 '방어만 · 복리 없음(현금 기계)'으로 적는다(헌장 §5).",
    "4 엔진 강점은 엔진 자체 구성 대비 구간별 상승 포착 · 증분 알파 · 사이클 복리 · S 로 적는다.",
    "5 귀속: MC8 라벨에 β 짝 결과와 size_exposure_path(시변 노출 경로 짝 · 진단) 결과를 병기해 '시변 노출(타이밍) 방어'와 '선택 방어'를 가른다. D1 · D2 는 '시변 + 보유 안 기울기 혼합'으로 적는다. 타이밍을 '선택 방어'로 쓰지 않는다.",
    "6 한 엔진만 통과 = '단일 엔진 · 미확증'(후보 아님). lag-1 에서 ③ · ④ 가 무너진 칸 = '지연 민감'을 결론 · 보고 1줄 · P4 후보 묶음 · P3 의견서에 싣는다. 느린 약세 개선까지 lag-1 에서 무너지면 누출 조사 · 최종 선택 보류.",
    "7 D5 · D6 · D7 결론은 P0R01 · P2R02 의 추세 현금 · 낙폭 브레이크 판정을 대체한다(그 판정은 전액 현금 결함 b234afb11 위). D3 은 Kritzman-Li 원문 난기류가 아니라 벤치 상태 벡터 거리 게이트다. 결론은 arm 에 대한 것이지 논문에 대한 것이 아니다('TSMOM 실패' 같은 문장 금지)."),
  candidates = list(
    selected = lapply(names(DEV), function(k) list(code = k, arm_id = DEV[[k]]$arm_id, kind = DEV[[k]]$kind, name = DEV[[k]]$name, basis = BASIS[[k]])),
    excluded = list(
      list(item = "변동성 타기팅(vol_median · vol_ewma · vol_har)", reason = "유효한 시험이 있다 — P0R01 C2(vol_scale · 노출 0 달 0/322 · 결함 무관)가 P2R02 에서 노출 짝 대조 미통과"),
      list(item = "저변동 · 퀄리티 틸트(P2R02 C4 · C5) · C6 의 저변동 성분", reason = "질문이 다르다 — 선택을 바꾸는 방어적 보유(비대칭 원천 ③) · 같은 선정 집합 대조가 깨진다 · C6 추세 성분은 D5 로 재시험 · 방어적 보유 × β 짝은 다음 라운드 후보(T1 C-033)"),
      list(item = "vol_x_dd · vol_x_turb", reason = "원리 중복(낙폭 대표 D6 · 상태 거리 대표 D3) · 시행 수 예산"),
      list(item = "vol_median 진단 칸(철학 P1 C-049 선택 사항)", reason = "불채택 — 이번 대조 읽기(D3 vs D6 · D4 vs D3)로 상태 계열 지도를 남기고, 단순 변동성 위 증분은 다음 라운드 후보(P2R02 C2 는 이 라운드의 β 짝 판정으로는 미시험)"),
      list(item = "book_convexity_brake · book_risk_* · book_stress_vouch", reason = "질문이 다르다 — 확장창 누적 추정 · 국면 급변에 거의 반응하지 않음(arm 자기 서술) · 정적 β 축소와 같은 형태"),
      list(item = "나머지 ML arm(ml_dual_forecast_tilt 외 8종) · multivar_* · xs_*", reason = "시행 수 예산 · 원리 중복(같은 상태 4축 — 대표 D4 · D3 · D2)"),
      list(item = "HRP 기저(v1 설계)", reason = "T1 C-034 — 헌장 '같은 엔진 기준' = 엔진 자체 구성 · HRP 강세 손실이 기준에 묻힘 · P3R03 HRP 통과 = 노출(β) 방어(β 짝 10/10 미통과)")),
    p2r02_tags = list(   # 철학 P1 C-050 — P4 후보 목록 표기(지금 적는다)
      list(item = "P2R02 C6(추세 현금 + 저변동) '검증'", tag = "무효 — 전액 현금 결함(b234afb11) 위 측정: 0 노출 95~102개월이 직전 보유 이월로 측정돼 추세 성분이 전달되지 않았다"),
      list(item = "P2R02 C4(저변동 틸트) '검증'", tag = "빈칸 8 미적용 — β 짝 판정(2026-10-17 헌장) 이전 판정이라 노출(β) 방어 여부 미확인"),
      list(item = "P2R02 C1(추세 현금) · C3(낙폭 브레이크) '기각'", tag = "무효 — 같은 결함 위 측정(C1 0 노출 달 전부 · C3 가장 깊은 낙폭 2개월) · 이 라운드 D5 · D6 이 대체"))),
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference = list(baseline = "같은 엔진 RX0(이 배치에서 P0R01_E?_C0 사양 그대로 재측정) — 반증 · 비열등 · β 짝 원천 · 시행 수 무가산 · 카탈로그 미등재(QVEST_RP_REGISTER=0)",
                   e3_note = "E3(B6_36) 의 RX0 비중 = lean:entropy(엔진 정의) · 순위 버퍼 2배 — 층은 그 위에 노출만 곱한다(선택 · 비중법 그대로)"),
  variants = lapply(DEV, function(v) list(name = v$name, delta = list(overlay = list(kind = v$kind, arm_id = v$arm_id)))),
  adaptations = list(
    "층 = 월간 노출 곱(Σw ≤ 1 · 잔여 현금 · MC5) — 신호는 보유월 시작 전 데이터(엔진 assert_overlay_pit · P0-09 가용일 마스크)",
    "노출 0 달 = 표현 하한(1e-9 × 원 비중)으로 현금 집행(b234afb11 · 셀 로그 '현금 집행(표현 하한) k신호일') — 수리 전 판은 그 달을 직전 보유 이월로 측정했다",
    "lag-1 판 = 같은 사양 + overlay_shift 1(노출 경로 한 달 지연 · 앞선 달 없는 첫 달 1)",
    "표본 축소(엔진 정의): e = 1 − w(1 − e_raw) · w = min(1, t / n_min) · n_min = turbulence 36 · ml_tail_gate 48 · 그 밖 24"),
  cells = unname(cells),
  fast_crash_prior = list(
    source = "벤치만 · 2000-01 ~ 2022-12 · LT 20/20 · 21거래일 창 최대 하락 · 그 빠른 구간 · 구간 직전 월말(그 달 노출을 정한 신호일) · 위기 안 여부 · 그 월말 뒤 남은 하락 · 달력 월 판(월말→월말) — 전략 성과 무관",
    definition = paste0("Mishkin & White (2002) NBER WP 8992 — 정의 p.6 · 창별 결과 p.6~7(20% 하락 = 급락 · 속도 창 1일 · 5일 · 1개월 · 3개월 · 1년). 창 선택 = 1개월: 결정 주기가 월간이고 신호는 보유월 시작 전 자료뿐이라 ",
                        "'빠름' = 한 결정 주기 안에 끝나는 하락 = 월간 층이 사후 대응할 수 없는 하락(철학 §1 '남들 다 깨질 때'를 이 층의 시간 해상도로 옮김). ",
                        "조작화 = 21거래일 이동 창(문헌 정의의 일간 조작화 — MW 는 사건을 달력 월로 부르고 월 창 자료는 월말 지수 · 이동 창은 월말을 가로지르는 급락을 쪼개지 않는다). ",
                        "달력 월 판(월말→월말 ≥ 20%)은 기록 — 보는 창에서 2008-05 위기 1건만 해당(짝 < 2 라 판정 불가)"),
    table = list(
      list(crisis = "2000-01-04 → 2000-05-29", depth = -0.381, max21 = -0.241, fast = TRUE, seg = "2000-03-29 → 2000-04-27", pre_me = "2000-02-29", pre_me_inside = TRUE, drop_after_pre_me = -0.198, cal_month_min = -0.156, prior = "반응 가능(구간 직전 월말이 위기 안)"),
      list(crisis = "2000-06-12 → 2000-12-04", depth = -0.420, max21 = -0.266, fast = TRUE, seg = "2000-08-22 → 2000-09-22", pre_me = "2000-07-31", pre_me_inside = TRUE, drop_after_pre_me = -0.301, cal_month_min = -0.162, prior = "반응 가능"),
      list(crisis = "2001-01-22 → 2001-04-10", depth = -0.233, max21 = -0.152, fast = FALSE, seg = "2001-03-08 → 2001-04-04", pre_me = "2001-02-28", pre_me_inside = TRUE, drop_after_pre_me = -0.155, cal_month_min = -0.097, prior = "—(느린 약세)"),
      list(crisis = "2001-05-29 → 2001-09-27", depth = -0.264, max21 = -0.187, fast = FALSE, seg = "2001-08-27 → 2001-09-25", pre_me = "2001-07-31", pre_me_inside = TRUE, drop_after_pre_me = -0.134, cal_month_min = -0.126, prior = "—(느린 약세)"),
      list(crisis = "2002-04-18 → 2002-10-10", depth = -0.377, max21 = -0.212, fast = TRUE, seg = "2002-09-12 → 2002-10-10", pre_me = "2002-08-30", pre_me_inside = TRUE, drop_after_pre_me = -0.207, cal_month_min = -0.121, prior = "반응 가능"),
      list(crisis = "2002-12-03 → 2003-03-17", depth = -0.298, max21 = -0.162, fast = FALSE, seg = "2003-02-24 → 2003-03-17", pre_me = "2003-01-30", pre_me_inside = TRUE, drop_after_pre_me = -0.127, cal_month_min = -0.132, prior = "—(느린 약세)"),
      list(crisis = "2004-04-23 → 2004-08-02", depth = -0.239, max21 = -0.232, fast = TRUE, seg = "2004-04-23 → 2004-05-17", pre_me = "2004-03-31", pre_me_inside = FALSE, drop_after_pre_me = -0.196, cal_month_min = -0.073, prior = "사전 포지셔닝만 — 빠른 구간이 고점에서 시작(직전 월말 = 위기 밖)"),
      list(crisis = "2007-10-11 → 2008-03-17", depth = -0.237, max21 = -0.166, fast = FALSE, seg = "2007-12-24 → 2008-01-22", pre_me = "2007-11-30", pre_me_inside = TRUE, drop_after_pre_me = -0.175, cal_month_min = -0.139, prior = "—(느린 약세)"),
      list(crisis = "2008-05-16 → 2008-10-24", depth = -0.494, max21 = -0.364, fast = TRUE, seg = "2008-09-25 → 2008-10-24", pre_me = "2008-08-29", pre_me_inside = TRUE, drop_after_pre_me = -0.348, cal_month_min = -0.210, prior = "반응 가능(빠른 구간 직전 넉 달이 위기 안)"),
      list(crisis = "2008-11-05 → 2008-11-20", depth = -0.203, max21 = -0.203, fast = TRUE, seg = "2008-11-05 → 2008-11-20", pre_me = "2008-10-31", pre_me_inside = FALSE, drop_after_pre_me = -0.162, cal_month_min = -0.046,
           prior = "대칭(C-047) — 결과는 10월 말 상태가 정한다: 지면 '미결 최빈(월말 0 · 경계 −20.3%)', 이기면 '10월 말 상태 이월 — 2008-05~10 과 한 상태 일화' · ④ 를 이 위기 포함 · 제외 두 판으로 기록"),
      list(crisis = "2011-05-02 → 2011-09-26", depth = -0.275, max21 = -0.225, fast = TRUE, seg = "2011-07-27 → 2011-08-22", pre_me = "2011-06-30", pre_me_inside = TRUE, drop_after_pre_me = -0.222, cal_month_min = -0.126,
           prior = "빠른 구간(07-27 시작) 노출 = 6월 말 상태(7월분) · 7월 말 상태(구간 3일째 · 8월분) — '반응 가능'은 8월 · 9월 몫"),
      list(crisis = "2017-11-03 → 2019-08-07", depth = -0.256, max21 = -0.140, fast = FALSE, seg = "2018-09-27 → 2018-10-29", pre_me = "2018-08-31", pre_me_inside = TRUE, drop_after_pre_me = -0.160, cal_month_min = -0.121, prior = "—(느린 약세)"),
      list(crisis = "2020-01-22 → 2020-03-19", depth = -0.349, max21 = -0.332, fast = TRUE, seg = "2020-02-19 → 2020-03-19", pre_me = "2020-01-31", pre_me_inside = TRUE, drop_after_pre_me = -0.300, cal_month_min = -0.116,
           prior = "1월 말 상태 평온 → 2월분은 막기 어려움 · 2월 말 신호(구간 6거래일째)가 3월을 덮는다"),
      list(crisis = "2021-06-25 → 2022-09-30", depth = -0.361, max21 = -0.142, fast = FALSE, seg = "2022-05-31 → 2022-07-01", pre_me = "2022-04-29", pre_me_inside = TRUE, drop_after_pre_me = -0.208, cal_month_min = -0.134, prior = "—(느린 약세)")),
    alt_definitions = "기록만: Pagan & Sossounov(2003) 시스템 강세 연대기(bbdetection max_chng 20 · 4개월 미만 국면 인정 ≈ MW 3개월) 판 · P2R02 상대 속도 판(표본 의존 — 2008-05~10 을 '완만'으로 분류해 빈칸 6 사례와 어긋남 · 채택 안 함)",
    note = "판정 대상은 칸마다 그 칸 보는 창 패킷의 위기(실효 시작이 정하는 창)이고 빠름 분류 · 위기 안 월말 수 · 빠른 구간은 같은 칸 산출물의 벤치 일수익으로 다시 계산한다(rules.fast · p2_fast_crash_keys)"),
  rules = list(
    tested = paste0("장치(또는 lag-1 판) × 엔진 판정은 다음을 모두 만족할 때만 — 아니면 미시험(반증 아님): ① 변형 · RX0 둘 다 평가됨(측정 ok ∧ 축 감사 ok) ",
                    "② 오버레이 집행 증거 — 변형 셀 로그에 '[rf_cell_engine] overlay <kind> | 축 …' 줄 · lag-1 판은 'overlay_shift=1 적용' 줄 있음 · 장치 칸은 그 줄 없음 ",
                    "③ 실효 시작 status = ok(두 칸) ④ 같은 선정 집합 — 보는 창 RX0 보유일마다 변형 보유 ⊆ RX0 보유(위반 0 · 변형 보유 결측 0) ⑤ 공통 창 사본 · 보는 창 패킷이 만들어짐 ",
                    "⑥ 위기 짝 — 두 칸의 위기가 모두 짝지어짐(짝 없는 위기 0) ∧ ① 의 짝 ≥ 2 ∧ ② 의 깊은 위기 짝 ≥ 2 ⑦ 판정 입력(①②⑤⑥⑨⑫⑬ · 알파 · 엔진 알파)이 모두 유한. ",
                    "측정 연기(워커 ok=FALSE · deferred)는 판정 전 같은 사양 재측정(rules.remeasure)"),
    remeasure = "인프라 실패(측정 결과 ok ≠ true) 칸은 measure.sh 가 같은 사양으로 1회 기계 재측정(RX0 먼저 단독 → 12칸) · 재측정 전 그 칸의 옛 칸 평가 캐시 · 지문 삭제 · 평가는 칸 평가 캐시의 산출물 = 현 측정 산출물을 단정",
    vintage_group = paste0("같은 엔진의 13칸(RX0 + 장치 6 + lag-1 6)은 함께 잰다(measure.sh — E2 묶음 → E3 묶음) · 칸마다 측정 시작 · 종료 데이터 지문(fingerprint.sh equality) — ",
                           "묶음 안 지문이 모두 같아야 판정 · 다르면 measure.sh 가 배리어 대기 뒤 그 묶음을 1회 재측정 · 그래도 다르면 evaluate.R 이 평가 전체를 멈춘다. ",
                           "평가 시점 지문을 함께 기록한다(이름 없는 문자열 비교)"),
    common_window = "변형과 RX0 의 실효 시작이 같으면 원 산출 · 다르면 공통 창 사본(늦게 시작한 칸의 첫 기간수익일 · 4파일 절단 · NAV · 벤치 재기준)에 같은 계약 적용 · 실패 = 미시험",
    pins_at_evaluation = "evaluate.R 은 시작부(셀 평가 샤드 포함)에서 precheck.R 과 같은 함수(p2_pin_mismatches)로 사양 · 운영 경로 · 비중 카탈로그 엔트리 · 오버레이 카탈로그 arm · 패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본을 재대조 — 다르면 평가하지 않는다",
    decisive = paste0("장치 × 엔진(보는 창 패킷 · 같은 엔진 RX0 대비 · tol = crisis_improve_min · 과반 = 비율 > majority_share): ",
                      "① 위기 과반 — 두 칸 모두의 위기에서 dd_capture < RX0 − tol 인 위기 비율 ",
                      "② 깊은 위기 과반 — 짝 위기 중 벤치 낙폭(bm_dd) 크기 ≥ 그 집합 중앙값인 위기에서 ① 과 같은 비율 ",
                      "③ β 짝 — k = 변형 β / RX0 β(behavior.stats.beta) · k < 1 이면 RX0 기간수익 · NAV · 보유를 k 배 노출로 낮춘 사본(잔여 현금)에 같은 계약(dp_build) · k ≥ 1 이면 사본 = RX0 · ",
                      "깊은 위기(②의 키)에서 dd_capture < 사본 − tol 인 위기 비율(짝 ≥ 2 · 아니면 'β 대조 미측정' = 통과 불가 · 사본 · 패킷 실패 · k 비유한도 같다) ",
                      "④ 빠른 급락 — 위기 [고점, 저점] 안에서 벤치가 fast_window_days 거래일 창 안에 fast_drop 이상 하락한 위기(같은 칸 RX0 산출물 05_benchmark_returns 일수익 누적곱) 에서 ",
                      "dd_capture < ③ 의 사본 − tol 인 위기 비율(짝 ≥ 2 · 아니면 '빠른 급락 미측정' = 통과 불가)"),
    strength = paste0("⑤ β 비대칭(철학 P1 C-044) — 장치 검증(통과 조건) = 변형 하락/상승 β 비(behavior.stats.beta_down / beta_up) < 같은 엔진 RX0 의 비 ",
                      "(비는 정적 축소에 불변 — 변화량만이 시변 층이 만든 비대칭 · 상승 β ≤ 0 · 비유한 = 판정 입력 NA = 미시험) · ",
                      "칸의 방어 주장(꼬리표 · 헌장 빈칸 3 · 8 문언) = 수준(하락 β < 상승 β) — 미달이면 '노출(β) 방어 — 비대칭 역행 · 방어 주장 불가' ",
                      "⑥ 강세 참여 — 두 칸의 강세 국면을 (start_ym, end_ym) 으로 짝짓고 변형 up_capture ≥ RX0 − (1 − bull_ratio) × |RX0| 인 국면 비율 > majority_share(짝 ≥ 2) ∧ ",
                      "변형 상승 포착 중앙값(behavior.summary.bull_up_capture_median) ≥ uc_floor ",
                      "⑦ 알파 비열등 — 보는 창 증분 β-통제 알파(rk_pair_alpha — 변형 − RX0 월 차이 · 벤치 대비 · NW lag 3) t > alpha_t_floor ∧ 증분 ≥ −alpha_margin_frac × max(엔진 α, 0) ",
                      "(엔진 α = RX0 대 벤치 보는 창 β-통제 알파 · 0 이하면 감소 허용 0) ",
                      "⑨ 사이클 복리 — 위기를 고점 순으로 놓고 위기마다 '직전 위기 바닥 연월 이후(같은 달 포함) 시작해 이 위기 고점 연월까지(같은 달 포함) 끝난 강세 중 마지막'과 짝(강세 1회 · 짝 없는 위기 기록) · ",
                      "사이클 수익 (1+강세 st_cum)(1+위기 st_cum) − 1 이 RX0 이상인 사이클 비율 > majority_share(두 칸 같은 짝만 · 짝 2 미만 = 판정 입력 NA = 미시험)"),
    non_inferiority = "⑫ S — RX0 의 S_vis > 0 이면 S_vis(변형) ≥ S_vis(RX0) − tie_eps · 0 이면 Calmar(변형) ≥ Calmar(RX0) · ⑬ 복리 경로 — mdd_vs_bench ≤ RX0 ∧ CDaR ≤ RX0",
    pit_construction = paste0("⑩ 통과 조건 = 오버레이 집행 증거(rules.tested ②) — 엔진이 신호 가용일 < 보유월 시작(assert_overlay_pit 한계 = 홀딩 시작 전날 · P0-09)을 단정하고 어기면 측정이 멈추므로 ",
                              "측정된 칸 = 통과한 칸 · 이 경로의 현 타이밍이 곧 strict 컷오프(Date < 보유월 첫날)라 strict-PIT A/B 차이는 구성상 0. ",
                              "진단(통과 조건 아님) = lag-1 판을 같은 함수로 판정해 장치 칸이 넘은 ③ · ④ 를 lag-1 판도 넘으면 'lag-1 유지' · 아니면 '지연 민감(lag-1 에서 ③ · ④ 붕괴)' 꼬리표 — ",
                              "월간 층은 한 달 안에 시작하는 급락에 원리상 늦고 lag-1 은 그 늦음을 한 달 더 키우므로(T1 C-039) 정당한 빠른 방어를 구조적으로 기각하지 않기 위해서다(pit.md C5 — lag-1 = 의심 신호 · strict A/B = 판정). ",
                              "철학 P1 C-052 유지 조건: (a) '지연 민감' 꼬리표를 결론 · 보고 · P4 후보 묶음 · P3 의견서에 싣는다 ",
                              "(b) 장치 칸이 느린 약세(빠름으로 분류되지 않은 위기)에서 β 짝 과반(짝 ≥ 2)을 넘었는데 lag-1 판이 못 넘으면 '누출 조사' — 설명될 때까지 최종 선택 보류(p2_lag_hold · lag-1 판 짝 < 2 = 보류 아님) ",
                              "(c) 셀 로그 집행 줄은 집행의 증거이고, PIT 의 증거는 엔진 assert_overlay_pit(가용일 · P0-09 마스크 · 양성 대조 test_rf_overlay_pit_mask.R)다"),
    concentration = "⑧ 깊은 위기 중 한 종목 최악 기여(exposure.top_losers contrib)가 single_name_loss_floor 보다 나쁜 위기가 하나라도 있으면 '집중 손실' · 표 결손 · 깊은 위기 누락 = '집중 손실 미측정' — 둘 다 검증 장치에서 제외(통과여도) · 유효 종목 수 · 최대 비중 기록",
    recovery = "⑪ 두 칸 모두의 위기에서 변형 회복 관측(st_recovery_obs · 미회복이면 관측 하한)이 RX0 보다 긴 위기 비율 > majority_share 면 '회복 지연' 꼬리표(판정 보조 · 통과 조건 아님)",
    pass = "장치 칸 통과 = ① ∧ ② ∧ ③ ∧ ④ ∧ ⑤ ∧ ⑥ ∧ ⑦ ∧ ⑨ ∧ ⑩(구성 증거) ∧ ⑫ ∧ ⑬ · 장치 검증 = 두 엔진 통과 ∧ ⑧ 제외 아님",
    selection = "검증 장치(두 엔진 통과 ∧ 집중 제외 아님) 중 lag-1 조건 (b) 보류가 아닌 것에서 보는 창 S 의 RX0 대비 증분(두 엔진 평균)이 가장 큰 1개 · 동률(차 < 1e-12)이면 ③ · ④ 비율 합(두 엔진 평균) · 검증 0 = 선택 없음 · 꼬리표: lag-1 · 회복 · ⑤ 수준 · 귀속(MC8 라벨 + β 짝 + size_exposure_path)",
    round_verdict = "supported = 검증 장치 ≥ 1 · partial = 한 엔진 통과 또는 두 엔진 통과지만 집중 제외 · falsified = 판정된 장치 칸 중 통과 0 · untested = 판정된 장치 칸 0 — '판정(판정 칸/전체 장치 칸 12)'으로 적는다",
    failure_semantics = paste0("사전 고정: 평가 상태 · 오버레이 집행 증거 · 실효 시작 · 같은 선정 집합 · 공통 창 · 패킷 · 위기 짝 · 판정 입력 실패 = 그 칸 미시험(반증 아님) / ",
                               "그 밖의 예기치 않은 평가 오류 = 그 칸 미시험(오류 문구 기록 · 라운드 평가는 계속 — p2_eval_pair_safe) / β 사본 실패 · ③ 짝 < 2 = 'β 대조 미측정'(통과 불가) / ",
                               "④ 짝 < 2 = '빠른 급락 미측정'(통과 불가) / 집중 손실 표 결손 = '집중 손실 미측정'(제외) / 핀 · 행동 카드 사본 · 지문 · 칸 평가 캐시 불일치 = 평가 중단"),
    files = "칸 평가 = results/<code>/visible/{diagnosis_packet.json, eval_visible.json} · results/<code>/full/{behavior_card.json, eval_full.json, NO_VISIBLE_REVIEW.txt} · 종합 = results/evaluation_visible.json(보는 창 리뷰어 열람 가능) · results/evaluation_full.json(사람 쪽 전용 · C-031)",
    test_window = "시험 창(2023-01~) 증분 알파 · 위기 포착 · 성과는 사람 쪽 보고만(evaluation_full.json · 선택 · 판정 입력 아님)",
    record = paste0("판정 입력 아님: 오버레이 노출(평균 · 최소 · 완전현금 · 현금 집행 수) · 회전 · 비용 · 평균 노출 · 위기별 표(①~④) · 강세 국면별 표 · 사이클 표 · 롤링 · ",
                    "귀속(MC8) · 집중 · 알파 표준오차 · 여유/표준오차 · 엔진 알파(자격) · 지문 · (철학 P1) Henriksson-Merton 타이밍 회귀(변형 − RX0 월 수익 ~ 벤치 + max(0, −벤치) · ",
                    "계약 .nw_fit · NW 3 · γ · t) · 현금 타이밍(현금 달 = 노출 ≤ 0.5 · 정밀도 = 현금 달 중 위기 달 · 재현율 = 위기 달 중 현금 달 · 위기/비위기 노출 · 반등 3 · 6개월 노출) · ",
                    "④ 기록 판(위기 안 월말 0 인 급락 제외 · C-047) · 느린 약세 β 짝 비율 · 빠른 구간 시작/끝 · 대조 읽기(엔진별 장치 간 월 노출 경로 상관 · 깊은 위기 β 짝 승패 겹침 · ",
                    "D3 vs D6 · D1 vs D6 · D5 vs D6 · D4 vs D3 · D7 vs D6 · C-049) · 새 판본 RX0 의 병목 지표(위기 포착 · Calmar · β · 하락/상승 β)를 P3R03 RX0(구 판본)와 나란히(C-050)"),
    leave_behind = paste0("검증 0 일 때 남길 것(C-050): 장치 × 항목(①~⑬) × 위기 실패 지도 — 실패 원인을 신호 지연(lag-1 · 위기 안 월말) · 현금 비용(⑦ · ⑫) · 엔진 비대칭(⑤ 수준 vs 변화량) · ",
                          "재진입(⑥ · ⑨ · 반등 노출 · D7 대비) 중 무엇인지로 분류 · 대조 읽기 5쌍 · 현금 타이밍 정밀도/재현율 — 다음 라운드(비대칭 원천 ① 분포 표적 · ③ 방어적 보유 × β 짝)의 입력")),
  expectations = list(
    D1 = "하방베타 높은 종목을 낙폭 국면에 줄인다 — 횡단면 차등이라 β 짝(③)을 넘을 사전 확률 중간 · 빠른 급락은 국면 진입이 늦어 약함",
    D2 = "산포 국면 × 특이변동 — D1 과 비슷 · 산포가 급락 직후 커져 빠른 급락(④) 약함",
    D3 = "상태 거리 90분위 이상 = 현금 — 급락 두 번째 달부터 강함 · 2008-11(월말 0)과 2020 첫 달은 못 막음 · 강세 초입 재진입 지연(⑥) 위험",
    D4 = "꼬리 확률 = 확장창 로지스틱 — 노출이 연속적 · 표본 축소 n_min 48 · 강세 참여 손실 작음 · 빠른 급락 판별력 사전 확률 낮음(상태 4축 평균 예측의 한계)",
    D5 = "추세 현금 — 느린 약세(2001 · 2002 · 2008 · 2018 · 2022)에서 강함 · V자(2020)와 짧은 급락에서 늦음 · 강세 초입 재진입 지연이 ⑥ · ⑦ 을 깎을 위험(재시험 · 이전 측정 무효)",
    D6 = "낙폭 브레이크 — 깊은 낙폭에서만 현금 · 바닥 근처에서 현금이라 회복 참여(⑪ · ⑨) 손실 위험(재시험)",
    D7 = paste0("재진입 게이트(철학 P1 C-045 사전 기대) — 빠른 급락: 직전 달 하락 뒤 현금이라 보유월 2개 이상에 걸친 급락(2008-05 · 2020-01)의 둘째 달 이후를 막고 첫 달은 진다 · ",
                "반등: 첫 상승 달 뒤 재진입이라 ⑥ · ⑨ · ⑪ 이 늦게 꺼지는 다섯 장치(D1 · D3 · D4 · D5 · D6)보다 낫다 · 수중 횡보(2011~16 · 2018~19): 잦은 전환으로 회전 비용 · 휩쏘 → ⑦ · ⑫ 위험. ",
                "반증: 늦게 꺼지는 다섯 장치가 ⑥ · ⑨ · ⑪ 에서 RX0 대비 반등 상실을 안 보이면 moot · D7 의 ⑥ · ⑨ · ⑪ 이 그 다섯보다 낫지 않으면 refuted(재진입 규칙이 이 형태를 못 고친다)"),
    overall = "철학 Superfan C-028: 정적 β 사본을 이기는 것은 '현금을 위기 국면에만' 쓰는 장치다 — 7종 중 0~2개 통과가 사전 기대(같은 상태 축 공유 — 독립 7개 아님) · 통과 0 이면 교훈을 남기고 비대칭 원천 ①(분포 표적)과 ③(방어적 보유 × β 짝)으로 간다"),
  final_selection_rule = FS,
  axis_audit = "측정 뒤 04_holdings 실보유가 롱온리 · ≤ max_names · Σw ≤ 1 — 위반 칸 = 측정 무효(미시험)",
  behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP)),
  operational_pins = .ops_pins(),
  evaluation = list(files = .eval_pins(), note = "판정 구현(evaluate.R) · 픽스처 · precheck · 측정 절차(measure.sh) · 데이터 지문(fingerprint.sh) · 규칙 상수(round_rules.R)를 결과 전에 고정 — evaluate.R 은 시작부(샤드 포함)에서 이 md5 와 운영 핀 전체를 재대조한다"),
  rehearsal = .rehearsal(),
  philosophy_p1 = .p1_check(),                                                  # 등록 때 다시 확인(--register)
  tests = TESTS,
  precheck = "측정 직전 precheck.R 가 evaluate.R 의 p2_pin_mismatches 로 사양 · 운영 경로 · 카탈로그(비중 1 · 오버레이 7) · 패키지 · R 판 · 평가 경로 · 행동 카드 설정 사본을 다시 대조 — 다르면 측정하지 않는다 · 데이터 지문 기록",
  data_note = "데이터 판본: RAWDATA · 벤치 퀀티 단일(225f909f2 · 25fa73831) · 2024-12-30 복원(48b3d3bfd) · 측정 축 동전주 바닥(all_hyg_px1000_2000_v1) · 일요일 00:03 Qvest_DailyRefresh 뒤 같은 배치로 잰다(measure.sh 대기) · 지문에 남긴다",
  design_inputs = "DESIGN.md v3 · 카탈로그 arm 정의 · 문헌 착상 7항(BASIS) · 측정 · 평가 계약 코드 · P3R03 사전등록 형식 · 판단 원장 J-20261017-007 · 009 · 010 · T1 리뷰 · 철학 P1 — 시험 창 성과 미사용",
  budget = list(variants = N_ROUND, reference_remeasure = length(ENGINES), diagnostic_lag1 = N_ROUND, rounds = 1L,
                note = "변형 12 만 시행 수 가산(계보 2002.06975) · RX0 2 · lag-1 12 = 무가산 · DSR 표본 아님(T1 C-038)"),
  changes_after_superfan = list(
    ch("T1 C-033 후보 근거", "보는 창 · 현 축 근거로 후보표 재작성 · 추세 현금 · 낙폭 브레이크 재시험(전액 현금 결함 발견) · C4/C5/C6 저변동 = 범위 밖 사유 명기 · DIST 열람 exposures · 후보 J 별도(J-009)",
       "DIST-GEN-155 · 027 은 구 축 · 전기간 · 수익 t 지표였고 P2R02 C4 · C6 제외 사유가 비었다"),
    ch("T1 C-034 기준선", "기저를 HRP → 엔진 자체 구성으로(층 효과 · 엔진 강점이 같은 기준 · β 짝 = RX0 × k) · 엔진 자격 = RX0 보는 창 β-통제 알파 기록",
       "헌장 '같은 엔진 기준' = 엔진 자체 구성 · HRP 의 강세 손실이 기준에 묻힌다"),
    ch("T1 C-037 · 038 · 039", "D3 개명(벤치 상태 벡터 거리) · PIT 의무 1~4 명시(rules.pit_construction) · 예산 칸 분리 · 빠른 급락 사전 기대표(fast_crash_prior)", "수용"),
    ch("철학 P1 C-044 ⑤ 판정 단위", "장치 검증 = 하락/상승 β 비의 변화량(비 < RX0 비 · 정적 축소 불변) · 칸 방어 주장 = 수준 꼬리표 · HM 타이밍 회귀 기록(계약 .nw_fit)",
       "E2 엔진 자체가 역비대칭(비 1.32)이라 수준을 두 엔진 통과 조건으로 두면 장치가 아니라 엔진이 검증을 정한다"),
    ch("철학 P1 C-045 재진입 축", "D7 dd_recovery(재진입 규칙) 추가 · 사전 기대 · 반증 조건 등록 · 변형 12 → 14 · 30칸", "6종 중 5종이 바닥 뒤 늦게 꺼져 공통 실패 형태가 반등 상실인데 그 원인을 겨누는 arm 이 '원리 중복'으로 빠져 있었다"),
    ch("철학 P1 C-046 결론 범위", "conclusion_scope 를 여섯 줄(+ 기록 정정)로 — 범위 · 방어 정의 · 현금 기계 이름 · 엔진 강점 · 귀속(타이밍 ≠ 선택 · size_exposure_path 병기) · 단일 엔진 · 지연 민감", "방어 절반만 말하고 '방어만 · 복리 없음'의 이름이 없었다"),
    ch("철학 P1 C-047 · 048 · 049 · 050 · 052(기록 · 조건)", paste0("빠른 급락 정의 근거(p.6~7 · 창 = 결정 주기 · 21거래일 = 일간 조작화 · 달력 월 판 기록) · 표에 빠른 구간 · 직전 월말 · 2008-11 대칭 · ④ 월말 0 제외 판 기록 · ",
       "현금 타이밍(정밀도 · 재현율 · 반등 노출) · 대조 읽기 5쌍 · D4~D7 '원문 구현 아님' · 검증 0 남길 것 · lag-1 조건 (a)(b)(c) — (b) 는 최종 선택 보류 규칙(p2_lag_hold)"), "수용"),
    ch("철학 P1 C-050 P2R02 표기", "P2R02 의 C6 '검증' = 전액 현금 결함 위 측정이라 무효 · C4 '검증' = 빈칸 8(β 짝) 이전 판정 — 이 사전등록 candidates.excluded 와 라운드 보고 · 등록부 메모에 적는다", "수용"),
    ch("철학 P1 C-051 헌장 빈칸 5건", "결정 기록부 상신(타이밍 방어의 자리 · 빈칸 6 과 결정 주기 · 집행 지연 강건성 · 현금 층 재진입 · 세는 단위와 문턱) — 이 라운드 판정은 기본값(현 헌장)으로", "도훈 교정 필요 — 결과 전에 상신")),
  changes_after_review = list())
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), DR, useBytes = TRUE)
cat(sprintf("[P2R03] 초안 v%d %s (md5 %s) · 칸 %d(장치 %d + 기준 %d + lag-1 %d) · 검사 %s · 시행 회계 E2 %d · E3 %d\n", pre$draft_version, DR, rk_md5(DR),
            length(cells), N_ROUND, length(ENGINES), N_ROUND,
            paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "),
            ENGINES$E2$n_prior + N_ROUND, ENGINES$E3$n_prior + N_ROUND))
