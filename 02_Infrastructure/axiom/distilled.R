# distilled.R — ②Distilled 계층 R-side helper (2026-07-04 엔진 재설계, 3층 산출물 모델)
#
# 엔진의 산출물은 승격이 아니라 재사용되는 지식이다. Distilled = Ledger(L-code 원장)와
# Law(axiom) 사이의 소비 단위 — 검색(hypothesis_index)·주입(axiom_context_inject)·
# negative failure-ledger가 이 계층을 소비한다.
#
# 데이터: qepm/memory/axioms/distilled/DIST-<MODE>-NNN.json (생성: cluster_extractor.py)
# 인덱스: 06_Registry/distilled_knowledge.json (단일 조회면)
#
# lifecycle: pending_5axis → [자동초안 + 적대검증] → proposed(주입 안 됨)
#            → [도훈 배치승인] → distilled(주입 가능) → promoted | expired
# INV-6 (2026-07-04 도훈 재정의): "무인 *정제* 금지" → "무인 *활성화* 금지".
#   statement_refined 초안(status=proposed)은 적대검증 붙여 자동화 허용.
#   단 활성화(status=distilled — 주입/truths/enforcement 소비)는 도훈 배치승인 게이트 필수.
#   주입 3배선(inject/hypothesis_index/strategic_truths)은 status=distilled만 소비
#   (proposed·pending_5axis 초안 텍스트 주입 금지 — INV-6 안전속성 보존).
# INV-7: negative distilled = provisional failure-ledger — 재시도 금지 라벨은
#        '불변 기각'이 아니라 'retry_condition 충족 + 차별점 명시 없인 재시도 금지'.
#
# 주요 함수:
#   load_distilled_index()                          — 인덱스 로드
#   lookup_distilled(keywords)                      — 키워드 AND 부분매치 조회 (status=distilled만 노출)
#   draft_proposed(dist_id, statement_refined, retry_condition=, adversarial_verdict=,
#                  expiry=, frontier=, live_trigger=, drafted_by="auto")
#                                                   — 자동초안 → status=proposed (주입 안 됨)
#     ★INV-7 negative 필수 필드: expiry + live_trigger + frontier. 방화벽 판정은 초안
#       에이전트(LLM)가 load_firewall_context()로 semantic 수행 후 위반 시 재작성해 넘긴다.
#       draft_proposed는 통과분만 받되, backstop(비-소진적) 가드가 명백 위반을 stop.
#   approve_proposed(dist_ids, approved_by="dohoon") — proposed → distilled (사람 승인 게이트)
#   list_proposed()                                 — status=proposed 목록 (모닝브리핑·다이제스트 소비)
#   refine_distilled(dist_id, statement_refined, retry_condition=, refined_by=)
#                                                   — /cleaner 수동 정제 → status=distilled (retain)
#   expire_distilled(dist_id, reason)               — status=expired
#   mark_promoted_distilled(dist_id, axiom_id)      — status=promoted (promote 후)
#   rebuild_distilled_index()                       — DIST 파일 → 인덱스 재작성
#   update_strategic_truths_distilled_block()       — strategic_truths.md generated 블록 갱신

suppressPackageStartupMessages(library(jsonlite))

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

.dist_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())
  for (p in cands) if (nzchar(p) && dir.exists(p)) return(p)
  stop("project root not found")
}
.dist_dir   <- function(root = .dist_root()) file.path(root, "qepm", "memory", "axioms", "distilled")
.dist_index <- function(root = .dist_root()) file.path(root, "06_Registry", "distilled_knowledge.json")

load_distilled_index <- function(root = .dist_root()) {
  ip <- .dist_index(root)
  if (!file.exists(ip)) return(list(n_entries = 0L, entries = list()))
  fromJSON(ip, simplifyVector = FALSE)
}

