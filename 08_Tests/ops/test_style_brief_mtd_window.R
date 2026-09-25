#!/usr/bin/env Rscript
#==============================================================================
# test_style_brief_mtd_window.R — 스타일 국면 브리핑: 12개월 창 = 완결 11개월 + 진행월 MTD (2026-09-24 도훈 지시
#   "스타일 국면 브리핑 26년 8월 기준으로 고정된 부분 수정해줘")
#
# 결함: 브리핑 제목·'최근 12개월 평균'·국면 판독·부활 워치·차트가 월간 파일 마지막 완결월에 묶여
#   9월 한 달 내내 '2026-08 기준' 같은 값이 나갔다.
# 대상 = 운영 코드 그 자체: 02_Infrastructure/reports/style_brief_lib.R (sw_window12 · sw_mtd_state ·
#   sw_brief_title · sw_compose_brief) + ops/morning_steps/ff5_brief_send.R 배선(드라이런 서브프로세스) +
#   트래커 완결월 발행 가드(ff5_kr_tracker.R §1 · smartbeta_kr_tracker.R §3 — 파스 트리에서 꺼내 합성 입력으로 실행).
# 양성 대조:
#   P1 FF5 합성 14개월 + MTD → 창 = (2025-10..2026-08 합 + MTD)/12 수기값(5팩터) · 월 목록
#   P2 스마트베타 7스타일 — 같은 함수 · 수기값        P3 MTD 부재 → 완결 12개월 수기값 + '진행월 MTD 없음'
#   P4 낡은 MTD(as_of 가 완결월 안·월말) → stale 폴백   P5 불연속·라벨 불일치·장중·미래 → 폴백 / 16시 후 → 채택
#   P6 제목 '(2026-09-23 기준 · 완결월 2026-08)' / 폴백 '(완결월 2026-08 기준 · 진행월 MTD 없음)'
#   P7 조립: 'FF5 최근 완결월 (2026-08)' · 12개월 절 라벨 · kv = 창 값(fmt +1.23% 규약) · 국면 판독 FF5/스타일 줄 ·
#      부활 워치(완결 12개월은 음, 창은 양 → 발화) · regime_line · 폴백 조립 · bullet ≤80자·MTD ≤1회(최악 입력)
#   P8 렌더: tg_agent_brief(dry_run=TRUE) 통과 3종(정상·폴백·최악) — 발송 없음
#   P9 드라이런 서브프로세스(FF5_BRIEF_DRYRUN=1 · 빌드 생략 · 샌드박스 데이터) → 제목 기록 · 텔레그램 미적재 · 'sent' 없음
#   P10 트래커 완결월 가드: FF5 rets · SB sig_dates — 진행월(부분월) 행 제외 · 표시층은 월간 기록 뒤에만 · 표시층 쓰기 0
#   R1 (읽기 전용 불변식) 운영 월간 파일 max(ym) < RAWDATA 최신월(진행월) — 부분월 발행 부재
# 위반 주입(사본 돌연변이 → 같은 판정이 red 여야 한다):
#   M1 창 → 완결 12개월(MTD 무시)   M2 제목 → 완결월 기준   M3 분모 12 → 11   M4 낡은 MTD 판정 제거
#   M5 FF5 트래커 가드 제거(부분월 월간 기록)   M6 SB 트래커 가드 '<' → '<='(부분월 발행)
# 실행: Rscript 08_Tests/ops/test_style_brief_mtd_window.R  (STYLE_BRIEF_CODE_ROOT=<스테이징> 로 배포 전 검증 가능)
#==============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
CODE <- Sys.getenv("STYLE_BRIEF_CODE_ROOT", ROOT)
LIB  <- file.path(CODE, "02_Infrastructure/reports/style_brief_lib.R")
SEND <- file.path(CODE, "02_Infrastructure/ops/morning_steps/ff5_brief_send.R")
TRK5 <- file.path(CODE, "02_Infrastructure/reports/ff5_kr_tracker.R")
TRKS <- file.path(CODE, "02_Infrastructure/reports/smartbeta_kr_tracker.R")
Sys.setenv(QVEST_TG_DRY_RUN = "1")   # 검사 중 텔레그램 실제 발송 금지 (배터리 기본값과 동일 — 단독 실행 대비)
PASS <- 0L; FAIL <- 0L; SKIPS <- list()
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
sk <- function(axis, reason, missing) { SKIPS[[length(SKIPS) + 1L]] <<- list(axis = axis, reason = reason, missing = missing)
  cat("  SKIP", axis, "—", reason, "\n") }
