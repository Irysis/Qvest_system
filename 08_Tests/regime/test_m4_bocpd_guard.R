# test_m4_bocpd_guard.R -- m4 BOCPD 팔 가드의 양방향 검증
#
# 배경 (2026-08-30 실측): m4 리스크 오버레이의 BOCPD 팔이 271개월 내내 **0회 발화**했다.
#   구판 가드 `bocpd_expected_runlen_lag >= 12` 는 주석에 "must observe >= 12 mo of data"
#   라는 PIT warm-up 검사로 적혀 있었으나, expected_runlen 은 관측 데이터 길이가 아니라
#   현재 런의 지속에 대한 BOCPD 사후 기대값 E[r_t|x_1:t] 다. BOCPD 는 변화점을 감지하면
#   run-length posterior 가 무너지므로 short_run_mass 가 오르는 순간 expected_runlen 이
#   내려간다 -- 구조적 음상관(rho=-0.5898). 가드가 신호를 정의상 지웠다.
#   실측: mass>=0.60 11개월 중 runlen>=12 동반 0개월 / mass>=0.80 6개월 중 0개월.
#   수리 = warm-up 을 **관측 개월 수**(행 인덱스)로 걸고, expected_runlen 은 기본 미사용.
#
# 계약 (양방향 -- 이 저장소 규약: 양성 대조 없는 계기는 방어선으로 세지 않는다):
#   A1 [양성] mass 高 + runlen 低 픽스처가 **발화한다** (구판이 죽였던 바로 그 배치)
#   A2 [양성] mass>=0.80 픽스처가 bocpd_extreme 까지 발화
#   B1 [음성] 평시(mass 低)는 미발화
#   B2 [음성] warm-up 이전 행은 mass=1.0 이라도 미발화 (2004 블록)
#   C1 warm-up 경계가 관측 개월 수로 걸린다 (경계 직전 미발화 / 직후 발화)
#   D1 [부활 차단] 소스에 결함 가드(mass 조건과 runlen>=12 의 접합)가 되살아나지 않음
#   D2 mode 스위치 정합: "mature" = 구판 재현(0 발화) / "young" = 이 패널에서 비구속
#   E1 [NA 안전] mass 또는 runlen 이 NA 인 행은 미발화
#   F1 [실패 기록 고정] 실제 패널에서 구판 가드가 0회 발화임이 재도출된다
#
# 방식: **소스의 가드 블록을 텍스트로 추출해 그대로 eval** 한다(재구현 금지 -- 재구현은
#   소스가 바뀌어도 통과하는 죽은 체크가 된다). 실행:
#   Rscript 08_Tests/regime/test_m4_bocpd_guard.R

## 루트 해석 = self 최우선 (worktree 가 main 구판을 읽지 않도록).
## normalize 계열 호출은 쓰지 않는다 -- 이 저장소는 한글 경로 취급 이력이 있고,
## 표지 파일(02_Infrastructure/config.R) 검증만으로 충분하다.
.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else "."
}, error = function(e) ".")
root <- file.path(.self, "..", "..")
if (!file.exists(file.path(root, "02_Infrastructure", "config.R")))
  root <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(root)
suppressPackageStartupMessages(library(data.table))

pass <- 0L; fail <- 0L; skip <- 0L; skips <- character(0)
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
# 전제 부재 사유는 **경로까지** 보존한다 — 조치 불가능한 보고는 결국 무시된다.
# ★러너 규약(run_all_hooks.sh:1375): skips[] 는 문자열이 아니라 **객체** 배열이고
#   {axis, reason, missing} 3키를 읽는다. 문자열 배열을 내면 러너 쪽 s.get() 이
#   AttributeError 로 죽고 그 에러가 2>/dev/null 로 삼켜져 **SKIP 목록이 통째로 사라진다**
#   (미판정이 조용해진다 = 이 저장소가 반복해서 밟은 침묵 실패). 형식을 맞춘다.
sk <- function(axis, reason, missing) {
  cat(sprintf("  [SKIP] %s -- %s (%s)\n", axis, reason, missing))
  skip <<- skip + 1L
  esc <- function(x) gsub('"', '\\\\"', x, perl = TRUE)
  skips <<- c(skips, sprintf('{"axis":"%s","reason":"%s","missing":"%s"}',
                             esc(axis), esc(reason), esc(missing)))
}
emit <- function() {
  cat(sprintf('{"test":"test_m4_bocpd_guard","pass":%d,"fail":%d,"skipped":%d,"total":%d,"skips":[%s]}\n',
              pass, fail, skip, pass + fail + skip, paste(skips, collapse = ",")))
}

