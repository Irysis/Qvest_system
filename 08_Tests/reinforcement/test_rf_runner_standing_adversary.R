#!/usr/bin/env Rscript
#==============================================================================
# test_rf_runner_standing_adversary.R — 상주 칸 · 예산 재도출 · 적대검증 소비 · Grade A 보류 **양방향 검사** (WP-R · 2026-09-17)
#
# 재는 것 (판정은 정본 rf_runner_gates.R 의 순수 함수 · 배선은 러너 **블록을 소스에서 추출해 실행** · 부작용은 스텁):
#   A 상주 삽입 판정 — (a) 시도 존재 → 항상 (b) B5 미측정 ∧ active ∧ carry 밖 (c) 재설계 라운드 · 건너뜀 사유 4종
#   B 러너 배선 — B5 첫 칸 삽입 · 규칙 픽커가 비상주 슬롯만 채우고 상주 arm 을 제외 · 회피 집행 면제 (추출 실행 포함)
#   C 예산 — 산식(B4 미절단) · 수동 상향 존중 · 자동은 자동식 위로 못 올린다 · 재설계 열림/닫힘의 합이 같다 (추출 실행 포함)
#   D 승자 게이트 — 러너의 .winner_of 를 **소스에서 추출해** 돌린다: pass 유지 · fail/not_candidate 제외 · 구 attempt 유지 · 전멸 → NULL
#   E Grade A 보류 — B5 자기 층 ∧ pass 없음 → 보류 · pass → 발행 · B1 / 승계 층만 → 발행 · 경계 블록 추출 실행(해제·차단·미결·러너 무정지)
#   F lcm_merge — B5 시도가 있는 entry 의 B5 설계는 거부(기전은 병합) · 없는 entry 는 저장(양성 대조) — 격리 root 에서 실제 실행
#   G 서명 불변 — 실제 스펙 파일에 부기 필드를 **하나씩** 얹어도 .spec_sig 비트 동일(+돌연변이 통제 · $ 부분 일치 함정)
#   H 주변 배선 — 승격 호출부(cfg·parent_carry·adversary) · 충실구현 L-code 스위치 · tick 의 B5 레인 · 프롬프트 스택 계약 · 원장 writer
#   I 운영 entry 드라이(읽기 전용 · 상태가 그대로일 때만) — combo_rulefast 는 B5_31 을 자동 삽입하지 않는다
# 부작용 없음: 운영 원장·로그·설정 무접촉. 러너 블록은 tempdir 샌드박스 root + jlog/원장 writer 스텁 위에서만 돈다.
#   자식 Rscript 는 R_ENVIRON_USER=빈 파일(~/.Renviron 의 QM_ROOT 가 샌드박스를 덮지 못하게) + 샌드박스 지목을 단언한다.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R")))))
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R")))))
RUNNER <- file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R")
src  <- readLines(RUNNER, warn = FALSE, encoding = "UTF-8")
code <- sub("#.*$", "", src)                      # 판정 축은 실행 코드다 — 주석의 단어에 걸리지 않는다
body <- paste(code, collapse = "\n")
.has <- function(pat) grepl(pat, body, fixed = TRUE)
.at  <- function(pat) { i <- grep(pat, code, fixed = TRUE); if (length(i)) i[1] else NA_integer_ }
.first_after <- function(i0, re) { if (is.na(i0)) return(NA_integer_); k <- which(grepl(re, src[(i0 + 1L):length(src)]))[1]; if (is.na(k)) NA_integer_ else i0 + k }
.ev_of <- function(env) vapply(env$.LOG, function(z) as.character(z$event), character(1))
.logs  <- function(env, ev) Filter(function(z) identical(as.character(z$event), ev), env$.LOG)
.mkenv <- function() { env <- new.env(parent = globalenv()); env$.LOG <- list()
  env$jlog <- function(event, ...) env$.LOG[[length(env$.LOG) + 1L]] <- c(list(event = event), list(...)); env }
TMPD <- file.path(tempdir(), sprintf("rf_gates_%d", Sys.getpid())); dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)

cat("=== A. 상주 삽입 판정 (rf_standing_decision · 양방향) ===\n")
SC  <- list(code = "B5_31", block = "B5", label = "PG2 상주", overlay_pick = "pg2_risk_overlay_v1")
CAT <- list(list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", status = "active", basis = "책 사양"),
            list(id = "dd_brake_q", kind = "dd_brake", status = "active", basis = ""))
CAT_RET <- list(list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", status = "retired", basis = ""))
att <- function(code, n = 1L) list(n = n, cell_code = code, grade = "C", essence = list(cell_code = code, port_t = 1))
d <- rf_standing_decision(SC, list(att("B1_1")), NULL, CAT, FALSE)
if (isTRUE(d$insert) && identical(d$reason, "first_b5_round") && identical(d$kind, "pg2_risk_overlay")) ok("A1 (b) B5 미측정 ∧ active ∧ carry 밖 → 삽입 · kind 는 카탈로그에서") else ng("A1", paste(d$insert, d$reason, d$kind))
d <- rf_standing_decision(SC, list(att("B5_31"), att("B5_16", 2L)), NULL, CAT_RET, FALSE)
if (isTRUE(d$insert) && identical(d$reason, "attempt_exists")) ok("A2 (a) 그 코드의 시도가 있으면 retired 여도 항상 삽입(재개·소비 일관성)") else ng("A2", paste(d$insert, d$reason))
d <- rf_standing_decision(SC, list(att("B1_1"), att("B5_16", 2L)), NULL, CAT, FALSE)
if (isFALSE(d$insert) && identical(d$reason, "b5_measured_no_redesign")) ok("A3 B5 측정됨 ∧ 재설계 없음 → 건너뜀(b5_measured_no_redesign) ★운영 entry 형태") else ng("A3", paste(d$insert, d$reason))
d <- rf_standing_decision(SC, list(att("B1_1"), att("B5_16", 2L)), NULL, CAT, TRUE)
if (isTRUE(d$insert) && identical(d$reason, "redesign_round")) ok("A4 (c) 재설계 라운드 ∧ 코드 없음 → 삽입") else ng("A4", paste(d$insert, d$reason))
d <- rf_standing_decision(SC, list(att("B1_1")), NULL, CAT_RET, FALSE)
if (isFALSE(d$insert) && identical(d$reason, "arm_not_active")) ok("A5 arm retired ∧ 시도 없음 → arm_not_active") else ng("A5", paste(d$insert, d$reason))
d <- rf_standing_decision(SC, list(att("B1_1")), NULL, list(), FALSE)
if (isFALSE(d$insert) && identical(d$reason, "arm_not_in_catalog")) ok("A6 카탈로그에 없는 arm → arm_not_in_catalog") else ng("A6", paste(d$insert, d$reason))
d <- rf_standing_decision(SC, list(att("B1_1")), list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1"), CAT, FALSE)
if (isFALSE(d$insert) && identical(d$reason, "carry_has_arm")) ok("A7 carry 에 이미 깔린 arm → carry_has_arm(이중 축소 방지)") else ng("A7", paste(d$insert, d$reason))
d <- rf_standing_decision(list(code = "B5_31", block = "B5"), list(), NULL, CAT, FALSE)
if (isFALSE(d$insert) && identical(d$reason, "standing_cell_malformed")) ok("A8 pick 없는 상주 칸 → malformed") else ng("A8", paste(d$insert, d$reason))
if (!rf_b5_redesign_active(list()) && rf_b5_redesign_active(list(b5_redesign = list(active = TRUE, round = 2L))) &&
    !rf_b5_redesign_active(list(b5_redesign = list(active = FALSE, round = 2L))) && rf_b5_redesign_active(list(b5_redesign = TRUE)))
  ok("A9 rf_b5_redesign_active — 부재/active=FALSE → FALSE · active=TRUE / bare TRUE → TRUE (레인 계약)") else ng("A9 재설계 플래그 판독")
cs <- rf_standing_cell(SC, "pg2_risk_overlay", basis = "책 사양")
if (identical(cs$code, "B5_31") && identical(cs$block, "B5") && identical(cs$axis, "risk_overlay") && isTRUE(cs$standing) &&
    identical(cs$overlay, list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1")) && grepl("상주", cs$basis))
  ok("A10 rf_standing_cell — 규칙 픽커와 같은 모양 + standing=TRUE") else ng("A10 상주 셀 모양")

cat("\n=== B. 러너 배선 — 삽입 위치 · 픽커 슬롯 · 회피 면제 (소스 대조 + 블록 추출 실행) ===\n")
if (.has('rf_standing_decision(.sc, E$attempts') && .has('jlog("standing_cell_inserted"') && .has('jlog("standing_cell_skipped"'))
  ok("B1 러너가 정본 판정을 부르고 삽입·건너뜀을 둘 다 로그로 드러낸다") else ng("B1 상주 판정 미배선")
if (.has("append(cells, list(.cellS), after = .kB5[1] - 1L)")) ok("B2 상주 칸 = B5 **첫 칸**(첫 B5 배치에서 돈다)") else ng("B2 삽입 위치")
i_pk <- .at('identical(first$block, "B5") && is.null(.blk_design[["B5"]])')
blk_pk <- if (!is.na(i_pk)) paste(code[i_pk:min(length(code), i_pk + 30L)], collapse = "\n") else ""
if (grepl("rfbd_standing_picks(ROOT)", blk_pk, fixed = TRUE) && grepl(".slots <- rf_batch_open_slots(batch)", blk_pk, fixed = TRUE) &&
    grepl("rf_pick_overlay_arms(length(.slots)", blk_pk, fixed = TRUE) && grepl("batch[[.slots[j]]] <- .c", blk_pk, fixed = TRUE))
  ok("B3 규칙 픽커 — 상주 arm 제외 · 비상주 슬롯 수만큼 뽑아 그 슬롯에만 채운다") else ng("B3 픽커 슬롯 배선", substr(blk_pk, 1, 80))
if (identical(rf_batch_open_slots(list(list(code = "B5_31", standing = TRUE), list(code = "B5_16"), list(code = "B5_17"))), c(2L, 3L)) &&
    !length(rf_batch_open_slots(list(list(code = "B5_31", standing = TRUE)))) && identical(rf_batch_open_slots(list()), integer(0)))
  ok("B4 rf_batch_open_slots — 상주 제외 인덱스 · 전부 상주면 0(픽커 호출 없음)") else ng("B4 슬롯 함수")
i_ex <- .at('jlog("avoid_exempt_standing"'); i_av <- .at('grade = "NA (미결 — 기전 회피: 측정 무효 사유)"')
if (!is.na(i_ex) && !is.na(i_av) && i_ex < i_av && .has("!is.null(.avoid_hit) && isTRUE(CELL$standing)") &&
    grepl(".avoid_hit <- NULL", paste(code[i_ex:(i_ex + 3L)], collapse = "\n"), fixed = TRUE))
  ok("B5 회피 집행 면제 — 상주 칸은 hit 을 지우고(로그) 측정으로 간다 · 비상주 칸의 집행은 그대로") else ng("B5 회피 면제 배선", paste(i_ex, i_av))

## ── B6~B9 규칙 픽커 블록 추출 실행 — 상주 슬롯 보존 · 비상주 슬롯 수 · 제외 목록 ──────────────────────
i_p0 <- grep('^if \\(length\\(batch\\) && identical\\(first\\$block, "B5"\\) && is\\.null\\(\\.blk_design\\[\\["B5"\\]\\]\\)\\) \\{$', src)[1]
i_p1 <- .first_after(i_p0, "^\\}$")
R_P <- file.path(TMPD, "picker"); dir.create(file.path(R_P, "02_Infrastructure/ops"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(R_P, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
write(toJSON(list(schema = "reinforce_program_v1", blocks = list(), standing_cells = list(SC)), auto_unbox = TRUE, null = "null"),
      file.path(R_P, "06_Registry/reinforce_program.json"))
writeLines(c("rf_pick_overlay_arms <- function(n, exclude = character(0), root = NULL) {",
             "  .WPR_PICK <<- c(.WPR_PICK, list(list(n = n, exclude = exclude)))",
             "  list(cells = lapply(seq_len(n), function(i) list(code = 'grid', label = sprintf('pick%d', i),",
             "                      overlay = list(kind = sprintf('pk_%d', i), arm_id = sprintf('pick_%d', i)))),",
             "       picked_ids = sprintf('pick_%d', seq_len(n)))",
             "}"), file.path(R_P, "02_Infrastructure/ops/rf_overlay_arms.R"))
sp_done <- file.path(R_P, "spec_done.json")
write(toJSON(list(code = "B5_20", overlay = list(kind = "k_done", arm_id = "arm_done")), auto_unbox = TRUE, null = "null"), sp_done)
.WPR_PICK <- list()
run_picker <- function(batch) {
  env <- .mkenv(); env$batch <- batch; env$first <- batch[[1]]; env$.blk_design <- list(); env$ROOT <- R_P
  env$E <- list(attempts = list(list(n = 1L, cell_code = "B5_20", essence = list(cell_code = "B5_20", port_t = 1, spec = sp_done))),
                carry = list(overlay = list(kind = "k_carry", arm_id = "arm_carry")))
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_p0:i_p1], collapse = "\n")), envir = env))); NULL },
                       error = function(e) conditionMessage(e))
  env
}
if (is.na(i_p0) || is.na(i_p1)) ng("B6 픽커 블록 추출 실패", paste(i_p0, i_p1)) else {
  STD <- rf_standing_cell(SC, "pg2_risk_overlay", "b")
  g <- function(cd) list(code = cd, label = cd, block = "B5", axis = "risk_overlay")
  n0 <- length(.WPR_PICK)
  ep <- run_picker(list(STD, g("B5_16"), g("B5_17"), g("B5_18")))
  pk <- if (length(.WPR_PICK) > n0) .WPR_PICK[[length(.WPR_PICK)]] else NULL
  if (is.null(ep$.err) && !is.null(pk) && identical(as.integer(pk$n), 3L) && all(c("arm_done", "arm_carry", "pg2_risk_overlay_v1") %in% pk$exclude))
    ok("B6 추출 실행 — 픽커는 비상주 슬롯 3개만 요청 · 제외 = 측정한 arm ∪ carry arm ∪ 상주 arm") else
    ng("B6 픽커 호출", paste(ep$.err %||% "", pk$n %||% "NULL", paste(pk$exclude, collapse = ",")))
  cds <- vapply(ep$batch, function(c) as.character(c$code), character(1))
  if (identical(ep$batch[[1]], STD) && identical(cds, c("B5_31", "B5_16", "B5_17", "B5_18")) &&
      identical(vapply(ep$batch[2:4], function(c) c$overlay$arm_id, character(1)), c("pick_1", "pick_2", "pick_3")))
    ok("B7 상주 칸은 자리·모양 그대로 · 픽은 격자 코드를 유지한 채 비상주 슬롯에만 들어간다") else ng("B7 슬롯 채움", paste(cds, collapse = ","))
  lg <- .logs(ep, "overlay_arms_picked")
  if (length(lg) == 1L && identical(as.integer(lg[[1]]$standing_slots), 1L)) ok("B8 overlay_arms_picked 로그에 standing_slots=1") else ng("B8 픽 로그")
  n1 <- length(.WPR_PICK); ep2 <- run_picker(list(STD))
  if (is.null(ep2$.err) && length(.WPR_PICK) == n1 && identical(ep2$batch, list(STD))) ok("B9 배치가 상주 칸뿐이면 픽커를 부르지 않는다(자리 0)") else ng("B9 전부 상주", ep2$.err %||% as.character(length(.WPR_PICK) - n1))
}

