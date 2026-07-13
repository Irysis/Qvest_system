## ============================================================================
## filing_delay_watch.R — 월간 monitoring 입력: 현 북 보유종목 사업보고서 제출지연 감시
## (task #61 배선, 2026-07-13 — R24(WT-D20260713_008) "극단 지각제출 = 부실 조기경보 지문"
##  지식의 유일 in-envelope 소비면 = ⑤ monitoring. 선례 kalman_beta_drift.R(#56) 구조 승계)
## book·전략 무변경 — monitoring 입력 확장만. book_state/weights/배포 파라미터 무수정.
## DART API 호출 절대 금지 (크롤 쿼터 = insider 백필 전용) — 전 재료 로컬 아카이브만.
##
## 지표 (사전 고정 — R24 frozen 로직 재사용, 재발명 금지):
##   delay_d  = rcept_dt(최초 제출일) − 법정기한
##              법정기한 = 12월 결산: (fy+1)-03-31 (Dec-FYE + 90d, R22 F-B/R24 prereg FROZEN)
##                         비-12월 결산: 결산월 말일 + 90d (일반화, 라벨 표기 — R24 상속 노이즈:
##                         주말/공휴일 기한연장 미반영 = attenuating, frozen)
##   최초 제출일 = (stock, fy)별 사업보고서 rows 중 min(rcept_dt) — [기재정정] 정정본은
##              원제출일로 붕괴 (지각 판정은 원제출 기준)
##
## 경보 규칙 (사전 고정 — 문턱/윈도우 sweep 금지):
##   WARN: delay_d > 0 AND delay_d >= 2일
##     문턱 2일 = R24 census 실측 고정값: 677-유니버스 역사 8,145 에피소드(fy2009..2023) 중
##       late(delay>0) 1,105건 분포의 top-decile bar = quantile(delay_d | delay_d>0, 0.90, type=7) = 2
##       (전 에피소드 p90 = 1일 = '임의지각' — R24 실측서 희석·기각(lift 1.23, firmBoot CI∋1) → 불채택.
##        per-fy rank top-decile(wd_strict)은 당해 fy 횡단면 미완결로 라이브 계산 불가 → 고정 절대문턱.
##        맥락: wd_strict 29에피소드 delay 중앙값 8일·범위 1..183일)
##   경보 톤 = "역사 기저율 낮음 · 위생 경보": R24 size-tier 분해 실측 — 중·대형 극단지각
##     15에피소드(mid 6 + large 9)는 12M 내 심각사건(상폐/관리/불성실) 0건. 신호는 소형주 국한.
##     자동조치 없음 — 도훈 판단 재료. 텔레그램 발송 없음 (Q-Lead가 monitoring_report 경유 수집).
##   EXPECTED_FY_MISSING: 최신 결산기말이 456일(12M+90d)보다 과거 = 최신 사업보고서가 아카이브에
##     부재 — '아카이브 갭'인지 '실제 미제출'인지 API 없이는 판별 불가(정직 라벨, warn-loud).
##   ARCHIVE STALE: 소비 아카이브 전체 최신 rcept_dt가 13개월 이상 과거 → STALE warn-loud
##     (경보 침묵을 신선도 문제와 구분).
##
## 재료 (전부 로컬 — R24 census(01_census.R)가 소비한 동일 경로):
##   lineage A: stage_artifacts/WT_D20260711_002/filings_inventory.parquet (fy필드 보유, R24 primary
##              — 단 fy2009..2023 · 최신 rcept 2024-04-29 = 단독으론 STALE)
##   lineage B: stage_artifacts/WT-D20260710_005/disc_ck/*.csv (list 아카이브, fy는 report_nm
##              "(YYYY.MM)" 파싱 — R24 census §C 소비 경로. 2026-07-08까지 신선. 별도 계보 라벨)
##   보유: 05_Production/.../20260701_noLayer4_weights_cap_0p20.csv (read-only 소비)
##
## 실행: 월간 monitoring agent가 source 패턴으로 실행
##   cd 02_Infrastructure/reports && Rscript -e 'source("filing_delay_watch.R")'
## 산출: qepm/observability/filing_delay_watch_latest.json + 월 아카이브 json + 콘솔 요약
## 규율: 단일스레드 · arrow io(2) · OneDrive 쓰기 temp-rename · 05_Production read-only 소비.
## ============================================================================
Sys.setenv(ARROW_IO_THREADS = "2")
suppressWarnings(suppressMessages({
  library(arrow); library(data.table); library(jsonlite)
}))
setDTthreads(1)
try(arrow::set_io_thread_count(2L), silent = TRUE)

ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
## 현행 배포 보유 (book_state.json::live 배포와 동일 — PG2 리밸 시 이 상수만 최신 weights csv로 교체)
HOLDINGS_CSV <- file.path(ROOT, "05_Production/2.Factor_Model/2-3.STR_1715_on_M4_R05_noLayer4_PG2/02_holdings_universe/20260701_noLayer4_weights_cap_0p20.csv")  # read-only
INV_PARQUET  <- file.path(ROOT, "stage_artifacts/WT_D20260711_002/filings_inventory.parquet")   # lineage A
DISC_DIR     <- file.path(ROOT, "stage_artifacts/WT-D20260710_005/disc_ck")                     # lineage B
CENSUS_RDS   <- file.path(ROOT, "stage_artifacts/WT_D20260713_008/census.rds")                  # 문턱 provenance soft-check용
OUT_DIR      <- file.path(ROOT, "qepm/observability")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

