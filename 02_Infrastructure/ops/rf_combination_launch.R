#!/usr/bin/env Rscript
#==============================================================================
# rf_combination_launch.R — 논문 간 결합 라운드 **착수** (2026-08-31 도훈 지시)
#
# 왜 이 파일이 생겼나:
#   rf_combination_review.R 이 논문 3편마다 결합 후보를 쌓아 왔지만(4회 · 10쌍),
#   그 후보를 **소비하는 코드가 없었다**. 검토 note 가 스스로 "착수하지 않는다 —
#   결합 라운드는 새 격자 설계가 필요해 규칙으로 환원되지 않는다" 고 적어 두었고,
#   세션도 착수한 적이 없다. 생산자만 있고 소비자가 없는 계기였다.
#
#   새 격자는 필요 없다 — 결합은 **기저 신호를 바꾸는 일**이지 격자를 바꾸는 일이 아니다.
#   다만 그 기저를 무엇으로 만드느냐가 2026-09-04 에 바뀌었다(도훈 지시).
#     구판: 두 엔진 신호의 rank-Z 평균(base_signal.kind="engine_blend") → **재지 않고** 25칸 개설.
#     현행: **LLM 이 두 논문 원문을 읽고 결합 전략을 설계**하고(engine.R 1파일),
#           그것을 충실구현 1회로 측정해 base_grade 를 얻은 뒤 base_min_port_t 를 통과해야 25칸.
#   그래서 이 파일이 하는 일은 entry 개설이 아니라 **설계 요청 발행**이다 —
#   측정·게이트·entry 개설은 충실구현 레인(rf_replication_auto.sh → rf_replication_verify.R)이 한다.
#
# 후보 선정이 검토기보다 엄격한 이유:
#   검토기의 판정은 "둘 다 다중검정 t > 0" 하나뿐이라 후보가 부풀려진다. 실측 10쌍 중
#   서로 다른 논문 쌍은 사실상 하나였다 — 같은 논문의 승격 사슬(원본·promo1·promo1r)이
#   별개 entry 라 4가지 조합으로 세어졌고, park 된 오염 판까지 후보에 있었다.
#   여기서는 ①논문(paper_key) 단위로 접고 ②parked/superseded 는 제외하며
#   ③엔진 경로가 실재하는 것만 남긴다.
#
# 사용:
#   Rscript rf_combination_launch.R            # 최고 후보 1쌍의 설계 요청 발행
#   Rscript rf_combination_launch.R --dry-run  # 무엇을 요청할지만 보고 쓰지 않는다
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
# ★격리 root (검사 전용 — 평시엔 미설정이라 아무 영향이 없다).
#   QM_ROOT 로는 격리가 안 된다: ~/.Renviron 이 같은 이름을 정의해 **R 시작 시 셸 값을 덮는다**.
#   그래서 셸에서 QM_ROOT=<임시> 를 줘도 자식 Rscript 는 진짜 root 를 본다 —
#   격리 사본을 쓰려던 검사가 조용히 공유 원장·공유 요청 파일을 만지게 되는 경로다.
#   (코드베이스에 QVEST_RF_CONFIG·QVEST_RF_CLAIM·QVEST_RP_REQUEST 가 따로 있는 이유가 이것.)
ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
setwd(ROOT)
DRY  <- any(c("--dry-run", "--dry") %in% commandArgs(TRUE))
LOG  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
# ★로그 디렉터리 보장 — 러너 2종은 이미 하는데 여기만 없었다. 없으면 jlog 첫 줄에서 죽는다.
dir.create(dirname(LOG), recursive = TRUE, showWarnings = FALSE)
jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "combo_launch"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG, append = TRUE)
  cat(sprintf("[combo] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse = ","), 1, 90))),
                    sep = "=", collapse = " ")))
}
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))

