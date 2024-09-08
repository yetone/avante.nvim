local parsers = require("nvim-treesitter.parsers")
local Config = require("avante.config")

local get_node_text = vim.treesitter.get_node_text

---@class avante.utils.repo_map
local RepoMap = {}

local dependencies_queries = {
  lua = [[
    (function_call
      name: (identifier) @function_name
      arguments: (arguments
        (string) @required_file))
  ]],

  python = [[
    (import_from_statement
      module_name: (dotted_name) @import_module)
    (import_statement
      (dotted_name) @import_module)
  ]],

  javascript = [[
    (import_statement
      source: (string) @import_module)
    (call_expression
      function: (identifier) @function_name
      arguments: (arguments
        (string) @required_file))
  ]],

  typescript = [[
    (import_statement
      source: (string) @import_module)
    (call_expression
      function: (identifier) @function_name
      arguments: (arguments
        (string) @required_file))
  ]],

  go = [[
    (import_spec
      path: (interpreted_string_literal) @import_module)
  ]],

  rust = [[
    (use_declaration
      (scoped_identifier) @import_module)
    (use_declaration
      (identifier) @import_module)
  ]],

  c = [[
    (preproc_include
      (string_literal) @import_module)
    (preproc_include
      (system_lib_string) @import_module)
  ]],

  cpp = [[
    (preproc_include
      (string_literal) @import_module)
    (preproc_include
      (system_lib_string) @import_module)
  ]],
}

local definitions_queries = {
  python = [[
    ;; Capture top-level functions, class, and method definitions
    (module
      (expression_statement
        (assignment) @assignment
      )
    )
    (module
      (function_definition) @function
    )
    (module
      (class_definition
        body: (block
          (expression_statement
            (assignment) @class_assignment
          )
        )
      )
    )
    (module
      (class_definition
        body: (block
          (function_definition) @method
        )
      )
    )
  ]],
  javascript = [[
    ;; Capture exported functions, arrow functions, variables, classes, and method definitions
    (export_statement
      declaration: (lexical_declaration
        (variable_declarator) @variable
      )
    )
    (export_statement
      declaration: (function_declaration) @function
    )
    (export_statement
      declaration: (class_declaration
        body: (class_body
          (field_definition) @class_variable
        )
      )
    )
    (export_statement
      declaration: (class_declaration
        body: (class_body
          (method_definition) @method
        )
      )
    )
  ]],
  typescript = [[
    ;; Capture exported functions, arrow functions, variables, classes, and method definitions
    (export_statement
      declaration: (lexical_declaration
        (variable_declarator) @variable
      )
    )
    (export_statement
      declaration: (function_declaration) @function
    )
    (export_statement
      declaration: (class_declaration
        body: (class_body
          (public_field_definition) @class_variable
        )
      )
    )
    (interface_declaration
      body: (interface_body
        (property_signature) @class_variable
      )
    )
    (type_alias_declaration
      value: (object_type
        (property_signature) @class_variable
      )
    )
    (export_statement
      declaration: (class_declaration
        body: (class_body
          (method_definition) @method
        )
      )
    )
  ]],
  rust = [[
    ;; Capture public functions, structs, methods, and variable definitions
    (function_item) @function
    (impl_item
      body: (declaration_list
        (function_item) @method
      )
    )
    (struct_item
      body: (field_declaration_list
        (field_declaration) @class_variable
      )
    )
    (enum_item
      body: (enum_variant_list
        (enum_variant) @enum_item
      )
    )
    (const_item) @variable
  ]],
  go = [[
    ;; Capture top-level functions and struct definitions
    (var_declaration
      (var_spec) @variable
    )
    (const_declaration
      (const_spec) @variable
    )
    (function_declaration) @function
    (type_declaration
      (type_spec (struct_type)) @class
    )
    (type_declaration
      (type_spec
        (struct_type
          (field_declaration_list
            (field_declaration) @class_variable)))
    )
    (method_declaration) @method
  ]],
  c = [[
    ;; Capture extern functions, variables, public classes, and methods
    (function_definition
      (storage_class_specifier) @extern
    ) @function
    (class_specifier
      (public) @class
      (function_definition) @method
    ) @class
    (declaration
      (storage_class_specifier) @extern
    ) @variable
  ]],
  cpp = [[
    ;; Capture extern functions, variables, public classes, and methods
    (function_definition
      (storage_class_specifier) @extern
    ) @function
    (class_specifier
      (public) @class
      (function_definition) @method
    ) @class
    (declaration
      (storage_class_specifier) @extern
    ) @variable
  ]],
  lua = [[
    ;; Capture function and method definitions
    (variable_list) @variable
    (function_declaration) @function
  ]],
  ruby = [[
    ;; Capture top-level methods, class definitions, and methods within classes
    (method) @function
    (assignment) @assignment
    (class
      body: (body_statement
        (assignment) @class_assignment
        (method) @method
      )
    )
  ]],
}

