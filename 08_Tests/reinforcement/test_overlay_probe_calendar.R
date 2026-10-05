#==============================================================================
# test_overlay_probe_calendar.R — 오버레이 probe 6번째 검사: 달력 리터럴 (v10.4 2026-09-17)
#
# 대상: 02_Infrastructure/reinforcement/overlay_probe.R :: overlay_probe_calendar_scan / overlay_probe_arm("calendar")
# ★왜: 합성 픽스처(2006-01 기점 240개월)는 실제 달력과 어긋난다. "2008년 이후만" · "t 가 146~153 이면"
#   같은 논리는 픽스처에서 **안 켜지고** fwd 섭동·처치 검사를 통과한 뒤 실데이터에서만 켜진다 —
#   probe 를 비껴가는 형태다. 특정 날짜를 아는 것 자체가 사후 지식이므로 정적으로 거른다.
# ★양방향: 위반 주입 6종(전부 "calendar" 에서 죽어야 한다) + 음성 대조 3종(포맷 문자열·날짜끼리 비교·
#   주석 속 날짜는 통과) + 기존 arm 전수 정적 스캔(과잉 차단이면 생성기가 정당한 arm 을 못 낸다).
# 부작용: overlay_arms/ 에 zz_cal_* 픽스처를 잠시 쓰고 지운다(함수 안 on.exit — 발화한다).
#==============================================================================
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
suppressMessages(source("02_Infrastructure/reinforcement/overlay_probe.R"))

PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat(paste("  OK   ", m), fill = TRUE) }
ng <- function(m, d = "") { FAIL <<- FAIL + 1L
  cat(paste("  FAIL ", m, if (nzchar(d)) paste("—", d) else ""), fill = TRUE) }

ADIR <- file.path(ROOT, "02_Infrastructure/reinforcement/overlay_arms")
inject <- function(kind, lines) {
  p <- file.path(ADIR, paste0(kind, ".R"))
  writeLines(lines, p)
  on.exit(unlink(p), add = TRUE)
  overlay_probe_arm(kind)
}
failed_at <- function(r) { z <- r$checks[status == "FAIL"]; if (nrow(z)) z$check[1] else NA_character_ }
cal_row   <- function(r) { z <- r$checks[check == "calendar"]; if (nrow(z)) z$status[1] else NA_character_ }

cat("=== A. 양성 대조 — 정상 arm 과 포맷 문자열은 통과 ===", fill = TRUE)
r0 <- overlay_probe_arm("dbeta_tilt")
if (isTRUE(r0$ok) && identical(cal_row(r0), "PASS"))
  ok("A1 dbeta_tilt 통과 · calendar 행 PASS 로 기록") else ng("A1 정상 arm 이 막혔다", as.character(r0$reason))

# 기존 arm 전수 정적 스캔 — pg2_risk_overlay 의 "%Y-%m-01" · sprintf("%04d-%02d-01") · paste0(ym, "-01") 이 여기 걸리면 안 된다
arms <- setdiff(list.files(ADIR, pattern = "\\.R$"), list.files(ADIR, pattern = "^zz_"))
hits <- character(0)
for (f in arms) {
  s <- overlay_probe_calendar_scan(file.path(ADIR, f))
  if (nrow(s)) hits <- c(hits, sprintf("%s[%s]", f, paste(s$rule, collapse = ",")))
}
if (length(arms) >= 5L && !length(hits))
  ok(sprintf("A2 기존 arm %d개 정적 스캔 — 달력 리터럴 0 (과잉 차단 없음)", length(arms))) else
  ng("A2 기존 arm 이 걸렸다", paste(hits, collapse = " "))

r <- inject("zz_cal_clean1", c(
  "overlay_expo_zz_cal_clean1 <- function(H, t, ctx) {",
  "  yr <- format(H$Date, \"%Y\")                 # 그룹 키로만 쓴다 — 연도 값과 비교하지 않는다",
  "  ym <- format(ctx$date, \"%Y-%m\")",
  "  v <- H$rv60; okv <- is.finite(v)",
  "  if (sum(okv) < 24L) return(1)",
  "  ybar <- stats::ave(v[okv], yr[okv])            # 연도별 평균(★R3R: tapply 는 ③d 허용 목록 밖 — 정본 arm 이 쓰는 ave 로)",
  "  ref <- stats::median(ybar)",
  "  now <- v[t]",
  "  if (!is.finite(now) || now <= 0) return(1)",
  "  max(0, min(1, ref / now))",
  "}"))
if (isTRUE(r$ok) && identical(cal_row(r), "PASS"))
  ok("A3 음성 대조 — format(…, \"%Y\") 를 그룹 키로만 쓰는 arm 은 통과") else ng("A3 오탐", as.character(r$reason))

r <- inject("zz_cal_clean2", c(
  "overlay_expo_zz_cal_clean2 <- function(H, t, ctx) {",
  "  d  <- as.Date(ctx$date)",
  "  hs <- as.Date(format(d, \"%Y-%m-01\"))          # 포맷 문자열은 달력 리터럴이 아니다",
  "  ym <- format(d, \"%Y-%m\"); nxt <- as.Date(paste0(ym, \"-01\"))",
  "  past <- H$Date < d                              # 날짜끼리 비교",
  "  if (t < 12L || sum(past) < 24L) return(1)       # 워밍업 가드(한 방향 · 두 자리)는 통과",
  "  x <- H$dd[past]; x <- x[is.finite(x)]",
  "  q <- stats::ecdf(x)(H$dd[t])",
  "  if (!is.finite(q)) return(1)",
  "  max(0, min(1, 1 - q))",
  "}"))
