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
# ★--directed=<key1,key2,...> (2026-09-21 도훈 승인 플랜 Part 3 · D3 (b)) — 리서치 디렉터의 지시 결합. **후보 선정만** 우회한다:
#   재료는 적격 풀 P(양수 t · 비파킹 · 엔진 존재 · url 보유) 안에서만 고르고, 스킵리스트·요청 슬롯 busy·발행 형식은 그대로다.
#   지시 재료가 P 밖이면 halt_directed_ineligible 로 물러난다 — 레인의 자격 규칙은 지시로 완화되지 않는다.
DKEYS <- { .a <- grep("^--directed=", commandArgs(TRUE), value = TRUE)
           if (length(.a)) { .k <- trimws(strsplit(sub("^--directed=", "", .a[1]), ",", fixed = TRUE)[[1]]); .k[nzchar(.k)] } else character(0) }
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

# ── 1. 풀 구성 — 결합의 단위는 "재료 하나" 다 (2026-09-04 재편) ─────────────
#   ★도훈 지시: 결합에 들어가는 논문 수도, 만들어지는 결합의 개수도 제한하지 않는다.
#   그래서 풀의 원소를 "논문" 이 아니라 **재료(item)** 로 일반화한다:
#     · 단독 논문 entry  → 재료 1개(구성 논문 1편)
#     · 결합 entry       → 재료 1개(구성 논문 N편)  ← 결합의 결합이 여기서 열린다
#   구판은 결합 entry 를 풀에서 통째로 뺐다. 뺀 이유는 "같은 논문이 두 번 들어간 조합"을
#   막기 위해서였는데, 그건 배제가 아니라 **구성 논문 집합의 서로소 판정**으로 풀 문제다.
by_item <- list()
.CUR_AXIS <- as.character(led$current_axis %||% "")
#' 결합 entry 의 구성 논문 키 — "combo:a+b+c" 를 펼친다
.papers_of_key <- function(pk) {
  if (!startsWith(pk, "combo:")) return(pk)
  strsplit(sub("^combo:", "", pk), "+", fixed = TRUE)[[1]]
}
for (e in led$entries) {
  if (identical(e$status, "parked") || identical(e$status, "superseded")) next
  pk <- as.character(e$paper_key %||% "")
  ep <- as.character(e$engine_path %||% "")
  if (!nzchar(pk) || !nzchar(ep) || !file.exists(ep)) next
  # ★축 필터 — 앵커가 축을 안 가리면 폐기된 자로 잰 값이 판정 기준이 된다
  #   (2608.27076 의 t 1.191 은 legacy_double_selection_n3 축 값이었다).
  if (isFALSE(e$axis_valid %||% TRUE)) next
  if (nzchar(.CUR_AXIS) && nzchar(as.character(e$measurement_axis %||% "")) &&
      !identical(as.character(e$measurement_axis), .CUR_AXIS)) next
  pts <- vapply(e$attempts %||% list(), function(a) {
    v <- tryCatch(as.numeric(a$essence$port_t), error = function(z) NA_real_)
    if (length(v) != 1L) NA_real_ else v }, numeric(1))
  best_t <- if (length(pts) && any(is.finite(pts))) max(pts, na.rm = TRUE) else NA_real_
  ap <- file.path(e$base_artifacts %||% "", "authoritative_remeasure.json")
  base_t <- if (nzchar(ap) && file.exists(ap))
    tryCatch(as.numeric(fromJSON(ap, simplifyVector = TRUE)$essence$portfolio_alpha_t_nw_lag3 %||%
                        fromJSON(ap, simplifyVector = TRUE)$essence$port_t), error = function(z) NA_real_) else NA_real_
  tt <- suppressWarnings(max(c(best_t, base_t), na.rm = TRUE))
  if (!is.finite(tt)) tt <- NA_real_
  # 원문 링크·제목 — 설계자가 **구성 논문 전부**를 읽어야 한다.
  #   결합 재료면 그 entry 의 combo 기록에서 구성 논문을 되읽는다(없으면 키만이라도).
  .sp <- if (nzchar(ap) && file.exists(ap))
    tryCatch(fromJSON(ap, simplifyVector = FALSE)$replication$source_paper, error = function(z) NULL) else NULL
  keys <- .papers_of_key(pk)
  papers <- if (length(keys) == 1L) {
    list(list(key = keys, url = as.character(.sp$url %||% ""), title = as.character(.sp$title %||% "")))
  } else {
    .cb <- e$combo %||% list()
    .src <- .cb$papers %||% list()
    if (length(.src) == length(keys)) lapply(.src, function(x)
      list(key = as.character(x$key %||% ""), url = as.character(x$url %||% ""),
           title = as.character(x$title %||% "")))
    else lapply(keys, function(k) list(key = k, url = "", title = k))
  }
  prev <- by_item[[pk]]
  if (is.null(prev) || (is.finite(tt) && (!is.finite(prev$t) || tt > prev$t)))
    by_item[[pk]] <- list(item_key = pk, engine = ep, t = tt, base_id = e$base_id,
                          papers = papers, keys = keys)
}
# 구성 논문의 원문 링크가 하나라도 비면 설계자가 읽을 수 없다 — 그 재료는 못 쓴다.
.has_urls <- function(x) all(vapply(x$papers, function(q) nzchar(q$url %||% ""), logical(1)))
P <- Filter(function(x) is.finite(x$t) && .has_urls(x), by_item)
jlog("items_pooled", n = length(P),
     keys = paste(vapply(P, function(x) x$item_key, character(1)), collapse = ","))
