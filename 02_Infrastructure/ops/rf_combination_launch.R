#!/usr/bin/env Rscript
#==============================================================================
# rf_combination_launch.R — 논문 간 결합 라운드 **착수** (2026-08-31 도훈 지시)
#
# 왜 이 파일이 생겼나:
#   rf_combination_review.R 이 논문 3편마다 결합 후보를 쌓아 왔지만(4회 · 10쌍),
#   그 후보를 **소비하는 코드가 없었다**. 검토 note 가 스스로 "착수하지 않는다 —
#   결합 라운드는 새 격자 설계가 필요해 규칙으로 환원되지 않는다" 고 적어 두었고,
#   세션도 착수한 적이 없다. 생산자만 있고 소비자가 없는 계기였다.
#
#   새 격자는 필요 없다는 것이 이 파일의 주장이다. 결합은 **기저 신호를 바꾸는 일**이지
#   격자를 바꾸는 일이 아니다. 두 엔진의 신호를 rank-Z 평균해 새 기저를 만들면
#   기존 25칸 격자가 그 위에서 그대로 돈다(rf_cell_engine 의 base_signal.kind =
#   "engine_blend"). 그래서 여기서 하는 일은 **원장 entry 를 하나 여는 것**뿐이다.
#
# 후보 선정이 검토기보다 엄격한 이유:
#   검토기의 판정은 "둘 다 다중검정 t > 0" 하나뿐이라 후보가 부풀려진다. 실측 10쌍 중
#   서로 다른 논문 쌍은 사실상 하나였다 — 같은 논문의 승격 사슬(원본·promo1·promo1r)이
#   별개 entry 라 4가지 조합으로 세어졌고, park 된 오염 판까지 후보에 있었다.
#   여기서는 ①논문(paper_key) 단위로 접고 ②parked/superseded 는 제외하며
#   ③엔진 경로가 실재하는 것만 남긴다.
#
# 사용:
#   Rscript rf_combination_launch.R            # 최고 후보 1건 착수
#   Rscript rf_combination_launch.R --dry-run  # 무엇을 열지만 보고 열지 않는다
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
DRY  <- any(c("--dry-run", "--dry") %in% commandArgs(TRUE))
LOG  <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
jlog <- function(event, ...) {
  rec <- c(list(ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), event = event, src = "combo_launch"), list(...))
  cat(toJSON(rec, auto_unbox = TRUE, null = "null"), "\n", sep = "", file = LOG, append = TRUE)
  cat(sprintf("[combo] %s %s\n", event,
              paste(names(rec)[-(1:3)], unlist(lapply(rec[-(1:3)], function(z) substr(paste(z, collapse = ","), 1, 90))),
                    sep = "=", collapse = " ")))
}
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R")))

led <- rf_load(1L, ROOT)
if (length(Filter(function(e) identical(e$status, "active"), led$entries))) {
  jlog("halt_active_exists", note = "진행 중인 강화가 있다 — 결합은 그 뒤에"); quit(status = 0)
}

# ── 1. 논문 단위로 접는다 (entry 가 아니라 paper_key 가 단위) ────────────────
#   같은 논문의 승격 사슬은 한 논문이다. parked/superseded 는 무효 판이라 제외한다.
by_paper <- list()
for (e in led$entries) {
  if (identical(e$status, "parked") || identical(e$status, "superseded")) next
  pk <- as.character(e$paper_key %||% "")
  ep <- as.character(e$engine_path %||% "")
  if (!nzchar(pk) || !nzchar(ep) || !file.exists(ep)) next
  # ★결합 entry 는 풀에 넣지 않는다. 넣으면 "27156 + (27156+27076)" 처럼 **같은 논문이
  #   두 번** 들어간 조합이 생긴다 — 결합의 결합은 다른 층이고, 여기서는 논문 쌍만 만든다.
  #   (engine_path 도 a 쪽 하나만 들고 있어 blend 를 재현하지도 못한다.)
  if (startsWith(pk, "combo:")) next
  pts <- vapply(e$attempts %||% list(), function(a) {
    v <- tryCatch(as.numeric(a$essence$port_t), error = function(z) NA_real_)
    if (length(v) != 1L) NA_real_ else v }, numeric(1))
  best_t <- if (length(pts) && any(is.finite(pts))) max(pts, na.rm = TRUE) else NA_real_
  # 기저 자체의 t 도 후보 자격에 쓴다 — 강화를 안 돌린 논문(0칸)도 신호는 있다
  ap <- file.path(e$base_artifacts %||% "", "authoritative_remeasure.json")
  base_t <- if (nzchar(ap) && file.exists(ap))
    tryCatch(as.numeric(fromJSON(ap, simplifyVector = TRUE)$essence$portfolio_alpha_t_nw_lag3 %||%
                        fromJSON(ap, simplifyVector = TRUE)$essence$port_t), error = function(z) NA_real_) else NA_real_
  tt <- suppressWarnings(max(c(best_t, base_t), na.rm = TRUE))
  if (!is.finite(tt)) tt <- NA_real_
  prev <- by_paper[[pk]]
  if (is.null(prev) || (is.finite(tt) && (!is.finite(prev$t) || tt > prev$t)))
    by_paper[[pk]] <- list(paper_key = pk, engine = ep, t = tt, base_id = e$base_id)
}
P <- Filter(function(x) is.finite(x$t), by_paper)
jlog("papers_pooled", n = length(P),
     keys = paste(vapply(P, function(x) x$paper_key, character(1)), collapse = ","))
