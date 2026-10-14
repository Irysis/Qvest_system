#!/usr/bin/env Rscript
#==============================================================================
# rf_replication_verify.R — 무인 충실구현 **측정 + 검증 게이트** (2026-08-30)
#
# 호출자 = rf_replication_auto.sh (헤드리스 에이전트가 engine.R 을 쓴 직후)
#
# ★이 파일이 판정한다 — 에이전트 진술은 근거가 아니다(AX-008: 산출은 Forge).
#   에이전트가 만든 건 엔진 하나뿐이고, 아래 전부가 기계 재도출이다:
#     ① run_paper_replication 계약 실행 → authoritative_remeasure.json
#     ② 고정 축 재도출 (n_max ≤ 25 · long-only)
#     ③ PIT 정적 검사 + **구조 검사**(정적 검사의 사각을 안다 — CLEAN 을 증명으로 안 쓴다)
#   하나라도 어기면 원장에 열지 않고 세션 대기로 되돌린다. **조용한 통과 없음.**
#
# 통과 시: rf_open_entry 로 새 강화 entry 개설 → 다음 tick 부터 강화 20칸이 무인 재개.
# ★청정 모드(RP_LANE_MODE=clean · 결정 FA-CLEAN-BASE-PATH 2026-09-26): ④ 감사만 달라진다 — 산출물 경로 비공개 + 스폰 한 번에만
#   가드 표식 · 재구현을 부르면 감사 원천을 .clean_audit_src/r<n> 에 보존하고 요청에 audit_feedback_mode 를 남긴다(도우미 rf_clean_lane_lib.R).
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# ── 큐 소비 미러 (도훈 2026-09-04) ────────────────────────────────────────────
#   큐 카운터(alpha-pending)는 alpha_search_queue_done.json 만 본다. 강화 레인의 소비는
#   강화 원장에만 남아 두 원장이 안 이어져 있었다 — 오늘 5편을 소비했는데 카운터는 75 그대로.
#   ★판정의 정본은 옮기지 않는다. 이건 표시용 미러이고, 실패해도 리서치를 멈추지 않는다.
.qmirror <- function(pk, why, sid = "") tryCatch({
  if (!isTRUE(COUNT_PAPER)) return(invisible(FALSE))   # 결합은 새 논문 소비가 아니다
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_queue_done.R")))
  okm <- rf_mark_queue_done(pk, why, sid, root = ROOT)
  jlog(if (isTRUE(okm)) "queue_done_mirrored" else "queue_done_mirror_skip",
       paper_key = as.character(pk %||% ""), note = why)
}, error = function(e) jlog("queue_done_mirror_failed", err = conditionMessage(e)))
## (v10.01 2026-10-13) 구 .RF_MAXA(강화 칸 상한 — 알림 문구용) 삭제: 고정 격자 강화 퇴역으로 쓰는 곳이 없다.
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
WDIR  <- Sys.getenv("RP_WDIR"); URL <- Sys.getenv("RP_URL")
TITLE <- Sys.getenv("RP_TITLE"); PKEY <- Sys.getenv("RP_KEY")
# ★결합 판 (2026-09-04) — 결합은 새 논문 소비가 아니라 기존 두 논문의 재조합이므로
#   3편 주기(count_paper)를 건드리지 않는다. 나머지 경로는 단독 논문과 완전히 같다 —
#   같은 계약이 재고 같은 게이트가 막는다. 그게 이 재사용의 요점이다.
IS_COMBO <- identical(Sys.getenv("RP_IS_COMBO", "0"), "1")
COUNT_PAPER <- !identical(Sys.getenv("RP_COUNT_PAPER", "1"), "0")

# ★텔레그램 '대상:' 줄 — 결합 제목이 잘려 재료가 사라지던 것 수리 (도훈 지적 2026-09-10) ────
#   결합 요청의 RP_TITLE 은 "결합: <제목1> + <제목2> + <제목3>" 연접이라 171자였고,
#   호출부가 전부 substr(TITLE, 1, 52~78) 로 선잘라 **2·3번째 논문이 통째로 사라졌다**.
#   ⚠원인이 발신기 상한이 아니다: tg_agent_brief 는 relaxed=TRUE 에서 BULLET_ITEM_MAX(80자)
#     가드를 면제한다(telegram_notify.R:1367-1374 "영어 논문 제목 허용"). 이 파일의 모든
#     브리핑이 relaxed=TRUE 이므로 자를 이유가 처음부터 없었다 — 방어적 선절단이 정보를 지웠다.
#   ⇒ 결합이면 재료 한 편당 한 줄로 편다(각 줄은 짧아 모바일 한 줄에 들어간다).
#     단독이면 넉넉한 상한을 쓰되 **잘렸으면 '…' 로 보이게** 한다(구판은 말없이 잘랐다).
.tg_clip <- function(x, cap) {
  x <- gsub("[\r\n]+", " ", as.character(x %||% ""))
  if (nchar(x) <= cap) x else paste0(substr(x, 1L, cap - 1L), "…")
}
#   ⚠키-제목 짝은 **연접 제목을 쪼개서 만들지 않는다**. paper_key 는 키를 정렬해 붙이고
#     (combo:1403.8125+2301.09173+2404.08129) 제목은 combo.papers 순서로 이어 붙이는데
#     둘이 서로 다른 순서다 — 위치로 짝지으면 1403.8125 에 2404.08129 의 제목이 붙는다
#     (드라이런 2026-09-10 실측). 잘림보다 나쁜 오귀속이라, 짝은 요청 파일의
#     combo.papers(key+title 쌍)에서만 읽고, 없으면 키만 낸다.
#   ★짝 원본은 **가변 슬롯**이다(2026-09-13 검사 신설 중 실측) — 요청 파일은 다음 요청이 덮는다.
#     구판은 편수만 맞춰 보고 짝을 믿어서, 같은 3편짜리 **다른** 결합이 슬롯에 있으면 남의 논문
#     3편을 이 결합 아래에 냈다. 키 **집합**이 paper_key 의 키와 같을 때만 짝을 쓴다.
#   ★cap 은 **줄 전체** 상한이다(접두 '대상: ' · '  · 키 — ' · suffix 포함). 구판은 제목 몫이라
#     긴 단독 제목 줄이 82자(suffix 포함 92자)로 telegram_notify.R BULLET_ITEM_MAX(80)를 넘었다.
#   짝 원본은 인자로 주입된다 — 검사(08_Tests/ops/test_rf_verify_tg_target.R)가 운영 슬롯을 빌리지 않게.
#   ★main 착지 2026-09-23 — 이 수리는 09-13 worktree(amazing-faraday)에 미커밋으로만 있었다.
# 반환 = character vector (items 안에서 c() 로 펼쳐진다). suffix 는 첫 줄 꼬리에 붙는다.
.tg_combo_papers <- function(req = file.path(ROOT, "06_Registry/replication_request.json")) tryCatch({
  d <- fromJSON(req, simplifyVector = FALSE)
  ps <- (d$combo %||% list())$papers %||% list()
  if (!length(ps)) return(NULL)
  data.frame(key   = vapply(ps, function(p) as.character(p$key   %||% ""), character(1L)),
             title = vapply(ps, function(p) as.character(p$title %||% ""), character(1L)),
             stringsAsFactors = FALSE)
}, error = function(e) NULL)

# 차트 캡션처럼 **한 줄만** 받는 자리용 압축 라벨 — 결합이면 키를 전부 남긴다
# (제목 연접을 60자로 자르면 재료 2·3편이 사라지지만, 키는 3편이라야 42자다).
.tg_target_label <- function(title, pkey, cap = 60L) {
  keys <- if (grepl("^combo:", pkey %||% ""))
    trimws(strsplit(sub("^combo:", "", pkey), "+", fixed = TRUE)[[1]]) else character(0)
  keys <- keys[nzchar(keys)]
  if (length(keys) >= 2L)
    .tg_clip(sprintf("결합 %d편: %s", length(keys), paste(keys, collapse = " / ")), cap)
  else .tg_clip(title, cap)
}

.tg_target_items <- function(title, pkey, suffix = "", cap = 78L, papers = .tg_combo_papers()) {
  keys <- if (grepl("^combo:", pkey %||% ""))
    trimws(strsplit(sub("^combo:", "", pkey), "+", fixed = TRUE)[[1]]) else character(0)
  keys <- keys[nzchar(keys)]
  if (length(keys) < 2L) {
    lead <- "대상: "
    return(paste0(lead, .tg_clip(title, cap - nchar(lead) - nchar(suffix)), suffix))
  }
  pp <- papers
  # 편수 일치는 짝의 증거가 아니다 — 중복 없는 키 **집합**이 이 결합의 키와 같을 때만 짝을 쓴다.
  paired <- !is.null(pp) && nrow(pp) == length(keys) && !anyDuplicated(pp$key) && setequal(pp$key, keys)
  lines <- if (paired)
    vapply(seq_len(nrow(pp)), function(i) {
      lead <- sprintf("  · %s", pp$key[i])
      if (!nzchar(pp$title[i])) return(lead)
      lead <- paste0(lead, " — ")
      paste0(lead, .tg_clip(pp$title[i], cap - nchar(lead)))
    }, character(1L))
  else sprintf("  · %s", keys)          # 짝을 확신할 수 없으면 키만 (지어내지 않는다)
  c(sprintf("대상: 결합 %d편%s", length(keys), suffix), lines)
}
REQ   <- file.path(ROOT, "06_Registry/replication_request.json")
# ★성과 요약 kv·차트 = 예전 알파 서칭 포맷(도훈 지시 2026-08-30).
#   ★수치를 재계산하지 않는다 — 계약 산출물에서 읽기만 한다(손계산 금지).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_perf_summary.R")))
## ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그를 오염시켰다)
LOG_P <- Sys.getenv("QVEST_RP_JLOG", file.path(ROOT, ".cache/reinforce_auto_log.jsonl"))

jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "replication_verify"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG_P, append = TRUE)
  cat(sprintf("[rp_vfy] %s\n", event))
}
fail <- function(why, detail = "") {
  jlog("verify_failed", why = why, detail = substr(detail, 1, 200))
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "failed_needs_session"; d$failure <- why; d$failure_detail <- substr(detail, 1, 400)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  ## v10.01 발송 규칙 §0(2026-10-13): 1단위 1통 · 판정 먼저 · 실패 원인을 숫자/단어 중간에서 자르지 않는다(감사 10-13 #2)
  tryCatch(.v1001_report(target = .tg_target_label(TITLE, PKEY),
                       status = list(stage = "충실구현 — 무인 시도", position = "검증 게이트에서 차단 · 원장 미개설", previous = why),
                       verdict_line = sprintf("무인 충실구현이 검증을 통과하지 못했다 — %s%s", why,
                                              if (nzchar(detail)) paste0(": ", .v1001_clip_words(detail, 300L)) else ""),
                       next_step = "세션이 원인을 확인해 다시 착수한다(요청 파일: 06_Registry/replication_request.json)",
                       push = TRUE),
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  quit(status = 1)
}

## ── v10.01 인계 · 보고 (2026-10-13 · 개선안 §3 · 발송 규칙 v10.01 §0) ───────────────────────────────────────
##   구판은 성공하면 강화 원장에 active entry 를 열고 "강화 N칸이 무인으로 돈다"고 보고했다. 고정 격자 강화 러너가 퇴역해
##   그 entry 를 소진할 주체가 없다 — entry 는 소비 기록으로만 남기고 바로 접는다(selector 가 원장 paper_key 로 소비를 판단).
##   측정 결과는 리서치 프로그램 재료로 넘기고(행동 카드 + 등록부 큐), 보고는 v10.01 발송기 1통이다.
.v1001_clip_words <- function(x, n) {
  x <- gsub("[[:space:]]+", " ", as.character(x %||% ""))
  if (nchar(x) <= n) return(x)
  cut <- substr(x, 1L, n); sp <- regexpr(" [^ ]*$", cut)
  paste0(if (sp > n / 2) substr(cut, 1L, sp - 1L) else cut, " …(전문은 요청 파일)")
}
.V1001_PROG_NAME <- c(P1_RETURN = "수익 엔진", P2_DEFENSE = "방어 엔진", P3_CONSTRUCTION = "구성")
.v1001_report <- function(target, status, verdict_line = NULL, card = NULL, next_step = NULL, artifact = NULL,
                        program = "충실구현", push = TRUE, charts = NULL, extra = NULL) {
  if (!exists("tg_agent_brief", mode = "function"))
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R")))
  if (!exists("prep_send", mode = "function"))
    source(file.path(ROOT, "02_Infrastructure/programs/program_report.R"))
  prep_send(program = program, target = target, status = status, card = card, verdict_line = verdict_line,
            next_step = next_step, artifact = artifact, push = push, charts = charts, extra = extra, root = ROOT)
}
## 등급 근거 — 행동 카드가 싣지 않는 등급 입력(PORT_t · SR · OOS 유지율 · DSR)과 구성 사실(보유 수 · 회전율)을 계약 산출물에서 그대로 옮긴다
##   (rf_perf_summary.R::rf_perf_kv — authoritative_remeasure.json·06_metrics.csv 읽기 전용 · 손계산 0 · AX-008).
##   지표명 = 정통 원표기(발송 규칙 §0 — 한 지표 한 이름). CAGR·최대낙폭·Calmar 는 행동 카드 핵심 수치에 이미 있어 싣지 않는다.
.V1001_GRADE_KV <- c("다중검정 t값" = "PORT_t", "샤프지수" = "SR", "표본외 유지율" = "OOS 유지율", "감가샤프지수" = "DSR",
                     "회전율" = "연 회전율", "유니버스" = "유니버스")
## 차트 = 이름 붙인 것만(발송 규칙 §0.5 — 캡션이 무엇을 보는 차트인지 말한다). 파일 선택·빈 그림 제외는 rf_perf_charts 정본 그대로.
.V1001_CHART_CAP <- c(equity_curve.png = "누적수익 — 전략과 벤치마크", annual_returns.png = "연도별 수익률", drawdown.png = "낙폭 — 고점 대비")
.v1001_charts <- function(dir) {
  p <- tryCatch(rf_perf_charts(dir), error = function(e) character(0))
  if (!length(p)) return(NULL)
  cap <- .V1001_CHART_CAP[basename(p)]
  setNames(p, ifelse(is.na(cap), basename(p), cap))
}
.v1001_grade_extra <- function(dir) {
  kv <- tryCatch(rf_perf_kv(dir), error = function(e) list())
  keep <- intersect(names(.V1001_GRADE_KV), names(kv))
  if (!length(keep)) return(NULL)
  out <- setNames(kv[keep], unname(.V1001_GRADE_KV[keep]))
  out <- lapply(out, function(v) sub("^-", "−", as.character(v)))   # 음수 표기 = 유니코드 마이너스(행동 카드 수치와 같은 형식 · 발송 규칙 §0)
  list(list(type = "kv", emoji = "\U0001F4CF", heading = "등급 근거(계약 산출물)", kv = out))
}
## 재료의 프로그램 = 라우팅 정본에서만 온다(2026-10-14 · 1810.08384 감독 실측). 구판은 등록부에 없으면 'P1_RETURN' 을 기본값으로 적어
##   구성(P3) 논문이 '수익 엔진'으로 보고됐고, 기저 음수(kind=skipped)라 어느 큐에도 들어가지 않았다. 순서:
##   ① 등록부 큐 · 소비 기록(라우터 동기화가 넣은 논문 키) ② 라우터 v5 산출의 engine(program_paper_sync.R::pps_engine_map — 판정 무관)
##   ③ 둘 다 없으면 미분류(UNROUTED) — 프로그램을 추측하지 않고 보류한다(pr_hold_unrouted · 분류가 생기면 동기화가 큐로 옮긴다).
##   키는 정본(1810.08384)과 라우터 표기(axv:1810.08384)를 함께 본다(rf_next_paper_pick.py probe_keys 와 같은 병).
.v1001_key_forms <- function(k) {
  k <- as.character(k %||% "")[1]
  if (is.na(k) || !nzchar(k)) return(character(0))
  b <- sub("^(axv|arxiv):", "", k, ignore.case = TRUE)
  unique(c(k, b, paste0("axv:", b)))
}
.v1001_route <- function(reg) {
  forms <- .v1001_key_forms(PKEY)
  for (f in forms) { pg <- pr_find_key(reg, f); if (!is.na(pg)) return(list(program = pg, routed_by = "program_queue", key = f)) }
  ps <- new.env(parent = globalenv())
  sys.source(file.path(ROOT, "02_Infrastructure/programs/program_paper_sync.R"), envir = ps)
  em <- ps$pps_engine_map(Sys.glob(file.path(ROOT, "stage_artifacts/paper_recharge/alpha_search_route_*.json")))
  b <- if (length(forms)) sub("^(axv|arxiv):", "", forms[1], ignore.case = TRUE) else ""
  if (nzchar(b) && b %in% names(em))
    return(list(program = if (identical(em[[b]], "NOT_RELEVANT")) NA_character_ else em[[b]],
                routed_by = if (identical(em[[b]], "NOT_RELEVANT")) "router_v5_not_relevant" else "router_v5", key = b))
  list(program = NA_character_, routed_by = "unrouted", key = b)
}
.v1001_prog_name <- function(p) {   # 이름 있는 원자 벡터의 [[ 는 없는 이름에 던진다 — 미분류(NA)를 먼저 가른다
  p <- as.character(p %||% NA_character_)[1]
  if (!is.na(p) && p %in% names(.V1001_PROG_NAME)) .V1001_PROG_NAME[[p]] else "미분류"
}
## 측정 산출물 → 행동 카드 · 프로그램 재료. kind = "engine"(기저 문턱 통과) | "skipped"(기저 PORT_t 문턱 미달)
##   ★둘 다 재료다(alpha-search SKILL '미달 → 재료 등록') — 구판은 skipped 를 소비만 하고 재료로 넣지 않았다(구 강화 격자의
##   '음수 알파 위의 강화는 헛돈다' 사유는 격자 퇴역으로 소멸). 기저 상태 · 구현 의심 · 롱숏 여부는 flags 로 싣고 쓰임은 프로그램이 정한다.
.v1001_handoff <- function(art_dir, base_id, grade, kind = "engine", flags = list()) {
  out <- list(card = NULL, program = NA_character_, routed_by = "unrouted", enqueued = FALSE, held = FALSE)
  out$card <- tryCatch({
    source(file.path(ROOT, "02_Infrastructure/contracts/behavior_card.R"))
    cd <- bc_card_from_artifacts(art_dir, root = ROOT); bc_write(cd, art_dir); cd
  }, error = function(e) { jlog("v1001_behavior_card_failed", err = conditionMessage(e)); NULL })
  tryCatch({
    source(file.path(ROOT, "02_Infrastructure/programs/program_registry.R"))
    reg <- pr_load(ROOT)
    rt <- .v1001_route(reg)
    out$program <- rt$program; out$routed_by <- rt$routed_by
    if (identical(rt$routed_by, "program_queue"))
      pr_consume_key(rt$program, rt$key, consumer = paste0("replication:", base_id), root = ROOT)
    item <- c(list(key = paste0("engine:", base_id), kind = "engine", base_status = kind, title = TITLE %||% "",
                   paper_key = PKEY %||% "", base_id = base_id, grade = grade, fidelity = .fidelity,
                   artifacts = art_dir, engine_path = eng, routed_by = rt$routed_by,
                   cr_verdict = if (!is.null(out$card)) out$card$overall$verdict else NA_character_), flags)
    if (!is.na(out$program)) {
      out$enqueued <- isTRUE(pr_enqueue(out$program, item, root = ROOT))
    } else if (!identical(rt$routed_by, "router_v5_not_relevant")) {
      out$held <- isTRUE(pr_hold_unrouted(item, root = ROOT))
      jlog("v1001_unrouted", base_id = base_id, paper_key = PKEY %||% "", held = out$held,
           note = "라우터 v5 분류 없음 — 프로그램을 추측하지 않고 미분류 재료로 보류(paper_routing.unrouted · 동기화 · 세션이 분류)")
    }
    jlog("v1001_handoff", base_id = base_id, program = if (is.na(out$program)) "UNROUTED" else out$program,
         routed_by = rt$routed_by, kind = kind, enqueued = out$enqueued, held = out$held,
         cr = if (!is.null(out$card)) out$card$overall$verdict else "card_missing")
  }, error = function(e) jlog("v1001_handoff_failed", err = conditionMessage(e)))
  out
}
.v1001_num <- function(x, d = 2L) {   # 음수 = 유니코드 마이너스(발송 규칙 §0 — 행동 카드 수치와 같은 형식)
  x <- suppressWarnings(as.numeric(x)[1])
  if (!is.finite(x)) "NA" else sub("^-", "−", formatC(x, format = "f", digits = d))
}
## 관문 줄 — 실제로 지난 것만 적는다(2026-10-14). 구판 '검증 4관문 통과' 는 충실도 감사 기각 · 구현 의심도 통과로 읽혔고,
##   고정 축 관문은 충실구현 축(롱숏 · 종목수 논문 그대로)에서 판정하지 않는다(러너가 replication$ 아래에 쓰는 값을 읽지 않는 것도 그 때문).
.v1001_gate_line <- function() sprintf("검증 관문 통과(계약 · PIT 구조) · 충실도 감사 %s%s",
  as.character(.aud$verdict %||% "?")[1],
  if (isTRUE(.aud_suspect)) " — 재구현 뒤에도 기각: 구현 의심(implementation_suspect)" else "")
## β · β 통제 α — measurement-graduation §2(PORT_t 를 보고할 때 병기 의무). 값 = 역할 카드(contracts/strategy_role.R · role_card.json)
##   ★PORT_t 는 KOSPI200 대비 초과수익 t 라 β<1(시장중립 · 저베타)이면 상승장 미참여만으로도 음수다 — 알파 판단은 t(α) 로 한다.
.v1001_beta_alpha <- function(dir) tryCatch({
  rc <- fromJSON(file.path(dir, "role_card.json"), simplifyVector = FALSE)
  b <- suppressWarnings(as.numeric(rc$beta)[1]); a <- rc$roles$alpha
  at <- suppressWarnings(as.numeric(a$t)[1])
  if (!is.finite(b) && !is.finite(at)) "" else
    sprintf("β %s · β 통제 α t %s(%s)", .v1001_num(b), .v1001_num(at),
            if (identical(as.character(a$basis %||% "")[1], "2f")) "2요인" else "1요인")
}, error = function(e) "")
## 보고 줄 — 재료가 어디로 갔는지(프로그램 · 미분류 보류 · 해당 없음)를 그대로 적는다
.v1001_material_line <- function(ho) {
  if (is.null(ho)) return("재료 인계 실패(저널 v1001_handoff_failed)")
  if (!is.na(ho$program)) return(sprintf("%s(%s) 재료 큐%s", .v1001_prog_name(ho$program), ho$program,
                                         if (isTRUE(ho$enqueued)) "에 등록" else " — 이미 등록됨"))
  if (identical(ho$routed_by, "router_v5_not_relevant")) return("라우터가 어느 엔진 재료도 아니라고 분류 — 큐에 넣지 않음")
  if (isTRUE(ho$held)) "라우터 미분류 — 미분류 재료로 보류(분류되면 프로그램 큐로 옮긴다)" else "라우터 미분류 — 보류 기록 실패(저널 확인)"
}
## 2계층 모듈 등재 — **감사 처분 뒤에만** 부른다(2026-10-14 · 러너 §7-c 는 이 레인에서 QVEST_RP_REGISTER=0 으로 꺼져 있다).
##   자격은 계약 술어(rmm_admission → ds_pool_eligible — 축 long-only · 등급 floor · 기전 방어)가 낸다. 자격 미달은 등재하지 않는다.
##   메모리 sim 이 없으므로 등재기가 계약 CSV(03 · 05 — 일간)로 재조립한다(새 측정 없음). 실패해도 검증은 계속한다.
.v1001_register_module <- function(origin_mode, meta = list()) tryCatch({
  .rmm <- new.env(parent = globalenv())     # 전역 %||% 오염 방지 — 격리 적재
  sys.source(file.path(ROOT, "02_Infrastructure/contracts/register_measured_module.R"), envir = .rmm)
  adm <- .rmm$rmm_admission(.rmm$rmm_read_auth(dirname(ar)))
  reg <- if (isTRUE(adm$eligible))
    .rmm$rmm_register_measured(dirname(ar), origin_mode = origin_mode,
      meta = c(list(paper_key = as.character(PKEY %||% ""), source_paper_url = URL, fidelity = .fidelity,
                    implementation_suspect = isTRUE(.aud_suspect), registered_after_audit = TRUE), meta)) else NULL
  list(adm = adm, reg = reg, note = .rmm$rmm_gate_note(adm))
}, error = function(e) { jlog("module_register_failed", err = conditionMessage(e)); NULL })

eng <- file.path(WDIR, "engine.R")
if (!file.exists(eng) || file.info(eng)$size < 200) fail("engine_too_small", eng)

# ── ①-0 의존 패키지 자동 설치 (도훈 지시 2026-08-30 "없으면 바로 깔아쓰게") ──
#   에이전트에는 Bash 권한을 주지 않는다(안전). 대신 여기서 엔진을 스캔해 설치한다.
#   2026-08-30 실측: 에이전트가 reticulate 를 쓴 엔진을 냈고 패키지 부재로 계약이 통째로 죽었다.
#   ★CRAN 만 · 개수 상한 6 · 설치 내역 로그 — 무인이라 조용한 설치를 남기지 않는다.
#   ★정규식을 쓰지 않는다: 이 파일을 스크립트로 고치는 왕복에서 역슬래시가 두 번 뭉개져
#     문자열이 깨졌다. 고정문자열 분해가 이 맥락에서는 더 견고하다.
#   ★문자열 리터럴도 벗긴다 (2026-09-05 실사고): 에이전트 엔진의 cat() 메시지 안 "FIDELITY.json::portfolio_spec" 을
#     `::` 스캐너가 패키지 FIDELITY.json 으로 읽어 install.packages 실패 → dependency_install_failed → 31분짜리
#     Fable 산출물이 2초 만에 기각됐다. 주석만 벗기던 구판은 문자열 안 `#` 도 주석으로 잘라 그 뒤 코드를 잃었다.
#     문자 단위로 걷는다(정규식·역슬래시 리터럴 없음 — 이 파일의 왕복 규약).
.strip_strings <- function(x) {
  ch <- strsplit(x, "", fixed = TRUE)[[1]]
  if (!length(ch)) return(x)
  BS <- intToUtf8(92); DQ <- intToUtf8(34); SQ <- intToUtf8(39); HASH <- intToUtf8(35)
  q <- ""; esc <- FALSE; out <- character(0)
  for (c in ch) {
    if (nzchar(q)) {                       # 문자열 안 — 아무것도 내보내지 않는다
      if (esc) { esc <- FALSE; next }
      if (identical(c, BS)) { esc <- TRUE; next }
      if (identical(c, q)) q <- ""
      next
    }
    if (identical(c, DQ) || identical(c, SQ)) { q <- c; next }
    if (identical(c, HASH)) break          # 문자열 밖 # = 주석 시작
    out <- c(out, c)
  }
  paste(out, collapse = "")
}
.extract_pkgs <- function(path) {
  ln <- readLines(path, warn = FALSE)
  ln <- vapply(ln, .strip_strings, character(1), USE.NAMES = FALSE)
  out <- character(0)
  clean <- function(s) gsub("[^A-Za-z0-9._]", "", s)
  for (kw in c("library(", "require(")) {
    for (x in ln) {
      pos <- gregexpr(kw, x, fixed = TRUE)[[1]]
      if (pos[1] < 0) next
      for (q in pos) {
        rest <- substr(x, q + nchar(kw), nchar(x))
        cut  <- regexpr(")", rest, fixed = TRUE)
        if (cut > 0) rest <- substr(rest, 1, cut - 1)
        rest <- strsplit(rest, ",", fixed = TRUE)[[1]][1]
        out <- c(out, clean(rest))
      }
    }
  }
  for (x in ln) {
    pos <- gregexpr("::", x, fixed = TRUE)[[1]]
    if (pos[1] < 0) next
    for (q in pos) {
      head_s <- substr(x, 1, q - 1)
      tok <- tail(strsplit(head_s, "[^A-Za-z0-9._]")[[1]], 1)
      out <- c(out, clean(tok))
    }
  }
  base_pkgs <- c("base","stats","utils","methods","graphics","grDevices","tools",
                 "parallel","compiler","datasets","")
  unique(setdiff(out, base_pkgs))
}
.has <- function(x) nzchar(system.file(package = x))
.deps <- .extract_pkgs(eng)
.missing <- .deps[!vapply(.deps, .has, logical(1))]
if (length(.missing)) {
  if (length(.missing) > 6L) fail("too_many_missing_packages", paste(.missing, collapse = ", "))
  jlog("installing_packages", pkgs = paste(.missing, collapse = ","))
  ok_inst <- tryCatch({
    install.packages(.missing, repos = "https://cloud.r-project.org", quiet = TRUE)
    still <- .missing[!vapply(.missing, .has, logical(1))]
    if (length(still)) { jlog("install_incomplete", still = paste(still, collapse = ",")); FALSE } else TRUE
  }, error = function(e) { jlog("install_error", err = conditionMessage(e)); FALSE })
  if (!isTRUE(ok_inst)) fail("dependency_install_failed", paste(.missing, collapse = ", "))
  jlog("packages_installed", pkgs = paste(.missing, collapse = ","))
}

# ── ① 계약 실행 ───────────────────────────────────────────────────────────────
Sys.setenv(QVEST_NO_LEDGER_OPEN = "1")   # 개설은 아래에서 검증 후 직접 한다
# ★2계층 모듈 등재도 감사 뒤로 미룬다(2026-10-14 · 1810.08384 감독 실측) — 러너 §7-c 는 측정 직후 등재해, 충실도 감사에서
#   기각(재구현)될 1차 구현이 감사 10분 전에 카탈로그에 올랐다(08:18 등재 · 08:28 기각). 이 레인의 등재는 소비 분기
#   (.v1001_register_module — 감사 처분 proceed/proceed_suspect 뒤)가 한다. 결합 · 프로그램 라운드 등 다른 러너 호출은 그대로다.
Sys.setenv(QVEST_RP_REGISTER = "0")
# ★기저 캐시 시드 (2026-10-05) — 이 측정이 강화 entry 의 기저가 되면 첫 블록 셀들이 이 엔진 산출을 캐시에서 바로 쓴다
#   (셀마다 엔진 재실행 → 무거운 엔진은 첫 블록 40~50분). 정본 = reinforcement/rf_base_cache.R '기저 캐시 시드'.
#   이 프로세스(검증기)에서만 켠다 — 셀 워커는 별도 프로세스라 상속하지 않는다.
Sys.setenv(QVEST_RP_SEED_BASE_CACHE = "1")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")))
# ★논문 포트폴리오 사양은 **에이전트가 FIDELITY.json 에 남긴 값**을 쓴다.
#   구판은 이 호출에 portfolio_spec 이 아예 없어서 러너 기본값(top_n_long)이 적용됐고,
#   엔진이 롱숏 PORTFOLIO 를 내도 버려졌다(2026-08-31: 무인 3편 전부 롱온리로 측정).
#   에이전트는 필요한 값을 engine.R 주석에 적어 두기까지 했는데 **읽는 자가 없었다**.
#   비용도 마찬가지 — 논문 명시값(예: 2.2bps)이 있으면 그것으로 병기 판을 만든다.
.fid_p <- file.path(dirname(eng), "FIDELITY.json")
.fid_o <- if (file.exists(.fid_p)) tryCatch(fromJSON(.fid_p, simplifyVector = FALSE),
                                            error = function(e) NULL) else NULL
.pspec <- .fid_o$portfolio_spec %||% NULL
## ★보수적 대체값을 넣으면 병기판이 사라진다 (2026-09-04 수리).
##   구판은 논문 무명시(null/부재)를 0.0015 로 덮어썬는데, 그것은 **등급 기준과
##   같은 수**다 — "논문 기준 성과 병기"(헌법)가 동어반복이 돼 서로를 받치는 두 판으로
##   읽힌다. 러너(run_paper_replication.R:180)의 계약이 이미 `NULL = 무명시 -> gross(0)` 이므로
##   덮지 말고 그 기본값에 맡긴다. 0 은 "gross 로 명시" 이므로 그대로 살린다.
.cmsn  <- suppressWarnings(as.numeric(.fid_o$commission_paper %||% NA))
.cmsn_known <- is.finite(.cmsn)
if (!.cmsn_known) .cmsn <- NULL
if (!is.null(.pspec)) jlog("portfolio_spec_from_fidelity",
                           construction = .pspec$construction %||% "?",
                           commission = if (.cmsn_known) .cmsn else "무명시(gross 병기)")
res <- tryCatch(do.call(run_paper_replication, c(list(
  strategy_name = paste0("RP_AUTO_", gsub("[^A-Za-z0-9]", "", substr(PKEY, 1, 20))),
  strategy_idea = paste0("[무인 충실구현] ", substr(TITLE, 1, 120)),
  # ★측정 축(2026-10-13 MEASUREMENT-AXIS-SWITCH-ALLHYG2000) — universe · start_date 를 넘기지 않는다 = 활성 epoch
  #   (constraint_defaults.json::measurement_axis.active — 현재 all_hyg_2000_v1 = 전 종목 + 위생 · 2000-01-01). 구 리터럴(K200_KQ150 · 2005)은 축을 박제했다.
  factor_engine_path = eng,
  source_paper = list(url = URL, title = TITLE, paper_key = PKEY),
  commission_paper = .cmsn, send_telegram = FALSE),
  if (!is.null(.pspec)) list(portfolio_spec = .pspec) else list())),
  error = function(e) structure(list(err = conditionMessage(e)), class = "rp_err"))
if (inherits(res, "rp_err")) fail("replication_error", res$err)

ar <- res$authoritative_remeasure_path %||% file.path(res$out_dir %||% "", "authoritative_remeasure.json")
if (!file.exists(ar)) {
  cand <- list.files(file.path(ROOT, "stage_artifacts/replication"),
                     pattern = "^authoritative_remeasure\\.json$", recursive = TRUE, full.names = TRUE)
  # ★재측정 형제 판(P0-05 · <run>/remeasure_<key>/authoritative_remeasure.json — 원 산출물의 다른 규약 판)은 새 측정이 아니다 —
  #   폴백 후보에서 뺀다(2026-09-24 · 통합 검증 L-B1 · 원장 rebase 형제 위치 = 칸 산출물 안)
  cand <- cand[!grepl("/remeasure_[^/]+/authoritative_remeasure\\.json$", gsub("\\", "/", cand, fixed = TRUE))]
  if (length(cand)) ar <- cand[which.max(file.mtime(cand))]
}
if (!file.exists(ar)) fail("no_authoritative_remeasure", "계약 미경유 = 미측정")
AR <- fromJSON(ar, simplifyVector = TRUE); es <- AR$essence

# ── ② 고정 축 재도출 ──────────────────────────────────────────────────────────
viol <- character(0)
nm <- suppressWarnings(as.integer(AR$n_max %||% es$n_max %||% NA))
if (is.finite(nm) && nm > 25L) viol <- c(viol, sprintf("n_max %d > 25", nm))
if (isTRUE(AR$has_short %||% es$has_short)) viol <- c(viol, "has_short=TRUE (long-only 위반)")
if (length(viol)) fail("fixed_axis_violation", paste(viol, collapse = "; "))

# ── ③ PIT 구조 검사 (정적 CLEAN 을 증명으로 쓰지 않는다) ─────────────────────
src <- paste(readLines(eng, warn = FALSE), collapse = "\n")
src_nc <- gsub("#[^\n]*", "", src)                       # 주석 제거 후 판정
bad <- character(0)
if (grepl("shift\\s*\\(\\s*[^,]+,\\s*-", src_nc))              bad <- c(bad, "음수 shift(미래 인덱싱)")
if (grepl("lead\\s*\\(", src_nc))                              bad <- c(bad, "lead() 사용")
if (grepl("\\b(cov|cor|mean|sd)\\s*\\([^)]*\\)\\s*$", src_nc) &&
    !grepl("froll|rolling|expanding|by\\s*=", src_nc))          bad <- c(bad, "전 표본 통계 의심")
if (grepl("read_parquet|open_dataset", src_nc) && grepl("factor_db", src_nc))
                                                                bad <- c(bad, "C15 위반(팩터 DB 직접 로드)")
if (grepl("NEGATE_FACTORS|FLIP_SIGN", src_nc))                  bad <- c(bad, "C13 위반(부호 반전)")
if (length(bad)) fail("pit_structural", paste(bad, collapse = "; "))

# ── ③-b 충실도 라벨 (도훈 지시 2026-08-30 — 변형구현 허용, 단 귀속을 구분한다) ──
#   faithful = 논문 그대로 · adapted = 인사이트 이식(기전은 남고 구현이 바뀜).
#   ★라벨이 기록에 안 남으면 구분이 무의미하다 — 원장·요청파일·텔레그램에 전부 흐른다.
.fid <- tryCatch({
  fp <- file.path(WDIR, "FIDELITY.json")
  if (file.exists(fp)) fromJSON(fp, simplifyVector = TRUE) else list(fidelity = "unlabeled")
}, error = function(e) list(fidelity = "unlabeled"))
.fidelity <- as.character(.fid$fidelity %||% "unlabeled")
if (!.fidelity %in% c("faithful", "adapted", "combination", "unlabeled")) .fidelity <- "unlabeled"
# ★결합 판은 라벨이 비어 와도 결합이다 — 요청이 그렇게 말했다(진술보다 요청이 정본).
if (IS_COMBO && identical(.fidelity, "unlabeled")) .fidelity <- "combination"
jlog("fidelity", label = .fidelity, kept = substr(.fid$kept %||% "", 1, 90),
     changed = substr(.fid$changed %||% "", 1, 90))

G <- AR$essence_grade
jlog("verified", grade = G, port_t = es$portfolio_alpha_t_nw_lag3, artifacts = dirname(ar))

# ── ★④ 적대적 충실도 감사 (도훈 지시 2026-09-04) ─────────────────────────────
#   위 3관문은 전부 **산출물**을 본다(계약·고정축·PIT). "논문대로 구현했는가" 만
#   재도출이 없었고, FIDELITY.json 은 에이전트 자신의 진술이었다 — 진술은 증거가 아니다.
#   ★값어치는 A등급 보호보다 **F 판정의 신뢰**에 있다: 아래 base_below_threshold 분기가
#     ledger_consumed 로 논문을 영구 소비하기 때문이다. 구현이 틀려서 F 였다면 그 논문은
#     잘못된 이유로 영영 버려진다. 그래서 감사는 **등급 무관 전건**이고 소비 **앞에** 선다.
#   처분(도훈 선택): misdeclared → 자동 재구현 1회 + 소비 보류. 재구현도 기각되면
#   소비하되 implementation_suspect 꼬리표를 남긴다(무한 재시도도, 조용한 소비도 아니다).
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit_lib.R"), local = TRUE))
.aud_p <- file.path(WDIR, "fidelity_audit.json")
.rq0 <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
.aud_tries <- as.integer(.rq0$audit_retries %||% 0L)
# ★청정 모드 감사 (결정 FA-CLEAN-BASE-PATH · 2026-09-26) — 레인이 RP_LANE_MODE=clean 을 싣으면 감사 레인에 산출물 경로를 주지 않고
#   (감사 프롬프트가 '청정 모드 — 비공개' 줄을 쓴다) 스폰 한 번에만 가드 표식을 싣는다(측정·원장 쓰기에는 안 샌다).
#   재구현 피드백(감사 지적)이 측정을 본 감사자의 서술이 되지 않게 — 도우미 = rf_clean_lane_lib.R. 도우미 판독 불능이면 구판 그대로 부르고
#   감사 출처를 normal 로 남긴다(레인이 그 지적을 청정 재구현에 싣지 않는다 — fail-closed 방향).
.CLEAN_LIB_OK <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_clean_lane_lib.R"), local = TRUE)); TRUE },
                          error = function(e) { jlog("clean_lane_lib_missing", err = conditionMessage(e)); FALSE })
