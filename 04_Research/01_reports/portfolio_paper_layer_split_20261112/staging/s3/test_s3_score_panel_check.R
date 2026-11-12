## S3 검증기 후보판의 새 검사 — 양방향 시험(합성 자료 · 운영 파일 · 레인 · 등록부 무접촉 · 성과 없음)
## 후보판 파일(staging/s3/rf_replication_verify.R)을 파싱해 새 함수 4개의 최상위 대입만 격리 환경에 적재한다(스크립트 본문은 실행하지 않는다).
## 실행: Rscript test_s3_score_panel_check.R   (마지막 줄 = {"test":…,"pass":N,"fail":M})
suppressPackageStartupMessages({ library(data.table); library(jsonlite); library(arrow) })
args <- commandArgs(trailingOnly = FALSE)
here <- dirname(normalizePath(sub("^--file=", "", args[grep("^--file=", args)][1]), winslash = "/"))
cand <- file.path(here, "rf_replication_verify.R")
orig <- file.path(here, "orig", "rf_replication_verify.R")
PASS <- 0L; FAIL <- 0L
ok <- function(cond, label) { if (isTRUE(cond)) { PASS <<- PASS + 1L; cat("  ok  ", label, "\n") } else { FAIL <<- FAIL + 1L; cat("  FAIL", label, "\n") } }

## ── 적재: 이름이 맞는 최상위 대입만 ─────────────────────────────────────────
ex <- parse(file = cand, keep.source = FALSE, encoding = "UTF-8")
want <- c(".v1001_breadth_mult", ".v1001_score_panel_check", ".v1001_score_panel_req", ".v1001_score_panel_extra")
E <- new.env(parent = globalenv())
assign("%||%", function(a, b) if (is.null(a)) b else a, envir = E)
hits <- setNames(integer(length(want)), want)
for (e in as.list(ex)) if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% want) {
  nm <- as.character(e[[2]]); hits[nm] <- hits[nm] + 1L; eval(e, E) }
ok(all(hits == 1L), sprintf("후보판에 새 함수 4개가 정확히 한 번씩(%s)", paste(hits, collapse = ",")))
eo <- parse(file = orig, keep.source = FALSE, encoding = "UTF-8")
ok(!any(vapply(as.list(eo), function(e) is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) && as.character(e[[2]]) %in% want, logical(1))),
   "원본에는 새 함수가 없다(후보판을 적재했다는 증거)")
## 배선: 호출 지점 정적 확인(텍스트 — 주석 제외 줄)
src <- readLines(cand, encoding = "UTF-8"); code <- src[!grepl("^\\s*#", src)]
ok(any(grepl("^\\.impl_suspect <- isTRUE\\(\\.aud_suspect\\) \\|\\| isTRUE\\(\\.p4_suspect\\) \\|\\| \\.sp_mismatch$", code)), "구현 의심 꼬리표에 .sp_mismatch 가 OR 로 들어간다")
ok(sum(grepl("score_panel_mismatch = isTRUE\\(\\.sp_mismatch\\)", code)) == 2L, "인계 flags 두 곳(기저 미달 · 정상)에 score_panel_mismatch")
ok(sum(grepl("\\.v1001_score_panel_extra\\(\\)", code)) == 2L, "보고 extra 두 곳에 점수 패널 섹션")
ok(sum(grepl("\\.v1001_score_panel_req\\(\\)", code)) == 2L, "요청 기록 두 곳에 점수 패널 요약")
ok(which(grepl("^\\.SPC <- tryCatch\\(\\.v1001_score_panel_check", code)) < which(grepl("^\\.impl_suspect <- ", code)), "검사 호출이 꼬리표 계산보다 앞")

## ── 합성 자료 ─────────────────────────────────────────────────────────────
root <- file.path(tempdir(), "s3root"); dir.create(file.path(root, "02_Infrastructure/worktask"), recursive = TRUE, showWarnings = FALSE)
writeLines(toJSON(list(measurement_axis = list(active = "ax1", epochs = list(ax1 = list(effective_start = list(rule = "breadth_multiple", breadth_mult = 2))))),
                  auto_unbox = TRUE), file.path(root, "02_Infrastructure/worktask/constraint_defaults.json"))
