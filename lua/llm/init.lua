local segment = require("llm.segment")
local util = require("llm.util")

local M = {}

local function get_prompt_and_segment(no_selection)
  if no_selection then
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local seg = segment.create_segment_at(#lines, 0, M.responding_hl_group)

    return {
      prompt = table.concat(lines, '\n'),
      segment = seg
    }
  else
    local selection = util.cursor.selection()
    local text = util.buf.text(selection)

    local seg = segment.create_segment_at(
      selection.stop.row,
      selection.stop.col,
      M.responding_hl_group
    )

    return {
      prompt = text,
      segment = seg
    }
  end
end

---@class StreamHandlers
---@field on_partial (fun(partial_text: string): nil)
---@field on_finish (fun(complete_text: string, finish_reason: string): nil)
---@field on_error (fun(data: any, label: string): nil) }

function M.request_completion_stream(args)
  local no_selection = args.range == 0

  local prompt_segment = get_prompt_and_segment(no_selection)
  local seg = prompt_segment.segment

  local prompt = M.default_prompt -- TODO get passed in prompt name from args

  local success, result = pcall(prompt.provider.request_completion_stream, prompt_segment.prompt, {
    on_partial = vim.schedule_wrap(function(partial)
      seg.add(partial)
    end),

    on_finish = vim.schedule_wrap(function(_, reason)
      if reason == 'stop' then
        seg.close()
      else
        seg.highlight("Error")
      end
    end),

    on_error = function(data, label)
      vim.notify(vim.inspect(data), vim.log.levels.ERROR, {title = 'stream error ' .. label})
    end
  }, nil, prompt.builder)

  if not success then
    util.eshow(result)
  end
end

function M.commands(opts)
  vim.api.nvim_create_user_command("Llm", M.request_completion_stream, {
    range = true,
    desc = "Request completion of selection",
    force = true
    -- TODO add custom Llm transform functions to complete :command-complete
    -- complete = function() end
  })
end

function M.setup(opts)
  -- TODO still figuring out this api
  local openai = require("llm.providers.openai")

  local _opts = vim.tbl_deep_extend("force", {
    responding_hl_group = "Comment",
    default_prompt = {
      provider = openai,
      builder = openai.default_builder
    },
  }, opts or {})

  M.default_prompt = _opts.default_prompt

  M.responding_hl_group = _opts.responding_hl_group

  M.commands(_opts)
end

return M