if (length(P) < 2L) { jlog("halt_too_few_papers", n = length(P)); quit(status = 0) }

# ── 2. 부분집합 열거 — 크기 2..N, 구성 논문이 서로소인 것만 ──────────────────
#   ★"조합 갯수 제한 없음"(도훈 2026-09-04). 크기도 고정하지 않는다.
#   유일한 한계는 **계산량**이다: 재료 m 개의 부분집합은 2^m 이라 m 이 커지면 폭발한다.
#   그래서 t 상위 재료로 열거 폭만 자른다 — 연구 제한이 아니라 열거 예산이고,
#   잘린 재료도 다음 회차에 상위로 올라오면 그때 들어온다.
V <- P[order(-vapply(P, function(x) x$t, numeric(1)))]
ENUM_M <- min(length(V), as.integer(.CFG$combination$enumerate_top_items %||% 12L))
V <- V[seq_len(ENUM_M)]
.setkey <- function(items) paste(sort(unique(unlist(lapply(items, function(x) x$keys)))), collapse = "+")
# 이미 착수한 구성 — **금지가 아니라 후순위**다. 같은 재료 집합이라도 설계가 다르면
# 다른 전략이므로 재도전 자체는 막지 않는다(도훈 2026-09-04). 미착수를 먼저 소진할 뿐이다.
.tried_v <- unlist(lapply(led$entries, function(e) {
  pk <- as.character(e$paper_key %||% "")
  if (!startsWith(pk, "combo:")) return(NULL)
  paste(sort(.papers_of_key(pk)), collapse = "+")
}))
# ★table(NULL) 은 에러고, table[[없는이름]] 도 에러다 — 결합 이력이 0건인
#   첫 회차가 정확히 그 상황이다. 없으면 0회로 읽는다.
.tried <- if (length(.tried_v)) table(.tried_v) else NULL
# ★스킵리스트 존중 (2026-09-04 실사고) — 결합 설계가 3회 연속 실패해 스킵리스트에 오른
#   직후 이 런처가 **같은 쌍을 즉시 재요청**했다(tries_before=3 으로 4회차 착수). 실패한
#   쌍이 유일한 후보이면 무한히 되풀이한다 — 한 번에 에이전트 3회 + 측정 3회를 태우면서.
#   ★금지가 아니라 **후순위 최하**다(AX-000): 다른 쌍이 없을 때만, 그리고 status 가
#     revoked 로 바뀌면 다시 정상 후보가 된다. 판정 철회 경로를 막지 않는다.
.skip_keys <- tryCatch({
  sp <- file.path(ROOT, "06_Registry/replication_skiplist.json")
  if (!file.exists(sp)) character(0) else {
    sk <- fromJSON(sp, simplifyVector = FALSE)
    ks <- vapply(sk$entries %||% list(), function(e) {
      st <- as.character(e$status %||% "")
      pk <- as.character(e$paper_key %||% "")
      if (identical(st, "revoked") || !startsWith(pk, "combo:")) NA_character_
      else paste(sort(.papers_of_key(pk)), collapse = "+")
    }, character(1))
    unique(ks[!is.na(ks)])
  } }, error = function(e) character(0))
if (length(.skip_keys)) jlog("skiplist_pairs", n = length(.skip_keys),
                             keys = paste(.skip_keys, collapse = ","))
.ntry_of <- function(k) { if (is.null(.tried)) return(0L)
                          v <- .tried[k]; if (is.na(v)) 0L else as.integer(v) }
