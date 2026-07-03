# KR Drawdown Frequency Baseline

Generated: 2026-06-12 12:48:59.284775

## Baseline Rows

              source                        path n_days      start        end
              <char>                      <char>  <int>     <Date>     <Date>
1:         benchmark                  BM_DT:full   8965 1990-01-04 2026-06-11
2:    benchmark_2005                 BM_DT:2005+   5289 2005-01-03 2026-06-11
3: large_universe_ew RAWDATA:K200_KQ150_EW_2005+   5261 2005-01-03 2026-04-28
4:   all_universe_ew        RAWDATA:ALL_EW_2005+   5289 2005-01-03 2026-06-11
      mdd e45_count e45_days e45_day_frac e45_max_days e55_count e55_days
   <char>     <int>    <int>       <char>        <int>     <int>    <int>
1:  75.4%        24      823         9.2%          305        15      266
2:  54.5%         8       63         1.2%           21         0        0
3:  58.2%         6       40         0.8%           19         1        4
4:  64.5%         5      117         2.2%          110         4       30
   e55_day_frac e55_max_days
         <char>        <int>
1:         3.0%          179
2:         0.0%            0
3:         0.1%            4
4:         0.6%           20

## Strategy Output Summary

                    source     n n_days_median mdd_median mdd_q75 mdd_q90
                    <char> <int>         <num>     <char>  <char>  <char>
1:         all_universe_ew     1          5289      64.5%   64.5%   64.5%
2: alpha_search_quarantine     2          5266      60.1%   62.2%   63.5%
3:               benchmark     1          8965      75.4%   75.4%   75.4%
4:          benchmark_2005     1          5289      54.5%   54.5%   54.5%
5:          korea_research    58          4968      53.1%   54.3%   56.0%
6:       large_universe_ew     1          5261      58.2%   58.2%   58.2%
7:     research_strategies   328          5152      51.0%   58.1%   64.4%
   e45_median e45_q75 e45_q90 e45_max e45_frac_q75 e45_frac_q90 e55_q75 e55_q90
       <char>  <char>  <char>   <int>       <char>       <char>  <char>  <char>
1:        5.0     5.0     5.0       5         2.2%         2.2%     4.0     4.0
2:       12.5    14.8    16.1      17         5.9%         6.8%     1.8     1.9
3:       24.0    24.0    24.0      24         9.2%         9.2%    15.0    15.0
4:        8.0     8.0     8.0       8         1.2%         1.2%     0.0     0.0
5:        4.0     5.0     5.3      31         0.5%         0.8%     0.0     1.3
6:        6.0     6.0     6.0       6         0.8%         0.8%     1.0     1.0
7:        2.5     6.0    14.0      38         1.5%         7.5%     2.0     5.0
   e55_max
     <int>
1:       4
2:       2
3:      15
4:       0
5:      11
6:       1
7:      26

## Calibration Sample

                          sample     n e45_q50 e45_q75 e45_q90 e45_q95
                          <char> <int>   <num>   <num>   <num>   <num>
1: strategy_outputs_n_days_2500+   356       4       5      14      25
   e45_frac_q75 e45_frac_q90 e55_q75 e55_q90
          <num>        <num>   <num>   <num>
1:    0.0107949   0.07127476       2       5

## Files

- Profiles: /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/reports/drawdown_frequency_kr_profiles_20260612.csv
- Summary: /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/reports/drawdown_frequency_kr_summary_20260612.csv
- Calibration: /mnt/c/Users/99922/OneDrive/Quant_Module_Moltbot/stage_artifacts/reports/drawdown_frequency_kr_calibration_20260612.csv
