# Builds the Connect IQ Store setup image (store-screenshots\01-setup.png),
# the cover (store-art\cover-500.png) and the hero (store-art\hero-1440x720.png).
# Inputs: store-art\setup-watch.png and store-art\pair-watch.png (simulator
# captures of Get PC app and Pair with PC),
# store-art\pair-pc.png (the PC pairing window) and the store screenshots.
# Run from the project folder: powershell -File tools\make-store-art.ps1
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$art = Join-Path $root 'store-art'
$shots = Join-Path $root 'store-screenshots'

$white  = [System.Drawing.Color]::White
$accent = [System.Drawing.Color]::FromArgb(255, 255, 106, 19)
$grey   = [System.Drawing.Color]::FromArgb(255, 170, 170, 170)
$bg     = [System.Drawing.Color]::FromArgb(255, 14, 14, 14)
$font   = 'Segoe UI'

function New-Canvas($w, $h) {
    $b = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.Clear($bg)
    return @($b, $g)
}

function Text($g, $s, $size, $style, $color, $x, $y, $w, $align) {
    $f = New-Object System.Drawing.Font $font, $size, $style, ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = $align
    $g.DrawString($s, $f, (New-Object System.Drawing.SolidBrush $color), (New-Object System.Drawing.RectangleF $x, $y, $w, 400), $fmt)
}

# Instinct-style watch face showing a 176x176 capture, pixels kept sharp:
# the round main display plus the round subscreen window at its top right
# (x 113-175, y 0-62 in screen pixels).
function Face-Path($cx, $cy, $d, $grow) {
    $k = $d / 176.0
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse($cx - $d/2 - $grow, $cy - $d/2 - $grow, $d + 2*$grow, $d + 2*$grow)
    $sx = $cx - $d/2 + 113 * $k; $sy = $cy - $d/2; $sd = 62 * $k
    $p.AddEllipse($sx - $grow, $sy - $grow, $sd + 2*$grow, $sd + 2*$grow)
    $p.FillMode = 'Winding'
    return $p
}
function Draw-Watch($g, $path, $cx, $cy, $d) {
    $img = [System.Drawing.Image]::FromFile($path)
    $g.FillPath((New-Object System.Drawing.SolidBrush $accent), (Face-Path $cx $cy $d 13))
    $g.FillPath((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 48, 48, 48))), (Face-Path $cx $cy $d 8))
    $state = $g.Save()
    $g.SetClip((Face-Path $cx $cy $d 0))
    $g.InterpolationMode = 'NearestNeighbor'
    $g.PixelOffsetMode = 'Half'
    $g.DrawImage($img, $cx - $d/2, $cy - $d/2, $d, $d)
    $g.Restore($state)
    $img.Dispose()
}

# Largest image in an .ico file. Big frames are stored as PNG, which
# System.Drawing.Icon decodes badly, so read the entry bytes directly.
function Load-IcoImage($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    $best = -1; $bestW = 0
    for ($i = 0; $i -lt $count; $i++) {
        $o = 6 + 16 * $i
        $w = $bytes[$o]; if ($w -eq 0) { $w = 256 }
        if ($w -gt $bestW) { $bestW = $w; $best = $o }
    }
    $size = [BitConverter]::ToInt32($bytes, $best + 8)
    $off = [BitConverter]::ToInt32($bytes, $best + 12)
    $ms = New-Object System.IO.MemoryStream (, $bytes[$off..($off + $size - 1)])
    if ($bytes[$off] -eq 0x89) { return [System.Drawing.Image]::FromStream($ms) }
    return (New-Object System.Drawing.Icon $path, $bestW, $bestW).ToBitmap()
}

# Numbered step badge.
function Badge($g, $n, $x, $y) {
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $accent), $x, $y, 46, 46)
    Text $g "$n" 28 ([System.Drawing.FontStyle]::Bold) $white $x ($y + 3) 46 ([System.Drawing.StringAlignment]::Center)
}

# ---------- setup image ----------
$c = New-Canvas 1440 720; $b = $c[0]; $g = $c[1]
$bold = [System.Drawing.FontStyle]::Bold
$reg = [System.Drawing.FontStyle]::Regular
$center = [System.Drawing.StringAlignment]::Center
Text $g 'Set up in 3 steps' 52 $bold $white 0 36 1440 $center
Text $g 'Wrist Remote needs its free app on the Windows 10 / 11 PC you want to control.' 24 $reg $grey 0 108 1440 $center