if (length(DKEYS)) {
  ## ── 지시 결합 (D3) — 열거·순위 없이 지시 재료로 top 을 만든다. 적격 풀 P 안에서만 · 논문 중복 금지 ──
  sel <- Filter(function(x) any(x$keys %in% DKEYS), P)
  cov <- unique(unlist(lapply(sel, function(x) x$keys)))
  miss <- setdiff(DKEYS, cov)
  if (length(miss) || length(sel) < 2L) {
    jlog("halt_directed_ineligible", missing = paste(miss, collapse = ","), n_sel = length(sel), keys = paste(DKEYS, collapse = ","),
         note = "지시 재료가 적격 풀(P)에 없다 — 양수 t·비파킹·엔진·url 규칙은 지시로 완화되지 않는다(디렉터는 unreachable 로 기록)")
    quit(status = 0) }
  if (anyDuplicated(unlist(lapply(sel, function(x) x$keys)))) { jlog("halt_directed_overlap", keys = paste(DKEYS, collapse = ","), note = "지시 재료끼리 논문이 겹친다"); quit(status = 0) }
  top <- list(items = sel, k = length(sel), n_papers = length(cov), setkey = .setkey(sel), score = sum(vapply(sel, function(x) x$t, numeric(1))))
  combos <- list(top); V <- sel
  jlog("directed_pair", setkey = top$setkey, keys = paste(DKEYS, collapse = ","), n_items = top$k, n_papers = top$n_papers)
} else {
combos <- list()
.rec <- function(start, cur) {
  if (length(cur) >= 2L) {
    .kk <- unlist(lapply(cur, function(x) x$keys))
    if (!anyDuplicated(.kk))          # 같은 논문이 두 번 들어간 조합은 결합이 아니다
      combos[[length(combos) + 1L]] <<- list(
        items = cur, k = length(cur), n_papers = length(.kk),
        setkey = .setkey(cur),
        score = sum(vapply(cur, function(x) x$t, numeric(1))))
  }
  if (start > length(V)) return(invisible(NULL))
  for (j in seq(start, length(V))) {
    .nk <- c(unlist(lapply(cur, function(x) x$keys)), V[[j]]$keys)
    if (anyDuplicated(.nk)) next
    .rec(j + 1L, c(cur, list(V[[j]])))
  }
}
.rec(1L, list())
combos <- Filter(function(x) all(vapply(x$items, function(z) z$t > 0, logical(1))), combos)
if (!length(combos)) { jlog("halt_no_new_pair", note = "양수 재료가 2개 미만이다"); quit(status = 0) }
# 미착수 우선 → 그 다음 착수 횟수 적은 순 → 점수 높은 순
.ntry <- vapply(combos, function(x) .ntry_of(x$setkey), integer(1))
# ★스킵리스트 쌍은 최하위로 — 배제가 아니라 후순위다(다른 후보가 없으면 그때는 간다).
.skipped <- vapply(combos, function(x) as.integer(x$setkey %in% .skip_keys), integer(1))
.scr  <- vapply(combos, function(x) x$score, numeric(1))
combos <- combos[order(.skipped, .ntry, -.scr)]
jlog("combos_enumerated", n = length(combos), enum_items = length(V),
     untried = sum(.ntry == 0L), max_k = max(vapply(combos, function(x) x$k, integer(1))))
top <- combos[[1]]
}
if (top$setkey %in% .skip_keys) {
  jlog("halt_all_pairs_skiplisted", setkey = top$setkey, n = length(combos),
       note = "남은 후보가 전부 스킵리스트 — 결합은 물러난다(다음 논문으로 이월). 철회 = status revoked")
  quit(status = 0)
}
.tries_before <- .ntry_of(top$setkey)

cat(sprintf("\n결합 후보 %d건(재료 %d개 열거) · 1위 = %s (재료 %d · 논문 %d · 합 %.3f · 기왕 착수 %d회)\n\n",
            length(combos), length(V), top$setkey, top$k, top$n_papers, top$score, .tries_before))
for (k in seq_len(min(5L, length(combos)))) {
  q <- combos[[k]]
  cat(sprintf("  %d. %-34s  재료 %d · 논문 %d · 합 %6.3f · 착수 %d회\n",
              k, substr(q$setkey, 1, 34), q$k, q$n_papers, q$score,
              .ntry_of(q$setkey)))
}

if (DRY) { jlog("dry_run", setkey = top$setkey, k = top$k); quit(status = 0) }

