#==============================================================================
# test_atomic_json_write.R — JSON 원장 원자적 쓰기 계약 (2026-08-23 신설)
#
# 계약 정본: 02_Infrastructure/utils/atomic_json.R::qvest_atomic_write_json
# 수리 계기: axiom_context_inject.sh 가 주입 변동부를 통째로 잃은 사건(08-23 21:44,
#   HARD_10 발화)에서 시작해 JSON 원장 쓰기 전수를 훑은 결과, 저장소가 tmp→rename 을
#   **3벌 인라인 복제**하고 있었고 셋이 같은 결함 2종을 공유하고 있었다.
#
# ★1급 축은 "원자적으로 썼는가" 가 아니라 **"소비자가 절단·부재를 한 번도 안 보는가"** 다.
#   그래서 검사는 쓰기 함수를 단위 호출하지 않고 **쓰기 루프와 읽기 루프를 실제로 병렬**로
#   돌려 소비자 관점에서 센다.
#
# ★★"경고 0" 은 검사 사망과 구별되지 않는다 (feedback-verify-both-directions-always).
#   그래서 축 B 는 **원자성을 제거한 판**(구 인라인 패턴 그대로)을 같은 하네스에 넣고,
#   거기서 절단이 **실제로 관측되는지** 를 확인한다. 위반 주입에서 절단 0 이면
#   그것은 "구판도 안전하다" 가 아니라 **하네스에 검출력이 없다** 는 뜻이므로 FAIL 이다.
#
# 축:
#   A. 원자 쓰기 — 동시 읽기 중 절단/부재 관측 0 (+ 쓰기가 실제로 착지했는지 비공허 확인)
#   B. 위반 주입 — 비원자 쓰기에서 절단 또는 부재가 실제로 관측된다 (검출력 실증)
#   C. 플랫폼 계약 — 측정치 고정(선삭제 불필요 · copy 폴백이 절단원)
#   D. 배선 도달 — 소비자 3파일이 정본을 실제로 호출하고, 구 결함 패턴이 남아있지 않다
#   E. Python 생산자 — os.replace 가 핸들 점유로 실패하는 창을 재시도가 덮는다 + tmp 무잔재
#
# 정본 오염 없음: 모든 쓰기는 tempfile() 작업장에서만 일어난다(06_Registry 무접촉 — 축 F).
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })

# r-portability ④-b: **테스트 러너는 self-first**. env 우선이면 worktree 에서 돌려도
#   main 의 구판을 검사한다(= 안 고친 것을 고쳤다고 읽게 만든다). 표지 검증은 tier 마다.
# ★정규화(역슬래시→슬래시)는 검사 **앞**에 — QM_ROOT 가 역슬래시 형식일 수 있다(③).
.self_dir <- function() {
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(chartr("\\", "/", f[1])) else ""
}
ROOT <- local({
  sd <- .self_dir()
  cands <- c(if (nzchar(sd)) dirname(dirname(sd)) else "",
             Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd())
  cands <- chartr("\\", "/", cands[nzchar(cands)])
  hit <- cands[file.exists(file.path(cands, "08_Tests/hooks/run_all_hooks.sh"))]
  if (!length(hit)) stop("[atomic_json] project root 미발견 — 표지를 가진 후보 없음")
  hit[1]
})
HELPER <- file.path(ROOT, "02_Infrastructure/utils/atomic_json.R")

PASS <- 0L; FAIL <- 0L
chk <- function(nm, ok, d = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", nm)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", nm, d)) }
}

WORK <- tempfile(pattern = "qvest_atomic_")   # ③ "/tmp" 리터럴 금지
dir.create(WORK, recursive = TRUE, showWarnings = FALSE)
# ② 스크립트 최상위 on.exit() 는 no-op — reg.finalizer 로 등록해야 3경로 전부 발화.
invisible(reg.finalizer(globalenv(), function(e) unlink(WORK, recursive = TRUE, force = TRUE),
                        onexit = TRUE))

