local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
vim.opt.runtimepath:prepend(root)

local function system(cmd, cwd)
  local result = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(cmd, " ") .. "\n" .. (result.stderr or result.stdout or ""))
  end
  return result.stdout or ""
end

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error(string.format("%s\nexpected: %s\nactual: %s", message or "assert_eq failed", vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or "expected value to be truthy")
  end
end

local function make_repo()
  local base = vim.fn.tempname()
  vim.fn.mkdir(base, "p")
  system({ "git", "init", "-b", "main" }, base)
  vim.fn.writefile({ "initial" }, base .. "/README.md")
  system({ "git", "add", "README.md" }, base)
  system({ "git", "commit", "-m", "initial" }, base)
  system({ "git", "checkout", "-b", "feature" }, base)
  system({ "git", "checkout", "main" }, base)
  return base
end

local function scratchpad_buf()
  local current = vim.api.nvim_get_current_buf()
  if vim.b[current].scratchpad_branch ~= nil then
    return current
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[bufnr].scratchpad_branch ~= nil then
      return bufnr
    end
  end
  return nil
end

local function scratchpad_lines()
  local bufnr = scratchpad_buf()
  assert_truthy(bufnr, "scratchpad buffer was not found")
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local failures = {}

local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    print("ok - " .. name)
  else
    print("not ok - " .. name)
    print(err)
    table.insert(failures, name)
  end
end

local data_dir = vim.fn.tempname()
vim.env.XDG_DATA_HOME = data_dir
vim.env.XDG_STATE_HOME = vim.fn.tempname()
vim.env.XDG_CACHE_HOME = vim.fn.tempname()
vim.env.GIT_AUTHOR_NAME = "scratchpad test"
vim.env.GIT_AUTHOR_EMAIL = "scratchpad@example.test"
vim.env.GIT_COMMITTER_NAME = "scratchpad test"
vim.env.GIT_COMMITTER_EMAIL = "scratchpad@example.test"

vim.cmd("runtime plugin/nvim-scratchpad.lua")
require("nvim-scratchpad").setup({ autosave_delay = 20 })

test("opens a markdown scratchpad in a git repo and autosaves edits", function()
  local repo = make_repo()
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
  vim.cmd("ScratchpadOpen")

  local bufnr = scratchpad_buf()
  assert_truthy(bufnr, "scratchpad buffer was not created")
  assert_eq(vim.bo[bufnr].filetype, "markdown", "scratchpad should use markdown filetype")
  assert_truthy(vim.api.nvim_buf_get_name(bufnr):find(data_dir, 1, true), "scratchpad file should live under data dir")

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# Main", "", "main branch note" })
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
  vim.wait(250, function()
    return vim.bo[bufnr].modified == false
  end)

  vim.cmd("ScratchpadClose")
  vim.cmd("ScratchpadOpen")
  assert_eq(table.concat(scratchpad_lines(), "\n"), "# Main\n\nmain branch note", "autosaved content should reopen")
end)

test("saves and reloads content when the git branch changes", function()
  local repo = make_repo()
  vim.cmd("cd " .. vim.fn.fnameescape(repo))
  vim.cmd("ScratchpadOpen")

  local bufnr = scratchpad_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "main note" })
  vim.cmd("ScratchpadWrite")

  system({ "git", "checkout", "feature" }, repo)
  vim.api.nvim_exec_autocmds("FocusGained", {})
  assert_eq(table.concat(scratchpad_lines(), "\n"), "", "feature branch should start with an empty scratchpad")

  bufnr = scratchpad_buf()
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "feature note" })
  vim.cmd("ScratchpadWrite")

  system({ "git", "checkout", "main" }, repo)
  vim.api.nvim_exec_autocmds("FocusGained", {})
  assert_eq(table.concat(scratchpad_lines(), "\n"), "main note", "main branch content should be restored")

  system({ "git", "checkout", "feature" }, repo)
  vim.api.nvim_exec_autocmds("FocusGained", {})
  assert_eq(table.concat(scratchpad_lines(), "\n"), "feature note", "feature branch content should be restored")
end)

test("reports an error outside a git repo", function()
  local outside = vim.fn.tempname()
  vim.fn.mkdir(outside, "p")
  vim.cmd("cd " .. vim.fn.fnameescape(outside))

  local ok, err = pcall(vim.cmd, "ScratchpadOpen")
  assert_eq(ok, false, "ScratchpadOpen should fail outside a git repo")
  assert_truthy(tostring(err):find("not inside a Git repository", 1, true), "error should explain git repo requirement")
end)

if #failures > 0 then
  vim.cmd("cquit")
end

vim.cmd("qall!")
