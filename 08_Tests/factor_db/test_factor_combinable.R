#!/usr/bin/env Rscript
#==============================================================================
# test_factor_combinable.R — 결합용 팩터 뷰(02_Infrastructure/factor_db/factor_combinable.R) 계약 검사
#   decision_register FACTOR-COMBINABLE-VIEW-20261109 · 설정 06_Registry/factor_combinable.json
#   P 순수 함수(순위 [−1,1] · 부호 대칭 · 부분집합 재순위 · 별칭 · 계열) · L 합성 저장본 읽기(방향 · 재순위 · 결측 · 별칭 ·
#   계열 · PIT · 대체 금지 · 부호 결측) · M 위반 주입 4종(동순위 규칙 · 재순위 제거 · PIT 가드 제거 · 부호 잘못 고르기)
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

cat("=== L. 합성 저장본 읽기(fc_load_month) ===\n")
TD <- file.path(tempdir(), sprintf("fc_test_%d", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
cfg <- G$fc_config(ROOT); sc <- as.numeric(cfg$storage$value_scale)
set.seed(20261109); n <- 40L; tk <- sprintf("A%05d", 1:n)
raw <- data.table(Ticker = tk, F1 = rnorm(n), F2 = rnorm(n), F3 = rnorm(n))
raw[sample(n, 6), F2 := NA]
raw[, F3_alias := F3]
st <- copy(raw)[, (c("F1", "F2", "F3", "F3_alias")) := lapply(.SD, G$fc_rank_pm1), .SDcols = c("F1", "F2", "F3", "F3_alias")]
enc <- copy(st)[, (c("F1", "F2", "F3", "F3_alias")) := lapply(.SD, function(v) as.integer(round(v * sc))), .SDcols = c("F1", "F2", "F3", "F3_alias")]
write_parquet(arrow_table(enc)$cast(do.call(arrow::schema, c(list(Ticker = utf8()), setNames(rep(list(int16()), 4), c("F1", "F2", "F3", "F3_alias"))))),
              file.path(TD, "fc_201006.parquet"))
SG <- data.table(ym = "201006", asof = "2010-06-30", Factor_Name = c("F1", "F2", "F3", "F3_alias"),
                 s_reg = c(1L, -1L, 1L, 1L), s_ic = c(-1L, -1L, 1L, 1L), src_ic = "ic")
SG[, s_rel := s_ic * s_reg]                                                  # F1 = −1(IC 가 등록부와 반대) · F2 = +1(둘 다 −1)
write_parquet(arrow_table(SG), file.path(TD, "fc_signs.parquet"))
writeLines(toJSON(list(schema = "factor_combinable_meta_v1", builder = "test", value_scale = sc,
                       months = data.table(ym = "201006", asof = "2010-06-30", size = 1, mtime = "x", n_tickers = n, n_factors = 4L)),
                  auto_unbox = TRUE), file.path(TD, "fc_meta.json"))
REG <- list(F1 = list(direction = "higher_better", category = "value"), F2 = list(direction = "lower_better", category = "value"),
            F3 = list(direction = "higher_better", category = "quality"),
            F3_alias = list(direction = "higher_better", category = "quality", dedup = list(role = "alias", canonical = "F3")))
ld <- function(env = G, ...) env$fc_load_month(..., root = ROOT, dir = TD, registry = REG, resolve = rv)
r <- ld(sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE)
chk("L1 registry 방향 = 저장값(÷ 10000)", isTRUE(all.equal(r$panel$F1, st$F1, tolerance = 1e-4)) && isTRUE(all.equal(r$panel$F2, st$F2, tolerance = 1e-4)))
r2 <- ld(sig_date = "2010-06-30", direction = "ic_asof", missing = "na", dedup = FALSE)
chk("L2 ic_asof = s_rel 곱 — F1 은 뒤집히고(s_rel −1) F2 는 그대로(s_reg · s_ic 모두 −1)",
    isTRUE(all.equal(r2$panel$F1, -st$F1, tolerance = 1e-4)) && isTRUE(all.equal(r2$panel$F2, st$F2, tolerance = 1e-4)))
sub_t <- tk[seq(1, n, 2)]
r3 <- ld(sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE, tickers = sub_t)
chk("L3 tickers 안에서 다시 순위 = 원값 부분집합의 순위", isTRUE(all.equal(r3$panel$F1, G$fc_rank_pm1(raw[Ticker %in% sub_t]$F1), tolerance = 1e-4)) &&
      identical(range(r3$panel$F1), c(-1, 1)))
r4 <- ld(sig_date = "2010-06-30", direction = "registry", missing = "zero", dedup = FALSE)
chk("L4 결측 'zero' = 0(횡단면 중앙값) · 'na' = 결측 유지 · n_avail", sum(is.na(r$panel$F2)) == 6L && sum(r4$panel$F2 == 0) >= 6L &&
      !anyNA(r4$panel$F2) && identical(as.integer(sort(unique(r4$n_avail$n_avail))), c(3L, 4L)))
r5 <- ld(sig_date = "2010-06-30", direction = "registry")
chk("L5 별칭 접기(기본) — F3 가 있어 F3_alias 를 뺀다 · dedup = FALSE 면 남긴다", !("F3_alias" %in% names(r5$panel)) && ("F3_alias" %in% names(r$panel)))
chk("L6 계열 평균 — value = F1 · F2 중 값 있는 것의 평균", isTRUE(all.equal(r$families$value, ifelse(is.na(st$F2), st$F1, (st$F1 + st$F2) / 2), tolerance = 1e-4)))
chk("L7 [위반 주입] 신호일이 그 달 as-of 보다 이르면 멈춘다(PIT)", thr(ld(sig_date = "2010-06-15", direction = "registry")))
chk("L8 [위반 주입] 저장본에 없는 달이면 멈춘다(이전 달로 대체 안 함)", thr(ld(sig_date = "2010-07-31", direction = "registry")))
TD9 <- paste0(TD, "_l9"); dir.create(TD9, showWarnings = FALSE)
for (f in c("fc_201006.parquet", "fc_meta.json")) file.copy(file.path(TD, f), file.path(TD9, f))
write_parquet(arrow_table(SG[Factor_Name != "F2"]), file.path(TD9, "fc_signs.parquet"))
chk("L9 [위반 주입] ic_asof 인데 부호표에 팩터가 없으면 멈춘다(지어내지 않는다)",
    thr(G$fc_load_month("2010-06-30", direction = "ic_asof", dedup = FALSE, root = ROOT, dir = TD9, registry = REG, resolve = rv)))

cat("=== M. 위반 주입(검사가 살아 있나) ===\n")
M1 <- mutant('ties.method = "average"', 'ties.method = "first"')
chk("M1 동순위 규칙을 바꾸면 부호 대칭이 깨진다(P2 가 잡는다)", !isTRUE(all.equal(M1$fc_rank_pm1(-x), -M1$fc_rank_pm1(x))))
M2 <- mutant("    for (c in fc) set(W, j = c, value = fc_rank_pm1(W[[c]]))\n", "")
r3m <- ld(env = M2, sig_date = "2010-06-30", direction = "registry", missing = "na", dedup = FALSE, tickers = sub_t)
chk("M2 부분집합 재순위를 지우면 L3 이 깨진다(L3 이 잡는다)", !isTRUE(all.equal(r3m$panel$F1, G$fc_rank_pm1(raw[Ticker %in% sub_t]$F1), tolerance = 1e-4)))
M3 <- mutant('  if (sig < asof) stop(sprintf("[fc] 신호일 %s 가 그 달 as-of %s 보다 이르다 — 월말 신호일로 부르라(PIT)", sig, asof))\n', "")
chk("M3 PIT 가드를 지우면 이른 신호일이 통과한다(L7 이 잡는다)", !thr(ld(env = M3, sig_date = "2010-06-15", direction = "registry")))
M4 <- mutant("setNames(s_rel, Factor_Name)", "setNames(s_ic, Factor_Name)")
r2m <- ld(env = M4, sig_date = "2010-06-30", direction = "ic_asof", missing = "na", dedup = FALSE)
chk("M4 s_rel 대신 s_ic 를 곱하면 F2 가 잘못 뒤집힌다(L2 가 잡는다)", !isTRUE(all.equal(r2m$panel$F2, st$F2, tolerance = 1e-4)))

unlink(c(TD, TD9), recursive = TRUE)
cat(sprintf("\n== factor_combinable: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(toJSON(list(test = "factor_combinable", pass = PASS, fail = FAIL, total = PASS + FAIL), auto_unbox = TRUE), "\n", sep = "")
if (FAIL > 0L) quit(save = "no", status = 1L)