# ── ★결합 레인 게이트 (2026-09-04 도훈 지시) ─────────────────────────────────
#   구판은 rank-Z 평균 blend 로 기저를 만들고 **재지 않은 채** 25칸을 열었다
#   (base_grade="NA" — 위 주석이 "여기서 하는 일은 entry 를 하나 여는 것뿐" 이라 적은 그것).
#   그래서 단독 논문 레인의 base_min_port_t 가드가 결합에서만 발화 불가였고,
#   결합 entry 5건 × 25칸 = 125칸이 기저 검증 없이 소진됐다.
#   도훈 지시: 결합은 **LLM 이 두 논문을 읽고 전략(기저)을 설계**한 뒤 그것을 한 번
#   측정하고(충실구현 1회) 나서 강화 25칸으로 간다. 그 설계 레인이 서기 전까지는
#   구판 blend 착수를 막는다 — 막히면 호출자는 다음 논문 충실구현으로 정상 이월한다.
.CFGP <- file.path(ROOT, "06_Registry/reinforce_auto_config.json")
.CFG  <- if (file.exists(.CFGP)) fromJSON(.CFGP, simplifyVector = FALSE) else list()
if (!isTRUE(.CFG$combination$enabled %||% FALSE)) {
  jlog("halt_combination_disabled",
       note = .CFG$combination$note %||% "결합 착수 정지 — LLM 전략설계 레인 대기(2026-09-04)")
  quit(status = 0)
}

led <- rf_load(1L, ROOT)
if (length(Filter(function(e) identical(e$status, "active"), led$entries))) {
  jlog("halt_active_exists", note = "진행 중인 강화가 있다 — 결합은 그 뒤에"); quit(status = 0)
}

# ── 1. 논문 단위로 접는다 (entry 가 아니라 paper_key 가 단위) ────────────────
#   같은 논문의 승격 사슬은 한 논문이다. parked/superseded 는 무효 판이라 제외한다.
by_paper <- list()
.CUR_AXIS <- as.character(led$current_axis %||% "")
for (e in led$entries) {
  if (identical(e$status, "parked") || identical(e$status, "superseded")) next
  pk <- as.character(e$paper_key %||% "")
  ep <- as.character(e$engine_path %||% "")
  if (!nzchar(pk) || !nzchar(ep) || !file.exists(ep)) next
  # ★축 필터 (2026-09-04) — 앵커 a_t/b_t 가 축을 안 가리고 있었다. 2608.27076 의 1.191 은
  #   폐기된 legacy_double_selection_n3 축 값인데, 그 수치가 쌍 선정과 "결합이 희석인가"
  #   판정 기준을 동시에 정하고 있었다. 폐기된 자로 잰 값은 앵커가 아니다.
  #   ⇒ 현행 축 측정만 후보로 쓴다. 후보가 마르면 마른 대로 — 단독 논문 레인이 채운다.
  if (isFALSE(e$axis_valid %||% TRUE)) next
  if (nzchar(.CUR_AXIS) && nzchar(as.character(e$measurement_axis %||% "")) &&
      !identical(as.character(e$measurement_axis), .CUR_AXIS)) next
  # ★결합 entry 는 풀에 넣지 않는다. 넣으면 "27156 + (27156+27076)" 처럼 **같은 논문이
  #   두 번** 들어간 조합이 생긴다 — 결합의 결합은 다른 층이고, 여기서는 논문 쌍만 만든다.
  #   (engine_path 도 a 쪽 하나만 들고 있어 blend 를 재현하지도 못한다.)
  if (startsWith(pk, "combo:")) next
  pts <- vapply(e$attempts %||% list(), function(a) {
    v <- tryCatch(as.numeric(a$essence$port_t), error = function(z) NA_real_)
    if (length(v) != 1L) NA_real_ else v }, numeric(1))
  best_t <- if (length(pts) && any(is.finite(pts))) max(pts, na.rm = TRUE) else NA_real_
  # 기저 자체의 t 도 후보 자격에 쓴다 — 강화를 안 돌린 논문(0칸)도 신호는 있다
  ap <- file.path(e$base_artifacts %||% "", "authoritative_remeasure.json")
  base_t <- if (nzchar(ap) && file.exists(ap))
    tryCatch(as.numeric(fromJSON(ap, simplifyVector = TRUE)$essence$portfolio_alpha_t_nw_lag3 %||%
                        fromJSON(ap, simplifyVector = TRUE)$essence$port_t), error = function(z) NA_real_) else NA_real_
  tt <- suppressWarnings(max(c(best_t, base_t), na.rm = TRUE))
  if (!is.finite(tt)) tt <- NA_real_
  # ★원문 링크·제목 — 설계 에이전트가 두 논문을 **읽어야** 하므로 여기서 같이 들고 간다.
  #   구판은 engine 경로만 들고 갔다(그래서 결합이 "두 엔진의 rank-Z 평균" 밖에 될 수 없었다).
  .sp <- if (nzchar(ap) && file.exists(ap))
    tryCatch(fromJSON(ap, simplifyVector = FALSE)$replication$source_paper, error = function(z) NULL) else NULL
  prev <- by_paper[[pk]]
  if (is.null(prev) || (is.finite(tt) && (!is.finite(prev$t) || tt > prev$t)))
    by_paper[[pk]] <- list(paper_key = pk, engine = ep, t = tt, base_id = e$base_id,
                           url = as.character(.sp$url %||% ""), title = as.character(.sp$title %||% ""))
}
P <- Filter(function(x) is.finite(x$t), by_paper)
jlog("papers_pooled", n = length(P),
     keys = paste(vapply(P, function(x) x$paper_key, character(1)), collapse = ","))
