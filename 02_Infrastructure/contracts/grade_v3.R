#==============================================================================
# grade_v3.R — 등급 v3 진단 계약 (MC7 · S0 진단 모드 · v10.01 2026-10-13)
#
# 왜: 도훈 투자철학(10-13) "남들 다 깨질 때 덜 잃고 복리로 이긴다"를 등급에 싣는다.
#   현행 essence 는 5조건 AND 라 PORT_t 2.95 미달이면 Calmar 가 아무리 좋아도 A 불가였다.
#   v3 = 종합점수 S(Calmar 6 : PORT_t 4 가중 기하평균) + 하한 + 위기 복원력(CR) 노치 + τ_D 단일 분할 OOS.
#   설계 정본 = 04_Research/01_reports/l1_prescription_redesign_20261013/README.md §2 · §3.5 · §7.2
#
# ★권위 등급이다(설정 mode = authoritative · 2026-10-13 MC7 승격 · decision_register GRADE-V3-PROMOTE).
#   essence_score.R 이 gv3_score_bt() 로 이 계약을 불러 essence_grade 를 낸다(구 5조건 판정 = grade_v921 · 진단).
#   규칙(GRADE-V3-S0-BANDS): B 경계 = S(같은 창 벤치 Calmar, 현행 B PORT_t) · C = 0 < S < B · F = S = 0 ·
#   롤링 통과율 문턱 확정 · 롤링 구제 미탑재 · CR '강함'은 자기 낙폭 조건 포함(behavior_card.R) · 벤치 = 공표 KOSPI200.
#   디렉터리판(gv3_score_dir)은 소급·진단용으로 같은 채점을 산출물 디렉터리에서 한다(두 경로 결과 동일 — 검사 E1).
#
# 숫자의 출처 (새 숫자 없음):
#   A·B 문턱 = constraint_defaults.json::tier_graduation (essence_score.R::.graduation_params 로 읽는다)
#   가중·노치·OOS 구성 = 06_Registry/grade_v3.json (도훈 결정 D1 형태 · D2 · D4 · D5)
#   τ_D · CR 판정 · CDaR = 06_Registry/behavior_card.json → behavior_card.R
#   롤링 36M = 06_Registry/rolling_grade.json → rolling_grade.R
#   지표 계산 = backtest_result_contract.R::build_metrics · build_benchmark_compare (essence 와 같은 함수)
#
# 공개: gv3_cfg · gv3_thresholds · gv3_ctx · gv3_S · gv3_window · gv3_decide · gv3_score_dir · gv3_score_bt · gv3_row · gv3_bench_history
# 검사: 08_Tests/contracts/test_grade_v3.R
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })

.gv3_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# 루트 = 호출자 명시 → CLAUDE_PROJECT_DIR → QM_ROOT → getwd. 정체성 표식(CLAUDE.md + 06_Registry)으로 검증한다.
.gv3_root <- function(root = NULL) {
  for (p in c(root, Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())) {
    if (is.null(p) || !nzchar(p)) next
    p <- gsub("\\\\", "/", p)
    if (file.exists(file.path(p, "CLAUDE.md")) && dir.exists(file.path(p, "06_Registry"))) return(p)
  }
  stop("[grade_v3] 프로젝트 루트 해석 실패")
}

# 의존 계약을 사적 환경에 한 번 싣는다 — 전역을 더럽히지 않고, 같은 루트면 재사용한다.
.GV3 <- new.env(parent = emptyenv())
.gv3_deps <- function(root) {
  if (isTRUE(.GV3$loaded) && identical(.GV3$root, root)) return(invisible(.GV3$e))
  e <- new.env(parent = globalenv())
  for (f in c("backtest_result_contract.R", "essence_score.R", "rolling_grade.R", "behavior_card.R")) {
    p <- file.path(root, "02_Infrastructure/contracts", f)
    if (!file.exists(p)) stop("[grade_v3] 의존 계약 없음: ", p)
    invisible(utils::capture.output(suppressMessages(sys.source(p, envir = e, keep.source = FALSE))))   # 적재 안내 cat 억제
  }
  .GV3$e <- e; .GV3$root <- root; .GV3$loaded <- TRUE
  invisible(e)
}

#' 설정 정본 — 필수 키가 없으면 멈춘다(기본값을 지어내지 않는다)
gv3_cfg <- function(root = NULL, path = NULL) {
  p <- .gv3_or(path, file.path(.gv3_root(root), "06_Registry/grade_v3.json"))
  cfg <- tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(cfg)) stop("[grade_v3] 설정 판독 불가: ", p)
  need <- c("mode", "weights", "a_boundary", "b_boundary", "c_boundary", "floors", "cr_notch", "oos")
  miss <- setdiff(need, names(cfg))
  if (length(miss)) stop("[grade_v3] 설정 키 누락: ", paste(miss, collapse = ","))
  w <- cfg$weights
  if (!is.numeric(w$calmar) || !is.numeric(w$port_t) || w$calmar <= 0 || w$port_t <= 0 ||
      abs(w$calmar + w$port_t - 1) > 1e-9)
    stop("[grade_v3] weights 는 양수이고 합이 1 이어야 한다 (calmar=", w$calmar, " port_t=", w$port_t, ")")
  if (!is.numeric(cfg$a_boundary) || !is.finite(cfg$a_boundary)) stop("[grade_v3] a_boundary 비수치")
  # B·C 경계 어휘(GRADE-V3-S0-BANDS) — 모르는 규칙이면 멈춘다(경계를 지어내지 않는다)
  if (!identical(cfg$b_boundary$rule, "S_at_corner") || !identical(cfg$b_boundary$calmar, "same_window_benchmark_calmar") ||
      !identical(cfg$b_boundary$port_t, "tier_graduation.grade_b_min_portfolio_alpha_t"))
    stop("[grade_v3] b_boundary 규칙 어휘 밖 — 기대 S_at_corner(same_window_benchmark_calmar · grade_b_min_portfolio_alpha_t)")
  if (!identical(cfg$c_boundary$rule, "S_gt_zero")) stop("[grade_v3] c_boundary 규칙 어휘 밖 — 기대 S_gt_zero")
  sr <- .gv3_or(cfg$cr_notch$strong_requires, "none")
  if (!sr %in% c("none", "mc8_selection_defense", "mc8_selection_or_timing_evidence"))
    stop("[grade_v3] cr_notch.strong_requires 어휘 밖: ", sr, " (none | mc8_selection_defense | mc8_selection_or_timing_evidence)")
  te <- cfg$cr_notch[["timing_evidence"]]                                   # [[ ]] = 정확 일치($ 는 timing_unit 등 앞부분 일치로 새는 값을 집는다)
  if (identical(sr, "mc8_selection_or_timing_evidence") && !(is.character(te) && length(te) == 1L && nzchar(te)))
    stop("[grade_v3] strong_requires = mc8_selection_or_timing_evidence 는 cr_notch.timing_evidence(증거 등록부 경로)를 요구한다")
  tu <- cfg$cr_notch[["timing_unit"]]
  if (identical(sr, "mc8_selection_or_timing_evidence") && !(is.character(tu) && length(tu) == 1L && tu %in% GV3_TIMING_UNITS))
    stop("[grade_v3] cr_notch.timing_unit 어휘 밖(", paste(GV3_TIMING_UNITS, collapse = " | "), ") — 증거 셈 단위(GRADE-V32-TIMING-EVENT-UNIT)")
  cfg
}

