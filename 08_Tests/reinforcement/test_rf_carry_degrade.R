## 승계 arm 강등 판정 — rac_degrade_plan · rac_gate · rac_gate_apply · 장부 신뢰 분모/귀속
## 실사고 ① 2026-09-04: 1라운드 승자 비중 lean:cvar 가 소형주 유니버스에서 커버리지 77% 로 막혀 B3_11 이 두 번 죽고
##   미측정으로 남았다. 시험 축이 아닌 승계 비중은 EW 로 강등해 측정한다.
## 실사고 ② 2026-09-13 (2002.06975 promo3): B4_21/22/25 가 lean:hrp × KQ150 "커버리지 76.6%" 로 통째 미측정.
##   (a) B4 가 강등 제외였고 (b) 재개 경로가 장부를 안 읽어 첫 조우 칸엔 출구가 없었고 (c) 76.6% 자체가
##   유니버스 지지구간 착시였다(분모 수리는 test_rf_arm_coverage_basis.R). 여기서는 (a)(b)와 장부 쪽을 잰다.
## ★합성 픽스처만 — 운영 원장·장부·격자 무접촉(임시 root · 부작용 주입).
## 실행: QM_ROOT=<저장소> Rscript --no-environ 08_Tests/reinforcement/test_rf_carry_degrade.R
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
cat(sprintf("ROOT = %s\n", ROOT))   # ~/.Renviron 의 QM_ROOT 가 셸 값을 덮는다 — 무엇을 재는지 먼저 찍는다
P <- 0L; F <- 0L
ok <- function(m) { P <<- P + 1L; cat(sprintf("  ok   %s\n", m)) }
ng <- function(m, d = "") { F <<- F + 1L; cat(sprintf("  NG   %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_arm_compat.R"), local = TRUE))

spec <- list(factors = list(list(kind = "db", id = "S01_Size")),
             weighting = list(kind = "catalog", catalog_id = "lean:cvar", label = "cvar"),
             universe = list(kind = "smallcap"))
blocked <- "weight:lean:cvar x smallcap - 앞서 커버리지로 막힌 조합(B3_11, 77%)"
attr(blocked, "arm") <- "weight:lean:cvar"

# 격자 B4 형태의 합성 형제 칸 + 같은 use 를 가진 다른 블록 미끼(형제 탐색이 블록을 넘으면 안 된다)
B4_CELLS <- list(
  list(code = "B4_21", block = "B4", combo = list(use = list("B1", "B2", "B3", "B5"))),
  list(code = "B4_22", block = "B4", combo = list(use = list("B2", "B3", "B5"))),
  list(code = "B4_23", block = "B4", combo = list(use = list("B1", "B3", "B5"))),
  list(code = "B4_24", block = "B4", combo = list(use = list("B1", "B2", "B5"))),
  list(code = "B4_25", block = "B4", combo = list(use = list("B1", "B2", "B3"))))
DECOY <- list(code = "ZZ_9", block = "B3", combo = list(use = list("B1", "B3", "B5")))
CELLS <- c(list(DECOY), B4_CELLS)

# 엔진 가드 문자열 형식 그대로 (rf_cell_engine.R — 채널 대조는 test_rf_arm_coverage_basis.R F 절이 실제 산출로 잰다)
MSG_W  <- function(arm, pct = 63.6, hit = 128L, try = 201L)
  sprintf("[rf_cell_engine] arm %s 커버리지 %.1f%% (<80%%) [basis=sel_dates %d/%d] — 침묵 부분측정 금지", arm, pct, hit, try)
