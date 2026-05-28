------------------------------------------------------------------------
-- Forja — Compilador Lua → Executável
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------
--
-- Forja compila projetos Lua (um ou múltiplos arquivos) em executáveis
-- nativos. O processo é:
--
--   1. Análise de dependências (resolve todos os require)
--   2. Empacotamento (bundle) em um único arquivo Lua
--   3. Compilação para bytecode (string.dump)
--   4. Geração de stub C mínimo (~30 linhas)
--   5. Compilação nativa (cl.exe / gcc)
--   6. Executável final
--
-- Uso:
--   lua55 forja/init.lua build meu_programa.lua -o meu_programa.exe
--   lua55 forja/init.lua bundle meu_programa.lua -o bundle.lua
--   lua55 forja/init.lua info
--
------------------------------------------------------------------------

local forja = {}

-- Importa submódulos
local bundler  = require("forja.bundler")
local compiler = require("forja.compiler")

-- Exporta submódulos
forja.bundler  = bundler
forja.compiler = compiler

-- Versão
forja._VERSION = "Forja 1.0.0"
forja._DESCRIPTION = "Lua to executable compiler"

------------------------------------------------------------------------
-- build — Compila um projeto Lua para executável
------------------------------------------------------------------------
---@param entry_file string     Arquivo Lua principal
---@param output_exe string     Caminho do executável de saída
---@param options? table        Opções
---@return boolean ok
---@return string? error_msg
---@return table? info
function forja.build(entry_file, output_exe, options)
  options = options or {}

  io.write(string.format("[forja] Forja %s\n", forja._VERSION))
  io.write(string.format("[forja] Entrada: %s\n", entry_file))
  io.write(string.format("[forja] Saída: %s\n", output_exe))
  io.write("\n")

  -- Passo 1: Bundle
  io.write("[forja] Empacotando módulos...\n")
  local search_paths = options.search_paths or { "." }
  local bundled_code, bundle_info = bundler.bundle(entry_file, search_paths, {
    strip_comments = options.strip_comments,
  })

  io.write(string.format("[forja] Módulos: %d | Tamanho: %d bytes\n",
    bundle_info.total, bundle_info.size_bytes))

  if #bundle_info.not_found > 0 then
    io.write("[forja] Módulos externos (não empacotados):\n")
    for _, name in ipairs(bundle_info.not_found) do
      io.write("  - " .. name .. "\n")
    end
  end
  io.write("\n")

  -- Passo 2: Compila para executável
  local ok, err, build_info = compiler.build(bundled_code, output_exe, options)

  if not ok then
    io.write(string.format("[forja] ERRO: %s\n", err or "desconhecido"))
    return false, err
  end

  io.write("\n[forja] Compilação concluída com sucesso!\n")

  return true, nil, {
    bundle = bundle_info,
    build  = build_info,
  }
end

------------------------------------------------------------------------
-- bundle_only — Apenas empacota (sem compilar)
------------------------------------------------------------------------
---@param entry_file string
---@param output_file string
---@param options? table
---@return boolean ok
---@return table? info
function forja.bundle_only(entry_file, output_file, options)
  options = options or {}
  local search_paths = options.search_paths or { "." }

  local bundled_code, info = bundler.bundle(entry_file, search_paths, {
    strip_comments = options.strip_comments,
  })

  local f = io.open(output_file, "w")
  if not f then
    return false, { error = "Não foi possível criar: " .. output_file }
  end
  f:write(bundled_code)
  f:close()

  io.write(string.format("[forja] Bundle: %s (%d bytes, %d módulos)\n",
    output_file, info.size_bytes, info.total))

  return true, info
end

