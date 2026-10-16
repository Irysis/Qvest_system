## P3R03 원문 고도화 구성 — 원문대로 구현한 비중 결정법 5종(HRP · NCO · Michaud 재표집 최소분산 · CVaR LP · ERC)이 같은 엔진 · 같은 배치 기준(RX0)보다
##   알파 손실 없이 급락기 낙폭을 줄이는가(복리 경로 · 깊은 위기 · 강세 참여를 지키면서)
##   설계 = Q 자율 판단(판단 원장 J-20261016-001 라운드 선택 · J-002 후보 · J-003 원문 구현 선행) · 철학 Superfan P1(R-20261016-001 · C-001~C-005 수용) ·
##   어댑터 = 02_Infrastructure/methods/adapters/{hrp_lopez_de_prado_2016,nco_lopez_de_prado_2019,michaud_resampled_minvar,cvar_lp_rockafellar_uryasev_2000,erc_maillard_roncalli_teiletche_2010}.R
##   (원문 대조 검사 08_Tests/methods/test_p3r03_adapters.R · 커밋 98884bf29)
## 실행:
##   Rscript register.R --draft      초안(검사 3종을 실제로 돌려 통과 수를 싣는다 · 리허설 요약이 통과 ∧ 현 evaluate.R 판이어야 한다 · 실패면 초안을 쓰지 않는다)
##   Rscript register.R --register   등록 — 검토판 보존 · 사양 · 운영 · 평가 경로 md5 · 패키지 · R 판 · 리허설 · 커밋 상태(고정 대상 전부)를 확인한 뒤에만
##   ★R2: 이 라운드의 측정 결과(results/P3R03_*.json)가 하나라도 있으면 사전등록을 바꾸지 않는다.
##   v2(2026-10-16 · 격리 교차 점검 v1 = revise 반영): 핀 확대(결과 계약 · E3 기준 비중법 · 강세 국면 패키지 · 롤링 등급 · 위생 판정식 등) · 시행 회계 = 계보(family_root) ·
##   리허설(rehearse.R) 연결 · 커밋 확인 = 고정 대상 전부 · 규칙 문장(사이클 짝 · 미측정 꼬리표 · 실패 의미 · 같은 선정 집합 · 재측정 규칙) 갱신
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
args <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--register" %in% args) "register" else if ("--draft" %in% args) "draft" else stop("usage: register.R --draft | --register")
PROGRAM <- "P3_CONSTRUCTION"; ROUND <- "P3R03_advanced_construction"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
PR <- file.path(P$prereg_dir, "prereg.json"); DR <- file.path(RD, "prereg_draft.json")
## 격리 교차 점검을 받은 초안 보존본(있으면 등록판에 연결 — 없으면 --register 거부)
REVIEWED <- Filter(function(z) file.exists(z$path), list(
  list(version = 1L, path = file.path(RD, "prereg_draft_reviewed_v1.json"), review = "격리 교차 점검(결과 미열람 · 범용 에이전트) — revise(필수 5 · 권고 13)"),
  list(version = 2L, path = file.path(RD, "prereg_draft_reviewed_v2.json"), review = "격리 변경분 점검(v1 → v2 · 결과 미열람 · 범용 에이전트) — pass(필수 5 재도출 fixed · 권고 5 · 선택 1)")))
rel <- function(p) sub(paste0("^", ROOT, "/"), "", p)
.measured_any <- function() length(Sys.glob(file.path(RD, "results", "P3R03_*.json"))) > 0L
if (.measured_any()) stop("[P3R03] 측정 결과가 생긴 뒤에는 사전등록을 바꿀 수 없다(R2)")
if (file.exists(PR)) stop("[P3R03] 사전등록이 이미 있다(R2) — 대체는 측정 전 · 별도 절차로만")

ADS <- c(HRP = "02_Infrastructure/methods/adapters/hrp_lopez_de_prado_2016.R", NCO = "02_Infrastructure/methods/adapters/nco_lopez_de_prado_2019.R",
         MRE = "02_Infrastructure/methods/adapters/michaud_resampled_minvar.R", CVR = "02_Infrastructure/methods/adapters/cvar_lp_rockafellar_uryasev_2000.R",
         ERC = "02_Infrastructure/methods/adapters/erc_maillard_roncalli_teiletche_2010.R")
CATS <- c(HRP = "paper:HRPLdP2016", NCO = "paper:NCOLdP2019", MRE = "paper:MichaudResampledMinVar", CVR = "paper:CVaRLPRU2000", ERC = "paper:ERCMRT2010")
OPS <- c(unname(ADS), "02_Infrastructure/portfolio/weight_catalog.R", "02_Infrastructure/methods/method_registry.R", "02_Infrastructure/portfolio/strategy_tilt_weights.R",
         "02_Infrastructure/reinforcement/rf_cell_engine.R", "02_Infrastructure/reinforcement/rf_base_cache.R", "02_Infrastructure/reinforcement/rf_axes.R",
         "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/reinforcement/rf_sleeve.R", "02_Infrastructure/ops/rf_cell_worker.R",
         "02_Infrastructure/alpha_search/run_paper_replication.R", "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/backtest_harness.R",
         "02_Infrastructure/config.R", "02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/behavior_card.R",
         "02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/matched_controls.R", "02_Infrastructure/contracts/grade_v3.R",
         "02_Infrastructure/contracts/tilt_attribution.R", "02_Infrastructure/contracts/beta_controlled_alpha.R", "06_Registry/matched_controls.json",
         "02_Infrastructure/worktask/constraint_defaults.json", "04_Research/strategies/RP_AUTO_2002_06975/engine.R",
         "02_Infrastructure/factor_db/factor_db_connector.R", "04_Research/programs/_lib/round_kit.R", "04_Research/programs/_lib/measure_round_cell.R",
         "04_Research/programs/_lib/eval_parallel.sh", "02_Infrastructure/ops/refresh_barrier.sh",
         ## v2 추가(교차 점검 필수 3) — 판정에 닿는데 핀 밖이던 것: 02~05 산출 · S 의 Calmar · PORT_t(결과 계약 · 저장) · 등급 · E3 기준 비중(lean:entropy 운반 함수) ·
         ## 노출 분해 설정(selection_sum · top_losers) · 롤링 등급(기록) · 위생 판정식(corp_action_member) · 등급 설정
         "02_Infrastructure/contracts/backtest_result_contract.R", "02_Infrastructure/contracts/save_bt_result.R", "02_Infrastructure/contracts/essence_score.R",
         "02_Infrastructure/portfolio/advanced_weights.R", "02_Infrastructure/contracts/tilt_attribution_config.json", "02_Infrastructure/contracts/rolling_grade.R",
         "06_Registry/rolling_grade.json", "02_Infrastructure/factor_db/factor_z_standard.R", "06_Registry/grade_v3.json")
