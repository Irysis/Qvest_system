## 병렬 세션 충돌 방지 — 내가 착수한 것을 큐에 **잠근다** (도훈 지시 2026-08-09)
## ★내가 방금 저지른 실수 교정: FQ-165 를 배분해놓고 owner 를 안 적어 큐에 UNCLAIMED 로 남아 있었다.
##   "큐 owner=미배정 불신" 규약을 내가 만들어놓고 그 원인을 내가 생산했다.
suppressPackageStartupMessages({ library(jsonlite) })
setwd(Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"))
p <- "06_Registry/alpha_frontier_queue.json"; q <- fromJSON(p, simplifyVector=FALSE)
E <- q$entries
SESS <- "Q-Lead session cee0bdd0 (2026-08-09)"

claim <- function(E, id, note) {
  i <- which(sapply(E, function(x) isTRUE(identical(x$id, id))))[1]
  if (is.na(i)) { cat(sprintf("[claim] %s 미발견\n", id)); return(E) }
  prev <- if (is.null(E[[i]]$owner)) "?" else E[[i]]$owner
  E[[i]]$owner <- SESS
  E[[i]]$in_flight_since <- "2026-08-09"
  E[[i]]$in_flight_note <- note
  cat(sprintf("[claim] %s : %s -> %s\n", id, substr(prev,1,40), SESS))
  E
}

E <- claim(E, "FQ-165", paste(
  "서브에이전트 실행 중(alpha-research). 소관 = M26 을 현행 PG2 북에 **더했을 때의 book-marginal ΔIR**.",
  "형태 분류·사다리 분해는 소관 아님(FQ-166 이 이미 완료). governor admit 금지 — 측정까지만.",
  "기준선 규약 부과: 05_Production 코드 경로 파생만 권위 · production_parity_verified 라벨 · ir_convention=net_active_recon_v1."))

## NP-A 는 큐 항목이 아니라 WT-003 next_probe 라 다른 세션이 못 본다 → 신규 등재로 가시화
exists_npa <- any(sapply(E, function(x) isTRUE(identical(x$id, "FQ-171"))))
if (!exists_npa) {
  E[[length(E)+1]] <- list(
    id = "FQ-171",
    lane = "shape_census",
    title = "현행 book 7종의 분위 프로파일 형태 census (NP-A)",
    hypothesis = paste(
      "WT-D20260809_003(FQ-166)이 5재료를 3형태로 분류했다(MONOTONE_TOP / HUMP / 상단-역전형).",
      "그 표본에는 **현행 자본이 배정된 신호가 없다**. C01_SUE·C02_EPS_Chg_1m·C04_ESBR·C06_TP_Gap·",
      "Q07_Earnings_Stability·M08_Residual_Mom·Q25_Ohlson_O 의 형태를 재면,",
      "혹(HUMP)이 **탈락 재료의 특징인지 현행 북에도 있는 성질인지**가 갈린다."),
    ev_rationale = paste(
      "book 다수(>=4/7)가 HUMP 면 top-N 선별의 구조적 불리가 **현행 북에 직접 적용**되고 ④construction 귀속이 강해진다.",
      "다수가 MONOTONE 이면 HUMP 는 탈락 재료의 특징이고 벽 일반화는 금지된다 — 발견 사정거리가 크게 좁아진다."),
    wall_check = "형태 census 이며 자본 주장 아님. FQ-166 과 분위 해상도·창이 다르면 수치를 같은 자로 읽지 말 것(질적 형태 대비만).",
    data_gate = "없음",
    status = "in_flight",
    owner = SESS,
    in_flight_since = "2026-08-09",
    in_flight_note = "서브에이전트 실행 중. FQ-166 과 소관 분리 완료(그쪽=5재료 동일프레임+사다리, 이쪽=book 7종 형태).",
    parent = "WT-D20260808_003 next_probe NP-A",
    registered = "2026-08-09",
    registered_by = SESS
  )
  cat("[claim] FQ-171 신규 등재 (NP-A 가시화)\n")
}

q$entries <- E
write(toJSON(q, auto_unbox=TRUE, pretty=TRUE, null="null"), p)
cat("[claim] 완료\n")
