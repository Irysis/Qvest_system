## B1 설계 재료가 승계를 알려주는가 — 승격·결합 entry 를 충실구현 entry 와 같은 구조로 (2026-09-05)
## 도훈 "구조 똑같이 맞춰줘". 실사고: 승격 entry 의 실제 기저는 논문 신호 + carry(팩터 3종·비중 cvar·유니버스)인데
##   재료는 "기저 = 논문 신호" 만 말했다. 설계자가 이미 켜진 팩터를 다시 고르면 dedup 후 승계와 같아져
##   **처치 미전달로 미측정 종결** — 칸만 탄다. 그리고 칸 수 = 예산(25 + n − 5) 관계도 안 알려줬다.
suppressMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

## 격리 root — QVEST_RF_ROOT 는 이 라이브러리 전용 격리 변수다(QM_ROOT 는 ~/.Renviron 에 져서 못 쓴다)
TMP <- file.path(tempdir(), sprintf("b1carry_%d", Sys.getpid()))
dir.create(file.path(TMP, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TMP, ".cache"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(TMP, "stage_artifacts/l_code/reinforcement"), recursive = TRUE, showWarnings = FALSE)
## 팩터 등록부·라이브러리는 실 root 것을 그대로 읽게 둔다(재구현 금지) — 코드 경로만 복사
for (d in c("02_Infrastructure/ops", "02_Infrastructure/reinforcement")) {
  dir.create(file.path(TMP, d), recursive = TRUE, showWarnings = FALSE)
}
mk_entry <- function(carry = NULL, parent = NULL) {
  e <- list(base_id = "TEST_CARRY", status = "active", base_grade = "B",
            paper_key = "1403.8125", base_artifacts = "", engine_path = "engine.R",
            attempts = list())
  if (!is.null(carry)) e$carry <- carry
  if (!is.null(parent)) e$parent <- parent
  write(toJSON(list(schema_version = "reinforce_ledger_v2", layer = 1L, max_attempts = 25L,
                    entries = list(e)), auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file.path(TMP, "06_Registry/reinforce_ledger_l1.json"))
}
build <- function() {
  out <- file.path(TMP, "mat.txt")
  ## ★Windows 에서 system2(env=) 는 무시된다(2026-08-30 실측) — 부모 환경에 심어 자식이 상속하게 한다
  .old <- Sys.getenv("QVEST_RF_ROOT", unset = NA_character_)
  Sys.setenv(QVEST_RF_ROOT = TMP, QVEST_RP_JLOG = file.path(TMP, ".cache/j.jsonl"))
  on.exit({ if (is.na(.old)) Sys.unsetenv("QVEST_RF_ROOT") else Sys.setenv(QVEST_RF_ROOT = .old) }, add = TRUE)
  r <- suppressWarnings(system2("Rscript",
        c(shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R")), "materials", "TEST_CARRY", shQuote(out)),
        stdout = TRUE, stderr = TRUE))
  if (!file.exists(out)) return(list(ok = FALSE, txt = paste(r, collapse = "\n")))
  list(ok = TRUE, txt = paste(readLines(out, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
}

cat("=== A. 승격 entry — 승계 절이 나온다 ===\n")
mk_entry(carry = list(factors = list(list(kind = "db", id = "S01_Size"), list(kind = "db", id = "V14_EBIT_EV"),
                                     list(kind = "db", id = "L27_Price_Level")),
                      weighting = list(kind = "catalog", catalog_id = "lean:cvar", label = "cvar"),
                      universe = list(kind = "k200_kq150"), overlay = NULL),
         parent = list(base_id = "PARENT_ID", depth = 2L, cell = "B1_2", best_port_t = 2.171))
r <- build()
if (!isTRUE(r$ok)) {
  ng("A 재료 생성 실패 (격리 root)", substr(r$txt, 1, 160))
} else {
  t <- r$txt
  for (needle in c("이 entry 는 승격이다", "S01_Size", "V14_EBIT_EV", "L27_Price_Level", "cvar",
                   "PARENT_ID", "B1_2", "2.171"))
    if (grepl(needle, t, fixed = TRUE)) ok(sprintf("A 승계 절에 `%s`", needle)) else ng(sprintf("A `%s` 누락", needle))
  if (grepl("미측정 종결", t, fixed = TRUE)) ok("A 중복 선택의 대가를 명시(미측정 종결)") else ng("A 중복 경고 없음")
  if (grepl("leave-one-out", t, fixed = TRUE)) ok("A 승계를 빼는 실험은 B4 소관임을 명시") else ng("A B4 안내 없음")
  ## 승계 절이 등록부 절보다 앞에 와야 읽힌다
  i1 <- regexpr("이 entry 는 승격이다", t, fixed = TRUE); i2 <- regexpr("후보 팩터 등록부", t, fixed = TRUE)
  if (i1 > 0 && i2 > 0 && i1 < i2) ok("A 승계 절이 등록부 앞에 온다") else ng("A 절 순서")
}

cat("\n=== B. 비승격(충실구현) entry — 승계 절이 없다 (양성 대조) ===\n")
mk_entry(carry = NULL, parent = NULL)
r2 <- build()
if (!isTRUE(r2$ok)) {
  ng("B 재료 생성 실패", substr(r2$txt, 1, 160))
} else {
  if (!grepl("이 entry 는 승격이다", r2$txt, fixed = TRUE)) ok("B 승계 절 없음 — 구판과 같은 구조") else ng("B 비승격에 승계 절이 붙었다")
  if (grepl("기저 (이 위에 팩터를 얹는다)", r2$txt, fixed = TRUE)) ok("B 기저 절은 그대로") else ng("B 기저 절 소실")
}
unlink(TMP, recursive = TRUE, force = TRUE)

cat("\n=== C. 프롬프트 — 예산 규칙과 승계 규칙이 있는가 ===\n")
sh <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_b1_design.sh"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("총예산 = 25 + max(0, 칸수 − 5)", sh, fixed = TRUE)) ok("C 칸 수 → 예산 관계 명시") else ng("C 예산 규칙 없음")
if (grepl("뒤 블록이 잘리지 않는다", sh, fixed = TRUE)) ok("C 넓혀도 뒤 블록이 안 잘린다는 사실 명시") else ng("C 뒤 블록 설명 없음")
if (grepl("승계 절이 있으면", sh, fixed = TRUE) && grepl("미측정으로 닫힌다", sh, fixed = TRUE)) ok("C 승계 중복의 대가 명시") else ng("C 승계 규칙 없음")

cat("\n=== D. 예산 식이 코드와 문서에서 같은가 (재도출) ===\n")
## ★2026-09-17 (WP-R) 소비자를 따라 옮김: 러너 예산은 인라인 `max(0L, length(.b1_design) - 5L)` 이 아니라 매 tick
##   정본 rf_runner_gates.R::rf_budget_auto 로 재도출된다(B1 초과 + B5 설계 초과 + 상주 + 재설계 추가 — B1 몫은 그대로).
##   그래서 ①러너가 B1 설계 칸 수와 격자 B1 슬롯을 정본 함수에 넘기는지 ②정본 함수의 B1 몫이 프롬프트 문구
##   "총예산 = 25 + max(0, 칸수 − 5)" 와 같은지(n=0..15 실행 대조) ③문구의 5 가 격자 blocks[B1].n 인지 잰다.
pr <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE, encoding = "UTF-8")), collapse = "\n")
suppressMessages(invisible(capture.output(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_runner_gates.R"), local = TRUE))))
.prog <- fromJSON(file.path(ROOT, "06_Registry/reinforce_program.json"), simplifyVector = FALSE)
.b1n <- { v <- NA_integer_; for (b in .prog$blocks) if (identical(b$id, "B1")) v <- as.integer(b$n %||% length(b$cells)); v }
.same <- all(vapply(0:15, function(n) rf_budget_auto(25L, n, 0L, 0L, 0L, slot_b1 = .b1n) == 25L + max(0L, n - 5L), logical(1)))
if (grepl(".nB1d <- length(.b1_design)", pr, fixed = TRUE) && grepl("rf_budget_auto(led$max_attempts %||% 25L, .nB1d,", pr, fixed = TRUE) &&
    grepl('slot_b1 = .slot_of("B1")', pr, fixed = TRUE) && identical(.b1n, 5L) && isTRUE(.same))
  ok("D 러너 예산 B1 몫 = rf_budget_auto(25, n, …, slot_b1 = 격자 B1 5칸) = 25 + max(0, n−5) — 프롬프트 문구와 실행 대조 일치(n=0..15)") else
  ng("D 러너 예산식이 바뀌었다 — 프롬프트 문구도 함께 고칠 것", sprintf("slot_b1=%s same=%s", .b1n, .same))
sk <- paste(readLines(file.path(ROOT, ".claude/skills/reinforce/SKILL.md"), warn = FALSE, encoding = "UTF-8"), collapse = "\n")
if (grepl("25 + max(0, B1 설계 칸수 − 5)", sk, fixed = TRUE)) ok("D SKILL 에 같은 식") else ng("D SKILL 미기재")

cat(sprintf("\n== test_rf_b1_carry_aware: %d pass · %d fail ==\n", P, F))
cat(sprintf('{"test":"rf_b1_carry_aware","pass":%d,"fail":%d,"total":%d}\n', P, F, P + F))
if (F > 0L) quit(status = 1L)
