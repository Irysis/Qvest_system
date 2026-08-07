# ============================================================================
# repair_rawdata_bmret_from_benchmark.R
#   RAWDATA.parquet::BM_Ret 을 정본 benchmark.parquet::BM_Ret 으로 국소 정정
# ----------------------------------------------------------------------------
# 신설 2026-08-02 (Q-Lead 야간 라운드).
#
# ## 배경 (실측)
# 두 캐시의 BM_Ret 은 독립 생성 경로를 갖는다:
#   · krx_build_rawdata.R:223  BM_Ret := BM_Close / shift(BM_Close) - 1   (KRX 종가 자체계산)
#   · incremental_update_file.R:181  merge(raw, bm[, .(Date, BM_Ret)])    (benchmark 조인)
# 2026-08-02 적발: 2026-07 의 8일이 갈렸고 4일은 RAWDATA 가 **정확히 0**
#   (07-06/21/22/28). 07-28 은 benchmark -11.55% 인데 RAWDATA 0 — 폭락일 벤치 소실.
#   월 누적 RAWDATA -17.70% vs benchmark -23.63% = 5.93%p.
#   1990-01~2026-06 전 8,990일은 diff=0 → **국소 오염**.
# 정본 = benchmark.parquet (2026-07 KOSPI200 폭락 실측 정합, Naver 패처 복구분).
#
# ## 안전 원칙 (2026-07-11 rawdata 4월 소실 사고 계승)
#  - **full-rebuild 금지**. BM_Ret 컬럼의 *지정 구간만* 갱신하는 in-place update.
#  - 백업 필수. 행수·유니버스 행수·Ret 컬럼·대상 구간 밖 값은 **불변이어야 한다**(가드).
#  - 가드 위반 시 write 하지 않고 중단.
#  - 기본 dry-run. 실제 쓰기는 apply=TRUE 명시 필요.
#
# ## 사용
#   Rscript 02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R            # dry-run
#   Rscript 02_Infrastructure/data/repair_rawdata_bmret_from_benchmark.R --apply    # 실제 쓰기
# ============================================================================
suppressWarnings(suppressMessages({library(arrow); library(data.table)}))

args  <- commandArgs(trailingOnly = TRUE)
APPLY <- any(args %in% c("--apply", "apply", "TRUE"))

RAW_P   <- ".cache/RAWDATA.parquet"
BENCH_P <- ".cache/benchmark.parquet"
BACKUP  <- sprintf(".cache/rawdata_pre_bmret_fix_%s.parquet", format(Sys.Date(), "%Y%m%d"))

stopifnot(file.exists(RAW_P), file.exists(BENCH_P))
cat(sprintf("[repair] mode = %s\n", if (APPLY) "APPLY (실제 쓰기)" else "DRY-RUN (검증만)"))

b <- as.data.table(read_parquet(BENCH_P))[, .(Date, bm_true = BM_Ret)]
r <- as.data.table(read_parquet(RAW_P))
n0 <- nrow(r)
cat(sprintf("[repair] RAWDATA rows = %s · cols = %d\n", format(n0, big.mark=","), ncol(r)))

# ── 대상 구간 = 두 소스가 실제로 갈린 날짜만 (전체 덮어쓰기 금지) ─────────────
u <- unique(r[, .(Date, BM_Ret)])
cmp <- merge(u, b, by = "Date", all = FALSE)
cmp[, diff := BM_Ret - bm_true]
target <- cmp[!is.na(diff) & abs(diff) > 1e-9]
setorder(target, Date)

# ── 방향 게이트 (2026-08-08 신설) ─────────────────────────────────────────────
#  이 스크립트는 이름부터 방향이 박혀 있다(rawdata ← benchmark). 그런데 **오염 측은
#  사건마다, 심지어 같은 사건 안에서도 날짜마다 다르다**:
#    · 2026-07-27 = benchmark 오염(스케일 단절 -88.5%)  ← 이 방향으로 고치면 정상값이 파괴됨
#    · 2026-08-05 = RAWDATA 0-위장                      ← 이 방향이 맞음
#    · 1990-01-05 = benchmark 첫 행(직전일 없음) 경계값  ← 결함 아님. 덮어쓰면 RAWDATA 에
#      **0-위장을 주입**하게 된다(고치려던 그 결함을 스스로 만듦)
#  ∴ 정합 감시기의 **날짜별 판정**(repair_directions)에서 RAWDATA 가 오염 측인 날짜만 남긴다.
#  판정 불가/반대 방향은 여기서 손대지 않는다 — 그건 다른 수리의 소관이다.
PAR_R <- "02_Infrastructure/validation/benchmark_source_parity.R"   # 이 스크립트는 프로젝트 루트에서 실행된다(상대경로 규약, RAW_P/BENCH_P 와 동일)
if (nrow(target) > 0L && file.exists(PAR_R)) {
  suppressWarnings(suppressMessages(source(PAR_R)))
  par <- try(benchmark_source_parity(), silent = TRUE)
  if (!inherits(par, "try-error") && is.data.frame(par$repair_directions)) {
    rd <- as.data.table(par$repair_directions)
    allow <- rd[contaminated == "RAWDATA::BM_Ret"]$Date
    dropped <- target[!(Date %in% allow)]
    if (nrow(dropped)) {
      cat(sprintf("[repair] ★방향 게이트: %d일 제외 (RAWDATA 가 오염 측이 아님)\n", nrow(dropped)))
      print(merge(dropped[, .(Date)], rd[, .(Date, contaminated, evidence)],
                  by = "Date", all.x = TRUE))
    }
    target <- target[Date %in% allow]
  } else {
    cat("[repair] ★정합 감시기 판정 실패 — 방향 미확인 상태에서 쓰지 않는다. 중단.\n")
    quit(status = 1L)
  }
} else if (nrow(target) > 0L) {
  cat("[repair] ★정합 감시기 부재 — 방향 판정 불가. 중단.\n"); quit(status = 1L)
}

