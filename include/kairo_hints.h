#ifndef KAIRO_HINTS_H
#define KAIRO_HINTS_H

/*
 * Experimental Kairo user-space hint definitions.
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

#endif
