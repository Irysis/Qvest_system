#!/usr/bin/env Rscript
# method_registry.R — 논문 유래 *가중/위험 method* 어댑터 레지스트리 (도훈 지시 2026-08-08, (b)안).
#
# 왜 있나: paper_router 가 optimizer/risk 로 분류한 논문이 **제목만 기록되고 끝나던** 문제.
#   Σ-가중 A/B 배터리(auto_sigma_weighting_ab.R)는 기계로서는 정확한 형태였는데
#   method 집합 `W_all` 이 2026-06-18 에 하드코딩된 상수라 새 논문이 **낄 자리가 없었다**.
#   → method 집합을 상수에서 **인자**로 바꾸는 것이 (b)안의 전부다.
#
# ★핵심 안전 성질: 어댑터는 "선호 벡터"만 낸다. **제약은 하네스가 건다.**
#   long-only / Σw=1 / w≤UB 는 wrap_adapter() 가 pmax(0)+normalize_long_only 로 *강제*하므로,
#   논문 method 가 아무리 이상해도 Production Constraints 를 깰 수 없다(AX-000 따름정리 — 제약은 고정 축).
#   어댑터가 부호를 반대로 내든 발산하든 결과는 항상 유효 비중이다.
#
# ★선별은 건드리지 않는다: 캐리어(현 PG2)가 종목을 고정하고 method 는 비중만 정한다.
#   그래야 성과 차이가 **가중 규칙 때문**이라고 말할 수 있다(A/B 통제).
#
# 자본 admit 없음 — 본 레지스트리는 *측정 대상*을 늘릴 뿐 채택 권한이 없다(governor 정지).

suppressWarnings(suppressMessages({ library(jsonlite) }))

# ── 프로젝트 루트: CLAUDE_PROJECT_DIR 우선 + **marker 로 정체 검사** (r-portability 금칙 ③④) ──
.mr_root <- function() {
  .marker <- file.path("02_Infrastructure", "methods", "method_registry.R")
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) {
    d <- dirname(normalizePath(f[1], winslash = "/", mustWork = FALSE))
    r <- normalizePath(file.path(d, "..", ".."), winslash = "/", mustWork = FALSE)
    if (file.exists(file.path(r, .marker))) return(r)
  }
  for (k in c("CLAUDE_PROJECT_DIR", "QM_ROOT")) {
    v <- Sys.getenv(k, "")
    if (nzchar(v) && file.exists(file.path(v, .marker))) return(v)
  }
  if (file.exists(.marker)) return(getwd())
  cand <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
  if (file.exists(file.path(cand, .marker))) cand else getwd()
}

METHOD_REGISTRY_PATH <- file.path("06_Registry", "method_registry.json")

#' 어댑터 계약 (한 줄): ctx -> named numeric over ctx$assets. 스케일·부호 자유.
#'
#' ctx 필드:
#'   Sigma         공분산 (assets × assets, PIT: 매수 이전 trailing 만)
#'   R             일별 수익 행렬 (obs × assets, 같은 창)
#'   mu            named numeric — 현 book 알파 score (없을 수 있음)
#'   assets        colnames(Sigma)
#'   ub            상한 (0.20)
#'   lookback_days Σ 추정창 길이
#'   decision_date / eval_date
#' 반환: assets 순서의 numeric. NA/Inf 허용(하네스가 0 으로 처리).

