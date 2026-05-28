------------------------------------------------------------------------
-- forja.compiler — Compilação de Lua para bytecode e executável
-- Parte do compilador Forja
-- 100% Lua puro | Compatível com Lua 5.3+ / 5.5
------------------------------------------------------------------------

local compiler = {}

-- Cache local
local io_open      = io.open
local os_execute   = os.execute
local os_remove    = os.remove
local string_format = string.format
local string_dump   = string.dump

local hex_cache = {}
for i = 0, 255 do
  hex_cache[i] = string_format("0x%02x", i)
end

------------------------------------------------------------------------
-- Configuração
------------------------------------------------------------------------

--- Separador de caminho
compiler.SEP = package.config:sub(1, 1)

--- Detecta o sistema operacional
compiler.OS = (compiler.SEP == "\\") and "windows" or "unix"

------------------------------------------------------------------------
-- detect_tools — Detecta ferramentas disponíveis no sistema
------------------------------------------------------------------------
---@return table tools  {luac=string, cc=string, lua_lib=string, lua_include=string}
function compiler.detect_tools()
  local tools = {
    luac = nil,
    cc = nil,
    lua_lib = nil,
    lua_include = nil,
  }

  -- Detecta luac
  local luac_names = { "luac55", "luac5.5", "luac" }
  for _, name in ipairs(luac_names) do
    local ok = os_execute(name .. " -v >NUL 2>NUL")
        or os_execute(name .. " -v >/dev/null 2>&1")
    if ok then
      tools.luac = name
      break
    end
  end

  -- Detecta compilador C
  if compiler.OS == "windows" then
    -- Tenta cl.exe (MSVC)
    local ok = os_execute("cl >NUL 2>NUL")
    if ok then
      tools.cc = "cl"
    else
      -- Tenta gcc (MinGW)
      ok = os_execute("gcc --version >NUL 2>NUL")
      if ok then
        tools.cc = "gcc"
      end
    end
  else
    -- Unix: tenta gcc, depois cc
    local ok = os_execute("gcc --version >/dev/null 2>&1")
    if ok then
      tools.cc = "gcc"
    else
      ok = os_execute("cc --version >/dev/null 2>&1")
      if ok then
        tools.cc = "cc"
      end
    end
  end

  -- Detecta biblioteca e headers do Lua
  -- Procura em caminhos comuns
  local lua_exe_path = nil

  if compiler.OS == "windows" then
    -- Tenta encontrar via where
    local p = io.popen("where lua55.exe 2>NUL")
    if p then
      lua_exe_path = p:read("*l")
      p:close()
    end
    if not lua_exe_path then
      p = io.popen("where lua.exe 2>NUL")
      if p then
        lua_exe_path = p:read("*l")
        p:close()
      end
    end
  else
    local p = io.popen("which lua5.5 2>/dev/null || which lua 2>/dev/null")
    if p then
      lua_exe_path = p:read("*l")
      p:close()
    end
  end

  if lua_exe_path then
    -- Extrai o diretório base
    local base_dir = lua_exe_path:match("(.+)[/\\][^/\\]+$")
    if base_dir then
      -- Procura lua55.lib ou liblua55.a
      local lib_names = { "lua55.lib", "liblua5.5.a", "liblua55.a", "liblua.a" }
      for _, lib_name in ipairs(lib_names) do
        local lib_path = base_dir .. compiler.SEP .. lib_name
        local f = io_open(lib_path, "rb")
        if f then
          f:close()
          tools.lua_lib = lib_path
          break
        end
      end

      -- Procura headers
      local include_paths = {
        base_dir .. compiler.SEP .. "include" .. compiler.SEP .. "lua" .. compiler.SEP .. "5.5",
        base_dir .. compiler.SEP .. "include",
        base_dir .. compiler.SEP .. ".." .. compiler.SEP .. "include" .. compiler.SEP .. "lua" .. compiler.SEP .. "5.5",
      }
      for _, inc_path in ipairs(include_paths) do
        local f = io_open(inc_path .. compiler.SEP .. "lua.h", "r")
        if f then
          f:close()
          tools.lua_include = inc_path
          break
        end
      end
    end
  end

  return tools
end