EVALF <- c("evaluate.R", "evaluate_fixture.R", "precheck.R", "measure.sh", "fingerprint.sh")
PIN_CATS <- c(unname(CATS), "lean:entropy")                                       # lean:entropy = E3 RX0 비중(엔진 정의)
.ops_pins <- function() {
  wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
  ents <- lapply(PIN_CATS, function(cid) { e <- Filter(function(z) identical(z$catalog_id, cid), wc)
    if (!length(e)) stop("[P3R03] 카탈로그 엔트리 없음: ", cid); list(catalog_id = cid, status = e[[1]]$status, resolver = e[[1]]$resolver) })
  list(files = lapply(OPS, function(f) list(path = f, md5 = rk_md5(file.path(ROOT, f)))), catalog_entries = ents,
       packages = list(quadprog = as.character(utils::packageVersion("quadprog")), lpSolve = as.character(utils::packageVersion("lpSolve")),
                       bbdetection = as.character(utils::packageVersion("bbdetection"))),
       r_version = R.version.string)
}
.eval_pins <- function() lapply(EVALF, function(f) { p <- file.path(RD, f); list(path = rel(p), md5 = rk_md5(p)) })
## 리허설(교차 점검 필수 4) — 요약이 통과 ∧ 현 evaluate.R 판으로 돈 것이어야 한다
REH <- file.path(RD, "rehearsal", "summary.json")
.rehearsal <- function() {
  if (!file.exists(REH)) stop("[P3R03] 리허설 요약이 없다 — Rscript rehearse.R 먼저")
  s <- fromJSON(REH, simplifyVector = FALSE)
  if (!isTRUE(s$pass)) stop("[P3R03] 리허설 실패 — 등록하지 않는다")
  if (!identical(s$evaluate_md5, rk_md5(file.path(RD, "evaluate.R")))) stop("[P3R03] 리허설 뒤 evaluate.R 이 바뀌었다 — 다시 리허설")
  list(script = list(path = rel(file.path(RD, "rehearse.R")), md5 = rk_md5(file.path(RD, "rehearse.R"))), summary = list(path = rel(REH), md5 = rk_md5(REH)),
       evaluate_md5 = s$evaluate_md5, pass = TRUE, inputs = s$inputs, seconds = s$seconds)
}
COMMIT_PATHS <- unique(c(unname(ADS), "08_Tests/methods/test_p3r03_adapters.R", "08_Tests/programs/test_round_kit_pair_alpha.R", rel(RD),
                         "06_Registry/method_registry.json", "06_Registry/weight_catalog.json", OPS))      # 권고 10 — 고정 대상 전부
.uncommitted <- function() { s <- system2("git", c("-C", ROOT, "status", "--porcelain", "--", COMMIT_PATHS), stdout = TRUE)
  s <- s[nzchar(s)]; s[!grepl("prereg_draft|results/|rehearsal/out", s)] }
.run_test <- function(path) {
  o <- suppressWarnings(system2("Rscript", shQuote(path), stdout = TRUE, stderr = TRUE))
  j <- grep('^\\{"test"', o, value = TRUE)
  if (length(j)) { r <- fromJSON(j[length(j)]); return(list(path = rel(path), md5 = rk_md5(path), pass = r$pass, fail = r$fail)) }
  list(path = rel(path), md5 = rk_md5(path), pass = NA, fail = NA)
}

if (MODE == "register") {
  if (!file.exists(DR)) stop("[P3R03] 초안이 없다 — --draft 먼저")
  if (!length(REVIEWED)) stop("[P3R03] 격리 교차 점검 보존본이 없다 — 점검 뒤 등록")
  pre <- fromJSON(DR, simplifyVector = FALSE)
  if (!length(pre$changes_after_review)) stop("[P3R03] 교차 점검 반영 기록(changes_after_review)이 비었다")
  for (c in pre$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P3R03] 사양 md5 ≠ 초안: ", c$code)
  now <- .ops_pins()
  for (f in pre$operational_pins$files) {
    m <- Filter(function(z) identical(z$path, f$path), now$files)[[1]]$md5
    if (!identical(m, f$md5)) stop("[P3R03] 운영 경로 md5 ≠ 초안(초안 뒤 구현이 바뀌었다): ", f$path)
  }
  if (!identical(now$packages, pre$operational_pins$packages) || !identical(now$r_version, pre$operational_pins$r_version)) stop("[P3R03] 패키지 · R 판 ≠ 초안")
  for (f in pre$evaluation$files) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P3R03] 평가 경로 md5 ≠ 초안: ", f$path)
  for (t in pre$tests) if (!identical(rk_md5(file.path(ROOT, t$path)), t$md5) || !identical(as.integer(t$fail), 0L)) stop("[P3R03] 검사 파일 변경 또는 실패: ", t$path)
  for (e in pre$operational_pins$catalog_entries) if (!any(vapply(now$catalog_entries, function(z) identical(z$catalog_id, e$catalog_id) &&
      identical(toJSON(z, auto_unbox = TRUE, null = "null"), toJSON(e, auto_unbox = TRUE, null = "null")), logical(1)))) stop("[P3R03] 카탈로그 엔트리 ≠ 초안: ", e$catalog_id)
  rh <- .rehearsal()
  if (!identical(rh$evaluate_md5, pre$rehearsal$evaluate_md5) || !identical(rh$summary$md5, pre$rehearsal$summary$md5) ||
      !identical(rh$script$md5, pre$rehearsal$script$md5)) stop("[P3R03] 리허설 기록(evaluate · 요약 · 리허설 스크립트 md5) ≠ 초안")
  if (!identical(rk_md5(file.path(ROOT, pre$behavior_card_cfg$path)), pre$behavior_card_cfg$md5)) stop("[P3R03] 행동 카드 설정 사본 md5 ≠ 초안")
  unc <- .uncommitted()
  if (length(unc)) stop("[P3R03] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n"))
  pre$status <- "registered"; pre$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"); pre$draft_md5 <- rk_md5(DR)
  pre$reviewed_drafts <- lapply(REVIEWED, function(rv) list(version = rv$version, path = rel(rv$path), md5 = rk_md5(rv$path), review = rv$review))
  pre$git_head_at_register <- tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_)
  dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
  file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                n_variants = length(Filter(function(z) !isTRUE(z$reference), pre$cells)),
                                variants = unname(vapply(pre$cells, function(z) z$code, character(1)))), root = ROOT)
  cat(sprintf("[P3R03] 사전등록 %s (md5 %s) · 칸 %d · HEAD %s\n", PR, rk_md5(PR), length(pre$cells), pre$git_head_at_register))
  quit(status = 0)
}

## ── 초안 ─────────────────────────────────────────────────────────────────────
TESTS <- list(.run_test(file.path(ROOT, "08_Tests/methods/test_p3r03_adapters.R")), .run_test(file.path(RD, "evaluate_fixture.R")),
              .run_test(file.path(ROOT, "08_Tests/programs/test_round_kit_pair_alpha.R")))
