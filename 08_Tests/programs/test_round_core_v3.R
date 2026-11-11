## test_round_core_v3.R — round_core v3(2026-11-11 · 판 2 P1S02) 시험: 출시 불변 · v2 대비 판 표식만 · 입구 사유 2개(portfolio_only_base · breadth_insufficient) ·
##   측정 기록의 기저 정합 진단(base_alignment_missing · base_not_score_panel) · 기저 풀 입구의 최신 판 우선 · 돌연변이 대조.
##   왜: 설계 04_Research/01_reports/portfolio_paper_layer_split_20261112/README.md §6-4 · §8 · BUILD_EDITION2.md S4 — 판 1 에서 포트폴리오만 내는 엔진이
##       입구를 통과해 측정이 무효가 됐다. 새 변경마다 양방향(양성 · 음성) + τ_D 음성 대조 + 성과 무관 불변.
##   격리: 임시 폴더(SB)만 쓴다 — RC_SA_ROOT · 임시 등록부(실제 등록부의 사본) · 임시 판단 원장 · 임시 레인 · 대체 워커 · 대체 GPU 관문 · 대체 신선도.
##     실제 등록부 · 원장 · 레인 · 텔레그램 · 측정에 닿지 않는다(마지막에 실제 파일 md5 대조).
## 실행: R_ENVIRON_USER=<빈 파일> QM_ROOT=<저장소> Rscript 08_Tests/programs/test_round_core_v3.R
ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")); setwd(ROOT)
if (!file.exists(file.path(ROOT, "04_Research/programs/_lib/round_core/v3/standing.R"))) stop("저장소 루트가 아니다(v3 없음): ", ROOT)
PASS <- 0L; FAIL <- 0L
chk <- function(name, ok, detail = "") {
  if (isTRUE(ok)) { PASS <<- PASS + 1L; cat(sprintf("  [ok]   %s\n", name)) } else { FAIL <<- FAIL + 1L; cat(sprintf("  [FAIL] %s %s\n", name, paste(detail, collapse = " "))) }
}
err_of <- function(expr) tryCatch({ force(expr); "" }, error = function(e) conditionMessage(e))
has_reason <- function(C, d, r) { x <- C[C$dir == d]$reasons; length(x) == 1L && r %in% strsplit(x, ";", fixed = TRUE)[[1]] }
suppressMessages(source("04_Research/programs/_lib/round_core/v3/load.R"))
suppressPackageStartupMessages({ library(data.table); library(arrow) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
md5 <- function(p) unname(as.character(tools::md5sum(p)))
CR <- file.path(ROOT, "04_Research/programs/_lib/round_core")

SB <- gsub("\\\\", "/", file.path(tempdir(), "rc_v3")); unlink(SB, recursive = TRUE); dir.create(SB, recursive = TRUE)
Sys.setenv(RC_SA_ROOT = file.path(SB, "sa"))
## 격리 단정(~/.Renviron 의 QM_ROOT 덮어쓰기 · 임시 폴더 위치) — 하나라도 어긋나면 아무것도 하지 않고 멈춘다
iso_ok <- identical(gsub("\\\\", "/", rc_root()), ROOT) && !startsWith(tolower(SB), tolower(paste0(ROOT, "/"))) &&
  identical(Sys.getenv("RC_SA_ROOT"), file.path(SB, "sa")) && identical(RC_VERSION, "v3") && grepl("/round_core/v3$", RC_DIR)
chk("A0 격리 — rc_root = 저장소 · 임시 폴더는 저장소 밖 · RC_SA_ROOT = 임시 · 적재 판 = v3(RC_DIR v3)", iso_ok, c(rc_root(), SB, RC_DIR))
if (!iso_ok) { cat(sprintf("\n== test_round_core_v3: %d ok · %d FAIL ==\n", PASS, FAIL)); quit(status = 1L) }
## 판단 원장 · 결정 기록부는 다른 세션이 실시간으로 쓴다(md5 대조 불가) — Z2 가 이 시험의 표식(임시 판 id · 논문 키)이 없음을 본다
SHARED <- c("06_Registry/q_judgment_ledger.json", "06_Registry/decision_register.json")
REAL <- c("06_Registry/research_programs.json",
          "06_Registry/factor_db_vintage.json", "stage_artifacts/programs/P1_RETURN/P1S01_standing_qualification/standing_ledger.jsonl",
          ".cache/gpu_lease.json", "04_Research/programs/_lib/round_core/RELEASES.json")
REAL0 <- vapply(REAL, function(f) if (file.exists(f)) md5(f) else "absent", ""); names(REAL0) <- REAL

## 자식 프로세스 — 판 ver 의 코어를 적재하고 식을 평가해 .res 를 돌려준다(한 프로세스 = 판 하나 · test_round_core_v2.R 과 같은 방식)
run_core <- function(ver, lines, tag) {
  f <- file.path(SB, paste0("child_", tag, ".R")); o <- file.path(SB, paste0("child_", tag, ".rds"))
  writeLines(c(sprintf('setwd("%s"); suppressMessages(source("04_Research/programs/_lib/round_core/%s/load.R"))', ROOT, ver),
               sprintf('stopifnot(identical(RC_VERSION, "%s")); suppressPackageStartupMessages(library(data.table))', ver),
               lines, sprintf('saveRDS(.res, "%s")', o)), f, useBytes = TRUE)
  out <- suppressWarnings(system2("Rscript", shQuote(f), stdout = TRUE, stderr = TRUE))
  if (!file.exists(o)) { cat(tail(out, 15), sep = "\n"); stop("자식 프로세스 실패: ", tag) }
  readRDS(o)
}

## ═══ A. 출시 불변 · v2 대비 판 표식만 ═════════════════════════════════════════════════
REL <- rc_json_read(file.path(CR, "RELEASES.json"))
for (v in c("v1", "v2")) {
  R0 <- Filter(function(r) identical(r$version, v), REL$releases)[[1]]; m <- rc_core_manifest(file.path(CR, v))
  chk(sprintf("A1 %s 디렉터리 매니페스트 = RELEASES %s(%s) — 출시 판 무수정", v, v, substr(R0$manifest_md5, 1, 8)),
      identical(m$manifest_md5, R0$manifest_md5) && all(vapply(names(R0$files), function(f) identical(m$files[[f]], R0$files[[f]]), TRUE)), m$manifest_md5)
}
m3 <- rc_core_manifest(); m2 <- rc_core_manifest(file.path(CR, "v2"))
chk("A2 v3 매니페스트 — 판 표기 v3 · 파일 목록 = v2(20개) · 매니페스트 ≠ v2", identical(m3$version, "v3") && identical(sort(names(m3$files)), sort(names(m2$files))) &&
      length(m3$files) == 20L && !identical(m3$manifest_md5, m2$manifest_md5))
v3txt <- unlist(lapply(names(m3$files), function(f) readLines(file.path(RC_DIR, f), encoding = "UTF-8", warn = FALSE)))
chk("A3 v3 파일 안에 round_core/v1 · round_core/v2 고정 경로 0", !any(grepl("round_core/v1", v3txt, fixed = TRUE)) && !any(grepl("round_core/v2", v3txt, fixed = TRUE)))
## v3 → v2 역치환(판 표식 4종)을 하면 standing.R 밖 19개 파일은 v2 와 바이트 같아야 한다
unmark <- function(x) { x <- gsub("round_core/v3", "round_core/v2", x, fixed = TRUE); x <- sub("^(#{1,2}) round_core v3 ", "\\1 round_core v2 ", x)
  x <- sub("이 판(v3)", "이 판(v2)", x, fixed = TRUE); x <- sub("[round_core] v3 모듈", "[round_core] v2 모듈", x, fixed = TRUE); sub('^RC_VERSION <- "v3"$', 'RC_VERSION <- "v2"', x) }
same19 <- vapply(setdiff(names(m3$files), c("standing.R", "p4.R")), function(f) {
  a <- readLines(file.path(RC_DIR, f), encoding = "UTF-8", warn = FALSE); b <- readLines(file.path(CR, "v2", f), encoding = "UTF-8", warn = FALSE)
  identical(unmark(a), b) && !identical(a, b) }, TRUE)
chk("A4 standing.R · p4.R 밖 18개 = v2 + 판 표식만(역치환하면 v2 와 같다 · 표식이 실제로 있다)", all(same19), names(same19)[!same19])
p4a <- unmark(readLines(file.path(RC_DIR, "p4.R"), encoding = "UTF-8", warn = FALSE)); p4b <- readLines(file.path(CR, "v2", "p4.R"), encoding = "UTF-8", warn = FALSE)
gi <- grep("^  ## v3 기저 정합 관문", p4a)
chk("A5 p4.R = v2 + 판 표식 + 사슬 측정 관문 8줄(.rcp4_run_cell)뿐", length(gi) == 1L && identical(p4a[-(gi:(gi + 7L))], p4b) && grepl("^  \\}$", p4a[gi + 7L]), gi)

## ═══ N. 폭 문턱 — 정본 참조(새 숫자 없음) · 판독 실패는 멈춘다 ═══════════════════════════════════
CD <- jsonlite::fromJSON("02_Infrastructure/worktask/constraint_defaults.json", simplifyVector = FALSE)
ACT <- CD$measurement_axis$active
need_ref <- as.numeric(CD$tier_soft_deployment$max_names) * as.numeric(CD$measurement_axis$epochs[[ACT]]$effective_start$breadth_mult)
NB <- rc_standing_breadth_need(ACT, ROOT)
chk(sprintf("N1 폭 문턱(활성 축 %s) = max_names × breadth_mult = %s(설정 파일 직접 판독과 같다)", ACT, format(need_ref)), identical(NB$need, need_ref) && is.finite(need_ref), NB$need)
chk("N2 규칙 없는 축(k200kq150_2005_v1 · effective_start 없음) · 없는 축 · 축 id 없음 = 멈춘다(기본값으로 접지 않는다)",
    grepl("breadth_mult", err_of(rc_standing_breadth_need("k200kq150_2005_v1", ROOT))) && grepl("판독 실패", err_of(rc_standing_breadth_need("no_such_axis", ROOT))) &&
      grepl("측정 축 id", err_of(rc_standing_breadth_need(NA_character_, ROOT))))
NEED <- NB$need; TAU <- "2022-12-31"

## ═══ 레인 고정물 ═════════════════════════════════════════════════════════════════
PAD <- "## fixture padding — 검증기 하한(200바이트)을 넘기기 위한 설명 줄: 이 엔진은 시험용이며 측정하지 않는다."
BODY <- c("## fixture — 가격 모멘텀(엔진 고유 방향 · 커넥터 부호 없음)", PAD, "x <- RAWDATA[, .(Date, Ticker, Close)]",
          "x[, s := shift(Close, 21L) / shift(Close, 252L) - 1, by = Ticker]")
E_FAC <- c(BODY, "FACTORS <- x[is.finite(s), .(Date, Ticker, Score = s)]")
E_PORT <- c(BODY, "PORTFOLIO <- x[is.finite(s), .(Date, Ticker, Weight = 1)]")
E_BOTH <- c(E_FAC, "PORTFOLIO <- x[is.finite(s), .(Date, Ticker, Weight = 1)]")
E_NOOUT <- c(BODY, "y <- x[, .N]")
HO_AT <- "2026-11-11T10:00:00+0900"; T_BEFORE <- as.POSIXct("2026-11-11 09:00:00", tz = "Asia/Seoul")
LANE <- file.path(SB, "lane"); ARTD <- file.path(SB, "art")
mk_art <- function(nm, panel = NULL) {
  a <- file.path(ARTD, nm); dir.create(a, recursive = TRUE, showWarnings = FALSE)
  fwrite(data.table(run_id = "t", date = c("2010-01-29", "2010-02-26"), ticker = c("A1", "A2"), target_weight = c(1, 1)), file.path(a, "04_holdings.csv"))
  if (!is.null(panel)) arrow::write_parquet(panel, file.path(a, "factors_panel.parquet"))
  a
}
## 합성 점수 패널 — 날짜별 폭 지정(Date · Ticker · Score)
mk_panel <- function(widths) rbindlist(lapply(names(widths), function(d) data.table(Date = as.Date(d), Ticker = sprintf("T%04d", seq_len(widths[[d]])), Score = rnorm(widths[[d]]))))
set.seed(1)
W_OK <- list("2010-01-29" = NEED + 10, "2010-02-26" = NEED - 5, "2023-03-31" = NEED - 30)
W_NARROW <- list("2010-01-29" = NEED - 20, "2010-02-26" = NEED - 1)
W_POST <- list("2010-01-29" = NEED - 20, "2010-02-26" = NEED - 1, "2023-01-31" = NEED + 40, "2024-06-28" = NEED + 60)   # τ_D 뒤에만 넓다
W_ONLYPOST <- list("2023-01-31" = NEED + 40)
W_WEEKLY <- list("2010-01-08" = NEED + 10, "2010-01-15" = NEED + 10, "2010-01-22" = NEED + 10, "2010-01-29" = NEED + 10, "2010-02-26" = NEED + 10)   # 주간(한 달 4)
W_QUARTER <- list("2010-03-31" = NEED + 10, "2010-06-30" = NEED + 10, "2010-09-30" = NEED + 10)                                                  # 분기(달마다 ≤ 1)
W_POSTDENSE <- list("2010-01-29" = NEED + 10, "2010-02-26" = NEED + 10, "2023-01-06" = NEED + 10, "2023-01-13" = NEED + 10, "2023-01-20" = NEED + 10)   # τ_D 뒤에만 조밀
FX <- list(   # 이름 · 엔진 · 키 · 패널(NULL = 파일 없음) · 기대 사유(NULL = 통과) · 기대 breadth 머리 · 기대 grid
  list("RP_AUTO_V3_FAC", E_FAC, "9931.00001", W_OK, NULL, "1/2(", "month"),
  list("RP_AUTO_V3_PORT", E_PORT, "9931.00002", W_OK, "portfolio_only_base", "na:portfolio_only", "na:portfolio_only"),
  list("RP_AUTO_V3_BOTH", E_BOTH, "9931.00003", W_OK, NULL, "1/2(", "month"),
  list("RP_AUTO_V3_NARROW", E_FAC, "9931.00004", W_NARROW, "breadth_insufficient", "0/2(", "month"),
  list("RP_AUTO_V3_POSTTAU", E_FAC, "9931.00005", W_POST, "breadth_insufficient", "0/2(", "month"),
  list("RP_AUTO_V3_NOPANEL", E_FAC, "9931.00006", NULL, NULL, "na:panel_missing", "na:panel_missing"),
  list("RP_AUTO_V3_ONLYPOST", E_FAC, "9931.00007", W_ONLYPOST, NULL, "na:no_visible_dates", "na:no_visible_dates"),
  list("RP_AUTO_V3_NOOUT", E_NOOUT, "9931.00008", W_OK, "output_contract_unknown", "na:output_contract_unknown", "na:output_contract_unknown"),
  list("RP_AUTO_V3_WEEKLY", E_FAC, "9931.00009", W_WEEKLY, "base_off_month_grid", "5/5(", "dense(max 4)"),
  list("RP_AUTO_V3_QUARTER", E_FAC, "9931.00010", W_QUARTER, NULL, "3/3(", "month"),
  list("RP_AUTO_V3_POSTDENSE", E_FAC, "9931.00011", W_POSTDENSE, NULL, "2/2(", "month"))
reg <- rc_json_read("06_Registry/research_programs.json")
pidx <- function(id) which(vapply(reg$programs, function(p) p$id, "") == id)
ART <- list()
for (f in FX) {
  nm <- f[[1]]; d <- file.path(LANE, nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(f[[2]], paste("##", nm)), file.path(d, "engine.R"), useBytes = TRUE); Sys.setFileTime(file.path(d, "engine.R"), T_BEFORE)
  rc_json_write(list(fidelity = "faithful", kept = "k", changed = "c"), file.path(d, "FIDELITY.json")); rc_json_write(list(verdict = "faithful"), file.path(d, "fidelity_audit.json"))
  rc_json_write(list(paper_key = f[[3]], paper_url = paste0("https://arxiv.org/abs/", f[[3]])), file.path(d, "lane_provenance.json"))
  ART[[nm]] <- mk_art(nm, if (is.null(f[[4]])) NULL else mk_panel(f[[4]]))
  it <- list(key = paste0("engine:RP_V3_", nm), kind = "engine", base_status = "engine", title = paste("시험 엔진", nm), paper_key = f[[3]], base_id = paste0("RP_V3_", nm),
             grade = "F", fidelity = "faithful", artifacts = ART[[nm]], engine_path = file.path(d, "engine.R"), routed_by = "program_queue", cr_verdict = "weak",
             implementation_suspect = FALSE, has_short = FALSE, audit_verdict = "faithful", enqueued_at = HO_AT)
  reg$programs[[pidx("P1_RETURN")]]$queue <- c(reg$programs[[pidx("P1_RETURN")]]$queue, list(it))
}
REG <- file.path(SB, "research_programs.json"); rc_json_write(reg, REG)
SC <- RC_STANDING_SCAN_DEFAULT; SC$lane_root <- LANE

## ═══ B. 입구 사유 — 양성 · 음성 · τ_D 음성 대조 · 판독 불가 · 성과 무관 ══════════════════════════════
C <- rc_standing_lane_candidates(SC, registry_path = REG, tau = TAU, lane_root = LANE)
chk("B0 디렉터리마다 1행 · 스캔 표에 breadth · grid 열", nrow(C) == length(FX) && all(c("breadth", "grid") %in% names(C)), paste(nrow(C), names(C)))
for (f in FX) {
  r <- C[dir == f[[1]]]; nm <- sub("^RP_AUTO_V3_", "", f[[1]])
  ok_reason <- if (is.null(f[[5]])) isTRUE(r$eligible) else has_reason(C, f[[1]], f[[5]])
  chk(sprintf("B1 %s → %s · breadth %s… · grid %s", nm, f[[5]] %||% "통과", f[[6]], f[[7]]), ok_reason && startsWith(r$breadth, f[[6]]) && identical(r$grid, f[[7]]),
      paste(r$reasons, "|", r$breadth, "|", r$grid))
}
chk("B1g base_off_month_grid 양성(주간) · 음성(월말 · 분기) · τ_D 대조(τ_D 뒤에만 조밀 = 사유 없음) · 판독 불가(사유 없음)",
    has_reason(C, "RP_AUTO_V3_WEEKLY", "base_off_month_grid") && !has_reason(C, "RP_AUTO_V3_FAC", "base_off_month_grid") &&
      isTRUE(C[dir == "RP_AUTO_V3_QUARTER"]$eligible) && isTRUE(C[dir == "RP_AUTO_V3_POSTDENSE"]$eligible) && isTRUE(C[dir == "RP_AUTO_V3_NOPANEL"]$eligible) &&
      grepl("주간 · 일간 신호 엔진", RC_STANDING_REASONS[["base_off_month_grid"]], fixed = TRUE))
chk("B2 portfolio_only_base 음성 — FACTORS 대입(FACTORS 만 · 둘 다)은 사유 없음 · 산출 대입 없음은 output_contract_unknown 만(포트폴리오 사유를 겹치지 않는다)",
    !has_reason(C, "RP_AUTO_V3_FAC", "portfolio_only_base") && !has_reason(C, "RP_AUTO_V3_BOTH", "portfolio_only_base") &&
      !has_reason(C, "RP_AUTO_V3_NOOUT", "portfolio_only_base"))
chk(sprintf("B3 breadth 문자열 형식 — 충족 날/보는 창 날(max 최대 폭 · need %s) · 최대 폭은 보는 창 값(τ_D 뒤 %d 는 안 보인다)", format(NEED), as.integer(NEED + 60)),
    identical(C[dir == "RP_AUTO_V3_FAC"]$breadth, sprintf("1/2(max %d · need %s)", as.integer(NEED + 10), format(NEED))) &&
      identical(C[dir == "RP_AUTO_V3_POSTTAU"]$breadth, sprintf("0/2(max %d · need %s)", as.integer(NEED - 1), format(NEED))), C$breadth)
chk("B4 τ_D 음성 대조 — τ_D 뒤에만 폭이 넓은 패널은 여전히 미달(breadth_insufficient) · τ_D 뒤 날짜뿐이면 na(사유 없음)",
    has_reason(C, "RP_AUTO_V3_POSTTAU", "breadth_insufficient") && isTRUE(C[dir == "RP_AUTO_V3_ONLYPOST"]$eligible))
b_un <- rc_standing_breadth(file.path(SB, "nope"), TAU, NEED); b_bad <- { a <- file.path(ARTD, "badpq"); dir.create(a); writeLines("not parquet", file.path(a, "factors_panel.parquet")); rc_standing_breadth(a, TAU, NEED) }
chk("B5 판독 불가 — 패널 없음 · 깨진 파일 = ok NA(사유 없음 · na:…) · 산출 경로 없음 = na:no_artifacts",
    is.na(b_un$ok) && identical(b_un$why, "panel_missing") && is.na(b_bad$ok) && identical(b_bad$why, "panel_unreadable") &&
      identical(rc_standing_breadth(NA, TAU, NEED)$why, "no_artifacts") && isTRUE(C[dir == "RP_AUTO_V3_NOPANEL"]$eligible))
## 성과 무관 — 산출 폴더의 성과 수치(권위 기록 · 점수 값 · 인계 등급)를 바꿔도 스캔 결과가 같다(v1 시험 B6 · B7 형태)
chk("B6 스캔 표에 성과 열이 없다", !any(c("grade", "base_port_t", "cr_verdict", "port_t", "cagr", "calmar", "sharpe") %in% names(C)))
for (nm in names(ART)) {
  rc_json_write(list(run_id = "RP_x", essence_grade = "A", calmar = 9.9, cagr = 0.9, port_t = 9.9), file.path(ART[[nm]], "authoritative_remeasure.json"))
  pf <- file.path(ART[[nm]], "factors_panel.parquet")
  if (file.exists(pf) && !identical(nm, "badpq")) { P <- as.data.table(arrow::read_parquet(pf, mmap = FALSE)); gc(); P[, Score := -Score * 100]; arrow::write_parquet(P, pf) }
}
reg2 <- rc_json_read(REG); q <- reg2$programs[[pidx("P1_RETURN")]]$queue
for (i in seq_along(q)) if (grepl("^RP_V3_", q[[i]]$base_id %||% "")) { q[[i]]$grade <- "A"; q[[i]]$base_port_t <- 9.9; q[[i]]$cr_verdict <- "strong" }
reg2$programs[[pidx("P1_RETURN")]]$queue <- q; REG2 <- file.path(SB, "reg_perf_flip.json"); rc_json_write(reg2, REG2)
C2 <- rc_standing_lane_candidates(SC, registry_path = REG2, tau = TAU, lane_root = LANE)
chk("B7 성과 무관 불변 — 권위 기록 · 점수 값 · 인계 등급을 바꿔도 eligible · reasons · breadth · grid 동일(음성 대조)",
    identical(C$eligible, C2$eligible) && identical(C$reasons, C2$reasons) && identical(C$breadth, C2$breadth) && identical(C$grid, C2$grid))
chk("B8 규칙 문서 — 새 사유 2개가 사유 표에 실린다(필요조건 문구 포함)", "portfolio_only_base" %in% names(RC_STANDING_REASONS) && "breadth_insufficient" %in% names(RC_STANDING_REASONS) &&
      grepl("필요조건", RC_STANDING_REASONS[["breadth_insufficient"]]))

## ═══ R. 상설 판 등록 → 스캔(사양 축 배선 · 태그) ═══════════════════════════════════════════
P0RES <- "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/results"
LED <- file.path(SB, "ledger.json"); RVR <- file.path(SB, "rv")
RD <- file.path(SB, "round", "P1S97_v3_selftest"); RID <- "P1S97_v3_selftest"
SEEDS <- list(list(code = "P0R01_E2_C0", engine = "E2", role = "reference", source_results = P0RES))
rc_init_standing_p1(RD, RID, SEEDS, purpose = "코어 v3 자체 시험(격리)", hypothesis = "입구 사유 2 · 측정 기저 정합 · 최신 판", edition = 7L,
                    scan = list(lane_root = LANE), exposures = list("시험"), conclusion_scope = list("자체 시험"), bcfg = NULL)
S0 <- rc_spec_load(file.path(RD, "round_spec.json"))
dr <- rc_standing_scan(RD, dry_run = TRUE, registry_path = REG, out = file.path(SB, "dry.json"))
chk("R1 dry-run 스캔 = 같은 판독(breadth · 사유) · 스캔 기록 파일에 breadth 열", identical(dr$table$breadth, C2$breadth) &&
      "breadth" %in% names(rc_json_read(file.path(SB, "dry.json"))$table[[1]]))
RDX <- file.path(SB, "round", "P1S96_axis"); dir.create(RDX, recursive = TRUE); Sx <- jsonlite::fromJSON(file.path(RD, "round_spec.json"), simplifyVector = FALSE)
Sx$standing_cfg$generator_pin$canon$measurement_axis <- "k200kq150_2005_v1"; rc_json_write(Sx, file.path(RDX, "round_spec.json"))
chk("R2 스캔은 그 판의 측정 축(generator_pin.canon.measurement_axis)으로 배수를 읽는다 — 규칙 없는 축을 핀한 판 = 멈춘다(배선 양성 대조)",
    grepl("breadth_mult", err_of(rc_standing_scan(RDX, dry_run = TRUE, registry_path = REG))))
review <- function(rd, v) { f <- file.path(SB, sprintf("review_%s_v%d.md", basename(rd), v)); writeLines("점검 ok", f); rc_mark_reviewed(rd, v, f, "ok") }
p1_review <- function(rid) {
  tag <- rc_round_tag(rid); rvf <- sprintf("04_Research/programs/_supervision/superfan/philosophy/20261111_2300_P1_%s.md", tag)
  dir.create(dirname(file.path(RVR, rvf)), recursive = TRUE, showWarnings = FALSE); writeLines("P1 리뷰", file.path(RVR, rvf))
  L <- if (file.exists(LED)) rc_json_read(LED) else list(schema = "q_judgment_ledger_v1", judgments = list(), reviews = list(), challenges = list())
  L$reviews <- c(L$reviews, list(list(id = paste0("R-", tag), role = "philosophy", trigger = "P1", round = rid, file = rvf, challenges = list())))
  writeLines(as.character(jsonlite::toJSON(L, auto_unbox = TRUE, null = "null", pretty = TRUE)), LED, useBytes = TRUE)
}
rg <- tryCatch({ rc_draft(RD); review(RD, 1L); p1_review(RID); rc_register(RD, registry_path = REG, ledger = LED, check_git = FALSE, run_tests = FALSE, review_root = RVR) },
               error = function(e) e)
chk("R3 상설 판 등록(임시 등록부 · 판 7)", !inherits(rg, "error"), if (inherits(rg, "error")) conditionMessage(rg) else "")
P <- rc_paths(RD, S0); LEDGER <- file.path(P$sa_dir, "standing_ledger.jsonl")
sc1 <- tryCatch(rc_standing_scan(RD, registry_path = REG), error = function(e) e)
I <- if (inherits(sc1, "error")) list() else rc_standing_items(rc_standing_ledger_read(LEDGER))
code_of <- function(key) names(I)[vapply(I, function(it) identical(it$paper$paper_key, key), TRUE)]
want <- c("9931.00001", "9931.00003", "9931.00006", "9931.00007", "9931.00010", "9931.00011")
chk("R4 스캔 — 입구 통과 6건만 넣음(포트폴리오만 · 폭 미달 · 산출 없음 · 주간 격자는 안 넣는다)", !inherits(sc1, "error") &&
      setequal(unlist(lapply(Filter(function(it) identical(it$source, "scan"), I), function(it) it$paper$paper_key)), want),
    if (inherits(sc1, "error")) conditionMessage(sc1) else paste(names(I), collapse = ","))
tg <- vapply(want, function(k) { cd <- code_of(k); if (length(cd) == 1L) .rcs_str(I[[cd]]$tags$breadth) else NA_character_ }, "")
tgg <- vapply(want, function(k) { cd <- code_of(k); if (length(cd) == 1L) .rcs_str(I[[cd]]$tags$grid) else NA_character_ }, "")
chk("R5 enqueue tags 에 breadth · grid 문자열(스캔 표와 같다)", identical(unname(tg), unname(vapply(want, function(k) C2[paper_key == k]$breadth, ""))) &&
      identical(unname(tgg), unname(vapply(want, function(k) C2[paper_key == k]$grid, ""))), c(tg, tgg))
scl <- Filter(function(r) identical(r$event, "scan"), rc_standing_ledger_read(LEDGER))[[1]]
chk("R6 스캔 원장 줄의 제외 사유 집계에 새 사유(portfolio_only_base 1 · breadth_insufficient 2 · base_off_month_grid 1)",
    identical(as.integer(scl$excluded$portfolio_only_base), 1L) && identical(as.integer(scl$excluded$breadth_insufficient), 2L) &&
      identical(as.integer(scl$excluded$base_off_month_grid), 1L), jsonlite::toJSON(scl$excluded, auto_unbox = TRUE))

## ═══ M. 측정 기록 — 기저 정합 진단(대체 워커 · 대체 신선도 · 대체 GPU) ══════════════════════════════
FP <- function() "fp-stable"; FRESH <- function(root) list(ok = TRUE, state = "fresh", reason = "시험 주입")
GPU <- function(engine_path, holder, purpose, root) list(ok = TRUE, need = FALSE, state = "cpu", reason = "시험 주입", release = function() invisible(NULL))
ARTF <- file.path(SB, "stub_art.txt"); STUB <- file.path(SB, "stub_worker.R")
writeLines(c("a <- commandArgs(trailingOnly = TRUE); code <- a[3]; out <- a[4]",
             sprintf("art <- readLines('%s', warn = FALSE)[1]", ARTF),
             "writeLines(as.character(jsonlite::toJSON(list(n = 1, code = code, ok = TRUE, artifacts = art), auto_unbox = TRUE)), out)"), STUB)
diag_art <- function(nm, entries) {   # entries = list(<키> = list(필드…)) · NULL = 진단 파일 없음
  a <- file.path(SB, "meas_art", nm); dir.create(a, recursive = TRUE, showWarnings = FALSE)
  if (!is.null(entries)) rc_json_write(list(schema = "rf_engine_diag_v1", cell_code = nm, base_alignment = entries), file.path(a, "rf_engine_diag.json"))
  a
}
ba_entry <- function(rule = "month_snap_v1", base_kind = "factors", first = "2000-01-31", drop_kind = FALSE, superseded = 0L, offcal = 0L, drop_grid = FALSE) {
  e <- list(rule = rule, n_engine_dates = 110L, n_cell_dates = 108L, n_identity = 0L, n_moved = 108L, n_superseded = superseded, n_offcal = offcal, n_dropped_tail = 0L,
            max_lag_td = 21L, median_lag_td = 10L, start_injected = TRUE, start = "2000-01-01", from_cache = FALSE,
            first_engine_date = "2000-01-14", last_engine_date = "2026-10-15", first_cell_date = first, last_cell_date = "2026-10-30",
            n_cell_dates_from_start = 106L, base_kind = base_kind)
  if (drop_kind) e$base_kind <- NULL
  if (drop_grid) { e$n_superseded <- NULL; e$n_offcal <- NULL }
  e
}
key_of <- function(nm) paste0(nm, "/engine.R")
measure <- function(code, art) { writeLines(art, ARTF)
  rc_standing_measure_item(RD, code, registry_path = REG, worker = STUB, freshness = FRESH, fingerprint = FP, gpu = GPU) }
it_of <- function(code) rc_standing_items(rc_standing_ledger_read(LEDGER))[[code]]
c_fac <- code_of("9931.00001"); c_both <- code_of("9931.00003"); c_nop <- code_of("9931.00006"); c_post <- code_of("9931.00007")
m_ok <- measure(c_fac, diag_art("ok", setNames(list(ba_entry()), key_of("RP_AUTO_V3_FAC"))))
L_ok <- it_of(c_fac)$measures[[1]]
chk("M1 진단 정상(규칙 month_snap_v1 · base_kind factors) = ok · 원장 기록에 base_alignment 요약(키 = 엔진 폴더/파일)",
    isTRUE(m_ok$ok) && isTRUE(L_ok$ok) && identical(names(L_ok$base_alignment), key_of("RP_AUTO_V3_FAC")) &&
      identical(L_ok$base_alignment[[1]]$rule, "month_snap_v1") && identical(L_ok$base_alignment[[1]]$n_moved, 108L) &&
      identical(L_ok$base_alignment[[1]]$base_kind, "factors") && identical(L_ok$base_alignment[[1]]$first_cell_date, "2000-01-31"), jsonlite::toJSON(L_ok$base_alignment, auto_unbox = TRUE))
chk("M2 요약에 last_cell_date · last_engine_date 없음(τ_D 뒤 날짜) · 요약 필드 = 지정 13개(n_superseded · n_offcal · first_engine_date · n_cell_dates_from_start 포함) · 원장 줄 전체에 τ_D 뒤 날짜 0",
    !any(c("last_cell_date", "last_engine_date") %in% names(L_ok$base_alignment[[1]])) && setequal(names(L_ok$base_alignment[[1]]), RC_STANDING_BASE_SUMMARY) &&
      all(c("n_superseded", "n_offcal", "first_engine_date", "n_cell_dates_from_start") %in% RC_STANDING_BASE_SUMMARY) && length(RC_STANDING_BASE_SUMMARY) == 13L &&
      identical(L_ok$base_alignment[[1]]$n_cell_dates_from_start, 106L) && identical(L_ok$base_alignment[[1]]$first_engine_date, "2000-01-14") &&
      !length(rc_after_tau_leaks(L_ok$base_alignment, as.Date(TAU))) && !any(grepl("2026-10-30|2026-10-15", readLines(LEDGER, encoding = "UTF-8"))))
chk("M3 통과 측정 = 측정됨(.rcs_measured) · 판정 대기(.rcs_judgeable)", .rcs_measured(it_of(c_fac)) && .rcs_judgeable(it_of(c_fac)))
m_miss <- measure(c_both, diag_art("none", NULL)); itb <- it_of(c_both)
chk("M4 진단 없음 = ok FALSE · error base_alignment_missing · 실패 1회(.rcs_fails) · 아직 대기(재측정 1회)",
    identical(m_miss$ok, FALSE) && identical(m_miss$error, "base_alignment_missing") && identical(itb$measures[[1]]$error, "base_alignment_missing") &&
      .rcs_fails(itb) == 1L && c_both %in% rc_standing_pending(RD, registry_path = REG) && !.rcs_judgeable(itb))
m_miss2 <- measure(c_both, diag_art("otherkey", setNames(list(ba_entry()), "RP_AUTO_OTHER/engine.R"))); itb <- it_of(c_both)
chk("M5 진단은 있으나 이 칸 엔진 키가 없다 = base_alignment_missing · 실패 2회 = 대기에서 빠지고 상태 줄 '사람 확인'",
    identical(m_miss2$error, "base_alignment_missing") && .rcs_fails(itb) == 2L && !(c_both %in% rc_standing_pending(RD, registry_path = REG)) &&
      any(grepl(c_both, rc_standing_status_lines(RD, registry_path = REG), fixed = TRUE)))
m_rule <- measure(c_nop, diag_art("oldrule", setNames(list(ba_entry(rule = "exact_date_v0")), key_of("RP_AUTO_V3_NOPANEL"))))
chk("M6 규칙 ≠ month_snap_v1(옛 셀 엔진) = base_alignment_missing", identical(m_rule$ok, FALSE) && identical(m_rule$error, "base_alignment_missing"), m_rule$error_detail)
m_pw <- measure(c_post, diag_art("pw", setNames(list(ba_entry(base_kind = "portfolio_weights")), key_of("RP_AUTO_V3_ONLYPOST"))))
chk("M7 base_kind = portfolio_weights = base_not_score_panel(비중을 점수로 읽은 측정 차단) · 요약은 남긴다(진단)",
    identical(m_pw$ok, FALSE) && identical(m_pw$error, "base_not_score_panel") && identical(it_of(c_post)$measures[[1]]$base_alignment[[1]]$base_kind, "portfolio_weights"))
m_uk <- measure(c_nop, diag_art("nokind", setNames(list(ba_entry(drop_kind = TRUE)), key_of("RP_AUTO_V3_NOPANEL"))))
chk("M8 base_kind 필드 없음 = unknown 으로 읽어 base_not_score_panel", identical(m_uk$error, "base_not_score_panel") &&
      identical(it_of(c_nop)$measures[[2]]$base_alignment[[1]]$base_kind, "unknown"))
mk_cs <- function(kind) { p <- file.path(SB, paste0("cs_", kind, ".json")); rc_json_write(list(code = "x", base_signal = list(kind = kind)), p); p }
ba_nonengine <- rc_standing_base_alignment(mk_cs("factor_db"), file.path(SB, "meas_art", "none"), TAU, ROOT)
ba_tau <- rc_standing_base_alignment(I[[c_fac]]$cell_spec, diag_art("taufirst", setNames(list(ba_entry(first = "2023-02-28")), key_of("RP_AUTO_V3_FAC"))), TAU, ROOT)
chk("M9 기저가 엔진이 아닌 칸 = 검사 대상 아님(진단 없어도 ok) · 칸 사양 판독 불가 = base_alignment_missing(fail-closed)",
    isTRUE(ba_nonengine$ok) && !isTRUE(ba_nonengine$need) &&
      identical(rc_standing_base_alignment(file.path(SB, "nope.json"), file.path(SB, "meas_art", "ok"), TAU, ROOT)$error, "base_alignment_missing"))
chk("M10 요약의 다른 날짜도 τ_D 뒤면 가린다(first_cell_date 2023 → after_tau_d)", isTRUE(ba_tau$ok) && identical(ba_tau$summary[[1]]$first_cell_date, "after_tau_d"))
eb <- list(code = "x", base_signal = list(kind = "engine_blend", paths = list(file.path(LANE, "RP_AUTO_V3_FAC", "engine.R"), file.path(LANE, "RP_AUTO_V3_BOTH", "engine.R"))))
ebp <- file.path(SB, "cs_blend.json"); rc_json_write(eb, ebp)
two <- setNames(list(ba_entry(), ba_entry()), c(key_of("RP_AUTO_V3_FAC"), key_of("RP_AUTO_V3_BOTH")))
one_pw <- setNames(list(ba_entry(), ba_entry(base_kind = "portfolio_weights")), c(key_of("RP_AUTO_V3_FAC"), key_of("RP_AUTO_V3_BOTH")))
chk("M11 engine_blend — 두 엔진 모두 정상 = ok · 한 엔진만 있으면 missing · 어느 항목이라도 비중이면 base_not_score_panel",
    isTRUE(rc_standing_base_alignment(ebp, diag_art("blend2", two), TAU, ROOT)$ok) &&
      identical(rc_standing_base_alignment(ebp, diag_art("blend1", two[1]), TAU, ROOT)$error, "base_alignment_missing") &&
      identical(rc_standing_base_alignment(ebp, diag_art("blendpw", one_pw), TAU, ROOT)$error, "base_not_score_panel"))

c_qt <- code_of("9931.00010"); c_pd <- code_of("9931.00011")
m_sup <- measure(c_qt, diag_art("sup", setNames(list(ba_entry(superseded = 3L)), key_of("RP_AUTO_V3_QUARTER"))))
chk("M12 n_superseded > 0(주간 · 일간 신호의 월말 표본) = 측정 실패 base_off_month_grid · 원장 요약에 n_superseded 3",
    identical(m_sup$ok, FALSE) && identical(m_sup$error, "base_off_month_grid") && identical(it_of(c_qt)$measures[[1]]$base_alignment[[1]]$n_superseded, 3L))
m_off <- measure(c_pd, diag_art("offcal", setNames(list(ba_entry(offcal = 1L)), key_of("RP_AUTO_V3_POSTDENSE"))))
chk("M13 n_offcal > 0(비거래일 도장) = base_off_month_grid", identical(m_off$ok, FALSE) && identical(m_off$error, "base_off_month_grid"))
g_ord <- rc_standing_base_alignment(I[[c_fac]]$cell_spec, diag_art("ord", setNames(list(ba_entry(base_kind = "portfolio_weights", superseded = 2L)), key_of("RP_AUTO_V3_FAC"))), TAU, ROOT)
g_na <- rc_standing_base_alignment(I[[c_fac]]$cell_spec, diag_art("gridna", setNames(list(ba_entry(drop_grid = TRUE)), key_of("RP_AUTO_V3_FAC"))), TAU, ROOT)
chk("M14 관문 순서 — 비중 + 격자 이탈 = base_not_score_panel 먼저 · 격자 필드 없음(NA) = 격자 관문 안 건다(ok) · 요약은 NA",
    identical(g_ord$error, "base_not_score_panel") && isTRUE(g_na$ok) && is.na(g_na$summary[[1]]$n_superseded) && is.na(g_na$summary[[1]]$n_offcal))

## ═══ P. P4 사슬 측정에도 같은 관문(.rcp4_run_cell · 가짜 러너 · 가짜 배리어 · 가짜 판 표식) ═══════════════════════
PCD <- file.path(SB, "p4chain"); dir.create(PCD, recursive = TRUE)
PST <- list(spec = list(chain_id = "P4C_v3test", tau_d = TAU), base_meas = NULL)
p4_cell <- function(cs, art) {
  runner <- function(msp, code, out, md, root, role) { writeLines(as.character(jsonlite::toJSON(list(ok = TRUE, artifacts = art), auto_unbox = TRUE)), out); 0L }
  .rcp4_run_cell(PCD, PST, cs, "k0", "P4C_v3test_k0", 1L, "v3 시험", "variant", ROOT, runner = runner,
                 barrier = function(root) list(state = "free", blocking = FALSE), fingerprint = FP,
                 vintage = function(root) list(id = "vtest", n_repairs = 0L, n_in_progress = 0L), freshness = FRESH, gpu = GPU)
}
CSF <- I[[c_fac]]$cell_spec
p_ok <- p4_cell(rc_abs(CSF), diag_art("ok", NULL)); p_miss <- p4_cell(rc_abs(CSF), diag_art("none", NULL))
p_pw <- p4_cell(rc_abs(CSF), diag_art("pw4", setNames(list(ba_entry(base_kind = "portfolio_weights")), key_of("RP_AUTO_V3_FAC"))))
p_grid <- p4_cell(rc_abs(CSF), diag_art("sup4", setNames(list(ba_entry(superseded = 1L)), key_of("RP_AUTO_V3_FAC"))))
p_ne <- p4_cell(mk_cs("factor_db"), diag_art("none", NULL))
chk("P1 사슬 측정 — 진단 정상 = ok + 요약(last_cell_date 없음) · 진단 없음 = failed base_alignment_missing",
    identical(p_ok$status, "ok") && identical(names(p_ok$rec$base_alignment), key_of("RP_AUTO_V3_FAC")) && !("last_cell_date" %in% names(p_ok$rec$base_alignment[[1]])) &&
      identical(p_miss$status, "failed") && identical(p_miss$rec$error, "base_alignment_missing"), c(p_ok$status, p_miss$status, p_ok$why))
chk("P2 사슬 측정 — 비중 기저 = base_not_score_panel · 격자 이탈 = base_off_month_grid · 기저가 엔진이 아닌 칸 = 관문 대상 아님(ok)",
    identical(p_pw$rec$error, "base_not_score_panel") && identical(p_grid$rec$error, "base_off_month_grid") && identical(p_ne$status, "ok") && is.null(p_ne$rec$base_alignment),
    c(p_pw$rec$error, p_grid$rec$error, p_ne$status))

## 돌연변이 사본 도구(J · X 절) — 소스 텍스트 치환(deparse 아님) · 치환 횟수 단정 · 격리 환경 적재
SRC <- readLines(file.path(RC_DIR, "standing.R"), encoding = "UTF-8", warn = FALSE)
mutant <- function(find, repl, tag) {
  k <- sum(lengths(regmatches(SRC, gregexpr(find, SRC, fixed = TRUE))))
  M <- gsub(find, repl, SRC, fixed = TRUE); f <- file.path(SB, paste0("mut_", tag, ".R")); writeLines(M, f, useBytes = TRUE)
  e <- new.env(parent = globalenv()); r <- tryCatch({ sys.source(f, envir = e, keep.source = FALSE); TRUE }, error = function(z) conditionMessage(z))
  list(k = k, env = e, loaded = isTRUE(r), changed = !identical(M, SRC))
}
## ═══ J. 판정이 굳지 않는다(판단 T3 C-20261111-049) — 판정 지표 NA · 자격 NA 행은 verdict 없이 eval_failed ═════════════════
eval_stub <- function(root, round_dir, cell, env, tau) {
  ev <- rc_json_read(file.path(P0RES, "P0R01_E2_C0", "eval.json")); ev$code <- cell$code; ev$engine <- cell$engine
  od <- file.path(round_dir, "results", cell$code); dir.create(od, recursive = TRUE, showWarnings = FALSE); rc_json_write(ev, file.path(od, "eval.json")); ev
}
orig_tab <- rc_p1_table; NA_CODES <- character(0)
assign("rc_p1_table", function(...) { T <- orig_tab(...); T[code %in% NA_CODES, t_alpha_vis := NA_real_]; T }, envir = globalenv())   # 대체 평가 — 판정 지표 NA 주입
invisible(measure(c_pd, diag_art("okpd", setNames(list(ba_entry()), key_of("RP_AUTO_V3_POSTDENSE")))))
NA_CODES <- c_fac
J1 <- rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub); IJ <- rc_standing_items(rc_standing_ledger_read(LEDGER))
efr <- Filter(function(r) identical(r$event, "eval_failed") && identical(r$code, c_fac), rc_standing_ledger_read(LEDGER))
chk("J1 판정 지표 NA 행 = verdict 없음 · 판정 파일 없음 · eval_failed(judge_metric_na: t_alpha_vis) 1 · 다시 평가 대상",
    is.null(IJ[[c_fac]]$verdict) && identical(IJ[[c_fac]]$eval_fails, 1L) && .rcs_judgeable(IJ[[c_fac]]) && !file.exists(file.path(RD, "results", "standing", paste0(c_fac, ".verdict.json"))) &&
      length(efr) == 1L && identical(efr[[1]]$error, "judge_metric_na: t_alpha_vis") && !(c_fac %in% J1$judged) && c_fac %in% J1$unsettled, paste(J1$judged, "|", efr[[1]]$error))
chk("J2 같은 묶음의 정상 항목(시드 · 다른 스캔 항목)은 verdict 가 남는다(판정 파일 · 자격 TRUE/FALSE)",
    !is.null(IJ[["P0R01_E2_C0"]]$verdict) && is.logical(IJ[["P0R01_E2_C0"]]$verdict$qualify) && !is.na(IJ[["P0R01_E2_C0"]]$verdict$qualify) &&
      !is.null(IJ[[c_pd]]$verdict) && file.exists(file.path(RD, "results", "standing", paste0(c_pd, ".verdict.json"))) && setequal(J1$judged, c("P0R01_E2_C0", c_pd)), paste(J1$judged))
J2 <- rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub); IJ <- rc_standing_items(rc_standing_ledger_read(LEDGER)); nL <- rc_standing_ledger_verify(LEDGER)$n
J3 <- rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub)
chk("J3 상한(RC_STANDING_MAX_FAILS) 뒤 판정 대상에서 빠진다 · 다음 judge 는 아무것도 안 쓴다 · standing-status 에 사람 확인으로 드러난다",
    identical(IJ[[c_fac]]$eval_fails, RC_STANDING_MAX_FAILS) && !.rcs_judgeable(IJ[[c_fac]]) && is.null(IJ[[c_fac]]$verdict) && !length(J3$judged) &&
      rc_standing_ledger_verify(LEDGER)$n == nL && any(grepl(paste0("실패.*", c_fac), rc_standing_status_lines(RD, registry_path = REG))))
