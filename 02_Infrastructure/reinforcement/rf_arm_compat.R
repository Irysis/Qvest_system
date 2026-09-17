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
#
# ★2026-09-13 수리 3건 — B4 결합 칸이 통째로 미측정되던 사고(2002.06975 promo3 B4_21/22/25):
#   ① 신뢰 분모(basis) — 엔진 커버리지 분모가 **유니버스·기저 신호의 지지구간**을 arm 결손으로 셌다
#      (정정 사연은 rf_cell_engine.R 가드 주석). KQ150 은 멤버십이 2010-01-29 부터라 지지 상한이 77.0% 여서
#      "막힌 적 있다" 기록 8행(비중 arm 7 + 오귀속 오버레이 1)이 전부 arm 이 아니라 유니버스에 대한 사실이었다. 그 분모로 쓰인 구 기록은
#      arm 에 대한 증거가 아니므로 **차단 근거로 쓰지 않는다**(파일에는 이력으로 남는다). 엔진 메시지가
#      [basis=…] 표식을 달고 오는 새 기록만 믿는다.
#   ② 귀속 — 실패한 arm 의 쌍만 적는다. 구판은 spec 의 **모든** 쌍을 적어 비중 arm 의 결손이 무관한
#      오버레이를 차단 목록에 올렸고(실측: overlay:holdlvl_syscrowd_tilt × KQ150 ← lean:entropy 의 실패),
#      오버레이는 강등 대상이 아니라 그 쌍에 걸린 칸은 출구 없이 닫혔다.
#   ③ 관문 단일화(rac_gate) — 러너의 **등록** 경로만 장부를 읽고 **재개** 경로는 안 읽었다. 그래서 첫 조우
#      조합(장부에 아직 기록 없음)에서 죽은 칸은 재개 때 같은 spec 으로 한 번 더 죽고 terminal 이 됐다 —
#      강등 규칙이 있어도 첫 조우 칸에는 영영 출구가 없었다. 두 경로가 이 함수 하나를 부른다.
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
  # ★단수 객체 판정은 kind 로도 한다 (2026-09-13) — arm_id 없는 단수 오버레이(list(kind="vol_scale"))를 층 리스트로
  #   오인해 필드 문자열을 순회하면 `$` 가 원자 벡터에서 던지고, 러너의 tryCatch 가 그걸 "차단 없음" 으로 삼킨다.
  ovl <- if (is.null(ovs)) list() else if (!is.null(ovs$arm_id) || !is.null(ovs$kind)) list(ovs) else ovs
  for (o in ovl) { if (!is.list(o)) next
    aid <- as.character(o$arm_id %||% "")
    if (nzchar(aid)) out[[length(out) + 1L]] <- list(arm = paste0("overlay:", aid), universe = ukey) }
  out
}

# ★차단 근거로 믿는 커버리지 분모. 이 목록 밖(표식 없음 = 2026-09-13 이전 엔진의 전 시그널일 분모)의
#   실패 기록은 이력일 뿐 판정에 안 쓴다. 표식을 발행하는 곳 = rf_cell_engine.R 의 두 커버리지 가드.
RAC_TRUSTED_BASES <- c("sel_dates", "held_rows")

#' 엔진 커버리지 실패 사유에서 분모 표식과 실패 arm 을 읽는다 — 워커→러너 채널은 오류 문자열 하나뿐이다.
#' @return list(basis = <표식 | "legacy">, kind = "weight" | "overlay" | NA, id = <catalog_id | overlay kind 라벨> | NA)
rac_parse_coverage <- function(detail) {
  d <- as.character(detail %||% "")[1]
  if (is.na(d)) d <- ""
  m <- regmatches(d, regexec("\\[basis=([a-z_]+)", d))[[1]]
  basis <- if (length(m) == 2L) m[2] else "legacy"
  w <- regmatches(d, regexec("(^|\\] )arm ([^ ]+) ", d))[[1]]
  if (length(w) == 3L) return(list(basis = basis, kind = "weight", id = w[3]))
  o <- regmatches(d, regexec("(^|\\] )overlay ([^ ]+) ", d))[[1]]
  if (length(o) == 3L) return(list(basis = basis, kind = "overlay", id = o[3]))
  list(basis = basis, kind = NA_character_, id = NA_character_)
}

