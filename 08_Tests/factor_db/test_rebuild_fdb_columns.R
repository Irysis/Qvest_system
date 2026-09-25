#!/usr/bin/env Rscript
#==============================================================================
# test_rebuild_fdb_columns.R — 월간 factor DB 열 단위 재빌드 도구 (PIT C11 2단계 · 2026-09-25)
#   대상: 02_Infrastructure/factor_db/rebuild_fdb_columns.R (+ 사양 column_rebuild_c11_phase2.json)
#
# 왜: C11 2단계는 D32·RE13·RE14·MA07 열만 재계산하고 MA01·MA02 열을 지운다(구판 월 파일 백업).
#   열 단위 재쓰기가 틀리면 **에러 없이** 다른 팩터 행을 건드리거나(전 소비자 오염), 퇴역 열을 남기거나,
#   재실행이 '구판' 백업을 덮어 롤백이 불가능해진다. 그래서 불변식(I0~I6)과 파일 IO(백업 1회·원자 교체·
#   매니페스트·재개·외부 변경 거부·롤백)를 합성 픽스처로 양방향 검사한다 — 운영 파일 무접촉.
#
# 설계:
#   P1~P7 양성(정상 경로) · N1~N8 위반 주입(불변식이 잡는가) · S1~S2 실물 사양·registry 대조(읽기 전용)
#   돌연변이는 대상 파일을 바꿔 끼워(QVEST_RFC_SRC) 외부에서 돌린다 — 런북 검증 기록 참조.
# 실행: cd <ROOT> && Rscript 08_Tests/factor_db/test_rebuild_fdb_columns.R
#==============================================================================
suppressMessages({ library(data.table); library(arrow); library(jsonlite) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
SRC  <- Sys.getenv("QVEST_RFC_SRC", file.path(ROOT, "02_Infrastructure/factor_db/rebuild_fdb_columns.R"))
SPEC <- Sys.getenv("QVEST_RFC_SPEC", file.path(ROOT, "02_Infrastructure/factor_db/column_rebuild_c11_phase2.json"))

.pass <- 0L; .fail <- 0L
ok <- function(m) { .pass <<- .pass + 1L; cat(sprintf("  [OK] %s\n", m)) }
ng <- function(m, d = "") { .fail <<- .fail + 1L; cat(sprintf("  [NG] %s%s\n", m, if (nzchar(d)) paste0(" — ", d) else "")) }
chk <- function(cond, m, d = "") if (isTRUE(cond)) ok(m) else ng(m, d)
cat(sprintf("== 열 단위 재빌드 도구 (%s) ==\n", SRC))

Sys.setenv(RFC_LIB_ONLY = "1")
E <- new.env(parent = globalenv())
lr <- tryCatch({ sys.source(SRC, envir = E, keep.source = FALSE); TRUE }, error = function(e) { ng("대상 적재 실패", conditionMessage(e)); FALSE })
need <- c("rfc_read_spec", "rfc_check_spec_registry", "rfc_plan", "rfc_new_month_dt", "rfc_verify_month",
          "rfc_process_month", "rfc_rollback", "rfc_manifest_last", "rfc_month_files")
if (lr) { miss <- need[!vapply(need, exists, logical(1), envir = E, inherits = FALSE)]
  if (length(miss)) { ng("함수 부재", paste(miss, collapse = ",")); lr <- FALSE } }
if (!lr) { cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail)); quit(status = 1L) }
for (nm in need) assign(nm, get(nm, envir = E))

# ── 합성 픽스처 ─────────────────────────────────────────────────────────────
set.seed(20260925)
TK <- sprintf("T%02d", 1:30)
mk_rows <- function(fac, d, base) data.table(Date = d, Ticker = TK, Factor_Name = fac, Raw_Value = base + seq_along(TK) / 7,
                                             Z_Score = as.numeric(scale(seq_along(TK))), Z_Sector = rnorm(30), Rank_Pct = (seq_along(TK) - 1) / 29,
                                             Coverage = TRUE)
D0 <- as.Date("2020-03-31")
OLD <- rbindlist(list(mk_rows("KEEP1", D0, 1), mk_rows("KEEP2", D0, 2), mk_rows("TGT_A", D0, 3),
                      mk_rows("TGT_B", D0, 4), mk_rows("DROP_X", D0, 5)))
