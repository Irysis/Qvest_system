# =============================================================================
# test_hygiene_worktree_maxpath_axes.R — hygiene 감사 (b5) 워크트리 / (b6) MAX_PATH 위반 주입
#
# 신설 2026-08-16. 대상 = 02_Infrastructure/ops/artifact_hygiene_audit.R 의 신설 2축.
#
# ★왜 이 축이 필요했나 (실사고): 워크트리 43개가 3주간 무정리로 5.3GB(저장소 파일의 88%)를
#   점유했고 위생 감사는 **아무 경고도 내지 않았다**. 삭제를 막은 것은 MAX_PATH(260) 초과인데,
#   초과는 오류가 아니라 **조용한 건너뜀**으로 나타난다 — .NET/R 재귀삭제가 첫 초과 파일에서
#   트리 전체를 포기하면서 성공처럼 보인다. 그래서 '계수 감지'가 유일한 조기 신호다.
#
# ★검사 설계 원칙 (feedback-verify-both-directions-always):
#   정상에서 조용한 것만으로는 축이 살아있는지 알 수 없다. 각 축마다
#   ① 깨끗한 픽스처 = 미발화(양성 대조)  ② 위반 주입 = 발화  둘 다 요구한다.
#   주입해서 빨개지지 않으면 그 축은 죽은 축이다.
#
# ★260자 파일을 픽스처로 만들 수 없다 — 만드는 순간 같은 벽에 막힌다. 그래서 감사 스크립트에
#   QVEST_HYGIENE_MAXPATH_LIMIT env seam 을 두고 낮은 한계를 주입해 **실제 코드 경로**를 태운다
#   (판정 로직을 테스트에 재구현하지 않는다 — 재구현은 리팩터에서 조용히 갈라진다).
#
# 기존 08_Tests/ops/test_worktree_stranded_axis.sh 와 겹치지 않는다:
#   그쪽 = bootstrap.sh §4h '좌초'(미커밋이 방치됨) 판정 / 이쪽 = hygiene '누적·정리후보·경로길이'.
#
# 실행: Rscript -e 'source("08_Tests/ops/test_hygiene_worktree_maxpath_axes.R", encoding="UTF-8")'
# =============================================================================

suppressWarnings(suppressMessages(library(jsonlite)))

ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
if (!nzchar(ROOT)) ROOT <- getwd()
ROOT <- sub("/+$", "", gsub("\\\\", "/", ROOT))
AUDIT <- file.path(ROOT, "02_Infrastructure", "ops", "artifact_hygiene_audit.R")
stopifnot(file.exists(AUDIT))

PASS <- 0L; FAIL <- 0L
ok  <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", m)) }
bad <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s — %s\n", m, d)) }

# ---- 픽스처: 최소 저장소 골격 ----------------------------------------------
make_fixture <- function() {
  # ★역슬래시를 남기면 자식 R 코드 문자열에서 "\U..." 가 유니코드 이스케이프로 해석돼
  #   자식이 파싱 단계에서 죽는다(2026-08-16 실측). 픽스처 경로는 항상 정규화한다.
  fx <- gsub("\\\\", "/", file.path(tempdir(), paste0("hygfx_", as.integer(runif(1, 1e6, 9e6)))))
  for (d in c("02_Infrastructure/ops", "06_Registry", "04_Research", "08_Tests",
              ".cache", ".claude/worktrees", ".git/worktrees",
              "00_Lawbook", "01_Literature", "03_Universe", "05_Production",
              "outputs", "qepm", "stage_artifacts"))
    dir.create(file.path(fx, d), recursive = TRUE, showWarnings = FALSE)
  writeLines("{}", file.path(fx, "06_Registry", "index_descriptions.json"))
  for (f in c("CLAUDE.md", "CHANGELOG.md", "ARTIFACTS.md")) writeLines("x", file.path(fx, f))
  fx
}

