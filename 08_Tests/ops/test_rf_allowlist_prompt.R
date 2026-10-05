#!/usr/bin/env Rscript
#==============================================================================
# test_rf_allowlist_prompt.R — 오버레이 arm 생성 프롬프트의 '허용 함수 목록'
#   (도훈 결정 B09-ALLOWLIST-PROMPT 2026-09-25 19시 · 06_Registry/decision_register.json)
#
# 대상: 02_Infrastructure/reinforcement/overlay_allowlist_prompt.R (렌더러 · probe 적재기 경유)
#       02_Infrastructure/ops/rf_overlay_propose.sh (생성 레인 — 미제공 = LLM 미호출)
#       02_Infrastructure/ops/rf_b5_design_lib.R   (B5 설계 재료 (7) 목록 · 미제공 = (7)·(8) 명시 · 재료는 쓴다)
# 양방향:
#   A 렌더러 — [양성] 키별 이름 집합 = 레지스트리(common ∪ widened · ★검사 자체 JSON 판독 — 피검 적재기와 독립) ·
#              참조 이름공간 · 개별 허가(새 arm 불가 표기) · [변경] widened 추가·common 삭제가 렌더에 반영 ·
#              [위반 주입] 레지스트리 부재 · JSON 파손 · 스키마 불일치 · 능력 계열 오염 · 적재기 없는 probe → rc 3 · 미제공 블록 · 목록 0 ·
#              [정합] 렌더에 있는 이름 ⇔ probe ③d 가 받는 이름(추가한 이름·삭제한 이름 양쪽 — overlay_probe_allowlist_scan)
#              (적대 검증 수리 2026-09-25) A11 [정합 2] 렌더의 '겹치는 열' ⇔ probe 가 맨이름으로 거부하는 픽스처 열 · $ 읽기 전부 통과 ·
#              A12 [위반 주입] 참조 이름공간 미설치 → rc 3(probe 도 판정 불가)
#   B B5 재료 — (7) 안 · G1 앞 · 목록 전부 · 변경 반영 · [부재] 재료는 쓰되 (7) 미제공 + (8) 새 arm 금지 + jlog 두 곳
#   C 생성 레인 — 가짜 claude(RF_CLAUDE_BIN + PATH) 로 **실제 발송 프롬프트** 포착: 목록 전부 · 변경 반영 · jlog allowlist_rendered ·
#              [위반 주입] 부재 · 적재기 없는 probe → LLM 호출 0 · halt_allowlist_unavailable · 방출 원장 불변 · 프롬프트 파일 없음
# 대상 교체(돌연변이 · 수리 전 red): QVEST_ALP_RENDERER · QVEST_ALP_LANE · QVEST_ALP_B5LIB (기본 = QM_ROOT 아래 정본)
# 격리: 합성 루트 전부 tempdir · 자식 R 은 R_ENVIRON_USER=빈 파일 + QM_ROOT=합성 루트(probe 의 QM_ROOT 폴백이 운영 목록을 못 줍게) ·
#       jlog = tempdir · 운영(QM_ROOT)은 코드·레지스트리 읽기만 — 끝에 해시 대조.
#==============================================================================
suppressMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
CODE <- sub("/+$", "", gsub("\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"), fixed = TRUE))
RENDERER <- Sys.getenv("QVEST_ALP_RENDERER", file.path(CODE, "02_Infrastructure/reinforcement/overlay_allowlist_prompt.R"))
LANE     <- Sys.getenv("QVEST_ALP_LANE", file.path(CODE, "02_Infrastructure/ops/rf_overlay_propose.sh"))
B5LIB    <- Sys.getenv("QVEST_ALP_B5LIB", file.path(CODE, "02_Infrastructure/ops/rf_b5_design_lib.R"))
PROBE    <- file.path(CODE, "02_Infrastructure/reinforcement/overlay_probe.R")
REG_REL  <- "06_Registry/overlay_probe_allowlist.json"
REG0     <- file.path(CODE, REG_REL)
RSCRIPT  <- file.path(R.home("bin"), "Rscript")
PYX      <- Sys.getenv("QVEST_PY", file.path(CODE, ".venv_qvest_ml/Scripts/python.exe"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { d <- paste(as.character(unlist(d)), collapse = " ")   # 길이 0·NA 상세도 죽지 않는다(red 판이 끝까지 보고)
  FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
  cat(sprintf('{"test":"rf_allowlist_prompt","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
  quit(status = if (FAIL > 0L) 1L else 0L)
}
T <- gsub("\\", "/", file.path(tempdir(), sprintf("alp_%d", Sys.getpid())), fixed = TRUE)
unlink(T, recursive = TRUE, force = TRUE); invisible(dir.create(T, recursive = TRUE))
EMPTY_RENV <- file.path(T, "empty.Renviron"); invisible(file.create(EMPTY_RENV))
wjson <- function(x, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), p) }
cpf <- function(rel, dst_root, src = file.path(CODE, rel)) {
  d <- file.path(dst_root, rel); dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE); invisible(file.copy(src, d, overwrite = TRUE)) }
#' 자식 프로세스 — 환경변수를 잠깐 바꿔 띄우고 되돌린다(system2 env 인자는 Windows 에서 믿지 않는다)
with_env <- function(vars, expr) {
  old <- Sys.getenv(names(vars), unset = NA_character_, names = TRUE)
  un <- vapply(vars, is.na, logical(1))
  if (any(!un)) do.call(Sys.setenv, as.list(vars[!un]))
  if (any(un)) Sys.unsetenv(names(vars)[un])
  on.exit({ for (k in names(old)) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)) }, add = TRUE)
  force(expr)
}
run <- function(cmd, args, vars) with_env(c(R_ENVIRON_USER = EMPTY_RENV, vars), {
  out <- suppressWarnings(system2(cmd, shQuote(args), stdout = TRUE, stderr = TRUE))
  list(rc = attr(out, "status") %||% 0L, out = gsub("\r", "", as.character(out))) })

