## 승격·결합 레인이 충실구현 후 강화와 같은 경로를 타는가 — 오늘 드러난 네 이음매 (2026-09-04)
##  ① 여섯 LLM 레인이 프롬프트를 stdin 으로 넘긴다 (승격 B1 설계 재료 41KB → argv 상한 → 에이전트 미기동 2회)
##  ② 승격 carry 가 overlay 를 싣는다 (생산자 누락 — 소비자만 읽고 있었다)
##  ③ B1 설계 재료의 앞선 교훈 절에 상한이 있다 (기전 700자 · 처방 3)
##  ④ 기전이 빈 블록을 백필한다 (rf_mech_backfill_targets 순수 함수 + 러너 배선 + 병합기 시도 기록)
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
rd <- function(f) readLines(file.path(ROOT, f), warn = FALSE, encoding = "UTF-8")

cat("=== ① 프롬프트 전달 — argv 금지 · stdin 필수 (재도출) ===\n")
lanes <- c("rf_b1_design.sh", "rf_lcode_mechanism.sh", "rf_replication_auto.sh",
           "rf_fidelity_audit.sh", "rf_overlay_propose.sh", "rf_fidelity_fanout.sh")
for (l in lanes) {
  s <- rd(file.path("02_Infrastructure/ops", l))
  argv <- grepl('claude -p "$PROMPT"', s, fixed = TRUE) | grepl('claude -p "$(cat', s, fixed = TRUE)
  stdin <- grepl('claude -p < "$PF"', s, fixed = TRUE)
  if (!any(argv) && any(stdin)) ok(sprintf("① %s stdin", l)) else ng(sprintf("① %s", l), sprintf("argv=%d stdin=%d", sum(argv), sum(stdin)))
  if (!identical(l, "rf_fidelity_fanout.sh")) {
    if (any(grepl('printf %s "$PROMPT" > "$PF"', s, fixed = TRUE))) ok(sprintf("① %s 프롬프트 파일 기록", l)) else ng(sprintf("① %s 파일 기록 없음", l))
  }
}
## 양성 대조: stdin 으로 넘긴 긴 입력이 실제로 통과하는가 — claude 대신 wc 로 같은 셸 경로를 재현
pf <- file.path(tempdir(), "big_prompt.txt"); writeLines(strrep("x", 200000L), pf)
r <- suppressWarnings(system2("bash", c("-c", shQuote(sprintf("wc -c < %s", shQuote(gsub("\\\\", "/", pf))))), stdout = TRUE))
if (length(r) && as.integer(trimws(r[1])) >= 200000L) ok("① 200KB 입력이 stdin 으로 통과 (argv 였다면 32K 상한)") else ng("① stdin 재현 실패", paste(r, collapse = " "))

cat("\n=== ② 승격 carry 에 overlay ===\n")
np <- paste(rd("02_Infrastructure/ops/reinforce_auto_next_paper.R"), collapse = "\n")
if (grepl("overlay = ws$overlay", np, fixed = TRUE)) ok("② carry <- list(..., overlay = ws$overlay)") else ng("② carry 에 overlay 없음")
pr <- paste(rd("02_Infrastructure/ops/reinforce_auto_parallel.R"), collapse = "\n")
if (grepl("E$carry$overlay", pr, fixed = TRUE)) ok("② 러너가 E$carry$overlay 를 읽는다 (생산자·소비자 짝)") else ng("② 소비자 없음")

cat("\n=== ③ B1 설계 재료 상한 ===\n")
b1 <- paste(rd("02_Infrastructure/ops/rf_b1_design_lib.R"), collapse = "\n")
if (grepl("nchar(.mx) > 700L", b1, fixed = TRUE) && grepl("utils::head(.t, 3L)", b1, fixed = TRUE)) ok("③ 기전 700자 · 처방 3건 상한") else ng("③ 상한 없음")

