## FQ-198 판정 수집 — 정본 writer 경유 (frontier_queue_io.R)
ROOT <- Sys.getenv("QM_ROOT","C:/Users/99922/OneDrive/Quant_Module_Moltbot"); setwd(ROOT)
source("02_Infrastructure/ops/frontier_queue_io.R")
suppressPackageStartupMessages(library(jsonlite))
AV <- fromJSON("stage_artifacts/WT_D20260809_005/alpha_validation.json", simplifyVector=FALSE)

Q <- read_frontier_queue()
ids <- vapply(Q$entries, function(e) as.character(e$id)[1], character(1))
i <- which(ids == "FQ-198"); stopifnot(length(i)==1L)
cat(sprintf("[fq] 대상 FQ-198 (index %d) · 원장 항목 %d\n", i, length(ids)))

e <- Q$entries[[i]]
e$owner  <- "[COMPLETE] alpha-research WT-D20260809_005 (2026-08-09) — 판정 수집. result_ref 참조."
e$status <- "materials_are_not_new_inventory_corrected_20260809"
e$result <- paste0(
 "측정 완료 2026-08-09 (metric_type=canonical_screen_diag · 재료 자격 판정, 자본 주장 아님 · build_hash 20260809203741_8c9befe0). ",
 "★결론: 재빌드로 '해금'됐다던 4종 중 **실제 신규 재료는 0종**. 본 라운드 산출은 알파가 아니라 **재료 인벤토리의 정정**이다.\n",
 "■ 공통 기전(실측): consensus 원천이 **일간**(sue 고유 Date 6,140개 · 인접 간격 중앙 1일)인데 sue/esbr 은 그 위의 **계단함수**",
 "(인접 영업일 값 변화율 sue 0.015396 · esbr 0.015435). 빌더 compute_consensus.R 의 '최근 N개 관측' 집계가 의도된 N 분기/개월이 아니라 ",
 "**N 영업일**로 실행되어 이동평균이 항등변환이 되고 차분이 항등 0 이 된다. ",
 "⚠자기 정정: 최초 가설('이력 깊이 1')은 P0d 실측으로 기각됐다 — sue 이력 깊이 중앙 536 · 깊이>=2 비율 1.0000.\n",
 "■ 팩터별 처분. (1) **C10_SUE_Persistence ≡ C01_SUE** · (2) **C13_Revision_Breadth_3m ≡ C04_ESBR** — 표본월 8건",
 "(2003-06~2026-07) 전건 완전동일 비율 1.0000 · **최대절대차 0.000e+00** · spearman/pearson **+1.000000**(z·raw 양쪽), ",
 "커버리지도 바이트 동일(299월/216,073 종목-월/월중앙 757 · 302월/328,778/1,152). 기전 = '최근 4(3)개 관측 전부 동일' 티커 비율 **1.000000**. ",
 "(3) **C15_Forecast_Error_Trend 는 factor_db 에 존재하지 않는다** — sue[1]-sue[2] = 인접 2영업일 차분이라 **정확히 0 인 비율 1.000000** · ",
 "sd 0.000000e+00 → 분산 0 으로 하류 탈락. 커넥터 전량 로드 4개 표본월(2005/2012/2019/2026)에서 C-계열 16종 중 부재. ",
 "★**FQ-163 verdict 의 'C15 300개월 실림' 진술은 성립하지 않는다 — 원장 정정 필요**.\n",
 "■ (4) **C18_Earnings_CAR_3d = 유일한 측정 대상이었으나 REPACKAGED_NOT_MATERIAL**. 증분 FMB NW(lag3) t = **-2.551** ",
 "(n=283월 2003-01~2026-07 · 월중앙 218종 · mean -0.002485 · SE_NW 0.000974 · placebo p 0.0000 · VIF 중앙 1.02 · incumbent 최대|rho| 0.047). ",
 "|t| 는 문턱 2.0 과 Bonferroni 2.50 을 넘지만 **두 가지가 자격을 부순다**: ",
 "①**사전 부호 반증** — 사전 지정 +(PEAD underreaction) vs 관측 −(단독 rank-IC -0.0246 t -3.12). ",
 "②**사전등록 자격 전제조건 미통과**('모멘텀/반전 배제 미통과 시 t 무관 자격 불인정'). ",
 "★C18 은 이벤트-CAR 가 아니다: 빌더의 '발표일 프록시'가 sue 를 매 영업일 관측하는 원천에서 Date[1] 을 뽑아 **월당 고유 ann_date 가 5~6개뿐**",
 "(같은 달 종목 287~382개 대상) · sig_d-ann_date 중앙 3~7일 ⇒ 전 종목 공통 **월말 고정 ~6일 창**(나머지 ~30% 는 sue 갱신 끊긴 종목의 최대 335~397일 전 낡은 창). ",
 "trail6d(월말 6일 시장조정 수익)와 월별 spearman **+0.674**(5%~95% 0.232~0.942). ",
 "**결정적 통제**: trail6d 추가 시 |t| 2.551 → **1.486**(유지율 0.58) · 전체 통제 1.554(0.61) — 문턱 아래 붕괴. lag1 유지율 -0.15 도 단기 반전과 정합. ",
 "⚠정직 한정: +1M 만 통제하면 |t| 가 3.502 로 **커진다**(1M 반전 직교화로 6일 성분이 선명해지는 것) — 한 스펙만 골라 보면 정반대 결론이 나오므로 5개 스펙 전부 보고.\n",
 "■ exploratory 3종(스텝-보정판, **사전등록 원안 아님 — P0 중 발견**): C10s t -0.456 · C13s +0.737 · C15s -0.909, ",
 "placebo p 0.665/0.425/0.375. 셋 다 incumbent 와 **구별은 된다**(최대|평균rho| 0.545/0.572/0.623 < 0.9) ⇒ 재탕이 아니라 **진짜 null**. ",
 "단 검정력 라벨 전건 INCONCLUSIVE_BAR_RESTATES_T (implied_t 2.44~2.58) — '효과 없음'으로 읽지 말 것. ",
 "외부 기준(top-25 EW 바스켓쌍 sd 0.0394) 필요 연효과 n=283 에서 2.29~5.10%. ",
 "부수: C13s 는 **단독** rank-IC +0.0184 (t +3.41 · ICIR 0.150) 로 신호력은 있으나 C04 위 증분이 없다.\n",
 "■ 전이(진단, 자본 주장 아님): C18 canonical top-25 cap-w PORT_t **-1.040** · EW-유니버스 **-2.335** · post-2017(EW) -1.084 · ",
 "잔차판 cap-w -0.849 / EW -1.845 · net SR -0.210 · 회전율 **16.99/yr**(Implementation Discipline 11.0 초과). ",
 "사전등록 부호(+)로 상위 25 를 잡았으므로 음의 PORT_t 는 음의 계수의 거울상 — 부호를 뒤집어도 |cap-w| 1.04 << 2.95.\n",
 "■ 적대검증 실측 3건: ①PIT parity PASS — 원천 재계산 C01 ↔ 커넥터 C01 월별 spearman 중앙 0.999993 · 최소 0.999986 · 11/11 월 양의 부호",
 "(내 원천 처리 = 빌더, 방향정렬 미반전). ②C18 표본 자기선택 **기각** — 보유군-미보유군 익월 수익차 t +0.22(298월), incumbent 계수 안정. ",
 "단 표본은 대형·고서프라이즈 편중(C01 평균 0.221 vs 0.041 · log Size 28.13 vs 26.88)이라 일반화 범위 좁음. ",
 "③AX-001 v2: C18 crisis(bm<-10%, n=13) IC -0.1445 로 위기에 **더 음** — 방어형 아님.")

