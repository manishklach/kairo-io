// SPDX-License-Identifier: GPL-2.0
/*
 * Kairo Validation Module — standalone kernel module that exposes the Kairo
 * sysfs interface for QEMU-based validation of user-space scripts, benchmarks,
 * and parsers without requiring a fully patched 6.8 kernel.
 *
 * All counters are simulated values that exercise the same sysfs paths
 * the real Kairo patches would use under /sys/kernel/kairo/.
 */
#include <linux/module.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/random.h>
#include <linux/jiffies.h>
#include <linux/slab.h>

#define KAIRO_MOD_NAME "kairo_validation"
#define KAIRO_VERSION  "0.0.0-qemu-1"

/* ─── Top-level kobject ─────────────────────────────────────────── */

static struct kobject *kairo_kobj;

/* ─── Core storage ──────────────────────────────────────────────── */

/* Stage 1-9 counters */
static u64 kairo_decode_dispatches;
static u64 kairo_prefetch_dispatches;
static u64 kairo_prefetch_deadline_hits;
static u64 kairo_prefetch_budget_skips;
static u64 kairo_prefill_dispatches;
static u64 kairo_evict_dispatches;
static u64 kairo_normal_dispatches;
static u64 kairo_starvation_escapes;
static u64 kairo_hinted_requests;
static u64 kairo_unhinted_requests;

/* Stage 25: fairness counters */
static u64 kairo_fairness_decode_budget_used;
static u64 kairo_fairness_prefetch_budget_used;
static u64 kairo_fairness_epoch_cycles;

/* Stage 26: blkcg counters */
static u64 kairo_blkcg_iops_read;
static u64 kairo_blkcg_iops_write;
static u64 kairo_blkcg_latency_avg_us;
static u64 kairo_blkcg_token_deficit;

/* Stage 17: KV region counters */
static u64 kairo_kv_region_hints;
static u64 kairo_kv_region_hits;
static u64 kairo_kv_region_misses;

/* Stage 18: eviction counters */
static u64 kairo_eviction_total;
static u64 kairo_eviction_recomputed;
static u64 kairo_eviction_kv_cache;
static u64 kairo_eviction_model_local;
static u64 kairo_eviction_decode_hot;
static u64 kairo_eviction_session_private;
static u64 kairo_eviction_persistent;
static u64 kairo_eviction_other;

/* Stage 19: heatmap counters */
static u64 kairo_heat_scan_regions;
static u64 kairo_heat_active_regions;
static u64 kairo_heat_cold_regions;
static u64 kairo_heat_frozen_regions;
static u64 kairo_heat_reheat_count;
static u64 kairo_heat_age_decay_count;
static u64 kairo_heat_promotions;
static u64 kairo_heat_demotions;

/* Stage 20: admission counters */
static u64 kairo_admit_accepted;
static u64 kairo_admit_rejected_recompute;
static u64 kairo_admit_rejected_lifetime;
static u64 kairo_admit_rejected_flash_pressure;
static u64 kairo_admit_rejected_reuse;
static u64 kairo_admit_rejected_policy;
static u64 kairo_admit_promoted;
static u64 kairo_admit_demoted;

/* ─── Unified show helper using container_of ────────────────────── */

struct kairo_val_attr {
    struct kobj_attribute attr;
    u64 *val;
};

static ssize_t kairo_val_show(struct kobject *kobj,
                               struct kobj_attribute *attr, char *buf)
{
    struct kairo_val_attr *va = container_of(attr, struct kairo_val_attr, attr);
    return sysfs_emit(buf, "%llu\n", *va->val);
}

#define KAIRO_VAL_ATTR(_name, _var) \
    static struct kairo_val_attr kairo_va_##_name = { \
        .attr = __ATTR(_name, 0444, kairo_val_show, NULL), \
        .val = &_var, \
    }

/* Instantiate attributes for all counters */
KAIRO_VAL_ATTR(decode_dispatches, kairo_decode_dispatches);
KAIRO_VAL_ATTR(prefetch_dispatches, kairo_prefetch_dispatches);
KAIRO_VAL_ATTR(prefetch_deadline_hits, kairo_prefetch_deadline_hits);
KAIRO_VAL_ATTR(prefetch_budget_skips, kairo_prefetch_budget_skips);
KAIRO_VAL_ATTR(prefill_dispatches, kairo_prefill_dispatches);
KAIRO_VAL_ATTR(evict_dispatches, kairo_evict_dispatches);
KAIRO_VAL_ATTR(normal_dispatches, kairo_normal_dispatches);
KAIRO_VAL_ATTR(starvation_escapes, kairo_starvation_escapes);
KAIRO_VAL_ATTR(hinted_requests, kairo_hinted_requests);
KAIRO_VAL_ATTR(unhinted_requests, kairo_unhinted_requests);

KAIRO_VAL_ATTR(fairness_decode_budget_used, kairo_fairness_decode_budget_used);
KAIRO_VAL_ATTR(fairness_prefetch_budget_used, kairo_fairness_prefetch_budget_used);
KAIRO_VAL_ATTR(fairness_epoch_cycles, kairo_fairness_epoch_cycles);