## 사전 고정 파라미터 — sweep/조정 금지 (변경은 도훈 mandate 필요)
THRESH_DELAY_D     <- 2L    # R24 census 실측 고정 (677-유니버스 late-분포 p90, 상단 header 참조)
HOLDING_STALE_DAYS <- 456L  # 12개월(366) + 법정 90일 — 최신 결산기말이 이보다 과거면 EXPECTED_FY_MISSING
ARCHIVE_STALE_M    <- 13L   # 아카이브 최신 rcept_dt 13개월 이상 과거 = STALE

check_date <- Sys.Date()
d2date <- function(x) as.Date(as.character(x), "%Y%m%d")
mdiff  <- function(a, b) (as.integer(format(a, "%Y")) * 12L + as.integer(format(a, "%m"))) -
                         (as.integer(format(b, "%Y")) * 12L + as.integer(format(b, "%m")))
eom    <- function(y, m) { d <- as.Date(sprintf("%d-%02d-01", y + (m == 12L), ifelse(m == 12L, 1L, m + 1L))); d - 1L }
## 법정기한 (R24 frozen): 12월 결산 = (fy+1)-03-31 정확 재사용 / 비-12월 = 결산월말 + 90d (일반화)
deadline_of <- function(fy, fye_m) fifelse(fye_m == 12L,
                                           as.Date(sprintf("%d-03-31", fy + 1L)),
                                           eom(fy, fye_m) + 90L)

## ---- 1. 현 북 보유종목 로드 (read-only) -----------------------------------
H <- fread(HOLDINGS_CSV)
n_zero_w <- H[Ticker != "CASH" & Weight <= 0, .N]
hold <- H[Ticker != "CASH" & Weight > 0, .(Ticker, Name, Weight)]
hold[, sc := sub("^A", "", Ticker)]
cat(sprintf("[load] 보유 equity(w>0) %d종목 + CASH (w=0 제외 %d행)  file=%s\n",
            nrow(hold), n_zero_w, basename(HOLDINGS_CSV)))

## ---- 2. lineage A: filings_inventory (R24 primary — fy 필드 보유) ---------
inv <- as.data.table(read_parquet(INV_PARQUET))
inv <- inv[grepl("사업보고서", report_nm)]
inv[, sc := sub("^A", "", Ticker)]
inv[, rc := d2date(rcept_dt)]
invA_max_rc <- max(inv$rc, na.rm = TRUE)
A <- inv[sc %in% hold$sc,
         .(rcept_orig = min(rc, na.rm = TRUE)), by = .(sc, fy)]
