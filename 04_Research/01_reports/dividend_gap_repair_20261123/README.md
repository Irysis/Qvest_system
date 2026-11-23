# 배당 여섯 분기(2012Q3~2013Q4) 보충 — 인프라 반영

도훈 11-23 "성장 지표랑 배당 데이터 수리하고 가자" · "1. 제대로 된 퀀티 세팅으로 (가)안 실행" · "1번 배당 수리반영".
판 표식 = `FUNDAMENTAL-DIV-GAP-SUPPLEMENT-20261123`(범위 all — 재무 캐시가 바뀌므로 캐시를 직접 읽는 엔진까지 닿는다 · 오늘 선례 두 건과 같은 범위).

## 무엇을 · 왜

- 퀀티 재무 v2 의 피어 배치 책은 배당 시트 다섯(CashDivTotal · CashDivCommon · AdjDPS · AdjDPSFinal · AdjDPSInterim)이 기간 열 201209~201312 에서
  '#INVALID OPTION' 을 돌려준다(코드 접미와 무관). 그래서 원천 표 · 재무 캐시 · 배당을 쓰는 팩터에 그 여섯 분기가 비어 있다.
- 같은 항목을 시계열(Company) 배치 + Base Date FQ0 으로 조회하면 값이 온다. 네 항목(중간 배당 제외 — 시계열 배치에서 뜻이 다르다)을 받아
  보충 적재기로 원천 표에 넣는다. 퀀티 파일이 기준이고 값은 고치지 않는다.
- 코드(커밋 `d56251674`): `02_Infrastructure/data/qw_fund_v2_div_supplement.py`(적재 · 관문) · `qw_fund_v2_ingest.py`(피어 통째 재적재가 보충 칸을 지우지 않게 보호) ·
  `qw_updatefile_registry.json::fundamentals_v2.ts_supplements` · 책 = `03_Universe/Fundamental_v2/FundV2_DIV_TS_201209_201312_{a,b}.xlsx`.

## 순서와 관문 — 재개 저널(단계가 끝나면 '상태'를 채운다)

밤 갱신(00:03~)과 겹치지 않게 **밤 갱신이 끝난 뒤** 한 묶음으로 돌린다. 원장은 ② 직전에 연다(열려 있는 채로 밤 갱신이 돌면 [6v] 가 실패 스텝으로 센다).
무거운 단계(④ · ⑧ · ⑨)는 세션과 떼어 띄우고(WMI) 끝을 기다린다. 한 번에 무거운 작업 하나.

| # | 단계 | 명령 · 산출 | 관문(어기면 멈춘다 — 원장은 열린 채로 둔다) | 상태 |
|---|---|---|---|---|
| 0 | 사전 점검 | 밤 갱신 끝 · 다른 팩터 빌드 없음 · 원장 열린 줄 0 · 가용 메모리 | 밤 갱신이 돌고 있거나 다른 수리가 열려 있으면 기다린다 | |
| 1 | 음성 대조 | 탐침(아래) 2달 — 지금 캐시로 다시 계산한 값 = 저장값 | 달라진 팩터 0(11-23 23:13 에 2014-06 한 달은 확인 — 0) | |
| 2 | 원천 반영 | 원천 표 둘 사본 → `qw_fund_v2_div_supplement.py --root <루트>` | META 신규 59,199 · INFO 신규 19,733 · 변경 0 · 삭제 0(예행과 같은 수) | |
| 3 | 원장 열기 | `06_Registry/factor_db_vintage.json` 에 한 줄(completed_at = null) | 계약이 읽힌다(`fdv_ledger`) | |
| 4 | 캐시 재생산 | `Rscript 02_Infrastructure/data/fundamental_produce_v2.R` → 옛 캐시 = `.cache/fundamental_backup/<시각>/` | rc 0 · 후보 검사 통과 | |
| 5 | 캐시 대조 | `cache_diff.py <옛 캐시 폴더> .cache <out.json>` | 값이 생긴 항목 = 배당 원계정과 그 파생뿐 · 사라진 값 0 · Factor_Date 변화 = 기간 202609 행뿐(달력 꼬리 — 아래 예행) | |
| 6 | FF 요인 | `Rscript --no-save 02_Infrastructure/data/build_kr_factor_returns.R`(분기 표 md5 가 바뀌므로) | rc 0 · meta md5 = 새 분기 표 | |
| 7 | 영향 팩터 탐침 | 표본 달 모의 실행 → `repair_spec.json`(대상 · 모듈) | 달라진 팩터가 배당을 쓰는 팩터로 설명된다 · 대조 달(영향 밖)은 0 | |
| 8 | 월간 부분 재빌드 | `QVEST_RFS_SPEC=<repair_spec.json> bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh --no-wait --workers 3` → 이번 달은 `rebuild_factor_subset.R --months <이번 달>` 따로 | 요약 result = 성공 · IC · 대응표 · 결합용 뷰 rc 0 | |
| 9 | 일간 단계 F | `cd 02_Infrastructure && Rscript -e "source('factor_db/factor_db_daily_phaseF_fundamental.R')"`(약 190분) | rc 0 · 443달 | |
| 10 | 검증 | 일간 = 월간 월말 값(대상 팩터 · 영향 달 + 대조 달) · 이번 달 일간 파일의 마지막 날짜 = RAWDATA 마지막 날짜 · `factor_db_vintage_coverage.py` | 차이 0 · status=OK | |
| 11 | 닫기 | 원장 completed_at · 등록부 `ts_supplements[].status` = loaded · 이 문서 · 커밋 · 텔레그램 1통 | | |
| 12 | 연구 쪽 | AI 팩터 연구의 위험 모형 1~3부 재실행(연구 캐시의 보충 표가 쓰이지 않게 됨을 확인) | | |

