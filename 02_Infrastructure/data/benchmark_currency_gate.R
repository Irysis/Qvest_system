#!/usr/bin/env Rscript
# benchmark_currency_gate.R — 거래일 지평선 단일점 감시 (2026-08-20 신설, BMG-01)
#
# 왜 있는가 (실사고 2026-08-14~20, 6일 정체):
#   .cache/benchmark.parquet 은 naver_benchmark_update.py 가 유일하게 쓰는 파일이고
#   (그 파일 L64 주석: "benchmark.parquet 저장 단일점"), trading_calendar.R 은 RAWDATA
#   자기참조의 순환오염을 끊으려고 **이 파일만을** 거래일 권위로 삼는다(L45/L137).
#   그런데 daily_refresh 의 [1pre] 는 실패해도 `|| echo "skipped (기존 cache 유지)"` 로
#   조용히 넘어간다. venv 소실로 그 스텝이 죽자 벤치마크가 08-14 에 얼어붙었고 →
#   캘린더가 얼고 → Naver 는 "already >= target", KRX 는 "gap 0 days" 를 **정직하게**
#   보고했다. 게이트가 거짓말한 게 아니라 얼어붙은 값을 정직하게 읽은 것이다.
#   ⇒ 결과: 거래일 3일(08-18/19/20)이 비었는데 리프레시는 6일 내내 "실패 0" 으로 마감.
#
# ★두 축이 필요하다 (하나로는 못 잡는다):
#   A. 갱신기가 **죽었는가**  — 호출부가 rc 를 버리지 않고 넘겨준다(--updater-rc).
#   B. 갱신기가 살아서 **아무것도 안 썼는가** — 파일 자체의 최신일이 늙었는가.
#   A 만 있으면 "exit 0 인데 no-op" 을 놓치고, B 만 있으면 장기 휴장과 구분이 안 된다.
#
# ★★B 의 문턱은 고정값이다(기본 7일). 한국 시장 최장 연휴(설·추석+주말)는 9일까지 가므로
#   그 창에서 오탐이 날 수 있다 — 그래서 B 는 **WARN 축**이고 A 가 **하드 축**이다.
#
# ★★이번 실사고를 B 는 **못 잡는다** — 정직하게 적어 둔다(2026-08-20 자기정정).
#   08-14 동결 → 08-20 발견 = lag 6일 < 문턱 7. 즉 B 를 이 사고의 방어선으로 읽으면 안 된다.
#   이 사고를 실제로 잡는 축은 A 다(갱신기가 매 런 rc≠0 으로 죽고 있었다 — 6일 내내).
#   B 의 존재 이유는 **다른 실패 모드**다: 갱신기가 exit 0 인데 아무것도 안 쓰는 경우.
#   그 경우 정체는 무한히 자라므로 느슨한 문턱으로도 결국 걸린다(늦게라도 걸리는 게 목적).
#   문턱을 6 미만으로 낮추면 이 사고도 B 가 잡지만 연휴 오탐이 상시화된다 — 그 교환은
#   하지 않는다. A 가 정밀 축이고 B 는 늦은 그물이다.
#
# 사용:
#   Rscript benchmark_currency_gate.R [--updater-rc N] [--path P] [--today YYYY-MM-DD]
#                                     [--max-lag-days K] [--quiet]
# 종료코드: 0=정상 / 1=정체·실패 감지(호출부가 DR_FAILED 에 올릴 것) / 2=판정 불가

suppressWarnings(suppressMessages({ library(arrow); library(data.table) }))

args <- commandArgs(trailingOnly = TRUE)
getarg <- function(flag, default = NULL) {
  i <- which(args == flag)
  if (length(i) == 1L && length(args) >= i + 1L) args[i + 1L] else default
}
# 금칙④(r-portability): resolver 우선순위는 CLAUDE_PROJECT_DIR 먼저. R 에서는
#   ~/.Renviron 이 QM_ROOT 를 고정해 export 로 못 덮으므로, QM_ROOT 를 앞에 두면
#   워크트리 세션이 자기 트리가 아니라 main 을 가리킨다(2026-08-20 래칫 검거).
ROOT <- Sys.getenv("CLAUDE_PROJECT_DIR", Sys.getenv("QM_ROOT", getwd()))
ROOT <- gsub("\\\\", "/", ROOT)

BM_PATH  <- getarg("--path", file.path(ROOT, ".cache", "benchmark.parquet"))
TODAY    <- as.Date(getarg("--today", format(Sys.Date())))
MAX_LAG  <- as.integer(getarg("--max-lag-days", "7"))
UPD_RC   <- getarg("--updater-rc", NA_character_)
QUIET    <- "--quiet" %in% args

say <- function(...) if (!QUIET) cat(sprintf(...))

fails <- character(0)

# ── 축 A: 갱신기 종료코드 (하드) ──────────────────────────────────────────────
if (!is.na(UPD_RC) && nzchar(UPD_RC)) {
  rc <- suppressWarnings(as.integer(UPD_RC))
  if (is.na(rc)) {
    fails <- c(fails, sprintf("A:updater-rc 해석불가(%s)", UPD_RC))
  } else if (rc != 0L) {
    fails <- c(fails, sprintf("A:갱신기 실패(rc=%d)", rc))
    say("!! [bm-gate][A] 벤치마크 갱신기가 rc=%d 로 죽었다 — 이 파일은 거래일 캘린더의 유일 권위다.\n", rc)
    say("   방치하면 캘린더가 얼고 Naver/KRX 가 'gap 0' 을 정직하게 보고해 결손이 안 보인다.\n")
  }
} else {
  say("   [bm-gate][A] updater-rc 미전달 — 갱신기 생사 축은 판정하지 않음(호출부가 --updater-rc 를 넘길 것).\n")
}

# ── 축 B: 파일 최신일 (WARN 축, 고정 문턱) ────────────────────────────────────
if (!file.exists(BM_PATH)) {
  fails <- c(fails, "B:benchmark.parquet 부재")
  say("!! [bm-gate][B] %s 부재 — 거래일 판정 불가.\n", BM_PATH)
} else {
  bm_max <- tryCatch(
    max(as.Date(as.data.table(read_parquet(BM_PATH, col_select = "Date"))$Date), na.rm = TRUE),
    error = function(e) as.Date(NA))
  if (is.na(bm_max)) {
    fails <- c(fails, "B:Date 열 판독 실패")
    say("!! [bm-gate][B] Date 열을 읽지 못했다 (%s).\n", BM_PATH)
  } else {
    lag_d <- as.integer(TODAY - bm_max)
    say("   [bm-gate][B] benchmark max(Date)=%s  today=%s  lag=%d일 (문턱 %d)\n",
        format(bm_max), format(TODAY), lag_d, MAX_LAG)
    if (lag_d > MAX_LAG) {
      fails <- c(fails, sprintf("B:벤치마크 정체(lag=%d일>%d)", lag_d, MAX_LAG))
      say("!! [bm-gate][B] ★벤치마크가 %d일 정체 — 갱신기가 exit 0 이어도 아무것도 안 썼을 수 있다.\n", lag_d)
      say("   (장기 연휴 오탐 가능: 설·추석+주말은 9일까지. 그 경우에도 A축이 0 이면 무해한 경고다.)\n")
    }
  }
}

if (length(fails) > 0L) {
  cat(sprintf("[bm-gate] FAIL: %s\n", paste(fails, collapse = " | ")))
  quit(status = 1L)
}
say("   [bm-gate] OK — 거래일 지평선 정상.\n")
quit(status = 0L)
