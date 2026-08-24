# test_ladder_pool_entry.R — 강화 프로세스의 풀 진입 계약 (v9.21 §2-a + §2-e)
#
# 대상: 02_Infrastructure/ops/reinforce_ladder.R
#         · 중간 arm 차단     (QVEST_LEAN_REGISTER=0 을 job env 로 전달)
#         · 최종 승자 등재    (rl_register_winner)
#       02_Infrastructure/alpha_search/run_alpha_search.R:433 (킬스위치 소비 지점)
#
# 왜 이 시험이 본체인가:
#   막는 것과 여는 것이 **한 쌍**이다. 막기만 배포하면 강화 산출물이 전략 로테이션 풀에
#   영원히 못 들어가고(Track2 소비원 2개에 2단계 자리가 없다), 열기만 하면 중간 arm 이
#   오버레이 큐로 새서 ③칸이 자기 산출을 먹는다(자기입력 루프 · 헤더 위험 R3).
#   ⇒ 두 방향을 **같은 검사기**에서 본다. 한쪽만 초록인 상태를 통과로 읽지 않기 위해서다.
#
# ★그리고 "차단됐다"는 주장은 **차단 전 판에서 실제로 새는 것을 보여야** 성립한다.
#   축 (C) 돌연변이 통제가 그 역할이다 — env 를 빼면 킬스위치 소비 조건이 뒤집힌다.

suppressPackageStartupMessages({ library(jsonlite) })

PASS <- 0L; FAIL <- 0L; SKIP <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  PASS ", m, "\n") }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L; cat("  FAIL ", m, " :: ", d, "\n") }
sk <- function(a, r, mi) { SKIP <<- SKIP + 1L
  SKIPS[[length(SKIPS) + 1L]] <<- list(axis = a, reason = r, missing = mi)
  cat("  SKIP ", a, " — ", r, "\n") }
emit <- function() {
  cat(sprintf("\nTOTAL: %d pass / %d fail / %d skipped\n", PASS, FAIL, SKIP))
  j <- sprintf('{"test":"ladder_pool_entry","pass":%d,"fail":%d,"total":%d,"skipped":%d',
               PASS, FAIL, PASS + FAIL, SKIP)
  if (SKIP > 0L) j <- paste0(j, ',"skips":[', paste(vapply(SKIPS, function(s)
    sprintf('{"axis":"%s","reason":"%s","missing":"%s"}', s$axis, s$reason, s$missing),
    character(1)), collapse = ","), "]")
  cat(paste0(j, "}\n")); quit(save = "no", status = if (FAIL > 0L) 1L else 0L)
}

# ── 앵커: 자기 트리 우선 ([[feedback-code-root-is-not-data-root]]) ──────────
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
ROOT <- normalizePath(file.path(.self, "..", ".."), winslash = "/", mustWork = FALSE)
RL   <- file.path(ROOT, "02_Infrastructure", "ops", "reinforce_ladder.R")
RAS  <- file.path(ROOT, "02_Infrastructure", "alpha_search", "run_alpha_search.R")
BMP  <- file.path(ROOT, "02_Infrastructure", "regime", "build_module_performance.R")

cat("=== ladder pool entry (v9.21) ===\n")
if (!file.exists(RL)) { sk("ladder_present", "reinforce_ladder.R 부재", RL); emit() }
rl <- readLines(RL, warn = FALSE); J <- paste(rl, collapse = "\n")

# ══ A. 중간 arm 차단 (§2-a) ═════════════════════════════════════════════════
cat("\n── A. 중간 arm 차단 ────────────────────────────────────────\n")

# A1 — 킬스위치 소비 지점이 실재하는가 (신설이 아니라 기존 것을 쓴다는 주장의 근거)
if (file.exists(RAS)) {
  ras <- paste(readLines(RAS, warn = FALSE), collapse = "\n")
  if (grepl('Sys.getenv("QVEST_LEAN_REGISTER", "1"), "0"', ras, fixed = TRUE))
    ok("킬스위치 소비 지점 실재 — run_alpha_search 가 QVEST_LEAN_REGISTER=0 에 반응") else
    ng("★킬스위치 소비 지점 부재 — env 를 넘겨도 아무 일도 안 일어난다")
} else sk("A1_killswitch_consumer", "run_alpha_search.R 부재", RAS)

