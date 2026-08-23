#!/usr/bin/env Rscript
#==============================================================================
# essence_score.R — Qvest 본질 스코어 + 등급 (Dual-Mode SOT §3.5)
#
# 본질 = 리스크 대비 수익률. 계약 bt_result에서 5 본질지표를 *읽기만* 하고
# A/B/C/F 등급을 산정한다. 자체합성(prod(1+r)/수동 Sharpe) 금지 — 계약값만 사용.
# DSR만 계약 미산출 → net active 시계열에서 BLdP(2014) 공식으로 보강 산출.
#
# ★문턱 정본 (v9 §3.3, 2026-08-23): 아래 수치는 전부
#   02_Infrastructure/worktask/constraint_defaults.json :: tier_graduation 에서 읽는다.
#   이 파일에는 폴백 사본(.GRAD_FALLBACK)만 남으며, 재보정은 JSON 한 곳만 고친다.
#   실제로 쓰인 문턱은 반환 객체의 graduation_params 에 기록된다(사후 감사).
#
# Grade A 임계 (전부 문서값/도출값 — 지어낸 것 없음):
#   PORT_t ≥ 2.95   (Harvey-Liu-Zhu 2016 — 문헌-레벨 다중검정 이미 반영)
#   OOS retention ≥ 0.7  (활성 Sharpe OOS/IS, 65/35; 과적합 게이트 — DSR 대체)
#   Sharpe ≥ 0.8, CAGR ≥ 16%  (legacy hurdle_gate Grade A 유지 / CLAUDE.md 제2목표)
#   Calmar ≥ 0.64   (= 16%/25%, CAGR16·MDD25 제2목표서 도출 — "리스크 대비 수익" 위험조정 게이트)
#   DSR ≥ 0.5 (BLdP 2014)  ← **sweep형 selection(열거집합 argmax/threshold-pick: ML스윕/optimizer서치/앙상블/사전등록 grid)에서만 게이트.**
#                            1논문/1알파 + 가설주도 순차개선 chain(selection_type="chain")엔 부적용
#                            (도훈 mandate 2026-05-31/2026-06-10; chain 자격 = IS-only 변형선택 + holdout 1회 — measurement-graduation §3).
#                            DSR 수치는 n_trials>1이면 진단용으로 항상 산출(게이트와 무관).
#
# 18-component proxy 합산(hurdle_gate.R)은 폐기 — 진단용으로만 retain.
#
# essence_score(bt_result, n_trials_cumulative = NULL, hard_fail = NULL, ..., selection_type = NULL)
#   bt_result : build_bt_result() 10-component (계약). 필수: metrics, benchmark_compare.
#   n_trials_cumulative : DSR 산출용 누적 시행수 (기록 의무 유지 — 게이트 적용 여부와 별개).
#   hard_fail : 외부 주입(judge). NULL이면 MDD 깊이 단독이 아니라
#               drawdown episode 빈도/지속성으로 구조적 hard fail 추론.
#   selection_type : "sweep"(게이트 강제) / "chain"(가설주도 순차개선 — 게이트 면제) /
#                    NULL(legacy: n_trials>1 휴리스틱 유지, 기존 sweep caller 호환).
#   oos_stat_version : "v2"(기본, 2026-06-10 도훈 mandate C1) = anchored 3분할{55/65/75} retention 중앙값
#                      / "v1" = 단일 65/35 (legacy 재현용).
#   escalation_evidence : C1 borderline band [0.5,0.7) 보강증거 (2/3 충족 시 조건부 PASS).
#                      list(trailing_port_t=, placebo_p=, book_marginal_delta_sr=, cor_vs_book=).
#                      ① trailing PORT_t>0 ② placebo p<0.05 ③ ΔSR>0 ∧ |cor|<0.30. holdout은 증거 불가(봉인).
#                      retention<0.5는 증거 무관 FAIL(band 남용 차단).
#   oos_fail_pattern : 선택 라벨 "overfit"/"decay" — FAIL 시 사유 분리(decay→screen_route 라우팅, 자본졸업 불가).
# Returns: list(grade, metric_type, essence{...}, hard_fail, reasons)
#==============================================================================

suppressPackageStartupMessages({ library(data.table) })

