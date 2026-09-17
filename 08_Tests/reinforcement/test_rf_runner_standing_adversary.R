#!/usr/bin/env Rscript
#==============================================================================
# test_rf_runner_standing_adversary.R — 상주 칸 · 예산 재도출 · 적대검증 소비 · Grade A 보류 **양방향 검사** (WP-R · 2026-09-17)
#
# 재는 것 (판정은 정본 rf_runner_gates.R 의 순수 함수 · 배선은 러너 소스 대조 · 실행은 격리 샌드박스):
#   A 상주 삽입 판정 — (a) 시도 존재 → 항상 (b) B5 미측정 ∧ active ∧ carry 밖 (c) 재설계 라운드 · 건너뜀 사유 4종
#   B 러너 배선 — B5 첫 칸 삽입 · 규칙 픽커가 비상주 슬롯만 채우고 상주 arm 을 제외 · 회피 집행 면제
#   C 예산 — 산식(B4 미절단) · 수동 상향 존중 · 자동은 자동식 위로 못 올린다 · 재설계 열림/닫힘의 합이 같다
#   D 승자 게이트 — 러너의 .winner_of 를 **소스에서 추출해** 돌린다: pass 유지 · fail/not_candidate 제외 · 구 attempt 유지 · 전멸 → NULL
#   E Grade A 보류 — B5 자기 층 ∧ pass 없음 → 보류 · pass → 발행 · B1 / 승계 층만 → 발행 · 러너 발행 1함수·경계 해제 배선
#   F lcm_merge — B5 시도가 있는 entry 의 B5 설계는 거부(기전은 병합) · 없는 entry 는 저장(양성 대조) — 격리 root 에서 실제 실행
#   G 서명 불변 — 실제 스펙 파일에 overlay_cell/floor_code/overlay_shift/overlay_strict 를 얹어도 .spec_sig 비트 동일(+돌연변이 통제)
#   H 주변 배선 — 승격 호출부(cfg·parent_carry·adversary) · 충실구현 L-code 스위치 · tick 의 B5 레인 · 프롬프트 스택 계약 · 원장 writer
#   I 운영 entry 드라이(읽기 전용 · 있을 때만) — combo_rulefast 는 B5_31 을 자동 삽입하지 않는다
# 부작용 없음: 운영 원장·로그·설정 무접촉(샌드박스 tempdir · 러너는 source 하지 않는다).
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

cat("\n=== B. 러너 배선 — 삽입 위치 · 픽커 슬롯 · 회피 면제 (소스 대조) ===\n")
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

cat("\n=== C. 예산 재도출 (rf_budget_auto / rf_budget_want / rf_b5_design_counts) ===\n")
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

cat("\n=== D. 승자 게이트 — 러너 .winner_of 추출 실행 ===\n")
if (rf_adversary_ok(list(n = 1L)) && rf_adversary_ok(list(adversary = list(verdict = "pass"))) &&
    !rf_adversary_ok(list(adversary = list(verdict = "fail"))) && !rf_adversary_ok(list(adversary = list(verdict = "not_candidate"))) &&
    !rf_adversary_ok(list(adversary = list(verdict = "error"))))
  ok("D1 rf_adversary_ok — 부재/pass 만 TRUE · fail/error/not_candidate FALSE") else ng("D1 술어")
TMPD <- file.path(tempdir(), sprintf("rf_gates_%d", Sys.getpid())); dir.create(TMPD, recursive = TRUE, showWarnings = FALSE)
mkspec <- function(cd, arm) { p <- file.path(TMPD, sprintf("spec_%s.json", cd))
  write(toJSON(list(code = cd, factors = list(), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"),
                    overlay = list(kind = "k", arm_id = arm)), auto_unbox = TRUE, null = "null"), p); p }
matt <- function(n, cd, cal, verdict = NULL) { a <- list(n = n, cell_code = cd, grade = "B",
  essence = list(cell_code = cd, port_t = 2, calmar = cal, spec = mkspec(cd, paste0("arm_", cd))))
  if (!is.null(verdict)) a$adversary <- list(verdict = verdict); a }
