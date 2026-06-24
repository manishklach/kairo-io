#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <linux/falloc.h>
#include <linux/ioprio.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#include <kairo_hints.h>

#ifndef O_DIRECT
#define O_DIRECT 0
#endif

#define KAIRO_MAX_SAMPLES 1000000UL
#define KAIRO_DIRECT_ALIGN 4096UL

enum kairo_worker_kind {
    KAIRO_WORKER_DECODE = 0,
    KAIRO_WORKER_PREFETCH = 1,
    KAIRO_WORKER_WRITE = 2,
    KAIRO_WORKER_EVICT = 3,
};

enum kairo_mode {
    KAIRO_MODE_DECODE_ONLY = 0,
    KAIRO_MODE_MIXED = 1,
    KAIRO_MODE_PREFETCH_PRESSURE = 2,
    KAIRO_MODE_EVICTION_PRESSURE = 3,
    KAIRO_MODE_MULTISESSION = 4,
    KAIRO_MODE_MERGE_FRIENDLY = 5,
    KAIRO_MODE_MERGE_HOSTILE = 6,
};

enum kairo_access_pattern {
    KAIRO_ACCESS_RANDOM = 0,
    KAIRO_ACCESS_SEQUENTIAL = 1,
    KAIRO_ACCESS_STRIDED = 2,
    KAIRO_ACCESS_CLUSTERED = 3,
};

struct kairo_config {
    const char *file_path;
    uint64_t file_size_bytes;
    size_t block_size_bytes;
    unsigned int decode_threads;
    unsigned int prefetch_threads;
    unsigned int write_threads;
    unsigned int evict_threads;
    unsigned int runtime_seconds;
    unsigned int queue_depth_hint;
    unsigned int sessions;
    unsigned int models;
    unsigned int prefill_region_pct;
    unsigned int decode_region_pct;
    enum kairo_mode mode;
    bool use_direct;
    bool random_read;
    enum kairo_access_pattern access_pattern;
    unsigned int stride_blocks;
    unsigned int cluster_size_blocks;
    size_t fragment_size_bytes;
    enum kairo_hint_mode hint_mode;
    enum kairo_semantic_mode semantic_mode;
    bool evict_threads_explicit;
    unsigned int fixed_model_id;
    unsigned int fixed_session_id;
    unsigned int fixed_cache_pool_id;
    unsigned int fixed_placement_group;
    unsigned int cache_pools;
    unsigned int placement_groups;
    uint32_t lifetime_class;
    bool recompute_ok;
    enum kairo_backend_mode backend_mode;
    unsigned int noisy_session;
    unsigned int noisy_model;
    unsigned int noisy_multiplier;
};

struct kairo_stats {
    pthread_mutex_t lock;
    uint64_t total_decode_reads;
    uint64_t total_prefetch_reads;
    uint64_t total_writes;
    uint64_t total_evictions;
    uint64_t total_decode_bytes;
    uint64_t total_prefetch_bytes;
    uint64_t total_write_bytes;
    uint64_t total_evict_bytes;
    uint64_t decode_latency_samples;
    long double decode_latency_sum_us;
    double decode_latency_max_us;
    double *decode_latencies_us;
    uint64_t ioprio_decode_ok;
    uint64_t ioprio_decode_fail;
    uint64_t ioprio_prefetch_ok;
    uint64_t ioprio_prefetch_fail;
    uint64_t ioprio_write_ok;
    uint64_t ioprio_write_fail;
    uint64_t rwf_decode_attempts;
    uint64_t rwf_decode_fail;
    uint64_t rwf_prefetch_attempts;
    uint64_t rwf_prefetch_fail;
    uint64_t rwf_prefill_attempts;
    uint64_t rwf_prefill_fail;
    uint64_t rwf_ephemeral_attempts;
    uint64_t rwf_ephemeral_fail;
    uint64_t rwf_recompute_attempts;
    uint64_t rwf_recompute_fail;
    uint64_t rwf_no_durability_attempts;
    uint64_t rwf_no_durability_fail;
    uint64_t rwf_avoid_pagecache_attempts;
    uint64_t rwf_avoid_pagecache_fail;
};

struct kairo_stats_snapshot {
    uint64_t total_decode_reads;
    uint64_t total_prefetch_reads;
    uint64_t total_writes;
    uint64_t total_evictions;
    uint64_t total_decode_bytes;
    uint64_t total_prefetch_bytes;
    uint64_t total_write_bytes;
    uint64_t total_evict_bytes;
    uint64_t decode_latency_samples;
    long double decode_latency_sum_us;
    double decode_latency_max_us;
    double *decode_latencies_us;
    uint64_t ioprio_decode_ok;
    uint64_t ioprio_decode_fail;
    uint64_t ioprio_prefetch_ok;
    uint64_t ioprio_prefetch_fail;
    uint64_t ioprio_write_ok;
    uint64_t ioprio_write_fail;
    uint64_t rwf_decode_attempts;
    uint64_t rwf_decode_fail;
    uint64_t rwf_prefetch_attempts;
    uint64_t rwf_prefetch_fail;
    uint64_t rwf_prefill_attempts;
    uint64_t rwf_prefill_fail;
    uint64_t rwf_ephemeral_attempts;
    uint64_t rwf_ephemeral_fail;
    uint64_t rwf_recompute_attempts;
    uint64_t rwf_recompute_fail;
    uint64_t rwf_no_durability_attempts;
    uint64_t rwf_no_durability_fail;
    uint64_t rwf_avoid_pagecache_attempts;
    uint64_t rwf_avoid_pagecache_fail;
};

struct kairo_worker_ctx {
    int fd;
    const struct kairo_config *cfg;
    struct kairo_stats *stats;
    unsigned int worker_id;
    unsigned int session_id;
    unsigned int model_id;
    enum kairo_worker_kind kind;
    volatile bool *stop;
    off_t region_start;
    off_t region_length;
    unsigned int cache_pool_id;
    unsigned int placement_group;
};

static const char *kairo_mode_name(enum kairo_mode mode)
{
    switch (mode) {
    case KAIRO_MODE_DECODE_ONLY:
        return "decode-only";
    case KAIRO_MODE_MIXED:
        return "mixed";
    case KAIRO_MODE_PREFETCH_PRESSURE:
        return "prefetch-pressure";
    case KAIRO_MODE_EVICTION_PRESSURE:
        return "eviction-pressure";
    case KAIRO_MODE_MULTISESSION:
        return "multisession";
    case KAIRO_MODE_MERGE_FRIENDLY:
        return "merge-friendly";
    case KAIRO_MODE_MERGE_HOSTILE:
        return "merge-hostile";
    default:
        return "mixed";
    }
}

static const char *kairo_access_pattern_name(enum kairo_access_pattern p)
{
    switch (p) {
    case KAIRO_ACCESS_RANDOM:
        return "random";
    case KAIRO_ACCESS_SEQUENTIAL:
        return "sequential";
    case KAIRO_ACCESS_STRIDED:
        return "strided";
    case KAIRO_ACCESS_CLUSTERED:
        return "clustered";
    default:
        return "random";
    }
}

static enum kairo_mode parse_mode(const char *value)
{
    if (strcmp(value, "decode-only") == 0)
        return KAIRO_MODE_DECODE_ONLY;
    if (strcmp(value, "mixed") == 0)
        return KAIRO_MODE_MIXED;
    if (strcmp(value, "prefetch-pressure") == 0)
        return KAIRO_MODE_PREFETCH_PRESSURE;
    if (strcmp(value, "eviction-pressure") == 0)
        return KAIRO_MODE_EVICTION_PRESSURE;
    if (strcmp(value, "multisession") == 0)
        return KAIRO_MODE_MULTISESSION;
    if (strcmp(value, "merge-friendly") == 0)
        return KAIRO_MODE_MERGE_FRIENDLY;
    if (strcmp(value, "merge-hostile") == 0)
        return KAIRO_MODE_MERGE_HOSTILE;

    fprintf(stderr, "invalid mode: %s\n", value);
    exit(EXIT_FAILURE);
}

static enum kairo_access_pattern parse_access_pattern(const char *value)
{
    if (strcmp(value, "random") == 0)
        return KAIRO_ACCESS_RANDOM;
    if (strcmp(value, "sequential") == 0)
        return KAIRO_ACCESS_SEQUENTIAL;
    if (strcmp(value, "strided") == 0)
        return KAIRO_ACCESS_STRIDED;
    if (strcmp(value, "clustered") == 0)
        return KAIRO_ACCESS_CLUSTERED;

    fprintf(stderr, "invalid access-pattern: %s\n", value);
    exit(EXIT_FAILURE);
}

