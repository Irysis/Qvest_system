# module_catalog 동일-hash 이명(異名) 오염 전수 감사 — 2026-08-20

**트리거**: /improve-drain R2 가 `authoritative_essence` 3짝(PORT_t/oos/calmar)이 소수점 3자리까지
동일한 클러스터 2개를 적발 (①155704/160537 = 1.938/−0.496/0.297 ②041830/045209/053505 =
1.836/−0.319/0.308) → 원장 이상 조사 chip.

## 판정 (계층 확정)

**측정·기록 계층은 결백하다.** 세 가설 중 어느 것도 아니었다:

| 가설 | 판정 | 근거 |
|---|---|---|
| (a) register_module/essence 기록 시 meta 복사 배선 결함 | **기각** | catalog meta == 각 run_dir 의 `authoritative_remeasure.json` 원본 (5/5 대조 일치) |
| (b) 전략들이 실제로 동일 top-25 로 수렴 | **부분** — 포트폴리오는 실제로 동일하나 "수렴"이 아님 | NAV 원화 단위 동일 · `sim_result.rds` 바이트 동일 (md5 = catalog `module_hash`) |
| (c) standalone_track_queue 조인 오류 | **기각** | 스캐너는 catalog 를 충실 보고 (catalog 자체가 동일값) |

**실제 계층 = 실행(treatment) 계층**: 2026-06-12/13 **batch_434** 대량 배치에서
`02_Infrastructure/tools/patch_codegen_blocked_runners.R` 가 codegen-blocked 러너
("Forge contract/spec requires code generation before backtest")를 **keyword-fallback 팩터
콤보로 치환 실행**했다. 키워드 미매치 가설(앙상블·메타·ML 계열 대부분)은 동일한
`base_robust`/`ml_robust` 고정 콤보로 낙착 → **서로 다른 가설명이 바이트 동일 백테스트**로
catalog 에 등재. 즉 **label ≠ signal**: "측정했더니 같았다"가 아니라 **"선언한 것을 측정한
적이 없다"**.

## 전수 census (catalog 275 모듈, 2026-08-20 실측)

- **동일 module_hash 그룹 30개 / 130 모듈** (최대 그룹 38건 — XGBoost 종목선정·리스크패리티·
  Kelly·Carry 등 전혀 다른 선언이 전부 같은 sim). essence-3짝 중복 30그룹과 1:1 대응
  (교차-hash 3짝 충돌 0 = 측정 계층 복사 전무의 독립 확인).
- 분류: **FALLBACK_SUBSTITUTION 116** (치환 마커 문자열 보유) · **OVERLAY_NOOP 6**
  (BRK/MRS12/25/QualityGate 선언이 결과에 미반영 — 9d300589 ×4 · 8afca9f8 ×2, 무마커 침묵형)
  · **SAME_IDEA_RERUN 6** (동일 가설 재등록 — 라벨 참) · **BASE_ALIAS 2** (6cf303cd —
  "base" 와 "overlay excluded base" 이명, 라벨 참).
- 등록일: 06-12 38건 · 06-13 90건 · 08-09 2건(FQ-100 rerun, 라벨 참).
- **R1 근접값(2.229/2.215 등)은 이 결함 아님** — 정확-중복 30그룹은 전수 열거됐고 근접값
  쌍은 hash 상이 = 실제로 다른 백테스트.

## 하류 노출 (blast radius)

- **FR 입력면 `module_performance.json`: 210 엔트리 중 128 이 중복 그룹 소속** — RCMA 가
  같은 NAV 를 다른 이름으로 중복 선정 가능한 상태였음. FR_ 실운용 산출물은 아직 없어
  자본 오염은 없음.