md3 <- rc_standing_rules_md(S0)
chk("J4 규칙 문서 4절 — '판정 지표 계산 예외'도 인프라 실패(판정 아님)", any(grepl("칸 평가 예외 · 판정 지표 계산 예외)는 판정이 아니다", md3, fixed = TRUE)))
## 대조 — 새 분기를 끈 돌연변이(= v1 · v2 동작)에서는 같은 입력이 자격 NA verdict 로 굳는다(다시 재지도 평가하지도 못한다)
invisible(measure(c_qt, diag_art("okqt", setNames(list(ba_entry()), key_of("RP_AUTO_V3_QUARTER"))))); NA_CODES <- c_qt
MUJ <- mutant('.rcs_judge_unsettled <- function(status, q) !identical(status, "evaluated") || is.na(q)', '.rcs_judge_unsettled <- function(status, q) FALSE', "judge")
if (MUJ$loaded) invisible(MUJ$env$rc_standing_judge(RD, registry_path = REG, eval_fun = eval_stub))
IQ <- rc_standing_items(rc_standing_ledger_read(LEDGER))[[c_qt]]
chk("J5 대조(돌연변이 · 치환 1곳) — 분기를 끄면 자격 NA verdict 가 남아 굳는다(판정 대기 · 측정 대기 둘 다 아님 · v2 의 결함 재현)",
    MUJ$k == 1L && MUJ$loaded && !is.null(IQ$verdict) && is.na(IQ$verdict$qualify %||% NA) && !.rcs_judgeable(IQ) && !.rcs_pending(IQ), c(MUJ$k, is.null(IQ$verdict)))