static enum kairo_hint_mode parse_hint_mode(const char *value)
{
    if (strcmp(value, "ioprio") == 0)
        return KAIRO_HINT_MODE_IOPRIO;
    if (strcmp(value, "rwf") == 0)
        return KAIRO_HINT_MODE_RWF;
    if (strcmp(value, "both") == 0)
        return KAIRO_HINT_MODE_BOTH;

    fprintf(stderr, "invalid hint-mode: %s\n", value);
    exit(EXIT_FAILURE);
}

static enum kairo_semantic_mode parse_semantic_mode(const char *value)
{
    if (strcmp(value, "normal") == 0)
        return KAIRO_SEMANTIC_NORMAL;
    if (strcmp(value, "ephemeral") == 0)
        return KAIRO_SEMANTIC_EPHEMERAL;
    if (strcmp(value, "recomputable") == 0)
        return KAIRO_SEMANTIC_RECOMPUTABLE;
    if (strcmp(value, "ephemeral-recomputable") == 0)
        return KAIRO_SEMANTIC_EPHEMERAL_RECOMPUTABLE;

    fprintf(stderr, "invalid semantic-mode: %s\n", value);
    exit(EXIT_FAILURE);
}

static enum kairo_backend_mode parse_backend_mode(const char *value)
{
    if (strcmp(value, "none") == 0)
        return KAIRO_BACKEND_MODE_NONE;
    if (strcmp(value, "generic") == 0)
        return KAIRO_BACKEND_MODE_GENERIC;
    if (strcmp(value, "streams") == 0)
        return KAIRO_BACKEND_MODE_STREAMS;
    if (strcmp(value, "fdp") == 0)
        return KAIRO_BACKEND_MODE_FDP;
    if (strcmp(value, "zns") == 0)
        return KAIRO_BACKEND_MODE_ZNS;

    fprintf(stderr, "invalid backend-mode: %s (expected none|generic|streams|fdp|zns)\n", value);
    exit(EXIT_FAILURE);
}

struct kairo_backend_model {
    const char *class_name;
    unsigned int stream_id;
    const char *stream_id_span;
    unsigned int fdp_placement_id;
    const char *fdp_placement_span;
    unsigned int zone_hint;
    bool noop_fallback;
};

static struct kairo_backend_model
kairo_compute_backend_model(const struct kairo_config *cfg)
{
    struct kairo_backend_model m;
    const char *class_name = "KAIRO_BACKEND_NONE";

    if (cfg->backend_mode != KAIRO_BACKEND_MODE_NONE) {
        switch (cfg->lifetime_class) {
        case KAIRO_USER_LIFE_SHORT:
            class_name = "KAIRO_BACKEND_SHORT_LIVED";
            break;
        case KAIRO_USER_LIFE_SESSION:
            class_name = "KAIRO_BACKEND_SESSION_LOCAL";
            break;
        case KAIRO_USER_LIFE_MODEL:
            class_name = "KAIRO_BACKEND_MODEL_LOCAL";
            break;
        case KAIRO_USER_LIFE_PERSISTENT:
            class_name = "KAIRO_BACKEND_PERSISTENT";
            break;
        default:
            if (cfg->recompute_ok)
                class_name = "KAIRO_BACKEND_RECOMPUTABLE";
            break;
        }
    }

    m.class_name = class_name;
    m.stream_id_span = "none";
    m.fdp_placement_span = "none";
    m.stream_id = (cfg->backend_mode == KAIRO_BACKEND_MODE_STREAMS)
        ? (cfg->fixed_placement_group > 0 ? cfg->fixed_placement_group
           : cfg->fixed_cache_pool_id > 0 ? cfg->fixed_cache_pool_id
           : 0) : 0;
    m.fdp_placement_id = (cfg->backend_mode == KAIRO_BACKEND_MODE_FDP)
        ? (cfg->fixed_cache_pool_id > 0 ? cfg->fixed_cache_pool_id
           : cfg->fixed_placement_group > 0 ? cfg->fixed_placement_group
           : 0) : 0;
    m.zone_hint = (cfg->backend_mode == KAIRO_BACKEND_MODE_ZNS)
        ? (unsigned int)cfg->lifetime_class : 0;
    m.noop_fallback = (cfg->backend_mode == KAIRO_BACKEND_MODE_NONE);

    if (cfg->backend_mode == KAIRO_BACKEND_MODE_STREAMS) {
        if (cfg->fixed_placement_group > 0)
            m.stream_id_span = "fixed-placement-group";
        else if (cfg->fixed_cache_pool_id > 0)
            m.stream_id_span = "fixed-cache-pool";
        else if (cfg->placement_groups > 1)
            m.stream_id_span = "distributed-placement-groups";
        else if (cfg->cache_pools > 1)
            m.stream_id_span = "distributed-cache-pools";
    }

    if (cfg->backend_mode == KAIRO_BACKEND_MODE_FDP) {
        if (cfg->fixed_cache_pool_id > 0)
            m.fdp_placement_span = "fixed-cache-pool";
        else if (cfg->fixed_placement_group > 0)
            m.fdp_placement_span = "fixed-placement-group";
        else if (cfg->cache_pools > 1)
            m.fdp_placement_span = "distributed-cache-pools";
        else if (cfg->placement_groups > 1)
            m.fdp_placement_span = "distributed-placement-groups";
    }

    return m;
}

static uint32_t parse_lifetime(const char *value)
{
    if (strcmp(value, "short") == 0)
        return KAIRO_USER_LIFE_SHORT;
    if (strcmp(value, "session") == 0)
        return KAIRO_USER_LIFE_SESSION;
    if (strcmp(value, "model") == 0)
        return KAIRO_USER_LIFE_MODEL;
    if (strcmp(value, "persistent") == 0)
        return KAIRO_USER_LIFE_PERSISTENT;

    fprintf(stderr, "invalid lifetime: %s (expected short|session|model|persistent)\n", value);
    exit(EXIT_FAILURE);
}

static void usage(const char *prog)
{
    fprintf(stderr,
            "Usage: %s --file <path> [options]\n"
            "  --file <path>             Target file path\n"
            "  --mode <name>             decode-only|mixed|prefetch-pressure|\n"
            "                            eviction-pressure|multisession|\n"
            "                            merge-friendly|merge-hostile\n"
            "  --size <bytes|K|M|G>      File size, default 8G\n"
            "  --block-size <bytes|K|M|G>\n"
            "                            I/O block size, default 1M\n"
            "  --decode-threads <n>      Default 4\n"
            "  --prefetch-threads <n>    Default 1\n"
            "  --write-threads <n>       Default 2\n"
            "  --evict-threads <n>       Default 0\n"
            "  --sessions <n>            Default 1\n"
            "  --models <n>              Default 1\n"
            "  --cache-pools <n>         Number of cache pools (default: 1)\n"
            "  --placement-groups <n>    Number of placement groups (default: 1)\n"
            "  --model-id <n>            Fixed model ID (default: distribute)\n"
            "  --session-id <n>          Fixed session ID (default: distribute)\n"
            "  --cache-pool-id <n>       Fixed cache pool ID (default: 0)\n"
            "  --placement-group <n>     Fixed placement group (default: 0)\n"
            "  --lifetime <name>         short|session|model|persistent\n"
            "  --recompute-ok            Mark writes as recomputable\n"
            "  --prefill-region-pct <n>  Default 34\n"
            "  --decode-region-pct <n>   Default 33\n"
            "  --runtime <sec>           Default 60\n"
            "  --queue-depth <n>         Placeholder for future io_uring path\n"
            "  --access-pattern <name>   random|sequential|strided|clustered\n"
            "  --stride-blocks <n>       Blocks between strided accesses\n"
            "  --cluster-size-blocks <n> Blocks per cluster (clustered mode)\n"
            "  --fragment-size <B|K|M>   Fragment I/O into smaller chunks\n"
            "  --hint-mode <name>        ioprio|rwf|both (default: ioprio)\n"
            "  --semantic-mode <name>    normal|ephemeral|recomputable|\n"
            "                            ephemeral-recomputable\n"
            "  --backend-mode <name>     none|generic|streams|fdp|zns\n"
            "  --random-read             Default mode\n"
            "  --sequential-read         Disable random read placement\n"
            "  --buffered                Disable O_DIRECT\n"
            "  --noisy-session <n>       Session ID for noise stress test\n"
            "  --noisy-model <n>         Model ID for noise stress test\n"
            "  --noisy-multiplier <n>    Traffic multiplier for noisy entity\n",
            prog);
}

