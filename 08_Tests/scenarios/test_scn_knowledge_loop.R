#!/usr/bin/env Rscript
#==============================================================================
# test_scn_knowledge_loop.R — v10.2 재귀적 개선 고리 운영 시나리오 (감사 레인 K · 2026-11-10)
#   격리: 임시 루트(behavior_card · rx_generator 사본 · 합성 원장) · 운영 원장 · 등록부 무쓰기 · 네트워크 · 텔레그램 · 측정 없음.
#   round_core 는 읽기 전용(정본 코드 적재만) — 실패는 'GAP'(패치 제안 대상)으로 따로 센다(fail 아님).
#   L1 라운드 닫기(탐침 2 · 교훈 1 · r7) → 결과 원장 1줄 → rc_outcomes_md 에 교훈 · 탐침 → rc_open_probes 2
#   L2 P4 사슬 닫기 기록 → 생성기 검토(rc_p4_generator_review) 결과 원장 절에 그 교훈
#   L3 설계 입력 배선 — rc_p4_design_input 이 rc_open_probes · rc_outcomes_md 를 싣는다(소스) · 과거 negative(hypothesis_index)는 안 싣는다(GAP)
#   L4 같은 닫기 두 번 → 원장 1줄(멱등)            L5 탐침 0개 · 사유 없음 → 거부 / 사유 있으면 기록
#   L6 교훈에 τ_D 뒤 날짜(YYYY-MM-DD · YYYY-MM) → 거부 · 다른 표기(2023년 3월 · 2024/05)는 통과(GAP)
#   L7 원장 줄 깨짐 → 판정 경로(rc_outcomes_read) 멈춤 · 계기(klm_collect) 손상 1줄 경고
#   L8 탐침 이어받기 두 번 → 두 번째 거부 · 열린 탐침 감소 · 자동 이어받기 호출처 0(GAP)
#   L9 생성기 개정 근거 = 결과 원장에 없는 id → 거부 / 있는 id → 다음 관문(철학 영수증)까지 감
#   L10 교훈에 '등급 C' 표기 → 기록은 받아들여짐 → 이후 생성기 검토가 멈춤(쓰기 · 읽기 검사 비대칭 = 원장 독살 GAP)
#   K1 계기: 주별 표(라운드 1 · 사슬 1 · 탐침) · 개정 근거로 안 쓴 사슬 1 → 근거 등록 뒤 0 · 허용 목록 밖 열 거부(돌연변이)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
self <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
CR <- gsub("\\", "/", dirname(dirname(dirname(self))), fixed = TRUE)
if (!file.exists(file.path(CR, "04_Research/programs/_lib/round_core/v1/load.R"))) stop("코드 루트 해석 실패: ", CR)
PASS <- 0L; FAIL <- 0L; GAP <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
gap <- function(m) { GAP <<- GAP + 1L; cat("  GAP ", m, "\n") }
chk <- function(c, m, why = "") if (isTRUE(c)) ok(m) else ng(m, why)
err <- function(expr) tryCatch({ force(expr); "no_stop" }, error = function(e) conditionMessage(e))

