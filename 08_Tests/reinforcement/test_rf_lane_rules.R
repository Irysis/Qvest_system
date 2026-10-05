#!/usr/bin/env Rscript
#==============================================================================
# test_rf_lane_rules.R — 유기체 밖 사람 규칙 정본(rf_lane_rules.R) + 예산 가산 차단(rf_runner_gates.R::rf_budget_auto) 양방향 검사
#   (2026-09-25 · 유기적 강화 설계 최종판 §1.1 '유기체 밖 사람 규칙' · §11 · 결정 D-G · B3-STRUCTURAL-TRIM · ORGANIC-DE Q②′(α))
#
# 재는 것 — 양성 대조 · 위반 주입 · 돌연변이(각 가드를 끈 사본이 해당 절에서 red):
#   A 레인 설정 판독(깨진 설정 = ok FALSE · 구판 거동)       B 레인 순위 선택(prereg > 신규 > 승격 > 반사실 · 실험 제외 · 구판 폴백)
#   C 차단 active(반사실·실험 비차단)                         D FIFO(exhausted_at 오름차순 · 이월·실험 제외 · 판독 불가 뒤로)
#   E 승격 세대 하한(D-G ≥1 · 결합·실험 미계수 · 시도 요청 계수)  F 구조 상태(B3 diag · 결합 ③⑤ · 진입 동결 · 불변식 ①④⑤ 항등)
#   G D-G B5 축소(연속 compose_only ≥ K · 유효 pass 복원 · 표식 pass 미계수 · 진입 동결 · ④)
#   H 예산 가산 차단(최종 B5 칸 수 · 축소분 재가산 없음 · 구판 산식 호환)   I 배선(러너·next_paper·레인 셸이 정본 함수를 부른다 — AST)
#   M 돌연변이 12종
# 쓰기 = tempdir() 뿐. ROOT = QM_ROOT(샌드박스·배포 미러) — 픽스처는 합성(운영 원장·상태를 빌리지 않는다).
#==============================================================================
suppressMessages(library(jsonlite))
.slash <- function(p) sub("/+$", "", gsub("\\\\", "/", p))   # 경로 정규화 함수 대신 구분자만 통일(저장소 규칙 — 한글 경로)
ROOT <- .slash(Sys.getenv("QM_ROOT", getwd())); stopifnot(dir.exists(ROOT))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
LIB <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_lane_rules.R")
GATES <- file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")
TMPB <- .slash(tempfile("rflanes_")); dir.create(TMPB, recursive = TRUE)
if (startsWith(tolower(TMPB), tolower(paste0(ROOT, "/")))) stop("tempdir 가 ROOT 안이다 — TMPDIR 을 루트 밖으로")
load_lib <- function(path) { e <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), envir = e))))
  invisible(capture.output(suppressMessages(sys.source(path, envir = e)))); e }
L0 <- load_lib(LIB)
CFG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE)
PROG <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)

## ── 픽스처 ─────────────────────────────────────────────────────────────────────────────────
en <- function(id, status = "active", priority = NULL, parent = NULL, experiment = NULL, opened = "2026-09-20T10:00:00+0900",
               exhausted = NULL, handed = NULL, combo = NULL, attempts = list(), used = NULL) {
  e <- list(base_id = id, status = status, opened_at = opened, attempts = attempts, attempts_used = used %||% length(attempts))
  if (!is.null(priority)) e$priority <- priority
  if (!is.null(parent)) e$parent <- list(base_id = parent, depth = 1L)
  if (!is.null(experiment)) e$experiment <- experiment
  if (!is.null(exhausted)) e$exhausted_at <- exhausted
  if (!is.null(handed)) e$handed_off <- handed
  if (!is.null(combo)) e$combo <- combo
  e }
att <- function(code, measured = TRUE, adversary = NULL, flags = NULL) {
  a <- list(n = 1L, cell_code = code, essence = if (measured) list(cell_code = code, port_t = 1) else NULL)
  if (!is.null(adversary)) a$adversary <- adversary
  if (!is.null(flags)) a$vintage_flags <- flags
  a }
ids <- function(l) vapply(l, function(e) as.character(e$base_id), character(1))

## ── A 설정 ───────────────────────────────────────────────────────────────────────────────────
secA <- function(L) {
  c1 <- L$rf_lane_cfg(CFG)
  r <- isTRUE(c1$ok) && identical(c1$order, c("prereg", "new_paper", "promotion", "counterfactual")) && identical(c1$nonblocking, "idle_only") &&
       identical(c1$min_new, 1L)
  bad1 <- CFG; bad1$lanes$order <- list("prereg", "new_paper", "promotion")
  bad2 <- CFG; bad2$lanes$nonblocking_priorities <- list("ghost")
  bad3 <- CFG; bad3$lanes$min_new_papers_per_promotion_generation <- "x"
  bad4 <- CFG; bad4$lanes <- NULL
  r2 <- !isTRUE(L$rf_lane_cfg(bad1)$ok) && !isTRUE(L$rf_lane_cfg(bad2)$ok) && !isTRUE(L$rf_lane_cfg(bad3)$ok) && !isTRUE(L$rf_lane_cfg(bad4)$ok)
  list(pos = r, neg = r2)
}
cat("=== A. 레인 설정 ===\n")
a <- secA(L0)
chk(a$pos, "A1 운영 설정 lanes 판독 — 순서 4레인 · 비차단 idle_only · 세대 하한 1(D-G 원문)")
chk(a$neg, "A2 위반 주입 4종(레인 누락 · 어휘 밖 비차단 · 하한 판독 불가 · 블록 부재) → ok=FALSE(구판 거동)")

