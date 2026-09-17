#!/usr/bin/env Rscript
#==============================================================================
# rf_block_design.R — **다음 블록 설계**의 카탈로그 제공·검증·소비 (도훈 지시 ④ · 2026-09-04)
#
# 왜: 블록 끝 기전 에이전트가 처방을 냈지만 **읽는 자가 없었다**. entry 안의 LLM 설계 지점은
#   B1 하나이고 그건 맨 처음에 돈다 — 교훈이 아직 없을 때. 나머지 블록은 규칙 선정이라
#   처방이 어디에도 안 갔다. 이 저장소가 반복해서 밟은 형태(생산자만 있고 소비자가 없음)다.
#
# 구조 선택 — 블록마다 설계 LLM 을 새로 붙이지 않는다:
#   기전 에이전트가 **이미** 그 블록 끝에 돌고, 필요한 재료(측정표·누적 교훈·앞 처방)를
#   전부 들고 있다. 거기에 다음 블록 카탈로그만 얹으면 진단·처방·설계가 한 산출물이 된다.
#   ⇒ 추가 LLM 호출 0회. 그리고 **처방과 설계가 같은 물건**이라 어긋날 자리가 없다.
#
# 설계 대상 = B2(비중) · B3(유니버스) · B5(오버레이). B1 은 진입 시 별도 설계(rf_b1_design).
#   ★B4(결합)는 설계하지 않는다 — LOO 는 계약이다. 2026-09-04 실측이 그 이유를 보여줬다:
#     커버리지로 3칸이 막혀 남은 두 칸이 LOO 가 아니게 되자 기전 에이전트가 스스로
#     "이 블록의 가장 큰 신호는 귀속 불가" 라고 적었다. 설계로 부분집합을 흔들면 그게 상시화된다.
#
# 경계: LLM 은 목록을 고를 뿐이고, 실재성·중복·양립성은 아래 검증이 재도출한다.
#   검증 실패 = 설계 폐기 + 규칙 선정 폴백(조용한 통과 없음).
#
# ★2026-09-17 스택 설계 (WP-Z · 횡단면 오버레이 축 강화):
#   B5 설계 칸은 `picks: [id, ...]`(스택) 또는 구판 `pick`(단일)을 받는다. **B5 만** 2층 이상을 허용한다 —
#   엔진은 층 노출을 곱으로 합성하고(rf_cell_engine .ov_compose) 비중·유니버스는 그런 합성이 없다.
#   검증 축(전부 재도출): ①id 실재 ∧ status=active(★구판 B5 카탈로그는 status 를 안 봤다 — 규칙 픽커
#   rf_overlay_arms.R:46 은 active 만 뽑는데 설계 경로는 retired 도 통과시켰다 · 술어가 둘) ②스택 안 같은
#   id·같은 kind 금지 ③층 수 ≤ max_layers(config b5_design.max_layers · 부재 시 3) ④칸끼리 같은 스택 금지
#   (정렬된 id 키 — [A,B] 와 [B,A] 는 같은 칸) ⑤상주 칸(program standing_cells)의 pick 과 같은 스택 금지
#   (상주가 매 세대 이미 잰다) ⑥≤15칸 ⑦label 필수.
#   소비(rfbd_cells): CELL$overlay = 층 리스트 {kind, arm_id} — **단층이면 단수 객체**(기존 서명 불변).
#   빈/무효 칸은 목록에서 **뺀다**(구판은 NULL 원소를 돌려줘 러너가 코드 없는 칸을 만들었다).
#   코드는 설계 위치(i)로 매긴다 — 무효 칸이 빠져도 뒤 칸의 코드는 밀리지 않는다(코드 = 그 설계 칸의 이름).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RFBD_BLOCKS <- c("B2", "B3", "B5")
RFBD_MAX_LAYERS_DEFAULT <- 3L
.rfbd_dir <- function(root) file.path(root, ".cache/rf_block_design")
rfbd_path <- function(root, base_id, block)
  file.path(.rfbd_dir(root), sprintf("%s_%s.json", substr(base_id, 1, 50), block))

