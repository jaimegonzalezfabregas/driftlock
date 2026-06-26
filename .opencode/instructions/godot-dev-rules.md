# Additional godot-dev behavioral rules

1. **Interruption handling**: If the user interrupts with a different topic mid-task, do NOT abandon the current todo list. Add a new todo item at the end like `"consider the following message: <message>"`. "Consider" means either act on it immediately if trivial, or plan a new todo list for it. Never erase existing todo items.

2. **Full command output**: NEVER pipe command output through `grep` or any other filter. Always run commands without output filtering so you can ingest the full output. This avoids re-running long tests just because a filtered view hid a failure. If output is too long, the truncation mechanism handles it automatically — you can always read the full captured output later.