#==============================================================================
# v9 §3.3 파라미터 단일화 (2026-08-23) — 자본 층 문턱의 단일 정본
#
# 정본 = 02_Infrastructure/worktask/constraint_defaults.json :: tier_graduation.
# 이 파일은 그 블록을 *읽기만* 한다. 구판은 같은 수치가 JSON 과 이 파일에 쌍둥이로
# 존재했다 — 한쪽만 바뀌면 조용히 갈라지는 드리프트 경로였고, 실제로 헌법이
# max_names 20→25 변경에서 같은 계통을 밟은 전례가 있다(worktask_manager.R
# 2026-08-20 수리 주석 참조). 값 재보정은 도훈 권한이며 JSON 한 곳만 고치면 된다.
#
# ★fail-open 설계: 파일/키가 없으면 **현행 리터럴로 그대로 폴백**하고 경고 1줄만 낸다.
#   판정 기계가 설정 결측으로 멈추면 안 된다(도입 시점 회귀 0 보장). 어느 키가
#   폴백됐는지는 반환 객체 graduation_params 에 기록돼 사후 감사가 가능하다.
#
# ★`[[ ]]` 정확 일치 필수 — `$` 는 리스트에서 **부분 일치**를 한다. min_calmar 가
#   결측이면 `$min_calmar` 가 min_calmar_rationale(문자열)에 매칭돼 as.numeric 이
#   NA 를 낸다: 폴백이 아니라 "그럴듯한 쓰레기". 같은 함정을 worktask_manager.R 이
#   2026-08-20 에 실측·기록했다.
#==============================================================================

.GRAD_CACHE <- new.env(parent = emptyenv())

# 폴백 정본 = 2026-08-23 시점 하드코딩 값 그대로(= 오늘의 동작). 값 변경 금지 —
#   이 목록을 고치는 것은 문턱 재보정이며 JSON 이 아니라 여기를 고치면 정본이 다시 갈라진다.
.GRAD_FALLBACK <- list(
  port_t_min   = 2.95,   # Grade A core: portfolio-alpha t (NW lag-3), Harvey-Liu-Zhu
  oos_min      = 0.7,    # oos_retention band 상단(단독 PASS)
  oos_floor    = 0.5,    # oos_retention band 하단(미만 = 증거 무관 FAIL)
  calmar_min   = 0.64,   # = 16%/25%
  dsr_min      = 0.5,    # BLdP DSR — sweep형 selection에서만 게이트
  mdd_hard     = 0.45,   # drawdown 프로파일 severe 임계
  sharpe_min   = 0.8,    # Grade A core
  cagr_min     = 0.16,   # Grade A core
  b_port_t_min = 2.0,    # Grade B(component) 진입
  b_net_ir_min = 0.2     # Grade B(component) 진입 (초과 비교)
)

# R 파라미터명 → constraint_defaults.json::tier_graduation 키
.GRAD_KEYMAP <- c(
  port_t_min   = "min_portfolio_alpha_t_nw",
  oos_min      = "min_oos_retention",
  oos_floor    = "oos_retention_floor",
  calmar_min   = "min_calmar",
  dsr_min      = "min_deflated_sharpe_ratio",
  mdd_hard     = "mdd_hard",
  sharpe_min   = "grade_a_min_sharpe",
  cagr_min     = "grade_a_min_cagr",
  b_port_t_min = "grade_b_min_portfolio_alpha_t",
  b_net_ir_min = "grade_b_min_net_ir"
)

# 프로젝트 루트 해석 — 후보를 marker(CLAUDE.md + 06_Registry)로 **정체성** 검증해 채택한다.
#   존재 검사(dir.exists)만으로 루트를 신뢰하지 않는다(r-portability 금칙 ③).
#   본 파일 하단 AST 사이드카 블록과 동일한 resolver 규약 — 규약을 하나로 유지한다.
#   sys.frame()$ofile 은 중첩 source 시 바깥 스크립트를 가리켜 신뢰 불가(기지 트랩).
.graduation_root <- function() {
  for (.c0 in c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                Sys.getenv("QM_ROOT", unset = ""), getwd())) {
    if (!nzchar(.c0)) next
    .c0 <- gsub("\\\\", "/", .c0)
    if (file.exists(file.path(.c0, "CLAUDE.md")) &&
        dir.exists(file.path(.c0, "06_Registry"))) return(.c0)
  }
  NA_character_
}

