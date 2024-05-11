local util = require('gpt.util')
local com = require('gpt.windows.common')
local Layout = require("nui.layout")
local Popup = require("nui.popup")
local llm = require("gpt.llm")
local Store = require("gpt.store")

local M = {}

---@param bufnr integer
---@param messages LlmMessage[]
local render_buffer_from_messages = function(bufnr, messages)
  local lines = {}
  for _, message in ipairs(messages) do
    local message_content = vim.split(message.content, "\n")
    lines = util.merge_tables(lines, message_content)
    table.insert(lines, "---")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
end

-- TODO when window is closed call job:shutdown()
-- TODO auto-scroll (lua fn for ctl-e?) when focus is not in chat window

---@param input_bufnr integer
---@param chat_bufnr integer
local on_CR = function(input_bufnr, chat_bufnr)
  local input_lines = vim.api.nvim_buf_get_lines(input_bufnr, 0, -1, false)
  local input_text = table.concat(input_lines, "\n")

  -- Clear input buf
  vim.api.nvim_buf_set_lines(input_bufnr, 0, -1, true, {})

  Store.chat.chat.append({ role = "user", content = input_text })
  render_buffer_from_messages(chat_bufnr, Store.chat.chat.read())

  local jorb = llm.chat({
    llm = {
      stream = true,
      messages = Store.chat.chat.read(),
    },
    on_read = function(_, message)
      Store.chat.chat.append(message)
      render_buffer_from_messages(chat_bufnr, Store.chat.chat.read())
    end,
    on_end = function()
      Store.clear_job()
    end
  })

  Store.register_job(jorb)
end

local function on_tab(i, bufs)
  local next_buf_index = (i % #bufs) + 1
  local next_win = vim.fn.bufwinid(bufs[next_buf_index])
  vim.api.nvim_set_current_win(next_win)
end

local function on_s_tab(i, bufs)
  local next_buf_index = (i % #bufs) + 1
  local next_win = vim.fn.bufwinid(bufs[next_buf_index])
  vim.api.nvim_set_current_win(next_win)
end

-- TODO TEST
local function on_q(layout)
  local job = Store.get_job()
  if job ~= nil then
    job.die()
    Store.clear_job()
  end
  layout:unmount()
end

---@param selected_text string[] | nil
---@return { input_bufnr: integer, chat_bufnr: integer }
function M.build_and_mount(selected_text)
  local chat = Popup(com.build_common_popup_opts("Chat"))
  local input = Popup(com.build_common_popup_opts("Prompt"))

  -- Input window is text with no syntax
  vim.api.nvim_buf_set_option(input.bufnr, 'filetype', 'txt')
  vim.api.nvim_buf_set_option(input.bufnr, 'syntax', '')

  -- Make input a 'scratch' buffer, effectively making it a temporary buffer
  vim.api.nvim_buf_set_option(input.bufnr, "buftype", "nofile")

  -- Chat in markdown
  vim.api.nvim_buf_set_option(chat.bufnr, 'filetype', 'markdown')

  -- If there's a chat history, open with that.
  render_buffer_from_messages(chat.bufnr, Store.chat.chat.read())

  vim.api.nvim_buf_set_keymap(
    input.bufnr,
    "n",
    "<CR>",
    "",
    { noremap = true, silent = true, callback = function() on_CR(input.bufnr, chat.bufnr) end }
  )

  local layout = Layout(
    {
      position = "50%",
      relative = "editor",
      size = {
        width = "90%",
        height = "90%",
      },
    },
    Layout.Box({
      Layout.Box(chat, { size = "80%" }),
      Layout.Box(input, { size = "22%" }),
    }, { dir = "col" })
  )

  layout:mount()

 -- Add text selection to input buf
  if selected_text then
    vim.api.nvim_buf_set_lines(input.bufnr, 0, -1, true, selected_text)
    local keys = vim.api.nvim_replace_termcodes('<Esc>Go', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)
  else
    -- start window in insert mode
    vim.api.nvim_command('startinsert')
  end

  -- keymaps
  local bufs = { chat.bufnr, input.bufnr }
  for i, buf in ipairs(bufs) do
    -- Tab cycles through windows
    vim.api.nvim_buf_set_keymap(buf, "n", "<Tab>", "", {
      noremap = true,
      silent = true,
      callback = function() on_tab(i, bufs) end,
    })

    -- Shift-Tab cycles through windows in reverse
    vim.api.nvim_buf_set_keymap(buf, "n", "<S-Tab>", "", {
      noremap = true,
      silent = true,
      callback = function() on_s_tab(i, bufs) end,
    })

    -- "q" exits from the thing
    -- TODO remove or test
    vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
      noremap = true,
      silent = true,
      callback = function() on_q(layout) end,
    })

    -- vim.api.nvim_create_autocmd("BufLeave", {
    --   buffer = buf,
    --   callback = function()
    --     on_q(layout)
    --   end,
    -- })
  end

  return {
    input_bufnr = input.bufnr,
    chat_bufnr = chat.bufnr
  }
end

return M
