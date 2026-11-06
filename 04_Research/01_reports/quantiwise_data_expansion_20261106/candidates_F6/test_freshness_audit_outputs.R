#!/usr/bin/env Rscript
#==============================================================================
# test_freshness_audit_outputs.R — 신선도 감사 출력별 검사(F6 · 2026-11-06) 양방향 시험
#
# 대상 = 02_Infrastructure/ops/morning_steps/freshness_audit.R(기본). 설치 전에는 --audit <사본 경로>.
# 계획 = 04_Research/01_reports/quantiwise_data_expansion_20261106/PLAN.md §3.0 F6 · §3.9 · §3.11('freshness 출력별 시험')
#
# 왜: 감사기가 패널마다 대표 파일 1개(eps_1y · investor_all · us_k200)의 max(Date)만 봐서 11-06 세 구멍
#   (컨센서스 4지표 10-19 · 수급 10-20~10-30 개인 · 기타법인 0행 · 외국인 1/3 · 유니버스 sector_lv2 10-30)이 모두 FRESH 였다.
#   이 시험은 감사기 **자체를** 모래상자 루트에서 source 해(재구현 없음) 다음을 잰다:
#   P  양성 대조 — 깨끗한 책(자연 변동 ±12% · 하루 0.78 급감 · 수준 30% 하락 · 유니버스 base→증분 행 구조 전환)은 경보 0
#   V  위반 주입 10 — 최신일 0행 · 끝 부분 채움/0행 구간 · 스냅숏 결손 · 내부 구멍 · 파생 사본 지연 · 출력 부재 ·
#      목록 밖 출력(+ 목록 밖 유형의 행 없는 날은 구멍 · 복구 창이 아니다) · report_only 일반화 · 기존 판정 불변 · 창 첫머리 구멍
#   V11 견고성 — 보고 출력 · JSON 조립 · 직렬화 실패가 EDC_RESULT · 판정 JSON · FA 줄 · stale 경보 경로를 끊지 않는다
#   T  텔레그램 서명 관문 — 새 구멍 1통 · 반복 0통 · 숫자만 변해도 0통 · 변경 1통 · 해소 1통 · 발송 실패면 미커밋 · QUIET 무접촉
#   U  측정 불가(2차) — 달력 source 열 소실 · 달력 판독 실패에도 '해소'를 보내지 않는다 · 원복 뒤 '새 경보' 재발송 없음 ·
#      미측정 중 실제로 메워지면 창 밖 재측정이 해소를 본다
#   W  창 이동(2차) — OHLCVS base 재수출로 E 가 뒤로 가도 창 밖 구멍은 유지(무음) · 창 시작을 가로지르는 구멍도 무음 ·
#      창 밖 구멍이 실제로 메워지면 '변경' · 다 메워지면 '해소'
#   R  구멍 기록 갱신(2차) — 같은 서명이 이어지는 동안 구간 끝을 고쳐 적어, 창 밖 재측정이 늘어난 끝까지 본다
#   D  하루 경과(2차) — 감사기 today 를 하루 당겨 '어제'를 잰 뒤 '오늘'을 잰다: ① 책 전체 정체(lag 만 +1) ② 한 출력만
#      정체(구멍 끝은 늘고 시작은 고정) — 둘 다 발송 0통
#   L  글자 수 상한(2차) — 4,096자(UTF-16)를 넘을 본문은 잘라 보내고(생략 표기) 커밋한다 · 스텁은 실 API 처럼 초과 = 400
#   S  정적 — 텔레그램 리터럴 균질 · 기존 계약 닻(다른 시험이 보는 문자열) · 이식성 금칙 · 출력 목록 ↔ 파서 정의(정적 파싱)
#   X  운영 호출 형태 — 새 Rscript 프로세스(--no-save <감사기> · ~/.Renviron 차단)의 EDC_RESULT · FA_OUTPUT_WARN 줄
#   M  돌연변이 — 소스 텍스트 치환(대상 문자열 정확히 1회 · 치환 성사 단정) 사본에서 해당 시나리오가 빨개지는지
# 부작용: 없음 — 쓰기는 tempdir 모래상자뿐. 운영 .cache · qepm · 06_Registry 무접촉 · 텔레그램은 모래상자 스텁(발송 0).
#   감사기를 같은 R 프로세스에서 source 하므로 QM_ROOT 는 Sys.setenv 로 바꾼다(~/.Renviron 은 기동 때만 읽힌다) — 끝에 복원.
# 사용: Rscript 08_Tests/data/test_freshness_audit_outputs.R [--audit <freshness_audit.R>]
# 요약: 마지막 줄 {"test":"freshness_audit_outputs","pass":N,"fail":M}
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
T_NAME <- "freshness_audit_outputs"
.MARK <- "02_Infrastructure/hooks/qvest_hook_router.py"
.abs <- function(p) if (grepl("^([A-Za-z]:)?[/\\\\]", p) || grepl("^~", p)) p else file.path(getwd(), p)
.self_root <- function() {
  a <- commandArgs(trailingOnly = FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (!length(f)) return("")
  gsub("\\\\", "/", dirname(dirname(dirname(.abs(f[1L])))))
}
## 앵커 순서(r-portability ④-b — 시험 러너는 self-first): 자기 위치 → CLAUDE_PROJECT_DIR → QM_ROOT. 표지로 검증한다.
.qv_order <- c(.self_root(), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))
ROOT <- ""
for (.c in .qv_order) if (nzchar(.c) && file.exists(file.path(.c, .MARK))) { ROOT <- gsub("\\\\", "/", .c); break }
.emit <- function(pass, fail, extra = list()) {
  cat(jsonlite::toJSON(c(list(test = T_NAME, pass = pass, fail = fail), extra), auto_unbox = TRUE), "\n", sep = "")
}
if (!nzchar(ROOT)) { .emit(0L, 1L, list(preflight = "no_root")); quit(status = 1) }
if (nzchar(.self_root()) && !identical(ROOT, .self_root()))
  message(sprintf("⚠ ANCHOR OVERRIDE — 자기 트리(%s) 대신 %s 를 쓴다", .self_root(), ROOT))
.args <- commandArgs(trailingOnly = TRUE)
.arg <- function(k) { i <- match(k, .args); if (is.na(i) || i == length(.args)) NULL else .args[i + 1L] }
AUDIT <- .arg("--audit") %||% file.path(ROOT, "02_Infrastructure/ops/morning_steps/freshness_audit.R")
AUDIT <- gsub("\\\\", "/", AUDIT)

## ── 사전 점검(카나리아) — 대상이 없거나 F6 이 없으면 케이스를 돌리지 않는다(0/N 을 '검거 실패'로 오독하지 않게) ──
.pre <- if (!file.exists(AUDIT)) "audit_missing" else {
  src0 <- tryCatch(readLines(AUDIT, encoding = "UTF-8", warn = FALSE), error = function(e) NULL)
  if (is.null(src0)) "audit_unreadable"
  else if (inherits(tryCatch(parse(text = src0, keep.source = FALSE), error = function(e) e), "error")) "audit_parse_error"
  else if (!any(grepl(".fa_output_audit <- function", src0, fixed = TRUE))) "f6_not_installed"
  else ""
}
if (nzchar(.pre)) { cat(sprintf("  preflight FAIL: %s (%s)\n", .pre, AUDIT)); .emit(0L, 1L, list(preflight = .pre)); quit(status = 1) }
SRC <- paste(readLines(AUDIT, encoding = "UTF-8", warn = FALSE), collapse = "\n")
cat(sprintf("== %s — 대상 %s ==\n", T_NAME, AUDIT))

PASS <- 0L; FAIL <- 0L
chk <- function(label, cond, detail = "") {
  ok <- isTRUE(cond)
  if (ok) PASS <<- PASS + 1L else FAIL <<- FAIL + 1L
  cat(sprintf("  %s %s%s\n", if (ok) "ok  " else "FAIL", label, if (!ok && nzchar(detail)) paste0(" — ", detail) else ""))
  invisible(ok)
}
chk_all <- function(v, prefix = "") for (k in names(v)) chk(paste0(prefix, k), v[[k]])

## ── 모래상자 ─────────────────────────────────────────────────────────────────
.TMP <- tempfile("fa_outputs_")
dir.create(.TMP, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(.TMP, recursive = TRUE, force = TRUE), onexit = TRUE))
.OLD_ENV <- Sys.getenv(c("QM_ROOT", "QVEST_FRESHNESS_QUIET"), unset = NA)

.wd <- function(from, to) { d <- seq(from, to, by = "day"); d[!format(d, "%u") %in% c("6", "7")] }
.prev_bd <- function(d) { t <- d - 1; while (format(t, "%u") %in% c("6", "7")) t <- t - 1; t }
AS_OF <- .prev_bd(Sys.Date())                       # 감사기 as_of 와 같은 규칙(합성 달력 = 평일 전부)
CAL <- .wd(seq(AS_OF, by = "-15 months", length.out = 2L)[2L], AS_OF)
N <- length(CAL); E_IDX <- N - 99L; E <- CAL[E_IDX]   # 증분 구간 = 마지막 100 거래일
DAYS <- CAL[(E_IDX - 60L):N]                        # 책 날짜 = base 60일 + 증분 100일(감사기는 E 부터 읽는다)
.exp_W <- function() { ym <- format(CAL, "%Y-%m"); m <- table(ym[ym < format(AS_OF, "%Y-%m")])
                       as.integer(round(stats::median(utils::tail(as.integer(m), 12L)))) }