for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P3R03] 검사 실패 — 초안을 쓰지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")
EP <- ma_epoch(root = ROOT)
P0SP <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs")
## 시행 회계(교차 점검 권고 1) — 계보(family_root)마다 앞선 모든 사전등록 칸의 n_family 최댓값 + 이 라운드 처방 변형 수(RX0 무가산).
##   엔진 이름이 아니라 계보로 센다 — E2 · E3 는 같은 계보(2002.06975)라 한 엔진의 시행이 다른 엔진의 선택 집합에도 들어간다
.spec_root <- function(path) tryCatch(fromJSON(file.path(ROOT, path), simplifyVector = FALSE)$selection_accounting$family_root %||% NA_character_,
                                      error = function(e) NA_character_)
nf_prior <- function(root_id) {
  v <- unlist(lapply(Sys.glob(file.path(ROOT, "stage_artifacts/programs/*/*/prereg.json")), function(p) {
    d <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
    vapply(Filter(function(z) is.numeric(z$n_family) && !is.null(z$path) && identical(.spec_root(z$path), root_id), d$cells %||% list()),
           function(z) as.integer(z$n_family), integer(1))
  }))
  if (length(v)) max(v) else 0L
}
ENGINES <- list(E2 = list(ref = "P0R01_E2_C0", base_weighting = "EW(동일 비중)"),
                E3 = list(ref = "P0R01_E3_C0", base_weighting = "lean:entropy(엔진 자체 엔트로피 비중 · B6_36 정의)"))
for (e in names(ENGINES)) {
  ENGINES[[e]]$family_root <- .spec_root(file.path("04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs", paste0(ENGINES[[e]]$ref, ".json")))
  if (is.na(ENGINES[[e]]$family_root)) stop("[P3R03] 기준 사양 계보(family_root) 판독 실패: ", ENGINES[[e]]$ref)
  ENGINES[[e]]$n_prior <- nf_prior(ENGINES[[e]]$family_root)
}
VAR <- list(
  HRP = list(name = "계층적 위험 균등(HRP · 단일 연결 · 원문 부록 A.3)",
             basis = "López de Prado(2016) Building Diversified Portfolios that Outperform Out-of-Sample, JPM 42(4) · SSRN 2708678 부록 A.3 코드 — 상관 거리 · 거리의 거리 · 단일 연결 · 준대각화 · 재귀 이분(IVP 군집 분산)"),
  NCO = list(name = "군집 중첩 최적화(NCO · MP 잡음 제거 · 군집 내 · 간 롱온리 최소분산)",
             basis = "López de Prado(2019) A Robust Estimator of the Efficient Frontier, SSRN 3469961 · MLAM(2020) §2 · §4 · §7 · 특허 US20210081828A1 코드 5 — 잡음 제거(bWidth 0.01) → K-평균 실루엣 t(상한 n/2 · 초기값 10) → 군집 내 · 간 최적화"),
  MRE = list(name = "재표집 효율 최소분산(Michaud RE · B 500)",
             basis = "Michaud(1998) Efficient Asset Management · Michaud & Michaud(2008) Estimation Error and Portfolio Optimization: A Resampling Solution, JOIM 6(1) — 다변량 정규 · 원 자료 길이 · 롱온리 최소분산 평균(Step 1~4 · 각주 14 · p.6)"),
  CVR = list(name = "CVaR 최소화 선형계획(β 0.95)",
             basis = "Rockafellar & Uryasev(2000) Optimization of Conditional Value-at-Risk, J. Risk 2(3) — 정리 2 시나리오 LP · 예제 β 0.90 · 0.95 · 0.99 의 가운데"),
  ERC = list(name = "위험 기여 균등(ERC)",
             basis = "Maillard, Roncalli & Teïletche(2010) The Properties of Equally Weighted Risk Contribution Portfolios, JPM 36(4) · SSRN 1271972 — 순환 좌표 하강(Griveau-Billion · Richard · Roncalli 2013 arXiv 1311.4057)"))