## ── B10~B12 회피 집행 블록 추출 실행 — 상주 면제 · 비상주 집행 (양방향) ─────────────────────────────
i_a0 <- grep("^  if \\(!is\\.null\\(\\.avoid_hit\\) && isTRUE\\(CELL\\$standing\\)\\) \\{$", src)[1]
i_an <- .first_after(i_a0, "^    next$"); i_a1 <- if (is.na(i_an)) NA_integer_ else i_an + 1L
run_avoid <- function(cell, hit) {
  env <- .mkenv(); env$CELL0 <- cell; env$.avoid_hit <- hit; env$att <- list(n = 7L); env$BID <- "T_AVOID"; env$ROOT <- TMPD
  env$.REC <- list(); env$REACHED <- FALSE
  env$rf_record_result <- function(layer, base_id, n, ...) env$.REC[[length(env$.REC) + 1L]] <- c(list(n = n), list(...))
  txt <- paste(c("for (CELL in list(CELL0)) {", src[i_a0:i_a1], "  REACHED <- TRUE", "}"), collapse = "\n")
  env$.err <- tryCatch({ eval(parse(text = txt), envir = env); NULL }, error = function(e) conditionMessage(e))
  env
}
if (is.na(i_a0) || is.na(i_a1) || !grepl("^  \\}$", src[i_a1])) ng("B10 회피 블록 추출 실패", paste(i_a0, i_a1)) else {
  HIT <- "B5_31 은 측정 무효 사유(C6 생존편향)로 쓰지 말 것"
  e1 <- run_avoid(rf_standing_cell(SC, "pg2_risk_overlay"), HIT)
  if (is.null(e1$.err) && isTRUE(e1$REACHED) && !length(e1$.REC) && "avoid_exempt_standing" %in% .ev_of(e1) && !("avoid_enforced" %in% .ev_of(e1)))
    ok("B10 상주 칸 + 측정 무효 회피 → 면제 로그 · 원장 종결 0 · 측정 경로로 진행") else ng("B10 상주 면제", paste(e1$.err %||% "", e1$REACHED, length(e1$.REC)))
  e2 <- run_avoid(list(code = "B5_16", label = "x", block = "B5"), HIT)
  if (is.null(e2$.err) && !isTRUE(e2$REACHED) && length(e2$.REC) == 1L && isTRUE(e2$.REC[[1]]$terminal) && "avoid_enforced" %in% .ev_of(e2))
    ok("B11 대조 — 비상주 칸은 같은 회피로 terminal 종결 · 측정 안 함(next)") else ng("B11 비상주 집행", paste(e2$.err %||% "", e2$REACHED, length(e2$.REC)))
  e3 <- run_avoid(rf_standing_cell(SC, "pg2_risk_overlay"), NULL)
  if (is.null(e3$.err) && isTRUE(e3$REACHED) && !length(e3$.LOG) && !length(e3$.REC)) ok("B12 회피 없음 → 무로그 통과") else ng("B12 무회피")
}

cat("\n=== C. 예산 재도출 (rf_budget_auto / rf_budget_want / rf_b5_design_counts + 러너 블록 추출 실행) ===\n")
if (rf_budget_auto(25L, 8L, 5L, 0L, 0L) == 28L) ok("C1 B1 8칸 → 25+3 = 28 (구판 산식과 동일)") else ng("C1", as.character(rf_budget_auto(25L, 8L, 5L, 0L, 0L)))
a2 <- rf_budget_auto(25L, 8L, 7L, 1L, 0L)
if (a2 == 31L && a2 == 8L + 7L + 1L + 5L + 5L + 5L) ok("C2 B1 8 · B5 설계 7 · 상주 1 → 31 = 격자 전 칸(B4 5칸 미절단)") else ng("C2 B4 절단", as.character(a2))
if (rf_budget_auto(25L, 3L, 2L, 0L, 0L) == 25L) ok("C3 설계가 5칸보다 적어도 예산을 깎지 않는다") else ng("C3")
if (rf_budget_want(28L, 40L) == 40L && rf_budget_want(28L, 20L) == 28L && rf_budget_want(28L, NULL) == 28L)
  ok("C4 실제 상한 = max(자동, 수동) — 수동 상향 존중 · 수동이 낮으면 자동식 · 자동은 자동식 위로 못 올린다") else ng("C4 want")
