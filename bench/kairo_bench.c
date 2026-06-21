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
#include <time.h>
#include <unistd.h>

#include "kairo_hints.h"

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
    default:
        return "mixed";
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

    fprintf(stderr, "invalid mode: %s\n", value);
    exit(EXIT_FAILURE);
}

static void usage(const char *prog)
{
    fprintf(stderr,
            "Usage: %s --file <path> [options]\n"
            "  --file <path>             Target file path\n"
            "  --mode <name>             decode-only|mixed|prefetch-pressure|eviction-pressure|multisession\n"
            "  --size <bytes|K|M|G>      File size, default 8G\n"
            "  --block-size <bytes|K|M|G>\n"
            "                            I/O block size, default 1M\n"
            "  --decode-threads <n>      Default 4\n"
            "  --prefetch-threads <n>    Default 1\n"
            "  --write-threads <n>       Default 2\n"
            "  --evict-threads <n>       Default 0\n"
            "  --sessions <n>            Default 1\n"
            "  --models <n>              Default 1\n"
            "  --prefill-region-pct <n>  Default 34\n"
            "  --decode-region-pct <n>   Default 33\n"
            "  --runtime <sec>           Default 60\n"
            "  --queue-depth <n>         Placeholder for future io_uring path\n"
            "  --random-read             Default mode\n"
            "  --sequential-read         Disable random read placement\n"
            "  --buffered                Disable O_DIRECT\n",
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

static int set_current_ioprio(enum kairo_worker_kind kind)
{
    int prio;

    switch (kind) {
    case KAIRO_WORKER_DECODE:
        prio = IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_DECODE_READ);
        break;
    case KAIRO_WORKER_PREFETCH:
        prio = IOPRIO_PRIO_VALUE(IOPRIO_CLASS_RT, KAIRO_CLASS_PREFETCH_READ);
        break;
    case KAIRO_WORKER_EVICT:
        prio = IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 6);
        break;
    case KAIRO_WORKER_WRITE:
    default:
        prio = IOPRIO_PRIO_VALUE(IOPRIO_CLASS_BE, 7);
        break;
    }

    return syscall(SYS_ioprio_set, IOPRIO_WHO_PROCESS, 0, prio);
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
    case KAIRO_MODE_MIXED:
    default:
        break;
    }
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
    pthread_mutex_unlock(&stats->lock);
}

static off_t next_read_block(const struct kairo_worker_ctx *ctx, off_t op_index, off_t block_count)
{
    unsigned int session_seed = ctx->session_id * 131;
    unsigned int model_seed = ctx->model_id * 977;

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

static void *worker_main(void *arg)
{
    struct kairo_worker_ctx *ctx = (struct kairo_worker_ctx *)arg;
    void *buffer = NULL;
    size_t block_size = ctx->cfg->block_size_bytes;
    off_t block_count = (off_t)(ctx->region_length / (off_t)block_size);
    off_t op_index = 0;
    int memalign_rc;

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

    memalign_rc = posix_memalign(&buffer, KAIRO_DIRECT_ALIGN, block_size);
    if (memalign_rc != 0) {
        fprintf(stderr, "posix_memalign failed for %s worker %u: %s\n",
                worker_kind_name(ctx->kind), ctx->worker_id, strerror(memalign_rc));
        return (void *)1;
    }

    memset(buffer, ctx->kind == KAIRO_WORKER_WRITE ? ('A' + (ctx->worker_id % 26)) : 0, block_size);

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

        file_offset = ctx->region_start + (block_offset * (off_t)block_size);

        if (ctx->kind == KAIRO_WORKER_WRITE) {
            rc = pwrite(ctx->fd, buffer, block_size, file_offset);
            if (rc < 0) {
                perror("pwrite");
                break;
            }
            if ((size_t)rc != block_size) {
                fprintf(stderr, "short write on %s worker %u: expected %zu got %zd\n",
                        worker_kind_name(ctx->kind), ctx->worker_id, block_size, rc);
                break;
            }
            record_write(ctx->stats, block_size);
        } else if (ctx->kind == KAIRO_WORKER_EVICT) {
            if (do_evict_op(ctx, buffer, block_size, file_offset) != 0) {
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
            rc = pread(ctx->fd, buffer, block_size, file_offset);
            if (clock_gettime(CLOCK_MONOTONIC, &end_ts) != 0) {
                perror("clock_gettime");
                break;
            }
            if (rc < 0) {
                perror("pread");
                break;
            }
            if ((size_t)rc != block_size) {
                fprintf(stderr, "short read on %s worker %u: expected %zu got %zd\n",
                        worker_kind_name(ctx->kind), ctx->worker_id, block_size, rc);
                break;
            }

            latency_us = timespec_diff_us(&start_ts, &end_ts);
            if (ctx->kind == KAIRO_WORKER_DECODE)
                record_decode(ctx->stats, latency_us, block_size);
            else
                record_prefetch(ctx->stats, block_size);
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
    struct kairo_stats_snapshot snapshot;

    snapshot_stats((struct kairo_stats *)stats, &snapshot);

    if (snapshot.decode_latency_samples > 0) {
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
    printf("sessions=%u\n", cfg->sessions);
    printf("models=%u\n", cfg->models);
    printf("decode_threads=%u\n", cfg->decode_threads);
    printf("prefetch_threads=%u\n", cfg->prefetch_threads);
    printf("write_threads=%u\n", cfg->write_threads);
    printf("evict_threads=%u\n", cfg->evict_threads);
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
    printf("ioprio_decode_ok=%" PRIu64 "\n", snapshot.ioprio_decode_ok);
    printf("ioprio_decode_fail=%" PRIu64 "\n", snapshot.ioprio_decode_fail);
    printf("ioprio_prefetch_ok=%" PRIu64 "\n", snapshot.ioprio_prefetch_ok);
    printf("ioprio_prefetch_fail=%" PRIu64 "\n", snapshot.ioprio_prefetch_fail);
    printf("ioprio_write_ok=%" PRIu64 "\n", snapshot.ioprio_write_ok);
    printf("ioprio_write_fail=%" PRIu64 "\n", snapshot.ioprio_write_fail);
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
        {"random-read", no_argument, NULL, 1},
        {"sequential-read", no_argument, NULL, 2},
        {"buffered", no_argument, NULL, 3},
        {0, 0, 0, 0},
    };

    set_defaults(&cfg);

    while ((opt = getopt_long(argc, argv, "f:m:s:b:d:p:w:e:t:q:S:M:P:D:", long_options, &option_index)) != -1) {
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
        case 1:
            cfg.random_read = true;
            break;
        case 2:
            cfg.random_read = false;
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
            .session_id = i % cfg.sessions,
            .model_id = i % cfg.models,
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
            .session_id = (i + cfg.decode_threads) % cfg.sessions,
            .model_id = (i + cfg.decode_threads) % cfg.models,
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
            .session_id = (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.sessions,
            .model_id = (i + cfg.decode_threads + cfg.prefetch_threads) % cfg.models,
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
            .session_id = (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.sessions,
            .model_id = (i + cfg.decode_threads + cfg.prefetch_threads + cfg.write_threads) % cfg.models,
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
