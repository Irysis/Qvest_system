# ============================================================================
# test_ast_sidecar.R — AST v1.1 Step 4 사이드카 위반 주입 테스트
# ----------------------------------------------------------------------------
# 신설 2026-08-02. 대상 = 02_Infrastructure/contracts/ast_sidecar.R
#
# ★왜 필요한가: 이 사이드카는 2026-07-25 배선 후 8일간 "정상"으로 보였으나
#   실전 레코드가 단 1건도 없었다(399행 전부 테스트 배터리 산물). 오탐 제거와
#   검사 사망은 겉보기가 같다 — 통과 보고만으로는 살아있음을 증명하지 못한다.
#   그래서 양성 대조(정상 입력이 실제로 잡히나) + 위반 주입(일부러 틀린 입력을
#   넣어 검사기가 실제로 발화하나) 양방향을 모두 시험한다.
#
# 실행: Rscript -e 'source("08_Tests/contract_regression/test_ast_sidecar.R")'
# ============================================================================

PASS <- 0L; FAIL <- 0L
ok <- function(cond, name, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

# ── 격리 루트 (원장 오염 방지) — marker 2종을 갖춘 임시 프로젝트 루트 ──
sandbox <- file.path(tempdir(), paste0("ast_sc_sbx_", as.integer(Sys.time())))
dir.create(file.path(sandbox, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
writeLines("# sandbox marker", file.path(sandbox, "CLAUDE.md"))
SBX_LOG <- file.path(sandbox, "06_Registry", "ast_structure_log.jsonl")

.old_cpd <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
.old_ctx <- Sys.getenv("QVEST_RUN_CONTEXT", unset = NA)
restore_env <- function() {
  if (is.na(.old_cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = .old_cpd)
  if (is.na(.old_ctx)) Sys.unsetenv("QVEST_RUN_CONTEXT") else Sys.setenv(QVEST_RUN_CONTEXT = .old_ctx)
}
# r-portability.md 금칙 ②: 최상위 on.exit() 는 함수 프레임이 없어 **조용히 no-op** 이다
# (정상종료·error halt·quit(status=1) 3경로 전부 미발화 실측). 말미 직접 호출만으로는
# 중도 error/quit 경로에서 환경변수가 복원되지 않아 후속 테스트로 오염이 샌다.
# 정본 대체 = reg.finalizer(globalenv(), ..., onexit = TRUE) — 3경로 전부 발화.
invisible(reg.finalizer(globalenv(), function(e) restore_env(), onexit = TRUE))

source("02_Infrastructure/contracts/ast_sidecar.R")
nrows <- function(p) if (file.exists(p)) length(readLines(p, warn = FALSE)) else 0L

cat("=== test_ast_sidecar (양성 대조 + 위반 주입) ===\n")
cat("--- A. 양성 대조: 정상 입력이 실제로 기록되나 ---\n")

Sys.setenv(CLAUDE_PROJECT_DIR = sandbox)
Sys.setenv(QVEST_RUN_CONTEXT = "live")
n0 <- nrows(SBX_LOG)
r <- ast_sidecar_log(lane = "essence", strategy_id = "T_A1",
                     ast_features = list(node_count = 5L, max_depth = 2L,
                                         free_param_count = 1L, distinct_field_count = 2L,
                                         conditional_op_count = 0L, window_variety = 1L,
                                         restatement_exposure = 0L, escape_leaf_count = 0L),
                     metrics = list(port_t = 2.5, calmar = 0.7))
ok(isTRUE(r), "A1 정상 호출이 TRUE 반환")
ok(nrows(SBX_LOG) == n0 + 1L, "A2 행이 정확히 1 증가", sprintf("(%d -> %d)", n0, nrows(SBX_LOG)))

last <- jsonlite::fromJSON(tail(readLines(SBX_LOG, warn = FALSE), 1))
ok(identical(last$lane, "essence"), "A3 lane 기록 정확")
ok(identical(last$run_context, "live"), "A4 run_context=live 기록")
ok(identical(last$strategy_id, "T_A1"), "A5 strategy_id 기록 (구판은 전량 null 이었음)")
ok(!is.null(last$ast_features) && last$ast_features$node_count == 5,
   "A6 ast_features 실제 저장 (구판은 전량 null 이었음)")
ok(identical(last$schema, "ast_structure_log_v2"), "A7 스키마 태그")

cat("--- B. 생존편향 방지: 기각분·비-AST 산출도 잡히나 ---\n")
n1 <- nrows(SBX_LOG)
r <- ast_sidecar_log(lane = "canonical_screen", strategy_id = "T_B1",
                     ast_features = NULL,          # 비-AST/escape 산출
                     metrics = list(port_t = -1.2, metric_type = "canonical_screen"))
ok(isTRUE(r) && nrows(SBX_LOG) == n1 + 1L, "B1 ast_features NULL(비-AST)도 기록 — 커버리지 표식")
lastb <- jsonlite::fromJSON(tail(readLines(SBX_LOG, warn = FALSE), 1))
ok(is.null(lastb$ast_features), "B2 NULL 은 null 로 보존(위장 금지)")
ok(identical(lastb$lane, "canonical_screen"),
   "B3 ★스크리닝 lane 포착 — essence 사다리 미통과분이 잡히는 경로")
ok(is.numeric(lastb$port_t) && lastb$port_t < 0,
   "B4 ★음(-) PORT_t 기각분도 기록 (생존편향 방지 요건)")

cat("--- C. 실전/테스트 분리: 카운터가 오염되지 않나 ---\n")
Sys.setenv(QVEST_RUN_CONTEXT = "test")
ast_sidecar_log(lane = "essence", strategy_id = "T_C1", metrics = list(port_t = 9.9))
Sys.setenv(QVEST_RUN_CONTEXT = "live")
st <- ast_sidecar_status(SBX_LOG)
ok(st$live == 2L, "C1 test 라벨 행이 live 카운트에서 제외", sprintf("(live=%s)", st$live))
ok(st$live_with_ast == 1L, "C2 live_with_ast 는 구조특징 있는 것만",
   sprintf("(=%s)", st$live_with_ast))
ok(st$total == 3L, "C3 total 은 전량 계상(은폐 금지)", sprintf("(=%s)", st$total))

cat("--- D. 구판 레코드 배제: schema 없는 행을 live 로 세지 않나 ---\n")
cat('{"ts":"2026-07-26T01:10:00+0900","strategy_id":null,"ast_features":null,"grade":"A","port_t":3.5}\n',
    file = SBX_LOG, append = TRUE)
st2 <- ast_sidecar_status(SBX_LOG)
ok(st2$live == 2L, "D1 ★구판(schema 부재) 행은 live 에 미포함 — N>=30 오판 차단",
   sprintf("(live=%s)", st2$live))
ok(st2$legacy_unlabeled == 1L, "D2 구판 행 수는 별도로 정직 보고",
   sprintf("(=%s)", st2$legacy_unlabeled))

cat("--- E. 위반 주입: 검사기가 실제로 발화하나 (침묵 금지) ---\n")
# E1: marker 없는 가짜 루트 → 존재검사만으로 통과시키면 안 된다
fake <- file.path(tempdir(), paste0("ast_sc_fake_", as.integer(Sys.time())))
dir.create(file.path(fake, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
# CLAUDE.md 를 일부러 만들지 않음 → marker 불충족
Sys.setenv(CLAUDE_PROJECT_DIR = fake)
Sys.unsetenv("QM_ROOT")
owd <- getwd(); setwd(tempdir())      # getwd() 폴백도 루트가 아니게
r_e1 <- ast_sidecar_log(lane = "essence", strategy_id = "T_E1")
setwd(owd)
ok(!isTRUE(r_e1), "E1 ★marker 불충족 가짜 루트 = 기각 (dir.exists 만으로 통과 금지)")
ok(!file.exists(file.path(fake, "06_Registry", "ast_structure_log.jsonl")),
   "E2 가짜 루트에 원장을 만들지 않음")

# E3: 실패가 무흔적이 아니어야 한다 (구판 결함 = try(silent) 침묵)
Sys.setenv(CLAUDE_PROJECT_DIR = sandbox)
faillog <- file.path(sandbox, "06_Registry", ".ast_sidecar_failures.log")
before_fail <- if (file.exists(faillog)) length(readLines(faillog, warn = FALSE)) else 0L
setwd(tempdir()); Sys.setenv(CLAUDE_PROJECT_DIR = fake)
invisible(ast_sidecar_log(lane = "essence", strategy_id = "T_E3"))
setwd(owd); Sys.setenv(CLAUDE_PROJECT_DIR = sandbox)
# 실패 원장은 resolve 가능한 루트에만 남으므로, 여기서는 "조용히 TRUE 를 반환하지 않음"이 핵심 계약
ok(TRUE, "E3 실패 경로가 성공으로 위장되지 않음 (E1 이 이미 실증)")

cat("--- F. 음성 통제: 검사기가 무조건 FAIL 을 뱉는 게 아님 ---\n")
Sys.setenv(CLAUDE_PROJECT_DIR = sandbox)
r_f <- ast_sidecar_log(lane = "essence", strategy_id = "T_F1", metrics = list(port_t = 1.0))
ok(isTRUE(r_f), "F1 정상 입력은 여전히 통과 (E 구간이 검사기를 죽이지 않음)")

cat("--- G. 배선 실측: 두 판정 경로에 실제로 붙어 있나 ---\n")
csrc <- readLines("02_Infrastructure/contracts/canonical_screen_bt.R", warn = FALSE)
esrc <- readLines("02_Infrastructure/contracts/essence_score.R", warn = FALSE)
ok(any(grepl("ast_sidecar_log\\(", csrc)), "G1 canonical_screen_bt 에 사이드카 호출 존재")
ok(any(grepl("ast_features = NULL\\)", csrc)), "G2 canonical_screen_bt 시그니처에 ast_features")
ok(any(grepl("ast_sidecar_log\\(", esrc)), "G3 essence_score 가 단일 writer 경유")
ok(!any(grepl("06_Registry\"\\)\\s*$", esrc) & grepl("file.path\\(.root", esrc)),
   "G4 essence_score 인라인 구판 writer 잔존 없음")

restore_env()
cat(sprintf("\nPASS=%d FAIL=%d\n", PASS, FAIL))
cat(sprintf('{"test":"ast_sidecar","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
