## FQ-191 종결 — H3 판정 + 오버레이 라우팅 + 원장 + close_round
suppressPackageStartupMessages({ library(jsonlite); library(data.table) })
ROOT <- Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
OUT  <- file.path(ROOT, "stage_artifacts/FQ191")
say  <- function(fmt, ...) { cat(sprintf(paste0("[cl] ", fmt, "\n"), ...)); flush.console() }
source("02_Infrastructure/ops/claim_state.R"); source("02_Infrastructure/ops/frontier_queue_io.R")

V <- list(
  round_id = "FQ-191", parent = "FQ-138",
  prereg_ref = "stage_artifacts/FQ191/preregistration.json (측정 전 작성 — OFF 월 처리 고정 포함)",
  as_of = "2026-08-09", metric_type = "canonical_screen", capital_claim = FALSE, governor_invoked = FALSE,
  verdict = "H3_NOT_CAPITAL_ELIGIBLE — 오버레이/선별 라벨 소비면으로 확정 라우팅",

  rule_measured = "국면 ON(t-1 mega_spread<=0): 계약 신호 top-25 EW · OFF: 벤치마크 보유. 전환 시 |Δ보유명목|×15bps 실과금.",

  HARD_3 = list(
    canonical_window = "2026 제외 (계약 패널 물리불가 68건 중 63건이 2026, 미수리)",
    n_months = 73L,
    port_t = list(value = 2.204, threshold = 2.95, pass = FALSE, gap = -0.746),
    oos_retention = list(value = 0.414, threshold = 0.7, pass = FALSE,
                         note = "★<0.5 = measurement-graduation §3 **증거 무관 무조건 FAIL** band"),
    calmar = list(value = 1.213, threshold = 0.64, pass = TRUE, ratio = 1.90),
    reference = list(cagr_pct = 27.63, mdd_pct = -22.77, ir = 0.935, active_sr = 0.935, alpha_ann = 0.0902),
    sensitivity_2026_included = list(port_t = 2.053, oos = 0.220, calmar = 1.311, n = 79L)),

  key_finding = list(
    lift = "★무조건부 PORT_t **+0.581 → 국면-조건부 +2.204** (3.8배) — 국면 조건부가 재료를 실제로 살려냈다",
    but = "2.95 에 **0.746 부족**. 그리고 oos_retention 0.414 는 무조건 FAIL band 라 PORT_t 를 고쳐도 별도 관문이 남는다",
    oos_diagnosis = "★국면 ON 이 27개월뿐이라 분할하면 표본이 무너진다 — 사전등록 known_risks 에 미리 적은 위험이 실현됐다. '효과 부재' 가 아니라 **검정력 부족** 라벨.",
    switching_cost = "전환 30회 / 79개월 = 연 4.6회 · 총 4.50%p (연 0.68%p) — 우려보다 작다. 회전율은 병목이 아니었다."),

  off_month_sensitivity = list(
    note = "★사전등록이 argmax 선택을 금지했다 — 아래는 감도 병기이지 판정 아님",
    bench_CHOSEN = list(port_t = 2.204, calmar = 1.213, cagr = 27.63, mdd = -22.77),
    cash = list(port_t = -0.425, calmar = 0.919, cagr = 13.54, mdd = -14.73),
    keep_sleeve = list(port_t = 1.651, calmar = 1.046, cagr = 32.29, mdd = -30.88),
    honest = paste0("★내가 고른 '벤치 보유' 가 결과적으로 셋 중 최고다. 사후에 골랐으면 정확히 그 이유로 무효였을 것 — ",
      "측정 **전에** 논리로 고정했다(현금은 국면 타이밍 알파를 섞고, sleeve 유지는 무조건부와 동일해져 라운드가 무의미). ",
      "오늘 내가 FQ-182 에서 어긴 규율의 반대 사례.")),

  disposition_applied = list(
    rule = "H3 (사전등록 고정): PORT_t 미달 ⇒ 자본이 아니라 **오버레이/선별 라벨** 소비면으로 확정 라우팅",
    also_preassigned = "FQ-138 live_trigger ③ 이 같은 분기를 이미 지정 — 두 사전등록이 일치",
    routing = c("③오버레이/국면 — 국면 ON 에서만 계약 sleeve 활성화하는 구조(자본 sleeve 아님)",
                "⑥선별 라벨 — '계약 재료 = 국면 조건부 유효, 자본 미달' 라벨 등재",
                "⑤monitoring — mega_spread 는 t-1 관측이라 PIT 자명, 국면 tripwire 로 즉시 사용 가능")),

  honest_caveats = c(
    "★자본 주장 없음 — governor 미호출. H3 는 '자본 아님' 확정이므로 admit 논의 자체가 없다",
    "oos_retention 은 canonical 근사(.canon_oos_rough)다. 권위는 essence_score.R — 다만 0.414 는 0.5 band 아래라 권위 측정으로도 뒤집힐 여지가 작다",
    "n 73개월 · 국면 ON 27개월 — HARD 3종 중 분할을 요구하는 게이트는 구조적으로 불리하다",
    "2026 오염 미수리 — 정본은 제외판. 포함판은 PORT_t 2.053 으로 더 낮다(오염이 개선을 만들지 않았다는 증거이기도)",
    "calmar 1.213 통과는 MDD −22.77% 가 낮아서다. 국면 OFF 에 벤치를 든 덕이 크며 **신호 자체의 방어력이 아니다**"),

  artifacts = c("preregistration.json", "p1_measure.R", "p1_rule.csv", "p1.rds"))