.CLEAN <- isTRUE(.CLEAN_LIB_OK) && identical(rcl_lane_mode(), "clean")
.AUD_MODE <- if (.CLEAN) "clean" else "normal"
if (identical(Sys.getenv("RP_LANE_MODE", "normal"), "clean") && !.CLEAN)
  jlog("clean_audit_degraded", note = "레인은 청정인데 도우미 판독 불능 — 감사를 구판 조건으로 부른다(감사 지적은 청정 재구현에 실리지 않는다)")
# 감사 레인 스폰 1회 → rc. system2(stdout=TRUE) 는 rc≠0 일 때만 status 속성을 단다(없으면 0).
.spawn_audit <- function() {
  .art <- if (.CLEAN) rcl_audit_art(TRUE, dirname(ar)) else dirname(ar)
  .run <- function() system2("bash", c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_fidelity_audit.sh")),
                                       shQuote(WDIR), shQuote(.art), shQuote(URL), shQuote(PKEY %||% "")),
                             wait = TRUE, stdout = TRUE, stderr = TRUE)
  r <- if (.CLEAN) rcl_with_env(rcl_clean_env(WDIR), .run()) else .run()
  as.integer(attr(r, "status") %||% 0L)
}
# ★재감사 — 앞 회차 지적 전문을 감사 레인에 넘긴다(2026-10-14 · 1810.08384 감사 상충 실측). 재구현이 받은 피드백 그대로이고,
#   감사 레인이 항목마다 confirmed/overturned 를 적는다 → 번복(근거 있음)이면 처분이 audit_conflict(세션 판정)로 보낸다.
#   청정 레인은 청정 감사의 지적만 넘긴다(레인이 재구현 프롬프트에 싣는 조건과 같다 — rf_replication_auto.sh '청정 모드' 절).
.prior_p  <- file.path(WDIR, ".prior_audit_findings.md")
.prior_fb <- as.character(.rq0$audit_feedback %||% "")[1]; if (is.na(.prior_fb)) .prior_fb <- ""
.prior_ok <- .aud_tries >= 1L && nzchar(trimws(.prior_fb)) &&
             (!.CLEAN || identical(as.character(.rq0$audit_feedback_mode %||% "")[1], "clean"))