MSG_LEGACY <- "[rf_cell_engine] arm lean:hrp 커버리지 76.6% (<80%) — 침묵 부분측정 금지"   # 09-13 원장 lessons 원문 형식
MSG_OV <- "[rf_cell_engine] overlay multivar_channel_tilt 종목 커버리지 0.55 < 0.80 [basis=held_rows] — arm 이 보유를 못 덮었다."
mk_root <- function() {
  r <- file.path(tempdir(), sprintf("rac_%d_%s", Sys.getpid(), paste(sample(letters, 8), collapse = "")))
  dir.create(file.path(r, "06_Registry"), recursive = TRUE, showWarnings = FALSE); r
}
# 러너와 같은 절단(③ detail = substr(.err, 1, 160))을 거쳐 기록한다
rec_fail <- function(sp, msg, root, cell = "T") rac_record(sp, "coverage_fail", root, detail = substr(msg, 1, 160), cell = cell)
SPEC_B4_21 <- list(code = "B4_21", block = "B4",
                   factors = list(list(kind = "db", id = "M01_Mom_12_1")),
                   weighting = list(kind = "catalog", catalog_id = "lean:hrp", label = "hrp"),
                   universe = list(kind = "index", flag = "KQ150"),
                   overlay = list(kind = "multivar_channel_tilt", arm_id = "multivar_channel_tilt"))

cat("=== A. 시험 축이 아닌 블록에서 승계 비중 → EW 강등 ===\n")
for (bk in c("B3", "B1", "B5")) {
  r <- rac_degrade_plan(spec, bk, blocked)
  if (isTRUE(r$degrade) && identical(r$spec$weighting$kind, "ew") &&
      identical(r$spec$carry_degraded$from, "weight:lean:cvar") && identical(r$spec$carry_degraded$to, "ew"))
    ok(sprintf("A %s 강등 · carry_degraded 기록", bk)) else
    ng(sprintf("A %s", bk), sprintf("degrade=%s kind=%s", r$degrade, r$spec$weighting$kind %||% "?"))
}
cat("\n=== B. 자기 축(B2)은 강등하지 않는다 (그 arm 이 처치 자체다) ===\n")
r <- rac_degrade_plan(spec, "B2", blocked)
if (!isTRUE(r$degrade) && identical(r$spec$weighting$catalog_id, "lean:cvar") && is.null(r$spec$carry_degraded))
  ok("B B2 강등 없음 · spec 불변") else ng("B B2 가 강등됐다")

cat("\n=== B4. 결합 블록은 강등한다 — '−비중' 동치 칸을 기록 (2026-09-13) ===\n")
r <- rac_degrade_plan(spec, "B4", blocked, combo_use = list("B1", "B2", "B3", "B5"), siblings = B4_CELLS)
cd <- r$spec$carry_degraded
if (isTRUE(r$degrade) && identical(r$spec$weighting$kind, "ew") && identical(cd$block, "B4") &&
    identical(cd$loo_equivalent, "B4_23") && identical(unlist(cd$combo_use), c("B1", "B2", "B3", "B5")) &&
    grepl("B4_23", cd$reading %||% "", fixed = TRUE))
  ok("B4-1 전결합(B4_21) → EW 강등 · loo_equivalent=B4_23 · combo_use · reading 기록") else
  ng("B4-1 전결합 강등", sprintf("degrade=%s eq=%s", r$degrade, cd$loo_equivalent %||% "-"))
r <- rac_degrade_plan(spec, "B4", blocked, combo_use = list("B2", "B3", "B5"), siblings = B4_CELLS)
if (isTRUE(r$degrade) && is.null(r$spec$carry_degraded$loo_equivalent) && nzchar(r$spec$carry_degraded$reading %||% ""))
  ok("B4-2 −팩터 칸(B4_22) → 강등 · 동치 형제 없음(−팩터−비중 은 격자에 없는 새 구성)") else
  ng("B4-2 −팩터 칸", sprintf("eq=%s", r$spec$carry_degraded$loo_equivalent %||% "-"))
r <- rac_degrade_plan(spec, "B4", blocked, combo_use = list("B1", "B2", "B3", "B5"), siblings = list(B4_CELLS[[1]]))
if (isTRUE(r$degrade) && is.null(r$spec$carry_degraded$loo_equivalent))
  ok("B4-3a 형제 목록에 '−비중' 칸이 없으면 동치를 지어내지 않는다") else ng("B4-3a 없는 동치를 기록")
