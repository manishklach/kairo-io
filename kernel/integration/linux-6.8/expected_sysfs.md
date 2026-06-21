# Expected Kairo Sysfs Files

After booting a Linux 6.8.x kernel with the experimental Kairo `mq-deadline`
patch applied, the scheduler should expose the following files when
`mq-deadline` is active on a device:

```text
/sys/block/<dev>/queue/iosched/kairo_enable
/sys/block/<dev>/queue/iosched/kairo_decode_budget
/sys/block/<dev>/queue/iosched/kairo_decode_dispatches
/sys/block/<dev>/queue/iosched/kairo_normal_dispatches
/sys/block/<dev>/queue/iosched/kairo_starvation_escapes
```

These files are intended for local validation and benchmark-driven POC work.

Suggested checks:

```bash
cat /sys/block/<dev>/queue/scheduler
for name in \
  kairo_enable \
  kairo_decode_budget \
  kairo_decode_dispatches \
  kairo_normal_dispatches \
  kairo_starvation_escapes; do
  cat "/sys/block/<dev>/queue/iosched/$name"
done
```
