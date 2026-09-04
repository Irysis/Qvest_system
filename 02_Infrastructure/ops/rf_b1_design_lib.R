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
## ★jlog 싱크는 QVEST_RP_JLOG 로 돌린다 (2026-09-04: 검사 픽스처가 운영 로그를 오염시켰다)
LOG <- Sys.getenv("QVEST_RP_JLOG", file.path(ROOT, ".cache/reinforce_auto_log.jsonl"))
dir.create(dirname(LOG), recursive = TRUE, showWarnings = FALSE)
.b1_log <- function(event, ...) {
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
## ★코드 루트는 데이터 루트가 아니다 — 자기 라이브러리는 **자기 위치**에서 읽는다(self-first).
##   ROOT(=QVEST_RF_ROOT)를 격리하면 데이터만 갈라야 하는데, 구판은 코드와 팩터 등록부까지 그 밑에서 찾아
##   격리 검사 자체가 불가능했다. (normalizePath 는 안 쓴다 — 한글 경로를 파손한다)
.CODE_ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
.SELF_DIR <- local({
  a <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  d <- if (length(a)) dirname(sub("^--file=", "", a[1])) else ""
  if (nzchar(d) && file.exists(file.path(d, "rf_factor_arms.R"))) d
  else file.path(.CODE_ROOT, "02_Infrastructure/ops")
})
.pool <- function() {
  suppressMessages(source(file.path(.SELF_DIR, "rf_factor_arms.R"), local = TRUE))
  P <- rf_factor_pool(root = .CODE_ROOT)
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
    "")
  ## ★승계 절 (2026-09-05) — 승격·결합 entry 는 기저가 "논문 신호" 가 아니라 "논문 신호 + carry" 다.
  ##   이걸 안 주면 설계자가 이미 켜진 팩터를 다시 골라 dedup 에 먹히고(= 무처치 칸) 예산만 탄다.
  cy <- E$carry
  if (!is.null(cy)) {
    .fid <- function(x) as.character((x %||% list())$id %||% (x %||% list())$catalog_id %||% "?")
    cf <- vapply(cy$factors %||% list(), .fid, character(1))
    L <- c(L,
      "## ★이 entry 는 승격이다 — 아래가 **이미 켜져 있다**(네가 다시 고를 필요가 없다)",
      sprintf("- 승계 팩터 %d종: %s", length(cf),
              if (length(cf)) paste(cf, collapse = ", ") else "없음"),
      sprintf("- 승계 비중: %s", as.character((cy$weighting %||% list())$label %||%
                                              (cy$weighting %||% list())$kind %||% "동일가중")),
      sprintf("- 승계 유니버스: %s", as.character((cy$universe %||% list())$kind %||% "k200_kq150")),
      sprintf("- 승계 오버레이: %s", as.character((cy$overlay %||% list())$arm_id %||%
                                                 (cy$overlay %||% list())$kind %||% "없음")),
      sprintf("- 부모: %s · 깊이 %s · 승자 칸 %s(다중검정 t %s)",
              as.character((E$parent %||% list())$base_id %||% "?"),
              as.character((E$parent %||% list())$depth %||% "?"),
              as.character((E$parent %||% list())$cell %||% "?"),
              as.character((E$parent %||% list())$best_port_t %||% "?")),
      "  ★네가 고르는 팩터는 이 승계 집합에 **더해지는 것**이다. 같은 id 를 다시 넣으면 중복 제거되어",
      "    그 칸은 승계와 동일해지고 **처치 미전달로 미측정 종결**된다(예산만 탄다).",
      "  ★승계 팩터를 빼는 설계는 이 블록에서 불가능하다 — 빼는 실험은 결합 블록(B4)의 leave-one-out 이 한다.",
      "")
  }
  L <- c(L,
    sprintf("## 후보 팩터 등록부 (%d종 — 여기 있는 id 만 쓸 수 있다)", nrow(pool)))
  cats <- sort(unique(as.character(pool$category)))
  for (cc in cats) {
    ids <- as.character(pool[category == cc]$id)
    L <- c(L, sprintf("### %s (%d)", cc, length(ids)),
           paste(strwrap(paste(ids, collapse = ", "), width = 110), collapse = "\n"))
  }
  # ── ★논문 간 축적 (도훈 지시 ② · 2026-09-04) ────────────────────────────
  #   B1 은 entry 의 **첫 블록**이라 안에 쌓인 교훈이 없다. 그래서 여기에 아무것도 안 주면
  #   논문이 바뀔 때마다 배운 것이 끊긴다 — entry 안에서만 누적되고 entry 사이에서는 0이다.
  #   ⇒ 직전 entry 들의 블록 L-code 에서 **기전·처방·쓰지 말 것**을 물려준다.
  #   ★수치가 아니라 기전을 물려준다: 다른 논문의 t 값은 이 기저에 의미가 없지만,
  #     "어떤 축이 어느 소비 지점에서 죽더라" 는 기저가 달라도 옮겨 붙는다.
  .prior <- tryCatch({
    fs <- list.files(file.path(ROOT, "stage_artifacts/l_code/reinforcement"),
                     pattern = "^l_code_.*_B[0-9]+\\.json$", full.names = TRUE)
    fs <- fs[!grepl(base_id, basename(fs), fixed = TRUE)]   # 자기 entry 는 제외(첫 블록이라 없다)
    if (!length(fs)) list() else {
      fs <- fs[order(file.info(fs)$mtime, decreasing = TRUE)]
      n_keep <- as.integer((.cfg()$b1_design$prior_entries) %||% 12L)
      lapply(head(fs, n_keep), function(f)
        tryCatch(fromJSON(f, simplifyVector = TRUE), error = function(e) NULL))
    } }, error = function(e) list())
  .prior <- Filter(function(x) !is.null(x) &&
                     (nzchar(as.character(x$mechanism %||% "")) ||
                      length(x$next_block_actions %||% list()) ||
                      length(x$avoid %||% list())), .prior)
  if (length(.prior)) {
    L <- c(L, "", sprintf("## 앞선 논문들에서 이미 배운 것 (%d블록) — 기저가 달라도 옮겨 붙는 것만", length(.prior)),
           "  ★수치는 그 논문의 것이라 여기에 의미가 없다. **기전과 처방**만 읽어라.",
           "  ★이미 벽이 확인된 축에 칸을 쓰는 것이 예산의 가장 큰 낭비다.")
    for (x in .prior) {
      L <- c(L, sprintf("### %s / %s", as.character(x$strategy_id %||% "?"),
                        as.character(x$l_code %||% "")))
      ## ★발췌 상한 (2026-09-04): 승격 entry 는 부모 사슬의 교훈까지 쌓여 이 절이 34KB 가 됐고
      ##   프롬프트가 argv 상한에 걸려 설계 에이전트가 안 떴다. 기전은 결론부터 쓰라고 했으니 앞 700자가 요지다.
      if (nzchar(as.character(x$mechanism %||% ""))) {
        .mx <- as.character(x$mechanism)
        if (nchar(.mx) > 700L) .mx <- paste0(substr(.mx, 1L, 700L), "…")
        L <- c(L, sprintf("- 기전: %s", .mx))
      }
      .a <- x$next_block_actions
      if (!is.null(.a) && length(.a)) {
        .t <- if (is.data.frame(.a)) as.character(.a$action) else
              vapply(.a, function(z) as.character(z$action %||% "")[1], character(1))
        L <- c(L, sprintf("- 그때의 처방: %s", paste(utils::head(.t, 3L), collapse = " / ")))
      }
      .v <- x$avoid
      if (!is.null(.v) && length(.v))
        L <- c(L, sprintf("- 쓰지 말 것: %s", paste(as.character(unlist(.v)), collapse = " / ")))
    }
  } else L <- c(L, "", "## 앞선 논문 교훈: 없음(기전이 적힌 L-code 가 아직 없다)")

  writeLines(L, out_p, useBytes = TRUE)
  .b1_log("materials_written", base_id = base_id, n_factors = nrow(pool),
          prior_lessons = length(.prior), out = out_p)
  invisible(out_p)
}

# ── verify — 설계 JSON 을 기계가 재도출로 검증 ───────────────────────────────
#   진술("좋은 조합이다")은 근거가 아니다. 여기서 보는 것은 **실재성과 형식**뿐이고,
#   좋은지 나쁜지는 계약(측정)이 판정한다.
b1_verify <- function(base_id, design_p) {
  bad <- function(why) { .b1_log("design_rejected", base_id = base_id, why = why)
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
  .b1_log("design_verified", base_id = base_id, cells = length(cells),
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
