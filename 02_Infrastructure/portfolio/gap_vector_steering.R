#==============================================================================
# Gap Vector Steering Layer — sleeve_needs 실증-열린 방향 enum 재정의
# gap_vector_steering.R
#
# 배경 (아키텍처 감사 SC-01/SC-06, 도훈 confirm 2026-07-03):
#   .cache/portfolio_gap_vector.json의 빌더는
#   02_Infrastructure/portfolio/portfolio_governor.R::pg0_gap_review().
#   본 파일은 그 산출물의 *후처리 레이어* (A7b 2026-07-04: pg0_gap_review 말미가
#   steer_gap_vector()를 자동 호출 — 빌더 재실행이 구 enum으로 덮어써도 즉시 재조향):
#   ① sleeve_needs를 실증 기록 기반 enum으로 재정의 (core_alpha standalone은
#      16/16 admission FAIL posterior와 함께 closed/최후순위 강등)
#   ② current_profile을 현 book 실값(backtested, 계약 재계산 meta)으로 갱신
#   ③ 신선도(stale) 진단 함수 제공 (bootstrap 4f가 bash로 동일 검사 수행)
#
# 사용:
#   source("02_Infrastructure/portfolio/gap_vector_steering.R")
#   steer_gap_vector()                      # 읽기 → 조향 → 재작성
#   gv_check_staleness()                    # WARN-only 진단
#
# 원칙: 수치 창작 금지 — current_profile은 기록된 실측 산출물
#   (WT-D20260702_002/output/step3_clean_recompute_meta.json, metric_type=
#   backtested(contract))만 소비. book_state.json은 읽기 전용.
#==============================================================================

# ─── Bootstrap ───────────────────────────────────────────────────────────────
.gvs_root <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) {
  file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                       Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
            "02_Infrastructure/portfolio")
})
.gvs_proj <- normalizePath(file.path(.gvs_root, "..", ".."), winslash = "/", mustWork = FALSE)

suppressPackageStartupMessages({
  library(jsonlite)
})

if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── Constants ───────────────────────────────────────────────────────────────
.GVS_VERSION       <- "1.0.0"
.GVS_GAP_PATH      <- file.path(.gvs_proj, ".cache", "portfolio_gap_vector.json")
.GVS_BOOK_STATE    <- file.path(.gvs_proj, "qepm", "mailbox", "governor", "book_state.json")
.GVS_MAX_AGE_DAYS  <- 30L
.GVS_DEFAULT_TARGET <- list(cagr = 0.16, sharpe = 2.5, mdd = 0.25)  # 헌법 제2목표 (SR 2.5, 2026-05-29 도훈 mandate)

# book_id → 실측 계약 재계산 meta (metric_type=backtested(contract)) 매핑.
# 수치 창작 금지 원칙: 여기 등재된 실측 산출물만 current_profile 갱신에 소비.
# book 교체 시 새 계약 재계산 meta 경로를 추가할 것 (미등재 book = builder 프로파일 유지 + WARN).
.GVS_BOOK_METRICS_SOURCES <- list(
  "STR_1715_on_M4_R05_noLayer4_PG2" = file.path(
    .gvs_proj, "qepm", "mailbox", "worktask", "WT-D20260702_002",
    "output", "step3_clean_recompute_meta.json")
)

# ─── Steering enum (도훈 confirm 2026-07-03) ─────────────────────────────────
# 실증 기록 기반 탐색 방향. open 방향이 1차 조향 입력, closed는 posterior 라벨과
# 함께 최후순위 강등 (조향 입력에서 제외되나 기록은 보존 — INV-7 failure-ledger 정합).
GV_STEERING_DIRECTIONS <- list(
  overlay_refinement = list(
    status   = "open",
    priority = 1L,
    label    = "오버레이 정교화 (β/regime timing) — 주 레버",
    evidence = "measurement-graduation §6: SR 2.5 레버 ① overlay = 주역·유일한 long-only β 레버 (KR long-only sleeve β≈0.99 실측)"
  ),
  residual_orthogonal_sleeve = list(
    status    = "open",
    priority  = 2L,
    label     = "잔차-직교 sleeve 스태킹",
    condition = "PORT_t(NW lag-3) ≥ 2.95 통과분만 book 실질 기여 — 직교 ≠ 수익",
    evidence  = "measurement-graduation §6: active(−BM) 잔차 공간엔 직교 구조 존재 (RAMP Gate4 PC2~10), 단 '직교 ∧ PORT_t 통과' 동시 충족분만 실질"
  ),
  non_return_datasource = list(
    status   = "open",
    priority = 3L,
    label    = "비-return 신규 정보원 (DART insider 등)",
    evidence = "memory project-paper-pool-qepm-exhaustion (2026-06-29): return-계열 논문풀 ~95% 소진, 미탐색 = 비-return (DART 인사이더 백필, registry 0건 신규 정보원)"
  ),
  dpl_feature = list(
    status   = "open_as_composition_layer",
    priority = 4L,
    label    = "DPL 구성레이어 입력 피처 (standalone 아님)",
    evidence = "measurement-graduation §5: 실패 standalone 알파 = 폐기 아닌 DPL 입력 피처. 단 DPL standalone vs PG2는 settled-negative (memory project-dpl-vs-pg2-settled, 2026-06-26) — feature 공급 용도 한정"
  ),
  core_alpha_standalone = list(
    status    = "closed",
    priority  = 99L,
    label     = "standalone core_alpha 신규 발굴 (최후순위 강등)",
    posterior = "16/16 admission FAIL, 2026-07 기준",
    evidence  = "measurement-graduation §6 '직교 ≠ 수익': standalone long-only 16/16 admission FAIL (사유 = PORT_t 실현 net active, BAB port_t -2.02 등)"
  )
)

