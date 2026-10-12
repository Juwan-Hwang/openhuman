/// Human-facing names for the tool runtime.
///
/// The runtime works in JSON Schema: tools and parameters arrive with
/// whatever identifiers the agent chose, and descriptions in English.
/// Shown raw, that reads as a developer console rather than as part of
/// the product. These tables translate the common cases. Anything
/// unlisted falls through to its original name, which is always better
/// than a wrong guess.
library;

/// Parameter names that show up across most agents.
///
/// Keyed by the schema name. Values are the label a reader sees.
const Map<String, String> parameterLabels = {
  'path': '路径',
  'file_path': '文件路径',
  'filepath': '文件路径',
  'filename': '文件名',
  'file_name': '文件名',
  'dir': '目录',
  'directory': '目录',
  'folder': '目录',
  'cwd': '工作目录',
  'command': '命令',
  'cmd': '命令',
  'args': '参数',
  'arguments': '参数',
  'query': '查询内容',
  'search': '搜索内容',
  'keyword': '关键词',
  'keywords': '关键词',
  'pattern': '匹配模式',
  'regex': '正则表达式',
  'url': '网址',
  'uri': '网址',
  'link': '链接',
  'text': '文本',
  'content': '内容',
  'body': '内容',
  'message': '消息',
  'prompt': '提示词',
  'input': '输入',
  'output': '输出',
  'code': '代码',
  'source': '源码',
  'language': '语言',
  'lang': '语言',
  'name': '名称',
  'title': '标题',
  'label': '标签',
  'id': 'ID',
  'key': '键',
  'value': '值',
  'type': '类型',
  'mode': '模式',
  'format': '格式',
  'encoding': '编码',
  'limit': '数量上限',
  'max_results': '最多结果数',
  'max_tokens': '最大长度',
  'max_length': '最大长度',
  'count': '数量',
  'offset': '偏移量',
  'page': '页码',
  'timeout': '超时（秒）',
  'dry_run': '仅预览不执行',
  'force': '强制执行',
  'recursive': '包含子目录',
  'verbose': '显示详细信息',
  'overwrite': '覆盖已有内容',
  'enabled': '启用',
  'include': '包含',
  'exclude': '排除',
  'filter': '过滤条件',
  'sort': '排序',
  'order': '排序',
  'start': '起始',
  'end': '结束',
  'from': '起始',
  'to': '目标',
  'target': '目标',
  'destination': '目标位置',
  'host': '主机',
  'port': '端口',
  'user': '用户',
  'username': '用户名',
  'password': '密码',
  'token': '令牌',
  'email': '邮箱',
  'phone': '电话',
  'date': '日期',
  'time': '时间',
};

/// Tool categories, inferred from the tool name.
///
/// Used only for an icon, so a miss costs nothing.
const Map<String, String> toolCategories = {
  'read': '读取',
  'write': '写入',
  'edit': '编辑',
  'create': '创建',
  'delete': '删除',
  'list': '查看',
  'search': '搜索',
  'grep': '搜索',
  'run': '运行',
  'exec': '运行',
  'bash': '终端',
  'shell': '终端',
  'terminal': '终端',
  'web': '网络',
  'fetch': '网络',
  'http': '网络',
  'browse': '网络',
  'image': '图像',
  'send': '发送',
  'notify': '通知',
  'memory': '记忆',
};

/// Invocation status, as words.
String statusLabel(String status) => switch (status) {
      'success' => '已完成',
      'error' => '出错了',
      'timeout' => '已超时',
      'pending' => '执行中',
      'running' => '执行中',
      _ => status,
    };

/// Schema type, as a word a reader would use.
String typeLabel(String type) => switch (type) {
      'string' => '文本',
      'integer' || 'number' => '数字',
      'boolean' => '开关',
      'array' => '列表',
      'object' => '对象',
      _ => type,
    };

/// A parameter's display name.
///
/// Falls back to the schema name when there is no translation, since
/// showing the real name is what lets someone connect this form to the
/// agent's documentation.
String parameterLabel(String schemaName) =>
    parameterLabels[schemaName.toLowerCase()] ?? schemaName;

/// A tool's display name, taken from its schema title when present.
String toolLabel(Map<String, dynamic> capability) {
  final meta = capability;
  final name = (meta['name'] ?? meta['tool'] ?? meta['id'] ?? '').toString();
  if (name.isEmpty) return '未命名工具';
  return name;
}

/// A rough category for the icon, from keywords in the tool name.
String toolCategory(String toolName) {
  final lower = toolName.toLowerCase();
  for (final entry in toolCategories.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }
  return '工具';
}
