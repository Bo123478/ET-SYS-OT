using System.ServiceProcess;

namespace Workbench.Service;

/// <summary>
/// 后台服务入口。
/// 负责设备登记校验、健康检测、传输调度的长期运行宿主。
/// TODO: 后续替换为 Microsoft.Extensions.Hosting 宿主并组装各模块。
/// </summary>
internal static class Program
{
    private static void Main()
    {
        ServiceBase.Run(new WorkbenchService());
    }
}
