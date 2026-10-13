## P4R01 — 처방 판독 → 검증(엔진 파서 · 규칙 형식) → 사양 컴파일 → 시행 회계 → ★사전등록(R2 · 측정 전)
## 실행: Rscript register.R
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
source(file.path(ROOT, "04_Research/programs/_lib/round_kit.R"))
PROGRAM <- "P4_ASSEMBLY"; ROUND <- "P4R01_skeleton_rx"
P <- rx_paths(PROGRAM, ROUND, ROOT); LP <- P$lane("prescriber")
PR <- file.path(P$prereg_dir, "prereg.json"); if (file.exists(PR)) stop("[P4R01] 사전등록이 이미 있다(R2)")
rl <- readLines(file.path(LP, "run.log"), warn = FALSE)
if (!any(grepl("^rc=0$", rl))) stop("[P4R01] 처방 담당 레인 실패: ", paste(rl, collapse = " | "))
po <- readLines(file.path(LP, "out.md"), warn = FALSE, encoding = "UTF-8")
.rx_assert_clean(paste(po, collapse = "\n"), ROOT, "prescriptions")
pj <- rx_parse_json(po); RX <- pj$prescriptions
if (!length(RX) || length(RX) > 3L) stop("[P4R01] 처방은 1~3건: ", length(RX))
FIELDS <- readLines(file.path(P$round_dir, "falsification_fields.txt"))
chk_rule <- function(r) {
  e <- character(0)
  if (!(as.character(r$field %||% "") %in% FIELDS)) e <- c(e, paste0("필드 밖: ", r$field %||% ""))
  if (!(as.character(r$op %||% "") %in% c("<", "<=", ">", ">="))) e <- c(e, paste0("연산자 밖: ", r$op %||% ""))
  if (is.null(r$ref)) { if (!is.numeric(r$value) || length(r$value) != 1L || !is.finite(r$value)) e <- c(e, "value 숫자 아님") }
  else if (!identical(r$ref, "base") || !is.numeric(r$delta %||% NULL)) e <- c(e, "ref 는 base · delta 숫자")
  e
}
fs <- pj$final_selection
fs_err <- c(if (!(as.character(fs$primary %||% "") %in% FIELDS)) "primary 필드 밖", if (!(as.character(fs$direction %||% "") %in% c("max", "min"))) "direction 은 max|min",
            unlist(lapply(fs$require %||% list(), chk_rule)), if (!is.numeric(fs$tie_eps %||% NULL)) "tie_eps 숫자 아님",
            if (!(as.character(fs$tie_break %||% "") %in% FIELDS)) "tie_break 필드 밖", if (!(as.character(fs$tie_direction %||% "") %in% c("max", "min"))) "tie_direction 은 max|min")
if (length(fs_err)) stop("[P4R01] 최종 선택 규칙 형식 오류 — 등록하지 않는다: ", paste(fs_err, collapse = " | "))
base_spec <- fromJSON(file.path(P$round_dir, "base", "base_cell_spec.json"), simplifyVector = FALSE)
val <- lapply(RX, function(z) { v <- rx_validate(z$implementation, ROOT); fe <- unlist(lapply(z$falsification %||% list(), chk_rule))
  if (!length(z$falsification)) fe <- c(fe, "반증 조건 없음")
  list(id = z$id, ok = isTRUE(v$ok) && !length(fe), impl_errors = v$errors, rule_errors = fe) })
for (v in val) cat(sprintf("[검증] %s — %s %s\n", v$id, if (v$ok) "통과" else "거부", paste(c(v$impl_errors, v$rule_errors), collapse = " | ")))
ok_ids <- vapply(Filter(function(v) v$ok, val), function(v) v$id, character(1))
if (!length(ok_ids)) stop("[P4R01] 유효한 처방이 없다 — 측정하지 않는다")
EP <- ma_epoch(root = ROOT)
## 시행 회계 — 골격 계보(사양의 n_family) + P2R02 장치 6 + P3R01 구성 10 + 이번 유효 처방
nb <- as.integer(base_spec$selection_accounting$n_family_at_registration %||% 0L)
nf <- as.integer(nb + 6L + 10L + length(ok_ids))
SA <- list(selection_type = "sweep", family_root = base_spec$selection_accounting$family_root,
           lineage = c(paste0("RX_", ROUND), unlist(base_spec$selection_accounting$lineage)), n_family_at_registration = nf,
           n_trials_basis = sprintf("P4R01: 골격 계보 %d(P0R01 회계) + P2R02 장치 6 + P3R01 구성 10 + 이번 유효 처방 %d", nb, length(ok_ids)))