# ─── gv_check_staleness ──────────────────────────────────────────────────────

#' Gap vector 신선도 진단 (WARN-only, 블록 아님)
#'
#' stale 판정: 파일 부재 / mtime 30일+ / n_strategies == 0 (콜드스타트 잔재).
#' bootstrap.sh 4f가 동일 검사를 bash로 수행 — 본 함수는 R 세션용 동형.
#'
#' @param gap_path Character: gap vector JSON 경로
#' @param max_age_days Integer: mtime 허용 일수
#' @return list(stale = logical, reasons = character vector)
gv_check_staleness <- function(gap_path = .GVS_GAP_PATH,
                               max_age_days = .GVS_MAX_AGE_DAYS) {
  reasons <- character(0)

  if (!file.exists(gap_path)) {
    reasons <- "file_missing"
  } else {
    age_days <- as.numeric(difftime(Sys.time(), file.mtime(gap_path), units = "days"))
    if (age_days > max_age_days) {
      reasons <- c(reasons, sprintf("mtime_age_%.0fd_gt_%dd", age_days, max_age_days))
    }
    gv <- tryCatch(fromJSON(gap_path, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(gv)) {
      reasons <- c(reasons, "json_unparseable")
    } else if (!is.null(gv$n_strategies) && as.integer(gv$n_strategies) == 0L) {
      reasons <- c(reasons, "n_strategies_0_cold_start_artifact")
    }
  }

  stale <- length(reasons) > 0
  if (stale) {
    cat(sprintf("[gv_steering] WARN: portfolio_gap_vector.json STALE (%s) — steer_gap_vector() 재생성 권장\n",
                paste(reasons, collapse = ", ")))
  }
  list(stale = stale, reasons = reasons)
}

# ─── steer_gap_vector ────────────────────────────────────────────────────────

#' Gap vector 후처리 조향 (읽기 → sleeve_needs enum 재정의 + book 실값 갱신 → 재작성)
#'
#' 빌더(pg0_gap_review) 산출을 입력으로:
#'  1. current_profile을 book_state 현 admitted book의 계약 재계산 실측
#'     (.GVS_BOOK_METRICS_SOURCES 등재분만)으로 갱신. 미등재 book이면 builder
#'     프로파일 유지 + profile_source 라벨.
#'  2. gap 재계산 (pg0와 동일 부호 규약: mdd_gap 양수 = MDD 초과).
#'  3. sleeve_needs → 실증-열린 방향 enum (GV_STEERING_DIRECTIONS)로 치환.
#'     빌더 원본은 sleeve_needs_raw_builder에 보존.
#'
#' @param gap_path Character: gap vector JSON 경로 (부재 시 skeleton에서 시작)
#' @param book_state_path Character: book_state.json 경로 (읽기 전용)
#' @param write Logical: TRUE면 gap_path에 재작성
#' @return Steered gap vector list (invisible)
steer_gap_vector <- function(gap_path = .GVS_GAP_PATH,
                             book_state_path = .GVS_BOOK_STATE,
                             write = TRUE) {

  # ── 1. 입력 로드 ────────────────────────────────────────────────────────────
  gv <- if (file.exists(gap_path)) {
    tryCatch(fromJSON(gap_path, simplifyVector = FALSE), error = function(e) list())
  } else list()

  bs <- if (file.exists(book_state_path)) {
    tryCatch(fromJSON(book_state_path, simplifyVector = FALSE), error = function(e) list())
  } else list()

  admitted_ids <- unlist(bs$admitted_ids %||% character(0))
  n_strategies <- as.integer(bs$n_admitted %||% length(admitted_ids))
  book_id      <- if (length(admitted_ids) > 0) admitted_ids[1] else NA_character_

  # ── 2. current_profile — 등재된 실측 계약 재계산만 소비 ──────────────────────
  profile_source <- "builder_unrefreshed"
  current_profile <- gv$current_profile %||% list(cagr = 0, sharpe = 0, mdd = 0)
  metrics_meta <- NULL

  src_path <- if (!is.na(book_id)) .GVS_BOOK_METRICS_SOURCES[[book_id]] else NULL
  if (!is.null(src_path) && file.exists(src_path)) {
    metrics_meta <- tryCatch(fromJSON(src_path, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(metrics_meta$metrics)) {
      m <- metrics_meta$metrics
      current_profile <- list(
        cagr   = as.numeric(m$CAGR),
        sharpe = as.numeric(m$SR_geometric_table),  # judge/3-way headline 컨벤션
        mdd    = abs(as.numeric(m$MDD))
      )
      rel_src <- sub(paste0(.gvs_proj, "/"), "",
                     gsub("\\\\", "/", src_path), fixed = TRUE)
      profile_source <- sprintf("%s (metric_type=%s)", rel_src,
                                metrics_meta$metric_type %||% "backtested(contract)")
    }
  } else if (!is.na(book_id)) {
    cat(sprintf("[gv_steering] WARN: book '%s' 실측 meta 미등재 — builder current_profile 유지 (.GVS_BOOK_METRICS_SOURCES 등재 필요)\n", book_id))
  }

  # ── 3. Gap 재계산 (pg0 부호 규약) ────────────────────────────────────────────
  target_profile <- gv$target_profile %||% .GVS_DEFAULT_TARGET
  gap <- list(
    cagr_gap   = round(as.numeric(target_profile$cagr)   - as.numeric(current_profile$cagr), 4),
    sharpe_gap = round(as.numeric(target_profile$sharpe) - as.numeric(current_profile$sharpe), 3),
    mdd_gap    = round(as.numeric(current_profile$mdd)   - as.numeric(target_profile$mdd), 4)  # 양수 = MDD 초과
  )

  # ── 4. sleeve_needs 조향 재정의 ──────────────────────────────────────────────
  prios <- vapply(GV_STEERING_DIRECTIONS, function(d) d$priority, integer(1))
  open_mask <- vapply(GV_STEERING_DIRECTIONS, function(d) d$status != "closed", logical(1))
  open_dirs <- names(GV_STEERING_DIRECTIONS)[open_mask][order(prios[open_mask])]

  sleeve_needs_raw <- gv$sleeve_needs %||% NULL

  out <- gv
  out$stage            <- gv$stage %||% "PG0"
  out$portfolio_id     <- gv$portfolio_id %||% "PF_BOOK"
  out$n_strategies     <- n_strategies
  out$admitted_ids     <- as.list(admitted_ids)
  out$cold_start_phase <- if (n_strategies == 0L) 0L else if (n_strategies == 1L) 1L else 2L
  out$current_profile  <- current_profile
  out$target_profile   <- target_profile
  out$gap              <- gap
  out$sleeve_needs     <- as.list(open_dirs)          # 1차 조향 입력 = 실증-열린 방향만
  out$sleeve_needs_raw_builder <- sleeve_needs_raw    # 빌더 원본 보존
  out$sleeve_needs_steering <- GV_STEERING_DIRECTIONS # enum 전체 (closed 포함, evidence/posterior)
  out$steering <- list(
    steered_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    steering_version = .GVS_VERSION,
    steered_by       = "gap_vector_steering.R (post-processing layer over pg0_gap_review)",
    profile_source   = profile_source,
    basis            = "감사 SC-01/SC-06 — sleeve_needs 실증-열린 enum 재정의 (도훈 confirm 2026-07-03)"
  )

  # ── 5. 저장 ─────────────────────────────────────────────────────────────────
  if (write) {
    dir.create(dirname(gap_path), recursive = TRUE, showWarnings = FALSE)
    write_json(out, gap_path, auto_unbox = TRUE, pretty = TRUE, na = "null")
  }

  cat(sprintf("[gv_steering] Gap: CAGR=%+.4f, SR=%+.3f, MDD=%+.4f (book=%s, n=%d). Needs(open): [%s]. core_alpha_standalone=closed('16/16 admission FAIL, 2026-07 기준')\n",
              gap$cagr_gap, gap$sharpe_gap, gap$mdd_gap,
              ifelse(is.na(book_id), "none", book_id), n_strategies,
              paste(open_dirs, collapse = ", ")))

  invisible(out)
}
