#==============================================================================
# test_lineage_cwd_root.R — artifact lineage 의 **cwd 독립성** 계약 검사기
#
# 계약: 02_Infrastructure/docs/rules/r-portability.md 금칙 ③(루트는 표지로 검증) ·
#       ④(resolver 우선순위 = CLAUDE_PROJECT_DIR → QM_ROOT → 상향탐색)
#
# 배경 (2026-08-09 실측, WT-D20260809_002):
#   lineage_utils.R 의 읽기/쓰기가 전부 상대경로였다 —
#     append_lineage(wt_root="qepm/mailbox/worktask") · record_package_lineage(pkg_path) ·
#     smoke_reproduce(...) · capture_input_hashes(file.exists).
#   그래서 cwd 가 프로젝트 루트일 때만 동작했는데, 이 저장소의 문서화된 R 실행 패턴은
#   **전략/스테이지 디렉토리로 cd 한 뒤 Rscript** 다. 자연스러운 호출 규약이 계보를 깨뜨린다.
#   재현: cwd=stage_artifacts/fq143_tail_overlay_20260809/ 에서
#     Error in file(con,"w") : cannot open the connection
#     cannot open file 'qepm/mailbox/worktask/WT-D20260809_002/artifact_lineage.json'
#   ⚠[2026-08-09 정정] 초판 주석의 "계보는 Judge P7 감사 입력" 은 검증 없는 단정이었다.
#   실측: audit_p7_lineage() 프로덕션 호출자 0 · judge.md 게이트 목록(A~F)에 계보 없음 ·
#   judge_init.md lineage 언급 0. 계보는 설계상 감사 입력이나 **현재 소비 게이트가 없다**.
#   결손의 실피해 = 게이트 뚫림이 아니라 **재현 자취가 조용히 비어 가는 것**.
#
# ★이 검사기는 실트리를 건드리지 않는다. 표지를 갖춘 **합성 트리**(tempdir)를 세우고
#   CLAUDE_PROJECT_DIR 로 가리킨 뒤, cwd 를 무관한 tempdir 로 옮겨 판정한다.
#   (실 mailbox 에 synthetic WT 를 만드는 방식은 금칙 ② 사례 — 유령 WT 잔류 — 의 재발이다.)
#
# ★자매 검사기: test_lineage_git_state.R (금칙 ⑤ — 결손이 JSON 까지 라벨로 도달하는가).
#   그쪽은 `setwd(PROJ)` 로 시작하므로 cwd 의존성을 **구조적으로 못 본다**. 이 파일이 그 공백.
#==============================================================================

suppressPackageStartupMessages({ library(jsonlite); library(digest) })

# ─── 앵커 = self-first (금칙 ④-b: 테스트 러너는 공유 resolver 와 반대 규칙) ──────
# env-first 로 잡으면 worktree 에서 돌린 검사기가 조용히 **main 의 소스**를 검사한다.
# Bash 툴 환경엔 CLAUDE_PROJECT_DIR 이 없고 QM_ROOT 는 ~/.Renviron 이 main 으로 고정한다.
.qv_anchor_order <- c("self(--file=)", "CLAUDE_PROJECT_DIR", "QM_ROOT", "cwd")
.QV_MARKER <- "02_Infrastructure/hooks/qvest_hook_router.py"

.qv_norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
.qv_ok   <- function(p) length(p) == 1L && !is.na(p) && nzchar(p) &&
                        file.exists(file.path(p, .QV_MARKER))

.qv_self_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- ca[grepl("^--file=", ca)]
  # ★--file= 부재(예: Rscript -e 'source(...)')를 NA 로 흘리지 말 것 — 2026-08-08 에
  #  러너가 정확히 그렇게 죽었고, 실패 모양이 "계약 FAIL" 이라 오진을 유도했다.
  if (!length(f)) return(NA_character_)
  .qv_norm(file.path(dirname(sub("^--file=", "", f[1])), "..", ".."))
}