KAIRO_VAL_ATTR(blkcg_iops_read, kairo_blkcg_iops_read);
KAIRO_VAL_ATTR(blkcg_iops_write, kairo_blkcg_iops_write);
KAIRO_VAL_ATTR(blkcg_latency_avg_us, kairo_blkcg_latency_avg_us);
KAIRO_VAL_ATTR(blkcg_token_deficit, kairo_blkcg_token_deficit);

KAIRO_VAL_ATTR(kv_region_hints, kairo_kv_region_hints);
KAIRO_VAL_ATTR(kv_region_hits, kairo_kv_region_hits);
KAIRO_VAL_ATTR(kv_region_misses, kairo_kv_region_misses);

KAIRO_VAL_ATTR(eviction_total, kairo_eviction_total);
KAIRO_VAL_ATTR(eviction_recomputed, kairo_eviction_recomputed);
KAIRO_VAL_ATTR(eviction_kv_cache, kairo_eviction_kv_cache);
KAIRO_VAL_ATTR(eviction_model_local, kairo_eviction_model_local);
KAIRO_VAL_ATTR(eviction_decode_hot, kairo_eviction_decode_hot);
KAIRO_VAL_ATTR(eviction_session_private, kairo_eviction_session_private);
KAIRO_VAL_ATTR(eviction_persistent, kairo_eviction_persistent);
KAIRO_VAL_ATTR(eviction_other, kairo_eviction_other);

KAIRO_VAL_ATTR(heat_scan_regions, kairo_heat_scan_regions);
KAIRO_VAL_ATTR(heat_active_regions, kairo_heat_active_regions);
KAIRO_VAL_ATTR(heat_cold_regions, kairo_heat_cold_regions);
KAIRO_VAL_ATTR(heat_frozen_regions, kairo_heat_frozen_regions);
KAIRO_VAL_ATTR(heat_reheat_count, kairo_heat_reheat_count);
KAIRO_VAL_ATTR(heat_age_decay_count, kairo_heat_age_decay_count);
KAIRO_VAL_ATTR(heat_promotions, kairo_heat_promotions);
KAIRO_VAL_ATTR(heat_demotions, kairo_heat_demotions);

KAIRO_VAL_ATTR(admit_accepted, kairo_admit_accepted);
KAIRO_VAL_ATTR(admit_rejected_recompute, kairo_admit_rejected_recompute);
KAIRO_VAL_ATTR(admit_rejected_lifetime, kairo_admit_rejected_lifetime);
KAIRO_VAL_ATTR(admit_rejected_flash_pressure, kairo_admit_rejected_flash_pressure);
KAIRO_VAL_ATTR(admit_rejected_reuse, kairo_admit_rejected_reuse);
KAIRO_VAL_ATTR(admit_rejected_policy, kairo_admit_rejected_policy);
KAIRO_VAL_ATTR(admit_promoted, kairo_admit_promoted);
KAIRO_VAL_ATTR(admit_demoted, kairo_admit_demoted);

/* ─── Batch attribute creation helper ───────────────────────────── */

static struct attribute *kairo_core_attrs[] = {
    &kairo_va_decode_dispatches.attr.attr,
    &kairo_va_prefetch_dispatches.attr.attr,
    &kairo_va_prefetch_deadline_hits.attr.attr,
    &kairo_va_prefetch_budget_skips.attr.attr,
    &kairo_va_prefill_dispatches.attr.attr,
    &kairo_va_evict_dispatches.attr.attr,
    &kairo_va_normal_dispatches.attr.attr,
    &kairo_va_starvation_escapes.attr.attr,
    &kairo_va_hinted_requests.attr.attr,
    &kairo_va_unhinted_requests.attr.attr,
    &kairo_va_fairness_decode_budget_used.attr.attr,
    &kairo_va_fairness_prefetch_budget_used.attr.attr,
    &kairo_va_fairness_epoch_cycles.attr.attr,
    &kairo_va_blkcg_iops_read.attr.attr,
    &kairo_va_blkcg_iops_write.attr.attr,
    &kairo_va_blkcg_latency_avg_us.attr.attr,
    &kairo_va_blkcg_token_deficit.attr.attr,
    &kairo_va_kv_region_hints.attr.attr,
    &kairo_va_kv_region_hits.attr.attr,
    &kairo_va_kv_region_misses.attr.attr,
    &kairo_va_eviction_total.attr.attr,
    &kairo_va_eviction_recomputed.attr.attr,
    &kairo_va_eviction_kv_cache.attr.attr,
    &kairo_va_eviction_model_local.attr.attr,
    &kairo_va_eviction_decode_hot.attr.attr,
    &kairo_va_eviction_session_private.attr.attr,
    &kairo_va_eviction_persistent.attr.attr,
    &kairo_va_eviction_other.attr.attr,
    &kairo_va_heat_scan_regions.attr.attr,
    &kairo_va_heat_active_regions.attr.attr,
    &kairo_va_heat_cold_regions.attr.attr,
    &kairo_va_heat_frozen_regions.attr.attr,
    &kairo_va_heat_reheat_count.attr.attr,
    &kairo_va_heat_age_decay_count.attr.attr,
    &kairo_va_heat_promotions.attr.attr,
    &kairo_va_heat_demotions.attr.attr,
    &kairo_va_admit_accepted.attr.attr,
    &kairo_va_admit_rejected_recompute.attr.attr,
    &kairo_va_admit_rejected_lifetime.attr.attr,
    &kairo_va_admit_rejected_flash_pressure.attr.attr,
    &kairo_va_admit_rejected_reuse.attr.attr,
    &kairo_va_admit_rejected_policy.attr.attr,
    &kairo_va_admit_promoted.attr.attr,
    &kairo_va_admit_demoted.attr.attr,
    NULL,
};

