local M = {}

---Configure task families and optional language adapters.
---@param opts? table
function M.setup(opts)
    local config = require("dispatch-kit.config").resolve(opts)
    require("dispatch-kit.runner").setup(config.backend, config.makeprg)
    require("dispatch-kit.registry").setup(config.tasks)
end

return M