ATT <- list(matt(1L, "B5_16", 0.50), matt(2L, "B5_17", 0.90, "fail"), matt(3L, "B5_18", 0.70, "pass"), matt(4L, "B5_19", 0.95, "not_candidate"))
i0 <- grep("^\\.winner_of <- function\\(bid", src); i1 <- if (length(i0)) i0 + which(grepl("^}", src[(i0 + 1L):length(src)]))[1] else NA
if (!length(i0) || is.na(i1)) ng("D2 .winner_of 추출 실패") else {
  env <- new.env(); env$cells <- list(); env$E <- list(attempts = ATT); env$.log <- list()
  env$jlog <- function(event, ...) env$.log[[length(env$.log) + 1L]] <- c(list(event = event), list(...))
  env$.metric <- function(a, key) { es <- a$essence; if (is.list(es) && !is.null(es[[key]])) as.numeric(es[[key]]) else NA_real_ }
  env$.cell_by_code <- function(cd) NULL; env$`%||%` <- `%||%`; env$rf_adversary_ok <- rf_adversary_ok; env$fromJSON <- fromJSON
  eval(parse(text = src[i0:i1]), envir = env)
  w <- env$.winner_of("B5", "calmar", gate = rf_adversary_ok)
  if (!is.null(w) && identical(w$overlay$arm_id, "arm_B5_18")) ok("D2 게이트 — calmar 최고 B5_19(not_candidate)·B5_17(fail) 제외, pass 인 B5_18 승자") else ng("D2 게이트 승자", w$overlay$arm_id %||% "NULL")
  ev <- vapply(env$.log, function(z) as.character(z$event), character(1)); ex <- env$.log[ev == "winner_excluded_adversary"]
  if (length(ex) == 2L && setequal(vapply(ex, function(z) z$code, character(1)), c("B5_17", "B5_19"))) ok("D3 제외 2건이 코드·verdict 와 함께 로그로 남는다") else ng("D3 제외 로그", as.character(length(ex)))
  w0 <- env$.winner_of("B5", "calmar")
  if (!is.null(w0) && identical(w0$overlay$arm_id, "arm_B5_19")) ok("D4 게이트 없는 호출(구판)은 not_candidate 도 승자 — 돌연변이 통제: 게이트가 결과를 가른다") else ng("D4 무게이트 대조")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5, "fail"), matt(2L, "B5_17", 0.9, "not_candidate")))
  if (is.null(env$.winner_of("B5", "calmar", gate = rf_adversary_ok))) ok("D5 전부 탈락 → NULL(B4 는 carry 오버레이만 깐다)") else ng("D5 전멸 시 NULL")
  env$E <- list(attempts = list(matt(1L, "B5_16", 0.5), matt(2L, "B5_17", 0.9)))
  w2 <- env$.winner_of("B5", "calmar", gate = rf_adversary_ok)
  if (!is.null(w2) && identical(w2$overlay$arm_id, "arm_B5_17")) ok("D6 verdict 없는 구 attempt 는 그대로 승자(구판 거동 보존)") else ng("D6 구 attempt")
}
if (.has('.winner_of("B5", "calmar", gate = rf_adversary_ok)') && .has(".w5_overlay <- if (!is.null(w5)) w5$overlay else E$carry$overlay") &&
    .has('if ("B5" %in% use) .w5_overlay else (E$carry$overlay %||% NULL)'))
  ok("D7 러너 — B5 승자만 게이트 · 승자 없으면 carry 오버레이(부모 위험통제 보존) · B4 LOO 줄 불변") else ng("D7 러너 승자 배선")

cat("\n=== E. Grade A 보류·해제 ===\n")
OWN <- list(kind = "x", arm_id = "a"); CAR <- list(kind = "c", arm_id = "carry1")
sp_b5 <- list(code = "B5_17", overlay = list(CAR, OWN), overlay_cell = OWN)
if (rf_grade_a_hold("B5_17", sp_b5, CAR, NULL) && rf_grade_a_hold("B5_17", sp_b5, CAR, list(adversary = list(verdict = "fail"))))
  ok("E1 B5 자기 층 ∧ verdict 없음/fail → 보류") else ng("E1 보류")
