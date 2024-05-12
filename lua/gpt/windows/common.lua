local Store = require('gpt.store')

local M = {}

function M.build_common_popup_opts(title)
  return {
    border = {
      style = "rounded",
      text = {
        top = title,
        top_align = "center",
        bottom = "",
        bottom_align = "center",
      },
    },
    focusable = true,
    enter = true,
    win_options = {
      -- winhighlight = "Normal:Normal",
      winhighlight = "Normal:Normal,FloatBorder:SpecialChar",
    },
  }
end

-- This works to close the popup. Probably good to delete the buffer too!
function M.close_popup(bufnr)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

-- Used for a very specific situation, when cycling models
---@param model_options { model: string, provider: string }[]
---@return integer | nil
function M.find_model_index(model_options)
  local provider = Store.llm_provider
  local model = Store.llm_model

  for index, option in ipairs(model_options) do
    if option.provider == provider and option.model == model then
      return index
    end
  end
  return nil     -- No match found
end

function M.model_display_name()
  return " " .. Store.llm_provider .. "." .. Store.llm_model .. " "
end

return M

-- Some memories, since I'm so new at this

-- -- Close the popup when leaving the buffer, just nice to have
-- input:on(event.BufLeave, function()
--   com.close_popup(input.bufnr)
-- end, { once = true })
