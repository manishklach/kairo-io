# Tested Kernel Matrix

| Kernel version | Foundation apply check | Foundation apply | Foundation symbol validation | `block/mq-deadline.o` build | `block/blk-mq.o` build | Boot tested | Sysfs visible | Counter movement | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux 6.8.12 | passed | passed | passed | passed | failed | pending | pending | pending | `scripts/validate_patch_stack.sh`, `apply_foundation_stack.sh`, and `validate_foundation_stack.sh` passed on the local `linux-6.8.12-min` tree. The direct patched `block/mq-deadline.o` build passed. The combined `block/blk-mq.o block/mq-deadline.o` path failed on local `blk-mq.o` `struct blk_plug` member errors that also reproduced outside the Kairo foundation path. Boot and runtime validation remain unrun. |
| Linux 6.8.x (additional trees) | pending | not run | not run | not run | not run | pending | pending | pending | add rows as local validation expands |