assign("rc_p1_table", orig_tab, envir = globalenv())

## ═══ Q. 기저 풀 입구 — 같은 칸을 두 판이 판정하면 최신 판(판 번호 큰 쪽)만 ═════════════════════════════
SAQ <- file.path(SB, "saq")
mk_engine <- function(nm) { d <- file.path(SB, "strategies", nm); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("## 시험 엔진(v3) — 실행하지 않는다", "FACTORS <- NULL", strrep("# 채움\n", 30), paste("##", nm)), file.path(d, "engine.R")); file.path(d, "engine.R") }
EA <- mk_engine("RP_AUTO_QA"); EB <- mk_engine("RP_AUTO_QB"); EC <- mk_engine("RP_AUTO_QC"); ED <- mk_engine("RP_AUTO_QD")
paper <- function(k) list(url = paste0("https://arxiv.org/abs/", k), title = paste("Test paper", k), paper_key = k)
dir.create(file.path(SB, "qspecs"), showWarnings = FALSE)
wspec <- function(s, nm) { p <- file.path(SB, "qspecs", paste0(nm, ".json")); rc_json_write(s, p); p }
std <- function(code, eng, k) wspec(rc_p1_cell_spec(code, eng, paper(k), k, 1L, "v3 시험", root = ROOT), code)
sd_trt <- rc_p1_cell_spec("Q1_D_TRT", ED, paper("2001.00014"), "2001.00014", 1L, "v3 시험", root = ROOT)
sd_trt$weighting <- list(kind = "catalog", catalog_id = "lean:entropy", label = "entropy"); SP_DT <- wspec(sd_trt, "Q1_D_TRT")
ctxq <- function(rid, ed) list(ledger = file.path(SAQ, "stage_artifacts/programs/P1_RETURN", rid, "standing_ledger.jsonl"), spec = list(round_id = rid), cfg = list(edition = ed), prereg_md5 = "v3test")
put <- function(ctx, code, eng, sp, k, q) {
  rc_standing_append(ctx, list(event = "enqueue", code = code, engine = code, role = "reference", source = "seed", engine_path = eng, engine_md5 = md5(eng),
                               cell_spec = sp, cell_spec_md5 = md5(sp), paper = paper(k), family_root = k, n_family = 1L))
  rc_standing_append(ctx, list(event = "measure", code = code, ok = TRUE, fp_same = TRUE, artifacts = file.path(SB, "qart", code)))
  rc_standing_append(ctx, list(event = "verdict", code = code, qualify = q, visible = list(uc_vis = 0.6)))
}
Q1 <- ctxq("P1S81_v3q", 1L); Q2 <- ctxq("P1S82_v3q", 2L)
invisible({
  put(Q1, "Q1_A", EA, std("Q1_A", EA, "2001.00011"), "2001.00011", TRUE);  put(Q2, "Q2_A", EA, std("Q2_A", EA, "2001.00011"), "2001.00011", FALSE)   # 앞 판 통과 · 뒤 판 미달
  put(Q1, "Q1_B", EB, std("Q1_B", EB, "2001.00012"), "2001.00012", FALSE); put(Q2, "Q2_B", EB, std("Q2_B", EB, "2001.00012"), "2001.00012", TRUE)    # 앞 판 미달 · 뒤 판 통과
  put(Q1, "Q1_C", EC, std("Q1_C", EC, "2001.00013"), "2001.00013", TRUE)                                                                               # 한 판만
  put(Q1, "Q1_D_TRT", ED, SP_DT, "2001.00014", TRUE); put(Q2, "Q2_D", ED, std("Q2_D", ED, "2001.00014"), "2001.00014", FALSE)                         # 다른 구성(처치 vs 표준)
  put(Q2, "Q2_U", EC, std("Q2_U", EC, "2001.00013"), "2001.00013", NA)                                                                                               # 뒤 판 미시험(qualify NA) — 표준 C
})
RIDS <- c("P1S81_v3q", "P1S82_v3q")
QQ <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SAQ)[round_id %in% RIDS]
Qv2 <- run_core("v2", sprintf('.res <- rc_standing_qualified("P1_RETURN", root = "%s", sa_root = "%s")[round_id %%in%% c("P1S81_v3q", "P1S82_v3q")]', ROOT, SAQ), "qual_v2")
chk("Q0 대조 · v2 = 판마다 통과를 그대로 모은다(Q1_A · Q2_B · Q1_C · Q1_D_TRT — 앞 판 통과 Q1_A 가 남는다)", setequal(Qv2$code, c("Q1_A", "Q2_B", "Q1_C", "Q1_D_TRT")), paste(Qv2$code))
chk("Q1 v3 · 앞 판 통과 + 뒤 판 미달 = 자격 없음(Q1_A 빠짐) · 앞 판 미달 + 뒤 판 통과 = 뒤 판 통과(Q2_B)", !("Q1_A" %in% QQ$code) && "Q2_B" %in% QQ$code, paste(QQ$code))
chk("Q2 v3 · 뒤 판 미시험(qualify NA)도 판정으로 센다 — 앞 판 통과 Q1_C 빠짐(fail-closed)", !("Q1_C" %in% QQ$code), paste(QQ$code))
chk("Q3 v3 · 다른 구성(처치 칸 Q1_D_TRT vs 표준 칸 Q2_D 미달)은 따로 — 처치 칸 통과 유지", "Q1_D_TRT" %in% QQ$code && identical(QQ[code == "Q1_D_TRT"]$construction, "treatment"), paste(QQ$code))
chk("Q4 v3 열 = v2 열(같은 이름 · 같은 순서 — P4 기저 풀 입력 형식 불변)", identical(names(QQ), names(Qv2)), setdiff(union(names(QQ), names(Qv2)), intersect(names(QQ), names(Qv2))))
SAQ1 <- file.path(SB, "saq1"); dir.create(file.path(SAQ1, "stage_artifacts/programs/P1_RETURN/P1S81_v3q"), recursive = TRUE)
invisible(file.copy(Q1$ledger, file.path(SAQ1, "stage_artifacts/programs/P1_RETURN/P1S81_v3q/standing_ledger.jsonl")))
Q1o <- rc_standing_qualified("P1_RETURN", root = ROOT, sa_root = SAQ1)[round_id %in% RIDS]
Q1v2 <- run_core("v2", sprintf('.res <- rc_standing_qualified("P1_RETURN", root = "%s", sa_root = "%s")[round_id %%in%% c("P1S81_v3q", "P1S82_v3q")]', ROOT, SAQ1), "qual1_v2")
chk("Q5 판정이 한 판에만 있으면 v2 와 같다(행 · 열 · 값 — 판 1 원장만)", identical(names(Q1o), names(Q1v2)) && isTRUE(all.equal(as.data.frame(Q1o), as.data.frame(Q1v2), check.attributes = FALSE)), paste(Q1o$code, "|", Q1v2$code))