writeLines(toJSON(V, auto_unbox = TRUE, pretty = 2, digits = NA), file.path(OUT, "validation.json"))
say("validation.json — %s", V$verdict)

Q <- read_frontier_queue(); ids <- vapply(Q$entries, function(e) as.character(e$id)[1], "")
i <- which(ids == "FQ-191")
Q$entries[[i]] <- make_claim(Q$entries[[i]], "complete", "Q-Lead 2026-08-09",
  "HARD 3종 측정 완료 — H3 판정(자본 아님), 오버레이/선별 라벨 라우팅.")
Q$entries[[i]]$status <- "h3_not_capital_routed_overlay_20260809"
Q$entries[[i]]$result_ref <- "stage_artifacts/FQ191/validation.json"
Q$entries[[i]]$next_action <- paste0(
  "★H3 판정 — 자본 자격 없음, **오버레이/선별 라벨 확정 라우팅**(사전등록 + FQ-138 live_trigger ③ 일치). ",
  "HARD 3종(정본 2026 제외, n=73): PORT_t **+2.204**(문턱 2.95, −0.746) FAIL · oos_retention **+0.414**(문턱 0.7, ★<0.5 무조건 FAIL band) FAIL · calmar **+1.213**(문턱 0.64) PASS. ",
  "참조 CAGR +27.63% · MDD −22.77% · IR +0.935. ",
  "★무조건부 PORT_t +0.581 → 조건부 **+2.204(3.8배)** — 국면 조건부가 재료를 실제로 살려냈으나 문턱엔 미달. ",
  "★oos 진단: 국면 ON 27개월뿐이라 분할 시 표본 붕괴 — 사전등록 known_risks 가 예고한 위험 실현. '효과 부재' 아닌 **검정력 부족**. ",
  "★전환비용은 병목 아님: 전환 연 4.6회 · 총 4.50%p(연 0.68%p). ",
  "★OFF 월 감도(argmax 금지, 병기): 벤치 2.204 / 현금 −0.425 / sleeve 유지 1.651 — 고정 선택이 최고였으나 **측정 전 논리로 고정**했다.")
Q$updated <- "2026-08-09"

nums <- suppressWarnings(as.integer(sub("^FQ-0*([0-9]+).*$","\\1",ids))); nums <- nums[is.finite(nums)]
k <- max(nums); newid <- NULL
repeat { k <- k+1L; c0 <- sprintf("FQ-%03d",k); if (!(c0 %in% ids)) { newid <- c0; break } }
Q$entries[[length(Q$entries)+1L]] <- list(
  id = newid, lane = "non_return",
  title = "★계약 국면 sleeve 의 **오버레이 소비** — 현행 book 대비 book-marginal (H3 라우팅 수행)",
  hypothesis = paste0(
    "FQ-191 이 국면-조건부 계약 규칙을 H3(자본 아님) 로 판정하고 **오버레이/선별 라벨** 로 라우팅했다. ",
    "그 라우팅을 실제로 수행한다: 계약 sleeve 를 독립 자본 sleeve 가 아니라 **현행 book 위 오버레이 성분**으로 소비할 때 ",
    "book-marginal ΔIR 이 문턱 0.05 를 넘는가. ",
    "근거: 조건부 IR +0.935 · calmar 1.213 · MDD −22.77% 는 book 과 결합 시 기여할 여지가 있는 프로파일이다."),
  ev_rationale = "H3 라우팅의 실행. FQ-191 이 이미 규칙·국면·비용을 확정했으므로 남은 것은 결합 측정뿐.",
  wall_check = paste0("★base 는 **05_Production 현행 PG2 코드 파생만 권위**(§7b) — 재구성 base 금지(부호 반전 선례). ",
    "book_state.json 부재 확인됨(2026-08-09) — base 확보 경로부터 사전 확인할 것. ",
    "Production Constraints 불변. governor admit 은 수동."),
  data_gate = "★book base 확보 필요 — FQ-165 가 같은 벽에서 config_scoped_negative 로 끝났다. 착수 전 base 경로 확인 의무.",
  owner = "UNCLAIMED — FQ-191 이 발행. claim_state.R 경유 착수.",
  status = "frontier_open",
  next_action = "①production PG2 base 파생 경로 확인(FQ-165 가 막힌 지점) ②확보 시 book-marginal ΔIR ③|cor|<0.30 ④착수 전 power 바",
  source_refs = list("stage_artifacts/FQ191/validation.json", "stage_artifacts/FQ138/validation.json"))
