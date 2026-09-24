##### RESULT 0
C11 봉쇄 (1)~(5)를 모두 적용했습니다. 코드의 시간축 수리, 이력 재빌드, 재측정은 하지 않았습니다. 운영 쓰기는 전부 쓰기 직전 재읽기 → 앵커 유일성 확인 → 원자 교체 → 파싱 diff 검증 순서로 했고, 의도하지 않은 변경은 0건입니다. git commit은 제가 하지 않았지만, 저장소의 auto-commit이 일부 변경을 이미 커밋에 넣었습니다(3788c470b, aeeb9f587, d1c4e7266, 730cd817e). decision_register는 쓰지 않았습니다.

**원장에서 다시 도출해 판정서와 대조한 결과**
- L1 오염 칸은 35칸으로 판정서와 같습니다.
  - MA01 20칸: C 18, F 2
  - pg2 15칸: B5_31 11칸 + RP_20260904_102326_skipped_base의 B4_21~24 4칸. 등급은 B 5, C 10
  - 두 목록의 중복 0
- 카탈로그 pg2 모듈 15개와 원장 pg2 15칸은 artifacts_dir로 1:1 대응합니다. B 모듈 5개는 과제에 적힌 id와 일치합니다.
- 판정서가 '미대조'로 남긴 후손도 이번에 대조했습니다. 승격 entry 17건 전부를 봤고 후손은 0건이라 `possible` 표식은 없습니다.
  - 대조 범위: 부모 칸이 오염 칸인지, carry 안의 factors·overlay, carry.source_spec 파일 내용
- 원장에서 D32·MA02·RE14·MA07을 소비한 칸은 0입니다.

## 봉쇄 목록
| 대상 | 수단 | 되돌리는 법 |
|---|---|---|
| (1) D32_Beta_VIX · MA01 · MA02 | `06_Registry/pit_quarantine.json`(PITQ-C11-20260924)을 `rf_factor_pool`이 읽어 후보에서 뺍니다. 이 풀은 B1 규칙 선정, B1 설계 재료, b1_verify가 같이 씁니다. 풀은 346종에서 343종이 됐습니다. 목록 파일이 파손되면 stop하고, 그때 러너는 격자 스냅샷 셀로 진행합니다(스냅샷에 오염 팩터 없음 확인). | 목록 항목의 status를 `released`로 바꿉니다. 복귀는 검사 F3에서 실증했습니다. |
| RE14 · MA07 | 확인만 했습니다. IC 이력이 없고 축 판정이 비횡단면이라 이미 풀 밖입니다. | — |
| 일간 fdb 오염 열 | 무인 소비 경로가 0이라 코드 격리는 하지 않았습니다. DPL 빌더와 ast_compile은 tick·스케줄·아침 체인 어디에서도 호출되지 않습니다. 대신 열 이름을 목록 `sources`에 넣었고, 이름을 참조하는 새 arm은 등재 관문에서 거부됩니다. | 같음(status) |
| (2) pg2_risk_overlay_v1 | `overlay_catalog.json` status를 active에서 suspended로 바꿨습니다(원값은 `status_before`). 규칙 픽커, 설계 카탈로그, 상주 칸 판정이 모두 active만 받으므로 B5_31은 새 entry에서 `arm_not_active`가 됩니다(재설계 라운드 포함). 다른 arm 23개와 빌트인 10종은 격리 원천을 참조하지 않습니다. | status를 `status_before`로 되돌리고 추가한 키 5개를 삭제합니다. |
| 새로 생성되는 arm | `rf_overlay_admit`이 목록의 `sources` 정규식에 걸리는 arm을 등재 거부하고 방출 원장에 사유를 남깁니다. 대상: m4·AE·regime_daily_v2·unified·macro_regime·Bear_Prob·FRED 패널, 격리 팩터 id. | 목록 status를 `released`로 바꿉니다. |
| (3) 카탈로그 15모듈 | writer 경로(`sr_with_lock`과 register_module의 `.write_json_obj`, CAS 포함)로 `fr_eligible=false`로 바꿨습니다. `contamination`에 reason `pit_invalid:C11`, `fr_eligible_before:true`, 원장 칸을 기록했고, 선례 어휘인 `grade_contaminated`(등급 문자)도 달았습니다. 등급, essence, 해시, contract는 그대로입니다. | `fr_eligible`을 `fr_eligible_before` 값으로 되돌리고, 같은 writer 경로로 추가 필드 2개를 삭제합니다. |
| (4) l2_auto 레인 | 설정 하위 키 `l2_auto.enabled`를 false로 바꾸고 `enabled_before_pause`, `paused_at`, `paused_by`, `paused_reason`(decision과 판정서 경로 포함), `resume_how`를 남겼습니다. 최상위 `enabled`는 건드리지 않았습니다. sh 게이트와 R 드라이버 모두 halt_disabled임을 실측했습니다. FR_003 요청은 이미 `done`이라 보류할 pending 요청은 없습니다. | 도훈 님 결정 후 true로 바꾸고 추가 키 5개를 삭제합니다. 재개 전에 module_performance 재빌드가 필요합니다. |
| (5) 원장 무효 표식 | `rf_mark_vintage_batch`로 표식을 붙였습니다(flag `pit_c11`, verdict `consumed`, claim·CAS 사용). writer의 허용 어휘가 충분해 확장은 필요 없었습니다. evidence에는 V-번호와 파일:줄을 넣었습니다. | append-only라 삭제 경로가 없습니다. 판정을 바꿀 때는 새 flag를 추가합니다(writer 계약). |
| — L1 | 35칸 | |
| — L2 FR_003 | n=1과 base, 2건 | |