## ═══ X. 돌연변이 대조 — 소스 텍스트 치환 사본(deparse 아님) · 치환 성사 단정 · 사본은 격리 환경에 적재 ═══════════════
MU1 <- mutant("  P <- P[!is.na(d) & d <= as.Date(tau)]   # τ_D 절단(세기 전에) — rc_standing_breadth:tau_cut", "  P <- P[!is.na(d)]", "taucut")
CM1 <- if (MU1$loaded) MU1$env$rc_standing_lane_candidates(SC, registry_path = REG, tau = TAU, lane_root = LANE) else NULL
chk("X1 돌연변이(τ_D 절단 줄 제거) — 치환 1곳 성사 · 사본 단독 적재 · τ_D 음성 대조가 red(POSTTAU 가 통과로 바뀐다) · 원본은 green",
    MU1$k == 1L && MU1$changed && MU1$loaded && !is.null(CM1) && isTRUE(CM1[dir == "RP_AUTO_V3_POSTTAU"]$eligible) && has_reason(C, "RP_AUTO_V3_POSTTAU", "breadth_insufficient"),
    c(MU1$k, if (!is.null(CM1)) CM1[dir == "RP_AUTO_V3_POSTTAU"]$reasons))
MU2 <- mutant('      else if (!("FACTORS" %in% st$outputs)) rs <- c(rs, "portfolio_only_base")', "", "portonly")
CM2 <- if (MU2$loaded) MU2$env$rc_standing_lane_candidates(SC, registry_path = REG, tau = TAU, lane_root = LANE) else NULL
chk("X2 돌연변이(portfolio_only_base 줄 제거) — 치환 1곳 · 포트폴리오만 내는 엔진이 입구 통과로 바뀐다(red)",
    MU2$k == 1L && MU2$loaded && !is.null(CM2) && isTRUE(CM2[dir == "RP_AUTO_V3_PORT"]$eligible), c(MU2$k, if (!is.null(CM2)) CM2[dir == "RP_AUTO_V3_PORT"]$reasons))