### 명령(루트 = `G:/OneDrive/Quant_Module_Moltbot` · Git Bash)

```bash
RS="C:/Program Files/R/R-4.6.2/bin/Rscript.exe"; PY=.venv_qvest_ml/Scripts/python.exe; RD=04_Research/01_reports/dividend_gap_repair_20261123
# 2 — 원천 표 사본을 먼저 둔다
B=.cache/fundamental_backup/$(date +%Y%m%d_%H%M%S)_pre_div_supp; mkdir -p "$B/qw_fund_v2"
cp -p .cache/qw_fund_v2/FundV2_META.parquet .cache/qw_fund_v2/FundV2_INFO.parquet "$B/qw_fund_v2/"
"$PY" -X utf8 02_Infrastructure/data/qw_fund_v2_div_supplement.py --root G:/OneDrive/Quant_Module_Moltbot
# 4
QM_ROOT="G:/OneDrive/Quant_Module_Moltbot" "$RS" 02_Infrastructure/data/fundamental_produce_v2.R > .cache/scheduler_logs/div_gap_produce.log 2>&1
# 5
"$PY" -X utf8 $RD/cache_diff.py .cache/fundamental_backup/<시각> .cache $RD/cache_diff.json
# 6
QM_ROOT="G:/OneDrive/Quant_Module_Moltbot" "$RS" --no-save 02_Infrastructure/data/build_kr_factor_returns.R > .cache/scheduler_logs/div_gap_krf.log 2>&1
# 7 — 탐침 사양은 스크래치에만 둔다(대상 = 재무 계열 전부 · 쓰기 실행 금지) · 기록도 스크래치(--log)
QVEST_RFS_SPEC=<스크래치>/probe_spec.json QM_ROOT="G:/OneDrive/Quant_Module_Moltbot" "$RS" 02_Infrastructure/factor_db/rebuild_factor_subset.R \
  --months <표본 달> --dry-run --log <스크래치>/probe.jsonl --no-hash        # 한 달 약 60초 · 팩터별 풀이 = probe_read.py
```

```powershell
# 8 · 9 — 세션과 떼어 띄운다(도구 셸의 자식은 도구가 끝나면 함께 죽는다)
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '"C:\Program Files\Git\bin\bash.exe" -c "cd /g/OneDrive/Quant_Module_Moltbot && QVEST_RFS_SPEC=04_Research/01_reports/dividend_gap_repair_20261123/repair_spec.json bash 02_Infrastructure/factor_db/run_factor_subset_repair.sh --no-wait --workers 3 > .cache/scheduler_logs/div_gap_subset.out.log 2>&1"' }
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = '"C:\Program Files\Git\bin\bash.exe" -c "cd /g/OneDrive/Quant_Module_Moltbot/02_Infrastructure && { echo START $(date); \"/c/Program Files/R/R-4.6.2/bin/Rscript.exe\" -e \"source(''factor_db/factor_db_daily_phaseF_fundamental.R'')\"; echo RC=$? END $(date); } > ../.cache/scheduler_logs/div_gap_phaseF.log 2>&1"' }
```

## 도구 확인 (11-23 밤 · 운영 데이터 무접촉)