CONS <- c("eps_1y", "bps_1y", "dps_1y", "eps_chg_1m", "eps_chg_3m", "target_price", "sue",
          "revenue_fy1", "escr", "esbr", "coverage", "op_profit_fy1")
US <- c("sector_lv1", "sector_lv2", "float", "k200", "kq150", "trading_halt", "admin_stock", "unfaithful_disc")
INV <- c("Foreign", "Institutional", "Individual", "OtherCorp")
PANEL_KEYS <- c("msm_daily", "fred", "ktri_indices", "ktri_v3_signals", "regime_daily", "benchmark", "p3_forecast",
                "rawdata", "consensus", "investor_act", "universe_support", "fred_wide")
.tick <- function(n) sprintf("A%05d", seq_len(n))
.wp <- function(dt, p) { dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE); arrow::write_parquet(dt, p) }
.counts <- function(base, frac, seed) { set.seed(seed); pmax(3L, as.integer(round(base * (1 + stats::runif(length(DAYS), -frac, frac))))) }
.long <- function(dates, n, col) {
  dt <- data.table(Date = rep(dates, n), Ticker = unlist(lapply(n, .tick), use.names = FALSE))
  dt[, (col) := stats::runif(.N)][]
}
## 유니버스 스냅숏 날짜: 월말 평일(as_of 달 앞까지) + E 이후 완결 월의 15일 근처 평일 + as_of(수급 시점 스냅숏)
.month_end <- function(d) { ym <- format(d, "%Y-%m"); keep <- ym < format(AS_OF, "%Y-%m")
                            as.Date(vapply(split(as.numeric(d[keep]), ym[keep]), max, numeric(1))) }
ME <- .month_end(CAL)
MID <- as.Date(vapply(split(as.numeric(CAL[CAL >= E]), format(CAL[CAL >= E], "%Y-%m")),
                      function(x) x[which.min(abs(as.integer(format(as.Date(x), "%d")) - 15L))], numeric(1)))
MID <- MID[format(MID, "%Y-%m") < format(AS_OF, "%Y-%m")]
SNAP <- sort(unique(c(ME[ME >= DAYS[1]], MID, AS_OF)))
LAST_ME <- max(ME)
FIRST_ME_INC <- min(ME[ME >= E])

build_template <- function(root) {
  w <- function(rel, dt) .wp(dt, file.path(root, rel))
  dir.create(file.path(root, "02_Infrastructure/telegram"), recursive = TRUE)
  writeLines(c("# 시험 스텁 — config.R 대역(감사기는 경로를 상대로 쓴다)", "invisible(NULL)"),
             file.path(root, "02_Infrastructure/config.R"))
  writeLines(c("# 시험 스텁 — 발송 0. 호출을 FA_TEST_TG_LOG 에 적고 FA_TEST_TG_OK=0 이면 실패를 돌려준다.",
               "#   텔레그램 sendMessage 상한(4096 · UTF-16 코드 단위로 보수 셈)을 넘으면 실 API 처럼 400 을 돌려준다.",
               "tg_send <- function(msg, parse_mode = '', silent = FALSE, validate_emoji = TRUE, emoji_min = 1L, mute = FALSE) {",
               "  u <- tryCatch({ cp <- utf8ToInt(enc2utf8(msg)); length(cp) + sum(cp > 65535L) }, error = function(e) nchar(msg, type = 'bytes'))",
               "  ok <- !identical(Sys.getenv('FA_TEST_TG_OK'), '0') && isTRUE(u <= 4096L)",
               "  cat(jsonlite::toJSON(list(msg = msg, mute = mute, ok = ok, u16 = u), auto_unbox = TRUE), '\\n', sep = '',",
               "      file = Sys.getenv('FA_TEST_TG_LOG'), append = TRUE)",
               "  invisible(list(ok = ok, kind = if (ok) 'sent' else 'http_error', status = if (ok) 200L else 400L, error = NA_character_))",
               "}"), file.path(root, "02_Infrastructure/telegram/telegram_notify.R"))
  w(".cache/trading_calendar.parquet",
    data.table(Date = CAL, source = ifelse(CAL < E, "quantiwise", "quantiwise_update")))
  ## 기존 패널(판정 축) — 전부 신선
  rec <- data.table(Date = utils::tail(CAL, 30L))
  for (rel in c(".cache/msm_asof_daily.parquet", ".cache/fred_macro.parquet", ".cache/ktri_indices.parquet",
                ".cache/unified_regime_signal_daily.parquet", ".cache/benchmark.parquet", ".cache/RAWDATA.parquet",
                ".cache/fred_macro_wide.parquet",
                "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet")) w(rel, rec)
  p <- file.path(root, "04_Research/regime_comparison/output/ktri_v3_signals.csv")
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(data.table(DATE = format(utils::tail(CAL, 30L)), v = 1), p)
  ## 컨센서스 12 — 계단형 3종(sue · escr · esbr: 변동 0) · 나머지 ±12%
  for (i in seq_along(CONS)) {
    m <- CONS[i]
    n <- if (m %in% c("sue", "escr", "esbr")) rep(30L + i, length(DAYS)) else .counts(40 + i, 0.12, 100 + i)
    w(sprintf(".cache/consensus/%s.parquet", m), .long(DAYS, n, m))
  }
  w(".cache/consensus/ticker_map.parquet", data.table(Ticker = .tick(80), Name = "x"))
  ## 수급 4유형 — 기관 하루 0.78 급감 · 기타법인 수준 30% 하락(자연 변동 · 판정 밖이어야 한다)
  nI <- list(Foreign = .counts(60, 0.03, 201), Institutional = .counts(45, 0.10, 202),
             Individual = .counts(60, 0.03, 203), OtherCorp = .counts(35, 0.12, 204))
  dip <- which(DAYS == CAL[N - 50L]); nI$Institutional[dip] <- as.integer(round(stats::median(nI$Institutional) * 0.78))
  sh <- which(DAYS >= CAL[N - 40L]); nI$OtherCorp[sh] <- as.integer(round(nI$OtherCorp[sh] * 0.7))
  inv <- rbindlist(lapply(INV, function(g) {
    d <- data.table(Date = rep(DAYS, nI[[g]]), Ticker = unlist(lapply(nI[[g]], .tick), use.names = FALSE))
    d[, `:=`(NetBuy = stats::runif(.N) + 0.1, InvestorType = g)][]
  }))
  setorder(inv, Date, Ticker, InvestorType)
  w(".cache/investor_stock/investor_all.parquet", inv)
  regen_derived(root)
  ## 유니버스 8 — base 스냅숏 100행 · 증분 첫 월말도 100행(base 구조 잔재 — 실측 03-31 6,383행) · 이후 40행(k200 · kq150 = 60)
  for (u in US) {
    inc <- if (u %in% c("k200", "kq150")) 60L else 40L
    n <- ifelse(SNAP < E | SNAP == FIRST_ME_INC, 100L, inc)
    w(sprintf(".cache/universe_support/us_%s.parquet", u), .long(SNAP, n, "Value"))
  }
}
regen_derived <- function(root) {   # 적재기(incremental_investor)와 같은 파생 재생성: 유형 분리 4종 + wide(fill = 0)
  inv <- as.data.table(arrow::read_parquet(file.path(root, ".cache/investor_stock/investor_all.parquet"), mmap = FALSE))
  for (g in INV) .wp(inv[InvestorType == g], file.path(root, sprintf(".cache/investor_stock/investor_%s.parquet", tolower(g))))
  .wp(dcast(inv[InvestorType %in% INV], Date + Ticker ~ InvestorType, value.var = "NetBuy", fill = 0),
      file.path(root, ".cache/investor_stock/investor_wide.parquet"))
}
TEMPLATE <- file.path(.TMP, "template")
dir.create(TEMPLATE)
build_template(TEMPLATE)
.sb_n <- 0L
new_sb <- function() {
  .sb_n <<- .sb_n + 1L
  sb <- file.path(.TMP, sprintf("sb%02d", .sb_n)); dir.create(sb)
  file.copy(list.files(TEMPLATE, full.names = TRUE, all.files = TRUE, no.. = TRUE), sb, recursive = TRUE)
  gsub("\\\\", "/", sb)
}
restore_books <- function(sb) {   # 책 3종만 원판으로(상태 파일 · 로그는 그대로)
  for (d in c("consensus", "investor_stock", "universe_support")) {
    unlink(file.path(sb, ".cache", d), recursive = TRUE)
    file.copy(file.path(TEMPLATE, ".cache", d), file.path(sb, ".cache"), recursive = TRUE)
  }
}
## 주입 도구 — frac = 그날 남길 비율(0 = 행 전부 삭제)
## ★mmap 없이 읽는다 — Windows 는 매핑이 열린 파일의 덮어쓰기를 거부한다(같은 프로세스가 곧바로 그 파일을 다시 쓴다)
.rw <- function(sb, rel, f) { p <- file.path(sb, rel); d <- as.data.table(arrow::read_parquet(p, mmap = FALSE)); .wp(f(d), p) }
.rwp <- function(p, f) { d <- as.data.table(arrow::read_parquet(p, mmap = FALSE)); .wp(f(d), p) }   # 절대 경로판
.thin <- function(d, dates, frac) {
  d[, .k := !(Date %in% dates) | seq_len(.N) <= ceiling(frac * .N), by = Date][.k == TRUE][, .k := NULL][]
}
cons_mod <- function(sb, m, dates, frac = 0) .rw(sb, sprintf(".cache/consensus/%s.parquet", m), function(d) .thin(d, dates, frac))
us_mod <- function(sb, u, dates) .rw(sb, sprintf(".cache/universe_support/us_%s.parquet", u), function(d) d[!Date %in% dates])
inv_mod <- function(sb, g, dates, frac = 0) {
  .rw(sb, ".cache/investor_stock/investor_all.parquet", function(d) {
    a <- .thin(d[InvestorType == g], dates, frac); r <- rbind(d[InvestorType != g], a); setorder(r, Date, Ticker, InvestorType); r
  })
  regen_derived(sb)
}
panel_stale <- function(sb, rel, keep_to) .rw(sb, rel, function(d) d[Date <= keep_to])