chk <- function(label, why) if (!nzchar(why)) ok(label) else ng(label, why)
finish <- function() {
  cat(sprintf("\n합계: 통과 %d · 실패 %d · 건너뜀 %d\n", PASS, FAIL, length(SKIPS)))
  cat(as.character(jsonlite::toJSON(list(test = "style_brief_mtd_window", pass = PASS, fail = FAIL, total = PASS + FAIL,
                                         skipped = length(SKIPS), skips = SKIPS), auto_unbox = TRUE)), "\n", sep = "")
  quit(status = if (FAIL == 0L) 0L else 1L)
}
for (p in c(LIB, SEND, TRK5, TRKS)) if (!file.exists(p)) { ng("대상 파일 부재", p); finish() }

read_txt <- function(path) paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
## 사본 돌연변이: from 이 정확히 1회 있어야 한다(없으면 '돌연변이 미적용' = 검사 자체 실패로 센다 — 조용히 통과 금지)
mutate <- function(path, from, to) {
  s <- read_txt(path)
  n <- lengths(regmatches(s, gregexpr(from, s, fixed = TRUE)))
  if (n != 1L) return(list(ok = FALSE, why = sprintf("돌연변이 표적 %d회(1회여야) — 원문이 바뀌었으면 표적 갱신", n)))
  f <- tempfile(fileext = ".R"); writeLines(enc2utf8(sub(from, to, s, fixed = TRUE)), f, useBytes = TRUE)
  list(ok = TRUE, file = f)
}
lib_env <- function(file) { E <- new.env(parent = globalenv()); eval(parse(file = file, encoding = "UTF-8", keep.source = FALSE), envir = E); E }
f2 <- function(v) sprintf("%+.2f%%", v * 100)    # 월평균 % 표기 규약(도훈 07-18) — 수기 기대 문자열
ym_seq <- function(start, n) format(seq(as.Date(paste0(start, "-01")), by = "1 month", length.out = n), "%Y-%m")

## ── 합성 입력 (월간 14개월 2025-07..2026-08 + 진행월 2026-09 MTD ~09-23, 17거래일) ──────────────
YM14 <- ym_seq("2025-07", 14L); i <- 1:14
FFS <- data.frame(ym = YM14, MKT = i / 1000, SMB = -i / 1000, HML = (i %% 3 - 1) / 100, RMW = rep(0.01, 14), CMA = i^2 / 1e4)
MTD5 <- list(as_of = "2026-09-23", ym = "2026-09", n_days = 17L, rf_mtd = 0.002,
             MKT = 0.05, SMB = 0.12, HML = 0.03, RMW = 0.04, CMA = 0.001)
NOW <- as.POSIXct("2026-09-24 07:30:00", tz = "Asia/Seoul")
## 수기 기대값 — 함수와 독립된 산술: i = 4..14(2025-10..2026-08) 11개월 합 + MTD, 나누기 12
EXP5 <- c(MKT = (sum((4:14) / 1000) + 0.05) / 12, SMB = (-sum((4:14) / 1000) + 0.12) / 12,
          HML = (sum(((4:14) %% 3 - 1) / 100) + 0.03) / 12, RMW = (11 * 0.01 + 0.04) / 12,
          CMA = (sum((4:14)^2 / 1e4) + 0.001) / 12)
## 완결 12개월(i = 3..14, 2025-09..2026-08) — 폴백 기대값. SMB 는 음(부활 미발화), 창(EXP5)은 양(발화)
EXP5C <- c(MKT = sum((3:14) / 1000) / 12, SMB = -sum((3:14) / 1000) / 12, HML = sum(((3:14) %% 3 - 1) / 100) / 12,
           RMW = 0.01, CMA = sum((3:14)^2 / 1e4) / 12)
STY <- c("VAL", "QUAL", "MOM", "LOWVOL", "SIZE", "DIV", "EREV")
SBS <- data.frame(ym = YM14, BENCH = 0.01, VAL = i / 100, QUAL = -i / 100, MOM = rep(0.005, 14), LOWVOL = (i - 7) / 1000,
                  SIZE = rep(-0.02, 14), DIV = c(1, -2, 3, -4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14) / 500, EREV = i * 0.003)
SBM <- list(as_of = "2026-09-23", sig = "2026-08-31", n_days = 17L, BENCH = 0.04,
            VAL = 0.03, QUAL = 0.2, MOM = -0.05, LOWVOL = 0.01, SIZE = -0.03, DIV = 0.02, EREV = -0.1)
EXPS <- c(VAL = (sum((4:14) / 100) + 0.03) / 12, QUAL = (-sum((4:14) / 100) + 0.2) / 12, MOM = (11 * 0.005 - 0.05) / 12,
          LOWVOL = (sum((4:14 - 7) / 1000) + 0.01) / 12, SIZE = (11 * -0.02 - 0.03) / 12,
          DIV = (sum(c(-4, 5, -6, 7, -8, 9, -10, 11, -12, 13, -14) / 500) + 0.02) / 12, EREV = (sum((4:14) * 0.003) - 0.1) / 12)