A[, fye_m := 12L]                      # inventory 계보 = Dec-FYE 가정 (R22/R24 frozen)
A[, lineage := "A_filings_inventory"]

## ---- 3. lineage B: disc_ck list 아카이브 (fy = report_nm "(YYYY.MM)" 파싱) --
fs <- list.files(DISC_DIR, pattern = "[.]csv$", full.names = TRUE)
DK <- rbindlist(lapply(fs, function(f) tryCatch(
  fread(f, colClasses = list(character = c("stock_code", "rcept_no")),
        select = c("stock_code", "report_nm", "rcept_dt")),
  error = function(e) NULL)), fill = TRUE)
DK[, stock_code := sprintf("%06d", as.integer(stock_code))]
DK <- DK[stock_code %in% hold$sc]
DK[, rnt := trimws(report_nm)]
## 진짜 연차 사업보고서만: "(YYYY.MM)" 토큰 필수 + 첨부/정정예고/해외신고류 제외
##  (census §C 필터 + 강화: A034730 "해외증권거래소등에신고한사업보고서등의국내신고" 류 배제)
DK <- DK[grepl("사업보고서\\s*\\(20[0-9]{2}[.][0-9]{2}\\)", rnt) &
         !grepl("첨부|정정예고|국내신고|해외", rnt)]
DK[, fy    := as.integer(sub(".*\\((20[0-9]{2})[.][0-9]{2}\\).*", "\\1", rnt))]
DK[, fye_m := as.integer(sub(".*\\(20[0-9]{2}[.]([0-9]{2})\\).*", "\\1", rnt))]
DK[, rc := d2date(rcept_dt)]
invB_max_rc <- if (nrow(DK)) max(DK$rc, na.rm = TRUE) else as.Date(NA)
B <- DK[, .(rcept_orig = min(rc, na.rm = TRUE), fye_m = fye_m[which.min(rc)]),
        by = .(sc = stock_code, fy)]
B[, lineage := "B_disc_ck"]
cat(sprintf("[load] lineage A rows(보유교집합)=%d (max rcept %s) | lineage B rows=%d (max rcept %s)\n",
            nrow(A), invA_max_rc, nrow(B), invB_max_rc))

## ---- 4. 보유별 최신 fy 판정 + 지연 계산 (fy 충돌 시 원제출일 min 병합) ------
AB <- rbindlist(list(A, B), use.names = TRUE)
AB <- AB[, .(rcept_orig = min(rcept_orig), fye_m = fye_m[which.min(rcept_orig)],
             lineage = paste(sort(unique(lineage)), collapse = "+")), by = .(sc, fy)]
latest <- AB[, .SD[which.max(fy)], by = sc]
latest[, deadline := deadline_of(fy, fye_m)]
latest[, delay_d := as.integer(rcept_orig - deadline)]
latest[, fye_date := eom(fy, fye_m)]

res <- merge(hold, latest, by = "sc", all.x = TRUE)
res[, flag := "OK"]
res[is.na(fy), flag := "NO_FILING_DATA"]
res[!is.na(fy) & as.integer(check_date - fye_date) > HOLDING_STALE_DAYS,
    flag := "EXPECTED_FY_MISSING"]
res[!is.na(fy) & flag == "OK" & delay_d > 0L & delay_d >= THRESH_DELAY_D, flag := "WARN"]
setorder(res, -Weight)

