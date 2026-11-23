#==============================================================================
# 한국 경기 지표(월간) 수집기 — ECOS(한국은행 경제통계시스템)
#   2026-11-23 · 도훈 '한국지표 추가(지속 수집가능한 파이프라인 배선 포함)' · 결정 KR-ACTIVITY-INDICATORS-PIPELINE-20261123
#
# 왜: 팩터 비중의 조건 신호(거시 주기)에 쓸 한국 활동 지표가 저장소에 없었다(미국 산업생산뿐).
#     틀 = MSCI 2018 Adaptive Multi-Factor Allocation — 활동 지표의 3개월 대 12개월 이동평균으로 경기 네 상태를 정한다
#     (https://www.msci.com/documents/10199/239004/Research_Insight_Adaptive_Multi-Factor_Allocation.pdf · 원문은 미국 PMI · CFNAI · ADS 를 썼다).
#
# 계열 9개(통계표 · 항목 코드는 2026-11-23 ECOS StatisticTableList · StatisticItemList 로 이름을 대조해 정했다):
#   심리(조사월 말 공표 · 개정 없음)     KR_ESI 경제심리지수(원계열) · KR_BSI_ALL · KR_BSI_MFG 업황실적 BSI(전산업 · 제조업)
#   실물                                  KR_EXPORT 수출금액(통관 · 천 달러)
#   종합(다음 달 말 공표 · 개정 있음)     KR_CLI 선행종합지수 · KR_CLI_CYC 선행지수 순환변동치 · KR_CCI_CYC 동행지수 순환변동치
#   생산(다음 달 말 공표 · 개정 있음)     KR_IP_ALL_SA 전산업생산지수 · KR_IP_MFG_SA 광공업(둘 다 계절조정)
#
# 쓰는 파일:
#   .cache/ecos_kr_activity.parquet            최신 값 — Date(관측월 1일) · Value · Series (ecos_bond_rates 와 같은 꼴)
#   .cache/ecos_kr_activity_vintages.parquet   수집 이력 — Series · Date · Value · First_Seen · Kind. 덧붙이기만 한다(지우거나 고치지 않는다).
#       Kind = backfill(그 계열을 처음 적재한 날의 과거 값 — First_Seen 은 가용일이 아니다) · new(새 관측월 — First_Seen 이 실제로 본 날)
#              · revision(이미 있던 관측월의 값이 바뀜) · late(과거 관측월이 뒤늦게 생김)
#   ECOS 는 최신 값만 준다. 경기종합지수 · 생산지수는 공표 뒤에도 고쳐지고, 순환변동치는 달마다 전 구간이 다시 추정된다.
#   '그때 알 수 있던 값'은 이 이력이 쌓인 구간에서만 쓸 수 있다 — 그 전 구간의 개정 계열은 최신 개정값이다(PIT 경계).
#
# 가용일 규칙 = 06_Registry/kr_activity_availability_rules.json — fred_availability 엔진에 rules_path 로 넘겨 쓴다.
#   정본 규칙 파일(fred_availability_rules.json)에는 더하지 않았다 — 그 파일의 md5 가 국면 계산의 에폭 키라, 고치면 국면 체인이 에폭 불일치로 선다.
# 항목 이름이 선언과 다르면 멈춘다(fail-closed — 2026-11-06 항목 코드 오표기 사고의 재발 방지). 하나라도 못 받으면 아무 파일도 쓰지 않는다.
#
# Usage(daily_refresh [4ka]):
#   source("config.R"); source("data/data_collector_ecos_activity.R"); ecos_fetch_kr_activity()
#==============================================================================
cat("[ecos_act] Loading...\n")

suppressPackageStartupMessages({ library(data.table); library(arrow) })
if (!exists(".ecos_fetch_series", mode = "function")) {
  source(file.path(if (exists("INFRA_DIR")) INFRA_DIR else file.path(PROJECT_ROOT, "02_Infrastructure"), "data", "data_collector_ecos.R"))
}
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_ROOT, ".cache")
if (!exists("ECOS_ACTIVITY_CACHE")) ECOS_ACTIVITY_CACHE <- file.path(CACHE_DIR, "ecos_kr_activity.parquet")
if (!exists("ECOS_ACTIVITY_VINTAGES")) ECOS_ACTIVITY_VINTAGES <- file.path(CACHE_DIR, "ecos_kr_activity_vintages.parquet")