KO <- c(VAL = "가치포워드", QUAL = "퀄리티", MOM = "모멘텀", LOWVOL = "저변동성", SIZE = "소형주", DIV = "고배당", EREV = "이익전망수정")
T_OK <- "스타일 국면 브리핑 — FF5 + 스마트베타 (2026-09-23 기준 · 완결월 2026-08)"
T_FB <- "스타일 국면 브리핑 — FF5 + 스마트베타 (완결월 2026-08 기준 · 진행월 MTD 없음)"
same <- function(a, b) isTRUE(all.equal(unname(as.numeric(a)), unname(as.numeric(b)), tolerance = 1e-12))

## ── 판정 함수 (양성 대조와 돌연변이가 같은 함수를 쓴다) ─────────────────────────
c_window_ff <- function(E) {
  w <- E$sw_window12(FFS, E$.SW_FF5, MTD5, NOW)
  if (!identical(w$mode, "mtd")) return(sprintf("mode=%s(%s) — 진행월 MTD 가 창에 안 들어갔다", w$mode, w$state$reason))
  if (!same(w$values[names(EXP5)], EXP5)) return(sprintf("창 값 불일치: %s vs 수기 %s", paste(signif(w$values, 6), collapse = ","),
                                                      paste(signif(EXP5, 6), collapse = ",")))
  if (!identical(w$months, c(YM14[4:14], "2026-09(MTD)"))) return(paste("월 목록:", paste(w$months, collapse = ",")))
  if (!identical(w$label, "최근 12개월(진행월 MTD 17거래일 포함, ~09-23)")) return(paste("라벨:", w$label))
  ""
}
c_window_sb <- function(E) {
  w <- E$sw_window12(SBS, STY, SBM, NOW)
  if (!identical(w$mode, "mtd")) return(sprintf("mode=%s(%s)", w$mode, w$state$reason))
  if (!same(w$values[STY], EXPS[STY])) return("스타일 창 값이 수기값과 다르다")
  ""
}
c_absent <- function(E) {
  w <- E$sw_window12(FFS, E$.SW_FF5, NULL, NOW)
  if (!identical(w$mode, "complete") || !identical(w$state$reason, "absent")) return(sprintf("mode=%s reason=%s", w$mode, w$state$reason))
  if (!same(w$values[names(EXP5C)], EXP5C)) return("완결 12개월 폴백 값이 수기값과 다르다")
  if (!identical(w$label, "최근 12개월(완결 2025-09~2026-08 · 진행월 MTD 없음)")) return(paste("라벨:", w$label))
  ""
}
c_stale <- function(E) {
  r <- vapply(c("2026-08-29", "2026-08-31", "2026-07-15"), function(a)
    E$sw_window12(FFS, E$.SW_FF5, modifyList(MTD5, list(as_of = a, ym = substr(a, 1, 7))), NOW)$state$reason, "")
  if (!all(r == "stale")) return(paste("낡은 MTD 판정:", paste(r, collapse = ",")))
  w <- E$sw_window12(FFS, E$.SW_FF5, modifyList(MTD5, list(as_of = "2026-08-31", ym = "2026-08")), NOW)
  if (!identical(w$mode, "complete") || !same(w$values[names(EXP5C)], EXP5C)) return("낡은 MTD 가 창에 섞였다")
  if (!grepl("진행월 MTD 낡음(as_of 2026-08-31)", w$label, fixed = TRUE)) return(paste("라벨:", w$label))
  ""
}
c_title <- function(E) {
  t1 <- E$sw_brief_title(E$sw_window12(FFS, E$.SW_FF5, MTD5, NOW))
  t2 <- E$sw_brief_title(E$sw_window12(FFS, E$.SW_FF5, NULL, NOW))
  t3 <- E$sw_compose_brief(FFS, SBS, MTD5, SBM, NULL, NOW)$title
  if (!identical(t1, T_OK)) return(paste("정상 제목:", t1))
  if (!identical(t3, T_OK)) return(paste("조립 제목:", t3))
  if (!identical(t2, T_FB)) return(paste("폴백 제목:", t2))
  ""
}
c_compose <- function(E) {
  o <- E$sw_compose_brief(FFS, SBS, MTD5, SBM, NULL, NOW)
  hs <- vapply(o$sections, function(s) s$heading, "")
  if (!identical(hs[1], "FF5 최근 완결월 (2026-08)")) return(paste("절1:", hs[1]))
  if (!identical(unlist(o$sections[[1]]$kv, use.names = FALSE), f2(unlist(FFS[14, E$.SW_FF5])))) return("완결월 절 값 ≠ 2026-08 행")
  if (!identical(hs[2], "FF5 최근 12개월(진행월 MTD 17거래일 포함, ~09-23) 평균")) return(paste("절2:", hs[2]))
  if (!identical(unlist(o$sections[[2]]$kv, use.names = FALSE), f2(EXP5))) return("FF5 12개월 절 값 ≠ 창 수기값")
  if (!identical(hs[3], "진행월 MTD (직전영업일 2026-09-23, 17거래일)")) return(paste("절3:", hs[3]))
  if (!identical(hs[4], "스마트베타 최근 12개월(진행월 MTD 17거래일 포함, ~09-23) 평균 초과수익")) return(paste("절4:", hs[4]))
  if (!identical(unlist(o$sections[[4]]$kv, use.names = FALSE), f2(EXPS[STY]))) return("스마트베타 절 값 ≠ 창 수기값")
  jd <- o$sections[[length(o$sections)]]$items
  e1 <- sprintf("FF5 12개월+MTD: 소형 주도(SMB %s)·가치 우위(HML %s)·퀄리티 강세(RMW %s)", f2(EXP5[["SMB"]]), f2(EXP5[["HML"]]), f2(EXP5[["RMW"]]))
  if (!identical(jd[1], e1)) return(paste("국면 판독 FF5 줄:", jd[1]))
  tp <- names(EXPS)[which.max(EXPS)]; bt <- names(EXPS)[which.min(EXPS)]
  e2 <- sprintf("스타일 12개월+MTD: 최강 %s %s · 최약 %s %s", KO[[tp]], f2(EXPS[[tp]]), KO[[bt]], f2(EXPS[[bt]]))
  if (!identical(jd[2], e2)) return(paste("국면 판독 스타일 줄:", jd[2]))
  if (!any(grepl("^부활 워치: <b>발화</b> — SMB·HML 12개월\\+MTD 동반 양전", jd))) return(paste("부활 워치:", jd[length(jd)]))
  if (!startsWith(o$regime_line, "소형 주도 / 가치 우위 / 퀄리티 강세")) return(paste("regime_line:", o$regime_line))
  if (!grepl("발화", o$revive_watch, fixed = TRUE)) return(paste("revive_watch:", o$revive_watch))
  ""
}
c_compose_fb <- function(E) {
  o <- E$sw_compose_brief(FFS, SBS, NULL, modifyList(SBM, list(as_of = "2026-08-31")), NULL, NOW)
  hs <- vapply(o$sections, function(s) s$heading, "")
  if (!identical(o$title, T_FB)) return(paste("폴백 제목:", o$title))
  if (any(startsWith(hs, "진행월 MTD"))) return("MTD 부재인데 '진행월 MTD' 절이 실렸다")
  if (!identical(unlist(o$sections[[2]]$kv, use.names = FALSE), f2(EXP5C))) return("폴백 12개월 값 ≠ 완결 12개월 수기값")
  if (!any(grepl("진행월 MTD 낡음(as_of 2026-08-31)", hs, fixed = TRUE))) return("스마트베타 낡은 MTD 사유 미표기")
  jd <- o$sections[[length(o$sections)]]$items
  if (!any(grepl("^부활 워치: 반전 신호 없음\\(SMB·HML 12개월\\(완결\\)", jd))) return(paste("폴백 부활 워치:", jd[length(jd)]))
  if (any(grepl("^진행월 MTD", jd))) return("낡은 스마트베타 MTD 가 진행월 줄로 실렸다")
  ""
}
## 최악 입력 — 두 자릿수 %·가장 긴 스타일명·부호반전 최다 조합 + 지수 민감도 → bullet ≤80자 · 비화이트리스트 약어(MTD) ≤1회
worst_inputs <- function() {
  FW <- data.frame(ym = YM14, MKT = -0.1234, SMB = -0.1234, HML = -0.1234, RMW = -0.1234, CMA = -0.1234)
  MW <- modifyList(MTD5, list(MKT = -0.1234, SMB = -0.1234, HML = -0.1234, RMW = -0.1234, CMA = -0.1234))
  SW <- data.frame(ym = YM14, BENCH = 0, VAL = -0.05, QUAL = 0.05, MOM = 0.05, LOWVOL = -0.05, SIZE = 0.05, DIV = 0.05, EREV = -0.1234)
  SMW <- modifyList(SBM, list(VAL = 0.5, QUAL = 0.01, MOM = 0.01, LOWVOL = 0.5, SIZE = 0.01, DIV = 0.01, EREV = 0.9999))
  bet <- list(MKT = 1.062, SMB = -0.026, HML = 0.209, RMW = -0.014, CMA = 0.268)
  sbb <- list(VAL = -1.23, QUAL = 0.5, MOM = 0.1, LOWVOL = 0.2, SIZE = -0.3, DIV = 0.4, EREV = 1.23)
  IB <- list(window = "36개월+MTD ~2026-09-23", betas = list(KOSPI200 = bet, KOSDAQ150 = bet, KOSPI = bet, KOSDAQ = bet),
             sb_betas = list(KOSPI200 = sbb, KOSDAQ150 = sbb, KOSPI = sbb, KOSDAQ = sbb))
  list(FW = FW, MW = MW, SW = SW, SMW = SMW, IB = IB)
}
c_bullets <- function(E) {
  W <- worst_inputs()
  outs <- list(E$sw_compose_brief(W$FW, W$SW, W$MW, W$SMW, W$IB, NOW), E$sw_compose_brief(W$FW, W$SW, NULL, NULL, W$IB, NOW))
  for (o in outs) for (s in o$sections) if (identical(s$type, "bullet")) {
    n <- nchar(s$items); if (any(n > 80L)) return(sprintf("bullet %d자 > 80: %s", max(n), s$items[which.max(n)]))
    m <- lengths(regmatches(s$items, gregexpr("MTD", s$items, fixed = TRUE)))
    if (any(m > 1L)) return(paste("MTD 2회 이상(약어 가드 stop):", s$items[which.max(m)]))
  }
  ""
}