$colW = 440; $xs = @(40, 500, 960)
for ($i = 0; $i -lt 3; $i++) { Badge $g ($i + 1) ($xs[$i] + $colW/2 - 23) 170 }
Text $g "Get the PC app" 30 $bold $white $xs[0] 232 $colW $center
Text $g "Open Get PC app on the watch and press`nSTART: the download link pops up on`nyour phone. Run WristRemote.exe." 22 $reg $grey $xs[0] 278 $colW $center
Text $g "Open Pair with PC" 30 $bold $white $xs[1] 232 $colW $center
Text $g "on the watch to see your code." 22 $reg $grey $xs[1] 278 $colW $center
Text $g "Type the code on the PC" 30 $bold $white $xs[2] 232 $colW $center
Text $g "then press START on the watch.`nA tick means it is connected." 22 $reg $grey $xs[2] 278 $colW $center

# Step 1: the watch's Get PC app screen.
Draw-Watch $g (Join-Path $art 'setup-watch.png') ($xs[0] + $colW/2) 530 230
# Step 2: the watch.
Draw-Watch $g (Join-Path $art 'pair-watch.png') ($xs[1] + $colW/2) 530 230
# Step 3: the PC pairing window.
$pc = [System.Drawing.Image]::FromFile((Join-Path $art 'pair-pc.png'))
$pw = $colW - 10; $ph = [int]($pc.Height * $pw / $pc.Width)
$g.InterpolationMode = 'HighQualityBicubic'
$g.DrawImage($pc, $xs[2] + 5, 530 - $ph/2, $pw, $ph)
$pc.Dispose()
$b.Save((Join-Path $shots '01-setup.png')); $g.Dispose(); $b.Dispose()

# ---------- app mark: Instinct-shaped face with remote arrows ----------
# Drawn at any size; $aa $false keeps to flat colours (for the 64-colour icon).
function Draw-Mark($g, $x, $y, $s, $bgCol, $faceCol, $ringCol, $fgCol) {
    # $s = width of the square the mark fills. Main face is 70% of it,
    # the subscreen circle sits at its top right like on the Instinct.
    $d = $s * 0.66; $cx = $x + $s * 0.46; $cy = $y + $s * 0.54
    $sd = $d * 62 / 176; $sx = $cx - $d/2 + $d * 113 / 176; $sy = $cy - $d/2
    $ring = $s * 0.045
    $br = New-Object System.Drawing.SolidBrush $ringCol
    $g.FillEllipse($br, $cx - $d/2 - $ring, $cy - $d/2 - $ring, $d + 2*$ring, $d + 2*$ring)
    $g.FillEllipse($br, $sx - $ring, $sy - $ring, $sd + 2*$ring, $sd + 2*$ring)
    $fb = New-Object System.Drawing.SolidBrush $faceCol
    $g.FillEllipse($fb, $cx - $d/2, $cy - $d/2, $d, $d)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $fgCol), $sx, $sy, $sd, $sd)
    # Subscreen: a small "signal" dot.
    $dot = $sd * 0.3
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $bgCol), $sx + $sd/2 - $dot/2, $sy + $sd/2 - $dot/2, $dot, $dot)
    # Remote arrows: back and next.
    $a = $d * 0.17; $gap = $d * 0.06; $ay = $cy + $d * 0.04
    $fg = New-Object System.Drawing.SolidBrush $fgCol
    $g.FillPolygon($fg, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ($cx - $gap - 1.6*$a), $ay),
        (New-Object System.Drawing.PointF ($cx - $gap), ($ay - $a)),
        (New-Object System.Drawing.PointF ($cx - $gap), ($ay + $a))))
    $g.FillPolygon($fg, [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF ($cx + $gap + 1.6*$a), $ay),
        (New-Object System.Drawing.PointF ($cx + $gap), ($ay - $a)),
        (New-Object System.Drawing.PointF ($cx + $gap), ($ay + $a))))
}

# Writes a 24-bit bitmap as an 8-bit indexed PNG using the 64-colour
# palette (channels 00, 55, AA, FF); each pixel takes the nearest colour.
function Save-Indexed64($src, $path) {
    $w = $src.Width; $h = $src.Height
    $dst = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format8bppIndexed)
    $pal = $dst.Palette
    $lv = @(0, 85, 170, 255)
    for ($i = 0; $i -lt 256; $i++) {
        if ($i -lt 64) { $pal.Entries[$i] = [System.Drawing.Color]::FromArgb(255, $lv[[int][math]::Floor($i / 16)], $lv[[int][math]::Floor($i / 4) % 4], $lv[$i % 4]) }
        else { $pal.Entries[$i] = [System.Drawing.Color]::Black }
    }
    $dst.Palette = $pal
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $data = $dst.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $dst.PixelFormat)
    $bytes = New-Object byte[] ($data.Stride * $h)
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $c = $src.GetPixel($x, $y)
            $q = { param($v) [int][math]::Round($v / 85.0) }
            $bytes[$y * $data.Stride + $x] = [byte](16 * (& $q $c.R) + 4 * (& $q $c.G) + (& $q $c.B))
        }
    }
    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
    $dst.UnlockBits($data)
    $dst.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
}