if (rf_budget_auto(25L, 8L, 5L, 0L, 0L, slot_b1 = 8L) == 25L) ok("C5 슬롯 수는 인자(격자 blocks[].n)에서 온다 — 하드코딩 아님") else ng("C5 슬롯 인자")
c_open <- rf_b5_design_counts(8L, list(b5_redesign = list(active = TRUE, round = 2L, cells_added = 3L, base_design_cells = 5L)))
c_shut <- rf_b5_design_counts(8L, list(b5_redesign = list(active = FALSE, round = 2L, cells_added = 3L, base_design_cells = 5L)))
if (identical(c_open$n_base, 5L) && identical(c_open$n_redesign, 3L) && identical(c_shut$n_base, 8L) && identical(c_shut$n_redesign, 0L) &&
    rf_budget_auto(25L, 5L, c_open$n_base, 0L, c_open$n_redesign) == rf_budget_auto(25L, 5L, c_shut$n_base, 0L, c_shut$n_redesign))
  ok("C6 재설계 열림(base 5 + 추가 3) 과 닫힘(설계 8) 의 자동 예산이 같다 — 이중 계산·요동 없음") else ng("C6 재설계 계수", paste(c_open$n_base, c_open$n_redesign, c_shut$n_base, c_shut$n_redesign))
c_nb <- rf_b5_design_counts(8L, list(b5_redesign = list(active = TRUE, cells_added = 3L)))
if (identical(c_nb$n_base, 5L)) ok("C7 base_design_cells 부재 → n_design − cells_added") else ng("C7", as.character(c_nb$n_base))
if (.has("rf_budget_auto(led$max_attempts %||% 25L, .nB1d, .b5c$n_base, .n_standing_inserted, .b5c$n_redesign") &&
    .has("rf_budget_want(.auto, E$max_attempts)") && .has("if (.want != .cur)") && !.has("max(0L, length(.b1_design) - 5L)"))
  ok("C8 러너 — 매 tick 정본 산식으로 재도출 · 바뀔 때만 기록 · 구판 인라인 산식 제거") else ng("C8 러너 예산 배선")
i_bud <- .at("rf_budget_auto(led$max_attempts"); i_b1 <- .at("if (length(.b1_design)) {")
if (!is.na(i_bud) && !is.na(i_b1) && i_bud > i_b1 && !grepl("rf_budget_auto", paste(code[i_b1:(i_b1 + 5L)], collapse = "\n"), fixed = TRUE))
  ok("C9 예산 블록이 B1 설계 조건문 **밖**에 있다(설계 없는 entry 도 상주·B5 설계를 센다)") else ng("C9 예산 블록 위치")

