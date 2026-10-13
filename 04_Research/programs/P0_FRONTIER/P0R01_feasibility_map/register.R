## P0R01 — 사양 검증 · 컴파일 · 시행 회계 · ★사전등록(R2 · 측정 전 고정) · 등록부 기록
## 실행: Rscript register.R   (사전등록이 이미 있으면 멈춘다 — 결과 뒤 재작성 금지)
suppressPackageStartupMessages({ library(data.table); library(jsonlite) })
ROOT <- "C:/Users/99922/OneDrive/Quant_Module_Moltbot"
Sys.setenv(CLAUDE_PROJECT_DIR = ROOT, QM_ROOT = ROOT); setwd(ROOT)
source("02_Infrastructure/programs/rx_round.R")
source("02_Infrastructure/programs/program_registry.R")
source("02_Infrastructure/contracts/measurement_axis.R")
RD <- file.path(ROOT, "04_Research/programs/P0_FRONTIER/P0R01_feasibility_map")
source(file.path(RD, "round_def.R"))
source(file.path(ROOT, "04_Research/programs/P2_DEFENSE/P2R01_s2_pilot/round_common.R"))   # rc_lineage_trials · rc_write_spec · rc_md5
P <- rx_paths(P0_PROGRAM, P0_ROUND, ROOT)
PR <- file.path(P$prereg_dir, "prereg.json")
if (file.exists(PR)) stop("[P0R01] 사전등록이 이미 있다 — 결과 뒤 재작성 금지(R2): ", PR)

EP <- ma_epoch(root = ROOT)
if (!identical(EP$universe, "ALL_HYG")) stop("[P0R01] 활성 측정 축이 ALL_HYG 가 아니다 — 전환 뒤 축에서만 잰다")
ENG <- p0_engines(ROOT); CMP <- p0_components()
N_ROUND <- length(ENG) * length(CMP)
n_lin <- rc_lineage_trials(ROOT)                       # 2002.06975 L1 계보 측정 시도(essence/grade 보유)

## ① 칸 사양 — 검증(엔진 파서) → 컴파일(활성 epoch 표식) → 쓰기
cells <- list(); bad <- character(0)
for (e in ENG) {
  b <- p0_base_spec(e)
  lt <- if (is.na(e$lineage_trials)) n_lin else e$lineage_trials
  nf <- as.integer(lt + e$prior_round_variants + N_ROUND)
  SA <- list(selection_type = "sweep", family_root = e$family,
             lineage = c(paste0("RX_", P0_ROUND), unlist(b$selection_accounting$lineage %||% list())),
             n_family_at_registration = nf,
             n_trials_basis = sprintf("P0R01: 계보 측정 시도 %d + 앞 라운드 변형 %d + 이 라운드 칸 %d(엔진 %d × 부품 %d · 선택은 21칸 전체에서)",
                                      as.integer(lt), as.integer(e$prior_round_variants), N_ROUND, length(ENG), length(CMP)))
  for (c in CMP) {
    d <- p0_delta_for(b, c)
    code <- sprintf("P0R01_%s_%s", e$id, c$id)
    if (length(d)) { v <- rx_validate(d, ROOT); if (!isTRUE(v$ok)) { bad <- c(bad, sprintf("%s: %s", code, paste(v$errors, collapse = " | "))); next } }
    sp <- rx_compile_spec(b, d, code = code, label = sprintf("%s × %s", e$name, c$name),
                          idea = sprintf("[P0R01 실현 가능성 지도 · %s × %s] %s", e$id, c$id, c$basis),
                          selection_accounting = SA, epoch = EP, root = ROOT)
    f <- file.path(P$specs_dir, paste0(code, ".json"))
    cells[[code]] <- list(code = code, engine = e$id, component = c$id, path = sub(paste0("^", ROOT, "/"), "", f),
                          md5 = rc_write_spec(sp, f), n_family = nf)
  }
}
if (length(bad)) stop("[P0R01] 검증 실패 — 등록하지 않는다:\n", paste(bad, collapse = "\n"))
cat(sprintf("[P0R01] 칸 %d개 검증 · 컴파일 완료(측정 축 %s)\n", length(cells), EP$id))