# ── 인덱스 재작성 (cluster_extractor._write_distilled_index와 동일 스키마) ──
rebuild_distilled_index <- function(root = .dist_root(), verbose = TRUE) {
  dd <- .dist_dir(root)
  files <- if (dir.exists(dd)) sort(list.files(dd, pattern = "^DIST-.*\\.json$", full.names = TRUE)) else character(0)
  entries <- list()
  for (f in files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    entries[[length(entries) + 1L]] <- list(
      dist_id = d$dist_id, research_mode = d$research_mode,
      family = (d$scope_draft %||% list())$factor_family,
      type = d$type, polarity = d$polarity, metric_type = d$metric_type,
      status = d$status,
      statement_refined = d$statement_refined, statement_draft = d$statement_draft,
      retry_condition = d$retry_condition,
      adversarial_verdict = d$adversarial_verdict,
      expiry = d$expiry,
      frontier = d$frontier %||% list(),           # INV-7: 미탐색 인접 경로(원리2)
      live_trigger = d$live_trigger %||% list(),    # INV-7: 부활 조건(원리4, 열린 스키마)
      constraint_firewall = d$constraint_firewall,  # 방화벽 판정 기록(원리3)
      supporting_l_codes = d$supporting_l_codes %||% list(),
      n_supporting = length(d$supporting_l_codes %||% list()),
      candidate_id = d$candidate_id, cluster_key = d$cluster_key,
      promoted_to_axiom = d$promoted_to_axiom,
      created_at = d$created_at, refined_at = d$refined_at,
      drafted_at = d$drafted_at, approved_at = d$approved_at,
      source_file = basename(f))
  }
  out <- list(
    schema_version = "distilled_knowledge_v1",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    note = paste0("Axiom 엔진 ②Distilled 계층 통합 인덱스. lifecycle: pending_5axis→",
                  "[자동초안+적대검증]→proposed→[도훈 배치승인]→distilled→promoted|expired. ",
                  "INV-6(2026-07-04 재정의: 무인 활성화 금지): 주입/truths 소비는 status=distilled만 ",
                  "— proposed·pending_5axis 초안 텍스트 주입 금지(안전속성 보존)."),
    n_entries = length(entries),
    n_distilled = sum(vapply(entries, function(e) identical(e$status, "distilled"), logical(1))),
    n_proposed = sum(vapply(entries, function(e) identical(e$status, "proposed"), logical(1))),
    entries = entries)
  write_json(out, .dist_index(root), pretty = TRUE, auto_unbox = TRUE, null = "null")
  if (verbose) cat(sprintf("[distilled] index rebuilt: %d entries (%d distilled, %d proposed) -> %s\n",
                           out$n_entries, out$n_distilled, out$n_proposed, .dist_index(root)))
  invisible(out)
}