# ── 사전 조건 — 운영 레지스트리·probe 적재기(R3R) ───────────────────────────────
if (!file.exists(REG0)) { ng("사전 조건: 레지스트리 부재", REG0); finish() }
if (!file.exists(PROBE) || !any(grepl("overlay_probe_allowlist_params <- function", readLines(PROBE, warn = FALSE), fixed = TRUE))) {
  ng("사전 조건: probe 에 ③d 적재기 없음(R3R 미배포)", PROBE); finish() }
REAL <- c(REG0, file.path(CODE, c("06_Registry/overlay_arm_ledger.jsonl", "06_Registry/overlay_catalog.json", "06_Registry/reinforce_ledger_l1.json")))
REAL <- REAL[file.exists(REAL)]; REAL_MD5 <- tools::md5sum(REAL)
ARMS_LS0 <- sort(list.files(file.path(CODE, "02_Infrastructure/reinforcement/overlay_arms")))

# ── 검사 자체 판독기(피검 적재기와 독립) ─────────────────────────────────────────
expect_of <- function(regp) {
  j <- fromJSON(regp, simplifyVector = FALSE)
  keys <- names(j$common)
  sets <- setNames(lapply(keys, function(k) sort(unique(c(as.character(unlist(j$common[[k]])), as.character(unlist(j$widened[[k]])))), method = "radix")), keys)
  gr <- lapply(j$grants %||% list(), function(g) sort(unique(as.character(unlist(g[intersect(keys, names(g))]))), method = "radix"))
  list(keys = keys, sets = sets, ref = as.character(unlist(j$ref_namespaces)), grants = gr)
}
ticks <- function(s) { m <- regmatches(s, gregexpr("`[^`]+`", s)); gsub("^`|`$", "", unlist(m)) }
#' 렌더 줄(재료·프롬프트 어디서든)에서 키별 이름 집합 — "- <key> — … (<n>종): `a`, `b`[ · 꼬리]"
rendered_sets <- function(lines, keys) {
  out <- list()
  for (k in keys) {
    i <- which(startsWith(lines, sprintf("- %s — ", k)))
    if (length(i) != 1L) { out[[k]] <- NULL; next }
    body <- sub("^.*?종\\): ", "", lines[i], perl = TRUE)
    body <- sub(" · 그 밖에 .*$", "", body); body <- sub(" · do\\.call .*$", "", body)
    n <- suppressWarnings(as.integer(sub("^.*\\((\\d+)종\\): .*$", "\\1", lines[i], perl = TRUE)))
    out[[k]] <- structure(sort(unique(ticks(body)), method = "radix"), n = n)
  }
  out
}
#' 렌더 블록 전체 대조 — 키별 집합 일치 · 개수 표기 일치 · 참조 이름공간 · 개별 허가 이름
cmp_block <- function(lines, ex, tag) {
  rs <- rendered_sets(lines, ex$keys)
  bad <- character(0)
  for (k in ex$keys) {
    got <- rs[[k]]
    if (is.null(got)) { bad <- c(bad, sprintf("%s 줄 없음", k)); next }
    if (!identical(as.character(got), ex$sets[[k]])) bad <- c(bad, sprintf("%s 집합 불일치(누락 %s · 과잉 %s)", k,
      paste(utils::head(setdiff(ex$sets[[k]], got), 4), collapse = ","), paste(utils::head(setdiff(got, ex$sets[[k]]), 4), collapse = ",")))
    if (!identical(attr(got, "n"), length(ex$sets[[k]]))) bad <- c(bad, sprintf("%s 개수 표기 %s ≠ %d", k, attr(got, "n"), length(ex$sets[[k]])))
  }
  ri <- grep("^- 참조 이름공간", lines)
  if (length(ri) != 1L || !setequal(ticks(lines[ri]), ex$ref)) bad <- c(bad, "참조 이름공간 불일치")
  for (g in names(ex$grants)) {
    gi <- grep(sprintf("^  · %s — ", g), lines)
    if (length(gi) != 1L || !setequal(ticks(lines[gi]), ex$grants[[g]])) bad <- c(bad, sprintf("개별 허가 %s 불일치", g))
  }
  if (length(ex$grants) && !any(grepl("새 arm 에는 적용되지 않는다", lines, fixed = TRUE))) bad <- c(bad, "개별 허가 '새 arm 불가' 표기 없음")
  n_all <- sum(lengths(ex$sets))
  chk(!length(bad), sprintf("%s 목록 전부 — 키 %d종 · 이름 %d · 참조 이름공간 %d · 개별 허가 %d", tag, length(ex$keys), n_all, length(ex$ref), length(ex$grants)),
      paste(utils::head(bad, 5), collapse = " | "))
}

