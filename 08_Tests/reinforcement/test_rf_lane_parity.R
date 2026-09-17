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
## ★2026-09-17 (WP-R) 소비자를 따라 옮김: 충실구현 레인은 Fable 한도 폴백 때문에 claude 를 직접 부르지 않고
##   rf_llm_env.sh::rf_llm_agent_run "$PF" 로 넘긴다(그 안에서 `< "$pf"` — stdin 은 여전히 프롬프트 파일이다).
##   리터럴 `claude -p < "$PF"` 만 세면 헬퍼 경유 레인을 argv 퇴행으로 오판한다. 헬퍼 경유는 **헬퍼 본문**이 stdin 으로
##   넘기는지(모든 호출 줄 · argv 형태 0)를 재도출하고, 아래 양성 대조가 실제 200KB 를 헬퍼로 통과시킨다.
env_src  <- rd("02_Infrastructure/ops/rf_llm_env.sh")
env_code <- sub("^\\s*#.*$", "", env_src)
i_fn <- grep("^rf_llm_agent_run\\(\\) \\{", env_code); i_end <- if (length(i_fn)) i_fn + which(grepl("^\\}", env_code[(i_fn + 1L):length(env_code)]))[1] else NA
fn_body <- if (length(i_fn) && !is.na(i_end)) paste(env_code[i_fn:i_end], collapse = "\n") else ""
n_call  <- lengths(regmatches(fn_body, gregexpr('"$bin" -p', fn_body, fixed = TRUE)))
n_stdin <- lengths(regmatches(fn_body, gregexpr('< "$pf"', fn_body, fixed = TRUE)))
helper_stdin <- nzchar(fn_body) && n_call >= 1L && n_stdin == n_call &&
  !grepl('-p "$(cat', fn_body, fixed = TRUE) && !grepl('-p "$PROMPT"', fn_body, fixed = TRUE)
if (helper_stdin) ok(sprintf("① rf_llm_agent_run — claude 호출 %d줄 전부 `< \"$pf\"`(stdin) · argv 형태 0", n_call)) else
  ng("① rf_llm_agent_run stdin", sprintf("calls=%d stdin=%d body=%d자", n_call, n_stdin, nchar(fn_body)))
for (l in lanes) {
  s <- rd(file.path("02_Infrastructure/ops", l))
  argv <- grepl('claude -p "$PROMPT"', s, fixed = TRUE) | grepl('claude -p "$(cat', s, fixed = TRUE)
  stdin <- grepl('claude -p < "$PF"', s, fixed = TRUE)
  via_helper <- any(grepl('rf_llm_agent_run "$PF"', s, fixed = TRUE)) && any(grepl("rf_llm_env.sh", s, fixed = TRUE)) && isTRUE(helper_stdin)
  if (!any(argv) && (any(stdin) || via_helper)) ok(sprintf("① %s stdin%s", l, if (!any(stdin)) " (rf_llm_agent_run 경유)" else ""))
  else ng(sprintf("① %s", l), sprintf("argv=%d stdin=%d helper=%s", sum(argv), sum(stdin), via_helper))
  if (!identical(l, "rf_fidelity_fanout.sh")) {
    if (any(grepl('printf %s "$PROMPT" > "$PF"', s, fixed = TRUE))) ok(sprintf("① %s 프롬프트 파일 기록", l)) else ng(sprintf("① %s 파일 기록 없음", l))
  }
}
## 양성 대조: stdin 으로 넘긴 긴 입력이 실제로 통과하는가 — claude 대신 wc 로 같은 셸 경로를 재현
pf <- file.path(tempdir(), "big_prompt.txt"); writeLines(strrep("x", 200000L), pf)
r <- suppressWarnings(system2("bash", c("-c", shQuote(sprintf("wc -c < %s", shQuote(gsub("\\\\", "/", pf))))), stdout = TRUE))
if (length(r) && as.integer(trimws(r[1])) >= 200000L) ok("① 200KB 입력이 stdin 으로 통과 (argv 였다면 32K 상한)") else ng("① stdin 재현 실패", paste(r, collapse = " "))
## 양성 대조 2: 같은 200KB 를 **헬퍼로** 통과시킨다 — claude 자리에 stdin 바이트를 세는 스텁(RF_CLAUDE_BIN)을 꽂는다.
##   헬퍼가 argv 로 넘기면 스텁은 0 을 센다(stdin 비어 있음) · 폴백 모델은 비워 1회 실행만.
stub <- file.path(tempdir(), sprintf("stub_claude_%d.sh", Sys.getpid())); outp <- file.path(tempdir(), sprintf("stub_out_%d.txt", Sys.getpid()))
writeLines(c("#!/usr/bin/env bash", "wc -c"), stub)
.bq <- function(p) shQuote(gsub("\\\\", "/", p))
cmd <- sprintf('. %s; LLM_MODEL=opus; LLM_EFFORT=max; LLM_FALLBACK_MODEL=""; RF_CLAUDE_BIN=%s rf_llm_agent_run %s %s 60; cat %s',
               .bq(file.path(ROOT, "02_Infrastructure/ops/rf_llm_env.sh")), .bq(stub), .bq(pf), .bq(outp), .bq(outp))
