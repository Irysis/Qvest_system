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

# ── 축 C: 레벨 축 정합 + 이음매 (하드) ────────────────────────────────────────
#
# 규약(2026-09-18 정규화): `BM_Close` = **공표 코스피200 지수 종가(포인트) 그대로**.
#   배율 개념 없음. 잴 것은 둘이다 — ①값이 같은가 ②그 같음이 하루 사이 계단을 안 타는가.
#
# 왜 여기인가 (실측 2026-09-07 · 수리 2026-09-18):
#   `BM_Close` 가 지수의 **8.834448배** 위에 있었다(BM_Ret 은 결백). 두 달 넘게 안 걸렸다.
#   같은 불변식을 적어 둔 가드는 이미 있었다(build_cache.R) — 안 발화한 이유는 두 겹:
#     ① **찬 경로다.** build_cache.R 은 전체 재빌드 스크립트이고 daily_refresh 가 안 부른다.
#     ② **동어반복이다.** 바로 앞 build_index_cache.py 가 같은 프로세스에서 방금 쓴
#        자기 산출물을 비교한다 — 그 뒤 다른 writer 가 파일을 어떻게 바꾸는지는 못 본다.
#   ⇒ 축 C 는 같은 불변식을 **소비면에서 · 상시 경로에서 · 독립 소스로** 잰다.
#
# ★2026-09-18 자기정정 — 구 축 C 는 **원리적으로 통과할 수 없었다**. 체인 축(8.83배) 위에서
#   |배수-1|<=0.01 을 요구했으므로 신설(09-07) 이후 매일 FAIL 이었다. 상시 오탐 = 상시 침묵
#   이라 진짜 이음매를 가린다. 파일을 축에 맞춘 뒤(rebuild_benchmark_canonical.py) 이 검사는
#   참이 될 수 있는 명제가 됐다. 그리고 **이음매 축을 더했다** — 정합만 재면 "전 구간이
#   똑같이 어긋난" 경우만 잡고 정확히 재발했던 하루짜리 계단은 놓친다.
#
# ★부재는 '정상' 이 아니다: 참조를 못 구하거나 공통 세션이 부족하면 no_measure 로 남기고
#   fails 에 올리지 않는다. 조용히 초록을 내는 것과 다르다(로그에 명시된다).
# ★축 정본(benchmark_level_axis.R)은 축 C·D 가 함께 쓰므로 블록 **밖**에서 한 번만 싣는다.
#   (구판은 C 블록 안에서 source 했는데, D 를 더하면서 C 를 건너뛴 경로에서 lcfg 가
#    없어 죽는다 — 앞 절의 잔재를 전제로 삼은 절은 앞 절을 끄면 죽는다.)
LVL_SRC <- file.path(ROOT, "02_Infrastructure/data/benchmark_level_axis.R")
LVL_OK  <- file.exists(LVL_SRC)
if (LVL_OK) source(LVL_SRC)
lcfg <- if (LVL_OK) bench_level_config(ROOT) else
  list(BENCH_LEVEL_AXIS = "index_points", BENCH_LEVEL_TOL = 1e-4,
       BENCH_LEVEL_SEAM_TOL = 1e-4, BENCH_LEVEL_MIN_SESSIONS = 5L,
       BENCH_LEVEL_WINDOW_SESSIONS = 0L, BENCH_CANONICAL_MAX_LAG_DAYS = 10L)

