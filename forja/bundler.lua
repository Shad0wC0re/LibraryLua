------------------------------------------------------------------------
-- forja.bundler — Empacotador de múltiplos arquivos Lua
-- Parte do compilador Forja
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local bundler = {}

-- Cache local
local io_open     = io.open
local string_find = string.find
local string_sub  = string.sub
local string_match = string.match
local string_gsub  = string.gsub
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat

------------------------------------------------------------------------
-- Configuração
------------------------------------------------------------------------

--- Separador de caminho do sistema
bundler.SEP = package.config:sub(1, 1)  -- '\' no Windows, '/' no Linux

--- Extensão de arquivos Lua
bundler.LUA_EXT = ".lua"

------------------------------------------------------------------------
-- resolve_path — Resolve um caminho de require para caminho de arquivo
------------------------------------------------------------------------
---@param name string       Nome do módulo (ex: "turbo.algo")
---@param search_paths table  Caminhos de busca
---@return string? filepath  Caminho do arquivo encontrado
function bundler.resolve_path(name, search_paths)
  -- Converte "turbo.algo" para "turbo/algo"
  local path_name = string_gsub(name, "%.", bundler.SEP)

  for _, base in ipairs(search_paths) do
    -- Tenta como arquivo direto
    local filepath = base .. bundler.SEP .. path_name .. bundler.LUA_EXT
    local f = io_open(filepath, "r")
    if f then
      f:close()
      return filepath
    end

    -- Tenta como init.lua dentro de diretório
    filepath = base .. bundler.SEP .. path_name .. bundler.SEP .. "init" .. bundler.LUA_EXT
    f = io_open(filepath, "r")
    if f then
      f:close()
      return filepath
    end
  end

  return nil
end

------------------------------------------------------------------------
-- scan_requires — Encontra todas as chamadas require() em um arquivo
------------------------------------------------------------------------
---@param filepath string
---@return table requires  Array de nomes de módulos
function bundler.scan_requires(filepath)
  local f = io_open(filepath, "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()

  local requires = {}
  local seen = {}

  -- Padrões para detectar require
  -- require("modulo")
  -- require('modulo')
  -- require "modulo"
  -- require 'modulo'
  for name in content:gmatch('require%s*%(%s*"([^"]+)"%s*%)') do
    if not seen[name] then
      seen[name] = true
      table_insert(requires, name)
    end
  end
  for name in content:gmatch("require%s*%(%s*'([^']+)'%s*%)") do
    if not seen[name] then
      seen[name] = true
      table_insert(requires, name)
    end
  end
  for name in content:gmatch('require%s+"([^"]+)"') do
    if not seen[name] then
      seen[name] = true
      table_insert(requires, name)
    end
  end
  for name in content:gmatch("require%s+'([^']+)'") do
    if not seen[name] then
      seen[name] = true
      table_insert(requires, name)
    end
  end

  return requires
end

------------------------------------------------------------------------
-- collect_dependencies — Coleta todas as dependências recursivamente
------------------------------------------------------------------------
---@param entry_file string    Arquivo de entrada
---@param search_paths table   Caminhos de busca
---@return table modules       Mapa de {nome_modulo = filepath}
---@return table order         Array de nomes na ordem de dependência
---@return table not_found     Módulos não encontrados
function bundler.collect_dependencies(entry_file, search_paths)
  local modules = {}
  local order = {}
  local not_found = {}
  local visited = {}

  local function visit(name, filepath)
    if visited[name] then return end
    visited[name] = true

    local requires = bundler.scan_requires(filepath)
    for _, req_name in ipairs(requires) do
      if not visited[req_name] then
        local req_path = bundler.resolve_path(req_name, search_paths)
        if req_path then
          visit(req_name, req_path)
        else
          -- Pode ser módulo padrão (io, os, string, etc.)
          if not not_found[req_name] then
            not_found[req_name] = true
            table_insert(not_found, req_name)
          end
        end
      end
    end

    modules[name] = filepath
    table_insert(order, name)
  end

  -- Inicia pelo arquivo de entrada como módulo "__main__"
  visit("__main__", entry_file)

  return modules, order, not_found
end

------------------------------------------------------------------------
-- bundle — Empacota todos os módulos em um único arquivo Lua
------------------------------------------------------------------------
---@param entry_file string    Arquivo de entrada principal
---@param search_paths? table  Caminhos de busca (default: {"."})
---@param options? table       Opções {minify=bool, strip_comments=bool}
---@return string bundled_code  Código Lua empacotado
---@return table info           Informações do bundle
function bundler.bundle(entry_file, search_paths, options)
  search_paths = search_paths or { "." }
  options = options or {}

  local modules, order, not_found = bundler.collect_dependencies(
    entry_file, search_paths
  )

  local parts = {}

  -- Cabeçalho
  table_insert(parts, "-- Bundled by Forja Compiler")
  table_insert(parts, "-- " .. os.date("%Y-%m-%d %H:%M:%S"))
  table_insert(parts, "")

  -- Sistema de módulos embutido
  table_insert(parts, "local __modules = {}")
  table_insert(parts, "local __loaded = {}")
  table_insert(parts, "local __original_require = require")
  table_insert(parts, "")
  table_insert(parts, "local function __require(name)")
  table_insert(parts, "  if __loaded[name] ~= nil then")
  table_insert(parts, "    return __loaded[name]")
  table_insert(parts, "  end")
  table_insert(parts, "  local loader = __modules[name]")
  table_insert(parts, "  if loader then")
  table_insert(parts, "    local result = loader()")
  table_insert(parts, "    if result == nil then result = true end")
  table_insert(parts, "    __loaded[name] = result")
  table_insert(parts, "    return result")
  table_insert(parts, "  end")
  table_insert(parts, "  return __original_require(name)")
  table_insert(parts, "end")
  table_insert(parts, "")
  table_insert(parts, "require = __require")
  table_insert(parts, "")

  -- Registra cada módulo (exceto __main__)
  for _, name in ipairs(order) do
    if name ~= "__main__" then
      local filepath = modules[name]
      local f = io_open(filepath, "r")
      if f then
        local code = f:read("*a")
        f:close()

        if options.strip_comments then
          code = bundler.strip_comments(code)
        end

        table_insert(parts, string_format("__modules[%q] = function()", name))
        table_insert(parts, code)
        table_insert(parts, "end")
        table_insert(parts, "")
      end
    end
  end

  -- Código principal (entry point)
  local f = io_open(entry_file, "r")
  if f then
    local main_code = f:read("*a")
    f:close()

    if options.strip_comments then
      main_code = bundler.strip_comments(main_code)
    end

    table_insert(parts, "-- Entry point")
    table_insert(parts, main_code)
  end

  local bundled = table_concat(parts, "\n")

  local info = {
    modules     = order,
    total       = #order,
    not_found   = not_found,
    size_bytes  = #bundled,
  }

  return bundled, info
end

------------------------------------------------------------------------
-- strip_comments — Remove comentários de código Lua (básico)
------------------------------------------------------------------------
---@param code string
---@return string
function bundler.strip_comments(code)
  -- Remove comentários de bloco --[[ ... ]]
  code = string_gsub(code, "%-%-%[%[.-%]%]", "")
  -- Remove comentários de linha (cuidado com strings)
  code = string_gsub(code, "%-%-[^\n]*", "")
  -- Remove linhas em branco consecutivas
  code = string_gsub(code, "\n\n+", "\n")
  return code
end

return bundler