if (.prior_ok) writeLines(enc2utf8(.prior_fb), .prior_p, useBytes = TRUE) else unlink(.prior_p, force = TRUE)
if (.aud_tries >= 1L && !.prior_ok)
  jlog("prior_audit_findings_withheld", retries = .aud_tries, has_feedback = nzchar(trimws(.prior_fb)),
       note = "재감사인데 앞 회차 지적을 넘기지 못했다(피드백 없음 또는 비청정 감사 지적) — 감사 상충은 탐지되지 않는다")
# ★감사 없이는 개설하지 않는다 (2026-09-06 — 09-05 실사고 3건: 킬스위치·CLI 부재·병합 즉사로 감사가
#   안 돌았는데 그 부재를 unverifiable 로 읽어 전부 proceed 했다). 관문은 rf_audit_gate 하나다:
#   스폰 → 읽기 → 처분, 미실행이면 최대 2회 더 스폰(사이 rc 는 fidelity_audit_retry 저널로 남는다).
#   ★ruling = 세션 판정(감사 상충 뒤 · alpha-search SKILL §5 — 요청의 audit_ruling · 레인은 failure=audit_ruled 면 검증기만 돈다)
.gate <- rf_audit_gate(WDIR, .spawn_audit, max_retries = 2L, retries_done = .aud_tries, log_fn = jlog,
                       ruling = .rq0$audit_ruling)
