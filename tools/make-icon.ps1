param([string]$Out)
Add-Type -AssemblyName System.Drawing

$size = 1024
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

# section
$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$bg = [System.Drawing.Drawing2D.LinearGradientBrush]::new($rect,
    [System.Drawing.Color]::FromArgb(255, 255, 179, 64),
    [System.Drawing.Color]::FromArgb(255, 255, 112, 20), [single]90)
$g.FillRectangle($bg, $rect)
$g.TranslateTransform(-37, -42)
$bg.TranslateTransform(37, 42)

$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)

# section
$p = New-Object System.Drawing.Drawing2D.GraphicsPath
$p.StartFigure()
$p.AddBezier(492, 270, 360, 270, 300, 370, 300, 500)
$p.AddLine(300, 500, 300, 610)
$p.AddBezier(300, 610, 300, 660, 250, 690, 215, 720)
$p.AddLine(215, 720, 215, 760)
$p.AddLine(215, 760, 769, 760)
$p.AddLine(769, 760, 769, 720)
$p.AddBezier(769, 720, 734, 690, 684, 660, 684, 610)
$p.AddLine(684, 610, 684, 500)
$p.AddBezier(684, 500, 684, 370, 624, 270, 492, 270)
$p.CloseFigure()
$g.FillPath($white, $p)

# section
$g.FillEllipse($white, 452, 205, 80, 80)
$g.FillEllipse($white, 432, 782, 120, 120)

# section
$cx = 712; $cy = 330; $r = 150
$ring = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 160, 50))
$g.FillEllipse($bg, $cx - $r - 22, $cy - $r - 22, 2 * ($r + 22), 2 * ($r + 22))
$green = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 52, 199, 89))
$g.FillEllipse($green, $cx - $r, $cy - $r, 2 * $r, 2 * $r)

$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 44)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$pts = [System.Drawing.Point[]]@(
    (New-Object System.Drawing.Point(($cx - 68), ($cy + 4))),
    (New-Object System.Drawing.Point(($cx - 18), ($cy + 56))),
    (New-Object System.Drawing.Point(($cx + 72), ($cy - 52)))
)
$g.DrawLines($pen, $pts)

$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
