#!/usr/bin/env Rscript
#==============================================================================
# rf_b1_design_lib.R — B1(멀티팩터) 블록 **설계 1회** 의 재료 생성과 검증
#   (도훈 지시 2026-09-04 "B1 멀티팩터도 같은 맥락으로" · 선택 = 블록 진입 시 1회만 LLM 설계)
#
# 왜 1회인가:
#   강화 레인은 "규칙 개시이지 LLM 개시가 아니다" 로 설계돼 있다(reinforce SKILL §0.1) —
#   무인 상태의 LLM 은 감독할 수 없기 때문이다. 칸마다 에이전트를 부르면 그 경계가 통째로
#   사라지고 비용도 25배가 된다. 블록 진입 시 **한 번** 설계하고 칸들은 그 설계를 규칙으로
#   전개하면, LLM 이 닿는 지점은 하나뿐이고 그 산출물은 아래 검증을 통과해야만 쓰인다.
#
# 경계 (구조로 강제):
#   ① 에이전트 산출은 **설계 JSON 하나**다. 측정·등급·PIT 는 계약이 강제한다(AX-008).
#   ② 팩터는 **등록부에 실재하는 id** 만 — 없는 id 를 쓰면 설계 전체를 기각한다.
#   ③ 셀 간 팩터 집합 중복 금지 — 같은 구성에 다른 이름을 붙이는 것은 칸 낭비다.
#   ④ 기각은 조용하지 않다. 기각 사유를 로그에 남기고 **규칙 선정으로 폴백**한다.
#
# 사용:
#   Rscript rf_b1_design_lib.R materials <base_id> <out.txt>
#   Rscript rf_b1_design_lib.R verify    <base_id> <design.json>
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- { .r <- Sys.getenv("QVEST_RF_ROOT", "")
          if (nzchar(.r)) .r else Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot") }
setwd(ROOT)
LOG <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
dir.create(dirname(LOG), recursive = TRUE, showWarnings = FALSE)
jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "b1_design"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG, append = TRUE)
  cat(sprintf("[b1_design] %s\n", event))
}
.cfg <- function() tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"),
                                     simplifyVector = FALSE), error = function(e) list())
rf_b1_max_cells <- function() as.integer((.cfg()$b1_design$max_cells) %||% 15L)

#' 활성 entry 1건 (없으면 NULL)
.active_entry <- function() {
  led <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"),
                           simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(led)) return(NULL)
  a <- Filter(function(e) identical(e$status, "active"), led$entries)
  if (length(a)) a[[1]] else NULL
}

#' 후보 팩터 풀 (규칙 선정기와 **같은 정본**을 쓴다 — 두 벌이 갈리면 설계가 없는 팩터를 고른다)
.pool <- function() {
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R"), local = TRUE))
  P <- rf_factor_pool(root = ROOT)
  if (is.list(P) && !is.data.table(P)) P$pool else P
}

# ── materials — 에이전트가 읽을 재료 ─────────────────────────────────────────
b1_materials <- function(base_id, out_p) {
  E <- .active_entry()
  if (is.null(E) || !identical(as.character(E$base_id), base_id))
    stop("[b1_design] 활성 entry 가 아니다: ", base_id)
  ap <- file.path(E$base_artifacts %||% "", "authoritative_remeasure.json")
  AR <- if (nzchar(ap) && file.exists(ap))
    tryCatch(fromJSON(ap, simplifyVector = FALSE), error = function(e) NULL) else NULL
  sp <- AR$replication$source_paper %||% list()
  es <- AR$essence %||% list()
  pool <- .pool()
  L <- c(
    "## 기저 (이 위에 팩터를 얹는다)",
    sprintf("- 전략 id: %s", base_id),
    sprintf("- 논문: %s", as.character(sp$title %||% E$paper_key %||% "?")),
    sprintf("- 원문: %s", as.character(sp$url %||% "")),
    sprintf("- 기저 엔진: %s", as.character(E$engine_path %||% "")),
    sprintf("- 기저 등급 %s · 다중검정 t %s · Calmar %s",
            as.character(E$base_grade %||% "?"),
            as.character(es$portfolio_alpha_t_nw_lag3 %||% "?"),
            as.character(es$calmar %||% "?")),
    "",
    sprintf("## 후보 팩터 등록부 (%d종 — 여기 있는 id 만 쓸 수 있다)", nrow(pool)))
  cats <- sort(unique(as.character(pool$category)))
  for (cc in cats) {
    ids <- as.character(pool[category == cc]$id)
    L <- c(L, sprintf("### %s (%d)", cc, length(ids)),
           paste(strwrap(paste(ids, collapse = ", "), width = 110), collapse = "\n"))
  }
  writeLines(L, out_p, useBytes = TRUE)
  jlog("materials_written", base_id = base_id, n_factors = nrow(pool), out = out_p)
  invisible(out_p)
}

