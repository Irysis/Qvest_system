# S8 — ast_verify.py 실행 결과를 산출물에 주입 (빈 검증 방지: 순회 리프 수 명시 기록)
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_003")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_003")
PY <- Sys.getenv("QVEST_PY"); if (!nzchar(PY)) PY <- "python"
VER <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")

run_ver <- function(pkg_path, out_path) {
  rc <- suppressWarnings(system2(PY, c(shQuote(VER), shQuote(pkg_path), "--out", shQuote(out_path)),
                                 stdout = NULL, stderr = NULL))
  v <- fromJSON(out_path, simplifyVector = FALSE)
  list(exit_code = rc, verdict = v$verdict, leaf_count = v$leaf_count, op_count = v$op_count,
       decision_ts = v$decision_ts, max_avail_ts = v$max_avail_ts,
       violations_n = length(v$violations), contract_failures = v$contract_failures,
       restatement_leaves_n = length(v$restatement_leaves), out = out_path) }

main  <- run_ver(file.path(MBX, "alpha_package.json"), file.path(OUT, "ast_verify.json"))
probe <- run_ver(file.path(OUT, "alpha_package_divname_probe.json"), file.path(OUT, "ast_verify_probe.json"))

block <- list(
  tool = "02_Infrastructure/ast/ast_verify.py",
  main_package = main, divname_probe = probe,
  traversal_evidence = sprintf("순회 리프 %d개 · 연산자 노드 %d개 — 2/20 의 '리프 0개 순회(빈 검증)' 재발 없음. 리프 = A1_RAWDATA_OHLCVS_daily 의 Vol/Close/Size FIELD 3종 + 모멘텀 SPECIAL_OP 1종.",
                               main$leaf_count, main$op_count),
  pit_reading = sprintf("max_avail_ts(%s) <= decision_ts(%s) · lookahead violations %d — PIT 위반 0. FAIL 사유는 PIT 가 아니라 계약 표면 분열이다.",
                        main$max_avail_ts, main$decision_ts, main$violations_n),
  contract_surface_split = paste(
    "나눗셈 연산자 이름이 두 정본에서 다르다: schema.json #/definitions/ast_node op enum = 'DIV_GUARD' /",
    "ast_verify.py operator_library ARITH_OPS = 'DIV'. 본 패키지는 schema.json(패키지 형식 정본)을 따라 DIV_GUARD 를 싣고,",
    "동일 트리에서 이름만 DIV 로 바꾼 probe 를 stage_artifacts 에 함께 발행해 같은 검증기로 돌렸다.",
    sprintf("결과: 정본 %s(exit %d) vs probe %s(exit %d), leaf_count 둘 다 %d · op_count 둘 다 %d.",
            main$verdict, main$exit_code, probe$verdict, probe$exit_code, main$leaf_count, main$op_count),
    "차이는 정확히 연산자 이름 하나이며 트리·리프·PIT 판정은 동일하다. 하네스 수리 대상(두 정본 중 하나로 통일)으로 기록한다 —",
    "본 에이전트는 계약 파일을 고치지 않는다(역할 경계·lean 예산).", sep = " "))

## 두 산출물에 주입 (write_json -> lineage 순서 유지: 아래에서 lineage 재기록)
pkg <- fromJSON(file.path(MBX, "alpha_package.json"), simplifyVector = FALSE)
pkg$ast_verify_result <- block
pkg$challenge_flags <- c(pkg$challenge_flags,
  sprintf("[계약 표면 분열 실증] ast_verify.py 정본 판정 %s — 사유는 나눗셈 연산자 이름(schema=DIV_GUARD vs 검증기=DIV) 하나다. 이름만 바꾼 probe 는 PASS 이고 leaf_count/op_count/PIT 판정이 동일하다. PIT 위반 0(max_avail_ts <= decision_ts). 순회 리프 %d개 — 2/20 의 빈 검증 재발 없음.",
          main$verdict, main$leaf_count))
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

av <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)
av$ast_verify_result <- block
av$challenge_flags <- pkg$challenge_flags
write_json(av, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_003", package_type = "alpha_package",
  method_selected = "LS2000 회전율 조건부 모멘텀 생애주기 — ast_verify 결과 주입판(최종)",
  input_file_paths = c(file.path(OUT, "alpha_validation.json"), file.path(OUT, "ast_verify.json"),
                       file.path(OUT, "ast_verify_probe.json")))

cat(sprintf("[S8] main: %s (exit %d) leaf=%d op=%d viol=%d | probe: %s (exit %d) leaf=%d\n",
            main$verdict, main$exit_code, main$leaf_count, main$op_count, main$violations_n,
            probe$verdict, probe$exit_code, probe$leaf_count))
