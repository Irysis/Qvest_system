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

# ── ⑦ 부정 선언이 긍정 매칭으로 뒤집히지 않는다 (2026-08-02 오탐 수리 고정) ──
#   원결함: hay 에 lane 을 넣었고 norm() 이 "_" 를 공백으로 바꾸므로
#   lane="non_return" → 토큰 {non, return} → 그 "return" 이 D1(횡단 return-파생) dead 와
#   매칭됐다. 즉 **비-return 이라고 선언한 FQ 가 그 선언 때문에 return-파생 dead 경고**를
#   받았다(실측 6건 중 5건). v8.3 주력 lane 이 비-return 원천이라 검사기가 전략 방향을
#   정확히 거꾸로 유도하던 상태.
D1 <- dc("D1 횡단 return-파생 single_long_only 전 family")
#   (a) 비-return lane 선언 → return-파생 dead 부적용
r6 <- mk_root(list(qe("FQ-T06", "DART 담보 질권 공시 신호", lane = "non_return",
                      hyp = "비-return 원천 횡단 신호")), list(D1), list(LIVE_CARD))
s6 <- frontier_coherence_scan(r6)
d6 <- if (nrow(s6$rows)) s6$rows[id == "FQ-T06", dead_hit] else character(0)
if (!length(d6) || !nzchar(d6)) {
  ok("negation_not_flipped", "비-return 선언 FQ 에 return-파생 dead 미적용")
} else {
  bad("negation_not_flipped", sprintf("부정 선언이 긍정 매칭으로 뒤집힘: %s", substr(d6, 1, 50)))
}
#   (b) ★검사 사망 통제 — 같은 dead 가 진짜 return-파생 FQ 는 여전히 잡아야 한다.
#       (a) 만 있으면 "return-파생 dead 를 통째로 꺼버린" 수리와 구별되지 않는다.
r7 <- mk_root(list(qe("FQ-T07", "횡단 모멘텀 return 파생 single 신호", lane = "alpha",
                      hyp = "return 파생 횡단 팩터")), list(D1), list(LIVE_CARD))
s7 <- frontier_coherence_scan(r7)
d7 <- if (nrow(s7$rows)) s7$rows[id == "FQ-T07", dead_hit] else character(0)
if (length(d7) && nzchar(d7)) {
  ok("dead_axis_still_alive", "진짜 return-파생 FQ 는 여전히 검출 (오탐 제거 ≠ 검사 사망)")
} else {
  bad("dead_axis_still_alive", "return-파생 dead 축이 통째로 죽음 — 수리가 검사를 껐다")
}

# ── ⑧ 도메인 공통어만 겹치는 카드 매칭은 flag 되지 않는다 (2026-08-02 오탐 수리 고정) ──
#   원결함: card 축이 [신호, ic, port] · [value, 월말, 동일] 같은 **저장소 어디에나 나오는 말**로
#   매칭됐다. 반면 FQ-004↔DIST-AR-018 은 [감사의견, going, concern] 로 주제어가 겹친 정탐이다.
#   수리 = 카드 절반 이상에 등장하는 토큰을 빈도로 걸러낸다(하드코딩 목록은 새 공통어에 무력).
#   ★픽스처 설계 주의: 카드 매칭 문턱이 **3토큰**이므로, 검사 사망 통제(b)의 주제어는
#   불용어를 뺀 뒤에도 3개 이상 남아야 한다. 초판이 2개만 줘서 (b)가 실패했는데
#   그건 수리 결함이 아니라 검사 결함이었다 — 통제를 짤 때 자기 문턱을 볼 것.
COMMON <- c("신호", "port", "ic")   # 픽스처에서 모든 카드가 공유할 공통어
mk_card_n <- function(n, extra) {   # 공통어 + 카드별 고유 주제어 3개
  lapply(seq_len(n), function(i)
    card(sprintf("DIST-C%02d", i), paste(c(COMMON, extra[[i]]), collapse = " ")))
}
TOPICS <- list(c("고유가", "고유나", "고유다"), c("베타가", "베타나", "베타다"),
               c("감마가", "감마나", "감마다"), c("델타가", "델타나", "델타다"))