# Device store icons, 128x128. Colours come from Garmin's 64-colour palette
# (each channel 00, 55, AA or FF) so the 64-colour one stays exact.
$pOrange = [System.Drawing.Color]::FromArgb(255, 255, 85, 0)
$pBlack  = [System.Drawing.Color]::FromArgb(255, 0, 0, 0)
$pWhite  = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$pGrey   = [System.Drawing.Color]::FromArgb(255, 85, 85, 85)
foreach ($v in @(@{ name = 'icon-64color-128.png'; aa = $false }, @{ name = 'icon-24bit-128.png'; aa = $true })) {
    $b = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = if ($v.aa) { 'AntiAlias' } else { 'None' }
    $g.Clear($pOrange)
    Draw-Mark $g 6 4 120 $pOrange $pBlack $pGrey $pWhite
    if ($v.aa) {
        $b.Save((Join-Path $art $v.name), [System.Drawing.Imaging.ImageFormat]::Png)
    } else {
        # 8-bit indexed PNG with Garmin's 64-colour palette (Garmin checks
        # that the two device icons differ in pixel format).
        Save-Indexed64 $b (Join-Path $art $v.name)
    }
    $g.Dispose(); $b.Dispose()
}

# ---------- cover 500x500 ----------
# Watch on the left, PC on the right, an arc between them, title below.
$c = New-Canvas 500 500; $b = $c[0]; $g = $c[1]
$top = [System.Drawing.Color]::FromArgb(255, 34, 34, 34)
$grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 0, 500), $top, $bg
$g.FillRectangle($grad, 0, 0, 500, 500)
# Monitor with a slide on it.
$mx = 282; $my = 104; $mw = 186; $mh = 124
$g.FillRectangle((New-Object System.Drawing.SolidBrush $white), $mx, $my, $mw, $mh)
$g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 28, 28, 28))), $mx + 7, $my + 7, $mw - 14, $mh - 14)
$g.FillRectangle((New-Object System.Drawing.SolidBrush $white), $mx + $mw/2 - 10, $my + $mh, 20, 20)
$g.FillRectangle((New-Object System.Drawing.SolidBrush $white), $mx + $mw/2 - 36, $my + $mh + 18, 72, 8)
# The slide: title bar, bullet lines, page number.
$sl = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 236, 236, 236))
$g.FillRectangle($sl, $mx + 20, $my + 18, $mw - 40, $mh - 36)
$g.FillRectangle((New-Object System.Drawing.SolidBrush $accent), $mx + 32, $my + 30, 76, 10)
$ln = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 150, 150, 150))
foreach ($k in 0..2) { $g.FillRectangle($ln, $mx + 32, $my + 50 + $k * 13, 104 - $k * 20, 6) }
Text $g '5 / 20' 14 $bold ([System.Drawing.Color]::FromArgb(255, 90, 90, 90)) ($mx + 20) ($my + $mh - 40) ($mw - 52) ([System.Drawing.StringAlignment]::Far)
# Watch showing the Slides screen.
Draw-Watch $g (Join-Path $shots '03-slides.png') 140 190 172
# Signal arc from the watch's subscreen to the screen, with a dashed line.
$pen = New-Object System.Drawing.Pen $accent, 5
$pen.DashStyle = 'Dash'
$pen.StartCap = 'Round'; $pen.EndCap = 'ArrowAnchor'
$g.DrawBezier($pen, 214, 96, 236, 46, 290, 40, 318, 90)
# Title and tagline.
Text $g 'Wrist Remote' 50 $bold $white 0 330 500 $center
Text $g 'Your watch is the remote' 24 $reg $grey 0 398 500 $center
Text $g 'for your Windows PC' 24 $reg $grey 0 430 500 $center
$b.Save((Join-Path $art 'cover-500.png')); $g.Dispose(); $b.Dispose()

# ---------- hero 1440x720 ----------
$c = New-Canvas 1440 720; $b = $c[0]; $g = $c[1]
Text $g 'Wrist Remote' 72 $bold $white 80 200 700 ([System.Drawing.StringAlignment]::Near)
Text $g "Control your Windows PC from your Instinct.`nTurn slides, play music, mute meetings,`nlock or sleep the PC." 30 $reg $grey 84 300 700 ([System.Drawing.StringAlignment]::Near)
Draw-Watch $g (Join-Path $shots '03-slides.png') 900 360 300
Draw-Watch $g (Join-Path $shots '05-meeting.png') 1230 360 220
$b.Save((Join-Path $art 'hero-1440x720.png')); $g.Dispose(); $b.Dispose()
'done'