# A2 — alpha_search kind job **전부**가 env 로 차단을 넘기는가
#   ★"어느 하나라도 빠지면" 그 칸이 샌다. 개수를 세는 게 아니라 **누락 0**을 단언한다.
job_lines <- grep('kind = "alpha_search"', rl)
if (!length(job_lines)) {
  ng("★alpha_search job 생성부를 못 찾음 — 검사 전제 붕괴")
} else {
  leaky <- integer(0)
  for (i in job_lines) {
    blk <- paste(rl[i:min(i + 22L, length(rl))], collapse = "\n")
    blk <- sub("\\), st\\$jobs_dir.*$", "", blk)          # job list 범위로 절단
    if (!grepl('QVEST_LEAN_REGISTER = "0"', blk, fixed = TRUE)) leaky <- c(leaky, i)
  }
  if (!length(leaky))
    ok(sprintf("alpha_search job %d개 전부 QVEST_LEAN_REGISTER=0 전달 (누락 0)", length(job_lines))) else
    ng("★차단 누락 job 존재 — 그 칸은 module_quarantine 으로 샌다",
       paste(sprintf("line %d", leaky), collapse = ", "))
}

# A3 — overlay kind 도 방어적으로 걸려 있는가
oi <- grep('kind = "overlay"', rl)
if (length(oi)) {
  blk <- paste(rl[oi[1]:min(oi[1] + 20L, length(rl))], collapse = "\n")
  if (grepl('QVEST_LEAN_REGISTER = "0"', blk, fixed = TRUE))
    ok("overlay job 도 차단 전달 (③칸은 큐를 소비하므로 같은 회차 쓰기 금지)") else
    ng("★overlay job 미차단")
} else ng("★overlay job 생성부 미발견")

# A4 — ★돌연변이 통제: env 를 빼면 소비 조건이 실제로 뒤집히는가
#   이게 없으면 A1~A3 는 "문자열이 있다"만 재고, 차단력을 재지 않는다.
#   ★반드시 함수 안에서 한다 — r-portability 금칙 ②: 스크립트 최상위 `on.exit` 은
#     함수 프레임이 없어 **조용히 no-op** 이다(정상종료/error/quit 3경로 전부 미발화 실측).
#     즉 최상위에 쓰면 env 복원이 아예 실행되지 않고 테스트가 환경을 오염시킨다.
.probe_killswitch <- function() {
  old <- Sys.getenv("QVEST_LEAN_REGISTER", unset = NA)
  on.exit({ if (is.na(old)) Sys.unsetenv("QVEST_LEAN_REGISTER") else
              Sys.setenv(QVEST_LEAN_REGISTER = old) }, add = TRUE)
  gate <- function() !identical(Sys.getenv("QVEST_LEAN_REGISTER", "1"), "0")  # run_alpha_search:433 자구
  Sys.setenv(QVEST_LEAN_REGISTER = "0"); blocked <- !gate()
  Sys.unsetenv("QVEST_LEAN_REGISTER");   opened  <-  gate()
  list(blocked = blocked, opened = opened)
}
.ks <- .probe_killswitch()
if (isTRUE(.ks$blocked) && isTRUE(.ks$opened))
  ok("돌연변이 통제: env=0 이면 등재 차단 · env 부재면 등재 개방 — 양방향 전환 실증") else
  ng("★돌연변이 통제 실패 — 킬스위치가 실제로 전환하지 않는다",
     sprintf("blocked=%s opened=%s", .ks$blocked, .ks$opened))
# ★복원 실증 — on.exit 이 함수 프레임에서 실제로 돌았는지 본다(금칙 ② 재발 방지 래칫)
if (identical(Sys.getenv("QVEST_LEAN_REGISTER", unset = "<unset>"), "<unset>"))
  ok("probe 종료 후 env 복원 확인 — on.exit 이 함수 프레임에서 실제로 발화했다") else
  ng("★env 가 오염된 채 남았다 — on.exit 미발화(금칙 ② 재발)",
     Sys.getenv("QVEST_LEAN_REGISTER"))

# ══ B. 최종 승자 등재 (§2-e) ════════════════════════════════════════════════
cat("\n── B. 최종 승자 등재 ───────────────────────────────────────\n")

