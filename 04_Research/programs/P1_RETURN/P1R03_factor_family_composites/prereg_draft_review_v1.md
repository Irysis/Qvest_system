# P1R03 사전등록 초안 격리 교차 점검 v1

- 점검자: 격리 교차 점검(서브에이전트). 초안을 만든 세션과 맥락을 공유하지 않았고, 이 판의 설계 · 구현에 참여하지 않았다. 측정 결과는 없다(아직 아무도 재지 않았다). 기술 점검만 했다 — 판단 · 철학 정렬은 다른 감독의 몫이다. 점검 시각은 2026-11-12 23:00~23:20, HEAD 는 시작 · 끝 모두 `71fd51da4` 였다.
- 점검 종류: 첫 점검(초안 v1 전체).
- 대상(md5 앞 8자리)
  - 판 폴더: `prereg_draft.json`(draft_version 1 · **daa0dc69**) · `prereg_draft.md`(a4cdbcc5) · `drafts.json`(v1 review = null · 9b2e191e) · `round_spec.json`(b0cb839c) · `specs/` 15 · `DESIGN.md`(699fa8cd) · `tools/p1r03_dawn_measure.sh`(b25228f3)
  - 엔진 15(`04_Research/strategies/FC_FAM_*` 14 · `FC_TOTAL_EW`) · 생성기 `02_Infrastructure/factor_db/fc_engine_gen.R`(e31ad11f) · 결합용 뷰 `factor_combinable.R`(077bf8f4) · 설정 `06_Registry/factor_combinable.json`(08e1194a)
  - 설계 `04_Research/01_reports/factor_spine_design_20261111/README.md`(10d468a0) §3 · §9 · 결정 FACTOR-SPINE-STAGE1-20261112 · FACTOR-SPINE-D6-REVISE-20261112
  - 코어 v3(매니페스트 4d00113a = `RELEASES.json` v3) · 같은 코어 · 같은 셀 경로를 쓰는 판 2(`P1S02_standing_qualification`)의 사양과 등록본 핀
- **판정: revise** — 규칙 · 선택 규칙 · 칸 사양 15 · 엔진 15 · 핀 68 은 모두 재도출과 맞는다. 그러나 등록 전에 막아야 할 것이 둘 있다. 둘 다 '핀 = 판정에 닿는 전체'가 깨진 경우다.
  - F-1: 러너의 판정 경로 파일 7개가 핀에 없다. 판 2 는 같은 경로에서 이 파일들을 핀했다(수익 시뮬레이터 · 위생 유니버스 · 리밸 · 결과 저장 · 결과 계약 · PIT 관문 · 등록부 판독기).
  - F-2: 판정 규칙 `q_uc` 의 지표(보는 창 상승 포착)를 계산하는 행동 카드 설정이 고정되지 않았다. 평가가 그때의 `06_Registry/behavior_card.json` 을 읽는다.
  - 새벽 감시 셸에도 고칠 것이 있다. 결정 D6 재결정의 전제는 '시드 GPU 와 무겹침'인데 셸은 시드 창과 겹치는 낮 창을 연다. 또 결합용 뷰가 데이터 지문에 들지 않는다. 이 둘은 사양 밖이라 초안을 바꾸지 않는다.
- **건수: 필수 2 · 권고 7 · 선택 7**

## 0. 정보 경계 선언

- 연 것
  - 판 폴더 전문: `round_spec.json` · `prereg_draft.json` · `prereg_draft.md` · `DESIGN.md` · `drafts.json` · 칸 사양 2개(FACCR · TOTAL)는 전문, 15개는 md5 와 재생성 대조 · `tools/p1r03_dawn_measure.sh`.
  - 형식 선례 `P1S02_standing_qualification/prereg_draft_review_v1.md` 전문. 판 2 `round_spec.json` 의 pins · rules · selection · behavior_card_cfg. 판 2 등록본 `prereg.json` 은 `pins.files` 의 경로와 md5 만 봤다.
  - 설계 README §0 · §3 · §9. `decision_register.json` 은 FACTOR-SPINE 두 항목만 봤다.
  - 생성기 전문. `factor_combinable.R` 은 1-30 · 70-120 · 255-345 행과 grep.
  - 코어 v3: `pins.R` · `p1.R` · `spec.R` · `load.R` 전문. `util.R`(1-35 · 236-260) · `register.R`(1-152) · `driver.R`(101-109 · grep) · `cell_eval.R` · `metrics.R`(grep) · `round.sh`(1-30 · 40-135) · `fingerprint.sh`.
  - 측정 경로: `rf_cell_engine.R`(40-60 · 290-302 · 560-580 · source 줄) · `run_paper_replication.R`(source 줄 · 730-745 · grep) · `measurement_axis.R` · `diagnosis_packet.R` · `behavior_card.R`(grep) · `rf_base_cache.R`(1-47 · 86-98) · `factor_db_connector.R`(55-85 · 255-270) · `p1s02_seed_watch.sh`(grep).
  - `06_Registry/factor_db_vintage.json` 은 마지막 3항목의 id · completed_at · note 만 봤다. 결합용 뷰 `fc_meta.json` 은 최상위 키와 마지막 두 달 행(ym · as-of · 종목 수 · 팩터 수 · 크기 · mtime)만 봤다. own_spec.json 15개는 core · n_members · excluded · rule_notes · view_check · inputs.registry md5 · declared_at 을 봤다.