AR2 <- list(measurement_axis = list(effective_start = list(breadth_mult = 2, status = "ok")))
mk <- function(panel, hold, name) {
  d <- file.path(tempdir(), "s3case", name); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  unlink(file.path(d, c("factors_panel.parquet", "04_holdings.csv", "score_panel_check_dates.csv")))
  if (!is.null(panel)) write_parquet(panel, file.path(d, "factors_panel.parquet"))
  if (!is.null(hold)) fwrite(hold, file.path(d, "04_holdings.csv"))
  d
}
tk <- sprintf("%06d", 1:80)
sig <- as.Date(c("2001-01-31", "2001-02-28", "2001-03-30"))
exe <- as.Date(c("2001-02-01", "2001-03-02", "2001-04-02"))     # 다음 거래일 체결
panel_full <- rbindlist(lapply(seq_along(sig), function(k) data.table(Date = sig[k], Ticker = tk[1:60], Score = rev(seq_len(60)) + k)))
hold_top <- function(n = 10, dates = exe, pick = function(k) tk[1:n]) rbindlist(lapply(seq_along(dates), function(k)
  data.table(run_id = "r", strategy_id = "s", date = dates[k], ticker = pick(k), target_weight = 1 / n)))
fidT <- list(score_panel = list(available = TRUE, scale = "cardinal"))
CK <- function(d, fid = fidT, ar = AR2) E$.v1001_score_panel_check(d, fid, ar, root = root)

## 1 정합 통과
r <- CK(mk(panel_full, hold_top(), "pass"))
ok(identical(r$status, "ok") && !isTRUE(r$mismatch) && r$n_violation_dates == 0L && r$n_signal_dates == 3L, "정합 통과 — 롱 보유 ⊆ 패널 · 어긋남 없음")
ok(isTRUE(all.equal(r$rank$in_top_n_share, 1)) && r$holdings_to_candidates$n_ok == 3L && !length(r$warnings), "순위 기록(상위 N 안 비율 1) · 비 ok · 경고 없음")
ok(file.exists(file.path(tempdir(), "s3case", "pass", "score_panel_check_dates.csv")), "신호일별 기록 파일")
## 1b 순위 불일치는 조건이 아니다(하위 점수 종목 보유 = 통과 · 순위만 기록)
r <- CK(mk(panel_full, hold_top(pick = function(k) tk[51:60]), "rank_low"))
ok(!isTRUE(r$mismatch) && r$rank$in_top_n_share == 0 && r$rank$max_rank_median == 60, "하위 순위 보유 — 어긋남 아님 · 순위는 기록(max 60)")
## 2 보유가 패널 밖 = 걸림
r <- CK(mk(panel_full, hold_top(pick = function(k) if (k == 2) c(tk[1:9], tk[75]) else tk[1:10]), "outside"))
ok(isTRUE(r$mismatch) && r$n_violation_dates == 1L && r$n_held_outside_panel == 1L, "패널 밖 보유 1건 — 어긋남 · 신호일 1")
ok(identical(r$violation_examples[[1]]$signal_date, "2001-02-28") && grepl(tk[75], r$violation_examples[[1]]$tickers), "어긋남 예시 = 신호일 · 종목")
ok(length(r$findings) == 1L && grepl("⊄", r$findings[1]), "발견 문장")
## 2b 패널에 있으나 점수 비유한(NA) = 후보 아님 = 걸림
pn <- copy(panel_full); pn[Date == sig[3] & Ticker == tk[1], Score := NA_real_]
r <- CK(mk(pn, hold_top(), "na_score"))
ok(isTRUE(r$mismatch) && r$n_violation_dates == 1L, "점수 NA 종목 보유 — 걸림")
## 2c 앞선 패널 날짜가 없는 체결일 = 걸림
r <- CK(mk(panel_full[Date != sig[1]], hold_top(), "unmapped"))
ok(isTRUE(r$mismatch) && r$n_unmapped_exec_dates == 1L, "첫 체결일 앞 패널 없음 — 걸림")
## 2d 숏 보유는 대상 아님(롱만)
hs <- rbind(hold_top(), data.table(run_id = "r", strategy_id = "s", date = exe[1], ticker = tk[79], target_weight = -0.1))
r <- CK(mk(panel_full, hs, "short"))
ok(!isTRUE(r$mismatch), "패널 밖 숏 보유 — 대상 아님")
## 2e 체결 지연 한 달(설계 §2-6 — 신호 1/04 · 체결 2/01)도 같은 대응
sg2 <- as.Date(c("2000-01-04", "2000-03-30")); ex2 <- as.Date(c("2000-02-01", "2000-04-03"))
p2 <- rbindlist(lapply(seq_along(sg2), function(k) data.table(Date = sg2[k], Ticker = tk[(1:40) + 10 * (k - 1)], Score = 40:1)))
r <- CK(mk(p2, hold_top(5, ex2, function(k) tk[(1:5) + 10 * (k - 1)]), "lag"))
ok(!isTRUE(r$mismatch) && r$n_signal_dates == 2L, "체결 지연이 길어도 신호일 대응 정상")
r <- CK(mk(p2, hold_top(5, ex2, function(k) if (k == 1) tk[11:15] else tk[41:45]), "lag_edge"))   # 두 신호일 패널 모두의 끝 쪽 종목
ok(!isTRUE(r$mismatch), "(대조) 각 신호일 패널 안의 종목이면 통과(1번 = 1~40 · 2번 = 11~50)")
r <- CK(mk(p2, hold_top(5, ex2, function(k) if (k == 1) tk[11:15] else tk[1:5]), "lag_wrongday"))
ok(isTRUE(r$mismatch) && identical(r$violation_examples[[1]]$signal_date, "2000-03-30"), "앞 신호일 패널에만 있는 종목을 뒤 체결일에 보유 = 걸림(날짜별 대조)")
r <- CK(mk(p2, hold_top(5, ex2, function(k) if (k == 1) tk[46:50] else tk[11:15]), "lag_bad2"))
ok(isTRUE(r$mismatch) && r$n_violation_dates == 1L, "1번 신호일 패널(1~40) 밖 46~50 보유 — 걸림")

