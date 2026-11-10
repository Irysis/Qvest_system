## test_scn_l1_chain_e2e.R — 1계층 강화 사슬 끝에서 끝까지 시나리오(감사 레인 E1 · 2026-11-10)
##   격리: 임시 루트(SB) — 임시 등록부 · 상설 원장(RC_SA_ROOT 대신 sa_root 인자) · 팩터 DB 수리 원장 · 생성기 등록부(RC_RXG_PATH) · 판단 원장 · 결과 원장 ·
##   합성 산출물 · 가짜 러너 · 가짜 재채점 · 가짜 관문. 코드 · 정본 설정은 저장소 것을 읽기만 한다. 실제 측정 · 발송 · 네트워크 없음.
##   F 데이터 신선도(v1/freshness.R — 감사기 규칙 재사용 · 낡음/신선/판독 불가 · 진입점 · 돌연변이 · 발송 없음 · 실행기 배선)
##   P 상설 원장 → 기저 풀(상설 경로 · 사슬 끊긴 원장 무시 · 규칙 변경 수혜 기록 제외 · 돌연변이)
##   C 사슬: 판 → 등록(영수증) → 기준 칸(낡음 거부 · 크래시 점유 인계) → 걸음 채택 · 기각 · 측정 실패 → 포기 · 잡음 연속 → 예산 종료
##     실패 주입: 칸 사양 변경 · τ_D 날짜 · 원장 변조 · 판 표식 변경 · 영수증 없음 · 동시 진행(두 프로세스 · 잠금 안 재확인 · 돌연변이)
##   Z 닫기 → 재채점(시행 집합) → 후보 관문(발행 경로 · 거두기) → 결과 원장 → 닫기 중간 크래시 재진입 → 다음 사슬 설계 입력 · 생성기 작업 디렉터리
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/scenarios/test_scn_l1_chain_e2e.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v1/p4.R"))) stop("저장소 루트가 아니다: ", ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
source("04_Research/programs/_lib/round_core/v1/load.R")
suppressPackageStartupMessages({ library(data.table); library(arrow) })
TG_CALLS <- 0L; tg_send <- function(...) { TG_CALLS <<- TG_CALLS + 1L; invisible(NULL) }   # 발송 함정(불리면 센다)

SB <- gsub("\\\\", "/", tempfile("scn_l1_")); dir.create(SB, recursive = TRUE)
invisible(reg.finalizer(globalenv(), function(e) unlink(SB, recursive = TRUE), onexit = TRUE))
if (startsWith(tolower(SB), tolower(paste0(ROOT, "/")))) stop("샌드박스가 저장소 안이다")
TAU <- rc_ref_value("06_Registry/behavior_card.json::tau_d")
REAL <- vapply(c("06_Registry/round_outcomes.jsonl", "06_Registry/q_judgment_ledger.json", "06_Registry/rx_generator.json", "06_Registry/research_programs.json"),
               function(f) if (file.exists(f)) rc_md5(f) else "absent", "")
FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "시험 주입")
STALE <- function(root) list(ok = FALSE, state = "stale", reason = "rawdata STALE(시험 주입)")

## ═══ F 데이터 신선도 ═══════════════════════════════════════════════════════════
cat("F 데이터 신선도\n")
TR <- file.path(SB, "froot")
for (f in c(RC_FRESH_SOURCE, "06_Registry/krx_holidays.json")) { dir.create(dirname(file.path(TR, f)), recursive = TRUE, showWarnings = FALSE); file.copy(f, file.path(TR, f)) }
dir.create(file.path(TR, ".cache"), showWarnings = FALSE)
mkp <- function(last_raw, last_bm, cal_to = as.Date("2026-11-09"), root = TR) {
  d <- seq(min(as.Date("2026-10-01"), cal_to - 90L), cal_to, by = "day"); bd <- d[!format(d, "%u") %in% c("6", "7")]
  write_parquet(data.frame(Date = bd), file.path(root, ".cache/trading_calendar.parquet"))
  r <- bd[bd <= last_raw]; write_parquet(data.frame(Date = rep(r, each = 2), Ticker = rep(c("A", "B"), length(r)), Close = 1), file.path(root, ".cache/RAWDATA.parquet"))
  b <- bd[bd <= last_bm]; write_parquet(data.frame(Date = b, KOSPI200 = 300), file.path(root, ".cache/benchmark.parquet"))
}
TODAY <- as.Date("2026-11-10")
mkp(as.Date("2026-11-09"), as.Date("2026-11-09")); f_ok <- rc_data_freshness(TR, TODAY)
chk("F1 신선(가격 · 벤치 = 직전 거래일 11-09 · 기준일 = 감사기 as_of) → ok", isTRUE(f_ok$ok) && identical(f_ok$as_of, "2026-11-09") && identical(f_ok$state, "fresh"), f_ok$reason)
mkp(as.Date("2026-11-06"), as.Date("2026-11-09")); f_st <- rc_data_freshness(TR, TODAY)
chk("F2 오늘 운영과 같은 꼴(RAWDATA 11-06 · 달력 지연 3일 ≤ 3 이지만 세션 1 빠짐) → stale(세션 축)", identical(f_st$state, "stale") && grepl("rawdata", f_st$reason) &&
      identical(as.integer(f_st$items$rawdata$sess_lag), 1L), f_st$reason)
mkp(as.Date("2026-11-09"), as.Date("2026-11-06")); f_b <- rc_data_freshness(TR, TODAY)
chk("F3 벤치만 낡음 → stale(벤치)", identical(f_b$state, "stale") && grepl("benchmark", f_b$reason) && !grepl("rawdata", f_b$reason), f_b$reason)
unlink(file.path(TR, ".cache/RAWDATA.parquet")); f_m <- rc_data_freshness(TR, TODAY)
chk("F4 가격 파일 없음(MISSING) → stale", identical(f_m$state, "stale") && grepl("MISSING", f_m$reason), f_m$reason)
mkp(as.Date("2026-11-09"), as.Date("2026-11-09"))
f_mon <- rc_data_freshness(TR, as.Date("2026-11-09"))
chk("F5 월요일 아침(기준일 = 금 11-06) · 데이터 11-09 → 신선(주말을 세션으로 세지 않는다)", isTRUE(f_mon$ok) && identical(f_mon$as_of, "2026-11-06"), f_mon$reason)
mkp(as.Date("2026-11-06"), as.Date("2026-11-09"))      # 빈 세션이 있어야 세션 축을 센다(지연 0 이면 셀 날이 없다)
hj <- jsonlite::fromJSON(file.path(TR, "06_Registry/krx_holidays.json"), simplifyVector = FALSE); hj0 <- hj
hj$years <- setdiff(unlist(hj$years), 2026L); jsonlite::write_json(hj, file.path(TR, "06_Registry/krx_holidays.json"), auto_unbox = TRUE)
f_h <- rc_data_freshness(TR, TODAY)
chk("F6 휴장일 정본에 그 해 없음(세션 축 미측정) → unreadable(달력 축만으로 통과시키지 않는다 · fail-closed)", identical(f_h$state, "unreadable") && !isTRUE(f_h$ok), f_h$reason)
file.copy("06_Registry/krx_holidays.json", file.path(TR, "06_Registry/krx_holidays.json"), overwrite = TRUE)
AUD <- file.path(TR, RC_FRESH_SOURCE); a0 <- readLines(AUD, encoding = "UTF-8", warn = FALSE)
m1 <- sub("^audits\\$rawdata ", "audits$rawdata_renamed ", a0); writeLines(m1, AUD, useBytes = TRUE); f_r <- rc_data_freshness(TR, TODAY)
chk("F7 돌연변이 — 감사기에서 rawdata 감사 호출이 사라짐(치환 1곳 성사) → unreadable", sum(m1 != a0) == 1L && identical(f_r$state, "unreadable") && grepl("audits\\$rawdata", f_r$reason), f_r$reason)
m2 <- sub("max_sess = 0L)   # 주가", "max_sess = 9L)   # 주가", a0, fixed = TRUE); writeLines(m2, AUD, useBytes = TRUE)
mkp(as.Date("2026-11-06"), as.Date("2026-11-09")); f_r2 <- rc_data_freshness(TR, TODAY)
chk("F8 규칙은 감사기 것을 그대로 쓴다(양성 대조 — 감사기 세션 여유를 9 로 바꾸면 같은 자료가 fresh · 치환 1곳)", sum(m2 != a0) == 1L && isTRUE(f_r2$ok), f_r2$reason)
writeLines(a0, AUD, useBytes = TRUE)
## ① 운영 경로 = 감사기 판정 전용 진입점(--check · 자식 R · 오늘 날짜) — 같은 자료에서 ② 정의 꺼내기와 같은 판정인가(양방향)
dir.create(file.path(TR, "02_Infrastructure"), showWarnings = FALSE); writeLines("invisible(NULL)", file.path(TR, "02_Infrastructure/config.R"))
TD0 <- Sys.Date(); AS <- as.Date(rc_data_freshness(TR, TD0)$as_of)
mkp(AS, AS, cal_to = AS); c1 <- rc_data_freshness(TR); e1 <- rc_data_freshness(TR, TD0)
mkp(AS - 7L, AS, cal_to = AS); c2 <- rc_data_freshness(TR); e2 <- rc_data_freshness(TR, TD0)
chk("F9 운영 호출(today 미지정) = 감사기 --check 진입점 · 신선/낡음 모두 정의 꺼내기 판정과 일치", identical(c1$items$via, "check") && identical(c1$state, "fresh") &&
      identical(e1$state, "fresh") && identical(c2$state, "stale") && identical(e2$state, "stale") && grepl("rawdata", c2$reason), paste(c1$reason, "|", c2$reason))