L2 FR_003의 **base 측정에도 표식을 붙인 것은 과제 문언보다 넓게 해석한 부분**입니다. base도 같은 `run_wf_ensemble.R:85-91` Category 경로(V-05·V-06)를 썼기 때문입니다. 원치 않으시면 알려 주세요.

## 변경 파일
- `06_Registry/reinforce_auto_config.json:19-24`
- `06_Registry/overlay_catalog.json:224-229`
- `06_Registry/module_catalog.json`: 모듈 15개 블록. `pit_invalid:C11` 줄이 38519, 39961, 42378, 44945, 49312, 51279, 52721, 54163, 54330, 54422, 54514, 56031, 59048, 62065, 65982행에 있습니다.
  - writer가 동작하면서 RP_20260924_043231_17572의 null이 {}로 정규화됐습니다. 다음 등재 때도 똑같이 생기는 writer 고유 동작입니다.
- `06_Registry/reinforce_ledger_l1.json`: pit_c11 표식 35개
- `06_Registry/reinforce_ledger_l2.json`: pit_c11 표식 2개
- `06_Registry/pit_quarantine.json`: 신규
- `02_Infrastructure/validation/pit_quarantine.R`: 신규, 1-61행
- `02_Infrastructure/ops/rf_factor_arms.R`: 14, 119-136, 168-171, 184, 295행
- `02_Infrastructure/reinforcement/rf_overlay_admit.R`: 17-33, 59-66행
- `08_Tests/validation/test_pit_quarantine_c11.R`: 신규
- `08_Tests/hooks/run_all_hooks.sh:1498-1502`: SUITES 편입

JSON 파일은 CRLF를, R/sh 파일은 LF를 유지했습니다.

## 백업
모두 `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/c11_contain/` 아래에 있습니다.
- `backup_20260924_043634/`: 편집 대상 전부, `MANIFEST.md5` 포함
  - 카탈로그는 이 백업 뒤에 다른 등재가 끼어들었습니다. 그래서 카탈로그의 정확한 쓰기 직전 판은 아래 잠금 안 백업입니다.
- `module_catalog.prewrite_20260924_044048.json`: 잠금 안에서 뜬 백업
- `reinforce_ledger_l1.prewrite_20260924_044711.json` / `.postwrite_20260924_044711.json`
- `reinforce_ledger_l2.prewrite_20260924_044711.json` / `.postwrite_20260924_044711.json`
- 대상 도출 결과: `targets.json`

## 검사 결과
- **신규 `test_pit_quarantine_c11.R`: 34/34 통과**
  - F 8건: 팩터 풀 양성 대조와 위반 주입
  - A 8건: 등재 관문
  - L 11건: 운영 상태. 격리 목록이 active일 때만 돌고 해제 후에는 SKIP합니다.
  - M 7건: 원본 사본으로 돌린 대조 1건은 green, 돌연변이 M1~M6은 모두 red였습니다. 돌연변이가 크래시가 아니라 의도한 단정에서 실패하는 것도 따로 확인했습니다.
- **원장 사후 대조**(writer와 무관하게 따로 구현): pit_c11 표식을 빼면 원장이 쓰기 전과 같고, grade와 essence는 불변입니다. 표식 칸 35개와 2개가 기대 목록과 일치합니다.
- **관련 기존 검사**: 아래 14개는 전부 fail 0입니다.
  - test_rf_b1_design 18, test_rf_overlay_admit_source 20, test_rf_overlay_arms 11, test_rf_block_design 55
  - test_rf_runner_standing_adversary 85, test_rf_mechanism_map 17, test_rf_root_papers 15, test_rf_b1_carry_aware 18
  - test_overlay_probe_calendar 16, test_rf_block_design_catalog_parity 11
  - test_rf_l2_auto 8, test_rf_l2_driver 18, test_rf_mark_vintage 36
- **test_rf_b5_design_lib는 71/73**입니다.
  - 실패 2건: B6(블록 순서에 B7이 끼어든 예측)과 E11(재료 절 이름 집합)
  - 이번에 바꾼 파일과 무관해 보이지만, 변경 전 상태에서 재현해 보지는 않았습니다.
- 전체 배터리는 돌리지 않았습니다(과제 지시).

## 남은 오염 경로(봉쇄 못 한 것)
1. **원장 표식은 기록일 뿐입니다.** `rf_has_vintage_flag`를 호출하는 소비자가 0이라, 오염 칸의 essence는 다음 도구에서 여전히 읽힙니다.
   - 디렉터 계보
   - B5 설계 재료의 측정표
   - 기전 재료
   - 결합 검토
2. **`module_performance.json`(2026-09-24 생성, 654모듈)에 pg2 모듈 15개 중 14개가 남아 있습니다.** Category 라벨과 RCMA 자체도 오염입니다. L2 레인은 멈췄지만 세션에서 수동으로 run_wf_ensemble을 돌리면 소비됩니다. 재개 전에 재빌드해야 합니다.
3. `rf_director.R:117`은 `isTRUE(grade_contaminated)`만 봅니다. 선례대로 등급 문자를 넣었기 때문에 디렉터 계보 ②에는 15모듈이 남습니다(진단 전용, act=false).
4. B7 방어 슬리브의 `rf_sl_resolve`(`rf_sleeve.R:61-86`)는 factor_evidence를 직접 읽고 격리 목록은 보지 않습니다.
   - D32는 ic_bad 순위 56/77이고, 격자는 1~2위만 쓰므로 지금은 도달하지 못합니다.
   - 필터는 넣지 않았습니다.