#' 어댑터를 제약-강제 래퍼로 감싼다. ★어댑터는 제약을 지킬 의무가 없다 — 여기서 강제한다.
wrap_adapter <- function(fn, method_id, ub = 0.20) {
  force(fn); force(method_id); force(ub)
  function(ctx) {
    v <- tryCatch(fn(ctx), error = function(e) {
      # ★실패를 조용히 EW 로 내려앉히지 않는다 — 이름을 부르고 EW 폴백임을 남긴다.
      cat(sprintf("[method:%s] 어댑터 실패 → EW 폴백: %s\n", method_id, conditionMessage(e)))
      NULL
    })
    a <- ctx$assets
    if (is.null(v)) return(setNames(rep(1 / length(a), length(a)), a))
    w <- suppressWarnings(as.numeric(v[a]))
    w[!is.finite(w)] <- 0
    w <- pmax(w, 0)
    if (sum(w) <= 1e-12) {
      cat(sprintf("[method:%s] 전량 0/음수 선호 → EW 폴백\n", method_id))
      return(setNames(rep(1 / length(a), length(a)), a))
    }
    names(w) <- a
    # ★스케일 정규화를 **먼저** 한다 (2026-08-08 실측 결함).
    #   normalize_long_only 은 `w[w > ub] <- ub` 를 **정규화 전에** 적용한다(production verbatim).
    #   임의 스케일 선호 벡터(예: 3.8~38.2)를 그대로 넣으면 전 원소가 ub 로 잘려 **동일해지고**,
    #   그 뒤 합-정규화되어 **정확히 EW** 가 된다 — 어댑터는 "돌았는데 아무것도 안 한" 상태가 된다.
    #   실측: minvar 빌트인이 정확히 1/25(0.040000~0.040000)였다. 검사 [3] 의 EW-구별 축이 검거.
    w <- w / sum(w)
    out <- normalize_long_only(w, lb = 0, ub = ub, target_sum = 1)
    # 사후 단언 — 여기서 깨지면 어댑터가 아니라 **하네스 결함**이다(조용히 넘기지 않는다).
    stopifnot(all(is.finite(out)), all(out >= -1e-9), all(out <= ub + 1e-9),
              abs(sum(out) - 1) < 1e-6)
    out
  }
}

#' 레지스트리 로드 → verdict=="implemented" 인 어댑터만 sourcing 해 named list 반환.
#' @param route "optimizer" | "risk" — 해당 라우트 method 만.
#' @param only  선택적 method_id 벡터(그날 큐에 든 논문만 돌릴 때).
#' ★route(논문이 어느 모드 연료인가) 와 adapter_kind(무엇을 교체하는가)는 **다른 축**이다.
#'   2026-08-08 실측: `PreferenceRobustDistortion` 은 paper route=risk 인데 구현은 **비중 어댑터**다
#'   (Σ 를 교체하는 게 아니라 목적함수 자체를 CVaR 로 바꾼다). route 로 로드하면 이 논문은
#'   영원히 안 실린다 — 라우팅 축 혼동이 조용한 드롭을 만드는 전형이다.
#'   그래서 로더는 **kind 로 고른다**. route 는 보고·추적용으로만 남는다.
#'   구 시그니처(route=)는 하위호환으로 받되 kind 로 해석한다.
load_method_adapters <- function(kind = "weight", only = NULL, ub = 0.20, root = .mr_root(),
                                 route = NULL) {
  if (!is.null(route)) kind <- if (identical(route, "risk")) "sigma" else "weight"
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) {
    cat(sprintf("[method_registry] 레지스트리 부재: %s — 등록 method 0건\n", rp))
    return(list())
  }
  reg <- fromJSON(rp, simplifyVector = FALSE)
  ms <- reg$methods
  if (is.null(ms) || length(ms) == 0) return(list())
  out <- list()
  n_skip <- list(verdict = 0L, route = 0L, missing = 0L)
  for (m in ms) {
    # adapter_kind 미선언분은 **기본을 가정하지 않고** 건너뛴다 — 조용한 오분류 방지.
    mk <- m$adapter_kind
    if (is.null(mk)) {
      if (identical(m$verdict, "implemented"))
        cat(sprintf("[method_registry] ★%s: adapter_kind 미선언(implemented) — 로드 생략. 원장에 명시할 것\n", m$method_id))
      n_skip$route <- n_skip$route + 1L; next
    }
    if (!identical(mk, kind)) { n_skip$route <- n_skip$route + 1L; next }
    if (!is.null(only) && !(m$method_id %in% only)) next
    if (!identical(m$verdict, "implemented")) { n_skip$verdict <- n_skip$verdict + 1L; next }
    ap <- file.path(root, m$adapter)
    if (!file.exists(ap)) {
      # ★"구현됨"이라고 등재됐는데 파일이 없다 = 등재가 판정으로 위장한 상태. 이름을 부른다.
      cat(sprintf("[method_registry] ★%s: verdict=implemented 인데 어댑터 파일 부재 (%s) — 건너뜀\n",
                  m$method_id, m$adapter))
      n_skip$missing <- n_skip$missing + 1L; next
    }
    env <- new.env(parent = globalenv())
    ok <- tryCatch({ sys.source(ap, envir = env); TRUE },
                   error = function(e) { cat(sprintf("[method_registry] %s source 실패: %s\n",
                                                     m$method_id, conditionMessage(e))); FALSE })
    if (!ok) next
    fname <- m$entrypoint %||% "method_weights"
    if (!exists(fname, envir = env, inherits = FALSE)) {
      cat(sprintf("[method_registry] ★%s: 진입점 `%s` 부재 — 건너뜀\n", m$method_id, fname)); next
    }
    out[[m$method_id]] <- wrap_adapter(get(fname, envir = env), m$method_id, ub = ub)
  }
  cat(sprintf("[method_registry] route=%s 등록 %d건 로드 (건너뜀: 타route %d · 미구현 %d · 파일부재 %d)\n",
              route, length(out), n_skip$route, n_skip$verdict, n_skip$missing))
  out
}

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