## ── B 선택 ───────────────────────────────────────────────────────────────────────────────────
LN <- L0$rf_lane_cfg(CFG)
FIXB <- list(en("CF", priority = "idle_only"), en("PROMO", parent = "X"), en("NEW"), en("EXP", priority = "prereg", experiment = list(prereg_id = "PR-T")),
             en("PRE", priority = "prereg"), en("DONE", status = "exhausted"))
secB <- function(L) {
  s <- L$rf_lane_select(FIXB, LN)
  s0 <- L$rf_lane_select(FIXB, list(ok = FALSE))
  list(order = identical(ids(s$entries), c("PRE", "NEW", "PROMO", "CF")) && identical(s$excluded_experiment, "EXP"),
       lanes = identical(s$lanes, c("prereg", "new_paper", "promotion", "counterfactual")),
       legacy = identical(ids(s0$entries), c("CF", "PROMO", "NEW", "EXP", "PRE")))
}
cat("=== B. 레인 순위 선택 ===\n")
b <- secB(L0)
chk(b$order, "B1 active 순서 = prereg > 신규 논문 > 승격 > 반사실 · 실험 entry 제외(전용 실행기 몫)")
chk(b$lanes, "B2 레인 판정 — priority 지정(prereg·idle_only) · 구조(부모 = 승격 · 없음 = 신규)")
chk(b$legacy, "B3 설정 깨짐 → 구판 거동(원장 순서 · 제외 없음)")

## ── C 차단 ───────────────────────────────────────────────────────────────────────────────────
secC <- function(L) list(
  only_cf = length(L$rf_blocking_active(list(en("CF", priority = "idle_only"), en("EXP", priority = "prereg", experiment = list(a = 1))), LN)) == 0L,
  normal  = identical(ids(L$rf_blocking_active(list(en("CF", priority = "idle_only"), en("NEW")), LN)), "NEW"),
  legacy  = length(L$rf_blocking_active(list(en("CF", priority = "idle_only"), en("NEW")), list(ok = FALSE))) == 2L)
cat("=== C. 차단 active ===\n")
cc <- secC(L0)
chk(cc$only_cf, "C1 반사실(idle_only)·실험 entry 만 active → 차단 0(개설·충실구현 진행 — D8-02)")
chk(cc$normal, "C2 신규 논문(normal) active 는 막는다")
chk(cc$legacy, "C3 설정 깨짐 → active 전부 차단(구판)")

## ── D FIFO — 원장 [10]·[11]·[26]·[47]·[61] 형태(시각은 픽스처 리터럴 · 원장 순서 ≠ 시각 순서) ─────────────────────
FIXD <- list(en("E10_promo4", status = "exhausted", exhausted = "2026-09-21T16:28:05+0900"),
             en("E11_cf", status = "exhausted", exhausted = "2026-09-21T20:12:04+0900"),
             en("E26_cf", status = "exhausted", exhausted = "2026-09-21T23:32:04+0900"),
             en("E47_cf", status = "exhausted", exhausted = "2026-09-22T02:47:20+0900"),
             en("E61_promo1", status = "exhausted", exhausted = "2026-09-23T21:39:42+0900"),
             en("E05_old", status = "exhausted", exhausted = "2026-09-01T00:00:00+0900", handed = TRUE),
             en("EXP_arm", status = "exhausted", exhausted = "2026-09-01T00:00:00+0900", experiment = list(prereg_id = "P")),
             en("BAD_time", status = "exhausted", exhausted = "not-a-time"),
             en("E00_first", status = "exhausted", exhausted = "2026-09-20T09:00:00+09:00"))
secD <- function(L) {
  f <- L$rf_fifo_exhausted(rev(FIXD))
  list(order = identical(f$ids, c("E00_first", "E10_promo4", "E11_cf", "E26_cf", "E47_cf", "E61_promo1", "BAD_time")),
       skipped = identical(f$skipped_experiment, "EXP_arm"), unread = identical(f$time_unreadable, "BAD_time"))
}
cat("=== D. FIFO ===\n")
d <- secD(L0)
chk(d$order, "D1 exhausted_at 오름차순(원장 역순 입력 · 콜론 오프셋 판독 · 이월 완료 제외) — 구판 LIFO 면 E61 이 먼저")
chk(d$skipped, "D2 실험 entry 는 요약·승격 대상에서 제외")
chk(d$unread, "D3 시각 판독 불가 → 끝으로(로그 대상)")