## ── 운영 라이브러리 로드 ─────────────────────────────────────────────────
E0 <- tryCatch(lib_env(LIB), error = function(e) { ng("style_brief_lib.R 로드", conditionMessage(e)); NULL })
if (is.null(E0)) finish()
cat("=== 양성 대조 (운영 코드 · 합성 입력 · 수기 기대값) ===\n")
chk("P1 FF5 창 = (2025-10..2026-08 합 + 09 MTD)/12 · 월 목록 · 라벨", c_window_ff(E0))
chk("P2 스마트베타 7스타일 창 — 같은 함수 · 수기값", c_window_sb(E0))
chk("P3 MTD 부재 → 완결 12개월(2025-09..2026-08) 수기값 + '진행월 MTD 없음'", c_absent(E0))
chk("P4 낡은 MTD(as_of 08-29·08-31·07-15) → stale 폴백 + 사유 표기", c_stale(E0))
st <- function(m, last = "2026-08", now = NOW) E0$sw_mtd_state(m, last, now)$reason
kst <- function(s) as.POSIXct(s, tz = "Asia/Seoul")
r5 <- c(gap = st(MTD5, "2026-07"), inconsistent = st(modifyList(MTD5, list(ym = "2026-10"))),
        intraday = st(MTD5, now = kst("2026-09-23 10:00:00")), ok_after_close = st(MTD5, now = kst("2026-09-23 16:30:00")),
        future = st(MTD5, now = kst("2026-09-22 12:00:00")), absent1 = st(NULL), absent2 = st(list(as_of = NA)),
        absent3 = st(list(n_days = 3)))
