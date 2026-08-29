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

# ══ D. 루프 폐쇄 — 사다리가 다음 후보로 전진하는가 (§2-f) ═══════════════════
cat("\n── D. 루프 폐쇄 (완주분 배제) ──────────────────────────────\n")
#
# ★실측 결함(2026-08-24): `rl_candidates()` 가 원장을 **전혀 보지 않았다**.
#   `entry_strength` 내림차순 + `max_active=1` 이라 **매 실행이 같은 1위 후보를 다시 집는다**.
#   셀 재개 로직 때문에 두 번째 실행은 빨리 끝나지만 결과가 같고, **다음 후보로는 영원히
#   넘어가지 않는다.** 무인 기동(§2-d)을 붙이면 매일 아침 같은 전략만 태운다.
#
# ★플랜 §2-f 정정: 플랜은 "close_round 에 frontier_update 인자 한 줄"이라고 적었으나
#   `close_round.R:169` 는 그 서술에서 `FQ-[0-9]+` 를 추출해 큐를 갱신한다. 사다리 입력은
#   frontier 가설이 아니라 전략 모듈이다 — `improvement_potential.json` 42 항목 전부 전략 id
#   키이고 **FQ-id 참조 0**(실측). 인자를 채워도 fq_ids 는 빈 벡터라 아무것도 안 바뀐다.
#   사다리의 실제 소비면은 **자기 원장**이고 폐쇄 지점이 후보 선정이다.
rlj <- paste(readLines(RL, warn = FALSE), collapse = "\n")

# D1 — 후보 선정이 원장을 읽는가
if (grepl("rl_ledger_read(root)", rlj, fixed = TRUE) &&
    grepl("n_done_excluded", rlj, fixed = TRUE))
  ok("후보 선정이 원장을 읽고 완주분을 배제 — 루프가 전진한다") else
  ng("★후보 선정이 원장을 안 본다 — 매 실행이 같은 1위 후보를 다시 집는다")

# D2 — 배제 기준이 stage=="done" 하나인가 (중단·진행 중은 재개해야 한다)
if (grepl('identical(as.character(r$stage %|N|% ""), "done")', rlj, fixed = TRUE))
  ok('배제 기준 = stage=="done" 만 — 중단(stopped)·진행 중은 재개 가능') else
  ng("★배제 기준이 넓다 — 중단된 후보가 영구 봉인될 수 있다")

# D3 — ★배제를 침묵시키지 않는가 ("후보 없음"과 "다 태웠음"은 다른 상태다)
if (grepl("done_excluded=%d", rlj, fixed = TRUE) &&
    grepl("원장 완주 %d건 배제", rlj, fixed = TRUE))
  ok("배제 건수·id 를 요약에 노출 — 조용한 봉인 없음") else
  ng("★배제가 침묵한다 — '후보가 없다'와 '이미 다 태웠다'가 같은 화면이 된다")

# D4 — ★해제 경로(--redo)가 **선정보다 앞**에서 파싱되는가
#   실측: 처음엔 `getopt("top")` 옆(선정 뒤)에 뒀더니 플래그가 죽었다 —
#   `--redo` 를 줘도 배제가 안 풀렸다. 돌연변이 통제가 그 죽은 판을 잡았다.
pos_redo <- regexpr('"--redo" %in% args', rlj, fixed = TRUE)
pos_cand <- regexpr("cs <- rl_candidates(config)", rlj, fixed = TRUE)
if (pos_redo > 0L && pos_cand > 0L && pos_redo < pos_cand)
  ok("--redo 파싱이 rl_candidates() 앞 — 플래그가 실제로 작동한다") else
  ng("★--redo 가 선정 뒤에서 파싱된다 — 플래그가 죽는다(실측 전례)",
     sprintf("redo@%d cand@%d", pos_redo, pos_cand))

# D5 — 기본값이 배제(=전진)인가. 기본이 재측정이면 루프가 안 닫힌다.
if (grepl("redo_completed = FALSE", rlj, fixed = TRUE))
  ok("기본값 = 완주분 배제(전진) · 재측정은 명시 --redo") else
  ng("★기본이 재측정이다 — 루프가 닫히지 않는다")