RSCRIPT <- file.path(R.home("bin"),
                     if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

#------------------------------------------------------------------------------
# 동시성 하네스 — 자식 writer N개(별 OS 프로세스) × 부모 reader 루프
#------------------------------------------------------------------------------
CHILD <- file.path(WORK, "writer.R")
writeLines(c(
  "suppressPackageStartupMessages({ library(jsonlite) })",
  "a <- commandArgs(trailingOnly = TRUE)",
  "mode <- a[1]; target <- a[2]; helper <- a[3]; iters <- as.integer(a[4]); done <- a[5]",
  "source(helper)",
  "# 페이로드는 소비자 원장(overlay 큐 ~246KB)과 같은 자릿수로 잡는다 — 비원자 쓰기의",
  "#   창이 실제 운영 규모에서 얼마나 벌어지는지를 재기 위함.",
  "items <- sprintf('STR_AS_2026%06d_%s', seq_len(9000), strrep('x', 12))",
  "okc <- 0L; errc <- 0L",
  "for (i in seq_len(iters)) {",
  "  payload <- list(schema = 'atomic_probe_v1', seq = i, n = length(items), items = items)",
  "  r <- tryCatch({",
  "    if (identical(mode, 'atomic')) {",
  "      qvest_atomic_write_json(payload, target, auto_unbox = TRUE, pretty = TRUE,",
  "                              null = 'null', na = 'null', validate = FALSE, tag = 'probe')",
  "    } else {",
  "      # ★위반 주입판 = 수리 전 인라인 패턴 그대로 (선삭제 + 제자리 write).",
  "      #   copy 폴백까지 재현할 필요는 없다 — 제자리 write 만으로 같은 절단면이 난다.",
  "      if (file.exists(target)) suppressWarnings(file.remove(target))",
  "      write_json(payload, target, auto_unbox = TRUE, pretty = TRUE, null = 'null', na = 'null')",
  "    }",
  "    TRUE }, error = function(e) FALSE)",
  "  if (isTRUE(r)) okc <- okc + 1L else errc <- errc + 1L",
  "}",
  "write_json(list(ok = okc, err = errc), done, auto_unbox = TRUE)"
), CHILD)

run_race <- function(mode, n_writers = 3L, iters = 12L, budget_s = 40) {
  target <- file.path(WORK, sprintf("%s_target.json", mode))
  unlink(target, force = TRUE)
  dones <- file.path(WORK, sprintf("%s_done_%d.json", mode, seq_len(n_writers)))
  logs  <- file.path(WORK, sprintf("%s_log_%d.txt",  mode, seq_len(n_writers)))
  unlink(c(dones, logs), force = TRUE)
  for (i in seq_len(n_writers)) {
    # ⑤ 인자에 쉘 리다이렉션을 넣지 않는다 — stdout/stderr 파라미터로 받는다.
    system2(RSCRIPT, args = c(CHILD, mode, target, HELPER, iters, dones[i]),
            wait = FALSE, stdout = logs[i], stderr = logs[i])
  }
  # ★관측을 3종으로 **분리**한다. 초판은 셋을 fromJSON 실패 하나로 뭉쳤는데, 그러면
  #   원자 쓰기에서도 "절단"이 잡혀 판정이 뒤집힌다(초판 실측: torn=3 인데 실체는 전부
  #   "Permission denied" 였다). 셋은 서로 다른 사건이다:
  #     absent  — 파일이 없다 (선삭제 창의 지문)
  #     blocked — 파일은 있는데 **open 이 거부**됐다. Windows 가 교체 찰나에 공유를 막는
  #               것으로, 원자성이 깨진 게 아니라 **소비자가 그 찰나에 못 여는 것**이다.
  #               ⇒ 원자 쓰기로도 0 이 되지 않는다. 소비자 재시도가 필요한 이유가 이것.
  #     torn    — 열어서 읽었는데 내용이 절단·불완전. 이것만이 원자성 위반의 지문이다.
  #   ★구조 검사(끝 문자 '}')를 fromJSON 앞에 둔다 — 절단된 대용량 JSON 의 파서 에러
  #     경로가 매우 느려(초판에서 주입 arm 읽기가 22회로 주저앉았다) 표본이 말라버린다.
  n_ok <- 0L; n_torn <- 0L; n_absent <- 0L; n_blocked <- 0L; seqs <- integer(0)
  t0 <- Sys.time(); deadline <- t0 + budget_s
  repeat {
    if (!file.exists(target)) {
      # "아직 첫 쓰기 전" 과 "선삭제 창" 을 구분 — 한 번이라도 읽힌 뒤의 부재만 센다.
      if (n_ok + n_torn > 0L) n_absent <- n_absent + 1L
    } else {
      raw <- tryCatch(suppressWarnings(readLines(target, warn = FALSE)),
                      error = function(e) NULL)
      if (is.null(raw)) {
        n_blocked <- n_blocked + 1L
      } else {
        txt <- trimws(paste(raw, collapse = "\n"))
        if (!nzchar(txt) || !endsWith(txt, "}")) {
          n_torn <- n_torn + 1L
        } else {
          d <- tryCatch(fromJSON(txt, simplifyVector = TRUE), error = function(e) NULL)
          if (is.null(d) || is.null(d$n) || is.null(d$items) || length(d$items) != d$n) {
            n_torn <- n_torn + 1L
          } else {
            n_ok <- n_ok + 1L; seqs <- c(seqs, as.integer(d$seq))
          }
        }
      }
    }
    if (all(file.exists(dones)) || Sys.time() > deadline) break
  }
  wrote <- vapply(dones, function(p)
    if (file.exists(p)) as.integer(fromJSON(p)$ok) else NA_integer_, integer(1))
  list(mode = mode, ok = n_ok, torn = n_torn, absent = n_absent, blocked = n_blocked,
       reads = n_ok + n_torn + n_absent + n_blocked, wrote = sum(wrote, na.rm = TRUE),
       finished = all(file.exists(dones)), distinct_seq = length(unique(seqs)),
       elapsed = round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1),
       size_kb = round(file.size(target) / 1024))
}

