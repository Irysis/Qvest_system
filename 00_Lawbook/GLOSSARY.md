# 1계층 리서치 용어집 (Qvest v10.01)

**기준 시점**: 2026-10-15 09시. 등록부 `06_Registry/research_programs.json` 을 기준으로 했다 — 값이 다르면 등록부와 코드가 정본이다.
**읽는 법**: 텔레그램 본문에는 셀 코드가 나오지 않는다(발송 규칙 ④ — 사람이 읽는 이름만). 코드는 세션 응답 · `ROUND_REPORT.md` · 로그에 나온다.
**용어 규칙**: 업계 표준 기술 용어를 쓴다(도훈 10-15). 프로젝트 정본 어휘(사전등록 · 행동 카드 · 보는 창/시험 창 · τ_D 등)는 헌법 · 등록부 정의를 따른다.

---

## 0. 표준 용어 — 세션 · 코드 · 로그 공통

| 표준 용어 | 뜻(이 프로젝트에서) | 쓰지 않는 말 |
|---|---|---|
| 셀(cell) | 라운드 안의 측정 단위 1개 = 사양 1개(`P0R01_E2_C4`) | — (등록부 · 코드의 '칸'과 같은 뜻) |
| 사전등록(pre-registration) · 재핀(re-pin) | 측정 전 가설 · 반증 조건 · 선택 규칙과 사양 · 운영 파일의 md5 핀을 고정 / 측정 전 핀을 새 판으로 갱신(supersede 기록) | 재고정 |
| 센티널 파일(sentinel) | 파이프라인 단계 완료를 알리는 빈 파일(`_lib/night_state/<단계>.done`) | 표식 파일 |
| 샤드(shard) · 샤딩 병렬 | 셀 목록을 K 개로 교차 분할해 K 프로세스가 동시에 평가(`--shard=i/K`) | 몫 |
| 캐시 워밍(cache warming) · 프리페치(prefetch) | 본 작업 전에 캐시를 미리 채움 | 데우기 · 예열 |
| 사전 컴파일(precompile) | Rcpp C++ 소스를 빌드 캐시(`.cache/rcpp_build`)에 한 번 컴파일 — 병렬 워커는 재컴파일 없이 로드 | 캐시 예열 |
| 파티션 캐시(partition cache) | 팩터×월 단위 필터 · 프로젝션 결과의 materialized 사본(`factor_db_partcache/v1`) | 조각 캐시 |
| 무효화 키(invalidation key) | 캐시 엔트리가 유효한지 판정하는 키(월 파일명 · 크기 · mtime · 컬럼 목록) | 서명 |
| atomic rename | 임시 파일에 쓰고 이름을 바꿔 교체(병렬 쓰기 안전) | 이름 바꾸기 쓰기 |
| 뮤테이션 테스트(mutation test) | 코드를 일부러 망가뜨린 변이체를 테스트가 잡는지 확인 | 돌연변이 |
| 양성 대조(positive control) | 효과가 있어야 하는 입력에서 계기가 실제로 반응하는지 확인 | — |
| stale index | 행이 바뀐 뒤에도 남은 data.table 자동 인덱스 속성 | 낡은 색인 |
| full scan · binary search | 전 행 비교 · 정렬된 키에서 이분 탐색 | 벡터 스캔 · 이진 탐색 |
| 3-way 병렬 | 동시 워커 3개(`xargs -P 3`) | 3병렬 |

---

## 1. 한 장 요약도

```
[재료]  논문 수집 → 라우터 v5(엔진 분류)              ▸ paper_router · Sonnet/high
        → P1·P2·P3 재료 큐                            ▸ program_paper_sync.R · R(결정론)
        → 메커니즘 지도                               ▸ paper_atlas · Opus/xhigh(켤 때만)
   │
[충실구현 · 논문 1편 = tick 1회]
        요청 발행(큐 상단 1편 · 고르지 않음)          ▸ next_replication.R · R
        → 청정 재구현 engine.R + FIDELITY.json        ▸ replication 레인 · Opus/max
        → 사전검사(신고 구조)                         ▸ rf_preaudit.py · 기계
        → 측정 → 권위 등급 v3                         ▸ run_paper_replication · R 계약
        → 충실도 감사 6축 병렬 → 병합                 ▸ 판독 3축 Opus/xhigh · 대조 3축 Sonnet/high · 병합 R
        → 검증기(행동 카드 · 재료 큐 · 보고 1통)      ▸ rf_replication_verify.R · R
        (세션에서 돌릴 때 /alpha-search               ▸ 세션 모델 상속 · high)
   │ A 미달 → 재료 큐                       A → [A 경로]
[프로그램 라운드 · P0 → P1·P2·P3 → P4]                 ▸ 오케스트레이션 = 세션 Q · claude-opus-5-5 · max(세션 설정)
   ① 사전등록 register.R → prereg.json + 등록부      ▸ R · 초안 교차 점검 = 범용 에이전트(세션 상속)
      (처방 루프 라운드만) 분석가 → 처방 담당        ▸ rx_lane.sh · Opus/max · 읽기 전용 청정 레인
   ② 측정 measure*.sh → rf_cell_worker.R             ▸ run_paper_replication · R 계약(LLM 없음)
   ③ 셀 평가 evaluate.R --cells-only(eval_parallel.sh 샤딩)  ▸ round_kit::rk_eval_cell · R 계약
      축 감사 · 보는 창 진단 패킷 · 전기간 행동 카드 · 시험 창
   ④ 판정 = evaluate.R 종합(사전등록 규칙 기계 적용) ▸ R → evaluation.json
      (처방 루프 라운드만) 리뷰어 — 기전 판독 · 다음 수 ▸ rx_lane.sh · Opus/max
   ⑤ 보고 close_*.R → ROUND_REPORT.md + 텔레그램 1통 ▸ R(prep_send) + Q
   ⑥ 교훈 L-code(기전이 특정될 때 · τ_D 이전 수치만) ▸ R 검사
   │
[A 경로] A 자격 관문 → judge_request.eligible.json   ▸ rf_a_eligibility · R
        → Judge(PIT C1~C15 검증)                      ▸ Opus/max · 트리거가 있을 때만
        → BOOK 등록                                   ▸ register_book_entry · 도훈 confirm
```

