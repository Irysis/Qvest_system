# =============================================================================
# run_wt004_compile.R — WT-D20260802_004 변동성 팩터 조합 (AX-001 조건부 평가)
#   단계 1/2: AST 스펙 선언 + 컴파일 (factor_db_monthly 리프, 컴파일러-소유 로드)
#
# 설계 (사전등록 — 컴파일 前 고정, 성과 조회 없음):
#   변동성 5축 (기전 상이 — 가설의 "직교 축" 후보):
#     D03_RealVol      총변동성 252d
#     D01_IdioVol      CAPM 잔차 변동성 252d (IVOL)
#     D41_Vol_of_Vol   변동성의 변동성
#     D45_Downside_Dev 하방 변동성 (semivol)
#     D55_Vol_Trend    변동성 추세 (단기vol vs 장기vol — vol-rank 동학 축)
#   + M01_Mom_12_1     Core 참조 (AX-001 mdd_complement_vs_core 비교대상)
#
#   두 배향 lane:
#     canonical  = load_month_factors Z_Score_Aligned 그대로 (C13 정본 —
#                  expanding IC 방향정렬. 실측: 5축 모두 IC>0 → "고변동 롱")
#     defensive  = AST에 MUL(leaf, -1) 구조 선언 (기전-고정 "저변동 롱").
#                  수치상 defensive 패널 = -1 × canonical 패널 (선형변환 —
#                  subsample 컴파일 parity로 검증 후 파생 사용, 전량 재컴파일 회피)
#
#   조합 규칙(사전등록): z_score_aligned_equal_weight.
#     C_ALL5 = 5축 등가중 / C_ORTH = 중복 축 제거 후 등가중.
#     중복 판정: 월별 횡단면 Spearman |rho| 평균 >= 0.8 쌍은 일반->특수 우선순위
#     (D03 > D01 > D45 > D41 > D55)에서 후순위 축 제거. **성과 무참조** (eval 단계에서
#     상관만으로 결정 — argmax 아님, selection_type=chain).
#
# 실행: Rscript -e 'source("stage_artifacts/WT_D20260802_004/run_wt004_compile.R")'
# =============================================================================
suppressPackageStartupMessages({
  library(data.table); library(arrow); library(jsonlite)
})
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
setwd(ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_D20260802_004")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(fmt, ...) cat(sprintf(paste0("[wt004c] ", fmt, "\n"), ...))

F5   <- c("D03_RealVol", "D01_IdioVol", "D41_Vol_of_Vol", "D45_Downside_Dev", "D55_Vol_Trend")
CORE <- "M01_Mom_12_1"
ALL6 <- c(F5, CORE)

# -----------------------------------------------------------------------------
# 1. AST 스펙 파일 선언 (canonical 리프 + defensive MUL(-1))
# -----------------------------------------------------------------------------
leaf_of <- function(f) list(type = "leaf", class = "FIELD",
                            source = "factor_db_monthly", field = f)
for (f in ALL6) {
  write_json(leaf_of(f), file.path(OUT, sprintf("ast_%s_canonical.json", f)),
             auto_unbox = TRUE, pretty = TRUE)
}
for (f in F5) {
  write_json(list(type = "op", op = "MUL", args = list(leaf_of(f), -1)),
             file.path(OUT, sprintf("ast_%s_defensive.json", f)),
             auto_unbox = TRUE, pretty = TRUE)
}
say("AST 스펙 %d개 선언 (canonical 6 + defensive 5)", length(ALL6) + length(F5))

# -----------------------------------------------------------------------------
# 2. 유니버스 그리드 (K200 ∪ KQ150, 월말 멤버십) — 2004-12 ~ 최신-1
# -----------------------------------------------------------------------------
RAW <- as.data.table(read_parquet(".cache/RAWDATA.parquet",
        col_select = c("Date", "Ticker", "K200", "KQ150")))
RAW[, Date := as.Date(Date)]
RAW[, ym := format(Date, "%Y-%m")]
MEND <- sort(RAW[, .(Date = max(Date)), by = ym]$Date)
SIG  <- MEND[MEND >= as.Date("2004-12-01") & MEND < max(MEND)]  # 마지막 월말은 forward 없음
UNIV <- RAW[Date %in% SIG & (K200 == TRUE | KQ150 == TRUE), .(Date, Ticker)]
say("sig months %d (%s ~ %s), 월평균 %.0f종목", length(SIG),
    as.character(min(SIG)), as.character(max(SIG)), UNIV[, .N, by = Date][, mean(N)])
rm(RAW); gc(verbose = FALSE)

# -----------------------------------------------------------------------------
# 3. canonical 6리프 병렬 컴파일 (리프 독립 — future_lapply, R 내부 병렬 의무)
# -----------------------------------------------------------------------------
suppressPackageStartupMessages(library(future.apply))
plan(multisession, workers = min(6L, max(1L, parallel::detectCores() - 1L)))
t0 <- Sys.time()
res <- future_lapply(ALL6, function(f) {
  tryCatch({
    setwd(ROOT)
    suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })
    source(file.path(ROOT, "02_Infrastructure/ast/ast_compile.R"))
    cmp <- ast_compile(file.path(OUT, sprintf("ast_%s_canonical.json", f)),
                       eval_dates = SIG, universe = UNIV,
                       manifest_out = file.path(OUT, sprintf("ast_manifest_%s_canonical.json", f)))
    write_parquet(cmp$panel, file.path(OUT, sprintf("panel_%s_canonical.parquet", f)))
    list(f = f, ok = TRUE, n = nrow(cmp$panel), nn = sum(!is.na(cmp$panel$value)),
         feats = cmp$manifest$ast_features)
  }, error = function(e) list(f = f, ok = FALSE, err = conditionMessage(e)))
}, future.seed = TRUE)
plan(sequential)
say("compile %.1f min", as.numeric(difftime(Sys.time(), t0, units = "mins")))
for (r in res) {
  if (isTRUE(r$ok)) say("  %s: %d행 non-NA %d", r$f, r$n, r$nn)
  else say("  %s: ERROR %s", r$f, r$err)
}
if (any(!sapply(res, `[[`, "ok"))) stop("[wt004c] 컴파일 실패 리프 존재 — 중단")

