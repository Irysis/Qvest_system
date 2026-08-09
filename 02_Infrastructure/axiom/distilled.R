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
#   supersede_subsumed_distilled(dry_run=)          — 부분집합 구 카드 자동 supersede
#     (판정 본체 = cluster_extractor.py::supersede_subsumed. 재등재 시 자동 실행되며
#      이 함수는 수동/감사 진입점 — 술어 재구현 아님)
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
      live_trigger = d$live_trigger %||% list(),    # INV-7: 부활 조건(원리4, 열린 스키마) — 사람용 표시
      revival_spec = d$revival_spec %||% list(),    # 기계용 부활 spec(구현 B) — monitor 소비
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

# ══ revival_spec 자동생성 (구현 B, 2026-07-05) ═══════════════════════════════
# 사람용 live_trigger(배열, {type,condition,monitored_source})는 표시용 — 절대 변경 금지.
# revival_spec(신규 optional)은 기계용 배열 — failure_revival_monitor.R가 소비:
#   각 원소 = {signal_id, condition, from_trigger, status('active'|'pending')}.
#   condition = 로드된 신호 현재값을 'x'로 참조하는 R 비교식.
# 신호명부(06_Registry/revival_signals.json)에 참조 signal_id가 없으면 pending 스텁 자동
#   append(자기증식) + 해당 spec 원소 status='pending' — 조용한 소실 금지(가시화).

.dist_revival_signals_path <- function(root = .dist_root())
  file.path(root, "06_Registry", "revival_signals.json")

# monitored_source 문자열에서 데이터원 slug 추출(type=data용). 알파벳/숫자/언더스코어만.
.dist_slug_from_source <- function(src) {
  s <- tolower(src %||% "")
  if (grepl("dart", s) && grepl("insider", s)) return("dart_insider_present")
  # generic: 첫 의미있는 토큰(괄호 안 예시 우선)에서 slug 생성.
  m <- regmatches(s, regexpr("[a-z][a-z0-9_]+", s))
  slug <- if (length(m) && nzchar(m)) m else "new_datasource"
  paste0(slug, "_present")
}

