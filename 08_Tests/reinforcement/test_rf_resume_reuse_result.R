#!/usr/bin/env Rscript
# test_rf_resume_reuse_result.R — 재개 job 은 신뢰할 수 있는 워커 결과를 다시 재지 않는다 (2026-09-07)
#   실사고 2026-09-05 23:14: B2 워커 5개 스폰 직후 절전으로 부모 러너만 죽었는데(SCHED_S_TASK_TERMINATED) 워커 4개는
#   result_B2_{6,8,9,10}.json 을 정상 완료했다. 다음 tick 의 재개 경로가 그 파일을 unlink 하고 5칸을 전부 재실행했다
#   (8분 낭비 + 같은 칸의 중복 산출물·L-code).
#   양방향: 신선한 ok 결과는 재사용 / 오래된·다른 spec·ok=false·artifacts 부재·essence 부재는 전부 재실행 판정.
#   ★러너 파일은 source 하지 않는다(원장에 닿는다) — 판정은 rf_spec_sig.R 의 순수 함수, 러너 호출은 문자열 재도출(주석 제외).
#   ★픽스처는 tempdir 합성 — 운영 .cache/rf_parallel 은 읽지도 쓰지도 않는다.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
suppressMessages(library(jsonlite))
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot")
PASS <- 0L; FAIL <- 0L
ok <- function(m) { PASS <<- PASS + 1L; cat("  OK  ", m, "\n") }
ng <- function(m, why = "") { FAIL <<- FAIL + 1L; cat("  FAIL", m, if (nzchar(why)) paste0(" — ", why) else "", "\n") }
invisible(capture.output(suppressMessages(source(file.path(ROOT, "02_Infrastructure/reinforcement/rf_spec_sig.R"), local = globalenv()))))
if (!exists("rf_result_reusable")) {
  cat("  FAIL rf_result_reusable 부재 — 정본 rf_spec_sig.R 에 없다\n")
  cat('{"test":"rf_resume_reuse_result","pass":0,"fail":1,"total":1}\n'); quit(status = 1L)
}

W <- file.path(tempdir(), sprintf("rf_reuse_%d", Sys.getpid()))
dir.create(W, recursive = TRUE, showWarnings = FALSE)
T0 <- Sys.time() - 600                                   # spec 기준 시각(결과는 이보다 60초 뒤가 '신선')
## 픽스처 빌더 — 실사고 형태(result_B2_6.json: ok=true · essence · artifacts · spec 절대경로)를 tempdir 에 합성
mk <- function(tag, code = "B2_6", n = 15L, ok = TRUE, essence = TRUE, artifacts = TRUE, ar_json = TRUE,
               spec_alt = NULL, result_dt = 60, n_in_result = NULL) {
  d <- file.path(W, tag); dir.create(d, recursive = TRUE, showWarnings = FALSE)
  sp <- file.path(d, sprintf("spec_%s__RP_TEST_%s.json", code, tag))
  write(toJSON(list(code = code, label = "t", block = "B2"), auto_unbox = TRUE), sp)
  Sys.setFileTime(sp, T0)
  ar <- file.path(d, "artifacts")
  if (artifacts) { dir.create(ar, showWarnings = FALSE)
    if (ar_json) write('{"essence_grade":"C"}', file.path(ar, "authoritative_remeasure.json")) }
  out <- file.path(d, sprintf("result_%s.json", code))
  R <- list(n = n_in_result %||% n, code = code, block = "B2", ok = ok, grade = "C", artifacts = ar,
            spec = if (is.null(spec_alt)) sp else spec_alt(sp))
  if (essence) R$essence <- list(cell_code = code, port_t = 0.582, calmar = 0.2, spec = sp)
  write(toJSON(R, auto_unbox = TRUE, null = "null"), out)
  Sys.setFileTime(out, T0 + result_dt)
  list(n = n, code = code, spec = sp, out = out, name = "RF_PAR_TEST", resume = TRUE)
}
show <- function(r) paste0("reuse=", r$reuse, " why=", r$why)

cat("=== 양성 대조 — 신선한 ok 결과 ===\n")
j1 <- mk("fresh"); r1 <- rf_result_reusable(j1, ROOT)
if (isTRUE(r1$reuse) && dir.exists(r1$artifacts %||% "")) ok("P1 ok·같은 spec·spec 보다 새것·artifacts 실재 → 재사용 (실사고 B2_6 형태)") else
  ng("P1 신선한 결과를 버린다 — 실사고 재현(5칸 재실행)", show(r1))
alt_sep <- function(p) if (identical(.Platform$OS.type, "windows")) chartr("/", "\\", p) else sub("^/", "//", p)
j2 <- mk("sep", spec_alt = alt_sep); r2 <- rf_result_reusable(j2, ROOT)
if (isTRUE(r2$reuse)) ok("P2 구분자만 다른 같은 spec 경로 → 재사용(정규화)") else ng("P2 구분자 차이를 다른 spec 으로 읽는다", show(r2))
j3 <- mk("case_ws"); j3$spec <- paste0(j3$spec, "")                # 동일 경로 그대로(회귀 기준)
r3 <- rf_result_reusable(j3, NULL)
if (isTRUE(r3$reuse)) ok("P3 root=NULL 이어도 절대경로 결과는 재사용") else ng("P3 root 없이 판정 실패", show(r3))

