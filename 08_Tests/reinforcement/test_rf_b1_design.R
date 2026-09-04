#!/usr/bin/env Rscript
#==============================================================================
# test_rf_b1_design.R — B1 블록 설계(LLM 1회)의 검증과 소비 (2026-09-04)
#
# 배경: 구판 B1 은 깊이 1~5 · 5칸 고정 · IC 상관 그리디 사슬이었다. 도훈 지시로
#   **블록 진입 시 1회** 에이전트가 그 논문 전용 조합을 설계하고 칸들이 그것을 전개한다.
#   LLM 이 무인 루프에 닿는 지점이라 안전은 **구조**가 진다:
#     ① 산출은 설계 JSON 하나 ② 팩터는 등록부 실재 id 만 ③ 칸 간 구성 중복 금지
#     ④ 기각은 조용하지 않다 — 설계를 지우고 규칙 선정으로 폴백한다.
#
# 이 검사는 그 네 가지를 **양방향**으로 잰다: 정상 설계는 통과하는가 + 위반은 실제로 잡는가.
# 부작용: 검사 전용 base_id 의 설계 파일만 쓰고 지운다(실 entry 무접촉).
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

LIB  <- file.path(ROOT, "02_Infrastructure/ops/rf_b1_design_lib.R")
DDIR <- file.path(ROOT, ".cache/rf_b1_design"); dir.create(DDIR, recursive = TRUE, showWarnings = FALSE)
BID  <- "TEST_B1_DESIGN"
DES  <- file.path(DDIR, paste0(BID, ".json"))
on.exit(unlink(c(DES, paste0(DES, ".bak")), force = TRUE), add = TRUE)

# 실재하는 팩터 id 두 개를 등록부에서 뽑는다 (검사가 자기 목록을 들고 있으면 낡는다)
pool_ids <- tryCatch({
  suppressMessages(source(file.path(ROOT, "02_Infrastructure/ops/rf_factor_arms.R"), local = TRUE))
  P <- rf_factor_pool(root = ROOT); as.character((if (is.data.frame(P)) P else P$pool)$id)
}, error = function(e) character(0))
if (length(pool_ids) < 3L) {
  cat("  SKIP 팩터 등록부를 읽을 수 없다(부트 환경) — 검증 절 생략\n")
  cat('{"test":"rf_b1_design","pass":0,"fail":0,"total":0,"skipped":1}\n'); quit(status = 0)
}
F1 <- pool_ids[1]; F2 <- pool_ids[2]; F3 <- pool_ids[3]

wr <- function(cells, extra = list()) {
  d <- c(list(schema = "rf_b1_design_v1", base_id = BID, rationale = "검사용"), extra)
  d$cells <- cells
  write(toJSON(d, auto_unbox = TRUE, null = "null"), DES)
}
verify <- function() {
  r <- suppressWarnings(system2("Rscript", c(shQuote(LIB), "verify", BID, shQuote(DES)),
                                stdout = TRUE, stderr = TRUE))
  list(rc = attr(r, "status") %||% 0L, txt = paste(r, collapse = "\n"))
}

cat("=== A. 정상 설계는 통과한다 (음성 대조) ===\n")
wr(list(list(label = "a", factors = list(F1), rationale = "r"),
        list(label = "b", factors = list(F1, F2), rationale = "r")))
v <- verify()
if (identical(as.integer(v$rc), 0L)) ok("A1 정상 설계 통과") else ng("A1 정상 설계 기각됨", substr(v$txt, 1, 160))
if (file.exists(DES)) ok("A2 통과한 설계는 남는다") else ng("A2 통과했는데 파일이 지워졌다")

cat("\n=== B. 위반 주입 — 등록부에 없는 팩터 ===\n")
wr(list(list(label = "a", factors = list(F1)),
        list(label = "b", factors = list("NO_SUCH_FACTOR_XYZ"))))
v <- verify()
if (!identical(as.integer(v$rc), 0L)) ok("B1 없는 팩터 id 기각") else ng("B1 없는 팩터가 통과했다")
if (!file.exists(DES)) ok("B2 기각된 설계는 지워진다(다음 tick 이 규칙으로 돈다)") else
  ng("B2 기각인데 설계가 남았다", "폴백이 안 된다")

cat("\n=== C. 위반 주입 — 칸 간 팩터 집합 동일 ===\n")
wr(list(list(label = "a", factors = list(F1, F2)),
        list(label = "b", factors = list(F2, F1))))
