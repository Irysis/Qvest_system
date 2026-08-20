## test_map_freshness_content.R — 계층 병목 지도 신선도 감시기 2종의 **행동** 검사
## 대상: 02_Infrastructure/memory/memory_knowledge_health.R  (W8, R 구현)
##       02_Infrastructure/hooks/research_continuity_guard.sh (W3, bash+python 구현)
##
## 왜: 두 감시기는 2026-08-20 까지 지도의 **mtime** 을 최신 L-code 시각과 비교했다.
##     mtime 은 touch·헤더 append 만으로 갱신되므로 **판정이 담긴 표 본문이 몇 주째
##     바이트 동일해도 초록**이었다. git 이력 실측(표 본문 sha 추적):
##       · 660f1ce393  2026-08-09 12:49 → 08-17 16:48 = 8일 동결 / 그 사이 커밋 20건
##       · 174f763b12  2026-07-19 13:44 → 08-02 20:32 = 14일 동결 / 커밋 16건
##     그 내내 mtime 은 최신 → W8·W3 둘 다 침묵.
##
## ★이 검사의 본체는 **양방향**이다. 대리지표를 내용 대조로 바꾸면 오탐은 사라지지만
##   검출력까지 같이 죽기 쉽고, **검사 사망과 정상은 겉보기가 같다**(둘 다 초록).
##   그래서 (a) 정상에서 침묵 (b) 일부러 만든 진짜 드리프트에서 발화 를 둘 다 잰다.
## ★그리고 음성 대조는 **자기 조작이 실제로 먹었는지 먼저 증명해야** 결론을 낼 자격이
##   생긴다 — 모든 주입 앞에 [조작 선행검증] 축을 둬서 파일이 의도대로 바뀐 것을
##   해시·mtime 으로 확인한 뒤에만 판정을 읽는다.
## ★구 mtime 판정을 테스트 안에 그대로 재현해 **같은 상태에서 구판은 초록, 신판은 경보**임을
##   보인다(검출력 실증). 이게 없으면 "고쳤다"는 주장에 증거가 없다.
##
## 실행: Rscript 08_Tests/hooks/test_map_freshness_content.R
suppressPackageStartupMessages({ library(jsonlite) })

## ── 자기 위치 우선 (r-portability 금칙④-b: 러너는 self-first) ─────────────────
.args <- commandArgs(trailingOnly = FALSE)
.fa <- grep("^--file=", .args, value = TRUE)
.here <- if (length(.fa)) dirname(normalizePath(sub("^--file=", "", .fa[1]), winslash = "/", mustWork = FALSE)) else getwd()
.root <- normalizePath(file.path(.here, "..", ".."), winslash = "/", mustWork = FALSE)
HEALTH_REL <- "02_Infrastructure/memory/memory_knowledge_health.R"
HOOK_REL   <- "02_Infrastructure/hooks/research_continuity_guard.sh"
if (!file.exists(file.path(.root, HEALTH_REL))) {
  cand <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", ""))
  if (nzchar(cand) && file.exists(file.path(cand, HEALTH_REL))) .root <- normalizePath(cand, winslash = "/", mustWork = FALSE)
}
HEALTH <- file.path(.root, HEALTH_REL)
HOOK   <- file.path(.root, HOOK_REL)
if (!file.exists(HEALTH)) stop(sprintf("감시기 소스를 못 찾음: %s (러너 위치 문제이지 검사 실패가 아님)", HEALTH))
if (!file.exists(HOOK))   stop(sprintf("감시기 소스를 못 찾음: %s", HOOK))

PASS <- 0L; FAIL <- 0L
.m1 <- function(x) { x <- as.character(x); if (!length(x)) "(빈 메시지)" else x[1] }
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s%s\n", n, if (nzchar(.m1(m))) paste0(" — ", .m1(m)) else "")) }
chk <- function(n, cond, m = "") if (isTRUE(cond)) ok(n, m) else bad(n, m)