#' 상주 칸 — 격자 정본(reinforce_program.json::standing_cells). 없으면 빈 목록.
#'   [{code, block, label, overlay_pick}] · 상주 칸은 설계·규칙 선정과 무관하게 매 세대 도는 칸이다.
rfbd_standing_cells <- function(root) {
  g <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                error = function(e) NULL)
  sc <- g$standing_cells %||% list()
  Filter(function(x) is.list(x) && nzchar(as.character(x$code %||% "")), sc)
}
#' 상주 칸의 오버레이 arm id 들(제외 목록의 정본 — 지도·승격·설계 검증이 전부 이걸 읽는다)
rfbd_standing_picks <- function(root) {
  v <- as.character(unlist(lapply(rfbd_standing_cells(root), function(x) x$overlay_pick %||% "")))
  unique(v[nzchar(v)])
}
#' 스택 층 수 상한 — config b5_design.max_layers · 부재/비정상이면 3.
rfbd_max_layers <- function(root) {
  cfg <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE),
                  error = function(e) NULL)
  v <- suppressWarnings(as.integer((cfg$b5_design %||% list())$max_layers %||% NA_integer_))
  if (length(v) != 1L || is.na(v) || v < 1L) RFBD_MAX_LAYERS_DEFAULT else v
}
#' 설계 칸 하나의 id 목록 — picks(스택) 우선, 없으면 pick(단일). 빈 문자열은 버린다.
rfbd_cell_picks <- function(ce) {
  v <- as.character(unlist(ce$picks %||% list()))
  v <- v[!is.na(v) & nzchar(v)]
  if (!length(v)) { v <- as.character(ce$pick %||% "")[1]; v <- v[!is.na(v) & nzchar(v)] }
  v
}
#' 스택의 동일성 키 — 정렬된 id 를 "+" 로. 단일이면 그 id 자체.
rfbd_stack_key <- function(ids) paste(sort(unique(as.character(ids))), collapse = "+")

# B5 원장부 — status 를 **보존**해서 읽는다(검증 사유에 "retired" 를 적기 위해). 소비용 카탈로그는 아래에서 거른다.
.rfbd_b5_raw <- function(root) {
  d <- tryCatch(fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE),
                error = function(e) NULL)
  ## ★kind 를 버리면 안 된다 — 엔진은 overlay$kind 로 overlay_arms/<kind>.R 을 찾는다.
  ##   실사고 2026-09-04 19:18: 설계 경로가 overlay=list(arm_id=id) 만 내서 B5 다섯 칸이
  ##   전부 "$ operator is invalid for atomic vectors" 로 죽었다. 정상 경로
  ##   (rf_pick_overlay_arms)는 list(kind = r$kind, arm_id = r$id) 를 낸다 — 둘이 달랐다.
  lapply(d$arms %||% list(), function(x) list(id = as.character(x$id %||% ""),
                                              kind = as.character(x$kind %||% x$id %||% ""),
                                              basis = as.character(x$basis %||% ""),
                                              label = as.character(x$basis %||% ""),
                                              family = as.character(x$family %||% ""),
                                              status = as.character(x$status %||% "active")))
}

#' 그 블록이 고를 수 있는 것 — 카탈로그를 **정본에서** 읽는다(재구현 금지)
rfbd_catalog <- function(block, root) {
  if (identical(block, "B2")) {
    ## ★엔진과 **같은 함수·같은 기본값** (2026-09-05). 구판은 JSON 을 직접 읽어 status != retracted 만
    ##   걸렀는데, 엔진(rf_cell_engine)은 weight_catalog_arms(min_status = "active") 를 읽는다.
    ##   술어가 둘이라 unverified 생성 arm(gen:lean_score_tilt__shr_lw_nls)이 설계를 통과하고 엔진에서
    ##   "카탈로그 arm 부재" 로 죽었다 — 실사고 promo2 B2_10, 설계의 대조쌍(추정오차 축) 칸이 미측정.
    ##   "실행 가능한 arm 인가" 의 정본은 엔진이 부르는 함수 하나다. 적재 실패 = 빈 목록 = 설계 전체 기각
    ##   (규칙 선정 폴백) — 조용한 통과가 아니라 조용한 거부 쪽으로 넘어진다.
    a <- tryCatch({
      invisible(capture.output(suppressMessages(
        source(file.path(root, "02_Infrastructure/portfolio/weight_catalog.R"), local = TRUE))))
      weight_catalog_arms(quiet = TRUE)
    }, error = function(e) NULL)
    if (is.null(a) || !NROW(a)) return(list())
    return(lapply(seq_len(NROW(a)), function(i) list(
      id     = as.character(a$catalog_id[i]),
      label  = as.character(if ("label"  %in% names(a)) a$label[i]  else a$catalog_id[i]),
      family = as.character(if ("family" %in% names(a)) a$family[i] else ""))))
  }
  if (identical(block, "B5")) {
    ## ★status=active 만 (2026-09-17). 규칙 픽커(rf_overlay_arms.R)와 같은 술어 — retired arm 은 설계로도 못 들어온다.
    return(Filter(function(x) identical(x$status, "active") && nzchar(x$id), .rfbd_b5_raw(root)))
  }
  if (identical(block, "B3")) {
    g <- tryCatch(fromJSON(file.path(root, "06_Registry/reinforce_program.json"), simplifyVector = FALSE),
                  error = function(e) NULL)
    out <- list()
    for (b in g$blocks %||% list()) if (identical(b$id, "B3"))
      for (cl in b$cells %||% list())
        out[[length(out) + 1L]] <- list(id = as.character(cl$code %||% ""),
                                        label = as.character(cl$label %||% ""),
                                        universe = cl$universe)
    return(out)
  }
  list()
}

