using System.Windows;

namespace Workbench.Desktop;

/// <summary>
/// 主工作台窗口。
/// TODO: 后续改为通过 MVVM 视图模型驱动，窗口本身不承载业务逻辑。
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }
}