5. **LLM이 생성하는 엔진에는 정적 관문이 없습니다.** 충실구현 엔진과 결합 기저 엔진이 격리 팩터나 국면 패널을 읽는 것을 막지 못합니다. 등재 관문은 오버레이 arm만 막습니다.
6. 엔진은 catalog status를 확인하지 않고 kind로 arm을 디스패치합니다.
   - pg2 kind를 명시한 spec(수동 세션이나 낡은 설계 파일)이 있으면 그대로 실행됩니다. 현재 미측정 칸 중 pg2를 참조하는 칸은 0입니다.
   - `rf_b5_design.sh:225` 프롬프트가 여전히 pg2를 외부 패널 본보기로 가리킵니다. 러너 파일이라 수정하지 않았습니다. 생성된 arm은 관문에서 막히지만 LLM 예산이 소모될 수 있습니다.
7. **오염 원천은 매일 계속 생산됩니다.** 코드 수리는 도훈 님 결정을 기다리는 중입니다.
   - 아침 체인 `fred_regime.R`: unified 신호와 regime_daily_v2
   - 팩터 DB 빌더: D32·MA01·MA02 같은 날짜 결합
8. **지시에 따라 범위 밖으로 둔 것:**
   - BOOK_0001의 AE·m4 게이트(`run_pg2_rebalance_full.sh`)
   - 05_Production 4파일
   - WT-D20260803_005/006
   - FR_003 결과 파일 3개(표식하지 않음)
   - 레거시 STR
   - RAMP: 스케줄 미등록, 마지막 실행 06-20
   - DPL ML과 ast_compile: 무인 호출부 0
9. **판정서가 스크래치패드(임시 경로)에만 있습니다.** 레지스트리들은 그 경로를 참조합니다. 핵심 V-번호와 파일:줄은 `pit_quarantine.json`에 직접 적어 두었습니다.

##### RESULT 1
# C11 봉쇄 적대 검증 (무결성 관점)

이 검증에서 운영 파일에는 쓰지 않았습니다. 산출물은 `scratchpad/c11_contain_verify_integrity/`에만 있습니다.

결론부터 말씀드리면, 무결성 주장의 핵심은 모두 재측정으로 확인됐고 차단할 결함은 없습니다. 원장 표식은 append-only였고, 표식 집합은 제가 독립으로 다시 도출한 집합과 같았으며, 원값도 보존됐습니다. 남은 것은 등재 관문의 우회 경로, 검사의 사각지대, 표식의 지속성 위험이며 모두 차단 사유는 아닙니다.

## 구현자 주장 재측정

| 주장 | 판정 | 재측정 근거 |
|---|---|---|
| L1 표식 35칸, append-only, essence·grade 불변 | **confirmed** | 쓰기 전 판(md5 `ec85ee65…`)은 백업 및 git `0f635173c`와 바이트 단위로 같습니다. 이것과 현재 원장을 독립 구현으로 깊이 diff했습니다. 차이 36건: 기존 `vintage_flags`에 추가 33건, 새 `vintage_flags` 키 2건, `last_updated` 1건. entry 수 63→63, attempt 수 1285→1285로 불변입니다. 표식 35건 모두 `pit_c11`/`consumed`이고 evidence에 V-번호와 파일:줄이 들어 있습니다. |
| 표식 집합 = 판정서 = 원장 재도출 | **confirmed** | 텍스트 검색 대신 구조화된 방식으로 다시 도출했습니다. `essence.spec` JSON의 `factors[].id`와 `overlay.kind`를 읽었습니다. 결과 35칸은 표식 집합과 완전히 같습니다(차집합 양쪽 0). MA01 20칸(C 18, F 2), pg2 15칸(B 5, C 10), 둘의 중복 0입니다. B 5칸의 entry 위치는 0-based 인덱스 10·58·59·60·61로 판정서 V-02와 일치합니다. D32·MA02는 소비 0입니다. MA01이 든 spec 파일은 22개로, 측정된 20칸에 NA 2칸(n=21, 25)을 더한 수입니다. 판정서의 "명세 22건"과 맞습니다. |
| 후손 0, 승격 entry 17건 대조 | **confirmed** | 승격 entry 17건의 부모 칸 중 오염 칸은 없습니다. 오염 칸 35개의 artifacts·spec 경로를 entry 수준(base_signal, carry 등)과 L2에서 참조하는 곳도 0입니다. |
| L2에 FR_003 n=1과 base 2건 | **confirmed**(과제 문언보다 넓음, 구현자가 공개함) | L2 diff는 표식 2건과 `last_updated`뿐입니다. base 표식도 근거가 있습니다. 09-12 판 엔진(`208830f80`, `588889b43`)이 82행에서 `unified_regime_signal_daily` Category를 읽습니다. |
| 카탈로그 15모듈 fr_eligible 해제, 원값 보존 | **confirmed** | 잠금 안에서 뜬 쓰기 전 판과 현재 판(git `3788c470b`와 같음)을 구조 diff했습니다. 15개 모듈이 각각 정확히 세 필드만 바뀌었습니다: `grade_contaminated` 추가, `fr_eligible` True→False, `contamination` 추가(`fr_eligible_before:true`, `reason:pit_invalid:C11` 포함). 모듈 수 865→865, 순서와 최상위 키 불변입니다. B 적격 모듈은 278→273이고, B 5개의 id는 과제 목록과 같습니다. |
| null→{} 정규화는 writer 고유 동작 | **confirmed**(구현자 서술이 조금 모자람) | 실제로는 두 필드가 바뀌었습니다: `role`, `defensive_score.n_months`. 04:36 백업에서는 직전 신규 모듈(`RP_20260924_033952_16576`)이 null이었다가 이후 쓰기에서 정규화됐습니다. 같은 패턴이므로 writer 고유 동작이 맞습니다. |
| config에서 선언 외 키 변경 0, 최상위 enabled 불변 | **confirmed** | 백업(git `906ce9091`와 같음)과 현재 판의 차이는 `l2_auto` 블록 19–24행뿐입니다. 최상위 `enabled: true`는 그대로이고 CRLF도 유지됐습니다. 04:57에 `resume_how` 문구를 한 번 더 고쳤는데, 이것도 CAS와 원자 교체로 했습니다. |
| overlay_catalog는 pg2 블록만 변경 | **confirmed** | 텍스트 diff상 `status` 변경과 키 5개 추가뿐입니다. |
| 풀 346→343 | **confirmed** | `rf_factor_pool`을 읽기 전용으로 실행했습니다. 343종이 나오고 `excluded_pit`은 D32·MA01·MA02입니다. 격리를 비운 반사실 판은 346종입니다. RE14·MA07은 IC 이력 부재와 축 판정 양쪽에서 이미 제외돼 있습니다. |
| 다른 arm 23개·빌트인은 격리 원천을 참조하지 않음 | **confirmed** | 격리 정규식 27개를 `overlay_arms/*` 전체와 `rf_cell_engine.R`에 돌렸습니다. 걸린 것은 pg2 파일 두 개뿐입니다. |
| 새 검사 34/34, M1~M6 red | **confirmed** | 스크래치 사본으로 전체 실행해 34/34 통과, rc=0이었습니다. |
| l2_auto 정지(sh와 R 모두) | **confirmed** | 러너 로그에서 04:48:08과 05:11 tick 모두 `[l2_auto] halt_disabled`입니다. R 드라이버는 `rf_l2_auto.R:30`에서 같은 조건을 봅니다. |
| 러너 정상 | **confirmed**(새 코드 경로는 라이브에서 실행 안 됨) | 봉쇄 뒤 tick 두 번(04:48:13, 05:11:59) 모두 rc=0입니다. 원장 writer의 claim은 04:47:11–17에 잡혔고, 러너는 04:48:10에 해제 표식을 보고 인수했습니다. 충돌은 없었습니다. 다만 활성 entry가 없고 ov_propose가 하루 상한에 걸려 있어서, 풀 필터와 등재 관문은 아직 라이브에서 **실행되지 않았습니다**(unverifiable). |
| test_rf_b5_design_lib 실패는 무관해 보임 | **confirmed**(정적 근거) | E11 실패의 원인은 `rf_b5_design_lib.R:780` 절 목록에 "director"가 들어가 있는데 검사는 그것 없는 목록을 기대한다는 점입니다. 이 lib는 09-21 이후 바뀌지 않았고, 구현자가 고친 파일에 의존하지 않습니다. |
| FR_003 결과 파일 3개는 "지시에 따라" 범위 밖 | **overstated** | 과제의 범위 밖 목록은 BOOK_0001, 05_Production, WT-D20260803_005뿐입니다. 판정서 안 A는 표식 항목에 "FR_003 결과 3개 파일 무효"를 넣었습니다. 과제 (5)에 없었던 것은 맞지만, "지시에 따른 제외"는 아닙니다. |
| 백업 MANIFEST | **confirmed**(사소한 흠 1) | 10개 파일 모두 OK입니다. 불일치 1건은 MANIFEST가 자기 자신의 해시를 넣은 것이라 무해합니다. |