unlink(file.path(TR, "02_Infrastructure/config.R")); c3 <- rc_data_freshness(TR)
chk("F9b 진입점 오류(감사기가 config.R 을 못 읽음 · 종료 1) = unreadable(측정 거부)", identical(c3$state, "unreadable"), c3$reason)
writeLines("invisible(NULL)", file.path(TR, "02_Infrastructure/config.R"))
unlink(AUD); f_x <- rc_data_freshness(TR, TODAY)
chk("F10 감사기 파일 없음 → unreadable", identical(f_x$state, "unreadable")); writeLines(a0, AUD, useBytes = TRUE)
chk("F11 판정 중 텔레그램 발송 0 · 감사 JSON 미기록", TG_CALLS == 0L && !file.exists(file.path(TR, "qepm/observability/morning_freshness_latest.json")))
g1 <- rc_fresh_gate(function(root) stop("판정기 죽음"), TR); g2 <- rc_fresh_gate(function(root) list(ok = NA), TR)
chk("F12 판정 함수 오류 · 모양 오류 = unreadable(측정 거부)", identical(g1$state, "unreadable") && !isTRUE(g1$ok) && identical(g2$state, "unreadable"))
OPS <- tryCatch(rc_data_freshness(ROOT), error = function(e) list(state = paste("error:", conditionMessage(e))))
cat(sprintf("  [정보] 운영 루트 건식 판정 = %s · 기준일 %s · %s\n", OPS$state, OPS$as_of %||% "?", OPS$reason %||% ""))
rs <- readLines("04_Research/programs/_lib/round_core/round.sh", encoding = "UTF-8", warn = FALSE)
li <- function(rx) which(grepl(rx, rs))[1]
chk("F13 실행기 배선 — measure: 배리어 → fresh-check → precheck 순 · standing-measure: 대기 측정 전 fresh-check · p4 측정 종료 6 = data_stale",
    isTRUE(li("fresh-check \\|\\| \\{") < li("precheck \\|\\| \\{")) && isTRUE(li("^    barrier; \\[") < li("fresh-check \\|\\| \\{")) &&
      isTRUE(li("- fresh-check") < li("for code in \\$PEND")) && any(grepl("6\\) echo data_stale", rs)))
st_src <- paste(deparse(rc_standing_measure_item), collapse = "\n")
chk("F14 상설 측정(rc_standing_measure_item) — 신선도 판정이 워커 호출(system2)보다 앞", isTRUE(regexpr("rc_fresh_gate", st_src) < regexpr("system2", st_src)) &&
      regexpr("rc_fresh_gate", st_src) > 0)

## ═══ 공통 픽스처(합성 산출 · 엔진 · 등록부 · 원장) ══════════════════════════════════
ME <- seq(as.Date("2000-02-01"), as.Date("2025-01-01"), by = "month") - 1L
mk_art <- function(nm, grade = "C", extra = list(), run_id = "RP_20261111_090000_t") {
  set.seed(nchar(nm)); n <- length(ME); bm <- rnorm(n, 0.006, 0.05); s <- 0.004 + 0.8 * bm + rnorm(n, 0, 0.02)
  d <- file.path(SB, "art", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(date = ME, ret_net = s, risk_free_ret = 0, leverage = 1, frequency = "monthly"), file.path(d, "03_period_returns.csv"))
  fwrite(data.table(date = ME, benchmark_ret = bm, benchmark_id = "KOSPI200"), file.path(d, "05_benchmark_returns.csv"))
  fwrite(data.table(date = ME, nav_net = cumprod(1 + s)), file.path(d, "02_nav.csv"))
  rc_json_write(c(list(run_id = run_id, essence_grade = grade, grade_scheme = "test_fixture"), extra), file.path(d, "authoritative_remeasure.json"))
  d
}
ENG <- file.path(SB, "eng")
mk_eng <- function(nm) { p <- file.path(ENG, nm, "engine.R"); dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeLines(c("## fixture", paste("##", nm), "FACTORS <- NULL"), p); p }
item <- function(nm, art) list(key = paste0("engine:E_", nm), kind = "engine", engine_path = mk_eng(nm), artifacts = art, implementation_suspect = FALSE,
                               has_short = FALSE, audit_verdict = "adapted", paper_key = paste0("9909.", nm))
A_OK <- mk_art("lane_ok", "B")
A_SRB <- mk_art("lane_srb", "B", list(selection_regrade = list(benefits_from_rule_change = TRUE, rules_version = "v3.4", prior_essence_grade = "C")))
A_RCB <- mk_art("lane_rcb", "A", list(rule_change_benefit = list(benefit = TRUE, rules_version = "v3.3", prior_essence_grade = "B")))
A_NOB <- mk_art("lane_nob", "B", list(selection_regrade = list(benefits_from_rule_change = FALSE)))
REG <- file.path(SB, "research_programs.json")
rc_json_write(list(schema = "research_programs_v1", programs = list(list(id = "P1_RETURN", queue = list(item("ok", A_OK), item("srb", A_SRB), item("rcb", A_RCB), item("nob", A_NOB)), consumed = list())),
                   paper_routing = list(unrouted = list())), REG)
FDVL <- file.path(SB, "factor_db_vintage.json")
rc_json_write(list(schema = "factor_db_vintage_v1", entries = list(list(id = "T-REPAIR", completed_at = "2026-11-10T11:26:00+09:00", scope = "all"))), FDVL)

## ═══ P 상설 원장 → 기저 풀 ═════════════════════════════════════════════════════
cat("P 상설 원장 → 기저 풀\n")
SA <- file.path(SB, "sa"); LD <- file.path(SA, "stage_artifacts/programs/P1_RETURN/P1S90_t"); dir.create(LD, recursive = TRUE)
ST_ENG <- mk_eng("standing_long"); A_STD <- mk_art("standing_meas", "C")
lines <- character(0); prev <- "genesis"
for (r in list(list(event = "enqueue", code = "P1S90_c1", engine = "S1", engine_path = ST_ENG, engine_md5 = rc_md5(ST_ENG), paper = list(paper_key = "9909.std")),
               list(event = "measure", code = "P1S90_c1", ok = TRUE, fp_same = TRUE, artifacts = A_STD),
               list(event = "verdict", code = "P1S90_c1", qualify = TRUE, status = "evaluated"))) {
  js <- as.character(jsonlite::toJSON(c(list(schema = RC_STANDING_LEDGER_SCHEMA, at = "2026-11-10T10:00:00+0900", round_id = "P1S90_t", edition = 1L, prev = prev), r),
                                      auto_unbox = TRUE, null = "null"))
  lines <- c(lines, js); prev <- .rcs_md5s(js)
}
writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), file.path(LD, "standing_ledger.jsonl"))
SQ <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SA); SQ <- SQ[startsWith(ledger, gsub("\\\\", "/", SA))]
chk("P1 상설 원장(판정 qualify) → 자격 통과 목록 1행(엔진 · 마지막 ok 측정 산출)", nrow(SQ) == 1L && identical(SQ$code, "P1S90_c1") && identical(SQ$artifacts, A_STD) && isTRUE(SQ$engine_same))
POOL <- rc_p4_base_pool(ROOT, registry_path = REG, standing = SQ, fdv_ledger_path = FDVL)
rsn <- function(k) strsplit(POOL[key == k]$reason, ";", fixed = TRUE)[[1]]
chk("P2 등급 B · 수혜 표식 없음 = 자격 · 수혜 FALSE 명시도 자격", isTRUE(POOL[key == "engine:E_ok"]$eligible) && isTRUE(POOL[key == "engine:E_nob"]$eligible),
    paste(POOL$key, POOL$reason))
chk("P3 규칙 변경 수혜 기록 — selection_regrade$benefits_from_rule_change(B) · rule_change_benefit$benefit(A) = rule_change_beneficiary 제외",
    identical(rsn("engine:E_srb"), "rule_change_beneficiary") && identical(rsn("engine:E_rcb"), "rule_change_beneficiary") &&
      !isTRUE(POOL[key == "engine:E_srb"]$eligible) && !isTRUE(POOL[key == "engine:E_rcb"]$eligible) && grepl("규칙 변경 수혜", POOL[key == "engine:E_rcb"]$reason_detail))
chk("P4 상설 경로 행(등록부에 없는 엔진) = 자격 · 사유 코드 어휘 안", isTRUE(POOL[standing_code == "P1S90_c1"]$eligible) &&
      all(unlist(strsplit(POOL$reason[nzchar(POOL$reason)], ";")) %in% names(RC_P4_REASONS)))
rbu <- .rcp4_rule_benefit(A_SRB, TR)        # TR = 관문 정본이 없는 루트
chk("P5 수혜 판정 정의를 꺼내지 못하면 NA → 등급 경로 rule_change_unknown(fail-closed)", is.na(rbu$benefit))
p4src <- readLines("04_Research/programs/_lib/round_core/v1/p4.R", encoding = "UTF-8", warn = FALSE)
mut_src <- function(from, to, fixed = TRUE) { m <- sub(from, to, p4src, fixed = fixed); n <- sum(m != p4src); f <- file.path(SB, sprintf("p4_mut_%d.R", sample.int(1e6, 1)))
  writeLines(m, f, useBytes = TRUE); list(n = n, path = f) }
restore_p4 <- function() sys.source("04_Research/programs/_lib/round_core/v1/p4.R", envir = globalenv())
mu <- mut_src("if (!stq && grade %in% c(\"A\", \"B\") && !isFALSE(rb$benefit)) {", "if (FALSE) {")
sys.source(mu$path, envir = globalenv()); PM <- rc_p4_base_pool(ROOT, registry_path = REG, standing = SQ, fdv_ledger_path = FDVL); restore_p4()
chk("P6 돌연변이(수혜 검사 끔 · 치환 1곳) → 수혜 기록이 자격을 얻는다(검사가 실제로 막고 있었다)", mu$n == 1L && isTRUE(PM[key == "engine:E_srb"]$eligible))
L2 <- lines; L2[2] <- sub("\"ok\":true", "\"ok\":false", L2[2]); dir.create(file.path(SA, "stage_artifacts/programs/P1_RETURN/P1S91_t"), recursive = TRUE)
writeBin(charToRaw(paste0(paste(sub("P1S90", "P1S91", L2), collapse = "\n"), "\n")), file.path(SA, "stage_artifacts/programs/P1_RETURN/P1S91_t/standing_ledger.jsonl"))
SQ2 <- suppressWarnings(rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SA)); SQ2 <- SQ2[startsWith(ledger, gsub("\\\\", "/", SA))]
chk("P7 사슬이 끊긴(변조) 상설 원장은 자격 목록에 들어오지 않는다", nrow(SQ2) == 1L && identical(SQ2$round_id, "P1S90_t"))

