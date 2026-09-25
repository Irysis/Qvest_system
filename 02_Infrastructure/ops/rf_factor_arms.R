#!/usr/bin/env Rscript
#==============================================================================
# rf_factor_arms.R — B1(멀티팩터) 칸을 **등록부에서 선정** (2026-09-01 도훈 지시)
#
# 왜: 구판 B1 은 팩터 5종이 격자에 문자로 박혀 있었다(2026-08-30 손으로 고른 값).
#   rf_grid_propose.sh 는 로그 0건 — 한 번도 안 돌았고, 그 파일 스스로 진단해 뒀다:
#   "팩터 DB 331종 중 5종을 세션이 임의로 골랐고 최선이라는 근거가 없음".
#   그리고 B1 은 2팩터 컴포짓만 재서 **결합 깊이를 한 번도 안 쟀다**.
#   weight_catalog·overlay_catalog 가 이미 같은 병을 진단해 뒀다 —
#   "안 붙은 이유는 계약 충돌이 아니라 아무도 한 줄을 안 썼기 때문이다."
#
# 규칙(판단이 아니라 정렬):
#   ① 후보 풀 = 횡단면 팩터 ∩ IC 이력 보유 ∩ active   (축 판정 = factor_panel_axis.json)
#      ∖ PIT 격리(06_Registry/pit_quarantine.json · 2026-09-24 C11 봉쇄 — B1 규칙 선정·설계 재료·b1_verify 공통)
#   ② ★시드 회전 — 시드를 "최상위 1종"으로 박으면 그리디가 결정론이라 **전 논문이 같은
#      사슬**을 받는다. 331종을 조사해 놓고 5종만 쓰고, 구판의 병("모든 논문이 같은 5팩터")을
#      선정 규칙만 바꿔 재생산한다. 회전이 없으면 이 블록의 총 조합은 entry 수와 무관하게 5개다.
#   ③ 직교 사슬 — 기선택 집합과의 max|rho| 최소를 반복 추가. rho = IC 시계열 상관.
#      계열 중복 금지(14계열이 실질 해상도 — 같은 계열 둘은 새 정보가 아니다).
#   ④ 셀 = 사슬의 **접두 집합**(깊이 1..n). entry 안 = 깊이 · entry 사이 = 구성.
#
# ★선정과 결합은 다른 직교성이다 — 선정은 IC **시계열** 상관(언제 벌리나),
#   결합은 rf_cell_engine 의 **횡단면** rank-Z(어떤 종목을 고르나). 셀 basis 에 명시한다.
#
# ★선정 통계는 as-of 다 (2026-09-24 · 플랜 P0-08 · 감사 D4-02·D10-05 · pit.md C1 D-E 명문화).
#   구판은 ①전기간 |ic_all|(factor_evidence — 2026 까지의 평균)로 정렬하고 ②전기간 IC 상관으로 사슬을 짰으며
#   ③tier 정렬항이 A..E 를 찾는데 실제 어휘는 S1/S2/S3 라 전부 99 → 사실상 |ic_all| 단독이었다.
#   2005~ 시그널일의 보유를 그 뒤 IC 로 고른 셈이다(평가 창 결과를 소비하는 자동 선정 = 전략의 일부 = C1/C14).
#   신판: 순위·tier·상관은 전부 `IC[Usable_Date <= asof]` 로만 계산한다. asof 기본 = 격자 fixed_axes.start_date
#   (첫 시그널일 이전 워밍업 창 — 2005-01-01 기준 풀 343종 중 316종이 36개월+ 이력, 실측 2026-09-24).
#   tier 는 factor_evidence.json 의 저장 tier(전기간 ic_all·최근 3년 ICIR — 미래 정보)를 쓰지 않고, 같은 파일이
#   선언한 절단선(thresholds_declared)·어휘(counts 의 S1/S2/S3)로 **as-of 통계에서 다시 판정**한다.
#   후보 **자격**(계열·lifecycle·축·격리·IC 이력 존재)은 분류라 as-of 와 무관하다 — 풀 구성은 그대로다
#   (설계 재료 rf_b1_design_lib 는 id·계열만 쓴다). 순위를 매길 as-of 표본이 min_ic_months 미만인 팩터만 사슬에서 뺀다
#   (실측: V06_fDY 는 2005-01 as-of 4개월 · |IC| 0.186 — 그대로 두면 잡음이 계열 시드가 된다).
#   ★격자(reinforce_program.json)를 못 찾는 root(합성 픽스처)는 as-of 를 해석할 수 없다 — 이때만 전표본으로 돌고
#     selection_basis = "full_sample_ic" 라벨을 셀·반환값에 싣는다(운영 root 는 격자가 있어 항상 as-of).
#   ★as-of 상한 가드 (2026-09-25 · P0-08 잔여 R3): 인자 as-of 는 결정 시점(격자 fixed_axes.start_date = 엔트리 워밍업 창 끝)
#     이하만 받는다 — 뒤·미래·NA(구 '명시적 전표본')·복수는 stop. 격자 없는 root 에 인자 as-of = stop(상한 대조 불가).
#
# 사용: rf_pick_factor_sets(n = 5, exclude = <기측정 서명>, seed_offset = <원장 entry 수>,
#                           depths = c(1,2,3,4,5), fallback_paper = <기저 논문>)
#       -> list(cells = [...], picked_ids, n_available, excluded_no_ic, substrate_asof)
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFF_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

