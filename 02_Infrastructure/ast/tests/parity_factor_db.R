#==============================================================================
# parity_factor_db.R — AST v1.1 Step 2 컴파일러 parity 대조 (SOT §8 검증 기준)
#
# 임무 S2d-1: 기존 팩터를 AST로 표현·컴파일해 factor DB 값과 대조.
#   - bit-parity 불요 — 정의 차이 문서화 + 횡단면 rank corr(Spearman) 실측 보고.
#   - 대상 월: 202605 · 202606 (sig_date = 해당 월의 **거래일 월말** — RAWDATA 파생.
#     2026-08-02 이전 판은 캘린더 월말 하드코딩이었고, 그것이 결함 은폐 원인이었다).
#
# 대상 3종 + 정의 차이 (사전 문서화):
#  [P1] M01_Mom_12_1 (rawdata 리프 합성):
#       엔진(compute_momentum.R:42-48) = prod(1+Ret[n-251..n-21]) - 1
#         (거래일 인덱스, NA-Ret 행 제외 후 인덱싱, n>252 요구)
#       AST = TS_LAG(TS_SUM(LOG(ADD(Ret, 1)), window=231), k=21)
#         sum(log(1+r)) 은 prod(1+r)-1 의 순증가 단조변환 → 횡단면 rank 동일 기대.
#       정의 차이: ① exp 부재(𝒪에 EXP 없음 — rank 비교로 무영향) ② NA 처리:
#         엔진은 NA행 제거 후 인덱싱 / AST frollsum 은 창 내 NA → NA (커버리지 차이)
#         ③ DB 값은 winsorize+z(z_safe) 후 Z_Score_Aligned — 단조(꼬리 클램프 동률만 영향)
#  [P2] M04_Mom_1 (rawdata 리프 합성): 엔진 = 최근 21거래일 누적수익(skip 없음)
#       AST = TS_SUM(LOG(ADD(Ret, 1)), window=21). 차이는 P1과 동일 계열.
#  [P3] V01_BM (재무 리프): 엔진 = TotalEquity/Size (compute_value.R:126-130).
#       ⚠ 정의-레벨 재합성은 현 컴파일러로 불가 — canonical provider leaf_sources 에
#       fundamental_merged 소스 부재 (S2b 범위: factor_db_monthly/daily/rawdata만).
#       → FIELD_REGISTRY_PTR 리프 passthrough parity 로 대체: load_month_factors()
#       경유 로드 → 월말 grid AS_OF 조인 배관 검증 (기대 rho = 1.0 정확).
#       fundamental 리프 소스는 leaf-source 확장 백로그로 별도 등재.
#
# Q4-수리 vintage 주석 (실측): factor_db_202605.parquet / 202606 mtime = 2026-07-02
#   (Q4 수리 이전 빌드). Q4 전기간 재빌드는 도훈 confirm 대기(SOT §3/§8 Step 1) —
#   본 parity 는 현행 신-DB(=현재 canonical 캐시) 기준. P1/P2 는 가격계(Q4 무관),
#   P3 는 passthrough(동일 소스 양변)라 Q4 재빌드 여부가 rho 에 영향 없음.
#
# 실행: cd 02_Infrastructure/ast && Rscript -e "source('tests/parity_factor_db.R')"
# 산출: tests/parity_factor_db_result.json
#==============================================================================

ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
source(file.path(ROOT, "02_Infrastructure/ast/ast_compile.R"))

# DB 측 로드용 인프라 (provider 와 동일 경로 — C15: load_month_factors 경유)
if (!exists("PROJECT_ROOT", envir = globalenv())) {
  source(file.path(ROOT, "02_Infrastructure/config.R"))
}
if (!exists("load_month_factors", mode = "function")) {
  source(file.path(ROOT, "02_Infrastructure/factor_db/factor_db_connector.R"))
}

# ⚠ 2026-08-02 수정 — eval 그리드는 **거래일 월말**이어야 한다.
#   구판은 캘린더 월말("2026-05-31" 등)을 하드코딩했는데, 그건 당시 provider 가
#   행을 라벨하던 좌표계와 **같았다** — 결함(캘린더 월말 합성 라벨)과 검사가 같은
#   좌표계에 서 있어 1개월 stale 이 상쇄되고 rho=1.0 이 나왔다. 실제 소비자(WT 드라이버·
#   canonical_screen_bt)는 RAWDATA 거래일 월말을 sig_date 로 쓴다. 그 그리드로 검사한다.
#   (거래말<캘린더말 = 실측 94/259 월. 상세: 08_Tests/contract_regression/test_ast_monthly_asof_label.R)
EVAL_DATES <- local({
  rp <- file.path(ROOT, ".cache/RAWDATA.parquet")
  if (!file.exists(rp)) stop("[parity] RAWDATA.parquet 부재 — 거래일 월말 그리드 해석 불가")
  rd <- data.table::as.data.table(arrow::read_parquet(rp, col_select = "Date"))
  rd[, Date := as.Date(Date)]
  me <- sort(rd[, .(d = max(Date)), by = .(ym = format(Date, "%Y%m"))]$d)
  me[format(me, "%Y%m") %in% c("202605", "202606")]
})
stopifnot(length(EVAL_DATES) == 2L)