## ═══ C 사슬 ═══════════════════════════════════════════════════════════════════
cat("C 사슬\n")
GEN_REG <- file.path(SB, "rx_generator.json"); Sys.setenv(RC_RXG_PATH = GEN_REG)
GD1 <- file.path(SB, "gen", "g1"); dir.create(GD1, recursive = TRUE); file.copy("04_Research/programs/P4_ASSEMBLY/_generator/g1/step.md", GD1)
rc_json_write(list(schema = "rx_generator_v1", current = "g1", versions = list(list(id = "g1", dir = GD1, files = rxg_files_md5(GD1), created_at = rc_now(), reason = "시험", evidence = list()))), GEN_REG)
LEDG <- file.path(SB, "q_judgment_ledger.json"); RVR <- file.path(SB, "rv"); OUTC <- file.path(SB, "round_outcomes.jsonl")
rvw <- function(id, role, trigger, round, file) { dir.create(dirname(file.path(RVR, file)), recursive = TRUE, showWarnings = FALSE); writeLines("리뷰", file.path(RVR, file))
  list(id = id, at = "x", role = role, trigger = trigger, file = file, round = round, challenges = list()) }
SFP <- "04_Research/programs/_supervision/superfan/"
REVS <- list()
for (cid in c("P4C90_e2e", "P4C91_next", "P4C92_charter", "P4C93_r7", "P4C94_r7mut")) { tg <- sub("_.*$", "", cid)
  REVS <- c(REVS, list(rvw(paste0("P1-", tg), "philosophy", "P1", cid, sprintf("%sphilosophy/20261110_1200_P1_%s.md", SFP, tg)),
                       rvw(paste0("T1-", tg), "judgment", "T1", cid, sprintf("%s20261110_1200_T1_%s.md", SFP, tg)),
                       rvw(paste0("P2-", tg), "philosophy", "P2", cid, sprintf("%sphilosophy/20261110_1300_P2_%s.md", SFP, tg)),
                       rvw(paste0("T2-", tg), "judgment", "T2", cid, sprintf("%s20261110_1300_T2_%s.md", SFP, tg)))) }
rc_json_write(list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = REVS, challenges = list()), LEDG)
CS <- file.path(SB, "cells"); dir.create(CS)
wspec <- function(nm, s) { p <- file.path(CS, paste0(nm, ".json")); rc_json_write(s, p); p }
BS <- list(code = "B0", label = "기저", fixed_axes = list(long_only = TRUE, n_max = 25L, commission_bps = 15L, liq_adv20_min = 2e8, measurement_axis = "all_hyg_px1000_2000_v1"),
           base_signal = list(kind = "engine", path = item("ok", A_OK)$engine_path), base_weight = 0.5, factors = list(), weighting = list(kind = "ew"), universe = list(kind = "all_hyg"))
