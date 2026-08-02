#==============================================================================
# test_contract_panel.R — FQ-002 계약 패널 빌더 로직 검사기 (합성 픽스처, API 무호출)
#
# 2026-08-02 신설. 크롤(1시간) 전에 집계·롤링·제외 로직을 확정한다.
# 검사 축:
#   ① 기재정정 제외 — 사후 수정본이 신호에 섞이면 look-ahead 와 동형
#   ② parse 실패 제외 — 결손이 0 으로 흘러 '계약 없음'이 되면 안 됨
#   ③ trailing 롤링 정확성 — WINDOW_M 합이 실제로 과거 창만 본다(미래 누출 없음)
#   ④ SCOPE=new_only 가 변경계약을 실제로 뺀다
#   ⑤ 빈 입력 → 조용한 빈 패널이 아니라 stop
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow) })

.t_root <- function() {
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", unset = ""), Sys.getenv("QM_ROOT", unset = ""),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[file.exists(file.path(cands, "02_Infrastructure/hooks/qvest_hook_router.py"))]
  if (!length(hit)) stop("project root 미발견"); hit[1]
}
PROJ <- .t_root(); setwd(PROJ)
PASS <- 0L; FAIL <- 0L
ok  <- function(n, m = "") { PASS <<- PASS + 1L; cat(sprintf("  PASS: %s%s\n", n, if (nzchar(m)) paste0(" — ", m) else "")) }
bad <- function(n, m = "") { FAIL <<- FAIL + 1L; cat(sprintf("  FAIL: %s — %s\n", n, m)) }
cat("=== contract panel builder (합성 픽스처) ===\n")

BUILDER <- file.path(PROJ, "02_Infrastructure/alpha_search/build_contract_panel.R")

# 유니버스 매핑에 실재하는 corp_code 2개를 골라 픽스처를 만든다(매핑 실패로 인한 위양성 방지)
map <- unique(fread(".cache/dart/universe_corpcodes.csv", colClasses = "character"))
cc <- map$corp_code[1:2]; tk <- map$ticker[1:2]

mk_fixture <- function(dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  row <- function(ym, dd, corp, amt, rev, corr, amend, st = "OK")
    data.table(ym = ym, rcept_no = paste0(ym, dd, "0001"), corp_code = corp,
               corp_name = "X", rcept_dt = as.integer(paste0(ym, dd)),
               report_nm = if (corr) "[기재정정]단일판매ㆍ공급계약체결" else "단일판매ㆍ공급계약체결",
               is_correction = corr, contract_amount = amt, recent_revenue = rev,
               ratio_to_revenue = if (is.na(amt) || is.na(rev)) NA_real_ else amt / rev,
               is_amendment = amend, rounding_flag = FALSE, fx_flag = FALSE,
               parse_status = st, parse_note = "")
  fwrite(rbind(
    row("202601", "15", cc[1], 100, 1000, FALSE, FALSE),          # 신규 · 유효 → ratio 0.10
    row("202601", "20", cc[1], 500, 1000, TRUE,  FALSE),          # 정정 → 제외되어야
    row("202601", "25", cc[2], 300, 1000, FALSE, TRUE)            # 변경계약 · 유효 → ratio 0.30
  ), file.path(dir, "202601.csv"))
  fwrite(rbind(
    row("202602", "10", cc[1], 200, 1000, FALSE, FALSE),          # 신규 → ratio 0.20
    row("202602", "11", cc[2], NA_real_, 1000, FALSE, FALSE, "NO_AMOUNT")  # parse 실패 → 제외
  ), file.path(dir, "202602.csv"))
}