- **노력 단계(effort)**: 최상위는 `max`. 'ultracode'는 세션 모드(워크플로 오케스트레이션)이지 에이전트별 노력 단계가 아니다.
- **역할별 모델 배정(D12)**: 판단(판독 · 분석 · 처방 · 리뷰 · 감사 · Judge) = Opus, 명확한 사양 실행(분류 · 요약 · 코딩) = Sonnet. Fable 미사용.
- **모델 드리프트**: 레인 설정은 별칭 `opus` — CLI 2.1.261 에서 `claude-opus-5` 로 해석된다(설정 메모 실측). 세션 Q 는 `claude-opus-5-5`. `sonnet` 의 실제 ID 는 (미확인).
- **예약 작업**: 10-15 조회 시 `Qvest_*` 12종 전부 Disabled — 무인 레인은 세션이 수동 실행할 때만 돈다.

---

## 2. 코드 사전

### a) 프로그램 — `P<n>_<이름>`

| 코드 | 이름 | 단계 · 상태(등록부) | 하는 일 | 담당 · 모델/노력 | 정본 파일 |
|---|---|---|---|---|---|
| `P0_FRONTIER` | 실현 가능성 지도 | 1 · `active` | 문헌 표준 단순 구성요소 × 기존 수익 엔진이 목표 영역에 닿는지 먼저 측정. 닿는 셀이 0 이면 탐색을 늘리지 않고 도훈 안건으로 | Q 오케스트레이션 · R 계약(LLM 없음) | `06_Registry/research_programs.json` |
| `P1_RETURN` | 수익 엔진 | 2 · `active` | 상승 포착과 β-통제 알파를 내는 횡단면 선택 엔진 확보 | Q · R | 〃 |
| `P2_DEFENSE` | 방어 엔진 | 2 · `active` | 위기 하락 포착을 줄이는 장치(시변 노출 · 방어적 보유)를 여러 엔진에 걸쳐 검증 | Q · R(P2R01 만 처방 루프 에이전트) | 〃 |
| `P3_CONSTRUCTION` | 구성 | 2 · `active` · 재료 1편(1810.08384) | 비중 · 집중 · 회전 · 용량을 '낙폭 제약 아래 복리'로 결정 | Q · R | 〃 |
| `P4_ASSEMBLY` | 조립 · 처방 루프 | 3 · `blocked`(P0 대기) | P0 골격의 빈자리를 처방 루프가 채운다. 리뷰어가 연속 '잡음 이내'로 판독하면 종료(R7) | 분석가 · 처방 담당 · 리뷰어 = Opus/max | 〃 |

상태 어휘 — 프로그램 `blocked · idle · ready · active · paused · done · killed` · 라운드 `registered → complete`(정의 = `program_registry.R`).

### b) 라운드 — `P<n>R<2자리>_<이름>`

| 코드 | 이름 | 단계 · 상태 | 하는 일 | 담당 · 모델/노력 | 정본 파일 |
|---|---|---|---|---|---|
| `P0R01_feasibility_map` | 실현 가능성 지도 | P0 · `registered`(10-15: E1 · E2 측정 완료 · E3 재측정 + 셀 평가 = 파이프라인 v2) | 엔진 3 × 구성요소 7 = 21셀. 보는 창 목표 영역 = 상승 포착 ≥ 0.55 ∧ 위기 누적 포착 ≤ 도출 문턱 ∧ CAGR ≥ 16%. 판정 `reached`/`not_reached` · S_vis 최대 1셀을 P4 골격으로 | R 계약 · Q | `04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/` |
| `P1R01_engine_qualification` | 수익 엔진 자격 | P1 · `registered` | 새 측정 없이 P0R01 C0 3셀 공유. 보는 창 β-통제 t(α) ≥ 2.0 ∧ 상승 포착 ≥ 0.55 → '자격', 시험 창 α > 0 → '유지' | R | `…/P1_RETURN/P1R01_engine_qualification/` |
| `P2R01_s2_pilot` | 처방 루프 파일럿(S2) | P2 · `complete` · 선정 없음 · 리뷰어 `deepen` | 기저 B6_36 에 처방 3건(RX1~3) + 같은 판본 대조(RX0). 반증 기계 판정 → 선택 규칙 | 분석가 · 처방 담당 · 리뷰어 Opus/max(각 1회, 14~16분) · 측정 · 판정 R | `…/P2_DEFENSE/P2R01_s2_pilot/` · `stage_artifacts/programs/P2_DEFENSE/P2R01_s2_pilot/ROUND_REPORT.md` |
| `P2R02_device_cross_engine` | 방어 장치 교차 엔진 검증 | P2 · `registered` | 새 측정 없이 P0R01 21셀 공유. 장치 C1~C6 × 엔진 3 × 보는 창 위기에서 V1 ∧ V2 ∧ V3 → `validated`, 아니면 `rejected`. 급락형 · 완만형 위기 분리 보고 | R | `…/P2_DEFENSE/P2R02_device_cross_engine/` |
| `P3R01_construction_map` | 구성 지도 | P3 · `registered`(E1 K1 · K5 측정 완료 · 나머지 8셀 = 파이프라인 v2) | E1 · E2 × K1~K5 = 10셀. 기준 K0 = `P0R01_E?_C0`. 보는 창 CDaR↓ ∧ S_vis ≥ 기준 → improve. 판정 `construction_lever`/`no_lever_over_ew` | R | `…/P3_CONSTRUCTION/P3R01_construction_map/`(+ `evaluate_fix_20261015.md`) |
| `P3R02_eigen_markowitz` | 정제 공분산 최소분산 | P3 · `registered`(사전등록 v4 · 측정 전 v5 재핀 예정 — 운영 경로 성능 수정 반영). 측정 = 파이프라인 v2 의 `pipeline.done` 뒤 precheck 통과 시 | M5 2셀 + 같은 배치 기준 RX0 2셀. M5 위기 누적 포착 < RX0 ∧ 위기별 과반 ∧ 상승 포착 ≥ 0.55 ∧ 비열등 → 귀속 태그와 함께 P4 구성 후보 | 사전등록 = Q + 격리 교차 점검 2회(범용 에이전트) · 측정 · 판정 R | `…/P3_CONSTRUCTION/P3R02_eigen_markowitz/` |
| `P4R01_skeleton_rx` | 조립 · 처방 루프 1라운드 | P4 · **미등록**(스크립트만 · 등록부 rounds 비어 있음) | P0 `reached` 일 때만: 골격(P0R01 선택 셀) → 분석가 → 처방 1~3건 → 사전등록 → 측정 → 리뷰어 → 종료. A → Judge | 레인 Opus/max · R | `04_Research/programs/P4_ASSEMBLY/P4R01_skeleton_rx/` |