#' 실패 사유가 지목한 arm 이 spec 의 어느 쌍인가.
#' @return NULL = 지목 없음(구 사유 — 전 쌍 기록) · character(0) = 지목한 arm 이 spec 에 없다(지어내지 않는다)
.rac_attribute <- function(spec, pc) {
  if (is.na(pc$kind)) return(NULL)
  if (identical(pc$kind, "weight")) {
    # 엔진 메시지는 catalog_id 를 싣고, 쌍 키(rac_pairs)는 arm → id → catalog_id 순이다 — 어느 식별자로 맞든 같은 키로
    wa <- spec$weighting %||% list()
    if (!identical(as.character(wa$kind %||% ""), "catalog")) return(character(0))
    if (!(pc$id %in% as.character(unlist(list(wa$arm, wa$id, wa$catalog_id))))) return(character(0))
    return(paste0("weight:", as.character(wa$arm %||% wa$id %||% wa$catalog_id)))
  }
  kinds <- strsplit(pc$id, "+", fixed = TRUE)[[1]]      # 엔진 라벨 = 층 kind 를 "+" 로 이은 것
  ovs <- spec$overlay
  ovl <- if (is.null(ovs)) list() else if (!is.null(ovs$arm_id) || !is.null(ovs$kind)) list(ovs) else ovs
  ids <- character(0)
  for (o in ovl) if (is.list(o) && as.character(o$kind %||% "") %in% kinds) {
    aid <- as.character(o$arm_id %||% "")
    if (nzchar(aid)) ids <- c(ids, paste0("overlay:", aid))
  }
  ids
}

