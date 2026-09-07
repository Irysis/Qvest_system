#!/usr/bin/env Rscript
# test_rf_reopen_attempt.R — 닫힌 칸 되살리기 (2026-09-07 · CDaR_LP 솔버 수리로 원인이 제거된 terminal 칸)
#   양방향: 양성(원인 제거 후 reopen → 재개 대상 복귀 · 이력 보존) + 위반 주입(사유 없음 · 이미 측정된 칸 ·
#   없는 n · 없는 entry). 격리 root 픽스처만 쓴다 — 운영 원장·저널 무접촉.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SBX <- file.path(tempdir(), sprintf("rf_reopen_%d", Sys.getpid()))
dir.create(file.path(SBX, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
suppressWarnings(suppressMessages(library(jsonlite)))
invisible(capture.output(suppressMessages(
  source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), local = globalenv()))))

# ── 픽스처: 실사고 형태 — B2_10 이 워커 시간초과 2회로 terminal, essence 없음 ──────────────
mk <- function() {
  led <- list(
    schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
    entries = list(list(
      base_id = "RP_FIXT_reopen", paper_key = "fixture", status = "active",
      base_grade = "C", attempts_used = 3L, max_attempts = 28L,
      attempts = list(
        list(n = 1L, cell_code = "B2_8", grade = "C",
             essence = list(cell_code = "B2_8", port_t = 1.9)),
        list(n = 2L, cell_code = "B2_10",
             grade = "NA (등급 미발행 — 병렬 워커 미완료/시간초과)", essence = NULL,
             fail_count = 2L, terminal = TRUE,
             terminal_reason = "워커 산출 부재 2회 연속 — 재시도 상한 2 도달"),
        list(n = 3L, cell_code = "B3_11", grade = NULL, essence = NULL)))))
  write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file.path(SBX, "06_Registry", "reinforce_ledger_l1.json"))
}
rd <- function() fromJSON(file.path(SBX, "06_Registry", "reinforce_ledger_l1.json"), simplifyVector = FALSE)
att <- function(o, n) Filter(function(a) identical(as.integer(a$n), n), o$entries[[1]]$attempts)[[1]]
# 러너의 재개 술어 정본(reinforce_auto_parallel.R): essence$port_t 없음 ∧ !terminal
is_pending <- function(a) (is.null(a$essence) || is.null(a$essence$port_t)) && !isTRUE(a$terminal)

cat("=== A. 양성 대조 — 원인 제거 후 reopen ===\n")
mk()
a0 <- att(rd(), 2L)
if (isTRUE(a0$terminal) && !is_pending(a0)) ok("A0 픽스처: B2_10 은 terminal 이라 재개 대상이 아니다") else
  ng("A0 픽스처가 실사고 형태가 아니다")
r <- tryCatch(rf_reopen_attempt(1L, "RP_FIXT_reopen", 2L,
  reason = "워커 시간초과의 원인 = CDaR_LP 솔버(cccp ~T^3). lpSolve 사슬로 제거(2026-09-07)", root = SBX),
  error = function(e) e)
if (inherits(r, "error")) ng("A1 reopen 이 죽었다", conditionMessage(r)) else {
  a1 <- att(rd(), 2L)
  if (is_pending(a1)) ok("A1 reopen 후 재개 대상 복귀(terminal 해제)") else ng("A1 아직 재개 대상이 아니다")
  if (identical(as.integer(a1$fail_count %||% -1L), 0L)) ok("A2 재시도 예산도 되돌아간다(fail_count 0)") else
    ng("A2 fail_count 가 남아 다음 실패 1회로 다시 닫힌다", as.character(a1$fail_count))
  if (length(a1$reopened) == 1L && nzchar(a1$reopened[[1]]$reason %||% "") &&
      isTRUE(a1$reopened[[1]]$was_terminal) &&
      identical(as.integer(a1$reopened[[1]]$was_fail_count), 2L))
    ok("A3 되살린 이력이 남는다(사유·직전 terminal·직전 fail_count)") else ng("A3 이력 소실 — 지우고 되살렸다")
  if (nzchar(a1$reopened[[1]]$prev_terminal_reason %||% "")) ok("A4 직전 terminal 사유를 보존한다") else
    ng("A4 왜 닫혔었는지가 사라졌다")
  if (is.null(a1$essence) && grepl("NA", as.character(a1$grade %||% ""))) ok("A5 성공 위장 없음 — essence·grade 는 그대로") else
    ng("A5 되살리면서 측정값을 위조했다")
}
# 두 번째 reopen → 이력 누적
invisible(tryCatch(rf_reopen_attempt(1L, "RP_FIXT_reopen", 2L, reason = "두 번째 원인 제거", root = SBX),
                   error = function(e) NULL))
if (length(att(rd(), 2L)$reopened) == 2L) ok("A6 이력은 누적된다(덮어쓰지 않는다)") else ng("A6 이력이 덮였다")

cat("=== B. 위반 주입 ===\n")
mk()
b1 <- tryCatch({ rf_reopen_attempt(1L, "RP_FIXT_reopen", 2L, reason = "", root = SBX); NULL },
               error = function(e) e)
if (inherits(b1, "error") && grepl("사유", conditionMessage(b1))) ok("B1 사유 없이 되살리지 않는다") else
  ng("B1 빈 사유가 통과했다 — terminal 과 대칭이 깨진다")
if (isTRUE(att(rd(), 2L)$terminal)) ok("B1' 거부된 호출은 원장을 바꾸지 않았다") else ng("B1' 거부인데 원장이 바뀌었다")

b2 <- tryCatch({ rf_reopen_attempt(1L, "RP_FIXT_reopen", 1L, reason = "측정된 칸 재측정 시도", root = SBX); NULL },
               error = function(e) e)
if (inherits(b2, "error") && grepl("이미 측정", conditionMessage(b2))) ok("B2 이미 측정된 칸은 reopen 대상이 아니다") else
  ng("B2 측정된 칸을 되살렸다 — 측정값을 덮는 경로가 열린다")

b3 <- tryCatch({ rf_reopen_attempt(1L, "RP_FIXT_reopen", 99L, reason = "없는 칸", root = SBX); NULL },
               error = function(e) e)
if (inherits(b3, "error") && grepl("attempt", conditionMessage(b3))) ok("B3 없는 n 은 거부") else ng("B3 없는 n 이 통과")

b4 <- tryCatch({ rf_reopen_attempt(1L, "RP_NOPE", 2L, reason = "없는 entry", root = SBX); NULL },
               error = function(e) e)
if (inherits(b4, "error") && grepl("entry 부재", conditionMessage(b4))) ok("B4 없는 entry 는 거부") else ng("B4 없는 entry 가 통과")

cat("=== C. 배선 — 러너의 재개 술어와 같은 축인가 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE)
src <- sub("#.*$", "", src)
if (any(grepl("!isTRUE(a$terminal)", src, fixed = TRUE)))
  ok("C1 러너 pending 정의가 terminal 을 보므로 reopen 이 곧 재개다") else
  ng("C1 러너가 terminal 을 안 본다 — reopen 이 재개로 이어지지 않는다")
led_src <- readLines(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), encoding = "UTF-8", warn = FALSE)
led_src <- sub("#.*$", "", led_src)
if (any(grepl("rf_reopen_attempt <- function", led_src, fixed = TRUE)))
  ok("C2 writer 는 원장 파일 안에 있다(원장 밖 직접 편집 아님)") else ng("C2 writer 부재")

unlink(SBX, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_reopen_attempt","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
