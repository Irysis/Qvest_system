# =============================================================================
# fe_score_composite.R — score-level 팩터 컴포짓 러너 어댑터 (v9.1 §7-S3a, E-6)
# =============================================================================
# 역할: 멤버 factor engine 여러 개를 격리 실행해 각자의 Score 를 시점별 z 로 표준화하고,
#       사용가능 멤버만의 가중평균으로 composite Score 를 만든 뒤 상위 25종 상한을
#       FACTORS$N 에 박는다. 계약 본체는 02_Infrastructure/contracts/score_composite.R.
#
# 원칙:
#   - 결합은 **score 층에서만**. return/weight 층 결합은 실보유가 25 를 넘는다
#     (L-484: 4-sleeve return-blend → 실보유 52~80종 → Judge A→B 강등).
#   - 멤버 support 불일치는 결측 유지로 처리한다. **0 으로 채워 "중립 신호"로 위장하지 않는다.**
#     n_members < COMPOSITE_MIN_MEMBERS 인 (Date,Ticker) 는 제외된다.
#   - 멤버 엔진의 N 컬럼은 폐기한다. 종목수는 이 어댑터가 마지막에 결정한다.
#   - overlay·grade hurdle·market timing·stop-loss 는 여기서 구현하지 않는다.
#
# 환경변수:
#   COMPOSITE_MEMBERS      필수. 멤버 engine 경로 CSV (절대/프로젝트 상대/alpha_search 상대)
#   COMPOSITE_WEIGHTS      선택. COMPOSITE_MEMBERS 와 같은 길이의 non-negative 가중
#   COMPOSITE_MIN_MEMBERS  선택. 기본 2
#   COMPOSITE_TOP_N        선택. 기본 25 — ★내부에서 min(25L, ·) 로 클램프되어 25 초과 불가
#
# 출력: FACTORS(Date, Ticker, Score, N)
#   소비 지점 = backtest_harness.R:933-937(N → n_hold_eff) + :965(head 절단).
#   _top25 엔진 3종이 259개월 전부 정확히 25 로 실증한 경로다.
#
# 실행: 신규 백테 러너를 만들지 않는다 —
#   run_alpha_search(name, idea, factor_engine_path=".../fe_score_composite.R",
#                    n_holdings=25L, weight_method="equal", deep=FALSE)
# =============================================================================

stopifnot(exists("RAWDATA"), is.data.table(RAWDATA))

.SC_ROOT <- local({
  cands <- c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(),
             "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
  cands <- cands[nzchar(cands)]
  hit <- cands[dir.exists(file.path(cands, "02_Infrastructure"))]
  if (!length(hit)) stop("[fe_score_composite] project root 미발견 (QM_ROOT 확인)")
  hit[1]
})

local({
  cp <- file.path(.SC_ROOT, "02_Infrastructure", "contracts", "score_composite.R")
  if (!file.exists(cp)) stop("[fe_score_composite] 계약 부재: ", cp)
  if (!exists("sc_combine_scores", mode = "function")) source(cp)
})

# ---- 멤버 목록 ---------------------------------------------------------------
.SC_MEMBER_STR <- Sys.getenv("COMPOSITE_MEMBERS", "")
.SC_MEMBERS <- trimws(strsplit(.SC_MEMBER_STR, ",", fixed = TRUE)[[1]])
.SC_MEMBERS <- unique(.SC_MEMBERS[nzchar(.SC_MEMBERS)])
if (length(.SC_MEMBERS) < 2L) {
  stop("[fe_score_composite] COMPOSITE_MEMBERS 미설정/부족 — 멤버 engine 경로 2개 이상 CSV 필요")
}

.sc_resolve <- function(p) {
  cands <- c(p, file.path(.SC_ROOT, p),
             file.path(.SC_ROOT, "02_Infrastructure", "alpha_search", p),
             file.path(.SC_ROOT, "02_Infrastructure", "alpha_search", basename(p)))
  hit <- cands[file.exists(cands)]
  if (!length(hit)) stop("[fe_score_composite] 멤버 engine 경로 해석 실패: ", p)
  hit[1]
}
.SC_PATHS <- vapply(.SC_MEMBERS, .sc_resolve, character(1), USE.NAMES = FALSE)
names(.SC_PATHS) <- sub("\\.R$", "", basename(.SC_MEMBERS))