# ── verify — 설계 JSON 을 기계가 재도출로 검증 ───────────────────────────────
#   진술("좋은 조합이다")은 근거가 아니다. 여기서 보는 것은 **실재성과 형식**뿐이고,
#   좋은지 나쁜지는 계약(측정)이 판정한다.
b1_verify <- function(base_id, design_p) {
  bad <- function(why) { jlog("design_rejected", base_id = base_id, why = why)
                         unlink(design_p, force = TRUE); quit(status = 1) }
  if (!file.exists(design_p) || file.size(design_p) == 0L) bad("설계 파일 부재")
  D <- tryCatch(fromJSON(design_p, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(D)) bad("JSON 파싱 실패")
  cells <- D$cells %||% list()
  if (!length(cells)) bad("cells 0건")
  MX <- rf_b1_max_cells()
  if (length(cells) > MX) bad(sprintf("cells %d > 상한 %d (예산 폭주 방지)", length(cells), MX))
  pool_ids <- as.character(.pool()$id)
  seen <- character(0)
  for (i in seq_along(cells)) {
    ce <- cells[[i]]
    fs <- as.character(unlist(ce$factors %||% list()))
    if (!length(fs)) bad(sprintf("cell %d: factors 비어 있음", i))
    miss <- setdiff(fs, pool_ids)
    if (length(miss)) bad(sprintf("cell %d: 등록부에 없는 팩터 %s", i, paste(head(miss, 4), collapse = ",")))
    if (anyDuplicated(fs)) bad(sprintf("cell %d: 같은 팩터를 두 번 넣었다", i))
    k <- paste(sort(fs), collapse = "+")
    if (k %in% seen) bad(sprintf("cell %d: 앞 칸과 팩터 집합이 동일(%s)", i, substr(k, 1, 60)))
    seen <- c(seen, k)
    if (!nzchar(as.character(ce$label %||% ""))) bad(sprintf("cell %d: label 없음", i))
  }
  jlog("design_verified", base_id = base_id, cells = length(cells),
       max_depth = max(vapply(cells, function(c) length(unlist(c$factors %||% list())), integer(1))))
  invisible(TRUE)
}

#' 설계 JSON → 러너가 쓰는 셀 목록 (규칙 선정기 산출과 **같은 형태**)
rf_b1_design_cells <- function(base_id, root = ROOT) {
  dp <- file.path(root, ".cache/rf_b1_design", sprintf("%s.json", substr(base_id, 1, 60)))
  if (!file.exists(dp)) return(NULL)
  D <- tryCatch(fromJSON(dp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(D) || !length(D$cells %||% list())) return(NULL)
  lapply(seq_along(D$cells), function(i) {
    ce <- D$cells[[i]]
    fs <- as.character(unlist(ce$factors %||% list()))
    list(code = sprintf("B1_%d", i),
         label = as.character(ce$label %||% sprintf("설계 %d", i)),
         factors = lapply(fs, function(x) list(kind = "db", id = x)),
         basis = sprintf("LLM 설계(블록 진입 1회) · 깊이 %d · %s", length(fs),
                         substr(as.character(ce$rationale %||% D$rationale %||% ""), 1, 160)),
         note = "★설계 산출 — 팩터 실재성·중복은 rf_b1_design_lib::b1_verify 가 재도출로 검증했다. 등급은 계약이 낸다.")
  })
}

if (!interactive()) {
  a <- commandArgs(TRUE)
  if (length(a) >= 3L && identical(a[1], "materials")) b1_materials(a[2], a[3])
  else if (length(a) >= 3L && identical(a[1], "verify")) b1_verify(a[2], a[3])
  else if (length(a) >= 1L && a[1] %in% c("materials", "verify")) stop("[b1_design] 인자 부족")
}