## ── ① 정본 R 구현(.mf_*)을 **소스에서 잘라내 그대로** 평가 ────────────────────
## 복제본을 만들지 않는다 — 테스트가 검사하는 코드와 운영 코드가 같은 바이트여야 한다.
.hl <- readLines(HEALTH, warn = FALSE, encoding = "UTF-8")
.i0 <- grep('^\\.MF_SCHEMA', .hl)
.i1 <- grep('^cat\\("\\[W8\\]', .hl)
if (!length(.i0) || !length(.i1) || .i1[1] <= .i0[1]) {
  stop("memory_knowledge_health.R 에서 map_freshness_v1 헬퍼 구간을 찾지 못함 — 앵커(.MF_SCHEMA … cat(\"[W8]\") 변경 여부 확인")
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
eval(parse(text = paste(.hl[.i0[1]:(.i1[1] - 1L)], collapse = "\n")), envir = globalenv())
cat(sprintf("[슬라이스] R 정본 헬퍼 %d줄 로드 (%d~%d행)\n", .i1[1] - .i0[1], .i0[1], .i1[1] - 1L))

## ── ② 정본 python 구현을 훅의 heredoc 에서 **그대로** 추출 ────────────────────
.hk <- readLines(HOOK, warn = FALSE, encoding = "UTF-8")
.p0 <- grep("<<'PY'", .hk, fixed = FALSE)
.p1 <- grep("^PY$", .hk)
if (!length(.p0) || !length(.p1)) stop("research_continuity_guard.sh 에서 python heredoc 구간을 찾지 못함")
PYSRC <- paste(.hk[(.p0[1] + 1L):(.p1[length(.p1)] - 1L)], collapse = "\n")
cat(sprintf("[슬라이스] python 정본 훅 본문 %d줄 추출\n", .p1[length(.p1)] - .p0[1] - 1L))

QPY <- Sys.getenv("QVEST_PY", "")
if (!nzchar(QPY) || !file.exists(QPY)) {
  QPY <- file.path(.root, ".venv_qvest_ml/Scripts/python.exe")
}
if (!file.exists(QPY)) stop("QVEST_PY 를 찾을 수 없음 — bare python 은 이 환경에서 스텁이라 검사 불가")

## ── 샌드박스 (native Windows 경로 — MSYS /tmp 은 native python glob 을 0건으로 만든다) ──
SBX <- file.path(.root, ".cache", "_test_map_freshness")
unlink(SBX, recursive = TRUE, force = TRUE)
dir.create(file.path(SBX, "06_Registry"),  recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(SBX, ".cache"),       recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(SBX, "stage_artifacts", "l_code", "rnd"), recursive = TRUE, showWarnings = FALSE)
MAP  <- file.path(SBX, "06_Registry", "layer_bottleneck_map.md")
SNAP <- file.path(SBX, ".cache", "layer_bottleneck_map_content.json")
LC   <- file.path(SBX, "stage_artifacts", "l_code", "rnd", "l_code_test_round.json")
PYF  <- file.path(SBX, "hook_body.py")
writeLines(PYSRC, PYF, useBytes = TRUE)

REAL_MAP <- file.path(.root, "06_Registry/layer_bottleneck_map.md")
if (!file.exists(REAL_MAP)) stop("정본 지도 파일 부재 — 실제 형식으로 검사할 수 없음")
invisible(file.copy(REAL_MAP, MAP, overwrite = TRUE))

NOW <- as.numeric(Sys.time())
set_lcode <- function(age_h) {                 # L-code 의 "연구 시각" = created_at
  ts <- as.POSIXct(NOW - age_h * 3600, origin = "1970-01-01")
  write_json(list(l_code = "L-TEST-MAPFRESH", verdict = "negative",
                  created_at = format(ts, "%Y-%m-%dT%H:%M:%S")),
             LC, auto_unbox = TRUE)
  Sys.setFileTime(LC, ts)                       # mtime 도 같이 (조기중단 경로 정합)
  invisible(ts)
}
set_snapshot_age <- function(age_h) {          # 표 본문이 age_h 전부터 그대로였다고 기록
  if (!file.exists(SNAP)) {                    # 없으면 현재 표로 먼저 생성(부재를 통과로 위장 금지)
    .mf_observed_at(SBX, .mf_table_sha(.mf_table_rows(MAP)), length(.mf_table_rows(MAP)), NOW)
  }
  if (!file.exists(SNAP)) stop("스냅샷 생성 실패 — 테스트 전제 불성립")
  s <- fromJSON(SNAP, simplifyVector = TRUE)
  s$observed_at <- NOW - age_h * 3600
  write_json(s, SNAP, auto_unbox = TRUE)
  invisible(s$table_sha)
}
file_sha  <- function(p) digest::digest(file = p, algo = "sha256")
table_sha <- function(p) .mf_table_sha(.mf_table_rows(p))
mtime_of  <- function(p) as.numeric(file.info(p)$mtime)

## 구(舊) 판정 재현 — 검출력 실증용 대조군. 이 코드는 2026-08-20 이전의 W8/W3 그 자체다.
legacy_stale <- function(map_p, newest_lc_s, thresh_h = 24) {
  lag <- (newest_lc_s - as.numeric(file.info(map_p)$mtime)) / 3600
  isTRUE(is.finite(lag) && lag > thresh_h)
}
legacy_w3_fires <- function(map_p, newest_lc_s) {   # 구 W3 = 0h 임계 + 6h 발화범위
  isTRUE((NOW - newest_lc_s) < 6 * 3600 && newest_lc_s > as.numeric(file.info(map_p)$mtime))
}

## R 정본 판정 실행
r_judge <- function(age_h_lcode) {
  ts <- set_lcode(age_h_lcode)
  .mf_judge(SBX, MAP, ts)
}
## python 정본(훅 본문) 실행 → 메시지 문자열 또는 "{}"
py_hook <- function() {
  out <- suppressWarnings(system2(QPY, c(shQuote(PYF), shQuote(SBX)), stdout = TRUE, stderr = TRUE))
  paste(out, collapse = " ")
}
py_fires <- function(o) !identical(trimws(o), "{}") && grepl("W3", o, fixed = TRUE)
## bash 훅 전체(E2E) 실행
TRANS <- file.path(SBX, "transcript.jsonl")
writeLines('{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}', TRANS)
## ★r-portability 금칙①/⑤: system2(env=) 는 argv 주입이고, system() 문자열의 `VAR=v cmd`
##   접두는 Windows 에서 쉘을 안 거쳐 "명령을 못 찾음"으로 죽는다(이 검사 작성 중 실사고).
##   → Sys.setenv 로 진짜 환경변수를 세우고 원복한다.
e2e_hook <- function() {
  inp <- sprintf('{"hook_event_name":"Stop","transcript_path":"%s","stop_hook_active":false}', TRANS)
  inf <- file.path(SBX, "hook_in.json"); writeLines(inp, inf)
  old <- Sys.getenv("CLAUDE_PROJECT_DIR", unset = NA)
  Sys.setenv(CLAUDE_PROJECT_DIR = SBX)
  on.exit({ if (is.na(old)) Sys.unsetenv("CLAUDE_PROJECT_DIR") else Sys.setenv(CLAUDE_PROJECT_DIR = old) }, add = TRUE)
  out <- suppressWarnings(system2("bash", c(shQuote(HOOK)), stdin = inf, stdout = TRUE, stderr = TRUE))
  paste(out, collapse = " ")
}

################################################################################
cat("\n[A] 표 본문 추출 규칙 — 무엇을 해시하는가 (추측 금지, 실제 개수 확인)\n")
rows <- .mf_table_rows(MAP)
chk("A1_rows_nonzero", length(rows) > 0, sprintf("정본 지도에서 표 행 %d개 추출", length(rows)))
chk("A2_rows_are_14", length(rows) == 14L,
    sprintf("실측 14행 = 계층 표 헤더1+9행 + 재료 표 헤더1+3행 (현재 %d)", length(rows)))
n_layer <- sum(grepl("^\\| *\\**[①-⑨]", rows))
chk("A3_nine_layer_rows", n_layer == 9L, sprintf("계층 행 ①~⑨ %d개가 해시 대상에 포함", n_layer))
chk("A4_no_separator", !any(grepl("^\\|[[:space:]:|-]+\\|[[:space:]]*$", rows)),
    "구분선(|---|---|)은 제외 — 내용이 아님")
chk("A5_no_version_chain", !any(grepl("^\\*\\*갱신\\*\\*", rows)) && !any(startsWith(rows, ">")),
    "버전 체인(**갱신**: vNN)·인용 갱신이력(> ...)은 **제외** — append 로 증식해 대리지표가 재발함")

cat("\n[B] R ↔ python 해시 동치 (복제본 드리프트 차단)\n")
r_sha <- table_sha(MAP)
## 훅 본문은 import 시 top-level 로직까지 도는 스크립트이므로, 해시 규칙만 따로 물어본다.
## (아래 프로브는 훅 본문의 정규식·인코딩·join 규칙을 **문자 그대로** 옮긴 것이며,
##  드리프트하면 G4/G5 상수 검사와 B1 해시 동치가 동시에 깨진다.)
py_probe <- file.path(SBX, "probe_sha.py")
writeLines(c(
  "import sys, re, hashlib",
  "SEP=re.compile(r'^\\|[\\s:|-]+\\|\\s*$'); EOL=re.compile(r'[\\r\\n]+$')",
  "p=sys.argv[1]",
  "lines=open(p,'r',encoding='utf-8',errors='replace').read().split('\\n')",
  "rows=[EOL.sub('',x) for x in lines]",
  "rows=[x for x in rows if x.startswith('|')]",
  "rows=[x for x in rows if not SEP.match(x)]",
  "print(len(rows)); print(hashlib.sha256('\\n'.join(rows).encode('utf-8')).hexdigest())"
), py_probe)
py_out <- suppressWarnings(system2(QPY, c(shQuote(py_probe), shQuote(MAP)), stdout = TRUE, stderr = TRUE))
chk("B1_hash_parity", length(py_out) >= 2 && identical(trimws(py_out[2]), r_sha),
    sprintf("R digest = python hashlib = %s", substr(r_sha, 1, 12)))
chk("B2_rowcount_parity", length(py_out) >= 1 && identical(as.integer(trimws(py_out[1])), length(rows)),
    sprintf("행 수 동치 (%s vs %d)", trimws(py_out[1]), length(rows)))

cat("\n[C] 초기화 — 스냅샷 부재는 경보하지 않는다 (초기화 오탐 방지)\n")
chk("C0_snap_absent", !file.exists(SNAP), "시작 시 스냅샷 없음")
j <- r_judge(1)                                   # L-code 1시간 전
chk("C1_init_creates_snapshot", file.exists(SNAP), "최초 1회는 생성만")
chk("C2_init_no_alarm", identical(j$basis, "content") && !isTRUE(j$stale),
    sprintf("basis=%s stale=%s lag=%.2fh — 최초 관측은 무경보", j$basis, j$stale, j$lag_h))
snap0 <- fromJSON(SNAP, simplifyVector = TRUE)
chk("C3_snapshot_fields", identical(snap0$schema, "map_freshness_v1") &&
      identical(snap0$table_sha, r_sha) && snap0$n_rows == length(rows),
    sprintf("스냅샷 = {schema, table_sha=%s, n_rows=%d, observed_at}", substr(snap0$table_sha, 1, 10), snap0$n_rows))
chk("C4_py_reads_r_snapshot", py_fires(py_hook()) == FALSE,
    "python 이 R 이 쓴 스냅샷을 읽고 같은 결론(무경보) — 교차 read 정합")

################################################################################
cat("\n[D] 정상 — 표를 실제로 갱신하면 경보 없음 (양성 대조)\n")
set_snapshot_age(72)                              # 표가 72h 전부터 그대로였다고 기록
pre_tsha <- table_sha(MAP); pre_fsha <- file_sha(MAP)
mp <- readLines(MAP, warn = FALSE, encoding = "UTF-8")
ix <- grep("^\\| ⑥ ", mp)                     # ⑥ 오버레이/국면 행
if (!length(ix)) ix <- grep("^\\|", mp)[3]
mp[ix[1]] <- paste0(mp[ix[1]], " · TEST-EDIT-", format(Sys.time(), "%H%M%S"))
writeLines(mp, MAP, useBytes = TRUE)
## ★조작 선행검증: 표 본문 해시가 실제로 바뀌었는가?
chk("D0_precheck_table_changed", table_sha(MAP) != pre_tsha && file_sha(MAP) != pre_fsha,
    sprintf("표 행 수정이 실제로 먹음 (%s → %s)", substr(pre_tsha, 1, 8), substr(table_sha(MAP), 1, 8)))
jD <- r_judge(1)
chk("D1_R_silent_after_real_edit", identical(jD$basis, "content") && !isTRUE(jD$stale),
    sprintf("표 본문이 바뀌었으므로 observed_at 재설정 → lag %.2fh, 무경보", jD$lag_h))
chk("D2_py_silent_after_real_edit", !py_fires(py_hook()), "python 훅도 침묵 (판정 동치)")

################################################################################
cat("\n[E] ★위반 주입 A — touch 만 하고 표는 그대로 (구 검사가 초록이던 자리)\n")
set_snapshot_age(72)
pre_tsha <- table_sha(MAP); pre_fsha <- file_sha(MAP); pre_mt <- mtime_of(MAP)
Sys.setFileTime(MAP, Sys.time())                  # = touch
## ★조작 선행검증: mtime 은 바뀌고 내용은 안 바뀌었는가?
chk("E0_precheck_touch_took", mtime_of(MAP) > pre_mt && identical(file_sha(MAP), pre_fsha) &&
      identical(table_sha(MAP), pre_tsha),
    sprintf("mtime %+.1fs 갱신 · 파일 바이트 동일(sha %s) — 진짜 touch", mtime_of(MAP) - pre_mt, substr(pre_fsha, 1, 8)))
ts_lc <- set_lcode(1)
jE <- .mf_judge(SBX, MAP, ts_lc)
chk("E1_R_fires_on_touch", identical(jE$basis, "content") && isTRUE(jE$stale),
    sprintf("★신판 경보: 표 본문이 %.1fh 째 동일 (임계 24h)", jE$lag_h))
chk("E2_legacy_would_be_green", !legacy_stale(MAP, as.numeric(ts_lc)),
    "★검출력 실증: **구 mtime 판정은 같은 상태에서 초록** — touch 한 번으로 계기가 꺼졌다")
outE <- py_hook()
chk("E3_py_fires_on_touch", py_fires(outE), sprintf("python 훅도 발화: %s", substr(outE, 1, 90)))
chk("E4_legacy_w3_would_be_green", !legacy_w3_fires(MAP, as.numeric(ts_lc)),
    "★구 W3(0h 임계 + mtime)도 같은 상태에서 침묵이었다")
outE2 <- e2e_hook()
chk("E5_e2e_bash_hook_fires", grepl("W3", outE2, fixed = TRUE),
    sprintf("bash 훅 전체 경로(E2E)에서도 발화: %s", substr(outE2, 1, 80)))

################################################################################
cat("\n[F] ★위반 주입 B — 헤더/이력 절에만 한 줄 append (표 본문 불변)\n")
set_snapshot_age(72)
pre_tsha <- table_sha(MAP); pre_fsha <- file_sha(MAP)
mp <- readLines(MAP, warn = FALSE, encoding = "UTF-8")
mp <- append(mp, "**갱신**: 2026-08-20 v61 (테스트 주입 — 헤더 부기만, 표 본문 무변경)", after = 4L)
mp <- append(mp, "> ★갱신 2026-08-20 — 이력 절 append (판정 내용 아님)", after = 6L)
writeLines(mp, MAP, useBytes = TRUE)
## ★조작 선행검증: 파일은 바뀌고 표 해시는 그대로인가?
chk("F0_precheck_append_took", file_sha(MAP) != pre_fsha && identical(table_sha(MAP), pre_tsha),
    sprintf("파일 바이트 변경 O / 표 해시 불변 %s — append 가 의도대로 먹음", substr(pre_tsha, 1, 8)))
ts_lc <- set_lcode(1)
jF <- .mf_judge(SBX, MAP, ts_lc)
chk("F1_R_fires_on_append", identical(jF$basis, "content") && isTRUE(jF$stale),
    sprintf("★신판 경보 유지: 헤더 부기는 신선도를 만들지 않는다 (lag %.1fh)", jF$lag_h))
chk("F2_legacy_would_be_green", !legacy_stale(MAP, as.numeric(ts_lc)),
    "★검출력 실증: 구 판정은 초록 (writeLines 가 mtime 을 갱신했으므로)")
chk("F3_py_fires_on_append", py_fires(py_hook()), "python 훅도 발화")
chk("F4_snapshot_not_reset", identical(fromJSON(SNAP, simplifyVector = TRUE)$table_sha, pre_tsha),
    "경보 상태에서 스냅샷이 갱신되지 않는다 — 경보가 자기를 지우지 않음")

################################################################################
cat("\n[G] 경계 — 임계 24h 양쪽 (문턱이 실제로 문턱인가)\n")
set_snapshot_age(72)
ts23 <- set_lcode(0); s <- fromJSON(SNAP, simplifyVector = TRUE)
s$observed_at <- NOW - 23 * 3600; write_json(s, SNAP, auto_unbox = TRUE)
chk("G1_below_threshold_silent", !isTRUE(.mf_judge(SBX, MAP, ts23)$stale), "lag 23h < 24h → 침묵")
s$observed_at <- NOW - 25 * 3600; write_json(s, SNAP, auto_unbox = TRUE)
chk("G2_above_threshold_fires", isTRUE(.mf_judge(SBX, MAP, ts23)$stale), "lag 25h > 24h → 경보")
chk("G3_thresh_constant", identical(.MF_THRESH_H, 24), "R 임계 상수 = 24h")
## ★`24` 를 접두 부분일치로 재면 240 으로 바뀌어도 통과한다(이 검사 작성 중 M2 돌연변이가
##   실제로 그렇게 빠져나갔다). 값 경계까지 고정한다.
chk("G4_py_thresh_same", any(grepl("^\\s*MF_THRESH_H\\s*=\\s*24(\\.0)?\\s*(#.*)?$", strsplit(PYSRC, "\n")[[1]])),
    "python 임계 상수도 정확히 24 — 두 구현이 같은 문턱 (드리프트하면 여기서 잡힘)")
chk("G5_py_schema_same", any(grepl('MF_SCHEMA\\s*=\\s*"map_freshness_v1"', strsplit(PYSRC, "\n")[[1]])),
    "스냅샷 schema 문자열도 동일 — 서로의 스냅샷을 읽는다")

################################################################################
cat("\n[H] 폴백 — 입력 결손 시 죽지 않고 구 동작으로 (회귀 없음)\n")
## H-1 표 본문 0행
map_bak <- readLines(MAP, warn = FALSE, encoding = "UTF-8")
writeLines(grep("^\\|", map_bak, value = TRUE, invert = TRUE), MAP, useBytes = TRUE)
chk("H0_precheck_rows_zero", length(.mf_table_rows(MAP)) == 0L, "★조작 선행검증: 표 행이 실제로 0개가 됨")
jH1 <- .mf_judge(SBX, MAP, set_lcode(1))
chk("H1_fallback_basis_mtime", identical(jH1$basis, "mtime") && grepl("0행", jH1$reason),
    sprintf("basis=mtime 폴백 + 사유 기록: %s", jH1$reason))
chk("H2_fallback_not_silent_pass", !is.na(jH1$lag_h) && is.finite(jH1$lag_h),
    "폴백이 판정을 포기하지 않는다 (구 mtime 판정을 실제로 수행)")
outH <- py_hook()
chk("H3_py_fallback_no_crash", nzchar(outH) && !grepl("Traceback", outH, fixed = TRUE),
    sprintf("python 훅 무크래시 (출력: %s)", substr(trimws(outH), 1, 60)))
writeLines(map_bak, MAP, useBytes = TRUE)

## H-2 스냅샷을 읽지도 쓰지도 못하게 (경로를 디렉토리로 점유)
unlink(SNAP, force = TRUE); dir.create(SNAP, showWarnings = FALSE)
chk("H4_precheck_snap_blocked", dir.exists(SNAP), "★조작 선행검증: 스냅샷 경로가 디렉토리로 점유됨")
jH2 <- .mf_judge(SBX, MAP, set_lcode(1))
chk("H5_snapshot_unwritable_fallback", identical(jH2$basis, "mtime") && grepl("스냅샷", jH2$reason),
    sprintf("스냅샷 불가 → mtime 폴백 (사유: %s)", jH2$reason))
outH2 <- py_hook()
chk("H6_py_snapshot_unwritable_no_crash", !grepl("Traceback", outH2, fixed = TRUE),
    "python 훅도 폴백 (크래시 아님)")
unlink(SNAP, recursive = TRUE, force = TRUE)

## H-3 지도 파일 자체 부재 → 훅은 침묵(기존 fail-open), 크래시 금지
map_keep <- readLines(MAP, warn = FALSE, encoding = "UTF-8"); unlink(MAP, force = TRUE)
chk("H7_precheck_map_absent", !file.exists(MAP), "★조작 선행검증: 지도 파일 실제 삭제됨")
outH3 <- py_hook()
chk("H8_py_map_missing_silent", identical(trimws(outH3), "{}"),
    "지도 부재 → python 훅 침묵 + 무크래시 (구 동작과 동일)")
writeLines(map_keep, MAP, useBytes = TRUE)

## H-4 L-code 없음 → 두 구현 모두 skip
lc_keep <- readLines(LC, warn = FALSE); unlink(LC, force = TRUE)
chk("H9_precheck_lcode_absent", !file.exists(LC), "★조작 선행검증: L-code 실제 삭제됨")
chk("H10_py_no_lcode_silent", identical(trimws(py_hook()), "{}"), "L-code 부재 → 침묵 (구 동작)")
writeLines(lc_keep, LC)

################################################################################
cat("\n[I] L-code 시각 기준 동치 — 실제 원장으로 (조기중단이 결과를 바꾸지 않는가)\n")
## R(W8) 은 전수 파싱, python(W3) 은 mtime 내림차순 조기중단. created_at <= mtime 불변식
## 하에서 동일해야 한다. 실제 494건 원장에서 잰다 — 어긋나면 여기서 잡힌다.
lc_all <- c(Sys.glob(file.path(.root, "stage_artifacts/l_code/*/l_code_*.json")),
            Sys.glob(file.path(.root, "stage_artifacts/l_code_*.json")),
            Sys.glob(file.path(.root, "04_Research/strategies/*/stage_artifacts/[Ll]_code*.json")))
lc_all <- lc_all[!grepl("/superseded/", lc_all, fixed = TRUE)]
if (length(lc_all) == 0) {
  cat("  SKIP: 실제 L-code 원장 비어 있음 (검사 불가 — 위장 통과시키지 않고 스킵으로 기록)\n")
} else {
  .lcrt <- function(f) {
    ca <- tryCatch(fromJSON(f, simplifyVector = FALSE)$created_at, error = function(e) NULL)
    ts <- suppressWarnings(as.POSIXct(sub("T", " ", sub("Z$", "", ca %||% NA_character_)), tz = "", optional = TRUE))
    if (is.null(ca) || is.na(ts)) file.info(f)$mtime else ts
  }
  r_newest <- suppressWarnings(max(do.call(c, lapply(lc_all, .lcrt)), na.rm = TRUE))
  py_newest_probe <- file.path(SBX, "probe_newest.py")
  writeLines(c(
    "import sys, importlib.util as u",
    sprintf("s=u.spec_from_file_location('hb', r'%s')", PYF),
    "src=open(s.origin,'r',encoding='utf-8').read()",
    "ns={'__name__':'hb'}",
    "src=src.split('msgs = []')[0]",
    "exec(compile(src,'hb','exec'), ns)",
    "print('%.3f' % ns['mf_newest_lcode'](sys.argv[1]))"
  ), py_newest_probe)
  pyn <- suppressWarnings(system2(QPY, c(shQuote(py_newest_probe), shQuote(.root)), stdout = TRUE, stderr = TRUE))
  pyv <- suppressWarnings(as.numeric(tail(pyn, 1)))
  chk("I1_newest_lcode_parity", !is.na(pyv) && abs(pyv - as.numeric(r_newest)) < 1.5,
      sprintf("전수 파싱(R) %s ↔ 조기중단(python) %s — 실제 %d건 원장에서 동치",
              format(r_newest, "%Y-%m-%d %H:%M:%S"),
              if (is.na(pyv)) paste(pyn, collapse = " ") else format(as.POSIXct(pyv, origin = "1970-01-01"), "%Y-%m-%d %H:%M:%S"),
              length(lc_all)))
  n_bad <- 0L
  for (f in lc_all) {
    ca <- tryCatch(fromJSON(f, simplifyVector = FALSE)$created_at, error = function(e) NULL)
    if (is.null(ca)) next
    ts <- suppressWarnings(as.POSIXct(sub("T", " ", sub("Z$", "", ca)), tz = "", optional = TRUE))
    if (!is.na(ts) && as.numeric(ts) > as.numeric(file.info(f)$mtime) + 1) n_bad <- n_bad + 1L
  }
  chk("I2_invariant_created_at_le_mtime", n_bad == 0L,
      sprintf("조기중단이 의존하는 불변식 created_at <= mtime 위반 %d건 / %d — 깨지면 python 이 과소보고(fail-open)",
              n_bad, length(lc_all)))
}

################################################################################
cat("\n[K] L-code 열거 규약 — 3-glob + /superseded/ 제외 (열거 드리프트 검거)\n")
## ★왜 [I] 만으로 부족한가: [I] 은 실제 원장에서 두 구현의 **최댓값**만 비교한다. 실제
##   원장의 최신 파일이 마침 첫 glob 에 있으면, python 쪽 glob 을 1개로 좁혀도 최댓값이
##   그대로라 검사가 초록이다 — 이 검사 작성 중 돌연변이 M5 가 실제로 그렇게 빠져나갔다
##   (47/47 통과). 그래서 **최신 파일을 3번째 glob 에 두고**, 그보다 더 새로운 파일을
##   /superseded/ 에 둬서 두 규약이 각각 없으면 답이 달라지도록 판을 짠다.
mk_lc <- function(path, age_h) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ts <- as.POSIXct(NOW - age_h * 3600, origin = "1970-01-01")
  write_json(list(l_code = paste0("L-TEST-", basename(path)),
                  created_at = format(ts, "%Y-%m-%dT%H:%M:%S")), path, auto_unbox = TRUE)
  Sys.setFileTime(path, ts)
  invisible(as.numeric(ts))
}
t_g1 <- mk_lc(LC, 5)                                                            # glob1
t_g2 <- mk_lc(file.path(SBX, "stage_artifacts", "l_code_root.json"), 3)         # glob2
t_g3 <- mk_lc(file.path(SBX, "04_Research", "strategies", "STR_TEST",
                        "stage_artifacts", "l_code_strategy.json"), 0.5)        # glob3 = 최신(정당)
