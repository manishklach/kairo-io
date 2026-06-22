#ifndef KAIRO_HINTS_H
#define KAIRO_HINTS_H

/*
 * Experimental Kairo user-space hint definitions.
 *
 * This is a local RFC/POC metadata path. It is not a proposed stable UAPI.
 *
 * Current local ioprio mapping:
 *   KAIRO_CLASS_DECODE_READ   -> IOPRIO_CLASS_RT, prio 0
 *   KAIRO_CLASS_PREFETCH_READ -> IOPRIO_CLASS_RT, prio 1
 *   KAIRO_CLASS_PREFILL_WRITE -> IOPRIO_CLASS_BE, prio 7
 *   KAIRO_CLASS_EVICT         -> discard / punch-hole path or BE prio 6 fallback
 */

#define KAIRO_CLASS_DECODE_READ   0
#define KAIRO_CLASS_PREFETCH_READ 1
#define KAIRO_CLASS_PREFILL_WRITE 2
#define KAIRO_CLASS_EVICT         3

#define KAIRO_RWF_DECODE      (1ULL << 28)
#define KAIRO_RWF_PREFETCH    (1ULL << 29)
#define KAIRO_RWF_PREFILL     (1ULL << 30)
#define KAIRO_RWF_RECOMPUTE   (1ULL << 31)

/*
 * Local RFC/POC only. These flags are used for benchmark intent modeling and
 * patched-kernel experiments, not stable Linux UAPI.
 */
#define KAIRO_RWF_EPHEMERAL        (1ULL << 32)
#define KAIRO_RWF_AVOID_PAGECACHE  (1ULL << 33)
#define KAIRO_RWF_NO_DURABILITY    (1ULL << 34)
#define KAIRO_RWF_EVICT_CLEANUP    (1ULL << 35)

enum kairo_hint_mode {
    KAIRO_HINT_MODE_IOPRIO = 0,
    KAIRO_HINT_MODE_RWF = 1,
    KAIRO_HINT_MODE_BOTH = 2,
};

enum kairo_semantic_mode {
    KAIRO_SEMANTIC_NORMAL = 0,
    KAIRO_SEMANTIC_EPHEMERAL = 1,
    KAIRO_SEMANTIC_RECOMPUTABLE = 2,
    KAIRO_SEMANTIC_EPHEMERAL_RECOMPUTABLE = 3,
};

enum kairo_lifetime_class_user {
    KAIRO_USER_LIFE_NONE = 0,
    KAIRO_USER_LIFE_SHORT,
    KAIRO_USER_LIFE_SESSION,
    KAIRO_USER_LIFE_MODEL,
    KAIRO_USER_LIFE_PERSISTENT,
};

struct kairo_user_placement_hint {
    uint32_t model_id;
    uint32_t session_id;
    uint32_t cache_pool_id;
    uint32_t placement_group;
    uint32_t lifetime_class;
    uint32_t flags;
};

/* Placement hint flags */
#define KAIRO_USER_HINT_HAS_MODEL_ID       (1U << 0)
#define KAIRO_USER_HINT_HAS_SESSION_ID     (1U << 1)
#define KAIRO_USER_HINT_HAS_CACHE_POOL     (1U << 2)
#define KAIRO_USER_HINT_RECOMPUTE_OK       (1U << 3)
#define KAIRO_USER_HINT_PLACEMENT_GROUP    (1U << 4)

static inline const char *kairo_user_lifetime_name(uint32_t lifetime_class)
{
    switch (lifetime_class) {
    case KAIRO_USER_LIFE_SHORT:
        return "short";
    case KAIRO_USER_LIFE_SESSION:
        return "session";
    case KAIRO_USER_LIFE_MODEL:
        return "model";
    case KAIRO_USER_LIFE_PERSISTENT:
        return "persistent";
    case KAIRO_USER_LIFE_NONE:
    default:
        return "none";
    }
}

static inline const char *kairo_hint_mode_name(enum kairo_hint_mode mode)
{
    switch (mode) {
    case KAIRO_HINT_MODE_IOPRIO:
        return "ioprio";
    case KAIRO_HINT_MODE_RWF:
        return "rwf";
    case KAIRO_HINT_MODE_BOTH:
        return "both";
    default:
        return "ioprio";
    }
}

static inline const char *kairo_semantic_mode_name(enum kairo_semantic_mode mode)
{
    switch (mode) {
    case KAIRO_SEMANTIC_NORMAL:
        return "normal";
    case KAIRO_SEMANTIC_EPHEMERAL:
        return "ephemeral";
    case KAIRO_SEMANTIC_RECOMPUTABLE:
        return "recomputable";
    case KAIRO_SEMANTIC_EPHEMERAL_RECOMPUTABLE:
        return "ephemeral-recomputable";
    default:
        return "normal";
    }
}

#endif