cat("\n=== ④ 기전 백필 — 순수 함수 ===\n")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_mech_backfill.R"), local = TRUE))
tmp <- file.path(tempdir(), sprintf("bf_%d", Sys.getpid()))
dir.create(file.path(tmp, "stage_artifacts/l_code/reinforcement"), recursive = TRUE, showWarnings = FALSE)
wr <- function(b, mech = "", tries = NULL) {
  d <- list(l_code = paste0("RF-", b), mechanism = mech)
  if (!is.null(tries)) d$mechanism_tries <- tries
  write(toJSON(d, auto_unbox = TRUE, null = "null"), file.path(tmp, "stage_artifacts/l_code/reinforcement", sprintf("l_code_TESTBF_%s.json", b)))
}
wr("B1", "실측: B1_2 …")          # 기전 있음 → 대상 아님
wr("B5", "")                      # 비어 있음 → 대상
wr("B2", "", tries = 2L)          # 비었지만 2회 시도 → 상한
wr("B3", "", tries = 1L)          # 1회 시도 → 대상
tg <- rf_mech_backfill_targets("TESTBF", tmp)
if (setequal(tg, c("B5", "B3"))) ok("④ 대상 = 기전 비고 시도 < 2 (B5·B3)") else ng("④ 대상 산출", paste(tg, collapse = ","))
if (!("B5" %in% rf_mech_backfill_targets("TESTBF", tmp, exclude_block = "B5"))) ok("④ 진행 중 블록 제외") else ng("④ exclude 무시")
rf_mech_note_try("TESTBF", "B5", tmp); rf_mech_note_try("TESTBF", "B5", tmp)
if (!("B5" %in% rf_mech_backfill_targets("TESTBF", tmp))) ok("④ 시도 2회 기록 후 대상에서 빠진다 (무한 재시도 없음)") else ng("④ 시도 기록 무효")
if (!length(rf_mech_backfill_targets("NOPE", tmp))) ok("④ L-code 없는 entry → 빈 벡터") else ng("④ 없는 entry")
unlink(tmp, recursive = TRUE, force = TRUE)

cat("\n=== ④ 배선 — 러너·병합기 ===\n")
if (grepl("rf_mech_backfill_targets(BID, ROOT)", pr, fixed = TRUE) && grepl('jlog("mechanism_backfill"', pr, fixed = TRUE)) ok("④ 러너가 tick 초입에 백필을 부른다") else ng("④ 러너 배선 없음")
i_bf <- grep("rf_mech_backfill_targets(BID, ROOT)", rd("02_Infrastructure/ops/reinforce_auto_parallel.R"), fixed = TRUE)
i_en <- grep("isTRUE(CFG$enabled) && isTRUE((CFG$lcode_mechanism %||% list())$enabled)", rd("02_Infrastructure/ops/reinforce_auto_parallel.R"), fixed = TRUE)
if (length(i_en) && length(i_bf) && min(i_en) < min(i_bf)) ok("④ 킬스위치·레인 스위치가 꺼져 있으면 안 부른다") else ng("④ 스위치 가드 없음")
lib <- paste(rd("02_Infrastructure/ops/rf_lcode_mechanism_lib.R"), collapse = "\n")
if (grepl("rf_mech_note_try(base_id, block_id, ROOT)", lib, fixed = TRUE)) ok("④ 병합기 기각 시 시도 횟수 기록") else ng("④ 병합기 기록 없음")

cat("\n=== ⑤ 텔레그램 dry-run 스위치 (미리보기가 실제 3건을 쏜 사고) ===\n")
tn <- paste(rd("02_Infrastructure/telegram/telegram_notify.R"), collapse = "\n")
if (grepl('dry_run = identical(Sys.getenv("QVEST_TG_DRY_RUN", ""), "1")', tn, fixed = TRUE)) ok("⑤ QVEST_TG_DRY_RUN=1 이 기본 dry_run") else ng("⑤ env 스위치 없음")
hk <- paste(rd("08_Tests/hooks/run_all_hooks.sh"), collapse = "\n")
if (grepl("export QVEST_TG_DRY_RUN=", hk, fixed = TRUE)) ok("⑤ 배터리가 dry-run 을 켠다") else ng("⑤ 배터리 미설정")

cat(sprintf("\n== test_rf_lane_parity: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_lane_parity","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