MU3 <- mutant('  if (any(bk != "factors")) return(bad(', '  if (FALSE) return(bad(', "kind")
chk("X3 돌연변이(base_kind 검사 제거) — 치환 1곳 · 비중 기저 진단이 ok 로 바뀐다(red)",
    MU3$k == 1L && MU3$loaded && isTRUE(MU3$env$rc_standing_base_alignment(I[[c_post]]$cell_spec, file.path(SB, "meas_art", "pw"), TAU, ROOT)$ok))

MU4 <- mutant('  if (isFALSE(gr$ok)) rs <- c(rs, "base_off_month_grid")', "", "grid")
CM4 <- if (MU4$loaded) MU4$env$rc_standing_lane_candidates(SC, registry_path = REG, tau = TAU, lane_root = LANE) else NULL
chk("X4 돌연변이(격자 사유 줄 제거) — 치환 1곳 · 주간 엔진이 입구 통과로 바뀐다(red)", MU4$k == 1L && MU4$loaded && !is.null(CM4) && isTRUE(CM4[dir == "RP_AUTO_V3_WEEKLY"]$eligible))

## ═══ 실제 원장 무접촉 ═══════════════════════════════════════════════════════════
REAL1 <- vapply(REAL, function(f) if (file.exists(f)) md5(f) else "absent", ""); names(REAL1) <- REAL
chk("Z1 실제 등록부 · 판 표식 원장 · P1S01 원장 · GPU 임대 · RELEASES md5 불변", identical(REAL0, REAL1), REAL[REAL0 != REAL1])
shtxt <- unlist(lapply(SHARED, function(f) if (file.exists(f)) readLines(f, encoding = "UTF-8", warn = FALSE) else character(0)))
chk("Z2 실제 판단 원장 · 결정 기록부에 이 시험의 표식 없음(P1S97_v3_selftest · P1S9[67] · _v3q · 9931.)", !any(grepl("P1S97_v3_selftest|P1S96_axis|_v3q|9931[.]0", shtxt)))
Sys.unsetenv("RC_SA_ROOT")
cat(sprintf("\n== test_round_core_v3: %d ok · %d FAIL ==\n", PASS, FAIL))
cat(sprintf('{"test":"round_core_v3","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL) 1L else 0L)