e$next_action <- paste0(
 "[프론티어 잔존 4 — 전부 조건-안, 재료 교체 아님] ",
 "▶NP-1 **C18 을 제대로 만든다**: 진짜 발표일 원천(DART 정기보고서 접수일 = 이미 저장소에 있는 재료)으로 ann_date 를 교체하면 ",
 "C18 은 처음으로 진짜 이벤트-CAR 가 된다. 현 정의가 반전 대용품이라는 것은 **이벤트 축이 미측정이라는 뜻이지 negative 가 아니다**. ",
 "발생률·창 순도부터 사전 확인. ",
 "▶NP-2 **C13s 단독 신호력의 소비면 순회**: 증분은 없으나 단독 rank-IC t +3.41 · ICIR 0.150 — 랭킹이 아닌 **유니버스 필터**로 소비 가능한지 ",
 "(MAX5 전례: 랭킹 사망·필터 생존 / [[project-consumption-path-changes-verdict-20260802]]). 헌법 4호 소비면 7종 순회 대상. ",
 "▶NP-3 **스텝 담체 수리의 다른 판본**: 본 라운드의 '스텝 압축'은 여러 수리 중 하나였다. 미검 대안 = 분기 리샘플 · 달력 lag(발표 시차 반영) · ",
 "이벤트 정렬. 셋 다 담체가 달라 서로 다른 팩터가 된다. 단 **독립 사전등록 라운드**여야 한다(본 라운드 exploratory 는 자유도 소진). ",
 "▶NP-4 **잔여 C-계열 미시험분 census**: 커넥터가 실제 내주는 C-계열은 16종인데 본 라운드가 판정한 것은 4종뿐. ",
 "C05/C06/C07/C08/C09/C11/C12/C16/C19 의 **정체 검사(incumbent 와 비트-동일인가)를 먼저** 돌릴 것 — 본 라운드가 세운 '이름이 아니라 값으로 재라'가 ",
 "그 9종에 그대로 적용된다. 비용 거의 0(P0c 스크립트 재사용).")