#' 실행 결과를 장부에 남긴다. status = "ok" | "coverage_fail"
rac_record <- function(spec, status, root, detail = "", cell = "") {
  prs <- rac_pairs(spec); if (!length(prs)) return(invisible(0L))
  basis <- NULL
  if (identical(status, "coverage_fail")) {
    pc <- rac_parse_coverage(detail)
    basis <- pc$basis
    tgt <- .rac_attribute(spec, pc)
    if (!is.null(tgt)) {                       # ★귀속 — 실패한 arm 의 쌍만
      prs <- Filter(function(p) p$arm %in% tgt, prs)
      if (!length(prs)) return(invisible(0L))
    }
  }
  obj <- .rac_load(root); n <- 0L
  for (pr in prs) {
    k <- which(vapply(obj$entries, function(e)
      identical(e$arm, pr$arm) && identical(e$universe, pr$universe), logical(1)))
    rec <- list(arm = pr$arm, universe = pr$universe, status = status,
                detail = substr(as.character(detail), 1, 200), cell = as.character(cell),
                observed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
    if (!is.null(basis)) rec$basis <- basis
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

#' 이 spec 이 **이미 막힌 적 있는** 조합을 담고 있는가 — 신뢰 분모 기록만 본다
#' @return NULL(문제없음) 또는 사유 문자열 (attr: arm · universe · basis)
rac_blocked <- function(spec, root) {
  obj <- .rac_load(root)
  if (!length(obj$entries %||% list())) return(NULL)
  for (pr in rac_pairs(spec)) {
    k <- which(vapply(obj$entries, function(e)
      identical(e$arm, pr$arm) && identical(e$universe, pr$universe) &&
      identical(e$status, "coverage_fail") &&
      as.character(e$basis %||% "legacy")[1] %in% RAC_TRUSTED_BASES, logical(1)))
    if (length(k)) {
      .r <- sprintf("%s × %s — 앞서 커버리지로 막힌 조합(%s, %s)",
        pr$arm, pr$universe, as.character(obj$entries[[k[1]]]$cell %||% "?"),
        substr(as.character(obj$entries[[k[1]]]$detail %||% ""), 1, 80))
      attr(.r, "arm") <- pr$arm; attr(.r, "universe") <- pr$universe   # 강등 판정이 어느 arm 인지 읽는다
      attr(.r, "basis") <- as.character(obj$entries[[k[1]]]$basis)
      return(.r)
    }
  }
  NULL
}

#' 막힌 arm 을 강등할 수 있는가 — **승계된 비중이 이 칸의 시험 축이 아닐 때만** EW 로 (2026-09-04)
#'   실사고: 1라운드 승자 비중 lean:cvar 가 소형주 유니버스에서 커버리지 77% 로 막혀 B3_11 이 두 번
#'   죽고 미측정으로 남았다. B3 의 시험 축은 유니버스지 비중이 아니다 — 비중 때문에 유니버스 칸이
#'   비는 것은 "미측정 시도 금지"(헌법) 위반이다. 강등은 spec 에 carry_degraded 로 남겨 블록 내
#'   비교에서 비중이 다른 칸임을 읽을 수 있게 한다.
#'   ★강등하지 않는 것: 자기 축이 막힌 칸(B2 비중 = 그 arm 이 처치 자체라 EW 로 바꾸면 무처치 · 그게 판정) ·
#'     오버레이 arm(강등 대상은 비중뿐) · 미지 블록.
#'   ★B4 는 강등한다 (2026-09-13 변경 · 도훈 지시 "출구를 만들어라"). 구판은 "강등하면 LOO 의 '−비중' 칸과
#'     같아진다" 는 이유로 제외했는데, 그 대가는 중복 한 칸을 피하려다 **결합 칸 전체를 잃는 것**이었다
#'     (promo3 B4_21/22/25). 측정된 중복 칸은 정보가 0 이 아니지만 죽은 칸은 정확히 0 이다.
#'     - 대안 기각: (b) 차선 비중 arm 대체 — 차선의 순위는 **다른 유니버스**에서 잰 것이라 기준이 옮겨지지 않고,
#'       선택 연산자가 하나 더 붙으며, 첫 조우 조합이면 또 태운다. (c) 유니버스 제약 — 비중 축의 문제를 유니버스
#'       축의 손실로 바꾼다(전결합 = '−유니버스' 칸이 되어 B3 기여가 사라진다).
#'     - (a) EW 강등은 막힌 축 **하나만** 바꾸고 B1·B3·B5 는 그대로 둔다. 강등된 칸끼리(전결합·−팩터·−오버레이)는
#'       비중이 같은 EW 라 팩터·오버레이 기여 대조가 깨끗하다. 중복되는 대조(전결합 = −비중)는 정확히
#'       '측정 불가능한 기여' 이고, 그 사실을 loo_equivalent 로 남긴다.
#' @param combo_use B4 칸의 combo$use (예: c("B1","B2","B3","B5")) — B4 에서만 쓴다
#' @param siblings  같은 블록의 격자 칸들(list of list(code, combo=list(use))) — '−비중' 동치 칸을 찾는다
#' @return list(degrade, own_axis, arm, spec)
rac_degrade_plan <- function(spec, block, blocked, combo_use = NULL, siblings = NULL) {
  own <- switch(as.character(block %||% ""), B1 = "factors", B2 = "weighting", B3 = "universe",
                B5 = "overlay", B4 = "combination", "?")
  arm <- as.character(attr(blocked, "arm") %||% "")
  ok  <- nzchar(arm) && startsWith(arm, "weight:") && !(own %in% c("weighting", "?"))
  if (!ok) return(list(degrade = FALSE, own_axis = own, arm = arm, spec = spec))
  spec$weighting <- list(kind = "ew")
  cd <- list(axis = "weighting", from = arm, to = "ew",
             why = substr(as.character(blocked), 1, 200),
             at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  if (identical(own, "combination")) {
    use <- sort(unique(as.character(unlist(combo_use %||% list()))))
    cd$block <- "B4"
    if (length(use)) cd$combo_use <- as.list(use)
    loo <- setdiff(use, "B2")
    for (s in siblings %||% list()) {
      if (!is.null(s$block) && !identical(as.character(s$block), "B4")) next   # 형제는 B4 안에서만
      su <- sort(unique(as.character(unlist((s$combo %||% list())$use %||% list()))))
      if (length(loo) && identical(su, loo) &&
          !identical(as.character(s$code %||% ""), as.character(spec$code %||% ""))) {
        cd$loo_equivalent <- as.character(s$code); break
      }
    }
    cd$reading <- if (!is.null(cd$loo_equivalent))
      sprintf("구성이 %s(−비중 칸)과 같다 — 이 결합에서 비중 기여는 측정 불가. 강등 안 된 칸과 대조하면 비중 차이가 섞인다", cd$loo_equivalent)
    else "승계 비중을 EW 로 바꿔 측정 — 강등 안 된 칸과 대조하면 비중 차이가 섞인다"
  }
  spec$carry_degraded <- cd
  list(degrade = TRUE, own_axis = own, arm = arm, spec = spec)
}

#' 칸 실행 전 양립성 관문 — **등록 경로와 재개 경로가 같은 함수를 쓴다** (2026-09-13)
#'   ①신뢰 분모 차단 기록 없음 → 그대로 실행 ②차단 + 강등 가능 + 강등 spec 이 안 막힘 → 강등 spec 으로 실행
#'   ③그 밖(자기 축 · 오버레이 쌍 차단 · 강등 후에도 차단) → 닫는다
#' @return list(action = "run" | "close", spec, degraded, reason, plan)
rac_gate <- function(spec, block, root, combo_use = NULL, siblings = NULL) {
  b <- rac_blocked(spec, root)
  if (is.null(b)) return(list(action = "run", spec = spec, degraded = FALSE, reason = NULL, plan = NULL))
  dp <- rac_degrade_plan(spec, block, b, combo_use = combo_use, siblings = siblings)
  if (!isTRUE(dp$degrade))
    return(list(action = "close", spec = spec, degraded = FALSE, reason = b, plan = dp))
  b2 <- rac_blocked(dp$spec, root)
  if (!is.null(b2))
    return(list(action = "close", spec = spec, degraded = FALSE, reason = b2, plan = dp))
  list(action = "run", spec = dp$spec, degraded = TRUE, reason = b, plan = dp)
}

#' 관문 결과를 spec 파일·원장·로그에 옮긴다 — 러너 등록·재개 경로 공용 (2026-09-13)
#'   부작용(원장 기록·로그)은 주입받는다: 검사가 운영 원장을 빌리지 않고 이 함수를 그대로 잰다.
#'   ★판정 고장(rac_gate 오류)은 차단 사유가 아니다 → "run"(엔진 가드가 최종선 · 구판 거동).
#'     기록 고장은 삼키지 않는다 — 닫아야 할 칸을 조용히 돌리지 않는다.
#' @param cell  격자 칸(list(code, block, combo)) · @param cells 격자 전 칸(같은 블록 형제 탐색)
#' @param path  "register" | "resume" — 등록 경로에서 닫힌 칸만 spec 을 지운다(재개분 spec 은 사후 추적용으로 둔다)
#' @param record_fn function(n, grade, lessons, terminal, terminal_reason)
#' @param log_fn    function(event, ...)
#' @return "run" | "closed"
rac_gate_apply <- function(spec, sp, cell, n, path, cells, root, record_fn, log_fn) {
  g <- tryCatch(rac_gate(spec, cell$block, root, combo_use = (cell$combo %||% list())$use,
                         siblings = Filter(function(c) identical(as.character(c$block %||% ""),
                                                                 as.character(cell$block %||% "")), cells %||% list())),
                error = function(e) { log_fn("arm_compat_gate_failed", code = cell$code, path = path,
                                             err = conditionMessage(e)); NULL })
  if (is.null(g)) return("run")
  if (identical(g$action, "close")) {
    why <- as.character(g$reason)
    record_fn(n, grade = "NA (미결 — arm×유니버스 양립 불가)",
              lessons = sprintf("%s: %s", as.character(cell$code), why), terminal = TRUE,
              terminal_reason = sprintf("양립성 장부 차단 — %s", why))
    log_fn("cell_arm_incompatible", n = n, code = cell$code, why = why, path = path,
           note = "신뢰 분모로 막힌 조합 — 강등 출구도 없다(자기 축 · 오버레이 쌍 · 강등 후에도 차단). 백테 전에 닫는다")
    if (identical(path, "register")) unlink(sp, force = TRUE)
    return("closed")
  }
  if (isTRUE(g$degraded)) {
    write(toJSON(g$spec, auto_unbox = TRUE, pretty = TRUE, null = "null"), sp)
    log_fn("carry_degraded", n = n, code = cell$code, own_axis = g$plan$own_axis, from = g$plan$arm, to = "ew",
           path = path, loo_equivalent = as.character(g$spec$carry_degraded$loo_equivalent %||% ""),
           note = "승계 비중이 이 유니버스에서 불가 — EW 로 강등해 측정한다(spec.carry_degraded · 원장 교훈 머리에 표식)")
  }
  "run"
}

#' 강등 표식 한 줄 — 원장 교훈 머리에 붙인다. spec 에만 두면 원장·텔레그램 독자는 모른다(조용한 통과 금지).
rac_degrade_note <- function(cd) {
  if (is.null(cd) || !is.list(cd)) return("")
  eq <- as.character(cd$loo_equivalent %||% "")
  sprintf("[승계 비중 강등 %s→EW%s]", as.character(cd$from %||% "?"),
          if (nzchar(eq[1])) sprintf(" · 구성 = %s(−비중 칸)과 동일", eq[1]) else "")
}