local queries_filetype_map = {
  ["javascriptreact"] = "javascript",
  ["typescriptreact"] = "typescript",
}

local function get_query(queries, filetype)
  filetype = queries_filetype_map[filetype] or filetype
  return queries[filetype]
end

local function get_ts_lang(bufnr)
  local lang = parsers.get_buf_lang(bufnr)
  return lang
end

function RepoMap.get_parser(bufnr)
  local lang = get_ts_lang(bufnr)
  if not lang then return end
  local parser = parsers.get_parser(bufnr, lang)
  return parser, lang
end

function RepoMap.extract_dependencies(bufnr)
  local parser, lang = RepoMap.get_parser(bufnr)
  if not lang or not parser or not dependencies_queries[lang] then
    print("No parser or query available for this buffer's language: " .. (lang or "unknown"))
    return {}
  end

  local dependencies = {}
  local tree = parser:parse()[1]
  local root = tree:root()
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  local query = get_query(dependencies_queries, filetype)
  if not query then return dependencies end

  local query_obj = vim.treesitter.query.parse(lang, query)

  for _, node, _ in query_obj:iter_captures(root, bufnr, 0, -1) do
    -- local name = query.captures[id]
    local required_file = vim.treesitter.get_node_text(node, bufnr):gsub('"', ""):gsub("'", "")
    table.insert(dependencies, required_file)
  end

  return dependencies
end

function RepoMap.get_filetype_by_filepath(filepath) return vim.filetype.match({ filename = filepath }) end

function RepoMap.parse_file(filepath)
  local File = require("avante.utils.file")
  local source = File.read_content(filepath)

  local filetype = RepoMap.get_filetype_by_filepath(filepath)
  local lang = parsers.ft_to_lang(filetype)
  if lang then
    local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
    if ok then
      local tree = parser:parse()[1]
      local node = tree:root()
      return { node = node, source = source }
    else
      print("parser error", parser)
    end
  end
end

local function get_closest_parent_name(node, source)
  local parent = node:parent()
  while parent do
    local name = parent:field("name")[1]
    if name then return get_node_text(name, source) end
    parent = parent:parent()
  end
  return ""
end

local function find_parent_by_type(node, type)
  local parent = node:parent()
  while parent do
    if parent:type() == type then return parent end
    parent = parent:parent()
  end
  return nil
end

local function find_child_by_type(node, type)
  for child in node:iter_children() do
    if child:type() == type then return child end
    local res = find_child_by_type(child, type)
    if res then return res end
  end
  return nil
end

local function get_node_type(node, source)
  local node_type
  local predefined_type_node = find_child_by_type(node, "predefined_type")
  if predefined_type_node then
    node_type = get_node_text(predefined_type_node, source)
  else
    local value_type_node = node:field("type")[1]
    node_type = value_type_node and get_node_text(value_type_node, source) or ""
  end
  return node_type
end