**의존 관계**: P0R01 측정 하나를 P1R01 · P2R02 · P3R01(기준 K0) · P3R02(RX0 사양) · P4R01(골격)이 공유한다.

### c) 셀 코드 규칙 — `P<프로그램>R<라운드>_<엔진>_<변형>`

**적용 범위**: 이 형식은 1계층 프로그램 라운드 **전체 공통**이다(P0~P4 · 라운드 순번은 프로그램 안에서 매긴다 — P3R01 → P3R02).
**라운드마다 다른 것**: E · C · K · M · RX 같은 기호의 **뜻**은 각 라운드의 사전등록(`round_def.R` · `prereg.json`)이 정한다 — 아래 표는 10-15 현재 등록된 라운드들의 정의다.
**논문과의 관계**: 라운드는 논문 단위가 아니다. 새 논문은 충실구현 → 라우터 분류(수익 · 방어 · 구성) → 해당 프로그램 재료 큐 → 그 프로그램의 다음 라운드에서 쓰인다(예: 1810.08384 → P3R02). P0R01 은 P0(실현 가능성 지도)의 1라운드이며, 엔진 E2 · E3 가 DNN(2002.06975) 계보인 것은 등록 시점의 기존 수익 엔진 중 그 계보가 가장 나았기 때문이다(E1 = 문헌 기준 모멘텀).

```
P0R01_E2_C4  =  P0 실현 가능성 지도 · 1라운드 · 엔진 E2(2002.06975 DNN 원형) × 구성요소 C4(저변동 틸트)
  사양        04_Research/programs/P0_FRONTIER/P0R01_feasibility_map/specs/P0R01_E2_C4.json  (md5 가 사전등록에 핀)
  측정 결과    …/results/P0R01_E2_C4.json(.log · .err.log) → artifacts = stage_artifacts/replication/<시각>_<pid>/
  권위 등급    <artifacts>/authoritative_remeasure.json::essence_grade
  셀 평가      …/results/P0R01_E2_C4/eval.json
  보는 창      …/results/P0R01_E2_C4/visible/diagnosis_packet.{json,md}
  전기간       …/results/P0R01_E2_C4/full/behavior_card.json
```

처방 셀은 엔진 자리 없이 `<라운드>_RX<n>`(기저가 하나뿐). P3R02 는 `<라운드>_<엔진>_<M5 또는 RX0>`.

| 코드 | 이름 | 쓰는 라운드 | 하는 일(사양 delta) | 담당 | 정본 파일 |
|---|---|---|---|---|---|
| `E1` | 모멘텀 12-1 | P0R01 · P1R01 · P3R01 · P3R02 | 셀 엔진 내장 12-1 신호(shift 21/252) 상위 25종 EW. Jegadeesh-Titman 1993. 성과를 보지 않고 고른 기준점 | R(셀 엔진) | `P0R01/round_def.R::p0_engines` |
| `E2` | 2002.06975 DNN 원형 | 〃 | 논문 DNN 예측 점수 상위 25종 EW(31특성 · DNN5 · 5거래일 갱신) | R | 〃 · `04_Research/strategies/RP_AUTO_2002_06975/engine.R` |
| `E3` | B6_36 | P0R01 · P1R01 | 같은 계보 기존 최고 셀. DNN 점수 + 팩터 3(M01_Mom_12_1 · V10_FCF_Yield · M08_Residual_Mom) rank-z 결합(기저 가중 0.5) · 엔트로피 비중 · 순위 버퍼 2배 | R | `P2R01_s2_pilot/base/base_cell_spec.json` |
| `C0` | 구성요소 없음 | P0R01 | 엔진 그대로(기준) | — | `round_def.R::p0_components` |
| `C1` | 추세 현금 | P0R01 · P2R02 | 시장 12개월 수익 < 0 → 현금(오버레이 `ts_mom_sign`). Moskowitz-Ooi-Pedersen 2012 · Faber 2007 | R | 〃 |
| `C2` | 변동성 타기팅 | 〃 | 노출 = min(1, 확장창 중앙 실현변동성 ÷ 현재 60일 변동성)(`vol_median`). Moreira-Muir 2017 | R | 〃 |
| `C3` | 낙폭 제어 | 〃 | 낙폭이 확장창 중앙~90분위 구간이면 노출 선형 축소(`dd_brake_q`). Grossman-Zhou 1993 | R | 〃 |
| `C4` | 저변동 틸트 | 〃 | 252일 실현변동성 낮은 쪽(`D03_RealVol`) 기저와 rank-z 결합. Blitz-van Vliet 2007 | R | 〃 |
| `C5` | 퀄리티 틸트 | 〃 | 복합 퀄리티(`Q08_Composite_Quality`) 결합. Asness-Frazzini-Pedersen 2019 | R | 〃 |
| `C6` | 추세 현금 + 저변동 | 〃 | C1 + C4(시변 노출 × 방어적 보유) | R | 〃 |
| `K0` | EW 기준 | P3R01 | `P0R01_E?_C0` 측정 재사용(새 측정 없음) | — | `P3R01/register.R` |
| `K1` | 역변동성 | P3R01 | `lean:ivol`(추정 창 60일). Kirby-Ostdiek 2012 | R | 〃 |
| `K2` | 최소분산 | P3R01 | `lean:minvar`(Ledoit-Wolf · 창 120일). Clarke-de Silva-Thorley 2006 | R | 〃 |
| `K3` | 낙폭 제약(CDaR LP) | P3R01 | `qepm:CDaR_LP`. Chekhlov-Uryasev-Zabarankin 2005 | R | 〃 |
| `K4` | 켈리 | P3R01 | `lean:kelly`(창 120일). Busseti-Ryu-Boyd 2016 | R | 〃 |
| `K5` | 순위 버퍼 2배 | P3R01 | 회전 통제. Novy-Marx-Velikov 2016 | R | 〃 |
| `M5` | 고유모드 정제 공분산 최소분산 | P3R02 | `paper:EigenCleanMarkowitz`. 1810.08384 §II 식 4 · 상위 k = 5 모드 · p = 1 · 비중 상한 없음 · 추정 창 252일 | R(어댑터) | `02_Infrastructure/methods/adapters/eigen_clean_markowitz.R` |
| `RX0` | 같은 판본 기준 재측정 | P2R01 · P3R02 | 처방 아님 · 시행 수 미산입. 데이터 판본이 바뀌었으면 기준을 같은 사양으로 다시 측정. P2R01 = B6_36, P3R02 = `P0R01_E?_C0`(카탈로그 미등재) | R | research-program SKILL §2 |
| `RX1`~`RX3` | 처방전 번호 | P2R01(P4R01 에선 `P4R01_<처방 id>`) | RX1 = 하방 비대칭 팩터 D07 추가 · RX2 = 회전 상한(≤25 축 위반으로 측정 무효) · RX3 = 추세 지속성 상태 → 보유 베타 순위 오버레이 | 처방 담당 Opus/max → R 측정 | `P2R01_s2_pilot/specs/*.json` · `prereg.json` |