## 발견 (심각한 순)

1. **[중] 등재 관문 정규식으로 pg2의 간접 참조를 못 막습니다.**
   - 위치: `06_Registry/pit_quarantine.json`의 sources, `rf_overlay_admit.R:62`.
   - 격리 원천 목록에 `pg2_risk_overlay` 자체가 없습니다.
   - `source(".../overlay_arms/pg2_risk_overlay.R")`로 pg2 코드를 불러오는 생성 arm은 `pitq_source_hits` 결과가 `[]`입니다. `bypass.R`로 실측했습니다(대조로 넣은 ae_regime, unified, regime_daily_v2는 모두 걸림).
   - 엔진은 카탈로그 status를 보지 않고 kind로 arm을 실행합니다. `rf_b5_design.sh:225` 프롬프트도 pg2를 본보기로 가리킵니다. 따라서 AE·m4 패널이 새 arm을 거쳐 다시 소비될 경로가 남아 있습니다.
2. **[중] 카탈로그 표식이 재등재 한 번이면 조용히 지워집니다.**
   - 위치: `register_module.R:182`(`obj$modules[[key]] <- entry`, 항목 통째 교체), `:489`(`fr_eligible=TRUE`).
   - 15개 id 중 하나라도 다시 등재되면 `contamination`이 사라지고 fr_eligible이 복귀합니다.
   - 무인 재등재 경로는 찾지 못했습니다. `backfill_lean_modules.R`은 이미 등재된 id를 기본으로 건너뜁니다. 그래서 잠재 위험입니다. 검사 L5·L6이 격리 active 동안에는 이를 탐지합니다.
3. **[하] 새 검사의 돌연변이 사각지대**: 독립 돌연변이 7종을 CORE 모드로 돌렸습니다.
   - red: X1(목록 판독 생략), X5(`.R` 스캔 제거), X7(필터 반전).
   - **green으로 생존**:
     - X2: 판독기가 첫 팩터만 반환. 픽스처에 격리 팩터가 1종뿐이라 못 잡습니다. L2가 운영 판독기에 대해서만 잡습니다.
     - X3: status가 없으면 released로 취급. 픽스처가 status를 항상 명시합니다.
     - X4: 관문이 `.arm.json`을 스캔하지 않음. A 절의 오염 참조가 `.R`에만 있습니다.
   - M 자식 프로세스는 CORE로만 돌기 때문에, 판독기를 변형해도 L 절에는 반영되지 않습니다(`test_pit_quarantine_c11.R:155`의 L 절은 운영 판독기를 씁니다).