if (length(P) < 2L) { jlog("halt_too_few_papers", n = length(P)); quit(status = 0) }

# ── 1b. 이미 돌린 쌍은 제외 ─────────────────────────────────────────────────
#   ★없으면 매 주기 같은 쌍(최고 점수)을 다시 연다. 결합 entry 의 paper_key 는
#   "combo:a+b" 형태라 거기서 되읽는다. 순서 무관하게 본다(a+b 와 b+a 는 같은 쌍).
.pairkey <- function(x, y) paste(sort(c(x, y)), collapse = "|")
.done_pairs <- unique(unlist(lapply(led$entries, function(e) {
  pk <- as.character(e$paper_key %||% "")
  if (!startsWith(pk, "combo:")) return(NULL)
  ab <- strsplit(sub("^combo:", "", pk), "+", fixed = TRUE)[[1]]
  if (length(ab) != 2L) return(NULL)
  .pairkey(ab[1], ab[2])
})))
if (length(.done_pairs)) jlog("pairs_already_done", n = length(.done_pairs),
                              keys = paste(.done_pairs, collapse = ","))

# ── 2. 쌍 만들기 — 둘 다 양수 t. 높은 합 순 ─────────────────────────────────
#   ★상관은 여기서 재지 않는다. 두 엔진을 다 돌려야 알 수 있고 그건 착수와 같은 비용이다.
#   대신 첫 셀(B1_1)의 결과가 곧 결합 기저의 성적이라 한 칸이면 판정이 선다.
V <- P[order(-vapply(P, function(x) x$t, numeric(1)))]
pairs <- list()
for (a in seq_along(V)) for (b in seq_along(V)) {
  if (b <= a) next
  if (!(V[[a]]$t > 0 && V[[b]]$t > 0)) next
  # ★설계 에이전트가 **두 논문을 읽어야** 하므로 원문 링크가 없는 쪽은 쌍을 이룬지 못한다.
  if (!nzchar(V[[a]]$url %||% "") || !nzchar(V[[b]]$url %||% "")) next
  if (.pairkey(V[[a]]$paper_key, V[[b]]$paper_key) %in% .done_pairs) next
  pairs[[length(pairs) + 1L]] <- list(a = V[[a]], b = V[[b]], score = V[[a]]$t + V[[b]]$t)
}
if (!length(pairs)) { jlog("halt_no_new_pair", note = "양수 쌍이 없거나 남은 쌍을 이미 다 돌렸다"); quit(status = 0) }
pairs <- pairs[order(-vapply(pairs, function(x) x$score, numeric(1)))]
top <- pairs[[1]]
cat(sprintf("\n결합 후보 %d쌍 · 1위 = %s (t %.3f) + %s (t %.3f)\n\n",
            length(pairs), top$a$paper_key, top$a$t, top$b$paper_key, top$b$t))