e5 <- c("gap", "inconsistent", "intraday", "ok", "future", "absent", "absent", "absent")
chk("P5 불연속·라벨 불일치·장중(10시)·마감 후(16:30 채택)·미래·부재 판정", if (identical(unname(r5), e5)) "" else
    paste(names(r5), r5, sep = "=", collapse = " "))
chk("P6 제목 — MTD as_of 기준 · 완결월 병기 / 폴백은 완결월 + 사유", c_title(E0))
chk("P6b 월평균 % 표기 규약 유지(fmt: +1.23% · NA)", if (identical(E0$sw_fmt(0.012345), "+1.23%") && identical(E0$sw_fmt(NA), "NA") &&
    identical(E0$sw_fmt(-0.1), "-10.00%")) "" else "fmt 규약 변경")
chk("P7 조립 — 절 이름·12개월 라벨·kv=창 값·국면 판독 FF5/스타일·부활 워치 발화·regime_line", c_compose(E0))
chk("P7b 폴백 조립 — 제목·MTD 절 부재·완결 12개월 값·SB 낡음 사유·부활 워치(완결)", c_compose_fb(E0))
chk("P7c 최악 입력 bullet ≤80자 · MTD ≤1회(렌더 약어 가드)", c_bullets(E0))

cat("\n=== P8 렌더 — tg_agent_brief(dry_run=TRUE) · 발송 없음 ===\n")
tg_ok <- tryCatch({ suppressMessages(source(file.path(ROOT, "02_Infrastructure/telegram/telegram_notify.R"))); TRUE },
                  error = function(e) { sk("P8 렌더", conditionMessage(e), "02_Infrastructure/telegram/telegram_notify.R"); FALSE })