4. **[하] 재도출할 수 없는 사각지대를 공개하지 않았습니다.**
   - 측정된 L1 칸 37개는 읽을 수 있는 spec이 없습니다. `RP_20260829_122020_9192`와 `_rulefast`에 spec 필드가 없는 28칸, `RP_20260830_…_promo1r`의 spec 파일이 사라진 9칸입니다.
   - artifacts 텍스트에는 팩터 id가 남지 않습니다. 양성 대조로 확인했습니다: MA01 칸의 artifacts에서 MA01이 0회 나옵니다.
   - 그래서 이 37칸에서 MA01 소비는 **unverifiable**입니다. 날짜가 08-29~31이라 위험은 낮습니다. 구현자의 도출 방식도 같은 사각지대가 있는데 공개하지 않았습니다.
5. **[정보] 변경 줄 번호 소폭 차이**: `rf_overlay_admit.R`의 실제 범위는 17–34행, 59–67행입니다(보고 17–33, 59–66). 나머지 줄 번호(카탈로그 15곳, config 19–24, overlay_catalog 224–229, SUITES 1498–1502, rf_factor_arms 14/119–136/168–171/184/295)는 일치합니다.
6. **[정보] 커밋 상태**: 원장, 격리 목록, 테스트, SUITES 변경은 auto-commit `5493283bf`(05:09:55)에 모두 들어갔습니다. 구현자가 한 커밋은 아닙니다. decision_register는 04:21:30 이후 바뀌지 않았고, BOOK 경로도 변경이 없습니다.

## 검증 산출물 (`scratchpad/c11_contain_verify_integrity/`)
- `ldiff.py`, `marks_l1.json`, `marks_l2.json`: 원장 깊이 diff
- `scan_specs.py`, `independent_hits.json`: 구조화 재도출
- `lineage.py`: 후손 대조
- `catdiff.py`, `cat_changed.json`: 카탈로그 diff
- `pool_check.R`: 풀 크기 확인
- `parse_check.R`: 수정 파일 파싱
- `bypass.R`: 관문 우회 실측
- `t_orig.R`, `t_orig.log`: 새 검사 34/34 재현
- `mut/X1~X7_*.R`, `mut/*.log`: 독립 돌연변이
- 스냅샷: `l1_git_0f635173c.json`, `l1_now.json`, `l2_git_af9205a62.json`, `l2_now.json`, `cat_now.json`, `cat_git_3788c470b.json`

BLOCKING: 없음

##### RESULT 2
## C11 봉쇄 완결성 적대 검증

**판정:** 봉쇄 (1)~(5)는 이미 알려진 오염 대상에 대해서는 전부 실측으로 성립합니다. 다만 새 arm을 막는 등재 관문은 우회 경로가 넓고, 무인 레인 두 개(B5 설계·일간 arm 생성)가 그 우회로를 그대로 쓸 수 있습니다. 운영 파일은 쓰지 않았고, 모든 실험은 스크래치 `c11_contain_verify_coverage/` 안의 사본으로만 했습니다.

### 구현자 주장 재측정

| 주장 | 판정 | 근거 |
|---|---|---|
| L1 오염 35칸. MA01 20칸(C 18, F 2) + pg2 15칸(B5_31 11칸 + `RP_20260904_102326_skipped_base` B4_21~24 4칸). 두 목록 중복 0 | confirmed | 원장 attempt 1,286건의 spec 파일을 독립으로 스캔해 오염 칸 35칸을 찾았고, 표식 35칸과 정확히 같습니다(`scan_specs.py`). 판독 못 한 spec 99건은 NA 실패칸과 구 entry입니다 |
| 카탈로그 15모듈과 원장 15칸이 1:1 대응. MA01 칸은 카탈로그에 없음 | confirmed | 실행 키로 대조했습니다. 카탈로그 전체(865개)를 스캔해도 오염 참조는 이 15개뿐입니다 |
| 승격 사슬·carry 후손 0 | confirmed | 모든 entry의 carry와 carry.source_spec에서 격리 원천이 걸리지 않았습니다. 아직 이월되지 않은 소진 entry 5건(idx 10·11·26·47·61)도 PORT_t 승자가 모두 청정해서, 앞으로 승격되더라도 오염이 넘어가지 않습니다 |
| 원장에서 D32·MA02·RE14·MA07 소비 0 | confirmed | 같은 spec 스캔 결과입니다 |
| 후보 풀 346 → 343, released로 복귀 | confirmed | 운영 풀은 343종이고, 시드 오프셋 41개 전부에서 격리 팩터가 선정되지 않았습니다. 목록을 released로 바꾼 샌드박스에서는 346종으로 돌아옵니다(`t_pool.R`) |
| b1_verify가 격리 팩터 설계를 기각 | confirmed | 구현자 검사는 D32만 봤습니다. 제가 MA01·MA02·D32를 넣으면 셋 다 rc=1, 청정 팩터(M01)는 rc=0입니다(`b1_jlog.jsonl`) |
| RE14·MA07은 이미 풀 밖 | confirmed | IC 이력 없음(no_ic) + 축 판정 비횡단면(axis_excl)입니다 |
| pg2 suspended로 규칙 픽커·설계·상주 칸 모두 차단 | confirmed | 샌드박스 설계 파일에 pg2를 넣으면 3칸 중 1칸만 만들어지고, pg2를 active로 되돌린 대조에서는 3칸이 만들어집니다. 상주 칸 판정은 `arm_not_active`이고 대조는 `first_b5_round`입니다(`t_b5.R`). 04:37 정지 이후 새로 생긴 spec에 pg2는 0건입니다 |
| **등재 관문이 "m4·AE·regime_daily_v2·unified·macro_regime·Bear_Prob·FRED 패널"을 거부** | **refuted(부분)** | 아래 F1 |
| fr_eligible을 writer 경유로 해제, 원값 보존 | confirmed | 쓰기 직전 백업과 비교하면 대상 15개는 3개 필드만 바뀌었습니다. 대상 밖 `RP_20260924_043231_17572`에서 null이 {}로 바뀐 것도 구현자가 공개한 대로입니다 |
| l2_auto 정지, 최상위 enabled 불변 | confirmed | 백업 대비 최상위 키 중 바뀐 것은 `l2_auto`뿐입니다. sh 게이트는 `l2.enabled`를 읽습니다. 요청 상태는 done입니다 |
| L2 FR_003 표식 2건, 원장 append-only | confirmed | pit_c11 표식만 빼면 쓰기 전 원장(63 entry)과 같습니다 |
| 신규 검사 34/34 | confirmed | 재실행에서 rc=0입니다 |
| 기존 관련 검사 14개 fail 0, b5_design_lib 71/73 | unverifiable | 다시 돌리지 않았습니다 |
| "R/sh 파일은 LF 유지" | overstated(사실 오류, 무해) | 수정한 R 파일, 검사 파일, `run_all_hooks.sh` 모두 CRLF입니다. 수정 전 판(HEAD 이전)도 CRLF라 줄끝은 보존됐고, 진술만 틀렸습니다 |