S <- gsub("\\", "/", file.path(tempdir(), sprintf("scn_kloop_%d", Sys.getpid())), fixed = TRUE)
dir.create(file.path(S, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(CR, "06_Registry/behavior_card.json"), file.path(S, "06_Registry/behavior_card.json"))
gdir <- file.path(S, "04_Research/programs/P4_ASSEMBLY/_generator/g1"); dir.create(gdir, recursive = TRUE, showWarnings = FALSE)
writeLines("# 생성기 g1 (시험)", file.path(gdir, "step.md"))
write_json(list(schema = "rx_generator_v1", current = "g1",
                versions = list(list(id = "g1", dir = "04_Research/programs/P4_ASSEMBLY/_generator/g1",
                                     files = list(step.md = unname(tools::md5sum(file.path(gdir, "step.md")))),
                                     created_at = "2026-11-01T00:00:00+0900", reason = "첫 판", evidence = list()))),
           file.path(S, "06_Registry/rx_generator.json"), auto_unbox = TRUE, pretty = TRUE)
OP <- file.path(S, "06_Registry/round_outcomes.jsonl")
pre <- file.path(S, "prereg.md"); writeLines("prereg", pre)

invisible(capture.output(suppressMessages(source(file.path(CR, "04_Research/programs/_lib/round_core/v1/load.R")))))
chk(exists("rc_outcome_record") && exists("rc_p4_generator_review") && exists("rxg_revise"), "round_core v1 적재(읽기 전용)")
tau <- "2022-12-31"
spec <- function(id, program = "P2_DEFENSE", template = "p2_device")
  list(program = program, round_id = id, template = template, tau_d = tau, cells = list(list(code = "c0", role = "reference"), list(code = "c1", role = "variant")))
rec_of <- function(id, ..., program = "P2_DEFENSE", template = "p2_device", label = "판정 라벨")
  rc_outcome_record(spec(id, program, template), list(summary = list(label = label)), note = "해석 한 줄", P = list(prereg = pre, results = S), root = S, ...)

cat("\n[L1] 라운드 닫기 → 결과 원장 → 다음 설계 입력\n")
r1 <- rec_of("P2R90_test", probes = c("탐침 A: 하락 국면 노출 경로", "탐침 B: 위기 하락 포착 분해"), lessons = "교훈: 정적 노출 축소는 비대칭을 못 만든다", r7 = "noise")
chk(isTRUE(rc_outcome_append_round(r1, OP)), "L1a 결과 원장에 1줄 추가")
md <- paste(rc_outcomes_md(OP, "P2_DEFENSE"), collapse = "\n")
chk(grepl("정적 노출 축소", md, fixed = TRUE) && grepl("P2R90_test#1", md, fixed = TRUE) && grepl("P2R90_test#2", md, fixed = TRUE), "L1b 설계 입력 md 에 교훈 · 탐침 2")
chk(length(rc_open_probes(OP)) == 2L && rc_r7_streak(OP, "P2_DEFENSE") == 1L, "L1c 열린 탐침 2 · 연속 잡음 1")

cat("\n[L2] P4 사슬 닫기 → 생성기 검토\n")
r2 <- rec_of("P4C90", program = "P4_ASSEMBLY", template = "p4_chain", probes = c("가중 블록 다른 기전", "기저 교체"),
             lessons = "교훈: tail_overlay 연속 기각 — 보는 창 위기 수 부족", r7 = "noise", label = "사슬 P4C90 — 걸음 3(채택 0 · 기각 3)")
rc_outcome_append_round(r2, OP)
gr <- tryCatch(rc_p4_generator_review(root = S, chain_dirs = character(0), outcomes_path = OP), error = function(e) e)
chk(!inherits(gr, "error") && grepl("tail_overlay 연속 기각", gr$md, fixed = TRUE), "L2 생성기 검토 결과 원장 절에 사슬 교훈",
    if (inherits(gr, "error")) conditionMessage(gr) else "")

cat("\n[L3] 설계 입력 배선(소스 대조)\n")
p4src <- paste(deparse(rc_p4_design_input), collapse = "\n")
chk(grepl("rc_open_probes(op)", p4src, fixed = TRUE) && grepl("rc_outcomes_md(op", p4src, fixed = TRUE), "L3a rc_p4_design_input 이 열린 탐침 · 결과 원장 요약을 싣는다")
if (!grepl("hypothesis_index|lookup_hypothesis", p4src)) gap("L3b 설계 입력에 과거 negative(hypothesis_index) 없음 — 생성기는 design_input.md 밖을 못 본다(step.md §입력)")
if (!grepl("generator_review|other_chain|rc_p4_generator_review", p4src)) gap("L3c 설계 입력에 다른 사슬의 걸음(같은 블록 기각 사유) 없음 — 이 사슬 이력(§4)만")

cat("\n[L4] 같은 닫기 두 번 → 멱등\n")
n0 <- length(readLines(OP)); chk(isFALSE(rc_outcome_append_round(r1, OP)) && length(readLines(OP)) == n0, "L4 두 번째 닫기는 원장에 안 쓴다")

cat("\n[L5] 탐침 0개\n")
chk(grepl("2개 미만", err(rec_of("P2R91", probes = character(0)))), "L5a 탐침 0 · 사유 없음 → 거부")
r5 <- tryCatch(rec_of("P2R91", probes = character(0), no_probes_reason = "프로그램 종료 — 목표 축 예산 소진"), error = function(e) e)
chk(!inherits(r5, "error") && identical(r5$no_probes_reason, "프로그램 종료 — 목표 축 예산 소진"), "L5b 사유 있으면 기록")

cat("\n[L6] 교훈의 τ_D 뒤 날짜\n")
chk(grepl("정보 경계", err(rec_of("P2R92", probes = c("a", "b"), lessons = "2023-03-15 급락에서 방어"))), "L6a YYYY-MM-DD 거부")
chk(grepl("정보 경계", err(rec_of("P2R92", probes = c("a", "b"), lessons = "2024-06 급락 구간"))), "L6b YYYY-MM 거부")
for (s in c("2023년 3월 급락에서 방어 성공", "2024/05 반등 구간", "2025년 하반기 강세장"))
  if (identical(err(rec_of("P2R92", probes = c("a", "b"), lessons = s)), "no_stop")) gap(sprintf("L6c τ_D 뒤 표기 '%s' 가 결과 원장 검사를 통과(rc_after_tau_leaks 는 YYYY-MM[-DD] 만)", s))

cat("\n[L7] 원장 줄 깨짐\n")
OPb <- file.path(S, "bad_outcomes.jsonl"); invisible(file.copy(OP, OPb)); cat("{\"schema\":\"round_outcome_v1\",\"kind\":\"round\",\"round_id\":\n", file = OPb, append = TRUE)
chk(grepl("판독 불가", err(rc_outcomes_read(OPb))), "L7a 판정 경로는 손상에서 멈춘다(추가 전용 원장)")
source(file.path(CR, "02_Infrastructure/memory/knowledge_loop_metrics.R"))
evb <- klm_collect(S, outcomes_path = OPb, standing_files = character(0), lane_log = file.path(S, "none.jsonl"))
fb <- klm_format(klm_weekly(evb, 2, now = Sys.time()), klm_snapshot(evb, S))
chk(evb$bad[["outcomes"]] == 1L && grepl("원장 손상", fb[1], fixed = TRUE), "L7b 계기는 멈추지 않고 손상 1줄을 첫 줄에 경고")
gap("L7c 손상 줄 하나가 모든 설계 입력 · 생성기 검토를 멈춘다 — 수리 도구(격리 · 재작성 절차) 없음")

cat("\n[L8] 탐침 이어받기\n")
rc_probe_consume("P2R90_test#1", "P2R93", OP)
chk(length(rc_open_probes(OP, "P2_DEFENSE")) == 1L, "L8a 이어받은 탐침은 열린 목록에서 빠진다")
chk(grepl("이미 이어받은", err(rc_probe_consume("P2R90_test#1", "P2R94", OP))), "L8b 같은 탐침 두 번 → 거부")
callers <- vapply(c("p4.R", "register.R", "driver.R", "standing.R"), function(f)
  sum(grepl("rc_probe_consume(", readLines(file.path(CR, "04_Research/programs/_lib/round_core/v1", f), warn = FALSE), fixed = TRUE)), 0L)
if (sum(callers) == 0L) gap("L8c rc_probe_consume 를 부르는 운영 경로 0 — 걸음 열기 · 라운드 등록이 이어받은 탐침을 표시하지 않는다(열린 탐침이 줄지 않음)")

cat("\n[L9] 생성기 개정 근거\n")
g2 <- file.path(S, "04_Research/programs/P4_ASSEMBLY/_generator/g2"); dir.create(g2, showWarnings = FALSE); writeLines("# g2 다른 본문", file.path(g2, "step.md"))
GP <- file.path(S, "06_Registry/rx_generator.json")
e9a <- err(rxg_revise(g2, reason = "기각 사유 반영", evidence = "NOPE_ROUND", root = S, path = GP, outcomes_path = OP))
chk(grepl("결과 원장에 없는", e9a), "L9a 원장에 없는 근거 id → 거부", e9a)
e9b <- err(rxg_revise(g2, reason = "기각 사유 반영", evidence = "P4C90", root = S, path = GP, outcomes_path = OP, ledger = file.path(S, "ql.json")))
chk(!grepl("결과 원장에 없는", e9b) && !identical(e9b, "no_stop"), "L9b 원장에 있는 근거 → 근거 검사 통과(다음 관문 = 철학 영수증에서 멈춤)", e9b)

cat("\n[L10] 교훈의 등급 표기 — 쓰기 · 읽기 검사 비대칭\n")
OPg <- file.path(S, "grade_outcomes.jsonl"); invisible(file.copy(OP, OPg))
r10 <- tryCatch(rec_of("P4C91", program = "P4_ASSEMBLY", template = "p4_chain", probes = c("a", "b"), lessons = "기저는 등급 C 에 머물렀다"), error = function(e) e)
if (!inherits(r10, "error")) {
  rc_outcome_append_round(r10, OPg)
  g10 <- tryCatch(rc_p4_generator_review(root = S, chain_dirs = character(0), outcomes_path = OPg), error = function(e) conditionMessage(e))
  if (is.character(g10) && grepl("등급 표기", g10)) gap("L10 '등급 C' 교훈이 결과 원장에 기록된 뒤 생성기 검토 · 설계 입력이 영구히 멈춘다(rc_outcome_record 에 등급 표기 검사 없음 · 추가 전용)")
  else ok("L10 등급 표기 교훈이 생성기 검토를 멈추지 않는다")
} else ok("L10 등급 표기 교훈은 기록 단계에서 거부된다")

cat("\n[K1] 계기 — 주별 표 · 개정 대기\n")
ev <- klm_collect(S, outcomes_path = OP, standing_files = character(0), lane_log = file.path(S, "none.jsonl"))
tb <- klm_weekly(ev, 2)
chk(sum(tb$rounds_closed) == 1L && sum(tb$chains_closed) == 1L && sum(tb$probes_new) == 4L && sum(tb$probes_consumed) == 1L, "K1a 라운드 1 · 사슬 1 · 새 탐침 4 · 이어받음 1",
    paste(capture.output(print(tb[, 1:5])), collapse = " / "))
sn <- klm_snapshot(ev, S, generator_path = GP)
chk(sn$unreviewed_closed_chains == 1L && sn$open_probes == 3L, "K1b 개정 근거로 안 쓴 닫힌 사슬 1 · 열린 탐침 3")
G <- fromJSON(GP, simplifyVector = FALSE); G$versions[[1]]$evidence <- list("P4C90"); write_json(G, GP, auto_unbox = TRUE, pretty = TRUE)
chk(klm_snapshot(ev, S, generator_path = GP)$unreviewed_closed_chains == 0L, "K1c 근거로 쓰이면 0")
tb2 <- tb; tb2$cagr <- 0.2
chk(grepl("허용 목록 밖", err(klm_assert_clean(tb2))), "K1d [돌연변이] 성과 열(cagr)이 끼면 거부")
# 레인 저널 · 걸음 원장 · 상설 원장 합성
LL <- file.path(S, "lane.jsonl"); now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+0900")
writeLines(c(sprintf('{"ts":"%s","event":"preaudit","rc":"0","result":"action=proceed"}', now),
             sprintf('{"ts":"%s","event":"preaudit","rc":"10","result":"action=reimplement"}', now),
             sprintf('{"ts":"%s","event":"fidelity_audit_verdict","action":"proceed","retries":0}', now)), LL)
SL <- file.path(S, "stage_artifacts/programs/P1_RETURN/P1S01/standing_ledger.jsonl"); dir.create(dirname(SL), recursive = TRUE, showWarnings = FALSE)
writeLines(sprintf('{"schema":"rc_standing_ledger_v1","at":"%s","event":"verdict","code":"e1","qualify":true}', now), SL)
tb3 <- klm_weekly(klm_collect(S, outcomes_path = OP, lane_log = LL), 1)
chk(tb3$standing_qualified == 1L &&
      tb3$preaudit_n == 2L && tb3$first_pass_rate == 0.5 && tb3$fidelity_first_pass == 1L, "K1e 상설 자격 · 1차 통과율(걸음 지표는 rxg_scorecard 정본)",
    paste(capture.output(print(tb3)), collapse = " / "))
chk(!any(grepl("(^|_)(ds|cagr|sharpe|calmar|grade|mdd)(_|$)", names(tb3), ignore.case = TRUE)), "K1f 출력 열에 성과 수치 없음")

unlink(S, recursive = TRUE)
cat(sprintf('{"test":"test_scn_knowledge_loop","pass":%d,"fail":%d,"total":%d,"gap":%d}\n', PASS, FAIL, PASS + FAIL, GAP))
quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
