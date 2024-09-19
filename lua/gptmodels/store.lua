-- I want to use private/protected for _right, _input etc, but am not finding a way to make that play nice with this file.
-- I really just want those _ prefixed fields to not be typewise accessible outside of this module.
---@diagnostic disable: invisible

---@param chat LlmMessage[]
---@param message LlmMessage
local concat_chat = function(chat, message)
  -- If this is the first message of the session
  if #chat == 0 then
    table.insert(chat, message)
    return
  end

  local last_message = chat[#chat]

  -- If the most recent message is not from the user, then it's assumed the llm is  giving a response.
  -- User messages never come in piecemeal.
  if last_message.role == "assistant" and message.role == "assistant" then
    last_message.content = last_message.content .. message.content
  else
    table.insert(chat, message)
  end
end

-- Finds the index of the model/provider pair where model == model and provider == provider
---@param model_options { model: string, provider: string }[]
---@param provider string
---@param model string
---@return integer | nil
local function find_model_index(model_options, provider, model)
  for index, option in ipairs(model_options) do
    if option.provider == provider and option.model == model then
      return index
    end
  end
  return nil -- No match found
end

---@param self Store
local function build_model_options(self)
  ---@type { model: string, provider: string }[]
  local model_options = {}
  for provider, models in pairs(self._llm_models) do
    for _, model in ipairs(models) do
      table.insert(model_options, { provider = provider, model = model })
    end
  end
  return model_options
end

---@class Pane
---@field clear fun(self: StrPane | LinesPane | MessagePane)
---@field popup NuiPopup

---@class StrPane : Pane
---@field append fun(self: StrPane, text: string)
---@field read fun(self: StrPane): string | nil
---@field clear fun(self: StrPane)
---@field private _text string

---@class LinesPane : Pane
---@field append fun(self: LinesPane, lines: string[])
---@field read fun(self: LinesPane): string[] | nil
---@field clear fun(self: LinesPane)
---@field private _lines string[]

---@class MessagePane : Pane
---@field append fun(self: MessagePane, message: LlmMessage)
---@field read fun(self: MessagePane): LlmMessage[]
---@field clear fun(self: MessagePane)
---@field private _messages LlmMessage[]

---@class Window
---@field clear fun(self: ChatWindow | CodeWindow | ProjectWindow)
---@field input StrPane
---@field append_file fun(self: Window, filename: string)
---@field get_files fun(self: Window): string[]
---@field clear_files fun(self: Window)
---@field private _files string[]

---@class CodeWindow : Window
---@field right StrPane
---@field left StrPane

---@class ChatWindow : Window
---@field chat MessagePane

---@class ProjectWindow : Window
---@field response_popups NuiPopup[]

---@alias Provider "openai" | "ollama"

---@class Store
---@field private _llm_models { openai: string[], ollama: string[] }
---@field private _llm_provider string
---@field private _llm_model string
---@field private _job Job | nil
---@field code CodeWindow
---@field chat ChatWindow
---@field project ProjectWindow
---@field clear fun(self: Store)
---@field register_job fun(self: Store, job: Job)
---@field get_job fun(self: Store): Job | nil
---@field clear_job fun(self: Store)
---@field get_models fun(self: Store, provider: Provider): string[]
---@field set_models fun(self: Store, provider: Provider, models: string[])
---@field get_model fun(self: Store): { provider: string, model: string }
---@field set_model fun(self: Store, provider: Provider, model: string)
---@field cycle_model_forward fun(self: Store)
---@field cycle_model_backward fun(self: Store)
---@field llm_model_strings fun(self: Store): string[]
---@field correct_potentially_missing_current_model fun(self: Store)

---@return StrPane
local function build_strpane()
  ---@type StrPane
  return {
    _text = "",
    append = function(self, text) self._text = self._text .. text end,
    read = function(self) return self._text end,
    clear = function(self) self._text = "" end
  }
end

---@type Store
local Store = {
  _llm_models = {
    openai = {},
    ollama = {},
  },

  _llm_provider = "",
  _llm_model = "",

  -- model accessor
  get_model = function(self)
    return { provider = self._llm_provider, model = self._llm_model }
  end,

  -- set the active model
  set_model = function(self, provider, model)
    self._llm_provider = provider
    self._llm_model = model
  end,

  -- get all models for a provider
  get_models = function(self, provider)
    return self._llm_models[provider]
  end,

  -- set all models for a provider, overwriting previous values
  set_models = function(self, provider, models)
    self._llm_models[provider] = models
  end,

  cycle_model_forward = function(self)
    local model_options = build_model_options(self)
    local current_index = find_model_index(model_options, self._llm_provider, self._llm_model)
    if not current_index then current_index = #model_options end
    local selected_option = model_options[(current_index % #model_options) + 1]
    self:set_model(selected_option.provider, selected_option.model)
  end,

  cycle_model_backward = function(self)
    local model_options = build_model_options(self)
    local current_index = find_model_index(model_options, self._llm_provider, self._llm_model)
    if not current_index then current_index = 1 end
    local selected_option = model_options[(current_index - 2) % #model_options + 1]
    self:set_model(selected_option.provider, selected_option.model)
  end,

  -- TODO Get rid of this, only used once in common. Just inline it.
  llm_model_strings = function(self)
    local model_strings = {}
    for provider, models in pairs(self._llm_models) do
      for _, model in ipairs(models) do
        table.insert(model_strings, provider .. "." .. model)
      end
    end
    return model_strings
  end,

  -- Introspects on the current model and the available models.
  -- Mutates own current model with set_model() to best option from a hardcoded
  -- list of defaults. Used on startup and after model etls.
  correct_potentially_missing_current_model = function(self)
    local current_model_info = self:get_model()
    local current_model = current_model_info.model

    -- Define available models as a table with providers and their corresponding models
    local available_models = {
      ollama = self:get_models("ollama"),
      openai = self:get_models("openai")
    }

    -- TODO Handle the case where available_models might be empty
    if not available_models.ollama and not available_models.openai then return end

    -- Check if the current model is still present in the available models list
    for _, provider in ipairs { "ollama", "openai" } do
      for _, available_model in ipairs(available_models[provider]) do
        if available_model == current_model then
          -- The currently selected model is present in our lists, no work need be done.
          return
        end
      end
    end

    -- Current model is not available; select a default model
    local preferred_defaults = { "mistral-nemo:latest", "llama3.1:latest", "deepseek-v2:latest", "gpt-4o-mini", "gpt-4o" }
    for _, preferred_default in ipairs(preferred_defaults) do
      for _, provider in ipairs { "ollama", "openai" } do
        for _, available_model in ipairs(available_models[provider]) do
          if available_model == preferred_default then
            self:set_model(provider, preferred_default)
            return
          end
        end
      end
    end

    -- If no preferred defaults are available, user gets the first available one
    for _, provider in ipairs { "ollama", "openai" } do
      if #available_models[provider] > 0 then
        -- Set the model to the first available option from the corresponding provider
        self:set_model(provider, available_models[provider][1])
        return
      end
    end

    -- If we reach this point, it means there are no available models. Plugin is useless.
    -- TODO Need to handle this though with some user feedback
  end,

  clear = function(self)
    self.code:clear()
    self.chat:clear()
    self.project:clear()
    self:set_models("ollama", {})
    self:set_models("openai", {})
    -- TODO Need to clear default model as well?
  end,

  code = {
    right = build_strpane(),
    left = build_strpane(),
    input = build_strpane(),

    _files = {},
    append_file = function(self, filename) table.insert(self._files, filename) end,
    get_files = function(self) return self._files end,
    clear_files = function(self) self._files = {} end,

    clear = function(self)
      self.right:clear()
      self.left:clear()
      self.input:clear()
      self:clear_files()
    end
  },

  chat = {
    input = build_strpane(),

    chat = {
      _messages = {},
      read = function(self) return self._messages end,
      append = function(self, message) concat_chat(self._messages, message) end,
      clear = function(self) self._messages = {} end
    },

    _files = {},
    append_file = function(self, filename) table.insert(self._files, filename) end,
    get_files = function(self) return self._files end,
    clear_files = function(self) self._files = {} end,

    clear = function(self)
      self.input:clear()
      self.chat:clear()
      self:clear_files()
    end
  },

  project = {
    input = build_strpane(),
    response_popups = {},
    changes = {
      _changes = {},
      clear = function (self)
        self._changes = {}
      end
    },

    _files = {},
    append_file = function(self, filename) table.insert(self._files, filename) end,
    get_files = function(self) return self._files end,
    clear_files = function(self) self._files = {} end,

    clear = function(self)
      self.input:clear()
      self:clear_files()
    end
  },

  register_job = function(self, job) self._job = job end,
  get_job = function(self) return self._job end,
  clear_job = function(self) self._job = nil end

}

return Store