## ── E 세대 하한 ───────────────────────────────────────────────────────────────────────────────
T0 <- "2026-09-23T16:29:49+0900"
FIXE_base <- list(en("P0", status = "exhausted", opened = "2026-09-10T00:00:00+0900"),
                  en("P0_promo1", status = "exhausted", parent = "P0", opened = T0))
secE <- function(L) {
  g0 <- L$rf_generation_gate(list(en("A0", status = "exhausted")), LN)
  g1 <- L$rf_generation_gate(FIXE_base, LN)
  g2 <- L$rf_generation_gate(c(FIXE_base, list(en("NEWP", opened = "2026-09-23T23:31:09+0900"))), LN)
  g3 <- L$rf_generation_gate(c(FIXE_base, list(en("COMBO", opened = "2026-09-24T00:00:00+0900", combo = list(a = 1)),
                                               en("EXPX", opened = "2026-09-24T00:00:00+0900", priority = "prereg", experiment = list(a = 1)),
                                               en("CFX", opened = "2026-09-24T00:00:00+0900", priority = "idle_only"),
                                               en("OLD_NEW", opened = "2026-09-22T00:00:00+0900"))), LN)
  g4 <- L$rf_generation_gate(FIXE_base, LN, request = list(requested_at = "2026-09-24T01:00:00+0900", status = "exhausted_retries"))
  g5 <- L$rf_generation_gate(FIXE_base, LN, request = list(requested_at = "2026-09-24T01:00:00+0900", status = "pending"))
  L1 <- LN; L1$min_new <- 0L
  g6 <- L$rf_generation_gate(FIXE_base, L1)
  list(noprior = isTRUE(g0$ok), deny = !isTRUE(g1$ok) && identical(g1$why, "new_paper_first") && identical(g1$last_promotion, "P0_promo1"),
       allow = isTRUE(g2$ok) && identical(g2$n_new_entries, 1L), nocount = !isTRUE(g3$ok) && identical(g3$n_new_entries, 0L),
       req = isTRUE(g4$ok) && identical(g4$n_request_attempts, 1L), pend = !isTRUE(g5$ok), zero = isTRUE(g6$ok))
}
cat("=== E. 승격 세대 하한(D-G) ===\n")
e <- secE(L0)
chk(e$noprior, "E1 이전 승격 없음 → 허용")
chk(e$deny, "E2 최근 승격 뒤 신규 논문 0 → 거부(new_paper_first) · 기준 = 가장 최근 승격 자식")
chk(e$allow, "E3 최근 승격 뒤 신규 논문 1 → 허용")
chk(e$nocount, "E4 결합·실험·반사실·승격 전 개설은 신규 논문으로 세지 않는다")
chk(e$req, "E5 승격 뒤 발행돼 entry 없이 끝난 요청(exhausted_retries)은 착수로 센다")
chk(e$pend, "E6 진행 중 요청(pending)은 아직 착수가 아니다")
chk(e$zero, "E7 하한 0(설정) → 항상 허용 — 값은 설정에서 온다")

