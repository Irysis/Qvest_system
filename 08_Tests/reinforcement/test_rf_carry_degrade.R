## 승계 arm 강등 판정 — rac_degrade_plan (2026-09-04)
## 실사고: 1라운드 승자 비중 lean:cvar 가 소형주 유니버스에서 커버리지 77% 로 막혀 B3_11 이 두 번 죽고
##   미측정으로 남았다. 시험 축이 아닌 승계 비중은 EW 로 강등해 측정한다. 자기 축·B4·오버레이는 강등 없음.
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
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

cat("=== A. 시험 축이 아닌 블록에서 승계 비중 → EW 강등 ===\n")
for (bk in c("B3", "B1", "B5")) {
  r <- rac_degrade_plan(spec, bk, blocked)
  if (isTRUE(r$degrade) && identical(r$spec$weighting$kind, "ew") &&
      identical(r$spec$carry_degraded$from, "weight:lean:cvar") && identical(r$spec$carry_degraded$to, "ew"))
    ok(sprintf("A %s 강등 · carry_degraded 기록", bk)) else
    ng(sprintf("A %s", bk), sprintf("degrade=%s kind=%s", r$degrade, r$spec$weighting$kind %||% "?"))
}
cat("\n=== B. 자기 축·결합 블록은 강등하지 않는다 (그게 판정이다) ===\n")
for (bk in c("B2", "B4")) {
  r <- rac_degrade_plan(spec, bk, blocked)
  if (!isTRUE(r$degrade) && identical(r$spec$weighting$catalog_id, "lean:cvar"))
    ok(sprintf("B %s 강등 없음 · spec 불변", bk)) else ng(sprintf("B %s 가 강등됐다", bk))
}
cat("\n=== C. 오버레이 arm · attr 없음 → 강등 없음 ===\n")
ob <- "overlay:csd_idio x smallcap"; attr(ob, "arm") <- "overlay:csd_idio"
if (!isTRUE(rac_degrade_plan(spec, "B3", ob)$degrade)) ok("C 오버레이 arm 은 강등 대상이 아니다") else ng("C 오버레이가 강등됨")
if (!isTRUE(rac_degrade_plan(spec, "B3", "no attr")$degrade)) ok("C attr 없는 사유는 강등 안 함") else ng("C attr 없이 강등")
if (!isTRUE(rac_degrade_plan(spec, "ZZ", blocked)$degrade)) ok("C 미지 블록은 강등 안 함") else ng("C 미지 블록 강등")

cat("\n=== D. 원본 spec 불변 (함수형) ===\n")
r <- rac_degrade_plan(spec, "B3", blocked)
if (identical(spec$weighting$catalog_id, "lean:cvar") && is.null(spec$carry_degraded)) ok("D 입력 spec 은 그대로") else ng("D 입력 spec 이 변경됨")

cat("\n=== E. rac_blocked 가 arm 속성을 붙이는가 (임시 장부) ===\n")
tmp <- file.path(tempdir(), sprintf("rac_%d", Sys.getpid())); dir.create(file.path(tmp, "06_Registry"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, ".cache"), recursive = TRUE, showWarnings = FALSE)
e1 <- tryCatch({ rac_record(spec, "coverage_fail", tmp, detail = "커버리지 77%", cell = "B3_11"); NULL }, error = function(e) conditionMessage(e))
if (is.null(e1)) {
  b <- tryCatch(rac_blocked(spec, tmp), error = function(e) NULL)
  if (!is.null(b) && identical(attr(b, "arm"), "weight:lean:cvar")) ok("E rac_blocked 사유에 arm 속성") else
    ng("E arm 속성 없음", sprintf("blocked=%s attr=%s", if (is.null(b)) "NULL" else "str", attr(b, "arm") %||% "-"))
  r2 <- rac_degrade_plan(spec, "B3", b)
  if (isTRUE(r2$degrade) && is.null(tryCatch(rac_blocked(r2$spec, tmp), error = function(e) "err")))
    ok("E 강등 후 spec 은 장부에 더 안 걸린다 (EW 는 arm 이 아니다)") else ng("E 강등 후에도 차단")
} else ng("E rac_record 임시 root 실패", e1)
unlink(tmp, recursive = TRUE, force = TRUE)

cat("\n=== F. 러너가 순수 함수를 부르고 그 뒤에야 닫는가 ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), warn = FALSE, encoding = "UTF-8")
i1 <- grep("rac_degrade_plan(SPEC, CELL$block, .rac)", src, fixed = TRUE)
i2 <- grep('grade = "NA (미결 — arm×유니버스 양립 불가)"', src, fixed = TRUE)
if (length(i1) == 1L && length(i2) >= 1L && i1 < min(i2)) ok("F 러너: 강등 판정 → 미결 종결 순서") else
  ng("F 러너 배선", sprintf("plan@%s close@%s", paste(i1, collapse = ","), paste(i2, collapse = ",")))
if (any(grepl('jlog("carry_degraded"', src, fixed = TRUE))) ok("F 강등이 로그에 남는다") else ng("F carry_degraded 로그 없음")

cat(sprintf("\n== test_rf_carry_degrade: %d pass · %d fail ==\n", P, F))
if (F > 0L) quit(status = 1L)