r <- rac_degrade_plan(spec, "B4", blocked, combo_use = list("B1", "B2", "B3", "B5"), siblings = list(DECOY, B4_CELLS[[1]]))
if (isTRUE(r$degrade) && is.null(r$spec$carry_degraded$loo_equivalent))
  ok("B4-3b 같은 use 를 가진 **다른 블록** 칸은 동치가 아니다(순수 함수 자체 방어)") else
  ng("B4-3b 블록을 넘어 동치를 기록", r$spec$carry_degraded$loo_equivalent %||% "-")
ob <- "overlay:csd_idio x KQ150"; attr(ob, "arm") <- "overlay:csd_idio"
if (!isTRUE(rac_degrade_plan(SPEC_B4_21, "B4", ob, combo_use = list("B1", "B2", "B3", "B5"), siblings = B4_CELLS)$degrade))
  ok("B4-4 B4 에서도 오버레이 arm 차단은 강등 대상이 아니다") else ng("B4-4 B4 오버레이가 강등됨")

cat("\n=== C. 오버레이 arm · attr 없음 · 미지 블록 → 강등 없음 ===\n")
if (!isTRUE(rac_degrade_plan(spec, "B3", ob)$degrade)) ok("C 오버레이 arm 은 강등 대상이 아니다") else ng("C 오버레이가 강등됨")
if (!isTRUE(rac_degrade_plan(spec, "B3", "no attr")$degrade)) ok("C attr 없는 사유는 강등 안 함") else ng("C attr 없이 강등")
if (!isTRUE(rac_degrade_plan(spec, "ZZ", blocked)$degrade)) ok("C 미지 블록은 강등 안 함") else ng("C 미지 블록 강등")

cat("\n=== D. 원본 spec 불변 (함수형) ===\n")
r <- rac_degrade_plan(spec, "B3", blocked)
if (identical(spec$weighting$catalog_id, "lean:cvar") && is.null(spec$carry_degraded)) ok("D 입력 spec 은 그대로") else ng("D 입력 spec 이 변경됨")

cat("\n=== E. 장부 — 신뢰 분모 · 귀속 (임시 root) ===\n")
if (grepl("[basis=sel_dates", substr(MSG_W("gen:lean_score_tilt__shr_ledoit_wolf"), 1, 160), fixed = TRUE))
  ok("E0 가장 긴 arm id 에서도 표식이 러너 절단(160자) 안에 든다") else ng("E0 표식이 절단에 잘린다")
tmp <- mk_root()
rec_fail(spec, MSG_W("lean:cvar"), tmp, cell = "B3_11")
b <- rac_blocked(spec, tmp)
if (!is.null(b) && identical(attr(b, "arm"), "weight:lean:cvar") && identical(attr(b, "basis"), "sel_dates"))
  ok("E1 신뢰 분모 기록은 차단 — 사유에 arm·basis 속성") else
  ng("E1 신뢰 기록 미차단", sprintf("blocked=%s", if (is.null(b)) "NULL" else "str"))
r2 <- rac_degrade_plan(spec, "B3", b)
if (isTRUE(r2$degrade) && is.null(rac_blocked(r2$spec, tmp))) ok("E2 강등 후 spec 은 장부에 더 안 걸린다 (EW 는 arm 이 아니다)") else ng("E2 강등 후에도 차단")

