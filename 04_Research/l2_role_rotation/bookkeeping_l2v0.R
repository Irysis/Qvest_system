#==============================================================================
# bookkeeping_l2v0.R — PR-L2-ROLESLEEVE-V0 2계층 부기 (판정 뒤 · 1회)
#
#   ① L-code: axiom/lcode_emit.R::emit_fr_lcode(track='factor_rotation' — strategy_rotation alias) — 수치는 판정 JSON 에서만 읽는다.
#   ② FR 레지스트리(register_fr_result): 등재하지 않는다 — 문서화된 입력 = run_wf_ensemble 산출(fr 리스트) · 소비자 rf_director
#      (dir_lever_l2)가 마지막 FR 의 04_Research/factor_rotation/output/<fr_id>/manipulation_check.json 을 찾는다. 이 단위는
#      run_paper_replication(종목 수준 25종) 측정이라 형식을 억지로 맞추지 않는다(Q-Lead 지시 'do NOT force').
#   ③ L2 원장(rf_open_entry/rf_append_attempt layer=2): 개설하지 않는다 — 사전등록 실험의 원장 경로(rf_open_entry(priority='prereg',
#      experiment=))는 prereg_config run.live_enabled=false(별판 검토 전) · L2 무인 레인(rf_l2_auto.R)은 run_wf_ensemble arm 만 돈다 ·
#      scope mechanism_only(A 자격 없음)라 A 를 향한 강화 계보가 성립하지 않는다.
# 실행: 이 디렉터리에서 Rscript --no-save -e 'source("bookkeeping_l2v0.R")' · 텔레그램 없음(Q-Lead 소관)
#==============================================================================
suppressPackageStartupMessages({ library(jsonlite) })
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
.find_root <- function() {
  for (p in c(Sys.getenv("CLAUDE_PROJECT_DIR", ""), Sys.getenv("QM_ROOT", ""), getwd(), dirname(getwd()), dirname(dirname(getwd())))) {
    if (nzchar(p) && file.exists(file.path(p, "02_Infrastructure/config.R"))) return(normalizePath(p, winslash = "/"))
  }
  stop("[bookkeeping_l2v0] 프로젝트 루트 미발견")
}
ROOT <- .find_root(); L2DIR <- file.path(ROOT, "04_Research/l2_role_rotation")
REC <- file.path(L2DIR, "verdict/bookkeeping_v0.json")
if (file.exists(REC)) stop("[bookkeeping_l2v0] 1회 — 이미 있다: ", REC)
V <- fromJSON(file.path(L2DIR, "verdict/h1_verdict_v0.json"), simplifyVector = FALSE)
Tv <- V$arms$T_var; Kv <- V$arms$K; Ew <- V$arms$EW_all
pc <- function(x, d = 1) formatC(100 * as.numeric(x), format = "f", digits = d)
f3 <- function(x, d = 3) formatC(as.numeric(x), format = "f", digits = d)
lesson <- sprintf(paste0(
  "[2계층 #1 · PR-L2-ROLESLEEVE-V0 · mechanism_only] as-of 역할 슬리브(65 close_t1 모듈)를 MSM as-of 고분산 확률로 기울인 T_var 는 ",
  "노출 맞춤 정적 K 대비 일평균 Δ %s%%/yr · NW t %s(lag3) → H1 %s(SESOI 1%%/yr 배제 못 함 — 미결, 벽 아님). ",
  "위험조정 얼굴도 없다: Calmar Δ(부트) %s · p_gt0 %s. 기전 전제 붕괴: as-of 방어 슬리브의 창 내 약세월(사후 PS %d개월) β-잔차 평균 %s%%/월 · ",
  "NW t %s → 방어 라벨이 다음 약세로 이어지지 않는다(MC2 FAIL). 처치는 전달됐다(MC3 %s · 종목 %s). 5 arm 전부 essence C · PORT_t 음수. ",
  "슬리브를 무시한 EW_all(가용 모듈 동일가중 → 상위 25)이 우위(CAGR %s%% · SR %s · Calmar %s vs T_var %s%% · %s · %s)."),
  f3(V$H1$value_ann * 100), f3(V$H1$t), V$label %||% "NA", f3(V$boot$calmar$value), f3(V$boot$calmar$p_gt0),
  as.integer(V$MC2$n_bear_months), f3(100 * as.numeric(V$MC2$mean_bear_resid)), f3(V$MC2$nw_t, 2), f3(V$MC3$value), f3(V$MC3$stock_level_T_K),
  pc(Ew$cagr), f3(Ew$net_sharpe), f3(Ew$calmar), pc(Tv$cagr), f3(Tv$net_sharpe), f3(Tv$calmar))