# item = StatisticSearch 의 항목 코드 경로(항목이 두 단이면 '코드1/코드2') · expect = ECOS 가 돌려주는 항목 이름에 들어 있어야 하는 글자
ECOS_ACTIVITY_SERIES <- list(
  list(name = "KR_ESI",       stat = "513Y001", item = "E1000",    expect = c("경제심리지수", "원계열")),
  list(name = "KR_BSI_ALL",   stat = "512Y007", item = "AA/99988", expect = c("업황실적", "전산업")),
  list(name = "KR_BSI_MFG",   stat = "512Y007", item = "AA/C0000", expect = c("업황실적", "제조업")),
  list(name = "KR_EXPORT",    stat = "901Y118", item = "T002",     expect = c("수출금액")),
  list(name = "KR_CLI",       stat = "901Y067", item = "I16A",     expect = c("선행종합지수")),
  list(name = "KR_CLI_CYC",   stat = "901Y067", item = "I16E",     expect = c("선행지수순환변동치")),
  list(name = "KR_CCI_CYC",   stat = "901Y067", item = "I16D",     expect = c("동행지수순환변동치")),
  list(name = "KR_IP_ALL_SA", stat = "901Y033", item = "A00/2",    expect = c("전산업생산지수", "계절조정")),
  list(name = "KR_IP_MFG_SA", stat = "901Y033", item = "AB00/2",   expect = c("광공업", "계절조정"))
)

## 임시 파일에 쓰고 덮어쓴다 — 대상을 다른 프로그램이 잠깐 잡고 있으면 이름 바꾸기가 실패하므로 짧게 기다렸다 다시 한다(합쳐 약 9초)
.ecos_act_write <- function(dt, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".", Sys.getpid(), ".tmp")
  write_parquet(dt, tmp)
  for (i in seq_len(40L)) {
    if (suppressWarnings(file.rename(tmp, path))) return(invisible(path))
    Sys.sleep(0.05 * (1 + (i - 1L) %/% 5L))
  }
  unlink(tmp)
  stop("[ecos_act] 저장 실패(이름 바꾸기): ", path)
}

## 받은 최신 값과 수집 이력을 견줘, 덧붙일 줄(새 계열의 첫 적재 · 새 관측월 · 바뀐 값 · 뒤늦게 생긴 관측월)을 만든다
.ecos_act_vintage_rows <- function(out, vint, today) {
  if (is.null(vint) || nrow(vint) == 0L) return(out[, .(Series, Date, Value, First_Seen = today, Kind = "backfill")])
  last <- vint[order(First_Seen), .SD[.N], by = .(Series, Date)]            # 관측월마다 마지막으로 적어 둔 값
  mx <- vint[, .(Max_Date = max(Date)), by = Series]
  mg <- merge(out, last[, .(Series, Date, Prev = Value)], by = c("Series", "Date"), all.x = TRUE)
  mg <- merge(mg, mx, by = "Series", all.x = TRUE)
  mg[, Kind := fifelse(is.na(Max_Date), "backfill",
               fifelse(is.na(Prev) & Date > Max_Date, "new",
               fifelse(is.na(Prev), "late",
               fifelse(abs(Value - Prev) > 1e-9 * pmax(1, abs(Prev)), "revision", NA_character_))))]
  mg[!is.na(Kind), .(Series, Date, Value, First_Seen = today, Kind)]
}

