## n3 — 수급(flow) 원천의 미측정 범위 확정 + 커버리지 실측
## ★중복 측정 회피: 331 에 이미 들어간 것과 raw 피처를 분리한다.
## ★PIT: 이 피처들은 5d/20d/60d 후행 집계라 월말 스냅샷 → 익월 수익 규약이면 안전.
##   단 fwd_* 컬럼은 **미래 라벨**이므로 절대 신호로 쓰지 않는다(이름에 fwd 가 있는 것 전부 배제).
suppressPackageStartupMessages({ library(data.table); library(arrow) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/pg2_hunt")
say  <- function(fmt, ...) { cat(sprintf(paste0("[n3] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/config.R"); source("02_Infrastructure/contracts/book_marginal.R")
mi <- function(d) as.integer(format(d,"%Y"))*12L + as.integer(format(d,"%m"))

FN331 <- readLines(file.path(OUT, "factors_eligible.txt"))
say("=== 1. 이미 측정된 331 중 수급 계열 ===")
flowish <- FN331[grepl("INV|flow|smart|netbuy|foreign|inst", FN331, ignore.case=TRUE)]
say("  %d건: %s", length(flowish), paste(flowish, collapse=", "))

say("=== 2. flow_features_daily 스키마·커버리지 (일간 raw) ===")
f <- ".cache/flow_features_daily.parquet"
if (!file.exists(f)) {
  cand <- list.files(".", pattern="flow_features_daily\\.parquet$", recursive=TRUE, full.names=TRUE)
  f <- if (length(cand)) cand[1] else NA_character_
}
if (is.na(f)) { say("★파일 미발견"); quit(status=0) }
say("  경로 %s (%.0fMB)", f, file.size(f)/1e6)
sc <- arrow::open_dataset(f)
say("  컬럼 %d: %s", length(names(sc)), paste(names(sc), collapse=", "))
## ★미래 라벨 배제 (fwd_*)
FEAT <- setdiff(names(sc), c("Date","Ticker"))
fwd  <- FEAT[grepl("^fwd_", FEAT)]
FEAT <- setdiff(FEAT, fwd)
say("  ★미래 라벨 배제: %s", paste(fwd, collapse=", "))
## return-파생도 배제 (이 라운드의 목적은 **비-return 원천**)
retlike <- FEAT[grepl("^ret_|volume_ratio|turnover_chg|log_mcap|liq_", FEAT)]
FEAT <- setdiff(FEAT, retlike)
say("  ★return/시총-파생 배제: %s", paste(retlike, collapse=", "))
say("  ⇒ **비-return 후보 %d개**: %s", length(FEAT), paste(FEAT, collapse=", "))

say("=== 3. 커버리지 실측 (월말 스냅샷 기준) ===")
D <- as.data.table(sc %>% dplyr::select(Date) %>% dplyr::collect())
D[, m := mi(Date)]
inc <- bm_load_incumbent(); inc[, m := mi(date)]
Mru <- fread(file.path(ROOT,"stage_artifacts/FQ191/p1_rule.csv"))[, date := as.Date(date)][date < as.Date("2026-01-01")]
mo <- sort(unique(D$m))
say("  일간 %d행 · %d개월 (%s ~ %s)", nrow(D), length(mo), min(D$Date), max(D$Date))
say("  PG2 창 겹침 **%d개월** / 269", length(intersect(mo, inc$m)))
say("  FQ-191 파킹 창 겹침 **%d개월** / 73 (요구 60)", length(intersect(mo, mi(Mru$date))))
ok_un <- length(intersect(mo, inc$m)) >= 60L
ok_pk <- length(intersect(mo, mi(Mru$date))) >= 60L
say("  ⇒ 무조건부 arm %s · 파킹 arm %s", if (ok_un) "측정 가능" else "★불가", if (ok_pk) "측정 가능" else "★불가")

say("=== 4. insider 자산 커버리지 ===")
ip <- list.files(".", pattern="^insider_trades\\.parquet$", recursive=TRUE, full.names=TRUE)
if (length(ip)) {
  I <- as.data.table(read_parquet(ip[1]))
  I[, m := mi(as.Date(Date))]
  say("  %d행 · %d개월 (%s ~ %s) · %d종목",
      nrow(I), uniqueN(I$m), min(I$Date, na.rm=TRUE), max(I$Date, na.rm=TRUE), uniqueN(I$Ticker))
  say("  PG2 겹침 %d · 파킹 겹침 %d (요구 60)",
      length(intersect(unique(I$m), inc$m)), length(intersect(unique(I$m), mi(Mru$date))))
  say("  ★수치 컬럼 0개 문제: sp_stock_lmp_irds_cnt 클래스 = %s · 예시 %s",
      class(I$sp_stock_lmp_irds_cnt)[1], paste(head(I$sp_stock_lmp_irds_cnt,3), collapse=" | "))
  say("  trade_type 분포:"); print(head(sort(table(I$trade_type), decreasing=TRUE), 6))
} else say("  insider_trades.parquet 미발견")

say("=== 5. ★착수 판정 ===")
say("  수급 raw 피처 %d개 · 무조건부 %s · 파킹 %s", length(FEAT),
    if (ok_un) "가능" else "불가", if (ok_pk) "가능" else "불가")
say("  ⇒ 다음 단계: 월말 스냅샷 패널 구축 → 계약 경로 슬리브 → 2-arm ΔIR")
saveRDS(list(feat = FEAT, path = f, ok_un = ok_un, ok_pk = ok_pk), file.path(OUT, "n3_scope.rds"))
say("=== n3 완료 ===")