write_frontier_queue(Q)
say("%s 등재 · FQ-191 claim=%s", newid,
    claim_state(read_frontier_queue()$entries[[i]])$state)

source("02_Infrastructure/contracts/close_round.R")
close_round(
  round_id = "FQ-191", verdict_type = "screen_tier_routed",
  mechanism_diagnosis = paste0(
    "국면 조건부는 계약 재료를 실제로 살려낸다 — 무조건부 PORT_t +0.581 이 조건부 +2.204 로 3.8배 오른다. ",
    "그러나 자본 문턱 2.95 에 0.746 부족하고, 더 결정적으로 oos_retention 0.414 가 <0.5 무조건 FAIL band 다. ",
    "그 원인은 신호 열화가 아니라 표본 구조다 — 국면 ON 이 27개월뿐이라 OOS 분할이 표본을 무너뜨린다(사전등록 known_risks 가 예고). ",
    "전환비용은 병목이 아니었다(연 4.6회, 연 0.68%p). calmar 1.213 통과는 OFF 월에 벤치를 든 덕이며 신호 자체의 방어력이 아니다. ",
    "⇒ 사전등록 H3 대로 자본이 아니라 오버레이/선별 라벨 소비면으로 확정 라우팅한다."),
  next_probes = c(
    paste0(newid, " H3 라우팅 수행 — 계약 sleeve 를 현행 book 위 오버레이 성분으로 소비할 때 book-marginal ΔIR. ★base 확보가 선행(FQ-165 가 같은 벽에서 멈췄다)."),
    "★국면 ON 표본 확대 — oos_retention 이 27개월 분할에서 무너진다. clean OOS 월 누적(사전등록이 2026-08-08 이후를 지정) 또는 국면 정의 완화로 ON 월수를 늘리면 이 게이트가 의미를 갖는다.",
    "PORT_t 갭 0.746 의 출처 분해 — FQ-178 사다리(net→gross→EW-basis)를 이 규칙에 적용하면 비용·벤치 채널이 얼마인지 나온다. M26 에서 그 분해가 통했다.",
    "2026 오염 수리 후 포함판 재측정 — 현재 포함판이 PORT_t 2.053 으로 더 낮다. 수리로 값이 바뀌면 정본 갱신.",
    "기전 규명 — 왜 메가캡이 지는 달에 계약 신호가 강해지는가. FQ-139 가 기관 후속매수를 기각하고 외국인 단독으로 좁혔을 뿐 국면 의존은 미설명."),
  consumer_surfaces = c(
    "①팩터 랭킹 — 무조건부는 여전히 미달(+0.581). 국면 조건부 가중은 근거 확보",
    "②유니버스 필터 — 미측정",
    "③오버레이/국면 — ★**확정 라우팅 대상**. 국면 ON 에서만 계약 sleeve 활성화(자본 sleeve 아님)",
    "④위험모델 — 미측정",
    "⑤monitoring — ★즉시 사용 가능: mega_spread 는 t-1 관측이라 PIT 자명, 국면 tripwire",
    "⑥선별 라벨 — ★'계약 재료 = 국면 조건부 유효, 자본 미달(PORT_t 2.204/oos 0.414)' 라벨 등재",
    "⑦타 모드 — FR 국면-조건부 모듈 배합에 계약 sleeve 후보 제공"),
  frontier_update = paste0("FQ-191 status=h3_not_capital_routed_overlay_20260809 · claim=complete · ", newid, " 신규 등재"),
  live_trigger = paste0("자본 경로 재개 조건: ①국면 ON 월이 누적돼 oos_retention 이 0.5 이상으로 회복될 때 ",
    "②PORT_t 갭 0.746 을 메우는 구성(비용·벤치 채널 분해 결과에 따라) ③2026 오염 수리 후 포함판에서 값이 오를 때. ",
    "★H3 는 **자본 경로 한정 negative** 이며 재료 자체의 기각이 아니다 — 국면-조건부 초과분(FQ-138 연 +26.09%)은 유효하다."),
  layer = "①재료 (비-return) + ⑨자본",
  evidence_refs = c("stage_artifacts/FQ191/validation.json", "stage_artifacts/FQ191/p1_rule.csv",
                    "stage_artifacts/FQ138/validation.json"))
say("=== FQ-191 종결 ===")
