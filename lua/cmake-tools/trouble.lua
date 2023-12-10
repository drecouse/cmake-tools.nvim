local log = require("cmake-tools.log")
local Job = require("plenary.job")
local troub = require("trouble")

---@alias trouble_show '"always"'|'"only_on_error"'
---@alias trouble_position '"belowright"'|'"bottom"'|'"top"'
---@alias trouble_opts_type {show:trouble_show, position:trouble_position, size:number}
--
---@class trouble : executor
local trouble = {
  job = nil,
}

function trouble.scroll_to_bottom()
      troub.last({skip_groups = true, jump = false})
end

local function append_to_trouble(encoding, error, data)
  local line = error and error or data
  if encoding ~= "utf-8" then
    line = vim.fn.iconv(line, encoding, "utf-8")
  end

  vim.fn.setqflist({}, "a", { lines = { line } })
  -- scroll the trouble buffer to bottom
  if trouble.check_scroll() then
    trouble.scroll_to_bottom()
  end
end

function trouble.show(opts)
  troub.open("quickfix")
  vim.api.nvim_command("wincmd p")
end

function trouble.close(opts)
  troub.close("quickfix")
end

function trouble.run(cmd, env_script, env, args, cwd, opts, on_exit, on_output)
  vim.fn.setqflist({}, " ", { title = cmd .. " " .. table.concat(args, " ") })
  if opts.show == "always" then
    trouble.show(opts)
  end

  -- NOTE: Unused env_script for trouble.run() as plenary does not yet support running scripts

  local job_args = {}

  if next(env) then
    table.insert(job_args, "-E")
    table.insert(job_args, "env")
    for _, v in ipairs(env) do
      table.insert(job_args, v)
    end
    table.insert(job_args, "cmake")
    for _, v in ipairs(args) do
      table.insert(job_args, v)
    end
  else
    job_args = args
  end

  trouble.job = Job:new({
    command = cmd,
    args = job_args,
    cwd = cwd,
    on_stdout = vim.schedule_wrap(function(err, data)
      append_to_trouble(opts.encoding, err, data)
      on_output(data, err)
    end),
    on_stderr = vim.schedule_wrap(function(err, data)
      append_to_trouble(opts.encoding, err, data)
      on_output(data, err)
    end),
    on_exit = vim.schedule_wrap(function(_, code, signal)
      code = signal == 0 and code or 128 + signal
      local msg = "Exited with code " .. code

      append_to_trouble(opts.encoding, msg)
      if code ~= 0 and opts.show == "only_on_error" then
        trouble.show(opts)
        trouble.scroll_to_bottom()
      end
      if on_exit ~= nil then
        on_exit(code)
      end
    end),
  })

  trouble.job:start()
end

---Checks if there is an active job
---@param opts trouble_opts_type options for this adapter
---@return boolean
function trouble.has_active_job(opts)
  if not trouble.job or trouble.job.is_shutdown then
    return false
  end
  log.error(
    "A CMake task is already running: "
      .. trouble.job.command
      .. " Stop it before trying to run a new CMake task."
  )
  return true
end

---Stop the active job
---@param opts trouble_opts_type options for this adapter
---@return nil
function trouble.stop(opts)
  trouble.job:shutdown(1, 9)

  for _, pid in ipairs(vim.api.nvim_get_proc_children(trouble.job.pid)) do
    vim.loop.kill(pid, 9)
  end
end

function trouble.check_scroll()
  local function is_cursor_at_last_line()
    local current_buf = vim.api.nvim_win_get_buf(0)
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line_count = vim.api.nvim_buf_line_count(current_buf)

    return cursor_pos[1] == line_count - 1
  end

  local buffer_type = vim.api.nvim_buf_get_option(0, "buftype")

  if buffer_type == "trouble" then
    return is_cursor_at_last_line()
  end

  return true
end

function trouble.is_installed()
  return troub ~= nil
end

return trouble
