# Placement And Lifetime Hints

Kairo reserves architectural space for placement and lifetime metadata even though the first patch series does not fully implement it.

Candidate hint fields:

- `model_id`
- `session_id`
- `placement_id`
- cache generation
- lifetime class
- recomputable flag

Possible future uses:

- request grouping
- scheduling affinity
- namespace or zone placement
- backend-specific mapping to optional NVMe features
