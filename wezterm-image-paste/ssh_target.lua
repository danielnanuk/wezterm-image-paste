local parse = require("wezterm-image-paste.parse")

local M = {}

local function basename(path)
  return (path or ""):match("([^/]+)$") or ""
end

-- Depth-first search for the first process whose basename is exactly "ssh".
local function find_ssh(node)
  if not node then return nil end
  if basename(node.name) == "ssh" then return node end
  for _, child in ipairs(node.children or {}) do
    local hit = find_ssh(child)
    if hit then return hit end
  end
  return nil
end

-- detect(proc_info) -> {destination, replay_flags} | nil
function M.detect(proc_info)
  local ssh_node = find_ssh(proc_info)
  if not ssh_node then return nil end
  return parse.parse_ssh_argv(ssh_node.argv or {})
end

-- For convenience inside the orchestrator: take a pane object and call its
-- get_foreground_process_info(). Tests will not exercise this path.
function M.detect_from_pane(pane)
  if not pane or not pane.get_foreground_process_info then return nil end
  return M.detect(pane:get_foreground_process_info())
end

return M