## ── F 구조 상태 ─────────────────────────────────────────────────────────────────────────────
grid_cells <- function(prog) do.call(c, lapply(prog$blocks, function(b) lapply(b$cells, function(c) { c$block <- b$id; c$axis <- b$axis; c })))
codes <- function(cl) vapply(cl, function(c) as.character(c$code), character(1))
## ★B4 기대값 = 격자에서 재도출(2026-10-03 · 결정 B4-SIX-AXIS-AND-CARRY-AXES 로 B4 가 5칸 → 7칸) — 리터럴(B4_22·23·25 · 21:25)은 격자 확장에서 red.
##   불변식 문언 그대로: ③ combo.use 에 B3(diag 블록 — F1 이 확인)이 든 칸을 뺀다 · ⑤ use 가 가장 넓은 칸(전 승자 결합)은 남긴다.
##   구 5칸 격자 = drop B4_22·23·25 / keep B4_21·24 · 7칸 격자 = drop B4_22·23·25·43·44 / keep B4_21·24.
.b4g <- (Filter(function(b) identical(b$id, "B4"), PROG$blocks)[[1]])$cells
.b4u <- lapply(.b4g, function(c) as.character(unlist(c$combo$use)))
B4_CODES <- vapply(.b4g, function(c) as.character(c$code), character(1))
B4_WIDE <- B4_CODES[lengths(.b4u) == max(lengths(.b4u))]
B4_DROP <- setdiff(B4_CODES[vapply(.b4u, function(u) "B3" %in% u, logical(1))], B4_WIDE)
B4_KEEP <- setdiff(B4_CODES, B4_DROP)
N_B3 <- length((Filter(function(b) identical(b$id, "B3"), PROG$blocks)[[1]])$cells)
secF <- function(L) {
  out <- list()
  S <- L$rf_structure_rules(PROG)
  out$rules <- length(S$rules) == 1L && identical(S$rules[[1]]$block, "B3") && identical(S$rules[[1]]$keep, "B3_12") && !length(S$invalid)
  cd <- L$rf_structure_combo_drop(PROG, "B3", "B4")
  out$combo <- identical(cd$drop, B4_DROP) && identical(cd$keep_widest, B4_WIDE) && length(B4_WIDE) == 1L && length(B4_DROP) >= 1L &&
               length(setdiff(B4_KEEP, B4_WIDE)) >= 1L   # B3 미참조 LOO 칸이 격자에 있어야 ③ 이 '참조 칸만' 을 가른다(퇴화 격자 거부)
  bad <- PROG
  bad$structure_rules$rules <- list(list(id = "x1", block = "B9", state = "diag", keep_cells = list("B9_1")),
                                    list(id = "x2", block = "B1", state = "dormant"),
                                    list(id = "x3", block = "B3", state = "diag", keep_cells = list("B3_99")),
                                    list(id = "x4", block = "B3", state = "gone"))
  out$invalid <- length(L$rf_structure_rules(bad)$invalid) == 4L && !length(L$rf_structure_rules(bad)$rules)
  gc <- grid_cells(PROG)
  E1 <- en("N1", attempts = list())
  c1 <- L$rf_structure_cells(gc, E1, PROG); i1 <- attr(c1, "structure_trim")
  b3 <- codes(Filter(function(c) identical(c$block, "B3"), c1)); b4 <- codes(Filter(function(c) identical(c$block, "B4"), c1))
  out$new <- identical(b3, "B3_12") && identical(b4, B4_KEEP) && isTRUE(i1$applied) && length(c1) == length(gc) - (N_B3 - 1L) - length(B4_DROP) &&
             identical(codes(c1)[1:5], codes(gc)[1:5])
  ## 설계가 B3 을 통째로 갈았다(설계 칸 = B3_13·B3_15) → 격자 진단 칸으로 되돌린다(같은 자리)
  gd <- gc; kb <- which(vapply(gd, function(c) identical(c$block, "B3"), logical(1)))
  des <- list(list(code = "B3_13", block = "B3", universe = list(kind = "size_band")), list(code = "B3_15", block = "B3", universe = list(kind = "sector_neutral")))
  gd <- append(gd[-kb], des, after = kb[1] - 1L)
  c2 <- L$rf_structure_cells(gd, E1, PROG)
  k2 <- which(codes(c2) == "B3_12")
  out$design <- identical(codes(Filter(function(c) identical(c$block, "B3"), c2)), "B3_12") && length(k2) == 1L &&
                identical(c2[[k2 - 1L]]$block, "B2") && identical(attr(c2, "structure_trim")$inserted, "B3_12")
  ## 진입한 B3 = 동결(설계 4칸 그대로) · B4 는 미진입이라 절단(상태 기준 — 불변식 ③)
  E3 <- en("N3", attempts = list(att("B1_1"), att("B3_13"), att("B3_15")), used = 3L)
  c3 <- L$rf_structure_cells(gd, E3, PROG)
  out$frozen3 <- identical(codes(Filter(function(c) identical(c$block, "B3"), c3)), c("B3_13", "B3_15")) &&
                 identical(codes(Filter(function(c) identical(c$block, "B4"), c3)), B4_KEEP) && "B3" %in% attr(c3, "structure_trim")$frozen
  ## 절단 계획으로 진입한 B3(시도 = keep B3_12 뿐)은 동결이 아니다 — 다음 tick 에 절단 칸이 되살아나면 안 된다
  E3b <- en("N3b", attempts = list(att("B1_1"), att("B3_12")), used = 2L)
  c3b <- L$rf_structure_cells(gc, E3b, PROG)
  out$trimmed_entered <- identical(codes(Filter(function(c) identical(c$block, "B3"), c3b)), "B3_12") && !("B3" %in% attr(c3b, "structure_trim")$frozen)
  ## 절단 전 계획으로 진입한 B4(뺄 칸 B4_22 시도) = 동결
  E4 <- en("N4", attempts = list(att("B4_22")), used = 1L)
  c4 <- L$rf_structure_cells(gc, E4, PROG)
  out$frozen4 <- identical(codes(Filter(function(c) identical(c$block, "B4"), c4)), B4_CODES) &&
                 identical(codes(Filter(function(c) identical(c$block, "B3"), c4)), "B3_12")
  ## 불변식 ④: 절단 뒤 빈 칸이 남는데 used ≥ 칸 수 → 항등(원장 used 가 고유 코드 수보다 큰 entry — 설계 §0.2-4 경로 ②)
  E5 <- en("N5", attempts = list(att("B1_1"), att("B1_2")), used = length(gc) - 3L)
  c5 <- L$rf_structure_cells(gc, E5, PROG)
  out$inv4 <- identical(attr(c5, "structure_trim")$reason, "inv4_identity") && identical(codes(c5), codes(gc))
  ## 대조: 같은 entry 인데 used 가 작으면 적용
  E5b <- E5; E5b$attempts_used <- 2L
  out$inv4_ctrl <- isTRUE(attr(L$rf_structure_cells(gc, E5b, PROG), "structure_trim")$applied)
  ## 규칙 없음 → 항등
  p0 <- PROG; p0$structure_rules <- NULL
  c6 <- L$rf_structure_cells(gc, E1, p0)
  out$norule <- identical(codes(c6), codes(gc)) && identical(attr(c6, "structure_trim")$reason, "no_rules")
  ## 불변식 ⑤: 전 승자 결합 칸이 결과에서 빠지는 규칙(가짜 dormant B2 + 결합 넓은 칸 상실 유도)은 항등
  p5 <- PROG; p5$structure_rules$rules <- c(p5$structure_rules$rules, list(list(id = "x5", block = "B2", state = "dormant")))
  c7 <- L$rf_structure_cells(gc, E1, p5)
  out$inv5_keep <- all(B4_WIDE %in% codes(c7))
  ## 정지 방지 종단: 절단된 새 entry 가 모든 칸을 시도하면 격자 소진(rf_grid_consumed) — 예산(MAXA 35)이 칸 수보다 커도
  allc <- codes(c1)
  E6 <- en("N6", attempts = lapply(allc, att), used = length(allc))
  c8 <- L$rf_structure_cells(gc, E6, PROG)
  out$consumed <- isTRUE(L$rf_grid_consumed(c8, E6$attempts)) && length(c8) < 35L   # 35 = 원장 기본 예산(7블록×5) — 예산이 칸 수보다 크다
  out
}
cat("=== F. 격자 구조 상태(B3-STRUCTURAL-TRIM) ===\n")
f <- secF(L0)
chk(f$rules, "F1 운영 격자 structure_rules = B3 diag · keep B3_12 · 무효 0")
chk(f$combo, sprintf("F2 결합 절단 = %s(B3 참조 · 격자 재도출) · %s(전 승자 결합) 보존 · %s(B3 미참조) 유지 — 불변식 ③⑤",
                     paste(B4_DROP, collapse = "·"), paste(B4_WIDE, collapse = "·"), paste(setdiff(B4_KEEP, B4_WIDE), collapse = "·")))
