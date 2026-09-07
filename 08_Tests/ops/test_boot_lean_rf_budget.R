#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_rf_budget.R — 부팅 Queue 줄의 강화 예산은 entry 에서 나온다 (2026-09-07)
#
# 실사고(2026-09-06 실측): boot_lean.sh 의 RF() 가 원장 루트 max_attempts(25)를 읽어 "20/25" 로 찍었는데 entry 는
#   B1 설계로 예산을 올린 max_attempts=30 이었다 — "칸 수는 격자·원장에서 세라" 카드의 병이 문서가 아니라 부팅 계기에서 났다.
# 판정: 배포된 RF 블록을 **패턴으로 추출**해(좌표 단정 없음) 격리 원장 픽스처에 대고 실행 — 결과값으로만 판정.
#   F1 루트 25 · entry 30 → "/30"   F2 entry 값 없음 → "/25" 폴백   F3 승격 depth 꼬리 보존   F4 active 0 → "0"   F5 둘 다 없음 → "∞"
#   M  변이(구판 mx=d.get(...) 로 되돌림) → F1 픽스처에서 "/25" — 검사가 병을 본다(양성 대조)
#   C  Queue 줄이 RF(1)·RF(2) 를 실제로 소비한다(소비자 재도출)
# boot_lean.sh 자체는 실행하지 않는다(부팅 5줄은 운영 상태를 읽는다). 운영 원장 무접촉.
#==============================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"boot_lean_rf_budget","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL)); quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")

# ── 배포 블록 추출: `def RF(l):` 부터 들여쓰기가 끝나는 줄 앞까지 (좌표 아님 · 패턴) ─────────────
L <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
i0 <- which(grepl("^def RF\\(l\\):", L))
if (length(i0) != 1L) { ng("RF 정의가 정확히 1개여야 한다", as.character(length(i0))); finish() }
j <- i0 + 1L
while (j <= length(L) && (grepl("^[[:space:]]", L[j]) || !nzchar(trimws(L[j])))) j <- j + 1L
blk <- L[i0:(j - 1L)]
ok(sprintf("RF 블록 추출 %d줄", length(blk)))

py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
run_rf <- function(block, ledger_json, layer = 1L) {
  S <- file.path(tempdir(), sprintf("boot_rf_%d_%d", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  dir.create(file.path(S, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(ledger_json), file.path(S, sprintf("06_Registry/reinforce_ledger_l%d.json", layer)), useBytes = TRUE)
  f <- file.path(S, "rf_probe.py")
  ## 부팅 스크립트의 보조 함수(P/R/S/J)는 의미가 같게 재현 — 검사 대상은 RF 블록이다
  pre <- c("import json,os,io", sprintf("P=%s", py_raw(S)), "R=lambda *a: os.path.join(P,*a)",
           "def S(f,d=None):", "    try: return f()", "    except Exception: return d",
           'J=lambda p,d=None: S(lambda: json.load(open(p if os.path.isabs(p) else R(p),encoding="utf-8-sig")),d)')
  writeLines(enc2utf8(c(pre, block, sprintf("print(RF(%d))", layer))), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE))
  unlink(S, recursive = TRUE)
  v <- out[nzchar(out)]
  if (length(v)) enc2utf8(trimws(v[length(v)])) else "ERR: no output"
}
led <- function(entry_extra = "", root_max = '"max_attempts":25,')
  sprintf('{"schema_version":"reinforce_ledger_v2","layer":1,%s"entries":[{"base_id":"RP_T_ENTRY_BUDGET","status":"active","attempts_used":20%s}]}', root_max, entry_extra)
F1 <- led(',"max_attempts":30')
F2 <- led("")
F3 <- led(',"max_attempts":30,"parent":{"base_id":"RP_T_PARENT","depth":1}')
F4 <- '{"schema_version":"reinforce_ledger_v2","layer":1,"max_attempts":25,"entries":[{"base_id":"RP_T_ENTRY_BUDGET","status":"exhausted","attempts_used":25,"max_attempts":30}]}'
F5 <- led(',"max_attempts":null', root_max = "")
chk <- function(label, got, want) if (identical(got, enc2utf8(want))) ok(sprintf("%s → %s", label, got)) else ng(label, sprintf("got %s · want %s", got, want))

cat("=== 양성 · 대조 (배포 블록) ===\n")
chk("F1 루트 25 · entry 30 → entry 예산", run_rf(blk, F1), "1(RP_T_ENTRY_BUDGET 20/30)")
chk("F2 entry 값 없음 → 루트 폴백",     run_rf(blk, F2), "1(RP_T_ENTRY_BUDGET 20/25)")
chk("F3 승격 depth 꼬리 보존",          run_rf(blk, F3), "1(RP_T_ENTRY_BUDGET 20/30 ·승격d1)")
chk("F4 active 0",                       run_rf(blk, F4), "0")
chk("F5 entry null · 루트 부재 → ∞",    run_rf(blk, F5), "1(RP_T_ENTRY_BUDGET 20/∞)")

cat("\n=== 변이 — 구판(루트 상한)으로 되돌리면 검사가 빨개지는가 ===\n")
k <- grep("mx=", blk, fixed = TRUE); k <- k[!grepl("^[[:space:]]*#", blk[k])]
if (length(k) == 1L) {
  blk_old <- blk; blk_old[k] <- sub("mx=.*$", 'mx=d.get("max_attempts")', blk_old[k])
  got <- run_rf(blk_old, F1)
  if (endsWith(got, "20/25)")) ok(sprintf("M 구판 로직은 F1 에서 %s — 검사가 병을 본다", got)) else ng("M 변이가 통과", got)
} else ng("M mx= 대입 줄이 정확히 1개여야 한다", as.character(length(k)))

cat("\n=== 소비자 재도출 ===\n")
qline <- grep("Queue:", L, fixed = TRUE, value = TRUE)
if (length(qline) >= 1L && any(grepl("RF(1)", qline, fixed = TRUE)) && any(grepl("RF(2)", qline, fixed = TRUE))) ok("C Queue 줄이 RF(1)·RF(2) 를 소비한다") else ng("C Queue 줄이 RF 를 안 쓴다")
finish()