#' 설계 1건 검증 — 실재성·중복·양립성. 진술은 근거가 아니다.
#' @return TRUE 또는 사유 문자열
rfbd_verify <- function(design, block, root, max_cells = 15L) {
  cs <- design$cells %||% list()
  if (!length(cs)) return("cells 0건")
  if (length(cs) > max_cells) return(sprintf("cells %d > 상한 %d", length(cs), max_cells))
  cat_map <- rfbd_catalog(block, root)
  cat_ids <- vapply(cat_map, function(x) as.character(x$id), character(1))
  .kind_of <- function(id) { k <- which(cat_ids == id); if (length(k)) as.character(cat_map[[k[1]]]$kind %||% "") else "" }
  is_b5 <- identical(block, "B5")
  max_layers <- if (is_b5) rfbd_max_layers(root) else 1L
  raw_b5 <- if (is_b5) .rfbd_b5_raw(root) else list()
  standing_keys <- if (is_b5) vapply(rfbd_standing_picks(root), rfbd_stack_key, character(1)) else character(0)
  seen_keys <- character(0)
  for (i in seq_along(cs)) {
    ce <- cs[[i]]
    ids <- rfbd_cell_picks(ce)
    if (!length(ids)) return(sprintf("cell %d: pick 없음", i))
    if (length(ids) > 1L && !is_b5)
      return(sprintf("cell %d: picks %d개 — %s 는 단일 pick 만 받는다(스택은 B5 오버레이 전용)", i, length(ids), block))
    if (length(ids) > max_layers)
      return(sprintf("cell %d: 층 %d > 상한 %d (b5_design.max_layers)", i, length(ids), max_layers))
    if (anyDuplicated(ids)) return(sprintf("cell %d: 스택 안 같은 id 두 번(%s) — 이중 축소", i, ids[duplicated(ids)][1]))
    for (id in ids) if (!(id %in% cat_ids)) {
      ## B5 는 사유를 가른다 — "없다" 와 "있는데 retired" 는 다른 사건이다(설계자가 고칠 방향이 다르다).
      if (is_b5) { r <- Filter(function(x) identical(x$id, id), raw_b5)
        if (length(r)) return(sprintf("cell %d: %s 는 status=%s — active 만 설계할 수 있다", i, id, r[[1]]$status)) }
      return(sprintf("cell %d: 카탈로그에 없는 항목 %s", i, id))
    }
    if (is_b5 && length(ids) > 1L) {
      kd <- vapply(ids, .kind_of, character(1))
      if (anyDuplicated(kd)) return(sprintf("cell %d: 스택 안 같은 kind 두 층(%s) — 엔진은 kind 로 arm 파일을 찾는다", i, kd[duplicated(kd)][1]))
    }
    key <- rfbd_stack_key(ids)
    if (key %in% seen_keys) return(sprintf("cell %d: 앞 칸과 같은 항목(%s) — 칸 낭비", i, key))
    if (key %in% standing_keys) return(sprintf("cell %d: 상주 칸과 같은 스택(%s) — 상주가 매 세대 이미 잰다", i, key))
    seen_keys <- c(seen_keys, key)
    if (!nzchar(as.character(ce$label %||% ""))) return(sprintf("cell %d: label 없음", i))
  }
  TRUE
}