## ---- 5. 아카이브 신선도 (전체 + 계보별) ------------------------------------
arch_max_rc <- max(c(invA_max_rc, invB_max_rc), na.rm = TRUE)
arch_stale  <- mdiff(check_date, arch_max_rc) >= ARCHIVE_STALE_M
freshness <- list(
  basis = "보유교집합 · 사업보고서-패턴 행 기준(본 watch가 실제 소비한 데이터의 최신성 — 아카이브 전체 max 아님)",
  combined_max_rcept_dt = format(arch_max_rc),
  combined_age_months   = mdiff(check_date, arch_max_rc),
  stale                 = arch_stale,
  rule                  = sprintf("최신 rcept_dt %d개월 이상 과거 = STALE warn-loud (경보 침묵 != 신선)", ARCHIVE_STALE_M),
  lineage_A_filings_inventory = list(max_rcept_dt = format(invA_max_rc),
                                     age_months = mdiff(check_date, invA_max_rc),
                                     stale = mdiff(check_date, invA_max_rc) >= ARCHIVE_STALE_M,
                                     note = "R24 primary 계보(fy필드) — fy2023까지. 단독으론 STALE: 최신 fy 판정은 lineage B가 지탱"),
  lineage_B_disc_ck = list(max_rcept_dt = format(invB_max_rc),
                           age_months = mdiff(check_date, invB_max_rc),
                           stale = mdiff(check_date, invB_max_rc) >= ARCHIVE_STALE_M,
                           note = "list 아카이브(fy=report_nm 파싱, 별도 계보) — R24 census §C 소비 경로"),
  refresh_dependency = "아카이브 갱신 = DART 크롤 의존(insider 백필 쿼터와 별개 미배선) — 본 watch는 refresh 경로를 갖지 않음. STALE 발화 시 도훈/Q-Lead가 크롤 라운드로 갱신 판단")

## ---- 6. 문턱 provenance soft-check (census.rds 존재 시 재계산 대조 — 실패해도 run 유지) ----
thresh_check <- tryCatch({
  if (file.exists(CENSUS_RDS)) {
    S <- readRDS(CENSUS_RDS)
    p90 <- as.integer(quantile(S$inv_m[delay_d > 0, delay_d], 0.90, type = 7))
    if (p90 != THRESH_DELAY_D)
      cat(sprintf("[!!] 문턱 provenance 불일치: census 재계산 p90=%d != 고정 %d — R24 아티팩트 변경 여부 확인 필요\n",
                  p90, THRESH_DELAY_D))
    list(recomputed_p90 = p90, match = p90 == THRESH_DELAY_D)
  } else list(recomputed_p90 = NA, match = NA,
              note = "census.rds 부재 — 고정 문턱값으로 계속 (provenance는 header 기록)")
}, error = function(e) list(recomputed_p90 = NA, match = NA, note = paste("soft-check 실패:", conditionMessage(e))))

## ---- 7. JSON 저장 (OneDrive temp-rename) + 콘솔 요약 -----------------------
warn_rows <- res[flag == "WARN"]
per_holding <- lapply(seq_len(nrow(res)), function(i) {
  r <- res[i]
  list(ticker = r$Ticker, name = r$Name, weight = r$Weight,
       latest_fy = if (is.na(r$fy)) NA else r$fy,
       fye_month = if (is.na(r$fy)) NA else r$fye_m,
       rcept_orig = if (is.na(r$fy)) NA else format(r$rcept_orig),
       deadline   = if (is.na(r$fy)) NA else format(r$deadline),
       delay_d    = if (is.na(r$fy)) NA else r$delay_d,
       lineage    = if (is.na(r$fy)) NA else r$lineage,
       flag = r$flag)
})
fdw_result <- list(
  as_of  = format(check_date),
  book   = "STR_1715_on_M4_R05_noLayer4_PG2",
  metric_type = "observational_monitoring",
  basis  = "로컬 DART list 아카이브 read-only 소비 · monitoring 위생 진단 (book 무변경 · API 호출 0)",
  method = "R24(WT-D20260713_008) frozen 지연 로직 재사용: delay_d = 원제출일(min rcept_dt) − 법정기한((fy+1)-03-31 Dec-FYE frozen / 비-12월은 결산월말+90d 일반화 라벨)",
  rule   = sprintf("WARN: delay_d > 0 AND delay_d >= %d일 (자동조치 없음·문턱 sweep 금지)", THRESH_DELAY_D),
  warn_tone = "역사 기저율 낮음 · 위생 경보 — R24 실측: 중·대형 극단지각 15에피소드(mid 6+large 9)는 12M 내 심각사건 0건. 신호는 소형주 국한(small 14ep 중 6건). WARN = 검토 재료이지 퇴출 신호 아님",
  params_fixed = list(
    thresh_delay_d = THRESH_DELAY_D,
    thresh_provenance = "R24 census 677-유니버스 8,145에피소드(fy2009..2023) late(delay>0) 1,105건 분포 p90(type=7)=2일. 전-에피소드 p90=1일(임의지각)은 R24 실측 희석 기각으로 불채택. wd_strict(rank top-decile) 맥락: 29ep 중앙값 8일·범위 1..183일",
    holding_stale_days = HOLDING_STALE_DAYS,
    archive_stale_months = ARCHIVE_STALE_M),
  n_holdings_equity = nrow(res),
  n_zero_weight_excluded = n_zero_w,
  n_warn = nrow(warn_rows),
  warn_list = if (nrow(warn_rows)) lapply(seq_len(nrow(warn_rows)), function(i)
    list(ticker = warn_rows$Ticker[i], name = warn_rows$Name[i],
         latest_fy = warn_rows$fy[i], delay_d = warn_rows$delay_d[i])) else list(),
  n_expected_fy_missing = res[flag == "EXPECTED_FY_MISSING", .N],
  n_no_filing_data = res[flag == "NO_FILING_DATA", .N],
  per_holding = per_holding,
  archive_freshness = freshness,
  thresh_soft_check = thresh_check,
  inputs = list(holdings_csv = HOLDINGS_CSV, filings_inventory = INV_PARQUET, disc_ck_dir = DISC_DIR))

