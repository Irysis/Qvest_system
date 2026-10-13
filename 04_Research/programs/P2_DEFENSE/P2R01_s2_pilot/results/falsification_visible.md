# 반증 조건 기계 판정 (보는 창 · R 계산 · 사전등록 규칙 그대로)

기저(ref = base) = RX0(같은 판본 재측정) — base_packet.md 가 그 패킷이다.

| 처방 | 필드 | 연산 | 처방 값 | 문턱 | 기준 | 참(=기각) |
|---|---|---|---|---|---|---|
| RX1 | behavior.summary.bull_up_capture_median | < | 2.0825 | 0.5500 | abs | 거짓 |
| RX1 | performance.strategy.cagr | < | 0.1793 | 0.1600 | abs | 거짓 |
| RX1 | performance.strategy.sharpe | < | 0.8292 | 0.8000 | abs | 거짓 |
| RX1 | performance.strategy.port_t | < | 3.6781 | 2.0000 | abs | 거짓 |
| RX1 | behavior.summary.crisis_dd_capture_median | >= | 0.9176 | 0.9229 | base | 거짓 |
| RX1 | behavior.summary.crisis_dd_capture_worst | >= | 1.3407 | 1.2025 | base | 참 |
| RX1 | behavior.stats.beta_down | >= | 1.1411 | 1.1549 | base | 거짓 |
| RX1 | performance.strategy.calmar | <= | 0.3247 | 0.3922 | base | 참 |
| RX1 | behavior.rolling.pass_life | < | 0.4500 | 0.4000 | base | 거짓 |
| RX2 | behavior.summary.bull_up_capture_median | < | 1.8170 | 0.5500 | abs | 거짓 |
| RX2 | performance.strategy.cagr | < | 0.1999 | 0.2023 | base | 참 |
| RX2 | performance.strategy.cagr | < | 0.1999 | 0.1600 | abs | 거짓 |
| RX2 | profile.turnover_annual | >= | 17.2512 | 13.4253 | base | 참 |
| RX2 | profile.cost_drag_annual | >= | 0.0260 | 0.0203 | base | 참 |
| RX2 | performance.strategy.calmar | <= | 0.3958 | 0.3922 | base | 거짓 |
| RX2 | performance.strategy.port_t | < | 3.8831 | 2.0000 | abs | 거짓 |
| RX2 | behavior.rolling.pass_life | < | 0.5056 | 0.4500 | base | 거짓 |
| RX3 | behavior.summary.bull_up_capture_median | < | 1.9042 | 0.5500 | abs | 거짓 |
| RX3 | performance.strategy.cagr | < | 0.2053 | 0.1600 | abs | 거짓 |
| RX3 | performance.strategy.sharpe | < | 0.9257 | 0.8000 | abs | 거짓 |
| RX3 | performance.strategy.port_t | < | 4.0072 | 2.0000 | abs | 거짓 |
| RX3 | behavior.summary.crisis_dd_capture_median | >= | 0.9529 | 0.9029 | base | 참 |
| RX3 | behavior.summary.asymmetry | <= | 1.9982 | 1.9982 | base | 참 |
| RX3 | controls.attribution.share_beats_exposure | < | 0.5000 | 0.7500 | base | 참 |
| RX3 | performance.strategy.calmar | <= | 0.4121 | 0.3922 | base | 거짓 |
| RX3 | behavior.rolling.pass_life | < | 0.4444 | 0.4000 | base | 거짓 |
