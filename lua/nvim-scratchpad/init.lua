local M = {}

local defaults = {
  autosave_delay = 500,
  split_height = 12,
}

local config = vim.deepcopy(defaults)
local state = {
  bufnr = nil,
  winid = nil,
  repo_root = nil,
  branch = nil,
  timer = nil,
  setup_done = false,
}

local branch_group = vim.api.nvim_create_augroup("NvimScratchpadBranch", { clear = true })
local buffer_group = vim.api.nvim_create_augroup("NvimScratchpadBuffer", { clear = true })

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "nvim-scratchpad" })
end

local function system(args, opts)
  opts = opts or {}
  local result = vim.system(args, { cwd = opts.cwd, text = true }):wait()
  local output = vim.trim(result.stdout or "")

  if result.code ~= 0 then
    return nil, vim.trim(result.stderr or result.stdout or "")
  end

  return output, nil
end

local function current_context()
  local repo_root, repo_err = system({ "git", "rev-parse", "--show-toplevel" })
  if not repo_root then
    return nil, "not inside a Git repository"
  end

  local branch = system({ "git", "branch", "--show-current" }, { cwd = repo_root })
  if branch == nil or branch == "" then
    local commit, commit_err = system({ "git", "rev-parse", "--short", "HEAD" }, { cwd = repo_root })
    if not commit then
      return nil, commit_err ~= "" and commit_err or "unable to determine Git branch"
    end
    branch = "detached-" .. commit
  end

  return {
    repo_root = repo_root,
    branch = branch,
  }, nil
end

local function hash(value)
  return vim.fn.sha256(value)
end

local function scratchpad_path(repo_root, branch)
  local dir = table.concat({
    vim.fn.stdpath("data"),
    "nvim-scratchpad",
    hash(repo_root),
  }, "/")

  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. hash(branch) .. ".md"
end

local function is_scratchpad_buffer(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].scratchpad_branch ~= nil
end

local function cancel_timer()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

local function save_buffer(bufnr)
  bufnr = bufnr or state.bufnr
  if not is_scratchpad_buffer(bufnr) then
    return false
  end

  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end

  local ok, err = pcall(vim.api.nvim_buf_call, bufnr, function()
    vim.cmd("silent noautocmd write")
  end)

  if not ok then
    notify("Unable to save scratchpad: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

local function schedule_save(bufnr)
  if not is_scratchpad_buffer(bufnr) then
    return
  end

  cancel_timer()
  state.timer = vim.uv.new_timer()
  state.timer:start(config.autosave_delay, 0, vim.schedule_wrap(function()
    save_buffer(bufnr)
    cancel_timer()
  end))
end

local function configure_buffer(bufnr, context)
  vim.bo[bufnr].filetype = "markdown"
  vim.b[bufnr].scratchpad_repo_root = context.repo_root
  vim.b[bufnr].scratchpad_branch = context.branch
  vim.b[bufnr].scratchpad = true

  vim.api.nvim_clear_autocmds({ group = buffer_group, buffer = bufnr })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = buffer_group,
    buffer = bufnr,
    callback = function(args)
      schedule_save(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave", "VimLeavePre" }, {
    group = buffer_group,
    buffer = bufnr,
    callback = function(args)
      save_buffer(args.buf)
    end,
  })
end

local function open_window(path)
  vim.cmd("botright " .. tostring(config.split_height) .. "split")
  state.winid = vim.api.nvim_get_current_win()
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function focus_window()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_set_current_win(state.winid)
    return true
  end

  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(winid) == state.bufnr then
        state.winid = winid
        vim.api.nvim_set_current_win(winid)
        return true
      end
    end
  end

  return false
end

local function load_context(context)
  local path = scratchpad_path(context.repo_root, context.branch)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end

  local bufnr
  if focus_window() then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    bufnr = vim.api.nvim_get_current_buf()
  else
    bufnr = open_window(path)
  end

  state.bufnr = bufnr
  state.repo_root = context.repo_root
  state.branch = context.branch
  configure_buffer(bufnr, context)
end

local function check_branch()
  if not is_scratchpad_buffer(state.bufnr) then
    return
  end

  local context = current_context()
  if not context then
    return
  end

  if context.repo_root == state.repo_root and context.branch == state.branch then
    return
  end

  save_buffer(state.bufnr)
  load_context(context)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  if state.setup_done then
    return
  end
  state.setup_done = true

  vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "VimResume" }, {
    group = branch_group,
    callback = check_branch,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = branch_group,
    callback = function(args)
      if tonumber(args.match) == state.winid then
        save_buffer(state.bufnr)
        state.winid = nil
      end
    end,
  })
end

function M.open()
  local context, err = current_context()
  if not context then
    error("nvim-scratchpad: " .. err, 0)
  end

  if is_scratchpad_buffer(state.bufnr) and state.repo_root == context.repo_root and state.branch == context.branch then
    if focus_window() then
      return
    end
  end

  if is_scratchpad_buffer(state.bufnr) then
    save_buffer(state.bufnr)
  end

  load_context(context)
end

function M.close()
  if is_scratchpad_buffer(state.bufnr) then
    save_buffer(state.bufnr)
  end

  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    vim.api.nvim_win_close(state.winid, true)
  end
  state.winid = nil
end

function M.write()
  if not is_scratchpad_buffer(state.bufnr) then
    error("nvim-scratchpad: no scratchpad buffer is open", 0)
  end

  save_buffer(state.bufnr)
end

function M._path_for_current_context()
  local context, err = current_context()
  if not context then
    return nil, err
  end
  return scratchpad_path(context.repo_root, context.branch)
end

return M
