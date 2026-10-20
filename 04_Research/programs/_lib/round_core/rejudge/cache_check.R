## 캐시 · 메모 결과 동일 실증(무거움 — 원자료 적재 · MC8) — 속도 조치 채택 조건(PERFORMANCE.md '결과가 바뀌는 최적화는 쓰지 않는다')
##   ① 원자료 디스크 메모(rc_raw_load disk) = mc_load_raw 와 같은 표인가 · 적재 시간
##   ② MC8 카드 입력 해시 캐시(rc_mc_card_cached) — 새로 계산 vs 캐시 적중(다른 경로 · 다른 strategy_id 의 같은 내용 사본) = 같은 JSON(시각 · 경로 · id 제외) · 시간
##   ③ 진단 패킷 MC8 메모(rc_mc_memo_install) — 같은 사본 패킷 두 번(두 번째 적중) = 바이트 동일(created_at 제외) · 시간
##   ④ ta_load_market 메모 — 같은 RX0 의 β 짝 사본 두 k(같은 보유 종목) = 두 번째 적중 · 패킷 = 메모 없이 만든 패킷과 바이트 동일
## 사용: RC_CORE_ROOT=<코어 저장소> Rscript cache_check.R <루트(계약 · .cache)> <칸 산출물 디렉터리> <칸 사양(루트 상대)> <행동 카드 설정(루트 상대)> <출력 디렉터리>
a <- commandArgs(trailingOnly = TRUE)
ROOT <- gsub("\\\\", "/", a[1]); ART <- gsub("\\\\", "/", a[2]); SPEC <- a[3]; BCF <- a[4]; OUT <- gsub("\\\\", "/", a[5])
WT <- gsub("\\\\", "/", Sys.getenv("RC_CORE_ROOT")); Sys.setenv(QM_ROOT = ROOT, CLAUDE_PROJECT_DIR = ROOT); setwd(ROOT)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
source(file.path(WT, "04_Research/programs/_lib/round_core/v1/load.R"))
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
E <- rc_deps(ROOT); BCFG <- E$bc_cfg(ROOT, path = file.path(ROOT, BCF))
tm <- function(expr) { t0 <- Sys.time(); v <- force(expr); list(v = v, s = as.numeric(difftime(Sys.time(), t0, units = "secs"))) }
strip <- function(x, drop_top = c("created_at", "strategy_id")) { for (k in drop_top) x[[k]] <- NULL
  if (!is.null(x$controls$spec$source_dir)) x$controls$spec$source_dir <- NULL
  if (!is.null(x$provenance)) { x$provenance$source_dir <- NULL; x$provenance$artifact <- NULL }
  as.character(toJSON(x, auto_unbox = TRUE, null = "null", na = "null", digits = NA, Date = "ISO8601")) }
R <- list()
## ① 원자료
r1 <- tm(mc_load_raw(ROOT, from = "1999-11-01", hygiene = TRUE))
.RCM$raw_key <- NULL; r2 <- tm(rc_raw_load(ROOT, disk = TRUE))                    # 첫 호출 = 계산 + 디스크 쓰기
.RCM$raw_key <- NULL; r3 <- tm(rc_raw_load(ROOT, disk = TRUE))                    # 둘째 = 디스크 읽기
raw <- r3$v
R$raw <- list(mc_load_raw_seconds = r1$s, first_seconds = r2$s, disk_hit_seconds = r3$s,
              same_as_contract = isTRUE(all.equal(as.data.frame(r1$v), as.data.frame(r3$v), check.attributes = FALSE)) && identical(names(r1$v), names(r3$v)),
              rows = nrow(r3$v))
rm(r1, r2); invisible(gc(FALSE))
## ② MC8 카드 — 같은 내용의 다른 경로 사본(이름 · id 다름)으로 적중 확인
c1 <- tm(rc_mc_card_cached(ART, ROOT, raw, BCFG))                                 # 첫 = 계약 mc_card 계산 + 저장(= 새로 계산한 값)
c0 <- c1
cp <- file.path(OUT, "card_copy"); dir.create(cp, showWarnings = FALSE)
for (f in list.files(ART)) if (!dir.exists(file.path(ART, f))) file.copy(file.path(ART, f), cp, overwrite = TRUE)
pr <- fread(file.path(cp, "03_period_returns.csv")); if ("strategy_id" %in% names(pr)) { pr[, strategy_id := "OTHER_ROUND_RX0"]; fwrite(pr, file.path(cp, "03_period_returns.csv")) }
c2 <- tm(rc_mc_card_cached(cp, ROOT, raw, BCFG))                                  # 적중(다른 경로 · 다른 id)
c3 <- tm(mc_card(cp, root = ROOT, raw = raw, bcfg = BCFG))                        # 그 사본을 새로 계산한 정답
R$mc8_card <- list(fresh_seconds = c3$s, first_cached_seconds = c1$s, hit_seconds = c2$s, hits = .RCM$card_hits %||% 0L, misses = .RCM$card_miss %||% 0L,
                   same_hit_vs_fresh_copy = identical(strip(c2$v, "created_at"), strip(c3$v, "created_at")),
                   hit_keeps_copy_id = identical(c2$v$strategy_id, c3$v$strategy_id), hit_source_dir = identical(c2$v$controls$spec$source_dir, c3$v$controls$spec$source_dir))