같은 글자의 다른 뜻: P1R01 의 `E1~E3` 은 '엔진'(데이터는 `P0R01_E?_C0`) · P2R02 의 `C1~C6` 은 '장치'(엔진 3개 위에서 C0 와 비교).
주의: ① P2R01 사전등록 `base.flags` 의 '2002.06975 계보 = 자동 기억 노출 possible → 이 계보 A 보류'가 P0R01 E2 · E3 셀에도 적용되는지 (미확인). ② 비중 상한 폐지(10-15 고정 축 결정)로 빌트인 `max_w` 0.15 가 없어져 P3R01 E1 셀 · P0R01 E3 셀은 재측정 대상(옛 결과 = `results/_superseded_cap_20261015/`).

### d) 측정 계약 — `MC1`~`MC8`(P0 선행 조건 · 전부 완료)

| 코드 | 이름 | 상태 | 하는 일 | 정본 파일 |
|---|---|---|---|---|
| `MC1` | 전 종목 + 위생 주입 | `done` | 유니버스는 엔진이 아니라 계약이 정한다. 관리종목 · 거래정지 · 불성실공시 제외 + 20일 거래대금(t−1) 하한. epoch `all_hyg_2000_v1` | `contracts/measurement_axis.R` · `constraint_defaults.json::measurement_axis` |
| `MC2` | 상장폐지 수익률 규칙 | **제외**(D14 · 도훈 "필요없어") | — | `research_programs.json::measurement_contract.dropped` |
| `MC3` | 시작 2000-01-01 · 실효 시작 | `done`(B안) | 신호 폭 ≥ 보유 수 × 2 첫 신호일부터 성과 집계 · A 관문 창도 이 기준 | `measurement_axis.R::ma_effective_start` |
| `MC4` | 주간 리밸런싱 | `done` | 하네스 주간 경로 + C5 컷오프 일반화(셀 엔진 주간 신호는 미구현 · 주간 처방 오버레이 금지) | `replication/replication_harness.R` · `validation/overlay_pit_guard.R` |
| `MC5` | Σw ≤ 1(잔여 현금) | `done` | 엔진 단정 개정. 현금을 만드는 층은 아직 오버레이뿐 | `reinforcement/rf_axes.R` |
| `MC6` | 행동 카드 계약 | `done` | 위기별 포착 · 상승 포착 · CR · CDaR · τ_D 분할 | `contracts/behavior_card.R` · `06_Registry/behavior_card.json` |
| `MC7` | 등급 v3 | `done`(권위 승격) | S · 하한 · CR 노치 · τ_D OOS | `contracts/grade_v3.R` · `06_Registry/grade_v3.json` |
| `MC8` | 크기 · 노출 매칭 대조 | `done` | 보유 기록으로 무작위 무신호 포트폴리오 200개(플라시보)를 만들어 방어 귀속 라벨 부여 | `contracts/matched_controls.R` · `06_Registry/matched_controls.json` |

### e) 레인 · 에이전트 — 누가, 어떤 모델 · 노력으로, 얼마나 자주