tmpL <- mk_root()
rec_fail(SPEC_B4_21, MSG_LEGACY, tmpL, cell = "B4_25")
L <- fromJSON(file.path(tmpL, "06_Registry/rf_arm_compat.json"), simplifyVector = FALSE)$entries
hrpL <- Filter(function(e) identical(e$arm, "weight:lean:hrp"), L)
if (is.null(rac_blocked(SPEC_B4_21, tmpL)) && length(hrpL) == 1L && identical(hrpL[[1]]$basis, "legacy"))
  ok("E3 구 분모(표식 없음) 기록은 차단 근거가 아니다 — 파일엔 basis=legacy 이력으로 남는다") else
  ng("E3 구 분모 기록", sprintf("blocked=%s n=%d", !is.null(rac_blocked(SPEC_B4_21, tmpL)), length(hrpL)))
# 이전 판(basis 필드 자체가 없는) 기록 — 운영 장부 09-13 이전 행과 같은 형태
tmpO <- mk_root()
writeLines(toJSON(list(schema = "rf_arm_compat_v1", entries = list(list(arm = "weight:lean:hrp", universe = "index:KQ150",
  status = "coverage_fail", detail = MSG_LEGACY, cell = "B4_25", observed_at = "2026-09-13T22:14:08+0900"))),
  auto_unbox = TRUE, pretty = TRUE), file.path(tmpO, "06_Registry/rf_arm_compat.json"))
if (is.null(rac_blocked(SPEC_B4_21, tmpO))) ok("E4 basis 필드가 없는 구 행도 차단 근거가 아니다") else ng("E4 구 행이 여전히 차단")

tmpA <- mk_root()
n_w <- rec_fail(SPEC_B4_21, MSG_W("lean:hrp"), tmpA, cell = "B4_21")
A <- fromJSON(file.path(tmpA, "06_Registry/rf_arm_compat.json"), simplifyVector = FALSE)$entries
arms <- vapply(A, function(e) e$arm, character(1))
if (identical(arms, "weight:lean:hrp") && identical(as.integer(n_w), 1L))
  ok("E5 귀속 — 비중 arm 실패는 그 비중 쌍만 기록(오버레이 쌍 무기록)") else
  ng("E5 귀속 실패", paste(arms, collapse = ","))
tmpV <- mk_root()
rec_fail(SPEC_B4_21, MSG_OV, tmpV, cell = "B4_21")
V <- fromJSON(file.path(tmpV, "06_Registry/rf_arm_compat.json"), simplifyVector = FALSE)$entries
if (identical(vapply(V, function(e) e$arm, character(1)), "overlay:multivar_channel_tilt") &&
    identical(V[[1]]$basis, "held_rows") && !is.null(rac_blocked(SPEC_B4_21, tmpV)))
  ok("E6 귀속 — 오버레이 가드 실패는 그 오버레이 쌍만(basis=held_rows · 차단 근거)") else
  ng("E6 오버레이 귀속", paste(vapply(V, function(e) e$arm, character(1)), collapse = ","))
tmpN <- mk_root()
if (identical(as.integer(rec_fail(SPEC_B4_21, MSG_W("lean:nco"), tmpN)), 0L) &&
    !file.exists(file.path(tmpN, "06_Registry/rf_arm_compat.json")))
  ok("E7 사유가 지목한 arm 이 spec 에 없으면 아무것도 기록하지 않는다(지어내지 않음)") else ng("E7 없는 arm 을 기록")
sp_ov1 <- list(weighting = list(kind = "ew"), overlay = list(kind = "vol_scale"))
e8 <- tryCatch({ length(rac_pairs(sp_ov1)) }, error = function(e) conditionMessage(e))
if (identical(e8, 0L)) ok("E8 arm_id 없는 단수 오버레이 — 던지지 않고 쌍 0(구판은 `$` 오류를 러너가 '차단 없음' 으로 삼켰다)") else
  ng("E8 단수 오버레이", as.character(e8))