- 팩터 등록부: 스크립트(생성기 `fce_inputs` 와 Python)가 구성원 334 의 정적 필드만 메모리에서 썼다 — category · definition · data_source · update_freq · direction · lifecycle.status · release_pending. **dedup · retired_dedup · evidence_tier · research_stage · factor_evidence 는 열지도 출력하지도 않았다.** 출력에서 본 것은 정의 문장 10개(Q12 · XF_DU02 · Q29 · XF_EF01 · AC01 · AC11 · AC18 · D46 · R15 · M29)의 앞 110자뿐이다.
- 안 연 것
  - `stage_artifacts/replication/**` · `authoritative_remeasure.json` · 모든 `results/` · 2023 이후 성과 수치 · 등급.
  - Superfan 리뷰 본문 · 판단 원장 본문 · `factor_evidence.json`. 철학 P1 리뷰는 파일 이름만 확인했다.
- 우연 열람(1건): 형식 선례(P1S02 점검 v1) 본문 29행에서 다른 점검자의 우연 열람 기록을 읽었다. 맞춤 팩터 `RP_1603_00751` 정의의 '등급 B' 표기다. 이 판의 판정 · 지적에는 쓰지 않았다.
- 실행한 것(쓰기는 모두 세션 스크래치 폴더 — 저장소 밖)
  - Rscript 1(코어 v3 적재): `rc_spec_load` · `rc_rules_resolve` · `rc_rules_sentences` · `rc_rules_test_window_use` · `rc_prereg_md`. `rc_init_p1` 을 스크래치 판 폴더로 돌려 칸 사양 15 를 다시 만들었다. `rc_pins_compute` · `rc_pins_mismatches`. `fce_verify` ×15. 엔진 본문 정적 grep 과 구조 비교.
  - Rscript 2: JSON 형 대조 · md 재생성 md5. `fce_inputs` · `fce_members`(구성원 재계산 — τ_D 달 2022-12 를 한 번 읽어 빌더 판 · 부호표만 대조한다). 같은 정의 묶음 계산. `fce_generate_all(write = FALSE)`(건식 재생성).
  - Python: 정의 첫 문장이 같은 묶음 · 판 2 등록본과의 핀 차집합 · 결정 기록부 · 뷰 메타 판독.
  - `bash -n`(새벽 셸) · PowerShell `Get-ScheduledTask`(읽기) · `refresh_barrier.sh status`(읽기) · `git status` · `git log` · `git show --stat`.
  - **시험 · `round.sh` 하위 명령 · 새벽 셸은 하나도 돌리지 않았다**(도훈 '테스트 좀 그만하자').
- 쓴 것: 이 파일 1개.

## 1. 판정

**revise.** F-1 · F-2 를 사양에 반영해 초안 v2 를 만들면 ok 다. 권고 가운데 사양에 닿는 것(R-1 결론 범위 줄 · R-5 · R-6)을 같은 v2 에 넣으면 변경분 점검으로 충분하다(3절). 셸 항목(R-1 셸 쪽 · R-2 · R-3 · R-4)은 사양 밖이다. 다만 측정이 오늘 새벽이므로 등록과 함께 고치는 편이 안전하다.

## 2. 지적

### 필수

**F-1. '판정에 닿는 전체' 핀에 러너의 판정 경로 파일 7개가 없다 — 판 2 는 같은 경로에서 이 파일들을 핀했다**

- 주장
  - 사양 `pins.basis`(round_spec.json:186)는 "판정에 닿는 전체 … 러너 · 셀 엔진 · 워커는 코어 기본 핀"이라고 적었다.
  - 그러나 코어 기본 핀은 러너 · 셀 엔진 · 워커 파일 자체뿐이다(pins.R:6-13). 아래 7개는 그 세 파일이 부르는 판정 경로인데 핀에도 basis 제외 목록에도 없다.
  - 판 2(P1S02)도 같은 코어 v3 · 같은 셀 경로를 쓴다. 판 2 는 격리 점검 v1 F-2 · 판 1 R-3 · R-6 을 거쳐 이 파일들을 `pins.files` 에 넣고 오늘 22:00 에 등록했다.