# ── 레지스트리 변형 3종 ─────────────────────────────────────────────────────────
RA <- file.path(T, "ra"); cpf(REG_REL, RA, REG0)
EXA <- expect_of(file.path(RA, REG_REL))
jb <- fromJSON(REG0, simplifyVector = FALSE)
ADD_NAME <- "zzallow_widen_fn"
calls0 <- as.character(unlist(jb$common$calls))
DEL_NAME <- calls0[grepl("^[a-z][a-z0-9]*$", calls0) & !calls0 %in% c("function", "c", "list", "length")][1]
jb$common$calls <- as.list(setdiff(calls0, DEL_NAME))
jb$widened$calls <- as.list(unique(c(as.character(unlist(jb$widened$calls)), ADD_NAME)))
RB <- file.path(T, "rb"); wjson(jb, file.path(RB, REG_REL))
EXB <- expect_of(file.path(RB, REG_REL))
stopifnot(ADD_NAME %in% EXB$sets$calls, !DEL_NAME %in% EXB$sets$calls, DEL_NAME %in% EXA$sets$calls)

render <- function(root, probe = PROBE, qm = root) {   # qm = 자식의 QM_ROOT(probe 적재기의 폴백 자리) — 기본은 root 와 같게
  outp <- file.path(T, sprintf("render_%s_%s.txt", basename(root), basename(qm))); unlink(outp)
  r <- run(RSCRIPT, c(RENDERER, outp, root, probe), c(QM_ROOT = qm, QVEST_RF_ROOT = NA))
  r$lines <- if (file.exists(outp)) gsub("\r", "", readLines(outp, warn = FALSE, encoding = "UTF-8")) else character(0)
  r$last <- utils::tail(grep("^allowlist:", r$out, value = TRUE), 1) %||% ""
  r
}