## ── C10~C18 러너 블록 추출 실행 — 격자 조립 → 설계 적용 → 상주 삽입 → 예산 (원장 writer·로그는 스텁) ──────────
i_c0 <- grep("^cells <- do\\.call\\(c, lapply\\(PROG\\$blocks", src)[1]
i_c1 <- grep("^\\} else MAXA <- \\.cur$", src)[1]
mk_prog <- function(standing = TRUE) {
  blk <- function(id, axis, codes) list(id = id, axis = axis, n = length(codes), cells = lapply(codes, function(cd) list(code = cd, label = cd)))
  p <- list(schema = "reinforce_program_v1",
            blocks = list(blk("B1", "multifactor", sprintf("B1_%d", 1:5)), blk("B2", "weighting", sprintf("B2_%d", 6:10)),
                          blk("B3", "universe", sprintf("B3_%d", 11:15)), blk("B5", "risk_overlay", sprintf("B5_%d", 16:20)),
                          blk("B4", "combination", sprintf("B4_%d", 21:25))))
  if (standing) p$standing_cells <- list(SC)
  p
}
mk_root <- function(tag, bid, prog = mk_prog(), pg2_status = "active", b1_n = 0L, b5_n = 0L) {
  R0 <- file.path(TMPD, paste0("bud_", tag)); unlink(R0, recursive = TRUE, force = TRUE)
  for (dd in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", ".cache/rf_b1_design", ".cache/rf_block_design"))
    dir.create(file.path(R0, dd), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R"), file.path(R0, "02_Infrastructure/ops/"), overwrite = TRUE)
  for (f in c("rf_block_design.R", "rf_runner_gates.R", "rf_spec_sig.R"))
    file.copy(file.path(ROOT, "02_Infrastructure/reinforcement", f), file.path(R0, "02_Infrastructure/reinforcement/"), overwrite = TRUE)
  write(toJSON(prog, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(R0, "06_Registry/reinforce_program.json"))
  arms <- c(list(list(id = "pg2_risk_overlay_v1", kind = "pg2_risk_overlay", status = pg2_status, basis = "책 사양")),
            lapply(1:12, function(i) list(id = sprintf("arm_%d", i), kind = sprintf("k_%d", i), status = "active", basis = "b")))
  write(toJSON(list(arms = arms), auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(R0, "06_Registry/overlay_catalog.json"))
  if (b1_n > 0L) write(toJSON(list(cells = lapply(seq_len(b1_n), function(i) list(factors = list(sprintf("F%d", i)), label = sprintf("d%d", i)))),
                              auto_unbox = TRUE, null = "null"), file.path(R0, ".cache/rf_b1_design", sprintf("%s.json", substr(bid, 1, 60))))
  if (b5_n > 0L) write(toJSON(list(block = "B5", cells = lapply(seq_len(b5_n), function(i) list(pick = sprintf("arm_%d", i), label = sprintf("o%d", i), why = "w"))),
                              auto_unbox = TRUE, null = "null"), file.path(R0, ".cache/rf_block_design", sprintf("%s_B5.json", substr(bid, 1, 50))))
  R0
}
run_budget <- function(R0, E, prog = mk_prog(), led_max = 25L) {
  env <- .mkenv(); env$ROOT <- R0; env$BID <- E$base_id; env$E <- E; env$led <- list(max_attempts = led_max)
  env$PROG <- fromJSON(as.character(toJSON(prog, auto_unbox = TRUE, null = "null")), simplifyVector = FALSE)
  env$MAXA <- as.integer(E$max_attempts %||% led_max); env$.BUD <- list()
  env$rf_record_entry_budget <- function(layer, base_id, max_attempts, reason, root) {
    env$.BUD[[length(env$.BUD) + 1L]] <- list(max_attempts = as.integer(max_attempts), reason = reason, root = root); invisible(max_attempts) }
  ## rf_b1_design_lib.R 는 ROOT 를 QVEST_RF_ROOT 로 다시 풀고 setwd 한다 — 샌드박스로 돌리고 끝나면 되돌린다
  old_rr <- Sys.getenv("QVEST_RF_ROOT", unset = NA); owd <- getwd()
  Sys.setenv(QVEST_RF_ROOT = R0)
  on.exit({ setwd(owd); if (is.na(old_rr)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old_rr) }, add = TRUE)
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_c0:i_c1], collapse = "\n")), envir = env))); NULL },
                       error = function(e) conditionMessage(e))
  env
}
.codes <- function(env) vapply(env$cells, function(c) as.character(c$code), character(1))
.b5    <- function(env) { v <- .codes(env); v[startsWith(v, "B5_")] }
.skip_reason <- function(env) { z <- .logs(env, "standing_cell_skipped"); if (length(z)) as.character(z[[1]]$reason) else "" }
.ins_reason  <- function(env) { z <- .logs(env, "standing_cell_inserted"); if (length(z)) as.character(z[[1]]$reason) else "" }
if (is.na(i_c0) || is.na(i_c1) || i_c1 <= i_c0) ng("C10 예산 블록 추출 실패", paste(i_c0, i_c1)) else {
  BIDA <- "T_WPR_budget_first_gen"
  RA <- mk_root("a", BIDA, b1_n = 8L, b5_n = 7L)
  EA <- list(base_id = BIDA, status = "active", attempts = list())
  ea <- run_budget(RA, EA)
  if (is.null(ea$.err) && identical(.b5(ea)[1], "B5_31") && identical(.ins_reason(ea), "first_b5_round") && identical(ea$.n_standing_inserted, 1L) &&
      isTRUE(ea$cells[[which(.codes(ea) == "B5_31")]]$standing))
    ok("C10 첫 세대(B5 미측정) — B5_31 이 B5 **첫 칸**으로 들어간다(first_b5_round)") else ng("C10 상주 삽입", paste(ea$.err %||% "", paste(.b5(ea), collapse = ",")))
  if (is.null(ea$.err) && identical(as.integer(ea$.auto), 31L) && length(ea$.BUD) == 1L && identical(ea$.BUD[[1]]$max_attempts, 31L) &&
      identical(as.integer(ea$MAXA), 31L) && length(ea$cells) == 31L && all(sprintf("B4_%d", 21:25) %in% .codes(ea)) && length(ea$cells) <= ea$MAXA)
    ok("C11 예산 31 = 25 + B1 초과 3 + B5 설계 초과 2 + 상주 1 · 1회 기록 · 격자 31칸 전부(B4 5칸) 예산 안") else
    ng("C11 예산", paste(ea$.auto, length(ea$.BUD), ea$MAXA, length(ea$cells)))
  eb <- run_budget(RA, c(EA, list(max_attempts = 40L)))
  if (is.null(eb$.err) && !length(eb$.BUD) && identical(as.integer(eb$MAXA), 40L)) ok("C12 수동 상향(40) 존중 — 자동(31)으로 되돌려 쓰지 않는다 · 기록 0") else ng("C12 수동 상향", paste(length(eb$.BUD), eb$MAXA))
  ec <- run_budget(RA, c(EA, list(max_attempts = 20L)))
  if (is.null(ec$.err) && length(ec$.BUD) == 1L && identical(ec$.BUD[[1]]$max_attempts, 31L) && identical(as.integer(ec$MAXA), 31L))
    ok("C13 원장 값이 자동식보다 낮으면 자동식(31)까지만 올린다 — 그 위로는 안 올린다") else ng("C13 자동 상향 한도", paste(length(ec$.BUD), ec$MAXA))
  ed <- run_budget(RA, c(EA, list(max_attempts = 31L)))
  if (is.null(ed$.err) && !length(ed$.BUD) && identical(as.integer(ed$MAXA), 31L)) ok("C14 값이 같으면 쓰지 않는다(바뀔 때만 기록)") else ng("C14 무변경 기록", as.character(length(ed$.BUD)))
  ## B5 측정됨 ∧ 재설계 없음 — 운영 entry(combo_rulefast) 형태
  BIDM <- "T_WPR_budget_measured"; RM <- mk_root("m", BIDM, b1_n = 8L, b5_n = 5L)
  EM <- list(base_id = BIDM, status = "active", max_attempts = 28L,
             attempts = c(lapply(1:8, function(i) att(sprintf("B1_%d", i), i)), lapply(16:20, function(k) att(sprintf("B5_%d", k), k - 7L))))
  em <- run_budget(RM, EM)
  if (is.null(em$.err) && identical(.skip_reason(em), "b5_measured_no_redesign") && identical(em$.n_standing_inserted, 0L) &&
      !("B5_31" %in% .codes(em)) && identical(as.integer(em$.auto), 28L) && !length(em$.BUD) && identical(as.integer(em$MAXA), 28L))
    ok("C15 B5 측정됨 ∧ 재설계 없음 → B5_31 건너뜀(사유 로그) · 예산 28 그대로 · 기록 0") else
    ng("C15 측정 후 무재설계", paste(em$.err %||% "", .skip_reason(em), em$.auto, length(em$.BUD)))
  ## 재설계 라운드 — 레인이 설계 뒤에 3칸을 덧붙이고 b5_redesign(active) 을 연 상태
  RR <- mk_root("r", BIDM, b1_n = 8L, b5_n = 8L)
  ER <- c(EM, list(b5_redesign = list(active = TRUE, round = 2L, cells_added = 3L, base_design_cells = 5L)))
  er <- run_budget(RR, ER)
  if (is.null(er$.err) && identical(.ins_reason(er), "redesign_round") && identical(.b5(er)[1], "B5_31") &&
      identical(as.integer(er$.auto), 32L) && length(er$.BUD) == 1L && identical(er$.BUD[[1]]$max_attempts, 32L) && length(er$cells) <= er$MAXA)
    ok("C16 재설계 라운드 → B5_31 삽입(redesign_round) · 예산 32 = 25 + 3 + 0 + 상주 1 + 추가 3 · 격자 전 칸 예산 안") else
    ng("C16 재설계", paste(er$.err %||% "", .ins_reason(er), er$.auto, length(er$cells), er$MAXA))
  ## (a) 시도 존재 — arm 이 retired 여도 코드가 격자에 남아야 재개·승자 해석이 그 칸을 찾는다
  RT <- mk_root("t", BIDM, b1_n = 8L, b5_n = 5L, pg2_status = "retired")
  ET <- EM; ET$attempts <- c(EM$attempts, list(att("B5_31", 14L)))
  et <- run_budget(RT, ET)
  if (is.null(et$.err) && identical(.ins_reason(et), "attempt_exists") && "B5_31" %in% .codes(et) && identical(as.integer(et$.auto), 29L))
    ok("C17 (a) B5_31 시도가 있으면 retired 여도 격자에 남는다 · 예산에 상주 1 포함(29)") else ng("C17 시도 존재", paste(et$.err %||% "", .ins_reason(et), et$.auto))
  EC <- EA; EC$carry <- list(overlay = list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1"))
  ecy <- run_budget(RA, EC)
  if (is.null(ecy$.err) && identical(.skip_reason(ecy), "carry_has_arm") && !("B5_31" %in% .codes(ecy)) && identical(as.integer(ecy$.auto), 30L))
    ok("C18 carry 에 상주 arm → 건너뜀(carry_has_arm) · 예산에서도 빠진다(30)") else ng("C18 carry 상주", paste(ecy$.err %||% "", .skip_reason(ecy), ecy$.auto))
  BIDZ <- "T_WPR_budget_plain"; RZ <- mk_root("z", BIDZ)
  ez <- run_budget(RZ, list(base_id = BIDZ, status = "active", attempts = list()))
  if (is.null(ez$.err) && identical(as.integer(ez$.auto), 26L) && length(ez$.BUD) == 1L && identical(ez$.BUD[[1]]$max_attempts, 26L) && length(ez$cells) == 26L)
    ok("C19 설계 없는 첫 entry — 상주 1칸만큼 26 으로 올린다(구판은 B1 설계가 없으면 예산을 안 봤다)") else ng("C19 설계 없음", paste(ez$.err %||% "", ez$.auto, length(ez$.BUD)))
  RN <- mk_root("n", BIDZ, prog = mk_prog(standing = FALSE))
  en <- run_budget(RN, list(base_id = BIDZ, status = "active", attempts = list()), prog = mk_prog(standing = FALSE))
  if (is.null(en$.err) && identical(as.integer(en$.auto), 25L) && !length(en$.BUD) && !any(c("standing_cell_inserted", "standing_cell_skipped") %in% .ev_of(en)))
    ok("C20 격자에 standing_cells 가 없으면 삽입·건너뜀 로그 0 · 예산 25 불변(돌연변이 통제)") else ng("C20 상주 없음", paste(en$.err %||% "", en$.auto))
}

cat("\n=== D. 승자 게이트 — 러너 .winner_of 추출 실행 ===\n")
if (rf_adversary_ok(list(n = 1L)) && rf_adversary_ok(list(adversary = list(verdict = "pass"))) &&
    !rf_adversary_ok(list(adversary = list(verdict = "fail"))) && !rf_adversary_ok(list(adversary = list(verdict = "not_candidate"))) &&
    !rf_adversary_ok(list(adversary = list(verdict = "error"))))
  ok("D1 rf_adversary_ok — 부재/pass 만 TRUE · fail/error/not_candidate FALSE") else ng("D1 술어")
mkspec <- function(cd, arm) { p <- file.path(TMPD, sprintf("spec_%s.json", cd))
  write(toJSON(list(code = cd, factors = list(), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"),
                    overlay = list(kind = "k", arm_id = arm)), auto_unbox = TRUE, null = "null"), p); p }
# ★2026-09-24(P0-12 규약 혼합 가드): 블록 승자 후보는 현행 규약 칸만(rf_candidates_keep) — 픽스처는 원장 rebase 표식 모양의
#   measurement_regime 으로 검사 규약을 명시하고, 러너 문맥 .RCTX 를 같은 규약으로 주입한다(적대검증 필터만 재는 절).
FIX_REGIME <- "fixture_regime"
matt <- function(n, cd, cal, verdict = NULL, own = TRUE) { a <- list(n = n, cell_code = cd, grade = "B",
  measurement_regime = list(regime = FIX_REGIME, basis = "fixture"),
  essence = list(cell_code = cd, port_t = 2, calmar = cal, spec = mkspec(cd, paste0("arm_", cd), own = own)))
  if (!is.null(verdict)) a$adversary <- list(verdict = verdict); a }
mkspec0 <- mkspec
mkspec <- function(cd, arm, own = TRUE) { p <- mkspec0(cd, arm)
  if (!isTRUE(own)) { s <- fromJSON(p, simplifyVector = FALSE); s$overlay_cell <- list()   # 자기 층 없음(승계분만) 표식
    write(toJSON(s, auto_unbox = TRUE, null = "null"), p) }
  p }
ATT <- list(matt(1L, "B5_16", 0.50), matt(2L, "B5_17", 0.90, "fail"), matt(3L, "B5_18", 0.70, "pass"), matt(4L, "B5_19", 0.95, "not_candidate"))
i0 <- grep("^\\.winner_of <- function\\(bid", src); i1 <- if (length(i0)) i0 + which(grepl("^}", src[(i0 + 1L):length(src)]))[1] else NA
if (!length(i0) || is.na(i1)) ng("D2 .winner_of 추출 실패") else {
  env <- .mkenv(); env$cells <- list(); env$E <- list(attempts = ATT); env$BID <- "T_WPR_winner"
  env$.RCTX <- rf_runner_ctx(ROOT, regime = FIX_REGIME)
  env$.metric <- function(a, key) { es <- a$essence; if (is.list(es) && !is.null(es[[key]])) as.numeric(es[[key]]) else NA_real_ }
  env$.cell_by_code <- function(cd) NULL
  eval(parse(text = src[i0:i1]), envir = env)
  w <- env$.winner_of("B5", "calmar", gate = rf_adversary_ok)
  if (!is.null(w) && identical(w$overlay$arm_id, "arm_B5_18")) ok("D2 게이트 — calmar 최고 B5_19(not_candidate)·B5_17(fail) 제외, pass 인 B5_18 승자") else ng("D2 게이트 승자", w$overlay$arm_id %||% "NULL")
  ex <- .logs(env, "winner_excluded_adversary")
  if (length(ex) == 3L && setequal(vapply(ex, function(z) z$code, character(1)), c("B5_16", "B5_17", "B5_19")) &&
      identical(vapply(ex, function(z) z$verdict, character(1))[vapply(ex, function(z) z$code, character(1)) == "B5_16"], "unverified"))
    ok("D3 제외 3건(★P0-11: verdict 없는 자기 층 B5_16 = unverified 포함)이 코드·verdict 와 함께 로그로 남는다") else ng("D3 제외 로그", as.character(length(ex)))
  w0 <- env$.winner_of("B5", "calmar")
  if (!is.null(w0) && identical(w0$overlay$arm_id, "arm_B5_19")) ok("D4 게이트 없는 호출(구판)은 not_candidate 도 승자 — 돌연변이 통제: 게이트가 결과를 가른다") else ng("D4 무게이트 대조")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5, "fail"), matt(2L, "B5_17", 0.9, "not_candidate")))
  if (is.null(env$.winner_of("B5", "calmar", gate = rf_adversary_ok))) ok("D5 전부 탈락 → NULL(B4 는 carry 오버레이만 깐다)") else ng("D5 전멸 시 NULL")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5), matt(2L, "B5_17", 0.9)))
  if (is.null(env$.winner_of("B5", "calmar", gate = rf_adversary_ok)))
    ok("D6 ★P0-11: verdict 없는 자기 층 B5 는 unverified → 승자 없음(구판은 부재 = 통과로 승자였다)") else ng("D6 미검증 B5 가 승자")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5, own = FALSE), matt(2L, "B5_17", 0.9, "fail")))
  w2 <- env$.winner_of("B5", "calmar", gate = rf_adversary_ok)
  if (!is.null(w2) && identical(w2$overlay$arm_id, "arm_B5_16")) ok("D6b verdict 없어도 자기 층이 없는 B5(overlay_cell=[])는 그대로 후보(검증할 처치가 없다)") else ng("D6b 자기 층 없는 B5")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5, "pass"), modifyList(matt(2L, "B5_18", 0.9, "pass"), list(measurement_regime = list(regime = "other_regime")))))
  w3 <- env$.winner_of("B5", "calmar", gate = rf_adversary_ok)
  if (!is.null(w3) && identical(w3$overlay$arm_id, "arm_B5_16") && length(.logs(env, "candidates_excluded")))
    ok("D6c 규약 혼합 가드 — 규약이 다른 칸(Calmar 0.9 pass)은 승자 후보에서 빠진다(candidates_excluded)") else ng("D6c 규약 가드", w3$overlay$arm_id %||% "NULL")
}
## ★B4-SIX(2026-09-26): 승자 = 등록부 소유 블록마다(.winner_of(b, by, gate = rf_adversary_ok) · by = 격자 select_winner_by — B5 = calmar) ·
##   B4 오버레이 base = carry(rf_axes_b4_assemble · 등록부 b4_base) — 줄 대신 정의·행동으로 잰다.
.ovA <- list(kind = "c", arm_id = "carry1")
.d7 <- rf_axes_b4_assemble(list(), c("B1", "B5"), list(), list(overlay = .ovA))$spec[["overlay"]]
.pg <- jsonlite::fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
if (.has(".winner_of(b, by, gate = rf_adversary_ok)") && .has("rf_axes_block_winners(PROG,") && identical(rf_grid_select_by(.pg, "B5"), "calmar") &&
    identical(.d7, .ovA) && .has("rf_axes_b4_assemble(SPEC, use, .b4_win, E$carry)"))
  ok("D7 러너 — B5 승자 게이트(전 블록 공통 · verdict 는 B5 에만) · 승자 없으면 carry 오버레이(부모 위험통제 보존) · B4 조립 = 등록부") else ng("D7 러너 승자 배선")