write_json_atomic <- function(obj, path) {   # OneDrive temp-rename 패턴
  tmp <- paste0(path, ".tmp_", Sys.getpid())
  write_json(obj, tmp, auto_unbox = TRUE, pretty = TRUE, digits = 6, na = "null")
  if (file.exists(path)) file.remove(path)
  invisible(file.rename(tmp, path))
}
write_json_atomic(fdw_result, file.path(OUT_DIR, "filing_delay_watch_latest.json"))
write_json_atomic(fdw_result, file.path(OUT_DIR, sprintf("filing_delay_watch_%s.json", format(check_date, "%Y%m"))))

cat(sprintf("\n[fdw] %s 기준 보유 %d종목 판정 (문턱: 지연>0 AND >=%d일):\n",
            format(check_date), nrow(res), THRESH_DELAY_D))
for (i in seq_len(nrow(res))) {
  r <- res[i]
  if (is.na(r$fy)) {
    cat(sprintf("   %-8s %-14s w=%.4f  [%s] 아카이브에 사업보고서 없음\n", r$Ticker, r$Name, r$Weight, r$flag))
  } else {
    cat(sprintf("   %-8s %-14s w=%.4f  fy%d 제출 %s (기한 %s, 지연 %+d일) [%s]%s\n",
                r$Ticker, r$Name, r$Weight, r$fy, format(r$rcept_orig), format(r$deadline),
                r$delay_d, r$flag,
                if (r$flag == "EXPECTED_FY_MISSING") " — 최신 결산기 보고서 아카이브 부재(갭/미제출 판별불가)" else ""))
  }
}
cat(sprintf("\n[fdw] WARN %d건 · EXPECTED_FY_MISSING %d건 · NO_FILING_DATA %d건\n",
            fdw_result$n_warn, fdw_result$n_expected_fy_missing, fdw_result$n_no_filing_data))
if (fdw_result$n_warn > 0)
  cat("[fdw] ⚠ WARN 종목 (위생 경보 — 역사 기저율: 중·대형 극단지각 15ep 사고 0):",
      paste(warn_rows$Ticker, collapse = ", "), "\n")
cat(sprintf("[fdw] 아카이브 신선도: 결합 최신 rcept %s (%d개월 전) → %s\n",
            freshness$combined_max_rcept_dt, freshness$combined_age_months,
            ifelse(arch_stale, "★STALE — 경보 침묵을 신선도 문제로 해석 금지·크롤 갱신 필요", "FRESH")))
cat("[DONE] outputs →", OUT_DIR, "\n")