| 코드(키) | 이름 | 단계 | 하는 일 | 모델/노력 · 호출 빈도 | 정본 파일 |
|---|---|---|---|---|---|
| Q | 세션(오케스트레이터) | 전 단계 | 스크립트 실행 · 결정 기록 · 보고 · 커밋. 수치를 직접 내지 않는다(AX-008) | `claude-opus-5-5` · max(세션 설정) · 상시 | `CLAUDE.md` |
| `paper_router` | 논문 라우터 v5 | 재료 | 신규 논문을 return · defense · construction · not_relevant 로 분류 | Sonnet/high · 아침 체인 하루 1회(예약 작업 비활성) | `ops/paper_router_run.sh` · `reinforce_auto_config.json::llm.lanes` |
| `paper_atlas` | 메커니즘 지도 추출 | 재료 | 논문 주장(시장 · 기간 · 효과 · 위기 행동) 추출 → R 검증 → 지도 | Opus/xhigh · `QVEST_PAPER_ATLAS_ENABLE=1` 일 때만 | `ops/paper_atlas_run.sh` · `programs/mechanism_atlas.R` |
| `replication` | 충실구현 레인(청정 재구현) | 충실구현 | 논문만 읽고 engine.R · FIDELITY.json 작성(성과 열람 차단) | Opus/max · tick 당 최대 1편(≤40분). 예약 작업(8분 간격)은 비활성 → 세션이 `run_tick_once.sh` 로 1회씩 실행 | `ops/rf_replication_auto.sh` |
| `fidelity_audit` 팬아웃 | 충실도 감사 6축 | 충실구현 | 축별 논문 ↔ 코드 대조 → R 병합 → faithful · adapted · misdeclared | 판독형 필수 3축(signal · portfolio · undeclared) = Opus/xhigh · 대조형 3축(timing · universe · cost) = Sonnet/high · 편당 1회 6병렬 | `ops/rf_fidelity_fanout.sh` · `06_Registry/rf_fidelity_axes.json` |
| (기계 · R) | 사전검사 · 측정 · 검증기 | 충실구현 | 신고 구조 확인 → 측정 · 등급 → 고정 축 · PIT · 감사 관문 재도출 → 행동 카드 · 재료 큐 · 보고 | LLM 없음 · 편당 | `ops/rf_preaudit.py` · `alpha_search/run_paper_replication.R` · `ops/rf_replication_verify.R` |
| `alpha-search` 에이전트 | 세션 충실구현 | 충실구현(세션) | 같은 일을 세션에서(논문 지정 가능) | 세션 모델 상속 · high · `/alpha-search` 때 | `.claude/agents/alpha-search.md` |
| `analyst` | 전략 분석가 | 라운드 ①(처방 루프) | 보는 창 진단 패킷 · 논문 · 헌장 → 전략 이해서(엣지 원천 · 국면 · 지킬 강점 · 약점 가설) | Opus/max · 라운드당 1회(P2R01 16분) | `programs/rx_lane.sh` · `<라운드>/prepare_analyst.R` |
| `prescriber` | 처방 담당 | 라운드 ① | 처방전 1~3건(가설 · 기대 방향 · 기계 판정형 반증 조건 · 구현 delta) + 최종 선택 규칙 | Opus/max · 라운드당 1회(14분) | `rx_lane.sh` · `prepare_prescriber.R` |
| `reviewer` | 리뷰어 | 라운드 ④ | 사전 가설 대비 기전 판독 · 다음 수 · 교훈 | Opus/max · 라운드당 1회(14분) | `rx_lane.sh` · `evaluate.R` |
| 범용 에이전트 | 격리 교차 점검 | 라운드 ① | 결과를 열지 않고 사전등록 초안의 결함 지적(필수 · 권고) | 세션 상속(opus-5-5 · max) · 초안마다(P3R02 는 2회) | P3R02 `prereg.json::reviewed_drafts` |
| (R 계약) | 셀 측정 | 라운드 ② | 사양 → 백테스트(close_t1 · 15bps · epoch 표기) → 권위 등급 | LLM 없음 · 셀당 1회(결과 있으면 skip) · 3-way 병렬 | `ops/rf_cell_worker.R` |
| (R 계약) | 셀 평가 | 라운드 ③ | 축 감사 + 보는 창 진단 패킷 + 전기간 카드 + 시험 창 | LLM 없음 · 셀당 1회(eval.json 캐시) · 샤딩 K = 여유 메모리 GB ÷ 4(최대 6) | `_lib/round_kit.R` · `_lib/eval_parallel.sh` |
| 재시작 파이프라인 v2 | 일괄 실행 | ②~④ | Rcpp 사전 컴파일 → 측정 3-way 병렬 ‖ 팩터×월 파티션 캐시 프리페치 → P0R01 셀 평가 샤딩 + 종합 판정 → P2R02 · P1R01 ‖ P3R01 셀 평가 샤딩 + 종합 → P3R02 재핀 센티널 대기 → `pipeline.done` | R · 1회성(10-15 분리 실행) | `_lib/pipeline_v2_20261015.sh`(로그 `_lib/pipeline_v2.log`) |
| `judge` | Judge(PIT 전담) | A 경로 | PIT C1~C15 · 재현 검증 → `judge_verdict_v2`. 등급 재채점 안 함 | Opus/max(10-15 도훈 지시로 xhigh → max · 설계 §10.4 상향안 반영) · `judge_request.eligible.json` pending 일 때만 | `.claude/agents/judge.md` |
| BOOK writer | BOOK 등록 | A 경로 | A + PIT PASS → 등록. 자동 등록 금지 · 도훈 confirm 뒤 | LLM 없음 · 사건마다 | `02_Infrastructure/book/book_registry.R` |
| `book-tracker` | BOOK 트래킹 | BOOK 뒤 | 등록 전략을 고정 사양 그대로 재실행 · drift 경보 | Opus/high · `/book` 때 | `.claude/agents/book-tracker.md` |

설정에만 있고 레인 스크립트가 없는 역할: `steward`(철학 감독관, Opus/max) · `factor_definer`(Opus/xhigh) · `coder`(Sonnet/high) · `report_writer`(Sonnet/medium). 처방 루프 3역할도 설정 항목은 읽히지 않는다 — 실제로는 `rx_lane.sh` 위치 인자 기본값(opus · max)이 정한다(결과 값은 같음).
그 밖의 무인 레인: `overlay_audit`(새 팩터 · arm 코드 감사, Opus/xhigh — 이번 라운드 사용 여부 미확인) · `cleaner_distill`(주간 증류, Sonnet/high).

### f) 판정 용어