if (!grepl("rl_register_winner <- function", J, fixed = TRUE)) {
  ng("★rl_register_winner 부재 — 막기만 하고 열지 않았다. 강화는 풀에 영원히 못 들어간다")
} else {
  ok("rl_register_winner 정의 존재")

  # B1 — 호출부가 실제로 있는가 (정의만 있고 호출 0 = 이 저장소가 반복한 '소비자 0')
  called <- length(grep("rl_register_winner\\(cand", rl)) > 0L
  if (called) ok("rl_run_candidate 가 실제로 호출 — 정의만 있고 호출 0 이 아니다") else
    ng("★정의만 있고 호출 0 — '소비자 0' 계통")

  # B2 — 호출부를 지우면 B1 이 뒤집히는가 (돌연변이 통제)
  mut <- rl[!grepl("rl_register_winner\\(cand", rl)]
  if (!length(grep("rl_register_winner\\(cand", mut)))
    ok("돌연변이 통제: 호출부를 지우면 B1 이 뒤집힌다") else
    ng("★돌연변이 통제 실패 — B1 이 아무것도 재지 않는다")

  fn_i <- grep("rl_register_winner <- function", rl)[1]
  fn_j <- min(fn_i + 90L, length(rl))
  fn <- paste(rl[fn_i:fn_j], collapse = "\n")

  # B3 — ★특혜 금지: contract_pass 를 선언하지 않고 실측값을 쓰는가
  if (grepl("contract_pass      = contract_ok", fn, fixed = TRUE) &&
      grepl('identical(as.character(ct$status', fn, fixed = TRUE) &&
      grepl("audit_fail", fn, fixed = TRUE))
    ok("contract_pass 를 **선언하지 않는다** — bt_contract_status 실측(status OK ∧ audit_fail 0)") else
    ng("★contract_pass 를 하드코딩했다 — 특혜. 1단계와 같은 floor 가 아니게 된다")

  # B4 — origin_mode 로 1·2단계를 구분 가능하게 하는가
  if (grepl('origin_mode = "reinforce_ladder"', fn, fixed = TRUE))
    ok("origin_mode='reinforce_ladder' — 풀에서 2단계 산출을 구분할 수 있다") else
    ng("★origin_mode 미표기 — 풀에서 1단계와 섞인다")

  # B5 — base 승자·등급 NA 는 등재하지 않는가 (AX-002)
  if (grepl("SKIPPED_BASE", fn, fixed = TRUE) && grepl("SKIPPED_NO_GRADE", fn, fixed = TRUE))
    ok("base 승자(개선 없음)와 등급 NA(계약 미경유)는 등재 제외 — AX-002") else
    ng("★개선 없는 base 나 계약 미경유분이 풀에 들어갈 수 있다")

  # B6 — 재구성기를 재사용하는가 (21번째 복사본 금지)
  if (grepl("bl_sim_from_bt", fn, fixed = TRUE))
    ok("bt_result→sim 재구성을 bl_sim_from_bt 재사용 (재구현 아님)") else
    ng("★sim 재구성을 자체 구현했다 — 정본이 둘이 된다")

  # B7 — 원장 재개 안전성: registration 이 통째로 교체되는가
  if (grepl('RL_LEDGER_REPLACE_KEYS <- c\\("cells", "rungs", "final", "registration"\\)', J))
    ok("registration 이 REPLACE_KEYS 에 포함 — 재개 시 이전 회차 잔재가 안 남는다") else
    ng("★registration 이 재귀 병합된다 — 이전 회차 등재 결과가 이번 것으로 오독된다")
}

# ══ C. 풀 floor 무변경 (특혜 금지의 반대 방향) ══════════════════════════════
cat("\n── C. 풀 floor 무변경 ──────────────────────────────────────\n")
if (!file.exists(BMP)) {
  sk("C_floor_untouched", "build_module_performance.R 부재", BMP)
} else {
  bmp <- paste(readLines(BMP, warn = FALSE), collapse = "\n")
  if (grepl("\\.is_fr_eligible <- function", bmp) &&
      grepl("isTRUE\\(e\\$fr_eligible\\)", bmp))
    ok(".is_fr_eligible 무변경 — 승자도 1단계와 같은 관문을 탄다") else
    ng("★풀 floor 가 변경됐다 — 강화에 특혜가 생겼는지 확인 필요")
  # legacy QEPM 상호배타가 깨지지 않았는가
  if (grepl("legacy", bmp) && grepl("module_catalog", bmp))
    ok("legacy QEPM 상호배타 서술 유지 (catalog 권위)") else
    ng("★legacy 예외 서술이 사라졌다")
}

emit()
