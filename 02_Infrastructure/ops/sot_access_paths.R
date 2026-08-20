#==============================================================================
# sot_access_paths.R — 정본(JSON) 소비 경로를 **AST 로** 추출한다
#
# 배경 (2026-08-20 세션, 실측):
#   "constraint_defaults.json 의 어느 필드가 실제로 소비되는가" 를 토큰 grep 으로 재려다
#   **같은 부류로 6번 실패**했다:
#     ① 리프 이름 grep + CRLF 오염 → 소비율이 아니라 **줄바꿈 방식**을 쟀다(81/100 허위)
#     ② 리프 grep 정정 → 블록 단위 소비를 못 봄(40/100 여전히 허위)
#     ③ 블록 이름 grep → `severity` 293건·`metrics` 718건 = 일반 영단어 오탐
#     ④ 모듈명 매칭을 필드 소비로 오독(`[pit_enforcement] Loading` 은 자기 이름)
#     ⑤ 로드 호출과 경로 리터럴이 같은 줄이라 가정 → 상수 경유(WT_CONSTRAINT_DEFAULTS) 누락
#     ⑥ 변수 할당이 문자열 리터럴이라 가정 → os.path.join(...) 누락
#   공통 기전 = **표기 형태를 가정**한 것. 파서를 쓰면 표기가 달라도 같은 경로로 정규화된다
#   (`d[["a"]][["b"]]` 와 `d$a$b` 가 동일 경로로 모임 — grep 은 이걸 못 한다).
#
# 사용:
#   source("02_Infrastructure/ops/sot_access_paths.R")
#   extract_paths("02_Infrastructure/worktask/worktask_manager.R", "defaults")
#   sot_unconsumed("02_Infrastructure/worktask/constraint_defaults.json",
#                  list(c("02_Infrastructure/worktask/worktask_manager.R", "defaults")))
#
# 한계 (정직):
#   - **R 전용**. python 로더는 미커버(ast 모듈로 동형 구현 가능하나 미구현).
#   - 뿌리 변수명을 알아야 한다. 로드 지점을 사람이 지정한다.
#   - 동적 접근(`d[[key]]` 에서 key 가 변수)은 NA 로 버려진다 — 과소 추출 방향(안전).
#   - ★**별칭 맹점**: `ts <- defaults$tier_soft_deployment` 처럼 중간 변수를 거친 뒤
#     `ts$max_names` 로 재접근하는 경로는 **추적 못 한다**(뿌리 심볼이 root_var 가 아니다).
#     2026-08-20 실측: worktask_manager.R 은 별칭 할당 8건이 전부 **리프 값**을 담고
#     이후 `$` 재접근 0건이라 맹점이 물지 않았다(15경로 결과 온전). 타 파일은 미확인.
#   - python 로더는 이 맹점이 **실제로 물다** — deployed_holdings_check.py 는
#     `t = d["tier_soft_deployment"]` 후 `t.get(...)` 형태라, 확장 시 별칭 추적이 선행되어야 한다.
#==============================================================================

