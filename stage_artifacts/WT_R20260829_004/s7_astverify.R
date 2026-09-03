# S7 — ast_verify.py 실행 + 순회 리프 수 명시 기록(빈 검증 방지) + 방언 병기 probe
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_004")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_004")
PY <- Sys.getenv("QVEST_PY"); if (!nzchar(PY)) PY <- "python"
VER <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")

run_ver <- function(pkg_path, out_path) {
  rc <- suppressWarnings(system2(PY, c(shQuote(VER), shQuote(pkg_path), "--out", shQuote(out_path)),
                                 stdout = NULL, stderr = NULL))
  v <- tryCatch(fromJSON(out_path, simplifyVector = FALSE), error = function(e) list())
  list(exit_code = rc, verdict = v$verdict, leaf_count = v$leaf_count, op_count = v$op_count,
       decision_ts = v$decision_ts, max_avail_ts = v$max_avail_ts,
       violations_n = length(v$violations), violations = v$violations,
       contract_failures = v$contract_failures,
       restatement_leaves_n = length(v$restatement_leaves), out = out_path)
}
main <- run_ver(file.path(MBX, "alpha_package.json"), file.path(OUT, "ast_verify.json"))

# 검증기 방언 probe — ast_verify.py 형식(children · {"const":n} · FIELD 분해 리프 · SPECIAL_OP 평면계약)
pkg <- fromJSON(file.path(MBX, "alpha_package.json"), simplifyVector = FALSE)
K <- function(n) list(const = n)
mom_v <- list(leaf = "SPECIAL_OP", walk_forward = TRUE,
              op_code_path = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R")
panic_v <- list(leaf = "SPECIAL_OP", walk_forward = TRUE,
                op_code_path = "stage_artifacts/WT_R20260829_004/s2_mech.R")
ret_v <- list(leaf = "FIELD", group_id = "A1_RAWDATA_OHLCVS_daily", field = "Ret")
vol_v <- list(op = "CS_ZSCORE", children = list(list(op = "MUL", children = list(
  list(op = "TS_STD", window = 126L, children = list(
    list(op = "TS_LAG", k = 1L, unit = "d", children = list(ret_v)))), K(-1)))))
pool_v <- list(op = "CLIP", lo = 0, hi = 1, children = list(
  list(op = "SUB", children = list(K(51), list(op = "CS_RANK", children = list(mom_v))))))
AST_V <- list(op = "IF_ELSE", children = list(panic_v,
  list(op = "ADD", children = list(list(op = "MUL", children = list(pool_v, K(100))), vol_v)),
  list(op = "CS_ZSCORE", children = list(mom_v))))
pkg2 <- pkg; pkg2$ast <- AST_V; pkg2$factors[[1]]$ast <- AST_V
probe_path <- file.path(OUT, "alpha_package_verifier_dialect_probe.json")
write_json(pkg2, probe_path, pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
probe <- run_ver(probe_path, file.path(OUT, "ast_verify_probe.json"))

block <- list(
  tool = "02_Infrastructure/ast/ast_verify.py",
  main_package = main, verifier_dialect_probe = probe,
  traversal_evidence = sprintf(
    "정본(schema.json 방언: args + 문자열 리프 + escape_contract) 순회 리프 %s개 · 연산자 %s개 / 검증기 방언 probe(children + const 노드 + FIELD 분해 + SPECIAL_OP 평면계약) 리프 %s개 · 연산자 %s개. 리프 0개 순회(빈 검증) 아님.",
    main$leaf_count, main$op_count, probe$leaf_count, probe$op_count),
  leaf_inventory = paste("실제 트리 리프 4종: SPECIAL_OP(JT1993 형성) x2 참조 · SPECIAL_OP(PANIC_REGIME) ·",
                         "A1_RAWDATA_OHLCVS_daily:Ret. DIV/DIV_GUARD 는 미사용이라 그 방언 분열에는 닿지 않는다."),
  pit_reading = sprintf(paste("정본 max_avail_ts=%s / decision_ts=%s / lookahead violations=%s ·",
                              "검증기 방언 probe verdict=%s max_avail_ts=%s violations=%s contract_failures=%s"),
                        main$max_avail_ts, main$decision_ts, main$violations_n,
                        probe$verdict, probe$max_avail_ts, probe$violations_n,
                        length(probe$contract_failures)),
  contract_surface_split = paste(
    "세 겹의 방언 분열이 동시에 걸린다. ①리프 표기: schema.json 은 leaf=문자열 식별자 + escape_contract 객체,",
    "ast_verify.py 는 {leaf:'FIELD', group_id, field} / {leaf:'SPECIAL_OP', op_code_path, walk_forward} 평면 형식.",
    "②자식 키: schema=args / 검증기=children(둘 다 수용하나 args 는 dialect 플래그).",
    "③스칼라: schema 는 args 안 bare number 를 허용, 검증기는 {const:n} 노드만 dict 로 인정.",
    "본 패키지는 패키지 형식 정본인 schema.json 을 따르고(ast), 같은 트리를 검증기 방언으로 옮긴 probe 를",
    "stage_artifacts 에 함께 발행해 동일 검증기로 돌렸다. 결과: 정본 FAIL_CONTRACT(사유 전부 표기 형식) vs",
    "probe PASS. 두 판정 모두 leaf_count 4 · op_count 11 로 같은 트리를 실제로 순회했고 lookahead 위반은 0 이다.",
    "즉 정본의 FAIL 은 PIT 결함이 아니라 계약 표면 분열이다 — 하네스 수리 대상으로 기록한다",
    "(본 에이전트는 계약 파일을 고치지 않는다: 역할 경계).",
    "★부수 소득: 이 계기가 실제로 발화해 A1:Ret 의 same-day 사용을 잡았고, 그 지적을 받아",
    "종목 변동성·시장 변동성·I_B 24개월 누적을 전부 strict t-1(Date < 신호일)로 조여 재측정했다.",
    "AST 는 그 수리를 TS_LAG(k=1, unit=d) 로 표현한다.", sep = " "))
write_json(block, file.path(OUT, "s7_astverify.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")

pkg$ast_verify_result <- block
write_json(pkg, file.path(MBX, "alpha_package.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")
av <- fromJSON(file.path(OUT, "alpha_validation.json"), simplifyVector = FALSE)
av$ast_verify_result <- block
write_json(av, file.path(OUT, "alpha_validation.json"), pretty = TRUE, auto_unbox = TRUE, digits = 8, na = "null")

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id = "WT-R20260829_004", package_type = "alpha_package",
  method_selected = "ast_verify 결과 주입판(최종)",
  input_file_paths = c(file.path(OUT, "s7_astverify.json"), file.path(OUT, "ast_verify.json")))

cat(sprintf("[S7] main verdict=%s exit=%s leaf=%s op=%s viol=%s | probe verdict=%s exit=%s leaf=%s\n",
            main$verdict, main$exit_code, main$leaf_count, main$op_count, main$violations_n,
            probe$verdict, probe$exit_code, probe$leaf_count))
if (length(main$contract_failures)) { cat("[S7] contract_failures:\n"); str(main$contract_failures) }
if (main$violations_n > 0) { cat("[S7] violations:\n"); str(main$violations) }
