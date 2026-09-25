# test_m4_append_c11_inherit.R — m4 발행 원장의 C11 표식 승계 · init 재설계 · epoch 재초기화 (양방향)
#
# 배경 (2026-09-24 · PIT C11 판정서 V-04 · 사후검증 NON-BLOCKING "m4_append_only.R:165·264·267 도 같은 병합 방식이라
#   c11 열을 지운다 — 10-03 09:00 에 m4 행이 unresolved 로 찍히고 pg2 arm 은 계속 정지"):
#   factor_engine.R 은 행마다 c11_info_cutoff · c11_regime_key · c11_status 를 싣는데, 게이트의 병합
#   `add[, .SD, .SDcols = names(pub)]` 과 두 쓰기(발행 원장 · 운영 패널)가 발행 원장 열 이름으로 잘라 표식을 버렸다.
#   결정 PIT-C11-P2-AUX ② = 구판 보관 후 C11 epoch 재초기화 → m4_epoch_reinit.R + --init 재설계.
#
# 방식: **배포 파일을 그대로 서브프로세스로 실행**한다(재구현 금지). 샌드박스 루트마다 픽스처(발행 원장 ·
#   재생성 패널 · unified 월간 MSM · 규칙 파일·가용시점 층 사본)를 깔고 CLAUDE_PROJECT_DIR/QM_ROOT 를 그 루트로 준다.
#   돌연변이는 배포 파일 텍스트를 수술해 만든다(수리 줄 제거 → 구판 동작) — 검사가 수리를 실제로 재는지 red 로 확인.
#
# 축:
#   A  [양성] 구 원장(표식 없음) + 표식 실은 신규 행 → 원장·운영 패널이 표식 3열 승계, 기발행 행 unresolved, 신규 verified
#   A2 [양성] 표식 원장 위 다음 달 → 승계 유지(재승계 로그 없음) · 사이드카에 표식
#   B  [위반 주입] verified 인데 컷오프 > 결정일 → exit 4 · 원장 무변경 / 상태값 미지 → exit 4
#   C  [계약] 표식 일부만 → exit 2 / 원장은 표식인데 신규 행 표식 없음(상류 퇴행) → exit 2
#   D  [경고·비차단] unresolved 신규 행 → exit 0 + 경고 · epoch 불일치 → exit 0 + 경고
#   E  [init] 원장 부재 + --init → 월 첫 행·AS_OF 이하만 · 운영 패널·사이드카 동기화 / 원장 있음 + --init → exit 2
#   R  [재초기화] dry-run = 쓰기 0 · 전제 미충족(unresolved) exit 5 · 사유 없는 --apply exit 2 · apply = 보관(md5)·이관·
#      새 기준선·PROVENANCE·drift 로그 · 귀속(국면 입력 변경 = regime / 입력 불변 = logic) · init 실패 → 원복(exit 6)
#   MUT-1 승계 블록 제거(구판 병합) → A 가 red · MUT-2 구판 init(재생성본 통째 동결) → E 가 red ·
#   MUT-3 C11 위반 차단 제거 → B 가 red
#
# 실행: Rscript 08_Tests/regime/test_m4_append_c11_inherit.R   (운영 트리 무접촉 — 전부 tempdir)
suppressPackageStartupMessages({ library(data.table); library(arrow); library(jsonlite) })