#' 파일에서 root_var 에 뿌리를 둔 `$` / `[[` 접근 체인을 전부 추출
#'
#' @param file      R 소스 경로
#' @param root_var  정본이 담긴 변수명 (예 "defaults")
#' @return character: "defaults$a$b" 형태 정규화 경로 (정렬·중복 제거)
extract_paths <- function(file, root_var, follow_alias = TRUE) {
  ex <- parse(file, keep.source = FALSE)
  out <- character(0)
  # ★별칭 추적(2026-08-20 추가): `ts <- defaults$a` 처럼 중간 변수로 받은 뒤
  #   `ts$b` 로 재접근하는 경로를 잎지 않기 위해 root 집합을 확장한다.
  #   roots[[var]] = 그 변수가 가리키는 정본 상대 접두(character vector).
  #   보수적: 단순 할당(`v <- <체인>`)만 따른다. 재할당되면 마지막 것으로 덮어쓴다.
  roots <- list(); roots[[root_var]] <- character(0)
  # 할당 수집 패스 — walk 전에 먼저 돌아 roots 를 채운다.
  #   순회를 반복해 고정점까지 — `a <- defaults$x; b <- a$y` 같은 2단 체인을 위해.
  chain_of <- function(e) {
    ch <- character(0); cur <- e
    while (is.call(cur) && as.character(cur[[1]])[1] %in% c("$", "[[")) {
      k <- cur[[3]]
      key <- if (is.character(k)) k else if (is.symbol(k)) as.character(k) else NA_character_
      ch <- c(key, ch); cur <- cur[[2]]
    }
    if (!is.symbol(cur) || any(is.na(ch))) return(NULL)
    list(root = as.character(cur), chain = ch)
  }
  collect <- function(e) {
    if (is.call(e)) {
      op <- as.character(e[[1]])[1]
      if (op %in% c("<-", "=", "<<-") && length(e) == 3 && is.symbol(e[[2]])) {
        lhs <- as.character(e[[2]]); r <- chain_of(e[[3]])
        if (!is.null(r) && length(r$chain) > 0 && !is.null(roots[[r$root]])) {
          roots[[lhs]] <<- c(roots[[r$root]], r$chain)
        } else if (!identical(lhs, root_var) && !is.null(roots[[lhs]])) {
          # ★재할당 무효화(2026-08-20): 별칭 변수가 **정본 체인이 아닌 것**으로
          #   다시 할당되면 별칭 자격을 박탈한다. 이걸 안 하면 `t <- read.csv(...)` 후의
          #   `t$SomeColumn` 이 정본 경로로 잡힌다(python 판 실측에서 적발 —
          #   deployed_holdings_check.py:85 `t = pq.read_table(...)` 가 $Date 오탐을 냈다).
          roots[[lhs]] <<- NULL
        }
      }
      for (i in seq_along(e)) if (!is.null(e[[i]])) try(collect(e[[i]]), silent = TRUE)
    } else if (is.pairlist(e) || is.expression(e)) {
      for (i in seq_along(e)) try(collect(e[[i]]), silent = TRUE)
    }
  }
  if (isTRUE(follow_alias)) for (pass in 1:3) for (i in seq_along(ex)) collect(ex[[i]])

  walk <- function(e) {
    if (is.call(e)) {
      op <- as.character(e[[1]])[1]
      if (op %in% c("$", "[[") && length(e) >= 3) {
        chain <- character(0); cur <- e
        while (is.call(cur) && as.character(cur[[1]])[1] %in% c("$", "[[")) {
          k <- cur[[3]]
          # 문자열 키 또는 심볼 키만 채택. 변수 키(동적)는 NA → 체인 폐기(과소 추출 = 안전)
          key <- if (is.character(k)) k else if (is.symbol(k)) as.character(k) else NA_character_
          chain <- c(key, chain); cur <- cur[[2]]
        }
        if (is.symbol(cur) && !any(is.na(chain))) {
          rv <- as.character(cur)
          if (!is.null(roots[[rv]]))
            out <<- c(out, paste(c(root_var, roots[[rv]], chain), collapse = "$"))
        }
      }
      for (i in seq_along(e)) if (!is.null(e[[i]])) try(walk(e[[i]]), silent = TRUE)
    } else if (is.pairlist(e) || is.expression(e)) {
      for (i in seq_along(e)) try(walk(e[[i]]), silent = TRUE)
    }
  }
  for (i in seq_along(ex)) walk(ex[[i]])
  sort(unique(out))
}

#' 추출 경로가 정본에 실재하는지 확인 (양성 대조)
#' @return list(ok = logical, missing = character)
verify_paths_exist <- function(paths, sot_list) {
  miss <- character(0)
  for (x in paths) {
    parts <- strsplit(x, "$", fixed = TRUE)[[1]][-1]
    v <- sot_list; okp <- TRUE
    for (k in parts) { v <- v[[k]]; if (is.null(v)) { okp <- FALSE; break } }
    if (!okp) miss <- c(miss, x)
  }
  list(ok = length(miss) == 0L, missing = miss)
}

#' 정본 리프 중 어떤 로더도 접근하지 않는 것을 산출
#' @param sot_json  정본 JSON 경로
#' @param loaders   list of c(file, root_var)
sot_unconsumed <- function(sot_json, loaders) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) stop("jsonlite 필요")
  d <- jsonlite::fromJSON(sot_json, simplifyVector = FALSE)
  hit <- character(0)
  for (L in loaders) hit <- c(hit, extract_paths(L[1], L[2]))
  # 뿌리 변수명 제거 → 정본 상대 경로. ★정규식 미사용 — heredoc/JSON 경계에서
  #   백슬래시 한 겹이 먹혀 정규식이 깔종 조용히 망가지는 기지 함정(L-code WORD_BOUNDARY_SILENT_FALSE).
  hit <- unique(vapply(hit, function(h) {
    pp <- strsplit(h, "$", fixed = TRUE)[[1]]
    paste(pp[-1], collapse = "$")
  }, character(1), USE.NAMES = FALSE))
  leaves <- character(0)
  wlk <- function(o, p = "") {
    if (is.list(o) && !is.null(names(o))) {
      for (nm in names(o)) wlk(o[[nm]], if (nzchar(p)) paste(p, nm, sep = "$") else nm)
    } else if (nzchar(p)) leaves <<- c(leaves, p)
  }
  wlk(d)
  # 리프가 접근됐거나, 그 조상 블록이 통째로 접근됐으면 소비로 본다
  consumed <- vapply(leaves, function(lf) {
    any(vapply(hit, function(h) identical(h, lf) || startsWith(lf, paste0(h, "$")), logical(1)))
  }, logical(1))
  list(n_leaf = length(leaves), n_consumed = sum(consumed),
       unconsumed = sort(leaves[!consumed]), accessed = sort(hit))
}

cat("[sot_access_paths] Loaded. extract_paths() / verify_paths_exist() / sot_unconsumed()\n")