------------------------------------------------------------------------
-- info — Exibe informações sobre ferramentas disponíveis
------------------------------------------------------------------------
function forja.info()
  io.write(string.format("Forja %s\n", forja._VERSION))
  io.write(string.format("Lua %s\n\n", _VERSION))

  local tools = compiler.detect_tools()

  io.write("Ferramentas detectadas:\n")
  io.write(string.format("  luac:        %s\n", tools.luac or "NÃO ENCONTRADO"))
  io.write(string.format("  Compilador C: %s\n", tools.cc or "NÃO ENCONTRADO"))
  io.write(string.format("  Lua lib:     %s\n", tools.lua_lib or "NÃO ENCONTRADO"))
  io.write(string.format("  Lua include: %s\n", tools.lua_include or "NÃO ENCONTRADO"))
  io.write("\n")

  if tools.cc and tools.lua_lib and tools.lua_include then
    io.write("Status: Pronto para compilar executáveis!\n")
  elseif tools.cc then
    io.write("Status: Compilador C encontrado, mas faltam headers/lib do Lua.\n")
  else
    io.write("Status: Apenas bytecode disponível (sem compilador C).\n")
    io.write("Instale Visual Studio (cl.exe) ou GCC para gerar executáveis.\n")
  end
end

------------------------------------------------------------------------
-- CLI — Interface de linha de comando
------------------------------------------------------------------------
local function cli()
  local args = arg or {}
  local command = args[1]

  if command == "build" then
    local entry = args[2]
    local output = nil
    local search_paths = { "." }
    local strip = false
    local format = nil
    local target_os = nil
    local module_name = nil
    local cc = nil
    local lua_include = nil
    local lua_lib = nil

    -- Parse argumentos
    local i = 3
    while i <= #args do
      if args[i] == "-o" or args[i] == "--output" then
        i = i + 1
        output = args[i]
      elseif args[i] == "-p" or args[i] == "--path" then
        i = i + 1
        table.insert(search_paths, args[i])
      elseif args[i] == "--strip" then
        strip = true
      elseif args[i] == "-fmt" or args[i] == "--format" then
        i = i + 1
        format = args[i]
      elseif args[i] == "-os" or args[i] == "--target-os" then
        i = i + 1
        target_os = args[i]
      elseif args[i] == "-mod" or args[i] == "--module" then
        i = i + 1
        module_name = args[i]
      elseif args[i] == "--cc" then
        i = i + 1
        cc = args[i]
      elseif args[i] == "--lua-include" then
        i = i + 1
        lua_include = args[i]
      elseif args[i] == "--lua-lib" then
        i = i + 1
        lua_lib = args[i]
      end
      i = i + 1
    end

    if not entry then
      io.write("Uso: lua55 forja build <arquivo.lua> [-o saida]\n")
      return
    end

    -- Determina sufixo padrão de saída
    if not output then
      local base = entry:match("(.+)%.lua$") or entry
      local suffix = ".exe"
      if format == "dll" then suffix = ".dll"
      elseif format == "so" then suffix = ".so"
      elseif format == "dylib" then suffix = ".dylib"
      elseif format == "sh" then suffix = ".sh"
      elseif format == "bat" then suffix = ".bat"
      elseif target_os == "linux" or target_os == "macos" then suffix = ""
      end
      output = base .. suffix
    end

    forja.build(entry, output, {
      search_paths = search_paths,
      strip_comments = strip,
      format = format,
      target_os = target_os,
      module_name = module_name,
      cc = cc,
      lua_include = lua_include,
      lua_lib = lua_lib,
    })

  elseif command == "bundle" then
    local entry = args[2]
    local output = nil

    local i = 3
    while i <= #args do
      if args[i] == "-o" or args[i] == "--output" then
        i = i + 1
        output = args[i]
      end
      i = i + 1
    end

    if not entry then
      io.write("Uso: lua55 forja bundle <arquivo.lua> [-o bundle.lua]\n")
      return
    end

    output = output or "bundle.lua"
    forja.bundle_only(entry, output)

  elseif command == "generate" or command == "gen" then
    local output = nil
    local count = 0
    local format_type = "text"
    local min_val = 1
    local max_val = 2000000000
    local decimals = 0
    local negatives = 0
    local empty_lines = 0
    local bin_format = "i8"
    local separator = ","
    local cols = 1

    -- Parse argumentos
    local i = 2
    while i <= #args do
      if args[i] == "-o" or args[i] == "--output" then
        i = i + 1
        output = args[i]
      elseif args[i] == "-n" or args[i] == "--count" then
        i = i + 1
        count = tonumber(args[i]) or 0
      elseif args[i] == "-t" or args[i] == "--type" then
        i = i + 1
        format_type = args[i]
      elseif args[i] == "--min" then
        i = i + 1
        min_val = tonumber(args[i]) or 1
      elseif args[i] == "--max" then
        i = i + 1
        max_val = tonumber(args[i]) or 2000000000
      elseif args[i] == "--decimals" then
        i = i + 1
        decimals = tonumber(args[i]) or 0
      elseif args[i] == "--negatives" then
        i = i + 1
        negatives = tonumber(args[i]) or 0
      elseif args[i] == "--empty-lines" then
        i = i + 1
        empty_lines = tonumber(args[i]) or 0
      elseif args[i] == "--bin-format" then
        i = i + 1
        bin_format = args[i]
      elseif args[i] == "--separator" then
        i = i + 1
        separator = args[i]
      elseif args[i] == "--cols" then
        i = i + 1
        cols = tonumber(args[i]) or 1
      end
      i = i + 1
    end

    if not output then
      io.write("Erro: Arquivo de saída não especificado. Use -o <arquivo>\n")
      return
    end
    if count <= 0 then
      io.write("Erro: Quantidade de elementos inválida. Use -n <quantidade>\n")
      return
    end

    io.write(string.format("[forja] Gerando %d elementos em %s...\n", count, output))
    
    -- Ajusta package.path temporariamente para carregar o Turbo localmente se necessário
    local old_path = package.path
    package.path = ".\\?.lua;.\\?\\init.lua;" .. package.path
    local turbo = require("turbo")
    
    local start = os.clock()
    local ok, err = turbo.generator.generate(output, count, {
      type = format_type,
      min = min_val,
      max = max_val,
      decimals = decimals,
      negatives = negatives,
      empty_lines = empty_lines,
      bin_format = bin_format,
      separator = separator,
      cols = cols
    })
    local elapsed = os.clock() - start
    package.path = old_path

    if ok then
      io.write(string.format("[forja] Arquivo gerado com sucesso em %.4fs!\n", elapsed))
    else
      io.write("[forja] Erro ao gerar arquivo: " .. tostring(err) .. "\n")
    end

  elseif command == "info" then
    forja.info()

  else
    io.write(string.format("Forja %s — Compilador Lua → Executável\n\n", forja._VERSION))
    io.write("Comandos:\n")
    io.write("  build  <arquivo.lua> [-o saida.exe]  Compila para executável\n")
    io.write("  bundle <arquivo.lua> [-o bundle.lua]  Empacota módulos\n")
    io.write("  generate -o <saida> -n <count> [opc]  Gera arquivos de dados massivos\n")
    io.write("  info                                  Mostra ferramentas\n")
    io.write("\nOpções do Build:\n")
    io.write("  -o, --output <arquivo>   Arquivo de saída\n")
    io.write("  -p, --path <caminho>     Caminho de busca adicional\n")
    io.write("  --strip                  Remove comentários\n")
    io.write("\nOpções do Generate:\n")
    io.write("  -o, --output <arquivo>   Arquivo de saída\n")
    io.write("  -n, --count <quantidade> Quantidade de elementos a gerar\n")
    io.write("  -t, --type <tipo>        Tipo de arquivo: text (padrão), binary, csv\n")
    io.write("  --min <valor>            Valor mínimo (padrão: 1)\n")
    io.write("  --max <valor>            Valor máximo (padrão: 2000000000)\n")
    io.write("  --decimals <chance>      Chance de decimais entre 0.0 e 1.0 (apenas text/csv)\n")
    io.write("  --negatives <chance>     Chance de negativos entre 0.0 e 1.0\n")
    io.write("  --empty-lines <chance>   Chance de linhas vazias entre 0.0 e 1.0 (apenas text/csv)\n")
    io.write("  --bin-format <formato>   Formato do string.pack: i8, I8, d, f, i4, I4 (padrão: i8)\n")
    io.write("  --cols <numero>          Número de colunas (apenas csv, padrão: 1)\n")
    io.write("  --separator <char>       Separador de colunas (apenas csv, padrão: ,)\n")
  end
end

-- Se executado diretamente, roda a CLI
if arg and arg[0] and (arg[0]:match("forja") or arg[0]:match("init%.lua")) then
  cli()
end

return forja
