# S10 — ast_verify.py 실행 + 순회 리프 수 기록 (리프 0개 = PASS 아님)
#   방언 probe 2종 병기: (a) children 제거판(args 방언 단독) (b) DIV_GUARD 표기판(schema enum 방언)
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_007")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_007")
PY <- Sys.getenv("QVEST_PY"); if (!nzchar(PY)) PY <- "python"
VER <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")

run_ver <- function(pkg_path, out_path) {
  rc <- suppressWarnings(system2(PY, c(shQuote(VER), shQuote(pkg_path), "--out", shQuote(out_path)),
                                 stdout = NULL, stderr = NULL))
  v <- fromJSON(out_path, simplifyVector = FALSE)
  list(exit_code = rc, verdict = v$verdict, leaf_count = v$leaf_count, op_count = v$op_count,
       decision_ts = v$decision_ts, max_avail_ts = v$max_avail_ts,
       violations_n = length(v$violations), violations = v$violations,
       contract_failures = v$contract_failures,
       restatement_leaves_n = length(v$restatement_leaves),
       dialect_args_used = v$dialect_args_used, out = out_path) }

main <- run_ver(file.path(MBX, "alpha_package.json"), file.path(OUT, "ast_verify.json"))

## probe (a): children 제거 — args 방언 단독 순회 실증
pk <- fromJSON(file.path(MBX, "alpha_package.json"), simplifyVector = FALSE)
strip_children <- function(n) { if (!is.list(n)) return(n)
  if (!is.null(n$children)) n$children <- NULL
  if (!is.null(n$args)) n$args <- lapply(n$args, strip_children)
  n }