cat("=== A. 렌더러 ===\n")
if (!file.exists(RENDERER)) { ng("A0 렌더러 파일 부재", RENDERER) } else {
  a1 <- render(RA)
  chk(a1$rc == 0L && startsWith(a1$last, "allowlist: ok"), "A1 [양성] rc 0 · 'allowlist: ok'", paste(a1$rc, a1$last, utils::tail(a1$out, 2)))
  cmp_block(a1$lines, EXA, "A1")
  chk(any(startsWith(a1$lines, "### 허용 함수 목록 — probe")), "A1 머리줄")
  a2 <- render(RB)
  cmp_block(a2$lines, EXB, "A2 [변경]")
  rsb <- rendered_sets(a2$lines, "calls")$calls
  chk(ADD_NAME %in% rsb && !DEL_NAME %in% rsb, sprintf("A2 [변경] widened 추가 %s 는 보이고 common 삭제 %s 는 사라진다", ADD_NAME, DEL_NAME))
  # [위반 주입] — 부재 · 파손 · 스키마 · 능력 계열 오염 · 적재기 없는 probe
  neg <- function(tag, root, probe = PROBE, want = "") {
    r <- render(root, probe)
    good <- r$rc == 3L && startsWith(r$last, "allowlist: unavailable") && any(grepl("미제공", r$lines, fixed = TRUE)) &&
            !any(grepl("^- calls — ", r$lines)) && (!nzchar(want) || grepl(want, r$last, fixed = TRUE))
    chk(good, sprintf("%s → rc 3 · 미제공 블록 · 목록 0%s", tag, if (nzchar(want)) sprintf(" · 사유 '%s'", want) else ""),
        paste(r$rc, r$last, paste(utils::head(r$lines, 1), collapse = "")))
  }
  RC0 <- file.path(T, "rc_absent"); dir.create(file.path(RC0, "06_Registry"), recursive = TRUE)
  neg("A3 [위반] 레지스트리 부재", RC0, want = "부재")
  RC1 <- file.path(T, "rc_broken"); dir.create(file.path(RC1, "06_Registry"), recursive = TRUE)
  writeLines('{"schema": "overlay_probe_allowlist_v1", "common": {', file.path(RC1, REG_REL))
  neg("A4 [위반] JSON 파손", RC1, want = "파손")
  jc <- fromJSON(REG0, simplifyVector = FALSE); jc$schema <- "overlay_probe_allowlist_v0"
  RC2 <- file.path(T, "rc_schema"); wjson(jc, file.path(RC2, REG_REL))
  neg("A5 [위반] 스키마 불일치", RC2, want = "schema")
  jd <- fromJSON(REG0, simplifyVector = FALSE); jd$widened$calls <- as.list(c(as.character(unlist(jd$widened$calls)), "get"))
  RC3 <- file.path(T, "rc_cap"); wjson(jd, file.path(RC3, REG_REL))
  neg("A6 [위반] 능력 계열(get) 오염 — probe 적재기가 레지스트리를 무효로 본다", RC3, want = "능력 계열")
  fake_probe <- file.path(T, "probe_noloader.R")
  writeLines(c("overlay_probe_arm <- function(kind, root) list(ok = FALSE)", "cat('[fake probe] Loaded\\n')"), fake_probe)
  neg("A7 [위반] 적재기 없는 probe(③d 이전 판)", RA, probe = fake_probe, want = "적재기")
  neg("A8 [위반] probe 파일 부재", RA, probe = file.path(T, "no_such_probe.R"), want = "probe 부재")
  # [인자] 받은 root 를 실제로 쓰는가 — QM_ROOT(원판 RA)와 다른 root(변경판 RB)를 넘기면 변경판이어야 한다(인자 무시 = 원판이 나온다)
  a10 <- render(RB, qm = RA)
  r10 <- rendered_sets(a10$lines, "calls")$calls
  chk(a10$rc == 0L && ADD_NAME %in% r10 && !DEL_NAME %in% r10, "A10 [인자] root 인자를 쓴다 — QM_ROOT=원판 · root=변경판 → 변경판 렌더",
      sprintf("rc=%s add=%s del=%s", a10$rc, ADD_NAME %in% r10, DEL_NAME %in% r10))
  # [정합] 렌더 ⇔ probe 판정 — 같은 이름을 probe 가 받는가
  pe <- new.env(parent = globalenv())
  invisible(capture.output(suppressMessages(sys.source(PROBE, envir = pe))))
  src_of <- function(fn) sprintf("overlay_expo_zz <- function(H, t, ctx) {\n  %s(1)\n}\n", fn)
  scan_ok <- function(fn, root) isTRUE(with_env(c(QM_ROOT = root), pe$overlay_probe_allowlist_scan(src_of(fn), root = root))$ok)
  scan_ok_src <- function(src, root) isTRUE(with_env(c(QM_ROOT = root), pe$overlay_probe_allowlist_scan(src, root = root))$ok)
  sa <- c(add_A = scan_ok(ADD_NAME, RA), add_B = scan_ok(ADD_NAME, RB), del_A = scan_ok(DEL_NAME, RA), del_B = scan_ok(DEL_NAME, RB))
  ra_calls <- rendered_sets(a1$lines, "calls")$calls
  chk(identical(unname(sa), c(ADD_NAME %in% ra_calls, ADD_NAME %in% rsb, DEL_NAME %in% ra_calls, DEL_NAME %in% rsb)) &&
        identical(unname(sa), c(FALSE, TRUE, TRUE, FALSE)),
      sprintf("A9 [정합] 렌더에 있는 이름 ⇔ probe ③d 가 받는 이름 (%s: 원판 거부·변경판 통과 · %s: 원판 통과·변경판 거부)", ADD_NAME, DEL_NAME),
      paste(names(sa), sa, collapse = " "))
  # [정합 2] (적대 검증 수리 2026-09-25) 렌더가 '목록과 무관'이라 적은 열 ⇔ probe R2 판정 — 오라클 = probe 자신(overlay_probe_allowlist_scan)
  #   픽스처 열 전부를 두 형태로 잰다: data.table 안 맨이름(h[, <열>]) · $ 읽기(ctx$hold$<열>). 렌더의 '겹치는 열' = 맨이름 거부 집합이어야 하고
  #   $ 읽기는 전부 통과해야 한다. 겹침 ≥1(비공허 — 표기를 빼는 돌연변이가 살아남지 못하게).
  fxc <- pe$overlay_probe_fixture(); cols <- unique(c(names(fxc$M), names(fxc$hold)))
  ci <- grep("겹치는 열: ", a1$lines, fixed = TRUE)
  coll_r <- if (length(ci) == 1L) ticks(sub("^.*겹치는 열: ", "", a1$lines[ci])) else character(0)
  nse_ok <- vapply(cols, function(cn) scan_ok_src(sprintf("overlay_expo_zz <- function(H, t, ctx) {
  h <- ctx$hold
  x <- h[, %s]
  1
}
", cn), RA), logical(1))
  dol_ok <- vapply(cols, function(cn) scan_ok_src(sprintf("overlay_expo_zz <- function(H, t, ctx) {
  x <- ctx$hold$%s
  1
}
", cn), RA), logical(1))
  chk(length(ci) == 1L && any(!nse_ok) && setequal(coll_r, cols[!nse_ok]) && all(dol_ok),
      sprintf("A11 [정합] 렌더의 '겹치는 열' = probe 가 맨이름으로 거부하는 열(%s) · $ 읽기는 열 %d개 전부 통과", paste(cols[!nse_ok], collapse = ","), length(cols)),
      sprintf("렌더=%s · 맨이름 거부=%s · $ 거부=%s", paste(coll_r, collapse = ","), paste(cols[!nse_ok], collapse = ","), paste(cols[!dol_ok], collapse = ",")))
  # [위반 주입] 참조 이름공간 미설치 — probe 는 판정 불가로 전부 거부한다 → 렌더도 미제공이어야 한다(렌더 ok ⇔ probe 판정 가능)
  jm <- fromJSON(REG0, simplifyVector = FALSE); jm$ref_namespaces <- as.list(c(as.character(unlist(jm$ref_namespaces)), "zzallowp_no_such_pkg"))
  RC4 <- file.path(T, "rc_nsmissing"); wjson(jm, file.path(RC4, REG_REL))
  neg("A12 [위반] 참조 이름공간 미설치(probe 판정 불가)", RC4, want = "미설치")
  sm <- with_env(c(QM_ROOT = RC4), pe$overlay_probe_allowlist_scan(src_of("abs"), root = RC4))
  chk(!isTRUE(sm$ok) && grepl("미설치", as.character(sm$reason %||% "")), "A12 [정합] 같은 레지스트리에서 probe 도 판정 불가(fail-closed)", as.character(sm$reason %||% ""))
}

cat("\n=== B. B5 설계 재료 (7)·(8) ===\n")
SB <- file.path(T, "b5"); JLB <- file.path(T, "jl_b5.jsonl")
for (d in c("06_Registry", ".cache/rf_block_design", "stage_artifacts/l_code/reinforcement", "qepm/memory/axioms/active", "art/T_AL_B1_5"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
cpf("06_Registry/reinforce_program.json", SB); cpf("02_Infrastructure/portfolio/weight_catalog.R", SB)
CFGB <- file.path(SB, "06_Registry/reinforce_auto_config.json")
wjson(list(enabled = TRUE, b5_design = list(enabled = TRUE, max_cells = 8, min_cells = 3, max_new_arms = 3, max_layers = 3, prior_entries = 12,
           guards = list(max_redesign_rounds = 1, daily_arm_cap = 6, stagnation_window = 2, max_active_generated = 40))), CFGB)
arm <- function(id, kind, action = "scalar_exposure", state = "vol") list(id = id, kind = kind, family = "vol_target", basis = "fixture",
                                                                         status = "active", est_cost_min = 1, action = action, state = state)
wjson(list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "x"),
           arms = list(arm("arm_v", "fx_v"), arm("arm_d", "fx_d", "cross_sectional", "drawdown"))), file.path(SB, "06_Registry/overlay_catalog.json"))
writeLines(character(0), file.path(SB, "06_Registry/overlay_arm_ledger.jsonl"))
writeLines(c("date,nav_net", "2005-01-28,1", "2005-02-28,1.1", "2005-03-28,0.9", "2005-04-28,1.2"), file.path(SB, "art/T_AL_B1_5/02_nav.csv"))
att <- function(n) list(n = n, cell_code = sprintf("B1_%d", n), idea = sprintf("[B1_%d] fixture", n),
                        essence = list(cell_code = sprintf("B1_%d", n), block = "B1", port_t = n + 0.5, cagr = 0.2, mdd = 0.5, calmar = 0.4,
                                       oos_retention = 0.5, spec = ""), artifacts = if (n == 5L) file.path(SB, "art/T_AL_B1_5") else NULL)
wjson(list(schema_version = "reinforce_ledger_v2", layer = 1, max_attempts = 25, note = "fixture",
           entries = list(list(base_id = "T_AL", status = "active", base_grade = "C", base_artifacts = "", attempts_used = 5L,
                               attempts = lapply(1:5, att), block_order = list("B1", "B5", "B2", "B3", "B4"))),
           combination_review = list(papers_since_last_review = 0, last_review_date = "", history = list()), last_updated = ""),
      file.path(SB, "06_Registry/reinforce_ledger_l1.json"))
mat <- function(tag) {
  outp <- file.path(T, sprintf("mat_%s.txt", tag)); unlink(c(outp, JLB))
  r <- run(RSCRIPT, c(B5LIB, "materials", "T_AL", outp, "0", "2", "1"),
           c(QVEST_RF_ROOT = SB, QM_ROOT = SB, QVEST_RP_JLOG = JLB, QVEST_RF_CONFIG = CFGB, QVEST_B5_CODE_ROOT = CODE))
  r$lines <- if (file.exists(outp)) gsub("\r", "", readLines(outp, warn = FALSE, encoding = "UTF-8")) else character(0)
  r$jl <- if (file.exists(JLB)) lapply(readLines(JLB, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l), error = function(e) list())) else list()
  r
}
sec_lines <- function(lines, head) {
  i <- which(startsWith(lines, head)); if (length(i) != 1L) return(character(0))
  j <- which(startsWith(lines, "## ") & seq_along(lines) > i); e <- if (length(j)) j[1] - 1L else length(lines)
  lines[i:e]
}
jl_ev <- function(jl, ev) Filter(function(x) identical(x$event, ev), jl)
cpf(REG_REL, SB, REG0)
b1 <- mat("present")
s7 <- sec_lines(b1$lines, "## (7) ")
ih <- which(startsWith(s7, "### 허용 함수 목록 — probe")); ig <- which(startsWith(s7, "### G1 "))
chk(b1$rc == 0L && length(b1$lines) > 0L, "B1 재료 생성 rc 0", paste(b1$rc, utils::tail(b1$out, 3), collapse = " | "))
chk(length(ih) == 1L && length(ig) == 1L && ih < ig, "B1 목록 블록은 (7) 안 · G1 감사 절 앞 (금칙 다음)", sprintf("ih=%s ig=%s", paste(ih, collapse = ","), paste(ig, collapse = ",")))
cmp_block(s7, EXA, "B1 (7)")
ma <- jl_ev(b1$jl, "materials_allowlist")
chk(length(ma) == 1L && identical(ma[[1]]$status, "ok") && isTRUE(as.integer(ma[[1]]$names) == sum(lengths(EXA$sets))) &&
      length(jl_ev(b1$jl, "materials_written")) == 1L,
    "B1 jlog materials_allowlist status=ok · 이름 수 일치 · materials_written 1건", if (length(ma)) paste(ma[[1]]$status, ma[[1]]$names) else "이벤트 없음")
chk(!any(grepl("허용 함수 목록 미제공", b1$lines, fixed = TRUE)), "B1 목록이 있으면 미제공 표기 0 (과잉 경보 아님)")
cpf(REG_REL, SB, file.path(RB, REG_REL))
b2 <- mat("changed")
rs2 <- rendered_sets(sec_lines(b2$lines, "## (7) "), "calls")$calls
chk(b2$rc == 0L && ADD_NAME %in% rs2 && !DEL_NAME %in% rs2, sprintf("B2 [변경] 재료가 레지스트리를 따라간다(+%s · −%s)", ADD_NAME, DEL_NAME))
cmp_block(sec_lines(b2$lines, "## (7) "), EXB, "B2 [변경] (7)")
unlink(file.path(SB, REG_REL))
b3 <- mat("absent")
s7b <- sec_lines(b3$lines, "## (7) "); s8b <- sec_lines(b3$lines, "## (8) ")
chk(b3$rc == 0L && length(b3$lines) > 0L, "B3 [부재] 재료는 쓴다(배합 설계는 목록과 무관 — fail-closed 는 probe 가 진다)", paste(b3$rc, utils::tail(b3$out, 2), collapse = " | "))
chk(any(startsWith(s7b, "### 허용 함수 목록 — 미제공")) && !any(grepl("^- calls — ", s7b)), "B3 [부재] (7) 미제공 블록 · 목록 줄 0")
chk(any(grepl("허용 함수 목록 미제공", s8b, fixed = TRUE)) && any(grepl("새 arm 을 내지 마라", s8b, fixed = TRUE)), "B3 [부재] (8) '새 arm 을 내지 마라' 명시")
ma3 <- jl_ev(b3$jl, "materials_allowlist")
chk(length(ma3) == 1L && identical(ma3[[1]]$status, "unavailable") && nzchar(as.character(ma3[[1]]$why %||% "")) &&
      length(jl_ev(b3$jl, "materials_written")) == 1L,
    "B3 [부재] jlog materials_allowlist status=unavailable + 사유 · 재료 기록(materials_written) 1건", if (length(ma3)) paste(ma3[[1]]$status, ma3[[1]]$why) else "이벤트 없음")

cat("\n=== C. 생성 레인 rf_overlay_propose.sh — 실제 발송 프롬프트 ===\n")
LR <- file.path(T, "lane")
for (rel in c("02_Infrastructure/ops/rf_llm_env.sh", "02_Infrastructure/ops/rf_overlay_ledger_count.py", "02_Infrastructure/ops/rf_overlay_admit_cli.R",
              "02_Infrastructure/reinforcement/rf_mechanism_map.R", "02_Infrastructure/reinforcement/rf_spec_sig.R",
              "02_Infrastructure/reinforcement/rf_block_design.R", "02_Infrastructure/reinforcement/rf_overlay_admit.R",
              "02_Infrastructure/reinforcement/overlay_probe.R", "02_Infrastructure/portfolio/weight_catalog.R",
              "06_Registry/reinforce_program.json")) cpf(rel, LR)
cpf("02_Infrastructure/ops/rf_overlay_propose.sh", LR, LANE)
cpf("02_Infrastructure/reinforcement/overlay_allowlist_prompt.R", LR, RENDERER)
invisible(dir.create(file.path(LR, "02_Infrastructure/reinforcement/overlay_arms"), recursive = TRUE, showWarnings = FALSE))
wjson(list(enabled = TRUE, llm = list(model = "opus", effort = "max", lanes = list(overlay_propose = list(model = "opus", effort = "max")))),
      file.path(LR, "06_Registry/reinforce_auto_config.json"))
wjson(list(schema = "overlay_catalog_v1", note = "fixture", families = list(vol_target = "x"), arms = list(arm("arm_v", "fx_v"))),
      file.path(LR, "06_Registry/overlay_catalog.json"))
wjson(list(schema_version = "reinforce_ledger_v2", layer = 1, max_attempts = 25, note = "fixture", entries = list(),
           combination_review = list(papers_since_last_review = 0, last_review_date = "", history = list()), last_updated = ""),
      file.path(LR, "06_Registry/reinforce_ledger_l1.json"))
STUBD <- file.path(T, "stubbin"); invisible(dir.create(STUBD)); STUB <- file.path(STUBD, "claude")
writeLines(c("#!/usr/bin/env bash", 'cat > "$ALP_STUB_PROMPT"', 'printf "%s\\n" "$*" >> "$ALP_STUB_CALLS"', 'echo "stub: arm 을 쓰지 않았다"', "exit 0"), STUB, useBytes = TRUE)
invisible(Sys.chmod(STUB, "0755"))
lane <- function(tag) {
  jl <- file.path(T, sprintf("jl_lane_%s.jsonl", tag)); pr <- file.path(T, sprintf("prompt_%s.txt", tag)); cl <- file.path(T, sprintf("calls_%s.txt", tag))
  unlink(c(jl, pr, cl, file.path(LR, ".cache")), recursive = TRUE); file.create(cl)
  writeLines(character(0), file.path(LR, "06_Registry/overlay_arm_ledger.jsonl"))
  led0 <- tools::md5sum(file.path(LR, "06_Registry/overlay_arm_ledger.jsonl"))
  for (f in list.files(file.path(LR, "02_Infrastructure/reinforcement/overlay_arms"), full.names = TRUE)) unlink(f)
  r <- run("bash", file.path(LR, "02_Infrastructure/ops/rf_overlay_propose.sh"),
           c(QM_ROOT = LR, QVEST_PY = PYX, QVEST_RP_JLOG = jl, RF_CLAUDE_BIN = STUB, ALP_STUB_PROMPT = pr, ALP_STUB_CALLS = cl,
             PATH = paste(gsub("/", "\\\\", STUBD), Sys.getenv("PATH"), sep = .Platform$path.sep),
             QVEST_RF_ROOT = NA, QVEST_RF_CONFIG = NA, QVEST_OV_MODEL = NA, QVEST_OV_EFFORT = NA, QVEST_OV_DAILY_CAP = NA, QVEST_LLM_FALLBACK = NA))
  r$jl <- if (file.exists(jl)) lapply(readLines(jl, warn = FALSE, encoding = "UTF-8"), function(l) tryCatch(fromJSON(l), error = function(e) list())) else list()
  r$ev <- vapply(r$jl, function(x) as.character(x$event %||% ""), character(1))
  r$prompt <- if (file.exists(pr)) gsub("\r", "", readLines(pr, warn = FALSE, encoding = "UTF-8")) else character(0)
  r$n_calls <- length(readLines(cl, warn = FALSE))
  r$ledger_same <- identical(unname(tools::md5sum(file.path(LR, "06_Registry/overlay_arm_ledger.jsonl"))), unname(led0))
  r$pfiles <- list.files(file.path(LR, "02_Infrastructure/reinforcement/overlay_arms"), pattern = "^prompt_gen_")
  r
}
cpf(REG_REL, LR, REG0)
c1 <- lane("present")
chk("target_picked" %in% c1$ev, "C0 픽스처 — 표적 선정까지 도달(목록 판정 앞 단계 통과)", paste(c1$ev, collapse = ","))
chk(c1$n_calls == 1L && length(c1$prompt) > 0L, "C1 목록이 있으면 LLM 1회 호출 · 프롬프트 포착", sprintf("calls=%d · ev=%s", c1$n_calls, paste(c1$ev, collapse = ",")))
cmp_block(c1$prompt, EXA, "C1 발송 프롬프트")
ia <- which(startsWith(c1$prompt, "### 허용 함수 목록 — probe")); ik <- which(startsWith(c1$prompt, "## 절대 금칙")); ib <- which(startsWith(c1$prompt, "## 본보기"))
chk(length(ia) == 1L && length(ik) == 1L && length(ib) == 1L && ik < ia && ia < ib, "C1 목록 블록은 '절대 금칙' 절 안(본보기 앞)")
chk("allowlist_rendered" %in% c1$ev && !"halt_allowlist_unavailable" %in% c1$ev, "C1 jlog allowlist_rendered · halt 0")
cpf(REG_REL, LR, file.path(RB, REG_REL))
c2 <- lane("changed")
rc2 <- rendered_sets(c2$prompt, "calls")$calls
chk(c2$n_calls == 1L && ADD_NAME %in% rc2 && !DEL_NAME %in% rc2, sprintf("C2 [변경] 다음 실행 프롬프트가 따라간다(+%s · −%s)", ADD_NAME, DEL_NAME))
unlink(file.path(LR, REG_REL))
c3 <- lane("absent")
chk(c3$n_calls == 0L && !length(c3$prompt), "C3 [위반 주입] 레지스트리 부재 → LLM 호출 0", sprintf("calls=%d", c3$n_calls))
chk("halt_allowlist_unavailable" %in% c3$ev && !"model_selected" %in% c3$ev && !"agent_done" %in% c3$ev,
    "C3 [부재] halt_allowlist_unavailable · 모델 선택·에이전트 단계 미도달", paste(c3$ev, collapse = ","))
chk(c3$rc == 0L && c3$ledger_same && !length(c3$pfiles), "C3 [부재] rc 0 · 방출 원장 불변 · 프롬프트 파일 없음", sprintf("rc=%s ledger_same=%s pfiles=%d", c3$rc, c3$ledger_same, length(c3$pfiles)))
cpf(REG_REL, LR, REG0)
writeLines(c("overlay_probe_arm <- function(kind, root) list(ok = FALSE)"), file.path(LR, "02_Infrastructure/reinforcement/overlay_probe.R"))
c4 <- lane("noloader")
chk(c4$n_calls == 0L && "halt_allowlist_unavailable" %in% c4$ev, "C4 [위반 주입] 적재기 없는 probe(③d 이전 판) → LLM 호출 0 · halt", sprintf("calls=%d ev=%s", c4$n_calls, paste(c4$ev, collapse = ",")))
cpf("02_Infrastructure/reinforcement/overlay_probe.R", LR)

cat("\n=== 격리 — 운영 무접촉 ===\n")
chk(identical(unname(tools::md5sum(REAL)), unname(REAL_MD5)), sprintf("운영 레지스트리·원장 %d종 해시 불변", length(REAL)))
chk(identical(sort(list.files(file.path(CODE, "02_Infrastructure/reinforcement/overlay_arms"))), ARMS_LS0), "운영 overlay_arms 목록 불변(프롬프트·arm 파일 0)")
unlink(T, recursive = TRUE, force = TRUE)
finish()