if (tg_ok) {
  W <- worst_inputs()
  cases <- list(정상 = E0$sw_compose_brief(FFS, SBS, MTD5, SBM, NULL, NOW),
                폴백 = E0$sw_compose_brief(FFS, SBS, NULL, NULL, NULL, NOW),
                최악 = E0$sw_compose_brief(W$FW, W$SW, W$MW, W$SMW, W$IB, NOW))
  for (nm in names(cases)) {
    o <- cases[[nm]]
    rr <- tryCatch({ invisible(capture.output(x <- tg_agent_brief(agent = "Q-Lead", title = o$title, sections = o$sections,
                                                                  charts = NULL, footer = o$footer, dry_run = TRUE))); x },
                   error = function(e) list(ok = FALSE, error = conditionMessage(e)))
    chk(sprintf("P8 %s 렌더 통과(dry_run)", nm), if (isTRUE(rr$ok) && isTRUE(rr$dry_run)) "" else
        if (is.null(rr$error)) "ok!=TRUE" else rr$error)
  }
}

cat("\n=== P9 드라이런 서브프로세스 — 운영 브리핑 파일 · 빌드 생략 · 샌드박스 데이터 ===\n")
local({
  S <- file.path(tempdir(), sprintf("sbt_dry_%d", Sys.getpid()))
  dir.create(file.path(S, "outputs/ff5_kr/charts"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(S, "outputs/smartbeta_kr/charts"), recursive = TRUE, showWarnings = FALSE)
  today <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = "Asia/Seoul"))
  as_of <- today - 1L; mym <- format(as_of, "%Y-%m")
  last <- format(seq(as.Date(paste0(mym, "-01")), by = "-1 month", length.out = 2L)[2L], "%Y-%m")
  yms <- rev(format(seq(as.Date(paste0(last, "-01")), by = "-1 month", length.out = 14L), "%Y-%m"))
  ff <- FFS; ff$ym <- yms; sb <- SBS; sb$ym <- yms
  write_parquet(ff, file.path(S, "outputs/ff5_kr/ff5_kr_monthly.parquet"))
  write_parquet(sb, file.path(S, "outputs/smartbeta_kr/smartbeta_kr_monthly.parquet"))
  write_json(modifyList(MTD5, list(as_of = format(as_of), ym = mym)), file.path(S, "outputs/ff5_kr/ff5_kr_mtd.json"), auto_unbox = TRUE)
  write_json(modifyList(SBM, list(as_of = format(as_of))), file.path(S, "outputs/smartbeta_kr/smartbeta_kr_mtd.json"), auto_unbox = TRUE)
  dry <- file.path(S, "dry.txt"); runner <- file.path(S, "run_brief.R")
  ## 환경은 러너 안에서 세운다 — ~/.Renviron 의 QM_ROOT 가 상속 환경을 덮어 자식이 운영 루트를 보는 함정 회피
  envs <- c(QM_ROOT = CODE, CLAUDE_PROJECT_DIR = S, FF5_BRIEF_DATA_DIR = S, FF5_BRIEF_SKIP_BUILD = "all",
            FF5_BRIEF_DRYRUN = "1", FF5_BRIEF_DRYRUN_RENDER = "0", FF5_BRIEF_DRYRUN_OUT = dry, QVEST_TG_DRY_RUN = "1")
  q <- function(x) sprintf('"%s"', gsub("\\\\", "/", x))
  writeLines(enc2utf8(c(sprintf("Sys.setenv(%s)", paste(sprintf("%s = %s", names(envs), q(envs)), collapse = ", ")),
                        sprintf("source(%s)", q(SEND)))), runner, useBytes = TRUE)
  out <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), shQuote(runner), stdout = TRUE, stderr = TRUE))
  rc <- attr(out, "status"); rc <- if (is.null(rc)) 0L else rc
  txt <- if (file.exists(dry)) readLines(dry, encoding = "UTF-8", warn = FALSE) else character(0)
  et <- sprintf("TITLE: 스타일 국면 브리핑 — FF5 + 스마트베타 (%s 기준 · 완결월 %s)", format(as_of), last)
  chk("P9a 종료코드 0 · 드라이런 본문 파일 기록", if (rc == 0L && length(txt)) "" else sprintf("rc=%s 본문 %d줄 · %s", rc, length(txt),
      paste(tail(out, 4), collapse = " | ")))
  chk(sprintf("P9b 제목 = as_of %s 기준 · 완결월 %s (운영 브리핑 배선)", format(as_of), last),
      if (any(txt == et)) "" else paste("TITLE 줄:", paste(grep("^TITLE", txt, value = TRUE), collapse = " / ")))
  chk("P9c 절1 = 'FF5 최근 완결월' · 12개월 절 = 진행월 MTD 포함 라벨",
      if (any(txt == sprintf("[절 1 · kv] FF5 최근 완결월 (%s)", last)) &&
          any(grepl(sprintf("^\\[절 2 · kv\\] FF5 최근 12개월\\(진행월 MTD 17거래일 포함, ~%s\\) 평균$", format(as_of, "%m-%d")), txt))) ""
      else "절 제목 불일치")
  chk("P9d 발송 0 — 'DRYRUN ok' · 텔레그램 미적재(tg_loaded=FALSE) · 'sent ok=' 없음",
      if (any(grepl("DRYRUN ok", out, fixed = TRUE)) && any(grepl("tg_loaded=FALSE", out, fixed = TRUE)) &&
          !any(grepl("sent ok=", out, fixed = TRUE))) "" else paste(tail(out, 3), collapse = " | "))
  unlink(S, recursive = TRUE)
})
## 배선 재도출: 발송 분기의 tg_agent_brief 가 조립 산출(out$title/out$sections)을 그대로 쓰는가
local({
  ex <- as.list(parse(file = SEND, encoding = "UTF-8", keep.source = FALSE))
  calls <- list()
  walk <- function(e) { if (is.call(e)) { if (identical(e[[1]], as.name("tg_agent_brief"))) calls[[length(calls) + 1L]] <<- e
    for (a in as.list(e)[-1]) if (!missing(a)) walk(a) } }
  for (e in ex) walk(e)
  send <- Filter(function(cl) is.null(cl$dry_run), calls)
  good <- length(send) == 1L && identical(deparse(send[[1]]$title), "out$title") && identical(deparse(send[[1]]$sections), "out$sections")
  chk("W1 발송 분기 tg_agent_brief(title = out$title, sections = out$sections) · 1곳", if (good) "" else
      sprintf("발송 호출 %d곳 · title=%s", length(send), if (length(send)) deparse(send[[1]]$title) else "-"))
  has_compose <- any(vapply(ex, function(e) grepl("sw_compose_brief(", paste(deparse(e), collapse = " "), fixed = TRUE), logical(1)))
  chk("W2 브리핑이 sw_compose_brief 로 조립", if (has_compose) "" else "조립 함수 미사용")
})