static uint64_t parse_size(const char *value, const char *name)
{
    char *end = NULL;
    uint64_t parsed;
    uint64_t scale = 1;

    if (value == NULL || value[0] == '\0') {
        fprintf(stderr, "invalid %s\n", name);
        exit(EXIT_FAILURE);
    }

    parsed = strtoull(value, &end, 10);
    if (end == value) {
        fprintf(stderr, "invalid %s: %s\n", name, value);
        exit(EXIT_FAILURE);
    }

    if (*end != '\0') {
        if (end[1] != '\0') {
            fprintf(stderr, "invalid %s suffix: %s\n", name, value);
            exit(EXIT_FAILURE);
        }
        switch (*end) {
        case 'k':
        case 'K':
            scale = 1024ULL;
            break;
        case 'm':
        case 'M':
            scale = 1024ULL * 1024ULL;
            break;
        case 'g':
        case 'G':
            scale = 1024ULL * 1024ULL * 1024ULL;
            break;
        default:
            fprintf(stderr, "invalid %s suffix: %s\n", name, value);
            exit(EXIT_FAILURE);
        }
    }

    return parsed * scale;
}

static double timespec_diff_us(const struct timespec *start, const struct timespec *end)
{
    time_t sec = end->tv_sec - start->tv_sec;
    long nsec = end->tv_nsec - start->tv_nsec;

    return ((double)sec * 1000000.0) + ((double)nsec / 1000.0);
}

static int compare_double(const void *lhs, const void *rhs)
{
    const double a = *(const double *)lhs;
    const double b = *(const double *)rhs;

    if (a < b)
        return -1;
    if (a > b)
        return 1;
    return 0;
}

static double percentile_from_sorted(const double *values, uint64_t count, double pct)
{
    uint64_t index;

    if (count == 0)
        return 0.0;

    if (pct <= 0.0)
        return values[0];
    if (pct >= 100.0)
        return values[count - 1];

    index = (uint64_t)(((pct / 100.0) * (double)(count - 1)) + 0.5);
    if (index >= count)
        index = count - 1;

    return values[index];
}

static int ioprio_value_for_worker_kind(enum kairo_worker_kind kind)
{
    switch (kind) {
    case KAIRO_WORKER_DECODE:
        return IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_DECODE_READ);
    case KAIRO_WORKER_PREFETCH:
        return IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_PREFETCH_READ);
    case KAIRO_WORKER_EVICT:
        return IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 6);
    case KAIRO_WORKER_WRITE:
    default:
        return IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 7);
    }
}

static int set_current_ioprio(enum kairo_worker_kind kind)
{
    return syscall(SYS_ioprio_set, IOPRIO_WHO_PROCESS, 0, ioprio_value_for_worker_kind(kind));
}

static const char *worker_kind_name(enum kairo_worker_kind kind)
{
    switch (kind) {
    case KAIRO_WORKER_DECODE:
        return "decode";
    case KAIRO_WORKER_PREFETCH:
        return "prefetch";
    case KAIRO_WORKER_WRITE:
        return "write";
    case KAIRO_WORKER_EVICT:
        return "evict";
    default:
        return "unknown";
    }
}

static void set_defaults(struct kairo_config *cfg)
{
    memset(cfg, 0, sizeof(*cfg));
    cfg->file_size_bytes = 8ULL * 1024ULL * 1024ULL * 1024ULL;
    cfg->block_size_bytes = 1024UL * 1024UL;
    cfg->decode_threads = 4;
    cfg->prefetch_threads = 1;
    cfg->write_threads = 2;
    cfg->evict_threads = 0;
    cfg->runtime_seconds = 60;
    cfg->queue_depth_hint = 32;
    cfg->sessions = 1;
    cfg->models = 1;
    cfg->prefill_region_pct = 34;
    cfg->decode_region_pct = 33;
    cfg->mode = KAIRO_MODE_MIXED;
    cfg->use_direct = true;
    cfg->random_read = true;
    cfg->access_pattern = KAIRO_ACCESS_RANDOM;
    cfg->stride_blocks = 16;
    cfg->cluster_size_blocks = 8;
    cfg->fragment_size_bytes = 0;
    cfg->hint_mode = KAIRO_HINT_MODE_IOPRIO;
    cfg->semantic_mode = KAIRO_SEMANTIC_NORMAL;
    cfg->evict_threads_explicit = false;
    cfg->fixed_model_id = 0;
    cfg->fixed_session_id = 0;
    cfg->fixed_cache_pool_id = 0;
    cfg->fixed_placement_group = 0;
    cfg->cache_pools = 1;
    cfg->placement_groups = 1;
    cfg->lifetime_class = KAIRO_USER_LIFE_NONE;
    cfg->recompute_ok = false;
    cfg->backend_mode = KAIRO_BACKEND_MODE_NONE;
}

static void apply_mode_defaults(struct kairo_config *cfg)
{
    switch (cfg->mode) {
    case KAIRO_MODE_DECODE_ONLY:
        cfg->prefetch_threads = 0;
        cfg->write_threads = 0;
        cfg->evict_threads = 0;
        if (cfg->decode_threads == 0)
            cfg->decode_threads = 1;
        cfg->decode_region_pct = 100;
        cfg->prefill_region_pct = 0;
        break;
    case KAIRO_MODE_PREFETCH_PRESSURE:
        if (cfg->prefetch_threads < 4)
            cfg->prefetch_threads = 4;
        if (cfg->write_threads == 0)
            cfg->write_threads = 1;
        cfg->decode_region_pct = 25;
        cfg->prefill_region_pct = 25;
        break;
    case KAIRO_MODE_EVICTION_PRESSURE:
        if (cfg->evict_threads == 0)
            cfg->evict_threads = 2;
        if (cfg->write_threads == 0)
            cfg->write_threads = 1;
        cfg->decode_region_pct = 25;
        cfg->prefill_region_pct = 25;
        break;
    case KAIRO_MODE_MULTISESSION:
        if (cfg->sessions < 4)
            cfg->sessions = 4;
        if (cfg->models < 2)
            cfg->models = 2;
        if (cfg->prefetch_threads < 2)
            cfg->prefetch_threads = 2;
        if (cfg->write_threads == 0)
            cfg->write_threads = 1;
        if (cfg->evict_threads == 0)
            cfg->evict_threads = 1;
        break;
    case KAIRO_MODE_MERGE_FRIENDLY:
        cfg->access_pattern = KAIRO_ACCESS_SEQUENTIAL;
        if (cfg->decode_threads < 4)
            cfg->decode_threads = 4;
        if (cfg->prefetch_threads == 0)
            cfg->prefetch_threads = 2;
        if (cfg->write_threads == 0)
            cfg->write_threads = 2;
        cfg->random_read = false;
        cfg->decode_region_pct = 50;
        cfg->prefill_region_pct = 25;
        break;
    case KAIRO_MODE_MERGE_HOSTILE:
        cfg->access_pattern = KAIRO_ACCESS_RANDOM;
        if (cfg->sessions < 4)
            cfg->sessions = 4;
        if (cfg->models < 2)
            cfg->models = 2;
        if (cfg->decode_threads < 4)
            cfg->decode_threads = 4;
        if (cfg->prefetch_threads < 2)
            cfg->prefetch_threads = 2;
        if (cfg->fragment_size_bytes == 0)
            cfg->fragment_size_bytes = 4096;
        cfg->random_read = true;
        cfg->decode_region_pct = 25;
        cfg->prefill_region_pct = 25;
        break;
    case KAIRO_MODE_MIXED:
    default:
        break;
    }

    switch (cfg->semantic_mode) {
    case KAIRO_SEMANTIC_EPHEMERAL:
    case KAIRO_SEMANTIC_EPHEMERAL_RECOMPUTABLE:
        if (!cfg->evict_threads_explicit && cfg->evict_threads == 0)
            cfg->evict_threads = 1;
        break;
    case KAIRO_SEMANTIC_NORMAL:
    case KAIRO_SEMANTIC_RECOMPUTABLE:
    default:
        break;
    }
}

static bool kairo_hint_mode_uses_ioprio(enum kairo_hint_mode mode)
{
    return mode == KAIRO_HINT_MODE_IOPRIO || mode == KAIRO_HINT_MODE_BOTH;
}

static bool kairo_hint_mode_uses_rwf(enum kairo_hint_mode mode)
{
    return mode == KAIRO_HINT_MODE_RWF || mode == KAIRO_HINT_MODE_BOTH;
}

