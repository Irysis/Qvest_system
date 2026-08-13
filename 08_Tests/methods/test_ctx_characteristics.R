#!/usr/bin/env Rscript
# test_ctx_characteristics.R — ctx 특성 확장 계약 (2026-08-13 신설)
#
# 왜: 2026-08-13 에 어댑터 ctx 에 `characteristics` 접근자를 붙여 특성 기반 방법(CD-DFM 계열)을
#   열었다. 그런데 **확장은 선언됐을 뿐 아무도 쓰지 않는다** — 이 저장소가 반복해 온
#   "존재 = 배선 완료" 착각의 정확한 형태다(screen_route 소비자 0 · wiring_map 미소비 표준).
#   확장을 실제로 소비하는 경로가 살아 있는지, 그리고 **틀리게 쓰면 막히는지**를 여기서 고정한다.
#
# ★본체는 T3·T4 다:
#   T3 = PIT — 특성 sig_date 가 **홀딩월 시작 전**인가(당월 패널이면 동월 look-ahead).
#        2026-07-06 BearProb 사고가 정확히 이 형태였고 placebo/OOS/DSR 를 전부 통과했다.
#   T4 = NULL 처리 — production 은 패널 부재/로드 실패 시 NULL 을 낸다. 성공 경로만 있는
#        어댑터는 **패널이 빈 달에 죽는다**. 등재 게이트가 그걸 잡는지 본다.
set.seed(20260813)

.root <- (function() {
  for (c in c(Sys.getenv("QM_ROOT"), Sys.getenv("CLAUDE_PROJECT_DIR"), getwd()))
    if (nzchar(c) && dir.exists(file.path(c, "06_Registry"))) return(c)
  getwd()
})()
setwd(.root)
suppressWarnings(suppressMessages(source("02_Infrastructure/methods/register_method.R")))
suppressWarnings(suppressMessages(source("02_Infrastructure/methods/ctx_providers.R")))

PASS <- 0; FAIL <- 0
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1; cat(sprintf("  ok   %s %s\n", name, detail)) }
  else            { FAIL <<- FAIL + 1; cat(sprintf("  FAIL %s %s\n", name, detail)) }
}
tmp <- file.path(tempdir(), "ctxchar"); dir.create(tmp, showWarnings = FALSE)
mk <- function(nm, txt) { p <- file.path(tmp, nm); writeLines(txt, p); p }

cat("== ctx 특성 확장 계약 ==\n")

# ── T1 fixture 가 접근자를 제공하는가 (양성 대조 — 없으면 이하 전부 공허)
fx <- rm_fixture()
chk("T1 weight/sigma ctx 에 characteristics 접근자 존재",
    is.function(fx$weight$characteristics) && is.function(fx$sigma$characteristics))

ch <- fx$weight$characteristics()
chk("T1b 접근자가 list(sig_date, panel) 반환",
    is.list(ch) && !is.null(ch$sig_date) && !is.null(ch$panel),
    sprintf("(패널 %dx%d)", nrow(ch$panel), ncol(ch$panel)))

# ── T2 특성을 **실제로 쓰는** 어댑터가 등재 검증을 통과한다 (배선 실효)
#   ★probe 는 리서치 방법이 아니라 **배관 검사용**이다 — 원장에 등재하지 않는다.
probe <- mk("probe_char.R", paste(
  "method_weights <- function(ctx) {",
  "  ch <- if (is.function(ctx$characteristics)) ctx$characteristics() else NULL",
  "  a <- ctx$assets",
  "  if (is.null(ch) || is.null(ch$panel)) return(setNames(rep(1, length(a)), a))   # NULL 처리",
  "  p <- ch$panel; v <- setNames(rep(NA_real_, length(a)), a)",
  "  if (all(c('Ticker','char_value') %in% names(p))) {",
  "    m <- match(a, p$Ticker); v <- as.numeric(p$char_value)[m]",
  "  }",
  "  v[!is.finite(v)] <- 0",
  "  w <- exp(v - max(v)); names(w) <- a; w",     # 특성에 단조인 선호
  "}", sep = "\n"))
v2 <- suppressWarnings(verify_adapter(probe, "weight", "PROBE_CHAR"))
chk("T2 특성 소비 어댑터가 등재 검증 통과(배선 실효)", isTRUE(v2$ok),
    if (isTRUE(v2$ok)) sprintf("(%s)", v2$checks$non_degenerate) else paste("-", v2$reason))

# ── T3 ★PIT — 특성 sig_date 가 홀딩월 시작 전인가
hold_start <- as.Date(format(as.Date(fx$weight$decision_date), "%Y-%m-01"))
chk("T3 특성 sig_date < 홀딩월 시작 (C5 동형)",
    as.Date(ch$sig_date) < hold_start,
    sprintf("(sig %s < hold_start %s)", ch$sig_date, hold_start))

# ── T3b production 경로도 같은 규약인가 — 소스에서 컷오프 식을 직접 확인
# ★2026-08-13 2차: PIT/C15 로직이 배터리에서 **ctx_providers.R 로 이동**했다(provider 레지스트리화).
#   검사가 옛 위치를 계속 보면 이동 후 **거짓 FAIL** 을 낸다 — 실제로 T3b/T3c 가 그렇게 갈렸고,
#   그건 대상의 결함이 아니라 검사가 이사를 못 따라간 것이다(오늘 반복 확인한 계통).
srcl <- readLines("02_Infrastructure/methods/ctx_providers.R", warn = FALSE)
src  <- paste(srcl, collapse = "\n")
btl  <- readLines("02_Infrastructure/ops/auto_sigma_weighting_ab.R", warn = FALSE)
chk("T3b production 이 '직전 월말'을 sig_date 로 쓴다",
    grepl('format\\(as\\.Date\\(decision_date\\), "%Y-%m-01"\\)\\) - 1L', src))