.aud <- .gate$aud; .disp <- .gate$disp
.n_ov <- .n_overturned(.aud)
if (.n_ov > 0L && !identical(.disp$action, "audit_conflict"))
  jlog("fidelity_prior_overturned", n = .n_ov, action = .disp$action,
       note = "재감사가 앞 회차 지적을 번복했다 — 이번 판정이 기각이 아니어서 상충 보류는 없다(기록만)")
jlog("fidelity_audit_verdict", verdict = .aud$verdict, action = .disp$action,
     undeclared = length(.aud$undeclared_changes %||% list()),
     mismatch = length(.aud$signal_mismatch %||% list()), retries = .aud_tries,
     spawns = .gate$spawns, last_rc = .gate$last_rc, audit_mode = .AUD_MODE)
# ★출처 기록(FA-CLEAN-BASE-PATH) — 감사 1건(모드 · 산출물 비공개 여부 · 판정). 청정 재구현이면 아래 분기가 원천 사본 위치를 더한다.
.aud_src <- NULL
if (identical(.disp$action, "reimplement") && .CLEAN)
  .aud_src <- tryCatch(rcl_archive_audit_src(WDIR, .aud_tries + 1L), error = function(e) { jlog("clean_audit_archive_failed", err = conditionMessage(e)); NULL })
if (isTRUE(.CLEAN_LIB_OK))
  tryCatch(rcl_prov_audit(WDIR, list(at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), mode = .AUD_MODE, art_hidden = .CLEAN,
                                     verdict = as.character(.aud$verdict %||% ""), action = as.character(.disp$action %||% ""),
                                     spawns = as.integer(.gate$spawns), src = if (is.null(.aud_src)) NULL else .aud_src$rel)),
           error = function(e) jlog("lane_provenance_audit_failed", err = conditionMessage(e)))