static void validate_config(const struct kairo_config *cfg)
{
    if (cfg->file_path == NULL) {
        fprintf(stderr, "--file is required\n");
        exit(EXIT_FAILURE);
    }
    if (cfg->block_size_bytes == 0 || cfg->file_size_bytes < cfg->block_size_bytes) {
        fprintf(stderr, "invalid size or block size\n");
        exit(EXIT_FAILURE);
    }
    if ((cfg->file_size_bytes % cfg->block_size_bytes) != 0) {
        fprintf(stderr, "--size must be a multiple of --block-size\n");
        exit(EXIT_FAILURE);
    }
    if (cfg->use_direct && ((cfg->block_size_bytes % KAIRO_DIRECT_ALIGN) != 0)) {
        fprintf(stderr,
                "O_DIRECT path expects --block-size to be a multiple of %lu bytes\n",
                (unsigned long)KAIRO_DIRECT_ALIGN);
        exit(EXIT_FAILURE);
    }
    if (cfg->decode_threads == 0 && cfg->prefetch_threads == 0 &&
        cfg->write_threads == 0 && cfg->evict_threads == 0) {
        fprintf(stderr, "no workers configured\n");
        exit(EXIT_FAILURE);
    }
    if (cfg->sessions == 0 || cfg->models == 0) {
        fprintf(stderr, "--sessions and --models must be non-zero\n");
        exit(EXIT_FAILURE);
    }
    if (cfg->decode_region_pct > 100 || cfg->prefill_region_pct > 100 ||
        cfg->decode_region_pct + cfg->prefill_region_pct > 100) {
        fprintf(stderr, "invalid region percentages\n");
        exit(EXIT_FAILURE);
    }
    if (cfg->fragment_size_bytes > 0 && cfg->fragment_size_bytes >= cfg->block_size_bytes) {
        fprintf(stderr, "--fragment-size must be smaller than --block-size\n");
        exit(EXIT_FAILURE);
    }
}

static int open_target(const struct kairo_config *cfg)
{
    int flags = O_CREAT | O_RDWR;
    int fd;

    if (cfg->use_direct)
        flags |= O_DIRECT;

    fd = open(cfg->file_path, flags, 0666);
    if (fd < 0 && cfg->use_direct) {
        fprintf(stderr, "warning: O_DIRECT open failed (%s), retrying buffered I/O\n", strerror(errno));
        flags &= ~O_DIRECT;
        fd = open(cfg->file_path, flags, 0666);
    }
    if (fd < 0) {
        perror("open");
        exit(EXIT_FAILURE);
    }

    return fd;
}

static void prepare_file(int fd, const struct kairo_config *cfg)
{
    if (ftruncate(fd, (off_t)cfg->file_size_bytes) != 0) {
        perror("ftruncate");
        close(fd);
        exit(EXIT_FAILURE);
    }
}

static void stats_init(struct kairo_stats *stats)
{
    memset(stats, 0, sizeof(*stats));
    pthread_mutex_init(&stats->lock, NULL);
    stats->decode_latencies_us = calloc(KAIRO_MAX_SAMPLES, sizeof(double));
    if (stats->decode_latencies_us == NULL) {
        perror("calloc");
        exit(EXIT_FAILURE);
    }
}

static void stats_destroy(struct kairo_stats *stats)
{
    pthread_mutex_destroy(&stats->lock);
    free(stats->decode_latencies_us);
}

static void record_ioprio_result(struct kairo_stats *stats, enum kairo_worker_kind kind, bool ok)
{
    pthread_mutex_lock(&stats->lock);
    switch (kind) {
    case KAIRO_WORKER_DECODE:
        if (ok)
            stats->ioprio_decode_ok++;
        else
            stats->ioprio_decode_fail++;
        break;
    case KAIRO_WORKER_PREFETCH:
        if (ok)
            stats->ioprio_prefetch_ok++;
        else
            stats->ioprio_prefetch_fail++;
        break;
    case KAIRO_WORKER_EVICT:
    case KAIRO_WORKER_WRITE:
    default:
        if (ok)
            stats->ioprio_write_ok++;
        else
            stats->ioprio_write_fail++;
        break;
    }
    pthread_mutex_unlock(&stats->lock);
}

static void record_rwf_attempt(struct kairo_stats *stats, enum kairo_worker_kind kind, bool failed)
{
    pthread_mutex_lock(&stats->lock);
    switch (kind) {
    case KAIRO_WORKER_DECODE:
        if (failed)
            stats->rwf_decode_fail++;
        else
            stats->rwf_decode_attempts++;
        break;
    case KAIRO_WORKER_PREFETCH:
        if (failed)
            stats->rwf_prefetch_fail++;
        else
            stats->rwf_prefetch_attempts++;
        break;
    case KAIRO_WORKER_WRITE:
        if (failed)
            stats->rwf_prefill_fail++;
        else
            stats->rwf_prefill_attempts++;
        break;
    case KAIRO_WORKER_EVICT:
    default:
        break;
    }
    pthread_mutex_unlock(&stats->lock);
}

static void record_rwf_semantic_attempt(struct kairo_stats *stats, uint64_t semantic_flags, bool failed)
{
    pthread_mutex_lock(&stats->lock);
    if (semantic_flags & KAIRO_RWF_EPHEMERAL) {
        if (failed)
            stats->rwf_ephemeral_fail++;
        else
            stats->rwf_ephemeral_attempts++;
    }
    if (semantic_flags & KAIRO_RWF_RECOMPUTE) {
        if (failed)
            stats->rwf_recompute_fail++;
        else
            stats->rwf_recompute_attempts++;
    }
    if (semantic_flags & KAIRO_RWF_NO_DURABILITY) {
        if (failed)
            stats->rwf_no_durability_fail++;
        else
            stats->rwf_no_durability_attempts++;
    }
    if (semantic_flags & KAIRO_RWF_AVOID_PAGECACHE) {
        if (failed)
            stats->rwf_avoid_pagecache_fail++;
        else
            stats->rwf_avoid_pagecache_attempts++;
    }
    pthread_mutex_unlock(&stats->lock);
}

static void record_decode(struct kairo_stats *stats, double latency_us, size_t bytes)
{
    pthread_mutex_lock(&stats->lock);
    stats->total_decode_reads++;
    stats->total_decode_bytes += bytes;
    stats->decode_latency_sum_us += latency_us;
    if (latency_us > stats->decode_latency_max_us)
        stats->decode_latency_max_us = latency_us;
    if (stats->decode_latency_samples < KAIRO_MAX_SAMPLES)
        stats->decode_latencies_us[stats->decode_latency_samples++] = latency_us;
    pthread_mutex_unlock(&stats->lock);
}

static void record_prefetch(struct kairo_stats *stats, size_t bytes)
{
    pthread_mutex_lock(&stats->lock);
    stats->total_prefetch_reads++;
    stats->total_prefetch_bytes += bytes;
    pthread_mutex_unlock(&stats->lock);
}

static void record_write(struct kairo_stats *stats, size_t bytes)
{
    pthread_mutex_lock(&stats->lock);
    stats->total_writes++;
    stats->total_write_bytes += bytes;
    pthread_mutex_unlock(&stats->lock);
}

static void record_evict(struct kairo_stats *stats, size_t bytes)
{
    pthread_mutex_lock(&stats->lock);
    stats->total_evictions++;
    stats->total_evict_bytes += bytes;
    pthread_mutex_unlock(&stats->lock);
}

static void snapshot_stats(struct kairo_stats *stats, struct kairo_stats_snapshot *snapshot)
{
    pthread_mutex_lock(&stats->lock);
    snapshot->total_decode_reads = stats->total_decode_reads;
    snapshot->total_prefetch_reads = stats->total_prefetch_reads;
    snapshot->total_writes = stats->total_writes;
    snapshot->total_evictions = stats->total_evictions;
    snapshot->total_decode_bytes = stats->total_decode_bytes;
    snapshot->total_prefetch_bytes = stats->total_prefetch_bytes;
    snapshot->total_write_bytes = stats->total_write_bytes;
    snapshot->total_evict_bytes = stats->total_evict_bytes;
    snapshot->decode_latency_samples = stats->decode_latency_samples;
    snapshot->decode_latency_sum_us = stats->decode_latency_sum_us;
    snapshot->decode_latency_max_us = stats->decode_latency_max_us;
    snapshot->decode_latencies_us = stats->decode_latencies_us;
    snapshot->ioprio_decode_ok = stats->ioprio_decode_ok;
    snapshot->ioprio_decode_fail = stats->ioprio_decode_fail;
    snapshot->ioprio_prefetch_ok = stats->ioprio_prefetch_ok;
    snapshot->ioprio_prefetch_fail = stats->ioprio_prefetch_fail;
    snapshot->ioprio_write_ok = stats->ioprio_write_ok;
    snapshot->ioprio_write_fail = stats->ioprio_write_fail;
    snapshot->rwf_decode_attempts = stats->rwf_decode_attempts;
    snapshot->rwf_decode_fail = stats->rwf_decode_fail;
    snapshot->rwf_prefetch_attempts = stats->rwf_prefetch_attempts;
    snapshot->rwf_prefetch_fail = stats->rwf_prefetch_fail;
    snapshot->rwf_prefill_attempts = stats->rwf_prefill_attempts;
    snapshot->rwf_prefill_fail = stats->rwf_prefill_fail;
    snapshot->rwf_ephemeral_attempts = stats->rwf_ephemeral_attempts;
    snapshot->rwf_ephemeral_fail = stats->rwf_ephemeral_fail;
    snapshot->rwf_recompute_attempts = stats->rwf_recompute_attempts;
    snapshot->rwf_recompute_fail = stats->rwf_recompute_fail;
    snapshot->rwf_no_durability_attempts = stats->rwf_no_durability_attempts;
    snapshot->rwf_no_durability_fail = stats->rwf_no_durability_fail;
    snapshot->rwf_avoid_pagecache_attempts = stats->rwf_avoid_pagecache_attempts;
    snapshot->rwf_avoid_pagecache_fail = stats->rwf_avoid_pagecache_fail;
    pthread_mutex_unlock(&stats->lock);
}

