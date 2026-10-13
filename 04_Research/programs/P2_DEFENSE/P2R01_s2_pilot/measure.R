## P2R01 S2 파일럿 — 처방 → 검증 → 사양 → 시행 회계 → ★사전등록(R2 · 측정 전 고정) → 측정(정본 셀 워커 · close_t1)
## 실행: Rscript measure.R [--register-only]
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/round_common.R"))
ARGS <- commandArgs(trailingOnly = TRUE); REGISTER_ONLY <- "--register-only" %in% ARGS
PROGRAM <- "P2_DEFENSE"; ROUND <- "P2R01_s2_pilot"
P <- rx_paths(PROGRAM, ROUND, ROOT); LP <- P$lane("prescriber")

## ① 처방 판독 — 실행 성공 · 금지 정보 없음 · 1~3건
rl <- readLines(file.path(LP, "run.log"), warn = FALSE)
if (!any(grepl("^rc=0$", rl))) stop("[measure] 처방 담당 레인 실패: ", paste(rl, collapse = " | "))
po <- readLines(file.path(LP, "out.md"), warn = FALSE, encoding = "UTF-8")
.rx_assert_clean(paste(po, collapse = "\n"), ROOT, "prescriptions")
pj <- rx_parse_json(po)
RX <- pj$prescriptions
if (!length(RX) || length(RX) > 3L) stop("[measure] 처방은 1~3건이어야 한다: ", length(RX))
FIELDS <- readLines(file.path(P$round_dir, "falsification_fields.txt"))

## ② 검증 — 구현은 엔진 파서 · 반증 규칙은 필드 · 연산자 · 값 형식
chk_rule <- function(r) {
  e <- character(0)
  if (!(as.character(r$field %||% "") %in% FIELDS)) e <- c(e, paste0("필드 밖: ", r$field %||% ""))
  if (!(as.character(r$op %||% "") %in% c("<", "<=", ">", ">="))) e <- c(e, paste0("연산자 밖: ", r$op %||% ""))
  if (is.null(r$ref)) { if (!is.numeric(r$value) || length(r$value) != 1L || !is.finite(r$value)) e <- c(e, "value 숫자 아님") }
  else if (!identical(r$ref, "base") || !is.numeric(r$delta %||% NULL)) e <- c(e, "ref 는 base · delta 숫자")
  e
}
val <- lapply(RX, function(z) {
  v <- rx_validate(z$implementation, ROOT)
  fe <- unlist(lapply(z$falsification %||% list(), chk_rule))
  if (!length(z$falsification)) fe <- c(fe, "반증 조건 없음")
  list(id = z$id, ok = isTRUE(v$ok) && !length(fe), impl_errors = v$errors, rule_errors = fe)
})
for (v in val) cat(sprintf("[검증] %s — %s %s\n", v$id, if (v$ok) "통과" else "거부",
                           paste(c(v$impl_errors, v$rule_errors), collapse = " | ")))
ok_ids <- vapply(Filter(function(v) v$ok, val), function(v) v$id, character(1))
if (!length(ok_ids)) stop("[measure] 유효한 처방이 없다 — 측정하지 않는다")

## ③ 시행 회계(R3) — 계보 측정 시도 수 + 기저 1 + 이번 라운드 유효 변형 수(RX0 대조는 무가산)
n_lin <- rc_lineage_trials(ROOT)
n_family <- as.integer(n_lin + 1L + length(ok_ids))
base_spec <- fromJSON(file.path(P$round_dir, "base", "base_cell_spec.json"), simplifyVector = FALSE)
SA <- list(selection_type = "sweep", family_root = base_spec$selection_accounting$family_root %||% NA_character_,
           lineage = c(paste0("RX_", ROUND), unlist(base_spec$selection_accounting$lineage)),
           n_family_at_registration = n_family,
           n_trials_basis = sprintf("rx_pilot: L1 계보 측정 시도 %d(2002.06975 · essence/grade 보유) + 기저 1 + 이번 라운드 유효 변형 %d",
                                    n_lin, length(ok_ids)))

## ④ 셀 사양 — RX0(같은 판본 기저 대조 · round_common.R · rx0_measure.R 와 같은 사양) + 처방
specs <- list()
f0 <- file.path(P$specs_dir, "P2R01_RX0.json")
m0 <- rc_write_spec(rc_rx0_spec(P, ROUND, n_lin), f0)
specs[["RX0"]] <- list(code = "P2R01_RX0", path = f0, md5 = m0, control = TRUE)
for (z in RX) {
  if (!(z$id %in% ok_ids)) next
  code <- paste0("P2R01_", z$id)
  sp <- rx_compile_spec(base_spec, z$implementation, code = code, label = z$name %||% z$id,
                        idea = sprintf("[처방 루프 v0 · %s · %s] %s", ROUND, z$id, substr(z$mechanism %||% "", 1, 300)),
                        selection_accounting = SA)
  f <- file.path(P$specs_dir, paste0(code, ".json"))
  specs[[z$id]] <- list(code = code, path = f, md5 = rc_write_spec(sp, f))
}