if (!rf_grade_a_hold("B5_17", sp_b5, CAR, list(adversary = list(verdict = "pass")))) ok("E2 pass → 발행") else ng("E2 pass")
if (!rf_grade_a_hold("B1_1", list(overlay = OWN, overlay_cell = list()), NULL, NULL)) ok("E3 B1 은 보류 대상 아님") else ng("E3 B1")
if (!rf_grade_a_hold("B5_18", list(overlay = CAR, overlay_cell = list()), CAR, NULL)) ok("E4 B5 인데 승계 층뿐(자기 층 0) → 발행") else ng("E4 승계만")
if (!rf_grade_a_hold("B5_18", list(overlay = list(CAR, OWN)), CAR, NULL) == FALSE) ok("E5 overlay_cell 없는 구 스펙 → overlay − carry 폴백으로 자기 층 판별(보류)") else ng("E5 폴백")
if (rf_grade_a_hold("B5_19", NULL, NULL, NULL)) ok("E6 스펙을 못 읽는 B5 칸은 보수적으로 보류(정직 결측)") else ng("E6 NULL 스펙")
n_def <- sum(grepl("^\\.grade_a_enqueue <- function", code)); n_call <- sum(grepl(".grade_a_enqueue(", code, fixed = TRUE)) - n_def
if (n_def == 1L && n_call >= 2L) ok(sprintf("E7 발행 1함수(정의 1 · 호출 %d — 즉시 경로 + 경계 해제 경로)", n_call)) else ng("E7 발행 함수", paste(n_def, n_call))
if (.has('jlog("grade_a_hold_adversary"') && .has('jlog("grade_a_released"') && .has('jlog("grade_a_adversary_blocked"') && .has('jlog("grade_a_hold_unresolved"') &&
    .has("if (rf_grade_a_hold(j$code, .spA, E$carry$overlay))"))
  ok("E8 러너 — 보류·해제·차단·미결 네 사건 전부 로그 · 판정은 정본 함수") else ng("E8 러너 보류 배선")
i_adv <- .at('rf_overlay_adversary_run(BID, "B5", 1L, root = ROOT)'); i_lc <- .at("rf_emit_block_lcode(BID, u2")
if (!is.na(i_adv) && !is.na(i_lc) && i_adv < i_lc && grepl("tryCatch", code[i_adv - 2L], fixed = TRUE) &&
    .has('jlog("adversary_done"') && .has('jlog("adversary_failed"') && .has("identical(.blk_now, \"B5\") && .blk_left == 0L) || length(.held_a)"))
  ok("E9 적대검증 — B5 경계(또는 보류 A)에서 tryCatch 안 · L-code 발행 **앞** · 성공/실패 둘 다 로그") else ng("E9 적대검증 배선", paste(i_adv, i_lc))
if (.has("rf_record_b5_redesign(1L, BID, list(active = FALSE") && .has('jlog("b5_redesign_closed"')) ok("E10 재설계 라운드는 B5 경계에서 러너가 닫는다(레인 계약)") else ng("E10 재설계 종료")

cat("\n=== F. lcm_merge — B5 사후 설계 거부 (격리 root · 실제 실행) ===\n")
LIB <- file.path(ROOT, "02_Infrastructure/ops/rf_lcode_mechanism_lib.R")
SBX <- file.path(tempdir(), sprintf("rf_lcm_%d", Sys.getpid()))
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement", "06_Registry", "stage_artifacts/l_code/reinforcement", ".cache"))
  dir.create(file.path(SBX, d), recursive = TRUE, showWarnings = FALSE)
