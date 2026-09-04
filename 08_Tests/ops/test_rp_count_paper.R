## count_paper 전달 — 비결합 요청은 새 논문이다 (2026-09-04)
## 실사고: C_COUNT 가 combo 블록의 count_paper 만 봐서 비결합 요청 전부 0 → 결합 검토 카운터 정지 ·
##   큐 미러 영구 침묵 · alpha-pending 과대. 배포된 줄을 그대로 뽑아(재도출) 픽스처 4종으로 돌린다.
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
SH <- readLines(file.path(ROOT, "02_Infrastructure/ops/rf_replication_auto.sh"), warn = FALSE, encoding = "UTF-8")
i0 <- which(startsWith(SH, "_cp = d.get('count_paper')")); i1 <- which(startsWith(SH, "print('C_COUNT="))
if (length(i0) != 1L || length(i1) < 1L || min(i1) <= i0) { ng("배포 줄 추출 실패"); cat(sprintf("\n== test_rp_count_paper: %d pass · %d fail ==\n", P, F)); quit(status = 1L) }
block <- SH[i0:min(i1)]
## 마지막 줄은 bash 의 $( ... -c "...") 닫는 따옴표를 달고 있다 — 파이썬이 아니라 떼어낸다
bl <- block[length(block)]; if (endsWith(bl, '")"')) block[length(block)] <- substr(bl, 1, nchar(bl) - 3L)
if (length(i1) == 1L) ok("C_COUNT 출력 줄이 하나 (중복 print 제거됨)") else ng("C_COUNT 출력 줄 중복", paste(i1, collapse = ","))
harness <- function(fixture_json, lines) {
  f <- file.path(tempdir(), sprintf("cc_%d.py", Sys.getpid()))
  writeLines(c("import json,sys", "q=lambda v: str(v)", sprintf("d=json.loads(%s)", shQuote(fixture_json)),
               "c=d.get('combo') or {}", lines), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE)); unlink(f, force = TRUE)
  v <- sub("^C_COUNT=", "", grep("^C_COUNT=", out, value = TRUE))
  if (length(v)) v[1] else paste("ERR:", paste(out, collapse = " "))
}
cat("=== A. 픽스처 4종 (현행 줄) ===\n")
cases <- list(
  list(nm = "비결합 · 키 없음 → 센다",            j = '{"paper":{"url":"u","paper_key":"1403.8125"},"status":"pending"}', want = "1"),
  list(nm = "결합 · combo.count_paper 없음 → 안 센다", j = '{"paper":{"url":"u"},"combo":{"setkey":"a+b"}}',                 want = "0"),
  list(nm = "결합 · combo.count_paper=true → 센다", j = '{"paper":{"url":"u"},"combo":{"setkey":"a+b","count_paper":true}}', want = "1"),
  list(nm = "최상위 count_paper=false → 안 센다",  j = '{"paper":{"url":"u"},"count_paper":false}',                        want = "0"))
for (cs in cases) { got <- harness(cs$j, block)
  if (identical(got, cs$want)) ok(sprintf("A %s (%s)", cs$nm, got)) else ng(sprintf("A %s", cs$nm), sprintf("got %s want %s", got, cs$want)) }
cat("\n=== B. 위반 주입 — 구판 줄은 비결합을 0 으로 만든다 ===\n")
old_line <- "print('C_COUNT=%s'  % q('1' if c.get('count_paper') else '0'))"
got <- harness(cases[[1]]$j, old_line)
if (identical(got, "0")) ok("B 구판 로직은 비결합 요청을 0 으로 (검사가 병을 본다)") else ng("B 구판 재현 실패", got)
cat(sprintf("\n== test_rp_count_paper: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