| 파일(지금 md5 앞 8) | 판정에 닿는 호출 경로 | 닿는 칸 |
|---|---|---|
| `02_Infrastructure/replication/replication_harness.R`(d0b94e14) | `run_paper_replication.R:62` 적재 → :809-814 `run_replication_simulation`(체결 · 비용 · 수익 계산) | 15칸 전부(수익 시계열 = t(α) · 상승 포착의 입력) |
| `02_Infrastructure/factor_db/factor_z_standard.R`(c82870c7) | `measurement_axis.R:148-155` 가 적재하고 `corp_action_member` 로 위생 멤버십을 판정한다(칸 사양 `universe.kind = all_hyg`) | 15칸 전부(유니버스) |
| `02_Infrastructure/reinforcement/rf_rebalance.R`(d94bdf3a) | `rf_cell_engine.R:44` 가 무조건 적재 · :47 `rf_rb_parse(SPEC$rebalance)`. 키가 없으면 항등이지만 그 항등도 이 파일의 코드다 | 15칸 전부 |
| `02_Infrastructure/contracts/save_bt_result.R`(d724252b) | `run_paper_replication.R:68` · :834 — 칸 평가가 읽는 산출을 쓴다 | 15칸 전부 |
| `02_Infrastructure/contracts/backtest_result_contract.R`(d1d6f81d) | `run_paper_replication.R:65` — 결과 계약(실패 시 중단) | 15칸 전부 |
| `02_Infrastructure/validation/lookahead_detector.R`(044f3ff1) | `run_paper_replication.R:64` · :738 `detect_lookahead(셀 엔진)` — 러너 하드 관문 | 15칸 전부(통과/중단) |
| `02_Infrastructure/factor_db/factor_db_connector.R`(fcf7e529) | 엔진 → `factor_combinable.R:93-101` `.fc_env` 가 적재 → `.load_registry` → :315-325 `cat_map` → `fc_family_scores`(구성원 → 가족 사상) | 15칸 전부. 사상이 바뀌면 엔진의 category 대조가 멈추게 하므로 조용한 변화는 아니다. 그래도 판 2 와 같은 기준으로 핀한다 |

- 근거(대조)
  - 판 2 등록본 핀은 35개, 이 초안 핀은 68개다. 공통 경로의 md5 차이는 0이다.
  - 판 2 에만 있는 인프라 파일은 10개다. 위 7개와, 카탈로그 비중 전용 3개(`weight_catalog.R` · `advanced_weights.R` · `method_registry.R`)다. 카탈로그 3개는 EW 칸에서 쓰이지 않는다 — `rf_cell_engine.R:561-575` 의 catalog 분기에서만 쓰고, 이 판의 칸 사양은 `weighting.kind = ew` 다.
- 고치는 법
  - 7개를 `pins.files` 에 더한다.
  - basis 에 제외 이유를 한 줄씩 적는다.
    - 카탈로그 3개: EW 라 카탈로그 분기를 타지 않는다.
    - `factor_dup_scan.R`: `.fc_env` 가 적재하지만 dedup = TRUE 일 때만 쓴다. 엔진은 dedup = FALSE 로 읽는다.
    - `rf_sleeve.R`: 방어 슬리브가 null 이다.
    - `audit_bt_result.R`: 감사 표만 만든다.
    - `F1. QT_to_xts.r`: 형 변환 도구다.
    - `refresh_barrier.R`: 운영 관문이다.
    - `contracts/factor_db_vintage.R`: P1 판정과 무관하고 A · 기저 자격에만 닿는다.
    - `pit_quarantine.R` · `factor_panel_axis.json`: 생성기 입력이다. own_spec `inputs` 에 md5 가 있고 실행 경로 밖이다.
    - 결합용 뷰 저장본: 자료다(R-1).
  - 사양 md5 가 바뀌므로 초안 v2 → 변경분 점검을 거친다.

**F-2. 판정 규칙 `q_uc` 의 지표를 계산하는 행동 카드 설정이 고정되지 않았다 — `behavior_card_cfg` 가 없다**

- 주장
  - `q_uc` 의 지표 `uc_vis` 는 칸 평가 `cell_eval.R:63` `dp_build(…, bcfg = env$BCFG_L)` 의 `behavior.summary.bull_up_capture_median` 이다(:72).
  - `BCFG_L` 은 사양 `behavior_card_cfg` 가 있을 때만 고정판이다(`cell_eval.R:94` · `driver.R:70`). 이 사양에는 그 키가 없고, 초안 `behavior_card_cfg` = null 이다.
  - 그러면 `dp_build` 가 평가 시점의 `06_Registry/behavior_card.json` 을 읽는다(`diagnosis_packet.R:234` → `behavior_card.R:45-46`). 강세 구간 정의와 상승 포착 계산이 이 설정에서 온다.
  - 이 파일은 핀 68 에도, 코어 기본 핀(pins.R:6-13)에도 없다. 등록 뒤 평가 전에 누가 이 설정을 고치면 `q_uc` 판정이 핀 불일치 없이 바뀐다.
- 근거
  - `diagnosis_packet.R:233` 주석: "사전등록 당시 정의로 판정해야 하는 라운드(R2)는 그 판을 넘긴다(위기 정의가 바뀌어도 반증 의미 불변)".
  - 판 2 는 같은 규칙 · 같은 코어인데 사본 `behavior_card_cfg_at_prereg.json`(6a2a1d21)을 사양에 걸어 핀했다.
  - 지금 `06_Registry/behavior_card.json` = 6a2a1d21(마지막 커밋 61095bae1 · 10-14 · 미커밋 변경 없음)으로, 판 2 사본과 같다.
