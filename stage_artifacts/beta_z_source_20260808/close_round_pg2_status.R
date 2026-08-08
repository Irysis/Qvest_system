source(file.path(Sys.getenv("QM_ROOT", "C:/Users/99922/OneDrive/Quant_Module_Moltbot"),
                 "02_Infrastructure/contracts/close_round.R"))

close_round(
  round_id = "R-PG2STATUS-20260808",
  verdict_type = "incumbent_confirmed",

  mechanism_diagnosis = paste0(
    "도훈 요청으로 PG2 현황을 실측 보고했다. 정체성 정합 확인(admitted_ids == current_pg2_official_name, ",
    "미러 sha1 36c5eb22 일치), 원장 271개월 CAGR 44.23%·SR 1.8501·MDD 23.29%·Calmar 1.899, ",
    "최신 배포 2026-08-01 CRISIS 노출 0.30/현금 0.70, 하드 제약 전 항목 충족. ",
    "오늘 수리분(invested_eff·beta_R05_panel·beta_matches_ret_net 3열, z 원천 live 통일)이 원장에 반영됐고 ",
    "2026-08 행이 배포 실측과 일치(β 0.30)함을 확인했다. ",
    "★보고 과정에서 내 상태 스크립트가 CASH 행(0.70)을 종목으로 세어 'max w 0.70 → 제약 위반'을 오탐했다. ",
    "기전 2중: ① CASH 행 미제외 ② bound 0.20 을 **노출 정규화 전** 원장부 값에 적용. ",
    "②는 이번엔 오탐이었지만 **반대 방향(누락)도 같은 뿌리**다 — 배포 비중 = 전략비중 × invested 이므로 ",
    "노출이 낮은 달(CRISIS)엔 제약이 헐거워지고, 노출이 1에 가까운 달엔 정상 판정된다. ",
    "즉 이 검사기는 **국면에 따라 판별력이 달라지는 상태**였다. 수리 후 재실행으로 정상 판정 확인."),

  next_probes = c(
    "같은 bound-적용 오류(노출 정규화 전/후 혼동)가 배포 체인의 다른 검사 지점에도 있는지 감사 — deployed_holdings_check.py(08-01 신설)와 judge Gate 계열이 CASH 행과 invested 스케일을 어떻게 다루는지 확인. 노출이 낮은 달에만 헐거워지는 검사는 CRISIS 구간에서 정확히 무력화된다",
    "제약 검증의 국면 의존성 실측 — 과거 배포 월 전체에 대해 '원장부 기준'과 '노출 정규화 기준' 판정을 대조해 두 기준이 갈리는 달이 몇 개월인지, 그 달들이 어느 국면에 몰려 있는지 산출(오탐/누락 양방향)",
    "PG2 SR 1.8501 vs 목표 2.5 갭의 계층 귀속 갱신 — layer_bottleneck_map 의 해당 행을 오늘 실측(MDD 23.29% 충족·CAGR 44.23% 충족·SR만 미달)으로 재기입해 병목이 '수익'이 아니라 '변동성 대비 효율'임을 명시"),

  consumer_surfaces = c(
    "pg2_status_report.R (상태 보고 도구 — CASH 제외 + 노출 정규화 적용, 수리 완료)",
    "deployed_holdings_check.py (하드제약 검사기 — 동일 오류 여부 미확인, next_probe ①)",
    "live_book_series.csv (β 3열 반영 확인 · 앵커 구성 rds 269/manifest 1/panel 1)",
    "05_Production 2-4 슬롯 배포 비중 (20종목·invested 0.30·max w 정규화 0.1739)",
    "layer_bottleneck_map.md (SR 갭 귀속 갱신 대상 — next_probe ③)",
    "qepm/mailbox/governor/book_state.json (incumbent_book_ir 1.416 · 오늘 수리로 무변경)"),

  frontier_update = paste0(
    "프론티어 큐 소비는 도훈 지시로 **중지**(다른 세션 진행 중) — 본 세션은 큐 항목을 착수하지 않는다. ",
    "본 라운드가 남긴 미검 축은 알파 발굴이 아니라 **제약 검증의 국면 의존성**이며, ",
    "이는 측정 신뢰 범주라 큐와 독립적으로 소비 가능."),

  live_trigger = paste0(
    "다음 중 하나가 발화하면 제약 검증 감사를 즉시 재개한다: ",
    "① 배포 노출이 낮은 달(invested < 0.5)에 신규 비중이 산출됨 — 그 달이 정확히 검사가 헐거워지는 구간이다 ",
    "② deployed_holdings_check.py 가 예약 경로에 배선됨(현재 미배선, project-gate-cd-not-on-scheduled-path) — 배선되는 순간 이 오류가 실효 검사로 승격되므로 선행 수리 필요 ",
    "③ 종목수/비중 제약이 변경됨(현행 25종·0.20) — 두 기준 차이가 판정을 가르는 경계가 이동 ",
    "④ 다른 세션의 프론티어 라운드가 PG2 book-marginal 편입을 상신 — 그때 제약 판정 기준이 실제 게이트가 된다")
)
