#!/usr/bin/env Rscript
#==============================================================================
# test_rf_terminal_retry.R — 재개(resume)의 출구 계약 **양방향 검사** (2026-08-31)
#
# 왜 이 검사가 있는가 (실사고):
#   병렬 러너의 재개는 "등록됐는데 실행이 실패한 칸을 잃지 않는다" 를 위해 만들어졌고,
#   그 설계는 *일시적* 실패(워커 미기동·시간초과)만 상정했다. 그런데 rf_cell_engine 에는
#   **결정론적** 거절이 있다 — 처치 미전달(같은 스펙이면 몇 번을 돌려도 같은 자리에서 죽는다).
#   그 둘을 구분하지 않으니 B3_11 이 2026-08-31 00:16~07:46 사이 16회 동일 실패로
#   재실행됐고 attempts_used 가 15 에 고정돼 강화 루프 전체가 7.5시간 제자리를 돌았다.
#   로그는 매번 정상적으로 보였다 — resume_pending → worker_spawn → cell_error → batch_done.
#
# 판정 축 (계기가 재기 쉬운 것 말고 잴 것을 재도록):
#   ① terminal 로 닫힌 칸은 **러너의 실제 pending 술어**에서 빠지는가
#      — 술어를 사본으로 재구현하지 않고 러너 소스에서 **추출해** 돌린다(사본은 낡는다).
#   ② terminal 은 성공으로 위장하지 않는가 (essence 는 여전히 없다)
#   ③ 사유 없는 terminal 은 거부되는가 (위반 주입)
#   ④ 일시 실패는 여전히 재개되는가 (음성 대조 — 고쳐서 반대쪽을 죽이지 않았는지)
#   ⑤ fail_count 는 실패에서만 오르는가 (측정 성공은 실패로 세지 않는다)
#
# 실행: Rscript 08_Tests/reinforcement/test_rf_terminal_retry.R
# 부작용 없음 — 격리된 임시 root 에만 쓴다(공유 원장 무접촉).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { cat(sprintf("  OK   %s\n", m)); PASS <<- PASS + 1L }
ng <- function(m, d = "") { cat(sprintf("  FAIL %s — %s\n", m, d)); FAIL <<- FAIL + 1L }

# ── 격리 root ────────────────────────────────────────────────────────────────
TROOT <- file.path(tempdir(), sprintf("rf_term_%d", Sys.getpid()))
dir.create(file.path(TROOT, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
# ★최상위 on.exit 금지 — Rscript <file> 로는 조용한 no-op(정리가 아예 안 돌아 픽스처가
#   남는다)이고, source() 로 부르면 프레임이 닫히며 **즉시 발화해 픽스처를 미리 지운다**.
#   호출 방식에 따라 정반대로 틀린다. 정리는 끝에서 명시적으로 한다.
mk <- function() {
  led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 20L,
              note = "test", entries = list(list(
                base_id = "T_BASE", base_grade = "F", paper_key = "t:1", status = "active",
                target_grade = "A", attempts_used = 3L,
                attempts = lapply(1:3, function(k) list(n = k, date = "20260831", idea = list(),
                  keyword_axis = "universe", root_papers = list(), grade = NA,
                  essence = NULL, artifacts = NULL, l_code = NULL, lessons = NULL)))),
              combination_review = list(papers_since_last_review = 0L, last_review_date = "", history = list()),
              last_updated = "")
  write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
        file.path(TROOT, "06_Registry/reinforce_ledger_l1.json"))
}
att <- function(n) {
  e <- rf_load(1L, TROOT)$entries[[1]]
  Filter(function(a) identical(as.integer(a$n), as.integer(n)), e$attempts)[[1]]
}