# ★인라인 `VAR=값 cmd` 접두는 **쉘 문법**이다 — Windows R 은 셸을 경유하지 않아
#  통째로 프로그램 이름이 된다(이 검사기 작성 중 실제로 밟았다: r-portability 금칙 ⑤).
#  정본 = Sys.setenv() + 복원(금칙 ①의 대체 패턴) + system2 인자 벡터.
run_builder <- function(dir, out, window = 2L, scope = "all") {
  keys <- c("CONTRACT_CKDIR", "CONTRACT_PANEL_OUT", "WINDOW_M", "SCOPE", "CLAUDE_PROJECT_DIR")
  old  <- vapply(keys, function(k) Sys.getenv(k, unset = NA_character_), character(1))
  on.exit({
    for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k))
  }, add = TRUE)
  Sys.setenv(CONTRACT_CKDIR = dir, CONTRACT_PANEL_OUT = out,
             WINDOW_M = as.character(window), SCOPE = scope, CLAUDE_PROJECT_DIR = PROJ)
  log <- suppressWarnings(system2("Rscript", args = BUILDER, stdout = TRUE, stderr = TRUE))
  list(log = log, ok = file.exists(out))
}

d <- file.path(tempdir(), paste0("ctrfx_", as.integer(Sys.time())))
mk_fixture(d)

# WINDOW_M=1 판: 월별 값을 그대로 본다(정정/parse 제외/미래누출 축).
#  ※ frollsum(align="right") 은 창을 못 채운 앞 구간을 NA 로 둔다 — WINDOW_M=2 에서
#    첫 달(202601)이 사라지는 것은 **정상**이며, 그 행을 검사하면 검사기 쪽 오류다(초판이 그랬다).
o1 <- file.path(tempdir(), paste0("ctrp1_", as.integer(Sys.time()), ".parquet"))
r1 <- run_builder(d, o1, window = 1L, scope = "all")
if (!r1$ok) {
  bad("panel_built_w1", paste(utils::tail(r1$log, 3), collapse = " | "))
} else {
  P <- as.data.table(read_parquet(o1))
  ok("panel_built_w1", sprintf("%d행", nrow(P)))

  # ① 정정 제외: 202601 corp1 = 0.10 (정정 0.50 이 섞이면 0.60)
  v <- P[ym == "202601" & Ticker == tk[1], w_ratio]
  if (length(v) && abs(v[1] - 0.10) < 1e-9) {
    ok("correction_excluded", "202601 ratio=0.10 (정정 0.50 미포함)")
  } else {
    bad("correction_excluded", sprintf("ratio=%s (0.10 기대)", if (length(v)) v[1] else "없음"))
  }
  # ★미래 누출: 202601 창에 202602 값(0.20)이 들어가면 0.30 이 된다
  if (length(v) && abs(v[1] - 0.10) < 1e-9) {
    ok("no_future_leak", "202601 창에 202602 값 미포함")
  } else {
    bad("no_future_leak", "202601 창이 미래 월을 포함")
  }
  # ② parse 실패 제외: 202602 corp2 는 NO_AMOUNT 뿐이라 그 달 행이 없어야 한다
  if (!nrow(P[ym == "202602" & Ticker == tk[2]])) {
    ok("parse_fail_excluded", "NO_AMOUNT 행이 0 으로 흘러들지 않음")
  } else {
    bad("parse_fail_excluded", "parse 실패가 신호로 계상됨")
  }
}

# WINDOW_M=2 판: trailing 누적 정확성
o <- file.path(tempdir(), paste0("ctrp2_", as.integer(Sys.time()), ".parquet"))
r <- run_builder(d, o, window = 2L, scope = "all")
if (!r$ok) {
  bad("trailing_window_sum", paste(utils::tail(r$log, 3), collapse = " | "))
} else {
  P2w <- as.data.table(read_parquet(o))
  v3 <- P2w[ym == "202602" & Ticker == tk[1], w_ratio]
  if (length(v3) && abs(v3[1] - 0.30) < 1e-9) {
    ok("trailing_window_sum", "202602 창합=0.30 (0.10+0.20)")
  } else {
    bad("trailing_window_sum", sprintf("w_ratio=%s (0.30 기대)", if (length(v3)) v3[1] else "없음"))
  }
  if (!nrow(P2w[ym == "202601"])) {
    ok("window_warmup_dropped", "창 미충족 첫 달은 제외(frollsum 정상 동작)")
  } else {
    bad("window_warmup_dropped", "창을 못 채운 달이 남아 부분합이 신호로 쓰임")
  }
}

