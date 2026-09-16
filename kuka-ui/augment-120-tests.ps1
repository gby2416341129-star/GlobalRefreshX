$ErrorActionPreference = 'Stop'
$testPath = 'tests/KukaManager.SmokeTests/Program.cs'
$test = Get-Content $testPath -Raw -Encoding UTF8

if ($test -notmatch '(?m)^using System\.Windows\.Controls;') {
    $test = $test.Replace("using System.Windows;`r`n", "using System.Windows;`r`nusing System.Windows.Controls;`r`n")
}

$marker = 'modern input, picker and grid templates instantiate and layout'
if ($test -notmatch [Regex]::Escape($marker)) {
    $anchor = '        Check(app.Resources.MergedDictionaries.Count > 0, "modern WPF theme parses and loads");'
    if (-not $test.Contains($anchor)) { throw 'Theme test anchor missing' }

    $extra = @'

        var controlsHost = new StackPanel { Width = 900, Height = 600 };
        var combo = new ComboBox { Width = 240 };
        combo.Items.Add("数学");
        combo.Items.Add("Python");
        combo.SelectedIndex = 0;
        var datePicker = new DatePicker { Width = 240, SelectedDate = DateTime.Today };
        var calendar = new Calendar();
        var grid = new DataGrid { Width = 720, Height = 180 };
        controlsHost.Children.Add(combo);
        controlsHost.Children.Add(datePicker);
        controlsHost.Children.Add(calendar);
        controlsHost.Children.Add(grid);
        controlsHost.Measure(new Size(900, 600));
        controlsHost.Arrange(new Rect(0, 0, 900, 600));
        combo.ApplyTemplate();
        datePicker.ApplyTemplate();
        calendar.ApplyTemplate();
        grid.ApplyTemplate();
        controlsHost.UpdateLayout();
        Check(combo.Template is not null && datePicker.Template is not null && grid.Template is not null,
            "modern input, picker and grid templates instantiate and layout");
'@
    $test = $test.Replace($anchor, $anchor + $extra)
}

[IO.File]::WriteAllText($testPath, $test, [Text.UTF8Encoding]::new($false))