if (length(P) < 2L) { jlog("halt_too_few_papers", n = length(P)); quit(status = 0) }

# ── 1b. 이미 돌린 쌍은 제외 ─────────────────────────────────────────────────
#   ★없으면 매 주기 같은 쌍(최고 점수)을 다시 연다. 결합 entry 의 paper_key 는
#   "combo:a+b" 형태라 거기서 되읽는다. 순서 무관하게 본다(a+b 와 b+a 는 같은 쌍).
.pairkey <- function(x, y) paste(sort(c(x, y)), collapse = "|")
.done_pairs <- unique(unlist(lapply(led$entries, function(e) {
  pk <- as.character(e$paper_key %||% "")
  if (!startsWith(pk, "combo:")) return(NULL)
  ab <- strsplit(sub("^combo:", "", pk), "+", fixed = TRUE)[[1]]
  if (length(ab) != 2L) return(NULL)
  .pairkey(ab[1], ab[2])
})))
if (length(.done_pairs)) jlog("pairs_already_done", n = length(.done_pairs),
                              keys = paste(.done_pairs, collapse = ","))

# ── 2. 쌍 만들기 — 둘 다 양수 t. 높은 합 순 ─────────────────────────────────
#   ★상관은 여기서 재지 않는다. 두 엔진을 다 돌려야 알 수 있고 그건 착수와 같은 비용이다.
#   대신 첫 셀(B1_1)의 결과가 곧 결합 기저의 성적이라 한 칸이면 판정이 선다.
V <- P[order(-vapply(P, function(x) x$t, numeric(1)))]
pairs <- list()
for (a in seq_along(V)) for (b in seq_along(V)) {
  if (b <= a) next
  if (!(V[[a]]$t > 0 && V[[b]]$t > 0)) next
  if (.pairkey(V[[a]]$paper_key, V[[b]]$paper_key) %in% .done_pairs) next
  pairs[[length(pairs) + 1L]] <- list(a = V[[a]], b = V[[b]], score = V[[a]]$t + V[[b]]$t)
}
if (!length(pairs)) { jlog("halt_no_new_pair", note = "양수 쌍이 없거나 남은 쌍을 이미 다 돌렸다"); quit(status = 0) }
pairs <- pairs[order(-vapply(pairs, function(x) x$score, numeric(1)))]
top <- pairs[[1]]
cat(sprintf("\n결합 후보 %d쌍 · 1위 = %s (t %.3f) + %s (t %.3f)\n\n",
            length(pairs), top$a$paper_key, top$a$t, top$b$paper_key, top$b$t))
for (k in seq_len(min(5L, length(pairs)))) {
  p <- pairs[[k]]
  cat(sprintf("  %d. %-14s (t %6.3f)  +  %-14s (t %6.3f)   합 %.3f\n",
              k, p$a$paper_key, p$a$t, p$b$paper_key, p$b$t, p$score))
}

if (DRY) { jlog("dry_run", pair = paste(top$a$paper_key, top$b$paper_key, sep = "+")); quit(status = 0) }

# ── 3. 결합 entry 개설 — 격자는 그대로, 기저만 blend 다 ─────────────────────
BID <- sprintf("RP_%s_combo", format(Sys.time(), "%Y%m%d_%H%M%S"))
ent <- rf_open_entry(1L, BID, base_grade = "NA",
  paper_key = sprintf("combo:%s+%s", top$a$paper_key, top$b$paper_key), paper_id = "",
  base_artifacts = "", engine_path = top$a$engine,
  count_paper = FALSE,   # 결합은 새 논문 소비가 아니다 — 3편 주기를 건드리지 않는다
  root = ROOT)

# base_signal 을 blend 로 박는다. 러너는 entry$engine_path 를 쓰므로 별도 필드로 알린다.
o <- fromJSON(file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
k <- which(vapply(o$entries, function(z) identical(z$base_id, BID), logical(1)))[1]
o$entries[[k]]$base_signal <- list(kind = "engine_blend",
                                   paths = list(top$a$engine, top$b$engine))
o$entries[[k]]$combo <- list(a = top$a$paper_key, b = top$b$paper_key,
                             a_t = top$a$t, b_t = top$b$t,
                             note = paste0("논문 간 결합 — 두 엔진 신호를 월별 rank-Z 평균해 새 기저를 만든다. ",
                                           "격자 25칸은 그 위에서 그대로 돈다(새 격자 없음). ",
                                           "판정: 첫 셀이 두 단독 기저(t ", sprintf("%.3f / %.3f", top$a$t, top$b$t),
                                           ")를 넘는지 — 못 넘으면 결합이 희석이다."))
txt <- toJSON(o, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6)
stopifnot(length(fromJSON(txt, simplifyVector = FALSE)$entries) == length(o$entries))
writeLines(txt, file.path(ROOT, "06_Registry/reinforce_ledger_l1.json"), useBytes = TRUE)
jlog("combo_entry_opened", base_id = BID,
     pair = paste(top$a$paper_key, top$b$paper_key, sep = "+"),
     a_t = top$a$t, b_t = top$b$t)
cat(sprintf("\n결합 entry 개설: %s\n  기저 = %s + %s (rank-Z 평균)\n  다음 tick 부터 25칸이 이 기저 위에서 돕니다.\n",
            BID, basename(top$a$engine), basename(top$b$engine)))