## ② 판정 설정 고정 — 행동 카드 설정 사본(위기 정의 · uc_floor) · 목표 명세 출처
BC <- file.path(ROOT, "06_Registry/behavior_card.json"); BCP <- file.path(RD, "behavior_card_cfg_at_prereg.json")
file.copy(BC, BCP, overwrite = TRUE)
REG <- pr_load(ROOT); TS <- REG$target_spec
BCJ <- fromJSON(BC, simplifyVector = FALSE)
TD <- fromJSON(file.path(ROOT, "02_Infrastructure/worktask/constraint_defaults.json"), simplifyVector = FALSE)$tier_graduation
GV <- fromJSON(file.path(ROOT, "06_Registry/grade_v3.json"), simplifyVector = FALSE)

## ③ 사전등록
dir.create(P$prereg_dir, recursive = TRUE, showWarnings = FALSE)
pre <- list(
  schema = "rx_prereg_v1", program = P0_PROGRAM, round_id = P0_ROUND,
  registered_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  purpose = "P0 실현 가능성 지도 — 문헌 표준 단순 부품 × 기존 수익 엔진이 한국 전 종목(측정 축 all_hyg_2000_v1)에서 목표 영역에 닿는가(등록부 P0_FRONTIER thesis)",
  hypothesis = REG$programs[[which(vapply(REG$programs, function(p) p$id, character(1)) == P0_PROGRAM)]]$thesis,
  measurement_axis = list(epoch = EP$id, universe = EP$universe, start = format(EP$start_date),
                          effective_start_rule = EP$effective_start),
  tau_d = "2022-12-31",
  engines = lapply(ENG, function(e) list(id = e$id, name = e$name, family = e$family, why = e$why)),
  components = lapply(CMP, function(c) list(id = c$id, name = c$name, delta = c$delta, basis = c$basis)),
  cells = unname(cells),
  decisive_test = list(
    statement = "보는 창(측정 시작~2022-12-31)에서 목표 영역에 닿는 칸이 하나라도 있는가 — 있으면 시험 창(2023-01~)에서 같은 판정을 유지하는가",
    target_region = list(
      list(field = "behavior.summary.bull_up_capture_median", op = ">=", value_source = "behavior_card_cfg_at_prereg.json::uc_floor",
           value = BCJ$uc_floor),
      list(field = "behavior.summary.crisis_cum_capture_median", op = "<=", value_source = "같은 패킷 behavior.dc_strong_max(uc_floor 와 KOSPI200 강세→약세 쌍에서 도출 · behavior_card.R::bc_dc_strong_max)",
           value = "derived"),
      list(field = "performance.strategy.cagr", op = ">=", value_source = "research_programs.json::target_spec.cagr_min", value = TS$cagr_min$value)),
    test_window = paste("목표 영역 칸만: 전기간 행동 카드(matched_controls.R::mc_card)의 test 블록 상승 포착 · 위기 누적 포착(같은 문턱) +",
                        "시험 창 CAGR(grade_v3.R::gv3_window · 2023-01~) — 시험 창에 강세 국면 · 위기가 없으면 그 항목은 '판정 불가'"),
    kill_or_pivot = "보는 창 목표 영역 칸 0 → 탐색을 늘리지 않고 도훈 안건(목표 또는 축 재검토) — 등록부 P0_FRONTIER kill_or_pivot"),
  expectations = list(   # 부품별 기대 방향(같은 엔진 C0 대비 · 보는 창) — 판정이 아니라 기전 기록(맞은 수를 R 이 센다)
    C1 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C0"),
              list(field = "behavior.summary.bull_up_capture_median", op = "<=", ref = "C0")),
    C2 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C0")),
    C3 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C0"),
              list(field = "behavior.summary.bull_up_capture_median", op = "<=", ref = "C0")),
    C4 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C0"),
              list(field = "behavior.summary.bull_up_capture_median", op = "<=", ref = "C0")),
    C5 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C0")),
    C6 = list(list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C1"),
              list(field = "behavior.summary.crisis_cum_capture_median", op = "<", ref = "C4"))),
  final_selection_rule = list(
    text = paste("보는 창 목표 영역 칸 중 보는 창 종합점수 S_vis = (Calmar/c0)^w_c × (PORT_t/p0)^w_p 최대 칸 1개(Calmar · PORT_t ≤ 0 이면 S_vis = 0) ·",
                 "동률(차 < 0.02) → 위기 누적 포착 낮은 칸 → 부품 수 적은 칸. 목표 영역 칸이 0 이면 선택 없음.",
                 "상수(c0 · p0 · w_c · w_p)는 등급 v3 정본에서 읽는다 — 보는 창 패킷 필드만 쓴다(τ_D)."),
    calmar_norm = TD$min_calmar, port_t_norm = TD$min_portfolio_alpha_t_nw,
    w_calmar = GV$weights$calmar %||% GV$w_calmar %||% NA, w_port_t = GV$weights$port_t %||% GV$w_port_t %||% NA, tie_eps = 0.02),
  axis_audit = "측정 뒤 04_holdings 실보유가 롱온리 · ≤ constraint_defaults.json::tier_soft_deployment.max_names · Σw ≤ 1 인지 — 위반 칸 = 측정 무효(미시험)",
  measurement = list(runner = "02_Infrastructure/ops/rf_cell_worker.R → run_paper_replication(close_t1 · 15bps · 측정 축 표식 epoch)",
                     grade = "essence v3(권위 · 사람 쪽)", visible = "diagnosis_packet.R::dp_build(bcfg = 사전등록 사본 · 위생 raw)",
                     full = "matched_controls.R::mc_card(전기간 · 시험 창 블록)"),
  selection_accounting = list(E1 = cells[[1]]$n_family, E2 = cells[[1L + length(CMP)]]$n_family, E3 = cells[[1L + 2L * length(CMP)]]$n_family,
                              note = "sweep — 이 라운드의 선택은 21칸 전체에서 · 2002.06975 계보는 L1 측정 시도 + P2R01 변형을 함께 센다"),
  budget = list(variants = N_ROUND, rounds = 1L, note = "등록부 budget rounds 1 · 변형 상한 = 이 사전등록(21)"),
  behavior_card_cfg = list(path = sub(paste0("^", ROOT, "/"), "", BCP), md5 = rc_md5(BCP)))