## 3 패널 없음
r <- CK(mk(NULL, hold_top(), "np_false"), fid = list(score_panel = list(available = FALSE, reason = "구성 규칙 논문")))
ok(identical(r$status, "not_applicable") && !isTRUE(r$mismatch) && identical(r$declared_reason, "구성 규칙 논문"), "available = false · 패널 없음 = 대상 아님")
r <- CK(mk(NULL, hold_top(), "np_old"), fid = list(fidelity = "faithful"))
ok(identical(r$status, "no_declaration") && !isTRUE(r$mismatch), "신고 블록 없는 구판 · 패널 없음 = 대상 아님")
r <- CK(mk(NULL, hold_top(), "np_true"))
ok(identical(r$status, "declared_but_missing") && isTRUE(r$mismatch), "available = true 인데 패널 없음 = 어긋남")
r <- CK(mk(NULL, hold_top(), "np_null"), fid = NULL)
ok(identical(r$status, "no_declaration"), "FIDELITY 없음 = 대상 아님")

## 4 보유/후보 비 띠(배수 2 — 측정 기록의 측정 축 블록에서 읽음)
band_case <- function(breadth, n = 10, nm) {
  p <- data.table(Date = sig[1], Ticker = tk[1:breadth], Score = breadth:1)
  CK(mk(p, hold_top(n, exe[1]), nm))
}
r <- band_case(19, nm = "b19"); ok(r$holdings_to_candidates$n_below == 1L && any(grepl("below_mult", r$warnings)) && !isTRUE(r$mismatch), "폭 19 · 보유 10 = below 경고(어긋남 아님)")
r <- band_case(20, nm = "b20"); ok(r$holdings_to_candidates$n_near == 1L && any(grepl("near_mult", r$warnings)), "폭 20 · 보유 10 = 정확히 2배 = near 경고(1610.01338 형)")
r <- band_case(21, nm = "b21"); ok(r$holdings_to_candidates$n_near == 1L, "폭 21 · 보유 10 = near")
r <- band_case(22, nm = "b22"); ok(r$holdings_to_candidates$n_ok == 1L && !length(r$warnings), "폭 22 · 보유 10 = ok(보유 11 이어도 문턱 충족)")
ok(isTRUE(all.equal(r$holdings_to_candidates$ratio_median, 10 / 22)) && grepl("^authoritative_remeasure", r$holdings_to_candidates$breadth_mult_source), "비 = 10/22 · 배수 출처 = 측정 기록")
## 4b 배수 출처 — 측정 기록이 다른 배수면 그 값(새 숫자 없음 · 그 기록을 따른다)
r <- CK(mk(data.table(Date = sig[1], Ticker = tk[1:25], Score = 25:1), hold_top(10, exe[1]), "m3"),
        ar = list(measurement_axis = list(effective_start = list(breadth_mult = 3))))
