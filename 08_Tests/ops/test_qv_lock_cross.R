## test_qv_lock_cross.R — 쓰기 잠금 R 판(qv_lock.R) ↔ 파이썬 정본(qv_lock.py) 상호 판정 · GPU 임대 R API (2026-10-20 · WP3 · L1-SPEED-LEVERS-20261020)
##   같은 디스크 형식이므로 R 이 잡은 잠금을 파이썬이 '살아 있음'으로, 파이썬이 잡은 잠금을 R 이 '살아 있음'으로 봐야 한다(양방향 · 언어 섞임 경합).
##   X1 R 획득 → 파이썬 판정 held · 파이썬 획득 시간 초과 / X2 파이썬(자식) 획득 → R 판정 held · R 획득 시간 초과(qv_lock_timeout) · 놓으면 R 이 잡는다 /
##   X3 죽은 소유자(파이썬 형식 기록) → R 즉시 회수 / X4 R 재진입 깊이 · 해제 / X5 R 펜싱(토큰이 바뀌면 qv_lock_assert_mine 실패) /
##   X6 R 생존 판정 양방향(살아 있는 pid · 없는 pid · 시작 시각 불일치) / X7 GPU 임대 R API(획득 · 거부 · 상태 · 해제 — 파이썬 CLI 위임 = 같은 의미)
##   운영 잠금 · 임대 무접촉(임시 디렉터리 · QVEST_GPU_LEASE · QVEST_RF_CONFIG). 실행: Rscript 08_Tests/ops/test_qv_lock_cross.R
suppressPackageStartupMessages(library(jsonlite))
.self_dir <- function() { a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)]); if (length(f)) dirname(f[1]) else "." }
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", ""))
.cand <- file.path(.self_dir(), "..", "..")
if (!nzchar(ROOT) || !file.exists(file.path(ROOT, "02_Infrastructure/ops/qv_lock.R"))) ROOT <- .cand
Sys.setenv(QVEST_CODE_ROOT = ROOT)
source(file.path(ROOT, "02_Infrastructure/ops/qv_lock.R"))
PYQ <- file.path(ROOT, "02_Infrastructure/ops/qv_lock.py")
PY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(PY) || !file.exists(PY)) PY <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot/.venv_qvest_ml/Scripts/python.exe"

PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
TMP <- gsub("\\\\", "/", tempfile("qvx_")); dir.create(TMP)
pyrun <- function(code) suppressWarnings(system2(PY, c("-X", "utf8", "-c", shQuote(code)), stdout = TRUE, stderr = TRUE))
pyq <- sprintf("import importlib.util as u;s=u.spec_from_file_location('q',r'%s');q=u.module_from_spec(s);s.loader.exec_module(q)", PYQ)

cat("=== X1 R 이 잡은 잠금 — 파이썬이 산 잠금으로 본다 ===\n")
L1 <- file.path(TMP, "r_held.qvlock")
h1 <- qv_lock_acquire(L1, wait_s = 1, purpose = "cross_test")
o1 <- pyrun(paste0(pyq, ";import json;print(json.dumps(q.lock_state(r'", L1, "')))"))
st1 <- tryCatch(fromJSON(tail(o1, 1)), error = function(e) list(state = "parse_fail"))
chk("X1 파이썬 판정 = held(alive · 소유 pid = 이 R 프로세스)", identical(st1$state, "held") && identical(as.integer(st1$owner$pid), as.integer(Sys.getpid())), tail(o1, 1))
o1b <- pyrun(paste0(pyq, "\ntry:\n  q.acquire(r'", L1, "',wait_s=0.4);print('GOT')\nexcept q.LockTimeout:\n  print('TIMEOUT')"))
chk("X1 파이썬 획득 시도 = 시간 초과(R 보유 중)", identical(tail(o1b, 1), "TIMEOUT"), o1b)
chk("X1 R 해제 = released", identical(qv_lock_release(h1), "released") && !dir.exists(L1))

cat("=== X2 파이썬(자식)이 잡은 잠금 — R 이 산 잠금으로 본다 ===\n")
L2 <- file.path(TMP, "py_held.qvlock"); FL <- file.path(TMP, "py_flag")
code2 <- paste0(pyq, "\nimport time\nh=q.acquire(r'", L2, "',wait_s=10)\nopen(r'", FL, "','w').write('1')\ntime.sleep(3)\nq.release(h)")
cf <- file.path(TMP, "child2.py"); writeLines(code2, cf)
system2(PY, c("-X", "utf8", shQuote(cf)), wait = FALSE)
t0 <- Sys.time(); while (!file.exists(FL) && as.numeric(difftime(Sys.time(), t0, units = "secs")) < 20) Sys.sleep(0.05)
st2 <- qv_lock_state(L2)
chk("X2 R 판정 = held(파이썬 소유 · 생존)", identical(st2$state, "held"), st2$state)
e2 <- tryCatch({ qv_lock_acquire(L2, wait_s = 0.4); "GOT" }, error = function(e) class(e)[1])
chk("X2 R 획득 시도 = qv_lock_timeout(파이썬 보유 중 · 쓰지 않는다)", identical(e2, "qv_lock_timeout"), e2)
t1 <- Sys.time(); h2 <- qv_lock_acquire(L2, wait_s = 20)
w2 <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
chk("X2 파이썬이 놓으면 R 이 잡는다", !is.null(h2) && w2 > 0.3 && w2 < 15, w2)
qv_lock_release(h2)