chk(f$invalid, "F3 위반 주입 4종(없는 블록 · 보호 블록 B1 · 격자 밖 keep · 어휘 밖 state) → 전부 무효 · 적용 0")
chk(f$new, sprintf("F4 새 entry — B3 = [B3_12] · B4 = [%s] · %d칸 감소 · 앞 블록 순서 불변", paste(B4_KEEP, collapse = ", "), (N_B3 - 1L) + length(B4_DROP)))
chk(f$design, "F5 B3 설계 칸(비진단)이 있어도 미진입이면 격자 진단 칸으로(같은 자리 · inserted 기록)")
chk(f$frozen3, "F6 진입한 B3 는 동결(시도 코드 보존 — 불변식 ①②) · 미진입 B4 는 상태 기준으로 절단(③)")
chk(f$trimmed_entered, "F6b 절단 계획으로 진입한 B3(B3_12 만 시도)는 계속 절단 — 동결 판정이 절단 칸을 되살리지 않는다")
chk(f$frozen4, sprintf("F7 절단 전 계획으로 진입한 B4(B4_22 시도)는 동결 — 격자 B4 %d칸 그대로", length(B4_CODES)))
chk(f$inv4, "F8 불변식 ④ — 빈 칸이 남는데 used ≥ 절단 뒤 칸 수 → 항등(halt_no_jobs 영구 정지 차단)")
chk(f$inv4_ctrl, "F9 대조 — 같은 entry · used 작음 → 적용(④ 가드가 늘 발화하는 계기 아님)")
chk(f$norule, "F10 structure_rules 없음 → 항등(no_rules)")
chk(f$inv5_keep, sprintf("F11 불변식 ⑤ — 다른 블록이 더 줄어도 전 승자 결합 칸 %s 은 남는다", paste(B4_WIDE, collapse = ",")))
chk(f$consumed, "F12 정지 방지 종단 — 절단 격자를 다 채우면 rf_grid_consumed = TRUE(MAXA > 칸 수여도 격자 소진으로 닫힌다 · K9 양성 대조)")

## ── G D-G B5 축소 ───────────────────────────────────────────────────────────────────────────
rnd <- function(at, co) list(round = 1L, at = at, compose_only = co)
FIXG_rounds <- list(en("R1", status = "exhausted"), en("R2", status = "exhausted"), en("R3", status = "exhausted"))
FIXG_rounds[[1]]$b5_design <- list(rounds = list(rnd("2026-09-19T00:00:00+0900", FALSE)))
FIXG_rounds[[2]]$b5_design <- list(rounds = list(rnd("2026-09-21T00:00:00+0900", TRUE)))
FIXG_rounds[[3]]$b5_design <- list(rounds = list(rnd("2026-09-22T00:00:00+0900", TRUE), rnd("2026-09-23T00:00:00+0900", TRUE)))
passA <- function(at, flags = NULL) { a <- att("B5_16", adversary = list(verdict = "pass", recorded_at = at)); if (!is.null(flags)) a$vintage_flags <- flags; a }
GATE_STAR <- list(vintage_flags = "*", vintage_verdicts = c("consumed", "consumed_absence", "possible"))
b5cells <- c(list(list(code = "B1_1", block = "B1")), list(list(code = "B5_31", block = "B5", standing = TRUE)),
             lapply(16:23, function(k) list(code = sprintf("B5_%d", k), block = "B5")), list(list(code = "B4_21", block = "B4")))
