<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Production architecture

Production quality is modeled as evidence and bounded operational contracts, not as an application domain or customer-size tier.

The architectural chain is:

```text
ontology/profile/SHACL or Ash metadata
              ↓
          admission
              ↓
        SemanticIR / Mapping IR
              ↓
       DfCM candidate space
              ↓
     production quality profile
              ↓
 dynamic ggen manufacturing input
              ↓
         production/ggen
              ↓
   generated operational projections
```

`AshR2RML.DfCM` is generic and preserves reversible alternatives. `AshR2RML.Production` evaluates measurable technical requirements against exact-subject evidence. `AshR2RML.Ggen.Production` constructs only dynamic model inputs. The checked-in `production/ggen` workspace owns deterministic gates/queries/templates. BRCE remains separate from all of these and is the only DO boundary.

Technical `ALIVE` means the profile's exact evidence set exists for the same semantic subject. It does not mean a deployment has been authorized. `AshR2RML.Production.authorize_do/2` requires an additional BRCE receipt after technical standing is complete.