- 고치는 법
  - `06_Registry/behavior_card.json` 을 판 폴더 `behavior_card_cfg_at_prereg.json` 으로 복사한다.
  - 사양에 `"behavior_card_cfg": "<그 경로>"` 를 넣는다.
  - 그러면 핀(pins.R:40)과 초안 기록(register.R:57)에 자동으로 실리고, 평가가 고정판을 쓴다.
  - 이 사본도 판 폴더 커밋에 넣는다(등록 조건 ⑦).

### 권고

**R-1. 결합용 뷰(엔진의 유일한 팩터 입력)가 칸 데이터 지문에도, 기저 캐시 키에도 없다**

- 근거
  - 칸 데이터 지문(`fingerprint.sh:13-17` equality)은 RAWDATA · 벤치 · 재무 · `.cache/factor_db` 의 등록부 사본 · build_hash · IC · consensus · 팩터 DB 월 파일을 본다. `.cache/factor_combinable/` 은 없다. `round.sh measure` 의 칸 시작 · 끝 지문(:102 · :104)과 엔진 묶음 대조(:121)가 이 지문을 쓴다.
  - 기저 캐시 키(`rf_base_cache.R:15-29` · :43-46 보조 데이터원)에도 없다. 그 파일 스스로 "새 엔진이 다른 패널을 읽으면 여기에 더한다(빠뜨리면 그 패널 갱신이 캐시를 못 깬다)"(:29)고 적었다. "실행 전후 도장이 다르면 저장하지 않는다"(:32)도 뷰를 보지 않는다.
  - 뷰는 밤 체인 [6e] 에서 증분으로 다시 짓고, 부호표는 빌드마다 전부 다시 만든다(`factor_combinable.R:13-20`). 지금 뷰는 built_at 2026-11-11 19:28:09, 202611 as-of 2026-11-06 이다. 오늘 밤 갱신 예정이다.
- 위험
  - 팩터 DB 를 함께 다시 지으면 ④ 도장(팩터 DB 월 파일)이 바뀌어 잡힌다.
  - 구멍은 뷰만 다시 지어지는 경우다. 수리 세션이나 수동 `--build` 가 측정 창 안에서 뷰만 다시 지으면, 달마다 다른 판을 읽은 FACTORS 가 지문 일치로 판정까지 가고 캐시에도 남는다.
- 고치는 법(코어 · 핀 파일은 건드리지 않는다)
  - 새벽 셸이 measure 전후로 뷰 도장을 적는다: `fc_meta.json` md5 · `fc_signs.parquet` 도장 · `fc_*.parquet` 수 · 총크기 · 최신 mtime.
  - 도장이 다르면 보고하지 않고 '재측정 필요'로 끝낸다.
  - 결론 범위에 "결합용 뷰는 칸 데이터 지문 밖 — 셸이 측정 전후 도장을 대조했다"를 한 줄 넣는다.
  - `rf_base_cache.R` 를 지금 고치면 판 2 등록본 핀이 깨진다. v4 후보(지문 · `RF_BASE_CACHE_AUX_DIRS` 에 factor_combinable)로만 적는다.

**R-2. 새벽 셸이 D6 재결정의 전제 '시드 GPU 와 무겹침'을 보장하지 않는다 — 낮 창 08:00~16:30**

- 근거
  - 결정 FACTOR-SPINE-D6-REVISE-20261112 의 (다)는 "11-13 새벽 자료 신선해지면 측정(CPU · 시드 GPU 와 무겹침)"이다. DESIGN §8 도 "GPU 시드 감시 셸(판 2 · 08:20~)과 겹치지 않는다(CPU · 시간대)"라고 적었다.
  - 셸 시작 창은 04:30~06:50 과 **08:00~16:30** 이다(p1r03_dawn_measure.sh:4 · :20). 시드 낮 창(시작 08:20~11:45 · 측정 약 6시간 · p1s02_seed_watch.sh:6 · :34)과 시간대가 겹친다.
  - 시드 상태 확인은 시작 때 'M 측정 중' 한 번뿐이다(:24). 시드는 E2 와 E3 사이에 상태가 'W(follow)'가 된다(p1s02_seed_watch.sh:94). 그 틈에 P1R03 이 서면 E3 와 겹친다.
  - 시드 셸은 P1R03 상태를 보지 않고 가용 메모리 ≥ 16 GB 만 본다(:39 · :114). P1R03 셀 워커 정점이 7.45 GB 여도 가용이 약 21 GB 면 시드가 선다. 그러면 DNN 지속 사용량 25~33 GB(:37)에 7.45 GB 가 더해져 물리 31.8 GB 를 넘고 페이징이 일어난다. 판 2 시드는 사다리의 기준점이다.
- 고치는 법
  - 낮 창을 없앤다(못 서면 다음 새벽 창). 또는 낮 창에서는 시드 상태가 '끝'일 때만 시작한다.
  - DESIGN §8 문장을 셸 동작과 맞춘다.

**R-3. '07:10 아침 체인 전에 끝 · 못 끝내면 아침 체인 뒤 이어서'와 '데이터 지문 안정'이 셸에 없다**