#' 자본 층(graduation) 문턱 로더 — 캐시됨
#'
#' ★캐시 수명 = R 세션. 정본 JSON 을 고쳐도 **이미 떠 있는 세션은 옛 값을 계속 쓴다**
#'   (위반 주입 실측 S7, 2026-08-23). 재보정 후에는 새 세션에서 돌리거나
#'   `.graduation_params(refresh = TRUE)` 를 한 번 호출할 것. 판정 배치가
#'   중간에 문턱을 갈아타면 같은 라운드 안에서 기준이 달라지므로 캐시가 기본값이다.
#'
#' @param refresh TRUE 면 캐시 무시하고 재로드(테스트/재보정 확인용).
#' @param root    명시 루트(검사기 격리용). NULL 이면 marker resolver.
#' @return 위 .GRAD_FALLBACK 과 동일 이름의 numeric 리스트.
.graduation_params <- function(refresh = FALSE, root = NULL) {
  if (!refresh && is.null(root) && !is.null(.GRAD_CACHE$p)) return(.GRAD_CACHE$p)
  p <- .GRAD_FALLBACK
  src <- NA_character_; missed <- character(0)
  r0 <- if (!is.null(root)) root else .graduation_root()
  f <- if (!is.na(r0) && nzchar(r0)) {
    file.path(r0, "02_Infrastructure", "worktask", "constraint_defaults.json")
  } else NA_character_
  tg <- NULL
  if (!is.na(f) && file.exists(f) && requireNamespace("jsonlite", quietly = TRUE)) {
    tg <- tryCatch(jsonlite::fromJSON(f, simplifyVector = TRUE)[["tier_graduation"]],
                   error = function(e) NULL)
    if (!is.null(tg)) src <- f
  }
  for (nm in names(.GRAD_KEYMAP)) {
    v <- if (is.null(tg)) NULL else tg[[ .GRAD_KEYMAP[[nm]] ]]   # [[ ]] = 정확 일치
    v <- suppressWarnings(as.numeric(v[1]))
    if (length(v) == 1L && is.finite(v)) p[[nm]] <- v else missed <- c(missed, nm)
  }
  if (length(missed)) {
    warning(sprintf("[essence_score] graduation 문턱 정본 미해소 (%s) — 현행 리터럴 폴백: %s",
                    if (is.na(src)) "constraint_defaults.json 미발견" else "키 결측/비수치",
                    paste(missed, collapse = ",")), call. = FALSE)
  }
  # ★속성을 캐시 *전에* 붙인다 — 뒤에 붙이면 캐시 적중 경로가 속성 없는 사본을 돌려줘
  #   첫 호출과 두 번째 호출의 반환값이 달라진다(감사 기록이 조용히 비는 결함).
  attr(p, "source") <- if (is.na(src)) "fallback_literals" else src
  attr(p, "fallback_keys") <- missed
  if (is.null(root)) .GRAD_CACHE$p <- p
  p
}

# Bailey-López de Prado (2014) Deflated Sharpe (per-period; dpl_ens_eval_contract.R와 동일 공식)
.essence_dsr <- function(sr_ann, n_obs, n_trials, skew = 0, kurt = 3, A = 12) {
  if (!is.finite(sr_ann) || !is.finite(n_obs) || n_obs < 12) return(NA_real_)
  emc <- 0.5772156649
  sr_m <- sr_ann / sqrt(A)
  var0 <- 1 / (n_obs - 1)
  if (is.null(n_trials) || !is.finite(n_trials) || n_trials < 2) {
    sr0 <- 0
  } else {
    z1 <- qnorm(1 - 1 / n_trials); z2 <- qnorm(1 - 1 / (n_trials * exp(1)))
    sr0 <- sqrt(var0) * ((1 - emc) * z1 + emc * z2)
  }
  den <- sqrt(1 - skew * sr_m + (kurt - 1) / 4 * sr_m^2)
  if (!is.finite(den) || den <= 0) return(NA_real_)
  pnorm((sr_m - sr0) * sqrt(n_obs - 1) / den)
}

.rn <- function(x, d = 3) if (is.null(x) || !is.finite(x)) NA_real_ else round(as.numeric(x), d)

# (v9 §3.3) 문턱을 판정 사유 문자열에 찍을 때 쓰는 포맷터 — 정수값이어도 소수 1자리를
#   유지한다. 구판 텍스트가 "PORT_t>=2.0" 이라 `%g`(→"2")로는 바이트가 달라진다.
#   `%.1f` 로 하면 2.25 가 "2.2" 로 잘리므로(재보정 시 사유가 거짓말) 무손실로 처리한다.
.thr1 <- function(x) {
  s <- format(x, trim = TRUE, scientific = FALSE)
  if (grepl(".", s, fixed = TRUE)) s else paste0(s, ".0")
}