cat("\n=== P10 트래커 완결월 발행 가드 (파스 트리에서 꺼내 합성 입력으로 실행) ===\n")
tl_exprs <- function(path) as.list(parse(file = path, encoding = "UTF-8", keep.source = FALSE))
is_asg <- function(e, nm) is.call(e) && identical(e[[1]], as.name("<-")) && identical(e[[2]], as.name(nm))
g_ff5 <- function(path) {
  ex <- tryCatch(tl_exprs(path), error = function(e) NULL); if (is.null(ex)) return("파스 실패")
  hits <- Filter(function(e) is_asg(e, "rets") && grepl("max(ud)", paste(deparse(e[[3]]), collapse = " "), fixed = TRUE), ex)
  if (!length(hits)) return("완결월 가드(rets <- rets[… max(ud) …]) 부재 — 진행월 부분월이 월간 파일로 간다")
  env <- new.env(parent = globalenv())
  env$ud <- as.Date(c("2026-08-28", "2026-08-31", "2026-09-01", "2026-09-23"))
  env$rets <- data.table(ym = c("2026-07", "2026-08", "2026-09"), Date = as.Date(c("2026-07-31", "2026-08-31", "2026-09-23")), ret = 0.01)
  for (h in hits) eval(h, env)
  if ("2026-09" %in% env$rets$ym) return("진행월(2026-09) 부분월 행이 월간 패널에 남는다")
  if (!all(c("2026-07", "2026-08") %in% env$rets$ym)) return("완결월까지 잘린다")
  ""
}
g_sb <- function(path) {
  ex <- tryCatch(tl_exprs(path), error = function(e) NULL); if (is.null(ex)) return("파스 실패")
  hits <- Filter(function(e) is_asg(e, "last_ym") || is_asg(e, "sig_dates"), ex)
  if (sum(vapply(hits, is_asg, logical(1), nm = "sig_dates")) < 2L) return("sig_dates 완결월 필터 부재")
  ud <- seq(as.Date("2026-05-01"), as.Date("2026-09-23"), by = "day"); ud <- ud[!format(ud, "%u") %in% c("6", "7")]
  env <- new.env(parent = globalenv()); env$ud <- ud
  env$me <- sort(as.Date(unname(tapply(ud, format(ud, "%Y-%m"), max)), origin = "1970-01-01"))
  for (h in hits) eval(h, env)
  sm <- format(as.Date(env$sig_dates, origin = "1970-01-01"), "%Y-%m")
  if ("2026-08" %in% sm) return("08월말 신호(실현월 2026-09 = 진행 중 부분월)가 월간 발행 대상에 남는다")
  if (!all(c("2026-05", "2026-06", "2026-07") %in% sm)) return("완결월 신호까지 잘린다")
  ""
}
g_order <- function(path, obj) {   # 표시층(style_brief_lib 소스)은 월간 파일 기록 뒤 · 그 뒤 월간 객체 재할당 0 · 표시층 쓰기 0
  ex <- tl_exprs(path); dp <- vapply(ex, function(e) paste(deparse(e), collapse = " "), "")
  iw <- grep(sprintf("write_parquet(%s,", obj), dp, fixed = TRUE); il <- grep("style_brief_lib.R", dp, fixed = TRUE)
  if (!length(iw) || !length(il)) return(sprintf("기록(%d)·표시층 소스(%d) 식별 실패", length(iw), length(il)))
  if (min(il) < max(iw)) return("표시층이 월간 파일 기록보다 앞선다(진행월이 섞인 채 기록될 수 있다)")
  after <- ex[seq.int(min(il), length(ex))]
  if (any(vapply(after, is_asg, logical(1), nm = obj))) return(sprintf("표시층 뒤에서 %s 재할당", obj))
  ""
}
chk("P10a FF5 트래커 §1 완결월 가드 — 진행월 부분월 제외", g_ff5(TRK5))
chk("P10b 스마트베타 트래커 §3 완결월 가드 — 08월말 신호(실현 09 부분월) 제외", g_sb(TRKS))
chk("P10c FF5 표시층은 월간 기록 뒤 · FF 재할당 0", g_order(TRK5, "FF"))
chk("P10d 스마트베타 표시층은 월간 기록 뒤 · SB 재할당 0", g_order(TRKS, "SB"))
lib_io <- grepl("write_parquet|write_json|fwrite|saveRDS|file.rename", read_txt(LIB))
chk("P10e style_brief_lib.R 쓰기 호출 0(표시층 전용)", if (!lib_io) "" else "라이브러리가 파일을 쓴다")