- 근거
  - 시작 허용 끝은 06:50(410분 · :20)이다. 15칸은 엔진마다 칸이 하나라 직렬로 돈다 — `round.sh:116` 의 병렬은 엔진 묶음 안에서만 걸린다. DESIGN §2 기준 약 1시간에 평가가 더해진다.
  - 그래서 06:50 에 시작하면 07:10 아침 체인(`Qvest_MorningBrief` 트리거 07:10 · 실재 확인)과 겹친다.
  - 셸은 시작 때만 창 · 체인 · 배리어를 보고 measure 를 끝까지 돌린다(:28-34). `round.sh measure` 도 배리어를 측정 시작(:93)과 평가 전(:131)에만 본다. 'pause → 아침 체인 뒤 이어서' 동작은 어디에도 없다.
  - DESIGN §8 의 조건 '데이터 지문 안정'을 셸은 보지 않는다. 시드 셸은 20분 안정을 본다.
- 고치는 법
  - 새벽 창 끝을 06:00 안팎(1시간 + 여유)으로 당긴다.
  - '지문 안정' 조건을 더한다 — 예: equality 지문 + R-1 뷰 도장이 N분 동안 불변.
  - 아니면 DESIGN §8 을 셸 동작대로 고친다.

**R-4. 무인 `report --send` 가 철학 P2 줄 없이 1통을 보낸다**

- 근거
  - 셸은 measure(평가 자동 연쇄) 뒤 곧바로 `report --send` 를 부른다(:33).
  - `rc_report` 는 판정 줄과 next_step 만 싣고 P2 는 싣지 않는다(driver.R:101-109). `--next` 도 넘기지 않는다.
  - lean-loop 라운드 4 는 "판정 직후 철학 Superfan P2 … 보고에 1줄로 실린다", 5 는 "리서치 1단위 = 1통"이다. 셸 머리(:6)는 P2 를 세션 몫이라고 적었다. 그러면 발송 뒤에 P2 를 실으려면 2통이 된다.
- 고치는 법: 셸은 `report`(dry-run)까지만 한다. 발송은 세션이 P2 뒤에 `report --send --next …` 로 1통을 보낸다.

**R-5. 결론 범위 '가족 사이 같은 정의 쌍(예: D46↔R15 Sortino 외 8쌍)'을 재도출하지 못했다 — 어느 기준으로도 9쌍이 아니다**

- 근거(위치 round_spec.json:155)
  - 생성기 기록: `FC_TOTAL_EW/own_spec.json` rule_notes · `FC_README.md:79` = 기계 규칙 (F) 쌍 1개(D46_Sortino ↔ R15_Sortino).
  - 재계산(구성원 334 · 정규화한 definition 전문이 같음 · 원천 · 주기 무관): 가족 사이 1개.
  - 식(definition 첫 문장)만 같은 쌍
    - 가족 사이 5개: D45_Downside_Dev(defense) ↔ R07_Downside_Dev(risk) · D46 ↔ R15 · XF_DU03_EquityMultiplier(leverage) ↔ Q13_Fin_Leverage(quality) · XF_LL05_WorkingCapital(leverage) ↔ Q31_WC_to_Assets(quality) · L41_Intraday_Vol_Proxy(liquidity) ↔ T14_HLRange(technical).
    - 가족 안: Q12 ↔ XF_DU02 · Q29 ↔ XF_EF01(결론 범위의 '원천만 다른 쌍')과 INV13 외국인 잔차 21d · 63d · 126d(같은 식 · 창만 다름).
  - '원천만 다른 쌍'도 정확하지 않다. 두 쌍은 원천(fundamental ↔ fundamental_xlsx)뿐 아니라 설명 문장도 달라, 원천이 같았어도 (F) 가 잡지 못한다.
- 고치는 법: 기준을 밝혀 다시 쓴다. 예: "가족 사이 같은 식(정의 첫 문장) 5쌍(D45↔R07 · D46↔R15 · XF_DU03↔Q13 · XF_LL05↔Q31 · L41↔T14)은 두 가족에 다 들어 토탈에서 이중 가중된다(기계 규칙 (F) 가 잡은 것은 D46↔R15 하나) · 가족 안 같은 식 · 다른 원천 2쌍(Q12↔XF_DU02 · Q29↔XF_EF01)은 남겼다".

**R-6. 설계 §3-8 '읽는 법'과 §9 의 위험 둘이 사전등록(사양)에 없다**

- 근거
  - 설계 §3-8 의 제목은 "사전등록에 그대로 넣는다"이다. 가설 · 반증은 사양 `hypothesis` 에 있다. 그러나 읽는 법 표(서로 다른 가족 3개 이상 · 1~2개 · 0개 → 다음)는 DESIGN.md §1 에만 있고, 그 파일은 핀 · 사양 밖이다. 또 '서로 다른 가족' 셈에 TOTAL 이 드는지 정해지지 않았다.
  - 설계 §9 '등록부 방향의 출처'(근거 필드 169 · `registry_original` 195 — 1단계는 그대로 믿는다)가 노출 · 결론 범위에 없다. C13 의 `registry` 해석('미리 선언된 방향')에 닿는 고지다.
  - 설계 §9 '가족 구분의 겹침'(저위험 계열 4/14)도 노출 · 결론 범위에 없다.