static off_t next_read_block(const struct kairo_worker_ctx *ctx, off_t op_index, off_t block_count)
{
    unsigned int session_seed = ctx->session_id * 131;
    unsigned int model_seed = ctx->model_id * 977;

    switch (ctx->cfg->access_pattern) {
    case KAIRO_ACCESS_SEQUENTIAL:
        return op_index % block_count;

    case KAIRO_ACCESS_STRIDED: {
        off_t stride = (off_t)ctx->cfg->stride_blocks;
        if (stride < 1)
            stride = 1;
        return (op_index * stride) % block_count;
    }

    case KAIRO_ACCESS_CLUSTERED: {
        off_t cluster = (off_t)ctx->cfg->cluster_size_blocks;
        if (cluster < 1)
            cluster = 1;
        off_t cluster_idx = (op_index / cluster) % block_count;
        off_t offset = op_index % cluster;
        return (cluster_idx + offset) % block_count;
    }

    case KAIRO_ACCESS_RANDOM:
    default:
        break;
    }

    if (!ctx->cfg->random_read)
        return op_index % block_count;

    if (ctx->kind == KAIRO_WORKER_PREFETCH)
        return (op_index * 31 + (off_t)session_seed + (off_t)model_seed) % block_count;

    if (ctx->kind == KAIRO_WORKER_EVICT)
        return (op_index * 7 + (off_t)session_seed + (off_t)(ctx->worker_id * 3)) % block_count;

    return (op_index * 17 + (off_t)session_seed + (off_t)ctx->worker_id + (off_t)model_seed) % block_count;
}

static int do_evict_op(struct kairo_worker_ctx *ctx, void *buffer, size_t block_size, off_t file_offset)
{
#ifdef FALLOC_FL_PUNCH_HOLE
    if (fallocate(ctx->fd, FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE,
                  file_offset, (off_t)block_size) == 0) {
        record_evict(ctx->stats, block_size);
        return 0;
    }

    if (errno != EOPNOTSUPP && errno != ENOTTY && errno != ENOSYS)
        return -1;
#endif

    memset(buffer, 0, block_size);
    if (pwrite(ctx->fd, buffer, block_size, file_offset) != (ssize_t)block_size)
        return -1;
    record_evict(ctx->stats, block_size);
    return 0;
}

static uint64_t kairo_rwf_for_worker(enum kairo_worker_kind kind)
{
    switch (kind) {
    case KAIRO_WORKER_DECODE:
        return KAIRO_RWF_DECODE;
    case KAIRO_WORKER_PREFETCH:
        return KAIRO_RWF_PREFETCH;
    case KAIRO_WORKER_WRITE:
        return KAIRO_RWF_PREFILL;
    case KAIRO_WORKER_EVICT:
    default:
        return 0;
    }
}

static uint64_t kairo_semantic_rwf_flags(const struct kairo_worker_ctx *ctx)
{
    switch (ctx->cfg->semantic_mode) {
    case KAIRO_SEMANTIC_EPHEMERAL:
        if (ctx->kind == KAIRO_WORKER_WRITE || ctx->kind == KAIRO_WORKER_EVICT)
            return KAIRO_RWF_EPHEMERAL;
        return 0;
    case KAIRO_SEMANTIC_RECOMPUTABLE:
        if (ctx->kind == KAIRO_WORKER_WRITE)
            return KAIRO_RWF_RECOMPUTE | KAIRO_RWF_NO_DURABILITY;
        return 0;
    case KAIRO_SEMANTIC_EPHEMERAL_RECOMPUTABLE: {
        uint64_t flags = KAIRO_RWF_AVOID_PAGECACHE;
        if (ctx->kind == KAIRO_WORKER_WRITE)
            flags |= KAIRO_RWF_EPHEMERAL | KAIRO_RWF_RECOMPUTE | KAIRO_RWF_NO_DURABILITY;
        if (ctx->kind == KAIRO_WORKER_EVICT)
            flags |= KAIRO_RWF_EPHEMERAL | KAIRO_RWF_EVICT_CLEANUP;
        return flags;
    }
    case KAIRO_SEMANTIC_NORMAL:
    default:
        return 0;
    }
}

static bool kairo_should_fallback_errno(int err)
{
    return err == EINVAL || err == EOPNOTSUPP || err == ENOSYS;
}

static ssize_t kairo_pread_with_hints(struct kairo_worker_ctx *ctx, void *buffer,
                                      size_t io_size, off_t file_offset)
{
    struct iovec iov = {
        .iov_base = buffer,
        .iov_len = io_size,
    };
    const uint64_t rwf = kairo_rwf_for_worker(ctx->kind) | kairo_semantic_rwf_flags(ctx);
    const uint64_t semantic_flags = kairo_semantic_rwf_flags(ctx);

    if (!kairo_hint_mode_uses_rwf(ctx->cfg->hint_mode) || rwf == 0)
        return pread(ctx->fd, buffer, io_size, file_offset);

    record_rwf_attempt(ctx->stats, ctx->kind, false);
    record_rwf_semantic_attempt(ctx->stats, semantic_flags, false);
    errno = 0;
    ssize_t rc = syscall(SYS_preadv2, ctx->fd, &iov, 1, (long)file_offset, (long)(file_offset >> 32), rwf);
    if (rc >= 0)
        return rc;

    if (kairo_should_fallback_errno(errno)) {
        record_rwf_attempt(ctx->stats, ctx->kind, true);
        record_rwf_semantic_attempt(ctx->stats, semantic_flags, true);
        return pread(ctx->fd, buffer, io_size, file_offset);
    }

    return rc;
}

static ssize_t kairo_pwrite_with_hints(struct kairo_worker_ctx *ctx, void *buffer,
                                       size_t io_size, off_t file_offset)
{
    struct iovec iov = {
        .iov_base = buffer,
        .iov_len = io_size,
    };
    const uint64_t rwf = kairo_rwf_for_worker(ctx->kind) | kairo_semantic_rwf_flags(ctx);
    const uint64_t semantic_flags = kairo_semantic_rwf_flags(ctx);

    if (!kairo_hint_mode_uses_rwf(ctx->cfg->hint_mode) || rwf == 0)
        return pwrite(ctx->fd, buffer, io_size, file_offset);

    record_rwf_attempt(ctx->stats, ctx->kind, false);
    record_rwf_semantic_attempt(ctx->stats, semantic_flags, false);
    errno = 0;
    ssize_t rc = syscall(SYS_pwritev2, ctx->fd, &iov, 1, (long)file_offset, (long)(file_offset >> 32), rwf);
    if (rc >= 0)
        return rc;

    if (kairo_should_fallback_errno(errno)) {
        record_rwf_attempt(ctx->stats, ctx->kind, true);
        record_rwf_semantic_attempt(ctx->stats, semantic_flags, true);
        return pwrite(ctx->fd, buffer, io_size, file_offset);
    }

    return rc;
}

