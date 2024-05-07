local cmd = require('gpt.cmd')
local util = require('gpt.util')

local path = vim.fn.stdpath('cache')
local data_dir = path .. "/GPT.nvim"

-- Mutates chat
---@param chat LlmMessage[]
---@param message LlmMessage
---@return LlmMessage[]
local concat_chat = function(chat, message)
  -- If this is the first message of the session
  if #chat == 0 then
    table.insert(chat, message)
    return chat
  end

  local last_message = chat[#chat]

  -- If the most recent message is not from the user, then it's assumed the llm is  giving a response.
  -- User messages never come in piecemeal.
  if last_message.role == "assistant" and message.role == "assistant" then
    last_message.content = last_message.content .. message.content
  else
    table.insert(chat, message)
  end

  return chat
end

---@param file_path string
local function ensure_file(file_path)
  if not vim.fn.filereadable(file_path) then
    local f, _ = io.open(file_path, "w+")
    if f then return f:close() end

    local job = cmd.exec({
      cmd = "touch",
      args = { file_path }
    })

    vim.wait(500, function () return job.done() end)
  end
end

---@param dir_path string
local function ensure_dir(dir_path)
  local job = cmd.exec({
    cmd = "mkdir",
    args = {
      "-p",
      dir_path
    }
  })

  vim.wait(100, function() return job.done() end)
end

-- maps a custom window identifier with a file name
local file_mapping = {
  edit_right = "/edit_right",
  edit_left = "/edit_left",
  edit_input = "/edit_input",
  chat_input = "/chat_input",
  chat_chat = "/chat_chat",
}

-- Appends given chat messages to the file on disk.
-- This is the only one that's not just writing text, so it lives on its own.
---@param messages LlmMessage[]
local function write_chat(messages)
  local file_path = data_dir .. file_mapping["chat_chat"]

  local json = vim.fn.json_encode(messages)

  -- S means no file writes with "fsync", which means writes are faster, but wait in OS buffers to write
  vim.fn.writefile({ json }, file_path, "S")
end

---@return LlmMessage[]
local function read_chat()
  local file_path = data_dir .. file_mapping["chat_chat"]
  local existing_contents = vim.fn.readfile(file_path)

  ---@type boolean, any
  local status_ok, content = pcall(vim.fn.json_decode, existing_contents)

  if not status_ok or not content then
    content = {}
  end

  return content
end

---@param message LlmMessage
local function append_chat(message)
  local concatenated = concat_chat(read_chat(), message)
  write_chat(concatenated)
end

---@param id "edit_right" | "edit_left" | "edit_input" | "chat_input"
---@param data string
local function append_to(id, data)
  local file_path = data_dir .. file_mapping[id]

  local existing_contents = vim.fn.readfile(file_path)
  local new_contents = { existing_contents[1] .. data }

  -- S means no file writes with "fsync", which means writes are faster, but wait in OS buffers to write
  vim.fn.writefile(new_contents, file_path, "S")
end

---@param id "edit_right" | "edit_left" | "edit_input" | "chat_input" | "chat_chat"
---@return string
local function read_from(id)
  local file_path = data_dir .. file_mapping[id]
  local existing_contents = vim.fn.readfile(file_path)
  return existing_contents[1]
end

---@param id "edit_right" | "edit_left" | "edit_input" | "chat_input"
local function clear(id)
  local file_path = data_dir .. file_mapping[id]
  vim.fn.writefile({ "" }, file_path, "S")
end

local Store = {}
Store = {
  -- initialize the save files if they don't exist
  init = function()
    ensure_dir(data_dir)
    for _, file_path in pairs(file_mapping) do
      ensure_file(data_dir .. file_path)
    end
  end,

  -- synchronously clears all store values. Useful mostly for testing
  clean = function()
    Store.chat.clear()
    Store.edit.clear()
    Store.clear_job()

    local job = cmd.exec({
      cmd = "rm",
      args = { "-rf", data_dir },
    })

    vim.wait(500, function() return job.done() end)

    Store.init()

    vim.wait(500, function()
      return Store.chat.chat.read() == {}
          and Store.chat.input.read() == ""
          and Store.edit.right.read() == ""
          and Store.edit.left.read() == ""
          and Store.edit.input.read() == ""
    end)
  end,

  edit = {
    _right = "",
    right = {
      ---@param text string
      append = function(text) append_to("edit_right", text) end,
      read = function() return read_from("edit_right") end,
    },

    _left = "",
    left = {
      ---@param text string
      append = function(text) append_to("edit_left", text) end,
      read = function() return read_from("edit_left") end,
    },

    _input = "",
    input = {
      ---@param text string
      append = function(text) append_to("edit_input", text) end,
      read = function() return read_from("edit_input") end,
    },

    clear = function()
      clear("edit_right")
      clear("edit_left")
      clear("edit_input")
    end
  },
  chat = {
    _input = "",
    input = {
      ---@param text string
      append = function(text) append_to("chat_input", text) end,
      read = function() return read_from("chat_input") end,
    },

    ---@type LlmMessage[]
    _chat = {},
    chat = {
      ---@param message LlmMessage
      append = function(message) append_chat(message) end,
      read = function() return read_chat() end,
    },

    clear = function()
      clear("chat_input")
      write_chat({})
    end
  },
}


-- Jobs --

---@param job Job
---@return nil
Store.register_job = function(job)
  Store._job = job
end

---@return Job | nil
Store.get_job = function()
  return Store._job
end

Store.clear_job = function()
  Store._job = nil
end

-- Sessions --

return Store
