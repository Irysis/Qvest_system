#==============================================================================
# test_rf_overlay_admit_source.R — 등재 출처(source) 기록 + 일간 상한이 레인 몫만 세는가 (v10.4 2026-09-17)
#
# 대상: rf_overlay_admit.R(source 인자) · rf_overlay_admit_cli.R(6번째 인자/QVEST_ARM_SOURCE) ·
#       rf_overlay_ledger_count.py(레인 몫 집계) · rf_overlay_propose.sh(배선)
# ★왜: 일간 상한은 원장에서 "오늘 방출 수" 를 센다. 출처가 안 남으면 세션 수동 등재·B5 설계 레인의
#   방출 1건이 그날 레인을 halt_daily_cap 으로 죽인다. 출처는 **원장과 카탈로그 양쪽**에 남아야 하고,
#   집계는 overlay_propose + 필드 부재(구판) 만 레인 몫으로 세야 한다.
# 격리: 샌드박스 루트(.cache/_test_…/<pid>)에 probe·admit·weight_catalog 사본 + 빈 카탈로그·원장 —
#   운영 원장·카탈로그에는 한 줄도 쓰지 않는다. 종료 시 샌드박스 삭제.
#==============================================================================
suppressMessages({ library(jsonlite); library(data.table) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
PY   <- Sys.getenv("QVEST_PY", file.path(ROOT, ".venv_qvest_ml/Scripts/python.exe"))
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }

# ── 샌드박스 루트 ──────────────────────────────────────────────────────────────
SB <- file.path(ROOT, ".cache", sprintf("_test_rf_overlay_admit_source_%d", Sys.getpid()))
unlink(SB, recursive = TRUE)
for (d in c("02_Infrastructure/reinforcement/overlay_arms", "02_Infrastructure/portfolio", "06_Registry"))
  dir.create(file.path(SB, d), recursive = TRUE, showWarnings = FALSE)
.cleanup <- function() unlink(SB, recursive = TRUE)
for (f in c("02_Infrastructure/reinforcement/overlay_probe.R", "02_Infrastructure/reinforcement/rf_overlay_admit.R",
            "02_Infrastructure/portfolio/weight_catalog.R",
            "06_Registry/overlay_probe_future.json"))   # ★P0-09(2026-09-24) probe ④ 설정 — CLI 자식은 QM_ROOT=SB 라 정본 폴백이 없다
  stopifnot(file.copy(file.path(ROOT, f), file.path(SB, f), overwrite = TRUE))
CAT <- file.path(SB, "06_Registry/overlay_catalog.json")
LED <- file.path(SB, "06_Registry/overlay_arm_ledger.jsonl")
write(toJSON(list(schema = "overlay_catalog_v1", note = "test sandbox",
                  families = list(vol_target = "검사 픽스처 계열"), arms = list()),
             auto_unbox = TRUE, pretty = TRUE, null = "null"), CAT)
ADIR <- file.path(SB, "02_Infrastructure/reinforcement/overlay_arms")
mk_arm <- function(kind, id, bad = FALSE) {
  body <- if (bad) c(
    sprintf("overlay_expo_%s <- function(H, t, ctx) {", kind),
    "  if (format(ctx$date, \"%Y\") >= \"2008\") return(0.5)",   # 달력 리터럴 → probe 거부
    "  1", "}") else c(
    sprintf("overlay_expo_%s <- function(H, t, ctx) {", kind),
    "  h <- H$rv60[is.finite(H$rv60)]",
    "  if (length(h) < 24L) return(1)",
    "  v <- H$rv60[t]",
    "  if (!is.finite(v) || v <= 0) return(1)",
    "  max(0, min(1, stats::median(h) / v))",
    "}")
  writeLines(body, file.path(ADIR, paste0(kind, ".R")))
  write(toJSON(list(id = id, family = "vol_target", state = "vol",
                    basis = "확장창 중앙 변동성 대비 현재 변동성 — 검사 픽스처", est_cost_min = 1),
               auto_unbox = TRUE), file.path(ADIR, paste0(kind, ".arm.json")))
}
last_rec <- function() { ln <- readLines(LED, warn = FALSE); ln <- ln[nzchar(ln)]; fromJSON(ln[length(ln)], simplifyVector = FALSE) }
cat_entry <- function(id) { cd <- fromJSON(CAT, simplifyVector = FALSE)
  z <- Filter(function(a) identical(as.character(a$id), id), cd$arms); if (length(z)) z[[1]] else NULL }

suppressMessages(source(file.path(SB, "02_Infrastructure/reinforcement/rf_overlay_admit.R")))

cat("=== A. R API — source 가 원장·카탈로그 양쪽에 남는다 ===\n")
mk_arm("zz_src_a", "zz_src_a_v1")
r <- rf_overlay_admit("zz_src_a", target = list(action = "scalar_exposure", state = "vol"),
                      n_siblings = 1L, generator_model = "stub", root = SB)
rec <- last_rec(); ce <- cat_entry("zz_src_a_v1")
if (isTRUE(r$ok) && identical(rec$source, "overlay_propose") && identical(ce$source, "overlay_propose"))
  ok("A1 기본 source = overlay_propose (원장 + 카탈로그)") else
  ng("A1", sprintf("ok=%s ledger=%s catalog=%s", r$ok, rec$source %||% "NULL", ce$source %||% "NULL"))
mk_arm("zz_src_b", "zz_src_b_v1")
r <- rf_overlay_admit("zz_src_b", target = list(action = "scalar_exposure", state = "vol"),
                      n_siblings = 1L, generator_model = "stub", root = SB, source = "manual_session")
rec <- last_rec(); ce <- cat_entry("zz_src_b_v1")
if (isTRUE(r$ok) && identical(rec$source, "manual_session") && identical(ce$source, "manual_session"))
  ok("A2 source = manual_session 이 원장·카탈로그에 그대로") else
  ng("A2", sprintf("ledger=%s catalog=%s", rec$source %||% "NULL", ce$source %||% "NULL"))
mk_arm("zz_src_c", "zz_src_c_v1", bad = TRUE)
r <- rf_overlay_admit("zz_src_c", target = list(action = "scalar_exposure", state = "vol"),
                      n_siblings = 1L, generator_model = "stub", root = SB, source = "b5_design")
rec <- last_rec()
if (!isTRUE(r$ok) && identical(rec$kind, "zz_src_c") && identical(rec$source, "b5_design") && !isTRUE(rec$probe$ok))
  ok("A3 거부된 방출도 원장에 source 와 함께 남는다(패자를 숨기지 않는다)") else
  ng("A3", sprintf("ok=%s kind=%s source=%s", r$ok, rec$kind %||% "NULL", rec$source %||% "NULL"))
if (is.null(cat_entry("zz_src_c_v1"))) ok("A4 거부된 arm 은 카탈로그에 없다") else ng("A4 거부 arm 이 등재됐다")
r <- rf_overlay_admit("zz_src_a", target = list(action = "scalar_exposure", state = "vol"),
                      n_siblings = 1L, generator_model = "stub", root = SB, source = "")
rec <- last_rec()
if (identical(rec$source, "overlay_propose")) ok("A5 빈 source 는 기본값으로 떨어진다") else ng("A5", rec$source %||% "NULL")

cat("\n=== B. CLI — 6번째 인자 · QVEST_ARM_SOURCE · 4/5인자 호환 ===\n")
CLI <- file.path(ROOT, "02_Infrastructure/ops/rf_overlay_admit_cli.R")
# ★자식 Rscript 는 ~/.Renviron 의 QM_ROOT 로 **상속 환경변수를 덮는다**(2026-09-17 실측 — 첫 판이 그 구멍으로
#   운영 원장에 픽스처 5줄을 박았다). 샌드박스 전용 .Renviron 을 R_ENVIRON_USER 로 물려 자식이 샌드박스를 루트로 읽게 한다.
SB_RENV <- file.path(SB, ".Renviron")
writeLines(c(sprintf("QM_ROOT=%s", SB), sprintf("QVEST_PY=%s", PY)), SB_RENV)
run_cli <- function(args, env_src = NULL) {
  old_re <- Sys.getenv("R_ENVIRON_USER", unset = NA); Sys.setenv(R_ENVIRON_USER = SB_RENV)
  if (is.null(env_src)) Sys.unsetenv("QVEST_ARM_SOURCE") else Sys.setenv(QVEST_ARM_SOURCE = env_src)
  on.exit({ if (is.na(old_re)) Sys.unsetenv("R_ENVIRON_USER") else Sys.setenv(R_ENVIRON_USER = old_re)
            Sys.unsetenv("QVEST_ARM_SOURCE") }, add = TRUE)
  system2("Rscript", c(shQuote(CLI), args), stdout = NULL, stderr = NULL)
}
# 사전 확인 — 자식이 실제로 샌드박스를 루트로 읽는가. 아니면 CLI 절은 **실행하지 않고** 실패로 적는다(운영 오염 방지).
.child_root <- {
  old_re <- Sys.getenv("R_ENVIRON_USER", unset = NA); Sys.setenv(R_ENVIRON_USER = SB_RENV)
  o <- tryCatch(system2("Rscript", c("-e", shQuote("cat(Sys.getenv('QM_ROOT'))")), stdout = TRUE, stderr = FALSE),
                error = function(e) "")
  if (is.na(old_re)) Sys.unsetenv("R_ENVIRON_USER") else Sys.setenv(R_ENVIRON_USER = old_re)
  trimws(paste(o, collapse = ""))
}
CLI_OK <- identical(normalizePath(.child_root, winslash = "/", mustWork = FALSE), normalizePath(SB, winslash = "/", mustWork = FALSE))
if (CLI_OK) ok("B0 자식 Rscript 가 샌드박스를 QM_ROOT 로 읽는다(~/.Renviron 우회)") else
  ng("B0 자식 루트가 샌드박스가 아니다 — CLI 절 건너뜀(운영 오염 방지)", .child_root)
if (!CLI_OK) run_cli <- function(args, env_src = NULL) 99L
mk_arm("zz_src_d", "zz_src_d_v1")
rc <- run_cli(c("zz_src_d", "scalar_exposure", "vol", "stub"))
rec <- last_rec()
if (identical(as.integer(rc), 0L) && identical(rec$kind, "zz_src_d") && identical(rec$source, "overlay_propose"))
  ok("B1 4인자 호출 그대로 돈다 · source 기본값") else ng("B1", sprintf("rc=%s source=%s", rc, rec$source %||% "NULL"))
mk_arm("zz_src_e", "zz_src_e_v1")
rc <- run_cli(c("zz_src_e", "scalar_exposure", "vol", "stub", "1", "b5_design"))
rec <- last_rec(); ce <- cat_entry("zz_src_e_v1")
if (identical(as.integer(rc), 0L) && identical(rec$source, "b5_design") && identical(ce$source, "b5_design"))
  ok("B2 6번째 인자 source=b5_design → 원장·카탈로그") else ng("B2", sprintf("rc=%s source=%s", rc, rec$source %||% "NULL"))
mk_arm("zz_src_f", "zz_src_f_v1")
rc <- run_cli(c("zz_src_f", "scalar_exposure", "vol", "stub", "1"), env_src = "manual_session")
rec <- last_rec()
if (identical(as.integer(rc), 0L) && identical(rec$source, "manual_session"))
  ok("B3 5인자 + QVEST_ARM_SOURCE → 환경변수가 출처") else ng("B3", sprintf("rc=%s source=%s", rc, rec$source %||% "NULL"))
mk_arm("zz_src_g", "zz_src_g_v1")
rc <- run_cli(c("zz_src_g", "scalar_exposure", "vol", "stub", "1", "arg_src"), env_src = "env_src")
rec <- last_rec()
if (identical(as.integer(rc), 0L) && identical(rec$source, "arg_src"))
  ok("B4 인자와 환경변수가 둘 다 있으면 인자가 이긴다") else ng("B4", sprintf("rc=%s source=%s", rc, rec$source %||% "NULL"))
mk_arm("zz_src_h", "zz_src_h_v1", bad = TRUE)
rc <- run_cli(c("zz_src_h", "scalar_exposure", "vol", "stub", "1", "b5_design"))
if (identical(as.integer(rc), 3L)) ok("B5 거부 = rc 3 (구판 종료 코드 계약 유지)") else ng("B5", sprintf("rc=%s", rc))

cat("\n=== C. 일간 상한 집계 — 레인 몫(overlay_propose + 필드 부재)만 센다 ===\n")
CNT <- file.path(ROOT, "02_Infrastructure/ops/rf_overlay_ledger_count.py")
today <- "2026-09-17"
fx <- file.path(SB, "fixture_ledger.jsonl")
recs <- list(
  list(record_type = "arm_emission", kind = "k1", emitted_at = paste0(today, "T09:00:00+0900"), source = "overlay_propose"),
  list(record_type = "arm_emission", kind = "k2", emitted_at = paste0(today, "T10:00:00+0900")),                      # 구판(필드 부재)
  list(record_type = "arm_emission", kind = "k3", emitted_at = paste0(today, "T11:00:00+0900"), source = "manual_session"),
  list(record_type = "arm_emission", kind = "k4", emitted_at = paste0(today, "T12:00:00+0900"), source = "b5_design"),
  list(record_type = "arm_emission", kind = "k5", emitted_at = "2026-09-16T12:00:00+0900", source = "overlay_propose"),  # 어제
  list(record_type = "other",        kind = "k6", emitted_at = paste0(today, "T13:00:00+0900"), source = "overlay_propose"))
writeLines(c(vapply(recs, function(r) as.character(toJSON(r, auto_unbox = TRUE)), character(1)), "", "{not json"), fx)
cnt <- function(...) { o <- system2(PY, c(shQuote(CNT), ...), stdout = TRUE, stderr = FALSE)
  suppressWarnings(as.integer(gsub("[^0-9]", "", tail(o, 1)))) }
n <- cnt(shQuote(fx), today)
if (identical(n, 2L)) ok("C1 오늘 6건 중 레인 몫 2건(overlay_propose 1 + 구판 1) — manual/b5/어제/타 레코드 제외 ★핵심") else
  ng("C1", sprintf("n=%s", n))
n <- cnt(shQuote(fx), today, "overlay_propose,b5_design")
if (identical(n, 3L)) ok("C2 source 집합 인자로 다른 레인 몫도 셀 수 있다") else ng("C2", sprintf("n=%s", n))
n <- cnt(shQuote(file.path(SB, "nope.jsonl")), today)
if (identical(n, 0L)) ok("C3 원장 부재 = 0 (상한 판정이 인프라 오류로 레인을 죽이지 않는다)") else ng("C3", sprintf("n=%s", n))
n <- cnt(shQuote(LED), format(Sys.Date(), "%Y-%m-%d"))
# 위 A·B 에서 오늘 샌드박스 원장에 실린 레인 몫 = A1·A5·B1 (overlay_propose) 3건. manual/b5/arg/env 는 제외.
if (identical(n, 3L)) ok("C4 실제 등재기가 쓴 원장에서도 레인 몫만 3건") else ng("C4", sprintf("n=%s", n))

cat("\n=== D. 레인 배선 ===\n")
lane <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_propose.sh"), warn = FALSE), collapse = "\n")
if (grepl("rf_overlay_ledger_count.py", lane, fixed = TRUE) && !grepl("startswith(d)", lane, fixed = TRUE))
  ok("D1 일간 상한이 집계 파일을 태우고 인라인 사본이 남지 않았다") else ng("D1 인라인 집계 잔존 또는 미배선")
if (grepl("rf_overlay_admit_cli.R\" \"\\$KIND\" \"\\$ACT\" \"\\$ST\" \"\\$RP_MODEL\" 1 overlay_propose", lane))
  ok("D2 레인이 등재기에 source=overlay_propose 를 명시한다") else ng("D2 source 미명시")
rc <- system2("bash", c("-n", shQuote(file.path(ROOT, "02_Infrastructure/ops/rf_overlay_propose.sh"))), stdout = NULL, stderr = NULL)
if (identical(as.integer(rc), 0L)) ok("D3 레인 문법") else ng("D3 bash -n 실패")

# ── 운영 파일 무오염 ───────────────────────────────────────────────────────────
real_led <- file.path(ROOT, "06_Registry/overlay_arm_ledger.jsonl")
if (!any(grepl("zz_src_", readLines(real_led, warn = FALSE), fixed = TRUE)) &&
    !any(grepl("zz_src_", readLines(file.path(ROOT, "06_Registry/overlay_catalog.json"), warn = FALSE), fixed = TRUE)))
  ok("E1 운영 원장·카탈로그에 검사 픽스처 0") else ng("E1 운영 파일 오염 ★")
.cleanup()
if (!dir.exists(SB)) ok("E2 샌드박스 삭제") else ng("E2 샌드박스 잔존")

cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_overlay_admit_source","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