## ── 실행 — 감사기를 이 프로세스에서 source(재구현 없음) ─────────────────────────
.parse_line <- function(out, prefix) {
  l <- utils::tail(grep(paste0("^", prefix, " "), out, value = TRUE), 1L)
  if (!length(l)) return(NULL)
  kv <- strsplit(sub(paste0("^", prefix, " "), "", l), " ", fixed = TRUE)[[1]]
  stats::setNames(as.list(sub("^[^=]*=", "", kv)), sub("=.*$", "", kv))
}
run_audit <- function(src, sb, quiet = TRUE, tg_ok = TRUE, today = NULL) {
  ## ★발송 방어 2겹 — ①작업 폴더 = 모래상자(감사기의 QM_ROOT 폴백이 getwd() 라 호출자 폴더(실트리)로 새지 않게)
  ##   ②발송 허용 실행 전, 전역 tg_send 가 있으면 스텁인지 확인(실 telegram_notify.R 이 올라와 있으면 시험을 멈춘다)
  old <- getwd(); on.exit(setwd(old), add = TRUE); setwd(sb)
  if (!quiet && exists("tg_send", envir = globalenv(), inherits = FALSE) &&
      !any(grepl("FA_TEST_TG_LOG", deparse(get("tg_send", envir = globalenv())), fixed = TRUE)))
    stop("실 tg_send 가 전역에 있다 — 발송 허용 실행을 거부한다")
  tgf <- file.path(sb, "tg_calls.jsonl"); n0 <- if (file.exists(tgf)) length(readLines(tgf, warn = FALSE)) else 0L
  Sys.setenv(QM_ROOT = sb, QVEST_FRESHNESS_QUIET = if (quiet) "1" else "0", FA_TEST_TG_LOG = tgf, FA_TEST_TG_OK = if (tg_ok) "1" else "0")
  env <- new.env(parent = globalenv())
  ## '하루 경과' 모사(D · R 축) — 감사기의 Sys.Date() 를 이 실행 환경에서만 가린다(감사기 코드 · 운영 경로 무변경)
  if (!is.null(today)) assign("Sys.Date", local({ d <- as.Date(today); function() d }), envir = env)
  out <- tryCatch(utils::capture.output(source(src, local = env, encoding = "UTF-8")),
                  error = function(e) sprintf("SOURCE_ERROR %s", conditionMessage(e)))
  out <- gsub("\r", "", out, fixed = TRUE)
  js <- tryCatch(jsonlite::fromJSON(file.path(sb, "qepm/observability/morning_freshness_latest.json"), simplifyVector = FALSE),
                 error = function(e) NULL)
  tg <- if (file.exists(tgf)) readLines(tgf, encoding = "UTF-8", warn = FALSE) else character(0)
  tg_new <- if (length(tg) > n0) lapply(tg[(n0 + 1L):length(tg)], jsonlite::fromJSON) else list()
  stf <- file.path(sb, ".cache/freshness_output_warn_state.json")
  rm(env); invisible(gc())   # 감사기의 기존 패널 읽기(read_parquet 기본 mmap)가 남긴 매핑을 풀어 다음 주입 쓰기를 막지 않게
  list(out = out, js = js, tg = tg_new, tg_n = length(tg_new), st = if (file.exists(stf)) readLines(stf, warn = FALSE) else NULL,
       edc = .parse_line(out, "EDC_RESULT"), fa = .parse_line(out, "FA_OUTPUT_WARN"), err = any(grepl("^SOURCE_ERROR", out)))
}
it <- function(r, k) r$js$output_audit$items[[k]]
.v <- function(r, k) identical(it(r, k)$verdict, "WARN")
.st_sig <- function(r) { if (is.null(r$st)) return(NA_character_); s <- jsonlite::fromJSON(paste(r$st, collapse = "\n"))$signature
                         if (is.null(s)) NA_character_ else s }

