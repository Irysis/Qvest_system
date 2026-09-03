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

#' 후보 풀 — 횡단면 ∩ IC 이력 ∩ active
rf_factor_pool <- function(root = .RFF_ROOT) {
  ev_p <- file.path(root, "06_Registry/factor_evidence.json")
  ax_p <- file.path(root, "06_Registry/factor_panel_axis.json")
  ic_p <- file.path(root, ".cache/factor_db/factor_ic_monthly.parquet")
  for (p in c(ev_p, ic_p)) if (!file.exists(p)) stop("[rf_factor_arms] 부재: ", p)
  EV <- fromJSON(ev_p, simplifyVector = FALSE)$factors
  AX <- if (file.exists(ax_p)) fromJSON(ax_p, simplifyVector = FALSE)$factors else list()
  # ★lifecycle 은 **registry 정본**에서 읽는다(2026-09-01 수리). factor_evidence 사이드카의
  #   lifecycle_status 는 C14/C17 처럼 registry 가 deprecated 로 표시한 팩터도 "active" 로
  #   내놓는다 — 그 필드로 거르면 필터가 죽은 채로 통과한다(승계된 팩터가 후보에 섞인다).
  REG <- tryCatch(fromJSON(file.path(root, ".cache/factor_db/factor_registry.json"),
                           simplifyVector = FALSE), error = function(e) list())
  suppressMessages(library(arrow))
  IC <- as.data.table(arrow::read_parquet(ic_p))
  setnames(IC, old = intersect(names(IC), c("Factor_Name", "IC", "Date")),
           new = intersect(names(IC), c("Factor_Name", "IC", "Date")))
  ic_names <- unique(as.character(IC$Factor_Name))

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

  pool <- data.table(
    id = ids[keep],
    category = vapply(ids[keep], function(f) as.character(EV[[f]]$category %||% "unknown"), character(1)),
    ic_all   = vapply(ids[keep], function(f) as.numeric(EV[[f]]$ic_all %||% NA_real_), numeric(1)),
    tier     = vapply(ids[keep], function(f) as.character(EV[[f]]$ic_screen_tier %||% "Z"), character(1)))
  list(pool = pool, IC = IC,
       excluded_no_ic = setdiff(ids, ic_names),
       excluded_axis  = Filter(function(f) {
         ax <- AX[[f]]$panel_axis %||% NA_character_
         !is.na(ax) && !identical(ax, "cross_sectional") }, ids),
       axis_available = length(AX) > 0L,
       asof = as.character(max(IC$Date, na.rm = TRUE)))
}

#' IC 시계열 상관행렬 (Factor_Name x Date 피벗)
#' ★고아 사본(.cache/ic_matrix_expanding.parquet, 2026-06-08 · 생산자 없음)을 쓰지 않는다.
#'   정본 factor_ic_monthly 에서 **매 배치 새로 만든다** — 매일 갱신되는 것이 정본이다.
rf_ic_cormat <- function(IC, ids) {
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
rf_pick_factor_sets <- function(n = 5L, exclude = character(0), seed_offset = 0L,
                                depths = NULL, fallback_paper = NULL, root = .RFF_ROOT) {
  P <- rf_factor_pool(root)
  pool <- P$pool
  if (!nrow(pool)) return(NULL)
  depths <- depths %||% seq_len(n)
  depths <- as.integer(depths)[seq_len(min(n, length(depths)))]
  maxd <- max(depths)

  # ── 정렬: tier 우선, 그 안에서 |ic_all| 내림차순 ────────────────────────────
  pool[, .tk := match(tier, c("A", "B", "C", "D", "E"))]
  pool[is.na(.tk), .tk := 99L]
  pool[, .absic := abs(ic_all)]
  setorderv(pool, c(".tk", ".absic"), c(1L, -1L), na.last = TRUE)

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

  R <- rf_ic_cormat(P$IC, pool$id)
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
                             "max|rho| %s · 시드 %s(회전 오프셋 %d) · 후보 %d종 · substrate %s"),
                      dd, length(fam_d),
                      if (dd > 1L) sprintf("%.3f", max(rho_tr[seq_len(dd - 1L)])) else "n/a",
                      seed_id, as.integer(seed_offset), nrow(pool), P$asof),
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
       max_rho = if (length(rho_tr)) max(rho_tr) else NA_real_, substrate_asof = P$asof)
}

cat("[rf_factor_arms.R] Loaded — rf_factor_pool() / rf_ic_cormat() / rf_pick_factor_sets(n, exclude, seed_offset) / rf_root_papers_for(spec|ids, base, cell)\n")
