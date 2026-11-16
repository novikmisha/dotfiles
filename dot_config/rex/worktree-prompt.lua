-- Run outside an action so the dialog can wait beyond Rex's 30-second action limit.
local prompt = assert(rex.exec({ "/usr/bin/osascript", "-e", [[
tell application "Rex Beta"
  activate
  try
    return text returned of (display dialog "New branch name:" with title "New Worktree Session" default answer "" buttons {"Cancel", "Create"} default button "Create" cancel button "Cancel")
  on error number -128
    return ""
  end try
end tell
]] }))
assert(prompt.ok, prompt.stderr)
local branch = prompt.stdout:gsub("\n$", "")
if branch == "" then
  return
end

local created, err = rex.invoke("new_worktree_session", {
  branch = branch,
  directory = rex.args.directory,
})
if err ~= nil then
  rex.exec({ "/usr/bin/osascript", "-e", [[
on run argv
  tell application "Rex Beta" to display alert "Worktree session failed" message (item 1 of argv)
end run
]], err })
  error(err, 0)
end
return created
