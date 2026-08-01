# ============================================================================
# ast_sidecar.R — AST 계층 v1.1 Step 4 구조특징 사이드카 단일 writer
# ----------------------------------------------------------------------------
# 신설: 2026-08-02 (Q-Lead 야간 라운드 — 실전 캡처 0 결함 수리)
#
# ## 왜 신설했나 (실측 근거 — SOT §5 M4 전제 반증)
# AST SOT v1.1 §5는 배선점을 essence_score() 단독으로 정하며 근거를
#   "essence_score는 전 graduation 판정 경유라 capture 구조 보장"
# 이라고 적었다. 2026-08-02 실측은 이 전제를 반증한다:
#
#   1) run_alpha_search.R:330 권위측정 사다리
#        if (grade %in% c("A","A_NOVEL","A_DEF","B","B_DEF") || screen_remeasure) {
#          auth <- .authoritative_remeasure(...)   # ← essence_score()는 여기서만 호출
#        } else { ... proxy 유지, 실측 재측정 생략 }
#      → essence_score 는 **proxy hurdle 사다리를 통과한 소수만** 경유한다.
#      실측: 2026-07-27 alpha-search 3라운드 = grade F/C, screen_pass=FALSE
#            → 사다리 생략 → 사이드카 기록 0.
#      이는 §5가 명문으로 요구한 "governor 거절분 포함 전량 로깅(생존편향 방지)"의
#      **정반대** 구조다 — 생존자만 남는다.
#   2) canonical_screen_bt() 는 essence_score 를 호출하지 않는다(주석 언급뿐).
#      alpha 스크리닝 판정의 1급 지표 PORT_t 가 이 경로에서 나오는데 사이드카 미도달.
#   3) main 저장소 essence_score() 호출자 35곳 전수가 ast_features/strategy_id 미전달.
#   4) worktree 6개 중 5개의 essence_score.R 이 사이드카 없는 구판.
#
#   결과: 06_Registry/ast_structure_log.jsonl 399행 중 실전 레코드 0
#         (ast_features non-null 0 / strategy_id non-null 0,
#          21행씩 동일-분 클러스터 = 테스트 배터리 반복 산물).
#         Step 5(N>=30 -> complexity_prior 추정 -> alpha 프롬프트 주입) 는
#         이 상태로 진입하면 **합성 데이터로 사전분포를 추정**하게 된다(AX-002 급 위험).
#
# ## 설계
# - 단일 writer. 배선점을 lane 으로 구분해 **복수 판정 경로 전부** 캡처한다.
#     lane="essence"          : essence_score() (graduation 판정)
#     lane="canonical_screen" : canonical_screen_bt() (스크리닝 판정 — 생존편향 없음)
# - run_context 로 실전/테스트를 분리 기록한다. 기본 "live";
#   테스트 배터리는 QVEST_RUN_CONTEXT=test 를 설정한다.
#   ★ 소비자(Step 5 분석)는 run_context=="live" 만 세야 한다.
# - **실패 시 침묵 금지**: 기록 실패는 stderr WARN + 실패 원장에 남긴다.
#   구판은 try(silent=TRUE) + dir.exists() 조건이라 실패가 무흔적이었다
#   ("발화 0"을 계측 사망으로 못 읽는 구조 — 본 저장소 반복 실패 부류).
# - append-only. 본 계산 비중단(fail-soft) 원칙은 유지하되 **관측 가능**하게.
#
# 규범: r-portability.md(루트 resolver marker 검증·선행 / 하드코딩 금지),
#       answer-principles(회피표현 금지), measurement-graduation §5.
# ============================================================================

# ── 프로젝트 루트 resolver (marker 검증 — 존재검사로 정체성검사 대체 금지) ──
#  2026-08-01 resolve_project marker 게이트 지식 계승: dir.exists() 만으로 루트를
#  신뢰하면 역슬래시 경로·부분 트리도 통과한다. CLAUDE.md + 06_Registry 동시 존재로 검증.
.ast_sc_is_root <- function(p) {
  if (is.null(p) || !nzchar(p)) return(FALSE)
  p <- gsub("\\\\", "/", p)                      # 정규화를 검사보다 먼저
  file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))
}

.ast_sc_root <- function() {
  # 우선순위: CLAUDE_PROJECT_DIR → QM_ROOT → getwd() 상향탐색.
  # 각 후보는 marker 검증을 통과해야 채택된다(기각 시 다음 후보로 낙하).
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""))
  for (c0 in cands) if (.ast_sc_is_root(c0)) return(gsub("\\\\", "/", c0))
  p <- gsub("\\\\", "/", getwd())
  for (i in 1:6) {
    if (.ast_sc_is_root(p)) return(p)
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  NA_character_
}

.ast_sc_fail <- function(msg) {
  # 실패를 관측 가능하게 — stderr + 실패 원장(있으면). 본 계산은 중단하지 않는다.
  try({
    cat(sprintf("[ast_sidecar] WARN 기록 실패: %s\n", msg), file = stderr())
    r <- .ast_sc_root()
    if (!is.na(r)) {
      cat(sprintf("%s\t%s\n", format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), msg),
          file = file.path(r, "06_Registry", ".ast_sidecar_failures.log"), append = TRUE)
    }
  }, silent = TRUE)
  invisible(FALSE)
}

.ast_sc_num <- function(x) {
  if (is.null(x) || length(x) == 0L) return(NA_real_)
  v <- suppressWarnings(as.numeric(x[1]))
  if (!is.finite(v)) NA_real_ else round(v, 6)
}