SRC <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/factor_engine.R"
if (!file.exists(SRC)) {
  sk("source", "factor_engine.R 부재 -- 이 트리에 m4 엔진 소스가 없다", SRC); emit(); quit(status = 0L)
}
txt <- paste(readLines(SRC, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

## ---- 소스에서 가드 블록 추출 (재구현 금지) ----------------------------------
grab <- function(pat) {
  m <- regmatches(txt, regexpr(pat, txt, perl = TRUE))
  if (!length(m)) NULL else m
}
GUARD <- grab("(?s)out\\[, bocpd_warm :=.*?out\\[is\\.na\\(bocpd_extreme\\), bocpd_extreme := 0L\\]")
DEF_WARM <- grab("BOCPD_WARMUP_MONTHS <- [0-9]+L")
DEF_THR  <- grab("BOCPD_RUNLEN_THRESHOLD <- [0-9.]+")
DEF_MODE <- grab('BOCPD_RUNLEN_MODE <- "[a-z]+"')
if (is.null(GUARD)) {
  ng("소스에서 가드 블록 추출 실패 -- 앵커 소실(테스트가 대상을 잃음)"); emit(); quit(status = 1L)
}
if (is.null(DEF_WARM) || is.null(DEF_THR) || is.null(DEF_MODE)) {
  ng("가드 상수 3종(WARMUP/THRESHOLD/MODE) 중 일부가 소스에 없음"); emit(); quit(status = 1L)
}
ok("소스에서 가드 블록 + 상수 3종 추출 (테스트가 실코드를 실행)")

# 가드를 mode 를 바꿔가며 실행하는 러너 -- 소스 텍스트를 eval 한다
run_guard <- function(dt, mode = NULL, warm = NULL, thr = NULL) {
  e <- new.env(parent = globalenv())
  eval(parse(text = DEF_WARM), e); eval(parse(text = DEF_THR), e); eval(parse(text = DEF_MODE), e)
  if (!is.null(mode)) assign("BOCPD_RUNLEN_MODE", mode, envir = e)
  if (!is.null(warm)) assign("BOCPD_WARMUP_MONTHS", as.integer(warm), envir = e)
  if (!is.null(thr))  assign("BOCPD_RUNLEN_THRESHOLD", thr, envir = e)
  assign("out", copy(dt), envir = e)
  eval(parse(text = GUARD), e)
  get("out", envir = e)
}
# 픽스처: 실제 패널 배치를 흉내낸다(월 1행 · lag 열 이름 동일)
mk <- function(mass, runlen) data.table(
  Date = seq(as.Date("2004-02-01"), by = "month", length.out = length(mass)),
  bocpd_short_run_mass_lag = as.numeric(mass),
  bocpd_expected_runlen_lag = as.numeric(runlen))

# 상수는 문자열 긁기 대신 **평가해서** 읽는다 (sub 는 첫 매치만 지워 "12L" 이 남는다)
wm <- local({ e <- new.env(); eval(parse(text = DEF_WARM), e); get("BOCPD_WARMUP_MONTHS", e) })
stopifnot(is.numeric(wm), wm >= 0L)

## ---- A. 양성 대조 -----------------------------------------------------------
# 30개월: 앞 29개월 평시(mass 0.10, runlen 30) + 30번째에 실제 사고 배치(mass 高/runlen 低)
n <- 30L
m <- rep(0.10, n); r <- rep(30, n)
m[n] <- 0.66; r[n] <- 10.46          # 2020-06 실측값 그대로
g <- run_guard(mk(m, r))
if (g$bocpd_strong[n] == 1L)
  ok("A1 [양성] mass=0.66 & runlen=10.46 (2020-06 실측 배치) -> bocpd_strong 발화") else
  ng("A1 [양성] 실사고 배치가 발화하지 않음 -- 가드가 여전히 신호를 지운다")

m2 <- m; r2 <- r; m2[n] <- 0.85; r2[n] <- 5.4   # 2004-08 형태의 극단 배치(mass 高/runlen 低)
g2 <- run_guard(mk(m2, r2))
if (g2$bocpd_extreme[n] == 1L && g2$bocpd_strong[n] == 1L)
  ok("A2 [양성] mass=0.85 & runlen=5.4 -> bocpd_extreme + strong 동시 발화") else
  ng(sprintf("A2 [양성] extreme 미발화 (strong=%d extreme=%d)",
             g2$bocpd_strong[n], g2$bocpd_extreme[n]))

## ---- B. 음성 대조 -----------------------------------------------------------
g3 <- run_guard(mk(rep(0.10, n), rep(30, n)))
if (sum(g3$bocpd_strong) == 0L && sum(g3$bocpd_extreme) == 0L)
  ok("B1 [음성] 평시(mass=0.10) 30개월 전량 미발화") else
  ng(sprintf("B1 [음성] 평시 오발화 strong=%d extreme=%d",
             sum(g3$bocpd_strong), sum(g3$bocpd_extreme)))

# warm-up 이전은 mass=1.0 이라도 미발화 (2004 블록 재현)
g4 <- run_guard(mk(rep(1.00, n), rep(3, n)))
if (sum(g4$bocpd_strong[seq_len(wm)]) == 0L)
  ok(sprintf("B2 [음성] warm-up 이전 %d개월은 mass=1.0 이어도 미발화 (2004 블록)", wm)) else
  ng("B2 [음성] warm-up 이전 발화 -- PIT warm-up 무력")
if (sum(g4$bocpd_strong[(wm + 1L):n]) == (n - wm))
  ok("B2b [양성] warm-up 이후 동일 조건은 전량 발화 (warm-up 이 신호를 영구 삭제하지 않음)") else
  ng("B2b warm-up 이후에도 미발화 -- 가드가 과잉 차단")

## ---- C. 경계 ---------------------------------------------------------------
# 경과 = 행 인덱스 - 1. 경과 == wm 인 행이 첫 발화행이어야 한다.
first <- which(g4$bocpd_strong == 1L)[1]
if (!is.na(first) && (first - 1L) == wm)
  ok(sprintf("C1 경계 정확: 첫 발화 = 경과 %d개월째 행(index %d)", wm, first)) else
  ng(sprintf("C1 경계 어긋남: 첫 발화 index=%s (기대 %d)", first, wm + 1L))

## ---- D. 부활 차단 + mode 정합 ----------------------------------------------
if (grepl("bocpd_short_run_mass_lag >= 0\\.(60|80) &\\s*\\n\\s*bocpd_expected_runlen_lag >= 12",
          txt, perl = TRUE))
  ng("D1 [부활] 결함 가드(mass & runlen>=12 직접 접합)가 소스에 되살아났다") else
  ok("D1 [부활 차단] 결함 가드가 소스에 없음")
if (grepl("bocpd_warm", txt, fixed = TRUE) && grepl("seq_len(.N) - 1L", txt, fixed = TRUE))
  ok("D1b warm-up 이 관측 개월 수로 걸려 있음 (expected_runlen 대리 아님)") else
  ng("D1b warm-up 구현이 관측 개월 수가 아님")

# "mature" = 구판 재현. 실사고 배치에서 0 발화여야 한다(그것이 구판의 병이었다)
g5 <- run_guard(mk(m, r), mode = "mature")
if (g5$bocpd_strong[n] == 0L)
  ok('D2 mode="mature"(구판) 는 실사고 배치에서 0 발화 -- 결함 재현 성립') else
  ng('D2 mode="mature" 가 발화 -- 구판 재현 실패(결함 서술이 틀렸다는 뜻)')
g6 <- run_guard(mk(m, r), mode = "young")
if (g6$bocpd_strong[n] == 1L)
  ok('D2b mode="young"(역방향) 은 실사고 배치에서 발화 -- 이 패널에선 비구속(=off 와 동일)') else
  ng('D2b mode="young" 미발화 -- 역방향 서술과 불일치')

## ---- E. NA 안전 -------------------------------------------------------------
mn <- m; mn[n] <- NA_real_
g7 <- run_guard(mk(mn, r))
rn <- r; rn[n] <- NA_real_
g8 <- run_guard(mk(m, rn), mode = "young")
if (g7$bocpd_strong[n] == 0L && g8$bocpd_strong[n] == 0L)
  ok("E1 [NA 안전] mass NA / runlen NA(young 모드) 행 모두 미발화") else
  ng(sprintf("E1 NA 행 오발화 (mass NA=%d, runlen NA=%d)",
             g7$bocpd_strong[n], g8$bocpd_strong[n]))

## ---- F. 실제 패널에서 결함의 크기가 재도출되는가 ------------------------------
PANEL <- "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"
if (!file.exists(PANEL)) {
  sk("F", "실패 기록 재도출 불가 -- m4 패널 부재(worktree 는 코드만 갖는다)", PANEL)
} else if (!requireNamespace("arrow", quietly = TRUE)) {
  sk("F", "실패 기록 재도출 불가 -- arrow 패키지 미설치", "R package: arrow")
} else {
  # arrow 자기교착 방어 (m4_append_only.R 상단 실측과 같은 함정)
  if (identical(suppressWarnings(as.integer(Sys.getenv("ARROW_IO_THREADS", "0"))), 1L))
    Sys.setenv(ARROW_IO_THREADS = "2")
  p <- as.data.table(arrow::read_parquet(PANEL, mmap = FALSE))
  setorder(p, Date)
  pm <- p$bocpd_short_run_mass_lag; pr <- p$bocpd_expected_runlen_lag
  n60  <- sum(pm >= 0.60, na.rm = TRUE)
  n60g <- sum(pm >= 0.60 & pr >= 12, na.rm = TRUE)
  n80  <- sum(pm >= 0.80, na.rm = TRUE)
  n80g <- sum(pm >= 0.80 & pr >= 12, na.rm = TRUE)
  rho  <- suppressWarnings(cor(pm, pr, use = "complete.obs"))
  cat(sprintf("      [실측] n=%d · mass>=0.60: %d (구판 통과 %d) · mass>=0.80: %d (구판 통과 %d) · rho=%.4f\n",
              nrow(p), n60, n60g, n80, n80g, rho))
  if (n60 > 0L && n60g == 0L && n80 > 0L && n80g == 0L)
    ok(sprintf("F1 구판 가드는 실제 패널에서 0회 발화 (신호 후보 %d개월 전량 차단)", n60)) else
    ng(sprintf("F1 구판 발화수가 0 이 아님 (strong %d / extreme %d) -- 결함 서술 재검토 필요",
               n60g, n80g))
  if (!is.na(rho) && rho < 0)
    ok(sprintf("F2 mass<->runlen 구조적 음상관 재도출 (rho=%.4f < 0)", rho)) else
    ng(sprintf("F2 음상관 미재현 (rho=%s)", format(rho)))
  # 수리판이 이 패널에서 실제로 발화하는가 (계기가 살아 있는지 최종 확인)
  gg <- run_guard(data.table(bocpd_short_run_mass_lag = pm, bocpd_expected_runlen_lag = pr))
  if (sum(gg$bocpd_strong) > 0L)
    ok(sprintf("F3 수리판은 같은 패널에서 %d회 발화 (계기 생존 확인)", sum(gg$bocpd_strong))) else
    ng("F3 수리판도 0회 발화 -- 수리가 듣지 않았다")
}

cat(sprintf("\n-- test_m4_bocpd_guard: %d passed, %d failed, %d skipped --\n\n", pass, fail, skip))
emit()
if (fail > 0L) quit(status = 1L)
