## 적대검증 우선순위 8 — F4 킬스위치 비대칭을 **공개 질문으로 등재**(규약 신설 아님)
## ★n=1 로 규약을 만들지 않는다(2026-08-09 자체 규약). 증거와 함께 질문만 세운다.
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
if (any(sapply(E, function(x) isTRUE(identical(x$id, "FQ-172"))))) {
  cat("[ks] FQ-172 이미 존재 — 중단\n"); quit(status=0)
}

E[[length(E)+1]] <- list(
  id = "FQ-172",
  lane = "governance_methodology",
  title = "사전 킬스위치도 검정력 라벨을 받아야 하는가 — 라운드 내 증거기준 비대칭",
  hypothesis = paste(
    "WT-D20260808_001 적대검증이 라운드 범위의 절반을 종료시킨 결정을 지적했다.",
    "소비면 (a) 타이브레이커는 사전등록 F4 킬스위치로 **측정 전** 기각됐는데, 그 근거 통계가",
    "D03 -3.283%/yr t **-1.276** · Q01 -3.257%/yr t **-1.518** 이고 관측/필요 비가 **0.47 / 0.57** —",
    "검출 가능 효과의 **절반 크기**다.",
    "★같은 라운드가 |t| 1.4 셀들에는 'INCONCLUSIVE_UNDERPOWERED — 효과 없음 단정 금지' 를 걸었다.",
    "즉 **사후 판정은 검정력 규율을 받는데 사전 킬스위치는 안 받는다**. 이것이 정당한 비대칭인가?"),
  ev_rationale = paste(
    "범위 손실이 크다 — 소비면 하나가 영구 종료됐고, 적대검증 4개 렌즈 **전원이 이 비대칭을 주장 B에서만 찾고",
    "F4 에는 적용하지 않았다**(종합자 단독 적발). 같은 형태가 다른 라운드에도 있으면 프론티어가 조용히 좁아진다."),
  positions = list(
    for_power_label = "킬스위치가 |t| 1.28 로 '효과 없음' 판단을 내리는 것은, 같은 라운드가 그 정도 증거를 불충분하다고 부르는 것과 모순이다.",
    against_reopening = "사전등록의 가치는 데이터를 보기 전에 구속된다는 것이다. 사후에 검정력을 이유로 재개방하면 구속력이 사라진다 — 그게 바로 사후 선택이다.",
    candidate_resolution = paste(
      "재개방이 아니라 **등록 시점 사양**으로 해결: 킬스위치를 '조건 X 면 기각' 이 아니라",
      "'조건 X 이고 **그 검정이 X 를 검출할 검정력이 있었으면** 기각' 으로 쓴다.",
      "사후 규칙 변경이 아니라 사전 규칙을 제대로 쓰는 문제로 환원된다.",
      "2026-08-09 확립 규약(사전등록 **전에** required_effect 계산)과 같은 방향이다.")
  ),
  wall_check = "규약 문제이며 자본 주장 아님. 알파를 만들지 않는다.",
  data_gate = "없음",
  status = "open_question",
  owner = "미배정",
  evidence_threshold = paste(
    "★규약으로 승격하려면 **독립 사례 2건 이상**이 필요하다. 현재 명확한 것은 WT-D20260808_001 F4 **1건**.",
    "WT-D20260808_003 도 F4 킬스위치가 발화했으나 그쪽 문턱은 t 통계가 아니라 부호 조건(밴드 기울기<=0)이라 같은 형태가 아니다.",
    "⇒ 지금 규약을 만들지 않는다(2026-08-09 자체 규약: 관측 1건으로 규칙 신설 금지)."),
  next_action = c(
    "①과거 라운드의 사전 킬스위치 발화 사례를 census 해 근거 통계의 |t| 분포를 본다 — 저검정력 발화가 계통인지 1건인지.",
    "②2건 이상이면 candidate_resolution(등록 시점 검정력 조건 내장)을 close_round/사전등록 템플릿에 반영할지 판단.",
    "③1건에 그치면 본 항목은 열어둔 채 유지 — 다음 발화 시 자동 재점화."),
  parent = "WT-D20260808_001 적대검증 종합 §5-5 / 우선순위 8",
  registered = "2026-08-09",
  registered_by = "Q-Lead session cee0bdd0"
)

q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[ks] FQ-172 등재 완료 (공개 질문 — 규약 신설 아님, owner 미배정)\n")