static void *worker_main(void *arg)
{
    struct kairo_worker_ctx *ctx = (struct kairo_worker_ctx *)arg;
    void *buffer = NULL;
    size_t block_size = ctx->cfg->block_size_bytes;
    size_t io_size = ctx->cfg->fragment_size_bytes > 0
                        ? ctx->cfg->fragment_size_bytes
                        : block_size;
    off_t block_count = (off_t)(ctx->region_length / (off_t)block_size);
    off_t fragments_per_block = block_size / io_size;
    off_t op_index = 0;
    int memalign_rc;

    if (kairo_hint_mode_uses_ioprio(ctx->cfg->hint_mode)) {
        if (set_current_ioprio(ctx->kind) != 0) {
            record_ioprio_result(ctx->stats, ctx->kind, false);
            fprintf(stderr,
                    "warning: ioprio_set failed for %s worker %u: %s. "
                    "Run with enough privilege if you need realtime-class signaling.\n",
                    worker_kind_name(ctx->kind),
                    ctx->worker_id,
                    strerror(errno));
        } else {
            record_ioprio_result(ctx->stats, ctx->kind, true);
        }
    }

    memalign_rc = posix_memalign(&buffer, KAIRO_DIRECT_ALIGN, io_size);
    if (memalign_rc != 0) {
        fprintf(stderr, "posix_memalign failed for %s worker %u: %s\n",
                worker_kind_name(ctx->kind), ctx->worker_id, strerror(memalign_rc));
        return (void *)1;
    }

    memset(buffer, ctx->kind == KAIRO_WORKER_WRITE ? ('A' + (ctx->worker_id % 26)) : 0, io_size);

    while (!*(ctx->stop)) {
        off_t block_offset;
        off_t file_offset;
        ssize_t rc;

        if (block_count == 0)
            break;

        if (ctx->kind == KAIRO_WORKER_WRITE)
            block_offset = op_index % block_count;
        else
            block_offset = next_read_block(ctx, op_index, block_count);

        if (ctx->cfg->fragment_size_bytes > 0 && ctx->kind != KAIRO_WORKER_WRITE) {
            off_t frag = op_index % fragments_per_block;
            file_offset = ctx->region_start
                        + (block_offset * (off_t)block_size)
                        + (frag * (off_t)io_size);
        } else {
            file_offset = ctx->region_start + (block_offset * (off_t)block_size);
        }

        if (ctx->kind == KAIRO_WORKER_WRITE) {
            rc = kairo_pwrite_with_hints(ctx, buffer, io_size, file_offset);
            if (rc < 0) {
                perror("pwrite");
                break;
            }
            if ((size_t)rc != io_size) {
                fprintf(stderr, "short write on %s worker %u: expected %zu got %zd\n",
                        worker_kind_name(ctx->kind), ctx->worker_id, io_size, rc);
                break;
            }
            record_write(ctx->stats, io_size);
        } else if (ctx->kind == KAIRO_WORKER_EVICT) {
            if (do_evict_op(ctx, buffer, io_size, file_offset) != 0) {
                perror("evict");
                break;
            }
        } else {
            struct timespec start_ts;
            struct timespec end_ts;
            double latency_us;

            if (clock_gettime(CLOCK_MONOTONIC, &start_ts) != 0) {
                perror("clock_gettime");
                break;
            }
            rc = kairo_pread_with_hints(ctx, buffer, io_size, file_offset);
            if (clock_gettime(CLOCK_MONOTONIC, &end_ts) != 0) {
                perror("clock_gettime");
                break;
            }
            if (rc < 0) {
                perror("pread");
                break;
            }
            if ((size_t)rc != io_size) {
                fprintf(stderr, "short read on %s worker %u: expected %zu got %zd\n",
                        worker_kind_name(ctx->kind), ctx->worker_id, io_size, rc);
                break;
            }

            latency_us = timespec_diff_us(&start_ts, &end_ts);
            if (ctx->kind == KAIRO_WORKER_DECODE)
                record_decode(ctx->stats, latency_us, io_size);
            else
                record_prefetch(ctx->stats, io_size);
        }

        op_index++;
    }

    free(buffer);
    return NULL;
}

static void print_summary(const struct kairo_config *cfg, const struct kairo_stats *stats)
{
    double decode_avg_us = 0.0;
    double decode_p50_us = 0.0;
    double decode_p95_us = 0.0;
    double decode_p99_us = 0.0;
    double decode_read_mbps;
    double prefetch_read_mbps;
    double write_mbps;
    double evict_mbps;
    double *sorted = NULL;
    uint64_t decode_lat_0_10us = 0;
    uint64_t decode_lat_10_25us = 0;
    uint64_t decode_lat_25_50us = 0;
    uint64_t decode_lat_50_100us = 0;
    uint64_t decode_lat_100_250us = 0;
    uint64_t decode_lat_250_500us = 0;
    uint64_t decode_lat_500_1000us = 0;
    uint64_t decode_lat_1ms_2ms = 0;
    uint64_t decode_lat_2ms_5ms = 0;
    uint64_t decode_lat_gt_5ms = 0;
    struct kairo_stats_snapshot snapshot;

    snapshot_stats((struct kairo_stats *)stats, &snapshot);

    if (snapshot.decode_latency_samples > 0) {
        uint64_t i;
        sorted = malloc((size_t)snapshot.decode_latency_samples * sizeof(*sorted));
        if (sorted == NULL) {
            perror("malloc");
            exit(EXIT_FAILURE);
        }
        memcpy(sorted,
               snapshot.decode_latencies_us,
               (size_t)snapshot.decode_latency_samples * sizeof(*sorted));
        qsort(sorted, (size_t)snapshot.decode_latency_samples, sizeof(*sorted), compare_double);
        decode_avg_us = (double)(snapshot.decode_latency_sum_us / (long double)snapshot.decode_latency_samples);
        decode_p50_us = percentile_from_sorted(sorted, snapshot.decode_latency_samples, 50.0);
        decode_p95_us = percentile_from_sorted(sorted, snapshot.decode_latency_samples, 95.0);
        decode_p99_us = percentile_from_sorted(sorted, snapshot.decode_latency_samples, 99.0);
        for (i = 0; i < snapshot.decode_latency_samples; i++) {
            double lat = snapshot.decode_latencies_us[i];
            if (lat <= 10.0)
                decode_lat_0_10us++;
            else if (lat <= 25.0)
                decode_lat_10_25us++;
            else if (lat <= 50.0)
                decode_lat_25_50us++;
            else if (lat <= 100.0)
                decode_lat_50_100us++;
            else if (lat <= 250.0)
                decode_lat_100_250us++;
            else if (lat <= 500.0)
                decode_lat_250_500us++;
            else if (lat <= 1000.0)
                decode_lat_500_1000us++;
            else if (lat <= 2000.0)
                decode_lat_1ms_2ms++;
            else if (lat <= 5000.0)
                decode_lat_2ms_5ms++;
            else
                decode_lat_gt_5ms++;
        }
    }

    decode_read_mbps = cfg->runtime_seconds
        ? ((double)snapshot.total_decode_bytes / (1024.0 * 1024.0)) / (double)cfg->runtime_seconds
        : 0.0;
    prefetch_read_mbps = cfg->runtime_seconds
        ? ((double)snapshot.total_prefetch_bytes / (1024.0 * 1024.0)) / (double)cfg->runtime_seconds
        : 0.0;
    write_mbps = cfg->runtime_seconds
        ? ((double)snapshot.total_write_bytes / (1024.0 * 1024.0)) / (double)cfg->runtime_seconds
        : 0.0;
    evict_mbps = cfg->runtime_seconds
        ? ((double)snapshot.total_evict_bytes / (1024.0 * 1024.0)) / (double)cfg->runtime_seconds
        : 0.0;

    puts("kairo_bench summary");
    printf("file=%s\n", cfg->file_path);
    printf("mode=%s\n", kairo_mode_name(cfg->mode));
    printf("hint_mode=%s\n", kairo_hint_mode_name(cfg->hint_mode));
    printf("semantic_mode=%s\n", kairo_semantic_mode_name(cfg->semantic_mode));
    printf("access_pattern=%s\n", kairo_access_pattern_name(cfg->access_pattern));
    printf("stride_blocks=%u\n", cfg->stride_blocks);
    printf("cluster_size_blocks=%u\n", cfg->cluster_size_blocks);
    printf("fragment_size_bytes=%zu\n", cfg->fragment_size_bytes);
    printf("block_size_bytes=%zu\n", cfg->block_size_bytes);
    printf("sessions=%u\n", cfg->sessions);
    printf("models=%u\n", cfg->models);
    printf("decode_threads=%u\n", cfg->decode_threads);
    printf("prefetch_threads=%u\n", cfg->prefetch_threads);
    printf("write_threads=%u\n", cfg->write_threads);
    printf("evict_threads=%u\n", cfg->evict_threads);
    printf("cache_pools=%u\n", cfg->cache_pools);
    printf("placement_groups=%u\n", cfg->placement_groups);
    printf("lifetime=%s\n", kairo_user_lifetime_name(cfg->lifetime_class));
    printf("recompute_ok=%d\n", cfg->recompute_ok);
    printf("fixed_model_id=%u\n", cfg->fixed_model_id);
    printf("fixed_session_id=%u\n", cfg->fixed_session_id);
    printf("fixed_cache_pool_id=%u\n", cfg->fixed_cache_pool_id);
    printf("fixed_placement_group=%u\n", cfg->fixed_placement_group);
    printf("noisy_session=%u\n", cfg->noisy_session);
    printf("noisy_model=%u\n", cfg->noisy_model);
    printf("noisy_multiplier=%u\n", cfg->noisy_multiplier);
    printf("fairness_mode=%s\n",
           cfg->noisy_session > 0 || cfg->noisy_model > 0 ? "stress" : "none");
    {
        struct kairo_backend_model m = kairo_compute_backend_model(cfg);
        printf("backend_mode=%s\n", kairo_backend_mode_name(cfg->backend_mode));
        printf("backend_class=%s\n", m.class_name);
        printf("stream_id=%u\n", m.stream_id);
        printf("stream_id_span=%s\n", m.stream_id_span);
        printf("fdp_placement_id=%u\n", m.fdp_placement_id);
        printf("fdp_placement_span=%s\n", m.fdp_placement_span);
        printf("zone_hint=%u\n", m.zone_hint);
        printf("backend_noop_fallback=%s\n",
               m.noop_fallback ? "true" : "false");
    }

    printf("decode_total_reads=%" PRIu64 "\n", snapshot.total_decode_reads);
    printf("prefetch_total_reads=%" PRIu64 "\n", snapshot.total_prefetch_reads);
    printf("write_total_ops=%" PRIu64 "\n", snapshot.total_writes);
    printf("evict_total_ops=%" PRIu64 "\n", snapshot.total_evictions);
    printf("decode_avg_us=%.2f\n", decode_avg_us);
    printf("decode_p50_us=%.2f\n", decode_p50_us);
    printf("decode_p95_us=%.2f\n", decode_p95_us);
    printf("decode_p99_us=%.2f\n", decode_p99_us);
    printf("decode_max_us=%.2f\n", snapshot.decode_latency_max_us);
    printf("decode_read_MBps=%.2f\n", decode_read_mbps);
    printf("prefetch_read_MBps=%.2f\n", prefetch_read_mbps);
    printf("write_MBps=%.2f\n", write_mbps);
    printf("evict_MBps=%.2f\n", evict_mbps);
    printf("decode_lat_0_10us=%" PRIu64 "\n", decode_lat_0_10us);
    printf("decode_lat_10_25us=%" PRIu64 "\n", decode_lat_10_25us);
    printf("decode_lat_25_50us=%" PRIu64 "\n", decode_lat_25_50us);
    printf("decode_lat_50_100us=%" PRIu64 "\n", decode_lat_50_100us);
    printf("decode_lat_100_250us=%" PRIu64 "\n", decode_lat_100_250us);
    printf("decode_lat_250_500us=%" PRIu64 "\n", decode_lat_250_500us);
    printf("decode_lat_500_1000us=%" PRIu64 "\n", decode_lat_500_1000us);
    printf("decode_lat_1ms_2ms=%" PRIu64 "\n", decode_lat_1ms_2ms);
    printf("decode_lat_2ms_5ms=%" PRIu64 "\n", decode_lat_2ms_5ms);
    printf("decode_lat_gt_5ms=%" PRIu64 "\n", decode_lat_gt_5ms);
    printf("ioprio_decode_ok=%" PRIu64 "\n", snapshot.ioprio_decode_ok);
    printf("ioprio_decode_fail=%" PRIu64 "\n", snapshot.ioprio_decode_fail);
    printf("ioprio_prefetch_ok=%" PRIu64 "\n", snapshot.ioprio_prefetch_ok);
    printf("ioprio_prefetch_fail=%" PRIu64 "\n", snapshot.ioprio_prefetch_fail);
    printf("ioprio_write_ok=%" PRIu64 "\n", snapshot.ioprio_write_ok);
    printf("ioprio_write_fail=%" PRIu64 "\n", snapshot.ioprio_write_fail);
    printf("rwf_decode_attempts=%" PRIu64 "\n", snapshot.rwf_decode_attempts);
    printf("rwf_decode_fail=%" PRIu64 "\n", snapshot.rwf_decode_fail);
    printf("rwf_prefetch_attempts=%" PRIu64 "\n", snapshot.rwf_prefetch_attempts);
    printf("rwf_prefetch_fail=%" PRIu64 "\n", snapshot.rwf_prefetch_fail);
    printf("rwf_prefill_attempts=%" PRIu64 "\n", snapshot.rwf_prefill_attempts);
    printf("rwf_prefill_fail=%" PRIu64 "\n", snapshot.rwf_prefill_fail);
    printf("rwf_ephemeral_attempts=%" PRIu64 "\n", snapshot.rwf_ephemeral_attempts);
    printf("rwf_ephemeral_fail=%" PRIu64 "\n", snapshot.rwf_ephemeral_fail);
    printf("rwf_recompute_attempts=%" PRIu64 "\n", snapshot.rwf_recompute_attempts);
    printf("rwf_recompute_fail=%" PRIu64 "\n", snapshot.rwf_recompute_fail);
    printf("rwf_no_durability_attempts=%" PRIu64 "\n", snapshot.rwf_no_durability_attempts);
    printf("rwf_no_durability_fail=%" PRIu64 "\n", snapshot.rwf_no_durability_fail);
    printf("rwf_avoid_pagecache_attempts=%" PRIu64 "\n", snapshot.rwf_avoid_pagecache_attempts);
    printf("rwf_avoid_pagecache_fail=%" PRIu64 "\n", snapshot.rwf_avoid_pagecache_fail);
    puts("todo=replace pthread pread/pwrite path with io_uring worker path");

    free(sorted);
}