- standalone_track_dispositions: 40건이 "독립 전략"으로 처분 심사됨 (R2 가 적발한 그 표면).
- **v8.4 SOT 의 ML 원장 "동일 3짝 클러스터 16+9건" = 같은 계통 (문자 그대로 같은 런들)**:
  ledger sharpe=0.493 16건 → 전원 catalog `1cc257b9` 그룹(38) · sharpe=0.492 9건 → 전원
  `3be89a6f` 그룹(11), **16/16·9/9 id 대응 실측**. 나아가 sharpe 보유 84건 중 **34건(40%)**
  이 중복 그룹 소속.

### v8.4 서사에 대한 함의 (도훈 판단 필요)

SOT 의 "서로 다른 결합 규칙이 같은 점을 낸다 — 같은 5전략 재가중이라 새 정보가 없다"는
기전 해석은 **오귀속**: 결합 규칙들은 **실행된 적이 없고** 치환 콤보가 돌았다.
- "죽은 자리 ① 결합기" 의 클러스터 근거는 **결합기에 대한 증거가 아님** (미측정이지 수렴 아님).
- 단, 재편의 다른 지지대(MDD ≤25% 충족 0/84 · PORT_t ≥2.95 = 0 · oos 게이트 2/17)는 치환
  런을 제거해도 남은 실측분에서 재검 필요하되 방향이 뒤집힐 가능성은 낮음 — **분모가 오염된
  것이지 통과 사례가 숨어 있는 것이 아님** (측정 자체는 진짜 백테스트).
- INV-7 관점: "결합기 settled-negative" 는 이 클러스터를 근거로 삼는 한 **비유효 negative**
  (선언 가설 미실행). 재판정 시 치환 런 제외 필수.

## 선행 감사와의 관계 — 진짜 결손은 "적용 안 됨"

**2026-06-13 `batch434_label_audit`** 이 이미 이 오염을 전수 진단했고(351런, MISMATCH 161)
수리 스크립트(`patch_catalog_label_annotations.R`)까지 만들었다. 그러나:
- `--apply` 는 **실행된 적 없음** (`.bak_label_audit_*` 부재 · 현행/08-09 백업 모두 label_class 0건).
- 스크립트의 `aud_dir` 가 `04_Research/audits/*` 로 낙후 (현 위치 `04_Research/01_reports/audits/*`)
  — 지금 돌려도 즉사. **본 감사 디렉토리의 스크립트가 이를 대체한다.**
- 도구 자체는 06-13 감사 후 `[PROXY-COMBO]` 라벨 강제가 추가돼 재발 방지됐으나, **기존
  catalog 오염분은 2개월간 방치**된 채 improve-drain 이 소비하다 R2 에서 재적발됐다.

## 즉시 수리 완료 (2026-08-20, 본 세션)

1. **`register_module.R` 이명 등록 차단 가드** — catalog 에 같은 `module_hash` 가 다른
   strategy_id 로 존재하면 신규 등록 **기본 BLOCK** (`QVEST_ALLOW_DUP_MODULE_HASH=1` +
   `meta$duplicate_of` 강제 기록으로만 예외. 같은 id 갱신 / quarantine 행은 대상 아님).
2. **`08_Tests/contract_regression/test_register_module.R` RM04 축 반전** — 구판은 "동일 sim
   이명 등록 성공"을 기대(= 오염 경로를 정상으로 검사). 위반 주입 + 오발화 대조 + 경계 2종
   포함 **15/15 PASS**.
3. 본 디렉토리: `build_census_and_plan.py` (재현 가능 census) + `census_dup_hash_20260820.csv`
   (130행 전수) + `catalog_patch_plan_20260820.csv` + `apply_catalog_dup_annotations.R`.

## 확장 census (continuity 사이클, 2026-08-20 동일 세션)

dup-hash census 는 **복제본만** 잡는다 — batch_434 치환 런 중 콤보가 유니크해 중복이 안 된
**37건이 추가로 현행 catalog 에 등재**(전원 fr_eligible=true, June label_class: PROXY_PLAUSIBLE 23 ·
MISMATCH 계열 14 — Residual Reversal·FF5 Alpha Filtered·잔차 Alpha 추출 등). 이들은 신설
dup 가드로도 원리적으로 안 잡히므로(산출물 유니크) **라벨 주석이 유일한 방어선**.
플랜에 편입 완료: `unique_hash_substituted_20260820.csv` + 플랜 167행.
**catalog label-integrity 조치대상 상한 = 130 + 37 = 167 / 275.**