## ── 시나리오(주입 + 단언). 단언은 이름 붙은 논리 벡터 — 돌연변이 판정이 같은 단언을 다시 쓴다 ─────────
## .lv — 단언마다 따로 평가한다(하나가 오류여도 나머지를 잰다 · 오류 = FALSE). 돌연변이가 감사기 F6 구간을 깨뜨려
##   출력이 비어도(NULL) '실행기 오류'가 아니라 '단언 실패'로 읽히게 한다.
.lv <- function(...) {
  ex <- as.list(substitute(list(...)))[-1L]; pf <- parent.frame()
  vapply(ex, function(e) isTRUE(tryCatch(eval(e, pf), error = function(err) FALSE)), logical(1))
}
L9 <- utils::tail(CAL, 9L)
sc <- list(
  P = list(mod = function(sb) NULL, test = function(r) {
    oa <- r$js$output_audit; its <- oa$items
    main <- its[!grepl("derived_", names(its))]
    .lv(P1_edc_clean = identical(r$edc$stale, "0") && identical(r$edc$items, "-"),
      P2_fa_line = identical(r$fa$status, "OK") && identical(r$fa$n, "0") && identical(r$fa$items, "-"),
      P3_items_29 = length(its) == 29L && all(c(paste0("consensus.", CONS), paste0("investor_act.", INV),
                                                paste0("universe_support.", US)) %in% names(its)),
      P4_all_ok = all(vapply(its, function(x) identical(x$verdict, "OK"), logical(1))),
      P5_panel_keys_unchanged = identical(sort(names(r$js$audits)), sort(PANEL_KEYS)) && length(r$js$stale_items) == 0L &&
        identical(unlist(r$js$downstream_items), "p3_forecast"),
      P6_meta_E_W_L = identical(oa$meta$window_from, as.character(E)) && identical(as.integer(oa$meta$W), .exp_W()) &&
        identical(as.integer(oa$meta$L), sum(CAL >= E & CAL <= AS_OF)) && identical(oa$meta$role, "report_only"),
      P7_fill_measured = all(vapply(main, function(x) isTRUE(x$fill_latest$ok), logical(1))),
      ## 음성 대조가 문턱 근처를 실제로 지났는가(빈 대조 아님): 0.78 급감 · 30% 하락이 재졌고 통과했다
      P8_natural_dip_measured = isTRUE(it(r, "investor_act.Institutional")$min_ok_ratio < 0.85) &&
        isTRUE(it(r, "investor_act.OtherCorp")$min_ok_ratio < 0.8),
      P9_no_send_quiet = r$tg_n == 0L && !r$err)
  }),
  V1 = list(mod = function(sb) for (m in c("coverage", "esbr", "escr", "op_profit_fy1")) cons_mod(sb, m, AS_OF), test = function(r) {
    k4 <- paste0("consensus.", c("coverage", "esbr", "escr", "op_profit_fy1"))
    .lv(V1_panel_blind = identical(r$js$audits$consensus$status, "FRESH"),   # 구판 맹점 재현 — 대표 eps_1y 는 멀쩡
      V1_warn4 = all(vapply(k4, function(k) .v(r, k), logical(1))),
      V1_latest_underfill = all(vapply(k4, function(k) identical(it(r, k)$fill_latest$ok, FALSE) &&
                                         identical(it(r, k)$fill_latest$date, as.character(AS_OF)), logical(1))),
      V1_hole_at_horizon = all(vapply(k4, function(k) { h <- it(r, k)$holes
        length(h) == 1L && identical(h[[1]]$from, as.character(AS_OF)) && identical(h[[1]]$kind, "zero") }, logical(1))),
      V1_others_ok = !any(vapply(setdiff(paste0("consensus.", CONS), k4), function(k) .v(r, k), logical(1))),
      V1_not_judged_edc = identical(r$edc$stale, "0") && identical(r$edc$items, "-"),
      V1_not_judged_json = length(r$js$stale_items) == 0L,
      V1_fa_line = identical(r$fa$n, "4") && setequal(strsplit(r$fa$items, ",", fixed = TRUE)[[1]], k4),
      V1_signature = all(paste0(k4, ":HOLE@", AS_OF) %in% strsplit(r$js$output_audit$signature, " ", fixed = TRUE)[[1]]))
  }),
  V2 = list(mod = function(sb) { inv_mod(sb, "Foreign", L9, 0.35); inv_mod(sb, "Individual", L9); inv_mod(sb, "OtherCorp", L9) },
            test = function(r) {
    F <- it(r, "investor_act.Foreign"); I <- it(r, "investor_act.Individual"); O <- it(r, "investor_act.OtherCorp")
    bk <- r$js$output_audit$books$investor_act
    .lv(V2_panel_blind = identical(r$js$audits$investor_act$status, "FRESH"),
      V2_foreign_partial = .v(r, "investor_act.Foreign") && identical(F$holes_n, 9L) && length(F$holes) == 1L &&
        identical(F$holes[[1]]$kind, "partial") && identical(F$holes[[1]]$from, as.character(L9[1])) && isTRUE(F$holes[[1]]$min_ratio < 0.5),
      V2_foreign_latest = identical(F$fill_latest$ok, FALSE) && isTRUE(F$fill_latest$ratio < 0.5),
      V2_indiv_zero = .v(r, "investor_act.Individual") && identical(I$holes_n, 9L) && identical(I$holes[[1]]$kind, "zero") &&
        identical(I$status, "STALE"),
      V2_other_zero = .v(r, "investor_act.OtherCorp") && identical(O$holes_n, 9L) && identical(O$holes[[1]]$kind, "zero"),
      V2_inst_ok = !.v(r, "investor_act.Institutional"),
      V2_derived_synced = all(vapply(paste0("investor_act.derived_", c("foreign", "institutional", "individual", "othercorp", "wide")),
                                     function(k) identical(it(r, k)$status, "SYNCED"), logical(1))),
      V2_not_judged = identical(r$edc$stale, "0") && length(r$js$stale_items) == 0L,
      V2_repair_hint = identical(bk$repair_from, as.character(L9[1])) &&
        grepl(sprintf("-Only Investor_Act -FromOverride Investor_Act=%s", format(L9[1], "%Y%m%d")), bk$repair_hint, fixed = TRUE))
  }),
  V3 = list(mod = function(sb) us_mod(sb, "sector_lv2", c(LAST_ME, AS_OF)), test = function(r) {
    S <- it(r, "universe_support.sector_lv2")
    .lv(V3_panel_blind = identical(r$js$audits$universe_support$status, "FRESH"),
      V3_lv2_holes = .v(r, "universe_support.sector_lv2") && identical(S$holes_n, 2L) && length(S$holes) == 1L &&
        identical(S$holes[[1]]$from, as.character(LAST_ME)) && identical(S$holes[[1]]$to, as.character(AS_OF)),
      V3_others_ok = !any(vapply(paste0("universe_support.", setdiff(US, "sector_lv2")), function(k) .v(r, k), logical(1))),
      V3_not_judged = identical(r$edc$stale, "0"))
  }),
  V4 = list(mod = function(sb) { cons_mod(sb, "dps_1y", CAL[N - 20L]); cons_mod(sb, "target_price", CAL[c(N - 30L, N - 29L)], 0.3) },
            test = function(r) {
    D <- it(r, "consensus.dps_1y"); P <- it(r, "consensus.target_price")
    .lv(V4_internal_zero = .v(r, "consensus.dps_1y") && identical(D$holes_n, 1L) && identical(D$holes[[1]]$from, as.character(CAL[N - 20L])) &&
        identical(D$status, "FRESH") && isTRUE(D$fill_latest$ok),
      V4_internal_partial = .v(r, "consensus.target_price") && identical(P$holes_n, 2L) && identical(P$holes[[1]]$kind, "partial") &&
        identical(P$holes[[1]]$from, as.character(CAL[N - 30L])) && identical(P$holes[[1]]$to, as.character(CAL[N - 29L])))
  }),
  V5 = list(mod = function(sb) .rw(sb, ".cache/investor_stock/investor_wide.parquet", function(d) d[Date <= CAL[N - 5L]]),
            test = function(r) {
    W <- it(r, "investor_act.derived_wide")
    .lv(V5_wide_behind = .v(r, "investor_act.derived_wide") && identical(W$status, "BEHIND") && identical(W$ref_date, as.character(AS_OF)),
      V5_primary_ok = !any(vapply(paste0("investor_act.", INV), function(k) .v(r, k), logical(1))))
  }),
  V6 = list(mod = function(sb) file.remove(file.path(sb, ".cache/consensus/sue.parquet")), test = function(r) {
    .lv(V6_missing = .v(r, "consensus.sue") && identical(it(r, "consensus.sue")$status, "MISSING"),
      V6_not_judged = identical(r$edc$stale, "0") && identical(r$js$audits$consensus$status, "FRESH"))
  }),
  V7 = list(mod = function(sb) {
    .wp(data.table(Date = utils::tail(CAL, 5L), Ticker = "A00001", x = 1), file.path(sb, ".cache/consensus/new_metric.parquet"))
    .rw(sb, ".cache/investor_stock/investor_all.parquet", function(d)
      rbind(d, data.table(Date = utils::tail(CAL, 5L), Ticker = "A00001", NetBuy = 1, InvestorType = "Pension")))
  }, test = function(r) {
    P <- it(r, "investor_act.Pension"); bk <- r$js$output_audit$books$investor_act
    .lv(V7_unlisted_file = .v(r, "consensus.new_metric") && identical(it(r, "consensus.new_metric")$status, "UNLISTED"),
      V7_unlisted_type = .v(r, "investor_act.Pension") && isTRUE(P$unlisted),
      ## 목록 밖 유형의 '행 없는 날'은 구멍이 아니다 — 구멍 · 채움을 재지 않고 책 복구 창에도 안 들어간다(검증 지적 4)
      V7_unlisted_type_no_holes = is.null(P$holes_n) && is.null(P$fill_latest) &&
        !grepl("investor_act.Pension:HOLE", r$js$output_audit$signature, fixed = TRUE),
      V7_unlisted_not_in_repair = is.null(bk$repair_from) && is.null(bk$repair_hint))
  }),
  ## 창 첫머리 구멍 — 기준선이 아직 없다(0행 판정만 남는다 · 실측 컨센서스 03-30~04-29 23거래일 계통)
  V10 = list(mod = function(sb) for (m in CONS) cons_mod(sb, m, CAL[E_IDX:(E_IDX + 4L)]), test = function(r) {
    .lv(V10_window_start_zero = all(vapply(paste0("consensus.", CONS), function(k) { h <- it(r, k)$holes
      .v(r, k) && length(h) >= 1L && identical(h[[1]]$from, as.character(E)) && identical(h[[1]]$days, 5L) &&
        identical(h[[1]]$kind, "zero") }, logical(1))))
  })
)
run_sc <- function(src, name, quiet = TRUE) { sb <- new_sb(); sc[[name]]$mod(sb); r <- run_audit(src, sb, quiet = quiet); list(r = r, sb = sb) }

## ── P · V ─────────────────────────────────────────────────────────────────────
cat("-- P 양성 대조 · V 위반 주입 --\n")
RES <- list()
for (nm in names(sc)) { RES[[nm]] <- run_sc(AUDIT, nm); chk_all(sc[[nm]]$test(RES[[nm]]$r)) }

## V8 — report_only 일반화(계획 §3.9): 패널 항목에 role 을 달면 판정에서 빠지고 출력별 경보로 간다 / 안 달면 기존대로 판정
.var_n <- 0L
## 치환 — 대상 문자열이 정확히 1회 있고 결과가 달라졌을 때만 성사(1회 초과 = 엉뚱한 자리를 바꿀 수 있어 실패로 본다)
.subst <- function(txt, old, new) {
  n <- lengths(regmatches(txt, gregexpr(old, txt, fixed = TRUE)))   # 개수만 센다(fixed — 금칙 ⑥ 기준 ①)
  out <- sub(old, new, txt, fixed = TRUE)
  list(text = out, applied = identical(as.integer(n), 1L) && !identical(out, txt))
}
.var <- function(old, new, base = SRC) {   # 시험 변형본(치환 성사 단정 포함)
  s <- .subst(base, old, new)
  .var_n <<- .var_n + 1L
  p <- file.path(.TMP, sprintf("variant_%03d.R", .var_n))
  writeLines(s$text, p, useBytes = TRUE)
  list(path = p, applied = s$applied)
}
.fw_line <- 'audits$fred_wide        <- check_freshness("fred_wide",        ".cache/fred_macro_wide.parquet",            "Date", 14)'
v8 <- .var(.fw_line, paste0(.fw_line, '\naudits$fred_wide$role <- "report_only"'))
chk("V8_variant_applied", v8$applied)
sb8 <- new_sb(); panel_stale(sb8, ".cache/fred_macro_wide.parquet", CAL[N - 20L])
r8 <- run_audit(v8$path, sb8)
chk("V8_report_only_not_in_edc", identical(r8$edc$stale, "0") && identical(r8$edc$items, "-") && length(r8$js$stale_items) == 0L)
chk("V8_report_only_in_fa", "fred_wide" %in% strsplit(r8$fa$items %||% "", ",", fixed = TRUE)[[1]] &&
      identical(it(r8, "fred_wide")$verdict, "WARN") && identical(r8$js$audits$fred_wide$role, "report_only"))
r8c <- run_audit(AUDIT, sb8)   # 같은 자료 · role 없음 = 기존 판정 그대로
chk("V8_control_judged", identical(r8c$edc$stale, "1") && identical(r8c$edc$items, "fred_wide") &&
      any(grepl("^fred_wide\\(STALE", unlist(r8c$js$stale_items))))

## V9 — 기존 판정 불변: F6 를 끈 변형본(= 구판 판정 경로)과 EDC 줄 · stale_items · audits 가 같다(구멍이 있어도 · 패널이 낡아도)
v0 <- .var(".fa_res <- tryCatch(.fa_output_audit(as_of, audits, .fa_st),", ".fa_res <- tryCatch(stop(\"F6 disabled (variant)\"),")
chk("V9_variant_applied", v0$applied)
sb9 <- new_sb(); sc$V1$mod(sb9); sc$V2$mod(sb9)
panel_stale(sb9, ".cache/benchmark.parquet", CAL[N - 5L])
panel_stale(sb9, "04_Research/decision_framework/bearish_forecast_v3/03_models/daily_predictions/P3_daily.parquet", CAL[N - 10L])
r9 <- run_audit(AUDIT, sb9); r9o <- run_audit(v0$path, sb9)
chk("V9_edc_identical", !is.null(r9$edc) && identical(r9$edc, r9o$edc) && identical(r9$edc$stale, "2") &&
      identical(r9$edc$items, "benchmark,p3_forecast"))