# 신호명부에 signal_id 없으면 pending 스텁 append(자기증식). 반환: TRUE=명부 존재(active)
# / FALSE=미등록이라 pending 스텁 추가함. registered_path 인자로 temp 명부 테스트 지원.
.dist_ensure_signal_registered <- function(signal_id, hint = list(),
                                           registry_path = .dist_revival_signals_path()) {
  if (is.null(signal_id) || !nzchar(signal_id)) return(TRUE)  # signal_id 없음 → 검증 대상 아님
  if (!file.exists(registry_path)) return(FALSE)              # 명부 부재 → 확정 불가, pending 취급
  reg <- tryCatch(fromJSON(registry_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(reg)) return(FALSE)
  sigs <- reg$signals %||% list()
  for (s in sigs) if (identical(s$signal_id %||% "", signal_id)) {
    # 이미 등록 — active면 TRUE, pending이면 FALSE(스텁 존재하되 미가동).
    return(identical(s$status %||% "active", "active"))
  }
  # 미등록 → pending 스텁 자동 append(자기증식 · 가시화).
  stub <- list(
    signal_id = signal_id,
    kind = hint$kind %||% "file_exists",
    source_path = hint$source_path %||% NULL,
    value_col = hint$value_col %||% NULL,
    sort_col = hint$sort_col %||% NULL,
    status = "pending",
    note = hint$note %||% sprintf(
      "auto-stub by distilled.R .dist_author_revival_spec (%s). 신호원 실측·확정 후 status='active'로 승격.",
      format(Sys.Date())))
  reg$signals <- c(sigs, list(stub))
  write_json(reg, registry_path, pretty = TRUE, auto_unbox = TRUE, null = "null")
  FALSE
}

# live_trigger(배열) + expiry → revival_spec 배열 생성(계약 §3 매핑).
#   registry_path 인자 = temp 명부 테스트/프로덕션 오염 회피용.
.dist_author_revival_spec <- function(d, registry_path = .dist_revival_signals_path()) {
  spec <- list()
  add <- function(signal_id, condition, from_trigger, hint = list()) {
    ok <- .dist_ensure_signal_registered(signal_id, hint, registry_path)
    spec[[length(spec) + 1L]] <<- list(
      signal_id = signal_id, condition = condition,
      from_trigger = from_trigger, status = if (ok) "active" else "pending")
  }

  # (1) 항상(보편 바닥): expiry 있으면 wall_clock_date 원소.
  exp0 <- d$expiry %||% NA
  if (!is.na(exp0) && nzchar(as.character(exp0))) {
    add("wall_clock_date", sprintf("x >= as.Date('%s')", exp0), "expiry",
        hint = list(kind = "time_now"))
  }

  # (2) live_trigger 각 원소 type별 매핑.
  lt <- d$live_trigger
  if (is.list(lt) && !is.null(lt) && length(lt)) {
    # 단일객체형({type,...})과 배열형 모두 수용 — 배열로 정규화.
    elems <- if (!is.null(lt$type)) list(lt) else lt
    for (el in elems) {
      typ <- tolower(el$type %||% "")
      if (identical(typ, "regime")) {
        # regime 정찰 결과(정찰-only, 실측 방향 확정): daily Category ∈ {CRISIS,CAUTION}.
        add("regime_category", "x %in% c('CRISIS','CAUTION')", "regime",
            hint = list(kind = "parquet_last",
                        source_path = ".cache/unified_regime_signal_daily.parquet",
                        value_col = "Category", sort_col = "Date",
                        note = "일별 통합 국면 Category. CRISIS/CAUTION = 위험 국면 진입."))
      } else if (identical(typ, "spread")) {
        add("value_quality_spread", "x >= 0.90", "spread",
            hint = list(kind = "parquet_percentile",
                        note = "value/quality spread 백분위. 상위 10%(x>=0.90) = 극단 spread reversion 재부상."))
      } else if (identical(typ, "data")) {
        slug <- .dist_slug_from_source(el$monitored_source %||% "")
        add(slug, "x == TRUE", "data",
            hint = list(kind = "file_exists",
                        note = sprintf("신규 데이터원 가용 플래그(monitored_source: %s).",
                                       substr(el$monitored_source %||% "", 1, 80))))
      }
      # type=time → expiry 바닥과 중복 → skip.
    }
  }
  spec
}


# ══ revival_spec 역방향 동기화 (2026-08-09 신설) ══════════════════════════════
# ★왜: 위 .dist_author_revival_spec 은 **카드 작성 시점의** 신호 상태로 status 를 박는다.
#   신호가 나중에 active 로 승격돼도 이미 쓰인 카드 원소를 되돌아가 승격시키는 경로가 없어,
#   조건이 참인데도 monitor 가 skip 하는 상태가 무기한 지속된다.
#   실측 적발(2026-08-09): dart_insider_present 는 명부에서 active 이고 마커
#   (.cache/dart/insider_backfill/202606.csv, 390KB, 2026-07-14)가 실재해 조건이 이미 참인데,
#   이를 참조하는 distilled 카드 3건(DIST-AR-001/AR-003/QPM-005)이 pending 인 채로
#   26일간 재부상하지 않았다. monitor 는 결백하다 — pending 을 세어 n_pending 으로 노출한다
#   (조용한 소실 아님). 빠진 것은 명부→카드 방향의 전파다.
# 양방향으로 맞춘다: 명부 active → 카드 active(승격), 명부 pending/부재 → 카드 pending(강등).
#   한 방향만 맞추면 지금 고치는 결함과 같은 계통을 반대쪽에 남긴다(죽은 신호 위의 active 원소).
sync_revival_spec_status <- function(root = .dist_root(), dry_run = FALSE,
                                     registry_path = .dist_revival_signals_path(root)) {
  if (!file.exists(registry_path)) stop("[distilled] 신호명부 부재: ", registry_path)
  reg <- fromJSON(registry_path, simplifyVector = FALSE)
  active_ids <- character(0)
  for (s in (reg$signals %||% list())) {
    if (identical(s$status %||% "active", "active"))
      active_ids <- c(active_ids, s$signal_id %||% "")
  }

  dir <- file.path(root, "qepm", "memory", "axioms", "distilled")
  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)
  promoted <- demoted <- list()
  n_files_changed <- 0L

  for (f in files) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(d)) next
    spec <- d$revival_spec %||% list()
    if (!length(spec)) next
    changed <- FALSE
    for (i in seq_along(spec)) {
      sid <- spec[[i]]$signal_id %||% ""
      cur <- spec[[i]]$status %||% "active"
      want <- if (nzchar(sid) && sid %in% active_ids) "active" else "pending"
      if (identical(cur, want)) next
      rec <- list(dist_id = d$dist_id %||% basename(f), signal_id = sid,
                  from = cur, to = want)
      if (identical(want, "active")) promoted[[length(promoted) + 1L]] <- rec
      else                            demoted[[length(demoted) + 1L]] <- rec
      spec[[i]]$status <- want
      changed <- TRUE
    }
    if (changed && !dry_run) {
      d$revival_spec <- spec
      d$revival_spec_synced_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
      write_json(d, f, pretty = TRUE, auto_unbox = TRUE, null = "null")
    }
    if (changed) n_files_changed <- n_files_changed + 1L
  }

  message(sprintf(
    "[distilled] revival_spec 동기화%s — 승격 %d · 강등 %d · 카드 %d건 변경 (명부 active %d종)",
    if (dry_run) "(dry-run)" else "", length(promoted), length(demoted),
    n_files_changed, length(active_ids)))
  invisible(list(promoted = promoted, demoted = demoted,
                 n_files_changed = n_files_changed,
                 active_signals = active_ids, dry_run = dry_run))
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

  # ── revival_spec 자동생성 (구현 B) ──
  # 사람용 live_trigger는 위에서 그대로 보존 · 기계용 revival_spec을 파생 추가(계약 §3).
  # 미등록 참조 signal_id는 명부에 pending 스텁 자동 append(자기증식) + spec 원소 pending.
  d$revival_spec <- .dist_author_revival_spec(d)

  # negative polarity인데 필수 필드 결측 시 경고(하드 stop 아님 — 초안 반복 허용)
  if (identical(d$polarity, "negative")) {
    miss <- c(if (is.null(d$frontier)) "frontier", if (is.null(d$live_trigger)) "live_trigger",
              if (is.null(d$expiry)) "expiry")
    if (length(miss))
      warning(sprintf("[distilled] %s negative 초안 INV-7 필수 필드 결측: %s — 승인 전 보강 권고",
                      dist_id, paste(miss, collapse = ", ")))
    # revival operability(정보성): live_trigger는 있으나 기계 revival_spec이 비면 자동감시 미배선.
    if (!is.null(d$live_trigger) && length(d$revival_spec %||% list()) == 0L)
      warning(sprintf("[distilled] %s negative: live_trigger는 있으나 revival_spec 자동생성 0건 — 자동 재부상 미배선(expiry 부활만). type 매핑 확인 권고", dist_id))
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

# ── 재등재 supersede (2026-08-02) — 부분집합 구 카드 자동 회수 ──
# ★구현은 여기 있지 않다. 판정 본체 = cluster_extractor.py::supersede_subsumed —
#   카드 **생성/재등재 지점**(build_distilled)에서 매 harvest/cluster 사이클마다 자동 실행된다.
#   여기 R 함수는 같은 술어를 R로 재구현하지 않고 그 구현을 호출한다: 술어를 두 벌로 두면
#   한쪽만 고쳐졌을 때 어느 검사에도 안 보인다(리더 재구현 계통 사고).
#   수동 회수는 종전대로 expire_distilled(reason="superseded_by=...")도 가능하다 —
#   엔진 자동분과 수동분은 사유 문자열 접두(`superseded_by=<id> — 같은 클러스터...`)가 같아
#   이력 검색이 일관되고, 꼬리 문구로 출처(엔진/cleaner)가 구분된다.
#
# 판정 기준(08-02 수동 회수와 동일 엄격): 진부분집합 ∧ family/polarity/type/research_mode
#   전부 동일 ∧ 지식 손실 0(구 카드 L-code 전량이 신 카드에 포함) ∧ 구 카드가 저술 지식
#   (statement_refined/retry_condition/frontier/live_trigger/…)을 들고 있지 않을 것.
#   status=distilled/promoted/quarantined_evidence는 대상 제외(활성 카드 자동 회수 금지).
.dist_py <- function() {
  cands <- c(Sys.getenv("QVEST_PY", ""),
             file.path(.dist_root(), ".venv_qvest_ml", "Scripts", "python.exe"),
             "C:/Users/99922/AppData/Local/Programs/Python/Python312/python.exe")
  for (p in cands) if (nzchar(p) && file.exists(p)) return(p)
  stop("python interpreter not found (bare python 금지 — QVEST_PY 또는 venv)")
}

supersede_subsumed_distilled <- function(root = .dist_root(), dry_run = FALSE, verbose = TRUE) {
  py <- .dist_py()
  script <- file.path(root, "02_Infrastructure", "axiom", "cluster_extractor.py")
  if (!file.exists(script)) stop("cluster_extractor.py 없음: ", script)
  # r-portability 금칙 ⑤: 인자는 벡터로 — 문자열에 쉘 리다이렉션/&& 주입 금지(셸 미경유).
  a <- c(script, "--project-dir", root, "--supersede-only")
  if (isTRUE(dry_run)) a <- c(a, "--dry-run")
  out <- system2(py, a, stdout = TRUE, stderr = TRUE)
  st <- attr(out, "status")
  if (!is.null(st) && st != 0)
    stop("supersede 실패(exit ", st, "): ", paste(tail(out, 3), collapse = " | "))
  if (verbose) cat(paste(out, collapse = "\n"), "\n", sep = "")
  # 카드 파일이 바뀌었으므로 R 소비면(인덱스·truths)도 현행화 — dry-run은 무변경.
  if (!isTRUE(dry_run) && any(grepl("[supersede]", out, fixed = TRUE))) {
    rebuild_distilled_index(root, verbose = FALSE)
    update_strategic_truths_distilled_block(root)
  }
  invisible(out)
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
  } else if (length(args) >= 1 && args[1] == "supersede") {
    supersede_subsumed_distilled(dry_run = length(args) >= 2 && args[2] == "--dry-run")
  } else {
    cat("usage:\n  Rscript distilled.R rebuild\n  Rscript distilled.R lookup <keyword...>\n",
        "  Rscript distilled.R truths\n  Rscript distilled.R list_proposed\n",
        "  Rscript distilled.R approve <dist_id...>\n",
        "  Rscript distilled.R supersede [--dry-run]\n", sep = "")
  }
}