cat("\n=== E. Grade A 보류·해제 ===\n")
OWN <- list(kind = "x", arm_id = "a"); CAR <- list(kind = "c", arm_id = "carry1")
sp_b5 <- list(code = "B5_17", overlay = list(CAR, OWN), overlay_cell = OWN)
if (rf_grade_a_hold("B5_17", sp_b5, CAR, NULL) && rf_grade_a_hold("B5_17", sp_b5, CAR, list(adversary = list(verdict = "fail"))))
  ok("E1 B5 자기 층 ∧ verdict 없음/fail → 보류") else ng("E1 보류")
if (!rf_grade_a_hold("B5_17", sp_b5, CAR, list(adversary = list(verdict = "pass")))) ok("E2 pass → 발행") else ng("E2 pass")
if (!rf_grade_a_hold("B1_1", list(overlay = OWN, overlay_cell = list()), NULL, NULL)) ok("E3 B1 은 보류 대상 아님") else ng("E3 B1")
if (!rf_grade_a_hold("B5_18", list(overlay = CAR, overlay_cell = list()), CAR, NULL)) ok("E4 B5 인데 승계 층뿐(자기 층 0) → 발행") else ng("E4 승계만")
if (rf_grade_a_hold("B5_18", list(overlay = list(CAR, OWN)), CAR, NULL)) ok("E5 overlay_cell 없는 구 스펙 → overlay − carry 폴백으로 자기 층 판별(보류)") else ng("E5 폴백")
if (rf_grade_a_hold("B5_19", NULL, NULL, NULL)) ok("E6 스펙을 못 읽는 B5 칸은 보수적으로 보류(정직 결측)") else ng("E6 NULL 스펙")
## ★정의 줄은 `.grade_a_enqueue <- function(` 이라 `.grade_a_enqueue(` 에 안 걸린다 — 호출 줄만 센다(구판은 정의 수를 또 빼 1로 오판)
n_def <- sum(grepl("^\\.grade_a_enqueue <- function", code)); n_call <- sum(grepl(".grade_a_enqueue(", code, fixed = TRUE))
if (n_def == 1L && n_call >= 2L) ok(sprintf("E7 발행 1함수(정의 1 · 호출 %d — 즉시 경로 + 경계 해제 경로)", n_call)) else ng("E7 발행 함수", paste(n_def, n_call))
## ★2026-09-24(P0-12): 적대검증 보류(rf_grade_a_hold)는 A 자격 관문 rf_a_eligibility 의 adversary_unverified(자기 층) 성분으로
##   흡수됐다 — 러너는 관문 결과(.elA)로 기록(graduate)과 발행(.a_route)을 가른다. 네 사건 로그는 그대로 남는다.
if (.has('jlog("grade_a_hold_adversary"') && .has('jlog("grade_a_released"') && .has('jlog("grade_a_adversary_blocked"') && .has('jlog("grade_a_hold_unresolved"') &&
    .has('.routed <- .a_route(j$n, j$code, R$artifacts, es, .elA, "collect")') &&
    .has("graduate = is.null(.elA) || isTRUE(.elA$eligible)") && .has("rf_a_eligibility(entry, att, spec, rf_a_ctx(.RCTX, entries, BID, axes = axes))"))
  ok("E8 러너 — 보류·해제·차단·미결 네 사건 전부 로그 · 판정은 정본 함수(rf_a_eligibility) · 기록 graduate 와 발행이 같은 판정") else ng("E8 러너 보류 배선")
i_adv <- .at('rf_overlay_adversary_run(BID, "B5", 1L, root = ROOT)'); i_lc <- .at("rf_emit_block_lcode(BID, u2")
if (!is.na(i_adv) && !is.na(i_lc) && i_adv < i_lc && grepl("tryCatch", code[i_adv - 2L], fixed = TRUE) &&
    .has('jlog("adversary_done"') && .has('jlog("adversary_failed"') && .has("identical(.blk_now, \"B5\") && .blk_left == 0L) || length(.held_a)"))
  ok("E9 적대검증 — B5 경계(또는 보류 A)에서 tryCatch 안 · L-code 발행 **앞** · 성공/실패 둘 다 로그") else ng("E9 적대검증 배선", paste(i_adv, i_lc))
if (.has("rf_record_b5_redesign(1L, BID, list(active = FALSE") && .has('jlog("b5_redesign_closed"')) ok("E10 재설계 라운드는 B5 경계에서 러너가 닫는다(레인 계약)") else ng("E10 재설계 종료")