### 발견 (심각도순)

**F1 [높음·차단] 생성 arm 등재 관문을 우회할 수 있습니다.**
- 원인: `rf_overlay_admit.R:28-31`은 `<kind>.R`과 `<kind>.arm.json`의 텍스트만 정규식으로 봅니다. 그런데 `pit_quarantine.json`의 sources 정규식에 다음이 빠져 있습니다.
  - 실제 FRED 저장소인 `.cache/fred_macro.parquet`와 `fred_macro_wide.parquet`. 둘 다 매일 갱신되고, VIX·StL_Fin_Stress·Chi_Fin_Cond·Init_Claims 열이 있습니다. 정규식에 있는 `\bmacro_fred\b`는 `fred_macro`와 맞지 않습니다.
  - AE 핀 `fred_macro_wide_pin20260718wt006.parquet`
  - `regime_jump_daily.parquet`(JM_State 열)
  - unified에서 파생된 `regime_current.json`
  - `regime_forecast_series_v1vix.parquet`
  - `pg2_risk_overlay.R` 자체를 source하는 경우
  - BOOK 생성기 `forward_weights_D3_M4gAE.R`
- 샌드박스 실측(`t_gate.R`):
  - 변형 13개 중 대조 3개만 걸리고 10개는 통과했습니다.
  - `rf_overlay_admit`를 끝까지 돌리면 fred_macro_wide(VIX 열)·pg2 source·JM_State 세 변형이 **ADMIT(ok=TRUE)**로 카탈로그에 등재됐습니다. m4 대조는 REJECT였습니다.
- 무인 레인 쪽 상황:
  - `rf_b5_design.sh:225`와 `rf_b5_design_lib.R:756`(구현자가 언급하지 않은 곳)이 pg2를 "외부 패널 + PIT 가드" 본보기로 제시합니다.
  - 그래서 정지한 pg2 신호가 새 arm id로 다시 들어올 수 있습니다. 하류의 assert_overlay_pit와 G2 T2는 날짜 라벨만 비교하므로 이를 잡지 못합니다(판정서 ③).
- 가능성: 기존 생성 arm 22개 중 외부 데이터를 쓴 것은 0개라 낮습니다. 하지만 두 레인이 무인으로 계속 돕니다.
- 수리안: 정규식에 `\bfred_macro`, `\bpg2_risk_overlay\b`, `M4gAE`, `WT_D20260718_007`, `\bregime_jump_daily\b`, `\bJM_State\b`, `\bregime_current\b`, `\bregime_forecast_series`를 추가하고, 프롬프트의 본보기를 바꿉니다.

**F2 [중간] 자동등록 경로에 방어가 없습니다.**
- `rf_factor_autoregister.R`(호출부 `rf_replication_verify.R:414-417`)은 격리 목록을 읽지 않습니다.
- 충실구현·결합 LLM 엔진(`rf_replication_auto.sh`, tick 32행)이 `load_month_factors`로 D32·MA01·MA02를 읽거나 FRED 패널을 같은 날짜로 결합해 B+를 내면, 그 신호가 새 custom id로 등록돼 B1 풀에 들어갑니다. id 필터 밖이라 오염이 세탁됩니다.
- 과제 (1)이 명시한 "자동등록 경로"입니다. 현재는 RP_* 엔진 전부와 `custom_factors.json`에 참조가 0이라 잠재 경로입니다.
- 구현자 보고의 남은 경로 5는 "LLM 엔진에 관문 없음"까지만 적었고, B1 풀로 세탁되는 경로는 적지 않았습니다.

**F3 [중간·구현자 인정] 오염 essence가 여전히 무인 결정 입력으로 쓰입니다.**
- `rf_combination_review.R:45-59`는 논문별 PORT_t 최고 셀을 vintage 표식과 무관하게 고릅니다.
- 실측으로 `RP_20260902_191247_combo`의 대표 셀이 B3_13(MA01 오염, PT 1.081)입니다. 이 값이 결합 후보 선정과 `rf_combination_launch.R:104-111`의 best_parent_t에 들어갑니다.
- 승격 승자 선정(`reinforce_auto_next_paper.R:69-72`)도 vintage 표식을 보지 않지만, 위 확인대로 현재 승자는 청정합니다.

**F4 [낮음] 카탈로그 재등재가 해제 표식을 덮어씁니다.**
- `register_module.R:182`는 같은 id를 전체 치환 upsert합니다. 같은 strategy_id로 다시 등재되면 fr_eligible=false와 contamination이 사라집니다. 격리 목록과는 연동되어 있지 않습니다.
- 현재 무인 재등재 경로는 없습니다. 셀 id가 매번 새로 생기기 때문입니다.