## 연속성 계약 (이 라운드의 종료 형태)

이 감사는 **config-scoped 판정 수집**이지 방향 종결이 아니다:
- **부활 조건 (live_trigger, INV-7)**: ①"결합기 계열 negative" 는 치환-제외 클린셋(84−34=50건)
  재판독에서 게이트-미달이 재현될 때에만 유효 negative 로 복권 ②반대로 **실제 결합 로직을 정직
  구현한 대조 실측 1건**이 치환 콤보와 유의하게 다른 분포를 내면 결합기 축은 "미측정 axis" 로
  부활 (v8.4 Lane A arm A 대조군 규약과 동형) ③catalog 처분 적용 트리거 = 도훈 confirm.
- **소비면 라우팅 (연속성 4호)**: ⑤monitoring — dup 가드 현역(등록면) + 부팅 위생 census 는
  본 감사 스크립트 재실행으로 대체 가능 · ⑥선별 라벨 — label_class/actual_factor_names 주석이
  RCMA·improve-drain 의 선별 입력이 됨 · FQ 등재 권고 2건 = (i) "치환-제외 ML 원장 재판독으로
  v8.4 죽은자리① 근거 재산정" (ii) "결합기 1건 정직 실측 대조군".
- **next_probe**: ①치환-제외 50건 클린셋으로 sharpe/mdd/oos 분포 재산출 → SOT 수치 재검
  ②적용 후 module_performance 재빌드 → RCMA 선정 변화 실측 ③dispositions 40건 재판정
  (복제본 처분의 대표-단위 통합).

## 도훈 결정 대기 (기존 catalog 167건의 처분 — June 선례대로 confirm 후 적용)

```bash
cd /c/Users/99922/OneDrive/Quant_Module_Moltbot && Rscript -e 'source("04_Research/01_reports/audits/module_catalog_dup_hash_audit_20260820/apply_catalog_dup_annotations.R")'
```

| 레버 | 대상 | 효과 |
|---|---|---|
| `--apply` (주석만) | 167건 (dup 130 + 유니크 치환 37) | meta 에 dup_hash_group/duplicate_of/label_class/actual_factor_names 기록. fr_eligible 불변 — 소비자가 스스로 걸러야 함 |
| `--apply --defr-nonrep` | 비대표 100건 | 복제본 fr_eligible=false → FR 입력면 128→30 대표만. **권고 최소선** |
| `--apply --defr-nonrep --quarantine-mismatch` | +mismatch 136건 | label≠signal 전체 격리 이동 (June 감사의 동일 옵션). 가장 정직하나 catalog 축소 폭 최대 |

적용 후속 의무: `build_module_performance.R` 재실행 + standalone_track_queue 재빌드.
추가 결정: v8.4 SOT "동일 3짝" 절의 기전 서술 정정 여부 (위 함의 절).

## 교훈 (메모리 카드 동시 적립)

- **바이트 동일 산출물의 이명 등재는 원장 계층이 아니라 실행 계층에서 태어난다** — 측정
  파이프는 치환된 입력도 정직하게 측정한다. 방어선은 등록 시점 identity 검사(hash 이명 차단).
- **감사가 수리를 만들었어도 적용이 게이트에 걸려 있으면 오염은 현역이다** — dry-run 대기
  상태 2개월. 결정 대기 항목은 시효를 갖고 재부상해야 한다.
- 구 테스트 RM04 가 오염 경로를 **정상 동작으로 박제**하고 있었다 — "동일 sim → 동일 hash
  등록 성공" 검증은 hash 결정론 검사였는데 