------------------------------------------------------------------------
-- compile_to_bytecode — Compila código Lua para bytecode
------------------------------------------------------------------------
---@param lua_code string      Código Lua fonte
---@param output_file string   Arquivo de saída (.luac)
---@param options? table       {strip=bool}
---@return boolean ok
---@return string? error_msg
function compiler.compile_to_bytecode(lua_code, output_file, options)
  options = options or {}

  -- Método 1: Usa string.dump (100% Lua, sem luac externo)
  local fn, err = load(lua_code, "=bundle")
  if not fn then
    return false, "Erro de compilação: " .. tostring(err)
  end

  local bytecode = string_dump(fn, options.strip)

  local f = io_open(output_file, "wb")
  if not f then
    return false, "Não foi possível criar: " .. output_file
  end
  f:write(bytecode)
  f:close()

  return true
end

------------------------------------------------------------------------
-- generate_c_stub — Gera o código C mínimo que carrega o bytecode
------------------------------------------------------------------------
---@param bytecode_file string  Caminho do arquivo de bytecode
---@param c_output string      Caminho do arquivo C de saída
---@param options? table       Opções {format=string, module_name=string}
---@return boolean ok
---@return string? error_msg
function compiler.generate_c_stub(bytecode_file, c_output, options)
  options = options or {}
  local format = options.format or "exe"
  local module_name = options.module_name or "module"

  -- Lê o bytecode
  local f = io_open(bytecode_file, "rb")
  if not f then
    return false, "Não foi possível ler: " .. bytecode_file
  end
  local bytecode = f:read("*a")
  f:close()

  -- Converte bytecode para array C
  local hex_parts = {}
  local len = #bytecode
  local byte = string.byte
  for i = 1, len do
    hex_parts[i] = hex_cache[byte(bytecode, i)]
  end

  local c_code
  if format == "dll" or format == "so" or format == "dylib" then
    -- Template para biblioteca compartilhada
    c_code = string_format([[
/* Gerado pelo Forja Compiler — Não editar manualmente */
/* Stub para biblioteca compartilhada Lua */

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static const unsigned char bytecode[] = {
  %s
};

static const unsigned int bytecode_size = %d;

#if defined(_WIN32)
#define FORJA_EXPORT __declspec(dllexport)
#else
#define FORJA_EXPORT __attribute__((visibility("default")))
#endif

FORJA_EXPORT int luaopen_%s(lua_State *L) {
    int status = luaL_loadbuffer(L,
        (const char *)bytecode, bytecode_size, "=%s");

    if (status != LUA_OK) {
        lua_error(L);
        return 0;
    }

    lua_call(L, 0, LUA_MULTRET);
    return lua_gettop(L);
}
]], table.concat(hex_parts, ","), #bytecode, module_name, module_name)
  else
    -- Template para executável
    c_code = string_format([[
/* Gerado pelo Forja Compiler — Não editar manualmente */
/* Stub mínimo para carregar bytecode Lua */

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

static const unsigned char bytecode[] = {
  %s
};

static const unsigned int bytecode_size = %d;

int main(int argc, char *argv[]) {
    lua_State *L = luaL_newstate();
    if (!L) {
        fprintf(stderr, "Erro: falha ao criar estado Lua\n");
        return 1;
    }

    luaL_openlibs(L);

    /* Passa argumentos da linha de comando */
    lua_createtable(L, argc, 0);
    for (int i = 0; i < argc; i++) {
        lua_pushstring(L, argv[i]);
        lua_rawseti(L, -2, i);
    }
    lua_setglobal(L, "arg");

    /* Carrega e executa o bytecode */
    int status = luaL_loadbuffer(L,
        (const char *)bytecode, bytecode_size, "=forja");

    if (status != LUA_OK) {
        fprintf(stderr, "Erro ao carregar: %%s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    status = lua_pcall(L, 0, LUA_MULTRET, 0);
    if (status != LUA_OK) {
        fprintf(stderr, "Erro: %%s\n", lua_tostring(L, -1));
        lua_close(L);
        return 1;
    }

    lua_close(L);
    return 0;
}
]], table.concat(hex_parts, ","), #bytecode)
  end

  -- Escreve o arquivo C
  local out = io_open(c_output, "w")
  if not out then
    return false, "Não foi possível criar: " .. c_output
  end
  out:write(c_code)
  out:close()

  return true
end

------------------------------------------------------------------------
-- compile_c — Compila o stub C para executável ou biblioteca compartilhada
------------------------------------------------------------------------
---@param c_file string        Arquivo C de entrada
---@param output_file string   Arquivo de saída (.exe, .dll, .so, etc.)
---@param tools table          Ferramentas detectadas
---@param options? table       Opções {format=string, target_os=string, cc=string, lua_include=string, lua_lib=string}
---@return boolean ok
---@return string? error_msg
function compiler.compile_c(c_file, output_file, tools, options)
  options = options or {}
  local format = options.format or "exe"
  local target_os = options.target_os or compiler.OS

  local cc = options.cc or tools.cc
  local lua_include = options.lua_include or tools.lua_include
  local lua_lib = options.lua_lib or tools.lua_lib

  if not cc then
    return false, "Nenhum compilador C encontrado ou especificado (cl.exe, gcc, etc.)"
  end

  if not lua_include then
    return false, "Headers do Lua não encontrados (lua.h). Use --lua-include"
  end

  local is_macos_dylib = (target_os == "macos" and (format == "dylib" or format == "so"))
  if not lua_lib and not is_macos_dylib then
    return false, "Biblioteca do Lua não encontrada (lua55.lib / liblua.a). Use --lua-lib"
  end

  local cmd

  -- MSVC
  if cc == "cl" then
    if format == "dll" then
      cmd = string_format(
        'cl /nologo /O2 /LD /I"%s" "%s" "%s" /Fe"%s"',
        lua_include, c_file, lua_lib, output_file
      )
    else
      cmd = string_format(
        'cl /nologo /O2 /MT /I"%s" "%s" "%s" /Fe"%s" /link /SUBSYSTEM:CONSOLE',
        lua_include, c_file, lua_lib, output_file
      )
    end
  -- GCC or Clang
  elseif cc == "gcc" or cc == "cc" or cc:match("gcc") or cc:match("clang") then
    local lib_dir = lua_lib and lua_lib:match("(.+)[/\\][^/\\]+$") or "."
    local lib_name = lua_lib and (lua_lib:match("[/\\]lib([^/\\%.]+)%.[^/\\]+$") or lua_lib:match("[/\\]([^/\\%.]+)%.lib$") or "lua55") or "lua55"

    if format == "dll" or format == "so" then
      if target_os == "macos" then
        cmd = string_format(
          '%s -dynamiclib -undefined dynamic_lookup -O2 -o "%s" "%s" -I"%s"',
          cc, output_file, c_file, lua_include
        )
      else
        cmd = string_format(
          '%s -shared -fPIC -O2 -o "%s" "%s" -I"%s" -L"%s" -l%s -lm -ldl',
          cc, output_file, c_file, lua_include, lib_dir, lib_name
        )
      end
    elseif format == "dylib" then
      cmd = string_format(
        '%s -dynamiclib -undefined dynamic_lookup -O2 -o "%s" "%s" -I"%s"',
        cc, output_file, c_file, lua_include
      )
    else
      -- Executable
      cmd = string_format(
        '%s -O2 -o "%s" "%s" -I"%s" -L"%s" -l%s -lm -ldl',
        cc, output_file, c_file, lua_include, lib_dir, lib_name
      )
    end
  else
    return false, "Compilador C não suportado: " .. cc
  end

  io.write("[forja] Executando: " .. cmd .. "\n")
  local ok = os_execute(cmd)
  if not ok then
    return false, "Falha na compilação C. Comando: " .. cmd
  end

  return true
end

------------------------------------------------------------------------
-- build — Pipeline completo: Lua → bytecode → C stub → executável/dll
------------------------------------------------------------------------
---@param bundled_code string  Código Lua empacotado
---@param output_file string   Caminho do executável de saída
---@param options? table       {strip=bool, keep_temp=bool, format=string, target_os=string, module_name=string, cc=string, lua_include=string, lua_lib=string}
---@return boolean ok
---@return string? error_msg
---@return table? info
function compiler.build(bundled_code, output_file, options)
  options = options or {}
  local format = options.format or "exe"
  local target_os = options.target_os or compiler.OS

  -- 1. Trata formatos wrapper (sh, bat) que não precisam de compilação C
  if format == "sh" then
    io.write("[forja] Gerando script wrapper Linux/macOS (.sh)...\n")
    local f, err = io_open(output_file, "w")
    if not f then return false, err end
    f:write("#!/usr/bin/env lua\n")
    f:write(bundled_code)
    f:write("\n")
    f:close()
    if compiler.OS == "unix" then
      os_execute("chmod +x " .. output_file)
    end
    io.write("[forja] Wrapper gerado com sucesso!\n")
    return true, nil, {
      executable = true,
      file = output_file,
      size = #bundled_code,
    }
  elseif format == "bat" then
    io.write("[forja] Gerando script wrapper Windows (.bat)...\n")
    local f, err = io_open(output_file, "w")
    if not f then return false, err end
    f:write("@echo off\n")
    f:write("lua55 -e \"local f=io.open('%~f0','r');f:read('*l');f:read('*l');f:read('*l');assert(load(f:read('*a')))()\" %*\n")
    f:write("exit /b %ERRORLEVEL%\n")
    f:write(bundled_code)
    f:write("\n")
    f:close()
    io.write("[forja] Wrapper gerado com sucesso!\n")
    return true, nil, {
      executable = true,
      file = output_file,
      size = #bundled_code,
    }
  end

  -- Remove extensão se presente para nomes temporários
  local base_name = output_file:match("(.+)%.[^%.]+$") or output_file
  local bytecode_file = base_name .. ".luac"
  local c_file = base_name .. "_stub.c"

  -- Passo 1: Compila para bytecode
  io.write("[forja] Compilando para bytecode...\n")
  local ok, err = compiler.compile_to_bytecode(bundled_code, bytecode_file, {
    strip = options.strip ~= false
  })
  if not ok then
    return false, err
  end

  -- Verifica tamanho do bytecode
  local f = io_open(bytecode_file, "rb")
  local bc_size = 0
  if f then
    bc_size = f:seek("end")
    f:close()
  end
  io.write(string_format("[forja] Bytecode: %d bytes\n", bc_size))

  -- Passo 2: Detecta ferramentas
  io.write("[forja] Detectando ferramentas...\n")
  local tools = compiler.detect_tools()

  -- Se o compilador C não for encontrado e não for explicitado
  local cc = options.cc or tools.cc
  if not cc then
    io.write("[forja] AVISO: Compilador C não encontrado.\n")
    io.write("[forja] Gerando pacote de compilação pronto para o sistema de destino:\n")
    io.write("  - Bytecode: " .. bytecode_file .. "\n")
    
    local module_name = options.module_name or output_file:match("[/\\]?([^/\\]+)%.[^%.]+$") or output_file:match("[/\\]?([^/\\]+)$") or "module"
    module_name = module_name:gsub("%.", "_"):gsub("-", "_")
    
    ok, err = compiler.generate_c_stub(bytecode_file, c_file, {
      format = format,
      module_name = module_name
    })
    
    if ok then
      io.write("  - Stub C:   " .. c_file .. "\n")
      io.write("\nPara compilar manualmente:\n")
      if format == "dll" or format == "so" or format == "dylib" then
        io.write(string_format("  gcc -shared -fPIC -o %s %s -I<lua_include> -L<lua_lib_dir> -llua\n", output_file, c_file))
      else
        io.write(string_format("  gcc -o %s %s -I<lua_include> -L<lua_lib_dir> -llua\n", output_file, c_file))
      end
    end
    
    return true, nil, {
      bytecode_file = bytecode_file,
      bytecode_size = bc_size,
      executable = false,
      c_stub_file = c_file,
    }
  end

  -- Passo 3: Gera stub C
  io.write("[forja] Gerando stub C...\n")
  local module_name = options.module_name or output_file:match("[/\\]?([^/\\]+)%.[^%.]+$") or output_file:match("[/\\]?([^/\\]+)$") or "module"
  module_name = module_name:gsub("%.", "_"):gsub("-", "_")

  ok, err = compiler.generate_c_stub(bytecode_file, c_file, {
    format = format,
    module_name = module_name
  })
  if not ok then
    return false, err
  end

  -- Passo 4: Compila C
  io.write("[forja] Compilando código C nativo...\n")
  ok, err = compiler.compile_c(c_file, output_file, tools, {
    format = format,
    target_os = target_os,
    cc = options.cc,
    lua_include = options.lua_include,
    lua_lib = options.lua_lib,
  })

  -- Limpa arquivos temporários
  if not options.keep_temp then
    os_remove(bytecode_file)
    os_remove(c_file)
    os_remove(base_name .. "_stub.obj")
    os_remove(base_name .. ".obj")
    os_remove(base_name .. ".exp")
    if format ~= "dll" then
      os_remove(base_name .. ".lib")
    end
  end

  if not ok then
    return false, err
  end

  -- Verifica tamanho do resultado final
  f = io_open(output_file, "rb")
  local out_size = 0
  if f then
    out_size = f:seek("end")
    f:close()
  end

  io.write(string_format("[forja] Saída gerada: %s (%d bytes)\n", output_file, out_size))

  return true, nil, {
    bytecode_file = bytecode_file,
    bytecode_size = bc_size,
    executable = true,
    file = output_file,
    size = out_size,
  }
end

return compiler
