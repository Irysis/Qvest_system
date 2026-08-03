import json

with open('06_Registry/alpha_frontier_queue.json', 'r', encoding='utf-8') as f:
    fq = json.load(f)

entries = fq['entries']
now = '2026-08-04'

# FQ-149 업데이트
for e in entries:
    if e['id'] == 'FQ-149':
        e['status'] = 'precheck_done_data_available'
        e['data_gate'] = (
            'PASS. dart_raw_financials.parquet에 외화환산이익/손실 계정 실재 확인. '
            'K200∪KQ150 연 142~211 tickers 커버(2015~2025). '
            '직접 외화자산 계정은 없지만 P&L 경유 FX 노출 크기 측정 가능 — '
            '(|외화환산이익|+|외화환산손실|)/TotalAssets 또는 |FX순손익|/매출로 구현.'
        )
        e['revised_hypothesis'] = (
            'AWARE-FX 논문 FX exposure baseline: 외화환산이익/손실 절대값 합계를 TotalAssets로 나눈 '
            'FX 노출 강도 지수. 높은 FX 노출 기업이 적극 헤징 시 불확실성 감소 → 리스크 프리미엄 감소 → 초과수익. '
            'annual lag(익년 3/31) 적용, PIT C4 준수.'
        )
        e['precheck_result'] = {
            'date': now,
            'dart_accounts': ['외화환산이익', '외화환산손실', '해외사업장환산외환차이'],
            'ku_kq_coverage_tickers_per_year': '142~211 (2015~2025)',
            'total_unique_tickers_in_universe': 293,
            'verdict': 'PASS — data available, sufficient coverage for top-25 ranking',
            'pit_lag': '익년 3/31 (C4 annual rule)',
            'proxy_formula': '(abs(외화환산이익) + abs(외화환산손실)) / TotalAssets'
        }
        e['next_action'] = 'alpha-search agent 착수 — FX 노출 강도 지수 경량 백테 (2015~2025, 11년)'
        e['updated'] = now
        print(f"FQ-149 업데이트: status={e['status']}, coverage=142~211/yr")
        break

fq['updated'] = f'{now} (FQ-149 precheck 결과 + data_gate PASS)'

with open('06_Registry/alpha_frontier_queue.json', 'w', encoding='utf-8') as f:
    json.dump(fq, f, ensure_ascii=False, indent=2)

print('FQ-149 업데이트 완료')