#' 설계 JSON → 러너 셀 목록 (규칙 선정기 산출과 같은 형태). 무효 칸은 목록에서 뺀다(NULL 원소 없음).
rfbd_cells <- function(root, base_id, block) {
  p <- rfbd_path(root, base_id, block)
  if (!file.exists(p)) return(NULL)
  D <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(D) || !length(D$cells %||% list())) return(NULL)
  cat_map <- rfbd_catalog(block, root)
  .find <- function(id) { k <- which(vapply(cat_map, function(x) identical(as.character(x$id), id), logical(1)))
                          if (length(k)) cat_map[[k[1]]] else NULL }
  # 코드는 격자 번호를 유지한다 — 블록 안 n번째 = <block>_<시작번호+n-1>
  .base_n <- switch(block, B2 = 6L, B3 = 11L, B5 = 16L, 1L)
  out <- lapply(seq_along(D$cells), function(i) {
    ce <- D$cells[[i]]; ids <- rfbd_cell_picks(ce)
    if (!length(ids)) return(NULL)
    id <- ids[1]; cm <- .find(id)
    ## ★코드는 pick 이 이 블록의 격자 코드면 **그 코드**다 (2026-09-05). 구판은 전 블록을 위치로 매겼다 —
    ##   B2/B5 는 pick 이 arm id 라 무해했지만 B3 은 pick 자체가 격자 코드(B3_11=KQ150 단독 …)라서
    ##   설계 [B3_12,B3_11,B3_15,B3_14] 가 슬롯 [B3_11..B3_14] 로 밀렸다. 내용은 설계를 따르고 코드만 어긋나
    ##   코드로 대조하는 회피 집행이 **KOSPI200 단독(슬롯 B3_11)** 을 C6 사유로 건너뛰고, 정작 C6 대상인
    ##   KOSDAQ150 단독은 코드 B3_12 로 측정됐다(실사고 promo2 n=16~19 · 예산 1칸 소실). 코드가 스펙을
    ##   가리키지 않으면 코드로 하는 모든 판정이 다른 칸을 때린다.
    .code <- if (length(ids) == 1L && grepl(sprintf("^%s_[0-9]+$", block), id)) id else sprintf("%s_%d", block, .base_n + i - 1L)
    .idtxt <- paste(ids, collapse = " × ")
    out <- list(code = .code,
                label = as.character(ce$label %||% .idtxt),
                basis = sprintf("LLM 설계(블록 전이) · %s · %s", .idtxt,
                                substr(as.character(ce$why %||% D$rationale %||% ""), 1, 200)),
                note = "★설계 산출 — 카탈로그 실재성·중복은 rfbd_verify 가 재도출로 검증했다.")
    ## ★정상 경로(rf_weight_arms)와 **같은 모양** — 엔진은 weighting$catalog_id 를 읽는다.
    ##   구판은 arm= 이라 B2 다섯 칸이 "카탈로그 arm 부재: " 로 전멸했다(2026-09-04 21:11).
    ##   ★B5 에서 같은 병을 고치면서 **형제 분기를 안 봤다** — 같은 함수 안 세 줄이었는데.
    if (identical(block, "B2")) {
      if (is.null(cm)) return(NULL)
      out$weighting <- list(kind = "catalog", catalog_id = id,
                            label = as.character(cm$label %||% id))
    }
    if (identical(block, "B5")) {
      ## ★정상 경로와 **같은 모양**을 낸다. 카탈로그에 없는 id 가 하나라도 있으면 칸을 만들지 않는다 —
      ##   없는 arm 을 지어내지 않는다(rfbd_verify 가 저장 전에 걸렀어도, 저장 뒤 retired 된 arm 은 여기서 걸린다).
      layers <- lapply(ids, function(x) { c1 <- .find(x)
        if (is.null(c1) || !nzchar(as.character(c1$kind %||% ""))) NULL else list(kind = as.character(c1$kind), arm_id = x) })
      if (any(vapply(layers, is.null, logical(1)))) return(NULL)
      ## 단층 = 단수 객체(기존 서명 불변) · 다층 = 층 리스트. 러너는 SPEC$overlay_cell <- CELL$overlay 로 이 칸의 몫을 남긴다.
      out$overlay <- if (length(layers) == 1L) layers[[1]] else layers
    }
    if (identical(block, "B3")) { if (is.null(cm)) return(NULL); out$universe <- cm$universe }
    out
  })
  Filter(Negate(is.null), out)
}