# ══ risk 레인: Σ 추정기 교체 A/B ══════════════════════════════════════════════
# optimizer 레인이 "비중 규칙"을 바꿔 끼운다면, risk 레인은 **위험을 재는 자(Σ)** 를 바꿔 낀다.
# 선별도 비중 규칙도 고정하고 Σ 만 교체 → 차이가 오직 추정기 때문이라고 말할 수 있다.
#
# 계약: sigma_estimate(ctx) -> matrix (assets × assets)
#   ctx = list(R, assets, lookback_days, decision_date, eval_date)   # Sigma 는 주지 않는다(그걸 만드는 게 일)
# ★유효성은 하네스가 강제한다 — 정방/대칭/유한/PD 를 검사하고, 실패하면 **표본공분산 폴백 + 이름 호명**.
#   조용히 폴백하면 "추정기를 갈아끼웠다"가 거짓이 된다(EW 붕괴와 같은 부류).

wrap_sigma_estimator <- function(fn, est_id) {
  force(fn); force(est_id)
  function(ctx) {
    a <- ctx$assets
    fallback <- function(why) {
      cat(sprintf("[sigma_est:%s] %s → 표본공분산 폴백\n", est_id, why))
      S <- stats::cov(ctx$R); dimnames(S) <- list(a, a); S
    }
    S <- tryCatch(fn(ctx), error = function(e) { cat(sprintf("[sigma_est:%s] 예외: %s\n", est_id, conditionMessage(e))); NULL })
    if (is.null(S)) return(fallback("NULL/예외"))
    if (!is.matrix(S) || nrow(S) != length(a) || ncol(S) != length(a)) return(fallback("차원 불일치"))
    if (!all(is.finite(S))) return(fallback("비유한 원소"))
    S <- (S + t(S)) / 2                                     # 대칭화(수치오차 흡수)
    dimnames(S) <- list(a, a)
    # ★분산 검사를 PD jitter **앞에** 둔다 (2026-08-08 검사기 검거).
    #   구 순서(jitter 먼저)에서는 대각이 0 인 퇴화 Σ 가 jitter 로 덧칠돼 대각>0 이 되어
    #   폴백도 호명도 없이 통과했다 — **망가진 추정기가 쓸만해 보이는 Σ 를 내는** 상태.
    #   jitter 는 미세 수치 비-PD 를 흡수하는 장치이지 퇴화 추정치를 되살리는 장치가 아니다.
    if (any(!is.finite(diag(S))) || any(diag(S) <= 0)) return(fallback("비양수 분산(퇴화 추정)"))
    ev <- tryCatch(min(eigen(S, symmetric = TRUE, only.values = TRUE)$values), error = function(e) NA_real_)
    if (is.na(ev)) return(fallback("고유값 계산 실패"))
    # 음 고유값이 대각 규모에 비해 크면 jitter 로 덮을 문제가 아니다 → 폴백.
    if (ev <= 0 && abs(ev) > 0.10 * mean(diag(S))) return(fallback(sprintf("심한 비-PD (min eig %.3g)", ev)))
    if (ev <= 0) S <- S + diag(abs(ev) + 1e-10, length(a))  # 미세 비-PD 만 보정(폴백 아님)
    S
  }
}

