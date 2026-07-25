# build_knowledge_index.R — 지식 순차 인덱스(뷰) 생성기
#
# 목적 (도훈 2026-07-05): "코드가 1부터 차례대로 정리 + 증류돼도 구멍 안 나게".
#   ★설계: 정체성(안정 ID)과 순서(순번)를 분리한다.
#     - 안정 ID(AX-003, L-132, DIST-QPM-003)는 provenance 앵커 = 영구 불변(절대 미변경).
#     - 순번(#1..#N)은 *현재 활성 집합*의 위치일 뿐인 파생 뷰 — 증류/강등되면 활성 뷰에서
#       자동 제외되어 뷰는 항상 1..N 연속을 유지(구멍 없음). 빠진 것은 아카이브/검색/부활로 보존.
#   → 3,911곳(AX-008)·5,610곳(L-code) 참조를 건드리지 않고 "차례대로 1부터" 목표 달성. blast radius 0.
#
# 산출: 06_Registry/knowledge_index.md (사람) + knowledge_index.json (기계). 읽기 전용 — 원본 미변경.
# 배선: 주간 Cleaner + bootstrap에서 자동 재생성(집합 변경 시 항상 최신 1..N).
# 실행: Rscript --no-save -e 'source("02_Infrastructure/ops/build_knowledge_index.R")'  (한글 -e 금지)

suppressWarnings(suppressMessages(library(jsonlite)))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a)) || (is.character(a) && !nzchar(a[1]))) b else a

.ki_root <- function() {
  for (p in c(Sys.getenv("QM_ROOT",""), "C:/Users/99922/OneDrive/Quant_Module_Moltbot", getwd()))
    if (nzchar(p) && dir.exists(p)) return(p)
  getwd()
}
.ki_trim <- function(s, n = 90) { s <- gsub("[\r\n]+", " ", as.character(s %||% "")); if (nchar(s) > n) paste0(substr(s, 1, n), "…") else s }

