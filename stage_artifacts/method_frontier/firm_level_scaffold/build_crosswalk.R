#==============================================================================
# build_crosswalk.R — 사업자등록번호(bizr_no) ↔ DART 고유번호(corp_code) ↔ 종목코드(stock_code)
#
#   목적: FQ-064(국민연금 헤드카운트)·FQ-065(나라장터 정부조달) firm-level 신호를
#         상장 유니버스(K200∪KQ150)에 귀속시키기 위한 firm-identity crosswalk.
#         DART_API_KEY 보유 → data.go.kr 키 랜딩 前 '지금' 구축 가능(도훈 키 불요).
#
#   조인 경로:
#     - data.go.kr 국민연금 사업장 데이터  --(사업자등록번호 6자리 or 10자리)-->  bizr_no
#     - data.go.kr 나라장터 낙찰/계약 데이터 --(사업자등록번호 10자리 bizno)-->    bizr_no
#     - bizr_no  --(본 crosswalk)-->  corp_code(DART)  --(corpCode.xml)-->  stock_code → Ticker(Axxxxxx)
#
#   출력(stage_artifacts/method_frontier/firm_level_scaffold/):
#     firm_crosswalk.parquet   — 1행/상장사: Ticker, stock_code, corp_code, corp_name,
#                                bizr_no, bizr_no6, jurir_no, corp_cls, induty_code, est_dt
#     firm_crosswalk.json      — 동일 내용 JSON(가독)
#     crosswalk_coverage.json  — 커버리지 리포트(요청/매칭/API성공/실패)
#
#   재실행: bash 02_Infrastructure/ops/safe_run.sh Rscript <이 파일>
#   PIT: crosswalk 자체는 시점-불변 firm-identity(look-ahead 없음). 단 corp_cls(상장부)와
#        est_dt는 as-of이며, 유니버스 멤버십은 별도 PIT 스냅샷(universe_monthly)이 관장.
#==============================================================================
suppressPackageStartupMessages({
  library(httr); library(jsonlite); library(xml2); library(arrow); library(data.table)
})
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
OUT  <- file.path(ROOT, "stage_artifacts/method_frontier/firm_level_scaffold")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

# ── DART key ────────────────────────────────────────────────────────────────
.load_key <- function() {
  ln <- readLines(file.path(ROOT, ".env"), warn = FALSE)
  k  <- sub("^DART_API_KEY=", "", trimws(ln[grepl("^DART_API_KEY=", ln)]))
  if (!length(k) || nchar(k) < 10) stop("[crosswalk] DART_API_KEY 부재/부족")
  k
}
KEY <- .load_key()

# ── 1) corpCode.xml (bulk corp_code ↔ stock_code) — fresh download ───────────
fetch_corpcode <- function() {
  cat("[crosswalk] corpCode.xml 다운로드...\n")
  url <- paste0("https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key=", KEY)
  z <- tempfile(fileext = ".zip")
  r <- GET(url, write_disk(z, overwrite = TRUE), timeout(90))
  if (status_code(r) != 200) stop("[crosswalk] corpCode HTTP ", status_code(r))
  d <- tempfile(); dir.create(d); unzip(z, exdir = d)
  xp <- list.files(d, pattern = "\\.xml$", full.names = TRUE)[1]
  doc <- read_xml(xp); nd <- xml_find_all(doc, ".//list")
  dt <- data.table(
    corp_code   = xml_text(xml_find_first(nd, ".//corp_code")),
    corp_name   = xml_text(xml_find_first(nd, ".//corp_name")),
    stock_code  = xml_text(xml_find_first(nd, ".//stock_code")),
    modify_date = xml_text(xml_find_first(nd, ".//modify_date")))
  dt <- dt[nchar(stock_code) == 6]
  dt[, Ticker := paste0("A", stock_code)]
  unlink(z)
  cat(sprintf("[crosswalk] 상장 corp: %d\n", nrow(dt)))
  dt
}

# ── 2) target universe: 최근(2023+) univ==TRUE 합집합 — 현재+근미래 churn robust ─
target_tickers <- function() {
  up <- file.path(ROOT, "stage_artifacts/insider_captier_escape/universe_monthly.parquet")
  u  <- as.data.table(read_parquet(up))
  tk <- unique(u[ym >= "2023-01" & univ == TRUE, Ticker])
  cat(sprintf("[crosswalk] target 유니버스(2023+ univ 합집합): %d tickers (max ym %s)\n",
              length(tk), max(u$ym)))
  tk
}