#   (a) 공통어만 겹치는 FQ → flag 되면 안 된다
cards8 <- mk_card_n(4, TOPICS)
r8 <- mk_root(list(qe("FQ-T08", "신호 port ic 를 쓰는 무관한 항목")), list(dc("D9 무관")), cards8)
s8 <- frontier_coherence_scan(r8)
c8 <- if (nrow(s8$rows)) s8$rows[id == "FQ-T08", card_hit] else character(0)
if (!length(c8) || !nzchar(c8)) {
  ok("common_words_not_flagged", "공통어(신호/port/ic)만 겹치면 미검출")
} else {
  bad("common_words_not_flagged", sprintf("공통어로 오검출: %s", substr(c8, 1, 60)))
}
#   (b) ★검사 사망 통제 — 주제어가 겹치면 여전히 잡아야 한다.
#       (a) 만 있으면 "카드 축을 통째로 꺼버린" 수리와 구별되지 않는다.
r9 <- mk_root(list(qe("FQ-T09", "고유가 고유나 재도전", hyp = "고유다 축 재측정")),
              list(dc("D9 무관")), cards8)
s9 <- frontier_coherence_scan(r9)
c9 <- if (nrow(s9$rows)) s9$rows[id == "FQ-T09", card_hit] else character(0)
if (length(c9) && nzchar(c9)) {
  ok("card_axis_still_alive", "주제어 겹침은 여전히 검출 (오탐 제거 ≠ 검사 사망)")
} else {
  bad("card_axis_still_alive", "카드 축이 통째로 죽음 — 불용어가 과도하다")
}

# ── ⑩ 대상 선정 범위: status 의 frontier_open 이 **접미**여도 스캔 대상인가 ──────
#   실사고(2026-08-02): OPEN 예측자가 startsWith 라 config_scoped_negative_frontier_open(7건)·
#   precheck_negative_frontier_open(1건) = open 후보의 19% 가 **스캔조차 안 됐다**.
#   구판이 signal_round_negative_frontier_open 하나를 손으로 넣어둔 것이 포함 의도의 증거였고,
#   변형이 늘 때마다 손으로 따라가는 구조라 누락이 기본값이었다.
#   실측(같은 코드베이스 like-for-like): 실원장 후보 12 → 19건(신규 7건, FQ-024/026/035/036/
#   037/039/120). ★신규분에 DIST-AR-018 과 주제어 7개가 겹치는 FQ-037 이 포함된다.
#   ★음성 통제 동반 — settled/done 계열까지 빨아들이면 이번엔 반대로 스크린이 노이즈로 죽는다.
r10 <- mk_root(list(qe("FQ-T10a", "오버레이 국면 결합 재시도", status = "config_scoped_negative_frontier_open"),
                    qe("FQ-T10b", "오버레이 국면 결합 재시도", status = "precheck_negative_frontier_open"),
                    qe("FQ-T10c", "오버레이 국면 결합 재시도", status = "settled_negative"),
                    qe("FQ-T10d", "오버레이 국면 결합 재시도", status = "done_consumed")),
               list(dc("D2 시장타이밍 오버레이 초월 국면")), list(LIVE_CARD))
s10 <- frontier_coherence_scan(r10)
got10 <- if (is.null(s10$rows) || !nrow(s10$rows)) character(0) else s10$rows$id
if (all(c("FQ-T10a", "FQ-T10b") %in% got10)) {
  ok("open_status_suffix_in_scope", "frontier_open 이 접미인 status 도 스캔 대상")
} else {
  bad("open_status_suffix_in_scope",
      sprintf("접미형 누락 — 대상 선정이 19%%를 조용히 버린다 (검출=%s)", paste(got10, collapse = ",")))
}
if (!any(c("FQ-T10c", "FQ-T10d") %in% got10)) {
  ok("settled_status_excluded", "settled/done 계열은 여전히 제외 (범위 과확장 아님)")
} else {
  bad("settled_status_excluded",
      sprintf("확정 항목이 대상에 편입됨 — 스크린이 노이즈로 무력화 (검출=%s)", paste(got10, collapse = ",")))
}

unlink(c(r1, r2, r3, r4, r5, r6, r7, r8, r9, r10), recursive = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "frontier_coherence", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