t_ss <- mk_lc(file.path(SBX, "stage_artifacts", "l_code", "superseded",
                        "l_code_old.json"), 0.1)                                # 더 새롭지만 제외 대상
chk("K0_precheck_files", file.exists(LC) &&
      file.exists(file.path(SBX, "stage_artifacts", "l_code_root.json")) &&
      file.exists(file.path(SBX, "04_Research/strategies/STR_TEST/stage_artifacts/l_code_strategy.json")) &&
      file.exists(file.path(SBX, "stage_artifacts/l_code/superseded/l_code_old.json")) &&
      t_ss > t_g3 && t_g3 > t_g2 && t_g2 > t_g1,
    sprintf("★조작 선행검증: 4개 파일이 실제로 놓였고 시각 순서 glob1<glob2<glob3<superseded (%.1f<%.1f<%.1f<%.1f)",
            t_g1, t_g2, t_g3, t_ss))
py_newest_sbx <- file.path(SBX, "probe_newest_sbx.py")
writeLines(c(
  "import sys, importlib.util as u",
  sprintf("src=open(r'%s','r',encoding='utf-8').read().split('msgs = []')[0]", PYF),
  "ns={'__name__':'hb'}",
  "exec(compile(src,'hb','exec'), ns)",
  "print('%.3f' % ns['mf_newest_lcode'](sys.argv[1]))"
), py_newest_sbx)
pk <- suppressWarnings(system2(QPY, c(shQuote(py_newest_sbx), shQuote(SBX)), stdout = TRUE, stderr = TRUE))
pkv <- suppressWarnings(as.numeric(tail(pk, 1)))
chk("K1_third_glob_counted", !is.na(pkv) && abs(pkv - t_g3) < 2,
    sprintf("최신 L-code 가 3번째 glob(04_Research/strategies/*/stage_artifacts/)에 있어도 잡힌다 — 반환 %s",
            if (is.na(pkv)) paste(pk, collapse = " ") else format(as.POSIXct(pkv, origin = "1970-01-01"), "%H:%M:%S")))