## ── E11~E17 B5 경계 블록 추출 실행 — 적대검증 호출 · 보류 A 해제/차단/미결 · 재설계 종료 · 실패해도 러너 무정지 ──────
i_v0 <- grep("^\\.adv_ran <- FALSE$", src)[1]
i_v1 <- grep("^if \\(nb > 0L && \\(\\.blk_left == 0L \\|\\| u2 >= MAXA\\)\\) \\{$", src)[1] - 1L
R_A <- file.path(TMPD, "adv"); dir.create(file.path(R_A, "02_Infrastructure/reinforcement"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("rf_overlay_adversary_run <- function(base_id, block = 'B5', layer = 1L, root = NULL, ...) {",
             "  .ADV_CALLS[[length(.ADV_CALLS) + 1L]] <<- list(base_id = base_id, block = block, layer = layer, root = root)",
             "  if (identical(ADV_MODE, 'throw')) stop('stub adversary failure')",
             "  data.frame(code = c('B5_31', 'B5_16', 'B5_17'), verdict = c('pass', 'fail', 'not_candidate'), stringsAsFactors = FALSE)",
             "}"), file.path(R_A, "02_Infrastructure/reinforcement/rf_overlay_adversary.R"))
held <- function(n, cd) list(n = n, code = cd, artifacts = paste0("art_", cd), essence = list(port_t = 3))
run_bound <- function(nb, blk_now, blk_left, held_a = list(), verdicts = list(), mode = "ok", redesign = TRUE) {
  env <- .mkenv(); env$nb <- nb; env$.blk_now <- blk_now; env$.blk_left <- blk_left; env$.held_a <- held_a
  env$BID <- "T_WPR_ADV"; env$ROOT <- R_A; env$.redesign_on <- redesign; env$ADV_MODE <- mode
  env$.ADV_CALLS <- list(); env$.ENQ <- list(); env$.RD <- list()
  env$rf_load <- function(layer, root) list(entries = list(list(base_id = "T_WPR_ADV", attempts = lapply(names(verdicts), function(k) {
    a <- list(n = as.integer(k)); if (nzchar(verdicts[[k]])) a$adversary <- list(verdict = verdicts[[k]]); a }))))
  env$.rf_find <- function(obj, base_id) 1L
  env$.grade_a_enqueue <- function(n, code, artifacts, essence, elig = NULL) env$.ENQ[[length(env$.ENQ) + 1L]] <- list(n = n, code = code)
  # ★2026-09-24(P0-12): 경계는 관문 **전체**를 다시 판정한다(.a_recheck) — 이 절은 경계 배선(호출·해제·차단·미결 분기)을 재므로
  #   관문을 verdict 로만 가르는 스텁을 꽂는다(관문 자체는 test_rf_a_eligibility.R · 실물 경로는 test_rf_runner_a_gate_e2e.R 이 잰다).
  env$.a_recheck <- function(h, aL, L) { v <- if (length(aL)) as.character((aL[[1]]$adversary %||% list())$verdict %||% "") else ""
    list(eligible = identical(v, "pass"), codes = if (identical(v, "pass")) character(0) else "adversary_unverified") }
  env$.a_decision <- function(...) invisible(TRUE); env$.a_hold_record <- function(...) invisible(TRUE)
  env$.GRAD <- list(); env$.a_graduate <- function(n, why) { env$.GRAD[[length(env$.GRAD) + 1L]] <- n; TRUE }
  env$rf_record_b5_redesign <- function(layer, base_id, fields, root) env$.RD[[length(env$.RD) + 1L]] <- list(base_id = base_id, fields = fields)
  env$.err <- tryCatch({ invisible(capture.output(eval(parse(text = paste(src[i_v0:i_v1], collapse = "\n")), envir = env))); NULL },
                       error = function(e) conditionMessage(e))
  env
}
if (is.na(i_v0) || is.na(i_v1) || i_v1 <= i_v0) ng("E11 경계 블록 추출 실패", paste(i_v0, i_v1)) else {
  b1 <- run_bound(3L, "B5", 0L, held_a = list(held(10L, "B5_31"), held(11L, "B5_16"), held(12L, "B5_20")),
                  verdicts = list("10" = "pass", "11" = "fail", "12" = ""))
  dn <- .logs(b1, "adversary_done")
  if (is.null(b1$.err) && length(b1$.ADV_CALLS) == 1L && identical(b1$.ADV_CALLS[[1]]$block, "B5") && identical(as.integer(b1$.ADV_CALLS[[1]]$layer), 1L) &&
      identical(b1$.ADV_CALLS[[1]]$root, R_A) && length(dn) == 1L && identical(dn[[1]]$verdicts, "B5_31=pass,B5_16=fail,B5_17=not_candidate") && isTRUE(b1$.adv_ran))
    ok("E11 B5 경계 — rf_overlay_adversary_run(BID,'B5',1L,root) 1회 · adversary_done 에 칸별 verdict") else ng("E11 적대검증 호출", paste(b1$.err %||% "", length(b1$.ADV_CALLS)))
  if (length(b1$.ENQ) == 1L && identical(as.integer(b1$.ENQ[[1]]$n), 10L) &&
      identical(as.integer(.logs(b1, "grade_a_released")[[1]]$n %||% NA), 10L) &&
      identical(as.integer(.logs(b1, "grade_a_adversary_blocked")[[1]]$n %||% NA), 11L) &&
      identical(as.integer(.logs(b1, "grade_a_hold_unresolved")[[1]]$n %||% NA), 12L) &&
      identical(as.integer(unlist(b1$.GRAD)), 10L))
    ok("E12 보류 A — pass(n10) 만 발행 1회 + 졸업 · fail(n11) 차단 · verdict 없음(n12) 미결 유지 (verdict 는 원장에서 재독)") else
    ng("E12 해제/차단", paste(length(b1$.ENQ), paste(.ev_of(b1), collapse = ",")))
  if (length(b1$.RD) == 1L && isFALSE(b1$.RD[[1]]$fields$active) && isTRUE(b1$.RD[[1]]$fields$adversary_ran) && "b5_redesign_closed" %in% .ev_of(b1))
    ok("E13 재설계 라운드 종료 — B5 경계에서 rf_record_b5_redesign(active=FALSE · adversary_ran=TRUE)") else ng("E13 재설계 종료", as.character(length(b1$.RD)))
  b2 <- run_bound(2L, "B5", 0L, held_a = list(held(12L, "B5_20")), verdicts = list("12" = ""), mode = "throw")
  fl <- .logs(b2, "adversary_failed")
  if (is.null(b2$.err) && length(fl) == 1L && grepl("stub adversary failure", fl[[1]]$err) && !isTRUE(b2$.adv_ran) && !length(b2$.ENQ) &&
      "grade_a_hold_unresolved" %in% .ev_of(b2) && length(b2$.RD) == 1L && isFALSE(b2$.RD[[1]]$fields$adversary_ran))
    ok("E14 적대검증 예외 → adversary_failed 로그 · 러너 무정지(블록 완주) · 보류 A 미발행 · 재설계는 adversary_ran=FALSE 로 닫힘") else
    ng("E14 실패 격리", paste(b2$.err %||% "", paste(.ev_of(b2), collapse = ",")))
  b3 <- run_bound(2L, "B5", 2L)
  b4 <- run_bound(5L, "B2", 0L)
  b5 <- run_bound(0L, "B5", 0L)
  b6 <- run_bound(3L, "B5", 0L, redesign = FALSE)
  if (!length(b3$.ADV_CALLS) && !length(b3$.RD) && !length(b4$.ADV_CALLS) && !length(b5$.ADV_CALLS) && !length(b5$.RD) &&
      length(b6$.ADV_CALLS) == 1L && !length(b6$.RD))
    ok("E15 대조 — B5 미완·보류 없음 / B2 경계 / 기록 0 → 호출 0 · 재설계 플래그가 없으면 닫지 않는다") else
    ng("E15 발화 조건", paste(length(b3$.ADV_CALLS), length(b4$.ADV_CALLS), length(b5$.ADV_CALLS), length(b6$.RD)))
  b7 <- run_bound(1L, "B5", 3L, held_a = list(held(10L, "B5_31")), verdicts = list("10" = "pass"))
  if (is.null(b7$.err) && length(b7$.ADV_CALLS) == 1L && length(b7$.ENQ) == 1L && !length(b7$.RD))
    ok("E16 B5 미완이어도 보류 A 가 있으면 같은 tick 에 적대검증(verdict 를 이 tick 에 받아 재평가 — P0-12 이후 보류 A 의 entry 는 active 유지) · 블록 미완이라 재설계는 안 닫는다") else
    ng("E16 보류 A 즉시 경로", paste(length(b7$.ADV_CALLS), length(b7$.ENQ), length(b7$.RD)))
}
## ── E17 수집 루프의 Grade A 분기 추출 실행 — 보류(자기 층 B5) vs 즉시 발행(B1) ─────────────────────────────
## ★2026-09-24(P0-12): 수집 분기는 관문 결과 .elA 를 받아 .a_route(발행/보류)로 간다. 관문 판정 자체는 test_rf_a_eligibility.R 가,
##   실물 배선 전체는 test_rf_runner_a_gate_e2e.R 가 잰다 — 여기서는 **자기 층 B5 보류 → 이 tick 경계 적대검증 대상(.held_a)** 배선과
##   발행/보류 분기를 설치본 .a_route(소스 추출)로 잰다. .elA 는 그 판정의 모양(rf_a_eligibility 반환)으로 준다.
i_g0 <- grep('^  if \\(identical\\(R\\$grade, "A"\\)\\) \\{$', src)[1]; i_g1 <- .first_after(i_g0, "^  \\}$")
i_r0 <- grep("^\\.a_route <- function\\(n, code, artifacts, essence, elig, phase\\)", src)[1]; i_r1 <- .first_after(i_r0, "^\\}$")
run_gradeA <- function(cd, spec, elA) {
  sp <- file.path(TMPD, sprintf("specA_%s.json", cd)); write(toJSON(spec, auto_unbox = TRUE, null = "null"), sp)
  env <- .mkenv(); env$R <- list(grade = "A", artifacts = "art"); env$j <- list(n = 5L, code = cd, spec = sp); env$es <- list(port_t = 3)
  env$E <- list(carry = list(overlay = CAR)); env$.held_a <- list(); env$.ENQ <- list(); env$.HOLD <- list(); env$.elA <- elA
  env$.grade_a_enqueue <- function(n, code, artifacts, essence, elig = NULL) env$.ENQ[[length(env$.ENQ) + 1L]] <- list(n = n, code = code)
  env$.a_hold_record <- function(n, code, artifacts, elig, phase) env$.HOLD[[length(env$.HOLD) + 1L]] <- list(n = n, codes = elig$codes)
  env$.a_decision <- function(...) invisible(TRUE)
  env$.err <- tryCatch({ eval(parse(text = paste(c(src[i_r0:i_r1], src[i_g0:i_g1]), collapse = "\n")), envir = env); NULL },
                       error = function(e) conditionMessage(e))
  env
}
if (is.na(i_g0) || is.na(i_g1) || is.na(i_r0) || is.na(i_r1)) ng("E17 Grade A 분기 추출 실패") else {
  ga <- run_gradeA("B5_17", sp_b5, list(eligible = FALSE, codes = "adversary_unverified", self_unverified = TRUE))
  gb <- run_gradeA("B1_1", list(code = "B1_1", overlay = CAR, overlay_cell = list()), list(eligible = TRUE, codes = character(0), self_unverified = FALSE))
  gc <- run_gradeA("B2_7", list(code = "B2_7", overlay_cell = list()), list(eligible = FALSE, codes = "legacy_regime", self_unverified = FALSE))
  if (is.null(ga$.err) && length(ga$.held_a) == 1L && !length(ga$.ENQ) && length(ga$.HOLD) == 1L && "grade_a_hold_adversary" %in% .ev_of(ga) &&
      is.null(gb$.err) && !length(gb$.held_a) && length(gb$.ENQ) == 1L && !length(gb$.HOLD) &&
      is.null(gc$.err) && !length(gc$.held_a) && !length(gc$.ENQ) && length(gc$.HOLD) == 1L)
    ok("E17 수집 시점 — B5 자기 층 A 는 보류 + 이 tick 적대검증 대상 · 발행 가능 A 는 즉시 발행 · 다른 사유 보류(legacy)는 경계 대상 아님") else
    ng("E17 수집 분기", paste(ga$.err %||% "", length(ga$.held_a), length(ga$.ENQ), gb$.err %||% "", length(gb$.ENQ), gc$.err %||% "", length(gc$.HOLD)))
}

cat("\n=== F. lcm_merge — B5 사후 설계 거부 (격리 root · 실제 실행) ===\n")
LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
SBX <- file.path(tempdir(), sprintf("rf_lcm_%d", Sys.getpid()))
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", "stage_artifacts/l_code/reinforcement", ".cache"))
  dir.create(file.path(SBX, d), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), file.path(SBX, "02_Infrastructure/reinforcement/"), overwrite = TRUE)
file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), file.path(SBX, "02_Infrastructure/ops/"), overwrite = TRUE)
file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(SBX, "06_Registry/"), overwrite = TRUE)
file.copy(file.path(ROOT, "06_Registry/overlay_catalog.json"), file.path(SBX, "06_Registry/"), overwrite = TRUE)
EMPTY_RENV <- file.path(SBX, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)
REAL_LOG <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl"); real_sz0 <- if (file.exists(REAL_LOG)) file.size(REAL_LOG) else 0
std <- rfbd_standing_picks(SBX)
pick <- { v <- vapply(rfbd_catalog("B5", SBX), function(x) x$id, character(1)); v <- v[!(v %in% std)]; if (length(v)) v[1] else "" }
led <- list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(
  list(base_id = "T_B5DONE", status = "active", base_grade = "C", attempts_used = 2L,
       attempts = list(att("B1_1", 1L), att("B5_16", 2L))),
  list(base_id = "T_B5NONE", status = "active", base_grade = "C", attempts_used = 1L, attempts = list(att("B1_1", 1L)))), last_updated = "")
