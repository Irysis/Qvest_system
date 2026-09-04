#!/usr/bin/env Rscript
#==============================================================================
# rf_arm_compat.R — arm × 유니버스 **양립성 장부** (도훈 지시 ③ · 2026-09-04)
#
# 무엇을 막나: 2026-09-04 B4 에서 비중 arm `entropy` 가 KQ150 단독 유니버스 위에서
#   커버리지 77%(<80%) 로 막혔다. 엔진 가드는 옳게 발화했지만 **백테를 다 돌린 뒤**였고,
#   결정론적 실패라 재시도까지 태웠다 — 3칸 × 2회. 같은 조합은 몇 번을 돌려도 같은 곳에서 죽는다.
#
# 왜 사전 백테가 아니라 장부인가:
#   커버리지를 미리 재려면 비중 단계를 실제로 돌려야 하고, 그러려면 패널을 로드해야 한다 —
#   아낀 만큼 쓴다. 대신 **이미 잰 것을 기억한다**: 어떤 arm 이 어떤 유니버스에서 통과했고
#   어디서 막혔는지. 첫 조합은 여전히 한 번 태우지만, 그 다음부터는 공짜로 막힌다.
#   ★재도출이지 진술이 아니다 — 기록은 전부 실행 결과(cell_done / cell_error)에서 온다.
#
# 한계(명시): 커버리지는 유니버스 크기·기간·팩터 결합에도 달린다. 그래서 판정은
#   "같은 (arm, universe) 조합이 **실제로** 막힌 적이 있는가" 하나뿐이고, 추정하지 않는다.
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

.rac_path <- function(root) file.path(root, "06_Registry/rf_arm_compat.json")

.rac_load <- function(root) {
  p <- .rac_path(root)
  if (!file.exists(p)) return(list(schema = "rf_arm_compat_v1", entries = list()))
  tryCatch(fromJSON(p, simplifyVector = FALSE),
           error = function(e) list(schema = "rf_arm_compat_v1", entries = list()))
}
.rac_write <- function(obj, root) {
  p <- .rac_path(root)
  txt <- toJSON(obj, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
  if (is.null(tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)))
    stop("[rf_arm_compat] 쓰기 직전 재파싱 실패 — 원본 불변")
  tmp <- paste0(p, ".tmp"); write(txt, tmp)
  if (!suppressWarnings(file.rename(tmp, p))) { file.copy(tmp, p, overwrite = TRUE); unlink(tmp) }
  invisible(p)
}

#' spec 에서 (arm, universe) 쌍들을 뽑는다 — 비중 arm + 오버레이 arm 전부
rac_pairs <- function(spec) {
  u <- spec$universe %||% list(kind = "k200_kq150")
  ukey <- paste0(as.character(u$kind %||% "?"),
                 if (nzchar(as.character(u$flag %||% ""))) paste0(":", u$flag) else "",
                 if (!is.null(u$quantile)) paste0(":q", paste(unlist(u$quantile), collapse = "-")) else "")
  out <- list()
  wa <- spec$weighting
  if (!is.null(wa) && identical(as.character(wa$kind %||% ""), "catalog")) {
    aid <- as.character(wa$arm %||% wa$id %||% wa$catalog_id %||% "")
    if (nzchar(aid)) out[[length(out) + 1L]] <- list(arm = paste0("weight:", aid), universe = ukey)
  }
  ovs <- spec$overlay
  ovl <- if (is.null(ovs)) list() else if (!is.null(ovs$arm_id)) list(ovs) else ovs
  for (o in ovl) { aid <- as.character((o %||% list())$arm_id %||% "")
    if (nzchar(aid)) out[[length(out) + 1L]] <- list(arm = paste0("overlay:", aid), universe = ukey) }
  out
}

#' 실행 결과를 장부에 남긴다. status = "ok" | "coverage_fail"
rac_record <- function(spec, status, root, detail = "", cell = "") {
  prs <- rac_pairs(spec); if (!length(prs)) return(invisible(0L))
  obj <- .rac_load(root); n <- 0L
  for (pr in prs) {
    k <- which(vapply(obj$entries, function(e)
      identical(e$arm, pr$arm) && identical(e$universe, pr$universe), logical(1)))
    rec <- list(arm = pr$arm, universe = pr$universe, status = status,
                detail = substr(as.character(detail), 1, 200), cell = as.character(cell),
                observed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
    if (length(k)) {
      # ★실패가 성공을 덮지 않는다 — 한 번 통과한 조합이 다른 이유로 실패할 수 있고,
      #   그걸 영구 차단으로 바꾸면 이 장부가 리서치를 막는 기계가 된다.
      if (identical(obj$entries[[k[1]]]$status, "ok") && identical(status, "coverage_fail")) {
        obj$entries[[k[1]]]$conflict <- rec; n <- n + 1L
      } else obj$entries[[k[1]]] <- rec
    } else { obj$entries[[length(obj$entries) + 1L]] <- rec; n <- n + 1L }
  }
  .rac_write(obj, root); invisible(n)
}

#' 이 spec 이 **이미 막힌 적 있는** 조합을 담고 있는가
#' @return NULL(문제없음) 또는 사유 문자열
rac_blocked <- function(spec, root) {
  obj <- .rac_load(root)
  if (!length(obj$entries %||% list())) return(NULL)
  for (pr in rac_pairs(spec)) {
    k <- which(vapply(obj$entries, function(e)
      identical(e$arm, pr$arm) && identical(e$universe, pr$universe) &&
      identical(e$status, "coverage_fail"), logical(1)))
    if (length(k)) return(sprintf("%s × %s — 앞서 커버리지로 막힌 조합(%s, %s)",
      pr$arm, pr$universe, as.character(obj$entries[[k[1]]]$cell %||% "?"),
      substr(as.character(obj$entries[[k[1]]]$detail %||% ""), 1, 80)))
  }
  NULL
}