.self <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) dirname(f[1]) else NA_character_
}, error = function(e) NA_character_)
GATE_REL <- "02_Infrastructure/regime/m4_append_only.R"
REINIT_REL <- "02_Infrastructure/regime/m4_epoch_reinit.R"
.pick <- function() {
  for (c in c(if (!is.na(.self)) file.path(.self, "..", ".."), Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""))) {
    if (!nzchar(c)) next
    c <- gsub("\\\\", "/", c)
    if (file.exists(file.path(c, GATE_REL)) && file.exists(file.path(c, REINIT_REL))) return(c)
  }
  NA_character_
}
ROOT <- .pick()
if (is.na(ROOT)) { cat("PROJECT_ROOT 해석 실패 — 표지", GATE_REL, "/", REINIT_REL, "없음\n"); quit(status = 2) }
## 규칙·가용시점 층은 데이터 루트(운영)에서 **읽기만** 한다 — 코드 루트(self)가 스테이징 트리일 수 있다
DATA_ROOT <- gsub("\\\\", "/", Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
FA_SRC <- Filter(file.exists, c(file.path(ROOT, "02_Infrastructure/data/fred_availability.R"),
                                file.path(DATA_ROOT, "02_Infrastructure/data/fred_availability.R")))[1]
RULES_SRC <- Filter(file.exists, c(file.path(ROOT, "06_Registry/fred_availability_rules.json"),
                                   file.path(DATA_ROOT, "06_Registry/fred_availability_rules.json")))[1]
if (is.na(FA_SRC) || is.na(RULES_SRC)) { cat("가용시점 층(fred_availability.R · rules json) 부재\n"); quit(status = 2) }
KEY <- local({ e <- new.env(); suppressMessages(sys.source(FA_SRC, envir = e)); e$fred_avail_rules_meta(RULES_SRC)$regime_key })

pass <- 0L; fail <- 0L
ok <- function(m) { cat(sprintf("  [PASS] %s\n", m)); pass <<- pass + 1L }
ng <- function(m) { cat(sprintf("  [FAIL] %s\n", m)); fail <<- fail + 1L }
chk <- function(cond, m, detail = "") if (isTRUE(cond)) ok(m) else ng(paste0(m, if (nzchar(detail)) paste0(" — ", detail) else ""))

GATE_TXT <- readLines(file.path(ROOT, GATE_REL), warn = FALSE, encoding = "UTF-8")
REINIT_TXT <- readLines(file.path(ROOT, REINIT_REL), warn = FALSE, encoding = "UTF-8")
## 샌드박스 경로 길이 — 보관 디렉터리가 깊다(Windows 260자). 긴 TMPDIR(세션 스크래치 ~147자)에서 가짜 red 가 나지 않게 짧은 기저로
.tbase <- if (nchar(tempdir()) <= 60L) tempdir() else file.path(Sys.getenv("SystemDrive", "C:"), "tmp")
TD <- file.path(.tbase, paste0("m4c11_", Sys.getpid())); dir.create(TD, recursive = TRUE, showWarnings = FALSE)
RS <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
EMPTY_RENV <- file.path(TD, "empty.Renviron"); writeLines(character(0), EMPTY_RENV)

## ── 픽스처 ──────────────────────────────────────────────────────────────────
## 결정행 = 월 첫 거래일. MSM_Crisis_Prob_lag = 직전월 말 unified 값(원칙 2 검사 통과형).
MAC <- data.table(Date = as.Date(c("2026-04-30", "2026-05-29", "2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30")),
                  MSM_Crisis_Prob = c(0.11, 0.22, 0.33, 0.44, 0.55, 0.66))
mk_rows <- function(dates, c11 = TRUE, status = "verified", key = KEY, cut_add = 1L) {
  d <- as.Date(dates)
  prev_end <- vapply(d, function(x) as.character(max(MAC$Date[MAC$Date < as.Date(format(x, "%Y-%m-01"))])), "")
  msm <- MAC$MSM_Crisis_Prob[match(as.Date(prev_end), MAC$Date)]
  dt <- data.table(Date = d, YM = format(d, "%Y-%m"), ret_net = 0.01, Regime_Score_lag = 40, Cash_Pct_lag = 0.1,
                   MSM_Crisis_Prob_lag = msm, bocpd_norm = 0.1, decay_signal = 0.2, combined_regime = 0.4,
                   conjunction_score = 0, weight_str1715 = 1.0, weight_cash = 0)
  if (c11) {
    dt[, c11_info_cutoff := as.Date(prev_end) + cut_add]   # 기본: 직전월 말 다음날(<= 결정일)
    dt[, c11_regime_key := key]
    dt[, c11_status := status]
  }
  dt
}
mk_root <- function(tag, pub, fresh, gate_txt = GATE_TXT, reinit_txt = REINIT_TXT) {
  r <- file.path(TD, tag)
  for (d in c("qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts", "stage_artifacts", "06_Registry/m4_published",
              ".cache", "02_Infrastructure/regime", "02_Infrastructure/data"))
    dir.create(file.path(r, d), recursive = TRUE, showWarnings = FALSE)
  write_parquet(fresh, file.path(r, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet"))
  if (!is.null(pub)) write_parquet(pub, file.path(r, "06_Registry/m4_published/m4_panel_published.parquet"))
  write_parquet(MAC, file.path(r, ".cache/unified_regime_signal.parquet"))
  writeLines(gate_txt, file.path(r, GATE_REL), useBytes = TRUE)
  writeLines(reinit_txt, file.path(r, REINIT_REL), useBytes = TRUE)
  file.copy(FA_SRC, file.path(r, "02_Infrastructure/data/fred_availability.R"))
  file.copy(RULES_SRC, file.path(r, "06_Registry/fred_availability_rules.json"))
  r
}
## 금칙 ①: system2(env=) 금지 → Sys.setenv + 복원
run_script <- function(root, rel, args) {
  keys <- c("CLAUDE_PROJECT_DIR", "QM_ROOT", "R_ENVIRON_USER")
  old <- Sys.getenv(keys, unset = NA)
  Sys.setenv(CLAUDE_PROJECT_DIR = root, QM_ROOT = root, R_ENVIRON_USER = EMPTY_RENV)
  out <- tryCatch(suppressWarnings(system2(RS, c("--no-save", shQuote(file.path(root, rel)), args), stdout = TRUE, stderr = TRUE)),
                  finally = for (k in keys) if (is.na(old[[k]])) Sys.unsetenv(k) else do.call(Sys.setenv, setNames(list(old[[k]]), k)))
  rc <- attr(out, "status"); if (is.null(rc)) rc <- 0L
  list(rc = as.integer(rc), out = paste(out, collapse = "\n"))
}
gate <- function(root, as_of, extra = character(0)) run_script(root, GATE_REL, c("--as-of", as_of, extra))
PUBP <- function(r) file.path(r, "06_Registry/m4_published/m4_panel_published.parquet")
PANP <- function(r) file.path(r, "qepm/mailbox/worktask/WT-D20260430_001/stage_artifacts/alpha_scores.parquet")
rd <- function(p) { x <- as.data.table(read_parquet(p, mmap = FALSE)); x[, Date := as.Date(Date)]; x[order(Date)] }
md5_dir <- function(d) { f <- sort(list.files(d, recursive = TRUE, full.names = TRUE, all.files = TRUE)); setNames(unname(tools::md5sum(f)), sub(d, "", f, fixed = TRUE)) }

## 돌연변이 수술 — 배포 텍스트에서 수리 블록을 제거/구판으로 치환(표지 줄이 없으면 돌연변이 무효로 FAIL)
cut_block <- function(txt, from_pat, to_pat) {
  i <- grep(from_pat, txt, fixed = TRUE)[1]; j <- grep(to_pat, txt, fixed = TRUE); j <- j[j > i][1]
  if (is.na(i) || is.na(j)) return(NULL)
  txt[-(i:(j - 1L))]
}
MUT1 <- cut_block(GATE_TXT, "## ★PIT C11 표식 승계 (2026-09-24", "final <- if (nrow(add)) rbindlist(")
MUT2 <- local({ i <- grep("pub <- fresh[0L]", GATE_TXT, fixed = TRUE)
  if (length(i) != 1L) NULL else { t <- GATE_TXT; t[i] <- "  write_parquet(fresh, PUB); quit(status = 0)  # 구판 init 동작"; t } })
MUT3 <- local({ i <- grep("if (length(c11c$viol)) {", GATE_TXT, fixed = TRUE)
  if (length(i) != 1L) NULL else { t <- GATE_TXT; t[i] <- "if (FALSE) {"; t } })

cat(strrep("=", 78), "\n", "test_m4_append_c11_inherit — 표식 승계 · init · epoch 재초기화 (epoch ", KEY, ")\n", strrep("=", 78), "\n", sep = "")
LEG_DATES <- c("2026-06-01", "2026-07-01", "2026-08-03")
pub_legacy <- mk_rows(LEG_DATES, c11 = FALSE)

## ── A. 양성 대조 ─────────────────────────────────────────────────────────────
fresh_A <- rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01"))
rA <- mk_root("A", pub_legacy, fresh_A)
g <- gate(rA, "2026-09-01")
pA <- if (file.exists(PUBP(rA))) rd(PUBP(rA)) else data.table()
chk(g$rc == 0L, "A1 구 원장(표식 없음) + 표식 신규 행 → exit 0", sprintf("rc=%d %s", g$rc, substr(g$out, nchar(g$out) - 300, nchar(g$out))))
chk(all(c("c11_info_cutoff", "c11_regime_key", "c11_status") %in% names(pA)), "A2 ★발행 원장이 표식 3열 승계", paste(names(pA), collapse = ","))
if (all(c("c11_status", "c11_info_cutoff") %in% names(pA))) {
  chk(identical(pA[Date < as.Date("2026-09-01"), unique(c11_status)], "unresolved") &&
        all(is.na(pA[Date < as.Date("2026-09-01"), c11_info_cutoff])),
      "A3 기발행 3행 = unresolved · 컷오프 NA(값 재서술 아님)")
  r9 <- pA[Date == as.Date("2026-09-01")]
  chk(nrow(r9) == 1L && r9$c11_status == "verified" && identical(r9$c11_regime_key, KEY) &&
        identical(as.Date(r9$c11_info_cutoff), as.Date("2026-09-01")),
      "A4 신규 행 verified · epoch 키 · 컷오프(08-31 다음날 = 결정일) 보존")
  chk(isTRUE(all.equal(pA[Date < as.Date("2026-09-01"), .(Date, weight_str1715, MSM_Crisis_Prob_lag)],
                       pub_legacy[, .(Date, weight_str1715, MSM_Crisis_Prob_lag)], check.attributes = FALSE)),
      "A5 기발행 행 값 불변(append-only 유지)")
}
pn <- if (file.exists(PANP(rA))) rd(PANP(rA)) else data.table()
chk("c11_status" %in% names(pn) && nrow(pn) == nrow(pA), "A6 ★운영 패널(:267 쓰기)도 표식 보존 — 배포 생성기가 읽는 면")
sj <- file.path(rA, "06_Registry/m4_published/m4_published_ledger.jsonl")
chk(file.exists(sj) && any(grepl('"c11_status":"verified"', readLines(sj, warn = FALSE), fixed = TRUE)), "A7 사이드카(git 추적)에 표식")
dl <- file.path(rA, "06_Registry/m4_published/m4_drift_log.jsonl")
chk(file.exists(dl) && grepl('"added_verified":1', paste(readLines(dl, warn = FALSE), collapse = ""), fixed = TRUE),
    "A8 드리프트 로그에 C11 요약(added_verified=1)")
chk(grepl("표식 열 3개 승계", g$out, fixed = TRUE), "A9 승계가 침묵하지 않음(로그 문구)")

## A2 — 표식 원장 위 다음 달
fresh_A2 <- rbind(if (all(names(fresh_A) %in% names(pA))) pA[, names(fresh_A), with = FALSE] else copy(fresh_A),  # 구판이면 표식 소실 → 재생성본으로
                  mk_rows("2026-10-01"))
fresh_A2[Date < as.Date("2026-09-01"), `:=`(c11_status = "verified", c11_info_cutoff = Date, c11_regime_key = KEY)]  # 재생성본은 전 행 표식
write_parquet(fresh_A2, PANP(rA))
g2 <- gate(rA, "2026-10-01")
pA2 <- if (file.exists(PUBP(rA))) rd(PUBP(rA)) else data.table()
chk(g2$rc == 0L && nrow(pA2) == 5L && "c11_status" %in% names(pA2) && identical(pA2[Date == as.Date("2026-10-01"), c11_status], "verified"),
    "A10 표식 원장 위 다음 달 → 승계 유지 · 신규 verified", sprintf("rc=%d n=%d", g2$rc, nrow(pA2)))
chk("c11_status" %in% names(pA2) && identical(pA2[Date < as.Date("2026-09-01"), unique(c11_status)], "unresolved") && grepl("C11 표식 드리프트(로그): status 3행", g2$out, fixed = TRUE),
    "A11 기발행 표식은 발행 시점 기록으로 유지 + 재생성본과의 표식 차이는 로그(status 3행)")

## ── B. 위반 주입 ─────────────────────────────────────────────────────────────
fresh_B <- rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01", cut_add = 6L))   # 컷오프 = 09-06 > 결정일
rB <- mk_root("B", pub_legacy, fresh_B); h0 <- md5_dir(file.path(rB, "06_Registry"))
gB <- gate(rB, "2026-09-01")
chk(gB$rc == 4L && grepl("PIT C11 위반", gB$out, fixed = TRUE), "B1 ★verified 컷오프 > 결정일 → exit 4", sprintf("rc=%d", gB$rc))
chk(identical(h0, md5_dir(file.path(rB, "06_Registry"))), "B2 차단 시 원장 디렉터리 무변경")
fresh_B3 <- rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01", status = "ok"))
gB3 <- gate(mk_root("B3", pub_legacy, fresh_B3), "2026-09-01")
chk(gB3$rc == 4L, "B3 ★상태값 계약 밖('ok') → exit 4", sprintf("rc=%d", gB3$rc))

## ── C. 계약 ──────────────────────────────────────────────────────────────────
fresh_C1 <- rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01"))[, c11_status := NULL]
gC1 <- gate(mk_root("C1", pub_legacy, fresh_C1), "2026-09-01")
chk(gC1$rc == 2L && grepl("일부만", gC1$out, fixed = TRUE), "C1 표식 일부만(상태 열 결손) → exit 2", sprintf("rc=%d", gC1$rc))
pub_c11 <- mk_rows(LEG_DATES)
fresh_C2 <- rbind(mk_rows(LEG_DATES, c11 = FALSE), mk_rows("2026-09-01", c11 = FALSE))
gC2 <- gate(mk_root("C2", pub_c11, fresh_C2), "2026-09-01")
chk(gC2$rc == 2L && grepl("C11 표식 열 결손", gC2$out, fixed = TRUE), "C2 ★표식 원장 + 표식 없는 신규 행(상류 퇴행) → exit 2", sprintf("rc=%d", gC2$rc))

## ── D. 경고·비차단 ───────────────────────────────────────────────────────────
gD1 <- gate(mk_root("D1", pub_legacy, rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01", status = "unresolved"))), "2026-09-01")
chk(gD1$rc == 0L && grepl("unresolved — 상류 unified", gD1$out, fixed = TRUE), "D1 unresolved 신규 행 → exit 0 + 경고(결정 BOOK0001 '표기')", sprintf("rc=%d", gD1$rc))
gD2 <- gate(mk_root("D2", pub_legacy, rbind(mk_rows(LEG_DATES), mk_rows("2026-09-01", key = "c11_avail:OLD"))), "2026-09-01")
chk(gD2$rc == 0L && grepl("epoch 'c11_avail:OLD'", gD2$out, fixed = TRUE), "D2 epoch 불일치 → exit 0 + 경고", sprintf("rc=%d", gD2$rc))

## ── E. init 재설계 ───────────────────────────────────────────────────────────
fresh_E <- rbind(mk_rows(c(LEG_DATES, "2026-09-01")), mk_rows("2026-09-18"), mk_rows("2026-10-01"))  # 꼬리 행 + AS_OF 뒤 행
rE <- mk_root("E", NULL, fresh_E)
gE <- gate(rE, "2026-09-01", "--init")
pE <- if (file.exists(PUBP(rE))) rd(PUBP(rE)) else data.table()
chk(gE$rc == 0L && identical(as.character(pE$Date), c(LEG_DATES, "2026-09-01")),
    "E1 ★--init = 월 첫 행 · AS_OF 이하만(꼬리 09-18 · 10-01 제외)", sprintf("rc=%d dates=%s", gE$rc, paste(pE$Date, collapse = ",")))
chk(file.exists(PANP(rE)) && nrow(rd(PANP(rE))) == 4L && file.exists(file.path(rE, "06_Registry/m4_published/m4_published_ledger.jsonl")) &&
      file.exists(file.path(rE, "stage_artifacts/WT-D20260430_001_m4_extended.csv")),
    "E2 init 도 운영 패널·m4_extended·사이드카 동기화")
gE3 <- gate(rE, "2026-09-01", "--init")
chk(gE3$rc == 2L && grepl("이미 있다", gE3$out, fixed = TRUE), "E3 ★원장 있음 + --init → exit 2(구판은 말없이 병합 경로)", sprintf("rc=%d", gE3$rc))
rE4 <- mk_root("E4", NULL, fresh_E); h4 <- md5_dir(file.path(rE4, "06_Registry"))
gE4 <- gate(rE4, "2026-09-01", c("--init", "--dry-run"))
chk(gE4$rc == 0L && identical(h4, md5_dir(file.path(rE4, "06_Registry"))), "E4 --init --dry-run → 쓰기 0")

## ── R. epoch 재초기화 ────────────────────────────────────────────────────────
## 새 기준선: 07-01 = 국면 입력 변경 + 결정 변경(regime) · 08-03 = 입력 불변 + 결정 변경(logic)
fresh_R <- mk_rows(c(LEG_DATES, "2026-09-01"))
fresh_R[Date == as.Date("2026-07-01"), `:=`(Regime_Score_lag = 55, weight_str1715 = 0.7, weight_cash = 0.3)]
fresh_R[Date == as.Date("2026-08-03"), `:=`(weight_str1715 = 0.92, weight_cash = 0.08)]
pub_R <- mk_rows(c(LEG_DATES, "2026-09-01"), c11 = FALSE)
reinit <- function(root, args) run_script(root, REINIT_REL, c("--as-of", "2026-09-01", args))
rR <- mk_root("R", pub_R, fresh_R)
writeLines("# 구 epoch 라벨", file.path(rR, "06_Registry/m4_published/PROVENANCE_bocpd_guard_defect.md"))
hR <- md5_dir(file.path(rR, "06_Registry")); hRp <- md5_dir(file.path(rR, "qepm"))
rep_p <- file.path(TD, "R_report.json")
d1 <- reinit(rR, c("--report", rep_p))
chk(d1$rc == 0L && identical(hR, md5_dir(file.path(rR, "06_Registry"))) && identical(hRp, md5_dir(file.path(rR, "qepm"))),
    "R1 ★dry-run(기본) = exit 0 · 원장·패널 쓰기 0", sprintf("rc=%d", d1$rc))
rj <- if (file.exists(rep_p)) fromJSON(rep_p) else list()
chk(identical(as.integer(rj$decision_changed), 2L) && identical(as.integer(rj$attribution[["regime"]]), 1L) &&
      identical(as.integer(rj$attribution[["logic(입력 배경 수준)"]]), 1L),
    "R2 ★귀속 재도출 — 07-01 regime · 08-03 logic(입력 불변 = 엔진 로직 몫)", toJSON(rj$attribution, auto_unbox = TRUE))
rR3 <- mk_root("R3", pub_R, mk_rows(c(LEG_DATES, "2026-09-01"), status = "unresolved"))
d3 <- reinit(rR3, character(0))
chk(d3$rc == 5L && grepl("P2 unresolved", d3$out, fixed = TRUE), "R3 ★전제 미충족(재생성본 unresolved) → exit 5", sprintf("rc=%d", d3$rc))
rR3b <- mk_root("R3b", pub_R, mk_rows(c(LEG_DATES, "2026-09-01"), key = "c11_avail:OLD"))
d3b <- reinit(rR3b, character(0))
chk(d3b$rc == 5L && grepl("P4 epoch", d3b$out, fixed = TRUE), "R3b 전제 미충족(옛 epoch) → exit 5", sprintf("rc=%d", d3b$rc))
d4 <- reinit(rR, "--apply")
chk(d4$rc == 2L && identical(hR, md5_dir(file.path(rR, "06_Registry"))), "R4 사유 없는 --apply → exit 2 · 무변경", sprintf("rc=%d", d4$rc))
d5 <- reinit(rR, c("--apply", "TEST: PIT-C11-P2-AUX 2 fixture"))
pR <- if (file.exists(PUBP(rR))) rd(PUBP(rR)) else data.table()
arch <- list.dirs(file.path(rR, "06_Registry/m4_published/_epoch_archive"), recursive = FALSE)
chk(d5$rc == 0L && length(arch) == 1L, "R5 apply → exit 0 · 보관 디렉터리 1개", sprintf("rc=%d %s", d5$rc, substr(d5$out, max(1, nchar(d5$out) - 400), nchar(d5$out))))
if (length(arch) == 1L) {
  chk(identical(unname(tools::md5sum(file.path(arch, "m4_panel_published.parquet"))),
                unname(hR[["/m4_published/m4_panel_published.parquet"]])),
      "R6 구판 원장 보관본 md5 = 적용 전 원장")
  chk(file.exists(file.path(arch, "PROVENANCE_bocpd_guard_defect.md.live_at_reinit")) &&
        !file.exists(file.path(rR, "06_Registry/m4_published/PROVENANCE_bocpd_guard_defect.md")) &&
        file.exists(file.path(rR, "06_Registry/m4_published/PROVENANCE_c11_epoch.md")),
      "R7 구 epoch PROVENANCE 이관 · 새 PROVENANCE_c11_epoch.md")
  chk(file.exists(file.path(arch, "reinit_drift_report.json")), "R8 보관 디렉터리에 드리프트 귀속 보고")
}
chk(nrow(pR) == 4L && "c11_status" %in% names(pR) && all(pR$c11_status == "verified") && identical(pR[Date == as.Date("2026-07-01"), weight_str1715], 0.7),
    "R9 새 기준선 = 표식 재생성본(전 행 verified · 07-01 새 값)")
dlR <- readLines(file.path(rR, "06_Registry/m4_published/m4_drift_log.jsonl"), warn = FALSE)
chk(any(grepl('"event":"epoch_reinit"', dlR, fixed = TRUE)) && any(grepl('"init":true', dlR, fixed = TRUE)), "R10 drift 로그 = init 기록 + epoch_reinit 기록")
## 원복 — 게이트가 실패하면(스텁 exit 3) 이관을 되돌린다
stub <- c("cat('[stub] init 실패 주입\\n')", "quit(status = 3)")
rR11 <- mk_root("R11", pub_R, fresh_R, gate_txt = stub); h11 <- tools::md5sum(PUBP(rR11))
d11 <- reinit(rR11, c("--apply", "TEST restore"))
chk(d11$rc == 6L && identical(unname(tools::md5sum(PUBP(rR11))), unname(h11)), "R11 ★init 실패 → exit 6 · 원장 원복(md5 동일)", sprintf("rc=%d", d11$rc))

## ── R12/R13 (2026-09-25 적대 검증 M4AE NB-1·NB-2 수리) ──────────────────────────────
## R12 P8: 구 원장에 AS_OF 뒤 발행 월(10-01)이 있는데 --as-of 09-01 → exit 5 · 무변경(구판 = exit 0 + 10-01 조용히 소실)
pub_12 <- mk_rows(c(LEG_DATES, "2026-09-01", "2026-10-01"), c11 = FALSE)
fresh_12 <- mk_rows(c(LEG_DATES, "2026-09-01", "2026-10-01"))
rR12 <- mk_root("R12", pub_12, fresh_12); h12 <- md5_dir(file.path(rR12, "06_Registry"))
d12 <- reinit(rR12, c("--apply", "TEST P8"))
chk(d12$rc == 5L && grepl("P8", d12$out, fixed = TRUE) && identical(h12, md5_dir(file.path(rR12, "06_Registry"))),
    "R12 ★P8 AS_OF(09) < 구 원장 최신 발행 월(10) → exit 5 · 원장 무변경", sprintf("rc=%d", d12$rc))
d12b <- run_script(rR12, REINIT_REL, c("--as-of", "2026-10-01"))
chk(d12b$rc == 0L, "R12b 양성: --as-of = 최신 발행 월(10-01) → 전제 통과(dry-run)", sprintf("rc=%d", d12b$rc))
MUTP8 <- sub('if (!is.na(.old_last_m) && .old_last_m > format(AS_OF, "%Y-%m"))', 'if (FALSE)', REINIT_TXT, fixed = TRUE)
if (identical(MUTP8, REINIT_TXT)) ng("MUT-P8 돌연변이 수술 실패(표지 줄 부재)") else {
  rM8 <- mk_root("MP8", pub_12, fresh_12, reinit_txt = MUTP8); dm8 <- reinit(rM8, c("--apply", "TEST MUT-P8"))
  pm8 <- if (file.exists(PUBP(rM8))) rd(PUBP(rM8)) else data.table(Date = as.Date(character(0)))
  chk(dm8$rc == 0L && !any(pm8$Date == as.Date("2026-10-01")),
      "MUT-P8 ★P8 제거 → 발행된 10-01 행이 새 원장에서 조용히 빠진다(exit 0 · 적대 검증 재현) = R12 가 red 를 낸다", sprintf("rc=%d", dm8$rc))
}
## R13 라벨 이동 달(08-01 → 08-03) 결정값 비교가 보고서 label_moved 에 실린다(공통 날짜 집계 밖)
pub_13 <- mk_rows(c("2026-06-01", "2026-07-01", "2026-08-01", "2026-09-01"), c11 = FALSE)
fresh_13 <- mk_rows(c("2026-06-01", "2026-07-01", "2026-08-03", "2026-09-01"))
fresh_13[Date == as.Date("2026-08-03"), `:=`(weight_str1715 = 0.8064, weight_cash = 0.1936)]
rep13 <- file.path(TD, "R13_report.json"); d13 <- reinit(mk_root("R13", pub_13, fresh_13), c("--report", rep13))
r13 <- if (file.exists(rep13)) fromJSON(rep13) else list()
lm <- r13$label_moved
chk(d13$rc == 0L && is.data.frame(lm) && nrow(lm) == 1L && identical(lm$month, "2026-08") && identical(lm$new_date, "2026-08-03") &&
      isTRUE(lm$decision_changed) && isTRUE(abs(lm$w_new - 0.8064) < 1e-12),
    "R13 라벨 이동 달 2026-08(08-01→08-03) 결정값 변경이 보고서 label_moved 에 실린다", sprintf("rc=%d", d13$rc))

## ── MUT. 검출력 실증 — 수리 줄을 걷어낸 배포 텍스트는 같은 입력에서 red ────────────
if (is.null(MUT1)) ng("MUT-1 돌연변이 수술 실패(표지 줄 부재) — 검사 무효") else {
  rM1 <- mk_root("M1", pub_legacy, fresh_A, gate_txt = MUT1); gm <- gate(rM1, "2026-09-01")
  pm <- if (file.exists(PUBP(rM1))) rd(PUBP(rM1)) else data.table()
  chk(gm$rc == 0L && !("c11_status" %in% names(pm)) && !("c11_status" %in% names(rd(PANP(rM1)))),
      "MUT-1 ★승계 블록 제거(구판 병합) → 원장·운영 패널에서 표식 소실 = A2/A6 가 red 를 낸다")
}
if (is.null(MUT2)) ng("MUT-2 돌연변이 수술 실패") else {
  rM2 <- mk_root("M2", NULL, fresh_E, gate_txt = MUT2); gm2 <- gate(rM2, "2026-09-01", "--init")
  pm2 <- if (file.exists(PUBP(rM2))) rd(PUBP(rM2)) else data.table()
  chk(gm2$rc == 0L && nrow(pm2) == nrow(fresh_E), "MUT-2 ★구판 init(재생성본 통째 동결) → 꼬리·AS_OF 뒤 행까지 원장 = E1 이 red 를 낸다",
      sprintf("rc=%d n=%d", gm2$rc, nrow(pm2)))
}
if (is.null(MUT3)) ng("MUT-3 돌연변이 수술 실패") else {
  gm3 <- gate(mk_root("M3", pub_legacy, fresh_B, gate_txt = MUT3), "2026-09-01")
  chk(gm3$rc == 0L, "MUT-3 ★C11 위반 차단 제거 → 컷오프 > 결정일 행이 원장에 들어간다 = B1 이 red 를 낸다", sprintf("rc=%d", gm3$rc))
}

unlink(TD, recursive = TRUE, force = TRUE)
cat(sprintf("결과: PASS=%d FAIL=%d\n", pass, fail))
cat(sprintf('{"test":"m4_append_c11_inherit","pass":%d,"fail":%d,"total":%d,"skipped":0}\n', pass, fail, pass + fail))
if (fail > 0L) quit(status = 1L)