.essence_drawdown_profile <- function(bt_result, mdd,
                                      # (v9 §3.3) severe 기본값도 정본 경유 — 유일 호출자
                                      #   essence_score() 는 항상 severe=mdd_hard 로 덮으므로
                                      #   실경로 동작은 불변이고, 직접 호출 시의 쌍둥이만 제거된다.
                                      #   extreme/catastrophic/count/frac 계열은 별개 휴리스틱이라
                                      #   이번 범위 밖(정본화 후속 대상 — JSON mdd_hard_rationale 참조).
                                      severe = .graduation_params()$mdd_hard, extreme = 0.55,
                                      catastrophic = 0.70,
                                      severe_hard_count = 15L,
                                      extreme_hard_count = 6L,
                                      severe_period_hard_frac = 0.25,
                                      severe_max_hard_periods = 252L) {
  pr_n <- tryCatch(nrow(as.data.table(bt_result$period_returns)), error = function(e) NA_integer_)
  pr <- tryCatch(as.data.table(bt_result$period_returns), error = function(e) NULL)
  if (!is.null(pr) && nrow(pr) > 0 && "ret_net" %in% names(pr)) {
    ret <- suppressWarnings(as.numeric(pr$ret_net))
    ret[!is.finite(ret)] <- 0
    nav <- cumprod(1 + pmax(ret, -0.9999))
    dd_path <- nav / cummax(nav) - 1
    .episodes <- function(th) {
      flag <- is.finite(dd_path) & dd_path <= -th
      if (!any(flag)) return(list(count = 0L, total = 0L, max = 0L, frac = 0))
      rr <- rle(flag)
      lens <- rr$lengths[rr$values]
      list(
        count = length(lens),
        total = sum(lens),
        max = max(lens),
        frac = sum(lens) / length(dd_path)
      )
    }
    ep_severe <- .episodes(severe)
    ep_extreme <- .episodes(extreme)
    mdd_path <- abs(min(dd_path, na.rm = TRUE))
    mdd_eff <- if (is.finite(mdd)) mdd else mdd_path
    structural <- isTRUE(is.finite(mdd_eff) && (
      mdd_eff >= catastrophic ||
        ep_severe$count >= severe_hard_count ||
        ep_extreme$count >= extreme_hard_count ||
        (is.finite(ep_severe$frac) && ep_severe$frac >= severe_period_hard_frac)
    ))

    return(list(
      severe_count = as.integer(ep_severe$count),
      extreme_count = as.integer(ep_extreme$count),
      severe_total_periods = as.integer(ep_severe$total),
      severe_max_periods = as.integer(ep_severe$max),
      severe_period_frac = ep_severe$frac,
      catastrophic_threshold = catastrophic,
      severe_hard_count = severe_hard_count,
      extreme_hard_count = extreme_hard_count,
      severe_period_hard_frac = severe_period_hard_frac,
      severe_max_hard_periods = severe_max_hard_periods,
      tail_review = isTRUE(is.finite(mdd_eff) && mdd_eff > severe && !structural),
      structural_hard_fail = structural,
      reason = if (structural) {
        "repeated/sample-dominant severe drawdown"
      } else if (isTRUE(ep_severe$max >= severe_max_hard_periods)) {
        "single long severe-drawdown episode; review, not hard fail"
      } else {
        "tail review or normal drawdown"
      }
    ))
  }

  dd <- tryCatch(as.data.table(bt_result$drawdowns), error = function(e) NULL)
  if (is.null(dd) || nrow(dd) == 0 || !"drawdown_depth" %in% names(dd)) {
    structural <- isTRUE(is.finite(mdd) && mdd >= catastrophic)
    return(list(
      severe_count = 0L, extreme_count = 0L,
      severe_total_periods = 0L, severe_max_periods = 0L,
      severe_period_frac = NA_real_,
      catastrophic_threshold = catastrophic,
      severe_hard_count = severe_hard_count,
      extreme_hard_count = extreme_hard_count,
      severe_period_hard_frac = severe_period_hard_frac,
      severe_max_hard_periods = severe_max_hard_periods,
      tail_review = isTRUE(is.finite(mdd) && mdd > severe && !structural),
      structural_hard_fail = structural,
      reason = "drawdowns table missing; catastrophic MDD only"
    ))
  }

  depth <- abs(suppressWarnings(as.numeric(dd$drawdown_depth)))
  len_col <- if ("total_underwater_period" %in% names(dd)) {
    "total_underwater_period"
  } else if ("drawdown_length" %in% names(dd)) {
    "drawdown_length"
  } else {
    NA_character_
  }
  len <- if (!is.na(len_col)) suppressWarnings(as.numeric(dd[[len_col]])) else rep(NA_real_, length(depth))
  if (length(len) != length(depth)) len <- rep(NA_real_, length(depth))
  len[!is.finite(len)] <- 0
  severe_idx <- is.finite(depth) & depth >= severe
  extreme_idx <- is.finite(depth) & depth >= extreme
  severe_count <- sum(severe_idx)
  extreme_count <- sum(extreme_idx)
  severe_total <- sum(len[severe_idx], na.rm = TRUE)
  severe_max <- if (any(severe_idx)) max(len[severe_idx], na.rm = TRUE) else 0
  severe_frac <- if (is.finite(pr_n) && pr_n > 0) severe_total / pr_n else NA_real_

  structural <- isTRUE(is.finite(mdd) && (
    mdd >= catastrophic ||
      severe_count >= severe_hard_count ||
      extreme_count >= extreme_hard_count ||
      (is.finite(severe_frac) && severe_frac >= severe_period_hard_frac)
  ))

  list(
    severe_count = as.integer(severe_count),
    extreme_count = as.integer(extreme_count),
    severe_total_periods = as.integer(severe_total),
    severe_max_periods = as.integer(severe_max),
    severe_period_frac = severe_frac,
    catastrophic_threshold = catastrophic,
    severe_hard_count = severe_hard_count,
    extreme_hard_count = extreme_hard_count,
    severe_period_hard_frac = severe_period_hard_frac,
    severe_max_hard_periods = severe_max_hard_periods,
    tail_review = isTRUE(is.finite(mdd) && mdd > severe && !structural),
    structural_hard_fail = structural,
    reason = if (structural) {
      "repeated/sample-dominant severe drawdown"
    } else if (isTRUE(severe_max >= severe_max_hard_periods)) {
      "single long recovery severe drawdown; review, not hard fail"
    } else {
      "tail review or normal drawdown"
    }
  )
}