#' CR '강함' 상향 노치의 MC8 조건(decision_register GRADE-V3-CR-STRONG-SELECTION · 도훈 10-13 · MC8 보고서 §7)
#'   설정 cr_notch.strong_requires = "mc8_selection_defense" 면 '강함'은 MC8 귀속(전체 창)이 선택(기전) 방어일 때만 강함으로 쓰고
#'   아니면(크기 방어 · 노출 방어 · 방어 없음 · 판정 불가 · 대조 불가 · 오류) 보통으로 낮춘다 — 크기 방어 착시(헌장 §7.3)로 상향하지 않는다.
#'   약함 · 보통 · 판정 불가는 그대로다(하향 노치는 대조와 무관).
#'   ★v3.2(10-18 · 헌장 §5 빈칸 9 A′ · decision_register CHARTER-GAPS-3-20261017): strong_requires = "mc8_selection_or_timing_evidence" 면
#'   MC8 selection_defense 를 선택 / 타이밍으로 가른다 — MC8 판정 플라시보는 평균 노출만 맞추므로 위기 타이밍(시변 노출)도 selection_defense 가 된다.
#'   선택 = 노출 경로가 고정이거나(타이밍 성분 없음) 노출 경로까지 맞춘 짝(size_exposure_path)을 과반에서 이김 → 강함.
#'   타이밍 = 경로 짝은 못 이김 → 타이밍 방어 증거 기록((a) 같은 β 현금 사본을 깊은 위기 · 빠른 급락 과반에서 이김 (b) 두 엔진 확인
#'   (c) 느린 약세 개선이 한 달 지연에서도 유지 — 라운드 평가가 남긴다)이 있을 때만 강함. 경로 짝을 못 쟀으면 보통(fail-closed).
#' @param mc8 MC8 결과 list(label · exposure_varies · share_beats_size_exposure_path · majority_share) 또는 라벨 문자열(구 호출 — v3.2 에서는 타이밍 미해소)
#' @param evidence 타이밍 방어 증거 기록 1건(gv3_timing_evidence 의 entry) 또는 NULL
gv3_cr_for_notch <- function(cr, mc8, cfg, evidence = NULL) {
  req <- .gv3_or(cfg$cr_notch$strong_requires, "none")
  if (!identical(cr, "strong") || identical(req, "none")) return(cr)
  lab <- if (is.list(mc8)) .gv3_or(mc8$label, NA_character_) else as.character(.gv3_or(mc8, NA_character_))[1]
  if (identical(req, "mc8_selection_defense")) return(if (identical(lab, "selection_defense")) "strong" else "normal")
  if (identical(req, "mc8_selection_or_timing_evidence"))
    return(if (gv3_notch_basis(mc8, evidence, cfg$cr_notch[["timing_unit"]]) %in% c("selection", "timing_evidence")) "strong" else "normal")
  stop("[grade_v3] cr_notch.strong_requires 어휘 밖: ", req)
}

#' v3.2 노치 근거 — not_selection | selection | timing_evidence | timing_no_evidence | timing_unresolved
gv3_notch_basis <- function(mc8, evidence = NULL, unit = NULL) {
  lab <- if (is.list(mc8)) .gv3_or(mc8$label, NA_character_) else as.character(.gv3_or(mc8, NA_character_))[1]
  if (!identical(lab, "selection_defense")) return("not_selection")
  if (!is.list(mc8)) return("timing_unresolved")                     # 라벨만으로는 경로 짝을 모른다
  varies <- mc8$exposure_varies
  if (identical(varies, FALSE)) return("selection")                  # 노출 경로 고정 — 타이밍 성분이 없다
  sp  <- suppressWarnings(as.numeric(.gv3_or(mc8$share_beats_size_exposure_path, NA_real_))[1])
  maj <- suppressWarnings(as.numeric(.gv3_or(mc8$majority_share, NA_real_))[1])
  if (!isTRUE(varies) || !is.finite(sp) || !is.finite(maj)) return("timing_unresolved")
  if (sp > maj) return("selection")                                  # 노출 경로까지 맞춘 짝을 과반에서 이김
  if (isTRUE(gv3_timing_evidence_ok(evidence, unit))) "timing_evidence" else "timing_no_evidence"
}

#' 타이밍 방어 증거 기록 1건이 A′ (a)(b)(c) 를 모두 충족하나 — 플래그는 라운드 평가(사전등록 판정)가 쓴다
GV3_TIMING_FLAGS <- c("a_deep_beta_majority", "a_fast_beta_majority", "b_both_engines", "c_slow_lag1_retained")
#   셈 단위(decision_register GRADE-V32-TIMING-EVENT-UNIT-20261018 · 도훈 10-18 = lt): lt = Lunde-Timmermann 위기 수 · episode = 독립 상태 일화 ·
#   both = 두 판 모두 통과. 설정 단위(cr_notch.timing_unit)와 기록 단위가 같아야 가점(다른 단위로 센 기록 = 가점 없음).
GV3_TIMING_UNITS <- c("lt", "episode", "both")
gv3_timing_evidence_ok <- function(evidence, unit = NULL) {
  if (!is.list(evidence) || !length(evidence)) return(FALSE)
  if (!is.null(unit) && !identical(as.character(.gv3_or(evidence$unit, NA_character_))[1], as.character(unit)[1])) return(FALSE)
  all(vapply(GV3_TIMING_FLAGS, function(k) isTRUE(evidence[[k]]), logical(1)))
}