if (!is.finite(as.numeric(pre$final_selection_rule$w_calmar)) || !is.finite(as.numeric(pre$final_selection_rule$w_port_t)))
  stop("[P0R01] 등급 v3 가중(grade_v3.json) 판독 실패 — 선택 규칙 상수를 지어내지 않는다")
writeLines(toJSON(pre, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA), PR, useBytes = TRUE)
file.copy(PR, file.path(RD, "prereg.json"), overwrite = TRUE)
PRMD5 <- rc_md5(PR)
cat(sprintf("[사전등록] %s (md5 %s) · 칸 %d · 시행 수 E1 %d · E2/E3 %d\n", PR, PRMD5, length(cells),
            pre$selection_accounting$E1, pre$selection_accounting$E2))
pr_set_status(P0_PROGRAM, "active", reason = sprintf("라운드 %s 사전등록(%d칸 · 측정 축 %s)", P0_ROUND, length(cells), EP$id), root = ROOT)
pr_record_round(P0_PROGRAM, list(round_id = P0_ROUND, prereg = sub(paste0("^", ROOT, "/"), "", PR), prereg_md5 = PRMD5,
                                 status = "registered", n_variants = length(cells),
                                 variants = unname(vapply(cells, function(z) z$code, character(1)))), root = ROOT)
cat("[P0R01] 등록부 기록 완료\n")