OLD[Factor_Name == "KEEP2" & Ticker == "T03", Raw_Value := NA_real_]   # NA 가 있어도 불변 대조가 성립해야 한다
FRESH <- rbindlist(list(mk_rows("TGT_A", D0, 30), mk_rows("TGT_B", D0, 40)[1:25], mk_rows("KEEP1", D0, 99)))[, Date := NULL]
TG <- c("TGT_A", "TGT_B"); DR <- "DROP_X"; ACT <- c("KEEP1", "KEEP2", "TGT_A", "TGT_B")
SPEC_FX <- list(name = "fx", targets = TG, modules = c(TGT_A = "m", TGT_B = "m"), drops = DR,
                from = "202001", to = "202012", drop_scope = "all_months")

# P1 순수 경로
NEW <- rfc_new_month_dt(OLD, FRESH, TG, DR)
v <- rfc_verify_month(OLD, NEW, TG, DR, fresh_std = FRESH, active_ids = ACT)
chk(v$ok, "P1 [양성] 새 월 테이블 불변식 I0~I6 통과", paste(v$fail, collapse = "|"))
chk(isTRUE(fsetequal(NEW[Factor_Name == "KEEP1"], OLD[Factor_Name == "KEEP1"])),
    "P1b 재계산 산출에 섞인 비대상(KEEP1 99.x)은 쓰지 않는다 — 대상만 교체")
chk(NEW[Factor_Name == "TGT_B", .N] == 25L && NEW[Factor_Name == "TGT_A", all(Raw_Value > 29)],
    "P1c 대상 행 = 재계산 결과(TGT_B 25행 · TGT_A 새 값)")
chk(!any(NEW$Factor_Name == DR) && identical(names(NEW), names(OLD)), "P1d drop 열 제거 · 열 순서 보존")

# ── 위반 주입 (불변식이 잡는가) ──
bad1 <- copy(NEW); bad1[Factor_Name == "KEEP2" & Ticker == "T05", Raw_Value := Raw_Value + 1e-9]
chk(any(grepl("^I1", rfc_verify_month(OLD, bad1, TG, DR, FRESH, ACT)$fail)), "N1 [주입] 비대상 1셀 1e-9 변경 → I1")
bad2 <- rbindlist(list(NEW, OLD[Factor_Name == DR][1]))
chk(any(grepl("^I2", rfc_verify_month(OLD, bad2, TG, DR, FRESH, ACT)$fail)), "N2 [주입] drop 1행 잔존 → I2")
bad3 <- rbindlist(list(NEW, NEW[Factor_Name == "TGT_A"][1]))
chk(any(grepl("^I3", rfc_verify_month(OLD, bad3, TG, DR, FRESH, ACT)$fail)), "N3 [주입] 대상 중복 1행 → I3")
bad4 <- NEW[!(Factor_Name == "TGT_A" & Ticker == "T01")]
chk(any(grepl("^I5", rfc_verify_month(OLD, bad4, TG, DR, FRESH, ACT)$fail)), "N4 [주입] 대상 1행 유실(부분 기록) → I5")
bad5 <- copy(NEW); bad5[Ticker == "T02", Date := D0 + 1]
chk(any(grepl("^I4", rfc_verify_month(OLD, bad5, TG, DR, FRESH, ACT)$fail)), "N5 [주입] Date 2값 → I4")
bad6 <- NEW[Factor_Name != "KEEP2"]
f6 <- rfc_verify_month(OLD, bad6, TG, DR, FRESH, ACT)$fail
chk(any(grepl("^I6", f6)) && any(grepl("^I1", f6)), "N6 [주입] 비대상 활성 팩터 통째 소실 → I1·I6")
bad7 <- copy(NEW); bad7[, Coverage := as.integer(Coverage)]
chk(any(grepl("^I0", rfc_verify_month(OLD, bad7, TG, DR, FRESH, ACT)$fail)), "N7 [주입] 열 타입 변경 → I0")
lost_ok <- rfc_verify_month(OLD, rfc_new_month_dt(OLD, FRESH[Factor_Name != "TGT_B"], TG, DR), TG, DR,
                            FRESH[Factor_Name != "TGT_B"], ACT)
chk(lost_ok$ok && identical(lost_ok$stats$target_lost, "TGT_B"),
    "N8 대상이 PIT 로 산출 불가(0행) → 오염값 제거는 허용·target_lost 로 기록(비대상 소실과 구분)")

# ── 사양 검증 ──
tmpd <- file.path(tempdir(), paste0("rfc_", paste(sample(letters, 8), collapse = "")))
dir.create(tmpd, recursive = TRUE)
wspec <- function(x) { p <- file.path(tmpd, paste0("s", sample(1e6, 1), ".json")); writeLines(toJSON(x, auto_unbox = TRUE), p); p }
base_spec <- list(schema = "fdb_column_rebuild/v1", name = "t", recompute = list(list(id = "A", module = "m")),
                  drop = list(list(id = "Z")), range = list(from = "200501", to = "202608"), drop_scope = "all_months")
