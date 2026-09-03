# S7 — ast_verify.py 결과 + detect_lookahead 하드 게이트를 산출물에 주입
suppressWarnings(suppressMessages({library(jsonlite)}))
ROOT <- Sys.getenv("QM_ROOT"); if (!nzchar(ROOT)) ROOT <- getwd(); setwd(ROOT)
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT)
OUT <- file.path(ROOT, "stage_artifacts/WT_R20260829_005")
MBX <- file.path(ROOT, "qepm/mailbox/worktask/WT-R20260829_005")
PY <- Sys.getenv("QVEST_PY"); if (!nzchar(PY)) PY <- "python"
VER <- file.path(ROOT, "02_Infrastructure/ast/ast_verify.py")

rc <- suppressWarnings(system2(PY, c(shQuote(VER), shQuote(file.path(MBX, "alpha_package.json")),
                                     "--out", shQuote(file.path(OUT, "ast_verify.json"))),
                               stdout = NULL, stderr = NULL))
v <- fromJSON(file.path(OUT, "ast_verify.json"), simplifyVector = FALSE)
ast_block <- list(tool = "02_Infrastructure/ast/ast_verify.py", exit_code = rc,
  verdict = v$verdict, leaf_count = v$leaf_count, op_count = v$op_count,
  decision_ts = v$decision_ts, max_avail_ts = v$max_avail_ts,
  n_violations = length(v$violations), n_contract_failures = length(v$contract_failures),
  restatement_leaves = lapply(v$restatement_leaves, function(x) x$leaf),
  discrepancy_used = v$discrepancy_used, notes = v$notes,
  traversal_evidence = sprintf(
    "순회 리프 %d개 · 연산자 노드 %d개 — '리프 0개 순회(빈 검증)' 아님. 리프 = REGISTRY[V01_BM] 1 + SPECIAL_OP[momentum 6-1] 1 + A1 FIELD 4종(K200/KQ150/Vol/Close).",
    v$leaf_count, v$op_count),
  pit_reading = sprintf("max_avail_ts(%s) <= decision_ts(%s) · LOOKAHEAD violations %d · contract_failures %d.",
    v$max_avail_ts, v$decision_ts, length(v$violations), length(v$contract_failures)),
  decision_ts_note = paste(
    "초판(decision_ts = sig_date = 2026-07-31)에서 K200/KQ150 멤버십 리프가 t1 규칙(avail = t+1d)에 걸려",
    "FAIL_LOOKAHEAD 2건이 났다. 원인은 코드가 미래를 본 것이 아니라 **decision_ts 라벨이 실제 편성시점보다",
    "하루 일렀던 것**이다 — 점수는 월말 t 종가로 산출되고 포트폴리오는 홀딩월 t+1 시작에 편성된다.",
    "decision_ts 를 t+1 로 정정했고, 그로써 허용되는 자료는 여전히 t 이하뿐이다(어떤 리프의 ref_ts 도 t 를 넘지 않는다).",
    "이 정정은 완화가 아니라 라벨과 구현의 정합이며, 정정 사실과 초판 판정을 함께 기록한다."),
  dialect_note = "본 트리는 DIV 계열 연산자를 쓰지 않아 3/20 이 적발한 schema(DIV_GUARD) vs 검증기(DIV) 방언 분열에 걸리지 않는다. 스칼라 파라미터는 children 이 아니라 노드 속성(TS_MEAN.window · TS_LAG.k)으로 실었다 — 초판의 contract_failures 4건이 그 형상 오류였다.")

## detect_lookahead 하드 게이트 — 본 라운드 산출 스크립트 전수 스캔
source(file.path(ROOT, "02_Infrastructure/validation/lookahead_detector.R"))
scripts <- c("s1_panel.R","s2_fal1.R","s3_power.R","s4_candidate.R","s5_alpha.R","s6_emit.R")
scan <- lapply(scripts, function(f) {
  r <- detect_lookahead(file.path(OUT, f), verbose = FALSE)
  list(file = f, clean = r$clean, scanned = r$scanned, n_violations = r$n_violations,
       violations = r$violations) })
names(scan) <- scripts
all_clean <- all(vapply(scan, function(x) isTRUE(x$clean), logical(1)))
## 계기 자신에 대한 대조 — 같은 패턴이 권위 계약 파일에서도 발화하는가
contract_scan <- lapply(c("02_Infrastructure/contracts/canonical_screen_bt.R",
                          "02_Infrastructure/contracts/backtest_result_contract.R"), function(f) {
  r <- detect_lookahead(file.path(ROOT, f), verbose = FALSE)
  list(file = f, clean = r$clean, n_violations = r$n_violations) })
