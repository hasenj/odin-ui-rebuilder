# Worker file service

Shared implementation for asynchronous directory snapshots and images. This
package has no dependency on UI state, native windows or GPU APIs.

```odin
service := files.create()
defer files.destroy(service)
task := files.request(service, path, .Directory) // Also .Image.
// During updates, without waiting:
state := files.status(service, task)
if result, ready := files.take(service, task); ready {
    // Move/retain the snapshot or upload its pixels on the renderer's thread.
    // Result.error distinguishes a failed read from a successful empty result.
    files.retire(service, result) // Stop using it; disposal runs on the worker.
}
// When the resource is no longer needed:
files.release(service, task)
```

The state starts at None for a nil task, becomes Reading on request/reload, and
Done after success or failure. Each completion increments a revision. `take`
transfers ownership of the newest result; unconsumed older results are freed.
Result data never borrows a worker's temporary arena. Either retire a result
or call `destroy_result` exactly once, including error results.

Use the accessors rather than touching service/task fields: these structures
are shared with the worker. Service addresses remain stable. Release cancels
queued work or discards an in-flight completion without waiting; do not use a
task pointer after release. Destroy joins the worker, then frees all remaining
requests/results. A blocking OS read can therefore delay shutdown.

Each service has one worker. All path normalization, reads, sorting, stat calls,
image decoding and thumbnail reduction run there. Directory results sort folders
first, then names case-insensitively, following symlinks to classify directories
but preserving lexical paths for navigation. Image results contain premultiplied
RGBA8 pixels and dimensions; `max_extent` optionally reduces their size.

Watching is portable metadata polling, enabled by default, with a nominal
250 ms interval. Slow I/O can delay checks. File stamps include existence,
modification time, size, inode, device and permissions. Directory changes cause
a fresh snapshot; this detects additions, removals and renames. Editing an
existing child's contents need not change the directory stamp, so its size
column may remain stale until the next directory refresh. Image subscriptions
watch their own file and reload independently. Rapid changes coalesce, and a
transient decode failure can recover on the next file change. Changes that
preserve all watched metadata cannot be detected by this implementation.

Native filesystem notifications and on-demand UI wakeups can replace polling
later without changing the data ownership model. The current application loop
already updates continuously and consumes completed snapshots on its next frame.