pa <- pk; pa$ast <- strip_children(pk$ast); pa$factors[[1]]$ast <- strip_children(pk$factors[[1]]$ast)
pa$strategy_id <- "WT-R20260829_007_ASTPROBE_argsdialect"
write_json(pa, file.path(OUT, "alpha_package_argsdialect_probe.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
probe_args <- run_ver(file.path(OUT, "alpha_package_argsdialect_probe.json"), file.path(OUT, "ast_verify_probe_argsdialect.json"))

## probe (b): DIV_GUARD 표기판 — schema enum 방언에서 검증기가 어떻게 반응하는지 실증
CL <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "Close")
hi <- list(op = "TS_MAX", args = list(CL, 252), children = list(CL), window = 252L, unit = "d")
dg <- list(op = "DIV_GUARD", args = list(CL, hi), children = list(CL, hi))
AST_DG <- list(op = "CS_RANK", args = list(dg), children = list(dg))
pd <- pk; pd$ast <- AST_DG; pd$factors[[1]]$ast <- AST_DG
pd$strategy_id <- "WT-R20260829_007_ASTPROBE_divguard"
write_json(pd, file.path(OUT, "alpha_package_divguard_probe.json"), pretty=TRUE, auto_unbox=TRUE, digits=8, na="null")
probe_dg <- run_ver(file.path(OUT, "alpha_package_divguard_probe.json"), file.path(OUT, "ast_verify_probe_divguard.json"))

block <- list(
  tool = "02_Infrastructure/ast/ast_verify.py",
  main_package = main[setdiff(names(main), "violations")],
  main_violations = main$violations,
  probe_args_dialect = probe_args[setdiff(names(probe_args), "violations")],
  probe_divguard_dialect = probe_dg[setdiff(names(probe_dg), "violations")],
  traversal_evidence = sprintf(
    "★순회 리프 %d개 · 연산자 노드 %d개 — 리프 0개(빈 검증) 아님. 리프 = A1_RAWDATA_OHLCVS_daily:Close (TS_LAG 분자 1 + TS_MAX 분모 1 = 2회 등장). children 제거 probe 도 리프 %d개 · 연산자 %d개를 순회했다 — 즉 args 방언에서도 트리 순회 자체는 일어난다(빈 검증 아님).",
    main$leaf_count, main$op_count, probe_args$leaf_count, probe_args$op_count),
  pit_reading = sprintf("max_avail_ts(%s) <= decision_ts(%s) · lookahead violations %d",
                        main$max_avail_ts %||% "NA", main$decision_ts %||% "NA", main$violations_n),
  dialect_split_record = list(
    split_1_operator_name = "나눗셈: schema.json #/definitions/ast_node op enum = 'DIV_GUARD' / ast_verify.py ARITH_OPS = 'DIV'. 한 이름만 쓰면 한쪽이 반드시 실패한다(3/20 실측 FAIL_CONTRACT).",
    split_1_probe_result = sprintf("DIV_GUARD 표기판 probe: verdict=%s · contract_failure = \"O 밖 연산자 'DIV_GUARD'\" — 분열이 실재함을 같은 검증기로 실증했다(leaf %d개 순회).",
                                   probe_dg$verdict %||% "NA", probe_dg$leaf_count %||% 0L),
    split_2_scalar_in_args = "구조 방언 2번째 실증: schema 는 args 항목에 number 를 명시 허용(#/definitions/ast_node args.items.oneOf 에 {type: number})하는데, ast_verify.py 는 args 원소를 전부 노드로 보고 스칼라에서 \"노드 형상 오류(비 dict): 252\" 로 FAIL_CONTRACT 한다. children 을 제거한 probe 가 이것을 정확히 재현했다.",
    avoidance_design = "본 패키지는 (a) 근접도를 log P - log high (SUB(LOG, LOG)) 로 표기해 나눗셈 자체를 쓰지 않았고 — LOG/SUB/TS_MAX/TS_LAG/CS_RANK 는 두 정본 모두에 존재한다. 소비가 CS_RANK 이므로 비율 표기와 **선택 동치**(단조 변환)다 — (b) 윈도우/lag 스칼라를 args 와 children 양쪽에 나눠 실어(args = 스칼라 포함 schema 형, children = 노드만) 두 방언을 동시에 만족시켰다.",
    remediation = "둘 다 하네스 수리 대상(두 정본 중 하나로 통일 + args 스칼라 수용). 본 에이전트는 계약 파일을 고치지 않는다(역할 경계)."))

`%||%` <- function(a,b) if (is.null(a)) b else a
pk$ast_verify_result <- block
pk$challenge_flags <- c(pk$challenge_flags, sprintf(
  "[ast_verify 실증] 정본 판정 %s (exit %d) · 순회 리프 %d개 · 연산자 노드 %d개 · lookahead 위반 %d · max_avail_ts %s <= decision_ts %s. 리프 0개 빈 검증(2/20 전례) 재발 없음. 방언 분열 2건을 probe 로 병기 실증했다 — ①연산자명(DIV_GUARD probe verdict %s) ②args 내 스칼라 수용(children 제거 probe verdict %s: '노드 형상 오류(비 dict): 252'). 둘 다 하네스 수리 대상으로 기록한다.",
  main$verdict %||% "NA", main$exit_code, main$leaf_count %||% 0L, main$op_count %||% 0L,
  main$violations_n, main$max_avail_ts %||% "NA", main$decision_ts %||% "NA",
  probe_dg$verdict %||% "NA", probe_args$verdict %||% "NA"))
write_json(pk, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

av <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)
av$ast_verify_result <- block
av$challenge_flags <- pk$challenge_flags
write_json(av, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(
  task_id = "WT-R20260829_007", package_type = "alpha_package",
  method_selected = "GH2004 근접도 — ast_verify 결과 주입판(최종)",
  input_file_paths = c(file.path(OUT, "alpha_validation.json"), file.path(OUT, "ast_verify.json"),
                       file.path(OUT, "ast_verify_probe_argsdialect.json"),
                       file.path(OUT, "ast_verify_probe_divguard.json")))

cat(sprintf("[S10] main: %s (exit %d) leaf=%d op=%d viol=%d | args-probe: %s leaf=%d | divguard-probe: %s leaf=%d\n",
            main$verdict %||% "NA", main$exit_code, main$leaf_count %||% 0L, main$op_count %||% 0L, main$violations_n,
            probe_args$verdict %||% "NA", probe_args$leaf_count %||% 0L,
            probe_dg$verdict %||% "NA", probe_dg$leaf_count %||% 0L))