- 고치는 법: `conclusion_scope` 에 세 줄을 더한다 — 읽는 법(TOTAL 을 가족 수에 세는지 명시) · 방향 출처 · 겹침.

**R-7. 설계 §3-5 절차의 '과거 음성 조회'와 §9 '미확인'이 기록되지 않았다**

- 근거: 설계 §3-5 의 절차는 "과거 음성 조회(`hypothesis_index.R lookup`) → 사양 → …"이다. §9 는 '현 측정 축 저장 기록에 가족 합성 단독 엔진이 이미 있는지'를 "사전등록 단계의 과거 음성 조회에서 확인한다"고 했다. DESIGN.md 에는 그 결과가 없다.
- 고치는 법: DESIGN §2 에 조회 키워드 · 건수 · 이 라운드와 다른 점을 적는다(τ_D 뒤 수치 없이).

### 선택

- **S-1.** 셸의 `--p=2` 는 이 판에서 효과가 없다. 엔진 묶음마다 칸이 하나라 직렬로 돈다(round.sh:113-118). 머리 주석(:5)의 '병렬 2'와 DESIGN §8 의 '한 번에 하나'가 다르게 읽힌다. `--p=1` 로 쓰거나 주석을 고친다.
- **S-2.** 노출 [2](round_spec.json:148)의 '등록부의 정적 필드(category · lifecycle · panel_axis · PIT 격리 · release_pending · 정의 문장)'는 고칠 곳이 셋이다.
  - panel_axis · PIT 격리는 별도 등록부(`06_Registry/factor_panel_axis.json` · `pit_quarantine.json`)다.
  - 규칙 6 의 키인 data_source · update_freq 가 빠졌다(fc_engine_gen.R:194).
  - 부호의 출처인 direction 도 빠졌다.
- **S-3.** 칸 사양 `root_paper` · `root_papers` 에는 JKP 2023 하나만 실린다. 설계 §3-4 는 JKP · AFP 를 말했다. `rc_p1_cell_spec` 은 논문을 하나만 받는다(p1.R:71). AFP · GKX 는 own_spec `literature` 와 엔진 머리에 있다. 기록만 한다.
- **S-4.** 칸 사양 `base_signal.path` 가 절대 경로(`C:/Users/99922/…`)다. 이 기계에서는 접합(`C:/Users/99922` → `C:/Users/User` · `OneDrive` → `G:/OneDrive`)으로 풀리고 재생성 md5 도 맞는다. 다른 기계로 옮기면 R2 가 막는다(안전 쪽). 판 2 S-5 와 같다. 기록만 한다.
- **S-5.** 이 판의 측정 경로에서는 설계 §3-7 의 정적 기계 검사(`c15_load_path_scan.R` · `rc_standing_static` 의 `factor_db_static`)가 FC 엔진에 돌지 않는다. 러너의 `detect_lookahead` 는 셀 엔진 파일을 본다(run_paper_replication.R:738 · rf_cell_worker.R:90). 이 점검의 정적 판독(4절 5)이 대신했다. v2 시험 파일에 설계 §3-7 시험 6(정적 분류)을 한 줄 넣으면 기계 검사가 된다.
- **S-6.** 실효 시작(MC3)이 가족마다 다르다. 설계 §3-1 기준으로 accrual · leverage 는 2000-05, consensus 는 2001-06, investor_flow 는 2000-02 다. 그래서 보는 창 길이와 t(α) 검정력이 가족마다 다르다. '0개 자격'을 읽을 때 닿으므로 결론 범위에 한 줄 넣는다.
- **S-7.** 셸의 체인 확인은 열린 쪽으로 실패한다. powershell 이 실패하면 'Running 아님'으로 읽고 진행한다(:15 · :21-22). 메모리 확인처럼 닫힌 쪽(판독 불가 = 대기)으로 바꾼다.

## 3. 초안 v2 변경분 점검 기준

- 사양에서 바뀌어야 할 곳
  - `pins.files` 에 7개를 더하고 `pins.basis` 에 제외 이유를 적는다(F-1).
  - `behavior_card_cfg` 와 판 폴더 사본을 더한다(F-2).
  - `tests` 에 `08_Tests/factor_db/test_fc_engine_gen.R` 를 넣는다(알려진 것).
  - `conclusion_scope` — R-1 · R-5 · R-6(· S-6). `exposures` — R-6 방향 출처(· S-2).
  - `changes_after_review` 에 이 점검의 항목 id 를 적는다.