cat("\n=== A. 원자 쓰기 — 동시 읽기 중 절단/부재 0 ===\n")
A <- run_race("atomic")
cat(sprintf(paste0("     reads=%d ok=%d torn=%d absent=%d blocked=%d | writers ok=%d",
                   " finished=%s distinct_seq=%d | %skB %ss\n"),
            A$reads, A$ok, A$torn, A$absent, A$blocked, A$wrote, A$finished,
            A$distinct_seq, A$size_kb, A$elapsed))
# ★비공허 확인 먼저 — "0 torn" 은 읽기·쓰기가 실제로 겹쳤을 때만 의미가 있다.
#   (빈 결과 = 합격 금지. 이 저장소의 반복 결함이라 순서를 강제한다.)
chk("하네스 비공허: 읽기 100회 이상", A$reads >= 100L, sprintf("(reads=%d)", A$reads))
chk("하네스 비공허: 쓰기 착지 확인", A$wrote >= 30L, sprintf("(wrote=%d)", A$wrote))
chk("하네스 비공허: 관측된 seq 2종 이상(= 겹침 실증)", A$distinct_seq >= 2L,
    sprintf("(distinct_seq=%d)", A$distinct_seq))
chk("writer 전원 완주(재시도 소진 stop 없음)", isTRUE(A$finished))
chk("★절단 JSON 관측 0", A$torn == 0L, sprintf("(torn=%d)", A$torn))
chk("★파일 부재 관측 0 (선삭제 창 없음)", A$absent == 0L, sprintf("(absent=%d)", A$absent))
# ★blocked 는 0 을 요구하지 않는다 — Windows 가 교체 찰나에 open 을 거부하는 것이라
#   생산자가 없앨 수 없다. 대신 **드물다**는 것과, 그래서 소비자가 재시도를 갖는다는
#   것(축 D)을 함께 못박는다. 여기서 blocked 가 급증하면 재시도 사다리가 병목이라는 신호.
chk("open 거부는 드물다 (<1% — 소비자 1회 재시도로 덮이는 범위)",
    A$blocked <= max(1L, as.integer(A$reads * 0.01)),
    sprintf("(blocked=%d / reads=%d)", A$blocked, A$reads))

cat("\n=== B. 위반 주입 — 원자성 제거판에서 검출력이 실제로 나는가 ===\n")
B <- run_race("naive", iters = 25L)   # 주입 arm 은 창을 넓힌다 — 표본이 얇으면 플레이크 위험
cat(sprintf(paste0("     reads=%d ok=%d torn=%d absent=%d blocked=%d | writers ok=%d",
                   " finished=%s | %ss\n"),
            B$reads, B$ok, B$torn, B$absent, B$blocked, B$wrote, B$finished, B$elapsed))
# 주입 arm 의 비공허 기준은 A 와 다르다: 읽기 표본이 절단·부재로 자주 깨져 회수가 적다.
#   요구는 ①writer 가 실제로 썼고 ②reader 가 온전한 판을 최소 1회 읽을 능력이 있다는 것.
chk("주입 하네스 비공허: 쓰기 착지 확인", B$wrote >= 30L, sprintf("(wrote=%d)", B$wrote))
chk("주입 하네스 비공허: 온전한 판도 최소 1회 읽힌다(reader 정상)", B$ok >= 1L,
    sprintf("(ok=%d)", B$ok))