| 코드 | 이름 | 단계 | 뜻 | 산출 | 정본 |
|---|---|---|---|---|---|
| `A·B·C·F` | 등급 v3(권위 등급) | 측정 · 사람 쪽 판정 | S + A 하한 + CR 노치 + τ_D OOS 로 낸 유일한 등급 | `essence_score.R` → `grade_v3.R` | `authoritative_remeasure.json::essence_grade`(인용은 여기서만) |
| `S` | 종합점수 | 〃 | (Calmar/0.64)^0.6 × (PORT_t/2.95)^0.4, 하나라도 ≤ 0 이면 0. A = S ≥ 1 · B = S ≥ S(같은 창 KOSPI200 Calmar, PORT_t 2.0) · C = S > 0 · F = 0 | `grade_v3.R` | `grade_v3.json` · `constraint_defaults.json::tier_graduation` |
| A 하한 | A 문턱 | 〃 | PORT_t ≥ 2.0 · Calmar ≥ 같은 창 KOSPI200 · CAGR ≥ 16% · Sharpe ≥ 0.8 · OOS(시험 창 CR 약함 아님 ∧ 롤링 36M ≥ 0.5) · 스윕이면 DSR. 미달 → B | 〃 | `CLAUDE.md` 등급 절 |
| CR 노치 | 위기 복원력 조정 | 〃 | 강함 = 한 단계 위(B→A 는 하한 전부 + MC8 선택 방어일 때만) · 약함 = 한 단계 아래 · A 불가 · F 는 노치 없음 · 규칙 판 v3.1 | 〃 | 〃 |
| `S_vis` | 보는 창 종합점수 | 라운드 판정 | 같은 S 식을 보는 창(≤ τ_D) 수치로. 선택 · 비열등 판정용(등급 아님) | `round_kit.R::rk_S` | 각 prereg `final_selection_rule` |
| `PORT_t` | 포트폴리오 알파 t | 〃 | KOSPI200 대비 순 초과수익의 Newey-West(lag 3) t | 결과 계약 | `measurement-graduation.md` §2 |
| `t(α)` | β-통제 알파 t | P1R01 | r = α + β·r_bm 회귀의 α t(NW lag 3). 알파 존재 주장은 이것으로만 | `contracts/beta_controlled_alpha.R` | P1R01 prereg |
| `Calmar` | 위험조정 수익 | 등급 | CAGR ÷ 최대낙폭(월간). 0.64 = 16% ÷ 25% | 결과 계약 | 〃 |
| `CDaR` | 조건부 낙폭 위험 | P3 판정 | 낙폭 분포 상위 5% 꼬리 평균(α 0.95) | `behavior_card.R` | `behavior_card.json::cdar_alpha` |
| 위기 | LT 20/20 위기 | 행동 카드 | KOSPI200 일간 기준 국지 고점 대비 −20% 시작 · 국지 저점 대비 +20% 종료(first passage). 저점 ≤ τ_D → 보는 창 · 고점 > τ_D → 시험 창 | 〃 | `behavior_card.json::crisis_episode_def` |
| `dd_capture` | 위기 하락 포착 | 〃 | 위기 구간 전략 최대낙폭 ÷ 벤치 최대낙폭(≥ 1 = 시장만큼 또는 더 하락) | 〃 | 〃 |
| `cum_capture` | 위기 누적 포착 | 〃 | 위기 구간 전략 누적수익 ÷ 벤치 누적수익. P0R01 목표 영역 · P3R02 판정은 이 값의 중앙값 | 〃 | 〃 |
| `up_capture` | 상승 포착 | 〃 | Pagan-Sossounov 강세 국면 누적수익 비. 하한 `uc_floor` = 0.55 | 〃 | `behavior_card.json::uc_floor` |
| `dc_strong` | '강함' 누적 포착 문턱 | 〃 | uc_floor 와 KOSPI200 강세→약세 쌍(2000-01~2022-12)에서 도출(새로 정한 숫자 아님) | `bc_dc_strong_max` | `behavior_card.R` |
| CR `strong·normal·weak·insufficient` | 위기 방어 판정 | 〃 | 아래 목록 | `.bc_verdict` | `behavior_card.json` |
| MC8 귀속 | 방어 귀속 라벨 | 카드 · 판정 | 아래 목록. 크기 방어 · 노출 방어는 '실력'으로 쓰지 않는다 | `matched_controls.R::mc_attribution` | `matched_controls.json` |
| `τ_D` | 정보 경계 2022-12-31 | 전 단계 | 보는 창(측정 시작~τ_D) = 처방 에이전트 · 선택 규칙 · 교훈. 시험 창(2023-01~) = 등급 · Judge · BOOK · 사람만 | — | lean-loop · `behavior_card.json::tau_d` |
| `all_hyg_2000_v1` | 현 측정 축(epoch) | 전 단계 | 전 상장 + 위생 · 2000-01-01~ · 롱온리 ≤ 25종 · Σw ≤ 1 · 15bps. 등급은 같은 epoch 끼리만 비교(구 `k200kq150_2005_v1` 과 혼용 금지) | `measurement_axis.R` | `constraint_defaults.json::measurement_axis` |
| 실효 시작 | MC3 B안 | 측정 | 신호 폭 ≥ 보유 수 × 2 첫 신호일부터 성과 집계 | `ma_effective_start` | `authoritative_remeasure.json::measurement_axis.effective_start` |
| 축 감사 | 고정 축 준수 확인 | ③ | 실보유(04_holdings)가 롱온리 ∧ ≤ 25종 ∧ Σw ≤ 1 인지. 위반 = 측정 무효(미시험) · 등급 인용 안 함 | `rk_axis_audit` | research-program SKILL §2 |
| `R2` 사전등록 | 사전 고정 | ① | 가설 · 기대 방향 · 반증 조건 · 변형 수 · 선택 규칙을 측정 전 고정. md5 는 등록부가 보관하고 평가 · 측정이 대조 | `register.R` → `pr_record_round` | `program_registry.R` |
| `n_family` | 시행 회계 | ① | 계보 전체의 측정 시도 수(DSR 입력). RX0 는 미산입 | `rx_compile_spec` | 셀 사양 `selection_accounting` |
| 반증 · 미시험 · 판정 불가 | 판정 결과 어휘 | ④ | 반증 = 사전등록 조건 불충족 · 미시험 = 축 위반 · 기전 미발화 · 입력 NA(반증 아님) · 판정 불가 = 시험 창에 강세나 위기가 없음 | `evaluate.R` | 각 prereg |
| `deepen·combine·switch·stop` | 리뷰어의 다음 수 | ④ | 심화(같은 기전 정교화) · 결합 · 전환(새 약점 가설) · 종료(R7) | 리뷰어 | `lane_reviewer/prompt.md` |
| `close_t1` · 15bps | 체결 · 비용 | ② | 신호 다음 거래일 종가 체결. 등급은 15bps 순비용 판 | 셀 워커 | prereg `measurement` |

**CR 판정**(위에서부터 먼저 맞는 것): ① insufficient = 위기 2개 미만 ② weak = `dd_capture ≥ 1` 위기가 과반 ③ strong = 누적 포착 ≤ `dc_strong` 위기 과반 ∧ 상승 포착 ≥ 0.55 ∧ 최악 `dd_capture` < 1 ∧ 전략 MDD ≤ 벤치 MDD ④ normal = 나머지.
**MC8 귀속 라벨**(위기 과반 기준 · 위에서부터): ① `selection_defense`(기전 방어) = 크기 · 노출을 맞춘 무작위 포트 200개의 5% 분위보다 덜 하락 ② `size_defense` = 위가 아니고 노출 매칭 대조보다 덜 하락 ③ `exposure_defense` = 위가 아니고 시장보다 덜 하락 ④ `no_defense` = 시장보다도 덜 하락하지 못함 ⑤ `insufficient` = 위기 2개 미만.