# -----------------------------------------------------------------------------
# 4. defensive lane parity 검증 — MUL(leaf,-1) 서브샘플 컴파일 = -1×canonical 확인
# -----------------------------------------------------------------------------
source(file.path(ROOT, "02_Infrastructure/ast/ast_compile.R"))
probe_dates <- SIG[format(SIG, "%Y-%m") %in% c("2008-11", "2015-06", "2020-03", "2024-12")]
probe_univ  <- UNIV[Date %in% probe_dates]
parity <- list()
for (f in F5) {
  cmp_d <- ast_compile(file.path(OUT, sprintf("ast_%s_defensive.json", f)),
                       eval_dates = probe_dates, universe = probe_univ,
                       manifest_out = file.path(OUT, sprintf("ast_manifest_%s_defensive.json", f)))
  can <- as.data.table(read_parquet(file.path(OUT, sprintf("panel_%s_canonical.parquet", f))))
  m <- merge(cmp_d$panel[, .(Date, Ticker, v_def = value)],
             can[, .(Date, Ticker, v_can = value)], by = c("Date", "Ticker"))
  m <- m[is.finite(v_def) & is.finite(v_can)]
  max_abs_diff <- m[, max(abs(v_def + v_can))]
  parity[[f]] <- max_abs_diff
  say("parity %s: n=%d max|def + can| = %.2e %s", f, nrow(m), max_abs_diff,
      ifelse(max_abs_diff < 1e-10, "PASS", "FAIL"))
}
if (any(unlist(parity) >= 1e-10)) stop("[wt004c] defensive parity FAIL — 파생 사용 불가")
saveRDS(list(res = res, parity = parity, SIG = SIG), file.path(OUT, "compile_meta.rds"))
say("완료 — panel_*.parquet %d개 + parity PASS. 다음: run_wt004_eval.R", length(ALL6))
