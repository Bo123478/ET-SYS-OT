using System.ServiceProcess;

namespace Workbench.Service;

/// <summary>
/// Windows 后台服务宿主。
/// TODO: 接入模块组装、任务调度与命名管道 IPC 监听。
/// </summary>
public sealed class WorkbenchService : ServiceBase
{
    public WorkbenchService()
    {
        ServiceName = "WorkbenchService";
        CanStop = true;
        CanPauseAndContinue = false;
        AutoLog = true;
    }

    protected override void OnStart(string[] args)
    {
        // TODO: 启动 IPC 监听、健康检测定时器和传输队列。
    }

    protected override void OnStop()
    {
        // TODO: 停止定时器、取消进行中的任务、释放资源。
    }
}