if (identical(.disp$action, "audit_required")) {
  # ★미실행은 별개 사건이다 — 소비도 개설도 큐 미러도 없이 세션 대기(failed_needs_session/audit_not_run)로
  #   되돌린다. 엔진은 그대로 둔다: 다음 tick 의 레인(rf_replication_auto.sh)이 audit_not_run + engine.R
  #   존재를 보면 에이전트 없이 검증기만 다시 돈다 — 30분짜리 재구현을 감사 미실행 때문에 태우지 않는다.
  .why <- sprintf("%s (스폰 %d회 · 마지막 rc %d)", as.character(.disp$reason %||% "감사 미실행")[1],
                  as.integer(.gate$spawns), as.integer(.gate$last_rc))
  .Gs <- as.character(G %||% "NA")[1]
  jlog("fidelity_audit_not_run", reason = .why, paper_key = PKEY %||% "", grade = .Gs,
       note = "감사 없이 개설 불가 — 요청을 failed_needs_session/audit_not_run 으로 되돌린다(원장·큐 미러 손대지 않음)")
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "failed_needs_session"; d$failure <- "audit_not_run"; d$failure_detail <- substr(.why, 1, 400)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  tryCatch(.v1001_report(target = .tg_target_label(TITLE, PKEY),
                       status = list(stage = "충실구현 — 적대적 충실도 감사", previous = sprintf("측정 등급 %s", .Gs),
                                     position = sprintf("감사 스폰 %d회 전부 산출 없음", as.integer(.gate$spawns))),
                       verdict_line = paste0("충실도 감사 미실행 — 소비 · 재료 등록 보류. 사유: ", .v1001_clip_words(.why, 240L)),
                       next_step = "엔진은 그대로 두고 검증기(측정 + 감사)만 재시도한다(3회 규약). 레인이 죽었으면 저널 fidelity_audit_retry 를 먼저 본다",
                       push = TRUE),
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  quit(status = 0)
}

if (identical(.disp$action, "audit_conflict")) {
  # ★감사 상충(2026-10-14 · 1810.08384 실측) — 재감사가 앞 회차 지적을 원문 근거로 번복했다. 재구현이 틀린 지적을 따랐을 수 있어
  #   이 기각을 구현자 몫(proceed_suspect = 소비 + 꼬리표)으로 세지 않는다. 소비 · 재료 등록 · 큐 미러 없이 이 논문만 보류하고
  #   (스킵리스트 held_audit_conflict — 선택기 rf_next_paper_pick.py 와 레인 스킵 관문이 revoked 아닌 항목을 집지 않는다)
  #   레인은 다음 논문으로 간다 — 무인 레인에 사람 대기 종점을 만들지 않는다(재시도 장치 주석 2026-08-30 규약).
  #   판정 절차 = alpha-search SKILL §5(재구현 예약 = reimplement_queue · suspect 수용 · 진행 = 요청의 audit_ruling + failure=audit_ruled).
  .Gs  <- as.character(G %||% "NA")[1]
  .rel <- function(p) {   # 접두 고정 문자열 비교 — ROOT 를 정규식에 넣지 않는다(역슬래시 경로의 '\U' 즉사 전례)
    p <- gsub("\\", "/", p, fixed = TRUE); r <- paste0(sub("/+$", "", gsub("\\", "/", ROOT, fixed = TRUE)), "/")
    if (startsWith(p, r)) substring(p, nchar(r) + 1L) else p
  }
  .ov  <- rf_audit_overturned(.aud)   # 처분과 같은 술어(lib 한 자리) — 근거 있는 번복만
  .cf_p <- file.path(WDIR, "audit_conflict.json")
  .now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  tryCatch(writeLines(toJSON(list(schema = "audit_conflict_v1", at = .now, paper_key = PKEY %||% "", url = URL, title = TITLE,
                                  wdir = .rel(WDIR), audit = .rel(.aud_p), audit_retries = .aud_tries, grade = .Gs,
                                  artifacts = .rel(dirname(ar)), n_overturned = length(.ov), overturned = .ov,
                                  prior_feedback = .prior_fb, current_feedback = .disp$feedback %||% ""),
                             auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), .cf_p, useBytes = TRUE),
           error = function(e) jlog("audit_conflict_write_failed", err = conditionMessage(e)))
  .skp <- file.path(ROOT, "06_Registry/replication_skiplist.json")
  tryCatch({
    sk <- if (file.exists(.skp)) fromJSON(.skp, simplifyVector = FALSE) else list(schema = "replication_skiplist_v1", entries = list())
    live <- vapply(sk$entries %||% list(), function(e) identical(as.character(e$paper_key %||% ""), PKEY) &&
                     !identical(as.character(e$status %||% ""), "revoked"), logical(1))
    if (nzchar(PKEY %||% "") && !any(live)) {
      sk$entries <- c(sk$entries %||% list(), list(list(
        paper_key = PKEY, status = "held_audit_conflict", added_at = .now, detail = .rel(.cf_p),
        reason = sprintf("감사 상충 — 재감사가 앞 회차 지적 %d건을 원문 근거로 번복(재구현 %d회). 소비 · 재료 등록 보류 · 세션 판정 대기. ★보류 해제는 status=revoked", length(.ov), .aud_tries))))
      .tmp <- paste0(.skp, ".tmp", Sys.getpid())
      writeLines(toJSON(sk, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), .tmp, useBytes = TRUE)
      if (!file.rename(.tmp, .skp)) { unlink(.tmp); stop("스킵리스트 교체 실패") }
    }
  }, error = function(e) jlog("audit_conflict_skiplist_failed", err = conditionMessage(e)))
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "held_audit_conflict"; d$failure <- "audit_conflict"; d$audit_conflict <- .rel(.cf_p)
  d$failure_detail <- substr(sprintf("재감사 번복 %d건: %s", length(.ov),
                                     paste(vapply(.ov, function(z) as.character(z$item %||% "")[1], character(1)), collapse = " / ")), 1, 400)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  jlog("fidelity_audit_conflict", paper_key = PKEY %||% "", grade = .Gs, n_overturned = length(.ov), retries = .aud_tries,
       detail = .rel(.cf_p), note = "감사 상충 — 구현자 몫으로 세지 않는다(소비 · 재료 등록 보류 · 스킵리스트 held_audit_conflict · 세션 판정)")
  tryCatch(.v1001_report(target = .tg_target_label(TITLE, PKEY),
                       status = list(stage = "충실구현 — 적대적 충실도 감사(재감사)", previous = sprintf("측정 등급 %s · 재구현 %d회", .Gs, .aud_tries),
                                     position = "감사 상충 · 소비 보류 · 다음 논문 진행"),
                       verdict_line = sprintf("재감사가 앞 회차 지적 %d건을 원문 근거로 번복했다 — 재구현이 틀린 지적을 따랐을 수 있어 이 기각을 구현 실패로 세지 않는다",
                                              length(.ov)),
                       extra = list(list(type = "text", emoji = "📝", heading = "번복된 앞 회차 지적",
                                         body = paste(vapply(head(.ov, 4L), function(z) sprintf("• %s — %s", .tg_clip(z$item %||% "", 60L),
                                                                                                 .tg_clip(z$evidence %||% "", 140L)), character(1)),
                                                      collapse = "\n"))),
                       next_step = sprintf("세션이 원문으로 판정한다(%s) — 재구현 예약 또는 suspect 수용", .rel(.cf_p)),
                       push = TRUE),
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/programs/next_replication.R")), "--root", shQuote(ROOT)), wait = TRUE)
  quit(status = 0)
}

if (identical(.disp$action, "reimplement")) {
  # ★소비 보류 — 원장에 아무것도 열지 않고 요청만 되돌린다. selector 는 원장으로 소비를
  #   판단하므로, 여기서 열지 않으면 같은 논문이 다시 잡힌다(그게 의도다).
  .bk <- file.path(WDIR, sprintf("engine.rejected%d.R", .aud_tries + 1L))
  tryCatch(file.rename(file.path(WDIR, "engine.R"), .bk), error = function(e) NULL)
  d <- .rq0
  d$status <- "pending"
  d$audit_retries <- .aud_tries + 1L
  d$audit_feedback <- .disp$feedback
  d$audit_verdict <- .aud$verdict
  d$audit_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  # ★감사 지적의 출처 모드(FA-CLEAN-BASE-PATH) — 레인은 clean 인 지적만 청정 재구현 프롬프트에 싣는다(가림 뒤) ·
  #   원천 사본(.clean_audit_src/r<n>) 위치를 함께 남긴다(사후 검사가 파일에서 '산출물 비공개 감사' 를 재도출한다)
  d$audit_feedback_mode <- if (.CLEAN && !is.null(.aud_src)) "clean" else "normal"
  d$audit_feedback_src <- if (is.null(.aud_src)) NULL else .aud_src$rel
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  jlog("fidelity_reimplement_requested", paper_key = PKEY %||% "", grade = G,
       note = "충실도 기각 — 소비 보류. 다음 tick 이 지적사항을 안고 재구현한다")
  tryCatch({
    .n_find <- length(.aud$undeclared_changes %||% list()) + length(.aud$signal_mismatch %||% list())
    .v1001_report(target = .tg_target_label(TITLE, PKEY),
                status = list(stage = "충실구현 — 적대적 충실도 감사", previous = sprintf("측정 등급 %s", G),
                              position = "감사 기각 · 소비 보류 · 자동 재구현 1회"),
                verdict_line = sprintf("충실도 감사 기각(%s) — 지적 %d건. 논문을 잘못된 이유로 버리지 않도록 지적을 안고 다시 구현한다",
                                       as.character(.aud$verdict %||% "?"), .n_find),
                extra = list(list(type = "text", emoji = "📝", heading = "감사 지적 요약",
                                  body = rf_audit_tg_brief(.aud, audit_path = sub(paste0("^", ROOT, "/?"), "", .aud_p)))),
                next_step = "다음 tick 이 지적사항을 안고 재구현한다", push = FALSE) },
    error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  quit(status = 0)
}
.aud_suspect <- identical(.disp$action, "proceed_suspect")
if (.aud_suspect) jlog("fidelity_suspect_proceed", paper_key = PKEY %||% "",
  note = "재구현도 충실도 기각 — 소비하되 implementation_suspect 로 남긴다")

# ── ★B등급 이상 신호를 팩터 DB 에 무인 등록 (도훈 지시 2026-09-01) ───────────
#   충실구현이 낸 신호가 어디에도 적립되지 않아, B+ 를 받아도 그 논문의 25칸이 끝나면
#   사라졌다 — 다음 논문의 B1 조합 후보가 되지 못했다. 여기가 그 루프를 닫는 자리다.
#   ★게이트·중복판정·되돌리기는 전부 rf_factor_autoregister.R 안에 있고, 실패해도
#     검증을 죽이지 않는다(등급 발행이 이 스크립트의 본업이다).
tryCatch(system2("Rscript",
  c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_factor_autoregister.R")),
    shQuote(dirname(ar)), shQuote(eng %||% ""), shQuote(PKEY %||% "")),
  wait = TRUE, stdout = TRUE, stderr = TRUE),
  error = function(e) jlog("factor_autoregister_failed", err = conditionMessage(e)))

# ── ③-b' 역할 카드 (도훈 결정 2026-10-06/07 — 1계층 목표 = 2계층 다양한 풀 · 규칙 기반 분류) ─────────────
#   측정 직후 기저의 역할(방어·공격·반등·잔차α)을 수익 행동으로 판정해 산출물 옆에 남긴다(role_card.json).
#   ★처분을 바꾸지 않는다 — 기록·보고 전용. 풀 대표 선정(계보 대표·군집)과 diversifier 는 일일 [8.1r] 일괄 분류가 한다.
#   ★declared_role(FIDELITY — 구현자가 논문에서 읽은 역할)과 측정 역할이 다르면 불일치 표식만 남긴다(LLM 판정 금지 · 대조용).
.role_items <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/contracts/strategy_role.R")))
  .rc <- sr_card_for_series(file.path(dirname(ar), "03_period_returns.csv"), ROOT)
  if (identical(.rc$status, "ok")) {
    .gs <- vapply(.rc$roles, function(z) as.character(z$grade), "")
    .ts <- vapply(.rc$roles, function(z) { v <- suppressWarnings(as.numeric(z$t)); if (length(v) && is.finite(v)) v else NA_real_ }, 0)
    .decl <- tryCatch(as.character(.fid$declared_role %||% ""), error = function(e) "")
    .mis <- nzchar(.decl) && !any(vapply(names(.gs)[.gs %in% c("A", "B")], function(r) grepl(r, .decl, ignore.case = TRUE), logical(1)))
    writeLines(toJSON(c(.rc, list(declared_role = .decl, declared_mismatch = .mis, computed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))),
                      auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null", null = "null"), file.path(dirname(ar), "role_card.json"))
    jlog("role_card", primary = .rc$primary_role, primary_grade = .rc$primary_grade, roles_bplus = paste(.rc$roles_bplus, collapse = ","),
         declared_role = .decl, declared_mismatch = .mis)
    c(sprintf("대표 역할: %s %s · 역할 B+: %s", .rc$primary_role, .rc$primary_grade,
              if (length(.rc$roles_bplus)) paste(.rc$roles_bplus, collapse = ", ") else "없음"),
      substr(paste(sprintf("%s %s(t %.1f)", names(.gs), .gs, .ts), collapse = " · "), 1, 78),
      if (nzchar(.decl)) substr(sprintf("논문 신고 역할: %s%s", .decl, if (.mis) " — 측정과 불일치" else ""), 1, 78))
  } else { jlog("role_card_skipped", status = .rc$status); character(0) }
}, error = function(e) { jlog("role_card_failed", err = conditionMessage(e)); character(0) })

# ── ③-c 기저 품질 문턱 (도훈 지시 2026-08-30 — PORT_t < 0 기준) ─────────────
#   ★왜: 강화 20칸은 기저 신호 **위에** 팩터를 얹는다. 기저 알파가 음수면 그 위에서
#   무엇을 얹어도 20칸이 헛돌 공산이 크다. 어제 JT1993 은 기저 F 였지만 PORT_t 가 0 근처
#   (0.16)였고 거기서 12칸이 C 로 올라왔다. 2026-08-30 Lead-Lag 착안판은 PORT_t -1.559 —
#   "약하다" 가 아니라 "반대로 작동한다" 이고, 그 위에 얹는 건 다른 문제다.
#   ⇒ 음수면 강화를 생략하고 **다음 논문으로 이월**한다. 측정은 이미 남았고 기록도 남는다.
.base_pt <- suppressWarnings(as.numeric(es$portfolio_alpha_t_nw_lag3 %||% NA))
.min_pt  <- suppressWarnings(as.numeric((tryCatch(fromJSON(file.path(ROOT,
              "06_Registry/reinforce_auto_config.json"), simplifyVector = TRUE),
              error = function(e) list())$base_min_port_t) %||% 0))
# ★구제된 기저는 이 문턱을 통과한다 (도훈 지시 2026-09-04).
#   구제의 논지가 "전기간 통계량이 이 전략을 서술하지 못한다" 인데, 바로 그 통계량으로
#   강화를 막으면 앞뒤가 안 맞는다. 실사례 1403.8125: 전기간 PORT_t -0.639 로 여기서
#   park 됐는데, 롤링 36개월 기준 최근 12점 중 83%가 절대문턱을 넘고 현재 CAGR 26.0% ·
#   Calmar 1.32 다. 전기간 MDD 61.1% 는 2012년 2월 사건이고 최근창 MDD 는 19.7% 다.
#   ⇒ 구제된 건은 통과시키되 **경로를 라벨로 남긴다** — 무엇이 왜 들어왔는지 보이게.
#   ★해제가 아니라 예외다: 구제 안 된 음수 알파는 여전히 막힌다(rg_rescue 가 F 에서만,
#     최근 문턱 충족 + 롤링점 하한을 다 만족할 때만 참을 내므로 문이 넓어지지 않는다).
.resc_ok <- isTRUE(AR$recent_regime_rescued)
if (.resc_ok) jlog("base_gate_bypass_rescued", port_t = .base_pt,
                   grade_base = as.character(AR$grade_base %||% ""), grade = G,
                   note = "recent_regime 구제 — 전기간 PORT_t 문턱을 우회한다")
if (is.finite(.base_pt) && .base_pt < .min_pt && !.resc_ok) {
  jlog("base_below_threshold", port_t = .base_pt, threshold = .min_pt,
       note = "기저 알파가 음수 — 강화 생략하고 다음 논문으로 이월(측정·기록은 남는다)")

  # ── ★방어형 병렬 경로 — 소비 **전에** 판정한다 (도훈 승인 2026-09-07) ────────
  #   왜: 이 게이트는 **전기간** PORT_t 하나로 논문을 영구 소비(ledger_consumed)하는데,
  #   방어형의 값어치는 전기간 평균이 아니라 **벤치가 실제로 마이너스를 낸 국면**에서 난다.
  #   AX-001 이 금지하는 "전기간 기준 방어형 평가" 를 게이트가 하고 있었다.
  #   실측 2026-09-07: 이 분기로 버려진 14건 중 **11건이 계약 기준 방어형**이었다
  #   (하락월 t 9.95 · 8.63 · 6.38 · 6.23 · 5.47 · 3.72 …).
  #   ⇒ 방어형이면 버리지 말고 **2계층 풀 후보로 모듈 등재**한 뒤 소비한다.
  #     1계층 강화는 여전히 생략한다(현행 유지) — "값어치는 조합 안에서 나온다"(reinforce SKILL).
  #   ★부재를 거짓으로 읽지 않는다: defensive_score 미산출은 `dscore_absent` 사유로 남는다.
  #   ★판정은 계약 술어(ds_pool_eligible) 가 낸다 — 여기에 사본을 두지 않는다.
  .adm_note <- ""
  tryCatch({
    .rg <- .v1001_register_module("replication_skipped_base",
             meta = list(skipped_base_port_t = .base_pt, base_min_port_t = .min_pt,
                         admitted_by = "base_below_threshold defensive route (도훈 2026-09-07)"))
    if (is.null(.rg)) stop("등재 도우미 실패(저널 module_register_failed)")
    .adm <- .rg$adm; .reg <- .rg$reg
    ## 텔레그램 줄은 **편입됐을 때** · **방어형이 미산출일 때** · **방어형 경로가 축/귀속으로 막혔을 때**만 낸다.
    ##   앞 둘은 처분 변경과 배선 결손 신호다. 축(롱숏)·노출 방어 차단은 '하락월 아웃퍼폼이 있었는데 왜 안 들어갔나'에 답한다
    ##   (2026-10-14 — 1810.08384 는 이 줄 없이 '방어형 등재'로 보고됐다). 평범한 비방어형(not_defensive)은 저널에만 남긴다.
    if (isTRUE(.adm$eligible) || as.character(.adm$code)[1] %in% c("dscore_absent", "axis_long_short", "exposure_defense"))
      .adm_note <- .rg$note
    if (isTRUE(.adm$eligible)) {
      jlog(if (identical(as.character(.adm$route)[1], "defensive_specialist"))
             "defensive_admitted" else "pool_admitted",
           route = as.character(.adm$route)[1], grade = as.character(.adm$grade)[1],
           down_n = .adm$n_down, down_t = .adm$down_t, down_excess = .adm$down_excess,
           deep_excess = .adm$deep_excess,   # convex 폐기 2026-09-07(도훈)
           registered = isTRUE(.reg$registered), strategy_id = .reg$strategy_id,
           code = .reg$code, port_t = .base_pt, attribution = .adm$attribution, beta = .adm$beta,
           note = "기저 음수여도 2계층 풀 후보로 등재 — 1계층 강화는 생략(현행 유지)")
    } else {
      jlog("defensive_not_admitted", code = as.character(.adm$code)[1],
           grade = as.character(.adm$grade)[1], has_dscore = isTRUE(.adm$has_dscore),
           has_short = .adm$has_short, attribution = .adm$attribution, beta = .adm$beta,
           reason = substr(as.character(.adm$reason)[1], 1, 200),
           note = "부재(dscore_absent)와 거짓(not_defensive)은 다르다 — 한 칸에 합치지 않는다")
    }
  }, error = function(e) jlog("defensive_admit_failed", err = conditionMessage(e),
       note = "★등재 경로 실패 — 소비는 그대로 진행한다(측정·기록은 남는다)"))

  # ★원장에 **소비 기록**을 남긴다. 안 남기면 rf_next_paper_pick 이 원장 paper_key 로
  #   소비를 판단하므로 같은 논문을 영원히 다시 집는다 — 8분마다 LLM 에이전트가 재실행된다.
  #   실사고 2026-08-31: 2608.23944 를 19:14~20:34 사이 **5회** 반복 구현했다.
  #   요청 파일(status=done_no_reinforce)만 닫는 것으로는 부족하다. selector 는 그 파일을 안 본다.
  .bid_sk <- sprintf("RP_%s_skipped_base", format(Sys.time(), "%Y%m%d_%H%M%S"))
  tryCatch({
    suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
    rf_open_entry(1L, .bid_sk, base_grade = G, paper_key = PKEY %||% "", paper_id = "",
                  base_artifacts = dirname(ar), engine_path = eng,
                  count_paper = COUNT_PAPER, root = ROOT)
    rf_park_entry(1L, .bid_sk, sprintf(
      "skipped_base_quality — 기저 PORT_t %.3f < %.2f. 논문 소비 처리(측정 · 기록 보존 · 측정 산출물은 프로그램 재료로 인계)%s",
      .base_pt, .min_pt,
      if (isTRUE(.aud_suspect)) " · implementation_suspect(충실도 감사 — 재구현 뒤에도 기각)" else ""), root = ROOT)
    jlog("ledger_consumed", base_id = .bid_sk, paper_key = PKEY %||% "", implementation_suspect = isTRUE(.aud_suspect),
         note = "소비 기록 — selector 가 이 논문을 다시 집지 않는다")
    .qmirror(PKEY, sprintf("skipped_base_quality (PORT_t %.3f)", .base_pt), .bid_sk)
  }, error = function(e) jlog("ledger_consume_failed", err = conditionMessage(e),
       note = "★소비 기록 실패 — 같은 논문이 재선택될 수 있다"))
  ## (2026-10-14) 기저 문턱 미달도 재료다(alpha-search SKILL '미달 → 재료 등록') — 구판은 소비만 하고 어느 큐에도 넣지 않았다.
  ##   기저 상태 · 구현 의심 · 롱숏은 flags 로 싣는다(쓰임은 프로그램 분석가가 정한다 · 라우팅은 .v1001_route).
  .hs <- isTRUE(AR$replication$has_short %||% AR$has_short)
  .ho <- .v1001_handoff(dirname(ar), .bid_sk %||% "skipped", G, kind = "skipped",
                        flags = list(base_below_threshold = TRUE, base_port_t = .base_pt, base_min_port_t = .min_pt,
                                     implementation_suspect = isTRUE(.aud_suspect), has_short = .hs,
                                     audit_verdict = as.character(.aud$verdict %||% "")[1]))
  d <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  d$status <- "done_no_reinforce"; d$grade <- G; d$fidelity <- .fidelity
  d$base_port_t <- .base_pt; d$artifacts <- dirname(ar)
  d$implementation_suspect <- isTRUE(.aud_suspect); d$audit_verdict <- as.character(.aud$verdict %||% "")[1]
  d$program <- if (is.na(.ho$program)) "UNROUTED" else .ho$program; d$material <- .v1001_material_line(.ho)
  d$skip_reason <- sprintf("기저 PORT_t %.3f < %.2f — 수익 엔진 문턱 미달(측정 산출물은 재료로 인계)", .base_pt, .min_pt)
  write(toJSON(d, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
  .ba <- .v1001_beta_alpha(dirname(ar))
  tryCatch(.v1001_report(target = .tg_target_label(TITLE, PKEY),
                       status = list(stage = sprintf("%s 완료", if (identical(.fidelity, "adapted")) "변형구현(착안)" else "충실구현"),
                                     position = .v1001_gate_line(), previous = sprintf("등급 %s(권위)", G)),
                       verdict_line = sprintf("등급 %s · 기저 PORT_t %s(KOSPI200 대비 초과수익 t · 문턱 %s 미만)%s — 재료: %s%s",
                                              G, .v1001_num(.base_pt), .v1001_num(.min_pt),
                                              if (nzchar(.ba)) paste0(" · ", .ba) else "", .v1001_material_line(.ho),
                                              if (length(.adm_note) == 1L && nzchar(.adm_note)) paste0(". 2계층 풀: ", .adm_note) else ""),
                       card = .ho$card, artifact = dirname(ar),
                       next_step = paste0("큐 다음 논문 충실구현으로 넘어간다",
                                          if (is.na(.ho$program)) " · 미분류 재료는 라우터 v5 동기화 또는 세션이 프로그램을 정한다" else ""),
                       push = TRUE, charts = .v1001_charts(dirname(ar)), extra = .v1001_grade_extra(dirname(ar))),
           error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
  # ★[팩터 분석] — 산출물이 있을 때만 보낸다 · 없으면 사유를 남긴다(침묵 누락 금지 · 정본 telegram_notify.R::tg_pass_analysis)
  if (file.exists(file.path(dirname(ar), "analysis_multifactor.csv")) || file.exists(file.path(dirname(ar), "analysis_fmb_summary.csv")))
    tryCatch(tg_pass_analysis(.tg_target_label(TITLE, PKEY), dirname(ar)), error = function(e) jlog("factor_tg_failed", err = conditionMessage(e)))
  else jlog("factor_analysis_absent", dir = dirname(ar), note = "FF/FMB 산출물 없음 — FACTORS 부재이거나 분석 실패")
  system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/programs/next_replication.R")), "--root", shQuote(ROOT)), wait = TRUE)
  quit(status = 0)
}

# ── ④ 원장 개설 → 강화 무인 재개 ─────────────────────────────────────────────
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))
BID <- paste0(AR$strategy_id %||% paste0("RP_AUTO_", format(Sys.time(), "%Y%m%d_%H%M%S")), "_rulefast")
# ★귀속을 base_id 에 새긴다 — adapted 를 충실구현으로 오독하는 경로를 원천 차단
BID <- if (identical(.fidelity, "adapted")) paste0(sub("_rulefast$", "", BID), "_adapted_rulefast") else BID
BID <- if (identical(.fidelity, "combination")) paste0(sub("_rulefast$", "", BID), "_combo_rulefast") else BID
tryCatch(rf_open_entry(1L, BID, base_grade = G, paper_key = PKEY,
                       base_artifacts = dirname(ar), engine_path = eng,
                       count_paper = COUNT_PAPER, root = ROOT),
         error = function(e) fail("ledger_open_failed", conditionMessage(e)))
.qmirror(PKEY, sprintf("측정 완료 — 프로그램 재료 (기저 %s)", G), BID)
## ★v10.01 (2026-10-13): 고정 격자 강화 러너 퇴역 — entry 는 소비 기록(selector 가 원장 paper_key 로 소비 판단)으로만 남기고 바로 접는다.
##   active 로 두면 소진할 주체가 없어 충실구현 레인이 영구 정지한다(삭제 지도 §0-3).
tryCatch(rf_park_entry(1L, BID, reason = "v10.01 — 고정 격자 강화 퇴역(2026-10-13). 측정 결과는 리서치 프로그램 재료로 넘어간다(06_Registry/research_programs.json)", root = ROOT),
         error = function(e) jlog("v1001_park_failed", err = conditionMessage(e)))
.HO <- .v1001_handoff(dirname(ar), BID, G, kind = "engine",
                      flags = list(implementation_suspect = isTRUE(.aud_suspect), has_short = isTRUE(AR$replication$has_short %||% AR$has_short),
                                   audit_verdict = as.character(.aud$verdict %||% "")[1]))
## 2계층 모듈 등재 — 감사 뒤(2026-10-14 · 러너 §7-c 이관). 자격 미달은 등재기가 저널(module_register_skipped)만 남긴다.
.RG <- .v1001_register_module("replication", meta = list(base_id = BID, strategy_name = as.character(AR$strategy_name %||% "")))
if (!is.null(.RG)) jlog("module_register_after_audit", eligible = isTRUE(.RG$adm$eligible), code = as.character(.RG$adm$code)[1],
                        registered = isTRUE(.RG$reg$registered), strategy_id = as.character(.RG$reg$strategy_id %||% "")[1],
                        attribution = .RG$adm$attribution, has_short = .RG$adm$has_short)

# ★결합이면 원장 entry 에 앵커와 **희석 판정**을 남긴다 (2026-09-04).
#   구판은 이 판정을 "첫 셀(B1_1)이 부모를 넘는가" 로 대리했는데, B1_1 은 순수 기저가
#   아니라 기저+팩터1종(w0=0.5)이라 재려는 것과 재는 도구가 달랐다. 이제 기저를 직접 잰다.
#   ★차단하지 않고 기록만 한다 — 격자는 기저 **위에** 쌓으므로 부모보다 낮은 기저에서도
#   강화가 뒤집을 수 있다(도훈 선택, 2026-09-04). 차단은 base_min_port_t 하나뿐이다.
if (IS_COMBO) tryCatch({
  .rq <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) list())
  .cb <- .rq$combo %||% list()
  .pt <- suppressWarnings(as.numeric(es$portfolio_alpha_t_nw_lag3 %||% NA))
  # ★N편 재편(2026-09-04)으로 앵커 키가 a_t/b_t -> best_parent_t/parent_t 로 바뀌었다.
  #   구 키를 읽어 max(NA, na.rm=TRUE) = -Inf 가 나왔고 판정이 unmeasured 로 죽었다(11:39 실측).
  #   구 키 폴백을 남긴다 — 이전 요청 형식으로 열린 건이 아직 흐를 수 있다.
  .parents <- suppressWarnings(as.numeric(unlist(.cb$parent_t %||% list())))
  .best_parent <- suppressWarnings(as.numeric(.cb$best_parent_t %||% NA))
  if (!is.finite(.best_parent) && length(.parents) && any(is.finite(.parents)))
    .best_parent <- max(.parents[is.finite(.parents)])
  if (!is.finite(.best_parent)) {
    .legacy <- suppressWarnings(as.numeric(c(.cb$a_t %||% NA, .cb$b_t %||% NA)))
    if (any(is.finite(.legacy))) .best_parent <- max(.legacy[is.finite(.legacy)])
  }
  .verdict <- if (!is.finite(.pt) || !is.finite(.best_parent)) "unmeasured"
              else if (.pt > .best_parent) "additive" else "dilution"
  .o <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
  .k <- which(vapply(.o$entries, function(z) identical(z$base_id, BID), logical(1)))[1]
  if (!is.na(.k)) {
    .o$entries[[.k]]$combo <- c(.cb, list(
      base_port_t = if (is.finite(.pt)) round(.pt, 4) else NULL,
      best_parent_t = if (is.finite(.best_parent)) round(.best_parent, 4) else NULL,
      dilution_verdict = .verdict,
      note = "LLM 결합 설계 → 충실구현 1회로 기저 측정 → base_min_port_t 통과분만 25칸(2026-09-04 도훈). 희석 판정은 기록 전용 — 차단하지 않는다."))
    .txt <- toJSON(.o, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
    stopifnot(length(fromJSON(.txt, simplifyVector = FALSE)$entries) == length(.o$entries))
    writeLines(.txt, file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), useBytes = TRUE)
    jlog("combo_verdict", base_id = BID, base_port_t = .pt,
         best_parent_t = .best_parent, verdict = .verdict)
  }
}, error = function(e) jlog("combo_meta_failed", err = conditionMessage(e)))