file.copy(file.path(ROOT, "02_Infrastructure/reinforcement/rf_block_design.R"), file.path(SBX, "02_Infrastructure/reinforcement/"), overwrite = TRUE)
file.copy(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), file.path(SBX, "02_Infrastructure/ops/"), overwrite = TRUE)
file.copy(file.path(ROOT, "06_Registry/reinforce_program.json"), file.path(SBX, "06_Registry/"), overwrite = TRUE)
file.copy(file.path(ROOT, "06_Registry/overlay_catalog.json"), file.path(SBX, "06_Registry/"), overwrite = TRUE)
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
run_merge <- function(b) { old <- Sys.getenv("QVEST_RF_ROOT", unset = NA); Sys.setenv(QVEST_RF_ROOT = SBX)
  on.exit(if (is.na(old)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = old), add = TRUE)
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
}
lib_src <- paste(sub("#.*$", "", readLines(LIB, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
if (grepl("rfbd_standing_picks(ROOT)", lib_src, fixed = TRUE) && grepl('identical(.nxt, "B5")', lib_src, fixed = TRUE))
  ok("F4 materials — B5 카탈로그 목록에서 상주 arm 을 뺀다") else ng("F4 materials 상주 제외")
unlink(SBX, recursive = TRUE, force = TRUE)

cat("\n=== G. 서명 불변 — 부기 필드는 .spec_sig 에 안 들어간다 (실제 스펙) ===\n")
.spd <- file.path(ROOT, ".cache/rf_parallel")
.fs <- if (dir.exists(.spd)) utils::head(sort(list.files(.spd, pattern = "^spec_B[0-9]+_[0-9]+__.*\\.json$", full.names = TRUE), decreasing = TRUE), 300L) else character(0)
n_ok <- 0L; bad <- character(0); n_mut <- 0L
for (f in .fs) {
  s0 <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL); if (is.null(s0)) next
  s1 <- s0; s1$overlay_cell <- s0$overlay %||% list(); s1$floor_code <- "B1_1"; s1$overlay_shift <- 0L; s1$overlay_strict <- FALSE
  if (identical(.spec_sig(s0), .spec_sig(s1)) && .same_axis(s0$overlay, s1$overlay)) n_ok <- n_ok + 1L else bad <- c(bad, basename(f))
  s2 <- s0; s2$overlay <- .ov_stack(s0$overlay, list(kind = "mut_kind", arm_id = "mut_arm"))
  if (!identical(.spec_sig(s0), .spec_sig(s2))) n_mut <- n_mut + 1L
}
if (length(.fs) && !length(bad)) ok(sprintf("G1 실제 스펙 %d건 — overlay_cell/floor_code/overlay_shift/overlay_strict 를 얹어도 서명 비트 동일", n_ok)) else ng("G1 서명 변경", paste(utils::head(bad, 3), collapse = ","))
if (length(.fs) && n_mut == n_ok + length(bad)) ok("G2 돌연변이 통제 — 층을 실제로 얹으면 서명이 바뀐다(픽스처 판별력)") else ng("G2 판별력", paste(n_mut, n_ok))
sig_src <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
i_s <- regexpr("\\.spec_sig <- function\\(sp\\)[^\n]*(\n[^\n]*){0,10}", sig_src); sig_fn <- regmatches(sig_src, i_s)
if (length(sig_fn) && !grepl("overlay_cell|floor_code|overlay_shift|overlay_strict|toJSON\\(sp\\b", sig_fn))
  ok("G3 .spec_sig 는 필드 조립식(전체 스펙 직렬화 아님) — 부기 필드가 원리상 안 들어간다") else ng("G3 .spec_sig 구성")
if (.has("SPEC$overlay_cell <- CELL$overlay") && .has("SPEC$floor_code <- .wbest_code") && .has('if (CELL$block %in% c("B1", "B2", "B3")) SPEC$overlay_cell <- list()') &&
    .has("SPEC$overlay <- .ov_stack(E$carry$overlay, CELL$overlay)"))
  ok("G4 러너 — B5 에 overlay_cell·floor_code · B1~B3 는 overlay_cell=[] · 중첩 줄(.ov_stack) 불변") else ng("G4 스펙 필드 배선")
if (.has("overlay=%s") && .has("rf_ov_txt(SPEC$overlay)") && !.has('ov = SPEC$overlay$arm_id %||% "none"'))
  ok("G5 idea·B4 로그·중복/무처치 사유에 오버레이 스택(a × b) 표기 — 구판 단수 접근 제거") else ng("G5 스택 표기")
if (identical(rf_ov_txt(NULL), "none") && identical(rf_ov_txt(list(kind = "k", arm_id = "a")), "a") &&
    identical(rf_ov_txt(list(list(kind = "k", arm_id = "a"), list(kind = "j", arm_id = "b"))), "a \u00d7 b"))
  ok("G6 rf_ov_txt — NULL none · 단층 id · 스택 ' × ' 연결") else ng("G6 표기 함수")

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

cat("\n=== I. 운영 entry 드라이 (읽기 전용 · 있을 때만) ===\n")
LP <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")
EI <- tryCatch({ L <- fromJSON(LP, simplifyVector = FALSE)
  e <- Filter(function(x) identical(x$base_id, "RP_20260917_105807_22632_combo_rulefast"), L$entries); if (length(e)) e[[1]] else NULL }, error = function(e) NULL)
if (is.null(EI)) cat("  --- combo_rulefast entry 없음 — 드라이 생략\n") else {
  sc0 <- rfbd_standing_cells(ROOT)
  di <- if (length(sc0)) rf_standing_decision(sc0[[1]], EI$attempts, EI$carry$overlay, .rfbd_b5_raw(ROOT), rf_b5_redesign_active(EI)) else list(insert = NA, reason = "no_standing")
  if (isFALSE(di$insert) && identical(di$reason, "b5_measured_no_redesign"))
    ok("I1 combo_rulefast — B5 측정됨 ∧ 재설계 없음 → B5_31 자동 삽입 안 함(사유 b5_measured_no_redesign)") else ng("I1 운영 entry 삽입 판정", paste(di$insert, di$reason))
}
unlink(TMPD, recursive = TRUE, force = TRUE)

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_runner_standing_adversary","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
