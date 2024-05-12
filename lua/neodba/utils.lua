local M = {}

function M.pp(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

function M.write_file(path, data)
  local fd = vim.loop.fs_open(path, 'a', 438) -- TODO: what is 438
  if fd then
    vim.loop.fs_write(fd, data, 0)
    vim.loop.fs_close(fd)
  else
    print('Failed to write to: ' .. path)
  end
end

return M