for (k in seq_len(min(5L, length(pairs)))) {
  p <- pairs[[k]]
  cat(sprintf("  %d. %-14s (t %6.3f)  +  %-14s (t %6.3f)   합 %.3f\n",
              k, p$a$paper_key, p$a$t, p$b$paper_key, p$b$t, p$score))
}

if (DRY) { jlog("dry_run", pair = paste(top$a$paper_key, top$b$paper_key, sep = "+")); quit(status = 0) }

# ── 3. 결합 **설계 요청** 발행 (2026-09-04 도훈 지시) ────────────────────────
#   구판은 여기서 곧장 entry 를 열었다 — 기저는 두 엔진의 rank-Z 평균이고 base_grade="NA",
#   즉 **결합 기저를 한 번도 재지 않은 채** 25칸을 열었다. 그래서 단독 논문 레인의
#   base_min_port_t 가드가 결합에서만 발화 불가였고, 결합 entry 5건 × 25칸 = 125칸이
#   기저 검증 없이 소진됐다. 그리고 이 파일의 옛 주석이 스스로 인정했듯 engine_path 는
#   a 쪽 하나뿐이라 blend 를 재현하지도 못했다.
#
#   지금은 **충실구현 레인에 일을 넘긴다**. 그쪽에는 이미 다 있다:
#     설계 에이전트(권한축소·claim·타임아웃) → 계약 측정 → base_min_port_t 게이트 →
#     rf_open_entry(base_grade=실측) → 텔레그램 → 강화 재개.
#   여기서 새로 만들 것은 "무엇을 설계하라" 는 요청뿐이다.
REQ <- file.path(ROOT, "06_Registry/replication_request.json")
.cur <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) NULL)
if (!is.null(.cur) && (.cur$status %||% "") %in% c("pending", "in_progress")) {
  jlog("halt_request_busy", status = .cur$status %||% "",
       note = "충실구현 요청이 아직 열려 있다 — 덮어쓰지 않는다")
  quit(status = 0)
}
PAIR <- sprintf("combo:%s+%s", top$a$paper_key, top$b$paper_key)
req <- list(
  requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  source = "rf_combination_launch",
  reason = "논문 결합 — LLM 전략설계 후 충실구현 1회로 기저를 측정한다(도훈 지시 2026-09-04)",
  paper = list(title = sprintf("결합: %s + %s", top$a$title, top$b$title),
               paper_title = sprintf("결합: %s + %s", top$a$title, top$b$title),
               url = top$a$url, paper_key = PAIR, source = "combination"),
  # ★결합 표식 — 러너·검증기가 이 키로 분기한다. 앵커는 **현행 축 측정만** 담겼다.
  combo = list(a = top$a$paper_key, b = top$b$paper_key,
               a_url = top$a$url, b_url = top$b$url,
               a_title = top$a$title, b_title = top$b$title,
               a_engine = top$a$engine, b_engine = top$b$engine,
               a_t = top$a$t, b_t = top$b$t,
               axis = as.character(led$current_axis %||% ""),
               dilution_test = sprintf(
                 "희석 판정 = 설계 기저 PORT_t vs max(a_t,b_t)=%.3f (같은 축). 기록만 하고 차단하지 않는다 — 격자는 기저 **위에** 쌓으므로 부모보다 낮은 기저에서도 강화가 뒤집을 수 있다.",
                 max(top$a$t, top$b$t)),
               count_paper = FALSE),
  status = "pending")
write(toJSON(req, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
jlog("combination_design_requested", pair = paste(top$a$paper_key, top$b$paper_key, sep = "+"),
     a_t = top$a$t, b_t = top$b$t, axis = as.character(led$current_axis %||% ""), req = REQ)
cat(sprintf("
결합 설계 요청 발행: %s
  a = %s (t %.3f)
  b = %s (t %.3f)
  다음 tick 이 설계 에이전트를 띄우고, 그 기저를 한 번 측정한 뒤 등급이 문턱을 넘으면 25칸을 엽니다.
",
            PAIR, top$a$paper_key, top$a$t, top$b$paper_key, top$b$t))
