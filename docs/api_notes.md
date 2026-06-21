# Kairo API Notes

These notes are experimental and RFC-stage only. They are not a proposed final UAPI.

## Guiding Approach

The project should begin with existing Linux interfaces and delay any new UAPI proposal until the workload model and scheduler behavior are backed by benchmark evidence.

## Existing Interfaces Worth Reusing

### `io_uring`

Potential use:

- low-overhead submission
- fixed files
- registered buffers
- batching for decode and prefetch traffic

Status:

- recommended for later benchmark evolution
- not required for the first pthreads baseline

### `ioprio`

Potential use:

- experimental request-class selection
- cheap user-space signal for decode versus prefill intent

Status:

- suitable for RFC-stage experiments
- should not be treated as a final semantic mapping

### `fcntl` Write-Life Hints

Potential use:

- expressing short-lived or recomputable cache data
- helping later placement experiments

Status:

- optional research input
- not sufficient by itself to express decode criticality

### `posix_fadvise()`

Potential use:

- reducing page-cache pollution
- expressing sequential or non-reuse expectations

Status:

- useful for baseline hygiene
- not a substitute for block-layer scheduling

### `O_DIRECT`

Potential use:

- reduce page-cache interference
- make storage behavior easier to observe

Status:

- primary baseline mode
- should fall back cleanly when a filesystem or environment resists direct I/O

### Registered Buffers

Potential use:

- lower submission overhead
- more stable `io_uring` benchmarking

Status:

- later benchmark optimization
- not a prerequisite for first-phase results

## Experimental Metadata Worth Preserving

The benchmark and eventual kernel path may want to preserve:

- `placement_id`
- `session_id`
- `model_id`
- lifetime class
- recomputable flag

Possible interpretations:

- `placement_id`: affinity grouping for future backend placement
- `session_id`: isolate per-conversation or per-request cache activity
- `model_id`: distinguish different model working sets
- lifetime class: short, medium, or long-lived cache data
- recomputable flag: marks data that can trade durability for scheduling flexibility

## Experimental Flag Ideas

Any future flags should remain conceptual until the project has stronger evidence. Example placeholders:

```c
#define RWF_KV_CACHE        0x00010000
#define RWF_KV_DECODE       0x00020000
#define RWF_KV_PREFETCH     0x00040000
#define RWF_KV_RECOMPUTABLE 0x00080000
#define RWF_KV_LARGE_BLOCK  0x00100000
```

These names are documentation aids, not implemented API commitments.

## Working Recommendation

The first practical path is:

1. benchmark with `O_DIRECT`, aligned buffers, and repeatable workload roles
2. experiment with `ioprio` as a classification signal
3. prototype internal kernel mappings
4. revisit public interface design only after scheduler behavior is validated
