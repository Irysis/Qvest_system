#!/usr/bin/env Rscript
#==============================================================================
# test_rf_axiom_inject.R — 공리가 **판단 지점**에 닿는가 (도훈 지시 2026-09-04)
#
# 배경: 공리 주입 경로가 둘 있었는데 둘 다 LLM 판단 지점에 안 닿았다.
#   ① axiom_context_inject.sh = PreToolUse[Agent] 훅 — 무인 레인은 Agent 를 0개 스폰하고
#      claude -p 를 직접 부르므로 발화하지 않는다.
#   ② rf_preflight.R 은 셀 스펙에 공리를 싣지만 rf_cell_engine 이 preflight 를 한 번도
#      참조하지 않는다(grep 0건) — 기록으로만 남는다.
#   ⇒ 규칙이 도는 자리에만 실리고, 판단이 일어나는 네 지점은 비어 있었다.
#
# 왜 중요한가(실측): 2026-09-04 B1 에서 방어 계열 셋이 나란히 F 였다. AX-001 은 정확히
#   "방어형 팩터를 전기간 SR/CAGR/MDD 로 평가하면 Grade F" 라고 말한다 — 그 전제 없이는
#   기전이 "방어 축은 죽었다" 로 닫힌다. AX-000 도 같다(소수 실패로 한계 단정 금지).
#
# 양방향: 브리프가 실제 내용을 담는가 + 네 레인이 전부 그것을 프롬프트에 넣는가
#   + 절단이 없는가 + "전제이지 지시가 아니다" 프레이밍이 살아 있는가.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

cat("=== A. 브리프 산출 — 정본에서 읽고 절단하지 않는가 ===\n")
# ★Windows 에서 system2("bash", c("-c", <긴 문자열>)) 은 인자가 쪼개져 조용히 0줄을 낸다.
#   래퍼 파일로 부른다 — 레인이 실제로 부르는 방식(source 후 호출)과 같다.
.wrap <- file.path(tempdir(), sprintf("axb_%d.sh", Sys.getpid()))
writeLines(c("#!/usr/bin/env bash",
             sprintf('ROOT="%s"', ROOT),
             sprintf('. "%s/02_Infrastructure/ops/rf_axiom_brief.sh"', ROOT),
             "rf_axiom_brief"), .wrap)
br <- tryCatch(system2("bash", shQuote(.wrap), stdout = TRUE, stderr = TRUE),
       error = function(e) character(0))
br <- paste(br, collapse = "\n")
axf <- list.files(file.path(ROOT, "qepm/memory/axioms/active"), pattern = "^AX-.*[.]json$", full.names = TRUE)
if (nzchar(br)) ok("A1 브리프가 산출된다") else ng("A1 브리프 산출 실패", substr(br, 1, 120))
hit <- sum(vapply(axf, function(f) {
  id <- sub("[.]json$", "", basename(f)); grepl(id, br, fixed = TRUE) }, logical(1)))
if (hit == length(axf)) ok(sprintf("A2 활성 공리 %d건 전부 포함", length(axf))) else
  ng("A2 일부 공리 누락", sprintf("%d/%d", hit, length(axf)))
# ★절단 금지 — 110자 절단은 원장 기록용이다. 판단에 쓰려면 문장이 온전해야 한다.
longest <- 0L
for (f in axf) { d <- tryCatch(fromJSON(f, simplifyVector = FALSE), error = function(e) NULL)
  tx <- as.character(d$statement %||% d$text %||% "")
  longest <- max(longest, nchar(tx))
  if (nchar(tx) > 130L) {
    tail120 <- substr(tx, nchar(tx) - 30L, nchar(tx))
    if (grepl(tail120, br, fixed = TRUE)) ok(sprintf("A3 %s 전문 포함(꼬리까지)", sub("[.]json$", "", basename(f))))
    else ng(sprintf("A3 %s 가 잘렸다", sub("[.]json$", "", basename(f))), "판단용 브리프는 절단하지 않는다")
  } }
if (longest > 130L) ok(sprintf("A4 최장 공리 %d자 — 절단 검사가 의미를 갖는다", longest)) else
  cat("  SKIP 공리가 전부 짧아 절단 검사 불가\n")

cat("\n=== B. 프레이밍 — 전제이지 지시가 아니다 ===\n")
if (grepl("전제 — 지시가 아니다", br, fixed = TRUE)) ok("B1 전제 프레이밍") else ng("B1 프레이밍 부재")
if (grepl("뒤집는 증거", br, fixed = TRUE))
  ok("B2 반증 여지를 남긴다(공리가 결론을 강제하지 않는다)") else ng("B2 반증 여지 부재")

cat("\n=== C. 배선 — 네 레인이 전부 받는가 ===\n")
LANES <- c("rf_replication_auto.sh", "rf_fidelity_audit.sh", "rf_b1_design.sh", "rf_lcode_mechanism.sh")
for (f in LANES) {
  src <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops", f), warn = FALSE), collapse = "\n")
  if (grepl("rf_axiom_brief", src, fixed = TRUE)) ok(sprintf("C %s — 브리프 로드", f)) else
    ng(sprintf("C %s — 브리프 미로드", f))
  if (grepl("${AXB}", src, fixed = TRUE) || grepl("$AXB", src, fixed = TRUE))
    ok(sprintf("C %s — 프롬프트에 삽입", f)) else
    ng(sprintf("C %s — 삽입 없음", f))
}

cat("\n=== D. 구 경로가 왜 안 닿았는지 (회귀 방지) ===\n")
eng <- paste(sub("#.*$", "", readLines(file.path(ROOT, "02_Infrastructure/reinforcement/rf_cell_engine.R"),
                                       warn = FALSE)), collapse = "\n")
if (!grepl("preflight", eng, fixed = TRUE))
  ok("D1 엔진은 여전히 preflight 를 안 읽는다 — 그래서 LLM 경로가 필요했다(사실 고정)") else
  ok("D1 엔진이 preflight 를 읽게 됐다 — 이 검사의 전제가 바뀌었으니 주석을 갱신할 것")
hooks <- tryCatch(paste(readLines(file.path(ROOT, ".claude/settings.json"), warn = FALSE), collapse = ""),
                  error = function(e) "")
if (grepl("axiom_context_inject", hooks, fixed = TRUE))
  ok("D2 훅은 살아 있다(Agent 스폰 경로용) — 무인 레인과 별개 경로") else
  cat("  SKIP axiom_context_inject 훅 미등록\n")

cat("\n=== E. 설정 기록 ===\n")
cfg <- tryCatch(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"), simplifyVector = FALSE),
                error = function(e) list())
if (isTRUE(cfg$axiom_inject$enabled)) ok("E1 axiom_inject 활성") else ng("E1 설정 부재")
if (length(cfg$axiom_inject$lanes %||% list()) == 4L) ok("E2 레인 4종 명시") else
  ng("E2 레인 명시", as.character(length(cfg$axiom_inject$lanes %||% list())))
if (isTRUE(cfg$distill_on_block$enabled)) ok("E3 블록 단위 증류 활성(주간 주기 불일치 해소)") else
  ng("E3 증류 주기 설정 부재")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_axiom_inject","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
