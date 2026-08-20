# knowledge_index_freshness.R — knowledge_index 신선도 검사 (내용 기반)
#
# 배경 (2026-08-20 폐쇄루프 감사 ④):
#   `06_Registry/knowledge_index.json` 은 `02_Infrastructure/ops/build_knowledge_index.R` 이
#   만들고, 그 빌더의 자동 트리거는 **bootstrap.sh:1027-1031 + weekly_cleaner_sweep.R:[3.6]**
#   두 곳뿐이다. 반면 원천인 `.cache/lcode_corpus.json` 은 harvester 가 부팅·주간·
#   alpha_search 종료 등 **더 많은 경로**에서 갱신하고, `hypothesis_index.json` 은
#   `lookup_hypothesis()` 안에서 corpus mtime 을 보고 **인라인 자가치유**까지 한다.
#   ⇒ 트리거 비대칭. 부팅 없는 세션에서 L-code 를 적립하면 corpus 만 늘고 knowledge_index 는
#     정체되는데, **그 상태를 재는 검사가 저장소 전체에 0줄**이었다.
#   실사고: 2026-08-15 적립분이 corpus 493 / knowledge_index 492 로 26시간+ 벌어졌고
#   아무 경보도 없었다(08-17 수동 재빌드로 해소).
#
# ★설계 원칙 — 주 판정은 **내용 카운트/ID 집합**, mtime·타임스탬프는 보조.
#   mtime 대리 지표는 append 나 무의미한 재기록만으로도 초록이 되므로 계기가 꺼진다
#   (layer_bottleneck_map 사고와 동일 계통). 여기서는:
#     P1 (주 판정) corpus 항목 수 vs index counts$lcode_corpus
#     P2 (주 판정) corpus L-code ID 집합 vs index lcode_corpus[].id 집합 (수가 같아도 멤버가
#                  다르면 STALE — 카운트 단독의 사각을 덮는다)
#     A1 (보조/advisory) index generated_at 이 corpus last_updated 보다 오래됨
#
# 폴백 (회귀 없음 최우선): 입력 파일 부재·파싱 실패·필드 결측은 **STALE 로 올리지 않고**
#   status="SKIP" + 명시 사유로 반환한다. 절대 stop() 으로 죽지 않고, 무조건 통과도 아니다.
#
# 사용:
#   source("02_Infrastructure/ops/knowledge_index_freshness.R")
#   r <- check_knowledge_index_freshness()          # list(status=OK|STALE|SKIP, ...)
#   cat(format_knowledge_index_freshness(r), "\n")
#   repair_knowledge_index()                        # 명시 opt-in 재빌드 (기본 비활성)
# CLI:
#   Rscript 02_Infrastructure/ops/knowledge_index_freshness.R           # 검사만 (exit 0/1/2)
#   Rscript 02_Infrastructure/ops/knowledge_index_freshness.R --repair  # STALE 이면 재빌드
#
# ⚠ 이 파일은 source 시 아무 것도 실행하지 않는다(빌더처럼 자동 재생성하지 않음).

suppressWarnings(suppressMessages(library(jsonlite)))