#' 증거 등록부에서 이 전략의 기록을 찾는다(strategy_id 우선 · 없으면 산출물 디렉터리) — 없거나 못 읽으면 NULL(fail-closed)
gv3_timing_evidence <- function(cfg, strategy_id = NA_character_, dir = NA_character_, root = NULL) {
  p <- .gv3_or(cfg$cr_notch[["timing_evidence"]], NA_character_)
  if (is.na(p) || !nzchar(p)) return(NULL)
  p <- gsub("\\\\", "/", p)                                                 # Windows 역슬래시 경로(tempdir 등)를 슬래시로
  f <- if (grepl("^([A-Za-z]:)?/", p)) p else file.path(.gv3_root(root), p)
  if (!file.exists(f)) return(NULL)
  reg <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  ent <- if (is.list(reg)) reg$entries else NULL
  if (!length(ent)) return(NULL)
  rt <- paste0(.gv3_root(root), "/")
  rel <- function(d) { d <- gsub("\\\\", "/", as.character(d)); if (startsWith(d, rt)) substring(d, nchar(rt) + 1L) else d }
  sid <- as.character(.gv3_or(strategy_id, NA_character_))[1]
  hit <- Filter(function(z) (!is.na(sid) && nzchar(sid) && identical(as.character(.gv3_or(z$strategy_id, "")), sid)) ||
                  (!is.na(dir) && nzchar(as.character(dir)) && identical(rel(.gv3_or(z$dir, "")), rel(dir))), ent)
  if (length(hit)) hit[[length(hit)]] else NULL
}

#' 증거 기록 쓰기(라운드 평가 전용 writer) — 같은 (strategy_id, round_id) 는 교체 · 원자적 쓰기 · 플래그 4종과 출처 필수
gv3_timing_evidence_add <- function(entry, cfg, root = NULL) {
  need <- c("strategy_id", "dir", "round_id", "prereg_md5", "unit", GV3_TIMING_FLAGS)
  miss <- setdiff(need, names(entry))
  if (length(miss)) stop("[grade_v3] 타이밍 증거 기록 필드 누락: ", paste(miss, collapse = ","))
  if (!all(vapply(GV3_TIMING_FLAGS, function(k) is.logical(entry[[k]]) && length(entry[[k]]) == 1L && !is.na(entry[[k]]), logical(1))))
    stop("[grade_v3] 타이밍 증거 플래그는 TRUE/FALSE 하나씩이어야 한다")
  if (!(is.character(entry$unit) && length(entry$unit) == 1L && entry$unit %in% GV3_TIMING_UNITS))
    stop("[grade_v3] 타이밍 증거 unit 어휘 밖(", paste(GV3_TIMING_UNITS, collapse = " | "), ")")
  p <- .gv3_or(cfg$cr_notch[["timing_evidence"]], NA_character_)
  if (is.na(p) || !nzchar(p)) stop("[grade_v3] cr_notch.timing_evidence 경로가 설정에 없다")
  p <- gsub("\\\\", "/", p)                                                 # Windows 역슬래시 경로(tempdir 등)를 슬래시로
  f <- if (grepl("^([A-Za-z]:)?/", p)) p else file.path(.gv3_root(root), p)
  reg <- if (file.exists(f)) fromJSON(f, simplifyVector = FALSE) else list(schema = "timing_defense_evidence_v1", entries = list())
  keep <- Filter(function(z) !(identical(as.character(z$strategy_id), as.character(entry$strategy_id)) &&
                                 identical(as.character(z$round_id), as.character(entry$round_id))), .gv3_or(reg$entries, list()))
  entry$recorded_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  reg$entries <- c(keep, list(entry))
  tmp <- paste0(f, ".tmp", Sys.getpid())
  writeLines(toJSON(reg, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), tmp, useBytes = TRUE)
  if (!file.rename(tmp, f)) { unlink(tmp); stop("[grade_v3] 증거 등록부 쓰기 실패: ", f) }
  invisible(f)
}

# MC8 계약(matched_controls.R)을 사적 환경에 싣는다 — 행동 카드 계약은 .gv3_deps 환경 것을 넘긴다
.gv3_mc_env <- function(root) {
  if (isTRUE(.GV3$mc_loaded) && identical(.GV3$mc_root, root)) return(.GV3$mc_e)
  m <- new.env(parent = globalenv())
  p <- file.path(root, "02_Infrastructure/contracts/matched_controls.R")
  if (!file.exists(p)) stop("[grade_v3] matched_controls.R 없음: ", p)
  invisible(utils::capture.output(suppressMessages(sys.source(p, envir = m, keep.source = FALSE))))
  .GV3$mc_e <- m; .GV3$mc_root <- root; .GV3$mc_loaded <- TRUE
  m
}

# MC8 대조용 RAWDATA — 측정 프로세스 메모리에 RAWDATA 가 있으면 그것(측정과 같은 판본), 없으면 파일에서 한 번 읽어 재사용(지문으로 무효화)
.gv3_mc_raw <- function(root, m, universe = NULL) {
  hyg <- identical(universe, "ALL_HYG")       # 측정 축 ALL_HYG(MC1) — 대조 유니버스에 위생 멤버십이 필요하다
  g <- if (exists("RAWDATA", envir = globalenv(), inherits = FALSE)) get("RAWDATA", envir = globalenv()) else NULL
  if (is.data.frame(g) && all(c("Date", "Ticker", "K200", "KQ150", "Size", "Ret") %in% names(g)) &&
      (!hyg || "K200_IDX" %in% names(g)))     # ALL_HYG 면 측정 축이 주입된 프로세스 RAWDATA 만 같은 판본으로 쓴다
    return(list(raw = data.table::as.data.table(g), source = "process_RAWDATA"))
  p <- file.path(root, ".cache/RAWDATA.parquet"); fi <- file.info(p)
  fp <- paste(fi$size, format(fi$mtime, "%Y-%m-%dT%H:%M:%OS3"), if (hyg) "hyg" else "base")
  slot <- if (hyg) "mc_raw_hyg" else "mc_raw"; fslot <- paste0(slot, "_fp")
  if (!identical(.GV3[[fslot]], fp)) {
    .GV3[[slot]] <- m$mc_load_raw(root, from = "2000-01-01", hygiene = hyg)
    .GV3[[fslot]] <- fp
  }
  list(raw = .GV3[[slot]], source = paste("RAWDATA.parquet", fp))
}