### g) 파일 · 산출물

| 파일 | 이름 | 단계 | 담는 것 | 쓰는 주체 | 위치 |
|---|---|---|---|---|---|
| `prereg.json` | 사전등록 정본 | ① | 가설 · 셀 목록(사양 md5) · 반증 · 선택 규칙 · 설정 사본 md5 · 운영 파일 핀 | `register.R` | `stage_artifacts/programs/<P>/<R>/`(라운드 폴더 것은 사본) |
| `specs/<셀>.json` | 셀 사양 | ①② | 기저 + delta · 측정 축 표기 · 시행 회계 | `rx_compile_spec` | `<라운드>/specs/` |
| `behavior_card_cfg_at_prereg.json` | 행동 카드 설정 사본 | ①③ | 등록 당시 위기 정의 · uc_floor — 정의가 바뀌어도 반증 의미 고정 | `register.R` | `<라운드>/` |
| `results/<셀>.json` | 측정 결과 | ② | ok · grade · artifacts 경로 · err(+ .log · .err.log) | 셀 워커 | `<라운드>/results/` |
| `<시각>_<pid>/` | 측정 산출 디렉터리 | ② | 02_nav · 03_period_returns · 04_holdings · 05_benchmark_returns · authoritative_remeasure.json · analysis_*.csv | `run_paper_replication` | `stage_artifacts/replication/` |
| `authoritative_remeasure.json` | 권위 기록 | ② | essence_grade · grade_v3(S · 규칙 판) · 측정 축 · 실효 시작. **등급 인용은 여기서만** | 〃 | 산출 디렉터리 |
| `eval.json` | 셀 평가 | ③ | status(evaluated · axis_violation · not_measured · measure_failed) · axis · visible · test · full. P0R01 판 visible 에는 cdar 없음(CDaR 은 패킷에서) | `rk_eval_cell`(P0R01 은 자체 판) | `<라운드>/results/<셀>/` |
| `diagnosis_packet.{json,md}` | 보는 창 진단 패킷 | ③ | τ_D 에서 적재를 끊고 만든 성과 · 행동 카드 · MC8 귀속 · 노출 분해 · 위기 귀속 · 구성 프로필. 처방 에이전트에겐 md 만 | `dp_build` | `…/results/<셀>/visible/` |
| `behavior_card.json` | 전기간 행동 카드 | ③ | 카드 + MC8 대조. test 블록 = 시험 창 · 사람 쪽 | `mc_card` | `…/results/<셀>/full/` |
| `evaluation.json` | 라운드 판정 | ④ | 사전등록 규칙 기계 적용 결과(+ evaluation_table.csv) | `evaluate.R` | `<라운드>/results/` |
| `ROUND_REPORT.md` | 라운드 보고서 | ⑤ | 사람 쪽 전기간 표 · 판정 · 다음 할 일 | `close_round.R` · `_lib/close_light_rounds.R` | `stage_artifacts/programs/<P>/<R>/` |
| `prompt.md · out.md · run.log` | 레인 입출력 | ①④ | 레인 입력(md) · 최종 응답 · rc · 모델 · 노력 | `rx_lane.sh` | `<라운드>/lane_analyst · lane_prescriber · lane_reviewer/` |
| `night_state/<단계>.done` | 파이프라인 센티널 | ②~④ | `p0_measured` · `v2_prefetch` · `v2_measured` · `p3_measured` · `p0_cells_evaluated` · `p0_evaluated` · `p2r02_evaluated` · `p1r01_evaluated` · `p3r01_evaluated` · `p3r02_repinned` · `pipeline` · `p3r02_measured` | 파이프라인 · measure.sh · 세션 | `04_Research/programs/_lib/night_state/` |
| `precheck.json` · `<셀>.fp_start/.fp_end` | P3R02 측정 전 대조 · 데이터 지문 | ② | 사양 · 운영 경로 md5 · quadprog · R 판 · RAWDATA · 벤치 캐시 크기 · mtime | `precheck.R` · `measure.sh` | `P3R02/results/` |
| `factor_db_partcache/v1/<팩터>/<월>.rds` | 팩터×월 파티션 캐시 | ② | `load_month_factors` 의 팩터 지정 읽기 결과(무효화 키 = 월 파일명 · 크기 · mtime · 컬럼) | `factor_db_connector.R` | `.cache/`(= `C:/qm_cache`) |
| `rcpp_build/` | Rcpp 빌드 캐시 | ② | 사전 컴파일된 C++ 공유 라이브러리(소스 해시가 같으면 재사용) | `backtest_harness.R` · `strategy_analyzer.R` | `.cache/` |
| `replication_request.json` | 충실구현 요청 슬롯 | 충실구현 | pending · in_progress · failed_needs_session · held_audit_conflict | `next_replication.R` · 레인 | `06_Registry/` |
| `RP_AUTO_CLEAN_<slug>/` | 청정 재구현 작업 디렉터리 | 충실구현 | engine.R · FIDELITY.json · fidelity_axis_<축>.json · fidelity_audit.json · lane_provenance.json · (audit_conflict.json) | 레인 · 감사 | `04_Research/strategies/` |
| `judge_request.eligible.json` / `.held.json` | Judge 트리거 / 보류 | A 경로 | A 관문 통과(pending) / 보류 사유 코드(트리거 아님) | `run_paper_replication` §11 | 산출 디렉터리 |
| `research_programs.json` | 프로그램 등록부 | 전 단계 | 프로그램 · 라운드 · MC · 재료 큐 · 미분류 보류 | `program_registry.R` 만 | `06_Registry/` |

### 헷갈리기 쉬운 코드