secG <- function(L) {
  o <- list()
  d1 <- L$rf_b5_budget_decide(FIXG_rounds, CFG, G = GATE_STAR)
  o$active <- isTRUE(d1$active) && identical(d1$run_len, 3L) && identical(d1$run_start, "2026-09-21T00:00:00+0900")
  fx <- FIXG_rounds; fx[[1]]$attempts <- list(passA("2026-09-22T12:00:00+0900"))
  d2 <- L$rf_b5_budget_decide(fx, CFG, G = GATE_STAR)
  o$restore <- !isTRUE(d2$active) && identical(d2$why, "g2_pass_restore") && identical(d2$n_valid_pass, 1L)
  fy <- FIXG_rounds; fy[[1]]$attempts <- list(passA("2026-09-22T12:00:00+0900", flags = list(list(flag = "pit_c11", verdict = "consumed"))))
  d3 <- L$rf_b5_budget_decide(fy, CFG, G = GATE_STAR)
  o$flagged <- isTRUE(d3$active) && identical(d3$n_pass_flagged, 1L) && identical(d3$n_evidence, 1L)
  fz <- FIXG_rounds; fz[[1]]$attempts <- list(passA("2026-09-20T12:00:00+0900"))
  o$before <- isTRUE(L$rf_b5_budget_decide(fz, CFG, G = GATE_STAR)$active)
  fs <- FIXG_rounds; fs[[3]]$b5_design$rounds[[2]]$compose_only <- FALSE
  d5 <- L$rf_b5_budget_decide(fs, CFG, G = GATE_STAR)
  o$short <- !isTRUE(d5$active) && identical(d5$why, "compose_only_run_short")
  cd <- CFG; cd$b5_budget$enabled <- FALSE
  o$disabled <- identical(L$rf_b5_budget_decide(FIXG_rounds, cd)$why, "disabled")
  cb <- CFG; cb$b5_budget$standing_plus <- "two"
  o$badcfg <- !isTRUE(L$rf_b5_budget_decide(FIXG_rounds, cb)$active) && !isTRUE(L$rf_b5_budget_cfg(cb)$ok)
  c1 <- L$rf_b5_budget_cells(b5cells, en("NB5"), d1)
  o$cells <- identical(codes(c1), c("B1_1", "B5_31", "B5_16", "B5_17", "B4_21")) && identical(attr(c1, "b5_budget")$removed, sprintf("B5_%d", 18:23))
  c2 <- L$rf_b5_budget_cells(b5cells, en("EB5", attempts = list(att("B5_20")), used = 1L), d1)
  c2b <- L$rf_b5_budget_cells(b5cells, en("EB5b", attempts = list(att("B5_16")), used = 1L), d1)
  o$frozen <- identical(codes(c2), codes(b5cells)) && identical(attr(c2, "b5_budget")$reason, "b5_entered_frozen") &&
              identical(codes(c2b), c("B1_1", "B5_31", "B5_16", "B5_17", "B4_21"))
  c3 <- L$rf_b5_budget_cells(b5cells, en("UB5", attempts = list(att("B1_1")), used = 9L), d1)
  o$inv4 <- identical(codes(c3), codes(b5cells)) && identical(attr(c3, "b5_budget")$reason, "inv4_identity")
  c4 <- L$rf_b5_budget_cells(b5cells, en("NB5"), d2)
  o$inactive <- identical(codes(c4), codes(b5cells))
  G_called <- 0L; gf <- function() { G_called <<- G_called + 1L; GATE_STAR }
  invisible(L$rf_b5_budget_decide(FIXG_rounds, CFG, gate_fn = gf)); n0 <- G_called
  invisible(L$rf_b5_budget_decide(fx, CFG, gate_fn = gf))
  o$lazy <- n0 == 0L && G_called == 1L
  o
}
cat("=== G. D-G B5 적응 축소 ===\n")
g <- secG(L0)
chk(g$active, "G1 연속 compose_only 3 ≥ K 2 ∧ 구간 뒤 유효 G2 pass 0 → 축소(구간 시작 = 첫 연속 라운드)")
chk(g$restore, "G2 구간 뒤 유효 G2 pass 1 → 즉시 복원(pass 시 복원)")
chk(g$flagged, "G3 표식(pit_c11) 칸의 pass 는 A 관문과 같은 필터로 무효 — 축소 유지 · 증거 칸 수 계상(N_program)")
chk(g$before, "G4 구간 시작 전 pass 는 복원 사유가 아니다")
chk(g$short, "G5 끝 라운드가 compose_only 아니면(연속 끊김) 축소 없음")
chk(g$disabled, "G6 enabled=false → 항등(kill switch)")
chk(g$badcfg, "G7 값 판독 불가 → 규칙 꺼짐(추정값으로 돌지 않는다)")
chk(g$cells, "G8 B5 = 상주 칸 전부 + 비상주 앞 2칸(standing_plus · 설계 순서) · 다른 블록 불변")
chk(g$frozen, "G9 축소 전 계획으로 진입한 B5(남길 칸 밖 B5_20 시도)는 동결 · 축소 계획으로 진입(B5_16)은 계속 축소")
chk(g$inv4, "G10 불변식 ④ — 절단 뒤 used ≥ 칸 수 · 빈 칸 남음 → 항등")
chk(g$inactive, "G11 비활성 판정 → 항등")
chk(g$lazy, "G12 관문 설정은 구간 안 pass 가 있을 때만 읽는다(매 tick 판독 없음)")

