## FQ-165 판정 큐 반영 + NP-3 신규 등재 + owner 해제
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
say <- function(fmt,...) cat(sprintf(paste0("[165] ",fmt,"\n"),...))

i <- which(sapply(E, function(x) isTRUE(identical(x$id, "FQ-165"))))[1]
say("FQ-165 인덱스: %d", i)
E[[i]]$status <- "measured_config_scoped_negative"
E[[i]]$owner <- "완료 — Q-Lead session cee0bdd0 (2026-08-09)"
E[[i]]$verdict_20260809 <- paste(
  "D4_NEGATIVE (사전등록 3형태 전건): blend w0.30 ΔIR −0.0975(t −1.383) · filter D1제외 −0.0079(t −0.327) ·",
  "carve k4 −0.1021(t −1.939). 기준선 production_parity_verified=TRUE(IR 1.4073, incumbent 1.416 tol 내), 269개월.",
  "★기전은 'M26 무용'이 아니라 **슬롯 대체 비용**: 정보 0(순열)인데도 개입 규모에 비례해 ΔIR 음 —",
  "**base 대비 ΔIR 은 정보의 척도가 아니다**. FMB 증분 기울기는 상위 영역에서 오히려 커진다",
  "(전체 +1.502%/yr/sd → top-20 +3.985). 북 top-20 에서 한 종목 밀어내는 비용 연 −13.7%, M26 회수 +1.8%p 뿐.",
  "★검정력: ΔIR≥0.05 게이트(연 +0.95%)가 paired 검출 바닥(연 +2.81%, 외부기준 placebo sd)의 1/3 —",
  "'게이트 통과'와 '통계적 확립'은 다른 사건. 관측 전건 바닥 미만 = 검출 못함(효과 부재 아님).",
  "★프레이밍 한정: 잰 것은 인컴번트 sleeve 안 랭킹 재구성(②)뿐. 독립 sleeve 편입(①)은 standalone HARD",
  "(PORT_t 1.544·oos 0.123)로 닫혀 있어 미측정 — 'M26 은 북에 기여하지 않는다' 전칭 금지.",
  "★판정은 tophi φ=3 config 조건부(신규 tilt 가 직전 비중과 75% 블렌드) — 구조 판결 아님.",
  "★착수 전 검거: M26 lag_rule=same-day 라 naive join 이면 IC t 3.34배 부풀림(offset0 8.758 vs offset1 2.620) —",
  "채택 정렬은 signal+1, 부모 WT-002 창과 일치.")
E[[i]]$next_probes_20260809 <- c(
  "NP-1 M26 을 슬롯 대체 아닌 유니버스 축소 필터로(F_B 유일 무해 + placebo 12draw 중 11 우수). 착수 전 required_effect 재산출.",
  "NP-2 FMB 증분 기울기(+1.5~4.0%/yr/sd)를 대체 비용 없이 수확하는 소비면 — 오버레이 집계신호/monitoring 경보/신규편입 tie-break.",
  "NP-4 독립 sleeve 경로 — standalone HARD 로 차단. 부활 조건 = stage_artifacts/FQ165_m26_book_marginal/next_probes.json::revival_conditions")

## NP-3 → 신규 FQ (북 전체에 걸리는 축이라 별도 등재)
ids <- suppressWarnings(as.integer(sub("^FQ-", "", sapply(E, function(x) if (is.null(x$id)) NA_character_ else x$id))))
nid <- sprintf("FQ-%03d", max(ids, na.rm=TRUE) + 1L)
E[[length(E)+1]] <- list(
  id = nid,
  lane = "measurement_trust",
  title = "base score_eff 의 offset+1 IC 우위 — 타이밍 여유인가 패널 스탬프 아티팩트인가 (vintage-swap 판별)",
  hypothesis = paste(
    "FQ-165 부수 실측: 현행 북 base score_eff 의 예측 IC 가 offset0 t 4.513 < **offset+1 t 5.324** 로",
    "한 달 늦춘 쪽이 더 높다. 현행 북은 offset0 으로 운용 중.",
    "두 해석이 갈린다 — (a) 진짜 타이밍 여유(신호가 느리게 반영) (b) 패널 Date 스탬프 아티팩트.",
    "★(b)의 선례가 이 저장소에 실재한다: 저장 패널 동월 vintage 가 PORT_t 를 2.08배 부풀린 07-14 사고 —",
    "그때 검거 도구가 정확히 **vintage-swap 통제**였다."),
  ev_rationale = "사실이면 북 전체에 걸리는 축(모든 admitted 신호의 운용 타이밍). 아티팩트면 측정 신뢰 결함.",
  wall_check = "★확립 아님 — 배포 시점 변경 주장 금지. vintage-swap 통제 통과 전에는 어느 방향으로도 소비 금지.",
  data_gate = "없음 (production 코드 경로 재실행 + 저장 패널 대조)",
  status = "open",
  owner = "미배정",
  next_action = paste(
    "①production 코드 경로(T-1 convention)에서 score_eff 를 재산출해 저장 패널과 Date 스탬프 대조",
    "②vintage-swap: 패널 기준 offset0/+1 IC 를 production 실산출 기준으로 재측정 — 우위가 유지되면 (a), 소멸하면 (b)",
    "③(a) 확정 시에도 배포 변경은 도훈 결정 — 측정까지만."),
  parent = "FQ-165 NP-3 (2026-08-09)",
  registered = "2026-08-09",
  registered_by = "Q-Lead session cee0bdd0"
)
say("%s 등재 (NP-3 승격)", nid)

q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
say("완료")
