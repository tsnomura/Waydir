Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationCore

function Get-FontGlyphTypeface([string]$Path) {
  foreach ($suffix in @('', '#0', '#1')) {
    try {
      return New-Object System.Windows.Media.GlyphTypeface((New-Object System.Uri($Path + $suffix)))
    } catch {}
  }
  return $null
}

function Test-FontHasChars($GlyphTypeface, [string]$Chars) {
  if ($null -eq $GlyphTypeface) { return $false }
  foreach ($ch in $Chars.ToCharArray()) {
    $idx = 0
    $has = $GlyphTypeface.CharacterToGlyphMap.TryGetValue([int][char]$ch, [ref]$idx)
    if (-not $has -or $idx -eq 0) { return $false }
  }
  return $true
}

# Ordered content blocks for Quick Look's paged preview, picked per-font from
# what it actually has glyphs for (not just assumed from the extension) — a
# font with Japanese glyphs gets that sample as its first page, ahead of the
# Latin ones; a font without it never shows a blank/tofu page for content it
# can't render. Falls back to the Latin blocks if detection finds nothing at
# all (e.g. a script GlyphTypeface can't identify), so there's always at
# least one page.
function Get-FontBlocks([string]$FontPath) {
  $gt = Get-FontGlyphTypeface $FontPath
  $hasLatin = Test-FontHasChars $gt 'Ag'
  $hasJapanese = Test-FontHasChars $gt 'あ字'

  $latinBlocks = @(
    @{ Text = "ABCDEFGHIJKLM`nNOPQRSTUVWXYZ"; Size = 38 },
    @{ Text = "abcdefghijklm`nnopqrstuvwxyz"; Size = 38 },
    @{ Text = "0123456789`n!?@#$%&*()+="; Size = 38 },
    @{ Text = "The quick brown fox`njumps over the lazy dog"; Size = 38 }
  )
  $japaneseBlock = @{
    Text = "これは、フォントの見本です。`n平仮名、片仮名、漢字を`nいっしょにプレビューします。"
    Size = 32
  }

  $blocks = @()
  if ($hasJapanese) { $blocks += $japaneseBlock }
  if ($hasLatin) { $blocks += $latinBlocks }
  if ($blocks.Count -eq 0) { $blocks += $latinBlocks }

  return ,$blocks
}

# The grid thumbnail's glyphs — same detection and the same Japanese-first
# priority as Get-FontBlocks, so a font that can't actually render "Ag"
# doesn't show it as a tile full of tofu, and a font with both scripts
# thumbnails the same script its preview opens on. Two characters even for
# the Japanese case (not just one): CharacterToGlyphMap only proves a
# codepoint maps to *some* glyph ID, not that the glyph has a visible
# outline — a decorative font can map a character to an intentionally blank
# placeholder glyph, which this can't detect. Two characters means one
# being blank doesn't necessarily blank the whole thumbnail.
function Get-ThumbnailSample([string]$FontPath) {
  $gt = Get-FontGlyphTypeface $FontPath
  if (Test-FontHasChars $gt 'あ字') { return 'あ字' }
  if (Test-FontHasChars $gt 'Ag') { return 'Ag' }
  if (Test-FontHasChars $gt '가') { return '가' }

  return 'Ag'
}