if (!exists("%||%")) {
  `%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
}

.kif_root <- function() {
  for (p in c(Sys.getenv("QM_ROOT", ""), Sys.getenv("CLAUDE_PROJECT_DIR", ""),
              "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd())) {
    if (nzchar(p) && dir.exists(p)) return(p)
  }
  getwd()
}

# ISO8601 파서 — "+0900" / "+00:00" / "Z" / 오프셋 없음 전부 수용.
# Windows 의 strptime %z 는 콜론 있는 오프셋을 못 읽으므로 정규화 후 파싱한다.
# 실패 시 NA 반환 (호출부가 advisory 축을 조용히 비활성).
.kif_parse_ts <- function(s) {
  s <- as.character(s %||% "")[1]
  if (!nzchar(s) || is.na(s)) return(as.POSIXct(NA))
  s <- sub("[Zz]$", "+0000", s)
  s <- sub("([+-][0-9]{2}):([0-9]{2})$", "\\1\\2", s)
  out <- suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"))
  if (is.na(out)) out <- suppressWarnings(as.POSIXct(s, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))
  out
}

.kif_read_json <- function(path) {
  if (!file.exists(path)) return(list(ok = FALSE, why = "missing", data = NULL))
  d <- tryCatch(fromJSON(path, simplifyVector = FALSE), error = function(e) e)
  if (inherits(d, "error")) return(list(ok = FALSE, why = paste0("parse_error: ", conditionMessage(d)), data = NULL))
  list(ok = TRUE, why = "", data = d)
}

.kif_skip <- function(reason, detail = "") {
  list(status = "SKIP", reason = reason, detail = detail,
       n_corpus = NA_integer_, n_index = NA_integer_,
       n_missing_in_index = NA_integer_, n_extra_in_index = NA_integer_,
       missing_sample = character(0), extra_sample = character(0),
       corpus_self_inconsistent = NA, ts_lag_seconds = NA_real_, ts_advisory = NA,
       corpus_path = NA_character_, index_path = NA_character_)
}

#' knowledge_index 신선도 검사 (내용 기반)
#'
#' @param root 프로젝트 루트 (기본 QM_ROOT → CLAUDE_PROJECT_DIR → 하드코딩 → getwd)
#' @param corpus_path .cache/lcode_corpus.json 경로 override
#' @param index_path  06_Registry/knowledge_index.json 경로 override
#' @param id_sample_n 불일치 ID 예시 최대 개수
#' @return list(status = "OK"|"STALE"|"SKIP", reason, ...)
check_knowledge_index_freshness <- function(root = .kif_root(),
                                            corpus_path = NULL,
                                            index_path = NULL,
                                            id_sample_n = 5L) {
  corpus_path <- corpus_path %||% file.path(root, ".cache", "lcode_corpus.json")
  index_path  <- index_path  %||% file.path(root, "06_Registry", "knowledge_index.json")

  cr <- .kif_read_json(corpus_path)
  if (!cr$ok) {
    r <- .kif_skip(paste0("corpus_", cr$why),
                   sprintf("lcode_corpus 소비 불가 (%s) — 검사 보류, 기존 동작 유지", corpus_path))
    r$corpus_path <- corpus_path; r$index_path <- index_path
    return(r)
  }
  ir <- .kif_read_json(index_path)
  if (!ir$ok) {
    r <- .kif_skip(paste0("index_", ir$why),
                   sprintf("knowledge_index 소비 불가 (%s) — 검사 보류, 기존 동작 유지", index_path))
    r$corpus_path <- corpus_path; r$index_path <- index_path
    return(r)
  }

  corpus <- cr$data; idx <- ir$data

  # --- 축 존재 확인 (필드명 추측 금지 — 실제 스키마: corpus$lcodes[]$l_code / idx$lcode_corpus[]$id) ---
  lcodes <- corpus$lcodes
  if (is.null(lcodes) || !is.list(lcodes)) {
    r <- .kif_skip("corpus_no_lcodes_field",
                   sprintf("corpus 에 'lcodes' 리스트 없음 (키: %s)", paste(names(corpus), collapse = ",")))
    r$corpus_path <- corpus_path; r$index_path <- index_path
    return(r)
  }
  idx_rows <- idx$lcode_corpus
  if (is.null(idx_rows) || !is.list(idx_rows)) {
    r <- .kif_skip("index_no_lcode_corpus_field",
                   sprintf("index 에 'lcode_corpus' 리스트 없음 (키: %s)", paste(names(idx), collapse = ",")))
    r$corpus_path <- corpus_path; r$index_path <- index_path
    return(r)
  }

  n_corpus_rows <- length(lcodes)
  n_corpus_decl <- suppressWarnings(as.integer(corpus$n_lcodes %||% NA))
  corpus_self_inconsistent <- !is.na(n_corpus_decl) && !identical(n_corpus_decl, n_corpus_rows)
  # 원장이 스스로 선언한 수와 실제 행수가 다르면 **실제 행수**를 권위로 삼는다
  # (선언 필드는 갱신 누락 가능 — 내용이 정본).
  n_corpus <- n_corpus_rows

  n_index_rows  <- length(idx_rows)
  n_index_decl  <- suppressWarnings(as.integer((idx$counts %||% list())$lcode_corpus %||% NA))
  index_self_inconsistent <- !is.na(n_index_decl) && !identical(n_index_decl, n_index_rows)
  n_index <- n_index_rows

  ids_corpus <- unique(vapply(lcodes, function(e) as.character(e$l_code %||% "")[1], character(1)))
  ids_index  <- unique(vapply(idx_rows, function(e) as.character(e$id %||% "")[1], character(1)))
  ids_corpus <- ids_corpus[nzchar(ids_corpus)]
  ids_index  <- ids_index[nzchar(ids_index)]

  missing_in_index <- setdiff(ids_corpus, ids_index)   # 적립됐는데 인덱스에 없음 = 낙후
  extra_in_index   <- setdiff(ids_index, ids_corpus)   # 인덱스에만 있음 = 원천 축소/재작성 미반영

  # --- advisory: 타임스탬프 역전 ---
  ts_idx <- .kif_parse_ts(idx$generated_at)
  ts_cor <- .kif_parse_ts(corpus$last_updated)
  ts_lag <- if (!is.na(ts_idx) && !is.na(ts_cor)) as.numeric(difftime(ts_cor, ts_idx, units = "secs")) else NA_real_
  ts_advisory <- !is.na(ts_lag) && ts_lag > 0    # corpus 가 index 보다 최신 = 낙후 의심(보조)

  reasons <- character(0)
  if (!identical(n_corpus, n_index)) reasons <- c(reasons, sprintf("count_mismatch(corpus=%d, index=%d)", n_corpus, n_index))
  if (length(missing_in_index))      reasons <- c(reasons, sprintf("missing_in_index=%d", length(missing_in_index)))
  if (length(extra_in_index))        reasons <- c(reasons, sprintf("extra_in_index=%d", length(extra_in_index)))
  if (index_self_inconsistent)       reasons <- c(reasons, sprintf("index_counts_field_stale(counts=%s, rows=%d)", n_index_decl, n_index_rows))

  status <- if (length(reasons)) "STALE" else "OK"
  # advisory 단독으로는 STALE 로 올리지 않는다 — 주 판정은 내용이다.
  if (identical(status, "OK") && isTRUE(ts_advisory)) {
    reasons <- c(reasons, sprintf("advisory_ts_lag=%.0fs (내용은 일치 — 재빌드 불요)", ts_lag))
  }

  list(status = status,
       reason = if (length(reasons)) paste(reasons, collapse = "; ") else "content_match",
       detail = "",
       n_corpus = n_corpus, n_index = n_index,
       n_corpus_declared = n_corpus_decl, n_index_declared = n_index_decl,
       n_missing_in_index = length(missing_in_index),
       n_extra_in_index = length(extra_in_index),
       missing_sample = utils::head(missing_in_index, id_sample_n),
       extra_sample = utils::head(extra_in_index, id_sample_n),
       corpus_self_inconsistent = corpus_self_inconsistent,
       index_self_inconsistent = index_self_inconsistent,
       ts_lag_seconds = ts_lag, ts_advisory = ts_advisory,
       corpus_path = corpus_path, index_path = index_path)
}

format_knowledge_index_freshness <- function(r) {
  if (identical(r$status, "SKIP")) {
    return(sprintf("[knowledge-index-freshness] SKIP — %s (%s)", r$reason, r$detail))
  }
  base <- sprintf("[knowledge-index-freshness] %s — corpus %d / index %d · missing %d · extra %d",
                  r$status, r$n_corpus, r$n_index, r$n_missing_in_index, r$n_extra_in_index)
  if (identical(r$status, "STALE")) {
    ex <- c(if (length(r$missing_sample)) sprintf("index 결측 예: %s", paste(r$missing_sample, collapse = ",")),
            if (length(r$extra_sample))   sprintf("corpus 결측 예: %s", paste(r$extra_sample, collapse = ",")))
    base <- paste0(base, "\n  사유: ", r$reason,
                   if (length(ex)) paste0("\n  ", paste(ex, collapse = "\n  ")) else "",
                   "\n  수리: Rscript 02_Infrastructure/ops/build_knowledge_index.R")
  } else if (isTRUE(r$ts_advisory)) {
    base <- paste0(base, " (advisory: ", r$reason, ")")
  }
  base
}

#' 명시 opt-in 재빌드 — STALE 일 때만 build_knowledge_index() 를 호출한다.
#'
#' ★기본 비활성인 이유(측정 근거는 파일 하단 주석): 검사가 정본 레지스트리를 재작성하면
#'   자신이 신고해야 할 증거를 지운다. 자동 자가치유는 *소비면*에 붙일 일이지
#'   *계기*에 붙일 일이 아니다.
repair_knowledge_index <- function(root = .kif_root(), verbose = TRUE, force = FALSE) {
  r <- check_knowledge_index_freshness(root = root)
  if (!force && !identical(r$status, "STALE")) {
    if (verbose) cat(format_knowledge_index_freshness(r), "\n")
    return(invisible(list(rebuilt = FALSE, before = r, after = r)))
  }
  builder <- file.path(root, "02_Infrastructure", "ops", "build_knowledge_index.R")
  if (!file.exists(builder)) {
    if (verbose) cat(sprintf("[knowledge-index-freshness] 재빌드 불가 — 빌더 부재: %s\n", builder))
    return(invisible(list(rebuilt = FALSE, before = r, after = r)))
  }
  ok <- tryCatch({
    old <- getOption("ki_no_autorun", FALSE)
    options(ki_no_autorun = TRUE)
    on.exit(options(ki_no_autorun = old), add = TRUE)
    source(builder, local = TRUE)
    get("build_knowledge_index")(root = root, verbose = verbose)
    TRUE
  }, error = function(e) {
    if (verbose) cat("[knowledge-index-freshness][경고] 재빌드 실패 — 기존 인덱스 유지: ",
                     conditionMessage(e), "\n", sep = "")
    FALSE
  })
  after <- check_knowledge_index_freshness(root = root)
  if (verbose) cat(format_knowledge_index_freshness(after), "\n")
  invisible(list(rebuilt = ok, before = r, after = after))
}

# ── CLI ───────────────────────────────────────────────────────────────────────
# exit code: 0 = OK, 1 = STALE, 2 = SKIP(입력 부재/파싱 실패 — 판정 보류)
if (identical(environment(), globalenv()) && !interactive()) {
  .kif_args <- commandArgs(trailingOnly = TRUE)
  if (length(.kif_args) && any(.kif_args %in% c("--repair", "repair"))) {
    .kif_res <- repair_knowledge_index()
    .kif_final <- .kif_res$after
  } else {
    .kif_final <- check_knowledge_index_freshness()
    cat(format_knowledge_index_freshness(.kif_final), "\n")
  }
  quit(status = switch(.kif_final$status, OK = 0L, STALE = 1L, SKIP = 2L, 2L))
}

# ── 자가치유 검토 기록 (2026-08-20 실측) ──────────────────────────────────────
# 질문: hypothesis_index 처럼 인라인 자가치유를 붙일 것인가?
#   비용은 장애물이 아니다 — 픽스처(L-code 494건 · corpus 1.2MB)에서 build_knowledge_index()
#   전체 실행 **0.222 s** 실측(hypothesis_index 전체 빌드 ~2s 대비 1/9).
#   장애물은 **부작용 위치**다:
#     (a) build_knowledge_index() 는 정본 06_Registry/knowledge_index.{json,md} 를 재작성한다.
#         weekly_cleaner_sweep.R:[3.6] 은 바로 이 이유로 DRY 에서 스킵한다(WCS-06 2026-07-26,
#         "dry_run:true 라벨인데 부작용이 나가면 라벨이 안전성을 위장").
#     (b) 검사기가 재작성하면 자신이 신고할 증거를 지운다 — 낙후가 corpus 손상에서 왔을 때
#         조용히 덮어써 원인을 감춘다. 계기는 대상을 바꾸지 않아야 한다.
#     (c) hypothesis_index 의 자가치유는 **consumer 진입점**(lookup_hypothesis)에 있지
#         health check 에 있지 않다. 같은 자리를 고르면 knowledge_index 의 소비면
#         (weekly_distill.R / monthly_distill.R / distill_stats.R / loop_integrator.R /
#          handbook_facts_audit.sh) 이지 이 파일이 아니다.
#   ⇒ 결론: 기본은 **경보만**. 재빌드는 repair_knowledge_index() / `--repair` 로 명시 opt-in.
#     소비면 자가치유는 별건으로 분리(그 파일들은 본 작업의 소유가 아님).