chk("K2_superseded_excluded", !is.na(pkv) && abs(pkv - t_ss) > 2,
    "/superseded/ 아래의 더 새로운 기록은 열거에서 제외된다 (필터가 사라지면 여기서 뒤집힘)")
unlink(file.path(SBX, "stage_artifacts", "l_code_root.json"), force = TRUE)
unlink(file.path(SBX, "04_Research"), recursive = TRUE, force = TRUE)
unlink(file.path(SBX, "stage_artifacts", "l_code", "superseded"), recursive = TRUE, force = TRUE)

################################################################################
cat("\n[J] 돌연변이 — 검사 사망 통제 (판정이 정말 내용에서 오는가)\n")
## 표 본문이 아니라 파일 전체를 해시하는 '잘못된 구현' 을 만들어, 그것이 위반 주입 B(헤더
## append)에서 **초록으로 뒤집히는지** 본다. 뒤집히면 [F] 의 PASS 는 대상 선택에서 온 것이다.
set_snapshot_age(72)
mut_fsha_before <- file_sha(MAP); mut_tsha_before <- table_sha(MAP)
mp <- readLines(MAP, warn = FALSE, encoding = "UTF-8")
writeLines(append(mp, "**갱신**: v62 (돌연변이 대조용 헤더 append)", after = 4L), MAP, useBytes = TRUE)
chk("J0_precheck_mutation_input", file_sha(MAP) != mut_fsha_before,
    "★조작 선행검증: 파일 바이트가 실제로 바뀜 (돌연변이 구현이 '변경'으로 읽을 입력)")
## 돌연변이 = "표 본문" 대신 "파일 전체" 를 해시하는 구현. 같은 입력에서 결론이 뒤집혀야
## [F] 의 PASS 가 **해시 대상 선택**에서 온 것임이 증명된다(뒤집히지 않으면 [F] 는 무의미).
mut_says_changed <- !identical(file_sha(MAP), mut_fsha_before)   # → observed_at 재설정 → 초록
real_stale <- isTRUE(.mf_judge(SBX, MAP, set_lcode(1))$stale)
chk("J1_mutation_flips", mut_says_changed && real_stale,
    "파일 전체 해시 구현이면 '변경됨'으로 읽혀 초록이 되는 입력에서, 정본은 경보를 유지")
chk("J2_extraction_is_the_reason", identical(table_sha(MAP), mut_tsha_before),
    sprintf("표 본문 sha 는 헤더 append 에도 불변 (%s) — 갈린 원인이 해시 대상임을 확정",
            substr(mut_tsha_before, 1, 10)))

unlink(SBX, recursive = TRUE, force = TRUE)

cat(sprintf("\nTOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(sprintf('{"test":"map_freshness_content","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