cat("\n=== G. 관문 rac_gate — 등록·재개 공용 판정 ===\n")
tmpG <- mk_root()
rec_fail(SPEC_B4_21, MSG_W("lean:hrp"), tmpG, cell = "B4_21")
g <- rac_gate(SPEC_B4_21, "B4", tmpG, combo_use = B4_CELLS[[1]]$combo$use, siblings = B4_CELLS)
if (identical(g$action, "run") && isTRUE(g$degraded) && identical(g$spec$weighting$kind, "ew") &&
    identical(g$spec$carry_degraded$loo_equivalent, "B4_23") &&
    identical(g$spec$overlay, SPEC_B4_21$overlay) && identical(g$spec$universe, SPEC_B4_21$universe) &&
    identical(g$spec$factors, SPEC_B4_21$factors))
  ok("G1 B4_21 hrp×KQ150 차단 → 측정(run) · 비중만 EW · 팩터·유니버스·오버레이 불변 · 동치 B4_23") else
  ng("G1 B4 출구", sprintf("action=%s degraded=%s", g$action, g$degraded))
SPEC_B2 <- modifyList(SPEC_B4_21, list(code = "B2_7", block = "B2", overlay = NULL))
g2 <- rac_gate(SPEC_B2, "B2", tmpG)
if (identical(g2$action, "close") && identical(attr(g2$reason, "arm"), "weight:lean:hrp") && identical(g2$spec, SPEC_B2))
  ok("G2 B2 자기 축 차단 → close (판정 · spec 불변)") else ng("G2 B2", g2$action)
SPEC_OK <- modifyList(SPEC_B4_21, list(weighting = list(kind = "catalog", catalog_id = "lean:ivol", label = "ivol")))
g3 <- rac_gate(SPEC_OK, "B4", tmpG, combo_use = B4_CELLS[[1]]$combo$use, siblings = B4_CELLS)
if (identical(g3$action, "run") && !isTRUE(g3$degraded) && identical(g3$spec, SPEC_OK))
  ok("G3 정상 arm(기록 없음) → run · spec 비트 동일 · 강등 없음") else ng("G3 정상 arm 이 바뀌었다", g3$action)
g4 <- rac_gate(SPEC_B4_21, "B4", tmpL, combo_use = B4_CELLS[[1]]$combo$use, siblings = B4_CELLS)
if (identical(g4$action, "run") && !isTRUE(g4$degraded) && identical(g4$spec, SPEC_B4_21))
  ok("G4 구 분모 기록만 있으면 → run · 강등 없음(원래 조합 그대로 측정)") else ng("G4 구 기록이 판정을 바꿨다", g4$action)
tmpG5 <- mk_root()
rec_fail(SPEC_B4_21, MSG_W("lean:hrp"), tmpG5, cell = "B4_21")
rec_fail(SPEC_B4_21, MSG_OV, tmpG5, cell = "B4_21")
g5 <- rac_gate(SPEC_B4_21, "B4", tmpG5, combo_use = B4_CELLS[[1]]$combo$use, siblings = B4_CELLS)
if (identical(g5$action, "close") && identical(attr(g5$reason, "arm"), "overlay:multivar_channel_tilt"))
  ok("G5 강등해도 오버레이 쌍이 막혀 있으면 → close(사유 = 오버레이)") else ng("G5", sprintf("%s / %s", g5$action, attr(g5$reason, "arm") %||% "-"))
g6 <- rac_gate(SPEC_OK, "B4", mk_root(), combo_use = B4_CELLS[[1]]$combo$use, siblings = B4_CELLS)
if (identical(g6$action, "run") && identical(g6$spec, SPEC_OK)) ok("G6 장부 파일 없음 → run · spec 불변") else ng("G6 빈 장부")

cat("\n=== H. 관문 적용 rac_gate_apply — 칸이 측정 경로로 가고 강등이 spec·로그에 남는가 (부작용 주입) ===\n")
calls <- new.env(); calls$rec <- list(); calls$log <- list()
REC <- function(n, ...) calls$rec[[length(calls$rec) + 1L]] <- c(list(n = n), list(...))
LOG <- function(event, ...) calls$log[[length(calls$log) + 1L]] <- c(list(event = event), list(...))
reset <- function() { calls$rec <- list(); calls$log <- list() }
put_spec <- function(s, root) { p <- file.path(root, sprintf("spec_%s.json", s$code))
  writeLines(toJSON(s, auto_unbox = TRUE, pretty = TRUE, null = "null"), p); p }