## ── H 예산 가산 차단 ─────────────────────────────────────────────────────────────────────────
secH <- function(GE) list(
  same = all(vapply(list(c(8L, 7L, 1L, 0L), c(8L, 5L, 0L, 0L), c(5L, 5L, 1L, 3L), c(0L, 0L, 1L, 0L)), function(v) {
    n5 <- (if (v[2] > 0L) v[2] else 5L) + v[3] + v[4]
    GE$rf_budget_auto(35L, v[1], v[2], v[3], v[4]) == GE$rf_budget_auto(35L, v[1], v[2], v[3], v[4], n_b5_cells = n5) }, logical(1))),
  blocked_standing = GE$rf_budget_auto(35L, 0L, 3L, 1L, 0L) == 36L && GE$rf_budget_auto(35L, 0L, 3L, 1L, 0L, n_b5_cells = 4L) == 35L,
  blocked_trim = GE$rf_budget_auto(35L, 0L, 8L, 1L, 0L) == 39L && GE$rf_budget_auto(35L, 0L, 8L, 1L, 0L, n_b5_cells = 3L) == 35L,
  b1_kept = GE$rf_budget_auto(35L, 11L, 0L, 0L, 0L, n_b5_cells = 5L) == 41L)
cat("=== H. 예산 가산 차단(rf_budget_auto n_b5_cells) ===\n")
GE0 <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(GATES, envir = GE0))))
h <- secH(GE0)
chk(h$same, "H1 설계 ≥ 슬롯이면 새 산식(최종 B5 칸 수) = 구판 산식 — 기존 격자·예산 불변(C11~C20 값 보존)")
chk(h$blocked_standing, "H2 설계 3 + 상주 1 = 4칸(슬롯 안) → 구판 +1 · 새 산식 +0(무조건 가산 차단)")
chk(h$blocked_trim, "H3 D-G 축소(설계 8 → 최종 3칸) → 구판 +4 · 새 산식 +0(축소분 재가산 차단)")
chk(h$b1_kept, "H4 B1 설계 초과는 그대로 더한다(09-04 지시 · B1 칸 수 제한 없음)")

## ── I 배선(AST) — 소비자가 정본 함수를 실제로 부른다 ─────────────────────────────────────────────
calls_of <- function(path) { pd <- getParseData(parse(path, encoding = "UTF-8", keep.source = TRUE)); pd$text[pd$token == "SYMBOL_FUNCTION_CALL"] }
syms_of <- function(path) { pd <- getParseData(parse(path, encoding = "UTF-8", keep.source = TRUE)); pd }
RUN <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"); NP <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R")
cr <- calls_of(RUN); cn <- calls_of(NP)
chk(all(c("rf_lane_select", "rf_blocking_active", "rf_request_inflight", "rf_structure_cells", "rf_b5_budget_decide", "rf_b5_budget_cells",
          "rf_block_cell_count") %in% cr), "I1 러너가 정본 함수 7종을 부른다(레인 선택 · 양보 · 구조 · D-G · 예산 칸 수)")
pr <- syms_of(RUN)
ln_of <- function(pd, fn) min(pd$line1[pd$token == "SYMBOL_FUNCTION_CALL" & pd$text == fn])
chk(ln_of(pr, "rf_structure_cells") < ln_of(pr, "rf_budget_auto") && ln_of(pr, "rf_b5_budget_cells") < ln_of(pr, "rf_budget_auto") &&
    ln_of(pr, "rf_standing_decision") < ln_of(pr, "rf_structure_cells"),
    "I2 러너 순서 — 상주 삽입 → 구조 상태 → D-G B5 → 예산 재도출(예산이 최종 칸 목록을 센다)")
