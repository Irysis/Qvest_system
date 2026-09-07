#!/usr/bin/env Rscript
#==============================================================================
# test_module_admission_seam.R — 생산 레인 → 2계층 풀 **등재 이음매** (2026-09-07 신설)
#
# 왜: 2026-09-07 실측에서 v10 생산 631 런(essence B 54 · defensive TRUE 407)이
#   module_catalog 에 들어갈 경로가 아예 없었다 — `run_paper_replication.R` 이
#   bt_result.rds 만 남기고 `register_module()` 을 한 번도 부르지 않았다. 동시에
#   `rf_replication_verify.R` 의 `base_below_threshold` 게이트는 **전기간** PORT_t
#   하나로 논문을 영구 소비했고, 그렇게 버려진 14건 중 11건이 계약 기준 방어형이었다
#   (AX-001 이 금지하는 "전기간 기준 방어형 평가"). 두 결함 다 **생산자·소비자가 있는데
#   전이가 없는** 형태라 기존 검사 전부가 초록이었다.
#
# 이 검사의 1급 축 = "붙였다" 가 아니라 **"부른다"** — 러너의 블록을 소스에서
#   **잘라 실제로 eval 한다**(재구현 아님). 좌표(줄번호·파일 위치)를 못박지 않고
#   의미 앵커(게이트 비교식 / kill-switch env 이름)로 찾는다.
#
# 축:
#   A. 자격 술어(rmm_admission) 양방향 — 방어형 TRUE / FALSE / **부재** / 판정불가 / 등급 floor
#   B. 게이트 블록 실제 구동 — 방어형이면 defensive_admitted 가 **소비(ledger_consumed) 앞**에
#      찍히고, 비방어형이면 안 찍히며, 부재는 dscore_absent 사유로 남는다
#   B4. PORT_t ≥ 문턱 → 게이트 조건 자체가 FALSE(분기 미진입) — 러너의 진짜 조건식을 eval
#   B5. 위반 주입(양성 대조) — 등재 호출을 깨뜨리면 defensive_admitted 가 사라진다
#   C. 생산 레인 등재 — 계약 floor 충족 시 등재되고, 미충족·재료부재는 **사유가 남는다**
#      (조용한 실패 없음). 등재분은 소비자(l2_admit)가 실제로 편입한다.
#   D. 격리 — 운영 module_catalog / 원장 / .cache/reinforce_auto_log.jsonl 에 안 쓴다
#==============================================================================
suppressMessages({ library(data.table); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
ROOT <- gsub("\\\\", "/", ROOT)     # R 문자열 안 Windows 백슬래시(\U)는 즉사
setwd(ROOT); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT)
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(sprintf("  OK   %s\n", m)) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(sprintf("  FAIL %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
## 최상위 if/else 는 R 파서가 끊는다 — 단언은 전부 이 한 함수로 낸다.
chk <- function(cond, msg, detail = "") if (isTRUE(cond)) ok(msg) else ng(msg, detail)

TD <- file.path(tempdir(), sprintf("madm_%d", Sys.getpid()))
dir.create(TD, recursive = TRUE, showWarnings = FALSE)
TCAT <- file.path(TD, "module_catalog.json")
TQ   <- file.path(TD, "module_quarantine.json")
TLOG <- file.path(TD, "jlog.jsonl")
write('{"schema_version":"v2.0","modules":{}}', TCAT)
OPS_CAT <- file.path(ROOT, "06_Registry/module_catalog.json")
OPS_LOG <- file.path(ROOT, ".cache/reinforce_auto_log.jsonl")
OPS_LED <- file.path(ROOT, "06_Registry/reinforce_ledger_l1.json")
LED_MD5_0 <- if (file.exists(OPS_LED)) unname(tools::md5sum(OPS_LED)) else NA_character_

## ★검사 전용 싱크로 돌린다 — 운영 저널·카탈로그를 빌리면 그것을 고칠 때 검사가 깨진다.
Sys.setenv(QVEST_RP_JLOG = TLOG, QVEST_MODULE_CATALOG = TCAT, QVEST_MODULE_QUARANTINE = TQ)

RMM <- new.env(parent = globalenv())
suppressMessages(sys.source(file.path(ROOT, "02_Infrastructure/contracts/register_measured_module.R"),
                            envir = RMM))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# ── 합성 산출물 (계약 산출물과 **같은 배치·같은 파일명**) ─────────────────────
.ds <- function(defensive, status = "ok", t = 6.16, ex = 0.0474)
  list(status = status, defensive = defensive, convex = TRUE, n_months = 240L,
       down = list(n = 111L, excess = ex, hit = 0.61, t = t, capture = 0.4),
       deep = list(n = 10L, excess = 0.1915, hit = 0.9, t = 3.1, capture = 0.2),
       mid = list(n = 30L, excess = 0.06, hit = 0.7, t = 2.2, capture = 0.3),
       up = list(n = 129L, excess = -0.004, hit = 0.45, t = -0.8, capture = 0.9),
       reason = "합성 픽스처 — 하락월 111개")

.mk <- function(tag, grade = "F", ds = .ds(TRUE), metric_type = "backtested",
                status = "OK", with_csv = TRUE, with_auth = TRUE) {
  d <- file.path(TD, tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  sid <- paste0("RP_FIX_", tag)
  if (with_auth) {
    a <- list(status = status, strategy_id = sid, strategy_name = tag,
              run_id = paste0("run_", tag), metric_type = metric_type,
              essence_grade = grade, grade_basis = "replication_chain",
              bt_result_path = file.path(d, "bt_result.rds"))
    if (!is.null(ds)) a$defensive_score <- ds
    write(toJSON(a, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
          file.path(d, "authoritative_remeasure.json"))
  }
  write(toJSON(list(run_id = paste0("run_", tag), code_version = "run_paper_replication_v10",
                    cost_model_version = "fixture_15bps"), auto_unbox = TRUE, pretty = TRUE),
        file.path(d, "00_manifest.json"))
  if (with_csv) {
    set.seed(42); n <- 400L
    dt <- seq(as.Date("2020-01-01"), by = "day", length.out = n)
    fwrite(data.table(run_id = "r", strategy_id = sid, date = dt, frequency = "daily",
                      ret_gross = rnorm(n, 3e-4, 0.01), ret_net = rnorm(n, 2e-4, 0.01)),
           file.path(d, "03_period_returns.csv"))
    fwrite(data.table(benchmark_id = "KOSPI200", benchmark_name = "KOSPI 200", date = dt,
                      frequency = "daily", benchmark_ret = rnorm(n, 1e-4, 0.011)),
           file.path(d, "05_benchmark_returns.csv"))
  }
  saveRDS(list(fixture = TRUE), file.path(d, "bt_result.rds"))
  list(dir = d, sid = sid)
}

.jl <- function() {                       # 검사 저널 판독 (event 순서 보존)
  if (!file.exists(TLOG)) return(data.table(event = character(0), code = character(0)))
  ln <- readLines(TLOG, warn = FALSE); ln <- ln[nzchar(trimws(ln))]
  if (!length(ln)) return(data.table(event = character(0), code = character(0)))
  rbindlist(lapply(ln, function(x) {
    y <- tryCatch(fromJSON(x, simplifyVector = TRUE), error = function(e) NULL)
    if (is.null(y)) return(NULL)
    data.table(event = as.character(y$event %||% ""), code = as.character(y$code %||% ""))
  }), fill = TRUE)
}

cat("\n[A] 자격 술어 — 방어형 부재/거짓/참을 가른다\n")
.adm_of <- function(f) RMM$rmm_admission(RMM$rmm_read_auth(f$dir))
A1 <- .adm_of(.mk("A1", "F", .ds(TRUE)))
chk(isTRUE(A1$eligible) && identical(as.character(A1$route)[1], "defensive_specialist"),
    "A1 PORT_t<0(등급 F) ∧ 방어형 TRUE → defensive_specialist 편입",
    paste(A1$code, A1$reason))
A2 <- .adm_of(.mk("A2", "F", .ds(FALSE)))
chk(!isTRUE(A2$eligible) && identical(A2$code, "not_defensive"),
    "A2 방어형 FALSE → 미편입(not_defensive)", paste(A2$eligible, A2$code))
A3 <- .adm_of(.mk("A3", "F", NULL))
chk(!isTRUE(A3$eligible) && identical(A3$code, "dscore_absent"),
    "A3 defensive_score **부재** → dscore_absent (거짓으로 읽지 않는다)",
    paste(A3$eligible, A3$code))
A4 <- .adm_of(.mk("A4", "F", .ds(NA, status = "하락월 8 < 12 — 판정 불가")))
chk(!isTRUE(A4$eligible) && identical(A4$code, "dscore_not_ok"),
    "A4 판정불가 → dscore_not_ok (부재·거짓과 다른 칸)", paste(A4$eligible, A4$code))
A5 <- .adm_of(.mk("A5", "B", .ds(FALSE)))
chk(isTRUE(A5$eligible) && identical(as.character(A5$route)[1], "grade_floor"),
    "A5 essence B → grade_floor 편입(방어형 무관)", paste(A5$eligible, A5$code))

# ── 러너 소스에서 **블록을 잘라 실제로 eval** 한다 ───────────────────────────
#   좌표를 못박지 않는다: 의미 앵커(게이트 비교식)로 찾고, R 파서가 완결되는 지점까지 취한다.
.take_expr <- function(lines, i0, maxlen = 400L) {
  n <- length(lines)
  for (j in i0:min(n, i0 + maxlen)) {
    t <- paste(lines[i0:j], collapse = "\n")
    e <- tryCatch(parse(text = t), error = function(e) NULL)
    if (!is.null(e) && length(e) >= 1L) return(list(expr = e, text = t, first = i0, last = j))
  }
  NULL
}
VFY <- file.path(ROOT, "02_Infrastructure/ops/rf_replication_verify.R")
VL  <- readLines(VFY, warn = FALSE)
i_gate <- grep(".base_pt < .min_pt", VL, fixed = TRUE)
i_gate <- i_gate[grepl("if (", VL[i_gate], fixed = TRUE)]
GATE <- if (length(i_gate)) .take_expr(VL, i_gate[1]) else NULL

cat("\n[B] 게이트 블록 — 러너의 진짜 코드를 잘라 구동한다\n")
if (is.null(GATE)) {
  ng("B0 게이트 블록을 찾지 못했다",
     "앵커 '.base_pt < .min_pt' 를 가진 if 문 — 이름이 바뀌었으면 이 검사를 재조준할 것")
} else {
  ok(sprintf("B0 게이트 블록 추출 (%d줄)", GATE$last - GATE$first + 1L))

  .run_gate <- function(fix, base_pt = -0.639, min_pt = 0, mutate = NULL) {
    unlink(TLOG, force = TRUE)
    txt <- GATE$text
    if (!is.null(mutate)) txt <- sub(mutate[1], mutate[2], txt, fixed = TRUE)
    ex <- tryCatch(parse(text = txt), error = function(e) NULL)
    if (is.null(ex)) return(list(err = "parse_failed", ev = character(0), args = list(), note = ""))
    sb <- new.env(parent = globalenv())
    REC <- new.env(parent = emptyenv()); REC$ev <- character(0); REC$args <- list()
    sb$jlog <- function(event, ...) { REC$ev <- c(REC$ev, event)
                                      REC$args[[length(REC$args) + 1L]] <- list(event = event, ...)
                                      invisible(TRUE) }
    sb$ROOT <- ROOT; sb$ar <- file.path(fix$dir, "authoritative_remeasure.json")
    sb$.base_pt <- base_pt; sb$.min_pt <- min_pt; sb$.resc_ok <- FALSE
    sb$PKEY <- "fixture.0001"; sb$.fidelity <- "faithful"; sb$G <- "F"
    sb$TITLE <- "fixture paper"; sb$COUNT_PAPER <- FALSE; sb$.RF_MAXA <- 25L
    sb$REQ <- file.path(TD, "replication_request.json")
    write('{"status":"pending"}', sb$REQ)
    ## 부작용 있는 협력자는 전부 샌드박스에서 가린다(샌드박스가 globalenv 보다 먼저 조회된다).
    sb$source <- function(...) invisible(NULL)
    sb$rf_open_entry <- function(...) invisible(TRUE)
    sb$rf_park_entry <- function(...) invisible(TRUE)
    sb$.qmirror <- function(...) invisible(TRUE)
    sb$tg_agent_brief <- function(...) invisible(list(ok = TRUE))
    sb$tg_pass_analysis <- function(...) invisible(TRUE)
    sb$rf_perf_kv <- function(...) list(a = "1")
    sb$rf_perf_weak <- function(...) c("w")
    sb$rf_perf_charts <- function(...) character(0)
    sb$system2 <- function(...) invisible("")
    sb$quit <- function(...) stop(structure(class = c("qvest_quit", "error", "condition"),
                                            list(message = "quit", call = NULL)))
    err <- NULL
    tryCatch(eval(ex[[1]], envir = sb),
             qvest_quit = function(e) invisible(NULL),
             error = function(e) err <<- conditionMessage(e))
    list(err = err, ev = REC$ev, args = REC$args,
         note = if (exists(".adm_note", envir = sb, inherits = FALSE)) sb$.adm_note else "")
  }

  r1 <- .run_gate(.mk("B1", "F", .ds(TRUE)))
  i_adm <- which(r1$ev == "defensive_admitted"); i_con <- which(r1$ev == "ledger_consumed")
  chk(length(i_adm) > 0L && length(i_con) > 0L && i_adm[1] < i_con[1],
      "B1 방어형 TRUE → defensive_admitted 가 ledger_consumed **앞에** 찍힌다",
      sprintf("events=%s err=%s", paste(r1$ev, collapse = ","), r1$err %||% "-"))
  A <- if (length(i_adm)) r1$args[[i_adm[1]]] else list()
  chk(length(i_adm) > 0L && is.finite(suppressWarnings(as.numeric(A$down_t))) &&
      is.finite(suppressWarnings(as.numeric(A$down_excess))) && !is.null(A$convex),
      "B1b defensive_admitted 에 하락월 t·초과·convex 가 병기된다",
      paste(names(A), collapse = ","))
  chk(length(r1$note) == 1L && nzchar(r1$note) && grepl("하락월", r1$note),
      "B1c 텔레그램 1줄(.adm_note)이 채워진다", paste(r1$note, collapse = "|"))

  r2 <- .run_gate(.mk("B2", "F", .ds(FALSE)))
  chk(!("defensive_admitted" %in% r2$ev) && ("ledger_consumed" %in% r2$ev) &&
      ("defensive_not_admitted" %in% r2$ev),
      "B2 방어형 FALSE → 등재 없이 현행대로 소비만", paste(r2$ev, collapse = ","))
  chk(!nzchar(paste(r2$note, collapse = "")),
      "B2b 평범한 비방어형은 텔레그램 줄을 만들지 않는다(소음 억제 · 저널에는 남는다)",
      paste(r2$note, collapse = "|"))

  r3 <- .run_gate(.mk("B3", "F", NULL))
  c3 <- if (length(r3$args)) vapply(r3$args, function(a) as.character(a$code %||% "")[1], "") else ""
  chk(!("defensive_admitted" %in% r3$ev) && ("ledger_consumed" %in% r3$ev) &&
      any(c3 == "dscore_absent"),
      "B3 defensive_score 부재 → 소비하되 사유가 dscore_absent 로 남는다",
      paste(paste(r3$ev, collapse = ","), paste(c3, collapse = ",")))
  chk(nzchar(paste(r3$note, collapse = "")) && grepl("dscore_absent", paste(r3$note, collapse = "")),
      "B3b 방어형 **미산출**은 텔레그램에도 뜬다 — 배선·측정 결손 신호이지 정상 결과가 아니다",
      paste(r3$note, collapse = "|"))

  ## B4 — 러너의 **진짜 조건식**을 꺼내 PORT_t ≥ 문턱에서 FALSE 인지 본다(분기 미진입).
  cond <- tryCatch(GATE$expr[[1]][[2]], error = function(e) NULL)
  if (is.null(cond)) {
    ng("B4 게이트 조건식 추출 실패")
  } else {
    e4 <- new.env(parent = globalenv()); e4$.min_pt <- 0; e4$.resc_ok <- FALSE
    e4$.base_pt <- 0.5;  v_pos <- isTRUE(eval(cond, envir = e4))
    e4$.base_pt <- -0.5; v_neg <- isTRUE(eval(cond, envir = e4))
    chk(!v_pos && v_neg, "B4 PORT_t ≥ 문턱 → 분기 미진입 · 미만 → 진입 (조건식 양방향)",
        sprintf("pos=%s neg=%s", v_pos, v_neg))
  }

  ## B5 — 위반 주입(양성 대조): 등재 호출을 깨면 defensive_admitted 가 사라져야 한다.
  ##      사라지지 않으면 위 B1 초록은 검출력이 없다는 뜻이다.
  r5 <- .run_gate(.mk("B5", "F", .ds(TRUE)),
                  mutate = c("rmm_admission(", "rmm_admission_REMOVED("))
  chk(!("defensive_admitted" %in% r5$ev),
      "B5 위반 주입(등재 호출 제거) → defensive_admitted 소실 = B1 에 검출력이 있다",
      paste(r5$ev, collapse = ","))
}

cat("\n[C] 생산 레인 등재 — 계약 floor 를 우회하지 않고, 못 넣으면 사유가 남는다\n")
unlink(TLOG, force = TRUE)
C1 <- .mk("C1", "F", .ds(TRUE))
r1c <- RMM$rmm_register_measured(C1$dir, origin_mode = "test_fixture",
                                 catalog_path = TCAT, quarantine_path = TQ)
chk(isTRUE(r1c$registered) && identical(r1c$code, "registered"),
    "C1 방어형 산출물 등재 성공", paste(r1c$code, r1c$reason))
MCT <- fromJSON(TCAT, simplifyVector = FALSE)$modules
e1 <- MCT[[C1$sid]]
chk(!is.null(e1) && isTRUE(e1$fr_eligible) && identical(e1$metric_type, "backtested") &&
    identical(as.character(e1$essence_grade), "F") && isTRUE(e1$defensive_score$defensive),
    "C1b 카탈로그 항목에 essence_grade + defensive_score 가 실린다",
    paste(names(e1 %||% list()), collapse = ","))
chk(!is.null(e1) && identical(unname(tools::md5sum(file.path(ROOT, e1$sim_result_path))),
                              as.character(e1$module_hash)),
    "C1c module_hash = 저장된 sim_result.rds md5 (frozen 신뢰 계약)",
    "불일치면 소비자 .verify_module_hash 가 SKIP 한다")

suppressMessages(source(file.path(ROOT, "02_Infrastructure/regime/l2_pool_admission.R")))
adm_cat <- l2_admit_catalog(MCT)
chk(adm_cat$n_admitted >= 1L && adm_cat$n_defensive >= 1L,
    "C1d 등재분을 소비자(l2_admit_catalog)가 실제로 편입한다 — 왕복 확인",
    paste(names(adm_cat$tally), collapse = ","))

C2 <- .mk("C2", "F", .ds(TRUE), metric_type = "proxy")
r2c <- RMM$rmm_register_measured(C2$dir, catalog_path = TCAT, quarantine_path = TQ)
J <- .jl()
chk(!isTRUE(r2c$registered) && grepl("^contract_floor", r2c$code) &&
    any(J$event == "module_register_blocked"),
    "C2 계약 floor 미충족(metric_type=proxy) → 미등재 + 저널 사유 (조용한 실패 없음)",
    paste(r2c$code, paste(unique(J$event), collapse = ",")))

C3 <- .mk("C3", "F", .ds(TRUE), with_csv = FALSE)
r3c <- RMM$rmm_register_measured(C3$dir, catalog_path = TCAT, quarantine_path = TQ)
chk(!isTRUE(r3c$registered) && startsWith(r3c$code, "sim_unavailable"),
    "C3 재료(계약 CSV) 부재 → sim_unavailable 사유 · 새 백테를 돌리지 않는다", r3c$code)

C4 <- .mk("C4", "F", .ds(TRUE), with_auth = FALSE)
r4c <- RMM$rmm_register_measured(C4$dir, catalog_path = TCAT, quarantine_path = TQ)
chk(!isTRUE(r4c$registered) && identical(r4c$code, "auth_absent"),
    "C4 권위 산출물 부재 → auth_absent (계약 미경유 = 미측정)", r4c$code)

C5 <- .mk("C5", "C", .ds(FALSE))
r5c <- RMM$rmm_register_measured(C5$dir, catalog_path = TCAT, quarantine_path = TQ)
chk(!isTRUE(r5c$registered) && identical(r5c$code, "not_defensive"),
    "C5 등급 C ∧ 비방어형 → 등재하지 않는다 (카탈로그 폭주 방지)", r5c$code)

## C6 — 생산 레인(run_paper_replication)의 등재 블록을 잘라 실제로 구동한다.
RP <- file.path(ROOT, "02_Infrastructure/alpha_search/run_paper_replication.R")
RL <- readLines(RP, warn = FALSE)
i_rp <- grep("QVEST_RP_REGISTER", RL, fixed = TRUE)
i_rp <- i_rp[grepl("if (", RL[i_rp], fixed = TRUE)]
BLK <- if (length(i_rp)) .take_expr(RL, i_rp[1]) else NULL
if (is.null(BLK)) {
  ng("C6 생산 레인 등재 블록을 찾지 못했다", "앵커 = kill switch env 이름 QVEST_RP_REGISTER")
} else {
  C6 <- .mk("C6", "B", .ds(FALSE))
  sb <- new.env(parent = globalenv())
  sb$.RP_INFRA <- file.path(ROOT, "02_Infrastructure")
  sb$OUT_DIR <- C6$dir
  sb$sim_grade <- NULL                               # 메모리 재료 없음 → 계약 CSV 폴백 경로
  sb$strategy_idea <- "fixture"; sb$strategy_name <- "C6"; sb$.sp_url <- "http://x"
  sb$source_paper <- list(paper_key = "fixture.c6")
  sb$portfolio_spec <- list(construction = "top_n_long")
  sb$weights_engine_direct <- FALSE
  sb$`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L ||
                                  (length(a) == 1L && is.na(a))) b else a
  err <- NULL
  tryCatch(eval(BLK$expr[[1]], envir = sb), error = function(e) err <<- conditionMessage(e))
  MC6 <- fromJSON(TCAT, simplifyVector = FALSE)$modules
  chk(is.null(err) && !is.null(MC6[[C6$sid]]),
      "C6 run_paper_replication 의 등재 블록이 실제로 등재를 일으킨다 (충실구현·결합·강화 셀 공통 경유)",
      err %||% "카탈로그에 항목 없음")
}

## C7 — **메모리 sim** 경로. 라이브 레인은 항상 sim_grade 를 넘기는데, replication_harness 의
##   DAILY_NAV_DT 는 (Date, NAV, NAV_gross) 라 Strategy_Ret 이 없다 — 계약 검증도 소비자도
##   그 열을 요구한다. 어댑터(rmm_normalize_sim)가 그 모양 차이를 메우는지 실측한다.
C7 <- .mk("C7", "F", .ds(TRUE))
set.seed(7); n7 <- 500L
d7 <- data.table(Date = seq(as.Date("2019-01-01"), by = "day", length.out = n7),
                 r = rnorm(n7, 2e-4, 0.01))
sim7 <- list(strategy_xts = xts::xts(d7$r, order.by = d7$Date),
             DAILY_NAV_DT = data.table(Date = d7$Date, NAV = cumprod(1 + d7$r),
                                       NAV_gross = cumprod(1 + d7$r + 1e-5)),
             bm_xts = xts::xts(rnorm(n7, 1e-4, 0.011), order.by = d7$Date),
             diagnostics = list(n_max = 25L, has_short = FALSE))
r7c <- RMM$rmm_register_measured(C7$dir, sim_result = sim7,
                                 catalog_path = TCAT, quarantine_path = TQ)
MC7 <- fromJSON(TCAT, simplifyVector = FALSE)$modules
s7 <- tryCatch(readRDS(file.path(ROOT, MC7[[C7$sid]]$sim_result_path)), error = function(e) NULL)
chk(isTRUE(r7c$registered) && !is.null(s7) &&
    all(c("Date", "Strategy_Ret") %in% names(as.data.table(s7$DAILY_NAV_DT))),
    "C7 메모리 sim(Strategy_Ret 없는 harness 모양) → 어댑터가 붙여 등재한다", r7c$code)

cat("\n[D] 격리 — 운영 원장·저널을 건드리지 않는다\n")
ops <- tryCatch(fromJSON(OPS_CAT, simplifyVector = FALSE)$modules, error = function(e) NULL)
fixids <- grep("^RP_FIX_", names(ops %||% list()), value = TRUE)
chk(!length(fixids), "D1 운영 module_catalog 에 픽스처 id 가 없다", paste(fixids, collapse = ","))
opslog <- if (file.exists(OPS_LOG)) tail(readLines(OPS_LOG, warn = FALSE), 400) else character(0)
chk(!any(grepl("RP_FIX_", opslog, fixed = TRUE)),
    "D2 운영 저널에 픽스처 흔적이 없다", "QVEST_RP_JLOG 경로 확인")
LED_MD5_1 <- if (file.exists(OPS_LED)) unname(tools::md5sum(OPS_LED)) else NA_character_
if (identical(LED_MD5_0, LED_MD5_1)) {
  ok("D3 강화 원장 불변")
} else {
  cat("  WARN D3 원장 md5 변동 — 무인 레인이 병렬로 돌면 정상(이 검사는 원장을 쓰지 않는다)\n")
}

## ★register_module 은 sim_result 를 04_Research/strategies/{id} 에 **실제로** 쓴다
##   (그 경로는 계약이 정하고 인자로 못 돌린다). 픽스처 접두 RP_FIX_ 로 격리하고 지운다 —
##   남기면 auto_commit_on_stop 이 저장소에 쓸어 담고, 다음 실행이 자기 잔재를 본다.
FIXDIRS <- Sys.glob(file.path(ROOT, "04_Research/strategies/RP_FIX_*"))
unlink(FIXDIRS, recursive = TRUE, force = TRUE)
chk(!length(Sys.glob(file.path(ROOT, "04_Research/strategies/RP_FIX_*"))),
    "D4 픽스처 sim_result 디렉터리 정리됨", paste(basename(FIXDIRS), collapse = ","))

Sys.unsetenv("QVEST_MODULE_CATALOG"); Sys.unsetenv("QVEST_MODULE_QUARANTINE")
unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("\n=== test_module_admission_seam: PASS %d / FAIL %d ===\n", PASS, FAIL))
quit(status = if (FAIL > 0L) 1L else 0L)
