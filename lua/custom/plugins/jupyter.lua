-- [[ Jupyter Notebooks ]]
--  jupytext.nvim  -> öffnet .ipynb als normales Python (Zellen mit `# %%`), speichert zurück als .ipynb
--  molten-nvim    -> führt Zellen in einem echten Jupyter-Kernel aus, Output direkt unter der Zelle
--  image.nvim     -> zeigt Plots/Bilder im Terminal an (Kitty-Grafik-Protokoll)
--
-- Benötigt (einmalig installiert):
--  - Python-venv für Neovim, siehe vim.g.python3_host_prog in init.lua
--  - jupytext CLI:  uv tool install jupytext
--  - Kernel:        <venv>/bin/python -m ipykernel install --user --name python3
--    Für ein Uni-Projekt mit eigenem venv: dort `uv pip install ipykernel` und
--    `python -m ipykernel install --user --name <projekt>`, dann mit <leader>ni auswählen
--  - nach dem ersten Installieren einmal :UpdateRemotePlugins und Neovim neu starten

-- Grenzen der aktuellen Zelle (Zellen sind durch `# %%` getrennt)
local function cell_range()
  local first = vim.fn.search('^# %%', 'bcnW')
  local next = vim.fn.search('^# %%', 'nW')
  local start_line = first == 0 and 1 or first + 1
  local end_line = next == 0 and vim.fn.line '$' or next - 1
  return start_line, end_line
end

-- Aktuelle Zelle ausführen und zur nächsten springen (wie Shift+Enter in Jupyter)
local function run_cell()
  local start_line, end_line = cell_range()
  if start_line <= end_line then vim.fn.MoltenEvaluateRange(start_line, end_line) end
  local next = vim.fn.search('^# %%', 'nW')
  if next ~= 0 then vim.api.nvim_win_set_cursor(0, { math.min(next + 1, vim.fn.line '$'), 0 }) end
end

-- Alle Zellen nacheinander ausführen (jede bekommt ihren eigenen Output)
local function run_all_cells()
  local markers = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:match '^# %%' then table.insert(markers, lnum) end
  end
  local last = vim.fn.line '$'
  -- Code vor dem ersten Marker zählt auch als Zelle
  if #markers == 0 or markers[1] > 1 then table.insert(markers, 1, 0) end
  for i, marker in ipairs(markers) do
    local start_line = marker + 1
    local end_line = (markers[i + 1] or last + 1) - 1
    local is_markdown = marker > 0 and vim.fn.getline(marker):match '%[markdown%]'
    if start_line <= end_line and not is_markdown then vim.fn.MoltenEvaluateRange(start_line, end_line) end
  end
end

-- Neue Zelle unter der aktuellen einfügen
local function new_cell(kind)
  local _, end_line = cell_range()
  local marker = kind == 'markdown' and '# %% [markdown]' or '# %%'
  vim.api.nvim_buf_set_lines(0, end_line, end_line, false, { '', marker, '' })
  vim.api.nvim_win_set_cursor(0, { end_line + 3, 0 })
  vim.cmd 'startinsert'
end