build_knowledge_index <- function(root = .ki_root(), verbose = TRUE) {
  gen_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

  ## ── 1) Active Law (active/*.json, mode-local 제외 = 글로벌만) ──
  adir <- file.path(root, "qepm/memory/axioms/active")
  afiles <- sort(list.files(adir, pattern = "^AX-\\d+\\.json$", full.names = TRUE))  # non-recursive = global Law
  law <- list()
  for (f in afiles) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(d)) next
    id <- d$memory_id %||% d$axiom_id %||% d$id %||% sub("\\.json$", "", basename(f))
    law[[length(law)+1L]] <- list(id = id, name = .ki_trim(d$name %||% d$canonical_statement %||% d$text, 60),
                                  class = d$axiom_class %||% "?")
  }
  law <- law[order(vapply(law, function(x) x$id, ""))]

  ## ── 2) Active Distilled 탐색지도 (status==distilled) ──
  dk_p <- file.path(root, "06_Registry/distilled_knowledge.json")
  dk <- tryCatch(fromJSON(dk_p, simplifyVector = FALSE), error = function(e) NULL)
  dent <- if (!is.null(dk)) (dk$entries %||% dk) else list()
  dist <- list()
  for (e in dent) {
    if (!identical(e$status %||% "", "distilled")) next
    sup <- e$supporting_l_codes %||% e$supporting %||% list()
    dist[[length(dist)+1L]] <- list(
      id = e$dist_id %||% "?", polarity = e$polarity %||% "?",
      gist = .ki_trim(e$statement_refined %||% "", 100),
      n_sup = length(sup), mode = e$research_mode %||% "?")
  }
  dist <- dist[order(vapply(dist, function(x) x$id, ""))]

  ## ── 3) L-code 코퍼스 (모드별 그룹 + 글로벌 연속 순번) ──
  lc_p <- file.path(root, ".cache/lcode_corpus.json")
  lc <- tryCatch(fromJSON(lc_p, simplifyVector = FALSE), error = function(e) NULL)
  lcodes <- if (!is.null(lc)) (lc$lcodes %||% list()) else list()
  # 2026-07-25: id_collision_with / source_file 전달 (종전 드롭).
  # 같은 id 로 서로 다른 기록이 존재할 때 소비면(DIST supporting·hypothesis_index·
  # inverse-miner)이 어느 쪽을 인용하는지 분기할 수 없었다 — 실제로 DIST-QPM-001 의
  # "L-160 ID 재발급 오링크"(knowledge_recheck_queue, 07-04)가 이 경로로 발생했다.
  # 재번호(REASSIGN_ID)는 기존 인용을 끊으므로, 식별 정보를 전달해 분기 가능하게 한다.
  lrows <- lapply(lcodes, function(e) {
    row <- list(
      id = e$l_code %||% "?", mode = e$research_mode %||% e$mode %||% "unknown",
      family = e$family %||% "?", grade = e$grade %||% e$grade_raw %||% "?",
      gist = .ki_trim(e$lesson_text %||% e$statement %||% "", 90),
      source_file = e$source_file %||% "?")
    if (!is.null(e$id_collision_with)) row$id_collision_with <- e$id_collision_with
    row
  })
  # 정렬: mode → l_code (결정론). 모드 내 순번 + 글로벌 순번.
  ord <- order(vapply(lrows, function(x) x$mode, ""), vapply(lrows, function(x) x$id, ""))
  lrows <- lrows[ord]

  ## ── 4) 강등/아카이브 (뷰 제외, 참조 보존) ──
  ddir <- file.path(root, "qepm/memory/axioms/deprecated")
  dfiles <- list.files(ddir, pattern = "demoted.*\\.json$", full.names = TRUE)
  arch <- list()
  for (f in dfiles) {
    d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(d)) next
    arch[[length(arch)+1L]] <- list(id = d$memory_id %||% d$axiom_id %||% sub("_demoted.*","",basename(f)),
                                    to = d$demoted_note %||% d$superseded_by %||% "distilled")
  }

  ## ── JSON 산출 (기계) ──
  law_j  <- lapply(seq_along(law),  function(i) c(list(ordinal = i), law[[i]]))
  dist_j <- lapply(seq_along(dist), function(i) c(list(ordinal = i), dist[[i]]))
  lc_j   <- lapply(seq_along(lrows),function(i) c(list(ordinal = i), lrows[[i]]))
  payload <- list(
    schema_version = "knowledge_index_v1", generated_at = gen_at,
    principle = "안정 ID = provenance 앵커(불변). 순번(ordinal) = 현재 활성 집합 위치(파생 뷰). 증류/강등 시 활성 뷰에서 자동 제외 → 1..N 연속 유지. blast radius 0.",
    counts = list(active_law = length(law), active_distilled = length(dist), lcode_corpus = length(lrows), archived = length(arch)),
    active_law = law_j, active_distilled = dist_j, lcode_corpus = lc_j,
    archived = lapply(arch, function(x) x))
  jp <- file.path(root, "06_Registry/knowledge_index.json")
  write_json(payload, jp, pretty = TRUE, auto_unbox = TRUE, null = "null")

  ## ── Markdown 산출 (사람) ──
  L <- c()
  L <- c(L, "# Knowledge Index — 순차 뷰 (안정 ID 불변 · 활성 집합 1..N 자동)", "",
         sprintf("생성: %s · `build_knowledge_index.R` · **안정 ID(AX-003/L-132/DIST-*)는 provenance 앵커 = 영구 불변**. 순번(#)은 현재 활성 집합의 위치일 뿐 — 증류/강등되면 뷰에서 자동 제외되어 항상 1..N 연속(구멍 없음). 빠진 것도 아카이브+검색+부활로 보존.", gen_at),
         "")
  # Active Law
  L <- c(L, sprintf("## Active Law (%d)", length(law)), "", "| # | ID | 이름 | class |", "|---|----|------|-------|")
  for (i in seq_along(law)) L <- c(L, sprintf("| %d | %s | %s | %s |", i, law[[i]]$id, law[[i]]$name, law[[i]]$class))
  L <- c(L, "")
  # Active Distilled
  L <- c(L, sprintf("## Active Distilled 탐색지도 (%d)", length(dist)), "", "| # | ID | polarity | 요지 | L수 |", "|---|----|----------|------|-----|")
  for (i in seq_along(dist)) L <- c(L, sprintf("| %d | %s | %s | %s | %d |", i, dist[[i]]$id, dist[[i]]$polarity, dist[[i]]$gist, dist[[i]]$n_sup))
  L <- c(L, "")
  # L-code corpus — 모드별 그룹, 글로벌 연속 순번
  L <- c(L, sprintf("## L-code 코퍼스 — 모드별 순차 (총 %d · 글로벌 연속 #)", length(lrows)), "",
         "안정 ID(L-...)는 불변. 아래 #는 활성 코퍼스 내 위치(모드 그룹 · 글로벌 연속).", "")
  cur_mode <- ""
  for (i in seq_along(lrows)) {
    r <- lrows[[i]]
    if (!identical(r$mode, cur_mode)) { cur_mode <- r$mode; L <- c(L, "", sprintf("### %s", cur_mode), "", "| # | L-code | family | grade | 요지 |", "|---|--------|--------|-------|------|") }
    L <- c(L, sprintf("| %d | %s | %s | %s | %s |", i, r$id, r$family, r$grade, r$gist))
  }
  L <- c(L, "")
  # Archived
  L <- c(L, sprintf("## 강등/아카이브 (뷰 제외 · 참조 영구 보존, %d)", length(arch)), "")
  if (length(arch)) for (a in arch) L <- c(L, sprintf("- **%s** → %s", a$id, .ki_trim(a$to, 70))) else L <- c(L, "- (없음)")
  L <- c(L, "")
  mp <- file.path(root, "06_Registry/knowledge_index.md")
  writeLines(L, mp, useBytes = FALSE)

  if (verbose) cat(sprintf("[knowledge-index] Law %d · Distilled %d · L-code %d · 아카이브 %d → %s (+ .json)\n",
                           length(law), length(dist), length(lrows), length(arch), basename(mp)))
  invisible(payload)
}

if (!isTRUE(getOption("ki_no_autorun", FALSE))) build_knowledge_index()