#' risk 레지스트리 로드 → est_id -> wrapped estimator.
load_sigma_estimators <- function(only = NULL, root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(list())
  reg <- fromJSON(rp, simplifyVector = FALSE)
  out <- list()
  # ★route 가 아니라 adapter_kind 로 고른다 (위 load_method_adapters 주석 참조).
  for (m in Filter(function(x) identical(x$adapter_kind, "sigma"), reg$methods %||% list())) {
    if (!is.null(only) && !(m$method_id %in% only)) next
    if (!identical(m$verdict, "implemented")) next
    ap <- file.path(root, m$adapter %||% "")
    if (!nzchar(m$adapter %||% "") || !file.exists(ap)) {
      cat(sprintf("[method_registry] ★%s: verdict=implemented 인데 어댑터 부재 — 건너뜀\n", m$method_id)); next
    }
    env <- new.env(parent = globalenv())
    ok <- tryCatch({ sys.source(ap, envir = env); TRUE },
                   error = function(e) { cat(sprintf("[method_registry] %s source 실패: %s\n", m$method_id, conditionMessage(e))); FALSE })
    if (!ok) next
    fname <- m$entrypoint %||% "sigma_estimate"
    if (!exists(fname, envir = env, inherits = FALSE)) {
      cat(sprintf("[method_registry] ★%s: 진입점 `%s` 부재 — 건너뜀\n", m$method_id, fname)); next
    }
    out[[m$method_id]] <- wrap_sigma_estimator(get(fname, envir = env), m$method_id)
  }
  cat(sprintf("[method_registry] route=risk 추정기 %d건 로드\n", length(out)))
  out
}

# ══ regime 레인: 오버레이 노출 스케줄 교체 A/B ═══════════════════════════════
# optimizer 레인이 "비중 규칙", risk 레인이 "위험을 재는 자(Σ)"를 바꿔 낀다면,
# regime 레인은 **얼마나 태울지(exposure 스칼라)** 를 바꿔 낀다. 선별·비중은 전부 고정.
#
# 계약: exposure_schedule(ctx) -> list(exposure = data.table(Date, exposure), used_cutoff = Date[])
#   ctx = list(periods = data.table(decision_date, eval_date), bare_gross = data.table(Date, r))
#   Date = eval_date 그리드. exposure ∈ [0, 1] (long-only · 무레버리지 — Production Constraints).
#
# ★★`used_cutoff` 는 **선택 항목이 아니다**. 2026-07-06 BearProb 실사고 = 오버레이가 홀딩월 *말*
#   정보로 그 홀딩월을 스케일한 ~1개월 동월 look-ahead 였고, placebo/OOS/DSR/subperiod 를 전부
#   통과했다(판별한 건 lag1 스트레스와 strict-PIT A/B 뿐). 그래서 어댑터가 자기 컷오프를
#   **신고하지 않으면 로드를 거부한다** — 신고 없음을 "아마 괜찮음"으로 내려앉히지 않는다.
#   (부재를 정상값으로 읽는 것이 이 저장소의 반복 결함이다.)
wrap_exposure_adapter <- function(fn, method_id) {
  force(fn); force(method_id)
  function(ctx) {
    hold_start <- as.Date(format(as.Date(ctx$periods$decision_date), "%Y-%m-01"))
    out <- tryCatch(fn(ctx), error = function(e) {
      cat(sprintf("[exposure_adapter:%s] 예외: %s → 제외\n", method_id, conditionMessage(e))); NULL })
    if (is.null(out)) return(NULL)
    if (!is.list(out) || is.null(out$exposure) || is.null(out$used_cutoff)) {
      cat(sprintf("[exposure_adapter:%s] ★계약 위반 — exposure/used_cutoff 둘 다 필요. PIT 미신고는 로드 거부\n", method_id))
      return(NULL)
    }
    e <- as.data.table(out$exposure)
    if (!all(c("Date", "exposure") %in% names(e))) {
      cat(sprintf("[exposure_adapter:%s] ★컬럼 결손(Date/exposure) — 제외\n", method_id)); return(NULL) }
    e[, Date := as.Date(Date)]; e[, exposure := as.numeric(exposure)]
    if (any(!is.finite(e$exposure))) {
      cat(sprintf("[exposure_adapter:%s] ★비유한 노출 — 제외\n", method_id)); return(NULL) }
    if (any(e$exposure < 0) || any(e$exposure > 1)) {
      # ★clip 으로 조용히 살려내지 않는다 — 제약을 어긴 어댑터를 통과시키면 "무엇을 쟀나"가 흐려진다.
      cat(sprintf("[exposure_adapter:%s] ★노출이 [0,1] 밖 (min %.3f max %.3f) — long-only 무레버리지 위반, 제외\n",
                  method_id, min(e$exposure), max(e$exposure))); return(NULL) }
    uc <- as.Date(out$used_cutoff)
    if (length(uc) != length(hold_start)) {
      # 스칼라 신고는 최댓값으로 해석(가장 늦은 컷오프 = 가장 보수적)
      if (length(uc) == 1L) uc <- rep(uc, length(hold_start))
      else { cat(sprintf("[exposure_adapter:%s] ★used_cutoff 길이 불일치(%d vs %d) — 제외\n",
                         method_id, length(uc), length(hold_start))); return(NULL) }
    }
    viol <- sum(uc >= hold_start, na.rm = TRUE)
    if (viol > 0) {
      cat(sprintf("[exposure_adapter:%s] ★C5 위반 — 신호 컷오프가 홀딩월 시작 이후인 기간 %d개월. 제외(pit.md C5)\n",
                  method_id, viol)); return(NULL) }
    cat(sprintf("[exposure_adapter:%s] OK — %d개월 · 평균 노출 %.4f · 홀딩월까지 최소 간격 %.0f일\n",
                method_id, nrow(e), mean(e$exposure), min(as.numeric(hold_start - uc))))
    e[, .(Date, exposure)]
  }
}