# ★여기서 0 이면 "구판도 안전" 이 아니라 "하네스가 아무것도 못 잰다" 다 → FAIL.
chk("★★위반 주입에서 절단/부재가 실제로 관측된다 (검사기 생존 증명)",
    (B$torn + B$absent) > 0L,
    sprintf("(torn=%d absent=%d — 검출력 0 이면 축 A 의 초록도 무의미)", B$torn, B$absent))
chk("★주입 arm 의 결함률이 원자 arm 보다 유의하게 높다 (대조 성립)",
    (B$torn + B$absent) / max(1L, B$reads) > (A$torn + A$absent) / max(1L, A$reads),
    sprintf("(naive %.3f vs atomic %.3f)",
            (B$torn + B$absent) / max(1L, B$reads), (A$torn + A$absent) / max(1L, A$reads)))

cat("\n=== C. 플랫폼 계약 (측정치 고정) ===\n")
source(HELPER)
cp <- file.path(WORK, "c_target.json"); ct <- file.path(WORK, "c_src.json")
writeLines("{\"v\":\"OLD\"}", cp); writeLines("{\"v\":\"NEW\"}", ct)
chk("file.rename 은 존재하는 대상을 덮어쓴다 (⇒ 선삭제 불필요)",
    isTRUE(suppressWarnings(file.rename(ct, cp))) &&
      identical(trimws(readLines(cp, warn = FALSE)[1]), "{\"v\":\"NEW\"}"))
writeLines("{\"v\":\"OLD\"}", cp); writeLines("{\"v\":\"NEW2\"}", ct)
con <- file(cp, "r"); invisible(readLines(con, n = 1L))       # 소비자 핸들 점유 재현
r_rename <- isTRUE(suppressWarnings(file.rename(ct, cp)))
r_copy   <- isTRUE(suppressWarnings(file.copy(ct, cp, overwrite = TRUE)))
close(con)
chk("핸들 점유 중 file.rename 은 실패한다 (⇒ 재시도가 1차 수단)", !r_rename)
chk("핸들 점유 중 file.copy(overwrite) 는 성공한다 (⇒ copy 폴백이 절단원)", r_copy)
chk("정본 기본값 allow_copy_fallback = FALSE",
    identical(formals(qvest_atomic_write_json)$allow_copy_fallback, FALSE))

cat("\n=== D. 배선 도달 — '붙였다' 가 아니라 '도달한다' ===\n")
consumers <- c(
  "02_Infrastructure/ops/auto_spawn_queue.R",
  "02_Infrastructure/regime/overlay_candidate_queue.R",
  "02_Infrastructure/portfolio/standalone_track_queue.R")
for (rel in consumers) {
  p <- file.path(ROOT, rel)
  txt <- if (file.exists(p)) readLines(p, warn = FALSE) else character(0)
  live <- txt[!grepl("^\\s*#", txt)]                  # 주석 제외 (수리 노트 오탐 방지)
  chk(sprintf("%s :: 정본 source", basename(rel)),
      any(grepl("utils/atomic_json.R", live, fixed = TRUE)))
  chk(sprintf("%s :: qvest_atomic_write_json 호출", basename(rel)),
      any(grepl("qvest_atomic_write_json", live, fixed = TRUE)))
  chk(sprintf("%s :: 선삭제 잔재 없음", basename(rel)),
      !any(grepl("file.remove(path)", live, fixed = TRUE) |
           grepl("file.remove(dp)", live, fixed = TRUE)))
  chk(sprintf("%s :: copy 폴백 잔재 없음", basename(rel)),
      !any(grepl("overwrite = TRUE", live, fixed = TRUE)))
}
ovq <- readLines(file.path(ROOT, "02_Infrastructure/regime/overlay_candidate_queue.R"), warn = FALSE)
chk("overlay 큐 :: QUEUE_PATH 로 가는 비원자 write_json 없음",
    !any(grepl("^\\s*write_json\\(queue, QUEUE_PATH", ovq)))
stq <- readLines(file.path(ROOT, "02_Infrastructure/portfolio/standalone_track_queue.R"), warn = FALSE)
chk("standalone 큐 :: qp 로 가는 비원자 write_json 없음",
    !any(grepl("^\\s*write_json\\(q, qp", stq)))
# ★소비자 쪽 재시도는 생산자 수리로 **대체되지 않는다** — 축 A 의 blocked 관측이 그 근거다
#   (교체 찰나의 open 거부는 원자성과 무관하게 남는다). 제거 회귀를 여기서 막는다.
inj <- readLines(file.path(ROOT, "02_Infrastructure/hooks/axiom_context_inject.sh"), warn = FALSE)
chk("axiom_context_inject.sh :: positive_context 재시도 유지",
    any(grepl("_load_pc()", inj, fixed = TRUE)) && any(grepl("pc_status", inj, fixed = TRUE)))