## ③ · ④ 진단 패킷 — β 짝 사본 두 k · 메모 없음 대 메모(ta · MC8) · β 짝 전체 사본 대 최소 사본 · 공통 창 전체 사본 대 최소 사본(메모 설치 전)
X <- list(root = ROOT, env = list(E = E, BCFG_L = BCFG, raw = raw))
b1 <- file.path(OUT, "beta_k1"); b2 <- file.path(OUT, "beta_k2"); b1f <- file.path(OUT, "beta_k1_full")
rc_beta_scaled_copy(ART, b1, 0.8, mark = TRUE, minimal = TRUE); rc_beta_scaled_copy(ART, b2, 0.7, mark = TRUE, minimal = TRUE)
rc_beta_scaled_copy(ART, b1f, 0.8, mark = TRUE, minimal = FALSE)
p_plain1 <- tm(rc_pk_build(X, SPEC, b1, file.path(OUT, "pk_plain1"))); p_plain2 <- tm(rc_pk_build(X, SPEC, b2, file.path(OUT, "pk_plain2")))
p_full1 <- tm(rc_pk_build(X, SPEC, b1f, file.path(OUT, "pk_full1")))
R$beta_copy <- list(files_full = length(list.files(b1f)), files_minimal = length(list.files(b1)), seconds = c(full = p_full1$s, minimal = p_plain1$s),
                    same_packet = identical(strip(p_full1$v, "created_at"), strip(p_plain1$v, "created_at")))
pr0 <- fread(file.path(ART, "03_period_returns.csv")); st <- sort(as.Date(pr0$date))[floor(nrow(pr0) / 3)]
tf <- file.path(OUT, "trim_full"); tmn <- file.path(OUT, "trim_min")
rc_trim_artifacts(ART, tf, st, mark = TRUE, minimal = FALSE); rc_trim_artifacts(ART, tmn, st, mark = TRUE, minimal = TRUE)
q1 <- tm(rc_pk_build(X, SPEC, tf, file.path(OUT, "pk_trim_full"))); q2 <- tm(rc_pk_build(X, SPEC, tmn, file.path(OUT, "pk_trim_min")))
R$trim <- list(start = format(st), files_full = length(list.files(tf)), files_min = length(list.files(tmn)), seconds = c(q1$s, q2$s),
               same_packet = identical(strip(q1$v, "created_at"), strip(q2$v, "created_at")))
rc_memo_install(E); rc_mc_memo_install(E, ROOT)
p_m1 <- tm(rc_pk_build(X, SPEC, b1, file.path(OUT, "pk_memo1"))); p_m2 <- tm(rc_pk_build(X, SPEC, b2, file.path(OUT, "pk_memo2")))
p_m1b <- tm(rc_pk_build(X, SPEC, b1, file.path(OUT, "pk_memo1b")))               # MC8 메모 적중(같은 사본)
R$packet <- list(plain_seconds = c(p_plain1$s, p_plain2$s), memo_seconds = c(p_m1$s, p_m2$s), memo_repeat_seconds = p_m1b$s,
                 ta_hits = .RCM$ta_hits %||% 0L, ta_miss = .RCM$ta_miss %||% 0L, mc_hits = .RCM$mc_hits %||% 0L, mc_miss = .RCM$mc_miss %||% 0L,
                 same_k1 = identical(strip(p_plain1$v, "created_at"), strip(p_m1$v, "created_at")), same_k2 = identical(strip(p_plain2$v, "created_at"), strip(p_m2$v, "created_at")),
                 same_repeat = identical(strip(p_m1$v, "created_at"), strip(p_m1b$v, "created_at")))
writeLines(toJSON(R, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = NA), file.path(OUT, "cache_check.json"), useBytes = TRUE)
cat(toJSON(R, auto_unbox = TRUE, pretty = TRUE, digits = 4), "\n")