# ── 3. 결합 **설계 요청** 발행 ───────────────────────────────────────────────
#   구판은 여기서 곧장 entry 를 열었다 — 기저는 두 엔진의 rank-Z 평균이고 base_grade="NA",
#   즉 **결합 기저를 한 번도 재지 않은 채** 25칸을 열었다(entry 5건 × 25칸 = 125칸 무검증).
#   지금은 충실구현 레인에 넘긴다: 설계 에이전트 → 계약 측정 → base_min_port_t → entry 개설.
REQ <- file.path(ROOT, "06_Registry/replication_request.json")
.cur <- tryCatch(fromJSON(REQ, simplifyVector = FALSE), error = function(e) NULL)
if (!is.null(.cur) && (.cur$status %||% "") %in% c("pending", "in_progress")) {
  jlog("halt_request_busy", status = .cur$status %||% "",
       note = "충실구현 요청이 아직 열려 있다 — 덮어쓰지 않는다")
  quit(status = 0)
}
.papers <- do.call(c, lapply(top$items, function(x) x$papers))
PAIR <- paste0("combo:", top$setkey)
.titles <- paste(vapply(.papers, function(q) as.character(q$title %||% q$key), character(1)), collapse = " + ")
req <- list(
  requested_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  source = "rf_combination_launch",
  reason = "논문 결합 — LLM 전략설계 후 충실구현 1회로 기저를 측정한다(도훈 지시 2026-09-04)",
  paper = list(title = sprintf("결합: %s", .titles), paper_title = sprintf("결합: %s", .titles),
               url = as.character(.papers[[1]]$url), paper_key = PAIR, source = "combination"),
  combo = list(
    setkey = top$setkey, k_items = top$k, n_papers = top$n_papers,
    papers = .papers,
    item_engines = lapply(top$items, function(x) list(key = x$item_key, engine = x$engine, t = x$t)),
    parent_t = vapply(top$items, function(x) x$t, numeric(1)),
    best_parent_t = max(vapply(top$items, function(x) x$t, numeric(1))),
    tries_before = .tries_before,
    axis = .CUR_AXIS,
    dilution_test = sprintf(
      "희석 판정 = 설계 기저 PORT_t vs 최고 재료 t %.3f (같은 축). 기록만 하고 차단하지 않는다 — 격자는 기저 **위에** 쌓으므로 재료보다 낮은 기저에서도 강화가 뒤집을 수 있다.",
      max(vapply(top$items, function(x) x$t, numeric(1)))),
    count_paper = FALSE),
  status = "pending")
write(toJSON(req, auto_unbox = TRUE, pretty = TRUE, null = "null"), REQ)
jlog("combination_design_requested", setkey = top$setkey, k_items = top$k,
     n_papers = top$n_papers, tries_before = .tries_before, axis = .CUR_AXIS, req = REQ)
## >>> O0a 시행 로그(P1-02 · 설계 organic_design_final §3 G1) — 결합 결정 1건(선택 = 발행한 조합 · 기각 = 열거된 나머지 · 판정 불변)
tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_trial_producers.R")))
  .tl_c <- if (exists("combos", inherits = FALSE) && length(combos)) combos else list(top)
  rf_tp_record("combination", "program",
    rf_tp_candidates(vapply(.tl_c, function(x) as.character(x$setkey), character(1)), NULL,   # 순위 = 실제 선정 순(정렬 뒤 combos 순서 그대로)
                     vapply(.tl_c, function(x) sprintf("재료 %d · 논문 %d · 점수 %.3f · 착수 %d회%s", as.integer(x$k %||% NA), as.integer(x$n_papers %||% NA),
                                                       as.numeric(x$score %||% NA), as.integer(.ntry_of(x$setkey)),
                                                       if (x$setkey %in% .skip_keys) " · 스킵리스트" else ""), character(1))),
    top$setkey, "02_Infrastructure/ops/rf_combination_launch.R(미착수 → 착수 적은 순 → 점수)",
    scope = list(block = "combination", setkey = top$setkey, by = if (length(DKEYS)) "directed" else "enumerated"), root = ROOT)
}, error = function(e) jlog("trial_log_failed", what = "combination", err = conditionMessage(e)))
## <<< O0a
cat(sprintf("\n결합 설계 요청 발행: %s\n  재료 %d개 · 구성 논문 %d편 · 기왕 착수 %d회\n  다음 tick 이 설계 에이전트를 띄우고, 그 기저를 한 번 측정한 뒤 등급이 문턱을 넘으면 25칸을 엽니다.\n",
            PAIR, top$k, top$n_papers, .tries_before))
