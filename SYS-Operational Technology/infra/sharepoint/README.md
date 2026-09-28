# SharePoint 文档库配置（S6 阶段待建）

本目录将存放 PnP PowerShell 脚本，用于创建和配置文档库。**当前为空占位，尚未开发。**

## 职责范围

**仅负责大文件存储层**。业务台账全部位于 Dataverse，不在 SharePoint 建列表。

| 文档库 | Phase | 用途 |
|---|---|---|
| `IssueEvidence` | 1 | 现场图片、屏幕截图等证据 |
| `LogPackages` | 1 | 日志包 zip |
| `TestEvidence` | 2 | 测试证据与报告 |
| `ReleasePackages` | 2 | 发布包 |
| `UserManuals` | 2 | 用户手册 |
| `Runbooks` | 2 | 运维手册 |

## 为什么大文件不放 Dataverse

| 限制项 | 上限 | 影响 |
|---|---|---|
| 文件列 | 131,072 KB（约 131 MB） | 日志包常超过此值 |
| 图片列 | 30,720 KB（约 30 MB） | 且图片会被自动转为 .jpg 并裁切缩略图至 144×144 |
| 单解决方案 | 约 95 MB | 与业务数据无关，但同样需注意 |

以上文件列与图片列的上限**在创建时设定，保存后不可更改**。因此大文件从一开始就走 SharePoint，不在 Dataverse 内做容量试探。

## 文件夹结构

```text
IssueEvidence/
└─ {yyyy}/
   └─ {IssueID}/            例：INC-2026-000123/
      ├─ 现场图片/
      └─ 屏幕截图/

LogPackages/
└─ {yyyy}/
   └─ {IssueID}/
```

## 元数据要求

文档库中的每个文件必须携带以下元数据（对应设计稿 §12.3）：

| 字段 | 说明 |
|---|---|
| Issue ID | 关联的问题编号 |
| Application ID | 关联的应用编号 |
| Version | 相关版本号 |
| 权限分类 | 用于控制访问范围 |
| 上传人 | 上传者 |
| 上传时间 | — |
| 图片类型 | 仅证据库需要，取值见 `docs/data-dictionary.md` |

## 图片类型建议取值

设备全景、控制面板、报警画面、软件界面、硬件连接、处理前、处理后。

## 注意

- 文档库权限按系统、区域、敏感级别分类控制（设计稿 §16.1）。
- 日志包与证据图片属于敏感数据，需遵循 `docs/data-dictionary.md` 中定义的保留周期与脱敏规则。
- **SPO 站点地址与库名通过环境变量注入**（`SharePointSiteRootUrl`、`EvidenceLibraryName`、`LogPackageLibraryName`），脚本中不得硬编码。