# 감사 실행 → 리포트 파싱.
# ★env 를 부모에 심고 상속을 기대하지 않는다 — 실측(2026-08-16)에서 자식이 QM_ROOT 를
#   상속받지 못해 테스트가 **픽스처가 아니라 실제 저장소**를 감사했다(그리고 조용히 통과할 뻔).
#   대신 자식이 스스로 Sys.setenv 후 source 하게 한다. r-portability 금칙이라 system2(env=) 는
#   쓰지 않는다(Windows 에서 환경변수가 아니라 인자로 주입된다).
run_audit <- function(fx, maxpath_limit = NULL) {
  setenv <- sprintf('Sys.setenv(QM_ROOT="%s", QVEST_HYGIENE_DRY="1")', fx)
  if (!is.null(maxpath_limit))
    setenv <- sprintf('%s; Sys.setenv(QVEST_HYGIENE_MAXPATH_LIMIT="%s")', setenv, maxpath_limit)
  code <- sprintf('%s; source("%s", encoding="UTF-8")', setenv, AUDIT)
  out <- try(system2("Rscript", c("-e", shQuote(code)), stdout = TRUE, stderr = TRUE),
             silent = TRUE)
  rp <- file.path(fx, "06_Registry", "hygiene_report.json")
  rep <- if (file.exists(rp)) tryCatch(fromJSON(rp, simplifyVector = FALSE), error = function(e) NULL) else NULL
  # ★가드: 리포트가 픽스처 밖(=실제 저장소)을 감사했으면 즉시 중단. 이 가드가 없으면
  #   env 주입 실패 시 테스트가 실제 저장소를 재고 '통과'해버린다 (실측 사례).
  if (!is.null(rep) && !grepl(basename(fx), paste(out, collapse = " "), fixed = TRUE))
    stop("run_audit: 자식이 픽스처 루트를 못 받음 — env 주입 경로 점검 필요")
  list(stdout = paste(out, collapse = "\n"), report = rep)
}

cat("=== hygiene (b5) worktree / (b6) MAX_PATH 축 — 위반 주입 ===\n")

# ── T1 양성 대조: 깨끗한 픽스처에서 두 축 모두 미발화 ────────────────────────
fx <- make_fixture()
r  <- run_audit(fx)
if (is.null(r$report)) {
  bad("T1 baseline", paste("리포트 미생성:", substr(r$stdout, 1, 300)))
} else {
  w <- r$report$warnings
  if (length(w$worktree_prunable) == 0 && !isTRUE(w$worktree_summary$over_threshold))
    ok("T1a 깨끗한 픽스처 — b5 미발화 (양성 대조)")
  else bad("T1a 깨끗한 픽스처 b5 오발화",
           sprintf("prunable=%d over=%s", length(w$worktree_prunable), w$worktree_summary$over_threshold))
  if (isTRUE(w$maxpath$scanned) && w$maxpath$n_over == 0)
    ok("T1b 깨끗한 픽스처 — b6 미발화 (양성 대조)")
  else bad("T1b 깨끗한 픽스처 b6 오발화", sprintf("n_over=%s", w$maxpath$n_over))
}

# ── T2 주입: 껍데기(디스크에만 있는 워크트리) ───────────────────────────────
fx <- make_fixture()
dir.create(file.path(fx, ".claude/worktrees", "orphan-shell-abc123"), recursive = TRUE)
r <- run_audit(fx)
if (!is.null(r$report) && "orphan-shell-abc123" %in% unlist(r$report$warnings$worktree_prunable)) {
  ok("T2 껍데기 주입 → worktree_prunable 발화")
} else bad("T2 껍데기 미검출", "디스크에만 있는 워크트리가 정리후보로 안 잡힘")

# ── T3 주입: stale admin (등록됐으나 gitdir 백포인터 결측) ──────────────────
#    2026-08-16 실사고에서 실제로 35건이 이 상태로 남았다
fx <- make_fixture()
dir.create(file.path(fx, ".claude/worktrees", "wt-both-ok"), recursive = TRUE)
dir.create(file.path(fx, ".git/worktrees", "wt-both-ok"), recursive = TRUE)
writeLines("gitdir: x", file.path(fx, ".git/worktrees", "wt-both-ok", "gitdir"))
dir.create(file.path(fx, ".claude/worktrees", "wt-stale"), recursive = TRUE)
dir.create(file.path(fx, ".git/worktrees", "wt-stale"), recursive = TRUE)  # gitdir 없음
r <- run_audit(fx)
pr <- unlist(r$report$warnings$worktree_prunable)
if ("wt-stale" %in% pr && !("wt-both-ok" %in% pr)) {
  ok("T3 stale admin 주입 → 발화, 정상 워크트리는 미발화 (양방향)")
} else bad("T3 stale admin 판별 실패", sprintf("prunable=%s", paste(pr, collapse = ",")))

# ── T4 주입: 누적 임계 초과 ────────────────────────────────────────────────
fx <- make_fixture()
for (i in 1:7) {
  nm <- sprintf("wt-accum-%02d", i)
  dir.create(file.path(fx, ".claude/worktrees", nm), recursive = TRUE)
  dir.create(file.path(fx, ".git/worktrees", nm), recursive = TRUE)
  writeLines("gitdir: x", file.path(fx, ".git/worktrees", nm, "gitdir"))
}
r <- run_audit(fx)
ws <- r$report$warnings$worktree_summary
if (isTRUE(ws$over_threshold) && ws$on_disk == 7) {
  ok("T4 워크트리 7개(임계 5) → 누적 경고 발화")
} else bad("T4 누적 임계 미발화", sprintf("on_disk=%s over=%s", ws$on_disk, ws$over_threshold))