reset(); spH <- put_spec(SPEC_B4_21, tmpG)
aH <- rac_gate_apply(SPEC_B4_21, spH, B4_CELLS[[1]], 21L, "resume", cells = CELLS, root = tmpG, record_fn = REC, log_fn = LOG)
onDisk <- fromJSON(spH, simplifyVector = FALSE)
lg <- Filter(function(z) identical(z$event, "carry_degraded"), calls$log)
if (identical(aH, "run") && !length(calls$rec) && identical(onDisk$weighting$kind, "ew") &&
    identical(onDisk$carry_degraded$from, "weight:lean:hrp") && identical(onDisk$carry_degraded$loo_equivalent, "B4_23") &&
    length(lg) == 1L && identical(lg[[1]]$path, "resume") && identical(lg[[1]]$loo_equivalent, "B4_23"))
  ok("H1 재개 경로 B4_21 → run(측정) · spec 파일에 EW+carry_degraded 기록 · carry_degraded 로그(path=resume) · 원장 종결 없음") else
  ng("H1 재개 출구", sprintf("action=%s rec=%d kind=%s log=%d", aH, length(calls$rec), onDisk$weighting$kind %||% "?", length(lg)))

reset(); spB <- put_spec(SPEC_B2, tmpG)
aB <- rac_gate_apply(SPEC_B2, spB, list(code = "B2_7", block = "B2"), 7L, "register", cells = CELLS, root = tmpG, record_fn = REC, log_fn = LOG)
if (identical(aB, "closed") && length(calls$rec) == 1L && isTRUE(calls$rec[[1]]$terminal) &&
    startsWith(calls$rec[[1]]$grade, "NA (미결 — arm×유니버스 양립 불가)") && !file.exists(spB) &&
    any(vapply(calls$log, function(z) identical(z$event, "cell_arm_incompatible"), logical(1))))
  ok("H2 등록 경로 B2 자기 축 → closed · 원장 NA terminal 1회 · spec 삭제 · cell_arm_incompatible 로그") else
  ng("H2 등록 종결", sprintf("action=%s rec=%d spec_exists=%s", aB, length(calls$rec), file.exists(spB)))

reset(); spB2 <- put_spec(SPEC_B2, tmpG)
aB2 <- rac_gate_apply(SPEC_B2, spB2, list(code = "B2_7", block = "B2"), 7L, "resume", cells = CELLS, root = tmpG, record_fn = REC, log_fn = LOG)
if (identical(aB2, "closed") && length(calls$rec) == 1L && file.exists(spB2))
  ok("H3 재개 경로 종결은 두 번째 백테를 태우지 않고 닫되 spec 은 사후 추적용으로 둔다") else
  ng("H3 재개 종결", sprintf("action=%s spec_exists=%s", aB2, file.exists(spB2)))

reset(); spN <- put_spec(SPEC_OK, tmpG); before <- readBin(spN, "raw", file.info(spN)$size)
aN <- rac_gate_apply(SPEC_OK, spN, B4_CELLS[[1]], 21L, "resume", cells = CELLS, root = tmpG, record_fn = REC, log_fn = LOG)
after <- readBin(spN, "raw", file.info(spN)$size)
if (identical(aN, "run") && identical(before, after) && !length(calls$rec) && !length(calls$log))
  ok("H4 정상 arm → run · spec 파일 바이트 동일 · 원장·로그 호출 0") else
  ng("H4 정상 arm 에서 무언가 바뀌었다", sprintf("action=%s rec=%d log=%d same=%s", aN, length(calls$rec), length(calls$log), identical(before, after)))