# ★요청 종결은 소유 대조 뒤에만 쓴다 (2026-09-15 도훈 승인 수리 — rf_request_guard.R 머리 주석).
#   구판은 지금의 요청 파일을 키 대조 없이 done 으로 덮었다 — 늦게 끝난 구 실행이 다음 논문 요청을 닫았다
#   (09-13: 2002.06975 3판이 1806.01743 요청을 done·C 로 덮음). 측정·원장 기록은 위에서 이미 이 실행 키로 남았다.
source(file.path(ROOT, "02_Infrastructure/ops/rf_request_guard.R"))
.own <- rf_request_mark_done(REQ, PKEY, list(
  base_id = BID, grade = G, artifacts = dirname(ar),
  fidelity = .fidelity, fidelity_detail = .fid,
  fidelity_audit = .aud, implementation_suspect = isTRUE(.aud_suspect),
  program = if (is.na(.HO$program)) "UNROUTED" else .HO$program, material = .v1001_material_line(.HO)))
if (!isTRUE(.own$written))
  jlog("request_done_skipped_retargeted", run_key = .own$run_key, req_key = .own$req_key,
       base_id = BID, grade = G,
       note = "요청이 다른 논문으로 바뀌었다 — 이 실행 결과로 남의 요청을 닫지 않는다(요청 상태는 현 소유 실행이 쓴다)")

