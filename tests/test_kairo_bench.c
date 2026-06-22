#define _GNU_SOURCE

#include <assert.h>
#include <linux/ioprio.h>
#include <stdio.h>

#define main kairo_bench_program_main
#include "../bench/kairo_bench.c"
#undef main

static void test_ioprio_mapping(void)
{
    assert(ioprio_value_for_worker_kind(KAIRO_WORKER_DECODE) ==
           IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_DECODE_READ));
    assert(ioprio_value_for_worker_kind(KAIRO_WORKER_PREFETCH) ==
           IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_PREFETCH_READ));
    assert(ioprio_value_for_worker_kind(KAIRO_WORKER_WRITE) ==
           IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 7));
    assert(ioprio_value_for_worker_kind(KAIRO_WORKER_EVICT) ==
           IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 6));
}

static void test_merge_friendly_defaults(void)
{
    struct kairo_config cfg;

    set_defaults(&cfg);
    cfg.mode = KAIRO_MODE_MERGE_FRIENDLY;
    cfg.decode_threads = 1;
    cfg.prefetch_threads = 0;
    cfg.write_threads = 0;
    apply_mode_defaults(&cfg);

    assert(cfg.access_pattern == KAIRO_ACCESS_SEQUENTIAL);
    assert(cfg.decode_threads == 4);
    assert(cfg.prefetch_threads == 2);
    assert(cfg.write_threads == 2);
    assert(cfg.random_read == false);
    assert(cfg.decode_region_pct == 50);
    assert(cfg.prefill_region_pct == 25);
}

static void test_merge_hostile_defaults(void)
{
    struct kairo_config cfg;

    set_defaults(&cfg);
    cfg.mode = KAIRO_MODE_MERGE_HOSTILE;
    cfg.sessions = 1;
    cfg.models = 1;
    cfg.decode_threads = 1;
    cfg.prefetch_threads = 1;
    cfg.fragment_size_bytes = 0;
    apply_mode_defaults(&cfg);

    assert(cfg.access_pattern == KAIRO_ACCESS_RANDOM);
    assert(cfg.sessions == 4);
    assert(cfg.models == 2);
    assert(cfg.decode_threads == 4);
    assert(cfg.prefetch_threads == 2);
    assert(cfg.fragment_size_bytes == 4096);
    assert(cfg.random_read == true);
    assert(cfg.decode_region_pct == 25);
    assert(cfg.prefill_region_pct == 25);
}

static void test_backend_summary_helpers(void)
{
    struct kairo_config cfg;
    struct kairo_backend_model model;

    set_defaults(&cfg);
    model = kairo_compute_backend_model(&cfg);
    assert(strcmp(model.class_name, "KAIRO_BACKEND_NONE") == 0);
    assert(model.stream_id == 0);
    assert(strcmp(model.stream_id_span, "none") == 0);
    assert(model.fdp_placement_id == 0);
    assert(strcmp(model.fdp_placement_span, "none") == 0);
    assert(model.zone_hint == 0);
    assert(model.noop_fallback == true);

    cfg.backend_mode = KAIRO_BACKEND_MODE_STREAMS;
    cfg.lifetime_class = KAIRO_USER_LIFE_MODEL;
    cfg.fixed_placement_group = 7;
    model = kairo_compute_backend_model(&cfg);
    assert(strcmp(model.class_name, "KAIRO_BACKEND_MODEL_LOCAL") == 0);
    assert(model.stream_id == 7);
    assert(strcmp(model.stream_id_span, "fixed-placement-group") == 0);
    assert(model.noop_fallback == false);

    cfg.backend_mode = KAIRO_BACKEND_MODE_FDP;
    cfg.fixed_placement_group = 0;
    cfg.fixed_cache_pool_id = 11;
    model = kairo_compute_backend_model(&cfg);
    assert(model.fdp_placement_id == 11);
    assert(strcmp(model.fdp_placement_span, "fixed-cache-pool") == 0);

    cfg.backend_mode = KAIRO_BACKEND_MODE_STREAMS;
    cfg.fixed_cache_pool_id = 0;
    cfg.fixed_placement_group = 0;
    cfg.placement_groups = 8;
    model = kairo_compute_backend_model(&cfg);
    assert(model.stream_id == 0);
    assert(strcmp(model.stream_id_span, "distributed-placement-groups") == 0);

    cfg.backend_mode = KAIRO_BACKEND_MODE_FDP;
    cfg.cache_pools = 4;
    model = kairo_compute_backend_model(&cfg);
    assert(model.fdp_placement_id == 0);
    assert(strcmp(model.fdp_placement_span, "distributed-cache-pools") == 0);

    cfg.backend_mode = KAIRO_BACKEND_MODE_ZNS;
    cfg.lifetime_class = KAIRO_USER_LIFE_SESSION;
    model = kairo_compute_backend_model(&cfg);
    assert(model.zone_hint == KAIRO_USER_LIFE_SESSION);

    cfg.backend_mode = KAIRO_BACKEND_MODE_NONE;
    cfg.recompute_ok = true;
    cfg.lifetime_class = KAIRO_USER_LIFE_NONE;
    model = kairo_compute_backend_model(&cfg);
    assert(strcmp(model.class_name, "KAIRO_BACKEND_NONE") == 0);
}

int main(void)
{
    test_ioprio_mapping();
    test_merge_friendly_defaults();
    test_merge_hostile_defaults();
    test_backend_summary_helpers();
    puts("test_kairo_bench: ok");
    return 0;
}