# ── 3) 기업개황 company.json (15034604) → bizr_no ─────────────────────────────
fetch_company <- function(corp_code) {
  r <- tryCatch(GET("https://opendart.fss.or.kr/api/company.json",
                    query = list(crtfc_key = KEY, corp_code = corp_code), timeout(30)),
                error = function(e) NULL)
  if (is.null(r) || status_code(r) != 200) return(list(status = "http_fail"))
  j <- tryCatch(fromJSON(content(r, "text", encoding = "UTF-8")), error = function(e) NULL)
  if (is.null(j)) return(list(status = "parse_fail"))
  j
}

# ── main ─────────────────────────────────────────────────────────────────────
cc  <- fetch_corpcode()
tks <- target_tickers()
tgt <- cc[Ticker %in% tks]
missing_in_dart <- setdiff(tks, cc$Ticker)   # 상장이나 corpCode 미수록(신규/우선주 등)
cat(sprintf("[crosswalk] DART corp_code 매칭: %d / %d (미매칭 %d)\n",
            nrow(tgt), length(tks), length(missing_in_dart)))

rows <- vector("list", nrow(tgt)); fails <- character(0)
for (i in seq_len(nrow(tgt))) {
  ccode <- tgt$corp_code[i]
  j <- fetch_company(ccode)
  st <- if (is.null(j$status)) "no_status" else j$status
  if (!identical(st, "000")) {
    if (identical(st, "020")) { cat("[crosswalk] ★ rate_limit(020) — 중단, 부분저장\n"); break }
    fails <- c(fails, paste0(tgt$Ticker[i], ":", st)); next
  }
  rows[[i]] <- data.table(
    Ticker      = tgt$Ticker[i],
    stock_code  = tgt$stock_code[i],
    corp_code   = ccode,
    corp_name   = j$corp_name %||% tgt$corp_name[i],
    bizr_no     = j$bizr_no %||% NA_character_,
    jurir_no    = j$jurir_no %||% NA_character_,
    corp_cls    = j$corp_cls %||% NA_character_,   # Y=KOSPI, K=KOSDAQ, N=KONEX, E=기타
    induty_code = j$induty_code %||% NA_character_,
    est_dt      = j$est_dt %||% NA_character_)
  if (i %% 50 == 0) cat(sprintf("[crosswalk] ... %d/%d\n", i, nrow(tgt)))
  Sys.sleep(0.12)   # polite throttle (일일 쿼터 20k 대비 여유)
}

xw <- rbindlist(Filter(Negate(is.null), rows), fill = TRUE)
xw[, bizr_no6 := ifelse(!is.na(bizr_no) & nchar(bizr_no) >= 6, substr(bizr_no, 1, 6), NA_character_)]
setcolorder(xw, c("Ticker","stock_code","corp_code","corp_name",
                  "bizr_no","bizr_no6","jurir_no","corp_cls","induty_code","est_dt"))

write_parquet(xw, file.path(OUT, "firm_crosswalk.parquet"))
write_json(xw, file.path(OUT, "firm_crosswalk.json"), pretty = TRUE, auto_unbox = TRUE)

cov <- list(
  built_at            = as.character(Sys.time()),
  source_apis         = c("DART corpCode.xml", "DART company.json (15034604 기업개황)"),
  universe_definition = "insider_captier_escape/universe_monthly.parquet · union(univ==TRUE, ym>=2023-01)",
  target_n            = length(tks),
  matched_corpcode_n  = nrow(tgt),
  crosswalk_rows      = nrow(xw),
  bizr_no_present     = sum(!is.na(xw$bizr_no)),
  api_fail_n          = length(fails),
  missing_in_dart_n   = length(missing_in_dart),
  missing_in_dart     = head(missing_in_dart, 50),
  api_fails           = head(fails, 50),
  corp_cls_breakdown  = as.list(table(xw$corp_cls, useNA = "ifany")),
  note = paste("crosswalk는 firm-identity(시점-불변). data.go.kr 키 랜딩 시 국민연금 bizr_no",
               "및 나라장터 bizno를 이 테이블의 bizr_no(10자리)로 조인 → Ticker 귀속.",
               "국민연금 공표가 앞 6자리 마스킹이면 bizr_no6로 조인(중복 위험은 랜딩 시 실측).")
)
write_json(cov, file.path(OUT, "crosswalk_coverage.json"), pretty = TRUE, auto_unbox = TRUE)

cat(sprintf("\n[crosswalk] DONE rows=%d bizr_no=%d fail=%d missing_in_dart=%d\n",
            nrow(xw), sum(!is.na(xw$bizr_no)), length(fails), length(missing_in_dart)))
cat("[crosswalk] 저장:", OUT, "\n")