- 바이트 동일이어야 할 블록: `rules` · `selection` · `cells` · `tau_d` · `purpose` · `hypothesis`(R-6 을 hypothesis 에 넣지 않는다면).
- 다시 재도출할 것
  - 핀 76 = 기본 18 + `pins.files` 27 + 엔진 15 + 칸 사양 15 + 카드 사본 1 · `rc_pins_mismatches` 0.
  - 칸 사양 15 md5 불변(생성 입력이 바뀌지 않는다 — 4절 3).
  - `fce_verify` 15/15 · 규칙 문장 · 해석 문턱 불변 · md 재생성 md5 = 디스크.
  - 시험 파일의 마지막 줄 형식 `{"test":…,"pass":…,"fail":0}` — 이 형식이어야 register.R:124 가 읽는다.
- 셸(사양 밖)은 등록 전에 R-1(셸 쪽) · R-2 · R-3 · R-4 를 반영했는지 `bash -n` 과 읽기로 확인한다.

## 4. 확인한 것(통과 · 근거)

| # | 항목 | 재도출 · 근거 | 결과 |
|---|---|---|---|
| 1 | 사양 ↔ 설계 · 결정 | `purpose` · `hypothesis` = 설계 §3-8 가설 · 반증(다음 탐침 = as-of 가중 결합기 · 팩터 성적표). 칸 15 = 가족 14 + 토탈 1(D3 가). size · custom 제외(§3-1). 방어 계열 4가족 = 기대수익 방향(D5 가 · own_spec 메모). 풀 입구 = 코어 다음 판 자체 사양 입구(D4 a · 결론 범위 [0]). 측정 = 시드 판정 전(D6 재결정 다 · 노출 [3] · 결론 범위 [5] — 설계 §9 '시드 판정 뒤'를 결정이 바꿨다). 틀 p1_qualification · 코어 v3 · τ_D 2022-12-31 | 일치(빠진 것 = R-6 · R-7) |
| 2 | 규칙 = P1 템플릿 | 스크래치에서 `rc_init_p1` 로 다시 만든 사양의 rules · selection 이 디스크와 identical 이다. 판 2 사양과도 identical 이다(Python). `rc_rules_test_window_use` = 0건(`_test` 는 report 규칙 `test_hold` 만). 해석 문턱 2 = `tier_graduation.grade_b_min_portfolio_alpha_t`(지금 파일) · 0.55(선언). `rules_resolved` 는 JSON 직렬화가 동일하다(정수/실수 형만 다름). 문장 identical. md 재생성 md5 a4cdbcc5 = 디스크 | 일치 |
| 3 | 칸 사양 15 재생성 | `rc_init_p1`(스크래치)의 입력은 engine_path = `FC_*/engine.R` · paper = own_spec `root_paper`(JKP 2023 · key = spec_id) · family_root = own_spec `family_root`(FC:<가족>) · n_family 1 · n_trials_basis = 디스크 문자열(15개 동일 · 독립 출처 없음)이다. **재생성 md5 = 디스크 = 초안 15/15.** 고정 축은 정본 대조를 통과했다(25 · 15bps · 2e8 · 롱온리). `measurement_axis.active` = all_hyg_px1000_2000_v1. weighting ew · factors [] · defense_sleeve null | 일치 |
| 4 | 핀 68 | `rc_pins_compute` 재계산 68 = 초안 68(경로 · md5 집합 동일) · `rc_pins_mismatches` = 0. 구성 = 기본 18 + `pins.files` 20 + 엔진 15 + 칸 사양 15. 코어 파일 20 md5 = 초안 `pins.core.files` · 매니페스트 4d00113a = RELEASES v3 · 사양 md5 b0cb839c = 초안 `spec_md5` · 초안에 실린 사양 = 디스크(identical) | 일치(빠진 것 = F-1 · F-2) |
| 5 | 엔진 15 | `fce_verify` ok 15/15 · generator_drift FALSE 15/15(own_spec 의 생성기 md5 e31ad11f = 지금 생성기). 건식 재생성(`fce_generate_all(write = FALSE)` · 지금 등록부 4995af5a = own_spec 기록 · 선언 22:25:50) 엔진 md5 15/15 동일. 코드 줄 판독: `fc_load_month` 호출은 1곳이고 인자가 `direction = "registry"`(문자열 상수) · `missing = "na"` · `dedup = FALSE` · `family = TRUE` 다. 금지 무늬 0(parquet · `.cache` · `load_month_factors` · fread · readRDS · ic_asof · defensive · s_ic · NEGATE/FLIP · connector 직접 · `sig`). `sys.source` 는 2곳(factor_combinable.R · measurement_axis.R). 가족 엔진 14개는 구성원 줄 · 고유 토큰을 빼면 본문이 동일하다. 생성 때 τ_D 달 뷰 대조 불일치 0. 실행 때 빌더 판 · 읽기 인자 · s_reg · category 대조가 있다(fc_engine_gen.R:437-450). 생성기 구성원 표 열에 dedup · 성과 표식이 없다(:148-156) | 일치 |
| 6 | 노출 · 결론 범위 사실 | 구성원 334 = 가족 합(47+57+44+30+23+24+21+15+19+14+14+12+8+6)이고 지금 등록부로 재계산해도 334 다. 초안 275 = 설계 §3-1. 정의상 별칭 3개 = AC11 · AC18(→ AC01) · M29(→ M11) — 모두 (D) 선언이고 남길 쪽은 id 사전순이다. AC01_Total_Accruals_CF 의 정의는 (dWC − dCash − dCL + dST − Depr)/TA 로 재무상태표식이라, 이름 '_CF' 와 AC11 · AC18 의 (NI − OCF)/TA 와 어긋난다. Q12↔XF_DU02 · Q29↔XF_EF01 은 같은 식이고 둘 다 구성원으로 남았다. 결과는 없다(판 폴더 `results/` 없음 · `stage_artifacts/programs/P1_RETURN/P1R03*` 없음 · `.cache/round_core/state` 에 P1R03 없음 · 엔진 폴더 `fce_diag.csv` 없음). 뷰 built_at 11-11 19:28:09 ≥ 마지막 팩터 DB 수리 완료 11-11 19:28(`factor_db_vintage.json` 마지막 항목 · 설계 §3-7 판 표식) | 대체로 맞음(가족 사이 쌍 수 = R-5 · 문구 = S-2) |
| 7 | 새벽 셸 | `bash -n` 통과. 창 270~410 · 480~990분 = 머리 문장. 체인 이름 `Qvest_DailyRefresh`(00:03) · `Qvest_MorningBrief`(07:10) 실재(Get-ScheduledTask 읽기). 배리어 판독 'state=free' = `refresh_barrier.sh status` 출력 형식(지금 free). 시드 상태 'M 측정 중' = p1s02_seed_watch.sh:79. 메모리 = FreePhysicalMemory(KB)/1MB = GB 이고, 문턱 10 GB 는 셀 워커 1개(7.45 GB)용이다(실제 직렬 · S-1). fresh-check 는 `round.sh -` 경로(round.sh:8)로 돌고, `measure --now` 도 배리어 · fresh-check · precheck 를 다시 본다(:93-95). 대기 상한 129600 s = 36시간. 종료 코드는 머리 문장과 같다 | 조건 판독 맞음(창 · 겹침 · 지문 · 발송 = R-1~R-4) |
| 8 | 시험(알려진 것) | 사양 `tests` = []. `08_Tests/factor_db/test_fc_engine_gen.R` 는 아직 없다(작성 중). 돌리지 않았다 | 확인만 |