## v10.01 발송 규칙 §0 — 1단위 1통: 등급(권위) · 위기 방어 판정 · 위기별 낙폭 · 핵심 수치 · 다음
.BA <- .v1001_beta_alpha(dirname(ar))
tryCatch(.v1001_report(target = .tg_target_label(TITLE, PKEY),
                     program = .v1001_prog_name(.HO$program),   # 미분류면 '미분류' — 구판은 'P1_RETURN'/'수익 엔진' 을 기본값으로 적었다
                     status = list(stage = sprintf("%s 완료", if (identical(.fidelity, "adapted")) "변형구현(착안)" else "충실구현"),
                                   position = .v1001_gate_line(),
                                   previous = sprintf("등급 %s(권위) · 충실도 %s%s", G,
                                                      if (identical(.fidelity, "adapted")) "착안(변형)" else "충실",
                                                      if (isTRUE(.aud_suspect)) " · 구현 의심 꼬리표" else "")),
                     verdict_line = sprintf("등급 %s(권위 · 15bps 순비용)%s — %s재료: %s",
                                            G, if (nzchar(.BA)) paste0(" · ", .BA) else "",
                                            if (identical(.fidelity, "adapted")) paste0("착안 구현(남긴 기전: ", .v1001_clip_words(.fid$kept %||% "?", 120L), ") · ") else "",
                                            .v1001_material_line(.HO)),
                     card = .HO$card, artifact = dirname(ar),
                     next_step = paste0("프로그램 큐에서 조립 단계(실현 가능성 지도 이후)가 쓴다 · 큐 다음 논문으로 넘어간다",
                                        if (is.na(.HO$program)) " · 미분류 재료는 라우터 v5 동기화 또는 세션이 프로그램을 정한다" else ""),
                     push = TRUE, charts = .v1001_charts(dirname(ar)), extra = .v1001_grade_extra(dirname(ar))),
         error = function(e) jlog("telegram_failed", err = conditionMessage(e)))
# ★[팩터 분석] — 산출물이 있을 때만 보낸다 · 없으면 사유를 남긴다(침묵 누락 금지 · 정본 telegram_notify.R::tg_pass_analysis)
if (file.exists(file.path(dirname(ar), "analysis_multifactor.csv")) || file.exists(file.path(dirname(ar), "analysis_fmb_summary.csv"))) {
  tryCatch(tg_pass_analysis(.tg_target_label(TITLE, PKEY), dirname(ar)), error = function(e) jlog("factor_tg_failed", err = conditionMessage(e)))
} else jlog("factor_analysis_absent", dir = dirname(ar), note = "FF/FMB 산출물 없음 — FACTORS 부재이거나 분석 실패")
system2("Rscript", c(shQuote(file.path(ROOT, "02_Infrastructure/programs/next_replication.R")), "--root", shQuote(ROOT)), wait = TRUE)
quit(status = 0)
