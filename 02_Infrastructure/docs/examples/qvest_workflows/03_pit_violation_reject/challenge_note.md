# Challenge Note — Example Fixture (03 PIT Violation Reject)

**codex_critic_skip_waiver**: examples/qvest_workflows/ fixture는 production WT 아닌 reference. v6.0 Codex Critic Round 면제.

본 시나리오: alpha_synthesis.R에 lookahead pattern (`lm(future_return ~ today_factor)`) 주입 → Judge Gate A PIT C1 FAIL → JUDGE_FAILED → ABORTED.
