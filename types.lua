--- @since 26.9.1
--- Where Yazi 26.9.1 and `types.yazi` disagree, in one place. Nothing requires
--- this file at run time; `lua-language-server` reads it with the rest of the
--- workspace, and Yazi never loads it.
---
--- Each difference is declared by inheriting from Yazi's class rather than
--- re-opening it, so a value taken off `cx` is cast where it arrives.
--- `annotate-supaline` says why. A newer Yazi is a reason to re-measure these
--- and correct them here, never to work around them at a call site.
---
--- Four fields read off a file, measured on 26.9.1 (Homebrew 2026-09-01) with
--- a probe linemode logging the file it was handed:
---
---     file.idx         number, 1
---     file.in_current  boolean, true
---     cha.perm         function; `cha:perm()` returned "drwxr-xr-x"
---     url.spec         userdata; `spec.is_virtual` false for a local file

--- `perm` is a method here and a `string?` upstream.
---@class supaline.Cha : Cha
---@field perm fun(self: self): string?

--- The exposed complement of Yazi's internal `AuthKind::is_local()`. Upstream
--- declares `is_regular`, the spelling CI refuses, and not this.
---@class supaline.UrlSpec
---@field is_virtual boolean

---@class supaline.Url : Url
---@field spec supaline.UrlSpec

--- What a `render` is handed.
---@class supaline.File : fs__File
---@field idx integer the row's 1-based position in its own folder
---@field in_current boolean whether the row's folder is the tab's current one
---@field cha supaline.Cha
---@field url supaline.Url

--- Yazi's folder, with its listing narrowed to the file above. A list rather
--- than `fs__Files`: `#files` and `files[i]` are all that is done with one, and
--- both hold for Yazi's userdata and for the table the harness builds.
---@class supaline.Folder : tab__Folder
---@field files supaline.File[]

--- `tab::Tab` answers `history(url)` with the folder it has already listed for
--- that URL, or nil for one it never opened. `tab__Tab` is `(exact)`, so the
--- harness cannot declare this for the plugin.
---@class supaline.Tab : tab__Tab
---@field history fun(self: self, url: Url): supaline.Folder?

--- `raw()` answers with the style as a plain table: `fg` and `bg` as strings,
--- each attribute under the theme's key, nothing for a key nobody set. Yazi's
--- own `entity.lua` reads it, since v25.12.29; `colour_spec.lua` pins the stub
--- against the run in `yazi-platform-traps/references/probes.md`.
---@class supaline.Style : ui.Style
---@field raw fun(self: self): supaline.StyleTable

--- One of `Linemode._children`, read off 26.9.1's `linemode.lua`: what
--- `redraw` calls at `[1]` -- a method's name for Yazi's own two, a function
--- for each child `children_add` added -- beside the id it returned and its
--- `order`. `types.yazi` declares no `Linemode` at all, so there is no class
--- of Yazi's to inherit from; `stub_spec.lua` pins the stub's port of the
--- two methods that fill it.
---@class supaline.LinemodeChild
---@field [1] string|function|table
---@field id integer
---@field order integer

--- `Line:truncate`, which 26.9.1 has and `test/stub_spec.lua` pins. The
--- two options are the ones this plugin passes, not all 26.9.1 accepts.
---@class supaline.Line : ui.Line
---@field truncate fun(self: self, opts: { max: integer, ellipsis: string? }): supaline.Line

return {}