cat("=== X3 죽은 소유자(파이썬 형식) → R 즉시 회수 ===\n")
L3 <- file.path(TMP, "dead.qvlock"); dir.create(L3)
writeLines(toJSON(list(schema = "qv_lock_v1", pid = 999901L, proc_start = NULL, token = "deadbeefdeadbeef",
                       acquired_epoch = as.numeric(Sys.time()), purpose = "fixture", lang = "py"), auto_unbox = TRUE, null = "null"),
           file.path(L3, "owner.json"))
st3 <- qv_lock_state(L3)
t3 <- Sys.time(); h3 <- qv_lock_acquire(L3, wait_s = 2)
chk("X3 stale(dead_owner) → 나이 무관 즉시 회수 · 소유 = 이 R", identical(st3$why, "dead_owner") && as.numeric(difftime(Sys.time(), t3, units = "secs")) < 1.5 &&
      identical(as.integer(qv_lock_state(L3)$owner$pid), as.integer(Sys.getpid())), st3$why)
qv_lock_release(h3)

cat("=== X4 R 재진입 ===\n")
L4 <- file.path(TMP, "reent.qvlock")
a <- qv_lock_acquire(L4); b <- qv_lock_acquire(L4)
chk("X4 같은 R 프로세스 재진입 = 깊이 2 · nested → released", b$depth == 2L && identical(qv_lock_release(b), "nested") &&
      identical(qv_lock_release(a), "released") && !dir.exists(L4))

cat("=== X5 R 펜싱 ===\n")
L5 <- file.path(TMP, "fence.qvlock"); h5 <- qv_lock_acquire(L5)
o <- fromJSON(file.path(L5, "owner.json")); o$token <- "ffffffffffffffff"
writeLines(toJSON(o, auto_unbox = TRUE, null = "null"), file.path(L5, "owner.json"))
e5 <- tryCatch({ qv_lock_assert_mine(h5); "OK" }, error = function(e) class(e)[1])
chk("X5 토큰이 바뀐(빼앗긴) 잠금 — qv_lock_assert_mine 실패(qv_lock_lost) · 해제는 lost(남의 잠금을 지우지 않는다)",
    identical(e5, "qv_lock_lost") && identical(qv_lock_release(h5), "lost") && dir.exists(L5), e5)
unlink(L5, recursive = TRUE)

cat("=== X6 R 생존 판정 양방향 ===\n")
ps0 <- qv_proc_start(Sys.getpid())
chk("X6 산 pid = TRUE · 없는 pid = FALSE · 시작 시각 불일치 = pid_reused",
    isTRUE(qv_pid_alive(Sys.getpid())) && identical(qv_pid_alive(999901L), FALSE) && is.finite(ps0) &&
      identical(qv_owner_alive(Sys.getpid(), ps0 - 3600)$why, "pid_reused") && isTRUE(qv_owner_alive(Sys.getpid(), ps0)$alive), ps0)
chk("X6 잠금 위치 규칙 = 파이썬과 같은 자리(06_Registry → .cache/registry_locks · 그 밖 → .qvlocks)",
    identical(qv_lock_dir_for(target = "C:/x/06_Registry/a.json"), "C:/x/.cache/registry_locks/a.json.qvlock") &&
      identical(qv_lock_dir_for(target = "C:/x/y/a.json"), "C:/x/y/.qvlocks/a.json.qvlock"))

cat("=== X7 GPU 임대 R API(파이썬 CLI 위임) ===\n")
Sys.setenv(QVEST_GPU_LEASE = file.path(TMP, "lease", "gpu_lease.json"))
cfg <- file.path(TMP, "cfg.json")
writeLines(toJSON(list(replication_lane = list(enabled = TRUE, gpu_lease = list(default_cap_hours = 12, max_cap_hours = 12))), auto_unbox = TRUE), cfg)
Sys.setenv(QVEST_RF_CONFIG = cfg)
g1 <- gpu_lease_acquire("core_runner", "P2 GPU 단계", 8)
g2 <- gpu_lease_acquire("other", "x")
g3 <- gpu_lease_status()
g4 <- gpu_lease_release("other"); g5 <- gpu_lease_release("core_runner"); g6 <- gpu_lease_status()
chk("X7 R 획득 = acquired(cap 8h) · 다른 보유자 거부 · 상태 held · 남의 해제 거부 · 보유자 해제 → free",
    isTRUE(g1$ok) && identical(g1$reason, "acquired") && identical(as.numeric(g1$lease$cap_hours), 8) && !isTRUE(g2$ok) &&
      identical(g2$reason, "held_by_other") && identical(g3$state, "held") && identical(g3$holder, "core_runner") &&
      !isTRUE(g4$ok) && isTRUE(g5$ok) && identical(g6$state, "free"), c(g1$reason, g2$reason, g3$state, g4$reason, g5$reason, g6$state))
g7 <- gpu_lease_acquire("core_runner", "P2 GPU 단계")
chk("X7 cap 생략 = 설정 기본 12h", isTRUE(g7$ok) && identical(as.numeric(g7$lease$cap_hours), 12), g7$lease$cap_hours)
invisible(gpu_lease_release("core_runner"))
Sys.unsetenv(c("QVEST_GPU_LEASE", "QVEST_RF_CONFIG"))
unlink(TMP, recursive = TRUE, force = TRUE)

cat(sprintf("\n== qv_lock_cross: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(toJSON(list(test = "qv_lock_cross", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n")
quit(status = if (FAIL > 0L) 1L else 0L)