source(file.path(ROOT, "02_Infrastructure/axiom/lcode_emit.R"))
lc <- emit_fr_lcode(
  strategy_id = "L2_ROLESLEEVE_V0", grade = Tv$essence_grade, lesson_text = lesson, track = "factor_rotation",
  metric_type = "backtested", construction_type = "regime_rotation",
  mechanism_hypothesis = "Moreira & Muir(2017) 분산 타이밍 — 고분산 상태(MSM as-of P↑)에 방어·α 슬리브, 저분산 상태에 공격·반등 슬리브로 기울이면 노출 맞춤 정적 혼합 대비 수익·위험조정 수익이 오른다",
  oos_retention = Tv$oos_retention, portfolio_alpha_t = Tv$port_t, selection_type = "chain",
  next_probe = list(
    "역할 라벨 지속성 수리가 먼저 — as-of 방어 등급을 '다음 약세 구간 잔차'로 검증되는 표적(실현 하락월·심층 하락 캡처의 as-of 판)으로 다시 정의하고 MC2 재측정",
    "EW_all 우위의 기전 분해 — 역할 부분집합 consensus 상위 25 가 전 모듈 consensus 보다 못한 이유(종목 집중·25 절단 뒤 남는 모듈 질량 비율 = 엔진 진단 kept_share) · 슬리브 안 비중법(EW→RP) 또는 모듈 단위 배분 대조",
    "분산 상태 기울기를 역할 라벨 대신 모듈 as-of 실현 β 순위에 걸기(고분산 → 저β 모듈 비중↑ · 고정 축 안 레버) — 같은 사전등록 틀(K 노출 맞춤·MC3)로"),
  source_paper = "https://doi.org/10.1111/jofi.12513",
  paper_assumption_broken = "M&M 의 개선은 분산을 낮추는 노출 조절에서 나오는데, Σw=1 롱온리 슬리브 혼합에서는 고분산 국면 기울기가 변동성을 낮추지 못했고(T_var·K 연변동성은 bt metrics 참조) as-of 방어 라벨이 미래 약세로 이어지지 않았다",
  tags = c("STRATEGY_ROTATION", "L2", "ROLE_SLEEVE", "PREREG_DRAFT", "MECHANISM_ONLY"),
  metrics = list(cagr_pct = round(100 * as.numeric(Tv$cagr), 2), sharpe = Tv$net_sharpe, mdd_pct = round(100 * as.numeric(Tv$mdd), 2), calmar = Tv$calmar,
                 h1_t = V$H1$t, h1_delta_ann_pct = 100 * as.numeric(V$H1$value_ann), h1_label = V$label, mc2_nw_t = V$MC2$nw_t, mc3 = V$MC3$value,
                 prereg_id = V$prereg_id, prereg_draft_sha256 = V$prereg_draft$sha256, verdict = "04_Research/l2_role_rotation/verdict/h1_verdict_v0.json"),
  project_root = ROOT)
out <- list(schema = "l2v0_bookkeeping_v1", prereg_id = V$prereg_id, at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
            lcode = list(emitted = !is.null(lc), path = if (is.character(lc)) sub(paste0("^", ROOT, "/"), "", lc) else NULL),
            fr_registry = list(registered = FALSE, reason = "register_fr_result 의 문서화된 입력 = run_wf_ensemble 산출(fr 리스트) · 소비자 rf_director dir_lever_l2 가 FR 산출 디렉터리(manipulation_check.json)를 전제 — run_paper_replication 측정 단위를 억지로 맞추지 않음(Q-Lead 'do NOT force'). 필요한 것 = 'run_paper_replication 측정 2계층 단위' 수락 결정 + 어댑터(fr_id·module_pool·manipulation_check 경로 규약)"),
            l2_ledger = list(opened = FALSE, reason = "사전등록 실험의 원장 개설(rf_open_entry priority='prereg', experiment=)은 prereg_config run.live_enabled=false · rf_l2_auto.R 는 run_wf_ensemble arm 만 실행 · scope mechanism_only(A 자격 없음)라 A 표적 강화 계보 부적합"),
            telegram = "미발송(Q-Lead 소관)")
writeLines(toJSON(out, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"), REC, useBytes = TRUE)
cat(sprintf("[bookkeeping_l2v0] L-code %s · FR 미등재 · L2 원장 미개설 · 기록 %s\n", if (!is.null(lc)) "적립" else "실패", REC))