write(toJSON(led, auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(SBX, "06_Registry/reinforce_ledger_l1.json"))
for (b in c("T_B5DONE", "T_B5NONE"))
  write(toJSON(list(l_code = paste0("RF-", b), lesson_text = "B1_1 t 1.0", next_probes = list("x")), auto_unbox = TRUE, null = "null"),
        file.path(SBX, "stage_artifacts/l_code/reinforcement", sprintf("l_code_%s_B1.json", b)))
mech <- function(b) { p <- file.path(SBX, sprintf("%s.mech.json", b))
  write(toJSON(list(mechanism = "B1_1 이 기저와 같은 낙폭을 냈다 — 손실은 시장 적재에서 온다.",
                    next_block_actions = list(list(action = "총노출 축에서 검정", why = "B1_1", expect = "MDD 감소")),
                    next_block_design = list(block = "B5", cells = list(list(pick = pick, label = "a", why = "w")))),
               auto_unbox = TRUE, null = "null"), p); p }
## ★자식 격리: ~/.Renviron 이 QM_ROOT 를 운영 경로로 되돌리지 못하게 R_ENVIRON_USER=빈 파일 · 루트 변수 셋 전부 샌드박스
run_merge <- function(b) {
  keys <- c("QVEST_RF_ROOT", "R_ENVIRON_USER", "QM_ROOT", "CLAUDE_PROJECT_DIR")
  old <- Sys.getenv(keys, unset = NA)
  Sys.setenv(QVEST_RF_ROOT = SBX, R_ENVIRON_USER = EMPTY_RENV, QM_ROOT = SBX, CLAUDE_PROJECT_DIR = SBX)
  on.exit(for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(old[[k]]), k)), add = TRUE)
  suppressWarnings(system2("Rscript", c(shQuote(LIB), "merge", b, "B1", shQuote(mech(b))), stdout = TRUE, stderr = TRUE)) }
logp <- file.path(SBX, ".cache/reinforce_auto_log.jsonl")
has_evt <- function(ev, b) file.exists(logp) && any(grepl(sprintf('"event":"%s".*"base_id":"%s"', ev, b), readLines(logp, warn = FALSE, encoding = "UTF-8")))
if (!nzchar(pick)) ng("F0 카탈로그에 비상주 active arm 이 없다 — 픽스처 불성립") else {
  o1 <- run_merge("T_B5DONE")
  lc1 <- tryCatch(fromJSON(file.path(SBX, "stage_artifacts/l_code/reinforcement/l_code_T_B5DONE_B1.json"), simplifyVector = FALSE), error = function(e) NULL)
  if (has_evt("b5_design_refused_post_measure", "T_B5DONE") && !file.exists(rfbd_path(SBX, "T_B5DONE", "B5")))
    ok("F1 B5 시도가 있는 entry — B5 설계 거부 · 설계 파일 미작성 (H6 재개 방지)") else ng("F1 거부 미발화", paste(utils::tail(o1, 2), collapse = " | "))
  if (!is.null(lc1) && nzchar(as.character(lc1$mechanism %||% "")) && has_evt("mechanism_merged", "T_B5DONE"))
    ok("F2 거부해도 기전·처방은 병합된다(레인을 막지 않는다 · 설계만 뺀다)") else ng("F2 기전 병합", paste(utils::tail(o1, 2), collapse = " | "))
  o2 <- run_merge("T_B5NONE")
  if (has_evt("block_design_saved", "T_B5NONE") && file.exists(rfbd_path(SBX, "T_B5NONE", "B5")))
    ok("F3 양성 대조 — B5 시도가 없는 entry 는 같은 설계가 저장된다") else ng("F3 양성 대조", paste(utils::tail(o2, 3), collapse = " | "))
  .tail_since <- function(p, off) {
    if (!file.exists(p) || file.size(p) <= off) return("")
    con <- file(p, "rb"); on.exit(close(con), add = TRUE); seek(con, off)
    rawToChar(readBin(con, "raw", file.size(p) - off))
  }
  real_new <- .tail_since(REAL_LOG, real_sz0)
  if (has_evt("mechanism_merged", "T_B5NONE") && !grepl("T_B5DONE|T_B5NONE", real_new, useBytes = TRUE))
    ok("F5 자식 R 은 샌드박스를 가리켰다 — 사건은 샌드박스 로그에만 · 운영 로그에 픽스처 base_id 0줄") else ng("F5 자식 격리", substr(real_new, 1, 120))
}
lib_src <- paste(sub("#.*$", "", readLines(LIB, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
if (grepl("rfbd_standing_picks(ROOT)", lib_src, fixed = TRUE) && grepl('identical(.nxt, "B5")', lib_src, fixed = TRUE))
  ok("F4 materials — B5 카탈로그 목록에서 상주 arm 을 뺀다") else ng("F4 materials 상주 제외")
unlink(SBX, recursive = TRUE, force = TRUE)

cat("\n=== G. 서명 불변 — 부기 필드는 .spec_sig 에 안 들어간다 (실제 스펙 · 필드 하나씩) ===\n")
## ★2026-09-17 수리: 구판 G1 은 부기 필드 넷을 **한꺼번에** 얹었다 — 그러면 `$overlay` 부분 일치가 이름 모호로 NULL 이 되어
##   우연히 같은 서명이 나왔다. 필드 하나씩 얹자 overlay 키 없는 스펙 497/801 에서 overlay_shift=0 / overlay_strict=FALSE 가
##   서명을 바꿨다(.spec_sig 가 [[ ]] 로 수리됨). 그래서 변형마다 따로 센다.
VAR <- list(
  overlay_cell_eq  = function(s) { s$overlay_cell <- s[["overlay"]] %||% list(); s },
  overlay_cell_nil = function(s) { s$overlay_cell <- list(); s },
  floor_code       = function(s) { s$floor_code <- "B1_1"; s },
  overlay_shift_0  = function(s) { s$overlay_shift <- 0L; s },
  overlay_strict_F = function(s) { s$overlay_strict <- FALSE; s },
  all_four         = function(s) { s$overlay_cell <- s[["overlay"]] %||% list(); s$floor_code <- "B1_1"; s$overlay_shift <- 0L; s$overlay_strict <- FALSE; s },
  all_four_json    = function(s) { s$overlay_cell <- s[["overlay"]] %||% list(); s$floor_code <- "B1_1"; s$overlay_shift <- 0L; s$overlay_strict <- FALSE
                                   fromJSON(as.character(toJSON(s, auto_unbox = TRUE, pretty = TRUE, null = "null")), simplifyVector = FALSE) })
.spd <- file.path(ROOT, ".cache/rf_parallel")
.fs <- if (dir.exists(.spd)) list.files(.spd, pattern = "^spec_.*\\.json$", full.names = TRUE) else character(0)
okn <- setNames(integer(length(VAR)), names(VAR)); bad <- setNames(vector("list", length(VAR)), names(VAR)); n_read <- 0L; n_mut <- 0L; n_noov <- 0L
for (f in .fs) {
  s0 <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(s0)) next
  n_read <- n_read + 1L; g0 <- .spec_sig(s0); if (!("overlay" %in% names(s0))) n_noov <- n_noov + 1L
  for (k in names(VAR)) if (identical(g0, .spec_sig(VAR[[k]](s0)))) okn[[k]] <- okn[[k]] + 1L else bad[[k]] <- c(bad[[k]], basename(f))
  s2 <- s0; s2$overlay <- .ov_stack(s0[["overlay"]], list(kind = "mut_kind", arm_id = "mut_arm"))
  if (!identical(g0, .spec_sig(s2))) n_mut <- n_mut + 1L
}
if (n_read < 50L) cat(sprintf("  --- 실제 스펙 %d건(<50) — 실측 대조 생략(합성 대조 G3 는 돈다)\n", n_read)) else {
  if (all(okn == n_read)) ok(sprintf("G1 실제 스펙 %d건(overlay 키 없음 %d) × 변형 %d종(부기 필드 하나씩 · 넷 동시 · JSON 왕복) — 서명 전부 비트 동일",
                                     n_read, n_noov, length(VAR)))
  else ng("G1 서명 변경", paste(sprintf("%s=%d/%d(%s)", names(okn), okn, n_read, vapply(bad, function(b) paste(utils::head(b, 1), collapse = ""), character(1))), collapse = " · "))
  if (n_mut == n_read) ok(sprintf("G2 돌연변이 통제 — 실제 층을 얹으면 %d건 전부 서명이 바뀐다(대조의 판별력)", n_mut)) else ng("G2 판별력", paste(n_mut, n_read))
}
sig_lines <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), warn = FALSE, encoding = "UTF-8"))
i_s0 <- grep("^\\.spec_sig <- function\\(sp\\)", sig_lines)[1]
i_s1 <- if (is.na(i_s0)) NA_integer_ else i_s0 - 1L + which(grepl('collapse = "|")', sig_lines[i_s0:length(sig_lines)], fixed = TRUE))[1]
sig_fn <- if (is.na(i_s0) || is.na(i_s1)) "" else paste(sig_lines[i_s0:i_s1], collapse = "\n")
syn <- list(code = "B1_1", factors = list(list(kind = "db", id = "f1")), weighting = list(kind = "ew"),
            universe = list(kind = "k200_kq150"), base_signal = list(kind = "mom_12_1"))
syn_ok <- all(vapply(names(VAR), function(k) identical(.spec_sig(syn), .spec_sig(VAR[[k]](syn))), logical(1)))
if (nzchar(sig_fn) && grepl('sp[["overlay"]]', sig_fn, fixed = TRUE) && !grepl("sp$overlay", sig_fn, fixed = TRUE) &&
    !grepl("toJSON\\(sp\\s*[,)]", sig_fn) && syn_ok)
  ok("G3 .spec_sig 는 필드를 [[ ]] 정확 일치로 조립(전체 직렬화 아님) · overlay 키 없는 합성 스펙에 부기 필드 하나씩 → 서명 불변") else
  ng("G3 .spec_sig 구성", sprintf("fn=%d자 exact=%s dollar=%s syn=%s", nchar(sig_fn), grepl('sp[["overlay"]]', sig_fn, fixed = TRUE), grepl("sp$overlay", sig_fn, fixed = TRUE), syn_ok))