if (!"--no-level" %in% args && file.exists(BM_PATH)) {
  if (!LVL_OK) {
    say("   [bm-gate][C] 레벨 축 정본 부재 — 미측정 (%s)\n", LVL_SRC)
  } else {
    ltol <- suppressWarnings(as.numeric(getarg("--level-tol", as.character(lcfg$BENCH_LEVEL_TOL))))
    if (!is.finite(ltol) || ltol <= 0) ltol <- as.numeric(lcfg$BENCH_LEVEL_TOL)
    lseam <- suppressWarnings(as.numeric(getarg("--seam-tol", as.character(lcfg$BENCH_LEVEL_SEAM_TOL))))
    if (!is.finite(lseam) || lseam <= 0) lseam <- as.numeric(lcfg$BENCH_LEVEL_SEAM_TOL)

    bm_lvl <- tryCatch(as.data.table(read_parquet(BM_PATH)), error = function(e) NULL)
    ref_path <- getarg("--ref-path", NULL)          # 테스트용 주입 경로 (Date + ref_close)
    ref <- if (!is.null(ref_path) && file.exists(ref_path)) {
      rr <- tryCatch(as.data.table(read_parquet(ref_path)), error = function(e) NULL)
      if (is.null(rr)) NULL else {
        if (!"ref_close" %in% names(rr) && "kospi200" %in% names(rr))
          setnames(rr, "kospi200", "ref_close")
        if (!"ref_source" %in% names(rr)) rr[, ref_source := "injected"]
        rr[, .(Date = as.Date(Date), ref_close = as.numeric(ref_close),
               ref_source = as.character(ref_source))]
      }
    } else bench_level_reference(ROOT)

    lv <- bench_level_axis_check(bm_lvl, ref, tol = ltol, seam_tol = lseam,
                                 min_sessions = lcfg$BENCH_LEVEL_MIN_SESSIONS,
                                 window_sessions = lcfg$BENCH_LEVEL_WINDOW_SESSIONS)
    if (identical(lv$status, "violation")) {
      # ★어느 축이 얼마나 어긋났는지를 사유에 적는다 — "C 실패" 만으로는 수리가 안 된다.
      fails <- c(fails, sprintf("C:%s(편차=%.3e 이음매=%.3e)",
                                lv$failed_axis, lv$max_dev,
                                if (is.finite(lv$max_seam)) lv$max_seam else 0))
      say("!! [bm-gate][C] ★%s\n", lv$detail)
      say("   축 정본 = .cache/benchmark_axis.json::unit ('%s'). 수리 = rebuild_benchmark_canonical.py --write\n",
          lcfg$BENCH_LEVEL_AXIS)
      say("   ※BM_Ret 은 스케일 불변이다 — 레벨만 어긋났다면 재구축이 수익률을 바꾸지 않는다(이음매 날짜 제외).\n")
    } else if (identical(lv$status, "no_measure")) {
      say("   [bm-gate][C] 미측정 — %s\n", lv$detail)
    } else {
      say("   [bm-gate][C] 레벨 축 정합 — %s\n", lv$detail)
    }
  }
}

# ── 축 D: 정본(QuantiWise xlsx) 신선도 (WARN 축) ──────────────────────────────
#
# ★왜 (도훈 2026-09-18): 모든 재발의 온상은 **정본이 멈춘 것을 아무도 못 본 것**이었다.
#   `03_Universe/Benchmark_price.xlsx` 가 07-01 이후 안 들어오는 사이, 일일 배관은
#   조용히 Naver 로 때우며 옛 체인 위에 값을 얹었다. 그래서 indices.parquet 은 06-30 에
#   멈췄는데 benchmark.parquet 은 매일 '최신' 이었다 — B축(정체)은 초록, 결함은 진행.
#   축 D 는 그 침묵을 깬다: 정본이 며칠째 안 들어왔는지를 **소비면에서** 센다.
# ★WARN 축인 이유: 정본 미갱신은 그 자체로 데이터 오류가 아니다(축 C 가 값을 지킨다).
#   하드로 걸면 xlsx 수급이 끊긴 기간 내내 리프레시가 통째로 빨개진다. 다만 **보이게** 한다.
if (!"--no-canonical" %in% args && LVL_OK && exists("bench_canonical_freshness")) {
  CMAX <- suppressWarnings(as.integer(getarg("--canonical-max-lag-days", NA_character_)))
  if (is.na(CMAX)) CMAX <- as.integer(lcfg$BENCH_CANONICAL_MAX_LAG_DAYS)
  cf <- tryCatch(bench_canonical_freshness(ROOT, TODAY), error = function(e) NULL)
  if (is.null(cf) || identical(cf$status, "no_measure")) {
    say("   [bm-gate][D] 정본 신선도 미측정 — %s\n", if (is.null(cf)) "판독 실패" else cf$detail)
  } else if (is.finite(cf$lag_days) && cf$lag_days > CMAX) {
    say("!! [bm-gate][D] ★정본 xlsx 미갱신 %d일 (문턱 %d) — %s\n", cf$lag_days, CMAX, cf$detail)
    say("   정본 = 03_Universe/Benchmark_price.xlsx → build_index_cache.py. 수급 경로 = quantiwise_fetch.py\n")
    say("   ※Naver 로 때우면 축은 유지되지만 정본은 계속 멈춰 있다 — 때움은 경보를 남긴다(.cache/benchmark_axis_alert.json).\n")
    say("   ※이 축은 WARN 이다(리프레시를 실패시키지 않는다). 그러나 **보이지 않게 두지 않는다**.\n")
  } else {
    say("   [bm-gate][D] 정본 신선도 — %s\n", cf$detail)
  }
}

if (length(fails) > 0L) {
  cat(sprintf("[bm-gate] FAIL: %s\n", paste(fails, collapse = " | ")))
  quit(status = 1L)
}
say("   [bm-gate] OK — 거래일 지평선 정상.\n")
quit(status = 0L)