#' regime 레지스트리 로드 → method_id -> wrapped exposure schedule builder.
#' ★현재 `06_Registry/method_registry.json` 의 regime route 항목은 0건이다. 그 사실은
#'   소비단이 **이름 붙여 보고**한다("등재 0건") — 0 을 조용한 통과로 두지 않는다.
load_exposure_adapters <- function(only = NULL, root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(list())
  reg <- fromJSON(rp, simplifyVector = FALSE)
  out <- list()
  for (m in Filter(function(x) identical(x$adapter_kind, "exposure"), reg$methods %||% list())) {
    if (!is.null(only) && !(m$method_id %in% only)) next
    if (!identical(m$verdict, "implemented")) next
    ap <- file.path(root, m$adapter %||% "")
    if (!nzchar(m$adapter %||% "") || !file.exists(ap)) {
      cat(sprintf("[method_registry] ★%s: verdict=implemented 인데 어댑터 부재 — 건너뜀\n", m$method_id)); next
    }
    env <- new.env(parent = globalenv())
    ok <- tryCatch({ sys.source(ap, envir = env); TRUE },
                   error = function(e) { cat(sprintf("[method_registry] %s source 실패: %s\n",
                                                     m$method_id, conditionMessage(e))); FALSE })
    if (!ok) next
    fname <- m$entrypoint %||% "exposure_schedule"
    if (!exists(fname, envir = env, inherits = FALSE)) {
      cat(sprintf("[method_registry] ★%s: 진입점 `%s` 부재 — 건너뜀\n", m$method_id, fname)); next
    }
    out[[m$method_id]] <- wrap_exposure_adapter(get(fname, envir = env), m$method_id)
  }
  cat(sprintf("[method_registry] route=regime 노출 어댑터 %d건 로드\n", length(out)))
  out
}