-- Function to extract definitions from the file
function RepoMap.extract_definitions(filepath)
  local Utils = require("avante.utils")

  local filetype = RepoMap.get_filetype_by_filepath(filepath)

  if not filetype then return {} end

  -- Get the corresponding query for the detected language
  local query = get_query(definitions_queries, filetype)
  if not query then return {} end

  local parsed = RepoMap.parse_file(filepath)
  if not parsed then return {} end

  -- Get the current buffer's syntax tree
  local root = parsed.node

  local lang = parsers.ft_to_lang(filetype)

  -- Parse the query
  local query_obj = vim.treesitter.query.parse(lang, query)

  -- Store captured results
  local definitions = {}

  local class_def_map = {}
  local enum_def_map = {}

  local function get_class_def(name)
    local def = class_def_map[name]
    if def == nil then
      def = {
        type = "class",
        name = name,
        methods = {},
        properties = {},
      }
      class_def_map[name] = def
    end
    return def
  end

  local function get_enum_def(name)
    local def = enum_def_map[name]
    if def == nil then
      def = {
        type = "enum",
        name = name,
        items = {},
      }
      enum_def_map[name] = def
    end
    return def
  end

  for _, captures, _ in query_obj:iter_matches(root, parsed.source) do
    for id, node in pairs(captures) do
      local type = query_obj.captures[id]
      local name_node = node:field("name")[1]
      local name = name_node and get_node_text(name_node, parsed.source) or ""

      if type == "class" then
        if name ~= "" then get_class_def(name) end
      elseif type == "enum_item" then
        local enum_name = get_closest_parent_name(node, parsed.source)
        if enum_name and filetype == "go" and not Utils.is_first_letter_uppercase(enum_name) then goto continue end
        local enum_def = get_enum_def(enum_name)
        local enum_type_node = find_child_by_type(node, "type_identifier")
        local enum_type = enum_type_node and get_node_text(enum_type_node, parsed.source) or ""
        table.insert(enum_def.items, {
          name = name,
          type = enum_type,
        })
      elseif type == "method" then
        local params_node = node:field("parameters")[1]
        local params = params_node and get_node_text(params_node, parsed.source) or "()"
        local return_type_node = node:field("return_type")[1] or node:field("result")[1]
        local return_type = return_type_node and get_node_text(return_type_node, parsed.source) or "void"

        local class_name
        local impl_item_node = find_parent_by_type(node, "impl_item")
        local receiver_node = node:field("receiver")[1]
        if impl_item_node then
          local impl_type_node = impl_item_node:field("type")[1]
          class_name = impl_type_node and get_node_text(impl_type_node, parsed.source) or ""
        elseif receiver_node then
          local type_identifier_node = find_child_by_type(receiver_node, "type_identifier")
          class_name = type_identifier_node and get_node_text(type_identifier_node, parsed.source) or ""
        else
          class_name = get_closest_parent_name(node, parsed.source)
        end
        if class_name and filetype == "go" and not Utils.is_first_letter_uppercase(class_name) then goto continue end
        local class_def = get_class_def(class_name)

        local accessibility_modifier_node = find_child_by_type(node, "accessibility_modifier")
        local accessibility_modifier = accessibility_modifier_node
            and get_node_text(accessibility_modifier_node, parsed.source)
          or ""

        table.insert(class_def.methods, {
          type = "function",
          name = name,
          params = params,
          return_type = return_type,
          accessibility_modifier = accessibility_modifier,
        })
      elseif type == "class_assignment" then
        local left_node = node:field("left")[1]
        local left = left_node and get_node_text(left_node, parsed.source) or ""

        local value_type = get_node_type(node, parsed.source)

        local class_name = get_closest_parent_name(node, parsed.source)
        if class_name and filetype == "go" and not Utils.is_first_letter_uppercase(class_name) then goto continue end

        local class_def = get_class_def(class_name)

        table.insert(class_def.properties, {
          type = "variable",
          name = left,
          value_type = value_type,
        })
      elseif type == "class_variable" then
        local value_type = get_node_type(node, parsed.source)

        local class_name = get_closest_parent_name(node, parsed.source)
        if class_name and filetype == "go" and not Utils.is_first_letter_uppercase(class_name) then goto continue end

        local class_def = get_class_def(class_name)

        table.insert(class_def.properties, {
          type = "variable",
          name = name,
          value_type = value_type,
        })
      elseif type == "function" or type == "arrow_function" then
        if name and filetype == "go" and not Utils.is_first_letter_uppercase(name) then goto continue end
        local impl_item_node = find_parent_by_type(node, "impl_item")
        if impl_item_node then goto continue end
        local function_node = find_parent_by_type(node, "function_declaration")
          or find_parent_by_type(node, "function_definition")
        if function_node then goto continue end
        -- Extract function parameters and return type
        local params_node = node:field("parameters")[1]
        local params = params_node and get_node_text(params_node, parsed.source) or "()"
        local return_type_node = node:field("return_type")[1] or node:field("result")[1]
        local return_type = return_type_node and get_node_text(return_type_node, parsed.source) or "void"

        local accessibility_modifier_node = find_child_by_type(node, "accessibility_modifier")
        local accessibility_modifier = accessibility_modifier_node
            and get_node_text(accessibility_modifier_node, parsed.source)
          or ""

        local def = {
          type = "function",
          name = name,
          params = params,
          return_type = return_type,
          accessibility_modifier = accessibility_modifier,
        }
        table.insert(definitions, def)
      elseif type == "assignment" then
        local impl_item_node = find_parent_by_type(node, "impl_item")
          or find_parent_by_type(node, "class_declaration")
          or find_parent_by_type(node, "class_definition")
        if impl_item_node then goto continue end
        local function_node = find_parent_by_type(node, "function_declaration")
          or find_parent_by_type(node, "function_definition")
        if function_node then goto continue end

        local left_node = node:field("left")[1]
        local left = left_node and get_node_text(left_node, parsed.source) or ""

        if left and filetype == "go" and not Utils.is_first_letter_uppercase(left) then goto continue end

        local value_type = get_node_type(node, parsed.source)

        local def = {
          type = "variable",
          name = left,
          value_type = value_type,
        }
        table.insert(definitions, def)
      elseif type == "variable" then
        local impl_item_node = find_parent_by_type(node, "impl_item")
          or find_parent_by_type(node, "class_declaration")
          or find_parent_by_type(node, "class_definition")
        if impl_item_node then goto continue end
        local function_node = find_parent_by_type(node, "function_declaration")
          or find_parent_by_type(node, "function_definition")
        if function_node then goto continue end

        local value_type = get_node_type(node, parsed.source)

        if name and filetype == "go" and not Utils.is_first_letter_uppercase(name) then goto continue end

        local def = { type = "variable", name = name, value_type = value_type }
        table.insert(definitions, def)
      end
      ::continue::
    end
  end

  for _, def in pairs(class_def_map) do
    table.insert(definitions, def)
  end

  for _, def in pairs(enum_def_map) do
    table.insert(definitions, def)
  end

  return definitions