cat("=== 위반 주입 — 전부 재실행 판정 ===\n")
v1 <- rf_result_reusable(mk("older", result_dt = -60), ROOT)
if (!isTRUE(v1$reuse) && identical(v1$why, "result_older_than_spec")) ok("V1 결과가 spec 보다 오래됨 → 재실행") else ng("V1 낡은 결과를 재사용", show(v1))
other <- mk("other_spec")                                 # 존재하는 다른 spec 파일
v2 <- rf_result_reusable(mk("mismatch", spec_alt = function(p) other$spec), ROOT)
if (!isTRUE(v2$reuse) && identical(v2$why, "spec_path_mismatch")) ok("V2 result$spec ≠ job$spec → 재실행") else ng("V2 다른 spec 의 결과를 재사용", show(v2))
v3 <- rf_result_reusable(mk("notok", ok = FALSE), ROOT)
if (!isTRUE(v3$reuse) && identical(v3$why, "result_not_ok")) ok("V3 ok=false → 재실행") else ng("V3 실패 결과를 재사용", show(v3))
v4 <- rf_result_reusable(mk("noart", artifacts = FALSE), ROOT)
if (!isTRUE(v4$reuse) && identical(v4$why, "artifacts_dir_absent")) ok("V4a artifacts 디렉터리 부재 → 재실행") else ng("V4a artifacts 없는 결과를 재사용", show(v4))
v5 <- rf_result_reusable(mk("noarjson", ar_json = FALSE), ROOT)
if (!isTRUE(v5$reuse) && identical(v5$why, "authoritative_remeasure_absent")) ok("V4b authoritative_remeasure.json 부재 → 재실행") else ng("V4b 권위 파일 없는 결과를 재사용", show(v5))
v6 <- rf_result_reusable(mk("noess", essence = FALSE), ROOT)
if (!isTRUE(v6$reuse) && identical(v6$why, "essence_missing")) ok("V5 essence$port_t 부재 → 재실행(무비용 재사용 루프 방지)") else ng("V5 essence 없는 결과를 재사용", show(v6))
j7 <- mk("absent"); unlink(j7$out, force = TRUE); v7 <- rf_result_reusable(j7, ROOT)
if (!isTRUE(v7$reuse) && identical(v7$why, "result_absent")) ok("V6 결과 파일 부재(보통의 재개) → 재실행") else ng("V6 부재를 재사용으로", show(v7))
v8 <- rf_result_reusable(mk("othern", n_in_result = 99L), ROOT)
if (!isTRUE(v8$reuse) && identical(v8$why, "n_mismatch")) ok("V7 result$n ≠ job$n(남의 칸) → 재실행") else ng("V7 다른 n 의 결과를 재사용", show(v8))
j9 <- mk("garbage"); writeLines("{not json", j9$out); Sys.setFileTime(j9$out, T0 + 60); v9 <- rf_result_reusable(j9, ROOT)
if (!isTRUE(v9$reuse) && identical(v9$why, "result_unparseable")) ok("V8 JSON 파싱 실패 → 재실행") else ng("V8 깨진 결과를 재사용", show(v9))
v10 <- rf_result_reusable(list(n = 15L, code = "B2_6", spec = j1$spec, out = j1$out, resume = TRUE), ROOT)
if (isTRUE(v10$reuse)) ok("P4 같은 job 을 다시 물어도 판정 불변(부작용 없음)") else ng("P4 판정이 호출마다 흔들린다", show(v10))

cat("=== 러너 배선 — 문자열 재도출(주석 제외) ===\n")
src <- readLines(file.path(ROOT, "02_Infrastructure/ops/reinforce_auto_parallel.R"), encoding = "UTF-8", warn = FALSE)
src <- sub("#.*$", "", src)   # 주석 제외 — 설명 주석이 함수명을 인용해도 코드가 아니다
if (any(grepl("rf_result_reusable(", src, fixed = TRUE))) ok("W1 러너가 rf_result_reusable( 을 실제로 부른다") else ng("W1 러너 호출 없음 — 판정 함수가 소비되지 않는다")
if (any(grepl('"resume_reuse_result"', src, fixed = TRUE))) ok("W2 재사용 이벤트(resume_reuse_result)를 저널에 남긴다") else ng("W2 재사용 이벤트 없음")
if (any(grepl("unlink(j$out, force = TRUE)", src, fixed = TRUE))) ok("W3 재실행 경로(unlink 후 스폰)는 남아 있다") else ng("W3 unlink 경로 소실 — 낡은 결과가 안 지워진다")
unlink(W, recursive = TRUE, force = TRUE)
cat(sprintf("\n합계: 통과 %d · 실패 %d\n", PASS, FAIL))
cat(sprintf('{"test":"rf_resume_reuse_result","pass":%d,"fail":%d,"total":%d}\n', PASS, FAIL, PASS + FAIL))
quit(status = if (FAIL == 0L) 0L else 1L)