int main(int argc, char **argv)
{
    struct kairo_config cfg;
    struct kairo_stats stats;
    pthread_t *threads = NULL;
    struct kairo_worker_ctx *workers = NULL;
    volatile bool stop = false;
    unsigned int total_threads;
    unsigned int index = 0;
    unsigned int i;
    unsigned int mode_total_pct;
    off_t decode_region;
    off_t prefetch_region;
    off_t write_region_start;
    off_t write_region_length;
    int fd;
    int opt;
    int option_index = 0;

    static const struct option long_options[] = {
        {"file", required_argument, NULL, 'f'},
        {"mode", required_argument, NULL, 'm'},
        {"size", required_argument, NULL, 's'},
        {"block-size", required_argument, NULL, 'b'},
        {"decode-threads", required_argument, NULL, 'd'},
        {"prefetch-threads", required_argument, NULL, 'p'},
        {"write-threads", required_argument, NULL, 'w'},
        {"evict-threads", required_argument, NULL, 'e'},
        {"runtime", required_argument, NULL, 't'},
        {"queue-depth", required_argument, NULL, 'q'},
        {"sessions", required_argument, NULL, 'S'},
        {"models", required_argument, NULL, 'M'},
        {"prefill-region-pct", required_argument, NULL, 'P'},
        {"decode-region-pct", required_argument, NULL, 'D'},
        {"access-pattern", required_argument, NULL, 'A'},
        {"hint-mode", required_argument, NULL, 7},
        {"stride-blocks", required_argument, NULL, 4},
        {"cluster-size-blocks", required_argument, NULL, 5},
        {"fragment-size", required_argument, NULL, 6},
        {"semantic-mode", required_argument, NULL, 8},
        {"model-id", required_argument, NULL, 9},
        {"session-id", required_argument, NULL, 10},
        {"cache-pool-id", required_argument, NULL, 11},
        {"placement-group", required_argument, NULL, 12},
        {"lifetime", required_argument, NULL, 13},
        {"recompute-ok", no_argument, NULL, 14},
        {"cache-pools", required_argument, NULL, 15},
        {"placement-groups", required_argument, NULL, 16},
        {"backend-mode", required_argument, NULL, 17},
        {"noisy-session", required_argument, NULL, 18},
        {"noisy-model", required_argument, NULL, 19},
        {"noisy-multiplier", required_argument, NULL, 20},
        {"random-read", no_argument, NULL, 1},
        {"sequential-read", no_argument, NULL, 2},
        {"buffered", no_argument, NULL, 3},
        {0, 0, 0, 0},
    };

    set_defaults(&cfg);

    while ((opt = getopt_long(argc, argv, "f:m:s:b:d:p:w:e:t:q:S:M:P:D:A:", long_options, &option_index)) != -1) {
        switch (opt) {
        case 'f':
            cfg.file_path = optarg;
            break;
        case 'm':
            cfg.mode = parse_mode(optarg);
            break;
        case 's':
            cfg.file_size_bytes = parse_size(optarg, "size");
            break;
        case 'b':
            cfg.block_size_bytes = (size_t)parse_size(optarg, "block-size");
            break;
        case 'd':
            cfg.decode_threads = (unsigned int)parse_size(optarg, "decode-threads");
            break;
        case 'p':
            cfg.prefetch_threads = (unsigned int)parse_size(optarg, "prefetch-threads");
            break;
        case 'w':
            cfg.write_threads = (unsigned int)parse_size(optarg, "write-threads");
            break;
        case 'e':
            cfg.evict_threads = (unsigned int)parse_size(optarg, "evict-threads");
            cfg.evict_threads_explicit = true;
            break;
        case 't':
            cfg.runtime_seconds = (unsigned int)parse_size(optarg, "runtime");
            break;
        case 'q':
            cfg.queue_depth_hint = (unsigned int)parse_size(optarg, "queue-depth");
            break;
        case 'S':
            cfg.sessions = (unsigned int)parse_size(optarg, "sessions");
            break;
        case 'M':
            cfg.models = (unsigned int)parse_size(optarg, "models");
            break;
        case 'P':
            cfg.prefill_region_pct = (unsigned int)parse_size(optarg, "prefill-region-pct");
            break;
        case 'D':
            cfg.decode_region_pct = (unsigned int)parse_size(optarg, "decode-region-pct");
            break;
        case 'A':
            cfg.access_pattern = parse_access_pattern(optarg);
            cfg.random_read = (cfg.access_pattern == KAIRO_ACCESS_RANDOM);
            break;
        case 7:
            cfg.hint_mode = parse_hint_mode(optarg);
            break;
        case 8:
            cfg.semantic_mode = parse_semantic_mode(optarg);
            break;
        case 9:
            cfg.fixed_model_id = (unsigned int)parse_size(optarg, "model-id");
            break;
        case 10:
            cfg.fixed_session_id = (unsigned int)parse_size(optarg, "session-id");
            break;
        case 11:
            cfg.fixed_cache_pool_id = (unsigned int)parse_size(optarg, "cache-pool-id");
            break;
        case 12:
            cfg.fixed_placement_group = (unsigned int)parse_size(optarg, "placement-group");
            break;
        case 13:
            cfg.lifetime_class = parse_lifetime(optarg);
            break;
        case 14:
            cfg.recompute_ok = true;
            break;
        case 15:
            cfg.cache_pools = (unsigned int)parse_size(optarg, "cache-pools");
            break;
        case 16:
            cfg.placement_groups = (unsigned int)parse_size(optarg, "placement-groups");
            break;
        case 17:
            cfg.backend_mode = parse_backend_mode(optarg);
            break;
        case 18:
            cfg.noisy_session = (unsigned int)parse_size(optarg, "noisy-session");
            break;
        case 19:
            cfg.noisy_model = (unsigned int)parse_size(optarg, "noisy-model");
            break;
        case 20:
            cfg.noisy_multiplier = (unsigned int)parse_size(optarg, "noisy-multiplier");
            break;
        case 4:
            cfg.stride_blocks = (unsigned int)parse_size(optarg, "stride-blocks");
            break;
        case 5:
            cfg.cluster_size_blocks = (unsigned int)parse_size(optarg, "cluster-size-blocks");
            break;
        case 6:
            cfg.fragment_size_bytes = (size_t)parse_size(optarg, "fragment-size");
            break;
        case 1:
            cfg.random_read = true;
            cfg.access_pattern = KAIRO_ACCESS_RANDOM;
            break;
        case 2:
            cfg.random_read = false;
            cfg.access_pattern = KAIRO_ACCESS_SEQUENTIAL;
            break;
        case 3:
            cfg.use_direct = false;
            break;
        default:
            usage(argv[0]);
            return EXIT_FAILURE;
        }
    }

    apply_mode_defaults(&cfg);
    validate_config(&cfg);
    fd = open_target(&cfg);
    prepare_file(fd, &cfg);
    stats_init(&stats);

    total_threads = cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads + cfg.evict_threads;
    threads = calloc(total_threads, sizeof(*threads));
    workers = calloc(total_threads, sizeof(*workers));
    if (threads == NULL || workers == NULL) {
        perror("calloc");
        close(fd);
        stats_destroy(&stats);
        free(threads);
        free(workers);
        return EXIT_FAILURE;
    }

    mode_total_pct = cfg.decode_region_pct + cfg.prefill_region_pct;
    decode_region = (off_t)((cfg.file_size_bytes * cfg.decode_region_pct) / 100U);
    decode_region -= decode_region % (off_t)cfg.block_size_bytes;
    if (cfg.decode_threads > 0 && decode_region == 0)
        decode_region = (off_t)cfg.block_size_bytes;

    prefetch_region = (off_t)((cfg.file_size_bytes * (100U - mode_total_pct)) / 100U);
    prefetch_region -= prefetch_region % (off_t)cfg.block_size_bytes;
    if ((cfg.prefetch_threads > 0 || cfg.write_threads > 0 || cfg.evict_threads > 0) && prefetch_region == 0)
        prefetch_region = (off_t)cfg.block_size_bytes;

    write_region_start = decode_region;
    write_region_length = (off_t)cfg.file_size_bytes - decode_region;
    if (write_region_length < (off_t)cfg.block_size_bytes) {
        write_region_start = 0;
        write_region_length = (off_t)cfg.file_size_bytes;
    }

    for (i = 0; i < cfg.decode_threads; i++, index++) {
        workers[index] = (struct kairo_worker_ctx){
            .fd = fd,
            .cfg = &cfg,
            .stats = &stats,
            .worker_id = i,
            .session_id = cfg.fixed_session_id > 0 ? cfg.fixed_session_id : i % cfg.sessions,
            .model_id = cfg.fixed_model_id > 0 ? cfg.fixed_model_id : i % cfg.models,
            .cache_pool_id = cfg.fixed_cache_pool_id > 0 ? cfg.fixed_cache_pool_id : i % cfg.cache_pools,
            .placement_group = cfg.fixed_placement_group > 0 ? cfg.fixed_placement_group : i % cfg.placement_groups,
            .kind = KAIRO_WORKER_DECODE,
            .stop = &stop,
            .region_start = 0,
            .region_length = decode_region ? decode_region : (off_t)cfg.file_size_bytes,
        };
        pthread_create(&threads[index], NULL, worker_main, &workers[index]);
    }

    for (i = 0; i < cfg.prefetch_threads; i++, index++) {
        workers[index] = (struct kairo_worker_ctx){
            .fd = fd,
            .cfg = &cfg,
            .stats = &stats,
            .worker_id = i,
            .session_id = cfg.fixed_session_id > 0 ? cfg.fixed_session_id : (i + cfg.decode_threads) % cfg.sessions,
            .model_id = cfg.fixed_model_id > 0 ? cfg.fixed_model_id : (i + cfg.decode_threads) % cfg.models,
            .cache_pool_id = cfg.fixed_cache_pool_id > 0 ? cfg.fixed_cache_pool_id : (i + cfg.decode_threads) % cfg.cache_pools,
            .placement_group = cfg.fixed_placement_group > 0 ? cfg.fixed_placement_group : (i + cfg.decode_threads) % cfg.placement_groups,
            .kind = KAIRO_WORKER_PREFETCH,
            .stop = &stop,
            .region_start = decode_region,
            .region_length = prefetch_region ? prefetch_region : write_region_length,
        };
        pthread_create(&threads[index], NULL, worker_main, &workers[index]);
    }

    for (i = 0; i < cfg.write_threads; i++, index++) {
        workers[index] = (struct kairo_worker_ctx){
            .fd = fd,
            .cfg = &cfg,
            .stats = &stats,
            .worker_id = i,
            .session_id = cfg.fixed_session_id > 0 ? cfg.fixed_session_id : (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.sessions,
            .model_id = cfg.fixed_model_id > 0 ? cfg.fixed_model_id : (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.models,
            .cache_pool_id = cfg.fixed_cache_pool_id > 0 ? cfg.fixed_cache_pool_id : (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.cache_pools,
            .placement_group = cfg.fixed_placement_group > 0 ? cfg.fixed_placement_group : (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.placement_groups,
            .kind = KAIRO_WORKER_WRITE,
            .stop = &stop,
            .region_start = write_region_start,
            .region_length = write_region_length,
        };
        pthread_create(&threads[index], NULL, worker_main, &workers[index]);
    }

    for (i = 0; i < cfg.evict_threads; i++, index++) {
        workers[index] = (struct kairo_worker_ctx){
            .fd = fd,
            .cfg = &cfg,
            .stats = &stats,
            .worker_id = i,
            .session_id = cfg.fixed_session_id > 0 ? cfg.fixed_session_id : (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.sessions,
            .model_id = cfg.fixed_model_id > 0 ? cfg.fixed_model_id : (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.models,
            .cache_pool_id = cfg.fixed_cache_pool_id > 0 ? cfg.fixed_cache_pool_id : (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.cache_pools,
            .placement_group = cfg.fixed_placement_group > 0 ? cfg.fixed_placement_group : (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.placement_groups,
            .kind = KAIRO_WORKER_EVICT,
            .stop = &stop,
            .region_start = write_region_start,
            .region_length = write_region_length,
        };
        pthread_create(&threads[index], NULL, worker_main, &workers[index]);
    }

    sleep(cfg.runtime_seconds);
    stop = true;

    for (i = 0; i < total_threads; i++)
        pthread_join(threads[i], NULL);

    print_summary(&cfg, &stats);

    free(threads);
    free(workers);
    stats_destroy(&stats);
    close(fd);
    return 0;
}