cells <- list()
for (z in RX) { if (!(z$id %in% ok_ids)) next
  code <- paste0("P4R01_", z$id)
  impl <- z$implementation
  sp <- rx_compile_spec(base_spec, impl, code = code, label = z$name %||% z$id,
                        idea = sprintf("[P4R01 조립 · 처방 루프 · %s] %s", z$id, substr(z$mechanism %||% "", 1, 300)), selection_accounting = SA, epoch = EP, root = ROOT)
  f <- file.path(P$specs_dir, paste0(code, ".json")); dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLines(toJSON(sp, auto_unbox = TRUE, pretty = TRUE, null = "null"), f, useBytes = TRUE)
  cells[[code]] <- list(code = code, engine = "skeleton", component = z$id, path = sub(paste0("^", ROOT, "/"), "", f), md5 = rk_md5(f), n_family = nf) }
BCP <- file.path(P$round_dir, "behavior_card_cfg_at_prereg.json"); file.copy(file.path(ROOT, "06_Registry/behavior_card.json"), BCP, overwrite = TRUE)
sk <- readLines(file.path(P$round_dir, "skeleton.txt"))
pre <- list(schema = "rx_prereg_v1", program = PROGRAM, round_id = ROUND, registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            purpose = "P4 조립 · 처방 루프 1라운드 — P0 골격의 빈칸을 처방 루프가 채운다(등록부 P4_ASSEMBLY)",
            skeleton = as.list(setNames(sub("^.*=", "", sk), sub("=.*$", "", sk))), tau_d = "2022-12-31", measurement_axis = list(epoch = EP$id),
            base = list(code = sub("^skeleton=", "", sk[1]), source = "P0R01_feasibility_map 측정(같은 데이터 판본) — RX0 재측정 불필요",
                        packet_md5 = rk_md5(file.path(P$round_dir, "base", "diagnosis_packet.json")), spec_md5 = rk_md5(file.path(P$round_dir, "base", "base_cell_spec.json"))),
            agents = list(analyst = list(md5 = rk_md5(file.path(P$lane("analyst"), "out.md"))), prescriber = list(md5 = rk_md5(file.path(LP, "out.md"))),
                          lane = "programs/rx_lane.sh — 청정(자동 기억 차단 · R6 읽기 가드) · opus · 읽기 전용"),
            prescriptions = lapply(RX, function(z) c(z, list(validation = Filter(function(v) identical(v$id, z$id), val)[[1]]))),
            cells = unname(cells), final_selection = fs,
            falsification_semantics = "규칙 하나라도 참이면 그 처방 기각 · 판정 = 처방 변형의 보는 창 진단 패킷 · ref = base 는 골격 칸의 보는 창 패킷",
            selection_accounting = SA, behavior_card_cfg = list(path = sub(paste0("^", ROOT, "/"), "", BCP), md5 = rk_md5(BCP)),
            budget = list(variants_max = 3L, rounds = 1L, r7 = "리뷰어가 '개선이 잡음 이내'로 판독하면 다음 라운드를 열지 않는다"))
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
file.copy(PR, file.path(P$round_dir, "prereg.json"), overwrite = TRUE)
pr_set_status(PROGRAM, "active", reason = sprintf("라운드 %s 사전등록(처방 %d건)", ROUND, length(cells)), root = ROOT)
pr_record_round(PROGRAM, list(round_id = ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = rk_md5(PR), status = "registered",
                              n_variants = length(cells), variants = unname(vapply(cells, function(z) z$code, character(1)))), root = ROOT)
cat(sprintf("[P4R01] 사전등록 %s (md5 %s) · 처방 %d · 시행 수 %d\n", PR, rk_md5(PR), length(cells), nf))