reset(); bad <- modifyList(SPEC_OK, list(universe = "not-a-list"))
aE <- rac_gate_apply(bad, file.path(tmpG, "nope.json"), B4_CELLS[[1]], 21L, "register", cells = CELLS, root = tmpG, record_fn = REC, log_fn = LOG)
if (identical(aE, "run") && !length(calls$rec) &&
    any(vapply(calls$log, function(z) identical(z$event, "arm_compat_gate_failed"), logical(1))))
  ok("H5 판정 고장은 차단 사유가 아니다 → run(엔진 가드가 최종선) · arm_compat_gate_failed 로그") else
  ng("H5 판정 고장", sprintf("action=%s rec=%d", aE, length(calls$rec)))

reset(); DEC_SIB <- list(DECOY, B4_CELLS[[1]])   # 형제 목록에 '−비중' use 를 가진 칸이 **다른 블록**에만 있다
spD <- put_spec(SPEC_B4_21, tmpG)
invisible(rac_gate_apply(SPEC_B4_21, spD, B4_CELLS[[1]], 21L, "resume", cells = DEC_SIB, root = tmpG, record_fn = REC, log_fn = LOG))
if (is.null(fromJSON(spD, simplifyVector = FALSE)$carry_degraded$loo_equivalent))
  ok("H6 동치 형제 탐색은 같은 블록 안에서만 — 다른 블록 칸을 동치로 적지 않는다") else ng("H6 블록을 넘어 동치를 기록")

cat("\n=== I. 교훈 표식 rac_degrade_note ===\n")
nt <- rac_degrade_note(g$spec$carry_degraded)
if (grepl("weight:lean:hrp→EW", nt, fixed = TRUE) && grepl("B4_23", nt, fixed = TRUE) && identical(rac_degrade_note(NULL), ""))
  ok(sprintf("I 교훈 머리 표식: %s", nt)) else ng("I 표식", nt)

cat("\n=== J. 러너 배선 — 두 경로가 같은 관문을 부르는가 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE, encoding = "UTF-8")
i_rs <- grep('jlog("resume_pending"', src, fixed = TRUE)
i_rg <- grep("사전 등록 (순차", src, fixed = TRUE)
calls_src <- grep(".rac_gate_apply(", src, fixed = TRUE)
res_call <- calls_src[grepl('"resume"', src[calls_src], fixed = TRUE)]
reg_call <- calls_src[grepl('"register"', src[calls_src], fixed = TRUE)]
if (length(i_rs) == 1L && length(i_rg) == 1L && length(res_call) == 1L && res_call > i_rs && res_call < i_rg)
  ok("J1 재개 블록 안에서 관문 호출(path=resume)") else
  ng("J1 재개 경로 관문 배선", sprintf("resume_pending@%s 등록@%s call@%s", paste(i_rs, collapse = ","), paste(i_rg, collapse = ","), paste(res_call, collapse = ",")))
if (length(reg_call) == 1L && length(i_rg) == 1L && reg_call > i_rg) ok("J2 등록 경로 관문 호출(path=register)") else
  ng("J2 등록 경로 관문 배선", paste(reg_call, collapse = ","))
if (!any(grepl("rac_degrade_plan(SPEC, CELL$block, .rac)", src, fixed = TRUE)) &&
    !any(grepl('grade = "NA (미결 — arm×유니버스 양립 불가)"', src, fixed = TRUE)))
  ok("J3 구 인라인 판정·종결이 러너에 남아 있지 않다(정본 = rf_arm_compat::rac_gate_apply)") else
  ng("J3 구 인라인 경로 잔존 — 두 경로가 갈라질 수 있다")
if (any(grepl("rac_degrade_note(", src, fixed = TRUE))) ok("J4 수집 절이 강등 표식을 원장 교훈 머리에 붙인다") else ng("J4 교훈 표식 배선 없음")

cat(sprintf("\n== test_rf_carry_degrade: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