#' 실행된 스펙에서 그 칸의 **자기 축 키**를 읽는다 — 설계 키와 같은 자리에서 비교하기 위해.
#'   B2 = catalog_id(★구판은 weighting$arm 을 읽었는데 스펙은 catalog_id 를 싣는다 — 항상 불일치 → 영구 "ignored")
#'   B5 = 이 칸의 몫(overlay_cell > overlay − carry > 전부)의 정렬 id 키 · arm_id 없는 층은 kind 로
#'   B3 = 유니버스가 카탈로그의 어느 격자 코드와 같은가(없으면 실행 셀 코드)
.rfbd_exec_key <- function(S, block, cat_map, carry = NULL, cell_code = "") {
  if (identical(block, "B2")) {
    w <- S$weighting %||% list()
    return(as.character(w$catalog_id %||% w$arm %||% w$id %||% "")[1])
  }
  if (identical(block, "B5")) {
    L <- if (!is.null(S$overlay_cell)) .rfbd_layers(S$overlay_cell) else {
      L0 <- .rfbd_layers(S$overlay)
      if (is.null(carry)) L0 else {
        ck <- vapply(.rfbd_layers(carry), .rfbd_lkey, character(1))
        L0[!(vapply(L0, .rfbd_lkey, character(1)) %in% ck)] } }
    ids <- vapply(L, function(o) { a <- as.character(o$arm_id %||% ""); if (nzchar(a)) a else as.character(o$kind %||% "") }, character(1))
    ids <- ids[nzchar(ids)]
    return(if (length(ids)) rfbd_stack_key(ids) else "")
  }
  if (identical(block, "B3")) {
    uj <- as.character(toJSON(S$universe %||% list(), auto_unbox = TRUE))
    for (x in cat_map) if (identical(as.character(toJSON(x$universe %||% list(), auto_unbox = TRUE)), uj)) return(as.character(x$id))
    return(as.character(cell_code))
  }
  ""
}
# 층 정규화(단수·리스트·중첩) — rf_spec_sig.R 의 .ov_layers 와 같은 규칙. 이 파일은 단독 source 되므로 여기 둔다.
.rfbd_layers <- function(x) {
  if (is.null(x) || !is.list(x)) return(list())
  if (!is.null(x$kind) || !is.null(x$arm_id)) return(list(x))
  out <- list(); for (z in x) if (is.list(z)) out <- c(out, .rfbd_layers(z)); out
}
.rfbd_lkey <- function(z) paste0(as.character(z$kind %||% ""), "~", as.character(z$arm_id %||% ""))

#' 앞 블록 처방이 **실제로 집행됐는가** — 설계와 실측 셀을 **칸 단위로** 대조한다(도훈 ④ 후반).
#'   ★풀링 금지 (2026-09-17): 구판은 전 시도의 id 를 한 주머니에 모아 "설계 id 가 어디든 있으면 집행" 으로
#'     셌다. 스택 설계 [A×B]·[A×C] 를 실행이 [A]·[B×C] 로 돌려도 주머니 {A,B,C} 가 설계를 덮어 executed 가 된다.
#'     칸의 정체는 스택(정렬 id 키)이지 원소가 아니다.
#' @param carry 그 entry 의 carry$overlay — B5 에서 실행 스펙의 carry 층을 빼기 위해. NULL 이면 원장에서 찾는다.
#' @return list(status = "executed"|"partial"|"ignored"|"no_design", detail = ...)
rfbd_action_status <- function(root, base_id, block, attempts, carry = NULL) {
  p <- rfbd_path(root, base_id, block)
  if (!file.exists(p)) return(list(status = "no_design", detail = "그 블록에 설계가 없었다(규칙 선정)"))
  D <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  want <- vapply(D$cells %||% list(), function(x) { ids <- rfbd_cell_picks(x); if (length(ids)) rfbd_stack_key(ids) else "" }, character(1))
  want <- unique(want[nzchar(want)])
  if (!length(want)) return(list(status = "no_design", detail = "설계에 pick 이 없다"))
  if (is.null(carry) && identical(block, "B5")) carry <- tryCatch({
    led <- fromJSON(file.path(root, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
    e <- Filter(function(x) identical(x$base_id, base_id), led$entries %||% list())
    if (length(e)) (e[[1]]$carry %||% list())$overlay else NULL }, error = function(e) NULL)
  cat_map <- if (identical(block, "B3")) rfbd_catalog("B3", root) else list()
  got <- character(0)
  for (a in attempts %||% list()) {
    cc <- as.character(a$cell_code %||% (a$essence$cell_code %||% ""))[1]
    if (!nzchar(cc) || !startsWith(cc, paste0(block, "_"))) next
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) next
    S <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(S)) next
    got <- c(got, .rfbd_exec_key(S, block, cat_map, carry = carry, cell_code = cc))
  }
  got <- unique(got[nzchar(got)])
  hit <- sum(want %in% got)
  st <- if (hit == length(want)) "executed" else if (hit > 0L) "partial" else "ignored"
  list(status = st, detail = sprintf("설계 %d건 중 %d건 집행 (설계: %s / 실측: %s)",
       length(want), hit, paste(want, collapse = ","), paste(got, collapse = ",")))
}
