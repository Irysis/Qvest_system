#!/usr/bin/env Rscript
#==============================================================================
# test_factor_combinable.R — 결합용 팩터 뷰(02_Infrastructure/factor_db/factor_combinable.R) 계약 검사
#   decision_register FACTOR-COMBINABLE-VIEW-20261109 · FACTOR-DIRECTION-TWO-VIEWS-20261109 · 설정 06_Registry/factor_combinable.json
#   P 순수 함수(순위 [−1,1] · 부호 대칭 · 부분집합 재순위 · 별칭 · 계열 · 저장 원값 되돌리기) · L 합성 저장본 읽기(v1.1 = 저장 원값 방향 ·
#   registry = s_reg · ic_asof = s_ic · defensive = s_def · 재순위 · 결측 · 별칭 · 계열 · PIT · 대체 금지 · 부호 결측 · 옛 저장본 거부) ·
#   M 위반 주입 6종(동순위 규칙 · 재순위 제거 · PIT 가드 제거 · 부호 열 바꾸기 · 방어 결측 빼기 제거 · 저장 부호 되돌리기 제거)
#==============================================================================
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", Sys.getenv("CLAUDE_PROJECT_DIR", "")))
if (!nzchar(ROOT)) stop("QM_ROOT 미설정")
FCF <- file.path(ROOT, "02_Infrastructure/factor_db/factor_combinable.R")
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) }
  else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, detail)) }
}
thr <- function(expr) inherits(tryCatch({ force(expr); NULL }, error = function(e) e), "error")
load_fc <- function(text = NULL) {
  e <- new.env(parent = globalenv()); f <- FCF
  if (!is.null(text)) { f <- tempfile(fileext = ".R"); writeLines(text, f, useBytes = TRUE) }
  sys.source(f, envir = e, keep.source = FALSE); e
}
mutant <- function(from, to) {
  txt <- paste(readLines(FCF, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  n <- lengths(regmatches(txt, gregexpr(from, txt, fixed = TRUE)))
  if (n != 1L) stop("돌연변이 치환 대상이 정확히 1곳이 아니다(", n, "): ", from)
  load_fc(sub(from, to, txt, fixed = TRUE))
}
G <- load_fc()

cat("=== P. 순수 함수 ===\n")
chk("P1 순위 → [−1, 1] · 결측 유지", isTRUE(all.equal(G$fc_rank_pm1(c(3, 1, 2, NA)), c(1, -1, 0, NA))))
chk("P1b 동순위 평균 · 값 하나 = 0 · 전부 결측 = NA", isTRUE(all.equal(G$fc_rank_pm1(c(1, 1, 2)), c(-0.5, -0.5, 1))) &&
      identical(G$fc_rank_pm1(c(NA, 5)), c(NA, 0)) && all(is.na(G$fc_rank_pm1(c(NA_real_, NA_real_)))))
set.seed(1109); x <- round(rnorm(500), 1)                                    # 반올림 = 동순위가 많다
chk("P2 부호 대칭 — 값을 뒤집으면 정확히 −1 배(동순위 포함) · 방향 = 부호표 곱의 근거", isTRUE(all.equal(G$fc_rank_pm1(-x), -G$fc_rank_pm1(x))))
S <- sample(500, 200)
chk("P3 부분집합 재순위 = 원값 부분집합 순위(저장값은 단조 변환)", isTRUE(all.equal(G$fc_rank_pm1(G$fc_rank_pm1(x)[S]), G$fc_rank_pm1(x[S]))))
rv <- function(z) ifelse(z == "F3_alias", "F3", ifelse(z == "C_alias", "C", z))
chk("P4 별칭 — 정본이 있을 때만 뺀다(정본 없는 별칭은 남긴다 · 이름 안 바꿈)",
    identical(G$fc_alias_drop(c("F3", "F3_alias", "B", "C_alias"), rv), c("F3", "B", "C_alias")))
W0 <- data.table(Ticker = c("a", "b", "c"), F1 = c(1, NA, -1), F2 = c(0, NA, NA), F3 = c(NA, NA, NA))
fs <- G$fc_family_scores(W0, c(F1 = "value", F2 = "value", F3 = "quality"))
chk("P5 계열 평균 = 값 있는 것의 평균 · 전부 결측이면 NA", isTRUE(all.equal(fs$value, c(0.5, NA, -1))) && all(is.na(fs$quality)))
# 접근자 정렬값 = 저장값 × 부호 ÷ sd(양수) → 저장 원값 순위로 정확히 되돌아온다(부호 −1 · 동순위 포함)
al <- -x / sd(x)
chk("P6 저장 원값 되돌리기 — fc_to_stored(정렬값, −1) = fc_rank_pm1(원값) · +1 은 그대로",
    isTRUE(all.equal(G$fc_to_stored(al, -1L), G$fc_rank_pm1(x))) && isTRUE(all.equal(G$fc_to_stored(x / 2, 1L), G$fc_rank_pm1(x))) &&
      thr(G$fc_to_stored(x, 0L)))

cat("=== L. 합성 저장본 읽기(fc_load_month · v1.1 저장 원값 방향) ===\n")
TD <- file.path(tempdir(), sprintf("fc_test_%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
cfg <- G$fc_config(ROOT); sc <- as.numeric(cfg$storage$value_scale)
chk("L0 설정 — direction 선택지에 defensive · 기본값은 선택지 안", all(c("ic_asof", "registry", "defensive") %in% cfg$direction$options) &&
      cfg$direction$default %in% cfg$direction$options)
set.seed(20261109); n <- 40L; tk <- sprintf("A%05d", 1:n)
raw <- data.table(Ticker = tk, F1 = rnorm(n), F2 = rnorm(n), F3 = rnorm(n))
raw[sample(n, 6), F2 := NA]
raw[, F3_alias := F3]
FN <- c("F1", "F2", "F3", "F3_alias")
st <- copy(raw)[, (FN) := lapply(.SD, G$fc_rank_pm1), .SDcols = FN]             # 저장 = 저장 원값 순위
enc <- copy(st)[, (FN) := lapply(.SD, function(v) as.integer(round(v * sc))), .SDcols = FN]
write_parquet(arrow_table(enc)$cast(do.call(arrow::schema, c(list(Ticker = utf8()), setNames(rep(list(int16()), 4), FN)))),
              file.path(TD, "fc_201006.parquet"))
# 부호: F1 s_reg + · s_ic − · 방어 없음 | F2 s_reg − · s_ic − · s_def + | F3 + · + · s_def − | F3_alias + · + · 방어 없음
SG <- data.table(ym = "201006", asof = "2010-06-30", Factor_Name = FN,
                 s_reg = c(1L, -1L, 1L, 1L), s_ic = c(-1L, -1L, 1L, 1L), src_ic = "ic", s_def = c(NA_integer_, 1L, -1L, NA_integer_))
write_parquet(arrow_table(SG), file.path(TD, "fc_signs.parquet"))
write_meta <- function(dir, stored = "stored_raw_value")
  writeLines(toJSON(list(schema = "factor_combinable_meta_v1", builder = "test", value_scale = sc, stored_direction = stored,
                         months = data.table(ym = "201006", asof = "2010-06-30", size = 1, mtime = "x", n_tickers = n, n_factors = 4L)),
                    auto_unbox = TRUE), file.path(dir, "fc_meta.json"))
write_meta(TD)
REG <- list(F1 = list(direction = "higher_better", category = "value"), F2 = list(direction = "lower_better", category = "value"),
            F3 = list(direction = "higher_better", category = "quality"),
            F3_alias = list(direction = "higher_better", category = "quality", dedup = list(role = "alias", canonical = "F3")))
ld <- function(env = G, ...) env$fc_load_month(..., root = ROOT, dir = TD, registry = REG, resolve = rv)
r <- ld(sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE)
chk("L1 registry = 저장값 × s_reg — F1 그대로 · F2 뒤집힘", isTRUE(all.equal(r$panel$F1, st$F1, tolerance = 1e-4)) &&
      isTRUE(all.equal(r$panel$F2, -st$F2, tolerance = 1e-4)))
r2 <- ld(sig_date = "2010-06-30", direction = "ic_asof", missing = "na", dedup = FALSE)
chk("L2 ic_asof = 저장값 × s_ic — F1 · F2 둘 다 뒤집힘 · F3 그대로",
    isTRUE(all.equal(r2$panel$F1, -st$F1, tolerance = 1e-4)) && isTRUE(all.equal(r2$panel$F2, -st$F2, tolerance = 1e-4)) &&
      isTRUE(all.equal(r2$panel$F3, st$F3, tolerance = 1e-4)))
rd <- ld(sig_date = "2010-06-30", direction = "defensive", missing = "na", dedup = FALSE)
chk("L2b defensive = 저장값 × s_def — F2 그대로 · F3 뒤집힘 · 방어 방향 없는 F1 · F3_alias 는 빠지고 info 에 적힌다",
    isTRUE(all.equal(rd$panel$F2, st$F2, tolerance = 1e-4)) && isTRUE(all.equal(rd$panel$F3, -st$F3, tolerance = 1e-4)) &&
      !any(c("F1", "F3_alias") %in% names(rd$panel)) && identical(rd$info$dropped_no_defensive, c("F1", "F3_alias")))
chk("L2c [위반 주입] defensive 로 방어 방향 없는 팩터를 명시하면 멈춘다",
    thr(ld(sig_date = "2010-06-30", direction = "defensive", factors = c("F1", "F2"), dedup = FALSE)))
sub_t <- tk[seq(1, n, 2)]
r3 <- ld(sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE, tickers = sub_t)
chk("L3 tickers 안에서 다시 순위 = 원값 부분집합의 순위", isTRUE(all.equal(r3$panel$F1, G$fc_rank_pm1(raw[Ticker %in% sub_t]$F1), tolerance = 1e-4)) &&
      identical(range(r3$panel$F1), c(-1, 1)))
r4 <- ld(sig_date = "2010-06-30", direction = "registry", missing = "zero", dedup = FALSE)
chk("L4 결측 'zero' = 0(횡단면 중앙값) · 'na' = 결측 유지 · n_avail", sum(is.na(r$panel$F2)) == 6L && sum(r4$panel$F2 == 0) >= 6L &&
      !anyNA(r4$panel$F2) && identical(as.integer(sort(unique(r4$n_avail$n_avail))), c(3L, 4L)))
r5 <- ld(sig_date = "2010-06-30", direction = "registry")
chk("L5 별칭 접기(기본) — F3 가 있어 F3_alias 를 뺀다 · dedup = FALSE 면 남긴다", !("F3_alias" %in% names(r5$panel)) && ("F3_alias" %in% names(r$panel)))
chk("L6 계열 평균 — value = F1 · F2(registry 방향) 중 값 있는 것의 평균",
    isTRUE(all.equal(r$families$value, ifelse(is.na(st$F2), st$F1, (st$F1 - st$F2) / 2), tolerance = 1e-4)))
chk("L7 [위반 주입] 신호일이 그 달 as-of 보다 이르면 멈춘다(PIT)", thr(ld(sig_date = "2010-06-15", direction = "registry")))
chk("L8 [위반 주입] 저장본에 없는 달이면 멈춘다(이전 달로 대체 안 함)", thr(ld(sig_date = "2010-07-31", direction = "registry")))
TD9 <- paste0(TD, "_l9"); dir.create(TD9, showWarnings = FALSE)
for (f in c("fc_201006.parquet", "fc_meta.json")) file.copy(file.path(TD, f), file.path(TD9, f))
write_parquet(arrow_table(SG[Factor_Name != "F2"]), file.path(TD9, "fc_signs.parquet"))
chk("L9 [위반 주입] 부호표에 팩터가 없으면 멈춘다(지어내지 않는다 · 방향 무관)",
    thr(G$fc_load_month("2010-06-30", direction = "ic_asof", dedup = FALSE, root = ROOT, dir = TD9, registry = REG, resolve = rv)) &&
      thr(G$fc_load_month("2010-06-30", direction = "registry", dedup = FALSE, root = ROOT, dir = TD9, registry = REG, resolve = rv)))
TD10 <- paste0(TD, "_l10"); dir.create(TD10, showWarnings = FALSE)
for (f in c("fc_201006.parquet", "fc_signs.parquet")) file.copy(file.path(TD, f), file.path(TD10, f))
write_meta(TD10, stored = "registry")
chk("L10 [위반 주입] 옛 저장본(stored_direction = registry · v1.0)은 읽지 않는다(방향이 섞였을 수 있다)",
    thr(G$fc_load_month("2010-06-30", direction = "registry", dedup = FALSE, root = ROOT, dir = TD10, registry = REG, resolve = rv)))

cat("=== K. 빌드 잠금(일일 체인 [6e] 증분 · 진행기 --full 이 겹치지 않게) ===\n")
lock_check <- function(env) {
  TK <- file.path(tempdir(), sprintf("fc_lock_%d_%d", Sys.getpid(), sample.int(1e6, 1))); dir.create(TK)
  on.exit(unlink(TK, recursive = TRUE), add = TRUE)
  l1 <- env$fc_lock(TK); l2 <- env$fc_lock(TK)
  held <- !is.null(l1) && is.null(l2)
  Sys.setFileTime(file.path(TK, ".build.lock"), Sys.time() - 7 * 3600)      # 7시간 묵은 잠금 = 죽은 빌드
  l3 <- env$fc_lock(TK)
  list(held = held, stale = !is.null(l3))
}
k <- lock_check(G)
chk("K1 잠금을 쥔 동안 두 번째 빌드는 건너뛴다(NULL)", isTRUE(k$held))
chk("K2 6시간 넘게 묵은 잠금은 넘겨받는다(죽은 빌드)", isTRUE(k$stale))
# 읽기 전용(R) 속성 잠금 — OneDrive 동기화 폴더가 수 초 안에 붙인다(11-10 실측: R unlink 가 폴더를 조용히 남겨 다음 빌드가 모두 건너뜀)
ro <- function(p) system2("attrib", c("+r", shQuote(gsub("/", "\\\\", p))), stdout = FALSE, stderr = FALSE)
lock_ro_check <- function(env) {
  TK <- file.path(tempdir(), sprintf("fc_lockro_%d_%d", Sys.getpid(), sample.int(1e6, 1))); dir.create(TK)
  on.exit({ Sys.chmod(list.dirs(TK), "777", use_umask = FALSE); unlink(TK, recursive = TRUE) }, add = TRUE)
  P <- file.path(TK, "premise"); dir.create(P); ro(P); unlink(P, recursive = TRUE)
  premise <- dir.exists(P)                                                  # 전제 재현: 그냥 unlink 는 R 폴더를 남긴다
  l1 <- env$fc_lock(TK); ro(l1); suppressWarnings(env$fc_release(l1))
  released <- !dir.exists(l1)
  if (dir.exists(l1)) { Sys.chmod(l1, "777", use_umask = FALSE); unlink(l1, recursive = TRUE) }
  l2 <- env$fc_lock(TK); ro(l2); Sys.setFileTime(l2, Sys.time() - 7 * 3600)
  l3 <- suppressWarnings(env$fc_lock(TK))
  list(premise = premise, released = released, stale_ro = !is.null(l3))
}
kr <- lock_ro_check(G)
chk("K3 [전제] 읽기 전용 폴더는 그냥 unlink 로 남는다(이 검사가 공허하지 않다)", isTRUE(kr$premise))
chk("K4 읽기 전용이 된 잠금도 빌드 끝에 지운다", isTRUE(kr$released))
chk("K5 읽기 전용인 묵은 잠금도 넘겨받는다", isTRUE(kr$stale_ro))

cat("=== M. 위반 주입(검사가 살아 있나) ===\n")
M1 <- mutant('ties.method = "average"', 'ties.method = "first"')
chk("M1 동순위 규칙을 바꾸면 부호 대칭이 깨진다(P2 가 잡는다)", !isTRUE(all.equal(M1$fc_rank_pm1(-x), -M1$fc_rank_pm1(x))))
M2 <- mutant("    for (c in fc) set(W, j = c, value = fc_rank_pm1(W[[c]]))\n", "")
r3m <- ld(env = M2, sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE, tickers = sub_t)
chk("M2 부분집합 재순위를 지우면 L3 이 깨진다(L3 이 잡는다)", !isTRUE(all.equal(r3m$panel$F1, G$fc_rank_pm1(raw[Ticker %in% sub_t]$F1), tolerance = 1e-4)))
M3 <- mutant('  if (sig < asof) stop(sprintf("[fc] 신호일 %s 가 그 달 as-of %s 보다 이르다 — 월말 신호일로 부르라(PIT)", sig, asof))\n', "")
chk("M3 PIT 가드를 지우면 이른 신호일이 통과한다(L7 이 잡는다)", !thr(ld(env = M3, sig_date = "2010-06-15", direction = "registry")))
M4 <- mutant('registry = "s_reg", ic_asof = "s_ic"', 'registry = "s_ic", ic_asof = "s_ic"')
r1m <- ld(env = M4, sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE)
chk("M4 registry 가 s_ic 를 곱하면 F1 이 잘못 뒤집힌다(L1 이 잡는다)", !isTRUE(all.equal(r1m$panel$F1, st$F1, tolerance = 1e-4)))
M5 <- mutant("    no_def <- sort(names(s)[is.na(s)])\n", "")
chk("M5 방어 결측 빼기를 지우면 defensive 읽기가 부호 결측으로 멈춘다(L2b 가 잡는다)",
    thr(ld(env = M5, sig_date = "2010-06-30", direction = "defensive", missing = "na", dedup = FALSE)))
M6 <- mutant("  fc_rank_pm1(z_aligned) * s0\n", "  fc_rank_pm1(z_aligned)\n")
chk("M6 저장 부호 되돌리기를 지우면 정렬 부호 −1 팩터가 거꾸로 저장된다(P6 이 잡는다)",
    !isTRUE(all.equal(M6$fc_to_stored(al, -1L), G$fc_rank_pm1(x))))
M7 <- mutant("    if (is.finite(age) && age < max_age_h) return(NULL)\n", "")
chk("M7 잠금 확인을 지우면 두 빌드가 겹친다(K1 이 잡는다)", !isTRUE(lock_check(M7)$held))
M8 <- mutant('  if (dir.exists(p)) { Sys.chmod(p, "777", use_umask = FALSE); unlink(p, recursive = TRUE) }\n', "")
k8 <- lock_ro_check(M8)
chk("M8 읽기 전용 풀기를 지우면 잠금이 남고 묵은 잠금도 못 넘겨받는다(K4 · K5 가 잡는다)", !isTRUE(k8$released) && !isTRUE(k8$stale_ro))

unlink(c(TD, TD9, TD10), recursive = TRUE)
cat(sprintf("\n== factor_combinable: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(toJSON(list(test = "factor_combinable", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(save = "no", status = 1L)
