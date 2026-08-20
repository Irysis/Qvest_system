#!/usr/bin/env Rscript
# test_frontier_citation_scan.R — CIT-1 인용 검증 스캔의 위반 주입 테스트 (2026-08-08).
#
# 왜 있나: 2026-08-08 FQ-096 사전확인이 "풀 천장 2.937"을 원장에서 밟지 못하고
#   큐 본문 서술에만 의존했다. 원인은 인덱싱 누락이 아니라 **네임스페이스 불일치** —
#   큐는 세션-로컬 별칭(`WT-002`)을 쓰는데 원장 strategy_id 에 그 형식은 0건이다.
#   `frontier_citation_scan()` 이 그 상태를 실제로 잡는지 확인한다.
#
# ★설계 축 (오늘 반복 확인: "발화했다 ≠ 옳은 걸 쟀다"):
#   (A) clean 선확인 — 전체형 인용이 원장에 실재하면 **발화하지 않아야** 한다.
#       이게 없으면 "전건 발화하는 검사기"가 통과해버린다.
#   (B) 별칭 미해소 검거 — 같은 항목에 대응 전체형이 없으면 잡는다.
#   (C) ★별칭 해소 시 **불발화** — 같은 항목 문맥에 끝번호가 맞는 전체형이 있으면
#       무해하므로 잡으면 안 된다. 이 축이 없으면 별칭만 보고 다 잡는 검사가 통과한다.
#   (D) 원장 부재 전체형 검거 — 형식은 맞지만 원장에 없는 ID.
#   (E) 빈 입력 = 0건 (0을 결함으로 세지 않음).
#   돌연변이: 원장에서 해당 ID 를 지우면 (A) 가 발화로 바뀌어야 한다 — 검출력 실증.

.root <- local({
  .marker <- file.path("02_Infrastructure", "ops", "frontier_registry_coherence.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
})
suppressMessages({ library(data.table); library(jsonlite) })
PASS <- 0; FAIL <- 0
ok  <- function(m) { PASS <<- PASS + 1; cat(sprintf("  [PASS] %s\n", m)) }
bad <- function(m, d) { FAIL <<- FAIL + 1; cat(sprintf("  [FAIL] %s — %s\n", m, d)) }

TARGET <- file.path(.root, "02_Infrastructure", "ops", "frontier_registry_coherence.R")
if (!file.exists(TARGET)) { cat("FATAL: 대상 부재:", TARGET, "\n"); quit(status = 2) }
# 모듈 로드 (main-guard 가 --file 로 자기 자신을 확인하므로 source 시 CLI 는 안 돈다)
source(TARGET)
if (!exists("frontier_citation_scan")) {
  cat("FATAL: frontier_citation_scan 미정의\n"); quit(status = 2)
}

# ── 픽스처: 임시 루트에 큐/원장 최소본을 만든다 ──────────────────────────────
mk <- function(entries, ledger_ids) {
  d <- file.path(tempdir(), paste0("cit_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(file.path(d, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(entries = entries), auto_unbox = TRUE, pretty = TRUE, digits = NA),
        file.path(d, "06_Registry/alpha_frontier_queue.json"))
  write(toJSON(list(entries = lapply(ledger_ids, function(i) list(strategy_id = i))),
               auto_unbox = TRUE, pretty = TRUE, digits = NA),
        file.path(d, "06_Registry/hypothesis_index.json"))
  d
}
flagged <- function(res, id) id %in% (if (nrow(res$rows)) res$rows$id else character(0))

cat("== (A) clean: 전체형 인용이 원장에 실재 -> 불발화 ==\n")
rA <- frontier_citation_scan(mk(
  list(list(id = "FQ-A", title = "clean", status = "frontier_open",
            ev_rationale = "WT-D20260802_003 실측 근거")),
  c("WT-D20260802_003_alpha")))
if (!flagged(rA, "FQ-A")) ok("전체형 + 원장 실재 -> 미발화") else
  bad("clean 오발화", "원장에 있는 전체형인데 잡음 — 전건 발화 검사기 의심")

cat("== (B) 별칭 미해소 검거 ==\n")
rB <- frontier_citation_scan(mk(
  list(list(id = "FQ-B", title = "alias only", status = "frontier_open",
            ev_rationale = "WT-014 에서 측정한 결과")),
  c("WT-D20260802_014_x")))
if (flagged(rB, "FQ-B")) ok("문맥 없는 별칭 -> 검거") else
  bad("별칭 미검거", "같은 항목에 대응 전체형이 없는데 안 잡음")

cat("== (C) ★별칭이 문맥으로 해소되면 불발화 ==\n")
rC <- frontier_citation_scan(mk(
  list(list(id = "FQ-C", title = "alias resolved", status = "frontier_open",
            ev_rationale = "WT-014(=WT-D20260802_014) 실측")),
  c("WT-D20260802_014_x")))
if (!flagged(rC, "FQ-C")) ok("끝번호 대응 전체형 동반 -> 미발화") else
  bad("해소된 별칭 오발화", "문맥으로 해소되는데 잡음 — 별칭만 보고 다 잡는 검사")

cat("== (D) 원장 부재 전체형 검거 ==\n")
rD <- frontier_citation_scan(mk(
  list(list(id = "FQ-D", title = "ghost id", status = "frontier_open",
            ev_rationale = "WT-D20260715_099 근거")),
  c("WT-D20260802_003_alpha")))
if (flagged(rD, "FQ-D")) ok("원장에 없는 전체형 -> 검거") else
  bad("유령 ID 미검거", "형식은 맞으나 원장 부재인데 안 잡음")

cat("== (E) 인용 없는 항목 = 0건 ==\n")
rE <- frontier_citation_scan(mk(
  list(list(id = "FQ-E", title = "no citation", status = "frontier_open",
            ev_rationale = "인용 없음")), c("WT-D20260802_003_alpha")))
if (rE$n_flag == 0L) ok("인용 0 -> 0건 (0을 결함으로 세지 않음)") else
  bad("빈 입력 오발화", sprintf("n_flag=%d", rE$n_flag))

cat("== (F) 돌연변이: 원장에서 해당 ID 제거 -> (A)가 발화로 전환 ==\n")
rF <- frontier_citation_scan(mk(
  list(list(id = "FQ-A", title = "clean", status = "frontier_open",
            ev_rationale = "WT-D20260802_003 실측 근거")),
  c("WT-D20260101_001_other")))
if (flagged(rF, "FQ-A")) ok("원장에서 지우니 발화 (검출력 실증)") else
  bad("돌연변이 미검출", "원장에 없는데도 통과 — 검사가 원장을 실제로 안 봄")

cat(sprintf("\nFINAL: PASS=%d FAIL=%d\n", PASS, FAIL))
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 미편입 상태였다.
cat(sprintf("{\"test\":\"test_frontier_citation_scan\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0) 1 else 0)