#' 한국 경기 지표 9계열을 받아 최신 값 파일과 수집 이력을 갱신한다
#' @param start_ym 받기 시작할 관측월(YYYYMM)
#' @param end_ym 끝 관측월(기본 = 이번 달)
#' @param today 수집일(시험용 — 기본 = 오늘)
#' @return 최신 값 data.table(Date, Value, Series) — 보이지 않게
#' @export
ecos_fetch_kr_activity <- function(start_ym = "197001", end_ym = NULL, today = Sys.Date()) {
  if (is.null(end_ym)) end_ym <- format(Sys.Date(), "%Y%m")
  parts <- list()
  for (s in ECOS_ACTIVITY_SERIES) {
    rows <- suppressWarnings(.ecos_fetch_series(s$stat, s$item, "M", start_ym, end_ym))   # 빈 항목 코드 열을 NA 로 채웠다는 경고만 가린다
    if (is.null(rows) || nrow(rows) == 0L) stop(sprintf("[ecos_act] %s (%s/%s) 수급 실패 — 아무 파일도 쓰지 않는다", s$name, s$stat, s$item))
    nmc <- intersect(c("ITEM_NAME1", "ITEM_NAME2", "ITEM_NAME3", "ITEM_NAME4"), names(rows))
    nm <- gsub("\\s+", "", paste(unique(unlist(lapply(nmc, function(cn) as.character(unlist(rows[[cn]]))))), collapse = "|"))
    miss <- s$expect[!vapply(s$expect, function(k) grepl(k, nm, fixed = TRUE), TRUE)]
    if (length(miss)) stop(sprintf("[ecos_act] %s 항목 이름 불일치 — ECOS '%s' · 선언 '%s'", s$name, nm, paste(s$expect, collapse = " + ")))
    d <- data.table(Date = as.Date(paste0(as.character(unlist(rows$TIME)), "01"), format = "%Y%m%d"),
                    Value = suppressWarnings(as.numeric(as.character(unlist(rows$DATA_VALUE)))), Series = s$name)[!is.na(Date) & !is.na(Value)]
    if (nrow(d) == 0L || anyDuplicated(d$Date)) stop(sprintf("[ecos_act] %s — 쓸 수 있는 행이 없거나 같은 달이 두 번 왔다", s$name))
    setorder(d, Date)
    parts[[s$name]] <- d
    cat(sprintf("[ecos_act] %-13s %s/%-9s %4d개월 (%s ~ %s) 끝 값 %s\n", s$name, s$stat, s$item, nrow(d),
                format(d$Date[1], "%Y-%m"), format(d$Date[nrow(d)], "%Y-%m"), format(d$Value[nrow(d)], big.mark = ",")))
  }
  out <- rbindlist(parts)
  setorder(out, Series, Date)
  vint <- if (file.exists(ECOS_ACTIVITY_VINTAGES)) as.data.table(read_parquet(ECOS_ACTIVITY_VINTAGES)) else NULL
  if (!is.null(vint)) vint[, `:=`(Date = as.Date(Date), First_Seen = as.Date(First_Seen))]
  add <- .ecos_act_vintage_rows(out, vint, as.Date(today))
  if (nrow(add)) {
    vint2 <- rbindlist(list(vint, add), use.names = TRUE)
    setorder(vint2, Series, Date, First_Seen)
    .ecos_act_write(vint2, ECOS_ACTIVITY_VINTAGES)
  }
  .ecos_act_write(out, ECOS_ACTIVITY_CACHE)
  k <- add[, .N, by = Kind]
  cat(sprintf("[ecos_act] 저장 — 최신 값 %d행 · 계열 %d개 · 수집 이력에 덧붙인 줄 %d(%s)\n", nrow(out), uniqueN(out$Series), nrow(add),
              if (nrow(k)) paste(sprintf("%s %d", k$Kind, k$N), collapse = " · ") else "변화 없음"))
  nw <- add[Kind == "new"]
  if (nrow(nw)) cat(sprintf("[ecos_act] 새 관측월 — %s\n", paste(sprintf("%s %s", nw$Series, format(nw$Date, "%Y-%m")), collapse = " · ")))
  invisible(out)
}

#' 최신 값(Date, Value, Series) — 없으면 받는다
#' @export
ecos_load_kr_activity <- function() {
  if (!file.exists(ECOS_ACTIVITY_CACHE)) {
    cat("[ecos_act] Cache not found, fetching...\n")
    return(ecos_fetch_kr_activity())
  }
  as.data.table(read_parquet(ECOS_ACTIVITY_CACHE))
}

#' 수집 이력(Series, Date, Value, First_Seen, Kind)
#' @export
ecos_load_kr_activity_vintages <- function() {
  if (!file.exists(ECOS_ACTIVITY_VINTAGES)) return(NULL)
  as.data.table(read_parquet(ECOS_ACTIVITY_VINTAGES))
}

cat("[ecos_act] Loaded. Functions: ecos_fetch_kr_activity(), ecos_load_kr_activity(), ecos_load_kr_activity_vintages()\n")