# ---- 가중 ------------------------------------------------------------------
.SC_WEIGHT_STR <- Sys.getenv("COMPOSITE_WEIGHTS", "")
if (nzchar(.SC_WEIGHT_STR)) {
  .SC_WEIGHTS <- suppressWarnings(as.numeric(trimws(strsplit(.SC_WEIGHT_STR, ",", fixed = TRUE)[[1]])))
  if (length(.SC_WEIGHTS) != length(.SC_PATHS) ||
      any(!is.finite(.SC_WEIGHTS)) || any(.SC_WEIGHTS < 0) || !any(.SC_WEIGHTS > 0)) {
    stop("[fe_score_composite] COMPOSITE_WEIGHTS 는 COMPOSITE_MEMBERS 와 같은 길이의 non-negative numeric 이어야 함")
  }
} else {
  .SC_WEIGHTS <- rep(1, length(.SC_PATHS))
}

.SC_MINM <- suppressWarnings(as.integer(Sys.getenv("COMPOSITE_MIN_MEMBERS", "")))
if (is.na(.SC_MINM) || .SC_MINM < 1L) .SC_MINM <- 2L
.SC_MINM <- min(.SC_MINM, length(.SC_PATHS))

.TOPN <- suppressWarnings(as.integer(Sys.getenv("COMPOSITE_TOP_N", "")))
if (is.na(.TOPN) || .TOPN < 1L) .TOPN <- 25L

# ---- 멤버 수확 (격리 실행 — 각자 RAWDATA copy) ------------------------------
.SC_EXTRA <- if (exists("BM_DT")) list(BM_DT = BM_DT) else list()
.sc_members <- vector("list", length(.SC_PATHS))
names(.sc_members) <- names(.SC_PATHS)
for (i in seq_along(.SC_PATHS)) {
  .sc_members[[i]] <- sc_harvest_member(.SC_PATHS[i], RAWDATA, extra_globals = .SC_EXTRA)
  cat(sprintf("[fe_score_composite] member %-38s rows=%7d | dates=%4d | tickers=%4d\n",
              names(.SC_PATHS)[i], nrow(.sc_members[[i]]),
              uniqueN(.sc_members[[i]]$Date), uniqueN(.sc_members[[i]]$Ticker)))
  gc(verbose = FALSE)
}

# ---- 결합 → 상한 -------------------------------------------------------------
.sc_comp <- sc_combine_scores(.sc_members, weights = .SC_WEIGHTS, min_members = .SC_MINM)
.sc_nmb  <- attr(.sc_comp, "n_members_by_date")
.sc_drop <- attr(.sc_comp, "dropped_below_min_members")

# ★마지막 방어선 — 25 초과를 구조적으로 불가능하게 한다(E-5 고정 축 우선).
FACTORS <- sc_cap_top_n(.sc_comp, top_n = min(25L, .TOPN))[, .(Date, Ticker, Score, N)]

stopifnot(is.data.table(FACTORS), nrow(FACTORS) > 0L, max(FACTORS$N) <= 25L)

cat(sprintf(paste0("[fe_score_composite] members=%s | weights=%s | min_members=%d | top_n=%d\n",
                   "[fe_score_composite] rows=%d | signal dates=%d | tickers=%d | ",
                   "n_members mean=%.2f (min %d / max %d) | min_members 미달 제외 %d행 | N max=%d\n"),
            paste(names(.SC_PATHS), collapse = ","),
            paste(round(.SC_WEIGHTS, 3), collapse = ","), .SC_MINM, min(25L, .TOPN),
            nrow(FACTORS), uniqueN(FACTORS$Date), uniqueN(FACTORS$Ticker),
            mean(.sc_nmb$n_members_mean), min(.sc_nmb$n_members_min), max(.sc_nmb$n_members_max),
            .sc_drop, max(FACTORS$N)))
