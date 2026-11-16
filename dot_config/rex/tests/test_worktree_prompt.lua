local invoked, alerts
local response, failure, success = "feature/quoted'$(literal)\n", nil, true
rex = {
  args = { directory = "/repo with spaces" },
  exec = function(argv)
    assert(argv[1] == "/usr/bin/osascript")
    if argv[4] then
      alerts = alerts + 1
      assert(argv[4] == failure)
    end
    return { ok = success, stdout = response, stderr = "dialog failed" }
  end,
  invoke = function(name, args)
    invoked = invoked + 1
    assert(name == "new_worktree_session")
    assert(args.branch == response:gsub("\n$", ""))
    assert(args.directory == rex.args.directory)
    return failure == nil and { session_id = "new-session" } or nil, failure
  end,
}

invoked, alerts = 0, 0
assert(dofile("worktree-prompt.lua").session_id == "new-session")
assert(invoked == 1 and alerts == 0)
response = "\n"
assert(dofile("worktree-prompt.lua") == nil)
assert(invoked == 1)
response, failure = "existing-branch\n", "Branch already exists"
assert(not pcall(dofile, "worktree-prompt.lua"))
assert(invoked == 2 and alerts == 1)
success = false
assert(not pcall(dofile, "worktree-prompt.lua"))
assert(invoked == 2)
print("Passed: branch prompt, cancellation, literal input, and visible errors")
