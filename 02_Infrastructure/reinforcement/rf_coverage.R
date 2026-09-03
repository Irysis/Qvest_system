#==============================================================================
# rf_coverage.R — 전 entry 커버리지 색인 (v10.2 2026-09-03 · 지식 소비면 A·B)
#
# ★왜: 중복 회피 배관(.done_fsets/.done_arms/.done_wt/.seen_sig)이 전부 **현재 entry 안만** 본다.
#   entry 가 바뀌면 앞선 논문에서 이미 잰 것과 정확히 같은 포트폴리오를 다시 잴 수 있고,
#   25칸 예산에서 그 칸이 그대로 날아간다. 서명은 base_signal 까지 포함하므로
#   entry 가 달라도 서명이 같으면 **같은 포트폴리오**다.
#
# ★성과를 쓰지 않는다. 이 색인이 답하는 질문은 "이미 쟀는가" 하나뿐이고,
#   "무엇이 더 나았는가" 는 답하지 않는다 — selection 오염 없음.
#   등급·지표는 **사유 문자열에만** 실려 사람이 어디를 보면 되는지 알려준다.
#
# 제공: rf_coverage_index() / rf_coverage_find() / rf_coverage_brief()
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.RFC_ROOT <- function() Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")

#' 전 entry 의 측정된 칸 → 서명 색인
#' @return data.table(sig, base_id, n, cell_code, grade, port_t, calmar, spec)
rf_coverage_index <- function(root = .RFC_ROOT(), layer = 1L) {
  suppressMessages(source(file.path(root, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = TRUE))
  lp <- file.path(root, sprintf("06_Registry/reinforce_ledger_l%d.json", layer))
  if (!file.exists(lp)) return(data.table(sig = character()))
  led <- tryCatch(fromJSON(lp, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(led)) return(data.table(sig = character()))
  rows <- list()
  for (e in led$entries %||% list()) {
    for (a in e$attempts %||% list()) {
      es <- a$essence
      sp <- if (is.list(es)) as.character(es$spec %||% "") else ""
      if (!nzchar(sp) || !file.exists(sp)) next
      s <- tryCatch(fromJSON(sp, simplifyVector = FALSE), error = function(z) NULL)
      if (is.null(s)) next
      rows[[length(rows) + 1L]] <- data.table(
        sig = .spec_sig(s), base_id = as.character(e$base_id %||% ""),
        n = as.integer(a$n %||% NA), cell_code = as.character(es$cell_code %||% ""),
        grade = as.character(a$grade %||% NA),
        port_t = suppressWarnings(as.numeric(es$port_t %||% NA)),
        calmar = suppressWarnings(as.numeric(es$calmar %||% NA)),
        spec = sp)
    }
  }
  if (!length(rows)) return(data.table(sig = character()))
  rbindlist(rows, fill = TRUE)
}

#' 이 스펙을 **다른 entry** 에서 이미 쟀는가
#' @param exclude_base 현재 entry — 안쪽 중복은 기존 .seen_sig 가 이미 본다
rf_coverage_find <- function(sig, idx, exclude_base = NULL) {
  # ★인자명 sig 가 컬럼명 sig 와 겹친다 — data.table i-식 안에서 컬럼이 이긴다.
  #   .q 로 받아 충돌을 없앤다(같은 이름으로 자기 자신을 거르는 죽은 필터를 만들지 않는다).
  .q <- as.character(sig)[1]
  if (is.null(idx) || !nrow(idx) || is.na(.q) || !nzchar(.q)) return(NULL)
  hit <- idx[sig == .q & is.finite(port_t)]
  if (!is.null(exclude_base) && nzchar(exclude_base)) hit <- hit[base_id != exclude_base]
  if (!nrow(hit)) return(NULL)
  hit[1]
}

#' 기전 좌표 커버리지 — **성과 없이** 무엇이 얼마나 측정됐는지만.
#'   생성기·프롬프트에 넣어도 안전한 형태다(rf_target_brief 와 같은 규율).
rf_coverage_brief <- function(root = .RFC_ROOT(), idx = NULL) {
  if (is.null(idx)) idx <- rf_coverage_index(root)
  if (!nrow(idx)) return("커버리지 0건")
  # 서명의 앞 두 칸(팩터 집합·기저가중)만 좌표로 접는다 — 지표는 넣지 않는다
  co <- vapply(strsplit(idx$sig, "|", fixed = TRUE), function(z) z[1] %||% "", character(1))
  tb <- sort(table(co[nzchar(co)]), decreasing = TRUE)
  paste(c(sprintf("측정 칸 %d · 고유 서명 %d", nrow(idx), length(unique(idx$sig))),
          sprintf("  %-52s %d회", names(tb)[seq_len(min(8L, length(tb)))],
                  as.integer(tb)[seq_len(min(8L, length(tb)))])), collapse = "\n")
}

cat("[rf_coverage.R] Loaded — rf_coverage_index() / rf_coverage_find() / rf_coverage_brief()\n")