# ★C15 검사는 **줄 단위**로 한다. 초판은 collapse 한 문자열에 `read_parquet\\(.*factor_db` 를 걸었는데
#   R 정규식의 `.` 는 개행도 먹어서 23행의 read_parquet 가 파일 저 뒤의 factor_db 와 매칭됐다
#   — 무관한 두 줄이 한 위반으로 보고됐다(오늘 반복 확인한 과잉매칭 계통).
chk("T3c production 이 load_month_factors 경유 (C15)",
    any(grepl("load_month_factors\\(sig\\)", srcl, fixed = FALSE)))
chk("T3d factor_db parquet 직독 없음 (C15) — 줄 단위 검사",
    !any(grepl("read_parquet", srcl) & grepl("factor_db", srcl)))
# T3e 배터리는 이제 **splice 만** 한다 — 입력 추가가 측정 경로 수정을 요구하면 안 된다
# ★주석은 배제하고 **코드만** 본다. 초판이 주석 한 줄("…load_month_factors() 경유")을
#   하드코딩으로 세어 거짓 FAIL 을 냈다 — 설명문을 위반으로 읽는 검사는 고쳐야 할 쪽이 검사다.
.btl_code <- sub("#.*$", "", btl)
chk("T3e 배터리가 provider 레지스트리 경유(입력별 하드코딩 없음)",
    any(grepl("build_ctx_extras", .btl_code, fixed = TRUE)) &&
      !any(grepl("load_month_factors", .btl_code, fixed = TRUE)))
# T3f provider 계약 강제 — pit_note 없는 등록은 거부된다
.rej <- tryCatch({ register_ctx_provider("t_nopit", function(d, a) 1); FALSE },
                 error = function(e) grepl("pit_note", conditionMessage(e)))
chk("T3f PIT 미신고 provider 등록 거부", isTRUE(.rej))

# ── T4 ★NULL 처리 — 축을 다시 설계했다 (초판 결함).
#   초판은 NULL 상황에서 **등재 검증**을 돌려 통과 여부를 봤는데, 그건 성립하지 않는다:
#   신호가 전부 특성에서 오는 어댑터는 패널이 없으면 **중립(EW)을 내는 것이 옳고**,
#   비-퇴화 게이트는 정확히 그 EW 를 거부한다. 즉 정상 어댑터와 고장난 어댑터가 **둘 다 EW** 로
#   수렴해 구분되지 않는다(초판 T4/T4b 가 같은 사유로 갈렸다).
#   ⇒ 등재 검증은 **패널이 있는 운영 조건**에서 하고(T2), NULL 안전성은 별도로
#     "예외 없이 유효 길이 벡터를 내는가"로만 잰다. 성능이 아니라 **생존**을 묻는 축이다.
.run_null <- function(path) {
  e <- new.env(parent = globalenv()); sys.source(path, envir = e)
  fnn <- get("method_weights", envir = e)
  cx <- fx$weight; cx$characteristics <- function() NULL
  tryCatch({ o <- fnn(cx); list(err = FALSE, len = length(o)) },
           error = function(z) list(err = TRUE, msg = conditionMessage(z)))
}
bad <- mk("probe_char_nonull.R", paste(
  "method_weights <- function(ctx) {",
  "  ch <- ctx$characteristics()",
  "  v <- as.numeric(ch$panel$char_value)   # ch=NULL 이면 numeric(0)",
  "  setNames(exp(v - max(v)), ctx$assets)  # 길이 불일치로 예외",
  "}", sep = "\n"))
r_bad  <- .run_null(bad)
r_good <- .run_null(probe)
chk("T4 NULL 미처리 어댑터는 예외를 던진다(검출 가능)", isTRUE(r_bad$err),
    if (isTRUE(r_bad$err)) sprintf("(%s)", substr(r_bad$msg, 1, 40)) else "예외 없음 — 축이 공허")
chk("T4b NULL-safe 어댑터는 예외 없이 유효 길이 반환", !isTRUE(r_good$err) &&
      identical(r_good$len, length(fx$weight$assets)),
    sprintf("(len=%s)", r_good$len %||% "err"))

# ── T5 확장이 기존 arm 을 바꾸지 않았다 (순수 가산 — 회귀 0)
base <- c(ConformalKelly = "02_Infrastructure/methods/adapters/conformal_kelly.R",
          SchurDamping   = "02_Infrastructure/methods/adapters/schur_damping.R")
allok <- TRUE
for (nm in names(base)) {
  vv <- suppressWarnings(verify_adapter(base[[nm]], "weight", nm))
  if (!isTRUE(vv$ok)) allok <- FALSE
}
chk("T5 기존 어댑터가 확장 후에도 전부 통과(순수 가산)", allok)

TOTAL <- PASS + FAIL
cat(sprintf("  ── %d/%d pass\n", PASS, TOTAL))
cat(sprintf('{"test":"ctx_characteristics","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, TOTAL))
quit(status = if (FAIL == 0) 0 else 1)