ba <- pr[pr$token == "SYMBOL_SUB" & pr$text == "n_b5_cells", ]
chk(nrow(ba) >= 1L, "I3 러너 예산 호출이 n_b5_cells 를 넘긴다(가산 차단 배선)")
chk(all(c("rf_fifo_exhausted", "rf_blocking_active", "rf_generation_gate", "rf_claim_acquire") %in% cn), "I4 next_paper 가 FIFO · 차단 · 세대 하한 · 러너 claim 을 부른다")
pn <- syms_of(NP)
lifo <- grepl("ex[[length(ex)]]", paste(deparse(parse(NP, encoding = "UTF-8", keep.source = FALSE)), collapse = " "), fixed = TRUE)   # 주석 제외(코드만)
chk(!lifo, "I5 next_paper 에 LIFO(ex[[length(ex)]]) 없음")
chk(ln_of(pn, "rf_mark_summarized") < ln_of(pn, "rf_blocking_active"), "I6 halt 위치 — 요약 표식이 차단 판정보다 앞(개설 직전 halt)")
sh <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), warn = FALSE, encoding = "UTF-8")
chk(any(grepl("rf_blocking_active(d$entries, L)", sh, fixed = TRUE)), "I7 충실구현 레인 ACT = rf_blocking_active(파이썬 사본 없음)")

## ── M 돌연변이 — 가드를 끈 사본이 해당 절에서 red ────────────────────────────────────────────────
mut <- function(path, from, to) {
  s <- readLines(path, warn = FALSE, encoding = "UTF-8"); t <- paste(s, collapse = "\n")
  n <- lengths(regmatches(t, gregexpr(from, t, fixed = TRUE)))
  if (n != 1L) return(NULL)
  p <- file.path(TMPB, paste0("mut_", basename(tempfile()), "_", basename(path)))
  writeLines(sub(from, to, t, fixed = TRUE), p, useBytes = TRUE); p }
M <- list(
  list("M1 FIFO → LIFO", LIB, "o <- order(is.na(t), t, ix)", "o <- order(is.na(t), -t, -ix)", function(L) all(unlist(secD(L)))),
  list("M2 비차단 무시", LIB, "!(rf_entry_priority(e) %in% L$nonblocking)", "TRUE", function(L) all(unlist(secC(L)))),
  list("M3 세대 하한 항상 통과", LIB, "list(ok = (nn + nr) >= L$min_new,", "list(ok = TRUE,", function(L) all(unlist(secE(L)))),
  list("M4 진입 블록 동결 제거", LIB, "{ info$frozen <- c(info$frozen, r$block); next }", "{ }", function(L) all(unlist(secF(L)))),
  list("M5 불변식 ④ 항등 제거", LIB, 'if (length(free) && used >= length(out)) { info$reason <- "inv4_identity"; return(ret(cells, info)) }', "", function(L) all(unlist(secF(L)))),
  list("M6 전 승자 결합 보존 제거", LIB, "code[hit & !(seq_along(cc) %in% wide)]", "code[hit]", function(L) all(unlist(secF(L)))),
  list("M7 pass 복원 무시", LIB, 'if (nv > 0L && isTRUE(B$restore)) { base$why <- "g2_pass_restore"; return(base) }', "", function(L) all(unlist(secG(L)))),
  list("M8 B5 진입 동결 제거", LIB, '{ info$reason <- "b5_entered_frozen"; return(ret(cells)) }', "{ }", function(L) all(unlist(secG(L)))),
  list("M12 동결 = '블록 코드 시도 있음'(절단 칸 부활)", LIB, "if (length(setdiff(taken[startsWith(taken, paste0(r$block, \"_\"))], r$keep)))", "if (any(startsWith(taken, paste0(r$block, \"_\"))))", function(L) all(unlist(secF(L)))),
  list("M9 실험 entry 미제외", LIB, "act <- act[!ex]", "act <- act", function(L) all(unlist(secB(L)))),
  list("M10 표식 pass 필터 제거", LIB, "if (.rflr_flag_hit(a$vintage_flags, G %||% list())) nf <- nf + 1L else nv <- nv + 1L", "nv <- nv + 1L", function(L) all(unlist(secG(L)))),
  list("M11 예산 n_b5_cells 무시", GATES, "b5 <- if (!is.null(n_b5_cells))", "b5 <- if (FALSE)", NULL))
for (m in M) {
  p <- mut(m[[2]], m[[3]], m[[4]])
  if (is.null(p)) { ng(sprintf("%s — 돌연변이 앵커 불일치(검사가 대상 코드를 못 찾는다)", m[[1]])); next }
  alive <- if (is.null(m[[5]])) { e2 <- new.env(parent = globalenv()); invisible(capture.output(suppressMessages(sys.source(p, envir = e2)))); all(unlist(secH(e2))) }
           else tryCatch(m[[5]](load_lib(p)), error = function(e) FALSE)
  chk(!isTRUE(alive), sprintf("%s → red(돌연변이 사살)", m[[1]]), "돌연변이 생존 — 이 절은 방어선이 아니다")
}
unlink(TMPB, recursive = TRUE)
cat(sprintf("\n== test_rf_lane_rules: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_lane_rules","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
quit(status = if (F == 0L) 0L else 1L)