# 채점 입력의 보유 · 집행 규약 · 유니버스(디렉터리판 = 산출물 파일 · bt 판 = bt_result 구성 요소)
.gv3_mc_inputs <- function(X) {
  if (!is.null(X$H)) return(X)
  d <- X$dir
  if (is.null(d) || is.na(d) || !file.exists(file.path(d, "04_holdings.csv"))) return(X)
  X$H <- data.table::fread(file.path(d, "04_holdings.csv"), colClasses = list(character = "ticker"))
  rj <- function(n) { p <- file.path(d, n); if (file.exists(p)) tryCatch(fromJSON(p, simplifyVector = TRUE), error = function(e) list()) else list() }
  sp <- rj("01_strategy_spec.json"); mn <- rj("00_manifest.json")
  X$spec <- list(exec_price = sp[["exec_price"]], universe = .gv3_or(sp[["universe"]], mn[["universe_id"]]))
  X
}

# MC8 귀속(전체 창) — CR '강함' 일 때만 부른다(그 밖은 노치에 쓰이지 않는다)
.gv3_mc8 <- function(X, card, ctx, root, e) {
  X <- .gv3_mc_inputs(X)
  if (is.null(X$H) || !NROW(X$H)) return(list(status = "no_holdings", label = NA_character_))
  m <- .gv3_mc_env(root)
  uni <- as.character(.gv3_or(X$spec$universe, NA_character_))[1]
  if (is.na(uni) || !nzchar(uni)) return(list(status = "no_universe", label = NA_character_))
  H <- data.table::as.data.table(X$H)[, .(date = as.Date(date), ticker = as.character(ticker), target_weight = as.numeric(target_weight))]
  ep <- m$.mc_exec_price(list(exec_price = X$spec$exec_price), X$pr$date, H$date)
  rw <- .gv3_mc_raw(root, m, uni)
  ctl <- m$mc_controls(H, X$pr, X$br, rw$raw, m$mc_cfg(root), ep$value, uni)
  k <- m$mc_attribution(card, ctl, X$br[, .(date, benchmark_ret)], ctx$bc_cfg, e)
  a <- k$controls$attribution$overall
  list(status = .gv3_or(k$controls$status, ctl$status), label = .gv3_or(a$label, NA_character_),
       share_beats_size_exposure = .gv3_or(a$share_beats_size_exposure, NA_real_),
       share_beats_exposure = .gv3_or(a$share_beats_exposure, NA_real_), share_beats_bench = .gv3_or(a$share_beats_bench, NA_real_),
       median_placebo_p = .gv3_or(a$median_placebo_p, NA_real_),
       # v3.2 선택 / 타이밍 구분 입력(헌장 빈칸 9 A′) — 노출 경로가 변할 때만 경로 짝이 있다
       exposure_varies = .gv3_or(k$controls$exposure_profile$varies, NA),
       share_beats_size_exposure_path = .gv3_or(a$share_beats_size_exposure_path, NA_real_),
       majority_share = .gv3_or(k$controls$attribution$majority_share, NA_real_),
       exec_price = ep$value, universe = uni, raw_source = rw$source)
}

#' A·B 문턱 — essence 와 같은 로더로 tier_graduation 정본을 읽는다. 정본 미해소(리터럴 폴백)면 멈춘다.
gv3_thresholds <- function(root = NULL) {
  root <- .gv3_root(root); e <- .gv3_deps(root)
  gp <- e$.graduation_params(refresh = TRUE, root = root)
  fb <- attr(gp, "fallback_keys")
  if (length(fb)) stop("[grade_v3] tier_graduation 정본 키 미해소(폴백 거부): ", paste(fb, collapse = ","))
  list(calmar_a = gp$calmar_min, port_t_a = gp$port_t_min, port_t_b = gp$b_port_t_min,
       cagr_min = gp$cagr_min, sharpe_min = gp$sharpe_min, source = attr(gp, "source"))
}

#' 종합점수 S = (Calmar/Calmar_A)^w_c · (PORT_t/PORT_t_A)^w_p — 어느 쪽이든 0 이하면 0(정의역 밖 = F). 벡터화.
gv3_S <- function(calmar, port_t, th, w) {
  ch <- as.numeric(calmar) / th$calmar_a; ph <- as.numeric(port_t) / th$port_t_a
  out <- rep(NA_real_, max(length(ch), length(ph)))
  ok <- is.finite(ch) & is.finite(ph)
  zero <- ok & (ch <= 0 | ph <= 0)
  pos <- ok & !zero
  out[zero] <- 0
  out[pos] <- ch[pos]^w$calmar * ph[pos]^w$port_t
  out
}