end

local function stringify_function(def)
  local res = "func " .. def.name .. def.params .. ":" .. def.return_type .. ";"
  if def.accessibility_modifier and def.accessibility_modifier ~= "" then
    res = def.accessibility_modifier .. " " .. res
  end
  return res
end

local function stringify_variable(def)
  local res = "var " .. def.name
  if def.value_type and def.value_type ~= "" then res = res .. ":" .. def.value_type end
  return res .. ";"
end

local function stringify_enum_item(def)
  local res = def.name
  if def.value_type and def.value_type ~= "" then res = res .. ":" .. def.value_type end
  return res .. ";"
end

-- Function to load file content into a temporary buffer, process it, and then delete the buffer
function RepoMap.stringify_definitions(filepath)
  if vim.endswith(filepath, "~") then return "" end

  -- Extract definitions
  local definitions = RepoMap.extract_definitions(filepath)

  local output = ""
  -- Print or process the definitions
  for _, def in ipairs(definitions) do
    if def.type == "class" then
      output = output .. def.type .. " " .. def.name .. "{"
      for _, property in ipairs(def.properties) do
        output = output .. stringify_variable(property)
      end
      for _, method in ipairs(def.methods) do
        output = output .. stringify_function(method)
      end
      output = output .. "}"
    elseif def.type == "enum" then
      output = output .. def.type .. " " .. def.name .. "{"
      for _, item in ipairs(def.items) do
        output = output .. stringify_enum_item(item) .. ""
      end
      output = output .. "}"
    elseif def.type == "function" then
      output = output .. stringify_function(def)
    elseif def.type == "variable" then
      output = output .. stringify_variable(def)
    end
  end

  return output