chk("V9_json_judgment_identical", identical(r9$js$stale_items, r9o$js$stale_items) && identical(r9$js$audits, r9o$js$audits) &&
      identical(r9$js$downstream_items, r9o$js$downstream_items) && identical(r9$js$stale_count, r9o$js$stale_count))
chk("V9_f6_failure_isolated", identical(r9o$fa$status, "ERROR") && identical(r9o$js$output_audit$status, "ERROR") && !r9o$err)

## X1 — 운영 호출 형태(새 프로세스 · Rscript --no-save <감사기>) — ensure_data_current · daily_refresh [0c] 가 부르는 방식 그대로.
##   ★~/.Renviron 이 QM_ROOT 를 실트리로 고정한다 → R_ENVIRON_USER = 빈 파일로 끊고 작업 폴더도 모래상자로 둔다
##     (안 끊으면 자식이 실트리를 재고 실 JSON 을 쓴다). 보호 단언 = 실트리 JSON 수정 시각 불변.
.rs <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
sbx <- new_sb(); sc$V1$mod(sbx)
.renv <- file.path(.TMP, "empty.Renviron"); writeLines(character(0), .renv)
.real_json <- file.path(ROOT, "qepm/observability/morning_freshness_latest.json"); .mt0 <- file.mtime(.real_json)
.oldx <- Sys.getenv(c("QM_ROOT", "QVEST_FRESHNESS_QUIET", "R_ENVIRON_USER"), unset = NA); .oldwd <- getwd()
Sys.setenv(QM_ROOT = sbx, QVEST_FRESHNESS_QUIET = "1", R_ENVIRON_USER = .renv); setwd(sbx)
xo <- tryCatch(suppressWarnings(system2(.rs, c("--no-save", shQuote(AUDIT)), stdout = TRUE, stderr = TRUE)),
               error = function(e) structure(conditionMessage(e), status = 127L))