r2 <- suppressWarnings(system2("bash", c("-c", shQuote(cmd)), stdout = TRUE, stderr = TRUE))
n2 <- suppressWarnings(as.integer(trimws(utils::tail(r2, 1))))
if (length(n2) && isTRUE(n2 >= 200000L)) ok(sprintf("① 200KB 가 rf_llm_agent_run 을 거쳐 claude 자리의 stdin 으로 도착 (%d bytes)", n2)) else
  ng("① 헬퍼 stdin 양성 대조", paste(utils::tail(r2, 2), collapse = " | "))
unlink(c(stub, outp), force = TRUE)

cat("\n=== ② 승격 carry 에 overlay ===\n")
## ★2026-09-17 (WP-R) 소비자를 따라 옮김: carry 조립은 next_paper.R 인라인 list(..., overlay = ws$overlay) 가 아니라
##   정본 rf_promote.R::rf_promote_carry 다(유니버스 리셋 09-05 · 오버레이 규칙 3종 09-17 — 상한·상주 제외·적대검증 탈락).
##   리터럴 `overlay = ws$overlay` 는 어디에도 없어야 정상이다. 그래서 ①호출부가 정본을 부르고 그 결과를 원장에 싣는지
##   ②정본이 **규칙이 안 걸리면 승자 overlay 를 그대로** 싣는지(생산자 누락 재발 방지 — 원래 이 절의 목적) ③새 의미론(상주 arm 은
##   빼고 사유를 남긴다)을 실행으로 잰다. 소비자(러너 E$carry$overlay)는 그대로 대조한다.
np <- paste(sub("^\\s*#.*$", "", rd("02_Infrastructure/ops/reinforce_auto_next_paper.R")), collapse = "\n")
if (grepl("carry <- rf_promote_carry(ws, cf, best, sp", np, fixed = TRUE) && grepl("carry = carry,", np, fixed = TRUE))
  ok("② next_paper — carry 는 정본 rf_promote_carry 가 조립하고 rf_open_entry(carry = carry) 로 원장에 싣는다") else ng("② 승격 호출부 — 정본 미경유 또는 원장 미기록")
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_promote.R"), local = TRUE))
tpr <- file.path(tempdir(), sprintf("lp_promote_%d", Sys.getpid())); dir.create(file.path(tpr, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
write(toJSON(list(schema = "reinforce_program_v1", blocks = list(),
                  standing_cells = list(list(code = "B5_31", block = "B5", label = "상주", overlay_pick = "std_arm_v1"))),
             auto_unbox = TRUE, null = "null"), file.path(tpr, "06_Registry/reinforce_program.json"))
OVA <- list(kind = "dd_brake", arm_id = "dd_brake_q"); OVS <- list(kind = "std_kind", arm_id = "std_arm_v1")
wsA <- list(factors = list(list(kind = "db", id = "F1")), weighting = list(kind = "ew"), universe = list(kind = "k200_kq150"), overlay = OVA)
cA <- rf_promote_carry(wsA, wsA$factors, list(cell_code = "B5_17", grade = "B"), "spec.json", cfg = list(b5_design = list(max_layers = 3L)), root = tpr)
if (identical(cA$overlay, OVA) && is.null(cA$overlay_dropped)) ok("② rf_promote_carry — 규칙 미발화면 승자 overlay 를 **그대로** 싣는다(생산자 누락 없음)") else ng("② 정본이 overlay 를 안 싣는다")
wsS <- wsA; wsS$overlay <- list(OVA, OVS)
cS <- rf_promote_carry(wsS, wsS$factors, list(cell_code = "B5_17", grade = "B"), "spec.json", cfg = list(b5_design = list(max_layers = 3L)), root = tpr)
if (identical(cS$overlay, OVA) && length(cS$overlay_dropped) == 1L && identical(cS$overlay_dropped[[1]]$why, "standing"))
  ok("② 새 의미론 — 상주 arm 은 carry 에서 빠지고 overlay_dropped(why=standing)로 드러난다") else ng("② 상주 제외 의미론", toJSON(cS$overlay_dropped %||% list(), auto_unbox = TRUE))
unlink(tpr, recursive = TRUE, force = TRUE)
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