- `cache_diff.py` 양성 대조: 오늘 낮 선례의 옛 캐시(`.cache/fundamental_backup/20261123_pre_share_lag/`) 대 지금 캐시 →
  분기 표 값 40,324개 생김(57항목) · Factor_Date 변화 0 · BuybackRatio 사라짐 · TreasuryShareRatio 값 바뀜 · 연간 표는 그 둘뿐 —
  선례 기록(`fundamental_derived_verify_20261123/README.md`)과 같다. 116초.
- 탐침 음성 대조: 지금 캐시로 2014-06 을 네 모듈(fundamental · value · defense · risk)로 모의 재계산 → 만들어진 145팩터 모두 저장값과 같음
  (바뀜 0 · 생김 0 · 사라짐 0 · 61초). 요약 줄의 '바뀜 −93'은 값이 ±1 인 행이 '그대로'와 '역수 · 부호 반전'에 겹쳐 세어진 것이다 — 팩터별로 다시 센다(`probe_read.py`).
- 보충 적재 예행(실제 원천 표의 사본): 신규 78,932행 · 변경 0 · 삭제 0 · 창 밖 행 동일(커밋 `d56251674` 메시지).
- 분기 표 생산기 예행(스크래치 — 보충을 넣은 원천 표 사본을 `build_fundamental_v2.py --v2-dir … --out-dir …` 로 · 운영 분기 표 무접촉 · 27초):
  - 행 19,245,658 → 19,324,590. 늘어난 78,932행 = 배당 네 항목 × 여섯 분기(기간마다 항목당 3,265~3,312행) · 사라짐 0 · 값 바뀜 0.
  - 여섯 분기의 (종목, 기간) 20,250개에서 Factor_Date 는 항목과 무관하게 하나다 — 보충 행은 그 분기의 다른 항목과 같은 날짜를 받는다(받은 날이 아니다).
    배당 행만 있는 (종목, 기간)은 0개. 보충 값 = 0 이 70,569행 · 양수 8,363행(분기 단독 값이라 기말 분기에 몰린다) · 음수 · 결측 0.
  - 예상 밖 차이 하나: 기간 202609 의 Factor_Date 33,117행이 2026-12-30 → 2027-01-01. 법정기한 11-14(토)가 달력에 새로 들어온 11-16(월)로 넘어가
    45일 뒤가 12-31 이 된 것이다 — 달력 끝을 넘는 날짜는 분기 표를 다시 만들 때마다 다시 매겨진다. 두 날짜 모두 아직 오지 않아 지금 팩터 값에는 닿지 않는다.
    단계 5 의 캐시 대조에서는 202609 행(원계정 + 파생)의 날짜 변화로 보인다.

## 배당을 읽는 곳(정적 확인 — 실측은 단계 7)

- 재무 캐시 파생: `PayoutRatio` · `DividendToEquity` · `DPS` · `CashDivCommon_Growth` · `AdjDPS_Growth` · `Delta_PayoutRatio`(`build_fundamental_caches.R`).
- 팩터(`compute_fundamental.R`): `V11_Shareholder_Yield` · `V17_Payout_Ratio` · `V23_RAFI_Weight`(단면 몫 평균 — 그 달 전 종목 값이 바뀐다) · `Q23_Sustainable_Growth`.
  합성 `Q08` · `GR07` 의 구성 팩터에는 없다.
- 가용일: 분기 표 생산기는 가용일을 (종목, 기간) 단위로 매긴다 → 보충 행도 그 기간의 다른 항목과 같은 날짜를 받는다(받은 날이 아니다).

## 남은 빈칸

- `AdjDPSInterim`(수정 중간 주당배당) 여섯 분기는 채우지 않았다 — 시계열 배치에서는 결산월 행에만 값이 와 뜻이 다르다.
  피어 표에서 두 항목이 다 있는 칸은 AdjDPSInterim = AdjDPS 였다(1,056칸 전부). 그 값으로 채울지는 도훈 결정.
- 수정 주당 항목은 받은 날의 수정 계수 기준이다(11-08 과 11-23 사이 한 종목이 절반이 됐다) — 퀀티 파일이 기준이라 그대로 둔다.

## 재개하는 법

위 표의 '상태'가 빈 첫 단계부터 한다. 원장에 이 결정의 줄이 열려 있으면(completed_at = null) 단계 3 은 끝난 것이다.
단계 8 이 중간에 끊겼으면 `run_factor_subset_repair.sh --resume <STAMP>`. 단계 9 는 처음부터 다시 돌려도 된다(같은 입력 → 같은 값).