leaf_ret <- list(type = "leaf", class = "FIELD", source = "rawdata", field = "Ret")
log1p_ret <- list(type = "op", op = "LOG", args = list(
  list(type = "op", op = "ADD", args = list(leaf_ret, list(type = "const", value = 1)))
))

AST_M01 <- list(type = "op", op = "TS_LAG", params = list(k = 21L), args = list(
  list(type = "op", op = "TS_SUM", params = list(window = 231L), args = list(log1p_ret))
))
AST_M04 <- list(type = "op", op = "TS_SUM", params = list(window = 21L), args = list(log1p_ret))
AST_V01 <- list(type = "leaf", class = "FIELD_REGISTRY_PTR",
                source = "factor_db_monthly", field = "V01_BM")

cat("[parity] ast_compile 3종 시작:", format(Sys.time()), "\n")

compile_one <- function(ast, tag) {
  cat(sprintf("[parity] compile %s ...\n", tag))
  r <- ast_compile(ast, eval_dates = EVAL_DATES, final_max_staleness_days = 10L)
  r$panel
}

pan_m01 <- compile_one(AST_M01, "M01(AST)")
pan_m04 <- compile_one(AST_M04, "M04(AST)")
pan_v01 <- compile_one(AST_V01, "V01(passthrough)")

# DB 측: 동일 sig_date 로 load_month_factors (C15 경유)
db_side <- function(sig_d, fnames) {
  dt <- load_month_factors(sig_d, factor_names = fnames)
  as.data.table(dt)
}

spearman_cmp <- function(ast_panel, db_dt, fname, sig_d) {
  a <- ast_panel[Date == sig_d & !is.na(value), .(Ticker, ast_value = value)]
  b <- db_dt[Factor_Name == fname & !is.na(Z_Score_Aligned), .(Ticker, db_z = Z_Score_Aligned)]
  m <- merge(a, b, by = "Ticker")
  rho <- if (nrow(m) >= 3L) suppressWarnings(
    cor(m$ast_value, m$db_z, method = "spearman", use = "complete.obs")) else NA_real_
  list(factor = fname, sig_date = as.character(sig_d),
       n_ast = nrow(a), n_db = nrow(b), n_common = nrow(m),
       spearman = round(rho, 6))
}

rows <- list()
for (sig_d in as.list(EVAL_DATES)) {
  db <- db_side(sig_d, c("M01_Mom_12_1", "M04_Mom_1", "V01_BM"))
  rows[[length(rows) + 1L]] <- spearman_cmp(pan_m01, db, "M01_Mom_12_1", sig_d)
  rows[[length(rows) + 1L]] <- spearman_cmp(pan_m04, db, "M04_Mom_1", sig_d)
  rows[[length(rows) + 1L]] <- spearman_cmp(pan_v01, db, "V01_BM", sig_d)
}

db_vintage <- lapply(c("202605", "202606"), function(ym) {
  fp <- file.path(ROOT, ".cache/factor_db", paste0("factor_db_", ym, ".parquet"))
  list(month = ym, mtime = as.character(file.mtime(fp)))
})

result <- list(
  schema = "ast_parity/v1",
  ran_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  purpose = "AST v1.1 Step 2 컴파일러 parity (SOT §8 검증 기준 — S2d-1)",
  metric = "cross-sectional Spearman rank corr (AST raw signal vs DB Z_Score_Aligned)",
  db_vintage = db_vintage,
  q4_note = paste("202605/202606 parquet = 2026-07-02 빌드(Q4 수리 이전 vintage).",
                  "Q4 전기간 재빌드는 도훈 confirm 대기 — P1/P2 가격계·P3 passthrough 라 rho 무영향."),
  definition_gaps = list(
    "M01/M04: AST=sum(log(1+r)) 단조변환(EXP 부재) — rank 동일; NA창 처리 차이로 커버리지 차이; DB측 winsorize+z 꼬리 동률",
    "M04 rho 음수 = C13 방향정렬(align_factor_direction ic_sign=-1, KR 단기모멘텀=반전팩터)의 기대 부호 — AST raw 대비 DB Z_Score_Aligned 부호 반전. |rho| 로 해석",
    "V01_BM: 정의-레벨 재합성 불가(canonical provider 에 fundamental 리프 소스 부재) — passthrough parity 로 배관만 검증. leaf-source 확장 백로그 등재(06_Registry/ast_operator_backlog.json BL-001)"
  ),
  rows = rows
)

out_path <- file.path(ROOT, "02_Infrastructure/ast/tests/parity_factor_db_result.json")
jsonlite::write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE, null = "null")
cat("[parity] 결과 저장:", out_path, "\n")
for (r in rows) {
  cat(sprintf("[parity] %s @ %s: rho=%s (common n=%d, ast n=%d, db n=%d)\n",
              r$factor, r$sig_date, format(r$spearman), r$n_common, r$n_ast, r$n_db))
}
cat("[parity] done:", format(Sys.time()), "\n")