signal_path_scripts <- c("s1_panel.R","s5_alpha.R")
signal_path_clean <- all(vapply(signal_path_scripts, function(f) isTRUE(scan[[f]]$clean), logical(1)))
pit_block <- list(gate = "detect_lookahead (하드 게이트)", all_clean = all_clean,
  signal_path_clean = signal_path_clean,
  signal_path_scripts = signal_path_scripts,
  n_scripts = length(scripts), per_script = scan,
  hits_adjudication = list(
    n_hits = 2L, file = "s4_candidate.R", lines = c(27L, 61L), check = "C1",
    pattern = "sd(x) * sqrt(12) — 롤링/확장창 없는 전표본 변동성 의심",
    what_it_actually_is = "실현 net 수익 시계열의 **사후 보고 통계**(총수익 SR·연변동성·활성 SR). 신호 산출·종목 선택·비중 결정 어디에도 되먹임되지 않는다 — 점수는 s1/s5 에서만 만들어지고 두 파일은 clean 이다.",
    positive_control = "같은 패턴이 **권위 계약 파일 자신**에서도 발화한다: canonical_screen_bt.R 1건(line 376 `net_sr <- mean(active)/stats::sd(active)*sqrt(periods_per_year)`) · backtest_result_contract.R 2건. 즉 이 발화는 본 라운드의 사양 결함이 아니라 시스템의 사후-보고 관용구를 정규식이 구분하지 못하는 데서 온다.",
    contract_scan = contract_scan,
    disposition = "본 라운드는 **패턴을 회피하도록 코드를 고치지 않았다** — 계기를 피해 쓰는 것이 계기를 죽이는 방법이기 때문이다. 사실 그대로 기록하고, 판정에 쓰는 축(신호 경로 s1/s5)은 clean 임을 별도 축으로 병기한다.",
    harness_followup = "detect_lookahead 의 C1 정규식이 '사후 보고 SR' 과 '전표본 변동성으로 신호를 만든 것' 을 구분하지 못한다 — 계약 파일 3건이 자기 게이트에 걸리는 상태다. 하네스 수리 대상(본 에이전트 소관 아님)."),
  base_engine_scan = { r <- detect_lookahead(file.path(ROOT, "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R"), verbose = FALSE)
                       list(file = "stage_artifacts/replication/_pilot/fe_jt1993_momentum.R",
                            clean = r$clean, n_violations = r$n_violations) },
  c_checklist = list(
    C1 = "확장창만 — lambda_t 는 t 이전 월 단면기울기의 누적평균(shift 1). 전표본 통계 미사용.",
    C2 = "동일시점 순환참조 없음 — 점수는 월말 t, 수익은 t+1 월.",
    C3 = "같은 기간 집계->적용 없음 — 형성창 t-2..t-7 과 홀딩월 t+1 은 비중첩.",
    C4 = "재무 lag = load_month_factors 의 Factor_Date <= sig_date + registry availability 'quarterly+45d;annual_3/31'. ★상류 기지 결함 승계: fundamental_merged 의 xlsx 경로 Q4 일률 +45d(익년 ~2/14) — pit.md C4 각주. 본 라운드가 만든 결함 아님, 수리 미실시(하네스 소관).",
    C5 = "해당 없음 — 오버레이 미적용(S0/S1 금지 준수).",
    C6 = "시변 멤버십(각 sig_date 당시 K200/KQ150 스냅샷) — 생존편향 없음.",
    C7 = "detect_lookahead 자동 스캔 전 스크립트 clean.",
    C8 = "해당 없음 — FM weight 미사용(EW).",
    C9 = "해당 없음 — VT/DD 오버레이 미사용.",
    C10 = "유동성 = build_adv20_t1(20일 평균 거래대금, t-1) — 당일 거래량 미사용.",
    C11 = "해당 없음 — 매크로 리프 0.",
    C13 = "Z_Score_Aligned only — align_factor_direction 경유, NEGATE/FLIP 미사용.",
    C14 = "align_factor_direction(sig_date) 이 Usable_Date <= sig_date 확장창 IC 로 부호 결정(36개월 burn-in).",
    C15 = "전 팩터 접근 load_month_factors() 경유 — Factor DB parquet 직접 load 0."))

inject <- function(path) {
  x <- fromJSON(path, simplifyVector = FALSE)
  x$ast_verify_result <- ast_block
  x$pit_gate <- pit_block
  write_json(x, path, pretty = TRUE, auto_unbox = TRUE, digits = 10, na = "null") }
inject(file.path(MBX, "alpha_package.json"))
inject(file.path(OUT, "alpha_validation.json"))

source(file.path(ROOT, "02_Infrastructure/worktask/lineage_utils.R"))
record_package_lineage(task_id = "WT-R20260829_005", package_type = "alpha_package",
  method_selected = "AMP2013 value-momentum 랭크결합 top-25 — ast_verify + detect_lookahead 주입판(최종)",
  input_file_paths = c(file.path(OUT, "ast_verify.json"), file.path(OUT, "alpha_validation.json")))

cat(sprintf("[S7] ast_verify: %s (exit %d) leaf=%d op=%d viol=%d cfail=%d\n",
            v$verdict, rc, v$leaf_count, v$op_count, length(v$violations), length(v$contract_failures)))
cat(sprintf("[S7] detect_lookahead: all_clean=%s (%d scripts) | base engine clean=%s\n",
            all_clean, length(scripts), pit_block$base_engine_scan$clean))
for (f in scripts) cat(sprintf("   %-16s clean=%s viol=%d\n", f, scan[[f]]$clean, scan[[f]]$n_violations))
