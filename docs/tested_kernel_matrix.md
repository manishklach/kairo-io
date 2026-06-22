# Tested Kernel Matrix

| Kernel version | Foundation patches apply | Foundation objects build | Boot tested | mq-deadline selected | Kairo sysfs visible | Decode counter increments | Prefetch counter increments | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux 6.8.12 | yes | partial | pending | pending | pending | pending | pending | `scripts/validate_patch_stack.sh`, `apply_foundation_stack.sh`, and `validate_foundation_stack.sh` passed on the local `linux-6.8.12-min` tree. The focused patched `block/mq-deadline.o` build passed, but the current combined `block/blk-mq.o block/mq-deadline.o` harness still fails on a local `blk-mq.o` `struct blk_plug` issue that also reproduces outside the Kairo path |
| Linux 6.8.x (additional trees) | pending | pending | pending | pending | pending | pending | pending | add rows as local validation expands |
