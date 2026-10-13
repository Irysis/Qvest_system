#!/usr/bin/env Rscript
#==============================================================================
# test_rf_queue_mirror.R — 소비가 **카운터에 닿는가** + 예산이 entry 에서 나오는가
#                          (도훈 지적 2026-09-04)
#
# 실사고 ①: 오늘 논문 5편을 소비했는데 부팅 5줄·텔레그램의 "논문 큐 대기" 가 75 에서
#   하루 종일 안 움직였다. 큐 카운터(alpha_pending)는 alpha_search_queue_done.json 을 보고,
#   강화 레인의 소비는 reinforce_ledger_l1.json 에만 남는다 — **두 원장이 안 이어져 있었다.**
#   이 저장소가 반복해서 데인 형태다(생산자만 있고 소비자가 없는 계기).
#
# 실사고 ②: 예산을 entry 별로 바꿨는데(B1 설계가 격자를 늘리면 25+k-5) 텔레그램은
#   전역 max_attempts=25 를 읽어 "강화 25회 소진" 이라고 했다. 실제로는 34였다.
#   2026-08-31 "20 vs 25" 와 같은 병이고, 이번엔 분모가 entry 마다 다르다.
#
# ★경계 검사(가장 중요): 미러는 **표시용**이다. 소비 판정의 정본은 강화 원장 그대로다.
#   두 곳에서 각자 판정하게 되면 언젠가 갈리고, 갈린 뒤엔 어느 쪽이 맞는지 아무도 모른다.
#
# (v10.01 2026-10-13) 고정 격자 러너 퇴역으로 D절(예산 — entry 에서 나오는가 D1~D3: reinforce_auto_next_paper.R 의
#   소진 entry 예산 재도출 · 그 의미 조건인 운영 원장 실측) 삭제 — 대상 코드가 없다(롤백 태그 pre-v10.01-prescription-20261013).
#   후속 공급자 programs/next_replication.R 은 강화 소진·예산을 다루지 않는다. 미러(A·B)·경계(C — 선택기·검증기 소비 지점)는 그대로 잰다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_queue_done.R"))

# ── 격리 사본에서만 쓴다 — 생산 원장을 검사가 건드리지 않는다 ─────────────────
SB <- file.path(tempdir(), sprintf("qm_%d", Sys.getpid()))
dir.create(file.path(SB, "stage_artifacts/paper_recharge"), recursive = TRUE, showWarnings = FALSE)
QP <- file.path(SB, "stage_artifacts/paper_recharge/alpha_search_queue_done.json")
.reset <- function() write(toJSON(list(processed = list("9999.00001"), records = list(),
  schema_note = "fixture", last_updated = ""), auto_unbox = TRUE, null = "null"), QP)
.read <- function() fromJSON(QP, simplifyVector = FALSE)
.reset()

cat("=== A. 미러가 실제로 기입하는가 (양성 대조) ===\n")
r <- rf_mark_queue_done("2608.12345", "기저 미달 소비", "RP_TEST", root = SB)
d <- .read()
if (isTRUE(r)) ok("A1 기입 성공 보고") else ng("A1 실패 보고")
if ("2608.12345" %in% as.character(unlist(d$processed)))
  ok("A2 processed 에 실제로 들어갔다 ★카운터가 보는 자리") else ng("A2 미기입")
if (length(d$records) == 1L && identical(d$records[[1]]$source, "reinforcement"))
  ok("A3 records 에 출처가 남는다(어디서 온 소비인지 구분 가능)") else ng("A3 출처 미기록")
if (nzchar(as.character(d$last_updated %||% ""))) ok("A4 last_updated 갱신") else ng("A4")

cat("\n=== B. 위반 주입 — 넣으면 안 되는 것 ===\n")
.reset()
r <- rf_mark_queue_done("combo:2608.1+2608.2", "결합", "X", root = SB)
d <- .read()
if (!isTRUE(r) && !any(grepl("^combo:", as.character(unlist(d$processed)))))
  ok("B1 결합은 미러에 안 들어간다 ★결합은 새 논문 소비가 아니다(count_paper=FALSE 와 같은 규약)") else
  ng("B1 결합이 논문 소비로 세어졌다", "큐가 실제보다 빨리 마른다")
r <- rf_mark_queue_done("", "빈 키", "X", root = SB)
if (!isTRUE(r)) ok("B2 빈 paper_key 거부") else ng("B2 빈 키가 통과")
.reset()
rf_mark_queue_done("2608.12345", "1차", "X", root = SB)
n1 <- length(.read()$processed)
rf_mark_queue_done("2608.12345", "2차", "X", root = SB)
n2 <- length(.read()$processed)
if (identical(n1, n2)) ok("B3 중복 기입 없음(재시도가 카운터를 부풀리지 않는다)") else
  ng("B3 중복 누적", sprintf("%d → %d", n1, n2))
r <- rf_mark_queue_done("2608.9", "원장 없음", "X", root = file.path(SB, "nowhere"))
if (!isTRUE(r)) ok("B4 원장 부재 시 조용히 실패(리서치를 안 멈춘다)") else ng("B4")

cat("\n=== C. 경계 — 판정의 정본이 안 옮겨졌는가 (회귀 방지) ===\n")
sel <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/rf_next_paper_pick.py"),
                                       warn = FALSE)), collapse = "\n")
if (grepl("reinforce_ledger", sel, fixed = TRUE))
  ok("C1 선택기는 여전히 **강화 원장**으로 소비를 판단한다 ★미러는 표시용") else
  ng("C1 선택기가 강화 원장을 안 본다", "판정 정본이 흔들렸다")
qd <- paste(readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_queue_done.R"),
                      warn = FALSE), collapse = "\n")
if (grepl("표시용", qd, fixed = TRUE) && grepl("정본은 옮기지 않는다", qd, fixed = TRUE))
  ok("C2 경계가 코드에 적혀 있다(다음 세션이 정본으로 오독하지 않게)") else ng("C2 경계 미기술")
vsrc <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R"),
                        warn = FALSE), collapse = "\n")
if (grepl("qmirror", vsrc, fixed = TRUE) && length(gregexpr("\\.qmirror\\(", vsrc)[[1]]) >= 2L)
  ok("C3 소비 지점 2곳 모두 배선(기저미달·정상개설)") else
  ng("C3 소비 지점 일부 미배선", "한 경로만 카운터에 닿는다")
if (grepl("isTRUE(COUNT_PAPER)", vsrc, fixed = TRUE))
  ok("C4 count_paper 규약을 미러도 따른다") else ng("C4 규약 불일치")

## (v10.01 2026-10-13) D절(예산 — reinforce_auto_next_paper.R 의 소진 entry 예산 재도출 D1~D3) 삭제 — 대상 코드 퇴역.

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_queue_mirror","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