e$revival_conditions <- list(
 "①진짜 발표일 원천(DART 접수일) 배선 시 C18 재도전 — 현 negative 는 **오구성 프록시에 대한 것**이지 이벤트-CAR 기전에 대한 판결이 아니다",
 "②빌더가 스텝 담체로 수리되면 C10/C13/C15 가 처음으로 서로 다른 팩터가 된다 — 그때 재측정(본 라운드 exploratory 는 미리보기였고 null 이었으나 검정력 미달)",
 "③C13s 가 소비면 순회(NP-2)에서 필터로 양성이면 단독 신호력 lane 재개")

e$result_ref <- "stage_artifacts/WT_D20260809_005/ : p0_precheck · p0b_c15_diag · p0c_identity · p0d_depth · p0e_mechanism · p1_increment · p2_canonical · p3_adversarial · p3b_c18_identity · alpha_validation.json · chart_fq198_summary.png | qepm/mailbox/worktask/WT-D20260809_005/ : alpha_package.json · alpha_hypothesis.json(rev2) · challenge_note.md"
e$handoff_to_qlead <- list(
 "①FQ-163 verdict 의 'C15 300개월 실림' 진술 정정 (본 라운드 실측이 반증)",
 "②compute_consensus.R C10/C13 중복 배출 처분 — .CONSENSUS_DEPRECATED 편입(C14/C17 선례) 또는 스텝 담체 수리",
 "③C18 발표일 프록시 재설계 — 현 정의로는 이벤트 팩터가 아님(월말 고정 창)",
 "④emission_guard 는 '전 구간 0행'은 잡지만 '**incumbent 와 비트-동일한 배출**'은 못 잡는다 — 정체 검사 축 추가 제안")

Q$entries[[i]] <- e
write_frontier_queue(Q)

## 재읽기 검증 (선언에서 파생 금지)
Q2 <- read_frontier_queue()
ids2 <- vapply(Q2$entries, function(x) as.character(x$id)[1], character(1))
j <- which(ids2=="FQ-198")
cat(sprintf("[fq] 재읽기: 항목 %d · FQ-198 index %d · status=%s · result %d자 · next_action %d자 · revival %d건\n",
  length(ids2), j, Q2$entries[[j]]$status, nchar(Q2$entries[[j]]$result),
  nchar(Q2$entries[[j]]$next_action), length(Q2$entries[[j]]$revival_conditions)))
stopifnot(Q2$entries[[j]]$status == e$status, nchar(Q2$entries[[j]]$result) > 500)
cat("[fq] OK\n")
