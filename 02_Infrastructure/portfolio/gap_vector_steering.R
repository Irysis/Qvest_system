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
# .gvs_root 해석 (M10 수리 2026-07-11): sys.frame(1)$ofile은 중첩 source 시(pg0_gap_review
# A7b가 본 파일을 source하는 경로 포함) 최외곽 호출 스크립트의 디렉토리로 풀린다 —
# 실측에서 .gvs_proj가 Temp 쪽으로 오해석되어 steered 산출물이 엉뚱한 .cache에 쓰이고
# 정본 cache는 빌더 콜드스타트로 잔존. 후보 경로가 본 파일을 실제 포함하는지 검증 후
# 채택, 아니면 env 기반 canonical로 폴백.
.gvs_root <- local({
  cand <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
  fallback <- file.path(Sys.getenv("CLAUDE_PROJECT_DIR",
                                   Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")),
                        "02_Infrastructure/portfolio")
  ok <- is.character(cand) && length(cand) == 1L && nzchar(cand) &&
    file.exists(file.path(cand, "gap_vector_steering.R"))
  if (ok) cand else fallback
})
.gvs_proj <- normalizePath(file.path(.gvs_root, "..", ".."), winslash = "/", mustWork = FALSE)

suppressPackageStartupMessages({
  library(jsonlite)
})

if (!exists("%||%")) `%||%` <- function(a, b) if (!is.null(a)) a else b

# ─── Constants ───────────────────────────────────────────────────────────────
.GVS_VERSION       <- "1.1.1"   # M10 2026-07-11: 실book 연결(book_context/championship) + v8.3 enum 현행화 / 1.1.1 2026-07-17: incumbent_book_ir_basis 라벨 병기(값 무변경)
.GVS_GAP_PATH      <- file.path(.gvs_proj, ".cache", "portfolio_gap_vector.json")
.GVS_BOOK_STATE    <- file.path(.gvs_proj, "qepm", "mailbox", "governor", "book_state.json")
.GVS_MAX_AGE_DAYS  <- 30L
.GVS_DEFAULT_TARGET <- list(cagr = 0.16, sharpe = 2.5, mdd = 0.25)  # 헌법 제2목표 (SR 2.5, 2026-05-29 도훈 mandate)

# pinned 챔피언십 기준선 (FQ-011, pin_tag=fq011_20260710_222924) — book PORT_t의
# vintage-pinned 실측 SOT (measurement-graduation §7 vintage pinning 정합).
# 수치 창작 금지: 파일을 런타임에 읽어 소비만 한다 (부재 시 WARN + 필드 생략).
.GVS_CHAMPIONSHIP_SRC <- file.path(
  .gvs_proj, "stage_artifacts", "fq011_port_t_championship", "fq011_summary.json")

# 상설 프론티어 큐 SOT (v8.3 M5): 발굴 착수 전 확인 의무 대상 — 계기판에 포인터 노출.
.GVS_FRONTIER_QUEUE_REL <- "06_Registry/alpha_frontier_queue.json"

# book_id → 실측 계약 재계산 meta (metric_type=backtested(contract)) 매핑.
# 수치 창작 금지 원칙: 여기 등재된 실측 산출물만 current_profile 갱신에 소비.
# book 교체 시 새 계약 재계산 meta 경로를 추가할 것 (미등재 book = builder 프로파일 유지 + WARN).
.GVS_BOOK_METRICS_SOURCES <- list(
  "STR_1715_on_M4_R05_noLayer4_PG2" = file.path(
    .gvs_proj, "qepm", "mailbox", "worktask", "WT-D20260702_002",
    "output", "step3_clean_recompute_meta.json")
)

# ─── Steering enum (v8.3 현행화 2026-07-11 M10 — 원판 도훈 confirm 2026-07-03) ──
# 실증 기록 기반 탐색 방향. open 방향이 1차 조향 입력, closed는 posterior 라벨과
# 함께 최후순위 강등 (조향 입력에서 제외되나 기록은 보존 — INV-7 failure-ledger 정합).
# 서열 근거 = CLAUDE.md 제2목표 도달 경로 (2026-07-10 v8.3 재편, 실측 순위 재조정):
#   ① 비-return 신규 원천(주력) ② screen-tier 회수 + EW/cap-tier 재분류 ③ overlay 잔여.
# 구판(07-03: overlay=1순위 '주 레버'·dpl_feature=open)은 07-05/06 실측(overlay 양방향
# negative·clean 잔여폭 좁음)과 v8.3 DPL_FEATURE 발급 중단(measurement-graduation §5)에
# 의해 폐기 — 본 파일이 alpha Step 0 조준 계기판 생성기이므로 헌법 현행과 단일화.
GV_STEERING_DIRECTIONS <- list(
  non_return_datasource = list(
    status   = "open",
    priority = 1L,
    label    = "비-return 신규 원천 (DART exec-insider 역사·계약금액 magnitude·공매도/대차 등) — 주력",
    evidence = "CLAUDE.md 제2목표 경로 ① (v8.3 2026-07-10 실측 갱신) + 06_Registry/alpha_frontier_queue.json FQ-001~005. return-파생 횡단 alpha 소진 실측(memory project-corr-recovery-lane-nondart-exhaustion-20260706)"
  ),
  screen_tier_recovery = list(
    status   = "open",
    priority = 2L,
    label    = "screen-tier 재고 회수 + EW-대비/cap-tier 재분류 (overlay 큐 드레인·벤치-아티팩트 기각 후보 재라우팅)",
    evidence = "CLAUDE.md 제2목표 경로 ② (FQ-006~008) + v8.3 dual-basis 진단: post-2017 감쇠의 상당부분 = mega-cap 벤치 아티팩트 실측 (memory project-megacap-anchor-construction-discovery — EW-유니버스 대비 post2017_t 0.41→2.04 생존)"
  ),
  overlay_refinement = list(
    status   = "open",
    priority = 3L,
    label    = "overlay 잔여 정교화 (실증 유일 long-only β 레버이나 clean 잔여폭 좁음)",
    evidence = "CLAUDE.md 제2목표 경로 ③: 07-05/06 clean 재연구 양방향 negative 실측 (defensive 5변형 strict 全 base 열위 + bull-conviction dSR +0.005 — memory project-riskoverlay-multilayer-bearprob / project-pg2-overlay-gate-composition-settled)"
  ),
  residual_orthogonal_sleeve = list(
    status    = "conditional_frontier",
    priority  = 4L,
    label     = "잔차-직교 sleeve 스태킹 (RAMP R1 config-scoped 미달 — frontier 조건부)",
    condition = "PORT_t(NW lag-3) ≥ 2.95 통과분만 book 실질 기여 — 직교 ≠ 수익. 부활 프레임: soft-membership ML 앙상블·cost-optimized top-N·비-return 원천 결합",
    evidence  = "RAMP R1 실측 2026-07-05 (L-RAMP-20260705_184828): 11 직교 sleeve 개별·선택스택·soft-overlay 전부 cap-w PORT_t<2.95(best 2.54)·survivors 0. 단 구조판결 아님(β≈0.92·active-corr 0.53, INV-7) — measurement-graduation §6 ②"
  ),
  dpl_feature = list(
    status    = "closed",
    priority  = 98L,
    label     = "DPL 구성레이어/피처 lane (발급 중단)",
    posterior = "DPL 구현 lane settled-negative (2026-06-26, SR 0.75~0.89 ≪ PG2 1.52 — memory project-dpl-vs-pg2-settled) + screen_route DPL_FEATURE 발급 중단 (v8.3 2026-07-10, measurement-graduation §5 — TURNOVER_REVIEW 대체). 부활신호 발화 시에만 재검토 (INV-7)",
    evidence  = "measurement-graduation §5 (2026-07-10 정합): 피처 보존 원칙은 유지하되 DPL 구현 재제안 금지"
  ),
  core_alpha_standalone = list(
    status    = "closed",
    priority  = 99L,
    label     = "standalone core_alpha 신규 발굴 (최후순위 강등)",
    posterior = "16/16 admission FAIL (2026-07 기준) + 신규 standalone return-파생 팩터 사냥 = 최후순위 (CLAUDE.md 제2목표, 16/16 FAIL posterior)",
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

  # ── 3b. 실book 컨텍스트 (M10 2026-07-11) — book_state 읽기 전용 소비 ──────────
  # incumbent_book_ir(§4 book-marginal 게이트 기준선) + 라이브 노출을 계기판에 노출.
  book_context <- NULL
  if (length(bs) > 0) {
    # live_exposure_change는 book_state 최상위가 아니라 event 블록(예:
    # event_WT_D20260702_002_layer4_removal) 내부에 중첩 — 최상위 우선, 없으면 1단계 중첩 탐색.
    lec <- bs$live_exposure_change %||% NULL
    if (is.null(lec)) {
      for (el in bs) {
        if (is.list(el) && !is.null(el$live_exposure_change)) { lec <- el$live_exposure_change; break }
      }
    }
    book_context <- list(
      book_id           = book_id,
      incumbent_book_ir = as.numeric(bs$incumbent_book_ir %||% NA),
      # basis 라벨 병기 필드 — 값 자체 무변경 (measurement-graduation §4 basis 라벨 의무).
      # 재산출은 FQ-044 후속(도훈 결정) 대기이므로 여기서는 라벨만 붙인다.
      incumbent_book_ir_basis = list(
        basis            = "stored embedded-BM: book_state.json 저장값 (recon NAV net-active vs 저장 벤치, ir_convention=net_active_recon_v1)",
        computed_at      = as.character(bs$updated_at %||% NA),
        computed_at_note = "book_state updated_at 기준 (산출 실체 = WT-D20260702_002 step3_clean_recompute_meta)",
        caution          = "window-matched clean-basis 재산출 = FQ-044 후속(도훈 결정) 대기 — 저장 패널 same-month vintage 사고(§7b) 이후 stored 수치 인용 시 basis 라벨 의무. 본 필드는 라벨 병기이며 값은 무변경"
      ),
      ir_convention     = bs$ir_convention %||% NA,
      metric_type       = "backtested",
      source            = "qepm/mailbox/governor/book_state.json (read-only)"
    )
    if (!is.null(lec)) {
      book_context$live_exposure <- list(
        as_of    = lec$as_of %||% NA,
        regime   = lec$regime %||% NA,
        invested = as.numeric(lec$noL4_invested %||% NA),
        cash     = as.numeric(lec$noL4_cash %||% NA)
      )
    }
  } else {
    cat("[gv_steering] WARN: book_state.json 부재/파싱실패 — book_context 생략\n")
  }

  # ── 3c. pinned 챔피언십 기준선 (FQ-011) — vintage-pinned book PORT_t 실측 ─────
  championship <- NULL
  if (file.exists(.GVS_CHAMPIONSHIP_SRC)) {
    fq <- tryCatch(fromJSON(.GVS_CHAMPIONSHIP_SRC, simplifyVector = FALSE), error = function(e) NULL)
    r1 <- if (!is.null(fq)) fq$R1_baseline_noLayer4 %||% NULL else NULL
    if (!is.null(r1)) {
      championship <- list(
        tag              = r1$tag %||% "R1_noLayer4_baseline",
        port_t_nw_lag3   = as.numeric(r1$PORT_t %||% NA),
        ir_pinned        = as.numeric(r1$IR %||% NA),
        oos_v2           = as.numeric(r1$oos_v2 %||% NA),
        post2017_t       = as.numeric(r1$post2017_t %||% NA),
        calmar           = as.numeric(r1$calmar %||% NA),
        pin_tag          = fq$pin_tag %||% NA,
        basis            = fq$basis %||% "cap-w active vs pinned IKS200 (authoritative)",
        metric_type      = fq$metric_type %||% "backtested",
        note             = "IR 컨벤션 주의: book_state incumbent_book_ir(net_active_recon_v1, 현행 IKS200 vintage)과 별개 — 본 값은 pinned vintage 산출 (basis 라벨 의무, measurement-graduation §4/§7)",
        source           = "stage_artifacts/fq011_port_t_championship/fq011_summary.json"
      )
    }
  }
  if (is.null(championship)) {
    cat(sprintf("[gv_steering] WARN: 챔피언십 기준선 미소비 (%s 부재/파싱실패) — championship_baseline 생략\n",
                .GVS_CHAMPIONSHIP_SRC))
  }

  # ── 4. sleeve_needs 조향 재정의 ──────────────────────────────────────────────
  prios <- vapply(GV_STEERING_DIRECTIONS, function(d) d$priority, integer(1))
  open_mask <- vapply(GV_STEERING_DIRECTIONS, function(d) d$status != "closed", logical(1))
  open_dirs <- names(GV_STEERING_DIRECTIONS)[open_mask][order(prios[open_mask])]

  sleeve_needs_raw <- gv$sleeve_needs %||% NULL

  out <- gv
  out$stage            <- gv$stage %||% "PG0"
  # portfolio_id: 계기판의 대상은 실 운용 북 — 빌더가 어떤 포트id로 호출됐든
  # (예: PF_ALPHASEARCH 권고 경로) cache 정본은 book 기준으로 라벨 (빌더 원본 보존).
  out$portfolio_id_builder <- gv$portfolio_id %||% NA
  out$portfolio_id     <- "PF_BOOK"
  out$n_strategies     <- n_strategies
  out$admitted_ids     <- as.list(admitted_ids)
  out$cold_start_phase <- if (n_strategies == 0L) 0L else if (n_strategies == 1L) 1L else 2L
  out$current_profile  <- current_profile
  out$target_profile   <- target_profile
  out$gap              <- gap
  out$book_context     <- book_context             # 실book 연결 (M10)
  out$championship_baseline <- championship        # pinned PORT_t 기준선 (M10)
  out$frontier_queue   <- .GVS_FRONTIER_QUEUE_REL  # v8.3 M5 상설 큐 포인터 (착수 전 확인 의무)
  out$sleeve_needs     <- as.list(open_dirs)          # 1차 조향 입력 = 실증-열린 방향만
  out$sleeve_needs_raw_builder <- sleeve_needs_raw    # 빌더 원본 보존
  out$sleeve_needs_steering <- GV_STEERING_DIRECTIONS # enum 전체 (closed 포함, evidence/posterior)
  out$steering <- list(
    steered_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    steering_version = .GVS_VERSION,
    steered_by       = "gap_vector_steering.R (post-processing layer over pg0_gap_review)",
    profile_source   = profile_source,
    basis            = "감사 SC-01/SC-06 enum 재정의 (도훈 confirm 2026-07-03) + M10 실book 연결·v8.3 서열 현행화 (2026-07-11, CLAUDE.md 제2목표 경로 ①②③)"
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
