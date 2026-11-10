#!/usr/bin/env Rscript
#==============================================================================
# test_boot_lean_lane_tick.R — 부팅 줄의 레인 틱 나이 · 컨텍스트 게이지 (2026-11-10 전수점검)
#
# 대상: 02_Infrastructure/ops/boot_lean.sh::LANE_TICK · CTX
#   LANE_TICK — 충실구현 레인 디스패처가 멈추면 슬롯 상태 파일은 마지막 값 그대로 남는다. 11-07~11-10 레인이 71시간 멈춘 동안 부팅은
#     '레인 슬롯 0/3' 만 보였다. 틱 시각이 감시 정의의 문턱(replication_lane/lane_alive.max_age_h)보다 오래되면 '★틱 N 전(레인 정지?)'.
#   CTX — 세션 전사 폴더 이름을 부팅의 정본 경로로 만들던 탓에, 여는 경로가 다른 기계에서 게이지가 늘 '?' 였다.
# 판정: 배포된 블록을 **패턴으로 추출**해 픽스처 루트에 대고 python 실행 — 결과값으로만.
#   T1 신선 → 꼬리 없음 · T2 71시간 → '★틱 71h 전' · T3 100시간 → '4d' · T4 at 없음 → 파일 mtime 대체 · T5 문턱 정의 부재 → '틱 ?'
#   T6 경계(문턱 ± 0.5h) · M1/M2 위반 주입(블록 사본) · C 소비 배선 · X1~X3 게이지 · M3 수리 전 한 줄로 되돌리면 못 찾는다
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PY <- Sys.getenv("QVEST_PY_BIN", Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe")))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
chk <- function(cond, m, why = "") if (isTRUE(cond)) ok(m) else ng(m, why)
finish <- function() { cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"boot_lean_lane_tick","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL == 0L) 0L else 1L) }
Sys.setenv(PYTHONUTF8 = "1", PYTHONIOENCODING = "utf-8")

cat("=== 블록 추출 ===\n")
BL <- readLines(file.path(ROOT, "02_Infrastructure/ops/boot_lean.sh"), encoding = "UTF-8", warn = FALSE)
grab_def <- function(name) {
  i0 <- which(grepl(sprintf("^def %s\\(", name), BL))
  if (length(i0) != 1L) return(NULL)
  j <- i0 + 1L
  while (j <= length(BL) && grepl("^[[:space:]]", BL[j])) j <- j + 1L
  BL[i0:(j - 1L)]
}
one <- function(pat) { i <- which(grepl(pat, BL)); if (length(i) == 1L) BL[i] else NULL }
b_tick <- grab_def("LANE_TICK"); b_ctx <- grab_def("CTX"); b_S <- grab_def("S")
l_R <- one("^R=lambda "); l_J <- one("^J=lambda "); l_HH <- one("^HH=lambda ")
if (is.null(b_tick) || is.null(b_ctx) || is.null(b_S) || is.null(l_R) || is.null(l_J) || is.null(l_HH)) {
  ng("LANE_TICK · CTX · S · R · J · HH 정의가 각각 정확히 1개여야 한다"); finish()
}
ok(sprintf("블록 추출 — LANE_TICK %d줄 · CTX %d줄 · 공용 도우미 4종(부팅 스크립트 그대로)", length(b_tick), length(b_ctx)))

py_raw <- function(s) sprintf("r'%s'", gsub("'", "", s))
run_py <- function(root, body) {
  f <- file.path(tempdir(), sprintf("boot_tick_probe_%d_%d.py", Sys.getpid(), as.integer(runif(1, 1, 1e6))))
  pre <- c("import json,os,re,glob,time,io,datetime as dt", sprintf("P=%s", py_raw(root)), l_R, b_S, l_J, l_HH)
  writeLines(enc2utf8(c(pre, body)), f, useBytes = TRUE)
  out <- suppressWarnings(system2(PY, shQuote(f), stdout = TRUE, stderr = TRUE)); unlink(f)
  v <- out[nzchar(out)]; if (length(v)) enc2utf8(v[length(v)]) else "ERR: no output"
}
mk_root <- function(tag, with_reg = TRUE, max_age = 8) {
  d <- file.path(tempdir(), sprintf("boottick_%s_%d", tag, Sys.getpid()))
  unlink(d, recursive = TRUE); dir.create(file.path(d, "06_Registry", "replication_slots"), recursive = TRUE)
  if (with_reg) writeLines(sprintf('{"components":[{"id":"other","rules":[{"id":"lane_alive","max_age_h":999}]},{"id":"replication_lane","rules":[{"id":"lane_errors","kind":"log_patterns"},{"id":"lane_alive","kind":"freshness","max_age_h":%s}]}]}', max_age),
                           file.path(d, "06_Registry", "superfan_components.json"))
  writeLines('{"slots":[{},{},{}]}', file.path(d, "06_Registry", "replication_slots", "_status.json"))
  gsub("\\\\", "/", d)
}
# 기준 시각을 고정해 넘긴다(now) — at 은 그 기준에서 h 시간 전
NOW <- "1794268800"                                  # 2026-11-10 12:00 KST 근처의 고정 epoch(값 자체는 의미 없음)
tick <- function(root, h, block = b_tick, with_at = TRUE) {
  at <- if (with_at) sprintf('{"at": dt.datetime.fromtimestamp(%s-%s*3600, dt.timezone(dt.timedelta(hours=9))).strftime("%%Y-%%m-%%dT%%H:%%M:%%S%%z")}', NOW, h) else "{}"
  run_py(root, c(block, sprintf('print("[" + S(lambda: LANE_TICK(%s, now=%s), "EXC") + "]")', at, NOW)))
}

cat("\n=== T 레인 틱 나이 ===\n")
SB <- mk_root("t")
g <- tick(SB, 2);   chk(identical(g, "[]"), "T1 2시간 전 틱 → 꼬리 없음(정상은 조용하다)", g)
g <- tick(SB, 71);  chk(identical(g, enc2utf8("[ · ★틱 71h 전(레인 정지?)]")), "T2 71시간 전 틱 → '★틱 71h 전(레인 정지?)'", g)
g <- tick(SB, 100); chk(identical(g, enc2utf8("[ · ★틱 4d 전(레인 정지?)]")), "T3 100시간 전 틱 → 일 단위('4d')", g)
g <- tick(SB, 8.5); chk(grepl("★틱", g), "T6 문턱(8h) + 0.5h → 경보", g)
g <- tick(SB, 7.5); chk(identical(g, "[]"), "T6 문턱(8h) − 0.5h → 조용", g)
SB2 <- mk_root("t2", max_age = 80)
g <- tick(SB2, 71); chk(identical(g, "[]"), "T6 문턱은 감시 정의에서 온다 — 정의를 80h 로 바꾸면 71시간은 조용(숫자가 블록에 박혀 있지 않다)", g)
# at 없음 → 파일 mtime 대체: mtime 을 기준 시각의 50시간 전으로 맞춘다
g <- run_py(SB, c(b_tick, sprintf('os.utime(R("06_Registry","replication_slots","_status.json"), (%s-50*3600, %s-50*3600))', NOW, NOW),
                  sprintf('print("[" + S(lambda: LANE_TICK({}, now=%s), "EXC") + "]")', NOW)))
chk(identical(g, enc2utf8("[ · ★틱 50h 전(레인 정지?)]")), "T4 at 없음 → 파일 mtime 으로 대체(50시간 → 경보)", g)
SBn <- mk_root("n", with_reg = FALSE)
g <- tick(SBn, 71); chk(identical(g, enc2utf8("[ · 틱 ?]")), "T5 감시 정의 부재 → '틱 ?'(정상으로 접지 않는다)", g)

cat("\n=== M 위반 주입(블록 사본) ===\n")
m1 <- sub('if ah>th else ""', 'if False else ""', b_tick, fixed = TRUE)
chk(!identical(m1, b_tick) && identical(tick(SB, 71, block = m1), "[]"), "M1 나이 비교를 끈 사본은 71시간 정지를 조용히 넘긴다 — T2 가 이것을 잡는다")
m2 <- sub('return " · 틱 ?"', 'return ""', b_tick, fixed = TRUE)
chk(!identical(m2, b_tick) && identical(tick(SBn, 71, block = m2), "[]"), "M2 '틱 ?' 를 빈 값으로 접은 사본은 정의 부재를 정상으로 보인다 — T5 가 이것을 잡는다")

cat("\n=== C 소비 배선 ===\n")
chk(sum(grepl("LANE_TICK(ss)", BL, fixed = TRUE)) == 1L && any(grepl("레인 슬롯 %d/%d%s%s%s", BL, fixed = TRUE)), "C 레인 슬롯 줄이 LANE_TICK(ss) 를 붙인다(1곳)")

cat("\n=== X 컨텍스트 게이지 ===\n")
TP <- gsub("\\\\", "/", file.path(tempdir(), sprintf("bootctx_%d", Sys.getpid()))); unlink(TP, recursive = TRUE)
PROJ <- file.path(TP, "Quant_Module_Moltbot"); BASE <- file.path(TP, "projects"); dir.create(PROJ, recursive = TRUE)
mk_tr <- function(key, name, tok, age_s) {
  d <- file.path(BASE, key); dir.create(d, recursive = TRUE, showWarnings = FALSE); f <- file.path(d, name)
  writeLines(c('{"type":"user","message":{"content":"hi"}}',
               sprintf('{"type":"assistant","message":{"usage":{"input_tokens":%d,"cache_creation_input_tokens":10,"cache_read_input_tokens":5}}}', tok),
               '{"type":"assistant","message":{"usage":{"input_tokens":999999}}}'), f)
  Sys.setFileTime(f, Sys.time() - age_s); invisible(f)
}
mk_tr("G--X-Quant-Module-Moltbot", "a.jsonl", 100L, 3000)
mk_tr("C--Users-Y-OneDrive-Quant-Module-Moltbot", "b.jsonl", 200L, 2000)                      # 맞는 꼬리 중 가장 최근
mk_tr("G--X-Quant-Module-Moltbot--claude-worktrees-zz", "c.jsonl", 300L, 10)                 # 워크트리 세션 — 꼬리가 달라 빠져야 한다
ctx <- function(block, base = BASE) run_py(PROJ, c(block, sprintf('print("[" + str(S(lambda: CTX(%s))) + "]")', py_raw(base))))
g <- ctx(b_ctx); chk(identical(g, "[215]"), "X1 꼬리가 맞는 폴더들 중 가장 최근 전사의 첫 응답 토큰 합(200 + 10 + 5)", g)
chk(!dir.exists(file.path(BASE, gsub("[^A-Za-z0-9]", "-", PROJ))), "X2 전제 — 정본 경로로 만든 폴더 이름은 픽스처에 없다(수리 전 방식이면 못 찾는 상황)")
g <- ctx(b_ctx, base = file.path(TP, "nowhere")); chk(identical(g, "[None]"), "X3 폴더 없음 → None(부팅 줄은 '?' · 예외로 죽지 않는다)", g)
old_line <- '    p=max(glob.glob(os.path.join(os.path.expanduser("~"),".claude","projects",re.sub(r"[^A-Za-z0-9]","-",P),"*.jsonl")),key=os.path.getmtime)'
i_p <- which(grepl("^    p=max\\(", b_ctx))
m3 <- b_ctx; if (length(i_p) == 1L) m3[i_p] <- sub('os.path.expanduser("~"),".claude","projects"', "base", old_line, fixed = TRUE)
g <- ctx(m3); chk(length(i_p) == 1L && identical(g, "[None]"), "M3 수리 전 한 줄(정본 경로로 폴더 이름)로 되돌린 사본은 전사를 못 찾는다 — X1 이 이것을 잡는다", g)

unlink(c(SB, SB2, SBn, TP), recursive = TRUE)
finish()