essence_score <- function(bt_result, n_trials_cumulative = NULL,
                          # (v9 §3.3) 기본값 정본 = constraint_defaults.json::tier_graduation.
                          #   R 기본인자는 지연 평가라 호출자가 명시 전달하면 그 값이 우선한다
                          #   — 기존 override 동작 불변(회귀 없음).
                          hard_fail = NULL, mdd_hard = .graduation_params()$mdd_hard,
                          oos_is_ratio_override = NULL,
                          calmar_min = .graduation_params()$calmar_min,
                          selection_type = NULL,
                          oos_stat_version = "v2",
                          escalation_evidence = NULL,
                          oos_fail_pattern = NULL,
                          # (AST v1.1 Step 4, 2026-07-25 — SOT §5) 구조특징 사이드카 로깅.
                          #  ast_features: ast_compile manifest의 구조특징 list(node_count/free_param_count/
                          #  conditional_op_count/window_variety/escape_leaf_count 등). NULL = 비-AST 산출
                          #  (NULL 여부 자체가 escape 커버리지 정보라 전 판정 로깅 — 생존편향 방지).
                          #  기록은 append-only 사이드카(06_Registry/ast_structure_log.jsonl), 채점 계산 무관여,
                          #  실패 시 침묵 skip(fail-soft — 로깅 장애가 graduation 판정을 막지 않는다).
                          #  judge/governor verdict는 채점 시점 미존재 — strategy_id 키로 사후 조인.
                          ast_features = NULL, strategy_id = NULL, active_regime = NULL,
                          sidecar_log = TRUE) {
  .nz <- function(x) { v <- suppressWarnings(as.numeric(if (is.null(x) || length(x) == 0L) NA else x[[1]])); v }
  stopifnot(is.list(bt_result),
            !is.null(bt_result$metrics), !is.null(bt_result$benchmark_compare))
  # (v9 §3.3) 나머지 문턱 일괄 로드. mdd_hard/calmar_min 은 형식인자라 위에서 이미 해소됐다.
  .gp <- .graduation_params()
  M  <- as.data.table(bt_result$metrics)
  BC <- as.data.table(bt_result$benchmark_compare)
  # 스키마 변종 robust: 컬럼명 alias 해소 + 결측 시 NA(크래시 금지 → uncertain 강등)
  .col <- function(dt, cands) { h <- intersect(cands, names(dt)); if (length(h)) h[1] else NA_character_ }
  m_nc <- .col(M, c("metric_name", "name")); m_vc <- .col(M, c("metric_value", "value"))
  bc_nc <- .col(BC, c("metric_name", "name")); bc_vc <- .col(BC, c("active_value", "value", "metric_value"))
  getm  <- function(nm) { if (is.na(m_nc) || is.na(m_vc)) return(NA_real_)
                          v <- M[get(m_nc) == nm, get(m_vc)];  if (length(v) == 0) NA_real_ else as.numeric(v[1]) }
  getbc <- function(nm) { if (is.na(bc_nc) || is.na(bc_vc)) return(NA_real_)
                          v <- BC[get(bc_nc) == nm, get(bc_vc)]; if (length(v) == 0) NA_real_ else as.numeric(v[1]) }

  # --- 5 본질지표 (계약값 읽기만) ---
  sharpe <- getm("Sharpe")
  cagr   <- getm("CAGR")
  mdd    <- getm("MDD")
  calmar <- getm("Calmar")
  net_ir <- getbc("Information_Ratio")
  port_t <- getbc("Portfolio_Alpha_t_NW_lag3")
  dd_profile <- .essence_drawdown_profile(bt_result, mdd, severe = mdd_hard)

  # --- 활성(alpha) 시계열: OOS retention(과적합, DSR 대체) + DSR(스윕 한정) ---
  af <- suppressWarnings(as.numeric(M[["annualization_factor"]][1]))
  if (length(af) != 1 || !is.finite(af)) af <- 12
  dsr <- NA_real_; oos_retention <- NA_real_; oos_retention_splits <- NA_real_
  # DSR *게이트* = sweep형 selection(열거집합 argmax/threshold-pick)에서만 (도훈 mandate 2026-06-10).
  #   selection_type "sweep"=강제 / "chain"(가설주도 순차개선, IS-only 선택 규율)=면제 /
  #   NULL(legacy)=n_trials>1 휴리스틱 (기존 sweep caller 호환). DSR 수치는 n_trials>1이면 진단용 항상 산출.
  has_trials <- !is.null(n_trials_cumulative) && is.finite(n_trials_cumulative) && n_trials_cumulative > 1
  is_sweep <- if (identical(selection_type, "chain")) FALSE
              else if (identical(selection_type, "sweep")) TRUE
              else has_trials
  pr <- bt_result$period_returns; br <- bt_result$benchmark_returns
  if (!is.null(pr) && !is.null(br)) {
    pr <- as.data.table(pr); br <- as.data.table(br)
    if (all(c("date", "ret_net") %in% names(pr)) &&
        all(c("date", "benchmark_ret") %in% names(br))) {
      m <- merge(pr[, .(date, ret_net)], br[, .(date, benchmark_ret)], by = "date")
      setorder(m, date)
      a <- m$ret_net - m$benchmark_ret; a <- a[is.finite(a)]
      n <- length(a)
      if (n >= 12 && sd(a) > 0) {
        # OOS retention (C1 v2, 2026-06-10 도훈 mandate): anchored 다중분할 {55/65/75} 중앙값
        #   — 단일 절단점의 임의성 노이즈 축소 (표본 노이즈 자체는 정보이론적 한계, 제거 불가).
        splits <- if (identical(oos_stat_version, "v1")) 0.65 else c(0.55, 0.65, 0.75)
        rets <- vapply(splits, function(fr) {
          k <- floor(n * fr)
          if (k < 6 || (n - k) < 6) return(NA_real_)
          ia <- a[1:k]; oa <- a[(k + 1):n]
          is_ir  <- if (sd(ia) > 0) mean(ia) / sd(ia) * sqrt(af) else NA_real_
          oos_ir <- if (sd(oa) > 0) mean(oa) / sd(oa) * sqrt(af) else NA_real_
          if (is.finite(is_ir) && is_ir > 0.05 && is.finite(oos_ir)) oos_ir / is_ir else NA_real_
        }, numeric(1))
        oos_retention_splits <- rets
        if (any(is.finite(rets))) oos_retention <- stats::median(rets[is.finite(rets)])
        # DSR(BLdP) 수치 = n_trials>1이면 진단용 산출 (게이트 적용은 is_sweep — 아래 dsr_ok).
        if (has_trials) {
          mu <- mean(a); s <- sd(a)
          dsr <- .essence_dsr(mean(a) / s * sqrt(af), n, n_trials_cumulative,
                              mean(((a - mu) / s)^3), mean(((a - mu) / s)^4), A = af)
        }
      }
    }
  }
  # judge lockbox 실 OOS 비율 주입 시 우선 (65/35 fallback 대체)
  if (!is.null(oos_is_ratio_override) && is.finite(oos_is_ratio_override)) oos_retention <- oos_is_ratio_override

  # --- hard_fail: 외부(judge) 주입 우선. 없으면 MDD 깊이 단독이 아니라 빈도/표본 점유율로 추론 ---
  # 단발/소수 시장 동반 폭락과 장기 회복 지연은 tail_review로 남기고,
  # repeated severe drawdown / sample-dominant severe drawdown만 hard fail.
  if (is.null(hard_fail)) hard_fail <- isTRUE(dd_profile$structural_hard_fail)

  # --- C1 borderline band [0.5, 0.7): 보강증거 2/3 충족 시 조건부 통과 (2026-06-10 도훈 mandate) ---
  #   retention >= 0.7 단독 PASS(불변) / < 0.5 무조건 FAIL(증거 무관) / band는 escalation 2/3.
  band_lo <- .gp$oos_floor; band_hi <- .gp$oos_min   # (v9 §3.3) 정본 경유
  esc_pass <- NA; esc_detail <- NULL
  if (!is.null(escalation_evidence) && is.list(escalation_evidence)) {
    ev <- escalation_evidence
    e1 <- isTRUE(is.finite(.nz(ev$trailing_port_t)) && .nz(ev$trailing_port_t) > 0)
    e2 <- isTRUE(is.finite(.nz(ev$placebo_p)) && .nz(ev$placebo_p) < 0.05)
    e3 <- isTRUE(is.finite(.nz(ev$book_marginal_delta_sr)) && .nz(ev$book_marginal_delta_sr) > 0 &&
                 is.finite(.nz(ev$cor_vs_book)) && abs(.nz(ev$cor_vs_book)) < 0.30)
    esc_pass <- sum(c(e1, e2, e3)) >= 2L
    esc_detail <- list(trailing_port_t_pos = e1, placebo_sig = e2, book_marginal = e3)
  }
  oos_in_band <- is.finite(oos_retention) && oos_retention >= band_lo && oos_retention < band_hi
  oos_ok <- (is.finite(oos_retention) && oos_retention >= band_hi) ||
            (oos_in_band && isTRUE(esc_pass))
  oos_band_status <- if (!is.finite(oos_retention)) NA_character_
                     else if (oos_retention >= band_hi) "pass"
                     else if (oos_in_band && isTRUE(esc_pass)) "band_escalated"
                     else if (oos_in_band) "band_fail"
                     else "fail"

  # --- 등급 (SOT §3.5): 유의성=PORT_t / 과적합=OOS retention / 위험조정=Calmar / DSR=스윕한정 ---
  reasons <- character(0)
  contract_ok <- is.finite(port_t) && is.finite(net_ir)  # 계약 경유 여부
  # DSR 게이트: sweep형 selection에서만 요구. chain/1논문/1알파에선 부적용(통과 간주).
  dsr_ok <- if (is_sweep) (is.finite(dsr) && dsr >= .gp$dsr_min) else TRUE
  a_core <- (is.finite(port_t) && port_t >= .gp$port_t_min &&
             oos_ok &&
             is.finite(sharpe) && sharpe >= .gp$sharpe_min &&
             is.finite(cagr)   && cagr   >= .gp$cagr_min &&
             is.finite(calmar) && calmar >= calmar_min)

  if (!contract_ok) {
    grade <- "uncertain"
    reasons <- "PORT_t/net_IR 미산출(계약 미경유) — 추정 등급 금지"
  } else if (hard_fail) {
    grade <- "F"
    reasons <- sprintf("hard_fail drawdown structure (MDD %.1f%%, %.0f%%+ episodes=%d, %.0f%%+ episodes=%d, max_underwater=%d periods)",
                       mdd * 100, mdd_hard * 100, dd_profile$severe_count,
                       max(0.55, mdd_hard + 0.10) * 100, dd_profile$extreme_count,
                       dd_profile$severe_max_periods)
  } else if (port_t <= 0 || net_ir <= 0) {
    grade <- "F"
    reasons <- "non-positive alpha (PORT_t<=0 또는 net_IR<=0)"
  } else if (a_core && dsr_ok) {
    grade <- "A"
    # (v9 §3.3) 사유 문자열도 정본을 찍는다 — 문턱이 재보정됐는데 사유가 옛 수치를
    #   그대로 주장하면 감사 기록이 능동적으로 거짓이 된다(단일화의 목적 자체가 무효).
    reasons <- sprintf("Standalone: PORT_t>=%g & OOS_ret %s & Sharpe>=%g & CAGR>=%g%% & Calmar>=%.2f%s%s",
                       .gp$port_t_min,
                       if (identical(oos_band_status, "band_escalated"))
                         sprintf("band[%g,%g) escalated 2/3", band_lo, band_hi)
                       else sprintf(">=%g", band_hi),
                       .gp$sharpe_min, .gp$cagr_min * 100,
                       calmar_min, if (is_sweep) sprintf(" & DSR>=%g(sweep)", .gp$dsr_min) else "",
                       if (isTRUE(dd_profile$tail_review)) " & drawdown_tail_review" else "")
  } else if (port_t >= .gp$b_port_t_min && net_ir > .gp$b_net_ir_min) {
    grade <- "B"
    miss <- c(if (!oos_ok) sprintf("OOS_ret %s<%g(band %s)",
                                   if (is.finite(oos_retention)) sprintf("%.2f", oos_retention) else "NA",
                                   band_hi,
                                   if (is.na(oos_band_status)) "NA" else oos_band_status) else NULL,
              if (!is.finite(sharpe) || sharpe < .gp$sharpe_min) sprintf("Sharpe<%g", .gp$sharpe_min) else NULL,
              if (!is.finite(cagr) || cagr < .gp$cagr_min) sprintf("CAGR<%g%%", .gp$cagr_min * 100) else NULL,
              if (!is.finite(calmar) || calmar < calmar_min) sprintf("Calmar<%.2f", calmar_min) else NULL,
              if (is_sweep && !dsr_ok) sprintf("DSR<%g(sweep)", .gp$dsr_min) else NULL)
    reasons <- paste0("Component: PORT_t>=", .thr1(.gp$b_port_t_min),
                      " & net_IR>", sprintf("%g", .gp$b_net_ir_min), "; A 미달[",
                      if (length(miss)) paste(miss, collapse = ",") else "?", "]")
  } else {
    grade <- "C"
    reasons <- "Ensemble: positive alpha이나 B 미달 (블렌드에서만 가치)"
  }

  .res <- list(
    grade = grade,
    metric_type = if (contract_ok) "backtested" else "uncertain",
    essence = list(
      net_sharpe                 = .rn(sharpe),
      net_ir                     = .rn(net_ir),
      portfolio_alpha_t_nw_lag3  = .rn(port_t),
      oos_retention              = .rn(oos_retention),
      dsr                        = .rn(dsr),
      mdd                        = .rn(mdd),
      calmar                     = .rn(calmar),
      cagr                       = .rn(cagr),
      drawdown_profile           = list(
        severe45_count = dd_profile$severe_count,
        severe55_count = dd_profile$extreme_count,
        severe45_total_periods = dd_profile$severe_total_periods,
        severe45_max_periods = dd_profile$severe_max_periods,
        severe45_period_frac = .rn(dd_profile$severe_period_frac, 4),
        catastrophic_mdd_threshold = dd_profile$catastrophic_threshold,
        severe45_hard_count = dd_profile$severe_hard_count,
        severe55_hard_count = dd_profile$extreme_hard_count,
        severe45_period_hard_frac = .rn(dd_profile$severe_period_hard_frac, 4),
        severe45_max_hard_periods = dd_profile$severe_max_hard_periods,
        tail_review = isTRUE(dd_profile$tail_review),
        structural_hard_fail = isTRUE(dd_profile$structural_hard_fail)
      )
    ),
    hard_fail = hard_fail,
    n_trials_cumulative = n_trials_cumulative,
    selection_type = selection_type,
    dsr_gate_applied = is_sweep,
    oos_stat_version = oos_stat_version,
    oos_retention_splits = round(oos_retention_splits, 3),
    oos_band_status = oos_band_status,
    oos_escalation = esc_detail,
    oos_fail_pattern = if (is.null(oos_fail_pattern)) NA_character_ else as.character(oos_fail_pattern),
    # (v9 §3.3) 이 판정에 **실제로 쓰인** 문턱 집합 — 판정의 사후 감사 가능성을 위해 기록.
    #   mdd_hard/calmar_min 은 형식인자라 호출자 override 를 반영한 값(정본값이 아니라
    #   '쓰인 값')을 담는다. source = 정본 파일 경로 또는 "fallback_literals",
    #   fallback_keys = 정본에서 못 읽어 리터럴로 떨어진 키 목록(빈 문자벡터면 전부 정본).
    graduation_params = list(
      port_t_min   = .gp$port_t_min,
      oos_min      = band_hi,
      oos_floor    = band_lo,
      calmar_min   = calmar_min,
      dsr_min      = .gp$dsr_min,
      mdd_hard     = mdd_hard,
      sharpe_min   = .gp$sharpe_min,
      cagr_min     = .gp$cagr_min,
      b_port_t_min = .gp$b_port_t_min,
      b_net_ir_min = .gp$b_net_ir_min,
      # ★`%||%` 를 쓰지 않는다 — 이 파일은 그것을 정의하지 않고, 호출자 판본을 상속하면
      #   단독 source 시 "could not find function" 으로 죽는다(2026-08-20 실측 계통).
      source        = if (is.null(attr(.gp, "source"))) NA_character_ else attr(.gp, "source"),
      fallback_keys = if (is.null(attr(.gp, "fallback_keys"))) character(0) else attr(.gp, "fallback_keys")
    ),
    reasons = reasons
  )

  # ── AST v1.1 Step 4 사이드카 (SOT §5) — append-only, 채점 무관여, fail-soft ──
  #  2026-08-02 수리: 인라인 writer → 단일 writer ast_sidecar_log() 위임.
  #    구판 결함 3종: (1) 루트 resolver 가 dir.exists() 만 신뢰 (2) try(silent) + 조건부
  #    스킵이라 **기록 실패가 무흔적** (3) lane 개념 부재로 canonical_screen 경로 미포착.
  #    상세 근거 = 02_Infrastructure/contracts/ast_sidecar.R 헤더 주석.
  if (isTRUE(sidecar_log)) {
    try({
      if (!exists("ast_sidecar_log", mode = "function")) {
        # 후보 루트를 marker(CLAUDE.md + 06_Registry)로 검증해 채택 — 존재검사 대체 금지.
        #  sys.frame()$ofile 은 중첩 source 시 바깥 스크립트를 가리켜 신뢰 불가(기지 트랩).
        .cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
                    Sys.getenv("QM_ROOT", unset = ""), getwd())
        for (.c0 in .cands) {
          if (!nzchar(.c0)) next
          .c0 <- gsub("\\\\", "/", .c0)
          if (!(file.exists(file.path(.c0, "CLAUDE.md")) &&
                dir.exists(file.path(.c0, "06_Registry")))) next
          .sc <- file.path(.c0, "02_Infrastructure", "contracts", "ast_sidecar.R")
          if (file.exists(.sc)) { source(.sc); break }
        }
      }
      if (exists("ast_sidecar_log", mode = "function")) {
        .sid <- strategy_id
        if (is.null(.sid)) .sid <- tryCatch(as.character(bt_result$manifest$strategy_id[[1]]),
                                            error = function(e) NA_character_)
        .rid <- tryCatch(as.character(bt_result$manifest$run_id[[1]]),
                         error = function(e) NA_character_)
        ast_sidecar_log(
          lane = "essence",
          strategy_id = .sid,
          ast_features = ast_features,          # NULL = 비-AST 산출 표식(커버리지 절단)
          metrics = list(
            grade = grade,
            metric_type = .res$metric_type,
            port_t = .rn(port_t), oos_retention = .rn(oos_retention),
            dsr = .rn(dsr), calmar = .rn(calmar), net_ir = .rn(net_ir),
            sharpe = .rn(sharpe), cagr = .rn(cagr), mdd = .rn(mdd),
            hard_fail = hard_fail
          ),
          extra = list(
            run_id = if (is.null(.rid) || !length(.rid)) NA_character_ else .rid,
            oos_retention_splits = round(oos_retention_splits, 3),
            selection_type = selection_type,
            n_trials_cumulative = n_trials_cumulative,
            active_regime = active_regime
          )
        )
      }
    }, silent = TRUE)
  }

  .res
}

if (sys.nframe() == 0) cat("[essence_score] Loaded — essence_score(bt_result, n_trials_cumulative, selection_type).\n")