cat(sprintf("[repair] 정정 대상 날짜 = %d일\n", nrow(target)))
if (nrow(target) == 0L) { cat("[repair] 정정할 것이 없습니다 — 종료.\n"); quit(status = 0L) }
print(target[, .(Date, rawdata = BM_Ret, benchmark = bm_true, diff)])

# 사전 스냅샷 (가드 비교용)
pre_rows_by_date <- r[Date %in% target$Date, .N, by = Date][order(Date)]
pre_ret_sum      <- suppressWarnings(sum(r$Ret, na.rm = TRUE))
pre_outside_bm   <- suppressWarnings(sum(r[!(Date %in% target$Date)]$BM_Ret, na.rm = TRUE))
pre_maxdate      <- max(r$Date, na.rm = TRUE)

# ── 국소 갱신: 대상 날짜의 BM_Ret 만 정본값으로 ───────────────────────────────
fix_map <- target[, .(Date, bm_true)]
r[fix_map, on = "Date", BM_Ret := i.bm_true]

# ── 가드 (하나라도 어긋나면 쓰지 않는다) ─────────────────────────────────────
g <- list()
g$rows_unchanged     <- (nrow(r) == n0)
post_rows_by_date    <- r[Date %in% target$Date, .N, by = Date][order(Date)]
g$rows_by_date_same  <- identical(pre_rows_by_date$N, post_rows_by_date$N)
g$ret_untouched      <- isTRUE(all.equal(pre_ret_sum, suppressWarnings(sum(r$Ret, na.rm = TRUE))))
g$outside_untouched  <- isTRUE(all.equal(pre_outside_bm,
                          suppressWarnings(sum(r[!(Date %in% target$Date)]$BM_Ret, na.rm = TRUE))))
g$maxdate_same       <- identical(pre_maxdate, max(r$Date, na.rm = TRUE))
chk <- merge(unique(r[Date %in% target$Date, .(Date, BM_Ret)]), fix_map, by = "Date")
g$applied_exactly    <- (nrow(chk) == nrow(fix_map)) &&
                        isTRUE(all.equal(chk$BM_Ret, chk$bm_true))

cat("\n[repair] 가드:\n")
for (k in names(g)) cat(sprintf("   %-20s : %s\n", k, if (isTRUE(g[[k]])) "PASS" else "FAIL"))
if (!all(vapply(g, isTRUE, logical(1)))) {
  cat("\n[repair] ★가드 FAIL — 쓰지 않고 중단합니다.\n"); quit(status = 1L)
}

if (!APPLY) {
  cat("\n[repair] DRY-RUN 통과. 실제 적용은 --apply 로 재실행하세요.\n")
  quit(status = 0L)
}

# ── 백업 후 원자적 교체 ──────────────────────────────────────────────────────
if (!file.exists(BACKUP)) {
  file.copy(RAW_P, BACKUP, overwrite = FALSE)
  cat(sprintf("[repair] 백업 생성: %s\n", BACKUP))
} else cat(sprintf("[repair] 백업 이미 존재(보존): %s\n", BACKUP))

tmp <- paste0(RAW_P, ".tmp")
write_parquet(r, tmp)
ok <- file.rename(tmp, RAW_P)
if (!ok) {
  unlink(tmp)
  cat("[repair] ★rename 실패 — 원본 유지(파일이 다른 프로세스에서 열려 있을 수 있음). 재시도하세요.\n")
  quit(status = 1L)
}
cat("[repair] 적용 완료.\n")

# ── 사후 정합 재검증 ─────────────────────────────────────────────────────────
source("02_Infrastructure/validation/benchmark_source_parity.R")
res <- benchmark_source_parity()
cat(sprintf("[repair] 사후 정합: %s — %s\n", res$severity, res$note))
if (!identical(res$severity, "OK"))
  cat("[repair] ★잔여 불일치 존재 — 위 note 확인 필요.\n")