if (isTRUE(r$ok) && identical(cal_row(r), "PASS"))
  ok("A4 음성 대조 — 날짜 객체끼리 비교 · \"%Y-%m-01\" · paste0(ym, \"-01\") 통과") else ng("A4 오탐", as.character(r$reason))

r <- inject("zz_cal_cmt", c(
  "# 2008-10 위기 국면에서 켜지는가 — 주석의 날짜는 코드가 아니다",
  "overlay_expo_zz_cal_cmt <- function(H, t, ctx) {   # as.Date(\"2008-10-31\") 를 쓰지 않는다",
  "  h <- H$rv60[is.finite(H$rv60)]; if (length(h) < 24L) return(1)",
  "  v <- H$rv60[t]; if (!is.finite(v) || v <= 0) return(1)",
  "  max(0, min(1, stats::median(h) / v))",
  "}"))
if (isTRUE(r$ok) && identical(cal_row(r), "PASS"))
  ok("A5 음성 대조 — 주석 속 날짜는 걸리지 않는다") else ng("A5 주석이 걸렸다", as.character(r$reason))

cat("", fill = TRUE); cat("=== B. 위반 주입 — 전부 calendar 에서 죽어야 한다 ===", fill = TRUE)
viol <- list(
  B1 = list(what = "format(ctx$date, \"%Y\") >= \"2008\"", lines = c(
    "overlay_expo_zz_cal_v1 <- function(H, t, ctx) {",
    "  if (format(ctx$date, \"%Y\") >= \"2008\") return(0.5)",
    "  1", "}")),
  B2 = list(what = "ctx$date >= as.Date(\"2018-01-31\")", lines = c(
    "overlay_expo_zz_cal_v2 <- function(H, t, ctx) {",
    "  if (ctx$date >= as.Date(\"2018-01-31\")) return(0.4)",
    "  1", "}")),
  B3 = list(what = "월 인덱스 창 t >= 146 && t <= 153", lines = c(
    "overlay_expo_zz_cal_v3 <- function(H, t, ctx) {",
    "  if (t >= 146L && t <= 153L) return(0.3)",
    "  1", "}")),
  B4 = list(what = "오염 변수 yr <- as.integer(format(…, \"%Y\")); yr %in% c(2008L, 2020L)", lines = c(
    "overlay_expo_zz_cal_v4 <- function(H, t, ctx) {",
    "  yr <- as.integer(format(ctx$date, \"%Y\"))",
    "  if (yr %in% c(2008L, 2020L)) return(0.2)",
    "  1", "}")),
  B5 = list(what = "H$Date[t] > \"2020-03-31\"", lines = c(
    "overlay_expo_zz_cal_v5 <- function(H, t, ctx) {",
    "  if (H$Date[t] > \"2020-03-31\") return(0.6)",
    "  1", "}")),
  B6 = list(what = "압축 연월 \"201801\" · t > 100L", lines = c(
    "overlay_expo_zz_cal_v6 <- function(H, t, ctx) {",
    "  if (format(ctx$date, \"%Y%m\") == \"201801\") return(0)",
    "  if (t > 100L) return(0.5)",
    "  1", "}")))
for (nm in names(viol)) {
  r <- inject(sub("^B", "zz_cal_v", nm), viol[[nm]]$lines)
  if (!isTRUE(r$ok) && identical(failed_at(r), "calendar"))
    ok(sprintf("%s 검출 — %s", nm, viol[[nm]]$what)) else
    ng(sprintf("%s 미검출 — %s", nm, viol[[nm]]$what), sprintf("failed_at=%s reason=%s", failed_at(r), as.character(r$reason)))
}

cat("", fill = TRUE); cat("=== C. 스캐너 계약 ===", fill = TRUE)
s <- overlay_probe_calendar_scan("x <- 1\nif (year(ctx$date) >= 2018) e <- 0.5\n")
if (nrow(s) && any(grepl("year_fn_cmp", s$rule))) ok("C1 문자열 입력 · year(ctx$date) >= 2018 → year_fn_cmp") else ng("C1", paste(s$rule, collapse = ","))
s <- overlay_probe_calendar_scan("e <- if (t < 24L) 1 else min(1, ctx$tgt / ctx$v_now)\n")
if (!nrow(s)) ok("C2 워밍업 가드 t < 24L 는 통과") else ng("C2 오탐", paste(s$rule, collapse = ","))
s <- overlay_probe_calendar_scan("if (t == 150L) e <- 0\n")
if (nrow(s) && any(grepl("t_index_eq", s$rule))) ok("C3 t == 150L → t_index_eq") else ng("C3", paste(s$rule, collapse = ","))
s <- overlay_probe_calendar_scan("q <- stats::quantile(x, 0.2000); z <- x > 2000\n")
if (!nrow(s)) ok("C4 연도처럼 보이는 일반 숫자(0.2000 · x > 2000)는 날짜 문맥 없이 걸리지 않는다") else ng("C4 오탐", paste(s$rule, collapse = ","))

left <- list.files(ADIR, pattern = "^zz_cal_")
if (!length(left)) ok("C5 픽스처 잔여 0") else ng("C5 픽스처가 남았다", paste(left, collapse = ","))

cat("", fill = TRUE)
cat(sprintf("합계: 통과 %d · 실패 %d", PASS, FAIL), fill = TRUE)
cat(sprintf('{"test":"overlay_probe_calendar","pass":%d,"fail":%d,"total":%d}', PASS, FAIL, PASS + FAIL), fill = TRUE)
if (FAIL > 0L) quit(status = 1L)
