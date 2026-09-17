#!/usr/bin/env Rscript
#==============================================================================
# test_rf_promote_overlay_carry.R — 승격 carry 의 오버레이 스택 규칙 3종 (2026-09-17 · WP-Z)
#
# 재는 것 (합성 픽스처 · 격리 root · 운영 원장·격자·설정 무접촉):
#   P1 상한 — 층 수 > max_layers 면 **가장 오래된 carry 층부터** 버린다(끝 = 이 칸의 몫이 살아남는다)
#   P2 상주 — program standing_cells 의 overlay_pick 은 물려주지 않는다(다음 세대도 상주로 돈다 — 이중 적용)
#   P3 적대검증 — 승자 attempt 에 adversary$verdict ≠ "pass" 가 있으면 그 attempt 의 **자기 층**만 뺀다
#   P4 구 attempt(verdict 없음)·pass 는 **입력 그대로**(단수 객체 형태·서명 불변 — 음성 대조)
#   P5 자기 층 판별 사다리 — overlay_cell > overlay − parent_carry > B5 칸의 마지막 층 > 비B5 는 안 버린다(보수)
#   P6 상한 출처 — cfg 인자 > config 파일(b5_design.max_layers) > 3
#   P7 돌연변이 통제 — 구판(overlay = ws$overlay 그대로)이면 P1~P3 픽스처가 전부 통과됐다(판별력)
#   P8 버린 층은 overlay_dropped 에 {kind, arm_id, why} 로 남는다(조용한 소실 금지)
# 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_promote_overlay_carry.R
#==============================================================================
suppressMessages(library(jsonlite))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R"), local = globalenv()))))