cat("\n=== R1 읽기 전용 불변식 — 운영 월간 파일에 진행월(부분월) 없음 ===\n")
local({
  rd <- file.path(ROOT, ".cache/rawdata.parquet")
  pf <- c(FF5 = "outputs/ff5_kr/ff5_kr_monthly.parquet", SB = "outputs/smartbeta_kr/smartbeta_kr_monthly.parquet")
  miss <- c(rd, file.path(ROOT, pf))[!file.exists(c(rd, file.path(ROOT, pf)))]
  if (length(miss)) { sk("R1 운영 불변식", "운영 파일 부재", paste(miss, collapse = ";")); return(invisible()) }
  pym <- format(max(as.Date(read_parquet(rd, col_select = "Date")$Date)), "%Y-%m")
  for (k in names(pf)) {
    mx <- max(read_parquet(file.path(ROOT, pf[[k]]), col_select = "ym")$ym)
    chk(sprintf("R1 %s 월간 max(ym)=%s < 진행월 %s", k, mx, pym), if (mx < pym) "" else "진행월 부분월이 월간 파일에 발행됐다")
  }
})

cat("\n=== 위반 주입 (사본 돌연변이 → red 여야 한다) ===\n")
mut <- function(label, path, from, to, judge) {
  m <- mutate(path, from, to)
  if (!isTRUE(m$ok)) { ng(label, m$why); return(invisible()) }
  why <- tryCatch(judge(m$file), error = function(e) paste("크래시:", conditionMessage(e)))
  if (nzchar(why)) ok(sprintf("%s → red (%s)", label, substr(why, 1, 70))) else ng(label, "돌연변이가 통과했다 — 검사가 이 위반을 못 잡는다")
}
mut("M1 창을 완결 12개월로 되돌림(MTD 무시)", LIB, "use_mtd <- isTRUE(st$ok)", "use_mtd <- FALSE",
    function(f) { E <- lib_env(f); paste0(c_window_ff(E), c_compose(E)) })
mut("M2 제목을 완결월 기준으로 되돌림", LIB,
    'sprintf("%s (%s 기준 · 완결월 %s)", .SW_TITLE_HEAD, format(w$state$as_of), w$last_ym)',
    'sprintf("%s (%s 기준)", .SW_TITLE_HEAD, w$last_ym)', function(f) c_title(lib_env(f)))
mut("M3 월평균 분모 12 → 11", LIB, "sum(v, na.rm = TRUE) / sum(!is.na(v))", "sum(v, na.rm = TRUE) / 11",
    function(f) c_window_ff(lib_env(f)))
mut("M4 낡은 MTD(stale) 판정 제거", LIB, 'if (mym <= last_ym) return(mk(FALSE, "stale", a, nd))', "invisible(NULL)",
    function(f) c_stale(lib_env(f)))
mut("M5 FF5 트래커 완결월 가드 제거(부분월 월간 기록)", TRK5, 'rets <- rets[ym < format(max(ud), "%Y-%m")]', "invisible(NULL)", g_ff5)
mut("M6 스마트베타 트래커 가드 '<' → '<='(부분월 발행)", TRKS, 'format(nx, "%Y-%m") < last_ym', 'format(nx, "%Y-%m") <= last_ym', g_sb)
finish()