.qv_resolve <- function() {
  self <- .qv_self_root()
  cands <- c(self,
             Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""),
             Sys.getenv("QM_ROOT", unset = ""),
             getwd())
  labs <- .qv_anchor_order
  for (i in seq_along(cands)) {
    p <- cands[i]
    if (is.na(p) || !nzchar(p)) next
    p <- .qv_norm(p)
    if (.qv_ok(p)) {
      if (i > 1L && !is.na(self) && .qv_ok(self) && !identical(p, self)) {
        message(sprintf("⚠ ANCHOR OVERRIDE — %s='%s' (self='%s')", labs[i], p, self))
      }
      return(p)
    }
    message(sprintf("[anchor] 후보 기각 (%s=%s): 표지 부재", labs[i], p))
  }
  stop("project root 미발견 — 표지 ", .QV_MARKER, " 를 가진 트리 없음")
}

PROJ <- .qv_resolve()
setwd(PROJ)

PASS <- 0L; FAIL <- 0L
# ★길이-0 메시지를 그대로 sprintf 에 넘기면 **결과가 character(0)** 이라 cat 이 아무것도 찍지
#  않는다 — 카운터는 올라가는데 줄이 사라져서 "15줄인데 총계 16" 이 된다. 개발 중 실제로
#  겪었다(구판 실행에서 ent=NULL → as.character(NULL) → 축 1개가 무음 FAIL).
#  이 저장소가 반복하는 "빈 결과가 정상으로 읽힘" 계통이 검사기 자신에게서 재발한 형태다.
.msg1 <- function(m) { m <- as.character(m); if (!length(m) || is.na(m[1])) "<없음>" else m[1] }
ok  <- function(n, m = "") { m <- .msg1(m); PASS <<- PASS + 1L
  cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m) && m != "<없음>") paste0(" — ", m) else "")) }
bad <- function(n, m = "") { m <- .msg1(m); FAIL <<- FAIL + 1L
  cat(sprintf("  FAIL: %s — %s\n", n, m)) }

LINEAGE_SRC <- file.path(PROJ, "02_Infrastructure/worktask/lineage_utils.R")
invisible(capture.output(source(LINEAGE_SRC)))

cat("=== lineage cwd-independence contract ===\n")
cat(sprintf("  PROJ=%s\n", PROJ))

# ─── 임시 트리 정리 — 최상위 on.exit 은 금칙 ②(무발화). reg.finalizer 로 등록 ────
.TMP <- new.env(parent = emptyenv()); .TMP$paths <- character(0)
track <- function(p) { .TMP$paths <- c(.TMP$paths, p); p }
invisible(reg.finalizer(globalenv(),
                        function(e) unlink(.TMP$paths, recursive = TRUE, force = TRUE),
                        onexit = TRUE))

# 표지를 갖춘(또는 일부러 안 갖춘) 합성 프로젝트 트리
make_tree <- function(marker = TRUE, wt_ids = character(0)) {
  d <- tempfile("qvtree_")
  dir.create(file.path(d, "02_Infrastructure", "hooks"), recursive = TRUE)
  if (marker) writeLines("# synthetic root marker",
                         file.path(d, "02_Infrastructure", "hooks", "qvest_hook_router.py"))
  for (t in wt_ids) dir.create(file.path(d, "qepm", "mailbox", "worktask", t), recursive = TRUE)
  track(.qv_norm(d))
}
make_cwd <- function() {
  d <- tempfile("qvcwd_"); dir.create(d, recursive = TRUE); track(.qv_norm(d))
}