# ── 조회: 키워드 AND 부분매치. negative는 재시도 금지/조건 라벨 동반 ──
# INV-6(2026-07-04 재정의): 주입/검색 소비면은 status=distilled만 노출.
#   proposed·pending_5axis 초안은 누출 금지(안전속성 보존). include_nondistilled=TRUE는
#   진단·감사 전용(주입 경로에서 호출 금지).
lookup_distilled <- function(keywords, root = .dist_root(), max_rows = 20L,
                             include_nondistilled = FALSE) {
  idx <- load_distilled_index(root)
  kws <- tolower(unlist(strsplit(paste(keywords, collapse = " "), "\\s+")))
  kws <- kws[nzchar(kws)]
  if (!length(kws)) stop("empty keywords")
  rows <- list()
  for (e in idx$entries %||% list()) {
    if (!include_nondistilled && !identical(e$status, "distilled")) next
    stmt <- e$statement_refined %||% e$statement_draft %||% ""
    hay <- tolower(paste(e$dist_id, e$research_mode, e$family %||% "", e$polarity,
                         e$status, stmt, paste(unlist(e$supporting_l_codes), collapse = " ")))
    if (all(vapply(kws, function(k) grepl(k, hay, fixed = TRUE), logical(1)))) {
      retry <- if (identical(e$polarity, "negative")) {
        rc <- e$retry_condition %||% ""
        if (nzchar(rc)) sprintf("재시도 조건: %s", rc)
        else "재시도 금지(INV-7 provisional — 차별점 명시 + 재도전 사유 기록 없인 진행 금지)"
      } else ""
      rows[[length(rows) + 1L]] <- data.frame(
        dist_id = e$dist_id, mode = e$research_mode %||% "",
        family = as.character(e$family %||% NA_character_),
        polarity = e$polarity %||% "", status = e$status %||% "",
        statement = substr(stmt, 1, 100),
        refined = !is.null(e$statement_refined) && nzchar(e$statement_refined %||% ""),
        retry_policy = retry, n_support = e$n_supporting %||% 0L,
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) { message("[distilled] no match: ", paste(kws, collapse = " ")); return(invisible(data.frame())) }
  df <- do.call(rbind, rows); rownames(df) <- NULL
  head(df, max_rows)
}

.dist_load_one <- function(dist_id, root = .dist_root()) {
  f <- file.path(.dist_dir(root), paste0(dist_id, ".json"))
  if (!file.exists(f)) stop("DIST not found: ", f)
  list(path = f, dist = fromJSON(f, simplifyVector = FALSE))
}

# ── quarantine 차단 가드 (draft/refine 공용) ──
.dist_block_quarantined <- function(d) {
  if (identical(d$status, "quarantined_evidence"))
    stop("evidence_audit_20260704: quarantined_evidence — 정제/초안 대상 제외 ",
         "(TAINTED_RETRACT_CANDIDATE. 도훈 confirm 후 expire 또는 분리 재정제. ",
         "근거: 04_Research/01_reports/knowledge_provenance_audit_20260704.md)")
  invisible(TRUE)
}

# ── 자동초안: statement_refined 초안 작성 → status=proposed (주입 안 됨) ──
# INV-6(2026-07-04 재정의) 초안 경로: 적대검증 붙여 자동화 허용. status=proposed로만 기록 —
#   활성화(distilled)가 아니므로 주입/truths 소비 대상 아님. 도훈 approve_proposed 게이트 필요.
draft_proposed <- function(dist_id, statement_refined, retry_condition = NULL,
                           adversarial_verdict = NULL, expiry = NULL,
                           frontier = NULL, live_trigger = NULL,
                           drafted_by = "auto", root = .dist_root()) {
  stopifnot(nzchar(statement_refined))
  if (grepl("\\[.*초안.*\\]|확정 필요", statement_refined))
    stop("INV-6: statement_refined에 초안 표식 잔존 — 정제문만 허용")
  x <- .dist_load_one(dist_id, root)
  d <- x$dist
  if (identical(d$status, "promoted")) stop("이미 promoted — 초안 불가(불변)")
  if (identical(d$status, "distilled")) stop("이미 distilled(활성화) — draft_proposed 부적용")
  .dist_block_quarantined(d)   # quarantined_evidence 6건 초안 대상 제외

  # ── INV-7 제약 방화벽 backstop 가드 (원리3) ──
  # semantic 판정은 초안 에이전트(LLM)가 load_firewall_context로 이미 수행했어야 한다.
  # 여기 backstop은 *비-소진적* 최종 가드 — 명백한 제약-귀속/완화-레버가 초안에 남아 있으면
  # stop해 오염 주입을 원천 차단. (semantic이 primary, 이건 마지막 그물.)
  fw_path <- file.path(root, "02_Infrastructure", "axiom", "constraint_firewall.R")
  if (file.exists(fw_path)) {
    local({ source(fw_path, local = TRUE)
      fw_txt <- paste(c(statement_refined, retry_condition %||% "",
                        unlist(frontier %||% list())), collapse = " \n ")
      r <- check_constraint_firewall(fw_txt, mode = "backstop", root = root)
      if (isFALSE(r$pass))
        stop("INV-7 제약 방화벽 backstop REJECT — 초안이 고정 제약을 원인 귀속하거나 ",
             "완화 레버로 제시. envelope-상대로 재작성 후 재제출.\n  ", r$suggestion,
             "\n  (semantic 판정은 초안 에이전트가 load_firewall_context로 선수행하는 것이 정칙)")
    })
  }

  d$statement_refined <- statement_refined
  if (!is.null(retry_condition)) d$retry_condition <- retry_condition
  if (!is.null(adversarial_verdict)) d$adversarial_verdict <- adversarial_verdict
  if (!is.null(expiry)) d$expiry <- expiry
  if (!is.null(frontier)) d$frontier <- frontier                # INV-7 필수(negative)
  if (!is.null(live_trigger)) d$live_trigger <- live_trigger    # INV-7 필수(negative)
  # negative polarity인데 필수 필드 결측 시 경고(하드 stop 아님 — 초안 반복 허용)
  if (identical(d$polarity, "negative")) {
    miss <- c(if (is.null(d$frontier)) "frontier", if (is.null(d$live_trigger)) "live_trigger",
              if (is.null(d$expiry)) "expiry")
    if (length(miss))
      warning(sprintf("[distilled] %s negative 초안 INV-7 필수 필드 결측: %s — 승인 전 보강 권고",
                      dist_id, paste(miss, collapse = ", ")))
  }
  d$constraint_firewall <- list(mode = "backstop_passed", checked_at = format(Sys.Date()))
  d$status <- "proposed"                 # ← 활성화 아님(주입 미소비)
  d$drafted_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  d$drafted_by <- drafted_by
  write_json(d, x$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[distilled] %s drafted → status=proposed (주입 안 됨, 도훈 승인 대기)\n", dist_id))
  rebuild_distilled_index(root, verbose = FALSE)
  # NOTE: proposed는 truths/inject 미소비 → strategic_truths 블록 갱신 안 함.
  invisible(d)
}

# ── 사람 승인 게이트: proposed → distilled (활성화) ──
# 벡터 dist_ids 배치 승인. proposed 아닌 건 skip+경고.
approve_proposed <- function(dist_ids, approved_by = "dohoon", root = .dist_root()) {
  stopifnot(length(dist_ids) >= 1)
  approved <- character(0); skipped <- character(0)
  for (id in dist_ids) {
    x <- tryCatch(.dist_load_one(id, root), error = function(e) NULL)
    if (is.null(x)) { warning(sprintf("[distilled] %s: DIST 파일 없음 — skip", id)); skipped <- c(skipped, id); next }
    d <- x$dist
    if (!identical(d$status, "proposed")) {
      warning(sprintf("[distilled] %s: status='%s' (proposed 아님) — skip", id, d$status %||% "NA"))
      skipped <- c(skipped, id); next
    }
    d$status <- "distilled"              # ← 활성화(주입 소비 시작)
    d$approved_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    d$approved_by <- approved_by
    if (is.null(d$refined_at)) d$refined_at <- d$drafted_at %||% format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
    write_json(d, x$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
    cat(sprintf("[distilled] %s approved → status=distilled (활성화)\n", id))
    approved <- c(approved, id)
  }
  if (length(approved)) {
    rebuild_distilled_index(root, verbose = FALSE)
    update_strategic_truths_distilled_block(root)   # distilled negative/conditional 재소집
  }
  invisible(list(approved = approved, skipped = skipped))
}

# ── proposed 목록 (모닝브리핑·다이제스트 소비용, 승인 대상 노출) ──
list_proposed <- function(root = .dist_root()) {
  idx <- load_distilled_index(root)
  rows <- list()
  for (e in idx$entries %||% list()) {
    if (!identical(e$status, "proposed")) next
    rows[[length(rows) + 1L]] <- data.frame(
      dist_id = e$dist_id %||% "",
      mode = e$research_mode %||% "",
      polarity = e$polarity %||% "",
      statement = substr(e$statement_refined %||% e$statement_draft %||% "", 1, 120),
      adversarial_verdict = as.character(e$adversarial_verdict %||% NA_character_),
      n_support = e$n_supporting %||% 0L,
      expiry = as.character(e$expiry %||% NA_character_),
      has_frontier = length(e$frontier %||% list()) > 0,       # INV-7 필수 필드 충족 여부
      has_live_trigger = length(e$live_trigger %||% list()) > 0,
      drafted_at = as.character(e$drafted_at %||% NA_character_),
      stringsAsFactors = FALSE)
  }
  if (!length(rows)) { message("[distilled] proposed 없음"); return(invisible(data.frame())) }
  df <- do.call(rbind, rows); rownames(df) <- NULL
  df
}

# ── /cleaner 수동 정제: statement_refined 작성 → status=distilled (수동 경로 retain) ──
# 자동 경로(draft_proposed→approve_proposed)와 별개. /cleaner 세션 수동 활성화 직행.
refine_distilled <- function(dist_id, statement_refined, retry_condition = NULL,
                             refined_by = "cleaner_session", root = .dist_root()) {
  stopifnot(nzchar(statement_refined))
  if (grepl("\\[.*초안.*\\]|확정 필요", statement_refined))
    stop("INV-6: statement_refined에 초안 표식 잔존 — 정제문만 허용")
  x <- .dist_load_one(dist_id, root)
  d <- x$dist
  if (identical(d$status, "promoted")) stop("이미 promoted — 정제 불가(불변)")
  .dist_block_quarantined(d)
  d$statement_refined <- statement_refined
  if (!is.null(retry_condition)) d$retry_condition <- retry_condition
  d$status <- "distilled"
  d$refined_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  d$refined_by <- refined_by
  write_json(d, x$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[distilled] %s refined → status=distilled\n", dist_id))
  rebuild_distilled_index(root, verbose = FALSE)
  update_strategic_truths_distilled_block(root)
  invisible(d)
}

expire_distilled <- function(dist_id, reason = "", root = .dist_root()) {
  x <- .dist_load_one(dist_id, root)
  d <- x$dist
  d$status <- "expired"; d$expired_at <- format(Sys.Date()); d$expire_reason <- reason
  write_json(d, x$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[distilled] %s → expired (%s)\n", dist_id, reason))
  rebuild_distilled_index(root, verbose = FALSE)
  update_strategic_truths_distilled_block(root)
  invisible(d)
}

mark_promoted_distilled <- function(dist_id, axiom_id, root = .dist_root()) {
  x <- .dist_load_one(dist_id, root)
  d <- x$dist
  d$status <- "promoted"; d$promoted_to_axiom <- axiom_id; d$promoted_at <- format(Sys.Date())
  write_json(d, x$path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  cat(sprintf("[distilled] %s → promoted (%s)\n", dist_id, axiom_id))
  rebuild_distilled_index(root, verbose = FALSE)
  invisible(d)
}

# ── strategic_truths.md DISTILLED generated 블록 갱신 ──
# 규약 (prompts/strategic_truths.md 헤더에도 명기):
#   - 블록 밖(수동 큐레이션 본문) 절대 보존 — 이 함수는 마커 사이만 교체.
#   - 블록 안 수동 수정 금지 — 재생성 시 소실.
#   - 소비 대상: status=distilled ∧ polarity∈{negative,conditional}만 (INV-6).
DIST_TRUTHS_START <- "<!-- DISTILLED_START"
DIST_TRUTHS_END   <- "<!-- DISTILLED_END -->"

update_strategic_truths_distilled_block <- function(root = .dist_root(), max_items = 8L) {
  tf <- file.path(root, "02_Infrastructure", "prompts", "strategic_truths.md")
  if (!file.exists(tf)) { warning("strategic_truths.md 없음 — 블록 갱신 생략"); return(invisible(FALSE)) }
  txt <- readLines(tf, encoding = "UTF-8", warn = FALSE)
  i_start <- grep(DIST_TRUTHS_START, txt, fixed = TRUE)
  i_end   <- grep(DIST_TRUTHS_END,   txt, fixed = TRUE)
  idx <- load_distilled_index(root)
  picks <- Filter(function(e) identical(e$status, "distilled") &&
                    (e$polarity %||% "") %in% c("negative", "conditional") &&
                    nzchar(e$statement_refined %||% ""),
                  idx$entries %||% list())
  # 최근 정제분 우선
  if (length(picks) > 1) {
    ord <- order(vapply(picks, function(e) e$refined_at %||% "", character(1)), decreasing = TRUE)
    picks <- picks[ord]
  }
  if (length(picks) > max_items) picks <- picks[seq_len(max_items)]
  body <- vapply(picks, function(e) {
    # (2026-07-05 감사) head-word를 inject/search 2면과 동일 지도-프레임으로 정렬.
    #   구 "재시도금지(INV-7 조건부)"는 유일하게 금지 어휘라 truths면에서만 낙인 톤 회귀 → 폐기.
    pol <- if (identical(e$polarity, "negative")) "탐색됨·재도전 대상(INV-7 조건부)" else "조건부(INV-7)"
    sprintf("  - [%s/%s] %s (%s, L-code %d건)", e$dist_id, pol, e$statement_refined,
            e$research_mode %||% "?", e$n_supporting %||% 0L)
  }, character(1))
  header <- paste0(DIST_TRUTHS_START, " — generated by 02_Infrastructure/axiom/distilled.R. ",
                   "블록 밖 수동 본문 절대 보존 · 블록 안 수동 수정 금지(재생성 시 소실) · ",
                   "소비: status=distilled ∧ negative/conditional만 (INV-6) -->")
  block <- c(header,
             if (length(body)) body else "  (아직 정제 완료된 distilled negative/conditional 없음 — /cleaner 세션에서 statement_refined 작성 시 자동 등재)",
             DIST_TRUTHS_END)
  if (length(i_start) && length(i_end) && i_start[1] < i_end[1]) {
    new_txt <- c(txt[seq_len(i_start[1] - 1L)], block,
                 if (i_end[1] < length(txt)) txt[(i_end[1] + 1L):length(txt)] else character(0))
  } else {
    new_txt <- c(txt, "", block)  # 마커 부재 — 파일 말미에 신설 (수동 본문 보존)
  }
  writeLines(new_txt, tf, useBytes = FALSE)
  cat(sprintf("[distilled] strategic_truths DISTILLED 블록 갱신: %d건\n", length(body)))
  invisible(TRUE)
}

# CLI: Rscript distilled.R [rebuild|lookup <kw...>|truths|list_proposed|approve <dist_id...>]
if (sys.nframe() == 0 && !interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1 && args[1] == "rebuild") {
    rebuild_distilled_index()
  } else if (length(args) >= 2 && args[1] == "lookup") {
    res <- lookup_distilled(args[-1]); if (nrow(res)) print(res, right = FALSE)
  } else if (length(args) >= 1 && args[1] == "truths") {
    update_strategic_truths_distilled_block()
  } else if (length(args) >= 1 && args[1] == "list_proposed") {
    res <- list_proposed(); if (nrow(res)) print(res, right = FALSE)
  } else if (length(args) >= 2 && args[1] == "approve") {
    print(approve_proposed(args[-1]))
  } else {
    cat("usage:\n  Rscript distilled.R rebuild\n  Rscript distilled.R lookup <keyword...>\n",
        "  Rscript distilled.R truths\n  Rscript distilled.R list_proposed\n",
        "  Rscript distilled.R approve <dist_id...>\n", sep = "")
  }
}