# ── 계열 → 정전 논문 (근거 의무 충족용) ──────────────────────────────────────
# ★여기에 있는 url 은 전부 **현행 격자에서 이미 쓰이던 검증된 링크**다. 링크를 지어내지
#   않는다 — 맵에 없는 계열은 호출부가 넘긴 fallback_paper(그 entry 의 기저 논문)를 쓴다.
#   원장 rf_append_attempt 는 multifactor 축에 url 1건을 기계 강제하므로 둘 중 하나는 있어야 한다.
.RFF_FAMILY_PAPER <- list(
  value = list(title = "Fama & French (1992), The Cross-Section of Expected Stock Returns, JF 47(2)",
               url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1992.tb04398.x"),
  quality = list(title = "Novy-Marx (2013), The Other Side of Value, JFE 108(1)",
                 url = "https://www.sciencedirect.com/science/article/pii/S0304405X13000044"),
  risk = list(title = "Ang, Hodrick, Xing & Zhang (2006), The Cross-Section of Volatility and Expected Returns, JF 61(1)",
              url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.2006.00836.x"),
  liquidity = list(title = "Amihud (2002), Illiquidity and Stock Returns, JFM 5(1)",
                   url = "https://www.sciencedirect.com/science/article/pii/S1386418101000246"),
  consensus = list(title = "Chan, Jegadeesh & Lakonishok (1996), Momentum Strategies, JF 51(5)",
                   url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1996.tb05222.x"),
  size = list(title = "Banz (1981), The Relationship Between Return and Market Value of Common Stocks, JFE 9(1)",
              url = "https://www.sciencedirect.com/science/article/abs/pii/0304405X81900180"),
  # defense 계열의 상위는 실측상 변동성 팩터(D42_EWMA_Vol·D35_RealVol_63d…)다 —
  # 현행 격자가 lowvol60 셀에 쓰던 바로 그 논문이 정확히 이 주제다(새 링크가 아니다).
  defense = list(title = "Ang, Hodrick, Xing & Zhang (2006), The Cross-Section of Volatility and Expected Returns, JF 61(1)",
                 url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.2006.00836.x"),
  momentum = list(title = "Chan, Jegadeesh & Lakonishok (1996), Momentum Strategies, JF 51(5)",
                  url = "https://onlinelibrary.wiley.com/doi/10.1111/j.1540-6261.1996.tb05222.x")
)

#' 팩터 id → 계열(category). 출처 = factor_evidence.json (rf_factor_pool 과 같은 원천 — 둘이 다른
#'   원천을 읽으면 라벨의 계열과 논문의 계열이 어긋난다). 등록부(factor_registry.json)는 폴백.
#'   ★kind=="db" 팩터만 계열이 있다 — 엔진 내장 신호·기저 신호는 NA 로 돌아온다.
rf_factor_families <- function(factor_ids, root = .RFF_ROOT) {
  ids <- unique(as.character(unlist(factor_ids))); ids <- ids[!is.na(ids) & nzchar(ids)]
  if (!length(ids)) return(setNames(character(0), character(0)))
  EV  <- tryCatch(fromJSON(file.path(root, "06_Registry/factor_evidence.json"), simplifyVector = FALSE)$factors,
                  error = function(e) list())
  REG <- tryCatch(fromJSON(file.path(root, ".cache/factor_db/factor_registry.json"), simplifyVector = FALSE)$factors,
                  error = function(e) list())
  vapply(ids, function(i) {
    c1 <- (EV[[i]]  %||% list())$category
    c2 <- (REG[[i]] %||% list())$category
    as.character(c1 %||% c2 %||% NA_character_)
  }, character(1))
}

#' 셀의 근거 논문 목록 = 기저 논문 + 셀 자체 처치 논문 + 셀에 든 팩터 **전 계열**의 논문 (url 중복 제거).
#'
#' ★2026-09-02 수리 배경: 구판은 첫 계열의 논문 하나만 붙였다. B1 사슬이 접두 집합이라 첫 계열 = 항상
#'   시드 계열이어서 4계열 컴포짓 5칸이 전부 같은 논문(Amihud 2002)으로 원장에 적혔고, B5 오버레이는
#'   자체 논문이 없어 러너가 **B1 승자 논문을 차용**했다(낙폭 브레이크가 유동성 논문을 인용). 그래서
#'   원장의 "같은 root_papers 3회 연속" WARN 이 20칸 연속 발화했다 — 계기가 재려던 '한 논문 매몰' 이
#'   아니라 표기 결함을 재고 있었다.
#' ★매핑 없는 계열은 버리지 않고 `unmapped_families` 로 돌려준다 — 침묵 누락이 이 저장소의 반복 결함.
#'   (2026-09-02 실측: accrual·growth·investor_flow·crowding·regime·leverage 6계열 91팩터가 매핑 없음.)
#' @param spec_or_ids  셀 스펙(list: factors/factor2/factor3) 또는 팩터 id 벡터
#' @param base_paper   기저 논문(이 entry 가 강화하는 논문) — 있으면 목록 첫 항목
#' @param cell_paper   셀 자체 처치 논문(B2 비중·B3 유니버스 격자 셀의 root_paper) — 있으면 둘째
#' @param families     계열 벡터를 호출자가 이미 알면 전달(등록부 조회 생략)
#' @return list(papers, families, unmapped_families, unknown_ids)
rf_root_papers_for <- function(spec_or_ids, base_paper = NULL, cell_paper = NULL, families = NULL,
                               root = .RFF_ROOT) {
  ids <- if (is.list(spec_or_ids) && !is.null(names(spec_or_ids)) &&
             any(c("factors", "factor2", "factor3") %in% names(spec_or_ids))) {
    fs <- c(spec_or_ids$factors %||% list(),
            if (!is.null(spec_or_ids$factor2) && !identical(spec_or_ids$factor2$kind %||% "", "none")) list(spec_or_ids$factor2),
            if (!is.null(spec_or_ids$factor3) && !identical(spec_or_ids$factor3$kind %||% "", "none")) list(spec_or_ids$factor3))
    fs <- Filter(function(f) is.list(f) && identical(as.character(f$kind %||% "db"), "db"), fs)
    vapply(fs, function(f) as.character(f$id %||% ""), character(1))
  } else as.character(unlist(spec_or_ids))
  ids <- unique(ids[!is.na(ids) & nzchar(ids)])
  unknown <- character(0)
  if (is.null(families)) {
    fam <- if (length(ids)) rf_factor_families(ids, root) else character(0)
    unknown <- unname(ids[is.na(fam) | !nzchar(fam)])
    families <- fam[!is.na(fam) & nzchar(fam)]
  }
  fams <- unique(as.character(families))
  unmapped <- fams[vapply(fams, function(fm) is.null(.RFF_FAMILY_PAPER[[fm]]), logical(1))]
  papers <- list()
  for (p in c(list(base_paper), list(cell_paper), lapply(fams, function(fm) .RFF_FAMILY_PAPER[[fm]]))) {
    if (is.list(p) && nzchar(as.character(p$url %||% ""))) papers[[length(papers) + 1L]] <- p
  }
  if (length(papers)) {
    urls <- vapply(papers, function(p) as.character(p$url), character(1))
    papers <- papers[!duplicated(urls)]
  }
  list(papers = papers, families = fams, unmapped_families = unname(unmapped), unknown_ids = unknown)
}

#' PIT 격리 팩터 id (2026-09-24 · C11 봉쇄 · pit.md '위반 시 처리' 1·2단계를 수리 전에 집행)
#'   정본 = <root>/06_Registry/pit_quarantine.json · 판독기 = 02_Infrastructure/validation/pit_quarantine.R.
#'   판독기는 데이터 루트 → 코드 루트 순으로 찾는다(검사 픽스처 root 에 코드가 없어도 된다).
#'   ★목록이 있는데 판독기가 없거나 목록이 파손이면 stop — 격리를 조용히 건너뛰지 않는다
#'     (러너는 factor_pick_failed 로 기록하고 격자 스냅샷 셀로 진행한다).
.rff_pitq_ids <- function(root) {
  rel <- "02_Infrastructure/validation/pit_quarantine.R"
  lib <- c(file.path(root, rel), file.path(.RFF_ROOT, rel)); lib <- lib[file.exists(lib)]
  if (!length(lib)) {
    if (file.exists(file.path(root, "06_Registry/pit_quarantine.json")))
      stop("[rf_factor_arms] pit_quarantine.json 은 있는데 판독기(pit_quarantine.R)가 없다 — 격리를 건너뛰지 않는다")
    return(character(0))
  }
  en <- new.env(parent = globalenv()); sys.source(lib[1], envir = en)
  en$pitq_factor_ids(root)
}

#' 격자(reinforce_program.json) — 데이터 root → 코드 root 순. 없으면 NULL.
.rff_program <- function(root) {
  for (r in unique(c(root, .RFF_ROOT))) {
    p <- file.path(r, "06_Registry/reinforce_program.json")
    if (file.exists(p)) return(list(prog = fromJSON(p, simplifyVector = FALSE), path = p))
  }
  NULL
}

#' as-of 해석 (선정 통계 창의 끝)
#'   asof = 날짜(≤ 결정 시점) → 그 날짜 · NULL → 격자 fixed_axes.start_date(= 결정 시점).
#'   격자가 없으면 전표본 + 라벨(unresolved) — 인자 as-of 는 받지 않는다(상한을 대조할 수 없다).
#'   격자가 있는데 B1.selection_asof 설정이 없으면 stop(하드코딩 금지).
#' ★상한 가드 (2026-09-25 · P0-08 잔여 R3) — 결정 시점 = 격자 fixed_axes.start_date(엔트리 워밍업 창의 끝 · 첫 시그널일
#'   이전 · B1.selection_asof.asof 가 선언한 정의). 규칙 선정 사슬은 그 엔트리의 전 칸(첫 시그널일부터)에 쓰이므로
#'   선정 통계가 그 날짜 뒤 IC 를 보면 시점 t 보유를 미래 통계로 고른 것이다(pit.md C1 D-E · C14).
#'   구판은 인자 as-of 를 상한 없이 받았다 — 2020-01-01·미래 날짜·NA(전표본)가 전부 통과했고 사슬이 바뀌었다
#'   (실증 = R3 evidence red_b08). 신판: 인자 as-of 가 NA·복수·해석 불가·미래·결정 시점 뒤면 stop.
#'   결정 시점보다 이른 as-of 는 받는다(더 보수적인 창 — 미래 정보 없음). 구 'asof=NA 명시적 전표본' 경로는 폐지.
#' @return list(date = Date|NA, basis = "asof_ic"|"full_sample_ic", source, bound(결정 시점), cfg(min_ic_months, recent_icir_days, recent_icir_min_n))
.rff_asof <- function(root, asof = NULL) {
  G <- .rff_program(root)
  cfg <- NULL
  if (!is.null(G)) {
    b1 <- Filter(function(b) identical(as.character(b$id %||% ""), "B1"), G$prog$blocks %||% list())
    cfg <- if (length(b1)) b1[[1]][["selection_asof"]] else NULL
    if (!is.list(cfg))
      stop("[rf_factor_arms] B1.selection_asof 설정 부재 — 최소 표본·최근 ICIR 창을 코드에 박지 않는다: ", G$path)
    need <- c("min_ic_months", "recent_icir_days", "recent_icir_min_n")
    miss <- need[vapply(need, function(k) is.null(cfg[[k]]), logical(1))]
    if (length(miss)) stop(sprintf("[rf_factor_arms] B1.selection_asof 필수 키 부재: %s", paste(miss, collapse = ", ")))
    cfg <- list(min_ic_months = as.integer(cfg$min_ic_months), recent_icir_days = as.integer(cfg$recent_icir_days),
                recent_icir_min_n = as.integer(cfg$recent_icir_min_n))
    if (any(!is.finite(unlist(cfg))) || any(unlist(cfg) < 1L))
      stop("[rf_factor_arms] B1.selection_asof 값은 1 이상 정수여야 한다")
  }
  # 결정 시점(상한) — 격자 fixed_axes.start_date. 값을 코드에 두지 않는다(격자가 정본).
  sd <- if (is.null(G)) "" else as.character((G$prog$fixed_axes %||% list())$start_date %||% "")
  if (!is.null(G) && !nzchar(sd)) stop("[rf_factor_arms] 격자 fixed_axes.start_date 부재 — as-of 를 정할 수 없다: ", G$path)
  bound <- if (nzchar(sd)) suppressWarnings(as.Date(sd)) else as.Date(NA)
  if (nzchar(sd) && is.na(bound)) stop(sprintf("[rf_factor_arms] fixed_axes.start_date 해석 불가: '%s'", sd))
  if (!is.na(bound) && bound > Sys.Date())
    stop(sprintf("[rf_factor_arms] 격자 fixed_axes.start_date %s 가 미래 — 결정 시점이 오늘 뒤면 전표본과 같다(C1)", format(bound)))
  if (!is.null(asof)) {
    # ★상한 가드 — NA 를 '전표본' 으로 읽지 않는다(구판 explicit_full_sample 폐지). 판정 순서: 형식 → 미래 → 결정 시점.
    if (length(asof) != 1L || is.na(asof))
      stop(sprintf("[rf_factor_arms] as-of 인자가 NA/복수(%s) — 전표본 선정 경로는 폐지됐다(C1/C14 · 결정 시점 = 격자 fixed_axes.start_date)",
                   paste(format(asof), collapse = ",")))
    d <- suppressWarnings(as.Date(as.character(asof)))
    if (length(d) != 1L || is.na(d)) stop(sprintf("[rf_factor_arms] as-of 해석 불가: '%s'", paste(asof, collapse = ",")))
    if (is.na(bound))
      stop("[rf_factor_arms] 결정 시점(격자 fixed_axes.start_date)을 모르는 root 에 as-of 인자 — 상한을 대조할 수 없다(fail-closed)")
    if (d > Sys.Date())
      stop(sprintf("[rf_factor_arms] as-of %s 가 미래(오늘 %s) — 선정 통계 창 끝은 결정 시점 %s 이하여야 한다(C1/C14)",
                   format(d), format(Sys.Date()), format(bound)))
    if (d > bound)
      stop(sprintf(paste0("[rf_factor_arms] as-of %s > 결정 시점 %s(격자 fixed_axes.start_date = 엔트리 워밍업 창 끝 · 첫 시그널일 이전) — ",
                          "첫 시그널일 뒤 실현 IC 로 사슬을 고르게 된다(pit.md C1 D-E · C14)"), format(d), format(bound)))
    return(list(date = d, basis = "asof_ic", source = "arg", bound = bound, cfg = cfg))
  }
  if (is.null(G)) {
    message("[rf_factor_arms] ★격자 부재 root — as-of 미해석, 전표본 IC 로 선정(selection_basis=full_sample_ic)")
    return(list(date = as.Date(NA), basis = "full_sample_ic", source = "unresolved(격자 부재)", bound = as.Date(NA), cfg = cfg))
  }
  list(date = bound, basis = "asof_ic", source = sprintf("fixed_axes.start_date(%s)", G$path), bound = bound, cfg = cfg)
}

#' tier 판정 규칙 — factor_evidence.json 이 **선언한** 절단선·어휘에서 재도출(A..E 리터럴 금지).
#'   어휘 = counts/thresholds_declared 의 S<k> 이름(k 오름차순 = 좋은 순). 규칙은 build_factor_evidence.py::tier_of 와 같다:
#'   |ic| >= S<k>_abs_ic 이고 그 단계의 부가 조건(S<k>_min_months · S<k>_require_sign_agree)을 모두 만족하는 첫 k,
#'   아무 절단선도 못 넘으면 마지막 어휘. ic 가 NA 면 NA(미측정). 선언이 없으면 NULL(= tier 정렬 없음 · 라벨).
.rff_tier_rule <- function(EVJ) {
  th <- EVJ$thresholds_declared; cn <- names(EVJ$counts %||% list())
  if (!is.list(th) || !length(th)) return(NULL)
  lv <- unique(c(sub("_.*$", "", names(th)), cn))
  lv <- lv[grepl("^S[0-9]+$", lv)]
  if (length(lv) < 2L) return(NULL)
  lv <- lv[order(as.integer(sub("^S", "", lv)))]
  list(levels = lv, th = th)
}
.rff_tier_of <- function(ic, icir3, n_months, rule) {
  if (is.null(rule)) return(rep(NA_character_, length(ic)))
  vapply(seq_along(ic), function(i) {
    a <- abs(ic[i]); if (!is.finite(a)) return(NA_character_)
    for (L in rule$levels[-length(rule$levels)]) {
      cut <- suppressWarnings(as.numeric(rule$th[[paste0(L, "_abs_ic")]] %||% NA_real_))
      if (!is.finite(cut) || a < cut) next
      mm <- rule$th[[paste0(L, "_min_months")]]
      if (!is.null(mm) && !(is.finite(n_months[i]) && n_months[i] >= as.numeric(mm))) next
      sg <- rule$th[[paste0(L, "_require_sign_agree")]]
      if (isTRUE(sg) && !(is.finite(icir3[i]) && ic[i] * icir3[i] > 0)) next
      return(L)
    }
    rule$levels[length(rule$levels)]
  }, character(1))
}

#' as-of IC 통계 (팩터별) — 평균 IC · 개월 수 · 최근 창 ICIR (stage_gate_engine.R:977-980 와 같은 정의, 창 끝 = as-of 표본의 마지막 형성일)
.rff_ic_stats <- function(IC, recent_days = NULL, recent_min_n = NULL) {
  if (!nrow(IC)) return(data.table(Factor_Name = character(), ic_asof = numeric(), n_asof = integer(), icir3_asof = numeric()))
  has_rc <- !is.null(recent_days) && !is.null(recent_min_n)
  IC[is.finite(IC), {
    rc <- if (has_rc) IC[Date >= max(Date) - recent_days] else numeric(0)
    .(ic_asof = mean(IC), n_asof = .N,
      icir3_asof = if (has_rc && length(rc) >= recent_min_n && isTRUE(stats::sd(rc) > 0)) mean(rc) / stats::sd(rc) else NA_real_)
  }, by = Factor_Name]
}

#' 후보 풀 — 횡단면 ∩ IC 이력 ∩ active ∖ PIT 격리 (+ as-of 순위 통계)
#' @param asof NULL = 격자 fixed_axes.start_date(결정 시점) · 날짜(≤ 결정 시점) = 그 날짜 · NA/미래/결정 시점 뒤 = stop(.rff_asof 상한 가드)
rf_factor_pool <- function(root = .RFF_ROOT, asof = NULL) {
  ev_p <- file.path(root, "06_Registry/factor_evidence.json")
  ax_p <- file.path(root, "06_Registry/factor_panel_axis.json")
  ic_p <- file.path(root, ".cache/factor_db/factor_ic_monthly.parquet")
  for (p in c(ev_p, ic_p)) if (!file.exists(p)) stop("[rf_factor_arms] 부재: ", p)
  A  <- .rff_asof(root, asof)
  EVJ <- fromJSON(ev_p, simplifyVector = FALSE)
  EV <- EVJ$factors
  AX <- if (file.exists(ax_p)) fromJSON(ax_p, simplifyVector = FALSE)$factors else list()
  # ★lifecycle 은 **registry 정본**에서 읽는다(2026-09-01 수리). factor_evidence 사이드카의
  #   lifecycle_status 는 C14/C17 처럼 registry 가 deprecated 로 표시한 팩터도 "active" 로
  #   내놓는다 — 그 필드로 거르면 필터가 죽은 채로 통과한다(승계된 팩터가 후보에 섞인다).
  REG <- tryCatch(fromJSON(file.path(root, ".cache/factor_db/factor_registry.json"),
                           simplifyVector = FALSE), error = function(e) list())
  suppressMessages(library(arrow))
  # ★mmap = FALSE — 판독 중 같은 경로 쓰기(야간 리프레시)를 막지 않는다(arrow mmap 잠금 전례 · 09-23)
  IC <- as.data.table(arrow::read_parquet(ic_p, mmap = FALSE))
  setnames(IC, old = intersect(names(IC), c("Factor_Name", "IC", "Date")),
           new = intersect(names(IC), c("Factor_Name", "IC", "Date")))
  IC[, Factor_Name := as.character(Factor_Name)]
  IC[, Date := as.Date(Date)]
  ic_names <- unique(as.character(IC$Factor_Name))   # 자격(이력 존재)은 분류 — as-of 와 무관
  # ★as-of 절단 (C14: IC 접근은 Usable_Date <= 결정 시점) — 순위·tier·상관은 이 표본만 본다
  if (!is.na(A$date)) {
    if (!("Usable_Date" %in% names(IC)))
      stop("[rf_factor_arms] IC 에 Usable_Date 열이 없다 — as-of 절단 불가(C14): ", ic_p)
    IC[, Usable_Date := as.Date(Usable_Date)]
    IC <- IC[!is.na(Usable_Date) & Usable_Date <= A$date]
  }

  ids <- names(EV)
  keep <- vapply(ids, function(f) {
    e <- EV[[f]]
    .lc <- as.character(((REG[[f]] %||% list())$lifecycle %||% list())$status %||%
                        (e$lifecycle_status %||% "active"))
    if (!identical(.lc, "active")) return(FALSE)
    if (is.null(REG[[f]])) return(FALSE)   # registry 에서 빠진 것(입력 테이블 위생 등)은 팩터가 아니다
    if (!(f %in% ic_names)) return(FALSE)
    # ★축 판정이 있으면 횡단면만. 없으면(사이드카 미생성) 통과시키되 호출부가 기록한다 —
    #   판정기 부재를 '전부 횡단면'으로 조용히 읽지 않는다.
    ax <- AX[[f]]$panel_axis %||% NA_character_
    is.na(ax) || identical(ax, "cross_sectional")
  }, logical(1))
  # ★PIT 격리 (2026-09-24 · C11 봉쇄) — 격리 목록의 팩터는 후보에서 뺀다(등급·IC·등록부는 그대로).
  #   D32_Beta_VIX · MA01/MA02 는 해외 계열을 관측일로 결합해 시점 오염(판정서 V-08·V-01) — 수리·재빌드 전까지 소비 금지.
  pitq <- .rff_pitq_ids(root)
  keep <- keep & !(ids %in% pitq)

  # ★순위 통계는 전부 as-of 표본에서 — factor_evidence 의 ic_all·ic_screen_tier(전기간·최근 3년 = 미래 정보)는 읽지 않는다.
  pid <- ids[keep]
  IC <- IC[Factor_Name %in% pid]
  # 격자 부재(전표본 라벨 경로)면 최근 창 설정이 없다 → 최근 ICIR 은 NA(부호 일치 조건을 요구하는 tier 는 못 받는다 · 코드에 창을 박지 않는다)
  S <- .rff_ic_stats(IC, (A$cfg %||% list())$recent_icir_days, (A$cfg %||% list())$recent_icir_min_n)
  rule <- .rff_tier_rule(EVJ)
  pool <- data.table(
    id = pid,
    category = vapply(pid, function(f) as.character(EV[[f]]$category %||% "unknown"), character(1)))
  pool <- merge(pool, S, by.x = "id", by.y = "Factor_Name", all.x = TRUE, sort = FALSE)
  pool[is.na(n_asof), n_asof := 0L]
  pool[, tier := .rff_tier_of(ic_asof, icir3_asof, n_asof, rule)]
  mn <- (A$cfg %||% list())$min_ic_months %||% 1L
  pool[, rankable := is.finite(ic_asof) & n_asof >= mn]
  pool <- pool[match(pid, id)]
  list(pool = pool, IC = IC,
       excluded_no_ic = setdiff(ids, ic_names),
       excluded_axis  = Filter(function(f) {
         ax <- AX[[f]]$panel_axis %||% NA_character_
         !is.na(ax) && !identical(ax, "cross_sectional") }, ids),
       axis_available = length(AX) > 0L,
       excluded_pit = intersect(ids, pitq),
       # asof = 선정 통계 창의 끝(구판은 IC 최신 형성일이었다 — 그게 전표본의 증거였다)
       asof = if (is.na(A$date)) "full_sample" else format(A$date),
       asof_date = A$date, asof_source = A$source, selection_basis = A$basis,
       ic_max_usable = if (nrow(IC) && "Usable_Date" %in% names(IC)) format(max(IC$Usable_Date, na.rm = TRUE)) else NA_character_,
       tier_levels = if (is.null(rule)) character(0) else rule$levels,
       min_ic_months = mn,
       n_unrankable = sum(!pool$rankable))
}

#' IC 시계열 상관행렬 (Factor_Name x Date 피벗)
#' ★고아 사본(.cache/ic_matrix_expanding.parquet, 2026-06-08 · 생산자 없음)을 쓰지 않는다.
#'   정본 factor_ic_monthly 에서 **매 배치 새로 만든다** — 매일 갱신되는 것이 정본이다.
#' ★asof(날짜)를 주면 `Usable_Date <= asof` 행만 쓴다(C14) — 호출자가 절단한 IC 를 넘겨도 다시 절단한다(멱등).
#'   asof NULL = 호출자가 절단을 보증(rf_factor_pool 반환 IC) · NA = 절단 없음(순수 계산기 — 결정 시점을 모른다).
#'   ★운영 호출은 rf_pick_factor_sets 한 곳뿐이고 그 asof 는 상한 가드를 통과한 P$asof_date 다(R3 · 2026-09-25).
rf_ic_cormat <- function(IC, ids, asof = NULL) {
  if (!is.null(asof) && length(asof) == 1L && !is.na(asof)) {
    if (!("Usable_Date" %in% names(IC))) stop("[rf_factor_arms] rf_ic_cormat — IC 에 Usable_Date 없음(as-of 절단 불가 · C14)")
    IC <- IC[!is.na(Usable_Date) & as.Date(Usable_Date) <= as.Date(asof)]
  }
  D <- IC[Factor_Name %in% ids, .(Factor_Name, Date, IC)]
  W <- dcast(D, Date ~ Factor_Name, value.var = "IC", fun.aggregate = function(z) z[1])
  M <- as.matrix(W[, -1L, with = FALSE])
  suppressWarnings(stats::cor(M, use = "pairwise.complete.obs"))
}

#' B1 팩터 집합 n개 선정
#' @param n 뽑을 칸 수
#' @param exclude 이미 측정한 팩터 집합 서명(문자 벡터) — 같은 조합을 다시 재지 않는다
#' @param seed_offset 시드 회전 오프셋(원장 누적 entry 수). 결정론 — 판단 없음
#' @param depths 각 칸의 결합 깊이. 기본 1..n (사슬의 접두 집합)
#' @param fallback_paper 계열 맵에 없는 계열용 근거 논문(그 entry 의 기저 논문)
#' @param asof 선정 통계 창의 끝 — NULL = 격자 fixed_axes.start_date (rf_factor_pool 참조 · 결정 시점 뒤·NA·미래 = stop)
rf_pick_factor_sets <- function(n = 5L, exclude = character(0), seed_offset = 0L,
                                depths = NULL, fallback_paper = NULL, root = .RFF_ROOT, asof = NULL) {
  P <- rf_factor_pool(root, asof = asof)
  # ★순위를 매길 as-of 표본이 있는 팩터만 사슬 후보(풀 자격은 그대로 — 설계 재료는 전 풀을 본다)
  pool <- P$pool[rankable == TRUE]
  if (!nrow(pool)) return(NULL)
  depths <- depths %||% seq_len(n)
  depths <- as.integer(depths)[seq_len(min(n, length(depths)))]
  maxd <- max(depths)

  # ── 정렬: as-of tier 우선(어휘 = factor_evidence 선언 · S1 이 앞), 그 안에서 as-of |IC| 내림차순 ──
  #   ★구판 match(tier, A..E) 는 실제 어휘(S1/S2/S3)와 안 맞아 전부 99 였다 — 어휘를 리터럴로 쓰지 않는다.
  .lv <- P$tier_levels
  pool[, .tk := if (length(.lv)) match(tier, .lv) else NA_integer_]
  pool[is.na(.tk), .tk := length(.lv) + 1L]
  pool[, .absic := abs(ic_asof)]
  setorderv(pool, c(".tk", ".absic", "id"), c(1L, -1L, 1L), na.last = TRUE)

  # ── ★시드 회전 = **계열 라운드로빈** ────────────────────────────────────────
  #   단순히 정렬 순서대로 오프셋을 밀면 큰 계열이 상위를 점유해 연속 entry 가 같은 계열에서만
  #   출발한다(실측 2026-09-01: offset 0/1/2 가 전부 defense — 58종이 상위를 먹었다).
  #   계열 안 순위로 먼저 묶고 계열을 돌면, 연속 entry 가 **다른 계열에서** 출발한다.
  pool[, .rk := seq_len(.N), by = category]
  fam_order <- unique(pool[order(.tk, -.absic), category])       # 계열 자체는 최고 팩터 순
  pool[, .fo := match(category, fam_order)]
  setorderv(pool, c(".rk", ".fo"), c(1L, 1L))                    # 각 계열 1위들 → 2위들 → …
  k <- (as.integer(seed_offset) %% nrow(pool)) + 1L
  seed_id <- pool$id[k]

  R <- rf_ic_cormat(P$IC, pool$id, asof = P$asof_date)   # as-of 상관(C14) — 전표본 라벨 경로면 NA = 절단 없음
  have <- colnames(R)
  if (!(seed_id %in% have)) {                      # 상관행렬에 없으면 다음 후보로
    alt <- pool$id[pool$id %in% have]
    if (!length(alt)) return(NULL)
    seed_id <- alt[((as.integer(seed_offset)) %% length(alt)) + 1L]
  }

  # ── ③ 직교 사슬 (계열 중복 금지) ────────────────────────────────────────────
  chosen <- seed_id
  fams   <- pool[id == seed_id, category]
  rho_tr <- numeric(0)
  while (length(chosen) < maxd) {
    cand <- pool[!(id %in% chosen) & !(category %in% fams) & id %in% have, id]
    if (!length(cand)) break
    mx <- vapply(cand, function(c1) {
      v <- abs(R[c1, chosen, drop = TRUE]); v <- v[is.finite(v)]
      if (!length(v)) 1 else max(v) }, numeric(1))
    pick <- cand[which.min(mx)]
    rho_tr <- c(rho_tr, unname(mx[which.min(mx)]))
    chosen <- c(chosen, pick)
    fams   <- c(fams, pool[id == pick, category])
  }
  if (!length(chosen)) return(NULL)

  # ── ④ 셀 = 접두 집합 ───────────────────────────────────────────────────────
  .sig <- function(ids) paste(sort(ids), collapse = "+")
  cells <- list(); used_d <- integer(0)
  for (d in depths) {
    dd <- min(d, length(chosen))
    ids <- chosen[seq_len(dd)]
    if (.sig(ids) %in% exclude) next
    if (dd %in% used_d) next                       # 같은 깊이 두 번 만들지 않는다
    used_d <- c(used_d, dd)
    fam_d <- unique(pool[id %in% ids, category])
    # ★2026-09-02 수리 — 첫 계열 하나가 아니라 계열 **전부**의 논문을 낸다(사연은 rf_root_papers_for 주석).
    #   root_paper(단수) 는 첫 계열 논문으로 유지 — 격자 스냅샷·검사 §4 하위호환. 러너의 source_paper 는
    #   기저 논문을 쓰므로 이 단수 값은 폴백일 뿐이다.
    .rpz <- rf_root_papers_for(ids, base_paper = NULL, families = fam_d, root = root)
    rp <- if (length(.rpz$papers)) .rpz$papers[[1L]] else fallback_paper
    cells[[length(cells) + 1L]] <- list(
      code = sprintf("B1_%d", length(cells) + 1L),
      label = sprintf("%d팩터 직교(%s)", dd, paste(fam_d, collapse = "+")),
      factors = lapply(ids, function(i) list(kind = "db", id = i)),
      basis = sprintf(paste0("IC 시계열 상관 최소화 사슬 · 깊이 %d · 계열 %d종(중복 0) · ",
                             "max|rho| %s · 시드 %s(회전 오프셋 %d) · 후보 %d종 · 선정 통계 %s(as-of %s · %s · ",
                             "IC 가용 ~%s · 순위 표본 %d개월 미만 %d종 제외)"),
                      dd, length(fam_d),
                      if (dd > 1L) sprintf("%.3f", max(rho_tr[seq_len(dd - 1L)])) else "n/a",
                      seed_id, as.integer(seed_offset), nrow(pool), P$selection_basis, P$asof, P$asof_source,
                      P$ic_max_usable %||% "NA", as.integer(P$min_ic_months), as.integer(P$n_unrankable)),
      selection_basis = P$selection_basis,
      selection_asof = P$asof,
      root_paper = rp,
      root_papers = .rpz$papers,
      unmapped_families = .rpz$unmapped_families,
      root_papers_note = if (length(.rpz$unmapped_families))
        sprintf("★논문 매핑 없는 계열 %s — 근거 의무의 공백(.RFF_FAMILY_PAPER 보강 대상)",
                paste(.rpz$unmapped_families, collapse = "+")) else "",
      note = sprintf(paste0("등록부 선정 — 격자가 팩터를 갖지 않고 factor_evidence+factor_ic_monthly 를 ",
                            "소비한다. IC 이력 부재로 제외 %d종 · 횡단면 아님으로 제외 %d종%s. ",
                            "★선정은 IC 시계열 상관, 결합은 횡단면 rank-Z — 다른 직교성이다."),
                     length(P$excluded_no_ic), length(P$excluded_axis),
                     if (P$axis_available) "" else " (★축 판정 사이드카 부재 — 축 필터 미적용)"))
  }
  if (!length(cells)) return(NULL)
  list(cells = cells, picked_ids = chosen, seed_id = seed_id, seed_offset = as.integer(seed_offset),
       n_available = nrow(pool), excluded_no_ic = P$excluded_no_ic,
       excluded_axis = P$excluded_axis, axis_available = P$axis_available,
       excluded_pit = P$excluded_pit,
       max_rho = if (length(rho_tr)) max(rho_tr) else NA_real_, substrate_asof = P$asof,
       selection_basis = P$selection_basis, asof_source = P$asof_source, ic_max_usable = P$ic_max_usable,
       n_pool = nrow(P$pool), n_unrankable = P$n_unrankable)
}

cat("[rf_factor_arms.R] Loaded — rf_factor_pool(root, asof) / rf_ic_cormat(IC, ids, asof) / rf_pick_factor_sets(n, exclude, seed_offset, asof) / rf_root_papers_for(spec|ids, base, cell)\n")