- **`C1`**: P0R01 구성요소(추세 현금) ↔ PIT C1(전기간 통계 위반).
- **`R2` · `R6`**: 설계 헌법 R1~R8(R2 사전등록 · R4 τ_D · R5 노출 매칭 · R6 여러 위기 지속성 · R7 목표 축 종료) ↔ 청정 레인 읽기 가드 규칙(R1_content · R2 · R3 · R6 · R6_outside — `hooks/policies/arm_gen_read_guard.json`).
- **`S`**: 종합점수 S · 보는 창 판 `S_vis` · 설계 단계 S0~S4(S0 = 등급 v3 소급 진단 · S1 = 진단 계약 · S2 = 처방 루프 파일럿 = P2R01) · pit.md 의 옛 단계 S0(가설) · S1(구현).
- **`K1`~`K5`**: P3R01 구성 변형. M5 의 `k = 5` 는 고유모드 개수(별개).
- **`P0_FRONTIER`**: 프로그램. `P0-13` · `P0-M1` 은 09-25 수리 계획 항목 번호(무관 — 예: P0-13 = 충실구현 A 자격 관문).
- **`RX0`**: P2R01 = B6_36 재측정 · P3R02 = P0R01 C0 재측정. `RX_<라운드>` 는 시행 회계의 계보 태그(처방 아님).
- **`B6_36`**: 퇴역한 고정 격자 블록 B6(집행 주기 · 회전 통제) 36번 셀. 등급 B 와 무관.
- **`L1` · `L2`**: 원장 이름(L1 = 충실구현 소비 기록 · L2 = 2계층 강화 원장). 1계층 · 2계층과 다르다.
- **`MC1`~`MC8`**: 측정 계약. `mc_card` · `mc_load_raw` 는 MC8 계약 구현 함수의 접두사.

---

## 3. 이렇게 말하면 이렇게 알아듣는다

1. **"P3R01 E2 K2 결과 보여줘"** → 셀 `P3R01_E2_K2`(DNN 원형 × 최소분산). 먼저 `…/P3R01_construction_map/results/P3R01_E2_K2/eval.json`, 상세는 같은 폴더 `visible/diagnosis_packet.md` · `full/behavior_card.json`, 등급은 `results/P3R01_E2_K2.json` 의 `artifacts` 안 `authoritative_remeasure.json`, 비교 기준 K0 = `P0R01_E2_C0`, 라운드 판정은 `results/evaluation.json`(없으면 판정 전).
2. **"P0 어디까지 왔어?"** → `pr_status_lines()`(등록부) · `_lib/night_state/*.done`(센티널) · `_lib/pipeline_v2.log` · `P0R01/evaluate_cells_*.log`. 종합 판정이 나오면 `P0R01/results/evaluation.json::decisive.verdict` = `reached`/`not_reached`.
3. **"P2R01 RX3 왜 떨어졌어?"** → 보는 창 판정 `P2R01_s2_pilot/results/falsification_visible.md`(반증) · `selection_visible.md`(선택 규칙) · 리뷰어 판독 `lane_reviewer/out.md` · 등록부 `rounds[P2R01].reviewer.lessons`/`next_hypotheses` · 사람 쪽 전기간 `ROUND_REPORT.md`.
4. **"논문 한 편 충실구현 돌려"** → 무인판 `bash 04_Research/programs/_lib/run_tick_once.sh`(tick 1회 = 요청 발행 → 청정 재구현(Opus/max) → 사전검사 → 측정 → 6축 감사 → 검증기 · 큐 순서 그대로) · 세션판 `/alpha-search`(논문 지정 가능). A 미달 → 재료 큐 · A → A 자격 관문.
5. **"처방 루프 돌려 / 분석가 띄워"** → P4R01: ① `prepare_analyst.R`(P0 `reached` 확인 — 아니면 중지) ② `bash _lib/run_lane.sh <lane_analyst> opus max` ③ `prepare_prescriber.R` → 처방 담당 레인 ④ `register.R`(사전등록) → 측정 ⑤ `evaluate.R` → 리뷰어 레인 ⑥ `close_round.R record send`. 세션 서브에이전트로는 띄우지 않는다(세션 기억 → τ_D 누출).
6. **"속도 어디가 병목이야?"** → 측정 1셀 Rprof 기준(10-15): 팩터 적재 → 파티션 캐시로 수리 · 팩터 분석(`run_analysis`) 반복 full scan · 롤링 지표(`rollapply`) · PIT 스캔 2회. 셀 평가는 MC8 플라시보 수리로 ~50초/셀.

---

## 4. 출처

- 등록부 · 프로그램 도구: `06_Registry/research_programs.json` · `02_Infrastructure/programs/{program_registry.R, rx_lane.sh, rx_round.R, program_report.R, next_replication.R, mechanism_atlas.R, program_paper_sync.R}`
- 라운드 폴더(`04_Research/programs/` 아래): `P0_FRONTIER/P0R01_feasibility_map/` · `P1_RETURN/P1R01_engine_qualification/` · `P2_DEFENSE/P2R01_s2_pilot/` · `P2_DEFENSE/P2R02_device_cross_engine/` · `P3_CONSTRUCTION/P3R01_construction_map/` · `P3_CONSTRUCTION/P3R02_eigen_markowitz/` · `P4_ASSEMBLY/P4R01_skeleton_rx/` · `_lib/` · `_supervision/1810_08384_loop_supervision.md`
- 무인 레인 · 계약 · 설정: `02_Infrastructure/ops/{rf_replication_auto.sh, rf_replication_verify.R, rf_fidelity_fanout.sh, rf_fidelity_audit.sh, rf_llm_env.sh, rf_cell_worker.R}` · `02_Infrastructure/contracts/{behavior_card.R, matched_controls.R, diagnosis_packet.R, grade_v3.R, measurement_axis.R}` · `06_Registry/{reinforce_auto_config.json, rf_fidelity_axes.json, behavior_card.json, matched_controls.json}` · `02_Infrastructure/worktask/constraint_defaults.json`
- 문서 · 에이전트: `.claude/agents/{judge.md, alpha-search.md, book-tracker.md}` · `.claude/skills/research-program/SKILL.md` · `.claude/skills/alpha-search/SKILL.md` · `.claude/rules/lean-loop.md` · `CLAUDE.md` · `00_Lawbook/INDEX.md` · `04_Research/01_reports/l1_prescription_redesign_20261013/README.md`
- 시스템 조회(10-15): `Get-ScheduledTask Qvest*`(12종 Disabled) · `claude --version`(2.1.261)