chk(!inherits(try(rfc_read_spec(wspec(base_spec)), silent = TRUE), "try-error"), "P2 사양 형식 정상 판독")
s_ov <- base_spec; s_ov$drop <- list(list(id = "A"))
chk(inherits(try(rfc_read_spec(wspec(s_ov)), silent = TRUE), "try-error"), "N9 [주입] recompute·drop 겹침 → 거부")
s_rg <- base_spec; s_rg$range$from <- "202609"
chk(inherits(try(rfc_read_spec(wspec(s_rg)), silent = TRUE), "try-error"), "N10 [주입] from > to → 거부")
s_sc <- base_spec; s_sc$schema <- "v0"
chk(inherits(try(rfc_read_spec(wspec(s_sc)), silent = TRUE), "try-error"), "N11 [주입] schema 불일치 → 거부")
REGX <- list(A = list(lifecycle = list(status = "active")), R = list(lifecycle = list(status = "retired")),
             Z = list(lifecycle = list(status = "retired")), K = list(category = "x"))
sp_ok <- rfc_read_spec(wspec(base_spec))
chk(!length(rfc_check_spec_registry(sp_ok, REGX, "m")), "P3 registry 대조 정상(A active 재계산 · Z retired 제거)")
s_r <- base_spec; s_r$recompute <- list(list(id = "R", module = "m"))
chk(length(rfc_check_spec_registry(rfc_read_spec(wspec(s_r)), REGX, "m")) > 0L, "N12 [주입] 퇴역 팩터 재계산(부활) → 거부")
s_d <- base_spec; s_d$drop <- list(list(id = "K"))
chk(length(rfc_check_spec_registry(rfc_read_spec(wspec(s_d)), REGX, "m")) > 0L, "N13 [주입] 활성 팩터(status 미기재) 제거 → 거부")
chk(length(rfc_check_spec_registry(sp_ok, REGX, "other")) > 0L, "N14 [주입] 미적재 모듈 → 거부")

# ── 계획 ──
MF <- data.table(ym = c("200412", "200501", "202608", "202609"), path = "x")
pl <- rfc_plan(MF, SPEC_FX, from = "200501", to = "202608")
chk(identical(pl$mode, c("drop_only", "recompute", "recompute", "drop_only")),
    "P4 계획 = 구간 안 recompute · 구간 밖 drop_only(drop_scope all_months)", paste(pl$mode, collapse = ","))
pl2 <- rfc_plan(MF, modifyList(SPEC_FX, list(drop_scope = "range")), from = "200501", to = "202608")
chk(identical(pl2$mode, c("skip", "recompute", "recompute", "skip")), "P4b drop_scope range → 구간 밖 skip")

# ── 파일 IO: 처리 · 백업 1회 · 재개 · 외부 변경 거부 · 롤백 ──
fdir <- file.path(tmpd, "fdb"); bk <- file.path(tmpd, "bk"); dir.create(fdir)
fp <- file.path(fdir, "factor_db_202003.parquet"); write_parquet(OLD, fp); md5_orig <- unname(tools::md5sum(fp))
fp2 <- file.path(fdir, "factor_db_200412.parquet"); write_parquet(copy(OLD)[, Date := as.Date("2004-12-31")], fp2)
md5_orig2 <- unname(tools::md5sum(fp2))
cf <- function(sig_d) list(std = FRESH, drift = list(n_drifted = 0L))
r1 <- rfc_process_month("202003", fp, "recompute", SPEC_FX, bk, compute_fn = cf, active_ids = ACT)
cur <- as.data.table(read_parquet(fp, mmap = FALSE))
chk(identical(r1$status, "done") && isTRUE(fsetequal(cur, NEW)) && identical(r1$md5_after, unname(tools::md5sum(fp))),
    "P5 [양성] 처리 → 파일 = 새 테이블 · md5_after 기록 일치", r1$status)
chk(file.exists(file.path(bk, basename(fp))) && identical(unname(tools::md5sum(file.path(bk, basename(fp)))), md5_orig),
    "P5b 구판 백업 = 원본 md5")
chk(!length(list.files(fdir, pattern = "tmp_rfc")), "P5c tmp 잔재 0(원자 교체 후 정리)")
E$rfc_manifest_append(bk, r1)
r2 <- rfc_process_month("202003", fp, "recompute", SPEC_FX, bk, compute_fn = cf, active_ids = ACT,
                        prev = rfc_manifest_last(bk)[["202003"]])