# env(root 앵커) + cwd 를 갈아끼우고 fn() 을 돌린 뒤 전부 원복한다.
# on.exit 은 **함수 프레임 안**이므로 금칙 ② 대상이 아니다(정상 발화).
#
# ★캐시 무효화를 `lineage_project_root(force=TRUE)` 로 하면 **루트가 없는 축**(12번)에서
#  하네스가 먼저 죽는다 — 제품 결함이 아니라 검사기 결함이고, 실패 모양이 제품 FAIL 로 읽힌다.
#  무효화는 캐시를 직접 비우는 것으로 한다(해석은 제품이 필요할 때 하게 둔다).
#
# ★구판(수리 전) 소스에 대해 돌려도 **조기 halt 하지 말 것**. halt 하면 exit 1 이라 빨갛기는
#  하나 어느 축이 뒤집혔는지 안 보이고, 읽는 사람이 "검사기가 깨졌다"로 오독한다.
#  구판에 없는 심볼은 존재 확인 후 해당 축을 FAIL 로 계상한다.
has_sym <- function(n) exists(n, envir = globalenv(), inherits = TRUE)

invalidate_root_cache <- function() {
  if (has_sym(".lineage_state")) {
    .lineage_state$root <- NULL
    .lineage_state$tier <- NULL
  }
}
in_context <- function(fn, cpd = NA, qm = NA, cwd = NULL) {
  old_cpd <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
  old_qm  <- Sys.getenv("QM_ROOT",            unset = NA)
  old_wd  <- getwd()
  on.exit({
    setwd(old_wd)
    if (is.na(old_cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old_cpd)
    if (is.na(old_qm))  Sys.unsetenv("QM_ROOT")            else Sys.setenv(QM_ROOT = old_qm)
    invalidate_root_cache()
  }, add = TRUE)

  if (is.na(cpd)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = cpd)
  if (is.na(qm))  Sys.unsetenv("QM_ROOT")            else Sys.setenv(QM_ROOT = qm)
  if (!is.null(cwd)) setwd(cwd)
  invalidate_root_cache()
  fn()
}
quiet <- function(expr) { r <- NULL; invisible(capture.output(suppressMessages(r <- expr))); r }

TID <- "WT-D29991231_001"   # 합성 트리 전용 id (실 mailbox 에는 만들지 않는다)

# ─── 1) 앵커 순서 = 계약 (금칙 ④ 표준 계열) ──────────────────────────────────
# 순서 자체가 계약이므로 기계가 읽을 수 있는 단일 줄로 노출돼 있어야 한다.
if (!has_sym(".LINEAGE_ANCHOR_ORDER")) {
  bad("anchor_order_declared", "앵커 순서가 기계-판독 가능한 형태로 노출돼 있지 않다(구판)")
} else if (identical(.LINEAGE_ANCHOR_ORDER, c("CLAUDE_PROJECT_DIR", "QM_ROOT", "ascend_from_cwd"))) {
  ok("anchor_order_declared", paste(.LINEAGE_ANCHOR_ORDER, collapse = " -> "))
} else {
  bad("anchor_order_declared",
      sprintf("표준 계열(CPD→QM_ROOT→ascend) 아님: %s",
              paste(.LINEAGE_ANCHOR_ORDER, collapse = " -> ")))
}

# ─── 2) 위반 주입: 표지 없는 후보는 수락이 아니라 낙하 ────────────────────────
# 02_Infrastructure/ 는 있지만 표지 파일이 없는 트리. dir.exists() 신뢰 구현이면 여기서 통과한다.
bare <- make_tree(marker = FALSE)
good <- make_tree(marker = TRUE)
if (!has_sym("lineage_project_root")) {
  bad("marker_gate_rejects_bare_dir", "lineage_project_root() 부재 — 루트 해석 자체가 없다(구판)")
  bad("resolver_cpd_over_qmroot",     "lineage_project_root() 부재 — 우선순위를 잴 대상이 없다(구판)")
} else {
  r <- in_context(function() lineage_project_root(), cpd = bare, qm = good, cwd = make_cwd())
  if (identical(r, good)) {
    ok("marker_gate_rejects_bare_dir", "표지 없는 CPD 후보 → QM_ROOT 로 낙하")
  } else if (identical(r, bare)) {
    bad("marker_gate_rejects_bare_dir", "표지 없는 디렉토리를 루트로 수락 — 존재 검사가 정체 검사를 대신함")
  } else {
    bad("marker_gate_rejects_bare_dir", sprintf("예상 밖 루트: %s", r))
  }

  # ─── 3) 우선순위: CLAUDE_PROJECT_DIR 이 QM_ROOT 를 이긴다 ───────────────────
  t1 <- make_tree(TRUE); t2 <- make_tree(TRUE)
  r <- in_context(function() lineage_project_root(), cpd = t1, qm = t2, cwd = make_cwd())
  if (identical(r, t1)) {
    ok("resolver_cpd_over_qmroot")
  } else {
    bad("resolver_cpd_over_qmroot", sprintf("QM_ROOT 가 이겼다(env-first 역전): %s", r))
  }
}

# ─── 4~7) 핵심 회귀: 비-루트 cwd 에서 record_package_lineage() ────────────────
tree <- make_tree(TRUE, wt_ids = TID)
wt   <- file.path(tree, "qepm/mailbox/worktask", TID)
pkg  <- file.path(wt, "alpha_package.json")
writeLines('{"synthetic":true}', pkg)
dir.create(file.path(tree, "06_Registry"), recursive = TRUE)
probe <- file.path(tree, "06_Registry", "probe.txt")
writeLines("probe", probe)

cwd_dir <- make_cwd()
writeLines("local", file.path(cwd_dir, "local_input.txt"))

res <- in_context(function() {
  tryCatch(quiet(record_package_lineage(
    task_id = TID, package_type = "alpha_package",
    input_file_paths = c("06_Registry/probe.txt",   # 프로젝트-상대
                         "local_input.txt",         # cwd-상대
                         "no/such/file.parquet")    # 진짜 부재
  )), error = function(e) structure(list(err = conditionMessage(e)), class = "axfail"))
}, cpd = tree, cwd = cwd_dir)

lp <- file.path(wt, "artifact_lineage.json")
if (inherits(res, "axfail")) {
  bad("nonroot_cwd_lands_in_root", sprintf("호출 자체가 실패: %s", res$err))
} else if (file.exists(lp)) {
  ok("nonroot_cwd_lands_in_root", "루트 기준 경로에 기록됨")
} else {
  bad("nonroot_cwd_lands_in_root", sprintf("기대 경로에 파일 없음: %s", lp))
}

# cwd 아래에 상대경로 잔재 트리를 만들지 않았는가 (구 구현의 다른 실패 형태)
if (dir.exists(file.path(cwd_dir, "qepm"))) {
  bad("no_stray_relative_tree", sprintf("cwd 아래 qepm/ 유령 트리 생성: %s", cwd_dir))
} else {
  ok("no_stray_relative_tree")
}

ent <- NULL
if (file.exists(lp)) {
  j <- fromJSON(lp, simplifyVector = FALSE)
  ent <- j$entries[[length(j$entries)]]
}
if (!is.null(ent) && identical(as.character(ent$task_id), TID) &&
    identical(as.character(ent$package_type), "alpha_package")) {
  ok("json_entry_reaches_file", sprintf("entries=%d", length(j$entries)))
} else {
  bad("json_entry_reaches_file", "직렬화된 entry 가 없거나 필드 불일치")
}

# package 파일 해시 — 구 구현은 비-루트 cwd 에서 file.exists()=FALSE 라
# file_path·file_hash_sha256 이 **오류 없이 둘 다 사라졌다**(필드 침묵 결손).
expect_hash <- digest::digest(file = pkg, algo = "sha256")
if (!is.null(ent) && identical(as.character(ent$file_hash_sha256), expect_hash)) {
  ok("pkg_hash_recorded_from_nonroot", substr(expect_hash, 1, 12))
} else {
  bad("pkg_hash_recorded_from_nonroot",
      sprintf("해시 누락/불일치: %s", if (is.null(ent$file_hash_sha256)) "<없음>" else as.character(ent$file_hash_sha256)))
}
# 기록 형식은 프로젝트-상대 유지 (기존 388 entry 와 형식이 갈리면 계보 비교가 깨진다)
if (!is.null(ent) && identical(as.character(ent$file_path),
                               file.path("qepm/mailbox/worktask", TID, "alpha_package.json"))) {
  ok("pkg_file_path_stays_relative", as.character(ent$file_path))
} else {
  bad("pkg_file_path_stays_relative",
      sprintf("기계-종속 절대경로가 기록됨: %s", as.character(ent$file_path)))
}

# ─── 8~10) input hash 해석: 루트-상대 ∧ cwd-상대 ∧ 진짜 부재는 NA ─────────────
ih <- if (is.null(ent)) list() else ent$input_hashes
gethash <- function(k) if (is.null(ih[[k]])) NULL else as.character(ih[[k]])
h_root <- gethash("06_Registry/probe.txt")
h_cwd  <- gethash("local_input.txt")
h_miss <- gethash("no/such/file.parquet")

if (!is.null(h_root) && identical(h_root, digest::digest(file = probe, algo = "sha256"))) {
  ok("input_hash_root_relative", "프로젝트-상대 입력이 비-루트 cwd 에서도 해석됨")
} else {
  bad("input_hash_root_relative", sprintf("해시 없음/불일치: %s", h_root %||% "<null>"))
}
if (!is.null(h_cwd) && identical(h_cwd, digest::digest(file = file.path(cwd_dir, "local_input.txt"), algo = "sha256"))) {
  ok("input_hash_cwd_first", "cwd-상대 입력이 여전히 해석됨(오검출 통제)")
} else {
  bad("input_hash_cwd_first",
      sprintf("cwd 기준 경로가 깨졌다 — 루트 재해석이 멀쩡한 경로를 덮음: %s", h_cwd %||% "<null>"))
}
if (is.null(h_miss)) {
  ok("input_hash_missing_is_na", "부재 입력 = null (결손 라벨 유지)")
} else {
  bad("input_hash_missing_is_na",
      sprintf("존재하지 않는 파일에 해시가 붙었다: %s", h_miss))
}

# ─── 11) smoke_reproduce: 비-루트 cwd 에서 'no_lineage' 로 위장하지 않는다 ────
# ★이건 예외가 아니라 **그럴듯한 정상 반환값**이라 호출자가 "계보 없음"으로 읽는다.
sm <- in_context(function() quiet(smoke_reproduce(TID)), cpd = tree, cwd = cwd_dir)
if (identical(sm$reason, "no_lineage")) {
  bad("smoke_reproduce_nonroot", "lineage 가 실재하는데 no_lineage — 결손의 값-위장(구 결함)")
} else if (isTRUE(sm$success)) {
  ok("smoke_reproduce_nonroot", sprintf("seed=%s", as.character(sm$seed)))
} else {
  bad("smoke_reproduce_nonroot", sprintf("예상 밖 사유: %s", sm$reason %||% "<none>"))
}

# ─── 12) 절대 wt_root 는 재-접두되지 않는다 (기존 호출자 회귀 + 지연해석 실증) ─
# env 를 비우고 cwd 를 tempdir 로 두면 루트는 **해석 불가**다. 그래도 절대 wt_root 는 동작해야 한다.
abs_root <- track(.qv_norm(tempfile("qvwt_")))
dir.create(file.path(abs_root, TID), recursive = TRUE)
r12 <- in_context(function() {
  tryCatch({
    e <- quiet(build_lineage_entry(task_id = TID, package_type = "risk_package"))
    quiet(append_lineage(TID, e, wt_root = abs_root))
    file.exists(file.path(abs_root, TID, "artifact_lineage.json"))
  }, error = function(e) conditionMessage(e))
}, cpd = NA, qm = NA, cwd = make_cwd())
if (isTRUE(r12)) {
  ok("absolute_wt_root_passthrough", "루트 미해결 상태에서도 절대 wt_root 동작(지연해석)")
} else {
  bad("absolute_wt_root_passthrough",
      sprintf("절대 wt_root 가 깨졌다: %s", as.character(r12)))
}

# ─── 13) WT 디렉토리 부재는 명시 오류 + 자동생성 금지 ─────────────────────────
# 구 구현은 raw connection error 만 던져 cwd 문제인지 task_id 오타인지 구별 불가였다.
ghost <- "WT-D29991231_999"
r13 <- in_context(function() {
  msg <- tryCatch({
    e <- quiet(build_lineage_entry(task_id = ghost, package_type = "alpha_package"))
    quiet(append_lineage(ghost, e)); NA_character_
  }, error = function(e) conditionMessage(e))
  list(msg = msg, created = dir.exists(file.path(tree, "qepm/mailbox/worktask", ghost)))
}, cpd = tree, cwd = cwd_dir)
if (!is.na(r13$msg) && grepl(ghost, r13$msg, fixed = TRUE) &&
    grepl(tree, r13$msg, fixed = TRUE)) {
  ok("missing_wt_dir_explicit_error", "해석된 절대경로가 오류문에 실림")
} else {
  bad("missing_wt_dir_explicit_error",
      sprintf("진단 불가능한 오류문: %s", if (is.na(r13$msg)) "<오류 없음>" else r13$msg))
}
if (isTRUE(r13$created)) {
  bad("no_ghost_wt_autocreate", "부재 task_id 로 mailbox 에 유령 WT 디렉토리 생성(금칙 ② 계열 재발)")
} else {
  ok("no_ghost_wt_autocreate")
}

# ─── 14) 돌연변이: 수리를 되돌린 사본에서 축 4 가 실제로 뒤집히는가 ───────────
# 안 뒤집히면 위 초록은 계측 사망이다 — 오탐 제거와 검사 사망은 겉보기가 같다.
mutate_and_run <- function() {
  src <- readLines(LINEAGE_SRC, warn = FALSE)
  needle <- ".lineage_abs(wt_root)"
  n_hit <- sum(vapply(src, function(l)
    sum(gregexpr(needle, l, fixed = TRUE)[[1]] > 0), integer(1)))   # count-only = 금칙 ⑥ 기준① 면제
  if (n_hit == 0L) {
    return(list(flipped = NA, note = sprintf("돌연변이 needle '%s' 미발견 — 수리가 사라졌거나 형태가 바뀜", needle)))
  }
  mut <- gsub(needle, "(wt_root)", src, fixed = TRUE)
  mp  <- track(tempfile("lineage_mut_", fileext = ".R"))
  writeLines(mut, mp)

  env <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(mp, envir = env))))

  mtree <- make_tree(TRUE, wt_ids = TID)
  mcwd  <- make_cwd()
  landed <- in_context(function() {
    tryCatch({
      quiet(env$record_package_lineage(task_id = TID, package_type = "alpha_package"))
      file.exists(file.path(mtree, "qepm/mailbox/worktask", TID, "artifact_lineage.json"))
    }, error = function(e) FALSE)
  }, cpd = mtree, cwd = mcwd)
  list(flipped = !isTRUE(landed), note = sprintf("needle %d곳 되돌림", n_hit))
}
mu <- mutate_and_run()
if (isTRUE(mu$flipped)) {
  ok("mutation_reverts_flip", sprintf("구판 사본에서 축 4 뒤집힘 (%s)", mu$note))
} else if (is.na(mu$flipped)) {
  bad("mutation_reverts_flip", mu$note)
} else {
  bad("mutation_reverts_flip",
      "구판(상대경로) 사본이 그대로 통과했다 — 이 suite 의 검출력이 없다(계측 사망)")
}

# ─── 요약 ────────────────────────────────────────────────────────────────────
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(toJSON(list(test = "lineage_cwd_root", pass = PASS, fail = FAIL,
                total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
