## P3R02 고유모드 정제 공분산 최소분산 구성(k = 5 · p = 1 · 비중 상한 없음 — 고정 축) — 같은 엔진 · 같은 판본(배치)의 EW 보다
##   보는 창 위기 하락 포착이 낮아지고 강세 참여는 지키는가
##   재료 = 1810.08384 「Portfolio Construction Matters」(충실구현 산출 · P3 큐 engine:RP_20261014_204929_skipped_base) ·
##   결정 = decision_register SUPERVISION-1810-CORRECTIONS ③(도훈 A안 2026-10-15) · 방법 = 카탈로그 paper:EigenCleanMarkowitz
## 판 이력:
##   v1 초안 00:14(md5 baf0c9a1…) → 격리 교차 점검 ②(revise · 필수 R1~R6 · 권고 13) →
##   v2 초안 01:09(md5 e185de6d…) → 범위 좁힌 격리 재점검(register · 필수 0 · 권고 13) →
##   v3 등록 01:49(md5 9fba96b8 · 측정 전) → 도훈 축 결정(10-15 "고정축 비중상한 없음으로 진행하자") → v4(이 생성기 · 상한 없음 ·
##   changes_after_registration = v3→v4). v3 등록판은 prereg_superseded_v3_9fba96b8.json 으로 보존(측정 결과가 없을 때만 대체 — R2)
##   → v5 = 핀 전용 재핀(--repin · 2026-10-15 도훈 승인 "핀만 재핀 허용"): 성능 수정(결과 동일 · 커밋 4aea904da)으로 바뀐 운영 · 평가
##   경로 md5 와 검사 기록만 갱신 · 나머지 필드는 v4 와 기계 대조로 동일 · v4 는 prereg_superseded_v4_c8b680ec.json 으로 보존
##   검토판 원본 = prereg_draft_reviewed_baf0c9a1.json · prereg_draft_reviewed2_e185de6d.json(md5 고정 · 등록판에 연결)
## 실행:
##   Rscript register.R --draft      v3 초안(어댑터 검사 · 평가 픽스처를 실제로 돌려 통과 수를 싣는다 · 실패면 초안을 쓰지 않는다)
##   Rscript register.R --register   등록 — 검토판 2개 보존 · 사양 · 운영 · 평가 경로 md5 · quadprog · R 판 · 커밋 상태(git)를 확인한 뒤에만
##   Rscript register.R --repin      핀 전용 재핀(v4 → v5) — 사양 · 설정 사본 md5 불변 · 핀 파일 목록 불변 · 검사 통과 · 커밋 상태 확인 ·
##                                   허용 필드(핀 · 검사 · 판 · 기록) 밖이 v4 와 다르면 거부 · 쓴 파일을 다시 읽어 같은 대조
##   ★R2: 등록은 P3R01 평가(가장 가까운 비교군 K2 LW 최소분산 결과 포함)가 생기기 전에만 한다(파일 존재로 확인).
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
args <- commandArgs(trailingOnly = TRUE)
MODE <- if ("--register" %in% args) "register" else if ("--draft" %in% args) "draft" else if ("--repin" %in% args) "repin" else
  stop("usage: register.R --draft | --register | --repin")
PROGRAM <- "P3_CONSTRUCTION"; ROUND <- "P3R02_eigen_markowitz"
P <- rx_paths(PROGRAM, ROUND, ROOT); RD <- P$round_dir
PR <- file.path(P$prereg_dir, "prereg.json"); DR <- file.path(RD, "prereg_draft.json")
REVIEWED <- list(
  list(version = 1L, path = file.path(RD, "prereg_draft_reviewed_baf0c9a1.json"), md5 = "baf0c9a1286da062a69766202a8ac5df",
       review = "격리 교차 점검 ②(2026-10-15 00:48 완료 · 결과 · 평가 json · 로그 본문 미열람)", verdict = "revise",
       findings = "필수 R1~R6 · 권고 13 — 반영 · 불채택 사유 = changes_after_draft"),
  list(version = 2L, path = file.path(RD, "prereg_draft_reviewed2_e185de6d.json"), md5 = "e185de6d0534d186abbe06658374df3c",
       review = "범위 좁힌 격리 재점검(2026-10-15 · R1~R6 적용 확인 · 결과 미열람)", verdict = "register",
       findings = "필수 0 · 권고 13 — 반영 · 불채택 사유 = changes_after_review2"))
P3R01_DIR <- file.path(ROOT, "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map")
P3R01_EVAL <- file.path(P3R01_DIR, "results/evaluation.json")
P0R <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results")
P0R01_EVAL <- file.path(P0R, "evaluation.json")
rel <- function(p) sub(paste0("^", ROOT, "/"), "", p)
## 대체 등록(v3 → v4) — 측정 결과(칸 json)가 하나라도 있으면 사전등록을 바꾸지 않는다(R2). 대체 대상은 v3 등록판(md5 고정)만
SUPERSEDE <- list(md5 = "9fba96b82e8951435ef2417c9db87a43", copy = "prereg_superseded_v3_9fba96b8.json",
                  reason = "도훈 축 결정(2026-10-15 \"고정축 비중상한 없음으로 진행하자\") — 카탈로그 하네스 상한 0.20 · 빌트인 max_w 0.15 폐지 → 어댑터 · 서술 · 핀 갱신(측정 전)")
## 핀 전용 재핀(v4 → v5) — 대상은 v4 등록판(md5 고정)만 · 과학 필드는 손대지 않는다(아래 --repin 절)
REPIN_FROM <- list(md5 = "c8b680ec4ca59ecb4a25e64398df9b2b", copy = "prereg_superseded_v4_c8b680ec.json",
                   reason = "성능 수정(결과 동일 — 산출물 대조 · 회귀 테스트 · 커밋 4aea904da)으로 고정 운영 · 평가 경로 md5 가 바뀌어 precheck 가 측정을 막는다 — 핀만 갱신(도훈 2026-10-15 승인 \"핀만 재핀 허용\")")
.measured_any <- function() length(Sys.glob(file.path(RD, "results", "P3R02_*.json"))) > 0L
if (file.exists(PR) && .measured_any()) stop("[P3R02] 측정 결과가 생긴 뒤에는 사전등록을 바꿀 수 없다(R2)")
if (MODE != "repin") {
  if (file.exists(PR) && !identical(rk_md5(PR), SUPERSEDE$md5)) stop("[P3R02] 사전등록이 이미 있고 대체 대상(v3 9fba96b8)이 아니다(R2)")
  if (file.exists(P3R01_EVAL)) stop("[P3R02] P3R01 평가가 이미 있다 — 가장 가까운 비교군(K2 최소분산) 결과 뒤의 사전등록이 된다 · 등록하지 않는다")
}
for (rv in REVIEWED) if (!file.exists(rv$path) || !identical(rk_md5(rv$path), rv$md5))
  stop("[P3R02] 검토판 v", rv$version, " 보존본이 없거나 바뀌었다 — 검토판 ↔ 등록판 연결 불가")

## 비교군 · 기준의 칸 단위 파일 — 존재와 수정 시각만(내용은 열지 않는다 · 교차 점검 R6 ② · 재점검 권고 ⑨)
.meta <- function(paths) lapply(paths, function(p) list(path = rel(p), exists = file.exists(p),
  mtime = if (file.exists(p)) format(file.mtime(p), "%Y-%m-%dT%H:%M:%S%z") else NA_character_))
.result_files <- function() .meta(unique(c(P3R01_EVAL, Sys.glob(file.path(P3R01_DIR, "results", "P3R01_*.json")),
  Sys.glob(file.path(P3R01_DIR, "results", "P3R01_*.log")), Sys.glob(file.path(P3R01_DIR, "results", "P3R01_*", "eval.json")), P0R01_EVAL,
  file.path(P0R, c("P0R01_E1_C0.json", "P0R01_E2_C0.json", "P0R01_E1_C0.log", "P0R01_E2_C0.log")),
  file.path(P0R, c("P0R01_E1_C0", "P0R01_E2_C0"), "eval.json"),
  file.path(P0R, c("P0R01_E1_C0", "P0R01_E2_C0"), "visible", "diagnosis_packet.json"))))