chk(identical(r2$status, "already_done"), "P6 재개 — 기록된 재빌드 후 md5 와 같으면 건너뜀", r2$status)
# 재실행이 백업을 덮지 않는가: 파일을 다른 내용으로 바꾼 뒤 force 재처리
write_parquet(OLD[Factor_Name != "KEEP2"], fp)
r3 <- tryCatch(rfc_process_month("202003", fp, "recompute", SPEC_FX, bk, compute_fn = cf, active_ids = ACT,
                                 prev = rfc_manifest_last(bk)[["202003"]]), error = function(e) conditionMessage(e))
chk(is.character(r3) && grepl("외부 변경", r3), "N15 [주입] 재빌드 뒤 파일이 외부에서 바뀜 → --force 없이 거부")
r4 <- rfc_process_month("202003", fp, "recompute", SPEC_FX, bk, compute_fn = cf, active_ids = ACT,
                        prev = rfc_manifest_last(bk)[["202003"]], force = TRUE)
chk(identical(unname(tools::md5sum(file.path(bk, basename(fp)))), md5_orig), "P7 force 재처리도 '구판' 백업을 덮지 않는다")
E$rfc_manifest_append(bk, r4)
# 불변식 위반이면 파일·백업 무접촉
fp3 <- file.path(fdir, "factor_db_202004.parquet"); write_parquet(OLD, fp3); m3 <- unname(tools::md5sum(fp3))
cf_bad <- function(sig_d) list(std = rbindlist(list(FRESH, FRESH[1])), drift = NULL)
r5 <- rfc_process_month("202004", fp3, "recompute", SPEC_FX, bk, compute_fn = cf_bad, active_ids = ACT)
chk(identical(r5$status, "invariant_fail") && identical(unname(tools::md5sum(fp3)), m3) &&
      !file.exists(file.path(bk, basename(fp3))), "N16 [주입] 재계산 결과 중복 → invariant_fail · 파일·백업 무접촉", r5$status)
# drop_only
r6 <- rfc_process_month("200412", fp2, "drop_only", SPEC_FX, bk, compute_fn = function(d) stop("호출되면 안 됨"), active_ids = ACT)
cur2 <- as.data.table(read_parquet(fp2, mmap = FALSE))
chk(identical(r6$status, "done") && !any(cur2$Factor_Name == DR) && cur2[Factor_Name == "TGT_A", .N] == 30L,
    "P8 drop_only — 재계산 없이 drop 열만 제거(대상 열 원값 유지)", r6$status)
E$rfc_manifest_append(bk, r6)
r7 <- rfc_process_month("200412", fp2, "drop_only", SPEC_FX, bk, compute_fn = NULL, active_ids = ACT)
chk(identical(r7$status, "noop"), "P8b drop 열이 없는 달 = noop(쓰기 0)", r7$status)
# 롤백
rb <- rfc_rollback(bk, fdir)
chk(rb$restored == 2L && identical(unname(tools::md5sum(fp)), md5_orig) && identical(unname(tools::md5sum(fp2)), md5_orig2),
    "P9 롤백 — 백업 월 파일 원자 복원(md5 = 원본)", sprintf("restored=%d", rb$restored))

# ── 실물 사양 · registry (읽기 전용) ──
if (file.exists(SPEC)) {
  sp <- tryCatch(rfc_read_spec(SPEC), error = function(e) e)
  chk(!inherits(sp, "error"), "S1 실물 사양 판독", if (inherits(sp, "error")) conditionMessage(sp) else "")
  rp <- file.path(ROOT, ".cache/factor_db/factor_registry.json")
  if (!inherits(sp, "error") && file.exists(rp)) {
    bad <- rfc_check_spec_registry(sp, fromJSON(rp, simplifyVector = FALSE), NULL)
    chk(!length(bad) && all(c("MA01_GDP_Sensitivity", "MA02_CPI_Sensitivity") %in% sp$drops) &&
          all(c("D32_Beta_VIX", "RE13_Credit_Spread_Pctile", "RE14_Inflation_YoY", "MA07_BusinessCycle_Composite") %in% sp$targets),
        "S2 실물 사양 ↔ registry — 재계산 4종 active · 제거 2종 비활성", paste(bad, collapse = "|"))
  }
} else ng("S1 실물 사양 부재", SPEC)

unlink(tmpd, recursive = TRUE)
cat(sprintf("\n== 결과: %d PASS / %d FAIL ==\n", .pass, .fail))
# 요약 JSON(run_all_hooks.sh 계약 — 없으면 UNMEASURED · 2026-09-25 C11 S9 에서 미측정으로 드러남)
cat(sprintf('{"test":"test_rebuild_fdb_columns","pass":%d,"fail":%d,"skipped":0,"total":%d,"skips":[]}\n', .pass, .fail, .pass + .fail))
if (.fail > 0L) quit(status = 1L)