**F5 [낮음·구현자 인정] 디렉터 계보에 오염 모듈이 남습니다.**
- `rf_director.R:117`은 `isTRUE(grade_contaminated)`만 봅니다. 값이 등급 문자열이라 제외되지 않습니다. 선례 3모듈도 같은 상태입니다. 진단 전용(act=false)입니다.

**F6 [낮음·구현자 주장 확인] B7 방어 슬리브는 격리 목록을 보지 않지만 지금은 도달하지 못합니다.**
- `rf_sleeve.R:61-86`은 격리 목록을 읽지 않습니다.
- D32는 ic_bad 순위 56/77이고 격자는 1~2위만 씁니다. MA01·MA02는 category가 regime이라 자격 밖입니다.

**F7 [정보] module_performance의 pg2 모듈은 다음 일간 리프레시에서 자동으로 빠집니다.**
- 현재 `module_performance.json`에 pg2 모듈 14개가 남아 있습니다.
- `daily_refresh.sh:870`이 매일 무조건 재빌드하고, 빌더가 fr_eligible을 보기 때문에 다음 리프레시에서 자동 제거됩니다. 구현자의 "재개 전 재빌드 필요"는 맞지만 이 자동 해소 사실은 빠져 있습니다.

### 증거
스크래치 `C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/c11_contain_verify_coverage/` 아래:
- `t_gate.R`: 관문 우회 13변형과 E2E 등재
- `t_pool.R`: 운영 풀과 released 대조
- `t_b5.R`: B5 설계 소비와 상주 칸 판정
- `scan_specs.py`: 원장 spec 전수 스캔
- `b1_jlog.jsonl`: b1_verify 주입 결과
- `test_run2.log`: 신규 검사 34/34

BLOCKING: 생성 오버레이 arm 등재 관문의 정규식 누락 — fred_macro(_wide).parquet·regime_jump_daily(JM_State)·regime_current.json·regime_forecast_series·pg2_risk_overlay.R source·M4gAE 생성기 참조가 통과해, 정지한 pg2/FRED 신호가 무인 B5 설계·arm 생성 레인에서 새 arm으로 등재될 수 있음(샌드박스 E2E ADMIT 3건 · rf_overlay_admit.R:28-31 · 06_Registry/pit_quarantine.json sources)

##### RESULT 3
## 수리 결과 (C11 봉쇄 · 적대 검증 F1 차단 결함)

차단 결함이던 생성 arm 등재 관문의 정규식 누락을 막았습니다. 코드는 한 줄도 고치지 않았고, 격리 목록 `06_Registry/pit_quarantine.json`의 `sources`에 정규식 18개를 추가하는 방식으로 봉쇄했습니다(각 항목에 `amend: "C11-F1"`). 같은 관문을 무인 B5 설계 레인(`rf_b5_design_lib.R:965`)과 일간 arm 레인(`rf_overlay_admit_cli.R`)이 함께 씁니다. 수리한 뒤 검증자의 `t_gate.R`를 그대로 다시 돌렸더니 오염 변형 12종이 모두 걸렸고, E2E로 넣은 4종은 모두 REJECT됐으며 카탈로그에는 아무것도 등재되지 않았습니다.

**1차: 검증자가 보인 우회 변형 13개**

| 추가한 정규식 | 판정서 근거 | 막는 것 |
|---|---|---|
| `fred_macro` | V-07·V-08 | `fred_macro.parquet`, `fred_macro_wide.parquet`(VIX·스트레스 열), AE 핀. 앞 경계가 없어 `load_fred_macro` 같은 함수명도 걸립니다 |
| `pg2_risk_overlay` | V-02 | pg2 파일을 source하거나 `overlay_expo_pg2_risk_overlay()`를 부르는 경우 |
| `M4gAE` | V-03·V-04 | BOOK 생성기 |
| `WT[-_]D20260718_007` · `\bae_regime_` | V-03 | AE 패널 디렉터리와 AE 생산자 전부 |
| `WT[-_]D20260430_001` | V-04 | m4를 계산하는 factor_engine |
| `\bregime_jump_daily\b` · `\bJM_State` | V-10 | 점프 모델 산출물과 그 국면 열 |
| `\bregime_current\b` | V-05 | `regime_current.json`(unified_daily에서 파생) |
| `\bregime_forecast` | V-10 | 국면 예측기와 그 산출물 |
| `\bFRED_MRS\b` | V-05 | unified 신호의 FRED 성분 열 |
| `module_performance` · `(module_regime\|regime_module)_admission` | V-06 | 모듈 성과와 RCMA |

**2차: 같은 계열인데 검증자가 짚지 않은 경로 5개**

arm 환경의 부모는 globalenv입니다(`rf_cell_engine.R:565`). 그리고 `run_paper_replication.R:57-61`이 `config.R`와 `backtest_harness.R`를 전역으로 불러옵니다. 그래서 arm은 파일명을 쓰지 않고 이미 로드된 이름만으로 오염 패널에 닿을 수 있습니다.

| 추가한 정규식 | 판정서 근거 | 막는 것 |
|---|---|---|
| `(?<![A-Za-z0-9])fred_` | V-07 | `FRED_MACRO_CACHE`, `FRED_REGIME_CACHE`, `load_fred_*`, `compute_fred_mrs_daily` |
| `(?<![A-Za-z0-9])macro_regime` | V-14 | `load_macro_regime()`(`backtest_harness.R:212`). 기존 `\bmacro_regime\b`는 앞의 `load_`를 놓칩니다 |
| `\bREGIME_SIGNAL_CACHE\b` | V-05 | `config.R:81`의 전역 상수 |
| `\bregime_signal\.R\b` | V-05 | unified 생산자 파일 |
| `\b(ctx_providers\|build_ctx_extras)\b` | V-07, 판정서 1-3 잠재 | FRED를 읽는 macro 컨텍스트 공급자 |