# 표 5종(수익 · 벤치 · NAV · 지표 · 벤치 비교) → 채점 입력. 디렉터리판·bt_result 판이 같은 정규화를 거친다.
#   등급 입력은 essence_score 가 읽는 그 표에서 읽는다(getm = metrics.metric_value · getbc = benchmark_compare.active_value).
#   authoritative_remeasure.json 의 essence 블록은 표시용 반올림(소수 셋째 자리)이라 S 입력으로 쓰지 않는다.
.gv3_prep <- function(pr, br, nv, M, C, ar = list()) {
  pr <- as.data.table(pr); br <- as.data.table(br); nv <- as.data.table(nv); M <- as.data.table(M); C <- as.data.table(C)
  for (nm in c("pr", "br", "nv")) { d <- get(nm); if (!"date" %in% names(d)) stop("[grade_v3] date 열 없음: ", nm) }
  pr[, date := as.Date(date)]; br[, date := as.Date(date)]; nv[, date := as.Date(date)]
  if (is.null(pr$leverage)) pr[, leverage := 1]
  if (is.null(pr$risk_free_ret)) pr[, risk_free_ret := 0]
  if (is.null(pr$frequency)) {                       # 빈도 열이 없으면 날짜 간격 중앙값으로 정한다(일 5 미만 = daily · 25 미만 = weekly · 그 이상 = monthly)
    dd <- suppressWarnings(stats::median(as.numeric(diff(sort(unique(pr$date))))))
    pr[, frequency := if (!is.finite(dd) || dd < 5) "daily" else if (dd < 25) "weekly" else "monthly"]
  }
  if (is.null(br$benchmark_id)) br[, benchmark_id := "KOSPI200"]
  br <- br[order(date)]
  if (is.null(br$benchmark_nav)) br[, benchmark_nav := cumprod(1 + benchmark_ret)]
  gm <- function(nm) { v <- M[metric_name == nm, metric_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  gc <- function(nm) { v <- C[metric_name == nm, active_value]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  ess <- list(calmar = gm("Calmar"), port_t = gc("Portfolio_Alpha_t_NW_lag3"), cagr = gm("CAGR"),
              sharpe = gm("Sharpe"), mdd = gm("MDD"))
  list(pr = pr[order(date)], br = br, nv = nv[order(date)], ar = ar, ess = ess)
}

# 산출물 디렉터리 → 채점 입력. 없는 파일은 멈춘다(조용한 NA 금지).
.gv3_read_dir <- function(dir) {
  f <- function(n) { p <- file.path(dir, n); if (!file.exists(p)) stop("[grade_v3] 산출물 없음: ", p); p }
  .gv3_prep(fread(f("03_period_returns.csv")), fread(f("05_benchmark_returns.csv")), fread(f("02_nav.csv")),
            fread(f("06_metrics.csv")), fread(f("07_benchmark_compare.csv")),
            fromJSON(f("authoritative_remeasure.json"), simplifyVector = TRUE))
}

# 메모리 위 bt_result(계약 10종) → 채점 입력 — essence_score 안에서 쓰는 경로(MC7 권위 승격)
.gv3_from_bt <- function(bt) {
  need <- c("period_returns", "benchmark_returns", "metrics", "benchmark_compare")
  miss <- need[vapply(need, function(k) is.null(bt[[k]]) || !NROW(bt[[k]]), logical(1))]
  if (length(miss)) stop("[grade_v3] bt_result 구성 요소 없음: ", paste(miss, collapse = ","))
  sid <- tryCatch(as.character(bt$manifest$strategy_id[[1]]), error = function(e) NA_character_)
  # NAV 가 없는 bt(계약 밖 · 합성 고정물)는 순수익 누적곱으로 유도한다 — 창 지표 전용이고, S 입력(Calmar · PORT_t)은 지표 표에서 온다
  nv <- bt$nav; nav_src <- "contract"
  if (is.null(nv) || !NROW(nv) || !"nav_net" %in% names(nv)) {
    p <- data.table::as.data.table(bt$period_returns)[order(as.Date(date))]
    nv <- p[, .(date, nav_net = cumprod(1 + ret_net))]; nav_src <- "derived_from_period_returns"
  }
  X <- .gv3_prep(bt$period_returns, bt$benchmark_returns, nv, bt$metrics, bt$benchmark_compare,
                 list(strategy_id = sid, essence_grade = NA_character_))
  X$nav_source <- nav_src
  # MC8(CR '강함' 일 때만 쓰인다) 입력 — 보유 · 집행 규약 · 유니버스
  if (!is.null(bt$holdings) && NROW(bt$holdings)) X$H <- data.table::as.data.table(bt$holdings)
  sp <- if (is.list(bt$strategy_spec)) bt$strategy_spec else list()
  mn <- if (is.list(bt$manifest)) bt$manifest else list()
  X$spec <- list(exec_price = .gv3_or(sp[["exec_price"]], NULL), universe = .gv3_or(sp[["universe"]], mn[["universe_id"]]))
  X
}

# 빈도 → 연율화 계수(계약 build_metrics 의 결합 가드와 같은 표)
.gv3_af <- function(freq) {
  f0 <- tolower(trimws(as.character(freq[1])))
  f <- if (grepl("^(d|day|daily)$", f0)) "daily" else if (grepl("^(w|week|weekly)$", f0)) "weekly" else
       if (grepl("^(m|month|monthly)$", f0)) "monthly" else f0
  v <- c(daily = 252, weekly = 52, monthly = 12)[f]
  if (is.na(v)) stop("[grade_v3] 빈도 어휘 밖: ", f0)
  unname(v)
}

#' 창 지표 — essence 와 같은 계약 함수(build_metrics · build_benchmark_compare)로 [from, to] 부분 창을 잰다.
#' @return list(n_obs, calmar, cagr, sharpe, mdd, port_t). 창의 달 수가 min_months 미만이면 지표는 NA
#'   (24개월 = behavior_card.R 의 카드 최소 겹침 월과 같은 관례). 빈도(daily/weekly/monthly)는 수익 표의 frequency 열을 따른다.
gv3_window <- function(pr, br, nv, from = NULL, to = NULL, min_months = 24L, root = NULL) {
  e <- .gv3_deps(.gv3_root(root))
  cut <- function(d) {
    if (!is.null(from)) d <- d[date >= as.Date(from)]
    if (!is.null(to)) d <- d[date <= as.Date(to)]
    d
  }
  P <- cut(pr); B <- cut(br); N <- cut(nv)
  na <- list(n_obs = nrow(P), calmar = NA_real_, cagr = NA_real_, sharpe = NA_real_, mdd = NA_real_, port_t = NA_real_)
  nm <- if (nrow(P)) data.table::uniqueN(format(P$date, "%Y-%m")) else 0L
  if (nm < min_months || !nrow(B) || !nrow(N)) return(na)
  freq <- as.character(P$frequency[1]); af <- .gv3_af(freq)
  # table.Drawdowns 의 'Only k available' 경고는 지표 값과 무관하다(드로다운 개수 안내) — 억제
  M <- suppressWarnings(e$build_metrics(N, P, NULL, run_id = "grade_v3", strategy_id = "grade_v3",
                                        frequency = freq, annualization_factor = af))
  C <- e$build_benchmark_compare(P, B, run_id = "grade_v3", strategy_id = "grade_v3", annualization_factor = af)
  g <- function(T, nm, col) { v <- T[metric_name == nm][[col]]; if (length(v)) as.numeric(v[1]) else NA_real_ }
  list(n_obs = nrow(P), calmar = g(M, "Calmar", "metric_value"), cagr = g(M, "CAGR", "metric_value"),
       sharpe = g(M, "Sharpe", "metric_value"), mdd = g(M, "MDD", "metric_value"),
       port_t = g(C, "Portfolio_Alpha_t_NW_lag3", "active_value"))
}

# 벤치를 '전략처럼' 같은 함수에 넣는다 — 같은 창 KOSPI200 Calmar(하한)를 전략과 같은 정의로 잰다.
.gv3_bench_as_strategy <- function(br, freq = "daily") {
  list(pr = br[, .(date, ret_net = benchmark_ret, risk_free_ret = 0, leverage = 1, frequency = freq)],
       nv = br[, .(date, nav_net = benchmark_nav)])
}

#' 긴 벤치 이력(연대기 · 위기 정의용) — 한 번 읽어 여러 디렉터리에 재사용한다
gv3_bench_history <- function(root = NULL) {
  bp <- file.path(.gv3_root(root), ".cache/benchmark.parquet")
  if (!file.exists(bp) || !requireNamespace("arrow", quietly = TRUE)) return(NULL)
  h <- as.data.table(arrow::read_parquet(bp))
  if (!all(c("Date", "BM_Ret") %in% names(h))) return(NULL)
  h[is.finite(BM_Ret), .(date = as.Date(Date), benchmark_ret = BM_Ret)][order(date)]
}

# 행동 카드 요약(등급에 필요한 것만 · 표는 버린다)
.gv3_card_summary <- function(card) {
  v <- function(x, k) { z <- x[[k]]; if (is.null(z) || !length(z)) NA else z }
  list(cr = v(card$overall, "verdict"), cr_visible = v(card$visible, "verdict"), cr_test = v(card$test, "verdict"),
       n_crisis = v(card$overall, "n_crisis"), n_crisis_test = v(card$test, "n_crisis"),
       dd_capture_median = v(card$overall, "crisis_dd_capture_median"),
       dd_capture_worst = v(card$overall, "crisis_dd_capture_worst"),
       cum_capture_median = v(card$overall, "crisis_cum_capture_median"),
       uc_median = v(card$overall, "bull_up_capture_median"),
       share_crisis_strong = v(card$overall, "share_crisis_strong"),
       share_crisis_weak = v(card$overall, "share_crisis_weak"),
       dc_strong_max = .gv3_or(card$dc_strong_max, NA_real_),
       cdar = v(card$stats, "cdar"), beta = v(card$stats, "beta"),
       beta_down = v(card$stats, "beta_down"), beta_up = v(card$stats, "beta_up"),
       controls = .gv3_or(card$controls$status, NA_character_))
}

#' 등급 결정(순수 함수) — GRADE-V3-S0-BANDS(도훈 수용 10-13) 규칙
#' @param S 종합점수 · @param S_B 그 전략의 B 경계(= S(같은 창 벤치 Calmar, 현행 B PORT_t))
#' @param floors 이름 있는 논리 벡터(port_t·calmar·cagr·sharpe) · @param oos_parts 이름 있는 논리 벡터
#' @param cr 행동 카드 전체 창 판정(strong/normal/weak/insufficient/error)
#' @return list(grade = A|B|C|F|NA, band = S 만으로 정한 띠, notch = +1/0/−1, blocked_by = A 가 아닌 사유, notch_a = 노치로 A)
#'   ① 띠: S ≤ 0 = F · S ≥ A 경계 = A · S ≥ S_B = B · 그 밖 = C
#'   ② A 띠 차단: 하한 ∨ OOS 관문 미충족이면 a_blocked_to(B)
#'   ③ CR 노치(F 제외): 강함 = C→B · B→A(하한 ∧ OOS 충족 시만) / 약함 = 한 단계 하향(A 불가 · B→C · C→F)
gv3_decide <- function(S, S_B, floors, oos_parts, cr, cfg, gates = NULL) {
  a <- cfg$a_boundary
  gates <- if (is.null(gates)) logical(0) else vapply(gates, isTRUE, logical(1))
  a_ok <- all(floors) && all(oos_parts) && all(gates)
  why <- character(0)
  if (!all(floors)) why <- c(why, paste0("floor:", names(floors)[!floors]))
  if (!all(oos_parts)) why <- c(why, paste0("oos:", names(oos_parts)[!oos_parts]))
  if (!all(gates)) why <- c(why, paste0("gate:", names(gates)[!gates]))
  if (identical(cr, "weak") && isTRUE(cfg$cr_notch$weak_blocks_a)) why <- c(why, "cr:weak")
  out <- list(grade = NA_character_, band = NA_character_, notch = 0L, blocked_by = why, notch_a = FALSE)
  if (length(S) != 1L || !is.finite(S)) return(out)
  sb_ok <- length(S_B) == 1L && is.finite(S_B)
  band <- if (S <= 0) "F" else if (S >= a) "A" else if (sb_ok && S >= S_B) "B" else if (sb_ok) "C" else NA_character_
  out$band <- band
  if (is.na(band)) return(out)                                   # B 경계를 못 재면(벤치 Calmar 결측) B·C 를 지어내지 않는다
  lv <- c("F", "C", "B", "A")
  g <- band
  if (g == "A" && !a_ok) g <- .gv3_or(cfg$cr_notch$a_blocked_to, "B")
  if (g != "F" && identical(cfg$cr_notch$applies_to, "S_gt_zero")) {
    if (identical(cr, "strong")) {
      if (g == "C") { g <- "B"; out$notch <- 1L }
      else if (g == "B" && (a_ok || !isTRUE(cfg$cr_notch$strong_to_a_requires_floors))) { g <- "A"; out$notch <- 1L; out$notch_a <- TRUE }
    } else if (identical(cr, "weak")) {
      g <- lv[max(1L, match(g, lv) - 1L)]; out$notch <- -1L
    }
  }
  out$grade <- g
  out
}

#' 채점 컨텍스트(설정 · 문턱 · 카드 설정 · 롤링 설정 · 긴 벤치 이력) — 여러 칸을 채점할 때 한 번만 만든다
gv3_ctx <- function(root = NULL) {
  root <- .gv3_root(root); e <- .gv3_deps(root)
  list(cfg = gv3_cfg(root), th = gv3_thresholds(root), bc_cfg = e$bc_cfg(root),
       rg = e$rg_params(root), bm_hist = gv3_bench_history(root))
}

#' 디렉터리 1개 채점
#' @param dir run_paper_replication 측정 산출물(또는 close_t1 재측정) 디렉터리
#' @param ctx 재사용 묶음(gv3_ctx) — NULL 이면 여기서 만든다
gv3_score_dir <- function(dir, root = NULL, ctx = NULL, gates = NULL) {
  .gv3_score_tables(.gv3_read_dir(dir), root, ctx, dir = dir, gates = gates)
}

#' 메모리 위 bt_result 채점 — essence_score 가 권위 등급을 낼 때 쓰는 경로(MC7)
#' @param gates A 의 추가 무결성 관문(이름 있는 논리 벡터) — 예: c(dsr_sweep = FALSE) 면 A 불가(사유 gate:dsr_sweep)
gv3_score_bt <- function(bt, root = NULL, ctx = NULL, gates = NULL) {
  .gv3_score_tables(.gv3_from_bt(bt), root, ctx, dir = NA_character_, gates = gates)
}

.gv3_score_tables <- function(X, root = NULL, ctx = NULL, dir = NA_character_, gates = NULL) {
  root <- .gv3_root(root); e <- .gv3_deps(root)
  if (is.null(ctx)) ctx <- gv3_ctx(root)
  cfg <- ctx$cfg; th <- ctx$th
  if (!is.null(dir) && !is.na(dir)) X$dir <- dir
  es <- X$ar[["essence"]]          # [[ ]] = 정확 일치 — $ 는 부분 일치라 bt 경로의 essence_grade 를 집어 온다
  if (!is.list(es)) es <- NULL
  num <- function(z) suppressWarnings(as.numeric(.gv3_or(z, NA_real_))[1])
  ess <- X$ess
  ess$oos_retention <- num(es$oos_retention)
  # 권위 JSON(반올림 표시값)과 표 원값의 정합 — 같은 측정에서 나온 값인지 확인(반올림 폭 안이어야 한다 · JSON 없으면 NA)
  json_gap <- if (is.null(es)) NA_real_ else
    max(abs(c(num(es$calmar) - ess$calmar, num(es$portfolio_alpha_t_nw_lag3) - ess$port_t,
              num(es$cagr) - ess$cagr, num(es$net_sharpe) - ess$sharpe)), na.rm = FALSE)

  # ── 재사용 경로 양성 대조: 같은 함수로 다시 잰 전기간 값이 권위 표 값과 같아야 한다 ──
  full <- gv3_window(X$pr, X$br, X$nv, root = root)
  parity <- max(abs(c(full$calmar - ess$calmar, full$port_t - ess$port_t, full$cagr - ess$cagr,
                      full$sharpe - ess$sharpe)), na.rm = FALSE)

  # ── S · 하한 ──
  S <- gv3_S(ess$calmar, ess$port_t, th, cfg$weights)
  B <- .gv3_bench_as_strategy(X$br, freq = as.character(X$pr$frequency[1]))
  bench <- gv3_window(B$pr, B$pr[, .(date, benchmark_ret = ret_net, benchmark_id = as.character(X$br$benchmark_id[1]))],
                      B$nv, root = root)
  fl <- c(port_t = isTRUE(ess$port_t >= th$port_t_b),
          calmar = isTRUE(ess$calmar >= bench$calmar),
          cagr = isTRUE(ess$cagr >= th$cagr_min),
          sharpe = isTRUE(ess$sharpe >= th$sharpe_min))

  # ── 행동 카드(CR · 상승 포착 · CDaR) ──
  #   긴 벤치 이력은 측정 마지막 날까지만 쓴다 — 그 뒤 이력이 붙으면 PS 연대기 끝 전환점이 움직여
  #   같은 산출물의 등급이 재채점 때마다 달라질 수 있다(재현성) · 측정 시점에 없던 데이터이기도 하다.
  last_d <- max(X$pr$date)
  bmh <- if (is.null(ctx$bm_hist)) NULL else ctx$bm_hist[date <= last_d]
  card <- tryCatch(e$bc_card(X$pr[, .(date, ret_net)], X$br[, .(date, benchmark_ret)], cfg = ctx$bc_cfg,
                             bm_hist = bmh, strategy_id = as.character(.gv3_or(X$ar$strategy_id, NA)),
                             root = root),
                   error = function(err) structure(list(err = conditionMessage(err)), class = "gv3_err"))
  cs <- if (inherits(card, "gv3_err")) list(cr = "error", cr_test = "error", card_error = card$err) else .gv3_card_summary(card)

  # ── OOS (τ_D 단일 달력 분할) ──
  tau <- as.Date(ctx$bc_cfg$tau_d); tau_ym <- format(tau, "%Y-%m")
  is_w <- gv3_window(X$pr, X$br, X$nv, to = tau, root = root)
  oos_w <- gv3_window(X$pr, X$br, X$nv, from = tau + 1, root = root)
  S_is <- gv3_S(is_w$calmar, is_w$port_t, th, cfg$weights); S_oos <- gv3_S(oos_w$calmar, oos_w$port_t, th, cfg$weights)
  ratio <- function(a, b) if (is.finite(a) && is.finite(b) && b > 0) a / b else NA_real_
  rr <- e$rg_rolling(X$pr[, .(date, ret_net)], X$br[, .(date, benchmark_ret)], params = ctx$rg, keep_series = TRUE)
  pass_oos <- if (identical(rr$status, "ok")) { s <- rr$series[ym > tau_ym]; if (nrow(s)) mean(s$pass) else NA_real_ } else NA_real_
  pass_min <- num(ctx$rg$rescue_min_recent_pass)
  oos_parts <- c(test_window_cr_not_weak = !(cs$cr_test %in% c("weak", "error")) && !is.na(cs$cr_test),
                 rolling36_pass_oos = isTRUE(is.finite(pass_oos) && is.finite(pass_min) && pass_oos >= pass_min))
  oos_gate <- all(oos_parts)

  S_B <- gv3_S(bench$calmar, th$port_t_b, th, cfg$weights)        # B 경계 = 같은 창 벤치 Calmar · 현행 B PORT_t 모서리의 S
  # CR '강함' 상향 노치의 MC8 조건(GRADE-V3-CR-STRONG-SELECTION) — 강함일 때만 대조를 잰다 · 실패 = 상향 없음(fail-closed)
  mc8 <- list(status = "not_needed", label = NA_character_)
  if (identical(cs$cr, "strong") && !identical(.gv3_or(cfg$cr_notch$strong_requires, "none"), "none"))
    mc8 <- tryCatch(.gv3_mc8(X, card, ctx, root, e),
                    error = function(err) list(status = "error", label = NA_character_, err = conditionMessage(err)))
  # v3.2 — 타이밍 방어(경로 짝 미통과)면 증거 등록부를 본다(없으면 보통 · fail-closed)
  basis <- NA_character_; tev <- NULL
  if (identical(cs$cr, "strong") && identical(.gv3_or(cfg$cr_notch$strong_requires, "none"), "mc8_selection_or_timing_evidence")) {
    tu <- cfg$cr_notch[["timing_unit"]]
    basis <- gv3_notch_basis(mc8, NULL, tu)
    if (identical(basis, "timing_no_evidence")) {
      tev <- tryCatch(gv3_timing_evidence(cfg, as.character(.gv3_or(X$ar$strategy_id, NA_character_))[1], dir, root), error = function(err) NULL)
      basis <- gv3_notch_basis(mc8, tev, tu)
    }
  }
  cr_notch <- gv3_cr_for_notch(cs$cr, mc8, cfg, tev)
  dec <- gv3_decide(S, S_B, fl, oos_parts, cr_notch, cfg, gates = gates)
  grade <- dec$grade; why <- dec$blocked_by
  if (identical(cs$cr, "strong") && !identical(cr_notch, "strong"))
    why <- c(why, if (!is.na(basis) && !identical(basis, "not_selection")) paste0("cr:strong_", basis) else
                   paste0("cr:strong_without_selection(", .gv3_or(mc8$label, mc8$status), ")"))

  list(schema = "grade_v3_v1", mode = cfg$mode, dir = dir, nav_source = .gv3_or(X$nav_source, "contract"),
       strategy_id = as.character(.gv3_or(X$ar$strategy_id, NA)),
       essence_grade = as.character(.gv3_or(X$ar$essence_grade, NA)),
       regime = as.character(.gv3_or(X$ar$measurement_regime$regime, .gv3_or(X$ar$measurement_regime$key, NA))),
       period = c(format(min(X$pr$date)), format(max(X$pr$date))),
       essence = ess, parity_max_abs = parity, json_gap_max_abs = json_gap, S = S,
       bench = list(calmar = bench$calmar, cagr = bench$cagr, mdd = bench$mdd, sharpe = bench$sharpe),
       floors = as.list(fl), card = cs,
       oos = list(tau_d = format(tau), is = is_w, oos = oos_w, S_is = S_is, S_oos = S_oos,
                  retention_S = ratio(S_oos, S_is), retention_calmar = ratio(oos_w$calmar, is_w$calmar),
                  retention_sharpe = ratio(oos_w$sharpe, is_w$sharpe),
                  rolling_status = rr$status, pass_life = .gv3_or(rr$pass_life, NA_real_),
                  pass_recent = .gv3_or(rr$pass_recent, NA_real_), pass_oos = pass_oos, pass_min = pass_min,
                  pass_min_status = cfg$oos$rolling_pass_min_status, parts = as.list(oos_parts), gate = oos_gate),
       S_B = S_B, band = dec$band, notch = dec$notch, notch_a = dec$notch_a, cr_notch = cr_notch, mc8 = mc8,
       cr_notch_basis = basis, timing_evidence = if (is.null(tev)) NULL else tev[c("round_id", "unit", GV3_TIMING_FLAGS)],
       rules_version = as.character(.gv3_or(cfg$rules_version, "v3.0")),
       crisis_def = as.character(.gv3_or(ctx$bc_cfg$crisis_episode_def, "running_peak_drawdown")),
       grade_v3 = grade, blocked_by = why)
}

#' 채점 결과 → 표 1행(평탄)
gv3_row <- function(r) {
  g <- function(x) if (is.null(x) || !length(x)) NA else x[[1]]
  data.table(dir = r$dir, strategy_id = r$strategy_id, regime = r$regime, essence_grade = r$essence_grade,
             grade_v3 = r$grade_v3, S = r$S, calmar = r$essence$calmar, port_t = r$essence$port_t,
             cagr = r$essence$cagr, sharpe = r$essence$sharpe, mdd = r$essence$mdd,
             parity_max_abs = r$parity_max_abs, json_gap_max_abs = r$json_gap_max_abs, bench_calmar = r$bench$calmar,
             floor_port_t = r$floors$port_t, floor_calmar = r$floors$calmar, floor_cagr = r$floors$cagr,
             floor_sharpe = r$floors$sharpe,
             cr = g(r$card$cr), cr_visible = g(r$card$cr_visible), cr_test = g(r$card$cr_test),
             n_crisis = g(r$card$n_crisis), dd_capture_median = g(r$card$dd_capture_median),
             dd_capture_worst = g(r$card$dd_capture_worst), uc_median = g(r$card$uc_median),
             cdar = g(r$card$cdar), beta = g(r$card$beta),
             S_is = r$oos$S_is, S_oos = r$oos$S_oos, retention_S = r$oos$retention_S,
             calmar_is = r$oos$is$calmar, calmar_oos = r$oos$oos$calmar,
             pass_life = r$oos$pass_life, pass_oos = r$oos$pass_oos, oos_gate = r$oos$gate,
             S_B = r$S_B, band = r$band, notch = r$notch, notch_a = r$notch_a,
             blocked_by = paste(r$blocked_by, collapse = ";"),
             period_start = r$period[1], period_end = r$period[2])
}