cat("\n=== E. Python 생산자 (lcode_harvester.py::_write_json_atomic) ===\n")
PYBIN <- Sys.getenv("QVEST_PY", "")
if (!nzchar(PYBIN) || !file.exists(PYBIN)) PYBIN <- unname(Sys.which("python"))
if (!nzchar(PYBIN)) {
  cat("  [skip] Python 해석기 미발견 (QVEST_PY 미설정 & PATH 부재)\n")
} else {
  PYPROBE <- file.path(WORK, "probe.py")
  writeLines(c(
    "import importlib.util, json, os, sys, threading, time, glob",
    "root, work = sys.argv[1], sys.argv[2]",
    "spec = importlib.util.spec_from_file_location('lh', os.path.join(root, '02_Infrastructure/axiom/lcode_harvester.py'))",
    "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)",
    "tgt = os.path.join(work, 'py_target.json')",
    "m._write_json_atomic({'v': 'OLD'}, tgt)",
    "res = {}",
    "# 1) 핸들을 0.12s 잡고 있는 동안 교체를 건다 — 재시도(~1.3s)가 그 창을 덮어야 한다.",
    "fh = open(tgt, 'r', encoding='utf-8')",
    "threading.Timer(0.12, fh.close).start()",
    "t0 = time.time()",
    "try:",
    "    m._write_json_atomic({'v': 'NEW'}, tgt); res['retry_covered'] = True",
    "except OSError as e:",
    "    res['retry_covered'] = False; res['err'] = str(e)",
    "res['elapsed'] = round(time.time() - t0, 3)",
    "res['content_new'] = json.load(open(tgt, encoding='utf-8')).get('v') == 'NEW'",
    "# 2) 위반 주입: 재시도를 1회로 낮추고 핸들을 길게(0.6s) 잡으면 반드시 실패해야 한다.",
    "#    여기서 실패하지 않으면 재시도 축 자체가 아무것도 안 재고 있다는 뜻이다.",
    "old = m._ATOMIC_RETRIES; m._ATOMIC_RETRIES = 1",
    "fh2 = open(tgt, 'r', encoding='utf-8')",
    "threading.Timer(0.6, fh2.close).start()",
    "try:",
    "    m._write_json_atomic({'v': 'X'}, tgt); res['injected_fails'] = False",
    "except OSError:",
    "    res['injected_fails'] = True",
    "m._ATOMIC_RETRIES = old",
    "time.sleep(0.7)",
    "res['tmp_residue'] = len(glob.glob(os.path.join(work, '.py_target.json.tmp_*')))",
    "print(json.dumps(res))"
  ), PYPROBE)
  out <- suppressWarnings(system2(PYBIN, args = c(PYPROBE, ROOT, WORK), stdout = TRUE, stderr = TRUE))
  jl <- out[grepl("^\\{", out)]
  if (!length(jl)) {
    chk("Python probe 실행", FALSE, paste(utils::tail(out, 3), collapse = " | "))
  } else {
    E <- fromJSON(jl[length(jl)])
    cat(sprintf("     retry_covered=%s elapsed=%ss injected_fails=%s tmp_residue=%s\n",
                E$retry_covered, E$elapsed, E$injected_fails, E$tmp_residue))
    chk("★핸들 점유 창을 재시도가 덮는다 (os.replace 성공)", isTRUE(E$retry_covered))
    chk("교체 내용이 실제로 반영됐다", isTRUE(E$content_new))
    chk("★★위반 주입(재시도 1회)에서 실제로 실패한다 (재시도 축 생존 증명)",
        isTRUE(E$injected_fails))
    chk("실패 후 tmp 잔재 0", isTRUE(E$tmp_residue == 0L), sprintf("(residue=%s)", E$tmp_residue))
  }
}

cat("\n=== F. 정본 오염 없음 ===\n")
chk("06_Registry 무접촉 (작업장은 tempfile 만)",
    !any(file.exists(file.path(ROOT, c("06_Registry/atomic_target.json",
                                       "06_Registry/naive_target.json")))))

unlink(WORK, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== 결과: PASS %d / FAIL %d ===\n", PASS, FAIL))
cat(sprintf("{\"test\":\"atomic_json_write\",\"pass\":%d,\"fail\":%d,\"skipped\":0,\"total\":%d}\n",
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
