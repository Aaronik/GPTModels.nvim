---@diagnostic disable: undefined-global

local util = require("gpt.util")
local assert = require("luassert")
local code_window = require('gpt.windows.code')
local stub = require('luassert.stub')
local llm = require('gpt.llm')
local cmd = require('gpt.cmd')
local Store = require('gpt.store')

describe("The Code window", function()
  before_each(function()
    -- Set current window dims, otherwise it defaults to 0 and nui.layout complains about not having a pos integer height
    vim.api.nvim_win_set_height(0, 100)
    vim.api.nvim_win_set_width(0, 100)

    stub(cmd, "exec")

    Store.clear()
  end)

  it("returns buffer numbers", function()
    local bufs = code_window.build_and_mount()
    assert.is_not(bufs.input_bufnr, nil)
    assert.is_not(bufs.left_bufnr, nil)
    assert.is_not(bufs.right_bufnr, nil)
  end)

  it("opens in input mode", function()
    code_window.build_and_mount()
    vim.api.nvim_feedkeys('xhello', 'mtx', true)
    -- For some reason, the first letter is always trimmed off. But if it's not in insert mode, the line will be empty ""
    assert.same(vim.api.nvim_get_current_line(), 'hello')
  end)

  it("opens with recent usage with no text provided", function()
    Store.code.right.append("right content")
    Store.code.input.append("input content")
    Store.code.left.append("left content")

    local bufs = code_window.build_and_mount()

    local right_lines = vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true)
    local input_lines = vim.api.nvim_buf_get_lines(bufs.input_bufnr, 0, -1, true)
    local left_lines = vim.api.nvim_buf_get_lines(bufs.left_bufnr, 0, -1, true)

    assert.same({ "right content" }, right_lines)
    assert.same({ "input content" }, input_lines)
    assert.same({ "left content" }, left_lines)
  end)

  it("does not open with recent usage when text is provided", function()
    Store.code.right.append("right content")
    Store.code.input.append("input content")
    Store.code.left.append("left content")

    local bufs = code_window.build_and_mount({ "provided text" })

    local right_lines = vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true)
    local input_lines = vim.api.nvim_buf_get_lines(bufs.input_bufnr, 0, -1, true)
    local left_lines = vim.api.nvim_buf_get_lines(bufs.left_bufnr, 0, -1, true)

    assert.same({ "" }, right_lines)
    assert.same({ "" }, input_lines)
    assert.same({ "provided text" }, left_lines)
  end)

  it("places given selected text in left window", function()
    local given_lines = { "text line 1", "text line 2" }
    local bufs = code_window.build_and_mount(given_lines)
    local gotten_lines = vim.api.nvim_buf_get_lines(bufs.left_bufnr, 0, -1, true)
    assert.same(given_lines, gotten_lines)
  end)

  it("shifts through windows on <Tab>", function()
    local bufs = code_window.build_and_mount()
    local input_bufnr = bufs.input_bufnr
    local left_bufnr = bufs.left_bufnr
    local right_bufnr = bufs.right_bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local left_win = vim.fn.bufwinid(left_bufnr)
    local right_win = vim.fn.bufwinid(right_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), left_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), right_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("shifts through windows on <S-Tab>", function()
    local bufs = code_window.build_and_mount()
    local input_bufnr = bufs.input_bufnr
    local left_bufnr = bufs.left_bufnr
    local right_bufnr = bufs.right_bufnr

    local input_win = vim.fn.bufwinid(input_bufnr)
    local left_win = vim.fn.bufwinid(left_bufnr)
    local right_win = vim.fn.bufwinid(right_bufnr)

    local esc = vim.api.nvim_replace_termcodes('<Esc>', true, true, true)
    local tab = vim.api.nvim_replace_termcodes("<S-Tab>", true, true, true)

    vim.api.nvim_feedkeys(esc, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), right_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), left_win)
    vim.api.nvim_feedkeys(tab, 'mtx', true)
    assert.equal(vim.api.nvim_get_current_win(), input_win)
  end)

  it("Places llm responses into right window", function()
    local bufs = code_window.build_and_mount()

    local s = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    -- simulate a multiline resposne from the llm
    args.on_read(nil, "line 1\nline 2")

    -- Those lines should be separated on newlines and placed into the right buf
    assert.same(vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true), { "line 1", "line 2" })
  end)

  it("includes a system prompt", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xincluding system prompt?<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]
    assert.is_not.same(args.llm.system, nil)
  end)

  it("includes the file type", function()
    -- return "lua" for filetype request
    stub(vim.api, "nvim_buf_get_option").returns("lua")

    code_window.build_and_mount()
    local s = stub(llm, "generate")

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xincluding filetype?<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    assert.not_same(string.find(args.llm.prompt, "lua"), nil)
    assert.is_not.same(args.llm.prompt, nil)
  end)

  -- TODO Actually, maybe we don't want to kill the job? Maybe it should just continue to
  -- run and populate a store in the background?
  it("kills jobs and closes the window when q is pressed", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")
    local die_called = false

    s.returns({
      die = function()
        die_called = true
      end
    })

    -- Make a request to start a job
    local keys = vim.api.nvim_replace_termcodes('xhello<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- press q
    keys = vim.api.nvim_replace_termcodes('q', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.is_true(die_called)
  end)

  it("Has a loading indicator", function()
    local bufs = code_window.build_and_mount()

    local s = stub(llm, "generate")

    local keys = vim.api.nvim_replace_termcodes('xloading test<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args = s.calls[1].refs[1]

    -- before on_response gets a response from the llm, the right window should show a loading indicator
    assert.same(vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true), { "Loading..." })

    -- simulate a response from the llm
    args.on_read(nil, "response line")

    -- After the response, the loading indicator should be replaced by the response
    assert.same(vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true), { "response line" })
  end)

  it("Replaces old response for new one that comes in", function()
    local bufs = code_window.build_and_mount()

    local s = stub(llm, "generate")

    -- Simulate first response
    local keys = vim.api.nvim_replace_termcodes('xfirst response<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    ---@type MakeGenerateRequestArgs
    local args_first = s.calls[1].refs[1]
    args_first.on_read(nil, "first response line")
    if args_first.on_end then args_first.on_end() end

    assert.same(vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true), { "first response line" })

    -- Simulate second response
    keys = vim.api.nvim_replace_termcodes('xsecond response<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)
    if args_first.on_end then args_first.on_end() end

    ---@type MakeGenerateRequestArgs
    local args_second = s.calls[2].refs[1]
    args_second.on_read(nil, "second response line")

    -- After the second response, the first response should be replaced by the second one
    assert.same(vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true), { "second response line" })
  end)

  it("kills any existing jobs in flight when <CR> is pressed", function()
    code_window.build_and_mount()
    local s = stub(llm, "generate")
    local job = {
      die = stub()
    }
    s.returns(job)

    -- Start a job
    local keys = vim.api.nvim_replace_termcodes('xstart job<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    -- Press <CR> to start a new job
    keys = vim.api.nvim_replace_termcodes('a new input<Esc><CR>', true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', false)

    assert.stub(job.die).was_called()
  end)

  it("clears all windows on <C-n>", function()
    local bufs = code_window.build_and_mount()

    -- Populate windows with some content
    vim.api.nvim_buf_set_lines(bufs.input_bufnr, 0, -1, true, { "input content" })
    vim.api.nvim_buf_set_lines(bufs.left_bufnr, 0, -1, true, { "left content" })
    vim.api.nvim_buf_set_lines(bufs.right_bufnr, 0, -1, true, { "right content" })

    -- Press <C-n>
    local keys = vim.api.nvim_replace_termcodes("<C-n>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Assert all windows are cleared
    assert.same({''}, vim.api.nvim_buf_get_lines(bufs.input_bufnr, 0, -1, true))
    assert.same({''}, vim.api.nvim_buf_get_lines(bufs.left_bufnr, 0, -1, true))
    assert.same({''}, vim.api.nvim_buf_get_lines(bufs.right_bufnr, 0, -1, true))
  end)

  it("retains text when reopened after <C-n>", function()
    local initial_text = { "initial text line 1", "initial text line 2" }
    local bufs = code_window.build_and_mount(initial_text)

    -- Press <C-n>
    local keys = vim.api.nvim_replace_termcodes("<Esc><C-n>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Close the window with :q
    keys = vim.api.nvim_replace_termcodes("<Esc>:q<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Reopen the window
    bufs = code_window.build_and_mount()

    local left_lines = vim.api.nvim_buf_get_lines(bufs.left_bufnr, 0, -1, true)

    assert.same(initial_text, left_lines)
  end)

  it("saves input text on normal mode entry and restores on reopen", function()
    local initial_input = "some initial input"
    local bufs = code_window.build_and_mount()

    -- Populate input window with some content and enter normal mode
    vim.api.nvim_buf_set_lines(bufs.input_bufnr, 0, -1, true, { initial_input })

    local keys = vim.api.nvim_replace_termcodes("<Esc>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Close the window with :q
    keys = vim.api.nvim_replace_termcodes(":q<CR>", true, true, true)
    vim.api.nvim_feedkeys(keys, 'mtx', true)

    -- Reopen the window
    bufs = code_window.build_and_mount()

    local input_lines = vim.api.nvim_buf_get_lines(bufs.input_bufnr, 0, -1, true)

    assert.same({ initial_input }, input_lines)
  end)
end)