### 등록 조건 ①~⑧ 의 지금 상태(register.R:3-4 · 107-145)

| 조건 | 지금 | 등록 전 할 일 |
|---|---|---|
| ① 마지막 초안 = 격리 점검 ok | v1 review = null · 이 점검 = revise | F 해소 → v2 → 변경분 점검 ok → `reviewed` |
| ② 사양 · 칸 사양 md5 = 초안 | b0cb839c · 15/15 일치 | v2 에서 다시 |
| ③ 핀 재대조 | 불일치 0 | F-1 · F-2 뒤 76개로 다시 |
| ④ 라운드 시험 | `tests` 빈 목록 | v2 에 시험 파일 · `run_tests = TRUE`(마지막 줄 JSON 형식) |
| ⑤ 리허설 | 초안에 `rehearsal` 없음 → 건너뜀(register.R:120) | — |
| ⑥ 철학 P1 | `_supervision/superfan/philosophy/20261112_2306_P1_P1R03.md` 파일이 있다(이름 형식 맞음). 원장 기록 · 도전 응답은 보지 않았다 | 도전 응답 · 보류 요청 없음 확인 |
| ⑦ 고정 대상 미커밋 | 판 폴더 전체가 `??`(untracked)다. 엔진 · 생성기는 커밋됐다(e577b6c61). 코어 v3 는 깨끗하다 | 판 폴더 커밋(칸 사양 · DESIGN · 셸 · F-2 카드 사본). 이 점검 파일은 이름에 `prereg_draft` 가 있어 검사에서 빠진다(register.R:103) |
| ⑧ 두 사본 + 등록부 | 실행하지 않았다 | — |

## 5. 못 본 것

- 엔진 실제 실행 · 셀 경로 측정 · 기저 정합 진단(실자료). 값 수준 PIT(절단 불변성 · 양성 대조)는 작성 중인 시험의 몫이다.
- 결합용 뷰 빌더 v1.1 이 as-of 뒤 자료를 쓰지 않는지(빌더 코드 전체).
- AC01 저장값이 정의 문장(재무상태표식)과 이름(_CF) 가운데 어느 식을 따르는지(팩터 빌더 코드). AC11 · AC18 의 제외는 선언에 기댄다.
- 등록부 방향 `registry_original` 195개의 출처(설계 §9).
- 아침 체인(`Qvest_MorningBrief`)과 07:10 자가 복구가 실제로 뷰 · 팩터 DB 를 다시 짓는지. `Qvest_StandingBoard` 틱 · 사슬 틱이 새벽에 셀 워커를 띄울 수 있는지(판 2 는 `tick_hold` 로 보류 중).
- `rc_metric_beta_alpha` · `dp_build` 내부(코어 · 계약 — 앞선 점검들이 다뤘다). `plan` 출력 형식은 round.sh 의 awk 사용으로만 추정했다.
- 철학 P1 리뷰 · 판단 T1 의 내용(감독 몫).