## 돌연변이 통제 — 소스에서 [[ ]] 를 `$` 로 되돌린 판을 만들어 같은 합성 스펙에 돌린다: 함정이 되살아나야 픽스처가 판별력을 갖는다
if (nzchar(sig_fn)) {
  menv <- new.env(parent = globalenv())
  eval(parse(text = sub("^\\.spec_sig <-", ".sig_dollar <-", gsub('sp[["overlay"]]', "sp$overlay", sig_fn, fixed = TRUE))), envir = menv)
  s_shift <- syn; s_shift$overlay_shift <- 0L
  if (!identical(menv$.sig_dollar(syn), menv$.sig_dollar(s_shift))) ok("G3b 돌연변이 통제 — `$overlay` 판은 overlay_shift=0 하나로 서명이 갈린다(부분 일치 함정 재현)") else ng("G3b 판별력 없음")
}
if (.has("SPEC$overlay_cell <- CELL$overlay") && .has("SPEC$floor_code <- .wbest_code") && .has("if (CELL$block %in% rf_axes_no_layer_blocks()) SPEC$overlay_cell <- list()") &&
    all(c("B1", "B2", "B3", "B6", "B7") %in% rf_axes_no_layer_blocks()) && !("B5" %in% rf_axes_no_layer_blocks()) &&
    .has("SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)"))
  ok("G4 러너 — B5 에 overlay_cell·floor_code · B1~B3 는 overlay_cell=[] · 중첩 줄(.ov_stack) 불변") else ng("G4 스펙 필드 배선")
if (.has("overlay=%s") && .has("rf_ov_txt(SPEC$overlay)") && !.has('ov = SPEC$overlay$arm_id %||% "none"'))
  ok("G5 idea·B4 로그·중복/무처치 사유에 오버레이 스택(a × b) 표기 — 구판 단수 접근 제거") else ng("G5 스택 표기")
if (identical(rf_ov_txt(NULL), "none") && identical(rf_ov_txt(list(kind = "k", arm_id = "a")), "a") &&
    identical(rf_ov_txt(list(list(kind = "k", arm_id = "a"), list(kind = "j", arm_id = "b"))), "a \u00d7 b"))
  ok("G6 rf_ov_txt — NULL none · 단층 id · 스택 ' × ' 연결") else ng("G6 표기 함수")
## ★B4-SIX(2026-09-26): 누적 = 등록부(rf_axes_accumulate · 전 축 [[ ]] 정확 일치) — 줄 대신 행동으로 잰다:
##   바닥 스펙에 overlay_cell=[] 만 있고 overlay 키가 없으면 누적 결과에 overlay 가 생기지 않는다($ 부분 일치 재발 방지).
.g7 <- rf_axes_accumulate(list(weighting = list(kind = "ew")), list(overlay_cell = list(), weighting = list(kind = "ew")), "B2")$spec
if (.has("rf_axes_accumulate(SPEC, .wbest_spec, CELL$block)") && !("overlay" %in% names(.g7)) && !.has(".wbest_spec$overlay"))
  ok("G7 러너 누적 — 바닥 스펙의 overlay 를 정확 일치로 읽는다(overlay_cell=[] 을 오버레이로 복사하지 않는다)") else ng("G7 누적 overlay 읽기")

cat("\n=== H. 주변 배선 — 승격 호출부 · 충실구현 스위치 · tick · 프롬프트 · 원장 writer ===\n")
np <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_next_paper.R"), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
if (grepl("rf_promote_carry(ws, cf, best, sp, cfg = CFG, root = ROOT,", np, fixed = TRUE) && grepl("parent_carry = (E2$carry %||% list())$overlay", np, fixed = TRUE) &&
    grepl("adversary = E$attempts[[i]]$adversary", np, fixed = TRUE) && grepl('jlog("carry_overlay_dropped"', np, fixed = TRUE))
  ok("H1 승격 호출부 — cfg · parent_carry · best$adversary 전달 · 버린 층 로그") else ng("H1 승격 호출부")
rp <- readLines(file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R"), warn = FALSE, encoding = "UTF-8"); rpc <- sub("#.*$", "", rp)
i_sw <- grep('Sys.getenv("QVEST_RP_NO_LCODE", "0")', rpc, fixed = TRUE); i_em <- grep('emit_lcode(mode = "paper_replication"', rpc, fixed = TRUE)
if (length(i_sw) && length(i_em) && i_sw[1] < i_em[1] && i_em[1] - i_sw[1] <= 6L) ok("H2 충실구현 §10 — QVEST_RP_NO_LCODE=1 이면 emit_lcode 를 건너뛴다(적대 재실행 격리)") else ng("H2 L-code 스위치", paste(i_sw[1], i_em[1]))
tk <- sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_tick.sh"), warn = FALSE, encoding = "UTF-8"))
i_b1 <- grep("rf_b1_design.sh", tk, fixed = TRUE); i_b5 <- grep('[ -f "$ROOT/02_Infrastructure/ops/rf_b5_design.sh" ] && bash', tk, fixed = TRUE); i_run <- grep("reinforce_auto_parallel.R", tk, fixed = TRUE)
if (length(i_b1) && length(i_b5) && length(i_run) && i_b1[1] < i_b5[1] && i_b5[1] < i_run[1]) ok("H3 tick — B1 설계 뒤 · 러너 앞에 B5 설계 레인(파일 있을 때만)") else ng("H3 tick 배선")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism.sh"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("picks: [id, id]", sh, fixed = TRUE) && grepl("${B5MAXL}", sh, fixed = TRUE) && grepl("${B5STAND}", sh, fixed = TRUE) &&
    grepl("b5_design", sh, fixed = TRUE) && grepl("standing_cells", sh, fixed = TRUE))
  ok("H4 기전 프롬프트 — B5 스택 picks 허용(상한 = config b5_design.max_layers) · 상주 arm 제안 금지 · 둘 다 정본에서 읽는다") else ng("H4 프롬프트 스택 계약")
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/reinforce_ledger.R"), local = globalenv()))))
if (exists("rf_record_b5_redesign", mode = "function")) {
  TL <- file.path(tempdir(), sprintf("rf_b5r_%d", Sys.getpid())); dir.create(file.path(TL, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L, entries = list(
    list(base_id = "T_RD", status = "active", base_grade = "C", attempts_used = 0L, attempts = list())), last_updated = ""),
    auto_unbox = TRUE, pretty = TRUE, null = "null"), file.path(TL, "06_Registry/reinforce_ledger_l1.json"))
  invisible(capture.output(rf_record_b5_redesign(1L, "T_RD", list(active = TRUE, round = 2L, at = "t0", cells_added = 3L, base_design_cells = 5L), root = TL)))
  e1 <- rf_load(1L, TL)$entries[[1]]
  invisible(capture.output(rf_record_b5_redesign(1L, "T_RD", list(active = FALSE, closed_at = "t1"), root = TL)))
  e2 <- rf_load(1L, TL)$entries[[1]]
  if (rf_b5_redesign_active(e1) && identical(as.integer(e1$b5_redesign$cells_added), 3L) && !rf_b5_redesign_active(e2) &&
      identical(as.integer(e2$b5_redesign$round), 2L) && identical(e2$b5_redesign$closed_at, "t1") && identical(e2$status, "active"))
    ok("H5 rf_record_b5_redesign — 열기·닫기 **병합**(round·cells_added 보존) · status 불변") else ng("H5 원장 writer")
  if (inherits(tryCatch(rf_record_b5_redesign(1L, "NOPE", list(active = TRUE), root = TL), error = function(e) e), "error") &&
      inherits(tryCatch(rf_record_b5_redesign(1L, "T_RD", list(), root = TL), error = function(e) e), "error"))
    ok("H6 writer — 없는 entry · 빈 필드 거부") else ng("H6 writer 거부")
  unlink(TL, recursive = TRUE, force = TRUE)
} else ng("H5 rf_record_b5_redesign 부재")

cat("\n=== I. 운영 entry 드라이 (읽기 전용 · 상태가 그대로일 때만) ===\n")
## ★운영 상태를 빌리는 단언은 그 상태가 바뀌면 깨진다(메모리 카드 09-05) — 재설계가 열렸거나 B5_31 시도가 생겼으면 판정 대신 사실만 적는다.
LP <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")
EI <- tryCatch({ L <- fromJSON(LP, simplifyVector = FALSE)
  e <- Filter(function(x) identical(x$base_id, "RP_20260917_105807_22632_combo_rulefast"), L$entries); if (length(e)) e[[1]] else NULL }, error = function(e) NULL)
sc0 <- rfbd_standing_cells(ROOT)
if (is.null(EI) || !length(sc0)) cat("  --- combo_rulefast entry 또는 상주 칸 없음 — 드라이 생략\n") else {
  di <- rf_standing_decision(sc0[[1]], EI$attempts, EI$carry$overlay, .rfbd_b5_raw(ROOT), rf_b5_redesign_active(EI))
  if (rf_b5_redesign_active(EI) || "B5_31" %in% .rf_taken_codes(EI$attempts %||% list()) || !any(startsWith(.rf_taken_codes(EI$attempts %||% list()), "B5_")))
    cat(sprintf("  --- 운영 entry 상태가 바뀜(재설계/상주 시도/B5 미측정) — 판정: insert=%s reason=%s\n", di$insert, di$reason))
  else if (isFALSE(di$insert) && identical(di$reason, "b5_measured_no_redesign"))
    ok("I1 combo_rulefast — B5 측정됨 ∧ 재설계 없음 → B5_31 자동 삽입 안 함(사유 b5_measured_no_redesign)") else ng("I1 운영 entry 삽입 판정", paste(di$insert, di$reason))
}
unlink(TMPD, recursive = TRUE, force = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_runner_standing_adversary","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