static const struct attribute_group kairo_core_group = {
    .attrs = kairo_core_attrs,
    .name = "counters",
};

/* ─── Version attribute ─────────────────────────────────────────── */

static ssize_t version_show(struct kobject *kobj,
                            struct kobj_attribute *attr, char *buf)
{
    return sysfs_emit(buf, "%s\n", KAIRO_VERSION);
}
static struct kobj_attribute version_attr = __ATTR_RO(version);

/* ─── Module init/exit ──────────────────────────────────────────── */

static int __init kairo_validation_init(void)
{
    int ret;

    /* Seed some demo values */
    kairo_decode_dispatches = 42;
    kairo_prefetch_dispatches = 17;
    kairo_prefetch_deadline_hits = 12;
    kairo_prefetch_budget_skips = 3;
    kairo_prefill_dispatches = 5;
    kairo_evict_dispatches = 8;
    kairo_normal_dispatches = 120;
    kairo_starvation_escapes = 1;
    kairo_hinted_requests = 28;
    kairo_unhinted_requests = 95;

    kairo_fairness_decode_budget_used = 85;
    kairo_fairness_prefetch_budget_used = 30;
    kairo_fairness_epoch_cycles = 1024;

    kairo_blkcg_iops_read = 4500;
    kairo_blkcg_iops_write = 1200;
    kairo_blkcg_latency_avg_us = 185;
    kairo_blkcg_token_deficit = 7;

    kairo_kv_region_hints = 15;
    kairo_kv_region_hits = 9;
    kairo_kv_region_misses = 6;

    kairo_eviction_total = 230;
    kairo_eviction_recomputed = 45;
    kairo_eviction_kv_cache = 60;
    kairo_eviction_model_local = 35;
    kairo_eviction_decode_hot = 20;
    kairo_eviction_session_private = 15;
    kairo_eviction_persistent = 40;
    kairo_eviction_other = 15;

    kairo_heat_scan_regions = 512;
    kairo_heat_active_regions = 87;
    kairo_heat_cold_regions = 340;
    kairo_heat_frozen_regions = 85;
    kairo_heat_reheat_count = 22;
    kairo_heat_age_decay_count = 156;
    kairo_heat_promotions = 14;
    kairo_heat_demotions = 31;

    kairo_admit_accepted = 180;
    kairo_admit_rejected_recompute = 25;
    kairo_admit_rejected_lifetime = 12;
    kairo_admit_rejected_flash_pressure = 8;
    kairo_admit_rejected_reuse = 15;
    kairo_admit_rejected_policy = 5;
    kairo_admit_promoted = 10;
    kairo_admit_demoted = 6;

    kairo_kobj = kobject_create_and_add("kairo", kernel_kobj);
    if (!kairo_kobj) {
        pr_err("[kairo] Failed to create /sys/kernel/kairo\n");
        return -ENOMEM;
    }

    ret = sysfs_create_file(kairo_kobj, &version_attr.attr);
    if (ret) {
        pr_err("[kairo] Failed to create version attr\n");
        goto err_kobj;
    }

    ret = sysfs_create_group(kairo_kobj, &kairo_core_group);
    if (ret) {
        pr_err("[kairo] Failed to create counter group\n");
        goto err_group;
    }

    pr_info("[kairo] Validation module loaded (%s)\n", KAIRO_VERSION);
    return 0;

err_group:
    sysfs_remove_file(kairo_kobj, &version_attr.attr);
err_kobj:
    kobject_put(kairo_kobj);
    return ret;
}

static void __exit kairo_validation_exit(void)
{
    sysfs_remove_group(kairo_kobj, &kairo_core_group);
    sysfs_remove_file(kairo_kobj, &version_attr.attr);
    kobject_put(kairo_kobj);
    pr_info("[kairo] Validation module unloaded\n");
}

module_init(kairo_validation_init);
module_exit(kairo_validation_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Kairo Authors <kairo@research>");
MODULE_DESCRIPTION("Kairo sysfs validation module for QEMU testing");
MODULE_VERSION(KAIRO_VERSION);