# ④ SCOPE=new_only — 변경계약(corp2) 제외
o2 <- paste0(o, ".newonly.parquet")
r2 <- run_builder(d, o2, window = 2L, scope = "new_only")
if (r2$ok) {
  P2 <- as.data.table(read_parquet(o2))
  if (!nrow(P2[Ticker == tk[2]])) ok("scope_new_only", "변경계약 종목 제외됨")
  else bad("scope_new_only", "new_only 인데 변경계약이 남음")
} else bad("scope_new_only", "빌드 실패")

# ⑤ 빈 입력 → stop (조용한 빈 패널 금지)
d_empty <- file.path(tempdir(), paste0("ctrempty_", as.integer(Sys.time())))
dir.create(d_empty, recursive = TRUE, showWarnings = FALSE)
o3 <- paste0(o, ".empty.parquet")
r3 <- run_builder(d_empty, o3, window = 2L)
if (!r3$ok) {
  ok("empty_input_refused", "빈 체크포인트 → 패널 미생성(명시 중단)")
} else {
  bad("empty_input_refused", "빈 입력인데 패널이 생성됨 — '빈 결과 = 정상' 재발")
}

# ⑥ 엔진 fan-out assert 위반 주입 (2026-08-02 신설 — 구 assert 는 모순 조건으로 발화 불가였다)
#   패널에 (ym,Ticker) 중복 행을 주입 → factor_engine_contract.R 이 stop 해야 한다.
#   위반 주입 없이 "통과"만 보면 오탐 제거와 검사 사망을 구분 못 한다.
eng_test <- local({
  o4 <- file.path(tempdir(), paste0("ctrdup_", as.integer(Sys.time()), ".parquet"))
  dup <- data.table(ym = c("202601", "202601"), Ticker = tk[1],
                    n_contracts = 1L, amt_sum = 100, ratio_rev_sum = 0.1,
                    amend_n = 0L, round_n = 0L, fx_n = 0L,
                    w_n = 1, w_amt = 100, w_ratio = 0.1, w_amend = 0,
                    window_m = 1L, scope = "all", metric_type = "raw_disclosure", built_at = "t")
  write_parquet(dup, o4)
  # 최소 RAWDATA (엔진이 요구하는 컬럼만)
  RAWDATA <- data.table(Date = as.Date(c("2026-01-30", "2026-01-31")), Ticker = tk[1],
                        Size = 1e12, LiqPass = TRUE)
  old_cp <- Sys.getenv("CONTRACT_PANEL", unset = NA_character_)
  Sys.setenv(CONTRACT_PANEL = o4)
  r <- tryCatch({ source(file.path(PROJ, "02_Infrastructure/alpha_search/factor_engine_contract.R"), local = TRUE); "no_stop" },
                error = function(e) conditionMessage(e))
  if (is.na(old_cp)) Sys.unsetenv("CONTRACT_PANEL") else Sys.setenv(CONTRACT_PANEL = old_cp)
  unlink(o4, force = TRUE)
  r
})
if (grepl("중복", eng_test)) {
  ok("engine_dup_injection_blocked", "패널 (ym,Ticker) 중복 주입 → 엔진 stop 발화")
} else {
  bad("engine_dup_injection_blocked", sprintf("주입이 통과됨: %s", substr(eng_test, 1, 80)))
}

unlink(c(d, d_empty), recursive = TRUE); unlink(c(o, o1, o2, o3), force = TRUE)
cat(sprintf("TOTAL: %d pass / %d fail\n", PASS, FAIL))
cat(jsonlite::toJSON(list(test = "contract_panel", pass = PASS, fail = FAIL,
                          total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0) quit(status = 1)