#' risk 레인 arm ↔ 정합 대조군 지도 (2026-08-09 신설).
#'
#' 왜 있나: **측정됐다 ≠ 판정됐다.** 2026-08-09 실측 — `ProperScoreGASFilter`·
#'   `PreferenceRobustDistortion` 두 건이 Σ-A/B 배터리에 실제로 합류해
#'   `h1b_sigma_ab_overlay.csv` 에 IR 0.920 / 0.658 이 찍혔는데, `research_status_20260809.json`
#'   의 risk 블록은 `harness_status="… 하네스 미배선"` · `action="자동 측정 아직 없음"` 이라는
#'   **하드코딩 문자열로 자기 실측을 부정**했다. 등재≠처분 계통의 반대 방향 판본이다
#'   (이번엔 산출물이 자기 측정을 과소보고). 상태 문자열은 선언이 아니라 실측에서 파생해야 한다.
#'
#' ★대조군은 "무엇이 달라졌나"의 축으로 정한다 — 여기서만 Δ 가 추정기/비중 탓이라고 말할 수 있다:
#'   - adapter_kind=sigma  → arm `minvar@<id>` vs **`minvar_lw`**: 비중 규칙(minvar) 고정, Σ 만 교체.
#'       ★대조군 Σ 는 Ledoit-Wolf 다. "표본 Σ 대비"가 아니므로 라벨에 박아 둔다.
#'   - adapter_kind=weight → arm `<id>` vs **`strategy`**(현 book): 비중 규칙 자체를 바꾸므로
#'       optimizer 레인과 동일한 book-marginal 컨벤션으로 잰다.
#' ★반환 Δ 는 **대조 진단량이지 자본 admission 게이트가 아니다**(§4 book-marginal 은 governor 수동).
risk_lane_arms <- function(root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(list())
  reg <- fromJSON(rp, simplifyVector = FALSE)
  ms <- Filter(function(m) identical(m$route, "risk") && identical(m$verdict, "implemented"),
               reg$methods %||% list())
  lapply(ms, function(m) {
    kind <- m$adapter_kind %||% "weight"
    if (identical(kind, "sigma")) {
      list(method_id = m$method_id, paper_id = m$paper_id %||% NA_character_, adapter_kind = kind,
           arm = paste0("minvar@", m$method_id), control = "minvar_lw",
           control_basis = "비중 규칙(minvar) 고정 · Σ 만 교체 → Δ = 추정기 효과. 대조군 Σ = Ledoit-Wolf")
    } else {
      list(method_id = m$method_id, paper_id = m$paper_id %||% NA_character_, adapter_kind = kind,
           arm = m$method_id, control = "strategy",
           control_basis = "비중 규칙 교체 → 현 book 대비 book-marginal (optimizer 레인과 동일 컨벤션)")
    }
  })
}

#' 라우트별 triage 요약 — "등재됐다"가 아니라 "무슨 처분을 받았나"를 낸다.
#' ★원장 등재(존재)를 판정(처분)으로 읽는 사고가 반복돼 왔다([[project-screen-route-consumer-zero-20260802]]).
#'   그래서 보고에는 항상 verdict 와 blocker 를 함께 싣는다.
method_triage <- function(route, root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(list())
  reg <- fromJSON(rp, simplifyVector = FALSE)
  ms <- Filter(function(m) identical(m$route, route), reg$methods %||% list())
  lapply(ms, function(m) list(
    method_id = m$method_id, paper_id = m$paper_id, verdict = m$verdict,
    blocker = m$blocker %||% (m$note %||% NA_character_),
    unblock_requirement = m$unblock_requirement %||% NA_character_))
}

#' triage 를 사람이 읽는 한 줄로.
method_triage_line <- function(route, root = .mr_root()) {
  tri <- method_triage(route, root)
  if (!length(tri)) return(sprintf("%s: 등록 method 0건", route))
  vs <- vapply(tri, function(x) as.character(x$verdict), character(1))
  paste0(sprintf("%s method %d건 — ", route, length(tri)),
         paste(sprintf("%s(%s)", vapply(tri, function(x) x$method_id, character(1)), vs), collapse = ", "))
}

#' 신규성 점검 — factor DB 중복 사고(approved 102에 EXACT 10~12쌍)의 method 판.
#' 지금은 registry 의 `similar_to` 선언을 보고 경고만 한다. 등재 시 사람이 채운다.
method_novelty_warn <- function(root = .mr_root()) {
  rp <- file.path(root, METHOD_REGISTRY_PATH)
  if (!file.exists(rp)) return(invisible(NULL))
  reg <- fromJSON(rp, simplifyVector = FALSE)
  for (m in reg$methods) {
    st <- m$similar_to
    if (!is.null(st) && length(st) > 0)
      cat(sprintf("[method_registry] ⚠신규성: %s 는 기존 %s 와 유사 선언 — 중복 여부 확인 필요\n",
                  m$method_id, paste(unlist(st), collapse = ", ")))
  }
  invisible(NULL)
}