if (!identical(as.integer(verify()$rc), 0L)) ok("C1 같은 구성에 다른 이름 = 기각(칸 낭비 차단)") else
  ng("C1 중복 구성이 통과했다")

cat("\n=== D. 위반 주입 — 형식 결손 ===\n")
wr(list(list(label = "a", factors = list())))
if (!identical(as.integer(verify()$rc), 0L)) ok("D1 factors 빈 칸 기각") else ng("D1 빈 칸 통과")
wr(list(list(label = "", factors = list(F1))))
if (!identical(as.integer(verify()$rc), 0L)) ok("D2 label 없는 칸 기각") else ng("D2 label 없이 통과")
wr(list(list(label = "a", factors = list(F1, F1))))
if (!identical(as.integer(verify()$rc), 0L)) ok("D3 한 칸에 같은 팩터 두 번 기각") else ng("D3 중복 팩터 통과")

cat("\n=== E. 위반 주입 — 칸 수 상한(예산 폭주) ===\n")
MX <- tryCatch(as.integer(fromJSON(file.path(ROOT, "06_Registry/reinforce_auto_config.json"),
                                   simplifyVector = FALSE)$b1_design$max_cells), error = function(e) 15L)
wr(lapply(seq_len(MX + 1L), function(i)
  list(label = sprintf("c%d", i), factors = as.list(pool_ids[seq_len(min(i, length(pool_ids)))]))))
if (!identical(as.integer(verify()$rc), 0L)) ok(sprintf("E1 상한 %d 초과 기각", MX)) else ng("E1 상한 초과 통과")

cat("\n=== F. 소비 — 설계가 러너 셀 형태로 나오는가 ===\n")
wr(list(list(label = "깊이1", factors = list(F1), rationale = "r1"),
        list(label = "깊이3", factors = list(F1, F2, F3), rationale = "r3")))
if (identical(as.integer(verify()$rc), 0L)) {
  suppressMessages(source(LIB, local = TRUE))
  cl <- rf_b1_design_cells(BID, root = ROOT)
  if (length(cl) == 2L) ok("F1 셀 2개 생성") else ng("F1 셀 개수", as.character(length(cl)))
  if (identical(cl[[1]]$code, "B1_1") && identical(cl[[2]]$code, "B1_2"))
    ok("F2 코드 B1_1..B1_k — 뒤 블록 코드는 안 밀린다") else ng("F2 코드 규칙")
  if (identical(cl[[2]]$factors[[1]]$kind, "db") && identical(as.character(cl[[2]]$factors[[1]]$id), F1))
    ok("F3 팩터가 규칙 선정기와 같은 형태({kind:db,id})") else ng("F3 팩터 형태")
  if (length(cl[[2]]$factors) == 3L) ok("F4 칸마다 깊이가 다를 수 있다(1↔3)") else ng("F4 깊이 가변")
} else ng("F 정상 설계가 기각됐다")

cat("\n=== G. 폴백 — 설계가 없으면 NULL (러너가 규칙으로 돈다) ===\n")
unlink(DES, force = TRUE)
suppressMessages(source(LIB, local = TRUE))
if (is.null(rf_b1_design_cells(BID, root = ROOT))) ok("G1 설계 부재 → NULL") else ng("G1 설계 없는데 셀이 나온다")

cat("\n=== H. 배선 (주석 제외) ===\n")
code_of <- function(f) paste(sub("#.*$", "", readLines(file.path(ROOT, f), warn = FALSE)), collapse = "\n")
par <- code_of("02_Infrastructure/ops/reinforce_auto_parallel.R")
tik <- code_of("02_Infrastructure/ops/reinforce_auto_tick.sh")
if (grepl("rf_b1_design_cells", par, fixed = TRUE)) ok("H1 러너가 설계를 소비") else ng("H1 러너 미소비")
if (grepl('!length(.b1_design)', par, fixed = TRUE))
  ok("H2 설계가 있으면 규칙 선정기를 안 부른다(조용한 덮어쓰기 차단)") else ng("H2 이중 선정")
if (grepl("rf_b1_design.sh", tik, fixed = TRUE)) ok("H3 tick 이 설계 레인을 부른다") else ng("H3 tick 미배선")
if (grepl("b1_design", code_of("06_Registry/reinforce_auto_config.json"), fixed = TRUE))
  ok("H4 kill switch 존재") else ng("H4 kill switch 부재")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_b1_design","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