# ── T5 주입: MAX_PATH 초과 (낮은 한계 주입으로 실제 코드 경로를 태운다) ─────
fx <- make_fixture()
deep <- file.path(fx, "04_Research", paste(rep("verylongsegment", 4), collapse = "/"))
dir.create(deep, recursive = TRUE, showWarnings = FALSE)
writeLines("x", file.path(deep, "target_file_with_a_long_name.txt"))
lim <- nchar(fx) + 40L   # 픽스처 경로 + 여유 → 위 파일만 초과하도록
r <- run_audit(fx, maxpath_limit = lim)
mp <- r$report$warnings$maxpath
if (isTRUE(mp$scanned) && mp$n_over >= 1 && mp$limit == lim) {
  ok(sprintf("T5 한계 %d 주입 → 초과 %d건 발화", lim, mp$n_over))
} else bad("T5 MAX_PATH 초과 미검출", sprintf("scanned=%s n_over=%s limit=%s",
                                             mp$scanned, mp$n_over, mp$limit))

# ── T5b 반대 방향: 한계를 크게 주면 같은 픽스처가 조용해야 한다 ────────────
r2  <- run_audit(fx, maxpath_limit = 4000)
mp2 <- r2$report$warnings$maxpath
if (isTRUE(mp2$scanned) && mp2$n_over == 0) {
  ok("T5b 한계 4000 → 동일 픽스처 미발화 (한계가 실제로 판정을 움직인다)")
} else bad("T5b 한계 상향에도 발화", sprintf("n_over=%s", mp2$n_over))

# ── T6 주입: 잠복(지금은 통과, 워크트리 진입 시 초과) ───────────────────────
#    한계를 '파일길이 + 오버헤드' 사이에 두면 잠복으로만 잡혀야 한다
fx <- make_fixture()
d2 <- file.path(fx, "04_Research", "seg")
dir.create(d2, recursive = TRUE, showWarnings = FALSE)
tgt <- file.path(d2, "latent_probe.txt")
writeLines("x", tgt)
lim2 <- nchar(tgt) + 10L   # 파일은 통과, +49(오버헤드) 는 초과
r <- run_audit(fx, maxpath_limit = lim2)
mp <- r$report$warnings$maxpath
if (isTRUE(mp$scanned) && mp$n_over == 0 && mp$n_latent >= 1) {
  ok(sprintf("T6 잠복 축 발화 (초과 0 / 잠복 %d)", mp$n_latent))
} else bad("T6 잠복 축 실패", sprintf("n_over=%s n_latent=%s", mp$n_over, mp$n_latent))

# ── T7 주입: WORKTREE_NAME_MAX 상수 낙후 (드리프트 대조) ────────────────────
#    ★상수를 관측치로 산정하면 지표가 출렁이므로 고정했다. 대신 고정값이 실제와
#    어긋나면 반드시 알려야 한다 — 안 그러면 잠복이 조용히 과소평가된다.
fx <- make_fixture()
long_nm <- paste(rep("z", 40), collapse = "")   # 40자 > 상수 30
dir.create(file.path(fx, ".claude/worktrees", long_nm), recursive = TRUE)
r <- run_audit(fx)
mp <- r$report$warnings$maxpath
if (isTRUE(mp$overhead_const_stale) && mp$worktree_name_observed_max == 40) {
  ok("T7 상수 낙후(실제 40자 > 상수 30) → 드리프트 경고 발화")
} else bad("T7 상수 드리프트 미검출",
           sprintf("stale=%s observed=%s", mp$overhead_const_stale, mp$worktree_name_observed_max))

# ── T8: 계수가 n_warnings 에 실제로 반영되는가 (경고가 집계에서 증발하지 않게) ─
fx <- make_fixture()
base_n <- run_audit(fx)$report$n_warnings
dir.create(file.path(fx, ".claude/worktrees", "orphan-counts-me"), recursive = TRUE)
after_n <- run_audit(fx)$report$n_warnings
if (after_n > base_n) {
  ok(sprintf("T8 주입이 n_warnings 를 증가시킴 (%s→%s)", base_n, after_n))
} else bad("T8 n_warnings 미반영", sprintf("%s→%s — 경고가 집계에서 증발", base_n, after_n))

cat(sprintf("\n=== 결과: %d PASS / %d FAIL ===\n", PASS, FAIL))
# 2026-08-20: 배터리는 마지막 유효 JSON 줄만 읽는다 — 이 줄이 없어 UNREPORTED(=1 fail)로
#   계상됐다(내부는 전건 통과였다). 계약 결측이지 결함이 아니었음.
cat(sprintf("{\"test\":\"hygiene_worktree_maxpath_axes\",\"pass\":%d,\"fail\":%d,\"total\":%d}
", PASS, FAIL, PASS + FAIL))
if (FAIL > 0) quit(status = 1)
