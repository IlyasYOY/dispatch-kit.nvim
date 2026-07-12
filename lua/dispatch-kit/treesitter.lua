local M = {}

local function notify_missing(language)
    vim.notify(
        "dispatch-kit: Tree-sitter parser '" .. language .. "' is unavailable",
        vim.log.levels.WARN
    )
end

function M.parser(bufnr, language)
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, language)
    if not ok or not parser then
        notify_missing(language)
        return nil
    end
    return parser
end

function M.find_enclosing(bufnr, predicate)
    local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr })
    if not ok then
        return nil
    end
    while node do
        local value = predicate(node)
        if value ~= nil then
            return value
        end
        node = node:parent()
    end
end

function M.field_text(bufnr, node, field_name)
    local fields = node:field(field_name)
    if not fields or not fields[1] then
        return nil
    end
    return vim.treesitter.get_node_text(fields[1], bufnr)
end

function M.enclosing_name(bufnr, language, node_type)
    if not M.parser(bufnr, language) then
        return nil
    end
    return M.find_enclosing(bufnr, function(node)
        if node:type() == node_type then
            return M.field_text(bufnr, node, "name")
        end
    end)
end

return M
