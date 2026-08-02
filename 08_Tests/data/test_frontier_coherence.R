#==============================================================================
# test_frontier_coherence.R — 원장 3종 정합 스크린 검사기 (합성 픽스처)
#
# 2026-08-02 신설. 대상: 02_Infrastructure/ops/frontier_registry_coherence.R
# 근거: 같은 날 3회 근접 사고(FQ-095 / FQ-004 x2)를 기계 스크린으로 전환한 도구.
#
# ★이 검사기의 존재 이유: 스크린 초판이 distilled 카드 축에서 **0건**을 반환했고
#   그 0 이 '충돌 없음'으로 읽혔다(verdict 필드가 없는데 verdict 로 걸렀다).
#   즉 도구 자신이 이 저장소 반복 결함("빈 결과 = 합격")을 재현했다.
#   → 카드 0건은 이제 stop 이며, 그 차단 실효를 여기서 실측한다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })

.t_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
PROJ <- .t_root(); setwd(PROJ)
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
cat("=== frontier registry coherence (합성 픽스처) ===\n")

source(file.path(PROJ, "02_Infrastructure/ops/frontier_registry_coherence.R"), encoding = "UTF-8")

# 픽스처 루트: 함수가 <root>/06_Registry/*.json 을 읽으므로 그 형태만 갖추면 된다.
# marker 파일도 만들어 .fc_root() 계약과 어긋나지 않게 한다(여기선 root 를 인자로 넘기지만).
mk_root <- function(queue_entries, dead_classes, cards) {
  r <- file.path(tempdir(), paste0("fcx_", as.integer(Sys.time()), "_", sample(1e6, 1)))
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(r, "02_Infrastructure/hooks"), recursive = TRUE, showWarnings = FALSE)
  writeLines("x", file.path(r, "02_Infrastructure/hooks/qvest_hook_router.py"))
  write_json(list(entries = queue_entries), file.path(r, "06_Registry/alpha_frontier_queue.json"),
             auto_unbox = TRUE)
  write_json(list(dead_classes = dead_classes),
             file.path(r, "06_Registry/research_ev_map.json"), auto_unbox = TRUE)
  write_json(list(entries = cards), file.path(r, "06_Registry/distilled_knowledge.json"),
             auto_unbox = TRUE)
  r
}
qe <- function(id, title, lane = "x", status = "frontier_open", hyp = "")
  list(id = id, title = title, lane = lane, status = status, hypothesis = hyp)
dc <- function(cls) list(class = cls, verdict = "dead")
card <- function(id, stmt, polarity = "negative", status = "distilled", expiry = "2099-01-01")
  list(dist_id = id, polarity = polarity, status = status,
       statement_refined = stmt, family = "x", expiry = expiry)

LIVE_CARD <- card("DIST-TEST-001", "오버레이 국면 결합 시장타이밍 초월 실패")

# ── ① 위반 주입: dead 계급과 토큰 2개 이상 겹치는 open 항목 ──────────────────
r1 <- mk_root(list(qe("FQ-T01", "오버레이 국면 결합 재시도")),
              list(dc("D2 시장타이밍 오버레이 초월 국면")), list(LIVE_CARD))
s1 <- frontier_coherence_scan(r1)
if (s1$n_flag >= 1L && "FQ-T01" %in% s1$rows$id) {
  ok("injection_dead_class", "dead 계급 저촉 항목 검출")
} else {
  bad("injection_dead_class", sprintf("검출 실패 (n_flag=%d) — 스크린 무력", s1$n_flag))
}

# ── ② 위양성 통제: 겹침 없는 항목은 잡히면 안 된다 ──────────────────────────
r2 <- mk_root(list(qe("FQ-T02", "계약금액 공시 규모 신호")),
              list(dc("D2 시장타이밍 오버레이 초월 국면")), list(LIVE_CARD))
s2 <- frontier_coherence_scan(r2)
if (s2$n_flag == 0L) {
  ok("false_positive_control", "무관 항목 오검출 0")
} else {
  bad("false_positive_control", sprintf("무관 항목이 %d건 잡힘: %s", s2$n_flag,
                                        paste(s2$rows$id, collapse = ",")))
}

# ── ③ 카드 축 차단 실효: negative·distilled 카드 0건이면 stop 이어야 한다 ────
r3 <- mk_root(list(qe("FQ-T03", "무엇이든")), list(dc("D9 무관")),
              list(card("DIST-P", "양성 카드", polarity = "positive")))
e3 <- tryCatch({ frontier_coherence_scan(r3); "NO_STOP" }, error = function(e) conditionMessage(e))
if (grepl("카드 0건", e3)) {
  ok("card_axis_death_blocked", "카드 0건 → stop (0 을 '충돌 없음'으로 흘리지 않음)")
} else {
  bad("card_axis_death_blocked", sprintf("0건인데 통과: %s", substr(e3, 1, 60)))
}

# ── ④ 만료 카드는 게이트하지 않는다 ─────────────────────────────────────────
r4 <- mk_root(list(qe("FQ-T04", "x")), list(dc("D9 무관")),
              list(card("DIST-EXP", "만료된 부정 카드", expiry = "2020-01-01")))
e4 <- tryCatch({ frontier_coherence_scan(r4); "NO_STOP" }, error = function(e) conditionMessage(e))
if (grepl("카드 0건", e4)) {
  ok("expired_card_not_gating", "만료 카드는 유효 카드로 세지 않음")
} else {
  bad("expired_card_not_gating", sprintf("만료 카드가 게이트에 계상됨: %s", substr(e4, 1, 60)))
}

# ── ⑤ 입력 부재를 '이상 없음'으로 흘리지 않는다 ─────────────────────────────
r5 <- file.path(tempdir(), paste0("fcempty_", as.integer(Sys.time())))
dir.create(file.path(r5, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
e5 <- tryCatch({ frontier_coherence_scan(r5); "NO_STOP" }, error = function(e) conditionMessage(e))
if (grepl("입력 부재", e5)) {
  ok("missing_input_refused", "원장 부재 → stop")
} else {
  bad("missing_input_refused", sprintf("부재인데 통과: %s", substr(e5, 1, 60)))
}

# ── ⑥ 회귀: 실제 원장에서 오늘의 근접사고(FQ-004)를 재현하는가 ──────────────
sr <- tryCatch(frontier_coherence_scan(PROJ), error = function(e) NULL)
if (is.null(sr)) {
  bad("live_registry_scan", "실제 원장 스캔 실패")
} else if ("FQ-004" %in% sr$rows$id) {
  ok("live_registry_scan", sprintf("FQ-004 검출 (총 %d건 후보)", sr$n_flag))
} else {
  bad("live_registry_scan",
      sprintf("FQ-004 미검출 — 2026-08-02 수동 게이트가 잡은 건을 기계가 못 잡음 (n=%d)", sr$n_flag))
}

unlink(c(r1, r2, r3, r4, r5), recursive = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "frontier_coherence", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