## 측정 비중 · 판정을 실제로 정하는 운영 경로 — md5 고정 · 측정 직전 precheck.R 가 다시 대조(교차 점검 R6 ④ · 재점검 권고 ⑤)
OPS <- c("02_Infrastructure/methods/adapters/eigen_clean_markowitz.R", "02_Infrastructure/portfolio/weight_catalog.R",
         "02_Infrastructure/methods/method_registry.R", "02_Infrastructure/portfolio/strategy_tilt_weights.R",
         "02_Infrastructure/reinforcement/rf_cell_engine.R", "02_Infrastructure/reinforcement/rf_base_cache.R",
         "02_Infrastructure/reinforcement/rf_axes.R", "02_Infrastructure/reinforcement/rf_rebalance.R", "02_Infrastructure/reinforcement/rf_sleeve.R",
         "02_Infrastructure/ops/rf_cell_worker.R", "02_Infrastructure/alpha_search/run_paper_replication.R",
         "02_Infrastructure/replication/replication_harness.R", "02_Infrastructure/backtest_harness.R", "02_Infrastructure/config.R",
         "02_Infrastructure/contracts/measurement_axis.R", "02_Infrastructure/contracts/behavior_card.R",
         "02_Infrastructure/contracts/diagnosis_packet.R", "02_Infrastructure/contracts/matched_controls.R",
         "02_Infrastructure/contracts/grade_v3.R", "02_Infrastructure/contracts/tilt_attribution.R",
         "06_Registry/matched_controls.json", "02_Infrastructure/worktask/constraint_defaults.json",
         "04_Research/strategies/RP_AUTO_2002_06975/engine.R",   # E2 기저 엔진(무인 레인이 strategies/ 엔진을 고친 전례 — 고정)
         "04_Research/programs/_lib/round_kit.R", "04_Research/programs/_lib/measure_round_cell.R")
EVALF <- c("evaluate.R", "evaluate_fixture.R", "precheck.R", "measure.sh")   # 판정 구현 · 측정 절차 — 결과 전에 고정(재점검 권고 ①)
.ops_pins <- function() {
  wc <- fromJSON(file.path(ROOT, "06_Registry/weight_catalog.json"), simplifyVector = FALSE)$entries
  ent <- Filter(function(z) identical(z$catalog_id, "paper:EigenCleanMarkowitz"), wc)
  list(files = lapply(OPS, function(f) list(path = f, md5 = rk_md5(file.path(ROOT, f)))),
       catalog_entry = if (length(ent)) list(catalog_id = ent[[1]]$catalog_id, status = ent[[1]]$status, resolver = ent[[1]]$resolver) else NULL,
       quadprog = as.character(utils::packageVersion("quadprog")), r_version = R.version.string)
}
.eval_pins <- function() lapply(EVALF, function(f) { p <- file.path(RD, f); list(path = rel(p), md5 = rk_md5(p)) })
## 커밋 상태 — 어댑터 · 검사 · 라운드 폴더 · 방법 등록부 · 비중 카탈로그가 커밋돼 있어야 등록한다(기록된 HEAD 로 원문 복원 가능 · 재점검 권고 ⑥)
COMMIT_PATHS <- c("02_Infrastructure/methods/adapters/eigen_clean_markowitz.R", "08_Tests/methods/test_eigen_clean_markowitz.R",
                  rel(RD), "06_Registry/method_registry.json", "06_Registry/weight_catalog.json",
                  "04_Research/programs/P3_CONSTRUCTION/P3R01_construction_map/evaluate.R")
.uncommitted <- function() { s <- system2("git", c("-C", ROOT, "status", "--porcelain", "--", COMMIT_PATHS), stdout = TRUE)
  s[nzchar(s)] }
## 검사 실행 — 요약 JSON 줄(pass · fail)을 그대로 싣는다
.run_test <- function(path) {
  o <- suppressWarnings(system2("Rscript", shQuote(path), stdout = TRUE, stderr = TRUE))
  j <- grep('^\\{"test"', o, value = TRUE); tot <- grep("^합계: 통과 [0-9]+ · 실패 [0-9]+", o, value = TRUE)
  if (length(j)) { r <- fromJSON(j[length(j)]); return(list(path = rel(path), md5 = rk_md5(path), pass = r$pass, fail = r$fail)) }
  if (length(tot)) { n <- as.integer(regmatches(tot[length(tot)], gregexpr("[0-9]+", tot[length(tot)]))[[1]])
                     return(list(path = rel(path), md5 = rk_md5(path), pass = n[1], fail = n[2])) }
  list(path = rel(path), md5 = rk_md5(path), pass = NA, fail = NA)
}

