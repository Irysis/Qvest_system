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
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RFBD_BLOCKS <- c("B2", "B3", "B5")
.rfbd_dir <- function(root) file.path(root, ".cache/rf_block_design")
rfbd_path <- function(root, base_id, block)
  file.path(.rfbd_dir(root), sprintf("%s_%s.json", substr(base_id, 1, 50), block))

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
    d <- tryCatch(fromJSON(file.path(root, "06_Registry/overlay_catalog.json"), simplifyVector = FALSE),
                  error = function(e) NULL)
    ## ★kind 를 버리면 안 된다 — 엔진은 overlay$kind 로 overlay_arms/<kind>.R 을 찾는다.
    ##   실사고 2026-09-04 19:18: 설계 경로가 overlay=list(arm_id=id) 만 내서 B5 다섯 칸이
    ##   전부 "$ operator is invalid for atomic vectors" 로 죽었다. 정상 경로
    ##   (rf_pick_overlay_arms)는 list(kind = r$kind, arm_id = r$id) 를 낸다 — 둘이 달랐다.
    return(lapply(d$arms %||% list(), function(x) list(id = as.character(x$id %||% ""),
                                                       kind = as.character(x$kind %||% x$id %||% ""),
                                                       basis = as.character(x$basis %||% ""),
                                                       label = as.character(x$basis %||% ""),
                                                       family = as.character(x$family %||% ""))))
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
  cat_ids <- vapply(rfbd_catalog(block, root), function(x) as.character(x$id), character(1))
  seen <- character(0)
  for (i in seq_along(cs)) {
    ce <- cs[[i]]
    id <- as.character(ce$pick %||% "")[1]
    if (!nzchar(id)) return(sprintf("cell %d: pick 없음", i))
    if (!(id %in% cat_ids)) return(sprintf("cell %d: 카탈로그에 없는 항목 %s", i, id))
    if (id %in% seen) return(sprintf("cell %d: 앞 칸과 같은 항목(%s) — 칸 낭비", i, id))
    seen <- c(seen, id)
    if (!nzchar(as.character(ce$label %||% ""))) return(sprintf("cell %d: label 없음", i))
  }
  TRUE
}

#' 설계 JSON → 러너 셀 목록 (규칙 선정기 산출과 같은 형태)
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
  lapply(seq_along(D$cells), function(i) {
    ce <- D$cells[[i]]; id <- as.character(ce$pick %||% "")[1]; cm <- .find(id)
    out <- list(code = sprintf("%s_%d", block, .base_n + i - 1L),
                label = as.character(ce$label %||% id),
                basis = sprintf("LLM 설계(블록 전이) · %s · %s", id,
                                substr(as.character(ce$why %||% D$rationale %||% ""), 1, 200)),
                note = "★설계 산출 — 카탈로그 실재성·중복은 rfbd_verify 가 재도출로 검증했다.")
    ## ★정상 경로(rf_weight_arms)와 **같은 모양** — 엔진은 weighting$catalog_id 를 읽는다.
    ##   구판은 arm= 이라 B2 다섯 칸이 "카탈로그 arm 부재: " 로 전멸했다(2026-09-04 21:11).
    ##   ★B5 에서 같은 병을 고치면서 **형제 분기를 안 봤다** — 같은 함수 안 세 줄이었는데.
    if (identical(block, "B2"))
      out$weighting <- list(kind = "catalog", catalog_id = id,
                            label = as.character(cm$label %||% id))
    if (identical(block, "B5")) {
      ## ★정상 경로와 **같은 모양**을 낸다. 카탈로그에 없는 id 면 NULL 로 둠 —
      ##   그러면 rfbd_verify 가 재도출로 걸러낸다(없는 arm 을 지어내지 않는다).
      if (is.null(cm) || !nzchar(as.character(cm$kind %||% ""))) return(NULL)
      out$overlay <- list(kind = as.character(cm$kind), arm_id = id)
    }
    if (identical(block, "B3")) out$universe  <- cm$universe
    out
  })
}

#' 앞 블록 처방이 **실제로 집행됐는가** — 설계와 실측 셀을 대조한다(도훈 ④ 후반).
#' @return list(status = "executed"|"partial"|"ignored"|"no_design", detail = ...)
rfbd_action_status <- function(root, base_id, block, attempts) {
  p <- rfbd_path(root, base_id, block)
  if (!file.exists(p)) return(list(status = "no_design", detail = "그 블록에 설계가 없었다(규칙 선정)"))
  D <- tryCatch(fromJSON(p, simplifyVector = FALSE), error = function(e) NULL)
  want <- vapply(D$cells %||% list(), function(x) as.character(x$pick %||% "")[1], character(1))
  want <- want[nzchar(want)]
  if (!length(want)) return(list(status = "no_design", detail = "설계에 pick 이 없다"))
  got <- character(0)
  for (a in attempts %||% list()) {
    cc <- as.character(a$cell_code %||% (a$essence$cell_code %||% ""))[1]
    if (!nzchar(cc) || !startsWith(cc, paste0(block, "_"))) next
    sp <- a$essence$spec
    if (is.null(sp) || !nzchar(sp) || !file.exists(sp)) next
    S <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(S)) next
    got <- c(got, if (identical(block, "B2")) as.character((S$weighting %||% list())$arm %||% "")
                  else if (identical(block, "B5")) {
                    ov <- S$overlay; ovl <- if (is.null(ov)) list() else if (!is.null(ov$arm_id)) list(ov) else ov
                    vapply(ovl, function(o) as.character(o$arm_id %||% ""), character(1))
                  } else as.character((S$universe %||% list())$kind %||% ""))
  }
  got <- unique(got[nzchar(got)])
  hit <- sum(want %in% got)
  st <- if (hit == length(want)) "executed" else if (hit > 0L) "partial" else "ignored"
  list(status = st, detail = sprintf("설계 %d건 중 %d건 집행 (설계: %s / 실측: %s)",
       length(want), hit, paste(want, collapse = ","), paste(got, collapse = ",")))
}