end

function RepoMap._build_repo_map(project_root, file_ext)
  local Utils = require("avante.utils")
  local output = {}
  local gitignore_path = project_root .. "/.gitignore"
  local ignore_patterns, negate_patterns = Utils.parse_gitignore(gitignore_path)
  local filepaths = Utils.scan_directory(project_root, ignore_patterns, negate_patterns)
  vim.iter(filepaths):each(function(filepath)
    if not Utils.is_same_file_ext(file_ext, filepath) then return end
    local definitions = RepoMap.stringify_definitions(filepath)
    if definitions == "" then return end
    table.insert(output, {
      path = Utils.relative_path(filepath),
      lang = RepoMap.get_filetype_by_filepath(filepath),
      defs = definitions,
    })
  end)
  return output
end

local cache = {}

function RepoMap.get_repo_map()
  local Utils = require("avante.utils")
  local project_root = Utils.root.get()
  local file_ext = vim.fn.expand("%:e")
  local cache_key = project_root .. "." .. file_ext
  local cached = cache[cache_key]
  if cached then return cached end

  local PPath = require("plenary.path")
  local Path = require("avante.path")
  local repo_map

  local function build_and_save()
    repo_map = RepoMap._build_repo_map(project_root, file_ext)
    cache[cache_key] = repo_map
    Path.repo_map.save(project_root, file_ext, repo_map)
  end

  repo_map = Path.repo_map.load(project_root, file_ext)

  if not repo_map or next(repo_map) == nil then
    build_and_save()
    if not repo_map then return end
  else
    local timer = vim.loop.new_timer()

    if timer then
      timer:start(
        0,
        0,
        vim.schedule_wrap(function()
          build_and_save()
          timer:close()
        end)
      )
    end
  end

  local update_repo_map = vim.schedule_wrap(function(rel_filepath)
    if rel_filepath and Utils.is_same_file_ext(file_ext, rel_filepath) then
      local abs_filepath = PPath:new(project_root):joinpath(rel_filepath):absolute()
      local definitions = RepoMap.stringify_definitions(abs_filepath)
      if definitions == "" then return end
      local found = false
      for _, m in ipairs(repo_map) do
        if m.path == rel_filepath then
          m.defs = definitions
          found = true
          break
        end
      end
      if not found then
        table.insert(repo_map, {
          path = Utils.relative_path(abs_filepath),
          lang = RepoMap.get_filetype_by_filepath(abs_filepath),
          defs = definitions,
        })
      end
      cache[cache_key] = repo_map
      Path.repo_map.save(project_root, file_ext, repo_map)
    end
  end)

  local handle = vim.loop.new_fs_event()

  if handle then
    handle:start(project_root, { recursive = true }, function(err, rel_filepath)
      if err then
        print("Error watching directory " .. project_root .. ":", err)
        return
      end

      if rel_filepath then update_repo_map(rel_filepath) end
    end)
  end

  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
    callback = function(ev)
      vim.defer_fn(function()
        local filepath = vim.api.nvim_buf_get_name(ev.buf)
        if not vim.startswith(filepath, project_root) then return end
        local rel_filepath = Utils.relative_path(filepath)
        update_repo_map(rel_filepath)
      end, 0)
    end,
  })

  return repo_map
end

return RepoMap