## ── 핀 전용 재핀(v4 → v5 · 2026-10-15 도훈 승인 "핀만 재핀 허용") ─────────────────────────────────────────────
##   등록된 v4 를 그대로 읽어 operational_pins$files · evaluation$files · tests 만 다시 재고 판(draft_version) · 기록 필드를 더한다.
##   나머지 필드(가설 · 셀 · 사양 md5 · 규칙 · 문턱 · 선택 규칙 · 설정 사본 · 노출 · 검토판 연결)는 v4 와 identical 이어야 하며,
##   쓴 파일을 다시 읽어 같은 대조를 한 번 더 한다(직렬화 왕복). P3R01 종합 판정은 파이프라인 v2 순서 실수(Q)로 이미 있다 —
##   내용은 열지 않고 존재 · 수정 시각만 기록한다.
if (MODE == "repin") {
  if (!file.exists(PR) || !identical(rk_md5(PR), REPIN_FROM$md5)) stop("[P3R02] 재핀 대상(v4 ", REPIN_FROM$md5, ")이 아니다")
  v4 <- fromJSON(PR, simplifyVector = FALSE)
  if (!identical(v4$status, "registered") || !identical(as.integer(v4$draft_version), 4L)) stop("[P3R02] v4 등록판이 아니다")
  for (c in v4$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P3R02] 사양 md5 ≠ v4 — 사양이 바뀌면 핀 전용 재핀이 아니다: ", c$code)
  if (!identical(rk_md5(file.path(ROOT, v4$behavior_card_cfg$path)), v4$behavior_card_cfg$md5)) stop("[P3R02] 행동 카드 설정 사본 md5 ≠ v4")
  TESTS <- list(.run_test(file.path(ROOT, "08_Tests/methods/test_eigen_clean_markowitz.R")), .run_test(file.path(RD, "evaluate_fixture.R")))
  for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P3R02] 검사 실패 — 재핀하지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")
  now <- .ops_pins(); ev <- .eval_pins()
  paths <- function(x) vapply(x, function(z) z$path, character(1))
  if (!identical(paths(now$files), paths(v4$operational_pins$files))) stop("[P3R02] 운영 핀 파일 목록 ≠ v4")
  if (!identical(paths(ev), paths(v4$evaluation$files))) stop("[P3R02] 평가 핀 파일 목록 ≠ v4")
  if (!identical(now$catalog_entry, v4$operational_pins$catalog_entry) || !identical(now$quadprog, v4$operational_pins$quadprog) ||
      !identical(now$r_version, v4$operational_pins$r_version)) stop("[P3R02] 카탈로그 엔트리 · quadprog · R 판 ≠ v4 — 핀 전용 재핀이 아니다")
  unc <- .uncommitted()
  if (length(unc)) stop("[P3R02] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 재핀:\n", paste(unc, collapse = "\n"))
  changed <- function(old, new) unname(Filter(Negate(is.null), Map(function(o, n) if (!identical(o$md5, n$md5))
    list(path = o$path, md5_v4 = o$md5, md5_v5 = n$md5) else NULL, old, new)))
  ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
  v5 <- v4
  v5$draft_version <- 5L
  v5$operational_pins$files <- now$files
  v5$evaluation$files <- ev
  v5$tests <- TESTS
  v5$changes_after_registration <- c(v4$changes_after_registration, list(
    ch("v4 → v5 핀 전용 재핀(도훈 2026-10-15 승인)", "operational_pins.files · evaluation.files md5 와 tests 기록만 갱신 — 가설 · 셀 · 사양 · 규칙 · 문턱 · 선택 규칙 · 설정 사본 불변(기계 대조)",
       REPIN_FROM$reason)))
  v5$repin <- list(kind = "pin_only", from_md5 = REPIN_FROM$md5, approved = "도훈 2026-10-15 세션 승인 — \"핀만 재핀 허용\"",
    changed_operational = changed(v4$operational_pins$files, now$files), changed_evaluation = changed(v4$evaluation$files, ev),
    verification = "성능 수정 결과 동일 — P0R01_E2_C4 재측정 산출 18종 identical(02~09 CSV · analysis_*.csv · 권위 기록 · 분석 보고서) · test_fdc_read_fastpath 13/0 · matched_controls 67/0 · replication_harness 46/0 · round_kit_shard 17/0 · program_registry 29/0(CHANGELOG 2026-10-15 1계층 실행 속도 절)",
    p3r01_evaluation = list(path = rel(P3R01_EVAL), exists = file.exists(P3R01_EVAL),
                            mtime = if (file.exists(P3R01_EVAL)) format(file.mtime(P3R01_EVAL), "%Y-%m-%dT%H:%M:%S%z") else NA_character_, opened = FALSE,
                            declaration = "파이프라인 v2 순서 실수(Q)로 재핀 전에 생겼다 — 내용은 열지 않았다 · 이 재핀은 과학 필드를 바꾸지 않는다(기계 대조)"),
    result_files = .result_files(), at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  v5$supersede_history <- c(v4$supersede_history %||% list(), if (!is.null(v4$supersedes)) list(v4$supersedes) else list())
  v5$supersedes <- list(md5 = REPIN_FROM$md5, path = rel(file.path(P$prereg_dir, REPIN_FROM$copy)), reason = REPIN_FROM$reason,
                        measured_before = FALSE, declaration = "대체 시점에 이 라운드의 측정 결과는 없었다(.measured_any = FALSE)")
  v5$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  v5$git_head_at_register <- tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_)
  ## 기계 대조 — 허용 필드 밖 identical · 허용 필드 안에서도 핀 목록 밖 · v4 기록 접두는 보존
  ALLOWED <- c("draft_version", "operational_pins", "evaluation", "tests", "changes_after_registration", "repin", "supersedes",
               "supersede_history", "registered_at", "git_head_at_register")
  .same_sci <- function(a, b) {
    identical(a[setdiff(names(a), ALLOWED)], b[setdiff(names(b), ALLOWED)]) &&
      identical(a$operational_pins[setdiff(names(a$operational_pins), "files")], b$operational_pins[setdiff(names(b$operational_pins), "files")]) &&
      identical(a$evaluation[setdiff(names(a$evaluation), "files")], b$evaluation[setdiff(names(b$evaluation), "files")]) &&
      identical(b$changes_after_registration[seq_along(a$changes_after_registration)], a$changes_after_registration)
  }
  if (!.same_sci(v4, v5)) stop("[P3R02] 핀 전용 재핀 위반 — 허용 필드 밖이 v4 와 다르다")
  for (d in c(P$prereg_dir, RD)) if (!file.exists(file.path(d, REPIN_FROM$copy))) file.copy(PR, file.path(d, REPIN_FROM$copy))
  if (!identical(rk_md5(file.path(P$prereg_dir, REPIN_FROM$copy)), REPIN_FROM$md5)) stop("[P3R02] v4 보존본 md5 불일치")
  tmp <- paste0(PR, ".v5tmp")
  writeLines(toJSON(v5, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), tmp, useBytes = TRUE)
  if (!.same_sci(fromJSON(file.path(P$prereg_dir, REPIN_FROM$copy), simplifyVector = FALSE), fromJSON(tmp, simplifyVector = FALSE))) {
    unlink(tmp); stop("[P3R02] 직렬화 왕복 뒤 과학 필드가 v4 와 다르다 — 재핀하지 않는다")
  }
  if (!file.rename(tmp, PR)) stop("[P3R02] 등록판 교체 실패")
  file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                n_variants = length(Filter(function(z) !isTRUE(z$reference), v5$cells)),
                                variants = unname(vapply(v5$cells, function(z) z$code, character(1))),
                                supersedes = list(md5 = REPIN_FROM$md5, reason = REPIN_FROM$reason)), root = ROOT)
  cat(sprintf("[P3R02] 핀 전용 재핀 v5 %s (md5 %s) · 운영 핀 변경 %d · 평가 핀 변경 %d · 검사 %s · HEAD %s\n", PR, rk_md5(PR),
              length(v5$repin$changed_operational), length(v5$repin$changed_evaluation),
              paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "), v5$git_head_at_register))
  quit(status = 0)
}

if (MODE == "register") {
  if (!file.exists(DR)) stop("[P3R02] 초안이 없다 — --draft 먼저")
  pre <- fromJSON(DR, simplifyVector = FALSE)
  if (!identical(as.integer(pre$draft_version), 4L)) stop("[P3R02] 초안 판 ≠ 4")
  if (!identical(vapply(pre$reviewed_drafts, function(z) z$md5, ""), vapply(REVIEWED, function(z) z$md5, ""))) stop("[P3R02] 초안이 검토판 2개에 연결되지 않았다")
  if (!length(pre$changes_after_draft) || !length(pre$changes_after_review2) || !length(pre$changes_after_registration))
    stop("[P3R02] 반영 기록(changes_after_draft · changes_after_review2 · changes_after_registration)이 비었다")
  for (c in pre$cells) if (!identical(rk_md5(file.path(ROOT, c$path)), c$md5)) stop("[P3R02] 사양 md5 ≠ 초안: ", c$code)
  now <- .ops_pins()
  for (f in pre$operational_pins$files) {
    m <- Filter(function(z) identical(z$path, f$path), now$files)[[1]]$md5
    if (!identical(m, f$md5)) stop("[P3R02] 운영 경로 md5 ≠ 초안(초안 뒤 구현이 바뀌었다): ", f$path)
  }
  if (!identical(now$quadprog, pre$operational_pins$quadprog) || !identical(now$r_version, pre$operational_pins$r_version)) stop("[P3R02] quadprog · R 판 ≠ 초안")
  for (f in pre$evaluation$files) if (!identical(rk_md5(file.path(ROOT, f$path)), f$md5)) stop("[P3R02] 평가 경로 md5 ≠ 초안: ", f$path)
  for (t in pre$tests) if (!identical(rk_md5(file.path(ROOT, t$path)), t$md5) || !identical(as.integer(t$fail), 0L)) stop("[P3R02] 검사 파일 변경 또는 실패: ", t$path)
  unc <- .uncommitted()
  if (length(unc)) stop("[P3R02] 커밋되지 않은 고정 대상이 있다 — 커밋 뒤 등록:\n", paste(unc, collapse = "\n"))
  pre$status <- "registered"; pre$registered_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  pre$draft_md5 <- rk_md5(DR)
  pre$registered_before <- list(result_files = .result_files(), declaration = "칸 단위 결과 파일은 존재 · 수정 시각만 확인했고 내용은 열지 않았다")
  pre$git_head_at_register <- tryCatch(system2("git", c("-C", ROOT, "rev-parse", "HEAD"), stdout = TRUE), error = function(e) NA_character_)
  if (file.exists(PR)) {   # v3 등록판 보존(같은 이름 두 곳) — 대체 사실을 등록판에 싣는다
    for (d in c(P$prereg_dir, RD)) file.copy(PR, file.path(d, SUPERSEDE$copy), overwrite = FALSE)
    pre$supersedes <- list(md5 = SUPERSEDE$md5, path = rel(file.path(P$prereg_dir, SUPERSEDE$copy)), reason = SUPERSEDE$reason,
                           measured_before = FALSE, declaration = "대체 시점에 이 라운드의 측정 결과는 없었다(.measured_any = FALSE)")
  }
  dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
  file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
  pr_record_round(PROGRAM, list(round_id = ROUND, prereg = rel(PR), prereg_md5 = rk_md5(PR), status = "registered",
                                n_variants = length(Filter(function(z) !isTRUE(z$reference), pre$cells)),
                                variants = unname(vapply(pre$cells, function(z) z$code, character(1)))), root = ROOT)
  cat(sprintf("[P3R02] 사전등록 %s (md5 %s) · 칸 %d(기준 재측정 포함) · HEAD %s\n", PR, rk_md5(PR), length(pre$cells), pre$git_head_at_register))
  quit(status = 0)
}

## ── 초안 v3 ────────────────────────────────────────────────────────────────
TESTS <- list(.run_test(file.path(ROOT, "08_Tests/methods/test_eigen_clean_markowitz.R")), .run_test(file.path(RD, "evaluate_fixture.R")))
for (t in TESTS) if (!identical(as.integer(t$fail), 0L) || !is.finite(as.numeric(t$pass))) stop("[P3R02] 검사 실패 — 초안을 쓰지 않는다: ", t$path, " (", t$pass, "/", t$fail, ")")
EP <- ma_epoch(root = ROOT)
P3PR <- fromJSON(file.path(ROOT, "stage_artifacts/programs/P3_CONSTRUCTION/P3R01_construction_map/prereg.json"), simplifyVector = FALSE)
P0SP <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs")
nf_prior <- function(eng) max(vapply(Filter(function(z) identical(z$engine, eng), P3PR$cells), function(z) as.integer(z$n_family), integer(1)))
ENGINES <- list(E1 = list(ref = "P0R01_E1_C0", n_prior = nf_prior("E1")), E2 = list(ref = "P0R01_E2_C0", n_prior = nf_prior("E2")))
AD <- "02_Infrastructure/methods/adapters/eigen_clean_markowitz.R"
VAR <- list(M5 = list(
  name = "고유모드 정제 공분산 최소분산(k = 5 · p = 1 · 상한 없음)",
  delta = list(weighting = list(kind = "catalog", catalog_id = "paper:EigenCleanMarkowitz", label = "EigenCleanMarkowitz")),
  basis = paste0("arXiv 1810.08384 Portfolio Construction Matters(2018) §II 식 (4) · §III(k = 5 최고 SR) — 원문 대조 = 감독 기록 교차 점검 ① · ",
                 "k = 5 는 1000종 풀(모드 비율 0.5%)의 결과 — 25종 상관행렬(T = 252)에선 상위 5 모드 = 스펙트럼 20% · 잡음 상한 (1+√(25/252))² ≈ 1.73 근처 모드가 섞일 수 있다(풀 크기가 달라 k 의 의미가 다르다 · 스윕 없음)"),
  adapter = list(path = AD, md5 = rk_md5(file.path(ROOT, AD)))))
N_ROUND <- length(ENGINES) * length(VAR)              # 처방 변형만 센다 — 기준 재측정(RX0)은 시행 수 무가산(SKILL §2)
cells <- list(); bad <- character(0)
for (eid in names(ENGINES)) {
  e <- ENGINES[[eid]]
  b <- fromJSON(file.path(P0SP, paste0(e$ref, ".json")), simplifyVector = FALSE)   # P0R01 기준 칸 사양(측정 축 표식 포함)
  nf <- as.integer(e$n_prior + N_ROUND)
  SA <- list(selection_type = "sweep", family_root = b$selection_accounting$family_root,
             lineage = c(paste0("RX_", ROUND), "RX_P3R01_construction_map", unlist(b$selection_accounting$lineage)),
             n_family_at_registration = nf,
             n_trials_basis = sprintf("P3R02: P3R01 회계 %d + 이 라운드 %d(엔진 %d × 구성 %d) · 기준 재측정 RX0 무가산", as.integer(e$n_prior), N_ROUND, length(ENGINES), length(VAR)))
  for (k in names(VAR)) {
    d <- VAR[[k]]$delta; code <- sprintf("P3R02_%s_%s", eid, k)
    v <- rx_validate(d, ROOT); if (!isTRUE(v$ok)) { bad <- c(bad, sprintf("%s: %s", code, paste(v$errors, collapse = " | "))); next }
    sp <- rx_compile_spec(b, d, code = code, label = sprintf("%s × %s", eid, VAR[[k]]$name),
                          idea = sprintf("[P3R02 정제 공분산 최소분산 · %s × %s] %s", eid, k, VAR[[k]]$basis),
                          selection_accounting = SA, epoch = EP, root = ROOT)
    f <- file.path(P$specs_dir, paste0(code, ".json"))
    dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
    writeLines(toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
    cells[[code]] <- list(code = code, engine = eid, component = k, path = rel(f), md5 = rk_md5(f), n_family = nf, reference = FALSE)
  }
  ## RX0 — 같은 배치 기준 재측정(교차 점검 R4 · SKILL §2): P0R01 기준 칸 사양 그대로(코드 · 표지 · 회계 메모만 다름)
  code0 <- sprintf("P3R02_%s_RX0", eid)
  SA0 <- c(b$selection_accounting, list(remeasure_of = e$ref, n_trials_note = "같은 판본 기준 재측정 — 시행 수 무가산(research-program SKILL §2)"))
  sp0 <- rx_compile_spec(b, list(), code = code0, label = sprintf("%s × 기준 재측정(EW · %s 사양 그대로)", eid, e$ref),
                         idea = sprintf("[P3R02 RX0 · %s] 같은 배치 기준 재측정 — %s 사양 그대로 · 반증 · 선택 기준 · 시행 수 무가산 · 카탈로그 미등재", eid, e$ref),
                         selection_accounting = SA0, epoch = EP, root = ROOT)
  f0 <- file.path(P$specs_dir, paste0(code0, ".json"))
  writeLines(toJSON(sp0, auto_unbox = TRUE, pretty = TRUE, null = "null"), f0, useBytes = TRUE)
  cells[[code0]] <- list(code = code0, engine = eid, component = "RX0", path = rel(f0), md5 = rk_md5(f0), n_family = NA, reference = TRUE,
                         remeasure_of = e$ref)
}
if (length(bad)) stop("[P3R02] 검증 실패:\n", paste(bad, collapse = "\n"))
BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json"); file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = TRUE)
TD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
GV <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)
BC <- fromJSON(BCP, simplifyVector = FALSE)
mce <- new.env(); sys.source(file.path(ROOT, "02_Infrastructure/contracts/matched_controls.R"), envir = mce)
MC_TOL <- get(".MC_TOL", envir = mce)

ch <- function(item, change, reason) list(item = item, change = change, reason = reason)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, status = "draft", draft_version = 4L,
  drafted_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  reviewed_drafts = lapply(REVIEWED, function(rv) list(version = rv$version, path = rel(rv$path), md5 = rv$md5, review = rv$review,
                                                        verdict = rv$verdict, findings = rv$findings)),
  drafted_before = list(result_files = .result_files(), declaration = "칸 단위 결과 파일은 존재 · 수정 시각만 확인했고 내용은 열지 않았다"),
  exposures = list(
    list(when = "2026-10-14(시각 미기록 · P0 A안 결정 전)", what = "측정 로그(module_register)에서 P3R01 E1 칸의 등급 기록 줄",
         source = "04_Research/programs/_supervision/1810_08384_loop_supervision.md '(관련 결정) P0 = A안' 절 — 칸 코드 · 등급 값은 기록에 없다"),
    list(when = "2026-10-14 22:28", what = "진행 중 라운드 칸의 module_registered 1줄(등급 B · stage_artifacts/replication/20261014_221229_34676)",
         source = "같은 감독 기록 '노출 기록' 절 — 그 시각 측정 중이던 라운드 = P0R01(밤 파이프라인 19:40~) · 칸 미식별"),
    list(assessment = paste0("둘 다 등급 1글자 · 칸(변형) 미식별 — 이 라운드의 판정 지표(위기 누적 포착 · 강세 참여 · CDaR)를 담지 않는다. ",
                             "변형(M5 · k = 5 · p = 1)은 논문과 도훈 A안 결정이 정했고 규칙은 P3R01 · P2R02 사전등록 형식과 교차 점검 · 재점검 지적에서 왔다 — 노출은 설계 입력이 아니다"))),
  purpose = "구성(비중)만 '고유모드 정제 공분산 최소분산(상한 없음 · p = 1)'으로 바꿨을 때 같은 엔진 · 같은 배치 EW(RX0)보다 보는 창 위기 하락 포착이 낮아지고 강세 참여는 지키는가 — 등록부 P3_CONSTRUCTION",
  conclusion_scope = paste0("p = 1 ⇒ 해 = Σ̃ 의 롱온리 최소분산(KKT 동치 · 비중 상한 없음 — 소수 종목 집중 가능). 결론 범위 = '고유모드 정제 공분산 최소분산 구성'이다 — ",
                            "'논문 구성법(롱숏 · 통계 요인 중립 마코위츠)이 KR 롱온리에서 통한다/안 통한다'가 아니다(롱온리 · p = 1 에선 시장 모드 중립화가 작동하지 않고 선택 집합 안 위험 분산만 남는다). ",
                            "위기 포착 개선은 저베타 · 노출 효과일 공산이 크다 — MC8 귀속 라벨과 β 대조(선택 기여 짝 과반)로 가른다. 가장 가까운 비교군 = P3R01 K2(LW 최소분산 · 같은 엔진)"),
  source_material = list(paper_key = "1810.08384", queue_key = "engine:RP_20261014_204929_skipped_base",
                         decision = "SUPERVISION-1810-CORRECTIONS ③",
                         why_not_faithful_grade = "충실구현 등급 F 는 이 구성법의 판정이 아니다 — 롱숏 시장중립을 KOSPI200 대비로 쟀고(PORT_t 구조적 음수) · 일간→주간 · 15bps 가 섞였다. 이 라운드는 기전(구성법)만 우리 축에서 잰다"),
  measurement_axis = list(epoch = EP$id), tau_d = "2022-12-31",
  reference = list(
    baseline = "같은 엔진 RX0(이 라운드 배치에서 P0R01_E?_C0 사양 그대로 재측정) — 반증 · 비열등 · 선택의 기준(교차 점검 R4 · SKILL §2: 판본이 바뀌었으면 기준을 같은 사양으로 다시 잰다 · 시행 수 무가산)",
    rx0_catalog = "RX0 는 카탈로그 미등재(QVEST_RP_REGISTER=0 — P0R01 C0 와 같은 모듈의 중복 등재 방지 · 측정 산출 무관)",
    vintage_record = "RX0 대 P0R01 C0(원 측정) 보는 창 지표 차와 데이터 지문(칸별 측정 시작 · 종료 RAWDATA · 벤치 캐시 크기 · mtime)을 기록한다(판정 입력 아님)"),
  variants = lapply(VAR, function(v) list(name = v$name, delta = v$delta, basis = v$basis, adapter = v$adapter)),
  adaptations = list(
    "예측자 p = 1(상수) — 논문 p 는 전 종목 순위 [-1, +1] · 엔진이 고른 ≤25종의 그 값은 [1 − 48/(N−1), 1](N = 그날 후보 폭 · N = 1000 이면 상대 차 ≤ 4.8% · 초기 연도처럼 N 이 작으면 더 크다). 해는 p 의 척도에 불변이라 p = 1 은 원문 사상의 근사다(원문 그대로 = ctx$mu 패널 rank-Z) — p = 1 ⇒ Σ̃ 의 롱온리 최소분산(KKT 동치)",
    "롱온리 · 비중 상한 없음(고정 축 — 2026-10-15 도훈 확정 · 카탈로그 하네스 WC_UB = 1 · 빌트인 max_w = 축 값): argmin_{x≥0} ½xᵀΣ̃x − pᵀx(부등식 제약 2차 계획 · 음수 사후 절단 아님) · 소수 종목 집중 가능(실보유 하한 없음) · 상한을 주는 호출자(ctx$ub < 1)에겐 상한을 계획 안에(x_i ≤ c·Σx · n·c = 1 이면 EW · n·c < 1 이면 호명 후 래퍼 EW 폴백) — 이 라운드 측정 경로(셀 엔진 ctx$ub = 1)에선 쓰이지 않는다 · 계획은 Σ̃/평균 분산으로 척도 정규화(해 불변) · 1e-10·Σx 미만 잔차는 0",
    "측정 경로 = rf_cell_engine.R catalog 분기(backtest_harness.R 카탈로그 분기가 아니다): 창 = Date < 신호일 직전 252행 · 그 창에 결측 없는 선정 종목만 비중 계산 · 보유(이력 불완전 종목은 빠진다 — 기준 EW 는 선정 전부를 보유하므로 선택 교락 · 아래 record ③ 과 꼬리표 규칙으로 센다) · 0 비중 행은 하네스가 시뮬레이션 전에 버린다",
    "추정 창 252 거래일(셀 사양 lookback 기본값 · 논문 '최소 2년'에서 변경) — P3R01 의 다른 비중 변형과 창이 같지 않다: 빌트인 K1 ivol 60 · K2 minvar 120(Ledoit-Wolf) · K4 kelly 120 — 빌트인 내부 상한(max_w 0.15)은 10-15 축 결정으로 폐지(P3R01 E2 칸 · 재측정 E1 칸부터 상한 없음)",
    "정제 대상 = 받은 종목(≤25 · 이력 완전)의 상관행렬(논문 = 투자 풀 1000종) — k = min(5, n−1) · ε² = 공분산 총분산 보존(식 4)",
    "롱숏 · 종목수 무제한 · 일간 리밸 → 우리 축(롱온리 · ≤25 · Σw ≤ 1 · 엔진 리밸 주기 · 15bps)"),
  cells = unname(cells),
  rules = list(
    tested = paste0("엔진 판정은 다음을 모두 만족할 때만 — 아니면 그 엔진 = 미시험(반증 아님): ① M5 · RX0 둘 다 평가됨(측정 ok ∧ 축 감사 ok) ",
                    "② 실효 시작 status = ok(authoritative_remeasure.json measurement_axis.effective_start — never_met · breadth_unmeasurable · no_rule 이면 미시험) ",
                    "③ 처치 전달률 = 계획 해를 낸 신호일([ecm] infeasible=0 줄) / 선정 신호일(엔진 커버리지 줄 n_try) ≥ delivery_min(줄이 없으면 미시험) ",
                    "④ 판정 입력(위기 누적 포착 중앙값 두 칸 · M5 강세 참여 중앙값 · 짝 위기 비율)이 모두 유한. ",
                    "측정 실패가 연기(워커 ok=FALSE · deferred)면 미시험이 아니라 판정 전 같은 사양 재측정이다(측정이 없는 것 · 결과를 보고 고르는 것이 아니다)"),
    vintage_pair = "같은 엔진 쌍(M5 · RX0)은 함께 시작하고(measure.sh — E1 쌍 → E2 쌍) 칸마다 측정 시작 · 종료 데이터 지문을 남긴다 — 쌍 안 지문 4개가 모두 같아야 판정한다 · 다르면(측정 중 데이터 갱신) 그 쌍을 재측정한 뒤 판정",
    common_window = paste0("칸과 기준의 실효 시작(effective_start.date)이 같으면 원 산출로 판정한다. 다르면 공통 창으로 판정한다: 절단일 = 늦게 시작한 칸의 첫 기간수익일(03_period_returns 첫 date — 두 칸을 같은 날에 맞춘다) · ",
                           "두 칸의 산출 디렉터리(ta_resolve_artifact 해석 디렉터리) 최상위 파일을 전부 복사하고 02_nav · 03_period_returns · 05_benchmark_returns 는 절단일 이후 행만, 04_holdings 는 절단일에 들고 있던 보유를 낸 집행일(절단일 이하 마지막 집행일)부터 남긴다 · ",
                           "NAV 는 절단일 1 로 재기준(drawdown_net · cum_cost 재계산) · 벤치 NAV 는 그 날부터 누적 · 그 사본에 같은 계약(dp_build · 사전등록 행동 카드 설정 사본 · 위생 raw)을 적용한 값으로 decisive · 비열등 · 선택을 판정한다 ",
                           "(셀 워커가 측정 축 표식 사양의 시작일을 epoch 시작으로 고정해 시작 절단 재측정은 하네스 수리 없이는 불가 — 잘린 사본은 절단일 매수 비용만 빠진다 · 그 사실을 기록)"),
    decisive = paste0("엔진별(판정 창 = 원 산출 또는 공통 창 · 보는 창): (a) M5 위기 누적 포착 중앙값(behavior.summary.crisis_cum_capture_median) < RX0 의 값 ∧ ",
                      "(b) 위기별 과반 — 두 칸 모두에 있는 위기(behavior.crises 의 peak_date · trough_date 로 짝 · 짝 없는 위기는 수만 기록하고 판정에서 제외)에서 M5 cum_capture < RX0 cum_capture − tol 인 위기의 비율 > majority_share(tol = matched_controls.R .MC_TOL · P2R02 V1 과 같은 값) ∧ ",
                      "(c) M5 강세 참여 중앙값(behavior.summary.bull_up_capture_median) ≥ uc_floor(behavior_card_cfg_at_prereg.json)"),
    falsified = "판정된(tested) 엔진 중 하나라도 decisive 불충족 = 반증(도훈 결정 문구: 위기 포착 개선 없음 ∨ 강세 참여 < 0.55) · 두 엔진 모두 미시험 = 미시험(반증 아님) · 한 엔진만 판정되면 그 엔진으로 반증만 가능(선택 불가)",
    non_inferiority = paste0("엔진별: RX0 의 보는 창 S_vis > 0 이면 S_vis(M5) ≥ S_vis(RX0) − tie_eps · RX0 의 S_vis = 0 이면(Calmar ≤ 0 또는 PORT_t ≤ 0 — S 가 0 으로 접혀 비교가 사라진다) 보는 창 Calmar(M5) ≥ Calmar(RX0) · ",
                             "tie_eps = 0.02(P3R01 final_selection_rule 승계 — 여기서는 비열등 여유 · 동률 깨기 아님) · S_vis = round_kit rk_S(등급 v3 의 S 식 · 상수 = final_selection_rule) · 입력 NA 면 비열등 불성립(선택 없음 · 반증 아님)"),
    per_crisis = "보는 창 위기별 누적 포착 · 낙폭 포착 · 최악 위기 포착 · CDaR(behavior.stats.cdar — 기준값도 RX0 보는 창 패킷에서 읽는다)를 기록(판정 입력은 decisive 만)",
    attribution = paste0("귀속 = 보는 창 패킷 라벨(controls.attribution.label — matched_controls.R mc_attribution: selection_defense · size_defense · exposure_defense · no_defense · insufficient · 대조 실패면 라벨 없음) + β 대조: ",
                         "같은 위기(패킷 exposure.crises 의 peak · trough 로 짝)에서 M5 selection_sum − RX0 selection_sum > 0 인 비율 > majority_share 이면 '선택 기여 개선'(MC8 짝은 크기 · 비중 · 총노출만 맞추고 β 는 안 맞춘다 — 저β 구성은 라벨만으로 기전 방어가 아니다) · ",
                         "behavior.stats.beta 는 두 칸 병기 · 전기간 귀속(mc_card full)은 사람 쪽 보고 · 방어 주장은 귀속과 함께만 — 크기 · 노출 귀속이면 '개선(크기·노출 귀속)'으로 적고 기전 방어로 쓰지 않는다"),
    selection = paste0("두 엔진 모두 tested ∧ decisive ∧ 비열등이면 P4 조립 구성 부품 후보로 넘긴다 — 꼬리표 없는 '구성 부품 후보' = 두 엔진 모두 기전 방어(selection_defense ∧ β 대조 선택 기여 개선) · ",
                       "그 밖(insufficient · 라벨 없음 · NA · 두 엔진 불일치 포함)은 '노출(β) 레버 — 기전 방어 아님' 꼬리표 · 이력 탈락 꼬리표 규칙(record ③)에 걸리면 '선택 교락(이력 탈락)' 꼬리표를 더한다 · ",
                       "아니면 선택 없음(EW 유지) · P4 에서 고를 때 P3R01(10) · P3R02(2) 구성 변형 전체를 시행 수로 센다"),
    test_window = "후보면: 시험 창(2023-01~) Calmar(gv3_window) · 위기 포착을 RX0 와 비교(사람 쪽 보고 · 선택 규칙 입력 아님)",
    record = paste0("판정 입력 아님(③ 의 꼬리표만 선택 꼬리표에 닿는다): ① 커버리지 = 엔진 요약 줄 '[rf_cell_engine] catalog … 커버리지 (선정일 n_hit/n_try)' · 미산출(이월) 신호일 = n_try − n_hit · ",
                    "폴백은 '[method:paper:EigenCleanMarkowitz] 어댑터 실패' 줄을 사유별로 나눠 센다(상한 불능 · 자산 3종 미만 · 기타 = 계획 오류 등) ",
                    "② 진단 줄 '[ecm] d=… n=… active=… capbind=… infeasible=…'(셀 로그 results/<code>.log)로 신호일별 활성 종목 수 · 상한 구속 수 · 상한 불능 수 ",
                    "③ 이력 불완전 탈락 = 신호일 d 의 RX0 선정 수(d 다음 첫 집행일의 EW 보유 수) − [ecm] n · 그 몫(탈락 / 선정 = 탈락 종목의 EW 기준 비중 합) — 전기간 평균 · 최대와 보는 창 위기 보유 집행일(위기마다 고점 이하 마지막 집행일 ∪ (고점, 저점] 안 집행일) 평균 · ",
                    "위기 평균 몫 > drop_tag_share 이면 결론에 '선택 교락(이력 탈락)' 꼬리표 ",
                    "④ 실보유 수(w > 1e-8 — 어댑터가 1e-10·Σx 미만 잔차를 0 으로 둔다 · [ecm] active 와 같은 문턱) · 유효 종목 수(1/Σw²) · 연 회전율 ",
                    "⑤ M5 대 P3R01 K2(같은 엔진 · P3R01 칸 평가)의 보는 창 위기 누적 포착 · CDaR · S_vis — 차이 = 공분산 추정(고유모드 대 LW) · 창(252 대 120) · 상한(둘 다 없음 — 10-15 축 결정 뒤 측정분만 비교 · 그 전 상한 측정분과 섞지 않는다) · 실효 시작 · 데이터 · 하네스 판본(P3R01 E1 = 10-14 아침 · E2 = 밤 파이프라인 · M5 = 이 배치) ",
                    "⑥ RX0 대 P0R01 C0 보는 창 지표 차(판본 대조) · 칸별 데이터 지문")),
  expectations = list(M5 = "위기 누적 포착 ↓(정제 공분산 최소분산의 위험 처리 — 고잡음 · 고베타 종목 비중 ↓) · 강세 참여 ↓ 가능(저위험 쏠림) · 집중 ↑(실보유 수 ↓ · 하한 없음 — 1~4종 집중 신호일 가능) · CDaR ↓ · 귀속은 노출(β) 방어일 공산"),
  final_selection_rule = list(calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw, w_calmar = GV$weights$calmar, w_port_t = GV$weights$port_t,
                              tie_eps = 0.02, tie_eps_role = "비열등 여유(P3R01 승계)", uc_floor = BC$uc_floor, crisis_tol = MC_TOL,
                              crisis_tol_source = "02_Infrastructure/contracts/matched_controls.R .MC_TOL",
                              majority_share = BC$majority_share, majority_share_source = paste0("behavior_card_cfg_at_prereg.json majority_share — ", BC$majority_share_source %||% ""),
                              delivery_min = 0.9,
                              delivery_min_evidence = "처방 레인 evidence(근거 논문 의무 해제 · CLAUDE.md) — 선정 신호일의 10% 넘게 M5 해가 아니면(EW 폴백 · 이월) 그 칸은 M5 시험이 아니라 혼합 시험이다 · 엔진 커버리지 정지(80% · 엔진 리터럴)보다 엄한 해석 문턱 · 재점검 권고 ⑩ · 결과 전 고정",
                              drop_tag_share = 0.10,
                              drop_tag_share_evidence = "처방 레인 evidence — 위기 보유에서 기준 EW 비중의 10% 넘게가 이력 탈락 종목(신규 상장 · 정지 이력)이면 위기 포착 차의 일부가 구성이 아니라 선택에서 온다 · 꼬리표만(판정 아님) · 재점검 권고 ⑩ · 결과 전 고정"),
  axis_audit = "측정 뒤 04_holdings 실보유가 롱온리 · ≤ max_names · Σw ≤ 1 — 위반 칸 = 측정 무효(미시험)",
  behavior_card_cfg = list(path = rel(BCP), md5 = rk_md5(BCP)),
  operational_pins = .ops_pins(),
  evaluation = list(files = .eval_pins(), note = "판정 구현(evaluate.R) · 픽스처 · precheck · 측정 절차를 결과 전에 고정 — evaluate.R 은 실행 시 자기 md5 를 이 값과 대조한다(재점검 권고 ①)"),
  tests = TESTS,
  precheck = "측정 직전 precheck.R 가 사양 · 어댑터 · 운영 경로 md5 · 카탈로그 엔트리 · quadprog · R 판 · 평가 경로 md5 를 사전등록 값과 다시 대조 — 하나라도 다르면 측정하지 않는다 · 데이터 지문(RAWDATA · 벤치 캐시 크기 · mtime)을 기록한다",
  design_inputs = paste0("논문 원문(감독 기록 교차 점검 ① 인용) · 측정 경로 코드(rf_cell_engine.R catalog 분기 · weight_catalog.R · method_registry.R · replication_harness.R) · 평가 계약 코드(diagnosis_packet.R · matched_controls.R · behavior_card.R) · ",
                         "P3R01 · P2R02 사전등록 형식 · 격리 교차 점검 ② · 재점검 지적 — 성과 수치 미사용(노출 2건 = exposures · 설계 입력 아님)"),
  budget = list(variants = N_ROUND, reference_remeasure = length(ENGINES), rounds = 1L),
  changes_after_draft = list(
    ch("R1 운영 상한 0.20 · 무기록 탈락", "어댑터 v2 — 상한을 2차 계획 안에(x_i ≤ c·Σx · c = WC_UB 0.20) · n·c < 1 이면 호명 후 래퍼 EW 폴백 · 호출마다 [ecm] 진단 줄 · 검사 E 절(운영 경로 weight_catalog_arms()$adapter_fn · 양수 ≤4종 · n·c<1 · 구판 사본 양방향 · 상한 드리프트 대조) · record ① ② · rules.tested(미시험 정의)",
       "래퍼의 사후 재분배는 최적해가 아니고 양수 ≤4종 해는 단언 실패 → 엔진이 삼켜 신호일이 기록 없이 빠졌다(코드로 확인 — rf_cell_engine.R catalog 분기 tryCatch → NULL)"),
    ch("R2 선언 정정", "adaptations 3 · 4 · 어댑터 머리 주석 · 방법 등록부 kr_mapping 을 실제 측정 경로로 다시 씀 · '같은 창' 문장 삭제(K1 60 · K2 120 · K4 120) · record ③(이력 불완전 탈락 수 · EW 기준 비중)",
       "측정 경로는 셀 엔진 catalog 분기(Date < 신호일 · 이력 완전 종목만)이고 P3R01 빌트인 변형은 자기 창을 쓴다(코드로 확인)"),
    ch("R3 p = 1 ⇒ 최소분산 · 결론 범위", "변형 이름 · purpose · conclusion_scope · adaptations 1 을 '상한 롱온리 최소분산(KKT 동치)'으로 · record ⑤(M5 대 P3R01 K2 · 판정 입력 아님 · K2 결과 열람 전 · P3R01 evaluation.json 생성 전 등록)",
       "결과가 '논문 구성법이 KR 롱온리에서 통한다/안 통한다'로 잘못 읽히는 것을 막는다"),
    ch("R4 같은 판본 기준", "RX0 2칸(P0R01_E?_C0 사양 그대로 · 같은 배치 · 시행 수 무가산 · 카탈로그 미등재)을 반증 · 비열등 · 선택 기준으로 · record ⑥ 판본 대조 · precheck 데이터 지문",
       "기준 측정(10-14~15 밤) 뒤 데이터 · 하네스가 바뀌면 처방 효과와 갱신 효과가 섞인다 · 기준 CDaR 부재 문제(P0R01 eval.json visible 에 cdar 없음)도 RX0 패킷에서 읽어 사라진다"),
    ch("R5 실효 시작 정렬", "rules.common_window — 실효 시작이 다르면 공통 창 사본에 같은 계약을 적용",
       "M5 는 보유 수가 작아 MC3 실효 시작이 EW 와 같거나 이르다 → 위기 집합 · S_vis 창이 칸마다 달라진다 · 시작 절단 재측정은 워커가 epoch 시작을 고정해 하네스 수리 없이는 불가"),
    ch("R6 R2 통제", "exposures(노출 2건과 평가) · drafted_before/registered_before 에 칸 단위 결과 파일 존재 · 수정 시각(미열람 선언) · 검토판 보존과 연결 · operational_pins · precheck.R · 등록 전 커밋",
       "노출 뒤 새로 쓰는 초안이고 가드는 라운드 평가 파일만 봤으며 --draft 재실행이 검토판과의 연결을 끊었다"),
    ch("권고 채택", "decisive 에 위기별 과반(b) 추가(∧ 중앙값) · 선택에 귀속 꼬리표 · S_vis = 0 처리(비열등 = Calmar) · tie_eps 역할 명시 · 귀속 창 명시(보는 창 패킷) · k 외삽 주석 · A6 을 위반 주입 양성 대조로 · P4 시행 회계 문장",
       "중앙값은 가운데 위기만 본다(P2R01 교훈 · P2R02 구조와 정합) · S 가 0 으로 접히면 비교가 사라진다"),
    ch("권고 불채택", "p = ctx$mu 전환 · 같은 위험 EW(σ 스케일) 위기 포착 · 등록 전 구현 확인 실행",
       "p = 1 은 결론 범위(최소분산)와 해석을 고정하고 근사 오차 상한을 적었다 · 스케일 합성 계열은 계약 경로가 없어 손계산이 된다(AX-008) · 활성 · 상한 구속 · 탈락 수는 측정의 진단 줄이 신호일마다 정확히 남긴다"),
    ch("범위 밖 조치", "P3R01 evaluate.R — 기준 CDaR 을 기준 칸 보는 창 패킷(behavior.stats.cdar)에서 읽고 못 읽으면 판정 중단(사전등록 문구대로의 구현 · 규칙 개정 아님 · 기록 = P3R01 폴더 evaluate_fix_20261015.md) · 하네스 카탈로그 분기(.bh_catalog_weights) 체결일 수익 포함 · 결측 0 채움 · 상한 0.20 축 충돌 = 별도 과제",
       "교차 점검 권고 — P3R01 평가가 결과와 무관하게 'no_lever_over_ew' 로 떨어질 결함(밤 파이프라인 ④ 전에 수리)")),
  changes_after_review2 = list(
    ch("①판정 구현 고정 · 남은 자유도", "evaluate.R · evaluate_fixture.R(22/0) · precheck.R · measure.sh md5 고정(evaluation.files · 실행 시 자기 대조) · NA 입력 · 실효 시작 status ≠ ok · 짝 위기 0 = 미시험 · (b) 분모 = 두 칸 모두의 위기(짝 없음 제외 · 수 기록) · 꼬리표 없는 후보 = 두 엔진 기전 방어 · 측정 연기 = 판정 전 재측정",
       "결과 뒤에 쓰면 NA 처리 · 분모 · 꼬리표가 결과를 본 뒤 정해진다 · isTRUE 로 접으면 미시험이 반증이 된다"),
    ch("②공통 창 사본 절차", "rules.common_window — 최상위 파일 전체 복사 · 4파일 절단 · 절단일 = 늦은 칸 첫 기간수익일 · 보유 = 절단일 이하 마지막 집행일부터 · NAV · 벤치 재기준", "4파일만으로는 dp_build · ta_resolve_artifact 가 멈추고 절단 기준이 미정이었다"),
    ch("③β 대조 꼬리표", "rules.attribution · selection — 기전 방어 = selection_defense ∧ exposure.crises selection_sum 짝 과반 · β 병기", "MC8 짝은 β 를 안 맞춘다 — 저β 구성이 selection_defense 로 찍힐 수 있다(10-14 방어형 411건 중 379건 β 착시와 같은 함정)"),
    ch("④쌍 판본", "measure.sh — E1 쌍 → E2 쌍 순차 · 쌍 안 2병렬 · 칸별 시작 · 종료 지문 · rules.vintage_pair", "xargs 4칸 순서로는 같은 엔진 쌍이 다른 시각에 시작해 데이터 갱신이 끼면 판본이 섞인다"),
    ch("⑤핀 보강", "OPS += E2 기저 엔진 · rf_base_cache · rf_axes · rf_rebalance · rf_sleeve · grade_v3 · tilt_attribution · matched_controls.json · constraint_defaults.json · precheck R 판 대조 · tests(어댑터 검사 md5 · 통과 수 · 픽스처)", "판정 · 측정에 닿는 파일이 핀 밖이었다"),
    ch("⑥등록 전 커밋 강제", "--register 가 git status 로 어댑터 · 검사 · 라운드 폴더 · 방법 등록부 · 비중 카탈로그 · P3R01 evaluate.R 미커밋이면 멈춘다", "기록된 HEAD 에 어댑터 원문이 없으면 md5 로 변경은 잡아도 복원이 안 된다"),
    ch("⑦등록 시점", "P3R01 평가 파일 전 등록(가드 유지) · measure.sh 는 등록 뒤 띄운다", "가드는 ④ 뒤 영구 거부"),
    ch("⑧R3 문구", "'K2 결과 열람 전 · P3R01 evaluation.json 생성 전' · record ⑤ 차이에 데이터 · 하네스 판본", "P3R01_E1_K2.json 은 v1 초안 전부터 있다(미열람)"),
    ch("⑨결과 파일 목록", "P0R01_E?_C0.json · .log · P3R01_*.log 를 존재 · 수정 시각 목록에", "기준 칸 전기간 결과 · 등급 줄이 목록 밖이었다"),
    ch("⑩해석 문턱 사전 고정", "delivery_min 0.9(미시험) · drop_tag_share 0.10(선택 교락 꼬리표) — evidence 기록", "엔진 정지(80%) 아래의 혼합 시험과 이력 탈락 해석이 결과 뒤 자유도였다"),
    ch("⑪미세 양수 비중", "어댑터 — 1e-10·Σx 미만 잔차 0 · record ④ 실보유 문턱 1e-8 · 검사 E9", "하네스 Weight != 0 이 잔차를 보유로 세어 MC3 보유 수 · 축 감사 n 을 부풀린다"),
    ch("⑫n = 5 경계 · 폴백 분리", "어댑터 — n·c = 1 이면 유일 가능해 EW(계획 생략) · Σ̃/평균 분산 척도 정규화(해 불변 · E11) · 검사 E8 · E10(꼭짓점) · record ① 폴백 사유별", "일차종속 상한 제약에서 quadprog 반올림 오류 → 진단 줄 없는 폴백"),
    ch("⑬상수 출처 · 검토 연결", "majority_share = 행동 카드 사본 값(출처 동봉) · reviewed_drafts = v1 · v2 보존본 md5 · --register 가 두 보존본을 대조", "리터럴 0.5 · 2차 검토 미연결"),
    ch("⑭P3R01 수리 기록(범위 밖)", "P3R01 폴더 evaluate_fix_20261015.md — 변경 시각 · 사유 · P3R01 칸 결과 미열람 선언", "R2 감사 흔적이 P3R02 초안에만 있었다")),
  changes_after_registration = list(
    ch("축 결정 — 비중 상한 없음(도훈 2026-10-15)", "카탈로그 하네스 WC_UB 0.20 → 1(상한 없음) · 빌트인 calc_*_weights 를 축 값 max_w 로 호출(구판 기본값 0.15) · 어댑터 v3 — 고정 상수 0.20 삭제, 상한 = 호출자 ctx$ub(셀 엔진 1 → 상한 없음 · ctx$ub < 1 이면 계획 안 상한 유지) · 검사 27/0(운영 경로 = 상한 없음 · 구판 하네스 사본 회귀 대조 · 상한 호출자 경로 · 돌연변이) · 이름 · purpose · conclusion_scope · adaptations · expectations · record ⑤ 에서 상한 0.20 서술 삭제",
       "도훈 \"고정축 비중상한 없음으로 진행하자\" — 하네스 상한은 v10(2026-08-29 [0, 0.20] 폐지) 이전 잔재였고 P0R01 · P3R01 사전등록도 상한을 적지 않았다(축 = 상한 없음 전제). v3 는 측정 전이라 대체한다(R2 — 결과 0)"),
    ch("판정 규칙 · 문턱 · 칸 · 기준", "변경 없음 — decisive · 비열등 · 선택 · 꼬리표 · delivery_min · drop_tag_share · RX0 · 쌍 지문 · 공통 창 그대로", "축 결정은 처치(비중법)의 상한만 바꾼다 — 규칙은 결과 전 v3 그대로")))
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), DR, useBytes = TRUE)
cat(sprintf("[P3R02] 초안 v4 %s (md5 %s) · 칸 %d(처방 %d + 기준 재측정 %d) · 검사 %s · P3R01 평가 %s · P0R01 평가 %s\n", DR, rk_md5(DR), length(cells), N_ROUND,
            length(ENGINES), paste(vapply(TESTS, function(t) sprintf("%s %s/%s", basename(t$path), t$pass, t$fail), ""), collapse = " · "),
            if (file.exists(P3R01_EVAL)) "있음" else "없음", if (file.exists(P0R01_EVAL)) "있음" else "없음"))