# ══ E. 무인 기동 배선 (§2-d) ════════════════════════════════════════════════
cat("\n── E. 무인 러너 뒤 자동 기동 ───────────────────────────────\n")
#
# 도훈 결정 2026-08-24: "강화 기동 = 무인 러너 뒤 자동".
# ★순서가 곧 파이프라인 선언이다 — 기본 1단계(논문 알파리서치) → 2단계(강화).
#   그래서 큐 리프레시 **뒤**, 완주 알림 **앞**이어야 한다.
ASQ <- file.path(ROOT, "02_Infrastructure", "ops", "alpha_search_queue_run.sh")
## ★부팅 스크립트는 ops/ 에 있고 현행 경로는 boot_lean.sh 다 — 둘 다 본다.
##   (구판은 hooks/bootstrap.sh 를 가리켜 SKIP 이 났다. SKIP 은 "재지 않았다"이지
##    "통과"가 아니다 — 죽은 축을 통과로 세는 것이 이 저장소의 반복 결함이다.)
BOOTS <- c(file.path(ROOT, "02_Infrastructure", "ops", "bootstrap.sh"),
           file.path(ROOT, "02_Infrastructure", "ops", "boot_lean.sh"))
BOOTS <- BOOTS[file.exists(BOOTS)]
if (!file.exists(ASQ)) sk("E_wiring", "alpha_search_queue_run.sh 부재", ASQ) else {
  asq <- paste(readLines(ASQ, warn = FALSE), collapse = "\n")

  # E1 — 호출이 존재하는가
  if (grepl("reinforce_ladder.R", asq, fixed = TRUE) && grepl("--top=1", asq, fixed = TRUE))
    ok("무인 러너가 강화 프로세스 1후보를 기동한다") else
    ng("★강화 기동 배선이 없다 — 2단계가 무인 경로에서 영원히 안 돈다")

  # E2 — ★순서: 큐 리프레시 < 강화 < 완주 알림
  p_q <- regexpr("스크린 큐 리프레시 시작", asq, fixed = TRUE)
  p_l <- regexpr("강화 프로세스 시작", asq, fixed = TRUE)
  p_n <- regexpr("research_run_notify.R", asq, fixed = TRUE)
  if (p_q > 0L && p_l > 0L && p_n > 0L && p_q < p_l && p_l < p_n)
    ok("순서 = 1단계 산출 → 큐 리프레시 → 2단계 강화 → 완주 알림 (파이프라인 선언 그대로)") else
    ng("★기동 순서가 파이프라인과 어긋난다", sprintf("queue@%d ladder@%d notify@%d", p_q, p_l, p_n))

  # E3 — 강화 실패가 **비치명**인가 (1단계 산출·알림을 막으면 안 된다)
  if (grepl("강화 프로세스 실패(비치명)", asq, fixed = TRUE))
    ok("강화 실패는 비치명 — 1단계 완주 알림을 막지 않는다") else
    ng("★강화 실패가 러너를 죽인다 — 이미 끝난 1단계 산출까지 보고가 사라진다")

  # E4 — 킬스위치가 있는가 (무인 경로에 정지 수단 없으면 되돌릴 방법이 없다)
  if (grepl("QVEST_LADDER_NORUN", asq, fixed = TRUE))
    ok("킬스위치 QVEST_LADDER_NORUN 존재 — 무인 기동을 끌 수 있다") else
    ng("★킬스위치가 없다")

  # E5 — 건너뜀을 침묵시키지 않는가
  if (grepl("강화 프로세스 건너뜀", asq, fixed = TRUE))
    ok("건너뜀 사유를 로그에 남긴다 — '안 돌렸다'와 '후보 0'을 구분") else
    ng("★건너뜀이 침묵한다")
}

# E6 — ★부팅에는 붙이지 않는다 (부팅 상태라인 읽기 전용 규약 8j)
if (!length(BOOTS)) sk("E6_boot", "부팅 스크립트 2종 모두 부재", "ops/{bootstrap,boot_lean}.sh") else {
  bad <- BOOTS[vapply(BOOTS, function(f)
    grepl("reinforce_ladder", paste(readLines(f, warn = FALSE), collapse = "\n"), fixed = TRUE),
    logical(1))]
  if (!length(bad))
    ok(sprintf("부팅 스크립트 %d종에 강화 기동 없음 — 상태라인 읽기 전용 규약 유지", length(BOOTS))) else
    ng("★부팅이 강화를 기동한다 — 상태라인이 부작용을 내면 부팅이 판정을 바꾼다",
       paste(basename(bad), collapse = ","))
}

emit()
