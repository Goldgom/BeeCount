/// AI 工具公共导出入口。
///
/// 保留独立文件便于未来增加预算、报表等工具，同时让上层只依赖稳定协议。
export 'bookkeeping_ai_tool.dart'
    show BookkeepingAiTool, BookkeepingToolResult, DefaultBookkeepingAiTool;