## ⑤ 사전등록(측정 전 · 정본 = stage_artifacts/programs/<프로그램>/<round>/prereg.json · research-program SKILL §2)
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
PR <- file.path(P$prereg_dir, "prereg.json")
if (file.exists(PR)) stop("[measure] 사전등록이 이미 있다 — 결과 뒤 재작성 금지(R2): ", PR)
pre <- list(
  schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND,
  registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "S2 파일럿 — 처방 루프 v0(분석가 → 처방 담당 → 사전등록 → 측정 → 리뷰어) 1회전 · 도훈 결정 GRADE-V3-PROMOTE ③ 출발점 = 2002.06975 계보",
  base = list(artifact = "stage_artifacts/replication/20260923_205641_8212/remeasure_close_t1_5562284e", cell = "B6_36",
              spec_md5 = rc_md5(file.path(P$round_dir, "base", "base_cell_spec.json")),
              packet_md5 = rc_md5(file.path(P$round_dir, "base", "diagnosis_packet.json")),
              flags = "automem 노출 'possible'(AUTOMEM-EXPOSED-CELLS-DISPOSITION · 이 계보 A 는 보류) · C1 표식 없음"),
  tau_d = "2022-12-31",
  agents = list(analyst = list(out = file.path(P$round_dir, "lane_analyst", "out.md"), md5 = rc_md5(file.path(P$round_dir, "lane_analyst", "out.md"))),
                prescriber = list(out = file.path(LP, "out.md"), md5 = rc_md5(file.path(LP, "out.md"))),
                lane = "programs/rx_lane.sh — 청정(자동 기억 차단 · R6 읽기 가드) · opus · 읽기 전용"),
  prescriptions = lapply(RX, function(z) c(z, list(validation = Filter(function(v) identical(v$id, z$id), val)[[1]],
                                                   spec = specs[[z$id]] %||% NULL))),
  final_selection_rule = pj$final_selection_rule %||% NA_character_,
  falsification_semantics = paste("규칙 하나라도 참이면 그 처방 기각 · 판정 = 처방 변형의 보는 창 진단 패킷(diagnosis_packet.R) · R 계산 ·",
                                  "ref = base 는 같은 데이터 판본으로 다시 잰 기저(RX0)의 보는 창 패킷과 비교(RX0 측정 실패 시 처방 전 기저 패킷 · 표식)"),
  control_cell = list(code = "P2R01_RX0", role = "같은 판본 기저 대조(처방 아님 · 시행 수 무가산 · 처방 담당 실행 중 선행 측정 — 결과는 평가 전 미열람)",
                      spec = specs[["RX0"]]),
  selection_accounting = SA,
  measurement = list(runner = "02_Infrastructure/ops/rf_cell_worker.R → run_paper_replication(close_t1 · 15bps)", grade = "essence v3(권위)",
                     controls = "matched_controls.R::mc_card(전기간 · 사람 쪽) · diagnosis_packet.R(보는 창 · 리뷰어)"),
  budget = list(variants_max = 3L, rounds_this_pilot = 1L,
                r7 = "리뷰어가 '개선이 잡음 이내'로 판독하면 이 기저의 다음 라운드를 열지 않는다(파일럿 = 1회전)"))
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null"), PR, useBytes = TRUE)
file.copy(PR, file.path(P$round_dir, "prereg.json"), overwrite = TRUE)
PRMD5 <- rc_md5(PR)
cat(sprintf("[사전등록] %s (md5 %s) · 유효 처방 %d · 시행 수 %d\n", PR, PRMD5, length(ok_ids), n_family))
pr_set_status(PROGRAM, "active", reason = sprintf("S2 파일럿 라운드 %s(D7 제한적 예외 · GRADE-V3-PROMOTE ③)", ROUND), root = ROOT)
pr_record_round(PROGRAM, list(round_id = ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = PRMD5,
                              status = "registered", base = "2002.06975 B6_36(close_t1)", n_variants = length(ok_ids),
                              control = "P2R01_RX0",
                              variants = unname(vapply(specs[setdiff(names(specs), "RX0")], function(s) s$code, character(1)))), root = ROOT)
if (REGISTER_ONLY) quit(status = 0)

## ⑥ 측정 — RX0 먼저(이미 있으면 건너뜀) · 처방 칸 순차
RES <- file.path(P$round_dir, "results")
for (id in names(specs)) rc_measure_cell(ROOT, specs[[id]]$path, specs[[id]]$code, RES)
cat("[측정] 끝\n")