for (k in names(VAR)) {
  VAR[[k]]$delta <- list(weighting = list(kind = "catalog", catalog_id = unname(CATS[k]), label = sub("^paper:", "", unname(CATS[k]))))
  VAR[[k]]$adapter <- list(path = unname(ADS[k]), md5 = rk_md5(file.path(ROOT, ADS[k])))
}
N_ROUND <- length(ENGINES) * length(VAR)
cells <- list(); bad <- character(0)
for (eid in names(ENGINES)) {
  e <- ENGINES[[eid]]
  b <- fromJSON(file.path(P0SP, paste0(e$ref, ".json")), simplifyVector = FALSE)
  nf <- as.integer(e$n_prior + N_ROUND)
  SA <- list(selection_type = "sweep", family_root = b$selection_accounting$family_root,
             lineage = c(paste0("RX_", ROUND), unlist(b$selection_accounting$lineage)), n_family_at_registration = nf,
             n_trials_basis = sprintf("P3R03: 앞선 사전등록 칸 중 계보 %s(E2 · E3 공통) 회계 최댓값 %d + 이 라운드 %d(엔진 %d × 구성 %d) · 기준 재측정 RX0 무가산(v2 — 엔진 이름이 아니라 계보로 센다)",
                                      e$family_root, as.integer(e$n_prior), N_ROUND, length(ENGINES), length(VAR)))
  for (k in names(VAR)) {
    d <- VAR[[k]]$delta; code <- sprintf("P3R03_%s_%s", eid, k)
    v <- rx_validate(d, ROOT); if (!isTRUE(v$ok)) { bad <- c(bad, sprintf("%s: %s", code, paste(v$errors, collapse = " | "))); next }
    sp <- rx_compile_spec(b, d, code = code, label = sprintf("%s × %s", eid, VAR[[k]]$name),
                          idea = sprintf("[P3R03 원문 고도화 구성 · %s × %s] %s", eid, k, VAR[[k]]$basis), selection_accounting = SA, epoch = EP, root = ROOT)
    f <- file.path(P$specs_dir, paste0(code, ".json")); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    writeLines(toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
    cells[[code]] <- list(code = code, engine = eid, component = k, path = rel(f), md5 = rk_md5(f), n_family = nf, reference = FALSE)
  }
  code0 <- sprintf("P3R03_%s_RX0", eid)
  SA0 <- c(b$selection_accounting, list(remeasure_of = e$ref, n_trials_note = "같은 판본 기준 재측정 — 시행 수 무가산(research-program SKILL §2)"))
  sp0 <- rx_compile_spec(b, list(), code = code0, label = sprintf("%s × 기준 재측정(%s · %s 사양 그대로)", eid, e$base_weighting, e$ref),
                         idea = sprintf("[P3R03 RX0 · %s] 같은 배치 기준 재측정 — %s 사양 그대로 · 반증 · 선택 기준 · 시행 수 무가산 · 카탈로그 미등재", eid, e$ref),
                         selection_accounting = SA0, epoch = EP, root = ROOT)
  f0 <- file.path(P$specs_dir, paste0(code0, ".json"))
  writeLines(toJSON(sp0, auto_unbox = TRUE, pretty = TRUE, null = "null"), f0, useBytes = TRUE)
  cells[[code0]] <- list(code = code0, engine = eid, component = "RX0", path = rel(f0), md5 = rk_md5(f0), n_family = NA, reference = TRUE, remeasure_of = e$ref)
}
if (length(bad)) stop("[P3R03] 검증 실패:\n", paste(bad, collapse = "\n"))
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json"); file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = TRUE)
TD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
GV <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
BC <- fromJSON(BCP, simplifyVector = FALSE)
ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, status = "draft", draft_version = 3L,
  drafted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  judgments = list(round_selection = "J-20261016-001", candidates = "J-20261016-002", priority = "J-20261016-003",
                   ledger = "06_Registry/q_judgment_ledger.json", superfan_philosophy_p1 = "R-20261016-001(04_Research/programs/_supervision/superfan/philosophy/20261016_2100_P1_P3R03.md)"),
  exposures = list(
    list(what = "1차 라운드(P0R01 · P1R01 · P2R02 · P3R01 · P3R02) 종료 보고 — 보는 창 · 시험 창 지표 · 시각 보고(증분 알파 보는 창 · 시험 창)",
         when = "2026-10-15", who = "Q(세션)"),
    list(assessment = paste0("Q 는 시험 창 수치를 본 상태다(τ_D 노출). 그래서 선택 · 판정 규칙은 보는 창(≤ 2022-12-31) 지표로만 쓰고 시험 창은 사람 쪽 보고 전용이다. ",
                             "후보 5종은 원리 범위(계층 배분 · 군집 최적화 · 재표집 · 꼬리 LP · 위험 기여)와 카탈로그 원문 불일치(측정 신뢰 결함)로 골랐고, 시험 창 성과로 고르지 않았다. ",
                             "철학 Superfan P1 은 보는 창 산출만 읽었다(리뷰 파일 머리 선언)."))),
  purpose = paste0("구성(비중)만 원문대로 구현한 고도화 방법 5종으로 바꿨을 때 같은 엔진 · 같은 배치 기준(RX0)보다 보는 창에서 급락기 낙폭(깊은 위기 · 복리 경로)이 줄고 ",
                   "강세 참여 · 사이클 복리 · 증분 알파(엔진 강점)는 지키는가 — 등록부 P3_CONSTRUCTION · 병목 = 급락기 MDD(자율 판단 체계 §7)"),
  conclusion_scope = paste0("구성(비중)만 바꾼 효과다 — 같은 엔진 · 같은 선정 집합 · 롱온리 Σw = 1 · 비중 상한 없음 · 추정 창 252일 · 원문 충실 어댑터 판. ",
                            "'급락기 방어'는 깊은 위기 항목과 복리 경로 비악화를 통과했을 때만 쓰고, 중앙값만 움직였으면 '완만한 약세 · 여진 방어'로 쓴다. ",
                            "방어는 귀속(선택 · 크기 · β 노출)과 함께만 적고, β 짝 기준을 넘지 못하면 '노출(β) 방어'다. 엔진 강점은 상승 포착 비 · 사이클 복리 · 증분 알파로 적는다. ",
                            "결론은 방법 일반이 아니라 이 축 · 이 선정 집합에서의 원문 구현에 대한 것이다(철학 Superfan C-20261016-009 문장). ",
                            "E3 의 기준 구성은 EW 가 아니라 엔진 자체의 엔트로피 비중(lean:entropy)이다 — E3 의 '기준 대비'는 '엔트로피 비중 대비'다. ",
                            "사이클 복리(c)는 GFC(2007-10 · 2008-05 · 2008-11 위기)와 코로나(2020-01)를 포함하지 않는다 — 보는 창 원 산출에서 직전 위기 바닥 이후 · 고점 이전 강세와 ",
                            "짝지어지는 위기는 2011-05 · 2017-11 · 2021-06 셋이다(벤치 연대기 · 리허설 확인). 깊은 첫 급락의 방어는 (d) · (e) 가 잰다."),
  candidates = list(
    selected = lapply(names(VAR), function(k) list(code = k, catalog_id = unname(CATS[k]), principle = switch(k, HRP = "계층적 위험 배분", NCO = "군집 최적화 + 잡음 제거",
                                                   MRE = "추정 오차 재표집", CVR = "꼬리 위험 LP", ERC = "위험 기여 균등(K1 역변동성의 공분산 일반형)"), basis = VAR[[k]]$basis)),
    excluded = list(
      list(item = "강건 최적화(robust MV)", reason = "최소분산 목적에선 공분산 불확실 집합의 최악 = 팽창 공분산 최소분산 → P3R01 K2 · P3R02 M5 와 원리 중복 · μ 불확실 집합은 기대수익 입력 필요(엔진 점수를 μ 로 쓰면 알파 사이징이 섞여 구성 단독 효과 판정 불가) · 반경 κ 에 KR 근거 없음"),
      list(item = "CDaR LP(qepm:CDaR_LP)", reason = "P3R01 K3 에서 시험(새로움)"),
      list(item = "lean:hrp · lean:nco · lean:resampled · lean:cvar · qepm:CVaR_LP · qepm:HRP · qepm:ERC", reason = "원문과 다른 근사 · 카탈로그 경로 EW 폴백(10-16 탐침) — 충실도 미달(이 라운드가 원문 어댑터로 대체)"),
      list(item = "HERC(Raffinot 2018)", reason = "원리 중복 — 계층 배분 대표는 HRP"),
      list(item = "CVaR β 0.99", reason = "252 시나리오 꼬리 2.5개 — 추정 불안정"),
      list(item = "엔진 E1(모멘텀 12-1)", reason = "P1R01 자격 탈락 · 보는 창 CAGR 음수 — 지킬 복리 엔진이 없다(철학 Superfan C-010 지지)"))),
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference = list(
    baseline = "같은 엔진 RX0(이 배치에서 P0R01_E?_C0 사양 그대로 재측정) — 반증 · 비열등 · 선택의 기준 · 시행 수 무가산 · 카탈로그 미등재(QVEST_RP_REGISTER=0)",
    e3_note = "E3(B6_36) 의 RX0 비중 = lean:entropy(엔진 정의) — 변형은 그 비중법을 원문 방법으로 바꾼다(순위 버퍼 · 신호 · 유니버스 그대로)"),
  variants = lapply(VAR, function(v) list(name = v$name, delta = v$delta, basis = v$basis, adapter = v$adapter)),
  adaptations = list(
    "HRP · Michaud · ERC 는 원문이 롱온리 · 합 1 — 사상 없음. NCO 원문 optPort(무제약 최소분산)는 롱온리 최소분산으로 사상(최적화기를 바꿔 끼우는 메타 알고리즘 · mu = None 판). CVaR LP 는 롱온리 · 합 1 · 기대수익 제약 없음(최소 CVaR 끝점).",
    "기대수익 입력 없음(5종 모두 최소위험 끝점) — 엔진 점수(ctx$mu)를 쓰지 않는다: 알파 사이징이 섞이면 구성 단독 효과를 판정할 수 없다.",
    paste0("추정 창 252 거래일(셀 사양 lookback 기본 · HRP 원문 260 · 다른 원문은 창을 정하지 않음) · 창 = Date < 신호일 · 그 창에 결측 없는 선정 종목만(이력 불완전 종목은 비중 · 보유에서 빠진다). ",
           "E2 의 기준(EW)은 선정 전부를 보유하므로 이력 탈락이 E2 에서만 선택 교락이 된다(꼬리표 규칙으로 센다). E3 의 기준(lean:entropy)도 같은 카탈로그 경로의 이력 필터를 거쳐 ",
           "변형과 같은 보유 집합에서 출발한다(rf_cell_engine 카탈로그 경로) — E3 에는 이력 교락이 없다. lean:entropy 는 EW 에 가깝다(P0R01_E3_C0 보유 261 리밸일 — 유효 종목 수 / 보유 수 중앙 0.96 · ",
           "리밸일별 종목 비중과 1/n 의 최대 차이 중앙 2.3%p · 전체 최대 2.6%p — v1 교차 점검 문구 '최대 0.25%p' 는 재측정과 다르다)."),
    "비중 상한 없음(고정 축 · 10-15 도훈 확정) — 최소분산 · LP 계열은 소수 종목 집중 가능(진단 줄 maxw · effn · 집중 손실 꼬리표).",
    "공분산 = ctx$Sigma(셀 엔진의 같은 창 표본 공분산) · NCO 의 잡음 제거는 방법의 일부.",
    "Michaud · NCO 의 난수 = 신호일 결정론 시드(전역 난수 보존 — 재현 · R2)."),
  cells = unname(cells),
  rules = list(
    tested = paste0("방법 × 엔진 판정은 다음을 모두 만족할 때만 — 아니면 미시험(반증 아님): ① 변형 · RX0 둘 다 평가됨(측정 ok ∧ 축 감사 ok) ② 실효 시작 status = ok ",
                    "③ 처치 전달률 = 방법 진단 줄의 고유 신호일 / 선정 신호일(엔진 커버리지 줄 n_try) ≥ delivery_min ④ 같은 선정 집합 — 방법 해를 낸 보는 창 신호일마다 그 뒤 첫 RX0 집행일의 ",
                    "변형 보유 ⊆ RX0 보유(위반 0 · 변형 집행 결측 ≤ (1 − delivery_min) × 대조 집행일) ⑤ 공통 창 사본 · 보는 창 패킷이 만들어짐 ⑥ 위기 짝 — 두 칸의 위기(벤치 정의)가 모두 짝지어짐(짝 없는 위기 0) ∧ ",
                    "(b) 의 짝 ≥ 2 ∧ (d) 의 깊은 위기 짝 ≥ 2 ⑦ 판정 입력(a~e · 사이클 복리 · 두 칸 Calmar · PORT_t · 알파 · 엔진 알파)이 모두 유한. ",
                    "측정 연기(워커 ok=FALSE · deferred)는 판정 전 같은 사양 재측정(rules.remeasure)."),
    remeasure = paste0("인프라 실패(측정 결과 ok ≠ true — 워커 연기 · 실패 · 산출 없음) 칸은 measure.sh 가 같은 사양으로 1회 기계 재측정한다(RX0 먼저 단독 → 방법 5칸). ",
                       "재측정 전에 그 칸의 옛 칸 평가 캐시(results/<code>/) · 지문을 지운다. 평가는 모든 칸에서 칸 평가 캐시의 산출물 경로 = 현 측정 결과의 산출물 경로를 단정한다(다르면 평가 중단)"),
    vintage_group = paste0("같은 엔진의 6칸(방법 5 + RX0)은 함께 잰다(measure.sh — E2 묶음 → E3 묶음 · RX0 먼저 단독 · 방법 5칸 3병렬) · 칸마다 측정 시작 · 종료 데이터 지문(fingerprint.sh equality — ",
                           "RAWDATA · 벤치 · 재무 원값 · 컨센서스 · 팩터 DB 월 스냅샷 · 팩터 레지스트리 · 빌드 해시 / DNN 캐시는 기록만) — 묶음 안 지문이 모두 같아야 판정 · ",
                           "다르면 measure.sh 가 배리어 대기 뒤 그 묶음을 1회 재측정 · 그래도 다르면 evaluate.R 이 평가 전체를 멈춘다(그 묶음 결과를 지우고 measure.sh 로 재측정한 뒤 다시 평가 — ",
                           "한 묶음만 판정하지 않는다). 평가 시점 지문을 함께 기록한다(측정 지문과 다르면 표기)"),
    common_window = paste0("변형과 RX0 의 실효 시작이 같으면 원 산출 · 다르면 공통 창 사본(P3R02 와 같은 절차 — 늦게 시작한 칸의 첫 기간수익일 · 4파일 절단 · NAV · 벤치 재기준)에 같은 계약을 적용. ",
                           "사본 · 패킷 생성이 실패하면 그 칸은 미시험(실패 의미 사전 고정 · 리허설 rehearse.R 로 두 경로 실행 확인)"),
    pins_at_evaluation = "evaluate.R 은 시작부(셀 평가 샤드 포함)에서 precheck.R 과 같은 함수(p3_pin_mismatches)로 사양 · 운영 경로 · 카탈로그 엔트리 · 패키지 · R 판 · 평가 경로를 전부 재대조한다 — 하나라도 다르면 평가하지 않는다",
    decisive = paste0("방법 × 엔진(보는 창 패킷): (a) 위기 누적 포착 중앙값 < RX0 ∧ ",
                      "(b) 위기별 과반 — 두 칸 모두의 위기(peak · trough 짝)에서 낙폭 포착(dd_capture)이 RX0 − crisis_improve_min 보다 낮은 위기 비율 > majority_share ∧ ",
                      "(c) 강세 참여 중앙값 ≥ uc_floor ∧ 사이클 복리 과반 — 위기를 고점 순으로 놓고 위기마다 '직전 위기 바닥 연월 이후(같은 달 포함) 시작해 이 위기 고점 연월까지(같은 달 포함) 끝난 ",
                      "강세 국면 중 마지막'과 짝짓고(강세 1개는 1번만 · 짝 없는 위기는 기록) 사이클 수익 (1+강세 st_cum)(1+위기 st_cum) − 1 이 RX0 이상인 사이클 비율 > majority_share · ",
                      "두 칸의 같은 (위기, 강세) 짝만 비교 · 짝 2 미만이면 미시험 ∧ ",
                      "(d) 깊은 위기 — 짝 위기 중 벤치 낙폭(bm_dd) 크기가 그 집합 중앙값 이상인 위기에서 (b) 와 같은 과반 ∧ ",
                      "(e) 복리 경로 비악화 — mdd_vs_bench ≤ RX0 ∧ CDaR ≤ RX0. (a)(b) 만 통과하고 (d) 또는 (e) 를 못 넘으면 '완만한 약세 · 여진 방어'(통과 아님)"),
    non_inferiority = paste0("(S) RX0 의 S_vis > 0 이면 S_vis(변형) ≥ S_vis(RX0) − tie_eps · 0 이면 Calmar 비교 ∧ ",
                             "(알파) 보는 창 증분 β-통제 알파(rk_pair_alpha — 변형 − RX0 월 차이 · 벤치 대비 · NW lag 3) t > alpha_t_floor ∧ 증분 ≥ −alpha_margin_frac × max(엔진 자체 보는 창 β-통제 알파(RX0 대 벤치), 0)"),
    beta_matched = paste0("β 짝 대조(철학 C-003) — k = 변형 β / RX0 β(보는 창 behavior.stats.beta) < 1 이면 RX0 기간수익 · NAV · 보유를 k 배 노출로 낮춘 사본(잔여 현금)에 같은 계약(dp_build)을 적용하고 ",
                          "변형이 그 사본보다 (a) 중앙값이 낮고 (d) 깊은 위기 과반(짝 ≥ 2)을 넘어야 '구성 방어' — 못 넘으면 '노출(β) 방어' 꼬리표(판정 탈락 아님 · 하락장 · 상승장 β 와 상승장 β 비 병기). ",
                          "k ≥ 1 이면 β 로 산 방어가 아니므로 대조 불필요. k 비유한 · 사본 · 패킷 실패 · 사본 판정 입력 NA 이면 꼬리표 'β 대조 미측정'(통과로 접지 않는다)"),
    concentration = paste0("집중 손실(철학 C-002) — 깊은 위기 중 한 종목 최악 기여(exposure.top_losers contrib)가 single_name_loss_floor 보다 나쁜 위기가 하나라도 있으면 '집중 손실' 꼬리표 → ",
                           "P4 구성 부품 후보에서 제외(두 엔진 통과여도). 손실 표가 없거나 깊은 위기 하나라도 표에 빠지면(위반이 없어도) '집중 손실 미측정' → 같은 제외(통과로 접지 않는다). ",
                           "유효 종목 수 · 최대 비중 · effn ≤ 4 신호일 수 · 위기별 1위 · 상위 3 합은 기록"),
    attribution = "MC8 귀속 라벨(보는 창) + β 대조(exposure.crises selection_sum 짝 과반) — 둘 다 '선택' 이어야 '기전(선택) 방어' · 아니면 꼬리표 '기전(선택) 방어 미확인'",
    selection = paste0("방법이 두 엔진 모두 pass(decisive ∧ S 비열등 ∧ 알파 비열등) ∧ 집중 손실 · 집중 손실 미측정 꼬리표 없음이면 P4 조립 구성 부품 후보 — 꼬리표: β 대조 미측정 · 노출(β) 방어 · ",
                       "기전(선택) 방어 미확인 · 선택 교락(이력 탈락) · 선택 교락 미측정(RX0 보유 판독 실패). ",
                       "여럿이면 두 엔진 평균 위기 누적 포착 개선 순. 한 엔진만이면 기록(후보 아님). P4 에서 고를 때 구성 변형 시행 수 22(P3R01 10 · P3R02 2 · P3R03 10)를 센다"),
    round_verdict = paste0("supported = 두 엔진 통과 ∧ 제외 아님인 방법 ≥ 1 · partial = 한 엔진 통과 또는 두 엔진 통과지만 집중 손실(미측정 포함) 제외 · falsified = 판정된 칸 중 통과 0 · ",
                           "untested = 판정된 칸 0 — 판정은 '판정(판정 칸/전체 칸)' 으로 적는다(예: falsified(판정 3/10))"),
    failure_semantics = paste0("사전 고정: 평가 상태 · 전달률 · 실효 시작 · 같은 선정 집합 · 공통 창 · 패킷 · 위기 짝 · 판정 입력 실패 = 그 칸 미시험(반증 아님) / ",
                               "그 밖의 예기치 않은 평가 오류 = 그 칸 미시험(오류 문구 기록 · 라운드 평가는 계속 — p3_eval_pair_safe) / β 사본 실패 = 'β 대조 미측정' / ",
                               "집중 손실 표 결손 = '집중 손실 미측정'(후보 제외) / 이력 탈락 판독 불가(RX0 보유 · 위기 집행 행 없음 · 탈락 몫 비유한) = '선택 교락 미측정' / ",
                               "핀 · 행동 카드 사본 · 지문 · 칸 평가 캐시 불일치 = 평가 중단"),
    test_window = "시험 창(2023-01~) 증분 알파 · 위기 포착은 사람 쪽 보고만(선택 · 판정 입력 아님)",
    record = paste0("판정 입력 아님: 커버리지 · 폴백 사유 · 진단 줄(effn 중앙 · maxw 최대 · effn ≤ 4 신호일) · 이력 탈락(위기 보유 평균 몫 > drop_tag_share 면 꼬리표) · ",
                    "위기별 회복 관측 · 롤링 36M 통과율 · 음수 해 수 · 크기 분위 기여(exposure.by_size_decile — 유동성 3분위는 미측정) · 상승 포착 비(변형/RX0) · 하락장 · 상승장 β · 상승장 β 비 · ",
                    "연 회전율 · 증분 알파 표준오차 · 여유/표준오차(알파 기준의 검정력 — 여유가 표준오차보다 작으면 사실상 점추정 부호 판정) · 사이클 짝 없는 위기 · 같은 선정 집합 대조 수 · ",
                    "평가 시점 데이터 지문 · 시험 창 증분 알파")),
  expectations = list(
    HRP = "위기 포착 소폭 ↓ · 상승 참여 거의 유지 · 집중 낮음(전 종목 양 비중) · β 소폭 ↓ — 깊은 첫 급락(2008 · 2020) 방어의 사전 확률 낮음(급락 때 상관 수렴 · 철학 Superfan C-008)",
    NCO = "위기 포착 ↓ · 상승 참여 ↓ 가능 · 집중 ↑(군집 내 · 간 최소분산) · β ↓(정적 β 축소 위험) — 깊은 위기 방어 사전 확률 낮음",
    MRE = "위기 포착 ↓ · 점추정 최소분산보다 덜 쏠림(원문 기전) · β ↓ — 깊은 위기 방어 사전 확률 낮음",
    CVR = "위기 포착 ↓ 가능 · 집중 ↑↑(LP 꼭짓점 해 · 소수 종목) · 집중 손실 꼬리표 위험 최대 · 상승 참여 ↓",
    ERC = "위기 포착 소폭 ↓ · 상승 참여 거의 유지 · 집중 낮음 · β 소폭 ↓(K1 역변동성과 같은 계열 — 1차에서 유일하게 경로 개선)",
    overall = "철학 Superfan C-008: 세 라운드째 같은 방어 형태(추정 위험으로 재가중) · 급락 때 상관 수렴 → 통과 사전 확률은 낮다. 반증이면 교훈을 남기고 P2(시변 노출 · 방어 엔진)로 간다"),
  final_selection_rule = list(calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw, w_calmar = GV$weights$calmar, w_port_t = GV$weights$port_t,
                              tie_eps = 0.02, tie_eps_role = "S 비열등 여유(P3R01 · P3R02 승계)", uc_floor = BC$uc_floor,
                              majority_share = BC$majority_share, majority_share_source = paste0("behavior_card_cfg_at_prereg.json majority_share — ", BC$majority_share_source %||% ""),
                              crisis_improve_min = 0.03, crisis_improve_min_evidence = "P2R01 R6 지속성 필터의 '기저 대비 0.03 이상 개선된 위기'(낙폭 포착 기준) 승계 — P3R02 의 1e-9 는 잡음도 개선으로 셌다(철학 Superfan C-005) · 결과 전 고정",
                              alpha_t_floor = -2, alpha_t_floor_evidence = "1차 라운드 시각 보고의 '알파 감소(t ≤ −2)' 분류와 같은 문턱 — 유의한 감소 없음",
                              alpha_margin_frac = 0.2, alpha_margin_frac_evidence = "처방 레인 evidence — 엔진 자체 보는 창 β-통제 알파의 20% 를 넘는 점 추정 감소는 '알파 손실'로 본다(엔진 강점의 상대 기준 · 헌장 빈칸 — 도훈 교정 필요 · 철학 Superfan C-004 ③) · 결과 전 고정",
                              single_name_loss_floor = -0.10, single_name_loss_floor_evidence = "처방 레인 evidence — EW 25종(4%) 종목이 위기 중 전액 손실이어도 −4% · 한 종목이 깊은 위기 하나에서 포트폴리오의 10% 넘게 잃으면 집중 손실(철학 Superfan C-002 · 2008 K2 −19.8% · M5 −21.5% vs RX0 −4.6% 관측) · 헌장 빈칸 '집중의 문턱' — 도훈 교정 필요 · 결과 전 고정",
                              delivery_min = 0.9, delivery_min_evidence = "P3R02 승계 — 선정 신호일의 10% 넘게 방법 해가 아니면(EW 폴백 · 이월) 그 칸은 혼합 시험",
                              drop_tag_share = 0.10, drop_tag_share_evidence = "P3R02 승계 — 위기 보유에서 기준 비중의 10% 넘게가 이력 탈락 종목이면 선택 교락 꼬리표"),
  axis_audit = "측정 뒤 04_holdings 실보유가 롱온리 · ≤ max_names · Σw ≤ 1 — 위반 칸 = 측정 무효(미시험)",
  behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP)),
  operational_pins = .ops_pins(),
  evaluation = list(files = .eval_pins(), note = paste0("판정 구현(evaluate.R) · 픽스처 · precheck · 측정 절차(measure.sh) · 데이터 지문 정의(fingerprint.sh)를 결과 전에 고정 — ",
                                                        "evaluate.R 은 시작부(샤드 포함)에서 이 md5 와 운영 핀 전체를 재대조한다")),
  rehearsal = .rehearsal(),
  tests = TESTS,
  precheck = paste0("측정 직전 precheck.R 가 evaluate.R 의 p3_pin_mismatches 로 사양 · 운영 경로 md5 · 카탈로그 엔트리 6종(방법 5 + lean:entropy) · quadprog · lpSolve · bbdetection · R 판 · ",
                    "평가 경로 md5 를 다시 대조 — 다르면 측정하지 않는다 · 데이터 지문(equality · record) 기록"),
  data_note = "데이터 갱신 전담 Superfan 진단(2026-10-16 · components/daily_refresh/20261016_2100_diagnosis.md): 퀀티 세션 무응답으로 consensus · investor_act(10-02~) · universe_support(08-28~)가 낡았다 — 측정 축 위생 표식은 2026-09-30 신호일부터 8월 말 값(시험 창 끝 · 보는 창 판정 무관). measure.sh 는 오늘 밤 갱신 뒤 같은 배치로 잰다",
  design_inputs = "원문 5편(어댑터 머리 주석 인용) · 측정 · 평가 계약 코드 · P3R02 사전등록 형식 · 판단 원장 J-20261016-001~003 · 철학 Superfan P1 리뷰(보는 창 산출만) — 시험 창 성과 미사용",
  budget = list(variants = N_ROUND, reference_remeasure = length(ENGINES), rounds = 1L),
  changes_after_superfan = list(
    ch("C-001 성공 기준 ≠ 병목", "decisive (d) 깊은 위기 과반 · (e) 복리 경로 비악화(mdd_vs_bench · CDaR) 추가 · '완만한 약세 · 여진 방어' 라벨", "중앙값은 깊은 첫 급락을 재지 않는다(P3R02 M5 — 중앙값 개선 · MDD · CDaR 악화)"),
    ch("C-002 집중", "집중 손실 꼬리표(깊은 위기 한 종목 기여 < −10% → P4 후보 제외) · 집중 기록 지표", "상한 없는 축에서 최소분산 · LP 계열이 소수 종목에 몰려 깊은 위기 단일 종목 손실"),
    ch("C-003 정적 β 축소", "β 짝 사본(RX0 를 β 비율 노출로) 대조 · 하락장 · 상승장 β 기록", "MC8 은 β 를 짝짓지 않는다"),
    ch("C-004 엔진 강점", "사이클 복리 과반 · 상승 포착 비 기록 · 알파 t 하한 −2 · 여유 20%(엔진 알파 비례) 고정", "DNN 엔진에선 상승 포착 0.55 가 걸리지 않는다"),
    ch("C-005 실질 문턱 · 다중 시도", "위기별 개선 문턱 0.03(P2R01) · 선택 = 두 엔진 통과 · P4 시행 수 22", "1e-9 문턱은 잡음도 개선으로 센다 · 10칸 중 1칸 통과는 약하다"),
    ch("C-006~C-009 기록 · 결론 범위", "회복 · 롤링 · 음수 해 · 크기 분위(유동성 미측정) 기록 · 사전 기대 정직 기술 · 결론 범위 = C-009 문장", "수용"),
    ch("불채택", "K1 비중과의 상관 기록(C-008)", "E3 에 K1 측정이 없어 엔진 간 비대칭 · 다음 라운드 기록 항목으로 이월")),
  changes_after_review = list(
    ch("필수 1 사이클 짝", "짝 = 직전 위기 바닥 이후 시작 · 이 위기 고점까지 끝난 강세 중 마지막 · 강세 1회 사용 · 짝 없는 위기 기록 · 짝 2 미만 미시험 · 결론 범위에 'GFC · 코로나 미포함' · 픽스처 11(실제 연대기 — 짝 3 · 코로나 짝 없음)",
       "구 구현은 '고점 이전에 끝난 강세 중 마지막'이라 2016-02~2017-10 강세가 2017-11 · 2020-01 두 위기에 쓰였고 2011-10~2014-07 강세 둘은 쓰이지 않았다(규칙 문장 '바로 앞'과 다름)"),
    ch("필수 2 재측정 뒤 옛 캐시", "measure.sh m() 가 측정 전에 results/<code>/ · 지문 · ok=false 잔재를 지운다 · evaluate.R 이 모든 칸에서 칸 평가 캐시 산출물 = 현 측정 산출물을 단정",
       "rk_eval_cell 은 eval.json 이 있으면 그대로 돌려줘, 묶음 재측정 뒤 지문은 같은데 판정은 옛 산출물로 내려지는 판본 혼입이 경고 없이 가능했다"),
    ch("필수 3 핀 밖 판정 경로", "운영 핀에 결과 계약 · 저장 · essence · advanced_weights(lean:entropy 운반) · tilt_attribution_config · rolling_grade(.R · .json) · factor_z_standard · grade_v3.json · 카탈로그 lean:entropy · bbdetection 판 추가 · evaluate.R 시작부(샤드 포함) 전체 재대조 · 커밋 확인 = 고정 대상 전부",
       "02~05 산출 · S 입력 · E3 기준 비중 · 노출 분해 · 강세 국면이 핀 밖이었고 평가 시점 재대조가 평가 4파일뿐이었다"),
    ch("필수 4 새 경로 무실행", "판정 1칸을 p3_eval_pair 로 묶어 본 실행과 리허설이 같은 함수를 쓴다 · rehearse.R(P3R02_E2_M5 vs RX0 — 원 창 · 자연 β / 강제 공통 창 · k 0.9) 통과 · 실패 의미 사전 고정(rules.failure_semantics)",
       "공통 창 사본 · β 짝 사본 + dp_build 경로가 실제 산출물에서 한 번도 돌지 않아, 측정 뒤 실패하면 고정된 evaluate.R 을 고치거나(R2 위반) 라운드가 멈출 수밖에 없었다"),
    ch("필수 5 NA 의 통과 접힘", "집중 손실 표 결손 · 깊은 위기 누락 = '집중 손실 미측정'(후보 제외) · k 비유한 · β 사본 실패 = 'β 대조 미측정' · 픽스처 12 · 뮤테이션 6/6",
       "미측정 집중 손실이 FALSE 로, 비유한 k 가 '대조 통과'로 접혔다"),
    ch("권고 1 시행 회계", "엔진 이름 → 계보(family_root 2002.06975) 기준 — E2 · E3 모두 238", "같은 계보인데 E3 만 226 으로 셌다"),
    ch("권고 2 · 3 · 11 측정 절차", "배리어 2시간 뒤에도 잡히면 측정 안 함(종료 4) · RX0 먼저 단독 · 인프라 실패 1회 기계 재측정 · 묶음 지문 불일치 시 배리어 대기 뒤 묶음 1회 재측정 · 센티널에 상태 · 종료 코드 · ok 칸 수",
       "배리어 결과를 파이프가 삼켰고, RX0 실패가 그 엔진 5칸을 모두 미시험으로 만들 수 있었고, 센티널이 실패를 구분하지 않았다"),
    ch("권고 4 · 5 · 7 판정 조건", "같은 선정 집합(변형 보유 ⊆ RX0 보유) · 위기 짝 없음 0 · (b)(d) 짝 ≥ 2 · 두 칸 Calmar · PORT_t 유한성을 미시험 조건에 추가", "검증 없는 전제 · 공통 창 퇴화 · NA 가 S = 0(반증)으로 접힘"),
    ch("권고 6 · 8 · 9 · 12 기록", "상승장 β 비 · 증분 알파 표준오차 · 여유/표준오차 · 데이터 지문 확대(재무 원값 · 컨센서스 · 팩터 DB 월 스냅샷 · 레지스트리 · 빌드 해시 / DNN 캐시는 기록만) · 평가 시점 지문 · 판정 칸 수 표기",
       "β 짝 k 의 순환성 · 알파 기준의 검정력 · 판본 비교 범위 · 판정 해석"),
    ch("권고 10 · 13", "커밋 확인 범위 = 고정 대상 전부 · adaptations 문구(E2 만 이력 교락 · lean:entropy ≈ EW 실측)", "수용"),
    ch("불채택 · 조정", "팩터 DB 폴더 전체 지문(권고 9 일부)", "ic_direction_cache_v1 · _asof 등 실행 중 쓰이는 캐시가 같은 판본에서도 지문을 가른다 — 월 스냅샷 · 레지스트리 · 빌드 해시로 좁혔다"),
    ## v3 = v2(pass) + v2 변경분 점검 권고 그대로(판정 의미 불변 — 오류 · 미측정을 미시험 · 꼬리표로 접는 방향만)
    ch("v2 점검 권고 1(중) 본 실행 루프 일괄 오류 처리", "판정 1칸을 p3_eval_pair_safe 로 부른다 — 이름 붙은 분기 밖 오류도 그 칸만 미시험(오류 문구) · rules.failure_semantics 에 명시 · 픽스처 17",
       "평가 전체가 멈추면 샤드가 이미 보는 창 지표를 찍은 뒤라 '고정 파일 수정(R2) 또는 라운드 정지' 경로가 남는다(E3 쌍 · 새 방법 5종 실제 로그는 리허설 밖)"),
    ch("v2 점검 권고 2(낮음) 묶음 지문 규칙 문장", "rules.vintage_group 를 코드에 맞춤 — 재측정 뒤에도 다르면 평가 전체 중단 · 그 묶음 재측정 뒤 다시 평가", "코드는 stop(전체) 인데 문장은 '그 묶음 판정 안 함'이었다(둘 다 fail-closed)"),
    ch("v2 점검 권고 3(낮음) 이력 탈락 꼬리표", "p3_history_drop_eval — 위기 집행 행 없음 · 탈락 몫 비유한 · 보유 판독 실패 = '선택 교락 미측정' · 픽스처 18", "조용히 FALSE(통과 쪽)로 접혔다"),
    ch("v2 점검 권고 4(낮음) 대조 위치", "행동 카드 설정 사본 md5 를 p3_pin_mismatches(precheck · 평가 시작)에 · --register 가 리허설 스크립트 md5 · 행동 카드 사본 md5 재대조", "등록 뒤 사본이 바뀌면 측정은 다 돌고 평가에서야 멈췄다"),
    ch("v2 점검 권고 5(낮음) measure.sh 완료 줄 세기", "grep -c … || true · 빈 값 0 — 일치 0건에서 '0' 두 줄이 되던 결함", "실해는 없었으나(완료 줄 64) 로그 교체 시 06:00 마감 경로로만 빠진다"),
    ch("v2 점검 선택 6 불채택", "측정 사슬의 핀 밖 파일(audit_bt_result · lookahead_detector · refresh_barrier.R · weight_method_registry · QT_to_xts · defensive_score)",
       "판정에 쓰는 02~05 CSV 를 건드리지 않는다(점검 추적 결과) — 바뀌어 측정이 깨지면 미시험 · 재측정으로 드러난다 · 측정 직전 핀이 늘수록 무관한 수정이 오늘 밤 측정을 막는다")))
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), DR, useBytes = TRUE)
cat(sprintf("[P3R03] 초안 v3 %s (md5 %s) · 칸 %d(처방 %d + 기준 %d) · 검사 %s · 시행 회계 E2 %d · E3 %d\n", DR, rk_md5(DR), length(cells), N_ROUND, length(ENGINES),
            paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "),
            ENGINES$E2$n_prior + N_ROUND, ENGINES$E3$n_prior + N_ROUND))