-- Leeres .ipynb anlegen und öffnen (jupytext kann keine leere Datei öffnen)
local function new_notebook()
  local path = vim.fn.input('Neues Notebook: ', vim.fn.getcwd() .. '/', 'file')
  if path == '' then return end
  if not path:match '%.ipynb$' then path = path .. '.ipynb' end
  if vim.uv.fs_stat(path) then return vim.notify(path .. ' existiert schon', vim.log.levels.WARN) end
  local notebook = {
    cells = { { cell_type = 'code', execution_count = vim.NIL, metadata = vim.empty_dict(), outputs = {}, source = {} } },
    metadata = {
      kernelspec = { display_name = 'Python 3', language = 'python', name = 'python3' },
      language_info = { name = 'python' },
    },
    nbformat = 4,
    nbformat_minor = 5,
  }
  vim.fn.writefile({ vim.json.encode(notebook) }, path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

return {
  {
    'GCBallesteros/jupytext.nvim',
    -- Muss beim Start geladen sein, damit das Öffnen von .ipynb abgefangen wird
    lazy = false,
    opts = {
      -- `# %%` Zellen, Magics wie `%timeit` werden als Kommentar gespeichert,
      -- dadurch ist der Buffer gültiges Python und LSP/ruff funktionieren
      style = 'percent',
      output_extension = 'auto',
      force_ft = nil,
    },
  },

  {
    '3rd/image.nvim',
    opts = {
      backend = 'kitty',
      -- nutzt das `magick` Programm statt der Lua-Rock, keine extra Installation nötig
      processor = 'magick_cli',
      integrations = {
        markdown = { enabled = false },
      },
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = math.huge,
      max_width_window_percentage = math.huge,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', 'blink-cmp-menu', 'blink-cmp-documentation', '' },
    },
  },

  {
    'benlubas/molten-nvim',
    version = '^1.0.0',
    dependencies = { '3rd/image.nvim' },
    build = ':UpdateRemotePlugins',
    init = function()
      vim.g.molten_image_provider = 'image.nvim'
      vim.g.molten_output_win_max_height = 20
      -- Output nicht automatisch als Fenster öffnen, sondern als Text unter der Zelle
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_wrap_output = true

      -- Molten legt hier die Kernel-Verbindungsdatei ab, erstellt den Ordner aber nicht selbst
      -- (normalerweise macht das die jupyter CLI, die wir nicht brauchen)
      vim.fn.mkdir(vim.fn.expand '~/.local/share/jupyter/runtime', 'p')
    end,
    config = function()
      -- [[ Notebook-Shortcuts unter <leader>n ]]

      -- Kernel starten (fragt welcher, z.B. python3 oder ein Projekt-Kernel)
      vim.keymap.set('n', '<leader>ni', '<cmd>MoltenInit<CR>', { desc = '[N]otebook [I]nit Kernel' })

      -- Aktuelle Zelle ausführen und zur nächsten springen
      vim.keymap.set('n', '<leader>nr', run_cell, { desc = '[N]otebook [R]un Cell' })

      -- Markierten Code ausführen
      vim.keymap.set('x', '<leader>nr', ':<C-u>MoltenEvaluateVisual<CR>gv<Esc>', { silent = true, desc = '[N]otebook [R]un Selection' })

      -- Nur die aktuelle Zeile ausführen
      vim.keymap.set('n', '<leader>nl', '<cmd>MoltenEvaluateLine<CR>', { desc = '[N]otebook Run [L]ine' })

      -- Alle Zellen von oben nach unten ausführen
      vim.keymap.set('n', '<leader>na', run_all_cells, { desc = '[N]otebook Run [A]ll Cells' })

      -- Output der Zelle in einem Fenster öffnen (zum Scrollen/Kopieren), q zum Schließen
      vim.keymap.set('n', '<leader>no', '<cmd>noautocmd MoltenEnterOutput<CR>', { desc = '[N]otebook [O]pen Output' })

      -- Output-Fenster verstecken
      vim.keymap.set('n', '<leader>nh', '<cmd>MoltenHideOutput<CR>', { desc = '[N]otebook [H]ide Output' })

      -- Output der Zelle unter dem Cursor löschen
      vim.keymap.set('n', '<leader>nd', '<cmd>MoltenDelete<CR>', { desc = '[N]otebook [D]elete Cell Output' })

      -- Laufende Ausführung abbrechen (z.B. Endlosschleife)
      vim.keymap.set('n', '<leader>nx', '<cmd>MoltenInterrupt<CR>', { desc = '[N]otebook Interrupt (e[X]it)' })

      -- Kernel neu starten, alle Variablen sind danach weg
      vim.keymap.set('n', '<leader>nk', '<cmd>MoltenRestart!<CR>', { desc = '[N]otebook Restart [K]ernel' })

      -- Neue Code-Zelle unter der aktuellen
      vim.keymap.set('n', '<leader>nc', function() new_cell 'code' end, { desc = '[N]otebook New [C]ode Cell' })

      -- Neue Markdown-Zelle unter der aktuellen (Text mit `# ` am Zeilenanfang)
      vim.keymap.set('n', '<leader>nm', function() new_cell 'markdown' end, { desc = '[N]otebook New [M]arkdown Cell' })

      -- Neues leeres .ipynb anlegen
      vim.keymap.set('n', '<leader>nn', new_notebook, { desc = '[N]otebook [N]ew File' })

      -- Outputs ins .ipynb schreiben (passiert beim Speichern auch automatisch)
      vim.keymap.set('n', '<leader>ne', '<cmd>MoltenExportOutput!<CR>', { desc = '[N]otebook [E]xport Outputs' })

      -- Zwischen Zellen springen
      vim.keymap.set('n', ']j', function() vim.fn.search('^# %%', 'W') end, { desc = 'Next Jupyter cell' })
      vim.keymap.set('n', '[j', function() vim.fn.search('^# %%', 'bW') end, { desc = 'Previous Jupyter cell' })

      -- Beim Öffnen eines .ipynb: Kernel aus den Notebook-Metadaten starten und alte Outputs laden
      local function init_notebook(event)
        -- Pro Buffer nur einmal, sonst startet jedes BufEnter einen neuen Kernel
        if vim.b[event.buf].molten_auto_init then return end
        vim.b[event.buf].molten_auto_init = true
        vim.schedule(function()
          local kernels = vim.fn.MoltenAvailableKernels()
          local ok, kernel_name = pcall(function()
            local file = assert(io.open(event.file, 'r'))
            local metadata = vim.json.decode(file:read 'a').metadata
            file:close()
            return metadata.kernelspec.name
          end)
          if not ok or not vim.tbl_contains(kernels, kernel_name) then kernel_name = 'python3' end
          if vim.tbl_contains(kernels, kernel_name) then
            vim.cmd(('MoltenInit %s'):format(kernel_name))
            vim.cmd 'MoltenImportOutput'
          end
        end)
      end

      local group = vim.api.nvim_create_augroup('molten-notebook', { clear = true })
      vim.api.nvim_create_autocmd('BufAdd', { group = group, pattern = '*.ipynb', callback = init_notebook })
      -- BufAdd feuert nicht für Dateien, die direkt beim Start (`nvim foo.ipynb`) geöffnet werden
      vim.api.nvim_create_autocmd('BufEnter', {
        group = group,
        pattern = '*.ipynb',
        callback = function(event)
          if vim.v.vim_did_enter ~= 1 then init_notebook(event) end
        end,
      })

      -- Beim Speichern die Outputs mit ins .ipynb schreiben (z.B. für die Abgabe)
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = group,
        pattern = '*.ipynb',
        callback = function()
          if require('molten.status').initialized() == 'Molten' then vim.cmd 'MoltenExportOutput!' end
        end,
      })
    end,
  },
}