#' AST 구조특징 사이드카 기록 (단일 writer)
#'
#' @param lane        판정 경로. "essence" | "canonical_screen" | 그 외 신규 배선점
#' @param strategy_id 전략 식별자 (NULL 이면 NA 기록 — 커버리지 결손 표식으로 남긴다)
#' @param ast_features ast_compile manifest 의 구조특징 list. 비-AST 산출은 NULL
#'                     (NULL = escape/비-AST 커버리지 표식. 생존편향 방지 위해 그래도 기록)
#' @param metrics     성과·판정 지표 named list (port_t/oos_retention/dsr/calmar/... )
#' @param extra       lane 별 추가 필드 named list
#' @return TRUE(기록 성공) / FALSE(실패 — 이미 관측 기록됨). 호출자 흐름 비중단.
ast_sidecar_log <- function(lane,
                            strategy_id = NULL,
                            ast_features = NULL,
                            metrics = list(),
                            extra = list()) {
  ok <- FALSE
  try({
    if (!requireNamespace("jsonlite", quietly = TRUE))
      return(.ast_sc_fail("jsonlite namespace 부재"))
    root <- .ast_sc_root()
    if (is.na(root))
      return(.ast_sc_fail(sprintf("프로젝트 루트 resolve 실패 (wd=%s, CPD=%s, QM_ROOT=%s)",
                                  getwd(), Sys.getenv("CLAUDE_PROJECT_DIR"), Sys.getenv("QM_ROOT"))))
    reg <- file.path(root, "06_Registry")
    if (!dir.exists(reg)) return(.ast_sc_fail(sprintf("06_Registry 부재: %s", reg)))

    sid <- if (is.null(strategy_id) || !length(strategy_id) ||
               is.na(strategy_id[1]) || !nzchar(as.character(strategy_id[1])))
             NA_character_ else as.character(strategy_id[1])

    rec <- c(
      list(
        ts           = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
        lane         = as.character(lane)[1],
        # ★ 실전/테스트 분리 — Step 5 분석은 run_context=="live" 만 센다.
        run_context  = Sys.getenv("QVEST_RUN_CONTEXT", unset = "live"),
        schema       = "ast_structure_log_v2",
        strategy_id  = sid,
        ast_features = ast_features            # NULL = 비-AST/escape 커버리지 표식
      ),
      lapply(metrics, function(v) if (is.numeric(v)) .ast_sc_num(v) else v),
      extra
    )
    cat(jsonlite::toJSON(rec, auto_unbox = TRUE, null = "null", na = "null"), "\n",
        sep = "", file = file.path(reg, "ast_structure_log.jsonl"), append = TRUE)
    ok <- TRUE
  }, silent = TRUE)
  if (!ok && !exists(".ast_sc_failed_already")) invisible(.ast_sc_fail("toJSON/cat 단계 예외"))
  invisible(ok)
}

#' Step 5 진입 판정용 정직 카운터
#'
#' SOT §5 는 "분석은 N>=30 부터"를 규율한다. 그 N 은 **실전 레코드 수**여야 한다.
#' 구판 로그(schema 필드 없음)는 전부 테스트 배터리 산물이므로 세지 않는다.
#' smoke/test lane 과 run_context!="live" 도 제외한다.
#'
#' @return list(total, live, live_with_ast, legacy_unlabeled, by_lane)
#'   - live          : 실전 판정 레코드 수 (구조특징 유무 무관 — 생존편향 방지 분모)
#'   - live_with_ast : ast_features 가 실제로 채워진 실전 레코드 수
#'                     (Step 5 구조특징 회귀의 실질 표본. escape/비-AST 는 커버리지 절단)
ast_sidecar_status <- function(path = NULL) {
  if (is.null(path)) {
    r <- .ast_sc_root()
    if (is.na(r)) return(list(total = NA_integer_, live = NA_integer_,
                              live_with_ast = NA_integer_, legacy_unlabeled = NA_integer_,
                              by_lane = character(0), note = "root resolve 실패"))
    path <- file.path(r, "06_Registry", "ast_structure_log.jsonl")
  }
  if (!file.exists(path)) return(list(total = 0L, live = 0L, live_with_ast = 0L,
                                      legacy_unlabeled = 0L, by_lane = character(0)))
  if (!requireNamespace("jsonlite", quietly = TRUE))
    return(list(total = NA_integer_, note = "jsonlite 부재"))
  ln <- readLines(path, warn = FALSE); ln <- ln[nzchar(trimws(ln))]
  recs <- lapply(ln, function(l) tryCatch(jsonlite::fromJSON(l), error = function(e) NULL))
  recs <- Filter(Negate(is.null), recs)
  has_schema <- vapply(recs, function(r) !is.null(r$schema), logical(1))
  ctx  <- vapply(recs, function(r) if (is.null(r$run_context)) NA_character_ else
                                    as.character(r$run_context)[1], character(1))
  lane <- vapply(recs, function(r) if (is.null(r$lane)) NA_character_ else
                                    as.character(r$lane)[1], character(1))
  is_live <- has_schema & !is.na(ctx) & ctx == "live" &
             !is.na(lane) & !grepl("smoke|test", lane)
  has_ast <- vapply(recs, function(r) !is.null(r$ast_features) &&
                                      length(r$ast_features) > 0L, logical(1))
  list(total = length(recs),
       live = sum(is_live),
       live_with_ast = sum(is_live & has_ast),
       legacy_unlabeled = sum(!has_schema),
       by_lane = if (any(is_live)) table(lane[is_live]) else table(character(0)))
}

if (sys.nframe() == 0)
  cat("[ast_sidecar.R] Loaded — ast_sidecar_log() / ast_sidecar_status()\n")
