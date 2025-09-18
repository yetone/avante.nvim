# Avante.nvim Config.json 修复总结

## 问题描述

用户报告了以下问题：
1. 选择一个模型并重启neovim后，只有provider是对的，上一次使用的模型没有正确读取（变成默认）
2. 除非删除config.json否则没有办法切换至其他供应商的模型
3. edit_file工具也有问题需要修复

## 根本原因分析

### 1. provider_model字段逻辑错误
在原始的`save_last_model`函数中，保存了一个`provider_model`字段：
```lua
local provider_model = provider and provider.model
file:write(vim.json.encode({
  last_model = model_name,
  last_provider = provider_name,
  provider_model = provider_model
}))
```

在`get_last_used_model`函数中，有这样的逻辑：
```lua
if data.provider_model and provider.model and provider.model ~= data.provider_model then
  return provider.model, data.last_provider  -- 返回provider默认模型而不是用户选择的模型！
end
```

这导致当provider的默认模型与保存的provider_model不匹配时，会返回provider的默认模型而不是用户实际选择的模型。

### 2. 过度删除配置文件
当provider无效时，原代码会删除整个配置文件：
```lua
if not provider then
  Utils.warn("Provider " .. data.last_provider .. " is no longer a valid provider")
  os.remove(storage_path)  -- 删除配置文件
  return
end
```

这导致用户无法切换到其他有效的provider。

### 3. edit_file工具的问题
- 重复的路径检查
- 过于详细的curl调试输出
- 错误处理可以改进

## 修复方案

### 1. 简化配置保存逻辑
移除有问题的`provider_model`字段，只保存必要的信息：
```lua
function M.save_last_model(model_name, provider_name)
  -- ...
  file:write(vim.json.encode({
    last_model = model_name,
    last_provider = provider_name
  }))
  -- ...
end
```

### 2. 改进配置读取逻辑
- 更严格的字段验证
- 当provider无效时不删除配置文件，允许用户切换到其他provider
```lua
function M.get_last_used_model(known_providers)
  -- ...
  -- 检查必要字段是否存在且有效
  if not data.last_model or data.last_model == "" or
     not data.last_provider or data.last_provider == "" then
    Utils.warn("Missing required fields in last used model file: " .. storage_path)
    os.rename(storage_path, storage_path .. ".bad")
    return
  end

  -- 检查provider是否仍然有效
  if data.last_provider then
    local provider = known_providers[data.last_provider]
    if not provider then
      Utils.warn("Provider " .. data.last_provider .. " is no longer a valid provider")
      -- 不删除配置文件，只是不使用它
      return
    end
  end

  return data.last_model, data.last_provider
end
```

### 3. 优化edit_file工具
- 移除重复的路径检查
- 使用`--silent`替代`--verbose`减少不必要的输出
- 改进错误消息格式

## 修复效果

经过测试验证，修复后的代码能够：

1. ✅ 正确保存和读取用户选择的模型
2. ✅ 成功在不同provider之间切换
3. ✅ 正确处理无效provider（不会阻止切换到其他provider）
4. ✅ 正确处理损坏的JSON文件
5. ✅ edit_file工具错误处理更加友好

## 测试结果

运行测试脚本`test_config_fix.lua`的结果：
```
=== 测试config.json修复 ===

测试1: 正常保存和读取
✓ 测试1通过: 正确读取了保存的模型

测试2: 切换到不同provider
✓ 测试2通过: 成功切换到claude provider

测试3: 无效provider处理
✓ 测试3通过: 正确处理了无效provider

测试4: 损坏的JSON处理
✓ 测试4通过: 正确处理了损坏的JSON

=== 测试完成 ===
```

## 文件修改清单

1. `lua/avante/config.lua` - 修复模型保存和读取逻辑
2. `lua/avante/llm_tools/edit_file.lua` - 优化edit_file工具
3. `test_config_fix.lua` - 测试脚本（可选）
4. `CONFIG_FIX_SUMMARY.md` - 本文档（可选）

这些修复确保了avante.nvim能够正确处理模型选择和provider切换，提供更好的用户体验。