setwd(.oldwd)
for (k in names(.oldx)) if (is.na(.oldx[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(.oldx[[k]]), k))
xs <- attr(xo, "status"); xs <- if (is.null(xs)) 0L else as.integer(xs)
xo <- gsub("\r", "", xo, fixed = TRUE); xe <- .parse_line(xo, "EDC_RESULT"); xf <- .parse_line(xo, "FA_OUTPUT_WARN")
chk("X1_child_rc0", identical(xs, 0L), paste(utils::tail(xo, 3L), collapse = " | "))
chk("X1_child_edc_unchanged", identical(xe$stale, "0") && identical(xe$items, "-") && identical(xe$as_of, as.character(AS_OF)))
chk("X1_child_fa_line", identical(xf$status, "OK") && identical(xf$n, "4"))
chk("X1_child_sandbox_only", file.exists(file.path(sbx, "qepm/observability/morning_freshness_latest.json")) &&
      identical(file.mtime(.real_json), .mt0))

## ── T 텔레그램 서명 관문(QUIET=0 · 스텁) ──────────────────────────────────────────
cat("-- T 텔레그램 서명 관문 --\n")
t_seq <- function(src) {   # 결과 = 이름 붙은 논리 벡터(돌연변이 판정이 다시 쓴다)
  sb <- new_sb(); sc$V2$mod(sb)
  r1 <- run_audit(src, sb, quiet = FALSE)
  r2 <- run_audit(src, sb, quiet = FALSE)
  inv_mod(sb, "Foreign", L9, 0.85)   # 같은 날들을 더 얇게(0.35 → 약 0.30): 숫자만 변하고 구간 시작일은 그대로
  r3 <- run_audit(src, sb, quiet = FALSE)
  cons_mod(sb, "dps_1y", CAL[N - 20L])
  r4 <- run_audit(src, sb, quiet = FALSE)
  restore_books(sb)
  r5 <- run_audit(src, sb, quiet = FALSE); r5b <- run_audit(src, sb, quiet = FALSE)
  sc$V1$mod(sb)
  r6 <- run_audit(src, sb, quiet = FALSE, tg_ok = FALSE); r6b <- run_audit(src, sb, quiet = FALSE)
  st_before <- r6b$st; r7 <- run_audit(src, sb, quiet = TRUE)
  m1 <- if (r1$tg_n) r1$tg[[1]]$msg else ""
  .lv(T1_new_one_push = r1$tg_n == 1L && startsWith(m1, "\U0001F573") && grepl("investor_act.Foreign: HOLE", m1, fixed = TRUE) &&
      identical(r1$tg[[1]]$mute, FALSE) && identical(.st_sig(r1), r1$js$output_audit$signature),
    T2_repeat_silent = r2$tg_n == 0L && any(grepl("[output-audit]", r2$out, fixed = TRUE)),
    T3_numbers_only_silent = r3$tg_n == 0L && isTRUE(it(r3, "investor_act.Foreign")$fill_latest$ratio < it(r1, "investor_act.Foreign")$fill_latest$ratio),
    T4_changed_one = r4$tg_n == 1L && grepl("변경", r4$tg[[1]]$msg, fixed = TRUE) && identical(.st_sig(r4), r4$js$output_audit$signature),
    T5_resolved_one = r5$tg_n == 1L && startsWith(r5$tg[[1]]$msg, "✅") && identical(.st_sig(r5), ""),
    T5b_clean_silent = r5b$tg_n == 0L,
    T6_fail_not_committed = r6$tg_n == 1L && identical(r6$tg[[1]]$ok, FALSE) && identical(.st_sig(r6), ""),
    T6b_retry_after_fail = r6b$tg_n == 1L && identical(.st_sig(r6b), r6b$js$output_audit$signature),
    T7_quiet_untouched = r7$tg_n == 0L && identical(r7$st, st_before))
}
chk_all(t_seq(AUDIT))
## T8 — 기존 stale 경보는 그대로(패널 낡음 · QUIET=0 → 기존 문구 1통)
sb8t <- new_sb(); panel_stale(sb8t, ".cache/benchmark.parquet", CAL[N - 5L])
r8t <- run_audit(AUDIT, sb8t, quiet = FALSE)
chk("T8_existing_stale_alert", r8t$tg_n == 1L && startsWith(r8t$tg[[1]]$msg, "\U0001F6A8 Morning Freshness Audit") &&
      grepl("benchmark(STALE", r8t$tg[[1]]$msg, fixed = TRUE))

## ── 2차 수리 축(11-06 독립 검증 지적 1 · 2 · 3 · 5) ───────────────────────────────────────
cat("-- U 측정 불가 · W 창 이동 · R 구멍 기록 · D 하루 경과 · L 상한 · V11 견고성 --\n")
.carry <- function(r) r$js$output_audit$carry %||% list()
## 이 축들은 F6 문구만 센다 — 패널 stale 경보(기존 동작 · 같은 실행에서 1통씩 따로 나간다)는 세지 않는다
.f6 <- function(r) Filter(function(m) grepl("출력별 신선도 경보", m$msg %||% "", fixed = TRUE), r$tg)
.f6n <- function(r) length(.f6(r))
.f6m <- function(r) { x <- .f6(r); if (length(x)) x[[1]] else list(msg = "", ok = NA) }
.carry_has <- function(r, token, status) any(vapply(.carry(r), function(z) identical(z$token, token) && identical(z$status, status), logical(1)))
.st_runs <- function(r) if (is.null(r$st)) NULL else jsonlite::fromJSON(paste(r$st, collapse = "\n"))$runs
.run_to <- function(ru, tok) if (is.data.frame(ru) && tok %in% ru$token) as.character(ru$to[ru$token == tok][1]) else NA_character_
## '어제 세계' — 책 3종 · 달력을 CAL[N-1] 까지로 자르고(감사기 today = CAL[N] → as_of = CAL[N-1]) 오늘 세계는 사본에서 복원한다
.day_save <- function(sb) {
  d <- file.path(sb, "_today"); unlink(d, recursive = TRUE); dir.create(d)
  for (x in c("consensus", "investor_stock", "universe_support")) file.copy(file.path(sb, ".cache", x), d, recursive = TRUE)
  file.copy(file.path(sb, ".cache/trading_calendar.parquet"), d)
  d
}
.day_back <- function(sb) {
  for (x in c("consensus", "universe_support"))
    for (p in list.files(file.path(sb, ".cache", x), pattern = "[.]parquet$", full.names = TRUE))
      if (!identical(basename(p), "ticker_map.parquet")) .rwp(p, function(d) d[Date <= CAL[N - 1L]])
  .rw(sb, ".cache/investor_stock/investor_all.parquet", function(d) d[Date <= CAL[N - 1L]]); regen_derived(sb)
  .rw(sb, ".cache/trading_calendar.parquet", function(d) d[Date <= CAL[N - 1L]])
}
.day_fwd <- function(sb, d) {
  for (x in c("consensus", "investor_stock", "universe_support")) {
    unlink(file.path(sb, ".cache", x), recursive = TRUE); file.copy(file.path(d, x), file.path(sb, ".cache"), recursive = TRUE)
  }
  file.copy(file.path(d, "trading_calendar.parquet"), file.path(sb, ".cache"), overwrite = TRUE)
}
.relabel <- function(sb, base_to) .rw(sb, ".cache/trading_calendar.parquet", function(d)   # OHLCVS base 재수출 모사(창 시작 E 이동)
  d[, source := ifelse(Date <= base_to, "quantiwise", "quantiwise_update")][])

## U — 측정 불가는 해소가 아니다(검증 지적 1). 직전 통지 = 수급 3구멍(V2) + dps_1y 내부 0행 1일.
u_seq <- function(src) {
  sb <- new_sb(); sc$V2$mod(sb); cons_mod(sb, "dps_1y", CAL[N - 20L])
  r0 <- run_audit(src, sb, quiet = FALSE); s0 <- .st_sig(r0)
  calp <- file.path(sb, ".cache/trading_calendar.parquet"); calb <- file.path(sb, "cal_backup.parquet"); file.copy(calp, calb)
  .rw(sb, ".cache/trading_calendar.parquet", function(d) d[, list(Date)])   # source 열 소실 → E = NA(날짜는 있다 → 창 밖 재측정)
  r1 <- run_audit(src, sb, quiet = FALSE)
  file.remove(calp)                                                        # 달력 판독 실패 → 날짜도 없다 → 그대로 이월
  r2 <- run_audit(src, sb, quiet = FALSE)
  file.copy(calb, calp, overwrite = TRUE)                                  # 원복 → 같은 구멍 → '새 경보' 재발송 없어야
  r3 <- run_audit(src, sb, quiet = FALSE)
  .rw(sb, ".cache/trading_calendar.parquet", function(d) d[, list(Date)]); restore_books(sb)   # 미측정 중 실제로 메워짐
  r4 <- run_audit(src, sb, quiet = FALSE)
  k1 <- .carry(r1); k2 <- .carry(r2)
  .lv(U0_new = .f6n(r0) == 1L && nzchar(s0) && grepl("consensus.dps_1y:HOLE@", s0, fixed = TRUE),
      U1_unmeasured_status = identical(r1$fa$status, "UNMEASURED_HOLES") && identical(r1$fa$carried, "4"),
      U1_no_false_resolved = .f6n(r1) == 0L && identical(.st_sig(r1), s0) && identical(r1$js$output_audit$signature, s0),
      U1_remeasured_kept = length(k1) == 4L && all(vapply(k1, function(z) identical(z$status, "kept_outside") &&
                                                            identical(z$reason, "window_unknown"), logical(1))),
      U2_calendar_absent_carried = .f6n(r2) == 0L && identical(.st_sig(r2), s0) && identical(r2$js$output_audit$signature, s0) &&
        length(k2) == 4L && all(vapply(k2, function(z) identical(z$status, "carried") && identical(z$reason, "calendar_unreadable"), logical(1))),
      U3_restored_no_resend = .f6n(r3) == 0L && identical(r3$fa$status, "OK") && identical(r3$js$output_audit$signature, s0),
      U4_filled_while_unmeasured_resolved = .f6n(r4) == 1L && startsWith(.f6m(r4)$msg, "✅") && identical(.st_sig(r4), "") &&
        identical(r4$fa$status, "UNMEASURED_HOLES") &&
        all(vapply(.carry(r4), function(z) identical(z$status, "resolved_outside"), logical(1))))
}
chk_all(u_seq(AUDIT))

## W — OHLCVS base 재수출로 창 시작 E 가 뒤로 간다(검증 지적 1 후단). 직전 통지 = dps_1y 내부 0행(CAL[N-20]) + 개인 꼬리 0행(CAL[N-8]~).
w_seq <- function(src) {
  sb <- new_sb(); cons_mod(sb, "dps_1y", CAL[N - 20L]); inv_mod(sb, "Individual", CAL[(N - 8L):N])
  r0 <- run_audit(src, sb, quiet = FALSE); s0 <- .st_sig(r0)
  .relabel(sb, CAL[N - 12L])            # E = CAL[N-11] — dps 구멍은 창 밖 · 개인 구멍은 창 안
  r1 <- run_audit(src, sb, quiet = FALSE)
  .relabel(sb, CAL[N - 5L])             # E = CAL[N-4] — 개인 구멍(CAL[N-8]~)이 창 시작을 가로지른다
  r2 <- run_audit(src, sb, quiet = FALSE)
  .wp(as.data.table(arrow::read_parquet(file.path(TEMPLATE, ".cache/consensus/dps_1y.parquet"), mmap = FALSE)),
      file.path(sb, ".cache/consensus/dps_1y.parquet"))       # 창 밖 dps 구멍이 실제로 메워짐
  r3 <- run_audit(src, sb, quiet = FALSE)
  restore_books(sb)                                          # 개인도 메워짐
  r4 <- run_audit(src, sb, quiet = FALSE)
  dtok <- paste0("consensus.dps_1y:HOLE@", CAL[N - 20L]); itok <- paste0("investor_act.Individual:HOLE@", CAL[N - 8L])
  h2 <- it(r2, "investor_act.Individual")$holes
  .lv(W0_new = .f6n(r0) == 1L && grepl(dtok, s0, fixed = TRUE) && grepl(itok, s0, fixed = TRUE),
      W1_window_moved = identical(r1$js$output_audit$meta$window_from, as.character(CAL[N - 11L])) &&
        identical(r2$js$output_audit$meta$window_from, as.character(CAL[N - 4L])),
      W1_outside_kept_silent = .f6n(r1) == 0L && identical(.st_sig(r1), s0) && identical(r1$js$output_audit$signature, s0) &&
        .carry_has(r1, dtok, "kept_outside"),
      W2_straddle_silent = .f6n(r2) == 0L && identical(r2$js$output_audit$signature, s0) && .carry_has(r2, itok, "kept_outside") &&
        length(h2) >= 1L && isTRUE(h2[[1]]$cont) && identical(h2[[1]]$from, as.character(CAL[N - 4L])),
      W3_outside_filled_changed = .f6n(r3) == 1L && grepl("변경", .f6m(r3)$msg, fixed = TRUE) && .carry_has(r3, dtok, "resolved_outside") &&
        !grepl(dtok, .st_sig(r3), fixed = TRUE) && grepl(itok, .st_sig(r3), fixed = TRUE),
      W4_all_filled_resolved = .f6n(r4) == 1L && startsWith(.f6m(r4)$msg, "✅") && identical(.st_sig(r4), ""))
}
chk_all(w_seq(AUDIT))

## R — 같은 서명이 이어지는 동안 구멍 기록(runs)의 끝을 고쳐 적는다. 어제 커밋한 끝(CAL[N-1])만 믿으면, 창이 사라진 뒤
##   앞부분만 메워지고 오늘 날(CAL[N])이 0행으로 남아도 '해소'로 오판한다.
r_seq <- function(src) {
  sb <- new_sb(); inv_mod(sb, "Individual", CAL[(N - 3L):N])
  td <- .day_save(sb); .day_back(sb)
  ra <- run_audit(src, sb, quiet = FALSE, today = CAL[N])       # 어제 — 구간 CAL[N-3]~CAL[N-1] 로 커밋
  .day_fwd(sb, td)
  rb <- run_audit(src, sb, quiet = FALSE)                       # 오늘 — 같은 서명(무음) · 구간 끝만 CAL[N] 으로 늘었다
  tok <- paste0("investor_act.Individual:HOLE@", CAL[N - 3L])
  ru_a <- .st_runs(ra); ru_b <- .st_runs(rb)
  restore_books(sb); inv_mod(sb, "Individual", CAL[N])            # 앞 사흘은 메워지고 CAL[N] 만 0행
  .relabel(sb, max(CAL))                                         # 전 구간 base(재수출) → E = NA · 창 없음 → 직전 구멍은 창 밖 재측정
  rc <- run_audit(src, sb, quiet = FALSE)
  .lv(R0_new = .f6n(ra) == 1L && grepl(tok, .st_sig(ra), fixed = TRUE) && identical(.run_to(ru_a, tok), as.character(CAL[N - 1L])),
      R1_repeat_silent = .f6n(rb) == 0L && identical(.st_sig(rb), .st_sig(ra)),
      R1_runs_refreshed = identical(.run_to(ru_b, tok), as.character(AS_OF)),
      R2_tail_zero_kept = identical(rc$fa$status, "UNMEASURED_HOLES") && .f6n(rc) == 0L && identical(.st_sig(rc), .st_sig(ra)) &&
        .carry_has(rc, tok, "kept_outside"))
}
chk_all(r_seq(AUDIT))

## D — 하루 경과(검증 지적 2): 서명이 하루가 지나도 변하지 않아야 한다(STALE lag · 구멍 끝은 날마다 움직이는 값)
##   ① 책 전체 정체(컨센서스 12 · CAL[N-15] 에서 멈춤 + 내부 0행 1일) — STALE lag 만 +1
##   ② 다른 출력은 전진 · 한 출력만 정체(coverage 꼬리 0행) — 구멍 끝은 늘고 시작은 고정
d_seq <- function(src, which) {
  sb <- new_sb()
  if (which == 1L) {
    for (m in CONS) .rw(sb, sprintf(".cache/consensus/%s.parquet", m), function(d) d[Date <= CAL[N - 15L]])
    cons_mod(sb, "dps_1y", CAL[N - 30L])
  } else {
    cons_mod(sb, "coverage", CAL[(N - 3L):N])
  }
  td <- .day_save(sb); .day_back(sb)
  ra <- run_audit(src, sb, quiet = FALSE, today = CAL[N])
  .day_fwd(sb, td)
  rb <- run_audit(src, sb, quiet = FALSE)
  k <- if (which == 1L) "consensus.eps_1y" else "consensus.coverage"
  ha <- it(ra, k)$holes; hb <- it(rb, k)$holes
  v <- .lv(first_new = .f6n(ra) == 1L,
           asof_moved = identical(ra$js$as_of, as.character(CAL[N - 1L])) && identical(rb$js$as_of, as.character(AS_OF)),
           exercised = if (which == 1L) identical(it(rb, k)$status, "STALE") && isTRUE(it(rb, k)$lag_days > it(ra, k)$lag_days) &&
                         grepl("consensus.dps_1y:HOLE@", .st_sig(ra), fixed = TRUE)
                       else length(ha) == 1L && length(hb) == 1L && identical(ha[[1]]$from, hb[[1]]$from) &&
                         identical(ha[[1]]$to, as.character(CAL[N - 1L])) && identical(hb[[1]]$to, as.character(AS_OF)) &&
                         identical(it(rb, k)$status, "FRESH"),
           day_passed_silent = .f6n(rb) == 0L && identical(.st_sig(rb), .st_sig(ra)) && identical(rb$js$output_audit$signature, .st_sig(ra)))
  stats::setNames(v, sprintf("D%d_%s", which, names(v)))
}
chk_all(d_seq(AUDIT, 1L)); chk_all(d_seq(AUDIT, 2L))

## L — 글자 수 상한(검증 지적 5): 구간이 많은 출력이 여럿이면 본문이 4,096자를 넘는다 → 잘라 보내고(생략 표기) 커밋.
l_test <- function(src) {
  sb <- new_sb()
  zd <- CAL[seq(N - 62L, N - 2L, by = 3L)]          # 사흘에 하루 0행 → 지표마다 1일 구간 21개
  for (m in CONS) cons_mod(sb, m, zd)
  r <- run_audit(src, sb, quiet = FALSE)
  m1 <- .f6m(r)
  nh <- sum(vapply(r$js$output_audit$items[paste0("consensus.", CONS)], function(x) length(x$holes), integer(1)))
  .lv(L0_exercised = nh >= 12L * 20L,
      L1_sent_ok = .f6n(r) == 1L && isTRUE(m1$ok),
      L2_within_limit = isTRUE(m1$u16 <= 4096L),
      L3_omission_marked = isTRUE(grepl("생략", m1$msg, fixed = TRUE)),
      L4_head_tail_kept = isTRUE(startsWith(m1$msg, intToUtf8(0x1F573L))) && isTRUE(grepl("-FromOverride Consensus=", m1$msg, fixed = TRUE)) &&
        isTRUE(grepl("output_audit", m1$msg, fixed = TRUE)),
      L5_committed = identical(.st_sig(r), r$js$output_audit$signature))
}
chk_all(l_test(AUDIT))

## V11 — 견고성(검증 지적 3): 보고 출력 · JSON 조립 · 직렬화 실패가 EDC_RESULT · 판정 JSON · FA 줄 · stale 경보 경로를 끊지 않는다.
##   주입은 감사기 사본의 함수 첫머리 치환(정확히 1회 · 성사 단정). ser = 직렬화 불가 객체(환경)를 output_audit 에 싣는다.
V11_INJ <- list(line = c(".fa_line <- function(x) {", ".fa_line <- function(x) { stop(\"injected .fa_line failure\");"),
                json = c(".fa_json <- function(res) {", ".fa_json <- function(res) { stop(\"injected .fa_json failure\");"),
                ser  = c(".fa_json <- function(res) {", ".fa_json <- function(res) { res$unserializable <- new.env();"))
v11_test <- function(path, nm) {
  sb <- new_sb(); sc$V1$mod(sb); panel_stale(sb, ".cache/benchmark.parquet", CAL[N - 5L])
  r <- run_audit(path, sb)
  oa <- r$js$output_audit
  .lv(no_abort = !r$err && any(grepl("QVEST_FRESHNESS_QUIET=1", r$out, fixed = TRUE)),
      edc_intact = identical(r$edc$stale, "1") && identical(r$edc$items, "benchmark"),
      json_judgment_intact = length(r$js$stale_items) == 1L && startsWith(unlist(r$js$stale_items), "benchmark(STALE") &&
        identical(unlist(r$js$downstream_items), "p3_forecast"),
      fa_line = !is.null(r$fa) && identical(r$fa$status, if (nm == "line") "OK" else "ERROR"),
      oa_marked = if (nm == "line") identical(oa$status, "OK") && any(grepl("[output-audit] 보고 출력 실패", r$out, fixed = TRUE))
                  else identical(oa$status, "ERROR") && grepl(if (nm == "json") "json_build" else "json_write", oa$error %||% "", fixed = TRUE))
}
for (nm in names(V11_INJ)) {
  v <- .var(V11_INJ[[nm]][1], V11_INJ[[nm]][2])
  chk(sprintf("V11_%s_variant_applied", nm), v$applied)
  if (v$applied) chk_all(v11_test(v$path, nm), sprintf("V11_%s_", nm))
}

## ── S 정적 ────────────────────────────────────────────────────────────────────
cat("-- S 정적 --\n")
## S1 텔레그램 리터럴 균질 — 한 문자열 리터럴에 \u·\U 이스케이프와 원시 비ASCII 를 섞지 않는다(C 로케일 이중 인코딩)
.mixed_literals <- function(code) {
  pd <- utils::getParseData(parse(text = code, keep.source = TRUE))
  s <- pd$text[pd$token == "STR_CONST"]
  esc <- grepl("(?<!\\\\)(?:\\\\\\\\)*\\\\[uU]", s, perl = TRUE)
  raw <- vapply(s, function(x) any(utf8ToInt(enc2utf8(x)) > 127L), logical(1))
  s[esc & raw]
}
chk("S1_literal_homogeneity", length(.mixed_literals(SRC)) == 0L, paste(utils::head(.mixed_literals(SRC), 3L), collapse = " | "))
chk("S1p_scanner_positive_control", length(.mixed_literals('a <- "\\u00b7 ·"\nb <- "· only"\nc <- "\\u00b7 only"')) == 1L)
## S2 기존 계약 닻 — 다른 시험이 이 파일에서 찾는 문자열(설치 뒤에도 초록이어야 한다)
chk("S2_ingest_autoextend_anchors", all(vapply(c("rawdata", "consensus", "investor_act", "universe_support", "fred_wide"),
      function(n) grepl(sprintf('check_freshness("%s"', n), SRC, fixed = TRUE), logical(1))))
chk("S2_dr_freshness_gate_anchors", grepl('audits\\$p3_forecast\\$role\\s*<-\\s*"downstream"', SRC, perl = TRUE) &&
      grepl("downstream_items = ", SRC, fixed = TRUE) && grepl('"EDC_RESULT stale=%d as_of=%s items=%s\\n"', SRC, fixed = TRUE))
chk("S2_msm_asof_preserved", grepl('".cache/msm_asof_daily.parquet"', SRC, fixed = TRUE) && !grepl("audits$msm_hybrid", SRC, fixed = TRUE))
## S3 이식성 금칙(r-portability) — 주석 밖 줄만
.code_lines <- function(txt) { l <- strsplit(txt, "\n", fixed = TRUE)[[1]]; l[!grepl("^\\s*#", l)] }
.cl <- .code_lines(SRC)
.slash_tmp <- paste0('"', "/", "tmp/"); .slash_mnt <- paste0('"', "/", "mnt/")
chk("S3_portability", !any(grepl("^on\\.exit\\(", .cl)) && !any(grepl(.slash_tmp, .cl, fixed = TRUE)) &&
      !any(grepl(.slash_mnt, .cl, fixed = TRUE)) && !any(grepl("\\bsystem2?\\(", .cl, perl = TRUE)) &&
      !any(grepl('Sys.getenv("CLAUDE_PROJECT_DIR"', .cl, fixed = TRUE)) && !any(grepl("regmatches(", .cl, fixed = TRUE)))
.self_txt <- tryCatch(paste(readLines(file.path(ROOT, "08_Tests/data/test_freshness_audit_outputs.R"), encoding = "UTF-8", warn = FALSE),
                      collapse = "\n"), error = function(e) "")
chk("S3_self_no_toplevel_onexit", nzchar(.self_txt) && !any(grepl("^on\\.exit\\(", .code_lines(.self_txt))))
## S4 출력 목록 ↔ 파서 정의(정적 파싱 — 파서를 source 하지 않는다: config.R · 패키지 부작용 없음).
##   파스 데이터에서 '<이름> <- 값' 대입 식을 찾아 값 식만 평가한다(첫 대입 · 함수 안 대입도 찾는다 — sheet_map).
.assign_value <- function(src, name, is_text = FALSE) {
  ex <- if (is_text) parse(text = src, keep.source = TRUE) else parse(src, keep.source = TRUE, encoding = "UTF-8")
  pd <- utils::getParseData(ex)
  for (j in which(pd$token == "SYMBOL" & pd$text == name)) {
    lhs <- pd$parent[j]; asg <- pd$parent[pd$id == lhs]
    kids <- pd[pd$parent == asg, , drop = FALSE]; kids <- kids[order(kids$line1, kids$col1), , drop = FALSE]
    if (nrow(kids) >= 3L && identical(kids$id[1], lhs) && identical(kids$token[2], "LEFT_ASSIGN"))
      return(eval(parse(text = utils::getParseText(pd, asg), keep.source = FALSE)[[1]][[3]], envir = new.env()))
  }
  NULL
}
.books <- .assign_value(SRC, ".FA_BOOKS", is_text = TRUE)
.bk <- function(p) Filter(function(b) identical(b$panel, p), .books)[[1]]
.pf <- function(rel) file.path(ROOT, rel)
cm <- tryCatch(.assign_value(.pf("02_Infrastructure/data/consensus_parser.R"), "CONSENSUS_METRICS"), error = function(e) NULL)
um <- tryCatch(.assign_value(.pf("02_Infrastructure/data/parse_universe_support.R"), "UNIVERSE_SUPPORT_SHEET_META"), error = function(e) NULL)
sm <- tryCatch(.assign_value(.pf("02_Infrastructure/data/incremental_update_file.R"), "sheet_map"), error = function(e) NULL)
chk("S4_consensus_list", !is.null(cm) && setequal(unname(cm), .bk("consensus")$outputs) && length(cm) == 12L)
chk("S4_universe_list", !is.null(um) && setequal(vapply(um, `[[`, "", "cache_name"), .bk("universe_support")$outputs) && length(um) == 8L)
chk("S4_investor_types", !is.null(sm) && setequal(unlist(sm, use.names = FALSE), .bk("investor_act")$outputs) && length(sm) == 4L)
.inc_txt <- paste(readLines(file.path(ROOT, "02_Infrastructure/data/incremental_update_file.R"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
chk("S4_derived_names", grepl('sprintf("investor_%s.parquet", tolower(itype))', .inc_txt, fixed = TRUE) &&
      grepl('"investor_wide.parquet"', .inc_txt, fixed = TRUE) && identical(.bk("investor_act")$derived_fmt, "investor_%s.parquet"))
.ps1 <- paste(readLines(file.path(ROOT, "02_Infrastructure/ops/qw_refresh.ps1"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
chk("S4_repair_hint_matches_driver", grepl("[string[]]$FromOverride", .ps1, fixed = TRUE) &&
      all(vapply(.books, function(b) grepl(sprintf('name="%s"', b$book), .ps1, fixed = TRUE), logical(1))))

## ── M 돌연변이 — 소스 텍스트 치환(성사 단정) → 대상 시나리오가 빨개져야 검출 ─────────────
cat("-- M 돌연변이 --\n")
.mut <- function(id, old, new, runner) {
  v <- .var(old, new)
  chk(sprintf("%s_applied", id), v$applied, "치환 대상 문자열이 감사기에 정확히 1회 있지 않다 — 돌연변이 갱신 필요")
  if (!v$applied) return(invisible(NULL))
  res <- tryCatch(runner(v$path), error = function(e) e)
  if (inherits(res, "error")) {   # 실행기 오류는 '검출'로 세지 않는다(못 쟀다 ≠ 잡았다)
    chk(sprintf("%s_detected", id), FALSE, paste("runner error:", conditionMessage(res))); return(invisible(NULL))
  }
  chk(sprintf("%s_detected", id), !all(res), "돌연변이가 통과했다 — 시험이 이 결함을 못 본다")
  if (!all(res)) cat(sprintf("    -> red: %s\n", paste(names(res)[!res], collapse = ",")))   # 어느 단언이 잡았나(보고 · 회귀 추적)
}
.sc_run <- function(name) function(p) sc[[name]]$test(run_sc(p, name)$r)
.mut("M0_f6_removed", ".fa_res <- tryCatch(.fa_output_audit(as_of, audits, .fa_st),", ".fa_res <- tryCatch(stop(\"F6 disabled (mutant)\"),", .sc_run("V1"))
.mut("M1_tau_zero", ".FA_FILL_MIN <- 0.5", ".FA_FILL_MIN <- 0", .sc_run("V2"))
.mut("M2_zero_rule_removed", "bad <- n == 0L | (!is.na(ratio) & ratio < tau)", "bad <- (!is.na(ratio) & ratio < tau)", .sc_run("V10"))
## M3 — 행이 없는 날을 '평소'로 메운다(있는 날만 보는 구판 사고) → V1 의 최신일 0행이 안 보여야 한다
.mut("M3_absent_day_imputed", "n <- as.integer(cnt$N[match(exp_dates, cnt$Date)]); n[is.na(n)] <- 0L",
     "n <- as.integer(cnt$N[match(exp_dates, cnt$Date)]); n[is.na(n)] <- as.integer(stats::median(n, na.rm = TRUE))", .sc_run("V1"))
## M3b — 기대일에서 달력을 뺀다(책에 실제로 있는 날의 합집합만) → 책 전체가 빠진 날(V10 · 실측 03-30~04-29 계통)이 안 보여야 한다
.mut("M3b_calendar_dropped", "ex <- .fa_expected(bk$kind, cal_dates, E, hz, unique(allD))",
     "ex <- sort(unique(allD[allD >= E]))", .sc_run("V10"))
.mut("M4_report_only_leak", "downstream_items <- unname(unlist(lapply(audits,",
     "stale_items <- c(stale_items, .fa_res$warn_items); downstream_items <- unname(unlist(lapply(audits,", .sc_run("V1"))
.mut("M5_signature_gate_removed", 'if (kind %in% c("ok", "repeat")) {', 'if (kind %in% c("ok")) {', t_seq)
.mut("M6_commit_before_ok", "if (is.list(r) && isTRUE(r$ok)) {", "if (TRUE) {", t_seq)
.mut("M7_derived_ref_horizon", "items[[nm(g)]]$last_date %||% NA_character_", "as.character(hz)", .sc_run("V2"))
## 2차 수리 축 — 측정 불가 이월 · 재측정 · 이어짐 · 구멍 기록 갱신 · 서명 안정 · 목록 밖 유형 · 상한 · 견고성
.mut("M8_carry_dropped", "if (is.data.frame(x$holes_kept) && nrow(x$holes_kept)) t <- c(t, x$holes_kept$token)",
     "if (FALSE) t <- c(t, x$holes_kept$token)", u_seq)
.mut("M9_remeasure_disabled", "else if (isTRUE(r$norec)) {", "else if (TRUE) {", w_seq)
.mut("M10_continuation_dropped", "if (any(cj)) { h$cont <- cj; x$holes <- h }", "if (FALSE) { h$cont <- cj; x$holes <- h }", w_seq)
.mut("M11_runs_refresh_dropped", "if (!identical(.fa_runs_key(st$runs), .fa_runs_key(res$runs))) {", "if (FALSE) {", r_seq)
.mut("M12_stale_token_lag", 'if (!x$status %in% c("FRESH", "SYNCED")) t <- c(t, paste0(x$name, ":", x$status))',
     'if (!x$status %in% c("FRESH", "SYNCED")) t <- c(t, paste0(x$name, ":", x$status, "/lag", x$lag_days))', function(p) d_seq(p, 1L))
.mut("M13_hole_token_end", 'if (is.data.frame(h) && nrow(h)) t <- c(t, paste0(x$name, ":HOLE@", h$from))',
     'if (is.data.frame(h) && nrow(h)) t <- c(t, paste0(x$name, ":HOLE@", h$to))', function(p) d_seq(p, 2L))
.mut("M14_unlisted_type_holes", "ev <- if (length(ex) && !unl) .fa_eval(ex, cn, W) else NULL",
     "ev <- if (length(ex)) .fa_eval(ex, cn, W) else NULL", .sc_run("V7"))
.mut("M15_tg_cap_off", ".FA_TG_MAX <- 4096L", ".FA_TG_MAX <- 1000000L", l_test)
## 견고성 돌연변이 = 보호를 벗긴 사본 + 같은 실패 주입(둘 다 정확히 1회 치환 성사 단정)
.mut2 <- function(id, old, new, inj, runner) {
  v <- .var(old, new)
  chk(sprintf("%s_applied", id), v$applied, "치환 대상 문자열이 감사기에 정확히 1회 있지 않다 — 돌연변이 갱신 필요")
  if (!v$applied) return(invisible(NULL))
  s2 <- .subst(paste(readLines(v$path, encoding = "UTF-8", warn = FALSE), collapse = "\n"), inj[1], inj[2])
  chk(sprintf("%s_inject_applied", id), s2$applied)
  if (!s2$applied) return(invisible(NULL))
  p2 <- paste0(v$path, ".inj.R"); writeLines(s2$text, p2, useBytes = TRUE)
  res <- tryCatch(runner(p2), error = function(e) e)
  if (inherits(res, "error")) {
    chk(sprintf("%s_detected", id), FALSE, paste("runner error:", conditionMessage(res))); return(invisible(NULL))
  }
  chk(sprintf("%s_detected", id), !all(res), "돌연변이가 통과했다 — 시험이 이 결함을 못 본다")
  if (!all(res)) cat(sprintf("    -> red: %s\n", paste(names(res)[!res], collapse = ",")))
}
.mut2("M16_print_unguarded", "tryCatch(.fa_print(.fa_res), error = function(e)", ".fa_print(.fa_res); tryCatch(NULL, error = function(e)",
      V11_INJ$line, function(p) v11_test(p, "line"))
.mut2("M17_json_build_unguarded", ".fa_oa <- tryCatch(.fa_json(.fa_res), error = function(e) e)", ".fa_oa <- .fa_json(.fa_res)",
      V11_INJ$json, function(p) v11_test(p, "json"))
.mut2("M18_json_write_unguarded", ".fa_wr <- tryCatch(.fa_write(.fa_oa), error = function(e) e)", ".fa_wr <- .fa_write(.fa_oa)",
      V11_INJ$ser, function(p) v11_test(p, "ser"))

## ── 정리 · 요약 ────────────────────────────────────────────────────────────────
for (k in names(.OLD_ENV)) if (is.na(.OLD_ENV[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, stats::setNames(list(.OLD_ENV[[k]]), k))
Sys.unsetenv(c("FA_TEST_TG_LOG", "FA_TEST_TG_OK"))
unlink(.TMP, recursive = TRUE, force = TRUE)
if (PASS + FAIL == 0L) { cat("  FAIL no_checks_ran — 검사가 하나도 돌지 않았다(0/0 을 통과로 읽지 않는다)\n"); FAIL <- 1L }
cat(sprintf("  ── %d/%d pass\n", PASS, PASS + FAIL))
.emit(PASS, FAIL)
quit(status = if (FAIL == 0L) 0L else 1L)