BASE_CELL <- wspec("base", BS)
RULES <- list(
  list(id = "improve", type = "threshold", label = "보는 창 S 개선", metric = "dS_vis", op = ">=",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.tie_eps", source = "tie_eps 승계(시험)"),
  list(id = "uc_floor", type = "threshold", label = "상승 포착 하한", metric = "uc_vis", op = ">=", value_ref = "06_Registry/behavior_card.json::uc_floor", source = "헌장(시험)"),
  list(id = "crisis_no_worse", type = "threshold", label = "위기 하락 포착 비악화", metric = "d_dd_capture_median_vis", op = "<=", value = 0, basis = "정의", source = "정의"),
  list(id = "bull_segments", type = "threshold", label = "강세 구간별 참여(N1)", metric = "uc_seg_ok_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 4 · 7 · 24"),
  list(id = "deep_crisis", type = "threshold", label = "깊은 위기 과반 비악화(N2)", metric = "deep_crisis_nonworse_share_vis", op = ">", value_ref = "06_Registry/behavior_card.json::majority_share",
       source = "헌장 §5 빈칸 2 · 23"))
EPS <- rc_ref_value(RULES[[1]]$value_ref)
BUD <- list(max_steps = 6L, max_steps_source = "시험", noise_k = 2L, noise_k_source = "시험")
## 보는 창 지표 대체(산출 이름별) — 실제 계약 계산은 test_round_core_v1_p4_chain.R B 절이 본다 · 헌장 지표 재료 = 합성 강세 4 · 위기 4(전부 보는 창)
FB <- function(up = 1) data.table(start_ym = c("2003-04", "2005-01", "2009-03", "2016-02"), end_ym = c("2004-03", "2007-10", "2010-12", "2017-10"), up_capture = up)
FC <- function(dd = 1, rec = 100) data.table(peak_date = c("2002-04-18", "2008-05-16", "2011-05-02", "2020-01-22"), trough_date = c("2002-09-30", "2008-10-24", "2011-09-26", "2020-03-19"),
                                            bm_dd = c(0.25, 0.50, 0.20, 0.35), dd_capture = dd, st_recovery_obs = rec, st_recovery_censored = FALSE)
mkm <- function(S, uc = 0.60, dd = 0.50, up = 1, crdd = 1, cdar = 0.3, bu = 1, bd = 0.8, worst = -0.02, rec = 100, tabs = TRUE)
  c(list(S_vis = S, uc_vis = uc, dd_capture_median_vis = dd, calmar_vis = 1, port_t_vis = 1, cagr_vis = 0.1, sharpe_vis = 1,
         mdd_vis = 0.2, window = c("2000-01-31", TAU), cdar_vis = cdar, beta_up_vis = bu, beta_down_vis = bd, worst_name_contrib_deep_vis = worst),
    if (tabs) list(bull_vis = FB(up), crises_vis = FC(crdd, rec)) else list())
STUB <- list(lane_ok = mkm(1), m_base = mkm(1), m_k1 = mkm(1 + 2 * EPS), m_k2 = mkm(1 + 2 * EPS + EPS / 10), m_k4 = mkm(1 + 2 * EPS - EPS / 10),
             m2_base = mkm(1), m2_k1 = mkm(0.5))
mfun <- function(artifacts, root, tau, ...) STUB[[basename(artifacts)]] %||% stop("지표 대체 없음: ", basename(artifacts))
RUN <- new.env(); RUN$n <- 0L
runner_to <- function(nm, grade = "C") function(spec_path, code, out_json, log_dir, root, role) {
  RUN$n <- RUN$n + 1L; RUN$last <- rc_json_read(spec_path); d <- mk_art(nm, grade)
  rc_json_write(list(n = 1L, code = code, ok = TRUE, grade = grade, essence = list(net_sharpe = 9.99), artifacts = d), out_json); 0L }
runner_crash <- function(spec_path, code, out_json, log_dir, root, role) { RUN$n <- RUN$n + 1L; stop("워커 크래시(주입)") }
free <- function(root) list(state = "free", reason = "", lock = "", blocking = FALSE)
FP <- function() "fp"; VINT <- function(root) list(id = "v1", n_repairs = 1L); VINT2 <- function(root) list(id = "v2", n_repairs = 2L)
bm_ <- function(cd, nm, fr = FRESH, vi = VINT) rc_p4_base_measure(cd, ROOT, runner = runner_to(nm), barrier = free, fingerprint = FP, vintage = vi, metrics_fun = mfun, freshness = fr)
sm_ <- function(cd, k, run, fr = FRESH, vi = VINT) rc_p4_step_measure(cd, k, ROOT, runner = run, barrier = free, fingerprint = FP, vintage = vi, freshness = fr)
dec <- function(cd, k) rc_p4_step_decide(cd, k, root = ROOT, metrics_fun = mfun)
nled <- function(cd) rc_p4_steps_verify(cd)$n
H <- "낙폭 브레이크가 깊은 위기의 하락 포착을 낮춘다"; M <- "보유월 시작 전 낙폭 신호로 노출을 줄여 위기 경로의 손실을 자른다"
open_ <- function(cd, k, block, cell, parent, h = H) rc_p4_step_open(cd, k, h, M, block, cell, parent, "g1", root = ROOT, pool = POOL)

CD <- file.path(SB, "chain", "P4C90_e2e")
chk("C1 사슬 판 생성(상설 아닌 등록부 등급 경로 기저 · 검사 통과)", identical(err_of(rc_p4_chain_new(CD, "P4C90_e2e", "engine:E_ok", POOL, BASE_CELL, RULES, BUD)), ""))
chk("C1b 규칙 변경 수혜 기저 = 사슬 판 거부", grepl("자격 미달", err_of(rc_p4_chain_new(file.path(SB, "chain", "x"), "P4C89_x", "engine:E_srb", POOL, BASE_CELL, RULES, BUD))))
reg_ <- function(p1 = "P1-P4C90", t1 = "T1-P4C90") err_of(rc_p4_chain_register(CD, POOL, ROOT, metrics_fun = mfun, p1 = p1, t1 = t1, ledger = LEDG, review_root = RVR))
chk("C2 영수증 없음 · 남의 사슬 영수증 = 등록 거부 · 원장 무기록", grepl("영수증", reg_(p1 = NULL)) && grepl("수령 목록|대상", reg_(p1 = "P1-P4C91")) && nled(CD) == 0L)
chk("C3 등록(영수증 일치)", identical(reg_(), ""))
n0 <- nled(CD); RUN$n <- 0L; b_st <- bm_(CD, "m_base", fr = STALE)
chk("C4 데이터 낡음 = 기준 칸 측정 거부(data_stale) · 러너 미호출 · 원장 무기록", identical(b_st$status, "data_stale") && RUN$n == 0L && nled(CD) == n0 && grepl("rawdata", b_st$reason))
mu <- mut_src("  if (!isTRUE(fr$ok)) {", "  if (FALSE) {"); sys.source(mu$path, envir = globalenv())
CDM <- file.path(SB, "chain", "P4C88_mut"); invisible(rc_p4_chain_new(CDM, "P4C88_mut", "engine:E_ok", POOL, BASE_CELL, RULES, BUD))
invisible(.rcp4_append(CDM, list(event = "chain_registered", chain_id = "P4C88_mut", spec_md5 = rc_md5(rc_p4_spec_path(CDM)), rules_resolved = rc_rules_resolve(RULES, ROOT))))
RUN$n <- 0L; bmm <- bm_(CDM, "m_base", fr = STALE); restore_p4()
chk("C4b 돌연변이(신선도 검사 끔 · 치환 1곳) → 낡은 자료로 측정된다(검사가 실제로 막고 있었다)", mu$n == 1L && identical(bmm$status, "measured") && RUN$n == 1L)
CLM <- file.path(CD, "measure", "k0.claim"); dir.create(CLM, recursive = TRUE); writeLines(c(as.character(Sys.getpid()), "x"), file.path(CLM, "pid"))
RUN$n <- 0L; b_busy <- bm_(CD, "m_base")
chk("C5 살아 있는 점유(다른 측정 진행 중) = busy · 러너 미호출 · 원장 무기록 · 남의 점유 유지", identical(b_busy$status, "busy") && RUN$n == 0L && dir.exists(CLM) && nled(CD) == n0)
writeLines(c("999999", "x"), file.path(CLM, "pid"))
RUN$n <- 0L; b_ok <- bm_(CD, "m_base")
chk("C6 크래시 잔재(죽은 pid 점유) 인계 → 기준 칸 측정 · 점유 해제 · 다시 = already", identical(b_ok$status, "measured") && RUN$n == 1L && !dir.exists(CLM) &&
      identical(bm_(CD, "m_base")$status, "already") && RUN$n == 1L, b_ok$status)
## 걸음 1(채택)
s1 <- BS; s1$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_q"); C1 <- wspec("k1", s1)
chk("C7 가설에 τ_D 뒤 날짜 = 열기 거부", grepl("τ_D", err_of(open_(CD, 1, "regime_exposure", C1, 0, h = "2024-08-05 급락을 막는다"))))
chk("C8 걸음 1 열기", identical(err_of(open_(CD, 1, "regime_exposure", C1, 0)), ""))
rec_open1 <- Filter(function(r) identical(r$event, "step_open"), rc_p4_steps_read(CD))[[1]]
chk("C9 잠금 안 재확인 — 같은 k 를 다른 프로세스가 늦게 덧붙이면 거부(원장 그대로)",
    grepl("이미 열렸다", err_of(.rcp4_append(CD, rec_open1[setdiff(names(rec_open1), c("schema", "at", "prev"))]))) && nled(CD) == n0 + 2L)
mu <- mut_src("rec, guard = .rcp4_unique_guard(rec)) {", "rec, guard = NULL) {"); sys.source(mu$path, envir = globalenv())
CDG <- file.path(SB, "chain_g"); dir.create(CDG); file.copy(c(rc_p4_spec_path(CD), rc_p4_steps_path(CD)), CDG)
dup <- err_of(.rcp4_append(CDG, rec_open1[setdiff(names(rec_open1), c("schema", "at", "prev"))])); restore_p4()
chk("C9b 돌연변이(재확인 끔 · 치환 1곳) → 같은 걸음이 두 번 들어간다(재확인이 실제로 막고 있었다)", mu$n == 1L && identical(dup, "") &&
      length(Filter(function(r) identical(r$event, "step_open"), rc_p4_steps_read(CDG))) == 2L)
## 두 프로세스 동시 측정(같은 걸음) — 하나만 잰다
CH <- file.path(SB, "child.R")
writeLines(c(sprintf("setwd('%s'); source('04_Research/programs/_lib/round_core/v1/load.R')", ROOT),
             "a <- commandArgs(trailingOnly = TRUE)",
             "run <- function(spec_path, code, out_json, log_dir, root, role) { Sys.sleep(4); d <- file.path(dirname(log_dir), 'kid_art'); dir.create(d, showWarnings = FALSE); file.copy(list.files(a[4], full.names = TRUE), d)",
             "  jsonlite::write_json(list(ok = TRUE, artifacts = d), out_json, auto_unbox = TRUE); 0L }",
             "r <- rc_p4_step_measure(a[1], 1, a[2], runner = run, barrier = function(root) list(blocking = FALSE), fingerprint = function() 'fp',",
             "                        vintage = function(root) list(id = 'v1', n_repairs = 1L), freshness = function(root) list(ok = TRUE, state = 'fresh'))",
             "writeLines(r$status, a[3])"), CH)
ev <- tempfile(); writeLines("", ev); old_rev <- Sys.getenv("R_ENVIRON_USER"); Sys.setenv(R_ENVIRON_USER = ev)
o1 <- file.path(SB, "kid1.txt"); o2 <- file.path(SB, "kid2.txt")
system2("Rscript", c(shQuote(CH), shQuote(CD), shQuote(ROOT), shQuote(o1), shQuote(A_OK)), wait = FALSE, stdout = FALSE, stderr = FALSE)
system2("Rscript", c(shQuote(CH), shQuote(CD), shQuote(ROOT), shQuote(o2), shQuote(A_OK)), wait = FALSE, stdout = FALSE, stderr = FALSE)
t0 <- Sys.time(); while (!(file.exists(o1) && file.exists(o2)) && difftime(Sys.time(), t0, units = "secs") < 90) Sys.sleep(0.5)
Sys.setenv(R_ENVIRON_USER = old_rev)
ks <- sort(c(if (file.exists(o1)) readLines(o1) else "none", if (file.exists(o2)) readLines(o2) else "none"))
nm1 <- length(Filter(function(r) identical(r$event, "step_measured"), rc_p4_steps_read(CD)))
chk("C10 두 프로세스가 같은 걸음을 동시에 잰다 → 하나 measured · 하나 busy(또는 already) · 원장 step_measured 1줄", identical(ks[2], "measured") && ks[1] %in% c("busy", "already") &&
      nm1 == 1L && rc_p4_steps_verify(CD)$ok, paste(ks, collapse = ","))
## 판정은 자식이 잰 산출(kid_art) — 지표 대체를 그 이름에 건다
STUB$kid_art <- STUB$m_k1
r1 <- tryCatch(dec(CD, 1), error = function(e) e)
chk("C11 걸음 1 채택(dS ≥ 여유 · 상승 포착 · 위기 비악화) · r7 signal · 머리 = 1", !inherits(r1, "error") && identical(r1$decision, "accept") && identical(r1$r7, "signal") &&
      identical(.rcp4_state(CD, ROOT)$head_k, 1L), if (inherits(r1, "error")) conditionMessage(r1) else unlist(r1$reasons))
## 걸음 2(기각 · 잡음) — 칸 사양 변경 주입 · 판 표식 변경 주입
s2 <- s1; s2$weighting <- list(kind = "inv_vol", window = 60L); C2 <- wspec("k2", s2)
invisible(open_(CD, 2, "weighting", C2, 1))
cb <- readBin(C2, "raw", file.info(C2)$size); cat(" ", file = C2, append = TRUE)
chk("C12 열린 뒤 칸 사양 변경 = 측정 거부(R2)", grepl("R2", err_of(sm_(CD, 2, runner_to("m_k2"))))); writeBin(cb, C2)
n_v <- nled(CD); vc <- sm_(CD, 2, runner_to("m_k2"), vi = VINT2)
chk("C13 팩터 DB 판 표식이 기준 칸과 다르면 측정 거부(vintage_changed · 원장 무기록)", identical(vc$status, "vintage_changed") && nled(CD) == n_v)
invisible(sm_(CD, 2, runner_to("m_k2"))); r2 <- dec(CD, 2)
chk("C14 걸음 2 기각(개선 < 여유) · r7 noise", identical(r2$decision, "reject") && identical(r2$r7, "noise"))
## 원장 변조 주입
SP <- rc_p4_steps_path(CD); LL <- readLines(SP, encoding = "UTF-8", warn = FALSE); LT <- LL; LT[3] <- sub("낙폭", "급등", LT[3], fixed = TRUE)
writeBin(charToRaw(paste0(paste(LT, collapse = "\n"), "\n")), SP)
chk("C15 원장 중간 줄 변조 → 사슬 검사 실패 · 걸음 열기 · 측정 · 닫기 모두 거부", sum(LT != LL) == 1L && !rc_p4_steps_verify(CD)$ok &&
      grepl("끊겼다", err_of(open_(CD, 3, "defense_sleeve", C2, 1))) && grepl("끊겼다", err_of(sm_(CD, 3, runner_to("x")))))
writeBin(charToRaw(paste0(paste(LL, collapse = "\n"), "\n")), SP)
## 걸음 3(측정 실패 → 포기)
s3 <- s1; s3$defense_sleeve <- list(kind = "cash_sleeve", share = 0.2); C3 <- wspec("k3", s3)
invisible(open_(CD, 3, "defense_sleeve", C3, 1))
RUN$n <- 0L; f1 <- sm_(CD, 3, runner_crash)
chk("C16 워커 크래시 = step_measure_failed(다시 잴 수 있다) · 1회로는 포기 거부", identical(f1$status, "failed") && RUN$n == 1L &&
      grepl("다시 잰다", err_of(rc_p4_step_abandon(CD, 3, "결정론적 실패", ROOT))))
invisible(sm_(CD, 3, runner_crash))
chk("C17 포기 사유 τ_D 날짜 = 거부 · 실패 2회 뒤 포기(기각 · 산출 없음 · r7 NA)", grepl("τ_D", err_of(rc_p4_step_abandon(CD, 3, "2024-01 이후 실패", ROOT))) &&
      identical(err_of(rc_p4_step_abandon(CD, 3, "칸 엔진이 이 방어 소매를 받지 못한다", ROOT)), "") &&
      isTRUE(tail(.rcp4_state(CD, ROOT)$results, 1)[[1]]$abandoned) && identical(.rcp4_state(CD, ROOT)$noise_streak, 1L))
## 걸음 4(기각 · 잡음) → 연속 잡음 2 = 예산 종료
s4 <- s1; s4$rebalance <- list(freq = "monthly_mid"); C4 <- wspec("k4", s4)
invisible(open_(CD, 4, "rebalance", C4, 1)); invisible(sm_(CD, 4, runner_to("m_k4"))); r4 <- dec(CD, 4)
s5 <- s1; s5$universe <- list(kind = "all_hyg", min_px = 2000); C5 <- wspec("k5", s5)
chk("C18 걸음 4 기각 · 잡음 → 연속 잡음 2 ≥ K 2 = 다음 걸음 열기 거부(예산 소진 · 포기한 걸음은 연속을 끊지 않는다)", identical(r4$r7, "noise") &&
      identical(.rcp4_state(CD, ROOT)$noise_streak, 2L) && grepl("예산 소진", err_of(open_(CD, 5, "universe", C5, 1))))
## 생성기 작업 디렉터리 · 사슬 디렉터리의 사람 쪽 파일
WD <- file.path(SB, "wd1"); wf <- tryCatch(rc_p4_generator_workdir(CD, WD, ROOT, pool = POOL, outcomes_path = OUTC, toolbox_md = "# 도구 상자(시험)"), error = function(e) e)
wtxt <- if (inherits(wf, "error")) "" else paste(unlist(lapply(wf, readLines, warn = FALSE, encoding = "UTF-8")), collapse = "\n")
chk("C19 생성기 작업 디렉터리 = 정확히 네 파일 · τ_D 뒤 날짜 없음 · 등급 · 워커 결과 수치 없음 · 부모 = 머리(걸음 1) 칸",
    !inherits(wf, "error") && setequal(list.files(WD), c("design_input.md", "investment_philosophy_charter.md", "toolbox.md", "parent_cell_spec.json")) &&
      !length(rc_after_tau_leaks(wtxt, TAU)) && !grepl("9.99", wtxt, fixed = TRUE) && !grepl("\"(essence_grade|grade)\"\\s*:", wtxt, perl = TRUE) && identical(rc_json_read(file.path(WD, "parent_cell_spec.json"))$overlay$kind, "dd_brake"),
    if (inherits(wf, "error")) conditionMessage(wf) else "")
mj <- paste(readLines(file.path(CD, "measure", "k2.json"), warn = FALSE), collapse = "")
chk("C20 (경계 기록) 사슬 디렉터리 measure/k<k>.json 에는 워커 결과(전기간 등급 · 수치)가 있다 — 그래서 작업 디렉터리를 따로 만든다 · 사슬 안 작업 디렉터리 거부",
    grepl("\"grade\"", mj) && grepl("9.99", mj, fixed = TRUE) && grepl("밖", err_of(rc_p4_generator_workdir(CD, file.path(CD, "wd"), ROOT, toolbox_md = "x"))))

## ═══ N 헌장 빈칸 집행(채택 규칙 v2 — N1~N5 · r7 · 현금 기계) ══════════════════════════
cat("N 헌장 빈칸 집행\n")
RULES_C <- c(RULES, list(
  list(id = "cdar_no_worse", type = "threshold", label = "낙폭 경로 비악화(N3)", metric = "d_cdar_vis", op = "<=", value = 0, basis = "정의 — 비악화 = 부모 이하", source = "헌장 §5 빈칸 5 · 18"),
  list(id = "concentration", type = "threshold", label = "깊은 위기 한 종목 기여(N4)", metric = "worst_name_contrib_deep_vis", op = ">",
       value_ref = "04_Research/programs/P3_CONSTRUCTION/P3R03_advanced_construction/prereg.json::final_selection_rule.single_name_loss_floor", source = "헌장 §5 빈칸 1(−10%)"),
  list(id = "beta_asym", type = "threshold", label = "노출 블록 β 비대칭(N5)", metric = "beta_asym_ok_vis", op = ">=", value = 1, basis = "정의 — 1 = 하락 β < 상승 β 또는 해당 없음", source = "헌장 §5 빈칸 3 · 8")))
chk("N0 새 사슬 판 = rules_version v2 · 필수 N1 · N2 없는 규칙 = 사슬 판 거부 · 옛 판(표식 없음) = v1 판독",
    grepl("uc_seg_ok_share_vis", err_of(rc_p4_chain_new(file.path(SB, "chain", "nx"), "P4C87_nx", "engine:E_ok", POOL, BASE_CELL, RULES[1:3], BUD))) &&
      identical(rc_json_read(rc_p4_spec_path(CD))$rules_version, "p4_rules_v2") && identical(.rcp4_rules_version(list()), "p4_rules_v1") &&
      identical(RC_P4_REQUIRED$p4_rules_v1, c("dS_vis", "uc_vis", "d_dd_capture_median_vis")))
SEEN <- new.env(); SEEN$conc <- FALSE
mfunC <- function(artifacts, root, tau, concentration = FALSE, ...) { if (isTRUE(concentration)) SEEN$conc <- TRUE; mfun(artifacts, root, tau) }
CDC <- file.path(SB, "chain", "P4C92_charter")
invisible(rc_p4_chain_new(CDC, "P4C92_charter", "engine:E_ok", POOL, BASE_CELL, RULES_C, list(max_steps = 8L, max_steps_source = "시험", noise_k = 2L, noise_k_source = "시험")))
invisible(rc_p4_chain_register(CDC, POOL, ROOT, metrics_fun = mfunC, p1 = "P1-P4C92", t1 = "T1-P4C92", ledger = LEDG, review_root = RVR))
STUB$c_base <- mkm(1); invisible(bm_(CDC, "c_base"))
S2 <- 1 + 2 * EPS
STUB$c_k1 <- mkm(S2, up = c(1, 0.5, 0.5, 1)); STUB$c_k2 <- mkm(S2, dd = 0.40, crdd = c(0.5, 1.2, 0.5, 1.2)); STUB$c_k3 <- mkm(S2, cdar = 0.4)
STUB$c_k4 <- mkm(S2, worst = -0.15); STUB$c_k5 <- mkm(S2, bu = 1.0, bd = 1.1); STUB$c_k6 <- mkm(S2, bu = 1.0, bd = 1.1)
cs <- function(nm, f) { s <- BS; s <- f(s); wspec(nm, s) }
CC <- list(k1 = list("weighting", cs("c1", function(s) { s$weighting <- list(kind = "inv_vol", window = 60L); s })),
           k2 = list("construction", cs("c2", function(s) { s$cap_core <- list(k = 5L, satellite = "floor"); s })),
           k3 = list("rebalance", cs("c3", function(s) { s$rebalance <- list(freq = "monthly_mid"); s })),
           k4 = list("universe", cs("c4", function(s) { s$universe <- list(kind = "all_hyg", min_px = 2000); s })),
           k5 = list("regime_exposure", cs("c5", function(s) { s$overlay <- list(kind = "dd_brake", arm_id = "dd_brake_q"); s })),
           k6 = list("weighting", cs("c6", function(s) { s$weighting <- list(kind = "inv_vol", window = 120L); s })))
stepC <- function(k, decide = TRUE) { b <- CC[[paste0("k", k)]]; invisible(rc_p4_step_open(CDC, k, H, M, b[[1]], b[[2]], 0L, "g1", root = ROOT, pool = POOL))
  invisible(sm_(CDC, k, runner_to(paste0("c_k", k)))); if (decide) rc_p4_step_decide(CDC, k, root = ROOT, metrics_fun = mfunC) else invisible(NULL) }
rsn_has <- function(r, id) any(startsWith(unlist(r$reasons), paste0(id, ":")))
d1 <- stepC(1)
chk("N1 강세 구간 둘을 통째로 놓친 걸음(중앙값 상승 포착 0.60 ≥ 하한 통과) → 구간별 참여 미달로 기각 · 기록 = 짝 4", identical(d1$decision, "reject") &&
      rsn_has(d1, "bull_segments") && !rsn_has(d1, "uc_floor") && identical(as.integer(d1$charter$n1_pairs), 4L) && isTRUE(all.equal(.rcp4_num(d1$table$uc_seg_ok_share_vis), 0.5)),
    unlist(d1$reasons))
d2 <- stepC(2)
chk("N2 깊은 위기(시장 낙폭 ≥ 중앙 = 2008 · 2020)에서만 악화 · 중앙값은 개선 → 깊은 위기 과반으로 기각", identical(d2$decision, "reject") && rsn_has(d2, "deep_crisis") &&
      !rsn_has(d2, "crisis_no_worse") && isTRUE(all.equal(.rcp4_num(d2$table$deep_crisis_nonworse_share_vis), 0)), unlist(d2$reasons))
cp_chain <- function(nm) { d <- file.path(SB, nm); dir.create(d); file.copy(list.files(CDC, full.names = TRUE), d, recursive = TRUE); d }
mut_decide <- function(from, to, k) { mu <- mut_src(from, to); dd <- cp_chain(sprintf("cdc_mut_k%d", k)); sys.source(mu$path, envir = globalenv())
  r <- tryCatch(rc_p4_step_decide(dd, k, root = ROOT, metrics_fun = mfunC), error = function(e) list(decision = paste("error:", conditionMessage(e)))); restore_p4(); list(n = mu$n, r = r) }
invisible(stepC(3, decide = FALSE)); m3 <- mut_decide('d_cdar_vis = g(m, "cdar_vis") - g(pm, "cdar_vis")', 'd_cdar_vis = g(pm, "cdar_vis") - g(m, "cdar_vis")', 3); d3 <- dec(CDC, 3)
d3 <- rc_p4_step_decide
d3 <- NULL; d3 <- tryCatch(Filter(function(r) identical(r$event, "step_result") && identical(as.integer(r$k), 3L), rc_p4_steps_read(CDC))[[1]], error = function(e) NULL)
chk("N3 낙폭 경로(CDaR 0.4 > 부모 0.3) = 기각 · 돌연변이(부호 뒤집기 · 치환 1곳) = 채택(검사가 막고 있었다)", isTRUE(rsn_has(d3, "cdar_no_worse")) &&
      identical(d3$decision, "reject") && m3$n == 1L && identical(m3$r$decision, "accept"), paste(unlist(d3$reasons), "|", m3$r$decision))
invisible(stepC(4, decide = FALSE)); SEEN$conc <- FALSE
m4 <- mut_decide('worst_name_contrib_deep_vis = g(m, "worst_name_contrib_deep_vis"),', 'worst_name_contrib_deep_vis = 0,', 4); invisible(dec(CDC, 4))
d4 <- Filter(function(r) identical(r$event, "step_result") && identical(as.integer(r$k), 4L), rc_p4_steps_read(CDC))[[1]]
chk("N4 깊은 위기 한 종목 기여 −15% < −10% = 기각 · 규칙이 쓰면 판정이 concentration = TRUE 로 지표를 부른다 · 돌연변이 = 채택",
    identical(d4$decision, "reject") && rsn_has(d4, "concentration") && isTRUE(SEEN$conc) && m4$n == 1L && identical(m4$r$decision, "accept"), paste(unlist(d4$reasons), "|", m4$r$decision))
TL <- data.table(peak_date = c("2008-05-16", "2020-01-22", "2002-04-18"), contrib = c(-0.15, -0.03, -0.01))
mc <- mut_src("dk <- cr[abs(as.numeric(bm_dd)) >= stats::median", "dk <- cr[abs(as.numeric(bm_dd)) < stats::median")
v_ok <- .rcp4_conc(TL, FC()); v_miss <- .rcp4_conc(TL[peak_date != "2020-01-22"], FC())
sys.source(mc$path, envir = globalenv()); v_mut <- .rcp4_conc(TL, FC()); restore_p4()
chk("N4b 집중 지표(pair.R::rc_top_loss) — 깊은 위기 최솟값 −0.15 · 깊은 위기가 표에 빠지면 NA(미측정) · 돌연변이(얕은 위기 선택) = 다른 값", isTRUE(all.equal(v_ok, -0.15)) &&
      is.na(v_miss) && mc$n == 1L && !isTRUE(all.equal(v_mut, -0.15)))
invisible(stepC(5, decide = FALSE)); m5 <- mut_decide("as.numeric(bd < bu)", "as.numeric(bd > bu)", 5); invisible(dec(CDC, 5))
d5 <- Filter(function(r) identical(r$event, "step_result") && identical(as.integer(r$k), 5L), rc_p4_steps_read(CDC))[[1]]
d6 <- stepC(6)
chk("N5 노출 블록(regime_exposure) 하락 β 1.1 > 상승 β 1.0 = 기각 · 같은 β 의 비노출 블록(weighting) = 해당 없음 → 채택 · 돌연변이 = 노출 블록 채택",
    identical(d5$decision, "reject") && rsn_has(d5, "beta_asym") && identical(d6$decision, "accept") && m5$n == 1L && identical(m5$r$decision, "accept"),
    paste(unlist(d5$reasons), "|", d6$decision, "|", m5$r$decision))
STUB$c_k7 <- mkm(S2 + 2 * EPS, tabs = FALSE)
invisible(rc_p4_step_open(CDC, 7, H, M, "rebalance", cs("c7", function(s) { s$weighting <- list(kind = "inv_vol", window = 120L); s$rebalance <- list(freq = "monthly_mid"); s }), 6L, "g1",
                          root = ROOT, pool = POOL)); invisible(sm_(CDC, 7, runner_to("c_k7"))); d7 <- dec(CDC, 7)
chk("N6 재료(행동 카드 위기 · 강세 표) 없음 = N1 · N2 미측정 = 기각(fail-closed)", identical(d7$decision, "reject") && rsn_has(d7, "bull_segments") && rsn_has(d7, "deep_crisis") &&
      any(grepl("미측정", unlist(d7$reasons))))
## r7 v2 — 악화 연속 K = 예산 종료 · 돌연변이(옛 |dS| 규칙) = 종료 안 함
r7run <- function(cid) { cd <- file.path(SB, "chain", cid); tg <- sub("_.*$", "", cid)
  invisible(rc_p4_chain_new(cd, cid, "engine:E_ok", POOL, BASE_CELL, RULES, BUD))
  invisible(rc_p4_chain_register(cd, POOL, ROOT, metrics_fun = mfun, p1 = paste0("P1-", tg), t1 = paste0("T1-", tg), ledger = LEDG, review_root = RVR))
  invisible(bm_(cd, "w_base"))
  for (k in 1:2) { sp <- cs(sprintf("%s_w%d", tg, k), function(s) { s$weighting <- list(kind = "inv_vol", window = 30L * k); s })
    invisible(rc_p4_step_open(cd, k, H, M, "weighting", sp, 0L, "g1", root = ROOT, pool = POOL)); invisible(sm_(cd, k, runner_to(sprintf("w_k%d", k)))); invisible(dec(cd, k)) }
  sp3 <- cs(sprintf("%s_w3", tg), function(s) { s$weighting <- list(kind = "inv_vol", window = 200L); s })
  list(st = .rcp4_state(cd, ROOT), open3 = err_of(rc_p4_step_open(cd, 3, H, M, "weighting", sp3, 0L, "g1", root = ROOT, pool = POOL))) }
STUB$w_base <- mkm(1); STUB$w_k1 <- mkm(0.5); STUB$w_k2 <- mkm(0.5)
R7 <- r7run("P4C93_r7")
mr <- mut_src('    (if (ds >= abs(mg)) "signal" else "noise")', '    (if (abs(ds) >= abs(mg)) "signal" else "noise")'); sys.source(mr$path, envir = globalenv())
R7M <- r7run("P4C94_r7mut"); restore_p4()
chk("N7 r7 v2 — 크게 나빠진 걸음 2번(dS −0.5) = r7 noise · r7_detail worse · 연속 2 ≥ K 2 = 다음 걸음 열기 거부 · 돌연변이(옛 |dS| 규칙 · 치환 1곳) = signal · 거부 안 함",
    all(vapply(R7$st$results, function(r) identical(r$r7, "noise") && identical(r$r7_detail, "worse"), TRUE)) && grepl("예산 소진", R7$open3) &&
      mr$n == 1L && identical(R7M$st$noise_streak, 0L) && identical(R7M$open3, ""), paste(R7$open3, "|", R7M$open3))
## 기저 풀 현금 기계(빈칸 24) — 상설 판정 기록의 보는 창 상승 포착
mkq <- function(code, uc) { e <- mk_eng(paste0("std_", code)); data.table(round_id = "P1S90_t", edition = 1L, code = code, engine = code, engine_path = e, engine_md5 = rc_md5(e),
                                                                         engine_same = TRUE, artifacts = A_STD, paper_key = paste0("9909.", code), verdict_at = "x", ledger = "t", uc_vis = uc) }
SQC <- rbind(mkq("cm_lo", 0.40), mkq("cm_hi", 0.70), mkq("cm_na", NA_real_))
PC <- rc_p4_base_pool(ROOT, registry_path = REG, standing = SQC, fdv_ledger_path = FDVL)
mcm <- mut_src('if (identical(cmach, "yes")) {', "if (FALSE) {"); sys.source(mcm$path, envir = globalenv())
PCM <- rc_p4_base_pool(ROOT, registry_path = REG, standing = SQC, fdv_ledger_path = FDVL); restore_p4()
chk("N8 기저 풀 현금 기계 — 보는 창 상승 포착 0.40 < 0.55 = cash_machine 제외 · 0.70 = 자격 · 값 없음(상설 기록 · 등급 경로) = unknown(제외 안 함) · 돌연변이 = 0.40 도 자격",
    identical(PC[standing_code == "cm_lo"]$reason, "cash_machine") && isTRUE(PC[standing_code == "cm_hi"]$eligible) && identical(PC[standing_code == "cm_hi"]$cash_machine, "no") &&
      isTRUE(PC[standing_code == "cm_na"]$eligible) && identical(PC[standing_code == "cm_na"]$cash_machine, "unknown") && identical(PC[key == "engine:E_ok"]$cash_machine, "unknown") &&
      mcm$n == 1L && isTRUE(PCM[standing_code == "cm_lo"]$eligible))

## ═══ Z 닫기 · 재채점 · 관문 · 결과 원장 · 다음 사슬 ════════════════════════════════
cat("Z 닫기\n")
FSR <- file.path(SB, "fake_sr.R"); SRLOG <- file.path(SB, "sr_log.txt"); FGT <- file.path(SB, "fake_gate.R"); GLOG <- file.path(SB, "gate_log.txt")
writeLines(c("sr_regrade <- function(candidate_dir, trial_dirs, root = NULL, write = FALSE, ...) {",
             sprintf("  writeLines(c(candidate_dir, trial_dirs, as.character(write)), '%s')", SRLOG),
             "  list(status = 'ok', grade_before = 'B', grade_after = Sys.getenv('T_SR_GRADE', 'A'), gate_ok = TRUE, reason = 'fake', written = write) }"), FSR)
writeLines(c(sprintf("rcg_route <- function(candidate_dir, strategy_id, spec_path, root, write) { cat('route', candidate_dir, strategy_id, '\\n', file = '%s', append = TRUE)", GLOG),
             "  list(action = 'publish', eligible = TRUE, codes = character(0), path = file.path(candidate_dir, 'judge_request.eligible.json')) }",
             sprintf("rcg_withdraw <- function(candidate_dir, grade, write) { cat('withdraw', candidate_dir, grade, write, '\\n', file = '%s', append = TRUE); list(withdrawn = isTRUE(write), pending = FALSE) }", GLOG)), FGT)
cl_ <- function(cd, cid, note = "오버레이가 기준 칸을 넘었고 뒤 걸음은 잡음 이내", probes = c("다음 탐침 하나", "다음 탐침 둘"), ...) { tg <- sub("_.*$", "", cid)
  rc_p4_close(cd, note, probes = probes, lessons = "교훈 하나", root = ROOT, outcomes_path = OUTC, philosophy_p2 = paste0("P2-", tg), superfan_t2 = paste0("T2-", tg),
              ledger = LEDG, review_root = RVR, regrade_file = FSR, gate_file = FGT, register_file = file.path(SB, "no_register.R"), ...) }
chk("Z1 닫기 영수증 없음 = 거부 · 글에 τ_D 뒤 날짜 = 거부(원장 무기록)",
    grepl("영수증", err_of(rc_p4_close(CD, "n", probes = c("a", "b"), root = ROOT, outcomes_path = OUTC, ledger = LEDG, review_root = RVR, regrade_file = FSR, gate_file = FGT))) &&
      grepl("정보 경계", err_of(cl_(CD, "P4C90_e2e", note = "2024-08 급락에서 통했다"))) && !file.exists(OUTC))
## 닫기 중간 크래시(결과 원장은 썼는데 chain_closed 전) → 재진입
orig_app <- .rcp4_append
assign(".rcp4_append", function(chain_dir, rec, ...) { if (identical(rec$event, "chain_closed")) stop("크래시(주입)"); orig_app(chain_dir, rec, ...) }, envir = globalenv())
z_crash <- err_of(cl_(CD, "P4C90_e2e", regrade_write = TRUE)); assign(".rcp4_append", orig_app, envir = globalenv())
n_out1 <- length(rc_outcomes_read(OUTC, program = "P4_ASSEMBLY"))
z <- tryCatch(cl_(CD, "P4C90_e2e", regrade_write = TRUE), error = function(e) e)
ST <- .rcp4_state(CD, ROOT); FZ <- rc_json_read(file.path(CD, "finalize.json")); srl <- readLines(SRLOG)
O <- rc_outcomes_read(OUTC, program = "P4_ASSEMBLY")
chk("Z2 닫기 중간 크래시 → 재진입: 결과 원장 1줄(중복 없음) · chain_closed 1줄 · 닫힘", grepl("크래시", z_crash) && n_out1 == 1L && !inherits(z, "error") &&
      length(O) == 1L && sum(vapply(ST$recs, function(r) identical(r$event, "chain_closed"), TRUE)) == 1L && ST$closed,
    if (inherits(z, "error")) conditionMessage(z) else "")
want_trials <- vapply(c(b_ok$artifacts, r1$artifacts, r2$artifacts, r4$artifacts), function(p) .rcp4_abs(p, ROOT), "")
chk("Z3 시행 집합 = 기준 칸 + 판정한 모든 걸음(채택 1 · 기각 2) · 포기 걸음 제외(n_abandoned 1) · 최종 후보 = 마지막 채택(걸음 1) · 쓰기 모드",
    setequal(srl[2:(length(srl) - 1L)], want_trials) && identical(srl[1], .rcp4_abs(r1$artifacts, ROOT)) && identical(tail(srl, 1), "TRUE") &&
      identical(as.integer(FZ$n_abandoned), 1L) && identical(as.integer(ST$recs[[length(ST$recs)]]$final_k), 1L), paste(srl, collapse = " | "))
gl <- readLines(GLOG)
chk("Z4 새 등급 A = 후보 관문 발행 경로(rcg_route · strategy_id = <사슬>_k1 · 크래시 재진입에서 같은 호출 1회 더 = 멱등 덮어쓰기) · 요약은 finalize.json 에만", length(gl) == 2L && all(grepl("^route .* P4C90_e2e_k1", gl)) &&
      identical(FZ$candidate_gate$action, "publish"))
oj <- .rcp4_js(O[[1]]); cj <- .rcp4_js(Filter(function(r) identical(r$event, "chain_closed"), ST$recs))
chk("Z5 결과 원장 · 사슬 원장에 등급 · 관문 판정이 새지 않는다(상태 문자열만) · 탐침 2 · 교훈 · τ_D 뒤 날짜 없음",
    identical(O[[1]]$extra$finalize$candidate_gate, "evaluated") && !grepl("publish|\"A\"|grade_after", oj) && !grepl("publish|grade_after", cj) &&
      length(O[[1]]$probes) == 2L && !length(rc_after_tau_leaks(O[[1]][setdiff(names(O[[1]]), "at")], TAU)))
chk("Z6 닫힌 사슬 — 다시 닫기 · 걸음 열기 · 측정 거부", grepl("닫힌", err_of(cl_(CD, "P4C90_e2e", regrade_write = TRUE))) && grepl("닫힌", err_of(open_(CD, 5, "universe", C5, 1))) &&
      grepl("닫힌", err_of(sm_(CD, 4, runner_to("x")))))
## 다음 사슬 — 설계 입력이 결과 원장을 읽는다 · 재채점 A 아님 = 요청 거두기
CD2 <- file.path(SB, "chain", "P4C91_next")
invisible(rc_p4_chain_new(CD2, "P4C91_next", "engine:E_ok", POOL, BASE_CELL, RULES, BUD))
invisible(rc_p4_chain_register(CD2, POOL, ROOT, metrics_fun = mfun, p1 = "P1-P4C91", t1 = "T1-P4C91", ledger = LEDG, review_root = RVR))
invisible(bm_(CD2, "m2_base"))
DI <- rc_p4_design_input(ROOT, CD2, pool = POOL, outcomes_path = OUTC)
chk("Z7 다음 사슬 설계 입력 = 결과 원장의 열린 탐침 · 교훈 · 앞 사슬 라벨에서 출발", grepl("P4C90_e2e#1", DI, fixed = TRUE) && grepl("다음 탐침 둘", DI) && grepl("교훈 하나", DI) &&
      !length(rc_after_tau_leaks(DI, TAU)))
rc_probe_consume("P4C90_e2e#1", "P4C91_next", OUTC)
chk("Z8 탐침 이어받기 → 열린 탐침 1개 · 설계 입력에 '(이어받음)'", length(rc_open_probes(OUTC, "P4_ASSEMBLY")) == 1L &&
      grepl("(이어받음)", rc_p4_design_input(ROOT, CD2, pool = POOL, outcomes_path = OUTC), fixed = TRUE))
t1 <- s1; t1$code <- "B0x"; CT1 <- wspec("n_k1", t1)
bogus <- err_of(rc_p4_step_open(CD2, 1, H, M, "regime_exposure", CT1, 0, "g1", root = ROOT, pool = POOL, probe_ref = "P4C90_e2e#9", outcomes_path = OUTC))
op_before <- length(rc_open_probes(OUTC))
invisible(rc_p4_step_open(CD2, 1, H, M, "regime_exposure", CT1, 0, "g1", root = ROOT, pool = POOL, probe_ref = "P4C90_e2e#2", outcomes_path = OUTC))
pc <- rc_outcomes_read(OUTC, kind = "probe_consumed")
chk("K3 걸음 열기가 잇는 탐침(probe_ref)을 이어받음으로 남긴다 — 열린 탐침 −1 · 소비자 = <사슬>#k1 · 열린 탐침이 아닌 ref = 열기 거부(원장 무기록)",
    grepl("열린 탐침이 아니다", bogus) && length(rc_open_probes(OUTC)) == op_before - 1L &&
      any(vapply(pc, function(x) identical(x$ref, "P4C90_e2e#2") && identical(x$by, "P4C91_next#k1"), TRUE)))
invisible(sm_(CD2, 1, runner_to("m2_k1"))); q1 <- dec(CD2, 1)
unlink(GLOG); Sys.setenv(T_SR_GRADE = "B"); z2 <- tryCatch(cl_(CD2, "P4C91_next", regrade_write = TRUE), error = function(e) e); Sys.unsetenv("T_SR_GRADE")
gl2 <- if (file.exists(GLOG)) readLines(GLOG) else character(0); FZ2 <- rc_json_read(file.path(CD2, "finalize.json"))
chk("Z9 채택 0 → 최종 후보 = 기저(k 0 · 기준 칸 산출) · 재채점 뒤 B = 관문 미호출 · 앞선 요청 거두기 호출(쓰기 모드)", !inherits(z2, "error") && identical(q1$decision, "reject") &&
      length(gl2) == 1L && grepl("^withdraw .*m2_base B TRUE", gl2[1]) && isTRUE(FZ2$candidate_gate$withdrawn) && grepl("m2_base$", FZ2$candidate),
    paste(gl2, if (inherits(z2, "error")) conditionMessage(z2) else ""))
chk("Z10 r7 v2 — 크게 나빠진 걸음(dS = −0.5)은 signal 이 아니라 noise(r7_detail worse · 연속 잡음을 끊지 않는다 · 총괄 11-10 결정)", identical(q1$r7, "noise") && identical(q1$r7_detail, "worse"))
cc <- O[[1]]$extra$conclusion
chk("Z10b 결론의 기준점(빈칸 16) — 엔진 대비 · 시장 대비를 함께 기록 · '시장보다 덜'은 둘 다 충족일 때만 · 라벨에 시장 대비", isTRUE(cc$engine_relative) && isTRUE(cc$market_relative) &&
      isTRUE(cc$market_sentence_allowed) && grepl("시장 이하", O[[1]]$verdict_label) && identical(O[[1]]$extra$rules_version, "p4_rules_v2"))
GR <- rc_p4_generator_review(ROOT, chain_dirs = c(CD, CD2, CDC), outcomes_path = OUTC)
chk("Z10c 생성기 검토가 판별 성적표(rx_generator_scorecard.R · 읽기 전용)를 함께 싣는다 · τ_D 뒤 날짜 없음", grepl("판별 성적표", GR$md) && !is.null(GR$scorecard) &&
      !length(rc_after_tau_leaks(GR$md, TAU)), substr(GR$md, nchar(GR$md) - 300, nchar(GR$md)))
drv <- readLines("04_Research/programs/_lib/round_core/v1/driver.R", encoding = "UTF-8", warn = FALSE)
## ═══ K 지식 축적 고리 결함(감사 K P1~P6) ═══════════════════════════════════════
cat("K 지식 축적 고리\n")
spK <- list(program = "P4_ASSEMBLY", round_id = "P4C80_k", template = "p4_chain", tau_d = TAU, cells = list())
recK <- function(lessons) rc_outcome_record(spK, list(summary = list(label = "라벨")), "해석", probes = c("a", "b"), lessons = lessons, P = list(prereg = BASE_CELL, results = SB), root = ROOT)
k1 <- err_of(recK("기저는 등급 C 에 머물렀다"))
osrc <- readLines("04_Research/programs/_lib/round_core/v1/outcomes.R", encoding = "UTF-8", warn = FALSE)
om <- sub("  if (!isTRUE(ci$ok)) stop(", "  if (FALSE) stop(", osrc, fixed = TRUE); fo <- file.path(SB, "outcomes_mut.R"); writeLines(om, fo, useBytes = TRUE)
sys.source(fo, envir = globalenv()); k1m <- err_of(recK("기저는 등급 C 에 머물렀다")); sys.source("04_Research/programs/_lib/round_core/v1/outcomes.R", envir = globalenv())
chk("K1 결과 원장 쓰기 = 설계 입력 읽기와 같은 검사 — '등급 C' 교훈 = 기록 거부 · 돌연변이(쓰기 검사 끔 · 치환 1곳) = 받아들임", grepl("등급 표기", k1) && sum(om != osrc) == 1L && identical(k1m, ""))
OB <- file.path(SB, "outcomes_dirty.jsonl"); file.copy(OUTC, OB); bd <- recK("교훈 자리"); bd$lessons <- list("기저는 등급 C 에 머물렀다"); .rc_outcome_write(bd, OB)
dk <- tryCatch(suppressWarnings(rc_outcomes_md(OB, tau_clean = TAU)), error = function(e) conditionMessage(e))
chk("K1b 이미 들어간 나쁜 줄(검사 강화 전) — 설계 입력 읽기는 그 줄만 빼고 계속(경고 · 원장 그대로)", is.character(dk) && length(dk) > 1L && !any(grepl("등급 C", dk, fixed = TRUE)) &&
      any(grepl("P4C80_k", readLines(OB, encoding = "UTF-8"), fixed = TRUE)))
DI2 <- rc_p4_design_input(ROOT, CDC, pool = POOL, outcomes_path = OUTC, other_chain_dirs = c(CD, CD2))
mo <- mut_src('for (r in o$results) if (identical(r$decision, "reject")) {', 'for (r in o$results) if (identical(r$decision, "nope")) {'); sys.source(mo$path, envir = globalenv())
DI2m <- rc_p4_design_input(ROOT, CDC, pool = POOL, outcomes_path = OUTC, other_chain_dirs = c(CD, CD2)); restore_p4()
chk("K2 설계 입력 §4b — 다른 사슬의 기각 걸음(블록 유형 · 사슬 · 걸음 · 사유 코드 · 수치 없음) · 돌연변이 = 없음",
    grepl("4b. 다른 사슬", DI2, fixed = TRUE) && grepl("`weighting` 기각", DI2, fixed = TRUE) && grepl("P4C90_e2e 걸음 2(improve", DI2, fixed = TRUE) &&
      !grepl("P4C92_charter 걸음", DI2, fixed = TRUE) && mo$n == 1L && !grepl("P4C90_e2e 걸음 2(improve", DI2m, fixed = TRUE))
cand <- c("2023년 3월", "2024/05", "2023.07", "’23년", "2023Q2", "1Q23", "2023년 2분기", "2025년 하반기")
safe <- c("2022년 12월까지", "2000년대", "2022/12", "2022Q4", "'22년", "2005년 1분기", "보유 25종 · 15bps")
hit <- vapply(cand, function(x) length(rc_after_tau_leaks(x, TAU)) > 0L, NA); miss <- vapply(safe, function(x) length(rc_after_tau_leaks(x, TAU)) > 0L, NA)
usrc <- readLines("04_Research/programs/_lib/round_core/v1/util.R", encoding = "UTF-8", warn = FALSE)
um <- sub('  ko_ym  = "', '  ko_ym  = "NEVER', usrc, fixed = TRUE); fu <- file.path(SB, "util_mut.R"); writeLines(um, fu, useBytes = TRUE)
sys.source(fu, envir = globalenv()); hm <- length(rc_after_tau_leaks("2023년 3월", TAU)) > 0L; sys.source("04_Research/programs/_lib/round_core/v1/util.R", envir = globalenv())
chk("K4 τ_D 날짜 표기 변형(한국어 연월 · 슬래시 · 점 · ’yy년 · 분기) 전부 잡음 · 정상 문장('2022년 12월까지' 등) 안 막음 · 가림도 같은 규칙 · 돌연변이 = 통과",
    all(hit) && !any(miss) && !length(rc_after_tau_leaks(rc_redact_after_tau("2023년 3월 급락", TAU), TAU)) && sum(um != usrc) == 1L && !hm,
    paste(names(hit)[!hit], names(miss)[miss]))
FR <- file.path(SB, "fakeroot"); dir.create(file.path(FR, "02_Infrastructure/ops"), recursive = TRUE)
writeLines("a <- commandArgs(trailingOnly = TRUE); jsonlite::write_json(list(nolcode = Sys.getenv('QVEST_RP_NO_LCODE', 'unset'), ok = TRUE), a[4], auto_unbox = TRUE)",
           file.path(FR, "02_Infrastructure/ops/rf_cell_worker.R"))
WO <- file.path(SB, "fr_out"); dir.create(WO); old_nl <- Sys.getenv("QVEST_RP_NO_LCODE", unset = NA); Sys.unsetenv("QVEST_RP_NO_LCODE")
invisible(rc_p4_runner_default(BASE_CELL, "K5", file.path(WO, "r.json"), WO, root = FR)); nl <- rc_json_read(file.path(WO, "r.json"))$nolcode
mn <- mut_src('  Sys.setenv(QVEST_RP_NO_LCODE = "1")   # 칸 L-code 끔', '  invisible(NULL)   # 칸 L-code 끔'); sys.source(mn$path, envir = globalenv())
invisible(rc_p4_runner_default(BASE_CELL, "K5m", file.path(WO, "m.json"), WO, root = FR)); nlm <- rc_json_read(file.path(WO, "m.json"))$nolcode; restore_p4()
if (!is.na(old_nl)) Sys.setenv(QVEST_RP_NO_LCODE = old_nl)
chk("K5 기준 칸 · 걸음 칸 러너 = L-code 발행 끔(QVEST_RP_NO_LCODE = 1 · 호출 뒤 환경 복원) · 돌연변이 = 켜짐", identical(nl, "1") && mn$n == 1L && identical(nlm, "unset") &&
      is.na(Sys.getenv("QVEST_RP_NO_LCODE", unset = NA)) == is.na(old_nl))
CQ <- file.path(SB, "chain_q"); dir.create(CQ); file.copy(c(rc_p4_spec_path(CD), rc_p4_steps_path(CD)), CQ)
LQ <- readLines(rc_p4_steps_path(CQ), encoding = "UTF-8"); n_rec0 <- length(rc_p4_steps_read(CQ)); LQ[3] <- sub("낙폭", "급등", LQ[3], fixed = TRUE)
writeBin(charToRaw(paste0(paste(LQ, collapse = "\n"), "\n")), rc_p4_steps_path(CQ))
v0 <- rc_p4_steps_verify(CQ)$ok; e_noreason <- err_of(rc_p4_steps_quarantine(CQ, 3, ""))
invisible(rc_p4_steps_quarantine(CQ, 3, "시험 — 변조 줄 격리")); v1 <- rc_p4_steps_verify(CQ)$ok; n_rec1 <- length(rc_p4_steps_read(CQ))
mq <- mut_src("    if (!is.na(j)) { qi <- c(qi, i);", "    if (FALSE) { qi <- c(qi, i);"); sys.source(mq$path, envir = globalenv()); vm <- rc_p4_steps_verify(CQ)$ok; restore_p4()
OQ <- file.path(SB, "outcomes_q.jsonl"); file.copy(OUTC, OQ); cat("{\"schema\":\"round_outcome_v1\",\"kind\":\"round\",\"round_id\":\n", file = OQ, append = TRUE)
e_oq <- err_of(rc_outcomes_read(OQ)); invisible(rc_outcomes_quarantine(OQ, length(readLines(OQ)), "시험 — 잘린 줄")); r_oq <- tryCatch(suppressWarnings(rc_outcomes_read(OQ)), error = function(e) NULL)
chk("K6 걸음 원장 · 결과 원장 손상 줄 격리(사람 호출 · 사유 필수 · 원장 줄은 지우지 않는다 · 사본 남김) → 판정 경로 재개 · 돌연변이(격리 무시) = 여전히 끊김",
    !v0 && grepl("사유", e_noreason) && v1 && n_rec1 == n_rec0 - 1L && length(readLines(rc_p4_steps_path(CQ))) == length(LQ) && file.exists(file.path(CQ, "chain_steps.quarantine.jsonl")) &&
      mq$n == 1L && !vm && grepl("판독 불가", e_oq) && is.list(r_oq) && length(r_oq) >= 1L)
chk("Z11 CLI p4-close 는 --regrade-write | --regrade-dry-run 중 하나를 요구(닫기는 한 번뿐 — 드라이런으로 닫아 재채점을 잃지 않게)", any(grepl("regrade-dry-run", drv, fixed = TRUE)))
chk("Z12 운영 등록부 · 결과 원장 · 판단 원장 · 생성기 등록부 무접촉", identical(unname(REAL), unname(vapply(names(REAL), function(f) if (file.exists(f)) rc_md5(f) else "absent", ""))))
Sys.unsetenv("RC_RXG_PATH")
cat(sprintf("\n== scn_l1_chain_e2e: PASS %d · FAIL %d ==\n", PASS, FAIL))
cat(sprintf('{"test":"scn_l1_chain_e2e","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
if (FAIL > 0L) quit(status = 1L)