ok(r$holdings_to_candidates$breadth_mult == 3 && r$holdings_to_candidates$n_below == 1L, "배수 3 기록 — 폭 25 < 30 = below")
r <- CK(mk(data.table(Date = sig[1], Ticker = tk[1:19], Score = 19:1), hold_top(10, exe[1]), "noarule"),
        ar = list(measurement_axis = list(universe = "K200_KQ150")))
ok(is.na(r$holdings_to_candidates$breadth_mult) && r$holdings_to_candidates$n_below == 0L && any(grepl("breadth_mult_unavailable\\(axis_has_no", r$warnings)), "측정 축에 규칙 없음 = 띠 없음(다른 축 배수 안 빌림)")
r <- CK(mk(data.table(Date = sig[1], Ticker = tk[1:19], Score = 19:1), hold_top(10, exe[1]), "noar"), ar = NULL)
ok(r$holdings_to_candidates$breadth_mult == 2 && grepl("^constraint_defaults", r$holdings_to_candidates$breadth_mult_source), "측정 기록 없음 = 활성 epoch 배수")

## 5 날짜 집합 어긋남 경고(패널이 더 촘촘)
pd <- rbind(panel_full, data.table(Date = as.Date("2001-02-15"), Ticker = tk[1:60], Score = 60:1))
r <- CK(mk(pd, hold_top(), "dense"))
ok(any(grepl("panel_dates_denser", r$warnings)), "패널 날짜가 보유 신호일보다 촘촘 = 경고")

## 6 요약 · 보고
assign(".SPC", CK(mk(panel_full, hold_top(pick = function(k) if (k == 2) c(tk[1:9], tk[75]) else tk[1:10]), "outside")), envir = E)
q <- E$.v1001_score_panel_req(); x <- E$.v1001_score_panel_extra()
ok(isTRUE(q$mismatch) && q$n_violation_dates == 1L && identical(q$file, "score_panel_check.json"), "요청 요약")
ok(length(x) == 1L && grepl("어긋남", x[[1]]$heading), "보고 섹션 — 어긋남이면 낸다")
assign(".SPC", CK(mk(panel_full, hold_top(), "pass")), envir = E)
ok(is.null(E$.v1001_score_panel_extra()), "보고 섹션 — 정상 · 경고 없음이면 내지 않는다")
ok(is.null(E$.v1001_score_panel_req(NULL)), "검사 결과 없음 = 요청 필드 없음(구판과 같음)")
## 7 JSON 직렬화(검증기 기록 경로와 같은 인자)
js <- tryCatch(toJSON(CK(mk(panel_full, hold_top(), "pass")), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 6), error = function(e) NULL)
ok(!is.null(js) && identical(fromJSON(js)$status, "ok"), "검사 결과가 검증기 toJSON 인자로 직렬화된다")

cat(sprintf('{"test":"s3_score_panel_check","pass":%d,"fail":%d}\n', PASS, FAIL))