**과잉 봉쇄 확인**
- 등재된 운영 arm 44파일(pg2 제외)과 국내 패널(msm·benchmark·rawdata)은 한 건도 걸리지 않습니다.
- 검증자 변형 중 `msm_daily_latest`는 격리하지 않았습니다. `msm_daily_refit.R:59`를 보니 benchmark만 읽는 국내 계열입니다.

## 봉쇄 목록
| 대상 | 수단 | 되돌리는 법 |
|---|---|---|
| 생성 arm 등재 관문의 누락 원천(위 18개) | 격리 목록 `sources`에 정규식을 추가했습니다. 기존 `rf_overlay_admit` → `pitq_source_hits` 경로가 그대로 읽어 등재를 거부합니다 | `sources`에서 `amend == "C11-F1"`인 항목과 `amendments` 항목을 지웁니다. 원본은 백업에 있습니다. 격리 전체 해제는 기존대로 status를 `released`로 바꿉니다 |

## 변경 파일
- `06_Registry/pit_quarantine.json`
  - `:229-373`: sources 18개 추가
  - `:859-870`: `amendments[C11-F1]`(사유, 증거, 되돌리는 법)
  - CRLF를 유지했습니다. 추가분과 amendments를 빼면 백업과 같습니다(구조 대조로 확인).
- `08_Tests/validation/test_pit_quarantine_c11.R`(LF 유지)
  - `:13-25`: 헤더
  - `:145-152`: A9(참조가 `.arm.json`의 external_data에만 있어도 거부)
  - `:236-300`: L11~L13
  - `:331`: M7
- `run_all_hooks.sh`는 이미 SUITES `:1502`에 등록돼 있어 바꾸지 않았습니다. R 코드와 러너 파일도 바꾸지 않았습니다.

## 백업
`C:/Users/99922/AppData/Local/Temp/claude/C--Users-99922-OneDrive-Quant-Module-Moltbot/be2e88bf-6a4c-44e5-a6ff-6aae164c14ca/scratchpad/c11_contain/repair_20260924_052644/`
- 수정 전 `pit_quarantine.json`과 테스트 파일, `MANIFEST.md5`
- 수정 스크립트와 평가 스크립트: 같은 상위 폴더의 `repair_eval/`

## 검사 결과
- **`test_pit_quarantine_c11.R`: 40/40 통과**(종전 34 + 신규 6). 러너 형식 env(QM_ROOT 슬래시 경로, 빈 R_ENVIRON_USER)로 돌렸습니다.
  - L11 재현: 운영 목록이 우회 변형 21종을 전부 잡습니다.
  - L11b 대조: 등재 arm과 국내 패널은 0 적중입니다.
  - L12 E2E: 검증자가 ADMIT시켰던 3종(fred_macro_wide VIX, pg2 source, JM_State)이 REJECT되고, 청정 대조는 ADMIT됩니다.
  - L13 데이터 돌연변이: C11-F1 정규식을 뺀 목록이면 21종이 모두 다시 통과해 red가 됩니다.
  - A9와 M7: 관문이 `.arm.json`을 읽지 않게 바꾼 돌연변이가 A9 단정에서 정확히 red가 되는 것을 따로 확인했습니다. 검증 2가 찾은 X4 생존 돌연변이를 이제 잡습니다.
- **`test_rf_overlay_admit_source.R`: 20/20.** 처음 돌렸을 때 7건이 실패했는데, Git Bash가 넘긴 역슬래시 QM_ROOT 때문이었습니다. 슬래시 경로로 다시 돌리니 전부 통과했고, 이번 변경과는 무관합니다.
- **운영 상태**: `overlay_catalog`, 방출 원장, `overlay_arms`는 변경 0입니다. B1 풀은 343종 그대로입니다(factors 불변).

## 남은 오염 경로(봉쇄 못 한 것, 차단 결함 아님)
1. **정규식 관문은 텍스트만 봅니다.**
   - 격리되지 않은 도우미 파일을 거쳐 오염 패널을 읽는 2단 간접 경로는 못 잡습니다. 예: `ramp_shumulvey_features.R`의 `smv_load_usvix`.
   - 문자열을 쪼개 경로를 만드는 경우도 못 잡습니다.
   - source된 파일까지 따라가 검사하는 방식은 도입하지 않았습니다. 프롬프트가 권장하는 `overlay_pit_guard.R`에 "BearProb"라는 문자열이 있어서, 그렇게 하면 모든 arm이 거부됩니다.
2. **설계 프롬프트가 여전히 pg2를 본보기로 가리킵니다**(`rf_b5_design.sh:225`, `rf_b5_design_lib.R:756`). 러너 파일이라 수정하지 않았습니다.
   - 이제 그런 arm은 등재에서 거부되지만 LLM 예산이 소모됩니다.
   - basis에 pg2를 언급하기만 해도 거부되므로 과잉 봉쇄 가능성이 있습니다.
3. **엔진은 카탈로그 status를 보지 않고 kind로 arm을 실행합니다**(구현자 보고의 남은 경로 6).
4. **검증 1의 F2~F7은 비차단이라 손대지 않았습니다.**
   - F2: 자동등록 경로
   - F3: 결합 검토가 오염 essence를 소비
   - F4: `register_module` upsert가 표식을 덮어씀
   - F5: 디렉터 계보
   - F6: B7 방어 슬리브
5. **git commit은 하지 않았습니다.** 저장소 auto-commit이 두 파일을 담을 수 있습니다.

RESIDUAL: 없음