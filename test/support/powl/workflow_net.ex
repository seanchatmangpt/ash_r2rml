# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# WorkflowNet moved to lib/ash_r2rml/powl/workflow_net.ex so the verifier and
# decomposition algorithms are production capabilities. Keeping a second module
# definition under test/support would shadow the admitted implementation during
# MIX_ENV=test and invalidate exact-subject verification.
