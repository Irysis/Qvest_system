# test_benchmark_currency_gate.R — BMG-01 위반 주입 테스트 (2026-08-20 신설)
#
# 지키는 것: 거래일 지평선 단일점(.cache/benchmark.parquet)이 얼었을 때 그것이
#   **드러나는가**. 2026-08-14~20 실사고에서는 안 드러났다 — 갱신기가 6일 내내
#   rc≠0 으로 죽었는데 [1pre] 가 fail-soft 라 삼켰고, 하류(Naver/KRX)는 얼어붙은
#   캘린더를 정직하게 읽어 "gap 0" 을 보고했으며, 리프레시는 매일 "실패 0" 으로 끝났다.
#
# ★이 검사의 핵심은 게이트가 **진짜 위반에 빨개지는가**이다. 주입 없이 초록은 무의미하다.
#
# 실행: Rscript 08_Tests/data/test_benchmark_currency_gate.R

suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)
GATE <- file.path(ROOT, "02_Infrastructure/data/benchmark_currency_gate.R")
RSCRIPT <- file.path(R.home("bin"), "Rscript")

PASS <- 0L; FAIL <- 0L
chk <- function(name, cond, detail = "") {
  if (isTRUE(cond)) { PASS <<- PASS + 1L; cat(sprintf("  PASS  %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s %s\n", name, detail)) }
}

TD <- file.path(tempdir(), paste0("bmg_", as.integer(runif(1, 1e6, 9e6))))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)

# 픽스처: max(Date) 를 원하는 값으로 갖는 최소 benchmark parquet
make_bm <- function(max_date, n = 30L) {
  p <- file.path(TD, sprintf("bm_%s.parquet", gsub("-", "", format(max_date))))
  d <- data.table(Date = seq(as.Date(max_date) - (n - 1L), as.Date(max_date), by = "day"),
                  Close = runif(n, 900, 1100))
  write_parquet(d, p); p
}

run_gate <- function(..., today, path, max_lag = NULL, rc = NULL) {
  a <- c(GATE, "--today", format(today), "--path", path, "--quiet")
  if (!is.null(max_lag)) a <- c(a, "--max-lag-days", as.character(max_lag))
  if (!is.null(rc))      a <- c(a, "--updater-rc", as.character(rc))
  out <- suppressWarnings(system2(RSCRIPT, args = c("--no-save", a), stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status"); if (is.null(st)) st <- 0L
  list(status = as.integer(st), out = paste(out, collapse = "\n"))
}

TODAY <- as.Date("2026-08-20")

cat("=== 양성 대조 (게이트가 상시-빨강이 아님을 먼저 확인) ===\n")
fresh <- make_bm(TODAY)
r <- run_gate(today = TODAY, path = fresh, rc = 0)
chk("P1 최신 파일 + 갱신기 정상 → exit 0", r$status == 0L, sprintf("(status=%d)", r$status))

cat("\n=== 위반 주입 A — 갱신기 사망 (하드 축) ===\n")
r <- run_gate(today = TODAY, path = fresh, rc = 1)
chk("A1 파일은 최신인데 갱신기 rc=1 → exit 1", r$status == 1L, sprintf("(status=%d)", r$status))
chk("A2 사유에 A축이 명시됨", grepl("A:", r$out, fixed = TRUE), "")
r <- run_gate(today = TODAY, path = fresh, rc = 127)
chk("A3 rc=127(실행기 부재)도 잡힘", r$status == 1L, sprintf("(status=%d)", r$status))

cat("\n=== 위반 주입 B — 파일 정체 (늦은 그물) ===\n")
stale <- make_bm(TODAY - 30L)
r <- run_gate(today = TODAY, path = stale, rc = 0)
chk("B1 30일 정체 → exit 1", r$status == 1L, sprintf("(status=%d)", r$status))
chk("B2 사유에 B축이 명시됨", grepl("B:", r$out, fixed = TRUE), "")

cat("\n=== 경계 (문턱이 실제로 그 자리에 있는가) ===\n")
r7 <- run_gate(today = TODAY, path = make_bm(TODAY - 7L), max_lag = 7, rc = 0)
chk("E1 lag==문턱(7) → 통과", r7$status == 0L, sprintf("(status=%d)", r7$status))
r8 <- run_gate(today = TODAY, path = make_bm(TODAY - 8L), max_lag = 7, rc = 0)
chk("E2 lag==문턱+1(8) → 차단", r8$status == 1L, sprintf("(status=%d)", r8$status))

cat("\n=== 파일 부재 ===\n")
r <- run_gate(today = TODAY, path = file.path(TD, "does_not_exist.parquet"), rc = 0)
chk("M1 benchmark 부재 → exit 1", r$status == 1L, sprintf("(status=%d)", r$status))

cat("\n=== ★실사고 재현 — 'B축이 이 사고를 못 잡는다'를 박제 ===\n")
# 2026-08-14 동결 → 08-20 발견 = lag 6일. 기본 문턱 7 에서 B 는 통과한다.
incident <- make_bm(as.Date("2026-08-14"))
rb <- run_gate(today = TODAY, path = incident, max_lag = 7, rc = 0)
chk("I1 실사고 lag=6 은 B축(문턱7)으로 **통과** — 이 축을 방어선으로 읽지 말 것",
    rb$status == 0L, sprintf("(status=%d — 여기가 1이면 문턱이 바뀐 것이니 주석도 고칠 것)", rb$status))
ra <- run_gate(today = TODAY, path = incident, max_lag = 7, rc = 1)
chk("I2 같은 상황에서 A축(rc=1)은 **잡는다** — 실제 방어선",
    ra$status == 1L, sprintf("(status=%d)", ra$status))

unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== test_benchmark_currency_gate: %d PASS / %d FAIL ===\n", PASS, FAIL))
cat(sprintf('{"test":"benchmark_currency_gate","pass":%d,"fail":%d,"skipped":0,"total":%d}\n',
            PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