# ── 러너의 pending 술어를 **소스에서 추출** ──────────────────────────────────
#   사본을 여기 다시 적으면 러너가 바뀔 때 이 검사만 옛 규칙을 지키며 통과한다.
#   ★경로는 덮어쓸 수 있다 — 이 검사기 자신의 양성 대조(구판 술어를 주입해 실제로 FAIL 하는지)를
#     공유 러너를 건드리지 않고 돌리기 위해서다. 기본값은 정본.
RUNNER <- Sys.getenv("QVEST_RF_RUNNER", file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"))
src <- readLines(RUNNER, warn = FALSE)
i0  <- grep("^pending <- Filter\\(", src)
if (!length(i0)) { cat("  FAIL pending 술어를 러너에서 못 찾았다 — 검사 자체가 낡았다\n"); quit(status = 1) }
.bal <- function(txt) { ch <- unlist(strsplit(txt, "")); sum(ch == "(") - sum(ch == ")") }
i1 <- i0
while (i1 <= length(src) && .bal(paste(src[i0:i1], collapse = " ")) > 0L) i1 <- i1 + 1L
PRED_TXT <- paste(src[i0:i1], collapse = "\n")
pending_of <- function(E) { eval(parse(text = PRED_TXT), envir = list2env(list(E = E), parent = environment())) }
cat(sprintf("=== 러너 술어 추출 (%s:%d-%d) ===\n", "reinforce_auto_parallel.R", i0, i1))

cat("=== 1. 구조적 실패 → terminal → 재개 대상에서 제외 ===\n")
mk()
rf_record_result(1L, "T_BASE", 1L, grade = "NA (미결 — 처치 미전달·측정 무효)",
                 lessons = "구조", terminal = TRUE, terminal_reason = "구조적 미결(결정론)", root = TROOT)
a1 <- att(1L)
if (isTRUE(a1$terminal)) ok("terminal 표식 기록") else ng("terminal 미기록")
E <- rf_load(1L, TROOT)$entries[[1]]
ns <- vapply(pending_of(E), function(a) as.integer(a$n), integer(1))
if (!(1L %in% ns)) ok("러너 pending 에서 제외 — 루프가 전진한다") else ng("여전히 pending", paste(ns, collapse = ","))

cat("=== 2. terminal 은 성공으로 위장하지 않는다 ===\n")
if (is.null(a1$essence)) ok("essence 없음(미측정 그대로)") else ng("essence 가 생겼다 — 성공 위장")
if (grepl("미결|미발행", a1$grade %||% "")) ok("등급이 미결로 표기") else ng("등급 표기 오류", a1$grade %||% "")
if (nzchar(a1$terminal_reason %||% "")) ok("사유 기록") else ng("사유 없이 닫혔다")

cat("=== 3. 사유 없는 terminal 거부 (위반 주입) ===\n")
r <- tryCatch({ rf_record_result(1L, "T_BASE", 2L, grade = "NA", terminal = TRUE, root = TROOT); "통과" },
              error = function(e) "차단")
if (identical(r, "차단")) ok("사유 없는 terminal 차단") else ng("사유 없이도 닫혔다 — 침묵 폐기 경로")

cat("=== 4. 일시 실패는 여전히 재개된다 (음성 대조) ===\n")
mk()
rf_record_result(1L, "T_BASE", 2L, grade = "NA (등급 미발행 — 병렬 실행 실패)",
                 lessons = "일시", terminal = FALSE, root = TROOT)
E <- rf_load(1L, TROOT)$entries[[1]]
ns <- vapply(pending_of(E), function(a) as.integer(a$n), integer(1))
if (2L %in% ns) ok("terminal=FALSE 는 pending 유지 — 재개 기능 생존") else ng("일시 실패까지 닫혔다 — 칸 영구 소실")
if (identical(as.integer(att(2L)$fail_count %||% 0L), 1L)) ok("fail_count 1 증가") else
  ng("fail_count 미증가", as.character(att(2L)$fail_count %||% "NULL"))
rf_record_result(1L, "T_BASE", 2L, grade = "NA (등급 미발행 — 병렬 실행 실패)", terminal = FALSE, root = TROOT)
if (identical(as.integer(att(2L)$fail_count %||% 0L), 2L)) ok("재실패 시 누적(재시도 상한의 축)") else
  ng("누적 실패", as.character(att(2L)$fail_count %||% "NULL"))

cat("=== 5. 측정 성공은 실패로 세지 않는다 ===\n")
rf_record_result(1L, "T_BASE", 3L, grade = "B", essence = list(cell_code = "B1_3", port_t = 2.1),
                 artifacts = "x", root = TROOT)
a3 <- att(3L)
if (is.null(a3$fail_count)) ok("성공 시 fail_count 미발생") else ng("성공을 실패로 셌다", as.character(a3$fail_count))
E <- rf_load(1L, TROOT)$entries[[1]]
ns <- vapply(pending_of(E), function(a) as.integer(a$n), integer(1))
if (!(3L %in% ns)) ok("측정된 칸은 pending 아님") else ng("측정됐는데 재개 대상")

cat("=== 6. 러너가 구조적 실패를 실제로 분류하는가 (배선) ===\n")
body <- paste(sub("#.*$", "", src), collapse = "\n")
if (grepl("측정 무효\\|처치 미전달", body)) ok("구조적 실패 분류 술어 존재(실행 코드)") else
  ng("분류 없음 — 결정론 실패가 다시 무한 재시도된다")
if (grepl("MAX_RETRY", body)) ok("재시도 상한 배선") else ng("상한 없음 — 일시 실패가 무한 재시도된다")
# ★fail_count 를 **스냅샷**에서 읽으면 신규 배치에서 죽는다. main() 초입의 E 는 등록보다
#   앞서 찍혀 새 칸을 모르고, Filter(...)[[1]] 이 subscript 오류를 내 배치 전체가 fatal 로
#   떨어진다(재개분에서만 맞으니 검사 없이는 오래 숨는다 — 이 수리 중 실제로 심었던 결함).
if (grepl("E\\$attempts\\)\\[\\[1\\]\\]\\$fail_count", body))
  ng("fail_count 를 E 스냅샷에서 인덱싱 — 신규 배치에서 fatal") else
  ok("fail_count 를 현재 원장에서 조회(스냅샷 미사용)")
cfg <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)
if (!is.null(cfg$cell_max_retry) && as.integer(cfg$cell_max_retry) >= 1L)
  ok(sprintf("설정에 cell_max_retry=%s", cfg$cell_max_retry)) else ng("설정 항목 없음 — 상한이 코드에 박힌다")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_terminal_retry","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
unlink(TROOT, recursive = TRUE, force = TRUE)   # 명시적 정리(구 on.exit 대체)
quit(status = if (FAIL == 0L) 0L else 1L)