## 격리 root — 격자(standing_cells)만 있고 config 는 없다(기본 상한 3)
TMP <- file.path(tempdir(), sprintf("rfp_ov_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
J <- function(x) toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null")
write(J(list(schema = "reinforce_program_v1", blocks = list(),
             standing_cells = list(list(code = "B5_31", block = "B5", label = "상주", overlay_pick = "pg2_risk_overlay_v1")))),
      file.path(TMP, "06_Registry/reinforce_program.json"))
## 임시 원장(부모 entry 의 carry 를 담는다 — parent_carry 인자의 출처)
L1 <- list(kind = "ts_mom_gate", arm_id = "ts_mom_sign")           # 가장 오래된 carry 층
L2 <- list(kind = "dd_brake",    arm_id = "dd_brake_q")
L3 <- list(kind = "gen_a",       arm_id = "csd_idio_tilt")
OWN <- list(kind = "gen_b",      arm_id = "multivar_channel_tilt")  # 이 승자 칸의 몫(끝)
STD <- list(kind = "pg2_risk_overlay", arm_id = "pg2_risk_overlay_v1")
write(J(list(entries = list(list(base_id = "PARENT", carry = list(overlay = list(L1, L2, L3)))))),
      file.path(TMP, "06_Registry/reinforce_ledger_l1.json"))
PLED <- fromJSON(file.path(TMP, "06_Registry/reinforce_ledger_l1.json"), simplifyVector = FALSE)
PCARRY <- PLED$entries[[1]]$carry$overlay
ws4 <- list(factors = list(list(kind = "db", id = "S01_Size")), weighting = list(kind = "ew"),
            universe = list(kind = "k200_kq150"), overlay = list(L1, L2, L3, OWN))
best <- list(cell_code = "B5_17", port_t = 2.6, grade = "B")
ids <- function(ov) vapply(.ov_layers(ov), function(z) as.character(z$arm_id), character(1))
## ★픽스처는 직접 대입으로 만든다 — modifyList 는 리스트 값을 **병합**한다(이름 없는 층 리스트는 아예 안 바뀐다).
##   첫 판이 그 함정을 밟아 7개 단정이 "코드 결함" 처럼 보였다(실제는 픽스처가 4층 그대로였다).
wsov <- function(ov, cell = NULL) { w <- ws4; w$overlay <- ov; if (!is.null(cell)) w$overlay_cell <- cell; w }
bestv <- function(v, code = "B5_17") { b <- best; b$cell_code <- code; b$adversary <- list(verdict = v, note = "검사"); b }

cat("=== P1. 상한 — 오래된 carry 층부터 버린다 ===\n")
c1 <- rf_promote_carry(ws4, ws4$factors, best, "spec.json", root = TMP)
if (identical(ids(c1$overlay), c("dd_brake_q", "csd_idio_tilt", "multivar_channel_tilt")))
  ok("P1 4층 → 3층: ts_mom_sign(가장 오래된 carry) 탈락 · 이 칸의 몫(끝)은 산다") else ng("P1 상한", paste(ids(c1$overlay), collapse = ","))
if (length(c1$overlay_dropped) == 1L && identical(c1$overlay_dropped[[1]]$arm_id, "ts_mom_sign") && identical(c1$overlay_dropped[[1]]$why, "cap:3"))
  ok("P8 overlay_dropped = {ts_mom_sign, cap:3}") else ng("P8 dropped 기록", J(c1$overlay_dropped))
c1b <- rf_promote_carry(ws4, ws4$factors, best, "spec.json", cfg = list(b5_design = list(max_layers = 2)), root = TMP)
if (identical(ids(c1b$overlay), c("csd_idio_tilt", "multivar_channel_tilt"))) ok("P6 cfg$b5_design$max_layers=2 → 2층") else ng("P6 cfg 상한", paste(ids(c1b$overlay), collapse = ","))
write('{"b5_design": {"max_layers": 2}}', file.path(TMP, "06_Registry/reinforce_auto_config.json"))
c1c <- rf_promote_carry(ws4, ws4$factors, best, "spec.json", root = TMP)
if (identical(ids(c1c$overlay), c("csd_idio_tilt", "multivar_channel_tilt"))) ok("P6 cfg 인자 없으면 config 파일(b5_design.max_layers=2)") else ng("P6 config 파일 상한", paste(ids(c1c$overlay), collapse = ","))
unlink(file.path(TMP, "06_Registry/reinforce_auto_config.json"))
if (identical(rf_promote_carry(ws4, ws4$factors, best, "spec.json", cfg = list(b5_design = list(max_layers = 1)), root = TMP)$overlay, OWN))
  ok("P1 상한 1 → 이 칸의 몫 하나만 · 단수 객체 형태") else ng("P1 상한 1")

cat("=== P2. 상주 arm 제외 ===\n")
ws_s <- wsov(list(STD, OWN))
c2 <- rf_promote_carry(ws_s, ws_s$factors, best, "spec.json", root = TMP)
if (identical(c2$overlay, OWN) && identical(c2$overlay_dropped[[1]]$why, "standing"))
  ok("P2 [상주 × own] → own 만(단수 객체) · dropped why=standing") else ng("P2 상주 제외", paste(ids(c2$overlay), collapse = ","))
c2b <- rf_promote_carry(wsov(STD), ws4$factors, best, "spec.json", root = TMP)
if (is.null(c2b$overlay) && length(c2b$overlay_dropped) == 1L) ok("P2 상주만 있으면 overlay NULL(물려줄 것 없음) + dropped 기록") else ng("P2 상주 단독", J(c2b$overlay))

cat("=== P3. 적대검증 — 자기 층만 뺀다 ===\n")
ws3 <- wsov(list(L2, L3, OWN), cell = OWN)
bf <- bestv("fail")
c3 <- rf_promote_carry(ws3, ws3$factors, bf, "spec.json", root = TMP)
if (identical(ids(c3$overlay), c("dd_brake_q", "csd_idio_tilt")) && identical(c3$overlay_dropped[[1]]$why, "adversary:fail"))
  ok("P3 verdict=fail → overlay_cell(자기 층) 탈락 · carry 층은 승계 · why=adversary:fail") else ng("P3 adversary", paste(ids(c3$overlay), collapse = ","))
c3b <- rf_promote_carry(ws3, ws3$factors, bestv("not_candidate"), "spec.json", root = TMP)
if (identical(ids(c3b$overlay), c("dd_brake_q", "csd_idio_tilt"))) ok("P3 verdict=not_candidate 도 pass 가 아니면 자기 층 탈락") else ng("P3 not_candidate", paste(ids(c3b$overlay), collapse = ","))
ws3n <- wsov(list(L2, L3, OWN))   # overlay_cell 없음
c5 <- rf_promote_carry(ws3n, ws3n$factors, bf, "spec.json", root = TMP, parent_carry = list(L2, L3))
if (identical(ids(c5$overlay), c("dd_brake_q", "csd_idio_tilt"))) ok("P5 overlay_cell 없음 + parent_carry → overlay − carry 가 자기 층") else ng("P5 parent_carry", paste(ids(c5$overlay), collapse = ","))
c5b <- rf_promote_carry(ws3n, ws3n$factors, bf, "spec.json", root = TMP)
if (identical(ids(c5b$overlay), c("dd_brake_q", "csd_idio_tilt"))) ok("P5 둘 다 없음 + B5 칸 → 마지막 층이 자기 층") else ng("P5 B5 마지막 층", paste(ids(c5b$overlay), collapse = ","))
c5c <- rf_promote_carry(ws3n, ws3n$factors, bestv("fail", code = "B4_21"), "spec.json", root = TMP)
if (identical(c5c$overlay, ws3n$overlay) && is.null(c5c$overlay_dropped)) ok("P5 비B5 칸 + 판별 불가 → 아무것도 안 버린다(보수)") else ng("P5 비B5 보수", paste(ids(c5c$overlay), collapse = ","))
c5d <- rf_promote_carry(ws3n, ws3n$factors, bestv("fail", code = "B4_21"), "spec.json", root = TMP, parent_carry = list(L2, L3))
if (identical(ids(c5d$overlay), c("dd_brake_q", "csd_idio_tilt"))) ok("P5 비B5 칸이라도 parent_carry 가 있으면 자기 층을 가려 뺀다") else ng("P5 비B5 + parent_carry", paste(ids(c5d$overlay), collapse = ","))

cat("=== P4. 음성 대조 — 구 attempt · pass · 상한 이내는 입력 그대로 ===\n")
ws1 <- wsov(list(kind = "arm", arm_id = "dbeta_tilt"))
c4 <- rf_promote_carry(ws1, ws1$factors, best, "spec.json", root = TMP)
if (identical(c4$overlay, ws1$overlay) && is.null(c4$overlay_dropped)) ok("P4 단층·verdict 없음 → overlay 비트 동일(단수 객체) · dropped 없음") else ng("P4 단층 불변")
ws3p <- wsov(list(L2, L3, OWN), cell = OWN)
c4b <- rf_promote_carry(ws3p, ws3p$factors, bestv("pass"), "spec.json", root = TMP)
if (identical(c4b$overlay, ws3p$overlay) && is.null(c4b$overlay_dropped)) ok("P4 verdict=pass → 3층 그대로(리스트 형태 불변)") else ng("P4 pass 불변", paste(ids(c4b$overlay), collapse = ","))
c4c <- rf_promote_carry(wsov(NULL), ws4$factors, best, "spec.json", root = TMP)
if (is.null(c4c$overlay) && identical(c4c$universe, list(kind = "k200_kq150")) && identical(c4c$universe_reset_from, ws4$universe))
  ok("P4 오버레이 없음 → NULL · 유니버스 리셋·provenance 는 구판 그대로") else ng("P4 NULL 오버레이")
if (identical(c4$factors, ws1$factors) && identical(c4$weighting, ws1$weighting) && identical(c4$source_cell, "B5_17"))
  ok("P4 팩터·비중·source_cell 은 건드리지 않는다") else ng("P4 다른 축 훼손")

cat("=== P7. 돌연변이 통제 — 구판(그대로 승계)이면 위 픽스처가 전부 통과됐다 ===\n")
naive <- function(ws) ws$overlay
if (length(.ov_layers(naive(ws4))) == 4L && "pg2_risk_overlay_v1" %in% ids(naive(ws_s)) && "multivar_channel_tilt" %in% ids(naive(ws3)))
  ok("P7 구판은 4층·상주·적대검증 실패 층을 전부 물려줬다 — 픽스처가 결함을 가른다") else ng("P7 판별력 없음")

unlink(TMP, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_promote_overlay_carry","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
